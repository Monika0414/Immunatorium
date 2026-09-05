extends Node2D
class_name Enemy
## Visual is either a real sprite (if GameData.ENEMY_STATS[type].sprite is set)
## or the flat-color circle placeholder — everything else (stats, targeting,
## damage) is unaffected either way. Same AnimatedSprite2D pattern as Defender:
## idle loops, attack plays on a real hit, die plays once on the killing blow
## and only then is the node actually freed.

enum State { MOVING, ENGAGED }

const TARGET_SPRITE_DIAMETER: float = 68.0

var type: int
var hp: float
var max_hp: float
var power: float
var attack_rate: float
var cooldown: float = 0.0
var base_move_speed: float
var slow_multiplier: float = 1.0  # reset and reapplied each tick by Lane._apply_auras
var mark_multiplier: float = 1.0  # reset each tick; Dendritic sets this above 1.0 while in range
var contact_damage: float
var lane: Lane = null
var position_units: float  # distance from core, in slot units (0 = core)
var state: int = State.MOVING
var engaged_defender: Defender = null

var _has_attack_animation: bool = false
var _has_die_animation: bool = false
var _dying: bool = false

@onready var visual: Node2D = $Visual
@onready var body: CircleShape = $Visual/Body
@onready var sprite: AnimatedSprite2D = $Visual/Sprite
@onready var hp_label: Label = $HPLabel


func effective_move_speed() -> float:
	return base_move_speed * slow_multiplier


func set_marked(is_marked: bool) -> void:
	# Visual tell for "Dendritic has this one tagged, it's taking +25% from
	# everyone" — a cool cyan tint, distinct from Helper T's warm gold buff tint.
	visual.modulate = Color(0.65, 1.0, 1.05) if is_marked else Color.WHITE


func setup(t: int, start_pos: float) -> void:
	type = t
	var stats: Dictionary = GameData.ENEMY_STATS[t]
	hp = stats.hp
	max_hp = stats.hp
	power = stats.power
	attack_rate = stats.attack_rate
	base_move_speed = stats.move_speed
	contact_damage = stats.contact_damage
	position_units = start_pos

	var anim: Dictionary = SpriteAnimator.build(sprite, stats, TARGET_SPRITE_DIAMETER)
	if anim.has_sprite:
		body.visible = false
		_has_attack_animation = anim.has_attack
		_has_die_animation = anim.has_die
		sprite.animation_finished.connect(_on_sprite_animation_finished)
	else:
		body.color = stats.color
		body.visible = true

	_update_label()
	SpriteAnimator.start_idle_breathe(visual)


func play_attack() -> void:
	if _has_attack_animation and not _dying:
		sprite.play("attack")


func _on_sprite_animation_finished() -> void:
	if sprite.animation == "attack":
		sprite.play("idle")
	elif sprite.animation == "die":
		queue_free()


func _update_label() -> void:
	hp_label.text = "%s\n%d/%d" % [GameData.enemy_name(type), int(ceil(hp)), int(max_hp)]


func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0:
		die()
	else:
		_update_label()


func die() -> void:
	if lane:
		lane.on_enemy_killed(self)
	if _dying:
		return
	_dying = true
	hp_label.visible = false
	if _has_die_animation:
		sprite.play("die")  # queue_free happens in _on_sprite_animation_finished
	else:
		queue_free()
