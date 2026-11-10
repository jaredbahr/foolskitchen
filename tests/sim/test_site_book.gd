extends TestCase
## The owner's sites: one active, the rest frozen copies of per-site sections.

const SECTIONS: Dictionary = {"shop": {"version": 9}, "pantry": {"stock": {"batches": {}}}}


func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))


func test_a_new_book_is_the_home_site_alone() -> void:
	var book: SiteBook = SiteBook.new()
	assert_eq(book.site_ids(), [SiteBook.HOME_ID] as Array[StringName])
	assert_eq(book.active_id, SiteBook.HOME_ID)
	assert_false(book.is_frozen(SiteBook.HOME_ID))
	assert_eq(book.lot_id(SiteBook.HOME_ID), SiteBook.HOME_LOT)
	assert_true(book.valid_before(0))


func test_two_sites_round_trip_through_json() -> void:
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"harbour", &"pier_lot", "Pier Shack", 4, SECTIONS))
	assert_true(book.set_manager(&"harbour", "staff_7"))
	var copy: SiteBook = SiteBook.from_dict(_json(book.to_dict()))
	assert_true(copy != null)
	assert_eq(_json(copy.to_dict()), _json(book.to_dict()), "a second round trip is identical")
	assert_eq(copy.site_ids(), [&"home", &"harbour"] as Array[StringName])
	assert_eq(copy.frozen_day(&"harbour"), 4)
	assert_eq(copy.frozen_sections(&"harbour"), _json(SECTIONS))
	assert_eq(copy.site_name(&"harbour"), "Pier Shack")
	assert_eq(copy.manager(&"harbour"), "staff_7")
	assert_false(copy.valid_before(3), "a site frozen after this morning is refused")
	assert_true(copy.valid_before(4))


func test_frozen_sections_are_detached_copies() -> void:
	var book: SiteBook = SiteBook.new()
	var sections: Dictionary = SECTIONS.duplicate(true)
	assert_true(book.add_site(&"harbour", &"pier_lot", "", 1, sections))
	sections["shop"]["version"] = 1
	var out: Dictionary = book.frozen_sections(&"harbour")
	out["shop"]["version"] = 2
	assert_eq(int(book.frozen_sections(&"harbour")["shop"]["version"]), 9)


func test_swap_active_freezes_the_departing_site_and_drops_the_target_copy() -> void:
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"harbour", &"pier_lot", "", 1, SECTIONS))
	assert_false(book.swap_active(&"home", 2, SECTIONS), "already active")
	assert_false(book.swap_active(&"nowhere", 2, SECTIONS))
	assert_false(book.swap_active(&"harbour", 2, {"sites": {}}), "only per-site sections can be frozen")
	assert_eq(book.active_id, SiteBook.HOME_ID, "a refused swap changes nothing")
	assert_true(book.swap_active(&"harbour", 2, {"shop": {"version": 3}}))
	assert_eq(book.active_id, &"harbour")
	assert_false(book.is_frozen(&"harbour"))
	assert_eq(book.frozen_day(&"home"), 2)
	assert_eq(book.frozen_sections(&"home"), {"shop": {"version": 3}})
	assert_true(SiteBook.from_dict(_json(book.to_dict())) != null)


func test_bad_new_sites_are_refused() -> void:
	var book: SiteBook = SiteBook.new()
	assert_false(book.add_site(&"home", &"x", "", 1, {}), "ids are unique")
	assert_false(book.add_site(&"Bad Id", &"x", "", 1, {}))
	assert_false(book.add_site(&"a", &"x", " padded", 1, {}))
	assert_false(book.add_site(&"a", &"x", "", -1, {}))
	assert_false(book.add_site(&"a", &"x", "", 1, {"clock": {}}), "global sections never freeze with a site")
	assert_false(book.add_site(&"a", &"x", "", 1, {"shop": 5}))
	assert_eq(book.site_count(), 1)


func test_malformed_sections_are_refused() -> void:
	var good: Dictionary = {"version": 1, "active": "home", "sites": [
		{"id": "home", "lot": "home", "name": "", "manager": ""},
		{"id": "harbour", "lot": "pier_lot", "name": "", "manager": "", "frozen_day": "2", "sections": {}}]}
	assert_true(SiteBook.from_dict(good) != null)
	var cases: Array[Callable] = [
		func(d: Dictionary) -> void: d["version"] = 2,
		func(d: Dictionary) -> void: d["active"] = "elsewhere",
		func(d: Dictionary) -> void: d["sites"] = {},
		func(d: Dictionary) -> void: d["sites"].append(d["sites"][1].duplicate(true)),
		func(d: Dictionary) -> void: d["sites"][0]["frozen_day"] = "1",
		func(d: Dictionary) -> void: d["sites"][1].erase("frozen_day"),
		func(d: Dictionary) -> void: d["sites"][1]["frozen_day"] = "-1",
		func(d: Dictionary) -> void: d["sites"][1]["frozen_day"] = 2.5,
		func(d: Dictionary) -> void: d["sites"][1]["frozen_day"] = "02",
		func(d: Dictionary) -> void: d["sites"][1]["sections"] = {"owner": {}},
		func(d: Dictionary) -> void: d["sites"][1]["lot"] = "",
		func(d: Dictionary) -> void: d["sites"][1]["name"] = 7,
		func(d: Dictionary) -> void: d["sites"][1]["manager"] = null,
	]
	for index: int in cases.size():
		var data: Dictionary = good.duplicate(true)
		cases[index].call(data)
		assert_true(SiteBook.from_dict(data) == null, "malformed case %d is refused" % index)
