class_name RivalState
extends RefCounted
## Eine Rivalen-Gruppe (Konfiguration: data/game/rivals.json). Spielt nach
## denselben Regeln wie der Spieler und kennt die wahren Fähigkeiten nicht:
## `beliefs` sind ihre eigenen Schätzungen (0..1), die sich durch Versuche und
## Beobachtungen verbessern (RivalAI).

const PATH := "res://data/game/rivals.json"

var id := ""
var name := ""
var color := Color(0.78, 0.6, 1.0)
var camp := Vector2.ZERO
var members: Array[GroupMember] = []
var credits := 0
## Punkte der laufenden Saison (verdiente Belohnungen)
var points := 0
## member_id -> {ability: Schätzung 0..1}
var beliefs: Dictionary = {}
## Versuche dieser Saison: task_id -> {"attempts", "successes"}
var tasks: Dictionary = {}
## Spielstunde (GameState.game_hours), ab der die nächste Aktion fällig ist
var next_action := 0.0
## heute schon versuchte Aufgaben (task_id -> true), Reset am Morgen
var today: Dictionary = {}
var _name_index := 0


static func config() -> Dictionary:
	var res := JsonLoader.read(PATH)
	return res.data if res.error == "" and res.data is Dictionary else {}


static func difficulty(key: String) -> Dictionary:
	var d: Dictionary = config().get("difficulties", {})
	return d.get(key, d.get("normal", {}))


## Neue Gruppe nach Konfiguration (Saisonbeginn).
static func create(group: Dictionary, factory: IndividualFactory, catalog: AbilityCatalog = null) -> RivalState:
	var r := RivalState.new()
	r.id = str(group.get("id", "rival"))
	r.name = str(group.get("name", "Rivalen"))
	var c: Array = group.get("color", [0.78, 0.6, 1.0])
	r.color = Color(c[0], c[1], c[2])
	var cp: Array = group.get("camp", [0, 0])
	r.camp = Vector2(cp[0], cp[1])
	r.credits = int(group.get("start_credits", 40))
	for m in group.get("members", []):
		if not factory.taxonomy.has_taxon(str(m.species)):
			continue
		var ind := factory.create_individual(str(m.species), int(m.get("index", 100)), "", "adult")
		r.add_member(GroupMember.from_individual(ind, r.next_name(group)), catalog)
	return r


func next_name(group: Dictionary = {}) -> String:
	if group.is_empty():
		for g in config().get("groups", []):
			if g.get("id", "") == id:
				group = g
	var names: Array = group.get("names", [])
	var n := "%s %d" % [name, _name_index + 1] if _name_index >= names.size() else str(names[_name_index])
	_name_index += 1
	return n


## Mitglied aufnehmen; Schätzungen beginnen neutral (0.5).
func add_member(m: GroupMember, catalog: AbilityCatalog = null) -> void:
	members.append(m)
	var b := {}
	if catalog != null:
		for a in catalog.order:
			b[a] = start_belief()
	beliefs[m.id] = b


static func start_belief() -> float:
	return float(config().get("start_belief", 0.3))


func belief(member_id: String, ability: String) -> float:
	return float(beliefs.get(member_id, {}).get(ability, start_belief()))


func set_belief(member_id: String, ability: String, value: float) -> void:
	if not beliefs.has(member_id):
		beliefs[member_id] = {}
	beliefs[member_id][ability] = clampf(value, 0.0, 1.0)


func new_morning() -> void:
	today.clear()
	for m in members:
		m.exhausted = false


## Freigeschaltet nach derselben Kette wie beim Spieler (eigene Erfolge).
func task_unlocked(task: TaskDef) -> bool:
	return task.unlock_after == "" or int(tasks.get(task.unlock_after, {}).get("successes", 0)) > 0


func to_dict() -> Dictionary:
	var list := []
	for m in members:
		list.append(m.to_dict())
	return {"id": id, "name": name, "color": [color.r, color.g, color.b], "camp": [camp.x, camp.y],
			"members": list, "credits": credits, "points": points, "beliefs": beliefs, "tasks": tasks,
			"next_action": next_action, "name_index": _name_index, "today": today.keys()}


static func from_dict(schema: GenomeSchema, d: Dictionary) -> RivalState:
	var r := RivalState.new()
	r.id = str(d.get("id", "rival"))
	r.name = str(d.get("name", "Rivalen"))
	var c: Array = d.get("color", [0.78, 0.6, 1.0])
	r.color = Color(c[0], c[1], c[2])
	var cp: Array = d.get("camp", [0, 0])
	r.camp = Vector2(cp[0], cp[1])
	for md in d.get("members", []):
		r.members.append(GroupMember.from_dict(schema, md))
	r.credits = int(d.get("credits", 0))
	r.points = int(d.get("points", 0))
	r.beliefs = d.get("beliefs", {})
	r.tasks = d.get("tasks", {})
	r.next_action = float(d.get("next_action", 0.0))
	r._name_index = int(d.get("name_index", r.members.size()))
	for k in d.get("today", []):
		r.today[str(k)] = true
	return r
