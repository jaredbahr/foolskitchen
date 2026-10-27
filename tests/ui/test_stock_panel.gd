extends TestCase
## The request-only Stock panel (an order cart since FK-087): player text,
## groups by storage, requests, and its fit at the
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
	for kind: int in StorageSpace.KINDS:
		for id: StringName in TUNING.morning_stock.keys() + [&"beer"]:
			var ingredient: IngredientDef = content.ingredient(id)
			if int(ingredient.storage) != kind:
				continue
			rows.append({"id": id, "name": ingredient.display_name, "count": 10, "expiring": 3 if id == &"beef_patty" else 0,
				"unit_cost": ingredient.unit_cost, "enabled": id != &"cheese", "target": TUNING.morning_stock.get(id, 20),
				"max_target": ReorderSettings.MAX_TARGET, "kind": kind, "in_use": id != &"beer",
				"cart": 2 if id == &"tomato" else 0, "on_order": 4 if id == &"bread" else 0})
	return rows


func _view(cash: int, editable: bool, notes: Array[String] = [], fridge_free: int = 10) -> Dictionary:
	return {"rows": _rows(), "cash": cash, "editable": editable, "notes": notes, "premium": 0.05,
		"groups": [{"kind": StorageSpace.FRIDGE, "label": "Fridge", "in_stock": 30, "on_order": 0,
			"capacity": 30 + fridge_free, "cart": 0},
			{"kind": StorageSpace.DRY, "label": "Dry", "in_stock": 50, "on_order": 4, "capacity": 60, "cart": 2}],
		"cart_total": 2, "cart_refusal": "", "pending": "On order (paid $4): 4 Bread. It arrives at 14:00.",
		"refund": 4, "delivery": {"text": "Next delivery at 14:00", "fraction": 0.25}}


func test_rows_show_groups_cart_and_send_requests() -> void:
	_panel.cart_requested.connect(_on_cart)
	_panel.auto_requested.connect(_on_auto)
	_panel.target_requested.connect(_on_target)
	_panel.order_requested.connect(_on_order)
	_panel.cancel_requested.connect(_on_cancel)
	_panel.set_view(_view(3, true, ["This morning's auto-order cost $93 ($88 at list price + $5 premium)."] as Array[String], 1))
	var fridge: Dictionary = _panel.group_for(StorageSpace.FRIDGE)
	assert_eq((fridge["title"] as Label).text, "Fridge")
	assert_eq((fridge["space"] as Label).text, "30 / 31 units")
	var dry: Dictionary = _panel.group_for(StorageSpace.DRY)
	assert_eq((dry["space"] as Label).text, "50 / 60 units (4 on order, 2 in the cart)")
	assert_true(_panel.group_for(StorageSpace.FREEZER).is_empty(), "no freezer, no freezer group")
	assert_true((fridge["root"] as Node).is_ancestor_of(_panel.row_for(&"beef_patty")["root"]), "patties are kept in the fridge")
	assert_true((dry["root"] as Node).is_ancestor_of(_panel.row_for(&"bread")["root"]), "bread on the dry shelves")
	var beef: Dictionary = _panel.row_for(&"beef_patty")
	assert_eq((beef["name"] as Label).text, "Beef patty")
	assert_eq((beef["count"] as Label).text, "10 in stock. 3 expire tomorrow")
	assert_eq((beef["price"] as Label).text, "$2 each")
	assert_false((beef["cart+1"] as Button).disabled, "one more fits the fridge")
	assert_true((beef["cart+5"] as Button).disabled, "five more do not")
	assert_eq((beef["cart+5"] as Button).tooltip_text, "Not enough fridge space")
	assert_true((beef["cart-1"] as Button).disabled, "nothing in the cart to take away")
	assert_eq((_panel.row_for(&"bread")["count"] as Label).text, "10 in stock, 4 on order")
	var beer: Dictionary = _panel.row_for(&"beer")
	assert_true((beer["root"] as Control).modulate.a < 1.0, "an ingredient nothing on the menu uses is greyed out")
	assert_eq((beer["count"] as Label).text, "10 in stock. Not on today's menu")
	assert_false((beer["cart+1"] as Button).disabled, "but it can still be ordered")
	assert_eq((_panel.row_for(&"tomato")["root"] as Control).modulate.a, 1.0)
	var cheese: Dictionary = _panel.row_for(&"cheese")
	assert_eq((cheese["auto"] as Button).text, "Auto-reorder off")
	assert_eq((_panel.get_node("%CartTotal") as Label).text, "Order total: $2 (cash $3)")
	assert_eq((_panel.get_node("%DeliveryLabel") as Label).text, "Next delivery at 14:00")
	assert_almost_eq((_panel.get_node("%DeliveryBar") as ProgressBar).value, 25.0, 0.01)
	assert_false((_panel.get_node("%Order") as Button).disabled)
	assert_false((_panel.get_node("%Cancel") as Button).disabled)
	(beef["cart+1"] as Button).pressed.emit()
	(_panel.row_for(&"tomato")["cart-1"] as Button).pressed.emit()
	(cheese["auto"] as Button).toggled.emit(true)
	(cheese["plus"] as Button).pressed.emit()
	(_panel.get_node("%Order") as Button).pressed.emit()
	(_panel.get_node("%Cancel") as Button).pressed.emit()
	assert_eq(_requests, [["cart", &"beef_patty", 1], ["cart", &"tomato", 1], ["auto", &"cheese", true],
		["target", &"cheese", 9], ["order"], ["cancel"]])
	assert_false((cheese["auto"] as Button).button_pressed, "the committed state returns until the session accepts")
	var refused: Dictionary = _view(300, true)
	refused["cart_refusal"] = "Not enough cash"
	refused["pending"] = ""
	_panel.set_view(refused)
	assert_true((_panel.get_node("%Order") as Button).disabled)
	assert_eq((_panel.get_node("%Order") as Button).tooltip_text, "Not enough cash")
	assert_true((_panel.get_node("%Cancel") as Button).disabled, "nothing on order to cancel")
	assert_eq((_panel.get_node("%Pending") as Label).text, "Nothing on order.")
	_panel.set_view(_view(300, false))
	assert_true((beef["cart+1"] as Button).disabled, "a locked panel sends nothing")
	(beef["cart+1"] as Button).pressed.emit()
	assert_eq(_requests.size(), 6)


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
	_panel.set_view(_view(300, true, ["This morning's auto-order cost $93 ($88 at list price + $5 premium).",
		"Not enough cash to auto-order 5 Beef patty, 20 Bread and 10 Burger bun."] as Array[String]))
	_panel.show()
	# An armed Throw out ("Click again") must not widen the panel either.
	(_panel.row_for(&"beef_patty")["throw"] as Button).pressed.emit()
	assert_eq((_panel.row_for(&"beef_patty")["throw"] as Button).text, "Click again")
	for scale: float in [1.0, 1.5]:
		window.content_scale_factor = scale
		for frame: int in range(4):
			await tree.process_frame
		var visible: Rect2 = window.get_visible_rect()
		var panel: Control = _panel.get_node("Panel") as Control
		var rect: Rect2 = panel.get_global_rect()
		assert_almost_eq(rect.size.x, 720.0, 0.5, "content never widens the panel at %d%%" % roundi(scale * 100))
		assert_true(visible.grow(0.5).encloses(rect), "the panel stays on screen at %d%%: %s in %s" % [roundi(scale * 100), rect, visible])
		for path: String in ["%Close", "%Order", "%Cancel", "%Clear", "%DeliveryBar"]:
			var control: Control = _panel.get_node(path) as Control
			assert_true(rect.grow(0.5).encloses(control.get_global_rect()), "%s stays reachable" % path)
		var scroll: Control = _panel.get_node("Panel/Content/Scroll") as Control
		assert_true(scroll.size.y > 100.0, "rows keep a scrolling area at %d%%" % roundi(scale * 100))
		for data: Dictionary in _rows():
			var row: Dictionary = _panel.row_for(data["id"])
			for key: String in ["name", "count", "price", "cart-1", "cart", "cart+1", "cart+5", "throw", "auto", "minus", "target", "plus"]:
				var control: Control = row[key]
				assert_true(control.size.x >= control.get_combined_minimum_size().x - 0.5,
					"%s %s keeps its full content" % [data["id"], key])
				var inside: Rect2 = control.get_global_rect()
				assert_true(inside.position.x >= rect.position.x - 0.5 and inside.end.x <= rect.end.x + 0.5,
					"%s %s stays inside the panel width" % [data["id"], key])


func _on_cart(id: StringName, qty: int) -> void:
	_requests.append(["cart", id, qty])


func _on_order() -> void:
	_requests.append(["order"])


func _on_cancel() -> void:
	_requests.append(["cancel"])


func _on_auto(id: StringName, enabled: bool) -> void:
	_requests.append(["auto", id, enabled])


func _on_target(id: StringName, target: int) -> void:
	_requests.append(["target", id, target])
