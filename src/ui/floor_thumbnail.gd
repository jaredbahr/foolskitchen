class_name FloorThumbnail
extends RefCounted
## Floors tab card pictures (D25): a small patch of a floor type, drawn on the
## CPU in flat palette colours with the same layout as
## src/world/floor_finish.gdshader (no antialiasing, no lighting). Deterministic.

const WIDTH: int = 64
const HEIGHT: int = 44
## Pixels per metre: the patch shows 0.5 m by about 0.34 m of floor.
const SCALE: float = 128.0


static func image(pattern: int, main: Color, accent: Color, auto_accent: bool) -> Image:
	var picture: Image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	var seam: Color = main * 0.72 if auto_accent else accent
	seam.a = 1.0
	var second: Color = main * 0.55 if auto_accent else accent
	second.a = 1.0
	for y: int in range(HEIGHT):
		for x: int in range(WIDTH):
			var p: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) / SCALE
			picture.set_pixel(x, y, _colour(pattern, p, main, seam, second))
	# A darker edge of the same colour, like the room and paint chips.
	var edge: Color = main.darkened(0.35)
	for x: int in range(WIDTH):
		picture.set_pixel(x, 0, edge)
		picture.set_pixel(x, HEIGHT - 1, edge)
	for y: int in range(HEIGHT):
		picture.set_pixel(0, y, edge)
		picture.set_pixel(WIDTH - 1, y, edge)
	return picture


static func texture(pattern: int, main: Color, accent: Color, auto_accent: bool) -> ImageTexture:
	return ImageTexture.create_from_image(image(pattern, main, accent, auto_accent))


static func _colour(pattern: int, p: Vector2, main: Color, seam: Color, second: Color) -> Color:
	var out: Color = main
	match pattern:
		FloorStyleDef.Pattern.NARROW_PLANKS:
			var row: float = floorf(p.y / 0.125)
			var across: float = fposmod(p.y / 0.125, 1.0)
			var u: float = (p.x + _hash(Vector2(row, 7.0)) * 0.75) / 0.75
			var along: float = fposmod(u, 1.0)
			out = main * (1.0 + (_hash(Vector2(row, floorf(u))) - 0.5) * 0.07)
			if minf(across, 1.0 - across) * 0.125 < 0.006 or minf(along, 1.0 - along) * 0.75 < 0.005:
				out = seam
		FloorStyleDef.Pattern.HERRINGBONE:
			var width: float = 0.0625
			var n: float = 4.0
			var q: Vector2 = Vector2(p.x + p.y, p.y - p.x) * 0.70710678 / width
			var row: float = floorf(q.y)
			var u: float = fposmod(q.x - row, 2.0 * n)
			var along: float
			var across: float
			var id: Vector2
			var turn: float
			if u < n:
				along = u
				across = fposmod(q.y, 1.0)
				id = Vector2(row, floorf((q.x - row) / (2.0 * n)))
				turn = 0.0
			else:
				var column: float = floorf(q.x)
				along = fposmod(q.y - (column - 2.0 * n + 1.0), 2.0 * n)
				across = fposmod(q.x, 1.0)
				id = Vector2(column + 101.0, floorf((q.y - column + 2.0 * n - 1.0) / (2.0 * n)))
				turn = 1.0
			out = main * (1.0 + (_hash(id) - 0.5) * 0.08 + (turn - 0.5) * 0.04)
			if minf(across, 1.0 - across) * width < 0.005 or minf(along, n - along) * width < 0.005:
				out = seam
		FloorStyleDef.Pattern.CHECKER:
			var square: Vector2 = (p / 0.25).floor()
			out = second if fposmod(square.x + square.y, 2.0) > 0.5 else main
		FloorStyleDef.Pattern.SMALL_TILE:
			var tile: Vector2 = (p / 0.125).floor()
			var f: Vector2 = Vector2(fposmod(p.x / 0.125, 1.0), fposmod(p.y / 0.125, 1.0))
			out = main * (1.0 + (_hash(tile) - 0.5) * 0.05)
			if minf(f.x, 1.0 - f.x) * 0.125 < 0.006 or minf(f.y, 1.0 - f.y) * 0.125 < 0.006:
				out = seam
		_:
			var band: float = fposmod(floorf(p.y / 0.5), 2.0)
			var seam_amount: float = 1.0 - smoothstep(0.0, 0.012, absf(fposmod(p.y / 0.5, 1.0) - 0.5))
			out = main * (1.0 - band * 0.018 - seam_amount * 0.025)
	out.a = 1.0
	return out


## The shader's hash12, so card boards vary like the floor's (not bit-exact).
static func _hash(p: Vector2) -> float:
	var q: Vector3 = Vector3(fposmod(p.x * 0.1031, 1.0), fposmod(p.y * 0.1031, 1.0), fposmod(p.x * 0.1031, 1.0))
	var d: float = q.dot(Vector3(q.y, q.z, q.x) + Vector3(33.33, 33.33, 33.33))
	q += Vector3(d, d, d)
	return fposmod((q.x + q.y) * q.z, 1.0)
