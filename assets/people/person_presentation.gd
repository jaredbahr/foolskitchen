class_name PersonPresentation
extends RefCounted
## Pure view choices. These never read or change the simulation or random streams.

const MODEL_DIRECTORY: String = "res://assets/kenney/characters/"
const COOK_MODEL: StringName = &"character-male-b"
# The male-d torso uses the kit's dark charcoal palette column.
const SERVER_MODEL: StringName = &"character-male-d"
# The delivery person (FK-099): the one kit model no other role uses. ART_STYLE
# lists female-b for cooks too, but cooks use male-b; it never wears the hat.
const COURIER_MODEL: StringName = &"character-female-b"
# Delivery uniform colours (ART_STYLE section 4): no other role wears either.
const COURIER_BROWN: Color = Color("9a6a3e")
const COURIER_AMBER: Color = Color("d98e2b")
# The health inspector (#302). Named regulars also wear this model, so the
# inspector is told apart by the slate repaint of the clothes and the clipboard.
const INSPECTOR_MODEL: StringName = &"character-female-a"
const INSPECTOR_SLATE: Color = Color("3f6577")
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
## Switching among these blends over CARRY_BLEND_SECONDS (the arms of
## `holding-both` and the `pick-up` bend's start differ by 0.2 m).
const CARRY_BLEND_CLIPS: Array[StringName] = [&"pick-up", &"holding-both", CARRY_WALK]
const CARRY_BLEND_SECONDS: float = 0.12
## The inspector's own arms (#302): bent forward, hands to the sides of the
## clipboard held at the chest, over `walk` legs (CLIPBOARD_WALK) or `idle`
## (CLIPBOARD_HOLD). Built in PersonView from the kit's own clips.
const CLIPBOARD_WALK: StringName = &"clipboard-walk"
const CLIPBOARD_HOLD: StringName = &"clipboard-hold"
## How far each rigid arm swings forward from the shoulder line, and drops.
const CLIPBOARD_ARM_YAW_DEGREES: float = 72.0
const CLIPBOARD_ARM_DROP_DEGREES: float = 35.0
## Clothing ramps measured from each kit body-mesh's torso UVs. None is a
## skin ramp; the separate head mesh always keeps its imported material.
const CLOTHING_RAMPS: Dictionary[StringName, Rect2i] = {
	&"character-female-a": Rect2i(480, 256, 32, 128),
	&"character-female-c": Rect2i(352, 256, 32, 128),
	&"character-female-d": Rect2i(96, 384, 32, 128),
	&"character-female-e": Rect2i(288, 384, 32, 128),
	&"character-female-f": Rect2i(160, 256, 32, 128),
	&"character-male-a": Rect2i(96, 256, 32, 128),
	&"character-male-c": Rect2i(352, 256, 32, 128),
	&"character-male-d": Rect2i(32, 384, 32, 128),
	&"character-male-e": Rect2i(160, 256, 32, 128),
	&"character-male-f": Rect2i(96, 256, 32, 128),
}
## Tourists (#661) wear a straw sun hat and one of two holiday shirts; the
## office crowd wear a lanyard and a navy or grey jacket over a white shirt.
## Which one follows the guest id (type_variant), never a random stream.
const TOURIST_SHIRTS: Array[Color] = [Color("f06a4f"), Color("26b9c2")]
const OFFICE_JACKETS: Array[Color] = [Color("5878c8"), Color("8a8f9c")]
## How far the hat's underside sinks into the hair below the head top.
const SUN_HAT_SINK: float = 0.04
## The hat sits a little back and tilted up at the front, so the face shows from above.
const SUN_HAT_BACK: float = -0.03
const SUN_HAT_TILT_DEGREES: float = -10.0
## Location guests (#663 #657 #658 #659): farmers wear a straw farm hat and
## denim overalls over a white or sage shirt; walkers a knit beanie and a yellow
## or green rain jacket; surfers a tank top and board shorts (aqua and orange,
## either way round) with damp, darker hair; foragers an olive or brown jacket
## and a basket on the arm. Which palette follows the guest id (type_variant).
const FARMER_SHIRTS: Array[Color] = [Color("f6efe2"), Color("8fc79a")]
const FARMER_DENIM: Color = Color("5f74cb")
const WALKER_JACKETS: Array[Color] = [Color("ffc23f"), Color("3fae7c")]
const SURFER_AQUA: Color = Color("3fd0cf")
const SURFER_ORANGE: Color = Color("ff9a3c")
const FORAGER_JACKETS: Array[Color] = [Color("7f8a45"), Color("9a6a48")]
## How dark a surfer's wet hair is against the kit's own hair colour.
const WET_HAIR_SHADE: float = 0.68
## The farm hat and beanie sit on the head top like the sun hat; the beanie
## sinks lower, over the hair line.
const FARM_HAT_SINK: float = 0.035
const FARM_HAT_BACK: float = -0.02
const FARM_HAT_TILT_DEGREES: float = -8.0
const BEANIE_SINK: float = 0.075
const BEANIE_BACK: float = -0.01
const BEANIE_TILT_DEGREES: float = -6.0
## Where the forager's basket hangs from the left hand, in the arm bone's space
## (the arm points along +X in the rest pose): its handle's inner end at the
## hand, the basket just outside it (and a little forward) so the big kit hand
## never hides it from the camera above. It is turned to hang straight down in
## the idle pose (the idle arm slopes 39 degrees off the vertical); it swings
## with the arm when walking, tilts with it when seated and hangs from the
## level forearm when carrying.
const BASKET_OFFSET: Vector3 = Vector3(0.27, 0.056, 0.03)
const BASKET_ROTATION_DEGREES: Vector3 = Vector3(0.0, 0.0, 39.0)
## The skin and hair colormap columns of each guest model's head mesh, read
## from the vendored GLBs' head-mesh UVs (the face block and the hair block).
const SKIN_COLUMNS: Dictionary[StringName, Vector2i] = {
	&"character-female-a": Vector2i(416, 384), &"character-female-c": Vector2i(352, 384),
	&"character-female-d": Vector2i(480, 384), &"character-female-e": Vector2i(480, 384),
	&"character-female-f": Vector2i(480, 384), &"character-male-c": Vector2i(480, 384),
	&"character-male-e": Vector2i(480, 384), &"character-male-f": Vector2i(352, 384),
}
const HAIR_COLUMNS: Dictionary[StringName, Vector2i] = {
	&"character-female-a": Vector2i(32, 384), &"character-female-c": Vector2i(96, 384),
	&"character-female-d": Vector2i(352, 384), &"character-female-e": Vector2i(32, 384),
	&"character-female-f": Vector2i(416, 384), &"character-male-e": Vector2i(416, 384),
	&"character-male-f": Vector2i(32, 384),
}
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


static func model_for(role: StringName, guest_id: int = 0, customer_type: StringName = &"regular",
		owner_model: StringName = OwnerAppearance.DEFAULT_MODEL) -> StringName:
	match role:
		&"cook":
			return COOK_MODEL
		&"server":
			return SERVER_MODEL
		&"owner":
			return owner_model if OwnerAppearance.valid_model(owner_model) else OwnerAppearance.DEFAULT_MODEL
		&"courier":
			return COURIER_MODEL
		&"inspector":
			return INSPECTOR_MODEL
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
				&"tourist":
					models = [&"character-female-d", &"character-male-e"]
				&"office":
					models = [&"character-female-a", &"character-male-f"]
				# Hats and beanies need a model without a bun or a cap.
				&"farmer":
					models = [&"character-female-e", &"character-male-e"]
				&"walker":
					models = [&"character-female-f", &"character-male-f"]
				&"surfer":
					models = [&"character-female-d", &"character-male-e"]
				&"forager":
					models = [&"character-female-c", &"character-male-f"]
			# Avoid abs(INT64_MIN) and use no RNG, including for negative IDs.
			var count: int = models.size()
			var index: int = ((guest_id % count) + count) % count
			return models[index]
	# ART_STYLE section 4 does not yet approve a Cleaner model. No substitute look.
	return &""


static func model_path_for(role: StringName, guest_id: int = 0, customer_type: StringName = &"regular",
		owner_model: StringName = OwnerAppearance.DEFAULT_MODEL) -> String:
	var model: StringName = model_for(role, guest_id, customer_type, owner_model)
	return "" if model == &"" else MODEL_DIRECTORY + String(model) + ".glb"


static func _is_guest_role(role: StringName) -> bool:
	return role == &"customer" or role == &"guest"


## Tourists wear a small straw sun hat (#661).
static func has_sun_hat(role: StringName, customer_type: StringName) -> bool:
	return _is_guest_role(role) and customer_type == &"tourist"


## The office crowd wear an ID lanyard on the chest (#661).
static func has_lanyard(role: StringName, customer_type: StringName) -> bool:
	return _is_guest_role(role) and customer_type == &"office"


## 0 or 1 from the guest id, independent of the model pair (which uses the low
## bit), so each model shows both shirt and jacket colours.
static func type_variant(guest_id: int) -> int:
	return posmod(guest_id >> 1, 2)


## Farmers wear a golden straw farm hat (#663).
static func has_farm_hat(role: StringName, customer_type: StringName) -> bool:
	return _is_guest_role(role) and customer_type == &"farmer"


## Farmers wear denim overalls: a bib on the chest over denim legs (#663).
static func has_overall_bib(role: StringName, customer_type: StringName) -> bool:
	return _is_guest_role(role) and customer_type == &"farmer"


## Walkers wear a knit beanie with a bobble (#657).
static func has_beanie(role: StringName, customer_type: StringName) -> bool:
	return _is_guest_role(role) and customer_type == &"walker"


## Foragers carry a wicker basket on the arm (#659).
static func has_basket(role: StringName, customer_type: StringName) -> bool:
	return _is_guest_role(role) and customer_type == &"forager"


## Names the type look (type and colour) a view must wear, or &"" for any
## other guest; a view rebuilds when this changes, even on the same model.
static func type_look_key(role: StringName, guest_id: int, customer_type: StringName) -> StringName:
	if has_sun_hat(role, customer_type) or has_lanyard(role, customer_type) \
			or not outfit(role, guest_id, customer_type).is_empty():
		return StringName("%s:%d" % [customer_type, type_variant(guest_id)])
	return &""


## The clothes of a location guest (farmer, walker, surfer, forager), or {} for
## every other look. Keys: `upper` (torso and sleeves), `lower` (hips and legs,
## absent to keep the model's own), `bare_arms`, `bare_hands` and `bare_shins`
## (paint those parts in the model's own skin: a tank top, no gloves, shorts)
## and `hair` (a shade multiplier for the head's hair block, absent for none).
## PersonOutfit paints them.
static func outfit(role: StringName, guest_id: int, customer_type: StringName) -> Dictionary:
	if not _is_guest_role(role):
		return {}
	var variant: int = type_variant(guest_id)
	match customer_type:
		&"farmer":
			return {"upper": FARMER_SHIRTS[variant], "lower": FARMER_DENIM, "bare_hands": true}
		&"walker":
			return {"upper": WALKER_JACKETS[variant]}
		&"surfer":
			return {"upper": SURFER_AQUA if variant == 0 else SURFER_ORANGE,
				"lower": SURFER_ORANGE if variant == 0 else SURFER_AQUA,
				"bare_arms": true, "bare_hands": true, "bare_shins": true, "hair": WET_HAIR_SHADE}
		&"forager":
			return {"upper": FORAGER_JACKETS[variant]}
	return {}


## Colormap blocks to repaint on the body mesh of a tourist (holiday shirt) or
## an office guest (jacket), as {rect, color}. Empty for every other look.
static func type_recolors(role: StringName, guest_id: int, customer_type: StringName,
		model: StringName) -> Array[Dictionary]:
	var colors: Array[Color] = []
	if has_sun_hat(role, customer_type):
		colors = TOURIST_SHIRTS
	elif has_lanyard(role, customer_type):
		colors = OFFICE_JACKETS
	if colors.is_empty() or not CLOTHING_RAMPS.has(model):
		return []
	var color: Color = colors[type_variant(guest_id)]
	var recolors: Array[Dictionary] = [{"rect": CLOTHING_RAMPS[model], "color": color}]
	return recolors


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
	if role == &"inspector":
		return [{"rect": Rect2i(480, 256, 32, 128), "color": INSPECTOR_SLATE}]
	if role != &"courier":
		return []
	return [
		{"rect": Rect2i(480, 256, 32, 128), "color": COURIER_BROWN},
		{"rect": Rect2i(160, 256, 32, 128), "color": COURIER_AMBER},
	]


## The inspector holds a clipboard (#302), drawn in the hands of the held pose.
static func has_clipboard(role: StringName) -> bool:
	return role == &"inspector"


## The clip a role actually plays for the generic `clip`: the inspector holds
## the clipboard instead of carrying; everyone else plays it unchanged.
static func clip_for_role(role: StringName, clip: StringName) -> StringName:
	if not has_clipboard(role):
		return clip
	if clip == CARRY_WALK:
		return CLIPBOARD_WALK
	if clip == &"holding-both":
		return CLIPBOARD_HOLD
	return clip


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
