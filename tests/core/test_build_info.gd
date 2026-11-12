extends TestCase
## Version parsing, the bundled notes, the dev fallback and the last-seen
## record for the What's new panel. Private user:// fixtures only.

const CHANGELOG: String = "# Changelog\n\nIntro.\n\n## Unreleased\n\n### Players\n- New thing. (#9)\n\n## v0.2.0 (2026-11-01)\n\n### Players\n- Old thing. (#5)\n"
const NOTES: String = "### Players\n- A **bold** change with `code`. (#5)\n  continued here\n\n### What to test\n- Seat a party of four.\n- Paint a chair.\n\n### Under the hood\n- Tooling. (#6)\n"

var _paths: Array[String] = []


func after_each() -> void:
	for path: String in _paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_paths.clear()


func test_parse_version_reads_release_tags_only() -> void:
	assert_eq(BuildInfo.parse_version("v0.2.0"), [0, 2, 0] as Array[int])
	assert_eq(BuildInfo.parse_version("1.12.30"), [1, 12, 30] as Array[int])
	assert_eq(BuildInfo.parse_version(" v10.0.1\n"), [10, 0, 1] as Array[int])
	for bad: String in ["", "dev", "dev-1a2b3c4", "v1.2", "v1.2.3.4", "v1.2.x", "v-1.2.3", "vv1.2.3", "v1.2.3-rc1"]:
		assert_true(BuildInfo.parse_version(bad).is_empty(), bad)
	assert_true(BuildInfo.is_release("v0.1.0"))
	assert_false(BuildInfo.is_release("dev-abc1234"))


func test_versions_compare_numerically() -> void:
	assert_true(BuildInfo.is_newer("v0.10.0", "v0.9.5"))
	assert_true(BuildInfo.is_newer("v1.0.0", "v0.99.99"))
	assert_false(BuildInfo.is_newer("v0.2.0", "v0.2.0"))
	assert_false(BuildInfo.is_newer("dev", "v0.2.0"))


func test_a_run_with_no_stamp_is_dev() -> void:
	assert_eq(BuildInfo.version("res://build_info/not_there.txt"), "dev")
	assert_eq(BuildInfo.label(BuildInfo.version("res://build_info/not_there.txt")), "dev")
	assert_eq(BuildInfo.label(""), "dev")
	var empty: String = _write("empty-version", "  \n")
	assert_eq(BuildInfo.version(empty), "dev")


func test_a_stamped_version_is_read_back_trimmed() -> void:
	assert_eq(BuildInfo.version(_write("tag-version", "v0.3.1\n")), "v0.3.1")
	assert_eq(BuildInfo.version(_write("sha-version", "dev-1a2b3c4\n")), "dev-1a2b3c4")


func test_the_bundled_notes_resource_loads() -> void:
	var path: String = _write("bundled-notes", NOTES)
	var loaded: String = BuildInfo.notes(path, "res://missing.md")
	assert_eq(loaded, NOTES.strip_edges())
	assert_false(ReleaseNotes.parse(loaded).is_empty())


func test_dev_notes_fall_back_to_the_unreleased_changelog_section() -> void:
	var changelog: String = _write("changelog", CHANGELOG)
	assert_eq(BuildInfo.notes("res://build_info/not_there.txt", changelog), "### Players\n- New thing. (#9)")
	assert_eq(BuildInfo.unreleased_section(CHANGELOG), "### Players\n- New thing. (#9)")
	assert_eq(BuildInfo.unreleased_section("# Changelog\n\n## v1.0.0\n- x\n"), "")
	assert_eq(BuildInfo.notes("res://build_info/not_there.txt", "res://missing.md"), "")


func test_what_to_test_comes_first_and_markdown_marks_are_dropped() -> void:
	var groups: Array[Dictionary] = ReleaseNotes.parse(NOTES)
	var titles: Array[String] = []
	for group: Dictionary in groups:
		titles.append(String(group["title"]))
	assert_eq(titles, ["What to test", "Players", "Under the hood"] as Array[String])
	assert_eq(groups[0]["items"], ["Seat a party of four.", "Paint a chair."] as Array[String])
	assert_eq(groups[1]["items"], ["A bold change with code. (#5) continued here"] as Array[String])
	# Case, a colon and position in the file do not matter.
	var shuffled: Array[Dictionary] = ReleaseNotes.parse("### Players\n- a\n\n### what to test:\n- b\n")
	assert_eq(shuffled[0]["title"], "what to test:")


func test_empty_groups_are_dropped_and_loose_text_is_kept() -> void:
	assert_true(ReleaseNotes.parse("").is_empty())
	var groups: Array[Dictionary] = ReleaseNotes.parse("### Empty\n\n### Players\n- one\n")
	assert_eq(groups.size(), 1)
	var loose: Array[Dictionary] = ReleaseNotes.parse("Just a line.\n")
	assert_eq(loose[0]["items"], ["Just a line."] as Array[String])


func test_the_panel_opens_once_per_release_version() -> void:
	assert_true(BuildInfo.should_show_whats_new("v0.2.0", "", NOTES))
	assert_true(BuildInfo.should_show_whats_new("v0.2.0", "v0.1.0", NOTES))
	assert_false(BuildInfo.should_show_whats_new("v0.2.0", "v0.2.0", NOTES))
	assert_false(BuildInfo.should_show_whats_new("dev", "", NOTES))
	assert_false(BuildInfo.should_show_whats_new("dev-1a2b3c4", "", NOTES))
	assert_false(BuildInfo.should_show_whats_new("v0.2.0", "", "  \n"))


func test_last_seen_version_lives_in_user_settings_and_round_trips() -> void:
	var path: String = "user://test-last-seen-%d-%d.cfg" % [OS.get_process_id(), get_instance_id()]
	_paths.append(path)
	var model: SettingsPreferences = SettingsPreferences.new(path)
	assert_eq(model.last_seen_version, "")
	assert_true(model.set_last_seen_version("v0.2.0"))
	var restored: SettingsPreferences = SettingsPreferences.new(path)
	assert_true(restored.load_from_disk())
	assert_eq(restored.last_seen_version, "v0.2.0")
	assert_true(restored.set_last_seen_version("v0.3.0"))
	assert_false(restored.set_last_seen_version("bad\"quote"))
	assert_eq(restored.last_seen_version, "v0.3.0")
	# An older file without the key still loads, with nothing seen yet.
	assert_true(model.set_last_seen_version(""))
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var lines: PackedStringArray = []
	for line: String in file.get_as_text().split("\n"):
		if not line.begins_with("last_seen_version"):
			lines.append(line)
	file.close()
	var legacy: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	legacy.store_string("\n".join(lines))
	legacy.close()
	var old: SettingsPreferences = SettingsPreferences.new(path)
	assert_true(old.load_from_disk())
	assert_eq(old.last_seen_version, "")
	model.free()
	restored.free()
	old.free()


func _write(name: String, text: String) -> String:
	var path: String = "user://test-build-info-%d-%d-%s.txt" % [OS.get_process_id(), get_instance_id(), name]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	_paths.append(path)
	return path
