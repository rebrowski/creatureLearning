class_name SimilaritySettings
extends Resource
## Globale Regler für die visuelle Ähnlichkeit.
##
## Die zufällige Abweichung eines Gens auf Rang r ist normalverteilt mit
##   sigma = base_variance[r] * spread[r] * gene.variance_scale   (Bruchteil des Wertebereichs)
## `spread` sind die eigentlichen Regler: 0 = keine Abweichung auf diesem Rang,
## 1 = Standard, 2 = doppelt so stark. Beispiel: species_spread steuert, wie stark
## sich Arten derselben Gattung unterscheiden, individual_spread die Streuung
## innerhalb einer Art.

## Standard-Streuung pro Rang (Klasse .. Individuum), Bruchteil des Wertebereichs.
@export var base_variance: PackedFloat32Array = [0.2, 0.12, 0.08, 0.06, 0.04, 0.03]
## Regler pro Rang (Klasse .. Individuum).
@export var spread: PackedFloat32Array = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
## 0 = Männchen/Weibchen/Jungtiere sehen gleich aus, 1 = wie definiert.
@export_range(0.0, 2.0) var dimorphism_strength: float = 1.0
## 0 = konvergente Arten ähneln ihrem Vorbild nicht, 1 = wie definiert.
@export_range(0.0, 1.0) var convergence_strength: float = 1.0
## ENUM-Gene: Wechselwahrscheinlichkeit = sigma * enum_switch_factor.
@export var enum_switch_factor: float = 2.0


func sigma(rank: int) -> float:
	return base_variance[rank] * spread[rank]


func get_spread(rank: int) -> float:
	return spread[rank]


func set_spread(rank: int, value: float) -> void:
	spread[rank] = maxf(0.0, value)


func copy() -> SimilaritySettings:
	var s := SimilaritySettings.new()
	s.base_variance = base_variance.duplicate()
	s.spread = spread.duplicate()
	s.dimorphism_strength = dimorphism_strength
	s.convergence_strength = convergence_strength
	s.enum_switch_factor = enum_switch_factor
	return s


## Übernimmt Werte aus JSON. Nicht genannte Werte bleiben unverändert.
## Format: {"spread": {"species": 1.0, ...}, "base_variance": {...},
##          "dimorphism_strength": 1.0, "convergence_strength": 1.0, "enum_switch_factor": 2.0}
func apply_dict(d: Dictionary, errors: PackedStringArray, ctx := "similarity") -> void:
	for key in ["spread", "base_variance"]:
		if not d.has(key):
			continue
		if not d[key] is Dictionary:
			errors.append("%s.%s muss ein Objekt {rang: wert} sein" % [ctx, key])
			continue
		var target: PackedFloat32Array = spread if key == "spread" else base_variance
		for rank_name in d[key]:
			var r := Ranks.from_name(rank_name)
			if r < 0:
				errors.append("%s.%s: unbekannter Rang '%s'" % [ctx, key, rank_name])
				continue
			target[r] = maxf(0.0, float(d[key][rank_name]))
	for key in ["dimorphism_strength", "convergence_strength", "enum_switch_factor"]:
		if d.has(key):
			set(key, maxf(0.0, float(d[key])))


func to_dict() -> Dictionary:
	var sp := {}
	var bv := {}
	for r in Ranks.NAMES.size():
		sp[Ranks.NAMES[r]] = spread[r]
		bv[Ranks.NAMES[r]] = base_variance[r]
	return {
		"spread": sp,
		"base_variance": bv,
		"dimorphism_strength": dimorphism_strength,
		"convergence_strength": convergence_strength,
		"enum_switch_factor": enum_switch_factor,
	}
