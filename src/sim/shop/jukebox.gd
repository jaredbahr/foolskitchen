class_name Jukebox
extends RefCounted
## The jukebox's music style (#294). A style is one of the item's looks
## (data/variants/jukebox_*.tres): its id names the music loop, its display name
## is what the player reads, and its theme tag is the theme it lifts. Only one
## jukebox counts toward vibe and plays: the first one guests can see.


## The theme a look stands for: its first tag in the vibe's own order, or empty.
static func style_theme(definition: ItemDef, variant_id: StringName, theme_order: Array[StringName]) -> StringName:
	if definition == null or not definition.plays_music:
		return &""
	var tags: Array[StringName] = definition.variant_tags(variant_id)
	for theme: StringName in theme_order:
		if tags.has(theme):
			return theme
	return &""


## The player's name for the style a jukebox plays, e.g. "Diner rock".
static func style_name(definition: ItemDef, variant_id: StringName) -> String:
	var look: ItemVariant = definition.variant(variant_id) if definition != null else null
	return look.display_name if look != null else ""


## The sound loop a placed jukebox plays: its style id (see Sfx loops).
static func loop_id(definition: ItemDef, variant_id: StringName) -> StringName:
	var look: ItemVariant = definition.variant(variant_id) if definition != null else null
	return look.id if look != null and definition.plays_music else &""


## The one jukebox that counts: the first placed one (by item order) that guests
## can see, using the same rule as every other decor item. Null when none.
static func counted_item(grid: SimGrid) -> PlacedItem:
	if grid == null:
		return null
	var gated: bool = not grid.entries().is_empty()
	var guests: Dictionary[Vector2i, bool] = RoomRules.guest_floor(grid) if gated else {}
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if placed.removed or definition == null or not definition.plays_music:
			continue
		if not gated or VibeInputs.guest_room_item(grid, placed, guests):
			return placed
	return null
