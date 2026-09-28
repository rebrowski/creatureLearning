class_name ForestNavigation
extends NavigationRegion3D
## Navmesh für Landkreaturen, zur Laufzeit aus dem Gelände gebacken
## (Gelände, Felsen, Baumstämme). Der Bach wird ausgespart – ab M4 können
## Schwimmer eigene Wege gehen.

signal baked

@export var terrain: ForestTerrain
@export var agent_radius := 0.5  # Vielfaches von cell_size (0.25)
@export var agent_max_slope_deg := 38.0
@export var agent_max_climb := 0.5  # Vielfaches von cell_height (0.25)

var is_baked := false
var bake_msec := 0


func bake_from_terrain() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = agent_radius
	nm.agent_height = 1.0
	nm.agent_max_slope = agent_max_slope_deg
	nm.agent_max_climb = agent_max_climb
	nm.cell_size = 0.25
	nm.cell_height = 0.25  # muss zur Navigationskarte passen (Projekteinstellung)
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = terrain.ground_layer
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, source, terrain)
	_add_stream_obstruction(source)
	var start := Time.get_ticks_msec()
	var done := func():
		navigation_mesh = nm
		is_baked = true
		bake_msec = Time.get_ticks_msec() - start
		baked.emit()
	if OS.has_feature("threads"):
		NavigationServer3D.bake_from_source_geometry_data_async(nm, source, done)
	else:
		# Web-Export ohne Threads: synchron backen (~0.1–0.3 s beim Start)
		NavigationServer3D.bake_from_source_geometry_data(nm, source)
		done.call_deferred()


func _add_stream_obstruction(source: NavigationMeshSourceGeometryData3D) -> void:
	var l := terrain.layout
	var pts := l.stream_points
	var half := l.stream_width * 0.5 + 0.3
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x) * half
		# etwas überlappen, damit an Knicken keine Lücken entstehen
		a -= dir * half
		b += dir * half
		var quad := PackedVector3Array([
			Vector3(a.x + side.x, 0, a.y + side.y), Vector3(b.x + side.x, 0, b.y + side.y),
			Vector3(b.x - side.x, 0, b.y - side.y), Vector3(a.x - side.x, 0, a.y - side.y)])
		source.add_projected_obstruction(quad, -10.0, 30.0, true)


func map() -> RID:
	return get_navigation_map()
