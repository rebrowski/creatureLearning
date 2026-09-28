class_name GaitTable
extends RefCounted
## Schrittmuster: Phasenversatz pro Bein und Anteil der Standphase ("duty").
##
## Phase 0..1 pro Zyklus; ein Bein schwingt, solange seine lokale Phase
## kleiner als (1 - duty) ist. Beine sind wie in BodyPlan nummeriert
## (Paar * 2 + Seite, Paar 0 = vorne).

const DUTY := {"walk": 0.65, "trot": 0.5, "hop": 0.35, "scuttle": 0.55, "slither": 0.7}
## Wie hoch der Fuß beim Schwingen angehoben wird (Anteil der Beinlänge).
const LIFT := {"walk": 0.18, "trot": 0.22, "hop": 0.3, "scuttle": 0.25, "slither": 0.12}


static func duty(gait: String) -> float:
	return DUTY.get(gait, 0.6)


static func lift(gait: String) -> float:
	return LIFT.get(gait, 0.2)


## Phasenversatz aller Beine.
static func offsets(leg_count: int, gait: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(leg_count)
	var pairs := leg_count / 2
	for leg in leg_count:
		var pair := leg / 2
		var side := leg % 2
		out[leg] = _offset(pairs, pair, side, gait)
	return out


static func _offset(pairs: int, pair: int, side: int, gait: String) -> float:
	match pairs:
		0:
			return 0.0
		1:
			# Zweibeiner: abwechselnd, beim Hüpfen gleichzeitig
			return 0.0 if gait == "hop" else side * 0.5
		2:
			match gait:
				"trot":
					return 0.5 * float((pair + side) % 2)  # diagonale Paare
				"hop":
					return 0.0 if pair == 0 else 0.15  # Sprung: vorne, dann hinten
				_:
					# Kreuzgang (walk): LV 0, RH 0.25, RV 0.5, LH 0.75
					var table := [[0.0, 0.5], [0.75, 0.25]]
					return table[pair][side]
		_:
			if gait == "slither" or (gait == "walk" and pairs >= 4):
				# Wellengang: Welle läuft von hinten nach vorne, Seiten gegenphasig
				return fposmod(float(pairs - 1 - pair) / pairs + side * 0.5, 1.0)
			if gait == "hop":
				return 0.0 if pair < pairs / 2 else 0.15
			# Tripod / alternierend: Nachbarn gegenphasig
			return 0.5 * float((pair + side) % 2)
