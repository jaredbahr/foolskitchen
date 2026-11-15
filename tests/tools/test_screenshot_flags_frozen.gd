extends TestCase
## #526 finding 3: tools/screenshot.gd (and the review helpers it calls) grew a
## command-line flag per feature. The list is frozen: a new capture is a scene,
## `--scene=res://tools/<name>_review.tscn`, which parses its own options and
## costs the shared script nothing. Move an old flag to a scene when its feature
## is next touched, and take it off FROZEN here.

const SCREENSHOT: String = "res://tools/screenshot.gd"
## Every flag screenshot.gd and the helpers it references accept today (2026-11-15).
const FROZEN: PackedStringArray = ["--assign-owner", "--blueprints", "--build", "--capture-set",
	"--catalogue-review", "--collections-review", "--diner-review", "--door-queue", "--expand", "--f3",
	"--fast", "--floors-review", "--frames", "--hud-layout", "--joined-tables-review", "--lease-review",
	"--loan-review", "--menu", "--menu-boards-review", "--milestone-review", "--neighbourhood-review",
	"--open", "--out", "--paint", "--paint-slots", "--property-review", "--quarter", "--report",
	"--report-slowest", "--restroom-review", "--rooms", "--scene", "--select", "--settings",
	"--settings-world", "--shortcuts", "--signature-review", "--site-card-review", "--speed", "--staff",
	"--stock", "--street-front-review", "--walls", "--walls-review", "--weather-review", "--window-size"]


func test_no_new_screenshot_flags() -> void:
	var found: PackedStringArray = _flags()
	assert_true(found.size() > 0, "the scan finds the existing flags")
	var added: PackedStringArray = []
	for flag: String in found:
		if not FROZEN.has(flag):
			added.append(flag)
	assert_eq(added, PackedStringArray(),
		"new screenshot.gd flags %s: make the capture a scene (--scene=res://tools/<name>_review.tscn) instead" % [added])
	var gone: PackedStringArray = []
	for flag: String in FROZEN:
		if not found.has(flag):
			gone.append(flag)
	assert_eq(gone, PackedStringArray(), "flags %s were retired: take them off FROZEN too" % [gone])


## Flag literals in code (not comments) of screenshot.gd and every
## res://tools/*.gd script it references.
func _flags() -> PackedStringArray:
	var source: String = FileAccess.get_file_as_string(SCREENSHOT)
	var scripts: PackedStringArray = [SCREENSHOT]
	var reference: RegEx = RegEx.create_from_string("res://tools/[a-z_]+\\.gd")
	for result: RegExMatch in reference.search_all(source):
		if not scripts.has(result.get_string()):
			scripts.append(result.get_string())
	var literal: RegEx = RegEx.create_from_string("\"(--[a-z0-9][a-z0-9-]*)")
	var flags: PackedStringArray = []
	for path: String in scripts:
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for result: RegExMatch in literal.search_all(line):
				var flag: String = result.get_string(1)
				if not flags.has(flag):
					flags.append(flag)
	flags.sort()
	return flags
