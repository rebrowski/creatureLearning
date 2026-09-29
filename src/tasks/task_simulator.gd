class_name TaskSimulator
extends RefCounted
## Rechnet aus, wie eine Aufgabe mit einer Rollenbesetzung ausgeht.
##
## Rollenwert = gewichteter Mittelwert der Fähigkeiten im Kontext der Aufgabe
## (Tageszeit, Wetter, Zone der Anforderung) + etwas Zufall (σ = 0.04).
## Eine Rolle gelingt, wenn der Wert die Schwelle erreicht und alle Rollen
## gelungen sind, von denen sie abhängt ("requires"). Die Aufgabe gelingt,
## wenn alle Rollen gelingen.
## Sonderfälle: "wading" – wer den Bach durchwaten kann, zählt als guter
## Schwimmer (0.85); "dark" – Anforderung wird bei Dunkelheit bewertet.

const NOISE := 0.04
const CLOSE_MARGIN := 0.06
## Liegt der Wert so weit unter der Schwelle, gilt "hint_fail_far" (falls angegeben).
const FAR_MARGIN := 0.2
const WADE_VALUE := 0.85


## assignments: role_id -> GroupMember. water_depth: Wassertiefe an der Querung (für "wading").
## Ergebnis: {"success": bool, "roles": {role_id: {score, threshold, success, skipped, close}}, "hints": PackedStringArray}
static func simulate(task: TaskDef, assignments: Dictionary, catalog: AbilityCatalog, attempt: int,
		water_depth := 0.6) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	var hour := float(task.context.get("hour", 12.0))
	var weather := str(task.context.get("weather", "clear"))
	var base := {
		"hour": hour, "is_night": DayNightCycle.phase_for(hour) == "night",
		"light": DayNightCycle.light_level_for(hour, 0.9 if weather == "rain" else (0.6 if weather == "cloudy" else 0.0)),
		"rain": 1.0 if weather == "rain" else 0.0, "wetness": 0.6 if weather == "rain" else 0.0, "weather": weather,
	}
	var results := {}
	var hints := PackedStringArray()
	var all_ok := true
	for r in task.roles:
		var m: GroupMember = assignments.get(r.id)
		var entry := {"score": 0.0, "threshold": r.threshold, "success": false, "skipped": false, "close": false}
		if m == null:
			entry.skipped = true
			results[r.id] = entry
			all_ok = false
			continue
		var sum := 0.0
		var wsum := 0.0
		for req in r.requirements:
			var sample := base.duplicate()
			if req.zone != "":
				sample.zone = req.zone
			if req.dark:
				sample.light = minf(sample.light, 0.1)
			var v := catalog.value_in(req.ability, m.genome, sample)
			if req.wading and can_wade(m.genome, water_depth):
				v = maxf(v, WADE_VALUE)
			sum += v * req.weight
			wsum += req.weight
		RngUtil.reseed(rng, ["task", task.id, attempt, r.id])
		entry.score = sum / maxf(wsum, 0.0001) + rng.randfn(0.0, NOISE)
		var deps_ok := true
		for dep in r.requires:
			if not results.get(dep, {}).get("success", false):
				deps_ok = false
		if not deps_ok:
			entry.skipped = true
			if r.hint_skipped != "":
				hints.append(r.hint_skipped)
		else:
			entry.success = entry.score >= r.threshold
			entry.close = absf(entry.score - r.threshold) < CLOSE_MARGIN
			if not entry.success and r.hint_fail_far != "" and entry.score < r.threshold - FAR_MARGIN:
				hints.append(r.hint_fail_far)
			elif not entry.success and r.hint_fail != "":
				hints.append(r.hint_fail)
			elif entry.success and entry.close and r.hint_close != "":
				hints.append(r.hint_close)
		all_ok = all_ok and entry.success
		results[r.id] = entry
	return {"success": all_ok, "roles": results, "hints": hints}


## Langbeinige Tiere waten durch Wasser dieser Tiefe (gleiche Regel wie SwimBehavior).
static func can_wade(genome: Genome, depth: float) -> bool:
	var plan := BodyPlan.from_genome(genome)
	return plan.leg_count > 0 and plan.leg_reach() * 0.85 > depth + 0.05
