class_name Journal
extends RefCounted
## Beobachtungs-Journal des Spielers: Markierungen, eigene Gruppen
## („gleiche Art?“), Notizen, Einschätzungen der Fähigkeiten und ein
## automatisches Protokoll beobachteter Verhaltensweisen.
## Das Spiel bewertet nichts davon – Rückmeldung gibt es nur indirekt über Aufgaben.

signal changed

const MARK_COLORS: Array[Color] = [Color(0.9, 0.3, 0.3), Color(0.95, 0.7, 0.2), Color(0.4, 0.8, 0.3),
		Color(0.3, 0.6, 0.95), Color(0.7, 0.4, 0.9), Color(0.9, 0.9, 0.9)]
## Einschätzung einer Fähigkeit: -1 = unbekannt, 0 = schwach, 1 = mittel, 2 = stark
const RATING_LABELS := {-1: "?", 0: "schwach", 1: "mittel", 2: "stark"}
const LOG_SIZE := 80

## member_id -> Farbindex (MARK_COLORS), fehlt = keine Markierung
var marks: Dictionary = {}
## member_id -> Text
var notes: Dictionary = {}
## member_id -> {ability_id: int}
var ratings: Dictionary = {}
## [{"name": String, "members": Array[String]}]
var groups: Array = []
## [{"time": String, "member": String, "text": String}]
var entries: Array = []
## Ergebnisse der Proben auf der Bühne: member_id -> {ability: Stufe 0..3 (letzte Probe)}
var probes: Dictionary = {}


func set_mark(member_id: String, color_index: int) -> void:
	if color_index < 0:
		marks.erase(member_id)
	else:
		marks[member_id] = color_index
	changed.emit()


func set_note(member_id: String, text: String) -> void:
	if text.strip_edges() == "":
		notes.erase(member_id)
	else:
		notes[member_id] = text
	changed.emit()


func rating(member_id: String, ability: String) -> int:
	return int(ratings.get(member_id, {}).get(ability, -1))


func set_rating(member_id: String, ability: String, value: int) -> void:
	if not ratings.has(member_id):
		ratings[member_id] = {}
	if value < 0:
		ratings[member_id].erase(ability)
	else:
		ratings[member_id][ability] = value
	changed.emit()


func add_group(group_name: String) -> int:
	groups.append({"name": group_name, "members": []})
	changed.emit()
	return groups.size() - 1


func rename_group(index: int, group_name: String) -> void:
	groups[index].name = group_name
	changed.emit()


func remove_group(index: int) -> void:
	groups.remove_at(index)
	changed.emit()


## Eine Kreatur gehört höchstens einer eigenen Gruppe an; -1 = keiner.
func group_of(member_id: String) -> int:
	for i in groups.size():
		if groups[i].members.has(member_id):
			return i
	return -1


func assign_group(member_id: String, index: int) -> void:
	for g in groups:
		g.members.erase(member_id)
	if index >= 0 and index < groups.size():
		groups[index].members.append(member_id)
	changed.emit()


func add_log(time_label: String, member_id: String, text: String) -> void:
	entries.append({"time": time_label, "member": member_id, "text": text})
	if entries.size() > LOG_SIZE:
		entries.pop_front()
	changed.emit()


func entries_for(member_id: String, max_count := 5) -> Array:
	var out := []
	for i in range(entries.size() - 1, -1, -1):
		if entries[i].member == member_id:
			out.append(entries[i])
			if out.size() >= max_count:
				break
	return out


## Probenergebnis festhalten (Stufe 0..3).
func set_probe(member_id: String, ability: String, grade: int) -> void:
	if not probes.has(member_id):
		probes[member_id] = {}
	probes[member_id][ability] = grade
	changed.emit()


## Letzte Probenstufe (-1 = noch nicht geprüft).
func probe(member_id: String, ability: String) -> int:
	return int(probes.get(member_id, {}).get(ability, -1))


## ●●○ für eine Stufe 0..3 (drei Punkte, gefüllt = erreicht).
static func grade_dots(grade: int) -> String:
	if grade < 0:
		return "–"
	return "●".repeat(grade) + "○".repeat(3 - grade)


func to_dict() -> Dictionary:
	return {"marks": marks, "notes": notes, "ratings": ratings, "groups": groups, "log": entries, "probes": probes}


static func from_dict(d: Dictionary) -> Journal:
	var j := Journal.new()
	j.marks = d.get("marks", {})
	j.notes = d.get("notes", {})
	j.probes = d.get("probes", {})
	j.ratings = d.get("ratings", {})
	for g in d.get("groups", []):
		j.groups.append({"name": str(g.get("name", "")), "members": Array(g.get("members", []))})
	j.entries = d.get("log", [])
	# JSON liefert Zahlen als float
	for k in j.marks:
		j.marks[k] = int(j.marks[k])
	for k in j.ratings:
		for a in j.ratings[k]:
			j.ratings[k][a] = int(j.ratings[k][a])
	return j
