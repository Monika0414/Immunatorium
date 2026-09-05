class_name SpriteAnimator
extends RefCounted
## Shared AnimatedSprite2D setup for Defender and Enemy. Both use the same
## art convention — a GameData stats dict with an optional "sprite" (idle,
## looping), "attack_sprites" (played once on a landed hit), and "die_sprites"
## (Enemy only, played once on the killing blow) — so the frame-building logic
## lives here instead of being copy-pasted in both scripts.

const ATTACK_FPS: float = 5.0  # e.g. 3 frames / 5fps = 0.6s, comfortably under any attacker's cooldown
const DIE_FPS: float = 2.0


## Builds and plays "idle" on the given sprite from `stats`. Returns which
## optional animations were actually available so the caller can gate its
## own animation-triggering logic (has_attack/has_die).
static func build(sprite: AnimatedSprite2D, stats: Dictionary, target_diameter: float) -> Dictionary:
	if not stats.has("sprite"):
		sprite.visible = false
		return {"has_sprite": false, "has_attack": false, "has_die": false}

	var idle_tex: Texture2D = load(stats.sprite)
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", idle_tex)

	var has_attack: bool = stats.has("attack_sprites")
	if has_attack:
		frames.add_animation("attack")
		frames.set_animation_loop("attack", false)
		# Per-type override: fast attackers (e.g. Complement at 2.5 atk/s) need
		# their animation to finish well inside a much shorter cooldown window
		# than the 5fps default assumes.
		frames.set_animation_speed("attack", stats.get("attack_fps", ATTACK_FPS))
		for path in stats.attack_sprites:
			frames.add_frame("attack", load(path))

	var has_die: bool = stats.has("die_sprites")
	if has_die:
		frames.add_animation("die")
		frames.set_animation_loop("die", false)
		frames.set_animation_speed("die", DIE_FPS)
		for path in stats.die_sprites:
			frames.add_frame("die", load(path))

	sprite.sprite_frames = frames
	sprite.play("idle")
	var scale_factor: float = target_diameter / max(idle_tex.get_width(), idle_tex.get_height())
	sprite.scale = Vector2(scale_factor, scale_factor)
	sprite.visible = true

	return {"has_sprite": true, "has_attack": has_attack, "has_die": has_die}


## A gentle looping squash/stretch on `visual` so anything holding still still
## reads as alive — used for both Defender and Enemy idle states. Never runs
## during "attack"/"die" since those are separate one-shot AnimatedSprite2D
## animations layered on top; this only ever touches `visual.scale`.
static func start_idle_breathe(visual: Node2D) -> void:
	var tween: Tween = visual.create_tween().set_loops()
	tween.tween_property(visual, "scale", Vector2(1.04, 0.96), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(visual, "scale", Vector2(0.97, 1.03), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(visual, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
