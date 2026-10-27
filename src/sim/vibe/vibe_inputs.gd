class_name VibeInputs
extends RefCounted
## Read-only bridge from the current shop to detached, derived vibe inputs.
## The caller supplies only today's enabled recipes and recomputes on edits/load.


## Null means an unavailable or invalid source; VibeModel evaluates it neutrally.
## No resource, placement, reservation, menu selection or random stream mutates.
static func capture(grid: SimGrid, content: ContentDB, menu: Array[RecipeDef],
		wall_swatch: StringName = &"", floor_swatch: StringName = &"") -> VibeModel.Inputs:
	if grid == null or content == null:
		return null
	var inputs: VibeModel.Inputs = VibeModel.Inputs.new()
	for cell: Vector2i in grid.cells():
		if grid.terrain(cell) == SimGrid.Terrain.FLOOR:
			inputs.floor_cells.append(cell)
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if placed.removed or definition == null or definition.id.is_empty() \
				or String(definition.id).strip_edges().is_empty() or definition.charm < 0 \
				or not ItemDef.Category.values().has(definition.category) or not definition.placement_layer_valid() \
				or placed.placement_layer != definition.placement_layer:
			return null
		var item: VibeModel.Item = VibeModel.Item.new()
		item.definition_id = definition.id
		item.charm = float(definition.charm)
		item.category = definition.category
		item.theme_tags = definition.theme_tags.duplicate()
		item.cells = placed.cells.duplicate()
		item.floor_decor = definition.placement_layer == ItemDef.PlacementLayer.FLOOR_DECOR
		if not placed.swatch_id.is_empty():
			var paint: SwatchDef = content.swatch(placed.swatch_id)
			if paint == null:
				return null
			item.paint_theme_tags = paint.theme_tags.duplicate()
		inputs.items.append(item)
	var recipe_ids: Dictionary[StringName, bool] = {}
	for recipe: RecipeDef in menu:
		if recipe == null or String(recipe.id).strip_edges().is_empty() or recipe_ids.has(recipe.id):
			return null
		recipe_ids[recipe.id] = true
		var dish: VibeModel.Dish = VibeModel.Dish.new()
		dish.id = recipe.id
		dish.theme_tags = recipe.theme_tags.duplicate()
		inputs.menu.append(dish)
	if not wall_swatch.is_empty():
		var paint: SwatchDef = content.swatch(wall_swatch)
		if paint == null:
			return null
		inputs.wall_paint_theme_tags = paint.theme_tags.duplicate()
	if not floor_swatch.is_empty():
		var paint: SwatchDef = content.swatch(floor_swatch)
		if paint == null:
			return null
		inputs.floor_paint_theme_tags = paint.theme_tags.duplicate()
	return inputs
