extends TestCase
## The web build of Godot leaves out some classes (OpenXR, GDExtension-only
## ones). A script that names one in code fails to load in browsers only,
## which desktop tests can't catch, so check the source text instead.

const NOT_IN_WEB := ["OpenXRInterface", "OpenXRAPIExtension", "OpenXRExtensionWrapper", "YinNative"]


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out


func test_no_web_missing_classes_in_code() -> void:
	var strings := RegEx.create_from_string(r'"[^"]*"')
	var words := RegEx.create_from_string(r"\b(" + "|".join(NOT_IN_WEB) + r")\b")
	for path in _scripts("res://scripts"):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			# Ignore comments and string literals (ClassDB.class_exists("YinNative") is fine).
			var code := strings.sub(lines[i], '""', true).split("#")[0]
			var m := words.search(code)
			if m:
				fail("%s:%d names %s, which the web build doesn't have" % [path.get_file(), i + 1, m.get_string(1)])


func test_catches_a_bad_line() -> void:
	var words := RegEx.create_from_string(r"\b(" + "|".join(NOT_IN_WEB) + r")\b")
	assert_true(words.search("var x: OpenXRInterface") != null)
	assert_true(words.search("var x: XRInterface") == null)
