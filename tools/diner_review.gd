class_name DinerReview
extends RefCounted
## Two explicit, unsaved Main fixtures. No alternate renderer, sim algorithm,
## palette, light or generated geometry. Wall props are view-only staging.

const MAIN_SCENE: String = "res://src/world/main.tscn"
const MANIFEST: String = "res://assets/made/diner/diner_manifest.json"
const THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const PERSON: PackedScene = preload("res://assets/people/person.tscn")
const HEAD_GEOMETRY: GDScript = preload("res://tools/seated_head_geometry.gd")
const SIZE: Vector2i = Vector2i(1600, 900)
const WALK_BUDGET: int = 160
const CROP_SCALE: int = 3
const CROP_PADDING: int = 12
const CROP_FILE: String = "shot_0090_booth_3x.png"
## Stable contract supplied by SeatedHeadGeometry; no bind-pose AABB substitute.
const POSED_HEAD_PROVENANCE: String = "native Mini head-mesh POSITION/JOINTS/WEIGHTS, imported Skin inverse binds, current Skeleton3D global poses, actual node transforms"
const POSED_CLEARANCE_METRIC: String = HEAD_GEOMETRY.CLEARANCE_METRIC
const IDS: Array[StringName] = [&"diner_booth", &"diner_stool", &"diner_open_sign",
	&"diner_chalkboard", &"diner_wall_art_a", &"diner_wall_art_b"]
const NAMES: Array[String] = ["Booth", "Counter stool", "OPEN sign", "Menu board", "Wall art A", "Wall art B"]
const REFERENCES: Array[String] = ["benchCushion", "stoolBar", "lampWall", "wallWindow", "wallWindow", "wallWindow"]
const COMPARISON: String = "DinerComparison"
const WALLS: String = "DinerWallStaging"
const NOTICE: String = "Diner review fixture - unsaved; wall pieces are view-only staging, not player wall placement."
const PURCHASES: Array[Dictionary] = [
	{"id": &"cross_table", "cell": Vector2i(2, 6), "turns": 0},
	{"id": &"diner_booth", "cell": Vector2i(2, 7), "turns": 0},
	{"id": &"diner_booth", "cell": Vector2i(2, 5), "turns": 2},
	{"id": &"bar_counter", "cell": Vector2i(6, 6), "turns": 0},
	{"id": &"diner_stool", "cell": Vector2i(6, 7), "turns": 0},
	{"id": &"diner_stool", "cell": Vector2i(7, 7), "turns": 0},
]


static func options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"enabled": false, "error": ""}
	for argument: String in arguments:
		if argument.begins_with("--diner-review"):
			if result["enabled"] or argument != "--diner-review":
				result["error"] = "--diner-review is one flag without a value"
				return result
			result["enabled"] = true
	if not result["enabled"]:
		return result
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	for argument: String in arguments:
		if argument == "--diner-review" or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=12,90":
			frames += 1
		elif argument == "--scene=" + MAIN_SCENE:
			scenes += 1
		else:
			result["error"] = "--diner-review requires only paused Main frames 12,90"
			return result
	if speeds != 1 or frames != 1 or scenes > 1:
		result["error"] = "--diner-review requires one --speed=0 and one --frames=12,90"
	return result


static func prepare(main: Node, context_root: Node) -> Dictionary:
	var result: Dictionary = {"error": "", "kind": "explicit_unsaved_diner_fixture",
		"notice": NOTICE, "guest_tick_budget": WALK_BUDGET, "world_ticks_advanced": 0}
	var world: SimWorld = main.get("world") as SimWorld
	var shop: ShopView = main.get_node_or_null("ShopView") as ShopView
	var rig: CameraRig = main.get_node_or_null("CameraRig") as CameraRig
	var clock: Node = context_root.get_node_or_null("Clock")
	if main.scene_file_path != MAIN_SCENE or main.get("use_saves") != false or world == null \
			or shop == null or rig == null or clock == null or clock.get("sim") != world.clock \
			or clock.get("speed") != 0 or world.now != 0 or world.clock.day != 1 \
			or world.clock.phase != SimClock.Phase.MORNING or main.has_node(COMPARISON):
		result["error"] = "diner review requires fresh paused unsaved Main"
		return result
	var stage: Node3D = Node3D.new()
	stage.name = COMPARISON
	main.add_child(stage)
	for index: int in range(IDS.size()):
		var pair: Node3D = Node3D.new()
		pair.name = String(IDS[index])
		pair.position = Vector3(1.2 + 2.25 * float(index % 3), 0.0, 1.25 + 2.65 * float(index / 3))
		stage.add_child(pair)
		var packed: PackedScene = load("res://assets/props/%s.tscn" % IDS[index]) as PackedScene
		var made: PropView = packed.instantiate() as PropView if packed != null else null
		var reference: PropView = _reference(REFERENCES[index])
		if made == null or reference == null:
			if reference != null:
				reference.free()
			result["error"] = "diner comparison source is missing: " + String(IDS[index])
			return result
		made.name = "Made"
		made.position.x = -0.55
		pair.add_child(made)
		reference.name = "Kenney"
		reference.position.x = 0.55
		pair.add_child(reference)
		_label(pair, "MadeLabel", "MADE\n" + NAMES[index], made.position + Vector3(0, 1.85, 0))
		_label(pair, "KenneyLabel", "KENNEY\n" + REFERENCES[index], reference.position + Vector3(0, 1.85, 0))
	var mini: PersonView = PERSON.instantiate() as PersonView
	mini.name = "ScaleMini"
	mini.set_look(&"owner")
	stage.add_child(mini)
	mini.position = Vector3(3.45, 0.0, 3.0)
	mini.face_direction(Vector3.FORWARD)
	mini.set_playback_speed(0.0)
	_label(stage, "ScaleLabel", "MINI CHARACTER\nshared scale", Vector3(4.35, 0.6, 3.0))
	_notice(main, "Six made pieces beside unchanged Kenney references; native Mini Character for scale.\n" + NOTICE)
	_comparison_visibility(shop, false)
	_camera(rig, Vector2(3.45, 3.1), 180.0, 5.5)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	# The capture camera is fixed. Native text planes face it directly, avoiding
	# billboard rendering's conservative cubical culling bounds around each label.
	for label: Label3D in stage.find_children("*Label", "Label3D", true, false):
		label.global_basis = camera.global_basis
	result["baseline"] = snapshot(main, context_root)
	result["lights"] = _lights(main)
	return result


## Real shop APIs author the layout. Six explicit arrivals walk and reserve seats
## through CustomerAgent.tick(), bounded independently; no hand-set sit state,
## no clock/service advancement, earned progress or balance claim.
static func furnish(main: Node, context_root: Node, fixture: Dictionary) -> Dictionary:
	var result: Dictionary = fixture.duplicate(true)
	var world: SimWorld = main.get("world") as SimWorld
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var content: ContentDB = main.get("content") as ContentDB
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var shop: ShopView = main.get_node_or_null("ShopView") as ShopView
	var economy: Node = context_root.get_node_or_null("Economy")
	if not String(result.get("error", "")).is_empty() or not main.has_node(COMPARISON) \
			or world == null or sim == null or content == null or progress == null or editor == null \
			or shop == null or economy == null or snapshot(main, context_root) != result.get("baseline", {}):
		result["error"] = "diner fixture changed before furnished staging"
		return result
	main.get_node(COMPARISON).queue_free()
	_comparison_visibility(shop, true)
	var owner: Dictionary = progress.to_dict()
	owner["total_xp"] = progress.threshold_for(4)
	owner["level"] = 4
	owner["last_awarded_day"] = 0
	if not progress.from_dict(owner):
		result["error"] = "explicit diner owner-level fixture was rejected"
		return result
	editor.set_owner_level(4)
	(main.get_node("Overlay/BuildCatalogue") as BuildCatalogue).set_owner_level(4)
	(main.get("menu_settings") as MenuSettings).set_owner_level(4)
	main.get_node("HUD").call("set_owner_progress", 4, progress.xp_into_level(), progress.xp_in_level())
	for item: PlacedItem in world.grid.items():
		if (item.def as ItemDef).id == &"table_2" and int(main.call("shop_sell", item.id)) < 0:
			result["error"] = "starter table sale was refused"
			return result
	var total: int = 0
	for row: Dictionary in PURCHASES:
		var definition: ItemDef = content.item(row["id"])
		if definition == null:
			result["error"] = "diner purchase definition is missing"
			return result
		total += definition.price
	var grant: int = maxi(0, total - int(economy.get("cash")))
	if grant > 0:
		economy.call("add_cash", grant, Ledger.OTHER)
	var purchased: Array[int] = []
	for row: Dictionary in PURCHASES:
		if not bool(main.call("shop_buy", row["id"], row["cell"], row["turns"])):
			result["error"] = "diner fixture purchase was refused: " + String(row["id"])
			return result
		var item: PlacedItem = world.grid.item_at(row["cell"])
		if item == null or (item.def as ItemDef).id != row["id"]:
			result["error"] = "diner fixture purchase is absent from grid"
			return result
		purchased.append(item.id)
	var plan: DiningSeats.Plan = DiningSeats.derive(world.grid)
	if not plan.failures.is_empty() or plan.links.size() != 6:
		result["error"] = "diner fixture must have six valid production dining links"
		return result
	var guests: Array[int] = []
	var ticks: Array[int] = []
	for index: int in range(6):
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 12300 + index
		var guest: CustomerAgent = sim.add_customer(Vector2i(6, 11), random)
		var walked: int = 0
		for tick: int in range(WALK_BUDGET):
			guest.tick(world)
			walked = tick + 1
			if AgentPresentationController.frame_for(guest, world).seated:
				break
		if not AgentPresentationController.frame_for(guest, world).seated:
			result["error"] = "guest did not reach a reserved diner seat within its bounded fixture walk"
			return result
		guests.append(guest.id)
		ticks.append(walked)
	var wall_stage: Node3D = Node3D.new()
	wall_stage.name = WALLS
	main.add_child(wall_stage)
	for index: int in range(2, IDS.size()):
		var packed: PackedScene = load("res://assets/props/%s.tscn" % IDS[index]) as PackedScene
		var prop: PropView = packed.instantiate() as PropView
		prop.name = String(IDS[index])
		prop.position = Vector3([1.0, 2.05, 4.7, 5.8][index - 2], 0.0, 2.75)
		prop.rotation.y = PI
		wall_stage.add_child(prop)
	# Aim farther toward the back wall: the entire corner moves down within the
	# image, clearing both the native HUD and the strict eight-pixel image margin.
	_camera(main.get_node("CameraRig") as CameraRig, Vector2(2.5, 2.9), 45.0, 5.4)
	shop._process(0.0)
	_notice(main, "Furnished diner: six explicit arrivals reached real reserved booth/stool seats.\n" + NOTICE)
	result.merge({"owner_progress_fixture": owner, "cash_grant": grant, "purchase_total": total,
		"purchased_ids": purchased, "guest_ids": guests, "guest_ticks": ticks})
	result["furnished_baseline"] = snapshot(main, context_root)
	return result


static func snapshot(main: Node, context_root: Node) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var game: Node = context_root.get_node_or_null("GameState")
	var clock: Node = context_root.get_node_or_null("Clock")
	var guests: Array[Dictionary] = []
	for guest: CustomerAgent in sim.customers():
		guests.append({"id": guest.id, "state": int(guest.state), "cell": _cell(guest.cell),
			"seat": _cell(guest.seat_cell), "table": guest.table_item_id,
			"rng_seed": str(guest.rng.seed), "rng_state": str(guest.rng.state)})
	return {"world_tick": world.now, "clock": world.clock.to_dict(), "speed": clock.get("speed"),
		"run": game.call("_capture_save"), "restaurant_rng": [str(sim.rng.seed), str(sim.rng.state)],
		"guests": guests, "served": sim.served_today, "lost": sim.lost_today}


## All evidence is queried from actual imported resources and current Main nodes.
static func evidence(main: Node, context_root: Node, frame: int) -> Dictionary:
	var camera: Camera3D = main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var shop: ShopView = main.get_node_or_null("ShopView") as ShopView
	var world: SimWorld = main.get("world") as SimWorld
	var stage: Node3D = main.get_node_or_null(COMPARISON if frame == 12 else WALLS) as Node3D
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if camera == null or shop == null or world == null or stage == null or not manifest is Dictionary:
		return {"available": false}
	var pairs: Array[Dictionary] = []
	var assets: Array[Dictionary] = []
	for index: int in range(IDS.size()):
		var id: String = String(IDS[index])
		var entry: Dictionary = (manifest["assets"] as Array)[index]
		var path: String = "res://assets/made/diner/%s.glb" % id
		assets.append({"id": id, "path": path, "hash": FileAccess.get_sha256(path),
			"expected_hash": entry.get("sha256", ""), "manifest_id": entry.get("asset", ""),
			"reference": "res://assets/kenney/furniture/%s.glb" % REFERENCES[index],
			"reference_hash": FileAccess.get_sha256("res://assets/kenney/furniture/%s.glb" % REFERENCES[index]),
			"expected_reference_hash": entry["references"][0]["sha256"],
			"triangles": entry["triangles"], "dimensions": entry["dimensions"]})
		if frame == 12:
			var pair: Node3D = stage.get_node_or_null(id) as Node3D
			var made: PropView = pair.get_node_or_null("Made") as PropView if pair != null else null
			var reference: PropView = pair.get_node_or_null("Kenney") as PropView if pair != null else null
			pairs.append({"id": id, "made": _prop(made, camera), "reference": _prop(reference, camera),
				"made_label": _label_evidence(pair.get_node_or_null("MadeLabel") as Label3D, camera) if pair != null else {},
				"reference_label": _label_evidence(pair.get_node_or_null("KenneyLabel") as Label3D, camera) if pair != null else {}})
	var actors: Array[Dictionary] = []
	var items: Array[Dictionary] = []
	if frame == 90:
		var sim: RestaurantSim = main.get("sim") as RestaurantSim
		for guest: CustomerAgent in sim.customers():
			var furnishing_id: int = world.grid.dining_furnishing_id(guest.seat_cell)
			var visual: ItemVisual = shop.item_nodes.get(furnishing_id) as ItemVisual
			var prop: PropView = visual.prop if visual != null else null
			var person: PersonView = shop.agent_nodes.get(guest.id) as PersonView
			var seated: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, world,
				prop.seat_surface_height() if prop != null else 0.0)
			var table: PlacedItem = world.grid.item(guest.table_item_id)
			var furnishing: PlacedItem = world.grid.item(furnishing_id)
			var expected: Dictionary = _expected_seated_position(guest, world)
			var expected_position: Vector3 = expected["position"]
			actors.append({"id": guest.id, "role": String(guest.role), "state": int(guest.state),
				"cell": _cell(guest.cell), "seat": _cell(guest.seat_cell), "arrived": guest.has_arrived(),
				"table": guest.table_item_id, "furnishing": furnishing_id,
				"furnishing_definition": String((furnishing.def as ItemDef).id) if furnishing != null else "",
				"linked_table": world.grid.dining_table_id(guest.seat_cell),
				"reservation": table.reserved_by(guest.seat_cell) if table != null else -1,
				"seat_member": table != null and table.seat_cells.has(guest.seat_cell),
				"walkable": world.grid.is_walkable(guest.seat_cell), "seated": seated.seated,
				"expected_model": String(PersonPresentation.model_for(guest.role, guest.id, guest.customer_type_id)),
				"model": String(person.model_name()) if person != null else "",
				"model_source": person._model.scene_file_path if person != null and person._model != null else "",
				"clip": String(person.current_clip()) if person != null else "",
				"player_clip": String(person._player.current_animation) if person != null and person._player != null else "",
				"seat_height": prop.seat_surface_height() if prop != null else 0.0,
				"seat_lift": (person.get_node("ModelPivot") as Node3D).position.y if person != null else -1.0,
				"expected_position": [expected_position.x, expected_position.y, expected_position.z],
				"forward_offset": expected["forward_offset"],
				"position_matches": expected["available"] and person != null and person.position.is_equal_approx(expected_position),
				"visible": person != null and person.is_visible_in_tree(),
				"seat_clearance": _seat_clearance(person, prop, camera, guest.id, furnishing_id, guest.table_item_id),
				"bounds": _screen_bounds(person.global_transform * PropView._children_aabb(person), camera) if person != null else {}})
		for row: Dictionary in PURCHASES:
			var item: PlacedItem = world.grid.item_at(row["cell"])
			var visual: ItemVisual = shop.item_nodes.get(item.id) as ItemVisual if item != null else null
			items.append({"id": item.id if item != null else 0, "definition": String((item.def as ItemDef).id) if item != null else "",
				"turns": item.quarter_turns if item != null else -1, "prop": _prop(visual.prop if visual != null else null, camera)})
	var walls: Array[Dictionary] = []
	if frame == 90:
		for index: int in range(2, IDS.size()):
			var prop: PropView = stage.get_node_or_null(String(IDS[index])) as PropView
			walls.append({"id": String(IDS[index]), "prop": _prop(prop, camera)})
	var mini: PersonView = stage.get_node_or_null("ScaleMini") as PersonView if frame == 12 else null
	var plan: DiningSeats.Plan = DiningSeats.derive(world.grid)
	return {"available": true, "scene": main.scene_file_path, "use_saves": main.get("use_saves"),
		"frame": frame, "snapshot": snapshot(main, context_root), "lights": _lights(main),
		"viewport": _cell(Vector2i(camera.get_viewport().get_visible_rect().size)),
		"assets": assets, "pairs": pairs, "actors": actors, "items": items, "walls": walls,
		"dining_links": plan.links.size(), "dining_failures": plan.failures,
		"notice": _notice_evidence(main),
		"scale_mini": {"model": String(mini.model_name()) if mini != null else "", "role": String(mini.role) if mini != null else "",
			"source": mini._model.scene_file_path if mini != null and mini._model != null else "",
			"scale": (mini.get_node("ModelPivot") as Node3D).scale.x if mini != null else 0.0,
			"visible": mini != null and mini.is_visible_in_tree(),
			"bounds": _screen_bounds(mini.global_transform * PropView._children_aabb(mini), camera) if mini != null else {}}}


static func valid(state: Dictionary, frame: int, fixture: Dictionary) -> bool:
	if frame not in [12, 90] or state.get("available") != true or not String(fixture.get("error", "missing")).is_empty() \
			or state.get("scene") != MAIN_SCENE or state.get("use_saves") != false or state.get("frame") != frame \
			or state.get("viewport") != [SIZE.x, SIZE.y] or state.get("lights") != fixture.get("lights") \
			or state.get("snapshot") != fixture.get("baseline" if frame == 12 else "furnished_baseline") \
			or not _notice_valid(state.get("notice", {})):
		return false
	var notice_rect: Rect2 = _rect(state["notice"]["panel_bounds"])
	var assets: Array = state.get("assets", [])
	if assets.size() != IDS.size():
		return false
	for index: int in range(IDS.size()):
		var asset: Dictionary = assets[index]
		if asset.get("id") != String(IDS[index]) or asset.get("manifest_id") != String(IDS[index]) \
				or String(asset.get("hash", "")).length() != 64 or asset["hash"] != asset.get("expected_hash") \
				or asset.get("reference") != "res://assets/kenney/furniture/%s.glb" % REFERENCES[index] \
				or asset.get("reference_hash") != asset.get("expected_reference_hash"):
			return false
	if frame == 12:
		var pairs: Array = state.get("pairs", [])
		var mini: Dictionary = state.get("scale_mini", {})
		if pairs.size() != IDS.size() or mini.get("visible") != true or mini.get("role") != "owner" \
				or mini.get("model") != String(PersonPresentation.OWNER_MODEL) \
				or mini.get("scale") != (Vector3.ONE * ArtScale.CHARACTER_SCALE).x \
				or mini.get("source") != PersonPresentation.model_path_for(&"owner") or not _bounds_valid(mini.get("bounds", {})):
			return false
		if notice_rect.intersects(_rect(mini["bounds"])):
			return false
		var pair_rects: Array[Rect2] = []
		for index: int in range(pairs.size()):
			var pair: Dictionary = pairs[index]
			var asset: Dictionary = assets[index]
			if pair.get("id") != String(IDS[index]) or not _prop_valid(pair.get("made", {}), asset["path"]) \
					or not _prop_valid(pair.get("reference", {}), asset["reference"]) \
					or pair["made"]["models"][0]["triangles"] != asset["triangles"] \
					or not _dimensions_match(pair["made"]["models"][0]["dimensions"], asset["dimensions"]) \
					or not _label_valid(pair.get("made_label", {}), "MADE\n" + NAMES[index]) \
					or not _label_valid(pair.get("reference_label", {}), "KENNEY\n" + REFERENCES[index]):
				return false
			var left: Rect2 = _rect(pair["made"]["bounds"])
			var right: Rect2 = _rect(pair["reference"]["bounds"])
			if left.intersects(right):
				return false
			var union: Rect2 = left.merge(right).merge(_rect(pair["made_label"]["bounds"])).merge(_rect(pair["reference_label"]["bounds"]))
			if notice_rect.intersects(union):
				return false
			for previous: Rect2 in pair_rects:
				if previous.intersects(union):
					return false
			pair_rects.append(union)
		return true
	var actors: Array = state.get("actors", [])
	var items: Array = state.get("items", [])
	var walls: Array = state.get("walls", [])
	if actors.size() != 6 or items.size() != PURCHASES.size() or walls.size() != 4 \
			or state.get("dining_links") != 6 or not (state.get("dining_failures", {}) as Dictionary).is_empty():
		return false
	var seats: Dictionary = {}
	var booths: int = 0
	var stools: int = 0
	for actor: Dictionary in actors:
		var key: String = str(actor.get("seat"))
		var measurement: Dictionary = actor.get("seat_clearance", {})
		if actor.get("role") != "customer" or actor.get("state") != int(CustomerAgent.State.ORDERING) \
				or actor.get("cell") != actor.get("seat") or actor.get("arrived") != true \
				or actor.get("seat_member") != true or actor.get("walkable") != true or actor.get("seated") != true \
				or actor.get("reservation") != actor.get("id") or actor.get("linked_table") != actor.get("table") \
				or int(actor.get("furnishing", 0)) <= 0 or actor.get("visible") != true or seats.has(key) \
				or actor.get("model") != actor.get("expected_model") or String(actor.get("model", "")).is_empty() \
				or actor.get("model_source") != PersonPresentation.MODEL_DIRECTORY + String(actor["model"]) + ".glb" \
				or actor.get("clip") != "sit" or actor.get("player_clip") != "sit" or actor.get("position_matches") != true \
				or float(actor.get("seat_height", 0.0)) <= 0.0 \
				or not is_equal_approx(float(actor.get("seat_lift", -1.0)), float(actor.get("seat_height", -2.0))) \
				or not _bounds_valid(actor.get("bounds", {})):
			return false
		if measurement.get("guest_id") != actor.get("id") or measurement.get("furnishing_id") != actor.get("furnishing") \
				or measurement.get("table_item_id") != actor.get("table") or not _seated_measurement_valid(measurement) \
				or not _crop_head_rect_valid(measurement.get("head_screen_bounds", {})):
			return false
		if notice_rect.intersects(_rect(actor["bounds"])):
			return false
		seats[key] = true
		if actor.get("furnishing_definition") == "diner_booth":
			booths += 1
		elif actor.get("furnishing_definition") == "diner_stool":
			stools += 1
		else:
			return false
	for index: int in range(items.size()):
		var item: Dictionary = items[index]
		if item.get("definition") != String(PURCHASES[index]["id"]) or item.get("turns") != PURCHASES[index]["turns"] \
				or item.get("id") != fixture["purchased_ids"][index] or item.get("prop", {}).get("visible") != true \
				or item["prop"].get("wrapper") != "res://assets/props/%s.tscn" % PURCHASES[index]["id"] \
				or not _bounds_valid(item["prop"].get("bounds", {})):
			return false
		if notice_rect.intersects(_rect(item["prop"]["bounds"])):
			return false
		if PURCHASES[index]["id"] in [&"diner_booth", &"diner_stool"]:
			var asset_index: int = 0 if PURCHASES[index]["id"] == &"diner_booth" else 1
			if not _prop_valid(item["prop"], assets[asset_index]["path"]) \
					or item["prop"]["models"][0]["triangles"] != assets[asset_index]["triangles"]:
				return false
	for index: int in range(walls.size()):
		if walls[index].get("id") != String(IDS[index + 2]) \
				or not _prop_valid(walls[index].get("prop", {}), assets[index + 2]["path"]):
			return false
		if notice_rect.intersects(_rect(walls[index]["prop"]["bounds"])):
			return false
	return booths == 4 and stools == 2


## Independent expectation from arrived sim cells and authored content. Never
## reads PersonView.position or the production frame's final display offset.
static func _expected_seated_position(guest: CustomerAgent, world: SimWorld) -> Dictionary:
	var unavailable: Dictionary = {"available": false, "position": Vector3.ZERO, "forward_offset": 0.0}
	if guest == null or world == null or not guest.has_arrived() or guest.cell != guest.seat_cell:
		return unavailable
	var table: PlacedItem = world.grid.item(guest.table_item_id)
	var furnishing: PlacedItem = world.grid.item(world.grid.dining_furnishing_id(guest.seat_cell))
	if table == null:
		return unavailable
	var source: PlacedItem = furnishing if furnishing != null else table
	var definition: ItemDef = source.def as ItemDef
	if definition == null:
		return unavailable
	var offset: float = float(definition.get("seated_forward_offset")) if "seated_forward_offset" in definition else 0.0
	if not is_finite(offset):
		return unavailable
	var origin: Vector3 = GridMath.cell_to_world(guest.seat_cell)
	var forward: Vector3 = Vector3.ZERO
	if definition.category == ItemDef.Category.CHAIR:
		var local_origin: Vector2i = GridMath.rotate_cell(Vector2i.ZERO, definition.footprint, source.quarter_turns)
		var local_front: Vector2i = GridMath.rotate_cell(Vector2i.UP, definition.footprint, source.quarter_turns)
		var direction: Vector2i = local_front - local_origin
		forward = Vector3(direction.x, 0.0, direction.y).normalized()
	else:
		var center: Vector3 = Vector3.ZERO
		for cell: Vector2i in table.cells:
			center += GridMath.cell_to_world(cell)
		center = center / float(table.cells.size()) if not table.cells.is_empty() else GridMath.cell_to_world(table.origin)
		forward = (center - origin).normalized()
	return {"available": true, "position": origin + forward * offset, "forward_offset": offset}


static func _reference(id: String) -> PropView:
	var packed: PackedScene = load("res://assets/kenney/furniture/%s.glb" % id) as PackedScene
	if packed == null:
		return null
	var prop: PropView = PropView.new()
	var part: Node3D = Node3D.new()
	var art: Node3D = Node3D.new()
	art.name = "Art"
	art.rotation.y = PI
	part.add_child(art)
	art.add_child(packed.instantiate())
	prop.add_child(part)
	prop.prepare()
	return prop


static func _label(parent: Node3D, name: String, text: String, position: Vector3) -> void:
	var label: Label3D = Label3D.new()
	label.name = name
	label.text = text
	label.font = THEME.default_font if THEME.default_font != null else ThemeDB.fallback_font
	label.font_size = 32
	label.pixel_size = 0.003
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.position = position
	parent.add_child(label)


static func _notice(main: Node, text: String) -> void:
	var layer: CanvasLayer = main.get_node_or_null("DinerReviewNotice") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "DinerReviewNotice"
		layer.layer = 20
		main.add_child(layer)
		var panel: PanelContainer = PanelContainer.new()
		panel.name = "Panel"
		panel.theme = THEME
		panel.position = Vector2(24, 796)
		panel.custom_minimum_size = Vector2(1152, 88)
		panel.size = panel.custom_minimum_size
		layer.add_child(panel)
		var label: Label = Label.new()
		label.name = "Text"
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(label)
	(layer.get_node("Panel/Text") as Label).text = text


## Query native panel/style/text layout, including the actual themed colours.
## No preference, layout, material or simulation mutation occurs during evidence.
static func _notice_evidence(main: Node) -> Dictionary:
	var panel: PanelContainer = main.get_node_or_null("DinerReviewNotice/Panel") as PanelContainer
	var label: Label = main.get_node_or_null("DinerReviewNotice/Panel/Text") as Label
	if panel == null or label == null:
		return {}
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return {}
	var background: Color = style.bg_color * panel.modulate * panel.self_modulate
	var foreground: Color = label.get_theme_color("font_color") * panel.modulate * label.modulate * label.self_modulate
	var light: float = maxf(_luminance(background), _luminance(foreground))
	var dark: float = minf(_luminance(background), _luminance(foreground))
	var content: Rect2 = Rect2(Vector2(style.get_margin(SIDE_LEFT), style.get_margin(SIDE_TOP)),
		panel.size - Vector2(style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT),
		style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)))
	var transform: Transform2D = panel.get_viewport().get_final_transform() * panel.get_global_transform_with_canvas()
	content = transform * content
	var minimum: Vector2 = label.get_minimum_size()
	return {"text": label.text, "visible": label.is_visible_in_tree(),
		"panel_bounds": _control_bounds(panel), "text_bounds": _control_bounds(label),
		"content_bounds": [content.position.x, content.position.y, content.size.x, content.size.y],
		"shared_panel_style": style == THEME.get_stylebox("panel", "PanelContainer"),
		"background_drawn": panel.is_visible_in_tree() and style.draw_center,
		"background_alpha": background.a, "text_alpha": foreground.a,
		"contrast": (light + 0.05) / (dark + 0.05),
		"line_count": label.get_line_count(), "visible_lines": label.get_visible_line_count(),
		"text_fits": label.size.x >= minimum.x and label.size.y >= minimum.y}


static func _control_bounds(control: Control) -> Dictionary:
	var viewport: Viewport = control.get_viewport()
	var bounds: Rect2 = viewport.get_final_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
	return {"rect": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"inside": viewport.get_visible_rect().grow(-8.0).encloses(bounds)}


static func _luminance(color: Color) -> float:
	var linear: Color = color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


static func _notice_valid(notice: Dictionary) -> bool:
	if notice.get("visible") != true or not String(notice.get("text", "")).contains(NOTICE) \
			or notice.get("shared_panel_style") != true or notice.get("background_drawn") != true \
			or float(notice.get("background_alpha", 0.0)) < 0.99 or float(notice.get("text_alpha", 0.0)) < 0.99 \
			or float(notice.get("contrast", 0.0)) < 4.5 or notice.get("text_fits") != true \
			or int(notice.get("line_count", 0)) < 2 or notice.get("visible_lines") != notice.get("line_count") \
			or notice.get("panel_bounds", {}).get("inside") != true or notice.get("text_bounds", {}).get("inside") != true:
		return false
	var panel: Rect2 = _rect(notice["panel_bounds"])
	var text: Rect2 = _rect(notice["text_bounds"])
	var values: Array = notice.get("content_bounds", [])
	if values.size() != 4:
		return false
	var content: Rect2 = Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return panel.has_area() and text.has_area() and panel.encloses(content) and content.grow(1.0).encloses(text)


static func _comparison_visibility(shop: ShopView, visible: bool) -> void:
	for visual: ItemVisual in shop.item_nodes.values():
		visual.visible = visible
	for person: Node3D in shop.agent_nodes.values():
		person.visible = visible
	shop._walls.visible = visible
	if shop.room_dressing != null:
		shop.room_dressing.visible = visible


static func _camera(rig: CameraRig, focus: Vector2, yaw: float, zoom: float) -> void:
	rig.set_process(false)
	rig.minimum_zoom = 2.0
	rig.initial_focus = focus
	rig.initial_yaw_degrees = yaw
	rig.initial_zoom = zoom
	rig.reset_view()


static func _prop(prop: PropView, camera: Camera3D) -> Dictionary:
	if prop == null:
		return {}
	var models: Array[Dictionary] = []
	_models(prop, models)
	return {"wrapper": prop.scene_file_path, "visible": prop.is_visible_in_tree(), "models": models,
		"bounds": _screen_bounds(prop.global_transform * prop.get_combined_aabb(), camera),
		"seat_surface_height": prop.seat_surface_height()}


static func _models(node: Node, result: Array[Dictionary]) -> void:
	if node.scene_file_path.ends_with(".glb"):
		var dimensions: Vector3 = PropView._children_aabb(node).size
		result.append({"path": node.scene_file_path, "triangles": _triangles(node),
			"dimensions": [dimensions.x, dimensions.y, dimensions.z]})
		return
	for child: Node in node.get_children():
		_models(child, result)


static func _triangles(node: Node) -> int:
	var count: int = 0
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	for child: Node in node.get_children():
		count += _triangles(child)
	return count


## Read the current native sit pose without moving or fitting the actor. The
## screen rectangle is derived from actual posed head vertices, not rest bounds.
static func _seat_clearance(person: PersonView, prop: PropView, camera: Camera3D,
		guest_id: int, furnishing_id: int, table_id: int) -> Dictionary:
	if person == null or prop == null or camera == null:
		return {"error": "native seated person, furnishing or camera is unavailable"}
	var measured: Dictionary = HEAD_GEOMETRY.measure(person, prop)
	if not String(measured.get("error", "missing native measurement")).is_empty():
		return {"error": measured.get("error", "missing native measurement")}
	var bounds: AABB = measured["world_bounds"]
	var screen: Dictionary = _screen_bounds(bounds, camera)
	if screen.get("inside") != true or screen.get("in_front") != true:
		return {"error": "actual posed head is outside the capture viewport"}
	var rect: Array = screen["rect"]
	var clearance: float = measured["clearance"]
	if not is_finite(clearance):
		return {"error": "native seat clearance is not a valid distance"}
	return {"error": "", "guest_id": guest_id, "furnishing_id": furnishing_id,
		"table_item_id": table_id, "head_world_bounds": {
			"min": [bounds.position.x, bounds.position.y, bounds.position.z],
			"max": [bounds.end.x, bounds.end.y, bounds.end.z]},
		"head_screen_bounds": {"x": rect[0], "y": rect[1], "width": rect[2], "height": rect[3]},
		"seated_head_clearance": clearance, "seat_geometry_measured": true,
		"intersecting_triangles": measured["intersecting_triangles"],
		"head_center_inside_seat": measured["head_center_inside_seat"],
		"head_vertices": measured["head_vertices"], "measurement_provenance": measured["provenance"],
		"clearance_metric": measured["clearance_metric"],
		"model": String(person.model_name()), "clip": String(person._player.current_animation),
		"sit_time": person._player.current_animation_position,
		"character_scale": (person.get_node("ModelPivot") as Node3D).scale.x}


static func _screen_bounds(bounds: AABB, camera: Camera3D) -> Dictionary:
	var rect: Rect2 = Rect2()
	var in_front: bool = true
	for index: int in range(8):
		var point: Vector3 = bounds.get_endpoint(index)
		var screen: Vector2 = camera.unproject_position(point)
		if index == 0:
			rect = Rect2(screen, Vector2.ZERO)
		else:
			rect = rect.expand(screen)
		in_front = in_front and not camera.is_position_behind(point)
	return {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "in_front": in_front,
		"inside": camera.get_viewport().get_visible_rect().grow(-8).encloses(rect)}


static func _label_evidence(label: Label3D, camera: Camera3D) -> Dictionary:
	if label == null:
		return {}
	return {"text": label.text, "visible": label.is_visible_in_tree(),
		"billboard": int(label.billboard), "faces_camera": label.global_basis.is_equal_approx(camera.global_basis),
		"bounds": _screen_bounds(label.global_transform * label.get_aabb(), camera)}


static func _lights(main: Node) -> Array[String]:
	var result: Array[String] = []
	for light: Node in main.find_children("*", "Light3D", true, false):
		result.append(String(main.get_path_to(light)))
	result.sort()
	return result


static func _prop_valid(prop: Dictionary, path: String) -> bool:
	var models: Array = prop.get("models", [])
	return prop.get("visible") == true and models.size() == 1 and models[0].get("path") == path \
		and int(models[0].get("triangles", 0)) > 0 and _bounds_valid(prop.get("bounds", {}))


static func _dimensions_match(actual: Array, expected: Array) -> bool:
	if actual.size() != 3 or expected.size() != 3:
		return false
	for index: int in range(3):
		if absf(float(actual[index]) - float(expected[index])) > 0.0001:
			return false
	return true


static func _label_valid(label: Dictionary, text: String) -> bool:
	return label.get("text") == text and label.get("visible") == true \
		and label.get("billboard") == int(BaseMaterial3D.BILLBOARD_DISABLED) and label.get("faces_camera") == true \
		and _bounds_valid(label.get("bounds", {}))


static func _bounds_valid(bounds: Dictionary) -> bool:
	var values: Array = bounds.get("rect", [])
	return values.size() == 4 and bounds.get("inside") == true and bounds.get("in_front") == true \
		and float(values[2]) >= 4.0 and float(values[3]) >= 4.0


static func _rect(bounds: Dictionary) -> Rect2:
	var values: Array = bounds["rect"]
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


static func _cell(value: Vector2i) -> Array[int]:
	return [value.x, value.y]


## Derivative evidence only: source pixels from the already captured frame 90.
## The caller supplies trusted output paths after saving the full PNG and building
## its complete metadata. Metadata never supplies an output path or filename.
static func write_seated_crop(full_image: Image, source_path: String, metadata: Dictionary, output_dir: String) -> Dictionary:
	var failure: Dictionary = {"error": "seated crop requires the validated paused frame 90 image"}
	var review: Dictionary = metadata.get("diner_review", {})
	var state: Dictionary = review.get("state", {})
	var fixture: Dictionary = review.get("fixture", {})
	if full_image == null or full_image.is_empty() or full_image.get_size() != SIZE \
			or metadata.get("frame") != 90 or metadata.get("image_file") != "shot_0090.png" \
			or metadata.get("width") != SIZE.x or metadata.get("height") != SIZE.y \
			or metadata.get("scene") != MAIN_SCENE or metadata.get("capture_timing") != "frame_post_draw" \
			or metadata.get("engine_errors") != 0 or not valid(state, 90, fixture):
		return failure
	var directory: String = _crop_path(output_dir)
	var source: String = _crop_path(source_path)
	var screens: String = _crop_path("res://screens")
	var compared_directory: String = directory.to_lower() if OS.has_feature("windows") else directory
	var compared_screens: String = screens.to_lower() if OS.has_feature("windows") else screens
	var compared_parent: String = source.get_base_dir().to_lower() if OS.has_feature("windows") else source.get_base_dir()
	if not compared_directory.begins_with(compared_screens + "/") and compared_directory != compared_screens:
		return {"error": "seated crop output must stay inside this project's ignored screens directory"}
	if compared_parent != compared_directory or source.get_file() != "shot_0090.png" or not FileAccess.file_exists(source):
		return {"error": "seated crop source must be the saved frame 90 PNG in the explicit output directory"}
	var source_hash: String = FileAccess.get_sha256(source)
	if source_hash.length() != 64 or source_hash != metadata.get("image_sha256"):
		return {"error": "seated crop source PNG does not match the full-frame metadata hash"}
	var saved_image: Image = Image.load_from_file(source)
	if saved_image == null or saved_image.is_empty() or saved_image.get_size() != SIZE:
		return {"error": "seated crop cannot read the saved source PNG"}
	# Compare decoded pixels in one lossless byte format before deriving anything.
	var supplied: Image = full_image.duplicate() as Image
	supplied.convert(Image.FORMAT_RGBA8)
	saved_image.convert(Image.FORMAT_RGBA8)
	if supplied.get_data() != saved_image.get_data():
		return {"error": "seated crop image differs from the saved full-frame pixels"}
	var selection: Dictionary = seated_crop_selection(state)
	if not String(selection.get("error", "missing")).is_empty():
		return selection
	var values: Array = selection["source_rect"]
	var region: Rect2i = Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))
	var cropped: Image = seated_crop_image(saved_image, region)
	if cropped == null:
		return {"error": "seated crop rectangle did not fit its source image"}
	var output: String = directory.path_join(CROP_FILE)
	if cropped.save_png(output) != OK:
		return {"error": "cannot save the exact three-times seated crop"}
	var crop_hash: String = FileAccess.get_sha256(output)
	if crop_hash.length() != 64:
		return {"error": "cannot hash the saved seated crop"}
	var result: Dictionary = selection.duplicate(true)
	result.merge({"kind": "source_pixel_derivative", "source_image_file": source.get_file(),
		"source_image_sha256": source_hash, "source_frame": 90, "scale": CROP_SCALE,
		"interpolation": "nearest", "image_file": CROP_FILE, "image_sha256": crop_hash,
		"width": cropped.get_width(), "height": cropped.get_height(),
		"notice": "Exact 3x nearest-neighbour crop of paused, unsaved frame 90; no new scene or rendered frame.",
		"fixture_notice": NOTICE})
	var file: FileAccess = FileAccess.open(output.get_basename() + ".json", FileAccess.WRITE)
	if file == null:
		return {"error": "cannot write seated crop provenance"}
	file.store_string(JSON.stringify(result, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return {"error": "cannot save seated crop provenance"}
	return result


## Pure selection from current native measurements. Actor bind-pose bounds are
## deliberately unused: the head comes from SeatedHeadGeometry's posed vertices.
static func seated_crop_selection(state: Dictionary) -> Dictionary:
	var failure: Dictionary = {"error": "seated crop needs a visible booth guest with current posed head clearance"}
	var candidates: Array = state.get("actors", [])
	var items: Array = state.get("items", [])
	var chosen: Dictionary = {}
	var chosen_bounds: Rect2 = Rect2()
	var nearest: float = -INF
	for actor: Dictionary in candidates:
		if actor.get("furnishing_definition") != "diner_booth":
			continue
		var measurement: Dictionary = actor.get("seat_clearance", {})
		var head_data: Dictionary = measurement.get("head_screen_bounds", {})
		if actor.get("role") != "customer" or actor.get("seated") != true or actor.get("visible") != true \
				or actor.get("clip") != "sit" or actor.get("player_clip") != "sit" \
				or actor.get("reservation") != actor.get("id") or actor.get("linked_table") != actor.get("table") \
				or measurement.get("guest_id") != actor.get("id") \
				or measurement.get("furnishing_id") != actor.get("furnishing") \
				or measurement.get("table_item_id") != actor.get("table") \
				or not _seated_measurement_valid(measurement) or not _crop_head_rect_valid(head_data):
			return failure
		var head: Rect2 = Rect2(float(head_data["x"]), float(head_data["y"]), float(head_data["width"]), float(head_data["height"]))
		var furnishing: Dictionary = _crop_item(items, int(actor["furnishing"]))
		var table: Dictionary = _crop_item(items, int(actor["table"]))
		if furnishing.get("definition") != "diner_booth" or not _bounds_valid(furnishing.get("prop", {}).get("bounds", {})) \
				or not _bounds_valid(table.get("prop", {}).get("bounds", {})):
			return failure
		var bounds: Rect2 = head.merge(_rect(furnishing["prop"]["bounds"])).merge(_rect(table["prop"]["bounds"]))
		# Prefer the nearest head in the existing three-quarter view; stable ID
		# breaks ties without randomness or a camera/actor presentation change.
		if head.end.y > nearest or (head.end.y == nearest and int(actor["id"]) < int(chosen.get("id", 2147483647))):
			nearest = head.end.y
			chosen = actor
			chosen_bounds = bounds
	if chosen.is_empty():
		return failure
	var viewport: Rect2 = Rect2(Vector2.ZERO, Vector2(SIZE))
	if not viewport.encloses(chosen_bounds):
		return {"error": "seated crop context lies outside the source image"}
	var padded: Rect2 = chosen_bounds.grow(CROP_PADDING).intersection(viewport)
	var origin: Vector2i = Vector2i(floori(padded.position.x), floori(padded.position.y))
	var end: Vector2i = Vector2i(ceili(padded.end.x), ceili(padded.end.y))
	return {"error": "", "guest_id": int(chosen["id"]), "furnishing_id": int(chosen["furnishing"]),
		"table_item_id": int(chosen["table"]), "source_rect": [origin.x, origin.y, end.x - origin.x, end.y - origin.y],
		"measurement": (chosen["seat_clearance"] as Dictionary).duplicate(true)}


## Exact source-region sampling only. Tests exercise this with tiny pixel grids;
## those grids are unit-test fixtures and never acceptance screenshots.
static func seated_crop_image(source: Image, region: Rect2i) -> Image:
	if source == null or source.is_empty() or region.size.x <= 0 or region.size.y <= 0 \
			or not Rect2i(Vector2i.ZERO, source.get_size()).encloses(region):
		return null
	var result: Image = source.get_region(region)
	result.resize(region.size.x * CROP_SCALE, region.size.y * CROP_SCALE, Image.INTERPOLATE_NEAREST)
	return result


static func _seated_measurement_valid(measurement: Dictionary) -> bool:
	var clearance: Variant = measurement.get("seated_head_clearance")
	var world: Dictionary = measurement.get("head_world_bounds", {})
	var low: Array = world.get("min", [])
	var high: Array = world.get("max", [])
	if not String(measurement.get("error", "")).is_empty() \
			or not _crop_integer(measurement.get("intersecting_triangles")) or measurement.get("intersecting_triangles") != 0 \
			or measurement.get("head_center_inside_seat") != false or not _crop_integer(measurement.get("head_vertices")) \
			or int(measurement.get("head_vertices", 0)) <= 0 or measurement.get("measurement_provenance") != POSED_HEAD_PROVENANCE \
			or measurement.get("clearance_metric") != POSED_CLEARANCE_METRIC \
			or low.size() != 3 or high.size() != 3:
		return false
	for axis: int in range(3):
		if not (low[axis] is float or low[axis] is int) or not (high[axis] is float or high[axis] is int) \
				or not is_finite(float(low[axis])) or not is_finite(float(high[axis])) or float(high[axis]) <= float(low[axis]):
			return false
	return measurement.get("seat_geometry_measured") == true \
		and (clearance is float or clearance is int) and is_finite(float(clearance)) and float(clearance) >= 0.02


static func _crop_head_rect_valid(data: Dictionary) -> bool:
	for key: String in ["x", "y", "width", "height"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	var bounds: Rect2 = Rect2(float(data["x"]), float(data["y"]), float(data["width"]), float(data["height"]))
	return bounds.has_area() and Rect2(Vector2.ZERO, Vector2(SIZE)).encloses(bounds)


static func _crop_item(items: Array, id: int) -> Dictionary:
	for item: Dictionary in items:
		if item.get("id") == id:
			return item
	return {}


static func _crop_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))


static func _crop_path(path: String) -> String:
	var normalized: String = path.replace("\\", "/")
	if not normalized.is_absolute_path():
		normalized = "res://".path_join(normalized)
	return ProjectSettings.globalize_path(normalized).replace("\\", "/").simplify_path().trim_suffix("/")
