extends CanvasLayer

signal choice_made(index: int)

var font_bold: Font = null
var font_reg: Font = null

var wrong_choice_count: int = 0
const MAX_WRONG_CHOICES: int = 3

var btn_exit: Button = null
var btn_power: Button = null
var title_label: Label = null
var warning_banner: PanelContainer = null
var warning_label: Label = null

var sfx_click: AudioStream = null
var sfx_alarm: AudioStream = null
var sfx_success: AudioStream = null
var audio_player: AudioStreamPlayer = null

var is_locked: bool = false
var root_control: Control = null

func _ready() -> void:
	layer = 25
	_load_resources()
	_setup_audio()
	_build_ui()
	hide()

func _load_resources() -> void:
	var bold_path := "res://Fonts/Telegraf-Bold-fix15408087824949790956.30.2aa1f309-cb96-4ad6-a94f-e5147e9.ttf"
	var reg_path := "res://Fonts/telegraf_regular_fix7340951357143627189..44096e48-3548-42c1-bd8a-c4745e9.ttf"
	if ResourceLoader.exists(bold_path):
		font_bold = load(bold_path)
	if ResourceLoader.exists(reg_path):
		font_reg = load(reg_path)
		
	if ResourceLoader.exists("res://assets/audio/sfx/click.wav"):
		sfx_click = load("res://assets/audio/sfx/click.wav")
	if ResourceLoader.exists("res://assets/audio/sfx/warning.wav"):
		sfx_alarm = load("res://assets/audio/sfx/warning.wav")
	if ResourceLoader.exists("res://assets/audio/sfx/success.wav"):
		sfx_success = load("res://assets/audio/sfx/success.wav")

func _setup_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = &"Master"
	add_child(audio_player)

func play_sfx(stream: AudioStream) -> void:
	if stream and audio_player:
		audio_player.stream = stream
		audio_player.play()

func _build_ui() -> void:
	root_control = Control.new()
	root_control.name = "RootControl"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	var dim = ColorRect.new()
	dim.name = "DimBackground"
	dim.color = Color(0.02, 0.04, 0.08, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(dim)

	var center = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(center)

	var panel = PanelContainer.new()
	panel.name = "ChoicePanel"
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.14, 0.95)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.15, 0.75, 1.0, 0.9)
	style.set_corner_radius_all(16)
	style.content_margin_left = 36.0
	style.content_margin_right = 36.0
	style.content_margin_top = 28.0
	style.content_margin_bottom = 28.0
	style.shadow_color = Color(0.0, 0.7, 1.0, 0.25)
	style.shadow_size = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(620, 0)
	panel.add_child(vbox)

	title_label = Label.new()
	title_label.text = "⚡ KENDALI MANUAL DARURAT ⚡"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_bold:
		title_label.add_theme_font_override("font", font_bold)
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	vbox.add_child(title_label)

	var sub_label = Label.new()
	sub_label.text = "TERDETEKSI ANOMALI GRAVITASI PLANET - PILIH TINDAKAN PENYELAMATAN:"
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font_reg:
		sub_label.add_theme_font_override("font", font_reg)
	sub_label.add_theme_font_size_override("font_size", 15)
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.88, 1.0, 0.85))
	vbox.add_child(sub_label)

	vbox.add_child(HSeparator.new())

	# Warning Banner for wrong attempts
	warning_banner = PanelContainer.new()
	var w_style = StyleBoxFlat.new()
	w_style.bg_color = Color(0.5, 0.05, 0.05, 0.85)
	w_style.border_width_left = 2
	w_style.border_width_top = 2
	w_style.border_width_right = 2
	w_style.border_width_bottom = 2
	w_style.border_color = Color(1.0, 0.2, 0.2, 1.0)
	w_style.set_corner_radius_all(8)
	w_style.content_margin_left = 14
	w_style.content_margin_right = 14
	w_style.content_margin_top = 8
	w_style.content_margin_bottom = 8
	warning_banner.add_theme_stylebox_override("panel", w_style)
	warning_label = Label.new()
	warning_label.text = "⚠️ [Notifikasi: TERLALU BERBAHAYA!!!]"
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_bold:
		warning_label.add_theme_font_override("font", font_bold)
	warning_label.add_theme_font_size_override("font_size", 16)
	warning_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.9, 1.0))
	warning_banner.add_child(warning_label)
	warning_banner.hide()
	vbox.add_child(warning_banner)

	# Tombol 1: Keluar dari Kapsul
	btn_exit = Button.new()
	btn_exit.text = "[!] Keluar dari Kapsul"
	btn_exit.custom_minimum_size = Vector2(0, 56)
	btn_exit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_button(btn_exit, Color(0.18, 0.08, 0.12, 0.9), Color(0.9, 0.3, 0.3, 0.7), Color(0.3, 0.1, 0.15, 1.0))
	btn_exit.pressed.connect(_on_btn_exit_pressed)
	vbox.add_child(btn_exit)

	# Tombol 2: Gunakan seluruh sumber daya
	btn_power = Button.new()
	btn_power.text = "[!] Gunakan seluruh sumber daya"
	btn_power.custom_minimum_size = Vector2(0, 56)
	btn_power.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_button(btn_power, Color(0.08, 0.18, 0.28, 0.9), Color(0.2, 0.75, 1.0, 0.8), Color(0.12, 0.28, 0.45, 1.0))
	btn_power.pressed.connect(_on_btn_power_pressed)
	vbox.add_child(btn_power)

func _style_button(btn: Button, bg: Color, border: Color, hover_bg: Color) -> void:
	if font_bold:
		btn.add_theme_font_override("font", font_bold)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	
	var norm = StyleBoxFlat.new()
	norm.bg_color = bg
	norm.border_color = border
	norm.border_width_left = 2
	norm.border_width_top = 2
	norm.border_width_right = 2
	norm.border_width_bottom = 2
	norm.set_corner_radius_all(10)
	norm.content_margin_left = 24.0
	btn.add_theme_stylebox_override("normal", norm)

	var hov = StyleBoxFlat.new()
	hov.bg_color = hover_bg
	hov.border_color = Color(1.0, 1.0, 1.0, 0.95)
	hov.border_width_left = 2
	hov.border_width_top = 2
	hov.border_width_right = 2
	hov.border_width_bottom = 2
	hov.set_corner_radius_all(10)
	hov.content_margin_left = 24.0
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("focus", hov)

func open_menu() -> void:
	is_locked = false
	show()
	if root_control:
		root_control.modulate.a = 0.0
		var tw = create_tween()
		tw.tween_property(root_control, "modulate:a", 1.0, 0.25)
	
	if wrong_choice_count > 0:
		warning_banner.show()
		if wrong_choice_count >= MAX_WRONG_CHOICES:
			warning_label.text = "⚠️ [TOMBOL RUSAK] Tombol keluar korsleting & tidak berfungsi!"
		else:
			warning_label.text = "⚠️ [Notifikasi: TERLALU BERBAHAYA!!!] Percobaan: %d/3" % wrong_choice_count
	else:
		warning_banner.hide()
		
	play_sfx(sfx_alarm)

func close_menu() -> void:
	if root_control:
		var tw = create_tween()
		tw.tween_property(root_control, "modulate:a", 0.0, 0.2)
		await tw.finished
	hide()

func _on_btn_exit_pressed() -> void:
	if is_locked:
		return
	is_locked = true
	wrong_choice_count += 1
	play_sfx(sfx_alarm)
	
	if wrong_choice_count >= MAX_WRONG_CHOICES:
		btn_exit.disabled = true
		btn_exit.text = "[!] Keluar dari Kapsul (RUSAK / KORSLETING)"
		var dis_style = StyleBoxFlat.new()
		dis_style.bg_color = Color(0.12, 0.1, 0.1, 0.8)
		dis_style.border_color = Color(0.4, 0.2, 0.2, 0.6)
		dis_style.set_corner_radius_all(10)
		dis_style.content_margin_left = 24.0
		btn_exit.add_theme_stylebox_override("disabled", dis_style)
		btn_exit.add_theme_color_override("font_disabled_color", Color(0.6, 0.4, 0.4, 0.6))
		
	choice_made.emit(0)
	close_menu()

func reenable_after_dialogue() -> void:
	is_locked = false

func _on_btn_power_pressed() -> void:
	if is_locked:
		return
	is_locked = true
	play_sfx(sfx_success)
	choice_made.emit(1)
	close_menu()
