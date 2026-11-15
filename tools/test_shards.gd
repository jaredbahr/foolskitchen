class_name TestShards
extends RefCounted
## Deals test files to shards by how long each took, not by its place in the
## sorted list. Dealing by position (`index % shards`) meant one new file moved
## every later file to the next shard, and the heavy session tests could all
## land together: #530 added one 52-second file and the hosted job went from
## 13 minutes to its 25-minute limit.
##
## Heaviest file first, each to the shard that is lightest so far, ties broken
## by path, so every shard process works out the same split. A file with no
## recorded time counts as the median, so a new test is placed sensibly before
## anyone re-measures. Times come from `tools/test_durations.json`
## (`run_tests.gd -- --write-durations` rewrites it; only the proportions
## matter, so the machine it was measured on does not).

const DURATIONS_PATH: String = "res://tools/test_durations.json"
const FALLBACK_MS: float = 1000.0


## The files of each shard, in sorted order within a shard.
static func assign(files: PackedStringArray, durations: Dictionary, shards: int) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	var count: int = maxi(1, shards)
	for index: int in count:
		result.append(PackedStringArray())
	var unknown: float = median_ms(files, durations)
	var order: Array[String] = []
	for path: String in files:
		order.append(path)
	order.sort_custom(func(a: String, b: String) -> bool:
		var cost_a: float = cost_ms(a, durations, unknown)
		var cost_b: float = cost_ms(b, durations, unknown)
		return a < b if is_equal_approx(cost_a, cost_b) else cost_a > cost_b)
	var loads: Array[float] = []
	loads.resize(count)
	loads.fill(0.0)
	for path: String in order:
		var lightest: int = 0
		for index: int in range(1, count):
			if loads[index] < loads[lightest]:
				lightest = index
		result[lightest].append(path)
		loads[lightest] += cost_ms(path, durations, unknown)
	for index: int in count:
		result[index].sort()
	return result


## The recorded time of one file, or `unknown` when it has none.
static func cost_ms(path: String, durations: Dictionary, unknown: float) -> float:
	var value: Variant = durations.get(path)
	if (value is float or value is int) and float(value) > 0.0:
		return float(value)
	return unknown


## The median recorded time among `files`; the fallback when none is recorded.
static func median_ms(files: PackedStringArray, durations: Dictionary) -> float:
	var known: Array[float] = []
	for path: String in files:
		var value: Variant = durations.get(path)
		if (value is float or value is int) and float(value) > 0.0:
			known.append(float(value))
	if known.is_empty():
		return FALLBACK_MS
	known.sort()
	return known[known.size() / 2]


## The summed recorded time of each shard, for reporting.
static func loads_ms(assignment: Array[PackedStringArray], durations: Dictionary) -> Array[float]:
	var all: PackedStringArray = []
	for shard: PackedStringArray in assignment:
		all.append_array(shard)
	var unknown: float = median_ms(all, durations)
	var out: Array[float] = []
	for shard: PackedStringArray in assignment:
		var total: float = 0.0
		for path: String in shard:
			total += cost_ms(path, durations, unknown)
		out.append(total)
	return out


## The recorded times; empty when the file is missing or unreadable, which
## makes every file count the same and the split still valid.
static func load_durations(path: String = DURATIONS_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
