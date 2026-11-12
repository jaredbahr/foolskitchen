class_name BuildInfo
extends RefCounted
## Which build this is and what changed in it. A tag build stamps its version
## and its release notes into build_info/ at export time (tools/export.sh); a
## run from the editor has neither file and reports "dev". Everything is read
## from the game's own files: there is no network access at runtime.

const VERSION_PATH: String = "res://build_info/version.txt"
const NOTES_PATH: String = "res://build_info/release_notes.txt"
const CHANGELOG_PATH: String = "res://CHANGELOG.md"
const DEV: String = "dev"
const RELEASES_URL: String = "https://github.com/jaredbahr/foolskitchen/releases"

static var _release_pattern: RegEx = null


## The stamped version ("v0.2.0", "dev-1a2b3c4") or "dev" when nothing is stamped.
static func version(path: String = VERSION_PATH) -> String:
	var text: String = _read(path).strip_edges()
	return text if not text.is_empty() and not text.contains("\n") else DEV


## [major, minor, patch] for a release tag such as "v0.2.0" (the "v" is
## optional); an empty array for anything else, including dev versions.
static func parse_version(text: String) -> Array[int]:
	if _release_pattern == null:
		_release_pattern = RegEx.create_from_string("^v?(\\d+)\\.(\\d+)\\.(\\d+)$")
	var parts: Array[int] = []
	var found: RegExMatch = _release_pattern.search(text.strip_edges())
	if found == null:
		return parts
	for group: int in [1, 2, 3]:
		parts.append(int(found.get_string(group)))
	return parts


static func is_release(text: String) -> bool:
	return not parse_version(text).is_empty()


## True when `a` is a newer release than `b` (both must be release versions).
static func is_newer(a: String, b: String) -> bool:
	var left: Array[int] = parse_version(a)
	var right: Array[int] = parse_version(b)
	if left.is_empty() or right.is_empty():
		return false
	for index: int in 3:
		if left[index] != right[index]:
			return left[index] > right[index]
	return false


## The small corner label on the title screen.
static func label(text: String) -> String:
	return text if not text.is_empty() else DEV


## The window heading for the What's new panel.
static func panel_title(text: String) -> String:
	return "What's new in %s" % text if is_release(text) else "What's new in this build"


## The release's notes as the export bundled them. A dev run falls back to the
## Unreleased section of CHANGELOG.md, so the panel is never empty at your desk.
static func notes(path: String = NOTES_PATH, changelog_path: String = CHANGELOG_PATH) -> String:
	var bundled: String = _read(path).strip_edges()
	if not bundled.is_empty():
		return bundled
	return unreleased_section(_read(changelog_path))


## The text under "## Unreleased" up to the next "## " heading, trimmed.
static func unreleased_section(changelog: String) -> String:
	var lines: PackedStringArray = []
	var inside: bool = false
	for raw: String in changelog.replace("\r\n", "\n").split("\n"):
		if raw.begins_with("## "):
			if inside:
				break
			inside = raw.substr(3).strip_edges() == "Unreleased"
			continue
		if inside:
			lines.append(raw)
	return "\n".join(lines).strip_edges()


## The panel opens by itself once for each new release build: never for dev
## runs, never again for a version already shown, never with nothing to show.
static func should_show_whats_new(current: String, last_seen: String, notes_text: String) -> bool:
	return is_release(current) and current != last_seen and not notes_text.strip_edges().is_empty()


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
