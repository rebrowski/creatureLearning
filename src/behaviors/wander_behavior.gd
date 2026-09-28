class_name WanderBehavior
extends CreatureBehavior
## Umherstreifen: zufälliges Ziel im Umkreis, danach kurz stehen bleiben.

var _arrived := false
var _idle := 0.0


func _init() -> void:
	id = "wander"
	label = "streift umher"


func utility(_s: Dictionary) -> float:
	return brain.weight(id)


func start() -> void:
	var a := brain.rng.randf_range(0.0, TAU)
	var r := sqrt(brain.rng.randf()) * brain.roam_radius
	brain.mover.go(brain.home + Vector3(cos(a) * r, 0.0, sin(a) * r))
	_arrived = false
	_idle = brain.rng.randf_range(1.0, 4.0)


func update(delta: float) -> bool:
	if not _arrived:
		_arrived = brain.mover.step(delta)
		return true
	_idle -= delta
	creature.desired_velocity = brain.mover.separation() * 0.5
	return _idle > 0.0
