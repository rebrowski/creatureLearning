class_name SwimBehavior
extends CreatureBehavior
## Den Bach durchqueren. Langbeinige Tiere waten über den Grund, andere
## schwimmen mit paddelnden Beinen – je schwächer, desto tiefer liegen sie im
## Wasser und desto langsamer sind sie. Schwache Schwimmer kehren auf halbem
## Weg um.

enum { APPROACH, CROSS, BACK }

var _state := APPROACH
var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _t := 0.0
var _turn_at := 1.0
var _speed := 0.5
var _wade := false
var _skill := 0.5
var _ripple := 0.0

var _limit := 30.0


func _init() -> void:
	id = "swim"
	label = "geht ins Wasser"
	ability = "swim"


func utility(s: Dictionary) -> float:
	var p := creature.global_position
	var l := brain.layout()
	if l.stream_points.size() < 2 or l.stream_info(p.x, p.z).distance > 18.0:
		return 0.0
	return brain.weight(id) * (0.1 + skill(s))


func start() -> void:
	var l := brain.layout()
	var p := creature.global_position
	var info := l.stream_info(p.x, p.z)
	var c: Vector2 = info.closest
	var side := Vector2(p.x - c.x, p.z - c.y).normalized()
	if side.length() < 0.5:
		side = Vector2(0, 1)
	var off := l.stream_width * 0.5 + l.stream_bank * 0.5 + 0.3
	var a2 := c + side * off
	var b2 := c - side * off
	_a = Vector3(a2.x, l.height_at(a2.x, a2.y), a2.y)
	_b = Vector3(b2.x, l.height_at(b2.x, b2.y), b2.y)
	brain.mover.go(_a)
	_limit = approach_time(brain.mover.distance_to_goal())
	_state = APPROACH


func update(delta: float) -> bool:
	match _state:
		APPROACH:
			if approach_done(delta, _limit):
				_enter()
			return not timed_out
		CROSS:
			_t += delta * _speed / maxf(_a.distance_to(_b), 0.1)
			_place(delta, 1.0)
			if outcome == "fail" and _t >= _turn_at:
				_state = BACK
			return _t < 1.0
		BACK:
			_t -= delta * _speed / maxf(_a.distance_to(_b), 0.1)
			_place(delta, -1.0)
			return _t > 0.0
	return true


func _enter() -> void:
	var l := brain.layout()
	var mid := _a.lerp(_b, 0.5)
	var depth := l.water_level_at(mid.x, mid.z) - l.height_at(mid.x, mid.z)
	var plan := creature.plan
	_wade = plan.leg_count > 0 and plan.leg_reach() * 0.85 > depth + 0.05
	_skill = skill(brain.context.sample(mid))
	outcome = "success" if _wade or _skill >= 0.3 else "fail"
	_turn_at = 1.0 if outcome == "success" else 0.3 + _skill
	_speed = plan.move_speed * (0.7 if _wade else 0.35 + 0.55 * _skill)
	label = "watet durch den Bach" if _wade else "schwimmt"
	creature.behavior_label = label
	_t = 0.0
	creature.scripted = true
	if not _wade:
		creature.locomotion.foot_override = _paddle
		creature.locomotion.pose_pitch = 0.1 + (1.0 - _skill) * 0.25  # schwache Schwimmer: Kopf hoch, Hinterteil tief
	_state = CROSS


func _place(delta: float, direction: float) -> void:
	var l := brain.layout()
	var p := _a.lerp(_b, clampf(_t, 0.0, 1.0))
	var ground := creature.ground_height_at(Vector3(p.x, p.y + 1.0, p.z))
	if is_nan(ground):
		ground = l.height_at(p.x, p.z)
	var y := ground
	var in_water := l.zone_at(p.x, p.z) == "water"
	if not _wade:
		var submerge := creature.plan.body_center_y * (0.7 + (1.0 - _skill) * 0.4)
		var bob := sin(elapsed * 5.0) * 0.04 * (1.0 - _skill)
		y = maxf(ground, l.water_level_at(p.x, p.z) - submerge + bob)
	p.y = y
	var dir := (_b - _a).normalized() * direction
	creature.velocity = dir * _speed
	creature.global_position = p
	face(dir, delta)
	_ripple -= delta
	if in_water and _ripple <= 0.0:
		_ripple = 0.7 if _wade else 0.45
		var wl := l.water_level_at(p.x, p.z)
		BehaviorEffects.ring(world_parent(), Vector3(p.x, wl + 0.02, p.z), 0.6 + (1.0 - _skill) * 0.8, Color(0.8, 0.9, 1.0, 0.5), 1.2)


func _paddle(leg: int, hip: Vector3) -> Variant:
	var phi := elapsed * 7.0 * (0.5 + _skill) + leg * PI * 0.5
	var r := creature.plan.leg_reach() * 0.35
	return hip + forward() * cos(phi) * r + Vector3.DOWN * (r * 0.8 + sin(phi) * r * 0.5)


func finish() -> void:
	brain.mover.stop()
	creature.velocity = Vector3.ZERO
	creature.locomotion.reset(creature.global_transform)
