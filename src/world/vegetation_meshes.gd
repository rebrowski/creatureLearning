class_name VegetationMeshes
extends RefCounted
## Platzhalter-Vegetation aus wenigen flach schattierten Dreiecken
## (handyfreundlich). Jede Pflanze ist ein ArrayMesh mit Vertexfarben und
## einem gemeinsamen Material.
##
## Neue Pflanzenart: Funktion `_build_<name>` ergänzen und in PLANTS eintragen.
## Das Build-Tool speichert die Meshes unter assets/vegetation/<name>.tres.

const PLANTS: PackedStringArray = ["tree_pine", "tree_round", "bush", "fern", "grass", "reed", "stone"]
const TRUNK := Color(0.36, 0.25, 0.16)

static var _material: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.roughness = 0.95
		_material.resource_name = "VegetationMaterial"
	return _material


static func build(plant: String) -> ArrayMesh:
	var b := VegetationMeshes.new()
	b._lp = LowPoly.new(plant.hash())
	b.call("_build_" + plant)
	var mesh := b._lp.commit(material())
	mesh.resource_name = plant
	return mesh


var _lp: LowPoly


# --- Pflanzen -----------------------------------------------------------------

func _build_tree_pine() -> void:
	_lp.cylinder(Vector3.ZERO, 0.16, 0.1, 1.4, 6, TRUNK)
	var greens := [Color(0.12, 0.3, 0.16), Color(0.14, 0.35, 0.18), Color(0.17, 0.4, 0.2)]
	for i in 3:
		var y := 0.9 + i * 1.15
		_lp.cone(Vector3(0, y, 0), 1.4 - i * 0.35, 2.0 - i * 0.2, 7, greens[i])


func _build_tree_round() -> void:
	_lp.cylinder(Vector3.ZERO, 0.22, 0.14, 2.4, 6, TRUNK)
	_lp.blob(Vector3(0, 3.2, 0), Vector3(1.7, 1.4, 1.7), 3, 7, Color(0.25, 0.45, 0.18), 0.18)
	_lp.blob(Vector3(0.7, 3.9, 0.3), Vector3(1.0, 0.9, 1.0), 3, 6, Color(0.3, 0.52, 0.2), 0.15)


func _build_bush() -> void:
	for i in 3:
		var a := TAU * i / 3.0
		_lp.blob(Vector3(cos(a) * 0.3, 0.35, sin(a) * 0.3), Vector3(0.5, 0.42, 0.5), 3, 6, Color(0.2, 0.42 + i * 0.04, 0.17), 0.12)


func _build_fern() -> void:
	for i in 7:
		var a := TAU * i / 7.0 + _lp.rng.randf() * 0.3
		_lp.blade(Vector3.ZERO, Vector3(cos(a), 0, sin(a)), 0.16, 0.75, 0.55, Color(0.2, 0.5, 0.2))


func _build_grass() -> void:
	for i in 6:
		var a := TAU * i / 6.0 + _lp.rng.randf()
		var base := Vector3(cos(a), 0, sin(a)) * 0.06
		_lp.blade(base, Vector3(cos(a), 0, sin(a)), 0.04, 0.35 + _lp.rng.randf() * 0.15, 0.25, Color(0.35, 0.55, 0.22))


func _build_reed() -> void:
	for i in 7:
		var a := TAU * i / 7.0 + _lp.rng.randf()
		var base := Vector3(cos(a), 0, sin(a)) * 0.1
		_lp.blade(base, Vector3(cos(a), 0, sin(a)), 0.035, 1.1 + _lp.rng.randf() * 0.4, 0.08, Color(0.45, 0.55, 0.28))
	_lp.cylinder(Vector3(0, 1.2, 0), 0.04, 0.04, 0.22, 5, Color(0.4, 0.26, 0.14))


func _build_stone() -> void:
	_lp.blob(Vector3(0, 0.12, 0), Vector3(0.35, 0.22, 0.3), 3, 5, Color(0.5, 0.49, 0.46), 0.3)
