class_name WanderBrain
extends RefCounted
## Platzhalter-Verhalten bis M4: zufällige Ziele in einem Rechteck anlaufen,
## dazwischen kurz stehen bleiben. Reproduzierbar über den Seed.

var area: Rect2
var creature: Creature
var target := Vector3.ZERO
var _idle := 0.0
var _rng := RandomNumberGenerator.new()


func _init(p_creature: Creature, p_area: Rect2, seed_value: int) -> void:
	creature = p_creature
	area = p_area
	_rng.seed = seed_value
	_idle = _rng.randf_range(0.0, 2.0)
	_pick_target()


func update(delta: float) -> void:
	if _idle > 0.0:
		_idle -= delta
		creature.desired_velocity = Vector3.ZERO
		return
	var to_target := target - creature.global_position
	to_target.y = 0.0
	if to_target.length() < 0.4:
		_idle = _rng.randf_range(0.5, 3.0)
		_pick_target()
		return
	creature.desired_velocity = to_target.normalized() * creature.plan.move_speed


func _pick_target() -> void:
	target = Vector3(_rng.randf_range(area.position.x, area.end.x), 0.0, _rng.randf_range(area.position.y, area.end.y))
