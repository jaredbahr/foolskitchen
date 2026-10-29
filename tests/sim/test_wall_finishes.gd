extends TestCase
## D26: wall finishes per wall face and wall decor hung on faces. Every face
## starts as the free plain paint in the shop's wall colour (nothing stored);
## a new finish costs its price per face and refunds half the old one,
## morning or closed only; recolouring is free at any time; locked finishes
## wait for their level. Wall decor hangs on solid faces only, one item per
## face, and comes down with its wall (refunded); the neon OPEN sign hangs in
## an outside window instead, one per window, and comes down with the window.
## Saves keep both (forgiving),
## older saves are plain paint with nothing hung, and the vibe sees exactly
## the old whole-shop paint and no wall decor by default.
## Grid: the starting shell is x 0..13, y 0..10; kitchen x 1..12, y 1..3 plus
## (5..7, 4); dining x 1..12, y 5..9 plus (6..7, 10); street entry (6..7, 11).
## Faces: Vector3i(x, y, dir) with dir 0 north, 1 east, 2 south, 3 west.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const START_CASH: int = 1000
const WEST: int = 3
const EAST: int = 1
const NORTH: int = 0
const SOUTH: int = 2
## A street-front window right of the door, and the OPEN sign's slot in it.
const FRONT_WINDOW: Vector3i = Vector3i(8, 10, SimGrid.EDGE_NORTH)
const FRONT_SLOT: Vector3i = Vector3i(8, 9, SOUTH)

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _ledger: Ledger


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_ledger = Ledger.new()
	_ledger.cash = START_CASH
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)


func after_each() -> void:
	_history = null
	_editor = null
	_sim = null
	_content = null
	_ledger = null


func test_every_shop_starts_as_plain_paint_with_nothing_stored_or_hung() -> void:
	assert_eq(_editor.walls.count(), 0)
	assert_eq(_editor.decor.count(), 0)
	var look: FloorFinishes.Finish = _editor.walls.finish(_face(1, 6, WEST))
	assert_eq(look.style, WallStyleDef.DEFAULT_ID)
	assert_eq(look.swatch, LAYOUT.wall_swatch_id)
	var snapshot: Dictionary = _editor.to_dict()
	assert_eq(int(snapshot["version"]), 6)
	assert_eq(snapshot["wall_style_id"], "paint")
	assert_eq(snapshot["wall_finishes"], [] as Array[Array])
	assert_eq(snapshot["wall_items"], [] as Array[Array])


func test_faces_are_solid_walls_seen_from_the_floor() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_true(WallFaces.is_face(grid, _face(1, 6, WEST)), "the dining room's west shell wall")
	assert_true(WallFaces.is_face(grid, _face(3, 1, NORTH)), "the kitchen's back wall")
	assert_true(WallFaces.is_face(grid, _face(3, 5, NORTH)), "the dining side of the kitchen wall")
	assert_false(WallFaces.is_face(grid, _face(6, 5, NORTH)), "the open pass has no wall")
	assert_eq(WallFaces.problem(grid, _face(6, 10, 2)), WallFaces.STREET_DOOR)
	assert_eq(WallFaces.problem(grid, _face(0, 6, EAST)), WallFaces.NOT_INSIDE, "seen from inside the wall")
	assert_eq(WallFaces.problem(grid, _face(3, 6, NORTH)), WallFaces.NO_WALL)
	# An interior wall has two faces; a window or doorway none.
	_wall(9, 5, 9, SimGrid.Segment.WALL)
	grid.set_segment(Vector3i(9, 7, SimGrid.EDGE_WEST), SimGrid.Segment.DOORWAY)
	grid.set_segment(Vector3i(9, 8, SimGrid.EDGE_WEST), SimGrid.Segment.WINDOW)
	assert_true(WallFaces.is_face(grid, _face(8, 6, EAST)))
	assert_true(WallFaces.is_face(grid, _face(9, 6, WEST)))
	assert_eq(WallFaces.kind(grid, _face(9, 6, WEST)), WallFaces.Kind.INTERIOR)
	assert_eq(WallFaces.kind(grid, _face(1, 6, WEST)), WallFaces.Kind.SHELL)
	assert_eq(WallFaces.problem(grid, _face(9, 7, WEST)), WallFaces.DOORWAY)
	assert_eq(WallFaces.problem(grid, _face(9, 8, WEST)), WallFaces.WINDOW)
	# A shell window cuts its whole cell: no face on any of its sides.
	grid.set_segment(Vector3i(1, 7, SimGrid.EDGE_WEST), SimGrid.Segment.WINDOW)
	assert_eq(WallFaces.problem(grid, _face(1, 7, WEST)), WallFaces.WINDOW)
	assert_true(WallFaces.is_face(grid, _face(1, 6, WEST)), "the neighbouring shell cell is whole")
	var all: Array[Vector3i] = WallFaces.all(grid)
	var sorted: Array[Vector3i] = all.duplicate()
	WallFaces.sort(sorted)
	assert_eq(all, sorted)
	assert_true(all.has(_face(8, 6, EAST)) and not all.has(_face(9, 7, WEST)))


func test_putting_up_costs_per_face_and_replacing_refunds_half() -> void:
	var faces: Array[Vector3i] = _west(5, 4)
	var brick: Dictionary[Vector3i, FloorFinishes.Finish] = _editor.wall_lay_changes(faces, &"brick", &"brick", &"cream")
	var check: EditCheck = _editor.check_wall_finishes(brick)
	assert_true(check.ok, check.why)
	assert_eq([check.cost, check.refund], [16, 0], "four faces at $4; plain paint refunds nothing")
	assert_true(_editor.apply_wall_finishes(brick), _editor.last_check.why)
	assert_eq(_ledger.cash, START_CASH - 16)
	assert_eq(_editor.walls.finish(_face(1, 7, WEST)).style, &"brick")
	assert_eq(_editor.walls.count(), 4)
	check = _editor.check_wall_finishes(_editor.wall_lay_changes(faces, &"stripes", &"butter"))
	assert_eq([check.cost, check.refund], [8, 8], "$2 a face, refund half of $4")
	check = _editor.check_wall_finishes(_editor.wall_recolour_changes(faces, &"clay"))
	assert_eq([check.ok, check.cost, check.refund], [true, 0, 0], "a recolour is free")
	assert_true(_editor.apply_wall_finishes(_editor.wall_recolour_changes(faces, &"clay")))
	assert_eq(_editor.walls.finish(_face(1, 5, WEST)).swatch, &"clay")
	assert_eq(_editor.walls.finish(_face(1, 5, WEST)).accent, &"cream")
	assert_true(_editor.apply_wall_finishes(_editor.wall_lay_changes(faces, &"paint", LAYOUT.wall_swatch_id)))
	assert_eq(_editor.walls.count(), 0, "plain paint in the shop colour stores nothing")
	assert_eq(_ledger.cash, START_CASH - 16 + 8)
	assert_eq(_editor.check_wall_finishes(_editor.wall_lay_changes(faces, &"paint", LAYOUT.wall_swatch_id)).why,
		ShopEditor.WALL_FINISH_ALREADY)
	assert_eq(_editor.check_wall_finishes(_editor.wall_lay_changes([_face(3, 6, NORTH)] as Array[Vector3i],
		&"brick", &"brick")).why, ShopEditor.WALL_FINISH_NOT_WALL)


func test_putting_up_is_closed_only_and_recolouring_works_during_service() -> void:
	var faces: Array[Vector3i] = _west(5, 2)
	assert_true(_editor.apply_wall_finishes(_editor.wall_lay_changes(faces, &"wainscot", &"sage")))
	_sim.world.clock.start_service()
	assert_eq(_editor.check_wall_finishes(_editor.wall_lay_changes(_west(8, 1), &"brick", &"brick")).why,
		ShopEditor.WALL_FINISH_CLOSED)
	var cash: int = _ledger.cash
	assert_true(_history.apply_wall_finishes(_editor.wall_recolour_changes(faces, &"moss")), _editor.last_check.why)
	assert_eq(_editor.walls.finish(_face(1, 6, WEST)).swatch, &"moss")
	assert_eq(_ledger.cash, cash)
	assert_eq(_history.undo_count(), 0, "service-time recolours are not undo entries, like paint")
	assert_eq(_editor.check_hang(&"wall_art_sunrise", _face(1, 8, WEST)).why, ShopEditor.DECOR_CLOSED)


func test_locked_finishes_and_decor_wait_for_their_level() -> void:
	_editor.set_owner_level(1)
	var faces: Array[Vector3i] = _west(5, 1)
	for style: StringName in [&"paint", &"wainscot", &"stripes"]:
		assert_true(_editor.check_wall_finishes(_editor.wall_lay_changes(faces, style, &"cream")).ok, "starter %s" % style)
	assert_eq(_editor.check_wall_finishes(_editor.wall_lay_changes(faces, &"subway_tile", &"cream")).why, "Unlocks at level 2")
	assert_eq(_editor.check_wall_finishes(_editor.wall_lay_changes(faces, &"brick", &"brick")).why, "Unlocks at level 3")
	_window(FRONT_WINDOW)
	assert_eq(_editor.check_hang(&"neon_open_sign", FRONT_SLOT).why, "Unlocks at level 4")
	assert_true(_editor.check_hang(&"wall_art_sunrise", _face(1, 6, WEST)).ok)
	_editor.set_owner_level(3)
	assert_true(_editor.check_wall_finishes(_editor.wall_lay_changes(faces, &"brick", &"brick")).ok)
	assert_eq(_editor.check_wall_finishes(_editor.wall_lay_changes(faces, &"marble", &"cream")).why, "Unknown wall finish")
	assert_eq(_editor.check_wall_finishes(_editor.wall_lay_changes(faces, &"brick", &"neon")).why, "Unknown colour")


func test_paint_area_follows_the_wall_round_corners_and_stops_at_rooms_and_doorways() -> void:
	var dining: Array[Vector3i] = _editor.wall_room_faces(_face(1, 6, WEST))
	for face: Vector3i in dining:
		assert_ne(_sim.world.grid.room(WallFaces.cell(face)), SimGrid.Room.KITCHEN, "Shift stays in its room")
	assert_true(dining.has(_face(12, 9, EAST)) and dining.has(_face(3, 5, NORTH)))
	var area: Array[Vector3i] = _editor.wall_area_faces(_face(1, 6, WEST))
	assert_true(area.has(_face(1, 5, NORTH)), "round the inside corner")
	assert_true(area.has(_face(1, 9, 2)) and area.has(_face(5, 9, 2)), "along the walls of one look")
	assert_false(area.has(_face(12, 5, EAST)), "an opening (the pass, the street door) ends the run")
	for face: Vector3i in area:
		assert_true(dining.has(face), "a click never reaches beyond Shift")
	assert_true(_editor.apply_wall_finishes(_editor.wall_lay_changes(_west(5, 2), &"brick", &"brick")))
	assert_eq(_editor.wall_area_faces(_face(1, 5, WEST)), _west(5, 2), "a run of one look")
	assert_false(_editor.wall_area_faces(_face(1, 8, WEST)).has(_face(1, 6, WEST)))


func test_hanging_rules_sale_and_move() -> void:
	var grid: SimGrid = _sim.world.grid
	var sunrise: ItemDef = _content.item(&"wall_art_sunrise")
	assert_true(sunrise.hangs_on_wall())
	assert_eq(grid.can_place_def(sunrise, Vector2i(3, 7), 0), SimGrid.PlaceResult.INVALID_LAYER, "never on the floor")
	assert_false(_editor.check_buy(&"wall_art_sunrise", Vector2i(3, 7)).ok)
	# West wall faces run north to south... the item's right is north there.
	var anchor: Vector3i = _face(1, 7, WEST)
	assert_eq(WallFaces.span(anchor, 2), [anchor, _face(1, 6, WEST)] as Array[Vector3i])
	var check: EditCheck = _editor.check_hang(&"wall_art_sunrise", anchor)
	assert_true(check.ok, check.why)
	assert_eq(check.cost, 30)
	assert_true(_history.hang(&"wall_art_sunrise", anchor), _editor.last_check.why)
	assert_eq(_history.undo_label(), "hang Sunrise print")
	assert_eq(_ledger.cash, START_CASH - 30)
	assert_eq(_editor.decor.anchor_at(_face(1, 6, WEST)), anchor)
	assert_eq(_editor.check_hang(&"menu_board", _face(1, 6, WEST)).why, WallDecor.OCCUPIED)
	assert_eq(_editor.check_hang(&"menu_board", _face(1, 5, WEST)).why, WallFaces.TOO_NARROW, "the corner ends the wall")
	assert_eq(_editor.check_hang(&"menu_board", _face(3, 6, NORTH)).why, WallFaces.NO_WALL)
	assert_eq(_editor.check_hang(&"menu_board", _face(6, 10, 2)).why, WallFaces.STREET_DOOR)
	assert_eq(_editor.check_hang(&"table_2", _face(1, 9, WEST)).why, WallDecor.NOT_WALL_DECOR)
	_wall(9, 5, 7, SimGrid.Segment.WINDOW)
	assert_eq(_editor.check_hang(&"menu_board", _face(8, 6, EAST)).why, WallFaces.WINDOW)
	# A move is free; the new spot may overlap the old one.
	assert_true(_history.rehang(anchor, _face(1, 8, WEST)), _editor.last_check.why)
	assert_eq(_ledger.cash, START_CASH - 30)
	assert_eq(_editor.decor.anchors(), [_face(1, 8, WEST)] as Array[Vector3i])
	assert_eq(_history.take_down(_face(1, 8, WEST)), 15, "sold at half price")
	assert_eq(_editor.decor.count(), 0)
	assert_eq(_ledger.cash, START_CASH - 15)
	# Undo all three exactly.
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, START_CASH - 30)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.decor.anchors(), [anchor] as Array[Vector3i])
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.decor.count(), 0)
	assert_eq(_ledger.cash, START_CASH)
	_editor.set_owner_level(1)
	for step: int in 3:
		assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_ledger.cash, START_CASH - 15)
	assert_eq(_upgrades(), -15)


func test_the_open_sign_hangs_only_in_an_outside_window() -> void:
	var sign: ItemDef = _content.item(&"neon_open_sign")
	assert_eq(sign.wall_mount, ItemDef.WallMount.WINDOW)
	assert_true(sign.hangs_in_window() and sign.placement_layer_valid())
	assert_false(_content.item(&"menu_board").hangs_in_window(), "boards and prints stay on inside walls")
	assert_eq(_editor.check_hang(&"neon_open_sign", _face(1, 7, WEST)).why, WallFaces.WINDOW_ONLY, "not on a wall")
	assert_eq(_editor.check_hang(&"neon_open_sign", FRONT_SLOT).why, WallFaces.WINDOW_ONLY, "no window yet")
	assert_eq(WallFaces.WINDOW_ONLY, "This sign hangs in a window")
	_window(FRONT_WINDOW)
	_window(Vector3i(10, 10, SimGrid.EDGE_NORTH))
	_wall(9, 5, 5, SimGrid.Segment.WINDOW)
	assert_eq(WallFaces.windows(_sim.world.grid), [FRONT_SLOT, _face(10, 9, SOUTH)] as Array[Vector3i],
		"outside windows only, seen from the floor inside")
	assert_eq(_editor.check_hang(&"neon_open_sign", _face(8, 5, EAST)).why, WallFaces.OUTSIDE_WINDOW_ONLY,
		"not in a window between two rooms")
	assert_eq(_editor.check_hang(&"wall_art_sunrise", FRONT_SLOT).why, WallFaces.WINDOW, "prints keep to walls")
	var cash: int = _ledger.cash
	assert_true(_history.hang(&"neon_open_sign", FRONT_SLOT), _editor.last_check.why)
	assert_eq(_ledger.cash, cash - 80)
	assert_eq(_editor.decor.item(FRONT_SLOT).width, 1, "one window wide")
	assert_eq(_editor.check_hang(&"neon_open_sign", FRONT_SLOT).why, WallDecor.OCCUPIED, "one sign per window")
	assert_true(_editor.check_rehang(FRONT_SLOT, _face(10, 9, SOUTH)).ok, "moves to another window")
	assert_eq(_editor.check_rehang(FRONT_SLOT, _face(1, 7, WEST)).why, WallFaces.WINDOW_ONLY)
	assert_true(_history.rehang(FRONT_SLOT, _face(10, 9, SOUTH)), _editor.last_check.why)
	assert_eq(_editor.decor.anchors(), [_face(10, 9, SOUTH)] as Array[Vector3i])
	assert_eq(_editor.decor_vibe_items(), [sign] as Array[ItemDef], "guests see it from the dining room")
	assert_eq(_history.take_down(_face(10, 9, SOUTH)), 40, "sold for half")
	# A window-mounted item is one window wide.
	var wide: ItemDef = sign.duplicate() as ItemDef
	wide.footprint = Vector2i(2, 1)
	assert_false(wide.placement_layer_valid())


func test_closing_the_window_takes_the_sign_down_with_a_refund() -> void:
	_window(FRONT_WINDOW)
	var to_wall: Dictionary[Vector3i, int] = {FRONT_WINDOW: SimGrid.Segment.NONE}
	var bare: int = _editor.check_segments(to_wall).refund
	assert_true(_history.hang(&"neon_open_sign", FRONT_SLOT), _editor.last_check.why)
	var check: EditCheck = _editor.check_segments(to_wall)
	assert_true(check.ok, check.why)
	assert_eq(check.lost_decor, [FRONT_SLOT] as Array[Vector3i])
	assert_eq(check.refund, bare + 40, "the sign's sale refund on top")
	var before: int = _ledger.cash
	assert_true(_history.apply_segments(to_wall), _editor.last_check.why)
	assert_eq(_ledger.cash, before + bare + 40)
	assert_eq(_editor.decor.count(), 0)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, before, "exact cash back")
	assert_eq(_editor.decor.anchors(), [FRONT_SLOT] as Array[Vector3i], "back in its window")
	# Floor bought behind the window's shell cell makes it an inside window: down it comes.
	var east: Vector3i = Vector3i(13, 2, SimGrid.EDGE_WEST)
	_window(east)
	assert_true(_history.hang(&"neon_open_sign", _face(12, 2, EAST)), _editor.last_check.why)
	var floor_check: EditCheck = _editor.check_floor(_lot_column(), true)
	assert_true(floor_check.ok, floor_check.why)
	assert_eq(floor_check.lost_decor, [_face(12, 2, EAST)] as Array[Vector3i])


func test_removing_a_wall_takes_its_finish_and_decor_down_with_a_refund() -> void:
	assert_true(_history.apply_segments(_segments(9, 5, 8, SimGrid.Segment.WALL)), _editor.last_check.why)
	var cash: int = _ledger.cash
	assert_true(_history.apply_wall_finishes(_editor.wall_lay_changes(
		[_face(8, 6, EAST), _face(9, 6, WEST), _face(1, 6, WEST)] as Array[Vector3i], &"brick", &"brick")))
	assert_true(_history.hang(&"menu_board", _face(9, 7, WEST)), _editor.last_check.why)
	assert_eq(_ledger.cash, cash - 12 - 25)
	var removal: Dictionary[Vector3i, int] = _segments(9, 5, 8, SimGrid.Segment.NONE)
	var check: EditCheck = _editor.check_segments(removal)
	assert_true(check.ok, check.why)
	assert_eq(check.lost_finishes, [_face(8, 6, EAST), _face(9, 6, WEST)] as Array[Vector3i])
	assert_eq(check.lost_decor, [_face(9, 7, WEST)] as Array[Vector3i])
	assert_eq(check.refund, 4 * 5 + 2 * 2 + 12, "walls $5 each, brick $2 a face, the board $12")
	var before: int = _ledger.cash
	assert_true(_history.apply_segments(removal), _editor.last_check.why)
	assert_eq(_ledger.cash, before + 36)
	assert_eq(_editor.walls.faces(), [_face(1, 6, WEST)] as Array[Vector3i], "the shell's finish stays")
	assert_eq(_editor.decor.count(), 0)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, before, "exact cash back")
	assert_eq(_editor.walls.count(), 3)
	assert_eq(_editor.walls.finish(_face(9, 6, WEST)).style, &"brick")
	assert_eq(_editor.decor.anchors(), [_face(9, 7, WEST)] as Array[Vector3i])
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_ledger.cash, before + 36)
	assert_eq(_editor.decor.count(), 0)
	# Turning a finished wall into a doorway takes the finish too.
	assert_true(_history.undo(), _history.last_refusal)
	var doorway: Dictionary[Vector3i, int] = {Vector3i(9, 6, SimGrid.EDGE_WEST): SimGrid.Segment.DOORWAY}
	check = _editor.check_segments(doorway)
	assert_eq(check.lost_finishes, [_face(8, 6, EAST), _face(9, 6, WEST)] as Array[Vector3i])
	assert_eq(check.lost_decor, [_face(9, 7, WEST)] as Array[Vector3i], "the board hung across that face")


func test_opening_the_shell_takes_its_finish_and_decor_down() -> void:
	# Floor bought on the lot east of the shop turns the east wall cells into floor.
	var face: Vector3i = _face(12, 2, EAST)
	assert_true(_history.apply_wall_finishes(_editor.wall_lay_changes([face] as Array[Vector3i], &"stripes", &"butter")))
	assert_true(_history.hang(&"wall_art_peaks", _face(12, 2, EAST)), _editor.last_check.why)
	var check: EditCheck = _editor.check_floor(_lot_column(), true)
	assert_true(check.ok, check.why)
	assert_eq(check.lost_finishes, [face] as Array[Vector3i])
	assert_eq(check.lost_decor, [_face(12, 2, EAST)] as Array[Vector3i])
	var cash: int = _ledger.cash
	assert_true(_history.apply_floor(_lot_column(), true), _editor.last_check.why)
	assert_eq(_editor.walls.count(), 0)
	assert_eq(_editor.decor.count(), 0)
	assert_eq(_ledger.cash, cash - check.cost + check.refund)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, cash)
	assert_eq(_editor.walls.faces(), [face] as Array[Vector3i])
	assert_eq(_editor.decor.anchors(), [_face(12, 2, EAST)] as Array[Vector3i])


func test_expansion_takes_down_a_print_and_window_sign_with_exact_undo() -> void:
	var grid: SimGrid = _sim.world.grid
	var window: Vector3i = Vector3i(13, 2, SimGrid.EDGE_WEST)
	var print_face: Vector3i = _face(12, 7, EAST)
	var sign_face: Vector3i = _face(12, 2, EAST)
	_window(window)
	assert_true(_history.apply_wall_finishes(_editor.wall_lay_changes(
		[print_face] as Array[Vector3i], &"stripes", &"butter")))
	assert_true(_history.hang(&"wall_art_sunrise", print_face), _editor.last_check.why)
	assert_true(_history.hang(&"neon_open_sign", sign_face), _editor.last_check.why)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	var check: EditCheck = _editor.check_floor(_lot_column(), true)
	assert_true(check.ok, check.why)
	assert_eq(check.changes[window], SimGrid.Segment.NONE)
	assert_true(check.lost_decor.has(print_face))
	assert_true(check.lost_decor.has(sign_face))
	assert_eq(check.lost_finishes, [print_face] as Array[Vector3i])
	var expected: int = 10 + 1 + ShopEditor.sale_refund(_content.item(&"wall_art_sunrise")) \
		+ ShopEditor.sale_refund(_content.item(&"neon_open_sign"))
	assert_eq(check.refund, expected, "window, wallpaper, print and sign refund once each")
	assert_true(_history.apply_floor(_lot_column(), true), _editor.last_check.why)
	assert_eq(grid.segment(window), SimGrid.Segment.NONE)
	assert_eq(_editor.decor.count(), 0)
	assert_eq(_editor.walls.count(), 0)
	assert_eq(_ledger.cash, cash - check.cost + expected)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.to_dict(), before, "floor, window, finish and both pieces of decor restore exactly")
	assert_eq(_ledger.cash, cash)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(grid.segment(window), SimGrid.Segment.NONE)
	assert_eq(_editor.decor.count(), 0)
	assert_eq(_ledger.cash, cash - check.cost + expected)


func test_history_undoes_and_redoes_wall_finishes_with_exact_cash() -> void:
	var faces: Array[Vector3i] = _west(5, 3)
	assert_true(_history.apply_wall_finishes(_editor.wall_lay_changes(faces, &"subway_tile", &"cream")))
	assert_eq(_history.undo_label(), "put up Subway tiles")
	assert_true(_history.apply_wall_finishes(_editor.wall_recolour_changes(faces, &"sage")))
	assert_eq(_history.undo_label(), "recolour the walls")
	assert_eq(_ledger.cash, START_CASH - 9)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.walls.finish(_face(1, 6, WEST)).swatch, &"cream")
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.walls.count(), 0)
	assert_eq(_ledger.cash, START_CASH)
	assert_eq(_last_entry()["note"], ShopEditHistory.UNDO_NOTE)
	_editor.set_owner_level(1)
	assert_true(_history.redo(), _history.last_refusal)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_editor.walls.finish(_face(1, 7, WEST)).swatch, &"sage")
	assert_eq(_upgrades(), -9)


func test_snapshot_round_trip_keeps_finishes_and_decor() -> void:
	assert_true(_editor.apply_wall_finishes(_editor.wall_lay_changes(_west(5, 2), &"brick", &"brick", &"cream")))
	assert_true(_editor.apply_wall_finishes(_editor.wall_lay_changes([_face(3, 1, NORTH)] as Array[Vector3i], &"wainscot", &"walnut")))
	assert_true(_editor.hang(&"wall_art_sunrise", _face(1, 7, WEST)), _editor.last_check.why)
	_window(FRONT_WINDOW)
	assert_true(_editor.hang(&"neon_open_sign", FRONT_SLOT), _editor.last_check.why)
	var snapshot: Dictionary = _editor.to_dict()
	assert_eq(int(snapshot["version"]), 6, "a window slot fits the v6 row")
	assert_eq((snapshot["wall_finishes"] as Array)[0], [3, 1, 0, "wainscot", "walnut", ""], "sorted")
	assert_eq(snapshot["wall_items"], [[1, 7, 3, "wall_art_sunrise"], [8, 9, 2, "neon_open_sign"]])
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(JSON.parse_string(JSON.stringify(snapshot)), LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	var copy: ShopEditor = _restore(layout)
	assert_eq(copy.walls.to_rows(), _editor.walls.to_rows())
	assert_eq(copy.decor.to_rows(), _editor.decor.to_rows())
	assert_eq(copy.to_dict()["wall_items"], snapshot["wall_items"])
	assert_true(copy.decor.item(FRONT_SLOT).window, "loads back into its window")
	# A save whose window is gone (or a sign row on a plain wall) skips the sign.
	var broken: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	broken["wall_items"] = [[1, 7, 3, "wall_art_sunrise"], [1, 9, 3, "neon_open_sign"], [8, 9, 2, "neon_open_sign"],
		[12, 9, 2, "neon_open_sign"]]
	layout = ShopEditor.from_dict(broken, LAYOUT, _content, errors)
	assert_eq(_restore(layout).decor.to_rows(), [[1, 7, 3, "wall_art_sunrise"], [8, 9, 2, "neon_open_sign"]] as Array[Array],
		"only the sign in a real window loads")


func test_older_snapshots_are_plain_paint_with_nothing_hung() -> void:
	assert_true(_editor.apply_wall_finishes(_editor.wall_lay_changes(_west(5, 2), &"brick", &"brick")))
	assert_true(_editor.hang(&"menu_board", _face(1, 8, WEST)))
	var legacy: Dictionary = _editor.to_dict()
	legacy["version"] = 5
	for key: String in ["wall_style_id", "wall_finishes", "wall_items"]:
		legacy.erase(key)
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(legacy, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_true(layout.wall_finishes.is_empty() and layout.wall_items.is_empty())
	var copy: ShopEditor = _restore(layout)
	assert_eq([copy.walls.count(), copy.decor.count()], [0, 0])


func test_saved_walls_decode_forgivingly_and_ignore_another_default() -> void:
	var snapshot: Dictionary = _editor.to_dict()
	snapshot["wall_style_id"] = "brick"
	snapshot["wall_finishes"] = [
		[1, 5, 3, "brick", "brick", "cream"],
		[1, 5, 3, "stripes", "", ""],
		[1, 6, 3, "marble", "", ""],
		[1, 7, 3, "stripes", "neon", "glitter"],
		[3, 6, 0, "brick", "", ""],
		[1, 8, 9, "brick", "", ""],
		[1, 9, 3],
		"junk",
	]
	snapshot["wall_items"] = [
		[1, 9, 3, "menu_board"],
		[1, 8, 3, "wall_art_sunrise"],
		[3, 6, 0, "menu_board"],
		[3, 1, 0, "table_2"],
		[4, 1, 0, "lava_lamp"],
		[5, 1, 0],
	]
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String], "wall looks never refuse a save")
	assert_eq(layout.wall_style_id, WallStyleDef.DEFAULT_ID)
	assert_eq(layout.wall_finishes.get(_face(1, 5, WEST)), PackedStringArray(["brick", "brick", "cream"]), "first row wins")
	assert_false(layout.wall_finishes.has(_face(1, 6, WEST)), "unknown finish")
	assert_eq(layout.wall_finishes.get(_face(1, 7, WEST)), PackedStringArray(["stripes", "butter", "cream"]), "unknown colours")
	assert_eq(layout.wall_finishes.size(), 2)
	assert_eq(layout.wall_items, {_face(1, 9, WEST): &"menu_board"} as Dictionary[Vector3i, StringName],
		"overlaps, non-walls, floor items and unknown items are skipped")
	var copy: ShopEditor = _restore(layout)
	assert_eq(copy.walls.default_style, WallStyleDef.DEFAULT_ID)
	var check: EditCheck = copy.check_wall_finishes(copy.wall_lay_changes([_face(1, 9, WEST)] as Array[Vector3i], &"stripes", &"butter"))
	assert_eq([check.cost, check.refund], [2, 0], "nothing to refund over plain paint")
	snapshot["wall_finishes"] = "nonsense"
	snapshot["wall_items"] = 7
	assert_not_null(ShopEditor.from_dict(snapshot, LAYOUT, _content, errors))


func test_content_validation() -> void:
	assert_eq(ContentDB.validate_wall_styles(_content.wall_styles(), _content.swatches()), PackedStringArray())
	assert_eq(_content.wall_styles()[0].id, WallStyleDef.DEFAULT_ID)
	var broken: WallStyleDef = WallStyleDef.new()
	broken.id = &"brick"
	broken.display_name = " "
	broken.price = -1
	broken.default_swatch = &"neon"
	var defs: Array[WallStyleDef] = _content.wall_styles()
	defs.append(broken)
	var errors: PackedStringArray = ContentDB.validate_wall_styles(defs, _content.swatches())
	for expected: String in ["duplicated", "display_name", "price", "unknown colour"]:
		assert_true(Array(errors).any(func(error: String) -> bool: return error.contains(expected)), expected)
	var without: Array[WallStyleDef] = []
	for style: WallStyleDef in _content.wall_styles():
		if style.id != WallStyleDef.DEFAULT_ID:
			without.append(style)
	assert_true(Array(ContentDB.validate_wall_styles(without, _content.swatches())).any(
		func(error: String) -> bool: return error.contains("missing")))
	var wide: ItemDef = _content.item(&"menu_board").duplicate() as ItemDef
	wide.footprint = Vector2i(5, 1)
	assert_false(wide.placement_layer_valid(), "at most four faces wide")
	wide.footprint = Vector2i(2, 2)
	assert_false(wide.placement_layer_valid(), "one face deep")
	wide.footprint = Vector2i(2, 1)
	wide.solid = true
	assert_false(wide.placement_layer_valid(), "never solid")


func test_vibe_sees_the_old_wall_paint_and_no_decor_by_default() -> void:
	assert_eq(_editor.wall_vibe_swatch(), _editor.wall_swatch_id)
	assert_eq(_editor.decor_vibe_items(), [] as Array[ItemDef])
	var tuning: VibeTuning = load("res://data/balance/vibe.tres") as VibeTuning
	var before: VibeModel.Result = VibeModel.evaluate(VibeInputs.capture(_sim.world.grid, _content, _sim.menu,
		_editor.wall_swatch_id, _editor.floor_swatch_id), tuning)
	var after: VibeModel.Result = VibeModel.evaluate(VibeInputs.capture(_sim.world.grid, _content, _sim.menu,
		_editor.wall_vibe_swatch(), _editor.floor_vibe_swatch(), _editor.decor_vibe_items()), tuning)
	assert_eq(after.score, before.score)
	assert_eq(after.active_theme, before.active_theme)
	assert_true(_editor.paint_wall(&"sage"), "the legacy whole-shop paint still sets the default")
	assert_eq(_editor.walls.finish(_face(1, 6, WEST)).swatch, &"sage")
	# Guests see the dining room: the kitchen's walls never count.
	assert_true(_editor.apply_wall_finishes(_editor.wall_recolour_changes(_editor.wall_room_faces(_face(3, 1, NORTH)), &"charcoal")))
	assert_eq(_editor.wall_vibe_swatch(), &"sage")
	assert_true(_editor.apply_wall_finishes(_editor.wall_recolour_changes(_editor.wall_room_faces(_face(1, 6, WEST)), &"clay")))
	assert_eq(_editor.wall_vibe_swatch(), &"clay")
	# Wall decor in the dining room counts as decor; in the kitchen it does not.
	assert_true(_editor.hang(&"wall_art_sunrise", _face(1, 7, WEST)))
	assert_true(_editor.hang(&"wall_art_peaks", _face(3, 1, NORTH)))
	assert_eq(_editor.decor_vibe_items(), [_content.item(&"wall_art_sunrise")] as Array[ItemDef])
	var inputs: VibeModel.Inputs = VibeInputs.capture(_sim.world.grid, _content, _sim.menu,
		_editor.wall_vibe_swatch(), _editor.floor_vibe_swatch(), _editor.decor_vibe_items())
	var hung: VibeModel.Item = inputs.items.back()
	assert_eq(hung.definition_id, &"wall_art_sunrise")
	assert_true(hung.floor_decor, "takes no floor space")
	assert_true(hung.cells.is_empty())


func test_money_fuzz_round_trips_exactly() -> void:
	# A seeded run of wall edits, finishes and decor through the history: the
	# books always equal the ledger, a full undo returns to the start exactly,
	# and a save of any state loads back the same looks.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2610
	_editor.set_owner_level(4)
	var styles: Array[StringName] = [&"paint", &"wainscot", &"stripes", &"subway_tile", &"brick"]
	var items: Array[StringName] = [&"wall_art_sunrise", &"wall_art_peaks", &"menu_board", &"neon_open_sign"]
	var colours: Array[StringName] = [&"", &"cream", &"sage", &"brick", &"walnut"]
	var done: int = 0
	for step: int in 160:
		var faces: Array[Vector3i] = WallFaces.all(_sim.world.grid)
		var face: Vector3i = faces[rng.randi_range(0, faces.size() - 1)]
		match rng.randi_range(0, 6):
			0, 1:
				var run: Array[Vector3i] = _editor.wall_area_faces(face).slice(0, rng.randi_range(1, 6))
				done += int(_history.apply_wall_finishes(_editor.wall_lay_changes(run,
					styles[rng.randi_range(0, 4)], colours[rng.randi_range(0, 4)], colours[rng.randi_range(0, 4)])))
			2:
				done += int(_history.hang(items[rng.randi_range(0, 3)], face))
			3:
				var anchors: Array[Vector3i] = _editor.decor.anchors()
				if not anchors.is_empty():
					var anchor: Vector3i = anchors[rng.randi_range(0, anchors.size() - 1)]
					done += int(_history.rehang(anchor, face) if rng.randi() % 2 == 0 else _history.take_down(anchor) >= 0)
			4:
				var x: int = rng.randi_range(2, 11)
				var y0: int = rng.randi_range(5, 8)
				var kind: int = [SimGrid.Segment.WALL, SimGrid.Segment.NONE, SimGrid.Segment.DOORWAY][rng.randi_range(0, 2)]
				done += int(_history.apply_segments(_segments(x, y0, y0 + rng.randi_range(0, 1), kind)))
			5:
				if rng.randi() % 2 == 0:
					_history.undo()
				else:
					_history.redo()
			6:
				done += int(_history.apply_wall_finishes(_editor.wall_recolour_changes([face] as Array[Vector3i], colours[rng.randi_range(1, 4)])))
		assert_eq(_ledger.cash, START_CASH + _upgrades(), "step %d: books match the ledger" % step)
		for anchor: Vector3i in _editor.decor.anchors():
			assert_eq(WallFaces.span_problem(_sim.world.grid, anchor, _editor.decor.item(anchor).width), "",
				"step %d: decor only on walls" % step)
		for finished: Vector3i in _editor.walls.faces():
			assert_true(WallFaces.is_face(_sim.world.grid, finished), "step %d: finishes only on walls" % step)
	assert_true(done > 40, "the run did real edits (%d)" % done)
	var snapshot: Dictionary = _editor.to_dict()
	var errors: Array[String] = []
	var copy: ShopEditor = _restore(ShopEditor.from_dict(JSON.parse_string(JSON.stringify(snapshot)), LAYOUT, _content, errors))
	assert_eq(errors, [] as Array[String])
	assert_eq(copy.walls.to_rows(), _editor.walls.to_rows())
	assert_eq(copy.decor.to_rows(), _editor.decor.to_rows())
	var guard: int = 0
	while _history.can_undo() and guard < 400:
		guard += 1
		if not _history.undo():
			fail("undo refused: %s" % _history.last_refusal)
			break
	assert_eq(_ledger.cash, START_CASH, "a full undo nets to zero")
	assert_eq([_editor.walls.count(), _editor.decor.count()], [0, 0])


func _restore(layout: ShopLayout) -> ShopEditor:
	var errors: Array[String] = []
	var restored: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, false, true)
	assert_eq(errors, [] as Array[String])
	return ShopEditor.new(restored, _content, ShopEditBooks.new(_can_spend, _record), layout)


func _face(x: int, y: int, dir: int) -> Vector3i:
	return Vector3i(x, y, dir)


## West shell wall faces of the dining room from row y0, `count` rows south.
func _west(y0: int, count: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for y: int in range(y0, y0 + count):
		out.append(_face(1, y, WEST))
	return out


## A vertical run of `kind` on the grid line west of column x, rows y0..y1.
func _segments(x: int, y0: int, y1: int, kind: int) -> Dictionary[Vector3i, int]:
	var out: Dictionary[Vector3i, int] = {}
	for y: int in range(y0, y1 + 1):
		out[Vector3i(x, y, SimGrid.EDGE_WEST)] = kind
	return out


## Opens an outside window on `edge` through the editor (bought).
func _window(edge: Vector3i) -> void:
	var change: Dictionary[Vector3i, int] = {edge: SimGrid.Segment.WINDOW}
	assert_true(_editor.apply_segments(change), _editor.last_check.why)


func _wall(x: int, y0: int, y1: int, kind: int) -> void:
	_sim.world.grid.set_segments(_segments(x, y0, y1, kind))


## One column of lot floor east of the starting shell (the floor tests' lot).
func _lot_column() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(0, 10):
		out.append(Vector2i(14, y))
	return out


func _upgrades() -> int:
	return int(_ledger.day_totals(1).get(Ledger.UPGRADES, 0))


func _last_entry() -> Dictionary:
	var entries: Array[Dictionary] = _ledger.entries_for_day(1)
	return entries.back() if not entries.is_empty() else {}


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)
