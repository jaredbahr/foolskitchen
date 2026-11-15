extends TestCase
## The test runner deals files to shards by recorded time (tools/test_shards.gd).


func _files(count: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for index: int in count:
		out.append("res://tests/world/test_%03d.gd" % index)
	return out


## Light files first, then a heavy tail: the shape of the real suite, where the
## long session tests sort last.
func _heavy_tail(files: PackedStringArray, heavy_from: int) -> Dictionary:
	var out: Dictionary = {}
	for index: int in files.size():
		out[files[index]] = 60000 if index >= heavy_from else 1000
	return out


func _spread(loads: Array[float]) -> float:
	return loads.max() - loads.min()


func test_every_file_lands_in_exactly_one_shard_and_the_split_repeats() -> void:
	var files: PackedStringArray = _files(41)
	var durations: Dictionary = _heavy_tail(files, 30)
	var first: Array[PackedStringArray] = TestShards.assign(files, durations, 4)
	var seen: Dictionary = {}
	for shard: PackedStringArray in first:
		for path: String in shard:
			assert_false(seen.has(path), "%s is in two shards" % path)
			seen[path] = true
	assert_eq(seen.size(), files.size(), "every file is in a shard")
	assert_eq(TestShards.assign(files, durations, 4), first, "the same input gives the same split")
	var reversed: PackedStringArray = files.duplicate()
	reversed.reverse()
	assert_eq(TestShards.assign(reversed, durations, 4), first, "the split does not depend on the order files were found in")


func test_shards_stay_level_whatever_the_position_of_the_heavy_files() -> void:
	var files: PackedStringArray = _files(40)
	var durations: Dictionary = _heavy_tail(files, 28)
	var loads: Array[float] = TestShards.loads_ms(TestShards.assign(files, durations, 4), durations)
	assert_true(_spread(loads) <= 60000.0, "no shard is more than one heavy file ahead (loads %s)" % [loads])


## The #530 case: one more file ahead of the heavy tail. Dealing by position
## moved every later file to the next shard; by time, the shards stay level.
func test_one_added_file_does_not_unbalance_the_shards() -> void:
	var files: PackedStringArray = _files(40)
	var durations: Dictionary = _heavy_tail(files, 28)
	var added: PackedStringArray = files.duplicate()
	added.append("res://tests/world/test_014_new.gd")
	added.sort()
	durations["res://tests/world/test_014_new.gd"] = 52000
	var loads: Array[float] = TestShards.loads_ms(TestShards.assign(added, durations, 4), durations)
	assert_true(_spread(loads) <= 60000.0, "the shards are still within one heavy file of each other (loads %s)" % [loads])
	var by_position: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for index: int in added.size():
		by_position[index % 4] += float(durations[added[index]])
	assert_true(_spread(loads) <= _spread(by_position), "never worse than dealing by position (%s against %s)" % [loads, by_position])


func test_a_file_with_no_recorded_time_counts_as_the_median() -> void:
	var files: PackedStringArray = _files(9)
	var durations: Dictionary = {}
	for index: int in 8:
		durations[files[index]] = 1000 * (index + 1)
	assert_eq(TestShards.median_ms(files, durations), 5000.0)
	assert_eq(TestShards.cost_ms(files[8], durations, TestShards.median_ms(files, durations)), 5000.0)
	durations[files[0]] = "not a number"
	assert_eq(TestShards.cost_ms(files[0], durations, 5000.0), 5000.0, "a broken entry is treated as unrecorded")


func test_no_recorded_times_still_gives_a_valid_even_split() -> void:
	var files: PackedStringArray = _files(10)
	var split: Array[PackedStringArray] = TestShards.assign(files, {}, 4)
	var sizes: Array[int] = []
	for shard: PackedStringArray in split:
		sizes.append(shard.size())
	sizes.sort()
	assert_eq(sizes, [2, 2, 3, 3] as Array[int])
	assert_eq(TestShards.assign(files, {}, 1)[0], files, "one shard takes everything, in order")
