## scripts/entities/Player.gd
## Full player controller: movement, dodge roll, target selection, cast triggers,
## vitals (HP/Mana/Stamina/Stagger), network sync (prediction + interpolation).
class_name Player
extends CharacterBody3D

# ---------------------------------------------------------------------------
# MultiplayerSynchronizer properties (declared for sync node to pick up)
# ---------------------------------------------------------------------------
@export var sync_position: Vector3    = Vector3.ZERO
@export var sync_rotation_y: float    = 0.0
@export var sync_state: int           = GameData.PlayerState.IDLE

# ---------------------------------------------------------------------------
# Node references (assigned after scene instantiation)
# ---------------------------------------------------------------------------
@onready var _cast_system: CastSystem        = $CastSystem
@onready var _model_root: Node3D             = $ModelRoot
@onready var _camera_pivot: Node3D           = $CameraPivot
@onready var _camera: Camera3D               = $CameraPivot/Camera3D
@onready var _sync_node: MultiplayerSynchronizer = $MultiplayerSynchronizer

# ---------------------------------------------------------------------------
# Exported action bar config (3 spell slots)
# ---------------------------------------------------------------------------
@export var spell_slot_1: int = 1   # Fireball
@export var spell_slot_2: int = 2   # Frost Nova
@export var spell_slot_3: int = 6   # Counterspell

# ---------------------------------------------------------------------------
# Vitals
# ---------------------------------------------------------------------------
var current_health: float       = GameData.MAX_HEALTH
var current_mana: float         = GameData.MAX_MANA
var current_stamina: float      = GameData.MAX_STAMINA
var current_stagger: float      = 0.0

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var current_state: int          = GameData.PlayerState.IDLE   # PlayerState
var display_name: String        = "Warrior"
var team: int                   = GameData.Team.NONE

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
var _move_dir: Vector3          = Vector3.ZERO
var _wish_velocity: Vector3     = Vector3.ZERO

# ---------------------------------------------------------------------------
# Dodge
# ---------------------------------------------------------------------------
var _dodge_timer: float         = 0.0
var _iframe_timer: float        = 0.0
var _dodge_direction: Vector3   = Vector3.ZERO
var _is_invulnerable: bool      = false

# ---------------------------------------------------------------------------
# Targeting
# ---------------------------------------------------------------------------
var _current_target: Node       = null
var _potential_targets: Array   = []    # All enemy players in arena

# ---------------------------------------------------------------------------
# Network / authority
# ---------------------------------------------------------------------------
var _is_local_player: bool      = false
var _peer_id: int               = 0

# Interpolation buffers for remote players
var _remote_target_pos: Vector3 = Vector3.ZERO
var _remote_target_rot: float   = 0.0

# HUD reference (only on local player)
var _hud: Node                  = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Set up synchronizer: server is authority for all players,
	# but local owner does client-side prediction
	if multiplayer.is_server():
		set_process(true)
		set_physics_process(true)
	else:
		set_physics_process(true)

	# Camera disabled by default; enabled in init_as_local_player
	if _camera:
		_camera.current = false

	# Connect cast system signals
	_cast_system.cast_started.connect(_on_cast_started)
	_cast_system.cast_completed.connect(_on_cast_completed)
	_cast_system.cast_interrupted.connect(_on_cast_interrupted)
	_cast_system.cast_cancelled.connect(_on_cast_cancelled)

	# Auto-detect local player on spawn
	var my_id: int = multiplayer.get_unique_id()
	if name == "Player_%d" % my_id:
		call_deferred("_setup_as_local_player", my_id)

func _setup_as_local_player(my_id: int) -> void:
	init_as_local_player(my_id, team)

func init_as_local_player(peer_id: int, team_id: int) -> void:
	if _is_local_player:
		return
	_is_local_player = true
	_peer_id         = peer_id
	team             = team_id
	set_meta("peer_id", peer_id)
	set_meta("team", team_id)

	if _camera:
		_camera.current = true

	# Load HUD
	if _hud == null:
		var hud_scene: PackedScene = load("res://scenes/ui/CombatHUD.tscn") as PackedScene
		if hud_scene:
			_hud = hud_scene.instantiate()
			get_tree().root.add_child(_hud)
			if _hud.has_method("init"):
				_hud.init(self)

	# Build target list after a frame
	call_deferred("_refresh_target_list")
	print("Player: Initialized as local player — id=%d team=%d" % [peer_id, team_id])

# ---------------------------------------------------------------------------
# Input & physics (local player only)
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_player:
		return

	# Target selection — left click
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_click_select_target()

	# Spell slots
	if event.is_action_pressed("cast_slot_1"):
		_initiate_cast(spell_slot_1)
	elif event.is_action_pressed("cast_slot_2"):
		_initiate_cast(spell_slot_2)
	elif event.is_action_pressed("cast_slot_3"):
		_initiate_cast(spell_slot_3)

	# Tab cycle target
	if event.is_action_pressed("cycle_target"):
		_cycle_target()

func _physics_process(delta: float) -> void:
	if _is_local_player:
		_process_local(delta)
	else:
		_process_remote(delta)

func _process_local(delta: float) -> void:
	# Regen
	_regen_stamina(delta)
	_regen_mana(delta)
	_decay_stagger(delta)

	# Dodge tick
	_tick_dodge(delta)

	match current_state:
		GameData.PlayerState.DEAD:
			return
		GameData.PlayerState.DODGE_ROLLING:
			_apply_dodge_velocity()
		GameData.PlayerState.STUNNED:
			velocity = Vector3.ZERO
		_:
			_apply_movement(delta)

	move_and_slide()
	_clamp_to_arena()

	# Push sync values
	sync_position  = global_position
	sync_rotation_y = rotation.y
	sync_state     = current_state

	# Update dodge action input (outside of state machine to allow triggering)
	if Input.is_action_just_pressed("dodge_roll") and current_state == GameData.PlayerState.MOVING \
			or (Input.is_action_just_pressed("dodge_roll") and current_state == GameData.PlayerState.IDLE):
		_begin_dodge()

func _process_remote(delta: float) -> void:
	# Interpolate remote player toward authoritative position
	global_position = global_position.lerp(_remote_target_pos, GameData.INTERP_FACTOR)
	rotation.y     = lerp_angle(rotation.y, _remote_target_rot, GameData.INTERP_FACTOR)

# ---------------------------------------------------------------------------
# Sync property setters — called when sync node receives new values
# ---------------------------------------------------------------------------
func set_sync_position(value: Vector3) -> void:
	sync_position = value
	if not _is_local_player:
		_remote_target_pos = value

func set_sync_rotation_y(value: float) -> void:
	sync_rotation_y = value
	if not _is_local_player:
		_remote_target_rot = value

func set_sync_state(value: int) -> void:
	sync_state    = value
	if not _is_local_player:
		current_state = value

# ---------------------------------------------------------------------------
# Movement helpers
# ---------------------------------------------------------------------------
func _apply_movement(delta: float) -> void:
	var fwd: Vector3 = Vector3.ZERO
	var right: Vector3 = Vector3.ZERO

	if _camera_pivot:
		fwd   = -_camera_pivot.global_transform.basis.z
		right = _camera_pivot.global_transform.basis.x
	else:
		fwd   = -global_transform.basis.z
		right = global_transform.basis.x

	fwd.y   = 0.0
	right.y = 0.0
	fwd     = fwd.normalized()
	right   = right.normalized()

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	_move_dir = (fwd * -input_dir.y + right * input_dir.x).normalized()

	if _move_dir.length_squared() > 0.01:
		current_state = GameData.PlayerState.MOVING
		# Face movement direction
		rotation.y = lerp_angle(rotation.y, atan2(-_move_dir.x, -_move_dir.z), 0.2)
	else:
		if current_state == GameData.PlayerState.MOVING:
			current_state = GameData.PlayerState.IDLE

	# Cancel cast on movement (channelled only)
	if _cast_system.is_casting() and _move_dir.length_squared() > 0.01:
		_cast_system.cancel_cast()

	var speed: float = GameData.MOVE_SPEED
	velocity.x = _move_dir.x * speed
	velocity.z = _move_dir.z * speed
	# Gravity
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0

func _clamp_to_arena() -> void:
	var flat: Vector2 = Vector2(global_position.x, global_position.z)
	if flat.length() > GameData.ARENA_BOUNDARY:
		flat = flat.normalized() * GameData.ARENA_BOUNDARY
		global_position.x = flat.x
		global_position.z = flat.y

# ---------------------------------------------------------------------------
# Dodge roll
# ---------------------------------------------------------------------------
func _begin_dodge() -> void:
	if current_stamina < GameData.DODGE_STAMINA_COST:
		return
	if current_state == GameData.PlayerState.DEAD:
		return

	spend_stamina(GameData.DODGE_STAMINA_COST)
	_dodge_timer      = GameData.DODGE_DURATION
	_iframe_timer     = GameData.IFRAME_DURATION
	_is_invulnerable  = true
	current_state     = GameData.PlayerState.DODGE_ROLLING

	# Dodge in move direction or forward if stationary
	_dodge_direction = _move_dir if _move_dir.length_squared() > 0.01 else -global_transform.basis.z
	_dodge_direction.y = 0.0
	_dodge_direction = _dodge_direction.normalized()

	# Cancel ongoing cast
	if _cast_system.is_casting():
		_cast_system.cancel_cast()

func _tick_dodge(delta: float) -> void:
	if current_state != GameData.PlayerState.DODGE_ROLLING:
		return

	_dodge_timer -= delta
	if _iframe_timer > 0.0:
		_iframe_timer -= delta
		if _iframe_timer <= 0.0:
			_is_invulnerable = false

	if _dodge_timer <= 0.0:
		_dodge_timer     = 0.0
		current_state    = GameData.PlayerState.IDLE
		_is_invulnerable = false

func _apply_dodge_velocity() -> void:
	var dodge_speed: float = GameData.MOVE_SPEED * GameData.DODGE_SPEED_MULT
	velocity.x = _dodge_direction.x * dodge_speed
	velocity.z = _dodge_direction.z * dodge_speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * get_physics_process_delta_time()

# ---------------------------------------------------------------------------
# Target selection
# ---------------------------------------------------------------------------
func _refresh_target_list() -> void:
	_potential_targets.clear()
	var arena: Node = get_tree().root.get_node_or_null("arena")
	if arena == null:
		return
	var players_root: Node = arena.get_node_or_null("Players")
	if players_root == null:
		return
	for child: Node in players_root.get_children():
		if child == self:
			continue
		var child_team: int = child.get_meta("team", GameData.Team.NONE)
		if child_team != team and child_team != GameData.Team.NONE:
			_potential_targets.append(child)

func _try_click_select_target() -> void:
	if _camera == null:
		return
	var viewport: Viewport = get_viewport()
	var mouse_pos: Vector2  = viewport.get_mouse_position()
	var ray_origin: Vector3 = _camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3    = _camera.project_ray_normal(mouse_pos)
	var ray_end: Vector3    = ray_origin + ray_dir * 100.0

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [get_rid()]
	query.collision_mask = 0b0010   # layer 2: players
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return

	var hit_object: Object = result.get("collider")
	if hit_object == null:
		return
	# Walk up to find Player node
	var node: Node = hit_object as Node
	while node != null:
		if node is Player and node != self:
			var hit_team: int = node.get_meta("team", GameData.Team.NONE)
			if hit_team != team:
				_set_target(node)
			break
		node = node.get_parent()

func _cycle_target() -> void:
	_refresh_target_list()
	if _potential_targets.is_empty():
		return
	if _current_target == null:
		_set_target(_potential_targets[0])
		return
	var idx: int = _potential_targets.find(_current_target)
	idx = (idx + 1) % _potential_targets.size()
	_set_target(_potential_targets[idx])

func _set_target(target: Node) -> void:
	_current_target = target
	if _hud and _hud.has_method("set_target"):
		_hud.set_target(target)

func get_current_target() -> Node:
	return _current_target

# ---------------------------------------------------------------------------
# Casting
# ---------------------------------------------------------------------------
func _initiate_cast(spell_id: int) -> void:
	if current_state == GameData.PlayerState.DEAD:
		return
	if _cast_system.is_on_cooldown(spell_id):
		return

	var spell: GameData.SpellData = GameData.get_spell(spell_id)
	if spell == null:
		return

	# For damage spells require a target
	if spell.base_damage > 0.0 and _current_target == null:
		_refresh_target_list()
		if _potential_targets.is_empty():
			return
		_set_target(_potential_targets[0])

	var target: Node = _current_target if spell.base_damage > 0.0 else null

	if spell.cast_time > 0.0:
		current_state = GameData.PlayerState.CASTING
	_cast_system.try_cast(spell_id, self, target)

	# For instant hits immediately request server validation
	if spell.cast_time <= 0.0 and target != null:
		_cast_system.server_validate_hit.rpc(get_path(), target.get_path(), spell_id)

func _on_cast_started(spell_id: int, cast_time: float) -> void:
	current_state = GameData.PlayerState.CASTING
	if _hud and _hud.has_method("on_cast_started"):
		_hud.on_cast_started(spell_id, cast_time)

func _on_cast_completed(spell_id: int) -> void:
	current_state = GameData.PlayerState.IDLE
	if _current_target != null:
		_cast_system.server_validate_hit.rpc(get_path(), _current_target.get_path(), spell_id)
	if _hud and _hud.has_method("on_cast_completed"):
		_hud.on_cast_completed(spell_id)

func _on_cast_interrupted(spell_id: int, locked_school: int) -> void:
	current_state = GameData.PlayerState.IDLE
	if _hud and _hud.has_method("on_cast_interrupted"):
		_hud.on_cast_interrupted(spell_id)

func _on_cast_cancelled() -> void:
	if current_state == GameData.PlayerState.CASTING:
		current_state = GameData.PlayerState.IDLE
	if _hud and _hud.has_method("on_cast_cancelled"):
		_hud.on_cast_cancelled()

# ---------------------------------------------------------------------------
# Vitals
# ---------------------------------------------------------------------------
func get_health() -> float:
	return current_health

func get_mana() -> float:
	return current_mana

func get_stamina() -> float:
	return current_stamina

func get_stagger() -> float:
	return current_stagger

func is_invulnerable() -> bool:
	return _is_invulnerable

func get_cast_system() -> CastSystem:
	return _cast_system

func receive_damage(amount: float) -> void:
	if _is_invulnerable:
		return
	current_health -= amount
	current_health = maxf(current_health, 0.0)
	if _hud and _is_local_player and _hud.has_method("update_vitals"):
		_hud.update_vitals()
	if current_health <= 0.0:
		_die()

func receive_heal(amount: float) -> void:
	current_health = minf(current_health + amount, GameData.MAX_HEALTH)
	if _hud and _is_local_player and _hud.has_method("update_vitals"):
		_hud.update_vitals()

func receive_stagger(amount: float) -> void:
	current_stagger = minf(current_stagger + amount, GameData.MAX_STAGGER)
	if _hud and _is_local_player and _hud.has_method("update_vitals"):
		_hud.update_vitals()

func spend_mana(amount: float) -> void:
	current_mana = maxf(current_mana - amount, 0.0)
	if _hud and _is_local_player and _hud.has_method("update_vitals"):
		_hud.update_vitals()

func spend_stamina(amount: float) -> void:
	current_stamina = maxf(current_stamina - amount, 0.0)
	if _hud and _is_local_player and _hud.has_method("update_vitals"):
		_hud.update_vitals()

func _regen_stamina(delta: float) -> void:
	if current_state == GameData.PlayerState.DODGE_ROLLING:
		return
	current_stamina = minf(current_stamina + GameData.STAMINA_REGEN_RATE * delta, GameData.MAX_STAMINA)
	if _hud and _is_local_player and _hud.has_method("update_vitals"):
		_hud.update_vitals()

func _regen_mana(delta: float) -> void:
	current_mana = minf(current_mana + GameData.MANA_REGEN_RATE * delta, GameData.MAX_MANA)

func _decay_stagger(delta: float) -> void:
	if current_stagger > 0.0:
		current_stagger = maxf(current_stagger - 10.0 * delta, 0.0)

func _die() -> void:
	current_state = GameData.PlayerState.DEAD
	velocity      = Vector3.ZERO
	if _cast_system.is_casting():
		_cast_system.cancel_cast()
	if _hud and _is_local_player and _hud.has_method("on_player_died"):
		_hud.on_player_died()
	print("Player %s has died." % display_name)

# ---------------------------------------------------------------------------
# Camera follow (local player only)
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _is_local_player or _camera_pivot == null:
		return
	# Isometric-style chase camera: offset above and behind
	var target_pos: Vector3 = global_position + Vector3(0.0, 12.0, 10.0)
	_camera_pivot.global_position = _camera_pivot.global_position.lerp(target_pos, 0.12)
	_camera_pivot.look_at(global_position, Vector3.UP)
