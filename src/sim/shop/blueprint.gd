class_name Blueprint
extends Resource
## A reusable group of floor furniture. ShopPlacement.origin is an offset
## from the group's top-left anchor, not a live grid position or item id.

@export var display_name: String = ""
@export var entries: Array[ShopPlacement] = []


static func eligible(definition: ItemDef) -> bool:
	return definition != null and definition.category != ItemDef.Category.DOOR \
		and not definition.hangs_on_wall() and definition.placement_layer_valid()


## Box selection captures whole items, in stable placement order. The caller
## selects only items fully enclosed by the box; rugs use their own layer.
static func capture(grid: SimGrid, ids: Array[int], name: String) -> Blueprint:
	var result: Blueprint = Blueprint.new()
	result.display_name = name.strip_edges()
	var anchor: Vector2i = Vector2i.ZERO
	var found: bool = false
	for placed: PlacedItem in grid.items():
		if not ids.has(placed.id) or not eligible(placed.def as ItemDef):
			continue
		anchor = anchor.min(placed.origin) if found else placed.origin
		found = true
	for placed: PlacedItem in grid.items():
		if not ids.has(placed.id) or not eligible(placed.def as ItemDef):
			continue
		var entry: ShopPlacement = ShopPlacement.new()
		entry.item_id = (placed.def as ItemDef).id
		entry.origin = placed.origin - anchor
		entry.quarter_turns = placed.quarter_turns
		entry.swatch_id = placed.swatch_id
		entry.variant_id = placed.variant_id
		result.entries.append(entry)
	return result


func total_price(content: ContentDB) -> int:
	var total: int = 0
	if content == null:
		return total
	for entry: ShopPlacement in entries:
		var definition: ItemDef = content.item(entry.item_id) if entry != null else null
		if definition != null:
			total += definition.variant_price(entry.variant_id)
	return total


## Rotate the entire occupied rectangle, not just each item's origin. The
## correction for the item's already-rotated size matters for non-square
## furniture: its new origin must be the minimum corner of its rotated cells.
func placements(content: ContentDB, anchor: Vector2i, rotation: int) -> Array[ShopPlacement]:
	if content == null:
		return []
	var size: Vector2i = Vector2i.ZERO
	for entry: ShopPlacement in entries:
		var definition: ItemDef = content.item(entry.item_id) if entry != null else null
		if definition == null:
			return []
		size = size.max(entry.origin + GridMath.rotated_footprint(definition.footprint, entry.quarter_turns))
	var result: Array[ShopPlacement] = []
	for entry: ShopPlacement in entries:
		var definition: ItemDef = content.item(entry.item_id)
		var footprint: Vector2i = GridMath.rotated_footprint(definition.footprint, entry.quarter_turns)
		var placed: ShopPlacement = ShopPlacement.new()
		placed.item_id = entry.item_id
		placed.origin = anchor + GridMath.rotate_cell(entry.origin, size, rotation) \
			- GridMath.rotate_cell(Vector2i.ZERO, footprint, rotation)
		placed.quarter_turns = posmod(entry.quarter_turns + rotation, 4)
		placed.swatch_id = entry.swatch_id
		placed.variant_id = entry.variant_id
		result.append(placed)
	return result


func copy() -> Blueprint:
	var result: Blueprint = Blueprint.new()
	result.display_name = display_name
	for entry: ShopPlacement in entries:
		result.entries.append(entry.duplicate() as ShopPlacement)
	return result


func to_dict() -> Dictionary:
	var rows: Array[Dictionary] = []
	for entry: ShopPlacement in entries:
		rows.append({"item_id": String(entry.item_id), "offset": [entry.origin.x, entry.origin.y],
			"rotation": entry.quarter_turns, "swatch_id": String(entry.swatch_id),
			"variant_id": String(entry.variant_id)})
	return {"name": display_name, "entries": rows}
