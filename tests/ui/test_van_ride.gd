extends TestCase
## The van ride picture (docs/CITY_MAP.md T5): it drives along its route in
## the time given, shows the commute line near the end, and any click or a
## skip ends it at once. Time is fed in by hand, so nothing waits.

var _ride: VanRide
var _screen: Control


func after_each() -> void:
	if is_instance_valid(_screen):
		if _screen.is_inside_tree():
			_screen.get_parent().remove_child(_screen)
		_screen.free()
	_screen = null
	_ride = null


func _map() -> Texture2D:
	return load("res://assets/made/city_map/paper_map.png") as Texture2D


func _road() -> PackedVector2Array:
	return CityMap.van_path(CityMap.load_default(), &"old_town", &"millbrook")


func _make() -> void:
	_screen = Control.new()
	_screen.size = Vector2(1600, 900)
	_ride = VanRide.new()
	_screen.add_child(_ride)
	(Engine.get_main_loop() as SceneTree).root.add_child(_screen)


func test_it_refuses_without_art_a_route_or_time() -> void:
	_make()
	assert_false(_ride.play(null, _road(), "x", 2.0))
	assert_false(_ride.play(_map(), PackedVector2Array([Vector2(0.1, 0.1)]), "x", 2.0))
	assert_false(_ride.play(_map(), _road(), "x", 0.0))
	assert_false(_ride.is_playing())
	assert_false(_ride.visible)


func test_the_van_drives_the_route_and_the_line_fades_in() -> void:
	_make()
	var path: PackedVector2Array = _road()
	assert_true(_ride.play(_map(), path, "A joke.", 2.0))
	assert_true(_ride.is_playing())
	assert_true(_ride.visible)
	assert_eq(_ride.van_position(), path[0], "it starts at the first neighbourhood")
	assert_eq(_ride.line_alpha(), 0.0, "no joke yet")
	_ride.tick(1.0)
	var middle: Vector2 = _ride.van_position()
	assert_ne(middle, path[0])
	assert_ne(middle, path[path.size() - 1])
	_ride.tick(0.9)
	assert_eq(_ride.line_alpha(), 1.0, "the joke is up by the end")
	_ride.tick(0.2)
	assert_true(_ride.van_position().is_equal_approx(path[path.size() - 1]))
	assert_true(_ride.is_playing(), "the line stays a moment")
	_ride.tick(VanRide.HOLD_SECONDS)
	assert_false(_ride.is_playing())
	assert_false(_ride.visible)


func test_the_first_skip_shows_the_arrival_and_the_line_and_the_second_ends_it() -> void:
	_make()
	var ends: Array[bool] = []
	_ride.finished.connect(ends.append)
	var path: PackedVector2Array = _road()
	assert_true(_ride.play(_map(), path, "A joke.", 2.0))
	_ride.tick(0.3)
	_ride.skip()
	assert_true(_ride.is_playing(), "the line is the payoff: it stays")
	assert_true(_ride.has_arrived())
	assert_true(_ride.van_position().is_equal_approx(path[path.size() - 1]))
	assert_eq(_ride.line_alpha(), 1.0, "the line is fully shown")
	assert_eq(ends.size(), 0)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_ride._gui_input(click)
	assert_false(_ride.is_playing(), "a second input ends it")
	assert_false(_ride.visible)
	assert_eq(ends, [true] as Array[bool])
	_ride.skip()
	assert_eq(ends.size(), 1, "ending twice says nothing twice")


func test_after_a_skip_it_ends_by_itself_within_about_a_second() -> void:
	_make()
	var ends: Array[bool] = []
	_ride.finished.connect(ends.append)
	assert_true(_ride.play(_map(), _road(), "A joke.", 2.0))
	_ride.skip()
	_ride.tick(VanRide.SKIP_HOLD_SECONDS - 0.1)
	assert_true(_ride.is_playing())
	_ride.tick(0.2)
	assert_false(_ride.is_playing())
	assert_eq(ends, [true] as Array[bool])


func test_a_skip_with_no_line_or_after_arrival_ends_at_once() -> void:
	_make()
	assert_true(_ride.play(_map(), _road(), "", 2.0))
	_ride.skip()
	assert_false(_ride.is_playing(), "nothing to read")
	assert_true(_ride.play(_map(), _road(), "A joke.", 2.0))
	_ride.tick(2.1)
	_ride.skip()
	assert_false(_ride.is_playing(), "already arrived")


func test_the_ride_runs_from_pin_to_pin_not_banner_to_banner() -> void:
	var map: CityMapDef = CityMap.load_default()
	var path: PackedVector2Array = VanRide.ride_path(map, &"home", &"skyscraper_rooftop")
	var sky: NeighbourhoodDef = map.neighbourhood(&"skyline")
	var end: Vector2 = path[path.size() - 1]
	assert_true(end.y > sky.map_position.y, "it parks below the banner")
	assert_eq(end, VanRide.pin_spot(sky, &"skyscraper_rooftop"))
	assert_eq(path[0], VanRide.pin_spot(map.neighbourhood(&"old_town"), &"home"))
	assert_eq(VanRide.ride_path(map, &"home", &"home").size(), 0)
	assert_eq(VanRide.ride_path(map, &"home", &"nowhere").size(), 0)
	var far: PackedVector2Array = VanRide.ride_path(map, &"woodland_cabin", &"home")
	assert_true(far.has(sky.map_position), "Pinewood to home still passes Skyline")


func test_it_ends_on_its_own_without_a_skip() -> void:
	_make()
	var ends: Array[bool] = []
	_ride.finished.connect(ends.append)
	assert_true(_ride.play(_map(), _road(), "", 0.5, 0.0))
	_ride.tick(0.6)
	assert_eq(ends, [false] as Array[bool])
	assert_eq(_ride.line_alpha(), 0.0, "no line, nothing to fade in")


func test_the_last_leg_goes_round_the_banner_not_across_it() -> void:
	var map: CityMapDef = CityMap.load_default()
	for pair: Array in [[&"home", &"skyscraper_rooftop"], [&"woodland_cabin", &"home"], [&"seaside_cliff", &"town_fixer_upper"]]:
		var path: PackedVector2Array = VanRide.ride_path(map, pair[0], pair[1])
		var ends: Array[Rect2] = [VanRide.banner(map.neighbourhood_for_lot(pair[0])),
			VanRide.banner(map.neighbourhood_for_lot(pair[1]))]
		for index: int in range(1, path.size()):
			# Only the legs that touch a pin: the roads between pass by the art's own way.
			if index == 1 or index == path.size() - 1 or index == 2 or index == path.size() - 2:
				for box: Rect2 in ends:
					if not box.has_point(path[index - 1]) and not box.has_point(path[index]):
						box = box.grow(-0.003)
						assert_false(VanRide.segment_hits(box, path[index - 1], path[index]),
							"%s to %s: leg %d crosses a banner" % [pair[0], pair[1], index])


func test_segment_hits_a_box() -> void:
	var box: Rect2 = Rect2(0.4, 0.4, 0.2, 0.1)
	assert_true(VanRide.segment_hits(box, Vector2(0.3, 0.45), Vector2(0.7, 0.45)))
	assert_true(VanRide.segment_hits(box, Vector2(0.5, 0.1), Vector2(0.5, 0.9)))
	assert_false(VanRide.segment_hits(box, Vector2(0.3, 0.3), Vector2(0.7, 0.3)))
	assert_false(VanRide.segment_hits(box, Vector2(0.1, 0.1), Vector2(0.3, 0.9)))
	assert_false(VanRide.segment_hits(box, Vector2(0.45, 0.6), Vector2(0.9, 0.9)))
