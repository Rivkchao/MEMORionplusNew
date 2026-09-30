extends Sprite3D

@export var warning_sound: AudioStream = preload("res://assets/audio/sfx/warning.wav")
@export var volume_db: float = 2.0

var _audio_player: AudioStreamPlayer = null
var _is_active: bool = true
var _repeat_timer: Timer = null


func _ready() -> void:
	_setup_audio()
	_setup_timer()


func _setup_audio() -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "WarningAudioPlayer"

	if AudioServer.get_bus_index("SFX") != -1:
		_audio_player.bus = &"SFX"
	else:
		_audio_player.bus = &"Master"

	_audio_player.stream = warning_sound
	_audio_player.volume_db = volume_db

	add_child(_audio_player)


func _setup_timer() -> void:
	_repeat_timer = Timer.new()

	# 1 detik suara + 3 detik jeda
	_repeat_timer.wait_time = 1.3

	_repeat_timer.timeout.connect(func():
		if _is_active and visible:
			play_warning()

			var tw = create_tween()
			tw.tween_property(self, "modulate:a", 0.2, 0.15)
			tw.tween_property(self, "modulate:a", 1.0, 0.15)
	)

	add_child(_repeat_timer)


func play_warning() -> void:
	if not _is_active:
		return

	if _audio_player and _audio_player.stream:
		_audio_player.play()


func start_alarm() -> void:
	_is_active = true
	visible = true
	modulate = Color(1.0, 0.3, 0.3, 1.0)

	# Bunyi pertama langsung
	play_warning()

	# Setelah itu ulang setiap 4 detik
	if _repeat_timer:
		_repeat_timer.start()


func stop_alarm() -> void:
	_is_active = false
	visible = false

	if _repeat_timer:
		_repeat_timer.stop()

	if _audio_player and _audio_player.playing:
		_audio_player.stop()
