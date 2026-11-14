class_name TestCase
extends RefCounted
## Base class for unit tests. A test file is tests/**/test_*.gd that extends
## TestCase; every method whose name starts with "test_" is one test.
## Optional hooks: before_each() and after_each().
## Run them all with: bash tools/check.sh  (or tools/run_tests.gd directly).

var _failures: PackedStringArray = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


## Persistence fixtures that jump a morning directly without running service
## have no day-close observation to advance a weekly challenge. Reset only the
## fixture state before that synthetic jump; the next morning then follows the
## supported legacy initialization path with zero fabricated progress.
func reset_weekly_for_synthetic_day_jump(main: Node) -> void:
	if main == null or not is_instance_valid(main):
		return
	if main.get("weekly_challenge") is WeeklyChallengeState:
		main.set("weekly_challenge", WeeklyChallengeState.new())


## Tests of other features that check exact cash after a price change, a
## decor buy or a day's service retire the opening-week chain (#494) first,
## so its goal rewards stay out of their sums. Its own tests never call this.
func retire_opening_week(main: Node) -> void:
	if main == null or not is_instance_valid(main) or not main.get("opening_week") is OpeningWeek:
		return
	main.set("opening_week", OpeningWeek.ended())
	if main.has_method("_refresh_opening_tracker"):
		main.call("_refresh_opening_tracker")


func assert_true(value: bool, msg: String = "") -> void:
	if not value:
		_fail("expected true", msg)


func assert_false(value: bool, msg: String = "") -> void:
	if value:
		_fail("expected false", msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("expected %s, got %s" % [var_to_str(expected), var_to_str(actual)], msg)


func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		_fail("did not expect %s" % var_to_str(unexpected), msg)


func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.0001, msg: String = "") -> void:
	if absf(actual - expected) > tolerance:
		_fail("expected %f (+/- %f), got %f" % [expected, tolerance, actual], msg)


func assert_null(value: Variant, msg: String = "") -> void:
	if value != null:
		_fail("expected null, got %s" % var_to_str(value), msg)


func assert_not_null(value: Variant, msg: String = "") -> void:
	if value == null:
		_fail("expected a value, got null", msg)


func fail(msg: String) -> void:
	_fail("failed", msg)


## Used by the runner. Clears and returns the failures of the last test.
func take_failures() -> PackedStringArray:
	var out := _failures
	_failures = []
	return out


func _fail(what: String, msg: String) -> void:
	_failures.append(what if msg.is_empty() else "%s: %s" % [msg, what])
