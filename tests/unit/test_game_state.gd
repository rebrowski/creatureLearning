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
	gs.record_task("fruit_over_stream", false)
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


func test_recruiting_prefers_lookalikes_and_is_reproducible() -> void:
	var a := GameState.new_game()
	var b := GameState.new_game()
	var joined := a.record_task("fruit_over_stream", true)
	assert_eq(joined.size(), 1)
	assert_eq(b.record_task("fruit_over_stream", true)[0].id, joined[0].id, "reproduzierbar")
	assert_eq(a.record_task("fruit_over_stream", false).size(), 0, "Misserfolg: niemand kommt dazu")
	# erster Neuzugang sieht einem Mitglied ähnlich (Doppelgänger)
	var f := a.factory
	var best := INF
	for m in a.members:
		if m.species_id != joined[0].species_id:
			best = minf(best, GenomeDistance.distance(f.mean_genome(m.species_id), f.mean_genome(joined[0].species_id)))
	assert_lt(best, 0.05)
	assert_false(a.members.slice(0, a.members.size() - 1).any(func(m): return m.id == joined[0].id), "neue ID")


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
