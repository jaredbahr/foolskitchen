extends "res://src/world/main.gd"
## Unsaved property fixture. The ordinary site switch and panels show each
## matching lot after layout settles. screenshot.gd records frames 30 and 90.

const SEASIDE: StringName = &"seaside_cliff"
const ROOFTOP: StringName = &"skyscraper_rooftop"
const CATCH: StringName = &"fresh_catch"
const COUNTER: StringName = &"cocktail_station"

var _review_frame: int = 0
var _review_failed: bool = false


func _ready() -> void:
	use_saves = false
	skip_owner_picker = true
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)


func _process(_delta: float) -> void:
	if _review_failed:
		return
	_review_frame += 1
	match _review_frame:
		4:
			_open_seaside_stock()
		15:
			var row: Control = _stock_panel.row_for(CATCH).get("root") as Control
			if row == null:
				_fail_review("Fresh catch row is missing")
				return
			var scroll: ScrollContainer = _stock_panel.get_node("Panel/Content/Scroll") as ScrollContainer
			scroll.ensure_control_visible(row)
		25:
			RenderingServer.frame_post_draw.connect(_observe_stock, CONNECT_ONE_SHOT)
		50:
			owner_progress.level = 4
			Economy.add_cash(300, Ledger.OTHER, "Review cash")
			if not set_stock_visible(false) or not switch_site(ROOFTOP) or not set_build_active(true):
				_fail_review("could not open the rooftop Build catalogue")
				return
			_build_catalogue.set_mode(BuildCatalogue.BUY)
			_build_catalogue.set_category(&"bar_cafe")
			_build_catalogue.set_group(&"tables")
		72:
			var tile: Button = _build_catalogue.item_buttons.get(COUNTER) as Button
			if tile != null:
				tile.mouse_entered.emit()
		75:
			RenderingServer.frame_post_draw.connect(_observe_build, CONNECT_ONE_SHOT)


func _open_seaside_stock() -> void:
	if sim == null:
		_fail_review("morning did not initialize")
		return
	for id: StringName in [SEASIDE, ROOFTOP]:
		var lot: LotDef = content.lot(id)
		if lot == null or not site_book.add_site(id, id, lot.display_name, Clock.sim.day, _new_site_sections(lot)):
			_fail_review("could not prepare both restaurant layouts")
			return
	if not switch_site(SEASIDE) or not set_stock_visible(true):
		_fail_review("could not open Stock at the seaside restaurant")


func _observe_stock() -> void:
	var label: Label = _stock_panel.row_for(CATCH).get("name") as Label
	var scroll: ScrollContainer = _stock_panel.get_node("Panel/Content/Scroll") as ScrollContainer
	if site_book.active_id != SEASIDE or label == null or label.text != "Fresh catch" \
			or not label.is_visible_in_tree() or not scroll.get_global_rect().encloses(label.get_global_rect()):
		_fail_review("Fresh catch is not readable in the seaside Stock panel")
		return
	print("LOT_ACCESS_REVIEW seaside stock: Fresh catch; frame 30")


func _observe_build() -> void:
	var item: Button = _build_catalogue.item_buttons.get(COUNTER) as Button
	var name: Label = _build_catalogue.get_node("HoverCard/Rows/Name") as Label
	if site_book.active_id != ROOFTOP or item == null or item.disabled or not item.is_visible_in_tree() \
			or not name.is_visible_in_tree() or name.text != "Cocktail station":
		_fail_review("Cocktail station is not available in the rooftop Buy catalogue")
		return
	print("LOT_ACCESS_REVIEW rooftop build: Cocktail station; frame 90")


func _fail_review(reason: String) -> void:
	_review_failed = true
	push_error("Lot access review: " + reason)
