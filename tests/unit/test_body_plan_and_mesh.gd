extends GutTest
## BodyPlan, Rig und Mesh-Builder für alle Baupläne der Demo, der Galerie und
## einer generierten Taxonomie.

var genomes: Array[Genome] = []


func before_all() -> void:
	var schema := TestData.schema()
	var taxonomies: Array[Taxonomy] = [TestData.demo(), TestData.generated(5)]
	var loader := TaxonomyLoader.new()
	var gallery := loader.load_file("res://data/taxonomies/bodyplan_gallery.json", schema)
	assert_not_null(gallery, str(loader.errors))
	taxonomies.append(gallery)
	for tax in taxonomies:
		var f := IndividualFactory.new(tax)
		for sp in tax.species():
			genomes.append(f.create_individual(sp.id, 0, "male", "adult").genome)
			genomes.append(f.create_individual(sp.id, 1, "female", "juvenile").genome)


func test_gallery_covers_all_leg_counts() -> void:
	var counts := {}
	for g in genomes:
		counts[g.i("leg_count")] = true
	for n in [0, 2, 4, 6, 8]:
		assert_true(counts.has(n), "Beinzahl %d" % n)


func test_plan_is_consistent() -> void:
	for g in genomes:
		var p := BodyPlan.from_genome(g)
		assert_eq(p.hips.size(), p.leg_count)
		assert_eq(p.foot_homes.size(), p.leg_count)
		assert_eq(p.segment_z.size(), p.segment_count)
		assert_gt(p.body_center_y, 0.0)
		assert_gt(p.move_speed, 0.0)
		for leg in p.leg_count:
			var reach := p.hip_rest(leg).distance_to(p.foot_homes[leg])
			assert_lt(reach, p.leg_reach(), "Fußruhepunkt erreichbar (Bein %d)" % leg)
			assert_gt(reach, p.leg_reach() * 0.5, "Bein nicht zu stark eingeknickt (Bein %d)" % leg)
			# linke Beine links, rechte rechts
			assert_eq(signf(p.foot_homes[leg].x), -1.0 if p.side_of(leg) == 0 else 1.0)


func test_rig_bones() -> void:
	for g in genomes:
		var p := BodyPlan.from_genome(g)
		var rig := CreatureRig.new(p)
		assert_eq(rig.bone_count(), 1 + p.segment_count + 1 + CreatureRig.TAIL_BONES + p.leg_count * 2)
		var sk := rig.create_skeleton()
		assert_eq(sk.get_bone_count(), rig.bone_count())
		assert_almost_eq(sk.get_bone_global_rest(rig.root).origin.y, p.body_center_y, 0.0001)
		sk.free()


func test_mesh_is_valid() -> void:
	for g in genomes:
		var p := BodyPlan.from_genome(g)
		var rig := CreatureRig.new(p)
		var hi := CreatureMeshBuilder.build(p, rig, 0)
		var lo := CreatureMeshBuilder.build(p, rig, 1)
		assert_eq(hi.get_surface_count(), 1)
		var arrays := hi.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert_gt(verts.size(), 100)
		assert_eq(bones.size(), verts.size() * 4, "4 Knochen-Slots pro Vertex")
		assert_eq(indices.size() % 3, 0)
		for b in bones:
			assert_between(b, 0, rig.bone_count() - 1)
		for v in verts:
			assert_false(is_nan(v.x) or is_nan(v.y) or is_nan(v.z), "NaN im Mesh")
		var aabb := hi.get_aabb()
		assert_gt(aabb.size.z, p.body_length * 0.9, "Mesh mindestens so lang wie der Rumpf")
		assert_lt(aabb.size.length(), 12.0, "Mesh nicht absurd groß")
		assert_lt((lo.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), verts.size(), "LOD-Mesh hat weniger Vertices")
