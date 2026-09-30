# scenes/ui/settings_menu.gd
extends Control
class_name SettingsMenu

signal closed

# Display References
@onready var brightness_slider: HSlider = %BrightnessSlider
@onready var brightness_label: Label = %BrightnessValue
@onready var window_mode_option: OptionButton = %WindowModeOption
@onready var resolution_option: OptionButton = %ResolutionOption

# Audio References
@onready var vol_general_slider: HSlider = %VolGeneralSlider
@onready var vol_general_label: Label = %VolGeneralValue
@onready var vol_bgm_slider: HSlider = %VolBgmSlider
@onready var vol_bgm_label: Label = %VolBgmValue
@onready var vol_sfx_slider: HSlider = %VolSfxSlider
@onready var vol_sfx_label: Label = %VolSfxValue

# Controls References
@onready var mobile_mode_option: OptionButton = %MobileModeOption

# Mobile Layout References
@onready var mobile_element_option: OptionButton = %MobileElementOption
@onready var mobile_pos_x_slider: HSlider = %MobilePosXSlider
@onready var mobile_pos_x_label: Label = %MobilePosXValue
@onready var mobile_pos_y_slider: HSlider = %MobilePosYSlider
@onready var mobile_pos_y_label: Label = %MobilePosYValue
@onready var mobile_size_slider: HSlider = %MobileSizeSlider
@onready var mobile_size_label: Label = %MobileSizeValue
@onready var mobile_opacity_slider: HSlider = %MobileOpacitySlider
@onready var mobile_opacity_label: Label = %MobileOpacityValue
@onready var reset_element_btn: Button = %ResetElementBtn
@onready var reset_all_layout_btn: Button = %ResetAllLayoutBtn

# Action Buttons
@onready var save_btn: Button = %SaveBtn
@onready var reset_btn: Button = %ResetBtn
@onready var close_btn: Button = %CloseBtn
@onready var panel_container: PanelContainer = %PanelContainer

# Save Game (progres) References
@onready var save_section: Control = %SaveSection
@onready var save_game_btn: Button = %SaveGameBtn
@onready var save_exit_btn: Button = %SaveExitBtn
@onready var save_feedback: Label = %SaveFeedback

const MOBILE_ELEMENTS: Array[Dictionary] = [
	{"id": "joystick", "name": "🎮 Joystick (Analog)"},
	{"id": "interact", "name": "✋ Tombol Aksi (Ambil / Interaksi)"},
	{"id": "jump", "name": "🦘 Tombol Lompat"},
	{"id": "sprint", "name": "⚡ Tombol Lari / Jalan"},
	{"id": "drop", "name": "🔻 Tombol Lepas Item"}
]

var _current_mobile_element_id: String = "joystick"
var _initial_mobile_layout: Dictionary = {}
var _spawned_preview_controls: CanvasLayer = null

var _was_paused_before_open: bool = false
var _initial_brightness: float = 1.0
var _initial_volume_general: float = 0.8
var _initial_volume_bgm: float = 0.8
var _initial_volume_sfx: float = 0.8
var _initial_window_mode: int = 0
var _initial_resolution: int = 0
var _initial_mobile_mode: int = 0

func _ready() -> void:
	add_to_group("settings_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	_populate_options()
	_connect_signals()
	_sync_from_manager()

func _populate_options() -> void:
	# Populate Mode Layar
	if window_mode_option:
		window_mode_option.clear()
		for m in SettingsManager.WINDOW_MODES:
			window_mode_option.add_item(m)
	
	# Populate Resolusi
	if resolution_option:
		resolution_option.clear()
		for res in SettingsManager.RESOLUTIONS:
			resolution_option.add_item(res["name"])
	
	# Populate Kontrol Mobile
	if mobile_mode_option:
		mobile_mode_option.clear()
		mobile_mode_option.add_item("Otomatis (Layar Sentuh)")
		mobile_mode_option.add_item("Selalu Aktif (Paksa Tampil)")
		mobile_mode_option.add_item("Nonaktif (Keyboard/Mouse)")
	
	# Populate Pilihan Elemen Kontrol Mobile
	if mobile_element_option:
		mobile_element_option.clear()
		for elem in MOBILE_ELEMENTS:
			mobile_element_option.add_item(elem["name"])

func _connect_signals() -> void:
	brightness_slider.value_changed.connect(_on_brightness_changed)
	
	if window_mode_option:
		window_mode_option.item_selected.connect(_on_window_mode_selected)
	
	if resolution_option:
		resolution_option.item_selected.connect(_on_resolution_selected)
	
	vol_general_slider.value_changed.connect(_on_vol_general_changed)
	vol_bgm_slider.value_changed.connect(_on_vol_bgm_changed)
	vol_sfx_slider.value_changed.connect(_on_vol_sfx_changed)
	
	if mobile_mode_option:
		mobile_mode_option.item_selected.connect(_on_mobile_mode_selected)
	
	if mobile_element_option:
		mobile_element_option.item_selected.connect(_on_mobile_element_selected)
	
	if mobile_pos_x_slider:
		mobile_pos_x_slider.value_changed.connect(_on_mobile_pos_x_changed)
	if mobile_pos_y_slider:
		mobile_pos_y_slider.value_changed.connect(_on_mobile_pos_y_changed)
	if mobile_size_slider:
		mobile_size_slider.value_changed.connect(_on_mobile_size_changed)
	if mobile_opacity_slider:
		mobile_opacity_slider.value_changed.connect(_on_mobile_opacity_changed)
	
	if reset_element_btn:
		reset_element_btn.pressed.connect(_on_reset_element_pressed)
	if reset_all_layout_btn:
		reset_all_layout_btn.pressed.connect(_on_reset_all_layout_pressed)
	
	save_btn.pressed.connect(_on_save_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)
	close_btn.pressed.connect(_on_close_pressed)

	if save_game_btn:
		save_game_btn.pressed.connect(_on_save_game_pressed)
	if save_exit_btn:
		save_exit_btn.pressed.connect(_on_save_exit_pressed)

	for btn in [save_btn, reset_btn, close_btn, reset_element_btn, reset_all_layout_btn, save_game_btn, save_exit_btn]:
		if btn:
			btn.pivot_offset = btn.size / 2.0
			btn.button_down.connect(func():
				var tween = create_tween()
				tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.08).set_ease(Tween.EASE_OUT)
			)
			btn.button_up.connect(func():
				var tween = create_tween()
				tween.tween_property(btn, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			)

	var dim = get_node_or_null("DimOverlay")
	if dim:
		dim.gui_input.connect(func(event):
			if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
				_on_close_pressed()
		)
	
	if SettingsManager:
		SettingsManager.window_mode_changed.connect(_on_settings_window_mode_changed)
		SettingsManager.resolution_changed.connect(_on_settings_resolution_changed)

func _sync_from_manager() -> void:
	if SettingsManager == null:
		return
	
	# Brightness
	brightness_slider.value = SettingsManager.brightness
	_update_brightness_label(SettingsManager.brightness)
	
	# Window Mode & Resolution
	if window_mode_option:
		window_mode_option.selected = clamp(SettingsManager.window_mode_index, 0, SettingsManager.WINDOW_MODES.size() - 1)
	if resolution_option:
		resolution_option.selected = clamp(SettingsManager.resolution_index, 0, SettingsManager.RESOLUTIONS.size() - 1)
	
	# Audio
	vol_general_slider.value = SettingsManager.volume_general
	_update_vol_label(vol_general_label, SettingsManager.volume_general)
	
	vol_bgm_slider.value = SettingsManager.volume_bgm
	_update_vol_label(vol_bgm_label, SettingsManager.volume_bgm)
	
	vol_sfx_slider.value = SettingsManager.volume_sfx
	_update_vol_label(vol_sfx_label, SettingsManager.volume_sfx)
	
	# Mobile Controls Mode
	if mobile_mode_option:
		mobile_mode_option.selected = clamp(SettingsManager.mobile_controls_mode, 0, 2)
	
	# Mobile Layout Sliders
	_sync_mobile_sliders_for_current_element()

# ----------------------------------------------------
# Event Handlers: Live Tweaks
# ----------------------------------------------------
func _on_brightness_changed(val: float) -> void:
	SettingsManager.set_brightness(val)
	_update_brightness_label(val)

func _update_brightness_label(val: float) -> void:
	brightness_label.text = "%d%%" % int(val * 100.0)

func _on_window_mode_selected(index: int) -> void:
	SettingsManager.set_window_mode(index)

func _on_resolution_selected(index: int) -> void:
	SettingsManager.set_resolution(index)

func _on_settings_window_mode_changed(index: int) -> void:
	if window_mode_option:
		window_mode_option.selected = index

func _on_settings_resolution_changed(index: int) -> void:
	if resolution_option:
		resolution_option.selected = index

func _on_vol_general_changed(val: float) -> void:
	SettingsManager.set_volume_general(val)
	_update_vol_label(vol_general_label, val)

func _on_vol_bgm_changed(val: float) -> void:
	SettingsManager.set_volume_bgm(val)
	_update_vol_label(vol_bgm_label, val)

func _on_vol_sfx_changed(val: float) -> void:
	SettingsManager.set_volume_sfx(val)
	_update_vol_label(vol_sfx_label, val)

func _update_vol_label(lbl: Label, val: float) -> void:
	lbl.text = "%d%%" % int(val * 100.0)

func _on_mobile_mode_selected(index: int) -> void:
	SettingsManager.set_mobile_controls_mode(index)

# ----------------------------------------------------
# Event Handlers: Mobile Controls Layout Live Editing
# ----------------------------------------------------
func _sync_mobile_sliders_for_current_element() -> void:
	if SettingsManager == null:
		return
	
	var px = SettingsManager.get_mobile_control_property(_current_mobile_element_id, "pos_x", 0.0)
	var py = SettingsManager.get_mobile_control_property(_current_mobile_element_id, "pos_y", 0.0)
	var s = SettingsManager.get_mobile_control_property(_current_mobile_element_id, "scale", 1.0)
	var op = SettingsManager.get_mobile_control_property(_current_mobile_element_id, "opacity", 0.95)
	
	if mobile_pos_x_slider:
		mobile_pos_x_slider.set_value_no_signal(px)
		_update_pos_label(mobile_pos_x_label, px)
	if mobile_pos_y_slider:
		mobile_pos_y_slider.set_value_no_signal(py)
		_update_pos_label(mobile_pos_y_label, py)
	if mobile_size_slider:
		mobile_size_slider.set_value_no_signal(s)
		_update_scale_label(mobile_size_label, s)
	if mobile_opacity_slider:
		mobile_opacity_slider.set_value_no_signal(op)
		_update_opacity_label(mobile_opacity_label, op)

func _on_mobile_element_selected(index: int) -> void:
	if index >= 0 and index < MOBILE_ELEMENTS.size():
		_current_mobile_element_id = MOBILE_ELEMENTS[index]["id"]
		_sync_mobile_sliders_for_current_element()
		var mc = _find_mobile_controls()
		if mc and mc.has_method("pulse_element"):
			mc.pulse_element(_current_mobile_element_id)

func _on_mobile_pos_x_changed(val: float) -> void:
	SettingsManager.set_mobile_control_property(_current_mobile_element_id, "pos_x", val)
	_update_pos_label(mobile_pos_x_label, val)

func _on_mobile_pos_y_changed(val: float) -> void:
	SettingsManager.set_mobile_control_property(_current_mobile_element_id, "pos_y", val)
	_update_pos_label(mobile_pos_y_label, val)

func _on_mobile_size_changed(val: float) -> void:
	SettingsManager.set_mobile_control_property(_current_mobile_element_id, "scale", val)
	_update_scale_label(mobile_size_label, val)

func _on_mobile_opacity_changed(val: float) -> void:
	SettingsManager.set_mobile_control_property(_current_mobile_element_id, "opacity", val)
	_update_opacity_label(mobile_opacity_label, val)

func _update_pos_label(lbl: Label, val: float) -> void:
	if lbl == null:
		return
	var ival = int(round(val))
	if ival > 0:
		lbl.text = "+%d px" % ival
	elif ival < 0:
		lbl.text = "%d px" % ival
	else:
		lbl.text = "0 px"

func _update_scale_label(lbl: Label, val: float) -> void:
	if lbl:
		lbl.text = "%d%%" % int(round(val * 100.0))

func _update_opacity_label(lbl: Label, val: float) -> void:
	if lbl:
		lbl.text = "%d%%" % int(round(val * 100.0))

func _on_reset_element_pressed() -> void:
	SettingsManager.reset_mobile_control_element(_current_mobile_element_id)
	_sync_mobile_sliders_for_current_element()
	var mc = _find_mobile_controls()
	if mc and mc.has_method("pulse_element"):
		mc.pulse_element(_current_mobile_element_id)

func _on_reset_all_layout_pressed() -> void:
	SettingsManager.reset_mobile_layout()
	_sync_mobile_sliders_for_current_element()
	var mc = _find_mobile_controls()
	if mc and mc.has_method("pulse_element"):
		mc.pulse_element(_current_mobile_element_id)

func _find_mobile_controls() -> Node:
	if _spawned_preview_controls != null and is_instance_valid(_spawned_preview_controls):
		return _spawned_preview_controls
	return get_tree().root.find_child("MobileControls", true, false)

func _find_or_create_mobile_controls_preview() -> Node:
	var existing = _find_mobile_controls()
	if existing != null:
		return existing
	
	var mc_res = load("res://scenes/ui/MobileControls.tscn")
	if mc_res:
		_spawned_preview_controls = mc_res.instantiate()
		get_tree().root.add_child(_spawned_preview_controls)
		return _spawned_preview_controls
	return null

func _on_save_pressed() -> void:
	SettingsManager.save_settings()
	close()

# ----------------------------------------------------
# Simpan Permainan (manual save)
# ----------------------------------------------------
func _refresh_save_section() -> void:
	var in_game: bool = SaveManager != null and SaveManager.is_in_game_level()
	if save_section:
		save_section.visible = in_game
	if save_feedback == null:
		return
	if SaveManager != null and SaveManager.is_logged_in():
		save_feedback.text = "Akun: %s" % SaveManager.current_username
	else:
		save_feedback.text = "Belum login - progres tidak bisa disimpan."

func _set_save_feedback(text: String) -> void:
	if save_feedback:
		save_feedback.text = text

func _on_save_game_pressed() -> void:
	if AudioManager:
		AudioManager.play_ui_confirm()
	if SettingsManager:
		SettingsManager.save_settings()
	if SaveManager == null or not SaveManager.is_logged_in():
		_set_save_feedback("Belum login.")
		return
	if not SaveManager.is_in_game_level():
		_set_save_feedback("Tidak ada permainan aktif.")
		return
	_set_save_feedback("Menyimpan...")
	if await SaveManager.save_slot(SaveManager.SLOT_MANUAL):
		_set_save_feedback("Permainan tersimpan.")
	else:
		_set_save_feedback("Gagal menyimpan (cek koneksi/server).")

func _on_save_exit_pressed() -> void:
	if AudioManager:
		AudioManager.play_ui_confirm()
	if SettingsManager:
		SettingsManager.save_settings()
	if SaveManager != null and SaveManager.is_logged_in() and SaveManager.is_in_game_level():
		_set_save_feedback("Menyimpan...")
		await SaveManager.save_slot(SaveManager.SLOT_MANUAL, 4.0)
	_set_save_feedback("Menyimpan & keluar...")
	get_tree().paused = false
	await get_tree().create_timer(0.35).timeout
	if has_node("/root/LoadingScreen"):
		LoadingScreen.load_scene("res://Menu/main_menu.tscn")
	else:
		get_tree().change_scene_to_file("res://Menu/main_menu.tscn")

func _on_reset_pressed() -> void:
	SettingsManager.reset_to_defaults()
	_sync_from_manager()

func _on_close_pressed() -> void:
	if SettingsManager:
		# Kembalikan pengaturan ke snapshot awal sebelum modal dibuka
		var display_changed: bool = (SettingsManager.window_mode_index != _initial_window_mode) or (SettingsManager.resolution_index != _initial_resolution)
		
		SettingsManager.brightness = _initial_brightness
		SettingsManager.volume_general = _initial_volume_general
		SettingsManager.volume_bgm = _initial_volume_bgm
		SettingsManager.volume_sfx = _initial_volume_sfx
		SettingsManager.window_mode_index = _initial_window_mode
		SettingsManager.resolution_index = _initial_resolution
		SettingsManager.mobile_controls_mode = _initial_mobile_mode
		SettingsManager.mobile_layout = _initial_mobile_layout.duplicate(true)
		
		SettingsManager._apply_brightness()
		SettingsManager._apply_bus_volume(SettingsManager._bus_master, _initial_volume_general)
		SettingsManager._apply_bus_volume(SettingsManager._bus_bgm, _initial_volume_bgm)
		SettingsManager._apply_bus_volume(SettingsManager._bus_sfx, _initial_volume_sfx)
		SettingsManager.mobile_controls_toggled.emit(SettingsManager.is_mobile_controls_active())
		SettingsManager.mobile_layout_updated.emit()
		
		# Hanya terapkan ulang display jika user sempat mengubahnya saat di menu
		if display_changed:
			SettingsManager._apply_window_mode()
	close()

# ----------------------------------------------------
# Modal Open & Close Animations
# ----------------------------------------------------
func open() -> void:
	_was_paused_before_open = get_tree().paused
	
	if SettingsManager:
		_initial_brightness = SettingsManager.brightness
		_initial_volume_general = SettingsManager.volume_general
		_initial_volume_bgm = SettingsManager.volume_bgm
		_initial_volume_sfx = SettingsManager.volume_sfx
		_initial_window_mode = SettingsManager.window_mode_index
		_initial_resolution = SettingsManager.resolution_index
		_initial_mobile_mode = SettingsManager.mobile_controls_mode
		_initial_mobile_layout = SettingsManager.mobile_layout.duplicate(true)
	
	var current_scene = get_tree().current_scene
	if current_scene != null and current_scene.name != "MainMenu":
		get_tree().paused = true
	
	_sync_from_manager()
	_refresh_save_section()
	
	# Aktifkan mode preview pada MobileControls untuk live editing
	var mobile_node = _find_or_create_mobile_controls_preview()
	if mobile_node and mobile_node.has_method("set_preview_mode"):
		mobile_node.set_preview_mode(true)
		if mobile_node.has_method("pulse_element"):
			mobile_node.pulse_element(_current_mobile_element_id)
	
	visible = true
	modulate.a = 0.0
	panel_container.scale = Vector2(0.9, 0.9)
	panel_container.pivot_offset = panel_container.size / 2.0
	
	var tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel_container, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close() -> void:
	var mobile_node = _find_mobile_controls()
	if mobile_node and mobile_node.has_method("set_preview_mode"):
		mobile_node.set_preview_mode(false)
	
	if _spawned_preview_controls != null and is_instance_valid(_spawned_preview_controls):
		_spawned_preview_controls.queue_free()
		_spawned_preview_controls = null
	
	var tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(panel_container, "scale", Vector2(0.9, 0.9), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	
	visible = false
	if not _was_paused_before_open:
		get_tree().paused = false
	
	closed.emit()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close_pressed()
