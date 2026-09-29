class_name GroupMember
extends RefCounted
## Ein Mitglied der Spielergruppe. Das Genom wird im Spielstand gespeichert
## (nicht nur Art + Nummer), damit sich Kreaturen nie verändern, auch wenn sich
## später der Erzeugungscode ändert.

var id := ""          # "art#nummer", stabil
var name := ""        # Anzeigename im Spiel (die Art sieht der Spieler nicht)
var species_id := ""
var index := 0
var sex := "female"
var age := "adult"
var genome: Genome
var morphs: Dictionary = {}
## Anzahl gelöster Aufgaben, als das Mitglied dazukam (0 = Startgruppe).
var joined_after := 0
## Preis zum Anheuern (nur bei Fremden, sonst 0).
var price := 0
## Nach einer gescheiterten Aufgabe bis zum nächsten Morgen nicht einsetzbar.
var exhausted := false


static func from_individual(ind: Individual, display_name: String, joined := 0) -> GroupMember:
	var m := GroupMember.new()
	m.id = ind.id
	m.name = display_name
	m.species_id = ind.species_id
	m.index = ind.index
	m.sex = ind.sex
	m.age = ind.age
	m.genome = ind.genome
	m.morphs = ind.morphs.duplicate()
	m.joined_after = joined
	return m


func to_individual() -> Individual:
	var ind := Individual.new()
	ind.id = id
	ind.species_id = species_id
	ind.index = index
	ind.sex = sex
	ind.age = age
	ind.genome = genome
	ind.morphs = morphs.duplicate()
	return ind


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "species": species_id, "index": index, "sex": sex, "age": age,
			"morphs": morphs, "joined_after": joined_after, "price": price, "exhausted": exhausted, "genome": genome.to_dict()}


static func from_dict(schema: GenomeSchema, d: Dictionary) -> GroupMember:
	var m := GroupMember.new()
	m.id = str(d.get("id", ""))
	m.name = str(d.get("name", m.id))
	m.species_id = str(d.get("species", ""))
	m.index = int(d.get("index", 0))
	m.sex = str(d.get("sex", "female"))
	m.age = str(d.get("age", "adult"))
	m.morphs = d.get("morphs", {})
	m.joined_after = int(d.get("joined_after", 0))
	m.price = int(d.get("price", 0))
	m.exhausted = bool(d.get("exhausted", false))
	m.genome = Genome.from_dict(schema, d.get("genome", {}))
	return m
