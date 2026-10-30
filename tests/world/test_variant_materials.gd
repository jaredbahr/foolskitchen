extends TestCase

var _root: Node3D
var _controller: PropVariantMaterials


func after_each() -> void:
	if _controller != null:
		_controller.restore()
		_controller = null
	if _root != null:
		_root.free()
		_root = null


func test_recipe_changes_only_named_surfaces_and_never_shared_sources() -> void:
	_start_booth()
	var before: Dictionary = _materials()
	var look: ItemVariant = load("res://data/variants/booth_walnut.tres") as ItemVariant
	assert_true(_controller.apply(look))
	var after: Dictionary = _materials()
	var palette: Dictionary[StringName, Color] = KitMaterialColours.colours()
	for name: String in before:
		if name == "carpetWhite":
			assert_eq((after[name] as BaseMaterial3D).albedo_color, palette[&"woodDark"])
			assert_ne(after[name], before[name])
		else:
			assert_eq(after[name], before[name], "unlisted surface keeps its exact material")
	assert_ne((before["carpetWhite"] as BaseMaterial3D).albedo_color, palette[&"woodDark"])


func test_changing_and_clearing_recipe_restores_exact_original_overrides() -> void:
	_start_booth()
	var before: Dictionary = _materials()
	assert_true(_controller.apply(load("res://data/variants/booth_walnut.tres") as ItemVariant))
	assert_true(_controller.apply(load("res://data/variants/booth_red.tres") as ItemVariant))
	assert_true(_controller.apply(null))
	assert_eq(_materials(), before)


func test_bad_material_or_surface_refuses_atomically() -> void:
	_start_booth()
	assert_true(_controller.apply(load("res://data/variants/booth_walnut.tres") as ItemVariant))
	var before: Dictionary = _materials()
	var bad: ItemVariant = ItemVariant.new()
	bad.id = &"bad"
	bad.display_name = "Bad"
	bad.material_colours = {&"carpetWhite": &"carpet", &"not_a_surface": &"wood"}
	assert_false(_controller.apply(bad))
	assert_eq(_materials(), before)
	bad.material_colours = {&"carpetWhite": &"not_a_kit_colour"}
	assert_false(_controller.apply(bad))
	assert_eq(_materials(), before)


func test_first_set_has_three_valid_looks_and_legacy_defaults_preserve_price_tags() -> void:
	for id: String in ["diner_booth", "diner_stool"]:
		var definition: ItemDef = load("res://data/items/%s.tres" % id) as ItemDef
		assert_eq(definition.variants.size(), 3)
		assert_eq(definition.variant(), definition.variants[0])
		assert_eq(definition.variant(&"missing"), definition.variants[0])
		assert_eq(definition.variant_price(), definition.price)
		assert_eq(definition.variant_tags(), definition.theme_tags)
		assert_true(definition.variant().material_colours.is_empty())
		for look: ItemVariant in definition.variants:
			assert_true(look.valid())


func test_every_authored_recipe_resolves_on_its_actual_wrapper() -> void:
	for id: String in ["diner_booth", "diner_stool"]:
		var definition: ItemDef = load("res://data/items/%s.tres" % id) as ItemDef
		var model: Node = definition.view_scene.instantiate()
		var recipe: PropVariantMaterials = PropVariantMaterials.new(model)
		for look: ItemVariant in definition.variants:
			assert_true(recipe.apply(look), String(look.id))
		recipe.restore()
		model.free()


func test_variant_price_and_tags_are_detached_data() -> void:
	var definition: ItemDef = ItemDef.new()
	definition.price = 20
	definition.theme_tags = [&"diner"]
	var look: ItemVariant = ItemVariant.new()
	look.id = &"walnut"
	look.display_name = "Walnut"
	look.price_delta = 5
	look.theme_tags = [&"cosy"]
	definition.variants = [look]
	assert_eq(definition.variant_price(&"walnut"), 25)
	assert_eq(definition.variant_tags(&"walnut"), [&"cosy"] as Array[StringName])
	var tags: Array[StringName] = definition.variant_tags()
	tags.clear()
	assert_eq(look.theme_tags, [&"cosy"] as Array[StringName])
	assert_eq(definition.theme_tags, [&"diner"] as Array[StringName])


func test_palette_returns_detached_kit_colours() -> void:
	var palette: Dictionary[StringName, Color] = KitMaterialColours.colours()
	assert_true(palette.has(&"woodDark"))
	assert_true(palette.has(&"metalDark"))
	palette.clear()
	assert_true(KitMaterialColours.colours().has(&"woodDark"))


func _start_booth() -> void:
	_root = (load("res://assets/props/diner_booth.tscn") as PackedScene).instantiate() as Node3D
	_controller = PropVariantMaterials.new(_root)


func _materials() -> Dictionary:
	var out: Dictionary = {}
	_collect(_root, out)
	return out


func _collect(node: Node, out: Dictionary) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for index: int in range(mesh.mesh.get_surface_count()):
			var source: Material = mesh.mesh.surface_get_material(index)
			out[source.resource_name] = mesh.get_active_material(index)
	for child: Node in node.get_children():
		_collect(child, out)


func test_prop_paint_overrides_body_only_and_clear_restores_selected_look() -> void:
	_root = (load("res://assets/props/diner_stool.tscn") as PackedScene).instantiate() as PropView
	var prop: PropView = _root as PropView
	var look: ItemVariant = load("res://data/variants/stool_dark_white.tres") as ItemVariant
	var palette: Dictionary[StringName, Color] = KitMaterialColours.colours()
	assert_true(prop.set_variant(look))
	var selected: Dictionary = _materials()
	assert_eq((selected["metal"] as BaseMaterial3D).albedo_color, palette[&"metalDark"])
	assert_eq((selected["carpet"] as BaseMaterial3D).albedo_color, palette[&"carpetWhite"])
	prop.set_body_tint(palette[&"woodDark"])
	assert_eq(prop.active_body_material().albedo_color, palette[&"woodDark"])
	assert_eq((_materials()["metal"] as BaseMaterial3D).albedo_color, palette[&"metalDark"])
	prop.clear_body_tint()
	assert_eq(prop.active_body_material().albedo_color, palette[&"carpetWhite"])
	prop.set_body_tint(palette[&"woodDark"])
	assert_true(prop.set_variant(load("res://data/variants/stool_chrome_teal.tres") as ItemVariant))
	assert_eq(prop.active_body_material().albedo_color, palette[&"woodDark"])
	prop.clear_body_tint()
	assert_eq(prop.active_body_material().albedo_color, palette[&"metalDark"])


func test_first_variant_after_paint_captures_unpainted_material_baseline() -> void:
	_root = (load("res://assets/props/diner_stool.tscn") as PackedScene).instantiate() as PropView
	var prop: PropView = _root as PropView
	var original: Color = prop.active_body_material().albedo_color
	var palette: Dictionary[StringName, Color] = KitMaterialColours.colours()
	prop.set_body_tint(palette[&"woodDark"])
	assert_true(prop.set_variant(load("res://data/variants/stool_chrome_teal.tres") as ItemVariant))
	assert_eq(prop.active_body_material().albedo_color, palette[&"woodDark"])
	prop.clear_body_tint()
	assert_eq(prop.active_body_material().albedo_color, palette[&"metalDark"])
	assert_true(prop.set_variant(null))
	assert_eq(prop.active_body_material().albedo_color, original)
