class_name WorldContext
extends Node
## Zentrale Kontextabfrage für Fähigkeiten und Verhalten (ab M4):
## Zone/Gelände, Tageszeit, Licht, Wetter an einer Position.
##
## Findbar über die Gruppe "world_context" (WorldContext.find(tree)).

@export var terrain: ForestTerrain
@export var day_night: DayNightCycle
@export var weather: Weather


func _ready() -> void:
	add_to_group("world_context")


static func find(tree: SceneTree) -> WorldContext:
	return tree.get_first_node_in_group("world_context") as WorldContext


func layout() -> ForestLayout:
	return terrain.layout if terrain != null else null


## Alles Wissenswerte über eine Position:
## {zone, height, water_level, in_water, near_rock, near_fruit_tree,
##  hour, phase, is_night, light, weather, rain, wetness}
func sample(pos: Vector3) -> Dictionary:
	var l := layout()
	var d := {}
	if l != null:
		d.zone = l.zone_at(pos.x, pos.z)
		d.height = l.height_at(pos.x, pos.z)
		d.water_level = l.water_level_at(pos.x, pos.z)
		d.in_water = d.zone == "water"
		d.near_rock = not l.nearest_rock(pos.x, pos.z, 1.5).is_empty()
		d.near_fruit_tree = _nearest_fruit_tree(pos, 3.0) != null
	if day_night != null:
		d.hour = day_night.hour
		d.phase = day_night.phase()
		d.is_night = day_night.is_night()
		d.light = day_night.light_level()
	if weather != null:
		d.weather = weather.state
		d.rain = weather.rain
		d.wetness = weather.wetness
	return d


func _nearest_fruit_tree(pos: Vector3, max_distance: float) -> FruitTree:
	if terrain == null:
		return null
	var best: FruitTree = null
	var best_d := max_distance
	for t in terrain.fruit_trees:
		var d := Vector2(pos.x - t.global_position.x, pos.z - t.global_position.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


func nearest_fruit_tree(pos: Vector3, max_distance := INF) -> FruitTree:
	return _nearest_fruit_tree(pos, max_distance)
