class_name InspectionModel
extends RefCounted
## What the health inspector reads, and how it becomes a grade (#302). It only
## reads state the shop already has (dirty tables, floor and restroom upkeep,
## spoiled stock, dirty plates); it adds no mess system of its own and draws
## nothing random.

const TABLES: StringName = &"tables"
const FLOOR: StringName = &"floor"
const RESTROOM: StringName = &"restroom"
const STOCK: StringName = &"stock"
const DISHES: StringName = &"dishes"
## The fixed order, which also breaks ties between equal findings.
const KINDS: Array[StringName] = [TABLES, FLOOR, RESTROOM, STOCK, DISHES]


## The shop as the inspector finds it right now: a count for each kind.
static func capture(sim: RestaurantSim) -> Dictionary:
	var facts: Dictionary = {TABLES: 0, FLOOR: 0, RESTROOM: 0, STOCK: 0, DISHES: 0}
	if sim == null or sim.world == null:
		return facts
	var grid: SimGrid = sim.world.grid
	if sim.kitchen != null:
		for id: int in sim.kitchen.dirty_tables:
			var table: PlacedItem = grid.item(id)
			if table != null and not table.removed:
				facts[TABLES] = int(facts[TABLES]) + 1
		facts[DISHES] = sim.kitchen.dirty_plates
	if sim.cleanliness != null:
		facts[FLOOR] = sim.cleanliness.spot_count()
		facts[RESTROOM] = sim.cleanliness.restroom_spots().size()
	if sim.stock != null:
		# What went off and was thrown out this morning, in currency.
		facts[STOCK] = int(sim.stock.spoilage_value(sim.world.clock.day).get("cost", 0))
	return facts


## Scores `facts` against the tuning. Returns {points, grade, findings}, where
## findings are {kind, count, points} rows for everything that cost points,
## worst first.
static func evaluate(facts: Dictionary, tuning: InspectionTuning) -> Dictionary:
	var rows: Array[Dictionary] = []
	var total: float = 0.0
	for kind: StringName in KINDS:
		var count: int = maxi(0, int(facts.get(kind, 0)))
		var points: float = _points(kind, count, tuning)
		if points > 0.0:
			rows.append({"kind": kind, "count": count, "points": points})
			total += points
	# Stable: equal points keep the fixed order of KINDS.
	rows.sort_custom(_worse_first)
	return {"points": total, "grade": grade_for(total, tuning), "findings": rows}


static func grade_for(points: float, tuning: InspectionTuning) -> StringName:
	if points <= tuning.grade_a_max:
		return &"A"
	if points <= tuning.grade_b_max:
		return &"B"
	return &"C"


static func _points(kind: StringName, count: int, tuning: InspectionTuning) -> float:
	match kind:
		TABLES:
			return float(count) * tuning.table_points
		FLOOR:
			return float(count) * tuning.floor_spot_points
		RESTROOM:
			return float(count) * tuning.restroom_spot_points
		STOCK:
			return minf(float(count) * tuning.spoiled_points_per_cash, tuning.spoiled_points_cap)
		DISHES:
			return float(maxi(0, count - tuning.dirty_plates_free)) * tuning.dirty_plate_points
	return 0.0


static func _worse_first(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["points"]), float(b["points"])):
		return float(a["points"]) > float(b["points"])
	return KINDS.find(a["kind"]) < KINDS.find(b["kind"])
