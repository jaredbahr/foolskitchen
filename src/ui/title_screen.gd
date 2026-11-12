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
var _new_creative: bool = false

@onready var menu: PanelContainer = $Menu
@onready var continue_button: Button = $Menu/Column/Continue
@onready var new_button: Button = $Menu/Column/NewGame
@onready var settings_button: Button = $Menu/Column/Settings
@onready var quit_button: Button = $Menu/Column/Quit
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
	quit_button.pressed.connect(_on_quit_pressed)
	confirmation.confirmed.connect(_start_new_game)
	settings.close_requested.connect(_on_settings_closed)
	settings.bind_preferences(Preferences)
	_build_mode_choice()
	refresh_save_availability()
	_prepare_backdrop()
	_layout_menu()
	resized.connect(_layout_menu)


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
	mode_choice.show()
	_layout_menu()


func _hide_mode_choice() -> void:
	mode_choice.hide()
	menu.show()


func request_new_game(creative: bool = false) -> void:
	_new_creative = creative
	_hide_mode_choice()
	refresh_save_availability()
	if continue_button.visible:
		confirmation.popup_centered(Vector2i(480, 160))
	else:
		_start_new_game()


func _start_new_game() -> void:
	if MAIN.start_fresh_run(get_tree(), MAIN.AUTOSAVE_SLOT, true, _new_creative) != OK:
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
		button.pressed.connect(request_new_game.bind(creative))
		column.add_child(button)
		var line: Label = Label.new()
		line.text = TitleText.CREATIVE_LINE if creative else TitleText.CAREER_LINE
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(line)
	var back: Button = Button.new()
	back.name = "Back"
	back.text = TitleText.BACK
	back.pressed.connect(_hide_mode_choice)
	column.add_child(back)


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
		if code == KEY_ESCAPE and settings.visible:
			_on_settings_closed()
		elif code == KEY_ESCAPE and mode_choice.visible:
			_hide_mode_choice()
	get_viewport().set_input_as_handled()

