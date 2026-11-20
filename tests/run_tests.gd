extends SceneTree
## Minimal headless test runner (no addon needed).
##   Godot_console.exe --headless --path . -s res://tests/run_tests.gd [-- filter]
## Exit code is the number of failed tests. Script errors during a test
## (null access, bad calls...) count as failures via an engine Logger.


class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var catcher := ErrorCatcher.new()

func _initialize() -> void:
	# One frame first, so the root viewport is in the tree and scene tests
	# (e.g. test_xr_windows) can add nodes and use global transforms.
	await process_frame
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var files := DirAccess.get_files_at("res://tests")
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	OS.add_logger(catcher)
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		catcher.errors.clear()
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			print("  FAIL  %s: does not compile" % file)
			for e in catcher.errors:
				print("        " + e)
			failed += 1
			total += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (file + ":" + name).contains(filter):
				continue
			catcher.errors.clear()
			var tc: TestCase = script.new()
			tc.current_test = name
			if tc.has_method("before_each"):
				tc.before_each()
			var started := Time.get_ticks_msec()
			tc.call(name)
			total += 1
			for e in catcher.errors:
				tc.failures.append("script error: " + e)
			var ms := Time.get_ticks_msec() - started
			if tc.failures.is_empty():
				print("  ok    %s:%s (%d ms)" % [file, name, ms])
			else:
				failed += 1
				print("  FAIL  %s:%s" % [file, name])
				for f in tc.failures:
					print("        " + f)
	print("\n%d tests, %d failed (%.1f s)" % [total, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(failed)
