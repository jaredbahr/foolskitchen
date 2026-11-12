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
	for context: StringName in [MusicTracks.TITLE, MusicTracks.SERVICE_DAY, MusicTracks.SERVICE_EVENING, MusicTracks.EVENING_REPORT]:
		var track: AudioStream = MusicTracks.track_for(context)
		assert_true(track is AudioStreamOggVorbis, "%s loads" % context)
		assert_true(track.get_length() > 60.0, "%s is a whole track" % context)
	assert_true(MusicTracks.track_for(&"nothing") == null, "unmapped contexts have none")
	assert_eq(MusicTracks.all_tracks().size(), 4)


func test_service_context_follows_phase_and_dusk() -> void:
	assert_eq(MusicTracks.service_context(false, 1.0), &"", "closed is silent")
	assert_eq(MusicTracks.service_context(true, 0.0), MusicTracks.SERVICE_DAY)
	assert_eq(MusicTracks.service_context(true, MusicTracks.EVENING_LIGHT), MusicTracks.SERVICE_EVENING)
	assert_eq(MusicTracks.service_context(false, 1.0, true), MusicTracks.EVENING_REPORT, "the evening report has its own song")
	assert_eq(MusicTracks.service_context(true, 0.0, true), MusicTracks.EVENING_REPORT, "a report shown during service still plays its song")
	assert_true(MusicTracks.track_for(MusicTracks.TITLE).resource_path.ends_with("kitchen_jamboree.ogg"), "Kitchen Jamboree is the title song")
	assert_true(MusicTracks.track_for(MusicTracks.EVENING_REPORT).resource_path.ends_with("stir_it_slow.ogg"), "Stir It Slow plays over the evening report")


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
