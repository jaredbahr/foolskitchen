class_name OwnerPicker
extends Control
## Request-only appearance editor. Main owns accepted choices and morning saves.

signal confirmed(model: StringName, display_name: String)
signal random_requested()
signal cancelled()

var selected_model: StringName = OwnerAppearance.DEFAULT_MODEL
var _buttons: Dictionary[StringName, Button] = {}
var _bound: bool = false
var _allow_cancel: bool = true


func _ready() -> void:
	_bind_controls()


func open(appearance: OwnerAppearance, allow_cancel: bool = true) -> void:
	_bind_controls()
	selected_model = appearance.model
	_allow_cancel = allow_cancel
	(%OwnerName as LineEdit).text = appearance.display_name
	(%Cancel as Button).visible = allow_cancel
	(%Error as Label).text = ""
	_update_selection()
	show()


func choose(model: StringName) -> bool:
	if not OwnerAppearance.valid_model(model):
		return false
	selected_model = model
	_bind_controls()
	_update_selection()
	return true


func _bind_controls() -> void:
	if _bound:
		return
	_bound = true
	(%Title as Label).text = OwnerText.TITLE
	(%NameLabel as Label).text = OwnerText.NAME_LABEL
	(%OwnerName as LineEdit).placeholder_text = OwnerAppearance.DEFAULT_NAME
	(%OwnerName as LineEdit).max_length = OwnerAppearance.MAX_NAME_LENGTH
	(%Confirm as Button).text = OwnerText.CONFIRM
	(%Random as Button).text = OwnerText.RANDOM
	(%Cancel as Button).text = OwnerText.CANCEL
	(%Confirm as Button).pressed.connect(_on_confirm)
	(%Random as Button).pressed.connect(_on_random)
	(%Cancel as Button).pressed.connect(_on_cancel)
	(%OwnerName as LineEdit).text_submitted.connect(_on_name_submitted)
	var choices: HBoxContainer = %Choices as HBoxContainer
	for index: int in OwnerAppearance.MODELS.size():
		var model: StringName = OwnerAppearance.MODELS[index]
		var button: Button = Button.new()
		button.text = OwnerText.look_label(index)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(82.0, 44.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_choose.bind(model))
		choices.add_child(button)
		_buttons[model] = button
	(%Preview as OwnerCharacterPreview).set_models(OwnerAppearance.MODELS)


func _update_selection() -> void:
	for model: StringName in _buttons:
		_buttons[model].set_pressed_no_signal(model == selected_model)


func _on_choose(model: StringName) -> void:
	choose(model)


func _on_confirm() -> void:
	var choice: OwnerAppearance = OwnerAppearance.new()
	if not choice.set_choice(selected_model, (%OwnerName as LineEdit).text):
		(%Error as Label).text = OwnerText.NAME_ERROR
		return
	confirmed.emit(choice.model, choice.display_name)


func _on_name_submitted(_text: String) -> void:
	_on_confirm()


func _on_random() -> void:
	random_requested.emit()


func _on_cancel() -> void:
	if not _allow_cancel:
		return
	hide()
	cancelled.emit()
