extends MeshInstance3D

@export var target_camera : Camera3D

func _process(_delta):
	if target_camera:
		global_position = target_camera.global_position
