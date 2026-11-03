class_name DayNightView
extends RefCounted
## Puts a DayLight.Look on the lighting rig and the glowing wall items (#208).
## Presentation only: it changes lights, the sky and glow strength, never
## the simulation. Glow keeps each item's authored strength as its base.

const BASE_META: StringName = &"day_night_base"
## Glow lights stay at or under this energy (the walls test keeps neon <= 1).
const MAX_GLOW_ENERGY: float = 1.0
const GLOW_POOLS: Array[StringName] = [&"PoolInside", &"PoolOutside"]
const SHOP_LIGHT: StringName = &"ShopLights"
## The shop's lights hang this high over the middle of the floor.
const SHOP_LIGHT_HEIGHT: float = 2.6
## Reach past the farthest floor corner, so the whole room is lit evenly.
const SHOP_LIGHT_REACH: float = 1.6
const SHOP_LIGHT_ATTENUATION: float = 0.5


static func apply_rig(rig: Node, look: DayLight.Look) -> void:
	if rig == null:
		return
	var key: DirectionalLight3D = rig.get_node_or_null(^"KeyLight") as DirectionalLight3D
	if key != null:
		key.light_color = look.key_color
		key.light_energy = look.key_energy
		# Only the downward angle changes; the compass direction stays exact.
		var rotation: Vector3 = key.rotation
		rotation.x = deg_to_rad(look.key_pitch)
		key.rotation = rotation
	var fill: DirectionalLight3D = rig.get_node_or_null(^"FillLight") as DirectionalLight3D
	if fill != null:
		fill.light_energy = look.fill_energy
	var world: WorldEnvironment = rig.get_node_or_null(^"Environment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	world.environment.ambient_light_color = look.ambient_color
	world.environment.ambient_light_energy = look.ambient_energy
	var sky: ProceduralSkyMaterial = world.environment.sky.sky_material as ProceduralSkyMaterial \
		if world.environment.sky != null else null
	if sky != null:
		sky.sky_top_color = look.sky_top
		sky.sky_horizon_color = look.sky_horizon
		sky.ground_horizon_color = look.sky_horizon
		sky.ground_bottom_color = look.sky_ground


## Scales every glowing wall item's light and window pools by `glow`.
static func apply_glow(items: Dictionary[Vector3i, ItemVisual], glow: float) -> void:
	for anchor: Vector3i in items:
		var node: ItemVisual = items[anchor]
		var light: OmniLight3D = node.get_node_or_null(^"Glow") as OmniLight3D
		if light == null:
			continue
		if not light.has_meta(BASE_META):
			light.set_meta(BASE_META, light.light_energy)
		light.light_energy = minf(float(light.get_meta(BASE_META)) * glow, MAX_GLOW_ENERGY)
		for pool_name: StringName in GLOW_POOLS:
			var pool: MeshInstance3D = node.get_node_or_null(NodePath(String(pool_name))) as MeshInstance3D
			var material: StandardMaterial3D = pool.material_override as StandardMaterial3D if pool != null else null
			if material == null:
				continue
			if not pool.has_meta(BASE_META):
				pool.set_meta(BASE_META, material.albedo_color)
			var base: Color = pool.get_meta(BASE_META)
			material.albedo_color = Color(base.r * glow, base.g * glow, base.b * glow, base.a)


## The shop's own warm lights at dusk and night: one soft light over the
## middle of the floor, reaching every corner and fading out past the walls,
## so the room glows while the street stays dark. Hidden by day.
static func apply_shop_light(rig: Node3D, grid: SimGrid, energy: float, colour: Color) -> void:
	if rig == null:
		return
	var light: OmniLight3D = rig.get_node_or_null(NodePath(String(SHOP_LIGHT))) as OmniLight3D
	if energy <= 0.001 or grid == null:
		if light != null:
			light.visible = false
		return
	var bounds: Rect2 = floor_bounds(grid)
	if bounds.size == Vector2.ZERO:
		return
	if light == null:
		light = OmniLight3D.new()
		light.name = String(SHOP_LIGHT)
		light.shadow_enabled = false
		light.omni_attenuation = SHOP_LIGHT_ATTENUATION
		rig.add_child(light)
	var middle: Vector2 = bounds.get_center()
	light.position = Vector3(middle.x, SHOP_LIGHT_HEIGHT, middle.y)
	light.omni_range = bounds.size.length() * 0.5 + SHOP_LIGHT_REACH
	light.light_color = colour
	light.light_energy = energy
	light.visible = true


## The world-space rectangle (x, z) covering every floor cell.
static func floor_bounds(grid: SimGrid) -> Rect2:
	var low: Vector2i = Vector2i(1 << 30, 1 << 30)
	var high: Vector2i = Vector2i(-(1 << 30), -(1 << 30))
	var found: bool = false
	for cell: Vector2i in grid.cells():
		if grid.terrain(cell) != SimGrid.Terrain.FLOOR:
			continue
		found = true
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	if not found:
		return Rect2()
	return Rect2(Vector2(low) * GridMath.CELL_SIZE, Vector2(high - low + Vector2i.ONE) * GridMath.CELL_SIZE)
