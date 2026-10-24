class_name Fmt
extends RefCounted
## Shared, locale-independent HUD formatting.


## Dollars with grouped thousands; string conversion also handles INT64_MIN.
static func money(value: int) -> String:
	var digits: String = str(value).trim_prefix("-")
	var grouped: String = ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-$" if value < 0 else "$") + digits + grouped


## Minutes since midnight as a 24-hour clock; negative inputs clamp to midnight.
static func clock(minutes: int) -> String:
	var normalized: int = maxi(minutes, 0) % (24 * 60)
	return "%02d:%02d" % [normalized / 60, normalized % 60]
