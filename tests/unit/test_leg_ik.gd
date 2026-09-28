extends GutTest
## Analytische 2-Knochen-IK.


func test_reachable_target_is_hit_exactly() -> void:
	var hip := Vector3(0, 1, 0)
	var target := Vector3(0.3, 0.2, -0.2)
	var r := LegIK.solve(hip, target, 0.6, 0.6, Vector3.FORWARD)
	assert_almost_eq(r.foot.distance_to(target), 0.0, 0.0001)
	assert_almost_eq(hip.distance_to(r.knee), 0.6, 0.0001, "Oberschenkellänge")
	assert_almost_eq(r.knee.distance_to(r.foot), 0.6, 0.0001, "Unterschenkellänge")


func test_unreachable_target_is_clamped() -> void:
	var hip := Vector3.ZERO
	var r := LegIK.solve(hip, Vector3(0, -5, 0), 0.5, 0.4, Vector3.FORWARD)
	assert_almost_eq(hip.distance_to(r.foot), 0.9, 0.001)
	assert_almost_eq(r.foot.x, 0.0, 0.0001)


func test_knee_bends_toward_pole() -> void:
	var hip := Vector3(0, 1, 0)
	var target := Vector3(0, 0, 0)
	var fwd := LegIK.solve(hip, target, 0.6, 0.6, Vector3.FORWARD)
	var up_out := LegIK.solve(hip, target, 0.6, 0.6, Vector3.RIGHT)
	assert_lt(fwd.knee.z, -0.1, "Knie nach vorne (-Z)")
	assert_gt(up_out.knee.x, 0.1, "Knie nach rechts")


func test_degenerate_pole_still_valid() -> void:
	var r := LegIK.solve(Vector3.ZERO, Vector3(0, -0.8, 0), 0.5, 0.5, Vector3.DOWN)
	assert_almost_eq(r.knee.length(), 0.5, 0.001)
	assert_false(is_nan(r.knee.x))


func test_bone_basis_points_minus_y_along_bone() -> void:
	var from := Vector3(0, 1, 0)
	var to := Vector3(0.5, 0.2, -0.3)
	var b := LegIK.bone_basis(from, to)
	var dir := (to - from).normalized()
	assert_almost_eq((b * Vector3.DOWN).distance_to(dir), 0.0, 0.0001)
	assert_almost_eq(b.determinant(), 1.0, 0.0001, "reine Rotation")
