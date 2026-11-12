extends TestCase
## #366: the dining-room ambience's mixing rules (a pure helper), its data
## file and the Sfx clinks, which report headless like the other cues.

const AMBIENCE: AmbienceTuning = preload("res://data/audio/ambience.tres")
const KINDS: Array[StringName] = [&"plate", &"cutlery", &"dish_stack", &"sink", &"glass"]

var _clinks: Array[StringName] = []


func before_each() -> void:
	_clinks.clear()
	Sfx.reset_throttle()
	Sfx.clink_played.connect(_on_clink)


func after_each() -> void:
	if Sfx.clink_played.is_connected(_on_clink):
		Sfx.clink_played.disconnect(_on_clink)
	Sfx.stop_loops()
	Sfx.reset_throttle()


func _on_clink(kind: StringName) -> void:
	_clinks.append(kind)


func _anchors() -> Dictionary[StringName, int]:
	return {&"chatter_light": 2, &"chatter_busy": 8, &"chatter_packed": 16} as Dictionary[StringName, int]


func test_data_file_has_every_clink_kind_with_enough_variants() -> void:
	assert_true(AMBIENCE.is_valid())
	for kind: StringName in KINDS:
		var clink_set: ClinkSet = AMBIENCE.clink(kind)
		assert_not_null(clink_set, "clink %s" % kind)
		assert_true(clink_set.streams.size() >= AmbienceTuning.MIN_CLINK_VARIANTS, "%s has at least 4 variants" % kind)
		assert_true(clink_set.min_interval > 0.0, "%s is throttled" % kind)
	assert_almost_eq(AMBIENCE.pitch_spread, 0.05, 0.0001, "the issue's +-5% pitch")
	for layer: StringName in AmbienceTuning.CHATTER_LAYERS:
		assert_true(AMBIENCE.loops.has(layer), "%s has a slot for its file" % layer)


func test_no_crowd_or_no_layers_is_silent() -> void:
	var levels: Dictionary[StringName, float] = AmbienceMix.chatter_levels(0, _anchors())
	for layer: StringName in levels:
		assert_almost_eq(levels[layer], 0.0, 0.0001, "%s silent in an empty room" % layer)
	assert_true(AmbienceMix.chatter_levels(10, {} as Dictionary[StringName, int]).is_empty())


func test_each_layer_is_full_at_its_crowd_and_alone() -> void:
	for pair: Array in [[2, &"chatter_light"], [8, &"chatter_busy"], [16, &"chatter_packed"]]:
		var levels: Dictionary[StringName, float] = AmbienceMix.chatter_levels(pair[0], _anchors())
		for layer: StringName in levels:
			var expected: float = 1.0 if layer == pair[1] else 0.0
			assert_almost_eq(levels[layer], expected, 0.0001, "%d guests: %s" % [pair[0], layer])


func test_layers_crossfade_at_equal_power_and_swell_with_the_crowd() -> void:
	var previous_busy: float = -1.0
	for crowd: int in range(3, 8):
		var levels: Dictionary[StringName, float] = AmbienceMix.chatter_levels(crowd, _anchors())
		var power: float = levels[&"chatter_light"] ** 2 + levels[&"chatter_busy"] ** 2
		assert_almost_eq(power, 1.0, 0.0001, "%d guests keep the same loudness" % crowd)
		assert_almost_eq(levels[&"chatter_packed"], 0.0, 0.0001)
		assert_true(levels[&"chatter_busy"] > previous_busy, "busy grows with the crowd")
		previous_busy = levels[&"chatter_busy"]
	var one: Dictionary[StringName, float] = AmbienceMix.chatter_levels(1, _anchors())
	assert_true(one[&"chatter_light"] > 0.0 and one[&"chatter_light"] < 1.0, "a lone guest is a quiet murmur")


func test_a_packed_room_stays_packed_and_missing_layers_drop_out() -> void:
	var packed: Dictionary[StringName, float] = AmbienceMix.chatter_levels(60, _anchors())
	assert_almost_eq(packed[&"chatter_packed"], 1.0, 0.0001)
	assert_almost_eq(packed[&"chatter_busy"], 0.0, 0.0001)
	var two: Dictionary[StringName, int] = {&"chatter_light": 2, &"chatter_busy": 8} as Dictionary[StringName, int]
	var levels: Dictionary[StringName, float] = AmbienceMix.chatter_levels(30, two)
	assert_false(levels.has(&"chatter_packed"), "a layer with no file is absent")
	assert_almost_eq(levels[&"chatter_busy"], 1.0, 0.0001, "the loudest file covers a packed room")


func test_the_shipped_chatter_is_three_quiet_loops() -> void:
	# Jared: the chatter is a barely audible bed, a few percent of full volume.
	for layer: StringName in AmbienceTuning.CHATTER_LAYERS:
		var stream: AudioStreamOggVorbis = AMBIENCE.loops.get(layer) as AudioStreamOggVorbis
		assert_not_null(stream, "%s has a file" % layer)
		assert_true(stream.loop, "%s loops" % layer)
		assert_true(stream.get_length() >= 20.0, "%s is a long loop" % layer)
		assert_true(float(AMBIENCE.loop_volume_db.get(layer, 0.0)) <= -20.0, "%s stays very quiet" % layer)
		assert_true(AMBIENCE.chatter_anchors().has(layer), "%s takes part in the crossfade" % layer)


func test_jukebox_ducks_chatter_and_fades_are_gradual() -> void:
	assert_almost_eq(AmbienceMix.chatter_gain(false, -8.0), 1.0)
	assert_almost_eq(AmbienceMix.chatter_gain(true, -8.0), db_to_linear(-8.0), 0.0001)
	assert_almost_eq(AmbienceMix.fade(1.0, 0.0, 1.0, 4.0), 0.75, 0.0001, "a quarter of a 4 s fade per second")
	assert_almost_eq(AmbienceMix.fade(0.9, 1.0, 1.0, 4.0), 1.0, 0.0001, "never overshoots")


func test_cutlery_rate_grows_with_eaters_and_is_capped() -> void:
	assert_almost_eq(AmbienceMix.cutlery_rate(0, 0.08, 1.2), 0.0)
	assert_almost_eq(AmbienceMix.cutlery_rate(5, 0.08, 1.2), 0.4, 0.0001)
	assert_true(AmbienceMix.cutlery_rate(6, 0.08, 1.2) > AmbienceMix.cutlery_rate(5, 0.08, 1.2))
	assert_almost_eq(AmbienceMix.cutlery_rate(200, 0.08, 1.2), 1.2, 0.0001, "a packed room is capped")
	assert_almost_eq(AmbienceMix.cutlery_rate(-3, 0.08, 1.2), 0.0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	assert_true(is_inf(AmbienceMix.next_gap(rng, 0.0)), "nobody eating never clinks")
	var total: float = 0.0
	for index: int in 400:
		var gap: float = AmbienceMix.next_gap(rng, 1.2)
		assert_true(gap > 0.0)
		total += gap
	assert_almost_eq(total / 400.0, 1.0 / 1.2, 0.15, "gaps average out to the rate")


func test_clink_pitch_stays_within_five_percent() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var low: float = 2.0
	var high: float = 0.0
	for index: int in 500:
		var pitch: float = AmbienceMix.pitch(rng, 0.05)
		low = minf(low, pitch)
		high = maxf(high, pitch)
	assert_true(low >= 0.95 and high <= 1.05, "%f..%f" % [low, high])
	assert_true(high - low > 0.05, "pitches actually vary")


func test_clinks_report_headless_and_throttle_bursts_per_kind() -> void:
	assert_true(Sfx.play_clink(&"plate", Vector3(3, 0, 4), true))
	assert_false(Sfx.play_clink(&"plate"), "a burst of deliveries in one frame is one clink")
	assert_true(Sfx.play_clink(&"glass"), "each kind has its own clock")
	assert_false(Sfx.play_clink(&"no_such_clink"))
	assert_eq(_clinks, [&"plate", &"glass"] as Array[StringName])


func test_ambience_uses_its_own_bus() -> void:
	assert_eq(Sfx.AMBIENCE_BUS, &"Ambience")
	assert_true(AudioServer.get_bus_index(Sfx.AMBIENCE_BUS) >= 0, "the bus layout has Ambience")
