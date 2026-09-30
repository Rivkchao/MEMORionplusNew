extends Interactable

@onready var omni_light_1: OmniLight3D = $OmniLight3D
@onready var omni_light_2: OmniLight3D = $OmniLight3D2
	
@export var flicker_min_energy: float = 200.0
@export var flicker_max_energy: float = 500.0
@export var flicker_speed: float = 0.2

@export var solved_color: Color = Color(0.2, 1.0, 0.3) # Hijau
@export var solved_energy: float = 100.0

var _flicker_timer: float = 0.0
var _puzzle_solved: bool = false
var _is_interacting: bool = false

@export var warning_sound: AudioStream = preload("res://assets/audio/sfx/warning.wav")
@export var warning_volume_db: float = 3.0

const BGM_AMBIENT = preload("res://assets/audio/bgm/meditation_main.mp3")

var _warning_audio: AudioStreamPlayer3D
var _ambient_ducked: bool = false

func _ready() -> void:
	super._ready()
	interact_label = "Gunakan Terminal"
	StoryManager.wire_puzzle_completed.connect(_on_wire_puzzle_completed)
	
	_setup_warning_audio()
	if GameManager.terminal_puzzle_done:
		_puzzle_solved = true
		omni_light_1.light_color = solved_color
		omni_light_1.light_energy = solved_energy
		omni_light_2.light_color = solved_color
		omni_light_2.light_energy = solved_energy
		interact_label = ""
		var col = find_child("CollisionShape3D", true, false) as CollisionShape3D
		if col:
			col.set_deferred("disabled", true)
	else:
		_update_power_lights()

func _setup_warning_audio() -> void:
	_warning_audio = AudioStreamPlayer3D.new()
	_warning_audio.name = "WarningAudio"

	_warning_audio.stream = warning_sound
	_warning_audio.volume_db = warning_volume_db
	_warning_audio.max_distance = 20.0

	if AudioServer.get_bus_index("SFX") != -1:
		_warning_audio.bus = &"SFX"
	else:
		_warning_audio.bus = &"Master"

	# Loop warning sound. AudioStreamWAV hasil impor tidak punya titik loop; kalau
	# loop_mode diubah tanpa loop_begin/loop_end, stream dianggap loop 0..0 dan
	# langsung selesai sehingga warning tak terdengar.
	if warning_sound is AudioStreamWAV:
		warning_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
		warning_sound.loop_begin = 0
		var frames := int(round(warning_sound.get_length() * float(warning_sound.mix_rate)))
		if frames > 0:
			warning_sound.loop_end = frames

	add_child(_warning_audio)

func _ona_lever_done() -> bool:
	return GameManager.solved_levers.get("OnaProgramRoom_Lever", false)

func _levers_done() -> bool:
	return GameManager.unpacking_rak1_done \
		and GameManager.solved_levers.get("CrusherRoom_Lever", false) \
		and _ona_lever_done()

func _update_power_lights() -> void:
	if _puzzle_solved:
		return
	if omni_light_1:
		omni_light_1.visible = true
	if omni_light_2:
		omni_light_2.visible = true

func _process(delta: float) -> void:
	if _puzzle_solved:
		return
	if omni_light_1 and not omni_light_1.visible:
		omni_light_1.visible = true
		omni_light_2.visible = true
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		var energy = randf_range(flicker_min_energy, flicker_max_energy)
		omni_light_1.light_energy = energy
		omni_light_2.light_energy = energy * 0.8
		_flicker_timer = flicker_speed

func interact() -> void:
	if _puzzle_solved or GameManager.terminal_puzzle_done or _is_interacting:
		return
	if not GameManager.unpacking_completed:
		if StoryManager and StoryManager.has_method("start_dialogue"):
			StoryManager.start_dialogue([
				"Rallux: \"Rion, bereskan dulu barang-barang bengkel sebelum menyalakan terminal ya!\""
			], "Rallux")
		return
	_is_interacting = true
	_play_terminal_emergency()

func _play_warning_sound() -> void:
	if _warning_audio and not _warning_audio.playing:
		_warning_audio.play()

# Matikan BGM + ambience selama alarm terminal agar warning terdengar jelas.
func _enter_emergency_audio() -> void:
	if _ambient_ducked:
		return
	_ambient_ducked = true
	if AudioManager:
		AudioManager.stop_bgm(1.0)
		AudioManager.stop_ambience(1.0)

# Nyalakan lagi BGM meditation setelah puzzle terminal selesai.
func _restore_ambient_audio() -> void:
	if not _ambient_ducked:
		return
	_ambient_ducked = false
	if AudioManager:
		AudioManager.play_bgm(BGM_AMBIENT, 1.5, -4.0)

func _play_terminal_emergency() -> void:
	if _puzzle_solved or GameManager.terminal_puzzle_done:
		_is_interacting = false
		return

	_enter_emergency_audio()
	_play_warning_sound()

	var layer := CanvasLayer.new()
	layer.layer = 110

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(1.0, 0.1, 0.1, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	layer.add_child(rect)
	add_child(layer)

	var flash := create_tween().set_loops(4)
	flash.tween_property(rect, "color:a", 0.14, 0.25)
	flash.tween_property(rect, "color:a", 0.0, 0.25)

	var emergency: Array[String] = [
		"Rallux: \"Nah, ini dia Terminal Daya Utama kita, Rion.\"",
		"Rallux: \"Sebab kapsulmu jatuh kemarin, getarannya membuat kabel terminal berantakan sehingga beberapa ruangan mati lampu.\"",
		"Rallux: \"Jadi benerin dulu kabelnya ya! Sambungkan warna kabel kiri ke soket kanan yang pas agar sistem listrik stabil kembali.\"",
		"Rion: \"Wah, ternyata getaran kapsulku ya... Tenang, Tuan Rallux! Aku akan benerin kabelnya sampai rapi dan menyala lagi!\"",
		"Rallux: \"Pintar! Ingat-ingat warnanya saat menyala ya, kamu pasti bisa!\""
	]
	StoryManager.start_dialogue(emergency, "Rallux")
	await StoryManager.dialogue_finished

	if flash:
		flash.kill()
	if is_instance_valid(layer):
		layer.queue_free()

	if _puzzle_solved or GameManager.terminal_puzzle_done:
		_is_interacting = false
		return

	StoryManager.start_wire_puzzle()
	_is_interacting = false

func _on_wire_puzzle_completed(is_correct: bool) -> void:
	if is_correct and not _puzzle_solved:
		_puzzle_solved = true
		_is_interacting = false
		if _warning_audio and _warning_audio.playing:
			_warning_audio.stop()
		_restore_ambient_audio()
		GameManager.terminal_puzzle_done = true
		omni_light_1.light_color = solved_color
		omni_light_1.light_energy = solved_energy
		omni_light_2.light_color = solved_color
		omni_light_2.light_energy = solved_energy
		interact_label = ""
		var col = find_child("CollisionShape3D", true, false) as CollisionShape3D
		if col:
			col.set_deferred("disabled", true)

		# Dialog apresiasi Rallux setelah kabel terminal berhasil dibetulkan
		if StoryManager and StoryManager.has_method("start_dialogue"):
			var lines: Array[String] = [
				"Rallux: \"Wah, hebat sekali, Rion! Sambungan kabelnya sudah rapi dan pas! Lampu terminal menyala hijau stabil kembali!\"",
				"Rion: \"Horeee! Kabel terminalnya sudah beres dan listrik utama menyala lagi!\"",
				"Rallux: \"Luar biasa! Sekarang ayo kita ke Ruang Crusher untuk menyalakan tuas lampu di sana!\""
			]
			StoryManager.start_dialogue(lines, "Rallux")
			await StoryManager.dialogue_finished

		GameManager.terminal_puzzle_done = true

		# Transisi fade in tepat di depan tuas lampu Ruang Crusher
		var main_scene = get_tree().current_scene
		if main_scene and main_scene.has_method("transition_to_crusher_lever"):
			await main_scene.transition_to_crusher_lever()
		else:
			GameManager.set_objective("Nyalakan tuas lampu di Ruang Crusher", 0, "")
