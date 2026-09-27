extends Node3D
class_name UnpackingManager3D

const TO_BE_CONTINUE_OVERLAY := preload("res://scenes/ui/ToBeContinueOverlay.gd")

@export var player: Node3D
@export var interact_distance: float = 3.5
@export var hold_offset: Vector3 = Vector3(0.0, 0.8, -1.2)
@export var speaker_name: String = "Rion"
@export var rak1_complete_dialogue: String = "Rak pertama sudah rapi! Sekarang mari bereskan rak kedua."
@export var rak2_complete_dialogue: String = "Semua rak sudah selesai dirapikan! Kerja bagus!"
@onready var rak1_container: Node3D = $RakUnpacking1
@onready var rak2_container: Node3D = $RakUnpacking2
var current_phase: int = 1

var held_item: UnpackItem3D = null
var current_total_items: int = 0
var current_placed_items: int = 0
var phase_completed: bool = false
var waiting_for_dialog: bool = false
var waiting_for_tasks: bool = false
var _last_missing_log: String = ""
var _ending_shown: bool = false

# Timer & Story Tracking
var session1_start_time: float = 0.0
var session1_duration: float = 0.0
var session2_start_time: float = 0.0
var session2_duration: float = 0.0
var _door_reminder_cooldown: float = 0.0
var _is_transitioning: bool = false

signal rak1_completed
signal all_completed

func _ready() -> void:
	add_to_group("unpacking_manager")
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
		if player == null and get_tree().current_scene:
			player = get_tree().current_scene.get_node_or_null("Player") as Node3D

	if GameManager.unpacking_completed:
		_restore_all_completed()
	elif GameManager.unpacking_rak1_done:
		_restore_rak1_completed()
		_setup_phase(2)
	else:
		_setup_phase(1)

func start_session_1() -> void:
	session1_start_time = Time.get_ticks_msec() / 1000.0
	_setup_phase(1)
	if GameManager:
		GameManager.set_objective("Rapikan Rak Pertama (0/9)", 0, "")

func _setup_phase(phase: int) -> void:
	current_phase = phase
	current_placed_items = 0
	current_total_items = 0
	phase_completed = false
	waiting_for_dialog = false
	held_item = null

	if rak1_container != null:
		_show_items(rak1_container)
		_set_container_interaction(rak1_container, phase == 1)

	if rak2_container != null:
		if phase == 2:
			_show_items(rak2_container)
			_set_container_interaction(rak2_container, true)
		else:
			_hide_items(rak2_container)
			_set_container_interaction(rak2_container, false)

	var active_container: Node3D = rak1_container if phase == 1 else rak2_container

	if active_container != null:
		var items = active_container.find_children("", "UnpackItem3D", true, false)
		current_total_items = items.size()

func _show_items(container: Node3D) -> void:
	if container == null:
		return
	container.visible = true
	for item in container.find_children("", "UnpackItem3D", true, false):
		var unpack_item := item as UnpackItem3D
		if unpack_item != null:
			unpack_item.visible = true

func _hide_items(container: Node3D) -> void:
	if container == null:
		return
	container.visible = true
	for item in container.find_children("", "UnpackItem3D", true, false):
		var unpack_item := item as UnpackItem3D
		if unpack_item != null:
			unpack_item.visible = false

func _set_container_interaction(container: Node3D, is_active: bool) -> void:
	if container == null:
		return

	container.process_mode = (
		Node.PROCESS_MODE_INHERIT
		if is_active
		else Node.PROCESS_MODE_DISABLED
	)

	for item in container.find_children("", "UnpackItem3D", true, false):
		var unpack_item := item as UnpackItem3D
		if unpack_item != null:
			unpack_item.process_mode = (
				Node.PROCESS_MODE_INHERIT
				if is_active
				else Node.PROCESS_MODE_DISABLED
			)

	for slot in container.find_children("", "UnpackingSlot3D", true, false):
		var unpack_slot := slot as UnpackingSlot3D
		if unpack_slot != null:
			unpack_slot.process_mode = (
				Node.PROCESS_MODE_INHERIT
				if is_active
				else Node.PROCESS_MODE_DISABLED
			)

func _process(delta: float) -> void:
	# Pengingat jika Rion berjalan terlalu jauh dari area rak / mendekati pintu keluar sebelum selesai
	if not GameManager.unpacking_completed and GameManager.r1_morning_intro_done and not _is_transitioning:
		if _door_reminder_cooldown > 0.0:
			_door_reminder_cooldown -= delta
		elif player != null:
			var near_door := player.global_position.distance_to(Vector3(-75.35, 0.0, -45.76)) < 25.0
			var wandering_hallway := player.global_position.x < -20.0 and player.global_position.z < 5.0
			if near_door or wandering_hallway:
				var dlg_open: bool = StoryManager.dialogue_box != null and StoryManager.dialogue_box.visible
				if not dlg_open:
					_door_reminder_cooldown = 20.0
					StoryManager.start_dialogue([
						"Ona: \"Eh, Kapten Rion! Pintu keluar masih tertutup dan Tuan Rallux masih sibuk di kebun. Yuk, kita selesaikan beres-beres barang di rak dulu supaya kejutannya berhasil!\""
					], "Ona")

	if held_item == null:
		return

	if held_item.is_placed:
		return

	if player == null:
		return

	var target_pos: Vector3 = (
		player.global_position
		+ (player.global_transform.basis * hold_offset)
	)

	held_item.global_position = held_item.global_position.lerp(
		target_pos,
		15.0 * delta
	)

	held_item.global_rotation = player.global_rotation

func _input(event: InputEvent) -> void:
	if phase_completed or waiting_for_dialog or _is_transitioning:
		return

	var is_interact := false
	if event.is_action_pressed("interact"):
		is_interact = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		is_interact = true

	if is_interact:
		if held_item == null:
			_try_interact_pickup()
		else:
			_try_interact_place()
		return

	if event.is_action_pressed("ui_cancel") and held_item != null:
		drop_held_item()
		return

	if event is InputEventScreenTouch and event.pressed:
		_try_touch_interact(event.position)

func drop_held_item() -> void:
	if held_item == null:
		return
	held_item.return_to_origin()
	held_item = null
	_highlight_matching_slots("", false)

func has_held_item() -> bool:
	return held_item != null

func get_nearest_item_distance() -> float:
	if player == null:
		return 999.0
	var active_container = _get_active_container()
	if active_container == null:
		return 999.0
	var min_d := 999.0
	for item in active_container.find_children("", "UnpackItem3D", true, false):
		var unpack_item := item as UnpackItem3D
		if unpack_item and not unpack_item.is_placed and unpack_item.visible:
			var d = player.global_position.distance_to(unpack_item.global_position)
			if d < min_d:
				min_d = d
	return min_d

func get_nearest_slot_distance() -> float:
	if player == null:
		return 999.0
	var active_container = _get_active_container()
	if active_container == null:
		return 999.0
	var min_d := 999.0
	for slot in active_container.find_children("", "UnpackingSlot3D", true, false):
		var unpack_slot := slot as UnpackingSlot3D
		if unpack_slot and not unpack_slot.occupied:
			var d = player.global_position.distance_to(unpack_slot.global_position)
			if d < min_d:
				min_d = d
	return min_d

func _try_touch_interact(screen_pos: Vector2) -> bool:
	var camera = get_viewport().get_camera_3d()
	if camera == null or player == null:
		return false

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var active_container = _get_active_container()
	if active_container == null:
		return false

	if held_item != null:
		for slot in active_container.find_children("", "UnpackingSlot3D", true, false):
			var unpack_slot := slot as UnpackingSlot3D
			if unpack_slot == null or unpack_slot.occupied or unpack_slot.accepts_item_type != held_item.item_type:
				continue
			var to_slot = unpack_slot.global_position - ray_origin
			var proj = to_slot.dot(ray_dir)
			if proj > 0.0:
				var closest = ray_origin + ray_dir * proj
				if closest.distance_to(unpack_slot.global_position) < 2.0:
					if player.global_position.distance_to(unpack_slot.global_position) <= interact_distance + 2.0:
						_try_interact_place()
						return true
	else:
		for item in active_container.find_children("", "UnpackItem3D", true, false):
			var unpack_item := item as UnpackItem3D
			if unpack_item == null or unpack_item.is_placed or not unpack_item.visible:
				continue
			var to_item = unpack_item.global_position - ray_origin
			var proj = to_item.dot(ray_dir)
			if proj > 0.0:
				var closest = ray_origin + ray_dir * proj
				if closest.distance_to(unpack_item.global_position) < 2.0:
					if player.global_position.distance_to(unpack_item.global_position) <= interact_distance + 2.0:
						held_item = unpack_item
						_highlight_matching_slots(unpack_item.item_type, true)
						return true
	return false

func _try_interact_pickup() -> void:
	if player == null:
		return

	var active_container: Node3D = _get_active_container()
	if active_container == null:
		return

	var nearest_item: UnpackItem3D = null
	var min_dist: float = interact_distance

	for item in active_container.find_children("", "UnpackItem3D", true, false):
		var unpack_item := item as UnpackItem3D
		if unpack_item == null or unpack_item.is_placed or not unpack_item.visible:
			continue

		var distance: float = player.global_position.distance_to(unpack_item.global_position)
		if distance < min_dist:
			min_dist = distance
			nearest_item = unpack_item

	if nearest_item == null:
		return

	held_item = nearest_item
	if AudioManager:
		AudioManager.play_rock_pickup()

	_highlight_matching_slots(nearest_item.item_type, true)

func _try_interact_place() -> void:
	if player == null or held_item == null:
		return

	var active_container: Node3D = _get_active_container()
	if active_container == null:
		return

	var matching_slot: UnpackingSlot3D = null
	var min_dist: float = interact_distance
	var player_flat := Vector3(player.global_position.x, 0.0, player.global_position.z)

	for slot in active_container.find_children("", "UnpackingSlot3D", true, false):
		var unpack_slot := slot as UnpackingSlot3D
		if unpack_slot == null or unpack_slot.occupied or unpack_slot.accepts_item_type != held_item.item_type:
			continue

		var slot_flat := Vector3(unpack_slot.global_position.x, 0.0, unpack_slot.global_position.z)
		var distance: float = player_flat.distance_to(slot_flat)
		if distance < min_dist:
			min_dist = distance
			matching_slot = unpack_slot

	if matching_slot == null:
		return

	var item_to_snap: UnpackItem3D = held_item
	held_item = null
	_highlight_matching_slots("", false)

	item_to_snap.is_placed = true
	matching_slot.snap_item(item_to_snap)
	if AudioManager:
		AudioManager.play_puzzle_step_correct()
	await matching_slot.item_snap_finished
	current_placed_items += 1
	print("Item placed: ", current_placed_items, "/", current_total_items)

	# Update counter HUD secara real-time
	if GameManager:
		var rack_label := "Pertama" if current_phase == 1 else "Kedua"
		GameManager.set_objective("Rapikan Rak " + rack_label + " (" + str(current_placed_items) + "/9)", 0, "")

	_check_phase_finish()

func _highlight_matching_slots(type: String, active: bool) -> void:
	var active_container: Node3D = _get_active_container()
	if active_container == null:
		return

	for slot in active_container.find_children("", "UnpackingSlot3D", true, false):
		var unpack_slot := slot as UnpackingSlot3D
		if unpack_slot == null or unpack_slot.occupied:
			continue
		var should_highlight: bool = (active and unpack_slot.accepts_item_type == type)
		unpack_slot.set_highlight(should_highlight)

func _get_active_container() -> Node3D:
	if current_phase == 1:
		return rak1_container
	if current_phase == 2:
		return rak2_container
	return null

func _check_phase_finish() -> void:
	if phase_completed or current_total_items <= 0:
		return

	if current_placed_items < current_total_items:
		return

	# PHASE SELESAI
	phase_completed = true
	if AudioManager:
		AudioManager.play_puzzle_solved()

	held_item = null
	_highlight_matching_slots("", false)

	if current_phase == 1:
		_handle_rak1_completed_sequence()
	elif current_phase == 2:
		_handle_rak2_completed_sequence()

## RAK 1 SELESAI: Evaluasi perasaan, text input modal, percabangan respon, dan transisi ke Rak 2
func _handle_rak1_completed_sequence() -> void:
	_is_transitioning = true
	waiting_for_dialog = true

	if session1_start_time > 0.0:
		session1_duration = (Time.get_ticks_msec() / 1000.0) - session1_start_time
	else:
		session1_duration = 30.0

	_set_container_interaction(rak1_container, false)
	GameManager.unpacking_rak1_done = true
	rak1_completed.emit()

	# Hentikan gerak pemain dan kamera untuk cutscene dialog
	if player:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.velocity = Vector3.ZERO
	var scene = get_tree().current_scene
	var camera_rig = scene.find_child("CameraRig", true, false) if scene else null
	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)

	# 1. Dialog selesai Rak 1
	var rak1_finish_lines: Array[String] = [
		"Rion: \"Wah... lihat deh, Ona! Begitu barang-barangnya tersusun rapi di tempatnya masing-masing, rasanya adem banget di kepala.\"",
		"Ona: \"Iya, kelihatan tenang dan nyaman banget ya. Kamu hebat sudah menata semuanya. Tapi selain ruangan ini yang rapi... aku lebih peduli sama keadaanmu, Rion. Gimana rasanya di dalam hatimu sekarang setelah menyelesaikan rak pertama tadi?\""
	]
	StoryManager.start_dialogue(rak1_finish_lines, "Rion")
	await StoryManager.dialogue_finished

	# 2. [KOTAK REFLEKSI DIRI: PERASAANMU]
	var player_input := "Lega"
	if scene and scene.has_method("_prompt_text_input"):
		player_input = await scene._prompt_text_input(
			"KOTAK REFLEKSI DIRI: PERASAANMU",
			"Apa yang sedang kamu rasakan setelah merapikan rak pertama tadi?\n(Contoh: Seru, Lega, Capek, Pusing, Senang, dll.)",
			"Ketik apa yang kamu rasakan di sini..."
		)
	if player_input.strip_edges().is_empty():
		player_input = "Lega"

	# 3. Percabangan Respons Perasaan Berdasarkan Input Pemain
	var input_clean := player_input.strip_edges()
	var lower := input_clean.to_lower()
	var is_negative := false
	var negative_words := ["capek", "lelah", "pusing", "kewalahan", "bingung", "berat", "penat", "bosan", "pegal", "takut", "marah", "sedih", "stress", "stres", "letih", "lesu", "sulit", "susah"]
	for nw in negative_words:
		if lower.contains(nw):
			is_negative = true
			break

	var branch_lines: Array[String] = []
	if is_negative:
		branch_lines = [
			"Rion: \"Jujur... rasanya... " + input_clean + ", Ona. Tadi pas pertama lihat lantainya berantakan, energiku langsung tersedot habis, walau sekarang barangnya sudah beres.\"",
			"Ona: \"Terima kasih banyak ya sudah mau cerita jujur kalau kamu merasa " + input_clean + ". Wajar banget kok kalau energimu terasa terkuras. Pikiran kita memang bisa kaget dan capek kalau melihat terlalu banyak barang berantakan sekaligus. Merasa lelah itu bukan kesalahan, tapi tanda dari tubuhmu untuk melambat sejenak. Yuk, kita tarik napas pelan bersama... lepaskan sisa tegang di pundakmu.\"",
			"Rion: \"Hoooh... iya, setelah dihembuskan, dadaku rasanya jadi jauh lebih longgar.\"",
			"Ona: \"Bagus sekali. Tidak ada yang mengejarmu di sini.\""
		]
	else:
		branch_lines = [
			"Rion: \"Rasanya... " + input_clean + ", Ona! Tadi sempat mikir bakal susah karena barangnya berceceran. Tapi pas dibebaskan ambil apa saja duluan dan jumlahnya cuma tiga-tiga, ternyata asyik dan gak bikin pusing!\"",
			"Ona: \"Senang mendengarnya! Merasakan " + input_clean + " dan bangga setelah menyelesaikan satu hal kecil itu bikin energimu tetap awet, Rion. Ternyata kalau tugas besar dipecah sedikit demi sedikit, semuanya terasa jauh lebih ringan ya.\""
		]
	StoryManager.start_dialogue(branch_lines, "Rion")
	await StoryManager.dialogue_finished

	# Hadiah Fragmen Rak 1: Tampilkan FragmentBox (Fragmen Keteraturan)
	var frag_box = get_node_or_null("/root/FragmentBox")
	if frag_box and frag_box.has_method("show_fragment"):
		await frag_box.show_fragment("unpacking_rak1")
	else:
		GameManager.collected_fragments["unpacking_rak1"] = true

	# 4. Transisi Menuju Rak Kedua
	var trans_lines: Array[String] = [
		"Ona: \"Nah, di sebelah sana masih ada satu rak lagi. Kita lakukan dengan santai seperti tadi. Kalau tenagamu sudah terkumpul kembali, kamu mau lanjut beres-beres sekarang?\"",
		"Rion: \"Siap! Ayo kita bereskan rak yang kedua, Ona!\""
	]
	StoryManager.start_dialogue(trans_lines, "Ona")
	await StoryManager.dialogue_finished

	# 5. Sesi 2: Ona di depan Rak 1 tetap menghadap ke Kapsul Rion, Rion di depan Rak 2
	var cap_pos := Vector3(-4.0, 0.0, -39.0)
	var cap_node = scene.find_child("RionCapsule", true, false) if scene else null
	if cap_node:
		var bar = cap_node.find_child("CapsuleBarier", true, false)
		if bar:
			cap_pos = bar.global_position
		else:
			cap_pos = cap_node.global_position
	cap_pos.y = 0.0

	var ona = scene.find_child("Ona", true, false) if scene else null
	if ona:
		ona.global_position = Vector3(2.4, 0.0, 34.0)
		var d_ona: Vector3 = cap_pos - ona.global_position
		d_ona.y = 0.0
		if d_ona.length_squared() > 0.01:
			ona.rotation.y = atan2(-d_ona.x, -d_ona.z)
		if ona.has_method("play_animation"):
			ona.play_animation("idle")

	# Pindahkan Rion ke depan Rak 2 menghadap rak
	if player:
		player.global_position = Vector3(-6.4, 0.0, 33.5)
		player.velocity = Vector3.ZERO
		var rion_mesh = player.get_node_or_null("RionMesh")
		if rion_mesh:
			rion_mesh.rotation = Vector3.ZERO
		player.rotation = Vector3.ZERO

	if camera_rig:
		var cam_slide = create_tween().set_parallel(true)
		cam_slide.tween_property(camera_rig, "global_position", Vector3(-6.4, 2.5, 27.5), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await cam_slide.finished
		camera_rig.look_at(Vector3(-6.4, 1.4, 37.6), Vector3.UP)

	# 6. Setup Gameplay Sesi 2 (Rak Kedua)
	_setup_phase(2)
	session2_start_time = Time.get_ticks_msec() / 1000.0
	if GameManager:
		GameManager.set_objective("Rapikan Rak Kedua (0/9)", 0, "")

	_is_transitioning = false
	waiting_for_dialog = false

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

## RAK 2 SELESAI: Perbandingan waktu sesi, fragmen memori, glitch Ona, dan kedatangan Rallux
func _handle_rak2_completed_sequence() -> void:
	_is_transitioning = true
	waiting_for_dialog = true

	if session2_start_time > 0.0:
		session2_duration = (Time.get_ticks_msec() / 1000.0) - session2_start_time
	else:
		session2_duration = 25.0

	_set_container_interaction(rak2_container, false)

	# Kunci kontrol selama cutscene akhir
	if player:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.velocity = Vector3.ZERO
	var scene = get_tree().current_scene
	var camera_rig = scene.find_child("CameraRig", true, false) if scene else null
	if camera_rig:
		camera_rig.set_physics_process(false)
		camera_rig.set_process(false)
		camera_rig.set_process_unhandled_input(false)

	# 1. Percabangan Evaluasi Waktu Background (Sesi 2 vs Sesi 1)
	var time_eval: Array[String] = []
	if session2_duration < session1_duration:
		time_eval = [
			"Ona: \"Wah, hebat banget, Rion! Gerakanmu di rak kedua ini terasa jauh lebih lincah. Karena sudah tahu caranya, tangan dan matamu langsung bergerak kompak tanpa ragu-ragu!\"",
			"Rion: \"Hehe, iya! Tadi pas lihat baut melayang, aku sudah langsung tahu harus diarahkan ke laci bawah!\""
		]
	else:
		time_eval = [
			"Ona: \"Bagus sekali, Rion. Di rak kedua ini kamu terlihat sangat tenang dan teliti. Memperhatikan setiap barang dengan santai tanpa harus tergesa-gesa itu cara yang sangat nyaman untuk menjaga pikiran tetap segar.\"",
			"Rion: \"Iya, Ona... aku sengaja pelan-pelan sambil lihat roda giginya berputar pas dipasang. Bikin tenang banget rasanya.\""
		]
	StoryManager.start_dialogue(time_eval, "Ona")
	await StoryManager.dialogue_finished

	# 2. Hadiah Puzzle: Fragmen Memori
	var frag_lines: Array[String] = [
		"Rion: \"Waaah... Ona, lihat! Fragmennya muncul lagi! Pas mendekat, rasanya hangat banget di tangan...\"",
		"Ona: \"Sistem pemindai dataku... masih belum punya catatan tentang benda ini, Rion. Di memoriku, kristal ini tidak terdaftar sama sekali. Tapi anehnya, setiap kali kamu berhasil mengendalikan pikiran turbomu untuk menyelesaikan sebuah tantangan, kristal ini selalu tercipta.\"",
		"Ona: \"Aku... aku rasanya senang dan bangga sekali melihat caramu berusaha tadi...\""
	]
	StoryManager.start_dialogue(frag_lines, "Rion")
	await StoryManager.dialogue_finished
	var frag_box_2 = get_node_or_null("/root/FragmentBox")
	if frag_box_2 and frag_box_2.has_method("show_fragment"):
		await frag_box_2.show_fragment("unpacking_rak2")
	else:
		GameManager.collected_fragments["unpacking_rak2"] = true

	# 3. Tiba-tiba: BZZZZT! — Suara dengungan listrik & glitch Ona
	await get_tree().create_timer(0.4).timeout
	var glitch_lines: Array[String] = [
		"Ona: \"Peringatan... Fluktuasi respon afektif tidak terdaftar terdeteksi pada sektor inti... Menyetel ulang batasan sistem... Mode kepatuhan dasar aktif.\"",
		"Rion: \"Lho? Ona, kamu kenapa?! Barusan ada suara mendesis keras di kepalamu! Kamu baik-baik saja kan?\"",
		"Ona: \"Saya baik-baik saja, Rion. Hanya lonjakan statis kecil pada kabel pendingin kipas. Sistem internal sudah beroperasi normal kembali.\""
	]
	StoryManager.start_dialogue(glitch_lines, "Ona")
	await StoryManager.dialogue_finished

	# 4. Kedatangan Tuan Rallux (melangkah cepat dari Point 2 ke Point 3 lalu menghadap ke rak)
	var rallux: Node3D = scene.find_child("Rallux", true, false) as Node3D if scene else null
	var storypoints = scene.find_child("StoryPointing2", true, false) if scene else null
	var p2_pos := Vector3(-22.378, 0.0, -7.185)
	var p3_pos := Vector3(-7.284, 0.0, -6.486)
	if storypoints:
		var m2 = storypoints.find_child("Point2", true, false) as Node3D
		if m2: p2_pos = m2.global_position
		var m3 = storypoints.find_child("Point3", true, false) as Node3D
		if m3: p3_pos = m3.global_position

	if rallux:
		rallux.visible = true
		rallux.scale = Vector3(8.0, 8.0, 8.0)
		rallux.global_position = p2_pos
		var dir_to_p3 := p3_pos - p2_pos
		dir_to_p3.y = 0.0
		if dir_to_p3.length_squared() > 0.01:
			rallux.rotation.y = atan2(dir_to_p3.x, dir_to_p3.z)
		if rallux.has_method("play_animation"):
			rallux.play_animation("run")

		if camera_rig:
			var cam_tw = create_tween().set_parallel(true)
			cam_tw.tween_property(camera_rig, "global_position", p3_pos + Vector3(-5.5, 3.2, 3.5), 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			camera_rig.look_at(p3_pos + Vector3(0.0, 1.4, 0.0), Vector3.UP)

		var run_dist := p2_pos.distance_to(p3_pos)
		var run_dur := clampf(run_dist / 6.0, 1.5, 2.8)
		var tw = create_tween()
		tw.tween_property(rallux, "global_position", p3_pos, run_dur).set_trans(Tween.TRANS_LINEAR)
		await tw.finished

		rallux.rotation.y = atan2(0.0, 1.0)
		if rallux.has_method("play_animation"):
			rallux.play_animation("idle")

	# Rion dan Ona berbalik menghadap ke arah Tuan Rallux di Point 3
	if player:
		var d_to_r := p3_pos - player.global_position
		d_to_r.y = 0.0
		var rion_mesh = player.get_node_or_null("RionMesh")
		if rion_mesh and d_to_r.length_squared() > 0.01:
			rion_mesh.rotation.y = atan2(d_to_r.x, d_to_r.z)
	var ona_node: Node3D = scene.find_child("Ona", true, false) as Node3D if scene else null
	if ona_node:
		var d_to_r := p3_pos - ona_node.global_position
		d_to_r.y = 0.0
		if d_to_r.length_squared() > 0.01:
			ona_node.rotation.y = atan2(d_to_r.x, d_to_r.z)

	# 5. Dialog apresiasi Tuan Rallux
	var rallux_arrival_dialog: Array[String] = [
		"Rallux: \"Wah, wah, wah! Luar biasa rapi banget ini! Hebat, hebat sekali!\"",
		"Rallux: \"Lantai bengkel yang tadi pagi kayak kapal pecah penuh ranjau baut... sekarang kinclong begini?! Siapa kapten hebat yang menyulap ruangan ini jadi sekeren dan setertata ini?!\"",
		"Rion: \"Aku sama Ona, Tuan Rallux! Tadi kami masukkan semuanya ke rak kiri dan rak kanan!\"",
		"Rallux: \"Keren banget kamu, Rion! Kakek beneran kagum dan bangga sekali! Menata barang sebanyak dan seberantakan tadi itu butuh ketelitian, kesabaran, dan fokus yang juara. Kamu membuktikan kalau pesawat turbo di kepalamu itu punya pilot yang hebat dan bisa bekerja sangat rapi!\"",
		"Ona: \"Rion menyelesaikannya dengan mandiri dan tenang, Tuan Rallux.\"",
		"Rion: \"Hehe... seru kok, Tuan Rallux! Rasanya plong banget pas lihat semua barangnya sudah duduk rapi di tempatnya.\"",
		"Rallux: \"Ruangan yang tertata selalu bikin pikiran kita ikutan adem, kan? Kamu sudah bikin suasana bengkel ini jadi jauh lebih cerah hari ini.\"",
		"Rallux: \"Oho... dan aku lihat, ada cahaya yang ikut berpendar di sakumu.\"",
		"Rion: \"Eh, iya! Pas raknya beres kami rapikan, tiba-tiba fragmen ini muncul lagi! Ona bilang datanya gak tahu fragmen apa ini. Tuan Rallux tahu ini benda apa?\"",
		"Rallux: \"Belum saatnya kamu mengetahui itu sekarang, petualang kecil. Yang paling penting, jaga benda itu baik-baik di sakumu. Jangan sampai hilang ya. Suatu saat nanti, kamu pasti akan sangat membutuhkannya.\"",
		"Rion: \"Siap! Bakal aku jaga baik-baik, Tuan Rallux!\"",
		"Rallux: \"Pintar! Nah, berhubung kejutan kalian luar biasa sukses dan bengkel ini sudah bersih rapi, ayo kita istirahat sejenak sambil merencanakan petualangan kita berikutnya!\""
	]
	StoryManager.start_dialogue(rallux_arrival_dialog, "Rallux")
	await StoryManager.dialogue_finished

	# 6. Selesaikan unpacking dan beralih ke objective tuas ruang crusher
	GameManager.unpacking_completed = true
	GameManager.ona_hold_position = false
	GameManager.set_objective("Nyalakan tuas lampu di Ruang Crusher", 0, "")
	all_completed.emit()

	_is_transitioning = false
	waiting_for_dialog = false

	var camera_rig_final = scene.find_child("CameraRig", true, false) if scene else null
	if player:
		player.set_physics_process(true)
		player.set_process_unhandled_input(true)
	if camera_rig_final:
		camera_rig_final.set_physics_process(true)
		camera_rig_final.set_process(true)
		camera_rig_final.set_process_unhandled_input(true)
		if camera_rig_final.has_method("snap_to_target"):
			camera_rig_final.snap_to_target()

func continue_to_next_phase() -> void:
	if current_phase == 1:
		waiting_for_dialog = false
		_setup_phase(2)

func _restore_rak1_completed() -> void:
	if rak1_container:
		_snap_container_items_instantly(rak1_container)
		_set_container_interaction(rak1_container, false)

func _restore_all_completed() -> void:
	phase_completed = true
	if rak1_container:
		_snap_container_items_instantly(rak1_container)
		_set_container_interaction(rak1_container, false)
	if rak2_container:
		_snap_container_items_instantly(rak2_container)
		_set_container_interaction(rak2_container, false)

func _snap_container_items_instantly(container: Node3D) -> void:
	if container == null:
		return
	container.visible = true
	var items = container.find_children("", "UnpackItem3D", true, false)
	var slots = container.find_children("", "UnpackingSlot3D", true, false)

	for slot in slots:
		var unpack_slot := slot as UnpackingSlot3D
		if unpack_slot == null:
			continue
		for item in items:
			var unpack_item := item as UnpackItem3D
			if unpack_item == null or unpack_item.is_placed:
				continue
			if unpack_item.item_type == unpack_slot.accepts_item_type:
				unpack_item.is_placed = true
				unpack_slot.occupied = true
				unpack_item.visible = true
				unpack_item.global_position = unpack_slot.global_position
				unpack_item.global_rotation = unpack_slot.global_rotation
				var col = unpack_item.find_child("CollisionShape3D", true, false) as CollisionShape3D
				if col:
					col.disabled = true
				if unpack_slot.preview_mesh:
					unpack_slot.preview_mesh.visible = false
				break
