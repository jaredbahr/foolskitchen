class_name Sounds
extends RefCounted
## Game code's way to the `Sfx` autoload (#117). Tools compile some scripts
## with `--check-only`, where autoload names are not declared, so game code
## looks the node up at run time instead of naming it. Without the autoload
## (a bare tool run) every call is a quiet no-op.

const TUNING: SoundTuning = preload("res://data/audio/sound_tuning.tres")
const AMBIENCE: AmbienceTuning = preload("res://data/audio/ambience.tres")


static func play(cue: StringName) -> bool:
	var sfx: Node = _sfx()
	return sfx != null and bool(sfx.call(&"play", cue))


## A table clink (#366); with `positioned`, it pans from `world_position`.
static func play_clink(kind: StringName, world_position: Vector3 = Vector3.ZERO, positioned: bool = false) -> bool:
	var sfx: Node = _sfx()
	return sfx != null and bool(sfx.call(&"play_clink", kind, world_position, positioned))


static func set_loop_level(loop: StringName, level: float) -> void:
	var sfx: Node = _sfx()
	if sfx != null:
		sfx.call(&"set_loop_level", loop, level)


static func stop_loops() -> void:
	var sfx: Node = _sfx()
	if sfx != null:
		sfx.call(&"stop_loops")


## Where the game is, for the music (`MusicTracks`): "" for none.
static func set_music_context(context: StringName) -> void:
	var sfx: Node = _sfx()
	if sfx != null:
		sfx.call(&"set_music_context", context)


static func set_music_ducked(ducked: bool) -> void:
	var sfx: Node = _sfx()
	if sfx != null:
		sfx.call(&"set_music_ducked", ducked)


static func _sfx() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Sfx") if tree != null and tree.root != null else null
