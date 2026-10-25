extends TestCase
## Option/provenance checks plus one private native Staff-grid validation.
## No screenshot, rendered capture fixture or device preference is created.

const CAPTURE: Script = preload("res://tools/screenshot.gd")


func test_catalogue_review_requires_one_profile_paused_main_and_exact_schedule() -> void:
	for profile: String in ["rustic", "modern"]:
		var arguments: PackedStringArray = PackedStringArray(["--catalogue-review=" + profile, "--speed=0", "--frames=90,120"])
		var accepted: Dictionary = CAPTURE.catalogue_review_options(arguments)
		assert_eq(accepted["error"], "")
		assert_eq(accepted["profile"], StringName(profile))
		arguments.append_array(["--out=screens/catalogue", "--out=screens/catalogue", "--scene=res://src/world/main.tscn"])
		assert_eq(CAPTURE.catalogue_review_options(arguments)["error"], "", "the shell duplicates --out")
		for extra: String in ["--catalogue-review=rustic", "--catalogue-review=unknown", "--loan-review", "--open", "--fast=1",
				"--select=owner", "--assign-owner=kitchen", "--f3", "--menu", "--staff", "--settings", "--settings-world",
				"--hud-layout", "--window-size=1600x900", "--door-queue", "--report", "--build=green", "--paint", "--quarter=0",
				"--speed=0", "--speed=1", "--frames=90,120", "--frames=120,90", "--scene=res://other.tscn", "--unknown"]:
			var invalid: PackedStringArray = arguments.duplicate()
			invalid.append(extra)
			assert_false(String(CAPTURE.catalogue_review_options(invalid)["error"]).is_empty(), extra)
	for arguments: PackedStringArray in [PackedStringArray(["--catalogue-review"]), PackedStringArray(["--catalogue-review=yes"]),
			PackedStringArray(["--catalogue-review=rustic", "--speed=0"]), PackedStringArray(["--catalogue-review=modern", "--frames=90,120"])]:
		assert_false(String(CAPTURE.catalogue_review_options(arguments)["error"]).is_empty())
	assert_eq(CAPTURE.catalogue_review_options(PackedStringArray(["--loan-review", "--speed=0", "--frames=12,90"]))["profile"], &"")
	assert_false(String(CAPTURE.loan_review_options(PackedStringArray(["--loan-review", "--speed=0", "--frames=12,90", "--catalogue-review=rustic"]))["error"]).is_empty())
	assert_false(String(CAPTURE.hud_layout_options(PackedStringArray(["--hud-layout", "--speed=0", "--frames=12,90", "--catalogue-review=modern"]))["error"]).is_empty())


func test_catalogue_uid_query_uses_its_scope_and_preserves_the_loan_default() -> void:
	var sources: Array[String] = CAPTURE.CATALOGUE_UID_SOURCES
	var before: Dictionary = {}
	for path: String in sources:
		before[path] = {"uid_exists": FileAccess.file_exists(path + ".uid"),
			"text": FileAccess.get_file_as_string(path + ".uid") if FileAccess.file_exists(path + ".uid") else "",
			"id": ResourceLoader.get_resource_uid(path) if FileAccess.file_exists(path) else ResourceUID.INVALID_ID}
	var evidence: Dictionary = CAPTURE.generated_uid_evidence(sources)
	assert_true(evidence["read_only"])
	assert_eq(evidence["entries"].size(), 9)
	for index: int in range(sources.size()):
		var path: String = sources[index]
		var row: Dictionary = evidence["entries"][index]
		assert_eq(row["source"], path)
		assert_eq(row["sidecar_text"], before[path]["text"])
		assert_eq(row["registered_id"], str(before[path]["id"]))
		assert_eq(FileAccess.file_exists(path + ".uid"), before[path]["uid_exists"])
		assert_eq(FileAccess.get_file_as_string(path + ".uid") if FileAccess.file_exists(path + ".uid") else "", before[path]["text"])
	assert_eq(CAPTURE.generated_uid_evidence()["entries"].size(), 5, "loan provenance retains its existing default")


func test_staff_priority_uid_query_reads_exactly_its_six_sources_without_changing_other_scopes() -> void:
	var expected: Array[String] = ["res://src/sim/staff/staff_job_priorities.gd",
		"res://tests/sim/test_staff_job_priorities.gd", "res://tests/fixtures/frozen_main_staff_picker.gd",
		"res://tests/world/test_staff_priorities_golden.gd", "res://tests/sim/test_staff_priority_persistence.gd",
		"res://tests/world/test_staff_priority_session.gd"]
	assert_eq(CAPTURE.STAFF_PRIORITY_UID_SOURCES, expected)
	var before: Dictionary = {}
	for path: String in expected:
		before[path] = {"exists": FileAccess.file_exists(path + ".uid"),
			"text": FileAccess.get_file_as_string(path + ".uid") if FileAccess.file_exists(path + ".uid") else "",
			"id": ResourceLoader.get_resource_uid(path) if FileAccess.file_exists(path) else ResourceUID.INVALID_ID}
	var evidence: Dictionary = CAPTURE.generated_uid_evidence(CAPTURE.STAFF_PRIORITY_UID_SOURCES)
	assert_true(evidence["read_only"])
	assert_eq(evidence["entries"].size(), 6)
	for index: int in range(expected.size()):
		var path: String = expected[index]
		var row: Dictionary = evidence["entries"][index]
		assert_eq(row["source"], path)
		assert_eq(row["sidecar_text"], before[path]["text"])
		assert_eq(row["registered_id"], str(before[path]["id"]))
		assert_eq(FileAccess.file_exists(path + ".uid"), before[path]["exists"])
		assert_eq(FileAccess.get_file_as_string(path + ".uid") if FileAccess.file_exists(path + ".uid") else "", before[path]["text"])
	assert_eq(CAPTURE.generated_uid_evidence()["entries"].size(), 5)
	assert_eq(CAPTURE.generated_uid_evidence(CAPTURE.CATALOGUE_UID_SOURCES)["entries"].size(), 9)


func test_staff_capture_source_retains_paused_morning_guards_and_conditional_read_only_queries() -> void:
	var source: String = FileAccess.get_file_as_string("res://tools/screenshot.gd")
	assert_true(source.contains('if _staff and (_open or _fast != 0 or not _selection.is_empty() or _assign_owner or _f3 or _menu or _speed != 0):'))
	assert_true(source.contains('if _staff and (staff_state.get("visible") != true or world == null or world.clock.phase != SimClock.Phase.MORNING'))
	assert_true(source.contains('or world.now != 0 or not _staff_capture_valid(staff_state))'))
	assert_true(source.contains('if _staff:\n\t\tstate["priority_grid"] = staff_priority_grid_evidence(panel, roster)'))
	assert_true(source.contains('if _staff:\n\t\tmetadata["staff_priority_review"] = {"generated_uids": generated_uid_evidence(STAFF_PRIORITY_UID_SOURCES)}'))
	var query: String = source.get_slice("static func staff_priority_grid_evidence", 1).get_slice("static func _staff_pixel_rect", 0)
	assert_true(query.contains("panel.priority_button_for(member.id, job)"))
	assert_true(query.contains("_staff_scroll_viewport(scroll)"))
	for forbidden: String in ["set_job_priority", "set_priority", ".refresh(", "run_ticks", "start_service", "FileAccess.open", "ResourceUID.add_id"]:
		assert_false(query.contains(forbidden), "the native evidence query cannot run commands: " + forbidden)


func test_staff_grid_validator_accepts_complete_records_and_rejects_wrong_words_locks_ids_and_colors() -> void:
	var record: Dictionary = _staff_grid_record()
	assert_true(CAPTURE.staff_priority_grid_valid(record["grid"], record["members"]))
	var wrong: Dictionary = record.duplicate(true)
	wrong["grid"]["cells"][0]["text"] = "Off"
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]), "a main job cannot display Off")
	wrong = record.duplicate(true)
	wrong["grid"]["cells"][1]["disabled"] = false
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]), "unsupported work must be locked")
	wrong = record.duplicate(true)
	wrong["grid"]["cells"][1]["job"] = "cooking"
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]), "duplicate or mismatched job identities fail")
	wrong = record.duplicate(true)
	wrong["grid"]["cells"][0]["tooltip"] = "Cooking"
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]), "main-job and next-pick explanations are required")
	wrong = record.duplicate(true)
	wrong["grid"]["cells"][0]["foreground"] = [0.0, 0.0, 0.0, 0.0]
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]), "the actual words must use the shared theme")
	wrong = record.duplicate(true)
	wrong["grid"]["headers"][3]["text"] = "bus_table"
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]), "headings use human job labels")


func test_staff_grid_validator_rejects_scrollbar_obscuring_cells_and_native_size_clipping() -> void:
	var record: Dictionary = _staff_grid_record()
	var wrong: Dictionary = record.duplicate(true)
	# The button still fits inside the card, but extends into space outside the
	# captured scroll content viewport (for example a visible native scrollbar).
	wrong["grid"]["cells"][4]["bounds"] = [1080.0, 258.0, 100.0, 32.0]
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]))
	wrong = record.duplicate(true)
	wrong["grid"]["scroll_viewport_bounds"][2] = 768.0
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]), "the viewport itself must exclude a visible scrollbar")
	wrong = record.duplicate(true)
	wrong["grid"]["cells"][0]["bounds"][2] = 90.0
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]), "native minimum width cannot be clipped")
	wrong = record.duplicate(true)
	wrong["grid"]["grid_minimum_bounds"][2] = 753.0
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]), "the grid cannot require horizontal overflow")
	wrong = record.duplicate(true)
	wrong["grid"]["close_bounds"] = [412.0, 880.0, 752.0, 36.0]
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]), "Close stays inside the native card")
	wrong = record.duplicate(true)
	wrong["grid"]["cells"][0]["bounds"] = [NAN, 258.0, 100.0, 32.0]
	assert_false(CAPTURE.staff_priority_grid_valid(wrong["grid"], wrong["members"]))


func test_real_staff_panel_native_grid_evidence_satisfies_capture_validator_without_mutation() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(1600, 900)
	host.gui_embed_subwindows = true
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(host)
	var window: Window = Window.new()
	window.borderless = true
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = Vector2i(1600, 900)
	window.content_scale_factor = 1.0
	window.size = Vector2i(1600, 900)
	host.add_child(window)
	var roster: StaffRoster = StaffRoster.new()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 72
	roster.draw_candidates(1, random)
	var panel: StaffPanel = (load("res://src/ui/staff_panel.tscn") as PackedScene).instantiate() as StaffPanel
	window.add_child(panel)
	panel.bind_roster(roster)
	panel.set_phase(SimClock.Phase.MORNING)
	panel.set_trays(0, PackedInt32Array([60, 150]), 200)
	panel.show()
	for frame: int in range(3):
		await tree.process_frame
	var before: Dictionary = roster.to_dict()
	var evidence: Dictionary = CAPTURE.staff_priority_grid_evidence(panel, roster)
	assert_true(CAPTURE.staff_priority_grid_valid(evidence, before["members"]),
		"Real Staff grid failed strict capture validation: " + JSON.stringify({"grid": evidence, "members": before["members"]}))
	assert_eq(roster.to_dict(), before, "native evidence never changes staff choices, growth or candidates")
	host.free()


## Pure captured-record unit data, never a scene or a screenshot fixture.
func _staff_grid_record() -> Dictionary:
	var members: Array = StaffRoster.new().to_dict()["members"]
	var grid: Dictionary = {"available": true, "columns": 6, "child_count": 18,
		"window_bounds": [0.0, 0.0, 1600.0, 900.0], "panel_bounds": [400.0, 112.0, 800.0, 776.0],
		"close_bounds": [412.0, 840.0, 752.0, 36.0], "close_visible": true,
		"scroll_bounds": [412.0, 220.0, 768.0, 350.0], "scroll_viewport_bounds": [412.0, 220.0, 752.0, 350.0],
		"scrollbars": [{"visible": true, "bounds": [1164.0, 220.0, 16.0, 350.0]}, {"visible": false, "bounds": []}],
		"grid_bounds": [412.0, 220.0, 650.0, 108.0], "grid_minimum_bounds": [412.0, 220.0, 650.0, 108.0],
		"horizontal_scroll_mode": ScrollContainer.SCROLL_MODE_DISABLED, "headers": [], "names": [], "cells": []}
	var labels: Array[String] = ["Team member", "Cooking", "Serving", "Bussing", "Washing", "Cleaning"]
	for column: int in range(labels.size()):
		grid["headers"].append({"text": labels[column], "visible": true,
			"bounds": [412.0 if column == 0 else 432.0 + column * 106.0, 220.0, 120.0 if column == 0 else 100.0, 32.0]})
	for row: int in range(members.size()):
		var member: Dictionary = members[row]
		var y: float = 258.0 + row * 38.0
		grid["names"].append({"id": member["id"], "text": member["name"], "visible": true,
			"bounds": [412.0, y, 120.0, 32.0]})
		for column: int in range(StaffJobPriorities.JOBS.size()):
			var job: StringName = StaffJobPriorities.JOBS[column]
			var value: int = int(member["priorities"][String(job)])
			var supported: bool = StaffJobPriorities.supports(StringName(member["role"]), job)
			var tooltip: String = "Applies on the next task pick; current work continues."
			if not supported:
				tooltip = "Off. This job is not available for this role."
			elif job == StaffJobPriorities.main_job(StringName(member["role"])):
				tooltip += " This role's main job cannot be Off."
			var normal: StyleBoxFlat = StaffPanel.SHARED_THEME.get_stylebox("normal", "Button") as StyleBoxFlat
			var muted: StyleBoxFlat = StaffPanel.SHARED_THEME.get_stylebox("disabled", "Button") as StyleBoxFlat
			var accent: StyleBoxFlat = StaffPanel.SHARED_THEME.get_stylebox("pressed", "Button") as StyleBoxFlat
			var foreground: Color = StaffPanel.SHARED_THEME.get_color("font_color", "Button")
			var background: Color = normal.bg_color
			var border: Color = accent.bg_color if value == StaffJobPriorities.Level.HIGH else normal.border_color
			if value == StaffJobPriorities.Level.LOW:
				background = muted.bg_color
				border = muted.border_color
			elif value == StaffJobPriorities.Level.OFF:
				background = foreground
				border = foreground
				foreground = StaffPanel.SHARED_THEME.get_color("font_pressed_color", "Button")
			var bounds: Array[float] = [538.0 + column * 106.0, y, 100.0, 32.0]
			grid["cells"].append({"id": member["id"], "job": String(job), "text": StaffJobPriorities.level_label(value),
				"disabled": not supported, "tooltip": tooltip, "visible": true, "clip_text": false,
				"parent_is_grid": true, "grid_index": (row + 1) * 6 + column + 1, "bounds": bounds,
				"minimum_bounds": [bounds[0], y, 100.0, 30.0],
				"foreground": [foreground.r, foreground.g, foreground.b, foreground.a],
				"background": [background.r, background.g, background.b, background.a],
				"border": [border.r, border.g, border.b, border.a]})
	return {"members": members, "grid": grid}


func test_legacy_capture_options_keep_their_default_window() -> void:
	for argument: String in ["--settings", "--settings-world", "--staff", "--build=green", "--paint"]:
		var options: Dictionary = CAPTURE.hud_layout_options(PackedStringArray([argument, "--speed=0", "--frames=90"]))
		assert_eq(options["error"], "")
		assert_false(options["enabled"])
		assert_eq(options["window_size"], Vector2i(1600, 900))


func test_hud_layout_accepts_both_supported_sizes_and_its_default() -> void:
	var defaults: PackedStringArray = PackedStringArray(["--hud-layout", "--speed=0", "--frames=12,90"])
	assert_eq(CAPTURE.hud_layout_options(defaults)["window_size"], Vector2i(1600, 900))
	for size: String in ["1280x720", "1600x900"]:
		var arguments: PackedStringArray = defaults.duplicate()
		arguments.append("--window-size=" + size)
		var options: Dictionary = CAPTURE.hud_layout_options(arguments)
		assert_eq(options["error"], "")
		assert_true(options["enabled"])
		assert_eq(options["window_size"], Vector2i(1280, 720) if size == "1280x720" else Vector2i(1600, 900))


func test_window_size_is_strict_and_belongs_only_to_hud_layout() -> void:
	for argument: String in ["--window-size", "--window-size=1920x1080", "--window-size=1280,720", "--hud-layout=yes", "--hud-layout"]:
		var arguments: PackedStringArray = PackedStringArray(["--hud-layout", "--speed=0", "--frames=12,90", argument])
		assert_false(String(CAPTURE.hud_layout_options(arguments)["error"]).is_empty(), argument)
	assert_false(String(CAPTURE.hud_layout_options(PackedStringArray(["--window-size=1280x720"]))["error"]).is_empty())
	var duplicate: PackedStringArray = PackedStringArray(["--hud-layout", "--speed=0", "--frames=12,90", "--window-size=1280x720", "--window-size=1600x900"])
	assert_false(String(CAPTURE.hud_layout_options(duplicate)["error"]).is_empty())


func test_hud_layout_requires_one_paused_two_frame_sequence() -> void:
	for extras: PackedStringArray in [PackedStringArray(), PackedStringArray(["--speed=0"]),
			PackedStringArray(["--speed=1", "--frames=12,90"]),
			PackedStringArray(["--speed=0", "--frames=12"]),
			PackedStringArray(["--speed=0", "--frames=90,12"]),
			PackedStringArray(["--speed=0", "--frames=12,90", "--speed=0"]),
			PackedStringArray(["--speed=0", "--frames=12,90", "--frames=12,90"])]:
		var arguments: PackedStringArray = PackedStringArray(["--hud-layout"])
		arguments.append_array(extras)
		assert_false(String(CAPTURE.hud_layout_options(arguments)["error"]).is_empty())


func test_hud_layout_uses_only_actual_main_without_other_capture_modes() -> void:
	for argument: String in ["--scene=res://other.tscn", "--open", "--fast=1", "--select=owner", "--assign-owner=kitchen", "--f3", "--menu", "--staff", "--settings", "--settings-world", "--report", "--build=red", "--paint", "--quarter=0"]:
		var arguments: PackedStringArray = PackedStringArray(["--hud-layout", "--speed=0", "--frames=12,90", argument])
		assert_false(String(CAPTURE.hud_layout_options(arguments)["error"]).is_empty(), argument)
	var main: PackedStringArray = PackedStringArray(["--hud-layout", "--speed=0", "--frames=12,90", "--scene=res://src/world/main.tscn", "--out=screens/hud"])
	assert_eq(CAPTURE.hud_layout_options(main)["error"], "")
