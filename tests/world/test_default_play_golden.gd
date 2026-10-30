extends TestCase
## FK-083 golden: default hours, the default menu and no drink station play
## exactly as main did before drinks, Café/Bar themes and opening hours
## (main 6f6495d). Two seeded production days; every value below was
## recorded on that main. The new arrival weights, visit draw and drink-add
## chance must draw nothing and change nothing here. Freeze the historical
## thick-divider fixture for that contract; the shipped thin layout has separate
## migration, service and balance-probe coverage. FK-120 also freezes demand
## at 1.0 in this detached historical context; actual default Day 1 draw-for-draw,
## later demand growth and replay have separate test_demand_session coverage.
## FK-121 selects genuine manual stock targets before ordinary planning.
## Director #257 intentionally rebaselined EXPECTED for faster cooking and
## $30 rent; that declared rent is charged by this historical fixture. Current
## automatic targets and rent have separate accounting and balance coverage.

const MainScene: PackedScene = preload("res://src/world/main.tscn")
const MANUAL_MAIN: GDScript = preload("res://tests/fixtures/manual_restock_main.gd")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
## Day -> [served, lost, sales, closing cash, customers RNG state, reviews RNG state].
const EXPECTED: Array = [[19, 2, 175, 347, "-3340690172320019757", "-3285513833473108564"], [19, 0, 172, 376, "1894290104310310707", "4855308092454611495"]]

var _main: Node
var _layout_backup: Dictionary = {}


func before_each() -> void:
	# Main owns this preloaded Resource. Scope the historical terrain override to
	# this test and restore it after freeing Main, including when assertions fail.
	var layout: ShopLayout = LAYOUT
	_layout_backup = {"rows": layout.rows.duplicate(), "rooms": layout.room_rows.duplicate(),
		"walls": layout.wall_segments.duplicate()}
	var legacy: ShopLayout = LegacyTier1Layout.make()
	layout.rows = legacy.rows.duplicate()
	layout.room_rows = legacy.room_rows.duplicate()
	layout.wall_segments = legacy.wall_segments.duplicate()


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
		_layout_backup.clear()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_two_default_days_match_main_draw_for_draw() -> void:
	_main = MainScene.instantiate()
	_main.set_script(MANUAL_MAIN)
	_main.set("historical_rent", 30)
	_main.set("use_saves", false)
	# Keep this pre-demand compatibility oracle's original two-day assertions.
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
