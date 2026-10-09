class_name CreatureBehavior
extends RefCounted
## Basisklasse für sichtbares Verhalten. Das Gehirn (BehaviorBrain) fragt alle
## Verhalten nach ihrem Nutzen, startet das beste und ruft update() bis es
## false liefert oder die maximale Dauer überschritten ist.
##
## Unterklassen setzen `id`, `label` (Anzeige) und `ability` (zugehörige Fähigkeit)
## und überschreiben utility(), start(), update(), finish().

var id := ""
var label := ""
var ability := ""
var brain: BehaviorBrain
var creature: Creature
## Laufzeit seit start()
var elapsed := 0.0
## Ergebnis für Beobachtung/Tests: "", "success", "fail"
var outcome := ""
## Anmarsch aufgegeben (Ziel nicht erreichbar).
var timed_out := false
## Vorgaben beim Erzwingen (Rivalen-Versuche, Tests): "forced_outcome" ("success"/"fail"),
## "speed" (Tempo-Faktor) und verhaltensspezifische Ziele (z. B. "tree",
## "crossing"). Leer bei freier Wahl.
var params: Dictionary = {}


func setup(p_brain: BehaviorBrain) -> void:
	brain = p_brain
	creature = p_brain.creature


## Nutzen in der aktuellen Situation (0 = nicht möglich). `sample` = WorldContext.sample().
func utility(_sample: Dictionary) -> float:
	return 0.0


func start() -> void:
	pass


## true = weiterlaufen
func update(_delta: float) -> bool:
	return false


func finish() -> void:
	pass


# --- Hilfen -------------------------------------------------------------------

## Fähigkeit im aktuellen Kontext an der Position der Kreatur (0..1).
func skill(sample := {}) -> float:
	if ability == "" or creature.abilities == null:
		return 0.5
	if sample.is_empty():
		sample = brain.sample_here()
	return creature.abilities.in_context(ability, sample)


func world_parent() -> Node:
	return creature.get_parent()


## Kreatur in Richtung `dir` (horizontal) drehen, weich.
func face(dir: Vector3, delta: float, rate := 4.0) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	creature.rotation.y = lerp_angle(creature.rotation.y, target_yaw, 1.0 - exp(-rate * delta))


## Zeitlimit für einen Anmarsch über `distance` Meter (langsame Arten brauchen länger).
func approach_time(distance: float) -> float:
	return clampf(8.0 + distance / maxf(creature.plan.move_speed, 0.1) * 1.8, 10.0, 80.0)


## Anmarsch auswerten: true = angekommen (oder nah genug, als die Zeit ablief).
## Setzt `timed_out`, wenn aufgegeben werden soll.
func approach_done(delta: float, limit: float, near := 2.5) -> bool:
	if brain.mover.step(delta, speed_factor()):
		return true
	if elapsed >= limit:
		if brain.mover.distance_to_goal() < near:
			brain.mover.stop()
			return true
		timed_out = true
	return false


## Tempo-Faktor aus params "speed" (Aufgaben laufen zügiger ab), sonst 1.
func speed_factor() -> float:
	return float(params.get("speed", 1.0))


## Ergebnis: vorgegeben (Aufgabe) oder aus dem Können.
func decide(ok_by_skill: bool) -> String:
	var forced := str(params.get("forced_outcome", ""))
	if forced != "":
		return forced
	return "success" if ok_by_skill else "fail"


func forward() -> Vector3:
	return -creature.global_transform.basis.z
