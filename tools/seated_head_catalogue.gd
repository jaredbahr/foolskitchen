class_name SeatedHeadCatalogue
extends RefCounted
## Read-only native ShopView fixture. Production code chooses seat position,
## height and facing; this harness never compensates for clipping itself.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const GEOMETRY: GDScript = preload("res://tools/seated_head_geometry.gd")


static func run(parent: Node, native_bake: bool = false) -> Dictionary:
	var report: Dictionary = {"errors": PackedStringArray(), "samples": [], "seats": 0,
		"required_clearance": GEOMETRY.REQUIRED_CLEARANCE, "native_bake": native_bake,
		"native_bake_upload_waits": 0, "native_bake_poses": {}}
	var errors: PackedStringArray = report["errors"]
	var poses: Dictionary[String, PackedVector3Array] = {}
	var parity: Dictionary[String, Dictionary] = {}
	var content: ContentDB = ContentDB.new()
	errors.append_array(content.load_all())
	if not errors.is_empty():
		report["errors"] = errors
		return report
	for definition: ItemDef in content.items():
		if definition.seat_cells.is_empty() or not definition.catalogue_visible:
			continue
		report["seats"] += 1
		for turns: int in range(4):
			await _sample_item(parent, definition, turns, native_bake, poses, parity, report)
	report["native_bake_poses"] = parity
	return report


static func _sample_item(parent: Node, definition: ItemDef, turns: int, native_bake: bool,
		poses: Dictionary[String, PackedVector3Array], parity: Dictionary[String, Dictionary], report: Dictionary) -> void:
	var errors: PackedStringArray = report["errors"]
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(12, 12)))
	var restaurant: RestaurantSim = RestaurantSim.new()
	restaurant.world = world
	var origin: Vector2i = Vector2i(4, 4)
	var table_def: ItemDef = ItemDef.new()
	table_def.category = ItemDef.Category.TABLE
	table_def.footprint = Vector2i.ONE
	var tables: Array[PlacedItem] = []
	if definition.category != ItemDef.Category.TABLE:
		for authored: Vector2i in definition.seat_cells:
			var front: Vector2i = origin + GridMath.rotate_cell(authored + Vector2i.UP, definition.footprint, turns)
			var table: PlacedItem = world.grid.place_def(table_def, front)
			if table == null:
				errors.append("%s rotation %d: cannot place facing table" % [definition.id, turns])
				report["errors"] = errors
				return
			tables.append(table)
	var placed: PlacedItem = world.grid.place_def(definition, origin, turns)
	if placed == null or definition.seat_cells.is_empty():
		errors.append("%s rotation %d: cannot place catalogue seat" % [definition.id, turns])
		report["errors"] = errors
		return
	if definition.category == ItemDef.Category.TABLE:
		for authored: Vector2i in definition.seat_cells:
			tables.append(placed)
	var guests: Array[CustomerAgent] = []
	for index: int in range(definition.seat_cells.size()):
		var cell: Vector2i = origin + GridMath.rotate_cell(definition.seat_cells[index], definition.footprint, turns)
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 147 + index
		var guest: CustomerAgent = world.add_agent(CustomerAgent.new(restaurant, random)) as CustomerAgent
		guest.state = CustomerAgent.State.WAITING_FOOD
		guest.table_item_id = tables[index].id
		guest.cell = cell
		guest.seat_cell = cell
		if not tables[index].reserve(cell, guest.id):
			errors.append("%s rotation %d: table did not project/reserve the native seat" % [definition.id, turns])
		guests.append(guest)
	var view: ShopView = VIEW.instantiate() as ShopView
	parent.add_child(view)
	view.set_process(false)
	view.show_world(world)
	var visual: ItemVisual = view.item_nodes.get(placed.id) as ItemVisual
	if visual == null or visual.prop == null:
		errors.append("%s: missing native seat wrapper" % definition.id)
	else:
		var faces: Dictionary[int, PackedVector3Array] = {}
		for look: int in range(PersonPresentation.GUEST_MODELS.size()):
			for guest: CustomerAgent in guests:
				var person: PersonView = view.agent_nodes.get(guest.id) as PersonView
				if person == null or not person.set_look(&"customer", look) or person.current_clip() != &"sit":
					errors.append("%s: native seated PersonView is unavailable" % definition.id)
					continue
				# Stop automatic advancement, then seek the actual imported sit clip.
				person._player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				var animation: Animation = person._player.get_animation(&"sit")
				for fraction: float in [0.0, 0.37, 0.91]:
					person._player.seek(animation.length * fraction, true)
					# Bone pose queries calculate dirty transforms synchronously.
					person._skeleton.force_update_all_bone_transforms()
					var pose_key: String = "%s:%.9f" % [person.model_name(), animation.length * fraction]
					if not poses.has(pose_key):
						var posed: Dictionary = GEOMETRY.skin_vertices(GEOMETRY.head_mesh(person), person._skeleton)
						if not String(posed["error"]).is_empty():
							errors.append(String(posed["error"]))
							continue
						poses[pose_key] = posed["vertices"]
					var reused_parity: bool = parity.has(pose_key)
					if native_bake and not reused_parity:
						# Native bake is mesh-local: only this model/time's first
						# encounter needs a renderer upload and vertex comparison.
						# All placements still use their real node transforms below.
						await RenderingServer.frame_post_draw
						report["native_bake_upload_waits"] += 1
						var comparison: Dictionary = GEOMETRY.native_bake_error(GEOMETRY.head_mesh(person), poses[pose_key])
						comparison["provenance"] = "MeshInstance3D.bake_mesh_from_current_skeleton_pose; mesh-local model/time comparison"
						comparison["head_vertices"] = poses[pose_key].size()
						parity[pose_key] = comparison
					if not faces.has(guest.id):
						faces[guest.id] = GEOMETRY.seat_triangles(visual.prop, person)
					var sample: Dictionary = GEOMETRY.measure(person, visual.prop, false, poses[pose_key], faces[guest.id])
					if native_bake:
						var cached_comparison: Dictionary = parity[pose_key]
						sample["native_bake_pose_key"] = pose_key
						sample["native_bake_reused"] = reused_parity
						sample["native_bake_max_error"] = cached_comparison["max_error"]
						sample["native_bake_provenance"] = cached_comparison["provenance"]
						if not String(cached_comparison["error"]).is_empty():
							sample["error"] = cached_comparison["error"]
							sample["passes"] = false
					sample["item"] = String(definition.id)
					sample["turns"] = turns
					sample["seat_cell"] = [guest.cell.x, guest.cell.y]
					sample["model"] = String(person.model_name())
					sample["sit_time"] = animation.length * fraction
					sample["seat_height"] = person._seat_height
					var zero: Vector2i = GridMath.rotate_cell(Vector2i.ZERO, definition.footprint, turns)
					var front: Vector2i = GridMath.rotate_cell(Vector2i.UP, definition.footprint, turns) - zero
					var palm: Vector3 = person.to_global(person.carry_anchor_position())
					var table_item: PlacedItem = tables[guests.find(guest)]
					var table_center: Vector3 = ItemVisual.placed_transform(table_item.def as ItemDef, table_item.origin, turns if definition.category == ItemDef.Category.TABLE else 0).origin
					var direction: Vector3 = Vector3(front.x, 0.0, front.y)
					if definition.category == ItemDef.Category.TABLE:
						direction = (table_center - GridMath.cell_to_world(guest.cell)).normalized()
					sample["facing_dot"] = (-person.global_basis.z).normalized().dot(direction)
					sample["palms_to_table_horizontal"] = Vector2(palm.x - table_center.x, palm.z - table_center.z).length()
					sample["palms_world_y"] = palm.y
					(report["samples"] as Array).append(sample)
	view.free()
	report["errors"] = errors
