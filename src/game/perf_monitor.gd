class_name PerfMonitor
extends RefCounted
## Misst Frame-Zeiten (Echtzeit) über die letzten Sekunden für die Leistungsanzeige.

const WINDOW := 180  # Frames

var _samples := PackedFloat32Array()
var _last_usec := 0


func tick() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_samples.append((now - _last_usec) / 1000.0)
		if _samples.size() > WINDOW:
			_samples.remove_at(0)
	_last_usec = now


## {avg, p95, max} in Millisekunden
func stats() -> Dictionary:
	if _samples.is_empty():
		return {"avg": 0.0, "p95": 0.0, "max": 0.0}
	var sorted := _samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in sorted:
		total += s
	return {"avg": total / sorted.size(), "p95": sorted[int(sorted.size() * 0.95)], "max": sorted[-1]}


static func lod_counts(creatures: Array) -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0]
	for c in creatures:
		counts[c.lod_level] += 1
	return counts
