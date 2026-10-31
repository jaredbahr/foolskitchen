extends TestCase
## One staged shop provider; existing morning saves and failed-load behavior.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const PROGRESSION: ProgressionTuning = preload("res://data/balance/progression.tres")
const SLOT: String = "blueprints"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "blueprint_session")
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


func test_player_library_only_saves_at_next_morning_and_survives_load() -> void:
	var first: Node = _start()
	var library: BlueprintLibrary = first.get("blueprint_library")
	var before: String = FileAccess.get_file_as_string(_path())
	var blueprint: Blueprint = _plant(first)
	assert_true(library.add(blueprint))
	assert_true(library.rename(blueprint, "Cosy corner"))
	(first.get("shop_editor") as ShopEditor).set_owner_level(2)
	assert_true(first.call("shop_stamp", blueprint, Vector2i(11, 8), 1), (first.get("shop_editor") as ShopEditor).last_check.why)
	assert_eq(FileAccess.get_file_as_string(_path()), before, "library and stamp actions never save")
	assert_eq(int(_document()["data"]["shop"]["version"]), 8, "the thin-divider shop snapshot must not go backwards")
	assert_false((_document()["data"]["shop"] as Dictionary).has("blueprints"))
	assert_eq((_document()["data"]["blueprints"]["blueprints"] as Array).size(), 0)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day(), "advance morning")
	assert_eq((_document()["data"]["blueprints"]["blueprints"] as Array).size(), 1)
	assert_eq(_document()["data"]["blueprints"]["blueprints"][0]["name"], "Cosy corner")
	_close(first)
	var second: Node = _start()
	var restored: BlueprintLibrary = second.get("blueprint_library")
	assert_eq(restored.blueprints.size(), 1)
	assert_eq(restored.blueprints[0].display_name, "Cosy corner")
	assert_eq(restored.blueprints[0].entries[0].item_id, &"potted_plant")
	var saved: String = FileAccess.get_file_as_string(_path())
	assert_true(restored.remove(restored.blueprints[0]), "delete library")
	assert_eq(FileAccess.get_file_as_string(_path()), saved, "deleting also waits until morning")
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day(), "advance morning")
	assert_eq((_document()["data"]["blueprints"]["blueprints"] as Array).size(), 0)


func test_legacy_save_without_library_loads_empty_and_keeps_shop_and_cash() -> void:
	var first: Node = _start()
	var saved: Dictionary = _document()
	var cash: int = Economy.cash
	var shop: Dictionary = (first.get("shop_editor") as ShopEditor).to_dict()
	saved["data"].erase("blueprints")
	_write_document(saved)
	_remove_backup()
	_close(first)
	var second: Node = _start()
	assert_true((second.get("blueprint_library") as BlueprintLibrary).blueprints.is_empty())
	assert_eq((second.get("shop_editor") as ShopEditor).to_dict(), shop)
	assert_eq(Economy.cash, cash)
	assert_true(_document()["data"].has("blueprints"))


func test_unknown_saved_blueprint_item_is_skipped_and_logged_without_losing_shop() -> void:
	var first: Node = _start()
	var blueprint: Blueprint = _plant(first)
	var entry: ShopPlacement = blueprint.entries[0].duplicate() as ShopPlacement
	entry.item_id = &"removed_future_item"
	blueprint.entries.append(entry)
	var library: BlueprintLibrary = first.get("blueprint_library")
	assert_true(library.add(blueprint))
	assert_eq(SaveSystem.save_game(SLOT), OK) # Test fixture; production only writes in morning.
	var cash: int = Economy.cash
	_close(first)
	var second: Node = _start()
	var restored: BlueprintLibrary = second.get("blueprint_library")
	assert_eq(restored.blueprints.size(), 1)
	assert_eq(restored.blueprints[0].entries.size(), 1)
	assert_eq(Economy.cash, cash)
	var world: SimWorld = second.get("world")
	assert_true("\n".join(world.event_log).contains("skipped unknown item 'removed_future_item'"))


func test_restore_is_staged_and_failed_load_does_not_keep_partial_library() -> void:
	var first: Node = _start()
	var library: BlueprintLibrary = first.get("blueprint_library")
	assert_true(library.add(_plant(first)))
	var saved_library: Dictionary = library.to_dict()
	assert_true(first.call("_restore_blueprints", {"version": 1, "blueprints": []}))
	assert_eq(library.to_dict(), saved_library, "restore callback must not mutate active library")
	assert_eq(SaveSystem.save_game(SLOT), OK)
	var saved: Dictionary = _document()
	saved["data"]["blueprints"]["version"] = 999
	_write_document(saved)
	_remove_backup()
	var broken: String = FileAccess.get_file_as_string(_path())
	_close(first)
	var second: Node = _start()
	assert_true((second.get("blueprint_library") as BlueprintLibrary).blueprints.is_empty())
	assert_eq(FileAccess.get_file_as_string(_path()), broken, "bad saves retain existing first-autosave safety")


func test_mixed_booth_library_and_stamp_wait_for_morning_then_reload_looks() -> void:
	var first: Node = _start()
	var editor: ShopEditor = first.get("shop_editor") as ShopEditor
	var library: BlueprintLibrary = first.get("blueprint_library") as BlueprintLibrary
	var world: SimWorld = first.get("world") as SimWorld
	var before: String = FileAccess.get_file_as_string(_path())
	# Isolated persistence fixture: disclosed funds and two unselected table
	# surfaces supplement the existing tables; ordinary starting cash is untouched.
	Economy.add_cash(1000 - Economy.cash, Ledger.OTHER, "Blueprint persistence test fixture")
	assert_eq(Economy.cash, 1000)
	editor.set_owner_level(3)
	var content: ContentDB = first.get("content") as ContentDB
	for origin: Vector2i in [Vector2i(4, 7), Vector2i(8, 7)]:
		assert_not_null(world.grid.place_def(content.item(&"cross_table"), origin), "unselected dining support")
	var white_check: EditCheck = editor.check_buy(&"diner_booth", Vector2i(2, 8), 0, null, &"booth_white")
	assert_true(white_check.ok, white_check.why)
	assert_true(first.call("shop_buy", &"diner_booth", Vector2i(2, 8), 0, &"", &"booth_white"), editor.last_check.why)
	var walnut_check: EditCheck = editor.check_buy(&"diner_booth", Vector2i(4, 8), 0, null, &"booth_walnut")
	assert_true(walnut_check.ok, walnut_check.why)
	assert_true(first.call("shop_buy", &"diner_booth", Vector2i(4, 8), 0, &"", &"booth_walnut"), editor.last_check.why)
	var white: PlacedItem = world.grid.item_at(Vector2i(2, 8))
	var walnut: PlacedItem = world.grid.item_at(Vector2i(4, 8))
	assert_not_null(white)
	assert_not_null(walnut)
	if white == null or walnut == null:
		return
	assert_eq(white.variant_id, &"booth_white")
	assert_eq(walnut.variant_id, &"booth_walnut")
	assert_eq(Economy.cash, 790, "two authored booth purchases debit the funded fixture")
	for source: PlacedItem in [white, walnut]:
		for cell: Vector2i in source.seat_cells:
			assert_eq(world.grid.dining_furnishing_id(cell), source.id)
	var blueprint: Blueprint = Blueprint.capture(world.grid, [white.id, walnut.id] as Array[int], "Mixed booths")
	assert_eq(blueprint.entries.size(), 2, "support tables are excluded from the capture")
	assert_true(library.add(blueprint))
	var stamp_check: EditCheck = editor.check_stamp(blueprint, Vector2i(8, 8))
	assert_true(stamp_check.ok, stamp_check.why)
	assert_true(first.call("shop_stamp", blueprint, Vector2i(8, 8)), editor.last_check.why)
	assert_eq(Economy.cash, 580, "one real stamp debits both copied booths")
	assert_eq(FileAccess.get_file_as_string(_path()), before, "buy, capture and stamp wait for the morning autosave")
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day(), "existing morning checkpoint")
	var saved: Dictionary = _document()
	assert_eq(int(saved["data"]["blueprints"]["version"]), 1)
	assert_eq(int(saved["data"]["shop"]["version"]), 8)
	assert_eq(saved["data"]["blueprints"]["blueprints"][0]["entries"][0].get("variant_id"), "booth_white")
	assert_eq(saved["data"]["blueprints"]["blueprints"][0]["entries"][1].get("variant_id"), "booth_walnut")
	_close(first)
	var second: Node = _start()
	var restored: BlueprintLibrary = second.get("blueprint_library") as BlueprintLibrary
	assert_eq(restored.blueprints.size(), 1)
	assert_eq(restored.blueprints[0].entries.size(), 2)
	assert_eq(restored.blueprints[0].entries[0].variant_id, &"booth_white")
	assert_eq(restored.blueprints[0].entries[1].variant_id, &"booth_walnut")
	var grid: SimGrid = (second.get("world") as SimWorld).grid
	assert_eq(grid.item_at(Vector2i(2, 8)).variant_id, &"booth_white")
	assert_eq(grid.item_at(Vector2i(4, 8)).variant_id, &"booth_walnut")
	assert_eq(grid.item_at(Vector2i(8, 8)).variant_id, &"booth_white")
	assert_eq(grid.item_at(Vector2i(10, 8)).variant_id, &"booth_walnut")


func _plant(main: Node) -> Blueprint:
	return Blueprint.capture((main.get("world") as SimWorld).grid, [_id(main, &"potted_plant")] as Array[int], "Plants")


func _start(with_saves: bool = true) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("save_slot", SLOT)
	main.set("use_saves", with_saves)
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


func _id(main: Node, def_id: StringName) -> int:
	return ShopBuilder.items_with_def(main.get("world"), def_id)[0].id


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path()))


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_backup() -> void:
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")
