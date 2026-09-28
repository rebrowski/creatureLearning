extends Node3D
## Wurzel der Waldwelt: verbindet Gelände, Navigation, Tageszeit, Wetter und
## Kamera, setzt die Startgruppe ein und zeigt ein Debug-HUD.
##
## Die Szene (scenes/world/forest.tscn) wird von tools/build_forest.gd erzeugt;
## Knoten werden über ihre Namen gefunden.

const GROUP_PATH := "res://data/world/start_group.json"
const TIME_SCALES := [1.0, 10.0, 60.0, 0.0]
const WEATHER_MODES := ["auto", "clear", "cloudy", "rain"]
const WEATHER_LABELS := {"clear": "klar", "cloudy": "bewölkt", "rain": "Regen"}
const PHASE_LABELS := {"night": "Nacht", "dawn": "Morgen", "day": "Tag", "dusk": "Abend"}

@onready var terrain: ForestTerrain = $Terrain
@onready var navigation: ForestNavigation = $Navigation
@onready var day_night: DayNightCycle = $DayNight
@onready var weather: Weather = $Weather
@onready var context: WorldContext = $WorldContext
@onready var camera: OrbitCamera = $Camera
@onready var creature_root: Node3D = $Creatures

var creatures: Array[Creature] = []
var brains: Array[BehaviorBrain] = []
var catalog: AbilityCatalog
var show_abilities := false
var selected: Creature

var _status: Label
var _info: Label
var _time_button: Button
var _weather_button: Button
var _time_index := 0
var _weather_index := 0


func _ready() -> void:
	if get_tree().root.has_meta("building_forest"):
		set_process(false)
		set_physics_process(false)
		return
	_build_hud()
	weather.register_water(terrain.water_material)
	var l := terrain.layout
	camera.bounds = Rect2(-l.size * 0.5, l.size)
	camera.ground_height = func(x: float, z: float) -> float: return l.height_at(x, z)
	camera.target = Vector3(l.spawn_pos.x, l.height_at(l.spawn_pos.x, l.spawn_pos.y), l.spawn_pos.y)
	camera.tapped.connect(_on_tap)
	navigation.baked.connect(func(): print("Navmesh gebacken in %d ms" % navigation.bake_msec))
	navigation.bake_from_terrain()
	_spawn_group()


func _physics_process(delta: float) -> void:
	for b in brains:
		b.update(delta)


func _process(_delta: float) -> void:
	var h := day_night.hour
	var sample := context.sample(camera.target)
	_status.text = "%02d:%02d %s · Wetter %s (Nässe %d %%) · Licht %d %%\nFPS %d · Draw-Calls %d · Kreaturen %d · Navmesh %s" % [
		int(h), int(fposmod(h, 1.0) * 60.0), PHASE_LABELS[day_night.phase()],
		WEATHER_LABELS[weather.state], int(weather.wetness * 100.0), int(day_night.light_level() * 100.0),
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		creatures.size(), ("bereit" if navigation.is_baked else "wird gebacken …")]
	if selected != null:
		var s := context.sample(selected.global_position)
		var text := "%s\n%s · Zone %s" % [selected.label, selected.behavior_label if selected.behavior_label != "" else "…", s.get("zone", "?")]
		if show_abilities and selected.abilities != null:
			var parts := []
			for entry in selected.abilities.ranked():
				parts.append("%s %d" % [catalog.name_of(entry[0]), int(entry[1] * 100)])
			text += "\n" + " · ".join(parts)
		_info.text = text
	else:
		_info.text = "Zone unter der Kamera: %s · Tippe eine Kreatur an." % sample.get("zone", "?")


# --- Kreaturen ----------------------------------------------------------------

func _spawn_group() -> void:
	var res := JsonLoader.read(GROUP_PATH)
	if res.error != "":
		push_error(res.error)
		return
	var group: Dictionary = res.data
	var loader := TaxonomyLoader.new()
	var tax := loader.load_file(group.get("taxonomy", ""), GenomeSchema.load_file())
	if tax == null:
		push_error("\n".join(loader.errors))
		return
	var factory := IndividualFactory.new(tax)
	catalog = AbilityCatalog.load_file(tax.schema)
	if not catalog.is_valid():
		push_error("\n".join(catalog.errors))
	var l := terrain.layout
	var home := Vector3(l.spawn_pos.x, 0.0, l.spawn_pos.y)
	for i in group.get("members", []).size():
		var m: Dictionary = group.members[i]
		if not tax.has_taxon(m.species):
			push_error("Startgruppe: unbekannte Art '%s'" % m.species)
			continue
		var ind := factory.create_individual(m.species, int(m.get("index", 0)), "", "", 0.1)
		var c := Creature.new()
		c.name = ind.id.replace("#", "_")
		c.position = _spawn_point(l, i)
		c.rotation.y = TAU * i / 7.0
		creature_root.add_child(c)
		c.setup_individual(ind, tax.get_taxon(m.species).display_name())
		c.abilities = AbilityProfile.new(catalog, ind.genome)
		creatures.append(c)
		var brain := BehaviorBrain.new(c, navigation, context, home, RngUtil.derive_seed(["brain", ind.id]))
		brain.roam_radius = 16.0
		brain.mover.others = creatures
		brains.append(brain)
	_spawn_items(l)


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


func _on_tap(pos: Vector2) -> void:
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


# --- HUD ----------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := VBoxContainer.new()
	root.position = Vector2(12, 8)
	root.theme = Theme.new()
	root.theme.default_font_size = 17
	layer.add_child(root)
	_status = _outlined_label()
	root.add_child(_status)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_time_button = _button(bar, "Zeit ×1", _cycle_time)
	_button(bar, "+3 h", func(): day_night.hour = fposmod(day_night.hour + 3.0, 24.0))
	_weather_button = _button(bar, "Wetter: auto", _cycle_weather)
	_button(bar, "Folgen aus", _select.bind(null))
	var ab := _button(bar, "Fähigkeiten: aus", Callable())
	ab.pressed.connect(func():
		show_abilities = not show_abilities
		ab.text = "Fähigkeiten: " + ("an" if show_abilities else "aus"))
	_info = _outlined_label()
	root.add_child(_info)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(100, 44)
	if action.is_valid():
		b.pressed.connect(action)
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
