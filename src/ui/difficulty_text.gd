class_name DifficultyText
extends RefCounted
## Shared wording for choosing or changing a Career difficulty.

const CHOOSE_CAREER: String = "Career difficulty"
const START_CAREER: String = "Start Career"
const AUTO_BUY: String = "Order ingredients automatically"
const AUTO_BUY_PREMIUM: String = "Pay extra for automatic orders"


static func description(mode_id: StringName) -> String:
	match mode_id:
		&"easy":
			return "Auto-order at list price. Lower pressure."
		&"normal":
			return "The usual rules with auto-order."
		&"hard":
			return "Stock up yourself. Higher pressure."
		&"custom":
			return "Choose which stock orders to automate."
	return ""
