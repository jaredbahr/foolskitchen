extends SceneTree
## Headless test runner. Finds res://tests/**/test_*.gd, runs every test_*
## method on a fresh instance per test, prints a summary and exits 1 on any
## failure. Usage: godot --headless --path . --script tools/run_tests.gd
## Optional filter: ... --script tools/run_tests.gd -- --filter=clock

const TEST_ROOT: String = "res://tests"


func _initialize() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
	var files := _find_tests(TEST_ROOT)
	files.sort()
	var passed := 0
	var failed := 0
	for path in files:
		if not filter.is_empty() and not path.contains(filter):
			continue
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
			tc.before_each()
			tc.call(name)
			tc.after_each()
			var failures := tc.take_failures()
			if failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in failures:
					print("FAIL %s::%s  %s" % [path.get_file(), name, f])
	print("TESTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


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
