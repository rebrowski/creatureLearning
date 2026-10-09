extends Node3D

## Wurzel der Waldwelt: verbindet Gelände, Navigation, Tageszeit, Wetter und
## Kamera, lädt den Spielstand (oder startet ein neues Spiel), setzt die Gruppe
## und die Fremden am Waldrand ein, protokolliert Beobachtungen, führt Aufgaben
## auf der Bühne (Stage, abseits des Lagers) durch, ebenso die Proben, und
## verwaltet das Anheuern.
##
## Das Spiel läuft in Runden (Runde = Spieltag der Saison) mit vier Phasen:
## Zug der Rivalen (als Bühnenszene) → zwei Proben → eigene Aufgabe (Wahl aus den
## Angeboten der Runde) → Abend (Artfrage, Ergebnisse, Erholung, „Nächste Runde“).
## Die Uhr läuft nicht von selbst; jede Phase hat ihre Tageszeit. Im Lager kann man
## jederzeit zuschauen.
##
## Die Szene (scenes/world/forest.tscn) wird von tools/build_forest.gd erzeugt;
## Knoten werden über ihre Namen gefunden.
## Ohne Spielstand (Tests, Screenshots): Root-Meta "forest_no_save" setzen.

## Tageszeit je Phase der Runde
const PHASE_HOURS := {"rivals": 8.0, "probes": 10.0, "task": 14.0, "evening": 19.5}
const ROUND_PHASE_LABELS := {"rivals": "Zug der Rivalen", "probes": "Proben", "task": "Aufgabe", "evening": "Abend"}
const WEATHER_LABELS := {"clear": "klar", "cloudy": "bewölkt", "rain": "Regen"}
## Beobachtungen werden protokolliert, wenn die Kreatur höchstens so weit von der Kamera entfernt ist.
const OBSERVE_DISTANCE := 28.0
const AUTOSAVE_SECONDS := 60.0
## Höchstgeschwindigkeit, mit der sich überlappende Kreaturen auseinanderschieben (m/s).
const SEPARATE_SPEED := 1.5
## Fremde streifen in diesem Abstand vom Lagerplatz umher (Meter).
const STRANGER_DISTANCE := 13.0
const STRANGER_ROAM := 5.0
const TAG_MEMBER := Color(1, 1, 1)
const TAG_STRANGER := Color(1.0, 0.75, 0.35)
const TAG_TIRED := Color(0.7, 0.7, 0.8)
## Die Bühne liegt weit außerhalb des Geländes (64 × 64 m), damit man von dort
## nichts vom Lager sieht und umgekehrt.
const STAGE_ORIGIN := Vector3(0.0, 0.0, 600.0)
## Proben pro Tag
const PROBES_PER_DAY := 2
## Zeitraffer für „Überspringen“.
const SKIP_SPEED := 6.0
## Rivalen streifen in diesem Umkreis um ihr Lager.
const RIVAL_ROAM := 9.0
## Geräusche der Kreatur im Fokus sind bis zu dieser Kameradistanz hörbar (Meter).
const SOUND_DISTANCE := 30.0
## Kamera-Verschiebung je Leistenhöhe (1 = Kreatur genau mittig im freien Bereich;
## etwas weniger, damit sie nicht unter die Knöpfe oben rutscht).
const VIEW_SHIFT_FACTOR := 0.7
## Vergangenheitsform für das Protokoll
const PAST := {
	"climb_rock": "kletterte auf einen Felsen", "climb_tree": "kletterte auf einen Baum",
	"swim": "ging ins Wasser", "dig": "grub ein Loch", "carry": "wollte einen Stein tragen",
	"call": "rief laut", "sniff": "witterte", "rest": "ruhte sich aus", "display": "drohte",
}
const OUTCOME := {"success": " – hat geklappt", "fail": " – hat nicht geklappt", "": ""}

@onready var terrain: ForestTerrain = $Terrain
@onready var navigation: ForestNavigation = $Navigation
@onready var day_night: DayNightCycle = $DayNight
@onready var weather: Weather = $Weather
@onready var context: WorldContext = $WorldContext
@onready var camera: OrbitCamera = $Camera
@onready var creature_root: Node3D = $Creatures

var game: GameState
var catalog: AbilityCatalog
var tasks: TaskCatalog
var creatures: Array[Creature] = []
var brains: Array[BehaviorBrain] = []
## Creature -> GroupMember
var members: Dictionary = {}
## Creature -> GroupMember (Fremde am Waldrand, noch nicht angeheuert)
var strangers: Dictionary = {}
## Creature -> [RivalState, GroupMember] (Kreaturen der Rivalen)
var rival_creatures: Dictionary = {}
var show_names := true
var selected: Creature
var debug_mode := false
var saving_enabled := true
var graphics_level := "high"
var perf := PerfMonitor.new()
## Vorübergehende Kreaturen des Leistungstests (nicht gespeichert).
var test_creatures: Array[Creature] = []

var _status: Label
var _info: Label
## obere Leiste (Status, Knöpfe) – auf der Bühne ausgeblendet
var _hud_top: Control
## Hauptknopf der Phase (Probe / Aufgabe wählen / Abend) und „Weiter ›“
var _phase_button: Button
var _next_button: Button
var _round_panel: RoundPanel
## Was der Hauptknopf der Übersicht als Nächstes tut
var _round_next: Callable
var _card: CreatureCard
var _journal_panel: JournalPanel
var _task_panel: TaskPanel
var _result_panel: ResultPanel
var _hire_panel: HirePanel
var _intro: IntroPanel
var _question: SpeciesQuestionPanel
var _intro_timer := 0.0
var _intro_ratings := 0
var _banner: Label
var _skip: Button
var _skipping := false
var _credits: Label
var _rival_rng := RandomNumberGenerator.new()
var _web_save_cb: JavaScriptObject
var _score: Label
var _season_label: Label
## Punktestand oben rechts – auf der Bühne ausgeblendet (verrät sonst das Ergebnis)
var _score_box: Control
var _season_panel: SeasonPanel
var _difficulty_button: Button
## true, solange auf der Bühne etwas läuft (Probe, Aufgabe)
var _busy := false
var stage: Stage
var director: StageDirector
var probe_catalog: ProbeCatalog
var _gallery: GalleryBar
var _probe_panel: ProbePanel
## Wofür die Galerie gerade offen ist: {"probe": Dictionary} oder {"task": TaskDef, "role": String};
## "last": Name der zuletzt geprüften Kreatur (für die Einführung)
var _gallery_for: Dictionary = {}
## Uhrzeit der Welt, während die Bühne nachts spielt
var _saved_hour := -1.0
var _history_seen: Dictionary = {}  # BehaviorBrain -> Anzahl bereits gesehener Einträge
var _autosave := AUTOSAVE_SECONDS
var _save_pending := false


func _ready() -> void:
	if get_tree().root.has_meta("building_forest"):
		set_process(false)
		set_physics_process(false)
		return
	saving_enabled = not get_tree().root.has_meta("forest_no_save")
	var l := terrain.layout
	camera.bounds = Rect2(-l.size * 0.5, l.size)
	camera.ground_height = func(x: float, z: float) -> float: return l.height_at(x, z)
	camera.target = Vector3(l.spawn_pos.x, l.height_at(l.spawn_pos.x, l.spawn_pos.y), l.spawn_pos.y)
	camera.tapped.connect(_on_tap)
	weather.register_water(terrain.water_material)
	navigation.baked.connect(func(): print("Navmesh gebacken in %d ms" % navigation.bake_msec))
	navigation.bake_from_terrain()

	_rival_rng.randomize()
	game = GameState.load_file() if saving_enabled and GameState.exists() else null
	if game == null or not game.is_valid():
		if game != null:
			push_warning("Spielstand unlesbar, neues Spiel: %s" % [game.errors])
		game = GameState.new_game()
	if not game.is_valid():
		push_error("\n".join(game.errors))
		return
	graphics_level = GraphicsSettings.load_level()
	GraphicsSettings.apply(graphics_level, get_node_or_null("Sun"), get_viewport())
	day_night.set_process(false)  # die Uhr folgt den Phasen der Runde
	day_night.hour = PHASE_HOURS.get(game.phase, 10.0)
	day_night.apply_lighting()
	weather.set_state(game.weather)
	weather.auto_change = false
	catalog = AbilityCatalog.load_file(game.schema)
	tasks = TaskCatalog.load_dir(catalog)
	if not tasks.errors.is_empty():
		push_error("\n".join(tasks.errors))
	game.journal.changed.connect(func(): _save_pending = true)
	show_names = UiSettings.show_names()
	_build_stage()
	_build_hud()
	for i in game.members.size():
		_spawn_member(game.members[i], _spawn_point(l, i))
	for o in game.offers:
		_spawn_stranger(o)
	_spawn_rivals()
	_ensure_needed_offer()
	_spawn_items(l)
	_update_tags()
	sync_sites()
	game.journal.changed.connect(func():
		if game.intro_step == 2 and _rating_count() > _intro_ratings:
			_intro_next())
	_update_phase_ui()
	if not game.pending_task.is_empty():
		_resume_or_enter.call_deferred()
	elif game.intro_step < GameState.INTRO_DONE:
		_intro_show.call_deferred()
	else:
		_enter_phase.call_deferred()
	_hook_web_save()


func _exit_tree() -> void:
	# Zeitraffer gilt nur in der Waldwelt (Engine.time_scale ist global)
	if _skipping:
		debug_speed(1.0)


func _notification(what: int) -> void:
	# Android/iOS beenden Apps im Hintergrund ohne Vorwarnung – beim Pausieren speichern
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		save_game()


## Web-App: speichern, sobald die Seite verborgen wird (App-Wechsel, Bildschirmsperre)
## – iOS lädt Web-Apps danach oft neu.
func _hook_web_save() -> void:
	if not OS.has_feature("web"):
		return
	_web_save_cb = JavaScriptBridge.create_callback(func(_args): save_game())
	var doc = JavaScriptBridge.get_interface("document")
	var win = JavaScriptBridge.get_interface("window")
	if doc != null:
		doc.addEventListener("visibilitychange", _web_save_cb)
	if win != null:
		win.addEventListener("pagehide", _web_save_cb)


func save_game() -> void:
	if not saving_enabled or game == null or not is_inside_tree():
		return
	game.hour = PHASE_HOURS.get(game.phase, day_night.hour)
	game.weather = weather.state
	game.save()
	_save_pending = false


func _physics_process(delta: float) -> void:
	for b in brains:
		b.update(delta)
	_separate(delta)
	_observe()
	_autosave -= delta
	if _autosave <= 0.0 or (_save_pending and _autosave < AUTOSAVE_SECONDS - 3.0):
		_autosave = AUTOSAVE_SECONDS
		save_game()


func _process(delta: float) -> void:
	perf.tick()
	if game == null or _status == null:
		return
	if game.intro_step == 2:
		_intro_timer += delta
		if _intro_timer > 40.0:
			_intro_next()
	_credits.text = "%d %s" % [game.credits, GameState.currency()]
	_update_score()
	var extra := ""
	if debug_mode:
		var st := perf.stats()
		var lod := PerfMonitor.lod_counts(creatures)
		extra = "\nFPS %d · Frame %.1f ms (95 %%: %.1f, max %.1f) · Draw-Calls %d · Grafik %s\nLOD voll %d · reduziert %d · eingefroren %d · aus %d · Licht %d %% · Nässe %d %%" % [
			Engine.get_frames_per_second(), st.avg, st.p95, st.max,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), GraphicsSettings.LABELS[graphics_level],
			lod[0], lod[1], lod[2], lod[3], int(day_night.light_level() * 100.0), int(weather.wetness * 100.0)]
	_status.text = "Runde %d/%d · %s · Wetter %s · Gruppe: %d%s" % [
		mini(game.round_number(), int(game.season.get("days", 7))), int(game.season.get("days", 7)),
		ROUND_PHASE_LABELS.get(game.phase, ""), WEATHER_LABELS[weather.state], game.members.size(), extra]
	if _busy:
		_info.text = ""
	elif selected != null and _member_of(selected) != null:
		_info.text = "%s: %s" % [_member_of(selected).name, selected.behavior_label if selected.behavior_label != "" else "…"]
	else:
		_info.text = "Tippe eine Kreatur an, um sie zu beobachten."


# --- Kreaturen ----------------------------------------------------------------

func _member_of(c: Creature) -> GroupMember:
	if rival_creatures.has(c):
		return rival_creatures[c][1]
	return members.get(c, strangers.get(c))


## Fremder am Waldrand: eigene Heimat, kleiner Streifradius.
func _spawn_stranger(o: GroupMember) -> Creature:
	var home := _stranger_home(o)
	var c := _spawn_member(o, home, true)
	var b := brains[creatures.find(c)]
	b.home = Vector3(home.x, 0.0, home.z)
	b.roam_radius = STRANGER_ROAM
	return c


func _stranger_home(o: GroupMember) -> Vector3:
	var l := terrain.layout
	var rng := RngUtil.make_rng(["stranger", l.seed_value, o.id])
	for attempt in 40:
		var a := rng.randf_range(0.0, TAU)
		var r := STRANGER_DISTANCE + rng.randf_range(-2.0, 3.0)
		var x := l.spawn_pos.x + cos(a) * r
		var z := l.spawn_pos.y + sin(a) * r
		if l.zone_at(x, z) in ["forest", "clearing"]:
			return Vector3(x, l.height_at(x, z), z)
	return _spawn_point(l, creatures.size() + 7)


func _spawn_member(m: GroupMember, pos: Vector3, stranger := false) -> Creature:
	var c := Creature.new()
	c.name = m.id.replace("#", "_")
	c.position = pos
	c.rotation.y = TAU * float(creatures.size()) / 7.0
	creature_root.add_child(c)
	c.setup_individual(m.to_individual(), m.name)
	c.label = m.name
	c.abilities = AbilityProfile.new(catalog, m.genome)
	creatures.append(c)
	if stranger:
		strangers[c] = m
	else:
		members[c] = m
	var l := terrain.layout
	var brain := BehaviorBrain.new(c, navigation, context, Vector3(l.spawn_pos.x, 0.0, l.spawn_pos.y), RngUtil.derive_seed(["brain", m.id]))
	brain.roam_radius = 16.0
	brain.mover.others = creatures
	brains.append(brain)
	return c


## Kreaturen laufen nicht durcheinander hindurch: überlappende Grundflächen
## werden auseinandergeschoben (höchstens SEPARATE_SPEED m/s, nicht ins Wasser).
## Kreaturen mit Skript-Bewegung (Klettern, Schwimmen …) werden nicht verschoben.
func _separate(delta: float) -> void:
	var l := terrain.layout
	var max_step := SEPARATE_SPEED * delta
	for i in creatures.size():
		var a := creatures[i]
		if not a.visible:
			continue
		for j in range(i + 1, creatures.size()):
			var b := creatures[j]
			if not b.visible or (a.scripted and b.scripted):
				continue
			var d := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
			var r := a.radius + b.radius
			var dist := d.length()
			if dist >= r:
				continue
			var n := d / dist if dist > 0.001 else Vector2(1, 0)
			var share_a := _push_share(a, b)
			# wer beiseitegestupst wird, weicht zügiger
			var step := max_step * (3.0 if share_a != 0.5 else 1.0)
			var overlap := minf(r - dist, step * 2.0)
			_nudge(a, -n * overlap * share_a, l)
			_nudge(b, n * overlap * (1.0 - share_a), l)


## Anteil der Überlappung, um den a verschoben wird (Rest: b). Skript-Bewegung
## wird nie verschoben; sonst weicht, wer weniger Vorrang hat oder stillsteht.
func _push_share(a: Creature, b: Creature) -> float:
	if a.scripted:
		return 0.0
	if b.scripted:
		return 1.0
	if a.priority != b.priority:
		return 0.1 if a.priority > b.priority else 0.9
	var a_moving := a.velocity.length() > NavMover.STILL_SPEED
	var b_moving := b.velocity.length() > NavMover.STILL_SPEED
	if a_moving != b_moving:
		return 0.15 if a_moving else 0.85
	return 0.5


func _nudge(c: Creature, offset: Vector2, l: ForestLayout) -> void:
	if offset.length_squared() < 0.0000001:
		return
	var p := c.global_position + Vector3(offset.x, 0.0, offset.y)
	if l.zone_at(p.x, p.z) in ["water", "outside"] and l.zone_at(c.global_position.x, c.global_position.z) != "water":
		return
	c.global_position = p


## Tragbare Steine auf der Lichtung (für das Trage-Verhalten).
func _spawn_items(l: ForestLayout) -> void:
	for i in 8:
		var rng := RngUtil.make_rng(["item", l.seed_value, i])
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(1.0, l.spawn_radius + 2.0)
		var x := l.spawn_pos.x + cos(a) * r
		var z := l.spawn_pos.y + sin(a) * r
		var item := CarryItem.new()
		item.size = [0.12, 0.18, 0.25, 0.32, 0.4, 0.15, 0.22, 0.48][i]
		item.seed_value = i
		item.position = Vector3(x, l.height_at(x, z), z)
		creature_root.add_child(item)


func _spawn_point(l: ForestLayout, i: int) -> Vector3:
	var rng := RngUtil.make_rng(["spawn", l.seed_value, i])
	for attempt in 30:
		var a := rng.randf_range(0.0, TAU)
		var r := sqrt(rng.randf()) * l.spawn_radius
		var x := l.spawn_pos.x + cos(a) * r
		var z := l.spawn_pos.y + sin(a) * r
		if l.zone_at(x, z) in ["clearing", "forest"]:
			return Vector3(x, l.height_at(x, z), z)
	return Vector3(l.spawn_pos.x, l.height_at(l.spawn_pos.x, l.spawn_pos.y), l.spawn_pos.y)


## Neue Verhaltensergebnisse beobachteter Kreaturen ins Journal schreiben.
func _observe() -> void:
	if game == null:
		return
	for i in brains.size():
		var b := brains[i]
		var seen: int = _history_seen.get(b, 0)
		if b.history.size() == seen:
			continue
		_history_seen[b] = b.history.size()
		var entry: Dictionary = b.history[-1]
		if entry.id == "wander" or not PAST.has(entry.id):
			continue
		var c := creatures[i]
		if not c.visible or c.global_position.distance_to(camera.global_position) > OBSERVE_DISTANCE \
				or camera.is_position_behind(c.global_position):
			continue
		var h := day_night.hour
		var text: String = PAST[entry.id] + OUTCOME.get(entry.outcome, "")
		game.journal.add_log("%02d:%02d" % [int(h), int(fposmod(h, 1.0) * 60.0)], _member_of(c).id, text)
		if c == selected and _card.visible:
			_select(c)


func _on_tap(pos: Vector2) -> void:
	if _busy:
		return
	_select(creature_at(pos))


## Kreatur unter einem Bildschirmpunkt (oder null).
func creature_at(pos: Vector2) -> Creature:
	var best: Creature = null
	var best_d := 70.0
	for c in creatures:
		if not c.visible or camera.is_position_behind(c.global_position):
			continue
		var d := camera.unproject_position(c.global_position + Vector3.UP * c.plan.body_center_y).distance_to(pos)
		if d < best_d:
			best_d = d
			best = c
	return best


# --- Einführung ------------------------------------------------------------------
## 0 Begrüßung · 1 erste Probe (Klettern) · 2 Einschätzung festhalten ·
## 3 erste Aufgabe öffnen. Danach INTRO_DONE.

func _intro_show() -> void:
	match game.intro_step:
		0:
			_intro.open()
		1:
			if game.phase == "rivals":
				_apply_rival_turn()  # in der Einführung ohne Bühnenszene
			game.phase = "probes"
			_update_phase_ui()
			_intro_banner("Wer von euch kommt einen Baum hinauf? Auf der Lichtung steht ein Stamm mit zwei Ringen und einer Frucht. Wähle unten eine Kreatur für die Kletterprobe.")
			open_probe(probe_catalog.get_probe("climb"))
		2:
			_intro_timer = 0.0
			_intro_ratings = _rating_count()
			var who := str(_gallery_for.get("last", ""))
			_intro_banner("Gut beobachtet! Halte unten fest, wie gut %s klettert: – schwach, o mittel, + stark." % (who if who != "" else "sie"))
		3:
			game.intro_step = GameState.INTRO_DONE
			_banner.visible = false
			set_phase("task")


func _rating_count() -> int:
	var n := 0
	for id in game.journal.ratings:
		n += game.journal.ratings[id].size()
	return n


func _intro_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true


func _intro_next() -> void:
	game.intro_step += 1
	_intro_show()


func _select(c: Creature) -> void:
	selected = c
	camera.follow = c
	if c == null:
		_card.visible = false
		return
	camera.distance = clampf(camera.distance, 4.0, 10.0)
	if rival_creatures.has(c):
		_card.show_rival(rival_creatures[c][1], rival_creatures[c][0].name, game.journal, _debug_text(c))
	elif strangers.has(c):
		var o: GroupMember = strangers[c]
		_card.show_stranger(o, o.name, game.journal, game.hire_problem(o), _debug_text(c))
	else:
		_card.show_member(members[c], game.journal, catalog, _debug_text(c))


func _debug_text(c: Creature) -> String:
	if not debug_mode:
		return ""
	var m := _member_of(c)
	var parts := []
	for entry in c.abilities.ranked():
		parts.append("%s %d" % [catalog.name_of(entry[0]), int(entry[1] * 100)])
	return "Debug – Art: %s\nWahre Fähigkeitswerte (0–100, ändern sich nicht durch deine Einschätzung):\n%s" % [
			game.taxonomy.get_taxon(m.species_id).display_name(), " · ".join(parts)]


# --- Aufgaben -----------------------------------------------------------------

func start_task(task: TaskDef, assignments: Dictionary) -> void:
	var attempt: int = game.tasks.get(task.id, {}).get("attempts", 0)
	var result := TaskSimulator.simulate(task, assignments, catalog, attempt, _crossing_depth(task))
	# Ergebnis sofort sichern: wird die App während der Wiedergabe beendet
	# (iOS beendet Web-Apps im Hintergrund), wertet der nächste Start es aus
	var ids := {}
	for role_id in assignments:
		ids[role_id] = assignments[role_id].id
	game.pending_task = {"task": task.id, "assignments": ids, "result": _json_safe(result)}
	save_game()
	var role_names := {}
	for role_id in assignments:
		role_names[role_id] = assignments[role_id].name
	enter_stage()
	await director.run_task(task, result, assignments, _crossing_depth(task))
	leave_stage()
	_on_task_finished(result, task, role_names, assignments)


static func _json_safe(result: Dictionary) -> Dictionary:
	var r := result.duplicate(true)
	r.hints = Array(r.get("hints", []))
	return r


func _resume_or_enter() -> void:
	if not _resume_pending_task():
		_enter_phase()


## Beim Start: eine unterbrochene Aufgabe auswerten (Ergebnis stand schon fest).
## false = keine (gültige) Aufgabe offen.
func _resume_pending_task() -> bool:
	var p := game.pending_task
	if p.is_empty():
		return false
	var task := tasks.get_task(str(p.get("task", "")))
	var assignments := {}
	var role_names := {}
	for role_id in p.get("assignments", {}):
		var m := game.member(str(p.assignments[role_id]))
		if m != null:
			assignments[role_id] = m
			role_names[role_id] = m.name
	if task == null or assignments.size() != task.roles.size():
		game.pending_task = {}
		return false
	var result: Dictionary = p.get("result", {})
	result.hints = PackedStringArray(result.get("hints", []))
	_show_note("Die Aufgabe „%s“ wurde unterbrochen – hier ist ihr Ergebnis." % task.name, 4.0)
	_on_task_finished(result, task, role_names, assignments)
	return true


func creature_of(m: GroupMember) -> Creature:
	for c in members:
		if members[c] == m:
			return c
	for c in strangers:
		if strangers[c] == m:
			return c
	for c in rival_creatures:
		if rival_creatures[c][1] == m:
			return c
	return null


func _on_task_finished(result: Dictionary, task: TaskDef, role_names: Dictionary, assignments: Dictionary = {}) -> void:
	var failed := []
	for role_id in assignments:
		var e: Dictionary = result.roles.get(role_id, {})
		if not e.get("success", false) and not e.get("skipped", false):
			failed.append(assignments[role_id])
	var outcome := game.record_task(task, result.success, failed)
	game.pending_task = {}
	game.round_log.append({"who": "player", "earned": int(outcome.earned) - int(outcome.cost),
			"text": "Du: „%s“ %s (%s)" % [task.name, "geschafft" if result.success else "nicht geschafft",
			("+%d" % outcome.earned) if result.success else ("−%d" % outcome.cost)]})
	if game.phase == "task":
		game.phase = "evening"
	sync_sites()
	for o in outcome.new_offers:
		_spawn_stranger(o)
	if result.success:
		_ensure_needed_offer()
	save_game()
	_banner.visible = false
	_update_tags()
	_update_phase_ui()
	_result_panel.show_result(task, result, role_names, outcome, assignments, game.journal, catalog)


## Geräusche einer Kreatur sind nur hörbar, wenn sie im Fokus ist (ausgewählt,
## verfolgt oder in der Aufgabe am Zug), nicht zu weit weg und im Bild.
func is_sound_focus(source: Node) -> bool:
	var c := source as Creature
	if c == null or not c.visible:
		return false
	if _busy:
		return stage.actors.has(c)
	var focused := c == selected or c == camera.follow
	if not focused:
		return false
	if camera.is_position_behind(c.global_position) or c.global_position.distance_to(camera.global_position) > SOUND_DISTANCE:
		return false
	var p := camera.unproject_position(c.global_position)
	return get_viewport().get_visible_rect().has_point(p)


## Kreatur oberhalb der Leiste halten: Drehpunkt im Bild so weit nach oben, wie die Leiste hoch ist.
func _update_view_shift() -> void:
	_info.visible = not _card.visible  # die Leiste zeigt den Namen ohnehin
	if _card.visible:
		camera.view_shift = _card.height_fraction() * VIEW_SHIFT_FACTOR
	else:
		camera.view_shift = 0.0


## Reihenfolge beim Durchblättern: Gruppe (wie im Spielstand), dann Fremde.
func browse_order() -> Array[Creature]:
	var list: Array[Creature] = []
	for m in game.members:
		var c := creature_of(m)
		if c != null:
			list.append(c)
	for o in game.offers:
		var c := creature_of(o)
		if c != null:
			list.append(c)
	return list


## Nächste (+1) bzw. vorherige (-1) Kreatur auswählen.
func cycle_selection(direction: int) -> void:
	var list := browse_order()
	if list.is_empty():
		return
	var i := list.find(selected)
	_select(list[posmod(i + direction, list.size())] if i >= 0 else list[0])


## Unter den Fremden muss jemand sein, der eine fehlende Rolle übernehmen kann.
func _ensure_needed_offer() -> void:
	var r := game.ensure_needed_offer(game.needed_species(tasks, catalog))
	for o in r.removed:
		var c := creature_of(o)
		if c != null:
			_despawn(c)
	for o in r.added:
		_spawn_stranger(o)


func _despawn(c: Creature) -> void:
	var i := creatures.find(c)
	if i < 0:
		return
	creatures.remove_at(i)
	brains.remove_at(i)
	strangers.erase(c)
	members.erase(c)
	rival_creatures.erase(c)
	if selected == c:
		_select(null)
	c.queue_free()


# --- Bühne, Proben und Galerie -------------------------------------------------

func _build_stage() -> void:
	stage = Stage.new()
	stage.name = "Stage"
	add_child(stage)
	stage.position = STAGE_ORIGIN
	stage.build(terrain.ground_layer)
	stage.visible = false
	stage.caption.connect(func(text: String):
		_banner.text = text
		_banner.visible = true)
	probe_catalog = ProbeCatalog.load_file()
	director = StageDirector.new(stage, catalog, probe_catalog, set_stage_night)


## Zur Bühne wechseln: eigene Kamera, Uhr steht, nur „Überspringen“ sichtbar.
func enter_stage() -> void:
	_busy = true
	for panel in [_card, _task_panel, _journal_panel, _hire_panel, _gallery, _probe_panel, _round_panel]:
		panel.visible = false
	stage.visible = true
	stage.camera.current = true
	_hud_top.visible = false
	_score_box.visible = false
	_banner.offset_top = 12
	_skip.visible = true
	_skipping = false


## Zurück ins Lager.
func leave_stage() -> void:
	stage.clear()
	stage.visible = false
	camera.make_current()
	for c in creatures:
		c.refresh_lod()  # im Lager war während der Bühne alles ausgeblendet (zu weit weg)
	_hud_top.visible = true
	_score_box.visible = true
	_banner.offset_top = 150
	_skip.visible = false
	_banner.visible = false
	if _skipping:
		_skipping = false
		debug_speed(1.0)
	_busy = false


## Bühne nachts spielen lassen: Himmel wie um 23 Uhr, Scheinwerfer an.
func set_stage_night(on: bool) -> void:
	if on and _saved_hour < 0.0:
		_saved_hour = day_night.hour
		day_night.hour = 23.0
	elif not on and _saved_hour >= 0.0:
		day_night.hour = _saved_hour
		_saved_hour = -1.0
	day_night.apply_lighting()
	stage.set_night(on)


func probes_left() -> int:
	return maxi(0, PROBES_PER_DAY - game.probes_today)


func open_probe_panel() -> void:
	if _busy:
		return
	_card.visible = false
	_probe_panel.open(probe_catalog, catalog, probes_left())


## Probe gewählt → in der Galerie die Kreatur bestimmen.
func open_probe(probe: Dictionary) -> void:
	if probe.is_empty() or probes_left() <= 0:
		return
	_card.visible = false
	_gallery_for = {"probe": probe, "last": _gallery_for.get("last", "")}
	_gallery.open("%s: Wer soll es versuchen?" % probe.name, _gallery_group(), [], game.journal, catalog, str(probe.ability))


## Rollenwahl aus der Galerie (statt in der Welt suchen); Fremde sind dabei.
func open_role_gallery(task: TaskDef, role_id: String) -> void:
	var role := task.role(role_id)
	_card.visible = false
	_gallery_for = {"task": task, "role": role_id, "last": _gallery_for.get("last", "")}
	_gallery.open("Wähle: %s" % role.name, _gallery_group(), game.offers.duplicate(), game.journal, catalog,
			TaskPanel.main_ability(role), true)


## Gruppe für die Galerie: fitte zuerst, Erschöpfte hinten.
func _gallery_group() -> Array:
	var fit := []
	var tired := []
	for m in game.members:
		if m.exhausted:
			tired.append(m)
		else:
			fit.append(m)
	return fit + tired


func _on_gallery_chosen(m: GroupMember) -> void:
	var g := _gallery_for
	if g.has("probe"):
		run_probe(m, g.probe)
	elif g.has("task"):
		if game.offers.has(m) and not hire(m):
			_show_note(game.hire_problem(m) if game.hire_problem(m) != "" else "Anheuern nicht möglich.")
			_task_panel.open(game, tasks, g.task, catalog)
			return
		_task_panel.assign(g.role, m, g.task)
		_task_panel.open(game, tasks, g.task, catalog)


func _on_gallery_cancelled() -> void:
	if _gallery_for.has("task"):
		_task_panel.open(game, tasks, _gallery_for.task, catalog)
	elif game.intro_step == 1:
		# Einführung: ohne Probe weiter zur Einschätzung
		_intro_next()


## Probe auf der Bühne abspielen und das Ergebnis im Journal festhalten.
func run_probe(m: GroupMember, probe: Dictionary) -> void:
	if _busy or probes_left() <= 0:
		return
	var trial := int(game.journal.probes.get(m.id, {}).size()) + game.probes_today * 7 + int(game.season.get("day", 1)) * 31
	var g := probe_catalog.grade(m, probe, catalog, trial)
	game.probes_today += 1
	game.journal.set_probe(m.id, str(probe.ability), g)
	var h := day_night.hour
	game.journal.add_log("%02d:%02d" % [int(h), int(fposmod(h, 1.0) * 60.0)], m.id,
			"%s: %s %s" % [probe.name, probe_catalog.result_text(probe, g), Journal.grade_dots(g)])
	_gallery_for.last = m.name
	save_game()
	enter_stage()
	await director.run_probe(m, probe, g)
	leave_stage()
	_update_phase_ui()
	var c := creature_of(m)
	if c != null:
		_select(c)
		_card.show_quick(str(probe.ability))
	if game.intro_step == 1:
		_intro_next()


# --- Runden ---------------------------------------------------------------------

## In eine Phase der Runde wechseln (Uhrzeit, Knöpfe) und sie beginnen.
func set_phase(p: String) -> void:
	game.phase = p
	save_game()
	_enter_phase()


## Die aktuelle Phase beginnen (auch nach dem Laden).
func _enter_phase() -> void:
	if game == null or _busy:
		return
	if game.round_number() > int(game.season.get("days", 7)):
		_show_season_end()
		return
	day_night.hour = PHASE_HOURS.get(game.phase, 10.0)
	day_night.apply_lighting()
	_update_phase_ui()
	match game.phase:
		"rivals":
			play_rival_turn()
		"probes":
			if game.round_offers.is_empty():
				game.pick_round_offers(tasks)
		"task":
			if game.round_offers.is_empty():
				game.pick_round_offers(tasks)
			open_task_offers()
		"evening":
			_open_evening()


## Knöpfe und Anzeigen zur Phase.
func _update_phase_ui() -> void:
	if _phase_button == null or game == null:
		return
	_phase_button.disabled = false
	_next_button.visible = true
	match game.phase:
		"rivals":
			_phase_button.text = "Zug der Rivalen …"
			_phase_button.disabled = true
			_next_button.visible = false
		"probes":
			_phase_button.text = "Probe (%d)" % probes_left()
			_phase_button.disabled = probes_left() <= 0
			_next_button.text = "Weiter: Aufgabe ›"
		"task":
			_phase_button.text = "Aufgabe wählen"
			_next_button.text = "Ohne Aufgabe: Abend ›"
		"evening":
			_phase_button.text = "Abend"
			_next_button.text = "Nächste Runde ›" if game.round_number() < int(game.season.get("days", 7)) else "Saison abschließen ›"
	day_night.hour = PHASE_HOURS.get(game.phase, day_night.hour)
	day_night.apply_lighting()


func _on_phase_button() -> void:
	if _busy:
		return
	match game.phase:
		"probes":
			open_probe_panel()
		"task":
			open_task_offers()
		"evening":
			_open_evening()


func _on_next_button() -> void:
	if _busy:
		return
	match game.phase:
		"probes":
			set_phase("task")
		"task":
			set_phase("evening")
		"evening":
			next_round()


## Aufgabenwahl mit den Angeboten der Runde.
func open_task_offers() -> void:
	_card.visible = false
	_task_panel.open(game, tasks, null, catalog, game.round_offers)


## Zug der Rivalen ausführen (Entscheidungen, Ergebnisse, Anheuern) – ohne Szene.
## Danach steht die Runde in der Phase „probes“. Rückgabe: [[RivalState, Ereignis]].
func _apply_rival_turn() -> Array:
	var events := []
	for r in game.rivals:
		for ev in RivalAI.take_turn(game, r, tasks, catalog, _rival_rng):
			_on_rival_event(r, ev)
			events.append([r, ev])
			if ev.type in ["task", "hire"]:
				game.round_log.append({"who": r.id, "text": ev.text, "earned": int(ev.get("earned", 0)) - int(ev.get("cost", 0))})
	game.phase = "probes"
	game.round_offers = []
	game.pick_round_offers(tasks)
	_ensure_needed_offer()
	save_game()
	return events


## Zug der Rivalen als Bühnenszene: ihre Aufgaben laufen ab (Überspringen = Zeitraffer),
## danach eine Übersicht; dann beginnen die Proben.
func play_rival_turn() -> void:
	var events := _apply_rival_turn()
	_update_phase_ui()
	var attempts := events.filter(func(e): return e[1].type == "task")
	if not attempts.is_empty():
		enter_stage()
		for e in attempts:
			var r: RivalState = e[0]
			var ev: Dictionary = e[1]
			stage.caption.emit("%s: „%s“" % [r.name, ev.task.name])
			await stage.wait(1.2)
			await director.run_task(ev.task, ev.result, ev.assignments, _crossing_depth(ev.task))
		leave_stage()
	var lines := []
	for e in events:
		var ev: Dictionary = e[1]
		match str(ev.type):
			"task":
				lines.append([ev.text, RoundPanel.GOOD if ev.result.success else RoundPanel.BAD])
			"hire":
				lines.append([ev.text, RoundPanel.NOTE])
	var watched := events.filter(func(e): return e[1].type == "observe").size()
	if watched > 0:
		lines.append(["%s beobachteten ihre Tiere (%d×)." % [game.rivals[0].name if not game.rivals.is_empty() else "Die Rivalen", watched], RoundPanel.NOTE])
	if lines.is_empty():
		lines.append(["Die Rivalen ruhten sich aus.", RoundPanel.NOTE])
	lines.append([_standings(), Color(0.95, 0.85, 0.4)])
	_round_next = func(): _enter_phase()
	_round_panel.open("Zug der Rivalen", "Runde %d/%d" % [game.round_number(), int(game.season.get("days", 7))], lines,
			"Weiter zu den Proben ›")


func _standings() -> String:
	var parts := ["Du %d" % game.points]
	for r in game.rivals:
		parts.append("%s %d" % [r.name, r.points])
	return "Stand: " + " · ".join(parts)


## Abend: erst die Artfrage (falls eine ansteht), dann die Übersicht der Runde.
func _open_evening() -> void:
	_card.visible = false
	var q := game.species_question()
	if not q.is_empty() and not game.round_log.any(func(e): return e.get("who", "") == "question"):
		game.round_log.append({"who": "question", "text": ""})
		_question.open(game, q.a, q.b)
		return
	_show_evening()


func _show_evening() -> void:
	var lines := []
	var mine := game.round_log.filter(func(e): return e.get("who", "") == "player")
	if mine.is_empty():
		lines.append(["Du hast heute keine Aufgabe versucht.", RoundPanel.NOTE])
	for e in game.round_log:
		if e.get("text", "") != "" and e.get("who", "") != "question":
			lines.append([e.text, RoundPanel.GOOD if int(e.get("earned", 0)) > 0 else (RoundPanel.BAD if int(e.get("earned", 0)) < 0 else RoundPanel.NOTE)])
	lines.append([_standings(), Color(0.95, 0.85, 0.4)])
	var tired := game.members.filter(func(m): return m.exhausted).size()
	lines.append(["Über Nacht erholen sich alle%s; die Vorräte wachsen nach." % (" (%d erschöpft)" % tired if tired > 0 else ""), RoundPanel.NOTE])
	var last := game.round_number() >= int(game.season.get("days", 7))
	_round_next = next_round
	_round_panel.open("Abend", "Runde %d/%d" % [game.round_number(), int(game.season.get("days", 7))], lines,
			"Saison abschließen ›" if last else "Nächste Runde ›", "Noch umsehen")


## Runde beenden: Nacht, Erholung; nächste Runde (oder Saisonende).
func next_round() -> void:
	if _busy:
		return
	_round_panel.visible = false
	var over := game.end_round()
	_roll_weather()
	sync_sites()
	_update_tags()
	if over:
		_show_season_end()
		return
	_show_note("Ein neuer Morgen – alle sind ausgeruht.")
	set_phase("rivals")


## Schlusswertung der Saison (auch nach dem Laden, ohne sie doppelt einzutragen).
func _show_season_end() -> void:
	_card.visible = false
	var hist: Array = game.season.get("history", [])
	var res: Dictionary = hist[-1] if not hist.is_empty() and int(hist[-1].get("number", 0)) == int(game.season.get("number", 1)) \
			else game.finish_season()
	_season_panel.open(res)
	_season_panel.move_to_front()
	save_game()
	_update_phase_ui()


## Wetter der neuen Runde (meist klar).
func _roll_weather() -> void:
	var x := _rival_rng.randf()
	weather.set_state("rain" if x < 0.12 else ("cloudy" if x < 0.35 else "clear"))
	game.weather = weather.state


# --- Anheuern -----------------------------------------------------------------

func hire(offer: GroupMember) -> bool:
	var c := creature_of(offer)
	if not game.hire(offer):
		return false
	if c != null:
		strangers.erase(c)
		members[c] = offer
		c.label = offer.name
		var b := brains[creatures.find(c)]
		var l := terrain.layout
		b.home = Vector3(l.spawn_pos.x, 0.0, l.spawn_pos.y)
		b.roam_radius = 16.0
	_update_tags()
	save_game()
	if _hire_panel.visible:
		_hire_panel.open(game)
	if c != null and selected == c:
		_select(c)
	_show_note("%s gehört jetzt zur Gruppe." % offer.name)
	Sound.play("coin")
	Sound.vibrate(30)
	return true


# --- Namensschilder und Hinweis -------------------------------------------------

func _update_tags() -> void:
	for c in creatures:
		if not show_names or test_creatures.has(c):
			c.set_tag("")
		elif rival_creatures.has(c):
			var rv: RivalState = rival_creatures[c][0]
			var rm: GroupMember = rival_creatures[c][1]
			c.set_tag("%s · %s%s" % [rm.name, rv.name, " · erschöpft" if rm.exhausted else ""], rv.color)
		elif strangers.has(c):
			c.set_tag("%s · %d %s" % [strangers[c].name, strangers[c].price, GameState.currency()], TAG_STRANGER)
		elif members.has(c):
			var m: GroupMember = members[c]
			c.set_tag(m.name + (" · erschöpft" if m.exhausted else ""), TAG_TIRED if m.exhausted else TAG_MEMBER)


## Sichtbare Früchte an den Bäumen = Vorrat der Fundstellen.
func sync_sites() -> void:
	var cfg := GameState.sites_config()
	for id in game.sites:
		var c: Dictionary = cfg.get(id, {})
		if c.has("tree") and int(c.tree) < terrain.fruit_trees.size():
			terrain.fruit_trees[int(c.tree)].set_visible_fruits(int(game.sites[id]))


func _update_score() -> void:
	var parts := ["Du %d" % game.points]
	for r in game.rivals:
		parts.append("%s %d" % [r.name, r.points])
	_score.text = " · ".join(parts)
	_season_label.text = "Saison %d · Runde %d/%d · Gegner: %s" % [int(game.season.get("number", 1)),
			mini(int(game.season.get("day", 1)), int(game.season.get("days", 7))), int(game.season.get("days", 7)),
			RivalState.difficulty(game.difficulty).get("label", game.difficulty)]


func _start_next_season(difficulty: String) -> void:
	for c in rival_creatures.keys():
		_despawn(c)
	game.difficulty = difficulty
	game.start_season(int(game.season.get("number", 1)) + 1)
	_spawn_rivals()
	sync_sites()
	_update_tags()
	_show_note("Saison %d beginnt – Gegner: %s" % [int(game.season.number), RivalState.difficulty(difficulty).get("label", difficulty)])
	set_phase("rivals")


func _cycle_difficulty() -> void:
	var order: Array = RivalState.config().get("order", ["gemütlich", "normal", "ehrgeizig"])
	game.difficulty = order[(order.find(game.difficulty) + 1) % order.size()]
	_difficulty_button.text = "Gegner: " + str(RivalState.difficulty(game.difficulty).get("label", game.difficulty))
	_save_pending = true


# --- Rivalen ----------------------------------------------------------------------

func _spawn_rivals() -> void:
	for r in game.rivals:
		for m in r.members:
			_spawn_rival_member(r, m)


func _spawn_rival_member(r: RivalState, m: GroupMember) -> Creature:
	var home := _camp_point(r, m)
	var c := _spawn_member(m, home, true)
	strangers.erase(c)
	rival_creatures[c] = [r, m]
	var b := brains[creatures.find(c)]
	b.home = Vector3(r.camp.x, 0.0, r.camp.y)
	b.roam_radius = RIVAL_ROAM
	return c


func _camp_point(r: RivalState, m: GroupMember) -> Vector3:
	var l := terrain.layout
	var rng := RngUtil.make_rng(["camp", l.seed_value, m.id])
	for attempt in 40:
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(0.0, 5.0)
		var x := r.camp.x + cos(a) * d
		var z := r.camp.y + sin(a) * d
		if l.zone_at(x, z) in ["forest", "clearing"]:
			return Vector3(x, l.height_at(x, z), z)
	return Vector3(r.camp.x, l.height_at(r.camp.x, r.camp.y), r.camp.y)


func _on_rival_event(r: RivalState, ev: Dictionary) -> void:
	match str(ev.type):
		"task":
			sync_sites()
			_update_tags()
		"hire":
			var c := creature_of(ev.member)
			if c != null:
				strangers.erase(c)
				rival_creatures[c] = [r, ev.member]
				var b := brains[creatures.find(c)]
				b.home = Vector3(r.camp.x, 0.0, r.camp.y)
				b.roam_radius = RIVAL_ROAM
			for o in game.refill_offers():
				_spawn_stranger(o)
			_ensure_needed_offer()
			_update_tags()
			if _hire_panel.visible:
				_hire_panel.open(game)
	_save_pending = true


## Kurze Einblendung oben (verschwindet nach ein paar Sekunden, nicht während Aufgaben).
func _show_note(text: String, seconds := 3.0) -> void:
	if _busy:
		return
	_banner.text = text
	_banner.visible = true
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func():
		if not _busy and _banner.text == text:
			_banner.visible = false)


## Wassertiefe an der Bachquerung der Aufgabe (für die Wat-Regel).
func _crossing_depth(task: TaskDef) -> float:
	for step in task.steps:
		if step.get("type", "") == "cross_stream":
			var p := task_point(task, str(step.place))
			var l := terrain.layout
			return l.water_level_at(p.x, p.z) - l.height_at(p.x, p.z)
	return 0.6


## Ort einer Aufgabe im Gelände (Namen aus task.places: "fruit_tree:0", "rock:largest",
## "stream_near:<ort>", "point:x,z"; sonst der Lagerplatz).
func task_point(task: TaskDef, place_name: String) -> Vector3:
	var l := terrain.layout
	var parts := str(task.places.get(place_name, place_name)).split(":")
	match parts[0]:
		"fruit_tree":
			return terrain.fruit_trees[clampi(int(parts[1]), 0, terrain.fruit_trees.size() - 1)].global_position
		"rock":
			var best: Dictionary = l.rocks[0]
			for r in l.rocks:
				if parts.size() > 1 and parts[1] == "largest" and r.size > best.size:
					best = r
			return Vector3(best.pos.x, l.height_at(best.pos.x, best.pos.y), best.pos.y)
		"stream_near":
			var ref := task_point(task, parts[1])
			var c: Vector2 = l.stream_info(ref.x, ref.z).closest
			return Vector3(c.x, l.water_level_at(c.x, c.y), c.y)
		"point":
			var xz := parts[1].split(",")
			return Vector3(float(xz[0]), l.height_at(float(xz[0]), float(xz[1])), float(xz[1]))
	return Vector3(l.spawn_pos.x, l.height_at(l.spawn_pos.x, l.spawn_pos.y), l.spawn_pos.y)


# --- HUD ----------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = Theme.new()
	ui.theme.default_font_size = 17
	layer.add_child(ui)
	var root := VBoxContainer.new()
	root.position = Vector2(12, 8)
	ui.add_child(root)
	_hud_top = root
	_status = _outlined_label()
	root.add_child(_status)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_button(bar, "Journal", func(): _card.visible = false; _journal_panel.open(game))
	_button(bar, "Anheuern", func(): _card.visible = false; _hire_panel.open(game))
	var more := _button(bar, "Optionen", Callable())
	_phase_button = _button(bar, "Probe", _on_phase_button)
	_phase_button.custom_minimum_size.x = 150
	_next_button = _button(bar, "Weiter ›", _on_next_button)
	_next_button.custom_minimum_size.x = 190
	var hi := StyleBoxFlat.new()
	hi.bg_color = Color(0.25, 0.42, 0.22, 0.92)
	hi.set_corner_radius_all(8)
	hi.set_content_margin_all(8)
	_next_button.add_theme_stylebox_override("normal", hi)
	_credits = _outlined_label()
	_credits.add_theme_font_size_override("font_size", 20)
	_credits.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_credits.custom_minimum_size = Vector2(120, 0)
	_credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_credits)

	# Optionen (eingeklappt): Gegner, Ton, Namen, Textgröße, Debug
	var opts := HBoxContainer.new()
	opts.visible = false
	root.add_child(opts)
	more.pressed.connect(func(): opts.visible = not opts.visible)
	_difficulty_button = _button(opts, "Gegner: " + str(RivalState.difficulty(game.difficulty).get("label", game.difficulty)), _cycle_difficulty)
	var snd := _button(opts, "Ton: an" if Sound.is_enabled() else "Ton: aus", Callable())
	snd.pressed.connect(func():
		Sound.set_enabled(not Sound.is_enabled())
		snd.text = "Ton: an" if Sound.is_enabled() else "Ton: aus")
	var names := _button(opts, "Namen: an" if show_names else "Namen: aus", Callable())
	names.pressed.connect(func():
		show_names = not show_names
		UiSettings.set_value("show_names", show_names)
		names.text = "Namen: an" if show_names else "Namen: aus"
		_update_tags())
	var text_size := _button(opts, "Text: " + UiSettings.scale_label(UiSettings.scale_setting()), Callable())
	text_size.pressed.connect(func():
		var next := UiSettings.next_scale_setting(UiSettings.scale_setting())
		UiSettings.set_value("scale", next)
		UiSettings.apply(get_tree().root)
		text_size.text = "Text: " + UiSettings.scale_label(next)
		_update_tags())
	var dbg := _button(opts, "Debug", Callable())
	var dbg_row := HBoxContainer.new()
	dbg_row.visible = false
	root.add_child(dbg_row)
	var gfx := _button(dbg_row, "Grafik: " + GraphicsSettings.LABELS[graphics_level], Callable())
	gfx.pressed.connect(func():
		graphics_level = GraphicsSettings.next_level(graphics_level)
		GraphicsSettings.save_level(graphics_level)
		GraphicsSettings.apply(graphics_level, get_node_or_null("Sun"), get_viewport())
		gfx.text = "Grafik: " + GraphicsSettings.LABELS[graphics_level])
	_button(dbg_row, "+5 Test", func(): add_test_creatures(5))
	_button(dbg_row, "Neues Spiel", debug_new_game)
	_button(dbg_row, "Entwicklermenü", func(): get_tree().change_scene_to_file(DebugNav.MENU))
	dbg.pressed.connect(func():
		debug_mode = not debug_mode
		dbg.text = "Debug: an" if debug_mode else "Debug"
		dbg_row.visible = debug_mode
		if selected != null:
			_select(selected))
	_info = _outlined_label()
	root.add_child(_info)

	# Punktestand (oben rechts)
	var score_box := VBoxContainer.new()
	score_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	score_box.offset_left = -360
	score_box.offset_right = -12
	score_box.offset_top = 8
	score_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	score_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(score_box)
	_season_label = _outlined_label()
	_season_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_season_label.add_theme_font_size_override("font_size", 14)
	score_box.add_child(_season_label)
	_score = _outlined_label()
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score.add_theme_font_size_override("font_size", 20)
	score_box.add_child(_score)
	_score_box = score_box

	# Einblendung der Aufgabenschritte (oben mittig, groß)
	_banner = _outlined_label()
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.add_theme_constant_override("outline_size", 6)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.05, 0.07, 0.06, 0.72)
	bsb.set_corner_radius_all(10)
	bsb.set_content_margin_all(10)
	_banner.add_theme_stylebox_override("normal", bsb)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_left = 0.15
	_banner.anchor_right = 0.85
	_banner.offset_left = 0
	_banner.offset_right = 0
	_banner.offset_top = 150
	_banner.visible = false
	ui.add_child(_banner)
	_skip = UiUtil.button("Überspringen", func():
		_skipping = true
		_skip.visible = false
		debug_speed(SKIP_SPEED), Vector2(170, 48))
	_skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.offset_left = -190
	_skip.offset_top = -64
	_skip.offset_right = -20
	_skip.offset_bottom = -16
	_skip.visible = false
	ui.add_child(_skip)

	_card = CreatureCard.new()
	_card.visible = false
	_card.closed.connect(func(): _select(null))
	_card.visibility_changed.connect(_update_view_shift)
	_card.layout_changed.connect(func(_e): _update_view_shift())
	_card.hire_requested.connect(hire)
	_card.cycle_requested.connect(cycle_selection)
	ui.add_child(_card)
	_journal_panel = JournalPanel.new()
	_journal_panel.member_chosen.connect(func(id):
		var c := creature_of(game.member(id))
		if c != null:
			_select(c))
	ui.add_child(_journal_panel)
	_task_panel = TaskPanel.new()
	_task_panel.start_requested.connect(start_task)
	_task_panel.pick_requested.connect(open_role_gallery)
	ui.add_child(_task_panel)
	_probe_panel = ProbePanel.new()
	_probe_panel.probe_chosen.connect(open_probe)
	ui.add_child(_probe_panel)
	_gallery = GalleryBar.new()
	_gallery.chosen.connect(_on_gallery_chosen)
	_gallery.cancelled.connect(_on_gallery_cancelled)
	ui.add_child(_gallery)
	_result_panel = ResultPanel.new()
	ui.add_child(_result_panel)
	_question = SpeciesQuestionPanel.new()
	ui.add_child(_question)
	_season_panel = SeasonPanel.new()
	_season_panel.next_season.connect(_start_next_season)
	ui.add_child(_season_panel)
	# nach der Aufgabe geht es zum Abend (Artfrage, Übersicht)
	_result_panel.closed.connect(func():
		if game.phase == "evening":
			_enter_phase())
	_question.closed.connect(func():
		save_game()
		if game.phase == "evening":
			_show_evening())
	_round_panel = RoundPanel.new()
	_round_panel.primary.connect(func(): _round_next.call())
	ui.add_child(_round_panel)
	_hire_panel = HirePanel.new()
	_hire_panel.show_requested.connect(func(o):
		var c := creature_of(o)
		if c != null:
			_select(c)
			camera.distance = 7.0)
	_hire_panel.hire_requested.connect(hire)
	ui.add_child(_hire_panel)
	_intro = IntroPanel.new()
	_intro.started.connect(func(): game.intro_step = 1; _intro_show())
	_intro.skipped.connect(func():
		game.intro_step = GameState.INTRO_DONE
		_banner.visible = false
		_enter_phase())
	ui.add_child(_intro)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := UiUtil.button(text, action, Vector2(100, 44))
	parent.add_child(b)
	return b


func _outlined_label() -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


# --- Debug --------------------------------------------------------------------

## "index:verhalten" – erzwingt ein Verhalten und folgt der Kreatur (Screenshots, Tests).
func debug_force(spec: String) -> void:
	var parts := spec.split(":")
	var i := int(parts[0])
	brains[i].force(parts[1])
	_select(creatures[i])
	camera.distance = 6.0


## Simulationsgeschwindigkeit (1 = normal).
func debug_speed(scale: float) -> void:
	Engine.time_scale = scale
	Engine.max_physics_steps_per_frame = maxi(8, int(ceilf(8 * scale)))


## "aufgabe:rolle=index,rolle=index" – startet eine Aufgabe (Screenshots, Tests).
func debug_task(spec: String) -> void:
	var parts := spec.split(":")
	var t := tasks.get_task(parts[0])
	var assignments := {}
	for pair in parts[1].split(","):
		var kv := pair.split("=")
		assignments[kv[0]] = game.members[int(kv[1])]
	start_task(t, assignments)


## Neues Spiel (löscht den Spielstand beim nächsten Start).
func debug_new_game() -> void:
	if FileAccess.file_exists(GameState.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.DEFAULT_PATH))
	saving_enabled = false
	get_tree().reload_current_scene()


## Leistungstest: vorübergehende Kreaturen (weitere Arten der Taxonomie), nicht gespeichert.
func add_test_creatures(count: int) -> void:
	var all := game.taxonomy.species()
	for n in count:
		var sp: Taxon = all[(test_creatures.size() + n) % all.size()]
		var ind := game.factory.create_individual(sp.id, 1000 + test_creatures.size(), "", "adult")
		var m := GroupMember.from_individual(ind, "Test %d" % (test_creatures.size() + 1))
		var c := _spawn_member(m, _spawn_point(terrain.layout, creatures.size() + 50))
		test_creatures.append(c)


## Kreatur Nummer i auswählen (Screenshots).
func debug_select(i: int) -> void:
	_select(creatures[i])


## "i:fähigkeit:wert" – Einschätzung im Journal setzen (Screenshots).
func debug_rate(spec: String) -> void:
	var p := spec.split(":")
	game.journal.set_rating(game.members[int(p[0])].id, p[1], int(p[2]))
	_select(creatures[int(p[0])])


## "journal", "tasks", "hire", "probes" oder "evening" öffnen (Screenshots).
func debug_open(panel_name: String) -> void:
	for panel in [_card, _task_panel, _journal_panel, _result_panel, _hire_panel, _gallery, _probe_panel, _round_panel]:
		panel.visible = false
	match panel_name:
		"probes":
			open_probe_panel()
		"journal":
			_journal_panel.open(game)
		"hire":
			_hire_panel.open(game)
		"evening":
			_show_evening()
		"tasks":
			open_task_offers()


## Oberflächen-Skalierung erzwingen (Screenshots in Handy-Größe).
func debug_ui_scale(factor: float) -> void:
	UiSettings.forced = factor
	UiSettings.apply(get_tree().root)
	_update_tags()


## Fremden Nummer i auswählen (Screenshots).
func debug_select_stranger(i: int) -> void:
	debug_open("none")
	_select(creature_of(game.offers[i]))


## Einführung bei Schritt n zeigen (Screenshots).
func debug_intro(step: int) -> void:
	_intro.visible = false
	game.intro_step = step
	_intro_show()


## Rollenwahl für Rolle i der Aufgabe öffnen (Screenshots).
func debug_pick(spec: String) -> void:
	var p := spec.split(":")
	var t := tasks.get_task(p[0])
	debug_open("none")
	game.intro_step = GameState.INTRO_DONE
	open_role_gallery(t, t.roles[int(p[1])].id)


## "probe_id:index" – Probe mit Gruppenmitglied Nummer index sofort spielen (Screenshots, Tests).
func debug_probe(spec: String) -> void:
	var p := spec.split(":")
	debug_open("none")
	run_probe(game.members[int(p[1])], probe_catalog.get_probe(p[0]))


## Kreaturen-Leiste auf- oder zuklappen (Screenshots).
func debug_card_expand(on: bool) -> void:
	_card.set_expanded(on)


## Saison sofort beenden (Screenshots).
func debug_season_end() -> void:
	game.season.day = game.season.days
	next_round()


## "phase" – Phase setzen und beginnen (Screenshots, Tests); "rivals" spielt den Zug der Rivalen.
func debug_phase(p: String) -> void:
	debug_open("none")
	_intro.visible = false
	game.intro_step = GameState.INTRO_DONE
	set_phase(p)


## Kamera auf das Lager der Rivalen (Screenshots).
func debug_view_camp() -> void:
	var r: RivalState = game.rivals[0]
	camera.follow = null
	camera.target = Vector3(r.camp.x, terrain.layout.height_at(r.camp.x, r.camp.y), r.camp.y)
	camera.distance = 12.0
