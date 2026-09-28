class_name DisplayBehavior
extends CreatureBehavior
## Drohen / Gefahr verscheuchen: aufrichten, aufplustern, stampfen – vor allem,
## wenn ein anderes Tier nahe ist. Gute Verscheucher wirken größer.

const DURATION := 3.0

var _skill := 0.5
var _target: Creature


func _init() -> void:
	id = "display"
	label = "droht"
	ability = "scare"


func utility(s: Dictionary) -> float:
	var near := brain.neighbor_within(3.5)
	var a := skill(s)
	return brain.weight(id) * (0.03 + a * 0.3 + (a * 0.4 if near != null else 0.0))


func start() -> void:
	_skill = skill()
	outcome = "success" if _skill >= 0.5 else "fail"
	_target = brain.neighbor_within(3.5)
	brain.mover.stop()


func update(delta: float) -> bool:
	creature.desired_velocity = Vector3.ZERO
	if _target != null and is_instance_valid(_target):
		face(_target.global_position - creature.global_position, delta)
	var lift := 0.45 if creature.plan.leg_count >= 4 else 0.2
	creature.locomotion.pose_pitch = lift * (0.4 + _skill)
	creature.locomotion.pose_scale = 1.0 + 0.3 * _skill
	creature.locomotion.pose_height = maxf(0.0, sin(elapsed * 12.0)) * 0.06 * _skill
	return elapsed < DURATION
