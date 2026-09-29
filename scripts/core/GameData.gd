## Autoload singleton: scripts/core/GameData.gd
## Holds shared enumerations, spell definitions, and global game constants.
## Registered as an AutoLoad in project.godot (name: GameData).
extends Node

# ---------------------------------------------------------------------------
# Enumerations shared across all systems
# ---------------------------------------------------------------------------
enum PlayerState {
	IDLE,
	MOVING,
	CASTING,
	DODGE_ROLLING,
	STUNNED,
	DEAD
}

enum SpellSchool {
	FIRE,
	FROST,
	ARCANE,
	SHADOW,
	HOLY,
	NATURE
}

enum Team {
	NONE = 0,
	TEAM_1 = 1,
	TEAM_2 = 2
}

# ---------------------------------------------------------------------------
# Spell definition structure
# ---------------------------------------------------------------------------
class SpellData:
	var id: int                     = 0
	var display_name: String        = ""
	var school: int                 = SpellSchool.FIRE     # SpellSchool
	var cast_time: float            = 0.0                  # 0 = instant
	var cooldown: float             = 1.5
	var mana_cost: float            = 20.0
	var base_damage: float          = 0.0
	var base_heal: float            = 0.0
	var range: float                = 25.0
	var causes_interrupt: bool      = false
	var icon_path: String           = ""
	var projectile_speed: float     = 0.0                  # 0 = instant hit
	var stagger_amount: float       = 0.0

	func _init(
		p_id: int,
		p_name: String,
		p_school: int,
		p_cast_time: float,
		p_cooldown: float,
		p_mana_cost: float,
		p_base_damage: float,
		p_base_heal: float,
		p_range: float,
		p_causes_interrupt: bool,
		p_stagger: float = 0.0,
		p_projectile_speed: float = 0.0
	) -> void:
		id                = p_id
		display_name      = p_name
		school            = p_school
		cast_time         = p_cast_time
		cooldown          = p_cooldown
		mana_cost         = p_mana_cost
		base_damage       = p_base_damage
		base_heal         = p_base_heal
		range             = p_range
		causes_interrupt  = p_causes_interrupt
		stagger_amount    = p_stagger
		projectile_speed  = p_projectile_speed

# ---------------------------------------------------------------------------
# Spell library — all spells available to players
# ---------------------------------------------------------------------------
var SPELLS: Dictionary = {}

func _ready() -> void:
	_register_spells()

func _register_spells() -> void:
	var spell_list: Array[SpellData] = [
		SpellData.new(1,  "Fireball",          SpellSchool.FIRE,    1.8,  3.0,  30.0, 85.0,  0.0, 30.0, false, 15.0, 18.0),
		SpellData.new(2,  "Frost Nova",         SpellSchool.FROST,   0.0,  12.0, 25.0, 45.0,  0.0, 12.0, true,  30.0, 0.0),
		SpellData.new(3,  "Arcane Blast",       SpellSchool.ARCANE,  2.5,  4.0,  40.0, 120.0, 0.0, 35.0, false, 10.0, 22.0),
		SpellData.new(4,  "Shadow Bolt",        SpellSchool.SHADOW,  2.0,  3.5,  35.0, 95.0,  0.0, 30.0, false, 20.0, 15.0),
		SpellData.new(5,  "Flash Heal",         SpellSchool.HOLY,    1.5,  5.0,  50.0, 0.0,  120.0, 25.0, false, 0.0, 0.0),
		SpellData.new(6,  "Counterspell",       SpellSchool.ARCANE,  0.0,  24.0, 20.0, 0.0,   0.0, 30.0, true,  0.0, 0.0),
		SpellData.new(7,  "Wrath",              SpellSchool.NATURE,  1.5,  2.5,  25.0, 70.0,  0.0, 30.0, false, 12.0, 14.0),
		SpellData.new(8,  "Holy Shock",         SpellSchool.HOLY,    0.0,  6.0,  30.0, 60.0,  60.0, 20.0, false, 25.0, 0.0),
		SpellData.new(9,  "Blizzard",           SpellSchool.FROST,   3.0,  8.0,  60.0, 150.0, 0.0, 25.0, false, 35.0, 0.0),
		SpellData.new(10, "Mind Flay",          SpellSchool.SHADOW,  0.0,  3.0,  20.0, 55.0,  0.0, 15.0, false, 10.0, 0.0),
	]
	for s: SpellData in spell_list:
		SPELLS[s.id] = s

func get_spell(spell_id: int) -> SpellData:
	if SPELLS.has(spell_id):
		return SPELLS[spell_id] as SpellData
	return null

# ---------------------------------------------------------------------------
# Global constants
# ---------------------------------------------------------------------------
const ARENA_RADIUS: float         = 15.0
const ARENA_BOUNDARY: float       = 14.5
const SPAWN_TEAM_1: Vector3       = Vector3(-12.0, 1.0, 0.0)
const SPAWN_TEAM_2: Vector3       = Vector3(12.0,  1.0, 0.0)
const MAX_HEALTH: float           = 1000.0
const MAX_MANA: float             = 600.0
const MAX_STAMINA: float          = 100.0
const MAX_STAGGER: float          = 200.0
const STAMINA_REGEN_RATE: float   = 20.0   # per second
const MANA_REGEN_RATE: float      = 5.0    # per second
const DODGE_STAMINA_COST: float   = 25.0
const DODGE_DURATION: float       = 0.35
const IFRAME_DURATION: float      = 0.20
const DODGE_SPEED_MULT: float     = 3.0
const INTERRUPT_LOCK_DURATION: float = 3.0
const MOVE_SPEED: float           = 6.0
const NETWORK_PORT: int           = 7777
const MAX_PLAYERS: int            = 4
const TICK_RATE: int              = 60
const INTERP_FACTOR: float        = 0.15  # remote player lerp per frame
