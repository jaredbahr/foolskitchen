class_name RecipeStep
extends Resource
## A single ordered kitchen operation, measured in fixed simulation ticks.

## Matches the station_type of a STATION ItemDef.
@export var station_type: StringName = &""
@export var duration_ticks: int = 1
