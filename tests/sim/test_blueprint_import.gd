extends TestCase
## Clipboard name allocation is atomic and leaves ordinary library rules alone.


func test_import_allocates_first_free_suffix_without_mutating_the_source() -> void:
	var library: BlueprintLibrary = BlueprintLibrary.new()
	var source: Blueprint = _blueprint("Dining corner")
	assert_true(library.add(source))
	var second: Blueprint = library.add_imported(source)
	var third: Blueprint = library.add_imported(source)
	assert_not_null(second)
	assert_not_null(third)
	assert_eq(second.display_name, "Dining corner (2)")
	assert_eq(third.display_name, "Dining corner (3)")
	assert_eq(source.display_name, "Dining corner")
	assert_ne(second, source)
	assert_ne(second.entries[0], source.entries[0])
	assert_true(library.remove(second))
	assert_eq(library.add_imported(source).display_name, "Dining corner (2)")


func test_eighty_character_name_keeps_suffix_and_every_result_inside_limit() -> void:
	var library: BlueprintLibrary = BlueprintLibrary.new()
	var source: Blueprint = _blueprint("é".repeat(80))
	assert_true(library.add(source))
	var second: Blueprint = library.add_imported(source)
	var third: Blueprint = library.add_imported(source)
	assert_eq(second.display_name, "é".repeat(76) + " (2)")
	assert_eq(third.display_name, "é".repeat(76) + " (3)")
	assert_eq(second.display_name.length(), 80)
	assert_eq(third.display_name.length(), 80)
	assert_eq(source.display_name.length(), 80)
	assert_true(BlueprintLibrary.valid_name(second.display_name))


func test_full_library_refuses_before_renaming_or_copying_source() -> void:
	var library: BlueprintLibrary = BlueprintLibrary.new()
	for i: int in BlueprintLibrary.MAX_BLUEPRINTS:
		assert_true(library.add(_blueprint("Corner %d" % i)))
	var source: Blueprint = _blueprint("Corner 0")
	var before: Dictionary = library.to_dict()
	assert_null(library.add_imported(source))
	assert_eq(library.to_dict(), before)
	assert_eq(source.display_name, "Corner 0")
	assert_eq(source.entries.size(), 1)


func test_ordinary_add_and_rename_keep_existing_duplicate_name_behavior() -> void:
	var library: BlueprintLibrary = BlueprintLibrary.new()
	var first: Blueprint = _blueprint("Same")
	var second: Blueprint = _blueprint("Same")
	assert_true(library.add(first))
	assert_true(library.add(second))
	assert_true(library.rename(second, "Same"))
	assert_eq(first.display_name, second.display_name)
	assert_eq(library.VERSION, 1)
	assert_eq(library.MAX_ENTRIES, 512)


func _blueprint(display_name: String) -> Blueprint:
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = display_name
	var entry: ShopPlacement = ShopPlacement.new()
	entry.item_id = &"potted_plant"
	blueprint.entries.append(entry)
	return blueprint
