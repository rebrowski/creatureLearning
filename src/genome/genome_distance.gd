class_name GenomeDistance
extends RefCounted
## Distanz zwischen zwei Genomen: gewichteter Mittelwert der normierten
## Gen-Unterschiede, Ergebnis in [0, 1]. 0 = identisch.
##
## Nur sichtbare Gene zählen (Standard), bedeutungslose Gene werden über
## Genome.effective() neutralisiert. Die Gewichte stehen im Schema ("weight").


static func distance(a: Genome, b: Genome, visible_only := true) -> float:
	var sum := 0.0
	var weight_sum := 0.0
	for g in a.schema.genes:
		if visible_only and not g.visible:
			continue
		sum += g.distance_weight * g.diff(a.effective(g.id), b.effective(g.id))
		weight_sum += g.distance_weight
	return sum / weight_sum if weight_sum > 0.0 else 0.0


## Distanz pro Merkmalsgruppe plus "total". Jede Gruppe ist in sich normiert.
static func breakdown(a: Genome, b: Genome, visible_only := true) -> Dictionary:
	var sums := {}
	var weights := {}
	for g in a.schema.genes:
		if visible_only and not g.visible:
			continue
		sums[g.group] = sums.get(g.group, 0.0) + g.distance_weight * g.diff(a.effective(g.id), b.effective(g.id))
		weights[g.group] = weights.get(g.group, 0.0) + g.distance_weight
	var out := {}
	for group in a.schema.groups:
		if weights.has(group) and weights[group] > 0.0:
			out[group] = sums[group] / weights[group]
	out["total"] = distance(a, b, visible_only)
	return out


## Liste pro Gen: {id, group, a, b, diff}. Für Debug-Tabellen.
static func gene_diffs(a: Genome, b: Genome) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in a.schema.genes:
		out.append({
			"id": g.id,
			"group": g.group,
			"a": a.get_value(g.id),
			"b": b.get_value(g.id),
			"diff": g.diff(a.effective(g.id), b.effective(g.id)),
		})
	return out
