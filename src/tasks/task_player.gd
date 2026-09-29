class_name TaskPlayer
extends Node
## Spielt eine Aufgabe mit den echten Kreaturen in der Welt ab.
##
## Das Ergebnis steht vorher fest (TaskSimulator); die Schritte zeigen es:
## jeder Schritt einer Rolle läuft mit deren Ergebnis als vorgegebenem Ausgang.
## Schritttypen (siehe docs/tasks_format.md):
##   climb_tree   Rolle klettert zum Ort (Fruchtbaum); on_success "drop_fruit" lässt eine Frucht fallen
##   pick_up      Rolle holt den Gegenstand (z. B. "task_fruit") und trägt ihn
##   cross_stream Rolle durchquert den Bach am Ort (schwimmt oder watet)
##   drop         Rolle legt den getragenen Gegenstand ab
##   walk_to      Rolle läuft zum Ort (Misserfolg: irrt umher)
##   behavior     Rolle zeigt ein Verhalten (sniff, call, display, dig, …)
##   follow       alle Beteiligten laufen zur Rolle "leader" (nur bei Erfolg der Rolle)
##   wait         Pause ("seconds")

signal step_started(text: String)
signal finished(result: Dictionary)

const STEP_TIMEOUT := 90.0
## So lange bleibt die Ergebnis-Einblendung eines Schritts stehen (Sekunden).
const RESULT_PAUSE := 1.6
## So lange stehen ✓/✗ über den Beteiligten, bevor die Auswertung kommt.
const MARKER_TIME := 2.5
const OK_COLOR := Color(0.55, 1.0, 0.45)
## Abstand, in dem die übrigen Beteiligten beim aktuellen Schritt warten (Meter).
const ESCORT_DISTANCE := 2.6
const FAIL_COLOR := Color(1.0, 0.5, 0.4)
const FRUIT_COLOR := Color(0.85, 0.2, 0.15)

var world: Node3D
var task: TaskDef
var result: Dictionary
## role_id -> Creature
var actors: Dictionary = {}
var running := false
## Kreatur, die gerade am Zug ist (Kamera-Knopf „Zur Aufgabe“).
var active: Creature

var _items: Dictionary = {}  # Name -> Node3D
## Creature -> true: Beteiligte, die schon zum Ort des aktuellen Schritts laufen
var _escorts: Dictionary = {}
var _names: Dictionary = {}  # Creature -> Anzeigename


## result: TaskSimulator.simulate(); creatures: role_id -> Creature; names: Creature -> Name
func play(p_world: Node3D, p_task: TaskDef, p_result: Dictionary, creatures: Dictionary, names: Dictionary) -> void:
	world = p_world
	task = p_task
	result = p_result
	actors = creatures
	_names = names
	running = true
	_apply_context()
	for c in actors.values():
		_brain(c).paused = true
		_brain(c).stop_current()
	_gather()
	for i in 20:
		await get_tree().physics_frame
	for step in task.steps:
		if not running:
			break
		await _run_step(step)
	for c in _escorts:
		if is_instance_valid(c):
			_brain(c).mover.stop()
	_escorts.clear()
	if running:
		await _show_markers()
	step_started.emit("")
	for c in actors.values():
		if is_instance_valid(c):
			_brain(c).paused = false
	for item in _items.values():
		if is_instance_valid(item):
			var t := get_tree().create_timer(20.0)
			t.timeout.connect(item.queue_free)
	running = false
	finished.emit(result)


## ✓ bzw. ✗ über jedem Beteiligten, damit sichtbar ist, wer es geschafft hat.
func _show_markers() -> void:
	for role_id in actors:
		var c: Creature = actors[role_id]
		if not is_instance_valid(c):
			continue
		var skipped: bool = result.roles.get(role_id, {}).get("skipped", false)
		var ok := role_ok(role_id)
		var mark := "–" if skipped else ("✓" if ok else "✗")
		c.set_tag("%s %s" % [mark, _who(role_id, c)], OK_COLOR if ok else (Color(0.8, 0.8, 0.8) if skipped else FAIL_COLOR))
	step_started.emit("Geschafft!" if result.success else "Nicht geschafft …")
	await _pause(MARKER_TIME)


## "Kletterer Tamo"
func _who(role_id: String, c: Creature) -> String:
	return "%s %s" % [task.role(role_id).get("name", role_id), _names.get(c, c.name)]


func _pause(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await _frame()
		t += get_physics_process_delta_time()


## Ein Physik-Frame; nebenbei laufen die übrigen Beteiligten weiter zum Geschehen.
func _frame() -> void:
	await get_tree().physics_frame
	var dt := get_physics_process_delta_time()
	for c in _escorts.keys():
		if not is_instance_valid(c):
			_escorts.erase(c)
		elif _brain(c).mover.step(dt):
			_brain(c).mover.stop()
			_escorts.erase(c)


## Wer später noch dran ist, geht schon jetzt in die Nähe des aktuellen Schritts,
## damit er nicht erst von weit her anlaufen muss.
func _send_escorts(step: Dictionary, active_role: String) -> void:
	var idx := task.steps.find(step)
	var upcoming := {}
	for later in task.steps.slice(idx + 1):
		upcoming[str(later.get("role", ""))] = true
	var place := _place_of(step)
	var n := 0
	for role_id in actors:
		var other: Creature = actors[role_id]
		if role_id == active_role or not upcoming.has(role_id) or not is_instance_valid(other):
			continue
		if result.roles.get(role_id, {}).get("skipped", false):
			continue
		var away := other.global_position - place
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.BACK
		away = away.rotated(Vector3.UP, 0.5 * n)
		var target := place + away * (ESCORT_DISTANCE + other.radius)
		if Vector2(other.global_position.x - target.x, other.global_position.z - target.z).length() > 1.0:
			_brain(other).mover.go(target)
			_escorts[other] = true
		n += 1


func role_ok(role_id: String) -> bool:
	return result.roles.get(role_id, {}).get("success", false)


func _brain(c: Creature) -> BehaviorBrain:
	return world.brains[world.creatures.find(c)]


func _apply_context() -> void:
	if task.context.has("hour"):
		world.day_night.hour = float(task.context.hour)
		world.day_night.apply_lighting()
	if task.context.has("weather"):
		world.weather.auto_change = false
		world.weather.set_state(str(task.context.weather))


## Beteiligte versammeln sich in der Nähe des ersten Ortes.
func _gather() -> void:
	var first: Vector3 = _place_of(task.steps[0]) if not task.steps.is_empty() else _place("spawn")
	var l: ForestLayout = world.terrain.layout
	var n := 0
	for c in actors.values():
		var rng := RngUtil.make_rng(["gather", task.id, n])
		for attempt in 40:
			var a := rng.randf_range(0.0, TAU)
			var r := rng.randf_range(3.0, 5.5)
			var x := first.x + cos(a) * r
			var z := first.z + sin(a) * r
			if l.zone_at(x, z) in ["forest", "clearing", "bank"]:
				c.global_position = Vector3(x, l.height_at(x, z), z)
				break
		c.look_at_from_position(c.global_position, Vector3(first.x, c.global_position.y, first.z), Vector3.UP)
		c.locomotion.reset(c.global_transform)
		n += 1


func _run_step(step: Dictionary) -> void:
	var role_id := str(step.get("role", ""))
	var c: Creature = actors.get(role_id)
	var skipped: bool = result.roles.get(role_id, {}).get("skipped", false)
	if c == null or skipped:
		return
	var outcome := "success" if role_ok(role_id) else "fail"
	var who := _who(role_id, c)
	_escorts.erase(c)
	_brain(c).mover.stop()
	_send_escorts(step, role_id)
	active = c
	world.camera.follow = c
	world.camera.distance = clampf(world.camera.distance, 5.0, 9.0)
	world.selected = c
	match str(step.type):
		"climb_tree":
			step_started.emit("%s klettert auf den Baum …" % who)
			var tree: FruitTree = _resolve(str(step.place))
			await _force_and_wait(c, "climb_tree", {"tree": tree, "forced_outcome": outcome})
			if outcome == "success" and step.get("on_success", "") == "drop_fruit":
				_drop_fruit(tree)
				step_started.emit("Die Frucht fällt herunter!")
				await _pause(RESULT_PAUSE)
			elif outcome != "success":
				step_started.emit("%s kommt nicht hinauf." % who)
				await _pause(RESULT_PAUSE)
			# vom Stamm zurücktreten, damit der Weg für die anderen frei ist
			var away := c.global_position - tree.global_position
			away.y = 0.0
			away = away.normalized() if away.length() > 0.01 else Vector3.BACK
			await _walk(c, c.global_position + away * 2.5, true, 6.0)
		"pick_up":
			var item: Node3D = _items.get(str(step.get("item", "")))
			if item == null:
				return
			step_started.emit("%s holt die Frucht …" % who)
			await _walk(c, item.global_position, true)
			c.locomotion.pose_pitch = -0.3
			for i in 30:
				await _frame()
			c.locomotion.pose_pitch = 0.0
			c.held_item = item
		"cross_stream":
			step_started.emit("%s versucht, den Bach zu durchqueren …" % who)
			var p: Vector3 = _place_of(step)
			await _force_and_wait(c, "swim", {"crossing": Vector2(p.x, p.z), "forced_outcome": outcome})
			step_started.emit(("%s ist drüben." if outcome == "success" else "%s schafft es nicht über den Bach.") % who)
			await _pause(RESULT_PAUSE)
		"drop":
			c.drop_item()
		"walk_to":
			step_started.emit("%s geht voraus …" % who)
			var target: Vector3 = _place_of(step)
			if outcome == "success":
				await _walk(c, target, false)
				step_started.emit("%s hat den Weg gefunden." % who)
			else:
				await _wander_lost(c)
				step_started.emit("%s hat sich verlaufen." % who)
			await _pause(RESULT_PAUSE)
		"behavior":
			var bid := str(step.get("behavior", "wander"))
			step_started.emit("%s: %s" % [who, _behavior_label(bid)])
			await _force_and_wait(c, bid, {"forced_outcome": outcome})
			step_started.emit("%s: %s" % [who, "hat geklappt" if outcome == "success" else "hat nicht geklappt"])
			await _pause(RESULT_PAUSE)
		"follow":
			var leader: Creature = actors.get(str(step.get("leader", "")))
			if leader == null or not role_ok(role_id):
				return
			step_started.emit("Die anderen folgen …")
			for other in actors.values():
				if other != leader:
					_brain(other).mover.go(leader.global_position)
			var t := 0.0
			while t < 25.0:
				var all_there := true
				for other in actors.values():
					if other != leader and not _brain(other).mover.step(1.0 / 60.0):
						all_there = false
				if all_there:
					break
				await get_tree().physics_frame
				t += get_physics_process_delta_time()
			for other in actors.values():
				_brain(other).mover.stop()
		"wait":
			var t2 := 0.0
			while t2 < float(step.get("seconds", 1.0)):
				await _frame()
				t2 += get_physics_process_delta_time()


func _force_and_wait(c: Creature, behavior_id: String, p: Dictionary) -> void:
	var brain := _brain(c)
	brain.force(behavior_id, p)
	var b := brain.current
	var t := 0.0
	while brain.current == b and b != null and t < STEP_TIMEOUT:
		await _frame()
		t += get_physics_process_delta_time()
	brain.stop_current()


## Läuft über das Navmesh (bei `near` bis kurz vor das Ziel).
func _walk(c: Creature, target: Vector3, near: bool, timeout := STEP_TIMEOUT) -> void:
	var mover := _brain(c).mover
	mover.go(target)
	var t := 0.0
	while t < timeout:
		if mover.step(get_physics_process_delta_time()) or (near and mover.distance_to_goal() < 0.9):
			break
		await _frame()
		t += get_physics_process_delta_time()
	mover.stop()


## Misserfolg beim Wegfinden: irrt einige Zeit ziellos umher.
func _wander_lost(c: Creature) -> void:
	var mover := _brain(c).mover
	var rng := RngUtil.make_rng(["lost", task.id, c.name])
	for leg in 3:
		var a := rng.randf_range(0.0, TAU)
		mover.go(c.global_position + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(3.0, 6.0))
		var t := 0.0
		while t < 8.0 and not mover.step(get_physics_process_delta_time(), 0.6):
			await _frame()
			t += get_physics_process_delta_time()
	mover.stop()


func _drop_fruit(tree: FruitTree) -> void:
	var positions := tree.fruit_positions()
	var start := positions[0] if not positions.is_empty() else tree.global_position + Vector3(0, tree.fruit_height, 0)
	tree.take_fruit()
	var fruit := CarryItem.new()
	fruit.size = 0.13
	fruit.name = "TaskFruit"
	world.creature_root.add_child(fruit)
	fruit.claimed_by = self
	for child in fruit.get_children():
		child.queue_free()
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.13
	s.height = 0.26
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FRUIT_COLOR
	s.material = mat
	mi.mesh = s
	mi.position.y = 0.13
	fruit.add_child(mi)
	fruit.global_position = start
	var l: ForestLayout = world.terrain.layout
	var ground := Vector3(start.x + 0.8, 0.0, start.z + 0.8)
	ground.y = l.height_at(ground.x, ground.z)
	fruit.create_tween().tween_property(fruit, "global_position", ground, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_items["task_fruit"] = fruit


func _place_of(step: Dictionary) -> Vector3:
	if step.has("place"):
		var p = _resolve(str(step.place))
		return p.global_position if p is Node3D else p
	var c: Creature = actors.get(str(step.get("role", "")))
	return c.global_position if c != null else _place("spawn")


## Ortsangabe aus task.places auflösen -> Node3D oder Vector3.
func _resolve(place_name: String) -> Variant:
	return _place(str(task.places.get(place_name, place_name)))


func _place(spec: String) -> Variant:
	var l: ForestLayout = world.terrain.layout
	var parts := spec.split(":")
	match parts[0]:
		"fruit_tree":
			return world.terrain.fruit_trees[clampi(int(parts[1]), 0, world.terrain.fruit_trees.size() - 1)]
		"rock":
			var best: Dictionary = l.rocks[0]
			for r in l.rocks:
				if (parts.size() > 1 and parts[1] == "largest" and r.size > best.size):
					best = r
			return Vector3(best.pos.x, l.height_at(best.pos.x, best.pos.y), best.pos.y)
		"stream_near":
			var ref = _resolve(parts[1])
			var p: Vector3 = ref.global_position if ref is Node3D else ref
			var c: Vector2 = l.stream_info(p.x, p.z).closest
			return Vector3(c.x, l.water_level_at(c.x, c.y), c.y)
		"point":
			var xz := parts[1].split(",")
			return Vector3(float(xz[0]), l.height_at(float(xz[0]), float(xz[1])), float(xz[1]))
		_:
			return Vector3(l.spawn_pos.x, l.height_at(l.spawn_pos.x, l.spawn_pos.y), l.spawn_pos.y)


func _behavior_label(id: String) -> String:
	var brain: BehaviorBrain = world.brains[0]
	for b in brain.behaviors:
		if b.id == id:
			return b.label
	return id
