extends SceneTree
## Minimal headless test runner (no addon needed).
##   Godot_console.exe --headless --path . -s res://tests/run_tests.gd [-- filter]
## Exit code is the number of failed tests.

func _initialize() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var files := DirAccess.get_files_at("res://tests")
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var script: GDScript = load("res://tests/" + file)
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (file + ":" + name).contains(filter):
				continue
			var tc: TestCase = script.new()
			tc.current_test = name
			if tc.has_method("before_each"):
				tc.before_each()
			var started := Time.get_ticks_msec()
			tc.call(name)
			total += 1
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
