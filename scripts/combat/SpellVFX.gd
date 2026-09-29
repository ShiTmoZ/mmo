## scripts/combat/SpellVFX.gd
## Ashen Sanctum — Spell Visual Effects Manager
## Handles: Fireball, Frost Nova, Counterspell, Floating Combat Text (FCT)
## All effects are purely cosmetic — no game logic here.

extends Node

static var instance: Node = null

## ─── Static Bridge Methods ──────────────────────────────────────────────────
static func get_vfx() -> Node:
	return instance

static func spawn_hit_effect(arg1, arg2 = null, arg3 = null) -> void:
	var world_pos: Vector3 = arg1 if arg1 is Vector3 else (arg2 if arg2 is Vector3 else Vector3.ZERO)
	if instance != null and is_instance_valid(instance):
		instance.fireball_explosion(world_pos)
		instance.spawn_fct(world_pos + Vector3(0, 1.8, 0), 85.0, false, "fire")

static func spawn_frost_ring(arg1, arg2 = null, arg3 = null) -> void:
	var world_pos: Vector3 = arg1 if arg1 is Vector3 else (arg2 if arg2 is Vector3 else Vector3.ZERO)
	if instance != null and is_instance_valid(instance):
		instance.frost_nova_expand(world_pos)
		instance.spawn_fct(world_pos + Vector3(0, 1.8, 0), 45.0, false, "frost")

static func spawn_counterspell(arg1, arg2 = null) -> void:
	var world_pos: Vector3 = arg1 if arg1 is Vector3 else (arg2 if arg2 is Vector3 else Vector3.ZERO)
	if instance != null and is_instance_valid(instance):
		instance.counterspell_crack(world_pos)

## ─── FCT Label Pool ──────────────────────────────────────────────────────────
const FCT_POOL_SIZE: int = 24
var _fct_pool: Array[Label3D] = []
var _fct_index: int = 0

## ─── Scene References ─────────────────────────────────────────────────────────
@export var fct_parent: Node3D = null   ## Where to attach floating text
@export var screen_shake_camera: Camera3D = null

## ─── Shake State ─────────────────────────────────────────────────────────────
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _camera_rest_pos: Vector3 = Vector3.ZERO
var _camera_shake_origin: Node3D = null

## ─── Active Effects ───────────────────────────────────────────────────────────
## Tracks active effect nodes for cleanup
var _active_effects: Array[Node3D] = []

## ─── Lifecycle ───────────────────────────────────────────────────────────────
func _enter_tree() -> void:
	instance = self

func _ready() -> void:
	instance = self

func _process(delta: float) -> void:
	_tick_screen_shake(delta)

func _get_world_root() -> Node:
	if get_tree() == null:
		return null
	var cs = get_tree().current_scene
	if cs != null and is_instance_valid(cs) and cs is Node3D:
		return cs
	var root: Window = get_tree().root
	if root == null:
		return null
	var arena: Node = root.get_node_or_null("arena")
	if arena != null:
		return arena
	arena = root.get_node_or_null("Arena")
	if arena != null:
		return arena
	for child in root.get_children():
		if child is Node3D:
			return child
	return root

## ─── Public API ──────────────────────────────────────────────────────────────

## Spawn a floating damage number above world_position
func spawn_fct(world_position: Vector3, damage: float, is_crit: bool, school: String = "fire") -> void:
	var world_root: Node = _get_world_root()
	if world_root == null:
		return
	var lbl: Label3D = Label3D.new()
	lbl.font_size = 72 if is_crit else 52
	lbl.outline_size = 6
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.pixel_size = 0.003
	var text: String = str(int(damage))
	if is_crit:
		text = "!! " + text + " !!"
	lbl.text = text
	match school:
		"fire":    lbl.modulate = Color(1.0, 0.5, 0.0, 1.0)
		"frost":   lbl.modulate = Color(0.3, 0.9, 1.0, 1.0)
		"arcane":  lbl.modulate = Color(0.85, 0.3, 1.0, 1.0)
		_:         lbl.modulate = Color(1.0, 0.95, 0.1, 1.0) if is_crit else Color.WHITE

	world_root.add_child(lbl)
	lbl.global_position = world_position + Vector3(randf_range(-0.3, 0.3), 1.8, randf_range(-0.3, 0.3))

	var tween: Tween = lbl.create_tween()
	var rise_vec: Vector3 = lbl.global_position + Vector3(0.0, 2.2, 0.0)
	tween.tween_property(lbl, "global_position", rise_vec, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tween.finished.connect(lbl.queue_free)

## ─── Fireball VFX ────────────────────────────────────────────────────────────

## Called at cast start: particles gather at caster's hand position
func fireball_cast_buildup(hand_pos: Node3D) -> GPUParticles3D:
	var ps: GPUParticles3D = GPUParticles3D.new()
	ps.amount = 40
	ps.lifetime = 0.6
	ps.explosiveness = 0.3
	ps.randomness = 0.5
	ps.one_shot = false
	ps.emitting = true

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3
	mat.direction = Vector3.ZERO
	mat.spread = 180.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 2.0
	mat.linear_accel_min = -3.0
	mat.linear_accel_max = 0.0
	mat.gravity = Vector3(0.0, -0.5, 0.0)
	mat.scale_min = 0.05
	mat.scale_max = 0.18
	mat.color = Color(1.0, 0.55, 0.0, 1.0)
	mat.color_ramp = _make_fire_gradient()
	ps.process_material = mat

	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	var surf: StandardMaterial3D = StandardMaterial3D.new()
	surf.albedo_color = Color(1.0, 0.6, 0.1, 1.0)
	surf.emission_enabled = true
	surf.emission = Color(1.5, 0.6, 0.0, 1.0)
	surf.emission_energy_multiplier = 3.0
	surf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = surf
	ps.draw_pass_1 = mesh

	hand_pos.add_child(ps)
	_active_effects.append(ps)
	return ps

## Spawns the fireball projectile body (visual only; physics handled by caller)
func fireball_projectile(start_pos: Vector3) -> Node3D:
	var root: Node3D = Node3D.new()
	_get_world_root().add_child(root)
	root.global_position = start_pos

	# Core glow sphere
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.1, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.8, 0.7, 0.0, 1.0)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	sphere.material = mat
	mesh_inst.mesh = sphere
	root.add_child(mesh_inst)

	# Flame trail particles
	var trail: GPUParticles3D = GPUParticles3D.new()
	trail.amount = 60
	trail.lifetime = 0.5
	trail.explosiveness = 0.0
	trail.randomness = 0.4
	trail.emitting = true
	trail.local_coords = false

	var tmat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	tmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	tmat.emission_sphere_radius = 0.15
	tmat.direction = Vector3(0.0, 0.0, 1.0)  # Behind projectile
	tmat.spread = 30.0
	tmat.initial_velocity_min = 1.0
	tmat.initial_velocity_max = 4.0
	tmat.scale_min = 0.08
	tmat.scale_max = 0.25
	tmat.gravity = Vector3(0.0, 0.3, 0.0)
	tmat.color = Color(1.0, 0.4, 0.0, 1.0)
	tmat.color_ramp = _make_fire_gradient()
	trail.process_material = tmat

	var tmesh: SphereMesh = SphereMesh.new()
	tmesh.radius = 0.06
	tmesh.height = 0.12
	var tsurf: StandardMaterial3D = StandardMaterial3D.new()
	tsurf.emission_enabled = true
	tsurf.emission = Color(1.5, 0.5, 0.0, 1.0)
	tsurf.emission_energy_multiplier = 4.0
	tsurf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmesh.material = tsurf
	trail.draw_pass_1 = tmesh
	root.add_child(trail)

	_active_effects.append(root)
	return root

## Launches a flying fireball projectile from start_pos to target_pos
func launch_fireball(start_pos: Vector3, target_pos: Vector3, on_hit_callback: Callable = Callable()) -> void:
	var proj: Node3D = fireball_projectile(start_pos)
	var diff: Vector3 = target_pos - start_pos
	if diff.length_squared() > 0.01:
		proj.look_at(target_pos, Vector3.UP)

	var dist: float = start_pos.distance_to(target_pos)
	var travel_time: float = clampf(dist / 28.0, 0.2, 1.0)

	var tween: Tween = proj.create_tween()
	tween.tween_property(proj, "global_position", target_pos, travel_time).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func() -> void:
		fireball_explosion(target_pos)
		if on_hit_callback.is_valid():
			on_hit_callback.call()
		proj.queue_free()
	)

## Radial explosion at impact point + screen shake
func fireball_explosion(impact_pos: Vector3) -> void:
	trigger_screen_shake(0.45, 0.25)

	var ps: GPUParticles3D = GPUParticles3D.new()
	ps.amount = 120
	ps.lifetime = 1.0
	ps.explosiveness = 0.9
	ps.randomness = 0.4
	ps.one_shot = true
	ps.emitting = true

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.4
	mat.spread = 180.0
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 14.0
	mat.gravity = Vector3(0.0, -4.0, 0.0)
	mat.damping_min = 2.0
	mat.damping_max = 5.0
	mat.scale_min = 0.1
	mat.scale_max = 0.45
	mat.color = Color(1.0, 0.55, 0.0, 1.0)
	mat.color_ramp = _make_fire_gradient()
	ps.process_material = mat

	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	var surf: StandardMaterial3D = StandardMaterial3D.new()
	surf.emission_enabled = true
	surf.emission = Color(2.0, 0.8, 0.0, 1.0)
	surf.emission_energy_multiplier = 5.0
	surf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = surf
	ps.draw_pass_1 = mesh

	_get_world_root().add_child(ps)
	ps.global_position = impact_pos
	_auto_free_node(ps, 2.5)

	# Ring shockwave
	_spawn_ring_shockwave(impact_pos, Color(1.0, 0.6, 0.15, 0.7), 2.8, 0.8)

## ─── Frost Nova VFX ──────────────────────────────────────────────────────────

func frost_nova_expand(origin: Vector3) -> void:
	# Expanding ice ring
	var ring_inst: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.outer_radius = 0.2
	torus.inner_radius = 0.18
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.85, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.8, 1.2, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = mat
	ring_inst.mesh = torus
	_get_world_root().add_child(ring_inst)
	ring_inst.global_position = origin + Vector3.UP * 0.05
	ring_inst.rotation_degrees.x = 90.0

	var tween: Tween = create_tween()
	tween.tween_property(ring_inst, "scale", Vector3(5.0, 5.0, 5.0), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween.parallel().tween_property(ring_inst, "transparency", 1.0, 0.6)
	tween.tween_callback(ring_inst.queue_free)

	# Frost mist particles
	var ps: GPUParticles3D = GPUParticles3D.new()
	var pmat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = 0.5
	pmat.spread = 180.0
	pmat.initial_velocity_min = 2.0
	pmat.initial_velocity_max = 6.0
	pmat.gravity = Vector3(0.0, 0.3, 0.0)
	pmat.damping_min = 2.0
	pmat.damping_max = 4.0
	pmat.scale_min = 0.12
	pmat.scale_max = 0.4
	pmat.color = Color(0.5, 0.9, 1.0, 0.7)
	pmat.color_ramp = _make_frost_gradient()
	ps.process_material = pmat

	var smesh: SphereMesh = SphereMesh.new()
	smesh.radius = 0.08
	smesh.height = 0.16
	var smat: StandardMaterial3D = StandardMaterial3D.new()
	smat.emission_enabled = true
	smat.emission = Color(0.3, 0.8, 1.2, 1.0)
	smat.emission_energy_multiplier = 2.5
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smesh.material = smat
	ps.draw_pass_1 = smesh

	ps.amount = 80
	ps.lifetime = 2.0
	ps.explosiveness = 0.7
	ps.randomness = 0.5
	ps.one_shot = true
	ps.emitting = true

	_get_world_root().add_child(ps)
	ps.global_position = origin
	_auto_free_node(ps, 3.0)

	# Ice shards
	for i: int in range(12):
		var shard: MeshInstance3D = _spawn_ice_shard(origin, i)
		_auto_free_node(shard, 2.5)

func frost_nova_shatter(origin: Vector3) -> void:
	trigger_screen_shake(0.18, 0.12)
	var ps: GPUParticles3D = GPUParticles3D.new()
	ps.global_position = origin
	ps.amount = 50
	ps.lifetime = 1.2
	ps.explosiveness = 1.0
	ps.one_shot = true
	ps.emitting = true

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.spread = 180.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 10.0
	mat.gravity = Vector3(0.0, -9.8, 0.0)
	mat.scale_min = 0.05
	mat.scale_max = 0.25
	mat.color = Color(0.7, 0.95, 1.0, 0.9)
	ps.process_material = mat

	_get_world_root().add_child(ps)
	_auto_free_node(ps, 2.5)

func _spawn_ice_shard(origin: Vector3, index: int) -> MeshInstance3D:
	var shard: MeshInstance3D = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(0.08, randf_range(0.15, 0.5), 0.08)
	var smat: StandardMaterial3D = StandardMaterial3D.new()
	smat.albedo_color = Color(0.6, 0.9, 1.0, 0.75)
	smat.emission_enabled = true
	smat.emission = Color(0.2, 0.7, 1.2, 1.0)
	smat.emission_energy_multiplier = 2.0
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	prism.material = smat
	shard.mesh = prism

	var angle: float = (float(index) / 12.0) * TAU
	var radius: float = randf_range(0.5, 2.5)
	_get_world_root().add_child(shard)
	shard.global_position = origin + Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
	shard.rotation_degrees = Vector3(randf_range(-30.0, 30.0), rad_to_deg(angle), randf_range(-20.0, 20.0))

	var tween: Tween = create_tween()
	tween.tween_property(shard, "transparency", 1.0, 2.0).set_delay(0.5)
	tween.tween_callback(shard.queue_free)
	return shard

## ─── Counterspell VFX ────────────────────────────────────────────────────────

func counterspell_crack(target_pos: Vector3) -> void:
	trigger_screen_shake(0.2, 0.1)

	# Violet arcane crack burst
	var ps: GPUParticles3D = GPUParticles3D.new()
	ps.amount = 60
	ps.lifetime = 0.7
	ps.explosiveness = 0.95
	ps.one_shot = true
	ps.emitting = true

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.spread = 180.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 15.0
	mat.gravity = Vector3(0.0, -2.0, 0.0)
	mat.damping_min = 4.0
	mat.damping_max = 8.0
	mat.scale_min = 0.04
	mat.scale_max = 0.18
	mat.color = Color(0.7, 0.0, 1.0, 1.0)
	mat.color_ramp = _make_arcane_gradient()
	ps.process_material = mat

	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.10
	var surf: StandardMaterial3D = StandardMaterial3D.new()
	surf.emission_enabled = true
	surf.emission = Color(0.9, 0.0, 1.2, 1.0)
	surf.emission_energy_multiplier = 5.0
	surf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = surf
	ps.draw_pass_1 = mesh

	_get_world_root().add_child(ps)
	ps.global_position = target_pos + Vector3.UP * 1.2
	_auto_free_node(ps, 2.0)

	# Shatter glass shards (arcane color)
	for i: int in range(8):
		var shard: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(randf_range(0.05, 0.15), randf_range(0.05, 0.2), 0.01)
		var smat: StandardMaterial3D = StandardMaterial3D.new()
		smat.albedo_color = Color(0.7, 0.1, 1.0, 0.8)
		smat.emission_enabled = true
		smat.emission = Color(0.8, 0.0, 1.2, 1.0)
		smat.emission_energy_multiplier = 3.0
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		box.material = smat
		shard.mesh = box
		_get_world_root().add_child(shard)
		shard.global_position = target_pos + Vector3(
			randf_range(-0.5, 0.5), randf_range(0.8, 1.8), randf_range(-0.5, 0.5)
		)
		shard.rotation_degrees = Vector3(randf_range(-60.0, 60.0), randf_range(0.0, 360.0), randf_range(-60.0, 60.0))

		var tween: Tween = create_tween()
		var fall_pos: Vector3 = shard.global_position + Vector3(
			randf_range(-1.0, 1.0), -2.0, randf_range(-1.0, 1.0)
		)
		tween.tween_property(shard, "global_position", fall_pos, 0.6).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(shard, "transparency", 1.0, 0.6)
		tween.tween_callback(shard.queue_free)

## ─── Screen Shake ────────────────────────────────────────────────────────────

func trigger_screen_shake(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_timer = duration
	if screen_shake_camera != null and _camera_shake_origin == null:
		_camera_rest_pos = screen_shake_camera.position

func _tick_screen_shake(delta: float) -> void:
	if _shake_timer <= 0.0 or screen_shake_camera == null:
		return
	_shake_timer -= delta
	var t: float = _shake_timer / maxf(_shake_intensity, 0.001)
	var offset: Vector3 = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		0.0
	) * _shake_intensity * minf(t, 1.0)
	screen_shake_camera.position = _camera_rest_pos + offset
	if _shake_timer <= 0.0:
		screen_shake_camera.position = _camera_rest_pos
		_shake_intensity = 0.0

## ─── Ring Shockwave ──────────────────────────────────────────────────────────
func _spawn_ring_shockwave(origin: Vector3, color: Color, max_scale: float, duration: float) -> void:
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.outer_radius = 0.4
	torus.inner_radius = 0.35
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = mat
	ring.mesh = torus
	_get_world_root().add_child(ring)
	ring.global_position = origin + Vector3.UP * 0.1
	ring.rotation_degrees.x = 90.0

	var tween: Tween = create_tween()
	var s: float = max_scale
	tween.tween_property(ring, "scale", Vector3(s, s, s), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.parallel().tween_property(ring, "transparency", 1.0, duration)
	tween.tween_callback(ring.queue_free)

## ─── Gradient Helpers ────────────────────────────────────────────────────────
func _make_fire_gradient() -> GradientTexture1D:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 0.7, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 0.5, 1.0),
		Color(1.0, 0.55, 0.0, 1.0),
		Color(0.7, 0.1, 0.0, 0.6),
		Color(0.2, 0.05, 0.0, 0.0),
	])
	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = g
	return tex

func _make_frost_gradient() -> GradientTexture1D:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.6, 0.9, 1.0, 0.9),
		Color(0.2, 0.6, 0.85, 0.4),
		Color(0.0, 0.3, 0.6, 0.0),
	])
	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = g
	return tex

func _make_arcane_gradient() -> GradientTexture1D:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 0.8, 1.0, 1.0),
		Color(0.75, 0.1, 1.0, 1.0),
		Color(0.4, 0.0, 0.8, 0.5),
		Color(0.1, 0.0, 0.3, 0.0),
	])
	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = g
	return tex

## ─── Utility ─────────────────────────────────────────────────────────────────
func _auto_free_node(node: Node, delay: float) -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(node):
			node.queue_free()
	)

## Dodgeroll afterimage trail
func spawn_dodge_trail(body_mesh: MeshInstance3D, position: Vector3, rotation: Basis, color: Color = Color(0.5, 0.8, 1.0, 0.4)) -> void:
	var ghost: MeshInstance3D = MeshInstance3D.new()
	ghost.mesh = body_mesh.mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.material_override = mat
	_get_world_root().add_child(ghost)
	ghost.global_position = position
	ghost.global_transform.basis = rotation

	var tween: Tween = create_tween()
	tween.tween_property(ghost, "transparency", 1.0, 0.35)
	tween.tween_callback(ghost.queue_free)
