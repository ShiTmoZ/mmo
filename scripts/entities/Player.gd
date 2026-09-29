class_name Player
extends Actor

@export var player_id: int = 1
@export var username: String = "Player"

# Preset Spells
@export var spell_slots: Array[SpellData] = []

var input_direction: Vector3 = Vector3.ZERO
var dodge_cost: float = 25.0
var is_dodging: bool = false
var dodge_duration: float = 0.35
var dodge_timer: float = 0.0

func _ready() -> void:
	super._ready()
	# Set authority for local player input
	set_multiplayer_authority(player_id)
	
	# Populate default test spells if empty
	if spell_slots.is_empty():
		_init_default_spells()

func _init_default_spells() -> void:
	# 1: Strike (Quick Melee)
	var strike = SpellData.new()
	strike.id = "strike"
	strike.name = "Sundering Strike"
	strike.cast_time = 0.0
	strike.cooldown = 3.0
	strike.mana_cost = 15.0
	strike.base_value = 85.0
	strike.causes_interrupt = true
	spell_slots.append(strike)

	# 2: Holy Mend (Heal)
	var mend = SpellData.new()
	mend.id = "mend"
	mend.name = "Holy Mend"
	mend.cast_time = 1.5
	mend.cooldown = 0.0
	mend.mana_cost = 40.0
	mend.base_value = 160.0
	mend.is_heal = true
	spell_slots.append(mend)

	# 3: Radiant Ward (Buff / Stagger shield)
	var ward = SpellData.new()
	ward.id = "ward"
	ward.name = "Radiant Ward"
	ward.cast_time = 0.8
	ward.cooldown = 15.0
	ward.mana_cost = 50.0
	ward.base_value = 0.0
	ward.crit_bonus = 0.25
	spell_slots.append(ward)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Handle Dodge roll
	if is_dodging:
		dodge_timer -= delta
		velocity = input_direction * (move_speed * 1.8)
		move_and_slide()
		if dodge_timer <= 0.0:
			is_dodging = false
			change_state(State.IDLE)
		return

	# Handle States
	if current_state == State.CASTING or current_state == State.COMMITTED or current_state == State.STUNNED or current_state == State.DEAD:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Handle Movement Inputs
	var move_x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var move_z = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	var dir = Vector3(move_x, 0, move_z).normalized()

	if dir != Vector3.ZERO:
		input_direction = dir
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		change_state(State.MOVING)
		
		# Rotate towards move direction
		var target_rotation = atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotate_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		if current_state == State.MOVING:
			change_state(State.IDLE)

	move_and_slide()

	# Handle Dodge Action (Souls-like i-frame mechanism)
	if Input.is_action_just_pressed("dodge") and current_stamina >= dodge_cost and not is_dodging:
		current_stamina -= dodge_cost
		stamina_changed.emit(current_stamina, max_stamina)
		is_dodging = true
		dodge_timer = dodge_duration
		change_state(State.COMMITTED)
		cast_system.interrupt()
		return

	# Handle Spell Inputs
	if Input.is_action_just_pressed("spell_1"):
		_try_cast(0)
	elif Input.is_action_just_pressed("spell_2"):
		_try_cast(1)
	elif Input.is_action_just_pressed("spell_3"):
		_try_cast(2)

func _try_cast(index: int) -> void:
	if index < 0 or index >= spell_slots.size():
		return
	var spell = spell_slots[index]
	if cast_system.can_cast(spell, current_mana, current_stamina):
		current_mana -= spell.mana_cost
		current_stamina -= spell.stamina_cost
		mana_changed.emit(current_mana, max_mana)
		stamina_changed.emit(current_stamina, max_stamina)
		cast_system.start_cast(spell)
		rpc("sync_spell_cast", spell.id)

@rpc("any_peer", "call_local")
func sync_spell_cast(spell_id: String) -> void:
	# Broadcast spell visual/sound to peers
	pass
