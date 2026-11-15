extends "res://src/world/main.gd"
## Paused, unsaved screenshot of the regular HUD at the top of the cash range.


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	Economy.add_cash(9_999_999 - Economy.cash, Ledger.OTHER)
	for frame: int in range(4):
		await get_tree().process_frame
	var cash: Label = $HUD/Top/Row/Cash
	var day: Rect2 = $HUD/Top/Row/Day.get_global_rect()
	var settings: Rect2 = $HUD/Top/Row/Settings.get_global_rect()
	var money: Rect2 = cash.get_global_rect()
	var row_top: float = maxf(day.position.y, maxf(money.position.y, settings.position.y))
	var row_bottom: float = minf(day.end.y, minf(money.end.y, settings.end.y))
	if cash.text != "$9.9M" or cash.tooltip_text != "Available cash: $9,999,999" or row_top >= row_bottom:
		push_error("Large cash capture did not show the full HUD row and exact balance")
		return
	print("LARGE_CASH_REVIEW cash=9999999 label=%s row_height=%s" % [cash.text, row_bottom - row_top])
