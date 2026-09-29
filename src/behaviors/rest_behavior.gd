class_name RestBehavior
extends CreatureBehavior
## Ruhen: hinlegen (Beine eingeknickt). Nachts ruhen vor allem Tiere mit
## schlechter Nachtsicht – gute Nachtseher bleiben aktiv.

var _duration := 10.0


func _init() -> void:
	id = "rest"
	label = "ruht"
	ability = "night_vision"


func utility(s: Dictionary) -> float:
	var darkness := 1.0 - float(s.get("light", 1.0))
	var nv := creature.abilities.value("night_vision") if creature.abilities else 0.5
	return brain.weight(id) * (0.05 + darkness * (1.0 - nv) * 2.5)


func start() -> void:
	brain.mover.stop()
	_duration = brain.rng.randf_range(10.0, 20.0)
	var plan := creature.plan
	creature.locomotion.pose_height = -plan.hip_height * 0.5 if plan.leg_count > 0 else -0.03
	creature.locomotion.head_pitch = -0.25
	creature.locomotion.pose_pitch = -0.05
	var darkness := 1.0 - float(brain.sample_here().get("light", 1.0))
	label = "schläft" if darkness > 0.5 else "ruht"
	creature.behavior_label = label


func update(_delta: float) -> bool:
	creature.desired_velocity = Vector3.ZERO
	return elapsed < _duration
