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
	assert_true(book.set_manager(&"harbour", &"staff_7"))
	var copy: SiteBook = SiteBook.from_dict(_json(book.to_dict()))
	assert_true(copy != null)
	assert_eq(_json(copy.to_dict()), _json(book.to_dict()), "a second round trip is identical")
	assert_eq(copy.site_ids(), [&"home", &"harbour"] as Array[StringName])
	assert_eq(copy.frozen_day(&"harbour"), 4)
	assert_eq(copy.frozen_sections(&"harbour"), _json(SECTIONS))
	assert_eq(copy.site_name(&"harbour"), "Pier Shack")
	assert_eq(copy.manager(&"harbour"), &"staff_7")
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
	assert_eq(book.frozen_sections(&"home"), _json({"shop": {"version": 3}}))
	assert_true(SiteBook.from_dict(_json(book.to_dict())) != null)


func test_bad_new_sites_are_refused() -> void:
	var book: SiteBook = SiteBook.new()
	assert_false(book.add_site(&"home", &"x", "", 1, {}), "ids are unique")
	assert_false(book.add_site(&"Bad Id", &"x", "", 1, {}))
	assert_false(book.add_site(&"a", &"x", " padded", 1, {}))
	assert_false(book.add_site(&"a", &"x", "", -1, {}))
	assert_false(book.add_site(&"a", &"x", "", 1, {"clock": {}}), "global sections never freeze with a site")
	assert_false(book.add_site(&"a", &"x", "", 1, {"shop": 5}))
	assert_false(book.add_site(&"a", SiteBook.HOME_LOT, "", 1, {}), "one site per lot")
	assert_false(book.add_site(&"a", &"x", "Tab\there", 1, {}))
	assert_false(book.set_manager(SiteBook.HOME_ID, &"Not An Id"))
	assert_eq(book.site_count(), 1)


func test_frozen_copies_take_the_shape_of_a_loaded_file_and_save_stable_bytes() -> void:
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"harbour", &"pier_lot", "", 1, {"shop": {"n": 3, "s": &"sn", "k": {5: 1}}}))
	var first: String = JSON.stringify(book.to_dict())
	var reloaded: SiteBook = SiteBook.from_dict(_json(book.to_dict()))
	assert_eq(JSON.stringify(reloaded.to_dict()), first, "the same bytes after a reload")
	assert_eq(book.frozen_sections(&"harbour"), reloaded.frozen_sections(&"harbour"))
	assert_true(book.frozen_sections(&"harbour")["shop"]["n"] is float)


func test_a_site_cannot_become_active_before_the_day_it_was_frozen() -> void:
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"harbour", &"pier_lot", "", 5, SECTIONS))
	assert_false(book.can_swap(&"harbour", 4))
	assert_false(book.swap_active(&"harbour", 4, SECTIONS))
	assert_true(book.can_swap(&"harbour", 5))
	assert_false(book.can_swap(SiteBook.HOME_ID, 5), "the active site is not a swap target")


func test_malformed_sections_are_refused() -> void:
	var good: Dictionary = {"version": 1, "active": "home", "sites": [
		{"id": "home", "lot": "home", "name": "", "manager": ""},
		{"id": "harbour", "lot": "pier_lot", "name": "", "manager": "", "frozen_day": "2", "sections": {}}]}
	assert_true(SiteBook.from_dict(good) != null)
	var cases: Array[Callable] = [
		func(d: Dictionary) -> void: d["version"] = 3,
		func(d: Dictionary) -> void: d["version"] = 0,
		func(d: Dictionary) -> void: d["sites"][1]["renovation_days_left"] = 2,
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
		func(d: Dictionary) -> void: d["sites"][1]["manager"] = "Bad Id",
		func(d: Dictionary) -> void: d["version"] = "1",
		func(d: Dictionary) -> void: d["version"] = 1.5,
		func(d: Dictionary) -> void: d["version"] = true,
		func(d: Dictionary) -> void: d["version"] = [1],
		func(d: Dictionary) -> void: d["version"] = {},
		func(d: Dictionary) -> void: d["future"] = 1,
		func(d: Dictionary) -> void: d["sites"][1]["lease_expanded"] = true,
		func(d: Dictionary) -> void: d["sites"][1]["lot"] = "home",
		func(d: Dictionary) -> void: d["sites"][1]["name"] = "Two\nlines",
	]
	for index: int in cases.size():
		var data: Dictionary = good.duplicate(true)
		cases[index].call(data)
		assert_true(SiteBook.from_dict(data) == null, "malformed case %d is refused" % index)


## #464: version 2 keeps a fixer-upper's days of work on its row.
func _v2_with(days: Variant) -> Dictionary:
	return {"version": 2, "active": "home", "sites": [
		{"id": "home", "lot": "home", "name": "", "manager": ""},
		{"id": "mill", "lot": "mill_lot", "name": "Old Mill", "manager": "", "frozen_day": "2",
			"sections": {}, "renovation_days_left": days}]}


func test_a_version_one_section_migrates_with_every_site_ready() -> void:
	var old: Dictionary = {"version": 1, "active": "harbour", "sites": [
		{"id": "home", "lot": "home", "name": "", "manager": "", "frozen_day": "3", "sections": {}},
		{"id": "harbour", "lot": "pier_lot", "name": "Pier Shack", "manager": "staff_2"}]}
	var book: SiteBook = SiteBook.from_dict(_json(old))
	assert_true(book != null, "a version 1 section still loads")
	assert_eq(book.active_id, &"harbour")
	assert_eq(book.renovation_days_left(&"home"), 0)
	assert_eq(book.renovation_days_left(&"harbour"), 0)
	assert_true(book.can_swap(&"home", 3))
	var saved: Dictionary = _json(book.to_dict())
	assert_eq(int(saved["version"]), SiteBook.VERSION, "it saves as the new version")
	assert_eq(SiteBook.VERSION, 2)
	for row: Dictionary in saved["sites"]:
		assert_false(row.has("renovation_days_left"), "a ready site writes no renovation field")
	assert_eq(_json(SiteBook.from_dict(saved).to_dict()), saved, "and round-trips")


func test_a_renovating_site_round_trips_counts_down_and_cannot_swap_until_ready() -> void:
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"mill", &"mill_lot", "Old Mill", 4, SECTIONS, 3))
	assert_eq(book.renovation_days_left(&"mill"), 3)
	assert_false(book.can_swap(&"mill", 4), "a site under renovation is not a swap target")
	assert_false(book.swap_active(&"mill", 4, SECTIONS))
	var copy: SiteBook = SiteBook.from_dict(_json(book.to_dict()))
	assert_true(copy != null)
	assert_eq(copy.renovation_days_left(&"mill"), 3, "the days left are saved on the row")
	assert_eq(_json(copy.to_dict()), _json(book.to_dict()))
	assert_eq(copy.count_down_renovations(), [] as Array[StringName])
	assert_eq(copy.renovation_days_left(&"mill"), 2)
	assert_eq(copy.count_down_renovations(), [] as Array[StringName])
	assert_false(copy.can_swap(&"mill", 6))
	assert_eq(copy.count_down_renovations(), [&"mill"] as Array[StringName], "ready on the third day")
	assert_eq(copy.renovation_days_left(&"mill"), 0)
	assert_true(copy.can_swap(&"mill", 7))
	assert_eq(copy.count_down_renovations(), [] as Array[StringName], "a ready site stays at 0")
	assert_false((copy.to_dict()["sites"][1] as Dictionary).has("renovation_days_left"))


func test_renovation_days_are_checked() -> void:
	var book: SiteBook = SiteBook.new()
	assert_false(book.add_site(&"mill", &"mill_lot", "", 1, SECTIONS, -1))
	assert_false(book.add_site(&"mill", &"mill_lot", "", 1, SECTIONS, SiteBook.MAX_RENOVATION_DAYS + 1))
	assert_eq(book.site_count(), 1)
	assert_true(SiteBook.from_dict(_json(_v2_with(5))) != null)
	assert_true(SiteBook.from_dict(_json(_v2_with(1))) != null)
	for bad: Variant in [0, 6, -1, 2.5, "2", null, true]:
		assert_true(SiteBook.from_dict(_v2_with(bad)) == null, "renovation %s is refused" % str(bad))


func test_owns_lot_reads_every_site() -> void:
	var book: SiteBook = SiteBook.new()
	assert_true(book.owns_lot(SiteBook.HOME_LOT))
	assert_false(book.owns_lot(&"mill_lot"))
	assert_true(book.add_site(&"mill", &"mill_lot", "", 1, SECTIONS, 2))
	assert_true(book.owns_lot(&"mill_lot"))
