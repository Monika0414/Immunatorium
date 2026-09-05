extends Control
class_name IconGlyph
## Flat vector glyph drawn via Godot's draw API — no image asset needed. Used
## for HUD chrome buttons (pause/play/restart) where a crisp, scalable icon is
## all that's wanted; deliberately plain/flat rather than matching the painted
## character art, since these are functional UI controls, not world elements.

enum Icon { PAUSE, PLAY, RESTART }

@export var icon: Icon = Icon.PAUSE:
	set(value):
		icon = value
		queue_redraw()
@export var glyph_color: Color = Color.WHITE:
	set(value):
		glyph_color = value
		queue_redraw()


func _draw() -> void:
	match icon:
		Icon.PAUSE:
			_draw_pause()
		Icon.PLAY:
			_draw_play()
		Icon.RESTART:
			_draw_restart()


func _draw_pause() -> void:
	var bar_w: float = size.x * 0.24
	var bar_h: float = size.y * 0.7
	var gap: float = size.x * 0.16
	var top: float = (size.y - bar_h) * 0.5
	var cx: float = size.x * 0.5
	draw_rect(Rect2(cx - gap * 0.5 - bar_w, top, bar_w, bar_h), glyph_color)
	draw_rect(Rect2(cx + gap * 0.5, top, bar_w, bar_h), glyph_color)


func _draw_play() -> void:
	# Slightly right-shifted so the triangle's visual center of mass lands in
	# the middle of the button rect (a symmetric triangle drawn edge-to-edge
	# looks off-center to the eye — its "point" is lighter than its base).
	var pad_x: float = size.x * 0.26
	var pad_y: float = size.y * 0.16
	var pts := PackedVector2Array([
		Vector2(pad_x, pad_y),
		Vector2(pad_x, size.y - pad_y),
		Vector2(size.x - pad_x * 0.6, size.y * 0.5),
	])
	draw_colored_polygon(pts, glyph_color)


func _draw_restart() -> void:
	# A ~290-degree arc (gap at the upper-left) plus an arrowhead at its
	# leading end reads as a standard clockwise "refresh/restart" glyph.
	# Angles: 0=right, 90=down, 180=left, -90=up (Godot's y-down convention),
	# so sweeping start=-90 -> end=205 (increasing angle) draws a clockwise
	# arc from the top, around through the right and bottom, ending up on
	# the upper-left — near the top of the gap rather than down at the
	# midline, which is what kept making the arrowhead read as too low.
	var center: Vector2 = size * 0.5
	var radius: float = min(size.x, size.y) * 0.32
	var stroke: float = size.x * 0.1
	var start_angle: float = deg_to_rad(-90.0)
	var end_angle: float = deg_to_rad(205.0)
	draw_arc(center, radius, start_angle, end_angle, 24, glyph_color, stroke, true)

	# Tangent direction at end_angle is the derivative of (cos, sin)*radius
	# w.r.t. angle — this points "forward" along the arc's sweep direction, so
	# the arrowhead visually continues the arc instead of pointing backward.
	# The head is centered ON the tip (half ahead, half behind) rather than
	# trailing fully behind it, so it hugs the arc instead of sagging below it.
	var tip: Vector2 = center + Vector2(cos(end_angle), sin(end_angle)) * radius
	var travel_dir: Vector2 = Vector2(-sin(end_angle), cos(end_angle))
	var perp: Vector2 = Vector2(-travel_dir.y, travel_dir.x)
	var head_len: float = size.x * 0.16
	var head_half_width: float = size.x * 0.14
	tip += travel_dir * head_len * 0.5
	var back_center: Vector2 = tip - travel_dir * head_len
	var pts := PackedVector2Array([
		tip,
		back_center + perp * head_half_width,
		back_center - perp * head_half_width,
	])
	draw_colored_polygon(pts, glyph_color)
