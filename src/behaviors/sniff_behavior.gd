class_name SniffBehavior
extends CreatureBehavior
## Wittern: mit gesenktem Kopf suchend umhergehen. Gute Witterer finden danach
## zielstrebig den nächsten Fruchtbaum, schwache geben auf.

enum { SEARCH, GO, AT_TREE }

var _state := SEARCH
var _skill := 0.5
var _puff := 0.0
var _heading := 0.0
var _tree: FruitTree
var _timer := 0.0

var _limit := 30.0


func _init() -> void:
	id = "sniff"
	label = "wittert"
	ability = "scent"


func utility(s: Dictionary) -> float:
	return brain.weight(id) * (0.1 + skill(s))


func start() -> void:
	_skill = skill()
	_heading = creature.rotation.y
	brain.mover.stop()
	creature.locomotion.head_pitch = -0.4
	creature.locomotion.pose_pitch = -0.15
	_state = SEARCH
	_tree = brain.context.nearest_fruit_tree(creature.global_position, 25.0)
	outcome = "success" if _skill >= 0.5 and _tree != null else "fail"


func update(delta: float) -> bool:
	_puff -= delta
	if _puff <= 0.0:
		_puff = 0.5
		var nose := creature.global_transform * (creature.plan.head_center + Vector3(0.0, creature.plan.body_center_y - creature.plan.head_radius, -creature.plan.head_radius))
		BehaviorEffects.scent_puff(world_parent(), nose)
	match _state:
		SEARCH:
			var dir := Vector3(-sin(_heading + sin(elapsed * 1.7) * 0.9), 0.0, -cos(_heading + sin(elapsed * 1.7) * 0.9))
			creature.desired_velocity = dir * creature.plan.move_speed * 0.3 + brain.mover.separation()
			if elapsed > 5.0:
				if outcome != "success":
					return false
				creature.locomotion.head_pitch = -0.1
				var out := (creature.global_position - _tree.global_position)
				out.y = 0.0
				brain.mover.go(_tree.global_position + out.normalized() * 1.2)
				_limit = elapsed + approach_time(brain.mover.distance_to_goal())
				_state = GO
		GO:
			if approach_done(delta, _limit, 2.0) or brain.mover.distance_to_goal() < 0.8:
				brain.mover.stop()
				creature.locomotion.head_pitch = 0.35
				_timer = 2.0
				_state = AT_TREE
			return not timed_out
		AT_TREE:
			face(_tree.global_position - creature.global_position, delta)
			_timer -= delta
			return _timer > 0.0
	return true
