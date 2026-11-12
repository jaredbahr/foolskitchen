class_name Fmt
extends RefCounted
## Shared, locale-independent HUD formatting.

const FREE: String = "Free"


## Dollars with grouped thousands; string conversion also handles INT64_MIN.
static func money(value: int) -> String:
	var digits: String = str(value).trim_prefix("-")
	var grouped: String = ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-$" if value < 0 else "$") + digits + grouped


## A price the player pays: "Free" in a Creative game (FK-141), where money
## is off; otherwise exactly money().
static func price(value: int) -> String:
	return FREE if GameMode.is_creative() else money(value)


## A price per unit ("$4 a tile"), or just "Free" in a Creative game.
static func price_each(value: int, unit: String) -> String:
	return FREE if GameMode.is_creative() else "%s a %s" % [money(value), unit]


## "for $40" in a sentence, or "for free" in a Creative game.
static func for_price(value: int) -> String:
	return "for free" if GameMode.is_creative() else "for %s" % money(value)


## "for $4 a tile" ("for $40 each" with an empty unit), or "for free".
static func for_price_each(value: int, unit: String) -> String:
	if GameMode.is_creative():
		return "for free"
	return "for %s %s" % [money(value), "each" if unit.is_empty() else "a " + unit]


## Minutes since midnight as a 24-hour clock; negative inputs clamp to midnight.
static func clock(minutes: int) -> String:
	var normalized: int = maxi(minutes, 0) % (24 * 60)
	return "%02d:%02d" % [normalized / 60, normalized % 60]
