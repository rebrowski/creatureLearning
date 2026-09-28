extends SceneTree
## Erzeugt die Waldwelt scenes/world/forest.tscn samt Spatial-Gardener-Vegetation.
##
##   godot --headless -s tools/build_forest.gd            # Szene neu erzeugen (falls nicht vorhanden)
##   godot --headless -s tools/build_forest.gd -- --regrow  # nur Vegetation neu verteilen
##   godot --headless -s tools/build_forest.gd -- --force   # Szene komplett neu erzeugen
##
## Ablauf: Vegetations-Meshes nach assets/vegetation/ speichern, Pflanzen nach
## den Regeln in data/world/forest.json verteilen (VegetationScatter) und in einen
## Gardener-Knoten laden. Gelände, Bach, Felsen und Fruchtbäume baut ForestTerrain
## beim Laden selbst aus der JSON-Datei. Nach dem Erzeugen kann man im Editor mit
## Spatial Gardener weiter malen; --regrow ersetzt dann allerdings die Vegetation.

const SCENE_PATH := "res://scenes/world/forest.tscn"
const GARDEN_DIR := "res://scenes/world/forest_garden"
const MESH_DIR := "res://assets/vegetation"
const Gardener = preload("res://addons/dreadpon.spatial_gardener/gardener/gardener.gd")
const Placeform = preload("res://addons/dreadpon.spatial_gardener/arborist/placeform.gd")
const PlantState = preload("res://addons/dreadpon.spatial_gardener/greenhouse/greenhouse_plant_state.gd")
const PaintingChanges = preload("res://addons/dreadpon.spatial_gardener/arborist/painting_changes.gd")
const SH_Manual = preload("res://addons/dreadpon.spatial_gardener/arborist/stroke_handler/sh_manual.gd")

## LOD-Einstellungen pro Pflanze: [max. Detaildistanz, Ausblenddistanz, Schatten]
const PLANT_LOD := {
	"tree_pine": [40.0, 90.0, 1],
	"tree_round": [40.0, 90.0, 1],
	"bush": [25.0, 50.0, 1],
	"fern": [18.0, 35.0, 0],
	"grass": [12.0, 26.0, 0],
	"reed": [15.0, 32.0, 0],
	"stone": [18.0, 40.0, 0],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var regrow := args.has("--regrow")
	var force := args.has("--force")
	var layout := ForestLayout.load_file()
	if not layout.is_valid():
		printerr("\n".join(layout.errors))
		quit(1)
		return

	# Debug-Zeichnung des Plugins braucht den Editor
	ProjectSettings.set_setting("dreadpons_spatial_gardener/debug/stroke_handler_debug_draw", false)
	_save_meshes()
	# ForestWorld soll beim Bauen weder Kreaturen noch HUD erzeugen
	root.set_meta("building_forest", true)
	var world: Node3D
	if FileAccess.file_exists(SCENE_PATH) and not force:
		if not regrow:
			print("Szene existiert bereits (%s). --regrow oder --force verwenden." % SCENE_PATH)
			quit(0)
			return
		world = (load(SCENE_PATH) as PackedScene).instantiate()
	else:
		world = _create_world()
	root.add_child(world)
	await process_frame

	var old := world.get_node_or_null("Gardener")
	if old != null:
		world.remove_child(old)
		old.free()
	_clear_dir(GARDEN_DIR)
	var gardener := await _grow(world, layout)

	_set_owner_recursive(world, world)
	var packed := PackedScene.new()
	var err := packed.pack(world)
	if err == OK:
		err = ResourceSaver.save(packed, SCENE_PATH)
	ResourceSaver.save(gardener.greenhouse, GARDEN_DIR.path_join("greenhouse.tres"))
	print("Gespeichert: %s (%s)" % [SCENE_PATH, error_string(err)])
	root.remove_child(world)
	world.free()
	quit(0 if err == OK else 1)


func _save_meshes() -> void:
	DirAccess.make_dir_recursive_absolute(MESH_DIR)
	var mat := VegetationMeshes.material()
	var mat_path := MESH_DIR.path_join("vegetation_material.tres")
	ResourceSaver.save(mat, mat_path)
	mat.take_over_path(mat_path)
	for plant in VegetationMeshes.PLANTS:
		var mesh := VegetationMeshes.build(plant)
		ResourceSaver.save(mesh, MESH_DIR.path_join(plant + ".tres"))


func _grow(world: Node3D, layout: ForestLayout) -> Node3D:
	DirAccess.make_dir_recursive_absolute(GARDEN_DIR)
	var g = Gardener.new()
	g.name = "Gardener"
	g.garden_work_directory = GARDEN_DIR
	world.add_child(g)
	world.move_child(g, world.get_node("Terrain").get_index() + 1)
	await process_frame
	var placements := VegetationScatter.scatter(layout)
	var total := 0
	for plant in placements:
		var data: Dictionary = PlantState.new().ifr_to_dict(true)
		var lod: Array = PLANT_LOD.get(plant, [20.0, 40.0, 0])
		data["plant/plant_label"] = plant
		var p: Dictionary = data["plant/plant"]
		p["mesh/mesh_LOD_variants"] = [{"mesh": MESH_DIR.path_join(plant + ".tres"), "spawned_spatial": null, "cast_shadow": lod[2]}]
		p["mesh/mesh_LOD_max_distance"] = lod[0]
		p["mesh/mesh_LOD_kill_distance"] = lod[1]
		var idx: int = g.greenhouse.add_plant_from_dict(data)
		var forms := []
		for t: Transform3D in placements[plant]:
			forms.append(Placeform.mk(t.origin, Vector3.UP, t))
		_batch_add(g, forms, idx)
		total += forms.size()
		print("  %-10s %5d" % [plant, forms.size()])
	print("Vegetation: %d Pflanzen" % total)
	await process_frame
	return g


## Wie Arborist.batch_add_instances, aber ohne Undo-Schritt (den gibt es nur im Editor).
func _batch_add(g: Node3D, forms: Array, plant_idx: int) -> void:
	var arb = g.arborist
	var changes = PaintingChanges.new()
	var handler = SH_Manual.new()
	arb.active_painting_changes = changes
	arb.active_stroke_handler = handler
	arb.mutex_octree.lock()
	for pf in forms:
		handler.add_instance_placeform(pf, plant_idx, changes)
	arb.mutex_octree.unlock()
	arb.apply_member_update_changes(changes)
	arb.active_stroke_handler = null
	arb.active_painting_changes = null


func _create_world() -> Node3D:
	var world := Node3D.new()
	world.name = "ForestWorld"
	world.set_script(load("res://src/world/forest_world.gd"))

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.008
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 35.0
	world.add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.rotation = Vector3(deg_to_rad(-60), deg_to_rad(30), 0)
	world.add_child(moon)

	var terrain := ForestTerrain.new()
	terrain.name = "Terrain"
	world.add_child(terrain)

	var nav := ForestNavigation.new()
	nav.name = "Navigation"
	world.add_child(nav)
	nav.terrain = terrain

	var dn := DayNightCycle.new()
	dn.name = "DayNight"
	world.add_child(dn)
	dn.sun = sun
	dn.moon = moon
	dn.environment = we

	var weather := Weather.new()
	weather.name = "Weather"
	world.add_child(weather)
	weather.day_night = dn

	var ctx := WorldContext.new()
	ctx.name = "WorldContext"
	world.add_child(ctx)
	ctx.terrain = terrain
	ctx.day_night = dn
	ctx.weather = weather

	var cam := OrbitCamera.new()
	cam.name = "Camera"
	cam.distance = 18.0
	cam.pitch = -0.7
	cam.far = 120.0
	world.add_child(cam)

	var creatures := Node3D.new()
	creatures.name = "Creatures"
	world.add_child(creatures)
	return world


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child in node.get_children():  # interne (generierte) Kinder werden nicht gespeichert
		child.owner = owner_node
		# Gardener verwaltet seine Kinder selbst (Octree-MultiMeshes)
		if child.scene_file_path == "" and child.get_meta("class", "") != "Gardener":
			_set_owner_recursive(child, owner_node)


func _clear_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
