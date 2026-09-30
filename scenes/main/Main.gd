extends Node3D

signal _choice_selected(index: int)
signal _text_input_submitted(text: String)

const BGM_LEVEL1_EXPLORATION = preload("res://assets/audio/bgm/meditation_main.mp3")

func _current_level_name() -> String:
	if not scene_file_path.is_empty():
		return scene_file_path.get_file().get_basename()
	var current := get_tree().current_scene if get_tree() else null
	if current:
		if not current.scene_file_path.is_empty():
			return current.scene_file_path.get_file().get_basename()
		return String(current.name)
	return ""

func _ready() -> void:
	if AudioManager:
		AudioManager.play_bgm(BGM_LEVEL1_EXPLORATION, 2.0, -4.0)
		# Angin hanya untuk area outdoor (LEV1). Di LEV2 (interior) dimatikan.
		if _current_level_name() == "LEV1":
			AudioManager.play_ambience(AudioManager.AMBIENCE_WIND, 2.0, -8.0)
		else:
			AudioManager.stop_ambience(2.0)

	# Cari node WirePuzzle & HUD secara dinamis
	var wire_puzzle_node = find_child("WirePuzzle", true, false)
	var dialogue_node = find_child("DialogueBox", true, false)
	if dialogue_node == null:
		dialogue_node = find_child("HUD", true, false)
	
	# Inisialisasi ke StoryManager
	StoryManager.init(dialogue_node, null, wire_puzzle_node)

	# Kalau scene ini dimuat dari save (Continue / Load Game), jangan ulang intro:
	# langsung pasang state gameplay supaya pemain muncul di posisi terakhir.
	if GameManager.skip_intro_on_load:
		GameManager.skip_intro_on_load = false
		_setup_gameplay_state()
		return

	# Jalankan intro roket HANYA jika scene ini memiliki roket & kamera roket DAN belum pernah ke bengkel
	if has_node("RocketCamera") and has_node("RionCapsule/AnimationPlayer") and not GameManager.has_visited_workshop:
		_play_rocket_intro()
	elif has_node("StoryPointing2") and has_node("Rallux") and not GameManager.has_visited_workshop:
		_play_workshop_intro()
	elif has_node("StoryPointing2") and has_node("Rallux") and GameManager.sleep_transition_done and not GameManager.r1_morning_intro_done:
		_play_r1_morning_intro()
	else:
		_setup_gameplay_state()

func _setup_gameplay_state() -> void:
	var player: CharacterBody3D = find_child("Player", true, false) as CharacterBody3D
	var camera_rig = find_child("CameraRig", true, false)
	var hud = find_child("HUD", true, false)

	# Pastikan Player aktif, terlihat, dan collision aktif
	if player:
		player.visible = true
		player.set_physics_process(true)
		player.set_process_unhandled_input(true)
		var col = player.find_child("CollisionShape3D", true, false)
		if col:
			col.set_deferred("disabled", false)
		
		# Ambil override spawn jika ada
		var scene_str = ""
		if owner and owner.scene_file_path:
			scene_str = owner.scene_file_path
		elif get_tree() and get_tree().current_scene:
			scene_str = get_tree().current_scene.scene_file_path
			if scene_str == "":
				scene_str = get_tree().current_scene.name
		if scene_str != "":
			var override_pos = GameManager.consume_spawn_override_for(scene_str)
			if override_pos != Vector3.ZERO:
				player.global_position = override_pos
				if "last_safe_position" in player:
					player.last_safe_position = override_pos

		player.rotation = Vector3.ZERO
		var rion_mesh = player.get_node_or_null("RionMesh")
		if rion_mesh:
			rion_mesh.rotation = Vector3.ZERO

	# Pasang posisi Ona tersimpan (kalau ada). Di LEV1 Ona sudah mengonsumsi
	# override ini sendiri di ona.gd; di LEV2/R1 baru dipakai di sini.
	var ona_node := find_child("Ona", true, false) as Node3D
	if ona_node:
		var ona_pos := GameManager.consume_ona_override()
		if ona_pos != Vector3.ZERO:
			ona_node.global_position = ona_pos

	var rallux_node := find_child("Rallux", true, false) as Node3D
	if rallux_node:
		var rallux_pos := GameManager.consume_rallux_override()
		if rallux_pos != Vector3.ZERO:
			rallux_node.visible = true
			rallux_node.global_position = rallux_pos
			if rallux_node.has_method("play_animation"):
				rallux_node.play_animation("idle")

	# Pastikan Kamera Player aktif & snap ke target
	if camera_rig:
		camera_rig.set_physics_process(true)
		camera_rig.set_process(true)
		camera_rig.set_process_unhandled_input(true)
		var player_cam = camera_rig.find_child("*Camera*", true, false) as Camera3D
		if player_cam:
			player_cam.make_current()
		if camera_rig.has_method("snap_to_target"):
			camera_rig.snap_to_target()

	# Pastikan HUD gameplay aktif
	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(true)
		else:
			hud.visible = true

	# Pastikan NavigationLink3D aktif jika puzzle batu sudah selesai, atau nonaktif jika belum
	var nav_link = find_child("NavigationLink3D", true, false)
	if nav_link:
		nav_link.enabled = GameManager.rock_puzzle_done

	# Khusus LEV1: pastikan kapsul tetap di lokasi mendarat dan api tetap menyala
	if has_node("RocketCamera"):
		var capsule = find_child("RionCapsule", true, false)
		if capsule:
			# Hentikan animasi dulu supaya posisi kapsul tidak dikembalikan ke posisi langit
			var c_anim: AnimationPlayer = capsule.get_node_or_null("AnimationPlayer")
			if c_anim:
				c_anim.stop()
			capsule.visible = true
			capsule.global_position = Vector3(106.118, -0.096, 25.87)
			capsule.rotation = Vector3(0, 0, deg_to_rad(9.5))
			var kap = capsule.find_child("KapsulRion", true, false)
			if kap:
				kap.visible = true
			var smoke = capsule.find_child("Smoke", true, false)
			if smoke:
				smoke.visible = true
		for fire_name in ["Fire1", "Fire2", "Fire3"]:
			var fire_node = find_child(fire_name, true, false)
			if fire_node:
				fire_node.visible = true
		_setup_capsule_landed_sfx(capsule)

	# Khusus R1: kapsul yang sudah dibersihkan tetap tampil setelah cutscene pagi.
	if has_node("StoryPointing2") and has_node("RionCapsule") and GameManager.r1_morning_intro_done:
		var r1_capsule = find_child("RionCapsule", true, false)
		if r1_capsule:
			r1_capsule.visible = true

	# Hari berikutnya di bengkel (R1): objective per alur cerita
	if has_node("StoryPointing2") and has_node("Rallux"):
		if not GameManager.unpacking_rak1_done:
			GameManager.set_objective("Kumpulkan perkakas berserakan dan rapikan Rak 1", 0, "")
		elif not GameManager.unpacking_completed:
			GameManager.set_objective("Rapikan Rak 2 bersama Ona", 0, "")
		elif not GameManager.terminal_puzzle_done:
			GameManager.set_objective("Perbaiki kabel terminal di Ruang Kontrol Daya", 0, "")

		elif not GameManager.solved_levers.get("CrusherRoom_Lever", false):
			GameManager.set_objective("Nyalakan tuas lampu di Ruang Crusher", 0, "")
		elif not GameManager.solved_levers.get("OnaProgramRoom_Lever", false):
			GameManager.set_objective("Pergi ke Ruang Perakitan Ona, nyalakan tuas lampu dan jenguk Ona", 0, "")

func _workshop_tasks_done() -> bool:
	return GameManager.terminal_puzzle_done \
		and GameManager.solved_levers.get("CrusherRoom_Lever", false) \
		and GameManager.solved_levers.get("OnaProgramRoom_Lever", false)

# AudioStreamWAV hasil impor tidak menyimpan titik loop. Kalau loop_mode diubah
# saat runtime tanpa loop_begin/loop_end, stream dianggap loop 0..0 dan langsung
# selesai sehingga suaranya tidak terdengar. Set titik loop eksplisit.
func _make_wav_loop(wav: AudioStream) -> void:
	if wav is AudioStreamWAV:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var frames := int(round(wav.get_length() * float(wav.mix_rate)))
		if frames > 0:
			wav.loop_end = frames

func _ensure_capsule_audio(capsule: Node3D, node_name: String, path: String) -> AudioStreamPlayer3D:
	if capsule == null:
		return null
	var player := capsule.get_node_or_null(node_name) as AudioStreamPlayer3D
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.name = node_name
		player.bus = &"SFX" if AudioServer.get_bus_index("SFX") != -1 else &"Master"
		var stream := load(path) as AudioStream
		if stream:
			_make_wav_loop(stream)
		player.stream = stream
		player.volume_db = -2.0
		player.max_distance = 40.0
		player.unit_size = 8.0
		capsule.add_child(player)
	if not player.playing:
		player.play()
	return player

func _setup_capsule_falling_sfx(capsule: Node3D) -> void:
	# Di langit: suara jet.
	_ensure_capsule_audio(capsule, "CapsuleJetAudio3D", "res://assets/audio/sfx/Jet.wav")

func _setup_capsule_landed_sfx(capsule: Node3D) -> void:
	if capsule == null:
		return
	# Sudah mendarat: suara jet hilang...
	var jet := capsule.get_node_or_null("CapsuleJetAudio3D") as AudioStreamPlayer3D
	if jet and jet.playing:
		jet.stop()
	# ...diganti suara asap dan api.
	_ensure_capsule_audio(capsule, "CapsuleSmokeAudio3D", "res://assets/audio/sfx/Smoke.wav")
	_ensure_capsule_audio(capsule, "CapsuleFireAudio3D", "res://assets/audio/sfx/Fire.wav")

var _ona_follow: bool = false
var _ona_last_anim: String = ""
var _last_player_pos: Vector3 = Vector3.ZERO
var _cached_player: CharacterBody3D = null
var _cached_ona: CharacterBody3D = null

func _process(delta: float) -> void:
	if not has_node("StoryPointing2"):
		return
	if _cached_ona == null or not is_instance_valid(_cached_ona):
		_cached_ona = find_child("Ona", true, false) as CharacterBody3D
	var ona := _cached_ona
	if ona == null:
		return
	# Di dalam ruangan misi: Ona diam di depan pintu
	if GameManager.ona_hold_position:
		_set_ona_anim(ona, "idle")
		return
	if not _ona_follow:
		# Ona baru mengikuti Rion setelah seluruh game unpacking selesai
		if GameManager.unpacking_completed:
			_ona_follow = true
		else:
			return
	if _cached_player == null or not is_instance_valid(_cached_player):
		_cached_player = find_child("Player", true, false) as CharacterBody3D
	var player := _cached_player
	if player == null:
		return
	if StoryManager and StoryManager.dialogue_box and StoryManager.dialogue_box.visible:
		return

	var player_pos := player.global_position
	var player_moving: bool = player_pos.distance_to(_last_player_pos) > 0.03
	_last_player_pos = player_pos

	var to_player: Vector3 = player_pos - ona.global_position
	to_player.y = 0.0
	var dist := to_player.length()
	# Rion diam -> Ona ikut diam, jangan terus berlari
	if not player_moving or dist <= 2.6:
		_set_ona_anim(ona, "idle")
		return
	if dist > 3.4:
		var dir := to_player.normalized()
		ona.global_position = ona.global_position.move_toward(player_pos, 4.6 * delta)
		ona.rotation.y = atan2(-dir.x, -dir.z)
		_set_ona_anim(ona, "run")

func _set_ona_anim(ona: CharacterBody3D, anim_name: String) -> void:
	if _ona_last_anim == anim_name:
		return
	_ona_last_anim = anim_name
	if ona.has_method("play_animation"):
		ona.play_animation(anim_name)

var _fade_layer: CanvasLayer = null
var _fade_color_rect: ColorRect = null

func _get_or_create_fade_rect() -> ColorRect:
	if _fade_color_rect and is_instance_valid(_fade_color_rect):
		return _fade_color_rect
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 120
	add_child(_fade_layer)
	_fade_color_rect = ColorRect.new()
	_fade_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_color_rect.color = Color.BLACK
	_fade_color_rect.modulate.a = 0.0
	_fade_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_color_rect)
	return _fade_color_rect

func _fade_screen_out(duration: float = 0.5) -> void:
	var rect = _get_or_create_fade_rect()
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, duration)
	await tween.finished

func _fade_screen_in(duration: float = 0.5) -> void:
	var rect = _get_or_create_fade_rect()
	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, duration)
	await tween.finished
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Redup lalu terang kembali TANPA menghentikan aksi (dipakai saat karakter sedang berjalan).
## Tidak di-await oleh pemanggil supaya jalan & fade berlangsung bersamaan.
func _fade_walk_transition(fade_out_time: float = 0.45, fade_in_time: float = 0.55, hold: float = 0.1, peak_alpha: float = 0.85) -> void:
	var rect = _get_or_create_fade_rect()
	# Biarkan input tetap lewat: ini hanya efek visual, bukan pemblokir
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", peak_alpha, fade_out_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if hold > 0.0:
		tween.tween_interval(hold)
	tween.tween_property(rect, "modulate:a", 0.0, fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _snap_to_ground(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
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

## Transisi fade in ke depan Terminal Daya di Ruang Kontrol Daya
func transition_to_terminal() -> void:
	var player = find_child("Player", true, false) as CharacterBody3D
	var camera_rig = find_child("CameraRig", true, false)
	var rallux = find_child("Rallux", true, false) as Node3D
	var terminal = find_child("Terminal", true, false) as Node3D
	var hud = find_child("HUD", true, false)

	# 1. Nonaktifkan kontrol & fade out ke hitam
	if player:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.velocity = Vector3.ZERO
	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)
	await _fade_screen_out(0.5)

	# 2. Posisikan Player & Rallux di depan Terminal Daya (x=49.89, y=5.885, z=-32.852)
	var term_pos: Vector3 = Vector3(49.89, 5.885, -32.852)
	if terminal:
		terminal.global_position = term_pos

	var target_player_pos: Vector3 = Vector3(48.2, 5.885, -32.2)
	var target_rallux_pos: Vector3 = Vector3(47.6, 5.885, -33.6)

	if player:
		player.global_position = target_player_pos
		player.velocity = Vector3.ZERO
		player.rotation = Vector3.ZERO
		var dir_p: Vector3 = term_pos - player.global_position
		dir_p.y = 0.0
		var rion_mesh = player.get_node_or_null("RionMesh")
		if rion_mesh and dir_p.length_squared() > 0.01:
			rion_mesh.rotation.y = atan2(dir_p.x, dir_p.z)
		_snap_to_ground(player)

	if rallux:
		rallux.visible = true
		rallux.global_position = target_rallux_pos
		var dir_r: Vector3 = term_pos - rallux.global_position
		dir_r.y = 0.0
		if dir_r.length_squared() > 0.01:
			rallux.rotation.y = atan2(dir_r.x, dir_r.z)
		_snap_to_ground(rallux)
		_play_rallux_anim(rallux, "idle")

	if camera_rig:
		camera_rig.global_position = Vector3(40.5, 8.2, -29.8)
		camera_rig.look_at(term_pos + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		camera_rig.yaw = 0.0
		camera_rig.pitch = 18.0
		camera_rig.zoom_distance = 6.8
		if camera_rig.has_method("snap_to_target"):
			camera_rig.snap_to_target()

	# Update objective misi ke terminal
	GameManager.set_objective("Perbaiki kabel terminal di Ruang Kontrol Daya", 0, "")


	# 3. Fade in dari hitam
	await _fade_screen_in(0.5)

	# 4. Aktifkan kembali kontrol gameplay
	if player:
		player.set_physics_process(true)
		player.set_process_unhandled_input(true)
	if camera_rig:
		camera_rig.set_physics_process(true)
		camera_rig.set_process(true)
		camera_rig.set_process_unhandled_input(true)
	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(true)
		else:
			hud.visible = true

	# 5. Dialog Tuan Rallux di depan terminal daya
	if terminal and terminal.has_method("interact"):
		terminal.interact()

## Transisi fade in ke depan Tuas Lampu di Ruang Crusher
func transition_to_crusher_lever() -> void:
	var player = find_child("Player", true, false) as CharacterBody3D
	var camera_rig = find_child("CameraRig", true, false)
	var rallux = find_child("Rallux", true, false) as Node3D
	var crusher_room = find_child("CrusherRoom", true, false)
	var crusher_lever = crusher_room.find_child("Lever", true, false) as Node3D if crusher_room else null
	var hud = find_child("HUD", true, false)

	# 1. Nonaktifkan kontrol & fade out ke hitam
	if player:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.velocity = Vector3.ZERO
	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)
	await _fade_screen_out(0.5)

	# 2. Posisi Player & Rallux sesuai permintaan user:
	# rallux x= -19.479 z=-22.42, rion x=-17.457 z=-26.254
	var target_player_pos := Vector3(-17.457, 1.16, -26.254)
	var target_rallux_pos := Vector3(-19.479, 1.16, -22.42)

	var lever_pos := Vector3(-15.324, 5.075, -24.292)
	if crusher_lever:
		if "lever_handle" in crusher_lever and crusher_lever.lever_handle:
			lever_pos = crusher_lever.lever_handle.global_position
		else:
			lever_pos = crusher_lever.global_position

	if player:
		player.global_position = target_player_pos
		player.velocity = Vector3.ZERO
		player.rotation = Vector3.ZERO
		var dir_p: Vector3 = lever_pos - target_player_pos
		dir_p.y = 0.0
		var rion_mesh = player.get_node_or_null("RionMesh")
		if rion_mesh and dir_p.length_squared() > 0.01:
			rion_mesh.rotation.y = atan2(dir_p.x, dir_p.z)
		_snap_to_ground(player)

	if rallux:
		rallux.visible = true
		rallux.scale = Vector3(8.0, 8.0, 8.0)
		rallux.global_position = target_rallux_pos
		var dir_r: Vector3 = lever_pos - target_rallux_pos
		dir_r.y = 0.0
		if dir_r.length_squared() > 0.01:
			rallux.rotation.y = atan2(dir_r.x, dir_r.z)
		_snap_to_ground(rallux)
		_play_rallux_anim(rallux, "idle")

	# Kamera sorot dari SM_Microwave ke arah lever
	var microwave_pos := Vector3(-34.536, 4.0, -34.28)
	if crusher_room:
		var mw = crusher_room.find_child("SM_Microwave", true, false) as Node3D
		if not mw:
			mw = crusher_room.find_child("Crusher", true, false) as Node3D
		if mw:
			microwave_pos = mw.global_position + Vector3(4.5, 3.8, 3.2)

	if camera_rig:
		camera_rig.global_position = microwave_pos
		camera_rig.look_at(lever_pos + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		camera_rig.yaw = 0.0
		camera_rig.pitch = 14.0
		camera_rig.zoom_distance = 4.5

	# Kondisi ruangan crusher gelap dulu karena tuas masih 0%
	var we = find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we and we.environment:
		var is_solved: bool = GameManager.solved_levers.get("CrusherRoom_Lever", false)
		we.environment.ambient_light_energy = 0.7 if is_solved else 0.05

	# 3. Fade in dari hitam
	await _fade_screen_in(0.5)

	# 4. Aktifkan kembali kontrol gameplay (kamera tetap menatap dari arah SM_Microwave ke tuas)
	if player:
		player.set_physics_process(true)
		player.set_process_unhandled_input(true)
	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)
	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(true)
		else:
			hud.visible = true

	GameManager.set_objective("Nyalakan tuas lampu di Ruang Crusher", 0, "")

	# Dialog penjelasan fungsi Ruang Crusher saat pertama kali masuk
	if not GameManager.room_intro_seen.get("crusher", false):
		GameManager.room_intro_seen["crusher"] = true
		if StoryManager and StoryManager.has_method("start_dialogue"):
			StoryManager.start_dialogue([
				"Rallux: \"Nah, ini dia Ruang Crusher kita, Rion. Di ruangan inilah semua bongkahan logam rongsokan, serpihan mesin tua, dan sisa perkakas bengkel dihancurkan untuk didaur ulang menjadi suku cadang baru yang bersih dan bermanfaat.\"",
				"Rion: \"Wah, keren banget! Jadi barang-barang yang kelihatan rusak dan berantakan bisa diolah lagi jadi berguna di sini ya, Tuan Rallux!\"",
				"Rallux: \"Tepat sekali! Tapi karena sistem dayanya terputus akibat getaran kemarin, lampu dan mesin daur ulang di sini ikut padam. Ruangannya jadi gelap gulita.\"",
				"Rion: \"Tenang saja, Tuan Rallux! Aku akan tarik tuas lampu di depan sana sampai seratus persen supaya mesinnya menyala dan ruangannya kembali terang benderang!\"",
				"Rallux: \"Bagus sekali semangatmu, Kapten! Tarik tuasnya sampai seratus persen ya!\""
			], "Rallux")
			await StoryManager.dialogue_finished

## Transisi fade in ke Ruang Perakitan & Pemrograman Ona
func transition_to_onaprogram_lever() -> void:
	var player = find_child("Player", true, false) as CharacterBody3D
	var camera_rig = find_child("CameraRig", true, false)
	var rallux = find_child("Rallux", true, false) as Node3D
	var ona = find_child("Ona", true, false) as Node3D
	var ona_room = find_child("OnaProgramRoom", true, false)
	var hud = find_child("HUD", true, false)

	# 1. Nonaktifkan kontrol & fade out ke hitam
	if player:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.velocity = Vector3.ZERO
	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)
	await _fade_screen_out(0.5)

	# 2. Posisi Player, Rallux, dan Ona sesuai instruksi:
	var target_rallux_pos := Vector3(-19.644, 0.14, 36.039)
	var target_ona_pos := Vector3(-30.848, 0.14, 27.768)
	var target_player_pos := Vector3(-16.848, 0.14, 30.351)

	var preview_pos := Vector3(-30.891, 0.0, 31.639)
	if ona_room:
		var pc = ona_room.find_child("PreviewControl", true, false) as Node3D
		if pc:
			preview_pos = pc.global_position

	var lever_pos := Vector3(-15.312, 5.285, 32.141)
	if ona_room:
		var lev = ona_room.find_child("Lever", true, false) as Node3D
		if lev:
			if "lever_handle" in lev and lev.lever_handle:
				lever_pos = lev.lever_handle.global_position
			else:
				lever_pos = lev.global_position

	# Posisikan Ona menghadap PreviewControl
	if ona:
		ona.visible = true
		ona.global_position = target_ona_pos
		var dir_o := preview_pos - target_ona_pos
		dir_o.y = 0.0
		if dir_o.length_squared() > 0.01:
			ona.rotation.y = atan2(-dir_o.x, -dir_o.z)
		_snap_to_ground(ona)
		if ona.has_method("play_animation"):
			ona.play_animation("idle")

	# Posisikan Rion menghadap Lever
	if player:
		player.global_position = target_player_pos
		player.velocity = Vector3.ZERO
		player.rotation = Vector3.ZERO
		var dir_p := lever_pos - target_player_pos
		dir_p.y = 0.0
		var rion_mesh = player.get_node_or_null("RionMesh")
		if rion_mesh and dir_p.length_squared() > 0.01:
			rion_mesh.rotation.y = atan2(dir_p.x, dir_p.z)
		_snap_to_ground(player)

	# Posisikan Rallux menghadap Lever
	if rallux:
		rallux.visible = true
		rallux.scale = Vector3(8.0, 8.0, 8.0)
		rallux.global_position = target_rallux_pos
		var dir_r := lever_pos - target_rallux_pos
		dir_r.y = 0.0
		if dir_r.length_squared() > 0.01:
			rallux.rotation.y = atan2(dir_r.x, dir_r.z)
		_snap_to_ground(rallux)
		_play_rallux_anim(rallux, "idle")

	# Kamera menyorot ke arah tuas dan pemain dari sudut yang pas dan lega
	if camera_rig:
		camera_rig.global_position = Vector3(-24.5, 3.8, 31.5)
		camera_rig.look_at(lever_pos + Vector3(0.0, 0.8, 0.0), Vector3.UP)
		camera_rig.yaw = 0.0
		camera_rig.pitch = 16.0
		camera_rig.zoom_distance = 6.8

	# Kondisi ruangan ona program gelap dulu karena tuas masih 0%
	var we = find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we and we.environment:
		var is_solved: bool = GameManager.solved_levers.get("OnaProgramRoom_Lever", false)
		we.environment.ambient_light_energy = 0.7 if is_solved else 0.05

	# 3. Fade in dari hitam
	await _fade_screen_in(0.5)

	# 4. Aktifkan kembali kontrol gameplay
	if player:
		player.set_physics_process(true)
		player.set_process_unhandled_input(true)
	if camera_rig:
		camera_rig.set_physics_process(true)
		camera_rig.set_process(true)
		camera_rig.set_process_unhandled_input(true)
		var player_cam = camera_rig.find_child("*Camera*", true, false) as Camera3D
		if player_cam:
			player_cam.make_current()
		if camera_rig.has_method("snap_to_target"):
			camera_rig.snap_to_target()
	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(true)
		else:
			hud.visible = true

	GameManager.set_objective("Nyalakan tuas lampu di Ruang Perakitan Ona", 0, "")

	# Dialog penjelasan fungsi Ruang Ona Program saat pertama kali masuk
	if not GameManager.room_intro_seen.get("onaprogram", false):
		GameManager.room_intro_seen["onaprogram"] = true
		if StoryManager and StoryManager.has_method("start_dialogue"):
			StoryManager.start_dialogue([
				"Rallux: \"Selamat datang di Ruang Perakitan & Pemrograman Ona, Rion. Ruangan ini adalah laboratorium khusus tempat bodi robot Ona dirakit, sirkuit memorinya dipelihara, dan dok pengisian baterai utamanya berada.\"",
				"Rion: \"Ooh, jadi ini tempat kelahiran Ona sekaligus ruang servis dan istirahatnya ya, Tuan Rallux!\"",
				"Rallux: \"Betul sekali. Di sinilah prosesor Ona didinginkan dan memorinya ditata ulang setelah lelah beraktivitas. Lihat, Ona sedang beristirahat di dok pengisian daya di samping panel kontrol itu.\"",
				"Rion: \"Ona kelihatan pulas banget... Ayo kita nyalakan tuas lampu di ruangan ini supaya daya dok pengisian baterainya pulih penuh dan Ona bisa segera bangun!\"",
				"Rallux: \"Pintar sekali, Rion! Ayo kita hidupkan tuas lampunya sampai seratus persen!\""
			], "Rallux")
			await StoryManager.dialogue_finished

## Memutar node/mesh secara halus ke sudut target Y dengan lerp_angle
func _smooth_rotate_y(node: Node3D, target_angle: float, duration: float = 0.35) -> void:
	if not is_instance_valid(node):
		return
	var start_angle = node.rotation.y
	var diff = abs(wrapf(target_angle - start_angle, -PI, PI))
	if diff < 0.02:
		node.rotation.y = target_angle
		return
	var adj_duration = clampf(duration * (diff / PI), 0.15, duration)
	var tween = create_tween()
	tween.tween_method(func(t: float):
		if is_instance_valid(node):
			node.rotation.y = lerp_angle(start_angle, target_angle, t)
	, 0.0, 1.0, adj_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if is_instance_valid(node):
		node.rotation.y = target_angle

func _walk_character(char: CharacterBody3D, target_pos: Vector3, speed: float = 6.0) -> void:
	var start_pos = char.global_position
	var diff = target_pos - start_pos
	diff.y = 0.0
	var dist = diff.length()
	if dist < 0.1:
		return
	var duration = max(dist / speed, 0.4)
	var move_dir = diff.normalized()

	var is_player = char.is_in_group("player") or char.name == "Player"
	var rion_mesh = char.get_node_or_null("RionMesh")
	var anim_tree: AnimationTree = char.get_node_or_null("AnimationTree")

	# Putar badan secara halus sebelum atau saat mulai melangkah
	if is_player:
		char.rotation = Vector3.ZERO
		if rion_mesh and move_dir.length() > 0.01:
			var target_rot = atan2(move_dir.x, move_dir.z)
			await _smooth_rotate_y(rion_mesh, target_rot, 0.25)
		if anim_tree:
			anim_tree.set("parameters/StateMachine/Move/blend_position", 0.5)
	else:
		if move_dir.length() > 0.01:
			var target_rot = atan2(-move_dir.x, -move_dir.z)
			await _smooth_rotate_y(char, target_rot, 0.25)
		if char.has_method("play_animation"):
			char.play_animation("walk")

	var tween = create_tween()
	tween.tween_property(char, "global_position", target_pos, duration)
	await tween.finished

	if is_player:
		if anim_tree:
			anim_tree.set("parameters/StateMachine/Move/blend_position", 0.0)
	else:
		if char.has_method("play_animation"):
			char.play_animation("idle")

func _walk_pair(ona_char: CharacterBody3D, ona_target: Vector3, player_char: CharacterBody3D, player_target: Vector3, speed: float = 6.0, cam_offset: Vector3 = Vector3.ZERO) -> void:
	var ona_diff = ona_target - ona_char.global_position
	ona_diff.y = 0.0
	var dist = ona_diff.length()
	var duration = max(dist / speed, 0.5)
	var ona_dir = ona_diff.normalized()

	var rion_mesh = player_char.get_node_or_null("RionMesh")
	var anim_tree: AnimationTree = player_char.get_node_or_null("AnimationTree")

	# Putar Ona dan Rion secara halus bersamaan sebelum melangkah maju
	var rot_tween = create_tween().set_parallel(true)
	if ona_dir.length() > 0.01:
		var ona_target_rot = atan2(-ona_dir.x, -ona_dir.z)
		var ona_start_rot = ona_char.rotation.y
		rot_tween.tween_method(func(t: float):
			if is_instance_valid(ona_char):
				ona_char.rotation.y = lerp_angle(ona_start_rot, ona_target_rot, t)
		, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var p_diff = player_target - player_char.global_position
	p_diff.y = 0.0
	var p_dir = p_diff.normalized()
	player_char.rotation = Vector3.ZERO
	if rion_mesh and p_dir.length() > 0.01:
		var p_target_rot = atan2(p_dir.x, p_dir.z)
		var p_start_rot = rion_mesh.rotation.y
		rot_tween.tween_method(func(t: float):
			if is_instance_valid(rion_mesh):
				rion_mesh.rotation.y = lerp_angle(p_start_rot, p_target_rot, t)
		, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await rot_tween.finished

	# Mulai animasi jalan
	if ona_char.has_method("play_animation"):
		ona_char.play_animation("walk")
	if anim_tree:
		anim_tree.set("parameters/StateMachine/Move/blend_position", 0.5)

	var camera_rig = find_child("CameraRig", true, false)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(ona_char, "global_position", ona_target, duration)
	tween.tween_property(player_char, "global_position", player_target, duration)
	if camera_rig and cam_offset != Vector3.ZERO:
		tween.tween_property(camera_rig, "global_position", ona_target + cam_offset, duration)

	await tween.finished

	if ona_char.has_method("play_animation"):
		ona_char.play_animation("idle")
	if anim_tree:
		anim_tree.set("parameters/StateMachine/Move/blend_position", 0.0)

func _play_rocket_intro() -> void:
	var rocket_cam: Camera3D = get_node_or_null("RocketCamera")
	var anim_player: AnimationPlayer = get_node_or_null("RionCapsule/AnimationPlayer")
	var player = find_child("Player", true, false)
	var camera_rig = find_child("CameraRig", true, false)
	var hud = find_child("HUD", true, false)
	var ona = find_child("Ona", true, false)
	
	# Cari kamera player di dalam CameraRig secara otomatis
	var player_cam: Camera3D = null
	if camera_rig:
		player_cam = camera_rig.find_child("*Camera*", true, false) as Camera3D

	# 1. Nonaktifkan kontrol player, sembunyikan Rion sampai Ona selesai ke Point 5
	if player:
		player.visible = false
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		var col = player.find_child("CollisionShape3D", true, false)
		if col:
			col.set_deferred("disabled", true)

	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)

	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(false)
		else:
			hud.visible = false

	# 2. Pindah ke kamera sinematik roket
	if rocket_cam:
		rocket_cam.make_current()

	# 3. Putar animasi roket Kehancuran
	var capsule = find_child("RionCapsule", true, false)
	if anim_player:
		anim_player.play("Kehancuran")
		# Di langit: suara jet.
		_setup_capsule_falling_sfx(capsule)
		if AudioManager:
			# Putar crash impact saat kapsul membentur tanah di detik ke-3.6
			get_tree().create_timer(3.6).timeout.connect(func():
				if AudioManager:
					AudioManager.play_capsule_crash(3.0)
			)

	# 4. Saat roket mendarat (5 detik), arahkan kamera ke Ona yang mulai berjalan
	await get_tree().create_timer(5.0).timeout
	if capsule:
		capsule.visible = true
		capsule.global_position = Vector3(106.118, -0.096, 25.87)
		capsule.rotation = Vector3(0, 0, deg_to_rad(9.5))
		var smoke = capsule.find_child("Smoke", true, false)
		if smoke:
			smoke.visible = true
		# Sudah mendarat: jet hilang, ganti asap + api.
		_setup_capsule_landed_sfx(capsule)
	for fire_name in ["Fire1", "Fire2", "Fire3"]:
		var fire_node = find_child(fire_name, true, false)
		if fire_node:
			fire_node.visible = true

	if rocket_cam and is_instance_valid(ona):
		if rocket_cam.has_method("track_target"):
			rocket_cam.track_target(ona)
		else:
			rocket_cam.target_node = ona

	# 5. Tunggu sampai Ona selesai sampai di Point 5
	if ona and ona.has_signal("point_5_finished"):
		await ona.point_5_finished

	# 6. Pastikan Rion muncul (unhidden) dan kontrol pemain pulih
	if player:
		player.visible = true
		player.set_physics_process(true)
		player.set_process_unhandled_input(true)
		var col = player.find_child("CollisionShape3D", true, false)
		if col:
			col.set_deferred("disabled", false)

	if camera_rig:
		camera_rig.set_physics_process(true)
		camera_rig.set_process(true)
		camera_rig.set_process_unhandled_input(true)
	if player_cam:
		player_cam.make_current()
	if camera_rig and camera_rig.has_method("snap_to_target"):
		camera_rig.snap_to_target()
	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(true)
		else:
			hud.visible = true

func _play_workshop_intro() -> void:
	var player: CharacterBody3D = find_child("Player", true, false) as CharacterBody3D
	var camera_rig = find_child("CameraRig", true, false)
	var hud = find_child("HUD", true, false)
	var ona: CharacterBody3D = find_child("Ona", true, false) as CharacterBody3D
	var rallux: Node3D = find_child("Rallux", true, false) as Node3D
	var storypoints: Node3D = get_node_or_null("StoryPointing2")

	if storypoints == null or ona == null or rallux == null or player == null:
		return

	var p1: Marker3D = storypoints.get_node_or_null("Point1") as Marker3D
	var p2: Marker3D = storypoints.get_node_or_null("Point2") as Marker3D
	var p3: Marker3D = storypoints.get_node_or_null("Point3") as Marker3D
	var p4: Marker3D = storypoints.get_node_or_null("Point4") as Marker3D
	var p5: Marker3D = storypoints.get_node_or_null("Point5") as Marker3D

	if p1 == null or p2 == null or p3 == null or p4 == null:
		return

	var rallux_anim: AnimationPlayer = rallux.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var rion_mesh = player.get_node_or_null("RionMesh")

	# 1. Nonaktifkan kontrol gameplay & UI
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)
	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(false)
		else:
			hud.visible = false

	# 2. Setup Posisi Awal di pintu masuk (Point 4)
	# Ona dan Rion masuk dari pintu bengkel
	ona.global_position = p4.global_position + Vector3(2.0, 0, 0)
	player.global_position = p4.global_position + Vector3(0.5, 0, -1.2)
	player.rotation = Vector3.ZERO
	if rion_mesh:
		rion_mesh.rotation = Vector3.ZERO

	# Rallux berada di posisi awal yang telah diatur (23.843, 0, 30.673) rotasi (0, -137.3, 0) di balik meja kerja
	var rallux_start_pos := Vector3(23.843, 0.0, 30.673)
	var rallux_start_rot := Vector3(0.0, deg_to_rad(-137.3), 0.0)
	rallux.global_position = rallux_start_pos
	rallux.rotation = rallux_start_rot
	_play_rallux_anim(rallux, "searching")

	# Setup Kamera di belakang-kiri Ona saat baru masuk - tetap di dalam ruangan (bukan menembus dinding selatan)
	var entrance_cam_offset := Vector3(-6.0, 5.0, 2.5)
	if camera_rig:
		camera_rig.global_position = ona.global_position + entrance_cam_offset
		camera_rig.look_at(ona.global_position + Vector3(0.0, 1.4, 3.0), Vector3.UP)
		var cam = camera_rig.find_child("*Camera*", true, false) as Camera3D
		if cam:
			cam.make_current()

	await get_tree().create_timer(0.5).timeout

	# =========================================================================
	# 2. ONA & RION BERJALAN DARI PINTU (P4) KE POINT 1 → DIALOG → LANJUT KE POINT 2
	# =========================================================================
	# Langkah 1: Jalan dari P4 ke Point 1
	var p1_ona_target: Vector3 = p1.global_position
	var p1_player_target: Vector3 = p1.global_position + Vector3(-1.0, 0, 1.0)
	var cam_p1: Vector3 = p1.global_position + Vector3(-6.0, 5.0, 3.0)
	await _walk_pair(ona, p1_ona_target, player, p1_player_target, 6.5, cam_p1 - p1_ona_target)

	# Pastikan di Point 1 menghadap lurus ke lorong (+X / menuju Point 2), tidak serong
	var straight_dir_p1 := Vector3(1.0, 0.0, 0.0)
	var target_rot_ona_p1 := atan2(-straight_dir_p1.x, -straight_dir_p1.z)
	var target_rot_rion_p1 := atan2(straight_dir_p1.x, straight_dir_p1.z)
	var rot_p1 = create_tween().set_parallel(true)
	var ona_s_p1 = ona.rotation.y
	rot_p1.tween_method(func(t: float):
		if is_instance_valid(ona):
			ona.rotation.y = lerp_angle(ona_s_p1, target_rot_ona_p1, t)
	, 0.0, 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if rion_mesh:
		var rion_s_p1 = rion_mesh.rotation.y
		rot_p1.tween_method(func(t: float):
			if is_instance_valid(rion_mesh):
				rion_mesh.rotation.y = lerp_angle(rion_s_p1, target_rot_rion_p1, t)
		, 0.0, 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await rot_p1.finished

	if camera_rig:
		camera_rig.look_at(ona.global_position + Vector3(0, 1.4, 0), Vector3.UP)

	# Dialog di Point 1: Rion bingung mencari Rallux
	var point1_dialog: Array[String] = [
		"Rion: \"Ona... tempatnya luas banget... Tapi... mana Tuan Rallux-nya?\"",
		"Ona: \"Tuan Rallux pasti sedang bekerja di meja kerjanya di sudut ruangan. Ayo kita hampiri, Rion.\""
	]
	StoryManager.start_dialogue(point1_dialog, "Rion")
	await StoryManager.dialogue_finished

	await get_tree().create_timer(0.3).timeout

	# Langkah 2: Lanjut BERJALAN ke Point 2.
	# Fade dijalankan SELAGI mereka berjalan (tanpa teleport) agar cutscene tidak kaku.
	var p2_ona_target: Vector3 = p2.global_position + Vector3(0.0, 0.0, -0.6)
	var p2_player_target: Vector3 = p2.global_position + Vector3(-1.2, 0, 1.0)
	var cam_p2: Vector3 = p2.global_position + Vector3(-7.5, 5.2, 4.0)

	# Redup sebentar lalu terang kembali sambil kaki tetap berjalan
	_fade_walk_transition(0.45, 0.55)
	await _walk_pair(ona, p2_ona_target, player, p2_player_target, 7.5, cam_p2 - p2_ona_target)

	# Di Point 2: Menghadap lurus ke depan (+X)
	var straight_dir_p2 := Vector3(1.0, 0.0, 0.0)
	await _smooth_rotate_y(ona, atan2(-straight_dir_p2.x, -straight_dir_p2.z), 0.3)
	if rion_mesh:
		rion_mesh.rotation.y = atan2(straight_dir_p2.x, straight_dir_p2.z)

	if ona.has_method("play_animation"):
		ona.play_animation("idle")
	var anim_tree: AnimationTree = player.get_node_or_null("AnimationTree")
	if anim_tree:
		anim_tree.set("parameters/StateMachine/Move/blend_position", 0.0)

	if camera_rig:
		camera_rig.look_at(ona.global_position + Vector3(0, 1.4, 0), Vector3.UP)

	await get_tree().create_timer(0.3).timeout

	# Di Point 2 terdengar suara TANG! KLATAK! dari meja kerja Rallux
	var point2_dialog: Array[String] = [
		"TANG! KLATAK!",
	]
	StoryManager.start_dialogue(point2_dialog, "Rion")
	await StoryManager.dialogue_finished

	await get_tree().create_timer(0.4).timeout

	# =========================================================================
	# 3. SHOOT RALLUX DI MEJA KERJA SAAT MENGGERUTU, LALU FADE MENUJU POINT 2 & 3
	# =========================================================================
	# Sorot Rallux dari arah depannya saat mencari baut di meja kerja
	if camera_rig:
		var rallux_cam_pos = rallux.global_position + Vector3(-7.0, 4.5, -7.2)
		camera_rig.global_position = rallux_cam_pos
		camera_rig.look_at(rallux.global_position + Vector3(0, 2.0, 0), Vector3.UP)

	_play_rallux_anim(rallux, "searching")

	# Rallux menggerutu sambil mencari baut di meja kerja (kamera menyorot Rallux)
	var p2_dialog: Array[String] = [
		"Rallux: \"Aduh! Baut gravitasi yang nakal... lari ke mana lagi kamu? Jangan pura-pura jadi hiasan lantai, aku tahu kamu sembunyi di dekat situ!\"",
		"Rallux: \"Fiuh... baut kecil itu lincah sekali kalau menggelinding.\""
	]
	StoryManager.start_dialogue(p2_dialog, "Rallux")
	await StoryManager.dialogue_finished

	# Setelah dialog Rallux selesai: Fade out
	await _fade_screen_out(0.4)

	# Posisikan Rallux di Point 3 menghadap ke arah Ona & Rion di Point 2
	rallux.global_position = p3.global_position
	var dir_rallux_to_ona = (ona.global_position - rallux.global_position).normalized()
	dir_rallux_to_ona.y = 0.0
	if dir_rallux_to_ona.length() > 0.01:
		rallux.rotation.y = atan2(dir_rallux_to_ona.x, dir_rallux_to_ona.z)
	if rallux.has_method("play_animation"):
		rallux.play_animation("idle")
	elif rallux_anim:
		rallux_anim.play("idle")

	# Kamera kembali siap di Point 2 menyorot Ona dan Rion
	if camera_rig:
		camera_rig.global_position = cam_p2
		camera_rig.look_at(ona.global_position + Vector3(0, 1.4, 0), Vector3.UP)

	await get_tree().create_timer(0.2).timeout
	# Fade in: layar kembali terang dengan kamera menyorot Ona & Rion dan Rallux sudah tiba di Point 3
	await _fade_screen_in(0.4)

	# Dialog sambutan Rallux bagian pertama
	var p3_dialog_1: Array[String] = [
		"Rallux: \"Eh? Ona! Kamu sudah kembali dari jalan-jalan di hutan?\"",
		"Rallux: \"Oho! Dan siapa teman baru di sampingmu ini?\"",
	]
	StoryManager.start_dialogue(p3_dialog_1, "Rallux")
	await StoryManager.dialogue_finished

	# Kamera berpindah menyorot Ona & Rion dari jarak lebih jauh
	if camera_rig:
		camera_rig.global_position = ona.global_position + Vector3(-5.5, 3.2, 6.5)
		camera_rig.look_at(ona.global_position + Vector3(0, 1.2, 0), Vector3.UP)

	# Rion bergerak secara alami ke belakang Ona, tetapi tetap menghadap ke arah Rallux
	var dir_to_rallux = (rallux.global_position - ona.global_position).normalized()
	dir_to_rallux.y = 0.0
	var rion_hide_pos = ona.global_position - dir_to_rallux * 1.5 + Vector3(-0.6, 0, 0)
	await _walk_character(player, rion_hide_pos, 3.5)

	var dir_rion_to_rallux = (rallux.global_position - player.global_position).normalized()
	dir_rion_to_rallux.y = 0.0
	if rion_mesh and dir_rion_to_rallux.length() > 0.01:
		var target_rion_rallux = atan2(dir_rion_to_rallux.x, dir_rion_to_rallux.z)
		await _smooth_rotate_y(rion_mesh, target_rion_rallux, 0.3)
	if ona.has_method("play_animation"):
		ona.play_animation("bashful")

	# Dialog perkenalan Ona & sambutan hangat Rallux
	var p3_dialog_2: Array[String] = [
		"Ona: \"Selamat sore, Tuan Rallux. Kenalkan, ini adalah teman baru kita. Namanya Rion. Dia masih agak malu dan berhati-hati saat bertemu dengan orang baru.\"",
		"Rallux: \"Ah, wajar sekali! Kalau aku jadi Rion dan tiba-tiba melihat orang asing tak dikenal, aku juga pasti memilih sembunyi dulu di balik punggungmu, Ona.\"",
		"Rallux: \"Halo, Rion. Senang sekali bisa menyambutmu di sini. Anggap saja tempat ini seperti ruang bermainmu sendiri ya. Kamu bebas melihat-lihat, duduk di sana, atau sekadar menikmati wangi matcha di bengkel ini.\"",
		"Rallux: \"Ona, bagaimana kalau kamu ajak Rion jalan-jalan santai dulu di sekitar kebun luar? Supaya Rion bisa menghirup udara segar dan merasa lebih rileks dulu.\"",
		"Ona: \"Ide yang sangat bagus, Tuan Rallux. Udara sore di luar sangat sejuk dan menenangkan.\"",
		"Ona: \"Ayo, Rion... kita jalan-jalan santai di luar sebentar, mau?\"",
		"Rion: \"...\""
	]
	StoryManager.start_dialogue(p3_dialog_2, "Rallux")
	await StoryManager.dialogue_finished

	# =========================================================================
	# 4. ONA & RION INGIN KELUAR BENGKEL: JALAN MENUJU POINT 1 → FADE SAAT JALAN
	# =========================================================================
	# Nonaktifkan tabrakan antara Player dan Ona agar pergerakan mulus tanpa saling dorong
	player.set_collision_mask_value(2, false)
	player.set_collision_mask_value(3, false)
	ona.set_collision_mask_value(2, false)
	ona.set_collision_mask_value(3, false)

	# Posisikan kamera di belakang Ona & Rion menghadap ke arah Point 1
	var dir_to_p1 = (p1.global_position - ona.global_position).normalized()
	dir_to_p1.y = 0.0
	var to_p1_cam_offset = -dir_to_p1 * 7.0 + Vector3(0, 4.0, 0)
	if camera_rig:
		camera_rig.global_position = ona.global_position + to_p1_cam_offset
		camera_rig.look_at(ona.global_position + Vector3(0, 1.4, 0), Vector3.UP)

	# Putar hadap Ona dan Rion ke arah Point 1
	var rot_exit = create_tween().set_parallel(true)
	if dir_to_p1.length() > 0.01:
		var ona_target_rot = atan2(-dir_to_p1.x, -dir_to_p1.z)
		var ona_start_rot = ona.rotation.y
		rot_exit.tween_method(func(t: float):
			if is_instance_valid(ona):
				ona.rotation.y = lerp_angle(ona_start_rot, ona_target_rot, t)
		, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var side_vec_p1 = Vector3(-dir_to_p1.z, 0.0, dir_to_p1.x).normalized()
	var player_p1_exit_target = p1.global_position + side_vec_p1 * 1.8 - dir_to_p1 * 0.8
	var p_diff = player_p1_exit_target - player.global_position
	p_diff.y = 0.0
	var p_dir = p_diff.normalized()
	player.rotation = Vector3.ZERO
	if rion_mesh and p_dir.length() > 0.01:
		var p_target_rot = atan2(p_dir.x, p_dir.z)
		var p_start_rot = rion_mesh.rotation.y
		rot_exit.tween_method(func(t: float):
			if is_instance_valid(rion_mesh):
				rion_mesh.rotation.y = lerp_angle(p_start_rot, p_target_rot, t)
		, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await rot_exit.finished

	# Mulai berjalan menuju Point 1
	if ona.has_method("play_animation"):
		ona.play_animation("walk")
	var ona_anim_player = ona.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ona_anim_player and (ona_anim_player.current_animation != "walk" or not ona_anim_player.is_playing()):
		ona_anim_player.play("walk")
	var anim_tree_exit: AnimationTree = player.get_node_or_null("AnimationTree")
	if anim_tree_exit:
		anim_tree_exit.set("parameters/StateMachine/Move/blend_position", 0.5)

	var walk_exit_tween = create_tween().set_parallel(true)
	walk_exit_tween.tween_property(ona, "global_position", p1.global_position, 6.0)
	walk_exit_tween.tween_property(player, "global_position", player_p1_exit_target, 6.0)
	if camera_rig:
		walk_exit_tween.tween_property(camera_rig, "global_position", p1.global_position + to_p1_cam_offset, 6.0)

	# Biarkan mereka melangkah sejenak (1.2 detik) sehingga terlihat jelas mereka sedang berjalan keluar menuju Point 1
	await get_tree().create_timer(1.2).timeout

	# Kunci pintu bengkel dan tandai telah mengunjungi bengkel
	GameManager.has_visited_workshop = true
	GameManager.workshop_door_locked = true

	# Set posisi spawn Rion di depan Bengkel di LEV1 berdampingan dengan Ona
	GameManager.set_spawn_override(Vector3(-145.8, 0.0, -2.5), "LEV1")

	# Saat sedang berjalan menuju Point 1, transisi fade keluar bengkel menuju LEV1
	if has_node("/root/LoadingScreen"):
		LoadingScreen.load_scene("res://LEV1.tscn")
	else:
		await _fade_screen_out(0.6)
		get_tree().change_scene_to_file("res://LEV1.tscn")

## Kilas balik monokrom di LEV1, tepat di depan kapsul Rion yang jatuh.
## Dipanggil saat transisi tidur sebelum berpindah ke bengkel R1 (pagi berikutnya).
func _play_lev1_flashback() -> void:
	var camera_rig = find_child("CameraRig", true, false)
	var player: CharacterBody3D = find_child("Player", true, false) as CharacterBody3D
	var capsule: Node3D = find_child("RionCapsule", true, false) as Node3D
	var hud = find_child("HUD", true, false)

	if hud and hud.has_method("set_gameplay_ui_visible"):
		hud.set_gameplay_ui_visible(false)
	if player:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.velocity = Vector3.ZERO
	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)
	if capsule:
		# Hentikan animasi DULU, baru set posisi (kalau tidak, animasi bisa mengembalikan
		# kapsul ke posisi awalnya di udara).
		var cap_anim = capsule.get_node_or_null("AnimationPlayer")
		if cap_anim:
			cap_anim.stop()
			cap_anim.autoplay = ""
		capsule.visible = true
		capsule.global_position = Vector3(106.118, -0.096, 25.87)
		capsule.rotation = Vector3(0.0, 0.0, deg_to_rad(9.5))
		var kap = capsule.find_child("KapsulRion", true, false)
		if kap:
			kap.visible = true
		var jet_node = capsule.find_child("Jet", true, false)
		if jet_node:
			jet_node.visible = false
		var smoke_node = capsule.find_child("Smoke", true, false)
		if smoke_node:
			smoke_node.visible = true
			if smoke_node is GPUParticles3D:
				smoke_node.emitting = true

	# Pastikan efek api di lokasi crash tetap tampil saat kilas balik
	for fire_name in ["Fire1", "Fire2", "Fire3"]:
		var fire_node = find_child(fire_name, true, false)
		if fire_node:
			fire_node.visible = true
			if fire_node is GPUParticles3D:
				fire_node.emitting = true

	var cap_pos: Vector3 = capsule.global_position if capsule else Vector3(106.118, 0.0, 25.87)
	cap_pos.y = 0.0

	# Rallux sementara berdiri di depan kapsul untuk kilas balik.
	# Kalau ada Marker3D bernama "FlashbackRalluxPoint" di LEV1, posisinya dipakai.
	var rallux_point: Node3D = find_child("FlashbackRalluxPoint", true, false) as Node3D
	var rallux_scene := load("res://assets/Rallux/rallux.tscn") as PackedScene
	var rally: Node3D = null
	if rallux_scene:
		rally = rallux_scene.instantiate() as Node3D
		add_child(rally)
		rally.scale = Vector3(2.0, 2.0, 2.0)
		rally.global_position = rallux_point.global_position if rallux_point else (cap_pos + Vector3(2.4, 0.0, 2.8))
		var d_r: Vector3 = cap_pos - rally.global_position
		d_r.y = 0.0
		if d_r.length_squared() > 0.01:
			rally.rotation.y = atan2(d_r.x, d_r.z)
		if rally.has_method("play_animation"):
			rally.play_animation("idle")

	var cam: Camera3D = null
	var cam_point: Node3D = find_child("FlashbackCameraPoint", true, false) as Node3D
	var look_point: Node3D = find_child("FlashbackLookPoint", true, false) as Node3D
	if camera_rig:
		cam = camera_rig.find_child("*Camera*", true, false) as Camera3D
		if cam:
			cam.make_current()
		# Posisi kamera: pakai marker FlashbackCameraPoint kalau ada (biar sesuai marker),
		# kalau tidak ada baru fallback ke sekitar Rallux.
		if cam_point:
			camera_rig.global_position = cam_point.global_position
		else:
			var focus_cam: Vector3 = rallux_point.global_position if rallux_point else cap_pos
			camera_rig.global_position = focus_cam + Vector3(4.5, 2.8, 6.0)
		# Titik pandang: pakai FlashbackLookPoint kalau ada, kalau tidak arahkan ke Rallux.
		if look_point:
			camera_rig.look_at(look_point.global_position, Vector3.UP)
		else:
			var focus_look: Vector3 = rallux_point.global_position if rallux_point else cap_pos
			camera_rig.look_at(focus_look + Vector3(0.0, 1.4, 0.0), Vector3.UP)

	var fade_rect = _get_or_create_fade_rect()
	fade_rect.modulate.a = 1.0
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	# Kondisikan langit dan pencahayaan ke malam hari (bintang, bulan, aurora, dan lampu malam)
	var sun = find_child("DirectionalLight3D", true, false)
	var prev_sun_elapsed: float = 0.0
	var prev_sun_process: bool = true
	if sun:
		prev_sun_elapsed = sun.get("elapsed") if sun.get("elapsed") != null else 0.0
		prev_sun_process = sun.is_processing()
		var cycle_dur: float = sun.get("cycle_duration") if sun.get("cycle_duration") != null else 70.0
		sun.set("elapsed", 0.65 * cycle_dur)
		sun.set("_update_timer", 1.0)
		if sun.has_method("_process"):
			sun._process(0.0)
		if sun.has_method("_update_ambient_light"):
			sun._update_ambient_light(0.65)
		if sun.has_method("_update_water_glow"):
			sun._update_water_glow(0.65)
		if sun.has_method("_update_terrain_glow"):
			sun._update_terrain_glow(0.65)
		if sun.has_method("_update_rock_glow"):
			sun._update_rock_glow(0.65)
		sun.set_process(false)

	_set_monochrome(true)
	var gray_canvas = _create_grayscale_flashback_filter()
	_set_flashback_particles(true)
	await _fade_screen_in(0.8)
	var flashback: Array[String] = [
		"Rallux: \"Kapsul penyelamat model gravitasi orbit... Sistem pelindungnya hampir habis terkikis gesekan atmosfer.\"",
		"Rallux: \"Data navigasi terhapus... rekaman memori nol byte. Anak sekecil itu menahan guncangan sebesar ini sendirian di ruang hampa.\"",
		"Rallux: \"Kamu sudah bertahan luar biasa, kapsul kecil. Ayo, kita bawa rumah besimu ini ke tempat yang aman.\""
	]
	StoryManager.start_dialogue(flashback, "Rallux")
	await StoryManager.dialogue_finished
	await _fade_screen_out(0.4)
	_set_flashback_particles(false)
	if is_instance_valid(gray_canvas):
		gray_canvas.queue_free()
	_set_monochrome(false)
	if is_instance_valid(rally):
		rally.queue_free()
	if sun:
		sun.set_process(prev_sun_process)
		sun.set("elapsed", prev_sun_elapsed)
		sun.set("_update_timer", 1.0)
		if sun.has_method("_process"):
			sun._process(0.0)

## Menampilkan popup pilihan respons pemain (2 opsi)
func _prompt_choice(options: Array[String]) -> int:
	var canvas := CanvasLayer.new()
	canvas.layer = 125
	add_child(canvas)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	canvas.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel := PanelContainer.new()
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.08, 0.11, 0.16, 0.95)
	panel_sb.border_color = Color(0.28, 0.58, 0.88, 0.9)
	panel_sb.border_width_left = 2
	panel_sb.border_width_top = 2
	panel_sb.border_width_right = 2
	panel_sb.border_width_bottom = 2
	panel_sb.corner_radius_top_left = 12
	panel_sb.corner_radius_top_right = 12
	panel_sb.corner_radius_bottom_left = 12
	panel_sb.corner_radius_bottom_right = 12
	panel_sb.content_margin_left = 28
	panel_sb.content_margin_top = 22
	panel_sb.content_margin_right = 28
	panel_sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(560, 0)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "PILIHAN RESPON RION"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0, 1.0))
	title_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	for i in range(options.size()):
		var btn := Button.new()
		btn.text = options[i]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(540, 52)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		var btn_sb := StyleBoxFlat.new()
		btn_sb.bg_color = Color(0.14, 0.19, 0.28, 0.9)
		btn_sb.border_color = Color(0.35, 0.55, 0.78, 0.8)
		btn_sb.border_width_left = 1
		btn_sb.border_width_top = 1
		btn_sb.border_width_right = 1
		btn_sb.border_width_bottom = 1
		btn_sb.corner_radius_top_left = 8
		btn_sb.corner_radius_top_right = 8
		btn_sb.corner_radius_bottom_left = 8
		btn_sb.corner_radius_bottom_right = 8
		btn_sb.content_margin_left = 16
		btn_sb.content_margin_right = 16
		btn_sb.content_margin_top = 10
		btn_sb.content_margin_bottom = 10
		btn.add_theme_stylebox_override("normal", btn_sb)

		var btn_sb_hover := btn_sb.duplicate() as StyleBoxFlat
		btn_sb_hover.bg_color = Color(0.22, 0.32, 0.48, 0.95)
		btn_sb_hover.border_color = Color(0.55, 0.85, 1.0, 1.0)
		btn.add_theme_stylebox_override("hover", btn_sb_hover)

		var btn_sb_pressed := btn_sb.duplicate() as StyleBoxFlat
		btn_sb_pressed.bg_color = Color(0.09, 0.14, 0.22, 0.95)
		btn.add_theme_stylebox_override("pressed", btn_sb_pressed)

		var idx_val: int = i
		btn.pressed.connect(func():
			_choice_selected.emit(idx_val)
		)
		vbox.add_child(btn)

	var prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var chosen: int = await _choice_selected
	Input.mouse_mode = prev_mouse_mode
	canvas.queue_free()
	return chosen

## Menampilkan narasi transisi sarapan di layar hitam dengan jeda hening
func _show_black_screen_narration(text: String, hold_time: float = 4.0) -> void:
	await _fade_screen_out(0.8)

	var canvas := CanvasLayer.new()
	canvas.layer = 125
	add_child(canvas)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(740, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96, 0.95))
	label.add_theme_font_size_override("font_size", 18)
	label.modulate.a = 0.0
	center.add_child(label)

	var t_in = create_tween()
	t_in.tween_property(label, "modulate:a", 1.0, 1.0)
	await t_in.finished

	await get_tree().create_timer(hold_time).timeout

	var t_out = create_tween()
	t_out.tween_property(label, "modulate:a", 0.0, 0.8)
	await t_out.finished

	# Jeda hening sekitar 2 detik persis sesuai instruksi
	await get_tree().create_timer(2.0).timeout

	canvas.queue_free()

## Pop-up jendela dialog interaktif / kotak input teks untuk refleksi diri
func _prompt_text_input(header: String, question: String, placeholder: String) -> String:
	var canvas := CanvasLayer.new()
	canvas.layer = 125
	add_child(canvas)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	canvas.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel := PanelContainer.new()
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.08, 0.11, 0.16, 0.95)
	panel_sb.border_color = Color(0.3, 0.65, 0.95, 0.9)
	panel_sb.border_width_left = 2
	panel_sb.border_width_top = 2
	panel_sb.border_width_right = 2
	panel_sb.border_width_bottom = 2
	panel_sb.corner_radius_top_left = 12
	panel_sb.corner_radius_top_right = 12
	panel_sb.corner_radius_bottom_left = 12
	panel_sb.corner_radius_bottom_right = 12
	panel_sb.content_margin_left = 28
	panel_sb.content_margin_top = 24
	panel_sb.content_margin_right = 28
	panel_sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(620, 0)
	panel.add_child(vbox)

	var header_lbl := Label.new()
	header_lbl.text = header
	header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35, 1.0))
	header_lbl.add_theme_font_size_override("font_size", 17)
	vbox.add_child(header_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var q_lbl := Label.new()
	q_lbl.text = question
	q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q_lbl.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95, 1.0))
	q_lbl.add_theme_font_size_override("font_size", 15)
	vbox.add_child(q_lbl)

	var line_edit := LineEdit.new()
	line_edit.placeholder_text = placeholder
	line_edit.custom_minimum_size = Vector2(0, 44)
	line_edit.max_length = 120
	line_edit.clear_button_enabled = true
	var le_sb := StyleBoxFlat.new()
	le_sb.bg_color = Color(0.12, 0.16, 0.24, 0.9)
	le_sb.border_color = Color(0.35, 0.5, 0.7, 0.7)
	le_sb.border_width_left = 1
	le_sb.border_width_top = 1
	le_sb.border_width_right = 1
	le_sb.border_width_bottom = 1
	le_sb.corner_radius_top_left = 6
	le_sb.corner_radius_top_right = 6
	le_sb.corner_radius_bottom_left = 6
	le_sb.corner_radius_bottom_right = 6
	le_sb.content_margin_left = 12
	le_sb.content_margin_right = 12
	line_edit.add_theme_stylebox_override("normal", le_sb)
	vbox.add_child(line_edit)

	var err_lbl := Label.new()
	err_lbl.text = "Jawaban tidak boleh kosong. Harap isi setidaknya satu kata ya!"
	err_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	err_lbl.add_theme_font_size_override("font_size", 13)
	err_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	err_lbl.visible = false
	vbox.add_child(err_lbl)

	var hbox_btn := HBoxContainer.new()
	hbox_btn.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(hbox_btn)

	var send_btn := Button.new()
	send_btn.text = "Kirim / Selesai"
	send_btn.custom_minimum_size = Vector2(140, 40)
	var btn_sb := StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.18, 0.45, 0.75, 0.9)
	btn_sb.corner_radius_top_left = 6
	btn_sb.corner_radius_top_right = 6
	btn_sb.corner_radius_bottom_left = 6
	btn_sb.corner_radius_bottom_right = 6
	send_btn.add_theme_stylebox_override("normal", btn_sb)
	var btn_sb_hover := btn_sb.duplicate() as StyleBoxFlat
	btn_sb_hover.bg_color = Color(0.24, 0.55, 0.9, 1.0)
	send_btn.add_theme_stylebox_override("hover", btn_sb_hover)
	hbox_btn.add_child(send_btn)

	var on_submit = func():
		var val: String = line_edit.text.strip_edges()
		var words: PackedStringArray = val.split(" ", false)
		if val.is_empty() or words.is_empty():
			err_lbl.text = "Jawaban tidak boleh kosong. Harap isi setidaknya satu kata ya!"
			err_lbl.visible = true
			le_sb.border_color = Color(1.0, 0.35, 0.35, 0.9)
			var orig_x: float = panel.position.x
			var shake_tw := panel.create_tween()
			for i in range(4):
				var ox: float = 8.0 if (i % 2 == 0) else -8.0
				shake_tw.tween_property(panel, "position:x", orig_x + ox, 0.04)
			shake_tw.tween_property(panel, "position:x", orig_x, 0.04)
			line_edit.grab_focus()
			return
		_text_input_submitted.emit(val)

	line_edit.text_changed.connect(func(t: String):
		if not t.strip_edges().is_empty():
			err_lbl.visible = false
			le_sb.border_color = Color(0.35, 0.5, 0.7, 0.7)
	)

	send_btn.pressed.connect(on_submit)
	line_edit.text_submitted.connect(func(_t): on_submit.call())

	var prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	line_edit.grab_focus()

	var result: String = await _text_input_submitted
	Input.mouse_mode = prev_mouse_mode
	canvas.queue_free()
	return result

func _play_r1_morning_intro() -> void:
	var player: CharacterBody3D = find_child("Player", true, false) as CharacterBody3D
	var camera_rig = find_child("CameraRig", true, false)
	var hud = find_child("HUD", true, false)
	var ona: CharacterBody3D = find_child("Ona", true, false) as CharacterBody3D
	var rallux: Node3D = find_child("Rallux", true, false) as Node3D
	var capsule: Node3D = find_child("RionCapsule", true, false) as Node3D
	var rion_mesh = player.get_node_or_null("RionMesh") if player else null
	var p_anim: AnimationTree = player.get_node_or_null("AnimationTree") if player else null

	# 1. Kunci kontrol gameplay & UI
	if player:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.velocity = Vector3.ZERO
	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)
	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(false)
		else:
			hud.visible = false
	var mobile = find_child("MobileControls", true, false)
	if mobile:
		mobile.visible = false
	var s_btn = find_child("SettingsBtn", true, false)
	if s_btn:
		s_btn.visible = false


	if capsule:
		capsule.visible = true

	# Posisi barier kapsul Rion di R1
	var barrier: Node3D = capsule.find_child("CapsuleBarier", true, false) as Node3D if capsule else null
	var cap_pos: Vector3 = Vector3(-4.0, 0.0, -39.0)
	if barrier:
		cap_pos = barrier.global_position
	elif capsule:
		cap_pos = capsule.global_position
	cap_pos.y = 0.0

	var storypoints := get_node_or_null("StoryPointing2")
	var p2: Marker3D = storypoints.get_node_or_null("Point2") as Marker3D if storypoints else null
	var p3: Marker3D = storypoints.get_node_or_null("Point3") as Marker3D if storypoints else null

	var p2_pos: Vector3 = p2.global_position if p2 else Vector3(-22.378, 0.0, -7.185)
	var p3_pos: Vector3 = p3.global_position if p3 else Vector3(-7.284, 0.0, -6.486)
	p2_pos.y = 0.0
	p3_pos.y = 0.0

	# 2. Ona & Rallux berada di depan barier kapsul Rion
	var ona_pos: Vector3 = cap_pos + Vector3(-2.6, 0.0, 2.8)
	var rallux_pos: Vector3 = cap_pos + Vector3(2.4, 0.0, 2.4)

	if ona:
		ona.global_position = ona_pos
		ona.velocity = Vector3.ZERO
		var d_ona: Vector3 = cap_pos - ona.global_position
		d_ona.y = 0.0
		if d_ona.length_squared() > 0.01:
			ona.rotation.y = atan2(-d_ona.x, -d_ona.z)
		if ona.has_method("play_animation"):
			ona.play_animation("idle")

	if rallux:
		rallux.global_position = rallux_pos
		var d_ral: Vector3 = cap_pos - rallux.global_position
		d_ral.y = 0.0
		if d_ral.length_squared() > 0.01:
			rallux.rotation.y = atan2(d_ral.x, d_ral.z)
		if rallux.has_method("play_animation"):
			rallux.play_animation("idle")

	# Kamera awal: menyorot Ona & Rallux di depan barier kapsul
	var cam: Camera3D = null
	if camera_rig:
		cam = camera_rig.find_child("*Camera*", true, false) as Camera3D
		if cam:
			cam.make_current()
		camera_rig.global_position = cap_pos + Vector3(0.0, 2.6, 9.0)
		camera_rig.look_at(cap_pos + Vector3(0.0, 1.2, 0.0), Vector3.UP)

	var fade_rect = _get_or_create_fade_rect()
	fade_rect.modulate.a = 1.0
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_screen_in(0.4)

	# Dialog awal Ona & Rallux di depan kapsul sebelum Rion bangun
	var present_1: Array[String] = [
		"Ona: \"Jadi... rekaman log kapsulnya benar-benar tidak bisa dipulihkan sama sekali, Tuan Rallux?\"",
		"Rallux: \"Semua catatan riwayat di sistem kapsul hangus terbakar saat menembus orbit. Rion kehilangan seluruh ingatannya, Ona. Dia tidak tahu dari mana asalnya, siapa keluarganya, atau ke mana arah tujuannya.\"",
		"Ona: \"Pasti sangat membingungkan baginya... terbangun di tempat asing tanpa tahu siapa dirinya sebenarnya.\"",
		"Rallux: \"Benar. Tapi kemarin sore kamu sudah memberinya ruang yang aman. Saat rasa takutnya mereda, mesin pikirannya mulai bernapas lagi dengan tenang. Kita tidak perlu memaksanya mengingat semuanya sekaligus. Hari ini kita temani dia menata energinya lewat kegiatan-kegiatan sederhana di bengkel.\""
	]
	StoryManager.start_dialogue(present_1, "Ona")
	await StoryManager.dialogue_finished

	# Transisi fade ke Rion bangun di Point2
	await _fade_screen_out(0.4)

	# 3. Summon Rion di Point2, hadapkan ke Point3
	var walk_dir: Vector3 = p3_pos - p2_pos
	walk_dir.y = 0.0
	if walk_dir.length_squared() > 0.01:
		walk_dir = walk_dir.normalized()
	else:
		walk_dir = Vector3(1.0, 0.0, 0.0)

	if player:
		player.global_position = p2_pos
		player.rotation = Vector3.ZERO
	if rion_mesh:
		rion_mesh.rotation.y = atan2(walk_dir.x, walk_dir.z)

	if camera_rig:
		camera_rig.global_position = p2_pos + Vector3(-3.5, 2.3, 3.5)
		camera_rig.look_at(p2_pos + Vector3(0.0, 1.2, 0.0), Vector3.UP)

	await _fade_screen_in(0.4)

	# 4. Rion berjalan dari Point2 ke Point3
	if p_anim:
		p_anim.set("parameters/StateMachine/Move/blend_position", 0.5)

	var walk_tween = create_tween().set_parallel(true)
	if player:
		walk_tween.tween_property(player, "global_position", p3_pos, 3.0)
	if camera_rig:
		var cam_dest = p3_pos + Vector3(-3.5, 2.3, 3.5)
		walk_tween.tween_property(camera_rig, "global_position", cam_dest, 3.0)
	await walk_tween.finished

	if p_anim:
		p_anim.set("parameters/StateMachine/Move/blend_position", 0.0)
	if camera_rig and player:
		camera_rig.look_at(player.global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP)

	# 5. Dialog Hoam: Rion mencari mereka dari Point3
	var rion_wake: Array[String] = [
		"Rion: \"Hoaaam... Ona...? Tuan Rallux...? Kalian di mana?\""
	]
	StoryManager.start_dialogue(rion_wake, "Rion")
	await StoryManager.dialogue_finished

	# Ona & Rallux dari depan kapsul menoleh ke arah Rion di Point3
	if ona and player:
		var d_o: Vector3 = player.global_position - ona.global_position
		d_o.y = 0.0
		if d_o.length_squared() > 0.01:
			ona.rotation.y = atan2(-d_o.x, -d_o.z)
	if rallux and player:
		var d_r: Vector3 = player.global_position - rallux.global_position
		d_r.y = 0.0
		if d_r.length_squared() > 0.01:
			rallux.rotation.y = atan2(d_r.x, d_r.z)

	var ona_greet: Array[String] = [
		"Ona: \"Selamat pagi, Rion! Nyenyak tidurnya semalam?\""
	]
	StoryManager.start_dialogue(ona_greet, "Ona")
	await StoryManager.dialogue_finished

	# 5. Setelah disapa Ona, barulah Rion menghadap ke arah kapsul (di mana Ona & Rallux berada)
	var dir_to_cap: Vector3 = cap_pos - (player.global_position if player else p3_pos)
	dir_to_cap.y = 0.0
	if dir_to_cap.length_squared() > 0.01:
		dir_to_cap = dir_to_cap.normalized()
	else:
		dir_to_cap = Vector3(0.0, 0.0, -1.0)

	if rion_mesh:
		var turn_tw = create_tween()
		turn_tw.tween_property(rion_mesh, "rotation:y", atan2(dir_to_cap.x, dir_to_cap.z), 0.6)
		await turn_tw.finished

	if camera_rig and player:
		var cam_tw = create_tween()
		var cam_cap_pos = player.global_position - dir_to_cap * 4.0 + Vector3(-1.5, 2.0, 0.0)
		cam_tw.tween_property(camera_rig, "global_position", cam_cap_pos, 0.8)
		await cam_tw.finished
		camera_rig.look_at(cap_pos + Vector3(0.0, 1.5, 0.0), Vector3.UP)

	var capsule_dialog: Array[String] = [
		"Rion: \"Selamat pagi! Tidurku nyenyak banget... Kasurnya empuk dan gak dingin sama sekali!\"",
		"Rion: \"Lho?! Itu kan... kapsul besi yang aku naiki kemarin! Kok bisa sudah ada di sini dan bersih banget?!\"",
		"Rion: \"Kalian mau bongkar ya? Mau ambil mesinnya? Jangan diapa-apain! Cuma itu satu-satunya barang yang tersisa pas aku bangun kemarin!\"",
		"Ona: \"Tenang, Rion... tarik napas dulu. Tidak ada yang membongkar kapsulmu. Semuanya masih utuh dan aman persis seperti kemarin.\"",
		"Rallux: \"Oho, jangan panik dulu, Nak. Aku tahu kapsul itu sangat berharga buatmu. Semalam, hutan jamur mulai turun kabut asam. Kalau kapsul logammu dibiarkan kehujanan di tanah basah semalaman, kabel-kabelnya bisa korsleting dan karatan.\"",
		"Rallux: \"Jadi subuh tadi, aku dan Ona membawanya kemari pakai derek gravitasi mini. Kami juga sudah mencuci sisa lumut dan lumpur asamnya sampai bersih mengilap. Anggap saja ini servis selamat datang dari bengkel kami.\"",
		"Rion: \"...Oh. Jadi bukan dibongkar...? Maaf... aku langsung nuduh yang aneh-aneh. Terima kasih banyak ya, Tuan Rallux, Ona. Kapsul ini... memang satu-satunya petunjuk siapa diriku.\"",
		"Rallux: \"Sama-sama, Rion. Nah, karena urusan kapsul sudah beres dan harinya sudah cerah... bagaimana kalau kita sarapan dulu? Ona sudah memasak sup biji kacang hangat dan roti gandum bakar di beranda depan.\""
	]
	StoryManager.start_dialogue(capsule_dialog, "Rion")
	await StoryManager.dialogue_finished

	# 6. Pilihan respons pemain untuk sarapan
	var choice_opts: Array[String] = [
		"Boleh, Tuan Rallux... perutku rasanya memang mulai keroncongan.",
		"Nanti dulu deh... dadaku masih agak deg-degan, belum nafsu."
	]
	var choice_idx: int = await _prompt_choice(choice_opts)
	if choice_idx == 0:
		var opt_a: Array[String] = [
			"Rion: \"Boleh, Tuan Rallux... pas rasa kagetnya agak hilang, perutku langsung kerasa kosong. Aku mau ikut sarapan.\"",
			"Rallux: \"Pilihan jempolan, Rion! Kamu tahu tidak, tubuh dan isi kepala kita itu cara kerjanya mirip sekali dengan mesin di kapsulmu. Otak kita butuh bahan bakar dan tenaga hangat di pagi hari. Kalau baterai tubuhmu terisi penuh, kepala kita jadi jauh lebih tenang, pikiran lebih jernih, dan kita gak gampang kaget atau cepat lelah saat mencoba hal-hal baru.\"",
			"Rion: \"Wah, iya juga ya... pantesan kemarin pas lapar badanku sempat lemas dan gampang bingung.\"",
			"Rallux: \"Tepat sekali! Makanya sarapan itu kunci utama buat mengisi tenaga kita. Yuk, kita melangkah ke beranda luar!\""
		]
		StoryManager.start_dialogue(opt_a, "Rion")
		await StoryManager.dialogue_finished
	else:
		var opt_b: Array[String] = [
			"Rion: \"Nanti dulu deh, Tuan Rallux... habis kaget tadi, dadaku masih agak deg-degan. Rasanya belum nafsu makan apa-apa.\"",
			"Rallux: \"Nggak apa-apa, Nak. Wajar kok kalau sehabis kaget perutmu terasa belum siap menerima makanan.\"",
			"Rallux: \"Tapi aku mau kasih tahu rahasia kecil: tubuh dan isi kepala kita itu cara kerjanya mirip sekali dengan mesin di kapsulmu. Kadang-kadang, rasa cemas dan deg-degan kita jadi lebih susah reda karena baterai tubuh kita lagi kosong.\"",
			"Rion: \"Maksudnya... rasa deg-deganku susah hilang gara-gara belum makan?\"",
			"Rallux: \"Tepat sekali! Kalau mesin kehabisan bahan bakar, mesinnya bakal bergetar kencang dan alarm di dalamnya gampang berbunyi panik.\"",
			"Rallux: \"Begitu perutmu mendapat sarapan hangat, tubuhmu akan kirim kabar ke kepala kalau semuanya sudah aman dan tenang. Daripada membiarkan rasa deg-deganmu bertahan lama, yuk kita jalan pelan-pelan ke beranda luar sambil hirup udara pagi.\"",
			"Rion: \"Oh... begitu ya... Kalau gitu aku ikut ke luar deh, Tuan Rallux. Mau coba isi baterai biar gak deg-degan lagi.\""
		]
		StoryManager.start_dialogue(opt_b, "Rion")
		await StoryManager.dialogue_finished

	# 7. Narasi layar hitam (transisi sarapan)
	var breakfast_narration: String = "Di bawah naungan beranda kebun yang sejuk dan semilir angin pagi, Rion menikmati sarapan hangat bersama Tuan Rallux dan Ona. Rasa hangat makanan mengembalikan energinya, dan mereka berbincang santai tanpa rasa takut lagi..."
	await _show_black_screen_narration(breakfast_narration, 4.0)

	# 8. Kembali ke dalam bengkel: Rion, Rallux, Ona santai di meja tengah (lurus lorong Point3)
	if player:
		player.global_position = p3_pos + Vector3(-2.4, 0.0, 0.0)
		player.velocity = Vector3.ZERO
		player.rotation = Vector3.ZERO
		_snap_to_ground(player)

	if ona:
		ona.global_position = p3_pos + Vector3(1.2, 0.0, -0.85)
		_snap_to_ground(ona)
		if ona.has_method("play_animation"):
			ona.play_animation("idle")

	if rallux:
		rallux.global_position = p3_pos + Vector3(1.2, 0.0, 0.85)
		_snap_to_ground(rallux)
		if rallux.has_method("play_animation"):
			rallux.play_animation("idle")

	if ona and player:
		var d_o: Vector3 = player.global_position - ona.global_position
		d_o.y = 0.0
		if d_o.length_squared() > 0.01:
			ona.rotation.y = atan2(-d_o.x, -d_o.z)

	if rallux and player:
		var d_r: Vector3 = player.global_position - rallux.global_position
		d_r.y = 0.0
		if d_r.length_squared() > 0.01:
			rallux.rotation.y = atan2(d_r.x, d_r.z)

	if rion_mesh and player:
		var d_mid: Vector3 = (p3_pos + Vector3(1.2, 0.0, 0.0)) - player.global_position
		d_mid.y = 0.0
		if d_mid.length_squared() > 0.01:
			rion_mesh.rotation.y = atan2(d_mid.x, d_mid.z)

	# Kamera disorot dari belakang Rion agak jauhan agar Rallux dan Ona terlihat jelas
	if camera_rig and player:
		camera_rig.global_position = player.global_position + Vector3(-4.6, 2.1, -0.6)
		camera_rig.look_at(p3_pos + Vector3(1.2, 1.1, 0.2), Vector3.UP)

	await _fade_screen_in(0.5)

	var post_breakfast: Array[String] = [
		"Rion: \"Wah... sup kacangnya enak sekali! Perutku hangat, dan kepalaku rasanya jauh lebih enteng sekarang.\"",
		"Ona: \"Syukurlah! Wajahmu juga sudah tidak sepucat tadi pagi.\"",
		"Rallux: \"Nah, sekarang biar kuperiksa sebentar kondisi fisikmu setelah istirahat dan sarapan. Berdiri diam sebentar ya, Nak.\""
	]
	StoryManager.start_dialogue(post_breakfast, "Rion")
	await StoryManager.dialogue_finished

	# Jeda observasi singkat oleh Rallux
	await get_tree().create_timer(1.2).timeout

	var health_check_2: Array[String] = [
		"Rallux: \"Luar biasa. Detak jantungmu stabil, sirkulasi energimu sangat bagus. Secara fisik, kamu 100% sehat dan kuat!\"",
		"Rion: \"Hehe, terima kasih! Tapi... kalau aku sehat, kenapa ya dari kemarin kepalaku sering terasa aneh?\"",
		"Rallux: \"Aneh bagaimana maksudmu?\"",
		"Rallux: \"Dari kemarin kulihat matamu bergerak sangat cepat ke mana-mana, tanganmu sering mengetuk-ngetuk benda di dekatmu, dan sepertinya kamu sangat gelisah kalau harus diam di satu tempat tanpa melakukan apa-apa. Benar begitu?\"",
		"Rion: \"Iya... benar banget, Tuan Rallux! Kadang rasanya ada terlalu banyak hal yang terjadi di kepalaku sekaligus.\""
	]
	StoryManager.start_dialogue(health_check_2, "Rallux")
	await StoryManager.dialogue_finished

	# 9. Kotak Curhat & Refleksi Diri (Interaktif)
	var input_header: String = "KOTAK CURHAT & REFLEKSI DIRI"
	var input_question: String = "Dalam kehidupan sehari-hari, hal apa yang sering terasa paling sulit atau bikin kamu kewalahan?\n(Contoh: gampang lupa, susah diam, susah mulai ngerjain sesuatu, dll)"
	var player_input: String = await _prompt_text_input(input_header, input_question, "Tulis jawabanmu di sini...")
	if player_input.strip_edges().is_empty():
		player_input = "gampang lupa dan susah diam"

	# 10. Dialog Refleksi & Psikoedukasi ADHD (Mesin Roket Turbo)
	var turbo_dialog: Array[String] = [
		"Rion: \"Itu dia... hal yang paling bikin aku capek atau kewalahan itu... " + player_input.strip_edges() + ".\"",
		"Rallux: \"Terima kasih sudah mau berbagi, Nak. Dengar baik-baik ya, Rion... apa yang kamu rasakan itu bukan tanda bahwa kamu rusak, lemah, atau nakal.\"",
		"Ona: \"Betul, Rion! Setiap orang punya tipe mesin pikiran yang berbeda-beda.\"",
		"Rallux: \"Pikiran kebanyakan orang bekerja seperti kereta rel biasa: bergerak di jalur yang sama, kecepatannya teratur, dan gampang berhenti di setiap stasiun. Tapi pikiranmu, Rion... pikiranmu bekerja seperti Mesin Roket Turbo!\"",
		"Rion: \"Mesin Roket Turbo...?\"",
		"Rallux: \"Tepat sekali! Mesinmu punya daya pacu yang luar biasa hebat, rasa ingin tahu yang tinggi, dan penuh energi. Tapi karena kecepatannya luar biasa tinggi, kamu sering kesulitan saat harus mengerem mendadak, atau gampang berbelok ke hal lain yang terlihat lebih menarik di sekitarmu.\"",
		"Ona: \"Jadi masalahnya bukan pada mesinmu yang rusak, melainkan kamu belum terbiasa memegang setir dan rem untuk roket secepat itu!\"",
		"Rion: \"Wah... jadi kepalaku ini bukan aneh, tapi punya mesin roket ya? Keren juga sih kalau dipikir-pikir... tapi tetap saja bikin repot kalau remnya blong!\"",
		"Rallux: \"Hahaha! Tentu saja. Dan rem itu bukan sesuatu yang langsung jadi dari pabrik, melainkan harus dilatih perlahan. Kita bisa pasang rambu-rambu kecil, membuat catatan navigasi, dan belajar cara mengatur laju bahan bakar mesinmu.\"",
		"Rion: \"Siap, Tuan Rallux! Aku mau belajar cara jadi kapten untuk mesin roket di kepalaku ini!\"",
		"Rallux: \"Bagus sekali semangatmu! Nah, sekarang kalian berdua santai dulu di sini. Aku mau ke kebun depan sebentar untuk memanen akar kristal sebelum matahari terlalu terik. Ona, tolong temani Rion ya.\"",
		"Ona: \"Beres, Tuan Rallux! Hati-hati di jalan!\""
	]
	StoryManager.start_dialogue(turbo_dialog, "Rion")
	await StoryManager.dialogue_finished

	# 11. Transisi fade: Tuan Rallux berangkat ke kebun, dipindahkan ke depan pintu keluar (Point4)
	await _fade_screen_out(0.4)

	if rallux:
		var p4_node: Node3D = null
		if storypoints:
			p4_node = storypoints.get_node_or_null("Point4") as Node3D
		var door_pos: Vector3 = p4_node.global_position if p4_node else Vector3(-67.2, 0.0, -43.3)
		rallux.global_position = door_pos
		rallux.rotation.y = deg_to_rad(-90.0) # Menghadap ke arah pintu keluar
		rallux.scale = Vector3(8.0, 8.0, 8.0)
		rallux.visible = true
		_snap_to_ground(rallux)
		_play_rallux_anim(rallux, "idle")

	# 12. Ona tetap di posisi dan rotasi awal, Rion menghadap Ona untuk dialog penutup
	if player and ona:
		var face_dir: Vector3 = ona.global_position - player.global_position
		face_dir.y = 0.0
		if face_dir.length_squared() > 0.01:
			if rion_mesh:
				rion_mesh.rotation.y = atan2(face_dir.x, face_dir.z)

	if camera_rig and player and ona:
		camera_rig.global_position = player.global_position + Vector3(-4.0, 1.9, -0.4)
		camera_rig.look_at(ona.global_position + Vector3(0.0, 1.1, 0.0), Vector3.UP)

	await _fade_screen_in(0.4)


	var cleanup_dialog: Array[String] = [
		"Rion: \"Ona... lihat deh lantainya. Barangnya masih berceceran ke mana-mana ya?\"",
		"Ona: \"Iya, tadi pagi Tuan Rallux belum sempat merapikannya karena buru-buru menyiapkan sarapan hangat untuk kita.\"",
		"Rion: \"Tuan Rallux kan sudah baik banget sama aku... Beliau merawat kapsulku, membuat sarapan, terus gak marah sama sekali waktu aku sempat curiga. Mumpung Tuan Rallux lagi periksa pipa di luar, gimana kalau kita beri kejutan? Kita bantu bereskan lantai bengkel ini bareng-bareng!\"",
		"Ona: \"Wah, ide yang luar biasa, Rion! Kamu punya perhatian yang hebat. Tuan Rallux pasti akan senang sekali melihat bengkelnya kembali rapi.\"",
		"Rion: \"Tapi... barangnya lumayan banyak. Kamu bantu arahkan ya, Ona? Biar pesawat turboku gak kebingungan milihnya.\"",
		"Ona: \"Tentu saja! Ayo kita lihat rak yang pertama.\""
	]
	StoryManager.start_dialogue(cleanup_dialog, "Rion")
	await StoryManager.dialogue_finished

	# [TRANSISI KAMERA & TAMPILAN OBJEKTIF]
	# Kamera permainan meluncur mulus mendekat dan menyorot langsung ke arah Rak Pertama di sisi kiri ruangan
	var rak1_pos := Vector3(2.4, 0.1, 37.6)

	GameManager.ona_hold_position = true
	_ona_follow = false

	# Sesi 1: Ona di depan Rak 2 saja menghadap ke Kapsul Rion
	if ona:
		ona.global_position = Vector3(-6.4, 0.0, 34.0)
		var d_ona: Vector3 = cap_pos - ona.global_position
		d_ona.y = 0.0
		if d_ona.length_squared() > 0.01:
			ona.rotation.y = atan2(-d_ona.x, -d_ona.z)
		_set_ona_anim(ona, "idle")

	# Pindahkan Rion ke depan Rak 1 menghadap rak
	if player:
		player.global_position = Vector3(2.4, 0.0, 33.5)
		player.velocity = Vector3.ZERO
		if rion_mesh:
			rion_mesh.rotation = Vector3.ZERO
		player.rotation = Vector3.ZERO

	# Kamera meluncur menyorot Rak 1 dan Rion
	if camera_rig:
		var cam_slide = create_tween().set_parallel(true)
		cam_slide.tween_property(camera_rig, "global_position", Vector3(2.4, 2.3, 28.5), 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await cam_slide.finished
		camera_rig.look_at(Vector3(2.4, 1.3, 37.6), Vector3.UP)

	var rak1_guide: Array[String] = [
		"Ona: \"Sistem pemandu aktif! Untuk rak pertama ini, tugas kita cukup mengumpulkan tiga Papan Sirkuit, tiga Roda Gigi, dan tiga Baut.\""
	]
	StoryManager.start_dialogue(rak1_guide, "Ona")
	await StoryManager.dialogue_finished

	GameManager.set_objective("Rapikan Rak Pertama (0/9)", 0, "")

	var rak1_order: Array[String] = [
		"Rion: \"Harus urut dari papan sirkuit dulu ya, Ona?\"",
		"Ona: \"Nggak perlu urut kok! Kamu bebas ambil barang mana saja yang paling dekat atau yang paling kamu suka duluan. Nanti rak pintarnya yang bakal menata barang itu ke posisi yang pas.\"",
		"Rion: \"Asyik! Bebas pilih ya! Aku mulai bereskan sekarang!\""
	]
	StoryManager.start_dialogue(rak1_order, "Rion")
	await StoryManager.dialogue_finished

	# 13. Aktifkan gameplay pembersihan rak pertama
	GameManager.r1_morning_intro_done = true
	GameManager.r1_puzzles_enabled = true

	var unpack_mgr = get_tree().get_first_node_in_group("unpacking_manager")
	if unpack_mgr and unpack_mgr.has_method("start_session_1"):
		unpack_mgr.start_session_1()

	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(true)
		else:
			hud.visible = true
	if player:
		player.set_physics_process(true)
		player.set_process_unhandled_input(true)
	if camera_rig:
		camera_rig.set_physics_process(true)
		camera_rig.set_process(true)
		camera_rig.set_process_unhandled_input(true)
		var player_cam = camera_rig.find_child("*Camera*", true, false) as Camera3D
		if player_cam:
			player_cam.make_current()
		camera_rig.yaw = PI
		camera_rig.pitch = 18.0
		camera_rig.zoom_distance = 6.8
		if camera_rig.has_method("snap_to_target"):
			camera_rig.snap_to_target()

var _mono_we: WorldEnvironment = null
var _mono_prev_enabled: bool = false
var _mono_prev_sat: float = 1.0
var _flashback_layer: CanvasLayer = null

func _set_monochrome(on: bool) -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	if on:
		_mono_we = we
		_mono_prev_enabled = we.environment.adjustment_enabled
		_mono_prev_sat = we.environment.adjustment_saturation
		we.environment.adjustment_enabled = true
		we.environment.adjustment_saturation = 0.0
	else:
		if _mono_we and _mono_we.environment:
			_mono_we.environment.adjustment_enabled = _mono_prev_enabled
			_mono_we.environment.adjustment_saturation = _mono_prev_sat

func _create_grayscale_flashback_filter() -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = 15
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec4 c = texture(screen_texture, SCREEN_UV);
	float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec2 uv = SCREEN_UV * (1.0 - SCREEN_UV.yx);
	float vig = uv.x * uv.y * 15.0;
	vig = clamp(pow(vig, 0.25), 0.0, 1.0);
	COLOR = vec4(vec3(gray) * vig, 1.0);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	cr.material = sm
	cl.add_child(cr)
	add_child(cl)
	return cl

func _set_flashback_particles(on: bool) -> void:
	if not on:
		if _flashback_layer:
			_flashback_layer.visible = false
		return
	if _flashback_layer == null:
		_flashback_layer = CanvasLayer.new()
		_flashback_layer.name = "FlashbackLayer"
		_flashback_layer.layer = 0
		add_child(_flashback_layer)
		var p := GPUParticles2D.new()
		p.name = "FlashbackParticles"
		p.amount = 70
		p.lifetime = 6.0
		p.preprocess = 6.0
		p.emitting = true
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 1.0, 1.0, 0.45))
		grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 16
		tex.height = 16
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		p.texture = tex
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(1100.0, 650.0, 0.0)
		mat.direction = Vector3(0.0, -1.0, 0.0)
		mat.spread = 180.0
		mat.initial_velocity_min = 3.0
		mat.initial_velocity_max = 10.0
		mat.gravity = Vector3.ZERO
		mat.scale_min = 0.4
		mat.scale_max = 1.3
		p.process_material = mat
		p.position = Vector2(960.0, 540.0)
		_flashback_layer.add_child(p)
	_flashback_layer.visible = true

## Paksa animasi Rallux (searching/idle/run) lewat state machine + pastikan loop.
func _play_rallux_anim(rallux: Node3D, anim_name: String) -> void:
	var at := rallux.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		at = rallux.find_child("AnimationTree", true, false) as AnimationTree
	if at:
		at.active = true
		var pb = at.get("parameters/playback")
		if pb:
			pb.travel(anim_name)
	var ap := rallux.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		ap = rallux.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		var a := ap.get_animation(anim_name)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
		if at == null and ap.current_animation != anim_name:
			ap.play(anim_name)

## Rallux berjalan keluar bengkel TANPA diiringi kamera. Animasi "run" dipaksa aktif.
func _run_rallux_leave(rallux: Node3D, route: Array, speed: float = 8.0) -> void:
	# State machine kadang tidak pindah, jadi paksa lewat AnimationPlayer langsung.
	var at := rallux.get_node_or_null("AnimationTree") as AnimationTree
	if at:
		at.active = false
	var ap := rallux.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		var run_anim := ap.get_animation("run")
		if run_anim:
			run_anim.loop_mode = Animation.LOOP_LINEAR
		ap.play("run")

	var prev := Time.get_ticks_msec()
	for i in range(1, route.size()):
		var to: Vector3 = route[i]
		var dist2d: float = Vector2(to.x - rallux.global_position.x, to.z - rallux.global_position.z).length()
		var time_limit := Time.get_ticks_msec() + int((dist2d / speed) * 1000.0) + 2000
		while rallux.global_position.distance_to(to) > 0.3:
			if Time.get_ticks_msec() > time_limit:
				break
			var now := Time.get_ticks_msec()
			var dt := clampf((now - prev) / 1000.0, 0.0, 0.1)
			prev = now
			var dir: Vector3 = to - rallux.global_position
			dir.y = 0.0
			if dir.length_squared() > 0.01:
				rallux.rotation.y = lerp_angle(rallux.rotation.y, atan2(dir.x, dir.z), 12.0 * dt)
			rallux.global_position = rallux.global_position.move_toward(to, speed * dt)
			await get_tree().physics_frame
		prev = Time.get_ticks_msec()
	rallux.global_position = route[route.size() - 1]

	# Kembalikan state machine ke idle sebelum disembunyikan
	if ap:
		ap.stop()
	if at:
		at.active = true
		var playback = at.get("parameters/playback")
		if playback:
			playback.start("idle")
	rallux.visible = false

## Rion berjalan ke target dengan kamera mengikuti dari belakang badannya.
func _walk_with_follow_camera(char: CharacterBody3D, target: Vector3, camera_rig: Node3D, speed: float = 6.0) -> void:
	var mesh := char.get_node_or_null("RionMesh")
	var anim := char.get_node_or_null("AnimationTree") as AnimationTree
	if anim:
		anim.set("parameters/StateMachine/Move/blend_position", 0.5)

	var start: Vector3 = char.global_position
	var walk_dir: Vector3 = target - start
	walk_dir.y = 0.0
	if walk_dir.length_squared() > 0.0001:
		walk_dir = walk_dir.normalized()
	else:
		walk_dir = Vector3(0.0, 0.0, -1.0)
	# Offset tetap (tidak berubah mengikuti rotasi) supaya kamera tidak getar
	var cam_offset: Vector3 = -walk_dir * 9.0 + Vector3(0.0, 2.8, 0.0)
	if camera_rig:
		camera_rig.global_position = char.global_position + cam_offset
		camera_rig.look_at(char.global_position + Vector3(0.0, 1.3, 0.0), Vector3.UP)

	var prev := Time.get_ticks_msec()
	while char.global_position.distance_to(target) > 0.3:
		var now := Time.get_ticks_msec()
		var dt := clampf((now - prev) / 1000.0, 0.0, 0.1)
		prev = now
		var dir: Vector3 = target - char.global_position
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			dir = dir.normalized()
			char.global_position = char.global_position.move_toward(target, speed * dt)
			if mesh:
				mesh.rotation.y = lerp_angle(mesh.rotation.y, atan2(dir.x, dir.z), 8.0 * dt)
			if camera_rig:
				var desired: Vector3 = char.global_position + cam_offset
				var a: float = 1.0 - exp(-10.0 * dt)
				camera_rig.global_position = camera_rig.global_position.lerp(desired, a)
				camera_rig.look_at(char.global_position + Vector3(0.0, 1.3, 0.0), Vector3.UP)
		await get_tree().physics_frame
	if anim:
		anim.set("parameters/StateMachine/Move/blend_position", 0.0)

## Rallux berlari menyusuri titik-titik rute dengan gerak tetap (move_toward per frame,
## bukan tween) sehingga dijamin sampai ke tujuan. Kamera mengikuti mulus setiap frame.
func _run_rallux_route(rallux: Node3D, route: Array, rallux_anim: AnimationPlayer, camera_rig: Node3D, speed: float = 9.0, end_idle: bool = true) -> void:
	if rallux.has_method("play_animation"):
		rallux.play_animation("run")
	elif rallux_anim:
		rallux_anim.play("run")

	var cam_offset: Vector3 = Vector3(-6.5, 4.2, 6.5)

	# Posisikan kamera dulu di belakang Rallux sebelum ia mulai berlari
	if camera_rig:
		var behind: Vector3 = rallux.global_position + cam_offset
		var cam_set: Tween = create_tween()
		cam_set.tween_property(camera_rig, "global_position", behind, 0.5)
		await cam_set.finished
		camera_rig.look_at(rallux.global_position + Vector3(0, 1.6, 0), Vector3.UP)

	var prev_time := Time.get_ticks_msec()

	for i in range(1, route.size()):
		var to: Vector3 = route[i]
		var dist2d: float = Vector2(
			to.x - rallux.global_position.x,
			to.z - rallux.global_position.z
		).length()
		var time_limit := Time.get_ticks_msec() + int((dist2d / speed) * 1000.0) + 1500

		while rallux.global_position.distance_to(to) > 0.2:
			if Time.get_ticks_msec() > time_limit:
				break
			var now := Time.get_ticks_msec()
			var dt := clampf((now - prev_time) / 1000.0, 0.0, 0.1)
			prev_time = now

			# Putar hadap Rallux secara mulus (lerp_angle) mengikuti arah gerak saat ini
			var dir: Vector3 = to - rallux.global_position
			dir.y = 0.0
			if dir.length() > 0.01:
				var target_rot = atan2(dir.x, dir.z)
				rallux.rotation.y = lerp_angle(rallux.rotation.y, target_rot, 12.0 * dt)

			var next_pos: Vector3 = rallux.global_position.move_toward(to, speed * dt)
			next_pos.y = to.y
			rallux.global_position = next_pos

			if camera_rig:
				var desired: Vector3 = rallux.global_position + cam_offset
				camera_rig.global_position = camera_rig.global_position.lerp(desired, 0.08)
				camera_rig.look_at(rallux.global_position + Vector3(0, 1.6, 0), Vector3.UP)
			await get_tree().physics_frame

		prev_time = Time.get_ticks_msec()

	rallux.global_position = route[route.size() - 1]
	if camera_rig:
		camera_rig.global_position = rallux.global_position + cam_offset
		camera_rig.look_at(rallux.global_position + Vector3(0, 1.6, 0), Vector3.UP)
	if end_idle:
		if rallux.has_method("play_animation"):
			rallux.play_animation("idle")
		elif rallux_anim:
			rallux_anim.play("idle")

## Cutscene obrolan di depan Battery-EC setelah puzzle terminal selesai
func play_battery_ec_cutscene() -> void:
	var player = find_child("Player", true, false) as CharacterBody3D
	var camera_rig = find_child("CameraRig", true, false)
	var rallux = find_child("Rallux", true, false) as Node3D
	var ona = find_child("Ona", true, false) as CharacterBody3D
	var hud = find_child("HUD", true, false)

	# 1. Nonaktifkan kontrol player & sembunyikan gameplay HUD
	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(false)
		else:
			hud.visible = false
	if player:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)

	# 2. Fade Out
	await _fade_screen_out(0.6)
	await get_tree().create_timer(0.2).timeout

	# 3. Posisikan Rallux & Rion di depan Battery-EC
	var battery_pos := Vector3(44.683, 0.0, -44.446)
	var rallux_pos := Vector3(35.007, 0.0, -43.817)
	var rion_pos := Vector3(44.142, 1.16, -37.878)

	if rallux:
		rallux.visible = true
		rallux.global_position = rallux_pos
		var r_dir := battery_pos - rallux_pos
		r_dir.y = 0.0
		if r_dir.length_squared() > 0.01:
			rallux.rotation.y = atan2(r_dir.x, r_dir.z)
		_play_rallux_anim(rallux, "idle")

	if player:
		player.global_position = rion_pos
		player.velocity = Vector3.ZERO
		var p_dir := battery_pos - rion_pos
		p_dir.y = 0.0
		var rion_mesh = player.get_node_or_null("RionMesh")
		if rion_mesh and p_dir.length_squared() > 0.01:
			rion_mesh.rotation.y = atan2(p_dir.x, p_dir.z)
		var anim_tree: AnimationTree = player.get_node_or_null("AnimationTree")
		if anim_tree:
			anim_tree.set("parameters/StateMachine/Move/blend_position", 0.0)

	# Ona sedang istirahat / isi baterai di ruangannya
	if ona:
		ona.visible = false

	# 4. Kamera dari belakang mereka mengarah ke Battery-EC
	if camera_rig:
		camera_rig.global_position = Vector3(37.5, 2.8, -33.0)
		camera_rig.look_at(Vector3(42.5, 1.4, -43.0), Vector3.UP)

	# 5. Fade In
	await _fade_screen_in(0.8)
	await get_tree().create_timer(0.4).timeout

	# 6. Dialog Utama Percakapan Baterai & Ona Pernah Marah
	var lines: Array[String] = [
		"Rallux: \"Nah, lihat ini, Rion. Aliran daya dari kabel yang kamu pasang tadi langsung mengalir ke tabung-tabung ini. Sekarang baterai cadangan bengkel kita sudah mulai terisi penuh lagi.\"",
		"Rion: \"Keren banget... Warnanya hangat banget. Ona juga lagi isi baterai di ruangannya kan ya, Tuan Rallux?\"",
		"Rallux: \"Betul. Ona sedang istirahat supaya mesin dan prosesor di kepalanya kembali dingin.\"",
		"Rion: \"Tuan Rallux... aku boleh tanya sesuatu gak tentang Ona?\"",
		"Rallux: \"Tentu saja boleh, Kapten. Mau tanya apa?\"",
		"Rion: \"Ona kan selalu ramah, sopan, terus sabar banget nemenin aku... Tapi, memangnya dulu Ona pernah marah sama Tuan Rallux?\"",
		"Rallux: \"Haha... pernah, Rion. Malah bukan cuma pernah, kami berdua dulu pernah saling marah dan mendiamkan satu sama lain seharian penuh.\"",
		"Rion: \"Hah?! Serius?! Tuan Rallux sama Ona pernah saling marah?! Kok bisa? Tuan Rallux kan baik banget, terus Ona juga gak kelihatan galak sama sekali!\"",
		"Rallux: \"Rion, aku ini orang biasa. Aku tidak selalu jadi orang yang sempurna. Ada hari-hari di mana aku capek sekali, banyak alat yang rusak, lalu kepalaku pusing. Waktu itu, aku sempat bicara dengan nada tinggi dan tidak sengaja membentak Ona karena aku sedang terburu-buru.\"",
		"Rion: \"Terus... Onanya gimana?\"",
		"Rallux: \"Ona kaget, lalu layarnya berkedip merah dan dia mogok bicara. Dia mengunci diri di ruang perakitan dan menolak membantuku. Saat itu aku sadar, robot maupun manusia, kalau diperlakukan tidak adil, pasti hatinya terasa sakit dan kesal.\"",
		"Rion: \"Kadang... kalau pikiranku lagi lari kencang banget atau pas aku lagi pengen main tapi disuruh diam, dadaku juga rasanya panas dan pengen marah, Tuan Rallux. Terus aku merasa bersalah... aku kira anak yang marah itu anak yang jahat.\"",
		"Rallux: \"Rasa marah itu bukan tanda kalau kamu anak jahat, Rion. Rasa marah itu cuma alarm di dalam dada kita yang memberitahu kalau ada sesuatu yang bikin kita tidak nyaman atau capek. Yang membuat masalah jadi rumit itu bukan rasa marahnya, tapi apa yang kita lakukan saat sedang marah.\"",
		"Rion: \"Lalu waktu itu, Tuan Rallux sama Ona gimana caranya bisa baikan lagi?\"",
		"Rallux: \"Aku menunggu sampai kepalaku dingin dulu. Setelah napasku tenang, aku yang pertama datang mengetuk pintu ruangan Ona. Aku meminta maaf dengan jujur, mengakui kalau aku salah karena sudah membentak. Begitu mendengar aku minta maaf, Ona juga minta maaf karena sudah mendiamkanku. Kami berpelukan, dan bengkel ini kembali terasa nyaman.\"",
		"Rion: \"Jadi... gak apa-apa ya kalau kita salah, asalkan kita berani minta maaf dan memperbaiki hubungan lagi?\"",
		"Rallux: \"Tepat sekali, petualang kecil! Mengakui kesalahan dan berani minta maaf itu butuh keberanian yang sangat besar. Orang hebat bukan orang yang gak pernah marah, tapi orang yang tahu cara berbaikan kembali.\""
	]
	if StoryManager and StoryManager.has_method("start_dialogue"):
		StoryManager.start_dialogue(lines, "Rallux")
		await StoryManager.dialogue_finished

	# (BZZT... Bunyi lonceng terminal energi berdenting pelan)
	if AudioManager:
		AudioManager.play_puzzle_solved()
	await get_tree().create_timer(1.0).timeout

	var closing_lines: Array[String] = [
		"Rallux: \"Nah, baterai utama bengkel sudah penuh seratus persen! Obrolan kita tadi pas sekali waktunya. Sekarang, ayo kita ke Ruang Penghancur Barang (Crusher Room) untuk menyalakan tuas lampu dan dayanya!\"",
		"Rion: \"Siap, Tuan Rallux! Ayo kita ke Ruang Crusher!\""
	]
	if StoryManager and StoryManager.has_method("start_dialogue"):
		StoryManager.start_dialogue(closing_lines, "Rallux")
		await StoryManager.dialogue_finished

	# 7. Kembalikan kamera dan kontrol gameplay
	if hud:
		if hud.has_method("set_gameplay_ui_visible"):
			hud.set_gameplay_ui_visible(true)
		else:
			hud.visible = true
	if player:
		player.set_physics_process(true)
		player.set_process_unhandled_input(true)
	if camera_rig:
		camera_rig.set_physics_process(true)
		camera_rig.set_process(true)
		camera_rig.set_process_unhandled_input(true)
		var player_cam = camera_rig.find_child("*Camera*", true, false) as Camera3D
		if player_cam:
			player_cam.make_current()
		if camera_rig.has_method("snap_to_target"):
			camera_rig.snap_to_target()
	GameManager.set_objective("Nyalakan tuas lampu di Ruang Crusher", 0, "")
