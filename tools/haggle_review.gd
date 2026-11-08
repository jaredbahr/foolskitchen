extends "res://src/world/main.gd"
## Unsaved seed-327 UI fixture. Real stock disposal/cart and three production
## Space stops at staged 60%-score times; no injected result, cash or supplies.
## Two photos: active game at frame30, actual 6%-off Stock panel at frame90.

var _review_frame: int = 0
var _review_game: HaggleGame


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 327
	super._ready()
	Clock.set_speed(0)
	for id: StringName in Economy.stock.ids():
		stock_throw_out(id)
	if not stock_cart_set(&"tomato", 20) or not set_stock_visible(true):
		push_error("Haggle review cannot prepare its real morning cart")
		return
	stock_start_haggle()
	_review_game = get_node("Overlay/HaggleGame") as HaggleGame
	_review_game.set_process(false)
	print("HAGGLE REVIEW: unsaved seed327; starter stock thrown out,20 tomatoes in cart; staged Space timing, no injected result")


func _process(delta: float) -> void:
	super._process(delta)
	if _review_game == null:
		return
	_review_frame += 1
	match _review_frame:
		10, 62, 65:
			var observation: Dictionary = _review_game.snapshot()
			var index: int = int(observation["round"])
			var marker: float = float(observation["centers"][index]) - HAGGLE_TUNING.zone_widths[index] * 0.2
			_review_game.call("_process", marker / HAGGLE_TUNING.speeds[index])
		25:
			if not is_haggle_active() or not _review_game.running:
				push_error("Haggle review's first photo must show the active game")
			_print_review_state()
		60, 63, 66:
			_send_space(true)
		61, 64, 67:
			_send_space(false)
		80:
			if is_haggle_active() or stock_haggle_percent() != 6 or stock_cart_total() != 19:
				push_error("Haggle review did not produce the actual 6%-off, $19 cart")
			_print_review_state()


func _send_space(pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)


func _print_review_state() -> void:
	print("HAGGLE REVIEW STATE ", JSON.stringify({"frame": _review_frame, "fixture": "unsaved, staged real Space timing",
		"game": _review_game.snapshot(), "phase": Clock.phase, "tick": Clock.tick,
		"speed": Clock.speed, "cash": Economy.cash, "percent": stock_haggle_percent(),
		"list_total": stock_cart_list_total(), "charge": stock_cart_total(),
		"panel_visible": is_stock_visible(), "panel_label": ($Overlay/StockPanel/%HaggleResult as Label).text,
		"rngs": GameState._capture_save()["rngs"]}))
