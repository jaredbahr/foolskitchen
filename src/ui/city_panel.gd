class_name CityPanel
extends Control
## The city screen (docs/CITY_MAP.md, phase C2): a plain list version of the
## city map. Each neighbourhood in map order with its state, then your
## restaurants there (status, yesterday's money, manager, stars, mood,
## tonight's away result, alerts and a "Work here today" button) and the lots
## for sale or locked. It decides nothing: ChainSummary and CityMap do, and
## main.gd acts on `site_chosen` (switch_site, mornings only) and
## `market_requested` (the Property screen). Every line is in ChainText.

signal close_requested()
signal site_chosen(site_id: StringName)
signal market_requested()

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const PIN_SCENE: PackedScene = preload("res://src/ui/city_pin.tscn")
## How far apart, in map units, the lots of one neighbourhood sit beside it.
const PIN_SPREAD: float = 0.13
## How far below its neighbourhood's label a lot pin sits, in map units.
const PIN_DROP: float = 0.11
## The Property screen's tones, so the screens read as one.
const MUTED_COLOR: Color = Color("766b60")
const ALERT_COLOR: Color = Color("a83e35")
const AREA_FONT_SIZE: int = 22
const NAME_FONT_SIZE: int = 20
const LINE_FONT_SIZE: int = 16
## The paper's inks, the UI's own (main_theme.tres), for the strips round the map.
const INK_COLOR: Color = Color("3b2a20")
const PAPER_COLOR: Color = Color("e8d9b4")
## A pin's picture is this share of the map's width, within these limits (px).
const ICON_RATIO: float = 0.085
const ICON_MIN: int = 36
const ICON_MAX: int = 96
## Below this map width pins show the state word only and the font shrinks.
const COMPACT_WIDTH: float = 620.0
## Below this screen width the card fills the screen.
const NARROW_WIDTH: float = 900.0
## From this screen width the tapped pin's card sits beside the map (so the map
## keeps its full size); below it the card sits under the map.
const SIDE_WIDTH: float = 1000.0
## The card's least width when it sits beside the map, px.
const SIDE_CARD_WIDTH: float = 320.0
## Pins and signs keep this far (a share of the map's width) inside the drawing,
## which is the paper's own margin: nothing is drawn across the frame.
const EDGE_MARGIN: float = 0.04
const ROADWORKS_ART: Texture2D = preload("res://assets/made/city_map/roadworks.png")
const HOARDING_ART: Texture2D = preload("res://assets/made/city_map/hoarding.png")
## The roadworks and hoarding picture's width, a share of the map's width.
const SIGN_WIDTH: float = 0.15
## The most alerts the bottom bar lists; the rest are "and N more".
const BAR_ALERTS: int = 3
## A neighbourhood's name banner, in map units, for its hit area: 40 px of the
## 1500 px map per letter plus its ends, 80 px tall (tools/build_city_map.py).
const NAME_LETTER: float = 40.0 / 1500.0
const NAME_ENDS: float = 52.0 / 1500.0
const NAME_HEIGHT: float = 80.0 / 1000.0

## The paper map (docs/CITY_MAP.md T1; the director's art). While null the
## screen is the plain list; once set, the map view shows above the list with
## a pin per neighbourhood and lot, placed from NeighbourhoodDef.map_position.
@export var map_texture: Texture2D

var _site_ids: Array[StringName] = []
var _area_ids: Array[StringName] = []
var _map: CityMapDef
var _view: View
var _owned: Array[StringName] = []
## The pin the owner last tapped (its card shows under the map), or "".
var _selected: StringName = &""
## True while the plain list is showing instead of the map.
var _list_mode: bool = false


## What the screen shows: detached values, read only.
class View extends RefCounted:
	var sites: Array[ChainSummary.Site] = []
	## Away site id -> why it cannot be switched to now ("" when it can).
	var refusals: Dictionary[StringName, String] = {}
	var lots: Array[LotDef] = []
	var career_tier: int = 1
	## The closing reputation (NAN before the first close), for lock lines.
	var reputation: float = NAN


func _ready() -> void:
	PanelScroll.attach(self, $Panel as Control, $Panel/Content/Scroll as ScrollContainer)
	(get_node("Panel/Content/Header/Title") as Label).text = ChainText.TITLE
	(%Intro as Label).text = ChainText.INTRO
	(%ViewToggle as Button).text = ChainText.SHOW_LIST
	(%ChainStrip as PanelContainer).add_theme_stylebox_override(&"panel", _strip_style(8.0))
	(%AlertsBar as PanelContainer).add_theme_stylebox_override(&"panel", _strip_style(6.0))
	(%Canvas as Control).resized.connect(_relayout)
	(%MapPage as Control).resized.connect(_size_map_view)
	get_viewport().size_changed.connect(_fit_to_screen)
	_fit_to_screen()


## The slim paper strip behind the chain line and the alerts bar.
func _strip_style(pad: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PAPER_COLOR
	style.set_border_width_all(2)
	style.border_color = INK_COLOR
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = pad
	style.content_margin_bottom = pad
	return style


## On a narrow screen the panel takes nearly all of it; on a wide one it opens
## out and the tapped pin's card sits beside the map, so the map keeps its size.
func _fit_to_screen() -> void:
	if not is_inside_tree():
		return
	var panel: Control = $Panel as Control
	var width: float = get_viewport_rect().size.x
	var narrow: bool = width < NARROW_WIDTH
	var side: bool = width >= SIDE_WIDTH
	panel.anchor_left = 0.02 if narrow else (0.05 if side else 0.18)
	panel.anchor_right = 0.98 if narrow else (0.95 if side else 0.82)
	panel.anchor_top = 0.02 if narrow else 0.08
	panel.anchor_bottom = 0.98 if narrow else 0.97
	(%MapPage as BoxContainer).vertical = not side
	(%Side as Control).custom_minimum_size = Vector2(SIDE_CARD_WIDTH if side else 0.0, 0.0)
	_size_map_view()


## Beside the card the map fills the page's height (keeping the drawing's
## shape). Stacked, the map is exactly as tall as its width asks (capped at
## half the screen) and everything packs from the top: map, card or hint, alerts.
func _size_map_view() -> void:
	var view: Control = %MapView as Control
	var page: Control = %MapPage as Control
	var texture: Texture2D = map_texture
	if card_is_beside() or texture == null:
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		view.custom_minimum_size = Vector2.ZERO
		(%Side as Control).size_flags_vertical = Control.SIZE_FILL
		return
	view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	(%Side as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tall: float = page.size.x * float(texture.get_height()) / float(texture.get_width())
	view.custom_minimum_size = Vector2(0.0, minf(tall, get_viewport_rect().size.y * 0.5))


## True while the tapped pin's card sits beside the map (a wide screen).
func card_is_beside() -> bool:
	return not (%MapPage as BoxContainer).vertical


func set_city(map: CityMapDef, view: View) -> void:
	_map = map
	_view = view
	var list: VBoxContainer = %List as VBoxContainer
	for child: Node in list.get_children():
		list.remove_child(child)
		# Queued: a button may be the one emitting right now.
		child.queue_free()
	_site_ids.clear()
	_area_ids.clear()
	(%Chain as Label).text = ChainText.chain_line(view.sites)
	var owned: Array[StringName] = []
	for site: ChainSummary.Site in view.sites:
		owned.append(site.lot)
	_owned = owned
	_add_alerts(list, view.sites)
	var shown: Dictionary[StringName, bool] = {}
	if map != null:
		for area: NeighbourhoodDef in map.neighbourhoods:
			if area == null:
				continue
			list.add_child(_make_area(area, view, owned))
			_area_ids.append(area.id)
			for lot: StringName in area.lots:
				for site: ChainSummary.Site in view.sites:
					if site.lot == lot:
						list.add_child(_make_site(site, view.refusals.get(site.id, "")))
						_site_ids.append(site.id)
						shown[site.id] = true
				if not owned.has(lot):
					var definition: LotDef = CityMap.find_lot(view.lots, lot)
					var state: CityMap.LotState = CityMap.lot_state(definition, false, view.career_tier, view.reputation)
					if state != CityMap.LotState.UNLISTED:
						list.add_child(_make_lot(definition, state, view))
	_build_map(map, view, owned)
	_refresh_bar_and_detail()
	# A site on a lot no neighbourhood lists (the data check prevents it):
	# still shown, so it can always be reached.
	for site: ChainSummary.Site in view.sites:
		if not shown.has(site.id):
			list.add_child(_make_site(site, view.refusals.get(site.id, "")))
			_site_ids.append(site.id)


## Where a lot pin sits: below its neighbourhood's label, the area's lots
## spread side by side (`index` of `count`), kept on the map. Map units.
static func pin_position(area_position: Vector2, index: int, count: int, spread: float = PIN_SPREAD) -> Vector2:
	var offset: float = (float(index) - float(maxi(count, 1) - 1) / 2.0) * spread
	return Vector2(clampf(area_position.x + offset, 0.0, 1.0), clampf(area_position.y + PIN_DROP, 0.0, 1.0))


## The pins on the map view, for tests and the art pass.
func pins() -> Array[CityPin]:
	var found: Array[CityPin] = []
	for child: Node in (%Pins as Control).get_children():
		if child is CityPin and not child.is_queued_for_deletion():
			found.append(child as CityPin)
	return found


func _build_map(map: CityMapDef, view: View, owned: Array[StringName]) -> void:
	var pins_layer: Control = %Pins as Control
	var overlays: Control = %Overlays as Control
	for layer: Control in [pins_layer, overlays]:
		for child: Node in layer.get_children():
			layer.remove_child(child)
			child.queue_free()
	var texture: Texture2D = map_texture
	(%Background as TextureRect).texture = texture
	var has_map: bool = texture != null and map != null
	(%MapView as Control).visible = has_map
	if has_map:
		# The map view keeps the drawing's own shape, so a pin's 0..1 spot lands on
		# the drawn map whatever the window.
		(%MapView as AspectRatioContainer).ratio = float(texture.get_width()) / float(maxi(texture.get_height(), 1))
	_size_map_view()
	_apply_mode()
	if not has_map:
		return
	for area: NeighbourhoodDef in map.neighbourhoods:
		if area == null:
			continue
		var half: Vector2 = Vector2(NAME_LETTER * area.display_name.length() + NAME_ENDS, NAME_HEIGHT) / 2.0
		var area_pin: CityPin = _add_pin(pins_layer, area.id, CityPin.AREA, area.display_name, "", area.map_position)
		area_pin.set_meta(&"half", half)
		area_pin.set_meta(&"area", area.id)
		_add_area_sign(overlays, map, area, view, owned)
		var shown: Array[Array] = []
		for lot: StringName in area.lots:
			var site: ChainSummary.Site = _site_on(view.sites, lot)
			if site != null:
				shown.append([site.id, CityPin.SHOP, site.name, ChainText.pin_badge(site), ChainText.pin_state(site)])
				continue
			var definition: LotDef = CityMap.find_lot(view.lots, lot)
			var state: CityMap.LotState = CityMap.lot_state(definition, owned.has(lot), view.career_tier, view.reputation)
			if state == CityMap.LotState.FOR_SALE:
				shown.append([lot, CityPin.FOR_SALE, definition.display_name, ChainText.FOR_SALE_BADGE, &""])
			elif state == CityMap.LotState.LOCKED:
				shown.append([lot, CityPin.LOCKED, definition.display_name, ChainText.LOCKED_BADGE, &""])
		for index: int in range(shown.size()):
			var entry: Array = shown[index]
			var lot_pin: CityPin = _add_pin(pins_layer, entry[0], entry[1], entry[2], entry[3],
				pin_position(area.map_position, index, shown.size()), entry[4])
			lot_pin.set_meta(&"area", area.id)
			lot_pin.set_meta(&"slot", [area.map_position, index, shown.size()])
	_relayout()


func _add_pin(layer: Control, id: StringName, kind: StringName, title: String, badge: String, at: Vector2,
		state: StringName = &"") -> CityPin:
	var pin: CityPin = PIN_SCENE.instantiate() as CityPin
	pin.name = "Pin_%s" % id
	layer.add_child(pin)
	pin.set_pin(id, kind, title, badge, state)
	pin.set_meta(&"map_at", at)
	pin.pin_pressed.connect(_on_pin_pressed)
	return pin


## Roadworks on the road into an area waiting on a tier, or a hoarding over an
## area with no lot yet (T4), with a tag saying what opens it.
func _add_area_sign(layer: Control, map: CityMapDef, area: NeighbourhoodDef, view: View,
		owned: Array[StringName]) -> void:
	var state: CityMap.AreaState = CityMap.area_state(area, view.lots, owned, view.career_tier, view.reputation)
	if state != CityMap.AreaState.LOCKED and state != CityMap.AreaState.COMING_SOON:
		return
	var coming: bool = state == CityMap.AreaState.COMING_SOON
	var picture: TextureRect = TextureRect.new()
	picture.name = "Hoarding_%s" % area.id if coming else "Roadworks_%s" % area.id
	picture.texture = HOARDING_ART if coming else ROADWORKS_ART
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_meta(&"area", area.id)
	picture.set_meta(&"coming", coming)
	layer.add_child(picture)
	var tag: Label = Label.new()
	tag.name = "Tag"
	tag.text = ChainText.area_line(state, CityMap.opening_tier(area, view.lots), area.coming_soon,
		view.career_tier, _area_lock(area, view))
	tag.add_theme_color_override(&"font_color", INK_COLOR)
	tag.add_theme_stylebox_override(&"normal", _tag_style())
	tag.set_meta(&"words", tag.text)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	picture.add_child(tag)


func _tag_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = _strip_style(2.0)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


## Lays the pins and signs out on the drawn map from their 0..1 spots, at the
## map's current size (the Canvas is exactly the drawing's shape).
func _relayout() -> void:
	var canvas: Control = %Canvas as Control
	var size: Vector2 = canvas.size
	if size.x < 1.0 or size.y < 1.0:
		return
	var icon: int = clampi(roundi(size.x * ICON_RATIO), ICON_MIN, ICON_MAX)
	var compact: bool = size.x < COMPACT_WIDTH
	var font: int = 11 if compact else 14
	# The name banners, which no pin's picture or words may cover.
	var keep_clear: Array[Rect2] = []
	for pin: CityPin in pins():
		if pin.kind == CityPin.AREA:
			keep_clear.append(_pin_rect(pin, size))
	for pin: CityPin in pins():
		var at: Vector2 = pin.get_meta(&"map_at", Vector2(0.5, 0.5))
		if pin.kind == CityPin.AREA:
			var half: Vector2 = pin.get_meta(&"half", Vector2(0.1, 0.04))
			pin.position = (at - half) * size
			pin.size = half * 2.0 * size
			continue
		pin.set_compact(compact)
		pin.add_theme_font_size_override(&"font_size", font)
		pin.add_theme_constant_override(&"icon_max_width", icon)
		# As wide as its words need (a state word on a small map must not wrap).
		var words: float = 0.0
		for line: String in pin.text.split("\n"):
			words = maxf(words, pin.get_theme_font(&"font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font).x)
		pin.custom_minimum_size = Vector2(maxf(icon * 1.5, words + 24.0), 0.0)
		pin.reset_size()
		# The picture, not the whole button, sits on the pin's spot. A pin never
		# sits closer to its neighbour than its own width, and the whole pin (its
		# words too) stays on the paper: it slides up from a bottom edge.
		var slot: Array = pin.get_meta(&"slot", [Vector2.ZERO, 0, 1])
		var spread: float = maxf(PIN_SPREAD, (pin.size.x + 6.0) / size.x)
		at = pin_position(slot[0], slot[1], slot[2], spread)
		# The picture sits just under its area's name banner, whatever the icon's size.
		at.y = slot[0].y + (NAME_HEIGHT / 2.0) + (icon / 2.0 + 4.0) / size.y
		var margin: float = size.x * EDGE_MARGIN
		# What is drawn (the picture and its words), not the button's roomier box.
		var ink: Vector2 = pin_ink_size(pin)
		var top_left: Vector2 = at * size - Vector2(ink.x / 2.0, icon / 2.0)
		top_left.x = clampf(top_left.x, margin, size.x - margin - ink.x)
		top_left.y = clampf(top_left.y, margin, size.y - margin - ink.y)
		top_left = _clear_spot(top_left, ink, keep_clear, Rect2(Vector2.ZERO, size).grow(-margin))
		keep_clear.append(Rect2(top_left, ink))
		pin.position = top_left
		pin.set_meta(&"map_at", (top_left + Vector2(ink.x / 2.0, icon / 2.0)) / size)
	var placed: Array[Rect2] = []
	# Top of the map first, so a sign by the northern area gets the room beside it.
	var pictures: Array[TextureRect] = []
	for picture: Node in (%Overlays as Control).get_children():
		if picture is TextureRect:
			pictures.append(picture as TextureRect)
	pictures.sort_custom(func(first: TextureRect, second: TextureRect) -> bool:
		return _banner_rect(StringName(first.get_meta(&"area", &""))).position.y \
			< _banner_rect(StringName(second.get_meta(&"area", &""))).position.y)
	for picture: TextureRect in pictures:
		placed.append(_place_sign(picture, size, font, placed))


## Where a pin of `extent` goes: `wanted` if it covers nothing in `others`,
## else the nearest spot (searched in up to 60 px) that does, kept
## inside `bounds`; `wanted` again if the map has no such spot.
static func _clear_spot(wanted: Vector2, extent: Vector2, others: Array[Rect2], bounds: Rect2) -> Vector2:
	if not _covers_any(Rect2(wanted, extent), others):
		return wanted
	var best: Vector2 = wanted
	var nearest: float = INF
	for dy: int in range(-60, 61, 6):
		for dx: int in range(-60, 61, 6):
			var spot: Vector2 = wanted + Vector2(dx, dy)
			var rect: Rect2 = Rect2(spot, extent)
			var distance: float = Vector2(dx, dy).length()
			if distance < nearest and bounds.encloses(rect) and not _covers_any(rect, others):
				nearest = distance
				best = spot
	return best


## Puts a roadworks or hoarding picture (and its tag) beside its area's name
## banner, on the first side where it covers no name banner, no pin and no sign
## placed before it (`placed`): roadworks right, above, left, below; a hoarding
## below, above, right, left (an area with no lot has nothing under its name).
## A crowded corner tries the sides slid along the banner, then the nearest
## clear spot on the map, then a smaller picture. Returns the rect it took.
func _place_sign(sign_rect: TextureRect, size: Vector2, font: int, placed: Array[Rect2]) -> Rect2:
	var compact: bool = size.x < COMPACT_WIDTH
	var full_width: float = maxf(size.x * SIGN_WIDTH, 72.0)
	var ratio: float = float(sign_rect.texture.get_height()) / float(sign_rect.texture.get_width())
	var tag: Label = sign_rect.get_node("Tag") as Label
	tag.add_theme_font_size_override(&"font_size", font)
	# A small map has no room for the tag: tapping the area's name shows the same line.
	tag.visible = not compact
	var area_id: StringName = StringName(sign_rect.get_meta(&"area", &""))
	var banner: Rect2 = _banner_rect(area_id)
	var coming: bool = bool(sign_rect.get_meta(&"coming", false))
	var bounds: Rect2 = Rect2(Vector2.ZERO, size).grow(-size.x * EDGE_MARGIN)
	# Everything a sign keeps clear of: every name banner and pin (the signs
	# stand where nothing is lettered) and the signs already placed.
	var taken: Array[Rect2] = placed.duplicate()
	for pin: CityPin in pins():
		taken.append(_pin_rect(pin, size))
	# Wrapped by hand: an autowrap label sizes its height a frame late.
	tag.text = _wrapped(String(tag.get_meta(&"words", tag.text)), tag.get_theme_font(&"font"), font,
		maxf(full_width * 1.3, 110.0 if compact else 0.0) - 20.0)
	tag.custom_minimum_size = Vector2.ZERO
	tag.reset_size()
	# The sign at full size, then smaller: each side is tried at every size
	# before the next side, so a crowded corner shrinks the sign rather than
	# sending it away from its area.
	var shapes: Array[Vector2] = []
	var wholes: Array[Vector2] = []
	for shrink: float in [1.0, 0.85, 0.7, 0.6]:
		var shape: Vector2 = Vector2(full_width, full_width * ratio) * shrink
		shapes.append(shape)
		wholes.append(shape if compact else Vector2(maxf(shape.x, tag.size.x), shape.y + 2.0 + tag.size.y))
	var found: Array = _sign_spot(banner, wholes, coming, bounds, taken)
	var index: int = found[2]
	var shape: Vector2 = shapes[index]
	var whole: Vector2 = wholes[index]
	var chosen: Vector2 = found[0]
	sign_rect.size = shape
	sign_rect.position = chosen + Vector2((whole.x - shape.x) / 2.0, 0.0)
	tag.position = Vector2((shape.x - tag.size.x) / 2.0, shape.y + 2.0)
	return Rect2(chosen, whole)


## Where a sign by `banner` goes, for the sign's `wholes` (picture and tag, big
## to small): [top-left, px of overlap with `taken`, which size]. The sides in
## order, each at every size and slid along the banner by half and a whole
## sign; with none clear, the nearest clear spot on the map at the third size.
func _sign_spot(banner: Rect2, wholes: Array[Vector2], coming: bool, bounds: Rect2, taken: Array[Rect2]) -> Array:
	var order: Array[StringName] = [&"right", &"above", &"left", &"below", &"below_right", &"below_left", &"above_left"]
	if coming:
		order = [&"below", &"above", &"right", &"left", &"below_right", &"below_left", &"above_left"]
	var chosen: Vector2 = Vector2.ZERO
	var least: float = INF
	var which: int = 0
	for spot: StringName in order:
		var sideways: bool = String(spot).begins_with("left") or String(spot).begins_with("right")
		# Unslid first (at every size), then slid half a sign, then a whole one.
		for slide: float in [0.0, -0.5, 0.5, -1.0, 1.0]:
			for index: int in range(wholes.size()):
				var whole: Vector2 = wholes[index]
				var base_spots: Dictionary = {
					&"right": Vector2(banner.end.x + 6.0, banner.get_center().y - whole.y / 2.0),
					&"left": Vector2(banner.position.x - 6.0 - whole.x, banner.get_center().y - whole.y / 2.0),
					&"above": Vector2(banner.end.x - whole.x, banner.position.y - 4.0 - whole.y),
					&"below": Vector2(banner.position.x + (banner.size.x - whole.x) / 2.0, banner.end.y + 4.0),
					&"below_left": Vector2(banner.position.x, banner.end.y + 4.0),
					&"below_right": Vector2(banner.end.x - whole.x, banner.end.y + 4.0),
					&"above_left": Vector2(banner.position.x, banner.position.y - 4.0 - whole.y),
				}
				var base: Vector2 = base_spots[spot]
				base += Vector2(0.0, slide * whole.y) if sideways else Vector2(slide * whole.x, 0.0)
				var at: Vector2 = base.clamp(bounds.position, bounds.end - whole)
				var covered: float = 0.0
				for other: Rect2 in taken:
					covered += Rect2(at, whole).intersection(other).get_area()
				if covered < least:
					least = covered
					chosen = at
					which = index
				if covered == 0.0:
					return [chosen, 0.0, which]
	var whole: Vector2 = wholes[mini(2, wholes.size() - 1)]
	var nearest: float = INF
	var y: float = bounds.position.y
	while y <= bounds.end.y - whole.y:
		var x: float = bounds.position.x
		while x <= bounds.end.x - whole.x:
			var candidate: Rect2 = Rect2(Vector2(x, y), whole)
			var distance: float = candidate.get_center().distance_to(banner.get_center())
			if distance < nearest and not _covers_any(candidate, taken):
				nearest = distance
				chosen = candidate.position
				least = 0.0
				which = mini(2, wholes.size() - 1)
			x += 8.0
		y += 8.0
	return [chosen, least, which]


## True when `rect` overlaps any of `others` (a pixel of air counts as touching).
static func _covers_any(rect: Rect2, others: Array[Rect2]) -> bool:
	for other: Rect2 in others:
		if rect.grow(3.0).intersects(other):
			return true
	return false


## The size of what a pin draws: its picture and its words (a button reserves
## more room under the words than they need).
static func pin_ink_size(pin: CityPin) -> Vector2:
	if pin.kind == CityPin.AREA:
		return pin.size
	var lines: int = 0 if pin.text.is_empty() else pin.text.split("\n").size()
	var font_size: int = pin.get_theme_font_size(&"font_size")
	var line: float = pin.get_theme_font(&"font").get_height(font_size)
	return Vector2(pin.size.x, minf(pin.size.y, float(pin.get_theme_constant(&"icon_max_width")) + line * float(lines)))


## A pin's rect on the map, in px: a neighbourhood's is its name banner.
func _pin_rect(pin: CityPin, size: Vector2) -> Rect2:
	if pin.kind == CityPin.AREA:
		var half: Vector2 = pin.get_meta(&"half", Vector2(0.1, 0.04))
		return Rect2((pin.get_meta(&"map_at", Vector2(0.5, 0.5)) - half) * size, half * 2.0 * size)
	return Rect2(pin.position, pin_ink_size(pin))


## Every sign on the map, the picture and its tag together, in map px, for tests.
func sign_rects() -> Array[Rect2]:
	var found: Array[Rect2] = []
	for picture: Node in (%Overlays as Control).get_children():
		if not picture is TextureRect:
			continue
		var art: TextureRect = picture as TextureRect
		var whole: Rect2 = Rect2(art.position, art.size)
		var tag: Label = art.get_node("Tag") as Label
		if tag.visible:
			whole = whole.merge(Rect2(art.position + tag.position, tag.size))
		found.append(whole)
	return found


## `words` broken into lines no wider than `width` px.
static func _wrapped(words: String, font: Font, font_size: int, width: float) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var line: String = ""
	for word: String in words.split(" "):
		var trial: String = word if line.is_empty() else "%s %s" % [line, word]
		if not line.is_empty() and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(line)
			line = word
		else:
			line = trial
	lines.append(line)
	return "\n".join(lines)


## An area's name banner on the map, in px: its pin's rect.
func _banner_rect(area_id: StringName) -> Rect2:
	var size: Vector2 = (%Canvas as Control).size
	for pin: CityPin in pins():
		if pin.kind == CityPin.AREA and pin.row_id == area_id:
			var half: Vector2 = pin.get_meta(&"half", Vector2(0.1, 0.04))
			return Rect2((pin.get_meta(&"map_at", Vector2(0.5, 0.5)) - half) * size, half * 2.0 * size)
	return Rect2()


## The market's lock line for a locked area's nearest lot (the cheapest to
## open among its locked lots), so the patch says what is really missing.
static func _area_lock(area: NeighbourhoodDef, view: View) -> String:
	var nearest: LotDef = null
	for lot: StringName in area.lots:
		var definition: LotDef = CityMap.find_lot(view.lots, lot)
		if definition == null or not PropertyMarket.locked(definition, view.career_tier, view.reputation):
			continue
		if nearest == null or definition.cost_to_open() < nearest.cost_to_open():
			nearest = definition
	return PropertyText.lock_line(nearest, view.career_tier, view.reputation) if nearest != null else ""


static func _site_on(sites: Array[ChainSummary.Site], lot: StringName) -> ChainSummary.Site:
	for site: ChainSummary.Site in sites:
		if site.lot == lot:
			return site
	return null


## Site ids in screen order, for tests and capture evidence.
func site_ids() -> Array[StringName]:
	return _site_ids.duplicate()


## Neighbourhood ids in screen order.
func area_ids() -> Array[StringName]:
	return _area_ids.duplicate()


## The row for a site, neighbourhood or lot id (meta "row_id"), or null.
func row_for(id: StringName) -> Control:
	for child: Node in (%List as VBoxContainer).get_children():
		if child.get_meta(&"row_id", &"") == id:
			return child as Control
	return null


func _add_alerts(list: VBoxContainer, sites: Array[ChainSummary.Site]) -> void:
	var alerts: Array[Dictionary] = ChainStats.alerts(sites)
	if alerts.is_empty():
		return
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Alerts"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_meta(&"row_id", &"alerts")
	list.add_child(box)
	var heading: Label = _add_label(box, "Heading", ChainText.alerts_heading(alerts.size()), NAME_FONT_SIZE)
	heading.add_theme_color_override(&"font_color", ALERT_COLOR)
	var names: Dictionary[StringName, String] = {}
	for site: ChainSummary.Site in sites:
		names[site.id] = site.name
	for index: int in range(alerts.size()):
		var entry: Dictionary = alerts[index]
		_add_label(box, "Alert%d" % index, "%s: %s" % [names.get(entry["site"], ""),
			ChainText.alert_line(int(entry["alert"]))], LINE_FONT_SIZE)


func _make_area(area: NeighbourhoodDef, view: View, owned: Array[StringName]) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Area_%s" % area.id
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_meta(&"row_id", area.id)
	box.add_theme_constant_override(&"separation", 0)
	_add_label(box, "Name", area.display_name, AREA_FONT_SIZE)
	var state: CityMap.AreaState = CityMap.area_state(area, view.lots, owned, view.career_tier, view.reputation)
	box.set_meta(&"state", state)
	var line: String = ChainText.area_line(state, CityMap.opening_tier(area, view.lots), area.coming_soon,
		view.career_tier, _area_lock(area, view))
	if not line.is_empty():
		_add_label(box, "State", line, LINE_FONT_SIZE)
	if not area.blurb.is_empty():
		_add_label(box, "Blurb", area.blurb, LINE_FONT_SIZE).add_theme_color_override(&"font_color", MUTED_COLOR)
	return box


func _make_site(site: ChainSummary.Site, refusal: String) -> Control:
	var card: PanelContainer = _card("Site_%s" % site.id, site.id)
	var body: VBoxContainer = card.get_node("Body") as VBoxContainer
	var top: HBoxContainer = _top(body)
	var title: Label = _add_label(top, "Name", site.name, NAME_FONT_SIZE)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var go: Button = Button.new()
	go.name = "Go"
	go.text = ChainText.go_label(site, refusal)
	go.disabled = site.is_active() or not refusal.is_empty()
	go.focus_mode = Control.FOCUS_NONE
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(_on_go_pressed.bind(site.id))
	top.add_child(go)
	_add_label(body, "Status", ChainText.status_line(site), LINE_FONT_SIZE)
	for pair: Array in [["Yesterday", ChainText.yesterday_line(site)], ["Tonight", ChainText.tonight_line(site)],
			["Manager", ChainText.manager_line(site)], ["Standing", ChainText.standing_line(site)]]:
		if not String(pair[1]).is_empty():
			_add_label(body, pair[0], pair[1], LINE_FONT_SIZE)
	for index: int in range(site.alerts.size()):
		_add_label(body, "Alert%d" % index, ChainText.alert_line(site.alerts[index]), LINE_FONT_SIZE) \
			.add_theme_color_override(&"font_color", ALERT_COLOR)
	return card


func _make_lot(lot: LotDef, state: CityMap.LotState, view: View) -> Control:
	var card: PanelContainer = _card("Lot_%s" % lot.id, lot.id)
	card.set_meta(&"state", state)
	var body: VBoxContainer = card.get_node("Body") as VBoxContainer
	var top: HBoxContainer = _top(body)
	var title: Label = _add_label(top, "Name", lot.display_name, NAME_FONT_SIZE)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_theme_color_override(&"font_color", MUTED_COLOR)
	if state == CityMap.LotState.FOR_SALE:
		var market: Button = Button.new()
		market.name = "Market"
		market.text = ChainText.MARKET
		market.focus_mode = Control.FOCUS_NONE
		market.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		market.pressed.connect(_on_market_pressed)
		top.add_child(market)
	var line: Label = _add_label(body, "Line", ChainText.lot_line(lot, state, view.career_tier, view.reputation),
		LINE_FONT_SIZE)
	line.add_theme_color_override(&"font_color", MUTED_COLOR if state == CityMap.LotState.FOR_SALE else ALERT_COLOR)
	return card


func _card(node_name: String, row_id: StringName) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.name = node_name
	card.theme = SHARED_THEME
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta(&"row_id", row_id)
	var style: StyleBox = SHARED_THEME.get_stylebox(&"panel", &"PanelContainer").duplicate()
	if style is StyleBoxFlat:
		var flat: StyleBoxFlat = style as StyleBoxFlat
		flat.content_margin_top = 8.0
		flat.content_margin_bottom = 8.0
		flat.border_color = SHARED_THEME.get_color(&"font_color", &"Label")
		flat.border_color.a = 0.25
		flat.set_border_width_all(2)
	card.add_theme_stylebox_override(&"panel", style)
	var body: VBoxContainer = VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override(&"separation", 2)
	card.add_child(body)
	return card


func _top(body: VBoxContainer) -> HBoxContainer:
	var top: HBoxContainer = HBoxContainer.new()
	top.name = "Top"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", 12)
	body.add_child(top)
	return top


func _add_label(parent: Control, node_name: String, text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	parent.add_child(label)
	return label


## A pin shows its card under the map (the list is the other view).
func _on_pin_pressed(row_id: StringName) -> void:
	_select(row_id)


## The card under the map for a pin or an alert, built like the list's row.
func _select(id: StringName) -> void:
	_selected = id
	_refresh_bar_and_detail()


## For the review fixture: as if the owner tapped that pin.
func pin_pressed_for_review(id: StringName) -> void:
	_select(id)


## The pin whose card shows under the map, or "".
func selected_id() -> StringName:
	return _selected


## Rebuilds the alerts bar and the selected pin's card from the current data.
func _refresh_bar_and_detail() -> void:
	var detail: VBoxContainer = %Detail as VBoxContainer
	for child: Node in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	if _view != null and _map != null:
		var card: Control = _card_for(_selected)
		if card == null:
			_selected = &""
			var hint: Label = _add_label(detail, "Hint", ChainText.SELECT_HINT, LINE_FONT_SIZE)
			hint.add_theme_color_override(&"font_color", MUTED_COLOR)
		else:
			detail.add_child(card)
	_build_alerts_bar()


func _card_for(id: StringName) -> Control:
	for site: ChainSummary.Site in _view.sites:
		if site.id == id:
			return _make_site(site, _view.refusals.get(site.id, ""))
	for area: NeighbourhoodDef in _map.neighbourhoods:
		if area == null:
			continue
		if area.id == id:
			return _make_area(area, _view, _owned)
		for lot: StringName in area.lots:
			if lot == id and not _owned.has(lot):
				var definition: LotDef = CityMap.find_lot(_view.lots, lot)
				var state: CityMap.LotState = CityMap.lot_state(definition, false, _view.career_tier, _view.reputation)
				if state != CityMap.LotState.UNLISTED:
					return _make_lot(definition, state, _view)
	return null


## The bottom bar: how many things need you, each one a button that picks its shop.
func _build_alerts_bar() -> void:
	var bar: PanelContainer = %AlertsBar as PanelContainer
	var flow: VBoxContainer = %Lines as VBoxContainer
	for child: Node in flow.get_children():
		flow.remove_child(child)
		child.queue_free()
	var sites: Array[ChainSummary.Site] = _view.sites if _view != null else ([] as Array[ChainSummary.Site])
	var alerts: Array[Dictionary] = ChainStats.alerts(sites)
	bar.set_meta(&"count", alerts.size())
	if alerts.is_empty():
		bar.visible = false
		return
	var heading: Label = Label.new()
	heading.name = "Heading"
	heading.text = ChainText.alerts_heading(alerts.size())
	heading.add_theme_color_override(&"font_color", ALERT_COLOR)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_child(heading)
	var names: Dictionary[StringName, String] = {}
	for site: ChainSummary.Site in sites:
		names[site.id] = site.name
	for index: int in range(mini(alerts.size(), BAR_ALERTS)):
		var entry: Dictionary = alerts[index]
		var button: Button = Button.new()
		button.name = "Alert%d" % index
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text = "%s: %s" % [names.get(entry["site"], ""), ChainText.alert_line(int(entry["alert"]))]
		button.pressed.connect(_select.bind(entry["site"]))
		flow.add_child(button)
	if alerts.size() > BAR_ALERTS:
		var more: Label = Label.new()
		more.name = "More"
		more.text = ChainText.more_line(alerts.size() - BAR_ALERTS)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flow.add_child(more)
	_apply_mode()


## Shows the map or the plain list. With no map art there is only the list.
func _apply_mode() -> void:
	var has_map: bool = (%MapView as Control).visible
	var show_map: bool = has_map and not _list_mode
	(%MapPage as Control).visible = show_map
	(get_node("Panel/Content/Scroll") as Control).visible = not show_map
	(%Intro as Control).visible = not show_map
	(%ViewToggle as Button).visible = has_map
	(%ViewToggle as Button).text = ChainText.SHOW_MAP if _list_mode else ChainText.SHOW_LIST
	var bar: Control = %AlertsBar as Control
	bar.visible = show_map and int(bar.get_meta(&"count", 0)) > 0


## True while the map (not the list) is the view.
func is_map_showing() -> bool:
	return (%MapPage as Control).visible


func _on_view_toggle_pressed() -> void:
	_list_mode = not _list_mode
	_apply_mode()


func _on_go_pressed(site_id: StringName) -> void:
	site_chosen.emit(site_id)


func _on_market_pressed() -> void:
	market_requested.emit()


func _on_close_pressed() -> void:
	close_requested.emit()
