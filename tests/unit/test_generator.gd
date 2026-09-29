extends GutTest
## Zufällige Taxonomien: Reproduzierbarkeit, Struktur, JSON-Roundtrip.

var schema: GenomeSchema
var preset: Dictionary


func before_all() -> void:
	schema = TestData.schema()
	preset = TaxonomyGenerator.load_preset()


func test_preset_loads() -> void:
	assert_false(preset.is_empty())
	assert_eq(preset.get("format"), TaxonomyGenerator.FORMAT)


func test_same_seed_same_taxonomy() -> void:
	var a := TaxonomyGenerator.new().generate(schema, preset, 123)
	var b := TaxonomyGenerator.new().generate(schema, preset, 123)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_different_seed_different_taxonomy() -> void:
	var a := TaxonomyGenerator.new().generate(schema, preset, 123)
	var b := TaxonomyGenerator.new().generate(schema, preset, 124)
	assert_ne(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_structure_respects_preset() -> void:
	for seed_value in [1, 2, 3, 4, 5]:
		var tax := TaxonomyGenerator.new().generate(schema, preset, seed_value)
		assert_eq(tax.roots().size(), int(preset.classes))
		for id in tax.taxa:
			var t: Taxon = tax.taxa[id]
			if t.rank == Ranks.SPECIES:
				assert_eq(t.children.size(), 0)
				continue
			var bounds: Array = preset.children_per_rank[Ranks.name_of(t.rank + 1)]
			assert_between(t.children.size(), int(bounds[0]), int(bounds[1]), id)


func test_generated_has_dimorphism_and_convergence() -> void:
	var tax := TaxonomyGenerator.new().generate(schema, preset, 77)
	var juveniles := 0
	var convergent := 0
	for id in tax.taxa:
		var t: Taxon = tax.taxa[id]
		if t.dimorphism.has("juvenile"):
			juveniles += 1
		if not t.convergence.is_empty():
			convergent += 1
			assert_lt(tax.shared_rank(id, t.convergence.target), Ranks.ORDER, "konvergente Arten sind nicht nah verwandt")
	assert_eq(juveniles, tax.roots().size())
	assert_eq(convergent, int(preset.convergence.pairs))


func test_export_and_reload_gives_identical_creatures() -> void:
	var gen := TaxonomyGenerator.new().generate(schema, preset, 31337)
	var text := JSON.stringify(gen.to_dict(), "  ", false, true)
	var loader := TaxonomyLoader.new()
	var reloaded := loader.from_dict(JsonLoader.parse(text).data, schema)
	assert_not_null(reloaded, str(loader.errors))
	assert_eq(loader.warnings, PackedStringArray())
	assert_eq(reloaded.taxa.size(), gen.taxa.size())
	var f1 := IndividualFactory.new(gen)
	var f2 := IndividualFactory.new(reloaded)
	for sp in gen.species():
		for n in 3:
			var a := f1.create_individual(sp.id, n)
			var b := f2.create_individual(sp.id, n)
			assert_true(a.genome.is_equal_approx_to(b.genome), sp.id)
			assert_eq(a.sex, b.sex)


func test_demo_roundtrip() -> void:
	var tax := TestData.demo()
	var loader := TaxonomyLoader.new()
	var again := loader.from_dict(JsonLoader.parse(JSON.stringify(tax.to_dict())).data, schema)
	assert_not_null(again, str(loader.errors))
	var f1 := IndividualFactory.new(tax)
	var f2 := IndividualFactory.new(again)
	for sp in tax.species():
		assert_true(f1.mean_genome(sp.id).is_equal_approx_to(f2.mean_genome(sp.id)), sp.id)
