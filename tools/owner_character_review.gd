extends "res://src/world/main.gd"
## Deterministic, unsaved review of the production picker and chosen owner.


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	var stage: String = OS.get_environment("OWNER_REVIEW_STAGE")
	if stage == "picker":
		if not show_owner_picker():
			push_error("Owner review could not open the picker")
			return
		_owner_picker.choose(&"character-female-e")
		(_owner_picker.get_node("%OwnerName") as LineEdit).text = "Morgan"
	elif stage == "shop":
		if not owner_set_appearance(&"character-female-e", "Morgan") \
				or not select_agent(sim.owner_agent().id):
			push_error("Owner review could not present the chosen owner")
			return
	else:
		push_error("Owner review needs a picker or shop stage")
		return
	print("OWNER_REVIEW ", JSON.stringify({"stage": stage, "seed": 1,
		"fixture": "presentation choices only; saves disabled", "use_saves": use_saves}))
