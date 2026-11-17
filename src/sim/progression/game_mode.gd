class_name GameMode
extends RefCounted
## Career or Creative (D34, FK-141). The one place that knows which mode the
## run is in: every unlock check reads OwnerProgress.effective_level() and
## effective_tier(), and every money movement and affordability check reads
## is_creative() through Economy, so no other system tests the mode itself.
##
## The state is a static run-wide flag (like an autoload, but plain data so
## the sim can read it). It is saved as its own "game_mode" section; a save
## without the section is a career game.

## The owner level every unlock check sees in a Creative game: above every
## authored unlock_level, so items, recipes, floors, events and customers
## are all open from day 1.
const CREATIVE_LEVEL: int = 99

static var _creative: bool = false
## The mode the next new game starts in, set by the title's choice (or the
## in-game Start over, which keeps the current mode). Used once.
static var _requested_creative: bool = false
static var _requested_difficulty: StringName = &"normal"
static var _requested_custom_flags: Dictionary = {}


static func is_creative() -> bool:
	return _creative


## Asks for the next new game's mode; _new_game() takes it with begin_new_game().
static func request_new_game(creative: bool, difficulty: StringName = &"normal", flags: Dictionary = {}) -> void:
	_requested_creative = creative
	_requested_difficulty = difficulty if not creative else &"normal"
	_requested_custom_flags = flags.duplicate() if not creative else {}


## A new game starts in the requested mode; the request is used up.
static func begin_new_game() -> Difficulty:
	_creative = _requested_creative
	var difficulty: Difficulty = Difficulty.new()
	difficulty.start(_requested_difficulty, _requested_custom_flags)
	request_new_game(false)
	return difficulty


## Before a load: a save from before Creative has no section and is a career game.
static func reset_for_load() -> void:
	_creative = false


## Tests and tools only.
static func set_creative(value: bool) -> void:
	_creative = value


static func capture() -> Dictionary:
	return {"creative": _creative}


static func restore(data: Dictionary) -> bool:
	var value: Variant = data.get("creative", null)
	if not value is bool or data.size() != 1:
		return false
	_creative = value
	return true


## Whether a save document's sections describe a Creative game. Reads only
## data already parsed by the caller (the title's Continue label).
static func is_creative_save(sections: Dictionary) -> bool:
	var section: Variant = sections.get("game_mode", null)
	return section is Dictionary and (section as Dictionary).get("creative", false) is bool \
		and bool((section as Dictionary).get("creative", false))
