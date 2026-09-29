class_name GenomeSchema
extends RefCounted
## Menge aller Gen-Definitionen (geladen aus data/genome_schema.json).
##
## Die Reihenfolge der Gene ist die Reihenfolge in der Datei; sie bestimmt
## nur die Anzeige, nicht die Zufallswerte (siehe RngUtil).

const FORMAT := "creature_genome_schema/1"
const DEFAULT_PATH := "res://data/genome_schema.json"

var genes: Array[GeneDef] = []
## Gruppen in Reihenfolge ihres ersten Auftretens.
var groups: PackedStringArray = []
var errors: PackedStringArray = []
var _by_id: Dictionary = {}


static func load_file(path: String = DEFAULT_PATH) -> GenomeSchema:
	var res := JsonLoader.read(path)
	if res.error != "":
		var s := GenomeSchema.new()
		s.errors.append(res.error)
		return s
	return from_dict(res.data, path)


static func from_dict(data: Variant, source := "<schema>") -> GenomeSchema:
	var s := GenomeSchema.new()
	if not data is Dictionary:
		s.errors.append("%s: Wurzel muss ein Objekt sein" % source)
		return s
	var list = data.get("genes", null)
	if not list is Array:
		s.errors.append("%s: 'genes' muss eine Liste sein" % source)
		return s
	for i in list.size():
		if not list[i] is Dictionary:
			s.errors.append("%s: genes[%d] ist kein Objekt" % [source, i])
			continue
		var g := GeneDef.from_dict(list[i], s.errors, "%s: genes[%d]" % [source, i])
		if g == null:
			continue
		if s.has_gene(g.id):
			s.errors.append("%s: Gen '%s' ist doppelt definiert" % [source, g.id])
			continue
		s.add_gene(g)
	for g in s.genes:
		if g.depends_on != "" and not s.has_gene(g.depends_on):
			s.errors.append("%s: Gen '%s' hängt von unbekanntem Gen '%s' ab" % [source, g.id, g.depends_on])
	return s


func add_gene(g: GeneDef) -> void:
	genes.append(g)
	_by_id[g.id] = g
	if not groups.has(g.group):
		groups.append(g.group)


func has_gene(id: String) -> bool:
	return _by_id.has(id)


func get_gene(id: String) -> GeneDef:
	return _by_id.get(id, null)


func genes_in_group(group: String) -> Array[GeneDef]:
	var out: Array[GeneDef] = []
	for g in genes:
		if g.group == group:
			out.append(g)
	return out


func default_genome() -> Genome:
	var genome := Genome.new(self)
	for g in genes:
		genome.values[g.id] = g.default_value
	return genome


func is_valid() -> bool:
	return errors.is_empty()
