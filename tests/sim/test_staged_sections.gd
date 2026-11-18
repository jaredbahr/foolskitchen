extends TestCase
## StagedSections: the staging shelf of a load (#526). Pure: no scene, Node
## or autoload. Every field is found by reflection, so a field added later
## fails here until `_filled()` sets it and `clear()` or `clear_site()` resets it.

## The sections a site switch stages (`SiteSections.PER_SITE` as fields).
const PER_SITE: PackedStringArray = ["layout", "tray_level", "lease_expanded", "site_hours", "menu", "evening_schedule",
	"daily_special", "signature", "staff", "plates", "reputation", "regulars", "reorder", "deliveries",
	"demand", "viral", "business_history", "shop_records", "cat", "inspection", "critic", "group_booking",
	"rush_hour", "aquarium"]
## The sections only a morning load stages.
const GLOBAL: PackedStringArray = ["difficulty", "sites", "blueprints", "menu_presets", "milestones",
	"weekly_challenge", "service_events", "opening_week", "weather", "collection_toast_ids",
	"has_collection_toast_section"]


func _filled() -> StagedSections:
	var shelf: StagedSections = StagedSections.new()
	shelf.layout = ShopLayout.new()
	shelf.tray_level = 2
	shelf.lease_expanded = true
	shelf.site_hours = {"open_minute": 600, "close_minute": 1200, "open_ticks": 6000}
	shelf.menu = MenuSettings.new()
	shelf.evening_schedule = EveningSchedule.new()
	shelf.daily_special = {"day": 3}
	shelf.signature = SignatureState.new()
	shelf.staff = StaffRoster.new()
	shelf.plates = PlateLedger.new(12)
	shelf.reputation = ReputationBook.new()
	shelf.regulars = RegularCast.new()
	shelf.reorder = ReorderSettings.new()
	shelf.deliveries = DeliveryBook.new()
	shelf.demand = DemandState.new()
	shelf.viral = ViralReview.new()
	shelf.business_history = BusinessHistory.new()
	shelf.shop_records = ShopRecords.new()
	shelf.cat = {"adopted": true}
	shelf.inspection = {"last_day": 2}
	shelf.critic = {"cooldown": 1}
	shelf.group_booking = GroupBooking.new()
	shelf.rush_hour = {"start_minute": 720}
	shelf.aquarium = {"tanks": []}
	shelf.difficulty = Difficulty.new()
	shelf.sites = SiteBook.new()
	shelf.blueprints = BlueprintLibrary.new()
	shelf.menu_presets = MenuPresetLibrary.new()
	shelf.milestones = MilestoneTracker.new()
	shelf.weekly_challenge = WeeklyChallengeState.new()
	shelf.service_events = ServiceEvents.new()
	shelf.opening_week = OpeningWeek.new()
	shelf.weather = WeatherState.new()
	shelf.collection_toast_ids = [&"diner_classics"] as Array[StringName]
	shelf.has_collection_toast_section = true
	return shelf


func _fields() -> PackedStringArray:
	var names: PackedStringArray = []
	for property: Dictionary in StagedSections.new().get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	return names


func _is_empty(shelf: StagedSections, field: String) -> bool:
	var value: Variant = shelf.get(field)
	var fresh: Variant = StagedSections.new().get(field)
	return typeof(value) == typeof(fresh) and value == fresh


func test_every_field_is_per_site_or_global() -> void:
	var listed: PackedStringArray = PER_SITE + GLOBAL
	for field: String in _fields():
		assert_true(listed.has(field), "'%s' is in one of this test's two lists" % field)
	for field: String in listed:
		assert_true(_fields().has(field), "'%s' is a field of StagedSections" % field)
	assert_eq(listed.size(), _fields().size(), "no field is in both lists")


func test_a_new_shelf_is_empty() -> void:
	var shelf: StagedSections = StagedSections.new()
	for field: String in _fields():
		var value: Variant = shelf.get(field)
		assert_true(value == null or (value is int and value == 0) or (value is bool and not value)
			or (value is Dictionary and (value as Dictionary).is_empty())
			or (value is Array and (value as Array).is_empty()), "'%s' starts empty" % field)


func test_the_filled_fixture_sets_every_field() -> void:
	var shelf: StagedSections = _filled()
	for field: String in _fields():
		assert_false(_is_empty(shelf, field), "the fixture stages '%s'" % field)


func test_clear_resets_every_field() -> void:
	var shelf: StagedSections = _filled()
	shelf.clear()
	for field: String in _fields():
		assert_true(_is_empty(shelf, field), "clear() resets '%s'" % field)


func test_clear_site_resets_the_per_site_fields_only() -> void:
	var shelf: StagedSections = _filled()
	var difficulty: Difficulty = shelf.difficulty
	shelf.clear_site()
	for field: String in PER_SITE:
		assert_true(_is_empty(shelf, field), "clear_site() resets '%s'" % field)
	for field: String in GLOBAL:
		assert_false(_is_empty(shelf, field), "clear_site() keeps the global '%s'" % field)
	assert_true(shelf.difficulty == difficulty, "the same staged object, not a copy")
	assert_eq(shelf.collection_toast_ids, [&"diner_classics"] as Array[StringName])


func test_clear_empties_the_toast_list_in_place() -> void:
	var shelf: StagedSections = _filled()
	var ids: Array[StringName] = shelf.collection_toast_ids
	shelf.clear()
	assert_true(ids.is_empty(), "the list a caller holds is emptied, as the load did before")
	assert_true(is_same(ids, shelf.collection_toast_ids))


func test_clearing_twice_and_restaging_works() -> void:
	var shelf: StagedSections = _filled()
	shelf.clear()
	shelf.clear()
	shelf.clear_site()
	shelf.cat = {"adopted": true}
	shelf.collection_toast_ids.append(&"cozy_corner")
	assert_eq(shelf.cat, {"adopted": true})
	assert_eq(shelf.collection_toast_ids.size(), 1)
	assert_true(StagedSections.new().collection_toast_ids.is_empty(), "shelves do not share a list")
