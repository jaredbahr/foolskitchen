extends TestCase
## UNIT identity binding only: generated blank PNG and synthetic measured
## identity/positions are not actual passing service/native review evidence.

class IdentityProbe extends "res://tools/movement_review.gd":
	var identity_failures: Array[String] = []

	func _review_fail(reason: String) -> void:
		identity_failures.append(reason)

var _probe: IdentityProbe
var _dir: String
var _png: String
var _metadata: Dictionary


func before_each() -> void:
	_dir = OS.get_user_data_dir().path_join("movement-identity-unit-%d-%d" % [OS.get_process_id(), get_instance_id()])
	assert_eq(DirAccess.make_dir_recursive_absolute(_dir), OK)
	_png = _dir.path_join("shot_0060.png")
	var image: Image = Image.create(1600, 900, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.2, 0.3, 1.0))
	assert_eq(image.save_png(_png), OK)
	_probe = IdentityProbe.new()
	# Never add this Node to the tree: no _ready/start/Main/service runs.
	_probe._review_out = _dir
	_metadata = {
		"scene": "res://tools/movement_review.tscn", "frame": 60,
		"width": 1600, "height": 900, "world_tick": 1020,
		"master_seed": "1", "new_game_seed_override": "1",
		"engine_errors": 0, "day_phase": 1,
		"capture_parameters": {"open": false, "fast_ticks_per_frame": 0, "speed": 0},
		"capture_timing": "frame_post_draw", "image_file": "shot_0060.png",
		"image_sha256": FileAccess.get_sha256(_png),
		"people": {"actors": [
			{"id": 2, "drawn_position": {"world": [3.25, 0.0, 4.375]}},
			{"id": 3, "drawn_position": {"world": [2.75, 0.0, 4.375]}},
		]},
	}


func after_each() -> void:
	if _probe != null:
		_probe.free()
	_probe = null
	for name: String in ["shot_0060.png", "shot_0060.json", "shot_0060.movement.json"]:
		DirAccess.remove_absolute(_dir.path_join(name))
	DirAccess.remove_absolute(_dir)


func test_actual_binding_accepts_canonical_json_roundtrip_identity() -> void:
	_bind(_metadata)
	assert_eq(_probe.identity_failures, [] as Array[String],
		"valid canonical JSON must pass the original real binding method")
	assert_true(FileAccess.file_exists(_dir.path_join("shot_0060.movement.json")))
	if not FileAccess.file_exists(_dir.path_join("shot_0060.movement.json")):
		return
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join("shot_0060.movement.json")))
	assert_true(result is Dictionary)
	if not result is Dictionary:
		return
	assert_eq(result.get("image_sha256"), FileAccess.get_sha256(_png))
	assert_eq(result.get("canonical_sidecar_sha256"), FileAccess.get_sha256(_dir.path_join("shot_0060.json")))
	assert_eq(result.get("scene"), _metadata.scene)
	assert_eq(result.get("frame"), 60.0)
	assert_eq(result.get("fixture"), "UNIT ONLY: identity binding, no measured native render")


func test_original_identity_gates_reject_single_field_and_parameter_mutations() -> void:
	var mutations: Array[Dictionary] = [
		{"scene": "res://src/world/main.tscn"}, {"frame": 59}, {"width": 1599}, {"height": 899},
		{"world_tick": 1019}, {"master_seed": "2"}, {"new_game_seed_override": "2"},
		{"engine_errors": 1}, {"day_phase": 2}, {"capture_timing": "before_draw"},
		{"image_file": "other.png"}, {"image_sha256": "wrong"},
		{"capture_parameters": {}},
		{"capture_parameters": {"open": false, "fast_ticks_per_frame": 0}},
		{"capture_parameters": {"open": false, "fast_ticks_per_frame": 0, "speed": 0, "extra": 0}},
		{"capture_parameters": {"open": true, "fast_ticks_per_frame": 0, "speed": 0}},
		{"capture_parameters": {"open": 0, "fast_ticks_per_frame": 0, "speed": 0}},
		{"capture_parameters": {"open": false, "fast_ticks_per_frame": false, "speed": 0}},
		{"capture_parameters": {"open": false, "fast_ticks_per_frame": "0", "speed": 0}},
		{"capture_parameters": {"open": false, "fast_ticks_per_frame": 1, "speed": 0}},
		{"capture_parameters": {"open": false, "fast_ticks_per_frame": 0.5, "speed": 0}},
		{"capture_parameters": {"open": false, "fast_ticks_per_frame": 0, "speed": false}},
		{"capture_parameters": {"open": false, "fast_ticks_per_frame": 0, "speed": "0"}},
		{"capture_parameters": {"open": false, "fast_ticks_per_frame": 0, "speed": 1}},
		{"capture_parameters": {"open": false, "fast_ticks_per_frame": 0, "speed": -0.5}},
	]
	for mutation: Dictionary in mutations:
		var metadata: Dictionary = _metadata.duplicate(true)
		metadata.merge(mutation, true)
		_bind(metadata)
		assert_eq(_probe.identity_failures.size(), 1, "single invalid field: %s" % mutation)
		assert_false(FileAccess.file_exists(_dir.path_join("shot_0060.movement.json")))


func test_canonical_people_binding_still_rejects_changed_drawn_position() -> void:
	var metadata: Dictionary = _metadata.duplicate(true)
	metadata.people.actors[0].drawn_position.world = [9.0, 0.0, 9.0]
	_bind(metadata)
	assert_eq(_probe.identity_failures,
		["canonical people evidence differs from the actual drawn passing actors"] as Array[String])
	assert_false(FileAccess.file_exists(_dir.path_join("shot_0060.movement.json")))


func _bind(metadata: Dictionary) -> void:
	DirAccess.remove_absolute(_dir.path_join("shot_0060.movement.json"))
	_probe.identity_failures.clear()
	_probe._review_render = {"world_tick": 1020, "phase": 1,
		"fixture": "UNIT ONLY: identity binding, no measured native render",
		"pair": [
			{"id": 2, "drawn_global": [3.25, 0.0, 4.375]},
			{"id": 3, "drawn_global": [2.75, 0.0, 4.375]},
		]}
	var file: FileAccess = FileAccess.open(_dir.path_join("shot_0060.json"), FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(JSON.stringify(metadata))
	file.close()
	_probe._bind_saved_capture()
