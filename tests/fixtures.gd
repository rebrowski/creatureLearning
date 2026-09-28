class_name TestData
extends RefCounted
## Gemeinsame Hilfen für Tests: lädt Schema, Demo-Taxonomie und Generator-Preset.

const DEMO_PATH := "res://data/taxonomies/forest_demo.json"


static func schema() -> GenomeSchema:
	return GenomeSchema.load_file()


static func demo() -> Taxonomy:
	var loader := TaxonomyLoader.new()
	var tax := loader.load_file(DEMO_PATH, schema())
	assert(tax != null, "Demo-Taxonomie lädt nicht: %s" % [loader.errors])
	return tax


static func generated(seed_value := 4242, preset_overrides := {}) -> Taxonomy:
	var preset := TaxonomyGenerator.load_preset()
	preset.merge(preset_overrides, true)
	return TaxonomyGenerator.new().generate(schema(), preset, seed_value)


## Minimale gültige Taxonomie als Dictionary, zum Verändern in Fehler-Tests.
static func minimal_dict() -> Dictionary:
	return {
		"format": "creature_taxonomy/1",
		"seed": 1,
		"taxa": [{
			"id": "c", "rank": "class",
			"children": [{
				"id": "o", "rank": "order",
				"children": [{
					"id": "f", "rank": "family",
					"children": [{
						"id": "g", "rank": "genus",
						"children": [{"id": "s1", "rank": "species"}, {"id": "s2", "rank": "species"}],
					}],
				}],
			}],
		}],
	}
