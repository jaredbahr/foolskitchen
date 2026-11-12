extends Node
## Plays the game's sounds (#117), as the `Sfx` autoload so the title screen's
## buttons click too. One-shot cues and station loops go to the Effects bus;
## the room tone, chatter and table clinks (#366) go to the Ambience bus.
## Settings sets both volumes. Presentation only: it never touches the
## simulation or its random streams, and saves nothing. Clinks pick a variant
## and a pitch from this node's own seeded generator.
##
## Headless runs and tool scripts (tests, probes, screenshot captures) create
## no players: `play` still reports the cue through `cue_played`, so tests can
## check what would be heard, and captures exit with no audio left playing.
## On the web, browsers block sound until the player first clicks or presses a
## key, so nothing plays (or queues) before then.

signal cue_played(cue: StringName)
## A table clink (#366) let through, reported headless too, like `cue_played`.
signal clink_played(kind: StringName)

const TUNING: SoundTuning = preload("res://data/audio/sound_tuning.tres")
const AMBIENCE: AmbienceTuning = preload("res://data/audio/ambience.tres")
const BUS: StringName = &"Effects"
const AMBIENCE_BUS: StringName = &"Ambience"
const MUSIC_BUS: StringName = &"Music"
## Seconds for a track to fade fully in or out; a crossfade runs both at once.
const MUSIC_FADE_SECONDS: float = 2.0
const ONE_SHOT_PLAYERS: int = 8
## Clinks placed at their table (panned by the camera) and a few unplaced ones.
const CLINK_PLAYERS: int = 6
const PLAIN_CLINK_PLAYERS: int = 2
## Clinks' own generator seed: a presentation stream, never the sim's.
const CLINK_SEED: int = 366
const BUTTON_META: StringName = &"sfx_bound"
## Below this a loop is stopped rather than played very quietly.
const SILENT_LEVEL: float = 0.01

var tuning: SoundTuning = TUNING
var ambience: AmbienceTuning = AMBIENCE
var _throttle: SoundThrottle = SoundThrottle.new()
var _headless: bool = false
var _unlocked: bool = true
var _one_shots: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _pitch_step: Dictionary[StringName, int] = {}
var _loop_players: Dictionary[StringName, AudioStreamPlayer] = {}
var _loop_levels: Dictionary[StringName, float] = {}
var _clink_players: Array[AudioStreamPlayer3D] = []
var _plain_clink_players: Array[AudioStreamPlayer] = []
var _next_clink: int = 0
var _clink_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## One player and one fade level per track, so a change of context crossfades.
var _music_players: Dictionary[AudioStream, AudioStreamPlayer] = {}
var _music_levels: Dictionary[AudioStream, float] = {}
var _music_context: StringName = &""
var _music_ducked: bool = false


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
		for index: int in CLINK_PLAYERS:
			var placed: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
			placed.name = "Clink%d" % index
			placed.bus = AMBIENCE_BUS
			# Pan only: a clink across the room is as loud as one nearby.
			placed.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			placed.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			placed.panning_strength = ambience.panning_strength
			add_child(placed)
			_clink_players.append(placed)
		for index: int in PLAIN_CLINK_PLAYERS:
			var plain: AudioStreamPlayer = AudioStreamPlayer.new()
			plain.name = "PlainClink%d" % index
			plain.bus = AMBIENCE_BUS
			add_child(plain)
			_plain_clink_players.append(plain)
	_clink_rng.seed = CLINK_SEED
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
	for player: AudioStreamPlayer in _one_shots + _plain_clink_players:
		player.stop()
		player.stream = null
	for placed: AudioStreamPlayer3D in _clink_players:
		placed.stop()
		placed.stream = null
	for loop: StringName in _loop_players:
		_loop_players[loop].stop()
		_loop_players[loop].stream = null
	_loop_levels.clear()
	for track: AudioStream in _music_players:
		_music_players[track].stop()
		_music_players[track].stream = null


func _process(delta: float) -> void:
	_step_music(delta)


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


## Plays one table clink of `kind` (#366) unless that kind played within its
## minimum interval: a random variant at a random pitch within the tuned
## spread, from Sfx's own generator. With `positioned`, it sounds from
## `world_position` and pans with the camera. Returns whether it was let through.
func play_clink(kind: StringName, world_position: Vector3 = Vector3.ZERO, positioned: bool = false) -> bool:
	var clink_set: ClinkSet = ambience.clink(kind)
	if not _unlocked or clink_set == null or clink_set.streams.is_empty():
		return false
	if not _throttle.allow(StringName("clink_" + String(kind)), Time.get_ticks_msec() / 1000.0, clink_set.min_interval):
		return false
	var stream: AudioStream = clink_set.streams[_clink_rng.randi_range(0, clink_set.streams.size() - 1)]
	var pitch: float = AmbienceMix.pitch(_clink_rng, ambience.pitch_spread)
	clink_played.emit(kind)
	if _headless or stream == null:
		return true
	if positioned and not _clink_players.is_empty():
		var placed: AudioStreamPlayer3D = _free_clink_player()
		placed.global_position = world_position
		placed.stream = stream
		placed.volume_db = clink_set.volume_db
		placed.pitch_scale = pitch
		placed.play()
	elif not _plain_clink_players.is_empty():
		var plain: AudioStreamPlayer = _plain_clink_players[0]
		for candidate: AudioStreamPlayer in _plain_clink_players:
			if not candidate.playing:
				plain = candidate
				break
		plain.stream = stream
		plain.volume_db = clink_set.volume_db
		plain.pitch_scale = pitch
		plain.play()
	return true


## Sets a looped ambience from 0 (off) to 1 (its full tuned level). Station
## and jukebox loops play on the Effects bus, the room tone and chatter on the
## Ambience bus. A known loop with no file yet keeps its level and plays nothing.
func set_loop_level(loop: StringName, level: float) -> void:
	var ambient: bool = ambience.loops.has(loop)
	if not ambient and not tuning.loops.has(loop):
		return
	level = clampf(level, 0.0, 1.0) if _unlocked else 0.0
	_loop_levels[loop] = level
	var stream: AudioStream = ambience.loops[loop] if ambient else tuning.loops[loop]
	if _headless or stream == null:
		return
	var player: AudioStreamPlayer = _loop_players.get(loop)
	if level < SILENT_LEVEL:
		if player != null and player.playing:
			player.stop()
		return
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "Loop_" + String(loop)
		player.bus = AMBIENCE_BUS if ambient else BUS
		player.stream = _looping(stream)
		add_child(player)
		_loop_players[loop] = player
	var gain: float = ambience.loop_gain_db(loop) if ambient else tuning.loop_gain_db(loop)
	player.volume_db = gain + linear_to_db(level)
	if not player.playing:
		player.play()


## Music for one part of the game (`MusicTracks`); an empty or unknown context
## fades the music out. Looping, fading and silence in headless runs are handled
## here, so callers only say where the game is.
func set_music_context(context: StringName) -> void:
	_music_context = context


## A jukebox playing its own loop takes over: the theme fades out while ducked.
func set_music_ducked(ducked: bool) -> void:
	_music_ducked = ducked


func music_context() -> StringName:
	return _music_context


## 1 when the current context has a track and nothing is ducking it, else 0.
func music_target() -> float:
	return 0.0 if _music_ducked or MusicTracks.track_for(_music_context) == null else 1.0


## A track's current fade level, 0 (silent) to 1. Headless runs track it but
## play nothing. With no track given, the loudest one.
func music_level(track: AudioStream = null) -> float:
	if track != null:
		return float(_music_levels.get(track, 0.0))
	var loudest: float = 0.0
	for level: float in _music_levels.values():
		loudest = maxf(loudest, level)
	return loudest


func is_unlocked() -> bool:
	return _unlocked


func _step_music(delta: float) -> void:
	var wanted: AudioStream = MusicTracks.track_for(_music_context) if _unlocked and not _music_ducked else null
	for track: AudioStream in MusicTracks.all_tracks():
		var target: float = 1.0 if track == wanted else 0.0
		var level: float = move_toward(float(_music_levels.get(track, 0.0)), target, delta / MUSIC_FADE_SECONDS)
		_music_levels[track] = level
		if not _headless:
			_apply_music_player(track, level, target)


func _apply_music_player(track: AudioStream, level: float, target: float) -> void:
	var player: AudioStreamPlayer = _music_players.get(track)
	if level < SILENT_LEVEL and target == 0.0:
		if player != null and player.playing:
			player.stop()
		return
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "Music_" + track.resource_path.get_file().get_basename()
		player.bus = MUSIC_BUS
		player.stream = _looping(track)
		add_child(player)
		_music_players[track] = player
	player.volume_db = linear_to_db(maxf(level, 0.0001))
	if not player.playing and level >= SILENT_LEVEL:
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
	_clink_rng.seed = CLINK_SEED


func _free_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _one_shots:
		if not player.playing:
			return player
	var oldest: AudioStreamPlayer = _one_shots[_next_player % _one_shots.size()]
	_next_player += 1
	return oldest


func _free_clink_player() -> AudioStreamPlayer3D:
	for placed: AudioStreamPlayer3D in _clink_players:
		if not placed.playing:
			return placed
	var oldest: AudioStreamPlayer3D = _clink_players[_next_clink % _clink_players.size()]
	_next_clink += 1
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
