extends TestCase
## Curated swatch theme tags are optional data and never change their colors.

const KNOWN_THEMES: Array[StringName] = [&"cosy", &"modern", &"rustic", &"diner", &"seafood"]


func test_new_swatch_defaults_to_no_theme_tags() -> void:
	var swatch: SwatchDef = SwatchDef.new()
	assert_eq(swatch.theme_tags, [] as Array[StringName])


func test_existing_palette_loads_with_original_names_and_authored_known_tags() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray(), "all authored swatches still validate")
	assert_eq(content.swatches().size(), 12)

	var expected: Dictionary[StringName, Dictionary] = {
		&"brick": {"name": "Brick", "tags": [&"diner"]},
		&"butter": {"name": "Butter", "tags": [&"cosy"]},
		&"charcoal": {"name": "Charcoal", "tags": [&"modern"]},
		&"clay": {"name": "Clay", "tags": [&"cosy", &"rustic"]},
		&"cream": {"name": "Cream", "tags": [&"cosy"]},
		&"dusty_rose": {"name": "Dusty Rose", "tags": [&"cosy"]},
		&"honey": {"name": "Honey", "tags": [&"cosy", &"rustic"]},
		&"moss": {"name": "Moss", "tags": [&"rustic"]},
		&"sage": {"name": "Sage", "tags": [&"cosy", &"rustic"]},
		&"slate_blue": {"name": "Slate Blue", "tags": [&"modern", &"seafood"]},
		&"terracotta": {"name": "Terracotta", "tags": [&"diner", &"rustic"]},
		&"walnut": {"name": "Walnut", "tags": [&"cosy", &"rustic"]},
	}
	var loaded_ids: Array[StringName] = []
	for swatch: SwatchDef in content.swatches():
		loaded_ids.append(swatch.id)
		assert_true(expected.has(swatch.id), "only the existing palette IDs are loaded")
		var row: Dictionary = expected[swatch.id]
		assert_eq(swatch.display_name, row["name"])
		assert_eq(swatch.theme_tags, row["tags"])
		var seen: Dictionary[StringName, bool] = {}
		for theme: StringName in swatch.theme_tags:
			assert_true(KNOWN_THEMES.has(theme), "swatches only name established themes")
			assert_false(seen.has(theme), "a swatch cannot vote twice for one theme")
			seen[theme] = true
	assert_eq(loaded_ids, [
		&"brick", &"butter", &"charcoal", &"clay", &"cream", &"dusty_rose", &"honey",
		&"moss", &"sage", &"slate_blue", &"terracotta", &"walnut",
	] as Array[StringName])
