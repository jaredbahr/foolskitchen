class_name RoomRules
extends RefCounted
## Rooms (FK-101): their names, which are staff-only, and every refusal
## sentence about seats, restrooms and the pass. Read-only queries over a
## SimGrid; the rooms themselves live on the grid (SimGrid.Room).
##
## Kitchen and Storage are staff-only. Guests never walk through them, staff
## walk everywhere. An edit is refused when it would newly put a seat in a
## staff-only room, or newly leave a seat, a toilet or the door reachable only
## through one (staff can reach it, guests can't), or newly leave the pass
## without the kitchen on its staff side and guests on its other side. Things
## that were already like that (an old save) stay, so unrelated edits work.

const IDS: Array[StringName] = [&"dining", &"kitchen", &"restroom", &"storage"]
const LABELS: Array[String] = ["Dining room", "Kitchen", "Restroom", "Storage"]

const SEAT_IN_KITCHEN: String = "Guests don't sit in the kitchen"
const SEAT_IN_STORAGE: String = "Guests don't sit in the storage room"
const SEAT_IN_RESTROOM: String = "Guests don't eat in the restroom"
const THROUGH_KITCHEN: String = "Guests can't reach this without walking through the kitchen"
const PASS_SIDES: String = "The pass needs the kitchen on one side and guests on the other"
const ROOMS_CLOSED: String = "Rooms can only be painted in the morning or after closing"
const NOT_FLOOR: String = "Rooms are painted on the shop floor"
const ALREADY: String = "That is already this room"

## ItemDef.station_type of a toilet (a restroom fixture).
const TOILET: StringName = &"toilet"


## The save id of a room kind, or &"" for an unknown one.
static func id_of(kind: int) -> StringName:
	return IDS[kind] if kind >= 0 and kind < IDS.size() else &""


## The room kind for a save id, or -1.
static func kind_of(id: StringName) -> int:
	return IDS.find(id)


## Player words for a room kind.
static func label(kind: int) -> String:
	return LABELS[kind] if kind >= 0 and kind < LABELS.size() else ""


## Cells guests can walk to from the street, never entering a staff-only room.
static func guest_reachable(grid: SimGrid) -> Dictionary[Vector2i, bool]:
	if not grid.has_staff_rooms():
		return WallRules.reachable(grid)
	var seen: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = []
	for entry: Vector2i in grid.entries():
		if grid.is_guest_walkable(entry) and not seen.has(entry):
			seen[entry] = true
			frontier.append(entry)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for neighbour: Vector2i in grid.guest_neighbours(cell):
				if not seen.has(neighbour):
					seen[neighbour] = true
					next.append(neighbour)
		frontier = next
	return seen


## The guest rooms as seen, not walked (the vibe, FK-101): FLOOR cells joined
## to the street door by orthogonal steps that cross no wall or window and
## never enter a staff-only room. Furniture is ignored, so decor crowded by
## other furniture still shows.
static func guest_floor(grid: SimGrid) -> Dictionary[Vector2i, bool]:
	var seen: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = []
	for entry: Vector2i in grid.entries():
		if not seen.has(entry):
			seen[entry] = true
			frontier.append(entry)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var neighbour: Vector2i = cell + step
				var terrain: SimGrid.Terrain = grid.terrain(neighbour)
				if seen.has(neighbour) or (terrain != SimGrid.Terrain.FLOOR and terrain != SimGrid.Terrain.ENTRY) \
						or grid.is_staff_only(neighbour) or grid.edge_blocked(cell, neighbour):
					continue
				seen[neighbour] = true
				next.append(neighbour)
		frontier = next
	return seen


## The back-wall rule (Jared, FK-101): starting-shell cells that a floor change
## opens into floor become Kitchen when they touch a Kitchen cell, so guests
## never brush past the stove through an opened wall; the player may repaint
## them. `before` is the shop before the change (its rooms decide), `after`
## the shop's terrain after it. Cells outside `building` (bought lot floor)
## stay Dining.
static func opened_kitchen(before: SimGrid, after: SimGrid, building: Rect2i) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in after.cells():
		if not building.has_point(cell) or after.terrain(cell) != SimGrid.Terrain.FLOOR \
				or before.terrain(cell) == SimGrid.Terrain.FLOOR:
			continue
		for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if before.room(cell + step) == SimGrid.Room.KITCHEN:
				out[cell] = SimGrid.Room.KITCHEN
				break
	return out


## True for a placed toilet (a restroom fixture guests use).
static func is_toilet(placed: PlacedItem) -> bool:
	var definition: ItemDef = placed.def as ItemDef if placed != null else null
	return definition != null and definition.category == ItemDef.Category.RESTROOM \
		and definition.station_type == TOILET


## The first problem `preview` adds over `live`, or "". `ids` maps preview item
## ids to live ids (0 for a proposed new item).
static func problem(live: SimGrid, preview: SimGrid, ids: Dictionary[int, int]) -> String:
	if not live.has_rooms() and not preview.has_rooms():
		return ""
	var before: Dictionary[String, String] = live_violations(live)
	var after: Dictionary[String, String] = violations(preview, ids)
	for key: String in after:
		if not before.has(key):
			return after[key]
	return ""


## The live shop's violations, cached on the grid against its layout version:
## hovering a buy, move or room paint only recomputes the proposed side.
static func live_violations(live: SimGrid) -> Dictionary[String, String]:
	var cached: Array = live.get_meta(&"room_violations", [])
	if cached.size() == 2 and cached[0] == live.version:
		return cached[1]
	var identity: Dictionary[int, int] = {}
	var found: Dictionary[String, String] = violations(live, identity)
	live.set_meta(&"room_violations", [live.version, found])
	return found


## Every rule broken in `grid`, key -> sentence, in a fixed order (seats in
## staff rooms first, then cut-off seats, toilets and the door, then the pass).
static func violations(grid: SimGrid, ids: Dictionary[int, int]) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	if not grid.has_rooms():
		return out
	var anyone: Dictionary[Vector2i, bool] = WallRules.reachable(grid)
	var guests: Dictionary[Vector2i, bool] = guest_reachable(grid)
	var cut_off: Dictionary[String, String] = {}
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null:
			continue
		var live_id: int = ids.get(placed.id, placed.id)
		if definition.category == ItemDef.Category.TABLE:
			for seat: Vector2i in placed.seat_cells:
				var kind: int = grid.room(seat)
				if kind != SimGrid.Room.DINING:
					out["seat:%d:%d:%d" % [live_id, seat.x, seat.y]] = SEAT_IN_KITCHEN \
						if kind == SimGrid.Room.KITCHEN else (SEAT_IN_STORAGE if kind == SimGrid.Room.STORAGE else SEAT_IN_RESTROOM)
				elif anyone.has(seat) and not guests.has(seat):
					cut_off["reach:%d:%d:%d" % [live_id, seat.x, seat.y]] = THROUGH_KITCHEN
		elif is_toilet(placed):
			for spot: Vector2i in placed.work_cells:
				if anyone.has(spot) and not guests.has(spot):
					cut_off["toilet:%d:%d:%d" % [live_id, spot.x, spot.y]] = THROUGH_KITCHEN
	for door: Vector2i in WallRules.door_cells(grid):
		if anyone.has(door) and not guests.has(door):
			cut_off["door:%d:%d" % [door.x, door.y]] = THROUGH_KITCHEN
	out.merge(cut_off)
	if not _has_kitchen(grid):
		return out
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null or definition.category != ItemDef.Category.PASS or placed.work_cells.size() < 2:
			continue
		if grid.room(placed.work_cells[0]) != SimGrid.Room.KITCHEN or not guests.has(placed.work_cells[1]):
			out["pass:%d:%d:%d:%d" % [ids.get(placed.id, placed.id), placed.origin.x, placed.origin.y,
				placed.quarter_turns]] = PASS_SIDES
	return out


static func _has_kitchen(grid: SimGrid) -> bool:
	for cell: Vector2i in grid.rooms():
		if grid.room(cell) == SimGrid.Room.KITCHEN:
			return true
	return false


## Toilets guests can use: standing in a Restroom room, with a use spot in
## the Restroom room too that guests can reach.
## In placement order. Empty when the shop has no restroom.
static func restroom_toilets(grid: SimGrid) -> Array[PlacedItem]:
	var out: Array[PlacedItem] = []
	var guests: Dictionary[Vector2i, bool] = {}
	var computed: bool = false
	for placed: PlacedItem in grid.items():
		if not is_toilet(placed) or placed.removed:
			continue
		var in_room: bool = false
		for cell: Vector2i in placed.cells:
			if grid.room(cell) == SimGrid.Room.RESTROOM:
				in_room = true
		if not in_room:
			continue
		if not computed:
			guests = guest_reachable(grid)
			computed = true
		for spot: Vector2i in placed.work_cells:
			if grid.room(spot) == SimGrid.Room.RESTROOM and guests.has(spot):
				out.append(placed)
				break
	return out
