extends TestCase
## Fresh isolated save directories exercise actual JSON/file operations.

const SaveScript := preload("res://src/core/save_system.gd")
const GameScript := preload("res://src/core/game_state.gd")
const ClockScript := preload("res://src/core/clock.gd")

class FailedRename:
	extends "res://src/core/save_system.gd"
	var fail_publish: bool = false
	var fail_backup: bool = false

	func _rename_file(source: String, destination: String) -> Error:
		if (fail_publish and source.ends_with(".tmp")) or (fail_backup and destination.ends_with(".bak")):
			return ERR_CANT_CREATE
		return super._rename_file(source, destination)

var _save: SaveScript
var _game: GameScript
var _clock: ClockScript
var _first: Dictionary = {"value": 3}
var _second: Dictionary = {"name": "Diner", "items": ["bun", "cheese"]}
var _restore_calls: int = 0


func before_each() -> void:
	_save = SaveScript.new()
	_save.save_dir = "user://test_saves/issue18_%s" % _save.get_instance_id()
	_save.register("first", _capture_first, _restore_first)
	_save.register("second", _capture_second, _restore_second)


func after_each() -> void:
	var directory: DirAccess = DirAccess.open(_save.save_dir)
	if directory != null:
		for file: String in directory.get_files():
			DirAccess.remove_absolute(_save.save_dir.path_join(file))
		DirAccess.remove_absolute(_save.save_dir)
	_save.free()
	if _game != null:
		_game.free()
	if _clock != null:
		_clock.free()


func test_two_providers_round_trip_and_envelope() -> void:
	assert_eq(_save.save_game("morning"), OK)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path("morning")))
	assert_eq(int(document["version"]), 1)
	assert_true(float(document["saved_at"]) > 0.0)
	_first.clear()
	_second.clear()
	assert_eq(_save.load_game("morning"), OK)
	assert_eq(int(_first["value"]), 3)
	assert_eq(_second["name"], "Diner")
	assert_eq(_second["items"], ["bun", "cheese"])
	assert_eq(_restore_calls, 2)


func test_replacement_save_overwrites_without_temporary_file() -> void:
	assert_eq(_save.save_game("slot-1"), OK)
	_first["value"] = 9
	assert_eq(_save.save_game("slot-1"), OK)
	assert_false(FileAccess.file_exists(_path("slot-1") + ".tmp"))
	_first.clear()
	assert_eq(_save.load_game("slot-1"), OK)
	assert_eq(int(_first["value"]), 9)


func test_registering_same_key_replaces_provider() -> void:
	_save.register("first", _capture_second, _restore_second)
	assert_eq(_save.save_game("replace"), OK)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path("replace")))
	assert_eq(document["data"]["first"]["name"], "Diner")
	assert_eq(document["data"].size(), 2)


func test_missing_corrupt_and_future_version_errors() -> void:
	assert_eq(_save.load_game("missing"), ERR_FILE_NOT_FOUND)
	_write("broken", "{bad json")
	assert_eq(_save.load_game("broken"), ERR_PARSE_ERROR)
	_write("future", JSON.stringify({"version": 2, "data": {}}))
	assert_eq(_save.load_game("future"), ERR_FILE_UNRECOGNIZED)
	assert_eq(_restore_calls, 0)


func test_invalid_slot_names_never_create_files() -> void:
	for slot: String in ["", "../escape", "Upper", "a/b", "x.y", "a b", "a\n", "a".repeat(33), "é"]:
		assert_eq(_save.save_game(slot), ERR_INVALID_PARAMETER, slot)
		assert_eq(_save.load_game(slot), ERR_INVALID_PARAMETER, slot)
		assert_eq(_save.delete_slot(slot), ERR_INVALID_PARAMETER, slot)
	assert_eq(_save.list_slots(), PackedStringArray())
	assert_false(DirAccess.dir_exists_absolute(_save.save_dir))


func test_valid_slot_boundaries() -> void:
	assert_eq(_save.save_game("a"), OK)
	assert_eq(_save.save_game("a0_-".repeat(8)), OK)
	assert_eq(_save.list_slots().size(), 2)


func test_version_zero_migrates_and_missing_section_is_skipped() -> void:
	_write("old", JSON.stringify({"version": 0, "data": {"first": {"value": 41}}}))
	assert_eq(_save.load_game("old"), OK)
	assert_eq(int(_first["value"]), 41)
	assert_eq(_second["name"], "Diner")
	assert_eq(_restore_calls, 1)


func test_missing_all_sections_and_unknown_sections_are_allowed() -> void:
	_write("empty", JSON.stringify({"version": 1, "data": {"future_system": {"x": 1}}}))
	assert_eq(_save.load_game("empty"), OK)
	assert_eq(_restore_calls, 0)


func test_failed_provider_returns_failed() -> void:
	_save.register("first", _capture_first, _reject_restore)
	assert_eq(_save.save_game("fail"), OK)
	assert_eq(_save.load_game("fail"), FAILED)


func test_malformed_envelopes_and_sections_are_rejected_before_restore() -> void:
	for document: Variant in [[], {}, {"version": -1, "data": {}}, {"version": 0.5, "data": {}},
		{"version": "1", "data": {}}, {"version": 1, "data": []},
		{"version": 1, "data": {"first": {}, "second": []}}]:
		_write("shape", JSON.stringify(document))
		assert_eq(_save.load_game("shape"), ERR_PARSE_ERROR)
	assert_eq(_restore_calls, 0)


func test_list_and_delete_ignore_temporary_and_unrelated_files() -> void:
	assert_eq(_save.save_game("z"), OK)
	assert_eq(_save.save_game("a"), OK)
	_write("ignored.json.tmp", "partial", false)
	_write("INVALID.json", "{}", false)
	assert_eq(_save.list_slots(), PackedStringArray(["a", "z"]))
	assert_eq(_save.delete_slot("a"), OK)
	assert_eq(_save.delete_slot("a"), ERR_FILE_NOT_FOUND)
	assert_eq(_save.list_slots(), PackedStringArray(["z"]))


func test_rng_continues_exactly_after_json_save_load() -> void:
	_game = GameScript.new()
	_game.new_run(9223372036854775806)
	var customers: RandomNumberGenerator = _game.rng(&"customers")
	var kitchen: RandomNumberGenerator = _game.rng(&"kitchen")
	customers.seed = 9223372036854775805
	kitchen.seed = -9223372036854775807
	for index: int in range(11):
		customers.randi()
		kitchen.randi()
	_save.register("game_state", _game._capture_save, _game._restore_save)
	assert_eq(_save.save_game("rng"), OK)
	var expected_customers: Array[int] = []
	var expected_kitchen: Array[int] = []
	for index: int in range(8):
		expected_customers.append(customers.randi())
		expected_kitchen.append(kitchen.randi())
	_game.new_run(4)
	_game.rng(&"unrelated")
	assert_eq(_save.load_game("rng"), OK)
	assert_eq(_game.master_seed, 9223372036854775806)
	assert_false(_game._capture_save()["rngs"].has("unrelated"))
	for index: int in range(8):
		assert_eq(_game.rng(&"customers").randi(), expected_customers[index])
		assert_eq(_game.rng(&"kitchen").randi(), expected_kitchen[index])
	var baseline: GameScript = GameScript.new()
	baseline.new_run(_game.master_seed)
	assert_eq(_game.rng(&"new_system").randi(), baseline.rng(&"new_system").randi())
	baseline.free()


func test_clock_restore_replaces_sim_and_rebinds_phase_signal() -> void:
	_clock = ClockScript.new()
	_clock.sim.open_ticks = 3
	_clock.sim.start_service()
	_clock.sim.advance()
	_save.register("clock", _clock._capture_save, _clock._restore_save)
	assert_eq(_save.save_game("clock"), OK)
	var previous: SimClock = _clock.sim
	_clock.sim.advance()
	assert_eq(_save.load_game("clock"), OK)
	assert_true(previous != _clock.sim)
	assert_eq(_clock.sim.tick, 1)
	assert_eq(_clock.sim.phase, SimClock.Phase.OPEN)
	assert_false(previous.phase_changed.is_connected(_clock._on_phase_changed))
	assert_true(_clock.sim.phase_changed.is_connected(_clock._on_phase_changed))
	_clock.sim.advance()
	assert_eq(_clock.sim.tick, 2)


func test_invalid_rng_section_leaves_existing_run_unchanged() -> void:
	_game = GameScript.new()
	_game.new_run(42)
	_game.rng(&"customers").randi()
	var original: Dictionary = _game._capture_save()
	assert_false(_game._restore_save({"master_seed": "1", "rngs": {"customers": {"seed": "1", "state": "bad"}}}))
	assert_eq(_game._capture_save(), original)


func test_interrupted_states_prefer_final_then_recover_backup() -> void:
	assert_eq(_save.save_game("recover"), OK)
	_first["value"] = 4
	assert_eq(_save.save_game("recover"), OK)
	# Before rotating the final, an old backup and an uncommitted tmp can exist.
	_write("recover.json.tmp", "{unfinished", false)
	_first.clear()
	assert_eq(_save.load_game("recover"), OK)
	assert_eq(int(_first["value"]), 4)
	# After rotation and before publication, only backup + tmp may remain.
	assert_eq(DirAccess.remove_absolute(_path("recover") + ".bak"), OK)
	assert_eq(DirAccess.rename_absolute(_path("recover"), _path("recover") + ".bak"), OK)
	_first.clear()
	assert_eq(_save.list_slots(), PackedStringArray(["recover"]))
	assert_eq(_save.load_game("recover"), OK)
	assert_eq(int(_first["value"]), 4)
	# Resume after interruption, retaining the valid backup during publication.
	_first["value"] = 5
	assert_eq(_save.save_game("recover"), OK)
	assert_true(FileAccess.file_exists(_path("recover") + ".bak"))
	_first.clear()
	assert_eq(_save.load_game("recover"), OK)
	assert_eq(int(_first["value"]), 5)


func test_rng_rejects_out_of_range_integer_strings_without_mutating_run() -> void:
	_game = GameScript.new()
	_game.new_run(42)
	_game.rng(&"customers").randi()
	var original: Dictionary = _game._capture_save()
	for invalid: String in ["9223372036854775808", "-9223372036854775809", "9".repeat(100), "-" + "9".repeat(100)]:
		var master: Dictionary = original.duplicate(true)
		master["master_seed"] = invalid
		assert_false(_game._restore_save(master))
		assert_eq(_game._capture_save(), original)
		for field: String in ["seed", "state"]:
			var system: Dictionary = original.duplicate(true)
			system["rngs"]["customers"][field] = invalid
			assert_false(_game._restore_save(system))
			assert_eq(_game._capture_save(), original)
	assert_true(_game._restore_save({"master_seed": "-9223372036854775808",
		"rngs": {"customers": {"seed": "9223372036854775807", "state": "-9223372036854775808"}}}))
	assert_eq(_game.master_seed, -9223372036854775807 - 1)
	assert_eq(_game.rng(&"customers").seed, 9223372036854775807)


func test_clock_rejects_malformed_numeric_fields_without_replacing_sim() -> void:
	_clock = ClockScript.new()
	_clock.sim.start_service()
	_clock.sim.advance()
	var original: SimClock = _clock.sim
	var original_data: Dictionary = original.to_dict()
	for key: String in original_data:
		for invalid: Variant in [{}, [], "1", true, -1, 0.5, 1e30]:
			var data: Dictionary = original_data.duplicate(true)
			data[key] = invalid
			assert_false(_clock._restore_save(data), key)
			assert_true(_clock.sim == original, key)
			assert_eq(_clock.sim.to_dict(), original_data)
	for malformed: Dictionary in [{"day": 0}, {"phase": 4}, {"open_ticks": 0},
		{"last_orders_max_ticks": 0}, {"display_open_minute": 1441},
		{"display_close_minute": 1441}, {"display_open_minute": 900, "display_close_minute": 800}]:
		assert_false(_clock._restore_save(malformed))
		assert_true(_clock.sim == original)
	# Numbers parsed from a valid JSON clock remain supported.
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(original_data))
	assert_true(_clock._restore_save(parsed))
	assert_eq(_clock.sim.to_dict(), original_data)


func test_corrupt_final_recovers_backup_and_ignores_temporary() -> void:
	assert_eq(_save.save_game("recover"), OK)
	_first["value"] = 8
	assert_eq(_save.save_game("recover"), OK)
	_write("recover", "{damaged")
	_write("recover.json.tmp", JSON.stringify({"version": 1, "data": {"first": {"value": 99}}}), false)
	_first.clear()
	assert_eq(_save.load_game("recover"), OK)
	assert_eq(int(_first["value"]), 3)
	# Another successful save must retain that last readable copy.
	_first["value"] = 10
	assert_eq(_save.save_game("recover"), OK)
	_write("recover", "{damaged again")
	assert_eq(_save.load_game("recover"), OK)
	assert_eq(int(_first["value"]), 3)


func test_failed_publication_after_rotating_existing_backup_keeps_latest_save() -> void:
	var failing: FailedRename = _use_failing_save()
	assert_eq(_save.save_game("fail"), OK)
	_first["value"] = 8
	assert_eq(_save.save_game("fail"), OK)
	failing.fail_publish = true
	_first["value"] = 12
	assert_eq(_save.save_game("fail"), ERR_CANT_CREATE)
	assert_false(FileAccess.file_exists(_path("fail")))
	assert_true(FileAccess.file_exists(_path("fail") + ".bak"))
	assert_false(FileAccess.file_exists(_path("fail") + ".tmp"))
	_first.clear()
	assert_eq(_save.load_game("fail"), OK)
	assert_eq(int(_first["value"]), 8)


func test_failed_backup_move_preserves_final_after_old_backup_removed() -> void:
	var failing: FailedRename = _use_failing_save()
	assert_eq(_save.save_game("fail"), OK)
	_first["value"] = 8
	assert_eq(_save.save_game("fail"), OK)
	failing.fail_backup = true
	_first["value"] = 12
	assert_eq(_save.save_game("fail"), ERR_CANT_CREATE)
	assert_true(FileAccess.file_exists(_path("fail")))
	_first.clear()
	assert_eq(_save.load_game("fail"), OK)
	assert_eq(int(_first["value"]), 8)


func test_failed_publish_with_damaged_final_preserves_only_valid_backup() -> void:
	var failing: FailedRename = _use_failing_save()
	assert_eq(_save.save_game("fail"), OK)
	_first["value"] = 8
	assert_eq(_save.save_game("fail"), OK)
	_write("fail", "{damaged")
	failing.fail_publish = true
	_first["value"] = 12
	assert_eq(_save.save_game("fail"), ERR_CANT_CREATE)
	_first.clear()
	assert_eq(_save.load_game("fail"), OK)
	assert_eq(int(_first["value"]), 3)


func test_unreadable_backup_is_not_restored_and_unknown_future_is_not_rolled_back() -> void:
	_write("bad.json.bak", "{bad backup", false)
	assert_eq(_save.load_game("bad"), ERR_PARSE_ERROR)
	_write("bad", "{bad final")
	assert_eq(_save.load_game("bad"), ERR_PARSE_ERROR)
	# A future save is not corruption: preserve its explicit version error.
	assert_eq(_save.save_game("future"), OK)
	_first["value"] = 8
	assert_eq(_save.save_game("future"), OK)
	_write("future", JSON.stringify({"version": 2, "data": {}}))
	assert_eq(_save.load_game("future"), ERR_FILE_UNRECOGNIZED)
	assert_eq(_restore_calls, 0)


func test_delete_removes_backup_and_temporary_to_prevent_resurrection() -> void:
	assert_eq(_save.save_game("delete"), OK)
	assert_eq(_save.save_game("delete"), OK)
	_write("delete.json.tmp", "{partial", false)
	assert_eq(_save.delete_slot("delete"), OK)
	assert_false(FileAccess.file_exists(_path("delete")))
	assert_false(FileAccess.file_exists(_path("delete") + ".bak"))
	assert_false(FileAccess.file_exists(_path("delete") + ".tmp"))
	assert_eq(_save.load_game("delete"), ERR_FILE_NOT_FOUND)
	assert_eq(_save.list_slots(), PackedStringArray())
	assert_eq(_save.save_game("backup_only"), OK)
	assert_eq(DirAccess.rename_absolute(_path("backup_only"), _path("backup_only") + ".bak"), OK)
	assert_eq(_save.delete_slot("backup_only"), OK)
	assert_eq(_save.list_slots(), PackedStringArray())


func _use_failing_save() -> FailedRename:
	var directory: String = _save.save_dir
	_save.free()
	var failing: FailedRename = FailedRename.new()
	failing.save_dir = directory
	failing.register("first", _capture_first, _restore_first)
	failing.register("second", _capture_second, _restore_second)
	_save = failing
	return failing


func _capture_first() -> Dictionary:
	return _first.duplicate(true)


func _capture_second() -> Dictionary:
	return _second.duplicate(true)


func _restore_first(data: Dictionary) -> bool:
	_restore_calls += 1
	_first = data
	return true


func _restore_second(data: Dictionary) -> bool:
	_restore_calls += 1
	_second = data
	return true


func _reject_restore(_data: Dictionary) -> bool:
	return false


func _path(slot: String) -> String:
	return _save.save_dir.path_join(slot + ".json")


func _write(slot: String, text: String, add_extension: bool = true) -> void:
	assert_eq(DirAccess.make_dir_recursive_absolute(_save.save_dir), OK)
	var path: String = _path(slot) if add_extension else _save.save_dir.path_join(slot)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(text)
		file.close()
