extends Node2D
class_name Lane
## One lane: slotCount discrete positions (0 = core, slot_count = spawn edge),
## plus every enemy currently travelling it. Implements spec 2.5 (combat
## resolution) and the per-frame version of the 2.6 main loop.
##
## Gameplay position (position_units, slot_index) is still a plain 0..slot_count
## number — none of the combat math below changed. What changed is how that
## number becomes a screen position: instead of x = origin + index * spacing
## (a straight row), it's sampled off a wavy Curve2D, so the lane reads as an
## organic vessel/tissue channel instead of a grid line. Swap _build_curve()
## for whatever path you want (or drive it from art later) without touching
## anything else in this file.

signal body_health_lost(amount: float)
signal defender_lost()
signal damage_dealt(amount: float, overkill: float)  # for the Level Efficiency Rating (spec 2.9)
signal kill_scored(defender_type: int, enemy_type: int)  # for Memory Cells (spec 2.9)

@export var slot_count: int = 6
@export var slot_spacing: float = 140.0
@export var slot_origin_x: float = 120.0
@export var lane_y: float = 300.0
@export var wave_amplitude: float = 45.0
@export var wave_frequency: float = 1.0   # full sine cycles along the lane's length
@export var wave_phase: float = 0.0       # radians; vary per-lane so lanes don't all bend identically

var slots: Array = []  # Defender or null, size slot_count
var enemies: Array = []  # Enemy

var defender_scene: PackedScene = preload("res://scenes/Defender.tscn")
var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")

var _curve: Curve2D
var _curve_length: float
var _tess: PackedVector2Array
var _shading_lines: Array[Line2D] = []  # soft gradient rim, built once in _build_curve()

const SHADING_LAYERS: int = 4  # per side; more layers = smoother falloff, at the cost of more draw calls

@onready var core: Node2D = $Core
@onready var vessel_outline: Line2D = $VesselOutline
@onready var vessel_fill: Line2D = $VesselFill
@onready var vessel_lining_top: Line2D = $VesselLiningTop
@onready var vessel_lining_bottom: Line2D = $VesselLiningBottom


func _ready() -> void:
	slots.resize(slot_count)
	for i in range(slot_count):
		slots[i] = null
	_build_curve()
	core.position = slot_to_screen(-0.5)  # sits just behind slot 0, still on-screen, no overlap with a placed defender


func _build_curve() -> void:
	# Sample a sine wave from the spawn edge (index = slot_count) to just past
	# the core (index = -1), then fit a smooth Curve2D through those points
	# so the path curves rather than kinking at each sample.
	var index_max: float = slot_count
	var index_min: float = -1.0
	var segments: int = 8
	var pts: Array[Vector2] = []
	for s in range(segments + 1):
		var t: float = float(s) / segments
		var index: float = lerp(index_max, index_min, t)
		var x: float = slot_origin_x + index * slot_spacing
		var y: float = lane_y + wave_amplitude * sin(t * wave_frequency * TAU + wave_phase)
		pts.append(Vector2(x, y))

	_curve = Curve2D.new()
	for i in range(pts.size()):
		var p: Vector2 = pts[i]
		var prev: Vector2 = pts[max(i - 1, 0)]
		var next: Vector2 = pts[min(i + 1, pts.size() - 1)]
		var tangent: Vector2 = (next - prev) * 0.18
		_curve.add_point(p, -tangent, tangent)
	_curve_length = _curve.get_baked_length()

	_tess = _curve.tessellate(5, 4)
	vessel_outline.points = _tess
	vessel_fill.points = _tess

	# Slight organic width variation instead of a perfectly uniform tube —
	# real vessels bulge and narrow a little along their length.
	var width_curve := Curve.new()
	width_curve.add_point(Vector2(0.0, 1.0))
	width_curve.add_point(Vector2(0.3, 0.9))
	width_curve.add_point(Vector2(0.55, 1.08))
	width_curve.add_point(Vector2(0.8, 0.92))
	width_curve.add_point(Vector2(1.0, 1.0))
	vessel_outline.width_curve = width_curve
	vessel_fill.width_curve = width_curve

	var normals: Array[Vector2] = _compute_normals(_tess)

	# Inner lining: marks the actual placement channel boundary.
	var half_width: float = vessel_outline.width * 0.5 - 6.0
	var lining_top: PackedVector2Array = PackedVector2Array()
	var lining_bottom: PackedVector2Array = PackedVector2Array()
	for i in range(_tess.size()):
		lining_top.append(_tess[i] + normals[i] * half_width)
		lining_bottom.append(_tess[i] - normals[i] * half_width)
	vessel_lining_top.points = lining_top
	vessel_lining_bottom.points = lining_bottom

	_build_tube_shading(normals)


## Smooth, lit-cylinder look: a stack of translucent strokes on each side of
## the centerline, offset along the path's own per-point normal (so the rim
## tracks the tube's bends rather than a straight light source cutting across
## a curved lane), each layer wider/fainter than the last — the same "stacked
## soft falloff" trick AuraRing uses for its glow, just following a line
## instead of a circle. Reads as a smooth gradient despite being flat colors.
func _build_tube_shading(normals: Array[Vector2]) -> void:
	for line in _shading_lines:
		line.queue_free()
	_shading_lines.clear()

	var insert_index: int = core.get_index()
	var sides: Array = [
		{"sign": 1.0, "color": Color(0.32, 0.08, 0.1)},   # shadow, underside of the tube
		{"sign": -1.0, "color": Color(0.95, 0.62, 0.55)},  # highlight, lit side of the tube
	]
	for side in sides:
		for layer in range(SHADING_LAYERS):
			var t: float = float(layer) / (SHADING_LAYERS - 1)  # 0 = outer (wide/faint), 1 = inner (narrow/strong)
			var line := Line2D.new()
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			line.antialiased = true
			line.width = lerp(30.0, 8.0, t)
			var c: Color = side.color
			c.a = lerp(0.08, 0.26, t)
			line.default_color = c
			var offset_amount: float = lerp(20.0, 7.0, t)
			var pts := PackedVector2Array()
			for i in range(_tess.size()):
				pts.append(_tess[i] + normals[i] * side.sign * offset_amount)
			line.points = pts
			add_child(line)
			move_child(line, insert_index)
			insert_index += 1
			_shading_lines.append(line)


func _compute_normals(points: PackedVector2Array) -> Array[Vector2]:
	var normals: Array[Vector2] = []
	for i in range(points.size()):
		var prev: Vector2 = points[max(i - 1, 0)]
		var next: Vector2 = points[min(i + 1, points.size() - 1)]
		var tangent: Vector2 = (next - prev).normalized()
		normals.append(Vector2(-tangent.y, tangent.x))
	return normals


func _flash_core() -> void:
	# Visual feedback for a leak: the thing being defended visibly takes the hit.
	var tween: Tween = create_tween()
	core.scale = Vector2(1.3, 1.3)
	tween.tween_property(core, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_CUBIC)


func slot_to_screen(index: float) -> Vector2:
	# index runs slot_count (spawn edge, t=0) down to -1 (just past core, t=1) —
	# matches the domain _build_curve() laid the curve out over.
	var t: float = (slot_count - index) / (slot_count + 1.0)
	return _curve.sample_baked(clampf(t, 0.0, 1.0) * _curve_length)


func reset() -> void:
	for e in enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	for i in range(slot_count):
		if slots[i] != null:
			slots[i].queue_free()
			slots[i] = null


func can_place(index: int) -> bool:
	return index >= 0 and index < slot_count and slots[index] == null


func place_defender(index: int, type: int) -> Defender:
	if not can_place(index):
		return null
	var d: Defender = defender_scene.instantiate()
	add_child(d)
	d.setup(type)
	d.lane = self
	d.slot_index = index
	d.position = slot_to_screen(index)
	if d.aura_slow > 0.0 or d.aura_power_buff > 0.0 or d.aura_mark_damage > 0.0:
		d.set_aura_radius(d.range_slots * slot_spacing)
	slots[index] = d
	return d


func spawn_enemy(type: int, start_offset: float = 0.0) -> Enemy:
	# start_offset staggers a group spawn (e.g. Staph Cluster) just behind the
	# spawn edge so they arrive as a tight pack instead of perfectly overlapping.
	var start_pos: float = float(slot_count) + start_offset
	var e: Enemy = enemy_scene.instantiate()
	add_child(e)
	e.setup(type, start_pos)
	e.lane = self
	e.position = slot_to_screen(start_pos)
	enemies.append(e)
	return e


func on_defender_killed(d: Defender) -> void:
	defender_lost.emit()
	if d.slot_index >= 0 and d.slot_index < slot_count and slots[d.slot_index] == d:
		slots[d.slot_index] = null
	for e in enemies:
		if e.engaged_defender == d:
			e.engaged_defender = null
			e.state = Enemy.State.MOVING


func on_enemy_killed(e: Enemy) -> void:
	enemies.erase(e)


func _process(delta: float) -> void:
	_apply_auras()
	_update_movement(delta)
	_update_defender_attacks(delta)
	_update_enemy_attacks(delta)


func _apply_auras() -> void:
	# Reset every per-tick modifier first, then re-derive from whoever is
	# currently in range — every aura effect (slow, power buff, damage mark)
	# must lapse the instant its source or target leaves range, not persist.
	for e in enemies:
		if is_instance_valid(e):
			e.slow_multiplier = 1.0
			e.mark_multiplier = 1.0
			e.set_marked(false)
	for i in range(slot_count):
		var d: Defender = slots[i]
		if d != null:
			d.power_multiplier = 1.0
			d.set_buffed(false)

	for i in range(slot_count):
		var d: Defender = slots[i]
		if d == null:
			continue
		if d.aura_slow > 0.0:
			_apply_mast_cell_slow(d, i)
		if d.aura_power_buff > 0.0:
			_apply_helper_t_buff(d, i)
		if d.aura_mark_damage > 0.0:
			_apply_dendritic_mark(d, i)

	for i in range(slot_count):
		if slots[i] != null:
			slots[i].power = slots[i].base_power * slots[i].power_multiplier


func _apply_mast_cell_slow(d: Defender, slot_i: int) -> void:
	var hit_any: bool = false
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.position_units >= slot_i and e.position_units <= slot_i + d.range_slots:
			e.slow_multiplier *= (1.0 - d.aura_slow)
			hit_any = true
	d.set_aura_active(hit_any)


func _apply_helper_t_buff(d: Defender, slot_i: int) -> void:
	# Spec: "+25% Power to one adjacent defender" — the single nearest
	# occupied slot within range, not everyone in range.
	var target: Defender = _find_nearest_defender(slot_i, d.range_slots, d)
	if target:
		target.power_multiplier = 1.0 + d.aura_power_buff
		target.set_buffed(true)
	d.set_aura_active(target != null)


func _apply_dendritic_mark(d: Defender, slot_i: int) -> void:
	var hit_any: bool = false
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.position_units >= slot_i and e.position_units <= slot_i + d.range_slots:
			e.mark_multiplier = max(e.mark_multiplier, 1.0 + d.aura_mark_damage)
			e.set_marked(true)
			hit_any = true
	d.set_aura_active(hit_any)


func _find_nearest_defender(from_index: int, max_range: int, exclude: Defender) -> Defender:
	for dist in range(1, max_range + 1):
		for idx in [from_index - dist, from_index + dist]:
			if idx >= 0 and idx < slot_count and slots[idx] != null and slots[idx] != exclude:
				return slots[idx]
	return null


func _update_movement(delta: float) -> void:
	for e in enemies.duplicate():
		if not is_instance_valid(e) or e.state != Enemy.State.MOVING:
			continue
		var blocking_index: int = clampi(int(floor(e.position_units)), 0, slot_count - 1)
		var blocker: Defender = slots[blocking_index]
		if blocker != null and e.position_units <= blocking_index + 1.0:
			e.state = Enemy.State.ENGAGED
			e.engaged_defender = blocker
			continue
		e.position_units -= e.effective_move_speed() * delta
		e.position = slot_to_screen(e.position_units)
		if e.position_units <= 0.0:
			body_health_lost.emit(e.contact_damage)
			_flash_core()
			SFX.play_leak()
			enemies.erase(e)
			e.queue_free()


func _update_defender_attacks(delta: float) -> void:
	for i in range(slot_count):
		var d: Defender = slots[i]
		if d == null or d.power <= 0.0:
			continue
		d.cooldown -= delta
		if d.cooldown > 0.0:
			continue
		var target: Enemy = _find_target_for_defender(d, i)
		if target:
			var mult: float = GameData.get_multiplier(d.type, target.type)
			var memory_mult: float = SaveData.power_multiplier(d.type, target.type)
			var dmg: float = max(1, round(d.power * mult * memory_mult * target.mark_multiplier))
			var hp_before: float = target.hp
			target.take_damage(dmg)
			# Overkill = damage beyond what was needed to land the killing blow;
			# 0 for any non-lethal hit since hp_before > dmg then.
			var overkill: float = max(0.0, dmg - hp_before)
			damage_dealt.emit(dmg, overkill)
			var is_kill: bool = hp_before <= dmg
			if is_kill:
				kill_scored.emit(d.type, target.type)
				SFX.play_kill()
			else:
				SFX.play_hit()
			d.play_attack(is_kill)
			d.cooldown = 1.0 / d.attack_rate


func _update_enemy_attacks(delta: float) -> void:
	for e in enemies.duplicate():
		if not is_instance_valid(e):
			continue
		if e.state == Enemy.State.ENGAGED and e.engaged_defender != null and is_instance_valid(e.engaged_defender):
			e.cooldown -= delta
			if e.cooldown <= 0.0:
				var dmg: float = max(1, round(e.power))
				e.engaged_defender.take_damage(dmg)
				e.play_attack()
				e.cooldown = 1.0 / e.attack_rate


func _find_target_for_defender(d: Defender, slot_i: int) -> Enemy:
	var best: Enemy = null
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.position_units >= slot_i and e.position_units <= slot_i + d.range_slots:
			if best == null or e.position_units < best.position_units:
				best = e
	return best
