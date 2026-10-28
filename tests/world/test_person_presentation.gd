extends TestCase
## Pure mappings only. Import, animation, model fit and pixels need engine checks.


func test_type_looks_use_deterministic_native_guest_pairs_and_preserve_regular() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for kind: StringName in [&"student", &"foodie", &"family"]:
		for id: int in [0, 1, -1, -9223372036854775807 - 1, 9223372036854775807]:
			var model: StringName = PersonPresentation.model_for(&"customer", id, kind)
			assert_eq(model, PersonPresentation.model_for(&"guest", id, kind))
			assert_true(PersonPresentation.GUEST_MODELS.has(model))
			assert_eq(PersonPresentation.model_path_for(&"customer", id, kind), PersonPresentation.MODEL_DIRECTORY + String(model) + ".glb")
		for id: int in [0, 1]:
			var model: StringName = PersonPresentation.model_for(&"customer", id, kind)
			assert_false(seen.has(model), "special types have distinct native model pairs")
			seen[model] = true
	for id: int in range(8):
		assert_eq(PersonPresentation.model_for(&"customer", id, &"regular"), PersonPresentation.GUEST_MODELS[id])
		assert_eq(PersonPresentation.model_for(&"customer", id, &"unknown"), PersonPresentation.GUEST_MODELS[id])
	assert_eq(PersonPresentation.model_for(&"cook", 5, &"foodie"), PersonPresentation.COOK_MODEL)
	assert_eq(seen.size(), 6)


func test_fixed_staff_and_owner_looks() -> void:
	assert_eq(PersonPresentation.model_for(&"cook"), &"character-male-b")
	assert_true(PersonPresentation.has_chef_hat(&"cook"))
	assert_eq(PersonPresentation.model_for(&"server"), &"character-male-d")
	assert_false(PersonPresentation.has_chef_hat(&"server"))
	assert_eq(PersonPresentation.model_for(&"owner"), &"character-male-a")
	assert_false(PersonPresentation.has_chef_hat(&"owner"))
	assert_eq(PersonPresentation.model_for(&"owner", 27), PersonPresentation.model_for(&"owner", 1))


func test_guest_ids_are_stable_and_use_only_remaining_models() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for id: int in range(PersonPresentation.GUEST_MODELS.size()):
		var model: StringName = PersonPresentation.model_for(&"customer", id)
		assert_eq(model, PersonPresentation.model_for(&"customer", id))
		assert_eq(model, PersonPresentation.model_for(&"guest", id))
		assert_false(seen.has(model))
		assert_ne(model, PersonPresentation.COOK_MODEL)
		assert_ne(model, &"character-female-b")
		assert_ne(model, PersonPresentation.SERVER_MODEL)
		assert_ne(model, PersonPresentation.OWNER_MODEL)
		assert_false(PersonPresentation.has_chef_hat(&"customer"))
		seen[model] = true
	assert_eq(seen.size(), 8)
	assert_eq(PersonPresentation.model_for(&"customer", -1), &"character-male-f")
	assert_eq(PersonPresentation.model_for(&"customer", -9223372036854775807 - 1), &"character-female-a")
	assert_eq(PersonPresentation.model_for(&"customer", 9223372036854775807), &"character-male-f")


func test_unknown_and_unapproved_cleaner_roles_have_no_substitute() -> void:
	assert_eq(PersonPresentation.model_for(&"cleaner"), &"")
	assert_eq(PersonPresentation.model_path_for(&"cleaner"), "")
	assert_eq(PersonPresentation.model_for(&"host"), &"")
	assert_false(PersonPresentation.has_chef_hat(&"cleaner"))


func test_models_are_restricted_to_vendored_mini_characters() -> void:
	assert_eq(PersonPresentation.model_path_for(&"cook"), "res://assets/kenney/characters/character-male-b.glb")
	for role: StringName in [&"cook", &"server", &"owner"]:
		assert_true(PersonPresentation.source_head_top(PersonPresentation.model_for(role)) > 0.0)
	for id: int in range(PersonPresentation.GUEST_MODELS.size()):
		assert_true(PersonPresentation.model_path_for(&"customer", id).begins_with("res://assets/kenney/characters/character-"))
		assert_true(PersonPresentation.model_path_for(&"customer", id).ends_with(".glb"))
		assert_true(PersonPresentation.source_head_top(PersonPresentation.model_for(&"customer", id)) > 0.0)


func test_agent_state_flags_choose_required_kit_clips() -> void:
	assert_eq(PersonPresentation.clip_for_state(false, false, false, false), &"idle")
	assert_eq(PersonPresentation.clip_for_state(true, false, false, false), &"walk")
	assert_eq(PersonPresentation.clip_for_state(false, true, false, false), &"sit")
	assert_eq(PersonPresentation.clip_for_state(false, false, true, false), &"holding-both")
	assert_eq(PersonPresentation.clip_for_state(false, false, false, true), &"interact-right")


func test_pose_priority_keeps_seats_and_carried_meals_readable() -> void:
	assert_eq(PersonPresentation.clip_for_state(true, true, true, true), &"sit")
	assert_eq(PersonPresentation.clip_for_state(true, false, true, true), &"holding-both")
	assert_eq(PersonPresentation.clip_for_state(true, false, false, true), &"walk")
	assert_eq(PersonPresentation.CLIPS.size(), 5)
	for clip: StringName in PersonPresentation.CLIPS:
		assert_false(String(clip).contains("wheelchair"))
		assert_false(String(clip).contains("attack"))
		assert_ne(clip, &"die")


func test_seated_lean_validation_uses_the_shared_finite_presentation_limit() -> void:
	for degrees: float in [0.0, 7.5, ItemDef.MAX_SEATED_LEAN_DEGREES] as Array[float]:
		assert_true(PersonPresentation.seated_lean_valid(degrees))
	for degrees: float in [-0.001, ItemDef.MAX_SEATED_LEAN_DEGREES + 0.001, NAN, INF, -INF] as Array[float]:
		assert_false(PersonPresentation.seated_lean_valid(degrees))
