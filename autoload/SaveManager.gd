extends Node

## SaveManager — client REST API Memorion+ (Laravel).
## Akun + auto-save (Continue) + manual save (Load Game) sekarang lewat HTTP.
## Base URL bisa dioverride lewat user://api_config.cfg  ->  [api] base_url=...

const DEFAULT_API_BASE_URL: String = "http://memorion-api.auto/api"
const SESSION_PATH: String = "user://session.json"

const SLOT_AUTO: String = "auto"
const SLOT_MANUAL: String = "manual"

var api_base_url: String = DEFAULT_API_BASE_URL

var current_uid: String = ""
var current_username: String = ""
var current_token: String = ""

var initial_auth_tab: int = 0

## Slot yang ingin dimuat setelah login ("" = tidak ada / game baru).
var pending_load_slot: String = ""
## Scene tujuan setelah sebuah slot dimuat (diisi oleh apply_state()).
var pending_scene: String = ""

@export var auto_save_interval: float = 15.0
var _auto_save_timer: float = 0.0
var _auto_save_busy: bool = false

signal login_success
signal login_failed(reason: String)
signal register_success
signal register_failed(reason: String)
signal save_success(slot: String)
signal load_success(data: Dictionary)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Supaya kita bisa auto-save progress saat window ditutup (tombol X).
	if get_tree():
		get_tree().set_auto_accept_quit(false)
	_load_api_config()
	load_session()

func _process(delta: float) -> void:
	# Auto-save berkala selama pemain aktif di dalam level.
	if _auto_save_busy or not is_logged_in() or not is_in_game_level():
		_auto_save_timer = 0.0
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.visible:
		return
	_auto_save_timer += delta
	if _auto_save_timer >= auto_save_interval:
		_auto_save_timer = 0.0
		_auto_save_busy = true
		await save_slot(SLOT_AUTO, 8.0)
		_auto_save_busy = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_exit_to_desktop()

func _exit_to_desktop() -> void:
	await handle_exit_auto_save()
	if get_tree():
		get_tree().quit()

# ─── KONFIGURASI ──────────────────────────────────────────────────
func _load_api_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://api_config.cfg") == OK:
		api_base_url = str(cfg.get_value("api", "base_url", api_base_url))
	api_base_url = api_base_url.rstrip("/")

func set_api_base_url(url: String) -> void:
	api_base_url = url.rstrip("/")

func is_logged_in() -> bool:
	return current_token != "" and current_username != ""

# ─── SESSION (semacam cookies login, lokal) ───────────────────────
func save_session() -> void:
	if current_username == "" or current_token == "":
		return
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"username": current_username,
		"token": current_token,
		"uid": current_uid,
	}))
	f.close()

func load_session() -> bool:
	if not FileAccess.file_exists(SESSION_PATH):
		return false
	var f := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	current_username = str(data.get("username", ""))
	current_token = str(data.get("token", ""))
	current_uid = str(data.get("uid", ""))
	return is_logged_in()

func clear_session() -> void:
	current_uid = ""
	current_username = ""
	current_token = ""
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)

# ─── HTTP CORE ────────────────────────────────────────────────────
func _request(method: int, path: String, body: Dictionary = {}, need_auth: bool = false, timeout: float = 20.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])
	if need_auth and current_token != "":
		headers.append("Authorization: Bearer " + current_token)

	var payload := ""
	if method == HTTPClient.METHOD_POST or method == HTTPClient.METHOD_PUT or method == HTTPClient.METHOD_PATCH:
		payload = JSON.stringify(body)

	var err := http.request(api_base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": -1, "data": {}, "raw": ""}

	var res: Array = await http.request_completed
	http.queue_free()

	var code := int(res[1])
	var raw := ""
	if res.size() > 3 and typeof(res[3]) == TYPE_PACKED_BYTE_ARRAY:
		raw = (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(raw) if raw != "" else null
	var data: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}

	return {"ok": code >= 200 and code < 300, "code": code, "data": data, "raw": raw}

# ─── AKUN ─────────────────────────────────────────────────────────
func register(username: String, password: String) -> bool:
	var r := await _request(HTTPClient.METHOD_POST, "/register", {
		"username": username,
		"password": password,
	})
	if r.get("ok", false):
		var user: Dictionary = r.get("data", {}).get("user", {})
		current_username = str(user.get("username", username))
		current_uid = str(user.get("id", ""))
		current_token = str(r.get("data", {}).get("token", ""))
		save_session()
		register_success.emit()
		return true
	register_failed.emit(str(r.get("data", {}).get("message", "Gagal membuat akun. Cek koneksi server.")))
	return false

func login(username: String, password: String) -> bool:
	var r := await _request(HTTPClient.METHOD_POST, "/login", {
		"username": username,
		"password": password,
	})
	if r.get("ok", false):
		var user: Dictionary = r.get("data", {}).get("user", {})
		current_username = str(user.get("username", username))
		current_uid = str(user.get("id", ""))
		current_token = str(r.get("data", {}).get("token", ""))
		save_session()
		login_success.emit()
		return true
	login_failed.emit(str(r.get("data", {}).get("message", "Login gagal. Cek koneksi server.")))
	return false

# ─── SLOT AUTO / MANUAL ───────────────────────────────────────────
func save_slot(slot: String, timeout: float = 20.0) -> bool:
	if not is_logged_in():
		return false
	var r := await _request(HTTPClient.METHOD_POST, "/saves/" + slot, {"data": _capture_state()}, true, timeout)
	if int(r.get("code", 0)) == 401:
		clear_session()
		return false
	if r.get("ok", false):
		save_success.emit(slot)
		print("[SaveManager] Simpan slot '%s' berhasil." % slot)
		return true
	push_warning("[SaveManager] Gagal simpan slot '%s' (%s): %s" % [slot, r.get("code"), r.get("raw")])
	return false

func load_slot(slot: String) -> bool:
	if not is_logged_in():
		return false
	var r := await _request(HTTPClient.METHOD_GET, "/saves/" + slot, {}, true)
	if int(r.get("code", 0)) == 401:
		clear_session()
		return false
	if not r.get("ok", false):
		return false
	var data = r.get("data", {}).get("data", {})
	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return false
	apply_state(data)
	load_success.emit(data)
	return true

# ─── CAPTURE / APPLY STATE ────────────────────────────────────────
func current_scene_path() -> String:
	if get_tree() and get_tree().current_scene and get_tree().current_scene.scene_file_path != "":
		return get_tree().current_scene.scene_file_path
	return "res://LEV0.tscn"

func is_in_game_level() -> bool:
	var p := current_scene_path()
	return p.contains("LEV0") or p.contains("LEV1") or p.contains("LEV2")

func _capture_state() -> Dictionary:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var pos := GameManager.spawn_override_position
	if player and is_instance_valid(player):
		pos = player.global_position

	var ona := get_tree().get_first_node_in_group("ona") as Node3D
	var ona_pos: Dictionary = {}
	var ona_wp: int = -1
	if ona and is_instance_valid(ona):
		ona_pos = {"x": ona.global_position.x, "y": ona.global_position.y, "z": ona.global_position.z}
		if "current_waypoint" in ona:
			ona_wp = int(ona.current_waypoint)

	var rallux := get_tree().get_first_node_in_group("rallux") as Node3D
	var rallux_pos: Dictionary = {}
	if rallux and is_instance_valid(rallux):
		rallux_pos = {"x": rallux.global_position.x, "y": rallux.global_position.y, "z": rallux.global_position.z}

	return {
		"scene": current_scene_path(),
		"player_position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"ona_position": ona_pos,
		"rallux_position": rallux_pos,
		"objective": {
			"current": GameManager.objective_current,
			"total": GameManager.objective_total,
			"item_name": GameManager.objective_item
		},
		"progress": {
			"rock_puzzle_done": GameManager.rock_puzzle_done,
			"river_crossed": GameManager.river_crossed,
			"point_9_dialog_done": GameManager.point_9_dialog_done,
			"ona_intro_done": GameManager.ona_intro_done,
			"ona_waypoint": ona_wp,
			"has_visited_workshop": GameManager.has_visited_workshop,
			"workshop_door_locked": GameManager.workshop_door_locked,
			"r1_puzzles_enabled": GameManager.r1_puzzles_enabled,
			"solved_levers": GameManager.solved_levers,
			"terminal_puzzle_done": GameManager.terminal_puzzle_done,
			"unpacking_rak1_done": GameManager.unpacking_rak1_done,
			"unpacking_completed": GameManager.unpacking_completed,
			"collected_fragments": GameManager.collected_fragments,
			"room_intro_seen": GameManager.room_intro_seen,
			"ona_hold_position": GameManager.ona_hold_position,
			"r1_morning_intro_done": GameManager.r1_morning_intro_done,
			"garden_intro_done": GameManager.garden_intro_done,
			"collected_flower_count": GameManager.collected_flower_count,
			"garden_night_active": GameManager.garden_night_active,
			"sleep_transition_done": GameManager.sleep_transition_done
		},
		"last_saved": Time.get_datetime_string_from_system()
	}

func apply_state(data: Dictionary) -> void:
	if data.is_empty():
		return

	var scene_path := str(data.get("scene", "res://LEV0.tscn"))
	pending_scene = scene_path if scene_path != "" else "res://LEV0.tscn"

	# Penanda agar scene tujuan tidak memutar ulang intro saat dimuat.
	GameManager.skip_intro_on_load = true

	var pos = data.get("player_position", {})
	if typeof(pos) == TYPE_DICTIONARY and pos.has("x"):
		var vec := Vector3(float(pos["x"]), float(pos["y"]), float(pos["z"]))
		GameManager.set_spawn_override(vec, pending_scene.get_file().get_basename())

	var opos = data.get("ona_position", {})
	if typeof(opos) == TYPE_DICTIONARY and opos.has("x"):
		GameManager.set_ona_override(Vector3(float(opos["x"]), float(opos["y"]), float(opos["z"])))

	var rpos = data.get("rallux_position", {})
	if typeof(rpos) == TYPE_DICTIONARY and rpos.has("x"):
		GameManager.set_rallux_override(Vector3(float(rpos["x"]), float(rpos["y"]), float(rpos["z"])))

	var obj = data.get("objective", {})
	if typeof(obj) == TYPE_DICTIONARY and not obj.is_empty():
		GameManager.objective_current = int(obj.get("current", 0))
		GameManager.objective_total = int(obj.get("total", 0))
		GameManager.objective_item = str(obj.get("item_name", ""))

	var pr = data.get("progress", {})
	if typeof(pr) == TYPE_DICTIONARY and not pr.is_empty():
		GameManager.rock_puzzle_done = bool(pr.get("rock_puzzle_done", false))
		GameManager.river_crossed = bool(pr.get("river_crossed", false))
		GameManager.point_9_dialog_done = bool(pr.get("point_9_dialog_done", false))
		GameManager.ona_intro_done = bool(pr.get("ona_intro_done", false))
		GameManager.ona_resume_waypoint = int(pr.get("ona_waypoint", -1))
		GameManager.has_visited_workshop = bool(pr.get("has_visited_workshop", false))
		GameManager.workshop_door_locked = bool(pr.get("workshop_door_locked", false))
		GameManager.r1_puzzles_enabled = bool(pr.get("r1_puzzles_enabled", true))
		GameManager.solved_levers = _as_dict(pr.get("solved_levers", {}))
		GameManager.terminal_puzzle_done = bool(pr.get("terminal_puzzle_done", false))
		GameManager.unpacking_rak1_done = bool(pr.get("unpacking_rak1_done", false))
		GameManager.unpacking_completed = bool(pr.get("unpacking_completed", false))
		GameManager.collected_fragments = _as_dict(pr.get("collected_fragments", {}))
		GameManager.room_intro_seen = _as_dict(pr.get("room_intro_seen", {}))
		GameManager.ona_hold_position = bool(pr.get("ona_hold_position", false))
		GameManager.r1_morning_intro_done = bool(pr.get("r1_morning_intro_done", false))
		GameManager.garden_intro_done = bool(pr.get("garden_intro_done", false))
		GameManager.collected_flower_count = int(pr.get("collected_flower_count", 0))
		GameManager.garden_night_active = bool(pr.get("garden_night_active", false))
		GameManager.sleep_transition_done = bool(pr.get("sleep_transition_done", false))

func _as_dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}

# ─── EXIT (auto-save) ─────────────────────────────────────────────
## - belum login -> tidak ada yang disimpan (quit biasa).
## - login, tapi belum masuk LEV0/1/2 -> hanya simpan sesi login.
## - login & di dalam level -> auto-save progres + sesi login.
func handle_exit_auto_save() -> void:
	if not is_logged_in():
		return
	if is_in_game_level():
		await save_slot(SLOT_AUTO, 4.0)
	save_session()
