extends TestCase
## A lot's default wall finish (#611): a woodland's street gives the shop log walls.
## Every face starts in the lot's finish, nothing is stored for it, Build can still
## finish any face otherwise (plain paint included), replacing the default refunds
## nothing, and a save keeps the faces finished otherwise when the lot gives the
## default again. Other lots keep plain paint.

const START_CASH: int = 1000
const WEST: int = 3

var _layout: ShopLayout
var _content: ContentDB
var _sim: RestaurantSim
var _ledger: Ledger


func before_each() -> void:
	_layout = LegacyTier1Layout.make()
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(_layout, _content, 1, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_ledger = Ledger.new()
	_ledger.cash = START_CASH


func after_each() -> void:
	_sim = null
	_content = null
	_ledger = null


func _editor(style_id: StringName, layout: ShopLayout = null, sim: RestaurantSim = null) -> ShopEditor:
	var editor: ShopEditor = ShopEditor.new(sim if sim != null else _sim, _content, ShopEditBooks.new(_can_spend, _record),
		layout if layout != null else _layout, style_id)
	editor.set_owner_level(6)
	return editor


func test_the_log_wall_finish_and_the_woodland_default() -> void:
	var logs: WallStyleDef = _content.wall_style(&"logs")
	assert_not_null(logs, "a log wall finish exists")
	assert_eq(int(logs.pattern), WallStyleDef.Pattern.LOGS)
	assert_true(logs.price > 0, "a priced finish on other lots")
	assert_not_null(_content.swatch(logs.default_swatch), "in a palette colour")
	var woodland: StreetPreset = load("res://data/streets/woodland.tres") as StreetPreset
	assert_eq(woodland.wall_style, &"logs", "a woodland cabin has log walls")
	for path: String in ["res://data/streets/starter.tres", "res://data/streets/seaside.tres", "res://data/streets/promenade.tres"]:
		assert_eq((load(path) as StreetPreset).wall_style, &"", "%s keeps plain paint" % path)


func test_the_concrete_panel_finish_and_the_rooftop_default() -> void:
	var concrete: WallStyleDef = _content.wall_style(&"concrete")
	assert_not_null(concrete, "a concrete panel wall finish exists (#618)")
	assert_eq(int(concrete.pattern), WallStyleDef.Pattern.CONCRETE)
	assert_eq(int(WallStyleDef.Pattern.CONCRETE), 7, "appended, never renumbered")
	assert_true(concrete.price > 0, "a priced finish on other lots")
	assert_true(concrete.unlock_level > 1, "bought later, like the log and mill finishes")
	assert_not_null(_content.swatch(concrete.default_swatch), "in a palette colour")
	var rooftop: StreetPreset = load("res://data/streets/rooftop.tres") as StreetPreset
	assert_eq(rooftop.wall_style, &"concrete", "the rooftop shop has concrete panel walls")
	# Its catalogue card draws panels: a dark reveal and a paler face than the paint.
	var main: Color = _content.swatch(concrete.default_swatch).color
	var accent: Color = WallFinishView.auto_accent(int(concrete.pattern), main, main)
	var card: Image = WallThumbnail.image(int(concrete.pattern), main, accent)
	var plain: Image = WallThumbnail.image(int(WallStyleDef.Pattern.PAINT), main, accent)
	assert_ne(card.get_data(), plain.get_data(), "the card is not plain paint")
	var reveal: Color = WallThumbnail.colour(int(concrete.pattern), Vector2(0.5, 0.3), main, accent)
	var face: Color = WallThumbnail.colour(int(concrete.pattern), Vector2(0.3, 0.3), main, accent)
	assert_true(reveal.get_luminance() < face.get_luminance(), "a dark reveal between panels")


func test_every_face_starts_as_the_lots_finish_with_nothing_stored() -> void:
	var editor: ShopEditor = _editor(&"logs")
	assert_eq(editor.default_wall_style, &"logs")
	assert_eq(editor.walls.count(), 0, "the default is not stored per face")
	for face: Vector3i in WallFaces.all(_sim.world.grid, true):
		assert_eq(editor.walls.finish(face).style, &"logs")
	# Other lots, and an unknown finish, keep plain paint.
	assert_eq(_editor(&"").walls.finish(Vector3i(1, 6, WEST)).style, WallStyleDef.DEFAULT_ID)
	assert_eq(_editor(&"no_such_finish").walls.finish(Vector3i(1, 6, WEST)).style, WallStyleDef.DEFAULT_ID)


func test_build_can_change_any_face_and_the_default_refunds_nothing() -> void:
	var editor: ShopEditor = _editor(&"logs")
	var faces: Array[Vector3i] = [Vector3i(1, 5, WEST), Vector3i(1, 6, WEST)]
	var paint: Dictionary[Vector3i, FloorFinishes.Finish] = editor.wall_lay_changes(faces, &"paint", &"")
	var check: EditCheck = editor.check_wall_finishes(paint)
	assert_true(check.ok, check.why)
	assert_eq([check.cost, check.refund], [0, 0], "plain paint is free and the lot's logs refund nothing")
	assert_true(editor.apply_wall_finishes(paint), editor.last_check.why)
	assert_eq(_ledger.cash, START_CASH)
	assert_eq(editor.walls.finish(faces[0]).style, WallStyleDef.DEFAULT_ID, "painted over the logs")
	assert_eq(editor.walls.count(), 2, "a face unlike the lot's default is stored")
	var brick: Dictionary[Vector3i, FloorFinishes.Finish] = editor.wall_lay_changes([Vector3i(1, 7, WEST)] as Array[Vector3i], &"brick", &"brick")
	check = editor.check_wall_finishes(brick)
	assert_eq([check.cost, check.refund], [4, 0], "a new finish costs its price; the logs it replaces refund nothing")
	# Back to the lot's own logs: stored nothing again.
	assert_true(editor.apply_wall_finishes(editor.wall_lay_changes(faces, &"logs", _layout.wall_swatch_id)))
	assert_eq(editor.walls.count(), 0)


func test_a_save_keeps_the_faces_finished_otherwise() -> void:
	var editor: ShopEditor = _editor(&"logs")
	var face: Vector3i = Vector3i(1, 6, WEST)
	assert_true(editor.apply_wall_finishes(editor.wall_lay_changes([face] as Array[Vector3i], &"paint", &"")))
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(editor.to_dict()))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snapshot, _layout, _content, errors)
	assert_eq(errors, [] as Array[String])
	var restored: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, false, true)
	var copy: ShopEditor = _editor(&"logs", layout, restored)
	assert_eq(copy.walls.finish(face).style, WallStyleDef.DEFAULT_ID, "the painted face stays painted")
	assert_eq(copy.walls.finish(Vector3i(1, 7, WEST)).style, &"logs", "the rest are the lot's logs again")
	assert_eq(copy.walls.to_rows(), editor.walls.to_rows())


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)
