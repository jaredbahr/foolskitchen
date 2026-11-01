extends TestCase
## Two-day snapshot of current deterministic traffic in the historical FK-083
## thick-divider shop: default hours, food-only menu, seed7, manual stock,
## neutral demand and the fixture's $30 rent. Original rows came from main
## 6f6495d and later economy/mess updates; FK-124 records the changed physical
## service, cash and review consumption while retaining this complete context.
## Its private-seat barrier constrains staff service; current starter throughput,
## thin-layout save migration and demand growth have separate coverage.

const MainScene: PackedScene = preload("res://src/world/main.tscn")
const MANUAL_MAIN: GDScript = preload("res://tests/fixtures/manual_restock_main.gd")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
## Day -> [served, lost, sales, closing cash, customers RNG state, reviews RNG state].
const EXPECTED: Array = [[17, 4, 157, 309, "-3340690172320019757", "-6198928102474621411"], [18, 1, 163, 349, "1894290104310310707", "6227064950443097254"]]

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
	var legacy: ShopLayout = LegacyTier1Layout.make()
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
	var rows: Array = []
	for day: int in range(2):
		assert_true(Clock.sim.start_service())
		var guard: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 30:
			_main.call("run_ticks", 1000)
			guard += 1
		var sim: RestaurantSim = _main.get("sim") as RestaurantSim
		var book: Dictionary = Economy.ledger.day_totals(Clock.sim.day)
		rows.append([sim.served_today, sim.lost_today, int(book.get(Ledger.SALE, 0)), Economy.cash,
			str(GameState.rng(&"customers").state), str(GameState.rng(&"reviews").state)])
		assert_true(Clock.sim.next_day())
	assert_eq(rows, EXPECTED)
