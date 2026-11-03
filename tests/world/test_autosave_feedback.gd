extends TestCase
## Real morning saves with a directory obstructing only the temporary filename.
## No permission changes, fake save implementation, retries or intentional errors.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "autosave_feedback"

var _main: Node
var _save_dir: String
var _old_save_dir: String
var _old_clock: Dictionary = {}
var _old_books: Dictionary = {}
var _old_providers: Dictionary = {}
var _old_rngs: Dictionary[StringName, RandomNumberGenerator] = {}
var _old_seed: int
var _attempts: int = 0


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "autosave_feedback")
	SaveSystem.save_dir = _save_dir
	_old_clock = {"sim": Clock.sim, "speed": Clock.speed, "last_speed": Clock._last_non_zero_speed,
		"accumulator": Clock._accumulator, "world": Clock.attached_world, "driver": Clock.tick_driver,
		"driven_tick": Clock.driven_world_tick, "processing": Clock.is_processing()}
	_old_books = {"ledger": Economy.ledger, "stock": Economy.stock, "loan": Economy.loan}
	_old_providers = SaveSystem._providers.duplicate()
	_old_seed = GameState.master_seed
	_old_rngs = GameState._rngs.duplicate()
	SaveSystem._providers.clear()
	SaveSystem.register("attempt_observer", _capture_attempt, _restore_attempt)
	Clock.set_process(false)
	Clock.attach_world(null)
	Clock.sim = SimClock.new()
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.free()
	DirAccess.remove_absolute(_path() + ".tmp")
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _old_providers
	Clock.attach_world(_old_clock["world"], _old_clock["driver"])
	Clock.sim = _old_clock["sim"]
	Clock.set_speed(int(_old_clock["speed"]))
	Clock._last_non_zero_speed = int(_old_clock["last_speed"])
	Clock._accumulator = float(_old_clock["accumulator"])
	Clock.driven_world_tick = int(_old_clock["driven_tick"])
	Clock.set_process(bool(_old_clock["processing"]))
	Economy.ledger = _old_books["ledger"]
	Economy.stock = _old_books["stock"]
	Economy.loan = _old_books["loan"]
	GameState.master_seed = _old_seed
	GameState._rngs = _old_rngs


func test_failed_initial_morning_warns_and_acknowledgement_neither_mutates_nor_retries() -> void:
	_block_temporary_write()
	_start(true)
	assert_eq(_attempts, 1, "the existing morning checkpoint tried once")
	assert_false(FileAccess.file_exists(_path()), "the failed write created no final save")
	var warning: AcceptDialog = _warning()
	if warning == null:
		return
	assert_true(warning.visible, "a failed initial save warns the player")
	assert_true(warning.dialog_text.contains("last save"))
	assert_true(warning.dialog_text.contains("next morning"))
	assert_true(warning.exclusive, "the player acknowledges this progress-loss warning")
	var before: Dictionary = _state()
	warning.get_ok_button().pressed.emit()
	assert_false(warning.visible, "the ordinary acknowledgement button dismisses the warning")
	assert_eq(_state(), before, "acknowledgement preserves clock, books, stock and RNG")
	assert_eq(_attempts, 1, "acknowledgement is not another save point")
	assert_true(DirAccess.dir_exists_absolute(_path() + ".tmp"))
	assert_false(FileAccess.file_exists(_path()))
	assert_true(_main.call("menu_set_price", &"burger", 7))
	assert_eq(_attempts, 1, "normal player edits still wait for the next morning")


func test_later_failure_preserves_both_save_copies_and_next_morning_recovers() -> void:
	_start(true)
	_next_morning()
	assert_eq(Clock.sim.day, 2)
	assert_eq(_attempts, 2)
	var final_bytes: PackedByteArray = FileAccess.get_file_as_bytes(_path())
	var backup_bytes: PackedByteArray = FileAccess.get_file_as_bytes(_path() + ".bak")
	assert_false(final_bytes.is_empty())
	assert_false(backup_bytes.is_empty())
	_block_temporary_write()
	_next_morning()
	assert_eq(Clock.sim.day, 3)
	assert_eq(_attempts, 3)
	assert_eq(FileAccess.get_file_as_bytes(_path()), final_bytes, "failed write preserves the prior morning")
	assert_eq(FileAccess.get_file_as_bytes(_path() + ".bak"), backup_bytes, "failed write preserves recovery too")
	var warning: AcceptDialog = _warning()
	if warning == null:
		return
	assert_true(warning.visible, "later morning failures also warn")
	warning.get_ok_button().pressed.emit()
	assert_eq(DirAccess.remove_absolute(_path() + ".tmp"), OK)
	assert_eq(_attempts, 3, "removing the obstruction does not trigger a retry")
	_next_morning()
	assert_eq(Clock.sim.day, 4)
	assert_eq(_attempts, 4, "only the next normal morning tries again")
	assert_false(warning.visible, "a successful morning shows no failure warning")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	assert_eq(int(saved["data"]["clock"]["day"]), 4)
	assert_eq(FileAccess.get_file_as_bytes(_path() + ".bak"), final_bytes,
		"normal replacement retains the last successful morning")


func test_successful_morning_has_no_warning_and_disabled_saves_do_not_attempt_a_write() -> void:
	_start(true)
	assert_eq(_attempts, 1)
	assert_true(FileAccess.file_exists(_path()))
	var warning: AcceptDialog = _main.get_node_or_null("Overlay/AutosaveFailure") as AcceptDialog
	if warning != null:
		assert_false(warning.visible)
	_main.free()
	_main = null
	assert_eq(SaveSystem.delete_slot(SLOT), OK)
	_block_temporary_write()
	_start(false)
	assert_eq(_attempts, 1, "unsaved sessions do not try or warn")
	warning = _main.get_node_or_null("Overlay/AutosaveFailure") as AcceptDialog
	if warning != null:
		assert_false(warning.visible)
	assert_false(FileAccess.file_exists(_path()))


func _start(with_saves: bool) -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", with_saves)
	_main.set("skip_owner_picker", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")


func _warning() -> AcceptDialog:
	var warning: AcceptDialog = _main.get_node_or_null("Overlay/AutosaveFailure") as AcceptDialog
	assert_not_null(warning, "the real session provides a save-failure warning")
	return warning


func _block_temporary_write() -> void:
	assert_eq(DirAccess.make_dir_recursive_absolute(_path() + ".tmp"), OK)


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _next_morning() -> void:
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 15000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	(_main.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


func _state() -> Dictionary:
	return {"clock": Clock._capture_save(), "speed": Clock.speed, "books": Economy._capture_save(),
		"rng": GameState._capture_save(), "world_tick": (_main.get("world") as SimWorld).now}


func _capture_attempt() -> Dictionary:
	_attempts += 1
	return {}


func _restore_attempt(_data: Dictionary) -> bool:
	return true
