extends GutTest
## Aufgaben: Format, Simulation, Auswertung.

var gs: GameState
var catalog: AbilityCatalog
var tasks: TaskCatalog


func before_all() -> void:
	gs = GameState.new_game()
	catalog = AbilityCatalog.load_file(gs.schema)
	tasks = TaskCatalog.load_dir(catalog)


func _by_score(task: TaskDef, role_id: String, best: bool) -> GroupMember:
	var pick: GroupMember = null
	var pick_score := 0.0
	for m in gs.members:
		var s: float = TaskSimulator.simulate(task, {role_id: m}, catalog, 0).roles[role_id].score
		if pick == null or (s > pick_score) == best:
			pick = m
			pick_score = s
	return pick


func test_catalog() -> void:
	assert_eq(tasks.errors, PackedStringArray())
	assert_gte(tasks.tasks.size(), 2)
	assert_eq(tasks.tasks[0].id, "fruit_over_stream", "sortiert nach order")
	for t in tasks.tasks:
		assert_between(t.roles.size(), 2, 4)


func test_invalid_task() -> void:
	var t := TaskDef.from_dict({"id": "x", "places": {}, "roles": [
		{"id": "a", "requirements": [{"ability": "fly"}]},
		{"id": "b", "requirements": [{"ability": "swim"}], "requires": ["c"]}],
		"steps": [{"type": "teleport"}, {"type": "walk_to", "role": "z", "place": "nowhere"}]}, catalog)
	assert_eq(t.errors.size(), 6, str(t.errors))


func test_good_team_succeeds_poor_team_fails() -> void:
	var t := tasks.get_task("fruit_over_stream")
	var good := {"climber": _by_score(t, "climber", true), "carrier": _by_score(t, "carrier", true)}
	if good.climber == good.carrier:
		good.carrier = gs.members.filter(func(m): return m != good.climber)[0]
	var r := TaskSimulator.simulate(t, good, catalog, 0)
	assert_true(r.roles.climber.success)
	var poor := {"climber": _by_score(t, "climber", false), "carrier": _by_score(t, "carrier", true)}
	if poor.climber == poor.carrier:
		poor.carrier = good.climber
	var r2 := TaskSimulator.simulate(t, poor, catalog, 0)
	assert_false(r2.success)
	assert_false(r2.roles.climber.success)
	assert_true(r2.roles.carrier.skipped, "ohne Frucht nichts zu tragen")
	assert_gt(r2.hints.size(), 0)
	for h in r2.hints:
		for m in gs.members:
			assert_false(h.contains(m.name), "Hinweise nennen keine Lösung")


func test_simulation_is_deterministic_per_attempt() -> void:
	var t := tasks.get_task("night_walk")
	var a := {"scout": gs.members[4], "caller": gs.members[5]}
	var r1 := TaskSimulator.simulate(t, a, catalog, 3)
	var r2 := TaskSimulator.simulate(t, a, catalog, 3)
	assert_eq(r1.roles.scout.score, r2.roles.scout.score)
	var r3 := TaskSimulator.simulate(t, a, catalog, 4)
	assert_almost_eq(r1.roles.scout.score, r3.roles.scout.score, 0.25, "Zufall ist klein")


func test_wading_counts_for_crossing() -> void:
	var t := tasks.get_task("fruit_over_stream")
	var long_legs: GroupMember = null
	for m in gs.members:
		if TaskSimulator.can_wade(m.genome, 0.6) and catalog.base_value("swim", m.genome) < 0.8:
			long_legs = m
	if long_legs == null:
		pass_test("keine passende Kreatur in der Startgruppe")
		return
	var shallow := TaskSimulator.simulate(t, {"climber": gs.members[4], "carrier": long_legs}, catalog, 0, 0.6)
	var deep := TaskSimulator.simulate(t, {"climber": gs.members[4], "carrier": long_legs}, catalog, 0, 5.0)
	assert_gt(shallow.roles.carrier.score, deep.roles.carrier.score)


func test_night_task_needs_night_vision() -> void:
	var t := tasks.get_task("night_walk")
	var best := _by_score(t, "scout", true)
	var worst := _by_score(t, "scout", false)
	var nv_best := catalog.base_value("night_vision", best.genome)
	var nv_worst := catalog.base_value("night_vision", worst.genome)
	assert_gt(nv_best, nv_worst)
