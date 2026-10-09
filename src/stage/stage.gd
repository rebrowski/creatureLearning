class_name Stage
extends Node3D
## Die Bühne: eine beleuchtete Lichtung abseits des Lagers, auf der Proben und
## Aufgaben ablaufen. Nur die Beteiligten stehen dort, schon am Startpunkt; jede
## Fähigkeit hat einen eindeutigen, abgestuften Beweis-Moment (Stufe 0–3):
##
##   trunk       Klettern     Stamm mit zwei Ringen, oben die Frucht
##   stream      Schwimmen    Bach mit Fahne am anderen Ufer (Waten zählt)
##   mounds      Wittern      vier Erdhügel, unter einem eine Knolle
##   dark_path   Nachtsicht   dunkler Pfad mit Abzweigung, am Ende ein Licht
##   hard_ground Graben       harter Boden; der Erdhaufen zeigt, wie tief es ging
##   stone       Tragen       schwerer Stein und Zielkreis
##   posts       Lärm         drei Pfosten mit Glöckchen in 3, 6, 9 m
##   raider      Verscheuchen ein Räuber am Rand der Lichtung
##
## Alles in lokalen Koordinaten der Bühne; die Kreaturen laufen hier ohne
## Navigation (scripted). Die Bühne hat eine eigene Kamera.

signal caption(text: String)

const SIZE := 60.0
const LIT_RADIUS := 7.0
const START := Vector3(-3.0, 0.0, 0.0)
const FRUIT_COLOR := Color(0.85, 0.2, 0.15)
const KNOLLE_COLOR := Color(0.55, 0.38, 0.2)
const TRUNK := Vector3(1.0, 0.0, 0.0)
const TRUNK_RADIUS := 0.28
const RINGS := [1.3, 2.5]
const FRUIT_HEIGHT := 3.6
const BANK_A := -0.9
const BANK_B := 2.1
const FLAG_X := 2.9
const MOUND_POS := [Vector3(1.2, 0, -1.6), Vector3(2.2, 0, -0.55), Vector3(2.2, 0, 0.6), Vector3(1.2, 0, 1.65)]
const FORK := Vector3(0.4, 0, 0)
const GOAL := Vector3(3.0, 0, 1.6)
const DEAD_END := Vector3(3.0, 0, -1.6)
const OBSTACLE := Vector3(-1.4, 0, 0.0)
const HOLE := Vector3(0.6, 0, 0)
const STONE_POS := Vector3(-1.2, 0, 0)
const TARGET_POS := Vector3(2.4, 0, 0)
const POSTS_X := [0.0, 3.0, 6.0]
const RAIDER_POS := Vector3(2.6, 0, 0)

var camera: Camera3D
## Kreaturen, die gerade auf der Bühne stehen
var actors: Array[Creature] = []
## Requisiten des aktuellen Abschnitts (Name -> Node3D)
var props: Dictionary = {}

var _props_root: Node3D
var _spot: SpotLight3D
var _cam_target := Vector3.ZERO
var _cam_pos := Vector3(0, 4, 7)
var _ground_layer := 1
var _rng := RandomNumberGenerator.new()


func build(ground_layer: int) -> void:
	_ground_layer = ground_layer
	_rng.seed = 4242
	var body := StaticBody3D.new()
	body.collision_layer = ground_layer
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE, 1.0, SIZE)
	cs.shape = box
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	ground.mesh = pm
	ground.material_override = _mat(Color(0.16, 0.22, 0.14))
	add_child(ground)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = LIT_RADIUS
	cm.bottom_radius = LIT_RADIUS
	cm.height = 0.02
	cm.radial_segments = 48
	disc.mesh = cm
	disc.position = Vector3(0.6, 0.005, 0)
	disc.material_override = _mat(Color(0.36, 0.46, 0.26))
	add_child(disc)
	# Bäume als Rahmen
	var pine := VegetationMeshes.build("tree_pine")
	var round := VegetationMeshes.build("tree_round")
	for i in 22:
		var a := TAU * i / 22.0 + _rng.randf() * 0.2
		var r := LIT_RADIUS + 4.0 + _rng.randf() * 4.0
		var t := MeshInstance3D.new()
		t.mesh = pine if i % 3 != 0 else round
		t.scale = Vector3.ONE * _rng.randf_range(1.2, 2.0)
		t.position = Vector3(0.6 + cos(a) * r, 0, sin(a) * r)
		add_child(t)
	_spot = SpotLight3D.new()
	_spot.position = Vector3(0.6, 9, 2.5)
	_spot.rotation_degrees = Vector3(-74, 0, 0)
	_spot.spot_range = 22.0
	_spot.spot_angle = 40.0
	_spot.light_energy = 0.0
	_spot.shadow_enabled = false
	add_child(_spot)
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.far = 200.0
	add_child(camera)
	frame(Vector3(0.6, 0.6, 0), 8.0, 4.0, true)


func _process(delta: float) -> void:
	if camera == null or not camera.current:
		return
	var k := 1.0 - exp(-4.0 * delta)
	camera.global_position = camera.global_position.lerp(to_global(_cam_pos), k)
	camera.look_at(to_global(_cam_target), Vector3.UP)


## Kamera auf einen Punkt richten (Abstand, Höhe; seitlich leicht versetzt).
func frame(target: Vector3, distance := 7.5, height := 3.6, instant := false) -> void:
	_cam_target = target
	_cam_pos = target + Vector3(-1.2, height, distance)
	if instant and camera != null and camera.is_inside_tree():
		camera.global_position = to_global(_cam_pos)
		camera.look_at(to_global(_cam_target), Vector3.UP)


## Bühne nachts: Scheinwerfer an (die Welt verdunkelt den Himmel).
func set_night(on: bool) -> void:
	_spot.light_energy = 2.2 if on else 0.0


func clear() -> void:
	for c in actors:
		if is_instance_valid(c):
			c.queue_free()
	actors.clear()
	for n in _props_root.get_children():
		n.queue_free()
	props.clear()


func spawn_actor(m: GroupMember, at: Vector3, face := Vector3.RIGHT, catalog: AbilityCatalog = null) -> Creature:
	var c := Creature.new()
	c.auto_lod = false
	c.name = "Actor_%d" % actors.size()
	c.position = at
	c.rotation.y = atan2(-face.x, -face.z)
	add_child(c)
	c.setup_individual(m.to_individual(), m.name)
	c.label = m.name
	if catalog != null:
		c.abilities = AbilityProfile.new(catalog, m.genome)
	c.set_tag(m.name, Color(1, 0.95, 0.7))
	c.locomotion.reset(c.global_transform)
	actors.append(c)
	return c


# --- Requisiten -------------------------------------------------------------------

func build_prop(kind: String, opts: Dictionary = {}) -> void:
	match kind:
		"trunk":
			var lp := LowPoly.new(3)
			lp.cylinder(Vector3.ZERO, TRUNK_RADIUS, 0.18, FRUIT_HEIGHT + 0.6, 8, VegetationMeshes.TRUNK)
			lp.blob(Vector3(0, FRUIT_HEIGHT + 1.0, 0), Vector3(1.4, 1.0, 1.4), 3, 8, Color(0.22, 0.42, 0.2), 0.2)
			var tree := _mesh_node(lp, TRUNK)
			for h in RINGS:
				var ring := _torus(TRUNK_RADIUS + 0.06, Color(1.0, 0.9, 0.5), 0.05)
				ring.position = Vector3(0, h, 0)
				tree.add_child(ring)
			var fruit := _sphere(0.14, FRUIT_COLOR)
			fruit.position = Vector3(0.0, FRUIT_HEIGHT, TRUNK_RADIUS + 0.2)
			tree.add_child(fruit)
			props.tree = tree
			props.fruit = fruit
		"stream":
			var water := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(BANK_B - BANK_A, 0.04, 14.0)
			water.mesh = bm
			var wm := _mat(Color(0.2, 0.45, 0.75))
			wm.roughness = 0.15
			water.material_override = wm
			water.position = Vector3((BANK_A + BANK_B) * 0.5, 0.04, 0)
			_props_root.add_child(water)
			props.water = water
			var pole := _box(Vector3(0.05, 1.4, 0.05), Color(0.5, 0.4, 0.3))
			pole.position = Vector3(FLAG_X, 0.7, 0)
			_props_root.add_child(pole)
			var flag := _box(Vector3(0.02, 0.32, 0.5), Color(0.95, 0.3, 0.25))
			flag.position = Vector3(FLAG_X, 1.24, 0.27)
			_props_root.add_child(flag)
			props.flag = flag
		"mounds":
			var correct: int = opts.get("correct", 0)
			var list := []
			for i in MOUND_POS.size():
				var lp := LowPoly.new(10 + i)
				lp.blob(Vector3(0, 0.05, 0), Vector3(0.38, 0.22, 0.38), 2, 7, Color(0.42, 0.3, 0.2), 0.15)
				var mound := _mesh_node(lp, MOUND_POS[i])
				if i == correct:
					var kn := _sphere(0.13, KNOLLE_COLOR)
					kn.position = Vector3(0, -0.2, 0)
					kn.visible = false
					mound.add_child(kn)
					props.knolle = kn
				list.append(mound)
			props.mounds = list
			props.correct = correct
		"dark_path":
			# leuchtende Wegsteine zur Abzweigung und weiter zum Ziel bzw. in die Sackgasse
			var dots := []
			for seg in [[START, FORK], [FORK, GOAL], [FORK, DEAD_END]]:
				for k in 6:
					var d := _sphere(0.05, Color(0.6, 0.8, 1.0), 0.15)
					d.position = seg[0].lerp(seg[1], (k + 0.5) / 6.0) + Vector3(0, 0.03, 0)
					_props_root.add_child(d)
					dots.append(d)
			props.dots = dots
			var lp := LowPoly.new(7)
			lp.blob(Vector3(0, 0.18, 0), Vector3(0.3, 0.25, 0.3), 2, 6, Color(0.45, 0.45, 0.42), 0.25)
			props.obstacle = _mesh_node(lp, OBSTACLE + Vector3(0, 0, 0.1))
			var lp2 := LowPoly.new(8)
			lp2.blob(Vector3(0, 0.4, 0), Vector3(0.6, 0.55, 0.5), 2, 6, Color(0.4, 0.4, 0.38), 0.25)
			_mesh_node(lp2, DEAD_END + Vector3(0.6, 0, 0))
			var goal := _sphere(0.18, Color(1.0, 0.85, 0.4), 2.0)
			goal.position = GOAL + Vector3(0, 0.4, 0)
			_props_root.add_child(goal)
			var gl := OmniLight3D.new()
			gl.light_color = Color(1.0, 0.85, 0.5)
			gl.light_energy = 1.2
			gl.omni_range = 2.5
			goal.add_child(gl)
			props.goal = goal
		"hard_ground":
			var hole := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			cm.height = 0.02
			hole.mesh = cm
			hole.material_override = _mat(Color(0.3, 0.24, 0.18))
			hole.position = HOLE + Vector3(0, 0.012, 0)
			_props_root.add_child(hole)
			props.hole = hole
			var lp := LowPoly.new(5)
			lp.blob(Vector3(0, 0.2, 0), Vector3(0.45, 0.3, 0.45), 2, 7, Color(0.4, 0.3, 0.2), 0.2)
			var pile := _mesh_node(lp, HOLE + Vector3(0.9, 0, -0.6))
			pile.scale = Vector3.ONE * 0.05
			props.pile = pile
			# Tiefenmarke: Stab mit drei Kerben – so hoch wird der Erdhaufen bei voller Tiefe
			var pole := _box(Vector3(0.05, 0.9, 0.05), Color(0.85, 0.8, 0.6))
			pole.position = HOLE + Vector3(0.9, 0.45, -1.15)
			_props_root.add_child(pole)
			var kn := _sphere(0.13, KNOLLE_COLOR)
			kn.position = HOLE + Vector3(0, -0.2, 0)
			kn.visible = false
			_props_root.add_child(kn)
			props.knolle = kn
		"stone":
			var stone := CarryItem.new()
			stone.size = 0.32
			stone.seed_value = 3
			stone.position = STONE_POS
			_props_root.add_child(stone)
			stone.remove_from_group("carry_item")  # nicht für das Lager
			props.stone = stone
			var ring := _torus(0.7, Color(1, 1, 1, 0.8), 0.05)
			ring.position = TARGET_POS + Vector3(0, 0.03, 0)
			_props_root.add_child(ring)
			props.target = ring
		"posts":
			var posts := []
			for x in POSTS_X:
				var post := _box(Vector3(0.1, 1.3, 0.1), Color(0.5, 0.38, 0.25))
				post.position = Vector3(x, 0.65, -0.8)
				_props_root.add_child(post)
				var bell := _sphere(0.11, Color(0.95, 0.8, 0.3), 0.0)
				bell.position = Vector3(0, 0.7, 0.12)
				post.add_child(bell)
				posts.append(post)
			props.posts = posts
		"raider":
			var raider := Node3D.new()
			raider.position = RAIDER_POS
			raider.rotation.y = -PI * 0.5
			_props_root.add_child(raider)
			var lp := LowPoly.new(9)
			lp.blob(Vector3(0, 0.45, 0), Vector3(0.35, 0.4, 0.55), 2, 7, Color(0.08, 0.08, 0.1), 0.2)
			lp.blob(Vector3(0, 0.75, -0.45), Vector3(0.22, 0.2, 0.22), 2, 6, Color(0.08, 0.08, 0.1), 0.1)
			var mi := MeshInstance3D.new()
			mi.mesh = lp.commit(VegetationMeshes.material())
			raider.add_child(mi)
			for s in [-1.0, 1.0]:
				var eye := _sphere(0.045, Color(1.0, 0.25, 0.15), 3.0)
				eye.position = Vector3(s * 0.09, 0.8, -0.63)
				raider.add_child(eye)
			props.raider = raider


# --- Beweis-Momente ---------------------------------------------------------------

## Führt den Beweis-Moment einer Requisite mit Stufe 0–3 aus.
## opts: "item" (getragener Gegenstand), "wade" (watet), "drop_fruit" (Klettern: Frucht fällt)
func perform(kind: String, c: Creature, g: int, opts: Dictionary = {}) -> void:
	match kind:
		"trunk":
			await _climb(c, g, opts)
		"stream":
			await _swim(c, g, opts)
		"mounds":
			await _seek(c, g)
		"dark_path":
			await _dark_path(c, g)
		"hard_ground":
			await _dig(c, g)
		"stone":
			await _carry(c, g)
		"posts":
			await _call(c, g)
		"raider":
			await _scare(c, g)


## Startpunkt und Blickrichtung je Requisite.
static func start_for(kind: String) -> Vector3:
	match kind:
		"trunk":
			return TRUNK + Vector3(-1.6, 0, 0.3)
		"stream":
			return Vector3(BANK_A - 1.3, 0, 0)
		"stone":
			return STONE_POS + Vector3(-1.3, 0, 0)
		_:
			return START


## Kamerablickpunkt je Requisite.
static func focus_for(kind: String) -> Array:
	match kind:
		"trunk":
			return [TRUNK + Vector3(-0.4, 1.8, 0), 7.0, 2.6]
		"posts":
			return [Vector3(1.5, 0.5, 0), 10.0, 4.5]
		"dark_path":
			return [Vector3(0.2, 0.3, 0), 7.5, 4.5]
		_:
			return [Vector3(0.3, 0.5, 0), 7.0, 3.6]


func _climb(c: Creature, g: int, opts: Dictionary) -> void:
	var base := to_global(TRUNK)
	await _move(c, TRUNK + Vector3(-(TRUNK_RADIUS + c.plan.body_length * 0.5 + 0.35), 0, 0.15), 0.8)
	var out := Vector3(c.global_position.x - base.x, 0, c.global_position.z - base.z).normalized()
	var ground_xf := c.global_transform
	var h0 := c.plan.body_length * 0.5 + c.plan.head_radius
	var heights := [h0 + 0.25, RINGS[0], RINGS[1], FRUIT_HEIGHT - c.plan.body_length * 0.3]
	var st := {"h": h0, "blend": 0.0, "moving": false}
	var cling := func() -> Transform3D:
		var y_axis := out
		var z_axis := Vector3.DOWN
		var x_axis := y_axis.cross(z_axis).normalized()
		return Transform3D(Basis(x_axis, y_axis, z_axis), base + Vector3.UP * float(st.h) + out * (TRUNK_RADIUS + 0.03))
	var apply := func() -> void:
		c.global_transform = ground_xf.interpolate_with(cling.call(), float(st.blend))
		c.velocity = Vector3.UP * (1.2 if st.moving else 0.0)
	c.scripted = true
	c.locomotion.foot_override = func(leg: int, hip: Vector3) -> Variant:
		if float(st.blend) < 0.5:
			return null
		var axis := Vector3(base.x, hip.y, base.z)
		var radial := Vector3(hip.x - axis.x, 0.0, hip.z - axis.z)
		if radial.length() < 0.01:
			radial = out
		var foot := axis + radial.normalized() * TRUNK_RADIUS
		if st.moving:
			foot.y += sin(Time.get_ticks_msec() * 0.009 + leg * PI) * 0.08
		return foot
	Sound.play("climb", c.global_position, c)
	await _tween_value(st, "blend", 0.0, 1.0, 0.45, apply)
	st.moving = true
	var target: float = heights[g]
	await _tween_value(st, "h", h0, target, maxf(0.5, (target - h0) / 1.5), apply)
	st.moving = false
	if g == 3:
		c.locomotion.head_pitch = 0.3
		await wait(0.4)
		if props.has("fruit") and is_instance_valid(props.fruit):
			var fruit: Node3D = props.fruit
			if opts.get("drop_fruit", false):
				var land := TRUNK + Vector3(0.0, 0.14, 1.0)
				var tw := fruit.create_tween()
				tw.tween_property(fruit, "global_position", to_global(land), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			else:
				fruit.visible = false
				_label(c, "✓", Color(0.6, 1.0, 0.5))
		c.locomotion.head_pitch = 0.0
		st.moving = true
		await _tween_value(st, "h", target, h0, (target - h0) / 2.2, apply)
	else:
		await wait(0.35)
		_label(c, "✗", Color(1.0, 0.55, 0.45))
		await _tween_value(st, "h", target, h0, maxf(0.25, (target - h0) / 5.0), apply)
	st.moving = false
	await _tween_value(st, "blend", 1.0, 0.0, 0.35, apply)
	c.global_transform = ground_xf
	c.locomotion.foot_override = Callable()
	c.locomotion.reset(c.global_transform)
	c.velocity = Vector3.ZERO
	c.scripted = false


func _swim(c: Creature, g: int, opts: Dictionary) -> void:
	var item: Node3D = opts.get("item")
	if item != null:
		c.held_item = item
	await _move(c, Vector3(BANK_A - 0.15, 0, 0), 0.6)
	if opts.get("wade", false):
		Sound.play("splash", c.global_position, c)
		var wade_fx := func(t: float) -> void: _ripple(c, t, 0.7)
		await _move(c, Vector3(FLAG_X - 0.5, 0, 0), 2.2, wade_fx)
		_finish_carry(c, Vector3(FLAG_X - 0.2, 0, 0.3))
		return
	if g == 0:
		c.locomotion.head_pitch = 0.45
		c.locomotion.pose_pitch = 0.12
		var p0 := c.position
		for k in 3:
			await _move(c, p0 + Vector3(0.18, 0, 0), 0.35)
			await _move(c, p0, 0.35)
		c.locomotion.head_pitch = 0.0
		c.locomotion.pose_pitch = 0.0
		_label(c, "✗", Color(1.0, 0.55, 0.45))
		await _move(c, Vector3(BANK_A - 1.3, 0, 0), 0.8)
		if item != null:
			c.drop_item()
		return
	var frac: float = [0.0, 0.28, 0.55, 1.0][g]
	var weak := 1.0 - g / 3.0
	c.locomotion.foot_override = func(leg: int, _hip: Vector3) -> Variant:
		var hip: Vector3 = c.global_transform * c.rig.global_rest[c.rig.upper[leg]]
		var phi := Time.get_ticks_msec() * 0.007 * (1.0 + weak) + leg * PI * 0.5
		var r := c.plan.leg_reach() * 0.35
		return hip + (-c.global_transform.basis.z) * cos(phi) * r + Vector3.DOWN * (r * 0.8 + sin(phi) * r * 0.5)
	c.locomotion.pose_pitch = 0.1 + weak * 0.25
	Sound.play("splash", c.global_position, c)
	var sink := c.plan.body_center_y * (0.55 + weak * 0.3)
	var target_x := BANK_A + (BANK_B - BANK_A) * frac
	var in_water := func(t: float) -> void:
		_ripple(c, t, 0.35 if g < 3 else 0.5)
		var x := c.position.x
		c.position.y = (-sink + sin(t * 9.0) * 0.05 * weak) if x > BANK_A + 0.1 and x < BANK_B - 0.1 else 0.0
	await _move(c, Vector3(target_x if g < 3 else BANK_B + 0.1, 0, 0), 1.0 + 1.6 * frac, in_water)
	if g < 3:
		_label(c, "✗", Color(1.0, 0.55, 0.45))
		if item != null:
			c.held_item = null
			Sound.play("splash", item.global_position, c)
			var tw := item.create_tween()
			tw.tween_property(item, "global_position", item.global_position + Vector3(0, -0.15, 3.5), 2.5)
		await _move(c, Vector3(BANK_A - 0.4, 0, 0), 1.0 + 1.2 * frac, in_water)
	c.locomotion.foot_override = Callable()
	c.locomotion.pose_pitch = 0.0
	c.position.y = 0.0
	c.locomotion.reset(c.global_transform)
	if g == 3:
		await _move(c, Vector3(FLAG_X - 0.4, 0, 0), 0.5)
		_label(c, "✓", Color(0.6, 1.0, 0.5))
		_finish_carry(c, Vector3(FLAG_X - 0.1, 0, 0.35))


func _finish_carry(c: Creature, at: Vector3) -> void:
	if c.held_item != null and is_instance_valid(c.held_item):
		var it := c.held_item
		c.held_item = null
		it.global_position = to_global(at)


func _seek(c: Creature, g: int) -> void:
	var mounds: Array = props.get("mounds", [])
	var correct: int = props.get("correct", 0)
	var wrong := []
	for i in mounds.size():
		if i != correct:
			wrong.append(i)
	var visits: Array = [[correct], [wrong[0], correct], [wrong[0], wrong[1]], []][3 - g]
	c.locomotion.head_pitch = -0.4
	c.locomotion.pose_pitch = -0.12
	var puff := func(t: float) -> void: _puff(c, t)
	if visits.is_empty():
		for p in [Vector3(-2.0, 0, 0.9), Vector3(-1.6, 0, -0.8), Vector3(-2.5, 0, 0.1)]:
			await _move(c, p, 0.9, puff)
		_label(c, "?", Color(1, 1, 1))
	for i in visits:
		var mound: Node3D = mounds[i]
		var dir := (mound.position - c.position).normalized()
		await _move(c, mound.position - dir * 0.55, 1.1, puff)
		c.locomotion.pose_pitch = -0.3
		for k in 2:
			BehaviorEffects.dirt_burst(_props_root, to_global(mound.position), 0.6, c)
			await wait(0.3)
		c.locomotion.pose_pitch = -0.12
		if i == correct:
			_reveal_knolle()
			_label(c, "✓", Color(0.6, 1.0, 0.5))
		else:
			var tw := mound.create_tween()
			tw.tween_property(mound, "scale", Vector3(1.0, 0.35, 1.0), 0.3)
			_label_at(mound.position + Vector3(0, 0.6, 0), "✗", Color(1.0, 0.55, 0.45))
	c.locomotion.head_pitch = 0.0
	c.locomotion.pose_pitch = 0.0
	if g < 3:
		await wait(0.4)
		_reveal_knolle()


func _reveal_knolle() -> void:
	if not props.has("knolle"):
		return
	var kn: Node3D = props.knolle
	if kn.visible:
		return
	kn.visible = true
	var tw := kn.create_tween()
	tw.tween_property(kn, "position:y", 0.45, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _dark_path(c: Creature, g: int) -> void:
	c.set_eye_glow(1.0 if g >= 2 else 0.25)
	var light_dots := func(t: float) -> void:
		for d in props.get("dots", []):
			if is_instance_valid(d) and d.position.distance_to(c.position) < 0.6:
				d.material_override.emission_energy_multiplier = 2.5
	match g:
		3:
			await _move(c, FORK, 1.3, light_dots)
			await _move(c, GOAL - Vector3(0.3, 0, 0.3), 1.2, light_dots)
			_label(c, "✓", Color(0.6, 1.0, 0.5))
		2:
			await _move(c, FORK, 1.5, light_dots)
			for yaw in [0.7, -0.7, 0.3]:
				await _turn(c, yaw, 0.4)
			await _move(c, GOAL - Vector3(0.3, 0, 0.3), 1.3, light_dots)
			_label(c, "✓", Color(0.6, 1.0, 0.5))
		1:
			await _move(c, OBSTACLE - Vector3(0.45, 0, 0), 0.9)
			await _move(c, OBSTACLE - Vector3(0.75, 0, 0), 0.25)  # stößt an und prallt zurück
			await _move(c, OBSTACLE + Vector3(0, 0, -0.6), 0.6)
			await _move(c, FORK, 0.8)
			await _move(c, DEAD_END - Vector3(0.2, 0, 0), 1.2)
			_label(c, "?", Color(1, 1, 1))
		_:
			await _move(c, START + Vector3(0.8, 0, 0), 0.9)
			for yaw in [0.8, -0.8]:
				await _turn(c, yaw, 0.5)
			_label(c, "?", Color(1, 1, 1))
	await wait(0.3)
	c.set_eye_glow(0.0)


func _dig(c: Creature, g: int) -> void:
	await _move(c, HOLE + Vector3(-0.75, 0, 0), 0.9)
	c.locomotion.pose_pitch = -0.3
	c.locomotion.head_pitch = -0.3
	var pile: Node3D = props.pile
	var sizes := [0.12, 0.35, 0.6, 0.85]
	var bursts := 1 + g * 2
	for k in bursts:
		BehaviorEffects.dirt_burst(_props_root, to_global(HOLE), 0.3 + 0.25 * g, c)
		var s: float = lerpf(0.05, sizes[g], float(k + 1) / bursts)
		pile.create_tween().tween_property(pile, "scale", Vector3.ONE * s, 0.25)
		await wait(0.3)
	c.locomotion.pose_pitch = 0.0
	c.locomotion.head_pitch = 0.0
	if g == 3:
		_reveal_knolle()
		_label(c, "✓", Color(0.6, 1.0, 0.5))
	else:
		_label(c, "✗", Color(1.0, 0.55, 0.45))


func _carry(c: Creature, g: int) -> void:
	var stone: Node3D = props.stone
	await _move(c, STONE_POS + Vector3(-0.6, 0, 0), 0.8)
	c.locomotion.pose_pitch = -0.3
	await wait(0.4)
	if g == 0:
		for k in 3:
			c.locomotion.pose_height = -0.06
			await wait(0.25)
			c.locomotion.pose_height = 0.0
			await wait(0.25)
		c.locomotion.pose_pitch = 0.0
		_label(c, "✗", Color(1.0, 0.55, 0.45))
		return
	c.locomotion.pose_pitch = 0.0
	c.held_item = stone
	var frac: float = [0.0, 0.3, 0.75, 1.0][g]
	var dest := STONE_POS.lerp(TARGET_POS, frac)
	await _move(c, dest + Vector3(-0.3, 0, 0), 0.8 + 1.4 * frac)
	c.drop_item()
	if g == 3:
		var ring: MeshInstance3D = props.target
		ring.material_override.albedo_color = Color(0.5, 1.0, 0.4)
		_label(c, "✓", Color(0.6, 1.0, 0.5))
	else:
		_label(c, "✗", Color(1.0, 0.55, 0.45))


func _call(c: Creature, g: int) -> void:
	await _turn(c, 0.0, 0.3)
	c.locomotion.head_pitch = 0.45
	c.locomotion.pose_pitch = 0.15
	var radius: float = [1.4, 3.4, 6.4, 9.5][g]
	var head := c.global_transform * (c.plan.head_center + Vector3(0.0, c.plan.body_center_y, 0.0))
	for k in 3:
		BehaviorEffects.ring(_props_root, head, radius, Color(1.0, 1.0, 0.8, 0.8), 1.0)
		if g > 0 and k == 0:
			Sound.play("call", head, c)
		await wait(0.5)
	var reached := 0
	for i in POSTS_X.size():
		var post: Node3D = props.posts[i]
		if absf(float(POSTS_X[i]) - c.position.x) <= radius:
			reached += 1
			var tw := post.create_tween()
			for s in [0.25, -0.25, 0.15, 0.0]:
				tw.tween_property(post, "rotation:z", s, 0.15)
			var bell: MeshInstance3D = post.get_child(0)
			bell.material_override.emission_energy_multiplier = 2.0
	c.locomotion.head_pitch = 0.0
	c.locomotion.pose_pitch = 0.0
	await wait(0.6)
	_label(c, "✓" if reached == 3 else ("✗" if reached == 0 else "%d/3" % reached),
			Color(0.6, 1.0, 0.5) if reached == 3 else Color(1.0, 0.8, 0.5))


func _scare(c: Creature, g: int) -> void:
	await _move(c, Vector3(0.4, 0, 0), 0.9)
	var raider: Node3D = props.raider
	c.locomotion.pose_height = 0.08
	c.locomotion.pose_scale = 1.15
	c.locomotion.head_pitch = -0.2
	await wait(0.8)
	match g:
		3:
			raider.rotation.y = PI * 0.5
			var tw := raider.create_tween()
			tw.tween_property(raider, "position", RAIDER_POS + Vector3(7, 0, 0), 1.0)
			_label(c, "✓", Color(0.6, 1.0, 0.5))
		2:
			raider.create_tween().tween_property(raider, "position", RAIDER_POS + Vector3(1.0, 0, 0), 0.6)
			_label(c, "½", Color(1.0, 0.8, 0.5))
		1:
			var tw2 := raider.create_tween()
			for s in [0.15, -0.15, 0.0]:
				tw2.tween_property(raider, "rotation:z", s, 0.2)
			_label(c, "✗", Color(1.0, 0.55, 0.45))
		_:
			c.locomotion.pose_scale = 1.0
			c.locomotion.pose_pitch = -0.2
			await _move(c, Vector3(-1.4, 0, 0), 0.8)
			_label(c, "✗", Color(1.0, 0.55, 0.45))
	await wait(0.8)
	c.locomotion.pose_height = 0.0
	c.locomotion.pose_scale = 1.0
	c.locomotion.head_pitch = 0.0
	c.locomotion.pose_pitch = 0.0


# --- Hilfen ------------------------------------------------------------------------

## Wartet (folgt Engine.time_scale – „Überspringen“ beschleunigt alles).
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


## Kreatur in `duration` Sekunden geradlinig an einen Punkt bewegen (Beine laufen mit).
## each: optional Callable(t) pro Frame (Effekte, Höhe).
func _move(c: Creature, to: Vector3, duration: float, each: Callable = Callable()) -> void:
	c.scripted = true
	var from := c.position
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var speed := flat.length() / maxf(duration, 0.05)
	var t := 0.0
	while t < duration:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var k := clampf(t / duration, 0.0, 1.0)
		var p := from.lerp(to, k)
		c.position = Vector3(p.x, c.position.y, p.z)  # Höhe setzt bei Bedarf `each`
		if flat.length() > 0.02:
			c.velocity = flat.normalized() * speed
			var target_yaw := atan2(-flat.x, -flat.z)
			c.rotation.y = lerp_angle(c.rotation.y, target_yaw, 0.2)
		if each.is_valid():
			each.call(t)
	c.velocity = Vector3.ZERO
	c.position = Vector3(to.x, c.position.y, to.z)


## Auf der Stelle drehen (Blickrichtung relativ zu +X).
func _turn(c: Creature, yaw_offset: float, duration: float) -> void:
	var target := atan2(-1.0, 0.0) + yaw_offset
	var from := c.rotation.y
	var t := 0.0
	while t < duration:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		c.rotation.y = lerp_angle(from, target, clampf(t / duration, 0.0, 1.0))


func _tween_value(st: Dictionary, key: String, from: float, to: float, duration: float, apply: Callable) -> void:
	var t := 0.0
	while t < duration:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		st[key] = lerpf(from, to, clampf(t / duration, 0.0, 1.0))
		apply.call()


var _fx_timer := 0.0


func _ripple(c: Creature, t: float, every: float) -> void:
	if t - _fx_timer >= every or t < _fx_timer:
		_fx_timer = t
		BehaviorEffects.ring(_props_root, c.global_position + Vector3(0, 0.07, 0) - Vector3(0, c.position.y, 0), 0.8, Color(0.8, 0.9, 1.0, 0.6), 1.0)


func _puff(c: Creature, t: float) -> void:
	if t - _fx_timer >= 0.25 or t < _fx_timer:
		_fx_timer = t
		var nose := c.global_transform * (c.plan.head_center + Vector3(0.0, c.plan.body_center_y - c.plan.head_radius, -c.plan.head_radius))
		BehaviorEffects.scent_puff(_props_root, nose)


## Großes Zeichen über einer Kreatur (✓ ✗ ?), verblasst.
func _label(c: Creature, text: String, color: Color) -> void:
	_label_at(to_local(c.global_position) + Vector3(0, c.plan.body_center_y + c.plan.half_height + 0.9, 0), text, color)


func _label_at(local: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.004
	l.font_size = 48
	l.outline_size = 12
	l.modulate = color
	l.no_depth_test = true
	l.position = local
	_props_root.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", local.y + 0.4, 1.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.6).set_delay(0.8)
	tw.tween_callback(l.queue_free)


func _mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


func _mesh_node(lp: LowPoly, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit(VegetationMeshes.material())
	n.add_child(mi)
	_props_root.add_child(n)
	return n


func _sphere(radius: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	var m := _mat(color, emission)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = emission
	mi.material_override = m
	return mi


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	return mi


func _torus(radius: float, color: Color, thickness: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - thickness
	tm.outer_radius = radius + thickness
	tm.rings = 24
	tm.ring_segments = 6
	mi.mesh = tm
	mi.material_override = _mat(color, 0.4)
	return mi
