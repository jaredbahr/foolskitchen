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
	# Decor only counts where guests can see it (FK-101): in a guest room joined
	# to the door (furniture ignored). A grid without a street entry (a test
	# grid) counts everything.
	var guests: Dictionary[Vector2i, bool] = {}
	var gated: bool = not grid.entries().is_empty()
	if gated:
		guests = RoomRules.guest_floor(grid)
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if placed.removed or definition == null or definition.id.is_empty() \
				or String(definition.id).strip_edges().is_empty() or definition.charm < 0 \
				or not ItemDef.Category.values().has(definition.category) or not definition.placement_layer_valid() \
				or placed.placement_layer != definition.placement_layer:
			return null
		if gated and definition.category == ItemDef.Category.DECOR and not guest_room_item(grid, placed, guests):
			continue
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


## True when guests can see this item: one of its cells is outside the staff
## rooms and is, or is next to (no wall between), a guest-room floor cell
## (RoomRules.guest_floor).
static func guest_room_item(grid: SimGrid, placed: PlacedItem, guests: Dictionary[Vector2i, bool]) -> bool:
	for cell: Vector2i in placed.cells:
		if grid.is_staff_only(cell):
			continue
		if guests.has(cell):
			return true
		for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + step
			if guests.has(next) and not grid.edge_blocked(cell, next):
				return true
	return false
