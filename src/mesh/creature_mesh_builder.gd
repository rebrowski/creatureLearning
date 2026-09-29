class_name CreatureMeshBuilder
extends RefCounted
## Baut aus BodyPlan + CreatureRig ein einziges Mesh in Ruhehaltung, dessen
## Vertices fest (Gewicht 1) an je einen Knochen gebunden sind.
##
## Vertex-Daten für den Shader (creature.gdshader):
##   COLOR.rgb  Tönung (bei a = 1) bzw. feste Farbe (bei a = 0, z. B. Augen, Hörner)
##   COLOR.a    1 = Körperfarbe verwenden, 0 = COLOR.rgb direkt
##   UV         Musterkoordinaten (z entlang des Körpers, Bogenlänge ums Segment) in Metern
##   UV2        (z, Höhe relativ zur Segmentmitte normiert auf -1..1); x < -500 = kein Muster

const NO_PATTERN := Vector2(-1000.0, -1000.0)
## UV2-Markierung für Augen (Shader: Leuchten im Dunkeln).
const EYE_MARK := Vector2(-2000.0, 0.0)
const HORN_COLOR := Color(0.93, 0.88, 0.74, 0.0)
const EYE_COLOR := Color(0.05, 0.05, 0.05, 0.0)
const BODY := Color(1, 1, 1, 1)
const LIMB := Color(0.82, 0.82, 0.82, 1)
const CREST := Color(0.62, 0.62, 0.62, 1)

## Auflösung pro Detailstufe: [Ringe, Sektoren, Beinsektoren]
const DETAIL := [[10, 14, 8], [5, 8, 4]]

var plan: BodyPlan
var rig: CreatureRig
var _st: SurfaceTool
var _rings := 10
var _sectors := 14
var _leg_sectors := 8
var _vertex_count := 0


## detail: 0 = hoch, 1 = niedrig (für LOD).
static func build(p_plan: BodyPlan, p_rig: CreatureRig, detail := 0) -> ArrayMesh:
	var b := CreatureMeshBuilder.new()
	b.plan = p_plan
	b.rig = p_rig
	var d: Array = DETAIL[clampi(detail, 0, DETAIL.size() - 1)]
	b._rings = d[0]
	b._sectors = d[1]
	b._leg_sectors = d[2]
	return b._build(detail)


func _build(detail: int) -> ArrayMesh:
	_st = SurfaceTool.new()
	_st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)  # muss vor begin() stehen
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body()
	_head()
	if detail == 0:
		_crest()
	_tail()
	_legs()
	return _st.commit()


# --- Körperteile --------------------------------------------------------------

func _body() -> void:
	var n := plan.segment_count
	for i in n:
		var c: Vector3 = rig.global_rest[rig.segments[i]]
		# mittlere Segmente etwas dicker, Segmente überlappen leicht
		var bulge := 0.85 + 0.15 * sin(PI * (i + 0.5) / n)
		var rz := plan.body_length * 0.5 if n == 1 else plan.segment_half_length * 1.25
		_ellipsoid(c, Vector3(plan.half_width * bulge, plan.half_height * bulge, rz), rig.segments[i], BODY, true)


func _head() -> void:
	var c: Vector3 = rig.global_rest[rig.head]
	var r := plan.head_radius
	_ellipsoid(c, Vector3(r * 0.9, r * 0.9, r), rig.head, BODY, false)
	for s in [-1.0, 1.0]:
		var eye := c + Vector3(s * r * 0.55, r * 0.3, -r * 0.65)
		_ellipsoid(eye, Vector3.ONE * maxf(0.012, r * 0.18), rig.head, EYE_COLOR, false, 5, 6)
	if plan.horn_count > 0 and plan.horn_length > 0.01:
		for k in plan.horn_count:
			var t := 0.5 if plan.horn_count == 1 else float(k) / (plan.horn_count - 1)
			var side := lerpf(-0.6, 0.6, t) if plan.horn_count > 1 else 0.0
			var dir := Vector3(side, 0.9, -0.35).normalized()
			var base := c + dir * r * 0.8
			var tip := base + (dir + Vector3(0, 0.15, -0.35)).normalized() * plan.horn_length
			_tube(base, tip, r * 0.18, 0.004, rig.head, HORN_COLOR, _leg_sectors)
	if plan.antenna_length > 0.02:
		for s in [-1.0, 1.0]:
			var p0 := c + Vector3(s * r * 0.35, r * 0.75, -r * 0.5)
			var p1 := p0 + Vector3(s * 0.15, 0.7, -0.35) * plan.antenna_length * 0.5
			var p2 := p1 + Vector3(s * 0.2, 0.2, -0.8) * plan.antenna_length * 0.5
			_tube(p0, p1, 0.012, 0.009, rig.head, LIMB, 4)
			_tube(p1, p2, 0.009, 0.004, rig.head, LIMB, 4)


func _crest() -> void:
	if plan.crest_height < 0.02:
		return
	var teeth := 5 + plan.segment_count * 2
	var z_front := -plan.body_length * 0.4
	var z_back := plan.body_length * 0.35
	var half_thick := maxf(0.006, plan.half_width * 0.06)
	for k in teeth:
		var z0 := lerpf(z_front, z_back, float(k) / teeth)
		var z1 := lerpf(z_front, z_back, float(k + 1) / teeth)
		var zm := (z0 + z1) * 0.5
		var bone := rig.segment_bone_at(zm)
		var y0 := _body_top(z0) - 0.01
		var y1 := _body_top(z1) - 0.01
		var tip := Vector3(0.0, maxf(y0, y1) + plan.crest_height * (0.8 + 0.2 * sin(PI * float(k) / teeth)), zm - (z1 - z0) * 0.3)
		var a := Vector3(0.0, y0, z0)
		var b := Vector3(0.0, y1, z1)
		for s in [-1.0, 1.0]:
			var off := Vector3(s * half_thick, 0.0, 0.0)
			_triangle(a + off, tip, b + off, Vector3(s, 0.0, 0.0), bone, CREST)


func _body_top(z: float) -> float:
	var u := clampf(z / (plan.body_length * 0.55), -1.0, 1.0)
	return plan.body_center_y + plan.half_height * 0.92 * sqrt(1.0 - u * u)


func _tail() -> void:
	if plan.tail_length < 0.02:
		return
	var r0 := maxf(0.02, plan.half_height * 0.4)
	var bones := rig.tail
	for i in bones.size():
		var a: Vector3 = rig.global_rest[bones[i]]
		var b: Vector3 = rig.global_rest[bones[i + 1]] if i + 1 < bones.size() else a + Vector3(0.0, 0.0, plan.tail_length / bones.size())
		var ra := lerpf(r0, 0.01, float(i) / bones.size())
		var rb := lerpf(r0, 0.01, float(i + 1) / bones.size())
		_tube(a, b, ra, rb, bones[i], BODY, _leg_sectors)
		if i + 1 < bones.size():
			_ellipsoid(b, Vector3.ONE * rb, bones[i + 1], BODY, false, 4, _leg_sectors)


func _legs() -> void:
	for leg in plan.leg_count:
		var hip: Vector3 = rig.global_rest[rig.upper[leg]]
		var knee: Vector3 = rig.global_rest[rig.lower[leg]]
		var foot := knee + Vector3(0.0, -plan.lower_leg, 0.0)
		var r := plan.leg_radius
		_ellipsoid(hip, Vector3.ONE * r * 1.3, rig.upper[leg], LIMB, false, 4, _leg_sectors)
		_tube(hip, knee, r * 1.1, r, rig.upper[leg], LIMB, _leg_sectors)
		_ellipsoid(knee, Vector3.ONE * r * 1.05, rig.lower[leg], LIMB, false, 4, _leg_sectors)
		_tube(knee, foot, r, r * 0.7, rig.lower[leg], LIMB, _leg_sectors)
		_ellipsoid(foot, Vector3(r * 1.2, r * 0.8, r * 1.4), rig.lower[leg], LIMB, false, 4, _leg_sectors)


# --- Primitive ----------------------------------------------------------------

func _vertex(pos: Vector3, normal: Vector3, bone: int, color: Color, uv: Vector2, uv2: Vector2) -> void:
	_st.set_color(color)
	_st.set_normal(normal)
	_st.set_uv(uv)
	_st.set_uv2(uv2)
	_st.set_bones(PackedInt32Array([bone, 0, 0, 0]))
	_st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	_st.add_vertex(pos)
	_vertex_count += 1


## Ellipsoid entlang Z. `patterned`: Musterkoordinaten schreiben.
func _ellipsoid(c: Vector3, radii: Vector3, bone: int, color: Color, patterned: bool, rings := -1, sectors := -1) -> void:
	rings = _rings if rings < 0 else rings
	sectors = _sectors if sectors < 0 else sectors
	var start := _vertex_count
	var arc_r := (radii.x + radii.y) * 0.5
	for i in rings + 1:
		var theta := PI * i / rings
		var st := sin(theta)
		var z := -radii.z * cos(theta)
		for j in sectors + 1:
			var phi := TAU * j / sectors
			var local := Vector3(radii.x * st * cos(phi), radii.y * st * sin(phi), z)
			var n := Vector3(local.x / (radii.x * radii.x), local.y / (radii.y * radii.y), local.z / (radii.z * radii.z)).normalized()
			if n == Vector3.ZERO:
				n = Vector3(0, 0, signf(z))
			var uv := Vector2(c.z + z, phi * arc_r) if patterned else Vector2.ZERO
			var uv2 := Vector2(c.z + z, st * sin(phi)) if patterned else (EYE_MARK if color == EYE_COLOR else NO_PATTERN)
			_vertex(c + local, n, bone, color, uv, uv2)
	var row := sectors + 1
	for i in rings:
		for j in sectors:
			var a := start + i * row + j
			var b := a + row
			# Godot: Vorderseite im Uhrzeigersinn (von außen gesehen)
			_st.add_index(a)
			_st.add_index(b)
			_st.add_index(a + 1)
			_st.add_index(b)
			_st.add_index(b + 1)
			_st.add_index(a + 1)


## Offene, sich verjüngende Röhre von a nach b.
func _tube(a: Vector3, b: Vector3, ra: float, rb: float, bone: int, color: Color, sectors: int) -> void:
	var axis := b - a
	if axis.length_squared() < 0.000001:
		return
	var dir := axis.normalized()
	var x := dir.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = dir.cross(Vector3.RIGHT)
	x = x.normalized()
	var y := dir.cross(x).normalized()
	var start := _vertex_count
	for ring in 2:
		var center := a if ring == 0 else b
		var r := ra if ring == 0 else rb
		for j in sectors + 1:
			var phi := TAU * j / sectors
			var radial := x * cos(phi) + y * sin(phi)
			_vertex(center + radial * r, radial, bone, color, Vector2.ZERO, NO_PATTERN)
	var row := sectors + 1
	for j in sectors:
		var i0 := start + j
		var i1 := start + row + j
		_st.add_index(i0)
		_st.add_index(i1)
		_st.add_index(i0 + 1)
		_st.add_index(i0 + 1)
		_st.add_index(i1)
		_st.add_index(i1 + 1)


func _triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, bone: int, color: Color) -> void:
	var start := _vertex_count
	for p in [a, b, c]:
		_vertex(p, normal, bone, color, Vector2.ZERO, NO_PATTERN)
	# Wicklung so wählen, dass die Vorderseite zur Normalen zeigt
	if (b - a).cross(c - a).dot(normal) >= 0.0:
		_st.add_index(start)
		_st.add_index(start + 2)
		_st.add_index(start + 1)
	else:
		_st.add_index(start)
		_st.add_index(start + 1)
		_st.add_index(start + 2)
