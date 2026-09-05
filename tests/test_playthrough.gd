class_name TestPlaythrough
extends RefCounted
## A real, automated playthrough of Level 1 using the actual Main scene and
## actual game logic (not a hand-rolled simulation) — a simple but honest bot:
## fill each lane's front slot with a Neutrophil as soon as RP allows, then
## backfill other slots, auto-collect every orb the instant it appears. If
## even this bare-minimum, no-strategy defense can't clear the level, that's
## a real balance problem, not a "skill issue".

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const TIME_SCALE: float = 25.0  # fast-forward: let the real engine drive every node's own _process(), just compressed
const MAX_REAL_MS: int = 10000  # 10 real seconds * 25x = up to 250 simulated seconds — well past the scripted final wave


static func run(t: TestFramework, tree: SceneTree) -> void:
	var main: Node2D = MAIN_SCENE.instantiate()
	tree.root.add_child(main)
	await tree.process_frame  # let _ready() run (lanes build, defender bar builds, etc.)

	main._on_start_pressed()  # same as clicking Start — skips the intro popup
	main.selected_type = GameData.DefenderType.NEUTROPHIL

	# Calling main._process(dt) manually here would only ever advance Main's
	# own state — each Lane child has its own _process() override that the
	# real engine calls automatically every frame, completely independent of
	# Main's. A tight synchronous loop never yields control back to the
	# engine, so that automatic dispatch never happens and nothing in any
	# lane would ever move, attack, or die. Fast-forwarding real engine time
	# instead means every node gets ticked exactly like normal gameplay,
	# just compressed.
	var original_time_scale: float = Engine.time_scale
	Engine.time_scale = TIME_SCALE
	var start_ms: int = Time.get_ticks_msec()
	while not main.game_over and (Time.get_ticks_msec() - start_ms) < MAX_REAL_MS:
		_bot_tick(main)
		await tree.process_frame
	Engine.time_scale = original_time_scale

	t.check(main.game_over, "Level reaches an end state within the simulation budget (didn't stall)")
	if main.game_over:
		var won: bool = main.game_over_title.text == "LEVEL COMPLETE!"
		t.check(won, "A bare-minimum bot (Neutrophils only, no strategy) clears Level 1 (Body Health: %.0f/100, got: '%s')" \
			% [main.body_health, main.game_over_title.text])
		if won:
			t.check(main.body_health > 20.0,
				"Wins with a real margin, not a photo finish (%.0f/100 Body Health left)" % main.body_health)

	main.queue_free()


static func _bot_tick(main: Node2D) -> void:
	var cost: int = GameData.DEFENDER_STATS[GameData.DefenderType.NEUTROPHIL].cost
	# Auto-collect every orb currently on screen — represents a player who's
	# actually paying attention, not an AFK one.
	for orb in main.active_orbs.duplicate():
		if is_instance_valid(orb):
			orb._on_pressed()

	if main.rp < cost:
		return
	# Front slot of an undefended lane first...
	for l in main.lanes:
		if l.can_place(0):
			main._on_slot_pressed(l, 0)
			return
	# ...then backfill anywhere else open, spending RP as fast as it regenerates.
	for l in main.lanes:
		for i in range(l.slot_count):
			if l.can_place(i):
				main._on_slot_pressed(l, i)
				return
