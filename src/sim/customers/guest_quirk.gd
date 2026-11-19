class_name GuestQuirk
extends Resource
## One small, readable guest personality (docs/GUESTS.md section 3): a line in
## the inspect panel, an icon hint for the view, and one testable effect.
## Data only, in data/customers/quirks.tres; every effect is neutral by default.

@export var id: StringName = &""
## The plain sentence the inspect panel shows, such as "Takes a photo of every dish."
@export var inspect_line: String = ""
## A hint for the view's icon over the guest (placeholder until art), such as &"camera".
@export var icon: StringName = &""
## Relative pick weight among the quirks a guest can have.
@export var weight: float = 1.0
## Guest types that can have this quirk; empty means any type.
@export var types: Array[StringName] = []
## Always writes a review when served (the review-chance draw still happens,
## so the review stream keeps its shape).
@export var always_reviews: bool = false
## Multiplies how long the guest stays at the table once their food arrives.
@export_range(1.0, 3.0, 0.05) var linger_multiplier: float = 1.0
## Multiplies both queue and food patience.
@export_range(0.2, 2.0, 0.05) var patience_multiplier: float = 1.0
## Raw review stars on any served visit.
@export_range(0.0, 1.0, 0.05) var review_bonus: float = 0.0
## Raw review stars when the food arrived within this share of their food
## patience (0 means no speed bonus).
@export_range(0.0, 1.0, 0.05) var fast_food_fraction: float = 0.0
@export_range(0.0, 1.0, 0.05) var fast_food_bonus: float = 0.0
## The review quote group used on a good visit (ReviewQuotes.CAUSES). For a
## speed quirk, only when the food was fast.
@export var happy_cause: StringName = &""


func is_valid() -> bool:
	if id.is_empty() or inspect_line.strip_edges().is_empty():
		return false
	if not is_finite(weight) or weight <= 0.0:
		return false
	if not is_finite(linger_multiplier) or linger_multiplier < 1.0 or linger_multiplier > 3.0:
		return false
	if not is_finite(patience_multiplier) or patience_multiplier < 0.2 or patience_multiplier > 2.0:
		return false
	for value: float in [review_bonus, fast_food_fraction, fast_food_bonus]:
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return false
	if (fast_food_fraction > 0.0) != (fast_food_bonus > 0.0):
		return false
	return happy_cause.is_empty() or ReviewQuotes.CAUSES.has(happy_cause)


func suits(type_id: StringName) -> bool:
	return types.is_empty() or types.has(type_id)


## True when a served visit's food came quickly enough for the speed bonus.
func was_fast(food_wait_fraction: float) -> bool:
	return fast_food_fraction > 0.0 and is_finite(food_wait_fraction) \
		and food_wait_fraction <= fast_food_fraction
