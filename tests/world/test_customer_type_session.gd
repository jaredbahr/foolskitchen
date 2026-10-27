extends TestCase
## Real Main configuration, named arrivals, owner-level refresh and morning load.
## These are source-authored tests; no engine result is implied.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const SLOT: String = "customer_type_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}
var _old_settings_path: String
var _old_settings_disk: bool
var _old_pending_settings: bool


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "customer_type_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_providers = SaveSystem._providers.duplicate()
	_old_settings_path = Preferences._file_path
	_old_settings_disk = Preferences._disk_enabled
	_old_pending_settings = Preferences._pending_volume_save
	Preferences._file_path = _save_dir.path_join("settings.cfg")
	Preferences._disk_enabled = false
	Preferences._pending_volume_save = false
	Clock.set_speed(0)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	Preferences._file_path = _old_settings_path
	Preferences._disk_enabled = _old_settings_disk
	Preferences._pending_volume_save = _old_pending_settings
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_default_main_spawns_authored_mix_on_exact_named_customers_stream() -> void:
	var main: Node = await _start(false)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	assert_not_null(sim.customer_types)
	assert_eq(sim.customer_types.types.size(), 4, "the playable default enables all authored types")
	assert_eq(sim.customer_level, 1)
	assert_eq(sim.rng, GameState.rng(&"customers"))
	assert_eq(sim.spawner.rng, GameState.rng(&"customers"))
	_one_tick_gaps(sim)
	var oracle: RandomNumberGenerator = RandomNumberGenerator.new()
	oracle.state = sim.rng.state
	var seen: Dictionary[StringName, bool] = {}
	assert_true(Clock.sim.start_service())
	for index: int in 64:
		var kind: CustomerType = CustomerTypePicker.choose(TYPES, 1, sim.review_book.average(), oracle)
		var entries: Array[Vector2i] = sim.world.grid.entries()
		var entry: Vector2i = entries[oracle.randi_range(0, entries.size() - 1)]
		# Level 1 is below every pair's party unlock: exactly main's single-guest draws.
		var count: int = kind.draw_party_size_at(oracle, 1)
		assert_eq(count, 1)
		var private_seeds: Array[int] = []
		for member: int in count:
			private_seeds.append(oracle.randi())
		oracle.randi_range(1, 1)
		main.call("run_ticks", 1)
		var arrivals: Array[CustomerAgent] = []
		var guests: Array[CustomerAgent] = sim.customers()
		arrivals.assign(guests.slice(guests.size() - count))
		assert_eq(arrivals.size(), count)
		for member: int in count:
			var guest: CustomerAgent = arrivals[member]
			assert_eq(guest.customer_type_id, kind.id)
			assert_eq(guest.customer_type_name, kind.display_name)
			assert_eq(guest.cell, entry)
			assert_eq(guest.rng.seed, private_seeds[member])
			if count > 1:
				assert_eq(guest.party, arrivals[0].party)
				assert_eq(guest.party.size(), count)
		assert_eq(sim.rng.state, oracle.state)
		assert_true([&"regular", &"student"].has(kind.id))
		seen[kind.id] = true
	assert_eq(seen.size(), 2, "actual Main arrivals include Students as well as Regulars")
	assert_false(FileAccess.file_exists(_path()), "non-saving test sessions remain isolated")


func test_morning_refresh_and_reload_use_restored_owner_level() -> void:
	var first: Node = await _start(true)
	var sim: RestaurantSim = first.get("sim") as RestaurantSim
	var progress: OwnerProgress = first.get("owner_progress") as OwnerProgress
	var saved_progress: Dictionary = progress.to_dict()
	saved_progress["total_xp"] = progress.threshold_for(4)
	saved_progress["level"] = 4
	assert_true(progress.from_dict(saved_progress))
	assert_eq(sim.customer_level, 1, "the existing world's level changes at the session hook")
	var oracle: RandomNumberGenerator = RandomNumberGenerator.new()
	oracle.state = sim.rng.state
	oracle.randi_range(sim.spawner.min_gap, sim.spawner.max_gap)
	first.call("_begin_morning")
	assert_eq(sim.customer_level, 4)
	assert_eq(sim.rng.state, oracle.state, "level refresh adds no draw beyond the ordinary morning gap")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	assert_eq(int(saved["data"]["owner"]["progress"]["level"]), 4)
	assert_false(saved["data"].has("customer_types"), "the authored mix has no new save section")
	_close(first)
	var restored: Node = await _start(true)
	var loaded: RestaurantSim = restored.get("sim") as RestaurantSim
	assert_eq((restored.get("owner_progress") as OwnerProgress).level, 4)
	assert_eq(loaded.customer_level, 4, "world replacement configures after saved progression restores")
	assert_eq(loaded.customer_types.types.size(), 4)
	assert_eq(loaded.rng, GameState.rng(&"customers"))
	assert_eq(loaded.customers().size(), 0, "morning loads do not manufacture guests")


func test_main_explicit_regular_catalogue_retains_legacy_arrival_draw_order() -> void:
	var regular: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	var single: CustomerType = TYPES.find_type(&"regular").duplicate() as CustomerType
	single.party_size_min = 1
	single.party_size_max = 1
	regular.types = [single]
	var main: Node = await _start(false, regular)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	assert_eq(sim.customer_types.types.size(), 1)
	_one_tick_gaps(sim)
	var oracle: RandomNumberGenerator = RandomNumberGenerator.new()
	oracle.state = sim.rng.state
	assert_true(Clock.sim.start_service())
	for index: int in 20:
		# Frozen pre-type draw order: entry, private seed, next gap. No selector draw.
		var entries: Array[Vector2i] = sim.world.grid.entries()
		var entry: Vector2i = entries[oracle.randi_range(0, entries.size() - 1)]
		var private_seed: int = oracle.randi()
		oracle.randi_range(1, 1)
		main.call("run_ticks", 1)
		var guest: CustomerAgent = sim.customers().back()
		assert_eq(guest.customer_type_id, &"regular")
		assert_eq(guest.customer_type_name, "Regular")
		assert_eq(guest.cell, entry)
		assert_eq(guest.rng.seed, private_seed)
		assert_eq(sim.rng.state, oracle.state)
	assert_eq(TYPES.types.size(), 4, "the fixture never edits shared authored content")


func _one_tick_gaps(sim: RestaurantSim) -> void:
	sim.spawner.min_gap = 1
	sim.spawner.max_gap = 1
	sim.start_day()


func _start(with_saves: bool, catalogue: CustomerTypeCatalogue = null) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var main: Node = MAIN.instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 11141)
	if catalogue != null:
		main.set("customer_type_catalogue", catalogue)
	_mains.append(main)
	tree.root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")
