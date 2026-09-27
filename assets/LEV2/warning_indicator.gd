extends Sprite3D

@export var blink_interval: float = 0.5
var _blink_tween: Tween
var _active: bool = false
var _light: OmniLight3D = null

func _ready() -> void:
	# Kalau terminal sudah selesai, warning tidak perlu tampil
	if GameManager.terminal_puzzle_done:
		visible = false
		set_process(false)
		return

	if StoryManager.has_signal("wire_puzzle_completed"):
		StoryManager.wire_puzzle_completed.connect(_on_puzzle_completed)

	_light = get_node_or_null("WarningOmniLight") as OmniLight3D
	if _light == null:
		_light = OmniLight3D.new()
		_light.name = "WarningOmniLight"
		_light.light_color = Color(1.0, 0.25, 0.1)
		_light.light_energy = 5.0
		_light.omni_range = 8.0
		add_child(_light)

	visible = true
	_refresh()

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	var should_show: bool = not GameManager.terminal_puzzle_done
	if should_show and not _active:
		_active = true
		visible = true
		if _light:
			_light.visible = true
		_start_blinking()
	elif not should_show and _active:
		_active = false
		if _blink_tween and _blink_tween.is_valid():
			_blink_tween.kill()
		visible = false
		if _light:
			_light.visible = false

func _start_blinking() -> void:
	if _blink_tween and _blink_tween.is_valid():
		_blink_tween.kill()
	_blink_tween = create_tween().set_loops()
	_blink_tween.tween_callback(func():
		visible = not visible
		if _light:
			_light.visible = visible
	).set_delay(blink_interval)

func _on_puzzle_completed(is_correct: bool) -> void:
	if is_correct:
		_active = false
		if _blink_tween and _blink_tween.is_valid():
			_blink_tween.kill()
		visible = false
		if _light:
			_light.visible = false
