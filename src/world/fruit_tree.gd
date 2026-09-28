@tool
class_name FruitTree
extends StaticBody3D
## Baum mit erreichbaren Früchten in bestimmter Höhe – Ziel für Kletter- und
## Sammelaufgaben (M4/M5). Stamm hat Kollision, Früchte sind Markierungen.

signal fruit_taken(remaining: int)

const FRUIT_COLOR := Color(0.85, 0.2, 0.15)

@export var tree_height := 6.0
@export var fruit_count := 3
## Höhe der Früchte über dem Boden in Metern.
@export var fruit_height := 4.5
@export var seed_value := 0

var fruits: Array[Node3D] = []


func _ready() -> void:
	add_to_group("fruit_tree")
	var lp := LowPoly.new(seed_value)
	var trunk_h := tree_height * 0.55
	lp.cylinder(Vector3.ZERO, 0.28, 0.18, trunk_h, 7, VegetationMeshes.TRUNK)
	var crown_r := tree_height * 0.3
	lp.blob(Vector3(0, trunk_h + crown_r * 0.5, 0), Vector3(crown_r, crown_r * 0.8, crown_r), 3, 8, Color(0.22, 0.42, 0.2), 0.2)
	# Ast Richtung Früchte
	lp.cylinder(Vector3(0, trunk_h * 0.7, 0), 0.1, 0.06, 1.2, 5, VegetationMeshes.TRUNK)
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit(VegetationMeshes.material())
	add_child(mi, false, Node.INTERNAL_MODE_BACK)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = trunk_h
	cs.shape = cap
	cs.position.y = trunk_h * 0.5
	add_child(cs, false, Node.INTERNAL_MODE_BACK)

	var fruit_mesh := SphereMesh.new()
	fruit_mesh.radius = 0.13
	fruit_mesh.height = 0.26
	fruit_mesh.radial_segments = 8
	fruit_mesh.rings = 4
	var fruit_mat := StandardMaterial3D.new()
	fruit_mat.albedo_color = FRUIT_COLOR
	fruit_mesh.material = fruit_mat
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in fruit_count:
		var a := TAU * i / maxi(1, fruit_count) + rng.randf() * 0.5
		var f := MeshInstance3D.new()
		f.mesh = fruit_mesh
		f.position = Vector3(cos(a) * crown_r * 0.85, fruit_height + rng.randf_range(-0.3, 0.3), sin(a) * crown_r * 0.85)
		f.add_to_group("fruit")
		add_child(f, false, Node.INTERNAL_MODE_BACK)
		fruits.append(f)


func fruit_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for f in fruits:
		if f.visible:
			out.append(f.global_position)
	return out


func remaining_fruits() -> int:
	return fruit_positions().size()


## Entfernt eine Frucht; liefert false, wenn keine mehr übrig ist.
func take_fruit() -> bool:
	for f in fruits:
		if f.visible:
			f.visible = false
			fruit_taken.emit(remaining_fruits())
			return true
	return false
