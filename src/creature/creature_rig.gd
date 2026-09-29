class_name CreatureRig
extends RefCounted
## Knochenaufbau einer Kreatur. Alle Ruhe-Transformationen haben eine
## Einheitsbasis; nur die Positionen unterscheiden sich. Beinknochen zeigen in
## Ruhe entlang -Y.
##
##   root (Körpermitte)
##   ├─ seg_0 … seg_n   (Rumpfsegmente, 0 = vorne)
##   ├─ head
##   ├─ tail_0 ─ tail_1 ─ tail_2
##   └─ leg_i_upper ─ leg_i_lower   (pro Bein)

const TAIL_BONES := 3

var plan: BodyPlan
var names: PackedStringArray = []
var parents: PackedInt32Array = []
## Ruheposition relativ zum Elternknochen.
var local_rest: PackedVector3Array = []
## Ruheposition im Skelett-Raum (= Kreatur-Raum).
var global_rest: PackedVector3Array = []

var root := -1
var segments: PackedInt32Array = []
var head := -1
var tail: PackedInt32Array = []
var upper: PackedInt32Array = []
var lower: PackedInt32Array = []


func _init(p_plan: BodyPlan) -> void:
	plan = p_plan
	root = _add("root", -1, Vector3(0.0, plan.body_center_y, 0.0))
	for i in plan.segment_count:
		segments.append(_add("seg_%d" % i, root, Vector3(0.0, 0.0, plan.segment_z[i])))
	head = _add("head", root, plan.head_center)
	var tail_step := maxf(plan.tail_length, 0.01) / TAIL_BONES
	var parent := root
	for i in TAIL_BONES:
		var offset := Vector3(0.0, 0.0, plan.body_length * 0.45) if i == 0 else Vector3(0.0, 0.0, tail_step)
		parent = _add("tail_%d" % i, parent, offset)
		tail.append(parent)
	for leg in plan.leg_count:
		var u := _add("leg_%d_upper" % leg, root, plan.hips[leg])
		upper.append(u)
		lower.append(_add("leg_%d_lower" % leg, u, Vector3(0.0, -plan.upper_leg, 0.0)))


func bone_count() -> int:
	return names.size()


func _add(bone_name: String, parent: int, local: Vector3) -> int:
	names.append(bone_name)
	parents.append(parent)
	local_rest.append(local)
	global_rest.append(local if parent < 0 else global_rest[parent] + local)
	return names.size() - 1


## Erzeugt das Skeleton3D mit allen Knochen in Ruhehaltung.
func create_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for i in names.size():
		sk.add_bone(names[i])
		if parents[i] >= 0:
			sk.set_bone_parent(i, parents[i])
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, local_rest[i]))
	sk.reset_bone_poses()
	return sk


## Nächstgelegener Segmentknochen zu einer z-Position.
func segment_bone_at(z: float) -> int:
	var best := segments[0]
	var best_d := INF
	for i in segments.size():
		var d := absf(plan.segment_z[i] - z)
		if d < best_d:
			best_d = d
			best = segments[i]
	return best
