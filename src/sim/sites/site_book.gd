class_name SiteBook
extends RefCounted
## The owner's restaurant sites (FK-087). One site is active and lives in the
## ordinary per-site save sections; every other site is frozen here as a copy
## of those sections, with the day it was frozen. Pure data, no nodes.
## Older saves have no "sites" section and load as the starter site alone.
## Version 2 (#464) adds a fixer-upper's "renovation_days_left" to its row;
## a version 1 section loads with no site under renovation.

const VERSION: int = 2
## The oldest sites section this decoder still reads.
const MIN_VERSION: int = 1
const HOME_ID: StringName = &"home"
## The starter shop is the implicit home lot (docs/TECH.md "Lots").
const HOME_LOT: StringName = &"home"
const MAX_NAME_LENGTH: int = 40
## The longest renovation a lot may need (LotDef's own limit).
const MAX_RENOVATION_DAYS: int = LotDef.MAX_RENOVATION_DAYS

## id -> {"lot": StringName, "name": String, "manager": StringName,
## "renovation": int}. A manager is a member id in that site's own "staff"
## section (ids are unique only within one roster). "renovation" is the days
## of work a fixer-upper still needs before it can open (0 = ready); it lives
## on the row because it changes while the site is inactive.
var _info: Dictionary[StringName, Dictionary] = {}
## id -> {"day": int, "sections": Dictionary}; never holds the active site.
var _frozen: Dictionary[StringName, Dictionary] = {}
var active_id: StringName = HOME_ID


func _init() -> void:
	_info[HOME_ID] = {"lot": HOME_LOT, "name": "", "manager": &"", "renovation": 0}


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


## Days of work a fixer-upper still needs before it can open; 0 when ready
## (or for an unknown site).
func renovation_days_left(id: StringName) -> int:
	return int(_info[id]["renovation"]) if _info.has(id) else 0


## True when one of the sites stands on `lot` (an owned lot is not for sale).
func owns_lot(lot: StringName) -> bool:
	return _has_lot(lot)


## One day of renovation done at every site still under it (each close of
## the active site, docs/TECH.md "Limits and renovation"). Returns the ids
## that became ready, sorted.
func count_down_renovations() -> Array[StringName]:
	var ready: Array[StringName] = []
	for id: StringName in site_ids():
		var left: int = int(_info[id]["renovation"])
		if left > 0:
			_info[id]["renovation"] = left - 1
			if left == 1:
				ready.append(id)
	return ready


func is_frozen(id: StringName) -> bool:
	return _frozen.has(id)


## The day a frozen site was last active, or -1.
func frozen_day(id: StringName) -> int:
	return int(_frozen[id]["day"]) if _frozen.has(id) else -1


## A detached copy of a frozen site's per-site sections, or {}.
func frozen_sections(id: StringName) -> Dictionary:
	return (_frozen[id]["sections"] as Dictionary).duplicate(true) if _frozen.has(id) else {}


## Replaces one per-site section of a frozen site in place, keeping its frozen
## day (an away site's booking lapsing at a close, FK-087). Kept in loaded-file
## JSON shape. Returns false and changes nothing for the active site, an
## unknown site or a section that is not per-site.
func set_frozen_section(id: StringName, key: String, section: Dictionary) -> bool:
	if not _frozen.has(id) or not SiteSections.is_per_site(key):
		return false
	(_frozen[id]["sections"] as Dictionary)[key] = _as_json(section)
	return true


## Adds a new inactive site, frozen as of `day` with the given sections and,
## for a fixer-upper, the days of work it needs before it can open. Each lot
## holds at most one site.
func add_site(id: StringName, lot: StringName, display_name: String, day: int, sections: Dictionary,
		renovation_days: int = 0) -> bool:
	if _info.has(id) or not _valid_id(String(id)) or not _valid_id(String(lot)) \
			or _has_lot(lot) or not _valid_name(display_name) or day < 0 \
			or not _valid_sections(sections) or renovation_days < 0 \
			or renovation_days > MAX_RENOVATION_DAYS:
		return false
	_info[id] = {"lot": lot, "name": display_name, "manager": &"", "renovation": renovation_days}
	_frozen[id] = {"day": day, "sections": _as_json(sections)}
	return true


## True when `target` is a frozen site that can become active on `day` (never
## before the day it was frozen). A site under renovation can be switched to
## for designing (D28; it cannot open, see main.gd). A switch checks this
## before restoring anything, so the swap after the restore cannot refuse.
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
		if int(_info[id]["renovation"]) > 0:
			row["renovation_days_left"] = int(_info[id]["renovation"])
		if _frozen.has(id):
			row["frozen_day"] = str(_frozen[id]["day"])
			row["sections"] = (_frozen[id]["sections"] as Dictionary).duplicate(true)
		sites.append(row)
	return {"version": VERSION, "active": String(active_id), "sites": sites}


## Strict: returns null for anything malformed, including unknown keys (a
## newer field must come with a new VERSION, never be dropped silently). The
## active site must be listed without frozen data; every other site must
## carry it. The home site may be absent (a future sale). Version 1 (before
## renovation) migrates by loading every site as ready.
static func from_dict(data: Dictionary) -> SiteBook:
	var version: Variant = data.get("version", null)
	if not (version is int or version is float) or not _only_keys(data, ["version", "active", "sites"]):
		return null
	var number: float = float(version)
	if number != float(MIN_VERSION) and number != float(VERSION):
		return null
	var row_keys: Array[String] = ["id", "lot", "name", "manager", "frozen_day", "sections"]
	if number >= 2.0:
		row_keys.append("renovation_days_left")
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
		if not _only_keys(row, row_keys):
			return null
		var renovation: int = _decode_renovation(row.get("renovation_days_left", 0)) \
			if row.has("renovation_days_left") else 0
		if renovation < 0 or (row.has("renovation_days_left") and renovation == 0):
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
			"manager": StringName(staff), "renovation": renovation}
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


## A saved renovation count: a whole number of days up to the longest
## renovation, or -1.
static func _decode_renovation(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	var days: float = float(value)
	if not is_finite(days) or days != floorf(days) or days < 0.0 or days > float(MAX_RENOVATION_DAYS):
		return -1
	return int(days)


static func _decode_day(value: Variant) -> int:
	if value is String and (value as String).is_valid_int():
		var day: int = (value as String).to_int()
		return day if day >= 0 and str(day) == value else -1
	return -1
