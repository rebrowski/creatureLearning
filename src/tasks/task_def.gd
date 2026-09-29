class_name TaskDef
extends RefCounted
## Eine Aufgabe aus data/tasks/*.json (Format: docs/tasks_format.md).

const FORMAT := "creature_task/1"
const STEP_TYPES := ["climb_tree", "pick_up", "cross_stream", "drop", "walk_to", "behavior", "follow", "wait"]
const REQ_KEYS := ["ability", "weight", "zone", "wading", "dark"]

var id := ""
var name := ""
var description := ""
var order := 0
## {"hour": float, "weather": String}
var context: Dictionary = {}
## Ortsname -> Ortsangabe (z. B. "fruit_tree:0")
var places: Dictionary = {}
## [{id, name, description, requirements: [{ability, weight, zone, wading, dark}], threshold, requires: [], hint_fail, hint_close, hint_skipped}]
var roles: Array = []
var steps: Array = []
var errors: PackedStringArray = []


static func from_dict(d: Variant, catalog: AbilityCatalog, source := "<task>") -> TaskDef:
	var t := TaskDef.new()
	if not d is Dictionary:
		t.errors.append("%s: Wurzel muss ein Objekt sein" % source)
		return t
	t.id = str(d.get("id", ""))
	if t.id == "":
		t.errors.append("%s: 'id' fehlt" % source)
	t.name = str(d.get("name", t.id))
	t.description = str(d.get("description", ""))
	t.order = int(d.get("order", 0))
	t.context = d.get("context", {})
	t.places = d.get("places", {})
	var role_ids := []
	for i in d.get("roles", []).size():
		var r: Dictionary = d.roles[i]
		var ctx := "%s: roles[%d]" % [source, i]
		var rid := str(r.get("id", ""))
		if rid == "" or role_ids.has(rid):
			t.errors.append("%s: 'id' fehlt oder doppelt" % ctx)
			continue
		var reqs := []
		for req in r.get("requirements", []):
			for k in req:
				if not REQ_KEYS.has(k):
					t.errors.append("%s.requirements: unbekanntes Feld '%s'" % [ctx, k])
			if not catalog.abilities.has(str(req.get("ability", ""))):
				t.errors.append("%s.requirements: unbekannte Fähigkeit '%s'" % [ctx, req.get("ability")])
				continue
			reqs.append({"ability": str(req.ability), "weight": float(req.get("weight", 1.0)), "zone": str(req.get("zone", "")),
					"wading": bool(req.get("wading", false)), "dark": bool(req.get("dark", false))})
		if reqs.is_empty():
			t.errors.append("%s: keine gültigen 'requirements'" % ctx)
		role_ids.append(rid)
		t.roles.append({"id": rid, "name": str(r.get("name", rid)), "description": str(r.get("description", "")),
				"requirements": reqs, "threshold": float(r.get("threshold", 0.5)), "requires": Array(r.get("requires", [])),
				"hint_fail": str(r.get("hint_fail", "")), "hint_close": str(r.get("hint_close", "")),
				"hint_skipped": str(r.get("hint_skipped", ""))})
	if t.roles.is_empty():
		t.errors.append("%s: mindestens eine Rolle nötig" % source)
	for r in t.roles:
		for dep in r.requires:
			if not role_ids.has(dep):
				t.errors.append("%s: Rolle '%s' hängt von unbekannter Rolle '%s' ab" % [source, r.id, dep])
	t.steps = d.get("steps", [])
	for i in t.steps.size():
		var s: Dictionary = t.steps[i]
		var ctx := "%s: steps[%d]" % [source, i]
		if not STEP_TYPES.has(s.get("type", "")):
			t.errors.append("%s: unbekannter Schritt '%s' (erlaubt: %s)" % [ctx, s.get("type"), ", ".join(STEP_TYPES)])
		if s.has("role") and not role_ids.has(s.role):
			t.errors.append("%s: unbekannte Rolle '%s'" % [ctx, s.role])
		if s.has("leader") and not role_ids.has(s.leader):
			t.errors.append("%s: unbekannte Rolle '%s'" % [ctx, s.leader])
		if s.has("place") and not t.places.has(s.place):
			t.errors.append("%s: unbekannter Ort '%s'" % [ctx, s.place])
	return t


func is_valid() -> bool:
	return errors.is_empty()


func role(role_id: String) -> Dictionary:
	for r in roles:
		if r.id == role_id:
			return r
	return {}
