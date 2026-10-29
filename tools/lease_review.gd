extends SceneTree
## Manual native review fixture, not a gameplay or CI path. Leaves the window
## interactive; all state is in memory (use_saves=false). No screenshots saved.
## godot --path . --resolution 1600x900 --script tools/lease_review.gd -- offer
## Modes: offer (deposit + $1, amber restock advice), short (cash refusal),
## expand (accepted lease, real Expand tool with the larger lot).


func _initialize() -> void:
	# Load after autoloads exist, as with the balance/capture entry points.
	await process_frame
	var mode: String = "offer"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		mode = args[0]
	if not mode in ["offer", "short", "expand"]:
		printerr("Use offer, short or expand")
		quit(2)
		return
	var scene: PackedScene = load("res://src/world/main.tscn")
	var main: Node = scene.instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", 1)
	root.add_child(main)
	main.call("start")
	var clock: Node = root.get_node("Clock")
	clock.call("set_speed", 0)
	var progress: RefCounted = main.get("owner_progress")
	var lease: Resource = load("res://data/balance/lease_upgrade.tres")
	progress.call("award_bonus", progress.call("threshold_for", lease.get("owner_level")))
	var menu: RefCounted = main.get("menu_settings")
	menu.call("set_owner_level", progress.get("level"))
	var editor: RefCounted = main.get("shop_editor")
	editor.call("set_owner_level", progress.get("level"))
	main.get_node("Overlay/BuildCatalogue").call("set_owner_level", progress.get("level"))
	main.get_node("HUD").call("set_owner_progress", progress.get("level"),
		progress.call("xp_into_level"), progress.call("xp_in_level"))
	var economy: Node = root.get_node("Economy")
	var deposit: int = lease.get("deposit")
	economy.set("cash", deposit - 1 if mode == "short" else deposit + 1)
	if mode == "expand":
		economy.set("cash", deposit + 5000)
		if not main.call("lease_buy"):
			printerr("Lease fixture purchase refused")
			quit(2)
			return
		main.call("set_build_active", true)
		main.call("_on_floor_tool_requested")
	else:
		main.call("set_menu_visible", true)
	print("LEASE REVIEW FIXTURE: %s; synthetic owner XP/cash; no saves" % mode)
