class_name PersonOutfit
extends RefCounted
## Paints a location guest's outfit (#663 #657 #658 #659) onto a kit body mesh.
##
## The kit colours each part of a model through a colormap block, and one block
## often serves several parts (sleeves and trousers share one on some models),
## so a block repaint cannot dress a torso apart from the legs. Instead each
## triangle of a private copy of the body mesh is sorted into a body region by
## its skin bone and rest-pose position, and its UVs move to a spare block of a
## private colormap copy painted in that region's colour. Each spare block keeps
## the shading of the block it replaces. Hands, shoes and anything already in
## the model's skin colour keep their kit UVs (some
## models wear gloves; an outfit may bare the hands). The vendored files are never
## edited, and nothing here reads a random stream.

enum Region { KEEP, TORSO, HIP, SLEEVE, HAND, THIGH, SHIN }

## Rest-pose heights and reach in the kit's source units (all eight guest
## models share one skeleton): shoes end at SHOE_TOP, the legs' lower blocks
## at SHIN_TOP, the hips at HIP_TOP; arm faces beyond HAND_X are the hand.
const SHOE_TOP: float = 0.03
const SHIN_TOP: float = 0.09
const HIP_TOP: float = 0.215
const HAND_X: float = 0.27
const TEXTURE_SIZE: int = 512
const BLOCK: Vector2i = Vector2i(32, 128)
## Blocks of the colormap no kit model uses (the black rows at the top), where
## the outfit's colours are painted.
const SPARE_ROWS: Array[int] = [0]

static var _cache: Dictionary[String, Array] = {}


## The region a body triangle belongs to, from its strongest bone and its
## centroid in the rest pose. `column` is the block its UVs point at.
static func region_for(bone: StringName, centroid: Vector3, column: Vector2i, skin: Vector2i) -> Region:
	if column == skin:
		return Region.KEEP
	match bone:
		&"leg-left", &"leg-right":
			if centroid.y < SHOE_TOP:
				return Region.KEEP
			return Region.SHIN if centroid.y < SHIN_TOP else Region.THIGH
		&"torso":
			return Region.HIP if centroid.y < HIP_TOP else Region.TORSO
		&"arm-left", &"arm-right":
			return Region.HAND if absf(centroid.x) >= HAND_X else Region.SLEEVE
	return Region.KEEP


## What a region wears under an outfit: a Color, &"skin" (bare), or null (keep).
static func paint_for(region: Region, outfit: Dictionary) -> Variant:
	var upper: Variant = outfit.get("upper")
	var lower: Variant = outfit.get("lower")
	match region:
		Region.TORSO:
			return upper
		Region.SLEEVE:
			return &"skin" if outfit.get("bare_arms", false) else upper
		Region.HAND:
			return &"skin" if outfit.get("bare_hands", false) else null
		Region.HIP:
			return lower if lower != null else upper
		Region.THIGH:
			return lower
		Region.SHIN:
			return &"skin" if outfit.get("bare_shins", false) else lower
	return null


## The block (top-left texel) that a texel coordinate falls in.
static func column_of(texel: Vector2) -> Vector2i:
	return Vector2i(int(floor(texel.x / BLOCK.x)) * BLOCK.x, int(floor(texel.y / BLOCK.y)) * BLOCK.y)


## The top-left texel of spare block `index`, or (-1, -1) once they run out.
static func spare_block(index: int) -> Vector2i:
	var per_row: int = TEXTURE_SIZE / BLOCK.x
	if index < 0 or index >= per_row * SPARE_ROWS.size():
		return Vector2i(-1, -1)
	return Vector2i((index % per_row) * BLOCK.x, SPARE_ROWS[index / per_row])


## [mesh, material] for `body` (the kit body-mesh instance, skinned to
## `skeleton`) dressed in `outfit`, built once per `key` and shared. Empty on
## any failure, so the caller keeps the kit look.
static func dressed_body(body: MeshInstance3D, outfit: Dictionary, skin: Vector2i, key: String) -> Array:
	if _cache.has(key):
		return _cache[key]
	var source: ArrayMesh = body.mesh as ArrayMesh
	if source == null or source.get_surface_count() != 1 or body.skin == null:
		return []
	var base: StandardMaterial3D = source.surface_get_material(0) as StandardMaterial3D
	if base == null or base.albedo_texture == null:
		return []
	var arrays: Array = source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if uvs.size() != vertices.size() or bones.size() != vertices.size() * 4 or indices.is_empty():
		return []
	var moved: PackedVector2Array = uvs.duplicate()
	# Spare blocks by "colour|source column": each keeps the source's shading.
	var slots: Dictionary[String, Vector2i] = {}
	var paints: Array[Dictionary] = []
	for triangle: int in range(0, indices.size(), 3):
		var first: int = indices[triangle]
		var centroid: Vector3 = (vertices[first] + vertices[indices[triangle + 1]] + vertices[indices[triangle + 2]]) / 3.0
		var texel: Vector2 = uvs[first] * TEXTURE_SIZE
		var column: Vector2i = column_of(texel)
		var paint: Variant = paint_for(region_for(_strongest_bone(body.skin, bones, weights, first), centroid,
			column, skin), outfit)
		if paint == null:
			continue
		var target: Vector2i = skin
		if paint is Color:
			var slot_key: String = "%s|%s" % [(paint as Color).to_html(), column]
			if not slots.has(slot_key):
				var block: Vector2i = spare_block(slots.size())
				if block.x < 0:
					return []
				slots[slot_key] = block
				paints.append({"block": block, "source": column, "color": paint})
			target = slots[slot_key]
		var shift: Vector2 = Vector2(target - column) / float(TEXTURE_SIZE)
		for corner: int in 3:
			var vertex: int = indices[triangle + corner]
			moved[vertex] = uvs[vertex] + shift
	arrays[Mesh.ARRAY_TEX_UV] = moved
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: StandardMaterial3D = painted_material(base, paints)
	if material == null:
		return []
	mesh.surface_set_material(0, material)
	_cache[key] = [mesh, material]
	return _cache[key]


static func _strongest_bone(skin: Skin, bones: PackedInt32Array, weights: PackedFloat32Array, vertex: int) -> StringName:
	var best: int = 0
	for influence: int in range(1, 4):
		if weights[vertex * 4 + influence] > weights[vertex * 4 + best]:
			best = influence
	var bind: int = bones[vertex * 4 + best]
	return skin.get_bind_name(bind) if bind >= 0 and bind < skin.get_bind_count() else &""


## A copy of `base` whose colormap has each paint's spare block filled with its
## colour, shaded like its source block (each texel's luminance over its
## column's top texel, as the uniforms are), and any `darken` blocks scaled.
static func painted_material(base: StandardMaterial3D, paints: Array[Dictionary],
		darken: Array[Dictionary] = []) -> StandardMaterial3D:
	var image: Image = base.albedo_texture.get_image()
	if image == null:
		return null
	image = image.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	for paint: Dictionary in paints:
		var block: Vector2i = paint["block"]
		var source: Vector2i = paint["source"]
		var color: Color = paint["color"]
		for x: int in BLOCK.x:
			var top: float = image.get_pixel(source.x + x, source.y).get_luminance()
			for y: int in BLOCK.y:
				var shade: float = image.get_pixel(source.x + x, source.y + y).get_luminance() / top if top > 0.0 else 1.0
				image.set_pixel(block.x + x, block.y + y, Color(color.r * shade, color.g * shade, color.b * shade, 1.0))
	for dark: Dictionary in darken:
		var block: Vector2i = dark["block"]
		var factor: float = dark["shade"]
		for x: int in BLOCK.x:
			for y: int in BLOCK.y:
				var texel: Color = image.get_pixel(block.x + x, block.y + y)
				image.set_pixel(block.x + x, block.y + y, Color(texel.r * factor, texel.g * factor, texel.b * factor, 1.0))
	if image.has_mipmaps():
		image.clear_mipmaps()
	image.generate_mipmaps()
	var material: StandardMaterial3D = base.duplicate() as StandardMaterial3D
	material.albedo_texture = ImageTexture.create_from_image(image)
	return material


## The head's material with its hair block darkened by `shade`, built once per key.
static func wet_hair_material(head: MeshInstance3D, hair: Vector2i, shade: float, key: String) -> Material:
	if _cache.has(key):
		return _cache[key][0]
	var base: StandardMaterial3D = head.mesh.surface_get_material(0) as StandardMaterial3D if head.mesh != null else null
	if base == null or base.albedo_texture == null:
		return null
	var empty: Array[Dictionary] = []
	var darken: Array[Dictionary] = [{"block": hair, "shade": shade}]
	var material: StandardMaterial3D = painted_material(base, empty, darken)
	if material == null:
		return null
	_cache[key] = [material]
	return material
