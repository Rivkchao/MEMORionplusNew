extends Node3D

@export var jet_sound: AudioStream = preload("res://assets/audio/sfx/jet.wav")
@export var volume_db: float = 0.0
@export var max_distance: float = 50.0

var _audio_player: AudioStreamPlayer3D

func _ready() -> void:
	_setup_audio()

func _setup_audio() -> void:
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "JetAudioPlayer"

	_audio_player.stream = jet_sound
	_audio_player.volume_db = volume_db
	_audio_player.max_distance = max_distance

	if AudioServer.get_bus_index("SFX") != -1:
		_audio_player.bus = &"SFX"
	else:
		_audio_player.bus = &"Master"
	add_child(_audio_player)
	_audio_player.play()

func stop_jet() -> void:
	if _audio_player and _audio_player.playing:
		_audio_player.stop()
