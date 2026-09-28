extends GutTest
## Laufsimulation ohne Physik: flacher bzw. schräger Boden über ground_query.

const DT := 1.0 / 60.0


func _loco_for(species_id: String, tax: Taxonomy, ground: Callable) -> CreatureLocomotion:
	var g := IndividualFactory.new(tax).create_individual(species_id, 0, "female", "adult").genome
	var plan := BodyPlan.from_genome(g)
	var rig := CreatureRig.new(plan)
	var sk := rig.create_skeleton()
	add_child_autofree(sk)
	var loco := CreatureLocomotion.new(plan, rig, sk, ground)
	loco.reset(Transform3D.IDENTITY)
	return loco


func _walk(loco: CreatureLocomotion, seconds: float, speed: float, check: Callable) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var vel := Vector3(0, 0, -speed)
	for n in int(seconds / DT):
		xf.origin += vel * DT
		xf.origin.y = loco.ground_query.call(xf.origin)
		var before := loco.feet.duplicate()
		var was_swinging := loco.swinging.duplicate()
		loco.update(DT, xf, vel)
		check.call(loco, xf, before, was_swinging)
	return xf


func _all_species() -> Array:
	var out := []
	var loader := TaxonomyLoader.new()
	var gallery := loader.load_file("res://data/taxonomies/bodyplan_gallery.json", TestData.schema())
	for tax in [TestData.demo(), gallery]:
		for sp in tax.species():
			out.append([tax, sp.id])
	return out


func test_planted_feet_do_not_slide() -> void:
	var flat := func(_p): return 0.0
	for entry in _all_species():
		var loco := _loco_for(entry[1], entry[0], flat)
		var slides := [0]
		_walk(loco, 3.0, loco.plan.move_speed, func(l, _xf, before, was_swinging):
			for leg in l.plan.leg_count:
				if was_swinging[leg] == 0 and l.swinging[leg] == 0 and l.feet[leg].distance_to(before[leg]) > 0.0001:
					slides[0] += 1)
		assert_eq(slides[0], 0, "Standfüße rutschen: " + entry[1])


func test_feet_stay_within_reach_while_walking() -> void:
	var flat := func(_p): return 0.0
	for entry in _all_species():
		var loco := _loco_for(entry[1], entry[0], flat)
		if loco.plan.leg_count == 0:
			continue
		var worst := [0.0]
		_walk(loco, 4.0, loco.plan.move_speed, func(l, xf, _b, _s):
			var body: Transform3D = l.body_transform()
			for leg in l.plan.leg_count:
				var hip: Vector3 = xf * (body * l.rig.local_rest[l.rig.upper[leg]])
				worst[0] = maxf(worst[0], hip.distance_to(l.feet[leg]) / l.plan.leg_reach()))
		assert_lt(worst[0], 1.25, "Bein überdehnt (%s): %.2f × Reichweite" % [entry[1], worst[0]])


func test_walking_gaits_keep_feet_on_ground() -> void:
	var flat := func(_p): return 0.0
	for entry in _all_species():
		var loco := _loco_for(entry[1], entry[0], flat)
		if loco.plan.leg_count < 4 or loco.plan.gait == "hop":
			continue
		var min_planted := [99]
		_walk(loco, 3.0, loco.plan.move_speed, func(l, _xf, _b, _s):
			var planted := 0
			for leg in l.plan.leg_count:
				if l.swinging[leg] == 0:
					planted += 1
			min_planted[0] = mini(min_planted[0], planted))
		assert_gte(min_planted[0], 2, "zu wenige Standbeine: " + entry[1])


func test_standing_still_stops_stepping() -> void:
	var loco := _loco_for("cornula_silvestris", TestData.demo(), func(_p): return 0.0)
	_walk(loco, 2.0, 0.0, func(_l, _x, _b, _s): pass)
	var before := loco.feet.duplicate()
	_walk(loco, 1.0, 0.0, func(_l, _x, _b, _s): pass)
	for leg in loco.plan.leg_count:
		assert_almost_eq(loco.feet[leg].distance_to(before[leg]), 0.0, 0.0001)


func test_slope_tilts_body_and_places_feet_on_ground() -> void:
	# Boden steigt nach vorne (-Z) an: y = -0.3 * z
	var slope := func(p: Vector3): return -0.3 * p.z
	var loco := _loco_for("saltator_agilis", TestData.demo(), slope)
	var xf := _walk(loco, 3.0, loco.plan.move_speed * 0.7, func(_l, _x, _b, _s): pass)
	for leg in loco.plan.leg_count:
		if loco.swinging[leg] == 0:
			assert_almost_eq(loco.feet[leg].y, -0.3 * loco.feet[leg].z, 0.02, "Fuß auf dem Hang")
	var pitch := loco.body_transform().basis.get_euler().x
	assert_gt(pitch, 0.05, "Nase zeigt bergauf")
	assert_gt(xf.origin.y, 0.1)


func test_creature_node_builds_and_walks() -> void:
	var c := Creature.new()
	add_child_autofree(c)
	var ind := IndividualFactory.new(TestData.demo()).create_individual("tessella_maculata", 2)
	c.setup_individual(ind, "Test")
	assert_not_null(c.mesh_instance.mesh)
	assert_eq(c.mesh_instance.get_node(c.mesh_instance.skeleton), c.skeleton)
	c.desired_velocity = Vector3(1, 0, 0)
	for n in 120:
		c._physics_process(DT)
	assert_gt(c.global_position.x, 0.3, "bewegt sich")
	assert_almost_eq(wrapf(c.rotation.y + PI * 0.5, -PI, PI), 0.0, 0.2, "dreht sich in Laufrichtung (+X)")
	c.set_lod(CreatureLOD.FROZEN)
	assert_eq(c.mesh_instance.mesh, c._meshes[1])
	c.set_lod(CreatureLOD.HIDDEN)
	assert_false(c.visible)


func test_lod_levels_with_hysteresis() -> void:
	assert_eq(CreatureLOD.level_for(5.0, CreatureLOD.FULL), CreatureLOD.FULL)
	assert_eq(CreatureLOD.level_for(20.0, CreatureLOD.FULL), CreatureLOD.REDUCED)
	assert_eq(CreatureLOD.level_for(50.0, CreatureLOD.FULL), CreatureLOD.FROZEN)
	assert_eq(CreatureLOD.level_for(100.0, CreatureLOD.FULL), CreatureLOD.HIDDEN)
	# knapp unter der Grenze bleibt die gröbere Stufe (Hysterese)
	assert_eq(CreatureLOD.level_for(13.5, CreatureLOD.REDUCED), CreatureLOD.REDUCED)
	assert_eq(CreatureLOD.level_for(12.0, CreatureLOD.REDUCED), CreatureLOD.FULL)
