class_name ShopPlacement
extends Resource
## One item placed in a ShopLayout.

## ItemDef id from data/items.
@export var item_id: StringName = &""
@export var origin: Vector2i = Vector2i.ZERO
## Clockwise quarter turns seen from above (GridMath.rotate_cell).
@export_range(0, 3) var quarter_turns: int = 0
## Body paint for this placed item; empty is its default placeholder colour.
@export var swatch_id: StringName = &""
## Authored furniture look; empty preserves the first/default look.
@export var variant_id: StringName = &""
## Per-slot paint (#431); never authored in layout files, so not exported.
var paint: PaintLook = PaintLook.new()


## Resource.duplicate() skips the unexported paint; copy it explicitly.
func copy() -> ShopPlacement:
	var result: ShopPlacement = duplicate() as ShopPlacement
	result.paint = paint.copy()
	return result
