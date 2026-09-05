extends Node2D
class_name Defender
## Visual is either a real sprite (if GameData.DEFENDER_STATS[type].sprite is set)
## or the flat-color circle placeholder — everything else (stats, targeting,
## damage) is unaffected either way. Idle breathe/wiggle is code-driven rather
## than a second near-duplicate art frame, applied to Visual so the HP label
## stays put.

enum State { IDLE, ENGAGED }

var type: int
var hp: float
var max_hp: float
var power: float
var base_power: float
var attack_rate: float
var cooldown: float = 0.0
var range_slots: int
var lane: Lane = null
var slot_index: int = -1
var state: int = State.IDLE
var aura_slow: float = 0.0  # e.g. Mast Cell: 0.20 = -20% enemy move speed in range
var aura_power_buff: float = 0.0  # e.g. Helper T: 0.25 = +25% power to one nearest defender in range
var aura_mark_damage: float = 0.0  # e.g. Dendritic: 0.25 = enemies in range take +25% damage from everyone
var power_multiplier: float = 1.0  # reset and reapplied each tick by Lane._apply_auras (Helper T's target)
var devour_on_kill: bool = false  # e.g. Macrophage: only play the attack anim on an actual kill

const TARGET_SPRITE_DIAMETER: float = 84.0

@onready var visual: Node2D = $Visual
@onready var body: CircleShape = $Visual/Body
@onready var sprite: AnimatedSprite2D = $Visual/Sprite
@onready var hp_label: Label = $HPLabel
@onready var aura_ring: AuraRing = $AuraRing

var _has_attack_animation: bool = false


func setup(t: int) -> void:
	type = t
	var stats: Dictionary = GameData.DEFENDER_STATS[t]
	hp = stats.hp
	max_hp = stats.hp
	base_power = stats.power
	power = stats.power
	attack_rate = stats.attack_rate
	range_slots = stats.range
	aura_slow = stats.get("aura_slow", 0.0)
	aura_power_buff = stats.get("aura_power_buff", 0.0)
	aura_mark_damage = stats.get("aura_mark_damage", 0.0)
	devour_on_kill = stats.get("devour_on_kill", false)

	var anim: Dictionary = SpriteAnimator.build(sprite, stats, TARGET_SPRITE_DIAMETER)
	if anim.has_sprite:
		body.visible = false
		_has_attack_animation = anim.has_attack
		sprite.animation_finished.connect(_on_sprite_animation_finished)
	else:
		body.color = stats.color
		body.visible = true

	if aura_slow > 0.0 or aura_power_buff > 0.0 or aura_mark_damage > 0.0:
		aura_ring.visible = true
		aura_ring.base_color = stats.color

	_update_label()
	SpriteAnimator.start_idle_breathe(visual)


func play_attack(is_kill: bool) -> void:
	if not _has_attack_animation:
		return
	if devour_on_kill and not is_kill:
		return  # Macrophage: only animate the bite on the swallow, not every poke
	sprite.play("attack")


func _on_sprite_animation_finished() -> void:
	if sprite.animation == "attack":
		sprite.play("idle")


func set_aura_radius(px: float) -> void:
	aura_ring.radius = px


func set_aura_active(is_active: bool) -> void:
	aura_ring.set_active(is_active)


func set_buffed(is_buffed: bool) -> void:
	# Visual tell for "this one is currently getting Helper T's +25% power" —
	# a warm gold tint on the whole visual, not just a number changing.
	visual.modulate = Color(1.25, 1.12, 0.7) if is_buffed else Color.WHITE


func _update_label() -> void:
	hp_label.text = "%s\n%d/%d" % [GameData.defender_name(type), int(ceil(hp)), int(max_hp)]


func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0:
		die()
	else:
		_update_label()


func die() -> void:
	if lane:
		lane.on_defender_killed(self)
	queue_free()
