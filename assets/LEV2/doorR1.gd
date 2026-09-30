extends Area3D

@export var marker_inside: Marker3D
@export var marker_outside: Marker3D
@export var interact_action: String = "interact"

@export_group("Room Darkness Control")
@export var world_environment: WorldEnvironment
@export var inside_ambient_energy: float = 0.05   # Sangat gelap saat di dalam
@export var outside_ambient_energy: float = 0.55  # Normal saat di luar

# Variabel ini diakses langsung oleh lever.gd tanpa butuh class_name
@export var is_room_unlocked: bool = false

var current_player: Node3D = null


var label_3d: Label3D = null

func _ready() -> void:
	add_to_group("doors")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	label_3d = Label3D.new()
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.font_size = 48
	label_3d.outline_size = 8
	label_3d.outline_modulate = Color(0, 0, 0, 1)
	label_3d.position = Vector3(0, 2.5, 0)
	add_child(label_3d)
	label_3d.hide()


func is_player_inside() -> bool:
	return current_player != null


func _unhandled_input(event: InputEvent) -> void:
	# Jangan proses input pintu saat dialog sedang berjalan
	if StoryManager != null and StoryManager.dialogue_box != null and StoryManager.dialogue_box.visible:
		return
	if current_player:
		if (InputMap.has_action(interact_action) and event.is_action_pressed(interact_action)) or \
		   (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E):
			teleport_player()


func _on_body_entered(body: Node3D) -> void:
	if body is StaticBody3D:
		return
	if body is CharacterBody3D or body.is_in_group("player") or "player" in body.name.to_lower():
		current_player = body
		if label_3d:
			var is_mobile := SettingsManager != null and SettingsManager.is_mobile_controls_active()
			label_3d.text = "Pindah Ruangan (Tekan Aksi)" if is_mobile else "Pindah Ruangan [E]"
			label_3d.show()


func _on_body_exited(body: Node3D) -> void:
	if body == current_player:
		current_player = null
		if label_3d:
			label_3d.hide()


func teleport_player() -> void:
	if not marker_inside or not marker_outside or not current_player:
		print_rich("[color=red][PINTU][/color] Pastikan kedua marker sudah diisi di Inspector!")
		return

	# Urutan misi: setiap pintu ruangan terkunci sampai tugas sebelumnya selesai
	if not _door_gate_ok():
		_show_locked_notice()
		return

	var dist_to_inside = current_player.global_position.distance_to(marker_inside.global_position)
	var dist_to_outside = current_player.global_position.distance_to(marker_outside.global_position)

	# Tentukan apakah player masuk ke dalam atau keluar
	var is_entering_inside: bool = dist_to_outside < dist_to_inside
	var target_marker = marker_inside if is_entering_inside else marker_outside
	var entering_room: bool = (target_marker == _inside_marker())

	# Blokir Rion keluar dari dalam ruangan jika puzzle ruangan belum selesai
	if not entering_room:
		var room_k := _room_key()
		if room_k.contains("glass") and not GameManager.terminal_puzzle_done:
			if StoryManager and StoryManager.has_method("start_dialogue"):
				StoryManager.start_dialogue([
					"Rallux: \"Eits, Rion! Jangan keluar dulu ya. Kabel terminalnya harus kita betulkan dulu supaya aliran listrik kembali aktif!\"",
					"Rion: \"Oh iya, Tuan Rallux! Aku betulkan kabel terminalnya sekarang!\""
				], "Rallux")
			return
		elif room_k.contains("crusher") and not GameManager.solved_levers.get("CrusherRoom_Lever", false):
			if StoryManager and StoryManager.has_method("start_dialogue"):
				StoryManager.start_dialogue([
					"Rallux: \"Tunggu dulu, Rion! Jangan keluar dulu, kita harus tarik tuas lampu di ruangan ini sampai seratus persen dulu supaya mesin daur ulang aktif!\"",
					"Rion: \"Siap, Tuan Rallux! Aku tarik tuas lampunya dulu sampai seratus persen!\""
				], "Rallux")
			return
		elif room_k.contains("onaprogram") and not GameManager.solved_levers.get("OnaProgramRoom_Lever", false):
			if StoryManager and StoryManager.has_method("start_dialogue"):
				StoryManager.start_dialogue([
					"Rallux: \"Eits, Rion! Ona masih belum selesai mengisi daya dan tuas lampunya belum dinyalakan. Ayo kita nyalakan tuasnya dulu sampai seratus persen!\"",
					"Rion: \"Baik, Tuan Rallux! Aku nyalakan tuas lampu untuk Ona dulu!\""
				], "Rallux")
			return

	current_player.global_position = target_marker.global_position
	current_player.global_rotation.y = target_marker.global_rotation.y

	var scene := get_tree().current_scene

	# Snap kamera seketika ke belakang pemain di ruangan baru agar tidak tersangkut / menabrak dinding antar ruangan
	var cam_rig: Node3D = scene.find_child("CameraRig", true, false) as Node3D if scene else null
	if cam_rig == null:
		cam_rig = get_tree().get_first_node_in_group("camera_rig") as Node3D
	if cam_rig and cam_rig.has_method("snap_to_target"):
		cam_rig.zoom_distance = 6.8
		cam_rig.snap_to_target()

	# Bawa Ona ikut berpindah ruangan HANYA jika Ona tidak sedang istirahat baterai
	if scene and not GameManager.ona_hold_position:
		var ona := scene.find_child("Ona", true, false) as Node3D
		if ona and ona != current_player:
			ona.global_position = target_marker.global_position + Vector3(1.6, 0.0, 0.8)
			ona.global_rotation.y = target_marker.global_rotation.y

	_apply_room_lighting(is_entering_inside)

	# Jika Ona tidak sedang istirahat di dok, posisikan Ona di depan pintu ruangan
	if not GameManager.ona_hold_position:
		GameManager.ona_hold_position = entering_room
	_play_room_intro(target_marker, entering_room)

func _inside_marker() -> Node3D:
	# Untuk GlassRoom, sisi "dalam" (Energy Core) ada di marker_outside
	if _room_key().contains("glass"):
		return marker_outside
	return marker_inside

func _play_room_intro(marker: Node3D, entering_room: bool) -> void:
	if not entering_room:
		return
	var room := _room_key()
	var already: bool = GameManager.room_intro_seen.get(room, false)
	GameManager.room_intro_seen[room] = true

	# Ona selalu diposisikan diam di depan pintu jika sedang mengikuti Rion
	if not GameManager.ona_hold_position:
		_position_ona_at_door(marker)

	if already:
		return
	if room.contains("crusher"):
		StoryManager.start_dialogue([
			"Rallux: \"Nah, ini dia Ruang Crusher kita, Rion. Di ruangan inilah semua bongkahan logam rongsokan, serpihan mesin tua, dan sisa perkakas bengkel dihancurkan untuk didaur ulang menjadi suku cadang baru yang bersih dan bermanfaat.\"",
			"Rion: \"Wah, keren banget! Jadi barang-barang yang kelihatan rusak dan berantakan bisa diolah lagi jadi berguna di sini ya, Tuan Rallux!\"",
			"Rallux: \"Tepat sekali! Tapi karena sistem dayanya terputus akibat getaran kemarin, lampu dan mesin daur ulang di sini ikut padam. Ruangannya jadi gelap gulita.\"",
			"Rion: \"Tenang saja, Tuan Rallux! Aku akan tarik tuas lampu di depan sana sampai seratus persen supaya mesinnya menyala dan ruangannya kembali terang benderang!\"",
			"Rallux: \"Bagus sekali semangatmu, Kapten! Tarik tuasnya sampai seratus persen ya!\""
		], "Rallux")
	elif room.contains("onaprogram"):
		StoryManager.start_dialogue([
			"Rallux: \"Selamat datang di Ruang Perakitan & Pemrograman Ona, Rion. Ruangan ini adalah laboratorium khusus tempat bodi robot Ona dirakit, sirkuit memorinya dipelihara, dan dok pengisian baterai utamanya berada.\"",
			"Rion: \"Ooh, jadi ini tempat kelahiran Ona sekaligus ruang servis dan istirahatnya ya, Tuan Rallux!\"",
			"Rallux: \"Betul sekali. Di sinilah prosesor Ona didinginkan dan memorinya ditata ulang setelah lelah beraktivitas. Lihat, Ona sedang beristirahat di dok pengisian daya di samping panel kontrol itu.\"",
			"Rion: \"Ona kelihatan pulas banget... Ayo kita nyalakan tuas lampu di ruangan ini supaya daya dok pengisian baterainya pulih penuh dan Ona bisa segera bangun!\"",
			"Rallux: \"Pintar sekali, Rion! Ayo kita hidupkan tuas lampunya sampai seratus persen!\""
		], "Rallux")
	elif room.contains("glass"):
		StoryManager.start_dialogue([
			"Rallux: \"Nah, kita sudah sampai di Ruang Kontrol Daya. Banyak kabel dan panel energi di sini.\"",
			"Rallux: \"Ayo ke depan terminal daya di sana, Rion. Kita periksa sambungan kabelnya bersama!\"",
			"Rion: \"Siap, Tuan Rallux! Aku segera ke terminal daya!\""
		], "Rallux")

func _position_ona_at_door(marker: Node3D) -> void:
	# Arah masuk ruangan = dari sisi luar ke sisi dalam pintu
	var inside := _inside_marker()
	var outside: Node3D = marker_inside if inside == marker_outside else marker_outside
	if outside == null:
		outside = marker
	var dir: Vector3 = inside.global_position - outside.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -marker.global_transform.basis.z
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, 0.0, -1.0)
	dir = dir.normalized()
	var perp: Vector3 = Vector3(-dir.z, 0.0, dir.x)

	# Geser sedikit ke samping + masuk ke dalam ruangan supaya pintu tidak terhalang
	if current_player:
		current_player.global_position = marker.global_position + dir * 2.2
		_snap_to_ground(current_player)

	var scene := get_tree().current_scene
	var ona: Node3D = scene.find_child("Ona", true, false) if scene else null
	if ona and current_player:
		ona.global_position = current_player.global_position + perp * 2.0
		ona.rotation.y = atan2(-dir.x, -dir.z)
		_snap_to_ground(ona)
		if ona.has_method("play_animation"):
			ona.play_animation("idle")
	var rion_mesh = current_player.get_node_or_null("RionMesh") if current_player else null
	if rion_mesh:
		rion_mesh.rotation.y = atan2(dir.x, dir.z)

func _snap_to_ground(node: Node3D) -> void:
	# Cari permukaan lantai supaya Ona tidak melayang
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var from_pos: Vector3 = node.global_position + Vector3(0.0, 4.0, 0.0)
	var to_pos: Vector3 = node.global_position - Vector3(0.0, 8.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = 1
	query.collide_with_areas = false
	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty():
		var p: Vector3 = node.global_position
		p.y = result["position"].y
		node.global_position = p

func _room_key() -> String:
	if name == "GlassRoom":
		return "glassroom"
	return get_parent().name.to_lower()

func _door_gate_ok() -> bool:
	var room := _room_key()
	if room.contains("glass"):
		# Ruang Kontrol Daya (Glass Room): dibuka setelah bengkel selesai dirapikan (Unpacking)
		return GameManager.unpacking_completed
	if room.contains("crusher"):
		# Ruang Crusher: dibuka setelah kabel terminal di Glass Room selesai dibetulkan
		return GameManager.terminal_puzzle_done
	if room.contains("onaprogram"):
		# Ruang Ona Program: dibuka setelah Tuas Crusher Room ditarik
		return GameManager.solved_levers.get("CrusherRoom_Lever", false)
	return true

func _show_locked_notice() -> void:
	if label_3d:
		label_3d.text = "Terkunci"
		label_3d.show()
	if StoryManager == null or StoryManager.dialogue_box == null:
		return
	var room := _room_key()
	var lines: Array[String]
	var speaker: String = "Rallux"
	if room.contains("glass"):
		# Larangan saat fase unpacking (sebelum bengkel rapi) disampaikan oleh Ona.
		lines = [
			"Ona: \"Eits, Rion! Jangan masuk dulu. Ayo kita selesaikan merapikan perkakas di rak bengkel dulu sebelum ke Ruang Kontrol Daya!\"",
			"Rion: \"Oh, iya, Ona! Aku bereskan rak bengkelnya dulu ya!\""
		]
		speaker = "Ona"
	elif room.contains("crusher"):
		lines = [
			"Rallux: \"Pintu Ruang Crusher masih terkunci. Kita harus membetulkan kabel terminal di Ruang Kontrol Daya dulu ya, Rion!\"",
			"Rion: \"Baik, Tuan Rallux! Ayo kita ke Ruang Kontrol Daya dulu!\""
		]
	elif room.contains("onaprogram"):
		lines = [
			"Rallux: \"Pintu Ruang Perakitan Ona masih terkunci. Kita nyalakan dulu tuas lampu di Ruang Crusher ya!\"",
			"Rion: \"Siap! Aku nyalakan tuas Ruang Crusher dulu supaya dayanya tersambung ke Ruang Perakitan Ona!\""
		]
	else:
		lines = ["Rion: \"Pintu ini masih terkunci.\""]
		speaker = "Rion"
	StoryManager.start_dialogue(lines, speaker)


func _apply_room_lighting(is_inside: bool) -> void:
	if not world_environment or not world_environment.environment:
		return

	var room := _room_key()
	var target_energy: float = outside_ambient_energy

	if is_inside:
		if room.contains("crusher"):
			var crusher_solved: bool = GameManager.solved_levers.get("CrusherRoom_Lever", false)
			target_energy = 0.7 if (is_room_unlocked or crusher_solved) else inside_ambient_energy
		elif room.contains("onaprogram"):
			var ona_solved: bool = GameManager.solved_levers.get("OnaProgramRoom_Lever", false)
			target_energy = 0.7 if (is_room_unlocked or ona_solved) else inside_ambient_energy
		else:
			target_energy = outside_ambient_energy
	else:
		target_energy = outside_ambient_energy

	var tween = create_tween()
	tween.tween_property(world_environment.environment, "ambient_light_energy", target_energy, 0.4)
