class_name StreetPropSpec
extends Resource
## One kind of street furniture a street sets out on its near pavement (#423):
## how many, and whether it stands against the shop fronts or along the kerb.
## A StreetSet lists these, so a seaside street (#425) swaps the whole prop list
## (lifebuoys and lobster pots for planters and postboxes) without touching the
## planner or the meshes.

enum Kind { TREE_PLANTER, BENCH, BIN, BIKE_RACK, HYDRANT, BUS_STOP, POSTBOX }
## KERB props stand along the kerb side of the pavement, WALL props against the shop fronts.
enum Zone { KERB, WALL }

@export var kind: Kind = Kind.BENCH
@export_range(0, 8) var count: int = 1
@export var zone: Zone = Zone.KERB


static func make(prop_kind: Kind, how_many: int, where: Zone) -> StreetPropSpec:
	var spec: StreetPropSpec = StreetPropSpec.new()
	spec.kind = prop_kind
	spec.count = how_many
	spec.zone = where
	return spec


## The footprint (u along the street, v across the pavement) and height of a prop, in metres.
## Persons are about 0.8 m tall and doors 1.0 m, so every prop is chunky and small.
static func size_of(prop_kind: Kind) -> Vector3:
	match prop_kind:
		Kind.TREE_PLANTER:
			return Vector3(0.5, 1.18, 0.5)
		Kind.BENCH:
			return Vector3(1.0, 0.44, 0.42)
		Kind.BIN:
			return Vector3(0.26, 0.34, 0.26)
		Kind.BIKE_RACK:
			return Vector3(0.84, 0.21, 0.24)
		Kind.HYDRANT:
			return Vector3(0.2, 0.28, 0.2)
		Kind.BUS_STOP:
			return Vector3(2.0, 1.1, 0.8)
		_:
			return Vector3(0.28, 0.54, 0.28)


## Wanted spacing to the nearest prop of the same kind, so no kind clusters.
static func spacing_of(prop_kind: Kind) -> float:
	match prop_kind:
		Kind.TREE_PLANTER:
			return 3.0
		Kind.BENCH:
			return 5.0
		Kind.BIN:
			return 4.5
		_:
			return 8.0
