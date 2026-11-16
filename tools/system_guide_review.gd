extends "res://src/world/main.gd"
## Capture the live Guide reached from the HUD on an unsaved morning.


func _ready() -> void:
	use_saves = false
	skip_owner_picker = true
	new_game_seed_override = 1
	super._ready()
	var page_title: String = OS.get_environment("SYSTEM_GUIDE_REVIEW_PAGE")
	if page_title not in ["Menu and prices", "Loans"]:
		push_error("Guide review requires Menu and prices or Loans")
		return
	($HUD/Top/Row/Guide as Button).pressed.emit()
	var topics: ItemList = $Overlay/GuidePanel/Card/Column/Pages/Topics
	for index: int in range(topics.item_count):
		if topics.get_item_text(index) != page_title:
			continue
		topics.select(index)
		topics.item_selected.emit(index)
		if not is_system_guide_visible():
			push_error("Guide review could not open the HUD panel")
			return
		print("SYSTEM_GUIDE_REVIEW ", JSON.stringify({"page": page_title, "seed": 1}))
		return
	push_error("Guide review could not find " + page_title)
