extends TestCase
## Back gardens, softer roofs, the toy and pet shops and the lit windows of the street
## (#440): every garden stays inside its own lot, off the hedges, the doorstep and the lanes
## at every seed and shift; the business set swaps the laundromat for a toy shop and adds a pet
## shop; windows are lit at night and dark by day, some going dark late; all of it is
## deterministic and cheap.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const MAIN: PackedScene = preload("res://src/world/main.tscn")
## Local street frame, as in the buildings test: the maximum lot, 12 m by 12.5 m.
const RESERVE: AABB = AABB(Vector3(-5.0, 0.0, -12.5), Vector3(12.0, 1.4, 12.5))
const SALTS: Array[int] = [7, 11, 23, 99, 1234, 5, 8, 13, 42, 77, 301, 9001]
const HEDGE_HALF: float = 0.15

var _viewport: SubViewport
var _main: Node3D


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	NeighbourhoodDressing.clear_mesh_cache()
	Clock.set_speed(0)
	GameState.new_run(1)


func _builder(salt: int = 7, shift: float = 0.0) -> NeighbourhoodBuildings:
	var builder: NeighbourhoodBuildings = NeighbourhoodBuildings.new()
	builder.street = StreetSet.standard()
	builder.street.seed_salt = salt
	builder.local_reserve = AABB(RESERVE.position + Vector3(0.0, 0.0, shift), RESERVE.size)
	builder.shift = shift
	builder.plan()
	return builder


func _houses(builder: NeighbourhoodBuildings) -> Array[NeighbourhoodBuildings.Plan]:
	var houses: Array[NeighbourhoodBuildings.Plan] = []
	for p: NeighbourhoodBuildings.Plan in builder.plans:
		if not p.is_shop:
			houses.append(p)
	return houses


func _overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x - 0.0001 and a.end.x > b.position.x + 0.0001 \
		and a.position.y < b.end.y - 0.0001 and a.end.y > b.position.y + 0.0001


# --- gardens ------------------------------------------------------------------

func test_gardens_stay_inside_their_lots_off_the_hedges_the_doorstep_and_the_lanes() -> void:
	var total: int = 0
	for shift: float in [0.0, 2.0]:
		for salt: int in SALTS:
			var builder: NeighbourhoodBuildings = _builder(salt, shift)
			# The back lane runs behind the shop's own block, on the far side of the shop from the houses.
			var lane_top: float = shift - RESERVE.size.z - 3.1 + 0.62
			for p: NeighbourhoodBuildings.Plan in _houses(builder):
				var lot: Rect2 = p.lot
				var id: String = "salt %d shift %.0f %s" % [salt, shift, p.id]
				var hedges: Array[Rect2] = [
					Rect2(lot.position.x - HEDGE_HALF, lot.position.y, HEDGE_HALF * 2.0, lot.size.y),
					Rect2(lot.end.x - HEDGE_HALF, lot.position.y, HEDGE_HALF * 2.0, lot.size.y),
					Rect2(lot.position.x, lot.end.y - HEDGE_HALF, lot.size.x, HEDGE_HALF * 2.0)]
				var zone: Rect2 = p.garden_zone
				assert_true(lot.encloses(zone), "%s: the garden ground is inside the lot" % id)
				var back_wall: float = p.xf.origin.z + p.depth
				assert_true(zone.position.y >= back_wall, "%s: the garden is behind the house, not beside or in front of it" % id)
				assert_true(zone.position.y > lane_top + 10.0, "%s: the garden is nowhere near the back lane" % id)
				assert_true(p.garden.size() >= 2, "%s: a garden has something in it" % id)
				for index: int in p.garden.size():
					var rect: Rect2 = p.garden[index]["rect"]
					total += 1
					assert_true(zone.encloses(rect), "%s: %s stays in the garden ground" % [id, p.garden[index]["kind"]])
					assert_false(_overlaps(rect, p.doorstep), "%s: the doorstep stays clear" % id)
					assert_false(_overlaps(rect, Rect2(p.bounds.position.x, p.bounds.position.z, p.bounds.size.x, p.bounds.size.z)),
						"%s: nothing stands in the house" % id)
					for hedge: Rect2 in hedges:
						assert_false(_overlaps(rect, hedge), "%s: nothing stands in a hedge" % id)
					for other: int in range(index + 1, p.garden.size()):
						assert_false(_overlaps(rect, p.garden[other]["rect"]), "%s: garden things do not overlap" % id)
				# Every vertex of the house's yard, gardens included, stays on its lot (the path runs on to the pavement).
				var mesh: MeshInstance3D = builder.build_mesh(p)
				for point: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					assert_true(point.z <= lot.end.y + 0.2 and point.x >= lot.position.x - 0.2 and point.x <= lot.end.x + 0.2,
						"%s: the whole yard stays on its lot" % id)
				mesh.free()
	assert_true(total > 150, "plenty of garden things were checked: %d" % total)


func test_the_gardens_are_varied_across_the_street_and_a_set_of_cosy_things() -> void:
	var builder: NeighbourhoodBuildings = _builder()
	var kinds: Dictionary[int, bool] = {}
	var signatures: Dictionary[String, bool] = {}
	for p: NeighbourhoodBuildings.Plan in _houses(builder):
		var own: Array[int] = []
		for item: Dictionary in p.garden:
			kinds[int(item["kind"])] = true
			own.append(int(item["kind"]))
		own.sort()
		signatures[str(own)] = true
	assert_true(kinds.size() >= 5, "the five gardens use a mixed set of things: %d kinds" % kinds.size())
	assert_eq(signatures.size(), 5, "no two gardens hold the same set")
	var play: bool = kinds.has(NeighbourhoodBuildings.Garden.SWING) or kinds.has(NeighbourhoodBuildings.Garden.SLIDE)
	var homely: bool = kinds.has(NeighbourhoodBuildings.Garden.VEG) or kinds.has(NeighbourhoodBuildings.Garden.BORDER) \
		or kinds.has(NeighbourhoodBuildings.Garden.TREE)
	assert_true(play and homely, "a play set and growing things both appear")
	# No ponds or pools, and nothing the plan can name that is water.
	for kind: int in kinds:
		assert_true(kind != -1)


func test_garden_plans_and_meshes_are_deterministic_and_the_salt_changes_them() -> void:
	var first: NeighbourhoodBuildings = _builder()
	var second: NeighbourhoodBuildings = _builder()
	var differs: bool = false
	var other: NeighbourhoodBuildings = _builder(11)
	for index: int in first.plans.size():
		assert_eq(first.plans[index].garden, second.plans[index].garden, "the same inputs plan the same garden")
		if not first.plans[index].is_shop:
			differs = differs or first.plans[index].garden != other.plans[index].garden
			var a: MeshInstance3D = first.build_mesh(first.plans[index])
			var b: MeshInstance3D = second.build_mesh(second.plans[index])
			assert_eq(a.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], b.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
			a.free()
			b.free()
	assert_true(differs, "a different seed salt grows different gardens")
	# The lit-window meshes are as repeatable.
	var glow_a: Array[ArrayMesh] = first.glow_meshes()
	var glow_b: Array[ArrayMesh] = second.glow_meshes()
	assert_eq(glow_a.size(), glow_b.size())
	for tier: int in glow_a.size():
		assert_eq(glow_a[tier] == null, glow_b[tier] == null)
		if glow_a[tier] != null:
			assert_eq(glow_a[tier].surface_get_arrays(0)[Mesh.ARRAY_VERTEX], glow_b[tier].surface_get_arrays(0)[Mesh.ARRAY_VERTEX])


func test_garden_shadows_sit_on_the_lawn_and_new_set_fields_are_in_the_cache_key() -> void:
	var builder: NeighbourhoodBuildings = _builder()
	builder.lawn_shadow = Color(0.1, 0.2, 0.3)
	var house: NeighbourhoodBuildings.Plan = _houses(builder)[0]
	var mesh: MeshInstance3D = builder.build_mesh(house)
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var shadow_vertices: int = 0
	for index: int in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		var point: Vector3 = arrays[Mesh.ARRAY_VERTEX][index]
		if is_equal_approx(point.y, NeighbourhoodBuildings.GARDEN_SHADOW_Y):
			shadow_vertices += 1
			var tone: Color = arrays[Mesh.ARRAY_COLOR][index]
			assert_true(absf(tone.r - builder.lawn_shadow.r) < 0.01 and absf(tone.g - builder.lawn_shadow.g) < 0.01 and absf(tone.b - builder.lawn_shadow.b) < 0.01, "a baked garden shadow takes the lawn's shadow tone")
			assert_true(house.garden_zone.grow(0.11).has_point(Vector2(point.x, point.z)), "garden shadows stay in the garden")
	assert_true(shadow_vertices >= 12, "the garden things stand on baked contact shadows: %d" % shadow_vertices)
	mesh.free()
	var base: String = StreetSet.standard().signature()
	var tweaks: Array[StreetSet] = []
	for index: int in 4:
		tweaks.append(StreetSet.standard())
	tweaks[0].soil = Color.RED
	tweaks[1].laundry_colors = [Color.RED]
	tweaks[2].play_colors = [Color.RED]
	tweaks[3].window_glows = [Color.RED]
	for set: StreetSet in tweaks:
		assert_ne(set.signature(), base, "every new street field is part of the cache key")


# --- roofs and businesses ------------------------------------------------------------

func test_roofs_are_soft_pastel_and_neighbours_never_share_a_roof_colour() -> void:
	var set: StreetSet = StreetSet.standard()
	assert_true(set.roof_colors.size() >= 6)
	for colour: Color in set.roof_colors:
		assert_true(colour.s <= 0.5 and colour.v >= 0.62, "a gentle, light roof tone: s %.2f v %.2f" % [colour.s, colour.v])
	for salt: int in SALTS:
		var builder: NeighbourhoodBuildings = _builder(salt)
		var previous: NeighbourhoodBuildings.Plan = null
		for p: NeighbourhoodBuildings.Plan in builder.plans:
			# Shops share a row per side (two each), houses share one row; a row's neighbours differ.
			if previous != null and previous.is_shop == p.is_shop and (not p.is_shop or p.id != "Shop2"):
				assert_ne(previous.roof_col, p.roof_col, "salt %d: %s and %s have different roofs" % [salt, previous.id, p.id])
			previous = p


func test_the_business_set_has_a_toy_shop_and_a_pet_shop_and_no_laundromat() -> void:
	var set: StreetSet = StreetSet.standard()
	var ids: Array[StringName] = []
	for style: ShopStyle in set.shops:
		ids.append(style.id)
	assert_true(ids.has(&"toy_shop"), "a toy shop")
	assert_true(ids.has(&"pet_shop"), "a pet shop")
	assert_false(ids.has(&"laundromat"), "the laundromat is gone")
	assert_eq(set.shops_per_side, 2)
	assert_eq(set.house_count, 5)
	var accents: Dictionary[int, bool] = {}
	for style: ShopStyle in set.shops:
		assert_false(accents.has(int(style.accent)) and style.accent != ShopStyle.Accent.CRATE, "each business sets out its own thing")
		accents[int(style.accent)] = true
	assert_false(accents.has(int(ShopStyle.Accent.PORTHOLE)), "no portholes without the laundromat")
	assert_true(accents.has(int(ShopStyle.Accent.TOYS)) and accents.has(int(ShopStyle.Accent.PETS)))
	# The first street shows both (2 + 2 shops, 5 houses) and every salt keeps that density.
	var builder: NeighbourhoodBuildings = _builder()
	var placed: Array[StringName] = []
	for p: NeighbourhoodBuildings.Plan in builder.plans:
		if p.is_shop:
			placed.append(p.style.id)
	assert_eq(placed.size(), 4)
	assert_true(placed.has(&"toy_shop") and placed.has(&"pet_shop"), "the default street stands both new shops: %s" % str(placed))
	for salt: int in SALTS:
		assert_eq(_builder(salt).plans.size(), 9)
	# Each new shop draws its window display and the thing out front without leaving its bounds.
	for p: NeighbourhoodBuildings.Plan in builder.plans:
		if p.is_shop and (p.style.accent == ShopStyle.Accent.TOYS or p.style.accent == ShopStyle.Accent.PETS):
			var mesh: MeshInstance3D = builder.build_mesh(p)
			var box: AABB = AABB((mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0], Vector3.ZERO)
			for point: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				box = box.expand(point)
			assert_true(p.bounds.grow(0.2).encloses(box), "%s's window and front stay in its bounds" % p.style.id)
			mesh.free()


func test_the_whole_street_stays_a_modest_number_of_triangles_and_draw_calls() -> void:
	var builder: NeighbourhoodBuildings = _builder()
	var triangles: int = 0
	var draws: int = 0
	for p: NeighbourhoodBuildings.Plan in builder.plans:
		var mesh: MeshInstance3D = builder.build_mesh(p)
		triangles += (mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		draws += mesh.mesh.get_surface_count()
		mesh.free()
	var windows: int = 0
	for mesh: ArrayMesh in builder.glow_meshes():
		if mesh != null:
			windows += (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			draws += 1
	assert_true(triangles > 6000 and triangles < 18000, "the buildings with their gardens: %d triangles" % triangles)
	assert_true(windows > 100 and windows < 600, "the lit windows are a few hundred triangles: %d" % windows)
	assert_eq(draws, 9 + 3, "one draw per building plus at most three lit-window meshes")


# --- lit windows -------------------------------------------------------------------

func _host() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)


func _grid() -> SimGrid:
	var base: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"########", "#......#", "#......#", "#......#", "#......#", "#......#", "###..###", "   EE   "]))
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	for cell: Vector2i in base.cells():
		grid.set_terrain(cell, base.terrain(cell))
	return grid


func _dressing(salt: int = 7) -> NeighbourhoodDressing:
	var grid: SimGrid = _grid()
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	var set: StreetSet = StreetSet.standard()
	set.seed_salt = salt
	dressing.street_set = set
	dressing.configure(grid, Rect2i(-2, -2, 12, 9), [{"cells": grid.entries().duplicate(), "normal": Vector2i.DOWN}] as Array[Dictionary],
		[] as Array[AABB])
	return dressing


func _free_dressing(dressing: NeighbourhoodDressing) -> void:
	dressing.get_parent().remove_child(dressing)
	dressing.free()


func test_windows_are_lit_at_night_dark_by_day_and_a_few_go_dark_late() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing()
	var day: Dictionary = dressing.window_state()
	assert_true(day["quads"] > 40, "the street has lit-window quads to show: %d" % day["quads"])
	assert_eq(day["night"], 0.0)
	for tier: Dictionary in day["tiers"]:
		assert_false(tier["visible"], "tier %d windows are hidden by day" % tier["tier"])
		assert_eq(tier["energy"], 0.0, "no glow by day")
	dressing.set_night(1.0)
	var evening: Dictionary = dressing.window_state()
	assert_eq(evening["tiers"].size(), 3, "three light tiers")
	for tier: Dictionary in evening["tiers"]:
		assert_true(tier["visible"], "tier %d is lit in the evening" % tier["tier"])
		assert_true(tier["energy"] > 0.1)
	dressing.set_night(1.0, 1.0)
	var late: Dictionary = dressing.window_state()
	var still_lit: int = 0
	var went_dark: int = 0
	for tier: Dictionary in late["tiers"]:
		if tier["visible"]:
			still_lit += tier["quads"]
		else:
			went_dark += tier["quads"]
	assert_true(went_dark > 0, "a few windows go dark late at night")
	assert_true(still_lit > went_dark, "most stay lit: %d lit, %d dark" % [still_lit, went_dark])
	assert_true(float(went_dark) / float(still_lit + went_dark) < 0.4, "only a few go dark")
	dressing.set_night(0.5, 0.0)
	assert_true(dressing.window_state()["tiers"][0]["energy"] < evening["tiers"][0]["energy"], "dusk is in between")
	dressing.set_night(0.0, 1.0)
	for tier: Dictionary in dressing.window_state()["tiers"]:
		assert_false(tier["visible"], "dark by day whatever the lateness")
	for node: Node in dressing.find_children("*", "Light3D", true, false):
		assert_true(false, "windows are emissive meshes, never %s" % node.name)
	for node: Node in dressing.find_children("WindowGlow*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		var material: BaseMaterial3D = mesh.material_override as BaseMaterial3D
		assert_true(material.emission_enabled, "a lit window is emissive")
	_free_dressing(dressing)


func test_which_windows_are_lit_is_a_hash_of_the_street_and_survives_a_rebuild() -> void:
	await _host()
	var first: NeighbourhoodDressing = _dressing()
	var second: NeighbourhoodDressing = _dressing()
	assert_eq(first.window_state()["quads"], second.window_state()["quads"])
	var other: NeighbourhoodDressing = _dressing(99)
	var counts: Array[int] = []
	for tier: Dictionary in first.window_state()["tiers"]:
		counts.append(tier["quads"])
	var other_counts: Array[int] = []
	for tier: Dictionary in other.window_state()["tiers"]:
		other_counts.append(tier["quads"])
	assert_ne(counts, other_counts, "a different salt lights a different set of windows")
	# A rebuild keeps the night and the cached meshes serve the same windows again.
	first.set_night(1.0, 0.0)
	var before: Dictionary = first.window_state()
	first.rebuild()
	assert_eq(first.window_state()["quads"], before["quads"])
	var salted: StreetSet = StreetSet.standard()
	salted.seed_salt = 5
	first.street_set = salted
	first.rebuild()
	assert_true(first.window_state()["tiers"][0]["visible"], "the new street's windows are lit at once")
	first.street_set = StreetSet.standard()
	first.rebuild()
	assert_eq(first.window_state()["quads"], before["quads"], "going back restores the same windows")
	_free_dressing(first)
	_free_dressing(second)
	_free_dressing(other)


func test_main_lights_the_windows_from_the_clock_and_darkens_some_late() -> void:
	var midday: float = 780.0
	var evening: float = 1290.0
	var late: float = 1410.0
	assert_eq(DayNightView.street_late(midday), 0.0)
	assert_true(DayNightView.street_late(evening) > 0.0 and DayNightView.street_late(evening) < 1.0)
	assert_eq(DayNightView.street_late(late), 1.0)
	await _host()
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	_main.set("owner_creation_requested", false)
	_viewport.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	_main.set_process(false)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var world: SimWorld = _main.get("world") as SimWorld
	var dressing: NeighbourhoodDressing = (_main.get_node("ShopView") as ShopView).neighbourhood_dressing
	assert_not_null(dressing)
	world.clock.phase = SimClock.Phase.MORNING
	_main.call("refresh_presentation")
	for tier: Dictionary in dressing.window_state()["tiers"]:
		assert_false(tier["visible"], "windows are dark in the morning")
	world.clock.phase = SimClock.Phase.OPEN
	world.clock.phase_tick = world.clock.open_ticks / 2
	_main.call("refresh_presentation")
	for tier: Dictionary in dressing.window_state()["tiers"]:
		assert_false(tier["visible"], "windows are dark at midday")
	world.clock.phase = SimClock.Phase.CLOSED
	world.clock.phase_tick = 0
	_main.call("refresh_presentation")
	var closed: Dictionary = dressing.window_state()
	assert_eq(closed["night"], 1.0, "the same level as the lamps")
	assert_eq(closed["night"], dressing.lamp_state()["night"])
	assert_true(closed["tiers"][0]["visible"], "windows are lit once the shop has closed")
	assert_true(closed["late"] > 0.9)
	var dark: int = 0
	for tier: Dictionary in closed["tiers"]:
		if not tier["visible"]:
			dark += 1
	assert_true(dark >= 1, "some windows have gone dark by the late closed evening")
	world.clock.phase = SimClock.Phase.MORNING
	_main.call("refresh_presentation")
	for tier: Dictionary in dressing.window_state()["tiers"]:
		assert_false(tier["visible"])
