class_name ShopEditor
extends RefCounted
## Closed-phase furniture editing. Checks use an isolated grid; books and live
## grid signals change only when a mutation succeeds. No autoloads or nodes.

## Version 2 adds wall segments (FK-070); version-1 shops have none.
## Version 3 adds the bought floor (FK-080); older shops are the starting shell.
## Version 4 adds rooms (FK-101); older shops get the starting layout's rooms.
## Version 5 adds floor types (D25); older shops are all the default planks.
## Version 6 adds wall finishes and wall decor (D26); older shops are plain
## paint with nothing hung.
const SNAPSHOT_VERSION: int = 6
const WALLS_CLOSED: String = "Walls can only be changed in the morning or after closing"
const FLOORS_CLOSED: String = "New floors can only be laid in the morning or after closing"
const FLOORS_NOT_FLOOR: String = "Floors are laid on the shop floor"
const FLOORS_ALREADY: String = "This floor already looks like that"
const WALL_FINISH_CLOSED: String = "New wall finishes can only be put up in the morning or after closing"
const WALL_FINISH_NOT_WALL: String = "Wall finishes go on the walls inside the shop"
const WALL_FINISH_ALREADY: String = "This wall already looks like that"
const DECOR_CLOSED: String = "Wall decor can only be changed in the morning or after closing"
const DECOR_GONE: String = "That wall decor is no longer there"

var last_check: EditCheck = EditCheck.new()
## The signed cash change of the last successful edit (negative = spent), and
## the id a successful buy gave its item. Undo history reads both (FK-085).
var last_cash_change: int = 0
var last_item_id: int = -1
## The ids of the last successful blueprint stamp, in entry order.
var last_stamp_ids: Array[int] = []
## Cosmetic whole-room paint. Empty IDs use the ShopView defaults.
var wall_swatch_id: StringName = &""
var floor_swatch_id: StringName = &""
## The floor's look per cell (D25). Its default is the free planks in
## floor_swatch_id, so a shop without floor types looks as it always did.
var floors: FloorFinishes = FloorFinishes.new()
## The walls' look per face and the decor hung on them (D26). The finishes'
## default is the free plain paint in wall_swatch_id, so a shop without wall
## finishes looks as it always did.
var walls: WallFinishes = WallFinishes.new()
var decor: WallDecor = WallDecor.new()
## The anchor a successful hang or move left its item at (undo history).
var last_anchor: Vector3i = WallFaces.NO_FACE
var _sim: RestaurantSim
var _content: ContentDB
var _books: ShopEditBooks
var _applying: bool = false
var _owner_level: int = 1
## The lot and the bought floor (FK-080). Null without a layout.
var _footprint: ShopFootprint
var _bought: Dictionary[Vector2i, bool] = {}
## Built-in dry storage from the layout (FK-087).
var pantry_units: int = 0
## Optional () -> Dictionary[int, int]: ingredient units each storage kind
## must hold (stock plus orders). Selling storage that would leave less room
## than that is refused, also on undo and redo. Unset: no storage check.
var storage_need: Callable = Callable()


## Undo and redo (FK-085). The edit moves `amount` cash (signed, negative
## charges) in one ledger line marked with `note`, instead of list prices and
## the half-price refund rate. It also restores a layout the shop already
## accepted, so the checks that only forbid LOSING something (seat, work-spot,
## door and floor reachability, seat links, the unlock level) are skipped:
## the restored layout may already have had an unusable seat. Everything else
## still applies: placement geometry, minimum equipment, items in use, people
## who would be shut in, furniture on removed floor, cash and closed-only.
class Exact extends RefCounted:
	var amount: int = 0
	var note: String = ""

	func _init(cash_change: int = 0, ledger_note: String = "") -> void:
		amount = cash_change
		note = ledger_note


func _init(sim: RestaurantSim, content: ContentDB, books: ShopEditBooks, layout: ShopLayout = null) -> void:
	_sim = sim
	_content = content
	_books = books
	if layout != null:
		wall_swatch_id = _known_swatch(layout.wall_swatch_id)
		floor_swatch_id = _known_swatch(layout.floor_swatch_id)
		_footprint = ShopFootprint.from_layout(layout)
		_bought = ShopFootprint.to_set(layout.floor_cells)
		pantry_units = maxi(0, layout.pantry_units)
		_load_floors(layout)
		_load_walls(layout)


## Main injects the restored owner level before accepting a new purchase.
## This does not change saved placements, including starter furniture.
func set_owner_level(level: int) -> void:
	if level >= 1:
		_owner_level = level


## Paint is free and available during service as well as closed phases.
func paint_wall(swatch_id: StringName) -> bool:
	if not _can_paint(swatch_id):
		return false
	wall_swatch_id = swatch_id
	walls.set_default_swatch(swatch_id)
	return true


func paint_floor(swatch_id: StringName) -> bool:
	if not _can_paint(swatch_id):
		return false
	floor_swatch_id = swatch_id
	floors.set_default_swatch(swatch_id)
	return true


func paint_item(item_id: int, swatch_id: StringName) -> bool:
	if not _can_paint(swatch_id):
		return false
	var placed: PlacedItem = _sim.world.grid.item(item_id)
	if placed == null or not placed.def is ItemDef or not (placed.def as ItemDef).paintable:
		return false
	placed.swatch_id = swatch_id
	return true


func _can_paint(swatch_id: StringName) -> bool:
	return _sim != null and _sim.world != null and _content != null and \
		(swatch_id.is_empty() or _content.swatch(swatch_id) != null)


func _known_swatch(swatch_id: StringName) -> StringName:
	return swatch_id if _content != null and _content.swatch(swatch_id) != null else &""


func can_edit() -> bool:
	return _sim != null and _sim.world != null and not _applying and (
		_sim.world.clock.phase == SimClock.Phase.MORNING or _sim.world.clock.phase == SimClock.Phase.CLOSED)


## Read-only warnings for actual placements, including after a purchase has
## received its real ID. This query neither changes last_check nor books.
func check_current() -> EditCheck:
	if _sim == null or _sim.world == null or _sim.world.grid == null or _content == null:
		return EditCheck.new(false, "The shop is unavailable")
	var ids: Dictionary[int, int] = {}
	var preview: SimGrid = _preview_without(-1, ids)
	if preview == null:
		return EditCheck.new(false, "The current shop has invalid placements")
	var check: EditCheck = EditCheck.new(true)
	_fill_warnings(check, preview, ids)
	return check


func check_move(item_id: int, origin: Vector2i, quarter_turns: int, exact: Exact = null) -> EditCheck:
	var check: EditCheck = _edit_check()
	if not check.ok:
		return check
	var placed: PlacedItem = _sim.world.grid.item(item_id)
	if placed == null:
		return EditCheck.new(false, "That item is no longer in the shop")
	var definition: ItemDef = placed.def as ItemDef
	if not _valid_definition(definition):
		return EditCheck.new(false, "That item has no valid definition")
	for cell: Vector2i in placed.work_cells + placed.seat_cells:
		if placed.reserved_by(cell) != -1:
			return EditCheck.new(false, "This item is in use; try next morning")
	if _linked_seat_in_use(placed):
		return EditCheck.new(false, "This item is in use; try next morning")
	return _check_placement(definition, origin, quarter_turns, item_id, item_id, exact != null)


## `exact` marks an undo/redo (no money moves; see Exact).
func move(item_id: int, origin: Vector2i, quarter_turns: int, exact: Exact = null) -> bool:
	var check: EditCheck = check_move(item_id, origin, quarter_turns, exact)
	last_check = check
	if not check.ok:
		return false
	_applying = true
	var moved: bool = _sim.world.grid.relocate_def(item_id, origin, quarter_turns)
	if moved:
		last_cash_change = 0
	_applying = false
	last_check = check if moved else EditCheck.new(false, "The shop changed; check the move again")
	return moved


func check_buy(def_id: StringName, origin: Vector2i, quarter_turns: int = 0, exact: Exact = null) -> EditCheck:
	var check: EditCheck = _edit_check()
	if not check.ok:
		return check
	var definition: ItemDef = _content.item(def_id)
	if not _valid_definition(definition):
		return EditCheck.new(false, "Unknown or invalid item definition")
	# Undo/redo put back an item the shop already had; only new buys need the level.
	if exact == null and definition.unlock_level > _owner_level:
		return EditCheck.new(false, "Unlocks at level %d" % definition.unlock_level)
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	var charge: int = definition.price if exact == null else -exact.amount
	if (exact == null or charge > 0) and not _books.can_spend_without_loan(charge):
		return EditCheck.new(false, _books.purchase_refusal_reason(charge))
	return _check_placement(definition, origin, quarter_turns, -1, 0, exact != null)


func buy(def_id: StringName, origin: Vector2i, quarter_turns: int = 0, exact: Exact = null) -> bool:
	var check: EditCheck = check_buy(def_id, origin, quarter_turns, exact)
	last_check = check
	if not check.ok:
		return false
	var definition: ItemDef = _content.item(def_id)
	_applying = true
	var placed: PlacedItem = _sim.world.grid.place_def(definition, origin, quarter_turns)
	if placed != null:
		last_item_id = placed.id
		_record_item(-definition.price if exact == null else exact.amount, exact)
	_applying = false
	last_check = check if placed != null else EditCheck.new(false, "The shop changed; check the purchase again")
	return placed != null


## All entries share one final preview. In particular chairs may appear before
## their table in the library; their links and RoomRules are checked only
## after every item has been staged. Normal buy path warnings stay warnings.
func check_stamp(blueprint: Blueprint, anchor: Vector2i, rotation: int = 0, exact: Exact = null) -> EditCheck:
	var check: EditCheck = _edit_check()
	if not check.ok:
		return check
	if blueprint == null or blueprint.entries.is_empty() or blueprint.entries.size() > BlueprintLibrary.MAX_ENTRIES:
		return EditCheck.new(false, CatalogueText.BLUEPRINT_EMPTY)
	var total: int = 0
	for entry: ShopPlacement in blueprint.entries:
		var definition: ItemDef = _content.item(entry.item_id) if entry != null else null
		if not _valid_definition(definition) or not Blueprint.eligible(definition):
			return EditCheck.new(false, CatalogueText.BLUEPRINT_CONTENT)
		if entry.origin.x < 0 or entry.origin.y < 0 or entry.quarter_turns < 0 or entry.quarter_turns > 3:
			return EditCheck.new(false, CatalogueText.BLUEPRINT_INVALID)
		if not entry.swatch_id.is_empty() and (not definition.paintable or _content.swatch(entry.swatch_id) == null):
			return EditCheck.new(false, "Unknown colour")
		if exact == null and definition.unlock_level > _owner_level:
			return EditCheck.new(false, "Unlocks at level %d" % definition.unlock_level)
		total += definition.price
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	var charge: int = total if exact == null else maxi(0, -exact.amount)
	if (exact == null or charge > 0) and not _books.can_spend_without_loan(charge):
		return EditCheck.new(false, _books.purchase_refusal_reason(charge))
	var ids: Dictionary[int, int] = {}
	var preview: SimGrid = _preview_without(-1, ids)
	if preview == null:
		return EditCheck.new(false, "The current shop has invalid placements")
	var proposed: Array[int] = []
	for entry: ShopPlacement in blueprint.placements(_content, anchor, rotation):
		var definition: ItemDef = _content.item(entry.item_id)
		var result: SimGrid.PlaceResult = preview.can_place_def(definition, entry.origin, entry.quarter_turns)
		if result != SimGrid.PlaceResult.OK:
			return EditCheck.new(false, placement_reason(result))
		var placed: PlacedItem = preview.place_def(definition, entry.origin, entry.quarter_turns)
		# Distinct non-live ids let dining and room rules identify every entry.
		ids[placed.id] = -1 - proposed.size()
		proposed.append(placed.id)
	if exact == null:
		for id: int in proposed:
			var dining: EditCheck = EditCheck.validate_dining(_sim.world.grid, preview, ids, id, -1)
			if not dining.ok:
				return dining
		var problem: String = RoomRules.problem(_sim.world.grid, preview, ids)
		if not problem.is_empty():
			return EditCheck.new(false, problem)
	check.cost = charge
	_fill_warnings(check, preview, ids)
	_note_menu_access(check, preview, exact != null)
	return check


func stamp(blueprint: Blueprint, anchor: Vector2i, rotation: int = 0, exact: Exact = null) -> bool:
	var check: EditCheck = check_stamp(blueprint, anchor, rotation, exact)
	last_check = check
	if not check.ok:
		return false
	var entries: Array[ShopPlacement] = blueprint.placements(_content, anchor, rotation)
	var definitions: Array[ItemDef] = []
	for entry: ShopPlacement in entries:
		definitions.append(_content.item(entry.item_id))
	_applying = true
	var placed: Array[PlacedItem] = _sim.world.grid.place_group(definitions, entries)
	if placed.is_empty():
		_applying = false
		last_check = EditCheck.new(false, "The shop changed; check the purchase again")
		return false
	last_stamp_ids.clear()
	for item: PlacedItem in placed:
		last_stamp_ids.append(item.id)
	if exact == null:
		var total: int = 0
		for definition: ItemDef in definitions:
			_record_item(-definition.price, null)
			total += definition.price
		last_cash_change = -total
	else:
		_record_item(exact.amount, exact)
	_applying = false
	last_check = check
	return true


## Undo of one stamp is also all-or-nothing. Check remaining equipment and
## storage as a group: individually removable shelves may not ALL be removed.
func remove_stamp(item_ids: Array[int], exact: Exact) -> bool:
	var check: EditCheck = _check_remove_stamp(item_ids, exact)
	last_check = check
	if not check.ok:
		return false
	_applying = true
	var removed: bool = _sim.world.grid.remove_group(item_ids)
	if removed:
		_record_item(exact.amount, exact)
	_applying = false
	last_check = check if removed else EditCheck.new(false, "The shop changed; check the sale again")
	return removed


func _check_remove_stamp(item_ids: Array[int], exact: Exact) -> EditCheck:
	var check: EditCheck = _edit_check()
	if not check.ok:
		return check
	if exact == null or item_ids.is_empty():
		return EditCheck.new(false, "That furniture is no longer in the shop")
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	if exact.amount < 0 and not _books.can_spend_without_loan(-exact.amount):
		return EditCheck.new(false, _books.purchase_refusal_reason(-exact.amount))
	var live: SimGrid = _sim.world.grid
	var seen: Dictionary[int, bool] = {}
	var required: Dictionary[String, bool] = {}
	var storage_kinds: Dictionary[int, bool] = {}
	for id: int in item_ids:
		var placed: PlacedItem = live.item(id)
		if placed == null or seen.has(id) or not Blueprint.eligible(placed.def as ItemDef):
			return EditCheck.new(false, "That furniture is no longer in the shop")
		seen[id] = true
		for cell: Vector2i in placed.work_cells + placed.seat_cells:
			if placed.reserved_by(cell) != -1:
				return EditCheck.new(false, "This item is in use; try next morning")
		if _linked_seat_in_use(placed):
			return EditCheck.new(false, "This item is in use; try next morning")
		var definition: ItemDef = placed.def as ItemDef
		if definition.storage_units > 0:
			storage_kinds[int(definition.storage_kind)] = true
		var key: String = _required_key(definition)
		if not key.is_empty():
			required[key] = true
	var ids: Dictionary[int, int] = {}
	var preview: SimGrid = _preview_without(-1, ids)
	if preview == null:
		return EditCheck.new(false, "The current shop has invalid placements")
	for preview_id: int in ids.keys():
		if seen.has(ids[preview_id]):
			preview.remove(preview_id)
			ids.erase(preview_id)
	for placed: PlacedItem in preview.items():
		required.erase(_required_key(placed.def as ItemDef))
	if not required.is_empty():
		return EditCheck.new(false, "Keep at least one %s" % required.keys()[0])
	if not storage_kinds.is_empty() and storage_need.is_valid():
		var need: Variant = storage_need.call()
		if need is Dictionary:
			var left: Dictionary[int, int] = StorageSpace.capacities(preview, pantry_units)
			for kind: int in storage_kinds:
				if int(need.get(kind, 0)) > int(left.get(kind, 0)):
					return EditCheck.new(false, StorageSpace.removal_refusal(kind))
	_fill_warnings(check, preview, ids)
	return check


func check_sell(item_id: int, exact: Exact = null) -> EditCheck:
	var check: EditCheck = _edit_check()
	if not check.ok:
		return check
	var placed: PlacedItem = _sim.world.grid.item(item_id)
	if placed == null:
		return EditCheck.new(false, "That item is no longer in the shop")
	var definition: ItemDef = placed.def as ItemDef
	if not _valid_definition(definition):
		return EditCheck.new(false, "That item has no valid definition")
	if _linked_seat_in_use(placed):
		return EditCheck.new(false, "This item is in use; try next morning")
	if definition.category == ItemDef.Category.DOOR:
		return EditCheck.new(false, "The door cannot be sold")
	var required: String = _required_key(definition)
	if not required.is_empty():
		var count: int = 0
		for other: PlacedItem in _sim.world.grid.items():
			if _required_key(other.def as ItemDef) == required:
				count += 1
		if count <= 1:
			return EditCheck.new(false, "Keep at least one %s" % required)
	var storage: String = _storage_refusal(placed)
	if not storage.is_empty():
		return EditCheck.new(false, storage)
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	var ids: Dictionary[int, int] = {}
	var preview: SimGrid = _preview_without(item_id, ids)
	if preview == null:
		return EditCheck.new(false, "The current shop has invalid placements")
	var dining: EditCheck = EditCheck.new(true) if exact != null \
		else EditCheck.validate_dining(_sim.world.grid, preview, ids, -1, item_id)
	if not dining.ok:
		return dining
	_fill_warnings(check, preview, ids)
	_note_menu_access(check, preview, exact != null)
	return check


## -1 is refusal (see last_check/check_sell); zero is a successful free refund.
func sell(item_id: int, exact: Exact = null) -> int:
	var check: EditCheck = check_sell(item_id, exact)
	last_check = check
	if not check.ok:
		return -1
	var definition: ItemDef = _sim.world.grid.item(item_id).def as ItemDef
	var refund: int = sale_refund(definition) if exact == null else exact.amount
	if refund < 0 and not _books.can_spend_without_loan(-refund):
		last_check = EditCheck.new(false, _books.purchase_refusal_reason(-refund))
		return -1
	_applying = true
	var removed: bool = _sim.world.grid.remove(item_id)
	if removed:
		_record_item(refund, exact)
	_applying = false
	last_check = check if removed else EditCheck.new(false, "The shop changed; check the sale again")
	return refund if removed else -1


## Stock never vanishes with a sold shelf or fridge (FK-087): the rest of the
## space of that kind must still hold the stock and the orders. This applies
## to undo and redo too, like any other refused edit.
func _storage_refusal(placed: PlacedItem) -> String:
	var definition: ItemDef = placed.def as ItemDef
	if definition == null or definition.storage_units <= 0 or not storage_need.is_valid():
		return ""
	var need: Variant = storage_need.call()
	if not need is Dictionary:
		return ""
	var kind: int = int(definition.storage_kind)
	var left: Dictionary[int, int] = StorageSpace.capacities(_sim.world.grid, pantry_units, placed.id)
	if int((need as Dictionary).get(kind, 0)) > int(left.get(kind, 0)):
		return StorageSpace.removal_refusal(kind)
	return ""


## Stable placement order, independent nested values, and no runtime references.
func to_dict() -> Dictionary:
	var placements: Array[Dictionary] = []
	for placed: PlacedItem in _sim.world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		placements.append({"def_id": String(definition.id),
			"origin": [placed.origin.x, placed.origin.y], "quarter_turns": placed.quarter_turns,
			"swatch_id": String(placed.swatch_id)})
	var segments: Array[Dictionary] = []
	for edge: Vector3i in _sim.world.grid.segment_edges():
		var kind: WallKindDef = _content.wall_kind_for(_sim.world.grid.segment(edge)) if _content != null else null
		if kind != null:
			segments.append({"edge": [edge.x, edge.y, edge.z], "kind": String(kind.id)})
	var floor: Array[Array] = []
	for cell: Vector2i in ShopFootprint.sorted(_bought):
		floor.append([cell.x, cell.y])
	var rooms: Array[Array] = []
	var painted: Dictionary[Vector2i, int] = _sim.world.grid.rooms()
	for cell: Vector2i in ShopFootprint.sorted(_cell_set(painted.keys())):
		rooms.append([cell.x, cell.y, String(RoomRules.id_of(painted[cell]))])
	return {"version": SNAPSHOT_VERSION, "items": placements, "walls": segments, "floor": floor,
		"rooms": rooms, "wall_swatch_id": String(wall_swatch_id), "floor_swatch_id": String(floor_swatch_id),
		"floor_style_id": String(floors.default_style), "floors": floors.to_rows(),
		"wall_style_id": String(walls.default_style), "wall_finishes": walls.to_rows(), "wall_items": decor.to_rows()}


static func _cell_set(cells: Array) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		out[cell] = true
	return out


## Pure, transactional decoder. A successful layout is staged for a NEW session;
## it never replaces a live grid, changes books or replays morning setup.
## Missing save sections are handled by the caller using the original template.
static func from_dict(data: Dictionary, template_layout: ShopLayout, content: ContentDB, errors: Array[String]) -> ShopLayout:
	if template_layout == null or content == null:
		errors.append("Shop snapshot needs a layout and content")
		return null
	if not _integer_in(data.get("version"), 1, SNAPSHOT_VERSION) or not data.get("items") is Array:
		errors.append("Invalid shop snapshot version or items")
		return null
	if (int(data["version"]) >= 2 or data.has("walls")) and not data.get("walls") is Array:
		errors.append("Invalid shop walls")
		return null
	if (int(data["version"]) >= 3 or data.has("floor")) and not data.get("floor") is Array:
		errors.append("Invalid shop floor")
		return null
	var preview: SimGrid = SimGrid.from_ascii(template_layout.rows)
	var footprint: ShopFootprint = ShopFootprint.from_layout(template_layout)
	var bought: Dictionary[Vector2i, bool] = {}
	var floor_rows: Array = data.get("floor", [])
	if floor_rows.size() > footprint.lot.get_area():
		errors.append("Too much shop floor")
		return null
	for value: Variant in floor_rows:
		var pair: Array = value if value is Array else []
		if pair.size() != 2 or not _integer_in(pair[0], -100000, 100000) or not _integer_in(pair[1], -100000, 100000) \
				or bought.has(Vector2i(int(pair[0]), int(pair[1]))):
			errors.append("Invalid shop floor")
			return null
		bought[Vector2i(int(pair[0]), int(pair[1]))] = true
	if not footprint.problem(bought).is_empty() or not footprint.apply(preview, bought):
		errors.append("Saved floor does not fit the lot")
		return null
	var rows: Array = data["items"]
	# Two grid layers (normal and floor decor); wall decor is saved separately.
	if rows.size() > preview.size.x * preview.size.y * 2:
		errors.append("Too many shop items")
		return null
	var layout: ShopLayout = ShopLayout.new()
	layout.id = template_layout.id
	layout.display_name = template_layout.display_name
	layout.rows = template_layout.rows.duplicate()
	layout.staff_spawns = template_layout.staff_spawns.duplicate()
	layout.lot_west = template_layout.lot_west
	layout.lot_east = template_layout.lot_east
	layout.lot_north = template_layout.lot_north
	layout.floor_cell_price = template_layout.floor_cell_price
	layout.pantry_units = template_layout.pantry_units
	layout.floor_cells = ShopFootprint.sorted(bought)
	layout.wall_swatch_id = _saved_swatch(data.get("wall_swatch_id", ""), content)
	layout.floor_swatch_id = _saved_swatch(data.get("floor_swatch_id", ""), content)
	for value: Variant in rows:
		if not value is Dictionary:
			errors.append("Invalid shop placement")
			return null
		var row: Dictionary = value
		var def_id: Variant = row.get("def_id")
		var origin: Variant = row.get("origin")
		var turns: Variant = row.get("quarter_turns")
		if not (def_id is String or def_id is StringName) or not origin is Array:
			errors.append("Invalid item id or origin")
			return null
		var area: Rect2i = preview.bounds
		if origin.size() != 2 or not _integer_in(origin[0], area.position.x, area.end.x - 1) \
				or not _integer_in(origin[1], area.position.y, area.end.y - 1) or not _integer_in(turns, 0, 3):
			errors.append("Invalid origin or quarter turns")
			return null
		var definition: ItemDef = content.item(StringName(def_id))
		if not _valid_definition(definition):
			errors.append("Unknown or invalid saved item")
			return null
		var placement: ShopPlacement = ShopPlacement.new()
		placement.item_id = definition.id
		placement.origin = Vector2i(int(origin[0]), int(origin[1]))
		placement.quarter_turns = int(turns)
		placement.swatch_id = _saved_swatch(row.get("swatch_id", ""), content) if definition.paintable else &""
		if preview.place_def(definition, placement.origin, placement.quarter_turns) == null:
			errors.append("Saved item does not fit on the layout's floor")
			return null
		layout.placements.append(placement)
	var minimums: Dictionary[String, int] = {}
	for placement: ShopPlacement in template_layout.placements:
		var definition: ItemDef = content.item(placement.item_id)
		if not _valid_definition(definition):
			errors.append("Invalid template item")
			return null
		var key: String = _structure_key(definition)
		if not key.is_empty():
			minimums[key] = int(minimums.get(key, 0)) + 1 if definition.category == ItemDef.Category.DOOR else 1
	var counts: Dictionary[String, int] = {}
	for placed: PlacedItem in preview.items():
		var key: String = _structure_key(placed.def as ItemDef)
		counts[key] = int(counts.get(key, 0)) + 1
	for key: String in minimums:
		if int(counts.get(key, 0)) < minimums[key]:
			errors.append("Saved shop must keep %s" % key)
			return null
	var walls: Array = data.get("walls", [])
	if walls.size() > preview.size.x * preview.size.y * 2:
		errors.append("Too many shop walls")
		return null
	for value: Variant in walls:
		var row: Dictionary = value if value is Dictionary else {}
		var edge_value: Variant = row.get("edge")
		var kind_value: Variant = row.get("kind")
		if not edge_value is Array or (edge_value as Array).size() != 3 \
				or not (kind_value is String or kind_value is StringName):
			errors.append("Invalid shop wall")
			return null
		var parts: Array = edge_value
		if not _integer_in(parts[0], preview.origin.x, preview.bounds.end.x) \
				or not _integer_in(parts[1], preview.origin.y, preview.bounds.end.y) \
				or not _integer_in(parts[2], SimGrid.EDGE_WEST, SimGrid.EDGE_NORTH):
			errors.append("Invalid shop wall")
			return null
		var edge: Vector3i = Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var kind: WallKindDef = content.wall_kind(StringName(kind_value))
		if kind == null or layout.wall_segments.has(edge) \
				or not WallRules.edge_problem(preview, edge, kind.segment as SimGrid.Segment).is_empty():
			errors.append("Saved wall does not fit the layout")
			return null
		preview.set_segment(edge, kind.segment as SimGrid.Segment)
		layout.wall_segments[edge] = kind.id
	# Older expansions could leave a frame standing after its wall opened.
	# Stage the complete run first so a supporting wall saved later counts;
	# drop only unsupported openings instead of discarding the player's shop.
	var orphaned: Array[Vector3i] = WallRules.orphan_openings(preview)
	for edge: Vector3i in orphaned:
		preview.set_segment(edge, SimGrid.Segment.NONE)
		layout.wall_segments.erase(edge)
	if not orphaned.is_empty():
		layout.load_notes.append("Removed window or doorway frames that no longer had a wall.")
	if not WallRules.layout_problem(preview).is_empty():
		errors.append("Saved walls block the shop")
		return null
	var rooms: Dictionary[Vector2i, int] = {}
	if int(data["version"]) >= 4 or data.has("rooms"):
		var saved: Variant = data.get("rooms")
		if not saved is Array or (saved as Array).size() > preview.size.x * preview.size.y:
			errors.append("Invalid shop rooms")
			return null
		for value: Variant in saved:
			var row: Array = value if value is Array else []
			if row.size() != 3 or not _integer_in(row[0], -100000, 100000) or not _integer_in(row[1], -100000, 100000) \
					or not (row[2] is String or row[2] is StringName):
				errors.append("Invalid shop rooms")
				return null
			var cell: Vector2i = Vector2i(int(row[0]), int(row[1]))
			var kind: int = RoomRules.kind_of(StringName(row[2]))
			if kind <= SimGrid.Room.DINING or rooms.has(cell) or preview.terrain(cell) != SimGrid.Terrain.FLOOR:
				errors.append("Saved rooms do not fit the shop")
				return null
			rooms[cell] = kind
	else:
		# Older saves had no rooms: the starting layout's kitchen is inferred
		# (with the back-wall rule for floor they bought). If that would put a
		# seat in the kitchen or leave a seat, toilet or the door reachable only
		# through it, nothing is inferred: every cell stays Dining and the
		# morning asks the player to mark their kitchen.
		var start: SimGrid = SimGrid.from_ascii(template_layout.rows)
		var authored: Dictionary[Vector2i, int] = {}
		var wanted: Dictionary[Vector2i, int] = template_layout.authored_rooms()
		for cell: Vector2i in wanted:
			if start.terrain(cell) == SimGrid.Terrain.FLOOR:
				authored[cell] = wanted[cell]
		start.set_rooms(authored)
		var inferred: Dictionary[Vector2i, int] = authored.duplicate()
		inferred.merge(RoomRules.opened_kitchen(start, preview, footprint.building))
		var filtered: Dictionary[Vector2i, int] = {}
		for cell: Vector2i in inferred:
			if preview.terrain(cell) == SimGrid.Terrain.FLOOR:
				filtered[cell] = inferred[cell]
		preview.set_rooms(filtered)
		var problems: bool = false
		for key: String in RoomRules.violations(preview, {} as Dictionary[int, int]):
			if not key.begins_with("pass:"):
				problems = true
		if problems:
			layout.rooms_unmarked = true
		else:
			rooms = filtered
	layout.room_rows = template_layout.room_rows.duplicate()
	layout.room_cells = rooms
	layout.rooms_explicit = true
	_decode_floors(data, preview, content, layout)
	_decode_walls(data, preview, content, layout)
	return layout


## Floor types (D25) are looks only, so their decoding forgives: an unknown
## floor type or a cell that is no longer floor falls back to the default
## planks, an unknown colour to the floor type's own colour, and a malformed
## row is skipped. Versions 1 to 4 had none (every cell the default).
static func _decode_floors(data: Dictionary, preview: SimGrid, content: ContentDB, layout: ShopLayout) -> void:
	# The shop's default floor is always the free wide planks: a saved
	# "floor_style_id" naming anything else (a hand-edited save) is ignored, so
	# it can never make every cell a priced type that refunds when replaced.
	layout.floor_style_id = FloorStyleDef.DEFAULT_ID
	layout.floor_finishes = {}
	var saved: Variant = data.get("floors", [])
	if not saved is Array:
		return
	var limit: int = preview.size.x * preview.size.y
	for value: Variant in (saved as Array).slice(0, limit):
		var row: Array = value if value is Array else []
		if row.size() != 5 or not _integer_in(row[0], -100000, 100000) or not _integer_in(row[1], -100000, 100000):
			continue
		var cell: Vector2i = Vector2i(int(row[0]), int(row[1]))
		if layout.floor_finishes.has(cell) or preview.terrain(cell) != SimGrid.Terrain.FLOOR \
				or not (row[2] is String or row[2] is StringName):
			continue
		var style: FloorStyleDef = content.floor_style(StringName(row[2]))
		if style == null:
			continue
		var swatch: StringName = _floor_colour(row[3], style.default_swatch, content)
		var accent: StringName = _floor_colour(row[4], style.default_accent, content)
		layout.floor_finishes[cell] = PackedStringArray([String(style.id), String(swatch), String(accent)])


## A saved floor colour: empty or a known swatch, else `fallback`.
static func _floor_colour(value: Variant, fallback: StringName, content: ContentDB) -> StringName:
	if not (value is String or value is StringName):
		return fallback
	var id: StringName = StringName(value)
	return id if id.is_empty() or content.swatch(id) != null else fallback


## The layout's floor types onto this shop's floor (forgiving, like decoding).
func _load_floors(layout: ShopLayout) -> void:
	var style_id: StringName = layout.floor_style_id
	if _content == null or style_id != FloorStyleDef.DEFAULT_ID or _content.floor_style(style_id) == null:
		style_id = FloorStyleDef.DEFAULT_ID
	floors = FloorFinishes.new(style_id, floor_swatch_id)
	if _content == null or _sim == null or _sim.world == null:
		return
	var looks: Dictionary[Vector2i, FloorFinishes.Finish] = {}
	for cell: Vector2i in layout.floor_finishes:
		var row: PackedStringArray = layout.floor_finishes[cell]
		if row.size() != 3 or _sim.world.grid.terrain(cell) != SimGrid.Terrain.FLOOR:
			continue
		var style: FloorStyleDef = _content.floor_style(StringName(row[0]))
		if style == null:
			continue
		looks[cell] = FloorFinishes.Finish.new(style.id, _floor_colour(row[1], style.default_swatch, _content),
			_floor_colour(row[2], style.default_accent, _content))
	floors.set_finishes(looks)


## Wall finishes and wall decor (D26) decode as forgivingly as floor types:
## the default is always plain paint (a saved other default is ignored), a
## face that is no longer a wall face, an unknown finish or item and a
## malformed or overlapping row are skipped, and an unknown colour falls back
## to the finish's own. Versions 1 to 5 had none (plain paint, nothing hung).
static func _decode_walls(data: Dictionary, preview: SimGrid, content: ContentDB, layout: ShopLayout) -> void:
	layout.wall_style_id = WallStyleDef.DEFAULT_ID
	layout.wall_finishes = {}
	layout.wall_items = {}
	var limit: int = preview.size.x * preview.size.y * 4
	var saved: Variant = data.get("wall_finishes", [])
	if saved is Array:
		for value: Variant in (saved as Array).slice(0, limit):
			var row: Array = value if value is Array else []
			var face: Vector3i = _saved_face(row, 6)
			if face == WallFaces.NO_FACE or layout.wall_finishes.has(face) or not WallFaces.is_face(preview, face) \
					or not (row[3] is String or row[3] is StringName):
				continue
			var style: WallStyleDef = content.wall_style(StringName(row[3]))
			if style == null:
				continue
			layout.wall_finishes[face] = PackedStringArray([String(style.id),
				String(_floor_colour(row[4], style.default_swatch, content)),
				String(_floor_colour(row[5], style.default_accent, content))])
	var hung: Variant = data.get("wall_items", [])
	if not hung is Array:
		return
	var staged: WallDecor = WallDecor.new()
	for value: Variant in (hung as Array).slice(0, limit):
		var row: Array = value if value is Array else []
		var anchor: Vector3i = _saved_face(row, 4)
		if anchor == WallFaces.NO_FACE or not (row[3] is String or row[3] is StringName):
			continue
		var definition: ItemDef = content.item(StringName(row[3]))
		if definition == null or not staged.problem(preview, definition, anchor).is_empty():
			continue
		staged.add(definition.id, anchor, definition.footprint.x, definition.hangs_in_window())
		layout.wall_items[anchor] = definition.id


## A saved face key [x, y, dir, ...] of `size` values, or NO_FACE.
static func _saved_face(row: Array, size: int) -> Vector3i:
	if row.size() != size or not _integer_in(row[0], -100000, 100000) or not _integer_in(row[1], -100000, 100000) \
			or not _integer_in(row[2], 0, 3):
		return WallFaces.NO_FACE
	return Vector3i(int(row[0]), int(row[1]), int(row[2]))


## The layout's wall finishes and decor onto this shop (forgiving, like decoding).
func _load_walls(layout: ShopLayout) -> void:
	walls = WallFinishes.new(WallStyleDef.DEFAULT_ID, wall_swatch_id)
	decor = WallDecor.new()
	if _content == null or _sim == null or _sim.world == null:
		return
	var grid: SimGrid = _sim.world.grid
	var looks: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	for face: Vector3i in layout.wall_finishes:
		var row: PackedStringArray = layout.wall_finishes[face]
		if row.size() != 3 or not WallFaces.is_face(grid, face):
			continue
		var style: WallStyleDef = _content.wall_style(StringName(row[0]))
		if style == null:
			continue
		looks[face] = FloorFinishes.Finish.new(style.id, _floor_colour(row[1], style.default_swatch, _content),
			_floor_colour(row[2], style.default_accent, _content))
	walls.set_finishes(looks)
	var anchors: Array[Vector3i] = []
	anchors.assign(layout.wall_items.keys())
	WallFaces.sort(anchors)
	for anchor: Vector3i in anchors:
		var definition: ItemDef = _content.item(layout.wall_items[anchor])
		if definition != null and decor.problem(grid, definition, anchor).is_empty():
			decor.add(definition.id, anchor, definition.footprint.x, definition.hangs_in_window())


## Invalid or removed palette entries revert to authored colours on old saves.
static func _saved_swatch(value: Variant, content: ContentDB) -> StringName:
	if not (value is String or value is StringName):
		return &""
	var id: StringName = StringName(value)
	return id if content.swatch(id) != null else &""


# --- Wall segments (FK-070) ----------------------------------------------

## The changes for a dragged run: each edge without a segment gets `kind`.
## Edges that already hold any segment are kept as they are and cost nothing.
func run_changes(edges: Array[Vector3i], kind: SimGrid.Segment) -> Dictionary[Vector3i, int]:
	var changes: Dictionary[Vector3i, int] = {}
	if _sim == null or _sim.world == null:
		return changes
	for edge: Vector3i in edges:
		if _sim.world.grid.segment(edge) == SimGrid.Segment.NONE:
			changes[edge] = kind
	return changes


## What one click on an edge does: interior segments cycle wall -> doorway ->
## window -> wall; an outer face toggles the selected window or back doorway. An empty
## interior edge gets `empty_kind`. Returns NONE for "remove".
func next_segment(edge: Vector3i, empty_kind: SimGrid.Segment) -> SimGrid.Segment:
	if _sim == null or _sim.world == null:
		return SimGrid.Segment.NONE
	var grid: SimGrid = _sim.world.grid
	var current: SimGrid.Segment = grid.segment(edge)
	if WallRules.outer_side(grid, edge) != Vector2i.ZERO:
		# An interior-only partition must refuse here, never become a window.
		if empty_kind == SimGrid.Segment.STALL_PARTITION:
			return empty_kind
		if empty_kind == SimGrid.Segment.DOORWAY:
			return SimGrid.Segment.NONE if current == SimGrid.Segment.DOORWAY else SimGrid.Segment.DOORWAY
		return SimGrid.Segment.NONE if current == SimGrid.Segment.WINDOW else SimGrid.Segment.WINDOW
	match current:
		SimGrid.Segment.NONE:
			return empty_kind
		SimGrid.Segment.WALL:
			return SimGrid.Segment.DOORWAY
		SimGrid.Segment.DOORWAY:
			return SimGrid.Segment.WINDOW
	return SimGrid.Segment.WALL


## Read-only check of a set of segment changes (edge -> new segment, NONE
## removes). Each changed edge is a sale of the old segment at the furniture
## refund rate plus a purchase of the new one.
func check_segments(changes: Dictionary[Vector3i, int], exact: Exact = null) -> EditCheck:
	if not can_edit():
		return EditCheck.new(false, WALLS_CLOSED)
	if _content == null:
		return EditCheck.new(false, "The shop content is unavailable")
	var live: SimGrid = _sim.world.grid
	var effective: Dictionary[Vector3i, int] = {}
	for edge: Vector3i in changes:
		if live.segment(edge) != changes[edge]:
			effective[edge] = changes[edge]
	if effective.is_empty():
		return EditCheck.new(false, "Nothing to change here")
	var cost: int = 0
	var refund: int = 0
	var ids: Dictionary[int, int] = {}
	var preview: SimGrid = _preview_without(-1, ids)
	if preview == null:
		return EditCheck.new(false, "The current shop has invalid placements")
	for edge: Vector3i in _sorted_edges(effective):
		var kind: SimGrid.Segment = effective[edge] as SimGrid.Segment
		var problem: String = WallRules.edge_problem(live, edge, kind)
		if not problem.is_empty():
			return EditCheck.new(false, problem)
		var new_def: WallKindDef = _content.wall_kind_for(kind)
		var old_def: WallKindDef = _content.wall_kind_for(live.segment(edge))
		if kind != SimGrid.Segment.NONE and new_def == null:
			return EditCheck.new(false, "Unknown wall type")
		cost += new_def.price if new_def != null else 0
		refund += floori(old_def.price / 2.0) if old_def != null else 0
	preview.set_segments(effective)
	# A new frame must be part of a wall. Existing frames whose last wall
	# support this edit removes come down too, with their normal sale refund.
	for edge: Vector3i in effective:
		if effective[edge] in [SimGrid.Segment.WINDOW, SimGrid.Segment.DOORWAY] \
				and not WallRules.has_continuing_wall(preview, edge):
			return EditCheck.new(false, WallRules.OPENING_NEEDS_WALL)
	for edge: Vector3i in WallRules.orphan_openings(preview):
		effective[edge] = SimGrid.Segment.NONE
		var old_def: WallKindDef = _content.wall_kind_for(live.segment(edge))
		refund += floori(old_def.price / 2.0) if old_def != null else 0
	preview.set_segments(effective)
	if exact != null:
		cost = maxi(-exact.amount, 0)
		refund = maxi(exact.amount, 0)
	preview.set_segments(effective)
	var menu_check: EditCheck = EditCheck.new(true)
	_note_menu_access(menu_check, preview, exact != null)
	# D25: one back door per shop (undo/redo restores accepted layouts as they were).
	var problem: String = WallRules.back_door_problem(live, preview) if exact == null else ""
	if problem.is_empty():
		problem = WallRules.closed_door_problem(live, preview)
	if problem.is_empty():
		problem = WallRules.layout_problem(preview)
	if problem.is_empty() and exact == null:
		var dining: EditCheck = EditCheck.validate_dining(live, preview, ids, -1, -1)
		problem = "" if dining.ok else dining.why
	if problem.is_empty():
		problem = WallRules.cut_off_problem(live, preview, _people_cells(), exact != null)
	if problem.is_empty() and exact == null:
		problem = RoomRules.problem(live, preview, ids)
	if not problem.is_empty():
		menu_check.ok = false
		menu_check.why = problem
		return menu_check
	if not menu_check.ok:
		return menu_check
	var check: EditCheck = EditCheck.new(true)
	# D26: finishes and decor on walls that go come down too, refunded at half.
	var lost: int = _note_wall_losses(preview, check)
	if exact == null:
		refund += lost
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	if cost > refund and not _books.can_spend_without_loan(cost - refund):
		return EditCheck.new(false, _books.purchase_refusal_reason(cost - refund))
	check.cost = cost
	check.refund = refund
	check.changes = effective
	_fill_warnings(check, preview, ids)
	check.menu_losses = menu_check.menu_losses
	check.menu_warning = menu_check.menu_warning
	return check


## Applies a checked change; books record the refund, then the purchase.
func apply_segments(changes: Dictionary[Vector3i, int], exact: Exact = null) -> bool:
	var check: EditCheck = check_segments(changes, exact)
	last_check = check
	if not check.ok:
		return false
	_applying = true
	# One batch: observers (view, agents, vibe) see a dragged run as one change.
	_sim.world.grid.set_segments(check.changes)
	_drop_wall_losses(check)
	_record(check.refund, check.cost, exact)
	_applying = false
	return true


# --- Rooms (FK-101) -------------------------------------------------------------

## Painting `kind` onto `cells`: the floor cells whose room would change.
func room_changes(cells: Array[Vector2i], kind: int) -> Dictionary[Vector2i, int]:
	var changes: Dictionary[Vector2i, int] = {}
	if _sim == null or _sim.world == null:
		return changes
	for cell: Vector2i in cells:
		if _sim.world.grid.terrain(cell) == SimGrid.Terrain.FLOOR:
			changes[cell] = kind
	return changes


## Read-only check of painting rooms (cell -> Room). Free, morning or closed
## only. Undo and redo (`exact`) restore rooms the shop already had, so only
## the phase is checked then (FK-085 accepted-layout rule).
func check_rooms(changes: Dictionary[Vector2i, int], exact: Exact = null) -> EditCheck:
	if not can_edit():
		return EditCheck.new(false, RoomRules.ROOMS_CLOSED)
	var live: SimGrid = _sim.world.grid
	var effective: Dictionary[Vector2i, int] = {}
	var floor_seen: bool = false
	for cell: Vector2i in changes:
		var kind: int = changes[cell]
		if kind < SimGrid.Room.DINING or kind > SimGrid.Room.STORAGE:
			return EditCheck.new(false, "Unknown room")
		if live.terrain(cell) != SimGrid.Terrain.FLOOR:
			continue
		floor_seen = true
		if live.room(cell) != kind:
			effective[cell] = kind
	if effective.is_empty():
		# Undo/redo of a paint that is already in place has nothing to do.
		if exact != null and floor_seen:
			return EditCheck.new(true)
		return EditCheck.new(false, RoomRules.ALREADY if floor_seen else RoomRules.NOT_FLOOR)
	var ids: Dictionary[int, int] = {}
	var preview: SimGrid = _preview_without(-1, ids)
	if preview == null:
		return EditCheck.new(false, "The current shop has invalid placements")
	preview.set_rooms(effective)
	if exact == null:
		var problem: String = RoomRules.problem(live, preview, ids)
		if not problem.is_empty():
			return EditCheck.new(false, problem)
	var check: EditCheck = EditCheck.new(true)
	check.rooms = effective
	_fill_warnings(check, preview, ids)
	return check


## Paints checked rooms. Free: no ledger line.
func apply_rooms(changes: Dictionary[Vector2i, int], exact: Exact = null) -> bool:
	var check: EditCheck = check_rooms(changes, exact)
	last_check = check
	if not check.ok:
		return false
	_applying = true
	var painted: bool = _sim.world.grid.set_rooms(check.rooms)
	_applying = false
	last_cash_change = 0
	if not painted:
		last_check = EditCheck.new(false, "The shop changed; check the rooms again")
	return painted


## Every painted room of the live shop (cell -> Room), for undo history.
func rooms() -> Dictionary[Vector2i, int]:
	if _sim == null or _sim.world == null:
		return {}
	return _sim.world.grid.rooms()


# --- Floor types (D25) ---------------------------------------------------------

## Laying `style_id` in these colours on `cells`: the floor cells it covers.
func lay_changes(cells: Array[Vector2i], style_id: StringName, swatch_id: StringName,
		accent_id: StringName = &"") -> Dictionary[Vector2i, FloorFinishes.Finish]:
	var changes: Dictionary[Vector2i, FloorFinishes.Finish] = {}
	if _sim == null or _sim.world == null:
		return changes
	for cell: Vector2i in cells:
		if _sim.world.grid.terrain(cell) == SimGrid.Terrain.FLOOR:
			changes[cell] = FloorFinishes.Finish.new(style_id, swatch_id, accent_id)
	return changes


## Recolouring `cells` with `swatch_id`: each floor cell keeps its floor type
## and accent and takes the new main colour.
func recolour_changes(cells: Array[Vector2i], swatch_id: StringName) -> Dictionary[Vector2i, FloorFinishes.Finish]:
	var changes: Dictionary[Vector2i, FloorFinishes.Finish] = {}
	if _sim == null or _sim.world == null:
		return changes
	for cell: Vector2i in cells:
		if _sim.world.grid.terrain(cell) == SimGrid.Terrain.FLOOR:
			changes[cell] = floors.finish(cell).recoloured(swatch_id)
	return changes


## Player words for a floor type ("Checker tiles"), or "floor" when unknown.
func floor_style_name(style_id: StringName) -> String:
	var style: FloorStyleDef = _content.floor_style(style_id) if _content != null else null
	return style.display_name if style != null else "floor"


## The room's floor around `cell` (Shift: fill the room), row-major.
func floor_room_cells(cell: Vector2i) -> Array[Vector2i]:
	return FloorFinishes.room_cells(_sim.world.grid, cell) if _sim != null and _sim.world != null else []


## The connected floor that looks like `cell` (a paint click), row-major.
func floor_area_cells(cell: Vector2i) -> Array[Vector2i]:
	return floors.area_cells(_sim.world.grid, cell) if _sim != null and _sim.world != null else []


## Read-only check of new floor looks (cell -> Finish). A change of floor type
## costs the new type's price per tile and refunds half the old type's price,
## and only in the morning or after closing; a recolour (same floor type) is
## free at any time. Undo and redo (`exact`) move exact money and restore
## floor types already laid, so the unlock level is not checked then.
func check_flooring(changes: Dictionary[Vector2i, FloorFinishes.Finish], exact: Exact = null) -> EditCheck:
	if _sim == null or _sim.world == null or _content == null:
		return EditCheck.new(false, "The shop is unavailable")
	var live: SimGrid = _sim.world.grid
	var effective: Dictionary[Vector2i, FloorFinishes.Finish] = {}
	var floor_seen: bool = false
	var relaid: bool = false
	var cost: int = 0
	var refund: int = 0
	var locked: String = ""
	for cell: Vector2i in changes:
		var next: FloorFinishes.Finish = changes[cell]
		var style: FloorStyleDef = _content.floor_style(next.style) if next != null else null
		if style == null:
			return EditCheck.new(false, "Unknown floor type")
		for colour: StringName in [next.swatch, next.accent]:
			if not colour.is_empty() and _content.swatch(colour) == null:
				return EditCheck.new(false, "Unknown colour")
		if live.terrain(cell) != SimGrid.Terrain.FLOOR:
			continue
		floor_seen = true
		var current: FloorFinishes.Finish = floors.finish(cell)
		if current.same(next):
			continue
		effective[cell] = next
		if current.style == next.style:
			continue
		relaid = true
		cost += style.price
		var old: FloorStyleDef = _content.floor_style(current.style)
		refund += floori(old.price / 2.0) if old != null else 0
		if locked.is_empty() and not style.unlocked(_owner_level):
			locked = style.locked_reason(_owner_level)
	if effective.is_empty():
		# Undo/redo of looks that are already in place has nothing to do.
		if exact != null and floor_seen:
			return EditCheck.new(true)
		return EditCheck.new(false, FLOORS_ALREADY if floor_seen else FLOORS_NOT_FLOOR)
	if relaid and not can_edit():
		return EditCheck.new(false, FLOORS_CLOSED)
	if exact == null and not locked.is_empty():
		return EditCheck.new(false, locked)
	if exact != null:
		cost = maxi(-exact.amount, 0)
		refund = maxi(exact.amount, 0)
	if cost > 0 or refund > 0:
		if _books == null or not _books.is_ready():
			return EditCheck.new(false, "The shop books are unavailable")
		if cost > refund and not _books.can_spend_without_loan(cost - refund):
			return EditCheck.new(false, _books.purchase_refusal_reason(cost - refund))
	var check: EditCheck = EditCheck.new(true)
	check.cost = cost
	check.refund = refund
	check.finishes = effective
	return check


## Lays or recolours checked floor looks; books record the refund, then the cost.
func apply_flooring(changes: Dictionary[Vector2i, FloorFinishes.Finish], exact: Exact = null) -> bool:
	var check: EditCheck = check_flooring(changes, exact)
	last_check = check
	if not check.ok:
		return false
	last_cash_change = 0
	if check.finishes.is_empty():
		return true
	floors.set_finishes(check.finishes)
	if check.cost > 0 or check.refund > 0 or (exact != null and exact.amount != 0):
		_record(check.refund, check.cost, exact)
	return true


## The floor colour guests see most (D25): the main colour of most guest-room
## floor cells (ties go to the first colour id), for the vibe's floor paint.
## A shop with one floor colour gives exactly its whole-floor paint, as before.
func floor_vibe_swatch() -> StringName:
	if _sim == null or _sim.world == null:
		return floor_swatch_id
	var grid: SimGrid = _sim.world.grid
	var gated: bool = not grid.entries().is_empty()
	var guests: Dictionary[Vector2i, bool] = RoomRules.guest_floor(grid) if gated else {}
	var counts: Dictionary[StringName, int] = {}
	for cell: Vector2i in grid.cells():
		if grid.terrain(cell) != SimGrid.Terrain.FLOOR or (gated and not guests.has(cell)):
			continue
		var swatch: StringName = floors.finish(cell).swatch
		counts[swatch] = int(counts.get(swatch, 0)) + 1
	var best: StringName = floor_swatch_id
	var most: int = 0
	for swatch: StringName in counts:
		if counts[swatch] > most or (counts[swatch] == most and String(swatch) < String(best)):
			best = swatch
			most = counts[swatch]
	return best


# --- Wall finishes (D26) -------------------------------------------------------

## Putting `style_id` up in these colours on `faces`: the wall faces it covers.
func wall_lay_changes(faces: Array[Vector3i], style_id: StringName, swatch_id: StringName,
		accent_id: StringName = &"") -> Dictionary[Vector3i, FloorFinishes.Finish]:
	var changes: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	if _sim == null or _sim.world == null:
		return changes
	for face: Vector3i in faces:
		if WallFaces.is_face(_sim.world.grid, face):
			changes[face] = FloorFinishes.Finish.new(style_id, swatch_id, accent_id)
	return changes


## Recolouring `faces` with `swatch_id`: each keeps its finish and accent.
func wall_recolour_changes(faces: Array[Vector3i], swatch_id: StringName) -> Dictionary[Vector3i, FloorFinishes.Finish]:
	var changes: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	if _sim == null or _sim.world == null:
		return changes
	for face: Vector3i in faces:
		if WallFaces.is_face(_sim.world.grid, face):
			changes[face] = walls.finish(face).recoloured(swatch_id)
	return changes


## Player words for a wall finish ("Brick"), or "wall finish" when unknown.
func wall_style_name(style_id: StringName) -> String:
	var style: WallStyleDef = _content.wall_style(style_id) if _content != null else null
	return style.display_name if style != null else "wall finish"


## Every wall face of the room `face` looks into (Shift), sorted.
func wall_room_faces(face: Vector3i) -> Array[Vector3i]:
	return WallFaces.room_faces(_sim.world.grid, face) if _sim != null and _sim.world != null else []


## The connected run of walls that look like `face` (a paint click), sorted.
func wall_area_faces(face: Vector3i) -> Array[Vector3i]:
	return walls.area_faces(_sim.world.grid, face) if _sim != null and _sim.world != null else []


## The wall faces of these floor cells (a dragged rectangle), sorted.
func wall_faces_of(cells: Array[Vector2i]) -> Array[Vector3i]:
	return WallFaces.of_cells(_sim.world.grid, cells) if _sim != null and _sim.world != null else []


## Read-only check of new wall looks (face -> Finish), like check_flooring: a
## change of finish costs the new finish's price per face and refunds half
## the old one's, only in the morning or after closing; a recolour (same
## finish) is free at any time. Undo and redo (`exact`) move exact money and
## skip the unlock level.
func check_wall_finishes(changes: Dictionary[Vector3i, FloorFinishes.Finish], exact: Exact = null) -> EditCheck:
	if _sim == null or _sim.world == null or _content == null:
		return EditCheck.new(false, "The shop is unavailable")
	var live: SimGrid = _sim.world.grid
	var effective: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	var face_seen: bool = false
	var relaid: bool = false
	var cost: int = 0
	var refund: int = 0
	var locked: String = ""
	for face: Vector3i in changes:
		var next: FloorFinishes.Finish = changes[face]
		var style: WallStyleDef = _content.wall_style(next.style) if next != null else null
		if style == null:
			return EditCheck.new(false, "Unknown wall finish")
		for colour: StringName in [next.swatch, next.accent]:
			if not colour.is_empty() and _content.swatch(colour) == null:
				return EditCheck.new(false, "Unknown colour")
		if not WallFaces.is_face(live, face):
			continue
		face_seen = true
		var current: FloorFinishes.Finish = walls.finish(face)
		if current.same(next):
			continue
		effective[face] = next
		if current.style == next.style:
			continue
		relaid = true
		cost += style.price
		var old: WallStyleDef = _content.wall_style(current.style)
		refund += floori(old.price / 2.0) if old != null else 0
		if locked.is_empty() and not style.unlocked(_owner_level):
			locked = style.locked_reason(_owner_level)
	if effective.is_empty():
		if exact != null and face_seen:
			return EditCheck.new(true)
		return EditCheck.new(false, WALL_FINISH_ALREADY if face_seen else WALL_FINISH_NOT_WALL)
	if relaid and not can_edit():
		return EditCheck.new(false, WALL_FINISH_CLOSED)
	if exact == null and not locked.is_empty():
		return EditCheck.new(false, locked)
	if exact != null:
		cost = maxi(-exact.amount, 0)
		refund = maxi(exact.amount, 0)
	if cost > 0 or refund > 0:
		if _books == null or not _books.is_ready():
			return EditCheck.new(false, "The shop books are unavailable")
		if cost > refund and not _books.can_spend_without_loan(cost - refund):
			return EditCheck.new(false, _books.purchase_refusal_reason(cost - refund))
	var check: EditCheck = EditCheck.new(true)
	check.cost = cost
	check.refund = refund
	check.wall_finishes = effective
	return check


## Puts up or recolours checked wall looks; books record the refund, then the cost.
func apply_wall_finishes(changes: Dictionary[Vector3i, FloorFinishes.Finish], exact: Exact = null) -> bool:
	var check: EditCheck = check_wall_finishes(changes, exact)
	last_check = check
	if not check.ok:
		return false
	last_cash_change = 0
	if check.wall_finishes.is_empty():
		return true
	walls.set_finishes(check.wall_finishes)
	if check.cost > 0 or check.refund > 0 or (exact != null and exact.amount != 0):
		_record(check.refund, check.cost, exact)
	return true


## The wall colour guests see most (D26): the main colour of most wall faces
## of the guest rooms (ties go to the first colour id), for the vibe's wall
## paint. A shop with one wall colour gives exactly its whole-shop paint.
func wall_vibe_swatch() -> StringName:
	if _sim == null or _sim.world == null:
		return wall_swatch_id
	var grid: SimGrid = _sim.world.grid
	var guests: Dictionary[Vector2i, bool] = _guest_cells(grid)
	var counts: Dictionary[StringName, int] = {}
	for face: Vector3i in WallFaces.all(grid):
		if guests.is_empty() or guests.has(WallFaces.cell(face)):
			var swatch: StringName = walls.finish(face).swatch
			counts[swatch] = int(counts.get(swatch, 0)) + 1
	var best: StringName = wall_swatch_id
	var most: int = 0
	for swatch: StringName in counts:
		if counts[swatch] > most or (counts[swatch] == most and String(swatch) < String(best)):
			best = swatch
			most = counts[swatch]
	return best


## The guest-room floor (RoomRules.guest_floor); empty on a grid without a
## street entry (a test grid), where everything counts.
static func _guest_cells(grid: SimGrid) -> Dictionary[Vector2i, bool]:
	if grid.entries().is_empty():
		return {}
	var guests: Dictionary[Vector2i, bool] = RoomRules.guest_floor(grid)
	if guests.is_empty():
		guests[SimGrid.NO_CELL] = true
	return guests


# --- Wall decor (D26) ------------------------------------------------------------

## The hung item's definition at `anchor`, or null.
func hung_definition(anchor: Vector3i) -> ItemDef:
	var hung: WallDecor.Hung = decor.item(anchor)
	return _content.item(hung.def_id) if hung != null and _content != null else null


## Read-only check of hanging a new `def_id` from `anchor` (its leftmost face).
func check_hang(def_id: StringName, anchor: Vector3i, exact: Exact = null) -> EditCheck:
	if not can_edit():
		return EditCheck.new(false, DECOR_CLOSED)
	if _content == null:
		return EditCheck.new(false, "The shop content is unavailable")
	var definition: ItemDef = _content.item(def_id)
	if definition == null or not definition.hangs_on_wall() or not _valid_definition(definition):
		return EditCheck.new(false, WallDecor.NOT_WALL_DECOR)
	if exact == null and definition.unlock_level > _owner_level:
		return EditCheck.new(false, "Unlocks at level %d" % definition.unlock_level)
	var why: String = decor.problem(_sim.world.grid, definition, anchor)
	if not why.is_empty():
		return EditCheck.new(false, why)
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	var charge: int = definition.price if exact == null else -exact.amount
	if (exact == null or charge > 0) and not _books.can_spend_without_loan(charge):
		return EditCheck.new(false, _books.purchase_refusal_reason(charge))
	var check: EditCheck = EditCheck.new(true)
	check.cost = maxi(charge, 0)
	return check


## Hangs a checked item; one ledger line like furniture (undo/redo: `exact`).
func hang(def_id: StringName, anchor: Vector3i, exact: Exact = null) -> bool:
	var check: EditCheck = check_hang(def_id, anchor, exact)
	last_check = check
	if not check.ok:
		return false
	var definition: ItemDef = _content.item(def_id)
	_applying = true
	var added: bool = decor.add(definition.id, anchor, definition.footprint.x, definition.hangs_in_window())
	if added:
		last_anchor = anchor
		_record_decor(-definition.price if exact == null else exact.amount, exact)
	_applying = false
	if not added:
		last_check = EditCheck.new(false, WallDecor.OCCUPIED)
	return added


## Read-only check of moving the item at `anchor` so it hangs from `to_anchor`.
func check_rehang(anchor: Vector3i, to_anchor: Vector3i, _exact: Exact = null) -> EditCheck:
	if not can_edit():
		return EditCheck.new(false, DECOR_CLOSED)
	var definition: ItemDef = hung_definition(anchor)
	if definition == null:
		return EditCheck.new(false, DECOR_GONE)
	var why: String = decor.problem(_sim.world.grid, definition, to_anchor, anchor)
	return EditCheck.new(why.is_empty(), why)


## Moves a hung item (free, no ledger line).
func rehang(anchor: Vector3i, to_anchor: Vector3i, exact: Exact = null) -> bool:
	var check: EditCheck = check_rehang(anchor, to_anchor, exact)
	last_check = check
	if not check.ok:
		return false
	if anchor == to_anchor:
		last_anchor = anchor
		last_cash_change = 0
		return true
	var hung: WallDecor.Hung = decor.item(anchor)
	_applying = true
	decor.remove(anchor)
	var added: bool = decor.add(hung.def_id, to_anchor, hung.width, hung.window)
	if not added:
		decor.add(hung.def_id, anchor, hung.width, hung.window)
	_applying = false
	last_anchor = to_anchor if added else anchor
	last_cash_change = 0
	if not added:
		last_check = EditCheck.new(false, WallDecor.OCCUPIED)
	return added


func check_take_down(anchor: Vector3i, exact: Exact = null) -> EditCheck:
	if not can_edit():
		return EditCheck.new(false, DECOR_CLOSED)
	var definition: ItemDef = hung_definition(anchor)
	if definition == null:
		return EditCheck.new(false, DECOR_GONE)
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	var refund: int = sale_refund(definition) if exact == null else exact.amount
	if refund < 0 and not _books.can_spend_without_loan(-refund):
		return EditCheck.new(false, _books.purchase_refusal_reason(-refund))
	var check: EditCheck = EditCheck.new(true)
	check.refund = maxi(refund, 0)
	return check


## Sells the item at `anchor`: half its price (undo/redo: `exact`). -1 refuses.
func take_down(anchor: Vector3i, exact: Exact = null) -> int:
	var check: EditCheck = check_take_down(anchor, exact)
	last_check = check
	if not check.ok:
		return -1
	var refund: int = sale_refund(hung_definition(anchor)) if exact == null else exact.amount
	_applying = true
	decor.remove(anchor)
	_record_decor(refund, exact)
	_applying = false
	return refund


## Hung decor guests can see (D26), as definitions: items on the wall faces of
## the guest rooms, for the vibe (decor charm and themes, like floor decor).
func decor_vibe_items() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	if _sim == null or _sim.world == null or _content == null:
		return out
	var guests: Dictionary[Vector2i, bool] = _guest_cells(_sim.world.grid)
	for anchor: Vector3i in decor.anchors():
		var definition: ItemDef = hung_definition(anchor)
		if definition == null:
			continue
		var seen: bool = guests.is_empty()
		for face: Vector3i in decor.item(anchor).faces():
			if guests.has(WallFaces.cell(face)):
				seen = true
		if seen:
			out.append(definition)
	return out


## Furniture books one line even at a zero price; undo/redo only when money moves.
func _record_decor(amount: int, exact: Exact) -> void:
	if exact == null or amount != 0:
		_books.add_cash(amount, Ledger.UPGRADES, exact.note if exact != null else "")
	last_cash_change = amount


# --- Floor expansion (FK-080) ------------------------------------------------

## The lot and floor plan, or null when this shop has no layout.
func footprint() -> ShopFootprint:
	return _footprint


## Bought floor cells, row-major.
func bought_floor() -> Array[Vector2i]:
	return ShopFootprint.sorted(_bought)


func is_bought(cell: Vector2i) -> bool:
	return _bought.has(cell)


## Read-only check of buying (`adding`) or removing the floor in `cells`.
## Adding uses every unbuilt lot cell; cells of the starting building, already
## bought or on the lot's wall ring are skipped, any cell beyond the lot refuses. Removing uses
## only bought cells. Wall segments that would no longer fit are taken down
## and refunded at the furniture rate; floor refunds half its price too, and
## half the price of its floor type (D25), as do the wall finishes and hung
## decor on walls that go (D26).
##
## Undo (FK-085) passes `restore`: segments (edge -> segment) the edit being
## undone took down, put back in the same change, and exact money.
func check_floor(cells: Array[Vector2i], adding: bool, exact: Exact = null,
		restore: Dictionary[Vector3i, int] = {}) -> EditCheck:
	if not can_edit():
		return EditCheck.new(false, ShopFootprint.FLOOR_CLOSED)
	if _footprint == null or not _footprint.has_lot():
		return EditCheck.new(false, ShopFootprint.NO_LOT)
	if _content == null:
		return EditCheck.new(false, "The shop content is unavailable")
	var effective: Dictionary[Vector2i, bool] = {}
	var on_ring: bool = false
	for cell: Vector2i in cells:
		if adding:
			if _footprint.building.has_point(cell) or _bought.has(cell):
				continue
			if not _footprint.lot.has_point(cell):
				return EditCheck.new(false, ShopFootprint.OUTSIDE_LOT)
			if _footprint.can_hold(cell):
				effective[cell] = true
			else:
				on_ring = true
		elif _bought.has(cell):
			effective[cell] = true
	if effective.is_empty():
		if adding and on_ring:
			return EditCheck.new(false, ShopFootprint.OUTSIDE_LOT)
		return EditCheck.new(false, ShopFootprint.ALREADY_BUILT if adding else ShopFootprint.ONLY_BOUGHT)
	var next: Dictionary[Vector2i, bool] = _bought.duplicate()
	for cell: Vector2i in effective:
		if adding:
			next[cell] = true
		else:
			next.erase(cell)
	var problem: String = _footprint.problem(next, adding)
	if not problem.is_empty():
		return EditCheck.new(false, problem)
	var live: SimGrid = _sim.world.grid
	var target: Dictionary[Vector2i, int] = _footprint.terrain_for(next)
	# Anything that needs a floor cell that would stop being floor: furniture
	# standing on it first, then a seat or work spot beside furniture.
	var losing: Array[Vector2i] = []
	for cell: Vector2i in target:
		if target[cell] != SimGrid.Terrain.FLOOR and live.terrain(cell) == SimGrid.Terrain.FLOOR:
			if not live.items_at(cell).is_empty():
				return EditCheck.new(false, ShopFootprint.HAS_FURNITURE)
			losing.append(cell)
	var ids: Dictionary[int, int] = {}
	var preview: SimGrid = _preview_without(-1, ids)
	if preview == null:
		return EditCheck.new(false, "The current shop has invalid placements")
	if not _footprint.apply(preview, next):
		return EditCheck.new(false, ShopFootprint.HAS_FURNITURE)
	var refund: int = 0
	var removals: Dictionary[Vector3i, int] = {}
	for edge: Vector3i in preview.segment_edges():
		var kind: SimGrid.Segment = preview.segment(edge)
		if WallRules.edge_problem(preview, edge, kind).is_empty():
			continue
		removals[edge] = SimGrid.Segment.NONE
		var old_def: WallKindDef = _content.wall_kind_for(kind)
		refund += floori(old_def.price / 2.0) if old_def != null else 0
	preview.set_segments(removals)
	# The back-wall rule: an opened shell cell beside the kitchen is kitchen.
	var kitchen: Dictionary[Vector2i, int] = RoomRules.opened_kitchen(live, preview, _footprint.building)
	preview.set_rooms(kitchen)
	for edge: Vector3i in _sorted_edges(restore):
		var restored: String = WallRules.edge_problem(preview, edge, restore[edge] as SimGrid.Segment)
		if not restored.is_empty():
			return EditCheck.new(false, restored)
		preview.set_segment(edge, restore[edge] as SimGrid.Segment)
		removals[edge] = restore[edge]
	# Judge support on the complete proposal, including walls restored by an
	# undo. An existing opening may rely on one of those restored wall edges.
	for edge: Vector3i in WallRules.orphan_openings(preview):
		removals[edge] = SimGrid.Segment.NONE
		var old_def: WallKindDef = _content.wall_kind_for(preview.segment(edge))
		refund += floori(old_def.price / 2.0) if old_def != null else 0
	preview.set_segments(removals)
	var menu_check: EditCheck = EditCheck.new(true)
	_note_menu_access(menu_check, preview, exact != null)
	for cell: Vector2i in losing:
		var lost: String = _lost_spot(live, cell) if exact == null else ""
		if not lost.is_empty():
			menu_check.ok = false
			menu_check.why = lost
			return menu_check
	# New floor must be walkable from the street through the walls as built:
	# an outer window that turned interior can seal a pocket.
	# Removing must not seal bought floor that people can walk to now.
	var reach: Dictionary[Vector2i, bool] = WallRules.reachable(WallRules.walls_only(preview))
	if exact != null:
		pass  # A restored floor plan was already accepted as joined.
	elif adding:
		for cell: Vector2i in target:
			if target[cell] == SimGrid.Terrain.FLOOR and live.terrain(cell) != SimGrid.Terrain.FLOOR \
					and not reach.has(cell):
				return EditCheck.new(false, ShopFootprint.NOT_JOINED)
	else:
		var was: Dictionary[Vector2i, bool] = WallRules.reachable(WallRules.walls_only(live))
		for cell: Vector2i in next:
			if was.has(cell) and not reach.has(cell):
				return EditCheck.new(false, ShopFootprint.SPLITS)
	# Selling floor can turn an interior doorway back into a back door (D25: one).
	problem = WallRules.back_door_problem(live, preview) if exact == null else ""
	if problem.is_empty():
		problem = WallRules.layout_problem(preview)
	if problem.is_empty() and exact == null:
		var dining: EditCheck = EditCheck.validate_dining(live, preview, ids, -1, -1)
		problem = "" if dining.ok else dining.why
	if problem.is_empty():
		problem = WallRules.cut_off_problem(live, preview, _people_cells(), exact != null)
	if problem.is_empty() and exact == null:
		problem = RoomRules.problem(live, preview, ids)
	if not problem.is_empty():
		menu_check.ok = false
		menu_check.why = problem
		return menu_check
	if not menu_check.ok:
		return menu_check
	var check: EditCheck = EditCheck.new(true)
	# D26: finishes and decor on walls that go come down too, refunded at half.
	refund += _note_wall_losses(preview, check)
	var cost: int = effective.size() * _footprint.cell_price if adding else 0
	if not adding:
		refund += effective.size() * floori(_footprint.cell_price / 2.0)
	# Floor that goes takes its look up too, refunded at half the type's price.
	for cell: Vector2i in losing:
		if floors.is_default(cell):
			continue
		var laid: FloorStyleDef = _content.floor_style(floors.finish(cell).style)
		check.floor_finish_refund += floori(laid.price / 2.0) if laid != null else 0
	refund += check.floor_finish_refund
	if exact != null:
		cost = maxi(-exact.amount, 0)
		refund = maxi(exact.amount, 0)
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	if cost > refund and not _books.can_spend_without_loan(cost - refund):
		return EditCheck.new(false, _books.purchase_refusal_reason(cost - refund))
	check.cost = cost
	check.refund = refund
	check.changes = removals
	check.floor_cells = ShopFootprint.sorted(effective)
	check.floor_adding = adding
	check.rooms = kitchen
	_fill_warnings(check, preview, ids)
	check.menu_losses = menu_check.menu_losses
	check.menu_warning = menu_check.menu_warning
	return check


## Applies a checked floor change: segments that no longer fit come down, the
## grid grows if needed and the floor plan is set with one cells_changed.
func apply_floor(cells: Array[Vector2i], adding: bool, exact: Exact = null,
		restore: Dictionary[Vector3i, int] = {}) -> bool:
	var check: EditCheck = check_floor(cells, adding, exact, restore)
	last_check = check
	if not check.ok:
		return false
	var next: Dictionary[Vector2i, bool] = _bought.duplicate()
	for cell: Vector2i in check.floor_cells:
		if adding:
			next[cell] = true
		else:
			next.erase(cell)
	var grid: SimGrid = _sim.world.grid
	_applying = true
	# Terrain first: if it is refused nothing has changed (segments included).
	var applied: bool = _footprint.apply(grid, next)
	if applied:
		if not check.changes.is_empty():
			grid.set_segments(check.changes)
		if not check.rooms.is_empty():
			grid.set_rooms(check.rooms)
		_bought = next
		# Floor that was taken away forgets its look; new floor is the default.
		var gone: Array[Vector2i] = []
		for cell: Vector2i in floors.cells():
			if grid.terrain(cell) != SimGrid.Terrain.FLOOR:
				gone.append(cell)
		floors.drop(gone)
		_drop_wall_losses(check)
		if _sim.cleanliness != null:
			for spot: Vector2i in _sim.cleanliness.spots() + _sim.cleanliness.restroom_spots():
				if grid.terrain(spot) != SimGrid.Terrain.FLOOR:
					_sim.cleanliness.clear_spot(spot)
		_record(check.refund, check.cost, exact)
	_applying = false
	if not applied:
		last_check = EditCheck.new(false, "The shop changed; check the floor again")
	return applied


## Finished faces and hung decor that the edited shop (`preview`) would no
## longer have (D26), noted in `check`; returns their refund: half the
## finish's price per face and the sale refund of each item.
func _note_wall_losses(preview: SimGrid, check: EditCheck) -> int:
	var refund: int = 0
	if _content == null:
		return refund
	for face: Vector3i in walls.faces():
		if not WallFaces.is_face(preview, face):
			check.lost_finishes.append(face)
			var style: WallStyleDef = _content.wall_style(walls.finish(face).style)
			refund += floori(style.price / 2.0) if style != null else 0
	for anchor: Vector3i in decor.lost_on(preview):
		check.lost_decor.append(anchor)
		refund += sale_refund(_content.item(decor.item(anchor).def_id))
	return refund


## Takes down what a checked wall or floor edit left without a wall.
func _drop_wall_losses(check: EditCheck) -> void:
	if not check.lost_finishes.is_empty():
		walls.drop(check.lost_finishes)
	for anchor: Vector3i in check.lost_decor:
		decor.remove(anchor)


## What selling a piece of furniture refunds: half its price, rounded down.
@warning_ignore("integer_division")
static func sale_refund(definition: ItemDef) -> int:
	return definition.price / 2 if definition != null else 0


## Books a successful edit: list-price edits record the refund, then the cost
## (unchanged since FK-031); exact edits record one noted line.
func _record(refund: int, cost: int, exact: Exact) -> void:
	if exact != null:
		if exact.amount != 0:
			_books.add_cash(exact.amount, Ledger.UPGRADES, exact.note)
		last_cash_change = exact.amount
		return
	if refund > 0:
		_books.add_cash(refund, Ledger.UPGRADES)
	if cost > 0:
		_books.add_cash(-cost, Ledger.UPGRADES)
	last_cash_change = refund - cost


## Furniture books one line even at a zero price (unchanged since FK-031).
func _record_item(amount: int, exact: Exact) -> void:
	_books.add_cash(amount, Ledger.UPGRADES, exact.note if exact != null else "")
	last_cash_change = amount


## Every wall segment of the live shop (edge -> segment), for undo history.
func segments() -> Dictionary[Vector3i, int]:
	var out: Dictionary[Vector3i, int] = {}
	if _sim != null and _sim.world != null:
		for edge: Vector3i in _sim.world.grid.segment_edges():
			out[edge] = _sim.world.grid.segment(edge)
	return out


## The sentence for a work spot or seat that would lose its floor cell, or "".
static func _lost_spot(grid: SimGrid, cell: Vector2i) -> String:
	if WallRules.door_cells(grid).has(cell):
		return WallRules.CUT_DOOR
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null:
			continue
		if placed.seat_cells.has(cell):
			return WallRules.CUT_SEAT
		if placed.work_cells.has(cell):
			return WallRules.CUT_SINK if definition.station_type == &"sink" else WallRules.CUT_STATION
	return ""


## Staff start (post) cells, where everyone stands each morning, may never be
## shut in. In the morning staff are about to work from where they stand, so
## their current cells count too; after closing they will be reset to posts.
func _people_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if _sim.world.clock.phase == SimClock.Phase.MORNING:
		for agent: SimAgent in _sim.world.agents:
			if not agent is CustomerAgent:
				cells.append(agent.cell)
	for role: StringName in _sim.staff_spawns:
		cells.append(_sim.staff_spawns[role])
	return cells


static func _sorted_edges(changes: Dictionary[Vector3i, int]) -> Array[Vector3i]:
	var edges: Array[Vector3i] = []
	edges.assign(changes.keys())
	edges.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.z < b.z or (a.z == b.z and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	return edges


func _edit_check() -> EditCheck:
	if not can_edit():
		return EditCheck.new(false, "Furniture can only be edited in the morning or after closing")
	if _content == null:
		return EditCheck.new(false, "The shop content is unavailable")
	return EditCheck.new(true)


func _check_placement(definition: ItemDef, origin: Vector2i, turns: int, exclude_id: int, result_id: int,
		restoring: bool = false) -> EditCheck:
	var ids: Dictionary[int, int] = {}
	var preview: SimGrid = _preview_without(exclude_id, ids)
	if preview == null:
		return EditCheck.new(false, "The current shop has invalid placements")
	var result: SimGrid.PlaceResult = preview.can_place_def(definition, origin, turns)
	if result != SimGrid.PlaceResult.OK:
		return EditCheck.new(false, placement_reason(result))
	var proposed_id: int = -1
	if exclude_id >= 0:
		# Seat priority follows stable live placement IDs. Appending a moved
		# early item last would validate a different shop from the real commit.
		ids.clear()
		preview = _preview_without(exclude_id, ids, definition, origin, turns)
		if preview == null:
			return EditCheck.new(false, "The current shop has invalid placements")
		for preview_id: int in ids:
			if ids[preview_id] == result_id:
				proposed_id = preview_id
				break
	else:
		var placed: PlacedItem = preview.place_def(definition, origin, turns)
		ids[placed.id] = result_id
		proposed_id = placed.id
	if proposed_id < 0:
		return EditCheck.new(false, "The shop changed; check the placement again")
	var dining: EditCheck = EditCheck.new(true) if restoring \
		else EditCheck.validate_dining(_sim.world.grid, preview, ids, proposed_id, exclude_id)
	if not dining.ok:
		return dining
	if not restoring:
		var rooms: String = RoomRules.problem(_sim.world.grid, preview, ids)
		if not rooms.is_empty():
			return EditCheck.new(false, rooms)
	var check: EditCheck = EditCheck.new(true)
	_fill_warnings(check, preview, ids)
	_note_menu_access(check, preview, restoring)
	return check


## Keep a new edit from leaving an empty unlocked catalogue. Exact history
## restores an accepted layout, so its existing access exemption still holds.
func _note_menu_access(check: EditCheck, preview: SimGrid, restoring: bool) -> void:
	if restoring:
		return
	check.menu_losses = MenuAccess.lost(_sim.world.grid, preview, _sim.menu)
	check.menu_warning = MenuAccess.warning(check.menu_losses, preview, _content)
	var recipes: Array[RecipeDef] = _content.recipes()
	if MenuAccess.cookable(preview, recipes, _owner_level).is_empty() \
			and not MenuAccess.cookable(_sim.world.grid, recipes, _owner_level).is_empty():
		check.ok = false
		check.why = MenuAccess.NO_DISH
		return


## One presentation mapping for every geometric placement result.
static func placement_reason(result: SimGrid.PlaceResult) -> String:
	match result:
		SimGrid.PlaceResult.OK:
			return ""
		SimGrid.PlaceResult.OUT_OF_BOUNDS:
			return "Outside the shop"
		SimGrid.PlaceResult.NOT_FLOOR:
			return "Must be placed on the floor"
		SimGrid.PlaceResult.OVERLAPS:
			return "Something is in the way"
		SimGrid.PlaceResult.INVALID_LAYER:
			return "This item cannot be placed here"
		SimGrid.PlaceResult.INVALID_CELLS:
			return "This item has invalid floor space"
		SimGrid.PlaceResult.WALL_IN_WAY:
			return "A wall is in the way"
	return "Cannot place this item here"


func _preview_without(exclude_id: int, ids: Dictionary[int, int], replacement: ItemDef = null,
		replacement_origin: Vector2i = Vector2i.ZERO, replacement_turns: int = 0) -> SimGrid:
	var live: SimGrid = _sim.world.grid
	var preview: SimGrid = live.terrain_copy()
	var segments: Dictionary[Vector3i, int] = {}
	for edge: Vector3i in live.segment_edges():
		segments[edge] = live.segment(edge)
	preview.set_segments(segments)
	for placed: PlacedItem in live.items():
		var replacing: bool = placed.id == exclude_id
		if replacing and replacement == null:
			continue
		var definition: ItemDef = replacement if replacing else placed.def as ItemDef
		if not _valid_definition(definition):
			return null
		var origin: Vector2i = replacement_origin if replacing else placed.origin
		var turns: int = replacement_turns if replacing else placed.quarter_turns
		var copy: PlacedItem = preview.place_def(definition, origin, turns)
		if copy == null:
			return null
		ids[copy.id] = placed.id
	return preview


## A furnishing's customer reservation belongs to its physical table, not to
## the chair's authored seat cells. Queries never release that reservation.
func _linked_seat_in_use(placed: PlacedItem) -> bool:
	var definition: ItemDef = placed.def as ItemDef
	if definition == null or definition.category != ItemDef.Category.CHAIR:
		return false
	var grid: SimGrid = _sim.world.grid
	for cell: Vector2i in placed.seat_cells:
		if grid.dining_furnishing_id(cell) != placed.id:
			continue
		var table: PlacedItem = grid.item(grid.dining_table_id(cell))
		if table != null and table.reserved_by(cell) != -1:
			return true
	return false


static func _fill_warnings(check: EditCheck, grid: SimGrid, ids: Dictionary[int, int]) -> void:
	check.unreachable = _unreachable(grid, ids)
	for table: PlacedItem in grid.items():
		var definition: ItemDef = table.def as ItemDef
		if definition.category == ItemDef.Category.WAITING:
			if WaitingBench.door_distance(grid, table.seat_cells) > WaitingBench.TUNING.waiting_bench_door_distance:
				check.seat_warnings[ids[table.id]] = WaitingBench.FAR_FROM_DOOR
			continue
		if definition.category != ItemDef.Category.TABLE:
			continue
		var nominal: int = DiningSeats.nominal_capacity(grid, table)
		var usable: int = DiningSeats.usable_cells(grid, table).size()
		if usable < nominal:
			check.seat_warnings[ids[table.id]] = "Only %d of %d seats usable" % [usable, nominal]


static func _unreachable(grid: SimGrid, ids: Dictionary[int, int]) -> Array[int]:
	var warnings: Array[int] = []
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		var reachable: bool = true
		if definition.category == ItemDef.Category.TABLE:
			reachable = _any_reachable(grid, placed.seat_cells)
		elif definition.category == ItemDef.Category.PASS:
			reachable = placed.work_cells.size() >= 2
			for index: int in range(mini(2, placed.work_cells.size())):
				if not _any_reachable(grid, [placed.work_cells[index]] as Array[Vector2i]):
					reachable = false
		elif definition.category == ItemDef.Category.STATION or definition.category == ItemDef.Category.STORAGE:
			reachable = _any_reachable(grid, placed.work_cells)
		if not reachable:
			warnings.append(ids[placed.id])
	warnings.sort()
	return warnings


static func _any_reachable(grid: SimGrid, cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		if not grid.is_walkable(cell):
			continue
		for entry: Vector2i in grid.entries():
			if grid.is_walkable(entry) and grid.is_reachable(entry, cell):
				return true
	return false


static func _valid_definition(definition: ItemDef) -> bool:
	return definition != null and not definition.id.is_empty() and definition.price >= 0 \
		and definition.unlock_level >= 1 and definition.footprint.x > 0 and definition.footprint.y > 0 \
		and definition.placement_layer_valid() and definition.blocking_cells_valid()


static func _required_key(definition: ItemDef) -> String:
	if definition == null:
		return ""
	if definition.category == ItemDef.Category.STORAGE and definition.station_type == &"fridge":
		return "fridge"
	if definition.category == ItemDef.Category.STATION and definition.station_type == &"prep_counter":
		return "prep counter"
	if definition.category == ItemDef.Category.STATION and definition.station_type == &"stove":
		return "stove"
	if definition.category == ItemDef.Category.STATION and definition.station_type == &"sink":
		return "sink"
	if definition.category == ItemDef.Category.PASS and definition.work_cells.size() >= 2:
		return "pass"
	return ""


static func _structure_key(definition: ItemDef) -> String:
	if definition.category == ItemDef.Category.DOOR:
		return "door:" + String(definition.id)
	# Existing version-1 shops predate sinks. Keep their saved layouts intact;
	# the last-present-sink sale guard applies once the player owns a sink.
	if definition.category == ItemDef.Category.STATION and definition.station_type == &"sink":
		return ""
	return _required_key(definition)


static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	if value is float:
		return is_finite(value) and value >= minimum and value <= maximum and floorf(value) == value
	return false
