extends Node3D
## Testszene für M2: alle Baupläne laufen über unebenen Boden.
##
## Kreaturen: je eine pro Art der Demo-Taxonomie plus die Bauplan-Galerie.
## Anzeige: FPS, Draw-Calls, Kreaturen je LOD-Stufe. Antippen wählt eine
## Kreatur aus (Kamera folgt), „+5“ fügt weitere hinzu (Performance-Test).

const DEMO := "res://data/taxonomies/forest_demo.json"
const GALLERY := "res://data/taxonomies/bodyplan_gallery.json"
const AREA := Rect2(-12, -12, 24, 24)

var schema: GenomeSchema
var sources: Array[IndividualFactory] = []
var creatures: Array[Creature] = []
var brains: Array[WanderBrain] = []
var camera: OrbitCamera
var selected: Creature

var _stats: Label
var _info: Label
var _lod_forced := -1
var _lod_button: Button
var _spawn_counter := 0
var _lined_up := false


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_ui()
	schema = GenomeSchema.load_file()
	for path in [DEMO, GALLERY]:
		var loader := TaxonomyLoader.new()
		var tax := loader.load_file(path, schema)
		if tax == null:
			push_error("\n".join(loader.errors))
			continue
		sources.append(IndividualFactory.new(tax))
	for factory in sources:
		for sp in factory.taxonomy.species():
			_spawn(factory, sp.id)


func _physics_process(delta: float) -> void:
	if _lined_up:
		return
	for b in brains:
		b.update(delta)


## Stellt alle Kreaturen still in Reihen auf (zum Vergleichen der Baupläne).
func lineup() -> void:
	_lined_up = not _lined_up
	if not _lined_up:
		return
	var cols := 5
	for i in creatures.size():
		var c := creatures[i]
		c.desired_velocity = Vector3.ZERO
		c.velocity = Vector3.ZERO
		# freie Fläche hinter den Hindernissen
		c.global_position = Vector3((i % cols - (cols - 1) * 0.5) * 2.6, 0.0, 11.0 + (i / cols) * 2.6)
		c.rotation.y = -PI * 0.5  # Blick nach +X: Seitenansicht für die Kamera
		c._snap_to_ground()
		c.locomotion.reset(c.global_transform)
	_select(null)
	var rows := (creatures.size() + cols - 1) / cols
	camera.target = Vector3(0, 0.4, 11.0 + (rows - 1) * 1.3)
	camera.yaw = 0.0
	camera.pitch = -0.45
	camera.distance = 12.0


func _process(_delta: float) -> void:
	var counts := [0, 0, 0, 0]
	for c in creatures:
		counts[c.lod_level] += 1
	_stats.text = "FPS %d · Kreaturen %d · Draw-Calls %d\nLOD voll %d · reduziert %d · eingefroren %d · aus %d" % [
		Engine.get_frames_per_second(), creatures.size(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		counts[0], counts[1], counts[2], counts[3]]


# --- Kreaturen ----------------------------------------------------------------

func _spawn(factory: IndividualFactory, species_id: String) -> Creature:
	var index := _spawn_counter
	_spawn_counter += 1
	var ind := factory.create_individual(species_id, index, "", "", 0.15)
	var c := Creature.new()
	c.name = "%s_%d" % [species_id, index]
	var rng := RngUtil.make_rng(["lab", species_id, index])
	c.position = Vector3(rng.randf_range(AREA.position.x, AREA.end.x), 0.0, rng.randf_range(AREA.position.y, AREA.end.y))
	c.rotation.y = rng.randf_range(-PI, PI)
	add_child(c)
	c.setup_individual(ind, factory.taxonomy.get_taxon(species_id).display_name())
	if _lod_forced >= 0:
		c.auto_lod = false
		c.set_lod(_lod_forced)
	creatures.append(c)
	brains.append(WanderBrain.new(c, AREA, rng.randi()))
	return c


func _spawn_more(count: int) -> void:
	for n in count:
		var factory: IndividualFactory = sources[n % sources.size()]
		var all := factory.taxonomy.species()
		_spawn(factory, all[(n + _spawn_counter) % all.size()].id)


func _remove(count: int) -> void:
	for n in mini(count, creatures.size()):
		var c: Creature = creatures.pop_back()
		brains.pop_back()
		if c == selected:
			_select(null)
		c.queue_free()


func _select(c: Creature) -> void:
	selected = c
	camera.follow = c
	if c == null:
		_info.text = "Tippe eine Kreatur an."
		return
	var p := c.plan
	_info.text = "%s\n%d Beine · %d Segmente · Gang %s · %.2f m/s" % [c.label, p.leg_count, p.segment_count, p.gait, p.move_speed]


func _on_tap(pos: Vector2) -> void:
	var best: Creature = null
	var best_d := 70.0
	for c in creatures:
		if not c.visible or camera.is_position_behind(c.global_position):
			continue
		var sp := camera.unproject_position(c.global_position + Vector3.UP * c.plan.body_center_y)
		var d := sp.distance_to(pos)
		if d < best_d:
			best_d = d
			best = c
	_select(best)


func _cycle_lod() -> void:
	_lod_forced += 1
	if _lod_forced > CreatureLOD.FROZEN:
		_lod_forced = -1
	_lod_button.text = "LOD: " + ("auto" if _lod_forced < 0 else CreatureLOD.NAMES[_lod_forced])
	for c in creatures:
		c.auto_lod = _lod_forced < 0
		if _lod_forced >= 0:
			c.set_lod(_lod_forced)


# --- Umgebung -----------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.8)
	sky_mat.ground_bottom_color = Color(0.2, 0.25, 0.2)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	# 2 Kaskaden statt 4: halbiert die Schatten-Draw-Calls (Mobile)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	camera = OrbitCamera.new()
	camera.distance = 16.0
	camera.tapped.connect(_on_tap)
	add_child(camera)


func _build_ground() -> void:
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.36, 0.42, 0.26)
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.43, 0.4)
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40), Vector3.ZERO, ground_mat)
	# Rampen, Stufen, Buckel – damit die Füße etwas zu tun haben
	_add_box(Vector3(4, 0.0, -3), Vector3(4, 0.6, 5), Vector3(0, 0, deg_to_rad(12)), rock_mat)
	_add_box(Vector3(-5, 0.0, 4), Vector3(5, 0.8, 3), Vector3(deg_to_rad(-15), 0, 0), rock_mat)
	_add_box(Vector3(-4, 0.1, -6), Vector3(3, 0.2, 3), Vector3.ZERO, rock_mat)
	_add_box(Vector3(-4, 0.2, -6), Vector3(2, 0.2, 2), Vector3.ZERO, rock_mat)
	_add_box(Vector3(7, 0.12, 6), Vector3(4, 0.25, 2), Vector3(0, deg_to_rad(30), 0), rock_mat)
	for i in 7:
		var rng := RngUtil.make_rng(["rock", i])
		var r := rng.randf_range(0.4, 1.1)
		_add_sphere(Vector3(rng.randf_range(-10, 10), -r * 0.6, rng.randf_range(-10, 10)), r, rock_mat)


func _add_box(pos: Vector3, size: Vector3, rot: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mesh.mesh = bm
	body.add_child(mesh)
	add_child(body)


func _add_sphere(pos: Vector3, radius: float, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	sm.material = mat
	mesh.mesh = sm
	body.add_child(mesh)
	add_child(body)


# --- UI -----------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := VBoxContainer.new()
	root.position = Vector2(12, 8)
	root.theme = Theme.new()
	root.theme.default_font_size = 17
	layer.add_child(root)
	_stats = Label.new()
	_stats.add_theme_color_override("font_outline_color", Color.BLACK)
	_stats.add_theme_constant_override("outline_size", 4)
	root.add_child(_stats)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	for spec in [["+5", _spawn_more.bind(5)], ["−5", _remove.bind(5)], ["LOD: auto", _cycle_lod], ["Folgen aus", _select.bind(null)], ["Aufstellen", lineup]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(100, 44)
		b.pressed.connect(spec[1])
		bar.add_child(b)
		if spec[0].begins_with("LOD"):
			_lod_button = b
	_info = Label.new()
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 4)
	root.add_child(_info)
	_select(null)
