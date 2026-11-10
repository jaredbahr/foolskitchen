class_name SiteBook
extends RefCounted
## The owner's restaurant sites (FK-087). One site is active and lives in the
## ordinary per-site save sections; every other site is frozen here as a copy
## of those sections, with the day it was frozen. Pure data, no nodes.
## Older saves have no "sites" section and load as the starter site alone.

const VERSION: int = 1
const HOME_ID: StringName = &"home"
## The starter shop is the implicit home lot (docs/TECH.md "Lots").
const HOME_LOT: StringName = &"home"
const MAX_NAME_LENGTH: int = 40

## id -> {"lot": StringName, "name": String, "manager": StringName}. A manager
## is a member id in that site's own "staff" section (ids are unique only
## within one roster).
var _info: Dictionary[StringName, Dictionary] = {}
## id -> {"day": int, "sections": Dictionary}; never holds the active site.
var _frozen: Dictionary[StringName, Dictionary] = {}
var active_id: StringName = HOME_ID


func _init() -> void:
	_info[HOME_ID] = {"lot": HOME_LOT, "name": "", "manager": &""}


## Every site id: the active one first, then the frozen ones sorted.
func site_ids() -> Array[StringName]:
	var ids: Array[StringName] = [active_id]
	var others: Array[StringName] = []
	for id: StringName in _info:
		if id != active_id:
			others.append(id)
	others.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	ids.append_array(others)
	return ids


func site_count() -> int:
	return _info.size()


func has_site(id: StringName) -> bool:
	return _info.has(id)


func lot_id(id: StringName) -> StringName:
	return _info[id]["lot"] if _info.has(id) else &""


func site_name(id: StringName) -> String:
	return _info[id]["name"] if _info.has(id) else ""


func manager(id: StringName) -> StringName:
	return _info[id]["manager"] if _info.has(id) else &""


func is_frozen(id: StringName) -> bool:
	return _frozen.has(id)


## The day a frozen site was last active, or -1.
func frozen_day(id: StringName) -> int:
	return int(_frozen[id]["day"]) if _frozen.has(id) else -1


## A detached copy of a frozen site's per-site sections, or {}.
func frozen_sections(id: StringName) -> Dictionary:
	return (_frozen[id]["sections"] as Dictionary).duplicate(true) if _frozen.has(id) else {}


## Adds a new inactive site, frozen as of `day` with the given sections.
## Each lot holds at most one site.
func add_site(id: StringName, lot: StringName, display_name: String, day: int, sections: Dictionary) -> bool:
	if _info.has(id) or not _valid_id(String(id)) or not _valid_id(String(lot)) \
			or _has_lot(lot) or not _valid_name(display_name) or day < 0 \
			or not _valid_sections(sections):
		return false
	_info[id] = {"lot": lot, "name": display_name, "manager": &""}
	_frozen[id] = {"day": day, "sections": _as_json(sections)}
	return true


## True when `target` is a frozen site that can become active on `day` (never
## before the day it was frozen). A switch checks this before restoring
## anything, so the swap after the restore cannot refuse.
func can_swap(target: StringName, day: int) -> bool:
	return target != active_id and _frozen.has(target) and day >= int(_frozen[target]["day"])


## Makes `target` the active site: the departing one is frozen with `sections`
## as of `day`, and the target's frozen copy is dropped (the caller has
## already restored it). Returns false and changes nothing on bad input.
func swap_active(target: StringName, day: int, departing_sections: Dictionary) -> bool:
	if not can_swap(target, day) or not _valid_sections(departing_sections):
		return false
	_frozen[active_id] = {"day": day, "sections": _as_json(departing_sections)}
	_frozen.erase(target)
	active_id = target
	return true


## True when no site was frozen after `day` (a load's morning check).
func valid_before(day: int) -> bool:
	for id: StringName in _frozen:
		if int(_frozen[id]["day"]) > day:
			return false
	return true


## An empty id clears the manager.
func set_manager(id: StringName, staff_id: StringName) -> bool:
	if not _info.has(id) or (staff_id != &"" and not _valid_id(String(staff_id))):
		return false
	_info[id]["manager"] = staff_id
	return true


func to_dict() -> Dictionary:
	var sites: Array[Dictionary] = []
	for id: StringName in site_ids():
		var row: Dictionary = {"id": String(id), "lot": String(_info[id]["lot"]),
			"name": _info[id]["name"], "manager": String(_info[id]["manager"])}
		if _frozen.has(id):
			row["frozen_day"] = str(_frozen[id]["day"])
			row["sections"] = (_frozen[id]["sections"] as Dictionary).duplicate(true)
		sites.append(row)
	return {"version": VERSION, "active": String(active_id), "sites": sites}


## Strict: returns null for anything malformed, including unknown keys (a
## newer field must come with a new VERSION, never be dropped silently). The
## active site must be listed without frozen data; every other site must
## carry it. The home site may be absent (a future sale).
static func from_dict(data: Dictionary) -> SiteBook:
	var version: Variant = data.get("version", null)
	if not (version is int or version is float) or float(version) != float(VERSION) \
			or not _only_keys(data, ["version", "active", "sites"]):
		return null
	var active: Variant = data.get("active", null)
	var rows: Variant = data.get("sites", null)
	if not active is String or not _valid_id(active) or not rows is Array:
		return null
	var book: SiteBook = SiteBook.new()
	book._info.clear()
	for raw: Variant in rows:
		if not raw is Dictionary:
			return null
		var row: Dictionary = raw
		if not _only_keys(row, ["id", "lot", "name", "manager", "frozen_day", "sections"]):
			return null
		var id: Variant = row.get("id", null)
		var lot: Variant = row.get("lot", null)
		var display_name: Variant = row.get("name", null)
		var staff: Variant = row.get("manager", null)
		if not id is String or not _valid_id(id) or not lot is String or not _valid_id(lot) \
				or not display_name is String or not _valid_name(display_name) \
				or not staff is String or (not (staff as String).is_empty() and not _valid_id(staff)) \
				or book._info.has(StringName(id)) or book._has_lot(StringName(lot)):
			return null
		book._info[StringName(id)] = {"lot": StringName(lot), "name": display_name,
			"manager": StringName(staff)}
		var frozen: bool = row.has("frozen_day") or row.has("sections")
		if id == active:
			if frozen:
				return null
			continue
		var day: int = _decode_day(row.get("frozen_day", null))
		var sections: Variant = row.get("sections", null)
		if day < 0 or not sections is Dictionary or not _valid_sections(sections):
			return null
		book._frozen[StringName(id)] = {"day": day, "sections": (sections as Dictionary).duplicate(true)}
	if not book._info.has(StringName(active)):
		return null
	book.active_id = StringName(active)
	return book


static func _valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > MAX_NAME_LENGTH:
		return false
	for character: String in id:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") \
				and character != "_":
			return false
	return true


static func _valid_name(display_name: String) -> bool:
	if display_name.length() > MAX_NAME_LENGTH or display_name != display_name.strip_edges():
		return false
	for character: String in display_name:
		if character.unicode_at(0) < 32:
			return false
	return true


func _has_lot(lot: StringName) -> bool:
	for id: StringName in _info:
		if _info[id]["lot"] == lot:
			return true
	return false


static func _only_keys(data: Dictionary, allowed: Array[String]) -> bool:
	for key: Variant in data:
		if not key is String or not allowed.has(key):
			return false
	return true


## Frozen copies are kept in exactly the shape a loaded file gives (numbers as
## floats, no StringNames), so they save the same bytes every time.
static func _as_json(sections: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(sections))


## Only per-site sections, each a Dictionary. Missing sections are allowed:
## older frozen copies skip them on restore, as a load does.
static func _valid_sections(sections: Dictionary) -> bool:
	for key: Variant in sections:
		if not key is String or not SiteSections.is_per_site(key) or not sections[key] is Dictionary:
			return false
	return true


static func _decode_day(value: Variant) -> int:
	if value is String and (value as String).is_valid_int():
		var day: int = (value as String).to_int()
		return day if day >= 0 and str(day) == value else -1
	return -1
