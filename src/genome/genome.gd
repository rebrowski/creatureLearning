class_name Genome
extends RefCounted
## Konkreter Parametersatz einer Kreatur (oder Mittelwert eines Taxons).

var schema: GenomeSchema
## gene_id -> Wert (float oder int, siehe GeneDef)
var values: Dictionary = {}


func _init(p_schema: GenomeSchema = null) -> void:
	schema = p_schema


func get_value(id: String) -> Variant:
	if values.has(id):
		return values[id]
	var g := schema.get_gene(id)
	return g.default_value if g else null


## Setzt einen Wert und bringt ihn in den gültigen Bereich.
func set_value(id: String, value: Variant) -> void:
	var g := schema.get_gene(id)
	assert(g != null, "Unbekanntes Gen: %s" % id)
	values[id] = g.sanitize(value)


func f(id: String) -> float:
	return float(get_value(id))


func i(id: String) -> int:
	return int(get_value(id))


## Name der Option bei ENUM-Genen.
func option(id: String) -> String:
	var g := schema.get_gene(id)
	return g.options[int(get_value(id))] if g and g.type == GeneDef.Type.ENUM else ""


## Wert wie für Distanz/Darstellung relevant: bedeutungslose Gene
## (depends_on == 0) liefern ihren Minimalwert.
func effective(id: String) -> Variant:
	var g := schema.get_gene(id)
	if g.depends_on != "" and int(round(float(get_value(g.depends_on)))) == 0:
		return g.min_value if g.type == GeneDef.Type.FLOAT else int(g.min_value)
	return get_value(id)


func copy() -> Genome:
	var c := Genome.new(schema)
	c.values = values.duplicate()
	return c


## Lesbare Form (ENUM als Name), z. B. für JSON-Export oder Debug-Ausgabe.
func to_dict() -> Dictionary:
	var d := {}
	for g in schema.genes:
		d[g.id] = g.to_json_value(get_value(g.id))
	return d


func is_equal_approx_to(other: Genome, eps := 0.0001) -> bool:
	for g in schema.genes:
		if absf(float(get_value(g.id)) - float(other.get_value(g.id))) > eps:
			return false
	return true
