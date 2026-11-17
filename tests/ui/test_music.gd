extends TestCase
## The main theme: its bus, volume setting, track resource and silence in tests.


func after_each() -> void:
	Sfx.set_music_context(&"")
	Sfx.set_music_ducked(false)
	Sfx._step_music(10.0)


func test_music_bus_exists_next_to_effects_with_a_trim() -> void:
	var music: int = AudioServer.get_bus_index(&"Music")
	assert_true(music >= 0, "Music bus")
	assert_true(AudioServer.get_bus_index(&"Effects") >= 0, "Effects bus")
	assert_almost_eq(SettingsPreferences.MUSIC_TRIM_DB, -6.0, 0.0001)
	assert_eq(Sfx.MUSIC_BUS, &"Music")


func test_music_volume_setting_persists() -> void:
	var path: String = "user://test-music-%d.cfg" % OS.get_process_id()
	var prefs: SettingsPreferences = SettingsPreferences.new(path)
	assert_true(prefs.set_volume_percent(&"Music", 42))
	var restored: SettingsPreferences = SettingsPreferences.new(path)
	assert_true(restored.load_from_disk())
	assert_eq(restored.music_volume_percent, 42)
	prefs.free()
	restored.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	prefs = SettingsPreferences.new()
	prefs.apply_audio()
	prefs.free()


func test_apply_audio_puts_music_six_db_under_the_slider() -> void:
	var prefs: SettingsPreferences = SettingsPreferences.new("user://test-music-bus.cfg")
	prefs.music_volume_percent = 100
	prefs.apply_audio()
	var index: int = AudioServer.get_bus_index(&"Music")
	assert_almost_eq(AudioServer.get_bus_volume_db(index), -6.0, 0.01)
	prefs.free()


func test_every_track_loads_and_is_mapped() -> void:
	for context: StringName in [MusicTracks.TITLE, MusicTracks.SERVICE_DAY, MusicTracks.SERVICE_EVENING]:
		for i: int in MusicTracks.track_count(context):
			var track: AudioStream = MusicTracks.track_for(context, i)
			assert_true(track is AudioStreamOggVorbis, "%s %d loads" % [context, i])
			assert_true(track.get_length() > 60.0, "%s %d is a whole track" % [context, i])
	assert_true(MusicTracks.track_for(&"nothing") == null, "unmapped contexts have none")
	assert_eq(MusicTracks.all_tracks().size(), 7, "the bar and evening share one Smoky Vamp stream")
	assert_eq(MusicTracks.track_count(MusicTracks.SERVICE_DAY), 2, "daytime service has two tracks")


func test_service_context_follows_phase_and_dusk() -> void:
	assert_eq(MusicTracks.service_context(false, 1.0), &"", "closed is silent")
	assert_eq(MusicTracks.service_context(true, 0.0), MusicTracks.SERVICE_DAY)
	assert_eq(MusicTracks.service_context(true, MusicTracks.EVENING_LIGHT), MusicTracks.SERVICE_EVENING)
	for theme: StringName in [&"", &"modern", &"cosy", &"rustic"]:
		assert_eq(MusicTracks.service_context(true, 0.0, theme), MusicTracks.SERVICE_DAY)
		assert_eq(MusicTracks.service_context(true, 1.0, theme), MusicTracks.SERVICE_EVENING)
	assert_true(MusicTracks.track_for(MusicTracks.SERVICE_EVENING).resource_path.ends_with("smoky_vamp.ogg"))
	assert_null(MusicTracks.track_for(MusicTracks.MORNING))
	assert_null(MusicTracks.track_for(MusicTracks.REPORT), "the report has no separate song")


func test_themes_have_the_expected_playable_loop_imports() -> void:
	var expected: Dictionary[StringName, String] = {&"bar": "smoky_vamp.ogg",
		&"diner": "diner_boogie.ogg", &"cafe": "coffee_shop_morning.ogg", &"seafood": "coastal_afternoon.ogg"}
	for theme: StringName in expected:
		assert_eq(MusicTracks.service_context(true, 0.0, theme), theme)
		assert_eq(MusicTracks.service_context(true, 1.0, theme), theme)
		assert_eq(MusicTracks.track_for(theme).resource_path, "res://assets/music/" + expected[theme])
	for theme: StringName in MusicTracks.BY_THEME:
		var tracks: Array = MusicTracks.BY_THEME[theme]
		assert_false(tracks.is_empty())
		for track: AudioStreamOggVorbis in tracks:
			assert_true(track.get_length() > 60.0 and track.loop, track.resource_path)
			assert_true(FileAccess.file_exists(track.resource_path), track.resource_path)
			var sidecar: ConfigFile = ConfigFile.new()
			assert_eq(sidecar.load(track.resource_path + ".import"), OK)
			assert_eq(sidecar.get_value("params", "loop", false), true, track.resource_path)
	for reserved: String in ["hazy_breakbeat.ogg", "sleek_groove.ogg", "buoyant_sea_shanty.ogg"]:
		for track: AudioStream in MusicTracks.all_tracks():
			assert_false(track.resource_path.ends_with(reserved), reserved + " is still reserved")


func test_themed_selection_uses_the_day_and_loops_its_pick() -> void:
	var diner: AudioStream = MusicTracks.track_for(&"diner")
	var cafe: AudioStream = MusicTracks.track_for(&"cafe")
	var pair: Array[AudioStream] = [diner, cafe]
	assert_eq(MusicTracks.track_at(pair, 1), cafe)
	assert_eq(MusicTracks.track_at(pair, 2), diner)
	assert_eq(MusicTracks.track_at(pair, 3), cafe)
	Sfx.set_music_context(&"diner", 3)
	assert_eq(Sfx._music_index, 3, "the selector passes the day to the wrap for a theme list")
	Sfx.advance_music()
	assert_eq(Sfx._music_index, 3, "the room's selected song loops until the day changes")
	Sfx.set_music_context(MusicTracks.MORNING)
	Sfx.set_music_context(&"diner", 3)
	assert_eq(Sfx._music_index, 3, "selecting service again on the saved day picks the same song")
	assert_eq(Sfx.music_track(), diner)
	Sfx.set_music_context(&"diner", 4)
	assert_eq(Sfx._music_index, 4)


func test_title_plays_stir_it_slow_the_full_take() -> void:
	var title: AudioStream = MusicTracks.track_for(MusicTracks.TITLE)
	assert_true(title.resource_path.ends_with("stir_it_slow.ogg"), "Stir It Slow is the title song")
	assert_almost_eq(title.get_length(), 164.4, 1.0, "the take with vocals, about 2:44")
	Sfx.set_music_context(MusicTracks.TITLE)
	assert_true(Sfx.music_track() == title)


func test_day_service_alternates_buoyant_then_jamboree() -> void:
	var buoyant: AudioStream = MusicTracks.track_for(MusicTracks.SERVICE_DAY, 0)
	var jamboree: AudioStream = MusicTracks.track_for(MusicTracks.SERVICE_DAY, 1)
	assert_true(buoyant.resource_path.ends_with("buoyant_swing_groove.ogg"), "starts with Buoyant Swing Groove")
	assert_true(jamboree.resource_path.ends_with("kitchen_jamboree.ogg"), "then Kitchen Jamboree")
	assert_true(MusicTracks.in_playlist(buoyant) and MusicTracks.in_playlist(jamboree))
	Sfx.set_music_context(MusicTracks.SERVICE_DAY)
	assert_true(Sfx.music_track() == buoyant)
	Sfx.advance_music()
	assert_true(Sfx.music_track() == jamboree, "the other follows")
	Sfx.advance_music()
	assert_true(Sfx.music_track() == buoyant, "and back round")
	Sfx.advance_music()
	Sfx.set_music_context(MusicTracks.SERVICE_EVENING)
	Sfx.set_music_context(MusicTracks.SERVICE_DAY)
	assert_true(Sfx.music_track() == buoyant, "a new day context starts with Buoyant Swing Groove again")


func test_track_change_in_one_context_crossfades() -> void:
	var buoyant: AudioStream = MusicTracks.track_for(MusicTracks.SERVICE_DAY, 0)
	var jamboree: AudioStream = MusicTracks.track_for(MusicTracks.SERVICE_DAY, 1)
	Sfx.set_music_context(MusicTracks.SERVICE_DAY)
	Sfx._step_music(Sfx.MUSIC_FADE_SECONDS)
	assert_almost_eq(Sfx.music_level(buoyant), 1.0, 0.0001)
	Sfx.advance_music()
	Sfx._step_music(Sfx.MUSIC_FADE_SECONDS / 2.0)
	assert_almost_eq(Sfx.music_level(buoyant), 0.5, 0.01)
	assert_almost_eq(Sfx.music_level(jamboree), 0.5, 0.01)


func test_report_keeps_the_actual_service_track_even_when_the_light_changes() -> void:
	var director: SoundDirector = SoundDirector.new()
	director._refresh_service_music(true, 0.0, false, 0)
	Sfx.advance_music()
	var track: AudioStream = MusicTracks.track_for(MusicTracks.SERVICE_DAY, 1)
	Sfx._step_music(Sfx.MUSIC_FADE_SECONDS)
	director._refresh_service_music(false, 1.0, true, 100)
	assert_eq(Sfx.music_context(), MusicTracks.SERVICE_DAY)
	assert_eq(Sfx.music_track(), track, "the report keeps the second song, even if it opens at dusk")
	assert_eq(Sfx.music_level(track), 1.0)
	director._refresh_service_music(false, 1.0, false, 200)
	assert_null(Sfx.music_track(), "closing the report fades to silence")
	director._refresh_service_music(false, 1.0, true, 300)
	assert_null(Sfx.music_track(), "reopening the report does not start a song")
	director.free()


func test_theme_changes_hold_for_sixty_seconds_of_monotonic_time() -> void:
	var director: SoundDirector = SoundDirector.new()
	var vibe: VibeModel.Result = VibeModel.Result.new()
	vibe.valid = true
	vibe.active_theme = &"diner"
	director.set_vibe(vibe)
	var started: int = 1743
	director._refresh_service_music(true, 0.0, false, started)
	assert_eq(Sfx.music_context(), &"diner")
	vibe.active_theme = &"bar"
	director.set_vibe(vibe)
	director._refresh_service_music(true, 0.0, false, started + 1)
	assert_eq(Sfx.music_context(), &"diner")
	vibe.active_theme = &"seafood"
	director.set_vibe(vibe)
	director._refresh_service_music(true, 1.0, false, started + 59_999_999)
	assert_eq(Sfx.music_context(), &"diner")
	var diner: AudioStream = Sfx.music_track()
	Sfx._step_music(Sfx.MUSIC_FADE_SECONDS)
	director._refresh_service_music(true, 1.0, false, started + 60_000_000)
	assert_eq(Sfx.music_context(), &"seafood", "choose the latest room theme at the exact boundary")
	var seafood: AudioStream = Sfx.music_track()
	Sfx._step_music(Sfx.MUSIC_FADE_SECONDS / 2.0)
	assert_almost_eq(Sfx.music_level(diner), 0.5, 0.01)
	assert_almost_eq(Sfx.music_level(seafood), 0.5, 0.01)
	vibe.active_theme = &""
	director.set_vibe(vibe)
	director._refresh_service_music(true, 1.0, false, started + 119_999_999)
	assert_eq(Sfx.music_context(), &"seafood")
	director._refresh_service_music(true, 1.0, false, started + 120_000_000)
	assert_eq(Sfx.music_context(), MusicTracks.SERVICE_EVENING)
	director.free()


func test_default_service_still_changes_at_dusk() -> void:
	var director: SoundDirector = SoundDirector.new()
	director._refresh_service_music(true, 0.0, false, 0)
	assert_eq(Sfx.music_context(), MusicTracks.SERVICE_DAY)
	director._refresh_service_music(true, MusicTracks.EVENING_LIGHT, false, 1)
	assert_eq(Sfx.music_context(), MusicTracks.SERVICE_EVENING)
	director.free()


func test_music_is_silent_in_headless_runs() -> void:
	assert_true(Sfx.is_silent_run("headless", PackedStringArray()))
	assert_true(Sfx.is_silent_run("x11", PackedStringArray(["--script", "a.gd"])))
	Sfx.set_music_context(MusicTracks.TITLE)
	Sfx._step_music(0.5)
	assert_true(Sfx._music_players.is_empty(), "no player is created")
	for child: Node in Sfx.get_children():
		if child is AudioStreamPlayer:
			assert_false((child as AudioStreamPlayer).playing, "%s is silent" % child.name)


func test_context_change_crossfades_and_a_jukebox_ducks() -> void:
	var day: AudioStream = MusicTracks.track_for(MusicTracks.SERVICE_DAY)
	var evening: AudioStream = MusicTracks.track_for(MusicTracks.SERVICE_EVENING)
	Sfx.set_music_context(MusicTracks.SERVICE_DAY)
	Sfx._step_music(Sfx.MUSIC_FADE_SECONDS)
	assert_almost_eq(Sfx.music_level(day), 1.0, 0.0001)
	Sfx.set_music_context(MusicTracks.SERVICE_EVENING)
	Sfx._step_music(Sfx.MUSIC_FADE_SECONDS / 2.0)
	assert_almost_eq(Sfx.music_level(day), 0.5, 0.01, "day fades out")
	assert_almost_eq(Sfx.music_level(evening), 0.5, 0.01, "evening fades in")
	Sfx._step_music(Sfx.MUSIC_FADE_SECONDS)
	assert_almost_eq(Sfx.music_level(day), 0.0, 0.0001)
	Sfx.set_music_ducked(true)
	Sfx._step_music(Sfx.MUSIC_FADE_SECONDS)
	assert_almost_eq(Sfx.music_level(), 0.0, 0.0001, "a jukebox takes over")
	Sfx.set_music_ducked(false)
	Sfx.set_music_context(&"")
	Sfx._step_music(Sfx.MUSIC_FADE_SECONDS)
	assert_almost_eq(Sfx.music_level(), 0.0, 0.0001, "closed is silent")

## A playlist track must be able to end, or the day never reaches its second
## song: the imported oggs loop, so the player gets a copy that does not.
func test_playlist_tracks_play_once_and_others_loop() -> void:
	var day: Array = MusicTracks.BY_CONTEXT[MusicTracks.SERVICE_DAY]
	assert_eq(day.size(), 2)
	for track: AudioStream in day:
		var stream: AudioStreamOggVorbis = Sfx.music_stream_for(track) as AudioStreamOggVorbis
		assert_false(stream.loop, "%s plays once" % track.resource_path.get_file())
		assert_true((track as AudioStreamOggVorbis).loop, "the shared import is untouched")
	var title: AudioStreamOggVorbis = Sfx.music_stream_for(MusicTracks.track_for(MusicTracks.TITLE)) as AudioStreamOggVorbis
	assert_true(title.loop, "the title loops")
