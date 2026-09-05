class_name TestSaveData
extends RefCounted
## SaveData is a real autoload that persists to disk — this backs up and
## restores both its in-memory state and the actual save file so running the
## suite can never clobber a real player's save.

static func run(t: TestFramework) -> void:
	var backup_stacks: Dictionary = SaveData.memory_stacks.duplicate(true)
	var backup_grade: String = SaveData.last_level_grade
	var backup_seen: Dictionary = SaveData.seen_notes.duplicate(true)
	var had_file: bool = FileAccess.file_exists(SaveData.SAVE_PATH)
	var backup_file_text: String = ""
	if had_file:
		var f: FileAccess = FileAccess.open(SaveData.SAVE_PATH, FileAccess.READ)
		backup_file_text = f.get_as_text()

	_run_unsafe(t)

	SaveData.memory_stacks = backup_stacks
	SaveData.last_level_grade = backup_grade
	SaveData.seen_notes = backup_seen
	if had_file:
		var out: FileAccess = FileAccess.open(SaveData.SAVE_PATH, FileAccess.WRITE)
		out.store_string(backup_file_text)
	elif FileAccess.file_exists(SaveData.SAVE_PATH):
		DirAccess.open("user://").remove(SaveData.SAVE_PATH.trim_prefix("user://"))


static func _run_unsafe(t: TestFramework) -> void:
	var d: int = GameData.DefenderType.NEUTROPHIL
	var e: int = GameData.EnemyType.STAPH
	SaveData.memory_stacks.clear()
	SaveData.seen_notes.clear()  # mark_note_seen below needs a clean slate, not whatever a real playthrough already saw

	t.check_eq(SaveData.get_stacks(d, e), 0, "No Memory Cell stacks initially")
	t.check_eq(SaveData.power_multiplier(d, e), 1.0, "No stacks = 1.0x power multiplier")

	SaveData.memory_stacks["%d_%d" % [d, e]] = 2
	t.check_almost(SaveData.power_multiplier(d, e), 1.4, 0.001, "2 stacks = +40% power (1 + 0.2*2, spec 2.9)")

	for i in range(5):
		SaveData.add_stack(d, e)
	t.check_eq(SaveData.get_stacks(d, e), 3, "add_stack caps at 3 no matter how many times it's called")
	t.check_almost(SaveData.power_multiplier(d, e), 1.6, 0.001, "3 stacks = +60% power, the spec-documented cap")

	t.check_almost(SaveData.grade_bonus("S"), 0.20, 0.001, "grade_bonus S")
	t.check_almost(SaveData.grade_bonus("A"), 0.15, 0.001, "grade_bonus A")
	t.check_almost(SaveData.grade_bonus("B"), 0.10, 0.001, "grade_bonus B")
	t.check_almost(SaveData.grade_bonus("C"), 0.0, 0.001, "grade_bonus C (and any unrecognized grade)")

	t.check(SaveData.mark_note_seen(d), "mark_note_seen returns true the first time")
	t.check(not SaveData.mark_note_seen(d), "mark_note_seen returns false on every call after the first")
