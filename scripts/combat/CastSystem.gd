## scripts/combat/CastSystem.gd
## Server-authoritative cast + hit registration system.
## Attached to each Player node; handles casting, interrupt, and spell schools.
class_name CastSystem
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal cast_started(spell_id: int, cast_time: float)
signal cast_completed(spell_id: int)
signal cast_interrupted(spell_id: int, locked_school: int)
signal cast_cancelled()
signal hit_landed(target: Node, spell_id: int, damage: float, healed: float)

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _owner_player: Node                      = null   # Player node this is attached to
var _current_spell_id: int                   = -1
var _cast_timer: float                       = 0.0
var _cast_duration: float                    = 0.0
var _is_casting: bool                        = false

# Spell school lockout: school_id -> remaining seconds locked
var _school_lockouts: Dictionary             = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_owner_player = get_parent()

func _physics_process(delta: float) -> void:
	# Tick active cast
	if _is_casting:
		_cast_timer += delta
		if _cast_timer >= _cast_duration:
			_finish_cast()

	# Tick school lockouts
	var expired_schools: Array[int] = []
	for school_id: int in _school_lockouts:
		_school_lockouts[school_id] -= delta
		if _school_lockouts[school_id] <= 0.0:
			expired_schools.append(school_id)
	for s: int in expired_schools:
		_school_lockouts.erase(s)

	# Tick spell cooldowns
	_physics_process_cooldowns(delta)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func try_cast(spell_id: int, caster: Node, target: Node) -> bool:
	var spell: GameData.SpellData = GameData.get_spell(spell_id)
	if spell == null:
		push_warning("CastSystem: Unknown spell id %d" % spell_id)
		return false

	# Validate caster state
	if _is_casting:
		push_warning("CastSystem: Already casting")
		return false
	if is_school_locked(spell.school):
		push_warning("CastSystem: School %d is locked out" % spell.school)
		return false
	if not caster.has_method("get_mana") or caster.get_mana() < spell.mana_cost:
		push_warning("CastSystem: Insufficient mana")
		return false

	# Deduct mana immediately
	caster.spend_mana(spell.mana_cost)

	if spell.cast_time <= 0.0:
		# Instant spell — resolve immediately
		_resolve_hit(spell, caster, target)
		_start_cooldown(spell_id, spell.cooldown)
		return true

	# Begin channelled cast
	_current_spell_id  = spell_id
	_cast_duration     = spell.cast_time
	_cast_timer        = 0.0
	_is_casting        = true
	cast_started.emit(spell_id, spell.cast_time)
	return true

func interrupt_cast(incoming_school_locked: int = -1) -> void:
	if not _is_casting:
		return
	var interrupted_spell_id: int = _current_spell_id
	var locked_school: int        = -1

	if incoming_school_locked >= 0:
		# Lock the school being interrupted
		locked_school = incoming_school_locked
		_school_lockouts[locked_school] = GameData.INTERRUPT_LOCK_DURATION

	_is_casting        = false
	_cast_timer        = 0.0
	_current_spell_id  = -1
	_cast_duration     = 0.0
	cast_interrupted.emit(interrupted_spell_id, locked_school)

func cancel_cast() -> void:
	if not _is_casting:
		return
	_is_casting        = false
	_cast_timer        = 0.0
	_current_spell_id  = -1
	_cast_duration     = 0.0
	cast_cancelled.emit()

func is_casting() -> bool:
	return _is_casting

func get_cast_progress() -> float:
	if not _is_casting or _cast_duration <= 0.0:
		return 0.0
	return clampf(_cast_timer / _cast_duration, 0.0, 1.0)

func get_current_spell_id() -> int:
	return _current_spell_id

func is_school_locked(school: int) -> bool:
	return _school_lockouts.has(school) and _school_lockouts[school] > 0.0

func get_school_lockout_remaining(school: int) -> float:
	return _school_lockouts.get(school, 0.0)

# ---------------------------------------------------------------------------
# Cooldown tracking (per spell)
# ---------------------------------------------------------------------------
var _cooldowns: Dictionary = {}   # spell_id -> remaining

func _physics_process_cooldowns(delta: float) -> void:
	var expired: Array[int] = []
	for sid: int in _cooldowns:
		_cooldowns[sid] -= delta
		if _cooldowns[sid] <= 0.0:
			expired.append(sid)
	for sid: int in expired:
		_cooldowns.erase(sid)

func _start_cooldown(spell_id: int, duration: float) -> void:
	_cooldowns[spell_id] = duration

func is_on_cooldown(spell_id: int) -> bool:
	return _cooldowns.has(spell_id) and _cooldowns[spell_id] > 0.0

func get_cooldown_remaining(spell_id: int) -> float:
	return _cooldowns.get(spell_id, 0.0)

func get_cooldown_fraction(spell_id: int) -> float:
	var spell: GameData.SpellData = GameData.get_spell(spell_id)
	if spell == null:
		return 0.0
	var remaining: float = get_cooldown_remaining(spell_id)
	return clampf(remaining / spell.cooldown, 0.0, 1.0)

# ---------------------------------------------------------------------------
# Hit resolution (always called on server)
# ---------------------------------------------------------------------------
func _finish_cast() -> void:
	_is_casting = false
	var spell_id: int = _current_spell_id
	_current_spell_id = -1
	_cast_timer       = 0.0
	_cast_duration    = 0.0

	var spell: GameData.SpellData = GameData.get_spell(spell_id)
	if spell == null:
		return

	# Find current target on owner player
	var target: Node = _owner_player.get_current_target() if _owner_player.has_method("get_current_target") else null

	_resolve_hit(spell, _owner_player, target)
	_start_cooldown(spell_id, spell.cooldown)
	cast_completed.emit(spell_id)

## Server-authoritative hit validation via RPC.
## Called by Player when a cast finishes or an instant fires.
@rpc("any_peer", "call_local", "reliable")
func server_validate_hit(
	caster_path: NodePath,
	target_path: NodePath,
	spell_id: int
) -> void:
	# Only the server runs the validation logic
	if not multiplayer.is_server():
		return

	var caster: Node = get_node_or_null(caster_path)
	var target: Node = get_node_or_null(target_path)
	if caster == null or target == null:
		return

	var spell: GameData.SpellData = GameData.get_spell(spell_id)
	if spell == null:
		return

	# Distance check
	if caster is Node3D and target is Node3D:
		var dist: float = (caster as Node3D).global_position.distance_to(
			(target as Node3D).global_position
		)
		if dist > spell.range + 2.0:   # +2.0 tolerance for prediction lag
			push_warning("CastSystem: Hit rejected — out of range (%.1fm)" % dist)
			return

	# Line-of-sight check using server PhysicsServer3D raycast
	if caster is Node3D and target is Node3D:
		var space: PhysicsDirectSpaceState3D = (caster as Node3D).get_world_3d().direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			(caster as Node3D).global_position + Vector3.UP * 1.0,
			(target as Node3D).global_position + Vector3.UP * 1.0
		)
		query.exclude = [(caster as CollisionObject3D).get_rid() if caster is CollisionObject3D else RID()]
		query.collision_mask = 0b0001   # static geometry only
		var result: Dictionary = space.intersect_ray(query)
		if not result.is_empty():
			# Ray hit geometry before target — no line of sight
			push_warning("CastSystem: Hit rejected — no line-of-sight")
			return

	# All checks passed — apply hit on all clients
	apply_hit_rpc.rpc(target_path, spell_id)

@rpc("authority", "call_local", "reliable")
func apply_hit_rpc(target_path: NodePath, spell_id: int) -> void:
	var target: Node = get_node_or_null(target_path)
	if target == null:
		return
	var spell: GameData.SpellData = GameData.get_spell(spell_id)
	if spell == null:
		return
	_resolve_hit(spell, _owner_player, target)

func _resolve_hit(spell: GameData.SpellData, caster: Node, target: Node) -> void:
	if target == null:
		# Self-cast heals have no target requirement
		if spell.base_heal > 0.0 and caster.has_method("receive_heal"):
			caster.receive_heal(spell.base_heal)
			hit_landed.emit(caster, spell.id, 0.0, spell.base_heal)
		return

	# Target must not be on same team as caster for damage
	var caster_team: int = caster.get_meta("team", GameData.Team.NONE)
	var target_team: int = target.get_meta("team", GameData.Team.NONE)

	if spell.base_damage > 0.0 and caster_team != target_team:
		# Check if target is in dodge i-frames
		var is_invulnerable: bool = target.is_invulnerable() if target.has_method("is_invulnerable") else false
		if not is_invulnerable:
			# Apply stagger
			if spell.stagger_amount > 0.0 and target.has_method("receive_stagger"):
				target.receive_stagger(spell.stagger_amount)

			# Check interrupt
			if spell.causes_interrupt and target.has_method("get_cast_system"):
				var target_cast_sys: CastSystem = target.get_cast_system() as CastSystem
				if target_cast_sys and target_cast_sys.is_casting():
					# Lock the school of the spell being cast on the target
					var target_spell_id: int = target_cast_sys.get_current_spell_id()
					var target_spell: GameData.SpellData = GameData.get_spell(target_spell_id)
					var school_to_lock: int = target_spell.school if target_spell else -1
					target_cast_sys.interrupt_cast(school_to_lock)

			if target.has_method("receive_damage"):
				target.receive_damage(spell.base_damage)
			hit_landed.emit(target, spell.id, spell.base_damage, 0.0)
		else:
			push_warning("CastSystem: Damage nullified — target in i-frames")

	elif spell.base_heal > 0.0 and (caster_team == target_team or target == caster):
		if target.has_method("receive_heal"):
			target.receive_heal(spell.base_heal)
		hit_landed.emit(target, spell.id, 0.0, spell.base_heal)
