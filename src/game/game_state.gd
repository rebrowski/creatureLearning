class_name GameState
extends RefCounted
## Spielstand: Taxonomie, Gruppe (mit Genomen), Journal, Aufgabenfortschritt,
## Guthaben, Fremde zum Anheuern, Tageszeit/Wetter. Gespeichert als versionierte JSON-Datei (lokal, user://).
## Regeln: docs/roadmap.md, Abschnitt „Spielstand“.

const FORMAT := "creature_save/1"
const DEFAULT_PATH := "user://save/savegame.json"
const GROUP_PATH := "res://data/world/start_group.json"
const NAMES_PATH := "res://data/game/names.json"
const PROGRESSION_PATH := "res://data/game/progression.json"
const SITES_PATH := "res://data/world/sites.json"

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
## Guthaben (Währung: progression.json "currency").
var credits := 0
## Fremde am Waldrand, die man anheuern kann (Name "Fremdling N", Preis in GroupMember.price).
var offers: Array[GroupMember] = []
## Fundstellen: ID -> verbleibender Vorrat (siehe data/world/sites.json)
var sites: Dictionary = {}
## Saison: {"number", "day", "days", "history": [{number, player, rival, won, difficulty}]}
var season: Dictionary = {}
## Schwierigkeit der Rivalen (Schlüssel in rivals.json "difficulties")
var difficulty := "normal"
## Punkte der laufenden Saison (verdiente Belohnungen + Artfragen)
var points := 0
## Versuche der laufenden Saison (für die Belohnungsfaktoren): task_id -> {attempts, successes}
var season_tasks: Dictionary = {}
var rivals: Array[RivalState] = []
## vergangene Spielzeit in Stunden (für die Taktung der Rivalen)
var game_hours := 0.0
## Bestimmungsbuch: Art-ID -> true, sobald eine Artfrage zu ihr richtig beantwortet wurde
var identified: Dictionary = {}
## schon gestellte Artfragen: "id_a|id_b" -> true
var asked_pairs: Dictionary = {}
## Einführung: 0 = noch nicht begonnen … INTRO_DONE = fertig/übersprungen.
var intro_step := 0
const INTRO_DONE := 99
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
	var cfg := progression()
	gs.credits = int(cfg.get("start_credits", 40))
	gs.start_season(1)
	gs.refill_offers(cfg)
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
	var offer_list := []
	for m in offers:
		offer_list.append(m.to_dict())
	return {"format": FORMAT, "taxonomy": taxonomy.to_dict(), "members": list, "journal": journal.to_dict(),
			"tasks": tasks, "hour": hour, "weather": weather, "recruit_count": recruit_count,
			"credits": credits, "offers": offer_list, "intro_step": intro_step,
			"identified": identified.keys(), "asked_pairs": asked_pairs.keys(), "sites": sites,
			"season": season, "difficulty": difficulty, "points": points, "season_tasks": season_tasks,
			"rivals": rivals.map(func(r): return r.to_dict()), "game_hours": game_hours}


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
	# ältere Spielstände (vor dem Anheuern): Startguthaben und neue Fremde
	credits = int(d.get("credits", progression().get("start_credits", 40)))
	intro_step = int(d.get("intro_step", INTRO_DONE))  # ältere Spielstände: keine Einführung
	for sp in d.get("identified", []):
		identified[str(sp)] = true
	for k in d.get("asked_pairs", []):
		asked_pairs[str(k)] = true
	difficulty = str(d.get("difficulty", "normal"))
	if d.has("season"):
		season = d.season
		points = int(d.get("points", 0))
		season_tasks = d.get("season_tasks", {})
		game_hours = float(d.get("game_hours", 0.0))
		for rd in d.get("rivals", []):
			rivals.append(RivalState.from_dict(schema, rd))
	else:
		start_season(1)  # ältere Spielstände: erste Saison beginnt jetzt
	refill_sites()
	var saved_sites: Dictionary = d.get("sites", {})
	for k in saved_sites:
		if sites.has(k):
			sites[k] = int(saved_sites[k])
	for od in d.get("offers", []):
		offers.append(GroupMember.from_dict(schema, od))
	if not d.has("offers"):
		refill_offers()


func member(id: String) -> GroupMember:
	for m in members:
		if m.id == id:
			return m
	return null


## Anzeigename für eine Kreaturen-ID – verrät bei Fremden nie die Art.
func display_name(id: String) -> String:
	var m := member(id)
	if m != null:
		return m.name
	for o in offers:
		if o.id == id:
			return o.name
	for r in rivals:
		for rm in r.members:
			if rm.id == id:
				return "%s (%s)" % [rm.name, r.name]
	return "ein %s" % UiUtil.STRANGER


func total_successes() -> int:
	var n := 0
	for k in tasks:
		n += tasks[k].successes
	return n


## Frei, wenn die vorausgesetzte Aufgabe (unlock_after) schon einmal gelungen ist.
func task_unlocked(task: TaskDef) -> bool:
	return task.unlock_after == "" or tasks.get(task.unlock_after, {}).get("successes", 0) > 0 \
			or tasks.get(task.id, {}).get("attempts", 0) > 0  # ältere Spielstände: schon Versuchtes bleibt offen


## Belohnung, die ein Erfolg bei dieser Aufgabe jetzt brächte: vor dem ersten
## Erfolg abhängig von der Zahl der Versuche (1. Versuch doppelt), danach
## × repeat_reward_factor.
func reward_for(task: TaskDef, cfg: Dictionary = {}) -> int:
	if cfg.is_empty():
		cfg = progression()
	var st: Dictionary = season_tasks.get(task.id, {})
	if st.get("successes", 0) > 0:
		return int(roundf(task.reward * float(cfg.get("repeat_reward_factor", 0.5))))
	var factors: Array = cfg.get("first_try_factors", [1.0])
	var f := float(factors[mini(int(st.get("attempts", 0)), factors.size() - 1)])
	return int(roundf(task.reward * f))


## Einsatz für den nächsten Versuch (nie mehr als das Guthaben – keine Sackgasse).
func attempt_cost(cfg: Dictionary = {}) -> int:
	if cfg.is_empty():
		cfg = progression()
	return mini(int(cfg.get("attempt_cost", 0)), credits)


## Aufgabenergebnis eintragen. Der Einsatz wird abgezogen, bei Erfolg gibt es
## die Belohnung. Wer gescheitert ist (failed), ist bis zum Morgen erschöpft.
## Danach kommen neue Fremde an den Waldrand.
## Rückgabe: {"earned": int, "cost": int, "new_offers": Array[GroupMember], "exhausted": Array[GroupMember]}.
func record_task(task: TaskDef, success: bool, failed: Array = []) -> Dictionary:
	var cfg := progression()
	var cost := attempt_cost(cfg)
	var earned := reward_for(task, cfg) if success else 0
	for book in [tasks, season_tasks]:
		if not book.has(task.id):
			book[task.id] = {"attempts": 0, "successes": 0}
		book[task.id].attempts = int(book[task.id].attempts) + 1
		if success:
			book[task.id].successes = int(book[task.id].successes) + 1
	if success and not consume_site(task.site):
		earned = 0  # nichts mehr zu holen (z. B. Rivalen waren schneller)
	credits += earned - cost
	points += earned
	var tired: Array[GroupMember] = []
	for m in failed:
		if m is GroupMember and members.has(m):
			m.exhausted = true
			tired.append(m)
	return {"earned": earned, "cost": cost, "new_offers": refill_offers(cfg), "exhausted": tired}


# --- Saisons und Rivalen --------------------------------------------------------

## IDs aller Kreaturen im Spiel (Gruppe, Fremde, Rivalen) – für eindeutige neue IDs.
func all_creature_ids() -> Dictionary:
	var ids := {}
	for m in members + offers:
		ids[m.id] = true
	for r in rivals:
		for m in r.members:
			ids[m.id] = true
	return ids


## Neue Saison: Punkte auf 0, Fundstellen voll, Rivalen frisch (eigene Gruppe,
## Journal, Guthaben und freigeschaltete Aufgaben bleiben).
func start_season(number: int) -> void:
	var cfg := RivalState.config()
	var history: Array = season.get("history", [])
	season = {"number": number, "day": 1, "days": int(cfg.get("season_days", 7)), "history": history}
	points = 0
	season_tasks = {}
	refill_sites()
	rivals.clear()
	if factory != null:
		for g in cfg.get("groups", []):
			var r := RivalState.create(g, factory)
			r.next_action = game_hours + float(RivalState.difficulty(difficulty).get("interval_hours", 2.0))
			rivals.append(r)


## Ein Spieltag ist vorbei. true = die Saison ist zu Ende.
func advance_day() -> bool:
	season.day = int(season.get("day", 1)) + 1
	for r in rivals:
		r.new_morning()
	return int(season.day) > int(season.get("days", 7))


## Saison auswerten und im Verlauf speichern. Vorschlag für die nächste Saison:
## eine Stufe schwerer bei deutlichem Sieg, leichter bei deutlicher Niederlage.
## Rückgabe: {"player", "rival", "rival_name", "won", "suggest": Schlüssel oder ""}
func finish_season() -> Dictionary:
	var cfg := RivalState.config()
	var best := 0
	var best_name := ""
	for r in rivals:
		if r.points >= best:
			best = r.points
			best_name = r.name
	var won := points > best
	var margin := float(cfg.get("adaptive_margin", 0.3))
	var order: Array = cfg.get("order", ["gemütlich", "normal", "ehrgeizig"])
	var i := order.find(difficulty)
	var suggest := ""
	if won and points >= best * (1.0 + margin) and i >= 0 and i < order.size() - 1:
		suggest = order[i + 1]
	elif not won and best >= points * (1.0 + margin) and i > 0:
		suggest = order[i - 1]
	var res := {"number": season.get("number", 1), "player": points, "rival": best, "rival_name": best_name,
			"won": won, "suggest": suggest, "difficulty": difficulty}
	var history: Array = season.get("history", [])
	history.append(res)
	season.history = history
	return res


# --- Fundstellen ------------------------------------------------------------------

static func sites_config() -> Dictionary:
	return _read(SITES_PATH).get("sites", {})


## Alle Fundstellen auf vollen Vorrat (neues Spiel, neue Saison).
func refill_sites() -> void:
	var cfg := sites_config()
	for id in cfg:
		sites[id] = int(cfg[id].get("stock", 1))


## Vorrat der Fundstelle einer Aufgabe (-1 = unbegrenzt).
func site_stock(task: TaskDef) -> int:
	if task.site == "" or not sites.has(task.site):
		return -1
	return int(sites[task.site])


## Eine Einheit verbrauchen (nach einem Erfolg). false = nichts mehr da.
func consume_site(site_id: String) -> bool:
	if site_id == "" or not sites.has(site_id):
		return true
	if sites[site_id] <= 0:
		return false
	sites[site_id] -= 1
	return true


## Text für die Aufgabenwahl, z. B. „Am großen Baum hängen noch 2 Früchte.“ ("" = unbegrenzt).
func site_text(task: TaskDef) -> String:
	var stock := site_stock(task)
	if stock < 0:
		return ""
	var c: Dictionary = sites_config().get(task.site, {})
	if stock == 0:
		return "%s: nichts mehr da – morgen wachsen %d %s nach." % [str(c.get("name", task.site)).capitalize(), int(c.get("regrow", 1)), c.get("unit", "")]
	return "%s: noch %d %s." % [str(c.get("name", task.site)).capitalize(), stock, c.get("unit", "")]


## Neuer Morgen: alle Erschöpften sind wieder fit, Fundstellen wachsen nach.
## Rückgabe: wie viele Erschöpfte sich erholt haben.
func new_morning() -> int:
	var cfg := sites_config()
	for id in sites:
		var c: Dictionary = cfg.get(id, {})
		sites[id] = mini(int(c.get("stock", sites[id])), int(sites[id]) + int(c.get("regrow", 1)))
	var n := 0
	for m in members:
		if m.exhausted:
			m.exhausted = false
			n += 1
	return n


## Füllt die Fremden am Waldrand auf "offers" auf (solange die Gruppe nicht voll ist).
func refill_offers(cfg: Dictionary = {}) -> Array[GroupMember]:
	if cfg.is_empty():
		cfg = progression()
	var added: Array[GroupMember] = []
	while offers.size() < int(cfg.get("offers", 3)) and members.size() + offers.size() < int(cfg.get("max_group_size", 20)):
		var m := recruit(cfg)
		if m == null:
			break
		offers.append(m)
		added.append(m)
	return added


# --- Artfragen und Bestimmungsbuch -------------------------------------------

static func _pair_key(a: GroupMember, b: GroupMember) -> String:
	return "%s|%s" % [a.id, b.id] if a.id < b.id else "%s|%s" % [b.id, a.id]


## Nächste Artfrage: das ähnlichste noch nicht gefragte Paar von Gruppenmitgliedern
## (Doppelgänger zuerst). {"a": GroupMember, "b": GroupMember} oder {}.
func species_question() -> Dictionary:
	var best := {}
	var best_d := INF
	for i in members.size():
		for j in range(i + 1, members.size()):
			var a := members[i]
			var b := members[j]
			if asked_pairs.has(_pair_key(a, b)):
				continue
			# schon beide Arten bestimmt und gleich/verschieden bekannt? dann uninteressant
			if identified.has(a.species_id) and identified.has(b.species_id):
				continue
			var d := GenomeDistance.distance(a.genome, b.genome)
			if d < best_d:
				best_d = d
				best = {"a": a, "b": b}
	return best


## Antwort auf eine Artfrage. Rückgabe: {"correct", "same", "reward", "discovered": [Anzeigenamen]}.
func answer_species_question(a: GroupMember, b: GroupMember, said_same: bool) -> Dictionary:
	asked_pairs[_pair_key(a, b)] = true
	var same := a.species_id == b.species_id
	var res := {"correct": said_same == same, "same": same, "reward": 0, "discovered": []}
	if res.correct:
		res.reward = int(progression().get("species_reward", 10))
		credits += res.reward
		points += res.reward
		for sp in [a.species_id, b.species_id]:
			if not identified.has(sp):
				identified[sp] = true
				res.discovered.append(taxonomy.get_taxon(sp).display_name())
	return res


## Arten, von denen die Gruppe Mitglieder hat: [[Taxon, [GroupMember], bestimmt?]]
func field_guide() -> Array:
	var by_species := {}
	for m in members:
		if not by_species.has(m.species_id):
			by_species[m.species_id] = []
		by_species[m.species_id].append(m)
	var out := []
	for sp in by_species:
		out.append([taxonomy.get_taxon(sp), by_species[sp], identified.has(sp)])
	return out


## Arten, die für eine freigeschaltete, noch ungelöste Aufgabe gebraucht
## werden: Rollen, die kein Gruppenmitglied schafft (Durchschnittstier der Art).
func needed_species(task_catalog: TaskCatalog, ability_catalog: AbilityCatalog) -> Array[String]:
	var out: Array[String] = []
	for t in task_catalog.tasks:
		if not task_unlocked(t) or tasks.get(t.id, {}).get("successes", 0) > 0:
			continue
		for r in t.roles:
			var covered := false
			for m in members + offers:
				if TaskSimulator.simulate(t, {r.id: m}, ability_catalog, 0).roles[r.id].score >= r.threshold:
					covered = true
					break
			if covered:
				continue
			for sp in taxonomy.species():
				var probe := GroupMember.from_individual(factory.create_individual(sp.id, 0, "", "adult"), "")
				if TaskSimulator.simulate(t, {r.id: probe}, ability_catalog, 0).roles[r.id].score >= r.threshold and not out.has(sp.id):
					out.append(sp.id)
	return out


## Sorgt dafür, dass unter den Fremden jemand ist, der eine fehlende Rolle
## übernehmen kann (sonst gäbe es eine Sackgasse). Rückgabe:
## {"added": [GroupMember], "removed": [GroupMember]} (für die Welt).
func ensure_needed_offer(needed: Array[String]) -> Dictionary:
	var result := {"added": [], "removed": []}
	if needed.is_empty():
		return result
	for o in offers:
		if needed.has(o.species_id):
			return result
	var cfg := progression()
	var rng := RngUtil.make_rng(["needed", taxonomy.base_seed, recruit_count])
	var sp: String = needed[rng.randi() % needed.size()]
	var m := recruit(cfg, sp)
	if offers.size() >= int(cfg.get("offers", 3)) and not offers.is_empty():
		result.removed.append(offers.pop_front())
	offers.append(m)
	result.added.append(m)
	return result


## Warum man diesen Fremden gerade nicht anheuern kann ("" = geht).
func hire_problem(offer: GroupMember) -> String:
	if not offers.has(offer):
		return "nicht mehr da"
	if members.size() >= int(progression().get("max_group_size", 20)):
		return "Die Gruppe ist voll."
	if credits < offer.price:
		return "Zu wenig %s (%d von %d)." % [currency(), credits, offer.price]
	return ""


## Heuert einen Fremden an: kostet seinen Preis, er bekommt einen Namen.
func hire(offer: GroupMember) -> bool:
	if hire_problem(offer) != "":
		return false
	credits -= offer.price
	offers.erase(offer)
	offer.name = _next_name()
	offer.joined_after = total_successes()
	offer.price = 0
	members.append(offer)
	return true


static func currency() -> String:
	return str(progression().get("currency", "Beeren"))


static func progression() -> Dictionary:
	return _read(PROGRESSION_PATH)


## Wählt einen neuen Fremden (vorläufiger Name "Fremdling N", mit Preis): meist eine Art, die
## einem Mitglied ähnlich sieht (Doppelgänger, Nachahmer), sonst zufällig; oft
## vertretene Arten seltener.
func recruit(cfg: Dictionary = {}, species_id := "") -> GroupMember:
	if cfg.is_empty():
		cfg = progression()
	var rng := RngUtil.make_rng(["recruit", taxonomy.base_seed, recruit_count])
	var counts := {}
	for m in members + offers:
		counts[m.species_id] = counts.get(m.species_id, 0) + 1
	var taken := all_creature_ids()
	var candidates: Array[Taxon] = taxonomy.species()
	if candidates.is_empty():
		return null
	var chosen: Taxon
	if species_id != "" and taxonomy.has_taxon(species_id):
		chosen = taxonomy.get_taxon(species_id)
	elif rng.randf() < float(cfg.get("lookalike_chance", 0.7)):
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
	for m in members + offers:
		if m.species_id == chosen.id:
			index = maxi(index, m.index + 1)
	while taken.has("%s#%d" % [chosen.id, index]):
		index += 1
	var ind := factory.create_individual(chosen.id, index, "", "", float(cfg.get("juvenile_chance", 0.15)))
	recruit_count += 1
	var gm := GroupMember.from_individual(ind, "%s %d" % [UiUtil.STRANGER, recruit_count], total_successes())
	var price := float(cfg.get("price_base", 20)) + float(cfg.get("price_per_member", 2)) * members.size()
	price += rng.randf_range(-1.0, 1.0) * float(cfg.get("price_jitter", 5))
	if gm.age == "juvenile":
		price *= float(cfg.get("juvenile_factor", 0.6))
	gm.price = maxi(5, int(roundf(price / 5.0)) * 5)
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
