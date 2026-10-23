extends Node
## Versioned JSON slots. Providers own plain-data sections; saves replace the
## destination only after the same-directory temporary file is fully written.
## A retained backup makes interrupted replacements recoverable. This is not a
## filesystem-atomic overwrite on Windows or a power-loss durability guarantee.

const FORMAT_VERSION: int = 1
const MIGRATIONS: Dictionary = {0: &"_migrate_0_to_1"}

var save_dir: String = "user://saves/"
var _providers: Dictionary[String, Dictionary] = {}


## Adds or replaces a section's capture() -> Dictionary and restore(data) -> bool.
func register(key: String, capture: Callable, restore: Callable) -> void:
	_providers[key] = {"capture": capture, "restore": restore}


## Publishes a completed temporary file while preserving a prior recovery copy.
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
	var prepare_error: Error = _prepare_replacement(destination)
	if prepare_error != OK:
		DirAccess.remove_absolute(temporary)
		return prepare_error
	# The target must be absent: Godot's Windows rename deletes an existing target.
	var rename_error: Error = _rename_file(temporary, destination)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
	return rename_error


## Prefers the final file, or a valid backup after an interrupted/corrupt save.
## Migrates before restoring registered sections; absent sections are skipped.
func load_game(slot: String) -> Error:
	if not _valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var result: Dictionary = _read_document(_slot_path(slot))
	var read_error: Error = result["error"]
	if read_error == ERR_FILE_NOT_FOUND or read_error == ERR_PARSE_ERROR:
		var recovery: Dictionary = _read_document(_slot_path(slot) + ".bak")
		if recovery["error"] != ERR_FILE_NOT_FOUND:
			result = recovery
			read_error = recovery["error"]
	if read_error != OK:
		return read_error
	var document: Dictionary = result["document"]
	var version: int = int(document["version"])
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


## Returns sorted slot names, including backup-only slots awaiting recovery.
func list_slots() -> PackedStringArray:
	var slots: PackedStringArray = []
	var directory: DirAccess = DirAccess.open(save_dir)
	if directory == null:
		return slots
	for file: String in directory.get_files():
		if file.ends_with(".json") or file.ends_with(".json.bak"):
			var slot: String = file.trim_suffix(".bak").trim_suffix(".json")
			if _valid_slot(slot) and not slots.has(slot):
				slots.append(slot)
	slots.sort()
	return slots


## Deletes recovery and temporary copies before the final to prevent resurrection.
func delete_slot(slot: String) -> Error:
	if not _valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var path: String = _slot_path(slot)
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		return ERR_FILE_NOT_FOUND
	for candidate: String in [path + ".bak", path + ".tmp", path]:
		if FileAccess.file_exists(candidate):
			var error: Error = DirAccess.remove_absolute(candidate)
			if error != OK:
				return error
	return OK


func _prepare_replacement(destination: String) -> Error:
	var backup: String = destination + ".bak"
	if not FileAccess.file_exists(destination):
		return OK # A previous interruption may have left the only valid copy in .bak.
	if FileAccess.file_exists(backup):
		var current: Dictionary = _read_document(destination)
		if current["error"] != OK:
			var recovery: Dictionary = _read_document(backup)
			if recovery["error"] != OK:
				return current["error"] # Preserve both files if neither is readable.
			# Keep the valid backup and discard only the damaged final.
			return DirAccess.remove_absolute(destination)
		# The readable final remains intact if deleting the old backup fails.
		var remove_error: Error = DirAccess.remove_absolute(backup)
		if remove_error != OK:
			return remove_error
	return _rename_file(destination, backup)


func _rename_file(source: String, destination: String) -> Error:
	# Isolated for failure-injection tests; callers always use absent destinations.
	return DirAccess.rename_absolute(source, destination)


func _read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": ERR_FILE_NOT_FOUND}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error()}
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {"error": read_error}
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {"error": ERR_PARSE_ERROR}
	var document: Dictionary = parser.data
	var version: Variant = document.get("version", null)
	if not (version is int or version is float):
		return {"error": ERR_PARSE_ERROR}
	if not is_finite(float(version)) or float(version) < 0.0 or floorf(float(version)) != float(version):
		return {"error": ERR_PARSE_ERROR}
	if float(version) > FORMAT_VERSION:
		return {"error": ERR_FILE_UNRECOGNIZED}
	if not document.get("data", null) is Dictionary:
		return {"error": ERR_PARSE_ERROR}
	var sections: Dictionary = document["data"]
	for key: Variant in sections:
		if not sections[key] is Dictionary:
			return {"error": ERR_PARSE_ERROR}
	return {"error": OK, "document": document}


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
