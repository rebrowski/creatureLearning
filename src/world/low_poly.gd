class_name LowPoly
extends RefCounted
## Baukasten für flach schattierte Low-Poly-Meshes mit Vertexfarben
## (Vegetation, Felsen, Fruchtbäume). Dreiecke werden nicht indiziert, damit
## generate_normals() harte Kanten ergibt.

var st := SurfaceTool.new()
var rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	rng.seed = seed_value
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func commit(material: Material = null) -> ArrayMesh:
	st.generate_normals()
	var mesh := st.commit()
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh


func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for p in [a, b, c]:
		st.set_color(color)
		st.add_vertex(p)


func cylinder(base: Vector3, r_bottom: float, r_top: float, height: float, sides: int, color: Color) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var b0 := base + Vector3(cos(a0), 0, sin(a0)) * r_bottom
		var b1 := base + Vector3(cos(a1), 0, sin(a1)) * r_bottom
		var t0 := base + Vector3(cos(a0) * r_top, height, sin(a0) * r_top)
		var t1 := base + Vector3(cos(a1) * r_top, height, sin(a1) * r_top)
		tri(b0, t0, b1, color)
		tri(b1, t0, t1, color)


func cone(base: Vector3, radius: float, height: float, sides: int, color: Color) -> void:
	var tip := base + Vector3(0, height, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := base + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := base + Vector3(cos(a1), 0, sin(a1)) * radius
		var shade := color.darkened(0.1 * (i % 2))
		tri(p0, tip, p1, shade)
		tri(p1, base, p0, color.darkened(0.3))


## Grobe, leicht verbeulte Kugel.
func blob(center: Vector3, radii: Vector3, rings: int, sectors: int, color: Color, jitter: float) -> void:
	var pts := []
	for i in rings + 1:
		var row := []
		var theta := PI * i / rings
		for j in sectors:
			var phi := TAU * j / sectors
			var n := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			var k := 1.0 + (rng.randf() - 0.5) * jitter * (0.0 if i == 0 or i == rings else 1.0)
			row.append(center + n * radii * k)
		pts.append(row)
	for i in rings:
		for j in sectors:
			var j1 := (j + 1) % sectors
			var shade := color.darkened(rng.randf() * 0.12)
			tri(pts[i][j], pts[i][j1], pts[i + 1][j], shade)
			tri(pts[i][j1], pts[i + 1][j1], pts[i + 1][j], shade)


## Gebogenes Blatt/Halm aus zwei Segmenten.
func blade(base: Vector3, dir: Vector3, width: float, height: float, bend: float, color: Color) -> void:
	var side := dir.cross(Vector3.UP).normalized() * width
	var mid := base + Vector3.UP * height * 0.55 + dir * bend * height * 0.35
	var tip := base + Vector3.UP * height + dir * bend * height
	tri(base - side, mid - side * 0.6, base + side, color.darkened(0.2))
	tri(base + side, mid - side * 0.6, mid + side * 0.6, color.darkened(0.1))
	tri(mid - side * 0.6, tip, mid + side * 0.6, color)
