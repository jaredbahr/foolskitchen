extends "res://src/world/main.gd"
## Explicit, unsaved FK-076 fixture: seed 126, level 5 and $2,000 to prepare
## seafood equipment, five selected dishes and the authored Deck planks floor.
## SEAFOOD_REVIEW_STAGE=floor|menu chooses the furnished floor or menu detail.


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 126
	super._ready()
	set_process(false)
	Clock.set_speed(0)
	var stage: String = OS.get_environment("SEAFOOD_REVIEW_STAGE")
	if stage not in ["floor", "menu"]:
		push_error("Seafood review requires a floor or menu stage")
		return
	Economy.add_cash(2000, Ledger.OTHER)
	owner_progress.award_bonus(owner_progress.threshold_for(5))
	shop_editor.set_owner_level(5)
	menu_settings.set_owner_level(5)
	_build_catalogue.set_owner_level(5)
	$HUD.set_owner_progress(owner_progress.level, owner_progress.xp_into_level(), owner_progress.xp_in_level())
	if not shop_buy(&"fryer", Vector2i(9, 3), 0) or not shop_buy(&"freezer", Vector2i(12, 3), 0) \
			or not shop_buy(&"fridge", Vector2i(11, 1), 2) or not shop_buy(&"storage_shelf", Vector2i(3, 1), 2):
		push_error("Seafood review could not prepare the normal kitchen equipment")
		return
	for id: StringName in [&"fish_and_chips", &"mussels_broth", &"salmon_maki", &"shrimp_skewer", &"seafood_stew"]:
		if not menu_set_enabled(id, true):
			push_error("Seafood review could not select " + String(id))
			return
	var style: FloorStyleDef = content.floor_style(&"deck_planks")
	var cells: Array[Vector2i] = shop_editor.floor_room_cells(Vector2i(3, 8))
	if not shop_flooring(shop_editor.lay_changes(cells, style.id, style.default_swatch, style.default_accent)):
		push_error("Seafood review could not lay the dining room floor")
		return
	for cell: Vector2i in cells:
		if shop_editor.floors.finish(cell).style != style.id:
			push_error("Seafood review is missing an authored Deck planks cell")
			return
	if stage == "menu" and (not set_menu_visible(true) or not _menu_panel.select_recipe(&"seafood_stew")):
		push_error("Seafood review could not show its menu branch and stew detail")
		return
	print("SEAFOOD_REVIEW ", JSON.stringify({"stage": stage, "fixture": "seed126; extra $2000; ownerlevel5; savesdisabled",
		"floor_style": String(style.id), "floor_pattern": int(style.pattern), "floor_cells": cells.size(),
		"enabled_dishes": menu_settings.enabled_count(), "use_saves": use_saves}))
