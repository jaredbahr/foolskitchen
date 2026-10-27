class_name CatalogueText
extends RefCounted
## Every player sentence the Build/Buy catalogue shows about an item (FK-085):
## room and group names, theme labels, charm and what the item does. Raw ids
## and enum names never reach the screen (rule 11); add new words here.

const VIBE: VibeTuning = preload("res://data/balance/vibe.tres")

const ROOM_LABELS: Dictionary[StringName, String] = {
	&"dining": "Dining", &"kitchen": "Kitchen", &"bar_cafe": "Bar & Café",
	&"decor": "Decor", &"lighting": "Lighting", &"restroom": "Restroom",
}
## Sub-tabs inside a room, by what the furniture is for.
const GROUP_IDS: Array[StringName] = [&"seating", &"tables", &"equipment", &"accents", &"rugs"]
const GROUP_LABELS: Dictionary[StringName, String] = {
	&"seating": "Seating", &"tables": "Tables", &"equipment": "Equipment",
	&"accents": "Accents", &"rugs": "Rugs",
}
const STATION_TEXT: Dictionary[StringName, String] = {
	&"stove": "Cooks hot dishes", &"prep_counter": "Prepares ingredients for dishes",
	&"sink": "Washes dirty plates",
}


static func room_label(room: StringName) -> String:
	return ROOM_LABELS.get(room, "Decor")


static func group_for(definition: ItemDef) -> StringName:
	if definition == null:
		return &""
	match definition.category:
		ItemDef.Category.CHAIR:
			return &"seating"
		ItemDef.Category.TABLE:
			return &"tables"
		ItemDef.Category.STATION, ItemDef.Category.STORAGE, ItemDef.Category.PASS, ItemDef.Category.DOOR:
			return &"equipment"
	return &"rugs" if definition.placement_layer == ItemDef.PlacementLayer.FLOOR_DECOR else &"accents"


## What the item does, in a few words: "Seats 2", "Cooks hot dishes".
static func does(definition: ItemDef) -> String:
	if definition == null:
		return ""
	match definition.category:
		ItemDef.Category.CHAIR:
			return "Seats %d" % maxi(definition.seat_cells.size(), 1)
		ItemDef.Category.TABLE:
			if not definition.seat_cells.is_empty():
				return "Table with seats for %d" % definition.seat_cells.size()
			return "Table for %d" % definition.capacity
		ItemDef.Category.STATION:
			return STATION_TEXT.get(definition.station_type, "Kitchen station")
		ItemDef.Category.STORAGE:
			return "Stores %d ingredients" % definition.capacity
		ItemDef.Category.PASS:
			return "Hands finished plates to the servers"
		ItemDef.Category.DOOR:
			return "The way in"
	if definition.placement_layer == ItemDef.PlacementLayer.FLOOR_DECOR:
		return "Rug: tables and chairs can stand on it"
	return "Decoration"


## Only decor earns charm in the vibe model; other furniture shows none.
static func charm_text(definition: ItemDef) -> String:
	if definition == null or definition.category != ItemDef.Category.DECOR or definition.charm <= 0:
		return ""
	return "Charm +%d" % definition.charm


## Theme tags in the vibe's own order and words, e.g. "Cosy, Rustic".
static func themes_text(definition: ItemDef) -> String:
	var labels: Array[String] = []
	if definition != null:
		for tag: StringName in VIBE.theme_order:
			if definition.theme_tags.has(tag):
				labels.append(VIBE.theme_labels[tag])
	return ", ".join(labels)


## The theme filters Buy mode offers: every theme the vibe knows, in order.
static func theme_ids() -> Array[StringName]:
	return VIBE.theme_order.duplicate()


static func theme_label(tag: StringName) -> String:
	return VIBE.theme_labels.get(tag, "")


## The words on a catalogue tile under its picture.
static func tile_text(definition: ItemDef, owner_level: int) -> String:
	if definition.unlock_level > owner_level:
		return "Level %d" % definition.unlock_level
	return Fmt.money(definition.price)


## The hover card's lines, top to bottom, after the picture.
static func card_lines(definition: ItemDef, owner_level: int) -> Array[String]:
	var lines: Array[String] = [definition.display_name]
	lines.append(Fmt.money(definition.price) if definition.unlock_level <= owner_level
		else "%s  (unlocks at level %d)" % [Fmt.money(definition.price), definition.unlock_level])
	lines.append(does(definition))
	var charm: String = charm_text(definition)
	if not charm.is_empty():
		lines.append(charm)
	var themes: String = themes_text(definition)
	lines.append("Themes: " + themes if not themes.is_empty() else "No theme")
	return lines
