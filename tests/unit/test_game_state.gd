extends GutTest
## Spielstand, Journal, Rekrutierung.

const PATH := "user://test_save/savegame.json"


func after_all() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_new_game_from_start_group() -> void:
	var gs := GameState.new_game()
	assert_true(gs.is_valid(), str(gs.errors))
	var group: Dictionary = JsonLoader.read(GameState.GROUP_PATH).data
	assert_eq(gs.members.size(), group.members.size())
	var names := {}
	for m in gs.members:
		assert_false(names.has(m.name), "Namen eindeutig")
		names[m.name] = true
		assert_ne(m.name, m.species_id, "Spieler sieht keinen Artnamen")


func test_save_and_load_roundtrip() -> void:
	var gs := GameState.new_game()
	gs.journal.set_mark(gs.members[0].id, 2)
	gs.journal.set_note(gs.members[1].id, "klettert gut?")
	gs.journal.set_rating(gs.members[1].id, "climb", 2)
	var gi := gs.journal.add_group("Stelzer")
	gs.journal.assign_group(gs.members[0].id, gi)
	gs.journal.add_log("10:00", gs.members[0].id, "rief laut")
	gs.record_task(_task(), false)
	gs.credits = 77
	gs.hour = 17.5
	assert_eq(gs.save(PATH), OK)
	var loaded := GameState.load_file(PATH)
	assert_true(loaded.is_valid(), str(loaded.errors))
	assert_eq(loaded.members.size(), gs.members.size())
	for i in gs.members.size():
		assert_eq(loaded.members[i].id, gs.members[i].id)
		assert_eq(loaded.members[i].name, gs.members[i].name)
		assert_true(loaded.members[i].genome.is_equal_approx_to(gs.members[i].genome))
	assert_eq(loaded.journal.marks[gs.members[0].id], 2)
	assert_eq(loaded.journal.notes[gs.members[1].id], "klettert gut?")
	assert_eq(loaded.journal.rating(gs.members[1].id, "climb"), 2)
	assert_eq(loaded.journal.group_of(gs.members[0].id), 0)
	assert_eq(loaded.journal.entries.size(), 1)
	assert_eq(loaded.tasks.fruit_over_stream.attempts, 1)
	assert_almost_eq(loaded.hour, 17.5, 0.001)
	assert_eq(loaded.credits, 77)
	assert_eq(loaded.offers.size(), gs.offers.size())
	for i in gs.offers.size():
		assert_eq(loaded.offers[i].id, gs.offers[i].id)
		assert_eq(loaded.offers[i].price, gs.offers[i].price)
		assert_true(loaded.offers[i].genome.is_equal_approx_to(gs.offers[i].genome))


func test_saved_genomes_survive_generator_changes() -> void:
	var gs := GameState.new_game()
	var d := gs.to_dict()
	d.taxonomy.seed = 999  # als hätte sich der Erzeugungscode/Seed geändert
	var loaded := GameState.new()
	loaded._from_dict(d)
	assert_true(loaded.is_valid(), str(loaded.errors))
	for i in gs.members.size():
		assert_true(loaded.members[i].genome.is_equal_approx_to(gs.members[i].genome), "Kreatur bleibt gleich")


func test_broken_save_is_reported() -> void:
	var gs := GameState.new()
	gs._from_dict({"format": "etwas_anderes"})
	assert_false(gs.is_valid())


func _task(reward := 30) -> TaskDef:
	var t := TaskDef.new()
	t.id = "fruit_over_stream"
	t.reward = reward
	return t


func test_offers_prefer_lookalikes_and_are_reproducible() -> void:
	var a := GameState.new_game()
	var b := GameState.new_game()
	var cfg := GameState.progression()
	assert_eq(a.offers.size(), int(cfg.offers))
	assert_eq(a.credits, int(cfg.start_credits))
	for i in a.offers.size():
		assert_eq(a.offers[i].id, b.offers[i].id, "reproduzierbar")
		assert_eq(a.offers[i].price, b.offers[i].price)
		assert_gt(a.offers[i].price, 0)
		assert_true(a.offers[i].name.begins_with(UiUtil.STRANGER), "Fremde haben noch keinen Namen")
		assert_false(a.members.any(func(m): return m.id == a.offers[i].id), "neue ID")
	# erster Fremder sieht einem Mitglied ähnlich (Doppelgänger)
	var f := a.factory
	var best := INF
	for m in a.members:
		if m.species_id != a.offers[0].species_id:
			best = minf(best, GenomeDistance.distance(f.mean_genome(m.species_id), f.mean_genome(a.offers[0].species_id)))
	assert_lt(best, 0.05)
	assert_eq(a.display_name(a.offers[0].id), a.offers[0].name, "Protokoll verrät die Art nicht")


func test_rewards_and_hiring() -> void:
	var gs := GameState.new_game()
	var start := gs.credits
	assert_eq(gs.reward_for(_task()), 60, "erster Versuch zählt doppelt")
	assert_eq(gs.attempt_cost(), 10)
	var r := gs.record_task(_task(), false, [gs.members[0]])
	assert_eq(r.earned, 0, "Misserfolg bringt nichts")
	assert_eq(r.cost, 10, "Einsatz")
	assert_eq(r.new_offers.size(), 0, "Fremde schon vollzählig")
	assert_true(gs.members[0].exhausted, "wer scheitert, ist erschöpft")
	assert_eq(r.exhausted.size(), 1)
	assert_eq(gs.new_morning(), 1)
	assert_false(gs.members[0].exhausted, "am Morgen wieder fit")
	assert_eq(gs.reward_for(_task()), 30, "zweiter Versuch: einfach")
	r = gs.record_task(_task(), true)
	assert_eq(r.earned, 30)
	assert_eq(gs.reward_for(_task()), 15, "Wiederholung: halbe Belohnung")
	assert_eq(gs.record_task(_task(), true).earned, 15)
	assert_eq(gs.credits, start + 45 - 30)
	gs.credits = 4
	assert_eq(gs.attempt_cost(), 4, "Einsatz nie höher als das Guthaben")
	var offer := gs.offers[0]
	gs.credits = offer.price - 1
	assert_ne(gs.hire_problem(offer), "")
	assert_false(gs.hire(offer), "zu wenig Guthaben")
	gs.credits = offer.price + 3
	var n := gs.members.size()
	assert_true(gs.hire(offer))
	assert_eq(gs.credits, 3)
	assert_eq(gs.members.size(), n + 1)
	assert_false(gs.offers.has(offer))
	assert_false(offer.name.begins_with(UiUtil.STRANGER), "bekommt einen Namen")
	assert_eq(offer.price, 0)
	assert_eq(gs.record_task(_task(), false).new_offers.size(), 1, "nach der Aufgabe kommt ein neuer Fremder")


func test_old_save_gets_credits_and_offers() -> void:
	var gs := GameState.new_game()
	var d := gs.to_dict()
	d.erase("credits")
	d.erase("offers")
	var loaded := GameState.new()
	loaded._from_dict(d)
	assert_true(loaded.is_valid(), str(loaded.errors))
	assert_eq(loaded.credits, int(GameState.progression().start_credits))
	assert_eq(loaded.offers.size(), int(GameState.progression().offers))


func test_journal_rules() -> void:
	var j := Journal.new()
	var g1 := j.add_group("A")
	var g2 := j.add_group("B")
	j.assign_group("x", g1)
	j.assign_group("x", g2)
	assert_eq(j.group_of("x"), g2, "nur eine eigene Gruppe pro Kreatur")
	assert_false(j.groups[g1].members.has("x"))
	j.set_rating("x", "swim", 1)
	j.set_rating("x", "swim", -1)
	assert_eq(j.rating("x", "swim"), -1)
	for i in Journal.LOG_SIZE + 10:
		j.add_log("00:00", "x", str(i))
	assert_eq(j.entries.size(), Journal.LOG_SIZE)
	assert_eq(j.entries_for("x", 3).size(), 3)
	assert_eq(j.entries_for("x", 1)[0].text, str(Journal.LOG_SIZE + 9), "neueste zuerst")


func test_task_unlocks() -> void:
	var gs := GameState.new_game()
	var t := _task()
	var later := TaskDef.new()
	later.id = "later"
	later.unlock_after = t.id
	assert_true(gs.task_unlocked(t))
	assert_false(gs.task_unlocked(later))
	gs.record_task(t, true)
	assert_true(gs.task_unlocked(later))


func test_species_questions_and_field_guide() -> void:
	var gs := GameState.new_game()
	var q := gs.species_question()
	assert_false(q.is_empty())
	var same: bool = q.a.species_id == q.b.species_id
	var credits := gs.credits
	var r := gs.answer_species_question(q.a, q.b, same)
	assert_true(r.correct)
	assert_eq(gs.credits, credits + int(GameState.progression().species_reward))
	assert_gt(r.discovered.size(), 0, "Art kommt ins Bestimmungsbuch")
	assert_true(gs.identified.has(q.a.species_id))
	var q2 := gs.species_question()
	assert_false(q2.is_empty() or (q2.a == q.a and q2.b == q.b), "nicht dieselbe Frage zweimal")
	var wrong := gs.answer_species_question(q2.a, q2.b, q2.a.species_id != q2.b.species_id)
	assert_false(wrong.correct)
	assert_eq(wrong.reward, 0)
	var known := 0
	for e in gs.field_guide():
		if e[2]:
			known += 1
	assert_gt(known, 0)
	var loaded := GameState.new()
	loaded._from_dict(gs.to_dict())
	assert_eq(loaded.identified.size(), gs.identified.size(), "gespeichert")
	assert_eq(loaded.asked_pairs.size(), gs.asked_pairs.size())


func test_intro_only_for_new_games_and_exhaustion_saved() -> void:
	var gs := GameState.new_game()
	assert_eq(gs.intro_step, 0, "neues Spiel beginnt mit Einführung")
	gs.members[0].exhausted = true
	var d := gs.to_dict()
	var loaded := GameState.new()
	loaded._from_dict(d)
	assert_true(loaded.members[0].exhausted)
	d.erase("intro_step")
	var old := GameState.new()
	old._from_dict(d)
	assert_eq(old.intro_step, GameState.INTRO_DONE, "ältere Spielstände ohne Einführung")


func test_needed_species_offer_avoids_dead_ends() -> void:
	var gs := GameState.new_game()
	var cat := AbilityCatalog.load_file(gs.schema)
	var tc := TaskCatalog.load_dir(cat)
	for t in tc.tasks:
		if t.id in ["fruit_from_tree", "fruit_over_stream"]:
			gs.record_task(t, true)
	var needed := gs.needed_species(tc, cat)
	assert_gt(needed.size(), 0, "Trüffelsuche braucht einen Gräber, den die Startgruppe nicht hat")
	gs.ensure_needed_offer(needed)
	assert_true(gs.offers.any(func(o): return needed.has(o.species_id)), "ein passender Fremder wartet")


func test_sites_limit_rewards_and_regrow() -> void:
	var gs := GameState.new_game()
	var t := _task()
	t.site = "fruit_tree_0"
	var stock: int = gs.site_stock(t)
	assert_gt(stock, 0)
	gs.sites["fruit_tree_0"] = 1
	assert_gt(gs.record_task(t, true).earned, 0)
	assert_eq(gs.site_stock(t), 0, "Vorrat verbraucht")
	assert_true(gs.site_text(t).contains("nichts mehr"))
	gs.new_morning()
	assert_gt(gs.site_stock(t), 0, "wächst über Nacht nach")


func test_rival_ai_is_fair_and_learns() -> void:
	var gs := GameState.new_game()
	var cat := AbilityCatalog.load_file(gs.schema)
	var tc := TaskCatalog.load_dir(cat)
	var r: RivalState = gs.rivals[0]
	assert_eq(r.members.size(), 6)
	assert_almost_eq(r.belief(r.members[0].id, "climb"), RivalState.start_belief(), 0.001, "kennt die wahren Werte nicht")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ev := RivalAI.act(gs, r, tc, cat, rng)
	assert_eq(ev.type, "observe", "mit vorsichtigen Schätzungen wird erst beobachtet")
	# nach vielen Beobachtungen nähern sich die Schätzungen den wahren Werten
	for i in 200:
		RivalAI._observe(r, cat, rng, RivalState.difficulty("ehrgeizig"))
	var m := r.members[0]
	var err := 0.0
	for a in cat.order:
		err += absf(r.belief(m.id, a) - cat.base_value(a, m.genome))
	assert_lt(err / cat.order.size(), 0.25, "lernt durch Beobachten")


func test_season_result_and_save() -> void:
	var gs := GameState.new_game()
	gs.points = 50
	gs.rivals[0].points = 100
	gs.difficulty = "normal"
	var res := gs.finish_season()
	assert_false(res.won)
	assert_eq(res.suggest, "gemütlich", "deutliche Niederlage: ruhigere Rivalen vorschlagen")
	var loaded := GameState.new()
	loaded._from_dict(gs.to_dict())
	assert_eq(loaded.rivals.size(), 1)
	assert_eq(loaded.rivals[0].members.size(), gs.rivals[0].members.size())
	assert_eq(loaded.rivals[0].points, 100)
	assert_eq(loaded.season.history.size(), 1)
	gs.start_season(2)
	assert_eq(gs.points, 0)
	assert_eq(gs.reward_for(_task()), 60, "neue Saison: Erstversuch-Bonus gilt wieder")


func test_pending_task_is_saved() -> void:
	var gs := GameState.new_game()
	gs.pending_task = {"task": "fruit_from_tree", "assignments": {"climber": gs.members[0].id}, "result": {"success": true, "roles": {}, "hints": []}}
	var loaded := GameState.new()
	loaded._from_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	assert_eq(loaded.pending_task.task, "fruit_from_tree", "laufende Aufgabe übersteht einen Neustart")
