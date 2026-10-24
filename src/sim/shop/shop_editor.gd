class_name ShopEditor
extends RefCounted
## Closed-phase furniture editing. Checks use an isolated grid; books and live
## grid signals change only when a mutation succeeds. No autoloads or nodes.

const SNAPSHOT_VERSION: int = 1

var last_check: EditCheck = EditCheck.new()
## Cosmetic whole-room paint. Empty IDs use the ShopView defaults.
var wall_swatch_id: StringName = &""
var floor_swatch_id: StringName = &""
var _sim: RestaurantSim
var _content: ContentDB
var _books: ShopEditBooks
var _applying: bool = false
var _owner_level: int = 1


func _init(sim: RestaurantSim, content: ContentDB, books: ShopEditBooks, layout: ShopLayout = null) -> void:
	_sim = sim
	_content = content
	_books = books
	if layout != null:
		wall_swatch_id = _known_swatch(layout.wall_swatch_id)
		floor_swatch_id = _known_swatch(layout.floor_swatch_id)


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
	check.unreachable = _unreachable(preview, ids)
	return check


func check_move(item_id: int, origin: Vector2i, quarter_turns: int) -> EditCheck:
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
	return _check_placement(definition, origin, quarter_turns, item_id, item_id)


func move(item_id: int, origin: Vector2i, quarter_turns: int) -> bool:
	var check: EditCheck = check_move(item_id, origin, quarter_turns)
	last_check = check
	if not check.ok:
		return false
	_applying = true
	var moved: bool = _sim.world.grid.relocate_def(item_id, origin, quarter_turns)
	_applying = false
	last_check = check if moved else EditCheck.new(false, "The shop changed; check the move again")
	return moved


func check_buy(def_id: StringName, origin: Vector2i, quarter_turns: int = 0) -> EditCheck:
	var check: EditCheck = _edit_check()
	if not check.ok:
		return check
	var definition: ItemDef = _content.item(def_id)
	if not _valid_definition(definition):
		return EditCheck.new(false, "Unknown or invalid item definition")
	if definition.unlock_level > _owner_level:
		return EditCheck.new(false, "Unlocks at level %d" % definition.unlock_level)
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	if not _books.can_spend_without_loan(definition.price):
		return EditCheck.new(false, "Not enough cash; furniture cannot use a loan")
	return _check_placement(definition, origin, quarter_turns, -1, 0)


func buy(def_id: StringName, origin: Vector2i, quarter_turns: int = 0) -> bool:
	var check: EditCheck = check_buy(def_id, origin, quarter_turns)
	last_check = check
	if not check.ok:
		return false
	var definition: ItemDef = _content.item(def_id)
	_applying = true
	var placed: PlacedItem = _sim.world.grid.place_def(definition, origin, quarter_turns)
	if placed != null:
		_books.add_cash(-definition.price, Ledger.UPGRADES)
	_applying = false
	last_check = check if placed != null else EditCheck.new(false, "The shop changed; check the purchase again")
	return placed != null


func check_sell(item_id: int) -> EditCheck:
	var check: EditCheck = _edit_check()
	if not check.ok:
		return check
	var placed: PlacedItem = _sim.world.grid.item(item_id)
	if placed == null:
		return EditCheck.new(false, "That item is no longer in the shop")
	var definition: ItemDef = placed.def as ItemDef
	if not _valid_definition(definition):
		return EditCheck.new(false, "That item has no valid definition")
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
	if _books == null or not _books.is_ready():
		return EditCheck.new(false, "The shop books are unavailable")
	var ids: Dictionary[int, int] = {}
	var preview: SimGrid = _preview_without(item_id, ids)
	if preview == null:
		return EditCheck.new(false, "The current shop has invalid placements")
	check.unreachable = _unreachable(preview, ids)
	return check


## -1 is refusal (see last_check/check_sell); zero is a successful free refund.
@warning_ignore("integer_division")
func sell(item_id: int) -> int:
	var check: EditCheck = check_sell(item_id)
	last_check = check
	if not check.ok:
		return -1
	var definition: ItemDef = _sim.world.grid.item(item_id).def as ItemDef
	var refund: int = definition.price / 2
	_applying = true
	var removed: bool = _sim.world.grid.remove(item_id)
	if removed:
		_books.add_cash(refund, Ledger.UPGRADES)
	_applying = false
	last_check = check if removed else EditCheck.new(false, "The shop changed; check the sale again")
	return refund if removed else -1


## Stable placement order, independent nested values, and no runtime references.
func to_dict() -> Dictionary:
	var placements: Array[Dictionary] = []
	for placed: PlacedItem in _sim.world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		placements.append({"def_id": String(definition.id),
			"origin": [placed.origin.x, placed.origin.y], "quarter_turns": placed.quarter_turns,
			"swatch_id": String(placed.swatch_id)})
	return {"version": SNAPSHOT_VERSION, "items": placements,
		"wall_swatch_id": String(wall_swatch_id), "floor_swatch_id": String(floor_swatch_id)}


## Pure, transactional decoder. A successful layout is staged for a NEW session;
## it never replaces a live grid, changes books or replays morning setup.
## Missing save sections are handled by the caller using the original template.
static func from_dict(data: Dictionary, template_layout: ShopLayout, content: ContentDB, errors: Array[String]) -> ShopLayout:
	if template_layout == null or content == null:
		errors.append("Shop snapshot needs a layout and content")
		return null
	if not _integer_in(data.get("version"), SNAPSHOT_VERSION, SNAPSHOT_VERSION) or not data.get("items") is Array:
		errors.append("Invalid shop snapshot version or items")
		return null
	var preview: SimGrid = SimGrid.from_ascii(template_layout.rows)
	var rows: Array = data["items"]
	if rows.size() > preview.size.x * preview.size.y:
		errors.append("Too many shop items")
		return null
	var layout: ShopLayout = ShopLayout.new()
	layout.id = template_layout.id
	layout.display_name = template_layout.display_name
	layout.rows = template_layout.rows.duplicate()
	layout.staff_spawns = template_layout.staff_spawns.duplicate()
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
		if origin.size() != 2 or not _integer_in(origin[0], 0, preview.size.x - 1) or not _integer_in(origin[1], 0, preview.size.y - 1) or not _integer_in(turns, 0, 3):
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
	return layout


## Invalid or removed palette entries revert to authored colours on old saves.
static func _saved_swatch(value: Variant, content: ContentDB) -> StringName:
	if not (value is String or value is StringName):
		return &""
	var id: StringName = StringName(value)
	return id if content.swatch(id) != null else &""


func _edit_check() -> EditCheck:
	if not can_edit():
		return EditCheck.new(false, "Furniture can only be edited in the morning or after closing")
	if _content == null:
		return EditCheck.new(false, "The shop content is unavailable")
	return EditCheck.new(true)


func _check_placement(definition: ItemDef, origin: Vector2i, turns: int, exclude_id: int, result_id: int) -> EditCheck:
	var ids: Dictionary[int, int] = {}
	var preview: SimGrid = _preview_without(exclude_id, ids)
	if preview == null:
		return EditCheck.new(false, "The current shop has invalid placements")
	var result: SimGrid.PlaceResult = preview.can_place(definition.footprint, origin, turns)
	if result != SimGrid.PlaceResult.OK:
		return EditCheck.new(false, placement_reason(result))
	var placed: PlacedItem = preview.place_def(definition, origin, turns)
	ids[placed.id] = result_id
	var check: EditCheck = EditCheck.new(true)
	check.unreachable = _unreachable(preview, ids)
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
	return "Cannot place this item here"


func _preview_without(exclude_id: int, ids: Dictionary[int, int]) -> SimGrid:
	var live: SimGrid = _sim.world.grid
	var preview: SimGrid = SimGrid.new(live.size)
	for y: int in range(live.size.y):
		for x: int in range(live.size.x):
			var cell: Vector2i = Vector2i(x, y)
			preview.set_terrain(cell, live.terrain(cell))
	for placed: PlacedItem in live.items():
		if placed.id == exclude_id:
			continue
		var definition: ItemDef = placed.def as ItemDef
		if not _valid_definition(definition):
			return null
		var copy: PlacedItem = preview.place_def(definition, placed.origin, placed.quarter_turns)
		if copy == null:
			return null
		ids[copy.id] = placed.id
	return preview


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
		and definition.unlock_level >= 1 and definition.footprint.x > 0 and definition.footprint.y > 0


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
