extends TestCase


func test_money_groups_thousands_and_negatives() -> void:
	assert_eq(Fmt.money(0), "$0")
	assert_eq(Fmt.money(12), "$12")
	assert_eq(Fmt.money(1234), "$1,234")
	assert_eq(Fmt.money(-1234567), "-$1,234,567")
	assert_eq(Fmt.money(-9223372036854775807 - 1), "-$9,223,372,036,854,775,808")


func test_clock_zero_and_leading_zero_minutes() -> void:
	assert_eq(Fmt.clock(0), "00:00")
	assert_eq(Fmt.clock(9 * 60 + 5), "09:05")
	assert_eq(Fmt.clock(21 * 60), "21:00")
	assert_eq(Fmt.clock(-1), "00:00")
	assert_eq(Fmt.clock(24 * 60), "00:00")
