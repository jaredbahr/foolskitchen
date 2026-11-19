class_name VanRide
extends Control
## The van ride (docs/CITY_MAP.md T5): a short, skippable picture of the
## owner's red van driving along the map road from one neighbourhood to the
## next, then one jokey commute line. Purely cosmetic: main.gd starts it after
## `switch_site` has already succeeded, and it changes nothing. Any click, tap
## or key (main.gd forwards keys) ends it at once. It draws the paper map
## it is given, so there is nothing to ride on without map art.

## Emitted once when the ride ends, whether it ran out or was skipped.
signal finished(skipped: bool)

const VAN_ART: Texture2D = preload("res://assets/made/city_map/van.png")
const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
## How long the commute line stays after the van arrives, seconds.
const HOLD_SECONDS: float = 1.0
## The commute line fades in over this share of the ride, from START to END.
const LINE_FADE_START: float = 0.55
const LINE_FADE_END: float = 0.8
## The frame (map and caption) fills at most this share of the screen.
const FRAME_SHARE: float = 0.92
## The caption's height, kept under the map, and its widest, px.
const CAPTION_HEIGHT: float = 96.0
const CAPTION_MAX_WIDTH: float = 560.0
## The caption's side padding, px.
const CAPTION_PAD: float = 14.0
## The van is this share of the map's width, within these limits (px).
const VAN_RATIO: float = 0.1
const VAN_MIN: float = 52.0
const VAN_MAX: float = 120.0
const TRAIL_COLOR: Color = Color("c44838")
const INK_COLOR: Color = Color("3b2a20")
const PAPER_COLOR: Color = Color("e8d9b4")
const HINT: String = "Click to skip"

var _map_texture: Texture2D
## The route in map units (0 to 1 on each axis) and the length up to each point.
var _path: PackedVector2Array = PackedVector2Array()
var _lengths: PackedFloat32Array = PackedFloat32Array()
var _ride_seconds: float = 0.0
var _hold_seconds: float = HOLD_SECONDS
var _elapsed: float = 0.0
var _playing: bool = false
var _line: String = ""

var _dim: ColorRect
var _frame: Control
var _background: TextureRect
var _route: Control
var _van: TextureRect
var _caption: Panel
var _caption_label: Label
var _hint: Label


func _init() -> void:
	name = "VanRide"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = SHARED_THEME
	visible = false
	set_process(false)
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_frame = Control.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_background = TextureRect.new()
	_background.name = "Map"
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(_background)
	_route = Control.new()
	_route.name = "Route"
	_route.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_route.set_anchors_preset(Control.PRESET_FULL_RECT)
	_route.draw.connect(_draw_route)
	_frame.add_child(_route)
	_van = TextureRect.new()
	_van.name = "Van"
	_van.texture = VAN_ART
	_van.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_van.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_van.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.add_child(_van)
	_caption = Panel.new()
	_caption.name = "Caption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_stylebox_override(&"panel", _caption_style())
	add_child(_caption)
	_caption_label = Label.new()
	_caption_label.name = "Line"
	_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A fixed box, so the text wraps inside it rather than sizing it.
	_caption_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption_label.offset_left = CAPTION_PAD
	_caption_label.offset_right = -CAPTION_PAD
	_caption_label.offset_top = 4.0
	_caption_label.offset_bottom = -4.0
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.add_theme_font_size_override(&"font_size", 20)
	_caption.add_child(_caption_label)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = HINT
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override(&"font_size", 14)
	_hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.75))
	add_child(_hint)
	resized.connect(_layout)


func _caption_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PAPER_COLOR
	style.set_border_width_all(2)
	style.border_color = INK_COLOR
	style.set_corner_radius_all(8)
	return style


## Starts a ride along `path` (map units) over `map_texture`, then shows `line`
## (may be "") for a moment. Returns false, drawing nothing, when there is no
## picture, no route or no time. Replaces a ride already under way.
func play(map_texture: Texture2D, path: PackedVector2Array, line: String, ride_seconds: float,
		hold_seconds: float = HOLD_SECONDS) -> bool:
	if map_texture == null or path.size() < 2 or ride_seconds <= 0.0:
		return false
	_map_texture = map_texture
	_background.texture = map_texture
	_path = path.duplicate()
	_lengths = PackedFloat32Array([0.0])
	for index: int in range(1, _path.size()):
		_lengths.append(_lengths[index - 1] + _path[index].distance_to(_path[index - 1]))
	_ride_seconds = ride_seconds
	_hold_seconds = maxf(hold_seconds, 0.0)
	_line = line
	_caption_label.text = line
	_elapsed = 0.0
	_playing = true
	visible = true
	set_process(true)
	_layout()
	_update()
	return true


func is_playing() -> bool:
	return _playing


## Ends the ride at once (a click, a tap or a key).
func skip() -> void:
	_end(true)


## Moves the ride on by `delta` seconds. _process calls it; tests call it
## directly so nothing waits on the clock.
func tick(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	if _elapsed >= _ride_seconds + _hold_seconds:
		_end(false)
		return
	_update()


## How far along the road the van is, 0 to 1, eased at both ends.
func progress() -> float:
	if _ride_seconds <= 0.0:
		return 1.0
	return smoothstep(0.0, 1.0, clampf(_elapsed / _ride_seconds, 0.0, 1.0))


## The van's spot on the map, in map units.
func van_position() -> Vector2:
	return _point_at(progress() * _total_length())


## The commute line being shown, and how visible it is now (0 to 1).
func line() -> String:
	return _line


func line_alpha() -> float:
	var t: float = clampf(_elapsed / maxf(_ride_seconds, 0.001), 0.0, 1.0)
	return smoothstep(LINE_FADE_START, LINE_FADE_END, t) if not _line.is_empty() else 0.0


func _process(delta: float) -> void:
	tick(delta)


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if _playing and button != null and button.pressed:
		skip()
		accept_event()


func _end(skipped: bool) -> void:
	if not _playing:
		return
	_playing = false
	visible = false
	set_process(false)
	finished.emit(skipped)


func _total_length() -> float:
	return _lengths[_lengths.size() - 1] if not _lengths.is_empty() else 0.0


## The point `distance` along the route, in map units.
func _point_at(distance: float) -> Vector2:
	if _path.is_empty():
		return Vector2.ZERO
	for index: int in range(1, _path.size()):
		if distance <= _lengths[index]:
			var span: float = _lengths[index] - _lengths[index - 1]
			var t: float = 0.0 if span <= 0.0 else (distance - _lengths[index - 1]) / span
			return _path[index - 1].lerp(_path[index], t)
	return _path[_path.size() - 1]


## The way the van faces at `distance`: -1 left, 1 right.
func _facing(distance: float) -> float:
	for index: int in range(1, _path.size()):
		if distance <= _lengths[index] or index == _path.size() - 1:
			var dx: float = _path[index].x - _path[index - 1].x
			return -1.0 if dx < -0.0001 else 1.0
	return 1.0


## Lays the frame out: the map keeps its shape and fits the screen, the
## caption sits under it and the hint in the corner.
func _layout() -> void:
	if _map_texture == null:
		return
	var screen: Vector2 = size
	var avail: Vector2 = Vector2(screen.x * FRAME_SHARE, screen.y * FRAME_SHARE - CAPTION_HEIGHT)
	var aspect: float = float(_map_texture.get_width()) / float(_map_texture.get_height())
	var width: float = minf(avail.x, avail.y * aspect)
	var height: float = width / aspect
	var top: float = (screen.y - height - CAPTION_HEIGHT) / 2.0
	_frame.position = Vector2((screen.x - width) / 2.0, top)
	_frame.size = Vector2(width, height)
	var caption_width: float = minf(width, CAPTION_MAX_WIDTH)
	_caption.position = Vector2((screen.x - caption_width) / 2.0, top + height + 12.0)
	_caption.size = Vector2(caption_width, CAPTION_HEIGHT - 12.0)
	_hint.position = Vector2(screen.x - _hint.get_minimum_size().x - 16.0, screen.y - 28.0)
	var van_width: float = clampf(width * VAN_RATIO, VAN_MIN, VAN_MAX)
	_van.size = Vector2(van_width, van_width * float(VAN_ART.get_height()) / float(VAN_ART.get_width()))
	_update()


func _update() -> void:
	if _path.is_empty():
		return
	var distance: float = progress() * _total_length()
	var spot: Vector2 = _point_at(distance) * _frame.size
	# The wheels sit on the road: the sprite's bottom edge, a little in from its ends.
	_van.pivot_offset = _van.size / 2.0
	_van.scale = Vector2(_facing(distance), 1.0)
	var bob: float = sin(_elapsed * 22.0) * 1.2 if _playing and progress() < 1.0 else 0.0
	_van.position = spot - Vector2(_van.size.x / 2.0, _van.size.y * 0.85) + Vector2(0.0, bob)
	_caption.modulate.a = line_alpha()
	_caption.visible = not _line.is_empty()
	_route.queue_redraw()


## The road driven so far, as red dashes.
func _draw_route() -> void:
	if _path.size() < 2:
		return
	var scale_to_frame: Vector2 = _frame.size
	var distance: float = progress() * _total_length()
	var points: PackedVector2Array = PackedVector2Array([_path[0] * scale_to_frame])
	for index: int in range(1, _path.size()):
		if distance >= _lengths[index]:
			points.append(_path[index] * scale_to_frame)
		else:
			points.append(_point_at(distance) * scale_to_frame)
			break
	var dash: float = maxf(_frame.size.x * 0.012, 5.0)
	for index: int in range(1, points.size()):
		_dashes(points[index - 1], points[index], dash)


func _dashes(from: Vector2, to: Vector2, dash: float) -> void:
	var length: float = from.distance_to(to)
	if length <= 0.0:
		return
	var direction: Vector2 = (to - from) / length
	var at: float = 0.0
	while at < length:
		var stop: float = minf(at + dash, length)
		_route.draw_line(from + direction * at, from + direction * stop, TRAIL_COLOR, 4.0, true)
		at += dash * 2.0
