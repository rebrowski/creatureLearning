class_name ProbeCatalog
extends RefCounted
## Proben der Bühne (data/stage/probes.json): eine Fähigkeit, ein eindeutiges,
## abgestuftes Ergebnis 0–3. Reine Logik (testbar ohne Szene).

const PATH := "res://data/stage/probes.json"

var probes: Array = []
var thresholds: Array = [0.25, 0.5, 0.75]
var noise := 0.06


static func load_file(path := PATH) -> ProbeCatalog:
	var c := ProbeCatalog.new()
	var res := JsonLoader.read(path)
	if res.error == "" and res.data is Dictionary:
		c.probes = res.data.get("probes", [])
		c.thresholds = res.data.get("thresholds", c.thresholds)
		c.noise = float(res.data.get("noise", c.noise))
	return c


func get_probe(id: String) -> Dictionary:
	for p in probes:
		if p.id == id:
			return p
	return {}


## Probe zur Fähigkeit (für Aufgaben-Rollen).
func for_ability(ability: String) -> Dictionary:
	for p in probes:
		if p.ability == ability:
			return p
	return {}


## Kontext einer Probe (Nacht, Zone) wie im TaskSimulator.
static func sample_for(probe: Dictionary) -> Dictionary:
	var night: bool = probe.get("night", false)
	var s := {"hour": 23.0 if night else 11.0, "is_night": night, "light": 0.05 if night else 1.0,
			"rain": 0.0, "wetness": 0.0, "weather": "clear"}
	if probe.get("zone", "") != "":
		s.zone = probe.zone
	return s


## Wert 0..1 → Stufe 0..3.
func grade_of(value: float) -> int:
	var g := 0
	for t in thresholds:
		if value >= float(t):
			g += 1
	return g


## Stufe einer Kreatur bei einer Probe; `trial` macht Wiederholungen leicht verschieden.
func grade(member: GroupMember, probe: Dictionary, catalog: AbilityCatalog, trial := 0) -> int:
	if probe.get("ability", "") == "swim" and TaskSimulator.can_wade(member.genome, 0.6):
		return 3  # watet einfach hindurch
	var v := catalog.value_in(str(probe.ability), member.genome, sample_for(probe))
	var rng := RngUtil.make_rng(["probe", member.id, probe.id, trial])
	return grade_of(v + rng.randfn(0.0, noise))


## Stufe einer Rolle in einer Aufgabe: Erfolg = 3, sonst nach Abstand zur Schwelle 0–2.
static func task_grade(role_result: Dictionary) -> int:
	if role_result.get("success", false):
		return 3
	var t := maxf(float(role_result.get("threshold", 0.5)), 0.01)
	return clampi(int(floorf(float(role_result.get("score", 0.0)) / t * 3.0)), 0, 2)


func result_text(probe: Dictionary, g: int) -> String:
	var r: Array = probe.get("results", [])
	return str(r[clampi(g, 0, r.size() - 1)]) if not r.is_empty() else ""
