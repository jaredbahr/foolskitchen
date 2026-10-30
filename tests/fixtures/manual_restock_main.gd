extends "res://src/world/main.gd"
## Historical fixed-stock context for storage/cart/save compatibility tests.
## Select genuine manual targets before the first real plan for each installed
## settings model. Subsequent player edits, disabled rows and loaded targets
## stay untouched; all purchases and morning saves use inherited production code.

var _fixed_settings_model: ReorderSettings = null


func _reorder(tomorrow: bool = false) -> ReorderSettings:
	if reorder_settings != null and reorder_settings != _fixed_settings_model:
		for id: StringName in reorder_settings.all_ids():
			reorder_settings.set_target(id, reorder_settings.target(id))
		_fixed_settings_model = reorder_settings
	return super._reorder(tomorrow)
