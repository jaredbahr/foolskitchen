class_name LoanAccount
extends RefCounted
## Day-close financing, independent of scenes and autosave timing. Principal is
## persistent; a repeated close for the same day cannot charge twice.

const MAX_CURRENCY: int = 9223372036854775807
const MIN_CURRENCY: int = -MAX_CURRENCY - 1

var principal: int = 0
var last_settled_day: int = 0
## Durable history, including a fully repaid loan, keeps the first notice once.
var has_borrowed: bool = false


## Profit is sampled before financing so a bank advance never counts as income
## available for repayment. Existing principal pays interest before repayment;
## a newly opened advance starts accruing on the following close.
@warning_ignore("integer_division")
func settle_day(ledger: Ledger, day: int, terms: LoanTuning) -> Dictionary:
	if ledger == null or terms == null or not terms.is_valid() \
			or principal < 0 or day < 1 or day <= last_settled_day:
		return {}
	var operating_profit: int = ledger.day_profit(day)
	var interest: int = roundi(float(principal) * terms.daily_interest) if principal > 0 else 0
	var repayment: int = 0
	if principal > 0 and operating_profit > 0 and terms.repay_share > 0.0:
		# The ledger has whole dollars. Floor the share, but collect at least $1
		# on a profitable day so a small remaining loan can actually close.
		# float(INT64_MAX) rounds up to 2^63, which floori cannot represent.
		repayment = mini(principal, operating_profit) if terms.repay_share == 1.0 else mini(principal,
			maxi(1, floori(float(operating_profit) * terms.repay_share)))
	# Preflight every signed operation before changing the ledger or account.
	# Even two individually representable charges can overflow when combined.
	if interest > MAX_CURRENCY - repayment:
		return {}
	var charges: int = interest + repayment
	if ledger.cash < MIN_CURRENCY + charges:
		return {}
	var projected_cash: int = ledger.cash - charges
	var advance: int = 0
	if projected_cash < 0:
		# Negating INT64_MIN cannot produce a representable positive shortage.
		if projected_cash == MIN_CURRENCY:
			return {}
		# Integer division keeps the $50 rounding exact, even for large balances.
		var shortage: int = -projected_cash
		var largest_advance: int = (MAX_CURRENCY / terms.borrowing_step) * terms.borrowing_step
		if shortage > largest_advance:
			return {}
		var blocks: int = shortage / terms.borrowing_step
		if shortage % terms.borrowing_step != 0:
			blocks += 1
		advance = blocks * terms.borrowing_step
		if principal - repayment > MAX_CURRENCY - advance:
			return {}
	var movements: Array[Dictionary] = []
	var borrowed_before: bool = has_borrowed or principal > 0
	var first_advance: bool = advance > 0 and not borrowed_before
	if interest > 0:
		ledger.record(day, -interest, Ledger.LOAN_INTEREST)
		movements.append({"amount": -interest, "category": Ledger.LOAN_INTEREST})
	if repayment > 0:
		ledger.record(day, -repayment, Ledger.LOAN_REPAYMENT)
		movements.append({"amount": -repayment, "category": Ledger.LOAN_REPAYMENT})
	principal -= repayment
	if advance > 0:
		ledger.record(day, advance, Ledger.BANK_LOAN)
		movements.append({"amount": advance, "category": Ledger.BANK_LOAN})
		principal += advance
	has_borrowed = borrowed_before or advance > 0
	last_settled_day = day
	return {"operating_profit": operating_profit,
		"interest": interest, "repayment": repayment, "advance": advance,
		"principal": principal, "first_advance": first_advance, "movements": movements}


func to_dict() -> Dictionary:
	return {"version": 1, "principal": str(principal),
		"last_settled_day": str(last_settled_day), "has_borrowed": has_borrowed or principal > 0}


## Invalid snapshots never mutate the caller's live account.
static func from_dict(value: Variant) -> LoanAccount:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	if data.get("version", null) != 1:
		return null
	var principal_text: Variant = data.get("principal", null)
	var day_text: Variant = data.get("last_settled_day", null)
	if not principal_text is String or not day_text is String:
		return null
	var principal_string: String = String(principal_text)
	var day_string: String = String(day_text)
	if not principal_string.is_valid_int() or not day_string.is_valid_int():
		return null
	var saved_principal: int = int(principal_string)
	var saved_day: int = int(day_string)
	if saved_principal < 0 or saved_day < 0 \
			or str(saved_principal) != principal_string or str(saved_day) != day_string:
		return null
	# Earlier loan snapshots did not retain paid-off history. An active loan
	# already received the introduction; a debt-free old snapshot is unknown.
	var borrowed: Variant = data.get("has_borrowed", saved_principal > 0)
	if not borrowed is bool or (saved_principal > 0 and not borrowed):
		return null
	var restored: LoanAccount = LoanAccount.new()
	restored.principal = saved_principal
	restored.last_settled_day = saved_day
	restored.has_borrowed = borrowed
	return restored
