class_name PersonPresentation
extends RefCounted
## Pure view choices. These never read or change the simulation or random streams.

const MODEL_DIRECTORY: String = "res://assets/kenney/characters/"
const COOK_MODEL: StringName = &"character-male-b"
# The male-d torso uses the kit's dark charcoal palette column.
const SERVER_MODEL: StringName = &"character-male-d"
const OWNER_MODEL: StringName = &"character-male-a"
# The delivery person (FK-099): the one kit model no other role uses. ART_STYLE
# lists female-b for cooks too, but cooks use male-b; it never wears the hat.
const COURIER_MODEL: StringName = &"character-female-b"
# Delivery uniform colours (ART_STYLE section 4): no other role wears either.
const COURIER_BROWN: Color = Color("9a6a3e")
const COURIER_AMBER: Color = Color("d98e2b")
# Both b models are reserved for cooks; owner and server looks stay distinct.
const GUEST_MODELS: Array[StringName] = [
	&"character-female-a", &"character-female-c", &"character-female-d",
	&"character-female-e", &"character-female-f", &"character-male-c",
	&"character-male-e", &"character-male-f",
]
const CLIPS: Array[StringName] = [
	&"idle", &"walk", &"sit", &"holding-both", &"interact-right", &"pick-up",
]
## Built from the kit's own clips, not imported: `walk` with the arms of
## `holding-both`, so a person carrying something walks instead of gliding.
const CARRY_WALK: StringName = &"carry-walk"
## Played once (bending to a crate), then held; every other clip loops.
const ONE_SHOT_CLIPS: Array[StringName] = [&"pick-up"]
# Rest-pose head mesh maxima read from the vendored GLB POSITION accessors.
# These are source measurements, before the single shared character scale.
const HEAD_TOPS: Dictionary[StringName, float] = {
	&"character-male-a": 0.671325, &"character-male-b": 0.661325,
	&"character-male-c": 0.792791, &"character-male-d": 0.721762,
	&"character-male-e": 0.675967, &"character-male-f": 0.671325,
	&"character-female-a": 0.775528, &"character-female-b": 0.723353, &"character-female-c": 0.775528,
	&"character-female-d": 0.775528, &"character-female-e": 0.716475,
	&"character-female-f": 0.671325,
}


static func model_for(role: StringName, guest_id: int = 0, customer_type: StringName = &"regular") -> StringName:
	match role:
		&"cook":
			return COOK_MODEL
		&"server":
			return SERVER_MODEL
		&"owner":
			return OWNER_MODEL
		&"courier":
			return COURIER_MODEL
		&"customer", &"guest":
			# Reuse native, unmodified Mini rigs. Each type has a deterministic
			# pair; Regular retains its complete existing guest-id mapping.
			var models: Array[StringName] = GUEST_MODELS
			match customer_type:
				&"student":
					models = [&"character-female-f", &"character-male-f"]
				&"foodie":
					models = [&"character-female-c", &"character-male-e"]
				&"family":
					models = [&"character-female-e", &"character-male-c"]
			# Avoid abs(INT64_MIN) and use no RNG, including for negative IDs.
			var count: int = models.size()
			var index: int = ((guest_id % count) + count) % count
			return models[index]
	# ART_STYLE section 4 does not yet approve a Cleaner model. No substitute look.
	return &""


static func model_path_for(role: StringName, guest_id: int = 0, customer_type: StringName = &"regular") -> String:
	var model: StringName = model_for(role, guest_id, customer_type)
	return "" if model == &"" else MODEL_DIRECTORY + String(model) + ".glb"


static func has_chef_hat(role: StringName) -> bool:
	return role == &"cook"


## The delivery person's uniform (FK-099): a parcel-brown cap with an amber
## peak, and the shared colormap's shirt ramps repainted for her alone.
static func has_courier_cap(role: StringName) -> bool:
	return role == &"courier"


## Colormap blocks to repaint, as {rect, color}: the female-b clothes (purple
## ramp) becomes parcel brown and her sleeves and collar (yellow ramp) amber.
## Each pixel keeps its shade relative to the block's top row, so the kit's
## baked gradient survives. Only a copy is painted; other roles see the
## vendored texture.
static func uniform_recolors(role: StringName) -> Array[Dictionary]:
	if role != &"courier":
		return []
	return [
		{"rect": Rect2i(480, 256, 32, 128), "color": COURIER_BROWN},
		{"rect": Rect2i(160, 256, 32, 128), "color": COURIER_AMBER},
	]


static func source_head_top(model: StringName) -> float:
	return HEAD_TOPS.get(model, 0.0)


## One presentation limit shared with the content definition; zero is neutral.
## This validates a pose request, not physical seat-fit acceptance.
static func seated_lean_valid(degrees: float) -> bool:
	return is_finite(degrees) and degrees >= 0.0 and degrees <= ItemDef.MAX_SEATED_LEAN_DEGREES


## Seat arrival wins, then bending to set down or pick up (a crate stays in
## the hands through the bend), then carrying holds both hands (walking legs
## under them while moving), then walking, then work.
## Callers derive these flags from actual state, not task labels or future goals.
static func clip_for_state(moving: bool, seated: bool, carrying: bool, working: bool,
		bending: bool = false) -> StringName:
	if seated:
		return &"sit"
	if bending and not moving:
		return &"pick-up"
	if carrying:
		return CARRY_WALK if moving else &"holding-both"
	if moving:
		return &"walk"
	if working:
		return &"interact-right"
	return &"idle"
