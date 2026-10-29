extends TestCase
## The picker requests presentation changes; Main alone commits the profile.

var _picker: OwnerPicker
var _profile: OwnerAppearance
var _confirmations: Array[Dictionary] = []
var _random_requests: int = 0
var _cancel_requests: int = 0
var _viewports: Array[SubViewport] = []


func before_each() -> void:
	# Acquire native UI after autoload initialization rather than retaining a
	# PackedScene graph in the test entry script's constants.
	_picker = (load("res://src/ui/owner_picker.tscn") as PackedScene).instantiate() as OwnerPicker
	_profile = OwnerAppearance.new()
	_picker.confirmed.connect(_record_confirmation)
	_picker.random_requested.connect(_record_random_request)
	_picker.cancelled.connect(_record_cancel_request)


func after_each() -> void:
	_picker.free()
	for viewport: SubViewport in _viewports:
		viewport.free()
	_viewports.clear()


func test_staff_heading_keeps_maximum_name_and_action_inside_small_ui_bounds() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var viewport: SubViewport = SubViewport.new()
	# Logical area of a 1280×720 window at the supported enlarged UI scale.
	viewport.size = Vector2i(1066, 600)
	tree.root.add_child(viewport)
	_viewports.append(viewport)
	var staff: StaffPanel = (load("res://src/ui/staff_panel.tscn") as PackedScene).instantiate() as StaffPanel
	viewport.add_child(staff)
	staff.bind_roster(StaffRoster.new(preload("res://data/balance/tier1_economy.tres")))
	staff.set_owner_name("W".repeat(OwnerAppearance.MAX_NAME_LENGTH))
	staff.set_phase(SimClock.Phase.MORNING)
	staff.show()
	await tree.process_frame
	await tree.process_frame
	var heading: Label = staff.get_node("Panel/Content/Title") as Label
	var name: Label = staff.get_node("%OwnerName") as Label
	var button: Button = staff.get_node("%OwnerLook") as Button
	var context: String = "heading=%s button=%s name=%s" % [heading.get_global_rect(), button.get_global_rect(), name.get_global_rect()]
	assert_true(heading.get_global_rect().encloses(button.get_global_rect()), "the action shares the existing heading: " + context)
	assert_true(heading.get_global_rect().encloses(name.get_global_rect()), context)
	assert_true(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(heading.get_global_rect()))
	assert_true(name.get_global_rect().end.x <= button.get_global_rect().position.x)
	assert_true(name.clip_text)
	assert_eq(name.tooltip_text, OwnerText.owner_label("W".repeat(OwnerAppearance.MAX_NAME_LENGTH)))
	assert_false(button.disabled)


func test_picker_lists_all_twelve_native_looks_with_plain_labels_and_shared_theme() -> void:
	_picker.open(_profile)
	assert_true(_picker.visible)
	assert_eq(_picker.theme, load("res://src/ui/theme/main_theme.tres"))
	assert_eq((_picker.get_node("%Title") as Label).text, OwnerText.TITLE)
	assert_eq((_picker.get_node("%NameLabel") as Label).text, OwnerText.NAME_LABEL)
	assert_eq((_picker.get_node("%Confirm") as Button).text, OwnerText.CONFIRM)
	assert_eq((_picker.get_node("%Random") as Button).text, OwnerText.RANDOM)
	assert_eq((_picker.get_node("%Cancel") as Button).text, OwnerText.CANCEL)
	var choices: HBoxContainer = _picker.get_node("%Choices") as HBoxContainer
	assert_eq(choices.get_child_count(), 12)
	for index: int in choices.get_child_count():
		var button: Button = choices.get_child(index) as Button
		assert_not_null(button)
		assert_eq(button.text, OwnerText.look_label(index))
		assert_false(button.text.contains("character-"), "model IDs never become player-facing labels")
	var preview: OwnerCharacterPreview = _picker.get_node("%Preview") as OwnerCharacterPreview
	assert_eq(preview.models(), OwnerAppearance.MODELS)
	assert_eq(_picker.selected_model, OwnerAppearance.DEFAULT_MODEL)
	assert_eq((_picker.get_node("%OwnerName") as LineEdit).placeholder_text, "You")
	assert_eq((_picker.get_node("%OwnerName") as LineEdit).max_length, OwnerAppearance.MAX_NAME_LENGTH)


func test_native_look_button_changes_only_the_pending_choice_and_keeps_one_selection() -> void:
	assert_true(_profile.set_choice(&"character-female-c", "Jordan"))
	var before: Dictionary = _profile.to_dict()
	_picker.open(_profile)
	var choices: HBoxContainer = _picker.get_node("%Choices") as HBoxContainer
	var selected_index: int = OwnerAppearance.MODELS.find(&"character-male-e")
	(choices.get_child(selected_index) as Button).pressed.emit()
	assert_eq(_picker.selected_model, &"character-male-e")
	for index: int in choices.get_child_count():
		assert_eq((choices.get_child(index) as Button).button_pressed, index == selected_index)
	assert_eq(_profile.to_dict(), before, "previewing a look never commits the appearance")
	assert_true(_confirmations.is_empty())
	assert_false(_picker.choose(&"missing-model"))
	assert_eq(_picker.selected_model, &"character-male-e")


func test_confirm_requests_the_selected_model_and_a_trimmed_name_without_mutating_profile() -> void:
	var before: Dictionary = _profile.to_dict()
	_picker.open(_profile)
	assert_true(_picker.choose(&"character-female-e"))
	(_picker.get_node("%OwnerName") as LineEdit).text = "  Sam  "
	(_picker.get_node("%Confirm") as Button).pressed.emit()
	assert_eq(_confirmations, [{"model": &"character-female-e", "name": "Sam"}] as Array[Dictionary])
	assert_eq(_profile.to_dict(), before, "Main must accept the request before saved choices change")
	assert_eq(_random_requests, 0)
	assert_eq(_cancel_requests, 0)


func test_submitting_an_optional_blank_name_requests_the_legacy_you_name() -> void:
	_picker.open(_profile)
	var input: LineEdit = _picker.get_node("%OwnerName") as LineEdit
	input.text = "    "
	input.text_submitted.emit(input.text)
	assert_eq(_confirmations, [{"model": OwnerAppearance.DEFAULT_MODEL, "name": "You"}] as Array[Dictionary])
	assert_eq(_profile.display_name, "You")


func test_random_is_a_request_only_and_does_not_create_or_draw_a_game_random_stream() -> void:
	var streams: Dictionary = GameState._capture_save().duplicate(true)
	var before: Dictionary = _profile.to_dict()
	_picker.open(_profile)
	assert_true(_picker.choose(&"character-male-c"))
	(_picker.get_node("%Random") as Button).pressed.emit()
	assert_eq(_random_requests, 1)
	assert_eq(_picker.selected_model, &"character-male-c", "the session supplies an explicitly randomized model")
	assert_eq(_profile.to_dict(), before)
	assert_eq(GameState._capture_save(), streams, "opening and using request-only controls must not consume RNG")
	assert_true(_confirmations.is_empty())


func test_new_run_hides_and_guards_cancel_but_later_edit_can_cancel_without_committing() -> void:
	var before: Dictionary = _profile.to_dict()
	_picker.open(_profile, false)
	var cancel: Button = _picker.get_node("%Cancel") as Button
	assert_false(cancel.visible)
	cancel.pressed.emit()
	assert_true(_picker.visible, "a stale cancel request cannot leave creation unfinished")
	assert_eq(_cancel_requests, 0)
	_picker.open(_profile, true)
	assert_true(cancel.visible)
	assert_true(_picker.choose(&"character-male-b"))
	(_picker.get_node("%OwnerName") as LineEdit).text = "Pending name"
	cancel.pressed.emit()
	assert_false(_picker.visible)
	assert_eq(_cancel_requests, 1)
	assert_true(_confirmations.is_empty())
	assert_eq(_profile.to_dict(), before)


func test_reopening_resets_pending_edits_without_duplicating_buttons_or_requests() -> void:
	_picker.open(_profile)
	var choices: HBoxContainer = _picker.get_node("%Choices") as HBoxContainer
	var first: Button = choices.get_child(0) as Button
	assert_true(_picker.choose(&"character-female-f"))
	(_picker.get_node("%OwnerName") as LineEdit).text = "Not committed"
	_picker.hide()
	assert_true(_profile.set_choice(&"character-male-f", "Robin"))
	_picker.open(_profile)
	_picker.open(_profile)
	assert_eq(choices.get_child_count(), 12)
	assert_true(choices.get_child(0) == first, "the same native controls survive reopening")
	assert_eq(_picker.selected_model, &"character-male-f")
	assert_eq((_picker.get_node("%OwnerName") as LineEdit).text, "Robin")
	(_picker.get_node("%Confirm") as Button).pressed.emit()
	assert_eq(_confirmations, [{"model": &"character-male-f", "name": "Robin"}] as Array[Dictionary])


func _record_confirmation(model: StringName, display_name: String) -> void:
	_confirmations.append({"model": model, "name": display_name})


func _record_random_request() -> void:
	_random_requests += 1


func _record_cancel_request() -> void:
	_cancel_requests += 1
