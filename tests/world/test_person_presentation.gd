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
		assert_ne(model, OwnerAppearance.DEFAULT_MODEL)
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
	for role: StringName in [&"cook", &"server", &"owner", &"courier"]:
		assert_true(PersonPresentation.source_head_top(PersonPresentation.model_for(role)) > 0.0)
	assert_eq(PersonPresentation.model_for(&"courier"), &"character-female-b", "the one kit model no role uses")
	assert_false(PersonPresentation.GUEST_MODELS.has(PersonPresentation.COURIER_MODEL))
	for id: int in range(PersonPresentation.GUEST_MODELS.size()):
		assert_true(PersonPresentation.model_path_for(&"customer", id).begins_with("res://assets/kenney/characters/character-"))
		assert_true(PersonPresentation.model_path_for(&"customer", id).ends_with(".glb"))
		assert_true(PersonPresentation.source_head_top(PersonPresentation.model_for(&"customer", id)) > 0.0)


func test_only_the_courier_wears_the_delivery_uniform() -> void:
	assert_true(PersonPresentation.has_courier_cap(&"courier"))
	assert_false(PersonPresentation.has_chef_hat(&"courier"))
	var recolors: Array[Dictionary] = PersonPresentation.uniform_recolors(&"courier")
	assert_eq(recolors.size(), 2)
	for recolor: Dictionary in recolors:
		var rect: Rect2i = recolor["rect"]
		assert_true(Rect2i(0, 0, 512, 512).encloses(rect), "blocks stay inside the kit colormap")
	for role: StringName in [&"cook", &"server", &"owner", &"customer", &"guest", &"cleaner"]:
		assert_false(PersonPresentation.has_courier_cap(role))
		assert_eq(PersonPresentation.uniform_recolors(role).size(), 0)
	assert_ne(PersonPresentation.COURIER_BROWN, PersonPresentation.COURIER_AMBER)


func test_agent_state_flags_choose_required_kit_clips() -> void:
	assert_eq(PersonPresentation.clip_for_state(false, false, false, false), &"idle")
	assert_eq(PersonPresentation.clip_for_state(true, false, false, false), &"walk")
	assert_eq(PersonPresentation.clip_for_state(false, true, false, false), &"sit")
	assert_eq(PersonPresentation.clip_for_state(false, false, true, false), &"holding-both")
	assert_eq(PersonPresentation.clip_for_state(false, false, false, true), &"interact-right")


func test_pose_priority_keeps_seats_and_carried_meals_readable() -> void:
	assert_eq(PersonPresentation.clip_for_state(true, true, true, true), &"sit")
	assert_eq(PersonPresentation.clip_for_state(true, false, true, true), PersonPresentation.CARRY_WALK,
		"carrying while walking keeps the legs walking (FK-099)")
	assert_eq(PersonPresentation.clip_for_state(false, false, true, true), &"holding-both")
	assert_eq(PersonPresentation.clip_for_state(true, false, false, true), &"walk")
	assert_eq(PersonPresentation.clip_for_state(false, false, false, true, true), &"pick-up", "bending to a crate")
	assert_eq(PersonPresentation.clip_for_state(false, false, true, false, true), &"pick-up",
		"a crate stays in the hands through the bend")
	assert_eq(PersonPresentation.clip_for_state(true, false, false, false, true), &"walk", "never bends while walking")
	assert_eq(PersonPresentation.CLIPS.size(), 6)
	for clip: StringName in PersonPresentation.CLIPS:
		assert_false(String(clip).contains("wheelchair"))
		assert_false(String(clip).contains("attack"))
		assert_ne(clip, &"die")


func test_seated_lean_validation_uses_the_shared_finite_presentation_limit() -> void:
	for degrees: float in [0.0, 7.5, ItemDef.MAX_SEATED_LEAN_DEGREES] as Array[float]:
		assert_true(PersonPresentation.seated_lean_valid(degrees))
	for degrees: float in [-0.001, ItemDef.MAX_SEATED_LEAN_DEGREES + 0.001, NAN, INF, -INF] as Array[float]:
		assert_false(PersonPresentation.seated_lean_valid(degrees))


func test_tourists_and_the_office_crowd_have_their_own_looks_and_no_one_else_does() -> void:
	for id: int in [0, 1, 2, 3, -1, -2, 9223372036854775807]:
		for role: StringName in [&"customer", &"guest"]:
			assert_true(PersonPresentation.has_sun_hat(role, &"tourist"))
			assert_false(PersonPresentation.has_lanyard(role, &"tourist"))
			assert_true(PersonPresentation.has_lanyard(role, &"office"))
			assert_false(PersonPresentation.has_sun_hat(role, &"office"))
		for kind: StringName in [&"regular", &"student", &"foodie", &"family", &"unknown"]:
			assert_false(PersonPresentation.has_sun_hat(&"customer", kind))
			assert_false(PersonPresentation.has_lanyard(&"customer", kind))
			assert_eq(PersonPresentation.type_look_key(&"customer", id, kind), &"")
			var model: StringName = PersonPresentation.model_for(&"customer", id, kind)
			assert_true(PersonPresentation.type_recolors(&"customer", id, kind, model).is_empty())
		for role: StringName in [&"cook", &"server", &"owner", &"courier", &"inspector"]:
			assert_false(PersonPresentation.has_sun_hat(role, &"tourist"))
			assert_false(PersonPresentation.has_lanyard(role, &"office"))
			assert_eq(PersonPresentation.type_look_key(role, id, &"tourist"), &"")
			assert_true(PersonPresentation.type_recolors(role, id, &"tourist", &"character-female-d").is_empty())


func test_tourist_and_office_models_and_colors_are_deterministic_by_guest_id() -> void:
	var colors_seen: Dictionary[String, bool] = {}
	for kind: StringName in [&"tourist", &"office"]:
		var pair: Array[StringName] = []
		for id: int in [0, 1, 2, 3, 4, 5, -1, -2, -3, -4, 9223372036854775807, -9223372036854775807 - 1]:
			var model: StringName = PersonPresentation.model_for(&"customer", id, kind)
			assert_eq(model, PersonPresentation.model_for(&"customer", id, kind), "same id, same model")
			assert_true(PersonPresentation.GUEST_MODELS.has(model))
			if not pair.has(model):
				pair.append(model)
			var recolors: Array[Dictionary] = PersonPresentation.type_recolors(&"customer", id, kind, model)
			assert_false(recolors.is_empty(), "%s id %d is repainted" % [kind, id])
			assert_eq(recolors, PersonPresentation.type_recolors(&"customer", id, kind, model))
			assert_eq(recolors[0]["rect"], PersonPresentation.CLOTHING_RAMPS[model], "the model's own clothing block")
			assert_true(Rect2i(0, 0, 512, 512).encloses(recolors[0]["rect"]))
			assert_eq(PersonPresentation.type_look_key(&"customer", id, kind),
				StringName("%s:%d" % [kind, PersonPresentation.type_variant(id)]))
			colors_seen["%s:%s" % [kind, (recolors[0]["color"] as Color).to_html()]] = true
		assert_eq(pair.size(), 2, "%s use a male and a female model" % kind)
	assert_eq(colors_seen.size(), 4, "two shirt colors and two jacket colors")
	# The color index is independent of the model index (the low id bit).
	for kind: StringName in [&"tourist", &"office"]:
		var combos: Dictionary[String, bool] = {}
		for id: int in range(8):
			combos["%s:%d" % [PersonPresentation.model_for(&"customer", id, kind), PersonPresentation.type_variant(id)]] = true
		assert_eq(combos.size(), 4, "each model wears both colors")


func test_tourist_hat_fits_every_model_the_pair_can_use() -> void:
	for id: int in [0, 1]:
		var model: StringName = PersonPresentation.model_for(&"customer", id, &"tourist")
		assert_true(PersonPresentation.source_head_top(model) > 0.0, "a measured head top for %s" % model)


const LOCATION_TYPES: Array[StringName] = [&"farmer", &"walker", &"surfer", &"forager"]


func test_location_guests_have_their_own_pieces_and_no_one_else_does() -> void:
	for role: StringName in [&"customer", &"guest"]:
		assert_true(PersonPresentation.has_farm_hat(role, &"farmer"))
		assert_true(PersonPresentation.has_overall_bib(role, &"farmer"))
		assert_true(PersonPresentation.has_beanie(role, &"walker"))
		assert_true(PersonPresentation.has_basket(role, &"forager"))
		assert_true(PersonPresentation.has_sunglasses(role, &"surfer"))
	for kind: StringName in [&"regular", &"student", &"foodie", &"family", &"tourist", &"office", &"unknown", &"surfer"]:
		assert_false(PersonPresentation.has_farm_hat(&"customer", kind))
		assert_false(PersonPresentation.has_beanie(&"customer", kind))
		assert_false(PersonPresentation.has_basket(&"customer", kind))
		assert_false(PersonPresentation.has_overall_bib(&"customer", kind))
		assert_false(PersonPresentation.has_sunglasses(&"customer", kind) and kind != &"surfer")
	for kind: StringName in [&"regular", &"student", &"foodie", &"family", &"tourist", &"office", &"unknown"]:
		for id: int in [0, 1, 2, 3, -1]:
			assert_true(PersonPresentation.outfit(&"customer", id, kind).is_empty(), "%s has no outfit" % kind)
	for kind: StringName in LOCATION_TYPES:
		for role: StringName in [&"cook", &"server", &"owner", &"courier", &"inspector"]:
			assert_true(PersonPresentation.outfit(role, 0, kind).is_empty())
			assert_eq(PersonPresentation.type_look_key(role, 0, kind), &"")
			assert_false(PersonPresentation.has_farm_hat(role, kind) or PersonPresentation.has_beanie(role, kind)
				or PersonPresentation.has_basket(role, kind) or PersonPresentation.has_overall_bib(role, kind))
	# An unknown type keeps the full stock model mapping and no look.
	for id: int in range(8):
		assert_eq(PersonPresentation.model_for(&"customer", id, &"sailor"), PersonPresentation.GUEST_MODELS[id])
		assert_eq(PersonPresentation.type_look_key(&"customer", id, &"sailor"), &"")


func test_location_guest_models_and_palettes_are_deterministic_by_guest_id() -> void:
	for kind: StringName in LOCATION_TYPES:
		var models: Dictionary[StringName, bool] = {}
		var outfits: Dictionary[String, bool] = {}
		for id: int in [0, 1, 2, 3, 4, 5, -1, -2, -3, -4, 9223372036854775807, -9223372036854775807 - 1]:
			var model: StringName = PersonPresentation.model_for(&"customer", id, kind)
			assert_eq(model, PersonPresentation.model_for(&"guest", id, kind))
			assert_true(PersonPresentation.GUEST_MODELS.has(model))
			assert_true(PersonPresentation.SKIN_COLUMNS.has(model), "%s: a measured skin block" % model)
			models[model] = true
			var outfit: Dictionary = PersonPresentation.outfit(&"customer", id, kind)
			assert_false(outfit.is_empty(), "%s id %d is dressed" % [kind, id])
			assert_eq(outfit, PersonPresentation.outfit(&"customer", id, kind), "same id, same clothes")
			assert_true(outfit.get("upper") is Color)
			assert_eq(PersonPresentation.type_look_key(&"customer", id, kind),
				StringName("%s:%d" % [kind, PersonPresentation.type_variant(id)]))
			outfits[var_to_str(outfit)] = true
			if outfit.has("hair"):
				assert_true(PersonPresentation.HAIR_COLUMNS.has(model), "%s: a measured hair block" % model)
		assert_eq(models.size(), 2, "%s use a pair of models" % kind)
		assert_eq(outfits.size(), 2, "%s wear one of two palettes" % kind)
		# Each model of the pair wears both palettes.
		var combos: Dictionary[String, bool] = {}
		for id: int in range(8):
			combos["%s:%d" % [PersonPresentation.model_for(&"customer", id, kind), PersonPresentation.type_variant(id)]] = true
		assert_eq(combos.size(), 4)
	# Hats and beanies fit a measured head top; the hat models have no bun or cap.
	for kind: StringName in [&"farmer", &"walker"]:
		for id: int in [0, 1]:
			var model: StringName = PersonPresentation.model_for(&"customer", id, kind)
			assert_true(PersonPresentation.source_head_top(model) > 0.0 and PersonPresentation.source_head_top(model) < 0.75,
				"%s fits a hat on %s" % [kind, model])


func test_outfit_regions_paint_the_right_body_parts() -> void:
	var skin: Vector2i = Vector2i(480, 384)
	var cloth: Vector2i = Vector2i(352, 256)
	# Legs: a block that reaches the hips is clothing; one that stays below the knee
	# (shoes, boots, socks, bare shins) is kept whatever its height.
	assert_eq(PersonOutfit.region_for(&"leg-left", Vector3(0.08, 0.01, 0.0), cloth, 0.17), PersonOutfit.Region.KEEP, "hem on the shoe")
	assert_eq(PersonOutfit.region_for(&"leg-right", Vector3(-0.08, 0.06, 0.0), cloth, 0.17), PersonOutfit.Region.SHIN)
	assert_eq(PersonOutfit.region_for(&"leg-left", Vector3(0.08, 0.14, 0.0), cloth, 0.17), PersonOutfit.Region.THIGH)
	assert_eq(PersonOutfit.region_for(&"leg-left", Vector3(0.08, 0.06, 0.0), Vector2i(32, 384), 0.08), PersonOutfit.Region.KEEP, "boot shaft")
	# Torso: skin-toned neckline kept, a skin-toned chest painted (an open shirt under a jacket).
	assert_eq(PersonOutfit.region_for(&"torso", Vector3(0.0, 0.19, 0.0), cloth, 0.3), PersonOutfit.Region.HIP)
	assert_eq(PersonOutfit.region_for(&"torso", Vector3(0.0, 0.3, 0.0), cloth, 0.3), PersonOutfit.Region.TORSO)
	assert_eq(PersonOutfit.region_for(&"torso", Vector3(0.0, 0.3, 0.0), skin, 0.36), PersonOutfit.Region.TORSO)
	assert_eq(PersonOutfit.region_for(&"torso", Vector3(0.0, 0.33, 0.0), Vector2i(448, 384), 0.33), PersonOutfit.Region.KEEP, "neckline")
	assert_eq(PersonOutfit.region_for(&"torso", Vector3(0.0, 0.33, 0.0), cloth, 0.33), PersonOutfit.Region.TORSO, "a collar")
	# Arms: the block reaching the fist is the hand, a wider one no body part.
	assert_eq(PersonOutfit.region_for(&"arm-left", Vector3(0.18, 0.29, 0.0), cloth, 0.3), PersonOutfit.Region.SLEEVE)
	assert_eq(PersonOutfit.region_for(&"arm-left", Vector3(0.31, 0.29, 0.0), skin, 0.33), PersonOutfit.Region.SLEEVE, "a lower sleeve")
	assert_eq(PersonOutfit.region_for(&"arm-right", Vector3(-0.32, 0.29, 0.0), skin, 0.38), PersonOutfit.Region.HAND)
	assert_eq(PersonOutfit.region_for(&"arm-right", Vector3(-0.5, 0.29, 0.0), cloth, 0.54), PersonOutfit.Region.KEEP, "a bag")
	assert_eq(PersonOutfit.region_for(&"head", Vector3(0.0, 0.5, 0.0), cloth, 0.6), PersonOutfit.Region.KEEP)
	var surfer: Dictionary = PersonPresentation.outfit(&"customer", 0, &"surfer")
	assert_eq(PersonOutfit.paint_for(PersonOutfit.Region.SLEEVE, surfer), &"skin", "a tank top bares the arms")
	assert_eq(PersonOutfit.paint_for(PersonOutfit.Region.SHIN, surfer), &"skin", "board shorts bare the shins")
	assert_eq(PersonOutfit.paint_for(PersonOutfit.Region.THIGH, surfer), surfer["lower"])
	assert_ne(surfer["upper"], surfer["lower"], "top and shorts differ")
	var farmer: Dictionary = PersonPresentation.outfit(&"customer", 0, &"farmer")
	assert_eq(PersonOutfit.paint_for(PersonOutfit.Region.HIP, farmer), PersonPresentation.FARMER_DENIM, "overalls cover the hips")
	assert_eq(PersonOutfit.paint_for(PersonOutfit.Region.SHIN, farmer), PersonPresentation.FARMER_DENIM)
	assert_eq(PersonOutfit.paint_for(PersonOutfit.Region.TORSO, farmer), farmer["upper"])
	var walker: Dictionary = PersonPresentation.outfit(&"customer", 0, &"walker")
	assert_eq(PersonOutfit.paint_for(PersonOutfit.Region.HIP, walker), walker["upper"], "a jacket reaches the hips")
	assert_null(PersonOutfit.paint_for(PersonOutfit.Region.THIGH, walker), "walkers keep their own trousers")
	assert_null(PersonOutfit.paint_for(PersonOutfit.Region.HAND, walker), "and their gloves")
	assert_null(PersonOutfit.paint_for(PersonOutfit.Region.KEEP, farmer))
	assert_eq(PersonOutfit.column_of(Vector2(353.5, 300.0)), Vector2i(352, 256))
	assert_eq(PersonOutfit.spare_block(0), Vector2i(0, 0))
	assert_eq(PersonOutfit.spare_block(15), Vector2i(480, 0))
	assert_eq(PersonOutfit.spare_block(16), Vector2i(-1, -1))
