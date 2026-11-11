class_name PaintLook
extends RefCounted
## A placed item's per-slot paint (#431), beside `PlacedItem.swatch_id`, which
## stays the main slot's colour (the vibe and older saves read it). `materials`
## holds a chosen PaintFinish per slot id (absent: the slot's default);
## `swatches` holds the colours of the other slots (absent: the kit colour).
## Values are detached: copy() before sharing between items or history steps.

## Save rows: [[slot_id, material, swatch], ...], one per slot that differs
## from its default, main slot included (its swatch column stays empty).
const MAX_ROWS: int = 8

var materials: Dictionary[StringName, StringName] = {}
var swatches: Dictionary[StringName, StringName] = {}


func copy() -> PaintLook:
	var result: PaintLook = PaintLook.new()
	result.materials = materials.duplicate()
	result.swatches = swatches.duplicate()
	return result


func is_empty() -> bool:
	return materials.is_empty() and swatches.is_empty()


func equals(other: PaintLook) -> bool:
	if other == null:
		return is_empty()
	return materials == other.materials and swatches == other.swatches


func material(slot_id: StringName) -> StringName:
	return materials.get(slot_id, &"")


func swatch(slot_id: StringName) -> StringName:
	return swatches.get(slot_id, &"")


## Empty `value` clears the choice back to the slot's default.
func set_material(slot_id: StringName, value: StringName) -> void:
	if value.is_empty():
		materials.erase(slot_id)
	else:
		materials[slot_id] = value


func set_swatch(slot_id: StringName, value: StringName) -> void:
	if value.is_empty():
		swatches.erase(slot_id)
	else:
		swatches[slot_id] = value


## Stable rows (sorted by slot id) for saves and blueprints. The main slot's
## colour is never here: it is `swatch_id`.
func to_rows() -> Array:
	var ids: Array[String] = []
	for slot_id: StringName in materials:
		ids.append(String(slot_id))
	for slot_id: StringName in swatches:
		if not materials.has(slot_id):
			ids.append(String(slot_id))
	ids.sort()
	var rows: Array = []
	for slot_id: String in ids:
		rows.append([slot_id, String(material(StringName(slot_id))), String(swatch(StringName(slot_id)))])
	return rows


## Forgiving decoder for looks-only data: unknown slots, materials or colours
## and malformed rows are skipped, never an error. A non-Array is empty.
static func from_rows(value: Variant, definition: ItemDef, content: ContentDB) -> PaintLook:
	var result: PaintLook = PaintLook.new()
	if not value is Array or definition == null or not definition.paintable:
		return result
	var slots: Array[PaintSlotDef] = definition.slots()
	var rows: Array = value
	for index: int in mini(rows.size(), MAX_ROWS):
		var row: Variant = rows[index]
		if not row is Array or (row as Array).size() != 3:
			continue
		var cells: Array = row
		if not (cells[0] is String and cells[1] is String and cells[2] is String):
			continue
		var slot_index: int = definition.slot_index(StringName(cells[0]))
		if slot_index < 0:
			continue
		var slot_id: StringName = slots[slot_index].id
		var material_id: StringName = StringName(cells[1])
		if PaintFinish.valid(material_id):
			result.materials[slot_id] = material_id
		var swatch_id: StringName = StringName(cells[2])
		if slot_index > 0 and content != null and content.swatch(swatch_id) != null:
			result.swatches[slot_id] = swatch_id
	return result


## A copied look pasted on another kind of piece (#431): part by part in slot
## order (main to main, second to second); parts the source lacks stay as
## they came. Same-kind pastes are an exact copy.
static func mapped(from: ItemDef, look: PaintLook, to: ItemDef) -> PaintLook:
	if from == to:
		return look.copy()
	var result: PaintLook = PaintLook.new()
	if from == null or to == null or not to.paintable:
		return result
	var source: Array[PaintSlotDef] = from.slots()
	var target: Array[PaintSlotDef] = to.slots()
	for index: int in mini(source.size(), target.size()):
		result.set_material(target[index].id, look.material(source[index].id))
		if index > 0:
			result.set_swatch(target[index].id, look.swatch(source[index].id))
	return result


## Older saves (no paint rows) painted only the main body in a flat coat:
## keep exactly that look by pinning the main slot to Paint when it has a colour.
static func legacy(definition: ItemDef, main_swatch: StringName) -> PaintLook:
	var result: PaintLook = PaintLook.new()
	if definition != null and definition.paintable and not main_swatch.is_empty():
		result.materials[definition.main_slot().id] = PaintFinish.PAINTED
	return result
