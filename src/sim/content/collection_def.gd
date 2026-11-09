class_name CollectionDef
extends Resource
## One authored decor collection. Its requirements are content IDs; UI uses names.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var short_line: String = ""
@export var item_ids: Array[StringName] = []
@export var floor_id: StringName = &""
@export var bonus: float = 2.0
