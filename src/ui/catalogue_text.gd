class_name CatalogueText
extends RefCounted
## Every player sentence the Build/Buy catalogue shows about an item (FK-085):
## room and group names, theme labels, charm and what the item does. Raw ids
## and enum names never reach the screen (rule 11); add new words here.

const VIBE: VibeTuning = preload("res://data/balance/vibe.tres")
const WALL_REMOVE_LABEL: String = "Remove"
const WALL_REMOVE_TOOLTIP: String = "Click a wall segment or drag along a run to remove it for a refund. Del: remove the hovered wall."
const WALL_REMOVE_EMPTY: String = "Point at a built wall to remove it"
const WALLS_KEYS: String = "Drag along grid lines  |  Click to build, change or remove  |  Del: remove  |  Ctrl+Z Undo  |  Esc Cancel"


const ROOM_LABELS: Dictionary[StringName, String] = {
	&"dining": "Dining", &"kitchen": "Kitchen", &"bar_cafe": "Bar & Café",
	&"decor": "Decor", &"lighting": "Lighting", &"restroom": "Restroom",
}
## Sub-tabs inside a room, by what the furniture is for.
const GROUP_IDS: Array[StringName] = [&"seating", &"tables", &"equipment", &"accents", &"rugs", &"wall_decor"]
const GROUP_LABELS: Dictionary[StringName, String] = {
	&"seating": "Seating", &"tables": "Tables", &"equipment": "Equipment",
	&"accents": "Accents", &"rugs": "Rugs", &"wall_decor": "Wall decor",
}
const STATION_TEXT: Dictionary[StringName, String] = {
	&"stove": "Cooks hot dishes", &"prep_counter": "Prepares ingredients for dishes",
	&"sink": "Washes dirty plates",
	&"fryer": "Fries dishes", &"oven": "Bakes dishes",
	&"coffee": "Makes coffee and tea, and warms pastries",
	&"drinks_fridge": "Keeps soft drinks cold",
	&"drinks_shelf": "Holds the beer and wine",
}
## Restroom fixtures (FK-101): plain words, nothing more (D8).
const RESTROOM_TEXT: Dictionary[StringName, String] = {
	&"toilet": "Guests use it in a Restroom room, one at a time",
	&"wash_basin": "A basin for washing hands",
}
## What each storage kind holds (FK-087), for "Holds 30 units of dry goods".
const STORAGE_WORDS: Dictionary[int, String] = {
	IngredientDef.Storage.FRIDGE: "fridge food", IngredientDef.Storage.FREEZER: "frozen food",
	IngredientDef.Storage.SHELF: "dry goods",
}
## What a station type is called on screen (the inspector's "Station:" line).
const STATION_NAMES: Dictionary[StringName, String] = {
	&"stove": "Stove", &"prep_counter": "Prep counter", &"sink": "Sink", &"fridge": "Fridge",
	&"fryer": "Fryer", &"oven": "Oven", &"coffee": "Coffee machine",
	&"drinks_fridge": "Drinks fridge", &"drinks_shelf": "Drinks shelf",
	&"storage_shelf": "Storage shelf", &"freezer": "Freezer", &"toilet": "Toilet", &"wash_basin": "Wash basin",
}


## One capacity readout for live tables, prospective ghosts and inspection.
static func dining_capacity(capacity: int, joined: bool = false) -> String:
	return "Seats %d (joined table)" % capacity if joined else "Seats %d" % capacity


static func wall_removal_refund(refund: int) -> String:
	return "%s wall (refund %s)" % [WALL_REMOVE_LABEL, Fmt.money(refund)]


## A station type's player name; an unlisted type falls back to the item's own name.
static func station_name(definition: ItemDef) -> String:
	if definition == null or definition.station_type.is_empty():
		return "None"
	return STATION_NAMES.get(definition.station_type, definition.display_name)


static func room_label(room: StringName) -> String:
	return ROOM_LABELS.get(room, "Decor")


static func group_for(definition: ItemDef) -> StringName:
	if definition == null:
		return &""
	if definition.hangs_on_wall():
		return &"wall_decor"
	match definition.category:
		ItemDef.Category.CHAIR, ItemDef.Category.WAITING:
			return &"seating"
		ItemDef.Category.TABLE:
			return &"tables"
		ItemDef.Category.STATION, ItemDef.Category.STORAGE, ItemDef.Category.PASS, ItemDef.Category.DOOR, \
				ItemDef.Category.RESTROOM:
			return &"equipment"
	return &"rugs" if definition.placement_layer == ItemDef.PlacementLayer.FLOOR_DECOR else &"accents"


## What the item does, in a few words: "Seats 2", "Cooks hot dishes".
static func does(definition: ItemDef) -> String:
	if definition == null:
		return ""
	match definition.category:
		ItemDef.Category.WAITING:
			return "Waiting seats for %d: guests wait more patiently, never eat here" % definition.seat_cells.size()
		ItemDef.Category.CHAIR:
			return "Seats %d" % maxi(definition.seat_cells.size(), 1)
		ItemDef.Category.TABLE:
			if definition.serve_across:
				return "Bar counter: stools facing it are seats, served from behind"
			if not definition.seat_cells.is_empty():
				return "Table with seats for %d" % definition.seat_cells.size()
			return "Table for %d" % definition.capacity
		ItemDef.Category.STATION:
			return STATION_TEXT.get(definition.station_type, "Kitchen station")
		ItemDef.Category.STORAGE:
			if definition.storage_units <= 0:
				return "Stores ingredients"
			return "Holds %d units of %s" % [definition.storage_units, STORAGE_WORDS.get(int(definition.storage_kind), "dry goods")]
		ItemDef.Category.PASS:
			return "Hands finished plates to the servers"
		ItemDef.Category.DOOR:
			return "The way in"
		ItemDef.Category.RESTROOM:
			return "Hangs on a restroom wall" if definition.hangs_on_wall() else RESTROOM_TEXT.get(definition.station_type, "Restroom fixture")
	if definition.placement_layer == ItemDef.PlacementLayer.FLOOR_DECOR:
		return "Rug: tables and chairs can stand on it"
	if definition.hangs_in_window():
		return "Hangs in a window, facing the street"
	if definition.hangs_on_wall():
		return "Hangs on a wall, %d tiles wide" % definition.footprint.x
	return "Decoration"


## Ordinary decor and hung restroom accents earn charm; floor fixtures do not.
static func charm_text(definition: ItemDef) -> String:
	if definition == null or definition.charm <= 0:
		return ""
	if definition.category != ItemDef.Category.DECOR and not (
			definition.category == ItemDef.Category.RESTROOM and definition.hangs_on_wall()):
		return ""
	return "Charm +%d" % definition.charm


## Theme tags in the vibe's own order and words, e.g. "Cosy, Rustic".
static func themes_text(definition: ItemDef, variant_id: StringName = &"") -> String:
	var labels: Array[String] = []
	if definition != null:
		for tag: StringName in VIBE.theme_order:
			if definition.variant_tags(variant_id).has(tag):
				labels.append(VIBE.theme_labels[tag])
	return ", ".join(labels)


## The theme filters Buy mode offers: every theme the vibe knows, in order.
static func theme_ids() -> Array[StringName]:
	return VIBE.theme_order.duplicate()


static func theme_label(tag: StringName) -> String:
	return VIBE.theme_labels.get(tag, "")


## The words on a catalogue tile under its picture.
static func tile_text(definition: ItemDef, owner_level: int, variant_id: StringName = &"") -> String:
	if definition.unlock_level > owner_level:
		return "Level %d" % definition.unlock_level
	return Fmt.money(definition.variant_price(variant_id))


## The hover card's lines, top to bottom, after the picture.
static func card_lines(definition: ItemDef, owner_level: int, variant_id: StringName = &"") -> Array[String]:
	var lines: Array[String] = [definition.display_name]
	var look: ItemVariant = definition.variant(variant_id)
	if look != null:
		lines.append(look.display_name)
	lines.append(Fmt.money(definition.variant_price(variant_id)) if definition.unlock_level <= owner_level
		else "%s  (unlocks at level %d)" % [Fmt.money(definition.variant_price(variant_id)), definition.unlock_level])
	lines.append(does(definition))
	var charm: String = charm_text(definition)
	if not charm.is_empty():
		lines.append(charm)
	var themes: String = themes_text(definition, variant_id)
	lines.append("Themes: " + themes if not themes.is_empty() else "No theme")
	return lines


static func paint_variant_title(definition: ItemDef, look: ItemVariant) -> String:
	return "Paint | %s: %s - Click a matching piece" % [definition.display_name, look.display_name]

# Blueprints (FK-045): names and instructions are shared by the catalogue,
# selection tool and HUD rather than exposing internal state names.
const BLUEPRINTS: String = "Blueprints"
const BLUEPRINT_SELECT: String = "Select furniture"
const BLUEPRINT_SELECT_TIP: String = "Drag a box around whole pieces of furniture and rugs"
const BLUEPRINT_SAVE: String = "Save as blueprint"
const BLUEPRINT_SAVE_TIP: String = "Saved to your library at the start of tomorrow"
const BLUEPRINT_NAME: String = "Blueprint name"
const BLUEPRINT_RENAME: String = "Rename"
const BLUEPRINT_DELETE: String = "Delete"
const BLUEPRINT_LIBRARY_EMPTY: String = "Select furniture to start your blueprint library"
const BLUEPRINT_EMPTY: String = "Choose a blueprint with furniture"
const BLUEPRINT_CONTENT: String = "Blueprints only contain floor furniture and rugs"
const BLUEPRINT_INVALID: String = "This blueprint has invalid furniture positions"
const BLUEPRINT_NONE_SELECTED: String = "Drag a box around furniture and rugs to save a blueprint"
const BLUEPRINT_FAILED: String = "The blueprint could not be saved"
const BLUEPRINT_STAMP_REFUSED: String = "The blueprint could not be placed; try again"
const BLUEPRINT_PLACE_TIP: String = "Place this blueprint; R or . rotates right, , rotates left"


static func blueprint_default_name(number: int) -> String:
	return "Blueprint %d" % number


static func blueprint_selection(count: int) -> String:
	return "%d piece%s selected" % [count, "" if count == 1 else "s"] if count > 0 else BLUEPRINT_NONE_SELECTED


static func blueprint_stamp(name: String, cost: int) -> String:
	return "%s — %s  ·  R / , / . rotate" % [name, Fmt.money(cost)]


static func blueprint_stamp_label(name: String) -> String:
	return "stamp " + name


static func blueprint_card(name: String, cost: int) -> String:
	return "%s — %s" % [name, Fmt.money(cost)]

const BLUEPRINT_KEYS: String = "Click Place blueprint  |  , . or R Rotate  |  Esc or Right-click Cancel"
const BLUEPRINT_SELECTION_KEYS: String = "Drag a box around furniture  |  Save as blueprint in Buy → Blueprints  |  Esc Cancel"
