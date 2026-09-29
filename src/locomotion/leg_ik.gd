class_name LegIK
extends RefCounted
## Analytische 2-Knochen-IK (Oberschenkel + Unterschenkel).
##
## Das Knie liegt auf dem Kreis, der sich aus den beiden Knochenlängen ergibt;
## `pole` legt fest, in welche Richtung es ausweicht. Ist das Ziel außer
## Reichweite, wird das Bein gestreckt und der Fuß auf die maximale Länge begrenzt.


## Liefert {"knee": Vector3, "foot": Vector3}.
static func solve(hip: Vector3, target: Vector3, upper: float, lower: float, pole: Vector3) -> Dictionary:
	var to_target := target - hip
	var dist := to_target.length()
	var reach := upper + lower
	if dist < 0.00001:
		return {"knee": hip + pole.normalized() * upper, "foot": target}
	var dir := to_target / dist
	# Mindestabstand, damit das Dreieck nicht entartet
	var min_dist := absf(upper - lower) + 0.0001
	var d := clampf(dist, min_dist, reach * 0.9999)
	var foot := hip + dir * d
	# Kosinussatz: Abstand des Knies entlang dir und senkrecht dazu
	var a := (upper * upper - lower * lower + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, upper * upper - a * a))
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 0.000001:
		bend = dir.cross(Vector3.RIGHT)
		if bend.length_squared() < 0.000001:
			bend = dir.cross(Vector3.FORWARD)
	bend = bend.normalized()
	return {"knee": hip + dir * a + bend * h, "foot": foot}


## Basis für einen Knochen, der in Ruhe entlang -Y zeigt und nun von `from` nach `to` zeigen soll.
static func bone_basis(from: Vector3, to: Vector3) -> Basis:
	var y := (from - to).normalized()
	if y.length_squared() < 0.5:
		return Basis.IDENTITY
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
