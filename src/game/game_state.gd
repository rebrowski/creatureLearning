class_name GameState
extends RefCounted
## Spielstand: Taxonomie, Gruppe (mit Genomen), Journal, Aufgabenfortschritt,
## Tageszeit/Wetter. Gespeichert als versionierte JSON-Datei (lokal, user://).
## Regeln: docs/roadmap.md, Abschnitt „Spielstand“.

const FORMAT := "creature_save/1"
const DEFAULT_PATH := "user://save/savegame.json"
const GROUP_PATH := "res://data/world/start_group.json"
const NAMES_PATH := "res://data/game/names.json"
const PROGRESSION_PATH := "res://data/game/progression.json"

var schema: GenomeSchema
var taxonomy: Taxonomy
var factory: IndividualFactory
var members: Array[GroupMember] = []
var journal := Journal.new()
## task_id -> {"attempts": int, "successes": int}
var tasks: Dictionary = {}
var hour := 9.0
var weather := "clear"
var recruit_count := 0
var errors: PackedStringArray = []


static func new_game(group_path: String = GROUP_PATH) -> GameState:
	var gs := GameState.new()
	gs.schema = GenomeSchema.load_file()
	var res := JsonLoader.read(group_path)
	if res.error != "":
		gs.errors.append(res.error)
		return gs
	var loader := TaxonomyLoader.new()
	gs.taxonomy = loader.load_file(res.data.get("taxonomy", ""), gs.schema)
	if gs.taxonomy == null:
		gs.errors.append_array(loader.errors)
		return gs
	gs.factory = IndividualFactory.new(gs.taxonomy)
	for m in res.data.get("members", []):
		if not gs.taxonomy.has_taxon(m.species):
			gs.errors.append("Startgruppe: unbekannte Art '%s'" % m.species)
			continue
		var ind := gs.factory.create_individual(m.species, int(m.get("index", 0)), "", "", 0.1)
		gs.members.append(GroupMember.from_individual(ind, gs._next_name()))
	return gs


static func load_file(path: String = DEFAULT_PATH) -> GameState:
	var gs := GameState.new()
	var res := JsonLoader.read(path)
	if res.error != "":
		gs.errors.append(res.error)
		return gs
	gs._from_dict(res.data)
	return gs


static func exists(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


func is_valid() -> bool:
	return errors.is_empty() and taxonomy != null


func save(path: String = DEFAULT_PATH) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return JsonLoader.write(path, to_dict())


func to_dict() -> Dictionary:
	var list := []
	for m in members:
		list.append(m.to_dict())
	return {"format": FORMAT, "taxonomy": taxonomy.to_dict(), "members": list, "journal": journal.to_dict(),
			"tasks": tasks, "hour": hour, "weather": weather, "recruit_count": recruit_count}


func _from_dict(d: Variant) -> void:
	if not d is Dictionary or d.get("format", "") != FORMAT:
		errors.append("Spielstand: unbekanntes Format")
		return
	schema = GenomeSchema.load_file()
	var loader := TaxonomyLoader.new()
	taxonomy = loader.from_dict(d.get("taxonomy", {}), schema, "Spielstand")
	if taxonomy == null:
		errors.append_array(loader.errors)
		return
	factory = IndividualFactory.new(taxonomy)
	for md in d.get("members", []):
		members.append(GroupMember.from_dict(schema, md))
	journal = Journal.from_dict(d.get("journal", {}))
	tasks = d.get("tasks", {})
	for k in tasks:
		tasks[k] = {"attempts": int(tasks[k].get("attempts", 0)), "successes": int(tasks[k].get("successes", 0))}
	hour = float(d.get("hour", 9.0))
	weather = str(d.get("weather", "clear"))
	recruit_count = int(d.get("recruit_count", 0))


func member(id: String) -> GroupMember:
	for m in members:
		if m.id == id:
			return m
	return null


func total_successes() -> int:
	var n := 0
	for k in tasks:
		n += tasks[k].successes
	return n


## Aufgabenergebnis eintragen; bei Erfolg kommen neue Mitglieder dazu (Rückgabe).
func record_task(task_id: String, success: bool) -> Array[GroupMember]:
	if not tasks.has(task_id):
		tasks[task_id] = {"attempts": 0, "successes": 0}
	tasks[task_id].attempts += 1
	var joined: Array[GroupMember] = []
	if success:
		tasks[task_id].successes += 1
		var cfg: Dictionary = _read(PROGRESSION_PATH)
		for i in int(cfg.get("recruits_per_success", 1)):
			if members.size() >= int(cfg.get("max_group_size", 20)):
				break
			var m := recruit(cfg)
			if m != null:
				joined.append(m)
	return joined


## Wählt eine neue Kreatur: meist eine Art, die einem Mitglied ähnlich sieht
## (Doppelgänger, Nachahmer), sonst zufällig; oft vertretene Arten seltener.
func recruit(cfg: Dictionary = {}) -> GroupMember:
	if cfg.is_empty():
		cfg = _read(PROGRESSION_PATH)
	var rng := RngUtil.make_rng(["recruit", taxonomy.base_seed, recruit_count])
	var counts := {}
	for m in members:
		counts[m.species_id] = counts.get(m.species_id, 0) + 1
	var candidates: Array[Taxon] = taxonomy.species()
	if candidates.is_empty():
		return null
	var chosen: Taxon
	if rng.randf() < float(cfg.get("lookalike_chance", 0.7)):
		var best_score := INF
		for sp in candidates:
			var d := INF
			for s2 in counts:
				if s2 != sp.id:
					d = minf(d, GenomeDistance.distance(factory.mean_genome(sp.id), factory.mean_genome(s2)))
			var score: float = d * (1.0 + 4.0 * counts.get(sp.id, 0)) + rng.randf() * 0.01
			if score < best_score:
				best_score = score
				chosen = sp
	else:
		var weights := []
		var total := 0.0
		for sp in candidates:
			var w: float = 1.0 / (1.0 + 2.0 * counts.get(sp.id, 0))
			weights.append(w)
			total += w
		var r := rng.randf() * total
		for i in candidates.size():
			r -= weights[i]
			if r <= 0.0:
				chosen = candidates[i]
				break
		if chosen == null:
			chosen = candidates[-1]
	var index := 0
	for m in members:
		if m.species_id == chosen.id:
			index = maxi(index, m.index + 1)
	var ind := factory.create_individual(chosen.id, index, "", "", float(cfg.get("juvenile_chance", 0.15)))
	recruit_count += 1
	var gm := GroupMember.from_individual(ind, _next_name(), total_successes())
	members.append(gm)
	return gm


func _next_name() -> String:
	var names: Array = _read(NAMES_PATH).get("names", [])
	var used := {}
	for m in members:
		used[m.name] = true
	for n in names:
		if not used.has(n):
			return n
	return "Kreatur %d" % (members.size() + 1)


static func _read(path: String) -> Dictionary:
	var res := JsonLoader.read(path)
	return res.data if res.error == "" and res.data is Dictionary else {}
