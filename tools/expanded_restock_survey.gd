extends SceneTree
## Manual FK-096 seeds1-50 survey. Never run as an extra CI loop.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if output.is_empty() or FileAccess.file_exists(output):
		print("Use a fresh --out=<json> path")
		quit(2)
		return
	var errors: ErrorCounter = ErrorCounter.new()
	OS.add_logger(errors)
	# Load after autoloads, exactly as the ordinary test runner does.
	var script: GDScript = load("res://tools/expanded_restock_survey_case.gd")
	var rows: Array[Dictionary] = []
	var unexpected: int = 0
	for seed_value: int in range(1, 51):
		var survey: TestCase = script.new() as TestCase
		survey.set("survey_seed", seed_value)
		survey.before_each()
		await survey.call("test_five_days_keep_books_guests_and_shop_consistent")
		var failures: PackedStringArray = survey.take_failures()
		var other_failures: PackedStringArray = []
		for failure: String in failures:
			if not failure.contains(" restocked"):
				other_failures.append(failure)
		var mornings: Array = (survey.get("mornings") as Array).duplicate(true)
		survey.after_each()
		unexpected += other_failures.size()
		rows.append({"seed": seed_value, "mornings": mornings,
			"original_soak_failures": failures, "non_restock_failures": other_failures})
		print("RESTOCK SURVEY seed=",seed_value,"/50 other_failures=",other_failures.size())
	var report: Dictionary = {"scenario": "test_expanded_shop_invariants: five days, $115 wing/table, reload before day3",
		"seeds": rows, "non_restock_failures": unexpected, "engine_errors": errors.count()}
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		OS.remove_logger(errors)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	OS.remove_logger(errors)
	quit(0 if unexpected == 0 and errors.count() == 0 else 1)