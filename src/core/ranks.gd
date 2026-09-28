class_name Ranks
extends RefCounted
## Taxonomische Ränge von grob nach fein.
##
## INDIVIDUAL ist kein Taxon, sondern der letzte Variationsschritt pro Kreatur.
## Ränge werden überall als int verglichen: kleiner = gröber.

enum { CLASS, ORDER, FAMILY, GENUS, SPECIES, INDIVIDUAL }

const NAMES: PackedStringArray = ["class", "order", "family", "genus", "species", "individual"]
const LABELS_DE: PackedStringArray = ["Klasse", "Ordnung", "Familie", "Gattung", "Art", "Individuum"]

## Anzahl echter Taxon-Ränge (ohne INDIVIDUAL).
const TAXON_RANK_COUNT := 5


## Liefert den Rang zu einem Namen wie "family" oder -1, wenn unbekannt.
static func from_name(rank_name: String) -> int:
	return NAMES.find(rank_name)


static func name_of(rank: int) -> String:
	return NAMES[rank] if rank >= 0 and rank < NAMES.size() else "?"


static func label_of(rank: int) -> String:
	return LABELS_DE[rank] if rank >= 0 and rank < LABELS_DE.size() else "?"
