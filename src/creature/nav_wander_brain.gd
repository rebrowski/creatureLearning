class_name NavWanderBrain
extends RefCounted
## Platzhalter-Verhalten bis M4: läuft über das Navmesh zu zufälligen Zielen
## in einem Umkreis, bleibt dazwischen stehen und hält Abstand zu Nachbarn.

const ARRIVE_DISTANCE := 0.6
const SEPARATION_RADIUS := 1.4

var creature: Creature
var navigation: ForestNavigation
var home := Vector3.ZERO
var roam_radius := 14.0
## Alle Kreaturen der Szene (für Abstand halten), wird geteilt.
var others: Array[Creature] = []

var _path := PackedVector3Array()
var _index := 0
var _idle := 0.0
var _repath := 0.0
var _rng := RandomNumberGenerator.new()


func _init(p_creature: Creature, p_navigation: ForestNavigation, p_home: Vector3, seed_value: int) -> void:
	creature = p_creature
	navigation = p_navigation
	home = p_home
	_rng.seed = seed_value
	_idle = _rng.randf_range(0.0, 2.0)


func update(delta: float) -> void:
	if not navigation.is_baked:
		creature.desired_velocity = Vector3.ZERO
		return
	if _idle > 0.0:
		_idle -= delta
		creature.desired_velocity = _separation() * 0.5
		return
	if _index >= _path.size():
		_new_target()
		return
	_repath -= delta
	var pos := creature.global_position
	var wp := _path[_index]
	var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	if to.length() < ARRIVE_DISTANCE:
		_index += 1
		if _index >= _path.size():
			_idle = _rng.randf_range(1.0, 5.0)
		return
	var speed := creature.plan.move_speed * (0.6 if _index == _path.size() - 1 and to.length() < 1.5 else 1.0)
	creature.desired_velocity = to.normalized() * speed + _separation()
	# steckengeblieben? neu planen
	if _repath <= 0.0:
		_repath = 3.0
		if creature.velocity.length() < 0.05:
			_new_target()


func _new_target() -> void:
	var map := navigation.map()
	var a := _rng.randf_range(0.0, TAU)
	var r := sqrt(_rng.randf()) * roam_radius
	var goal := NavigationServer3D.map_get_closest_point(map, home + Vector3(cos(a) * r, 0.0, sin(a) * r))
	_path = NavigationServer3D.map_get_path(map, creature.global_position, goal, true)
	_index = 1 if _path.size() > 1 else _path.size()
	_repath = 3.0


func _separation() -> Vector3:
	var push := Vector3.ZERO
	var pos := creature.global_position
	for o in others:
		if o == creature or not is_instance_valid(o):
			continue
		var d := Vector3(pos.x - o.global_position.x, 0.0, pos.z - o.global_position.z)
		var dist := d.length()
		if dist > 0.001 and dist < SEPARATION_RADIUS:
			push += d / dist * (SEPARATION_RADIUS - dist)
	return push
