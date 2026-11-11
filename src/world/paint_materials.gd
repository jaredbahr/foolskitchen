class_name PaintMaterials
extends RefCounted
## The material looks of paint slots (#431): Paint, Wood, Fabric and Metal.
## A look is a plain StandardMaterial3D copy of the kit surface, so lighting,
## alpha and the palette colour (albedo_color) stay exactly the kit's way; Wood,
## Fabric and Metal add a soft, light grey pattern (object-space triplanar, so
## no UVs or meshes change) and their own sheen. Patterns are drawn once from
## integer hashes: deterministic, no RNG. Paint is the legacy flat coat.

const SIZE: int = 64
## Pattern repeats per model unit (Kenney models are about 1 unit across).
const SCALES: Dictionary[StringName, float] = {
	PaintFinish.WOOD: 1.2, PaintFinish.FABRIC: 5.0, PaintFinish.METAL: 2.0,
}
const ROUGHNESS: Dictionary[StringName, float] = {
	PaintFinish.WOOD: 0.8, PaintFinish.FABRIC: 1.0, PaintFinish.METAL: 0.35,
}
## Low: the Compatibility renderer has no reflections to fill a true metal,
## which would turn every colour dark; the sheen comes from the specular.
const METALLIC: float = 0.15
const METAL_SPECULAR: float = 0.85

## Above this many shared painted copies the cache starts again (live meshes
## keep their own references), so endless hovering never piles up.
const MAX_CACHED: int = 1024

static var _textures: Dictionary[StringName, ImageTexture] = {}
## Painted copies shared by every item: (kit source material, colour, finish).
static var _painted: Dictionary[String, BaseMaterial3D] = {}


## The shared painted copy of `source` in `color` and `material`. Items built
## from one kit model share it, so a Shift-hover over a room of chairs
## through many colours adds one copy per colour, not one per chair.
static func shared(source: BaseMaterial3D, color: Color, material: StringName) -> BaseMaterial3D:
	var key: String = "%d/%s/%s" % [source.get_instance_id(), color.to_html(), material]
	var painted: BaseMaterial3D = _painted.get(key) as BaseMaterial3D
	if painted == null:
		if _painted.size() >= MAX_CACHED:
			_painted.clear()
		painted = source.duplicate() as BaseMaterial3D
		configure(painted, source, color, material)
		_painted[key] = painted
	return painted


static func cached_count() -> int:
	return _painted.size()


## Drop every shared copy (the shop view leaving the tree, test teardown).
static func clear_cache() -> void:
	_painted.clear()


## Configure `target` (a duplicate of `source`) as `material` in `color`.
## Paint, an empty id or an unknown one keeps the legacy flat coat exactly.
static func configure(target: BaseMaterial3D, source: BaseMaterial3D, color: Color, material: StringName) -> void:
	target.albedo_color = Color(color.r, color.g, color.b, source.albedo_color.a)
	if not SCALES.has(material):
		return
	target.albedo_texture = texture(material)
	target.uv1_triplanar = true
	target.uv1_world_triplanar = false
	target.uv1_triplanar_sharpness = 4.0
	var scale: float = SCALES[material]
	target.uv1_scale = Vector3(scale, scale, scale)
	target.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	target.roughness = ROUGHNESS[material]
	if material == PaintFinish.METAL:
		target.metallic = METALLIC
		target.metallic_specular = METAL_SPECULAR
	else:
		target.metallic = 0.0


## The shared pattern of a textured look (null for Paint).
static func texture(material: StringName) -> ImageTexture:
	if not SCALES.has(material):
		return null
	if not _textures.has(material):
		_textures[material] = ImageTexture.create_from_image(pattern(material))
	return _textures[material]


## The pattern image (also drawn on the Paint panel's material chips).
## Values stay light (0.8 to 1.0) so the palette colour reads first.
static func pattern(material: StringName) -> Image:
	var image: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			var shade: float = 1.0
			match material:
				PaintFinish.WOOD:
					shade = _wood(x, y)
				PaintFinish.FABRIC:
					shade = _fabric(x, y)
				PaintFinish.METAL:
					shade = _metal(x, y)
			image.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	image.generate_mipmaps()
	return image


## Soft long grain: a few darker lines that wander a little, plus faint rings.
## Seamless: every term repeats over the tile.
static func _wood(x: int, y: int) -> float:
	var v: float = float(y) / SIZE
	var wobble: float = 0.9 * sin(TAU * v) + 0.4 * sin(TAU * 2.0 * v + 1.3)
	var u: float = (float(x) + wobble) / SIZE
	var rings: float = 0.5 + 0.5 * cos(TAU * 4.0 * u)
	var line: float = pow(maxf(0.0, cos(TAU * 8.0 * u + 0.7)), 24.0)
	var fleck: float = float(_hash(x, y / 6) % 100) / 100.0
	return clampf(1.0 - 0.05 * rings - 0.09 * line - 0.015 * fleck, 0.8, 1.0)


## A plain weave: alternating over/under threads in a soft checker of ridges.
static func _fabric(x: int, y: int) -> float:
	var cell: int = 4
	var over: bool = ((x / cell) + (y / cell)) % 2 == 0
	var along: float = float(y % cell if over else x % cell) / cell
	var ridge: float = sin(PI * (along + 0.5 / cell))
	var slub: float = float(_hash(x / 2, y / 2) % 100) / 100.0
	return clampf(0.82 + 0.15 * ridge - 0.03 * slub, 0.8, 1.0)


## Brushed metal: fine streaks along one direction, faint and seamless.
static func _metal(x: int, y: int) -> float:
	var streak: float = float(_hash(y, 7) % 100) / 100.0
	var drift: float = float(_hash(y / 3, x / 16) % 100) / 100.0
	return clampf(0.94 - 0.06 * streak - 0.03 * drift + 0.04 * sin(TAU * float(x) / SIZE), 0.8, 1.0)


## Small integer hash (deterministic, no RNG).
static func _hash(a: int, b: int) -> int:
	var h: int = (a * 374761393 + b * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)
