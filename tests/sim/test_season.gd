extends TestCase
## Pure 28-day seasons and one whole-unit supplier-price calculation.

const TUNING: SeasonTuning = preload("res://data/balance/seasons.tres")


func test_calendar_boundaries_repeat_without_saved_state() -> void:
	for pair: Array in [[-8, Season.Kind.SPRING], [0, Season.Kind.SPRING],
			[1, Season.Kind.SPRING], [28, Season.Kind.SPRING],
			[29, Season.Kind.SUMMER], [56, Season.Kind.SUMMER],
			[57, Season.Kind.AUTUMN], [84, Season.Kind.AUTUMN],
			[85, Season.Kind.WINTER], [112, Season.Kind.WINTER],
			[113, Season.Kind.SPRING], [140, Season.Kind.SPRING],
			[141, Season.Kind.SUMMER]]:
		assert_eq(Season.kind_for_day(int(pair[0])), int(pair[1]))


func test_authored_lists_use_known_distinct_ingredient_ids() -> void:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all().size(), 0)
	assert_eq(TUNING.validate(db.ingredients()), PackedStringArray())
	for kind: int in 4:
		assert_true(TUNING.is_in_season(&"fish_fillet", kind)
				or TUNING.is_out_of_season(&"fish_fillet", kind))
		assert_eq(TUNING.multiplier_for(&"rice", kind), 1.0)


func test_typo_duplicate_overlap_and_bad_multiplier_are_rejected() -> void:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all().size(), 0)
	var edited: SeasonTuning = TUNING.duplicate(true) as SeasonTuning
	edited.spring_in[0] = &"missing_fish"
	assert_true(edited.validate(db.ingredients()).size() > 0)
	edited = TUNING.duplicate(true) as SeasonTuning
	edited.spring_in[0] = edited.spring_in[1]
	assert_true(edited.validate(db.ingredients()).size() > 0)
	edited = TUNING.duplicate(true) as SeasonTuning
	edited.spring_out[0] = edited.spring_in[0]
	assert_true(edited.validate(db.ingredients()).size() > 0)
	edited = TUNING.duplicate(true) as SeasonTuning
	edited.out_of_season_multiplier = NAN
	assert_true(edited.validate(db.ingredients()).size() > 0)
	edited = TUNING.duplicate(true) as SeasonTuning
	edited.winter_out.clear()
	assert_true(edited.validate(db.ingredients()).size() > 0)
	assert_eq(TUNING.validate(db.ingredients()), PackedStringArray(),
		"invalid in-memory copies must not change authored data")


func test_each_unit_is_rounded_once_and_base_resource_is_unchanged() -> void:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all().size(), 0)
	var fish: IngredientDef = db.ingredient(&"fish_fillet")
	assert_eq(fish.unit_cost, 3)
	assert_eq(Season.purchase_unit_cost(fish.id, fish.unit_cost, 28, TUNING), 2)
	assert_eq(Season.purchase_unit_cost(fish.id, fish.unit_cost, 29, TUNING), 4)
	assert_eq(Season.purchase_unit_cost(&"mussels", 3, 28, TUNING), 4)
	assert_eq(Season.purchase_unit_cost(&"mussels", 3, 29, TUNING), 2)
	assert_eq(Season.purchase_unit_cost(&"rice", 1, 29, TUNING), 1)
	assert_eq(Season.purchase_unit_cost(&"fish_fillet", 0, 28, TUNING), 0)
	assert_eq(fish.unit_cost, 3, "pricing must not revalue the authored definition")
