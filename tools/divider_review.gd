extends "res://src/world/main.gd"
## Native review fixture; the same shop and production edit APIs as play.
## default: untouched starter; restroom: corner bathroom; remove: bathroom
## beside a held red removal run. The existing CI job captures default/remove.

var _review_stage: String = "default"
var _review_drag: bool = false
var _review_frames: int = 0
var _review_reported: bool = false
var _review_failed: bool = false


func _ready() -> void:
	use_saves = false
	skip_owner_picker = true
	new_game_seed_override = 1
	super._ready()
	_review_stage = OS.get_environment("DIVIDER_REVIEW_STAGE")
	if _review_stage.is_empty() or _review_stage == "default":
		return
	if _review_stage not in ["restroom", "remove"]:
		push_error("Unknown divider review stage")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not _make_review_restroom():
		push_error("The divider review bathroom was refused: " + shop_editor.last_check.why)
		return
	if _review_stage == "remove":
		if not set_build_active(true) or not begin_wall_tool(SimGrid.Segment.NONE):
			push_error("The divider review Remove tool was refused")
			return
		($Overlay/BuildCatalogue as BuildCatalogue).set_category(BuildCatalogue.WALLS)
		var camera: Camera3D = $CameraRig/Camera3D as Camera3D
		var start: Vector2 = camera.unproject_position(Vector3(4.0, 0.0, 2.5))
		get_window().warp_mouse(start)
		var press: InputEventMouseButton = InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = start
		press.global_position = start
		Input.parse_input_event(press)
		Input.flush_buffered_events()
		_review_drag = true


func _process(delta: float) -> void:
	if _review_drag:
		var camera: Camera3D = $CameraRig/Camera3D as Camera3D
		get_window().warp_mouse(camera.unproject_position(Vector3(6.5, 0.0, 2.5)))
	super._process(delta)
	_review_frames += 1
	if _review_frames >= 20 and not _review_failed:
		if not _review_state_valid():
			_review_failed = true
			push_error("The divider review state does not match its requested capture")
		elif not _review_reported:
			_review_reported = true
			print("DIVIDER_REVIEW verified stage=", _review_stage, " refund=", build_mode.current_check.refund)


func _review_state_valid() -> bool:
	for x: int in [1, 2, 3, 4, 8, 9, 10, 11, 12]:
		if world.grid.terrain(Vector2i(x, 4)) != SimGrid.Terrain.FLOOR:
			return false
		if _review_stage.is_empty() or _review_stage == "default":
			if world.grid.room(Vector2i(x, 4)) != SimGrid.Room.KITCHEN \
					or world.grid.segment(Vector3i(x, 5, SimGrid.EDGE_NORTH)) != SimGrid.Segment.WALL:
				return false
	if _review_stage.is_empty() or _review_stage == "default":
		return world.now == 0
	for y: int in range(3, 5):
		for x: int in range(1, 4):
			if world.grid.room(Vector2i(x, y)) != SimGrid.Room.RESTROOM:
				return false
	if ShopBuilder.items_with_def(world, &"toilet").size() != 1 \
			or ShopBuilder.items_with_def(world, &"bathroom_sink").size() != 1 \
			or not world.grid.is_guest_reachable(world.grid.entries()[0], Vector2i(2, 4)):
		return false
	if _review_stage == "restroom":
		return world.now == 0
	var preview: BuildPreview = $BuildPreview
	if build_mode.state != BuildMode.State.WALLS or build_mode.wall_kind != SimGrid.Segment.NONE \
			or not build_mode.wall_dragging or not build_mode.current_check.ok \
			or build_mode.wall_changes.size() != 5 or build_mode.current_check.refund != 25 \
			or build_mode.current_check.cost != 0 or preview.wall_ghosts.size() != 5:
		return false
	var color: Color = BuildPreview.INVALID_COLOR
	color.a = BuildPreview.WALL_GHOST_ALPHA
	for ghost: MeshInstance3D in preview.wall_ghosts:
		var material: BaseMaterial3D = ghost.get_active_material(0) as BaseMaterial3D
		if material == null or not material.albedo_color.is_equal_approx(color):
			return false
	var hint: Label = $HUD/BuildHints/Scroll/Lines/Text
	return world.now == 0 and hint.visible and hint.text.contains("refund $25")


func _make_review_restroom() -> bool:
	var walls: Dictionary[Vector3i, int] = {}
	for x: int in range(1, 4):
		walls[Vector3i(x, 3, SimGrid.EDGE_NORTH)] = SimGrid.Segment.WALL
	for y: int in range(3, 5):
		walls[Vector3i(4, y, SimGrid.EDGE_WEST)] = SimGrid.Segment.WALL
	walls[Vector3i(2, 5, SimGrid.EDGE_NORTH)] = SimGrid.Segment.DOORWAY
	if not shop_walls(walls):
		return false
	var rooms: Dictionary[Vector2i, int] = {}
	for y: int in range(3, 5):
		for x: int in range(1, 4):
			rooms[Vector2i(x, y)] = SimGrid.Room.RESTROOM
	return shop_rooms(rooms) and shop_buy(&"toilet", Vector2i(1, 3), 2) \
		and shop_buy(&"bathroom_sink", Vector2i(3, 3), 2)
