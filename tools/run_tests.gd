extends SceneTree
## Headless test runner. Finds res://tests/**/test_*.gd, runs every test_*
## method on a fresh instance per test, prints a summary and exits 1 on any
## failure. A test also fails if it raises an engine or script error (a null call,
## push_error) even when its asserts pass. Usage: godot --headless --path . --script tools/run_tests.gd
## Optional filter: ... --script tools/run_tests.gd -- --filter=clock
## Explicit diagnostics: -- --diagnose-game-session [--through-game-session].
## Tests may await a bounded number of process frames for real UI layout. The
## runner awaits completion before teardown or counting failures; synchronous
## tests still execute immediately. The first await lets the scene root enter.

const TEST_ROOT: String = "res://tests"
const SESSION_TEST: String = "res://tests/world/test_game_session.gd"


func _initialize() -> void:
	var filter := ""
	var diagnose_session: bool = false
	var through_session: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
		elif arg == "--diagnose-game-session":
			diagnose_session = true
		elif arg == "--through-game-session":
			through_session = true
	if (through_session and not diagnose_session) or (diagnose_session and not filter.is_empty()):
		print("FAIL: session diagnostics require an unfiltered full suite or ordered prefix")
		quit(2)
		return
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var files := _find_tests(TEST_ROOT)
	files.sort()
	var selected: PackedStringArray = []
	for path: String in files:
		if filter.is_empty() or path.contains(filter):
			selected.append(path)
		if through_session and path == SESSION_TEST:
			break
	if diagnose_session:
		if not selected.has(SESSION_TEST):
			print("FAIL: diagnostic selection does not include the session test")
			quit(2)
			return
		print("DIAG MODE: %s" % ("prefix" if through_session else "full"))
		for path: String in selected:
			print("DIAG SELECTED: %s" % path)
		print("DIAG PLAN: files=%d target_included=true" % selected.size())
	if files.is_empty():
		print("FAIL: no test files found under %s" % TEST_ROOT)
		quit(1)
		return
	var passed := 0
	var failed := 0
	var completed_files: int = 0
	var completed_methods: int = 0
	var target_methods: int = 0
	for path in selected:
		if not filter.is_empty() or diagnose_session:
			print("TEST FILE: %s" % path)
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL %s: could not load script" % path)
			failed += 1
			continue
		var file_methods: int = 0
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var t: Object = script.new()
			if not t is TestCase:
				print("FAIL %s: does not extend TestCase" % path)
				failed += 1
				break
			var tc: TestCase = t
			var errors_before := errors.count()
			if diagnose_session and path == SESSION_TEST:
				_session_diagnostic("before_fixture", name, tc)
			tc.before_each()
			if diagnose_session and path == SESSION_TEST:
				_session_diagnostic("after_fixture", name, tc)
			await tc.call(name)
			if diagnose_session and path == SESSION_TEST:
				_session_diagnostic("before_teardown", name, tc)
			tc.after_each()
			file_methods += 1
			var failures := tc.take_failures()
			if errors.count() > errors_before:
				failures.append("raised %d engine/script error(s), see the log above" % (errors.count() - errors_before))
			if failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in failures:
					print("FAIL %s::%s  %s" % [path.get_file(), name, f])
		completed_files += 1
		completed_methods += file_methods
		if path == SESSION_TEST:
			target_methods = file_methods
		if diagnose_session:
			print("DIAG FILE: %s methods=%d" % [path, file_methods])
	if diagnose_session:
		print("DIAG COMPLETE: files=%d methods=%d target_methods=%d" % [completed_files, completed_methods, target_methods])
	print("TESTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


## Explicit diagnostic mode only. Never invoke registered providers: a suspect
## callable could mutate state. Read their live identities and known autoload data.
func _session_diagnostic(stage: String, method: String, tc: TestCase) -> void:
	# --script SceneTree entry points resolve autoloads at runtime, as the
	# capture and balance tools do; their names are not compile-time globals.
	var save_system: Node = root.get_node("SaveSystem")
	var game_state: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var economy: Node = root.get_node("Economy")
	var save_dir: String = save_system.get("save_dir")
	var provider_entries: Dictionary = save_system.get("_providers")
	var existing_rngs: Dictionary = game_state.get("_rngs")
	var sim_clock: SimClock = clock.get("sim") as SimClock
	var attached_world: SimWorld = clock.get("attached_world") as SimWorld
	var tick_driver: Callable = clock.get("tick_driver")
	var ledger: Ledger = economy.get("ledger") as Ledger
	var stock: Stock = economy.get("stock") as Stock
	var providers: Array[Dictionary] = []
	for key: String in provider_entries:
		var entry: Dictionary = provider_entries[key]
		var capture: Callable = entry["capture"]
		var restore: Callable = entry["restore"]
		providers.append({"key": key, "capture_valid": capture.is_valid(),
			"capture_owner": capture.get_object_id(), "capture_method": String(capture.get_method()),
			"restore_valid": restore.is_valid(), "restore_owner": restore.get_object_id(),
			"restore_method": String(restore.get_method())})
	var files: Array[Dictionary] = []
	for suffix: String in ["", ".bak", ".tmp"]:
		files.append(_diagnostic_file(save_dir.path_join("test_session.json" + suffix)))
	var directory_files: PackedStringArray = []
	var directory: DirAccess = DirAccess.open(save_dir)
	if directory != null:
		directory_files = directory.get_files()
		directory_files.sort()
	var rngs: Dictionary = {}
	for system: StringName in existing_rngs:
		var generator: RandomNumberGenerator = existing_rngs[system]
		rngs[String(system)] = {"seed": str(generator.seed), "state": str(generator.state)}
	var snapshot: Dictionary = {"stage": stage, "method": method, "pid": OS.get_process_id(),
		"save_dir": save_dir, "absolute_save_dir": ProjectSettings.globalize_path(save_dir),
		"directory_files": directory_files, "providers": providers, "files": files,
		"clock": {"node": clock.get_instance_id(), "sim": sim_clock.get_instance_id(),
			"world": attached_world.get_instance_id() if attached_world != null else 0,
			"driver_valid": tick_driver.is_valid(), "driver_owner": tick_driver.get_object_id(),
			"speed": clock.get("speed"), "accumulator": clock.get("_accumulator"), "state": sim_clock.to_dict()},
		"economy": {"node": economy.get_instance_id(), "ledger": ledger.to_dict(), "stock": stock.to_dict()},
		"game_state": {"node": game_state.get_instance_id(), "master_seed": str(game_state.get("master_seed")), "rngs": rngs},
		"assertions_so_far": tc._failures.duplicate()}
	print("SAVE DIAG: %s" % JSON.stringify(snapshot))


func _diagnostic_file(path: String) -> Dictionary:
	var result: Dictionary = {"path": ProjectSettings.globalize_path(path), "exists": FileAccess.file_exists(path)}
	if not result["exists"]:
		return result
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		result["open_error"] = int(FileAccess.get_open_error())
		return result
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	result["read_error"] = int(file.get_error())
	file.close()
	result["size_bytes"] = bytes.size()
	var digest: HashingContext = HashingContext.new()
	var hash_error: Error = digest.start(HashingContext.HASH_SHA256)
	if hash_error == OK:
		hash_error = digest.update(bytes)
	result["hash_error"] = int(hash_error)
	if hash_error == OK:
		result["sha256"] = digest.finish().hex_encode()
	var contents: String = bytes.get_string_from_utf8()
	result["contents"] = contents
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(contents)
	result["parse_error"] = int(parse_error)
	if parse_error != OK:
		result["parse_error_message"] = parser.get_error_message()
	var document: Variant = parser.data if parse_error == OK else null
	if document is Dictionary and document.get("data") is Dictionary:
		var sections: Dictionary = document["data"]
		var shapes: Dictionary = {}
		for key: Variant in sections:
			shapes[String(key)] = type_string(typeof(sections[key]))
		result["section_types"] = shapes
	return result


func _find_tests(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_find_tests(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out
