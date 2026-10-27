extends TestCase
## The request-only Stock panel: player text, requests, and its fit at the
## usual 1600x900 window and at the 150% UI scale.

const PANEL_SCENE: PackedScene = preload("res://src/ui/stock_panel.tscn")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")

var _panel: StockPanel
var _host: SubViewport
var _requests: Array[Array] = []


func before_each() -> void:
	_panel = PANEL_SCENE.instantiate() as StockPanel
	_requests.clear()


func after_each() -> void:
	if is_instance_valid(_host):
		_host.free()
	elif is_instance_valid(_panel):
		_panel.free()


func _rows() -> Array[Dictionary]:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var rows: Array[Dictionary] = []
	for id: StringName in TUNING.morning_stock:
		var ingredient: IngredientDef = content.ingredient(id)
		rows.append({"id": id, "name": ingredient.display_name, "count": 10, "expiring": 3 if id == &"beef_patty" else 0,
			"unit_cost": ingredient.unit_cost, "enabled": id != &"cheese", "target": TUNING.morning_stock[id],
			"max_target": ReorderSettings.MAX_TARGET})
	return rows


func test_rows_show_names_counts_and_send_requests() -> void:
	_panel.buy_requested.connect(_on_buy)
	_panel.auto_requested.connect(_on_auto)
	_panel.target_requested.connect(_on_target)
	_panel.set_stock(_rows(), 3, true, ["This morning's auto-order cost $93 ($88 at list price + $5 premium)."] as Array[String])
	var beef: Dictionary = _panel.row_for(&"beef_patty")
	assert_eq((beef["name"] as Label).text, "Beef patty")
	assert_eq((beef["count"] as Label).text, "10 in the fridge")
	assert_eq((beef["expiry"] as Label).text, "3 expire tomorrow")
	assert_eq((beef["price"] as Label).text, "$2 each")
	assert_false((beef["buy1"] as Button).disabled, "$3 buys one $2 patty")
	assert_true((beef["buy5"] as Button).disabled, "but not five")
	var cheese: Dictionary = _panel.row_for(&"cheese")
	assert_eq((cheese["auto"] as Button).text, "Auto-reorder off")
	assert_eq((cheese["expiry"] as Label).text, "0 expire tomorrow")
	(beef["buy1"] as Button).pressed.emit()
	(cheese["auto"] as Button).toggled.emit(true)
	(cheese["plus"] as Button).pressed.emit()
	assert_eq(_requests, [["buy", &"beef_patty", 1], ["auto", &"cheese", true], ["target", &"cheese", 9]])
	assert_false((cheese["auto"] as Button).button_pressed, "the committed state returns until the session accepts")
	_panel.set_stock(_rows(), 300, false)
	assert_true((beef["buy1"] as Button).disabled, "nothing is bought outside the morning")
	assert_true((cheese["plus"] as Button).disabled)
	(beef["buy1"] as Button).pressed.emit()
	assert_eq(_requests.size(), 3)


func test_panel_fits_the_usual_window_and_150_percent_scale() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_host = SubViewport.new()
	_host.size = Vector2i(1600, 900)
	_host.gui_embed_subwindows = true
	tree.root.add_child(_host)
	var window: Window = Window.new()
	window.borderless = true
	window.size = Vector2i(1600, 900)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = Vector2i(1600, 900)
	_host.add_child(window)
	window.add_child(_panel)
	_panel.set_stock(_rows(), 300, true, ["This morning's auto-order cost $93 ($88 at list price + $5 premium).",
		"Not enough cash to auto-order 5 Beef patty, 20 Bread and 10 Burger bun."] as Array[String])
	_panel.show()
	for scale: float in [1.0, 1.5]:
		window.content_scale_factor = scale
		for frame: int in range(4):
			await tree.process_frame
		var visible: Rect2 = window.get_visible_rect()
		var panel: Control = _panel.get_node("Panel") as Control
		var rect: Rect2 = panel.get_global_rect()
		assert_almost_eq(rect.size.x, 720.0, 0.5, "content never widens the panel at %d%%" % roundi(scale * 100))
		assert_true(visible.grow(0.5).encloses(rect), "the panel stays on screen at %d%%: %s in %s" % [roundi(scale * 100), rect, visible])
		var close: Control = _panel.get_node("Panel/Content/Close") as Control
		assert_true(rect.grow(0.5).encloses(close.get_global_rect()), "Close stays reachable")
		var scroll: Control = _panel.get_node("Panel/Content/Scroll") as Control
		assert_true(scroll.size.y > 100.0, "rows keep a scrolling area at %d%%" % roundi(scale * 100))
		for data: Dictionary in _rows():
			var row: Dictionary = _panel.row_for(data["id"])
			for key: String in ["name", "count", "price", "buy1", "buy5", "expiry", "auto", "minus", "target", "plus"]:
				var control: Control = row[key]
				assert_true(control.size.x >= control.get_combined_minimum_size().x - 0.5,
					"%s %s keeps its full content" % [data["id"], key])
				var inside: Rect2 = control.get_global_rect()
				assert_true(inside.position.x >= rect.position.x - 0.5 and inside.end.x <= rect.end.x + 0.5,
					"%s %s stays inside the panel width" % [data["id"], key])


func _on_buy(id: StringName, qty: int) -> void:
	_requests.append(["buy", id, qty])


func _on_auto(id: StringName, enabled: bool) -> void:
	_requests.append(["auto", id, enabled])


func _on_target(id: StringName, target: int) -> void:
	_requests.append(["target", id, target])
