class_name Prestige
extends RefCounted
## Recognition from the active site's placed furniture and wall decor.

class Result extends RefCounted:
	var uncapped_score: int = 0
	var cap_item: ItemDef

	func value() -> int:
		return uncapped_score if cap_item == null else mini(uncapped_score, cap_item.prestige_cap)

	func _include(item: ItemDef) -> void:
		if item == null:
			return
		uncapped_score += item.prestige
		if item.prestige_cap >= 0 and (cap_item == null or item.prestige_cap < cap_item.prestige_cap):
			cap_item = item


static func score(grid: SimGrid, content: ContentDB, decor: WallDecor = null) -> int:
	return evaluate(grid, content, decor).value()


static func evaluate(grid: SimGrid, content: ContentDB, decor: WallDecor = null) -> Result:
	var result: Result = Result.new()
	for placed: PlacedItem in grid.items():
		var item: ItemDef = placed.def as ItemDef
		if item != null and not placed.removed:
			result._include(content.item(item.id))
	if decor != null:
		for anchor: Vector3i in decor.anchors():
			var hung: WallDecor.Hung = decor.item(anchor)
			result._include(content.item(hung.def_id))
	return result


static func ladles(prestige_score: int, tuning: PrestigeTuning) -> int:
	if tuning == null or not tuning.is_valid():
		return 0
	var thresholds: Vector3i = tuning.thresholds
	return int(prestige_score >= thresholds.x) + int(prestige_score >= thresholds.y) \
		+ int(prestige_score >= thresholds.z)
