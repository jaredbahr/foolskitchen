extends TestCase
## Save-contract and input validation for presentation-only owner choices.


func test_legacy_default_look_and_all_twelve_approved_models_are_available() -> void:
	var choice: OwnerAppearance = OwnerAppearance.new()
	assert_eq(choice.model, &"character-male-a")
	assert_eq(choice.display_name, "You")
	assert_eq(choice.to_dict(), {"model": "character-male-a", "name": "You"})
	assert_eq(OwnerAppearance.MODELS, [
		&"character-female-a", &"character-female-b", &"character-female-c",
		&"character-female-d", &"character-female-e", &"character-female-f",
		&"character-male-a", &"character-male-b", &"character-male-c",
		&"character-male-d", &"character-male-e", &"character-male-f",
	] as Array[StringName])
	for model: StringName in OwnerAppearance.MODELS:
		assert_true(OwnerAppearance.valid_model(model))
		assert_true(choice.set_choice(model, "You"))
		assert_eq(choice.model, model)
	for model: StringName in [&"", &"character-male-g", &"character-female-g",
			&"CHARACTER-MALE-A", &"res://assets/kenney/characters/character-male-a.glb"]:
		assert_false(OwnerAppearance.valid_model(model))


func test_chosen_model_and_name_round_trip_through_plain_json() -> void:
	var chosen: OwnerAppearance = OwnerAppearance.new()
	assert_true(chosen.set_choice(&"character-female-e", "Léa"))
	var encoded: String = JSON.stringify(chosen.to_dict())
	var data: Variant = JSON.parse_string(encoded)
	assert_true(data is Dictionary)
	var restored: OwnerAppearance = OwnerAppearance.new()
	assert_true(restored.from_dict(data as Dictionary))
	assert_eq(restored.model, &"character-female-e")
	assert_eq(restored.display_name, "Léa")
	var detached: Dictionary = chosen.to_dict()
	detached["model"] = "character-male-c"
	detached["name"] = "Another owner"
	assert_eq(chosen.model, &"character-female-e")
	assert_eq(chosen.display_name, "Léa")


func test_empty_legacy_appearance_restores_the_original_default_look() -> void:
	var choice: OwnerAppearance = OwnerAppearance.new()
	assert_true(choice.set_choice(&"character-female-b", "Harper"))
	assert_true(choice.from_dict({}))
	assert_eq(choice.model, &"character-male-a")
	assert_eq(choice.display_name, "You")


func test_optional_names_trim_edges_and_preserve_valid_unicode_at_the_limit() -> void:
	var choice: OwnerAppearance = OwnerAppearance.new()
	assert_true(choice.set_choice(&"character-male-f", "  Sam  "))
	assert_eq(choice.display_name, "Sam")
	assert_true(choice.set_choice(&"character-male-f", ""))
	assert_eq(choice.display_name, "You")
	assert_true(choice.set_choice(&"character-male-f", "    "))
	assert_eq(choice.display_name, "You")
	assert_true(choice.set_choice(&"character-male-f", "é".repeat(OwnerAppearance.MAX_NAME_LENGTH)))
	assert_eq(choice.display_name.length(), OwnerAppearance.MAX_NAME_LENGTH)
	assert_true(choice.set_choice(&"character-male-f", "  " + "a".repeat(OwnerAppearance.MAX_NAME_LENGTH) + "  "))
	assert_eq(choice.display_name.length(), OwnerAppearance.MAX_NAME_LENGTH)


func test_invalid_choice_rejects_controls_and_overlong_names_without_mutating() -> void:
	var choice: OwnerAppearance = OwnerAppearance.new()
	assert_true(choice.set_choice(&"character-female-d", "Robin"))
	var expected: Dictionary = choice.to_dict()
	assert_false(choice.set_choice(&"missing-model", "Valid name"))
	assert_eq(choice.to_dict(), expected)
	for name: String in ["Too\nMany", "Too\rMany", "Tab\tName", "a".repeat(OwnerAppearance.MAX_NAME_LENGTH + 1),
			"A" + String.chr(1) + "B", "A" + String.chr(127) + "B", "A" + String.chr(159) + "B",
			"A" + String.chr(8232) + "B", "A" + String.chr(8233) + "B"]:
		assert_false(choice.set_choice(&"character-male-b", name), "a malformed name cannot become player-facing text")
		assert_eq(choice.to_dict(), expected, "validation must not partly replace the chosen model")


func test_malformed_save_shapes_are_rejected_without_losing_the_previous_choice() -> void:
	var choice: OwnerAppearance = OwnerAppearance.new()
	assert_true(choice.set_choice(&"character-female-a", "Morgan"))
	var expected: Dictionary = choice.to_dict()
	for data: Dictionary in [
		{"model": "character-male-c"}, {"name": "Riley"},
		{"model": "character-male-c", "name": "Riley", "other": true},
		{"model": "missing-model", "name": "Riley"},
		{"model": 1, "name": "Riley"}, {"model": null, "name": "Riley"},
		{"model": &"character-male-c", "name": "Riley"},
		{"model": "character-male-c", "name": 1}, {"model": "character-male-c", "name": null},
		{"model": "character-male-c", "name": "Riley\nRobin"},
		{"model": "character-male-c", "name": "a".repeat(OwnerAppearance.MAX_NAME_LENGTH + 1)},
		{&"model": "character-male-c", "name": "Riley"},
	]:
		assert_false(choice.from_dict(data))
		assert_eq(choice.to_dict(), expected, "a bad save cannot partly replace the current appearance")
