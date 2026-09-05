extends Node2D
## Headless test runner. Invoke with:
##   godot --headless --path <project> res://tests/TestScene.tscn
## Runs GameData/SaveData unit tests (pure logic) plus a Lane combat
## integration test (real Defender/Enemy scene instances, ticked
## deterministically instead of relying on real time), then prints a summary
## and quits with 0 (all passed) or 1 (something failed) — CI-friendly.

const LANE_SCENE: PackedScene = preload("res://scenes/Lane.tscn")


func _ready() -> void:
	var t := TestFramework.new()

	TestGameData.run(t)
	TestSaveData.run(t)
	await _run_lane_combat_tests(t)
	await TestPlaythrough.run(t, get_tree())

	SFX.stop_all()  # release our own cached AudioStreamWAV resources
	await get_tree().process_frame  # let queue_free()'d nodes finish cleaning up

	# You'll still see "6 ObjectDB instances were leaked at exit" after this —
	# that's AudioServer's own internal playback-object bookkeeping for the
	# streams SFX played during the Lane combat test. It's only released at
	# real engine shutdown, not through any script-reachable API; stop() +
	# clearing our cache (above) is the actual fix on our side, confirmed by
	# testing frame-yields and a wall-clock delay, neither of which changed
	# the count. Benign — not a real leak, doesn't grow, doesn't affect a
	# normal (non-quitting) play session, and doesn't affect this suite's
	# exit code. Don't spend more time chasing it.

	t.print_summary()
	get_tree().quit(0 if t.failed == 0 else 1)


func _run_lane_combat_tests(t: TestFramework) -> void:
	# The damage formula includes SaveData's Memory Cell multiplier — clear it
	# in-memory (not on disk) for the duration so this test's expected numbers
	# don't depend on whatever a real playthrough may have already earned.
	var backup_stacks: Dictionary = SaveData.memory_stacks.duplicate(true)
	SaveData.memory_stacks.clear()

	var lane: Lane = LANE_SCENE.instantiate()
	add_child(lane)
	await get_tree().process_frame  # let Lane's real _ready() run (curve build, slots init)

	# --- Placement ---
	var placed: Defender = lane.place_defender(0, GameData.DefenderType.NEUTROPHIL)
	t.check(placed != null, "place_defender succeeds on an open slot")
	t.check_eq(lane.can_place(0), false, "Slot reads as occupied after placing")
	t.check(lane.place_defender(0, GameData.DefenderType.NEUTROPHIL) == null,
		"place_defender fails (returns null) on an already-occupied slot")

	# --- Combat: Neutrophil (2.0x vs Bacteria, spec 2.4) should kill a
	# Bacteria (32 HP) in exactly 2 hits per spec 2.5's damage formula, with
	# zero overkill since 16 + 16 == 32 exactly.
	var damage_events: Array = []
	var kill_events: Array = []
	lane.damage_dealt.connect(func(amount, overkill): damage_events.append({"amount": amount, "overkill": overkill}))
	lane.kill_scored.connect(func(dtype, etype): kill_events.append([dtype, etype]))

	var enemy: Enemy = lane.spawn_enemy(GameData.EnemyType.BACTERIA)
	enemy.position_units = 1.0  # adjacent to slot 0 — engages immediately
	var expected_dmg: int = int(round(placed.power * GameData.get_multiplier(placed.type, enemy.type)))
	t.check_eq(expected_dmg, 16, "Neutrophil vs Bacteria hits for 16 (8 power x 2.0 multiplier)")

	# Poll enemy.hp, not lane.enemies membership: Bacteria has a die animation,
	# so it now deliberately STAYS in lane.enemies until that animation's
	# animation_finished signal fires (this was bug fix #3 from the code
	# review — the win-check and Lane.reset() were previously able to act on
	# a corpse mid-death-animation). animation_finished is driven by the
	# engine's own per-frame dispatch on AnimatedSprite2D, which a tight
	# synchronous lane._process() loop never triggers (same class of gotcha as
	# queue_free()'s deferred deletion) — so hp is the right thing to poll for
	# "did combat actually resolve", independent of animation/cleanup timing.
	var dt: float = 0.1
	var ticks: int = 0
	while is_instance_valid(enemy) and enemy.hp > 0 and ticks < 200:  # generous ceiling: a real hang shows up as a failure, not a stall
		lane._process(dt)
		ticks += 1
	t.check(is_instance_valid(enemy) and enemy.hp <= 0, "Bacteria dies within a bounded number of ticks")
	t.check(lane.enemies.has(enemy), "Killed enemy stays in lane.enemies until its die animation actually finishes")
	t.check(is_instance_valid(placed) and placed.hp > 0, "Neutrophil survives the exchange (Bacteria is comparatively weak)")

	# Simulate the animation actually finishing (no real engine frames run in
	# this synchronous test) and confirm the deferred cleanup path works.
	enemy._on_sprite_animation_finished()
	t.check(not lane.enemies.has(enemy), "Once the die animation finishes, the enemy is removed from lane.enemies")

	t.check_eq(kill_events.size(), 1, "kill_scored fires exactly once for the kill")
	if kill_events.size() > 0:
		t.check_eq(kill_events[0], [placed.type, GameData.EnemyType.BACTERIA],
			"kill_scored reports the correct defender/enemy types")
	t.check_eq(damage_events.size(), 2, "Exactly 2 damage_dealt events for a 2-hit kill (16+16=32)")
	if damage_events.size() == 2:
		t.check_eq(damage_events[1].overkill, 0.0, "No overkill: 16+16 exactly matches Bacteria's 32 HP")

	lane.reset()

	# --- Leak: an enemy reaching the core with nothing in its way costs Body
	# Health exactly its contact_damage, once.
	var leaked: Array = []
	lane.body_health_lost.connect(func(amount): leaked.append(amount))
	var runner: Enemy = lane.spawn_enemy(GameData.EnemyType.STREP)
	runner.position_units = 0.01
	lane._process(0.1)
	t.check_eq(leaked.size(), 1, "Leak signal fires exactly once")
	if leaked.size() > 0:
		t.check_eq(leaked[0], GameData.ENEMY_STATS[GameData.EnemyType.STREP].contact_damage,
			"Leak damage matches the enemy's contact_damage stat")

	lane.queue_free()
	SaveData.memory_stacks = backup_stacks
