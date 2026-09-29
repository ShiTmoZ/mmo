class_name SpellData
extends Resource

@export var id: String = "spell_default"
@export var name: String = "Default Spell"
@export var description: String = ""
@export var icon_path: String = ""

# Costs & Timings
@export var cast_time: float = 1.0       # Seconds (locks movement if > 0)
@export var cooldown: float = 0.0        # Seconds after cast finish
@export var mana_cost: float = 10.0
@export var stamina_cost: float = 0.0

# Effect Attributes
@export var base_value: float = 50.0      # Base damage or healing
@export var is_heal: bool = false
@export var range_radius: float = 12.0
@export var crit_bonus: float = 0.0       # Temporary crit boost or flat crit
@export var causes_interrupt: bool = false
@export var interruptible: bool = true
