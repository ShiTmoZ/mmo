## scripts/combat/SpellVFX.gd
## Lightweight procedural visual effects for spells and impacts
extends RefCounted

static func spawn_hit_effect(tree: SceneTree, target_pos: Vector3, school: int) -> void:
	if tree == null:
		return
	var root: Node = tree.current_scene
	if root == null:
		return

	# Determine color scheme: 1=Fire, 2=Frost, 3=Arcane, 4=Holy
	var fx_color: Color = Color(1.0, 0.45, 0.1) # Fire default
	if school == 2:
		fx_color = Color(0.2, 0.85, 1.0)
	elif school == 3:
		fx_color = Color(0.8, 0.3, 1.0)
	elif school == 4:
		fx_color = Color(1.0, 0.95, 0.5)

	# 1. Burst light
	var light := OmniLight3D.new()
	light.light_color = fx_color
	light.light_energy = 5.0
	light.omni_range = 10.0
	light.global_position = target_pos + Vector3(0.0, 1.0, 0.0)
	root.add_child(light)

	# 2. Expanding energy shockwave
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	mesh_inst.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = fx_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.global_position = target_pos + Vector3(0.0, 1.0, 0.0)
	root.add_child(mesh_inst)

	# 3. Animate burst
	var tween: Tween = tree.create_tween().set_parallel(true)
	tween.tween_property(light, "light_energy", 0.0, 0.3)
	tween.tween_property(mesh_inst, "scale", Vector3(3.0, 3.0, 3.0), 0.3)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(func():
		if is_instance_valid(light):
			light.queue_free()
		if is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
	)

static func spawn_frost_ring(tree: SceneTree, center_pos: Vector3, radius: float = 6.0) -> void:
	if tree == null:
		return
	var root: Node = tree.current_scene
	if root == null:
		return

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.6
	ring.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.set_surface_override_material(0, mat)
	ring.global_position = center_pos + Vector3(0.0, 0.1, 0.0)
	root.add_child(ring)

	var tween: Tween = tree.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.4)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tween.chain().tween_callback(func():
		if is_instance_valid(ring):
			ring.queue_free()
	)
