class_name VegetationScatter
extends RefCounted
## Verteilt Vegetation reproduzierbar nach den Regeln in forest.json.
##
## Regel-Felder (pro Eintrag in "vegetation"):
##   plant         Name der Pflanze (VegetationMeshes.PLANTS)
##   density       Pflanzen pro Quadratmeter in den erlaubten Zonen
##   zones         erlaubte Zonen (ForestLayout.ZONES)
##   min_spacing   Mindestabstand zu Pflanzen derselben Regel (0 = egal)
##   scale         [min, max] gleichmäßige Skalierung
##   clear_radius  Abstand zu Felsen, Fruchtbäumen und Wasser, der frei bleibt
## Ergebnis: pro Pflanze ein Array von Transform3D in Weltkoordinaten.


static func scatter(layout: ForestLayout) -> Dictionary:
	var out := {}
	for i in layout.vegetation.size():
		var rule: Dictionary = layout.vegetation[i]
		var plant := str(rule.get("plant", ""))
		if not out.has(plant):
			out[plant] = []
		out[plant].append_array(_scatter_rule(layout, rule, i))
	return out


static func _scatter_rule(layout: ForestLayout, rule: Dictionary, rule_index: int) -> Array:
	var rng := RngUtil.make_rng(["vegetation", layout.seed_value, rule_index, rule.get("plant", "")])
	var zones: Array = rule.get("zones", ["forest"])
	var spacing := float(rule.get("min_spacing", 0.0))
	var clear := float(rule.get("clear_radius", 0.5))
	var scale_range: Array = rule.get("scale", [1.0, 1.0])
	var area := layout.size.x * layout.size.y
	var candidates := int(area * float(rule.get("density", 0.01)))
	var half := layout.half_size() - Vector2(0.5, 0.5)
	var grid := {}  # Rasterzellen für Mindestabstand
	var cell := maxf(spacing, 0.001)
	var out: Array = []
	for n in candidates:
		var p := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		var yaw := rng.randf_range(0.0, TAU)
		var s := rng.randf_range(float(scale_range[0]), float(scale_range[1]))
		if not zones.has(layout.zone_at(p.x, p.y)):
			continue
		if not _is_clear(layout, p, clear):
			continue
		if spacing > 0.0:
			var key := Vector2i(floori(p.x / cell), floori(p.y / cell))
			if _too_close(grid, key, p, spacing):
				continue
			if not grid.has(key):
				grid[key] = []
			grid[key].append(p)
		var y := layout.height_at(p.x, p.y)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
		out.append(Transform3D(basis, Vector3(p.x, y, p.y)))
	return out


static func _is_clear(layout: ForestLayout, p: Vector2, clear: float) -> bool:
	for r in layout.rocks:
		if p.distance_to(r.pos) < r.size + clear:
			return false
	for t in layout.fruit_trees:
		if p.distance_to(t.pos) < 1.0 + clear:
			return false
	if layout.stream_points.size() >= 2:
		var d: float = layout.stream_info(p.x, p.y).distance
		if d < layout.stream_width * 0.5 + minf(clear, 0.3):
			return false
	return true


static func _too_close(grid: Dictionary, key: Vector2i, p: Vector2, spacing: float) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for q in grid.get(key + Vector2i(dx, dy), []):
				if p.distance_to(q) < spacing:
					return true
	return false
