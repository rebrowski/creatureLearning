extends GutTest
## Bühne und Proben: Bewertung (0–3), Journal, alle acht Beweis-Momente.

var gs: GameState
var catalog: AbilityCatalog
var probes: ProbeCatalog


func before_all() -> void:
	gs = GameState.new_game()
	catalog = AbilityCatalog.load_file(gs.schema)
	probes = ProbeCatalog.load_file()


func _members(count: int) -> Array[GroupMember]:
	var out: Array[GroupMember] = []
	var all := gs.taxonomy.species()
	for i in count:
		var sp: Taxon = all[i % all.size()]
		out.append(GroupMember.from_individual(gs.factory.create_individual(sp.id, 500 + i, "", "adult"), "T%d" % i))
	return out


func test_catalog_covers_every_ability() -> void:
	assert_eq(probes.probes.size(), 8)
	var seen := {}
	for p in probes.probes:
		assert_true(catalog.order.has(str(p.ability)), "%s: Fähigkeit existiert" % p.id)
		assert_eq(p.results.size(), 4, "%s: vier Stufen" % p.id)
		assert_true(Stage.focus_for(str(p.prop)).size() == 3, "%s: Kamera-Ziel" % p.id)
		seen[p.ability] = true
	assert_eq(seen.size(), catalog.order.size(), "jede Fähigkeit hat eine Probe")


func test_grade_follows_ability_and_is_deterministic() -> void:
	var probe := probes.get_probe("climb")
	var low := 0.0
	var high := 0.0
	var nl := 0
	var nh := 0
	for m in _members(40):
		var g := probes.grade(m, probe, catalog, 0)
		assert_between(g, 0, 3)
		assert_eq(probes.grade(m, probe, catalog, 0), g, "gleicher Versuch = gleiche Stufe")
		var v := catalog.value_in("climb", m.genome, ProbeCatalog.sample_for(probe))
		if v < 0.3:
			low += g
			nl += 1
		elif v > 0.7:
			high += g
			nh += 1
	if nl > 0 and nh > 0:
		assert_gt(high / nh, low / nl + 1.0, "starke Kletterer schneiden deutlich besser ab")


func test_waders_pass_the_stream() -> void:
	var probe := probes.get_probe("swim")
	for m in _members(40):
		if TaskSimulator.can_wade(m.genome, 0.6):
			assert_eq(probes.grade(m, probe, catalog, 0), 3, "Waten zählt")


func test_night_probe_uses_darkness() -> void:
	var s := ProbeCatalog.sample_for(probes.get_probe("night"))
	assert_true(s.is_night)
	assert_lt(float(s.light), 0.2)


func test_task_grade() -> void:
	assert_eq(ProbeCatalog.task_grade({"success": true, "score": 0.1, "threshold": 0.5}), 3)
	assert_eq(ProbeCatalog.task_grade({"success": false, "score": 0.0, "threshold": 0.5}), 0)
	assert_eq(ProbeCatalog.task_grade({"success": false, "score": 0.49, "threshold": 0.5}), 2)
	assert_eq(ProbeCatalog.task_grade({"success": false, "score": 0.2, "threshold": 0.5}), 1)


func test_journal_keeps_probes() -> void:
	var j := Journal.new()
	assert_eq(j.probe("a", "dig"), -1)
	j.set_probe("a", "dig", 2)
	assert_eq(Journal.from_dict(j.to_dict()).probe("a", "dig"), 2)
	assert_eq(Journal.grade_dots(0), "○○○")
	assert_eq(Journal.grade_dots(3), "●●●")


func test_every_proof_moment_plays_to_the_end() -> void:
	var stage := Stage.new()
	add_child(stage)
	stage.position = Vector3(0, 0, 900)
	stage.build(1)
	stage.camera.current = true
	var nights := []
	var director := StageDirector.new(stage, catalog, probes, func(on: bool): nights.append(on))
	var m: GroupMember = gs.members[0]
	var captions := []
	stage.caption.connect(func(t: String): captions.append(t))
	Engine.time_scale = 10.0
	for p in probes.probes:
		for g in [0, 3]:
			captions.clear()
			var t0 := Time.get_ticks_msec()
			await director.run_probe(m, p, g)
			assert_lt(Time.get_ticks_msec() - t0, 6000, "%s/%d endet zügig" % [p.id, g])
			assert_eq(captions[-1], "%s: %s" % [m.name, probes.result_text(p, g)], "%s/%d: Ergebnis gezeigt" % [p.id, g])
			assert_eq(stage.actors.size(), 1)
	Engine.time_scale = 1.0
	assert_true(nights.has(true), "Nachtprobe verdunkelt")
	assert_false(nights[-1], "danach wieder Tag")
	stage.clear()
	stage.queue_free()
