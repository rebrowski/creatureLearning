class_name BehaviorEffects
extends RefCounted
## Kleine, kurzlebige Effekte, die Fähigkeiten sichtbar machen
## (Erdbrocken, Rufwellen, Löcher, Duftwolken, Wasserringe). Mobilgerecht:
## CPU-Partikel mit wenigen Teilchen, einfache Meshes, Tweens.

static var _dirt_mat: StandardMaterial3D
static var _ring_mesh: TorusMesh
static var _disc_mesh: CylinderMesh


static func dirt_burst(parent: Node, pos: Vector3, strength: float) -> void:
	if strength <= 0.02:
		return
	Sound.play("dig", pos)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = int(4 + strength * 14)
	p.lifetime = 0.7
	p.explosiveness = 0.9
	p.direction = Vector3(0, 1, 0)
	p.spread = 50.0
	p.initial_velocity_min = 1.0 + strength
	p.initial_velocity_max = 2.0 + strength * 2.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var m := BoxMesh.new()
	m.size = Vector3.ONE * 0.05
	if _dirt_mat == null:
		_dirt_mat = StandardMaterial3D.new()
		_dirt_mat.albedo_color = Color(0.3, 0.22, 0.14)
	m.material = _dirt_mat
	p.mesh = m
	_spawn(parent, p, pos, 1.2)
	p.emitting = true


## Sich ausbreitender Ring (Ruf, Wasserwelle). radius in Metern.
static func ring(parent: Node, pos: Vector3, radius: float, color: Color, duration := 1.0) -> void:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.9
		_ring_mesh.outer_radius = 1.0
		_ring_mesh.rings = 24
		_ring_mesh.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mi.material_override = mat
	_spawn(parent, mi, pos, duration + 0.1)
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)


## Loch im Boden, wächst auf `radius` und verblasst nach `lifetime` Sekunden.
static func hole(parent: Node, pos: Vector3, radius: float, grow_time: float, lifetime := 25.0) -> Node3D:
	if _disc_mesh == null:
		_disc_mesh = CylinderMesh.new()
		_disc_mesh.top_radius = 1.0
		_disc_mesh.bottom_radius = 1.0
		_disc_mesh.height = 0.02
		_disc_mesh.radial_segments = 12
		_disc_mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = _disc_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.08, 0.05)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	_spawn(parent, mi, pos + Vector3(0, 0.02, 0), lifetime + 3.0)
	mi.scale = Vector3(0.05, 1, 0.05)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), grow_time)
	tw.tween_interval(lifetime)
	tw.tween_property(mat, "albedo_color:a", 0.0, 3.0)
	return mi


static func scent_puff(parent: Node, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.12
	s.radial_segments = 6
	s.rings = 3
	mi.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 0.7, 0.6)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(parent, mi, pos, 1.3)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "position", pos + Vector3(0, 0.5, 0), 1.2)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.2)


## Gegenstand treibt auf dem Wasser mit der Strömung davon und geht langsam unter.
static func float_away(item: Node3D, layout: ForestLayout, flow: Vector2, duration: float) -> void:
	var start := item.global_position
	var tw := item.create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(item):
			return
		var p := start + Vector3(flow.x, 0.0, flow.y) * t * duration * 0.7
		var wl := layout.water_level_at(p.x, p.z)
		var ground := layout.height_at(p.x, p.z)
		var sink := smoothstep(0.6, 1.0, t) * 0.3
		p.y = maxf(ground, wl - 0.05 - sink + sin(t * 20.0) * 0.03)
		item.global_position = p
		item.rotation.y += 0.02, 0.0, 1.0, duration)


static func _spawn(parent: Node, node: Node3D, pos: Vector3, lifetime: float) -> void:
	parent.add_child(node)
	node.global_position = pos
	var timer := parent.get_tree().create_timer(lifetime)
	timer.timeout.connect(node.queue_free)
