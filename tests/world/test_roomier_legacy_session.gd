extends TestCase
## Real SaveSystem startup, including saves without any shop or staff section.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const NEW: ShopLayout = preload("res://data/layouts/tier1_deeper.tres")
## #389: the 7-row dining room new games had before the deeper starter.
const ROOMIER: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const ORIGINAL: ShopLayout = preload("res://data/layouts/tier1_original.tres")
const LEASE: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
const SLOT: String = "roomier_legacy_session"
const REJECT: String = "roomier_test_late_reject"

var _main: Node
var _old_dir: String
var _dir: String
var _providers: Dictionary[String, Dictionary] = {}
var _old_clock_processing: bool
var _old_speed: int
var _preferences: SettingsPreferences
var _old_preferences: Dictionary = {}
var _reject_reached: bool = false
var _old_was_staged: bool = false


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _dir
	SaveSystem.delete_slot(SLOT)
	_old_clock_processing = Clock.is_processing()
	_old_speed = Clock.speed
	Clock.set_process(false)
	Clock.set_speed(0)
	_preferences = (Engine.get_main_loop() as SceneTree).root.get_node("Preferences") as SettingsPreferences
	for key: String in ["_file_path", "_disk_enabled", "_pending_volume_save"]:
		_old_preferences[key] = _preferences.get(key)
	_preferences.set("_file_path", _dir.path_join("preferences.cfg"))
	_preferences.set("_disk_enabled", false)
	_preferences.set("_pending_volume_save", false)
	_reject_reached = false
	_old_was_staged = false


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	for key: String in _old_preferences:
		_preferences.set(key, _old_preferences[key])
	Economy.reset(0)
	GameState.new_run(1)
	Clock.set_speed(_old_speed)
	Clock.set_process(_old_clock_processing)


func test_only_a_new_shop_uses_the_deeper_base_and_its_next_morning_roundtrips() -> void:
	_start()
	_assert_base(NEW)
	assert_eq(_document()["data"]["shop"]["layout_id"], "tier1_deeper")
	var expected: Dictionary = _editor().to_dict()
	_empty_next_morning()
	assert_eq(_document()["data"]["shop"]["layout_id"], "tier1_deeper")
	_close()
	_start()
	assert_eq(Clock.sim.day, 2)
	_assert_base(NEW)
	assert_eq(_editor().to_dict(), expected)


func test_pre_roomier_v8_restores_old_looks_and_keeps_old_lease_bounds_after_reload() -> void:
	_start()
	var doc: Dictionary = _document()
	var snapshot: Dictionary = _original_snapshot(true)
	doc["data"]["shop"] = snapshot
	_write(doc)
	_close()
	_start()
	_assert_base(ORIGINAL)
	assert_eq(_editor().to_dict(), _without_trays(snapshot))
	var morning: String = _saved_text()
	var progress: OwnerProgress = _main.get("owner_progress") as OwnerProgress
	progress.award_bonus(progress.threshold_for(3))
	# The lease offer needs career Tier 2 (D30), which a real close grants here.
	progress.raise_career_tier(preload("res://data/balance/career_tiers.tres") as CareerTierTuning, 3.0)
	(_main.get("menu_settings") as MenuSettings).set_owner_level(progress.level)
	_editor().set_owner_level(progress.level)
	Economy.cash = LEASE.deposit + 10000 # Explicit transaction funding fixture.
	assert_true(_main.call("lease_buy"))
	var old_tier_two: ShopLayout = LEASE.layout_for(ORIGINAL, 2)
	assert_eq(_editor().footprint().lot, ShopFootprint.from_layout(old_tier_two).lot)
	var cells: Array[Vector2i] = []
	for y: int in range(ShopFootprint.from_layout(ORIGINAL).lot.position.y - 1, 0):
		cells.append(Vector2i(2, y))
	assert_true(_main.call("shop_floor", cells, true), _editor().last_check.why)
	var expected_rooms: Dictionary[Vector2i, int] = (_main.get("world") as SimWorld).grid.rooms()
	assert_eq(_saved_text(), morning, "lease and old-shop edits still wait for the morning checkpoint")
	_empty_next_morning()
	var expected: Dictionary = _editor().to_dict()
	_close()
	_start()
	_assert_base(ORIGINAL, 2)
	assert_eq(_editor().to_dict(), expected)
	assert_eq(_editor().bought_floor(), cells)
	assert_eq((_main.get("world") as SimWorld).grid.rooms(), expected_rooms)
	assert_eq(_editor().footprint().lot, ShopFootprint.from_layout(old_tier_two).lot,
		"reloading an old lease applies its extra margins once")


## #389: a game saved in the earlier 7-row dining room keeps that room and
## its furniture after the deeper starter became the default, and saves it
## under the same name again.
func test_roomier_save_keeps_its_seven_row_dining_room() -> void:
	_start()
	var doc: Dictionary = _document()
	var snapshot: Dictionary = _snapshot_of(ROOMIER)
	assert_eq(snapshot["layout_id"], "tier1_roomier")
	doc["data"]["shop"] = snapshot
	_write(doc)
	_close()
	_start()
	_assert_base(ROOMIER)
	assert_eq((_main.get("world") as SimWorld).grid.bounds.size, Vector2i(16, 14))
	assert_eq(_editor().to_dict(), _without_trays(snapshot))
	assert_eq((_main.get("sim") as RestaurantSim).staff_spawns, ROOMIER.staff_spawns)
	_empty_next_morning()
	assert_eq(_document()["data"]["shop"]["layout_id"], "tier1_roomier")
	_close()
	_start()
	_assert_base(ROOMIER)


func test_missing_shop_and_staff_sections_rebuild_original_world_after_new_world_initialization() -> void:
	_start()
	var doc: Dictionary = _document()
	doc["data"].erase("shop")
	doc["data"].erase("staff")
	_write(doc)
	_close()
	_start()
	_assert_base(ORIGINAL)
	assert_eq(_editor().to_dict()["items"], _without_trays(_original_snapshot(false))["items"])
	var loaded: ShopLayout = _main.get("_loaded_layout") as ShopLayout
	assert_not_null(loaded, "the missing section still installs an explicit original-base layout")
	# Its shop predates the turned tables (#320): the morning says they moved.
	assert_true((_main.get_node("HUD/Top/Row/AisleNote") as Label).visible)
	assert_eq((_main.get("sim") as RestaurantSim).staff_spawns, ORIGINAL.staff_spawns)
	assert_eq((_main.call("_lease_layout") as ShopLayout).pantry_units, ORIGINAL.pantry_units)
	_empty_next_morning()
	_close()
	_start()
	_assert_base(ORIGINAL)
	_close()
	SaveSystem.delete_slot(SLOT)
	_start()
	_assert_base(NEW, 1)


## #320: a version-9 save of the original layout, its three tables in one row
## of seats that shut the kitchen off, loads with the tables turned, says so
## that morning only, and saves the repaired shop at the next morning.
func test_original_table_row_save_is_repaired_once_with_a_morning_note() -> void:
	_start()
	var doc: Dictionary = _document()
	var snapshot: Dictionary = _original_snapshot(false)
	var table: int = 0
	for item: Dictionary in snapshot["items"]:
		if item["def_id"] == "table_2":
			var origin: Vector2i = AisleRepair.ORIGINAL_TABLES[table][0]
			item["origin"] = [origin.x, origin.y]
			item["quarter_turns"] = AisleRepair.ORIGINAL_TABLES[table][1]
			table += 1
	snapshot["version"] = 9
	doc["data"]["shop"] = snapshot
	_write(doc)
	_close()
	_start()
	_assert_base(ORIGINAL)
	assert_eq(_editor().to_dict()["items"], _without_trays(_original_snapshot(false))["items"],
		"the tables stand where the repaired template has them")
	var note: Label = _main.get_node("HUD/Top/Row/AisleNote") as Label
	assert_true(note.visible, "the morning says the tables moved")
	assert_eq(note.text, AisleRepair.NOTE)
	assert_eq(ShopEditor._unreachable((_main.get("world") as SimWorld).grid, _identity()), [] as Array[int])
	_empty_next_morning()
	assert_false(note.visible, "the note is for that morning only")
	assert_eq(int(_document()["data"]["shop"]["version"]), ShopEditor.SNAPSHOT_VERSION)
	_close()
	_start()
	assert_false((_main.get_node("HUD/Top/Row/AisleNote") as Label).visible, "a repaired save never repeats it")
	assert_eq((_main.get("_loaded_layout") as ShopLayout).aisle_moved, 0)


func _identity() -> Dictionary[int, int]:
	var ids: Dictionary[int, int] = {}
	for item: PlacedItem in (_main.get("world") as SimWorld).grid.items():
		ids[item.id] = item.id
	return ids


func test_saved_furniture_covering_owner_home_keeps_old_shop_and_valid_owner_mode() -> void:
	_start()
	var doc: Dictionary = _document()
	var snapshot: Dictionary = _original_snapshot(false)
	# A legitimate older snapshot can cover a staff birth/home cell. Keep the
	# furniture and requested home; movement may admit the owner elsewhere or
	# leave them pending. A pending owner is still part of the saved population.
	snapshot["items"].append({"def_id": "prep_counter", "origin": [8, 3],
		"quarter_turns": 0, "swatch_id": "", "variant_id": "", "paint": []})
	doc["data"]["shop"] = snapshot
	doc["data"]["owner"]["mode"] = "floor"
	_write(doc)
	_close()
	_start()
	_assert_base(ORIGINAL)
	assert_eq(_editor().to_dict()["items"], snapshot["items"])
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var owner: OwnerAgent = sim.owner_agent()
	assert_not_null(owner, "pending admission cannot make a valid saved owner disappear")
	if owner != null:
		assert_eq(owner.home_cell(), ORIGINAL.staff_spawns[&"owner"])
		assert_eq(owner.current_mode(), &"floor")
	var covering: PlacedItem = sim.world.grid.item_at(ORIGINAL.staff_spawns[&"owner"])
	assert_not_null(covering)
	if covering != null:
		assert_eq((covering.def as ItemDef).id, &"prep_counter")


func test_unknown_identity_and_late_whole_load_rejection_preserve_slot_and_discard_staged_old_base() -> void:
	_start()
	var valid: Dictionary = _document()
	for identity: Variant in ["unknown_base", 3, [], null]:
		var malformed: Dictionary = valid.duplicate(true)
		malformed["data"]["shop"]["layout_id"] = identity
		_write(malformed)
		var failed: String = _saved_text()
		_close()
		_start()
		_assert_base(NEW)
		assert_null(_main.get("_loaded_layout"))
		assert_eq(_saved_text(), failed, "invalid identity cannot overwrite the only old checkpoint")
	var late: Dictionary = valid.duplicate(true)
	late["data"]["shop"] = _original_snapshot(false)
	late["data"][REJECT] = {}
	SaveSystem.register(REJECT, _empty_capture, _reject_after_shop)
	_write(late)
	var failed: String = _saved_text()
	_close()
	_start()
	assert_true(_reject_reached)
	assert_true(_old_was_staged, "the later rejection follows a valid staged original shop")
	_assert_base(NEW)
	assert_null(_main.get("_loaded_layout"))
	assert_eq(_saved_text(), failed)


func test_player_counter_move_buy_and_stamp_refuse_owner_overlap_but_clear_and_flat_edits_work() -> void:
	_start()
	_stage_placement_controls()
	assert_true(_main.call("set_build_active", true))
	var prep: PlacedItem = ShopBuilder.items_with_def(_main.get("world") as SimWorld, &"prep_counter")[0]
	var before: Dictionary = _placement_state()
	assert_false(_main.call("shop_move", prep.id, Vector2i(8, 3), 0))
	assert_eq(_editor().last_check.why, ShopEditor.PERSON_IN_WAY)
	assert_eq(_placement_state(), before)
	assert_false(_main.call("shop_buy", &"prep_counter", Vector2i(8, 3), 0))
	assert_eq(_editor().last_check.why, ShopEditor.PERSON_IN_WAY)
	assert_eq(_placement_state(), before)
	var entry: ShopPlacement = ShopPlacement.new()
	entry.item_id = &"prep_counter"
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "Counter"
	blueprint.entries = [entry]
	assert_false(_main.call("shop_stamp", blueprint, Vector2i(8, 3), 0))
	assert_eq(_editor().last_check.why, ShopEditor.PERSON_IN_WAY)
	assert_eq(_placement_state(), before)
	# A bench is walkable, but adding its seat under an unassigned standing
	# owner still puts their body inside the furniture.
	assert_false(_main.call("shop_buy", &"waiting_bench", Vector2i(9, 3), 0))
	assert_eq(_editor().last_check.why, ShopEditor.PERSON_IN_WAY)
	assert_eq(_placement_state(), before)
	assert_true(_main.call("shop_buy", &"rug_square", Vector2i(8, 3), 0), _editor().last_check.why)
	var cash: int = Economy.cash
	assert_true(_main.call("shop_buy", &"prep_counter", Vector2i(11, 3), 0), _editor().last_check.why)
	assert_eq(Economy.cash, cash - (_main.get("content") as ContentDB).item(&"prep_counter").price)
	assert_eq(_saved_text(), before["save"], "even accepted controls create no action save")


func test_exact_undo_cannot_restore_counter_on_person_and_keeps_history_and_books() -> void:
	_start()
	assert_true(_main.call("set_build_active", true))
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var owner: OwnerAgent = sim.owner_agent()
	assert_true(sim.world.reset_agent_position(owner, Vector2i(11, 3)))
	var prep: PlacedItem = ShopBuilder.items_with_def(sim.world, &"prep_counter")[0]
	assert_true(_main.call("shop_move", prep.id, Vector2i(8, 3), 0))
	# A legal admission to the now-vacant old location exercises exact history
	# after the physical population changes; no through-solid teleport is used.
	assert_true(sim.world.reset_agent_position(owner, Vector2i(4, 1)))
	var before: Dictionary = _placement_state()
	assert_false(_main.call("undo_edit"))
	assert_eq(_editor().last_check.why, ShopEditor.PERSON_IN_WAY)
	assert_eq(_placement_state(), before, "refusal cannot pop history, refund or move the item")
	assert_true(sim.world.reset_agent_position(owner, Vector2i(11, 3)))
	assert_true(_main.call("undo_edit"))
	assert_eq(prep.origin, Vector2i(4, 1))


func test_closed_partial_edge_corner_and_swept_claims_refuse_new_solid_placement() -> void:
	_start()
	_stage_placement_controls()
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var owner: OwnerAgent = sim.owner_agent()
	assert_true(owner.set_destination(sim.world.grid, Vector2i(10, 4)))
	owner.step_move(sim.world)
	assert_true(owner.move_progress > 0.0)
	assert_eq(owner.next_cell(), Vector2i(10, 4))
	# A controlled paused-close boundary retains a real partial diagonal edge.
	# Both orthogonal corners belong to the movement interval as well.
	Clock.sim.phase = SimClock.Phase.CLOSED
	var before: Dictionary = _placement_state()
	for cell: Vector2i in [Vector2i(10, 4), Vector2i(10, 3), Vector2i(9, 4)]:
		assert_false(_main.call("shop_buy", &"potted_plant", cell, 0))
		assert_eq(_editor().last_check.why, ShopEditor.PERSON_IN_WAY)
		assert_eq(_placement_state(), before)
	# Completing this edge retains its swept corners for the same tick. The
	# placement guard intentionally keeps that conservative coordinator hold.
	for step: int in 8:
		if owner.has_arrived():
			break
		owner.step_move(sim.world)
	assert_true(owner.has_arrived())
	assert_false(_main.call("shop_buy", &"potted_plant", Vector2i(10, 3), 0))
	assert_eq(_editor().last_check.why, ShopEditor.PERSON_IN_WAY)


func _stage_placement_controls() -> void:
	# Explicit unlock/funding fixture isolates physical safety from affordability.
	var progress: OwnerProgress = _main.get("owner_progress") as OwnerProgress
	progress.award_bonus(progress.threshold_for(2))
	(_main.get("menu_settings") as MenuSettings).set_owner_level(progress.level)
	_editor().set_owner_level(progress.level)
	Economy.add_cash(1000, Ledger.OTHER, "placement_fixture")


func _placement_state() -> Dictionary:
	var history: ShopEditHistory = _main.get("edit_history") as ShopEditHistory
	var world: SimWorld = _main.get("world") as SimWorld
	return {"shop": _editor().to_dict(), "economy": Economy.call("_capture_save"),
		"rng": GameState.call("_capture_save"), "clock": Clock.sim.to_dict(),
		"world_tick": world.now, "claims": world.movement.snapshot(),
		"undo": history.undo_count(), "redo": history.redo_count(), "save": _saved_text()}


func _start() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("skip_owner_picker", true)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	(_main.get_node("CameraRig") as CameraRig).set_process(false)
	(_main.get_node("ShopView") as ShopView).set_process(false)
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _assert_base(base: ShopLayout, tier: int = 1) -> void:
	var grid: SimGrid = (_main.get("world") as SimWorld).grid
	var authored: SimGrid = SimGrid.from_ascii(base.rows)
	var footprint: ShopFootprint = ShopFootprint.from_layout(LEASE.layout_for(base, tier))
	if not _editor().bought_floor().is_empty():
		assert_true(footprint.apply(authored, ShopFootprint.to_set(_editor().bought_floor())))
	assert_eq(grid.bounds, authored.bounds)
	for cell: Vector2i in authored.cells():
		assert_eq(grid.terrain(cell), authored.terrain(cell), "preserved terrain %s" % cell)
	assert_eq(grid.entries(), authored.entries())
	if _editor().bought_floor().is_empty():
		assert_eq(grid.rooms(), base.authored_rooms())
	else:
		for cell: Vector2i in base.authored_rooms():
			assert_eq(grid.room(cell), base.authored_rooms()[cell])
	assert_eq((_main.get("sim") as RestaurantSim).staff_spawns, base.staff_spawns)
	assert_eq(_editor().pantry_units, base.pantry_units)
	assert_eq(_editor().footprint().lot, ShopFootprint.from_layout(LEASE.layout_for(base, tier)).lot)
	assert_eq((_main.get("_base_layout") as ShopLayout).save_layout_id, base.save_layout_id)


func _original_snapshot(decorated: bool) -> Dictionary:
	var content: ContentDB = _main.get("content") as ContentDB
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = ShopBuilder.build(ORIGINAL, content, errors)
	assert_eq(errors, [] as Array[String])
	var editor: ShopEditor = ShopEditor.new(sim, content, ShopEditBooks.new(_can_spend, _ignore_cash), ORIGINAL)
	if decorated:
		editor.set_owner_level(3)
		assert_true(editor.paint_wall(&"sage"))
		assert_true(editor.apply_wall_finishes({Vector3i(3, 11, 0):
			FloorFinishes.Finish.new(&"brick", &"sage", &"cream")} as Dictionary[Vector3i, FloorFinishes.Finish]))
		assert_true(editor.hang(&"street_awning_2", Vector3i(6, 11, 4), null, &"clay"))
	var snapshot: Dictionary = editor.to_dict()
	snapshot["tray_level"] = 0
	return snapshot


func _snapshot_of(base: ShopLayout) -> Dictionary:
	var content: ContentDB = _main.get("content") as ContentDB
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = ShopBuilder.build(base, content, errors)
	assert_eq(errors, [] as Array[String])
	var snapshot: Dictionary = ShopEditor.new(sim, content, ShopEditBooks.new(_can_spend, _ignore_cash), base).to_dict()
	snapshot["tray_level"] = 0
	return snapshot


func _without_trays(snapshot: Dictionary) -> Dictionary:
	var copy: Dictionary = snapshot.duplicate(true)
	copy.erase("tray_level")
	return copy


func _empty_next_morning() -> void:
	# Persistence fixture only: no claim of a played service day.
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_dir.path_join(SLOT + ".json"))


func _document() -> Dictionary:
	return JSON.parse_string(_saved_text()) as Dictionary


func _write(doc: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_dir.path_join(SLOT + ".json"), FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(JSON.stringify(doc))
		file.close()
	DirAccess.remove_absolute(_dir.path_join(SLOT + ".json.bak"))


func _can_spend(_amount: int) -> bool:
	return true


func _ignore_cash(_amount: int, _category: StringName, _note: String = "") -> void:
	pass


func _empty_capture() -> Dictionary:
	return {}


func _reject_after_shop(_data: Dictionary) -> bool:
	_reject_reached = true
	var staged: ShopLayout = _main.get("_loaded_layout") as ShopLayout
	_old_was_staged = staged != null and staged.rows == ORIGINAL.rows \
		and staged.staff_spawns == ORIGINAL.staff_spawns
	return false
