class_name NavMover
extends RefCounted
## Läuft über das Navmesh zu einem Ziel und hält Abstand zu Nachbarn:
## Entgegenkommenden weicht die Kreatur nach rechts aus (kommt ihr jemand
## direkt entgegen, wartet eine der beiden kurz, Vorrang nach ID). Stehende
## Kreaturen und solche mit weniger Vorrang (Creature.priority) werden nicht
## umgangen, sondern beiseitegestupst – das erledigt die Welt beim Auflösen
## von Überlappungen (ForestWorld._separate).

const ARRIVE_DISTANCE := 0.6
## Zusätzlicher Abstand zwischen den Grundflächen zweier Kreaturen.
const SEPARATION_MARGIN := 0.4
## So weit voraus (Meter, plus Radien) wird auf Entgegenkommende geachtet.
const LOOK_AHEAD := 2.0
const YIELD_TIME := 0.8
## Langsamer gilt eine Kreatur als stehend (m/s).
const STILL_SPEED := 0.05

var creature: Creature
var navigation: ForestNavigation
## Alle Kreaturen (geteilt), für Abstand halten.
var others: Array[Creature] = []
var goal := Vector3.ZERO

var _path := PackedVector3Array()
var _index := 0
var _stuck := 0.0
var _wait := 0.0


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
	_wait = 0.0
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
	if _wait > 0.0:
		_wait -= delta
		creature.desired_velocity = separation()
		return false
	var dir := to.normalized()
	var avoid := avoidance(dir)
	if avoid.is_empty():
		creature.desired_velocity = dir * speed + separation()
	elif avoid.yield:
		_wait = YIELD_TIME
		creature.desired_velocity = separation()
		return false
	else:
		creature.desired_velocity = (dir + avoid.side).normalized() * speed * avoid.slow + separation()
	_stuck = _stuck + delta if creature.velocity.length() < 0.03 and _wait <= 0.0 else 0.0
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
		if o == creature or not is_instance_valid(o) or o.scripted or yields_to_me(o):
			continue
		var d := Vector3(pos.x - o.global_position.x, 0.0, pos.z - o.global_position.z)
		var dist := d.length()
		var r := creature.radius + o.radius + SEPARATION_MARGIN
		if dist > 0.001 and dist < r:
			push += d / dist * (r - dist)
	return push


## Wird beiseitegestupst statt umgangen: weniger Vorrang, oder steht nur herum.
func yields_to_me(o: Creature) -> bool:
	if o.scripted:
		return false
	return o.priority < creature.priority or (o.priority == creature.priority and o.velocity.length() < STILL_SPEED)


## Nachbar voraus? {} = frei; sonst {"side": Ausweichrichtung, "slow": Faktor,
## "yield": true = kurz warten und dem anderen den Vortritt lassen}.
func avoidance(dir: Vector3) -> Dictionary:
	var pos := creature.global_position
	var best: Creature = null
	var best_ahead := INF
	for o in others:
		if o == creature or not is_instance_valid(o) or not o.visible or yields_to_me(o):
			continue
		var d := Vector3(o.global_position.x - pos.x, 0.0, o.global_position.z - pos.z)
		var ahead := d.dot(dir)
		if ahead <= 0.0:
			continue
		var lateral := absf(d.cross(dir).y)
		var r := creature.radius + o.radius + SEPARATION_MARGIN
		if ahead < LOOK_AHEAD + r and lateral < r and ahead < best_ahead:
			best = o
			best_ahead = ahead
	if best == null:
		return {}
	var r2 := creature.radius + best.radius + SEPARATION_MARGIN
	var oncoming := best.velocity.length() > 0.05 and best.velocity.normalized().dot(dir) < -0.5
	# Wer die höhere ID hat, wartet – so bleiben nie beide stehen
	if oncoming and best_ahead < r2 + 0.5 and creature.get_instance_id() > best.get_instance_id():
		return {"yield": true}
	# rechts vorbei (von oben gesehen: dir × UP zeigt nach rechts)
	var right := dir.cross(Vector3.UP).normalized()
	var strength := clampf(1.0 - (best_ahead - r2) / LOOK_AHEAD, 0.2, 1.0)
	# Stehenden umgeht man zügig, bei Entgegenkommenden etwas langsamer
	var slow := lerpf(1.0, 0.6, strength) if best.velocity.length() > 0.05 else 1.0
	return {"yield": false, "side": right * strength * 1.5, "slow": slow}
