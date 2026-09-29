class_name CarryItem
extends Node3D
## Tragbarer Gegenstand (Stein). Gewicht 0..1 relativ zur Größe.

@export var size := 0.3
@export var seed_value := 0

var weight := 0.3
var claimed_by: Node = null


func _ready() -> void:
	add_to_group("carry_item")
	weight = clampf(pow(size / 0.5, 2.0), 0.05, 1.0)
	var lp := LowPoly.new(seed_value)
	lp.blob(Vector3(0, size * 0.4, 0), Vector3(size, size * 0.75, size * 0.85), 3, 6, Color(0.55, 0.52, 0.46), 0.3)
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit(VegetationMeshes.material())
	add_child(mi)


func is_free() -> bool:
	return claimed_by == null or not is_instance_valid(claimed_by)
