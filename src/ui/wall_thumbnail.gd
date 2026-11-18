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
		WallStyleDef.Pattern.LOGS:
			var course: float = 0.14
			var row: float = floorf(p.y / course)
			var t: float = fposmod(p.y / course, 1.0)
			if minf(t, 1.0 - t) * course < 0.008:
				return accent
			var tone: float = 0.95 + 0.08 * fposmod(sin(row * 12.9898) * 43758.5453, 1.0)
			if t > 0.66:
				tone *= 1.1
			elif t < 0.24:
				tone *= 0.8
			return _shade(main, tone)
		WallStyleDef.Pattern.MILL:
			return _mill(p, main, accent)
		WallStyleDef.Pattern.CONCRETE:
			return _concrete(p, main, accent)
		WallStyleDef.Pattern.WHITEWASH:
			return _whitewash(p, main, accent)
	return main


## A country mill's wall (#613), as in the shader: rubble stone with pale mortar to
## 0.78 m, an oak sill beam, then upright timber boards in the accent colour.
static func _mill(p: Vector2, main: Color, timber: Color) -> Color:
	if p.y < 0.78:
		var course: float = floorf(p.y / 0.13)
		var lift: float = fposmod(p.y / 0.13, 1.0)
		var row_seed: float = fposmod(sin(course * 17.31) * 4375.85, 1.0)
		var length: float = 0.17 + 0.13 * row_seed
		var u: float = p.x / length + row_seed * 3.7
		var stone: float = floorf(u)
		var h: float = fposmod(sin(stone * 12.9898 + course * 78.233) * 43758.5453, 1.0)
		var f: float = fposmod(u, 1.0)
		var dx: float = minf(f, 1.0 - f) * length
		if h > 0.72:
			dx = minf(dx, absf(f - 0.5) * length)
		if dx < 0.009 or minf(lift, 1.0 - lift) * 0.13 < 0.009:
			return Color(minf(main.r * 1.22, 1.0), minf(main.g * 1.22, 1.0), minf(main.b * 1.22, 1.0))
		var tone: float = (0.86 + 0.2 * h) * (1.07 if lift > 0.78 else (0.9 if lift < 0.18 else 1.0))
		return _shade(main, tone)
	if p.y < 0.86:
		var t: float = (p.y - 0.78) / 0.08
		return _shade(timber, 1.12 if t > 0.7 else (0.72 if t < 0.25 else 0.92))
	var board: float = fposmod(p.x / 0.11, 1.0)
	if minf(board, 1.0 - board) * 0.11 < 0.005:
		return _shade(timber, 0.55)
	if board < 0.12:
		return _shade(timber, 1.16)
	return _shade(timber, 0.94 + 0.1 * fposmod(sin(floorf(p.x / 0.11) * 91.7) * 4375.85, 1.0))


## Architectural concrete panels (#618), as in the shader: 0.5 x 0.7 m panels in a
## dark reveal (the accent), lit chamfers top and left, shaded bottom and right, and
## four form-tie holes each.
static func _concrete(p: Vector2, main: Color, reveal: Color) -> Color:
	var size: Vector2 = Vector2(0.5, 0.7)
	var cell: Vector2 = Vector2(floorf(p.x / size.x), floorf(p.y / size.y))
	var f: Vector2 = Vector2(fposmod(p.x, size.x), fposmod(p.y, size.y))
	if minf(f.x, size.x - f.x) < 0.009 or minf(f.y, size.y - f.y) < 0.009:
		return _shade(reveal, 0.85)
	var tie: Vector2 = Vector2(0.125 if f.x < size.x * 0.5 else size.x - 0.125, 0.175 if f.y < size.y * 0.5 else size.y - 0.175)
	if f.distance_to(tie) < 0.014:
		return _shade(reveal, 0.92)
	if f.x < 0.022 or size.y - f.y < 0.022:
		return _shade(main, 1.42)
	if size.x - f.x < 0.022 or f.y < 0.022:
		return _shade(main, 1.06)
	var h: float = fposmod(sin(cell.x * 12.9898 + cell.y * 78.233) * 43758.5453, 1.0)
	return _shade(main, 1.26 + 0.06 * h)


## Whitewashed rubble (#380), as in the shader: a tarred plinth (the accent) to 0.16 m
## with a pale drip edge, then washed stone courses 0.13 m high with lit top edges and
## soft joints.
static func _whitewash(p: Vector2, main: Color, plinth: Color) -> Color:
	var foot: float = 0.16
	if p.y < foot:
		return _shade(plinth, 1.3) if foot - p.y < 0.018 else plinth
	var course: float = 0.13
	var row: float = floorf((p.y - foot) / course)
	var width: float = 0.24 + 0.1 * fposmod(sin(row * 17.1) * 913.7, 1.0)
	var x: float = p.x / width + fposmod(sin(row * 41.3) * 4375.85, 1.0)
	var f: Vector2 = Vector2(fposmod(x, 1.0) * width, fposmod(p.y - foot, course))
	if minf(f.x, width - f.x) < 0.009 or minf(f.y, course - f.y) < 0.009:
		return _shade(main, 0.95)
	if course - f.y < 0.02:
		return _shade(main, 1.2)
	var h: float = fposmod(sin(floorf(x) * 12.9898 + row * 78.233) * 43758.5453, 1.0)
	return _shade(main, 1.12 + 0.05 * h)


static func _bond(p: Vector2, size: Vector2, joint: float, main: Color, seam: Color) -> Color:
	var row: float = floorf(p.y / size.y)
	var u: float = fposmod(p.x / size.x + fposmod(row, 2.0) * 0.5, 1.0)
	var v: float = fposmod(p.y / size.y, 1.0)
	if minf(u, 1.0 - u) * size.x < joint or minf(v, 1.0 - v) * size.y < joint:
		return seam
	return main


static func _shade(colour_value: Color, factor: float) -> Color:
	return Color(minf(colour_value.r * factor, 1.0), minf(colour_value.g * factor, 1.0), minf(colour_value.b * factor, 1.0))
