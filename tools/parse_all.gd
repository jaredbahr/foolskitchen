extends SceneTree
## Loads every .gd script under res://src, res://tests and res://tools with the
## project's autoloads present, so compile errors surface (as "SCRIPT ERROR"
## lines, which tools/check.sh treats as failures). Exits 1 if any script fails.

const ROOTS: PackedStringArray = ["res://src", "res://tests", "res://tools"]


func _initialize() -> void:
	var bad := 0
	var count := 0
	for root in ROOTS:
		for path in _find(root):
			# Skip the running script itself: reloading it mid-run corrupts it.
			if path == (get_script() as Script).resource_path:
				continue
			count += 1
			var s: Resource = ResourceLoader.load(path)
			if not is_instance_valid(s) or not (s is GDScript) or not (s as GDScript).can_instantiate():
				print("PARSE FAIL %s" % path)
				bad += 1
	print("PARSE: %d scripts, %d failed" % [count, bad])
	quit(1 if bad > 0 else 0)


func _find(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_find(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out
