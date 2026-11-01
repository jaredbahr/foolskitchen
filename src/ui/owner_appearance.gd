class_name OwnerAppearance
extends RefCounted
## Plain presentation choices. Main includes these in its existing owner
## section at the morning autosave; this helper owns no scene or random stream.

const DEFAULT_MODEL: StringName = &"character-male-a"
const DEFAULT_NAME: String = "You"
const MAX_NAME_LENGTH: int = 32
const MODELS: Array[StringName] = [
	&"character-female-a", &"character-female-b", &"character-female-c",
	&"character-female-d", &"character-female-e", &"character-female-f",
	&"character-male-a", &"character-male-b", &"character-male-c",
	&"character-male-d", &"character-male-e", &"character-male-f",
]

var model: StringName = DEFAULT_MODEL
var display_name: String = DEFAULT_NAME


static func valid_model(value: StringName) -> bool:
	return MODELS.has(value)


## A rejected choice never replaces either field. Blank names use the same
## default as old saves, while controls cannot create extra UI lines.
func set_choice(value: StringName, name: String) -> bool:
	if not valid_model(value):
		return false
	for index: int in name.length():
		var code: int = name.unicode_at(index)
		if code < 32 or (code >= 127 and code <= 159) or code == 8232 or code == 8233:
			return false
	var trimmed: String = name.strip_edges()
	if trimmed.length() > MAX_NAME_LENGTH:
		return false
	model = value
	display_name = DEFAULT_NAME if trimmed.is_empty() else trimmed
	return true


func to_dict() -> Dictionary:
	return {"model": String(model), "name": display_name}


## The absent legacy appearance section may be supplied as an empty dictionary.
## Otherwise restore only the complete, canonical JSON shape, transactionally.
func from_dict(data: Dictionary) -> bool:
	if data.is_empty():
		return set_choice(DEFAULT_MODEL, DEFAULT_NAME)
	if data.size() != 2 or not data.has("model") or not data.has("name"):
		return false
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or (key != "model" and key != "name"):
			return false
	if not data["model"] is String or not data["name"] is String:
		return false
	return set_choice(StringName(data["model"]), String(data["name"]))
