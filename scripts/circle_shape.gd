extends Node2D
class_name CircleShape
## Reusable placeholder visual: a filled circle, used for every defender,
## enemy, and the core so cells actually read as cells instead of squares.

@export var radius: float = 40.0
@export var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()

@export var outline_color: Color = Color(0, 0, 0, 0.35)
@export var outline_width: float = 2.0


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
	if outline_width > 0.0:
		draw_arc(Vector2.ZERO, radius - outline_width * 0.5, 0, TAU, 32, outline_color, outline_width, true)
