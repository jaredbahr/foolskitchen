class_name ErrorCounter
extends Logger
## Counts engine and script errors (push_error, runtime script errors) so the
## test runner can fail a test that errored, even if its asserts passed.
## Logger callbacks can come from any thread, hence the mutex.

var _mutex := Mutex.new()
var _count: int = 0


func count() -> int:
	_mutex.lock()
	var c := _count
	_mutex.unlock()
	return c


func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_mutex.lock()
	_count += 1
	_mutex.unlock()
