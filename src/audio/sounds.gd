class_name Sounds
extends RefCounted
## Game code's way to the `Sfx` autoload (#117). Tools compile some scripts
## with `--check-only`, where autoload names are not declared, so game code
## looks the node up at run time instead of naming it. Without the autoload
## (a bare tool run) every call is a quiet no-op.

const TUNING: SoundTuning = preload("res://data/audio/sound_tuning.tres")


static func play(cue: StringName) -> bool:
	var sfx: Node = _sfx()
	return sfx != null and bool(sfx.call(&"play", cue))


static func set_loop_level(loop: StringName, level: float) -> void:
	var sfx: Node = _sfx()
	if sfx != null:
		sfx.call(&"set_loop_level", loop, level)


static func stop_loops() -> void:
	var sfx: Node = _sfx()
	if sfx != null:
		sfx.call(&"stop_loops")


static func _sfx() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Sfx") if tree != null and tree.root != null else null
