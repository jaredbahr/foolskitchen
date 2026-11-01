extends TestCase
## A placed chalkboard owns its menu-section choice. Saving and undoing wall
## edits preserve that choice without changing ordinary wall decor rows.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const WEST: int = 3
const EAST: int = 1

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _ledger: Ledger
var _changed_count: int = 0


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_ledger = Ledger.new()
	_ledger.cash = 1000
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)
	_changed_count = 0
	_editor.decor.changed.connect(_on_decor_changed)


func after_each() -> void:
	_history = null
	_editor = null
	_sim = null
	_content = null
	_ledger = null


func test_section_choice_is_per_board_and_only_effective_changes_notify() -> void:
	var first: Vector3i = Vector3i(1, 7, WEST)
	var second: Vector3i = Vector3i(1, 9, WEST)
	var art: Vector3i = Vector3i(3, 1, 0)
	assert_true(_editor.hang(&"menu_board", first), _editor.last_check.why)
	assert_true(_editor.hang(&"menu_board", second), _editor.last_check.why)
	assert_true(_editor.hang(&"wall_art_peaks", art), _editor.last_check.why)
	assert_eq(_editor.decor.item(first).menu_section, -1)
	assert_eq(_editor.decor.item(second).menu_section, -1)
	var revision: int = _editor.decor.revision
	var notices: int = _changed_count
	assert_false(_editor.set_menu_board_section(Vector3i(2, 6, WEST), RecipeDef.Section.MAINS))
	assert_false(_editor.set_menu_board_section(art, RecipeDef.Section.MAINS))
	assert_false(_editor.set_menu_board_section(first, -2))
	assert_false(_editor.set_menu_board_section(first, RecipeDef.Section.BAKERY + 1))
	assert_eq(_editor.decor.revision, revision)
	assert_eq(_changed_count, notices)
	assert_true(_editor.set_menu_board_section(first, RecipeDef.Section.MAINS))
	assert_eq(_editor.decor.revision, revision + 1)
	assert_eq(_changed_count, notices + 1)
	assert_true(_editor.set_menu_board_section(first, RecipeDef.Section.MAINS))
	assert_eq(_editor.decor.revision, revision + 1, "choosing the same section does not redraw")
	assert_eq(_changed_count, notices + 1)
	assert_true(_editor.set_menu_board_section(second, RecipeDef.Section.DRINKS))
	assert_eq(_editor.decor.item(first).menu_section, RecipeDef.Section.MAINS)
	assert_eq(_editor.decor.item(second).menu_section, RecipeDef.Section.DRINKS)
	assert_eq(_editor.decor.item(art).menu_section, -1)
	assert_true(_editor.set_menu_board_section(first, -1))
	assert_eq(_editor.decor.item(first).menu_section, -1)
	assert_eq(_editor.decor.revision, revision + 3)
	assert_eq(_changed_count, notices + 3)
	assert_eq(_editor.to_dict()["wall_items"], [
		[3, 1, 0, "wall_art_peaks"], [1, 7, WEST, "menu_board"],
		[1, 9, WEST, "menu_board", RecipeDef.Section.DRINKS],
	] as Array[Array])
	var cash: int = _ledger.cash
	var rng_state: int = _sim.rng.state
	_sim.world.clock.phase = SimClock.Phase.OPEN
	assert_true(_editor.set_menu_board_section(first, RecipeDef.Section.BAKERY), "the inspect choice is available during service")
	assert_eq(_editor.decor.item(second).menu_section, RecipeDef.Section.DRINKS)
	assert_eq(_ledger.cash, cash)
	assert_eq(_sim.rng.state, rng_state)


func test_snapshot_restores_distinct_sections_and_legacy_rows() -> void:
	var first: Vector3i = Vector3i(1, 7, WEST)
	var second: Vector3i = Vector3i(1, 9, WEST)
	assert_true(_editor.hang(&"menu_board", first), _editor.last_check.why)
	assert_true(_editor.hang(&"menu_board", second), _editor.last_check.why)
	assert_true(_editor.set_menu_board_section(first, RecipeDef.Section.DESSERTS))
	assert_true(_editor.set_menu_board_section(second, RecipeDef.Section.STARTERS))
	var expected: Array[Array] = [
		[1, 7, WEST, "menu_board", RecipeDef.Section.DESSERTS],
		[1, 9, WEST, "menu_board", RecipeDef.Section.STARTERS],
	]
	assert_eq(_editor.to_dict()["wall_items"], expected)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	var copy: ShopEditor = _restore(snapshot)
	assert_eq(copy.decor.item(first).menu_section, RecipeDef.Section.DESSERTS)
	assert_eq(copy.decor.item(second).menu_section, RecipeDef.Section.STARTERS)
	assert_eq(copy.to_dict()["wall_items"], expected)
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy["wall_items"] = [[1, 7, WEST, "menu_board"], [1, 9, WEST, "menu_board", RecipeDef.Section.STARTERS]]
	copy = _restore(legacy)
	assert_eq(copy.decor.item(first).menu_section, -1)
	assert_eq(copy.decor.item(second).menu_section, RecipeDef.Section.STARTERS)
	assert_eq(copy.to_dict()["wall_items"], [
		[1, 7, WEST, "menu_board"], [1, 9, WEST, "menu_board", RecipeDef.Section.STARTERS],
	] as Array[Array])


func test_bad_saved_sections_keep_the_board_in_automatic_mode() -> void:
	var anchor: Vector3i = Vector3i(1, 7, WEST)
	var base: Dictionary = _editor.to_dict()
	var invalid: Array[Variant] = [null, "Mains", [], -2, RecipeDef.Section.BAKERY + 1, 1.5]
	for value: Variant in invalid:
		var saved: Dictionary = base.duplicate(true)
		saved["wall_items"] = [[1, 7, WEST, "menu_board", value]]
		var copy: ShopEditor = _restore(saved)
		assert_not_null(copy.decor.item(anchor), "a bad section never loses the board")
		assert_eq(copy.decor.item(anchor).menu_section, -1)
		assert_eq(copy.to_dict()["wall_items"], [[1, 7, WEST, "menu_board"]] as Array[Array])


func test_hang_move_sale_and_wall_loss_undo_keep_the_section() -> void:
	var wall: Dictionary[Vector3i, int] = _segments(9, 5, 8, SimGrid.Segment.WALL)
	assert_true(_history.apply_segments(wall), _editor.last_check.why)
	var first: Vector3i = Vector3i(9, 7, WEST)
	var second: Vector3i = Vector3i(9, 8, WEST)
	assert_true(_history.hang(&"menu_board", first), _editor.last_check.why)
	assert_true(_editor.set_menu_board_section(first, RecipeDef.Section.BAKERY))
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.decor.count(), 0)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_editor.decor.item(first).menu_section, RecipeDef.Section.BAKERY, "redo of hang")
	assert_true(_history.rehang(first, second), _editor.last_check.why)
	assert_eq(_editor.decor.item(second).menu_section, RecipeDef.Section.BAKERY)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.decor.item(first).menu_section, RecipeDef.Section.BAKERY, "undo of move")
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_editor.decor.item(second).menu_section, RecipeDef.Section.BAKERY, "redo of move")
	assert_true(_history.take_down(second) >= 0, _editor.last_check.why)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.decor.item(second).menu_section, RecipeDef.Section.BAKERY, "undo of sale")
	assert_true(_history.redo(), _history.last_refusal)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.decor.item(second).menu_section, RecipeDef.Section.BAKERY, "sale round trip")
	assert_true(_history.apply_segments(_segments(9, 5, 8, SimGrid.Segment.NONE)), _editor.last_check.why)
	assert_eq(_editor.decor.count(), 0)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.decor.item(second).menu_section, RecipeDef.Section.BAKERY, "wall loss undo")
	assert_true(_editor.set_menu_board_section(second, RecipeDef.Section.MAINS))
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_editor.decor.count(), 0)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.decor.item(second).menu_section, RecipeDef.Section.MAINS, "wall loss redo keeps later choice")


func test_expanding_floor_then_undo_restores_the_board_section() -> void:
	var anchor: Vector3i = Vector3i(12, 2, EAST)
	assert_true(_history.hang(&"menu_board", anchor), _editor.last_check.why)
	assert_true(_editor.set_menu_board_section(anchor, RecipeDef.Section.SIDES))
	var bought: Array[Vector2i] = []
	for y: int in range(0, 10):
		bought.append(Vector2i(14, y))
	assert_true(_history.apply_floor(bought, true), _editor.last_check.why)
	assert_eq(_editor.decor.count(), 0)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.decor.item(anchor).menu_section, RecipeDef.Section.SIDES)
	assert_true(_editor.set_menu_board_section(anchor, RecipeDef.Section.DRINKS))
	assert_true(_history.redo(), _history.last_refusal)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.decor.item(anchor).menu_section, RecipeDef.Section.DRINKS)


func _restore(snapshot: Dictionary) -> ShopEditor:
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	var restored: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, false, true)
	assert_eq(errors, [] as Array[String])
	return ShopEditor.new(restored, _content, ShopEditBooks.new(_can_spend, _record), layout)


func _segments(x: int, y0: int, y1: int, kind: int) -> Dictionary[Vector3i, int]:
	var out: Dictionary[Vector3i, int] = {}
	for y: int in range(y0, y1 + 1):
		out[Vector3i(x, y, SimGrid.EDGE_WEST)] = kind
	return out


func _on_decor_changed() -> void:
	_changed_count += 1


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)
