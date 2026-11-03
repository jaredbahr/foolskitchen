extends TestCase
## Loading the full suite first hides #270. Run the original catalogue file
## in a fresh engine and inspect its complete log, including shutdown.

const TIMEOUT_MS: int = 30000


func test_catalogue_alone_passes_and_releases_its_scripts_at_exit() -> void:
	var arguments: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/run_tests.gd", "--",
		"--filter=test_build_buy_catalogue.gd",
	]
	# Godot closes --log-file before reporting exit-time resource retention.
	# Read OS pipes instead, so diagnostics after logger teardown count too.
	var child: Dictionary = OS.execute_with_pipe(OS.get_executable_path(), arguments, false)
	assert_false(child.is_empty(), "the isolated catalogue process starts")
	if child.is_empty():
		return
	var pid: int = child["pid"]
	var stdout_pipe: FileAccess = child["stdio"]
	var stderr_pipe: FileAccess = child["stderr"]
	var output: String = ""
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		output += _read_available(stdout_pipe) + _read_available(stderr_pipe)
		await tree.process_frame
	var timed_out: bool = OS.is_process_running(pid)
	if timed_out:
		OS.kill(pid)
		deadline = Time.get_ticks_msec() + 2000
		while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
			output += _read_available(stdout_pipe) + _read_available(stderr_pipe)
			await tree.process_frame
	output += _read_available(stdout_pipe) + _read_available(stderr_pipe)
	stdout_pipe.close()
	stderr_pipe.close()
	assert_false(timed_out, "the isolated run finishes within 30 seconds")
	assert_false(OS.is_process_running(pid), "no child process remains")
	assert_eq(OS.get_process_exit_code(pid), 0, "the original runner exits successfully")
	assert_true(output.contains("TEST FILE: res://tests/ui/test_build_buy_catalogue.gd"),
		"the child selects the original catalogue file")
	assert_true(output.contains("TESTS: 16 passed, 0 failed"), "all sixteen original tests run")
	for diagnostic: String in ["WARNING:", "ERROR:", "SCRIPT ERROR", "Parse Error", "Leaked instance:"]:
		assert_false(output.contains(diagnostic), "isolated shutdown must be clean: %s\n%s" % [diagnostic, output])


func _read_available(pipe: FileAccess) -> String:
	return pipe.get_buffer(65536).get_string_from_utf8()
