class_name TestGameData
extends RefCounted
## Pure-logic tests for the GameData autoload — no scene tree needed.

static func run(t: TestFramework) -> void:
	_test_type_multiplier(t)
	_test_weighted_random_enemy(t)
	_test_names_and_tooltip(t)


static func _test_type_multiplier(t: TestFramework) -> void:
	t.check_eq(GameData.get_multiplier(GameData.DefenderType.NEUTROPHIL, GameData.EnemyType.BACTERIA), 2.0,
		"Neutrophil vs Bacteria = 2.0 (spec 2.4)")
	t.check_eq(GameData.get_multiplier(GameData.DefenderType.NK_CELL, GameData.EnemyType.VIRUS), 2.0,
		"NK Cell vs Virus = 2.0 (the 'right tool' hook Milestone 3 is built around)")
	t.check_eq(GameData.get_multiplier(GameData.DefenderType.NEUTROPHIL, GameData.EnemyType.VIRUS), 0.5,
		"Neutrophil vs Virus = 0.5 (devour-types should underperform here)")
	t.check_eq(GameData.get_multiplier(9999, 9999), 1.0,
		"Unknown defender/enemy pairing defaults to 1.0, not a crash or 0")
	# STAPH/STREP were added later and deliberately mirror the BACTERIA column
	# (Level 1's lesson is "any defender roughly works", not a new counter).
	t.check_eq(
		GameData.get_multiplier(GameData.DefenderType.NEUTROPHIL, GameData.EnemyType.STAPH),
		GameData.get_multiplier(GameData.DefenderType.NEUTROPHIL, GameData.EnemyType.BACTERIA),
		"Staph Cluster mirrors Bacteria's multiplier row"
	)


static func _test_weighted_random_enemy(t: TestFramework) -> void:
	var only_bacteria: Dictionary = {GameData.EnemyType.BACTERIA: 1.0}
	var always_bacteria: bool = true
	for i in range(20):
		if GameData.weighted_random_enemy(only_bacteria) != GameData.EnemyType.BACTERIA:
			always_bacteria = false
			break
	t.check(always_bacteria, "weighted_random_enemy with a single 1.0-weight entry always returns that type")

	var weights: Dictionary = {GameData.EnemyType.STAPH: 0.5, GameData.EnemyType.STREP: 0.5}
	var staph_count: int = 0
	var samples: int = 2000
	for i in range(samples):
		if GameData.weighted_random_enemy(weights) == GameData.EnemyType.STAPH:
			staph_count += 1
	t.check_almost(float(staph_count) / samples, 0.5, 0.05,
		"50/50 weights land roughly balanced over %d samples" % samples)


static func _test_names_and_tooltip(t: TestFramework) -> void:
	t.check_eq(GameData.defender_name(GameData.DefenderType.NEUTROPHIL), "Neutrophil", "defender_name: known type")
	t.check_eq(GameData.defender_name(9999), "Unknown", "defender_name: unknown type falls back")
	t.check_eq(GameData.enemy_name(GameData.EnemyType.STAPH), "Staph Cluster", "enemy_name: known type")

	var tooltip: String = GameData.defender_tooltip(GameData.DefenderType.MACROPHAGE)
	t.check(tooltip.find("Macrophage") >= 0, "defender_tooltip includes the defender's name")
	t.check(tooltip.find("HP") >= 0, "defender_tooltip includes the stat line")
