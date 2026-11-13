extends TestCase
## Buying a lot (FK-087 part 1b, #464), pure parts: the tier site limits in
## data/balance/sites.tres, why a lot cannot be bought, what a purchase
## charges, the Buy button's words and the morning card's reads.

const LIMITS: SiteLimitTuning = preload("res://data/balance/sites.tres")


func _db() -> ContentDB:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all(), PackedStringArray())
	return db


func test_authored_site_limits_follow_the_design() -> void:
	assert_true(LIMITS.is_valid())
	assert_eq(LIMITS.limit_for(1), 1)
	assert_eq(LIMITS.limit_for(2), 1)
	assert_eq(LIMITS.limit_for(3), 2, "a second site at Tier 3")
	assert_eq(LIMITS.limit_for(4), 2)
	assert_eq(LIMITS.limit_for(5), 3, "a third at Tier 5")
	assert_eq(LIMITS.limit_for(6), SiteLimitTuning.UNLIMITED, "a chain at Tier 6")
	assert_true(LIMITS.allows_another(3, 1))
	assert_false(LIMITS.allows_another(3, 2))
	assert_true(LIMITS.allows_another(5, 2))
	assert_false(LIMITS.allows_another(5, 3))
	assert_true(LIMITS.allows_another(6, 40))
	assert_eq(LIMITS.tier_for_more(2), 5)
	assert_eq(LIMITS.tier_for_more(3), 6)


func test_bad_site_limits_are_invalid_and_allow_only_home() -> void:
	for bad: Array[int] in [[1, 1, 2] as Array[int], [0, 1, 2, 2, 3, 0] as Array[int],
			[1, 1, 2, 1, 3, 0] as Array[int], [1, 1, 0, 2, 3, 0] as Array[int], [1, 1, 2, 2, 3, -1] as Array[int]]:
		var tuning: SiteLimitTuning = SiteLimitTuning.new()
		tuning.sites_by_tier = bad
		assert_false(tuning.is_valid(), "invalid: %s" % str(bad))
		assert_eq(tuning.limit_for(6), 1)
		assert_false(tuning.allows_another(6, 1))


func test_purchase_refusals_come_in_order() -> void:
	var fixer: LotDef = _db().lot(&"town_fixer_upper") # Tier 3, $6,000 + $2,500.
	var seaside: LotDef = _db().lot(&"seaside_cliff") # Tier 3 and 4.2 stars.
	var cost: int = fixer.cost_to_open()
	assert_eq(cost, 8500)
	var none: PropertyMarket.Refusal = PropertyMarket.Refusal.NONE
	assert_eq(PropertyMarket.purchase_refusal(fixer, 3, NAN, false, 1, LIMITS, cost, 0), none,
		"exactly enough cash buys it; a lot without a star lock needs no closing reputation")
	assert_eq(PropertyMarket.purchase_refusal(fixer, 3, 3.0, true, 2, LIMITS, 0, 500),
		PropertyMarket.Refusal.OWNED, "owned comes first")
	assert_eq(PropertyMarket.purchase_refusal(seaside, 3, 4.1, false, 1, LIMITS, 99999, 0),
		PropertyMarket.Refusal.LOCKED)
	assert_eq(PropertyMarket.purchase_refusal(seaside, 3, NAN, false, 1, LIMITS, 99999, 0),
		PropertyMarket.Refusal.LOCKED, "no closing reputation yet keeps a star lock")
	assert_eq(PropertyMarket.purchase_refusal(fixer, 2, 5.0, false, 1, LIMITS, 99999, 0),
		PropertyMarket.Refusal.LOCKED, "below the market tier")
	assert_eq(PropertyMarket.purchase_refusal(fixer, 3, 5.0, false, 2, LIMITS, 99999, 0),
		PropertyMarket.Refusal.LIMIT, "Tier 3 allows two sites")
	assert_eq(PropertyMarket.purchase_refusal(fixer, 5, 5.0, false, 2, LIMITS, 99999, 0), none)
	assert_eq(PropertyMarket.purchase_refusal(fixer, 3, 5.0, false, 1, null, 99999, 0),
		PropertyMarket.Refusal.LIMIT, "no limits authored: no purchase")
	assert_eq(PropertyMarket.purchase_refusal(fixer, 3, 5.0, false, 1, LIMITS, 99999, 1),
		PropertyMarket.Refusal.LOAN)
	assert_eq(PropertyMarket.purchase_refusal(fixer, 3, 5.0, false, 1, LIMITS, cost - 1, 0),
		PropertyMarket.Refusal.CASH)


func test_a_purchase_charges_the_price_or_the_fixer_price_and_bill() -> void:
	var db: ContentDB = _db()
	var fixer: LotDef = db.lot(&"town_fixer_upper")
	var seaside: LotDef = db.lot(&"seaside_cliff")
	assert_eq(PropertyMarket.purchase_charges(fixer), [
		{"amount": -fixer.fixer_price, "category": Ledger.LOT_PURCHASE},
		{"amount": -fixer.renovation_bill, "category": Ledger.RENOVATION}] as Array[Dictionary])
	assert_eq(PropertyMarket.purchase_charges(seaside), [
		{"amount": -seaside.price, "category": Ledger.LOT_PURCHASE}] as Array[Dictionary])
	assert_eq(PropertyMarket.renovation_days(fixer), 3)
	assert_eq(PropertyMarket.renovation_days(seaside), 0)
	for lot: LotDef in db.lots():
		var total: int = 0
		for charge: Dictionary in PropertyMarket.purchase_charges(lot):
			total += int(charge["amount"])
		assert_eq(total, -lot.cost_to_open(), "%s charges what the market lists" % lot.id)


func test_buy_button_words_and_reasons_are_plain() -> void:
	var fixer: LotDef = _db().lot(&"town_fixer_upper")
	assert_eq(PropertyText.buy_label(fixer, PropertyMarket.Refusal.NONE), "Buy for $8,500")
	assert_eq(PropertyText.buy_label(fixer, PropertyMarket.Refusal.OWNED), "Owned")
	assert_eq(PropertyText.buy_label(fixer, PropertyMarket.Refusal.LOCKED), "Locked")
	assert_eq(PropertyText.buy_label(fixer, PropertyMarket.Refusal.CASH), "Buy")
	assert_eq(PropertyText.refusal_line(fixer, PropertyMarket.Refusal.NONE, 0, 1, LIMITS), "")
	assert_eq(PropertyText.refusal_line(fixer, PropertyMarket.Refusal.LOCKED, 0, 1, LIMITS), "",
		"the lock line says it")
	assert_eq(PropertyText.refusal_line(fixer, PropertyMarket.Refusal.OWNED, 0, 2, LIMITS), "You own this lot.")
	assert_eq(PropertyText.refusal_line(fixer, PropertyMarket.Refusal.CASH, 8000, 1, LIMITS),
		"Not enough cash: you need $500 more.")
	assert_eq(PropertyText.refusal_line(fixer, PropertyMarket.Refusal.LOAN, 0, 1, LIMITS),
		"Pay off your loan before buying a lot.")
	assert_eq(PropertyText.refusal_line(fixer, PropertyMarket.Refusal.LIMIT, 0, 2, LIMITS),
		"Your tier allows 2 restaurants. Reach Tier 5 to run more.")
	var capped: SiteLimitTuning = SiteLimitTuning.new()
	capped.sites_by_tier = [1, 1, 2, 2, 2, 2] as Array[int]
	assert_eq(PropertyText.refusal_line(fixer, PropertyMarket.Refusal.LIMIT, 0, 2, capped),
		"You run as many restaurants as you can.")
	assert_eq(PropertyText.renovation_report_note(2, false), "; renovating, 2 days left")
	assert_eq(PropertyText.renovation_report_note(1, false), "; renovating, 1 day left")
	assert_eq(PropertyText.renovation_report_note(0, true), "; renovation done, ready to open")
	assert_eq(PropertyText.renovation_report_note(0, false), "")
	assert_eq(PropertyText.bought_line(fixer),
		"You bought Old Mill Street. It needs 3 days of work before it can open.")


func test_a_lock_line_without_a_closing_reputation_quotes_no_stars() -> void:
	var seaside: LotDef = _db().lot(&"seaside_cliff")
	assert_eq(PropertyText.lock_line(seaside, 3, NAN), "Locked: needs 4.2 stars")
	assert_eq(PropertyText.lock_line(seaside, 3, 3.0), "Locked: needs 4.2 stars (you have 3.0)")


func test_takings_read_a_sites_own_guest_money() -> void:
	var ledger: Ledger = Ledger.new()
	ledger.record(4, 300, Ledger.SALE, "", &"home")
	ledger.record(4, 20, Ledger.TIP, "", &"home")
	ledger.record(4, -90, Ledger.WAGES, "", &"home")
	ledger.record(4, -8500, Ledger.LOT_PURCHASE, "", &"home")
	ledger.record(4, 84, Ledger.AWAY_SITE_INCOME, "", &"mill")
	ledger.record(5, 999, Ledger.SALE, "", &"home")
	assert_eq(SiteMorning.takings(ledger, 4, &"home"), 320, "sales and tips only")
	assert_eq(SiteMorning.takings(ledger, 4, &"mill"), 84, "a manager's takings")
	assert_eq(SiteMorning.takings(ledger, 3, &"home"), 0)
	assert_eq(SiteMorning.takings(ledger, 0, &"home"), 0)
	assert_eq(SiteMorning.takings(null, 4, &"home"), 0)


func test_card_lines() -> void:
	var row: SiteCard.Row = SiteCard.Row.new()
	row.takings = 1412
	assert_eq(SiteCard.status_line(row), "Yesterday's takings: $1,412")
	assert_eq(SiteCard.manager_line(row), "No manager")
	row.manager = "Ana"
	assert_eq(SiteCard.manager_line(row), "Manager: Ana")
	row.renovation_days = 1
	assert_eq(SiteCard.status_line(row), "Renovating: 1 day")
	row.renovation_days = 3
	assert_eq(SiteCard.status_line(row), "Renovating: 3 days")
