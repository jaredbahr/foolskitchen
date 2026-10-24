extends TestCase
## Actual Main/provider/HUD wiring. Runtime and image acceptance remain separate.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "plates_session"

var _main: Node3D
var _viewport: SubViewport
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "plate_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	for key: String in ["owner", "shop", "menu", "plates"]:
		if SaveSystem._providers.has(key):
			_old_providers[key] = SaveSystem._providers[key].duplicate()
	Clock.set_speed(0)


func after_each() -> void:
	_close_main()
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	for key: String in ["owner", "shop", "menu", "plates"]:
		if _old_providers.has(key):
			var provider: Dictionary = _old_providers[key]
			SaveSystem.register(key, provider["capture"], provider["restore"])
		else:
			SaveSystem._providers.erase(key)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_plate_counter_uses_ascii_counts_and_fits_the_actual_1280_hud() -> void:
	await _start(false, Vector2i(1280, 720))
	var label: Label = _main.get_node("HUD/Top/Row/Plates") as Label
	assert_eq(label.text, "Plates 12/12")
	assert_eq(_sim().kitchen.plates.total, 12)
	var books: Dictionary = Economy.ledger.to_dict()
	assert_true(_sim().kitchen.configure_plates(9))
	assert_eq(label.text, "Plates 9/9", "Main forwards the actual kitchen change")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(_sim().world.now, 0)
	await _frames(3)
	_assert_hud_row_fits(1280.0)
	assert_eq((_main.get_node("HUD/Top") as Control).theme, load("res://src/ui/theme/main_theme.tres"))


func test_real_plating_changes_the_counter_without_a_service_save() -> void:
	await _start()
	var saved: String = _saved_text()
	var sim: RestaurantSim = _sim()
	sim.menu = [(_main.get("content") as ContentDB).recipe(&"burger")] as Array[RecipeDef]
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 7301
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], random)
	assert_true(Clock.sim.start_service())
	for tick: int in range(1200):
		_main.call("run_ticks", 1)
		if sim.kitchen.in_use_plates > 0:
			break
	assert_not_null(guest.order)
	assert_eq(sim.kitchen.in_use_plates, 1)
	assert_eq(sim.kitchen.clean_plates, 11)
	assert_eq((_main.get_node("HUD/Top/Row/Plates") as Label).text, "Plates 11/12")
	assert_eq(_saved_text(), saved, "plating never adds a save point")
	assert_eq(sim.kitchen.clean_plates + sim.kitchen.dirty_plates + sim.kitchen.in_use_plates, 12)


func test_only_total_persists_at_the_next_morning_and_survives_world_rebuild() -> void:
	await _start()
	var original: String = _saved_text()
	assert_true(_sim().kitchen.configure_plates(5))
	assert_eq(_saved_text(), original, "stock configuration waits for the morning checkpoint")
	Clock.sim.open_ticks = 2
	Clock.sim.last_orders_max_ticks = 1
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 10)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	(_main.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	assert_eq(Clock.sim.day, 2)
	var document: Dictionary = JSON.parse_string(_saved_text())
	var sections: Dictionary = document["data"]
	var saved_plates: Dictionary = sections["plates"]
	assert_eq(saved_plates, {"version": 1.0, "total": 5.0})
	assert_eq(typeof(saved_plates["total"]), TYPE_FLOAT, "the actual JSON file contains a number")
	var captured_plates: Dictionary = _main.call("_capture_plates")
	assert_eq(typeof(captured_plates["total"]), TYPE_INT, "the morning provider writes an integer")
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var old_world: SimWorld = _sim().world
	_reload_main()
	assert_true(_sim().world != old_world)
	assert_eq(Clock.sim.day, 2)
	assert_eq(_sim().kitchen.plates.total, 5)
	assert_eq(_sim().kitchen.clean_plates, 5)
	assert_eq(_sim().kitchen.dirty_plates, 0)
	assert_eq(_sim().kitchen.in_use_plates, 0)
	assert_eq((_main.get_node("HUD/Top/Row/Plates") as Label).text, "Plates 5/5")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)


func test_previous_string_plate_total_loads_and_the_normal_morning_save_writes_a_number() -> void:
	await _start()
	var document: Dictionary = JSON.parse_string(_saved_text())
	var sections: Dictionary = document["data"]
	sections["plates"] = {"version": 1, "total": "7"}
	_write_document(document)
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	_reload_main()
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(_sim().kitchen.plates.total, 7)
	assert_eq(_sim().kitchen.clean_plates, 7)
	assert_eq(_sim().kitchen.dirty_plates, 0)
	assert_eq(_sim().kitchen.in_use_plates, 0)
	assert_eq((_main.get_node("HUD/Top/Row/Plates") as Label).text, "Plates 7/7")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	var rewritten: Dictionary = JSON.parse_string(_saved_text())
	assert_eq(rewritten["data"]["plates"], {"version": 1.0, "total": 7.0})
	assert_eq(typeof(rewritten["data"]["plates"]["total"]), TYPE_FLOAT)


func test_pre_sink_save_keeps_its_layout_and_defaults_missing_plate_stock() -> void:
	await _start(true, Vector2i(1280, 720))
	var document: Dictionary = JSON.parse_string(_saved_text())
	var sections: Dictionary = document["data"]
	sections.erase("plates")
	var shop: Dictionary = sections["shop"]
	var placements: Array = []
	for value: Dictionary in shop["items"]:
		if value["def_id"] == "sink":
			continue
		if value["def_id"] == "potted_plant":
			value["origin"] = [11, 9]
		placements.append(value)
	shop["items"] = placements
	_write_document(document)
	var cash: int = Economy.cash
	_reload_main()
	assert_eq(Economy.cash, cash, "a valid legacy layout does not silently start a new game")
	assert_eq(ShopBuilder.items_with_def(_sim().world, &"sink").size(), 0, "loading does not insert furniture")
	assert_eq(ShopBuilder.items_with_def(_sim().world, &"potted_plant")[0].origin, Vector2i(11, 9))
	assert_eq(_sim().kitchen.clean_plates, 12)
	assert_false(_sim().kitchen.plate_cycle_enabled)
	var label: Label = _main.get_node("HUD/Top/Row/Plates") as Label
	assert_eq(label.text, "Plates: buy a sink")
	assert_true(label.tooltip_text.contains("Plate limits are off"))
	await _frames(3)
	_assert_hud_row_fits(1280.0)
	var before_purchase: String = _saved_text()
	assert_true(_main.call("shop_buy", &"sink", Vector2i(10, 1), 2), "the existing shop can buy its missing sink")
	assert_true(_sim().kitchen.plate_cycle_enabled)
	assert_eq(label.text, "Plates 12/12", "the topology signal updates the existing counter immediately")
	assert_eq(_saved_text(), before_purchase, "buying a sink adds no save point")
	await _frames(3)
	_assert_hud_row_fits(1280.0)
	var sink: PlacedItem = ShopBuilder.items_with_def(_sim().world, &"sink")[0]
	assert_false((_main.get("shop_editor") as ShopEditor).check_sell(sink.id).ok)


func test_invalid_plate_save_stages_no_live_change_and_fresh_start_clears_staged_stock() -> void:
	await _start()
	assert_true(_main.call("_restore_plates", {"version": 1, "total": "7"}))
	assert_true(_main.call("_restore_plates", {"version": 1, "total": 7}))
	assert_eq(_sim().kitchen.plates.total, 12, "provider validation stages only primitive durable stock")
	assert_false(_main.call("_restore_plates", {"version": 1, "total": "-1"}))
	assert_false(_main.call("_restore_plates", {"version": 1, "total": 1000}))
	assert_eq(_sim().kitchen.plates.total, 12)
	var document: Dictionary = JSON.parse_string(_saved_text())
	var sections: Dictionary = document["data"]
	sections["plates"] = {"version": 1, "total": 1000}
	_write_document(document)
	var broken: String = _saved_text()
	_reload_main()
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(_sim().kitchen.plates.total, 12, "failed startup discards every staged plate total")
	assert_eq(_sim().kitchen.clean_plates, 12)
	assert_eq(_saved_text(), broken, "the existing failed-startup autosave skip remains intact")


func _assert_hud_row_fits(width: float) -> void:
	var previous_end: float = 0.0
	var row: HBoxContainer = _main.get_node("HUD/Top/Row") as HBoxContainer
	for child: Node in row.get_children():
		var control: Control = child as Control
		if control == null or not control.visible:
			continue
		var rect: Rect2 = control.get_global_rect()
		assert_true(rect.position.x >= previous_end, "top controls do not overlap")
		assert_true(rect.end.x <= width - 12.0, "the plate count and existing buttons fit within the 12px margin")
		previous_end = rect.end.x


func _start(with_saves: bool = true, viewport_size: Vector2i = Vector2i(1600, 900)) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = viewport_size
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	_create_main(with_saves)
	await _frames(3)


func _create_main(with_saves: bool) -> void:
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", with_saves)
	_main.set("save_slot", SLOT)
	_viewport.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	_main.get_node("CameraRig").set_process(false)
	_main.get_node("ShopView").set_process(false)
	Clock.set_speed(0)


func _reload_main() -> void:
	_close_main()
	_create_main(true)


func _close_main() -> void:
	if not is_instance_valid(_main):
		return
	if _main.get_parent() != null:
		_main.get_parent().remove_child(_main)
	_main.free()
	_main = null


func _sim() -> RestaurantSim:
	return _main.get("sim") as RestaurantSim


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_save_dir.path_join(SLOT + ".json"), FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(JSON.stringify(document))
	file.close()


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for frame: int in range(count):
		await tree.process_frame
