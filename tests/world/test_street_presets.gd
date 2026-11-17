extends TestCase
## Street presets (#425): every lot's street loads and is valid, the starter
## street is data, a second preset changes the building set, palette, props and
## ground with no code, and the view builds the active site's street.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const MAIN: PackedScene = preload("res://src/world/main.tscn")
## A test-only second street: one blue shop a side, three flat-roofed houses,
## a single bench and a sandy ground with no meadow trees.
const ALT: String = "res://tests/fixtures/streets/test_alt.tres"
const SEASIDE: String = "res://data/streets/seaside.tres"
const PROMENADE: String = "res://data/streets/promenade.tres"
const STREETS: String = "res://data/streets/"
const LOTS: String = "res://data/lots/"
const RESERVE: Rect2i = Rect2i(-2, -2, 12, 9)

var _viewport: SubViewport
var _main: Node
var _lot: LotDef
var _lot_preset: String = ""


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	if _lot != null:
		_lot.street_preset = _lot_preset
		_lot = null
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	NeighbourhoodDressing.clear_mesh_cache()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _files(dir: String) -> Array[String]:
	var paths: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			paths.append(dir + file)
	paths.sort()
	return paths


func test_every_street_preset_is_valid_and_named_for_its_file() -> void:
	var paths: Array[String] = _files(STREETS)
	assert_true(paths.has(StreetPreset.STARTER), "the starter street is data")
	for path: String in paths:
		var preset: StreetPreset = load(path) as StreetPreset
		assert_not_null(preset, "%s is a street preset" % path)
		if preset == null:
			continue
		assert_eq(preset.errors(), PackedStringArray(), path)
		assert_eq(String(preset.id), path.get_file().get_basename(), "the id matches the file")


func test_every_lot_stands_on_a_valid_street() -> void:
	var lots: Array[String] = _files(LOTS)
	assert_true(lots.size() >= 3)
	for path: String in lots:
		var lot: LotDef = load(path) as LotDef
		var preset: StreetPreset = StreetPreset.for_lot(lot)
		assert_not_null(preset, "%s has a street" % lot.id)
		assert_eq(preset.errors(), PackedStringArray(), "%s's street is valid" % lot.id)
		if not lot.street_preset.is_empty():
			assert_true(ResourceLoader.exists(lot.street_preset), "%s names a preset that exists" % lot.id)
			assert_true(preset == load(lot.street_preset), "%s gets the preset it names" % lot.id)
		else:
			assert_true(preset == StreetPreset.starter(), "%s has none yet: the starter street" % lot.id)
	assert_eq(load(LOTS + "town_fixer_upper.tres").street_preset, StreetPreset.STARTER, "a town lot names the starter street")


func test_the_home_lot_and_a_missing_preset_fall_back_to_the_starter_street() -> void:
	var starter: StreetPreset = StreetPreset.starter()
	assert_true(StreetPreset.for_lot(null) == starter, "the home lot")
	assert_true(StreetPreset.for_lot(LotDef.new()) == starter, "a lot without a preset")
	assert_true(StreetPreset.from_path("res://data/streets/no_such_street.tres") == starter, "a missing file")
	assert_true(StreetPreset.for_site(SiteBook.new(), null) == starter, "no content")


func test_the_standard_parts_are_copies_of_the_starter_preset() -> void:
	var starter: StreetPreset = StreetPreset.starter()
	assert_eq(StreetSet.standard().signature(), starter.buildings.signature())
	assert_eq(GroundSkin.standard().signature(), starter.ground.signature())
	var copy: StreetSet = StreetSet.standard()
	copy.seed_salt = 99
	copy.shops[0].wall = Color.BLACK
	assert_eq(starter.buildings.seed_salt, 7, "changing a copy leaves the starter street alone")
	assert_ne(starter.buildings.shops[0].wall, Color.BLACK)


func test_a_preset_missing_a_part_is_refused() -> void:
	var broken: StreetPreset = (load(ALT) as StreetPreset).duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as StreetPreset
	broken.buildings.roof_colors = []
	broken.buildings.house_roofs = [99] as Array[int]
	broken.ground = null
	var errors: String = ", ".join(broken.errors())
	assert_true(errors.contains("roof_colors"), errors)
	assert_true(errors.contains("unknown roof shape 99"), errors)
	assert_true(errors.contains("no ground"), errors)


func test_content_refuses_a_lot_whose_street_does_not_exist() -> void:
	var lot: LotDef = (load(LOTS + "seaside_cliff.tres") as LotDef).duplicate() as LotDef
	var types: Array[StringName] = []
	for kind: StringName in lot.guest_mix:
		types.append(kind)
	var items: Array[ItemDef] = []
	for item_path: String in _files("res://data/items/"):
		items.append(load(item_path) as ItemDef)
	var lots: Array[LotDef] = [lot]
	assert_eq(ContentDB.validate_lots(lots, items, types), PackedStringArray(), "the lot is otherwise valid")
	lot.street_preset = "res://data/streets/no_such_street.tres"
	var errors: String = ", ".join(ContentDB.validate_lots(lots, items, types))
	assert_true(errors.contains("street preset"), errors)


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


func _ground_colors(dressing: NeighbourhoodDressing) -> Dictionary[Color, bool]:
	var colours: Dictionary[Color, bool] = {}
	var meadow: MeshInstance3D = dressing.ground_root.get_child(0) as MeshInstance3D
	for colour: Color in meadow.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		colours[colour] = true
	return colours


func _free(dressing: NeighbourhoodDressing) -> void:
	dressing.get_parent().remove_child(dressing)
	dressing.free()


func test_a_second_preset_restyles_the_street_with_no_code() -> void:
	await _host()
	var alt: StreetPreset = load(ALT) as StreetPreset
	assert_eq(alt.errors(), PackedStringArray())
	var starter: NeighbourhoodDressing = _dressing(StreetPreset.starter())
	var other: NeighbourhoodDressing = _dressing(alt)
	assert_eq(starter.build_error, "")
	assert_eq(other.build_error, "")
	assert_true(other.preset == alt and other.street_set == alt.buildings and other.ground_skin == alt.ground)
	# Building set: one shop each side and three houses.
	var buildings: Node3D = other.find_child("Buildings", true, false) as Node3D
	assert_eq(buildings.get_child_count(), 1 * 2 + 3, "the preset's shops and houses")
	assert_eq((starter.find_child("Buildings", true, false) as Node3D).get_child_count(), 2 * 2 + 5)
	# Palette: the houses and shops wear only the preset's colours and shapes.
	var builder: NeighbourhoodBuildings = NeighbourhoodBuildings.new()
	builder.street = other.street_set
	builder.local_reserve = AABB(Vector3(-5.0, 0.0, -12.5), Vector3(12.0, 1.4, 12.5))
	builder.plan()
	assert_eq(builder.plans.size(), 5)
	for plan: NeighbourhoodBuildings.Plan in builder.plans:
		if plan.is_shop:
			assert_eq(plan.style.id, &"test_blue_shop")
			assert_eq(plan.roof, StreetSet.Roof.FLAT)
		else:
			assert_eq(plan.wall, alt.buildings.wall_colors[0])
			assert_eq(plan.roof, StreetSet.Roof.SHED)
			assert_eq(plan.fence, StreetSet.Fence.RAIL)
		assert_eq(plan.roof_col, alt.buildings.roof_colors[0])
	# Props: just the one bench.
	var plan: Array[Dictionary] = other.furniture_plan()
	assert_eq(plan.size(), 1)
	assert_eq(plan[0]["kind"], StreetPropSpec.Kind.BENCH)
	assert_true(starter.furniture_plan().size() > 1)
	# Ground: the meadow takes the preset's colours, none of the starter's.
	var sandy: Dictionary[Color, bool] = _ground_colors(other)
	var meadow: Dictionary[Color, bool] = _ground_colors(starter)
	var shared: int = 0
	for colour: Color in sandy:
		if meadow.has(colour):
			shared += 1
	assert_true(sandy.size() > 0 and shared < sandy.size(), "the ground is recoloured (%d of %d shared)" % [shared, sandy.size()])
	_free(starter)
	_free(other)


func test_the_view_builds_the_active_sites_street() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	var view: ShopView = _main.get_node("ShopView") as ShopView
	assert_true(view.street_preset == StreetPreset.starter(), "the home site is on the starter street")
	assert_true(view.neighbourhood_dressing.preset == StreetPreset.starter())
	var content: ContentDB = _main.get("content")
	_lot = content.lot(&"town_fixer_upper")
	_lot_preset = _lot.street_preset
	_lot.street_preset = ALT
	var book: SiteBook = _main.get("site_book")
	var sections: Dictionary = SaveSystem.capture_sections(SiteSections.PER_SITE)
	assert_true(book.add_site(&"second", &"town_fixer_upper", "Second", Clock.sim.day, sections))
	assert_true(_main.call("switch_site", &"second"))
	var alt: StreetPreset = load(ALT) as StreetPreset
	assert_true(view.street_preset == alt, "the second site's lot names its street")
	assert_true(view.neighbourhood_dressing.preset == alt)
	assert_true(view.neighbourhood_dressing.street_set == alt.buildings)
	assert_eq(view.neighbourhood_dressing.furniture_plan().size(), 1, "built from the second street's props")
	assert_true(_main.call("switch_site", SiteBook.HOME_ID))
	assert_true(view.street_preset == StreetPreset.starter(), "back home, back on the starter street")
	assert_true(view.neighbourhood_dressing.street_set == StreetPreset.starter().buildings)


func test_the_boardwalk_lot_stands_on_the_promenade() -> void:
	var lot: LotDef = load(LOTS + "beachfront_boardwalk.tres") as LotDef
	var cliff: LotDef = load(LOTS + "seaside_cliff.tres") as LotDef
	assert_eq(cliff.street_preset, SEASIDE)
	assert_eq(lot.street_preset, PROMENADE)
	var promenade: StreetPreset = StreetPreset.for_lot(lot)
	assert_eq(promenade.id, &"promenade")
	assert_false(promenade.has_traffic(), "a car-free front")
	assert_not_null(promenade.shore, "the beach stays behind the shop")


func test_the_seaside_road_street() -> void:
	var seaside: StreetPreset = load(SEASIDE) as StreetPreset
	assert_true(seaside != StreetPreset.starter(), "it is not the starter street")
	assert_eq(seaside.id, &"seaside")
	assert_eq(seaside.errors(), PackedStringArray())
	# Boardwalk ground, sea-blue and rope tan accents, and its own props.
	assert_true(seaside.ground.pavement.a > 0.0 and seaside.ground.plank_seam.a > 0.0, "a boardwalk")
	var kinds: Dictionary[int, bool] = {}
	for spec: StreetPropSpec in seaside.buildings.furniture:
		kinds[int(spec.kind)] = true
	for kind: int in [StreetPropSpec.Kind.ROPE_BOLLARD, StreetPropSpec.Kind.LIFEBUOY, StreetPropSpec.Kind.CATCH_CRATES,
			StreetPropSpec.Kind.BUNTING]:
		assert_true(kinds.has(kind), "the seaside street sets out prop kind %d" % kind)
	for kind: int in [StreetPropSpec.Kind.TREE_PLANTER, StreetPropSpec.Kind.BIKE_RACK, StreetPropSpec.Kind.HYDRANT,
			StreetPropSpec.Kind.BUS_STOP, StreetPropSpec.Kind.POSTBOX]:
		assert_false(kinds.has(kind), "no town furniture (kind %d) on the seaside street" % kind)
	assert_true(seaside.buildings.birds > 0, "gulls")
	assert_true(seaside.buildings.wall_colors != StreetPreset.starter().buildings.wall_colors, "its own palette")


func test_the_starter_street_has_no_boardwalk() -> void:
	var skin: GroundSkin = StreetPreset.starter().ground
	assert_eq(skin.pavement.a, 0.0, "the starter paving keeps the shared grey")
	assert_eq(skin.plank_seam.a, 0.0, "the starter paving has no seams")
	for spec: StreetPropSpec in StreetPreset.starter().buildings.furniture:
		assert_true(int(spec.kind) <= int(StreetPropSpec.Kind.POSTBOX), "the starter street keeps its original props")


func test_every_prop_kind_has_a_size_and_a_mesh() -> void:
	for kind: int in StreetPropSpec.Kind.values():
		var size: Vector3 = StreetPropSpec.size_of(kind as StreetPropSpec.Kind)
		assert_true(size.x > 0.0 and size.y > 0.0 and size.z > 0.0, "kind %d has a footprint" % kind)
	var street: StreetSet = (load(SEASIDE) as StreetPreset).buildings
	var planner: NeighbourhoodFurniture = NeighbourhoodFurniture.new()
	planner.street = street
	planner.lot_u = Vector2(0.0, 6.0)
	planner.u_range = Vector2(-18.0, 24.0)
	planner.plan()
	var seen: Dictionary[int, bool] = {}
	for item: NeighbourhoodFurniture.Placed in planner.placed:
		seen[item.kind] = true
		assert_true(item.rect().position.y >= NeighbourhoodFurniture.BAND_LO - 0.001 and item.rect().end.y <= NeighbourhoodFurniture.BAND_HI + 0.001,
			"props stay in the pavement band, off the walking lane")
		assert_false(item.rect().intersects(Rect2(-0.5, -2.0, 7.0, NeighbourhoodFurniture.BAND_HI + 3.0)), "none stands in front of the lot")
	assert_eq(seen.size(), 6, "every kind the seaside street asks for finds a place: %s" % str(seen.keys()))
	var meshes: Array[MeshInstance3D] = planner.build_meshes(0.055, 0.0, Vector2(0.3, 0.3), [] as Array[Vector2])
	assert_not_null(meshes[0].mesh, "the props are meshed")
	assert_not_null(meshes[1].mesh, "and have contact shadows")
	for mesh: MeshInstance3D in meshes:
		mesh.free()


func test_the_seaside_street_lays_a_boardwalk_and_the_starter_street_does_not() -> void:
	await _host()
	var seaside: NeighbourhoodDressing = _dressing(load(SEASIDE) as StreetPreset)
	var starter: NeighbourhoodDressing = _dressing(StreetPreset.starter())
	assert_eq(seaside.build_error, "")
	assert_not_null(seaside.find_child("PlankSeams", true, false), "boardwalk seams")
	assert_null(starter.find_child("PlankSeams", true, false), "the starter street has none")
	var kinds: Dictionary[int, bool] = {}
	for entry: Dictionary in seaside.furniture_plan():
		kinds[int(entry["kind"])] = true
	assert_true(kinds.has(int(StreetPropSpec.Kind.ROPE_BOLLARD)) and kinds.has(int(StreetPropSpec.Kind.CATCH_CRATES)),
		"the seaside props are on the street")
	# Every kind the preset asks for is placed on the real dressing, so a dropped
	# lifebuoy or bunting fails here.
	for spec: StreetPropSpec in (load(SEASIDE) as StreetPreset).buildings.furniture:
		assert_true(kinds.has(int(spec.kind)), "the real seaside dressing places prop kind %d" % int(spec.kind))
	_free(seaside)
	_free(starter)
