class_name MenuPresetControls
extends VBoxContainer
## The menu owns visibility; the session accepts these requests.

signal save_requested(preset_name: String)
signal load_requested(index: int)
signal rename_requested(index: int, preset_name: String)
signal delete_requested(index: int)

var _names: Array[String] = []
var _rename_index: int = -1
var _editable: bool = false
var _picker: OptionButton
var _load_button: Button
var _rename_button: Button
var _delete_button: Button
var _name_edit: LineEdit
var _submit: Button
var _cancel: Button
var _feedback: Label


func set_names(names: Array[String], preferred_selection: int = -1) -> void:
	_bind_controls()
	var selection: int = preferred_selection if preferred_selection >= 0 else _picker.selected
	_names.assign(names)
	_picker.clear()
	if _names.is_empty():
		_picker.add_item("No saved presets")
	else:
		for preset_name: String in _names:
			_picker.add_item(preset_name)
		_picker.select(clampi(selection, 0, _names.size() - 1))
	_clear_editor()


func set_editable(editable: bool) -> void:
	_bind_controls()
	_editable = editable
	_refresh_actions()


func set_open(open: bool) -> void:
	_bind_controls()
	visible = open
	if not open:
		_clear_editor()
		set_feedback("")


func set_feedback(text: String) -> void:
	_bind_controls()
	_feedback.text = text
	_feedback.visible = not text.is_empty()


func _bind_controls() -> void:
	if _picker != null:
		return
	_picker = %PresetList
	_load_button = %LoadPreset
	_rename_button = %RenamePreset
	_delete_button = %DeletePreset
	_name_edit = %PresetName
	_submit = %SavePreset
	_cancel = %CancelRename
	_feedback = %PresetFeedback
	_picker.item_selected.connect(_on_preset_selected)
	_load_button.pressed.connect(_on_load_pressed)
	_rename_button.pressed.connect(_on_rename_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_submit.pressed.connect(_on_submit_pressed)
	_cancel.pressed.connect(_clear_editor)
	_picker.add_item("No saved presets")


func _refresh_actions() -> void:
	var selected: bool = _editable and not _names.is_empty() and _picker.selected >= 0
	var renaming: bool = _rename_index >= 0
	var can_add: bool = _names.size() < MenuPresetLibrary.MAX_PRESETS
	_picker.disabled = not selected or renaming
	_load_button.disabled = not selected or renaming
	_rename_button.disabled = not selected or renaming
	_delete_button.disabled = not selected or renaming
	_name_edit.editable = _editable and (renaming or can_add)
	_cancel.visible = renaming
	_submit.text = "Save name" if renaming else "Save as preset…"
	var preset_name: String = MenuSettings.normalized_restaurant_name(_name_edit.text)
	var duplicate: bool = _name_in_use(preset_name)
	_submit.disabled = not _name_edit.editable or preset_name.is_empty() or duplicate
	_submit.tooltip_text = ""
	if not can_add and not renaming:
		_submit.tooltip_text = "Delete a preset to make room for a new one."
	elif duplicate:
		_submit.tooltip_text = "A preset already uses this name."


func _name_in_use(preset_name: String) -> bool:
	var folded_name: String = preset_name.to_lower()
	for index: int in _names.size():
		if index != _rename_index and _names[index].to_lower() == folded_name:
			return true
	return false


func _clear_editor() -> void:
	_rename_index = -1
	_name_edit.clear()
	_refresh_actions()


func _on_preset_selected(_index: int) -> void:
	set_feedback("")
	_refresh_actions()


func _on_load_pressed() -> void:
	if not _load_button.disabled:
		load_requested.emit(_picker.selected)


func _on_rename_pressed() -> void:
	if _rename_button.disabled:
		return
	_rename_index = _picker.selected
	set_feedback("")
	_name_edit.text = _names[_rename_index]
	_refresh_actions()
	if _name_edit.is_inside_tree():
		_name_edit.grab_focus()
	_name_edit.select_all()


func _on_delete_pressed() -> void:
	if not _delete_button.disabled:
		delete_requested.emit(_picker.selected)


func _on_name_changed(_text: String) -> void:
	_refresh_actions()


func _on_name_submitted(_text: String) -> void:
	_on_submit_pressed()


func _on_submit_pressed() -> void:
	if _submit.disabled:
		return
	var preset_name: String = MenuSettings.normalized_restaurant_name(_name_edit.text)
	if _rename_index >= 0:
		rename_requested.emit(_rename_index, preset_name)
	else:
		save_requested.emit(preset_name)
