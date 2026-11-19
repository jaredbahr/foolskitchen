extends SceneTree
## Hand-run early-game audit (docs/EARLY_GAME_AUDIT_2.md). Plays days 1 to N of a new
## Career game in the real Main scene with saving off and service event cards
## on (each answered with its first choice), and prints one JSON line per day:
## guests, money, unlocks, goals, cards, news, reviews and the decisions on
## offer. Never run by CI.
##
## godot --headless --path . --script tools/early_game_audit.gd -- \
##     [--days=10] [--seed=1] [--player=engaged|passive] [--difficulty=normal|easy]


func _initialize() -> void:
	await process_frame
	var core: GDScript = load("res://tools/early_game_audit_core.gd")
	if core == null:
		printerr("Cannot load the early-game audit core")
		quit(2)
		return
	var status: int = core.run_cli(self, OS.get_cmdline_user_args())
	quit(status)
