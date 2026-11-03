extends TestCase
## Rejected-load feedback through real title/session paths; save policy is unchanged.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "autosave"

var _main: Node
var _nodes: Array[Node] = []
var _old_scene: Node
var _save_dir: String
var _old_save_dir: String
var _old_clock: Dictionary = {}
var _old_books: Dictionary = {}
var _old_providers: Dictionary = {}
var _old_rngs: Dictionary[StringName, RandomNumberGenerator] = {}
var _old_seed: int
var _attempts: int = 0


func before_each() -> void:
	_old_scene = _tree().current_scene
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "autosave_load_feedback")
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
	for node: Node in _nodes:
		if is_instance_valid(node):
			if _tree().current_scene == node:
				_tree().current_scene = null
			node.free()
	_nodes.clear()
	_tree().current_scene = _old_scene if is_instance_valid(_old_scene) else null
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


func test_real_continue_explains_rejected_provider_without_touching_save_copies_or_retrying() -> void:
	_start(true)
	_next_morning()
	_close()
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	document["data"]["economy"]["ledger"] = 5
	_write(JSON.stringify(document))
	var rejected: PackedByteArray = FileAccess.get_file_as_bytes(_path())
	var recovery: PackedByteArray = FileAccess.get_file_as_bytes(_path() + ".bak")
	assert_false(recovery.is_empty())
	var title: TitleScreen = _title()
	assert_true(title.continue_button.visible)
	title.continue_button.pressed.emit()
	for frame: int in 4:
		await _tree().process_frame
	_main = _tree().current_scene
	_nodes.append(_main)
	assert_eq(_main.scene_file_path, "res://src/world/main.tscn")
	assert_eq(Clock.sim.day, 1, "the existing rejected-load fallback still opens a fresh shop")
	assert_eq(_attempts, 2, "the guarded initial morning does not save over a rejected slot")
	assert_eq(FileAccess.get_file_as_bytes(_path()), rejected)
	assert_eq(FileAccess.get_file_as_bytes(_path() + ".bak"), recovery)
	var warning: AcceptDialog = _warning()
	if warning == null:
		return
	assert_true(warning.visible, "Continue must explain why it opened a fresh shop")
	assert_true(warning.dialog_text.contains("fresh shop"))
	assert_true(warning.dialog_text.contains("next morning"))
	var before: Dictionary = _state()
	warning.get_ok_button().pressed.emit()
	assert_false(warning.visible)
	assert_eq(_state(), before, "acknowledgement changes no simulation state")
	assert_eq(_attempts, 2, "acknowledgement is not a retry or save point")
	assert_eq(FileAccess.get_file_as_bytes(_path()), rejected)
	assert_eq(FileAccess.get_file_as_bytes(_path() + ".bak"), recovery)
	_next_morning()
	assert_eq(_attempts, 3, "the next ordinary morning keeps its existing save attempt")
	assert_false(warning.visible, "the one-time load warning does not repeat next morning")
	assert_eq(FileAccess.get_file_as_bytes(_path() + ".bak"), rejected,
		"ordinary replacement retains the previous final as before")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	assert_eq(int(saved["data"]["clock"]["day"]), 2)


func test_rejected_load_waits_for_owner_creation_before_showing_the_warning() -> void:
	_write(JSON.stringify({"version": 1, "data": {"economy": {"ledger": 5}}}))
	var rejected: PackedByteArray = FileAccess.get_file_as_bytes(_path())
	_start(true, true)
	assert_true(_main.call("is_owner_picker_visible"))
	var warning: AcceptDialog = _main.get_node_or_null("Overlay/AutosaveLoadFailure") as AcceptDialog
	if warning != null:
		assert_false(warning.visible, "creation stays usable until the morning checkpoint")
	assert_eq(_attempts, 0)
	var picker: OwnerPicker = _main.get("_owner_picker") as OwnerPicker
	(picker.get_node("%Confirm") as Button).pressed.emit()
	assert_false(_main.call("is_owner_picker_visible"))
	assert_true((_main.get_node("HUD") as CanvasLayer).visible)
	warning = _warning()
	if warning == null:
		return
	assert_true(warning.visible, "the completed initial morning explains the rejected save")
	assert_eq(_attempts, 0)
	assert_eq(FileAccess.get_file_as_bytes(_path()), rejected)


func test_missing_valid_recovered_and_unsaved_sessions_do_not_show_a_load_warning() -> void:
	_start(true)
	_assert_no_warning(_main)
	_next_morning()
	_close()
	_start(true)
	assert_eq(Clock.sim.day, 2, "valid saves still resume normally")
	_assert_no_warning(_main)
	_close()
	# A syntax-damaged final uses the real valid backup; it is a successful load.
	_write("{not json")
	_start(true)
	assert_eq(Clock.sim.day, 2, "backup recovery remains the loader's existing policy")
	_assert_no_warning(_main)
	_close()
	var attempts: int = _attempts
	_start(false)
	_assert_no_warning(_main)
	assert_eq(_attempts, attempts)
	_close()
	_write(JSON.stringify({"version": 1, "data": {"economy": {"ledger": 5}}}))
	var rejected: PackedByteArray = FileAccess.get_file_as_bytes(_path())
	var title: TitleScreen = _title()
	var backdrop: Node = title.get("_backdrop") as Node
	_assert_no_warning(backdrop)
	assert_eq(_attempts, attempts, "the title backdrop never starts a session or save")
	assert_eq(FileAccess.get_file_as_bytes(_path()), rejected)


func _start(with_saves: bool, creating: bool = false) -> void:
	_main = MAIN.instantiate()
	_nodes.append(_main)
	_main.set("use_saves", with_saves)
	_main.set("skip_owner_picker", not creating)
	_main.set("owner_creation_requested", creating)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	_tree().root.add_child(_main)
	_main.call("start")


func _title() -> TitleScreen:
	var title: TitleScreen = (load("res://src/ui/title_screen.tscn") as PackedScene).instantiate() as TitleScreen
	_nodes.append(title)
	_tree().root.add_child(title)
	_tree().current_scene = title
	title.start()
	return title


func _close() -> void:
	if _tree().current_scene == _main:
		_tree().current_scene = null
	_main.free()
	_main = null


func _warning() -> AcceptDialog:
	var warning: AcceptDialog = _main.get_node_or_null("Overlay/AutosaveLoadFailure") as AcceptDialog
	assert_not_null(warning, "the actual session provides rejected-save feedback")
	return warning


func _assert_no_warning(main: Node) -> void:
	var warning: AcceptDialog = main.get_node_or_null("Overlay/AutosaveLoadFailure") as AcceptDialog
	if warning != null:
		assert_false(warning.visible)


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _write(text: String) -> void:
	assert_eq(DirAccess.make_dir_recursive_absolute(_save_dir), OK)
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _next_morning() -> void:
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 15000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	(_main.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


func _state() -> Dictionary:
	return {"clock": Clock._capture_save(), "speed": Clock.speed, "books": Economy._capture_save(),
		"rng": GameState._capture_save(), "world_tick": (_main.get("world") as SimWorld).now}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _capture_attempt() -> Dictionary:
	_attempts += 1
	return {}


func _restore_attempt(_data: Dictionary) -> bool:
	return true
