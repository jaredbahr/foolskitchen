extends TestCase
## Two-day snapshot of current deterministic traffic in the historical FK-083
## thick-divider shop: default hours, food-only menu, seed7, manual stock,
## neutral demand and the fixture's $30 rent. Original rows came from main
## 6f6495d and later economy/mess updates; FK-124 records the changed physical
## service, cash and review consumption while retaining this complete context.
## #307 (staff serve the most impatient guests first) re-ordered which waiting
## guest staff reach first: day 1 serves and loses the same guests but a review
## differs; day 2 serves 17 (was 16), loses 2 (was 3), sales 154, pre-challenge cash 349.
## Its private-seat barrier constrains staff service; current starter throughput,
## thin-layout save migration and demand growth have separate coverage.
## The weekly review target now completes on day two, paying its authored
## $100 separately from operating sales and included in closing cash.

const MainScene: PackedScene = preload("res://src/world/main.tscn")
const MANUAL_MAIN: GDScript = preload("res://tests/fixtures/manual_restock_main.gd")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_deeper.tres")
## Day -> [served, lost, sales, closing cash, customers RNG state, reviews RNG state].
const EXPECTED: Array = [[18, 3, 166, 338, "-3340690172320019757", "-3285513833473108564"], [17, 2, 154, 449, "1894290104310310707", "6227064950443097254"]]

var _main: Node
var _layout_backup: Dictionary = {}


func before_each() -> void:
	# Main owns this preloaded Resource. Scope the complete historical geometry to
	# this test and restore it after freeing Main, including when assertions fail.
	var layout: ShopLayout = LAYOUT
	_layout_backup = {"rows": layout.rows.duplicate(), "rooms": layout.room_rows.duplicate(),
		"walls": layout.wall_segments.duplicate(), "legacy_rows": layout.legacy_rows.duplicate(),
		"placements": layout.placements.duplicate(), "spawns": layout.staff_spawns.duplicate(),
		"layout_id": layout.save_layout_id}
	# The recorded days ran with the original table row, before #320 turned it.
	var legacy: ShopLayout = LegacyTier1Layout.with_table_row(LegacyTier1Layout.make())
	layout.rows = legacy.rows.duplicate()
	layout.room_rows = legacy.room_rows.duplicate()
	layout.wall_segments = legacy.wall_segments.duplicate()
	layout.legacy_rows = legacy.legacy_rows.duplicate()
	layout.placements = legacy.placements.duplicate()
	layout.staff_spawns = legacy.staff_spawns.duplicate()
	layout.save_layout_id = legacy.save_layout_id


func after_each() -> void:
	if is_instance_valid(_main):
		if _main.is_inside_tree():
			_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	if not _layout_backup.is_empty():
		var layout: ShopLayout = LAYOUT
		layout.rows = _layout_backup["rows"]
		layout.room_rows = _layout_backup["rooms"]
		layout.wall_segments = _layout_backup["walls"]
		layout.legacy_rows = _layout_backup["legacy_rows"]
		layout.placements = _layout_backup["placements"]
		layout.staff_spawns = _layout_backup["spawns"]
		layout.save_layout_id = _layout_backup["layout_id"]
		_layout_backup.clear()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_two_legacy_manual_stock_days_match_recorded_snapshot() -> void:
	_main = MainScene.instantiate()
	_main.set_script(MANUAL_MAIN)
	_main.set("historical_rent", 30)
	_main.set("use_saves", false)
	# Keep the historical two-day context and all six recorded fields per day.
	# A per-session Resource prevents any change to shipped authored tuning.
	var neutral: DemandTuning = DemandTuning.new()
	neutral.reputation_factors = PackedFloat32Array([1, 1, 1])
	neutral.renown_max_factor = 1.0
	neutral.menu_per_extra_dish = 0.0
	neutral.menu_max_bonus = 0.0
	neutral.vibe_min_factor = 1.0
	neutral.vibe_max_factor = 1.0
	_main.set("demand_tuning", neutral)
	_main.set("new_game_seed_override", 7)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	# Exact books for this feature: no opening-week rewards (#494).
	retire_opening_week(_main)
	var rows: Array = []
	for day: int in range(2):
		assert_true(Clock.sim.start_service())
		var guard: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 30:
			_main.call("run_ticks", 1000)
			guard += 1
		var sim: RestaurantSim = _main.get("sim") as RestaurantSim
		var book: Dictionary = Economy.ledger.day_totals(Clock.sim.day)
		var weekly_entries: int = 0
		var weekly_amount: int = 0
		for entry: Dictionary in Economy.ledger.entries_for_day(Clock.sim.day):
			if entry.get("category") == Ledger.WEEKLY_CHALLENGE_BONUS:
				weekly_entries += 1
				weekly_amount += int(entry.get("amount", 0))
		var expected_weekly: int = 100 if day == 1 else 0
		assert_eq(weekly_entries, 1 if expected_weekly > 0 else 0,
			"day %d: the deterministic challenge completion settles exactly once" % Clock.sim.day)
		assert_eq(weekly_amount, expected_weekly,
			"day %d: weekly reward cash is recorded independently of sales" % Clock.sim.day)
		rows.append([sim.served_today, sim.lost_today, int(book.get(Ledger.SALE, 0)), Economy.cash,
			str(GameState.rng(&"customers").state), str(GameState.rng(&"reviews").state)])
		assert_true(Clock.sim.next_day())
	assert_eq(rows, EXPECTED)
