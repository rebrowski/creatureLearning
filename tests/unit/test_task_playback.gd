extends GutTest
## Eine Aufgabe auf der Bühne abspielen (beschleunigt).

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


## Startet die Aufgabe und wartet, bis die Bühne fertig ist. Rückgabe: Anzahl Darsteller zwischendurch.
func _play(task: TaskDef, assignments: Dictionary) -> int:
	world._result_panel.visible = false
	world.start_task(task, assignments)
	assert_true(world._busy, "Bühne läuft")
	assert_true(world.stage.camera.current, "Bühnenkamera aktiv")
	var most := 0
	var t := 0.0
	while world._busy and t < 60.0:  # Echtzeit-Sekunden
		await get_tree().process_frame
		most = maxi(most, world.stage.actors.size())
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	assert_false(world._busy, "Aufgabe endet (Zeitlimit)")
	assert_true(world._result_panel.visible, "Auswertung erscheint")
	assert_true(world.stage.actors.is_empty(), "Bühne aufgeräumt")
	assert_eq(world.get_viewport().get_camera_3d(), world.camera, "zurück ins Lager")
	return most


func test_successful_fruit_task_pays_and_uses_stock() -> void:
	var task: TaskDef = world.tasks.get_task("fruit_over_stream")
	var climber := _pick("climber", task, true)
	var carrier := _pick("carrier", task, true, climber)
	var stock: int = world.game.site_stock(task)
	var credits_before: int = world.game.credits
	var expected_gain: int = world.game.reward_for(task) - world.game.attempt_cost()
	var most := await _play(task, {"climber": climber, "carrier": carrier})
	assert_eq(most, 1, "je Abschnitt steht nur eine Kreatur auf der Bühne")
	assert_eq(world.game.tasks.fruit_over_stream.successes, 1, "gute Besetzung gelingt")
	assert_eq(world.game.site_stock(task), stock - 1, "Fundstelle verbraucht")
	assert_eq(world.game.credits, credits_before + expected_gain, "Belohnung minus Einsatz")
	assert_true(world.game.pending_task.is_empty())


func test_weak_climber_fails() -> void:
	var task: TaskDef = world.tasks.get_task("fruit_over_stream")
	var climber := _pick("climber", task, false)
	var carrier := _pick("carrier", task, true, climber)
	var stock: int = world.game.site_stock(task)
	var before: int = world.game.tasks.get(task.id, {}).get("successes", 0)
	await _play(task, {"climber": climber, "carrier": carrier})
	assert_eq(world.game.tasks.get(task.id, {}).get("successes", 0), before, "kein Erfolg")
	assert_eq(world.game.site_stock(task), stock, "Vorrat unverändert")
	assert_true(climber.exhausted, "wer scheitert, ist erschöpft")
