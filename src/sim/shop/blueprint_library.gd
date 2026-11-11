class_name BlueprintLibrary
extends RefCounted
## Player-owned, not ShopLayout state. Main registers this separate section;
## edits only change memory and join the next morning autosave.

signal changed

const VERSION: int = 1
const MAX_BLUEPRINTS: int = 256
const MAX_ENTRIES: int = 512
const MAX_NAME_LENGTH: int = 80

var blueprints: Array[Blueprint] = []


func add(blueprint: Blueprint) -> bool:
	if blueprint == null or blueprint.entries.is_empty() or blueprint.entries.size() > MAX_ENTRIES \
			or blueprints.size() >= MAX_BLUEPRINTS or blueprints.has(blueprint) \
			or not valid_name(blueprint.display_name):
		return false
	blueprint.display_name = blueprint.display_name.strip_edges()
	blueprints.append(blueprint)
	changed.emit()
	return true


## Clipboard imports get a private copy and a free name. Ordinary add/rename
## and the version-1 save decoder retain their existing behavior.
func add_imported(blueprint: Blueprint) -> Blueprint:
	if blueprint == null or blueprints.size() >= MAX_BLUEPRINTS or blueprint.entries.is_empty() \
			or blueprint.entries.size() > MAX_ENTRIES or not valid_name(blueprint.display_name):
		return null
	for entry: ShopPlacement in blueprint.entries:
		if entry == null:
			return null
	var names: Dictionary[String, bool] = {}
	for saved: Blueprint in blueprints:
		names[saved.display_name] = true
	var base: String = blueprint.display_name.strip_edges()
	var name: String = base
	var suffix_number: int = 2
	while names.has(name):
		var suffix: String = " (%d)" % suffix_number
		name = base.left(MAX_NAME_LENGTH - suffix.length()).strip_edges() + suffix
		suffix_number += 1
	var imported: Blueprint = blueprint.copy()
	imported.display_name = name
	return imported if add(imported) else null


func rename(blueprint: Blueprint, name: String) -> bool:
	if not blueprints.has(blueprint) or not valid_name(name):
		return false
	blueprint.display_name = name.strip_edges()
	changed.emit()
	return true


func remove(blueprint: Blueprint) -> bool:
	if not blueprints.has(blueprint):
		return false
	blueprints.erase(blueprint)
	changed.emit()
	return true


static func valid_name(name: String) -> bool:
	return not name.strip_edges().is_empty() and name.strip_edges().length() <= MAX_NAME_LENGTH \
		and not name.contains("\n") and not name.contains("\r")


func to_dict() -> Dictionary:
	var rows: Array[Dictionary] = []
	for blueprint: Blueprint in blueprints:
		rows.append(blueprint.to_dict())
	return {"version": VERSION, "blueprints": rows}


## Transactional decoder. Unknown content is deliberately skipped, with one
## log line per missing id; malformed data never partially replaces a library.
func restore(data: Dictionary, content: ContentDB, messages: Array[String]) -> bool:
	if not _integer(data.get("version"), VERSION, VERSION) or not data.get("blueprints") is Array:
		return false
	var rows: Array = data["blueprints"]
	if rows.size() > MAX_BLUEPRINTS:
		return false
	var staged: Array[Blueprint] = []
	var notes: Array[String] = []
	for value: Variant in rows:
		if not value is Dictionary:
			return false
		var row: Dictionary = value
		if not row.get("name") is String or not valid_name(row["name"]) or not row.get("entries") is Array:
			return false
		var entries: Array = row["entries"]
		if entries.size() > MAX_ENTRIES:
			return false
		var blueprint: Blueprint = Blueprint.new()
		blueprint.display_name = String(row["name"]).strip_edges()
		for entry_value: Variant in entries:
			if not entry_value is Dictionary:
				return false
			var saved: Dictionary = entry_value
			if not saved.get("item_id") is String or not saved.get("offset") is Array \
					or not saved.get("swatch_id", "") is String or not saved.get("variant_id", "") is String \
					or not _integer(saved.get("rotation"), 0, 3):
				return false
			var offset: Array = saved["offset"]
			if offset.size() != 2 or not _integer(offset[0], 0, 100000) or not _integer(offset[1], 0, 100000):
				return false
			var id: StringName = StringName(saved["item_id"])
			var definition: ItemDef = content.item(id)
			if definition == null:
				notes.append("Blueprint '%s': skipped unknown item '%s'" % [blueprint.display_name, id])
				continue
			if not Blueprint.eligible(definition):
				return false
			var entry: ShopPlacement = ShopPlacement.new()
			entry.item_id = id
			entry.origin = Vector2i(int(offset[0]), int(offset[1]))
			entry.quarter_turns = int(saved["rotation"])
			var swatch: StringName = StringName(saved.get("swatch_id", ""))
			entry.swatch_id = swatch if definition.paintable and content.swatch(swatch) != null else &""
			entry.variant_id = definition.known_variant_id(StringName(saved.get("variant_id", "")))
			entry.paint = PaintLook.from_rows(saved["paint"], definition, content) if saved.has("paint") \
				else PaintLook.legacy(definition, entry.swatch_id)
			blueprint.entries.append(entry)
		if not blueprint.entries.is_empty():
			staged.append(blueprint)
	blueprints = staged
	messages.append_array(notes)
	changed.emit()
	return true


static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and floorf(float(value)) == float(value) and value >= low and value <= high
