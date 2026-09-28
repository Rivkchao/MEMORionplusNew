extends Node3D

@export var hold_time := 3.0
@export var lever_light: OmniLight3D
@export var world_environment: WorldEnvironment
@export var door_node: Area3D
@export var interact_distance := 6.0
@export var bright_ambient_energy := 0.7

@export_group("Lever Animation")
@export var lever_handle: Node3D
@export var target_down_angle: float = -120.0

@onready var progress_label: Label3D = $ProgressLabel

var holding := false
var progress := 0.0
var completed := false
var initial_rot_z: float = 0.0
var player_node: Node3D = null
var is_near: bool = false
var _touch_holding: bool = false

# Timer interval agar Output tidak spam setiap frame
var debug_timer: float = 0.0
var _pull_sound_timer: float = 0.0

func is_player_near() -> bool:
	return is_near and not completed

func _unhandled_input(event: InputEvent) -> void:
	if completed or not is_near:
		_touch_holding = false
		return
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			var cam = get_viewport().get_camera_3d()
			if cam:
				var pos_3d = lever_handle.global_position if lever_handle else global_position
				var screen_pos = cam.unproject_position(pos_3d)
				if event.position.distance_to(screen_pos) < 140.0:
					_touch_holding = true
		else:
			_touch_holding = false


func _ready() -> void:
	add_to_group("levers")
	print_rich("[color=cyan]=== INITIALIZING LEVER (%s) ===[/color]" % name)

	if progress_label:
		progress_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		progress_label.no_depth_test = true
		progress_label.visible = false
	else:
		print_rich("[color=red][LEVER ERROR][/color] Child node 'ProgressLabel' tidak ditemukan!")

	if lever_light:
		lever_light.visible = true

	if lever_handle:
		initial_rot_z = lever_handle.rotation_degrees.z
		print("[LEVER] Handle terpasang di: ", lever_handle.name)
	else:
		print_rich("[color=yellow][LEVER WARNING][/color] 'lever_handle' belum dimasukkan di Inspector!")

	if not door_node:
		print_rich("[color=yellow][LEVER WARNING][/color] 'door_node' belum dimasukkan di Inspector!")

	var lever_id := get_parent().name + "_" + name
	if GameManager.solved_levers.get(lever_id, false):
		completed = true
		progress = 1.0
		if lever_handle:
			lever_handle.rotation_degrees.z = initial_rot_z + target_down_angle
		if lever_light:
			lever_light.visible = false
		if progress_label:
			progress_label.visible = false
		if door_node and "is_room_unlocked" in door_node:
			door_node.is_room_unlocked = true


func _process(delta: float) -> void:
	# Cek apakah ruangan sudah terbuka
	var is_unlocked: bool = false
	if door_node and "is_room_unlocked" in door_node:
		is_unlocked = door_node.is_room_unlocked

	if completed or is_unlocked:
		if lever_handle:
			lever_handle.rotation_degrees.z = initial_rot_z + target_down_angle
		if lever_light:
			lever_light.visible = false
		if progress_label:
			progress_label.visible = false
		return

	# Cari player jika belum ada
	if player_node == null:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]
			print_rich("[color=green][LEVER][/color] Player ditemukan via Group 'player': ", player_node.name)
		else:
			player_node = get_tree().root.find_child("Player", true, false)
			if player_node:
				print_rich("[color=yellow][LEVER][/color] Player ditemukan via nama node fallback: ", player_node.name)

	# Jika player tetap tidak ditemukan sama sekali
	if player_node == null:
		debug_timer += delta
		if debug_timer >= 2.0:
			print_rich("[color=red][LEVER GAGAL][/color] Player tidak terdeteksi! Pastikan Player ada di scene dan masuk group 'player'.")
			debug_timer = 0.0
		return

	# Ambil koordinat titik fisik tuas
	var switch_pos: Vector3 = lever_handle.global_position if lever_handle else global_position
	var player_pos: Vector3 = player_node.global_position
	var dist: float = switch_pos.distance_to(player_pos)
	is_near = dist <= interact_distance

	var is_mobile := SettingsManager != null and SettingsManager.is_mobile_controls_active()
	var hold_prompt := "[TAHAN AKSI]" if is_mobile else "[E] TAHAN"

	# Cek input tombol E / action / touch langsung
	var e_pressed = Input.is_key_pressed(KEY_E)
	var action_pressed = Input.is_action_pressed("interact") if InputMap.has_action("interact") else false
	var dialogue_open: bool = StoryManager.dialogue_box != null and StoryManager.dialogue_box.visible
	var key_active = (e_pressed or action_pressed or _touch_holding) and is_near and not dialogue_open

	# Log debug saat tombol ditekan
	if key_active:
		debug_timer += delta
		if debug_timer >= 0.5:
			print_rich("[color=white][DEBUG INPUT][/color] Menarik Tuas: %s | Jarak: [b]%.2f m[/b]" % [name, dist])
			debug_timer = 0.0

	# Tampilan teks saat player mendekat
	if is_near and not holding and progress == 0.0:
		if progress_label:
			progress_label.text = hold_prompt
			progress_label.visible = true
	elif not is_near and not holding:
		if progress_label and progress == 0.0:
			progress_label.visible = false

	# Logika menahan tuas
	if key_active:
		if not holding:
			print_rich("[color=green][LEVER][/color] Mulai menarik tuas...")
		holding = true
		progress += delta / hold_time
		progress = clamp(progress, 0.0, 1.0)

		# SFX ratchet tarikan tuas dengan pitch naik seiring progress
		_pull_sound_timer += delta
		if _pull_sound_timer >= 0.22 and progress < 1.0:
			_pull_sound_timer = 0.0
			if AudioManager:
				var pitch: float = lerpf(0.85, 1.35, progress)
				AudioManager.play_lever_ratchet(pitch, -4.0)

		if progress_label:
			progress_label.visible = true
			progress_label.text = str(int(progress * 100.0)) + "%"

		if lever_handle:
			lever_handle.rotation_degrees.z = lerp(initial_rot_z, initial_rot_z + target_down_angle, progress)

		# Kecerahan ruangan naik perlahan dari gelap (0.05) ke terang (bright_ambient_energy) seiring tarikan tuas 0% -> 100%
		if world_environment and world_environment.environment:
			world_environment.environment.ambient_light_energy = lerpf(0.05, bright_ambient_energy, progress)

		if progress >= 1.0:
			complete_lever()
	else:
		if holding:
			print_rich("[color=orange][LEVER][/color] Tombol dilepas sebelum 100%, kembali turun.")
			if AudioManager:
				AudioManager.play_lever_release(-6.0)
		holding = false
		_pull_sound_timer = 0.0
		if progress > 0.0:
			progress = move_toward(progress, 0.0, delta * 2.0)
			if lever_handle:
				lever_handle.rotation_degrees.z = lerp(initial_rot_z, initial_rot_z + target_down_angle, progress)
			if progress_label:
				progress_label.text = str(int(progress * 100.0)) + "%"
				if progress <= 0.0:
					progress_label.text = hold_prompt
			if world_environment and world_environment.environment:
				world_environment.environment.ambient_light_energy = lerpf(0.05, bright_ambient_energy, progress)


func complete_lever() -> void:
	completed = true
	holding = false
	progress = 1.0
	var lever_id := get_parent().name + "_" + name
	GameManager.solved_levers[lever_id] = true
	print_rich("[color=green][LEVER SELESAI][/color] 100%% tercapai! Menyalakan lampu...")

	if AudioManager:
		AudioManager.play_lever_complete(1.0)

	if progress_label:
		progress_label.text = "100%"

	if lever_handle:
		lever_handle.rotation_degrees.z = initial_rot_z + target_down_angle

	if door_node and "is_room_unlocked" in door_node:
		door_node.is_room_unlocked = true

	if world_environment and world_environment.environment:
		var tween := create_tween()
		tween.tween_property(world_environment.environment, "ambient_light_energy", bright_ambient_energy, 1.2)

	var light_tween := create_tween()
	light_tween.tween_interval(1.0)
	light_tween.tween_callback(func():
		if lever_light:
			lever_light.visible = false
		if progress_label:
			progress_label.visible = false
	)
	
	var is_crusher := "crusher" in get_parent().name.to_lower()
	var frag_key := "lever_crusher" if is_crusher else "lever_onaprogram"

	if is_crusher:
		var scene_cr := get_tree().current_scene
		var cam_cr: Node3D = scene_cr.find_child("CameraRig", true, false) as Node3D if scene_cr else null
		if cam_cr:
			var crusher_room = scene_cr.find_child("CrusherRoom", true, false)
			var microwave = crusher_room.find_child("SM_Microwave", true, false) as Node3D if crusher_room else null
			if not microwave and crusher_room:
				microwave = crusher_room.find_child("Crusher", true, false) as Node3D
			var cam_pos = microwave.global_position + Vector3(4.5, 3.8, 3.2) if microwave else Vector3(-30.0, 3.8, -31.5)
			var lever_pos = lever_handle.global_position if lever_handle else global_position
			cam_cr.global_position = cam_pos
			cam_cr.look_at(lever_pos + Vector3(0.0, 1.0, 0.0), Vector3.UP)

		if StoryManager and StoryManager.has_method("start_dialogue"):
			StoryManager.start_dialogue([
				"Rallux: \"Wah, hebat sekali, Rion! Ruang Crusher sudah terang benderang kembali!\"",
				"Rion: \"Mesin-mesin daur ulang mulai aktif dan suasananya jadi terang dan aman!\"",
				"Rallux: \"Pintar sekali! Sekarang, ayo kita lanjutkan ke Ruang Perakitan Ona. Kita nyalakan tuas lampu di sana, sekalian menjenguk Ona yang sedang mengisi daya!\"",
				"Rion: \"Asyik! Ayo kita ke Ruang Perakitan Ona, semoga baterainya sudah penuh!\""
			], "Rallux")
			await StoryManager.dialogue_finished

		if not GameManager.collected_fragments.get(frag_key, false):
			await FragmentBox.show_fragment(frag_key)

		# Transisi fade in langsung ke Ruang Perakitan & Pemrograman Ona
		if scene_cr and scene_cr.has_method("transition_to_onaprogram_lever"):
			await scene_cr.transition_to_onaprogram_lever()
		else:
			if cam_cr:
				cam_cr.set_physics_process(true)
				cam_cr.set_process(true)
				cam_cr.set_process_unhandled_input(true)
				if cam_cr.has_method("snap_to_target"):
					cam_cr.snap_to_target()
			GameManager.set_objective("Nyalakan tuas lampu di Ruang Perakitan Ona", 0, "")
	else:
		# Ruang Ona Program: Rion menyalakan tuas dan menjenguk Ona yang sedang recharge
		var scene := get_tree().current_scene
		var ona: Node3D = scene.find_child("Ona", true, false) if scene else null
		var rallux: Node3D = scene.find_child("Rallux", true, false) as Node3D if scene else null
		var camera_rig: Node3D = scene.find_child("CameraRig", true, false) as Node3D if scene else null

		if ona and ona.has_method("play_animation"):
			ona.play_animation("idle")

		# Posisikan Rion dan Rallux saling berhadapan dengan Ona
		if ona and player_node:
			var dir_to_ona: Vector3 = ona.global_position - player_node.global_position
			dir_to_ona.y = 0.0
			var rion_mesh = player_node.get_node_or_null("RionMesh")
			if rion_mesh and dir_to_ona.length_squared() > 0.01:
				rion_mesh.rotation.y = atan2(dir_to_ona.x, dir_to_ona.z)

			if rallux:
				rallux.visible = true
				var dir_r_ona: Vector3 = ona.global_position - rallux.global_position
				dir_r_ona.y = 0.0
				if dir_r_ona.length_squared() > 0.01:
					rallux.rotation.y = atan2(dir_r_ona.x, dir_r_ona.z)
				if rallux.has_method("play_animation"):
					rallux.play_animation("idle")

			var dir_o_player: Vector3 = player_node.global_position - ona.global_position
			dir_o_player.y = 0.0
			if dir_o_player.length_squared() > 0.01:
				ona.rotation.y = atan2(-dir_o_player.x, -dir_o_player.z)

		# Kamera saat Ona selesai charge shoot dari node previewona ke arah lever
		var preview_node: Node3D = null
		var ona_room = scene.find_child("OnaProgramRoom", true, false) if scene else null
		if ona_room:
			preview_node = ona_room.find_child("OnaPreview", true, false) as Node3D
			if not preview_node:
				preview_node = ona_room.find_child("PlatOnaPreview", true, false) as Node3D
		if not preview_node and scene:
			preview_node = scene.find_child("OnaPreview", true, false) as Node3D
			if not preview_node:
				preview_node = scene.find_child("PlatOnaPreview", true, false) as Node3D

		var preview_pos: Vector3 = preview_node.global_position if preview_node else Vector3(-44.817, 0.0, 23.912)
		var lever_target_pos: Vector3 = lever_handle.global_position if lever_handle else global_position

		var cam_target: Vector3 = preview_pos + Vector3(2.2, 7.6, 1.0)
		if camera_rig:
			camera_rig.set_physics_process(false)
			camera_rig.set_process(false)
			camera_rig.set_process_unhandled_input(false)
			var cam_tw = create_tween()
			cam_tw.tween_property(camera_rig, "global_position", cam_target, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			await cam_tw.finished
			camera_rig.look_at(Vector3(lever_target_pos.x, 1.8, lever_target_pos.z), Vector3.UP)

		if StoryManager and StoryManager.has_method("start_dialogue"):
			StoryManager.start_dialogue([
				"Ona: \"*Bip... bip... ding!* Sistem daya mendeteksi aliran energi utama telah pulih sepenuhnya...\"",
				"Rion: \"Ona! Kamu sudah bangun! Lihat, ruanganmu sudah terang benderang!\"",
				"Ona: \"Rion! Tuan Rallux! Terima kasih banyak sudah menyalakan tuas lampu dan membetulkan kabel terminal. Bateraiku sekarang sudah pulih seratus persen!\"",
				"Rallux: \"Hahaha! Syukurlah! Kerja sama kalian berdua benar-benar luar biasa. Saling membantu dan peduli saat sahabat membutuhkan dukungan.\"",
				"Rion: \"Semua berkat kerja sama tim kita, Tuan Rallux! Bersama Ona, petualangan jadi seru banget!\"",
				"Ona: \"Terima kasih sudah menjadi sahabat terbaikku, Rion. Sekarang bengkel sudah aman, dan kita siap untuk petualangan berikutnya!\"",
				"Rallux: \"Tepat sekali, anak-anak hebat. Beristirahatlah sejenak, karena perjalanan bintang kalian yang sesungguhnya baru saja dimulai...\""
			], "Ona")
			await StoryManager.dialogue_finished

		if not GameManager.collected_fragments.get(frag_key, false):
			await FragmentBox.show_fragment(frag_key)

		# Tampilkan layar To Be Continued...
		var tbc_script = load("res://scenes/ui/ToBeContinueOverlay.gd")
		if tbc_script:
			var tbc_overlay = tbc_script.new()
			get_tree().root.add_child(tbc_overlay)
			tbc_overlay.play()
