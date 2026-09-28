class_name TaxonomyLoader
extends RefCounted
## Lädt eine Taxonomie aus JSON und prüft sie gründlich.
##
## Nutzung:
##   var loader := TaxonomyLoader.new()
##   var tax := loader.load_file("res://data/taxonomies/forest_demo.json", schema)
##   if tax == null: print(loader.errors)
## Warnungen (z. B. unbekannte Felder) verhindern das Laden nicht.

const TAXON_KEYS := ["id", "rank", "name", "common_name", "set", "shift", "variance", "fixed",
		"dimorphism", "convergence", "children", "notes"]
const DIMORPHISM_OPS := ["set", "shift", "scale"]
const CONVERGENCE_KEYS := ["target", "genes", "groups", "strength"]

var errors: PackedStringArray = []
var warnings: PackedStringArray = []


func load_file(path: String, schema: GenomeSchema) -> Taxonomy:
	var res := JsonLoader.read(path)
	if res.error != "":
		errors.append(res.error)
		return null
	return from_dict(res.data, schema, path)


func from_dict(data: Variant, schema: GenomeSchema, source := "<taxonomy>") -> Taxonomy:
	errors.clear()
	warnings.clear()
	if schema == null or not schema.is_valid():
		errors.append("%s: kein gültiges Genom-Schema übergeben" % source)
		return null
	if not data is Dictionary:
		errors.append("%s: Wurzel muss ein Objekt sein" % source)
		return null
	if data.get("format", Taxonomy.FORMAT) != Taxonomy.FORMAT:
		warnings.append("%s: unerwartetes format '%s' (erwartet %s)" % [source, data.get("format"), Taxonomy.FORMAT])

	var tax := Taxonomy.new()
	tax.schema = schema
	tax.name = str(data.get("name", source.get_file()))
	tax.notes = str(data.get("notes", ""))
	tax.base_seed = int(data.get("seed", 0))
	if data.has("similarity"):
		if data["similarity"] is Dictionary:
			tax.settings.apply_dict(data["similarity"], errors, source + ": similarity")
		else:
			errors.append("%s: 'similarity' muss ein Objekt sein" % source)

	var list = data.get("taxa", null)
	if not list is Array or list.is_empty():
		errors.append("%s: 'taxa' muss eine nicht-leere Liste von Klassen sein" % source)
		return null
	for i in list.size():
		_parse_taxon(list[i], "", Ranks.CLASS, tax, "%s: taxa[%d]" % [source, i])

	_validate_convergence(tax, source)
	return tax if errors.is_empty() else null


func _parse_taxon(d: Variant, parent_id: String, expected_rank: int, tax: Taxonomy, ctx: String) -> void:
	if not d is Dictionary:
		errors.append("%s: Taxon muss ein Objekt sein" % ctx)
		return
	var id := str(d.get("id", ""))
	if id.is_empty():
		errors.append("%s: 'id' fehlt" % ctx)
		return
	ctx = "%s (%s)" % [ctx, id]
	if tax.has_taxon(id):
		errors.append("%s: id '%s' ist doppelt vergeben" % [ctx, id])
		return
	for key in d:
		if not TAXON_KEYS.has(key):
			warnings.append("%s: unbekanntes Feld '%s' wird ignoriert" % [ctx, key])

	var t := Taxon.new()
	t.id = id
	t.parent_id = parent_id
	t.name = str(d.get("name", id))
	t.common_name = str(d.get("common_name", ""))
	t.notes = str(d.get("notes", ""))
	t.rank = expected_rank
	if d.has("rank"):
		var r := Ranks.from_name(str(d["rank"]))
		if r < 0 or r > Ranks.SPECIES:
			errors.append("%s: unbekannter Rang '%s'" % [ctx, d["rank"]])
			return
		if r != expected_rank:
			errors.append("%s: Rang '%s' passt nicht – an dieser Stelle wird '%s' erwartet (Klasse > Ordnung > Familie > Gattung > Art)"
					% [ctx, d["rank"], Ranks.name_of(expected_rank)])
			return

	t.set_values = _parse_values(d.get("set", {}), tax.schema, ctx + ".set", t.rank, true)
	t.shift = _parse_numbers(d.get("shift", {}), tax.schema, ctx + ".shift", t.rank, false)
	t.variance = _parse_numbers(d.get("variance", {}), tax.schema, ctx + ".variance", t.rank, true)
	var fixed = d.get("fixed", [])
	if not fixed is Array:
		errors.append("%s.fixed: muss eine Liste von Gen-IDs sein" % ctx)
	else:
		for gene_id in fixed:
			if not tax.schema.has_gene(str(gene_id)):
				errors.append("%s.fixed: unbekanntes Gen '%s'" % [ctx, gene_id])
			else:
				t.fixed.append(str(gene_id))
	for gene_id in t.shift:
		if t.set_values.has(gene_id):
			warnings.append("%s: '%s' steht in set und shift – shift wird ignoriert" % [ctx, gene_id])
	if d.has("dimorphism"):
		t.dimorphism = _parse_dimorphism(d["dimorphism"], tax.schema, ctx + ".dimorphism")
	if d.has("convergence"):
		t.convergence = _parse_convergence(d["convergence"], tax.schema, ctx + ".convergence")
	tax.add_taxon(t)

	var kids = d.get("children", [])
	if not kids is Array:
		errors.append("%s: 'children' muss eine Liste sein" % ctx)
		return
	if t.rank == Ranks.SPECIES and not kids.is_empty():
		errors.append("%s: eine Art darf keine Kinder haben" % ctx)
		return
	if t.rank < Ranks.SPECIES and kids.is_empty():
		warnings.append("%s: %s ohne Kinder – enthält keine Arten" % [ctx, Ranks.label_of(t.rank)])
	for i in kids.size():
		_parse_taxon(kids[i], id, t.rank + 1, tax, "%s.children[%d]" % [ctx, i])


## gene_id -> Wert im Gen-Format. `check_lock`: Gen muss auf diesem Rang veränderbar sein.
func _parse_values(d: Variant, schema: GenomeSchema, ctx: String, rank: int, check_lock: bool) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		errors.append("%s: muss ein Objekt {gen: wert} sein" % ctx)
		return out
	for gene_id in d:
		var g := schema.get_gene(gene_id)
		if g == null:
			errors.append("%s: unbekanntes Gen '%s'" % [ctx, gene_id])
			continue
		if check_lock and rank > g.varies_until:
			errors.append("%s: Gen '%s' ist ab Rang '%s' fixiert und darf auf Rang '%s' nicht mehr gesetzt werden"
					% [ctx, gene_id, Ranks.name_of(g.varies_until + 1), Ranks.name_of(rank)])
			continue
		var v = g.parse_value(d[gene_id])
		if v == null:
			var hint := " (erlaubt: %s)" % ", ".join(g.options) if g.type == GeneDef.Type.ENUM else ""
			errors.append("%s: ungültiger Wert '%s' für '%s'%s" % [ctx, d[gene_id], gene_id, hint])
			continue
		if g.type != GeneDef.Type.ENUM and not g.wrap and (float(d[gene_id]) < g.min_value or float(d[gene_id]) > g.max_value):
			warnings.append("%s: '%s' = %s liegt außerhalb [%s, %s] und wird begrenzt"
					% [ctx, gene_id, d[gene_id], g.min_value, g.max_value])
		out[gene_id] = v
	return out


## gene_id -> float. `allow_enum`: ENUM-Gene zulassen (für variance, nicht für shift).
func _parse_numbers(d: Variant, schema: GenomeSchema, ctx: String, rank: int, allow_enum: bool) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		errors.append("%s: muss ein Objekt {gen: zahl} sein" % ctx)
		return out
	for gene_id in d:
		var g := schema.get_gene(gene_id)
		if g == null:
			errors.append("%s: unbekanntes Gen '%s'" % [ctx, gene_id])
			continue
		if not (d[gene_id] is float or d[gene_id] is int):
			errors.append("%s: '%s' muss eine Zahl sein" % [ctx, gene_id])
			continue
		if g.type == GeneDef.Type.ENUM and not allow_enum:
			errors.append("%s: '%s' ist ein enum-Gen und kann nicht verschoben werden (set verwenden)" % [ctx, gene_id])
			continue
		if rank > g.varies_until:
			errors.append("%s: Gen '%s' ist auf Rang '%s' fixiert" % [ctx, gene_id, Ranks.name_of(rank)])
			continue
		out[gene_id] = float(d[gene_id])
	return out


func _parse_dimorphism(d: Variant, schema: GenomeSchema, ctx: String) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		errors.append("%s: muss ein Objekt sein" % ctx)
		return out
	for stage in d:
		if not Dimorphism.STAGES.has(stage):
			errors.append("%s: unbekannte Stufe '%s' (erlaubt: %s)" % [ctx, stage, ", ".join(Dimorphism.STAGES)])
			continue
		var rules = d[stage]
		if not rules is Dictionary:
			errors.append("%s.%s: muss ein Objekt sein" % [ctx, stage])
			continue
		var parsed := {"set": {}, "shift": {}, "scale": {}}
		for op in rules:
			if not DIMORPHISM_OPS.has(op):
				errors.append("%s.%s: unbekannte Operation '%s' (erlaubt: set, shift, scale)" % [ctx, stage, op])
				continue
			var sub_ctx := "%s.%s.%s" % [ctx, stage, op]
			# Dimorphismus darf bewusst auch fixierte Gene ändern (z. B. Larven ohne Beine).
			if op == "set":
				parsed["set"] = _parse_values(rules[op], schema, sub_ctx, Ranks.CLASS, false)
			else:
				parsed[op] = _parse_numbers(rules[op], schema, sub_ctx, Ranks.CLASS, false)
		out[stage] = parsed
	return out


func _parse_convergence(d: Variant, schema: GenomeSchema, ctx: String) -> Dictionary:
	if not d is Dictionary:
		errors.append("%s: muss ein Objekt sein" % ctx)
		return {}
	for key in d:
		if not CONVERGENCE_KEYS.has(key):
			warnings.append("%s: unbekanntes Feld '%s'" % [ctx, key])
	var target := str(d.get("target", ""))
	if target.is_empty():
		errors.append("%s: 'target' fehlt" % ctx)
		return {}
	var genes := PackedStringArray()
	for gene_id in d.get("genes", []):
		if not schema.has_gene(gene_id):
			errors.append("%s.genes: unbekanntes Gen '%s'" % [ctx, gene_id])
		else:
			genes.append(gene_id)
	var groups := PackedStringArray()
	for group in d.get("groups", []):
		if not schema.groups.has(group):
			errors.append("%s.groups: unbekannte Gruppe '%s' (vorhanden: %s)" % [ctx, group, ", ".join(schema.groups)])
		else:
			groups.append(group)
	if genes.is_empty() and groups.is_empty():
		errors.append("%s: 'genes' oder 'groups' angeben" % ctx)
	var strength := float(d.get("strength", 0.8))
	if strength < 0.0 or strength > 1.0:
		errors.append("%s: strength muss zwischen 0 und 1 liegen" % ctx)
	return {"target": target, "genes": genes, "groups": groups, "strength": clampf(strength, 0.0, 1.0)}


func _validate_convergence(tax: Taxonomy, source: String) -> void:
	for id in tax.taxa:
		var t: Taxon = tax.taxa[id]
		if t.convergence.is_empty():
			continue
		var target: String = t.convergence.target
		var ctx := "%s: Taxon '%s'.convergence" % [source, id]
		if not tax.has_taxon(target):
			errors.append("%s: Ziel '%s' existiert nicht" % [ctx, target])
		elif target == id or tax.is_ancestor(target, id) or tax.is_ancestor(id, target):
			errors.append("%s: Ziel '%s' darf weder das Taxon selbst noch Vorfahre oder Nachkomme sein" % [ctx, target])
	# Zyklen über mehrere Konvergenzen erkennen (A -> B -> A, auch über Vorfahren).
	# Das Mittel-Genom eines Taxons braucht das seines Eltern-Taxons und ggf. das
	# seines Konvergenz-Ziels; dieser Abhängigkeitsgraph muss zyklenfrei sein.
	var state := {}  # id -> 1 (in Bearbeitung) / 2 (fertig)
	for id in tax.taxa:
		if _has_cycle(tax, id, state):
			errors.append("%s: Konvergenz-Zyklus über Taxon '%s'" % [source, id])
			return


func _has_cycle(tax: Taxonomy, id: String, state: Dictionary) -> bool:
	if state.get(id, 0) == 2:
		return false
	if state.get(id, 0) == 1:
		return true
	state[id] = 1
	var t: Taxon = tax.get_taxon(id)
	var deps: Array = []
	if t.parent_id != "":
		deps.append(t.parent_id)
	if not t.convergence.is_empty() and tax.has_taxon(t.convergence.target):
		deps.append(t.convergence.target)
	for dep in deps:
		if _has_cycle(tax, dep, state):
			return true
	state[id] = 2
	return false
