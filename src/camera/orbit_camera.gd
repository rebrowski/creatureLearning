class_name OrbitCamera
extends Camera3D
## Einfache Orbit-Kamera für Debug-Szenen, Maus und Touch.
##
##   ein Finger / linke Maustaste ziehen  -> drehen
##   zwei Finger ziehen / rechte Maustaste -> verschieben
##   Pinch / Mausrad                       -> zoomen
## Kurzes Tippen ohne Ziehen meldet `tapped(screen_pos)`.
## Mit `follow` folgt der Drehpunkt einem Node3D.

signal tapped(screen_pos: Vector2)

@export var target := Vector3.ZERO
@export var distance := 14.0
@export var yaw := 0.6
@export var pitch := -0.6
@export var min_distance := 2.0
@export var max_distance := 60.0
@export var rotate_speed := 0.008
@export var pan_speed := 0.0025
var follow: Node3D

var _touches: Dictionary = {}  # index -> Position
var _drag_moved := 0.0
var _last_pinch := 0.0
var _mouse_rotating := false
var _mouse_panning := false


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	if follow != null and is_instance_valid(follow):
		target = target.lerp(follow.global_position, 1.0 - exp(-5.0 * delta))
	_apply()


func _apply() -> void:
	pitch = clampf(pitch, -1.45, -0.05)
	distance = clampf(distance, min_distance, max_distance)
	var offset := Vector3(0.0, 0.0, distance).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	global_position = target + offset
	look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_drag_moved = 0.0
			_last_pinch = _pinch_distance()
		else:
			_touches.erase(event.index)
			if _touches.is_empty() and _drag_moved < 12.0:
				tapped.emit(event.position)
			_last_pinch = _pinch_distance()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		_drag_moved += event.relative.length()
		if _touches.size() == 1:
			_rotate(event.relative)
		elif _touches.size() >= 2:
			var pinch := _pinch_distance()
			if _last_pinch > 0.0:
				distance *= _last_pinch / maxf(pinch, 1.0)
			_last_pinch = pinch
			_pan(event.relative * 0.5)
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


func _rotate(rel: Vector2) -> void:
	yaw -= rel.x * rotate_speed
	pitch -= rel.y * rotate_speed


func _pan(rel: Vector2) -> void:
	follow = null
	var right := global_transform.basis.x
	var fwd := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z).normalized()
	target += (-right * rel.x + fwd * rel.y) * pan_speed * distance


func _pinch_distance() -> float:
	if _touches.size() < 2:
		return 0.0
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1])
