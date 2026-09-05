extends Button
class_name ResourceOrb
## PvZ-style falling "sun" analog: spawns above the board, drifts down to a
## resting height, sits there clickable for a while, then fades out if
## ignored. This is the primary RP income now — passive regen (see main.gd)
## is just a small trickle/safety net, not the main loop.

signal collected(amount: int)
signal expired()  # fired when it fades out uncollected, so the caller's tracking array stays in sync

@export var amount: int = 15
@export var fall_target_y: float = 220.0
@export var fall_speed: float = 90.0
@export var lifetime_after_landing: float = 6.0
@export var fade_duration: float = 0.6

# Roughly 65% of a placed defender's on-board diameter (Defender.
# TARGET_SPRITE_DIAMETER = 84) — small enough to clearly read as a pickup
# rather than a same-scale cell.
const ORB_DIAMETER: float = 55.0

var _landed: bool = false
var _life_timer: float = 0.0

@onready var body: TextureRect = $Body


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(ORB_DIAMETER, ORB_DIAMETER)
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	pressed.connect(_on_pressed)


func _process(delta: float) -> void:
	if not _landed:
		position.y += fall_speed * delta
		if position.y >= fall_target_y:
			position.y = fall_target_y
			_landed = true
		return

	_life_timer += delta
	if _life_timer >= lifetime_after_landing:
		var fade_t: float = (_life_timer - lifetime_after_landing) / fade_duration
		modulate.a = clampf(1.0 - fade_t, 0.0, 1.0)
		if modulate.a <= 0.0:
			expired.emit()
			queue_free()


func _on_pressed() -> void:
	collected.emit(amount)
	SFX.play_place()
	queue_free()
