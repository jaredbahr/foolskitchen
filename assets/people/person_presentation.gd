class_name PersonPresentation
extends RefCounted
## Pure view choices. These never read or change the simulation or random streams.

const MODEL_DIRECTORY: String = "res://assets/kenney/characters/"
const COOK_MODEL: StringName = &"character-male-b"
# The male-d torso uses the kit's dark charcoal palette column.
const SERVER_MODEL: StringName = &"character-male-d"
const OWNER_MODEL: StringName = &"character-male-a"
# Both b models are reserved for cooks; owner and server looks stay distinct.
const GUEST_MODELS: Array[StringName] = [
	&"character-female-a", &"character-female-c", &"character-female-d",
	&"character-female-e", &"character-female-f", &"character-male-c",
	&"character-male-e", &"character-male-f",
]
const CLIPS: Array[StringName] = [
	&"idle", &"walk", &"sit", &"holding-both", &"interact-right",
]
# Rest-pose head mesh maxima read from the vendored GLB POSITION accessors.
# These are source measurements, before the single shared character scale.
const HEAD_TOPS: Dictionary[StringName, float] = {
	&"character-male-a": 0.671325, &"character-male-b": 0.661325,
	&"character-male-c": 0.792791, &"character-male-d": 0.721762,
	&"character-male-e": 0.675967, &"character-male-f": 0.671325,
	&"character-female-a": 0.775528, &"character-female-c": 0.775528,
	&"character-female-d": 0.775528, &"character-female-e": 0.716475,
	&"character-female-f": 0.671325,
}


static func model_for(role: StringName, guest_id: int = 0) -> StringName:
	match role:
		&"cook":
			return COOK_MODEL
		&"server":
			return SERVER_MODEL
		&"owner":
			return OWNER_MODEL
		&"customer", &"guest":
			# Avoid abs(INT64_MIN) and use no RNG, including for negative IDs.
			var count: int = GUEST_MODELS.size()
			var index: int = ((guest_id % count) + count) % count
			return GUEST_MODELS[index]
	# ART_STYLE section 4 does not yet approve a Cleaner model. No substitute look.
	return &""


static func model_path_for(role: StringName, guest_id: int = 0) -> String:
	var model: StringName = model_for(role, guest_id)
	return "" if model == &"" else MODEL_DIRECTORY + String(model) + ".glb"


static func has_chef_hat(role: StringName) -> bool:
	return role == &"cook"


static func source_head_top(model: StringName) -> float:
	return HEAD_TOPS.get(model, 0.0)


## Seat arrival wins, then carrying holds both hands, then walking, then work.
## Callers derive these flags from actual state, not task labels or future goals.
## This single-clip selection does not layer walk legs beneath a carrying pose.
static func clip_for_state(moving: bool, seated: bool, carrying: bool, working: bool) -> StringName:
	if seated:
		return &"sit"
	if carrying:
		return &"holding-both"
	if moving:
		return &"walk"
	if working:
		return &"interact-right"
	return &"idle"
