extends TestCase
## The seaside promenade (#596): a car-free street front with a terrace of beach
## shops. The promenade preset has no traffic; its named neighbours exist and can be
## shown closed and for sale; and the starter street is exactly what it was. The
## terrace stands wall to wall with the lot without ever touching it, and a closed
## arcade's bulb sign goes dark (#600).

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const PROMENADE: String = "res://data/streets/promenade.tres"
const SEASIDE: String = "res://data/streets/seaside.tres"
const RESERVE: Rect2i = Rect2i(-2, -2, 12, 9)
## A digest of everything the starter street builds (see `_digest`), taken before the
## promenade work. A change here means the starter street changed.
const STARTER_DIGEST: String = "aacd560112720e7b4f6c719fd747873106abd731cf8131875be5ac01ffd4d5ff"

var _viewport: SubViewport


func after_each() -> void:
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	NeighbourhoodDressing.clear_mesh_cache()


func _host() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)


func _dressing(preset: StreetPreset) -> NeighbourhoodDressing:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"########", "#......#", "#......#", "#......#", "#......#", "#......#", "###..###", "   EE   "]))
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	dressing.use_preset(preset)
	dressing.configure(grid, RESERVE, [{"cells": grid.entries().duplicate(), "normal": Vector2i.DOWN}] as Array[Dictionary],
		[] as Array[AABB])
	return dressing


## Everything the street builds that a player could see: the static meshes (name and
## vertex count), the furniture plan, the neighbours' doors, the street's bounds and the
## street life at a fixed time.
func _digest(dressing: NeighbourhoodDressing) -> String:
	var parts: Array = []
	for node: Node in dressing.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null or not dressing.is_ancestor_of(mesh) or mesh.get_parent() is PersonView \
				or dressing.car != null and dressing.car.is_ancestor_of(mesh) or _in_person(mesh):
			continue
		var vertices: int = 0
		for surface: int in mesh.mesh.get_surface_count():
			vertices += (mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		parts.append("%s:%d" % [dressing.get_path_to(mesh), vertices])
	parts.sort()
	for entry: Dictionary in dressing.furniture_plan():
		parts.append("%d@%.3f,%.3f" % [entry["kind"], entry["u"], entry["v"]])
	for door: float in dressing.shop_door_positions():
		parts.append("door%.3f" % door)
	dressing.set_review_time(7.0)
	var state: Dictionary = dressing.capture_state()
	parts.append(var_to_str(state["bounds"]))
	parts.append(var_to_str(state["car"]))
	for actor: Dictionary in state["actors"]:
		parts.append(var_to_str([actor["guest_id"], actor["position"], actor["direction"]]))
	return var_to_str(parts).sha256_text()


func _in_person(node: Node) -> bool:
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is PersonView:
			return true
		parent = parent.get_parent()
	return false


func test_the_promenade_preset_has_no_traffic() -> void:
	var promenade: StreetPreset = load(PROMENADE) as StreetPreset
	assert_not_null(promenade, "the promenade is a street preset")
	assert_eq(promenade.errors(), PackedStringArray())
	assert_not_null(promenade.promenade, "it is a promenade")
	assert_false(promenade.has_traffic(), "a promenade has no cars")
	assert_true(StreetPreset.starter().has_traffic(), "the starter street keeps its road")
	assert_true((load(SEASIDE) as StreetPreset).has_traffic(), "the seaside road keeps its cars")
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(promenade)
	assert_eq(dressing.build_error, "")
	var state: Dictionary = dressing.capture_state()
	assert_eq(state["car_count"], 0, "no car is built")
	assert_null(dressing.find_child("Road", true, false).get_child(0) if dressing.find_child("Road", true, false).get_child_count() > 0 else null,
		"no road is laid")
	assert_null(dressing.far_root.find_child("FarRoad", false, false), "no far road either")
	assert_true(dressing.pedestrians.size() > 3, "more people on foot instead")
	var kinds: Dictionary[StringName, bool] = {}
	for walker: Dictionary in dressing.walker_state():
		kinds[walker["kind"]] = true
	for kind: StringName in [&"stroll", &"jog", &"cycle", &"dog", &"pram"]:
		assert_true(kinds.has(kind), "someone is out: %s" % kind)
	# Every walker keeps to the paving and moves on the display clock alone.
	dressing.set_review_time(12.5)
	var first: Array[Dictionary] = dressing.walker_state()
	dressing.set_review_time(40.0)
	dressing.set_review_time(12.5)
	assert_eq(var_to_str(dressing.walker_state()), var_to_str(first), "the same time shows the same frame")
	for walker: Dictionary in first:
		var local: Vector3 = dressing.local_frame().affine_inverse() * (walker["position"] as Vector3)
		var v: float = local.z - dressing.street_shift()
		assert_true(v > 2.2 and v < NeighbourhoodDressing.FAR_START + NeighbourhoodDressing.FAR_DEPTH,
			"walker %s stays on the promenade (v %.2f)" % [walker["kind"], v])
		if walker["kind"] in [&"cycle", &"pram", &"dog"]:
			assert_true(walker.has("prop"), "the %s walker has their bike, pram or dog" % walker["kind"])
	dressing.get_parent().remove_child(dressing)
	dressing.free()


func test_the_promenade_neighbours_exist() -> void:
	var promenade: StreetPreset = load(PROMENADE) as StreetPreset
	var inner: Array[StringName] = []
	for side: Array[ShopStyle] in [promenade.buildings.terrace_left, promenade.buildings.terrace_right]:
		assert_false(side.is_empty(), "the terrace runs both ways")
		inner.append(side[0].id)
	assert_true(inner.has(&"surf_hire"), "the surf-hire shop is next door")
	assert_true(inner.has(&"beach_goods"), "the bucket-and-spade shop is next door on the other side")
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(promenade)
	assert_eq(dressing.build_error, "")
	var ids: Array[StringName] = dressing.neighbour_ids()
	for id: StringName in [&"surf_hire", &"beach_goods", &"chip_kiosk", &"arcade"]:
		assert_true(ids.has(id), "the terrace has %s" % id)
		var node: Node3D = dressing.neighbour(id)
		assert_not_null(node, "%s has its own node" % id)
		if node != null:
			assert_eq(String(node.name), String(id), "named for its id")
			assert_not_null(node.get_node_or_null(^"Shell"), "%s has its building" % id)
	var huts: int = 0
	for id: StringName in ids:
		if String(id).begins_with("beach_hut"):
			huts += 1
	assert_true(huts >= 1, "a beach hut or two")
	var surf: Label3D = dressing.neighbour(&"surf_hire").get_node_or_null(^"Sign") as Label3D
	assert_not_null(surf, "the surf-hire shop has a painted sign")
	if surf != null:
		assert_eq(surf.text, "SURF HIRE")
	# The two next-door shops stand right beside the lot, one each side, nearest of their rows.
	var surf_info: Dictionary = dressing.neighbour_info(&"surf_hire")
	var goods_info: Dictionary = dressing.neighbour_info(&"beach_goods")
	assert_eq(surf_info["slot"], 0, "the surf-hire shop is next door")
	assert_eq(goods_info["slot"], 0, "so is the bucket-and-spade shop")
	assert_ne(surf_info["side"], goods_info["side"], "one each side of the lot")
	assert_eq(surf_info["name"], "SURF HIRE")
	assert_true(dressing.neighbour(&"no_such_shop") == null, "an unknown id has no node")
	# The starter street names none, so nothing there can be bought or closed.
	var starter: NeighbourhoodDressing = _dressing(StreetPreset.starter())
	assert_eq(starter.neighbour_ids(), [] as Array[StringName])
	for node: NeighbourhoodDressing in [dressing, starter]:
		node.get_parent().remove_child(node)
		node.free()


func test_a_neighbour_can_be_shown_closed_and_for_sale() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(PROMENADE) as StreetPreset)
	var surf: Node3D = dressing.neighbour(&"surf_hire")
	assert_eq(dressing.neighbour_state(&"surf_hire"), NeighbourhoodDressing.NeighbourState.OCCUPIED, "occupied by default")
	assert_true((surf.get_node(^"Trade") as Node3D).visible, "its stock is out")
	assert_false((surf.get_node(^"ForSale") as Node3D).visible, "no for-sale board")
	assert_true(dressing.set_neighbour_state(&"surf_hire", NeighbourhoodDressing.NeighbourState.FOR_SALE))
	assert_eq(dressing.neighbour_state(&"surf_hire"), NeighbourhoodDressing.NeighbourState.FOR_SALE)
	assert_false((surf.get_node(^"Trade") as Node3D).visible, "closed: the stock is in")
	assert_true((surf.get_node(^"ForSale") as Node3D).visible, "a for-sale board in the window")
	assert_eq(dressing.neighbour_state(&"beach_goods"), NeighbourhoodDressing.NeighbourState.OCCUPIED, "the other side stays open")
	# The state survives a rebuild of the street.
	dressing.street_set = (load(PROMENADE) as StreetPreset).buildings
	dressing.rebuild()
	assert_true((dressing.neighbour(&"surf_hire").get_node(^"ForSale") as Node3D).visible, "still for sale after a rebuild")
	assert_true(dressing.set_neighbour_state(&"surf_hire", NeighbourhoodDressing.NeighbourState.OCCUPIED))
	assert_false((dressing.neighbour(&"surf_hire").get_node(^"ForSale") as Node3D).visible, "open again")
	assert_false(dressing.set_neighbour_state(&"no_such_shop", NeighbourhoodDressing.NeighbourState.FOR_SALE), "an unknown id is refused")
	dressing.get_parent().remove_child(dressing)
	dressing.free()


## The lot in the dressing's space (x, z), as the shop view hands it over: RESERVE in cells.
func _lot_rect() -> Rect2:
	return Rect2(Vector2(RESERVE.position) * GridMath.CELL_SIZE, Vector2(RESERVE.size) * GridMath.CELL_SIZE)


static func _overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x - 0.0001 and a.end.x > b.position.x + 0.0001 \
		and a.position.y < b.end.y - 0.0001 and a.end.y > b.position.y + 0.0001


static func _xz(node: MeshInstance3D) -> Rect2:
	var box: AABB = node.global_transform * node.get_aabb()
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


func test_no_neighbour_overlaps_the_maximum_lot_and_the_next_door_shops_stand_wall_to_wall() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(PROMENADE) as StreetPreset)
	assert_eq(dressing.build_error, "")
	var lot: Rect2 = _lot_rect()
	# The lot here reaches past the shop on every side, like a lease with room to expand.
	for box: AABB in dressing.building_boxes_in_view():
		assert_false(_overlaps(Rect2(box.position.x, box.position.z, box.size.x, box.size.z), lot),
			"a building's box clears the maximum lot: %s" % box)
	# Every mesh a neighbour owns (its shell and walled yard, its stock, its for-sale front and
	# its bulbs) and the lot's own front walls stay off the maximum lot too.
	var meshes: Array[MeshInstance3D] = []
	for id: StringName in dressing.neighbour_ids():
		for node: Node in dressing.neighbour(id).find_children("*", "MeshInstance3D", true, false):
			meshes.append(node as MeshInstance3D)
	var fronts: MeshInstance3D = dressing.find_child("YardFronts", true, false) as MeshInstance3D
	assert_not_null(fronts, "the lot's side strips meet the promenade with a wall and gate")
	if fronts != null:
		meshes.append(fronts)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh != null:
			assert_false(_overlaps(_xz(mesh), lot), "%s clears the maximum lot" % dressing.get_path_to(mesh))
	# Wall to wall: each next-door shop's party wall stands within a hand's width of the lot's edge.
	for id: StringName in [&"surf_hire", &"beach_goods"]:
		var info: Dictionary = dressing.neighbour_info(id)
		var facade: Transform3D = info["facade"]
		var inner: float = facade.origin.x - float(info["side"]) * float(info["width"]) * 0.5
		var edge: float = lot.position.x if int(info["side"]) < 0 else lot.end.x
		var gap: float = (edge - inner) * -float(info["side"])
		assert_true(gap > 0.0 and gap < 0.2, "%s backs right onto the lot (gap %.3f m)" % [id, gap])
	# The starter street has no terrace, so no front walls either.
	var starter: NeighbourhoodDressing = _dressing(StreetPreset.starter())
	assert_null(starter.find_child("YardFronts", true, false), "the starter street builds no yard walls")
	for node: NeighbourhoodDressing in [dressing, starter]:
		node.get_parent().remove_child(node)
		node.free()


func test_a_closed_arcade_s_bulb_sign_goes_dark() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(PROMENADE) as StreetPreset)
	var arcade: Node3D = dressing.neighbour(&"arcade")
	assert_not_null(arcade, "the promenade has its arcade")
	var sign: Label3D = arcade.get_node_or_null(^"Sign") as Label3D
	assert_not_null(arcade.get_node_or_null(^"Lamps"), "the arcade has its own bulbs")
	assert_false(dressing.neighbour_lit(&"arcade"), "by day the bulbs are off")
	dressing.set_night(1.0)
	assert_true(dressing.neighbour_lit(&"arcade"), "at night an open arcade's bulbs are lit")
	assert_false(sign.shaded, "and its name glows")
	assert_true(dressing.set_neighbour_state(&"arcade", NeighbourhoodDressing.NeighbourState.FOR_SALE))
	assert_false(dressing.neighbour_lit(&"arcade"), "closed and for sale: the bulbs are dark")
	assert_true(sign.shaded, "and its name is only paint in the dark")
	# Dark through a rebuild of the street, and lit again when it reopens.
	dressing.street_set = (load(PROMENADE) as StreetPreset).buildings
	dressing.rebuild()
	assert_false(dressing.neighbour_lit(&"arcade"), "still dark after a rebuild")
	assert_true((dressing.neighbour(&"arcade").get_node(^"Sign") as Label3D).shaded, "its sign too")
	assert_true(dressing.set_neighbour_state(&"arcade", NeighbourhoodDressing.NeighbourState.OCCUPIED))
	assert_true(dressing.neighbour_lit(&"arcade"), "reopened, it lights up again")
	assert_false((dressing.neighbour(&"arcade").get_node(^"Sign") as Label3D).shaded)
	dressing.get_parent().remove_child(dressing)
	dressing.free()


func test_the_starter_street_is_unchanged() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(StreetPreset.starter())
	assert_eq(dressing.build_error, "")
	var digest: String = _digest(dressing)
	print("STARTER_DIGEST ", digest)
	assert_eq(digest, STARTER_DIGEST, "the starter street builds exactly what it did before the promenade")
	assert_true(StreetPreset.starter().has_traffic())
	assert_eq(dressing.capture_state()["car_count"], 1, "its car still drives by")
	assert_eq(dressing.pedestrians.size(), 3, "and its three passers-by walk")
	dressing.get_parent().remove_child(dressing)
	dressing.free()
