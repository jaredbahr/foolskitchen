extends "res://src/world/main.gd"
## Unsaved candidate fixture for both new traits in the real Staff panel.

var _review_frame: int = 0
var _review_ready: bool = false


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 377
	super._ready()
	Clock.set_speed(0)
	var roster: Dictionary = staff_roster.to_dict()
	var candidates: Array = roster["candidates"]
	if candidates.size() < 2:
		push_error("Staff traits review needs two hiring candidates.")
		return
	candidates[0]["trait"] = "night_owl"
	var server: Dictionary = candidates[1]
	server["trait"] = "neat_freak"
	server["role"] = "server"
	server["wage"] = TUNING.staff_wage(&"server", int(server["skill"]))
	server.erase("growth")
	server.erase("priorities")
	if not staff_roster.from_dict(roster) or not set_staff_visible(true):
		push_error("Staff traits review could not display the staged candidates.")
		return
	_review_ready = true


func _process(_delta: float) -> void:
	if not _review_ready:
		return
	_review_frame += 1
	if _review_frame not in [25, 45]:
		return
	var candidates: Array[StaffMember] = staff_roster.candidates()
	var scroll: ScrollContainer = _staff_panel.get_node("Panel/Content/Scroll") as ScrollContainer
	if _review_frame == 25:
		scroll.ensure_control_visible(_staff_panel.row_for(candidates[1].id))
		return
	for index: int in 2:
		var row: Control = _staff_panel.row_for(candidates[index].id)
		var label: Label = row.get_node_or_null("Trait") as Label if row != null else null
		var definition: StaffTrait = staff_roster.catalogue.find_trait(candidates[index].trait_id)
		if label == null or definition == null or not label.is_visible_in_tree() \
				or not scroll.get_global_rect().grow(1.0).encloses(label.get_global_rect()) \
				or label.text != "%s: %s" % [definition.display_name, definition.description_for(candidates[index].role)]:
			push_error("Staff traits review could not read a visible candidate description.")
			return
		print("STAFF_TRAITS_REVIEW " + label.text)
