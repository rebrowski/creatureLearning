extends GutTest
## Erzeugung von Mittel-Genomen und Individuen: Determinismus, Fixierung,
## Regler, Dimorphismus, Konvergenz.

var tax: Taxonomy


func before_each() -> void:
	tax = TestData.demo()


func test_same_seed_same_creature() -> void:
	var a := IndividualFactory.new(tax).create_individual("tessella_umbra", 3)
	var b := IndividualFactory.new(TestData.demo()).create_individual("tessella_umbra", 3)
	assert_eq(a.genome.to_dict(), b.genome.to_dict())
	assert_eq(a.sex, b.sex)
	assert_eq(a.age, b.age)


func test_different_index_or_seed_differs() -> void:
	var f := IndividualFactory.new(tax)
	var a := f.create_individual("tessella_umbra", 1, "female", "adult")
	var b := f.create_individual("tessella_umbra", 2, "female", "adult")
	assert_gt(GenomeDistance.distance(a.genome, b.genome), 0.0)
	tax.base_seed += 1
	var c := IndividualFactory.new(tax).create_individual("tessella_umbra", 1, "female", "adult")
	assert_gt(GenomeDistance.distance(a.genome, c.genome), 0.0)


func test_set_values_are_applied() -> void:
	var f := IndividualFactory.new(tax)
	var m := f.mean_genome("stelzus_fluvialis")
	assert_eq(m.i("leg_count"), 6)
	assert_eq(m.i("segment_count"), 3)
	assert_eq(m.option("gait"), "scuttle")
	assert_eq(m.option("body_shape"), "round")
	assert_almost_eq(m.f("leg_length"), 1.2, 0.3)
	assert_eq(f.mean_genome("tessella_maculata").i("leg_count"), 8)


func test_locked_genes_constant_within_family() -> void:
	var f := IndividualFactory.new(tax)
	for family in tax.taxa_of_rank(Ranks.FAMILY):
		var ref: Genome = null
		for sp in tax.species(family.id):
			for n in 5:
				var g := f.create_individual(sp.id, n, "", "adult").genome
				if ref == null:
					ref = g
				for gene_id in ["segment_count", "leg_count", "body_shape", "gait"]:
					assert_eq(g.get_value(gene_id), ref.get_value(gene_id), "%s in %s" % [gene_id, family.id])


func test_locked_genes_constant_in_generated_taxonomy() -> void:
	var gen := TestData.generated(99)
	var f := IndividualFactory.new(gen)
	for order in gen.taxa_of_rank(Ranks.ORDER):
		var legs := {}
		for sp in gen.species(order.id):
			legs[f.create_individual(sp.id, 0, "", "adult").genome.i("leg_count")] = true
		assert_eq(legs.size(), 1, "Beinzahl innerhalb Ordnung " + order.id)


func test_species_spread_zero_makes_sibling_species_identical() -> void:
	var gen := TestData.generated(7)
	gen.settings.set_spread(Ranks.SPECIES, 0.0)
	gen.settings.convergence_strength = 0.0
	var f := IndividualFactory.new(gen)
	var checked := 0
	for genus in gen.taxa_of_rank(Ranks.GENUS):
		var sp := gen.species(genus.id)
		for k in range(1, sp.size()):
			assert_true(f.mean_genome(sp[0].id).is_equal_approx_to(f.mean_genome(sp[k].id)), genus.id)
			checked += 1
	assert_gt(checked, 0, "Preset sollte Gattungen mit mehreren Arten erzeugen")


func test_individual_spread_scales_variation() -> void:
	var spread_of := func(value: float) -> float:
		tax.settings.set_spread(Ranks.INDIVIDUAL, value)
		var f := IndividualFactory.new(tax)
		var mean := f.mean_genome("saltator_agilis")
		var total := 0.0
		for n in 30:
			total += GenomeDistance.distance(mean, f.create_individual("saltator_agilis", n, "female", "adult").genome)
		return total / 30.0
	var none: float = spread_of.call(0.0)
	var normal: float = spread_of.call(1.0)
	var wide: float = spread_of.call(3.0)
	assert_almost_eq(none, 0.0, 0.000001)
	assert_gt(normal, none)
	assert_gt(wide, normal * 1.5)


func test_distance_increases_with_taxonomic_distance() -> void:
	var gen := TestData.generated(2026, {"classes": 3})
	var f := IndividualFactory.new(gen)
	var sums := {}
	var counts := {}
	var all := gen.species()
	var samples := {}
	for sp in all:
		samples[sp.id] = []
		for n in 4:
			samples[sp.id].append(f.create_individual(sp.id, n, "female", "adult").genome)
	for i in all.size():
		for j in range(i, all.size()):
			var rank := Ranks.SPECIES if i == j else gen.shared_rank(all[i].id, all[j].id)
			for a in samples[all[i].id].size():
				for b in samples[all[j].id].size():
					if i == j and b <= a:
						continue
					var d := GenomeDistance.distance(samples[all[i].id][a], samples[all[j].id][b])
					sums[rank] = sums.get(rank, 0.0) + d
					counts[rank] = counts.get(rank, 0) + 1
	var means := {}
	for rank in sums:
		means[rank] = sums[rank] / counts[rank]
	gut.p("Mittlere Distanz je gemeinsamem Rang: %s" % [means])
	# gleiche Art < gleiche Gattung < gleiche Familie < ... < andere Klasse
	var order := [Ranks.SPECIES, Ranks.GENUS, Ranks.FAMILY, Ranks.ORDER, Ranks.CLASS, -1]
	var last := -1.0
	for rank in order:
		if means.has(rank):
			assert_gt(means[rank], last, "gemeinsamer Rang: %s" % (Ranks.name_of(rank) if rank >= 0 else "keiner"))
			last = means[rank]


func test_dimorphism_strength_zero_removes_sex_differences() -> void:
	tax.settings.dimorphism_strength = 0.0
	var f := IndividualFactory.new(tax)
	var m := f.create_individual("cornula_silvestris", 4, "male", "adult")
	var w := f.create_individual("cornula_silvestris", 4, "female", "adult")
	assert_eq(m.genome.to_dict(), w.genome.to_dict())


func test_sexual_dimorphism() -> void:
	var f := IndividualFactory.new(tax)
	var m := f.create_individual("cornula_silvestris", 4, "male", "adult").genome
	var w := f.create_individual("cornula_silvestris", 4, "female", "adult").genome
	assert_gt(m.f("horn_length"), w.f("horn_length"))
	assert_gt(m.f("crest_height"), w.f("crest_height"))
	# Weibchen von Talpides cornutus haben kein Horn
	assert_eq(f.create_individual("talpides_cornutus", 1, "female", "adult").genome.i("horn_count"), 0)
	assert_eq(f.create_individual("talpides_cornutus", 1, "male", "adult").genome.i("horn_count"), 1)


func test_age_dimorphism_inherited_from_class() -> void:
	var f := IndividualFactory.new(tax)
	var adult := f.create_individual("saltator_agilis", 2, "female", "adult").genome
	var young := f.create_individual("saltator_agilis", 2, "female", "juvenile").genome
	assert_almost_eq(young.f("body_length"), adult.f("body_length") * 0.55, 0.001)
	assert_gt(young.f("head_size"), adult.f("head_size"))
	# Jungtiere zeigen keinen Geschlechtsunterschied
	var young_m := f.create_individual("cornula_silvestris", 2, "male", "juvenile").genome
	var young_w := f.create_individual("cornula_silvestris", 2, "female", "juvenile").genome
	assert_eq(young_m.to_dict(), young_w.to_dict())


func test_convergence_brings_unrelated_species_closer() -> void:
	var with_conv := IndividualFactory.new(tax)
	var d_with := GenomeDistance.distance(with_conv.mean_genome("mimula_fallax"), with_conv.mean_genome("stelzus_fluvialis"))
	var settings := tax.settings.copy()
	settings.convergence_strength = 0.0
	var without := IndividualFactory.new(tax, settings)
	var d_without := GenomeDistance.distance(without.mean_genome("mimula_fallax"), without.mean_genome("stelzus_fluvialis"))
	gut.p("Mimula fallax <-> Stelzus fluvialis: mit %.3f, ohne %.3f" % [d_with, d_without])
	assert_lt(d_with, d_without * 0.6)
	# Der Nachahmer ähnelt seinem Vorbild stärker als seiner eigenen Schwesterart.
	var d_sister := GenomeDistance.distance(with_conv.mean_genome("mimula_fallax"), with_conv.mean_genome("mimula_vulgaris"))
	assert_lt(d_with, d_sister)


func test_new_gene_does_not_change_existing_values() -> void:
	var before := IndividualFactory.new(tax).create_individual("hydropes_minor", 5).genome.to_dict()
	var data: Dictionary = JsonLoader.read(GenomeSchema.DEFAULT_PATH).data
	# Neues Gen sogar ganz vorne einfügen – die Reihenfolge darf keine Rolle spielen.
	data.genes.push_front({"id": "zz_new", "type": "float", "min": 0, "max": 1, "default": 0.5})
	var extended := GenomeSchema.from_dict(data)
	assert_eq(extended.errors, PackedStringArray())
	var tax2 := TaxonomyLoader.new().load_file(TestData.DEMO_PATH, extended)
	var after := IndividualFactory.new(tax2).create_individual("hydropes_minor", 5).genome.to_dict()
	assert_true(after.has("zz_new"))
	for key in before:
		assert_eq(after[key], before[key], key)


func test_fixed_genes_stop_random_deviation_but_allow_explicit_set() -> void:
	var d := TestData.minimal_dict()
	d.taxa[0]["set"] = {"hue": 0.5, "gait": "hop"}
	d.taxa[0]["fixed"] = ["hue", "gait"]
	var species_dict: Dictionary = d.taxa[0].children[0].children[0].children[0].children[1]
	species_dict["set"] = {"hue": 0.9}
	var loader := TaxonomyLoader.new()
	var t := loader.from_dict(d, TestData.schema())
	assert_not_null(t, str(loader.errors))
	t.settings.set_spread(Ranks.INDIVIDUAL, 5.0)
	var f := IndividualFactory.new(t)
	for n in 10:
		var g := f.create_individual("s1", n, "female", "adult").genome
		assert_almost_eq(g.f("hue"), 0.5, 0.0001, "fixed: kein Zufall bis zum Individuum")
		assert_eq(g.option("gait"), "hop")
	assert_almost_eq(f.mean_genome("s2").f("hue"), 0.9, 0.0001, "explizites set bleibt möglich")
