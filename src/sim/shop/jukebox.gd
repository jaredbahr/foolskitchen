class_name Jukebox
extends RefCounted
## The jukebox's music style (#294). A style is one of the item's looks
## (data/variants/jukebox_*.tres): its id names the music loop, its display name
## is what the player reads, and its theme tag is the theme it lifts. Only one
## jukebox counts toward vibe and plays: the one with the most charm among those
## guests can see (so the deluxe jukebox beats the basic one), the first placed
## when charm ties. Every item with `plays_music` is a jukebox.


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


## The one jukebox that counts: among the placed ones guests can see (the same rule
## as every other decor item), the one with the most charm, the first placed (by
## item order) when charm ties. Null when none. `guests` may pass the guest floor the
## caller already worked out.
static func counted_item(grid: SimGrid, guests: Dictionary[Vector2i, bool] = {}) -> PlacedItem:
	if grid == null:
		return null
	var gated: bool = not grid.entries().is_empty()
	if gated and guests.is_empty():
		guests = RoomRules.guest_floor(grid)
	var best: PlacedItem = null
	var best_charm: int = -1
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if placed.removed or definition == null or not definition.plays_music:
			continue
		if definition.charm > best_charm and (not gated or VibeInputs.guest_room_item(grid, placed, guests)):
			best = placed
			best_charm = definition.charm
	return best
