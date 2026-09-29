extends GutTest
## Weltlayout, Vegetationsverteilung und Low-Poly-Meshes.

var layout: ForestLayout


func before_all() -> void:
	layout = ForestLayout.load_file()


func test_layout_loads() -> void:
	assert_true(layout.is_valid(), str(layout.errors))
	assert_eq(layout.size, Vector2(64, 64))
	assert_gt(layout.stream_points.size(), 1)
	assert_gt(layout.rocks.size(), 0)
	assert_gt(layout.fruit_trees.size(), 0)


func test_zones() -> void:
	var p := layout.stream_points[2]
	assert_eq(layout.zone_at(p.x, p.y), "water")
	assert_eq(layout.zone_at(layout.clearing_pos.x, layout.clearing_pos.y), "clearing")
	var r: Dictionary = layout.rocks[0]
	assert_eq(layout.zone_at(r.pos.x, r.pos.y), "rock")
	var t: Dictionary = layout.fruit_trees[0]
	assert_eq(layout.zone_at(t.pos.x, t.pos.y), "tree")
	assert_eq(layout.zone_at(100, 0), "outside")
	# Ufer liegt zwischen Wasser und Wald
	var d := layout.stream_width * 0.5 + layout.stream_bank * 0.5
	assert_eq(layout.zone_at(p.x, p.y + d), "bank")


func test_heights_are_continuous_and_stream_is_lower() -> void:
	var worst := 0.0
	for i in 400:
		var x := -30.0 + (i % 20) * 3.0
		var z := -30.0 + (i / 20) * 3.0
		worst = maxf(worst, absf(layout.height_at(x, z) - layout.height_at(x + 0.25, z)))
	assert_lt(worst, 0.5, "keine Sprünge im Gelände")
	var p := layout.stream_points[2]
	assert_lt(layout.height_at(p.x, p.y), layout.water_level_at(p.x, p.y), "Bachgrund unter Wasser")
	assert_gt(layout.height_at(p.x, p.y + 8.0), layout.water_level_at(p.x, p.y), "Wald über Wasser")


func test_hill_is_raised() -> void:
	var h: Dictionary = layout.hills[0]
	assert_gt(layout.height_at(h.pos.x, h.pos.y), h.height * 0.6)


func test_clearing_is_flattened() -> void:
	var c := layout.clearing_pos
	var spread := 0.0
	for a in 8:
		var q := c + Vector2(cos(a * TAU / 8), sin(a * TAU / 8)) * layout.clearing_radius * 0.4
		spread = maxf(spread, absf(layout.height_at(q.x, q.y) - layout.height_at(c.x, c.y)))
	assert_lt(spread, 0.25)


func test_invalid_layout_reports_errors() -> void:
	var l := ForestLayout.from_dict({"stream": {"points": [[0, 0]]}, "rocks": [{"pos": [1]}],
			"vegetation": [{"plant": "grass", "zones": ["lava"]}]})
	assert_eq(l.errors.size(), 3, str(l.errors))


func test_scatter_is_deterministic_and_respects_zones() -> void:
	var a := VegetationScatter.scatter(layout)
	var b := VegetationScatter.scatter(layout)
	for plant in a:
		assert_eq(a[plant].size(), b[plant].size())
		if not a[plant].is_empty():
			assert_eq(a[plant][0], b[plant][0])
	var rules := {}
	for r in layout.vegetation:
		rules[r.plant] = r
	for plant in a:
		for t: Transform3D in a[plant]:
			var zone := layout.zone_at(t.origin.x, t.origin.z)
			assert_true(rules[plant].zones.has(zone), "%s in Zone %s" % [plant, zone])
			assert_almost_eq(t.origin.y, layout.height_at(t.origin.x, t.origin.z), 0.001)
	assert_gt(a.tree_pine.size(), 10)
	assert_gt(a.grass.size(), 500)


func test_scatter_min_spacing() -> void:
	var trees: Array = VegetationScatter.scatter(layout).tree_pine
	for i in trees.size():
		for j in range(i + 1, trees.size()):
			var d := Vector2(trees[i].origin.x - trees[j].origin.x, trees[i].origin.z - trees[j].origin.z).length()
			assert_gte(d, 3.0 - 0.001)


func test_vegetation_meshes_build() -> void:
	for plant in VegetationMeshes.PLANTS:
		var m := VegetationMeshes.build(plant)
		assert_eq(m.get_surface_count(), 1, plant)
		var verts: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_gt(verts.size(), 8, plant)
		assert_lt(verts.size(), 1500, "Low-Poly bleibt klein: " + plant)
		assert_not_null(m.surface_get_material(0))
