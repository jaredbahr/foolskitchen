class_name ReviewVisit
extends RefCounted
## Detached inputs captured when one guest departs. Wait fractions mean elapsed
## waiting divided by that guest's patience budget, not time remaining.

var served: bool = false
var closing: bool = false
var queue_wait_fraction: float = 0.0
var food_wait_fraction: float = 0.0
var price_ratio: float = 1.0
## Final cooked Order.quality (0..1); absent dishes retain zero.
var quality: float = 0.0
var quality_weight: float = 0.0
var review_chance_multiplier: float = 1.0
## Zero until the optional cleanliness system is present.
var dirt_fraction: float = 0.0
## Raw additive ambience term sampled on arrival; stars still round to integers.
var vibe_review_bonus: float = 0.0
