extends SceneTree
## Manual FK-082 native before/after evidence. No production state is saved.
## godot --rendering-method gl_compatibility --path . --script tools/chair_pose_review.gd -- --out=/fresh/directory
const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const GEOMETRY: Script = preload("res://tools/seated_head_geometry.gd")
var _out: String = ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	if _out.is_empty() or DisplayServer.get_name() == "headless" or DirAccess.dir_exists_absolute(_out):
		print("Use a rendered Compatibility session and a fresh --out directory")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		quit(2)
		return
	await process_frame
	root.size = Vector2i(1200, 850)
	var content: ContentDB = ContentDB.new()
	if not content.load_all().is_empty():
		quit(1)
		return
	var results: Array[Dictionary] = []
	for corrected: bool in [false, true]:
		results.append(await _capture(content.item(&"chair"), corrected))
	var file: FileAccess = FileAccess.open(_out.path_join("chair-pose.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t") + "\n")
	file.close()
	var valid: bool = not results[0]["passes"] and results[1]["passes"]
	for result: Dictionary in results:
		valid = valid and String(result["error"]).is_empty() and float(result["native_bake_max_error"]) <= 0.00001
	valid = valid and results[1]["hips_supported_at_offset"]
	print("CHAIR NATIVE BEFORE/AFTER: ", "PASS" if valid else "FAIL")
	quit(0 if valid else 1)

func _capture(authored: ItemDef, corrected: bool) -> Dictionary:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(12, 12)))
	var restaurant: RestaurantSim = RestaurantSim.new()
	restaurant.world = world
	var definition: ItemDef = authored.duplicate(true) as ItemDef
	if not corrected:
		definition.seated_forward_offset = 0.0
		definition.seated_lean_degrees = 0.0
	var chair: PlacedItem = world.grid.place_def(definition, Vector2i(4, 4))
	var table_def: ItemDef = ItemDef.new()
	table_def.category = ItemDef.Category.TABLE
	var table: PlacedItem = world.grid.place_def(table_def, Vector2i(4, 3))
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 147
	var guest: CustomerAgent = world.add_agent(CustomerAgent.new(restaurant, random)) as CustomerAgent
	guest.state = CustomerAgent.State.WAITING_FOOD
	guest.table_item_id = table.id
	guest.cell = Vector2i(4, 4)
	guest.seat_cell = guest.cell
	table.reserve(guest.cell, guest.id)
	var staff: StaffAgent = world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	staff.cell = Vector2i(7, 4)
	var view: ShopView = VIEW.instantiate() as ShopView
	root.add_child(view)
	view.set_process(false)
	view.show_world(world)
	# The reservation-only placeholder is not part of the chair geometry. Hide
	# that unauthored box in the close crop; keep the real table in simulation.
	view.item_nodes[table.id].visible = false
	view.agent_nodes[staff.id].visible = false
	var person: PersonView = view.agent_nodes[guest.id]
	person.set_look(&"customer", PersonPresentation.GUEST_MODELS.find(&"character-female-e"))
	person._player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	person._player.seek(0.0, true)
	if view.mood_nodes.has(guest.id):
		view.mood_nodes[guest.id].visible = false
	var prop: Node3D = (view.item_nodes[chair.id] as ItemVisual).prop
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.75, 0.77, 0.78)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	view.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	view.add_child(light)
	var camera: Camera3D = Camera3D.new()
	view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.1
	camera.global_position = person.global_position + Vector3(2.0, 0.65, 0.6)
	camera.look_at(person.global_position + Vector3(0, 0.45, 0))
	camera.make_current()
	for frame: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var result: Dictionary = GEOMETRY.measure(person, prop, true)
	var prefix: String = "after" if corrected else "before"
	root.get_texture().get_image().save_png(_out.path_join(prefix + ".png"))
	if corrected:
		# Compare actual native hip support before/after the authored translation,
		# with the same upper-body articulation. The legs are not rotated by it.
		var saved_position: Vector3 = person.position
		person.position -= -person.basis.z * definition.seated_forward_offset
		var support: Dictionary = GEOMETRY.supported_offset_trial(person, prop,
			GEOMETRY.seat_parts(prop, person), 0.0)
		person.position = saved_position
		result["hips_supported_at_offset"] = support["trial_supported"]
		result["hip_support_points"] = support["trial_support_points"]
		view.agent_nodes[staff.id].visible = true
		camera.size = 2.0
		camera.global_position = person.global_position + Vector3(2.5, 1.1, 2.5)
		camera.look_at(person.global_position + Vector3(0.65, 0.45, 0))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("after-standing-reference.png"))
	for key: String in ["person_bounds", "world_bounds", "head_bounds"]:
		result.erase(key)
	result["corrected"] = corrected
	result["seated_lean_degrees"] = person.current_seated_lean_degrees()
	result["seated_forward_offset"] = definition.seated_forward_offset
	result["model"] = String(person.model_name())
	result["sit_fraction"] = 0.0
	view.free()
	return result