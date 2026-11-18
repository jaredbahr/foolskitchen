class_name TipJarTuning
extends Resource
## One supported jar close to any service counter qualifies.

const LEDGER_NOTE: String = "Tip jar"

@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.18
@export_range(1, 10, 1) var drop_amount: int = 1
@export_range(0, 10, 1) var range_cells: int = 3


func has_eligible_jar(grid: SimGrid) -> bool:
	if grid == null:
		return false
	var items: Array[PlacedItem] = grid.items()
	for jar: PlacedItem in items:
		var definition: ItemDef = jar.def as ItemDef
		if definition == null or definition.id != &"tip_jar" or grid.surface_support_at(jar.origin) == null:
			continue
		for counter: PlacedItem in items:
			var counter_def: ItemDef = counter.def as ItemDef
			if counter_def == null or not (counter_def.serve_across or counter_def.category == ItemDef.Category.PASS \
					or counter_def.station_type == OrderCounter.STATION):
				continue
			for cell: Vector2i in counter.cells:
				var delta: Vector2i = cell - jar.origin
				if absi(delta.x) + absi(delta.y) <= range_cells:
					return true
	return false
