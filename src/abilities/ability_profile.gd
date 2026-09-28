class_name AbilityProfile
extends RefCounted
## Fähigkeiten einer Kreatur (Grundwerte gecacht, Kontextwerte auf Abfrage).

var catalog: AbilityCatalog
var genome: Genome
var base: Dictionary = {}


func _init(p_catalog: AbilityCatalog, p_genome: Genome) -> void:
	catalog = p_catalog
	genome = p_genome
	for id in catalog.order:
		base[id] = catalog.base_value(id, genome)


func value(id: String) -> float:
	return base.get(id, 0.0)


func in_context(id: String, sample: Dictionary) -> float:
	return catalog.value_in(id, genome, sample)


## Beste Fähigkeiten, absteigend (für Debug-Anzeigen).
func ranked() -> Array:
	var out := []
	for id in catalog.order:
		out.append([id, base[id]])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out
