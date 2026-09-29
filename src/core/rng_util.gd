class_name RngUtil
extends RefCounted
## Reproduzierbare Zufallszahlen.
##
## Jeder Zufallswert im Projekt wird aus einem Seed abgeleitet, der aus
## sprechenden Bestandteilen zusammengesetzt ist (z. B. Welt-Seed, Taxon-ID,
## Gen-ID). Dadurch ändert das Hinzufügen neuer Gene oder Taxa die bereits
## existierenden Werte nicht.


## Baut aus beliebigen Werten (ints, Strings, ...) einen stabilen 32-bit-Seed.
static func derive_seed(parts: Array) -> int:
	var key := ""
	for part in parts:
		key += str(part) + "\u001f"
	return key.hash()


## Setzt einen vorhandenen Generator auf den aus `parts` abgeleiteten Seed zurück.
static func reseed(rng: RandomNumberGenerator, parts: Array) -> void:
	rng.seed = derive_seed(parts)


static func make_rng(parts: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	reseed(rng, parts)
	return rng


## Gleichverteilter Wert aus einem Bereich [a, b], angegeben als Array.
static func range_f(rng: RandomNumberGenerator, bounds: Array) -> float:
	return rng.randf_range(float(bounds[0]), float(bounds[1]))


## Ganzzahl aus einem Bereich [a, b] (inklusive), angegeben als Array.
static func range_i(rng: RandomNumberGenerator, bounds: Array) -> int:
	return rng.randi_range(int(bounds[0]), int(bounds[1]))


static func pick(rng: RandomNumberGenerator, items: Array) -> Variant:
	return items[rng.randi_range(0, items.size() - 1)] if not items.is_empty() else null


## Fisher-Yates in place.
static func shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
