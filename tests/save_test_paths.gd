class_name SaveTestPaths
extends RefCounted
## Pure namespacing for test saves; ids are arguments, never real processes.


static func process_dir(process_id: int) -> String:
	return "user://test_saves_%d/" % process_id if process_id > 0 else ""


static func case_dir(process_id: int, case_name: String) -> String:
	if process_id <= 0 or case_name.is_empty():
		return ""
	for character: String in case_name:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") and character != "_" and character != "-":
			return ""
	return process_dir(process_id) + case_name + "/"
