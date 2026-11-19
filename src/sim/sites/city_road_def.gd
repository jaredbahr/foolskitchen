class_name CityRoadDef
extends Resource
## One road on the city map between two neighbourhoods (docs/CITY_MAP.md
## section 3, T5): the line the van follows when the owner travels between
## them. Data only, held by CityMapDef.roads; CityMap.van_path reads it.

## Neighbourhood ids at each end (either way round).
@export var from: StringName = &""
@export var to: StringName = &""
## The bends between the two ends, from `from` towards `to`, 0 to 1 on each
## axis like NeighbourhoodDef.map_position. The ends themselves are the
## neighbourhoods' positions; an empty list is a straight road. The art pass
## traces these over the drawn roads.
@export var bends: PackedVector2Array = PackedVector2Array()
