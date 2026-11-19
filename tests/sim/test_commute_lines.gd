extends TestCase
## The commute lines after a van ride (docs/CITY_MAP.md T5): the shipped data
## has the director's lines, and the pick depends on the day and the
## destination alone and never repeats the line shown just before. Pure.

const AREAS: Array[StringName] = [&"old_town", &"millbrook", &"seafront", &"skyline", &"pinewood"]


func _lines() -> CommuteLines:
	var lines: CommuteLines = CommuteLines.load_default()
	assert_not_null(lines, "data/city/commute_lines.tres loads")
	return lines


func _area_line(map: CityMapDef, id: StringName) -> String:
	return map.neighbourhood(id).commute_line


func test_the_shipped_lines_are_data() -> void:
	var lines: CommuteLines = _lines()
	assert_eq(lines.general.size(), 11)
	assert_true(lines.general.has("A pigeon raced you there. The pigeon won."))
	var map: CityMapDef = CityMap.load_default()
	for id: StringName in AREAS:
		assert_false(_area_line(map, id).is_empty(), "%s has its own line" % String(id))
	assert_eq(_area_line(map, &"pinewood"), "The road turned to gravel, then to mud, then to trees.")
	assert_eq(_area_line(map, &"old_town"), "Back on the high street. The florist waved.")


func test_the_pick_is_deterministic() -> void:
	var lines: CommuteLines = _lines()
	var map: CityMapDef = CityMap.load_default()
	for day: int in range(1, 40):
		for id: StringName in AREAS:
			var first: String = lines.pick(day, id, _area_line(map, id))
			assert_false(first.is_empty())
			assert_eq(lines.pick(day, id, _area_line(map, id)), first, "same day and place, same line")


func test_the_pick_never_repeats_the_previous_line() -> void:
	var lines: CommuteLines = _lines()
	var map: CityMapDef = CityMap.load_default()
	for id: StringName in AREAS:
		var previous: String = ""
		for day: int in range(1, 200):
			var line: String = lines.pick(day, id, _area_line(map, id), previous)
			assert_ne(line, previous, "day %d to %s repeated a line" % [day, String(id)])
			previous = line


func test_the_lines_vary_and_the_destination_line_comes_up() -> void:
	var lines: CommuteLines = _lines()
	var map: CityMapDef = CityMap.load_default()
	var seen: Dictionary[String, bool] = {}
	var own: String = _area_line(map, &"seafront")
	var own_count: int = 0
	for day: int in range(1, 121):
		var line: String = lines.pick(day, &"seafront", own)
		seen[line] = true
		own_count += 1 if line == own else 0
	assert_true(seen.size() >= 8, "a month of trips is not one joke (%d kinds)" % seen.size())
	assert_true(own_count >= 10, "the Seafront's gull turns up (%d times)" % own_count)
	# A general line from elsewhere never names another place's joke.
	assert_false(seen.has(_area_line(map, &"pinewood")))


func test_a_single_line_still_answers_and_no_lines_give_nothing() -> void:
	var one: CommuteLines = CommuteLines.new()
	one.general = PackedStringArray(["Only one."])
	assert_eq(one.pick(3, &"a", "", "Only one."), "Only one.", "nothing else to pick")
	assert_eq(CommuteLines.new().pick(3, &"a", ""), "")
