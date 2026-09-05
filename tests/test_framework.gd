class_name TestFramework
extends RefCounted
## Minimal homemade assertion helper — no external addon (GUT etc.) required.
## Run the whole suite headlessly:
##   godot --headless --path <project> res://tests/TestScene.tscn
## Exits 0 if everything passed, 1 otherwise, so it's CI-friendly.

var passed: int = 0
var failed: int = 0
var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		failures.append(message)


func check_eq(actual, expected, label: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [label, str(expected), str(actual)])


func check_almost(actual: float, expected: float, tolerance: float, label: String) -> void:
	check(absf(actual - expected) <= tolerance, "%s (expected ~%s ±%s, got %s)" % [label, str(expected), str(tolerance), str(actual)])


func print_summary() -> void:
	print("\n=== TEST RESULTS: %d passed, %d failed ===" % [passed, failed])
	for f in failures:
		print("  FAIL: " + f)
