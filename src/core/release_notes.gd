class_name ReleaseNotes
extends RefCounted
## Turns a changelog section (the text tools/release_notes.sh prints) into
## titled groups of plain lines for the What's new panel. A "What to test"
## group always comes first; the others keep the order they were written in.

const TEST_TITLE: String = "What to test"


## [{"title": String, "items": Array[String]}], What to test first.
static func parse(text: String) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var current: Dictionary = {}
	var last_item: int = -1
	for raw: String in text.replace("\r\n", "\n").split("\n"):
		var line: String = raw.strip_edges()
		if line.is_empty() or line.begins_with("## "):
			continue
		if line.begins_with("### "):
			current = {"title": plain(line.substr(4)), "items": [] as Array[String]}
			groups.append(current)
			last_item = -1
			continue
		if current.is_empty():
			current = {"title": "", "items": [] as Array[String]}
			groups.append(current)
		var items: Array[String] = current["items"]
		var bullet: bool = line.begins_with("- ") or line.begins_with("* ")
		if bullet:
			items.append(plain(line.substr(2)))
			last_item = items.size() - 1
		elif raw.begins_with(" ") and last_item >= 0:
			items[last_item] += " " + plain(line)
		else:
			items.append(plain(line))
			last_item = items.size() - 1
	var tests: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for group: Dictionary in groups:
		if (group["items"] as Array).is_empty():
			continue
		if is_test_title(String(group["title"])):
			tests.append(group)
		else:
			rest.append(group)
	return tests + rest


static func is_test_title(title: String) -> bool:
	return title.strip_edges().trim_suffix(":").strip_edges().to_lower() == TEST_TITLE.to_lower()


## Drops the markdown marks a Label would show literally.
static func plain(text: String) -> String:
	return text.replace("**", "").replace("`", "").strip_edges()
