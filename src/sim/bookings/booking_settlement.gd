class_name BookingSettlement
extends RefCounted
## Explicit cash movements for a customer advance and its final meal bill.

static func deposit_movement(booking: Dictionary) -> Dictionary:
	if booking.is_empty():
		return {}
	var amount: int = int(booking.get("deposit_amount", 0))
	if amount <= 0:
		return {}
	return {"amount": amount, "category": Ledger.BOOKING_DEPOSIT, "note": "Customer booking advance"}


## SALE records the full earned bill. The paired liability entries reduce the
## cash movement to bill minus advance and refund any unused advance.
static func pay_bill(booking: Dictionary, full_bill: int) -> Array[Dictionary]:
	var movements: Array[Dictionary] = []
	if booking.is_empty() or full_bill < 0:
		return movements
	var advance: int = int(booking.get("deposit_amount", 0))
	if advance < 0:
		return movements
	var applied: int = mini(advance, full_bill)
	var refund: int = advance - applied
	movements.append({"amount": full_bill, "category": Ledger.SALE, "note": "Booked party meal"})
	if applied > 0:
		movements.append({"amount": -applied, "category": Ledger.BOOKING_DEPOSIT,
			"note": "Booking advance applied"})
	if refund > 0:
		movements.append({"amount": -refund, "category": Ledger.BOOKING_REFUND,
			"note": "Unused booking advance refunded"})
	return movements


static func no_seat_refund(booking: Dictionary) -> Dictionary:
	if booking.is_empty():
		return {}
	var amount: int = int(booking.get("deposit_amount", 0))
	if amount <= 0:
		return {}
	return {"amount": -amount, "category": Ledger.BOOKING_REFUND,
		"note": "Booking could not be seated"}


static func good_service_tip(full_bill: int, stars: int, tuning: BookingTuning) -> int:
	if full_bill <= 0 or tuning == null or not tuning.is_valid() or stars < tuning.good_service_stars:
		return 0
	return roundi(float(full_bill) * tuning.tip_bonus)
