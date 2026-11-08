extends RefCounted
## Two paused, unsaved booking views using the existing joined-table capture:
## morning offer and one real held/served booking party. Table moves, accept,
## opening, party arrival, routing and seating use normal game paths; offer
## odds, party size and quarter-hour slot are explicit visual-fixture controls.

const FRAMES: Array[int] = [12, 90]
## Guests now walk in single file around people and furniture in the roomier
## starter shop; the party sits after 278 ticks, so this keeps a margin.
const WALK_BUDGET: int = 360
const TABLE_COUNT: int = 3
const SLOT_MINUTE: int = 12 * 60 + 15


## The three real starter tables, west to east, from the actual grid.
static func starter_tables(world: SimWorld) -> Array[PlacedItem]:
	var tables: Array[PlacedItem] = []
	for item: PlacedItem in world.grid.items():
		var definition: ItemDef = item.def as ItemDef
		if definition != null and definition.id == &"table_2":
			tables.append(item)
	tables.sort_custom(func(a: PlacedItem, b: PlacedItem) -> bool: return a.origin.x < b.origin.x)
	return tables


## The tables close up end to end, quarter-turned, starting one cell east of
## the west starter table on its row, so the join sits in the dining room
## whatever the starter layout's size.
static func targets_for(first: Vector2i) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	for index: int in TABLE_COUNT:
		targets.append(first + Vector2i(1 + 2 * index, 0))
	return targets


## One outside seat per table on its north side, then one each on its south side.
static func seats_for(targets: Array[Vector2i]) -> Array[Vector2i]:
	var seats: Array[Vector2i] = []
	for target: Vector2i in targets:
		seats.append(target + Vector2i(0, -1))
	for target: Vector2i in targets:
		seats.append(target + Vector2i(0, 2))
	return seats


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
		elif argument == "--frames=12,90":
			frames += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		else:
			return {"enabled": false, "error": "Joined-table booking review uses only paused Main frames 12 and 90"}
	if speeds != 1 or frames != 1 or scenes > 1:
		return {"enabled": false, "error": "--joined-tables-review requires --speed=0 --frames=12,90"}
	return {"enabled": true, "error": ""}


static func prepare(main: Node, root: Window) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var clock: Node = root.get_node("Clock")
	var result: Dictionary = {"error": "", "kind": "explicit_unsaved_joined_booking_fixture",
		"description": "Explicit unsaved visual setup: offer probability is forced to 100%, size is fixed at six, and the offer's legal slot is set to 12:15. Frame 12 captures the live morning offer before interaction. At frame 24 the real Accept button is pressed, the fixture advances to the offer's service day, and normal service starts. The scheduled guest's saved private seeds, held-group selection, routing and seating use the live simulation; only walk-in countdown is delayed in this visual fixture. Frame 90 captures the real seated booking and its held-group label.",
		"walk_tick_limit": WALK_BUDGET, "guest_rng_seeds": [], "table_ids": []}
	if world == null or sim == null or main.get("use_saves") != false or world.now != 0 \
			or world.clock.day != 1 or world.clock.phase != SimClock.Phase.MORNING or clock.get("speed") != 0:
		result["error"] = "Joined-table review requires a fresh paused unsaved Main morning"
		return result
	var starters: Array[PlacedItem] = starter_tables(world)
	if starters.size() != TABLE_COUNT:
		result["error"] = "Joined-table review cannot find its actual starter table"
		return result
	var ids: Array[int] = []
	for item: PlacedItem in starters:
		ids.append(item.id)
	var targets: Array[Vector2i] = targets_for(starters[0].origin)
	var seats: Array[Vector2i] = seats_for(targets)
	result["targets"] = vectors(targets)
	result["seats"] = vectors(seats)
	for index: int in ids.size():
		if not main.call("shop_move", ids[index], targets[index], 1):
			result["error"] = "Joined-table review's normal table move was refused"
			return result
	result["table_ids"] = ids
	var group: DiningSeats.Group = world.grid.dining_group(ids[0])
	if group == null or group.member_ids != ids or group.seat_cells != seats:
		result["error"] = "Three moved tables did not derive the expected six outside seats"
		return result
	var owner_progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var level_two_xp: int = owner_progress.threshold_for(2) - owner_progress.total_xp
	owner_progress.award_bonus(level_two_xp)
	var hud: Node = main.get_node("HUD")
	hud.call("set_owner_progress", owner_progress.level,
		owner_progress.xp_into_level(), owner_progress.xp_in_level())
	var menu: MenuSettings = main.get("menu_settings") as MenuSettings
	menu.set_owner_level(2)
	sim.set_customer_level(2)
	var tuning: BookingTuning = preload("res://data/balance/bookings.tres").duplicate() as BookingTuning
	tuning.offer_chance = 1.0
	tuning.min_party_size = 6
	tuning.max_party_size = 6
	var model: GroupBooking = GroupBooking.new(tuning)
	var menu_ids: Array[StringName] = [&"burger"]
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 463316
	var provider: Callable = func() -> RandomNumberGenerator:
		return random
	var offer: Dictionary = model.plan_offer(world.clock.day, 2, menu_ids,
		world.clock.display_open_minute, world.clock.display_close_minute, provider)
	if offer.is_empty():
		result["error"] = "Joined-table booking fixture could not create its explicit offer"
		return result
	model.offer["slot_minute"] = SLOT_MINUTE # First legal slot after the 75-minute hold.
	main.set("group_booking", model)
	sim.configure_booking(model)
	main.call("_refresh_booking_offer")
	if not main.call("set_menu_visible", true):
		result["error"] = "Joined-table booking fixture could not show the morning offer"
		return result
	result["offer_day"] = world.clock.day
	result["service_day"] = int(model.offer["service_day"])
	result["party_size"] = 6
	result["slot_minute"] = SLOT_MINUTE
	result["offer_recipe"] = String(model.offer["recipe_id"])
	result["menu_ids"] = ["burger"]
	result["table_ids"] = ids
	result["targets"] = vectors(targets)
	result["seats"] = vectors(seats)
	return result


static func begin_booking_service(main: Node, root: Window, fixture: Dictionary) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var model: GroupBooking = main.get("group_booking") as GroupBooking
	var result: Dictionary = fixture.duplicate(true)
	result["error"] = ""
	result["opening_action"] = "MenuPanel/BookingOffer/Buttons/Accept.pressed"
	result["held_group_id"] = 0
	result["party_member_ids"] = []
	result["guest_rng_seeds"] = []
	if world == null or sim == null or model == null or world.clock.phase != SimClock.Phase.MORNING \
			or model.offer.is_empty() or int(model.offer.get("party_size", 0)) != 6:
		result["error"] = "Joined-table booking offer is not ready for acceptance"
		return result
	var accept: Button = main.get_node("Overlay/MenuPanel/Panel/Content/BookingOffer/Buttons/Accept") as Button
	accept.pressed.emit()
	if not model.has_active_booking():
		result["error"] = "The real offer button did not accept the booking"
		return result
	# Visual-only day advance: the offer and acceptance are day one, while the
	# existing normal service start opens its scheduled day two.
	world.clock.day = int(fixture["service_day"])
	(root.get_node("Clock").get("sim") as SimClock).day = world.clock.day
	sim.start_day()
	sim.spawner._remaining = 100000
	var context: Button = main.get_node("HUD/Top/Row/Context") as Button
	if context.disabled:
		result["error"] = "Joined-table booking review cannot open through the real HUD action"
		return result
	context.pressed.emit()
	root.get_node("Clock").call("set_speed", 0)
	if world.clock.phase != SimClock.Phase.OPEN:
		result["error"] = "The normal HUD action did not open booking service"
		return result
	result["service_start_action"] = "HUD/Top/Row/Context.pressed"
	# The 12:15 slot starts its 75-minute hold at 11:00 opening. Normal sim ticks
	# establish the actual marker before the scheduled party arrives.
	main.call("run_ticks", 60)
	var held_group: int = sim.world.booking_hold.group_for_booking(world,
		int(model.booking["booking_id"]))
	if held_group != int(fixture["table_ids"][0]):
		result["error"] = "The scheduled six-seat joined group was not held during service"
		return result
	var slot_ticks: int = ceili(float(SLOT_MINUTE - world.clock.display_open_minute) \
		/ float(world.clock.display_close_minute - world.clock.display_open_minute) * world.clock.open_ticks)
	main.call("run_ticks", maxi(0, slot_ticks - 60))
	main.call("run_ticks", WALK_BUDGET) # Normal single-file entry and seated-party movement.
	var party: Party = null
	for customer: CustomerAgent in sim.customers():
		if customer.party != null and customer.party.booking_id == int(model.booking["booking_id"]):
			party = customer.party
			break
	if party == null or not party.seated or party.departing:
		result["error"] = "The real booked party did not sit within its bounded walk budget"
		return result
	result["held_group_id"] = held_group
	result["service_day"] = int(model.booking["service_day"])
	result["party_member_ids"] = party.member_ids.duplicate()
	for id: int in party.member_ids:
		var customer: CustomerAgent = world.agent(id) as CustomerAgent
		if customer == null:
			result["error"] = "A booked guest left before the native hold capture"
			return result
		(result["guest_rng_seeds"] as Array).append(str(customer.rng.seed))
	result["frozen_world_tick"] = world.now
	main.call("refresh_presentation")
	return result


static func evidence(main: Node, root: Window, fixture: Dictionary, frame: int) -> Dictionary:
	if frame == 12:
		var offer_box: Control = main.get_node("Overlay/MenuPanel/Panel/Content/BookingOffer") as Control
		var heading: Label = offer_box.get_node("Heading") as Label
		var details: Label = offer_box.get_node("Details") as Label
		var accept: Button = offer_box.get_node("Buttons/Accept") as Button
		var decline: Button = offer_box.get_node("Buttons/Decline") as Button
		var model: GroupBooking = main.get("group_booking") as GroupBooking
		var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
		var level_label: Label = main.get_node("HUD/Top/Row/OwnerProgress/OwnerLevel") as Label
		return {"available": true, "frame": frame, "visible": offer_box.is_visible_in_tree(),
			"heading": heading.text, "details": details.text, "accept_enabled": accept.is_visible_in_tree() and not accept.disabled,
			"decline_enabled": decline.is_visible_in_tree() and not decline.disabled,
			"offer_day": model.offer.get("offer_day", -1), "service_day": model.offer.get("service_day", -1),
			"active_booking": model.has_active_booking(), "use_saves": main.get("use_saves"),
			"owner_level": progress.level, "owner_level_label": level_label.text}
	if frame != 90:
		return {"available": false, "frame": frame}
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
		var presentation_frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, world)
		var facing: Vector3 = Vector3(presentation_frame.facing_direction.x, 0.0, presentation_frame.facing_direction.z).normalized()
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
			"expected_seated": presentation_frame.seated, "expected_clip": String(presentation_frame.clip),
			"actual_clip": String(person.current_clip()),
			"actual_player_clip": String(person._player.current_animation) if person._player != null else "",
			"actual_skeleton_ready": person._skeleton != null, "actual_model": String(person.model_name()),
			"expected_model": String(PersonPresentation.model_for(guest.role, guest.id, guest.customer_type_id)),
			"actual_model_scene": person._model.scene_file_path if person._model != null else "",
			"expected_model_scene": PersonPresentation.model_path_for(guest.role, guest.id, guest.customer_type_id),
			"model_visible": person._model != null and person._model.is_visible_in_tree() and person.is_visible_in_tree(),
			"expected_seat_lift": presentation_frame.seat_height, "actual_seat_lift": pivot.position.y,
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
	var marker: Label3D = shop.get_node_or_null("BookingReservationMarker") as Label3D
	var model: GroupBooking = main.get("group_booking") as GroupBooking
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var level_label: Label = main.get_node("HUD/Top/Row/OwnerProgress/OwnerLevel") as Label
	var header_rect: Rect2 = (main.get_node("HUD/Top") as Control).get_global_rect()
	var status_rect: Rect2 = (main.get_node("HUD/BookingStatus") as Control).get_global_rect()
	return {"available": true, "frame": frame, "use_saves": main.get("use_saves"), "day": world.clock.day,
		"owner_level": progress.level, "owner_level_label": level_label.text,
		"header_bounds": bounds(header_rect), "booking_status_bounds": bounds(status_rect),
		"notices_bottom": main.get_node("HUD").call("_notices_bottom"),
		"viewport_size": vector2(root.get_visible_rect().size),
		"phase": int(world.clock.phase), "world_tick": world.now,
		"clock_speed": root.get_node("Clock").get("speed"), "customer_count": sim.customers().size(),
		"canonical_group_id": group.id, "group_members": group.member_ids.duplicate(),
		"group_seats": vectors(group.seat_cells), "group_joined": group.is_joined(),
		"group_usable_capacity": DiningSeats.usable_cells(world.grid, world.grid.item(ids[0])).size(),
		"booking_id": model.booking.get("booking_id", -1), "booking_status": model.booking.get("status", ""),
		"held_group_id": sim.world.booking_hold.group_for_booking(world, int(model.booking.get("booking_id", -1))),
		"marker_visible": marker != null and marker.is_visible_in_tree(),
		"marker_text": marker.text if marker != null else "",
		"marker_position": vector3(marker.global_position) if marker != null else [],
		"party_table_id": party.table_item_id, "party_members": party.member_ids.duplicate(),
		"party_seated": party.seated, "party_departing": party.departing,
		"booked_table_ids": party.booked_table_ids.duplicate(), "guests": guests, "tables": tables,
		"inspection_visible": bool(inspection.get("panel_visible", false)),
		"menu_visible": bool(main.call("is_menu_visible")), "camera": {"projection": camera.projection,
			"size": camera.size, "transform": transform(camera.global_transform), "cull_mask": camera.cull_mask},
		"visibility_scope": "Actual posed head/feet and table bounds are in the native viewport; occlusion still requires reviewing the complete image."}


static func valid(state: Dictionary, fixture: Dictionary, frame: int) -> bool:
	if frame == 12:
		return state.get("available") == true and state.get("frame") == 12 and state.get("visible") == true \
			and state.get("heading") == "Tomorrow's booking" and state.get("accept_enabled") == true \
			and state.get("decline_enabled") == true and state.get("offer_day") == 1 \
			and state.get("service_day") == 2 and state.get("active_booking") == false \
			and state.get("use_saves") == false and state.get("owner_level") == 2 \
			and state.get("owner_level_label") == "Lv 2" and String(state.get("details", "")).contains("tomorrow") \
			and String(state.get("details", "")).contains("12:15") and String(state.get("details", "")).contains("12:30") \
			and String(state.get("details", "")).contains("deposit")
	if frame != 90:
		return false
	var header: Rect2 = rect_from_bounds(state.get("header_bounds", {}))
	var status: Rect2 = rect_from_bounds(state.get("booking_status_bounds", {}))
	var viewport: Array = state.get("viewport_size", [])
	if viewport.size() != 2 or status.size.x <= 0.0 or status.size.y <= 0.0 \
			or status.position.y < float(state.get("notices_bottom", header.end.y)) + 7.5 or status.position.x < 0.0 \
			or status.end.x > float(viewport[0]) or status.end.y > float(viewport[1]) \
			or header.intersects(status):
		return false
	if fixture.get("error") != "" or state.get("available") != true or state.get("use_saves") != false \
			or state.get("day") != fixture.get("service_day") or state.get("phase") != SimClock.Phase.OPEN or state.get("clock_speed") != 0 \
			or state.get("world_tick") != fixture.get("frozen_world_tick") or state.get("customer_count") != 6 \
			or state.get("booking_status") != "accepted" or state.get("held_group_id") != fixture.get("table_ids", [0])[0] \
			or state.get("owner_level") != 2 or state.get("owner_level_label") != "Lv 2" \
			or state.get("marker_visible") != true or not String(state.get("marker_text", "")).contains("Reserved") \
			or not String(state.get("marker_text", "")).contains("6 guests") \
			or state.get("group_joined") != true or state.get("group_usable_capacity") != 6 \
			or state.get("group_members") != fixture.get("table_ids") \
			or state.get("group_seats") != fixture.get("seats") or state.get("party_members") != fixture.get("party_member_ids") \
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
	var targets: Array = fixture.get("targets", [])
	if tables.size() != TABLE_COUNT or targets.size() != TABLE_COUNT or seen.size() != 6:
		return false
	for index: int in tables.size():
		var table: Dictionary = tables[index]
		if table["id"] != fixture["table_ids"][index] or table["definition"] != "table_2" \
				or table["origin"] != targets[index] or table["turns"] != 1 \
				or table["scene"] != "res://assets/props/table_2.tscn" or table["visible"] != true \
				or table["inside_viewport"] != true:
			return false
	return true


static func vector(value: Vector2i) -> Array[int]:
	return [value.x, value.y]


static func vector3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


static func vector2(value: Vector2) -> Array[float]:
	return [value.x, value.y]


static func bounds(value: Rect2) -> Dictionary:
	return {"x": value.position.x, "y": value.position.y,
		"width": value.size.x, "height": value.size.y}


static func rect_from_bounds(value: Dictionary) -> Rect2:
	return Rect2(Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0))),
		Vector2(float(value.get("width", 0.0)), float(value.get("height", 0.0))))


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
