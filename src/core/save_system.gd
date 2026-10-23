extends Node
## Reserved save/load API. Returns ERR_UNAVAILABLE until persistence exists.
## The skeleton never reads or writes a player's saves.


func save_game(_slot_name: StringName) -> Error:
	return ERR_UNAVAILABLE


func load_game(_slot_name: StringName) -> Error:
	return ERR_UNAVAILABLE
