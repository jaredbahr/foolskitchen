class_name LotDef
extends Resource
## One lot on the property market (FK-087, D28): data only, in data/lots/.
## A lot is either move-in ready (`price`) or a fixer-upper (`fixer_price`
## plus a renovation bill and some days of work). Every lot can expand once,
## for `expansion_price`, after which it pays `expanded_daily_rent`.
## ContentDB.validate_lots checks every field; a bad lot fails the load.

## Tags this game knows. Each one is a perk on the market screen
## (PropertyText.TAG_PERKS) and, later, gates lot-only content.
const KNOWN_TAGS: Array[StringName] = [&"seaside", &"rooftop"]
const MIN_RENOVATION_DAYS: int = 2
const MAX_RENOVATION_DAYS: int = 5
## The most one expansion adds on a side (the home lease's own limit).
const MAX_EXPANSION_CELLS: int = 32

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var blurb: String = ""
## The lot's own shop: its shell, starting kitchen, lot margins (which bound
## its maximum footprint) and floor price.
@export var base_layout: ShopLayout
## Move-in ready price; 0 for a fixer-upper.
@export var price: int = 0
## Fixer-upper price; 0 for a move-in ready lot.
@export var fixer_price: int = 0
@export var renovation_bill: int = 0
@export var renovation_days: int = 0
@export var daily_rent: int = 0
## Every lot can expand once (Jared, 2026-11-13): the one-off cost and the
## daily rent from then on (#465).
@export var expansion_price: int = 0
@export var expanded_daily_rent: int = 0
## How many cells the expansion adds to the lot's own margins on each side
## (like the home lease's extra_west/east/north). 0 to MAX_EXPANSION_CELLS
## each, at least one above 0. The street side never grows.
@export var expansion_west: int = 0
@export var expansion_east: int = 0
@export var expansion_north: int = 0
@export_range(1, 6, 1) var min_tier: int = 3
## Closing reputation in stars; 0 means none.
@export_range(0.0, 5.0, 0.1) var min_reputation: float = 0.0
## Share of each existing customer type (CustomerType ids); need not sum to 1.
@export var guest_mix: Dictionary[StringName, float] = {}
@export var upstairs_allowed: bool = false
@export var tags: Array[StringName] = []


func is_fixer_upper() -> bool:
	return fixer_price > 0


## What it costs to get the lot open: the price, or the fixer price plus the
## renovation bill. The market lists lots by this, cheapest first.
func cost_to_open() -> int:
	return fixer_price + renovation_bill if is_fixer_upper() else price


## Floor cells of the starting shell ('.' in the layout's rows).
func size_cells() -> int:
	if base_layout == null:
		return 0
	var cells: int = 0
	for row: String in base_layout.rows:
		cells += row.count(".")
	return cells


## The lot's expansion as lease terms, so the offer, refusal and layout share
## the home lease's rules (D30): the price is the deposit, the expanded rent
## the daily rent, and the lot's own margins grow. `home` gives the owner
## level (unused since career tiers, kept for LeaseUpgrade.is_valid).
func lease_upgrade(home: LeaseUpgrade) -> LeaseUpgrade:
	var lease: LeaseUpgrade = LeaseUpgrade.new()
	lease.owner_level = home.owner_level if home != null else lease.owner_level
	lease.deposit = expansion_price
	lease.daily_rent = expanded_daily_rent
	lease.extra_west = expansion_west
	lease.extra_east = expansion_east
	lease.extra_north = expansion_north
	return lease


## The lot's daily rent with its lease expanded or not.
func rent(expanded: bool) -> int:
	return expanded_daily_rent if expanded else daily_rent
