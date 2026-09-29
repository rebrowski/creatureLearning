class_name Taxonomy
extends RefCounted
## Baum aus Taxa plus Seed, Schema und Ähnlichkeits-Einstellungen.
##
## Reine Datenstruktur – die Erzeugung von Genomen übernimmt IndividualFactory.

const FORMAT := "creature_taxonomy/1"

var name: String = ""
## Basis aller Zufallswerte dieser Taxonomie.
var base_seed: int = 0
var schema: GenomeSchema
var settings: SimilaritySettings = SimilaritySettings.new()
var notes: String = ""
## id -> Taxon
var taxa: Dictionary = {}
## IDs der Klassen in Einfügereihenfolge.
var root_ids: PackedStringArray = []


func add_taxon(t: Taxon) -> void:
	taxa[t.id] = t
	if t.parent_id == "":
		root_ids.append(t.id)
	else:
		taxa[t.parent_id].children.append(t.id)


func has_taxon(id: String) -> bool:
	return taxa.has(id)


func get_taxon(id: String) -> Taxon:
	return taxa.get(id, null)


func children_of(id: String) -> Array[Taxon]:
	var out: Array[Taxon] = []
	for cid in taxa[id].children:
		out.append(taxa[cid])
	return out


func roots() -> Array[Taxon]:
	var out: Array[Taxon] = []
	for rid in root_ids:
		out.append(taxa[rid])
	return out


## Pfad von der Klasse bis einschließlich `id`.
func lineage(id: String) -> Array[Taxon]:
	var out: Array[Taxon] = []
	var t: Taxon = taxa.get(id, null)
	while t != null:
		out.push_front(t)
		t = taxa.get(t.parent_id, null)
	return out


func ancestor_at_rank(id: String, rank: int) -> Taxon:
	for t in lineage(id):
		if t.rank == rank:
			return t
	return null


## true, wenn `ancestor_id` ein echter Vorfahre von `id` ist.
func is_ancestor(ancestor_id: String, id: String) -> bool:
	var t: Taxon = taxa.get(id, null)
	while t != null and t.parent_id != "":
		if t.parent_id == ancestor_id:
			return true
		t = taxa.get(t.parent_id, null)
	return false


## Feinster gemeinsamer Rang zweier Taxa (z. B. GENUS bei zwei Arten derselben
## Gattung). -1, wenn sie in verschiedenen Klassen liegen.
func shared_rank(a_id: String, b_id: String) -> int:
	var la := lineage(a_id)
	var lb := lineage(b_id)
	var shared := -1
	for i in mini(la.size(), lb.size()):
		if la[i].id != lb[i].id:
			break
		shared = la[i].rank
	return shared


## Alle Taxa eines Rangs, optional nur unterhalb von `under_id` (inklusive).
func taxa_of_rank(rank: int, under_id := "") -> Array[Taxon]:
	var out: Array[Taxon] = []
	var start: Array = [under_id] if under_id != "" else Array(root_ids)
	while not start.is_empty():
		var t: Taxon = taxa[start.pop_front()]
		if t.rank == rank:
			out.append(t)
		elif t.rank < rank:
			start.append_array(Array(t.children))
	return out


func species(under_id := "") -> Array[Taxon]:
	return taxa_of_rank(Ranks.SPECIES, under_id)


## Verschachtelte JSON-Form, kompatibel mit TaxonomyLoader.
func to_dict() -> Dictionary:
	var list := []
	for rid in root_ids:
		list.append(_taxon_tree_dict(rid))
	var d := {"format": FORMAT, "name": name, "seed": base_seed, "similarity": settings.to_dict(), "taxa": list}
	if notes != "":
		d["notes"] = notes
	return d


func _taxon_tree_dict(id: String) -> Dictionary:
	var t: Taxon = taxa[id]
	var d := t.to_dict(schema)
	if not t.children.is_empty():
		var kids := []
		for cid in t.children:
			kids.append(_taxon_tree_dict(cid))
		d["children"] = kids
	return d
