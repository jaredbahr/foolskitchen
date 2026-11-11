extends TestCase
## Every save section is either the owner's (shared by every site) or one
## site's (FK-087). A new section must pick a side in SiteSections.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
var _main: Node
var _providers: Dictionary


func before_each() -> void:
	_providers = SaveSystem._providers.duplicate(true)
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
		_main = null
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func _captures() -> Dictionary:
	var sections: Dictionary = {}
	for key: String in SaveSystem.keys():
		sections[key] = SaveSystem._providers[key]["capture"].call()
	return sections


func test_every_registered_section_is_global_or_per_site_and_never_both() -> void:
	_start()
	var keys: PackedStringArray = SaveSystem.keys()
	assert_true(keys.has("pantry") and keys.has("economy"), "the session registers both money sections")
	for key: String in keys:
		assert_true(SiteSections.is_global(key) != SiteSections.is_per_site(key),
			"save section '%s' must be in exactly one SiteSections list" % key)
	for key: String in SiteSections.GLOBAL + SiteSections.PER_SITE:
		assert_true(keys.has(key), "SiteSections lists '%s', but nothing registers it" % key)


func test_books_and_pantry_restore_independently() -> void:
	Economy.reset(500)
	Economy.stock.add(&"bun", 4, 1)
	var books: Dictionary = Economy._capture_books()
	var pantry: Dictionary = Economy._capture_pantry()
	Economy.reset(9)
	var empty_stock: Stock = Economy.stock
	assert_true(Economy._restore_books(books))
	assert_eq(Economy.cash, 500, "the books bring back cash")
	assert_true(Economy.stock == empty_stock, "restoring the books leaves the pantry alone")
	var ledger: Ledger = Economy.ledger
	var loan: LoanAccount = Economy.loan
	assert_true(Economy._restore_pantry(pantry))
	assert_eq(Economy.stock.count(&"bun"), 4, "the pantry brings back the stock")
	assert_true(Economy.ledger == ledger and Economy.loan == loan, "restoring the pantry leaves the books alone")
	var stock: Stock = Economy.stock
	assert_false(Economy._restore_pantry({"stock": 5}))
	assert_false(Economy._restore_books({"ledger": 5}))
	assert_true(Economy.stock == stock and Economy.ledger == ledger, "a refused section changes nothing")


func test_a_live_session_restores_its_own_site_sections_and_survives_a_refusal() -> void:
	_start()
	var sim: RestaurantSim = _main.get("sim")
	assert_true(sim.stock == Economy.stock)
	var sections: Dictionary = _captures()
	assert_eq(SaveSystem.restore_sections(sections, SiteSections.PER_SITE), OK,
		"every per-site provider accepts its own capture")
	var stock_before: Dictionary = Economy.stock.to_dict()
	var bad: Dictionary = sections.duplicate(true)
	bad["pantry"] = {"stock": {"batches": {}}}
	bad["shop"] = {"tray_level": 99}
	assert_eq(SaveSystem.restore_sections(bad, SiteSections.PER_SITE), FAILED)
	assert_true(sim.stock == Economy.stock, "the kitchen still shares the pantry after a rollback")
	assert_eq(Economy.stock.to_dict(), stock_before, "the pantry is put back")
