class_name PaintSlotDef
extends Resource
## One paintable part of a catalogue item (#431), such as a chair's frame or its
## cushion. The first slot of an item is its main slot: the body colour that
## `PlacedItem.swatch_id` holds and the vibe reads. IDs are save data.

@export var id: StringName = &""
@export var display_name: String = ""
## Exact imported material names of the model surfaces this slot paints. Empty
## (main slot only) means the item's wrapper scene `body_material_names`.
@export var surfaces: PackedStringArray = []
## The material a freshly painted slot wears (a PaintFinish id).
@export var default_material: StringName = PaintFinish.PAINTED
## Optional SwatchDef id the catalogue suggests first; empty is the kit colour.
@export var default_swatch: StringName = &""


func valid() -> bool:
	return not id.is_empty() and not display_name.strip_edges().is_empty() \
		and PaintFinish.valid(default_material)
