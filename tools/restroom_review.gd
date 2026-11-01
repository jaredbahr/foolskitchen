extends RefCounted
## Explicit #198 review fixture: real morning edits, never saved. Capture via
## tools/screenshot.sh --restroom-review --speed=0 --frames=12,30 --out=<outside repo>
## First frame: two reachable toilets, divider, basin, mirror and dryer.
## Second: closer wall view with the real owner beside the fittings for scale.

static func prepare(main: Node, root: Window) -> String:
	var world: SimWorld = main.get("world") as SimWorld
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	root.get_node("Economy").call("add_cash", 2000, Ledger.OTHER)
	for placed: PlacedItem in world.grid.items():
		if placed.origin.y >= 5 and (placed.def as ItemDef).category != ItemDef.Category.DOOR:
			if int(main.call("shop_sell", placed.id)) < 0:
				return "could not clear the restroom fixture"
	var rooms: Dictionary[Vector2i, int] = {}
	for x: int in range(1, 6):
		for y: int in range(5, 10):
			rooms[Vector2i(x, y)] = SimGrid.Room.RESTROOM
	if not bool(main.call("shop_rooms", rooms)):
		return editor.last_check.why
	for piece: Array in [[&"toilet", Vector2i(1, 9)], [&"toilet", Vector2i(2, 9)], [&"bathroom_sink", Vector2i(1, 6)]]:
		if not bool(main.call("shop_buy", piece[0], piece[1], 0)):
			return editor.last_check.why
	var partitions: Dictionary[Vector3i, int] = {
		Vector3i(2, 9, SimGrid.EDGE_WEST): SimGrid.Segment.STALL_PARTITION,
		Vector3i(2, 8, SimGrid.EDGE_WEST): SimGrid.Segment.STALL_PARTITION}
	if not bool(main.call("shop_walls", partitions)):
		return editor.last_check.why
	for piece: Array in [[&"restroom_mirror", Vector3i(1, 6, 3)], [&"wall_hand_dryer", Vector3i(1, 7, 3)]]:
		if not bool(main.call("shop_hang", piece[0], piece[1])):
			return editor.last_check.why
	var owner: OwnerAgent = (main.get("sim") as RestaurantSim).owner_agent()
	owner.cell = Vector2i(2, 7)
	owner.path.clear()
	owner.move_progress = 0.0
	if RoomRules.restroom_toilets(world.grid).size() != 2:
		return "both toilets must remain reachable"
	for placed: PlacedItem in world.grid.items():
		if (placed.def as ItemDef).category == ItemDef.Category.RESTROOM:
			for spot: Vector2i in placed.work_cells:
				if world.grid.find_guest_path(Vector2i(6, 11), spot).is_empty():
					return "a restroom use spot is unreachable"
	print("RESTROOM_REVIEW: two reachable toilets, two divider edges, basin, mirror, hand dryer; owner at (2,7)")
	return ""


static func focus(main: Node, close: bool) -> void:
	(main.get_node("ShopView") as ShopView).set_wall_mode(ShopView.WallMode.UP)
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	var camera: Camera3D = main.get_node("CameraRig/Camera3D") as Camera3D
	# Pixel-checked complementary views: steep enough to see both complete
	# toilet bowls over the unchanged divider, with an eastward component so
	# the mirror frame reads; then due east for its full face and person scale.
	var target: Vector3 = Vector3(0.95, 0.65, 3.5) if close else Vector3(1.15, 0.45, 3.85)
	var offset: Vector3 = Vector3(4.0, 3.0, 0.0) if close else Vector3(2.0, 20.0, -4.0)
	camera.global_position = target + offset
	camera.look_at(target)
	camera.size = 2.2 if close else 3.4
