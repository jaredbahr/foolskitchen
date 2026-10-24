extends TestCase
## Pure floor-ray and drawn-position selection; no scene tree or sim required.


func test_empty_positions_have_no_pick() -> void:
	assert_eq(Picker.pick_agent(Vector3.ZERO, {}), -1)


func test_nearest_inside_radius_wins_over_lower_id() -> void:
	var positions: Dictionary = {
		2: Vector3(0.55, 0.0, 0.0),
		7: Vector3(0.15, 0.0, 0.0),
		1: Vector3(0.8, 0.0, 0.0),
	}
	assert_eq(Picker.pick_agent(Vector3.ZERO, positions), 7)


func test_radius_boundary_is_inclusive_on_both_axes_and_diagonal() -> void:
	var boundary: Array[Vector3] = [
		Vector3(0.6, 0.0, 0.0), Vector3(-0.6, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.6), Vector3(0.0, 0.0, -0.6),
		Vector3(0.36, 0.0, 0.48),
	]
	for position: Vector3 in boundary:
		assert_eq(Picker.pick_agent(Vector3.ZERO, {4: position}), 4)
	assert_eq(Picker.pick_agent(Vector3.ZERO, {4: Vector3(0.5999, 0.0, 0.0)}), 4)


func test_positions_outside_circle_are_not_picked() -> void:
	assert_eq(Picker.pick_agent(Vector3.ZERO, {4: Vector3(0.6001, 0.0, 0.0)}), -1)
	assert_eq(Picker.pick_agent(Vector3.ZERO, {4: Vector3(0.0, 0.0, -0.6001)}), -1)
	assert_eq(Picker.pick_agent(Vector3.ZERO, {4: Vector3(0.5, 0.0, 0.5)}), -1)


func test_exact_tie_uses_lowest_id_in_either_dictionary_order() -> void:
	var first: Dictionary = {9: Vector3(0.5, 0.0, 0.0), 3: Vector3(-0.5, 0.0, 0.0)}
	var reversed: Dictionary = {3: Vector3(-0.5, 0.0, 0.0), 9: Vector3(0.5, 0.0, 0.0)}
	assert_eq(Picker.pick_agent(Vector3.ZERO, first), 3)
	assert_eq(Picker.pick_agent(Vector3.ZERO, reversed), 3)
	assert_eq(Picker.pick_agent(Vector3.ZERO, {9: Vector3.ZERO, 3: Vector3.ZERO}), 3)


func test_close_but_unequal_distances_are_not_ties() -> void:
	var positions: Dictionary = {1: Vector3(0.500001, 0.0, 0.0), 9: Vector3(0.5, 0.0, 0.0)}
	assert_eq(Picker.pick_agent(Vector3.ZERO, positions), 9)


func test_supplied_interpolated_positions_are_used_without_mutation() -> void:
	var drawn: Vector3 = Vector3(0.25, 0.875, 0.25).lerp(Vector3(0.75, 0.875, 0.25), 0.75)
	var positions: Dictionary = {6: drawn, 2: Vector3(0.25, 0.875, 0.25)}
	var before: Dictionary = positions.duplicate()
	assert_eq(Picker.pick_agent(Vector3(0.625, 0.0, 0.25), positions), 6)
	assert_eq(positions, before)


func test_vertical_coordinates_do_not_affect_selection() -> void:
	var positions: Dictionary = {2: Vector3(0.25, 20.0, 0.25), 1: Vector3(0.35, -30.0, 0.25)}
	assert_eq(Picker.pick_agent(Vector3(0.25, -30.0, 0.25), positions), 2)


func test_floor_intersection_accepts_unnormalized_oblique_ray() -> void:
	assert_eq(Picker.floor_intersection(Vector3(1.0, 4.0, 3.0), Vector3(2.0, -2.0, -1.0)), Vector3(5.0, 0.0, 1.0))


func test_floor_intersection_accepts_upward_ray_from_below() -> void:
	assert_eq(Picker.floor_intersection(Vector3(1.0, -4.0, 3.0), Vector3(-2.0, 2.0, 1.0)), Vector3(-3.0, 0.0, 5.0))


func test_floor_intersection_rejects_parallel_and_zero_rays() -> void:
	assert_null(Picker.floor_intersection(Vector3.UP, Vector3.RIGHT))
	assert_null(Picker.floor_intersection(Vector3.ZERO, Vector3.FORWARD))
	assert_null(Picker.floor_intersection(Vector3.UP, Vector3.ZERO))


func test_floor_intersection_rejects_hits_behind_origin() -> void:
	assert_null(Picker.floor_intersection(Vector3.UP, Vector3.UP))
	assert_null(Picker.floor_intersection(Vector3.DOWN, Vector3.DOWN))


func test_floor_intersection_accepts_origin_on_floor() -> void:
	var origin: Vector3 = Vector3(-2.0, 0.0, 3.0)
	assert_eq(Picker.floor_intersection(origin, Vector3(1.0, 2.0, 3.0)), origin)


func test_floor_intersection_does_not_treat_shallow_ray_as_parallel() -> void:
	assert_eq(Picker.floor_intersection(Vector3.UP, Vector3(0.0, -0.000001, 0.0)), Vector3.ZERO)
