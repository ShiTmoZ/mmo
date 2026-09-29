class_name Actor
extends CharacterBody3D

enum State {
	IDLE,
	MOVING,
	CASTING,
	COMMITTED,
	STUNNED,
	DEAD
}

signal state_changed(old_state: State, new_state: State)
signal health_changed(current: float, max_val: float)
signal mana_changed(current: float, max_val: float)
signal stamina_changed(current: float, max_val: float)
signal staggered()

# Core Vitals
@export var max_health: float = 1000.0
@export var max_mana: float = 300.0
@export var max_stamina: float = 100.0
@export var max_stagger: float = 100.0

var current_health: float
var current_mana: float
var current_stamina: float
var current_stagger: float = 0.0

var current_state: State = State.IDLE
var move_speed: float = 6.0
var rotate_speed: float = 12.0

@onready var cast_system: CastSystem = CastSystem.new()

func _ready() -> void:
	current_health = max_health
	current_mana = max_mana
	current_stamina = max_stamina
	add_child(cast_system)

	cast_system.cast_started.connect(_on_cast_started)
	cast_system.cast_finished.connect(_on_cast_finished)
	cast_system.cast_interrupted.connect(_on_cast_interrupted)

func change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	var old = current_state
	current_state = new_state
	state_changed.emit(old, new_state)

func take_damage(amount: float, causes_interrupt: bool = false, stagger_add: float = 0.0) -> void:
	if current_state == State.DEAD:
		return
	
	current_health = max(0.0, current_health - amount)
	health_changed.emit(current_health, max_health)

	if stagger_add > 0.0:
		current_stagger += stagger_add
		if current_stagger >= max_stagger:
			current_stagger = 0.0
			staggered.emit()
			change_state(State.STUNNED)

	if causes_interrupt or current_state == State.STUNNED:
		cast_system.interrupt()

	if current_health <= 0.0:
		change_state(State.DEAD)

func receive_heal(amount: float) -> void:
	if current_state == State.DEAD:
		return
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func _on_cast_started(_spell: SpellData) -> void:
	change_state(State.CASTING)

func _on_cast_finished(_spell: SpellData) -> void:
	if current_state == State.CASTING:
		change_state(State.IDLE)

func _on_cast_interrupted(_spell: SpellData) -> void:
	if current_state == State.CASTING:
		change_state(State.IDLE)
