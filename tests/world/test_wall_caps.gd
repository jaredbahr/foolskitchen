extends TestCase
## The walls' top caps follow a lot's patterned default finish: concrete panels
## (the Skyline Rooftop) get a grey coping, log walls a wooden top, while plain
## paint and the finishes whose main colour covers only the wall's foot keep the
## authored cap.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _view: ShopView
var _content: ContentDB
var _sim: RestaurantSim


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_view = VIEW.instantiate() as ShopView
	(Engine.get_main_loop() as SceneTree).root.add_child(_view)
	_view.show_world(_sim.world)
	_view.set_paint(_content, &"", &"")


func after_each() -> void:
	if is_instance_valid(_view):
		_view.free()
	_sim = null
	_content = null


## Every top cap drawn: the shell cells' and the segment view's.
func _caps() -> Array[MeshInstance3D]:
	var caps: Array[MeshInstance3D] = []
	var pending: Array[Node] = [_view]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var shell_cap: bool = node.get_parent() != null and node.get_parent().has_meta(&"wall_cell")
		var segment_cap: bool = _view.segment_view != null and _view.segment_view.is_ancestor_of(node)
		if node.name == "Top" and node is MeshInstance3D and (shell_cap or segment_cap):
			caps.append(node as MeshInstance3D)
		pending.append_array(node.get_children())
	return caps


func _grey(colour: Color) -> bool:
	return maxf(colour.r, maxf(colour.g, colour.b)) - minf(colour.r, minf(colour.g, colour.b)) < 0.04


func test_plain_paint_keeps_the_authored_cap() -> void:
	_view.bind_wall_finishes(WallFinishes.new(), WallDecor.new())
	assert_true(_view.wall_cap_colour().is_equal_approx(_view.wall_top_color))
	var caps: Array[MeshInstance3D] = _caps()
	assert_true(caps.size() > 0)
	for cap: MeshInstance3D in caps:
		assert_true((cap.material_override as StandardMaterial3D).albedo_color.is_equal_approx(_view.wall_top_color))


func test_concrete_walls_have_grey_caps() -> void:
	_view.bind_wall_finishes(WallFinishes.new(&"concrete"), WallDecor.new())
	var colour: Color = _view.wall_cap_colour()
	assert_true(_grey(colour), "a concrete coping is grey, not tan: %s" % colour)
	assert_false(_grey(_view.wall_top_color), "the authored cap is the tan one")
	var pewter: Color = _content.swatch(_content.wall_style(&"concrete").default_swatch).color
	assert_true(colour.get_luminance() > pewter.get_luminance() * 0.9 and colour.get_luminance() < 1.0,
		"about the concrete face's own tone")
	var caps: Array[MeshInstance3D] = _caps()
	assert_true(caps.size() > 0)
	for cap: MeshInstance3D in caps:
		assert_true((cap.material_override as StandardMaterial3D).albedo_color.is_equal_approx(colour), "every cap follows the finish")


func test_caps_follow_the_finish_by_pattern() -> void:
	var tan: Color = Color("b9a789")
	var honey: Color = _content.swatch(&"honey").color
	var logs: Color = WallFinishView.cap_colour(WallStyleDef.Pattern.LOGS, honey, tan)
	assert_true(logs.is_equal_approx(Color(honey.r * 0.8, honey.g * 0.8, honey.b * 0.8)), "log walls get a wooden top")
	for pattern: int in [WallStyleDef.Pattern.PAINT, WallStyleDef.Pattern.WAINSCOT, WallStyleDef.Pattern.MILL]:
		assert_true(WallFinishView.cap_colour(pattern, honey, tan).is_equal_approx(tan), "pattern %d keeps the authored cap" % pattern)
