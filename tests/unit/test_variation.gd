extends GutTest
## Polymorphismus, Individuen-Streuung, Platzhalter-Varianz, Trennschärfe.

var tax: Taxonomy
var factory: IndividualFactory


func before_all() -> void:
	tax = TestData.demo()
	factory = IndividualFactory.new(tax)


func test_morph_frequency_and_effect() -> void:
	var plain := 0
	var n := 500
	for i in n:
		var ind := factory.create_individual("tessella_maculata", i, "", "adult")
		if ind.morphs.get("tessella_maculata", "") == "ungefleckt":
			plain += 1
			assert_eq(ind.genome.option("pattern_type"), "none")
		else:
			assert_eq(ind.genome.option("pattern_type"), "spots")
	assert_almost_eq(float(plain) / n, 0.2, 0.06, "≈20 % ungefleckt")
	var again := IndividualFactory.new(TestData.demo()).create_individual("tessella_maculata", 7, "", "adult")
	assert_eq(again.morphs, factory.create_individual("tessella_maculata", 7, "", "adult").morphs, "reproduzierbar")


func test_morph_validation() -> void:
	var d := TestData.minimal_dict()
	var sp: Dictionary = d.taxa[0].children[0].children[0].children[0].children[0]
	sp["morphs"] = [{"p": 0.7, "set": {"hue": 0.1}}, {"p": 0.5, "colour": 1}]
	var loader := TaxonomyLoader.new()
	assert_null(loader.from_dict(d, TestData.schema()))
	assert_eq(loader.errors.size(), 2, str(loader.errors))


func test_wildcard_variance_makes_lookalike_species_close() -> void:
	var d_look := GenomeDistance.distance(factory.mean_genome("stelzus_fluvialis"), factory.mean_genome("stelzus_nocturnus"))
	var d_normal := GenomeDistance.distance(factory.mean_genome("tessella_maculata"), factory.mean_genome("tessella_umbra"))
	assert_lt(d_look, 0.03, "Platzhalter-Varianz 0.01 → Arten fast gleich")
	assert_lt(d_look, d_normal * 0.5)


func test_individual_variance_override() -> void:
	var spread := func(species: String) -> float:
		var mean := factory.mean_genome(species)
		var total := 0.0
		for i in 40:
			total += GenomeDistance.distance(mean, factory.create_individual(species, i, "female", "adult").genome)
		return total / 40.0
	assert_gt(spread.call("stelzus_nocturnus"), spread.call("tessella_umbra") * 1.2, "Stelzus streut stärker (individual_variance)")


func test_design_goal_lookalikes_not_separable_by_one_feature() -> void:
	var best := SpeciesDiagnostics.best_single_gene(factory, "stelzus_fluvialis", "stelzus_nocturnus", 200)
	gut.p("Bach- vs. Nacht-Stelzer: bestes Einzelmerkmal %s %.0f %%" % [best.gene, best.accuracy * 100])
	assert_lt(best.accuracy, 0.8)


func test_design_goal_mimic_recognizable_only_by_movement() -> void:
	var r := SpeciesDiagnostics.separability(factory, "mimula_fallax", "stelzus_fluvialis", 200)
	var best_static := 0.0
	var best_movement := 0.0
	for x in r:
		if x.group == "movement":
			best_movement = maxf(best_movement, x.accuracy)
		else:
			best_static = maxf(best_static, x.accuracy)
	gut.p("Nachahmer: Aussehen max %.0f %%, Bewegung max %.0f %%" % [best_static * 100, best_movement * 100])
	assert_lt(best_static, 0.95, "am Aussehen nicht sicher erkennbar")
	assert_gt(best_movement, 0.9, "an der Bewegung erkennbar")


func test_ordinary_species_stay_distinct() -> void:
	assert_gt(SpeciesDiagnostics.best_single_gene(factory, "tessella_maculata", "tessella_umbra", 150).accuracy, 0.95)


func test_separability_of_species_with_itself_is_chance() -> void:
	var tax2 := TestData.demo()
	var f2 := IndividualFactory.new(tax2)
	# gleiche Art, aber unterschiedliche Stichproben: Nummern 0..n bzw. über create_group verschoben
	var best := SpeciesDiagnostics.best_single_gene(f2, "cornula_silvestris", "cornula_silvestris", 100)
	assert_lt(best.accuracy, 0.56)


func test_roundtrip_keeps_new_fields() -> void:
	var loader := TaxonomyLoader.new()
	var again := loader.from_dict(JsonLoader.parse(JSON.stringify(tax.to_dict())).data, TestData.schema())
	assert_not_null(again, str(loader.errors))
	var f2 := IndividualFactory.new(again)
	for sp in ["tessella_maculata", "stelzus_nocturnus", "cornula_saxatilis"]:
		for i in 5:
			assert_true(factory.create_individual(sp, i).genome.is_equal_approx_to(f2.create_individual(sp, i).genome), sp)
