extends Node3D
## Wurzel der Waldwelt: verbindet Gelände, Navigation, Tageszeit, Wetter und
## Kamera, lädt den Spielstand (oder startet ein neues Spiel), setzt die Gruppe
## und die Fremden am Waldrand ein, protokolliert Beobachtungen, führt Aufgaben
## durch und verwaltet das Anheuern.
##
## Die Szene (scenes/world/forest.tscn) wird von tools/build_forest.gd erzeugt;
## Knoten werden über ihre Namen gefunden.
## Ohne Spielstand (Tests, Screenshots): Root-Meta "forest_no_save" setzen.

const TIME_SCALES := [1.0, 10.0, 60.0, 0.0]
const WEATHER_MODES := ["auto", "clear", "cloudy", "rain"]
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
## Zeitraffer während einer Aufgabe (Knopf „Schneller“).
const TASK_FAST := 2.5
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
var _time_button: Button
var _weather_button: Button
var _time_index := 0
var _weather_index := 0
var _card: CreatureCard
var _journal_panel: JournalPanel
var _task_panel: TaskPanel
var _result_panel: ResultPanel
var _hire_panel: HirePanel
var _prompt: TaskPrompt
var _banner: Label
var _fast: Button
var _focus: Button
var _fast_on := false
var _credits: Label
var _idle := 0.0
var _prompt_after := PROMPT_IDLE
var _prompt_enabled := true
## Creature -> Rollenname, solange eine Aufgabe läuft
var _roles_shown: Dictionary = {}
var _player: TaskPlayer
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
	catalog = AbilityCatalog.load_file(game.schema)
	tasks = TaskCatalog.load_dir(catalog)
	if not tasks.errors.is_empty():
		push_error("\n".join(tasks.errors))
	game.journal.changed.connect(func(): _save_pending = true)
	show_names = UiSettings.show_names()
	_prompt_enabled = UiSettings.task_prompt()
	_build_hud()
	for i in game.members.size():
		_spawn_member(game.members[i], _spawn_point(l, i))
	for o in game.offers:
		_spawn_stranger(o)
	_spawn_items(l)
	_update_tags()


func _notification(what: int) -> void:
	# Android beendet Apps im Hintergrund ohne Vorwarnung – beim Pausieren speichern
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()


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
	_update_prompt(delta)
	_credits.text = "%d %s" % [game.credits, GameState.currency()]
	var h := day_night.hour
	var extra := ""
	if debug_mode:
		var st := perf.stats()
		var lod := PerfMonitor.lod_counts(creatures)
		extra = "\nFPS %d · Frame %.1f ms (95 %%: %.1f, max %.1f) · Draw-Calls %d · Grafik %s\nLOD voll %d · reduziert %d · eingefroren %d · aus %d · Licht %d %% · Nässe %d %%" % [
			Engine.get_frames_per_second(), st.avg, st.p95, st.max,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), GraphicsSettings.LABELS[graphics_level],
			lod[0], lod[1], lod[2], lod[3], int(day_night.light_level() * 100.0), int(weather.wetness * 100.0)]
	_status.text = "%02d:%02d %s · Wetter %s · %d Kreaturen%s" % [
		int(h), int(fposmod(h, 1.0) * 60.0), PHASE_LABELS[day_night.phase()], WEATHER_LABELS[weather.state],
		creatures.size() - test_creatures.size(), extra]
	if _player != null and _player.running:
		_info.text = ""
	elif selected != null and _member_of(selected) != null:
		_info.text = "%s: %s" % [_member_of(selected).name, selected.behavior_label if selected.behavior_label != "" else "…"]
	else:
		_info.text = "Tippe eine Kreatur an, um sie zu beobachten."


# --- Kreaturen ----------------------------------------------------------------

func _member_of(c: Creature) -> GroupMember:
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
	if _player != null and _player.running:
		return
	var best: Creature = null
	var best_d := 70.0
	for c in creatures:
		if not c.visible or camera.is_position_behind(c.global_position):
			continue
		var d := camera.unproject_position(c.global_position + Vector3.UP * c.plan.body_center_y).distance_to(pos)
		if d < best_d:
			best_d = d
			best = c
	_select(best)


func _select(c: Creature) -> void:
	selected = c
	camera.follow = c
	if c == null:
		_card.visible = false
		return
	camera.distance = clampf(camera.distance, 4.0, 10.0)
	if strangers.has(c):
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
	var actors := {}
	var names := {}
	var role_names := {}
	for role_id in assignments:
		var c := creature_of(assignments[role_id])
		actors[role_id] = c
		names[c] = assignments[role_id].name
		role_names[role_id] = assignments[role_id].name
	_card.visible = false
	_roles_shown.clear()
	for role_id in actors:
		_roles_shown[actors[role_id]] = task.role(role_id).name
		actors[role_id].priority = 2
	_update_tags()
	_fast.visible = true
	_focus.visible = true
	_fast.text = "» Schneller"
	_player = TaskPlayer.new()
	add_child(_player)
	_player.step_started.connect(func(t):
		_banner.text = t
		_banner.visible = t != "")
	_player.finished.connect(_on_task_finished.bind(task, role_names), CONNECT_ONE_SHOT)
	_player.play(self, task, result, actors, names)


func creature_of(m: GroupMember) -> Creature:
	for c in members:
		if members[c] == m:
			return c
	for c in strangers:
		if strangers[c] == m:
			return c
	return null


func _on_task_finished(result: Dictionary, task: TaskDef, role_names: Dictionary) -> void:
	var outcome := game.record_task(task, result.success)
	for o in outcome.new_offers:
		_spawn_stranger(o)
	save_game()
	_player.queue_free()
	_player = null
	_banner.visible = false
	_fast.visible = false
	_focus.visible = false
	if _fast_on:
		_set_task_speed(1.0)
	for c in _roles_shown:
		if is_instance_valid(c):
			c.priority = 0
	_roles_shown.clear()
	_update_tags()
	_idle = 0.0
	_result_panel.show_result(task, result, role_names, outcome)


## Kamera zur Kreatur, die in der laufenden Aufgabe gerade am Zug ist.
func focus_active() -> void:
	if _player == null or _player.active == null or not is_instance_valid(_player.active):
		return
	camera.follow = _player.active
	camera.distance = clampf(camera.distance, 5.0, 9.0)


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


func _toggle_fast() -> void:
	_set_task_speed(1.0 if _fast_on else TASK_FAST)


func _set_task_speed(scale: float) -> void:
	_fast_on = scale > 1.0
	debug_speed(scale)
	_fast.text = "▶ Normal" if _fast_on else "» Schneller"


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
	_banner.text = "%s gehört jetzt zur Gruppe." % offer.name
	_banner.visible = true
	get_tree().create_timer(3.0).timeout.connect(func():
		if _player == null:
			_banner.visible = false)
	return true


# --- Namensschilder und Hinweis -------------------------------------------------

func _update_tags() -> void:
	for c in creatures:
		if _roles_shown.has(c):
			c.set_tag("%s: %s" % [_roles_shown[c], _member_of(c).name], TAG_ROLE)
		elif not show_names or test_creatures.has(c):
			c.set_tag("")
		elif strangers.has(c):
			c.set_tag("%s · %d %s" % [strangers[c].name, strangers[c].price, GameState.currency()], TAG_STRANGER)
		elif members.has(c):
			c.set_tag(members[c].name, TAG_MEMBER)


func _update_prompt(delta: float) -> void:
	if not _prompt_enabled or tasks == null or tasks.tasks.is_empty() or _player != null:
		_idle = 0.0
		return
	for panel in [_task_panel, _journal_panel, _result_panel, _hire_panel, _prompt]:
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
	_status = _outlined_label()
	root.add_child(_status)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_button(bar, "Journal", func(): _card.visible = false; _journal_panel.open(game))
	_button(bar, "Aufgaben", func(): _card.visible = false; _task_panel.open(game, tasks))
	_button(bar, "Anheuern", func(): _card.visible = false; _hire_panel.open(game))
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
	_time_button = _button(opts, "Zeit ×1", _cycle_time)
	_weather_button = _button(opts, "Wetter: auto", _cycle_weather)
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
	dbg.pressed.connect(func():
		debug_mode = not debug_mode
		dbg.text = "Debug: an" if debug_mode else "Debug"
		dbg_row.visible = debug_mode
		if selected != null:
			_select(selected))
	_info = _outlined_label()
	root.add_child(_info)

	# Einblendung der Aufgabenschritte (oben mittig, groß)
	_banner = _outlined_label()
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_left = 0.15
	_banner.anchor_right = 0.85
	_banner.offset_left = 0
	_banner.offset_right = 0
	_banner.offset_top = 140
	_banner.visible = false
	ui.add_child(_banner)
	_fast = UiUtil.button("» Schneller", _toggle_fast, Vector2(170, 48))
	_fast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_fast.offset_left = -190
	_fast.offset_top = -64
	_fast.offset_right = -20
	_fast.offset_bottom = -16
	_fast.visible = false
	ui.add_child(_fast)
	_focus = UiUtil.button("◎ Zur Aufgabe", focus_active, Vector2(190, 48))
	_focus.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_focus.offset_left = -400
	_focus.offset_top = -64
	_focus.offset_right = -210
	_focus.offset_bottom = -16
	_focus.visible = false
	ui.add_child(_focus)

	_card = CreatureCard.new()
	_card.visible = false
	_card.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_card.offset_left = -390
	_card.offset_top = 60
	_card.offset_bottom = -10
	_card.offset_right = -10
	_card.closed.connect(func(): _select(null))
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
	ui.add_child(_task_panel)
	_result_panel = ResultPanel.new()
	ui.add_child(_result_panel)
	_hire_panel = HirePanel.new()
	_hire_panel.show_requested.connect(func(o):
		var c := creature_of(o)
		if c != null:
			_select(c)
			camera.distance = 7.0)
	_hire_panel.hire_requested.connect(hire)
	ui.add_child(_hire_panel)
	_prompt = TaskPrompt.new()
	_prompt.accepted.connect(func(t): _card.visible = false; _task_panel.open(game, tasks, t))
	_prompt.later.connect(func(): _prompt_after = PROMPT_AGAIN)
	_prompt.never.connect(func():
		_prompt_enabled = false
		UiSettings.set_value("task_prompt", false))
	ui.add_child(_prompt)


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
	_time_index = (_time_index + 1) % TIME_SCALES.size()
	day_night.time_scale = TIME_SCALES[_time_index]
	_time_button.text = "Zeit ×%d" % TIME_SCALES[_time_index] if TIME_SCALES[_time_index] > 0.0 else "Zeit angehalten"


func _cycle_weather() -> void:
	_weather_index = (_weather_index + 1) % WEATHER_MODES.size()
	var mode: String = WEATHER_MODES[_weather_index]
	weather.auto_change = mode == "auto"
	if mode != "auto":
		weather.set_state(mode)
	_weather_button.text = "Wetter: " + (WEATHER_LABELS.get(mode, "auto"))


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
	Engine.max_physics_steps_per_frame = maxi(8, int(8 * scale))


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


## "journal", "tasks", "hire" oder "prompt" öffnen (Screenshots).
func debug_open(panel_name: String) -> void:
	for panel in [_card, _task_panel, _journal_panel, _result_panel, _hire_panel, _prompt]:
		panel.visible = false
	match panel_name:
		"journal":
			_journal_panel.open(game)
		"hire":
			_hire_panel.open(game)
		"prompt":
			var t := suggested_task()
			_prompt.open(t, game.reward_for(t))
		"tasks":
			_task_panel.open(game, tasks)


## Oberflächen-Skalierung erzwingen (Screenshots in Handy-Größe).
func debug_ui_scale(factor: float) -> void:
	UiSettings.forced = factor
	UiSettings.apply(get_tree().root)
	_update_tags()


## Fremden Nummer i auswählen (Screenshots).
func debug_select_stranger(i: int) -> void:
	debug_open("none")
	_select(creature_of(game.offers[i]))
