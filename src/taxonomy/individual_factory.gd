class_name IndividualFactory
extends RefCounted
## Erzeugt Mittel-Genome für Taxa und Genome für einzelne Kreaturen.
##
## Ablauf für eine Kreatur (alles deterministisch aus Taxonomy.base_seed):
##   1. Start: Standardwerte aus dem Schema.
##   2. Für jeden Rang Klasse -> Art das Mittel-Genom des Taxons bilden:
##        set   -> Wert ersetzen
##        sonst -> Wert + shift + Zufall(sigma = variance bzw. base_variance[rang] × spread[rang])
##      Gene mit varies_until gröber als der Rang bleiben unverändert,
##      Gene aus `fixed` (dieses Taxon oder Vorfahren) bekommen keinen Zufall.
##      Danach ggf. Konvergenz Richtung Vorbild-Taxon.
##   3. Individuelles Rauschen (Rang INDIVIDUAL; Streuung ggf. aus individual_variance).
##   4. Polymorphismus: jedes Taxon der Abstammung mit `morphs` würfelt eine Variante.
##   5. Geschlechts- bzw. Altersdimorphismus.
## Mittel-Genome werden gecacht; nach Änderung der Einstellungen clear_cache() aufrufen.

var taxonomy: Taxonomy
var settings: SimilaritySettings

var _mean_cache: Dictionary = {}
var _resolving: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init(p_taxonomy: Taxonomy, p_settings: SimilaritySettings = null) -> void:
	taxonomy = p_taxonomy
	settings = p_settings if p_settings != null else p_taxonomy.settings


func clear_cache() -> void:
	_mean_cache.clear()


## Mittel-Genom eines Taxons (ohne individuelles Rauschen und Dimorphismus).
## Nicht verändern – bei Bedarf .copy() verwenden.
func mean_genome(taxon_id: String) -> Genome:
	if _mean_cache.has(taxon_id):
		return _mean_cache[taxon_id]
	var taxon := taxonomy.get_taxon(taxon_id)
	assert(taxon != null, "Unbekanntes Taxon: %s" % taxon_id)
	if _resolving.has(taxon_id):
		push_error("Konvergenz-Zyklus bei Taxon '%s'" % taxon_id)
		return taxonomy.schema.default_genome()
	_resolving[taxon_id] = true

	var genome: Genome
	if taxon.parent_id == "":
		genome = taxonomy.schema.default_genome()
	else:
		genome = mean_genome(taxon.parent_id).copy()
	_apply_taxon(genome, taxon)
	if not taxon.convergence.is_empty():
		var target := mean_genome(taxon.convergence.target)
		var strength: float = taxon.convergence.strength * settings.convergence_strength
		Convergence.apply(genome, target, taxon.convergence, taxon.rank, clampf(strength, 0.0, 1.0))

	_resolving.erase(taxon_id)
	_mean_cache[taxon_id] = genome
	return genome


## Erzeugt Kreatur Nummer `index` einer Art. Gleiche Argumente -> gleiches Ergebnis.
## `sex`/`age` leer lassen, um sie zufällig (aber reproduzierbar) zu bestimmen;
## `juvenile_chance` gilt nur dann.
func create_individual(species_id: String, index: int, sex := "", age := "", juvenile_chance := 0.25) -> Individual:
	var species := taxonomy.get_taxon(species_id)
	assert(species != null and species.is_species(), "'%s' ist keine Art" % species_id)
	var ind := Individual.new()
	ind.species_id = species_id
	ind.index = index
	ind.id = "%s#%d" % [species_id, index]

	RngUtil.reseed(_rng, [taxonomy.base_seed, species_id, index, "sex"])
	ind.sex = sex if sex != "" else Dimorphism.SEXES[_rng.randi_range(0, 1)]
	RngUtil.reseed(_rng, [taxonomy.base_seed, species_id, index, "age"])
	ind.age = age if age != "" else ("juvenile" if _rng.randf() < juvenile_chance else "adult")

	var genome := mean_genome(species_id).copy()
	var fixed := fixed_genes(species_id)
	var ind_var := individual_variances(species_id)
	for g in taxonomy.schema.genes:
		if g.varies_until < Ranks.INDIVIDUAL or fixed.has(g.id):
			continue
		var sigma := settings.sigma(Ranks.INDIVIDUAL)
		if ind_var.has(g.id) or ind_var.has("*"):
			sigma = float(ind_var.get(g.id, ind_var.get("*"))) * settings.get_spread(Ranks.INDIVIDUAL)
		RngUtil.reseed(_rng, [taxonomy.base_seed, species_id, index, g.id])
		genome.values[g.id] = g.mutate(genome.get_value(g.id), sigma, sigma * settings.enum_switch_factor, _rng)

	for t in taxonomy.lineage(species_id):
		if t.morphs.is_empty():
			continue
		RngUtil.reseed(_rng, [taxonomy.base_seed, species_id, index, "morph", t.id])
		var r := _rng.randf()
		var acc := 0.0
		for m in t.morphs:
			acc += m.p
			if r < acc:
				ind.morphs[t.id] = m.name
				Dimorphism.apply(genome, m, 1.0)
				break

	var stage := Dimorphism.stage_for(ind.sex, ind.age)
	Dimorphism.apply(genome, Dimorphism.effective_rules(taxonomy, species_id, stage), settings.dimorphism_strength)
	ind.genome = genome
	return ind


## Bequemlichkeit: `count` Kreaturen einer Art, Nummern ab `first_index`.
func create_group(species_id: String, count: int, first_index := 0, juvenile_chance := 0.25) -> Array[Individual]:
	var out: Array[Individual] = []
	for n in count:
		out.append(create_individual(species_id, first_index + n, "", "", juvenile_chance))
	return out


## Individuen-Streuung pro Gen entlang der Abstammung (feinster Eintrag gewinnt,
## "*" = alle übrigen Gene).
func individual_variances(taxon_id: String) -> Dictionary:
	var out := {}
	for t in taxonomy.lineage(taxon_id):
		if t.individual_variance.has("*"):
			out.clear()  # feinerer Platzhalter ersetzt gröbere Einzelwerte
		out.merge(t.individual_variance, true)
	return out


## Alle Gene, die für `taxon_id` per `fixed` (selbst oder Vorfahren) festgelegt sind.
func fixed_genes(taxon_id: String) -> Dictionary:
	var out := {}
	for t in taxonomy.lineage(taxon_id):
		for gene_id in t.fixed:
			out[gene_id] = true
	return out


func _apply_taxon(genome: Genome, taxon: Taxon) -> void:
	var base_sigma := settings.sigma(taxon.rank)
	var spread := settings.get_spread(taxon.rank)
	var fixed := fixed_genes(taxon.id)
	for g in taxonomy.schema.genes:
		if taxon.rank > g.varies_until:
			continue
		if taxon.set_values.has(g.id):
			genome.values[g.id] = taxon.set_values[g.id]
			continue
		var value: Variant = genome.get_value(g.id)
		if taxon.shift.has(g.id):
			value = g.sanitize(float(value) + taxon.shift[g.id])
		if fixed.has(g.id):
			genome.values[g.id] = value
			continue
		var own = taxon.variance.get(g.id, taxon.variance.get("*"))
		var sigma: float = float(own) * spread if own != null else base_sigma
		var switch_p: float = sigma * settings.enum_switch_factor
		if own != null and g.type == GeneDef.Type.ENUM:
			switch_p = sigma  # bei ENUM ist variance direkt die Wechselwahrscheinlichkeit
		RngUtil.reseed(_rng, [taxonomy.base_seed, taxon.id, g.id])
		genome.values[g.id] = g.mutate(value, sigma, switch_p, _rng)
