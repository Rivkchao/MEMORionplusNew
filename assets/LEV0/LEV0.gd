extends Node3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var interior_kapsul: Node3D = $InteriorKapsul
@onready var interior_camera: Camera3D = $InteriorKapsul/Camera3D
@onready var color_rect: ColorRect = $InteriorKapsul/Camera3D/ColorRect
@onready var hologram_sprite: Sprite3D = $InteriorKapsul/Sprite3D

var dialogue_box: CanvasLayer = null
var emergency_choice_ui: CanvasLayer = null
var orbit_ui: CanvasLayer = null
var descent_tween: Tween = null

# State management
enum SceneStage {
	SCENE_1_WAKEUP,
	SCENE_2_CHOICE,
	SCENE_3_ORBIT,
	SCENE_4_DESCENT,
	COMPLETED
}

var current_stage: SceneStage = SceneStage.SCENE_1_WAKEUP
var has_picked_right_choice: bool = false

# Orbit spin state
var is_spinning: bool = false
var spin_speed: float = 2.4 # rad/sec
var shake_intensity: float = 0.0

# Sound effects
var sfx_success: AudioStream = null
var audio_player: AudioStreamPlayer = null

func _ready() -> void:
	_setup_audio()
	_setup_ui()
	_start_scene_1()

func _setup_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = &"Master"
	add_child(audio_player)
	
	if ResourceLoader.exists("res://assets/audio/sfx/success.wav"):
		sfx_success = load("res://assets/audio/sfx/success.wav")

func start_warning_sfx() -> void:
	if hologram_sprite and hologram_sprite.has_method("start_alarm"):
		hologram_sprite.start_alarm()

func stop_warning_sfx() -> void:
	if hologram_sprite and hologram_sprite.has_method("stop_alarm"):
		hologram_sprite.stop_alarm()

func play_sfx(stream: AudioStream) -> void:
	if stream and audio_player:
		audio_player.stream = stream
		audio_player.play()

func _setup_ui() -> void:
	# 1. DialogueBox
	var db_scene = load("res://scenes/ui/DialogueBox.tscn")
	if db_scene:
		dialogue_box = db_scene.instantiate()
		add_child(dialogue_box)
		dialogue_box.dialogue_started.connect(_on_dialogue_started)
		dialogue_box.dialogue_finished.connect(_on_dialogue_finished)

	# 2. Emergency Choice UI
	var choice_script = load("res://scenes/ui/EmergencyChoiceUI.gd")
	if choice_script:
		emergency_choice_ui = choice_script.new()
		add_child(emergency_choice_ui)
		emergency_choice_ui.choice_made.connect(_on_emergency_choice_made)

	# 3. Orbit Alignment UI
	var orbit_script = load("res://scenes/ui/OrbitAlignmentUI.gd")
	if orbit_script:
		orbit_ui = orbit_script.new()
		add_child(orbit_ui)
		orbit_ui.orbit_aligned.connect(_on_orbit_aligned)
		orbit_ui.align_attempt_failed.connect(_on_align_failed)

func _process(delta: float) -> void:
	# Capsule tumbling/spinning physics in orbit
	if is_spinning and interior_kapsul:
		interior_kapsul.rotate_z(spin_speed * delta)
		interior_kapsul.rotation.x = sin(Time.get_ticks_msec() * 0.006) * 0.12
		
		# Shake camera slightly due to turbulence
		if interior_camera:
			var shake = Vector3(
				randf_range(-0.015, 0.015),
				randf_range(-0.015, 0.015),
				0.0
			)
			interior_camera.position = Vector3(0, 0.0888, -0.1102) + shake

func _start_scene_1() -> void:
	current_stage = SceneStage.SCENE_1_WAKEUP
	if animation_player and animation_player.has_animation("babak_1"):
		animation_player.play("babak_1")
	
	# Wait for initial wake up eye blink animation (around 1.5 seconds)
	await get_tree().create_timer(1.6).timeout
	
	var lines: Array[String] = [
		"Rion: \"Aduh... pusing banget... Kepalaku rasanya berputar-putar...\"",
		"Rion: \"Lho... aku di mana? Ini tempat apa? Kok tanganku gak bisa digerakkin?!\"",
	]
	if dialogue_box:
		dialogue_box.start(lines)

func _start_scene_2() -> void:
	current_stage = SceneStage.SCENE_2_CHOICE
	
	# Alarm sound and emergency light effect
	start_warning_sfx()
	_flash_emergency_tint(Color(0.8, 0.1, 0.1, 0.4), 0.8)
	
	# Turn hologram on brightly
	if hologram_sprite:
		hologram_sprite.visible = true
		hologram_sprite.modulate = Color(1.0, 0.3, 0.3, 1.0)
	
	var lines: Array[String] = [
		"SISTEM KAPSUL: \"PERINGATAN: TERDETEKSI GRAVITASI PLANET. SISTEM KEAMANAN DARURAT DIAKTIFKAN.\"",
		"SISTEM KAPSUL: \"Sistem otomatis membuka sabuk pengaman Rion karena situasi darurat. Layar hologram bercahaya muncul tepat di hadapan Rion, menampilkan pilihan kendali manual darurat.\""
	]
	if dialogue_box:
		dialogue_box.start(lines)

func _on_emergency_choice_made(choice_index: int) -> void:
	if choice_index == 0:
		# Wrong choice: Keluar dari Kapsul
		_flash_emergency_tint(Color(1.0, 0.05, 0.05, 0.55), 0.5)
		
		# Shake cockpit violently
		var tw = create_tween()
		var orig_rot = interior_camera.rotation
		tw.tween_property(interior_camera, "rotation", orig_rot + Vector3(0.08, -0.05, 0.04), 0.06)
		tw.tween_property(interior_camera, "rotation", orig_rot - Vector3(0.06, 0.05, -0.04), 0.06)
		tw.tween_property(interior_camera, "rotation", orig_rot, 0.06)
		
		var lines: Array[String] = [
			"Rion: \"Aku harus keluar sekarang!!!\"",
			"[Notifikasi: TERLALU BERBAHAYA!!!]"
		]
		if emergency_choice_ui and emergency_choice_ui.wrong_choice_count >= emergency_choice_ui.MAX_WRONG_CHOICES:
			lines.append("Rion: \"Sial... tombol daruratnya korsleting dan rusak! Gak bisa dipencet lagi!\"")
		
		if dialogue_box:
			dialogue_box.start(lines)
			
	elif choice_index == 1:
		# Right choice: Gunakan seluruh sumber daya
		has_picked_right_choice = true
		play_sfx(sfx_success)
		_flash_emergency_tint(Color(0.1, 0.8, 1.0, 0.35), 0.6)
		
		var lines: Array[String] = [
			"Rion: \"Kalau keluar sekarang, bahaya banget di luar angkasa... Aku harus bertahan di dalam kapsul!\""
		]
		if dialogue_box:
			dialogue_box.start(lines)

func _start_scene_3() -> void:
	current_stage = SceneStage.SCENE_3_ORBIT
	is_spinning = true
	
	var lines: Array[String] = [
		"(Kapsul mulai berputar di orbit planet)",
		"Rion: \"Aduh, pusing! Cepat banget putarannya!\"",
		"[NOTIFIKASI SISTEM / UI PANDUAN] ⚠️ PERINGATAN: \"Berotasilah ke posisi orbit! Selaraskan arah kapsul dengan gravitasi planet!\"",
		"Rion: \"Tunggu... tenang dulu, Rion... Jangan buru-buru. Biarin masuk ke jalurnya dulu...\"",
		"Rion: \"Pas di garis hijau...\""
	]
	if dialogue_box:
		dialogue_box.start(lines)

func _on_orbit_aligned() -> void:
	# Successfully stabilized in orbit!
	is_spinning = false
	stop_warning_sfx()
	play_sfx(sfx_success)
	
	# Smoothly decelerate rotation and align forward
	if interior_kapsul:
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(interior_kapsul, "rotation", Vector3.ZERO, 1.2)
		if interior_camera:
			tw.tween_property(interior_camera, "position", Vector3(0, 0.0888, -0.1102), 0.6)
			tw.tween_property(interior_camera, "rotation", Vector3.ZERO, 0.8)
	
	# Show "Sekarang!!!" exclamation line
	var lines: Array[String] = [
		"Rion: \"Sekarang!!!\""
	]
	if dialogue_box:
		dialogue_box.start(lines)

func _on_align_failed() -> void:
	# Capsule shakes on misfire
	_flash_emergency_tint(Color(1.0, 0.2, 0.2, 0.3), 0.3)
	if hologram_sprite and hologram_sprite.has_method("play_warning"):
		hologram_sprite.play_warning()

func _start_scene_4() -> void:
	current_stage = SceneStage.SCENE_4_DESCENT
	stop_warning_sfx()
	
	# Capsule surges forward into atmosphere
	if interior_kapsul:
		descent_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		descent_tween.tween_property(interior_kapsul, "position:z", -150.0, 4.5)
	
	var lines: Array[String] = [
		"Kapsul berhasil stabil! Moncong kapsul mengarah lurus menuju Hutan Jamur Kosmik di sebuah planet)",
		"Rion: \"Waaaaah! Meluncurrrr! ...Huh... hah... tarikan gravitasinya berat banget!\"",
		"Rion: \"Syukurlah... berhasil…\""
	]
	if dialogue_box:
		dialogue_box.start(lines)

func _finish_prologue() -> void:
	current_stage = SceneStage.COMPLETED
	stop_warning_sfx()
	
	# Akhir scene gelap pekat tanpa teks apapun
	var fade = CanvasLayer.new()
	fade.layer = 50
	add_child(fade)
	
	var rect = ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.add_child(rect)
	
	var tw = create_tween()
	tw.tween_property(rect, "color:a", 1.0, 2.5)
	await tw.finished
	if has_node("/root/LoadingScreen"):
		get_node("/root/LoadingScreen").load_scene("res://LEV1.tscn")
	else:
		get_tree().change_scene_to_file("res://LEV1.tscn")

func _on_dialogue_started() -> void:
	# Hanya pause animasi saat dialog muncul setelah emergent & orbitalignment selesai (Scene 4 / Descent)
	if current_stage == SceneStage.SCENE_4_DESCENT:
		if descent_tween and descent_tween.is_valid():
			descent_tween.pause()
		if animation_player and animation_player.is_playing():
			animation_player.pause()

func _on_dialogue_finished() -> void:
	match current_stage:
		SceneStage.SCENE_1_WAKEUP:
			_start_scene_2()
			
		SceneStage.SCENE_2_CHOICE:
			if has_picked_right_choice:
				_start_scene_3()
			else:
				# Buka / munculkan kembali choice menu setelah dialog selesai
				if emergency_choice_ui:
					emergency_choice_ui.open_menu()
				
		SceneStage.SCENE_3_ORBIT:
			if orbit_ui and not orbit_ui.is_active and not orbit_ui.is_completed:
				# Dialogue intro for orbit done, start minigame!
				orbit_ui.start_minigame()
			elif orbit_ui and orbit_ui.is_completed:
				# "Sekarang!!!" dialogue done, advance to Scene 4!
				_start_scene_4()
				
		SceneStage.SCENE_4_DESCENT:
			if descent_tween and descent_tween.is_valid():
				descent_tween.play()
				_flash_emergency_tint(Color(0.2, 0.5, 0.9, 0.25), 1.5)
				await descent_tween.finished
			if animation_player and animation_player.is_playing():
				await animation_player.animation_finished
			_finish_prologue()

func _flash_emergency_tint(color: Color, duration: float) -> void:
	if color_rect == null:
		return
	var orig_color = color_rect.color
	var tw = create_tween()
	tw.tween_property(color_rect, "color", color, duration * 0.4)
	tw.tween_property(color_rect, "color", Color(orig_color.r, orig_color.g, orig_color.b, 0.0), duration * 0.6)
