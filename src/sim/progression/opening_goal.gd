class_name OpeningGoal
extends Resource
## One authored goal of the opening-week chain (#494). The session observes
## the condition and pays the reward; a definition never moves cash or XP.

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
}

@export var id: StringName = &""
## Short line for the HUD tracker.
@export var title: String = ""
## One plain sentence for the Goals card.
@export_multiline var description: String = ""
@export_enum("Price changed", "Decor placed", "Served today", "Drink on menu",
	"Owner on floor", "Grow together", "Five-star reviews today") var condition: int = Condition.PRICE_CHANGED
## Every condition uses a whole-number target.
@export var target: float = 1.0
@export_range(0, 100000, 1) var reward_cash: int = 0
@export_range(0, 100000, 1) var reward_xp: int = 0


func is_valid() -> bool:
	if id.is_empty() or title.strip_edges().is_empty() or description.strip_edges().is_empty() \
			or condition < Condition.PRICE_CHANGED or condition > Condition.FIVE_STAR_REVIEWS_TODAY \
			or not is_finite(target) or target <= 0.0 \
			or reward_cash < 0 or reward_cash > 100000 or reward_xp < 0 or reward_xp > 100000 \
			or (reward_cash == 0 and reward_xp == 0):
		return false
	return target <= 1000000.0 and floorf(target) == target
