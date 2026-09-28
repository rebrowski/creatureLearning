extends GutTest
## Schrittmuster pro Beinzahl und Gangart.

func _leg(pair: int, side: int) -> int:
	return pair * 2 + side


func test_sizes() -> void:
	for legs in [0, 2, 4, 6, 8]:
		for gait in ["walk", "trot", "hop", "scuttle", "slither"]:
			assert_eq(GaitTable.offsets(legs, gait).size(), legs)


func test_biped_alternates_and_hops_together() -> void:
	var walk := GaitTable.offsets(2, "walk")
	assert_almost_eq(absf(walk[0] - walk[1]), 0.5, 0.0001)
	var hop := GaitTable.offsets(2, "hop")
	assert_eq(hop[0], hop[1])


func test_trot_moves_diagonal_pairs_together() -> void:
	var o := GaitTable.offsets(4, "trot")
	assert_eq(o[_leg(0, 0)], o[_leg(1, 1)], "links vorne + rechts hinten")
	assert_eq(o[_leg(0, 1)], o[_leg(1, 0)], "rechts vorne + links hinten")
	assert_ne(o[_leg(0, 0)], o[_leg(0, 1)])


func test_walk_quadruped_uses_four_phases() -> void:
	var o := GaitTable.offsets(4, "walk")
	var phases := {}
	for v in o:
		phases[snappedf(v, 0.01)] = true
	assert_eq(phases.size(), 4)


func test_hexapod_tripod() -> void:
	for gait in ["scuttle", "trot"]:
		var o := GaitTable.offsets(6, gait)
		# Dreifuß: L1, R2, L3 gemeinsam, gegenphasig zu R1, L2, R3
		assert_eq(o[_leg(0, 0)], o[_leg(1, 1)])
		assert_eq(o[_leg(0, 0)], o[_leg(2, 0)])
		assert_almost_eq(absf(o[_leg(0, 0)] - o[_leg(0, 1)]), 0.5, 0.0001)
		assert_almost_eq(absf(o[_leg(0, 0)] - o[_leg(1, 0)]), 0.5, 0.0001)


func test_never_all_legs_in_swing_for_walking_gaits() -> void:
	for legs in [4, 6, 8]:
		for gait in ["walk", "trot", "scuttle"]:
			var o := GaitTable.offsets(legs, gait)
			var swing := 1.0 - GaitTable.duty(gait)
			for step in 100:
				var phase := step / 100.0
				var planted := 0
				for v in o:
					if fposmod(phase + v, 1.0) >= swing:
						planted += 1
				assert_gte(planted, 2, "%d Beine %s bei Phase %.2f" % [legs, gait, phase])
