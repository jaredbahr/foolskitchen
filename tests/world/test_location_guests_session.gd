extends TestCase
## Location guests (#471) in a real session: Main installs the active lot's
## guest mix and tags when it wires a site, and the home shop has none.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "location_guests_session"
const SEASIDE: StringName = &"seaside_cliff"
var _main: Node
var _old_dir: String
var _providers: Dictionary


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	SaveSystem.save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SaveSystem.save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_main_installs_the_active_lots_mix_and_none_at_home() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	var sim: RestaurantSim = _main.get("sim")
	assert_true(sim.lot_guest_mix.is_empty(), "the home shop keeps its reputation weights")
	assert_true(sim.lot_tags.is_empty())
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 30000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	_main.call("_on_next_day_pressed")
	(_main.get("reputation") as ReputationBook)._scores.assign([5, 5, 5, 5, 5])
	(_main.get("owner_progress") as OwnerProgress).career_tier = 3
	Economy.add_cash(100000 - Economy.cash, Ledger.OTHER, "test cash")
	assert_true(_main.call("buy_lot", SEASIDE))
	assert_true(_main.call("switch_site", SEASIDE))
	var lot: LotDef = (_main.get("content") as ContentDB).lot(SEASIDE)
	sim = _main.get("sim")
	assert_eq(sim.lot_guest_mix, lot.guest_mix, "the Seaside Cliff's own mix")
	assert_eq(sim.lot_tags, lot.tags)
	assert_true(sim.lot_guest_mix.has(&"tourist"))
	assert_true(_main.call("switch_site", SiteBook.HOME_ID))
	sim = _main.get("sim")
	assert_true(sim.lot_guest_mix.is_empty(), "back home, no mix")
