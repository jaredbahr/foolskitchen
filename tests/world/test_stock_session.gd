extends TestCase
## #54 in the real game session: morning auto-reorder with its premium, the
## Stock panel's manual buys and settings, saving, expiry, sold-out dishes on
## the HUD and the evening report's Low stock section.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const SLOT: String = "stock_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "stock_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _ingredient_entries(day: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in Economy.ledger.entries_for_day(day):
		if entry["category"] == Ledger.INGREDIENTS:
			found.append(entry)
	return found


## Defaults buy what the old fixed top-up bought; the premium is one entry.
func test_new_game_auto_order_buys_the_old_amounts_with_one_premium() -> void:
	_start(false)
	for id: StringName in TUNING.morning_stock:
		assert_eq(Economy.stock.count(id), TUNING.morning_stock[id], "%s topped up as before" % id)
	assert_eq(Economy.cash, TUNING.starting_cash - 97, "$88 at list price plus a $9 premium")
	var entries: Array[Dictionary] = _ingredient_entries(1)
	assert_eq(entries.size(), TUNING.morning_stock.size() + 1)
	var premiums: int = 0
	for entry: Dictionary in entries:
		if entry["note"] == "auto_reorder_premium":
			premiums += 1
			assert_eq(entry["amount"], -9)
	assert_eq(premiums, 1, "the premium is charged once per order")


## Manual buys are list price, MORNING only, through the real panel.
func test_manual_buys_are_list_price_and_morning_only() -> void:
	var main: Node = _start(false)
	var button: Button = main.get_node("HUD/Top/Row/Stock") as Button
	var panel: StockPanel = main.get_node("Overlay/StockPanel") as StockPanel
	assert_false(button.disabled)
	button.pressed.emit()
	assert_true(panel.visible)
	var cash: int = Economy.cash
	var row: Dictionary = panel.row_for(&"tomato")
	(row["buy5"] as Button).pressed.emit()
	assert_eq(Economy.stock.count(&"tomato"), TUNING.morning_stock[&"tomato"] + 5)
	assert_eq(Economy.cash, cash - 5, "five $1 tomatoes cost $5: no premium")
	(row["buy1"] as Button).pressed.emit()
	assert_eq(Economy.cash, cash - 6)
	assert_eq((row["count"] as Label).text, "22 in the fridge")
	assert_false(main.call("stock_buy", &"tomato", 3), "only the +1 and +5 buttons exist")
	assert_true(Clock.sim.start_service())
	assert_false(panel.visible, "opening the shop closes the panel")
	assert_true(button.disabled)
	assert_false(main.call("set_stock_visible", true))
	assert_false(main.call("stock_buy", &"tomato", 1))
	assert_false(main.call("stock_set_auto", &"tomato", false))
	assert_eq(Economy.cash, cash - 6)


## Short cash never borrows; it buys in the fixed order.
func test_disabled_and_short_cash_mornings() -> void:
	var main: Node = _start(false)
	assert_true(main.call("stock_set_auto", &"tomato", false))
	assert_true(main.call("stock_set_target", &"bread", 20))
	assert_true(Economy.stock.take(&"tomato", 16))
	_next_morning()
	assert_eq(Economy.stock.count(&"tomato"), 0, "a disabled ingredient is not bought")
	assert_eq(Economy.stock.count(&"bread"), 20, "a raised target is bought")
	var notes: Array[String] = main.call("stock_notes")
	assert_eq(notes, ["This morning's auto-order cost $5 ($4 at list price + $1 premium)."] as Array[String])
	for id: StringName in TUNING.morning_stock:
		Economy.stock.take(id, Economy.stock.count(id))
	Economy.cash = 12
	_next_morning()
	assert_true(Economy.cash >= 0, "the auto-order never borrows")
	assert_eq(Economy.stock.count(&"beef_patty"), 5, "$10 of patties plus a $1 premium fit in $12")
	assert_eq(Economy.stock.count(&"bread"), 0)
	notes = main.call("stock_notes")
	assert_true(notes[1].begins_with("Not enough cash to auto-order 5 Beef patty, 20 Bread"), notes[1])


func test_settings_survive_the_morning_autosave_and_old_saves_use_defaults() -> void:
	var first: Node = _start(true)
	assert_true(first.call("stock_set_auto", &"cheese", false))
	assert_true(first.call("stock_set_target", &"bun", 14))
	_next_morning()
	_close(first)
	Economy.reset(12345)
	var second: Node = _start(true)
	var restored: ReorderSettings = second.get("reorder_settings")
	assert_false(restored.is_enabled(&"cheese"))
	assert_eq(restored.target(&"bun"), 14)
	assert_eq(Economy.stock.count(&"bun"), 14)
	# A save from before the Stock panel has no reorder section.
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	document["data"].erase("reorder")
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")
	_close(second)
	var third: Node = _start(true)
	var defaults: ReorderSettings = third.get("reorder_settings")
	assert_true(defaults.is_enabled(&"cheese"))
	assert_eq(defaults.target(&"bun"), TUNING.morning_stock[&"bun"])


## Old stock is thrown out before the morning order replaces it.
func test_expired_stock_is_thrown_out_and_replaced() -> void:
	var main: Node = _start(false)
	var rows: Array[Dictionary] = main.call("stock_rows")
	var beef: Dictionary = rows.filter(func(row: Dictionary) -> bool: return row["id"] == &"beef_patty")[0]
	assert_eq(beef["expiring"], 0, "day-one patties keep two days")
	_next_morning()
	rows = main.call("stock_rows")
	beef = rows.filter(func(row: Dictionary) -> bool: return row["id"] == &"beef_patty")[0]
	assert_eq(beef["expiring"], 10, "day-one patties must be used today")
	_next_morning()
	assert_eq(Economy.stock.count(&"beef_patty"), 10)
	var notes: Array[String] = main.call("stock_notes")
	assert_true(notes.has("Thrown out this morning (too old): 10 Beef patty."), str(notes))
	assert_true(notes[0].begins_with("This morning's auto-order cost $22"), notes[0])


## A dish that runs out is tagged on the HUD and named in the report with
## its ingredient and time; guests order the dishes that are left.
func test_sold_out_dish_reaches_hud_and_report() -> void:
	var main: Node = _start(false)
	assert_true(main.call("stock_set_auto", &"soup_stock", false))
	assert_true(Economy.stock.take(&"soup_stock", 8))
	# Plenty of everything else, so only the soup can run out today.
	for id: StringName in TUNING.morning_stock:
		if id != &"soup_stock":
			Economy.stock.add(id, 50, Clock.sim.day)
	var sim: RestaurantSim = main.get("sim")
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 200)
	assert_true(sim.is_sold_out(&"tomato_soup"))
	var tag: Label = main.get_node("HUD/Top/Row/SoldOut") as Label
	assert_true(tag.visible)
	assert_eq(tag.text, "Sold out: Tomato soup")
	var guard: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 30:
		main.call("run_ticks", 1000)
		guard += 1
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_false(tag.visible, "at closing the report explains what sold out")
	assert_eq((main.get("dishes_sold_today") as Dictionary).get(&"tomato_soup", 0), 0)
	assert_eq(int(sim.leave_reasons_today.get(&"out_of_stock", 0)), 0,
		"guests choose burgers and grilled cheese instead of leaving")
	var report: DayReport = main.get("shown_report")
	assert_eq(report.low_stock[0], "Soup stock ran out at 11:00: Tomato soup sold out")
	assert_true(report.low_stock.has("Soup stock: 0 left, target 8. Auto-reorder is off."), str(report.low_stock))
	assert_eq(report.low_stock.size(), 2, "the extra stock covers every other target: %s" % [report.low_stock])
	var rows: VBoxContainer = main.get_node("Overlay/EveningReport").find_child("LowStockRows", true, false) as VBoxContainer
	assert_eq((rows.get_child(0) as Label).text, report.low_stock[0])
	(main.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	assert_false(tag.visible, "a new morning clears the tag")


func _next_morning() -> void:
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


func _start(with_saves: bool) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", SLOT)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")
