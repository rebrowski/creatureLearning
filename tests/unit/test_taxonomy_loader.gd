extends GutTest
## Laden und Validieren von Taxonomie-JSON.

var schema: GenomeSchema


func before_all() -> void:
	schema = TestData.schema()


func _load(d: Variant) -> Array:
	var loader := TaxonomyLoader.new()
	var tax := loader.from_dict(d, schema)
	return [tax, loader]


func test_demo_loads_cleanly() -> void:
	var loader := TaxonomyLoader.new()
	var tax := loader.load_file(TestData.DEMO_PATH, schema)
	assert_not_null(tax, str(loader.errors))
	assert_eq(loader.warnings, PackedStringArray(), "Warnungen")
	assert_eq(tax.roots().size(), 2)
	assert_eq(tax.species().size(), 12)
	assert_eq(tax.base_seed, 20260928)


func test_demo_structure_and_helpers() -> void:
	var tax := TestData.demo()
	var path := tax.lineage("stelzus_fluvialis")
	assert_eq(path.size(), 5)
	assert_eq(path[0].id, "chitinopoda")
	assert_eq(path[4].rank, Ranks.SPECIES)
	assert_eq(tax.ancestor_at_rank("stelzus_fluvialis", Ranks.FAMILY).id, "longipedidae")
	assert_true(tax.is_ancestor("scuttlida", "talpides_cornutus"))
	assert_false(tax.is_ancestor("talpides_cornutus", "scuttlida"))
	assert_eq(tax.shared_rank("stelzus_fluvialis", "stelzus_nocturnus"), Ranks.GENUS)
	assert_eq(tax.shared_rank("stelzus_fluvialis", "hydropes_minor"), Ranks.FAMILY)
	assert_eq(tax.shared_rank("stelzus_fluvialis", "mimula_fallax"), -1)
	assert_eq(tax.species("tessella").size(), 2)


func test_minimal_dict_is_valid() -> void:
	var r := _load(TestData.minimal_dict())
	assert_not_null(r[0], str(r[1].errors))


func test_rank_can_be_omitted() -> void:
	var d := TestData.minimal_dict()
	d.taxa[0].erase("rank")
	d.taxa[0].children[0].erase("rank")
	var r := _load(d)
	assert_not_null(r[0], str(r[1].errors))
	assert_eq(r[0].get_taxon("o").rank, Ranks.ORDER)


func test_broken_json_reports_line() -> void:
	var res := JsonLoader.parse('{"taxa": [ {"id": "x",, } ]}', "kaputt.json")
	assert_ne(res.error, "")
	assert_string_contains(res.error, "kaputt.json")


func test_missing_file() -> void:
	var loader := TaxonomyLoader.new()
	assert_null(loader.load_file("res://gibt_es_nicht.json", schema))
	assert_eq(loader.errors.size(), 1)


func test_wrong_rank_order() -> void:
	var d := TestData.minimal_dict()
	d.taxa[0].children[0].rank = "genus"
	var r := _load(d)
	assert_null(r[0])
	assert_string_contains(str(r[1].errors), "passt nicht")


func test_unknown_gene_and_bad_enum() -> void:
	var d := TestData.minimal_dict()
	d.taxa[0]["set"] = {"legcount": 4, "gait": "fly"}
	var r := _load(d)
	assert_null(r[0])
	assert_eq(r[1].errors.size(), 2, str(r[1].errors))


func test_locked_gene_on_fine_rank_is_error() -> void:
	var d := TestData.minimal_dict()
	d.taxa[0].children[0].children[0]["set"] = {"leg_count": 6}  # Familie
	var r := _load(d)
	assert_null(r[0])
	assert_string_contains(str(r[1].errors), "fixiert")


func test_duplicate_id() -> void:
	var d := TestData.minimal_dict()
	d.taxa[0].children[0].children[0].children[0].children[1].id = "s1"
	var r := _load(d)
	assert_null(r[0])
	assert_string_contains(str(r[1].errors), "doppelt")


func test_species_with_children_is_error() -> void:
	var d := TestData.minimal_dict()
	d.taxa[0].children[0].children[0].children[0].children[0]["children"] = [{"id": "x"}]
	assert_null(_load(d)[0])


func test_unknown_field_is_warning_only() -> void:
	var d := TestData.minimal_dict()
	d.taxa[0]["colour"] = "red"
	var r := _load(d)
	assert_not_null(r[0])
	assert_eq(r[1].warnings.size(), 1)


func test_convergence_validation() -> void:
	var genus: Dictionary = TestData.minimal_dict().taxa[0].children[0].children[0].children[0]
	var cases := {
		"unbekanntes Ziel": {"target": "nope", "groups": ["color"]},
		"Vorfahre": {"target": "g", "groups": ["color"]},
		"keine Gene": {"target": "s2"},
		"falsche Gruppe": {"target": "s2", "groups": ["farbe"]},
	}
	for label in cases:
		var d := TestData.minimal_dict()
		d.taxa[0].children[0].children[0].children[0].children[0]["convergence"] = cases[label]
		assert_null(_load(d)[0], label)
	# Zyklus: s1 -> s2 -> s1
	var d2 := TestData.minimal_dict()
	var kids: Array = d2.taxa[0].children[0].children[0].children[0].children
	kids[0]["convergence"] = {"target": "s2", "groups": ["color"]}
	kids[1]["convergence"] = {"target": "s1", "groups": ["color"]}
	var r := _load(d2)
	assert_null(r[0])
	assert_string_contains(str(r[1].errors), "Zyklus")
	assert_not_null(genus)


func test_bad_dimorphism_stage() -> void:
	var d := TestData.minimal_dict()
	d.taxa[0]["dimorphism"] = {"baby": {"scale": {"body_length": 0.5}}}
	assert_null(_load(d)[0])


func test_similarity_overrides() -> void:
	var d := TestData.minimal_dict()
	d["similarity"] = {"spread": {"species": 0.0}, "dimorphism_strength": 0.5}
	var tax: Taxonomy = _load(d)[0]
	assert_eq(tax.settings.get_spread(Ranks.SPECIES), 0.0)
	assert_eq(tax.settings.dimorphism_strength, 0.5)


func test_fixed_list_validation() -> void:
	var d := TestData.minimal_dict()
	d.taxa[0]["fixed"] = ["leg_count", "wings"]
	var r := _load(d)
	assert_null(r[0])
	assert_string_contains(str(r[1].errors), "wings")
