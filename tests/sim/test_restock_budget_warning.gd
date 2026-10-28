extends TestCase

func test_warning_below_reserve_but_not_at_or_above_it() -> void:
	assert_eq(RestockBudgetWarning.text(99, 20, 80), "Leaves $79; allow about $80 for restocking")
	assert_eq(RestockBudgetWarning.text(100, 20, 80), "")
	assert_eq(RestockBudgetWarning.text(101, 20, 80), "")

func test_free_refund_unaffordable_and_empty_restock_do_not_add_advice() -> void:
	assert_eq(RestockBudgetWarning.text(50, 0, 80), "")
	assert_eq(RestockBudgetWarning.text(50, -10, 80), "")
	assert_eq(RestockBudgetWarning.text(10, 20, 80), "")
	assert_eq(RestockBudgetWarning.text(50, 20, 0), "")