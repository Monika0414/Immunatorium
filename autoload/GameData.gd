extends Node
## Central data tables: stats, type effectiveness, level configs. Autoloaded as "GameData".
## Milestone 3 scope: Neutrophil, Macrophage, Complement, Mast Cell, NK Cell vs.
## Bacteria + Virus. Full 2.4 type matrix is filled in for all five enemy types
## even where the countering defender isn't implemented yet — harmless now,
## and one less thing to remember when Eosinophil/B Cell/Cytotoxic T land.

enum DefenderType {
	NEUTROPHIL, MACROPHAGE, COMPLEMENT, NK_CELL, EOSINOPHIL,
	B_CELL, HELPER_T, CYTOTOXIC_T, MAST_CELL, DENDRITIC,
	STEM_CELL,  # not in the original spec roster — added as the Sunflower-equivalent economy unit
}

enum EnemyType { BACTERIA, VIRUS, FUNGUS, PARASITE, CANCER, STAPH, STREP }

# hp, power (0 = support unit, no direct damage), attack_rate (atk/s, 0 = none),
# range (slots ahead), cost (RP), color (placeholder art swap point).
const DEFENDER_STATS := {
	DefenderType.NEUTROPHIL: {"hp": 20.0, "power": 8.0, "attack_rate": 1.5, "range": 1, "cost": 25, "color": Color8(235, 220, 80), "sprite": "res://art/defenders/neutrophil_idle.png", "attack_sprites": ["res://art/defenders/neutrophil_attack_1.png"], "devour_on_kill": true},
	DefenderType.MACROPHAGE: {"hp": 50.0, "power": 15.0, "attack_rate": 0.7, "range": 1, "cost": 50, "color": Color8(150, 90, 210), "sprite": "res://art/defenders/macrophage_idle.png", "attack_sprites": ["res://art/defenders/macrophage_attack_1.png", "res://art/defenders/macrophage_attack_2.png", "res://art/defenders/macrophage_attack_3.png"], "devour_on_kill": true},
	DefenderType.COMPLEMENT: {"hp": 10.0, "power": 5.0, "attack_rate": 2.5, "range": 1, "cost": 15, "color": Color8(90, 200, 230), "sprite": "res://art/defenders/complement_idle.png", "attack_sprites": ["res://art/defenders/complement_attack.png"], "attack_fps": 4.0},
	DefenderType.MAST_CELL: {"hp": 15.0, "power": 0.0, "attack_rate": 0.0, "range": 1, "cost": 30, "color": Color8(235, 130, 170), "aura_slow": 0.20, "sprite": "res://art/defenders/mast_cell_idle.png"},
	DefenderType.NK_CELL: {"hp": 25.0, "power": 12.0, "attack_rate": 1.0, "range": 1, "cost": 60, "color": Color8(80, 210, 190), "sprite": "res://art/defenders/nk_cell_idle.png", "attack_sprites": ["res://art/defenders/nk_cell_attack_charge.png", "res://art/defenders/nk_cell_attack_burst.png", "res://art/defenders/nk_cell_attack_release.png"]},
	DefenderType.HELPER_T: {"hp": 20.0, "power": 0.0, "attack_rate": 0.0, "range": 2, "cost": 35, "color": Color8(230, 190, 90), "aura_power_buff": 0.25, "sprite": "res://art/defenders/helper_t_idle.png"},
	DefenderType.DENDRITIC: {"hp": 15.0, "power": 0.0, "attack_rate": 0.0, "range": 2, "cost": 35, "color": Color8(130, 140, 220), "aura_mark_damage": 0.25, "sprite": "res://art/defenders/dendritic_idle.png"},
	# The Sunflower-equivalent: hematopoietic stem cells in bone marrow are the
	# actual biological source of every blood/immune cell, so "this produces
	# more resources over time" has a real basis, not just a game abstraction.
	# Cheap relative to attackers (mirrors Sunflower costing half a Peashooter)
	# to reward early economy investment.
	DefenderType.STEM_CELL: {"hp": 15.0, "power": 0.0, "attack_rate": 0.0, "range": 0, "cost": 30, "color": Color8(190, 220, 90), "produces_orb_interval": 14.0, "produces_orb_amount": 12},
	# Not in DEFENDER_ROSTER yet (main.gd) — spec 2.2 stats filled in now so
	# adding them to the roster later really is "a single line", matching
	# TYPE_MULTIPLIER/DEFENDER_NAMES/DEFENDER_ABILITIES, which already had
	# entries for these three. Previously missing here, which meant every
	# DEFENDER_STATS[type] call site (all unguarded) would have hard-crashed
	# the instant one of these was added to the roster.
	DefenderType.EOSINOPHIL: {"hp": 30.0, "power": 10.0, "attack_rate": 0.8, "range": 1, "cost": 40, "color": Color8(200, 210, 100)},
	DefenderType.B_CELL: {"hp": 15.0, "power": 6.0, "attack_rate": 1.2, "range": 3, "cost": 45, "color": Color8(160, 200, 230)},
	DefenderType.CYTOTOXIC_T: {"hp": 20.0, "power": 20.0, "attack_rate": 0.9, "range": 2, "cost": 70, "color": Color8(220, 80, 100)},
}

const ENEMY_STATS := {
	# Move speeds tuned to a PvZ-like readable crawl rather than the faster
	# pace from before — the point is you can see a threat coming and have
	# real time to react, not react to something already halfway down the lane.
	EnemyType.BACTERIA: {"hp": 32.0, "power": 7.0, "attack_rate": 1.0, "move_speed": 0.19, "contact_damage": 7.0, "color": Color8(140, 190, 60), "sprite": "res://art/enemies/bacteria_idle.png", "attack_sprites": ["res://art/enemies/bacteria_attack_1.png", "res://art/enemies/bacteria_attack_2.png"], "die_sprites": ["res://art/enemies/bacteria_die.png"]},
	EnemyType.VIRUS: {"hp": 18.0, "power": 8.0, "attack_rate": 1.3, "move_speed": 0.3, "contact_damage": 8.0, "color": Color8(200, 80, 190)},
	# S. aureus — "aureus" is Latin for golden, its colonies really are golden-yellow.
	# Clumps ("staphylo" = cluster of grapes): spawns 2 at once via spawn_group
	# (tuned down from an original 3 during balance passes), individually
	# weaker than baseline Bacteria so the threat is the burst, not the unit.
	EnemyType.STAPH: {"hp": 18.0, "power": 4.0, "attack_rate": 1.0, "move_speed": 0.19, "contact_damage": 4.0, "spawn_group": 2, "color": Color8(210, 175, 50), "sprite": "res://art/enemies/staph_idle.png", "attack_sprites": ["res://art/enemies/staph_attack_1.png", "res://art/enemies/staph_attack_2.png"], "die_sprites": ["res://art/enemies/staph_die.png"]},
	# S. pyogenes — "strepto" = twisted chain; spreads through tissue fast
	# (cellulitis). Glassy and quick: low HP, high speed, punishes a slow
	# single-target defender if it's left unengaged near the front. Still the
	# fast one relative to its lane-mates, just not absurdly so anymore.
	EnemyType.STREP: {"hp": 16.0, "power": 6.0, "attack_rate": 1.2, "move_speed": 0.34, "contact_damage": 6.0, "color": Color8(205, 90, 80), "sprite": "res://art/enemies/strep_idle.png", "attack_sprites": ["res://art/enemies/strep_attack_1.png", "res://art/enemies/strep_attack_2.png"], "die_sprites": ["res://art/enemies/strep_die.png"]},
}

# TYPE_MULTIPLIER[defender_type][enemy_type] -> damage multiplier. Missing entry = 1.0.
# Full table from spec 2.4, including rows for defenders not implemented yet
# (Eosinophil, B Cell, Cytotoxic T) so the data is correct the day they land.
# STAPH and STREP mirror the BACTERIA column exactly for now — they're still
# "bacteria" for type-effectiveness purposes (Level 1's lesson is "any
# defender roughly works", not a new counter to learn). Their variety comes
# from ENEMY_STATS (speed/HP/spawn pattern), not from a new matrix row.
const TYPE_MULTIPLIER := {
	DefenderType.NEUTROPHIL: {EnemyType.BACTERIA: 2.0, EnemyType.VIRUS: 0.5, EnemyType.FUNGUS: 1.0, EnemyType.PARASITE: 0.25, EnemyType.CANCER: 0.5, EnemyType.STAPH: 2.0, EnemyType.STREP: 2.0},
	DefenderType.MACROPHAGE: {EnemyType.BACTERIA: 1.5, EnemyType.VIRUS: 0.5, EnemyType.FUNGUS: 1.0, EnemyType.PARASITE: 0.5, EnemyType.CANCER: 0.5, EnemyType.STAPH: 1.5, EnemyType.STREP: 1.5},
	DefenderType.COMPLEMENT: {EnemyType.BACTERIA: 1.5, EnemyType.VIRUS: 0.5, EnemyType.FUNGUS: 0.5, EnemyType.PARASITE: 0.5, EnemyType.CANCER: 0.25, EnemyType.STAPH: 1.5, EnemyType.STREP: 1.5},
	DefenderType.NK_CELL: {EnemyType.BACTERIA: 1.0, EnemyType.VIRUS: 2.0, EnemyType.FUNGUS: 1.0, EnemyType.PARASITE: 0.5, EnemyType.CANCER: 2.0, EnemyType.STAPH: 1.0, EnemyType.STREP: 1.0},
	DefenderType.EOSINOPHIL: {EnemyType.BACTERIA: 0.5, EnemyType.VIRUS: 0.5, EnemyType.FUNGUS: 0.5, EnemyType.PARASITE: 2.0, EnemyType.CANCER: 0.5, EnemyType.STAPH: 0.5, EnemyType.STREP: 0.5},
	DefenderType.B_CELL: {EnemyType.BACTERIA: 1.5, EnemyType.VIRUS: 1.5, EnemyType.FUNGUS: 0.5, EnemyType.PARASITE: 0.5, EnemyType.CANCER: 0.5, EnemyType.STAPH: 1.5, EnemyType.STREP: 1.5},
	DefenderType.CYTOTOXIC_T: {EnemyType.BACTERIA: 1.0, EnemyType.VIRUS: 2.0, EnemyType.FUNGUS: 0.5, EnemyType.PARASITE: 0.25, EnemyType.CANCER: 0.5, EnemyType.STAPH: 1.0, EnemyType.STREP: 1.0},
}

# LevelConfig per spec 2.1/2.8 — data-driven so adding Levels 2-5 later is
# "new dictionary entries", not new code (per the spec's own Milestone 5 promise).
const LEVELS := {
	1: {
		"name": "Skin — The Wound",
		"duration": 170.0,  # informational only for wave-scripted levels — see "waves". Measured actual clear time (bot playthrough): ~2.5-3 min.
		"starting_rp": 70.0,
		"weights": {EnemyType.STAPH: 0.5, EnemyType.STREP: 0.5},
		# The actual PvZ rhythm, stretched to a real early-PvZ-level length
		# (2-4 min, not a 90-second demo round): a quiet setup period to place
		# defenders, then a SLOW, gradual density ramp across three trickle
		# tiers (not one sharp jump) — "increase of bacteria be slow" — a
		# telegraphed huge wave, a still-gentle middle stretch, then the final
		# wave. Ends once the final wave is cleared, not on a fixed timer.
		"waves": [
			{"t": 10.0, "type": "trickle", "interval": 4.2},
			{"t": 45.0, "type": "trickle", "interval": 3.4},
			{"t": 60.0, "type": "warning", "text": "A huge wave is approaching!"},
			{"t": 64.0, "type": "burst", "per_lane": 2},
			{"t": 65.0, "type": "trickle", "interval": 3.0},
			{"t": 130.0, "type": "warning", "text": "Final wave!"},
			{"t": 135.0, "type": "burst", "per_lane": 3, "final": true},
		],
	},
	2: {
		"name": "Bloodstream — Local Inflammation",
		"duration": 70.0, "base_interval": 3.8, "interval_decay": 0.03, "interval_floor": 1.4,
		"starting_rp": 55.0,
		"weights": {EnemyType.BACTERIA: 0.6, EnemyType.VIRUS: 0.4},
	},
}

const DEFENDER_NAMES := {
	DefenderType.NEUTROPHIL: "Neutrophil",
	DefenderType.MACROPHAGE: "Macrophage",
	DefenderType.COMPLEMENT: "Complement",
	DefenderType.MAST_CELL: "Mast Cell",
	DefenderType.NK_CELL: "NK Cell",
	DefenderType.EOSINOPHIL: "Eosinophil",
	DefenderType.B_CELL: "B Cell",
	DefenderType.HELPER_T: "Helper T Cell",
	DefenderType.CYTOTOXIC_T: "Cytotoxic T Cell",
	DefenderType.DENDRITIC: "Dendritic Cell",
	DefenderType.STEM_CELL: "Stem Cell",
}

const DEFENDER_ABILITIES := {
	DefenderType.NEUTROPHIL: "Fast, cheap devour — high numbers, low individual power.",
	DefenderType.MACROPHAGE: "Slow, heavy devour — high damage, low speed.",
	DefenderType.COMPLEMENT: "Fast, low-damage ranged shot. Fires first on simultaneous ticks.",
	DefenderType.MAST_CELL: "Support aura: -20% move speed to enemies in range. Deals no direct damage.",
	DefenderType.NK_CELL: "Ranged burst, no setup required. Strong vs. viruses and rogue cells.",
	DefenderType.EOSINOPHIL: "Slow, weak vs. small targets, strong vs. large ones.",
	DefenderType.B_CELL: "Ranged; gains +5% power per hit vs. the same enemy type, up to +50%.",
	DefenderType.HELPER_T: "Support aura: +25% power to one adjacent defender. Deals no direct damage.",
	DefenderType.CYTOTOXIC_T: "High single-target damage vs. infected cells.",
	DefenderType.DENDRITIC: "Support aura: enemies in range take +25% damage from all sources.",
	DefenderType.STEM_CELL: "Deals no damage. Periodically produces a bonus RP orb nearby — your main economy investment.",
}


## First-time Memory Cell unlock text (spec: "Explorer-type payoff"), keyed by DefenderType.
const FIELD_NOTES := {
	DefenderType.NEUTROPHIL: "Neutrophils are the most abundant white blood cell and the first responders to a wound — but they're short-lived, dying within days.",
	DefenderType.MACROPHAGE: "\"Macrophage\" means \"big eater\" — these long-lived cells engulf debris and pathogens, then flag threats for the adaptive immune system.",
	DefenderType.COMPLEMENT: "Complement proteins punch literal holes in bacterial membranes, or tag pathogens so other immune cells know to destroy them.",
	DefenderType.MAST_CELL: "Mast cells trigger inflammation by releasing histamine — the same chemical antihistamine allergy medication blocks.",
	DefenderType.NK_CELL: "Natural Killer cells can destroy infected or abnormal cells without ever having seen that threat before — no prior exposure needed.",
	DefenderType.HELPER_T: "Helper T cells don't kill anything directly — they coordinate everyone else. Losing too many (as in advanced HIV) leaves the body unable to fight almost anything.",
	DefenderType.DENDRITIC: "Dendritic cells capture pathogen fragments and present them to T cells — the actual bridge between your fast \"innate\" defenses and your slower, smarter \"adaptive\" immune system.",
	DefenderType.STEM_CELL: "Hematopoietic stem cells in bone marrow are the actual biological source of every blood and immune cell your body makes.",
}

const ENEMY_NAMES := {
	EnemyType.BACTERIA: "Bacteria",
	EnemyType.VIRUS: "Virus",
	EnemyType.FUNGUS: "Fungus",
	EnemyType.PARASITE: "Parasite",
	EnemyType.CANCER: "Cancer",
	EnemyType.STAPH: "Staph Cluster",
	EnemyType.STREP: "Strep Runner",
}


## Single canonical definition of "has any aura" for a raw DEFENDER_STATS
## dict (used where no Defender instance exists yet, e.g. the hover preview
## for a currently-selected type). Defender.has_aura() is the equivalent for
## an already-placed instance — kept separate since they operate on different
## representations, but each is defined exactly once now instead of being
## copy-pasted inline at every call site.
func defender_stats_has_aura(stats: Dictionary) -> bool:
	return stats.get("aura_slow", 0.0) > 0.0 \
		or stats.get("aura_power_buff", 0.0) > 0.0 \
		or stats.get("aura_mark_damage", 0.0) > 0.0


func defender_tooltip(t: int) -> String:
	var s: Dictionary = DEFENDER_STATS.get(t, {})
	if s.is_empty():
		return DEFENDER_NAMES.get(t, "Unknown")
	var lines: PackedStringArray = [
		DEFENDER_NAMES[t],
		"HP %d | Power %d | Rate %.1f/s | Range %d | Cost %d RP" % [s.hp, s.power, s.attack_rate, s.range, s.cost],
		DEFENDER_ABILITIES.get(t, ""),
	]
	if FIELD_NOTES.has(t):
		lines.append(FIELD_NOTES[t])
	return "\n".join(lines)


func weighted_random_enemy(weights: Dictionary) -> int:
	var total: float = 0.0
	for w in weights.values():
		total += w
	var roll: float = randf() * total
	var acc: float = 0.0
	for enemy_type in weights.keys():
		acc += weights[enemy_type]
		if roll <= acc:
			return enemy_type
	return weights.keys().back()


func get_multiplier(defender_type: int, enemy_type: int) -> float:
	if TYPE_MULTIPLIER.has(defender_type) and TYPE_MULTIPLIER[defender_type].has(enemy_type):
		return TYPE_MULTIPLIER[defender_type][enemy_type]
	return 1.0


func defender_name(t: int) -> String:
	return DEFENDER_NAMES.get(t, "Unknown")


func enemy_name(t: int) -> String:
	return ENEMY_NAMES.get(t, "Unknown")
