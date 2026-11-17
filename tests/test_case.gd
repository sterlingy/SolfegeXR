class_name TestCase
extends RefCounted
## Base class for tests. Put files named tests/test_*.gd that extend TestCase,
## with methods named test_*. Run all of them with:
##   Godot_console.exe --headless --path . -s res://tests/run_tests.gd
## Optional: before_each() runs before every test method.

var failures: PackedStringArray = []
var current_test := ""


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


func assert_true(cond: bool, msg := "expected true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg := "expected false") -> void:
	if cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("expected %s, got %s %s" % [var_to_str(expected), var_to_str(actual), msg])


func assert_near(actual: float, expected: float, tolerance: float, msg := "") -> void:
	if is_nan(actual) or absf(actual - expected) > tolerance:
		fail("expected %s ± %s, got %s %s" % [expected, tolerance, actual, msg])
