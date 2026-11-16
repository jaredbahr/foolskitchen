extends "res://tests/test_case.gd"

const BOOK: GDScript = preload("res://src/ui/guide_book.gd")
const EXPECTED_TITLES: PackedStringArray = [
	"Menu and prices", "Stock", "Staff and priorities", "Build and paint",
	"Vibe and themes", "Reviews and reputation", "Cleanliness", "Loans", "Events",
]


func test_pages_are_ordered_player_safe_and_sized_for_the_guide() -> void:
	var pages: Array[GuidePage] = BOOK.load_pages()
	assert_eq(pages.size(), EXPECTED_TITLES.size())
	for index: int in range(mini(pages.size(), EXPECTED_TITLES.size())):
		var page: GuidePage = pages[index]
		assert_eq(page.title, EXPECTED_TITLES[index])
		var words: PackedStringArray = page.body.replace("\n", " ").strip_edges().split(" ", false)
		assert_true(words.size() >= 80 and words.size() <= 200,
			"%s has %d words" % [page.title, words.size()])
		assert_false(page.body.contains("{"), "%s has an unresolved data marker" % page.title)
		assert_false(page.body.contains("data/"), "%s exposes a file path" % page.title)
		assert_false(page.body.contains("_"), "%s may expose an internal name" % page.title)


func test_numeric_guide_facts_follow_the_live_recipe_and_loan_resources() -> void:
	var pages: Array[GuidePage] = BOOK.load_pages()
	var menu: String = pages[0].body
	var loans: String = pages[7].body
	var career: String = pages[5].body
	assert_true(menu.contains("Fries opens at level 2"), "recipe level comes from the live resource")
	assert_true(menu.contains("Fish & chips follows at level 2"), "recipe chain comes from the live resource")
	assert_true(loans.contains("5% interest each day"), "interest comes from loan tuning")
	assert_true(loans.contains("50% of positive operating profit"), "repayment share comes from loan tuning")
	assert_true(loans.contains("$50"), "borrowing step comes from loan tuning")
	assert_true(career.contains("Tier 2 requires owner level 3"), "tier requirement comes from live career tuning")
	assert_true(career.contains("Tier 3 requires level 6 and 4.0 stars"), "tier level and reputation come from live tuning")
