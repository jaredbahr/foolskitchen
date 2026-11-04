extends Node
## Plays the game's sounds (#117), as the `Sfx` autoload so the title screen's
## buttons click too. One-shot cues and looped ambience go to the Effects bus;
## Settings already sets its volume. Presentation only: it never touches the
## simulation, draws no random numbers and saves nothing.
##
## Headless runs and tool scripts (tests, probes, screenshot captures) create
## no players: `play` still reports the cue through `cue_played`, so tests can
## check what would be heard, and captures exit with no audio left playing.
## On the web, browsers block sound until the player first clicks or presses a
## key, so nothing plays (or queues) before then.

signal cue_played(cue: StringName)

const TUNING: SoundTuning = preload("res://data/audio/sound_tuning.tres")
const BUS: StringName = &"Effects"
const ONE_SHOT_PLAYERS: int = 8
const BUTTON_META: StringName = &"sfx_bound"
## Below this a loop is stopped rather than played very quietly.
const SILENT_LEVEL: float = 0.01

var tuning: SoundTuning = TUNING
var _throttle: SoundThrottle = SoundThrottle.new()
var _headless: bool = false
var _unlocked: bool = true
var _one_shots: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _pitch_step: Dictionary[StringName, int] = {}
var _loop_players: Dictionary[StringName, AudioStreamPlayer] = {}
var _loop_levels: Dictionary[StringName, float] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = is_silent_run(DisplayServer.get_name(), OS.get_cmdline_args())
	_unlocked = not OS.has_feature("web")
	if not _headless:
		for index: int in ONE_SHOT_PLAYERS:
			var player: AudioStreamPlayer = AudioStreamPlayer.new()
			player.name = "OneShot%d" % index
			player.bus = BUS
			add_child(player)
			_one_shots.append(player)
	get_tree().node_added.connect(_on_node_added)
	_bind_buttons(get_tree().root)


## The game itself never starts with `--script`; only tools do.
static func is_silent_run(display: String, arguments: PackedStringArray) -> bool:
	if display == "headless":
		return true
	for argument: String in arguments:
		if argument == "--script" or argument == "-s" or argument.begins_with("--script="):
			return true
	return false


## Stop and release every player so nothing is still playing at exit.
func _exit_tree() -> void:
	for player: AudioStreamPlayer in _one_shots:
		player.stop()
		player.stream = null
	for loop: StringName in _loop_players:
		_loop_players[loop].stop()
		_loop_players[loop].stream = null
	_loop_levels.clear()


func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if (event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch) \
			and event.is_pressed():
		_unlocked = true


## Plays `cue` once unless it played within its minimum interval. Returns
## whether it was let through.
func play(cue: StringName) -> bool:
	if not _unlocked or not tuning.cues.has(cue):
		return false
	if not _throttle.allow(cue, Time.get_ticks_msec() / 1000.0, tuning.interval(cue)):
		return false
	cue_played.emit(cue)
	if _headless or _one_shots.is_empty():
		return true
	var player: AudioStreamPlayer = _free_player()
	player.stream = tuning.cues[cue]
	player.volume_db = tuning.gain_db(cue)
	var step: int = _pitch_step.get(cue, 0)
	player.pitch_scale = tuning.pitch_cycle[step % tuning.pitch_cycle.size()]
	_pitch_step[cue] = step + 1
	player.play()
	return true


## Sets a looped ambience from 0 (off) to 1 (its full tuned level).
func set_loop_level(loop: StringName, level: float) -> void:
	if not tuning.loops.has(loop):
		return
	level = clampf(level, 0.0, 1.0) if _unlocked else 0.0
	_loop_levels[loop] = level
	if _headless:
		return
	var player: AudioStreamPlayer = _loop_players.get(loop)
	if level < SILENT_LEVEL:
		if player != null and player.playing:
			player.stop()
		return
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "Loop_" + String(loop)
		player.bus = BUS
		player.stream = _looping(tuning.loops[loop])
		add_child(player)
		_loop_players[loop] = player
	player.volume_db = tuning.loop_gain_db(loop) + linear_to_db(level)
	if not player.playing:
		player.play()


func loop_level(loop: StringName) -> float:
	return float(_loop_levels.get(loop, 0.0))


func stop_loops() -> void:
	for loop: StringName in _loop_levels.keys():
		set_loop_level(loop, 0.0)


## Forgets recent plays (tests use this between cases).
func reset_throttle() -> void:
	_throttle.reset()
	_pitch_step.clear()


func _free_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _one_shots:
		if not player.playing:
			return player
	var oldest: AudioStreamPlayer = _one_shots[_next_player % _one_shots.size()]
	_next_player += 1
	return oldest


static func _looping(stream: AudioStream) -> AudioStream:
	var copy: AudioStream = stream.duplicate()
	if copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	elif copy is AudioStreamWAV:
		(copy as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return copy


# --- Buttons ------------------------------------------------------------------

func _bind_buttons(node: Node) -> void:
	_on_node_added(node)
	for child: Node in node.get_children():
		_bind_buttons(child)


func _on_node_added(node: Node) -> void:
	if not node is BaseButton or node.has_meta(BUTTON_META):
		return
	node.set_meta(BUTTON_META, true)
	var button: BaseButton = node as BaseButton
	button.pressed.connect(_on_button_pressed)
	button.mouse_entered.connect(_on_button_hovered.bind(button))


func _on_button_pressed() -> void:
	play(&"click")


func _on_button_hovered(button: BaseButton) -> void:
	if is_instance_valid(button) and not button.disabled:
		play(&"hover")
