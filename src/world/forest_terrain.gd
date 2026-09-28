@tool
class_name ForestTerrain
extends Node3D
## Baut Gelände, Bach, Felsen und Fruchtbäume aus data/world/forest.json.
##
## Läuft auch im Editor (@tool), damit Spatial Gardener auf dem Gelände malen
## kann. Die erzeugten Kinder werden nicht in der Szene gespeichert, sondern
## bei jedem Laden neu gebaut – Quelle der Wahrheit bleibt die JSON-Datei.
## Im Editor: „Neu bauen“ im Inspektor nach Änderungen an der JSON-Datei.

signal built

const WATER_SHADER := preload("res://src/world/water.gdshader")
const ZONE_COLORS := {
	"forest": Color(0.24, 0.3, 0.16),
	"clearing": Color(0.42, 0.52, 0.24),
	"bank": Color(0.5, 0.46, 0.32),
	"water": Color(0.3, 0.27, 0.2),
	"rock": Color(0.34, 0.33, 0.28),
	"tree": Color(0.26, 0.28, 0.16),
	"outside": Color(0.2, 0.25, 0.14),
}

@export_file("*.json") var layout_path := ForestLayout.DEFAULT_PATH:
	set(value):
		layout_path = value
		if is_inside_tree():
			rebuild()
@export var rebuild_now := false:
	set(value):
		if value and is_inside_tree():
			rebuild()
## Kollisionsebene des Bodens (Kreaturen-Raycasts, Gardener).
@export_flags_3d_physics var ground_layer := 1

var layout: ForestLayout
var terrain_body: StaticBody3D
var water_mesh: MeshInstance3D
var water_material: ShaderMaterial
var fruit_trees: Array[FruitTree] = []
var rocks: Array[StaticBody3D] = []


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for child in get_children(true):
		if child.get_meta("generated", false):
			remove_child(child)
			child.queue_free()
	fruit_trees.clear()
	rocks.clear()
	layout = ForestLayout.load_file(layout_path)
	if not layout.is_valid():
		push_error("ForestTerrain: " + "\n".join(layout.errors))
		return
	_build_terrain()
	_build_water()
	_build_rocks()
	_build_fruit_trees()
	built.emit()


func _add_generated(node: Node) -> void:
	node.set_meta("generated", true)
	add_child(node, false, Node.INTERNAL_MODE_BACK)


# --- Gelände ------------------------------------------------------------------

func _build_terrain() -> void:
	var nx := int(layout.size.x) + 1
	var nz := int(layout.size.y) + 1
	var half := layout.half_size()
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			heights[iz * nx + ix] = layout.height_at(ix - half.x, iz - half.y)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise := FastNoiseLite.new()
	noise.seed = layout.seed_value + 1
	noise.frequency = 0.15
	for iz in nz:
		for ix in nx:
			var x := ix - half.x
			var z := iz - half.y
			var c: Color = ZONE_COLORS.get(layout.zone_at(x, z), ZONE_COLORS.forest)
			c = c.lightened(noise.get_noise_2d(x, z) * 0.08)
			st.set_color(c)
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, heights[iz * nx + ix], z))
	for iz in nz - 1:
		for ix in nx - 1:
			var i := iz * nx + ix
			# Godot: Vorderseite im Uhrzeigersinn (von oben gesehen)
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + nx)
			st.add_index(i + 1)
			st.add_index(i + nx + 1)
			st.add_index(i + nx)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)

	terrain_body = StaticBody3D.new()
	terrain_body.name = "Terrain"
	terrain_body.collision_layer = ground_layer
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	terrain_body.add_child(mi)
	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	terrain_body.add_child(cs)
	_add_generated(terrain_body)


# --- Bach ---------------------------------------------------------------------

func _build_water() -> void:
	var pts := layout.stream_points
	if pts.size() < 2:
		return
	# Mittellinie in ~1-m-Schritten abtasten
	var line := PackedVector2Array()
	for i in pts.size() - 1:
		var seg_len := pts[i].distance_to(pts[i + 1])
		var steps := maxi(1, int(seg_len))
		for s in steps:
			line.append(pts[i].lerp(pts[i + 1], float(s) / steps))
	line.append(pts[pts.size() - 1])

	var half_w := layout.stream_width * 0.5 + layout.stream_bank * 0.45
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for i in line.size():
		var dir := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x)
		if i > 0:
			along += line[i].distance_to(line[i - 1])
		var y := layout.water_level_at(line[i].x, line[i].y)
		for k in 3:
			var off := float(k - 1)  # -1, 0, 1
			var p := line[i] + side * half_w * off
			st.set_uv(Vector2(0.0, absf(off)))
			st.set_uv2(Vector2(along, off * half_w))
			st.add_vertex(Vector3(p.x, y, p.y))
	for i in line.size() - 1:
		for k in 2:
			var a := i * 3 + k
			var b := a + 3
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	st.generate_normals()
	water_material = ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	water_mesh = MeshInstance3D.new()
	water_mesh.name = "Water"
	water_mesh.mesh = st.commit()
	water_mesh.material_override = water_material
	water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_generated(water_mesh)


# --- Felsen und Fruchtbäume ---------------------------------------------------

func _build_rocks() -> void:
	var mat := VegetationMeshes.material()
	for i in layout.rocks.size():
		var r: Dictionary = layout.rocks[i]
		var lp := LowPoly.new(RngUtil.derive_seed(["rock", layout.seed_value, i]))
		var s: float = r.size
		lp.blob(Vector3(0, s * 0.35, 0), Vector3(s, s * 0.8, s * 0.9), 4, 7, Color(0.45, 0.44, 0.4), 0.25)
		var mesh := lp.commit(mat)
		var body := StaticBody3D.new()
		body.name = "Rock%d" % i
		body.collision_layer = ground_layer
		body.add_to_group("rock")
		body.set_meta("climbable", r.climbable)
		body.position = Vector3(r.pos.x, layout.height_at(r.pos.x, r.pos.y) - s * 0.25, r.pos.y)
		body.rotation.y = TAU * float(i) / 7.0
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_convex_shape()
		body.add_child(cs)
		_add_generated(body)
		rocks.append(body)


func _build_fruit_trees() -> void:
	for i in layout.fruit_trees.size():
		var t: Dictionary = layout.fruit_trees[i]
		var tree := FruitTree.new()
		tree.name = "FruitTree%d" % i
		tree.tree_height = t.height
		tree.fruit_count = t.fruits
		tree.fruit_height = t.fruit_height
		tree.seed_value = RngUtil.derive_seed(["fruit_tree", layout.seed_value, i])
		tree.collision_layer = ground_layer
		tree.position = Vector3(t.pos.x, layout.height_at(t.pos.x, t.pos.y), t.pos.y)
		_add_generated(tree)
		fruit_trees.append(tree)
