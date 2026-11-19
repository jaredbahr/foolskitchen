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


func test_skip_and_a_click_end_it_at_once() -> void:
	_make()
	var ends: Array[bool] = []
	_ride.finished.connect(ends.append)
	assert_true(_ride.play(_map(), _road(), "A joke.", 2.0))
	_ride.skip()
	assert_false(_ride.is_playing())
	assert_false(_ride.visible)
	assert_eq(ends, [true] as Array[bool])
	assert_true(_ride.play(_map(), _road(), "A joke.", 2.0))
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_ride._gui_input(click)
	assert_false(_ride.is_playing(), "a click skips")
	assert_eq(ends.size(), 2)
	_ride.skip()
	assert_eq(ends.size(), 2, "ending twice says nothing twice")


func test_it_ends_on_its_own_without_a_skip() -> void:
	_make()
	var ends: Array[bool] = []
	_ride.finished.connect(ends.append)
	assert_true(_ride.play(_map(), _road(), "", 0.5, 0.0))
	_ride.tick(0.6)
	assert_eq(ends, [false] as Array[bool])
	assert_eq(_ride.line_alpha(), 0.0, "no line, nothing to fade in")
