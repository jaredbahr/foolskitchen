extends TestCase
## Pure regression for concurrent worktrees sharing the same Godot user://.


func test_different_processes_have_distinct_primary_backup_and_temporary_paths() -> void:
	var first: String = SaveTestPaths.case_dir(101, "game_session")
	var second: String = SaveTestPaths.case_dir(202, "game_session")
	assert_ne(first, second)
	for suffix: String in [".json", ".json.bak", ".json.tmp"]:
		assert_ne(first.path_join("test_session" + suffix), second.path_join("test_session" + suffix))
	assert_eq(first, "user://test_saves_101/game_session/")
	assert_eq(second, "user://test_saves_202/game_session/")


func test_cases_are_distinct_and_stay_under_their_own_process_root() -> void:
	var seen: Dictionary[String, bool] = {}
	for case_name: String in ["save_system_1", "build_session", "game_session", "menu_session",
			"multi_day_invariants", "owner_session", "shop_edit_session", "shop_edit_soak"]:
		var path: String = SaveTestPaths.case_dir(101, case_name)
		assert_true(path.begins_with(SaveTestPaths.process_dir(101)))
		assert_false(path.begins_with(SaveTestPaths.process_dir(202)))
		assert_false(seen.has(path))
		seen[path] = true
		assert_eq(SaveTestPaths.case_dir(101, case_name), path, "path construction is deterministic")


func test_invalid_ids_and_case_components_cannot_escape_the_namespace() -> void:
	for process_id: int in [0, -1]:
		assert_eq(SaveTestPaths.process_dir(process_id), "")
		assert_eq(SaveTestPaths.case_dir(process_id, "game_session"), "")
	for case_name: String in ["", ".", "..", "../other", "a/b", "a\\b", "/absolute", "two words"]:
		assert_eq(SaveTestPaths.case_dir(101, case_name), "")
