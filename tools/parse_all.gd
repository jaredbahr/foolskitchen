extends SceneTree
## Loads every script (.gd) and resource (.tscn, .tres, .res) in the project
## with the autoloads present, so compile errors and broken references
## (a scene pointing at a missing script, say) surface. Errors print as
## "SCRIPT ERROR"/"ERROR:" lines, which tools/check.sh treats as failures.
## Exits 1 if anything fails to load. Hidden folders (.godot, .tools) are skipped.

const EXTENSIONS: PackedStringArray = ["gd", "tscn", "tres", "res"]


func _initialize() -> void:
	var bad := 0
	var count := 0
	var self_path := (get_script() as Script).resource_path
	for path in _find("res://"):
		# Skip the running script itself: reloading it mid-run corrupts it.
		if path == self_path:
			continue
		count += 1
		var res: Resource = ResourceLoader.load(path)
		var ok := is_instance_valid(res)
		if ok and res is GDScript:
			ok = (res as GDScript).can_instantiate()
		if not ok:
			print("LOAD FAIL %s" % path)
			bad += 1
	print("PARSE: %d files, %d failed" % [count, bad])
	quit(1 if bad > 0 else 0)


func _find(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_find(dir_path.path_join(sub)))
	for file in dir.get_files():
		if EXTENSIONS.has(file.get_extension()):
			out.append(dir_path.path_join(file))
	return out
