extends SceneTree

## Renders a ridden jump over a real course fence.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_fence_jump.gd

const MAIN := "res://scenes/main.tscn"

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _course: Node3D
var _camera: Camera3D
var _frame := 0
var _phase := 0
var _captured := false


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_camera = Camera3D.new()
	_camera.name = "FenceJumpCamera"
	_camera.fov = 50.0
	_camera.far = 400.0
	root.add_child(_camera)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			if _frame < 6:
				return false
			for scenery in ["Forest", "NatureProps"]:
				var node := _world.get_node_or_null(scenery) as Node3D
				if node != null:
					node.visible = false
			_player = _world.get_node("Player") as CharacterBody3D
			_horse = _world.get_node("Horse") as CharacterBody3D
			_course = _world.get_node("RidingCourse") as Node3D
			_player.global_position = _horse.global_position + Vector3(1.2, 0.05, 0.1)
			_player.try_mount()
			_course.start_round()
			var jump: Dictionary = _course.get("_jumps")[0]
			var aabb: AABB = jump["aabb"]
			var centre := aabb.get_center()
			_player.rotation.y = PI
			_horse.global_position = Vector3(centre.x, 0.05, centre.z - 2.0)
			_horse.velocity = Vector3(0.0, 0.0, 4.5)
			_horse.set("_ride_speed", 4.5)
			_horse.airborne = false
			Input.action_press("move_forward")
			Input.action_press("jump")
			Engine.time_scale = 0.05
			_phase = 1
			_frame = 0
		1:
			Input.action_release("jump")
			_track()
			if not _captured and _horse.is_airborne() and _horse.air_phase > 0.4:
				_captured = true
				Engine.time_scale = 0.0
				_track()
				_shot("fence_jump_apex")
				print("apex: z=%.2f y=%.2f clears=%d" % [
					_horse.global_position.z, _horse.global_position.y, _course.cleared_count
				])
				Engine.time_scale = 0.05
			if _captured and not _horse.is_airborne():
				Input.action_release("move_forward")
				Engine.time_scale = 1.0
				quit(0)
				return true
	return false


func _track() -> void:
	if _horse == null:
		return
	_camera.current = true
	_camera.global_position = _horse.global_position + Vector3(3.6, 1.5, 2.1)
	_camera.look_at(_horse.global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP)


func _shot(name: String) -> void:
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s.png" % name
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
	else:
		print("saved ", target)
