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
## Namensschilder sind bis zu dieser Kameradistanz sichtbar.
const TAG_DISTANCE := 24.0
const TAG_PIXEL_SIZE := 0.0015

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

## Fähigkeiten (gesetzt von der Welt, ab M4).
var abilities: AbilityProfile
## Gerade ausgeführtes Verhalten (Anzeige/Debug).
var behavior_label := ""
## true = ein Verhalten setzt Position/Drehung selbst (Klettern, Schwimmen …);
## dann keine eigene Fortbewegung und keine Bodenhaftung.
var scripted := false
## Getragener Gegenstand (folgt Maul bzw. Rücken), null = nichts.
var held_item: Node3D
## Radius der Grundfläche (für Abstand halten, siehe BodyPlan.footprint_radius).
var radius := 0.5
## Namensschild über der Kreatur (null = keins).
var tag: Label3D
var _tag_height := 1.0

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
	radius = plan.footprint_radius()
	var top := maxf(plan.body_center_y + plan.half_height + plan.crest_height, plan.body_center_y + plan.head_center.y + plan.head_radius)
	_tag_height = top + maxf(plan.horn_length, plan.antenna_length * 0.5) + 0.3
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
	if not scripted:
		_move(delta)
	if tag != null and tag.visible:
		tag.global_position = global_position + Vector3.UP * _tag_height
	if held_item != null:
		if is_instance_valid(held_item):
			held_item.global_position = hold_point(held_item.get("size") if held_item.get("size") != null else 0.2)
			held_item.rotation.y = rotation.y
		else:
			held_item = null
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


## Namensschild setzen (leerer Text = ausblenden). Bleibt aufrecht über der
## Kreatur, auch wenn sie klettert; ab TAG_DISTANCE ausgeblendet.
func set_tag(text: String, color := Color.WHITE) -> void:
	if tag == null:
		tag = Label3D.new()
		tag.name = "Tag"
		tag.top_level = true
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.fixed_size = true
		tag.font_size = 30
		tag.outline_size = 10
		tag.outline_modulate = Color(0, 0, 0, 0.85)
		tag.visibility_range_end = TAG_DISTANCE
		tag.no_depth_test = false
		tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tag)
	tag.text = text
	tag.modulate = color
	# wächst mit der Oberflächen-Skalierung mit (Handy)
	tag.pixel_size = TAG_PIXEL_SIZE * (get_tree().root.content_scale_factor if is_inside_tree() else 1.0)
	tag.visible = text != ""
	if tag.visible and is_inside_tree():
		tag.global_position = global_position + Vector3.UP * _tag_height


func set_eye_glow(value: float) -> void:
	material.set_shader_parameter("eye_glow", clampf(value, 0.0, 1.0))


## Setzt alle Verhaltens-Eingriffe zurück (Pose, Füße, Skript-Modus).
func clear_behavior_pose() -> void:
	scripted = false
	locomotion.foot_override = Callable()
	locomotion.pose_height = 0.0
	locomotion.pose_pitch = 0.0
	locomotion.pose_roll = 0.0
	locomotion.pose_scale = 1.0
	locomotion.head_pitch = 0.0


## Wo ein Gegenstand getragen wird: kleine im Maul, große auf dem Rücken.
func hold_point(item_size: float) -> Vector3:
	if item_size < plan.head_radius * 1.6:
		return global_transform * (plan.head_center + Vector3(0.0, plan.body_center_y - item_size * 0.4, -plan.head_radius * 0.9))
	return global_transform * Vector3(0.0, plan.body_center_y + plan.half_height * 0.85, 0.0)


## Legt den getragenen Gegenstand vor sich auf den Boden.
func drop_item() -> void:
	if held_item == null or not is_instance_valid(held_item):
		held_item = null
		return
	var s: float = held_item.get("size") if held_item.get("size") != null else 0.2
	var p := global_transform * Vector3(0.0, 0.0, -(plan.body_length * 0.5 + s))
	var y := _ground_height(p)
	held_item.global_position = Vector3(p.x, y if not is_nan(y) else global_position.y, p.z)
	held_item = null


## Bodenhöhe an einer Position (Raycast), NAN wenn kein Boden.
func ground_height_at(p: Vector3) -> float:
	return _ground_height(p)


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
