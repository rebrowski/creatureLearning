class_name SeekBehavior
extends CreatureBehavior
## Eine ausgelegte Beere (Köder auf dem Boden) suchen. Tagsüber findet sie fast
## jeder (Witterung hilft), in der Dunkelheit zählt die Nachtsicht: Wer schlecht
## sieht, irrt suchend umher und gibt auf. Nur erzwungen (params "bait").

enum { SEARCH, GO }

var _bait: Bait
var _target := Vector3.ZERO
var _state := SEARCH
var _legs := 0
var _limit := 20.0


func _init() -> void:
	id = "seek"
	label = "sucht eine Beere"
	ability = "night_vision"


func utility(_s: Dictionary) -> float:
	return 0.0  # nur als Reaktion auf einen Köder


func start() -> void:
	_bait = params.get("bait")
	_target = _bait.global_position if _bait != null else creature.global_position
	var s := brain.sample_here()
	var darkness := 1.0 - float(s.get("light", 1.0))
	var day := 0.6 + 0.4 * creature.abilities.in_context("scent", s)
	var night := creature.abilities.in_context("night_vision", s)
	var skill_ := lerpf(day, night, clampf(darkness * 1.4, 0.0, 1.0))
	outcome = decide(skill_ >= 0.4)
	_legs = 0
	if outcome == "success":
		_go(_target)
		_state = GO
	else:
		label = "sucht im Dunkeln" if darkness > 0.5 else "sucht eine Beere"
		creature.behavior_label = label
		creature.locomotion.head_pitch = -0.35
		_search_leg()
		_state = SEARCH


func _go(p: Vector3) -> void:
	brain.mover.go(p)
	_limit = elapsed + approach_time(brain.mover.distance_to_goal())


## Irrt in der Nähe des Köders umher, ohne ihn zu finden.
func _search_leg() -> void:
	var a := brain.rng.randf_range(0.0, TAU)
	var r := brain.rng.randf_range(2.5, 5.0)
	_go(_target + Vector3(cos(a) * r, 0.0, sin(a) * r))
	_limit = elapsed + 7.0
	_legs += 1


func update(delta: float) -> bool:
	match _state:
		GO:
			if brain.mover.distance_to_goal() < 0.7 or approach_done(delta, _limit, 1.2):
				brain.mover.stop()
				if _bait != null and is_instance_valid(_bait):
					_bait.take(creature)
				return false
			return not timed_out
		SEARCH:
			if brain.mover.step(delta) or elapsed >= _limit:
				if _legs >= 3:
					return false
				_search_leg()
	return true


func finish() -> void:
	brain.mover.stop()
