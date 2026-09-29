class_name BodyPlan
extends RefCounted
## Aus dem Genom abgeleitete Geometrie einer Kreatur – die gemeinsame Grundlage
## für Mesh-Builder, Skelett und Locomotion.
##
## Koordinaten (Meter) im Kreatur-Raum: Ursprung auf dem Boden unter der
## Körpermitte, vorne = -Z, rechts = +X, oben = +Y.
## Beine sind paarweise von vorne nach hinten nummeriert:
##   Index = Paar * 2 + Seite (0 = links, 1 = rechts).

const SHAPES := {
	# Querschnitt: [Faktor seitliche Halbachse, Faktor vertikale Halbachse] relativ zu body_width/2
	"round": [1.0, 1.0],
	"elongated": [0.85, 0.65],
	"flat": [1.25, 0.42],
}

var genome: Genome
var gait: String = "walk"
var segment_count: int = 1
var leg_count: int = 0
## Rumpflänge und Halbachsen des Querschnitts.
var body_length: float = 1.0
var half_width: float = 0.25
var half_height: float = 0.25
## Höhe der Körpermitte über dem Boden in Ruhe.
var body_center_y: float = 0.25
## Höhe der Hüftgelenke über dem Boden in Ruhe.
var hip_height: float = 0.0
var upper_leg: float = 0.0
var lower_leg: float = 0.0
var leg_radius: float = 0.03
var head_radius: float = 0.15
var head_center: Vector3
var tail_length: float = 0.0
var horn_count: int = 0
var horn_length: float = 0.0
var crest_height: float = 0.0
var antenna_length: float = 0.0
## Mittelpunkte der Segmente (z) und ihre halbe Länge.
var segment_z: PackedFloat32Array = []
var segment_half_length: float = 0.5
## Pro Bein: Hüfte (relativ zur Körpermitte), Fußruhepunkt (Kreatur-Raum, y = 0),
## Kniebeuge-Richtung (Kreatur-Raum).
var hips: PackedVector3Array = []
var foot_homes: PackedVector3Array = []
var knee_poles: PackedVector3Array = []
## Grundtempo in m/s und Schrittlänge in m.
var move_speed: float = 1.0
var stride_length: float = 0.5


static func from_genome(g: Genome) -> BodyPlan:
	var p := BodyPlan.new()
	p.genome = g
	p.gait = g.option("gait")
	p.segment_count = maxi(1, g.i("segment_count"))
	p.leg_count = g.i("leg_count")
	p.body_length = g.f("body_length")
	var shape: Array = SHAPES.get(g.option("body_shape"), SHAPES.round)
	p.half_width = g.f("body_width") * 0.5 * shape[0]
	p.half_height = g.f("body_width") * 0.5 * shape[1]

	var leg_len := float(g.effective("leg_length")) if p.leg_count > 0 else 0.0
	p.upper_leg = leg_len * 0.55
	p.lower_leg = leg_len * 0.55
	p.leg_radius = maxf(0.01, float(g.effective("leg_thickness")) * 0.5)
	if p.leg_count > 0:
		# gespreizte Beine (Krabbler, Sechs-/Achtbeiner) tragen den Körper tiefer
		var sprawl := p.gait == "scuttle" or p.leg_count >= 6
		p.hip_height = leg_len * ((0.3 + 0.35 * g.f("posture")) if sprawl else (0.45 + 0.45 * g.f("posture")))
		p.body_center_y = p.hip_height + p.half_height * 0.6
	else:
		p.hip_height = 0.0
		p.body_center_y = p.half_height

	p.segment_half_length = p.body_length * 0.5 / p.segment_count
	for i in p.segment_count:
		# Segment 0 ist vorne.
		p.segment_z.append(-p.body_length * 0.5 + (i + 0.5) * p.body_length / p.segment_count)

	p.head_radius = g.f("head_size") * 0.5
	p.head_center = Vector3(0.0, p.half_height * 0.3 + p.head_radius * 0.2, -(p.body_length * 0.5 + p.head_radius * 0.7))
	p.tail_length = g.f("tail_length")
	p.horn_count = g.i("horn_count")
	p.horn_length = float(g.effective("horn_length"))
	p.crest_height = g.f("crest_height")
	p.antenna_length = g.f("antenna_length")

	p._layout_legs(leg_len)
	var size_factor := clampf(leg_len + p.body_length * 0.3, 0.3, 2.0)
	p.move_speed = g.f("speed") * size_factor * 0.9
	p.stride_length = maxf(0.15, leg_len * 0.7) if p.leg_count > 0 else maxf(0.2, p.body_length * 0.4)
	return p


func _layout_legs(leg_len: float) -> void:
	var pairs := leg_count / 2
	var sprawl := gait == "scuttle" or leg_count >= 6
	var splay := leg_len * (0.6 if sprawl else 0.12)
	for k in pairs:
		# t = +1 vorne, -1 hinten
		var t := 0.0 if pairs == 1 else lerpf(0.7, -0.7, float(k) / (pairs - 1))
		for side in 2:
			var s := -1.0 if side == 0 else 1.0
			var hip := Vector3(s * half_width * 0.8, -half_height * 0.6, -t * body_length * 0.5)
			hips.append(hip)
			var home := Vector3(s * (half_width * 0.8 + splay), 0.0, hip.z - t * leg_len * 0.2)
			foot_homes.append(home)
			var pole: Vector3
			if sprawl:
				pole = Vector3(s, 1.0, 0.0).normalized()  # Spinnenknie: nach oben/außen
			elif t >= 0.0:
				pole = Vector3(0.0, 0.2, -1.0).normalized()  # Vorderbeine: Knie nach vorn
			else:
				pole = Vector3(0.0, 0.2, 1.0).normalized()  # Hinterbeine: Ferse nach hinten
			knee_poles.append(pole)


func leg_reach() -> float:
	return upper_leg + lower_leg


## Hüfte im Kreatur-Raum in Ruhehaltung.
func hip_rest(leg: int) -> Vector3:
	return hips[leg] + Vector3(0.0, body_center_y, 0.0)


func pair_of(leg: int) -> int:
	return leg / 2


func side_of(leg: int) -> int:
	return leg % 2
