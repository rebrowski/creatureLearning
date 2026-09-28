class_name Dimorphism
extends RefCounted
## Geschlechts- und Altersdimorphismus.
##
## Jedes Taxon kann Regeln pro Stufe definieren; eine Art erbt die Regeln
## aller Vorfahren, feinere Ränge überschreiben gröbere pro Gen und Operation.
## Erwachsene bekommen die Regeln ihres Geschlechts ("male"/"female"),
## Jungtiere nur die "juvenile"-Regeln (kein Geschlechtsunterschied).
##
## Operationen (in dieser Reihenfolge angewendet):
##   scale – Wert multiplizieren (z. B. Jungtiere body_length × 0.6)
##   shift – Wert addieren (z. B. Männchen horn_length + 0.3)
##   set   – Wert ersetzen (z. B. Weibchen horn_count = 0)
## `strength` (SimilaritySettings.dimorphism_strength) blendet alles stufenlos aus.

const STAGES: PackedStringArray = ["male", "female", "juvenile"]
const SEXES: PackedStringArray = ["female", "male"]
const AGES: PackedStringArray = ["adult", "juvenile"]


static func stage_for(sex: String, age: String) -> String:
	return "juvenile" if age == "juvenile" else sex


## Zusammengeführte Regeln für eine Stufe entlang der Abstammung von `taxon_id`.
static func effective_rules(taxonomy: Taxonomy, taxon_id: String, stage: String) -> Dictionary:
	var merged := {"set": {}, "shift": {}, "scale": {}}
	for t in taxonomy.lineage(taxon_id):
		var rules: Dictionary = t.dimorphism.get(stage, {})
		for op in merged:
			merged[op].merge(rules.get(op, {}), true)
	return merged


static func apply(genome: Genome, rules: Dictionary, strength: float) -> void:
	if strength <= 0.0:
		return
	var schema := genome.schema
	for gene_id in rules.get("scale", {}):
		var g := schema.get_gene(gene_id)
		genome.values[gene_id] = g.sanitize(genome.f(gene_id) * lerpf(1.0, rules.scale[gene_id], strength))
	for gene_id in rules.get("shift", {}):
		var g := schema.get_gene(gene_id)
		genome.values[gene_id] = g.sanitize(genome.f(gene_id) + rules.shift[gene_id] * strength)
	for gene_id in rules.get("set", {}):
		var g := schema.get_gene(gene_id)
		genome.values[gene_id] = g.lerp_toward(genome.get_value(gene_id), rules["set"][gene_id], minf(strength, 1.0))
