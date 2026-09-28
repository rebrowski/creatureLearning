class_name CarryBehavior
extends CreatureBehavior
## Einen Stein aufheben und woanders ablegen. Starke Träger schaffen schwere
## Steine; schwache zerren vergeblich und geben auf.

enum { APPROACH, LIFT, TUG, CARRY }

var _item: CarryItem
var _state := APPROACH
var _timer := 0.0
var _speed := 1.0
var _item_origin := Vector3.ZERO

var _limit := 30.0


func _init() -> void:
	id = "carry"
	label = "trägt einen Stein"
	ability = "carry"


func utility(s: Dictionary) -> float:
	if _nearest_item(14.0) == null:
		return 0.0
	return brain.weight(id) * (0.1 + skill(s))


func start() -> void:
	_item = _nearest_item(14.0)
	if _item == null:
		return
	_item.claimed_by = creature
	brain.mover.go(_item.global_position)
	_limit = approach_time(brain.mover.distance_to_goal())
	_state = APPROACH


func update(delta: float) -> bool:
	if _item == null or not is_instance_valid(_item):
		return false
	match _state:
		APPROACH:
			if approach_done(delta, _limit, 1.2) or brain.mover.distance_to_goal() < 0.8:
				brain.mover.stop()
				creature.locomotion.pose_pitch = -0.35
				creature.locomotion.head_pitch = -0.3
				_timer = 0.8
				_state = LIFT
			return not timed_out
		LIFT:
			creature.desired_velocity = Vector3.ZERO
			_timer -= delta
			if _timer <= 0.0:
				var a := skill()
				if a >= _item.weight * 0.8:
					outcome = "success"
					_speed = clampf(1.0 - (_item.weight - a * 0.5), 0.3, 1.0)
					creature.locomotion.pose_pitch = -0.05
					creature.locomotion.head_pitch = 0.0
					var r := brain.rng.randf_range(2.0, 5.0)
					var ang := brain.rng.randf_range(0.0, TAU)
					brain.mover.go(brain.home + Vector3(cos(ang) * r, 0.0, sin(ang) * r))
					_state = CARRY
				else:
					outcome = "fail"
					_item_origin = _item.global_position
					_timer = 2.5
					_state = TUG
		TUG:
			creature.desired_velocity = Vector3.ZERO
			_timer -= delta
			creature.locomotion.pose_pitch = -0.3 + sin(elapsed * 10.0) * 0.12
			_item.global_position = _item_origin + Vector3(sin(elapsed * 14.0) * 0.02, 0.0, 0.0)
			if _timer <= 0.0:
				_item.global_position = _item_origin
				return false
		CARRY:
			_item.global_position = _hold_point()
			_item.rotation.y = creature.rotation.y
			return not brain.mover.step(delta, _speed)
	return true


## Kleine Steine im Maul, große auf dem Rücken.
func _hold_point() -> Vector3:
	var plan := creature.plan
	if _item.size < plan.head_radius * 1.6:
		return creature.global_transform * (plan.head_center + Vector3(0.0, plan.body_center_y - _item.size * 0.4, -plan.head_radius * 0.9))
	return creature.global_transform * Vector3(0.0, plan.body_center_y + plan.half_height * 0.85, 0.0)


func _nearest_item(max_distance: float) -> CarryItem:
	var best: CarryItem = null
	var best_d := max_distance
	for n in creature.get_tree().get_nodes_in_group("carry_item"):
		var item := n as CarryItem
		if item == null or not item.is_free():
			continue
		var d := item.global_position.distance_to(creature.global_position)
		if d < best_d:
			best_d = d
			best = item
	return best


func finish() -> void:
	brain.mover.stop()
	if _item != null and is_instance_valid(_item):
		if _state == CARRY:
			var p := creature.global_transform * Vector3(0.0, 0.0, -(creature.plan.body_length * 0.5 + _item.size))
			var y := creature.ground_height_at(p)
			_item.global_position = Vector3(p.x, y if not is_nan(y) else creature.global_position.y, p.z)
		_item.claimed_by = null
