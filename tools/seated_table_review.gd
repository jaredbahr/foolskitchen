extends SceneTree
## Manual real-table sweep. Generated JSON and PNGs stay outside the repo.
## --out=<fresh-directory> [--native-bake] [--capture] [--quick] [--authored] [--capture-only]
## --capture-only is a fast cross-table capture of the unleaned baseline and, when
## the chair authors a lean, the leaned pose (one image per distinct lean).
## The broad all-table/rotation/look/time trial sweep is the default (--sweep).
## Trial sweeps report rejected poses without treating a rejected trial as an
## engine failure. --authored requires the actual chair to clear every table.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var output: String = ""
	var native_bake: bool = false
	var capture: bool = false
	var quick: bool = false
	var authored: bool = false
	var capture_only: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
		native_bake = native_bake or argument == "--native-bake"
		capture = capture or argument == "--capture"
		quick = quick or argument == "--quick"
		authored = authored or argument == "--authored"
		capture_only = capture_only or argument == "--capture-only"
	if capture_only:
		native_bake = true
		capture = true
	if output.is_empty() or DirAccess.dir_exists_absolute(output) \
			or ((native_bake or capture) and DisplayServer.get_name() == "headless"):
		print("Use a fresh --out directory; native bake/capture needs rendered Compatibility")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	root.size = Vector2i(1200, 850)
	var errors: ErrorCounter = ErrorCounter.new()
	OS.add_logger(errors)
	var catalogue: GDScript = load("res://tools/seated_table_clearance.gd")
	var leans: Array[float] = [0.0, 10.0, 12.5, 15.0]
	if authored or capture_only:
		var content: ContentDB = ContentDB.new()
		if not content.load_all().is_empty():
			OS.remove_logger(errors)
			quit(1)
			return
		if content.item(&"chair").seated_forward_offset != 0.0:
			print("Authored table review refuses an unmeasured nonzero chair offset")
			OS.remove_logger(errors)
			quit(1)
			return
		leans = [content.item(&"chair").seated_lean_degrees]
		# The baseline is the unleaned sit; add it only when the chair leans.
		if capture_only and leans[0] != 0.0:
			leans.push_front(0.0)
	var turns: Array[int] = [0, 1, 2, 3]
	var looks: Array[int] = []
	for look: int in PersonPresentation.GUEST_MODELS.size():
		looks.append(look)
	var fractions: Array[float] = [0.0, 0.37, 0.91]
	if quick:
		turns = [0]
		fractions = [0.0]
	var table_ids: Array[StringName] = [&"cross_table", &"glass_table", &"cloth_table", &"round_table"]
	if capture_only:
		turns = [0]
		looks = [PersonPresentation.GUEST_MODELS.find(&"character-female-e")]
		fractions = [0.0]
		table_ids = [&"cross_table"]
	var report: Dictionary = await catalogue.run(root, leans, turns, looks, fractions,
		native_bake, output if capture else "", table_ids)
	report["engine_errors"] = errors.count()
	report["authored"] = authored
	var file: FileAccess = FileAccess.open(output.path_join("table-clearance.json"), FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	OS.remove_logger(errors)
	var valid: bool = (report["errors"] as PackedStringArray).is_empty() \
		and report["coverage_complete"] and errors.count() == 0
	if authored or capture_only:
		valid = valid and int(report["failures"]) == 0 and int(report["opposite_head_regressions"]) == 0
	if capture_only:
		valid = valid and (report["captures"] as Array).size() == leans.size()
	print("REAL TABLE REVIEW: ", "PASS" if valid else "FAIL", "; pairs=", (report["pairs"] as Array).size(),
		"; head/table violations=", report["failures"], "; errors=", report["errors"])
	quit(0 if valid else 1)
