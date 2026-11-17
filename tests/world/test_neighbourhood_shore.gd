extends TestCase
## The beach behind a seaside street (#588): the seaside preset has a shore and the
## starter street does not; the shore lies wholly behind the lot past the back lane;
## its motion is a pure function of the street clock; the beach fills by day, keeps
## a few for the sunset and empties at night; the view can pan out over it.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const CAMERA: PackedScene = preload("res://src/world/camera_rig.tscn")
const SEASIDE: String = "res://data/streets/seaside.tres"
const RESERVE: Rect2i = Rect2i(-2, -2, 12, 9)

var _viewport: SubViewport


func after_each() -> void:
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	NeighbourhoodDressing.clear_mesh_cache()


func _host() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)


func _dressing(preset: StreetPreset) -> NeighbourhoodDressing:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"########", "#......#", "#......#", "#......#", "#......#", "#......#", "###..###", "   EE   "]))
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	dressing.use_preset(preset)
	dressing.configure(grid, RESERVE, [{"cells": grid.entries().duplicate(), "normal": Vector2i.DOWN}] as Array[Dictionary],
		[] as Array[AABB])
	return dressing


func test_the_seaside_street_has_a_shore_and_the_starter_street_does_not() -> void:
	var seaside: StreetPreset = load(SEASIDE) as StreetPreset
	assert_not_null(seaside.shore, "the seaside street has a beach")
	assert_eq(seaside.shore.errors(), PackedStringArray())
	assert_null(StreetPreset.starter().shore, "the starter street keeps its meadow")
	var broken: StreetPreset = seaside.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as StreetPreset
	broken.shore.umbrella_colors.clear()
	assert_false(broken.errors().is_empty(), "a shore with no umbrella colours is refused")


func test_the_shore_is_built_behind_the_lot_and_only_on_a_shore_street() -> void:
	await _host()
	var seaside: NeighbourhoodDressing = _dressing(load(SEASIDE) as StreetPreset)
	var starter: NeighbourhoodDressing = _dressing(StreetPreset.starter())
	assert_eq(seaside.build_error, "")
	assert_eq(starter.build_error, "")
	assert_null(starter.shore(), "no beach on the starter street")
	var shore: NeighbourhoodShore = seaside.shore()
	assert_not_null(shore, "the seaside street builds its beach")
	var skin: ShoreSkin = seaside.preset.shore
	assert_eq(shore.gulls.size(), skin.gulls)
	assert_eq(shore.boats.size(), skin.boats)
	assert_eq(shore.bathers.size(), skin.sunbathers + skin.waders)
	assert_not_null(seaside.find_child("Sea", true, false), "the sea")
	# Local z falls toward the sea: the lane is past the lot, the waterline past the lane.
	var lot_back: float = (seaside.local_frame().affine_inverse() * AABB(Vector3(RESERVE.position.x, 0.0, RESERVE.position.y) * GridMath.CELL_SIZE,
		Vector3(RESERVE.size.x, 1.0, RESERVE.size.y) * GridMath.CELL_SIZE)).position.z
	assert_true(shore.lane_v < lot_back, "the back lane runs behind the lot")
	assert_true(shore.waterline_z() < shore.lane_v - 3.0, "the beach lies past the lane")
	for index: int in skin.umbrellas:
		assert_true(shore.umbrella_spot(index).y < shore.lane_v - 1.0, "umbrella %d stands on the beach" % index)
		assert_true(shore.umbrella_spot(index).y > shore.waterline_z() + 1.0, "umbrella %d stays out of the surf" % index)
	for bather: NeighbourhoodShore.Bather in shore.bathers:
		assert_true(bather.at.z < shore.lane_v - 1.0, "every beachgoer is past the lane")
	seaside.get_parent().remove_child(seaside)
	seaside.free()
	starter.get_parent().remove_child(starter)
	starter.free()


func test_shore_motion_is_a_pure_function_of_the_street_clock() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(SEASIDE) as StreetPreset)
	var shore: NeighbourhoodShore = dressing.shore()
	var snapshot: Callable = func() -> Array:
		var values: Array = []
		for node: Node3D in shore.gulls + shore.boats:
			values.append(node.transform)
		for bather: NeighbourhoodShore.Bather in shore.bathers:
			values.append(bather.person.transform)
		values.append(shore.beam.transform)
		values.append(shore.sea_material.get_shader_parameter(&"sea_time"))
		return values
	dressing.set_review_time(12.5)
	var first: Array = snapshot.call()
	dressing.set_review_time(40.0)
	var moved: Array = snapshot.call()
	dressing.set_review_time(12.5)
	assert_eq(snapshot.call(), first, "the same time shows the same frame")
	assert_ne(moved, first, "gulls, boats and the beam move with time")
	assert_eq(float(first[first.size() - 1]), 12.5, "the sea runs on the street clock, not the engine's")
	dressing.get_parent().remove_child(dressing)
	dressing.free()


func test_the_beach_fills_by_day_keeps_a_few_for_the_sunset_and_empties_at_night() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(SEASIDE) as StreetPreset)
	var shore: NeighbourhoodShore = dressing.shore()
	var all: int = shore.bathers.size()
	dressing.set_night(0.0, 0.0)
	var day: Dictionary = shore.capture_state()
	assert_eq(int(day["visible_bathers"]), all, "everyone is out by day")
	assert_true(day["day_props"], "umbrellas up and towels out")
	assert_false(day["beam"], "no lighthouse beam by day")
	dressing.set_night(1.0, 0.0)
	var dusk: Dictionary = shore.capture_state()
	assert_true(int(dusk["visible_bathers"]) > 0 and int(dusk["visible_bathers"]) < all, "a few stay for the sunset")
	assert_false(dusk["day_props"], "the umbrellas are furled")
	assert_true(dusk["beam"], "the lighthouse is lit")
	dressing.set_night(1.0, 1.0)
	var night: Dictionary = shore.capture_state()
	assert_eq(int(night["visible_bathers"]), 0, "everyone has gone home")
	for gull: Node3D in shore.gulls:
		assert_false(gull.visible, "the gulls roost")
	dressing.get_parent().remove_child(dressing)
	dressing.free()


func test_the_view_can_pan_out_over_the_beach_as_far_as_the_street() -> void:
	await _host()
	var rig: CameraRig = CAMERA.instantiate() as CameraRig
	_viewport.add_child(rig)
	rig.frame_area(Vector2.ZERO, Vector2(5.0, 5.0), 15.0, true)
	assert_true(rig.set_street_pan_extension(Vector2i.DOWN, 3.0))
	var street_only: Rect2 = rig._focus_bounds()
	assert_true(rig.set_shore_pan_extension(Vector2i.UP, 3.0))
	var both: Rect2 = rig._focus_bounds()
	assert_eq(both.end.y, street_only.end.y, "the street side is unchanged")
	assert_almost_eq(both.position.y, street_only.position.y - 3.0, 0.001, "the beach side reaches 3 m further")
	assert_false(rig.set_shore_pan_extension(Vector2i(1, 1), 3.0), "only a cardinal side")
	rig.frame_area(Vector2.ZERO, Vector2(5.0, 5.0), 15.0, true)
	assert_eq(rig._focus_bounds(), Rect2(-5.0, -5.0, 10.0, 10.0), "a new framing clears both extensions")
