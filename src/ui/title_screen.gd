class_name TitleScreen
extends Control
## The live backdrop never starts a session: it does not load, save or consume
## the run's random streams. Main remains independently bootable for tools.

const MAIN: Script = preload("res://src/world/main.gd")
const MAIN_SCENE: String = "res://src/world/main.tscn"
const ORBIT_DEGREES_PER_SECOND: float = 2.0
const CARD_WIDTH: float = 480.0
const CARD_MARGIN: float = 24.0

var _backdrop: Node3D
var _camera: CameraRig
var _clock_processed: bool = true
var _clock_input: bool = true
var _started: bool = false
## The new game's Career or Creative card (FK-141), built in code.
var mode_choice: PanelContainer
var difficulty_choice: PanelContainer
var _career_button: Button
var _difficulty_buttons: Dictionary[StringName, Button] = {}
var _difficulty_scroll: ScrollContainer
var _difficulty_content: VBoxContainer
var _custom_toggles: VBoxContainer
var _auto_buy: CheckButton
var _auto_buy_premium: CheckButton
var _selected_difficulty: StringName = &"normal"
var _new_creative: bool = false
var _new_difficulty: StringName = &"normal"
var _new_custom_flags: Dictionary = {}
## Test seam: the build's version and notes, normally read from BuildInfo.
var build_version: String = ""
var build_notes: String = ""

@onready var menu: PanelContainer = $Menu
@onready var continue_button: Button = $Menu/Column/Continue
@onready var new_button: Button = $Menu/Column/NewGame
@onready var settings_button: Button = $Menu/Column/Settings
@onready var whats_new_button: Button = $Menu/Column/WhatsNew
@onready var quit_button: Button = $Menu/Column/Quit
@onready var whats_new: WhatsNewPanel = $WhatsNewPanel
@onready var version_label: Label = $VersionLabel
@onready var confirmation: ConfirmationDialog = $StartOver
@onready var settings: SettingsPanel = $SettingsPanel
@onready var status: Label = $Menu/Column/Status


func _ready() -> void:
	start()


## Idempotent for both normal startup and the headless test runner.
func start() -> void:
	if _started:
		return
	_started = true
	_clock_processed = Clock.is_processing()
	_clock_input = Clock.is_processing_unhandled_input()
	Sounds.set_music_context(MusicTracks.TITLE)
	Clock.set_speed(0)
	Clock.set_process(false)
	Clock.set_process_unhandled_input(false)
	$Menu/Column/Title.text = TitleText.GAME_NAME
	continue_button.text = TitleText.CONTINUE
	new_button.text = TitleText.NEW_GAME
	settings_button.text = TitleText.SETTINGS
	whats_new_button.text = TitleText.WHATS_NEW
	quit_button.text = TitleText.QUIT
	quit_button.visible = not OS.has_feature("web")
	# Keep native dialog padding, but use the shared palette in this dialog only.
	var dialog_theme: Theme = theme.duplicate() as Theme
	var dialog_panel: StyleBoxFlat = confirmation.get_theme_stylebox("panel", "AcceptDialog").duplicate() as StyleBoxFlat
	dialog_panel.bg_color = (theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color
	dialog_theme.set_stylebox("panel", "AcceptDialog", dialog_panel)
	dialog_theme.set_color("font_focus_color", "Button", theme.get_color("font_color", "Button"))
	confirmation.theme = dialog_theme
	confirmation.dialog_text = TitleText.START_OVER
	confirmation.title = TitleText.NEW_GAME
	confirmation.ok_button_text = TitleText.NEW_GAME
	confirmation.cancel_button_text = TitleText.CANCEL
	continue_button.pressed.connect(continue_game)
	new_button.pressed.connect(show_mode_choice)
	settings_button.pressed.connect(_on_settings_pressed)
	whats_new_button.pressed.connect(show_whats_new)
	whats_new.close_requested.connect(_on_whats_new_closed)
	quit_button.pressed.connect(_on_quit_pressed)
	confirmation.confirmed.connect(_start_new_game)
	confirmation.canceled.connect(new_button.grab_focus)
	settings.close_requested.connect(_on_settings_closed)
	settings.bind_preferences(Preferences)
	_build_mode_choice()
	_build_difficulty_choice()
	refresh_save_availability()
	_prepare_backdrop()
	_layout_menu()
	resized.connect(_layout_menu)
	if build_version.is_empty():
		build_version = BuildInfo.version()
		build_notes = BuildInfo.notes()
	version_label.text = BuildInfo.label(build_version)
	_open_whats_new_once()


## The panel opens by itself on the first launch of each new release; the
## version is recorded as seen as soon as it shows (user settings, not the save).
func _open_whats_new_once() -> void:
	if BuildInfo.should_show_whats_new(build_version, Preferences.last_seen_version, build_notes):
		Preferences.set_last_seen_version(build_version)
		show_whats_new()


func show_whats_new() -> void:
	menu.hide()
	whats_new.present(build_version, build_notes)


func _on_whats_new_closed() -> void:
	menu.show()
	_layout_menu()
	whats_new_button.grab_focus()


func _exit_tree() -> void:
	if _started:
		Sounds.set_music_context(&"")
		Clock.set_process(_clock_processed)
		Clock.set_process_unhandled_input(_clock_input)


func refresh_save_availability() -> void:
	continue_button.visible = SaveSystem.list_slots().has(MAIN.AUTOSAVE_SLOT)
	continue_button.text = TitleText.CONTINUE + (TitleText.CREATIVE_SUFFIX
		if continue_button.visible and _autosave_is_creative() else "")


## Reads only the autosave's mode, for the Continue label; Main still owns
## loading, validation and backup recovery.
func _autosave_is_creative() -> bool:
	var file: FileAccess = FileAccess.open(
		SaveSystem.save_dir.path_join(MAIN.AUTOSAVE_SLOT + ".json"), FileAccess.READ)
	if file == null:
		return false
	var parser: JSON = JSON.new()
	var parsed: Error = parser.parse(file.get_as_text())
	file.close()
	var document: Variant = parser.data
	return parsed == OK and document is Dictionary and (document as Dictionary).get("data", null) is Dictionary \
		and GameMode.is_creative_save((document as Dictionary)["data"])


## New game first asks Career or Creative.
func show_mode_choice() -> void:
	menu.hide()
	difficulty_choice.hide()
	mode_choice.show()
	_layout_menu()
	_career_button.grab_focus()


func _return_to_menu() -> void:
	difficulty_choice.hide()
	mode_choice.hide()
	menu.show()
	new_button.grab_focus()


func _show_difficulty_choice() -> void:
	_auto_buy.set_pressed_no_signal(Difficulty.DEFAULT_CUSTOM_FLAGS[&"buy"])
	_auto_buy_premium.set_pressed_no_signal(Difficulty.DEFAULT_CUSTOM_FLAGS[&"buy_premium"])
	_difficulty_buttons[&"normal"].button_pressed = true
	_on_difficulty_toggled(true, &"normal")
	mode_choice.hide()
	difficulty_choice.show()
	_layout_menu()
	_difficulty_buttons[&"normal"].grab_focus()


func _on_difficulty_toggled(pressed: bool, mode_id: StringName) -> void:
	if pressed:
		_selected_difficulty = mode_id
		_custom_toggles.visible = mode_id == &"custom"


func _start_career() -> void:
	var flags: Dictionary = {}
	if _selected_difficulty == &"custom":
		flags = Difficulty.DEFAULT_CUSTOM_FLAGS.duplicate()
		flags[&"buy"] = _auto_buy.button_pressed
		flags[&"buy_premium"] = _auto_buy_premium.button_pressed
	request_new_game(false, _selected_difficulty, flags)


func request_new_game(creative: bool = false, difficulty_id: StringName = &"normal",
		custom_flags: Dictionary = {}) -> void:
	_new_creative = creative
	_new_difficulty = &"normal" if creative else difficulty_id
	_new_custom_flags = {} if creative else custom_flags.duplicate()
	_return_to_menu()
	refresh_save_availability()
	if continue_button.visible:
		confirmation.popup_centered(Vector2i(480, 160))
	else:
		_start_new_game()


func _start_new_game() -> void:
	if MAIN.start_fresh_run(get_tree(), MAIN.AUTOSAVE_SLOT, true,
			_new_creative, _new_difficulty, _new_custom_flags) != OK:
		_show_start_error()


func _build_mode_choice() -> void:
	mode_choice = PanelContainer.new()
	mode_choice.name = "ModeChoice"
	mode_choice.hide()
	add_child(mode_choice)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	mode_choice.add_child(column)
	var heading: Label = Label.new()
	heading.text = TitleText.CHOOSE_MODE
	heading.add_theme_font_size_override("font_size", 28)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	for creative: bool in [false, true]:
		var button: Button = Button.new()
		button.name = "Creative" if creative else "Career"
		button.text = TitleText.CREATIVE if creative else TitleText.CAREER
		if creative:
			button.pressed.connect(request_new_game.bind(true))
		else:
			_career_button = button
			button.pressed.connect(_show_difficulty_choice)
		column.add_child(button)
		var line: Label = Label.new()
		line.text = TitleText.CREATIVE_LINE if creative else TitleText.CAREER_LINE
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(line)
	var back: Button = Button.new()
	back.name = "Back"
	back.text = TitleText.BACK
	back.pressed.connect(_return_to_menu)
	column.add_child(back)


func _build_difficulty_choice() -> void:
	difficulty_choice = PanelContainer.new()
	difficulty_choice.name = "DifficultyChoice"
	difficulty_choice.hide()
	add_child(difficulty_choice)
	_difficulty_scroll = ScrollContainer.new()
	_difficulty_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_difficulty_scroll.follow_focus = true
	difficulty_choice.add_child(_difficulty_scroll)
	_difficulty_content = VBoxContainer.new()
	_difficulty_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_difficulty_content.add_theme_constant_override("separation", 12)
	_difficulty_scroll.add_child(_difficulty_content)
	var heading: Label = Label.new()
	heading.text = DifficultyText.CHOOSE_CAREER
	heading.add_theme_font_size_override("font_size", 28)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_difficulty_content.add_child(heading)

	var options: GridContainer = GridContainer.new()
	options.columns = 2
	options.add_theme_constant_override("h_separation", 14)
	options.add_theme_constant_override("v_separation", 8)
	_difficulty_content.add_child(options)
	var group: ButtonGroup = ButtonGroup.new()
	var ink: Color = get_theme_color("font_color", "Button")
	for mode_id: StringName in Difficulty.MODES:
		var button: Button = Button.new()
		button.name = Difficulty.mode_name(mode_id)
		button.text = Difficulty.mode_name(mode_id)
		button.custom_minimum_size.x = 106.0
		button.toggle_mode = true
		button.button_group = group
		button.add_theme_color_override("font_pressed_color", ink)
		button.add_theme_color_override("font_hover_pressed_color", ink)
		button.add_theme_color_override("font_focus_color", ink)
		button.toggled.connect(_on_difficulty_toggled.bind(mode_id))
		_difficulty_buttons[mode_id] = button
		options.add_child(button)
		var line: Label = Label.new()
		line.text = DifficultyText.description(mode_id)
		line.add_theme_font_size_override("font_size", 16)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		options.add_child(line)

	_custom_toggles = VBoxContainer.new()
	_custom_toggles.name = "CustomToggles"
	_custom_toggles.add_theme_constant_override("separation", 6)
	_custom_toggles.hide()
	_difficulty_content.add_child(_custom_toggles)
	_auto_buy = _add_difficulty_switch("AutoBuy", DifficultyText.AUTO_BUY)
	_auto_buy_premium = _add_difficulty_switch("AutoBuyPremium", DifficultyText.AUTO_BUY_PREMIUM)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	_difficulty_content.add_child(actions)
	var back: Button = Button.new()
	back.name = "Back"
	back.text = TitleText.BACK
	back.pressed.connect(show_mode_choice)
	actions.add_child(back)
	var begin: Button = Button.new()
	begin.name = "StartCareer"
	begin.text = DifficultyText.START_CAREER
	begin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	begin.pressed.connect(_start_career)
	actions.add_child(begin)
	_difficulty_content.minimum_size_changed.connect(_layout_difficulty_choice)


func _add_difficulty_switch(node_name: String, caption: String) -> CheckButton:
	var button: CheckButton = CheckButton.new()
	button.name = node_name
	button.text = caption
	_custom_toggles.add_child(button)
	return button


func continue_game() -> void:
	refresh_save_availability()
	if not continue_button.visible:
		return
	# Main owns validation, backup recovery and morning restoration.
	if get_tree().change_scene_to_file(MAIN_SCENE) != OK:
		_show_start_error()


func _show_start_error() -> void:
	status.text = TitleText.CANNOT_START
	status.show()


func _prepare_backdrop() -> void:
	_backdrop = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	_backdrop.set("display_only", true)
	_backdrop.set("use_saves", false)
	add_child(_backdrop)
	move_child(_backdrop, 0)
	_backdrop.call("initialize")
	_camera = _backdrop.get_node("CameraRig") as CameraRig


func _process(delta: float) -> void:
	if _camera == null:
		return
	_camera.rotation.y += deg_to_rad(ORBIT_DEGREES_PER_SECOND) * delta
	var quarter: int = posmod(roundi((rad_to_deg(_camera.rotation.y) - 45.0) / 90.0), 4)
	(_backdrop.get_node("ShopView") as ShopView).set_camera_quarter(quarter)


func _layout_menu() -> void:
	if not _started:
		return
	menu.custom_minimum_size.x = minf(CARD_WIDTH, maxf(0.0, size.x - CARD_MARGIN * 2.0))
	menu.size = menu.get_combined_minimum_size()
	menu.position = Vector2(CARD_MARGIN, maxf(CARD_MARGIN, (size.y - menu.size.y) * 0.5))
	mode_choice.custom_minimum_size.x = menu.custom_minimum_size.x
	mode_choice.size = mode_choice.get_combined_minimum_size()
	mode_choice.position = Vector2(CARD_MARGIN, maxf(CARD_MARGIN, (size.y - mode_choice.size.y) * 0.5))
	_layout_difficulty_choice()


func _layout_difficulty_choice() -> void:
	var padding: Vector2 = difficulty_choice.get_theme_stylebox("panel").get_minimum_size()
	_difficulty_scroll.custom_minimum_size.y = minf(_difficulty_content.get_combined_minimum_size().y,
		maxf(0.0, size.y - CARD_MARGIN * 2.0 - padding.y))
	difficulty_choice.custom_minimum_size.x = menu.custom_minimum_size.x
	difficulty_choice.size = difficulty_choice.get_combined_minimum_size()
	difficulty_choice.position = Vector2(CARD_MARGIN, maxf(CARD_MARGIN, (size.y - difficulty_choice.size.y) * 0.5))


func _on_settings_pressed() -> void:
	menu.hide()
	settings.refresh()
	settings.show()


func _on_settings_closed() -> void:
	if settings.flush_pending_changes():
		settings.hide()
		menu.show()


func _on_quit_pressed() -> void:
	if not OS.has_feature("web") and settings.flush_pending_changes():
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_ESCAPE and whats_new.visible:
			whats_new.close()
		elif code == KEY_ESCAPE and settings.visible:
			_on_settings_closed()
		elif code == KEY_ESCAPE and difficulty_choice.visible:
			show_mode_choice()
		elif code == KEY_ESCAPE and mode_choice.visible:
			_return_to_menu()
	get_viewport().set_input_as_handled()

