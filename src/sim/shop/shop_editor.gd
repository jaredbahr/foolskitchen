class_name ShopEditor
extends RefCounted
## Closed-phase furniture editing. Checks use an isolated grid; books and live
## grid signals change only when a mutation succeeds. No autoloads or nodes.

## Version 2 adds wall segments (FK-070); version-1 shops have none.
## Version 3 adds the bought floor (FK-080); older shops are the starting shell.
const SNAPSHOT_VERSION: int = 3
const WALLS_CLOSED: String = "Walls can only be changed in the morning or after closing"

var last_check: EditCheck = EditCheck.new()
## The signed cash change of the last successful edit (negative = spent), and
## the id a successful buy gave its item. Undo history reads both (FK-085).
var last_cash_change: int = 0
var last_item_id: int = -1
## Cosmetic whole-room paint. Empty IDs use the ShopView defaults.
var wall_swatch_id: StringName = &""
var floor_swatch_id: StringName = &""
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
	return true


func paint_floor(swatch_id: StringName) -> bool:
	if not _can_paint(swatch_id):
		return false
	floor_swatch_id = swatch_id
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
	return {"version": SNAPSHOT_VERSION, "items": placements, "walls": segments, "floor": floor,
		"wall_swatch_id": String(wall_swatch_id), "floor_swatch_id": String(floor_swatch_id)}


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
	if rows.size() > preview.size.x * preview.size.y * ItemDef.PlacementLayer.size():
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
	if not WallRules.layout_problem(preview).is_empty():
		errors.append("Saved walls block the shop")
		return null
	return layout


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
## window -> wall; an outer face toggles between solid and window. An empty
## interior edge gets `empty_kind`. Returns NONE for "remove".
func next_segment(edge: Vector3i, empty_kind: SimGrid.Segment) -> SimGrid.Segment:
	if _sim == null or _sim.world == null:
		return SimGrid.Segment.NONE
	var grid: SimGrid = _sim.world.grid
	var current: SimGrid.Segment = grid.segment(edge)
	if WallRules.outer_side(grid, edge) != Vector2i.ZERO:
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
	if exact != null:
		cost = maxi(-exact.amount, 0)
		refund = maxi(exact.amount, 0)
	preview.set_segments(effective)
	var problem: String = WallRules.layout_problem(preview)
	if problem.is_empty() and exact == null:
		var dining: EditCheck = EditCheck.validate_dining(live, preview, ids, -1, -1)
		problem = "" if dining.ok else dining.why
	if problem.is_empty():
		problem = WallRules.cut_off_problem(live, preview, _people_cells(), exact != null)
	if not problem.is_empty():
		return EditCheck.new(false, problem)
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	if cost > refund and not _books.can_spend_without_loan(cost - refund):
		return EditCheck.new(false, _books.purchase_refusal_reason(cost - refund))
	var check: EditCheck = EditCheck.new(true)
	check.cost = cost
	check.refund = refund
	check.changes = effective
	_fill_warnings(check, preview, ids)
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
	_record(check.refund, check.cost, exact)
	_applying = false
	return true


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
## and refunded at the furniture rate; floor refunds half its price too.
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
	for cell: Vector2i in losing:
		var lost: String = _lost_spot(live, cell) if exact == null else ""
		if not lost.is_empty():
			return EditCheck.new(false, lost)
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
	for edge: Vector3i in _sorted_edges(restore):
		var restored: String = WallRules.edge_problem(preview, edge, restore[edge] as SimGrid.Segment)
		if not restored.is_empty():
			return EditCheck.new(false, restored)
		preview.set_segment(edge, restore[edge] as SimGrid.Segment)
		removals[edge] = restore[edge]
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
	problem = WallRules.layout_problem(preview)
	if problem.is_empty() and exact == null:
		var dining: EditCheck = EditCheck.validate_dining(live, preview, ids, -1, -1)
		problem = "" if dining.ok else dining.why
	if problem.is_empty():
		problem = WallRules.cut_off_problem(live, preview, _people_cells(), exact != null)
	if not problem.is_empty():
		return EditCheck.new(false, problem)
	var cost: int = effective.size() * _footprint.cell_price if adding else 0
	if not adding:
		refund += effective.size() * floori(_footprint.cell_price / 2.0)
	if exact != null:
		cost = maxi(-exact.amount, 0)
		refund = maxi(exact.amount, 0)
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	if cost > refund and not _books.can_spend_without_loan(cost - refund):
		return EditCheck.new(false, _books.purchase_refusal_reason(cost - refund))
	var check: EditCheck = EditCheck.new(true)
	check.cost = cost
	check.refund = refund
	check.changes = removals
	check.floor_cells = ShopFootprint.sorted(effective)
	check.floor_adding = adding
	_fill_warnings(check, preview, ids)
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
		_bought = next
		if _sim.cleanliness != null:
			for spot: Vector2i in _sim.cleanliness.spots():
				if grid.terrain(spot) != SimGrid.Terrain.FLOOR:
					_sim.cleanliness.clear_spot(spot)
		_record(check.refund, check.cost, exact)
	_applying = false
	if not applied:
		last_check = EditCheck.new(false, "The shop changed; check the floor again")
	return applied


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
	var check: EditCheck = EditCheck.new(true)
	_fill_warnings(check, preview, ids)
	return check


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
