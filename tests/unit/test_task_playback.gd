extends GutTest
## Eine Aufgabe in der Welt abspielen (beschleunigt).

var world: Node3D


func before_all() -> void:
	get_tree().root.set_meta("forest_no_save", true)
	world = (load("res://scenes/world/forest.tscn") as PackedScene).instantiate()
	add_child(world)
	for i in 240:
		await get_tree().physics_frame
		if world.brains[0].mover.ready():
			break
	Engine.time_scale = 8.0
	Engine.max_physics_steps_per_frame = 64


func after_all() -> void:
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	world.queue_free()


func _pick(role: String, task: TaskDef, best: bool, exclude: GroupMember = null) -> GroupMember:
	var pick: GroupMember = null
	var ps := 0.0
	for m in world.game.members:
		if m == exclude:
			continue
		var s: float = TaskSimulator.simulate(task, {role: m}, world.catalog, 0).roles[role].score
		if pick == null or (s > ps) == best:
			pick = m
			ps = s
	return pick


func _play(task: TaskDef, assignments: Dictionary) -> Dictionary:
	var done := []
	world.start_task(task, assignments)
	world._player.finished.connect(func(r): done.append(r))
	var t := 0.0
	while done.is_empty() and t < 300.0:  # simulierte Sekunden (time_scale)
		await get_tree().process_frame
		t += get_process_delta_time()
	assert_false(done.is_empty(), "Aufgabe endet (Zeitlimit)")
	return done[0] if not done.is_empty() else {}


func test_successful_fruit_task_moves_fruit_across_and_pays() -> void:
	var task: TaskDef = world.tasks.get_task("fruit_over_stream")
	var climber := _pick("climber", task, true)
	var carrier := _pick("carrier", task, true, climber)
	var tree: FruitTree = world.terrain.fruit_trees[0]
	var fruits_before := tree.remaining_fruits()
	var credits_before: int = world.game.credits
	var expected_gain: int = world.game.reward_for(task) - world.game.attempt_cost()
	var r := await _play(task, {"climber": climber, "carrier": carrier})
	assert_true(r.get("success", false), "gute Besetzung gelingt")
	assert_eq(tree.remaining_fruits(), fruits_before - 1, "Frucht vom Baum geholt")
	var fruit: Node3D = world.creature_root.get_node_or_null("TaskFruit")
	assert_not_null(fruit)
	var l: ForestLayout = world.terrain.layout
	var tree_side := l.stream_info(tree.global_position.x, tree.global_position.z)
	var c2: Vector2 = tree_side.closest
	var to_tree := Vector2(tree.global_position.x, tree.global_position.z) - c2
	var to_fruit := Vector2(fruit.global_position.x, fruit.global_position.z) - c2
	assert_lt(to_tree.dot(to_fruit), 0.0, "Frucht liegt am anderen Ufer")
	assert_eq(world.game.credits, credits_before + expected_gain, "Belohnung minus Einsatz")
	assert_eq(world.game.tasks.fruit_over_stream.successes, 1)
	assert_false(world.creature_of(climber).scripted)


func test_weak_climber_fails_without_fruit() -> void:
	var task: TaskDef = world.tasks.get_task("fruit_over_stream")
	var climber := _pick("climber", task, false)
	var carrier := _pick("carrier", task, true, climber)
	var tree: FruitTree = world.terrain.fruit_trees[0]
	var fruits_before := tree.remaining_fruits()
	var r := await _play(task, {"climber": climber, "carrier": carrier})
	assert_false(r.get("success", true))
	assert_eq(tree.remaining_fruits(), fruits_before, "keine Frucht geholt")
	for c in world.creatures:
		assert_false(world.brains[world.creatures.find(c)].paused, "Gehirne wieder frei")
