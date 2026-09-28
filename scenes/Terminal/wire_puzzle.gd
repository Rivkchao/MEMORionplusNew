extends CanvasLayer

@onready var wire_panel: Control = $WirePanel

signal puzzle_completed(is_correct: bool)

func _ready() -> void:
	hide()
	wire_panel.puzzle_completed.connect(_on_puzzle_completed)

func start() -> void:
	if GameManager.terminal_puzzle_done:
		hide()
		return
	show()
	wire_panel.setup()
		
func _on_puzzle_completed(is_correct: bool) -> void:
	if is_correct:
		hide()
	puzzle_completed.emit(is_correct)
