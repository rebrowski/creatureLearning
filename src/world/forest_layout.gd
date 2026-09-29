class_name ForestLayout
extends RefCounted
## Layout der Waldwelt aus data/world/forest.json: Geländehöhe und Zonen an
## jeder Position. Reine Logik ohne Nodes – genutzt von Gelände-Builder,
## Vegetationsverteilung, WorldContext und Tests.
##
## Koordinaten in Metern, (0,0) = Weltmitte, Ebene x/z, Höhe y.

const FORMAT := "forest_layout/1"
const DEFAULT_PATH := "res://data/world/forest.json"

## Zonen, von höchster zu niedrigster Priorität.
const ZONES: PackedStringArray = ["water", "bank", "rock", "tree", "clearing", "forest", "outside"]

var name := ""
var seed_value := 0
var size := Vector2(64, 64)
var noise_amplitude := 0.5
var noise_scale := 0.07
## [{pos: Vector2, radius, height}]
var hills: Array[Dictionary] = []
var stream_points: PackedVector2Array = []
var stream_width := 3.0
var stream_depth := 0.9
var stream_bank := 2.0
var clearing_pos := Vector2.ZERO
var clearing_radius := 0.0
var clearing_flatten := 0.8
## [{pos: Vector2, size, climbable}]
var rocks: Array[Dictionary] = []
## [{pos: Vector2, height, fruits, fruit_height}]
var fruit_trees: Array[Dictionary] = []
var spawn_pos := Vector2.ZERO
var spawn_radius := 5.0
## Vegetationsregeln wie in JSON (siehe VegetationScatter).
var vegetation: Array = []
var errors: PackedStringArray = []

var _noise := FastNoiseLite.new()
var _clearing_base := 0.0


static func load_file(path: String = DEFAULT_PATH) -> ForestLayout:
	var res := JsonLoader.read(path)
	var l := ForestLayout.new()
	if res.error != "":
		l.errors.append(res.error)
		return l
	l._parse(res.data, path)
	return l


static func from_dict(d: Variant) -> ForestLayout:
	var l := ForestLayout.new()
	l._parse(d, "<layout>")
	return l


func is_valid() -> bool:
	return errors.is_empty()


func _parse(d: Variant, src: String) -> void:
	if not d is Dictionary:
		errors.append("%s: Wurzel muss ein Objekt sein" % src)
		return
	name = str(d.get("name", ""))
	seed_value = int(d.get("seed", 0))
	size = _vec2(d.get("size", [64, 64]), src + ".size")
	var t: Dictionary = d.get("terrain", {})
	noise_amplitude = float(t.get("noise_amplitude", 0.5))
	noise_scale = float(t.get("noise_scale", 0.07))
	for i in t.get("hills", []).size():
		var h: Dictionary = t.hills[i]
		hills.append({"pos": _vec2(h.get("pos"), "%s.terrain.hills[%d].pos" % [src, i]),
				"radius": maxf(0.1, float(h.get("radius", 5.0))), "height": float(h.get("height", 1.0))})
	var s: Dictionary = d.get("stream", {})
	for i in s.get("points", []).size():
		stream_points.append(_vec2(s.points[i], "%s.stream.points[%d]" % [src, i]))
	if stream_points.size() == 1:
		errors.append("%s.stream.points: mindestens 2 Punkte oder gar keine" % src)
	stream_width = float(s.get("width", 3.0))
	stream_depth = float(s.get("depth", 0.9))
	stream_bank = float(s.get("bank", 2.0))
	if d.has("clearing"):
		clearing_pos = _vec2(d.clearing.get("pos"), src + ".clearing.pos")
		clearing_radius = float(d.clearing.get("radius", 6.0))
		clearing_flatten = clampf(float(d.clearing.get("flatten", 0.8)), 0.0, 1.0)
	for i in d.get("rocks", []).size():
		var r: Dictionary = d.rocks[i]
		rocks.append({"pos": _vec2(r.get("pos"), "%s.rocks[%d].pos" % [src, i]),
				"size": maxf(0.2, float(r.get("size", 1.0))), "climbable": bool(r.get("climbable", false))})
	for i in d.get("fruit_trees", []).size():
		var f: Dictionary = d.fruit_trees[i]
		var height := float(f.get("height", 6.0))
		fruit_trees.append({"pos": _vec2(f.get("pos"), "%s.fruit_trees[%d].pos" % [src, i]),
				"height": height, "fruits": int(f.get("fruits", 3)),
				"fruit_height": clampf(float(f.get("fruit_height", height * 0.7)), 0.5, height)})
	if d.has("spawn"):
		spawn_pos = _vec2(d.spawn.get("pos"), src + ".spawn.pos")
		spawn_radius = float(d.spawn.get("radius", 5.0))
	vegetation = d.get("vegetation", [])
	for i in vegetation.size():
		for z in vegetation[i].get("zones", []):
			if not ZONES.has(z):
				errors.append("%s.vegetation[%d]: unbekannte Zone '%s' (erlaubt: %s)" % [src, i, z, ", ".join(ZONES)])

	_noise.seed = seed_value
	_noise.frequency = noise_scale
	_noise.fractal_octaves = 3
	_clearing_base = _base_height(clearing_pos.x, clearing_pos.y)


func _vec2(v: Variant, ctx: String) -> Vector2:
	if v is Array and v.size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	errors.append("%s: erwartet [x, z]" % ctx)
	return Vector2.ZERO


# --- Abfragen -----------------------------------------------------------------

func half_size() -> Vector2:
	return size * 0.5


func contains(x: float, z: float) -> bool:
	return absf(x) <= size.x * 0.5 and absf(z) <= size.y * 0.5


## Geländehöhe (Boden, bei Wasser der Grund des Bachs).
func height_at(x: float, z: float) -> float:
	var h := _land_height(x, z)
	if stream_points.size() >= 2:
		var info := stream_info(x, z)
		var reach := stream_width * 0.5 + stream_bank
		if info.distance < reach:
			var base := _land_height(info.closest.x, info.closest.y)
			var profile := 1.0 - smoothstep(0.0, reach, info.distance)
			h = lerpf(h, base, profile) - stream_depth * profile
	return h


## Höhe der Wasseroberfläche am nächsten Punkt des Bachs (NAN ohne Bach).
func water_level_at(x: float, z: float) -> float:
	if stream_points.size() < 2:
		return NAN
	var info := stream_info(x, z)
	return _land_height(info.closest.x, info.closest.y) - stream_depth * 0.35


## Abstand zum Bach-Mittellauf und nächster Punkt darauf.
func stream_info(x: float, z: float) -> Dictionary:
	var p := Vector2(x, z)
	var best := INF
	var closest := Vector2.ZERO
	for i in stream_points.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, stream_points[i], stream_points[i + 1])
		var d := p.distance_to(q)
		if d < best:
			best = d
			closest = q
	return {"distance": best, "closest": closest}


## Fließrichtung des Bachs am nächsten Abschnitt (Reihenfolge der Punkte), normiert.
func stream_direction(x: float, z: float) -> Vector2:
	var p := Vector2(x, z)
	var best := INF
	var dir := Vector2(1, 0)
	for i in stream_points.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, stream_points[i], stream_points[i + 1])
		var d := p.distance_to(q)
		if d < best:
			best = d
			dir = (stream_points[i + 1] - stream_points[i]).normalized()
	return dir


func zone_at(x: float, z: float) -> String:
	if not contains(x, z):
		return "outside"
	if stream_points.size() >= 2:
		var d: float = stream_info(x, z).distance
		if d < stream_width * 0.5:
			return "water"
		if d < stream_width * 0.5 + stream_bank:
			return "bank"
	var p := Vector2(x, z)
	for r in rocks:
		if p.distance_to(r.pos) < r.size * 0.9:
			return "rock"
	for t in fruit_trees:
		if p.distance_to(t.pos) < 1.5:
			return "tree"
	if clearing_radius > 0.0 and p.distance_to(clearing_pos) < clearing_radius:
		return "clearing"
	return "forest"


## Nächster Fels innerhalb `max_distance` oder leeres Dictionary.
func nearest_rock(x: float, z: float, max_distance := INF) -> Dictionary:
	var p := Vector2(x, z)
	var best := {}
	var best_d := max_distance
	for r in rocks:
		var d: float = p.distance_to(r.pos) - r.size
		if d < best_d:
			best_d = d
			best = r
	return best


# --- intern -------------------------------------------------------------------

func _base_height(x: float, z: float) -> float:
	var h := noise_amplitude * _noise.get_noise_2d(x, z)
	for hill in hills:
		var d: float = Vector2(x, z).distance_to(hill.pos) / hill.radius
		if d < 1.0:
			var f := 1.0 - d * d
			h += hill.height * f * f
	return h


func _land_height(x: float, z: float) -> float:
	var h := _base_height(x, z)
	if clearing_radius > 0.0:
		var d := Vector2(x, z).distance_to(clearing_pos)
		var f := clearing_flatten * (1.0 - smoothstep(clearing_radius * 0.6, clearing_radius * 1.2, d))
		h = lerpf(h, _clearing_base, f)
	return h
