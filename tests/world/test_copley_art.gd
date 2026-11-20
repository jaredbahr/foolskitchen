extends TestCase
## Chef Copley's art (#701): the made food truck, sign and closing-sign trophy
## (assets/made/copley/, tools/build_copley_art.py), the RIVAL look a neighbour can wear
## (a gaudy sign, bunting and balloons), the named rival house across the starter street,
## the food truck parked at the lots with no shopfronts, and the not-for-sale trophy item.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const METRICS: String = "res://assets/made/copley/copley.metrics.json"
const PROMENADE: String = "res://data/streets/promenade.tres"
const RESERVE: Rect2i = Rect2i(-2, -2, 12, 9)
const OPEN_LAND: Array[String] = ["cliff", "country", "rooftop", "woodland"]

var _viewport: SubViewport
var _views: Array[Node] = []


func after_each() -> void:
	for view: Node in _views:
		if is_instance_valid(view):
			view.free()
	_views.clear()
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


func _free(dressing: NeighbourhoodDressing) -> void:
	dressing.get_parent().remove_child(dressing)
	dressing.free()


func _metrics() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(METRICS))
	assert_true(parsed is Dictionary, "the metrics file parses")
	return parsed as Dictionary if parsed is Dictionary else {}


## The visible meshes of a street as one number each: how many vertices, and a checksum of where
## they are, so a street with and without a rival house can be compared.
func _visible_geometry(dressing: NeighbourhoodDressing) -> Dictionary:
	var count: int = 0
	var checksum: float = 0.0
	for node: Node in dressing.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var parent: Node = mesh.get_parent()
		var inside_person: bool = false
		while parent != null and parent != dressing:
			if parent is PersonView:
				inside_person = true
			parent = parent.get_parent()
		if inside_person or (dressing.car != null and dressing.car.is_ancestor_of(mesh)):
			continue
		for surface: int in mesh.mesh.get_surface_count():
			for vertex: Vector3 in (mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var world: Vector3 = mesh.global_transform * vertex
				count += 1
				checksum += world.x * 1.3 + world.y * 1.7 + world.z * 1.9
	return {"count": count, "checksum": checksum}


# --- the models --------------------------------------------------------------------

func test_the_made_models_are_within_budget_and_match_the_name_areas() -> void:
	var metrics: Dictionary = _metrics()
	var assets: Dictionary = metrics.get("assets", {})
	var budget: int = int(metrics.get("budget", 0))
	assert_eq(budget, 800, "the decor triangle budget")
	assert_eq(assets.keys().size(), 3, "the truck, the sign and the trophy")
	for id: String in ["copley_truck", "copley_sign", "copley_closing_sign"]:
		assert_true(assets.has(id), id)
		if not assets.has(id):
			continue
		assert_true(int(assets[id]["triangles"]) <= budget, "%s is within the triangle budget" % id)
		assert_true(load(NeighbourhoodRival.MADE_ROOT + id + ".glb") is PackedScene, "%s loads" % id)
	var truck: Dictionary = assets["copley_truck"]
	var panel: Dictionary = truck["text"]["panel"]
	assert_true((NeighbourhoodRival.TRUCK_TEXT_CENTRE - _vector(panel["centre"])).length() < 0.0001, "the truck's name panel")
	assert_true((NeighbourhoodRival.TRUCK_TEXT_SIZE - _vector2(panel["size"])).length() < 0.0001, "and its size")
	var sign_panel: Dictionary = assets["copley_sign"]["text"]["panel"]
	assert_true((NeighbourhoodRival.SIGN_TEXT_CENTRE - _vector(sign_panel["centre"])).length() < 0.0001, "the sign's name plate")
	assert_true((NeighbourhoodRival.SIGN_TEXT_SIZE - _vector2(sign_panel["size"])).length() < 0.0001, "and its size")
	assert_eq(assets["copley_closing_sign"]["text"]["panel"], sign_panel, "the trophy is the same sign")
	# The truck is about 2 x 1 cells (0.5 m each) and a little taller than a person (0.75 m).
	var size: Array = truck["world_box"]["size"]
	assert_true(float(size[0]) > 1.0 and float(size[0]) < 1.6, "about 2 x 1 cells long: %s" % size[0])
	assert_true(float(size[2]) > 0.5 and float(size[2]) < 0.9, "and across: %s" % size[2])
	assert_true(float(size[1]) > 0.9 and float(size[1]) < 1.5, "taller than a person: %s" % size[1])
	var trophy: Array = assets["copley_closing_sign"]["world_box"]["size"]
	assert_true(float(trophy[0]) <= 1.1, "the trophy fits its two wall faces")


static func _vector(parts: Array) -> Vector3:
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


static func _vector2(parts: Array) -> Vector2:
	return Vector2(float(parts[0]), float(parts[1]))


# --- the trophy --------------------------------------------------------------------

func test_the_closing_sign_is_a_wall_decor_item_that_is_not_for_sale() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var definition: ItemDef = content.item(&"copley_sign")
	assert_not_null(definition, "copley_sign is content")
	if definition == null:
		return
	assert_eq(definition.display_name, "Copley's Closing Sign")
	assert_eq(definition.charm, 2)
	assert_eq(int(definition.category), int(ItemDef.Category.DECOR))
	assert_true(definition.hangs_on_wall(), "it hangs on a wall")
	assert_eq(definition.footprint, Vector2i(2, 1), "two wall faces wide")
	assert_false(definition.catalogue_visible, "it is not in the catalogue: the rival's closing is the only way to get one")
	assert_eq(definition.price, 0)
	assert_true(definition.lot_tags.is_empty(), "it can hang at any lot")
	var view: PropView = definition.view_scene.instantiate() as PropView
	_views.append(view)
	var model: Node = view.get_node("WallMount/Art/Model")
	assert_eq(model.scene_file_path, NeighbourhoodRival.CLOSING_SIGN_MODEL)
	# Its back plane sits on the wall: the bounds' far z is where the other wall pieces stop.
	var box: AABB = view.get_combined_aabb()
	assert_true(absf(box.end.z - 0.25) < 0.005, "it hangs flush: %.4f" % box.end.z)
	assert_true(box.position.y > 0.5 and box.end.y < ArtScale.WALL_HEIGHT, "inside the wall's height")


# --- the rival look ----------------------------------------------------------------

func test_the_starter_street_names_a_rival_house_that_looks_like_any_house_until_he_arrives() -> void:
	await _host()
	var starter: NeighbourhoodDressing = _dressing(StreetPreset.starter())
	assert_eq(starter.build_error, "")
	var plain: StreetPreset = StreetPreset.starter().duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as StreetPreset
	plain.buildings.rival_house = -1
	var without: NeighbourhoodDressing = _dressing(plain)
	assert_eq(without.neighbour_ids(), [] as Array[StringName], "no slot, no neighbour")
	assert_eq(starter.neighbour_ids(), [StreetSet.RIVAL_ID] as Array[StringName], "one named slot across the road")
	assert_eq(starter.neighbour_state(StreetSet.RIVAL_ID), NeighbourhoodDressing.NeighbourState.OCCUPIED)
	var with_slot: Dictionary = _visible_geometry(starter)
	var without_slot: Dictionary = _visible_geometry(without)
	assert_eq(with_slot["count"], without_slot["count"], "the street has the same vertices with the slot unused")
	assert_true(absf(float(with_slot["checksum"]) - float(without_slot["checksum"])) < 0.5, "in the same places")
	assert_null(starter.neighbour(StreetSet.RIVAL_ID).get_node_or_null(^"Rival"), "and carries no rival look yet")
	var info: Dictionary = starter.neighbour_info(StreetSet.RIVAL_ID)
	assert_eq(info["name"], "", "an ordinary house has no shop sign")
	# The house is across the road from the lot: well out past its maximum footprint.
	var facade: Transform3D = info["facade"]
	var local: Vector3 = starter.local_frame().affine_inverse() * facade.origin
	assert_true(local.z > starter.street_shift() + NeighbourhoodBuildings.FENCE_V, "across the road: z %.2f" % local.z)
	_free(starter)
	_free(without)


func test_a_neighbour_can_be_taken_over_by_the_rival_and_given_back() -> void:
	await _host()
	var starter: NeighbourhoodDressing = _dressing(StreetPreset.starter())
	var id: StringName = StreetSet.RIVAL_ID
	var before: Dictionary = _visible_geometry(starter)
	assert_true(starter.set_neighbour_state(id, NeighbourhoodDressing.NeighbourState.RIVAL, "Cool's Kitchen"))
	assert_eq(starter.neighbour_state(id), NeighbourhoodDressing.NeighbourState.RIVAL)
	assert_eq(starter.neighbour_name(id), "Cool's Kitchen")
	assert_eq(starter.neighbour_info(id)["name"], "Cool's Kitchen")
	var look: Node3D = starter.neighbour(id).get_node_or_null(^"Rival") as Node3D
	assert_not_null(look, "his look is on the house")
	assert_true(look.visible)
	var words: Label3D = look.get_node("Sign/Name") as Label3D
	assert_eq(words.text, "Cool's Kitchen", "the name is painted on the sign")
	assert_true(words.pixel_size > 0.0)
	# The sign's plate is where the label is: the made model's plate scaled with the sign.
	var sign: Node3D = look.get_node("Sign") as Node3D
	var plate: Vector3 = sign.to_global(NeighbourhoodRival.SIGN_TEXT_CENTRE * (words.position.length() / NeighbourhoodRival.SIGN_TEXT_CENTRE.length()))
	assert_true(plate.distance_to(words.global_position) < 0.02, "the lettering sits on the plate")
	assert_true(look.get_node("Decor") is MeshInstance3D, "with bunting and balloons")
	assert_false((starter.neighbour(id).get_node(^"ForSale") as Node3D).visible, "it is open for trade")
	assert_true((starter.neighbour(id).get_node(^"Trade") as Node3D).visible)
	# A new name replaces the old; no second look is built.
	assert_true(starter.set_neighbour_state(id, NeighbourhoodDressing.NeighbourState.RIVAL, "Not Fool's Kitchen"))
	assert_eq((starter.neighbour(id).find_children("Rival", "Node3D", false, false)).size(), 1)
	assert_eq((starter.neighbour(id).get_node(^"Rival/Sign/Name") as Label3D).text, "Not Fool's Kitchen")
	# It survives a rebuild of the street (a different street set, so the street really is built again).
	var changed: StreetSet = StreetSet.standard()
	changed.seed_salt += 1
	starter.street_set = changed
	starter.rebuild()
	assert_eq(starter.neighbour_state(id), NeighbourhoodDressing.NeighbourState.RIVAL, "he is still there after a rebuild")
	assert_eq((starter.neighbour(id).get_node(^"Rival/Sign/Name") as Label3D).text, "Not Fool's Kitchen", "with his new name")
	assert_true((starter.neighbour(id).get_node(^"Rival") as Node3D).visible)
	_free(starter)
	# Giving it back hides the look, and the house is as it was.
	var again: NeighbourhoodDressing = _dressing(StreetPreset.starter())
	assert_true(again.set_neighbour_state(id, NeighbourhoodDressing.NeighbourState.RIVAL, "Cool's Kitchen"))
	assert_true(again.set_neighbour_state(id, NeighbourhoodDressing.NeighbourState.OCCUPIED))
	assert_false((again.neighbour(id).get_node(^"Rival") as Node3D).visible, "his look goes")
	assert_eq(again.neighbour_name(id), "", "and so does his name")
	var after: Dictionary = _visible_geometry(again)
	assert_eq(after["count"], before["count"], "the house is as it was")
	assert_true(absf(float(after["checksum"]) - float(before["checksum"])) < 0.5)
	# A house can still be shown for sale: a board on a post in the front yard.
	assert_true(again.set_neighbour_state(id, NeighbourhoodDressing.NeighbourState.FOR_SALE))
	assert_true((again.neighbour(id).get_node(^"ForSale") as Node3D).visible)
	assert_false((again.neighbour(id).get_node(^"Rival") as Node3D).visible)
	assert_false(again.set_neighbour_state(&"no_such_house", NeighbourhoodDressing.NeighbourState.RIVAL, "x"), "an unknown id is refused")
	_free(again)


func test_the_rival_look_changes_no_other_neighbour_and_fits_every_building_form() -> void:
	await _host()
	var promenade: NeighbourhoodDressing = _dressing(load(PROMENADE) as StreetPreset)
	assert_eq(promenade.build_error, "")
	var closed: StringName = &"surf_hire"
	assert_true(promenade.set_neighbour_state(closed, NeighbourhoodDressing.NeighbourState.FOR_SALE))
	var untouched: Dictionary = _visible_geometry(promenade)
	var ids: Array[StringName] = promenade.neighbour_ids()
	var forms: Dictionary[int, bool] = {}
	for id: StringName in ids:
		if id == closed:
			continue
		var info: Dictionary = promenade.neighbour_info(id)
		forms[int(info["form"])] = true
		var shell_before: Array = _states(promenade, id)
		assert_true(promenade.set_neighbour_state(id, NeighbourhoodDressing.NeighbourState.RIVAL, "Beachfront Bored Walk"), String(id))
		var look: Node3D = promenade.neighbour(id).get_node(^"Rival") as Node3D
		assert_not_null(look, "%s wears his look" % id)
		assert_false((promenade.neighbour(id).get_node_or_null(^"Sign") as Label3D).visible if promenade.neighbour(id).get_node_or_null(^"Sign") != null else false,
			"%s's own name is covered" % id)
		assert_true(promenade.neighbour_name(id) == "Beachfront Bored Walk")
		# Sign and balloons stay near the building: nothing strays from the facade.
		var bounds: AABB = AABB()
		for mesh: Node in look.find_children("*", "MeshInstance3D", true, false):
			var part: MeshInstance3D = mesh as MeshInstance3D
			bounds = (part.global_transform * part.get_aabb()) if bounds.size == Vector3.ZERO else bounds.merge(part.global_transform * part.get_aabb())
		assert_true(bounds.size.length() > 0.5 and bounds.size.length() < 8.0, "%s: his look is a sensible size" % id)
		assert_true(promenade.set_neighbour_state(id, NeighbourhoodDressing.NeighbourState.OCCUPIED))
		assert_eq(_states(promenade, id), shell_before, "%s is as it was when he leaves" % id)
	assert_true(forms.size() >= 4, "a shop, a kiosk, a hut and an arcade all took his look: %s" % str(forms.keys()))
	assert_eq(promenade.neighbour_state(closed), NeighbourhoodDressing.NeighbourState.FOR_SALE, "the closed shop stayed closed")
	var after: Dictionary = _visible_geometry(promenade)
	assert_eq(after["count"], untouched["count"], "the street has the vertices it had before he came and went")
	assert_true(absf(float(after["checksum"]) - float(untouched["checksum"])) < 0.5)
	_free(promenade)


## What a neighbour shows: which of its parts are visible.
func _states(dressing: NeighbourhoodDressing, id: StringName) -> Array:
	var shown: Array = []
	for child: Node in dressing.neighbour(id).get_children():
		var node: Node3D = child as Node3D
		if node != null:
			shown.append([String(node.name), node.visible])
	shown = shown.filter(func(entry: Array) -> bool: return entry[0] != "Rival")
	return shown


# --- the food truck ----------------------------------------------------------------

func test_the_truck_parks_only_where_a_street_names_a_slot() -> void:
	await _host()
	for path: String in ["res://data/streets/starter.tres", "res://data/streets/seaside.tres", PROMENADE]:
		var dressing: NeighbourhoodDressing = _dressing(load(path) as StreetPreset)
		assert_false(dressing.can_park_truck(), "%s has shopfronts: the rival takes a building" % path)
		assert_false(dressing.set_rival_truck("Cool's Kitchen"), path)
		assert_null(dressing.rival_truck())
		_free(dressing)
	for kind: String in OPEN_LAND:
		var preset: StreetPreset = load("res://data/streets/%s.tres" % kind) as StreetPreset
		var dressing: NeighbourhoodDressing = _dressing(preset)
		assert_eq(dressing.build_error, "", kind)
		assert_true(dressing.can_park_truck(), kind)
		assert_null(dressing.rival_truck(), "%s: no truck until he comes" % kind)
		assert_true(dressing.set_rival_truck("Seaside Riff"), kind)
		var truck: Node3D = dressing.rival_truck()
		assert_not_null(truck, kind)
		assert_eq((truck.get_node("Name") as Label3D).text, "Seaside Riff", kind)
		assert_true(truck.get_node("Model").get_child_count() == 1, "%s: the made model is in" % kind)
		# The truck stands in front of the lot, beside the door, off the door's own approach.
		var spot: Dictionary = dressing.rival_truck_spot()
		var footprint: Rect2 = spot["footprint"]
		var lot_front: float = dressing.street_shift()
		assert_true(footprint.position.y > lot_front, "%s: it is outside the lot, not on the shop floor" % kind)
		assert_true(footprint.position.y < lot_front + 4.0, "%s: and near the door" % kind)
		assert_true(footprint.end.x < -1.2 or footprint.position.x > 1.2, "%s: it leaves the door's approach clear" % kind)
		# It is where the spot says, with its hatch toward the street.
		var local: Vector3 = dressing.local_frame().affine_inverse() * truck.global_position
		assert_true(absf(local.x - float(spot["u"])) < 0.001 and absf(local.z - float(spot["z"])) < 0.001, kind)
		# A rebuild keeps it, a second name renames it, and sending it away removes it.
		dressing.rebuild()
		assert_not_null(dressing.rival_truck(), "%s: it is still there" % kind)
		assert_true(dressing.set_rival_truck("Beachfront Bored Walk"))
		assert_eq((dressing.rival_truck().get_node("Name") as Label3D).text, "Beachfront Bored Walk")
		dressing.clear_rival_truck()
		assert_null(dressing.rival_truck(), kind)
		assert_eq(dressing.rival_truck_name(), "")
		_free(dressing)
