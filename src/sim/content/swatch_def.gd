class_name SwatchDef
extends Resource
## A named, curated paint colour. IDs are save data; names are player text.

@export var id: StringName = &""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
## Optional style tags for derived restaurant themes; legacy swatches stay neutral.
@export var theme_tags: Array[StringName] = []
