class_name PaintFinish
extends RefCounted
## The material looks a paint slot can wear (#431). IDs are save data; labels
## are player text. Looks only: a finish never changes the sim.

const PAINTED: StringName = &"painted"
const WOOD: StringName = &"wood"
const FABRIC: StringName = &"fabric"
const METAL: StringName = &"metal"
## Catalogue order of the material row.
const ALL: Array[StringName] = [PAINTED, WOOD, FABRIC, METAL]
const LABELS: Dictionary[StringName, String] = {
	PAINTED: "Paint", WOOD: "Wood", FABRIC: "Fabric", METAL: "Metal",
}
const TIPS: Dictionary[StringName, String] = {
	PAINTED: "Paint: a smooth painted coat",
	WOOD: "Wood: a soft wood grain",
	FABRIC: "Fabric: a soft woven cloth",
	METAL: "Metal: a brushed metal sheen",
}


static func valid(id: StringName) -> bool:
	return ALL.has(id)


static func label(id: StringName) -> String:
	return LABELS.get(id, "Auto")
