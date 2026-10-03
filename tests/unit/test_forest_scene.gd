extends GutTest
## Die gebaute Waldszene: Gelände, Kontext, Navigation, Startgruppe.

const SCENE := "res://scenes/world/forest.tscn"
var world: Node3D


func before_all() -> void:
	get_tree().root.set_meta("forest_no_save", true)
	world = (load(SCENE) as PackedScene).instantiate()
	add_child(world)
	for i in 60:
		await get_tree().physics_frame
		if world.navigation.is_baked:
			break


func after_all() -> void:
	world.queue_free()


func test_scene_has_components() -> void:
	for n in ["Terrain", "Gardener", "Navigation", "DayNight", "Weather", "WorldContext", "Camera", "Creatures", "Sun", "Moon"]:
		assert_not_null(world.get_node_or_null(n), n)


func test_terrain_built_with_collision_matching_layout() -> void:
	var t: ForestTerrain = world.terrain
	assert_not_null(t.terrain_body)
	assert_eq(t.fruit_trees.size(), t.layout.fruit_trees.size())
	assert_eq(t.rocks.size(), t.layout.rocks.size())
	var space := world.get_world_3d().direct_space_state
	for p in [Vector2(5.3, -7.1), Vector2(-12.0, 15.0), Vector2(20.4, 3.3)]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 30, p.y), Vector3(p.x, -30, p.y))
		q.collision_mask = t.ground_layer
		var hit := space.intersect_ray(q)
		assert_false(hit.is_empty())
		if t.layout.zone_at(p.x, p.y) != "rock":
			assert_almost_eq(hit.position.y, t.layout.height_at(p.x, p.y), 0.15, "Kollision = Layout bei %s" % p)


func test_gardener_has_vegetation() -> void:
	var g = world.get_node("Gardener")
	var total := 0
	for m in g.arborist.octree_managers:
		total += m.root_octree_node.get_nested_member_count()
	assert_gt(total, 1000)


func test_fruit_trees_have_fruits_at_height() -> void:
	var tree: FruitTree = world.terrain.fruit_trees[0]
	var fruits := tree.fruit_positions()
	assert_eq(fruits.size(), tree.fruit_count)
	for f in fruits:
		assert_almost_eq(f.y - tree.global_position.y, tree.fruit_height, 0.35)
	assert_true(tree.take_fruit())
	assert_eq(tree.remaining_fruits(), tree.fruit_count - 1)


func test_world_context_sample() -> void:
	var ctx: WorldContext = WorldContext.find(get_tree())
	assert_not_null(ctx)
	var l: ForestLayout = world.terrain.layout
	var water := l.stream_points[2]
	var s := ctx.sample(Vector3(water.x, 0, water.y))
	assert_eq(s.zone, "water")
	assert_true(s.in_water)
	for key in ["hour", "phase", "is_night", "light", "weather", "rain", "wetness", "near_rock", "near_fruit_tree"]:
		assert_true(s.has(key), key)
	var tree_pos: Vector3 = world.terrain.fruit_trees[0].global_position
	assert_true(ctx.sample(tree_pos + Vector3(1.8, 0, 0)).near_fruit_tree)


func test_navigation_avoids_water() -> void:
	assert_true(world.navigation.is_baked, "Navmesh gebacken")
	var map: RID = world.navigation.map()
	var l: ForestLayout = world.terrain.layout
	var on_water := NavigationServer3D.map_get_closest_point(map, Vector3(l.stream_points[2].x, 0, l.stream_points[2].y))
	var d: float = l.stream_info(on_water.x, on_water.z).distance
	assert_gt(d, l.stream_width * 0.5, "nächster begehbarer Punkt liegt nicht im Bach")
	var path := NavigationServer3D.map_get_path(map, Vector3(-4, 0, -10), Vector3(8, 0, -16), true)
	assert_gt(path.size(), 1)


func test_start_group_spawned_on_land() -> void:
	var group: Dictionary = JsonLoader.read(GameState.GROUP_PATH).data
	assert_eq(world.members.size(), group.members.size())
	assert_eq(world.strangers.size(), world.game.offers.size(), "Fremde am Waldrand")
	assert_eq(world.rival_creatures.size(), world.game.rivals[0].members.size(), "Rivalen im Lager")
	assert_eq(world.creatures.size(), world.members.size() + world.strangers.size() + world.rival_creatures.size())
	for c in world.creatures:
		var zone: String = world.terrain.layout.zone_at(c.global_position.x, c.global_position.z)
		assert_true(zone in ["clearing", "forest", "bank", "tree", "rock"], "%s steht in %s" % [c.name, zone])


func test_name_tags() -> void:
	for c in world.members:
		assert_not_null(c.tag)
		assert_eq(c.tag.text, world.members[c].name)
	for c in world.strangers:
		assert_true(c.tag.text.contains(str(world.strangers[c].price)), "Fremde zeigen ihren Preis")
		assert_false(c.tag.text.contains(world.strangers[c].species_id))
	world.show_names = false
	world._update_tags()
	assert_false(world.creatures[0].tag.visible)
	world.show_names = true
	world._update_tags()
	assert_true(world.creatures[0].tag.visible)


func test_creatures_do_not_overlap() -> void:
	var a: Creature = world.creatures[0]
	var b: Creature = world.creatures[1]
	world.brains[0].paused = true
	world.brains[1].paused = true
	b.global_position = a.global_position + Vector3(0.05, 0.0, 0.0)
	for i in 120:
		await get_tree().physics_frame
	var d := Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()
	assert_gt(d, (a.radius + b.radius) * 0.9, "auseinandergeschoben")
	world.brains[0].paused = false
	world.brains[1].paused = false


func test_hiring_a_stranger() -> void:
	var offer: GroupMember = world.game.offers[0]
	var c: Creature = world.creature_of(offer)
	assert_true(world.strangers.has(c))
	world.game.credits = offer.price
	assert_true(world.hire(offer))
	assert_false(world.strangers.has(c))
	assert_eq(world.members[c], offer)
	assert_eq(c.tag.text, offer.name, "Schild zeigt jetzt den Namen")
	assert_eq(world.game.credits, 0)


func test_push_share_prefers_priority_and_movers() -> void:
	var a: Creature = world.creatures[2]
	var b: Creature = world.creatures[3]
	a.priority = 2
	assert_lt(world._push_share(a, b), 0.5, "Aufgaben-Beteiligte stupsen andere beiseite")
	a.priority = 0
	a.velocity = Vector3(0.5, 0, 0)
	b.velocity = Vector3.ZERO
	assert_lt(world._push_share(a, b), 0.5, "wer läuft, schiebt Stehende beiseite")
	assert_true(world.brains[2].mover.yields_to_me(b), "Stehende werden nicht umgangen")
	a.velocity = Vector3.ZERO


func test_cycling_through_creatures() -> void:
	var order: Array = world.browse_order()
	assert_eq(order.size(), world.game.members.size() + world.game.offers.size())
	world._select(order[0])
	world.cycle_selection(1)
	assert_eq(world.selected, order[1])
	world.cycle_selection(-1)
	world.cycle_selection(-1)
	assert_eq(world.selected, order[-1], "blättert rundum")
	world._select(null)


func test_tempo_speeds_up_everything() -> void:
	world.set_tempo(2)
	assert_eq(Engine.time_scale, 2.0, "Kreaturen und Aufgaben laufen mit")
	assert_eq(world._time_button.text, "Tempo ×2")
	world.set_tempo(1)
	assert_eq(world._time_button.text, "Tempo ×1.5")
	world.set_tempo(world.TIME_SCALES.size() - 1)
	assert_eq(Engine.time_scale, 0.0)
	assert_eq(world._time_button.text, "Pause")
	for s in world.TIME_SCALES:
		assert_lte(s, 4.0, "nicht zu schnell")
	world.set_tempo(0)
	assert_eq(Engine.time_scale, 1.0)


func test_pick_roles_by_tapping() -> void:
	var t: TaskDef = world.tasks.tasks[0]
	var role: String = t.roles[0].id
	world._begin_pick(t, role)
	var tired: GroupMember = world.game.members[1]
	tired.exhausted = true
	assert_false(world.pick_creature(world.creature_of(tired)), "Erschöpfte können nicht")
	if not world.strangers.is_empty():
		assert_false(world.pick_creature(world.strangers.keys()[0]), "Fremde erst anheuern")
	assert_true(world.pick_creature(world.creature_of(world.game.members[0])))
	assert_true(world._picking.is_empty())
	assert_true(world._task_panel.visible, "Panel wieder offen")
	assert_eq(world._task_panel._choice[role], world.game.members[0].id)
	tired.exhausted = false
	world._task_panel.visible = false


func test_bait_starts_trials() -> void:
	var tree: FruitTree = world.terrain.fruit_trees[0]
	var c: Creature = world.creatures[0]
	c.global_position = tree.global_position + Vector3(3, 0, 0)
	world.game.credits = 20
	var credits: int = world.game.credits
	var bait: Bait = world.place_bait(tree.global_position + Vector3(0.5, 0, 0))
	assert_not_null(bait)
	assert_eq(bait.kind, "tree")
	assert_eq(world.game.credits, credits - 1, "Köder kostet eine Beere")
	assert_false(world._bait_trials.is_empty(), "Kreaturen in der Nähe probieren es")
	assert_eq(world._bait_trials[0].behavior.id, "climb_tree")
	var l: ForestLayout = world.terrain.layout
	var s: Vector2 = l.stream_info(tree.global_position.x, tree.global_position.z).closest
	var w: Bait = world.place_bait(Vector3(s.x, 0, s.y))
	assert_eq(w.kind, "water")
	for t in world._bait_trials:
		assert_eq(t.behavior.id, "swim")
		t.brain.stop_current()
	world._bait_trials.clear()


func test_wait_jumps_to_evening() -> void:
	world.day_night.hour = 10.0
	world.wait_until_next()
	await get_tree().create_timer(2.0).timeout
	assert_almost_eq(world.day_night.hour, world.EVENING_HOUR, 0.2)
	world.day_night.hour = 10.0


func test_pick_by_browsing_with_filters() -> void:
	var t: TaskDef = world.tasks.tasks[0]
	world._begin_pick(t, t.roles[0].id)
	assert_true(world._card.visible)
	assert_eq(world._card.mode, "pick")
	assert_eq(world._picking.list.size(), world.game.members.size(), "Filter Gruppe: alle Mitglieder")
	var first: Creature = world._picking.list[0]
	world.cycle_selection(1)
	assert_ne(world._picking.list[world._picking.index], first, "‹ › blättert in der Rollenwahl")
	assert_eq(world.camera.follow, world._picking.list[world._picking.index], "Kamera folgt")
	world._card.filter_changed.emit("strangers")
	for c in world._picking.list:
		assert_true(world.strangers.has(c), "Filter Fremde")
	world._card.filter_changed.emit("group")
	world._confirm_pick()
	assert_true(world._picking.is_empty())
	assert_true(world._task_panel._choice.has(t.roles[0].id), "Rolle besetzt")
	world._task_panel.visible = false


func test_card_sits_at_bottom_and_shifts_camera() -> void:
	world._select(world.creatures[0])
	await get_tree().process_frame
	var vp: Vector2 = world._card.get_viewport_rect().size
	assert_gt(world._card.get_global_rect().position.y, vp.y * 0.5, "Leiste unten")
	assert_gt(world.camera.view_shift, 0.0, "Kreatur rückt nach oben")
	world._select(null)
	assert_eq(world.camera.view_shift, 0.0)


func test_rival_attempt_and_hire_events() -> void:
	var r: RivalState = world.game.rivals[0]
	var t: TaskDef = world.tasks.get_task("fruit_from_tree")
	var climber: GroupMember = r.members[0]
	r.new_morning()
	world.game.refill_sites()
	r.set_belief(climber.id, "climb", 0.95)
	var stock_before: int = world.game.site_stock(t)
	var ev := RivalAI.act(world.game, r, world.tasks, world.catalog, RandomNumberGenerator.new())
	assert_eq(ev.type, "task", "zuversichtliche Rivalen versuchen eine Aufgabe")
	world._on_rival_event(r, ev)
	if ev.result.success and ev.task.site == t.site:
		assert_eq(world.game.site_stock(t), stock_before - 1, "verbraucht den Vorrat")
	assert_gt(world._ticker.get_child_count(), 0, "Meldung oben rechts")
	# Anheuern: ein Fremder wird zum Rivalen, ein neuer kommt nach
	r.credits = 500
	var hire := RivalAI._hire(world.game, r, world.catalog, RandomNumberGenerator.new())
	assert_eq(hire.type, "hire")
	world._on_rival_event(r, hire)
	assert_true(world.rival_creatures.has(world.creature_of(hire.member)))
	assert_eq(world.game.offers.size(), int(GameState.progression().offers), "Fremde werden aufgefüllt")
	world.sync_sites()


func test_season_rollover() -> void:
	var g: GameState = world.game
	g.points = 120
	g.rivals[0].points = 60
	g.season.day = g.season.days
	world._on_new_day()
	assert_true(world._season_panel.visible, "Schlusswertung")
	var res: Dictionary = g.season.history[-1]
	assert_true(res.won)
	assert_eq(res.suggest, "ehrgeizig", "deutlicher Sieg: stärkere Rivalen vorschlagen")
	world._season_panel.visible = false
	world._start_next_season("ehrgeizig")
	assert_eq(int(g.season.number), 2)
	assert_eq(g.points, 0)
	assert_eq(g.rivals[0].points, 0)
	assert_eq(g.difficulty, "ehrgeizig")
	assert_eq(world.rival_creatures.size(), g.rivals[0].members.size(), "neue Rivalen im Lager")
	world._start_next_season("normal")


func test_interrupted_task_is_resumed_on_start() -> void:
	var t: TaskDef = world.tasks.get_task("fruit_from_tree")
	var m: GroupMember = world.game.members[0]
	m.exhausted = false
	var result := {"success": true, "roles": {"climber": {"success": true, "skipped": false, "score": 0.9, "threshold": 0.5, "close": false}}, "hints": []}
	world.game.pending_task = {"task": t.id, "assignments": {"climber": m.id}, "result": result}
	var attempts: int = world.game.tasks.get(t.id, {}).get("attempts", 0)
	world._resume_pending_task()
	assert_eq(world.game.tasks[t.id].attempts, attempts + 1, "Ergebnis wird nachgetragen")
	assert_true(world.game.pending_task.is_empty())
	assert_true(world._result_panel.visible, "Auswertung erscheint")
	world._result_panel.visible = false
	world._question.visible = false


func test_sound_only_from_focused_visible_creature() -> void:
	var a: Creature = world.creatures[0]
	var b: Creature = world.creatures[1]
	world._select(a)
	world.camera.target = a.global_position
	world.camera.distance = 8.0
	world.camera._apply()
	assert_true(world.is_sound_focus(a), "ausgewählte Kreatur im Bild ist hörbar")
	if b != world.camera.follow:
		assert_false(world.is_sound_focus(b), "andere Kreaturen bleiben still")
	world._select(null)
