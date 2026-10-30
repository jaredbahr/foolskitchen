extends "res://src/world/main.gd"
## Historical fixed-stock context for storage/cart/save compatibility tests.
## Select genuine manual targets before the first real plan for each installed
## settings model. Subsequent player edits, disabled rows and loaded targets
## stay untouched; all purchases and morning saves use inherited production code.

var _fixed_settings_model: ReorderSettings = null
## Only the pre-FK-121 golden selects its recorded $40 rent. An instance
## field avoids compile-time folding of the shipped Resource constant.
var historical_rent: int = -1


func _reorder(tomorrow: bool = false) -> ReorderSettings:
	if reorder_settings != null and reorder_settings != _fixed_settings_model:
		for id: StringName in reorder_settings.all_ids():
			reorder_settings.set_target(id, reorder_settings.target(id))
		_fixed_settings_model = reorder_settings
	return super._reorder(tomorrow)


func _charge_closing_costs() -> void:
	if historical_rent < 0:
		super._charge_closing_costs()
		return
	# Original closing policy and real ledger charges, with an explicit
	# historical rent input. No balancing grant, refund or extra adjustment.
	for agent: SimAgent in world.agents:
		if agent is StaffAgent and not agent is OwnerAgent:
			Economy.add_cash(-OpeningHours.wage_for_day((agent as StaffAgent).wage,
				Clock.sim, HOURS_TUNING), Ledger.WAGES)
	if historical_rent > 0:
		Economy.add_cash(-historical_rent, Ledger.RENT)
