extends TestCase
## FK-087 storage capacity: units per storage kind shared by every ingredient
## of that kind, items of one kind adding up, orders counted as used space,
## the auto-reorder clamped to free space, and Build refusing to sell storage
## the stock still needs (undo and redo included).

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const START_CASH: int = 1000

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _ledger: Ledger
var _stock: Stock
var _pending: Dictionary[StringName, int] = {}


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors)
	assert_eq(errors, [] as Array[String])
	_ledger = Ledger.new()
	_ledger.cash = START_CASH
	_stock = Stock.new()
	_pending = {}
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)
	_editor.storage_need = _need
	_history = ShopEditHistory.new(_editor, _sim.world.grid)


func after_each() -> void:
	_history = null
	_editor = null
	_sim = null
	_content = null


func _space() -> StorageSpace:
	return StorageSpace.new(StorageSpace.capacities(_sim.world.grid, _editor.pantry_units), _stock,
		_pending, StorageSpace.kinds_of(_content))


func _need() -> Dictionary:
	var space: StorageSpace = _space()
	var out: Dictionary = {}
	for kind: int in StorageSpace.KINDS:
		out[kind] = space.committed(kind)
	return out


func test_starter_storage_holds_the_starter_order_with_headroom() -> void:
	var space: StorageSpace = _space()
	assert_eq(space.capacity(StorageSpace.FRIDGE), 40, "the starter fridge")
	assert_eq(space.capacity(StorageSpace.DRY), 60, "the built-in back-room pantry")
	assert_eq(space.capacity(StorageSpace.FREEZER), 0)
	var fridge: int = 0
	var dry: int = 0
	for id: StringName in TUNING.morning_stock:
		var kind: int = int(_content.ingredient(id).storage)
		if kind == StorageSpace.FRIDGE:
			fridge += TUNING.morning_stock[id]
		elif kind == StorageSpace.DRY:
			dry += TUNING.morning_stock[id]
	assert_eq(fridge, 28, "patties, cheese and lettuce are kept cold")
	assert_eq(dry, 50, "bread, buns, soup stock and tomatoes on the shelves")
	assert_true(fridge < space.capacity(StorageSpace.FRIDGE) and dry < space.capacity(StorageSpace.DRY))
	for id: StringName in TUNING.station_stock:
		# Raw dough (FK-081 savoury pie) keeps cold; every other station supply is dry.
		var expected: int = StorageSpace.FRIDGE if id == &"dough" else StorageSpace.DRY
		assert_eq(int(_content.ingredient(id).storage), expected, "%s storage kind" % id)


func test_capacity_is_per_kind_and_items_of_a_kind_add_up() -> void:
	assert_true(_editor.buy(&"storage_shelf", Vector2i(12, 1), 2), _editor.last_check.why)
	assert_true(_editor.buy(&"storage_shelf", Vector2i(11, 1), 2), _editor.last_check.why)
	var space: StorageSpace = _space()
	assert_eq(space.capacity(StorageSpace.DRY), 60 + 40 + 40)
	assert_eq(space.capacity(StorageSpace.FRIDGE), 40, "shelves add no fridge space")
	_stock.add(&"cheese", 30, 1)
	_stock.add(&"lettuce", 6, 1)
	_stock.add(&"bread", 100, 1)
	_pending[&"beef_patty"] = 3
	space = _space()
	assert_eq(space.in_stock(StorageSpace.FRIDGE), 36, "every fridge ingredient shares the fridge's units")
	assert_eq(space.on_order(StorageSpace.FRIDGE), 3)
	assert_eq(space.free_units(StorageSpace.FRIDGE), 1, "orders already take their space")
	assert_eq(space.free_units(StorageSpace.DRY), 40)
	assert_eq(space.first_overflow({&"cheese": 1, &"bread": 20}), -1)
	assert_eq(space.first_overflow({&"cheese": 2}), StorageSpace.FRIDGE)
	assert_eq(space.first_overflow({&"lettuce": 1, &"cheese": 1}), StorageSpace.FRIDGE, "the cart counts together")
	assert_eq(space.first_overflow({&"tomato": 41}), StorageSpace.DRY)
	assert_eq(StorageSpace.refusal(StorageSpace.FRIDGE), "Not enough fridge space")
	assert_eq(StorageSpace.refusal(StorageSpace.FREEZER), "Not enough freezer space")
	assert_eq(StorageSpace.refusal(StorageSpace.DRY), "Not enough dry storage space")
	assert_almost_eq(space.fill(StorageSpace.FRIDGE), 0.9, 0.0001)


func test_an_over_full_kind_has_no_free_space_but_keeps_its_stock() -> void:
	_stock.add(&"cheese", 55, 1)
	var space: StorageSpace = _space()
	assert_true(space.is_over(StorageSpace.FRIDGE))
	assert_eq(space.free_units(StorageSpace.FRIDGE), 0)
	assert_eq(space.first_overflow({&"lettuce": 1}), StorageSpace.FRIDGE, "new buys of that kind are blocked")
	assert_eq(space.first_overflow({&"bread": 1}), -1, "other kinds are not")
	assert_eq(_stock.count(&"cheese"), 55, "nothing is thrown away")
	assert_almost_eq(space.fill(StorageSpace.FRIDGE), 1.0, 0.0001)


func test_auto_reorder_buys_up_to_the_free_space_in_the_fixed_order() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	var costs: Dictionary = _costs()
	_stock.add(&"cheese", 20, 1)
	# Fridge: 40 - 20 cheese = 20 free for 10 patties, 0 more cheese... in the fixed order.
	var plan: Dictionary = settings.plan(_stock, costs, 1000, 0.0, false, _space())
	var bought: Dictionary = _quantities(plan)
	assert_eq(bought.get(&"beef_patty", 0), 10)
	assert_eq(bought.get(&"lettuce", 0), 10, "patties then lettuce fill the fridge")
	assert_false(bought.has(&"cheese"), "the cheese is above its target already")
	assert_eq(plan["unfit"], {}, "20 + 10 + 10 fits 40 exactly")
	_stock.add(&"cheese", 5, 1)
	plan = settings.plan(_stock, costs, 1000, 0.0, false, _space())
	bought = _quantities(plan)
	assert_eq(bought.get(&"beef_patty", 0), 10)
	assert_eq(bought.get(&"lettuce", 0), 5, "the last fridge space goes to lettuce")
	assert_eq(plan["unfit"], {&"lettuce": 5})
	assert_eq(bought.get(&"bread", 0), 16, "dry goods are unaffected")


func test_orders_on_the_way_count_towards_the_target() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	_pending[&"bread"] = 10
	var plan: Dictionary = settings.plan(_stock, _costs(), 1000, 0.0, false, _space())
	assert_eq(_quantities(plan).get(&"bread", 0), 6, "16 target - 10 already ordered")


## #156 on defaults: with the starter storage the space never binds, so the
## standing order is exactly the old auto-order, premium included.
func test_the_standing_order_matches_the_old_auto_order_on_defaults() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	for cash: int in [1000, 300, 41, 11, 0]:
		var old: Dictionary = settings.plan(_stock, _costs(), cash, TUNING.auto_reorder_premium)
		var limited: Dictionary = settings.plan(_stock, _costs(), cash, TUNING.auto_reorder_premium, false, _space())
		assert_eq(limited["lines"], old["lines"], "same lines with $%d" % cash)
		assert_eq(limited["cost"], old["cost"])
		assert_eq(limited["short"], old["short"])
		assert_eq(limited["unfit"], {})
	_stock.add(&"beef_patty", 4, 1)
	_stock.add(&"tomato", 9, 1)
	var old_partial: Dictionary = settings.plan(_stock, _costs(), 300, TUNING.auto_reorder_premium)
	assert_eq(settings.plan(_stock, _costs(), 300, TUNING.auto_reorder_premium, false, _space())["lines"], old_partial["lines"])


func test_selling_storage_the_stock_needs_is_refused() -> void:
	var fridge: PlacedItem = _item(&"fridge")
	assert_true(_editor.buy(&"fridge", Vector2i(11, 1), 2) or _editor.buy(&"fridge", Vector2i(2, 2), 0), _editor.last_check.why)
	_stock.add(&"cheese", 45, 1)
	var check: EditCheck = _editor.check_sell(fridge.id)
	assert_false(check.ok)
	assert_eq(check.why, "Move stock out first: the fridge stock would not fit without it")
	_stock.take(&"cheese", 5)
	assert_true(_editor.check_sell(fridge.id).ok, "40 units fit the other fridge")
	_pending[&"lettuce"] = 1
	assert_false(_editor.check_sell(fridge.id).ok, "an order on the way needs its space too")


func test_undo_and_redo_refuse_to_overflow_storage_like_any_refused_edit() -> void:
	assert_true(_history.buy(&"storage_shelf", Vector2i(12, 1), 2), _editor.last_check.why)
	_stock.add(&"bread", 80, 1)
	var cash: int = _ledger.cash
	assert_false(_history.undo(), "undoing the shelf would leave 80 dry units in 60")
	assert_eq(_history.last_refusal, "Move stock out first: the dry stock would not fit without it")
	assert_eq(_history.undo_count(), 1, "the refused undo stays on the stack")
	assert_eq(_ledger.cash, cash)
	assert_not_null(_sim.world.grid.item_at(Vector2i(12, 1)))
	_stock.take(&"bread", 25)
	assert_true(_history.undo(), _history.last_refusal)
	assert_null(_sim.world.grid.item_at(Vector2i(12, 1)))
	# Redo of a sale: sell a shelf, refill, undo the sale, then its redo is refused.
	assert_true(_history.redo(), _history.last_refusal)
	var shelf: PlacedItem = _sim.world.grid.item_at(Vector2i(12, 1))
	assert_true(_history.sell(shelf.id) >= 0, _editor.last_check.why)
	assert_true(_history.undo(), _history.last_refusal)
	_stock.add(&"bread", 30, 1)
	assert_false(_history.redo(), "selling it again would overflow")
	assert_true(_history.last_refusal.begins_with("Move stock out first"))


func _item(id: StringName) -> PlacedItem:
	for placed: PlacedItem in _sim.world.grid.items():
		if (placed.def as ItemDef).id == id:
			return placed
	return null


func _costs() -> Dictionary:
	var costs: Dictionary = {}
	for ingredient: IngredientDef in _content.ingredients():
		costs[ingredient.id] = ingredient.unit_cost
	return costs


func _quantities(plan: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for line: Dictionary in plan["lines"]:
		out[line["id"]] = int(line["qty"])
	return out


func _can_spend(amount: int) -> bool:
	return _ledger.cash >= amount


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)
