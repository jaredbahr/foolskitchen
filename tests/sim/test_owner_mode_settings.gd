extends TestCase


func test_mode_provider_defaults_validates_and_returns_detached_data() -> void:
	var settings: OwnerModeSettings = OwnerModeSettings.new()
	assert_eq(settings.current_mode(), &"rest")
	for mode: StringName in OwnerAgent.MODES:
		assert_true(settings.assign_mode(mode))
		var data: Dictionary = settings.to_dict()
		assert_eq(data, {"mode": String(mode)})
		data["mode"] = "invalid"
		assert_eq(settings.current_mode(), mode)
	assert_false(settings.assign_mode(&"invalid"))
	settings.reset()
	assert_eq(settings.current_mode(), &"rest")


func test_restore_is_transactional_and_accepts_only_canonical_mode_strings() -> void:
	var settings: OwnerModeSettings = OwnerModeSettings.new()
	assert_true(settings.restore({"mode": "kitchen"}))
	for data: Dictionary in [{}, {"mode": "KITCHEN"}, {"mode": 1},
		{"mode": null}, {"mode": "floor", "extra": true}, {"other": "help"}]:
		assert_false(settings.restore(data))
		assert_eq(settings.current_mode(), &"kitchen")
	assert_true(settings.restore({"mode": "floor"}))
	assert_eq(settings.current_mode(), &"floor")
