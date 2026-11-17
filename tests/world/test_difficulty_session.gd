extends TestCase
## Verify the career settings and stock rules through the live session.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "autosave"

var _main: Node
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary
var _old_clock: SimClock
var _clock_processed: bool


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "difficulty_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_providers = SaveSystem._providers.duplicate()
	_old_clock = Clock.sim
	_clock_processed = Clock.is_processing()
	Clock.set_process(false)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _old_providers
	Clock.sim = _old_clock
	Clock.set_speed(0)
	Clock.set_process(_clock_processed)
	GameMode.request_new_game(false)
	GameMode.set_creative(false)
	Economy.reset(0)
	GameState.new_run(1)


func test_settings_change_applies_before_next_morning_and_survives_continue() -> void:
	_start()
	assert_true(_main.call("set_settings_visible", true))
	var settings: SettingsPanel = _main.get_node("Overlay/SettingsPanel") as SettingsPanel
	var choice: OptionButton = settings.get_node("%DifficultyChoice") as OptionButton
	var note: Label = settings.get_node("%DifficultySchedule") as Label
	var buy: CheckButton = settings.get_node("%AutoBuy") as CheckButton
	var premium: CheckButton = settings.get_node("%AutoBuyPremium") as CheckButton
	var tag: Label = _main.get_node("HUD/Top/Row/Difficulty") as Label
	assert_eq(Difficulty.MODES[choice.selected], &"normal")
	assert_false(tag.visible)
	assert_false(buy.visible)
	choice.item_selected.emit(Difficulty.MODES.find(&"custom"))
	assert_true(buy.visible)
	assert_true(premium.visible)
	premium.button_pressed = false
	assert_eq(note.text, "From tomorrow: Custom (today: Normal)")
	assert_eq(_difficulty().mode(), &"normal")
	assert_true(_difficulty().auto(&"buy_premium"))
	assert_false(tag.visible)
	assert_true(_main.call("set_settings_visible", false))
	_finish_service()
	assert_true(Clock.sim.next_day())
	assert_eq(_difficulty().mode(), &"custom")
	assert_true(_difficulty().auto(&"buy"))
	assert_false(_difficulty().auto(&"buy_premium"))
	assert_eq(_difficulty().pending_mode(), &"")
	assert_true(tag.visible)
	assert_eq(tag.text, "Custom")
	_close()
	_start()
	assert_eq(Clock.sim.day, 2)
	assert_eq(_difficulty().mode(), &"custom")
	assert_false(_difficulty().auto(&"buy_premium"))


func test_hard_hides_standing_orders_and_charges_higher_rent() -> void:
	_start(&"hard")
	assert_true(_main.call("set_stock_visible", true))
	var stock: Control = _main.get_node("Overlay/StockPanel") as Control
	var rows: Array = _main.call("stock_rows")
	var id: StringName = rows[0]["id"]
	var row: Dictionary = stock.call("row_for", id)
	assert_false((row["auto"] as Button).visible)
	assert_false((row["reorder"] as HBoxContainer).visible)
	assert_false(_main.call("stock_set_auto", id, true))
	assert_true(_main.call("stock_cart_set", id, 1))
	assert_true(_main.call("stock_place_order"))
	assert_true(_main.call("set_stock_visible", false))
	_finish_service()
	assert_eq(int(Economy.ledger.day_totals(1)[Ledger.RENT]), -roundi(_main.call("_home_rent") * 1.1))
	assert_true(Clock.sim.next_day())
	for entry: Dictionary in Economy.ledger.entries_for_day(2):
		assert_false(String(entry["note"]).begins_with("auto_reorder"))


func test_easy_forces_auto_buy_without_rewriting_saved_ingredient_preferences() -> void:
	_start()
	var rows: Array = _main.call("stock_rows")
	var id: StringName = rows[0]["id"]
	assert_true(_main.call("stock_set_auto", id, false))
	assert_true(_difficulty().request_change(&"easy", {}, 2))
	_finish_service()
	assert_true(Clock.sim.next_day())
	assert_true((_main.call("_reorder") as ReorderSettings).is_enabled(id))
	assert_false((_main.get("reorder_settings") as ReorderSettings).is_enabled(id))
	assert_false(_main.call("stock_set_auto", id, false))
	assert_eq(_main.call("_reorder_premium"), 0.0)
	var replenished: bool = false
	for entry: Dictionary in Economy.ledger.entries_for_day(2):
		var note: String = entry["note"]
		assert_ne(note, "auto_reorder_premium")
		replenished = replenished or note.begins_with("auto_reorder:")
	assert_true(replenished, "Easy used the real morning standing order")


func test_save_without_difficulty_section_loads_normal() -> void:
	_start(&"easy")
	_close()
	var path: String = _save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true((document["data"] as Dictionary).erase("difficulty"))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_start()
	assert_eq(_difficulty().mode(), &"normal")
	assert_true(_difficulty().auto(&"buy_premium"))
	assert_false((_main.get_node("HUD/Top/Row/Difficulty") as Label).visible)


func _start(mode_id: StringName = &"normal") -> void:
	GameMode.request_new_game(false, mode_id)
	_main = MAIN.instantiate()
	_main.set("skip_owner_picker", true)
	_main.set("new_game_seed_override", 1)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_main)
	_main.call("start")


func _close() -> void:
	if is_instance_valid(_main):
		_main.free()
		_main = null


func _difficulty() -> Difficulty:
	return _main.get("difficulty") as Difficulty


func _finish_service() -> void:
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 15000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
