class_name WallThumbnail
extends RefCounted
## Wall finish card pictures (D26): a patch of wall from the floor up, drawn
## on the CPU in flat palette colours with the same layout as
## src/world/wall_finish.gdshader (no antialiasing, no lighting).
## `accent` is already resolved (WallFinishView's automatic accents).

const WIDTH: int = 64
const HEIGHT: int = 44
## Pixels per metre: the patch shows 0.8 m of wall by 0.55 m high.
const SCALE: float = 80.0


static func image(pattern: int, main: Color, accent: Color) -> Image:
	var picture: Image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	main.a = 1.0
	accent.a = 1.0
	for y: int in range(HEIGHT):
		for x: int in range(WIDTH):
			# Image rows run down; wall height runs up from the bottom edge.
			var p: Vector2 = Vector2(float(x) + 0.5, float(HEIGHT - y) - 0.5) / SCALE
			picture.set_pixel(x, y, colour(pattern, p, main, accent))
	var edge: Color = main.darkened(0.35)
	for x: int in range(WIDTH):
		picture.set_pixel(x, 0, edge)
		picture.set_pixel(x, HEIGHT - 1, edge)
	for y: int in range(HEIGHT):
		picture.set_pixel(0, y, edge)
		picture.set_pixel(WIDTH - 1, y, edge)
	return picture


static func texture(pattern: int, main: Color, accent: Color) -> ImageTexture:
	return ImageTexture.create_from_image(image(pattern, main, accent))


## The colour at `p` (metres: along the wall, up from the floor).
static func colour(pattern: int, p: Vector2, main: Color, accent: Color) -> Color:
	match pattern:
		WallStyleDef.Pattern.WAINSCOT:
			var top: float = 0.46
			if p.y > top:
				return accent
			var out: Color = main
			var board: float = fposmod(p.x / 0.1, 1.0)
			if minf(board, 1.0 - board) * 0.1 < 0.006:
				out = _shade(main, 0.78)
			if p.y < 0.06:
				out = _shade(main, 0.88)
			if p.y > top - 0.045:
				out = _shade(main, 1.08) if p.y > top - 0.016 else _shade(main, 0.92)
			return out
		WallStyleDef.Pattern.STRIPES:
			return main if fposmod(p.x, 0.12) < 0.07 else accent
		WallStyleDef.Pattern.SUBWAY_TILE:
			return _bond(p, Vector2(0.15, 0.075), 0.006, main, accent)
		WallStyleDef.Pattern.BRICK:
			return _bond(p + Vector2(0.0, 0.02), Vector2(0.22, 0.075), 0.009, main, accent)
	return main


static func _bond(p: Vector2, size: Vector2, joint: float, main: Color, seam: Color) -> Color:
	var row: float = floorf(p.y / size.y)
	var u: float = fposmod(p.x / size.x + fposmod(row, 2.0) * 0.5, 1.0)
	var v: float = fposmod(p.y / size.y, 1.0)
	if minf(u, 1.0 - u) * size.x < joint or minf(v, 1.0 - v) * size.y < joint:
		return seam
	return main


static func _shade(colour_value: Color, factor: float) -> Color:
	return Color(minf(colour_value.r * factor, 1.0), minf(colour_value.g * factor, 1.0), minf(colour_value.b * factor, 1.0))
