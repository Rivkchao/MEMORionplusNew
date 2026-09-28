# scenes/ui/ToBeContinueOverlay.gd
# Layar penutup "To Be Continue..." setelah semua misi R1 selesai.
# Dibuat murni dari kode agar tidak perlu mengubah file .tscn.
extends CanvasLayer

signal finished

@export var title_text: String = "Bersambung..."
@export var subtitle_text: String = "Kerja hebat, Kapten Rion!\nKamu telah belajar merapikan barang, menenangkan emosi, membetulkan terminal daya, dan saling peduli bersama Ona.\nPetualangan menjelajahi planet MEMORion akan berlanjut di babak berikutnya!"
@export var fade_to_black_time: float = 1.2
@export var text_fade_time: float = 1.5
@export var hold_time: float = 6.0
@export var pause_game: bool = true
## Scene tujuan setelah layar penutup. Kosongkan untuk berhenti di layar ini saja.
@export_file("*.tscn") var next_scene: String = "res://Menu/main_menu.tscn"

var _black: ColorRect
var _vbox: VBoxContainer
var _label: Label
var _sub_label: Label
var _btn_container: HBoxContainer
var _playing: bool = false

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func _build_ui() -> void:
	_black = ColorRect.new()
	_black.name = "Black"
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.color = Color(0.04, 0.06, 0.12, 1.0) # Biru malam kosmik
	_black.modulate.a = 0.0
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_black)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_vbox = VBoxContainer.new()
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_theme_constant_override("separation", 24)
	_vbox.modulate.a = 0.0
	center.add_child(_vbox)

	_label = Label.new()
	_label.name = "Title"
	_label.text = title_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 64)
	_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35)) # Kuning emas bintang
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_label.add_theme_constant_override("outline_size", 10)
	_vbox.add_child(_label)

	_sub_label = Label.new()
	_sub_label.name = "Subtitle"
	_sub_label.text = subtitle_text
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_label.custom_minimum_size = Vector2(720, 0)
	_sub_label.add_theme_font_size_override("font_size", 22)
	_sub_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_sub_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
	_sub_label.add_theme_constant_override("outline_size", 6)
	_vbox.add_child(_sub_label)

	_btn_container = HBoxContainer.new()
	_btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_container.add_theme_constant_override("separation", 20)
	_vbox.add_child(_btn_container)

	var btn_menu := Button.new()
	btn_menu.text = "Kembali ke Menu Utama"
	btn_menu.custom_minimum_size = Vector2(260, 52)
	btn_menu.add_theme_font_size_override("font_size", 20)
	btn_menu.pressed.connect(func():
		_go_to_next_scene()
	)
	_btn_container.add_child(btn_menu)

## Jalankan animasi penutup: fade ke hitam, lalu teks muncul.
func play() -> void:
	if _playing:
		return
	_playing = true

	if pause_game and get_tree() != null:
		get_tree().paused = true

	var fade_to_black := create_tween()
	fade_to_black.tween_property(_black, "modulate:a", 1.0, fade_to_black_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_to_black.finished

	var reveal := create_tween()
	reveal.tween_property(_vbox, "modulate:a", 1.0, text_fade_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await reveal.finished

	finished.emit()

## Pindah ke next_scene memakai LoadingScreen bila tersedia.
func _go_to_next_scene() -> void:
	var tree := get_tree()
	if tree == null:
		queue_free()
		return

	# Wajib unpause dulu agar LoadingScreen (PAUSABLE) bisa menjalankan tween-nya.
	if pause_game:
		tree.paused = false

	var loading := tree.root.get_node_or_null("LoadingScreen")
	if loading != null and loading.has_method("load_scene"):
		loading.load_scene(next_scene)
		# Biarkan fade LoadingScreen menutupi layar sebelum overlay dilepas.
		await tree.create_timer(0.6).timeout
		queue_free()
	else:
		tree.change_scene_to_file(next_scene)
		queue_free()

## Sembunyikan layar penutup dan lanjutkan game (dipakai bila perlu lanjut bermain).
func dismiss() -> void:
	var tween := create_tween()
	tween.tween_property(_black, "modulate:a", 0.0, 0.6)
	await tween.finished
	if pause_game and get_tree() != null:
		get_tree().paused = false
	queue_free()
