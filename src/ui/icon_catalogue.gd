class_name IconCatalogue
extends RefCounted
## Approved Kenney Game Icons for the UI. A missing role deliberately has no icon:
## callers keep its text until the art set supplies a fitting silhouette.

const TOP_BAR_SIZE: int = 28
const PANEL_SIZE: int = 24
const ROOT: String = "res://assets/kenney/icons/"
## Issue #241: explicitly approved made silhouettes in the same icon style.
const WEATHER_ROOT: String = "res://assets/made/icons/"

const ICON_ROLES: Array[StringName] = [
	&"pause", &"speed_1", &"speed_2", &"speed_4", &"build", &"menu", &"staff",
	&"reputation", &"open_shop", &"next_day", &"catalogue", &"report", &"settings",
	&"stock", &"sell",
	&"weather_sunny", &"weather_cloudy", &"weather_rain",
]


## Returns an approved path, or an empty string for an unsupported/missing icon.
static func path_for(role: StringName) -> String:
	match role:
		&"pause":
			return ROOT + "pause.png"
		&"speed_1":
			return ROOT + "right.png"
		&"speed_2", &"speed_4":
			return ROOT + "fastForward.png"
		&"build":
			return ROOT + "wrench.png"
		&"menu":
			return ROOT + "menuList.png"
		&"staff":
			return ROOT + "singleplayer.png"
		&"reputation":
			return ROOT + "star.png"
		&"open_shop", &"next_day":
			return ROOT + "next.png"
		&"catalogue":
			return ROOT + "menuGrid.png"
		&"report":
			return ROOT + "leaderboardsSimple.png"
		&"settings":
			return ROOT + "gear.png"
		&"stock":
			return ROOT + "shoppingBasket.png"
		&"sell":
			return ROOT + "trashcan.png"
		&"weather_sunny":
			return WEATHER_ROOT + "weather_sunny.png"
		&"weather_cloudy":
			return WEATHER_ROOT + "weather_cloudy.png"
		&"weather_rain":
			return WEATHER_ROOT + "weather_rain.png"
	return ""


## ResourceLoader.exists guards optional roles without emitting load errors.
static func texture_for(role: StringName) -> Texture2D:
	var path: String = path_for(role)
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		return null
	return ResourceLoader.load(path, "Texture2D") as Texture2D
