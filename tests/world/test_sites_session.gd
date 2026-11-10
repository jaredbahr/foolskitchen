extends TestCase
## The sites save section (FK-087) round-trips through the real morning save.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "sites_session"
var _main: Node
var _old_dir: String
var _providers: Dictionary


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	SaveSystem.save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SaveSystem.save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start(saves: bool = false) -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", saves)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _path() -> String:
	return SaveSystem.save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path()))


func _write(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")


func test_a_save_holding_two_sites_round_trips() -> void:
	_start(true)
	var day: int = Clock.sim.day
	var frozen: Dictionary = {}
	for key: String in ["shop", "menu", "pantry"]:
		frozen[key] = SaveSystem._providers[key]["capture"].call()
	var book: SiteBook = _main.get("site_book")
	assert_true(book.add_site(&"harbour", &"pier_lot", "Pier Shack", day, frozen))
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")
	var saved: Dictionary = _document()["data"]["sites"]
	_close()
	_start(true)
	assert_eq(Clock.sim.day, day + 1, "the saved game loaded")
	var loaded: SiteBook = _main.get("site_book")
	assert_eq(loaded.site_ids(), [&"home", &"harbour"] as Array[StringName])
	assert_eq(loaded.frozen_day(&"harbour"), day)
	assert_eq(JSON.parse_string(JSON.stringify(loaded.to_dict())), saved,
		"the frozen site comes back byte for byte")


func test_an_old_save_without_sites_loads_as_the_starter_site() -> void:
	_start(true)
	var document: Dictionary = _document()
	var day: int = Clock.sim.day
	document["data"].erase("sites")
	_write(document)
	_close()
	_start(true)
	assert_eq(Clock.sim.day, day, "the old save loaded")
	var book: SiteBook = _main.get("site_book")
	assert_eq(book.site_ids(), [SiteBook.HOME_ID] as Array[StringName])


func test_a_site_frozen_after_this_morning_refuses_the_load() -> void:
	_start(true)
	var document: Dictionary = _document()
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"harbour", &"pier_lot", "", Clock.sim.day + 1, {}))
	document["data"]["sites"] = JSON.parse_string(JSON.stringify(book.to_dict()))
	_write(document)
	_close()
	_start(true)
	var loaded: SiteBook = _main.get("site_book")
	assert_eq(loaded.site_count(), 1, "a refused load starts over with the starter site")
