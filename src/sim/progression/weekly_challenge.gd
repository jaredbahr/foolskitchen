class_name WeeklyChallenge
extends Resource
## Authored weekly objective. All draw-time values are copied into state.

enum Kind { SERVE_IN_ONE_DAY, OPERATING_PROFIT, NO_LOSS_DAYS, GOOD_REVIEWS, SELL_DISH }

const MAX_TARGET: int = 1000000
const MAX_REWARD: int = 1000000
const MAX_ID_LENGTH: int = 64
const MAX_DISH_NAME_LENGTH: int = 128
const MAX_RENDERED_TEXT_LENGTH: int = 160

@export var id: StringName = &""
@export var kind: Kind = Kind.SERVE_IN_ONE_DAY
@export var text_template: String = ""
@export_range(1, 1000000, 1) var base_target: int = 1
@export_range(0, 1000000, 1) var per_level: int = 0
@export_range(1, 1000000, 1) var reward_cash: int = 1


func is_valid() -> bool:
	if id.is_empty() or id.length() > MAX_ID_LENGTH \
			or kind < Kind.SERVE_IN_ONE_DAY or kind > Kind.SELL_DISH \
			or text_template.strip_edges().is_empty() \
			or text_template.length() > MAX_RENDERED_TEXT_LENGTH or base_target < 1 \
			or base_target > MAX_TARGET or per_level < 0 or per_level > MAX_TARGET \
			or reward_cash < 1 or reward_cash > MAX_REWARD:
		return false
	if kind == Kind.SELL_DISH:
		return text_template.contains("{target}") and text_template.contains("{dish}")
	if kind == Kind.NO_LOSS_DAYS:
		return base_target <= 7 and per_level >= 0 \
			and text_template.contains("{target}") and not text_template.contains("{dish}")
	return text_template.contains("{target}") and not text_template.contains("{dish}")


func target_at_level(owner_level: int) -> int:
	if not is_valid() or owner_level < 1 or owner_level > 1000000:
		return 0
	var scaled: int = base_target + per_level * (owner_level - 1)
	return mini(scaled, 7) if kind == Kind.NO_LOSS_DAYS else mini(scaled, MAX_TARGET)


func display_text(target: int, dish_name: String = "") -> String:
	if not is_valid() or target < 1 or target > MAX_TARGET:
		return ""
	if kind == Kind.SELL_DISH and dish_name.strip_edges().is_empty():
		return ""
	var rendered: String = text_template.replace("{target}", str(target)).replace("{dish}", dish_name.strip_edges())
	return rendered if rendered.length() <= MAX_RENDERED_TEXT_LENGTH else ""
