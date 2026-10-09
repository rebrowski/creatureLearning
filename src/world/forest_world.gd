extends Node3D

## Wurzel der Waldwelt: verbindet Gelände, Navigation, Tageszeit, Wetter und
## Kamera, lädt den Spielstand (oder startet ein neues Spiel), setzt die Gruppe
## und die Fremden am Waldrand ein, protokolliert Beobachtungen, führt Aufgaben
## auf der Bühne (Stage, abseits des Lagers) durch, ebenso die Proben, und
## verwaltet das Anheuern.
##
## Die Szene (scenes/world/forest.tscn) wird von tools/build_forest.gd erzeugt;
## Knoten werden über ihre Namen gefunden.
## Ohne Spielstand (Tests, Screenshots): Root-Meta "forest_no_save" setzen.

## Tempo-Stufen (Knopf „Tempo“): beschleunigt alles – Kreaturen, Aufgaben und
## Tageszeit (Engine.time_scale); 0 = Pause.
const TIME_SCALES := [1.0, 1.5, 2.0, 3.0, 4.0, 0.0]
## „Warten“: springt zum nächsten Abend bzw. Morgen (Uhrzeit).
const EVENING_HOUR := 19.5
const MORNING_WAKE := 7.0
const WEATHER_LABELS := {"clear": "klar", "cloudy": "bewölkt", "rain": "Regen"}
const PHASE_LABELS := {"night": "Nacht", "dawn": "Morgen", "day": "Tag", "dusk": "Abend"}
## Beobachtungen werden protokolliert, wenn die Kreatur höchstens so weit von der Kamera entfernt ist.
const OBSERVE_DISTANCE := 28.0
const AUTOSAVE_SECONDS := 60.0
## Höchstgeschwindigkeit, mit der sich überlappende Kreaturen auseinanderschieben (m/s).
const SEPARATE_SPEED := 1.5
## Hinweis „Aufgabe starten?“ nach so vielen Sekunden ohne Eingabe (danach PROMPT_AGAIN).
const PROMPT_IDLE := 20.0
const PROMPT_AGAIN := 90.0
## Fremde streifen in diesem Abstand vom Lagerplatz umher (Meter).
const STRANGER_DISTANCE := 13.0
const STRANGER_ROAM := 5.0
const TAG_MEMBER := Color(1, 1, 1)
const TAG_STRANGER := Color(1.0, 0.75, 0.35)
const TAG_ROLE := Color(1.0, 0.92, 0.45)
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
const TICKER_LINES := 3
## Geräusche der Kreatur im Fokus sind bis zu dieser Kameradistanz hörbar (Meter).
const SOUND_DISTANCE := 30.0
const TICKER_SECONDS := 9.0
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
var _time_button: Button
var _wait_button: Button
var _time_index := 0
var _card: CreatureCard
var _journal_panel: JournalPanel
var _task_panel: TaskPanel
var _result_panel: ResultPanel
var _hire_panel: HirePanel
var _prompt: TaskPrompt
var _intro: IntroPanel
var _question: SpeciesQuestionPanel
var _intro_timer := 0.0
var _intro_ratings := 0
var _banner: Label
var _skip: Button
var _skipping := false
var _credits: Label
var _idle := 0.0
var _rival_rng := RandomNumberGenerator.new()
var _web_save_cb: JavaScriptObject
var _score: Label
var _season_label: Label
var _ticker: VBoxContainer
var _season_panel: SeasonPanel
var _difficulty_button: Button
var _last_hour := -1.0
var _morning_hour := -1.0
var _prompt_after := PROMPT_IDLE
var _prompt_enabled := true
## Creature -> Rollenname, solange eine Aufgabe läuft
var _roles_shown: Dictionary = {}
## true, solange auf der Bühne etwas läuft (Probe, Aufgabe)
var _busy := false
var stage: Stage
var director: StageDirector
var probe_catalog: ProbeCatalog
var _gallery: GalleryBar
var _probe_panel: ProbePanel
var _probe_button: Button
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
	day_night.hour = game.hour
	weather.set_state(game.weather)
	weather.auto_change = true
	catalog = AbilityCatalog.load_file(game.schema)
	tasks = TaskCatalog.load_dir(catalog)
	if not tasks.errors.is_empty():
		push_error("\n".join(tasks.errors))
	game.journal.changed.connect(func(): _save_pending = true)
	show_names = UiSettings.show_names()
	_prompt_enabled = UiSettings.task_prompt()
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
	if game.intro_step < GameState.INTRO_DONE:
		_intro_show.call_deferred()
	_update_probe_button()
	_resume_pending_task.call_deferred()
	_hook_web_save()


func _exit_tree() -> void:
	# Tempo gilt nur in der Waldwelt (Engine.time_scale ist global)
	if _time_index != 0:
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
	game.hour = day_night.hour
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


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenDrag:
		_idle = 0.0


func _process(delta: float) -> void:
	perf.tick()
	if game == null or _status == null:
		return
	_check_morning()
	if game.intro_step == 2:
		_intro_timer += delta
		if _intro_timer > 40.0:
			_intro_next()
	_update_prompt(delta)
	_credits.text = "%d %s" % [game.credits, GameState.currency()]
	_update_score()
	var h := day_night.hour
	var extra := ""
	if debug_mode:
		var st := perf.stats()
		var lod := PerfMonitor.lod_counts(creatures)
		extra = "\nFPS %d · Frame %.1f ms (95 %%: %.1f, max %.1f) · Draw-Calls %d · Grafik %s\nLOD voll %d · reduziert %d · eingefroren %d · aus %d · Licht %d %% · Nässe %d %%" % [
			Engine.get_frames_per_second(), st.avg, st.p95, st.max,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), GraphicsSettings.LABELS[graphics_level],
			lod[0], lod[1], lod[2], lod[3], int(day_night.light_level() * 100.0), int(weather.wetness * 100.0)]
	_status.text = "%02d:%02d %s · Wetter %s · Gruppe: %d%s" % [
		int(h), int(fposmod(h, 1.0) * 60.0), PHASE_LABELS[day_night.phase()], WEATHER_LABELS[weather.state],
		game.members.size(), extra]
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
			var first: TaskDef = tasks.tasks[0] if not tasks.tasks.is_empty() else null
			if first != null:
				_card.visible = false
				_task_panel.open(game, tasks, first, catalog)
			save_game()


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


## Beim Start: eine unterbrochene Aufgabe auswerten (Ergebnis stand schon fest).
func _resume_pending_task() -> void:
	var p := game.pending_task
	if p.is_empty():
		return
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
		return
	var result: Dictionary = p.get("result", {})
	result.hints = PackedStringArray(result.get("hints", []))
	_show_note("Die Aufgabe „%s“ wurde unterbrochen – hier ist ihr Ergebnis." % task.name, 4.0)
	_on_task_finished(result, task, role_names, assignments)


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
	sync_sites()
	weather.auto_change = true
	for o in outcome.new_offers:
		_spawn_stranger(o)
	if result.success:
		_ensure_needed_offer()
	save_game()
	_banner.visible = false
	for c in _roles_shown:
		if is_instance_valid(c):
			c.priority = 0
	_roles_shown.clear()
	_update_tags()
	_idle = 0.0
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


## Tempo setzen (Index in TIME_SCALES) und beide Tempo-Knöpfe beschriften.
func set_tempo(index: int) -> void:
	_time_index = posmod(index, TIME_SCALES.size())
	var scale: float = TIME_SCALES[_time_index]
	debug_speed(scale)
	var text := "Pause" if scale == 0.0 else ("Tempo ×%s" % String.num(scale, 1).trim_suffix(".0"))
	_time_button.text = text


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
	for panel in [_card, _task_panel, _journal_panel, _hire_panel, _prompt, _gallery, _probe_panel]:
		panel.visible = false
	day_night.set_process(false)
	weather.auto_change = false
	stage.visible = true
	stage.camera.current = true
	_hud_top.visible = false
	_banner.offset_top = 12
	_skip.visible = true
	_skipping = false


## Zurück ins Lager.
func leave_stage() -> void:
	stage.clear()
	stage.visible = false
	camera.make_current()
	day_night.set_process(true)
	weather.auto_change = true
	_hud_top.visible = true
	_banner.offset_top = 150
	_skip.visible = false
	_banner.visible = false
	if _skipping:
		_skipping = false
		set_tempo(_time_index)
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
	_update_probe_button()
	var c := creature_of(m)
	if c != null:
		_select(c)
		_card.show_quick(str(probe.ability))
	if game.intro_step == 1:
		_intro_next()


func _update_probe_button() -> void:
	if _probe_button != null and game != null:
		_probe_button.text = "Proben (%d)" % probes_left()


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
		if _roles_shown.has(c):
			c.set_tag("%s: %s" % [_roles_shown[c], _member_of(c).name], TAG_ROLE)
		elif not show_names or test_creatures.has(c):
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


## Beim Übergang über morning_hour (auch über Mitternacht) werden Erschöpfte wieder fit.
func _check_morning() -> void:
	if _busy:
		return
	var h := day_night.hour
	if _last_hour >= 0.0:
		var dh := h - _last_hour
		if dh < -12.0:
			dh += 24.0
		if dh > 0.0:
			_tick_rivals(dh)
		var m := float(GameState.progression().get("morning_hour", 6.0)) if _morning_hour < 0.0 else _morning_hour
		_morning_hour = m
		# rückwärts um mehr als 12 h = über Mitternacht; kleine Rücksprünge (Aufgaben setzen die Uhrzeit) zählen nicht
		var wrapped := _last_hour - h > 12.0
		var crossed := (_last_hour < m and h >= m) or (wrapped and (h >= m or _last_hour < m))
		if crossed:
			var rested := game.new_morning()
			sync_sites()
			_update_probe_button()
			_on_new_day()
			if rested > 0:
				_update_tags()
				_show_note("Ein neuer Morgen – alle sind ausgeruht.")
	_last_hour = h


## Sichtbare Früchte an den Bäumen = Vorrat der Fundstellen.
func sync_sites() -> void:
	var cfg := GameState.sites_config()
	for id in game.sites:
		var c: Dictionary = cfg.get(id, {})
		if c.has("tree") and int(c.tree) < terrain.fruit_trees.size():
			terrain.fruit_trees[int(c.tree)].set_visible_fruits(int(game.sites[id]))


## Neuer Spieltag: Saison weiterzählen; am Ende Schlusswertung.
func _on_new_day() -> void:
	if game.advance_day():
		_prompt.visible = false
		_card.visible = false
		_season_panel.open(game.finish_season())
		_season_panel.move_to_front()
		save_game()
	_update_tags()


func _update_score() -> void:
	var parts := ["Du %d" % game.points]
	for r in game.rivals:
		parts.append("%s %d" % [r.name, r.points])
	_score.text = " · ".join(parts)
	_season_label.text = "Saison %d · Tag %d/%d · Gegner: %s" % [int(game.season.get("number", 1)),
			mini(int(game.season.get("day", 1)), int(game.season.get("days", 7))), int(game.season.get("days", 7)),
			RivalState.difficulty(game.difficulty).get("label", game.difficulty)]


## Meldung oben rechts (höchstens TICKER_LINES, verblasst nach TICKER_SECONDS).
func _ticker_add(text: String, color: Color) -> void:
	var l := _outlined_label()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 340
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	_ticker.add_child(l)
	while _ticker.get_child_count() > TICKER_LINES:
		_ticker.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(TICKER_SECONDS)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


func _start_next_season(difficulty: String) -> void:
	for c in rival_creatures.keys():
		_despawn(c)
	game.difficulty = difficulty
	game.start_season(int(game.season.get("number", 1)) + 1)
	_spawn_rivals()
	sync_sites()
	_update_tags()
	_show_note("Saison %d beginnt – Gegner: %s" % [int(game.season.number), RivalState.difficulty(difficulty).get("label", difficulty)])
	save_game()


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


## Spielzeit vorrücken und fällige Rivalen-Aktionen ausführen.
func _tick_rivals(hours: float) -> void:
	game.game_hours += hours
	if _busy or game.rivals.is_empty():
		return
	var cfg := RivalState.config()
	var active: Array = cfg.get("active_hours", [7, 21])
	var h := day_night.hour
	if h < float(active[0]) or h > float(active[1]):
		return
	var interval := float(RivalState.difficulty(game.difficulty).get("interval_hours", 2.0))
	for r in game.rivals:
		if game.game_hours < r.next_action:
			continue
		r.next_action = game.game_hours + interval
		var ev := RivalAI.act(game, r, tasks, catalog, _rival_rng)
		_on_rival_event(r, ev)


func _on_rival_event(r: RivalState, ev: Dictionary) -> void:
	match str(ev.type):
		"task":
			_show_rival_attempt(r, ev)
			sync_sites()
			_ticker_add(ev.text, r.color if ev.result.success else Color(1.0, 0.65, 0.5))
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
			_ticker_add(ev.text, r.color)
	_save_pending = true


## Der Versuch der Rivalen wird sichtbar: die entscheidende Rolle zeigt ihr Verhalten.
func _show_rival_attempt(r: RivalState, ev: Dictionary) -> void:
	var t: TaskDef = ev.task
	var role_id := ""
	for rl in t.roles:
		var e: Dictionary = ev.result.roles.get(rl.id, {})
		if not e.get("success", false) and not e.get("skipped", false):
			role_id = rl.id
			break
	if role_id == "":
		role_id = t.roles[0].id
	var m: GroupMember = ev.assignments.get(role_id)
	var c := creature_of(m) if m != null else null
	if c == null or c.scripted:
		return
	var outcome := "success" if ev.result.roles.get(role_id, {}).get("success", false) else "fail"
	var b := brains[creatures.find(c)]
	var tp := TaskPlayer.new()
	tp.world = self
	tp.task = t
	for step in t.steps:
		if str(step.get("role", "")) != role_id:
			continue
		match str(step.type):
			"climb_tree":
				b.force("climb_tree", {"tree": tp._resolve(str(step.place)), "forced_outcome": outcome})
			"cross_stream":
				var p = tp._resolve(str(step.place))
				var pv: Vector3 = p.global_position if p is Node3D else p
				b.force("swim", {"crossing": Vector2(pv.x, pv.z), "forced_outcome": outcome})
			"behavior":
				b.force(str(step.get("behavior", "wander")), {"forced_outcome": outcome})
			_:
				continue
		break
	tp.free()


## Kurze Einblendung oben (verschwindet nach ein paar Sekunden, nicht während Aufgaben).
func _show_note(text: String, seconds := 3.0) -> void:
	if _busy:
		return
	_banner.text = text
	_banner.visible = true
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func():
		if not _busy and _banner.text == text:
			_banner.visible = false)


func _update_prompt(delta: float) -> void:
	if not _prompt_enabled or tasks == null or tasks.tasks.is_empty() or _busy \
			or game.intro_step < GameState.INTRO_DONE:
		_idle = 0.0
		return
	for panel in [_task_panel, _journal_panel, _result_panel, _hire_panel, _prompt, _intro, _question, _season_panel,
			_gallery, _probe_panel]:
		if panel.visible:
			_idle = 0.0
			return
	_idle += delta
	if _idle >= _prompt_after:
		_idle = 0.0
		var t := suggested_task()
		_prompt.open(t, game.reward_for(t))


## Aufgabe für den Hinweis: die erste noch nicht gelöste, sonst die erste.
func suggested_task() -> TaskDef:
	for t in tasks.tasks:
		if game.tasks.get(t.id, {}).get("successes", 0) == 0:
			return t
	return tasks.tasks[0]


## Wassertiefe an der Bachquerung der Aufgabe (für die Wat-Regel).
func _crossing_depth(task: TaskDef) -> float:
	for step in task.steps:
		if step.get("type", "") == "cross_stream":
			var tp := TaskPlayer.new()
			tp.world = self
			tp.task = task
			var p: Vector3 = tp._resolve(str(step.place))
			tp.free()
			var l := terrain.layout
			return l.water_level_at(p.x, p.z) - l.height_at(p.x, p.z)
	return 0.6


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
	_button(bar, "Aufgaben", func(): _card.visible = false; _task_panel.open(game, tasks, null, catalog))
	_button(bar, "Anheuern", func(): _card.visible = false; _hire_panel.open(game))
	_probe_button = _button(bar, "Proben", open_probe_panel)
	var more := _button(bar, "Optionen", Callable())
	_credits = _outlined_label()
	_credits.add_theme_font_size_override("font_size", 20)
	_credits.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_credits.custom_minimum_size = Vector2(120, 0)
	_credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_credits)

	# Optionen (eingeklappt): Zeit, Wetter, Namen, Textgröße, Debug
	var opts := HBoxContainer.new()
	opts.visible = false
	root.add_child(opts)
	more.pressed.connect(func(): opts.visible = not opts.visible)
	_time_button = _button(opts, "Tempo ×1", _cycle_time)
	_wait_button = _button(opts, "Warten …", wait_until_next)
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

	# Punktestand und Meldungen der Rivalen (oben rechts)
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
	_ticker = VBoxContainer.new()
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_box.add_child(_ticker)

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
	_result_panel.closed.connect(func():
		var q := game.species_question()
		if not q.is_empty():
			_question.open(game, q.a, q.b))
	_question.closed.connect(func(): save_game())
	_hire_panel = HirePanel.new()
	_hire_panel.show_requested.connect(func(o):
		var c := creature_of(o)
		if c != null:
			_select(c)
			camera.distance = 7.0)
	_hire_panel.hire_requested.connect(hire)
	ui.add_child(_hire_panel)
	_prompt = TaskPrompt.new()
	_prompt.accepted.connect(func(t): _card.visible = false; _task_panel.open(game, tasks, t, catalog))
	_prompt.later.connect(func(): _prompt_after = PROMPT_AGAIN)
	_prompt.never.connect(func():
		_prompt_enabled = false
		UiSettings.set_value("task_prompt", false))
	ui.add_child(_prompt)
	_intro = IntroPanel.new()
	_intro.started.connect(func(): game.intro_step = 1; _intro_show())
	_intro.skipped.connect(func(): game.intro_step = GameState.INTRO_DONE; _banner.visible = false)
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


func _cycle_time() -> void:
	set_tempo(_time_index + 1)


## Zeit bis zum nächsten Abend (tagsüber) bzw. Morgen (abends/nachts) vorspulen.
## Manches zeigt sich erst in der Dunkelheit; am Morgen sind alle ausgeruht.
func wait_until_next() -> void:
	if _busy:
		return
	var h := day_night.hour
	var target := EVENING_HOUR if h >= MORNING_WAKE and h < EVENING_HOUR else MORNING_WAKE
	var step := fposmod(target - h, 24.0)
	var tw := create_tween()
	tw.tween_method(func(t: float): day_night.hour = fposmod(h + step * t, 24.0), 0.0, 1.0, 1.5)
	_show_note("Es wird Abend …" if target == EVENING_HOUR else "Die Nacht vergeht …", 1.8)


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


## "journal", "tasks", "hire", "probes" oder "prompt" öffnen (Screenshots).
func debug_open(panel_name: String) -> void:
	for panel in [_card, _task_panel, _journal_panel, _result_panel, _hire_panel, _prompt, _gallery, _probe_panel]:
		panel.visible = false
	match panel_name:
		"probes":
			open_probe_panel()
		"journal":
			_journal_panel.open(game)
		"hire":
			_hire_panel.open(game)
		"prompt":
			var t := suggested_task()
			_prompt.open(t, game.reward_for(t))
		"tasks":
			_task_panel.open(game, tasks, null, catalog)


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


## Rivalen sofort handeln lassen; n Mal (Screenshots).
func debug_rival_act(n: int) -> void:
	var r: RivalState = game.rivals[0]
	for m in r.members:
		for a in catalog.order:
			r.set_belief(m.id, a, catalog.base_value(a, m.genome))
	for i in n:
		_on_rival_event(r, RivalAI.act(game, r, tasks, catalog, _rival_rng))


## Saison sofort beenden (Screenshots).
func debug_season_end() -> void:
	game.season.day = game.season.days
	_on_new_day()


## Kamera auf das Lager der Rivalen (Screenshots).
func debug_view_camp() -> void:
	var r: RivalState = game.rivals[0]
	camera.follow = null
	camera.target = Vector3(r.camp.x, terrain.layout.height_at(r.camp.x, r.camp.y), r.camp.y)
	camera.distance = 12.0
