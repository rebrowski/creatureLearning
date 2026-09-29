extends GutTest
## Touch-Gesten der Orbit-Kamera.

var cam: OrbitCamera


func before_each() -> void:
	cam = OrbitCamera.new()
	add_child_autofree(cam)


func _touch(i: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = pos
	e.pressed = pressed
	cam._unhandled_input(e)


func _drag(i: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = pos
	e.relative = pos - (cam._touches.get(i, pos) as Vector2)
	cam._unhandled_input(e)


func test_one_finger_rotates() -> void:
	var p0 := cam.pitch
	_touch(0, Vector2(100, 100), true)
	for k in 5:
		_drag(0, Vector2(100, 100 + (k + 1) * 10))
	_touch(0, Vector2(100, 150), false)
	assert_ne(cam.pitch, p0)


func test_lifting_one_finger_after_pan_does_not_tilt() -> void:
	cam._apply()
	var p0 := cam.pitch
	var y0 := cam.yaw
	_touch(0, Vector2(100, 300), true)
	_touch(1, Vector2(300, 300), true)
	for k in 5:
		_drag(0, Vector2(100, 300 - (k + 1) * 20))
		_drag(1, Vector2(300, 300 - (k + 1) * 20))
	assert_almost_eq(cam.pitch, p0, 0.001, "Zwei-Finger-Ziehen verschiebt nur")
	var target := cam.target
	assert_ne(target, Vector3.ZERO, "verschoben")
	_touch(0, Vector2(100, 200), false)
	# der verbleibende Finger bewegt sich beim Abheben noch
	for k in 5:
		_drag(1, Vector2(300, 200 - (k + 1) * 30))
	_touch(1, Vector2(300, 50), false)
	assert_almost_eq(cam.pitch, p0, 0.001, "kein Kippen am Ende der Geste")
	assert_almost_eq(cam.yaw, y0, 0.001)


func test_jumps_are_ignored_and_pitch_is_limited() -> void:
	_touch(0, Vector2(100, 100), true)
	_drag(0, Vector2(100, 700))
	assert_almost_eq(cam.pitch, -0.6, 0.001, "Sprung ignoriert")
	for k in 60:
		_drag(0, Vector2(100, 100 - (k + 1) * 10))
	cam._apply()
	assert_gte(cam.pitch, cam.min_pitch)
	assert_lte(cam.pitch, cam.max_pitch)


func test_tap_only_for_single_finger() -> void:
	watch_signals(cam)
	_touch(0, Vector2(10, 10), true)
	_touch(0, Vector2(10, 10), false)
	assert_signal_emit_count(cam, "tapped", 1)
	_touch(0, Vector2(10, 10), true)
	_touch(1, Vector2(50, 10), true)
	_touch(1, Vector2(50, 10), false)
	_touch(0, Vector2(10, 10), false)
	assert_signal_emit_count(cam, "tapped", 1, "Zwei-Finger-Tipp wählt nichts aus")
