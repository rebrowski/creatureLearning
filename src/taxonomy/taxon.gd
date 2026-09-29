class_name Taxon
extends RefCounted
## Ein Knoten der Taxonomie (Klasse, Ordnung, Familie, Gattung oder Art).
##
## Ein Taxon verändert das geerbte Mittel-Genom seines Eltern-Taxons:
##   set       – feste Werte (ersetzen den geerbten Wert, keine Zufallsabweichung)
##   shift     – feste Verschiebung (addiert, dann Zufallsabweichung)
##   variance  – eigene Streuung pro Gen statt SimilaritySettings.base_variance
##   individual_variance – Streuung der Individuen (statt base_variance[individual]), vererbt
##   morphs    – Varianten mit Häufigkeit, pro Individuum gewürfelt (Polymorphismus)
##   fixed     – Gene, die ab hier (inkl. aller Nachkommen und Individuen) nicht mehr
##               zufällig abweichen; explizites set/shift weiter unten bleibt möglich
## Details: docs/taxonomy_format.md

var id: String = ""
var name: String = ""
var common_name: String = ""
var rank: int = Ranks.CLASS
var parent_id: String = ""
var children: PackedStringArray = []
## gene_id -> Wert (bereits im Gen-Format, ENUM als Index)
var set_values: Dictionary = {}
## gene_id -> float (absolute Einheiten)
var shift: Dictionary = {}
## gene_id -> float (Bruchteil des Wertebereichs bzw. Wechselwahrscheinlichkeit bei ENUM);
## Schlüssel "*" gilt für alle nicht genannten Gene.
var variance: Dictionary = {}
## Wie variance, aber für das Rauschen der Individuen; gilt für den ganzen Teilbaum
## (feinster Eintrag gewinnt).
var individual_variance: Dictionary = {}
## [{"name": String, "p": float, "set": {}, "shift": {}, "scale": {}}]
var morphs: Array = []
## Gene ohne weitere Zufallsabweichung in diesem Teilbaum.
var fixed: PackedStringArray = []
## Stufe ("male", "female", "juvenile") -> {"set": {}, "shift": {}, "scale": {}}
var dimorphism: Dictionary = {}
## Leer oder {"target": String, "genes": PackedStringArray, "groups": PackedStringArray, "strength": float}
var convergence: Dictionary = {}
var notes: String = ""


func display_name() -> String:
	return "%s (%s)" % [name, common_name] if common_name != "" else name


func is_species() -> bool:
	return rank == Ranks.SPECIES


## JSON-Form ohne Kinder (die hängt Taxonomy.to_dict an).
func to_dict(schema: GenomeSchema) -> Dictionary:
	var d := {"id": id, "rank": Ranks.name_of(rank), "name": name}
	if common_name != "":
		d["common_name"] = common_name
	if not set_values.is_empty():
		d["set"] = _values_to_json(set_values, schema)
	if not shift.is_empty():
		d["shift"] = shift.duplicate()
	if not variance.is_empty():
		d["variance"] = variance.duplicate()
	if not individual_variance.is_empty():
		d["individual_variance"] = individual_variance.duplicate()
	if not morphs.is_empty():
		var list := []
		for m in morphs:
			var out := {"name": m.name, "p": m.p}
			if m["set"].size() > 0:
				out["set"] = _values_to_json(m["set"], schema)
			for op in ["shift", "scale"]:
				if m[op].size() > 0:
					out[op] = m[op].duplicate()
			list.append(out)
		d["morphs"] = list
	if not fixed.is_empty():
		d["fixed"] = Array(fixed)
	if not dimorphism.is_empty():
		var dim := {}
		for stage in dimorphism:
			var rules: Dictionary = dimorphism[stage]
			var out := {}
			if rules.get("set", {}).size() > 0:
				out["set"] = _values_to_json(rules["set"], schema)
			for op in ["shift", "scale"]:
				if rules.get(op, {}).size() > 0:
					out[op] = rules[op].duplicate()
			dim[stage] = out
		d["dimorphism"] = dim
	if not convergence.is_empty():
		var c := {"target": convergence["target"], "strength": convergence["strength"]}
		if convergence.get("genes", PackedStringArray()).size() > 0:
			c["genes"] = Array(convergence["genes"])
		if convergence.get("groups", PackedStringArray()).size() > 0:
			c["groups"] = Array(convergence["groups"])
		d["convergence"] = c
	if notes != "":
		d["notes"] = notes
	return d


static func _values_to_json(values: Dictionary, schema: GenomeSchema) -> Dictionary:
	var out := {}
	for gene_id in values:
		out[gene_id] = schema.get_gene(gene_id).to_json_value(values[gene_id])
	return out
