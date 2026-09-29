class_name ClimbRockBehavior
extends CreatureBehavior
## Auf einen Felsen klettern. Gute Kletterer erreichen die Spitze und sitzen
## dort; schwache rutschen auf halber Höhe ab. Glatte (nicht „climbable“)
## Felsen verlangen mehr Können.

enum { APPROACH, UP, TOP, DOWN, SLIDE }

var _rock: Dictionary
var _state := APPROACH
var _t := 0.0
var _max_t := 1.0
var _speed := 0.3
var _start := Vector3.ZERO
var _top := Vector3.ZERO
var _wait := 0.0

var _limit := 30.0


func _init() -> void:
	id = "climb_rock"
	label = "klettert auf einen Felsen"
	ability = "climb"


func utility(s: Dictionary) -> float:
	var p := creature.global_position
	var rock := brain.layout().nearest_rock(p.x, p.z, 14.0)
	if rock.is_empty():
		return 0.0
	return brain.weight(id) * (0.15 + skill(s)) * (1.2 if rock.climbable else 0.8)


func start() -> void:
	var p := creature.global_position
	_rock = brain.layout().nearest_rock(p.x, p.z, 14.0)
	if _rock.is_empty():
		_state = SLIDE
		_t = 0.0
		return
	var dir := Vector2(p.x - _rock.pos.x, p.z - _rock.pos.y).normalized()
	var approach: Vector2 = _rock.pos + dir * (_rock.size + 0.7)
	brain.mover.go(Vector3(approach.x, p.y, approach.y))
	_limit = approach_time(brain.mover.distance_to_goal())
	_state = APPROACH


func update(delta: float) -> bool:
	match _state:
		APPROACH:
			if approach_done(delta, _limit):
				_begin_climb()
			return not timed_out
		UP:
			_t = minf(_t + delta * _speed, _max_t)
			_place(delta, 1.0)
			if _t >= _max_t:
				if outcome == "success":
					_state = TOP
					_wait = brain.rng.randf_range(3.0, 6.0)
					creature.locomotion.pose_height = -0.05
				else:
					_state = SLIDE
		TOP:
			_wait -= delta
			creature.velocity = Vector3.ZERO
			creature.locomotion.head_pitch = sin(elapsed * 1.5) * 0.25
			if _wait <= 0.0:
				_state = DOWN
		DOWN:
			_t -= delta * _speed * 1.3
			_place(delta, -1.0)
			return _t > 0.0
		SLIDE:
			_t -= delta * 1.1
			_place(delta, -1.0, false)
			return _t > 0.0
	return true


func _begin_climb() -> void:
	var a := skill({"zone": "rock", "wetness": brain.sample_here().get("wetness", 0.0)})
	var threshold := 0.35 if _rock.climbable else 0.55
	outcome = decide(a >= threshold)
	_max_t = 1.0 if outcome == "success" else clampf(a / threshold, 0.15, 0.9) * 0.7
	_speed = 0.12 + 0.4 * a
	_start = creature.global_position
	_top = Vector3(_rock.pos.x, _start.y, _rock.pos.y)
	_t = 0.0
	creature.scripted = true
	_state = UP


func _place(delta: float, direction: float, turn := true) -> void:
	var p := _start.lerp(_top, clampf(_t, 0.0, 1.0))
	var y := creature.ground_height_at(Vector3(p.x, creature.global_position.y, p.z))
	if not is_nan(y):
		p.y = y
	var dir := (_top - _start).normalized() * direction
	creature.velocity = dir * _speed * _start.distance_to(_top)
	creature.global_position = p
	if turn:
		face(dir, delta)


func finish() -> void:
	brain.mover.stop()
	creature.velocity = Vector3.ZERO
