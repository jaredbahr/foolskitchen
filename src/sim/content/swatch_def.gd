class_name SwatchDef
extends Resource
## A named, curated paint colour. IDs are save data; names are player text.

## Palette families (#431), in catalogue order.
const FAMILIES: Array[StringName] = [&"neutral", &"pastel", &"bright", &"deep", &"wood", &"metal"]

@export var id: StringName = &""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
## Optional style tags for derived restaurant themes; legacy swatches stay neutral.
@export var theme_tags: Array[StringName] = []
## Palette family (one of FAMILIES) and order within it, for the Paint grid.
@export var family: StringName = &"neutral"
@export var family_order: int = 0
