extends TestCase
## D25/D26 edit fuzz (from the #207 review): seeded runs of wall finishes,
## wall decor (the OPEN sign in outside windows), interior and outer
## segments, floor expansion, flooring, whole-shop paint and undo/redo. Every
## step keeps the books equal to the ledger, refunds equal to what an edit
## took down, refused edits change nothing, a full unwind returns the start
## exactly and a save loads back the same shop.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const START_CASH: int = 5000

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _ledger: Ledger
var _log: Array[String] = []
var _fail_count: int = 0


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func _start() -> void:
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, null, false)
	_ledger = Ledger.new()
	_ledger.cash = START_CASH
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)


func _reload() -> void:
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snap, LAYOUT, _content, errors)
	_expect(errors.is_empty() and layout != null, "reload errors %s" % [errors])
	_sim = RestaurantSim.create(layout, _content, 1, errors, null, false, true)
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), layout)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)
	var again: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	_expect(_same(snap, again), "save round trip differs:\n%s\n%s" % [JSON.stringify(snap), JSON.stringify(again)])


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fail_count += 1
		if _fail_count < 25:
			fail(msg + " | last ops: " + ", ".join(_log.slice(maxi(0, _log.size() - 6))))


func _same(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a, "", true) == JSON.stringify(b, "", true)


func _state() -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(_editor.to_dict())), "", true)


func _diff(a: String, b: String) -> String:
	var da: Dictionary = JSON.parse_string(a)
	var db: Dictionary = JSON.parse_string(b)
	var out: String = ""
	for k: String in da:
		if JSON.stringify(da[k]) != JSON.stringify(db.get(k)):
			out += "\n  %s: WAS %s\n      NOW %s" % [k, JSON.stringify(da[k]).left(600), JSON.stringify(db.get(k)).left(600)]
	return out


func _invariants(step: int) -> void:
	var grid: SimGrid = _sim.world.grid
	_expect(_ledger.cash == START_CASH + _upgrades(), "step %d books" % step)
	for edge: Vector3i in grid.segment_edges():
		if grid.segment(edge) in [SimGrid.Segment.WINDOW, SimGrid.Segment.DOORWAY]:
			_expect(WallRules.has_continuing_wall(grid, edge), "step %d freestanding window/doorway %s" % [step, edge])
	for face: Vector3i in _editor.walls.faces():
		_expect(WallFaces.is_face(grid, face), "step %d finish on non-face %s" % [step, face])
	for anchor: Vector3i in _editor.decor.anchors():
		var h: WallDecor.Hung = _editor.decor.item(anchor)
		_expect(h.problem_on(grid) == "", "step %d decor on bad span %s" % [step, anchor])
		_expect(_content.item(h.def_id) != null, "orphan def")
	var covered: int = 0
	for anchor: Vector3i in _editor.decor.anchors():
		covered += _editor.decor.item(anchor).width
	_expect(covered == _editor.decor.covered_faces().size(), "step %d cover map out of sync" % step)


func _run(seed_value: int, steps: int) -> Array:
	_start()
	_log.clear()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var styles: Array[StringName] = [&"paint", &"wainscot", &"stripes", &"subway_tile", &"brick"]
	var items: Array[StringName] = [&"wall_art_sunrise", &"wall_art_peaks", &"menu_board", &"neon_open_sign"]
	var colours: Array[StringName] = [&"", &"cream", &"sage", &"brick", &"walnut", &"charcoal"]
	var fstyles: Array[StringName] = [&"planks", &"checker", &"herringbone", &"small_tile"]
	var base_state: String = _state()
	var base_cash: int = _ledger.cash
	var stats: Dictionary = {}
	for step: int in steps:
		var grid: SimGrid = _sim.world.grid
		var faces: Array[Vector3i] = WallFaces.all(grid)
		var face: Vector3i = faces[rng.randi_range(0, faces.size() - 1)]
		var op: int = rng.randi_range(0, 14)
		var before_state: String = _state()
		var before_cash: int = _ledger.cash
		var ok: bool = false
		var name: String = ""
		var walls_before: Array[Vector3i] = _editor.walls.faces()
		var decor_before: Array[Vector3i] = _editor.decor.anchors()
		var looks_before: Dictionary = {}
		for f0: Vector3i in walls_before:
			looks_before[f0] = _editor.walls.finish(f0).style
		var decor_defs: Dictionary = {}
		for a0: Vector3i in decor_before:
			decor_defs[a0] = _editor.decor.item(a0).def_id
		var segs_before: Dictionary[Vector3i, int] = _editor.segments()
		var floor_looks_before: Dictionary = {}
		for c0: Vector2i in _editor.floors.cells():
			floor_looks_before[c0] = _editor.floors.finish(c0).style
		var terrain_before: Dictionary = {}
		for c0: Vector2i in grid.cells():
			terrain_before[c0] = grid.terrain(c0)
		match op:
			0, 1:
				var pick: int = rng.randi_range(0, 2)
				var run: Array[Vector3i] = [face]
				if pick == 0:
					run.assign(_editor.wall_area_faces(face).slice(0, rng.randi_range(1, 8)))
				elif pick == 1:
					run.assign(_editor.wall_room_faces(face))
				name = "lay"
				ok = _history.apply_wall_finishes(_editor.wall_lay_changes(run, styles[rng.randi_range(0, 4)],
					colours[rng.randi_range(0, 5)], colours[rng.randi_range(0, 5)]))
			2:
				name = "recolour"
				ok = _history.apply_wall_finishes(_editor.wall_recolour_changes(_editor.wall_area_faces(face), colours[rng.randi_range(1, 5)]))
			3, 4:
				name = "hang"
				var def_id: StringName = items[rng.randi_range(0, 3)]
				var price: int = _content.item(def_id).price
				var target: Vector3i = face
				var windows: Array[Vector3i] = WallFaces.windows(grid)
				if def_id == &"neon_open_sign" and not windows.is_empty() and rng.randi() % 4 != 0:
					target = windows[rng.randi_range(0, windows.size() - 1)]
				ok = _history.hang(def_id, target)
				if ok:
					_expect(_ledger.cash == before_cash - price, "hang price exact")
			5:
				var anchors: Array[Vector3i] = _editor.decor.anchors()
				if not anchors.is_empty():
					var anchor: Vector3i = anchors[rng.randi_range(0, anchors.size() - 1)]
					if rng.randi() % 2 == 0:
						name = "rehang"
						var windows: Array[Vector3i] = WallFaces.windows(grid)
						var target: Vector3i = windows[rng.randi_range(0, windows.size() - 1)] \
							if _editor.decor.item(anchor).window and not windows.is_empty() else face
						ok = _history.rehang(anchor, target)
						if ok:
							_expect(_ledger.cash == before_cash, "rehang free")
					else:
						name = "takedown"
						var refund: int = ShopEditor.sale_refund(_editor.hung_definition(anchor))
						ok = _history.take_down(anchor) >= 0
						if ok:
							_expect(_ledger.cash == before_cash + refund, "takedown exact")
			6, 7:
				# Interior segments anywhere, incl. kitchen and grown parts.
				var cells: Array[Vector2i] = grid.cells()
				var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
				var vertical: bool = rng.randi() % 2 == 0
				var length: int = rng.randi_range(1, 4)
				var kind: int = [SimGrid.Segment.WALL, SimGrid.Segment.WALL, SimGrid.Segment.NONE,
					SimGrid.Segment.DOORWAY, SimGrid.Segment.WINDOW][rng.randi_range(0, 4)]
				var changes: Dictionary[Vector3i, int] = {}
				for i: int in length:
					var e: Vector3i = Vector3i(c.x, c.y + i, SimGrid.EDGE_WEST) if vertical else Vector3i(c.x + i, c.y, SimGrid.EDGE_NORTH)
					changes[e] = kind
				name = "segments"
				var check: EditCheck = _editor.check_segments(changes)
				ok = _history.apply_segments(changes)
				if ok:
					var loss: int = _loss_sum(looks_before, decor_defs, check)
					var seg_refund: int = 0
					var seg_cost: int = 0
					for e: Vector3i in check.changes:
						var od: WallKindDef = _content.wall_kind_for(segs_before.get(e, SimGrid.Segment.NONE))
						var nd: WallKindDef = _content.wall_kind_for(check.changes[e])
						seg_refund += floori(od.price / 2.0) if od != null else 0
						seg_cost += nd.price if nd != null else 0
					_expect(check.refund == seg_refund + loss and check.cost == seg_cost, "segments refund %d != %d + loss %d" % [check.refund, seg_refund, loss])
					_expect(_ledger.cash == before_cash + check.refund - check.cost, "segments cash = check")
			8:
				# Outer window or back door on the shell.
				var outer: Array[Vector3i] = []
				for c: Vector2i in grid.cells():
					if grid.terrain(c) != SimGrid.Terrain.FLOOR:
						continue
					for d: Vector2i in WallFaces.DIRS:
						var e: Vector3i = SimGrid.edge_between(c, c + d)
						if WallRules.outer_side(grid, e) != Vector2i.ZERO:
							outer.append(e)
				if not outer.is_empty():
					var e: Vector3i = outer[rng.randi_range(0, outer.size() - 1)]
					var kind: SimGrid.Segment = _editor.next_segment(e, SimGrid.Segment.DOORWAY if rng.randi() % 3 == 0 else SimGrid.Segment.WINDOW)
					name = "outer %s" % kind
					var check: EditCheck = _editor.check_segments({e: kind} as Dictionary[Vector3i, int])
					ok = _history.apply_segments({e: kind} as Dictionary[Vector3i, int])
					if ok:
						_expect(_ledger.cash == before_cash + check.refund - check.cost, "outer cash = check")
			9:
				var adding: bool = rng.randi() % 3 != 0
				var cells: Array[Vector2i] = []
				if adding:
					var x0: int = [-1, 14, rng.randi_range(-1, 14)][rng.randi_range(0, 2)]
					var y0: int = rng.randi_range(-3, 9)
					for x: int in range(x0, x0 + rng.randi_range(1, 2)):
						for y: int in range(y0, y0 + rng.randi_range(1, 4)):
							cells.append(Vector2i(x, y))
				else:
					var bought: Array[Vector2i] = _editor.bought_floor()
					if not bought.is_empty():
						var start: int = rng.randi_range(0, bought.size() - 1)
						cells = bought.slice(start, start + rng.randi_range(1, 4))
				name = "floor %s" % adding
				if not cells.is_empty():
					var check: EditCheck = _editor.check_floor(cells, adding)
					ok = _history.apply_floor(cells, adding)
					if ok:
						_expect(_ledger.cash == before_cash + check.refund - check.cost, "floor cash = check")
						var loss: int = _loss_sum(looks_before, decor_defs, check)
						var fr: int = 0
						var gone_cells: int = 0
						for c0: Vector2i in terrain_before:
							if terrain_before[c0] == SimGrid.Terrain.FLOOR and _sim.world.grid.terrain(c0) != SimGrid.Terrain.FLOOR:
								gone_cells += 1
								if floor_looks_before.has(c0):
									var fs: FloorStyleDef = _content.floor_style(floor_looks_before[c0])
									fr += floori(fs.price / 2.0)
						var now_segs: Dictionary[Vector3i, int] = _editor.segments()
						var sr: int = 0
						for e: Vector3i in segs_before:
							if not now_segs.has(e) or now_segs[e] != segs_before[e]:
								var od: WallKindDef = _content.wall_kind_for(segs_before[e])
								sr += floori(od.price / 2.0) if od != null else 0
						var expect_refund: int = loss + fr + sr + (0 if adding else check.floor_cells.size() * 7)
						_expect(check.refund == expect_refund, "floor refund %d != loss %d + floorlooks %d + segs %d + cells %d" % [check.refund, loss, fr, sr, gone_cells])
			10:
				name = "flooring"
				var c: Vector2i = WallFaces.cell(face)
				var room: Array[Vector2i] = FloorFinishes.room_cells(grid, c)
				ok = _history.apply_flooring(_editor.lay_changes(room.slice(0, rng.randi_range(1, 10)),
					fstyles[rng.randi_range(0, 3)], &""))
			11:
				name = "paint wall"
				ok = _history.paint(&"wall" if rng.randi() % 2 == 0 else &"floor", colours[rng.randi_range(0, 5)])
			12, 13:
				name = "undo/redo"
				for k: int in rng.randi_range(1, 4):
					ok = (_history.undo() if rng.randi() % 3 != 0 else _history.redo()) or ok
			14:
				name = "unwind+reload"
				# Full unwind to base, check exact, then redo all and reload.
				var top_state: String = _state()
				var top_cash: int = _ledger.cash
				var undone: int = 0
				var labels: Array[String] = []
				while _history.can_undo():
					labels.append(_history.undo_label())
					if not _history.undo():
						_expect(false, "undo stuck: %s (%s)" % [_history.last_refusal, _history.undo_label()])
						break
					undone += 1
				_expect(_ledger.cash == base_cash, "unwind cash %d != base %d" % [_ledger.cash, base_cash])
				if _state() != base_state:
					_expect(false, "unwind state differs (%d undos %s): %s" % [undone, labels, _diff(base_state, _state())])
				for r: int in undone:
					if not _history.redo():
						_expect(false, "redo stuck: %s (%s)" % [_history.last_refusal, _history.redo_label()])
						break
				_expect(_ledger.cash == top_cash, "rewind cash")
				if _state() != top_state:
					_expect(false, "redo-all state differs: %s" % _diff(top_state, _state()))
				_reload()
				base_state = _state()
				base_cash = _ledger.cash
				ok = true
		_log.append("%d:%s%s" % [step, name, "+" if ok else "-"])
		stats[name.get_slice(" ", 0)] = int(stats.get(name.get_slice(" ", 0), 0)) + int(ok)
		if not ok and op != 12 and op != 13:
			_expect(_state() == before_state and _ledger.cash == before_cash, "step %d refused op changed state" % step)
		_invariants(step)
	return [_state(), _ledger.cash, stats]


func _loss_sum(looks_before: Dictionary, decor_defs: Dictionary, check: EditCheck) -> int:
	var grid: SimGrid = _sim.world.grid
	var sum: int = 0
	var lost_f: Array[Vector3i] = []
	for f0: Vector3i in looks_before:
		if not _editor.walls.faces().has(f0):
			lost_f.append(f0)
			_expect(not WallFaces.is_face(grid, f0), "finish dropped from a face that still exists %s" % f0)
			sum += floori(_content.wall_style(looks_before[f0]).price / 2.0)
	WallFaces.sort(lost_f)
	var cl: Array[Vector3i] = check.lost_finishes.duplicate()
	WallFaces.sort(cl)
	_expect(cl == lost_f, "lost_finishes %s != dropped %s" % [cl, lost_f])
	var lost_d: Array[Vector3i] = []
	for a0: Vector3i in decor_defs:
		if _editor.decor.item(a0) == null or _editor.decor.item(a0).def_id != decor_defs[a0]:
			lost_d.append(a0)
			sum += ShopEditor.sale_refund(_content.item(decor_defs[a0]))
	WallFaces.sort(lost_d)
	var dl: Array[Vector3i] = check.lost_decor.duplicate()
	WallFaces.sort(dl)
	_expect(dl == lost_d, "lost_decor %s != dropped %s" % [dl, lost_d])
	return sum


func test_seeded_edits_keep_money_saves_and_undo_exact() -> void:
	for seed_value: int in [3, 11, 26]:
		_run(seed_value, 200)
	assert_eq(_fail_count, 0)


func test_a_run_is_deterministic() -> void:
	var a: Array = _run(77, 120)
	var b: Array = _run(77, 120)
	assert_eq(a[0], b[0])
	assert_eq(a[1], b[1])


func _upgrades() -> int:
	return int(_ledger.day_totals(1).get(Ledger.UPGRADES, 0))


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)


func test_whole_shop_paint_undo_restores_each_face_and_cell() -> void:
	_start()
	var face: Vector3i = Vector3i(1, 6, 3)
	assert_true(_history.apply_wall_finishes(_editor.wall_recolour_changes([face] as Array[Vector3i], &"sage")))
	var cell: Vector2i = Vector2i(3, 6)
	assert_true(_history.apply_flooring(_editor.recolour_changes([cell] as Array[Vector2i], &"sage")))
	var before: String = _state()
	assert_true(_history.paint(&"wall", &"sage"))
	assert_true(_history.paint(&"floor", &"sage"))
	assert_true(_history.undo())
	assert_true(_history.undo())
	assert_eq(_editor.walls.finish(face).swatch, &"sage", "the face kept its own sage")
	assert_eq(_editor.floors.finish(cell).swatch, &"sage", "the cell kept its own sage")
	assert_eq(_state(), before, "undo is exact")
	assert_true(_history.redo())
	assert_true(_history.redo())
	assert_eq(_editor.wall_swatch_id, &"sage")
	while _history.can_undo():
		assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.walls.count(), 0, "a full unwind is the starting shop")
	assert_eq(_editor.floors.cells().size(), 0)
	assert_eq(_ledger.cash, START_CASH)


func test_a_wide_item_never_spans_a_shell_face_and_an_interior_face() -> void:
	_start()
	var grid: SimGrid = _sim.world.grid
	grid.set_segments({Vector3i(7, 5, SimGrid.EDGE_NORTH): SimGrid.Segment.WALL} as Dictionary[Vector3i, int])
	var anchor: Vector3i = Vector3i(7, 5, 0)
	assert_eq(WallFaces.kind(grid, anchor), WallFaces.Kind.INTERIOR)
	assert_eq(WallFaces.kind(grid, Vector3i(8, 5, 0)), WallFaces.Kind.SHELL)
	assert_eq(WallFaces.span_problem(grid, anchor, 2), WallFaces.TWO_WALLS)
	assert_eq(_editor.check_hang(&"menu_board", anchor).why, "This would span two different walls")
	assert_true(_editor.check_hang(&"menu_board", Vector3i(8, 5, 0)).ok, "two shell faces are fine")


func test_older_and_junk_saves_load_without_errors() -> void:
	_start()
	assert_true(_history.apply_floor([Vector2i(14, 5), Vector2i(14, 6)] as Array[Vector2i], true), _editor.last_check.why)
	assert_true(_history.apply_wall_finishes(_editor.wall_lay_changes([Vector3i(14, 5, 1)] as Array[Vector3i], &"brick", &"brick")))
	assert_true(_history.hang(&"menu_board", Vector3i(14, 5, 1)), _editor.last_check.why)
	var base: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	for v: int in [5, 4, 3, 2, 1]:
		var legacy: Dictionary = base.duplicate(true)
		legacy["version"] = v
		for key: String in ["wall_style_id", "wall_finishes", "wall_items"]:
			legacy.erase(key)
		if v < 5:
			for key: String in ["floor_style_id", "floors"]:
				legacy.erase(key)
		if v < 4:
			legacy.erase("rooms")
		if v < 3:
			legacy.erase("floor")
		var errors: Array[String] = []
		var layout: ShopLayout = ShopEditor.from_dict(legacy, LAYOUT, _content, errors)
		assert_eq(errors, [] as Array[String], "v%d" % v)
		assert_not_null(layout, "v%d" % v)
		if layout != null:
			assert_eq(layout.wall_finishes.size(), 0, "v%d is plain paint" % v)
			assert_eq(layout.wall_items.size(), 0, "v%d hangs nothing" % v)
	var junk: Dictionary = base.duplicate(true)
	junk["wall_finishes"] = [[1.5, 6, 3, "brick", "", ""], [1, 6, 3, null, "", ""], [1, 6, 3, "brick", 7, []], [99999999, 1, 0, "brick", "", ""], {}]
	junk["wall_items"] = [[1, 6, 3, null], [14, 5, 1, "menu_board"], [14, 6, 1, "menu_board"], [1, 6, 3, 5]]
	var junk_errors: Array[String] = []
	var junk_layout: ShopLayout = ShopEditor.from_dict(junk, LAYOUT, _content, junk_errors)
	assert_eq(junk_errors, [] as Array[String], "bad wall rows never refuse a save")
	assert_not_null(junk_layout)
	if junk_layout != null:
		assert_eq(junk_layout.wall_items.size(), 1, "one board: the overlapping one is skipped")
