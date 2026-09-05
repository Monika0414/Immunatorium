extends Node2D
class_name AmbientParticles
## A handful of slow-drifting translucent circles (loose cells/debris) behind
## the lanes. Pure code, no art, purely decorative — no gameplay significance,
## no collision, nothing else in the codebase reads from this. Wraps around
## screen edges so it drifts forever without ever needing to respawn.

@export var particle_count: int = 12
@export var canvas_size: Vector2 = Vector2(1152, 648)
@export var min_radius: float = 4.0
@export var max_radius: float = 15.0
@export var min_speed: float = 4.0
@export var max_speed: float = 13.0
@export var colors: Array[Color] = [
	Color(0.85, 0.55, 0.5),
	Color(0.7, 0.35, 0.35),
	Color(0.9, 0.75, 0.7),
]

var _particles: Array[Dictionary] = []


func _ready() -> void:
	for i in range(particle_count):
		_particles.append(_make_particle())


func _make_particle() -> Dictionary:
	var angle: float = randf() * TAU
	var speed: float = randf_range(min_speed, max_speed)
	return {
		"pos": Vector2(randf() * canvas_size.x, randf() * canvas_size.y),
		"vel": Vector2(cos(angle), sin(angle)) * speed,
		"radius": randf_range(min_radius, max_radius),
		"color": colors[randi() % colors.size()],
		"alpha": randf_range(0.06, 0.16),
		"wobble_phase": randf() * TAU,
	}


func _process(delta: float) -> void:
	for p in _particles:
		p.wobble_phase += delta * 0.5
		p.pos += p.vel * delta + Vector2(0, sin(p.wobble_phase) * 3.0) * delta
		if p.pos.x < -p.radius:
			p.pos.x = canvas_size.x + p.radius
		elif p.pos.x > canvas_size.x + p.radius:
			p.pos.x = -p.radius
		if p.pos.y < -p.radius:
			p.pos.y = canvas_size.y + p.radius
		elif p.pos.y > canvas_size.y + p.radius:
			p.pos.y = -p.radius
	queue_redraw()


func _draw() -> void:
	for p in _particles:
		var c: Color = p.color
		c.a = p.alpha
		draw_circle(p.pos, p.radius, c)
