extends DirectionalLight3D

@export_group("Cycle Settings")
@export var cycle_duration: float = 70.0

@export_group("Environment Fill")
@export var world_environment: WorldEnvironment
@export var min_ambient_energy: float = 0.55  
@export var max_ambient_energy: float = 0.65

@export_group("Water Glow")
@export var water_mesh: MeshInstance3D
@export var max_water_glow: float = 0.5 

@export_group("Terrain Glow")
@export var terrain_node: Node3D
@export var max_path_glow: float = 1.5
@export var max_grass_glow: float = 1.2
@export var max_grass_mesh_glow: float = 1.2

@export_group("Rock Glow")
@export var max_rock_glow: float = 2.0

@export_group("Tree Glow")
@export var max_tree_glow: float = 2.0

@export_group("Player Night Light")
@export var player_light: OmniLight3D
@export var max_player_light_energy: float = 0.8

var elapsed: float = 0.0
var _water_material: ShaderMaterial = null
var _terrain_material: Resource = null
var _grass_material: ShaderMaterial = null
var _rock_materials: Array[ShaderMaterial] = []
var _tree_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	if water_mesh != null:
		_water_material = water_mesh.get_active_material(0) as ShaderMaterial

	if terrain_node != null:
		_terrain_material = terrain_node.get("material")

	if _terrain_material == null:
		var nav_terrains = get_tree().get_nodes_in_group("terrain_navigation")
		for tn in nav_terrains:
			var mat = tn.get("material")
			if mat != null:
				_terrain_material = mat
				break

	var rumput_scene = load("res://Distribute/Rumput.tscn") as PackedScene
	if rumput_scene:
		var state = rumput_scene.get_state()
		for i in range(state.get_node_count()):
			for p_idx in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, p_idx) == "material_override":
					_grass_material = state.get_node_property_value(i, p_idx) as ShaderMaterial
					break
			if _grass_material != null:
				break

	_collect_rock_materials()
	_collect_tree_materials()

	# Terapkan kondisi waktu saat scene dibuka (di editor maupun runtime).
	_apply_time(fmod(elapsed, cycle_duration) / cycle_duration, 0.1)

func _collect_rock_materials() -> void:
	var rocks = get_tree().get_nodes_in_group("glowing_rock")
	for r in rocks:
		if r is MeshInstance3D:
			var mat = r.get_active_material(0) as ShaderMaterial
			if mat and not _rock_materials.has(mat):
				_rock_materials.append(mat)

	if _rock_materials.is_empty():
		var rock_scene = load("res://scenes/Rock/draggable_rock.tscn") as PackedScene
		if rock_scene:
			var state = rock_scene.get_state()
			for i in range(state.get_node_count()):
				for p_idx in range(state.get_node_property_count(i)):
					if state.get_node_property_name(i, p_idx) == "material_override":
						var mat = state.get_node_property_value(i, p_idx) as ShaderMaterial
						if mat and not _rock_materials.has(mat):
							_rock_materials.append(mat)
						break
				if not _rock_materials.is_empty():
					break

var _update_timer: float = 0.0

func _process(delta: float) -> void:
	elapsed += delta
	var t: float = fmod(elapsed, cycle_duration) / cycle_duration
	_apply_time(t, delta)

func _apply_time(t: float, delta: float = 0.1) -> void:
	rotation_degrees.x = t * 360.0 - 90.0

	var col: Color
	if t < 0.05:
		col = Color(1.0, 0.6, 0.35).lerp(Color(1.0, 0.92, 0.82), t / 0.05)
	elif t < 0.25:
		col = Color(1.0, 0.92, 0.82).lerp(Color(1.0, 1.0, 0.98), (t - 0.05) / 0.20)
	elif t < 0.35:
		col = Color(1.0, 1.0, 0.98).lerp(Color(1.0, 0.85, 0.55), (t - 0.25) / 0.10)
	elif t < 0.5:
		col = Color(1.0, 0.85, 0.55).lerp(Color(1.0, 0.45, 0.15), (t - 0.35) / 0.15)
	elif t < 0.55:
		col = Color(1.0, 0.45, 0.15).lerp(Color(0.15, 0.18, 0.35), (t - 0.5) / 0.05)
	elif t < 0.95:
		col = Color(0.15, 0.18, 0.35).lerp(Color(0.18, 0.2, 0.38), (t - 0.55) / 0.40)
	else:
		col = Color(0.18, 0.2, 0.38).lerp(Color(1.0, 0.6, 0.35), (t - 0.95) / 0.05)

	light_color = col

	# Energi Cahaya Matahari / Bulan
	var energy: float
	if t < 0.05:
		energy = lerpf(0.3, 0.8, t / 0.05)
	elif t < 0.10:
		energy = lerpf(0.8, 1.2, (t - 0.05) / 0.05)
	elif t < 0.40:
		energy = 1.2
	elif t < 0.50:
		energy = lerpf(1.2, 0.6, (t - 0.40) / 0.10)
	elif t < 0.55:
		energy = lerpf(0.6, 0.15, (t - 0.50) / 0.05)
	elif t < 0.95:
		energy = 0.55
	else:
		energy = lerpf(0.55, 0.3, (t - 0.95) / 0.05)

	light_energy = energy
	
	# Throttle update material / shader / ambient (10 kali per detik sudah sangat halus dan hemat baterai)
	_update_timer += delta
	if _update_timer >= 0.1:
		_update_timer = 0.0
		_update_ambient_light(t)
		_update_water_glow(t)
		_update_terrain_glow(t)
		_update_rock_glow(t)
		_update_tree_glow(t)
		_update_player_light(t)

func _update_ambient_light(t: float) -> void:
	if world_environment == null or world_environment.environment == null:
		return
	
	var amb_energy: float = max_ambient_energy
	if t >= 0.45 and t < 0.55:
		amb_energy = lerpf(max_ambient_energy, min_ambient_energy, (t - 0.45) / 0.10)
	elif t >= 0.55 and t < 0.90:
		amb_energy = min_ambient_energy
	elif t >= 0.90:
		amb_energy = lerpf(min_ambient_energy, max_ambient_energy, (t - 0.90) / 0.10)
		
	world_environment.environment.ambient_light_energy = amb_energy

func _update_water_glow(t: float) -> void:
	if _water_material == null:
		return

	var glow: float = 0.0
	if t >= 0.42 and t < 0.50:
		glow = lerpf(0.0, max_water_glow, (t - 0.42) / 0.08)
	elif t >= 0.50 and t < 0.95:
		glow = max_water_glow
	elif t >= 0.95:
		glow = lerpf(max_water_glow, 0.0, (t - 0.95) / 0.05)
	else:
		glow = 0.0

	_water_material.set_shader_parameter("night_glow_strength", glow)

func _update_terrain_glow(t: float) -> void:
	if _terrain_material == null and _grass_material == null:
		return

	var glow_factor: float = 0.0
	if t >= 0.30 and t < 0.40:
		# Sore hari -> perlahan menyala
		glow_factor = (t - 0.30) / 0.10
	elif t >= 0.40 and t < 0.95:
		# Sore sampai malam & fajar -> menyala stabil penuh
		glow_factor = 1.0
	elif t >= 0.95:
		# Menjelang pagi -> perlahan padam
		glow_factor = lerpf(1.0, 0.0, (t - 0.95) / 0.05)
	else:
		# Siang hari -> mati
		glow_factor = 0.0

	var path_glow: float = max_path_glow * glow_factor
	var grass_glow: float = max_grass_glow * glow_factor
	var grass_mesh_glow: float = max_grass_mesh_glow * glow_factor

	if _terrain_material != null:
		if _terrain_material.has_method("set_shader_param"):
			_terrain_material.set_shader_param("path_glow_intensity", path_glow)
			_terrain_material.set_shader_param("grass_glow_intensity", grass_glow)
		elif _terrain_material.has_method("set_shader_parameter"):
			_terrain_material.set_shader_parameter("path_glow_intensity", path_glow)
			_terrain_material.set_shader_parameter("grass_glow_intensity", grass_glow)
		elif _terrain_material is ShaderMaterial:
			_terrain_material.set_shader_parameter("path_glow_intensity", path_glow)
			_terrain_material.set_shader_parameter("grass_glow_intensity", grass_glow)

	if _grass_material != null:
		_grass_material.set_shader_parameter("emission_strength", grass_mesh_glow)

func _update_rock_glow(t: float) -> void:
	if _rock_materials.is_empty():
		_collect_rock_materials()
	if _rock_materials.is_empty():
		return

	var glow: float = 0.0
	# Nyala dari sore (t >= 0.30) sampai ketemu pagi (t < 0.95)
	if t >= 0.30 and t < 0.40:
		# Mulai sore hari -> perlahan menyala
		glow = lerpf(0.0, max_rock_glow, (t - 0.30) / 0.10)
	elif t >= 0.40 and t < 0.95:
		# Sepanjang sore sampai malam & fajar -> menyala stabil
		glow = max_rock_glow
	elif t >= 0.95:
		# Menjelang pagi -> perlahan padam
		glow = lerpf(max_rock_glow, 0.0, (t - 0.95) / 0.05)
	else:
		# Siang hari -> mati
		glow = 0.0

	for mat in _rock_materials:
		mat.set_shader_parameter("night_glow_strength", glow)

func _collect_tree_materials() -> void:
	var tree_scenes = [
		"res://Distribute/Pohon1.tscn",
		"res://Distribute/Pohon2.tscn",
		"res://Distribute/Pohon3.tscn"
	]
	for sc_path in tree_scenes:
		var sc = load(sc_path) as PackedScene
		if sc:
			var inst = sc.instantiate()
			if inst:
				var mesh_nodes: Array[Node] = inst.find_children("*", "MeshInstance3D", true, false)
				if inst is MeshInstance3D:
					mesh_nodes.append(inst)
				for mn in mesh_nodes:
					if mn is MeshInstance3D:
						for s in range(mn.get_surface_override_material_count()):
							var mat = mn.get_active_material(s)
							if mat is StandardMaterial3D and mat.resource_name.begins_with("Bark"):
								if not _tree_materials.has(mat):
									_tree_materials.append(mat)
						if mn.mesh:
							for s in range(mn.mesh.get_surface_count()):
								var mat = mn.mesh.surface_get_material(s)
								if mat is StandardMaterial3D and mat.resource_name.begins_with("Bark"):
									if not _tree_materials.has(mat):
										_tree_materials.append(mat)
				inst.queue_free()

	# Also check terrain_node assets if assigned
	if terrain_node != null and terrain_node.get("assets") != null:
		var assets = terrain_node.get("assets")
		if assets.has_method("get_mesh_count") and assets.has_method("get_mesh_asset"):
			for i in range(assets.get_mesh_count()):
				var ma = assets.get_mesh_asset(i)
				if ma:
					var m = ma.get("mesh")
					if m is Mesh:
						for s in range(m.get_surface_count()):
							var mat = m.surface_get_material(s)
							if mat is StandardMaterial3D and mat.resource_name.begins_with("Bark"):
								if not _tree_materials.has(mat):
									_tree_materials.append(mat)

func _update_tree_glow(t: float) -> void:
	if _tree_materials.is_empty():
		_collect_tree_materials()
	if _tree_materials.is_empty():
		return

	var glow: float = 0.0
	# Nyala dari sore/malam (t >= 0.30) sampai fajar (t < 0.95), padam saat pagi (t >= 0.95)
	if t >= 0.30 and t < 0.40:
		# Sore hari -> perlahan menyala
		glow = lerpf(0.0, max_tree_glow, (t - 0.30) / 0.10)
	elif t >= 0.40 and t < 0.95:
		# Malam penuh sampai fajar -> menyala stabil
		glow = max_tree_glow
	elif t >= 0.95:
		# Menjelang pagi -> perlahan padam
		glow = lerpf(max_tree_glow, 0.0, (t - 0.95) / 0.05)
	else:
		# Siang hari -> mati
		glow = 0.0

	for mat in _tree_materials:
		mat.emission_energy_multiplier = glow

func _update_player_light(t: float) -> void:
	if player_light == null:
		return

	var target_energy: float = 0.0

	# Sore mulai redup ke malam (t: 0.25 - 0.50) -> lampu perlahan menyala
	if t >= 0.25 and t < 0.50:
		var factor: float = (t - 0.25) / 0.25
		target_energy = lerpf(0.0, max_player_light_energy, factor)
	# Malam penuh (t: 0.50 - 0.95) -> lampu menyala stabil
	elif t >= 0.50 and t < 0.95:
		target_energy = max_player_light_energy
	# Fajar menjelang pagi (t: 0.95 - 1.0) -> lampu perlahan mati
	elif t >= 0.95:
		var factor: float = (t - 0.95) / 0.05
		target_energy = lerpf(max_player_light_energy, 0.0, factor)
	else:
		target_energy = 0.0

	player_light.light_energy = target_energy
	player_light.visible = target_energy > 0.01

func transition_to_night(duration: float = 10.0) -> void:
	var current_t: float = fmod(elapsed, cycle_duration) / cycle_duration
	var target_t: float = 0.65
	var target_elapsed = target_t * cycle_duration
	if target_elapsed < elapsed:
		target_elapsed += cycle_duration
	var tween = create_tween()
	tween.tween_property(self, "elapsed", target_elapsed, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if GameManager:
		GameManager.garden_night_active = true

func is_night_time() -> bool:
	var t: float = fmod(elapsed, cycle_duration) / cycle_duration
	return t >= 0.55 and t <= 0.90
