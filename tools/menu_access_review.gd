extends "res://src/world/main.gd"
## Explicit native UI fixture: seed 1, $1500 added cash and owner level 2.
## It buys/enables Fries, then previews a plant blocking the fryer work tile.
## FK_MENU_REVIEW_STAGE=open commits through Build and opens the real shop.
## No save is read or written. Capture each stage with tools/screenshot.sh
## --scene=res://tools/menu_access_review.tscn --speed=0 --frames=12.

func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	set_process(false)
	Clock.set_speed(0)
	Economy.add_cash(1500, Ledger.OTHER)
	owner_progress.award_bonus(owner_progress.threshold_for(2))
	shop_editor.set_owner_level(owner_progress.level)
	menu_settings.set_owner_level(owner_progress.level)
	_build_catalogue.set_owner_level(owner_progress.level)
	$HUD.set_owner_progress(owner_progress.level, owner_progress.xp_into_level(), owner_progress.xp_in_level())
	if not shop_buy(&"fryer", Vector2i(10, 3), 0) or not menu_set_enabled(&"fries", true):
		push_error("Menu-access fixture could not prepare the fryer")
		return
	if not set_build_active(true):
		push_error("Menu-access fixture could not enter Build")
		return
	var plant: PlacedItem = ShopBuilder.items_with_def(world, &"potted_plant")[0]
	if not build_mode.pick_up(plant.id):
		push_error("Menu-access fixture could not pick up its blocker")
		return
	build_mode.update_origin(Vector2i(10, 2))
	if not build_mode.current_check.ok:
		push_error("Menu-access fixture blocking preview was refused")
		return
	if build_mode.current_check.menu_warning != "Fries will leave the menu: staff can't reach the fryer":
		push_error("Menu-access fixture did not show its named dish warning")
		return
	if OS.get_environment("FK_MENU_REVIEW_STAGE") == "open":
		if not build_mode.commit() or not Clock.sim.start_service():
			push_error("Menu-access fixture could not open after the edit")
			return
		Clock.set_speed(0)
		if menu_open_note() != "Fries left today's menu: staff can't reach the fryer":
			push_error("Menu-access fixture did not show its opening notice")
			return
	print("MENU_ACCESS_REVIEW fixture=blocked_fryer seed=1 added_cash=1500 owner_level=2 stage=%s" % [
		"open" if OS.get_environment("FK_MENU_REVIEW_STAGE") == "open" else "preview"])
