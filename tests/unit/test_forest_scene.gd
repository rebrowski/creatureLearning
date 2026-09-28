extends GutTest
## Die gebaute Waldszene: Gelände, Kontext, Navigation, Startgruppe.

const SCENE := "res://scenes/world/forest.tscn"
var world: Node3D


func before_all() -> void:
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
	assert_eq(world.creatures.size(), 16)
	for c in world.creatures:
		var zone: String = world.terrain.layout.zone_at(c.global_position.x, c.global_position.z)
		assert_true(zone in ["clearing", "forest", "bank", "tree", "rock"], "%s steht in %s" % [c.name, zone])
