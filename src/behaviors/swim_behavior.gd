class_name SwimBehavior
extends CreatureBehavior
## Den Bach durchqueren. Langbeinige Tiere waten über den Grund, andere
## schwimmen mit paddelnden Beinen – je schwächer, desto tiefer liegen sie im
## Wasser und desto langsamer sind sie. Schwache Schwimmer kehren auf halbem
## Weg um: Nicht-Schwimmer zögern am Ufer und weichen zurück, schwache
## Schwimmer strampeln, treiben ab und verlieren, was sie tragen.

enum { APPROACH, CROSS, HESITATE, BACK }

## Unter dieser Schwimmfähigkeit traut sich eine Kreatur nicht ins Wasser.
const HESITATE_SKILL := 0.12
const HESITATE_TIME := 2.2

var _state := APPROACH
var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _t := 0.0
var _turn_at := 1.0
var _speed := 0.5
var _wade := false
var _skill := 0.5
var _ripple := 0.0
## "cross" | "hesitate" (zögert am Ufer) | "struggle" (strampelt, gibt auf)
var _mode := "cross"
var _pause := 0.0
var _drift := 0.0
var _flow := Vector2(1, 0)

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
	var c: Vector2 = params.get("crossing", info.closest)
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
				_t = _turn_at
				_state = HESITATE if _mode == "hesitate" else BACK
				_pause = 0.0
				if _mode == "struggle":
					_lose_item()
			return _t < 1.0
		HESITATE:
			# steht am Wasser, schaut hinein, tastet vor und zurück
			_pause += delta
			creature.locomotion.head_pitch = 0.45
			creature.locomotion.pose_pitch = 0.12
			var wobble := sin(_pause * 3.0) * 0.04
			_t = maxf(0.0, _turn_at - 0.03 + wobble)
			_place(delta, 1.0, false)
			if _pause > HESITATE_TIME:
				creature.locomotion.head_pitch = 0.0
				_state = BACK
			return true
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
	outcome = decide(_wade or _skill >= 0.3)
	_mode = "cross"
	if outcome == "fail":
		# Nicht-Schwimmer trauen sich nicht hinein, schwache Schwimmer geben mittendrin auf
		_mode = "hesitate" if _skill < HESITATE_SKILL and not _wade else "struggle"
	_turn_at = 1.0
	if _mode == "hesitate":
		_turn_at = _water_edge_t() + 0.04
	elif _mode == "struggle":
		_turn_at = 0.3 + _skill * 0.6
	_speed = plan.move_speed * (0.7 if _wade else 0.35 + 0.55 * _skill)
	if _mode == "hesitate":
		_speed = plan.move_speed * 0.4
	_speed *= speed_factor()
	label = "watet durch den Bach" if _wade else ("zögert am Ufer" if _mode == "hesitate" else ("strampelt im Wasser" if _mode == "struggle" else "schwimmt"))
	creature.behavior_label = label
	_t = 0.0
	_drift = 0.0
	_flow = l.stream_direction(mid.x, mid.z)
	creature.scripted = true
	if _mode != "hesitate":
		Sound.play("splash", _a.lerp(_b, 0.3), creature)
	if not _wade and _mode != "hesitate":
		creature.locomotion.foot_override = _paddle
		creature.locomotion.pose_pitch = 0.1 + (1.0 - _skill) * 0.25  # schwache Schwimmer: Kopf hoch, Hinterteil tief
	_state = CROSS


## Anteil des Weges (0..1), an dem das Wasser beginnt.
func _water_edge_t() -> float:
	var l := brain.layout()
	for i in 40:
		var t := i / 40.0
		var p := _a.lerp(_b, t)
		if l.zone_at(p.x, p.z) == "water":
			return t
	return 0.2


func _place(delta: float, direction: float, turn := true) -> void:
	var l := brain.layout()
	var p := _a.lerp(_b, clampf(_t, 0.0, 1.0))
	var in_water := l.zone_at(p.x, p.z) == "water"
	if _mode == "struggle" and in_water:
		# wird von der Strömung abgetrieben
		_drift = minf(_drift + delta * 0.35 * (1.0 - _skill), 1.6)
	elif not in_water:
		_drift = move_toward(_drift, 0.0, delta * 0.5)
	p += Vector3(_flow.x, 0.0, _flow.y) * _drift
	var ground := creature.ground_height_at(Vector3(p.x, p.y + 1.0, p.z))
	if is_nan(ground):
		ground = l.height_at(p.x, p.z)
	var y := ground
	if not _wade and in_water:
		var weak := 1.0 - _skill
		var submerge := creature.plan.body_center_y * (0.6 + weak * 0.3)
		var bob := sin(elapsed * (5.0 + weak * 4.0)) * (0.03 + 0.07 * weak if _mode == "struggle" else 0.04 * weak)
		y = maxf(ground, l.water_level_at(p.x, p.z) - submerge + bob)
	p.y = y
	var bait = params.get("bait")
	if bait != null and is_instance_valid(bait) and Vector2(p.x - bait.global_position.x, p.z - bait.global_position.z).length() < 0.6:
		bait.take(creature)
	var dir := (_b - _a).normalized() * direction
	creature.velocity = dir * _speed
	creature.global_position = p
	if turn:
		face(dir, delta)
	_ripple -= delta
	if in_water and _ripple <= 0.0:
		_ripple = 0.7 if _wade else (0.2 if _mode == "struggle" else 0.45)
		var wl := l.water_level_at(p.x, p.z)
		BehaviorEffects.ring(world_parent(), Vector3(p.x, wl + 0.02, p.z), 0.6 + (1.0 - _skill) * 0.8, Color(0.8, 0.9, 1.0, 0.5), 1.2)


## Schwacher Schwimmer lässt los: der getragene Gegenstand treibt davon.
func _lose_item() -> void:
	var item := creature.held_item
	if item == null or not is_instance_valid(item):
		return
	creature.held_item = null
	Sound.play("splash", item.global_position, creature)
	BehaviorEffects.float_away(item, brain.layout(), _flow, 4.0)


func _paddle(leg: int, _hip: Vector3) -> Variant:
	# Hüfte aus der Ruhelage (ohne Körperneigung) – sonst schaukelt sich die Neigung auf
	var hip: Vector3 = creature.global_transform * creature.rig.global_rest[creature.rig.upper[leg]]
	var phi := elapsed * 7.0 * (0.5 + _skill) * (1.6 if _mode == "struggle" else 1.0) + leg * PI * 0.5
	var r := creature.plan.leg_reach() * 0.35
	return hip + forward() * cos(phi) * r + Vector3.DOWN * (r * 0.8 + sin(phi) * r * 0.5)


func finish() -> void:
	brain.mover.stop()
	creature.velocity = Vector3.ZERO
	creature.locomotion.reset(creature.global_transform)
