class_name Convergence
extends RefCounted
## Konvergente Merkmale: ein Taxon wird in ausgewählten sichtbaren Genen seinem
## (nicht verwandten) Vorbild angenähert.
##
## Angewendet auf das Mittel-Genom des Taxons, wirkt also auf alle Nachkommen.
## Fixierte Gene (varies_until gröber als der Rang des Taxons) bleiben
## unverändert – ein Sechsbeiner wird nicht zum Vierbeiner. Für starke
## Ähnlichkeit sollte der Bauplan daher schon auf höherem Rang passen.


## Gene, die die Konvergenz-Angabe betrifft (Einzel-Gene plus Gruppen, nur sichtbare).
static func affected_genes(schema: GenomeSchema, spec: Dictionary) -> Array[GeneDef]:
	var out: Array[GeneDef] = []
	var genes: PackedStringArray = spec.get("genes", PackedStringArray())
	var groups: PackedStringArray = spec.get("groups", PackedStringArray())
	for g in schema.genes:
		if g.visible and (genes.has(g.id) or groups.has(g.group)):
			out.append(g)
	return out


## Zieht `genome` Richtung `target` (in place). `strength` in [0, 1].
static func apply(genome: Genome, target: Genome, spec: Dictionary, rank: int, strength: float) -> void:
	if strength <= 0.0:
		return
	for g in affected_genes(genome.schema, spec):
		if rank > g.varies_until:
			continue
		genome.values[g.id] = g.lerp_toward(genome.get_value(g.id), target.get_value(g.id), strength)
