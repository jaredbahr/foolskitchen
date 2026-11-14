extends TestCase
## A new game starts clean. Main resets each system by hand (`_new_game()`),
## and the autoloads, GameMode's static flag and the save slot all outlive the
## scene, so anything a played game leaves behind would show up in the next
## one. Each test plays a real game, starts a new one the way a player does
## (the title's New game, F10, or Continue on a save that is refused) with the
## reference seed, and compares it with a boot that nothing came before: every
## save section as the morning autosave would write it, the state that is not
## saved, and then both again after one identical day of service.
##
## Nothing is left out of the save sections. The one unsaved key that is
## allowed to differ is named in KEPT_BY_START_OVER.

const MAIN_SCENE: String = "res://src/world/main.tscn"
const TITLE_SCENE: String = "res://src/ui/title_screen.tscn"
const SLOT: String = "autosave"
## The reference boot and every new game under test.
const SEED: int = 4242
## The games played before them.
const PLAYED_SEED: int = 977
const FIXER: StringName = &"town_fixer_upper"
const MAX_REPORTED: int = 40

## Sections each played game must have changed before its new game, so a test
## cannot pass by comparing two untouched games. Only sections the test
## changes on purpose or that any service day moves are listed; the played
## games change more (random visits, bookings, reviews), which is not required.
const CAREER_DIRT: PackedStringArray = ["game_state", "clock", "economy", "pantry", "owner", "shop",
	"blueprints", "menu", "daily_special", "signature", "staff", "reorder", "demand", "business_history",
	"shop_records", "collection_toasts", "site_hours", "sites"]
const CREATIVE_DIRT: PackedStringArray = ["game_state", "clock", "pantry", "game_mode", "shop", "menu",
	"staff", "plates", "demand", "business_history", "shop_records", "cat", "aquarium"]
const SERVICE_DIRT: PackedStringArray = ["game_state", "clock", "economy", "pantry", "menu", "deliveries",
	"business_history", "shop_records"]
const SAVED_DIRT: PackedStringArray = ["game_state", "clock", "economy", "pantry", "owner", "shop",
	"blueprints", "menu", "daily_special", "staff", "reorder", "business_history", "shop_records",
	"collection_toasts", "site_hours"]

## F10 does not touch the speed control: the shared clock keeps the player's
## last speed, as it does from one day to the next. It moves nothing outside
## service, and opening sets the preferred speed. Quit to title pauses first.
const KEPT_BY_START_OVER: PackedStringArray = ["speed"]
## The event log says why a refused save became a new game.
const REFUSED_LOAD_LINES: PackedStringArray = ["starting a new game"]

## The reference boot, taken once per process before this file plays anything:
## "morning" and "day_two" are the save sections, "morning_state" and
## "day_two_state" the unsaved state beside them.
static var _reference_boot: Dictionary = {}

var _nodes: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_scene: Node
var _clock_processed: bool
var _old_sim: SimClock
var _old_attached_world: SimWorld
var _old_tick_driver: Callable
var _providers: Dictionary
var _next_seed: int = SEED
var _dirt: Dictionary[String, bool] = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "new_game_clean")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_scene = _tree().current_scene
	_clock_processed = Clock.is_processing()
	_old_sim = Clock.sim
	_old_attached_world = Clock.attached_world
	_old_tick_driver = Clock.tick_driver
	Clock.set_process(false)
	Clock.set_speed(0)
	_tree().node_added.connect(_seed_next_main)


func after_each() -> void:
	_tree().node_added.disconnect(_seed_next_main)
	_close_all()
	_tree().current_scene = _old_scene if is_instance_valid(_old_scene) else null
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _providers
	_reset_shared_state()
	# A closed Main only hands the clock back while its own world is attached,
	# so with two Mains in one test a played game's clock can be left behind.
	Clock.attach_world(_old_attached_world, _old_tick_driver)
	Clock.sim = _old_sim
	Clock.set_process(_clock_processed)


## The common case: a few days of career play with the shop, menu, staff and
## stock changed, a second site bought and walked into, then Quit to title and
## New game.
func test_title_new_game_after_career_play_matches_a_fresh_boot() -> void:
	var reference: Dictionary = _reference()
	var main: Node = _boot(PLAYED_SEED)
	_career_morning_edits(main)
	for day: int in 3:
		_play_day(main)
	_note_dirt(reference)
	_step("second site bought and entered", _buy_and_enter_second_site(main))
	_note_dirt(reference)
	_assert_played(CAREER_DIRT)
	var again: Node = await _new_game_from_title(main, false)
	_assert_clean(reference, again)


## Creative keeps its mode in a static flag and opens everything on day 1:
## the lease, trays, the cat and an aquarium all carry over unless reset.
func test_career_game_after_a_creative_game_matches_a_fresh_boot() -> void:
	var reference: Dictionary = _reference()
	_next_seed = PLAYED_SEED
	var title: TitleScreen = (load(TITLE_SCENE) as PackedScene).instantiate() as TitleScreen
	_nodes.append(title)
	_tree().root.add_child(title)
	_tree().current_scene = title
	title.start()
	title.request_new_game(true)
	await _settle()
	var main: Node = _tree().current_scene
	assert_true(GameMode.is_creative(), "the played game is Creative")
	_creative_morning_edits(main)
	_play_day(main)
	_note_dirt(reference)
	_assert_played(CREATIVE_DIRT)
	_next_seed = SEED
	var again: Node = await _new_game_from_title(main, false)
	_assert_clean(reference, again)


## F10 replaces the game from anywhere: here in the middle of a service, with
## guests seated, a delivery on its way, a bank loan open and the clock
## running fast.
func test_start_over_in_the_middle_of_service_matches_a_fresh_boot() -> void:
	var reference: Dictionary = _reference()
	var main: Node = _boot(PLAYED_SEED)
	_step("price", main.call("menu_set_price", &"burger", 15))
	# The goal rewards would cover tonight's bills; without them, with a full
	# crew to pay and the till emptied, closing opens a real bank loan.
	retire_opening_week(main)
	for candidate: StaffMember in (main.get("staff_roster") as StaffRoster).candidates():
		_step("hire %s" % candidate.display_name, main.call("staff_hire", candidate.id))
	_play_day(main, true)
	_step("a bank loan is open", Economy.loan.principal > 0)
	assert_true(Clock.sim.start_service(), "the shop opens")
	main.call("run_ticks", 1500)
	assert_eq(Clock.sim.phase, SimClock.Phase.OPEN, "service is still running")
	_step("order in the cart", main.call("stock_cart_set", &"bun", 3))
	_step("order placed", main.call("stock_place_order"))
	Clock.set_speed(2)
	_note_dirt(reference)
	_assert_played(SERVICE_DIRT)
	main.call("start_over")
	await _settle()
	_assert_clean(reference, _tree().current_scene, KEPT_BY_START_OVER)


## The hand-written reset's other job: Continue on a save that is refused
## starts a new game instead. Each damaged copy is refused at a different
## point, after its sections were read back over the session.
func test_new_game_after_a_refused_save_matches_a_fresh_boot() -> void:
	var reference: Dictionary = _reference()
	var main: Node = _boot(PLAYED_SEED)
	_career_morning_edits(main)
	_play_day(main)
	_note_dirt(reference)
	_assert_played(SAVED_DIRT)
	var path: String = _save_dir.path_join(SLOT + ".json")
	var saved: String = FileAccess.get_file_as_string(path)
	assert_false(saved.is_empty(), "the played game's morning autosave exists")
	if saved.is_empty():
		return
	# Each new game autosaves on its second morning, so the played game's save
	# is written back before the next damage.
	for damage: String in ["staff_ahead", "last_section_broken"]:
		_tree().current_scene.call("request_quit_to_title")
		await _settle()
		var title: TitleScreen = _tree().current_scene as TitleScreen
		assert_not_null(title, "quitting reaches the title")
		if title == null:
			return
		var document: Dictionary = JSON.parse_string(saved)
		var sections: Dictionary = document["data"]
		if damage == "staff_ahead":
			# Every provider accepts its section; the checks after them refuse.
			(sections["staff"] as Dictionary)["candidate_day"] = float(int(sections["clock"]["day"]) + 7)
		else:
			# The last provider refuses, after all the others restored or staged.
			sections[SaveSystem.keys()[SaveSystem.keys().size() - 1]] = {"broken": true}
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(document))
		file.close()
		DirAccess.remove_absolute(path + ".bak")
		title.continue_game()
		await _settle()
		assert_eq(Clock.sim.day, 1, "%s: the save was refused" % damage)
		_assert_clean(reference, _tree().current_scene, [], REFUSED_LOAD_LINES)


## Every scene change adds the next Main under the root before its _ready()
## starts the game: the one place a test can give it a seed. Everything else
## about the new game is the player's own route.
func _seed_next_main(node: Node) -> void:
	if node.scene_file_path == MAIN_SCENE and node.get_parent() == _tree().root:
		node.set("new_game_seed_override", _next_seed)


func _reference() -> Dictionary:
	if not _reference_boot.is_empty():
		return _reference_boot
	var main: Node = _boot(SEED)
	var boot: Dictionary = {"morning": _capture(), "morning_state": _unsaved(main)}
	_play_day(main)
	boot["day_two"] = _capture()
	boot["day_two_state"] = _unsaved(main)
	_close_all()
	SaveSystem.delete_slot(SLOT)
	_reset_shared_state()
	assert_eq((boot["morning"] as Dictionary).size(), SaveSystem.keys().size(), "every section was captured")
	_reference_boot = boot
	return _reference_boot


func _reset_shared_state() -> void:
	GameMode.set_creative(false)
	GameMode.request_new_game(false)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _boot(seed_value: int) -> Node:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	# The node_added hook seeds every Main as it enters the tree: this one gets
	# its own seed, and the new game that follows gets the reference seed.
	_next_seed = seed_value
	_nodes.append(main)
	_tree().root.add_child(main)
	_next_seed = SEED
	_tree().current_scene = main
	main.call("start")
	return main


func _close_all() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			if _tree().current_scene == node:
				_tree().current_scene = null
			if node.is_inside_tree():
				node.get_parent().remove_child(node)
			node.free()
	_nodes.clear()


## Quit to title, New game, and the replacement warning when a save exists.
func _new_game_from_title(main: Node, creative: bool) -> Node:
	var morning: bool = Clock.sim.phase == SimClock.Phase.MORNING
	main.call("request_quit_to_title")
	if not morning:
		(main.get_node("Overlay/QuitToTitle") as ConfirmationDialog).confirmed.emit()
	await _settle()
	var title: TitleScreen = _tree().current_scene as TitleScreen
	assert_not_null(title, "quitting reaches the title")
	if title == null:
		return null
	title.request_new_game(creative)
	assert_true(title.confirmation.visible, "the played game's save is about to be replaced")
	title.confirmation.confirmed.emit()
	await _settle()
	return _tree().current_scene


func _settle() -> void:
	for frame: int in 4:
		await _tree().process_frame
	if _tree().current_scene != null and not _nodes.has(_tree().current_scene):
		_nodes.append(_tree().current_scene)


## One real service and the real Next day button. `empty_till` takes the cash
## out by hand through the last minutes (the loan session tests empty it too),
## so the closing wages and rent open a real bank loan.
func _play_day(main: Node, empty_till: bool = false) -> void:
	assert_true(Clock.sim.start_service(), "the shop opens")
	for _guard: int in 600:
		if Clock.sim.phase == SimClock.Phase.CLOSED:
			break
		if empty_till and (Clock.sim.phase == SimClock.Phase.LAST_ORDERS \
				or Clock.sim.phase_tick >= Clock.sim.open_ticks - 60):
			Economy.add_cash(-Economy.cash, Ledger.OTHER)
		main.call("run_ticks", 20 if empty_till else 1000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED, "the day closes")
	main.call("_on_next_day_pressed")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING, "the next morning starts")


## Every registered section, in the shape the morning autosave writes.
func _capture() -> Dictionary:
	return SaveSystem.capture_sections(SaveSystem.keys())


## State a save does not hold but the next game would show or play from.
func _unsaved(main: Node, without: PackedStringArray = [], without_log_lines: PackedStringArray = []) -> Dictionary:
	var sim: RestaurantSim = main.get("sim")
	var world: SimWorld = main.get("world")
	var staff: Array[String] = []
	for member: StaffMember in (main.get("staff_roster") as StaffRoster).members():
		staff.append("%s %s %s" % [member.id, member.display_name, member.role])
	var people: Array[String] = []
	for agent: SimAgent in world.all_agents():
		people.append("%d %s %s %s" % [agent.id, agent.role, agent.display_name, agent.cell])
	var streams: Array[String] = []
	for system: StringName in GameState._rngs:
		streams.append("%s %d" % [system, GameState._rngs[system].state])
	# A listener left on an autoload is an old game still reacting in the new one.
	var listeners: Dictionary = {}
	for autoload: Node in [EventBus, Clock, Economy, GameState, SaveSystem, Sfx]:
		for entry: Dictionary in autoload.get_signal_list():
			var count: int = autoload.get_signal_connection_list(entry["name"]).size()
			if count > 0:
				listeners["%s.%s" % [autoload.name, entry["name"]]] = count
	var log_lines: Array[String] = []
	for line: String in world.event_log:
		var skipped: bool = false
		for part: String in without_log_lines:
			skipped = skipped or line.contains(part)
		if not skipped:
			log_lines.append(line)
	var state: Dictionary = {
		"cash": Economy.cash, "loan_owed": Economy.loan.principal, "has_borrowed": Economy.loan.has_borrowed,
		"ledger_entries": Economy.ledger._entries.size(), "active_site": String(Economy.active_site),
		"day": Clock.sim.day, "phase": Clock.sim.phase, "tick": Clock.sim.tick, "speed": Clock.speed,
		"opening_refusal": Clock.sim.opening_refusal, "clock_drives_this_world": Clock.attached_world == world,
		"seed": GameState.master_seed, "random_streams": streams,
		"creative": GameMode.is_creative(), "creative_requested": GameMode._requested_creative,
		"world_tick": world.now, "placed_items": world.grid.items().size(), "people": people,
		"staff": staff, "served_today": sim.served_today, "lost_today": sim.lost_today,
		"carry_capacity": sim.carry_capacity, "tray_level": main.get("tray_level"),
		"lease_expanded": main.get("lease_expanded"),
		"owner_level": (main.get("owner_progress") as OwnerProgress).effective_level(),
		"music": String(Sfx.music_context()), "autoload_listeners": listeners, "event_log": log_lines,
	}
	for key: String in without:
		state.erase(key)
	return state


## `main` is a new game: it must match the reference boot now and after a day.
func _assert_clean(reference: Dictionary, main: Node, kept: PackedStringArray = [],
		log_lines: PackedStringArray = []) -> void:
	assert_not_null(main, "a new game started")
	if main == null:
		return
	assert_eq(main.scene_file_path, MAIN_SCENE, "the new game is the shop")
	assert_true(bool(main.get("_started")), "the new game started")
	assert_eq(GameState.master_seed, SEED, "the new game took the reference seed")
	_assert_same("first morning", reference["morning"], _capture())
	_assert_same("first morning, not saved", _without(reference["morning_state"], kept),
		_unsaved(main, kept, log_lines))
	_play_day(main)
	_assert_same("after one day", reference["day_two"], _capture())
	_assert_same("after one day, not saved", _without(reference["day_two_state"], kept),
		_unsaved(main, kept, log_lines))


func _without(state: Dictionary, keys: PackedStringArray) -> Dictionary:
	var out: Dictionary = state.duplicate()
	for key: String in keys:
		out.erase(key)
	return out


func _assert_same(label: String, expected: Dictionary, actual: Dictionary) -> void:
	var lines: PackedStringArray = _differences(expected, actual, "")
	for index: int in mini(lines.size(), MAX_REPORTED):
		fail("%s: %s" % [label, lines[index]])
	if lines.size() > MAX_REPORTED:
		fail("%s: and %d more differences" % [label, lines.size() - MAX_REPORTED])


## Every leaf that differs, as "section.key[index]: reference -> new game".
func _differences(expected: Variant, actual: Variant, path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if expected is Dictionary and actual is Dictionary:
		var left: Dictionary = expected
		var right: Dictionary = actual
		var keys: Array = left.keys()
		for key: Variant in right:
			if not left.has(key):
				keys.append(key)
		for key: Variant in keys:
			var here: String = str(key) if path.is_empty() else "%s.%s" % [path, key]
			if not left.has(key):
				out.append("%s: absent -> %s" % [here, _short(right[key])])
			elif not right.has(key):
				out.append("%s: %s -> absent" % [here, _short(left[key])])
			else:
				out.append_array(_differences(left[key], right[key], here))
	elif expected is Array and actual is Array:
		var left_list: Array = expected
		var right_list: Array = actual
		if left_list.size() != right_list.size():
			out.append("%s: %d entries -> %d entries" % [path, left_list.size(), right_list.size()])
		for index: int in mini(left_list.size(), right_list.size()):
			out.append_array(_differences(left_list[index], right_list[index], "%s[%d]" % [path, index]))
	elif typeof(expected) != typeof(actual) or expected != actual:
		out.append("%s: %s -> %s" % [path, _short(expected), _short(actual)])
	return out


func _short(value: Variant) -> String:
	var text: String = JSON.stringify(value)
	return text if text.length() <= 120 else text.left(117) + "..."


## Remembers which sections the played game has changed so far. A section
## counts once it has differed from the reference morning at any check: the
## second site hides the first one's shop and staff inside "sites".
func _note_dirt(reference: Dictionary) -> void:
	var fresh: Dictionary = reference["morning"]
	var played: Dictionary = _capture()
	for key: String in fresh:
		if not _differences(fresh[key], played.get(key, null), key).is_empty():
			_dirt[key] = true


func _assert_played(expected: PackedStringArray) -> void:
	for key: String in expected:
		assert_true(_dirt.has(key), "the played game changed the '%s' section" % key)


func _step(name: String, accepted: Variant) -> void:
	assert_true(accepted is bool and accepted, "the played game's step was accepted: %s" % name)


## Morning choices a player makes through the panels, each by its own command.
func _career_morning_edits(main: Node) -> void:
	var world: SimWorld = main.get("world")
	var editor: ShopEditor = main.get("shop_editor")
	var roster: StaffRoster = main.get("staff_roster")
	_step("price", main.call("menu_set_price", &"burger", 15))
	_step("restaurant name", main.call("menu_set_restaurant_name", "Leaky Ladle"))
	_step("dish off", main.call("menu_set_enabled", &"tomato_soup", false))
	_step("special", main.call("menu_set_special", &"burger"))
	_step("owner look", main.call("owner_set_appearance", &"character-male-f", "Avery"))
	_step("auto order off", main.call("stock_set_auto", &"tomato", false))
	_step("order target", main.call("stock_set_target", &"bread", 20))
	_step("hours", main.call("set_opening_hours", 600, 1200))
	_step("job priority", _reprioritise_someone(main))
	_step("hire", main.call("staff_hire", roster.candidates()[0].id))
	_step("owner picked", main.call("select_agent", (main.get("sim") as RestaurantSim).owner_agent().id))
	_step("owner job", main.call("assign_owner_mode", &"floor"))
	# The Cozy Corner collection: three items and a patch of its floor. The
	# spare cash keeps a later price change from turning the purchases down.
	Economy.add_cash(300, Ledger.OTHER)
	_step("rug", _buy_anywhere(main, &"rug_round", &""))
	_step("painted lamp", _buy_anywhere(main, &"lamp_table_round", &"tomato"))
	_step("wall art", _hang_anywhere(main, &"wall_art_sunrise"))
	var plants: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"potted_plant")
	_step("a plant to copy", not plants.is_empty())
	if plants.is_empty():
		return
	_step("floor", main.call("shop_flooring", editor.lay_changes(
		editor.floor_room_cells(plants[0].origin).slice(0, 4), &"herringbone", &"walnut")))
	_let_toasts_play(main)
	_step("build on", main.call("set_build_active", true))
	main.call("_on_blueprint_code_paste_requested", BlueprintCode.encode(
		Blueprint.capture(world.grid, [plants[0].id] as Array[int], "Leafy corner")))
	_step("blueprint", (main.get("blueprint_library") as BlueprintLibrary).blueprints.size() == 1)
	_step("build off", main.call("set_build_active", false))


func _creative_morning_edits(main: Node) -> void:
	var roster: StaffRoster = main.get("staff_roster")
	_step("lease", main.call("lease_buy"))
	_step("small trays", main.call("tray_buy", 1))
	_step("big trays", main.call("tray_buy", 2))
	_step("cat", main.call("adopt_cat"))
	_step("aquarium", _buy_anywhere(main, &"aquarium", &""))
	_step("jukebox", _buy_anywhere(main, &"jukebox", &""))
	_step("hire", main.call("staff_hire", roster.candidates()[0].id))
	_step("restaurant name", main.call("menu_set_restaurant_name", "Sandbox"))
	# Nothing in play changes the plate count yet; the plate session test
	# sets it this way too.
	_step("plates", (main.get("sim") as RestaurantSim).kitchen.configure_plates(20))


## Tier 3 and the price of a lot take weeks of play, so the test grants them
## (as the lot session tests do); buying and walking in are the real commands.
func _buy_and_enter_second_site(main: Node) -> bool:
	(main.get("owner_progress") as OwnerProgress).career_tier = 3
	Economy.add_cash(100000, Ledger.OTHER)
	return main.call("buy_lot", FIXER) and main.call("switch_site", FIXER) and Economy.active_site == FIXER


func _reprioritise_someone(main: Node) -> bool:
	for member: StaffMember in (main.get("staff_roster") as StaffRoster).members():
		for job: StringName in StaffJobPriorities.JOBS:
			for level: int in [2, 1, 3]:
				if member.priority_state().to_dict().get(String(job), -1) != level \
						and main.call("staff_set_job_priority", member.id, job, level):
					return true
	return false


func _buy_anywhere(main: Node, def_id: StringName, swatch_id: StringName) -> bool:
	var editor: ShopEditor = main.get("shop_editor")
	for cell: Vector2i in (main.get("world") as SimWorld).grid.cells():
		if editor.check_buy(def_id, cell, 0).ok:
			return main.call("shop_buy", def_id, cell, 0, swatch_id)
	return false


func _hang_anywhere(main: Node, def_id: StringName) -> bool:
	var editor: ShopEditor = main.get("shop_editor")
	for cell: Vector2i in (main.get("world") as SimWorld).grid.cells():
		for side: int in 4:
			var face: Vector3i = Vector3i(cell.x, cell.y, side)
			if editor.check_hang(def_id, face).ok:
				return main.call("shop_hang", def_id, face)
	return false


## Toasts show one at a time for three real seconds each, and a collection
## counts as shown (and is saved as such) only once its own toast appears.
## This is those seconds passing.
func _let_toasts_play(main: Node) -> void:
	for _guard: int in 20:
		var timer: Timer = main.get_node_or_null("HUD/CollectionToastTimer") as Timer
		if timer == null or timer.is_stopped():
			return
		timer.stop()
		timer.timeout.emit()


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
