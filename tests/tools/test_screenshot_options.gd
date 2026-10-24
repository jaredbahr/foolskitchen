extends TestCase
## Pure opt-in option parsing; no SceneTree, window, settings or capture is created.

const CAPTURE: Script = preload("res://tools/screenshot.gd")


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
