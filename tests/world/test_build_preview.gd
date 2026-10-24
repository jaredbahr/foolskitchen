extends TestCase
## Checked controller -> native geometry only. No frame/render acceptance is claimed here.

const PREVIEW: PackedScene = preload("res://src/world/build_preview.tscn")
const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

class PreviewContent extends ContentDB:
	var extra: Dictionary[StringName, ItemDef] = {}

	func item(id: StringName) -> ItemDef:
		return extra[id] if extra.has(id) else super.item(id)

var _preview: BuildPreview
var _view: ShopView
var _mode: BuildMode
var _content: PreviewContent
var _sim: RestaurantSim
var _editor: ShopEditor
var _books: ShopEditBooks
var _cash: int = 1000
var _entries: Array[Dictionary] = []
var _changes: int = 0
var _host: Node3D


func before_each() -> void:
	_content = PreviewContent.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 55031, errors)
	assert_eq(errors, [] as Array[String])
	_cash = 1000
	_entries.clear()
	_changes = 0
	_books = ShopEditBooks.new(_can_spend, _record_cash)
	_editor = ShopEditor.new(_sim, _content, _books)
	_mode = BuildMode.new()
	_mode.bind_session(_editor, _sim.world, _content, _move, _buy, _sell)
	_view = VIEW.instantiate() as ShopView
	_view.show_world(_sim.world)
	_preview = PREVIEW.instantiate() as BuildPreview
	_preview.bind_build_mode(_mode, _view)
	_sim.world.grid.cells_changed.connect(_record_cells)


func after_each() -> void:
	if is_instance_valid(_preview):
		_preview.clear()
		_preview.free()
	_mode.bind_session(null, null, null, Callable(), Callable(), Callable())
	if is_instance_valid(_view):
		_view.show_world(null)
		_view.free()
	if is_instance_valid(_host):
		_host.free()
	_host = null
	_sim.world.grid.cells_changed.disconnect(_record_cells)
	_mode = null
	_editor = null
	_books = null
	_sim = null
	_content = null
	_entries.clear()


func test_unbound_and_inactive_preview_are_empty_before_ready() -> void:
	assert_false(_preview.is_node_ready())
	assert_eq(_preview.get_child_count(), 0)
	assert_null(_preview.ghost_mesh)
	assert_true(_preview.displayed_warning_ids().is_empty())
	assert_eq(_preview.invalid_reason(), "")
	var initial_native: Dictionary = _preview.visual_state()
	assert_false(initial_native["inside_tree"])
	assert_eq(initial_native["ghost"], {})
	assert_true(initial_native["warning_ids"].is_empty())
	_preview.bind_build_mode(null, null)
	_preview.refresh()
	_preview.clear()
	assert_eq(_preview.get_child_count(), 0)


func test_all_camera_and_item_quarters_match_checked_min_corner_and_rotated_markers() -> void:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"preview_asymmetric"
	definition.footprint = Vector2i(3, 2)
	definition.category = ItemDef.Category.STATION
	definition.station_type = &"prep_counter"
	definition.work_cells = [Vector2i(-1, 0), Vector2i(3, 1)]
	definition.seat_cells = [Vector2i(0, 2)]
	_content.extra[definition.id] = definition
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(definition.id, Vector2i(8, 8)))
	var saw_valid: bool = false
	var saw_invalid: bool = false
	for camera_quarter: int in range(4):
		_view.set_camera_quarter(camera_quarter)
		for turn: int in range(4):
			var check: EditCheck = _editor.check_buy(definition.id, _mode.origin, turn)
			saw_valid = saw_valid or check.ok
			saw_invalid = saw_invalid or not check.ok
			assert_eq(_mode.quarter_turns, turn)
			_preview.refresh()
			assert_not_null(_preview.ghost_mesh)
			var bounds: AABB = _preview.ghost_mesh.transform * _preview.ghost_mesh.get_aabb()
			var footprint: Vector2i = GridMath.rotated_footprint(definition.footprint, turn)
			assert_almost_eq(bounds.position.x, _mode.origin.x * GridMath.CELL_SIZE)
			assert_almost_eq(bounds.position.z, _mode.origin.y * GridMath.CELL_SIZE)
			assert_almost_eq(bounds.size.x, footprint.x * GridMath.CELL_SIZE)
			assert_almost_eq(bounds.size.z, footprint.y * GridMath.CELL_SIZE)
			assert_almost_eq(bounds.size.y, ShopView.HEIGHTS[definition.category])
			assert_almost_eq(_preview.ghost_mesh.rotation.y, -turn * PI / 2.0)
			assert_eq(_preview.ghost_mesh.get_meta("valid"), check.ok)
			assert_eq(_preview.displayed_warning_ids(), _mode.warning_ids())
			assert_eq(_preview.work_markers.size(), definition.work_cells.size())
			assert_eq(_preview.seat_markers.size(), definition.seat_cells.size())
			for index: int in range(definition.work_cells.size()):
				var marker: MeshInstance3D = _preview.work_markers[index]
				_assert_marker(marker, _mode.origin + GridMath.rotate_cell(definition.work_cells[index], definition.footprint, turn))
				assert_true(marker.mesh is BoxMesh)
				assert_eq((marker.material_override as StandardMaterial3D).albedo_color, BuildPreview.WORK_COLOR)
			for index: int in range(definition.seat_cells.size()):
				var marker: MeshInstance3D = _preview.seat_markers[index]
				_assert_marker(marker, _mode.origin + GridMath.rotate_cell(definition.seat_cells[index], definition.footprint, turn))
				assert_true(marker.mesh is CylinderMesh)
				assert_eq((marker.material_override as StandardMaterial3D).albedo_color, BuildPreview.SEAT_COLOR)
			assert_true(_mode.rotate())
	assert_true(saw_valid, "the all-quarter fixture includes a green placement")
	assert_true(saw_invalid, "the all-quarter fixture includes a red placement")
	var native_marker: MeshInstance3D = _preview.work_markers[0]
	native_marker.set_meta("cell", Vector2i(66, 77))
	native_marker.position = Vector3(8.0, 9.0, 10.0)
	var native_state: Dictionary = _preview.visual_state()
	assert_eq(native_state["work_markers"][0]["cell"], [66, 77])
	assert_eq(native_state["work_markers"][0]["position"], [8.0, 9.0, 10.0] as Array[float])
	assert_eq(native_state["work_markers"][0]["mesh_class"], "BoxMesh")
	assert_eq(native_state["seat_markers"][0]["mesh_class"], "CylinderMesh")
	assert_eq(native_marker.position, Vector3(8.0, 9.0, 10.0), "reading never repairs or moves native markers")
	assert_eq(_changes, 0)
	assert_eq(_entries.size(), 0)


func test_valid_and_invalid_tints_are_private_and_reason_matches_editor() -> void:
	var id: int = _id(&"potted_plant")
	var original: MeshInstance3D = _view.item_nodes[id]
	var material: StandardMaterial3D = original.material_override as StandardMaterial3D
	var color: Color = material.albedo_color
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(id))
	_mode.update_origin(Vector2i(11, 9))
	assert_true(_mode.current_check.ok)
	assert_false(original.visible)
	var green: StandardMaterial3D = _preview.ghost_mesh.material_override as StandardMaterial3D
	assert_true(green != material)
	assert_true(green.albedo_color.g > green.albedo_color.r)
	assert_almost_eq(green.albedo_color.a, 0.92)
	assert_eq(green.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_eq(_preview.invalid_reason(), "")
	_mode.update_origin(Vector2i(-1, 0))
	var check: EditCheck = _editor.check_move(id, Vector2i(-1, 0), _mode.quarter_turns)
	assert_false(check.ok)
	assert_eq(_preview.invalid_reason(), check.why)
	var red: StandardMaterial3D = _preview.ghost_mesh.material_override as StandardMaterial3D
	assert_true(red.albedo_color.r > red.albedo_color.g)
	assert_almost_eq(red.albedo_color.a, 0.68)
	assert_true(red != material)
	assert_eq(material.albedo_color, color)
	assert_eq(_content.item(&"potted_plant").placeholder_color, color)
	# Deliberately diverge native presentation from the checked model. Capture
	# evidence must report these actual nodes and must never mirror/repair them.
	var checked_before: Dictionary = _mode.presentation_state()
	var native_ghost: MeshInstance3D = _preview.ghost_mesh
	native_ghost.position += Vector3(0.125, 0.25, 0.5)
	native_ghost.visible = false
	native_ghost.set_meta("valid", true)
	red.albedo_color = Color(0.1, 0.2, 0.3, 0.4)
	var native_position: Vector3 = native_ghost.position
	var native: Dictionary = _preview.visual_state()
	assert_false(native["inside_tree"])
	assert_false(native["ghost"]["visible"])
	assert_false(native["ghost"]["visible_in_tree"])
	assert_true(native["ghost"]["global_transform"].is_empty())
	assert_true(native["ghost"]["valid"], "actual metadata can disagree with the invalid controller check")
	assert_eq(native["ghost"]["position"], [native_position.x, native_position.y, native_position.z] as Array[float])
	assert_eq(native["ghost"]["material_color"], [red.albedo_color.r, red.albedo_color.g, red.albedo_color.b, red.albedo_color.a])
	assert_eq(native["ghost"]["transparency"], int(red.transparency))
	var native_size: Vector3 = native_ghost.mesh.get_aabb().size
	assert_eq(native["ghost"]["mesh_size"], [native_size.x, native_size.y, native_size.z] as Array[float])
	assert_true(JSON.parse_string(JSON.stringify(native)) is Dictionary)
	native["ghost"]["position"][0] = 999.0
	assert_eq(native_ghost.position, native_position, "returned arrays cannot modify native transforms")
	assert_true(_preview.ghost_mesh == native_ghost, "reading never recreates presentation")
	assert_eq(_mode.presentation_state(), checked_before)
	assert_false(_mode.current_check.ok)
	assert_eq(material.albedo_color, color, "native evidence never touches the live furniture material")
	_mode.cancel()
	assert_true(original.visible)
	assert_eq(_preview.invalid_reason(), "")
	assert_eq(_preview.get_child_count(), 0)


func test_cancel_rebind_and_clear_restore_exact_original_visibility_and_remove_nodes() -> void:
	var original: MeshInstance3D = _view.item_nodes[_id(&"table_2")]
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(_id(&"table_2")))
	assert_false(original.visible)
	assert_eq(_preview.seat_markers.size(), 2)
	_preview.bind_build_mode(_mode, _view)
	assert_false(original.visible)
	_mode.cancel()
	assert_true(original.visible)
	assert_true(_preview.work_markers.is_empty())
	assert_true(_preview.seat_markers.is_empty())
	original.visible = false
	assert_true(_mode.pick_up(_id(&"table_2")))
	_mode.cancel()
	assert_false(original.visible, "a previously hidden source stays hidden")
	original.visible = true
	assert_true(_mode.pick_up(_id(&"table_2")))
	var callback: Callable = Callable(_preview, "refresh")
	assert_true(_mode.changed.is_connected(callback))
	_preview.clear()
	_preview.clear()
	assert_false(_mode.changed.is_connected(callback))
	assert_true(original.visible)
	assert_eq(_preview.get_child_count(), 0)
	_mode.update_origin(Vector2i(8, 8))
	assert_eq(_preview.get_child_count(), 0, "old controller no longer drives a cleared view")


func test_buy_zero_warning_becomes_actual_id_after_commit_and_clears_after_fix() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"fridge", Vector2i(10, 1)))
	assert_true(_mode.current_check.ok)
	assert_true(_mode.current_check.unreachable.has(0))
	assert_eq(_preview.displayed_warning_ids(), _mode.current_check.unreachable)
	assert_true(_preview.warning_nodes.has(0))
	assert_eq(_preview.warning_nodes[0].get_child_count(), 12)
	var warning_root: Node3D = _preview.warning_nodes[0]
	var warning_position: Vector3 = warning_root.position
	warning_root.position.x += 0.125
	warning_root.set_meta("item_id", 71)
	var actual_warnings: Dictionary = _preview.visual_state()
	assert_eq(actual_warnings["warning_ids"], [0] as Array[int])
	assert_eq(actual_warnings["warnings"][0]["item_id"], 0)
	assert_eq(actual_warnings["warnings"][0]["metadata_item_id"], 71)
	assert_eq(actual_warnings["warnings"][0]["position"],
		[warning_root.position.x, warning_root.position.y, warning_root.position.z] as Array[float])
	assert_eq(actual_warnings["warnings"][0]["rails"].size(), 12)
	assert_eq(actual_warnings["warnings"][0]["rails"][0]["mesh_class"], "BoxMesh")
	assert_eq(_mode.current_check.unreachable, [0] as Array[int], "reading does not rewrite model warnings")
	assert_eq(warning_root.position.x, 5.125)
	warning_root.position = warning_position
	warning_root.set_meta("item_id", 0)
	warning_root.free()
	var missing_warning: Dictionary = _preview.visual_state()
	assert_true(missing_warning["warning_ids"].is_empty(), "freed nodes are not rendered warning evidence")
	assert_true(missing_warning["warnings"].is_empty())
	assert_eq(_mode.current_check.unreachable, [0] as Array[int], "reading never repairs a missing native outline")
	_preview.warning_nodes.erase(0) # Fixture cleanup of the deliberately freed reference.
	assert_true(_mode.commit())
	var fridge: PlacedItem = _sim.world.grid.item_at(Vector2i(10, 1))
	assert_not_null(fridge)
	assert_false(_preview.warning_nodes.has(0))
	assert_true(_preview.warning_nodes.has(fridge.id))
	assert_eq(_preview.displayed_warning_ids(), _editor.check_current().unreachable)
	assert_eq(_preview.warning_nodes[fridge.id].get_meta("item_id"), fridge.id)
	assert_eq(_preview.warning_nodes[fridge.id].position, Vector3(5.0, 0.02, 0.5))
	_mode.exit()
	assert_null(_preview.ghost_mesh)
	assert_true(_preview.warning_nodes.has(fridge.id), "leaving build mode keeps committed warnings")
	assert_eq(_preview.displayed_warning_ids(), _editor.check_current().unreachable)
	assert_true(_mode.enter())
	_mode.cancel()
	assert_false(_mode.is_active())
	assert_true(_preview.warning_nodes.has(fridge.id), "Esc from idle keeps committed warnings")
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"chair", Vector2i(-1, 0)))
	assert_false(_mode.current_check.ok)
	assert_true(_preview.warning_nodes.has(fridge.id), "invalid proposal keeps committed warnings")
	_mode.cancel()
	assert_true(_preview.warning_nodes.has(fridge.id), "cancel keeps actual layout warnings")
	assert_true(_mode.pick_up(fridge.id))
	_mode.update_origin(Vector2i(9, 1))
	assert_true(_mode.current_check.ok)
	assert_true(_mode.current_check.unreachable.has(fridge.id))
	assert_eq(_preview.warning_nodes[fridge.id].position, Vector3(4.5, 0.02, 0.5), "a valid moved warning follows the proposed pose")
	_mode.update_origin(Vector2i(-1, 0))
	assert_false(_mode.current_check.ok)
	assert_eq(_preview.warning_nodes[fridge.id].position, Vector3(5.0, 0.02, 0.5), "an invalid proposal keeps the actual warning pose")
	_mode.update_origin(Vector2i(10, 2))
	assert_true(_mode.current_check.ok)
	assert_false(_mode.current_check.unreachable.has(fridge.id))
	assert_true(_mode.commit())
	assert_false(_preview.warning_nodes.has(fridge.id))
	assert_eq(_preview.displayed_warning_ids(), _editor.check_current().unreachable)
	_mode.exit()
	assert_eq(_preview.get_child_count(), 0)


func test_table_warning_highlights_match_actual_checked_ids_and_cancelled_proposal() -> void:
	assert_true(_editor.buy(&"potted_plant", Vector2i(1, 7)))
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"potted_plant", Vector2i(4, 7)))
	var check: EditCheck = _editor.check_buy(&"potted_plant", Vector2i(4, 7))
	var table_id: int = _id(&"table_2")
	assert_true(check.ok)
	assert_true(check.unreachable.has(table_id))
	assert_eq(_preview.displayed_warning_ids(), check.unreachable)
	assert_true(_preview.warning_nodes.has(table_id))
	for rail: Node in _preview.warning_nodes[table_id].get_children():
		var material: StandardMaterial3D = (rail as MeshInstance3D).material_override as StandardMaterial3D
		assert_eq(material.albedo_color, BuildPreview.INVALID_COLOR)
		assert_true(material.no_depth_test)
	_mode.cancel()
	assert_eq(_preview.displayed_warning_ids(), _editor.check_current().unreachable)
	assert_false(_preview.warning_nodes.has(table_id), "cancel never pretends an uncommitted blocker exists")


func test_removed_item_and_replaced_shop_mesh_leave_no_hidden_or_orphan_nodes() -> void:
	var id: int = _id(&"potted_plant")
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(id))
	var old_mesh: MeshInstance3D = _view.item_nodes[id]
	assert_true(_editor.move(id, Vector2i(11, 9), 1))
	assert_false(is_instance_valid(old_mesh))
	# The controller can notify before ShopView rebuilds. The preview's later
	# read-only topology observer must hide the replacement without polling.
	assert_false(_view.item_nodes[id].visible)
	_mode.cancel()
	assert_true(_view.item_nodes[id].visible)
	assert_true(_mode.pick_up(id))
	assert_true(_sim.world.grid.remove(id))
	_preview.refresh()
	_preview.ghost_mesh.free()
	assert_eq(_preview.visual_state()["ghost"], {}, "freed mesh references are guarded")
	_preview.clear()
	assert_false(_view.item_nodes.has(id))
	assert_eq(_preview.get_child_count(), 0)
	assert_true(_preview.warning_nodes.is_empty())


func test_free_while_holding_restores_mesh_and_disconnects_even_before_tree_entry() -> void:
	var original: MeshInstance3D = _view.item_nodes[_id(&"potted_plant")]
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(_id(&"potted_plant")))
	assert_false(original.visible)
	_preview.free()
	assert_true(original.visible)
	assert_true(_mode.changed.get_connections().is_empty())


func test_tree_exit_restores_mesh_and_reentry_rebinds_checked_geometry() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(_id(&"potted_plant")))
	var original: MeshInstance3D = _view.item_nodes[_id(&"potted_plant")]
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_host = Node3D.new()
	tree.root.add_child(_host)
	_host.add_child(_view)
	_host.add_child(_preview)
	assert_false(original.visible)
	assert_not_null(_preview.ghost_mesh)
	var native: Dictionary = _preview.visual_state()
	assert_true(native["inside_tree"])
	assert_true(native["ghost"]["visible"])
	assert_true(native["ghost"]["visible_in_tree"])
	assert_eq(native["ghost"]["global_transform"].size(), 12)
	_host.visible = false
	native = _preview.visual_state()
	assert_true(native["ghost"]["visible"], "local visibility is independent of an ancestor")
	assert_false(native["ghost"]["visible_in_tree"], "hidden ancestors affect actual tree visibility")
	assert_false(_host.visible, "reading leaves ancestor visibility untouched")
	_host.visible = true
	_host.remove_child(_preview)
	assert_true(original.visible)
	assert_eq(_preview.get_child_count(), 0)
	assert_true(_mode.changed.get_connections().is_empty())
	_host.add_child(_preview)
	assert_false(original.visible)
	assert_not_null(_preview.ghost_mesh)
	assert_eq(_mode.changed.get_connections().size(), 1)
	_mode.cancel()
	assert_true(original.visible)
	assert_eq(_preview.get_child_count(), 0)


func test_unparent_before_tree_readiness_restores_mesh_and_detaches_sources() -> void:
	_host = Node3D.new()
	_host.add_child(_preview)
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(_id(&"potted_plant")))
	var original: MeshInstance3D = _view.item_nodes[_id(&"potted_plant")]
	assert_false(original.visible)
	_host.remove_child(_preview)
	assert_false(_preview.is_node_ready())
	assert_true(original.visible)
	assert_eq(_preview.get_child_count(), 0)
	assert_true(_mode.changed.get_connections().is_empty())
	assert_false(_sim.world.grid.cells_changed.is_connected(Callable(_preview, "_on_cells_changed")))
	_preview.bind_build_mode(_mode, _view)
	assert_false(original.visible, "explicit pre-ready rebinding reconnects presentation")
	_mode.cancel()
	assert_true(original.visible)


func test_preview_refresh_rotate_cancel_and_rebind_do_not_write_real_session() -> void:
	var table: PlacedItem = _sim.world.grid.item(_id(&"table_2"))
	assert_true(table.reserve(table.seat_cells[0], 55))
	_sim.world.log_event("Preview read-only fixture")
	var before: Dictionary = _snapshot(table)
	assert_true(_mode.enter())
	for _iteration: int in range(3):
		assert_true(_mode.pick_up(_id(&"potted_plant")))
		_mode.update_origin(Vector2i(11, 9))
		assert_true(_mode.rotate())
		_preview.refresh()
		_preview.bind_build_mode(_mode, _view)
		assert_false(_preview.visual_state()["ghost"].is_empty())
		_mode.cancel()
		assert_true(_mode.pick_up(table.id))
		assert_false(_mode.current_check.ok)
		_preview.refresh()
		_mode.cancel()
	assert_eq(_snapshot(table), before)
	assert_eq(_changes, 0)
	assert_eq(_entries.size(), 0)
	_preview.visual_state()
	assert_eq(_snapshot(table), before, "native evidence never writes the real session")


func _snapshot(table: PlacedItem) -> Dictionary:
	return {"layout": _editor.to_dict(), "cash": _cash, "entries": _entries.duplicate(true),
		"clock": _sim.world.clock.to_dict(), "now": _sim.world.now,
		"agents": _sim.world.agents.duplicate(), "tasks": _sim.world.board.active_count(),
		"log": _sim.world.event_log.duplicate(), "stock": _sim.stock.to_dict(),
		"rng_seed": _sim.spawner.rng.seed, "rng_state": _sim.spawner.rng.state,
		"reservation": table.reserved_by(table.seat_cells[0]),
		"served": _sim.served_today, "lost": _sim.lost_today}


func _assert_marker(marker: MeshInstance3D, cell: Vector2i) -> void:
	assert_eq(marker.get_meta("cell"), cell)
	assert_eq(marker.position, GridMath.cell_to_world(cell) + Vector3(0.0, 0.04, 0.0))


func _id(def_id: StringName) -> int:
	return ShopBuilder.items_with_def(_sim.world, def_id)[0].id


func _move(id: int, origin: Vector2i, turns: int) -> bool:
	return _editor.move(id, origin, turns)


func _buy(id: StringName, origin: Vector2i, turns: int) -> bool:
	return _editor.buy(id, origin, turns)


func _sell(id: int) -> int:
	return _editor.sell(id)


func _can_spend(amount: int) -> bool:
	return _cash >= amount


func _record_cash(amount: int, category: StringName) -> void:
	_cash += amount
	_entries.append({"amount": amount, "category": category})


func _record_cells(_cells: Array[Vector2i]) -> void:
	_changes += 1
