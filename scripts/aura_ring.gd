extends Node2D
class_name AuraRing
## Pulsing outline showing an aura defender's effective range — dim and slow
## when idle, brighter and faster when it's actually affecting an enemy this
## tick. Drawn as a sibling of Visual so it doesn't scale with the idle
## breathe/wiggle tween.

@export var radius: float = 100.0
@export var base_color: Color = Color(0.92, 0.55, 0.65)

var active: bool = false
var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta * (3.0 if active else 1.2)
	queue_redraw()


func _draw() -> void:
	var pulse: float = (sin(_t) + 1.0) * 0.5  # 0..1
	var alpha: float = lerp(0.10, 0.22, pulse) + (0.18 if active else 0.0)
	var width: float = 3.0 + (2.0 if active else 0.0)

	# Soft inner glow: stacked circles shrinking toward the center with falling
	# alpha, faking a radial gradient (Godot's draw API has no native one) so
	# the light concentrates near the ring edge and fades toward the middle.
	var glow_layers: int = 6
	for i in range(glow_layers):
		var t: float = float(i) / (glow_layers - 1)  # 0 = at the ring edge, 1 = innermost
		var layer_radius: float = lerp(radius, radius * 0.3, t)
		var layer_alpha: float = alpha * 0.4 * (1.0 - t)
		var glow_c: Color = base_color
		glow_c.a = layer_alpha
		draw_circle(Vector2.ZERO, layer_radius, glow_c)

	var c: Color = base_color
	c.a = alpha
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, c, width, true)


func set_active(is_active: bool) -> void:
	active = is_active
