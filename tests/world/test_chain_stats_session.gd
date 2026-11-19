extends TestCase
## ChainStats against a real evening report (docs/CITY_MAP.md section 5): after
## a played day, a site's takings are the report's Sales and Tips (the tip jar
## included) and its net is the report's profit. Forces sunny weather so the
## day's guests do not depend on rain.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

var _main: Node


func after_each() -> void:
	if is_instance_valid(_main):
		if _main.is_inside_tree():
			_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_takings_and_net_match_the_evening_report() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 7)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	(_main.get("world") as SimWorld).weather.kind = WeatherState.Kind.SUNNY
	var day: int = Clock.sim.day
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 30000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: DayReport = _main.get("shown_report")
	assert_true(report != null and report.day == day)
	var home: StringName = SiteBook.HOME_ID
	var sold: int = int(report.income.get(Ledger.SALE, 0)) + int(report.income.get(Ledger.TIP, 0))
	assert_true(sold > 0, "guests paid")
	assert_eq(ChainStats.site_takings(Economy.ledger, day, home), sold, "takings are Sales plus Tips")
	assert_eq(ChainStats.site_net(Economy.ledger, day, home), report.profit(), "net is the report's profit")
	assert_eq(ChainStats.chain_takings(Economy.ledger, day, [home] as Array[StringName]), sold)
