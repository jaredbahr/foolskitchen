extends SceneTree
## Manual diagnostic, never a CI/workflow loop.
## godot --headless --path . --script tools/seated_head_probe.gd
## Rendered parity: godot --rendering-method gl_compatibility --path .
##   --script tools/seated_head_probe.gd -- --native-bake --out=seat-clearance.json

const CATALOGUE: GDScript = preload("res://tools/seated_head_catalogue.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var native_bake: bool = OS.get_cmdline_user_args().has("--native-bake")
	var path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			path = argument.trim_prefix("--out=")
	if native_bake and DisplayServer.get_name() == "headless":
		print("Native bake needs a rendered Compatibility session; omit --headless.")
		quit(2)
		return
	await process_frame
	var report: Dictionary = await CATALOGUE.run(root, native_bake)
	var failures: int = (report["errors"] as PackedStringArray).size()
	for sample: Dictionary in report["samples"]:
		if not sample.get("passes", false) or float(sample.get("facing_dot", 0.0)) < 0.9999:
			failures += 1
		for key: String in ["head_bounds", "person_bounds", "world_bounds"]:
			if sample.has(key):
				var bounds: AABB = sample[key]
				sample[key] = {"min": [bounds.position.x, bounds.position.y, bounds.position.z],
					"max": [bounds.end.x, bounds.end.y, bounds.end.z]}
		if sample.has("native_bake_max_error") and not is_finite(float(sample["native_bake_max_error"])):
			sample["native_bake_max_error"] = null
	for comparison: Dictionary in (report["native_bake_poses"] as Dictionary).values():
		if not is_finite(float(comparison["max_error"])):
			comparison["max_error"] = null
	report["failures"] = failures
	var output: String = JSON.stringify(report, "\t")
	if path.is_empty():
		print(output)
	else:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			print("Could not write probe report: " + path)
			quit(2)
			return
		file.store_string(output + "\n")
		file.close()
	print("SEATED HEAD: %d catalogue seats, %d native sit samples, %d failures" % [report["seats"], (report["samples"] as Array).size(), failures])
	quit(1 if failures > 0 else 0)
