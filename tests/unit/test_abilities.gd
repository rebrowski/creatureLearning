extends GutTest
## Fähigkeiten: Katalog, Kopplung an sichtbare Gene, Kontext, Demo-Design.

var schema: GenomeSchema
var catalog: AbilityCatalog
var tax: Taxonomy
var factory: IndividualFactory


func before_all() -> void:
	schema = TestData.schema()
	catalog = AbilityCatalog.load_file(schema)
	tax = TestData.demo()
	factory = IndividualFactory.new(tax)


func test_catalog_loads() -> void:
	assert_true(catalog.is_valid(), str(catalog.errors))
	for id in ["climb", "swim", "dig", "carry", "noise", "night_vision", "scent", "scare"]:
		assert_true(catalog.abilities.has(id), id)
		assert_false(schema.get_gene(id).visible, "Fähigkeits-Gen unsichtbar: " + id)


func test_values_in_range() -> void:
	for sp in tax.species():
		var p := AbilityProfile.new(catalog, factory.create_individual(sp.id, 0).genome)
		for id in catalog.order:
			assert_between(p.value(id), 0.0, 1.0)


func test_visible_coupling() -> void:
	var g := schema.default_genome()
	g.set_value("leg_count", 4)
	g.set_value("leg_length", 0.3)
	var short := catalog.base_value("swim", g)
	g.set_value("leg_length", 1.5)
	assert_gt(catalog.base_value("swim", g), short + 0.1, "lange Beine → besser im Wasser")
	g.set_value("antenna_length", 0.0)
	var no_ant := catalog.base_value("scent", g)
	g.set_value("antenna_length", 1.0)
	assert_gt(catalog.base_value("scent", g), no_ant, "Fühler → besser wittern")


func test_context() -> void:
	var g := schema.default_genome()
	var day := {"zone": "forest", "light": 1.0, "is_night": false, "rain": 0.0, "wetness": 0.0}
	assert_almost_eq(catalog.value_in("dig", g, {"zone": "rock"}), 0.0, 0.05, "Fels ist zu hart zum Graben")
	assert_lt(catalog.value_in("noise", g, {"rain": 1.0}), catalog.value_in("noise", g, day), "Regen dämpft Rufe")
	assert_lt(catalog.value_in("climb", g, {"wetness": 1.0}), catalog.value_in("climb", g, day), "nasser Fels ist rutschig")
	# Nachtsicht zählt nur im Dunkeln
	g.set_value("night_vision", 0.1)
	assert_almost_eq(catalog.value_in("night_vision", g, day), 1.0, 0.001)
	assert_almost_eq(catalog.value_in("night_vision", g, {"light": 0.0, "is_night": true}), 0.1, 0.001)


func test_lookalikes_differ_in_abilities() -> void:
	var fl := AbilityProfile.new(catalog, factory.mean_genome("stelzus_fluvialis"))
	var no := AbilityProfile.new(catalog, factory.mean_genome("stelzus_nocturnus"))
	assert_gt(no.value("night_vision"), fl.value("night_vision") + 0.4)
	assert_gt(fl.value("swim"), no.value("swim"))
	var mimic := AbilityProfile.new(catalog, factory.mean_genome("mimula_fallax"))
	assert_lt(mimic.value("swim"), fl.value("swim") - 0.4, "Nachahmer schwimmt schlecht")


func test_invalid_catalog() -> void:
	var c := AbilityCatalog.new()
	c._parse({"abilities": [{"id": "fly"}, {"id": "swim", "derived_from": [{"gene": "wings"}], "context": {"zones": {"lava": 1}, "moon": 2}}]}, schema, "test")
	assert_eq(c.errors.size(), 4, str(c.errors))
