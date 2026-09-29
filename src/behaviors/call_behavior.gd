class_name CallBehavior
extends CreatureBehavior
## Rufen / Lärm machen: Kopf hoch, sichtbare Schallwellen – je lauter, desto
## größer. Regen dämpft (Kontext).

const CALLS := 3

var _skill := 0.5
var _timer := 0.0
var _count := 0


func _init() -> void:
	id = "call"
	label = "ruft"
	ability = "noise"


func utility(s: Dictionary) -> float:
	var bonus := 0.1 if brain.neighbor_within(6.0) != null else 0.0
	return brain.weight(id) * (0.05 + skill(s) * 0.8 + bonus)


func start() -> void:
	_skill = skill()
	outcome = decide(_skill >= 0.45)
	brain.mover.stop()
	creature.locomotion.head_pitch = 0.45
	creature.locomotion.pose_pitch = 0.15
	_timer = 0.5
	_count = 0


func update(delta: float) -> bool:
	creature.desired_velocity = Vector3.ZERO
	_timer -= delta
	creature.locomotion.pose_height = 0.04 if _timer > 0.9 else 0.0
	if _timer <= 0.0 and _count < CALLS:
		_count += 1
		_timer = 1.2
		var head := creature.global_transform * (creature.plan.head_center + Vector3(0.0, creature.plan.body_center_y, 0.0))
		BehaviorEffects.ring(world_parent(), head, 0.6 + 4.5 * _skill, Color(1.0, 1.0, 0.8, 0.7), 1.0)
		if _skill > 0.2:
			Sound.play("call", head)
	return _count < CALLS or _timer > 0.0
