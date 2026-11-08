class_name ShortcutsText
extends RefCounted
## The single source for the keyboard help panel and its input-map coverage test.

const GROUPS: Array[String] = ["Game", "Owner", "Build"]

const ROWS: Array[Dictionary] = [
	{"group": "Game", "keys": "Space", "action": "Pause or resume", "input_actions": [&"speed_pause"]},
	{"group": "Game", "keys": "1 / Keypad 1", "action": "Normal speed", "input_actions": [&"speed_1"]},
	{"group": "Game", "keys": "2 / Keypad 2", "action": "2× speed", "input_actions": [&"speed_2"]},
	{"group": "Game", "keys": "3 / Keypad 3", "action": "4× speed", "input_actions": [&"speed_3", &"speed_4"]},
	{"group": "Game", "keys": "F1", "action": "Show or close shortcuts"},
	{"group": "Game", "keys": "Esc", "action": "Close a panel or cancel the current tool"},
	{"group": "Game", "keys": "F3", "action": "Toggle debug view"},
	{"group": "Game", "keys": "F10", "action": "Start over with a new shop"},
	{"group": "Game", "keys": "W / A / S / D", "action": "Pan the camera"},
	{"group": "Game", "keys": "Q / E", "action": "Rotate the camera"},
	{"group": "Game", "keys": "G", "action": "Toggle the grid"},
	{"group": "Game", "keys": "C", "action": "Cycle wall display"},
	{"group": "Owner", "keys": "K", "action": "Set owner to Kitchen"},
	{"group": "Owner", "keys": "F", "action": "Set owner to Floor"},
	{"group": "Owner", "keys": "H", "action": "Set owner to Help"},
	{"group": "Owner", "keys": "R", "action": "Set owner to Rest"},
	{"group": "Build", "keys": "B", "action": "Enter or leave Build"},
	{"group": "Build", "keys": "P", "action": "Toggle Paint"},
	{"group": "Build", "keys": "G", "action": "Toggle the build grid"},
	{"group": "Build", "keys": "R / .", "action": "Rotate clockwise"},
	{"group": "Build", "keys": ",", "action": "Rotate counter-clockwise"},
	{"group": "Build", "keys": "Delete", "action": "Remove or sell the selection"},
	{"group": "Build", "keys": "Ctrl / Cmd + Z", "action": "Undo"},
	{"group": "Build", "keys": "Ctrl / Cmd + Y", "action": "Redo; also Ctrl / Cmd + Shift + Z"},
	{"group": "Build", "keys": "Esc", "action": "Cancel or leave the current tool"},
	{"group": "Build", "keys": "Shift-click", "action": "Fill a room while painting or laying floors"},
	{"group": "Build", "keys": "Alt-click", "action": "Pick floor decor beneath furniture"},
	{"group": "Build", "keys": "Alt-click", "action": "Pick a floor or wall finish for the active tool"},
]


static func rows_for(group: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in ROWS:
		if row["group"] == group:
			result.append(row)
	return result
