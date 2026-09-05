extends Node2D
## Level 1 playable slice, PvZ-flavored: 5 straight lanes, data-driven
## LevelConfig spawner (spec 2.1/2.8) with a calm trickle + periodic
## telegraphed "wave" burst, RP economy driven mainly by clicking falling
## ResourceOrbs (a small passive trickle is just a safety net), icon-based
## defender selection. GameData.LEVELS already has a Level 2 entry (Virus
## mix) for when we're ready to build that out — just not exposed in UI yet.

@onready var lanes: Array[Lane] = [$Lane1, $Lane2, $Lane3, $Lane4, $Lane5]
@onready var rp_label: Label = $UI/RPLabel
@onready var health_bar: ProgressBar = $UI/HealthBar
@onready var status_label: Label = $UI/StatusLabel
@onready var selected_label: Label = $UI/SelectedLabel
@onready var level_label: Label = $UI/LevelLabel
@onready var field_note_label: RichTextLabel = $UI/FieldNoteLabel
@onready var intro_layer: CanvasLayer = $IntroLayer
@onready var intro_next_button: Button = $IntroLayer/Panel/StartButton
@onready var intro_dialogue_label: RichTextLabel = $IntroLayer/Panel/RulesLabel
@onready var doctor_sprite: TextureRect = $IntroLayer/DoctorSprite
@onready var game_over_layer: CanvasLayer = $GameOverLayer
@onready var game_over_title: RichTextLabel = $GameOverLayer/Panel/TitleLabel
@onready var game_over_subtitle: RichTextLabel = $GameOverLayer/Panel/SubtitleLabel
@onready var retry_button: Button = $GameOverLayer/Panel/RetryButton
@onready var preview_aura_ring: AuraRing = $PreviewAuraRing
@onready var defender_bar: VBoxContainer = $UI/DefenderBar

var rp: float = 50.0
var rp_cap: float = 150.0
var rp_regen: float = 1.5  # small trickle/safety net — orbs (see below) are the main income now

const ORB_SCENE: PackedScene = preload("res://scenes/ResourceOrb.tscn")
const ORB_INTERVAL: float = 8.0
var time_since_orb: float = 0.0
var active_orbs: Array = []

var defender_cards: Array = []  # [{"btn": Button, "cost": int}, ...] — built once in _build_defender_bar()

# Intro dialogue (spec: doctor greets the player over 3 lines, "Next" advances
# each one, and the final "Next" click both closes the intro and starts the
# level — there's no separate "Start" button/label).
const DOCTOR_LINES: Array[String] = [
	"[i]Oh good, you're here.[/i] Hey buddy — it's quite [b]bloody[/b] in here, isn't it?",
	"So. My patient thought climbing a tree was a great way to impress his girlfriend. [b]Bold strategy.[/b] Cut his hand wide open, infection strolled right in, and now — congratulations — [i]you're[/i] the only thing standing between him and being single forever.",
	"[b]Good luck.[/b] [i]Try not to lose him.[/i] No pressure.",
]
var intro_line_index: int = 0

# Typewriter reveal for the current line, done via RichTextLabel's own
# visible_characters (bbcode-aware — it counts glyphs, not raw string index,
# so a tag like [b] never gets sliced in half mid-reveal the way a plain
# String.substr() would). The mouth only animates while a character is
# actively still appearing (see _update_doctor_talk_cycle), and rests closed
# once the full line is on screen — without that gate she was flapping her
# mouth nonstop the whole time a line just sat there waiting for a click,
# which read as a nervous tic instead of "talking."
const DOCTOR_CHARS_PER_SECOND: float = 32.0
var _intro_reveal_chars: float = 0.0

const DOCTOR_IDLE_TEXTURE: Texture2D = preload("res://art/characters/doctor_idle.png")
const DOCTOR_TALK_TEXTURE: Texture2D = preload("res://art/characters/doctor_talk.png")
const DOCTOR_TALK_FRAME_TIME: float = 0.28
var _doctor_talk_timer: float = 0.0
var _doctor_mouth_open: bool = false

# One entry per recruitable defender. Level 1's whole roster; adding a new
# one later is a single line here (no new Main.tscn node needed — the icon
# button is built at runtime in _build_defender_bar()).
const DEFENDER_ROSTER: Array = [
	GameData.DefenderType.NEUTROPHIL,
	GameData.DefenderType.MACROPHAGE,
	GameData.DefenderType.COMPLEMENT,
	GameData.DefenderType.MAST_CELL,
	GameData.DefenderType.NK_CELL,
	GameData.DefenderType.HELPER_T,
	GameData.DefenderType.DENDRITIC,
	GameData.DefenderType.STEM_CELL,
]

var body_health: float = 100.0
var max_body_health: float = 100.0

var selected_type: int = GameData.DefenderType.NEUTROPHIL

var current_level_id: int = 1
var level_config: Dictionary = {}

var level_elapsed: float = 0.0
var time_since_spawn: float = 0.0
var game_over: bool = false
var game_over_won: bool = false  # set by _end_game() — lets tests check outcome without parsing display copy/flavor text

## --- Wave-scripted levels (level_config.has("waves"), see GameData.LEVELS) ---
var wave_index: int = 0
var trickle_active: bool = false
var trickle_interval: float = 3.6
var time_since_trickle: float = 0.0
var final_wave_fired: bool = false

## --- Fallback for levels without a "waves" schedule (e.g. Level 2 for now) ---
const BURST_INTERVAL: float = 18.0
const WAVE_WARNING_LEAD: float = 2.5
var time_since_burst: float = 0.0
var wave_warning_shown: bool = false

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
		l.resource_produced.connect(_on_resource_produced)
	health_bar.max_value = max_body_health
	health_bar.value = body_health

	_build_defender_bar()

	$UI/Level1Button.pressed.connect(_load_level.bind(1))
	retry_button.pressed.connect(_load_level.bind(1))
	intro_next_button.pressed.connect(_on_intro_next_pressed)

	doctor_sprite.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	doctor_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_begin_intro_line(0)

	_create_slot_buttons()
	game_over = true  # paused behind the intro popup until Start is pressed
	intro_layer.visible = true


func _build_defender_bar() -> void:
	# PvZ-style "seed packet": icon + cost badge, no name text — the tooltip
	# still carries full stats/ability text for anyone who hovers. Built at
	# runtime from GameData so a defender without art yet still gets a
	# consistent-looking packet (colored swatch + short name) instead of a
	# missing/blank button.
	for type in DEFENDER_ROSTER:
		var stats: Dictionary = GameData.DEFENDER_STATS[type]
		var btn := Button.new()
		# Width 0 = let the VBoxContainer stretch it to fill the sidebar;
		# height fixed so the card reads as a square icon, not a name-plate.
		btn.custom_minimum_size = Vector2(0, 52)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = GameData.defender_tooltip(type)
		btn.pressed.connect(_select_type.bind(type))

		if stats.has("sprite"):
			var icon_rect := TextureRect.new()
			icon_rect.texture = load(stats.sprite)
			# expand_mode defaults to EXPAND_KEEP_SIZE (draw at native texture
			# size, ignoring the assigned rect) — stretch_mode alone does
			# nothing without this; that combination is what actually scales
			# a ~1250px source image down to fit an 88px icon.
			icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon_rect.offset_left = 2
			icon_rect.offset_top = 2
			icon_rect.offset_right = -2
			icon_rect.offset_bottom = -2
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(icon_rect)
		else:
			# No art yet for this type — the icon itself becomes the colored
			# swatch with its short name, so it still reads as "one icon" and
			# not a leftover name-plate layout.
			var swatch := ColorRect.new()
			swatch.color = stats.color
			swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
			swatch.offset_left = 2
			swatch.offset_top = 2
			swatch.offset_right = -2
			swatch.offset_bottom = -2
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(swatch)
			var name_label := Label.new()
			name_label.text = GameData.defender_name(type)
			name_label.add_theme_font_size_override("font_size", 10)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(name_label)

		# RP cost badge: a small tag pinned to the icon's bottom-right corner
		# (PvZ seed-packet style), not a full-width strip eating into the icon.
		var badge_bg := ColorRect.new()
		badge_bg.color = Color(0, 0, 0, 0.65)
		badge_bg.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge_bg.offset_left = -20
		badge_bg.offset_top = -13
		badge_bg.offset_right = -1
		badge_bg.offset_bottom = -1
		badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(badge_bg)
		var badge := Label.new()
		badge.text = str(int(stats.cost))
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -24
		badge.offset_top = -16
		badge.offset_right = -1
		badge.offset_bottom = -1
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(badge)

		defender_bar.add_child(btn)
		defender_cards.append({"btn": btn, "cost": int(stats.cost)})

	_refresh_defender_bar_affordability()


## PvZ-style: a seed packet you can't afford grays out and stops accepting
## clicks entirely (not just a click that bounces with an error message).
## Called every time RP changes so it's always current.
func _refresh_defender_bar_affordability() -> void:
	for entry in defender_cards:
		var affordable: bool = rp >= entry.cost
		entry.btn.disabled = not affordable
		entry.btn.modulate = Color.WHITE if affordable else Color(0.42, 0.42, 0.42)


## Loads a new line's bbcode into the label with 0 characters revealed yet —
## _update_doctor_talk_cycle() does the actual per-frame reveal.
func _begin_intro_line(index: int) -> void:
	intro_line_index = index
	intro_dialogue_label.text = DOCTOR_LINES[index]
	_intro_reveal_chars = 0.0
	intro_dialogue_label.visible_characters = 0


## Typewriter-reveals the current line via visible_characters (bbcode-safe —
## see the const comment above), and only cel-swaps idle/talk textures while a
## character is actually still appearing — once the full line is on screen she
## settles back to idle and holds still until the next click.
func _update_doctor_talk_cycle(delta: float) -> void:
	var total_chars: int = intro_dialogue_label.get_total_character_count()
	if intro_dialogue_label.visible_characters < total_chars:
		_intro_reveal_chars = min(total_chars, _intro_reveal_chars + DOCTOR_CHARS_PER_SECOND * delta)
		intro_dialogue_label.visible_characters = int(_intro_reveal_chars)

		_doctor_talk_timer += delta
		if _doctor_talk_timer >= DOCTOR_TALK_FRAME_TIME:
			_doctor_talk_timer = 0.0
			_doctor_mouth_open = not _doctor_mouth_open
			doctor_sprite.texture = DOCTOR_TALK_TEXTURE if _doctor_mouth_open else DOCTOR_IDLE_TEXTURE
	elif _doctor_mouth_open:
		_doctor_mouth_open = false
		_doctor_talk_timer = 0.0
		doctor_sprite.texture = DOCTOR_IDLE_TEXTURE


func _on_intro_next_pressed() -> void:
	var total_chars: int = intro_dialogue_label.get_total_character_count()
	if intro_dialogue_label.visible_characters < total_chars:
		# First click while she's still "talking" just finishes the line
		# instantly instead of skipping it — same convention as most VN/dialogue
		# boxes, and it means an eager clicker never loses text.
		_intro_reveal_chars = total_chars
		intro_dialogue_label.visible_characters = total_chars
		return

	if intro_line_index + 1 < DOCTOR_LINES.size():
		_begin_intro_line(intro_line_index + 1)
	else:
		_on_start_pressed()


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
	wave_warning_shown = false
	wave_index = 0
	trickle_active = false
	time_since_trickle = 0.0
	final_wave_fired = false
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
		l.set_process(true)  # undo the freeze _end_game() applies on win/loss
		l.reset()

	for orb in active_orbs.duplicate():
		if is_instance_valid(orb):
			orb.queue_free()
	active_orbs.clear()
	time_since_orb = 0.0
	wave_warning_shown = false

	_update_rp_label()
	_update_selected_label()


func _create_slot_buttons() -> void:
	# PvZ-style lawn grid: every open slot shows a dim persistent ring at rest
	# (not just on hover) so the placement grid is always legible, brightening
	# further on hover to honestly preview the outcome of a click before it
	# happens — white = placeable, red = blocked (occupied, or can't afford it).
	var idle_style := StyleBoxFlat.new()
	idle_style.bg_color = Color(1, 1, 1, 0.10)
	idle_style.set_corner_radius_all(36)
	idle_style.set_border_width_all(3)
	idle_style.border_color = Color(1, 1, 1, 0.45)
	var ok_style := StyleBoxFlat.new()
	ok_style.bg_color = Color(1, 1, 1, 0.22)
	ok_style.set_corner_radius_all(36)
	ok_style.set_border_width_all(3)
	ok_style.border_color = Color(1, 1, 1, 0.7)
	var blocked_style := StyleBoxFlat.new()
	blocked_style.bg_color = Color(0.9, 0.2, 0.2, 0.22)
	blocked_style.set_corner_radius_all(36)
	blocked_style.set_border_width_all(3)
	blocked_style.border_color = Color(0.9, 0.3, 0.3, 0.7)
	var hover_styles: Dictionary = {"ok": ok_style, "blocked": blocked_style, "idle": idle_style}

	for l in lanes:
		for i in range(l.slot_count):
			var btn := Button.new()
			btn.text = ""
			btn.custom_minimum_size = Vector2(72, 72)
			btn.focus_mode = Control.FOCUS_NONE
			# flat = false: we WANT the "normal" (idle, unhovered) stylebox to
			# actually draw all the time — flat = true (the old behavior, back
			# when slots were meant to be invisible until hovered) suppresses
			# the normal-state stylebox entirely regardless of what's assigned
			# to it, which is exactly why a persistent grid needs this off.
			btn.flat = false
			for state in ["normal", "hover", "pressed", "disabled"]:
				btn.add_theme_stylebox_override(state, idle_style)
			var top_left: Vector2 = l.slot_to_screen(i) - Vector2(36, 36)
			btn.position = top_left
			btn.pressed.connect(_on_slot_pressed.bind(l, i))
			btn.mouse_entered.connect(_on_slot_hover.bind(l, i, btn, hover_styles))
			btn.mouse_exited.connect(_on_slot_unhover.bind(btn, idle_style))
			add_child(btn)
			slot_buttons.append(btn)


func _on_slot_hover(l: Lane, i: int, btn: Button, hover_styles: Dictionary) -> void:
	var stats: Dictionary = GameData.DEFENDER_STATS[selected_type]
	var placeable: bool = l.can_place(i) and rp >= stats.cost
	var style: StyleBox = hover_styles.ok if placeable else hover_styles.blocked
	# Godot actually displays the "hover" stylebox while the mouse is over the
	# button (not "normal") — override both so the feedback shows regardless
	# of exactly which state Godot picks at that instant.
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)

	# Preview an aura defender's actual coverage before spending RP on it —
	# shown for any open slot regardless of affordability, since seeing the
	# shape doesn't require being able to place it right now.
	if GameData.defender_stats_has_aura(stats) and l.can_place(i):
		preview_aura_ring.position = l.slot_to_screen(i)
		preview_aura_ring.radius = stats.range * l.slot_spacing
		preview_aura_ring.base_color = stats.color
		preview_aura_ring.set_active(true)
		preview_aura_ring.visible = true


func _on_slot_unhover(btn: Button, idle_style: StyleBox) -> void:
	btn.add_theme_stylebox_override("normal", idle_style)
	btn.add_theme_stylebox_override("hover", idle_style)
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
	if intro_layer.visible:
		_update_doctor_talk_cycle(delta)

	if game_over:
		return

	rp = min(rp_cap, rp + rp_regen * delta)
	_update_rp_label()

	time_since_orb += delta
	if time_since_orb >= ORB_INTERVAL:
		time_since_orb = 0.0
		_spawn_resource_orb()

	level_elapsed += delta
	if level_config.has("waves"):
		_update_wave_schedule(delta)
	else:
		_update_continuous_spawner(delta)

	if body_health <= 0:
		_end_game(false)
	elif level_config.has("waves"):
		if final_wave_fired and _all_lanes_clear():
			_end_game(true)
	elif level_elapsed >= level_config.duration and _all_lanes_clear():
		_end_game(true)


## PvZ-style scripted pacing (see GameData.LEVELS[1].waves for the actual
## schedule): a quiet setup period, a light trickle, a telegraphed huge wave
## hitting every lane at once, a denser breather, then the final wave — the
## level ends once that last wave is fully cleared, not on a fixed timer.
func _update_wave_schedule(delta: float) -> void:
	var waves: Array = level_config.waves
	while wave_index < waves.size() and level_elapsed >= waves[wave_index].t:
		_fire_wave_event(waves[wave_index])
		wave_index += 1

	if trickle_active:
		time_since_trickle += delta
		if time_since_trickle >= trickle_interval:
			time_since_trickle = 0.0
			var target_lane: Lane = lanes[randi() % lanes.size()]
			_spawn_into(target_lane, GameData.weighted_random_enemy(level_config.weights))


func _fire_wave_event(event: Dictionary) -> void:
	match event.type:
		"trickle":
			trickle_active = true
			trickle_interval = event.interval
			time_since_trickle = 0.0
		"warning":
			status_label.text = event.text
		"burst":
			trickle_active = false  # a later "trickle" event (if scripted) resumes it
			status_label.text = ""
			for l in lanes:
				for i in range(int(event.per_lane)):
					_spawn_into(l, GameData.weighted_random_enemy(level_config.weights))
			if event.get("final", false):
				final_wave_fired = true


## Old continuous decay-and-burst model — kept for any level without a
## "waves" schedule (currently Level 2, not yet exposed in the UI).
func _update_continuous_spawner(delta: float) -> void:
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
	if not wave_warning_shown and time_since_burst >= BURST_INTERVAL - WAVE_WARNING_LEAD:
		wave_warning_shown = true
		status_label.text = "A wave is approaching!"
	if level_elapsed < level_config.duration and time_since_burst >= BURST_INTERVAL:
		time_since_burst = 0.0
		wave_warning_shown = false
		status_label.text = ""
		for l in lanes:
			_spawn_into(l, GameData.weighted_random_enemy(level_config.weights))


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


const AMBIENT_ORB_AMOUNT: int = 15  # matches ResourceOrb's own default; named here since ambient orbs are spawned via _spawn_orb, which requires an explicit amount

func _spawn_resource_orb() -> void:
	var lane_index: int = randi() % lanes.size()
	_spawn_orb(Vector2(randf_range(160.0, 900.0), 0.0), lanes[lane_index].lane_y, AMBIENT_ORB_AMOUNT)


func _on_resource_produced(d: Defender) -> void:
	# Stem Cell: the orb pops up right next to the cell instead of falling
	# from the top — it's produced locally, not ambient — with a small random
	# offset so several Stem Cells' orbs don't perfectly overlap.
	var offset := Vector2(randf_range(-24.0, 24.0), randf_range(-14.0, 14.0))
	var spawn_pos: Vector2 = d.global_position + offset
	_spawn_orb(spawn_pos, spawn_pos.y, d.produces_orb_amount)


func _spawn_orb(start_pos: Vector2, fall_target_y: float, amount: int) -> void:
	var orb: ResourceOrb = ORB_SCENE.instantiate()
	add_child(orb)
	orb.position = start_pos
	orb.fall_target_y = fall_target_y
	orb.amount = amount
	orb.collected.connect(_on_orb_collected.bind(orb))
	orb.expired.connect(_on_orb_expired.bind(orb))
	active_orbs.append(orb)


func _on_orb_collected(amount: int, orb: ResourceOrb) -> void:
	rp = min(rp_cap, rp + amount)
	_update_rp_label()
	active_orbs.erase(orb)


func _on_orb_expired(orb: ResourceOrb) -> void:
	# An uncollected orb frees itself without ever emitting `collected` — this
	# is what keeps active_orbs from accumulating dangling references to it.
	active_orbs.erase(orb)


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
	var full_text: String = "[b]🔬 Field Note:[/b] [i]%s[/i]" % text
	field_note_label.text = full_text
	field_note_label.visible = true
	# Guarded like _flash_status: without this, a timer armed by one note
	# could hide a *different*, newer note shown after a quick level restart.
	get_tree().create_timer(6.0).timeout.connect(func():
		if field_note_label.text == full_text:
			field_note_label.visible = false
	)


func _update_rp_label() -> void:
	rp_label.text = "RP: %d / %d" % [int(rp), int(rp_cap)]
	_refresh_defender_bar_affordability()


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


## Grade -> {color, flavor line}. Keeps the doctor's "dating market" joke from
## the intro running through to the payoff instead of dropping it the moment
## the level actually starts.
const GRADE_FLAVOR: Dictionary = {
	"S": {"color": "#f2d94e", "line": "Flawless. He owes you a best-man speech."},
	"A": {"color": "#8ee08e", "line": "Great work — the immune system thanks you."},
	"B": {"color": "#7fc7e8", "line": "He'll live. Barely. Might want to rethink tree-climbing."},
	"C": {"color": "#e8a15c", "line": "Scraped through. Please never do that again."},
}


func _end_game(won: bool) -> void:
	game_over = true
	game_over_won = won
	# Stop combat resolution outright — game_over alone only gates spawning
	# (see the checks below in _process), but Lane._process() drives its own
	# movement/attacks every frame regardless, so without this, enemies kept
	# advancing and defenders kept fighting behind the game-over popup.
	for l in lanes:
		l.set_process(false)
	if won:
		var result: Dictionary = _compute_efficiency_grade()
		var flavor: Dictionary = GRADE_FLAVOR.get(result.grade, GRADE_FLAVOR.C)
		game_over_title.text = "[center][b]🎉 PATIENT SAVED![/b][/center]"
		game_over_subtitle.text = "[center]Grade [b][color=%s]%s[/color][/b] — %d/100\n[i]%s[/i][/center]" % \
			[flavor.color, result.grade, int(round(result.score)), flavor.line]
		SaveData.last_level_grade = result.grade
		SaveData.save_game()
		SFX.play_win()
	else:
		game_over_title.text = "[center][b]💀 INFECTION WINS[/b][/center]"
		game_over_subtitle.text = "[center]He's cancelling the date. Again?[/center]"
		SFX.play_lose()
	game_over_layer.visible = true
