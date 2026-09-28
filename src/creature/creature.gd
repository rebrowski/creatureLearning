class_name Creature
extends Node3D
## Eine Kreatur in der Welt: baut Skelett und Mesh aus dem Genom, bewegt sich
## Richtung `desired_velocity` und läuft prozedural.
##
## Steuerung von außen (Verhalten, später M4): `desired_velocity` setzen.
## Die Kreatur dreht sich in Laufrichtung und passt ihre Höhe dem Boden an
## (Raycast auf `ground_mask`). Kreaturen selbst haben keine Kollision.

const SHADER := preload("res://src/mesh/creature.gdshader")
const PATTERN_IDS := {"none": 0, "stripes": 1, "spots": 2, "bands": 3}

@export_flags_3d_physics var ground_mask := 1
## Maximale Drehrate in rad/s.
@export var turn_speed := 2.5
## Beschleunigung in m/s².
@export var acceleration := 3.0

var genome: Genome
var individual: Individual
var plan: BodyPlan
var rig: CreatureRig
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var locomotion: CreatureLocomotion
var material: ShaderMaterial
var label := ""

var desired_velocity := Vector3.ZERO
var velocity := Vector3.ZERO
var lod_level := CreatureLOD.FULL
## Automatische LOD-Wahl nach Kameradistanz.
var auto_lod := true

var _meshes: Array[ArrayMesh] = []
var _ray: PhysicsRayQueryParameters3D
var _lod_timer := 0.0
var _frame := 0
var _pending_delta := 0.0


## Baut die Kreatur. Vor oder nach add_child aufrufbar.
func setup(p_genome: Genome, p_label := "") -> void:
	genome = p_genome
	label = p_label
	plan = BodyPlan.from_genome(genome)
	rig = CreatureRig.new(plan)
	skeleton = rig.create_skeleton()
	add_child(skeleton)
	_meshes = [CreatureMeshBuilder.build(plan, rig, 0), CreatureMeshBuilder.build(plan, rig, 1)]
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("body_color", Color.from_hsv(genome.f("hue"), genome.f("saturation"), genome.f("brightness")))
	material.set_shader_parameter("pattern_type", PATTERN_IDS.get(genome.option("pattern_type"), 0))
	material.set_shader_parameter("pattern_frequency", float(genome.effective("pattern_density")) / maxf(0.05, plan.segment_half_length * 2.0))
	material.set_shader_parameter("pattern_contrast", float(genome.effective("pattern_contrast")))
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Body"
	mesh_instance.mesh = _meshes[0]
	mesh_instance.material_override = material
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = ground_mask
	locomotion = CreatureLocomotion.new(plan, rig, skeleton, _ground_height)
	if is_inside_tree():
		_snap_to_ground()
		locomotion.reset(global_transform)


func setup_individual(ind: Individual, species_name := "") -> void:
	individual = ind
	setup(ind.genome, "%s %s" % [species_name, ind.short_label()])


func _ready() -> void:
	if locomotion != null:
		_snap_to_ground()
		locomotion.reset(global_transform)


func _physics_process(delta: float) -> void:
	if locomotion == null:
		return
	_frame += 1
	_update_lod(delta)
	_move(delta)
	match lod_level:
		CreatureLOD.FULL:
			locomotion.update(delta, global_transform, velocity, true)
		CreatureLOD.REDUCED:
			_pending_delta += delta
			if _frame % 2 == 0:
				locomotion.update(_pending_delta, global_transform, velocity, false)
				_pending_delta = 0.0
		_:
			pass


func _move(delta: float) -> void:
	var desired := Vector3(desired_velocity.x, 0.0, desired_velocity.z)
	var desired_speed := minf(desired.length(), plan.move_speed * 1.5)
	var forward := -global_transform.basis.z
	if desired_speed > 0.01:
		# in Laufrichtung drehen
		var target_yaw := atan2(-desired.x, -desired.z)
		var diff := wrapf(target_yaw - rotation.y, -PI, PI)
		rotation.y += clampf(diff, -turn_speed * delta, turn_speed * delta)
		# langsamer, solange die Richtung noch nicht passt
		desired_speed *= clampf(forward.dot(desired.normalized()), 0.2, 1.0)
	var speed := move_toward(velocity.length(), desired_speed, acceleration * delta)
	velocity = -global_transform.basis.z * speed
	global_position += velocity * delta
	if lod_level <= CreatureLOD.REDUCED or _frame % 8 == 0:
		_snap_to_ground()


func _snap_to_ground() -> void:
	var y := _ground_height(global_position)
	if not is_nan(y):
		global_position.y = y


func _ground_height(p: Vector3) -> float:
	if not is_inside_tree():
		return NAN
	_ray.from = Vector3(p.x, p.y + 3.0, p.z)
	_ray.to = Vector3(p.x, p.y - 6.0, p.z)
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	return hit.position.y if not hit.is_empty() else NAN


# --- LOD ----------------------------------------------------------------------

func _update_lod(delta: float) -> void:
	if not auto_lod:
		return
	_lod_timer -= delta
	if _lod_timer > 0.0:
		return
	_lod_timer = 0.25 + randf() * 0.1  # verteilt die Prüfungen über Frames
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	set_lod(CreatureLOD.level_for(cam.global_position.distance_to(global_position), lod_level))


func set_lod(level: int) -> void:
	if level == lod_level:
		return
	var was_frozen := lod_level >= CreatureLOD.FROZEN
	lod_level = level
	mesh_instance.mesh = _meshes[1] if level >= CreatureLOD.FROZEN else _meshes[0]
	visible = level != CreatureLOD.HIDDEN
	if was_frozen and level <= CreatureLOD.REDUCED:
		locomotion.reset(global_transform)
