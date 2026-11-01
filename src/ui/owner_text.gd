class_name OwnerText
extends RefCounted
## Player-facing owner choices stay separate from model IDs and save keys.

const TITLE: String = "Who runs this place?"
const NAME_LABEL: String = "Your name (optional)"
const CONFIRM: String = "Confirm"
const RANDOM: String = "Random"
const CANCEL: String = "Cancel"
const CHANGE_LOOK: String = "Change look"
const MORNING_ONLY: String = "Change your look in the morning."
const NAME_ERROR: String = "Use a name of up to 32 characters, on one line."


static func look_label(index: int) -> String:
	return "Look %d" % (index + 1)


static func owner_label(display_name: String) -> String:
	return "Owner: %s" % display_name


static func inspect_title(display_name: String, id: int) -> String:
	return "%s (Owner #%d)" % [display_name, id]
