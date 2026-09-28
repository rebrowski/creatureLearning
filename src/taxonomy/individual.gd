class_name Individual
extends RefCounted
## Eine konkrete Kreatur: Art, laufende Nummer, Geschlecht, Alter, Genom.

var id: String = ""
var species_id: String = ""
var index: int = 0
## "female" oder "male"
var sex: String = "female"
## "adult" oder "juvenile"
var age: String = "adult"
var genome: Genome


func sex_symbol() -> String:
	return "♂" if sex == "male" else "♀"


func short_label() -> String:
	return "#%d %s%s" % [index, sex_symbol(), " juv." if age == "juvenile" else ""]
