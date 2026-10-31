extends TestCase
## Existing books and live closing UI, with no new save provider or save action.

var _main: Node


func after_each() -> void:
	if _main != null:
		_main.free()
	_main = null
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_breakage_uses_existing_ledger_and_plain_live_report_without_saved_fields() -> void:
	var scene: PackedScene = load("res://src/world/main.tscn") as PackedScene
	_main = scene.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 127)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var before: int = Economy.cash
	sim.plate_broken.emit(sim.mishaps.tuning.replacement_plate_cost)
	sim.mishaps.record_spill(true)
	assert_eq(Economy.cash, before - sim.mishaps.tuning.replacement_plate_cost)
	assert_eq(Economy.ledger.day_totals(Clock.sim.day)[Ledger.BREAKAGES], -2)
	var report: DayReport = _main.call("build_report", Clock.sim.day)
	assert_eq(report.costs[Ledger.BREAKAGES], 2)
	assert_true(report.mishaps_text.contains("1 spill, 1 broken plate"))
	assert_false(report.to_dict().has("mishaps_text"))
	var view: Control = _main.get_node("Overlay/EveningReport")
	view.call("show_report", report)
	var label: Label = view.get_node("Panel/Scroll/Content/Mishaps") as Label
	assert_eq(label.text, report.mishaps_text)
	assert_true(label.visible)
	var rows: GridContainer = view.get_node("Panel/Scroll/Content/Finances/Costs/CostRows") as GridContainer
	var found: bool = false
	for child: Node in rows.get_children():
		if child is Label and (child as Label).text == "Breakages":
			found = true
	assert_true(found)
