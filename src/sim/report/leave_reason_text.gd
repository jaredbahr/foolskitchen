class_name LeaveReasonText
extends RefCounted
## One set of player-facing reason labels for the evening report and Today log.

const LABELS: Dictionary[StringName, String] = {
	&"out_of_stock": "Dish was out of stock",
	&"kitchen_failed": "The kitchen couldn't make the dish",
	&"no_menu": "Nothing on the menu",
	&"closing": "Shop closed",
	&"waited_too_long": "Waited too long",
	&"too_expensive": "Too expensive",
	&"no_table": "No table available",
	&"no_clean_plates": "No clean plates",
	&"no_way_through": "Couldn't get through",
	&"happy": "Finished their visit",
	&"removed": "Left before being served",
}


static func label(reason: StringName) -> String:
	return LABELS.get(reason, "Left before being served")
