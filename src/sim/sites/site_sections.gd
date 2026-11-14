class_name SiteSections
extends RefCounted
## Which save sections belong to the owner (shared by every site) and which
## belong to one site (FK-087, docs/TECH.md "Sites and the property market").
## Every registered save section must be in exactly one list; a test checks it.
## When sites switch, PER_SITE sections are swapped and GLOBAL ones stay.

const GLOBAL: PackedStringArray = [
	"owner", "game_state",
	# The clock is the shared calendar. Each site's opening hours are its own
	# "site_hours" section; the clock's copy follows the active site.
	"clock",
	"economy", "blueprints", "milestones", "weekly_challenge", "hints", "weather",
	"collection_toasts", "sites",
	# Career or Creative (FK-141) belongs to the whole game, not one site.
	"game_mode",
	# Service event cooldowns (#495) follow the owner, wherever he works.
	"service_events",
]

const PER_SITE: PackedStringArray = [
	"shop", "menu", "daily_special", "signature", "staff", "plates", "reviews",
	"regulars", "reorder", "deliveries", "demand", "viral", "business_history",
	"shop_records", "cat", "inspection", "critic", "bookings", "rush_hour",
	"aquarium", "pantry",
	# Opening hours (FK-087 part 1, #408), split out of "clock".
	"site_hours",
]


static func is_global(key: String) -> bool:
	return GLOBAL.has(key)


static func is_per_site(key: String) -> bool:
	return PER_SITE.has(key)
