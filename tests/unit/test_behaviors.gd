extends GutTest
## Sichtbares Verhalten in der Waldwelt (manuell getaktet, ohne Echtzeit).

const DT := 1.0 / 30.0
var world: Node3D


func before_all() -> void:
	get_tree().root.set_meta("forest_no_save", true)
	world = (load("res://scenes/world/forest.tscn") as PackedScene).instantiate()
	add_child(world)
	for i in 120:
		await get_tree().physics_frame
		if world.brains[0].mover.ready():
			break
	world.set_physics_process(false)
	for c in world.creatures:
		c.set_physics_process(false)


func after_all() -> void:
	Engine.time_scale = 1.0
	world.queue_free()


func _index_by_ability(id: String, best: bool) -> int:
	var pick := -1
	for i in world.creatures.size():
		var v: float = world.creatures[i].abilities.value(id)
		if pick < 0 or (v > world.creatures[pick].abilities.value(id)) == best:
			pick = i
	return pick


## Erzwingt ein Verhalten und taktet bis zum Ende. Liefert {outcome, dy, start, end, behavior}.
func _run(i: int, id: String, max_seconds := 120.0) -> Dictionary:
	var c: Creature = world.creatures[i]
	var brain: BehaviorBrain = world.brains[i]
	var start := c.global_position
	assert_true(brain.force(id))
	var b := brain.current
	var max_y := start.y
	var t := 0.0
	while brain.current == b and t < max_seconds:
		brain.update(DT)
		c._physics_process(DT)
		max_y = maxf(max_y, c.global_position.y)
		t += DT
	return {"outcome": b.outcome, "dy": max_y - start.y, "start": start, "end": c.global_position, "time": t}


func test_every_creature_has_abilities_and_brain() -> void:
	assert_eq(world.brains.size(), world.creatures.size())
	for c in world.creatures:
		assert_not_null(c.abilities)


func test_good_climber_reaches_rock_top_poor_one_slides_back() -> void:
	var good := _run(_index_by_ability("climb", true), "climb_rock")
	var poor := _run(_index_by_ability("climb", false), "climb_rock")
	assert_eq(good.outcome, "success")
	assert_gt(good.dy, 0.8)
	assert_eq(poor.outcome, "fail")
	assert_lt(poor.dy, good.dy)


func test_tree_climbing() -> void:
	var good := _run(_index_by_ability("climb", true), "climb_tree")
	var poor := _run(_index_by_ability("climb", false), "climb_tree")
	assert_eq(good.outcome, "success")
	assert_gt(good.dy, 2.5, "erreicht die Früchte")
	assert_eq(poor.outcome, "fail")
	assert_lt(poor.dy, good.dy)
	assert_false(world.creatures[_index_by_ability("climb", true)].scripted, "nach dem Klettern wieder normal")


func test_swimming_crosses_or_turns_back() -> void:
	var l: ForestLayout = world.terrain.layout
	var side := func(p: Vector3) -> float:
		var info := l.stream_info(p.x, p.z)
		var c2: Vector2 = info.closest
		var i := 0
		# Vorzeichen: auf welcher Seite des nächsten Bachsegments
		var best := INF
		for k in l.stream_points.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), l.stream_points[k], l.stream_points[k + 1])
			if q.distance_to(c2) < best:
				best = q.distance_to(c2)
				i = k
		var seg := l.stream_points[i + 1] - l.stream_points[i]
		return signf(seg.cross(Vector2(p.x, p.z) - l.stream_points[i]))
	var good := _run(_index_by_ability("swim", true), "swim")
	assert_eq(good.outcome, "success")
	assert_ne(side.call(good.start), side.call(good.end), "auf dem anderen Ufer angekommen")
	# schwacher Schwimmer, der nicht waten kann
	var poor_i := -1
	for i in world.creatures.size():
		var c: Creature = world.creatures[i]
		if c.plan.leg_reach() < 0.9 and (poor_i < 0 or c.abilities.value("swim") < world.creatures[poor_i].abilities.value("swim")):
			poor_i = i
	var poor := _run(poor_i, "swim")
	assert_eq(poor.outcome, "fail")


func test_dig_and_call_outcomes_follow_ability() -> void:
	# auf weichen Boden (Lichtung) stellen – auf Fels kann niemand graben
	var digger: Creature = world.creatures[_index_by_ability("dig", true)]
	var l: ForestLayout = world.terrain.layout
	digger.global_position = Vector3(l.clearing_pos.x, l.height_at(l.clearing_pos.x, l.clearing_pos.y), l.clearing_pos.y)
	assert_eq(_run(_index_by_ability("dig", true), "dig").outcome, "success")
	assert_eq(_run(_index_by_ability("dig", false), "dig").outcome, "fail")
	assert_eq(_run(_index_by_ability("noise", false), "call").outcome, "fail")


func test_carrying_moves_a_stone() -> void:
	var items := get_tree().get_nodes_in_group("carry_item")
	assert_gt(items.size(), 0)
	var before := {}
	for it in items:
		before[it] = it.global_position
	var r := _run(_index_by_ability("carry", true), "carry")
	var moved := 0
	for it in items:
		if it.global_position.distance_to(before[it]) > 0.5:
			moved += 1
	if r.outcome == "success":
		assert_gt(moved, 0, "ein Stein wurde versetzt")
	else:
		assert_eq(r.outcome, "fail")


func test_autonomous_behavior_variety_and_night_rest() -> void:
	world.day_night.hour = 11.0
	world.day_night.time_scale = 0.0
	for s in int(120.0 / DT):
		for i in world.creatures.size():
			world.brains[i].update(DT)
			world.creatures[i]._physics_process(DT)
	var ids := {}
	for b in world.brains:
		for h in b.history:
			ids[h.id] = true
	gut.p("Verhalten am Tag: %s" % [ids.keys()])
	assert_gte(ids.size(), 5)
	# Nacht: Tiere mit schlechter Nachtsicht ruhen häufiger
	world.day_night.hour = 23.5
	world.day_night.apply_lighting()
	for b in world.brains:
		b.history.clear()
	for s in int(150.0 / DT):
		for i in world.creatures.size():
			world.brains[i].update(DT)
			world.creatures[i]._physics_process(DT)
	var rest_poor := 0.0
	var rest_good := 0.0
	var n_poor := 0
	var n_good := 0
	for i in world.creatures.size():
		var nv: float = world.creatures[i].abilities.value("night_vision")
		var rests := 0
		for h in world.brains[i].history:
			if h.id == "rest":
				rests += 1
		var share := float(rests) / maxf(1.0, world.brains[i].history.size())
		if nv < 0.4:
			rest_poor += share
			n_poor += 1
		elif nv > 0.6:
			rest_good += share
			n_good += 1
	gut.p("Anteil Ruhen nachts: schlechte Nachtsicht %.2f, gute %.2f" % [rest_poor / maxf(1, n_poor), rest_good / maxf(1, n_good)])
	assert_gt(rest_poor / maxf(1, n_poor), rest_good / maxf(1, n_good))
