class_name PropertyPanel
extends Control
## The property market screen (FK-087, D28). One card per lot, cheapest
## first, with its price, size, rent, guests, perks, any lock and a Buy
## button: enabled with the cost when the lot can be bought now (#464),
## otherwise disabled with the reason on the card. Buying is main.gd's
## `buy_lot`, asked for through `buy_requested`.

signal close_requested()
signal buy_requested(lot_id: StringName)

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
## The Menu panel's muted and warning tones, so the screens read as one.
const MUTED_COLOR: Color = Color("766b60")
const LOCK_COLOR: Color = Color("a83e35")
const NAME_FONT_SIZE: int = 20
const LINE_FONT_SIZE: int = 16

var _ids: Array[StringName] = []


func _ready() -> void:
	# One wheel step everywhere, and the wheel works over the whole card (#497).
	PanelScroll.attach(self, $Panel as Control, $Panel/Content/Scroll as ScrollContainer)
	(%Intro as Label).text = PropertyText.INTRO
	(%EmptyState as Label).text = PropertyText.EMPTY
	(get_node("Panel/Content/Header/Title") as Label).text = PropertyText.TITLE


## What the owner has, for the Buy buttons: detached values, read only.
class Buyer extends RefCounted:
	var career_tier: int = 1
	## The closing reputation (NAN before the first close).
	var reputation: float = NAN
	var site_count: int = 1
	var owned_lots: Array[StringName] = []
	var limits: SiteLimitTuning
	var cash: int = 0
	var loan: int = 0


## Detached display inputs; the session owns the lots and the buyer's state.
func set_market(lots: Array[LotDef], buyer: Buyer, catalogue: CustomerTypeCatalogue) -> void:
	var list: VBoxContainer = %List as VBoxContainer
	for child: Node in list.get_children():
		if child.name != "EmptyState":
			list.remove_child(child)
			# Queued: a Buy button may be the one emitting right now.
			child.queue_free()
	_ids.clear()
	for lot: LotDef in PropertyMarket.listing(lots):
		list.add_child(_make_card(lot, buyer, catalogue, _ids.size()))
		_ids.append(lot.id)
	(%EmptyState as Label).visible = _ids.is_empty()


## Listed lot ids in screen order, for tests and capture evidence.
func lot_ids() -> Array[StringName]:
	return _ids.duplicate()


func card_for(id: StringName) -> Control:
	for child: Node in (%List as VBoxContainer).get_children():
		if child.get_meta(&"lot_id", &"") == id:
			return child as Control
	return null


func _make_card(lot: LotDef, buyer: Buyer, catalogue: CustomerTypeCatalogue, index: int) -> Control:
	var career_tier: int = buyer.career_tier
	var reputation: float = buyer.reputation
	var card: PanelContainer = PanelContainer.new()
	card.name = "Lot%d" % index
	card.theme = SHARED_THEME
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta(&"lot_id", lot.id)
	var lock: String = PropertyText.lock_line(lot, career_tier, reputation)
	card.set_meta(&"locked", not lock.is_empty())
	var refusal: PropertyMarket.Refusal = PropertyMarket.purchase_refusal(lot, career_tier, reputation,
		buyer.owned_lots.has(lot.id), buyer.site_count, buyer.limits, buyer.cash, buyer.loan)
	card.set_meta(&"refusal", refusal)
	var style: StyleBox = SHARED_THEME.get_stylebox(&"panel", &"PanelContainer").duplicate()
	if style is StyleBoxFlat:
		var flat: StyleBoxFlat = style as StyleBoxFlat
		flat.content_margin_top = 10.0
		flat.content_margin_bottom = 10.0
		flat.border_color = SHARED_THEME.get_color(&"font_color", &"Label")
		flat.border_color.a = 0.25
		flat.set_border_width_all(2)
	card.add_theme_stylebox_override(&"panel", style)
	var body: VBoxContainer = VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override(&"separation", 2)
	card.add_child(body)
	var top: HBoxContainer = HBoxContainer.new()
	top.name = "Top"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", 12)
	body.add_child(top)
	var title: Label = _add_label(top, "Name", lot.display_name, NAME_FONT_SIZE)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var buy: Button = Button.new()
	buy.name = "Buy"
	buy.text = PropertyText.buy_label(lot, refusal)
	var reason: String = PropertyText.refusal_line(lot, refusal, buyer.cash, buyer.site_count, buyer.limits)
	buy.tooltip_text = reason if not reason.is_empty() else lock
	buy.disabled = refusal != PropertyMarket.Refusal.NONE
	buy.focus_mode = Control.FOCUS_NONE
	buy.pressed.connect(_on_buy_pressed.bind(lot.id))
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(buy)
	var blurb: Label = _add_label(body, "Blurb", lot.blurb, LINE_FONT_SIZE)
	blurb.add_theme_color_override(&"font_color", MUTED_COLOR)
	_add_label(body, "Price", "%s · %s" % [PropertyText.price_line(lot), PropertyText.size_line(lot)], LINE_FONT_SIZE)
	_add_label(body, "Rent", "%s · %s" % [PropertyText.rent_line(lot), PropertyText.expansion_line(lot)], LINE_FONT_SIZE)
	var guests: String = PropertyText.guest_line(lot, catalogue)
	var perks: String = PropertyText.perks_line(lot)
	var feel: PackedStringArray = []
	for part: String in [guests, perks]:
		if not part.is_empty():
			feel.append(part)
	if not feel.is_empty():
		_add_label(body, "Guests", " · ".join(feel), LINE_FONT_SIZE)
	if not lock.is_empty():
		var locked: Label = _add_label(body, "Lock", lock, LINE_FONT_SIZE)
		locked.add_theme_color_override(&"font_color", LOCK_COLOR)
	if not reason.is_empty():
		var why: Label = _add_label(body, "Reason", reason, LINE_FONT_SIZE)
		why.add_theme_color_override(&"font_color",
			MUTED_COLOR if refusal == PropertyMarket.Refusal.OWNED else LOCK_COLOR)
	return card


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


func _on_buy_pressed(lot_id: StringName) -> void:
	buy_requested.emit(lot_id)


func _on_close_pressed() -> void:
	close_requested.emit()
