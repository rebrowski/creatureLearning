class_name CreatureLOD
extends RefCounted
## Detailstufen nach Kameradistanz.
##
##   FULL    volle IK, Fuß-Raycasts, jedes Physik-Frame
##   REDUCED IK jedes zweite Frame, Boden als Ebene (keine Raycasts)
##   FROZEN  Low-Poly-Mesh, Beine in letzter Haltung, nur Fortbewegung
##   HIDDEN  unsichtbar, nur Fortbewegung

enum { FULL, REDUCED, FROZEN, HIDDEN }

const NAMES: PackedStringArray = ["full", "reduced", "frozen", "hidden"]

## Distanzgrenzen in Metern (Übergang zur nächsten Stufe).
static var thresholds: PackedFloat32Array = [14.0, 32.0, 70.0]
## Hysterese, damit die Stufe an der Grenze nicht flackert.
const HYSTERESIS := 1.5


static func level_for(distance: float, current: int) -> int:
	var level := thresholds.size()
	for i in thresholds.size():
		if distance < thresholds[i]:
			level = i
			break
	# Beim Wechsel zu feinerer Stufe etwas näher kommen müssen
	if level < current and current - 1 < thresholds.size() and distance > thresholds[current - 1] - HYSTERESIS:
		return current
	return level
