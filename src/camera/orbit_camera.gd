class_name OrbitCamera
extends Camera3D
## Einfache Orbit-Kamera für Debug-Szenen, Maus und Touch.
##
##   ein Finger / linke Maustaste ziehen  -> drehen
##   zwei Finger ziehen / rechte Maustaste -> verschieben (Schwerpunkt der Finger)
##   zwei Finger drehen / Q, E             -> um die Hochachse drehen
##   Pinch / Mausrad                       -> zoomen
## Kurzes Tippen ohne Ziehen meldet `tapped(screen_pos)`.
## Mit `follow` folgt der Drehpunkt einem Node3D. Optional: `bounds` (Rechteck in
## x/z, in dem der Drehpunkt bleibt) und `ground_height` (Callable x, z -> Höhe),
## damit der Drehpunkt dem Gelände folgt.

signal tapped(screen_pos: Vector2)

@export var target := Vector3.ZERO
@export var distance := 14.0
@export var yaw := 0.6
@export var pitch := -0.6
@export var min_distance := 2.0
@export var max_distance := 60.0
@export var rotate_speed := 0.008
@export var pan_speed := 0.0025
## Steilster und flachster Blickwinkel (rad). Flacher als MIN_PITCH sähe man
## nur noch den Boden vom Rand her.
@export var min_pitch := -1.45
@export var max_pitch := -0.2
## Größere Sprünge eines Fingers pro Ereignis gelten als Fehlmessung (Pixel).
const MAX_STEP := 150.0
## Rechteck (x, z) für den Drehpunkt; Größe 0 = unbegrenzt.
@export var bounds := Rect2()
var follow: Node3D
var ground_height: Callable

var _touches: Dictionary = {}  # index -> Position
var _drag_moved := 0.0
var _last_pinch := 0.0
var _last_twist := 0.0
var _last_center := Vector2.ZERO
## größte Fingerzahl der laufenden Geste (1 = reines Ein-Finger-Ziehen)
var _gesture_fingers := 0
var _mouse_panning := false


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	if follow != null and is_instance_valid(follow):
		target = target.lerp(follow.global_position, 1.0 - exp(-5.0 * delta))
	_apply()


func _apply() -> void:
	if bounds.size != Vector2.ZERO:
		target.x = clampf(target.x, bounds.position.x, bounds.end.x)
		target.z = clampf(target.z, bounds.position.y, bounds.end.y)
	if ground_height.is_valid() and follow == null:
		var h: float = ground_height.call(target.x, target.z)
		if not is_nan(h):
			target.y = lerpf(target.y, h, 0.2)
	pitch = clampf(pitch, min_pitch, max_pitch)
	distance = clampf(distance, min_distance, max_distance)
	var offset := Vector3(0.0, 0.0, distance).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	global_position = target + offset
	look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touches.is_empty():
				_drag_moved = 0.0
				_gesture_fingers = 0
			_touches[event.index] = event.position
			_gesture_fingers = maxi(_gesture_fingers, _touches.size())
		else:
			_touches.erase(event.index)
			if _touches.is_empty() and _drag_moved < 12.0 and _gesture_fingers == 1:
				tapped.emit(event.position)
		_reset_multi()
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return  # Drag ohne bekanntes Aufsetzen (z. B. nach Fokuswechsel) ignorieren
		var prev: Vector2 = _touches[event.index]
		_touches[event.index] = event.position
		# eigene Differenz statt event.relative: nach dem Abheben eines Fingers
		# liefern manche Browser (iOS) einen Sprung
		var rel: Vector2 = event.position - prev
		if rel.length() > MAX_STEP:
			return
		_drag_moved += rel.length()
		if _touches.size() == 1:
			# nach einer Zwei-Finger-Geste nicht drehen, bis alle Finger oben sind –
			# sonst kippt der letzte Finger beim Loslassen die Ansicht
			if _gesture_fingers == 1:
				_rotate(rel)
		elif _touches.size() >= 2:
			var pinch := _pinch_distance()
			if _last_pinch > 0.0 and pinch > 1.0:
				distance *= _last_pinch / pinch
			_last_pinch = pinch
			var twist := _twist_angle()
			yaw -= wrapf(twist - _last_twist, -PI, PI)
			_last_twist = twist
			var center := _centroid()
			_pan(center - _last_center)
			_last_center = center
	elif event is InputEventMouseButton:
		# Touch-Emulation liefert Maus-Links bereits als Touch; hier nur Rad/rechts.
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				distance *= 0.9
			MOUSE_BUTTON_WHEEL_DOWN:
				distance *= 1.1
			MOUSE_BUTTON_RIGHT:
				_mouse_panning = event.pressed
	elif event is InputEventMouseMotion and _mouse_panning:
		_pan(event.relative)
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q:
				yaw += 0.15
			KEY_E:
				yaw -= 0.15


func _rotate(rel: Vector2) -> void:
	yaw -= rel.x * rotate_speed
	pitch -= rel.y * rotate_speed


func _pan(rel: Vector2) -> void:
	follow = null
	var right := global_transform.basis.x
	var fwd := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z).normalized()
	target += (-right * rel.x + fwd * rel.y) * pan_speed * distance


## Bezugswerte der Mehrfinger-Geste neu setzen (bei jedem Aufsetzen/Abheben).
func _reset_multi() -> void:
	_last_pinch = _pinch_distance()
	_last_twist = _twist_angle()
	_last_center = _centroid()


func _centroid() -> Vector2:
	if _touches.is_empty():
		return Vector2.ZERO
	var c := Vector2.ZERO
	for p in _touches.values():
		c += p
	return c / _touches.size()


func _twist_angle() -> float:
	if _touches.size() < 2:
		return 0.0
	var pts := _touches.values()
	return ((pts[1] as Vector2) - (pts[0] as Vector2)).angle()


func _pinch_distance() -> float:
	if _touches.size() < 2:
		return 0.0
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1])
