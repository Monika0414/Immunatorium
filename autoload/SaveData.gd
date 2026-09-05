extends Node
## Persistent cross-level save data: Memory Cell buffs (spec 2.1 MemoryBuff, 2.9).
## Autoloaded as "SaveData".

const SAVE_PATH := "user://savegame.json"

# key "%d_%d" % [defender_type, enemy_type] -> stacks (0-3)
var memory_stacks: Dictionary = {}
var last_level_grade: String = "C"
var seen_notes: Dictionary = {}  # defender_type (as String) -> true, once a field note has shown


func _ready() -> void:
	load_game()


func _key(defender_type: int, enemy_type: int) -> String:
	return "%d_%d" % [defender_type, enemy_type]


func get_stacks(defender_type: int, enemy_type: int) -> int:
	return memory_stacks.get(_key(defender_type, enemy_type), 0)


func add_stack(defender_type: int, enemy_type: int) -> void:
	var key: String = _key(defender_type, enemy_type)
	memory_stacks[key] = min(3, memory_stacks.get(key, 0) + 1)
	save_game()


func power_multiplier(defender_type: int, enemy_type: int) -> float:
	return 1.0 + 0.20 * get_stacks(defender_type, enemy_type)


func mark_note_seen(defender_type: int) -> bool:
	# Returns true the first time this defender's note is shown, false after.
	var key: String = str(defender_type)
	if seen_notes.has(key):
		return false
	seen_notes[key] = true
	save_game()
	return true


func grade_bonus(grade: String) -> float:
	match grade:
		"S": return 0.20
		"A": return 0.15
		"B": return 0.10
		_: return 0.0


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"memory_stacks": memory_stacks,
			"last_level_grade": last_level_grade,
			"seen_notes": seen_notes,
		}))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		memory_stacks = parsed.get("memory_stacks", {})
		last_level_grade = parsed.get("last_level_grade", "C")
		seen_notes = parsed.get("seen_notes", {})
