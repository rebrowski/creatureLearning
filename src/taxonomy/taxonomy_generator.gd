class_name TaxonomyGenerator
extends RefCounted
## Erzeugt zufällige, aber reproduzierbare Taxonomien aus Seed + Preset.
##
## Das Ergebnis ist eine ganz normale Taxonomy (wie aus JSON geladen) und lässt
## sich mit Taxonomy.to_dict() exportieren. Aussehen entsteht nicht hier,
## sondern in IndividualFactory aus base_seed + Taxon-IDs; der Generator legt
## nur Struktur, Namen, Dimorphismus und Konvergenz fest.

const FORMAT := "creature_generator_preset/1"
const DEFAULT_PRESET := "res://data/generator_presets/default.json"

var errors: PackedStringArray = []

var _rng := RandomNumberGenerator.new()
var _preset: Dictionary
var _used_names: Dictionary = {}


static func load_preset(path: String = DEFAULT_PRESET) -> Dictionary:
	var res := JsonLoader.read(path)
	if res.error != "":
		push_error(res.error)
		return {}
	return res.data


func generate(schema: GenomeSchema, preset: Dictionary, seed_value: int) -> Taxonomy:
	errors.clear()
	_preset = preset
	_used_names.clear()
	RngUtil.reseed(_rng, ["taxonomy_generator", seed_value])

	var tax := Taxonomy.new()
	tax.schema = schema
	tax.base_seed = seed_value
	tax.name = "Generiert (Seed %d)" % seed_value
	if preset.has("similarity"):
		tax.settings.apply_dict(preset["similarity"], errors, "preset.similarity")

	for i in int(preset.get("classes", 2)):
		_make_taxon(tax, Ranks.CLASS, "")
	_add_convergence(tax)
	return tax


func _make_taxon(tax: Taxonomy, rank: int, parent_id: String) -> void:
	var t := Taxon.new()
	t.rank = rank
	t.parent_id = parent_id
	t.name = _make_name(rank, tax.get_taxon(parent_id) if parent_id != "" else null)
	t.id = _unique_id(tax, t.name.to_lower().replace(" ", "_"))
	if rank == Ranks.CLASS:
		_add_juvenile(t, tax.schema)
	elif rank == Ranks.GENUS:
		_add_sexual(t, tax.schema)
	tax.add_taxon(t)
	if rank == Ranks.SPECIES:
		return
	var child_rank := rank + 1
	var bounds: Array = _preset.get("children_per_rank", {}).get(Ranks.name_of(child_rank), [1, 2])
	for n in RngUtil.range_i(_rng, bounds):
		_make_taxon(tax, child_rank, t.id)


# --- Dimorphismus -----------------------------------------------------------

func _add_juvenile(t: Taxon, schema: GenomeSchema) -> void:
	var cfg: Dictionary = _preset.get("juvenile", {})
	if cfg.is_empty() or _rng.randf() >= float(cfg.get("chance", 1.0)):
		return
	var rules := {"set": {}, "shift": {}, "scale": {}}
	for op in ["scale", "shift"]:
		for gene_id in cfg.get(op, {}):
			if schema.has_gene(gene_id):
				rules[op][gene_id] = snappedf(RngUtil.range_f(_rng, cfg[op][gene_id]), 0.001)
	t.dimorphism["juvenile"] = rules


func _add_sexual(t: Taxon, schema: GenomeSchema) -> void:
	var cfg: Dictionary = _preset.get("sexual", {})
	if cfg.is_empty() or _rng.randf() >= float(cfg.get("chance", 0.5)):
		return
	# Kandidaten: [stufe, gen, bereich]
	var candidates := []
	for stage in ["male", "female"]:
		var shifts: Dictionary = cfg.get(stage, {}).get("shift", {})
		for gene_id in shifts:
			if schema.has_gene(gene_id):
				candidates.append([stage, gene_id, shifts[gene_id]])
	RngUtil.shuffle(_rng, candidates)
	var count := mini(RngUtil.range_i(_rng, cfg.get("genes_per_taxon", [1, 2])), candidates.size())
	for n in count:
		var stage: String = candidates[n][0]
		if not t.dimorphism.has(stage):
			t.dimorphism[stage] = {"set": {}, "shift": {}, "scale": {}}
		t.dimorphism[stage]["shift"][candidates[n][1]] = snappedf(RngUtil.range_f(_rng, candidates[n][2]), 0.001)


# --- Konvergenz -------------------------------------------------------------

## Sucht Artenpaare aus verschiedenen Ordnungen (bevorzugt Klassen), deren
## fixierter Bauplan möglichst gut passt, und lässt die erste der zweiten ähneln.
func _add_convergence(tax: Taxonomy) -> void:
	var cfg: Dictionary = _preset.get("convergence", {})
	var pairs := int(cfg.get("pairs", 0))
	if pairs <= 0:
		return
	var factory := IndividualFactory.new(tax)
	var locked: Array[GeneDef] = []
	for g in tax.schema.genes:
		if g.visible and g.varies_until < Ranks.SPECIES:
			locked.append(g)
	var match_bodyplan := bool(cfg.get("require_matching_bodyplan", true))

	var all_species := tax.species()
	var candidates := []  # [score, a_id, b_id]
	for i in all_species.size():
		for j in all_species.size():
			if i == j:
				continue
			var a := all_species[i]
			var b := all_species[j]
			var shared := tax.shared_rank(a.id, b.id)
			if shared >= Ranks.ORDER:
				continue  # zu nah verwandt
			var score := 0.0 if shared < 0 else 0.5  # verschiedene Klassen bevorzugen
			if match_bodyplan:
				for g in locked:
					score += g.diff(factory.mean_genome(a.id).get_value(g.id), factory.mean_genome(b.id).get_value(g.id)) * g.distance_weight
			score += _rng.randf() * 0.01  # reproduzierbarer Tie-Break
			candidates.append([score, a.id, b.id])
	candidates.sort_custom(func(x, y): return x[0] < y[0])

	var used := {}
	for c in candidates:
		if pairs <= 0:
			break
		if used.has(c[1]) or used.has(c[2]):
			continue
		used[c[1]] = true
		used[c[2]] = true
		var groups := PackedStringArray(cfg.get("groups", ["color", "pattern"]))
		tax.get_taxon(c[1]).convergence = {
			"target": c[2],
			"genes": PackedStringArray(),
			"groups": groups,
			"strength": snappedf(RngUtil.range_f(_rng, cfg.get("strength", [0.8, 0.8])), 0.001),
		}
		pairs -= 1


# --- Namen ------------------------------------------------------------------

func _make_name(rank: int, parent: Taxon) -> String:
	var cfg: Dictionary = _preset.get("names", {})
	var syll: Array = cfg.get("syllables", ["ka", "lo", "mi", "ra"])
	var suffix: Dictionary = cfg.get("suffix", {})
	for attempt in 50:
		var n := ""
		if rank == Ranks.SPECIES:
			var epithets: Array = cfg.get("epithets", [])
			var epithet: String = RngUtil.pick(_rng, epithets) if not epithets.is_empty() and attempt < 20 else _syllables(syll, 2) + "is"
			n = "%s %s" % [parent.name, epithet]
		else:
			n = _syllables(syll, 2 if rank != Ranks.GENUS else _rng.randi_range(2, 3)).capitalize()
			var suf = suffix.get(Ranks.name_of(rank), "")
			n += str(RngUtil.pick(_rng, suf)) if suf is Array else str(suf)
		if not _used_names.has(n):
			_used_names[n] = true
			return n
	var fallback := "%s_%d" % [Ranks.name_of(rank), _used_names.size()]
	_used_names[fallback] = true
	return fallback


func _syllables(syll: Array, count: int) -> String:
	var s := ""
	for n in count:
		s += str(RngUtil.pick(_rng, syll))
	return s


func _unique_id(tax: Taxonomy, base: String) -> String:
	var id := base
	var n := 2
	while tax.has_taxon(id):
		id = "%s_%d" % [base, n]
		n += 1
	return id
