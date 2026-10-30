class_name ItemVariant
extends Resource
## An item's authored look. Material names refer to approved kit colours only.

@export var id: StringName = &""
@export var display_name: String = ""
## Approved donor colour displayed by the catalogue selection dot.
@export var chip_colour: StringName = &""
@export var price_delta: int = 0
@export var theme_tags: Array[StringName] = []
## Imported surface material name -> donor kit material colour name.
@export var material_colours: Dictionary[StringName, StringName] = {}


func valid() -> bool:
	if id == &"" or display_name.strip_edges().is_empty():
		return false
	for surface: StringName in material_colours:
		if surface == &"" or material_colours[surface] == &"":
			return false
	return true
