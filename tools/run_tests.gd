extends SceneTree
## Headless test runner. Finds res://tests/**/test_*.gd, runs every test_*
## method on a fresh instance per test, prints a summary and exits 1 on any
## failure. A test also fails if it raises an engine or script error (a null call,
## push_error) even when its asserts pass. Usage: godot --headless --path . --script tools/run_tests.gd
## Optional filter: ... --script tools/run_tests.gd -- --filter=clock
## Optional shard: --shard=K/N runs shard K of N, so N processes can split the
## suite (tools/check.sh: TEST_SHARDS, default 2; CI uses 4). Files are dealt
## by their recorded time (tools/test_shards.gd), so the shards stay level when
## a test is added.
## Optional timing: ... -- --write-durations runs every file in one process and
## rewrites tools/test_durations.json. Run it by hand when the suite has changed
## a lot; a file with no recorded time counts as the median until then.
## Tests may await a bounded number of process frames for real UI layout. The
## runner awaits completion before teardown or counting failures; synchronous
## tests still execute immediately. The first await lets the scene root enter.

const TEST_ROOT: String = "res://tests"


func _initialize() -> void:
	var filter := ""
	var shard: int = 0
	var shards: int = 1
	var write_durations := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
		elif arg == "--write-durations":
			write_durations = true
		elif arg.begins_with("--shard="):
			var parts: PackedStringArray = arg.trim_prefix("--shard=").split("/")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() \
					or int(parts[1]) < 1 or int(parts[0]) < 0 or int(parts[0]) >= int(parts[1]):
				print("FAIL: --shard needs K/N with 0 <= K < N")
				quit(1)
				return
			shard = int(parts[0])
			shards = int(parts[1])
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var files := _find_tests(TEST_ROOT)
	files.sort()
	if write_durations and (shards > 1 or not filter.is_empty()):
		print("FAIL: --write-durations times the whole suite; do not combine it with --shard or --filter")
		quit(1)
		return
	if shards > 1:
		var durations: Dictionary = TestShards.load_durations()
		var assignment: Array[PackedStringArray] = TestShards.assign(files, durations, shards)
		var loads: Array[float] = TestShards.loads_ms(assignment, durations)
		print("SHARD %d/%d: %d of %d files, recorded %.0f s (all shards: %s s)" % [shard, shards,
			assignment[shard].size(), files.size(), loads[shard] / 1000.0,
			", ".join(loads.map(func(ms: float) -> String: return "%.0f" % (ms / 1000.0)))])
		files = assignment[shard]
	if files.is_empty():
		print("FAIL: no test files found under %s" % TEST_ROOT)
		quit(1)
		return
	var passed := 0
	var failed := 0
	var measured: Dictionary = {}
	# Let the scene root enter the tree before any test, so no test passes or
	# fails depending on which file happened to await a frame first.
	await process_frame
	for path in files:
		if not filter.is_empty() and not path.contains(filter):
			continue
		if not filter.is_empty():
			print("TEST FILE: %s" % path)
		var file_started: int = Time.get_ticks_msec()
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL %s: could not load script" % path)
			failed += 1
			continue
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
			tc.before_each()
			await tc.call(name)
			tc.after_each()
			var failures := tc.take_failures()
			if errors.count() > errors_before:
				failures.append("raised %d engine/script error(s), see the log above" % (errors.count() - errors_before))
			if failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in failures:
					print("FAIL %s::%s  %s" % [path.get_file(), name, f])
		measured[path] = Time.get_ticks_msec() - file_started
	if write_durations and failed == 0:
		_write_durations(measured)
	print("TESTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


## Sorted keys and one file a line, so two branches that add tests merge cleanly.
func _write_durations(measured: Dictionary) -> void:
	var paths: Array = measured.keys()
	paths.sort()
	var lines: PackedStringArray = []
	for path: String in paths:
		lines.append("\t%s: %d" % [JSON.stringify(path), int(measured[path])])
	var file := FileAccess.open(TestShards.DURATIONS_PATH, FileAccess.WRITE)
	if file == null:
		print("FAIL: could not write %s" % TestShards.DURATIONS_PATH)
		return
	file.store_string("{\n" + ",\n".join(lines) + "\n}\n")
	file.close()
	print("DURATIONS: wrote %d files to %s" % [paths.size(), TestShards.DURATIONS_PATH])


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
