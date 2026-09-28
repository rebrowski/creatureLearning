class_name NavMover
extends RefCounted
## Läuft über das Navmesh zu einem Ziel und hält Abstand zu Nachbarn.

const ARRIVE_DISTANCE := 0.6
const SEPARATION_RADIUS := 1.4

var creature: Creature
var navigation: ForestNavigation
## Alle Kreaturen (geteilt), für Abstand halten.
var others: Array[Creature] = []
var goal := Vector3.ZERO

var _path := PackedVector3Array()
var _index := 0
var _stuck := 0.0


func _init(p_creature: Creature, p_navigation: ForestNavigation) -> void:
	creature = p_creature
	navigation = p_navigation


## Erst nach der ersten Synchronisation der Navigationskarte liefern Abfragen Wege.
func ready() -> bool:
	return navigation != null and navigation.is_baked and NavigationServer3D.map_get_iteration_id(navigation.map()) > 0


## Neues Ziel (wird auf das Navmesh gezogen). Liefert den erreichbaren Zielpunkt.
func go(target: Vector3) -> Vector3:
	var map := navigation.map()
	goal = NavigationServer3D.map_get_closest_point(map, target)
	_path = NavigationServer3D.map_get_path(map, creature.global_position, goal, true)
	_index = 1 if _path.size() > 1 else _path.size()
	_stuck = 0.0
	return goal


## Ein Schritt; true = angekommen (oder kein Weg).
func step(delta: float, speed_factor := 1.0) -> bool:
	if _index >= _path.size():
		creature.desired_velocity = separation() * 0.5
		return true
	var pos := creature.global_position
	var wp := _path[_index]
	var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	if to.length() < ARRIVE_DISTANCE:
		_index += 1
		return _index >= _path.size()
	var last := _index == _path.size() - 1
	var speed := creature.plan.move_speed * speed_factor * (0.6 if last and to.length() < 1.5 else 1.0)
	creature.desired_velocity = to.normalized() * speed + separation()
	_stuck = _stuck + delta if creature.velocity.length() < 0.03 else 0.0
	if _stuck > 3.0:
		_index = _path.size()  # aufgeben, Verhalten entscheidet neu
		return true
	return false


func distance_to_goal() -> float:
	var p := creature.global_position
	return Vector2(p.x - goal.x, p.z - goal.z).length()


func stop() -> void:
	_path = PackedVector3Array()
	_index = 0
	creature.desired_velocity = Vector3.ZERO


func separation() -> Vector3:
	var push := Vector3.ZERO
	var pos := creature.global_position
	for o in others:
		if o == creature or not is_instance_valid(o) or o.scripted:
			continue
		var d := Vector3(pos.x - o.global_position.x, 0.0, pos.z - o.global_position.z)
		var dist := d.length()
		if dist > 0.001 and dist < SEPARATION_RADIUS:
			push += d / dist * (SEPARATION_RADIUS - dist)
	return push
