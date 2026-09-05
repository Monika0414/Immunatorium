extends Node2D
class_name WoundShape
## Procedural placeholder for the wound the level is set in (spec: "Skin —
## The Wound") — a torn-skin opening sitting where the lanes actually spawn
## enemies from (index = slot_count, the right edge), so the fiction has a
## visual anchor before real art exists. Layered jagged polygons, same
## "stacked soft shapes" trick used elsewhere in this project, no art needed.
## Drawn behind the lanes (added early in Main's scene tree) so the vessels
## visually emerge from it. Swap for real art by hiding this node — nothing
## else depends on it.

@export var center: Vector2 = Vector2(1020, 430)
@export var radius: float = 200.0

const RNG_SEED: int = 1337  # fixed so the jagged silhouette is stable, not regenerated/flickering


func _draw() -> void:
	draw_colored_polygon(_jagged_circle(radius, 14, 0.18), Color(0.16, 0.05, 0.05, 0.9))
	draw_colored_polygon(_jagged_circle(radius * 0.82, 14, 0.16), Color(0.42, 0.1, 0.1, 0.92))
	draw_colored_polygon(_jagged_circle(radius * 0.6, 12, 0.22), Color(0.6, 0.17, 0.15, 0.95))
	draw_colored_polygon(_jagged_circle(radius * 0.32, 10, 0.25), Color(0.72, 0.24, 0.19, 0.9))


func _jagged_circle(r: float, point_count: int, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	for i in range(point_count):
		var angle: float = (float(i) / point_count) * TAU
		var r_i: float = r * (1.0 - jitter + rng.randf() * jitter * 2.0)
		pts.append(center + Vector2(cos(angle), sin(angle)) * r_i)
	return pts
