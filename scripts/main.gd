extends Node2D
## Level 1 playable slice: 3 parallel lanes (spec's "vessels/tissue channels",
## spawner picks randomLane() per 2.8), data-driven LevelConfig spawner
## (spec 2.1/2.8), RP economy, click-to-place. UI is placeholder Controls,
## not final layout. GameData.LEVELS already has a Level 2 entry (Virus mix)
## for when we're ready to build that out — just not exposed in UI right now
## since we're focused on Level 1.

@onready var lanes: Array[Lane] = [$Lane1, $Lane2, $Lane3]
@onready var rp_label: Label = $UI/RPLabel
@onready var health_bar: ProgressBar = $UI/HealthBar
@onready var status_label: Label = $UI/StatusLabel
@onready var selected_label: Label = $UI/SelectedLabel
@onready var level_label: Label = $UI/LevelLabel
@onready var field_note_label: Label = $UI/FieldNoteLabel
@onready var intro_layer: CanvasLayer = $IntroLayer
@onready var start_button: Button = $IntroLayer/Panel/StartButton
@onready var game_over_layer: CanvasLayer = $GameOverLayer
@onready var game_over_title: Label = $GameOverLayer/Panel/TitleLabel
@onready var game_over_subtitle: Label = $GameOverLayer/Panel/SubtitleLabel
@onready var retry_button: Button = $GameOverLayer/Panel/RetryButton
@onready var preview_aura_ring: AuraRing = $PreviewAuraRing

var rp: float = 50.0
var rp_cap: float = 150.0
var rp_regen: float = 5.0

var body_health: float = 100.0
var max_body_health: float = 100.0

var selected_type: int = GameData.DefenderType.NEUTROPHIL

var current_level_id: int = 1
var level_config: Dictionary = {}

var level_elapsed: float = 0.0
var time_since_spawn: float = 0.0
var game_over: bool = false

const BURST_INTERVAL: float = 15.0  # synchronized wave: one enemy per lane at once, on top of the trickle
var time_since_burst: float = 0.0

var slot_buttons: Array = []

# Level Efficiency Rating inputs (spec 2.9), reset per _load_level.
var leaked_damage: float = 0.0
var defenders_lost: int = 0
var total_damage_dealt: float = 0.0
var total_overkill: float = 0.0


func _ready() -> void:
	for l in lanes:
		l.body_health_lost.connect(_on_body_health_lost)
		l.defender_lost.connect(_on_defender_lost)
		l.damage_dealt.connect(_on_damage_dealt)
		l.kill_scored.connect(_on_kill_scored)
	health_bar.max_value = max_body_health
	health_bar.value = body_health

	# One entry per recruitable defender — adding a new one later is a single
	# line here (plus its button node in Main.tscn), not five scattered edits.
	var defender_buttons: Array = [
		[$UI/NeutrophilButton, GameData.DefenderType.NEUTROPHIL],
		[$UI/MacrophageButton, GameData.DefenderType.MACROPHAGE],
		[$UI/ComplementButton, GameData.DefenderType.COMPLEMENT],
		[$UI/MastCellButton, GameData.DefenderType.MAST_CELL],
		[$UI/NKCellButton, GameData.DefenderType.NK_CELL],
		[$UI/HelperTButton, GameData.DefenderType.HELPER_T],
		[$UI/DendriticButton, GameData.DefenderType.DENDRITIC],
	]
	for entry in defender_buttons:
		var btn: Button = entry[0]
		var type: int = entry[1]
		btn.pressed.connect(_select_type.bind(type))
		btn.tooltip_text = GameData.defender_tooltip(type)

	$UI/Level1Button.pressed.connect(_load_level.bind(1))
	retry_button.pressed.connect(_load_level.bind(1))
	start_button.pressed.connect(_on_start_pressed)

	_create_slot_buttons()
	game_over = true  # paused behind the intro popup until Start is pressed
	intro_layer.visible = true


func _on_start_pressed() -> void:
	intro_layer.visible = false
	_load_level(1)


func _load_level(level_id: int) -> void:
	current_level_id = level_id
	level_config = GameData.LEVELS[level_id]
	rp = level_config.starting_rp
	body_health = max_body_health
	health_bar.value = body_health
	level_elapsed = 0.0
	time_since_spawn = 0.0
	time_since_burst = 0.0
	game_over = false
	status_label.text = ""
	field_note_label.visible = false
	preview_aura_ring.visible = false
	game_over_layer.visible = false
	level_label.text = "Level %d: %s" % [level_id, level_config.name]

	leaked_damage = 0.0
	defenders_lost = 0
	total_damage_dealt = 0.0
	total_overkill = 0.0

	for l in lanes:
		l.reset()

	_update_rp_label()
	_update_selected_label()


func _create_slot_buttons() -> void:
	# Invisible hit-area, no text/border — a soft ring shows on hover instead,
	# honestly previewing the outcome of a click before it happens: bright
	# white = placeable, dim red = blocked (occupied, or can't afford the
	# currently selected type), rather than only reacting after the fact.
	var empty_style := StyleBoxEmpty.new()
	var ok_style := StyleBoxFlat.new()
	ok_style.bg_color = Color(1, 1, 1, 0.14)
	ok_style.set_corner_radius_all(50)
	ok_style.set_border_width_all(2)
	ok_style.border_color = Color(1, 1, 1, 0.5)
	var blocked_style := StyleBoxFlat.new()
	blocked_style.bg_color = Color(0.9, 0.2, 0.2, 0.14)
	blocked_style.set_corner_radius_all(50)
	blocked_style.set_border_width_all(2)
	blocked_style.border_color = Color(0.9, 0.3, 0.3, 0.55)
	var hover_styles: Dictionary = {"ok": ok_style, "blocked": blocked_style}

	for l in lanes:
		for i in range(l.slot_count):
			var btn := Button.new()
			btn.text = ""
			btn.custom_minimum_size = Vector2(100, 100)
			btn.focus_mode = Control.FOCUS_NONE
			btn.flat = true
			for state in ["normal", "hover", "pressed", "disabled"]:
				btn.add_theme_stylebox_override(state, empty_style)
			var top_left: Vector2 = l.slot_to_screen(i) - Vector2(50, 50)
			btn.position = top_left
			btn.pressed.connect(_on_slot_pressed.bind(l, i))
			btn.mouse_entered.connect(_on_slot_hover.bind(l, i, btn, hover_styles))
			btn.mouse_exited.connect(_on_slot_unhover.bind(btn, empty_style))
			add_child(btn)
			slot_buttons.append(btn)


func _on_slot_hover(l: Lane, i: int, btn: Button, hover_styles: Dictionary) -> void:
	var stats: Dictionary = GameData.DEFENDER_STATS[selected_type]
	var placeable: bool = l.can_place(i) and rp >= stats.cost
	btn.add_theme_stylebox_override("normal", hover_styles.ok if placeable else hover_styles.blocked)

	# Preview an aura defender's actual coverage before spending RP on it —
	# shown for any open slot regardless of affordability, since seeing the
	# shape doesn't require being able to place it right now.
	var has_aura: bool = stats.get("aura_slow", 0.0) > 0.0 \
		or stats.get("aura_power_buff", 0.0) > 0.0 \
		or stats.get("aura_mark_damage", 0.0) > 0.0
	if has_aura and l.can_place(i):
		preview_aura_ring.position = l.slot_to_screen(i)
		preview_aura_ring.radius = stats.range * l.slot_spacing
		preview_aura_ring.base_color = stats.color
		preview_aura_ring.set_active(true)
		preview_aura_ring.visible = true


func _on_slot_unhover(btn: Button, empty_style: StyleBox) -> void:
	btn.add_theme_stylebox_override("normal", empty_style)
	preview_aura_ring.visible = false


func _select_type(type: int) -> void:
	selected_type = type
	_update_selected_label()


func _update_selected_label() -> void:
	var cost: int = GameData.DEFENDER_STATS[selected_type].cost
	selected_label.text = "Selected: %s (%d RP)" % [GameData.defender_name(selected_type), cost]


func _on_slot_pressed(l: Lane, i: int) -> void:
	if game_over:
		return
	var occupant: Defender = l.slots[i]
	if occupant != null:
		_flash_status("Can't place here — occupied by %s." % GameData.defender_name(occupant.type))
		return
	var cost: int = GameData.DEFENDER_STATS[selected_type].cost
	if rp < cost:
		_flash_status("Not enough RP — need %d, have %d." % [cost, int(rp)])
		return
	var placed: Defender = l.place_defender(i, selected_type)
	if placed == null:
		# Shouldn't happen given the checks above, but guard against ever
		# silently charging RP for a placement that didn't actually happen.
		_flash_status("Couldn't place there — try a different slot.")
		return
	rp -= cost
	status_label.text = ""
	_update_rp_label()
	SFX.play_place()


func _flash_status(text: String) -> void:
	# Every caller here represents a blocked action (occupied slot, can't
	# afford it, etc.) — one sound cue covers all of them.
	SFX.play_invalid()
	status_label.text = text
	get_tree().create_timer(2.5).timeout.connect(func():
		if status_label.text == text:
			status_label.text = ""
	)


func _process(delta: float) -> void:
	if game_over:
		return

	rp = min(rp_cap, rp + rp_regen * delta)
	_update_rp_label()

	level_elapsed += delta
	var interval: float = max(
		level_config.interval_floor,
		level_config.base_interval - level_config.interval_decay * level_elapsed
	)
	time_since_spawn += delta
	if level_elapsed < level_config.duration and time_since_spawn >= interval:
		time_since_spawn = 0.0
		var target_lane: Lane = lanes[randi() % lanes.size()]
		_spawn_into(target_lane, GameData.weighted_random_enemy(level_config.weights))

	time_since_burst += delta
	if level_elapsed < level_config.duration and time_since_burst >= BURST_INTERVAL:
		time_since_burst = 0.0
		for l in lanes:
			_spawn_into(l, GameData.weighted_random_enemy(level_config.weights))

	if body_health <= 0:
		_end_game(false)
	elif level_elapsed >= level_config.duration and _all_lanes_clear():
		_end_game(true)


const CLUMP_CHANCE: float = 0.15  # rare chance a group spawns nearly on top of itself instead of staggered

func _spawn_into(l: Lane, enemy_type: int) -> void:
	# Some enemies (e.g. Staph Cluster) spawn as a group instead of one at a
	# time — normally staggered so they arrive as a tight pack, not stacked
	# exactly on top of each other, but occasionally (real clumping, after
	# all) they land nearly overlapping.
	var group_size: int = GameData.ENEMY_STATS[enemy_type].get("spawn_group", 1)
	var stagger: float = 0.4
	if group_size > 1 and randf() < CLUMP_CHANCE:
		stagger = 0.05
	for i in range(group_size):
		l.spawn_enemy(enemy_type, i * stagger)


func _all_lanes_clear() -> bool:
	for l in lanes:
		if not l.enemies.is_empty():
			return false
	return true


func _on_body_health_lost(amount: float) -> void:
	body_health = max(0, body_health - amount)
	health_bar.value = body_health
	leaked_damage += amount


func _on_defender_lost() -> void:
	defenders_lost += 1


func _on_damage_dealt(amount: float, overkill: float) -> void:
	total_damage_dealt += amount
	total_overkill += overkill


func _on_kill_scored(defender_type: int, enemy_type: int) -> void:
	var chance: float = 0.10 + SaveData.grade_bonus(SaveData.last_level_grade)
	if randf() < chance:
		SaveData.add_stack(defender_type, enemy_type)
		if SaveData.mark_note_seen(defender_type):
			_show_field_note(GameData.FIELD_NOTES.get(defender_type, ""))


func _show_field_note(text: String) -> void:
	if text.is_empty():
		return
	field_note_label.text = "Field Note: " + text
	field_note_label.visible = true
	get_tree().create_timer(6.0).timeout.connect(func(): field_note_label.visible = false)


func _update_rp_label() -> void:
	rp_label.text = "RP: %d / %d" % [int(rp), int(rp_cap)]


func _compute_efficiency_grade() -> Dictionary:
	# Spec 2.9. overkillWastedPercent = what fraction of all damage dealt was
	# spent past a kill's actual HP requirement.
	var overkill_percent: float = 0.0
	if total_damage_dealt > 0.0:
		overkill_percent = 100.0 * total_overkill / total_damage_dealt
	var score: float = 100.0 \
		- (2.0 * leaked_damage) \
		- (5.0 * defenders_lost) \
		- (0.3 * overkill_percent)
	score = clampf(score, 0.0, 100.0)
	var grade: String = "C"
	if score >= 90.0:
		grade = "S"
	elif score >= 75.0:
		grade = "A"
	elif score >= 55.0:
		grade = "B"
	return {"score": score, "grade": grade}


func _end_game(won: bool) -> void:
	game_over = true
	if won:
		var result: Dictionary = _compute_efficiency_grade()
		game_over_title.text = "LEVEL COMPLETE!"
		game_over_subtitle.text = "Score: %d/100" % int(round(result.score))
		SaveData.last_level_grade = result.grade
		SaveData.save_game()
		SFX.play_win()
	else:
		game_over_title.text = "BODY HEALTH DEPLETED"
		game_over_subtitle.text = "The infection got through. Try again?"
		SFX.play_lose()
	game_over_layer.visible = true
