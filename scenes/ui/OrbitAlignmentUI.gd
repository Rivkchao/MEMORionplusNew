extends CanvasLayer

signal orbit_aligned
signal align_attempt_failed

var font_bold: Font = null
var font_reg: Font = null

var is_active: bool = false
var is_completed: bool = false

# Needle rotation / position (0.0 to 1.0 or angle)
var needle_angle: float = 0.0 # in radians
var rotation_speed: float = 2.2 # sweeps per second

# Green zone parameters: center at -PI/2 (top) with width of ~0.45 rad (~26 degrees each side)
const GREEN_CENTER: float = -PI / 2.0
const GREEN_HALF_WIDTH: float = 0.38 # tolerance window

var hud_panel: Control = null
var action_btn: Button = null
var prompt_label: Label = null
var status_label: Label = null
var warning_sign: TextureRect = null

var sfx_success: AudioStream = null
var sfx_warning: AudioStream = null
var sfx_click: AudioStream = null
var audio_player: AudioStreamPlayer = null

func _ready() -> void:
	layer = 20
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
		
	if ResourceLoader.exists("res://assets/audio/sfx/success.wav"):
		sfx_success = load("res://assets/audio/sfx/success.wav")
	if ResourceLoader.exists("res://assets/audio/sfx/warning.wav"):
		sfx_warning = load("res://assets/audio/sfx/warning.wav")
	if ResourceLoader.exists("res://assets/audio/sfx/click.wav"):
		sfx_click = load("res://assets/audio/sfx/click.wav")

func _setup_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = &"Master"
	add_child(audio_player)

func play_sfx(stream: AudioStream) -> void:
	if stream and audio_player:
		audio_player.stream = stream
		audio_player.play()

func _build_ui() -> void:
	hud_panel = Control.new()
	hud_panel.name = "HUDPanel"
	hud_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_panel)

	# Top instruction banner
	var top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_panel.offset_top = 40.0
	top_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var top_style = StyleBoxFlat.new()
	top_style.bg_color = Color(0.04, 0.08, 0.16, 0.88)
	top_style.border_width_bottom = 3
	top_style.border_color = Color(0.1, 0.8, 1.0, 0.8)
	top_style.set_corner_radius_all(12)
	top_style.content_margin_left = 32
	top_style.content_margin_right = 32
	top_style.content_margin_top = 12
	top_style.content_margin_bottom = 12
	top_panel.add_theme_stylebox_override("panel", top_style)
	hud_panel.add_child(top_panel)

	var top_vbox = VBoxContainer.new()
	top_vbox.add_theme_constant_override("separation", 4)
	top_panel.add_child(top_vbox)

	var title = Label.new()
	title.text = "⚠️ SISTEM PENYELARASAN ORBIT DARURAT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_bold:
		title.add_theme_font_override("font", font_bold)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	top_vbox.add_child(title)

	prompt_label = Label.new()
	prompt_label.text = "Selaraskan jarum dengan GARIS HIJAU, lalu tekan [ ! ] SEKARANG!"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_reg:
		prompt_label.add_theme_font_override("font", font_reg)
	prompt_label.add_theme_font_size_override("font_size", 16)
	prompt_label.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0, 0.9))
	top_vbox.add_child(prompt_label)

	# Center Dial / Orbit Ring Custom Node
	var dial = OrbitDialNode.new()
	dial.name = "OrbitDial"
	dial.set_anchors_preset(Control.PRESET_CENTER)
	dial.orbit_ui = self
	hud_panel.add_child(dial)

	# Bottom Action Button & Status
	var bottom_container = VBoxContainer.new()
	bottom_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom_container.offset_bottom = -70.0
	bottom_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_container.add_theme_constant_override("separation", 12)
	hud_panel.add_child(bottom_container)

	status_label = Label.new()
	status_label.text = "Menunggu momentum orbit..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_bold:
		status_label.add_theme_font_override("font", font_bold)
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.9))
	bottom_container.add_child(status_label)

	action_btn = Button.new()
	action_btn.custom_minimum_size = Vector2(380, 64)
	action_btn.text = "[!] KUNCI ORBIT SEKARANG! (SPASI)"
	if font_bold:
		action_btn.add_theme_font_override("font", font_bold)
	action_btn.add_theme_font_size_override("font_size", 20)
	action_btn.pressed.connect(_try_align)
	bottom_container.add_child(action_btn)
	_update_btn_style(false)

func _update_btn_style(in_green: bool) -> void:
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(14)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	
	if in_green:
		style.bg_color = Color(0.08, 0.45, 0.25, 0.95)
		style.border_color = Color(0.2, 1.0, 0.45, 1.0)
		style.shadow_color = Color(0.0, 1.0, 0.4, 0.6)
		style.shadow_size = 22
		action_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		action_btn.text = "⚡ [!] SEKARANG! KUNCI ORBIT! ⚡"
	else:
		style.bg_color = Color(0.1, 0.15, 0.22, 0.75)
		style.border_color = Color(0.3, 0.5, 0.7, 0.6)
		style.shadow_color = Color(0, 0, 0, 0.3)
		style.shadow_size = 8
		action_btn.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95, 0.75))
		action_btn.text = "MENUNGGU GARIS HIJAU... [SPASI]"

	action_btn.add_theme_stylebox_override("normal", style)
	action_btn.add_theme_stylebox_override("hover", style)
	action_btn.add_theme_stylebox_override("focus", style)

func start_minigame() -> void:
	is_active = true
	is_completed = false
	needle_angle = 0.0
	show()
	if hud_panel:
		hud_panel.modulate.a = 0.0
		var tw = create_tween()
		tw.tween_property(hud_panel, "modulate:a", 1.0, 0.3)

func _process(delta: float) -> void:
	if not is_active or is_completed:
		return

	# Rotate the needle continuously
	needle_angle += rotation_speed * delta
	if needle_angle > PI:
		needle_angle -= TAU
	elif needle_angle < -PI:
		needle_angle += TAU

	var in_green = is_needle_in_green_zone()
	_update_btn_style(in_green)
	
	if in_green:
		status_label.text = "✦ PAS DI GARIS HIJAU! TEKAN SEKARANG! ✦"
		status_label.modulate = Color(0.2, 1.0, 0.5, 1.0)
	else:
		status_label.text = "Biarin masuk ke jalurnya dulu..."
		status_label.modulate = Color(0.6, 0.75, 0.9, 0.85)

	# Trigger redraw of dial
	var dial = hud_panel.get_node_or_null("OrbitDial")
	if dial:
		dial.queue_redraw()

func is_needle_in_green_zone() -> bool:
	var diff = abs(wrapf(needle_angle - GREEN_CENTER, -PI, PI))
	return diff <= GREEN_HALF_WIDTH

func _unhandled_input(event: InputEvent) -> void:
	if not is_active or is_completed:
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		_try_align()

func _try_align() -> void:
	if not is_active or is_completed:
		return

	if is_needle_in_green_zone():
		# Success!
		is_completed = true
		is_active = false
		play_sfx(sfx_success)
		status_label.text = "🎉 BERHASIL! KAPSUL STABIL DI JALUR ORBIT!"
		status_label.modulate = Color(0.2, 1.0, 0.4, 1.0)
		
		# Flash success
		var dial = hud_panel.get_node_or_null("OrbitDial")
		if dial:
			dial.queue_redraw()
			
		orbit_aligned.emit()
		
		var tw = create_tween()
		tw.tween_interval(1.2)
		if hud_panel:
			tw.tween_property(hud_panel, "modulate:a", 0.0, 0.4)
		await tw.finished
		hide()
	else:
		# Misfire / wrong timing
		play_sfx(sfx_warning)
		status_label.text = "❌ Meleset! Tunggu jarum tepat di garis hijau!"
		status_label.modulate = Color(1.0, 0.3, 0.3, 1.0)
		
		# Shake bottom container
		var bc = hud_panel.get_node_or_null("VBoxContainer")
		if bc:
			var orig = bc.position
			var tw = create_tween()
			tw.tween_property(bc, "position", orig + Vector2(-15, 0), 0.05)
			tw.tween_property(bc, "position", orig + Vector2(15, 0), 0.05)
			tw.tween_property(bc, "position", orig, 0.05)
		
		align_attempt_failed.emit()

# Custom Draw Node for the Sci-Fi Orbit Dial
class OrbitDialNode extends Control:
	var orbit_ui: CanvasLayer = null

	func _draw() -> void:
		if orbit_ui == null:
			return
			
		var center = Vector2.ZERO
		var radius = 130.0
		var thickness = 10.0
		
		# 1. Dark background ring
		draw_arc(center, radius, 0, TAU, 64, Color(0.05, 0.1, 0.2, 0.7), thickness)
		
		# 2. Glowing Green Target Arc (Garis Hijau)
		var g_start = orbit_ui.GREEN_CENTER - orbit_ui.GREEN_HALF_WIDTH
		var g_end = orbit_ui.GREEN_CENTER + orbit_ui.GREEN_HALF_WIDTH
		var in_green = orbit_ui.is_needle_in_green_zone()
		
		var green_color = Color(0.2, 1.0, 0.45, 1.0) if in_green else Color(0.1, 0.8, 0.35, 0.75)
		var green_thickness = thickness + (6.0 if in_green else 2.0)
		draw_arc(center, radius, g_start, g_end, 32, green_color, green_thickness)
		
		# Target marker brackets
		var p1 = center + Vector2(cos(g_start), sin(g_start)) * (radius + 16.0)
		var p2 = center + Vector2(cos(g_end), sin(g_end)) * (radius + 16.0)
		draw_line(center + Vector2(cos(g_start), sin(g_start)) * (radius - 12.0), p1, Color(0.4, 1.0, 0.6, 0.9), 2.5)
		draw_line(center + Vector2(cos(g_end), sin(g_end)) * (radius - 12.0), p2, Color(0.4, 1.0, 0.6, 0.9), 2.5)
		
		# Green zone text / icon
		var label_pos = center + Vector2(0, -radius - 32.0)
		var f = orbit_ui.font_bold
		if f:
			var txt = "▲ JALUR ORBIT (GARIS HIJAU) ▲"
			var sz = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			draw_string(f, label_pos - Vector2(sz.x / 2.0, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, green_color)
		
		# 3. Rotating Needle / Crosshair (Stabilizer Pointer)
		var n_angle = orbit_ui.needle_angle
		var n_dir = Vector2(cos(n_angle), sin(n_angle))
		var needle_color = Color(1.0, 1.0, 0.2, 1.0) if in_green else Color(1.0, 0.4, 0.4, 0.9)
		
		# Draw pointer line
		draw_line(center, center + n_dir * (radius + 8.0), needle_color, 3.5)
		# Draw pointer arrowhead
		var tip = center + n_dir * (radius + 18.0)
		var side1 = center + Vector2(cos(n_angle + 0.15), sin(n_angle + 0.15)) * (radius + 4.0)
		var side2 = center + Vector2(cos(n_angle - 0.15), sin(n_angle - 0.15)) * (radius + 4.0)
		var pts = PackedVector2Array([tip, side1, side2])
		draw_colored_polygon(pts, needle_color)
		
		# Center circle
		draw_circle(center, 12.0, Color(0.08, 0.18, 0.32, 0.95))
		draw_circle(center, 6.0, needle_color)
