class_name LeaseUpgrade
extends Resource
## A larger lease on the same shop. No furniture or floor is supplied.
## Initial prices and margins are provisional balance tuning for review.

@export var owner_level: int = 3
@export var deposit: int = 300
@export var daily_rent: int = 60
@export var extra_west: int = 0
@export var extra_east: int = 4
@export var extra_north: int = 4


func is_valid() -> bool:
	return owner_level >= 3 and deposit > 0 and deposit <= 1000000 \
		and daily_rent > 0 and daily_rent <= 1000000 \
		and extra_west >= 0 and extra_west <= 32 and extra_east >= 0 and extra_east <= 32 \
		and extra_north >= 0 and extra_north <= 32 and extra_west + extra_east + extra_north > 0


## Always derive from the original template, never from a previously grown lot.
func layout_for(base: ShopLayout, tier: int) -> ShopLayout:
	var layout: ShopLayout = base.duplicate() as ShopLayout
	if tier == 2 and is_valid():
		layout.lot_west += extra_west
		layout.lot_east += extra_east
		layout.lot_north += extra_north
	return layout


func offered(progress: OwnerProgress, phase: int) -> bool:
	return is_valid() and progress != null and progress.property_tier == 1 \
		and progress.level >= owner_level and phase == SimClock.Phase.MORNING


## One source of plain player-facing refusal text for the panel and command.
func refusal(progress: OwnerProgress, phase: int, cash: int, loan: int) -> String:
	if not is_valid():
		return "This lease is not available"
	if progress.property_tier != 1:
		return "Your lease is already upgraded"
	if phase != SimClock.Phase.MORNING:
		return "Upgrade your lease in the morning"
	if progress.level < owner_level:
		return "Unlocks at owner level %d" % owner_level
	if loan > 0:
		return "Pay off your loan before upgrading your lease"
	if cash < deposit:
		return "Not enough cash for the lease deposit"
	return ""
