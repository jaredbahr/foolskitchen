class_name OpeningGoal
extends Resource
## One authored goal of a paid goal chain (#494 Opening week, #514 Week 2).
## The session observes the condition and pays the reward; a definition never
## moves cash or XP.

enum Condition {
	## A dish's price was changed in the menu.
	PRICE_CHANGED,
	## A decor item (ItemDef.Category.DECOR) was bought and placed.
	DECOR_PLACED,
	## Guests served so far today.
	SERVED_TODAY,
	## Drinks on the live menu.
	DRINK_ON_MENU,
	## The owner works the floor while the shop is open.
	OWNER_ON_FLOOR,
	## At opening, more tables and more servers than at the start of the morning.
	GROW_TOGETHER,
	## Five-star reviews written so far today.
	FIVE_STAR_REVIEWS_TODAY,
	## At opening, the active site's lease is the bigger one (Tier 2, #514).
	LEASE_EXPANDED,
	## At opening, bought floor cells above the count at the last opening.
	FLOOR_ADDED,
	## At opening, placed items whose id is in `item_ids` above the count at
	## the last opening.
	ITEM_PLACED,
	## Dishes on the live menu with a step at `station_type`.
	DISH_AT_STATION,
	## At opening, hired staff in `role`.
	STAFF_ROLE,
	## A seated party of this many guests or more ate and paid.
	GROUP_SEATED,
	## At the close, the star rating (as the HUD rounds it) when at most
	## `max_turned_away` guests left for a reason in `leave_reasons` today;
	## otherwise zero.
	CALM_DAY_STARS,
}

## The last condition, for range checks.
const LAST_CONDITION: int = Condition.CALM_DAY_STARS

@export var id: StringName = &""
## Short line for the HUD tracker.
@export var title: String = ""
## One plain sentence for the Goals card.
@export_multiline var description: String = ""
@export_enum("Price changed", "Decor placed", "Served today", "Drink on menu",
	"Owner on floor", "Grow together", "Five-star reviews today", "Lease expanded",
	"Floor added", "Item placed", "Dish at station", "Staff role", "Group seated",
	"Calm day stars") var condition: int = Condition.PRICE_CHANGED
## Every condition but CALM_DAY_STARS uses a whole-number target.
@export var target: float = 1.0
@export_range(0, 100000, 1) var reward_cash: int = 0
@export_range(0, 100000, 1) var reward_xp: int = 0
## ITEM_PLACED: the ItemDef ids that count.
@export var item_ids: Array[StringName] = []
## DISH_AT_STATION: the station type a dish must use (for example the fryer).
@export var station_type: StringName = &""
## STAFF_ROLE: the role that counts (for example cleaner).
@export var role: StringName = &""
## CALM_DAY_STARS: leave reasons that spoil the day (for example no_table).
@export var leave_reasons: Array[StringName] = []
## CALM_DAY_STARS: how many such guests the day may lose and still count.
@export_range(0, 1000, 1) var max_turned_away: int = 0


func is_valid() -> bool:
	if id.is_empty() or title.strip_edges().is_empty() or description.strip_edges().is_empty() \
			or condition < Condition.PRICE_CHANGED or condition > LAST_CONDITION \
			or not is_finite(target) or target <= 0.0 \
			or reward_cash < 0 or reward_cash > 100000 or reward_xp < 0 or reward_xp > 100000 \
			or (reward_cash == 0 and reward_xp == 0):
		return false
	match condition:
		Condition.ITEM_PLACED:
			if item_ids.is_empty() or item_ids.has(&""):
				return false
		Condition.DISH_AT_STATION:
			if station_type.is_empty():
				return false
		Condition.STAFF_ROLE:
			if role.is_empty():
				return false
		Condition.CALM_DAY_STARS:
			# A star rating: fractions allowed, never above five stars.
			return target <= 5.0 and not leave_reasons.has(&"") and max_turned_away >= 0
	return target <= 1000000.0 and floorf(target) == target
