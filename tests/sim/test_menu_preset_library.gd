extends "res://tests/test_case.gd"

const LIBRARY: GDScript = preload("res://src/sim/restaurant/menu_preset_library.gd")


func test_save_captures_enabled_dishes_and_all_cookable_prices() -> void:
	var menu: MenuSettings = _menu()
	assert_true(menu.set_enabled(&"fries", false))
	assert_true(menu.set_price(&"burger", 18))
	assert_true(menu.set_price(&"fries", 10))
	var library: MenuPresetLibrary = LIBRARY.new()
	assert_true(library.save_menu("  Lunch  ", menu))
	assert_eq(library.names(), ["Lunch"])
	var preset: Dictionary = library.get_preset(0)
	assert_eq(preset["name"], "Lunch")
	assert_eq(preset["enabled"], [&"burger"])
	assert_eq(preset["prices"], {&"burger": 18, &"fries": 10})
	assert_false(preset["prices"].has(&"locked"), "level-locked dishes are not captured")


func test_get_preset_and_save_snapshot_are_protected_copies() -> void:
	var library: MenuPresetLibrary = LIBRARY.new()
	assert_true(library.save_menu("Lunch", _menu()))
	var preset: Dictionary = library.get_preset(0)
	(preset["enabled"] as Array).clear()
	(preset["prices"] as Dictionary)[&"burger"] = 1
	var saved: Dictionary = library.to_save()
	(saved["presets"] as Array)[0]["name"] = "Changed"
	assert_eq(library.get_preset(0)["name"], "Lunch")
	assert_eq(library.get_preset(0)["enabled"], [&"burger", &"fries"])
	assert_eq(library.get_preset(0)["prices"][&"burger"], 12)


func test_rename_remove_and_eight_preset_limit() -> void:
	var library: MenuPresetLibrary = LIBRARY.new()
	var menu: MenuSettings = _menu()
	for index: int in range(8):
		assert_true(library.save_menu("Preset %d" % index, menu))
	assert_false(library.save_menu("Ninth", menu))
	assert_true(library.rename(1, "  Dinner  "))
	assert_eq(library.names()[1], "Dinner")
	assert_false(library.rename(-1, "Invalid"))
	assert_false(library.rename(0, "  "))
	assert_true(library.remove(1))
	assert_eq(library.names().size(), 7)
	assert_eq(library.names()[1], "Preset 2")
	assert_false(library.remove(7))
	assert_eq(library.get_preset(-1), {})
	assert_eq(library.get_preset(7), {})


func test_names_are_unique_ignoring_case_and_validate_trimmed_length() -> void:
	var library: MenuPresetLibrary = LIBRARY.new()
	var menu: MenuSettings = _menu()
	assert_true(library.save_menu("Same", menu))
	assert_false(library.save_menu(" same ", menu), "preset names are unique ignoring case")
	assert_true(library.save_menu("Other", menu))
	assert_true(library.rename(0, " same "), "a preset can keep its own name")
	assert_eq(library.names()[0], "same")
	assert_false(library.rename(1, "SAME"), "a rename cannot collide with another preset")
	assert_false(library.save_menu("", menu))
	assert_false(library.save_menu("x".repeat(25), menu))
	assert_false(library.save_menu("Valid", MenuSettings.new()))
	assert_false(library.rename(0, "x".repeat(25)))


func test_round_trip_preserves_full_width_integer_prices_and_unknown_ids() -> void:
	var costly: RecipeDef = _recipe(&"costly", MenuSettings.MAX_PRICE)
	var menu: MenuSettings = MenuSettings.new([costly], 1)
	var library: MenuPresetLibrary = LIBRARY.new()
	assert_true(menu.set_price(&"costly", MenuSettings.MAX_PRICE))
	assert_true(library.save_menu("Big price", menu))
	var saved: Dictionary = library.to_save()
	var row: Dictionary = (saved["presets"] as Array)[0]
	assert_eq(row["prices"], {"costly": "9223372036854775807"})
	var restored: MenuPresetLibrary = LIBRARY.new()
	assert_true(restored.restore(saved))
	assert_eq(restored.get_preset(0)["prices"][&"costly"], MenuSettings.MAX_PRICE)
	var future_content: Dictionary = {"version": 1, "presets": [{
		"name": "Future menu", "enabled": ["new_dish"], "prices": {"new_dish": "123"}}]}
	assert_true(restored.restore(future_content))
	assert_eq(restored.get_preset(0)["enabled"], [&"new_dish"])
	assert_eq(restored.get_preset(0)["prices"], {&"new_dish": 123})
	var formerly_locked: Dictionary = {"version": 1, "presets": [{
		"name": "Older dish", "enabled": ["locked_dish"], "prices": {"locked_dish": "45"}}]}
	assert_true(restored.restore(formerly_locked))
	assert_eq(restored.get_preset(0)["enabled"], [&"locked_dish"])
	assert_eq(restored.get_preset(0)["prices"][&"locked_dish"], 45)


func test_invalid_restore_is_atomic() -> void:
	var library: MenuPresetLibrary = LIBRARY.new()
	assert_true(library.save_menu("Keep", _menu()))
	var before: Dictionary = library.to_save()
	var invalid_rows: Array[Dictionary] = [
		{"version": 2, "presets": []},
		{"version": 1, "presets": [{"name": "", "enabled": [&"burger"], "prices": {"burger": "12"}}]},
		{"version": 1, "presets": [{"name": "No enabled dish", "enabled": [], "prices": {"burger": "12"}}]},
		{"version": 1, "presets": [{"name": "Missing price", "enabled": ["burger"], "prices": {}}]},
		{"version": 1, "presets": [{"name": "Bad number", "enabled": ["burger"], "prices": {"burger": "01"}}]},
		{"version": 1, "presets": [{"name": "Wrong number type", "enabled": ["burger"], "prices": {"burger": 12}}]},
		{"version": 1, "presets": ["not a preset"]},
		{"version": 1, "presets": [
			{"name": "Would replace current", "enabled": ["burger"], "prices": {"burger": "12"}},
			{"name": "Bad later row", "enabled": ["fries"], "prices": {"fries": "-1"}}]},
		{"version": 1, "presets": [
			{"name": "Duplicate", "enabled": ["burger"], "prices": {"burger": "12"}},
			{"name": " duplicate ", "enabled": ["fries"], "prices": {"fries": "8"}}]},
	]
	for invalid: Dictionary in invalid_rows:
		assert_false(library.restore(invalid), "malformed presets are rejected")
		assert_eq(library.to_save(), before, "a failed restore changes nothing")
	var too_many: Array[Dictionary] = []
	for index: int in range(9):
		too_many.append({"name": "P%d" % index, "enabled": ["burger"], "prices": {"burger": "12"}})
	assert_false(library.restore({"version": 1, "presets": too_many}))
	assert_eq(library.to_save(), before)


func _menu() -> MenuSettings:
	var burger: RecipeDef = _recipe(&"burger", 12)
	var fries: RecipeDef = _recipe(&"fries", 8)
	var locked: RecipeDef = _recipe(&"locked", 14)
	locked.unlock_level = 2
	return MenuSettings.new([burger, fries, locked], 1)


func _recipe(id: StringName, price: int) -> RecipeDef:
	var recipe: RecipeDef = RecipeDef.new()
	recipe.id = id
	recipe.display_name = String(id)
	recipe.standard_price = price
	recipe.unlock_level = 1
	return recipe
