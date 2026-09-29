class_name SpeciesDiagnostics
extends RefCounted
## Wie gut trennt ein einzelnes Gen zwei Arten? (Designwerkzeug)
##
## Für jedes Gen wird die beste einfache Regel gesucht: bei Zahlen eine
## Schwelle („Wert ≤ x → Art A“), bei enum-Genen die beste Zuordnung Option → Art.
## Ergebnis: Trefferquote 0.5 (Zufall) bis 1.0 (perfekt diagnostisch).
## Stichprobe: erwachsene Tiere, Geschlecht zufällig, Nummern 0..samples-1.


## Liefert [{gene, group, accuracy}] absteigend nach Trefferquote.
static func separability(factory: IndividualFactory, species_a: String, species_b: String,
		samples := 200, visible_only := true) -> Array[Dictionary]:
	var ga: Array[Genome] = []
	var gb: Array[Genome] = []
	for n in samples:
		ga.append(factory.create_individual(species_a, n, "", "adult").genome)
		gb.append(factory.create_individual(species_b, n, "", "adult").genome)
	var out: Array[Dictionary] = []
	for g in factory.taxonomy.schema.genes:
		if visible_only and not g.visible:
			continue
		var va := ga.map(func(x: Genome): return float(x.effective(g.id)))
		var vb := gb.map(func(x: Genome): return float(x.effective(g.id)))
		var acc := _enum_accuracy(va, vb) if g.type == GeneDef.Type.ENUM else _threshold_accuracy(va, vb)
		out.append({"gene": g.id, "group": g.group, "accuracy": acc})
	out.sort_custom(func(x, y): return x.accuracy > y.accuracy)
	return out


## Höchste Einzelgen-Trefferquote (0.5..1).
static func best_single_gene(factory: IndividualFactory, species_a: String, species_b: String, samples := 200) -> Dictionary:
	return separability(factory, species_a, species_b, samples)[0]


static func _threshold_accuracy(va: Array, vb: Array) -> float:
	var all := []
	for v in va:
		all.append([v, 0])
	for v in vb:
		all.append([v, 1])
	all.sort_custom(func(x, y): return x[0] < y[0])
	var best := 0.5
	var below_a := 0
	var below_b := 0
	for i in all.size():
		if all[i][1] == 0:
			below_a += 1
		else:
			below_b += 1
		if i + 1 < all.size() and all[i + 1][0] == all[i][0]:
			continue  # Schwelle nur zwischen verschiedenen Werten
		var acc := float(below_a + (vb.size() - below_b)) / all.size()
		best = maxf(best, maxf(acc, 1.0 - acc))
	return best


static func _enum_accuracy(va: Array, vb: Array) -> float:
	var counts := {}
	for v in va:
		counts[v] = counts.get(v, Vector2i.ZERO) + Vector2i(1, 0)
	for v in vb:
		counts[v] = counts.get(v, Vector2i.ZERO) + Vector2i(0, 1)
	var correct := 0
	for k in counts:
		correct += maxi(counts[k].x, counts[k].y)
	return float(correct) / (va.size() + vb.size())
