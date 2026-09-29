class_name CastSystem
extends Node

signal cast_started(spell: SpellData)
signal cast_progress(spell: SpellData, progress: float)
signal cast_finished(spell: SpellData)
signal cast_interrupted(spell: SpellData)
signal cooldown_updated(spell_id: String, remaining: float)

@export var global_cooldown_duration: float = 1.0
var gcd_timer: float = 0.0

var current_spell: SpellData = null
var current_cast_time: float = 0.0
var cooldowns: Dictionary = {}  # spell_id -> remaining_time float

func _process(delta: float) -> void:
	# Tick GCD
	if gcd_timer > 0.0:
		gcd_timer = max(0.0, gcd_timer - delta)

	# Tick Individual Cooldowns
	var to_erase = []
	for s_id in cooldowns.keys():
		cooldowns[s_id] = max(0.0, cooldowns[s_id] - delta)
		cooldown_updated.emit(s_id, cooldowns[s_id])
		if cooldowns[s_id] <= 0.0:
			to_erase.append(s_id)
	for s_id in to_erase:
		cooldowns.erase(s_id)

	# Process Active Cast
	if current_spell != null:
		current_cast_time += delta
		var ratio = current_cast_time / max(0.001, current_spell.cast_time)
		cast_progress.emit(current_spell, min(1.0, ratio))

		if current_cast_time >= current_spell.cast_time:
			_complete_cast()

func can_cast(spell: SpellData, current_mana: float, current_stamina: float) -> bool:
	if current_spell != null:
		return false
	if gcd_timer > 0.0:
		return false
	if cooldowns.has(spell.id) and cooldowns[spell.id] > 0.0:
		return false
	if current_mana < spell.mana_cost or current_stamina < spell.stamina_cost:
		return false
	return true

func start_cast(spell: SpellData) -> bool:
	if current_spell != null:
		return false
	current_spell = spell
	current_cast_time = 0.0
	gcd_timer = global_cooldown_duration
	cast_started.emit(spell)

	# Instant casts complete immediately
	if spell.cast_time <= 0.0:
		_complete_cast()
	return true

func interrupt() -> void:
	if current_spell != null and current_spell.interruptible:
		var interrupted_spell = current_spell
		current_spell = null
		current_cast_time = 0.0
		cast_interrupted.emit(interrupted_spell)

func _complete_cast() -> void:
	if current_spell == null:
		return
	var spell = current_spell
	if spell.cooldown > 0.0:
		cooldowns[spell.id] = spell.cooldown
	current_spell = null
	current_cast_time = 0.0
	cast_finished.emit(spell)
