extends GutTest
## Schema, Gen-Definitionen und Distanzfunktion.

var schema: GenomeSchema


func before_all() -> void:
	schema = TestData.schema()


func test_schema_loads_without_errors() -> void:
	assert_eq(schema.errors, PackedStringArray(), "Schema-Fehler")
	assert_gt(schema.genes.size(), 15)
	for id in ["segment_count", "leg_count", "leg_length", "body_shape", "horn_length", "tail_length",
			"crest_height", "antenna_length", "hue", "pattern_type", "gait", "speed", "posture"]:
		assert_true(schema.has_gene(id), "Gen fehlt: " + id)


func test_defaults_are_within_bounds() -> void:
	var g := schema.default_genome()
	for gene in schema.genes:
		assert_eq(gene.sanitize(g.get_value(gene.id)), g.get_value(gene.id), "Default außerhalb: " + gene.id)


func test_bodyplan_is_locked_early() -> void:
	assert_eq(schema.get_gene("leg_count").varies_until, Ranks.ORDER)
	assert_eq(schema.get_gene("body_shape").varies_until, Ranks.FAMILY)
	assert_eq(schema.get_gene("hue").varies_until, Ranks.INDIVIDUAL)


func test_sanitize_int_step_and_clamp() -> void:
	var legs := schema.get_gene("leg_count")
	assert_eq(legs.sanitize(3.2), 4)
	assert_eq(legs.sanitize(2.9), 2)
	assert_eq(legs.sanitize(99), 8)
	assert_eq(legs.sanitize(-5), 0)


func test_hue_wraps() -> void:
	var hue := schema.get_gene("hue")
	assert_almost_eq(float(hue.sanitize(1.1)), 0.1, 0.0001)
	assert_almost_eq(float(hue.sanitize(-0.2)), 0.8, 0.0001)
	assert_almost_eq(hue.diff(0.95, 0.05), 0.2, 0.0001, "Kreisabstand")
	assert_almost_eq(float(hue.lerp_toward(0.9, 0.1, 0.5)), 0.0, 0.0001, "kürzester Weg über 0")


func test_enum_parse_by_name_and_index() -> void:
	var gait := schema.get_gene("gait")
	assert_eq(gait.parse_value("scuttle"), gait.options.find("scuttle"))
	assert_eq(gait.parse_value(1), 1)
	assert_null(gait.parse_value("fly"))
	assert_null(gait.parse_value(99))


func test_invalid_schema_reports_errors() -> void:
	var s := GenomeSchema.from_dict({"genes": [
		{"id": "a", "type": "float", "min": 1, "max": 0},
		{"id": "b", "type": "banana"},
		{"id": "c", "type": "enum"},
		{"id": "d", "type": "float", "min": 0, "max": 1, "depends_on": "zzz"},
	]})
	assert_eq(s.errors.size(), 4, str(s.errors))


func test_distance_identity_symmetry_range() -> void:
	var a := schema.default_genome()
	var b := a.copy()
	assert_eq(GenomeDistance.distance(a, b), 0.0)
	b.set_value("leg_count", 8)
	b.set_value("hue", 0.8)
	var d_ab := GenomeDistance.distance(a, b)
	assert_gt(d_ab, 0.0)
	assert_almost_eq(d_ab, GenomeDistance.distance(b, a), 0.000001)
	assert_lte(d_ab, 1.0)


func test_distance_ignores_meaningless_genes() -> void:
	var a := schema.default_genome()
	a.set_value("horn_count", 0)
	var b := a.copy()
	b.set_value("horn_length", 0.8)  # ohne Hörner unsichtbar
	assert_eq(GenomeDistance.distance(a, b), 0.0)
	a.set_value("horn_count", 2)
	b.set_value("horn_count", 2)
	assert_gt(GenomeDistance.distance(a, b), 0.0)


func test_distance_ignores_invisible_genes() -> void:
	var s := GenomeSchema.from_dict({"genes": [
		{"id": "look", "type": "float", "min": 0, "max": 1},
		{"id": "swim", "type": "float", "min": 0, "max": 1, "visible": false},
	]})
	var a := s.default_genome()
	var b := a.copy()
	b.set_value("swim", 1.0)
	assert_eq(GenomeDistance.distance(a, b), 0.0)
	assert_gt(GenomeDistance.distance(a, b, false), 0.0)


func test_breakdown_has_groups_and_total() -> void:
	var a := schema.default_genome()
	var b := a.copy()
	b.set_value("hue", 0.8)
	var br := GenomeDistance.breakdown(a, b)
	assert_true(br.has("total"))
	assert_true(br.has("color"))
	assert_gt(br["color"], 0.0)
	assert_eq(br["bodyplan"], 0.0)
