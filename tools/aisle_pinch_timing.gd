extends SceneTree
## Hand-run timing of the Build-mode aisle pinch pass (#391). Never a CI job.
##   godot --headless --path . --script tools/aisle_pinch_timing.gd
## Two shops: the deeper starter room, and the same shop on the tier-2 lease
## with every lot cell bought. For each it hovers a potted plant over every
## cell that takes one and prints, in milliseconds:
## - full: tracing every route of the standing shop once (AisleRules.pinches);
## - pinch: the pinch pass of one hover alone, given the proposed layout;
## - hover: one whole ShopEditor.check_buy, pinch pass included.
## Wall-clock times: run it on a quiet machine and compare runs made on the
## same machine only. The script also runs on a checkout from before #391
## (no resurvey), where `pinch` is the old full pass per hover.

const DEEPER: ShopLayout = preload("res://data/layouts/tier1_deeper.tres")
const LEASE: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
const RULES: GDScript = preload("res://src/sim/shop/aisle_rules.gd")
const ITEM: StringName = &"potted_plant"
const FULL_RUNS: int = 15

var _incremental: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	for method: Dictionary in RULES.get_script_method_list():
		if String(method["name"]) == "resurvey":
			_incremental = true
	var content: ContentDB = ContentDB.new()
	if not content.load_all().is_empty():
		print("Content failed to load")
		quit(1)
		return
	print("AISLE PINCH TIMING (%s), ms" % ("incremental re-survey" if _incremental else "full pass per hover"))
	print("%-22s %6s %7s | %-28s | %-28s" % ["shop", "cells", "full", "pinch  mean  median  p95  max",
		"hover  mean  median  p95  max"])
	_measure("deeper room", DEEPER, content, false)
	_measure("tier 2, all floor", LEASE.layout_for(DEEPER, 2), content, true)
	quit(0)


func _measure(label: String, layout: ShopLayout, content: ContentDB, buy_lot: bool) -> void:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(layout, content, 1, errors)
	var editor: ShopEditor = ShopEditor.new(sim, content, ShopEditBooks.new(_can_spend, _record), layout)
	editor.set_owner_level(5)
	if buy_lot:
		var lot: Array[Vector2i] = []
		var area: Rect2i = editor.footprint().lot
		for y: int in range(area.position.y, area.end.y):
			for x: int in range(area.position.x, area.end.x):
				if editor.footprint().can_hold(Vector2i(x, y)):
					lot.append(Vector2i(x, y))
		if not editor.apply_floor(lot, true):
			print("%s: the lot could not be bought (%s)" % [label, editor.last_check.why])
			return
	var grid: SimGrid = sim.world.grid
	var definition: ItemDef = content.item(ITEM)
	var full: Array[float] = []
	for _run_index: int in FULL_RUNS:
		var started: int = Time.get_ticks_usec()
		RULES.call("pinches", grid)
		full.append((Time.get_ticks_usec() - started) / 1000.0)
	var had: Array[Vector2i] = []
	had.assign(RULES.call("pinches", grid))
	var lot: Rect2i = editor.footprint().lot
	var live: Variant = RULES.call("survey", grid, lot) if _incremental else null
	editor.check_buy(ITEM, grid.bounds.position)  # fills the editor's own cache
	var pinch: Array[float] = []
	var hover: Array[float] = []
	for cell: Vector2i in grid.cells():
		if grid.can_place_def(definition, cell, 0) != SimGrid.PlaceResult.OK:
			continue
		var preview: SimGrid = _copy(grid)
		var placed: PlacedItem = preview.place_def(definition, cell, 0)
		var changed: Array[Vector2i] = []
		for group: Array[Vector2i] in [placed.cells, placed.seat_cells, placed.work_cells]:
			changed.append_array(group)
		var started: int = Time.get_ticks_usec()
		if _incremental:
			RULES.call("added_pinches", had, RULES.call("resurvey", live, preview, changed, false, lot))
		else:
			RULES.call("new_pinches_from", had, preview)
		pinch.append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		editor.check_buy(ITEM, cell)
		hover.append((Time.get_ticks_usec() - started) / 1000.0)
	full.sort()
	print("%-22s %6d %7.2f | %s | %s" % [label, pinch.size(), full[full.size() / 2], _stats(pinch), _stats(hover)])


static func _stats(times: Array[float]) -> String:
	if times.is_empty():
		return "no cells"
	var sorted: Array[float] = times.duplicate()
	sorted.sort()
	var total: float = 0.0
	for time: float in sorted:
		total += time
	return "%11.2f %7.2f %5.2f %5.2f" % [total / sorted.size(), sorted[sorted.size() / 2],
		sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], sorted[sorted.size() - 1]]


## The standing shop again: terrain, wall segments and items, as the editor
## builds a proposal.
static func _copy(grid: SimGrid) -> SimGrid:
	var copy: SimGrid = grid.terrain_copy()
	var segments: Dictionary[Vector3i, int] = {}
	for edge: Vector3i in grid.segment_edges():
		segments[edge] = grid.segment(edge)
	copy.set_segments(segments)
	for placed: PlacedItem in grid.items():
		copy.place_def(placed.def as ItemDef, placed.origin, placed.quarter_turns)
	return copy


func _can_spend(_amount: int) -> bool:
	return true


func _record(_amount: int, _category: StringName, _note: String = "") -> void:
	pass
