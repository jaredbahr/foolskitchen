extends Node
## Versioned JSON slots. Providers own plain-data sections; saves replace the
## destination only after the same-directory temporary file is fully written.

const FORMAT_VERSION: int = 1
const MIGRATIONS: Dictionary = {0: &"_migrate_0_to_1"}

var save_dir: String = "user://saves/"
var _providers: Dictionary[String, Dictionary] = {}


## Adds or replaces a section's capture() -> Dictionary and restore(data) -> bool.
func register(key: String, capture: Callable, restore: Callable) -> void:
	_providers[key] = {"capture": capture, "restore": restore}


## Writes a slot atomically using a temporary file in the same directory.
func save_game(slot: String) -> Error:
	if not _valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var sections: Dictionary = {}
	for key: String in _providers:
		var capture: Callable = _providers[key]["capture"]
		if not capture.is_valid():
			return FAILED
		var section: Variant = capture.call()
		if not section is Dictionary:
			return FAILED
		sections[key] = section
	var document: Dictionary = {
		"version": FORMAT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"data": sections,
	}
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(save_dir)
	if directory_error != OK:
		return directory_error
	var destination: String = _slot_path(slot)
	var temporary: String = destination + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return write_error
	var rename_error: Error = DirAccess.rename_absolute(temporary, destination)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
	return rename_error


## Migrates before restoring registered sections; absent sections are skipped.
func load_game(slot: String) -> Error:
	if not _valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var path: String = _slot_path(slot)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return read_error
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return ERR_PARSE_ERROR
	var document: Dictionary = parser.data
	var version_value: Variant = document.get("version", null)
	if not (version_value is int or version_value is float):
		return ERR_PARSE_ERROR
	var version: int = int(version_value)
	if float(version_value) != float(version) or version < 0:
		return ERR_PARSE_ERROR
	if version > FORMAT_VERSION:
		return ERR_FILE_UNRECOGNIZED
	while version < FORMAT_VERSION:
		if not MIGRATIONS.has(version):
			return ERR_FILE_UNRECOGNIZED
		document = call(MIGRATIONS[version], document)
		if int(document.get("version", -1)) != version + 1:
			return FAILED
		version += 1
	var sections_value: Variant = document.get("data", null)
	if not sections_value is Dictionary:
		return ERR_PARSE_ERROR
	var sections: Dictionary = sections_value
	# Validate section shapes before any provider mutates its state.
	for key: String in _providers:
		if sections.has(key) and not sections[key] is Dictionary:
			return ERR_PARSE_ERROR
	for key: String in _providers:
		if not sections.has(key):
			continue
		var restore: Callable = _providers[key]["restore"]
		if not restore.is_valid():
			return FAILED
		var success: Variant = restore.call(sections[key])
		if not success is bool or not success:
			return FAILED
	return OK


## Returns sorted valid slot names, excluding temporary and unrelated files.
func list_slots() -> PackedStringArray:
	var slots: PackedStringArray = []
	var directory: DirAccess = DirAccess.open(save_dir)
	if directory == null:
		return slots
	for file: String in directory.get_files():
		if file.ends_with(".json"):
			var slot: String = file.trim_suffix(".json")
			if _valid_slot(slot):
				slots.append(slot)
	slots.sort()
	return slots


## Deletes a validated slot, returning a missing-file error when it is absent.
func delete_slot(slot: String) -> Error:
	if not _valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var path: String = _slot_path(slot)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(path)


func _slot_path(slot: String) -> String:
	return save_dir.path_join(slot + ".json")


func _valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 32:
		return false
	for character: String in slot:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") and character != "_" and character != "-":
			return false
	return true


func _migrate_0_to_1(document: Dictionary) -> Dictionary:
	# Version zero has the same sections; demonstrate a single-version step.
	document["version"] = 1
	return document
