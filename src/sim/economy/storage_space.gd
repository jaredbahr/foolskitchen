class_name StorageSpace
extends RefCounted
## Ingredient storage space per kind (FK-087): fridge, freezer and dry units.
## Every ingredient of one kind shares that kind's units. Capacity is the
## shop's built-in pantry (dry) plus every placed item's storage_units; items
## of one kind add up. Used space is the stock on hand plus what is already
## on order, so a delivery always fits when it arrives. A snapshot: build a
## new one after stock, orders or furniture change. No nodes.

const FRIDGE: int = IngredientDef.Storage.FRIDGE
const FREEZER: int = IngredientDef.Storage.FREEZER
const DRY: int = IngredientDef.Storage.SHELF
## Display order of the Stock panel's groups.
const KINDS: Array[int] = [FRIDGE, FREEZER, DRY]
const LABELS: Dictionary[int, String] = {FRIDGE: "Fridge", FREEZER: "Freezer", DRY: "Dry"}
const SPACE_WORDS: Dictionary[int, String] = {FRIDGE: "fridge", FREEZER: "freezer", DRY: "dry storage"}
const STOCK_WORDS: Dictionary[int, String] = {FRIDGE: "fridge", FREEZER: "freezer", DRY: "dry"}

var _capacity: Dictionary[int, int] = {}
var _in_stock: Dictionary[int, int] = {}
var _on_order: Dictionary[int, int] = {}
var _kind_of: Dictionary[StringName, int] = {}
var _pending_by_id: Dictionary[StringName, int] = {}


## `kinds` maps ingredient id -> IngredientDef.Storage; unknown ids count as dry.
## `pending` is what is paid for and not yet delivered, by ingredient id.
func _init(capacity: Dictionary[int, int] = {}, stock: Stock = null,
		pending: Dictionary[StringName, int] = {}, kinds: Dictionary[StringName, int] = {}) -> void:
	_kind_of = kinds.duplicate()
	for kind: int in KINDS:
		_capacity[kind] = maxi(0, int(capacity.get(kind, 0)))
		_in_stock[kind] = 0
		_on_order[kind] = 0
	if stock != null:
		for id: StringName in stock.ids():
			_in_stock[kind_of(id)] += stock.count(id)
	for id: StringName in pending:
		var qty: int = maxi(0, int(pending[id]))
		_pending_by_id[id] = qty
		_on_order[kind_of(id)] += qty


## Capacity per kind from the grid's placed items plus the built-in pantry.
## `exclude_item_id` previews the shop without one item (a sale).
static func capacities(grid: SimGrid, pantry_units: int, exclude_item_id: int = -1) -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {FRIDGE: 0, FREEZER: 0, DRY: maxi(0, pantry_units)}
	if grid == null:
		return out
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null or placed.removed or placed.id == exclude_item_id or definition.storage_units <= 0:
			continue
		var kind: int = int(definition.storage_kind)
		if out.has(kind):
			out[kind] += definition.storage_units
	return out


## Ingredient id -> storage kind for every ingredient in the content.
static func kinds_of(content: ContentDB) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	if content != null:
		for ingredient: IngredientDef in content.ingredients():
			out[ingredient.id] = int(ingredient.storage)
	return out


static func label(kind: int) -> String:
	return LABELS.get(kind, "Dry")


## "Not enough fridge space" (rule 11: never the enum name).
static func refusal(kind: int) -> String:
	return "Not enough %s space" % SPACE_WORDS.get(kind, "dry storage")


## Build mode's refusal for selling storage the stock still needs.
static func removal_refusal(kind: int) -> String:
	return "Move stock out first: the %s stock would not fit without it" % STOCK_WORDS.get(kind, "dry")


func kind_of(id: StringName) -> int:
	var kind: int = int(_kind_of.get(id, DRY))
	return kind if KINDS.has(kind) else DRY


func capacity(kind: int) -> int:
	return int(_capacity.get(kind, 0))


func in_stock(kind: int) -> int:
	return int(_in_stock.get(kind, 0))


func on_order(kind: int) -> int:
	return int(_on_order.get(kind, 0))


## Units an ingredient has on order (paid for, not yet delivered).
func pending_of(id: StringName) -> int:
	return int(_pending_by_id.get(id, 0))


## Stock plus orders: what the space must hold once every delivery is in.
func committed(kind: int) -> int:
	return in_stock(kind) + on_order(kind)


## Free units of a kind; zero when full or over (an old save may be over).
func free_units(kind: int) -> int:
	return maxi(0, capacity(kind) - committed(kind))


func is_over(kind: int) -> bool:
	return committed(kind) > capacity(kind)


## The first kind (in KINDS order) an order {id: qty} would overfill, or -1.
func first_overflow(quantities: Dictionary) -> int:
	var extra: Dictionary[int, int] = {}
	for id: Variant in quantities:
		var kind: int = kind_of(StringName(id))
		extra[kind] = int(extra.get(kind, 0)) + maxi(0, int(quantities[id]))
	for kind: int in KINDS:
		if int(extra.get(kind, 0)) > 0 and int(extra[kind]) > free_units(kind):
			return kind
	return -1


## Counts units as on order in this snapshot (planning several lines).
func reserve(id: StringName, qty: int) -> void:
	if qty <= 0:
		return
	_pending_by_id[id] = pending_of(id) + qty
	_on_order[kind_of(id)] += qty


## How full a kind is, 0..1, from stock on hand (the shelves show it).
func fill(kind: int) -> float:
	var room: int = capacity(kind)
	if room <= 0:
		return 0.0
	return clampf(float(in_stock(kind)) / float(room), 0.0, 1.0)


func copy() -> StorageSpace:
	var other: StorageSpace = StorageSpace.new()
	other._capacity = _capacity.duplicate()
	other._in_stock = _in_stock.duplicate()
	other._on_order = _on_order.duplicate()
	other._kind_of = _kind_of.duplicate()
	other._pending_by_id = _pending_by_id.duplicate()
	return other
