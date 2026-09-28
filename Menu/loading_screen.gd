extends CanvasLayer

@onready var fade_rect: ColorRect = $FadeRect
@onready var panel: Control = $Panel
@onready var bg_menu: TextureRect = $Panel/BackgroundMenu
@onready var planet: Sprite2D = $Panel/Planet
@onready var frame_menu: TextureRect = $Panel/FrameMenu
@onready var logo_rect: TextureRect = $Panel/Logo
@onready var logo2_rect: TextureRect = $Panel/Logo2
@onready var instagram_btn: Button = $Panel/InstagramBtn
@onready var greeting_label: Label = $Panel/Label
@onready var progress_bar: ProgressBar = $Panel/ProgressBar
@onready var loading_label: Label = $Panel/LoadingLabel
@onready var animated_sprite: AnimatedSprite2D = $Panel/AnimatedSprite2D
@onready var sprite_bar: Sprite2D = $Panel/SpriteBar

const INSTAGRAM_URL: String = "https://www.instagram.com/memorion.plus"

var target_scene: String = ""
var is_loading_finished: bool = false
var min_display_time: float = 1.0
var show_loading_panel: bool = true
var _preloaded_scene: PackedScene = null

func _ready() -> void:
	_start_logo_flip_animation()
	layer = 100
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.hide()
	
	if get_viewport():
		get_viewport().size_changed.connect(_apply_responsive_layout)
	if panel:
		panel.resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	
	if is_instance_valid(instagram_btn):
		instagram_btn.pressed.connect(_on_instagram)

func _apply_responsive_layout() -> void:
	if not is_inside_tree() or panel == null:
		return
	var vp_size = panel.get_viewport_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
	
	var scale_y: float = vp_size.y / 1080.0
	var scale_factor: float = clampf(scale_y, 0.5, 1.5)
	
	# 1. Responsif FrameMenu (Texture portrait diputar -90 deg agar menutup layar penuh di segala rasio)
	if frame_menu:
		frame_menu.rotation = -PI / 2.0
		frame_menu.position = Vector2(0, vp_size.y)
		frame_menu.size = Vector2(vp_size.y, vp_size.x)
	
	# 2. Responsif Planet & SpriteBar
	if planet:
		planet.scale = Vector2.ONE * scale_factor
		planet.position = Vector2(240.0 * scale_factor, vp_size.y * 0.44)
	if sprite_bar:
		sprite_bar.scale = Vector2(0.47, 0.47) * scale_factor
		sprite_bar.position = Vector2(vp_size.x - 171.0 * scale_factor, vp_size.y - 123.0 * scale_factor)
	
	# 3. Responsif Greeting Label ("Halo, Penjelajah Bintang!")
	if greeting_label:
		greeting_label.add_theme_font_size_override("font_size", clampi(int(24.0 * scale_factor), 14, 28))
		greeting_label.position.x = 127.0 * scale_factor
		greeting_label.position.y = vp_size.y - (89.0 * scale_factor)
	
	# 4. Responsif Logo & Logo2
	if logo_rect:
		logo_rect.scale = Vector2.ONE * scale_factor
		logo_rect.position = Vector2(75.0 * scale_factor, 42.0 * scale_factor)
	if logo2_rect:
		logo2_rect.scale = Vector2.ONE * scale_factor
		var l2_w = 800.0 * scale_factor
		logo2_rect.position = Vector2(vp_size.x - l2_w - (115.0 * scale_factor), 83.0 * scale_factor)
	
	# 5. Responsif ProgressBar, LoadingLabel, AnimatedSprite
	if progress_bar:
		var bar_width = clampf(vp_size.x * 0.45, 320.0, 800.0)
		progress_bar.custom_minimum_size.x = bar_width
		progress_bar.size.x = bar_width
		progress_bar.position.x = (vp_size.x - bar_width) * 0.5
		progress_bar.position.y = vp_size.y - (107.0 * scale_factor)
	if loading_label and progress_bar:
		loading_label.add_theme_font_size_override("font_size", clampi(int(36.0 * scale_factor), 20, 42))
		loading_label.position = Vector2(progress_bar.position.x, progress_bar.position.y - 65.0 * scale_factor)
	if animated_sprite and progress_bar:
		animated_sprite.scale = Vector2(0.4, 0.4) * scale_factor
		animated_sprite.position = Vector2(progress_bar.position.x + progress_bar.size.x - 30.0 * scale_factor, progress_bar.position.y + 30.0 * scale_factor)
	
	# 6. Responsif Instagram Button
	if instagram_btn:
		instagram_btn.add_theme_font_size_override("font_size", clampi(int(24.0 * scale_factor), 14, 26))
		instagram_btn.position = Vector2(vp_size.x - (474.0 * scale_factor), vp_size.y - (80.0 * scale_factor))

func _debug_log(msg: String) -> void:
	print("[LoadingScreen] ", msg)
	var f = FileAccess.open("user://loading_debug.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("user://loading_debug.log", FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line("[%s] %s" % [Time.get_time_string_from_system(), msg])
		f.close()

func load_scene(scene_path: String, min_display: float = 1.0, show_panel: bool = true) -> void:
	_debug_log("load_scene called for: " + scene_path + " (current target was: " + target_scene + ")")
	target_scene = scene_path
	min_display_time = maxf(0.0, min_display)
	show_loading_panel = show_panel
	is_loading_finished = false
	layer = 100
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var mobile = get_tree().root.find_child("MobileControls", true, false)
	if mobile:
		mobile.visible = false
	_fade_out()

func _fade_out() -> void:
	var tween = create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, 0.5)
	tween.tween_callback(_start_loading)

func _start_logo_flip_animation() -> void:
	if not is_instance_valid(logo_rect):
		return
	logo_rect.pivot_offset = logo_rect.size / 2.0
	
	var flip_tween = create_tween().set_loops()
	flip_tween.tween_interval(3.0)
	flip_tween.tween_property(logo_rect, "scale:x", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	flip_tween.tween_property(logo_rect, "scale:x", -1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	flip_tween.tween_property(logo_rect, "scale:x", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	flip_tween.tween_property(logo_rect, "scale:x", 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _start_loading() -> void:
	if show_loading_panel:
		panel.show()
	progress_bar.value = 0
	loading_label.text = "Memuat..."
	animated_sprite.play("default")
	_preloaded_scene = null

	# Web build bersifat single-threaded: load_threaded_request tidak berjalan normal
	# (status bisa langsung INVALID_RESOURCE), jadi muat sinkron saja.
	if OS.has_feature("web") or not OS.has_feature("threads"):
		_preloaded_scene = ResourceLoader.load(target_scene) as PackedScene
		_debug_log("sync load for '" + target_scene + "' result: " + str(_preloaded_scene))
		is_loading_finished = true
		if _preloaded_scene != null:
			_on_load_success()
		else:
			_debug_log("GAGAL sync load: " + target_scene)
			loading_label.text = "Gagal memuat!"
			target_scene = ""
			panel.hide()
			_fade_in()
		return

	var req_err = ResourceLoader.load_threaded_request(target_scene)
	_debug_log("load_threaded_request for '" + target_scene + "' returned code: " + str(req_err))
	if req_err != OK:
		is_loading_finished = true
		loading_label.text = "Gagal memuat!"
		target_scene = ""
		panel.hide()
		_fade_in()

func _process(_delta: float) -> void:
	if target_scene == "" or is_loading_finished:
		return
	
	var progress = []
	var status = ResourceLoader.load_threaded_get_status(target_scene, progress)
	
	if progress.size() > 0:
		var p: float = progress[0]
		progress_bar.value = p * 100
		
		if p < 0.3:
			loading_label.text = "Memuat..."
		elif p < 0.7:
			loading_label.text = "Menyiapkan planet..."
		elif p < 1.0:
			loading_label.text = "Hampir selesai..."
	
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			is_loading_finished = true
			_debug_log("THREAD_LOAD_LOADED for: " + target_scene)
			_on_load_success()
		
		ResourceLoader.THREAD_LOAD_FAILED:
			is_loading_finished = true
			_debug_log("THREAD_LOAD_FAILED for: " + target_scene)
			loading_label.text = "Gagal memuat!"
			animated_sprite.stop()
			await get_tree().create_timer(1.0).timeout
			target_scene = ""
			panel.hide()
			_fade_in()
		
		_:
			# THREAD_LOAD_IN_PROGRESS / INVALID_RESOURCE: masih menunggu, cek lagi frame berikutnya
			pass

func _on_load_success() -> void:
	progress_bar.value = 100
	loading_label.text = "Siap dimainkan!"
	animated_sprite.stop()
	
	await get_tree().create_timer(min_display_time).timeout
	
	var scene: PackedScene = _preloaded_scene
	if scene == null:
		scene = ResourceLoader.load_threaded_get(target_scene) as PackedScene
	_debug_log("scene siap: " + str(scene))
	
	if scene == null:
		_debug_log("ERROR: Loaded scene is NULL!")
		target_scene = ""
		panel.hide()
		_fade_in()
		return
	
	var err = get_tree().change_scene_to_packed(scene)
	_debug_log("change_scene_to_packed returned code: " + str(err) + " (OK is 0)")
	target_scene = ""
	
	await get_tree().process_frame
	panel.hide()
	_fade_in()

func _fade_in() -> void:
	var tween = create_tween()
	tween.tween_property(fade_rect, "color:a", 0.0, 0.5)
	tween.tween_callback(func():
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if SettingsManager and SettingsManager.has_method("is_mobile_controls_active"):
			var mobile = get_tree().root.find_child("MobileControls", true, false)
			if mobile:
				var hud = get_tree().root.find_child("HUD", true, false)
				if hud and hud.has_method("is_gameplay_ui_visible") and not hud.is_gameplay_ui_visible():
					mobile.visible = false
				elif hud and "_gameplay_ui_visible" in hud and not hud._gameplay_ui_visible:
					mobile.visible = false
				else:
					mobile.visible = SettingsManager.is_mobile_controls_active()
	)


func _on_instagram() -> void:
	OS.shell_open(INSTAGRAM_URL)
