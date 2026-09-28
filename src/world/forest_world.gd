extends Node3D
## Wurzel der Waldwelt: verbindet Gelände, Navigation, Tageszeit, Wetter und
## Kamera, lädt den Spielstand (oder startet ein neues Spiel), setzt die Gruppe
## ein, protokolliert Beobachtungen und führt Aufgaben durch.
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
var selected: Creature
var debug_mode := false
var saving_enabled := true

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
	day_night.hour = game.hour
	weather.set_state(game.weather)
	catalog = AbilityCatalog.load_file(game.schema)
	tasks = TaskCatalog.load_dir(catalog)
	if not tasks.errors.is_empty():
		push_error("\n".join(tasks.errors))
	game.journal.changed.connect(func(): _save_pending = true)
	_build_hud()
	for i in game.members.size():
		_spawn_member(game.members[i], _spawn_point(l, i))
	_spawn_items(l)


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
	_observe()
	_autosave -= delta
	if _autosave <= 0.0 or (_save_pending and _autosave < AUTOSAVE_SECONDS - 3.0):
		_autosave = AUTOSAVE_SECONDS
		save_game()


func _process(_delta: float) -> void:
	if game == null or _status == null:
		return
	var h := day_night.hour
	_status.text = "%02d:%02d %s · Wetter %s · %d Kreaturen%s" % [
		int(h), int(fposmod(h, 1.0) * 60.0), PHASE_LABELS[day_night.phase()], WEATHER_LABELS[weather.state],
		creatures.size(), ("\nFPS %d · Draw-Calls %d · Licht %d %% · Nässe %d %%" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), int(day_night.light_level() * 100.0),
		int(weather.wetness * 100.0)]) if debug_mode else ""]
	if selected != null and members.has(selected):
		_info.text = "%s: %s" % [members[selected].name, selected.behavior_label if selected.behavior_label != "" else "…"]
	else:
		_info.text = "Tippe eine Kreatur an, um sie zu beobachten."


# --- Kreaturen ----------------------------------------------------------------

func _spawn_member(m: GroupMember, pos: Vector3) -> Creature:
	var c := Creature.new()
	c.name = m.id.replace("#", "_")
	c.position = pos
	c.rotation.y = TAU * float(creatures.size()) / 7.0
	creature_root.add_child(c)
	c.setup_individual(m.to_individual(), m.name)
	c.label = m.name
	c.abilities = AbilityProfile.new(catalog, m.genome)
	creatures.append(c)
	members[c] = m
	var l := terrain.layout
	var brain := BehaviorBrain.new(c, navigation, context, Vector3(l.spawn_pos.x, 0.0, l.spawn_pos.y), RngUtil.derive_seed(["brain", m.id]))
	brain.roam_radius = 16.0
	brain.mover.others = creatures
	brains.append(brain)
	return c


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
		game.journal.add_log("%02d:%02d" % [int(h), int(fposmod(h, 1.0) * 60.0)], members[c].id, text)
		if c == selected and _card.visible:
			_card.refresh()


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
	if c != null:
		camera.distance = clampf(camera.distance, 4.0, 10.0)
		_card.show_member(members[c], game.journal, catalog, _debug_text(c))
	else:
		_card.visible = false


func _debug_text(c: Creature) -> String:
	if not debug_mode:
		return ""
	var m: GroupMember = members[c]
	var parts := []
	for entry in c.abilities.ranked():
		parts.append("%s %d" % [catalog.name_of(entry[0]), int(entry[1] * 100)])
	return "Debug: %s\n%s" % [game.taxonomy.get_taxon(m.species_id).display_name(), " · ".join(parts)]


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
	_player = TaskPlayer.new()
	add_child(_player)
	_player.step_started.connect(func(t): _info.text = t)
	_player.finished.connect(_on_task_finished.bind(task, role_names), CONNECT_ONE_SHOT)
	_player.play(self, task, result, actors, names)


func creature_of(m: GroupMember) -> Creature:
	for c in members:
		if members[c] == m:
			return c
	return null


func _on_task_finished(result: Dictionary, task: TaskDef, role_names: Dictionary) -> void:
	var joined := game.record_task(task.id, result.success)
	for m in joined:
		_spawn_member(m, _spawn_point(terrain.layout, creatures.size() + 3))
	save_game()
	_player.queue_free()
	_player = null
	_result_panel.show_result(task, result, role_names, joined)


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
	_time_button = _button(bar, "Zeit ×1", _cycle_time)
	_weather_button = _button(bar, "Wetter: auto", _cycle_weather)
	var dbg := _button(bar, "Debug", Callable())
	var reset := _button(bar, "Neues Spiel", debug_new_game)
	reset.visible = false
	dbg.pressed.connect(func():
		debug_mode = not debug_mode
		dbg.text = "Debug: an" if debug_mode else "Debug"
		reset.visible = debug_mode
		if selected != null:
			_select(selected))
	_info = _outlined_label()
	root.add_child(_info)

	_card = CreatureCard.new()
	_card.visible = false
	_card.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_card.offset_left = -400
	_card.offset_top = 60
	_card.offset_bottom = -10
	_card.offset_right = -10
	_card.closed.connect(func(): _select(null))
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


## Kreatur Nummer i auswählen (Screenshots).
func debug_select(i: int) -> void:
	_select(creatures[i])


## "journal" oder "tasks" öffnen (Screenshots).
func debug_open(panel_name: String) -> void:
	_card.visible = false
	if panel_name == "journal":
		_journal_panel.open(game)
	else:
		_task_panel.open(game, tasks)
