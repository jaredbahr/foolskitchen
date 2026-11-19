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
## The Property screen's tones, so the screens read as one.
const MUTED_COLOR: Color = Color("766b60")
const ALERT_COLOR: Color = Color("a83e35")
const AREA_FONT_SIZE: int = 22
const NAME_FONT_SIZE: int = 20
const LINE_FONT_SIZE: int = 16

var _site_ids: Array[StringName] = []
var _area_ids: Array[StringName] = []


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


func set_city(map: CityMapDef, view: View) -> void:
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
	# A site on a lot no neighbourhood lists (the data check prevents it):
	# still shown, so it can always be reached.
	for site: ChainSummary.Site in view.sites:
		if not shown.has(site.id):
			list.add_child(_make_site(site, view.refusals.get(site.id, "")))
			_site_ids.append(site.id)


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
	var line: String = ChainText.area_line(state, CityMap.opening_tier(area, view.lots), area.coming_soon)
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


func _on_go_pressed(site_id: StringName) -> void:
	site_chosen.emit(site_id)


func _on_market_pressed() -> void:
	market_requested.emit()


func _on_close_pressed() -> void:
	close_requested.emit()
