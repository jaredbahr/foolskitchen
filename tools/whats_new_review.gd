extends TitleScreen
## Capture fixture for the What's new panel: the real title screen with a
## sample release (a "What to test" group plus ordinary groups), shown without
## touching the player's settings. Used by `tools/screenshot.sh --whats-new`.

const SAMPLE_NOTES: String = """### Players
- The street outside is cosier and livelier: planter trees, benches, bins and a little bus stop line the pavement, the shops have flower boxes and swinging signs, and the street lamps glow at night. (#439)
- Open Staff to see what each employee did today and in total. (#417)
- Use -10%, +10%, or Reset to standard to change menu prices together in the morning. (#409)
- Two staff who meet head-on in a one-cell corridor now squeeze past each other instead of stepping back and forth. (#402)

### What to test
- Start a new game, open the shop and serve a full day without anyone getting stuck at a door.
- Try the new menu price buttons, then check the evening report shows your prices.
- Paint a chair two different colours and reload your save.

### Under the hood
- Release builds now carry their version and notes. (#433)
"""


func _ready() -> void:
	build_version = "v0.2.0"
	build_notes = SAMPLE_NOTES
	# Already "seen", so the capture never writes the player's settings file.
	Preferences.last_seen_version = build_version
	super._ready()
	show_whats_new()
