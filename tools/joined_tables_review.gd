extends RefCounted
## Explicit, unsaved review of one real six-person party. All table moves,
## opening, routing and seating use the normal game commands and simulation.

const FRAME: int = 90
const WALK_BUDGET: int = 160
const STARTS: Array[Vector2i] = [Vector2i(2, 6), Vector2i(6, 6), Vector2i(10, 6)]
const TARGETS: Array[Vector2i] = [Vector2i(3, 6), Vector2i(5, 6), Vector2i(7, 6)]
const SEATS: Array[Vector2i] = [Vector2i(3, 5), Vector2i(5, 5), Vector2i(7, 5),
	Vector2i(3, 8), Vector2i(5, 8), Vector2i(7, 8)]


static func options(arguments: PackedStringArray) -> Dictionary:
	var enabled: bool = false
	for argument: String in arguments:
		if argument.begins_with("--joined-tables-review"):
			if enabled or argument != "--joined-tables-review":
				return {"enabled": false, "error": "--joined-tables-review is one flag without a value"}
			enabled = true
	if not enabled:
		return {"enabled": false, "error": ""}
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	for argument: String in arguments:
		if argument == "--joined-tables-review" or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=%d" % FRAME:
			frames += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		else:
			return {"enabled": false, "error": "Joined-table review uses only paused Main frame 90"}
	if speeds != 1 or frames != 1 or scenes > 1:
		return {"enabled": false, "error": "--joined-tables-review requires --speed=0 --frames=90"}
	return {"enabled": true, "error": ""}


static func prepare(main: Node, root: Window) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var clock: Node = root.get_node("Clock")
	var result: Dictionary = {"error": "", "kind": "explicit_unsaved_joined_party_fixture",
		"description": "Seed 1; three real starter tables moved normally; one explicit party of six with fixed private guest seeds, normal opening and walking. Only the fixture-local unrelated-arrival countdown is delayed.",
		"walk_tick_limit": WALK_BUDGET, "guest_rng_seeds": [], "table_ids": []}
	if world == null or sim == null or main.get("use_saves") != false or world.now != 0 \
			or world.clock.day != 1 or world.clock.phase != SimClock.Phase.MORNING or clock.get("speed") != 0:
		result["error"] = "Joined-table review requires a fresh paused unsaved Main morning"
		return result
	var ids: Array[int] = []
	for origin: Vector2i in STARTS:
		var found: int = 0
		for item: PlacedItem in world.grid.items():
			var definition: ItemDef = item.def as ItemDef
			if definition != null and definition.id == &"table_2" and item.origin == origin:
				found = item.id
		if found == 0:
			result["error"] = "Joined-table review cannot find its actual starter table"
			return result
		ids.append(found)
	for index: int in ids.size():
		if not main.call("shop_move", ids[index], TARGETS[index], 1):
			result["error"] = "Joined-table review's normal table move was refused"
			return result
	result["table_ids"] = ids
	var group: DiningSeats.Group = world.grid.dining_group(ids[0])
	if group == null or group.member_ids != ids or group.seat_cells != SEATS:
		result["error"] = "Three moved tables did not derive the expected six outside seats"
		return result
	var context: Button = main.get_node("HUD/Top/Row/Context") as Button
	if context.disabled:
		result["error"] = "Joined-table review cannot open through the real HUD action"
		return result
	context.pressed.emit()
	clock.call("set_speed", 0)
	if world.clock.phase != SimClock.Phase.OPEN:
		result["error"] = "The normal HUD action did not open service"
		return result
	result["opening_action"] = "HUD/Top/Row/Context.pressed"
	result["unrelated_arrival_countdown_before"] = sim.spawner._remaining
	sim.spawner._remaining = WALK_BUDGET + 1
	result["unrelated_arrival_countdown_delayed_to"] = sim.spawner._remaining
	var randoms: Array[RandomNumberGenerator] = []
	for index: int in 6:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 24601 + index
		randoms.append(random)
		(result["guest_rng_seeds"] as Array).append(str(random.seed))
	var entries: Array[Vector2i] = world.grid.entries()
	if entries.is_empty():
		result["error"] = "Joined-table review has no real street entry"
		return result
	var party: Party = sim.add_party(entries[0], randoms)
	if party == null or party.size() != 6:
		result["error"] = "The simulation refused the explicit six-person party"
		return result
	var start_tick: int = world.now
	for tick: int in WALK_BUDGET:
		if party.seated or party.departing:
			break
		main.call("run_ticks", 1)
	result["world_ticks_advanced"] = world.now - start_tick
	result["frozen_world_tick"] = world.now
	result["party_member_ids"] = party.member_ids.duplicate()
	result["canonical_group_id"] = party.table_item_id
	result["booked_table_ids"] = party.booked_table_ids.duplicate()
	if not party.seated or party.departing:
		result["error"] = "The real party did not walk to all six seats within the review's bounded tick limit"
		return result
	main.call("refresh_presentation")
	return result


static func evidence(main: Node, root: Window, fixture: Dictionary) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var shop: ShopView = main.get_node("ShopView") as ShopView
	var camera: Camera3D = main.get_node("CameraRig/Camera3D") as Camera3D
	var ids: Array[int] = []
	ids.assign(fixture.get("table_ids", []))
	var guest_ids: Array[int] = []
	guest_ids.assign(fixture.get("party_member_ids", []))
	if ids.size() != 3 or guest_ids.size() != 6:
		return {"available": false}
	var first: CustomerAgent = world.agent(guest_ids[0]) as CustomerAgent
	var party: Party = first.party if first != null else null
	var group: DiningSeats.Group = world.grid.dining_group(ids[0])
	if party == null or group == null:
		return {"available": false}
	var guests: Array[Dictionary] = []
	for id: int in guest_ids:
		var guest: CustomerAgent = world.agent(id) as CustomerAgent
		var person: PersonView = shop.agent_nodes.get(id) as PersonView
		if guest == null or person == null:
			return {"available": false}
		var owner_id: int = world.grid.dining_owner_id(ids[0], guest.seat_cell)
		var owner: PlacedItem = world.grid.item(owner_id)
		var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, world)
		var facing: Vector3 = Vector3(frame.facing_direction.x, 0.0, frame.facing_direction.z).normalized()
		var drawn_facing: Vector3 = -person.global_basis.z
		drawn_facing.y = 0.0
		var head: Vector3 = person.global_transform * person.head_anchor_position()
		var pivot: Node3D = person.get_node("ModelPivot") as Node3D
		var inside_table: bool = false
		for member: int in group.member_ids:
			inside_table = inside_table or world.grid.item(member).cells.has(guest.seat_cell)
		guests.append({"id": id, "same_party": guest.party == party, "state": int(guest.state),
			"physical_table_id": guest.table_item_id, "physical_owner_id": owner_id,
			"physical_map_id": world.grid.dining_table_id(guest.seat_cell),
			"furnishing_id": world.grid.dining_furnishing_id(guest.seat_cell),
			"cell": vector(guest.cell), "seat": vector(guest.seat_cell), "arrived": guest.has_arrived(),
			"hold_owner": owner.reserved_by(guest.seat_cell) if owner != null else -1,
			"physical_seat_member": owner != null and owner.seat_cells.has(guest.seat_cell),
			"inside_member_footprint": inside_table,
			"original_group_members": guest.booked_table_ids.duplicate(),
			"expected_seated": frame.seated, "expected_clip": String(frame.clip),
			"actual_clip": String(person.current_clip()),
			"actual_player_clip": String(person._player.current_animation) if person._player != null else "",
			"actual_skeleton_ready": person._skeleton != null, "actual_model": String(person.model_name()),
			"expected_model": String(PersonPresentation.model_for(guest.role, guest.id, guest.customer_type_id)),
			"actual_model_scene": person._model.scene_file_path if person._model != null else "",
			"expected_model_scene": PersonPresentation.model_path_for(guest.role, guest.id, guest.customer_type_id),
			"model_visible": person._model != null and person._model.is_visible_in_tree() and person.is_visible_in_tree(),
			"expected_seat_lift": frame.seat_height, "actual_seat_lift": pivot.position.y,
			"physical_facing_dot": drawn_facing.normalized().dot(facing),
			"head": point(head, camera), "drawn_feet": point(person.global_position, camera)})
	var tables: Array[Dictionary] = []
	for id: int in group.member_ids:
		var item: PlacedItem = world.grid.item(id)
		var visual: ItemVisual = shop.item_nodes.get(id) as ItemVisual
		var prop: PropView = visual.prop if visual != null else null
		if item == null or prop == null:
			return {"available": false}
		var box: AABB = prop.global_transform * prop.get_combined_aabb()
		tables.append({"id": id, "definition": String((item.def as ItemDef).id),
			"origin": vector(item.origin), "turns": item.quarter_turns,
			"physical_seats": vectors(item.seat_cells), "scene": prop.scene_file_path,
			"visible": prop.is_visible_in_tree(), "screen_bounds": screen_bounds(box, camera),
			"inside_viewport": root.get_visible_rect().encloses(project_bounds(box, camera))})
	var inspection: Dictionary = main.call("inspection_state")
	return {"available": true, "use_saves": main.get("use_saves"), "day": world.clock.day,
		"phase": int(world.clock.phase), "world_tick": world.now,
		"clock_speed": root.get_node("Clock").get("speed"), "customer_count": sim.customers().size(),
		"canonical_group_id": group.id, "group_members": group.member_ids.duplicate(),
		"group_seats": vectors(group.seat_cells), "group_joined": group.is_joined(),
		"group_usable_capacity": DiningSeats.usable_cells(world.grid, world.grid.item(ids[0])).size(),
		"party_table_id": party.table_item_id, "party_members": party.member_ids.duplicate(),
		"party_seated": party.seated, "party_departing": party.departing,
		"booked_table_ids": party.booked_table_ids.duplicate(), "guests": guests, "tables": tables,
		"inspection_visible": bool(inspection.get("panel_visible", false)),
		"menu_visible": bool(main.call("is_menu_visible")), "camera": {"projection": camera.projection,
			"size": camera.size, "transform": transform(camera.global_transform), "cull_mask": camera.cull_mask},
		"visibility_scope": "Actual posed head/feet and table bounds are in the native viewport; occlusion still requires reviewing the complete image."}


static func valid(state: Dictionary, fixture: Dictionary) -> bool:
	if fixture.get("error") != "" or state.get("available") != true or state.get("use_saves") != false \
			or state.get("day") != 1 or state.get("phase") != SimClock.Phase.OPEN or state.get("clock_speed") != 0 \
			or state.get("world_tick") != fixture.get("frozen_world_tick") or state.get("customer_count") != 6 \
			or state.get("group_joined") != true or state.get("group_usable_capacity") != 6 \
			or state.get("group_members") != fixture.get("table_ids") \
			or state.get("group_seats") != vectors(SEATS) or state.get("party_members") != fixture.get("party_member_ids") \
			or state.get("party_table_id") != state.get("canonical_group_id") or state.get("party_seated") != true \
			or state.get("party_departing") != false or state.get("booked_table_ids") != fixture.get("table_ids") \
			or state.get("inspection_visible") != false or state.get("menu_visible") != false:
		return false
	var seen: Dictionary = {}
	for guest: Dictionary in state["guests"]:
		var seat: Array = guest["seat"]
		var key: String = str(seat)
		if seen.has(key):
			return false
		seen[key] = true
		if guest["same_party"] != true or guest["arrived"] != true or guest["cell"] != seat \
				or guest["physical_table_id"] != guest["physical_owner_id"] \
				or guest["physical_map_id"] != guest["physical_owner_id"] \
				or guest["furnishing_id"] != guest["physical_owner_id"] \
				or guest["hold_owner"] != guest["id"] or guest["physical_seat_member"] != true \
				or guest["inside_member_footprint"] != false \
				or guest["original_group_members"] != fixture["table_ids"] or guest["expected_seated"] != true \
				or guest["expected_clip"] != "sit" or guest["actual_clip"] != "sit" \
				or guest["actual_player_clip"] != "sit" or guest["actual_skeleton_ready"] != true \
				or guest["actual_model"] != guest["expected_model"] \
				or guest["actual_model_scene"] != guest["expected_model_scene"] or guest["model_visible"] != true \
				or not is_equal_approx(float(guest["actual_seat_lift"]), float(guest["expected_seat_lift"])) \
				or float(guest["physical_facing_dot"]) < 0.999 \
				or guest["state"] not in [CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD,
					CustomerAgent.State.EATING, CustomerAgent.State.PAYING]:
			return false
		for anchor: String in ["head", "drawn_feet"]:
			if guest[anchor]["in_frustum"] != true or guest[anchor]["inside_viewport"] != true:
				return false
	var tables: Array = state["tables"]
	if tables.size() != TARGETS.size() or seen.size() != 6:
		return false
	for index: int in tables.size():
		var table: Dictionary = tables[index]
		if table["id"] != fixture["table_ids"][index] or table["definition"] != "table_2" \
				or table["origin"] != vector(TARGETS[index]) or table["turns"] != 1 \
				or table["scene"] != "res://assets/props/table_2.tscn" or table["visible"] != true \
				or table["inside_viewport"] != true:
			return false
	return true


static func vector(value: Vector2i) -> Array[int]:
	return [value.x, value.y]


static func vectors(values: Array[Vector2i]) -> Array:
	var result: Array = []
	for value: Vector2i in values:
		result.append(vector(value))
	return result


static func transform(value: Transform3D) -> Array:
	return [[value.basis.x.x, value.basis.x.y, value.basis.x.z],
		[value.basis.y.x, value.basis.y.y, value.basis.y.z],
		[value.basis.z.x, value.basis.z.y, value.basis.z.z],
		[value.origin.x, value.origin.y, value.origin.z]]


static func point(value: Vector3, camera: Camera3D) -> Dictionary:
	var screen: Vector2 = camera.unproject_position(value)
	return {"world": [value.x, value.y, value.z], "screen": [screen.x, screen.y],
		"in_frustum": camera.is_position_in_frustum(value),
		"inside_viewport": camera.get_viewport().get_visible_rect().has_point(screen)}


static func project_bounds(box: AABB, camera: Camera3D) -> Rect2:
	var result: Rect2 = Rect2()
	for index: int in 8:
		var screen: Vector2 = camera.unproject_position(box.get_endpoint(index))
		result = Rect2(screen, Vector2.ZERO) if index == 0 else result.expand(screen)
	return result


static func screen_bounds(box: AABB, camera: Camera3D) -> Array:
	var rect: Rect2 = project_bounds(box, camera)
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
