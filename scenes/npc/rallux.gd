extends CharacterBody3D

@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree")

var _playback: AnimationNodeStateMachinePlayback = null

func _ready() -> void:
	add_to_group("npc")
	add_to_group("rallux")
	_setup_animation_tree()

func _setup_animation_tree() -> void:
	if animation_tree == null:
		animation_tree = get_node_or_null("AnimationTree")

	if animation_tree:
		animation_tree.active = true
		_playback = animation_tree.get("parameters/playback")
		if _playback:
			_playback.start("idle")

func play_animation(animation_name: String) -> void:
	if animation_player:
		var anim = animation_player.get_animation(animation_name)
		if anim and (animation_name == "run" or animation_name == "idle" or animation_name == "searching"):
			anim.loop_mode = Animation.LOOP_LINEAR
	if animation_tree and animation_tree.active and _playback:
		_playback.travel(animation_name)
	elif animation_player and animation_player.current_animation != animation_name:
		animation_player.play(animation_name)
