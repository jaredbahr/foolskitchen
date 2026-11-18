extends TestCase
## The Seaside Cliff's street (#380): a cliff-top café over the sea. The cliff preset is
## valid and has no traffic, street, pavement, cars, neighbours or passers-by; nothing
## it stands up is on the lot's maximum footprint or the door's approach; the cliff edge
## and its rail stay outside the maximum lot; the coast, sea and life are the same every
## build and every frame for a given clock; the Seaside Cliff lot names the preset and
## defaults to whitewashed walls; and every other street builds exactly what it did
## before the cliff.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const CLIFF: String = "res://data/streets/cliff.tres"
const LOT: String = "res://data/lots/seaside_cliff.tres"
const RESERVE: Rect2i = Rect2i(-2, -2, 12, 9)
## Every other street's digest (see `_digest`, the same one test_rooftop_street.gd
## holds), taken on main before the cliff: a change here means that street changed.
const DIGESTS: Dictionary[String, String] = {
	"res://data/streets/starter.tres": "aacd560112720e7b4f6c719fd747873106abd731cf8131875be5ac01ffd4d5ff",
	"res://data/streets/seaside.tres": "84d6b57a43954776d68096fa88f967ba1fe6b9a51a8c40c4a7509146a81b0c86",
	"res://data/streets/promenade.tres": "6360419dd2afd9921e1450c39fea1879465f0ae8df33491001de67d8f2406649",
	"res://data/streets/woodland.tres": "25d71eed7b271fc2ae3df6c594d0deaa3efb3fe402918f832694dfa16a832950",
	"res://data/streets/country.tres": "06808771942aa2313f5bdbf8f92daf6a069b91d37b72a920d2402497836512da",
	"res://data/streets/rooftop.tres": "2b1100223514a6d0063f9794b040524243a3d18d602a0a82b9aac1522ab369ad",
}

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


func _grid() -> SimGrid:
	return SimGrid.from_ascii(PackedStringArray([
		"########", "#......#", "#......#", "#......#", "#......#", "#......#", "###..###", "   EE   "]))


func _dressing(preset: StreetPreset) -> NeighbourhoodDressing:
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	dressing.use_preset(preset)
	var grid: SimGrid = _grid()
	dressing.configure(grid, RESERVE, [{"cells": grid.entries().duplicate(), "normal": Vector2i.DOWN}] as Array[Dictionary],
		[] as Array[AABB])
	return dressing


func _free(dressing: NeighbourhoodDressing) -> void:
	dressing.get_parent().remove_child(dressing)
	dressing.free()


static func _vector(parts: Array) -> Vector3:
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


static func _box(entry: Dictionary) -> AABB:
	return AABB(_vector(entry["position"]), _vector(entry["size"]))


## The same digest as test_rooftop_street.gd: every static mesh (name and vertex
## count), the furniture plan, the neighbours' doors, the bounds and the street life.
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


## The lot's maximum footprint in the cliff's local (u, z).
func _local_lot(cliff: NeighbourhoodCliff) -> Rect2:
	return cliff.lot


func test_the_cliff_preset_is_valid_and_has_no_traffic() -> void:
	var preset: StreetPreset = load(CLIFF) as StreetPreset
	assert_not_null(preset, "the cliff is a street preset")
	assert_eq(preset.errors(), PackedStringArray())
	assert_eq(String(preset.id), "cliff")
	assert_not_null(preset.cliff, "it is a cliff top")
	assert_false(preset.has_traffic(), "no cars come up the cliff path")
	# A cliff missing a list it draws from is refused, in plain words.
	var broken: CliffSkin = preset.cliff.duplicate() as CliffSkin
	broken.strata = [] as Array[Color]
	assert_true(broken.errors().size() > 0, "a cliff with no rock strata is an error")
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(preset)
	assert_eq(dressing.build_error, "")
	assert_true(dressing.has_cliff())
	assert_false(dressing.has_rooftop())
	assert_false(dressing.has_forest())
	assert_eq(dressing.capture_state()["car_count"], 0, "no car is built")
	assert_eq(dressing.find_child("Road", true, false).get_child_count(), 0, "no road is laid")
	assert_eq(dressing.find_child("Pavement", true, false).get_child_count(), 0, "no pavement either")
	assert_eq(dressing.find_child("Buildings", true, false).get_child_count(), 0, "no neighbouring shops")
	assert_eq(dressing.find_child("StreetLamps", true, false).get_child_count(), 0, "no street lamps")
	assert_eq(dressing.far_root.get_child_count(), 0, "no far road")
	assert_eq(dressing.ground_root.get_child_count(), 0, "the street's meadow gives way to the cliff top")
	assert_eq(dressing.walker_state(), [] as Array[Dictionary], "no street runs past")
	var cliff: NeighbourhoodCliff = dressing.cliff()
	assert_not_null(cliff, "the cliff is built")
	assert_true(cliff.drop() >= 10.0, "the sea is a long way down")
	assert_true(cliff.stacks.size() >= 2, "sea stacks stand off the cove")
	assert_true(cliff.rail_points.size() > 10, "a rail runs along the edge")
	assert_true(cliff.path_points.size() > 10, "a cliff path winds up to the door")
	assert_not_null(cliff.sea, "the sea lies below")
	assert_eq((cliff.sea.material_override as ShaderMaterial).shader, NeighbourhoodCliff.SEA_SHADER, "the beach's water")
	# The lights come on from dusk; the gulls roost late at night.
	dressing.set_night(0.0)
	assert_false(cliff.is_lit())
	assert_false(cliff.beam.visible, "no beam by day")
	assert_true(cliff.gulls.size() > 0 and cliff.gulls[0].visible, "gulls glide by day")
	dressing.set_night(1.0, 1.0)
	assert_true(cliff.is_lit(), "the lamps light up at night")
	assert_true(cliff.beam.visible, "the lighthouse beam sweeps at night")
	assert_false(cliff.gulls[0].visible, "the gulls have gone to roost")
	_free(dressing)


## Jared's chalk (#380 follow-up): a lower drop so the sea shows, bright white chalk with
## faint grey bands and dark flint lines under a green turf cap, sea stacks between the
## sea and the top, and the chalk catching the moon at night.
func test_the_cliff_is_white_chalk_over_a_lower_drop() -> void:
	await _host()
	var skin: CliffSkin = (load(CLIFF) as StreetPreset).cliff
	assert_true(skin.drop >= 10.0 and skin.drop <= 11.0, "about 10 m down, so the sea shows (%.1f)" % skin.drop)
	var lightest: float = 0.0
	var darkest: float = 1.0
	for colour: Color in skin.strata:
		lightest = maxf(lightest, colour.get_luminance())
		darkest = minf(darkest, colour.get_luminance())
	assert_true(darkest >= 0.75, "every stratum is pale chalk (%.2f)" % darkest)
	assert_true(lightest <= 0.95, "the brightest stays short of pure white so a lit face never blows out (%.2f)" % lightest)
	assert_true(lightest - darkest >= 0.05 and lightest - darkest <= 0.2, "the grey bands are faint")
	assert_true(skin.flint.a > 0.0 and skin.flint.get_luminance() < 0.45, "dark flint lines run through the chalk")
	assert_true(skin.turf.g > skin.turf.r and skin.turf.g > skin.turf.b, "a green turf cap")
	assert_true(skin.relief < 1.0, "a sheerer face than ledged sandstone")
	var dressing: NeighbourhoodDressing = _dressing(load(CLIFF) as StreetPreset)
	var cliff: NeighbourhoodCliff = dressing.cliff()
	for stack: Vector4 in cliff.stacks:
		assert_true(stack.w > 0.5 and stack.w < cliff.drop() - 0.5, "a sea stack stands between the sea and the top")
	var rock: MeshInstance3D = cliff.root.find_child("Cliff", false, false) as MeshInstance3D
	var material: StandardMaterial3D = rock.material_override as StandardMaterial3D
	dressing.set_night(0.0)
	assert_eq(material.albedo_color, Color.WHITE, "by day the chalk is as the sun lights it")
	dressing.set_night(1.0, 1.0)
	assert_true(material.albedo_color.b > 1.0, "at night the chalk catches the moon")
	_free(dressing)


func test_nothing_stands_on_the_lot_or_the_approach() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(CLIFF) as StreetPreset)
	var state: Dictionary = dressing.capture_state()
	var reserve: AABB = _box(state["bounds"]["reserve"])
	var lot: AABB = AABB(Vector3(RESERVE.position.x, 0.0, RESERVE.position.y) * GridMath.CELL_SIZE,
		Vector3(RESERVE.size.x, 1.0, RESERVE.size.y) * GridMath.CELL_SIZE)
	assert_true(reserve.encloses(lot.grow(-0.01)), "the reserve covers the maximum lot")
	var keep_off: Array[AABB] = [reserve]
	for box: Dictionary in state["bounds"]["door_approaches"]:
		keep_off.append(_box(box))
	assert_true(keep_off.size() > 1, "the door has an approach")
	var cliff: NeighbourhoodCliff = dressing.cliff()
	var frame: Transform3D = cliff.root.global_transform
	var pieces: Array[MeshInstance3D] = []
	for child: Node in cliff.root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null and (child as MeshInstance3D).mesh.get_surface_count() > 0:
			pieces.append(child as MeshInstance3D)
	assert_true(pieces.size() >= 8, "the ground, cliff, props, sea and lights are built")
	# Only flat ground (under the floor line) lies under the lot and the approach.
	for piece: MeshInstance3D in pieces:
		if piece.name == "LighthouseBeam" or piece.name.begins_with("Gull") or piece.name == "FishingBoat":
			continue
		var stray: int = 0
		for point: Vector3 in (piece.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			var world: Vector3 = frame * point
			if world.y < 0.02:
				continue
			for box: AABB in keep_off:
				if world.x > box.position.x and world.x < box.end.x and world.z > box.position.z and world.z < box.end.z:
					stray += 1
		assert_eq(stray, 0, "nothing in %s stands on the lot or the door's approach" % piece.name)
	for vertex: Vector3 in (cliff.root.get_node(^"Ground") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		assert_true(vertex.y < 0.0, "the cliff top lies under the shop floor")
		break
	_free(dressing)


func test_the_edge_and_rail_stay_outside_the_maximum_lot() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(CLIFF) as StreetPreset)
	var cliff: NeighbourhoodCliff = dressing.cliff()
	var lot: Rect2 = _local_lot(cliff)
	assert_true(lot.has_area(), "the lot was found")
	var reserve: AABB = _box(dressing.capture_state()["bounds"]["reserve"])
	var local: AABB = cliff.root.global_transform.affine_inverse() * reserve
	assert_true(lot.grow(0.01).encloses(Rect2(local.position.x, local.position.z, local.size.x, local.size.z)),
		"the cliff plans round the whole maximum lot")
	var nearest_edge: float = INF
	for point: Vector2 in cliff.coast.points:
		nearest_edge = minf(nearest_edge, point.distance_to(Vector2(clampf(point.x, lot.position.x, lot.end.x), clampf(point.y, lot.position.y, lot.end.y))))
	assert_true(nearest_edge >= NeighbourhoodCliff.EDGE_MIN - 0.01, "the drop is never nearer the lot than %.1f m (%.2f)" % [NeighbourhoodCliff.EDGE_MIN, nearest_edge])
	var nearest_rail: float = INF
	for point: Vector2 in cliff.rail_points:
		assert_false(lot.has_point(point), "no rail post on the lot")
		nearest_rail = minf(nearest_rail, point.distance_to(Vector2(clampf(point.x, lot.position.x, lot.end.x), clampf(point.y, lot.position.y, lot.end.y))))
		assert_true(cliff.coast.signed(point) < 0.0, "the rail stands on the top, inside the edge")
	assert_true(nearest_rail > 1.0, "the rail stays well outside the maximum lot (%.2f)" % nearest_rail)
	# The edge runs behind the lot and along one side; the door's side is open land.
	var behind: bool = false
	var beside: bool = false
	for point: Vector2 in cliff.rail_points:
		behind = behind or point.y < lot.position.y
		beside = beside or point.x > lot.end.x and point.y > lot.position.y and point.y < lot.end.y
	assert_true(behind and beside, "the rail runs behind the lot and along its side")
	assert_true(cliff.coast.signed(Vector2(cliff.door.get_center().x, lot.end.y + 3.0)) < -2.0, "the door looks out over land, up the path")
	_free(dressing)


func test_the_cliff_is_the_same_every_build_and_frame() -> void:
	await _host()
	var first: NeighbourhoodDressing = _dressing(load(CLIFF) as StreetPreset)
	var a: String = _digest(first)
	first.set_review_time(31.5)
	var cliff: NeighbourhoodCliff = first.cliff()
	var pose: String = var_to_str([cliff.gull_pose(0, 31.5), cliff.boat_pose(31.5), cliff.gulls[1].transform, cliff.boat.transform,
		cliff.beam.transform])
	first.set_review_time(80.0)
	first.set_review_time(31.5)
	assert_eq(var_to_str([cliff.gull_pose(0, 31.5), cliff.boat_pose(31.5), cliff.gulls[1].transform, cliff.boat.transform,
		cliff.beam.transform]), pose, "the same time shows the same frame")
	for line: String in NeighbourhoodCliff.SEA_SHADER.code.split("\n"):
		assert_false(line.get_slice("//", 0).contains("TIME"), "the sea moves on the street clock only")
	_free(first)
	NeighbourhoodDressing.clear_mesh_cache()
	var second: NeighbourhoodDressing = _dressing(load(CLIFF) as StreetPreset)
	assert_eq(_digest(second), a, "the cliff is laid out the same way every time (no randomness)")
	_free(second)


func test_the_seaside_cliff_lot_stands_on_the_cliff() -> void:
	var lot: LotDef = load(LOT) as LotDef
	assert_eq(lot.street_preset, CLIFF)
	assert_eq(String(StreetPreset.for_lot(lot).id), "cliff")
	assert_true(lot.blurb.contains("cliff path") and lot.blurb.contains("terrace"), "the blurb names the path and the terrace")
	assert_eq(String(load("res://data/lots/seaside_cliff.tres").get("street_preset")), CLIFF)
	var promenade: StreetPreset = load("res://data/streets/promenade.tres") as StreetPreset
	assert_null(promenade.cliff, "the promenade stays the boardwalk's")


func test_the_whitewash_finish_and_the_cliff_default() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var whitewash: WallStyleDef = content.wall_style(&"whitewash")
	assert_not_null(whitewash, "a whitewash wall finish exists (#380)")
	assert_eq(int(whitewash.pattern), WallStyleDef.Pattern.WHITEWASH)
	assert_eq(int(WallStyleDef.Pattern.WHITEWASH), 8, "appended, never renumbered")
	assert_eq(int(WallStyleDef.Pattern.CONCRETE), 7)
	assert_true(whitewash.price > 0 and whitewash.unlock_level > 1, "a priced finish on other lots, bought later")
	assert_not_null(content.swatch(whitewash.default_swatch), "in a palette colour")
	assert_not_null(content.swatch(whitewash.default_accent), "with a palette colour plinth")
	assert_eq((load(CLIFF) as StreetPreset).wall_style, &"whitewash", "the cliff café is a whitewashed cottage")
	var main: Color = content.swatch(whitewash.default_swatch).color
	var plinth: Color = content.swatch(whitewash.default_accent).color
	var card: Image = WallThumbnail.image(int(whitewash.pattern), main, plinth)
	var plain: Image = WallThumbnail.image(int(WallStyleDef.Pattern.PAINT), main, plinth)
	assert_ne(card.get_data(), plain.get_data(), "the card is not plain paint")
	var low: Color = WallThumbnail.colour(int(whitewash.pattern), Vector2(0.3, 0.05), main, plinth)
	var high: Color = WallThumbnail.colour(int(whitewash.pattern), Vector2(0.3, 0.4), main, plinth)
	assert_true(low.get_luminance() < high.get_luminance() - 0.3, "a dark tarred plinth under the white wash")


func test_the_other_streets_are_unchanged() -> void:
	await _host()
	for path: String in DIGESTS:
		var dressing: NeighbourhoodDressing = _dressing(load(path) as StreetPreset)
		assert_eq(dressing.build_error, "")
		assert_false(dressing.has_cliff())
		assert_null(dressing.cliff())
		assert_eq(_digest(dressing), DIGESTS[path], "%s builds exactly what it did before the cliff" % path)
		_free(dressing)
		NeighbourhoodDressing.clear_mesh_cache()
