class_name Prestige
extends RefCounted
## Recognition from the active site's placed furniture and wall decor.

const TUNING: PrestigeTuning = preload("res://data/balance/prestige.tres")


class Contribution extends RefCounted:
	var item: ItemDef
	var copies: int
	var point_units: int


class Result extends RefCounted:
	var point_units: int = 0
	var cap_item: ItemDef
	var contributions: Array[Contribution] = []

	## Keep the fractions until the final score is read.
	var uncapped_score: int:
		get:
			@warning_ignore("integer_division")
			return point_units / PrestigeTuning.UNITS_PER_POINT

	func value() -> int:
		return uncapped_score if cap_item == null else mini(uncapped_score, cap_item.prestige_cap)

	func _include(item: ItemDef, copies: int) -> void:
		if item == null:
			return
		if item.prestige_cap >= 0 and (cap_item == null or item.prestige_cap < cap_item.prestige_cap):
			cap_item = item
		if item.prestige > 0:
			var row: Contribution = Contribution.new()
			row.item = item
			row.copies = copies
			row.point_units = item.prestige * TUNING.copy_weight_units(copies)
			point_units += row.point_units
			contributions.append(row)


static func score(grid: SimGrid, content: ContentDB, decor: WallDecor = null) -> int:
	return evaluate(grid, content, decor).value()


static func evaluate(grid: SimGrid, content: ContentDB, decor: WallDecor = null) -> Result:
	var copies: Dictionary[StringName, int] = {}
	for placed: PlacedItem in grid.items():
		var item: ItemDef = placed.def as ItemDef
		if item != null and not placed.removed:
			copies[item.id] = copies.get(item.id, 0) + 1
	if decor != null:
		for anchor: Vector3i in decor.anchors():
			var hung: WallDecor.Hung = decor.item(anchor)
			copies[hung.def_id] = copies.get(hung.def_id, 0) + 1
	var ids: PackedStringArray = PackedStringArray(copies.keys())
	ids.sort()
	var result: Result = Result.new()
	for key: String in ids:
		var id: StringName = StringName(key)
		result._include(content.item(id), copies[id])
	return result


static func ladles(prestige_score: int, tuning: PrestigeTuning) -> int:
	if tuning == null or not tuning.is_valid():
		return 0
	var thresholds: Vector3i = tuning.thresholds
	return int(prestige_score >= thresholds.x) + int(prestige_score >= thresholds.y) \
		+ int(prestige_score >= thresholds.z)
