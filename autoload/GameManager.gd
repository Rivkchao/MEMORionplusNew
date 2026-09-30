extends Node

var hud: CanvasLayer = null
var objective_current: int = 0
var objective_total: int = 0
var objective_item: String = ""

var spawn_override_position: Vector3 = Vector3.ZERO
var spawn_override_scene: String = "LEV1"
var has_spawn_override: bool = false
var rock_puzzle_done: bool = false
## Rion sudah menyeberangi sungai (fase setelah puzzle batu).
var river_crossed: bool = false
var point_9_dialog_done: bool = false
## Di-set true saat memuat save supaya Main.gd tidak memutar ulang intro.
var skip_intro_on_load: bool = false
## Intro jalan Ona di LEV1 (Point 1 -> Point 7) sudah selesai.
var ona_intro_done: bool = false
## Override posisi Ona dari save (dipakai sekali saat scene dimuat).
var spawn_ona_position: Vector3 = Vector3.ZERO
var has_ona_override: bool = false
## Waypoint Ona yang harus dilanjutkan setelah load (-1 = hitung dari posisi).
var ona_resume_waypoint: int = -1
## Override posisi Rallux dari save.
var spawn_rallux_position: Vector3 = Vector3.ZERO
var has_rallux_override: bool = false

# State R1 (Bengkel & Ruangan)
var has_visited_workshop: bool = false
var workshop_door_locked: bool = false
var r1_puzzles_enabled: bool = true
var solved_levers: Dictionary = {}
var terminal_puzzle_done: bool = false
var unpacking_rak1_done: bool = false
var unpacking_completed: bool = false
var collected_fragments: Dictionary = {}
var room_intro_seen: Dictionary = {}
var ona_hold_position: bool = false
var r1_morning_intro_done: bool = false

# State Scene 5 (Kebun Bunga Kosmik & Malam Hari)
var garden_intro_done: bool = false
var collected_flower_count: int = 0
var max_collectible_flowers: int = 10
var garden_night_active: bool = false
var sleep_transition_done: bool = false

func set_spawn_override(pos: Vector3, for_scene_name: String = "LEV1") -> void:
	spawn_override_position = pos
	spawn_override_scene = for_scene_name
	has_spawn_override = true

func consume_spawn_override_for(current_scene_str: String) -> Vector3:
	if has_spawn_override:
		if spawn_override_scene == "" or current_scene_str.contains(spawn_override_scene) or spawn_override_scene.contains(current_scene_str):
			has_spawn_override = false
			return spawn_override_position
	return Vector3.ZERO

func set_ona_override(pos: Vector3) -> void:
	spawn_ona_position = pos
	has_ona_override = true

func consume_ona_override() -> Vector3:
	if has_ona_override:
		has_ona_override = false
		return spawn_ona_position
	return Vector3.ZERO

func set_rallux_override(pos: Vector3) -> void:
	spawn_rallux_position = pos
	has_rallux_override = true

func consume_rallux_override() -> Vector3:
	if has_rallux_override:
		has_rallux_override = false
		return spawn_rallux_position
	return Vector3.ZERO

func save_state(player_node: Node3D, target_scene_for_override: String = "LEV1") -> void:
	if player_node:
		set_spawn_override(player_node.global_position, target_scene_for_override)

## Reset seluruh progres untuk memulai game baru (akun baru).
func reset_all_progress() -> void:
	objective_current = 0
	objective_total = 0
	objective_item = ""

	spawn_override_position = Vector3.ZERO
	spawn_override_scene = "LEV1"
	has_spawn_override = false
	rock_puzzle_done = false
	river_crossed = false
	point_9_dialog_done = false
	skip_intro_on_load = false
	ona_intro_done = false
	spawn_ona_position = Vector3.ZERO
	has_ona_override = false
	ona_resume_waypoint = -1
	spawn_rallux_position = Vector3.ZERO
	has_rallux_override = false

	has_visited_workshop = false
	workshop_door_locked = false
	r1_puzzles_enabled = true
	solved_levers = {}
	terminal_puzzle_done = false
	unpacking_rak1_done = false
	unpacking_completed = false
	collected_fragments = {}
	room_intro_seen = {}
	ona_hold_position = false
	r1_morning_intro_done = false

	garden_intro_done = false
	collected_flower_count = 0
	garden_night_active = false
	sleep_transition_done = false

func init(hud_node: CanvasLayer) -> void:
	hud = hud_node

func set_objective(text: String, total: int, item_name: String = "") -> void:
	objective_total = total
	objective_current = 0
	objective_item = item_name
	if hud:
		hud.set_objective(text)
		hud.set_progress(0, total, item_name)

func add_progress() -> void:
	objective_current = min(objective_current + 1, objective_total)
	if hud:
		hud.set_progress(objective_current, objective_total, objective_item)
	
	if objective_current >= objective_total:
		_on_objective_complete()

func _on_objective_complete() -> void:
	print("Objective complete!")
	StoryManager.start_dialogue(["Hebat! Semua target sudah selesai!"], "Rion")

func update_flower_hud() -> void:
	if hud:
		hud.set_objective("Petik bunga mekar di kebun bersama Ona (Tekan E / Aksi di dekat bunga)")
		# Jumlah bunga disembunyikan (hanya dipakai untuk teka-teki jumlah saat dialog)
		if hud.has_method("set_progress"):
			hud.set_progress(0, 0, "")
