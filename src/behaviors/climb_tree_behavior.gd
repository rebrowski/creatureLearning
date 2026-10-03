class_name ClimbTreeBehavior
extends CreatureBehavior
## Einen Fruchtbaum hinaufklettern. Gute Kletterer erreichen die Früchte,
## schwache fallen nach kurzer Strecke herunter.
##
## Beim Klettern zeigt die Kreatur mit dem Kopf nach oben (-Z = Welt-oben),
## der Rücken vom Stamm weg (+Y = weg vom Stamm); die Füße greifen um den Stamm.

enum { APPROACH, ATTACH, UP, TOP, DOWN, DROP, DETACH }
const TRUNK_RADIUS := 0.28

var _tree: FruitTree
var _state := APPROACH
var _out := Vector3.FORWARD
var _h := 0.0
var _h0 := 0.0
var _target_h := 1.0
var _speed := 0.5
var _blend := 0.0
var _ground_xform := Transform3D.IDENTITY
var _wait := 0.0
var _moving := false

var _limit := 30.0


func _init() -> void:
	id = "climb_tree"
	label = "klettert auf einen Baum"
	ability = "climb"


func utility(s: Dictionary) -> float:
	var t := brain.context.nearest_fruit_tree(creature.global_position, 16.0)
	if t == null:
		return 0.0
	return brain.weight(id) * (0.1 + skill(s))


func start() -> void:
	_tree = params.get("tree", brain.context.nearest_fruit_tree(creature.global_position, 16.0))
	if _tree == null:
		_state = DETACH
		return
	var p := creature.global_position
	var base := _tree.global_position
	_out = Vector3(p.x - base.x, 0.0, p.z - base.z).normalized()
	if _out.length() < 0.5:
		_out = Vector3.FORWARD
	var approach := base + _out * (TRUNK_RADIUS + creature.plan.body_length * 0.5 + 0.5)
	brain.mover.go(approach)
	_limit = approach_time(brain.mover.distance_to_goal())
	_state = APPROACH


func update(delta: float) -> bool:
	match _state:
		APPROACH:
			if approach_done(delta, _limit):
				_attach()
			return not timed_out
		ATTACH:
			_blend = minf(_blend + delta * 1.8, 1.0)
			_apply()
			if _blend >= 1.0:
				_state = UP
		UP:
			_moving = true
			_h = minf(_h + _speed * delta, _target_h)
			_apply()
			if _h >= _target_h:
				_moving = false
				if outcome == "success":
					_state = TOP
					_wait = float(params.get("top_wait", 3.0))
					var bait = params.get("bait")
					if bait != null and is_instance_valid(bait):
						bait.take(creature)
					creature.locomotion.head_pitch = 0.3
				else:
					_state = DROP
		TOP:
			_wait -= delta
			if _wait <= 0.0:
				_state = DOWN
		DOWN:
			_moving = true
			_h = maxf(_h - _speed * 1.2 * delta, _h0)
			_apply()
			if _h <= _h0:
				_moving = false
				_state = DETACH
		DROP:
			_h = maxf(_h - 4.0 * delta, _h0)
			_apply()
			if _h <= _h0:
				_state = DETACH
		DETACH:
			_blend = maxf(_blend - delta * 1.8, 0.0)
			_apply()
			return _blend > 0.0
	return true


func _attach() -> void:
	var a := skill({"zone": "tree", "wetness": brain.sample_here().get("wetness", 0.0)})
	outcome = decide(a >= 0.45)
	_h0 = creature.plan.body_length * 0.5 + creature.plan.head_radius
	_target_h = maxf(_tree.fruit_height - creature.plan.body_length * 0.3, _h0 + 0.5) if outcome == "success" \
			else clampf(_h0 + 0.3 + a * 2.0, _h0 + 0.3, _tree.fruit_height * 0.5)
	_speed = (0.25 + 1.1 * a) * speed_factor()
	_h = _h0
	_blend = 0.0
	creature.scripted = true
	creature.velocity = Vector3.ZERO
	_ground_xform = creature.global_transform
	creature.locomotion.foot_override = _feet
	Sound.play("climb", creature.global_position, creature)
	_state = ATTACH


func _cling_transform() -> Transform3D:
	var y_axis := _out
	var z_axis := Vector3.DOWN
	var x_axis := y_axis.cross(z_axis).normalized()
	var origin := _tree.global_position + Vector3.UP * _h + _out * (TRUNK_RADIUS + 0.03)
	return Transform3D(Basis(x_axis, y_axis, z_axis), origin)


func _apply() -> void:
	var cling := _cling_transform()
	creature.global_transform = _ground_xform.interpolate_with(cling, _blend)
	creature.velocity = Vector3.UP * (_speed if _moving else 0.0)


## Füße greifen um den Stamm; beim Klettern greifen sie abwechselnd nach.
func _feet(leg: int, hip: Vector3) -> Variant:
	if _blend < 0.5:
		return null
	var axis := Vector3(_tree.global_position.x, hip.y, _tree.global_position.z)
	var radial := Vector3(hip.x - axis.x, 0.0, hip.z - axis.z)
	if radial.length() < 0.01:
		radial = _out
	var foot := axis + radial.normalized() * TRUNK_RADIUS
	if _moving:
		foot.y += sin(elapsed * 9.0 + leg * PI) * 0.08
	return foot


func finish() -> void:
	brain.mover.stop()
	if _blend > 0.0 and _tree != null:
		creature.global_transform = _ground_xform
	creature.locomotion.reset(creature.global_transform)
