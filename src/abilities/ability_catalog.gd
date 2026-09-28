class_name AbilityCatalog
extends RefCounted
## Fähigkeiten aus data/abilities/abilities.json.
##
## Wert einer Fähigkeit (0..1) für ein Genom:
##   basis = Genwert der Fähigkeit (unsichtbares Gen, vererbt wie das Aussehen)
##   + Σ weight × (normierter Wert des sichtbaren Gens − 0.5) × 2
## Kontextfaktor (Multiplikator) aus WorldContext.sample():
##   zones[zone] (sonst zones.default, sonst 1) × (night bzw. day) × lerp(1, rain, Regenstärke)
##   × (1 + wetness × Nässe)
## Fähigkeiten mit "darkness_only" zählen nur bei Dunkelheit; bei Tageslicht
## sieht jeder gut genug (Wert → 1).

const DEFAULT_PATH := "res://data/abilities/abilities.json"

## id -> {id, name, description, derived_from: [{gene, weight}], context: {}, darkness_only}
var abilities: Dictionary = {}
var order: PackedStringArray = []
var errors: PackedStringArray = []


static func load_file(schema: GenomeSchema, path: String = DEFAULT_PATH) -> AbilityCatalog:
	var c := AbilityCatalog.new()
	var res := JsonLoader.read(path)
	if res.error != "":
		c.errors.append(res.error)
		return c
	c._parse(res.data, schema, path)
	return c


func is_valid() -> bool:
	return errors.is_empty()


func _parse(d: Variant, schema: GenomeSchema, src: String) -> void:
	if not d is Dictionary or not d.get("abilities", null) is Array:
		errors.append("%s: erwartet {\"abilities\": [...]}" % src)
		return
	for i in d.abilities.size():
		var a: Dictionary = d.abilities[i]
		var ctx := "%s: abilities[%d]" % [src, i]
		var id := str(a.get("id", ""))
		var g := schema.get_gene(id)
		if g == null:
			errors.append("%s: zu '%s' gibt es kein Gen im Schema (unsichtbares Gen mit gleicher id anlegen)" % [ctx, id])
			continue
		var derived := []
		for dd in a.get("derived_from", []):
			if not schema.has_gene(str(dd.get("gene", ""))):
				errors.append("%s.derived_from: unbekanntes Gen '%s'" % [ctx, dd.get("gene")])
				continue
			derived.append({"gene": str(dd.gene), "weight": float(dd.get("weight", 0.0))})
		var context: Dictionary = a.get("context", {})
		for key in context:
			if not key in ["zones", "night", "day", "rain", "wetness"]:
				errors.append("%s.context: unbekannter Schlüssel '%s'" % [ctx, key])
		for z in context.get("zones", {}):
			if z != "default" and not ForestLayout.ZONES.has(z):
				errors.append("%s.context.zones: unbekannte Zone '%s'" % [ctx, z])
		abilities[id] = {"id": id, "name": str(a.get("name", id)), "description": str(a.get("description", "")),
				"derived_from": derived, "context": context, "darkness_only": bool(a.get("darkness_only", false))}
		order.append(id)


func name_of(id: String) -> String:
	return abilities[id].name if abilities.has(id) else id


## Wert ohne Kontext (0..1).
func base_value(id: String, genome: Genome) -> float:
	var a: Dictionary = abilities[id]
	var v := genome.f(id)
	var schema := genome.schema
	for dd in a.derived_from:
		var g := schema.get_gene(dd.gene)
		var norm := (float(genome.effective(dd.gene)) - g.min_value) / g.range_size()
		v += dd.weight * (norm - 0.5) * 2.0
	return clampf(v, 0.0, 1.0)


## Kontextfaktor für eine Situation (Dictionary wie WorldContext.sample()).
func context_factor(id: String, sample: Dictionary) -> float:
	var c: Dictionary = abilities[id].context
	var f := 1.0
	if c.has("zones"):
		var zones: Dictionary = c.zones
		f *= float(zones.get(sample.get("zone", ""), zones.get("default", 1.0)))
	if sample.get("is_night", false):
		f *= float(c.get("night", 1.0))
	else:
		f *= float(c.get("day", 1.0))
	f *= lerpf(1.0, float(c.get("rain", 1.0)), float(sample.get("rain", 0.0)))
	f *= 1.0 + float(c.get("wetness", 0.0)) * float(sample.get("wetness", 0.0))
	return maxf(f, 0.0)


## Wert im Kontext (0..1).
func value_in(id: String, genome: Genome, sample: Dictionary) -> float:
	var v := base_value(id, genome)
	if abilities[id].darkness_only:
		var darkness := 1.0 - clampf(float(sample.get("light", 1.0)), 0.0, 1.0)
		v = lerpf(1.0, v, darkness)
	return clampf(v * context_factor(id, sample), 0.0, 1.0)
