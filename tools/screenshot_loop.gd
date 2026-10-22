extends SceneTree

## Renders the schooling-round HUD and the gated arena.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_loop.gd

const MAIN := "res://scenes/main.tscn"

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _course: Node3D
var _review_cam: Camera3D
var _frame := 0
var _phase := 0
var _clear_index := 0


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_review_cam = Camera3D.new()
	_review_cam.name = "LoopReviewCamera"
	_review_cam.fov = 55.0
	_review_cam.far = 400.0
	root.add_child(_review_cam)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			if _frame < 6:
				return false
			_player = _world.get_node("Player") as CharacterBody3D
			_horse = _world.get_node("Horse") as CharacterBody3D
			_course = _world.get_node("RidingCourse") as Node3D
			_player.global_position = _horse.global_position + Vector3(1.2, 0.05, 0.1)
			_player.try_mount()
			_player.rotation.y = PI * 0.5
			_horse.global_position = Vector3(-7.0, 0.1, -1.5)
			_horse.velocity = Vector3.ZERO
			_phase = 1
			_frame = 0
		1:
			if _frame < 14:
				return false
			_shot("round_gate")
			_horse.global_position = Vector3(-12.5, 0.1, -1.5)
			_horse.velocity = Vector3.ZERO
			_phase = 2
			_frame = 0
		2:
			if _frame < 14:
				return false
			_shot("round_hud")
			_course.reset_round()
			_review_cam.global_position = Vector3(10.0, 24.0, 48.0)
			_review_cam.look_at(Vector3(-32.0, 1.0, 0.0), Vector3.UP)
			_review_cam.current = true
			_phase = 3
			_frame = 0
		3:
			if _frame < 10:
				return false
			_shot("arena_loop")
			# Keep the result card up for the screenshot.
			_course.reset_delay = 999.0
			_course.start_round()
			_clear_index = 0
			_phase = 4
			_frame = 0
		4:
			# Drop the horse over each fence to exercise the clear detection and
			# produce a real result card.
			if _frame % 3 == 1 and _clear_index < _course.get_jump_count():
				var jump: Dictionary = _course.get("_jumps")[_clear_index]
				var centre: Vector3 = (jump["aabb"] as AABB).get_center()
				_horse.global_position = Vector3(centre.x, 1.6, centre.z)
				_horse.velocity = Vector3(0.0, 2.0, 0.0)
				_horse.airborne = true
				_clear_index += 1
			if _frame < 36:
				return false
			_shot("round_result")
			_phase = 5
			_frame = 0
		5:
			if _frame == 1:
				_course.reset_round()
				_player.dismount()
				_player.global_position = Vector3(45.0, 0.1, 45.0)
				_player.rotation.y = 0.0
				Engine.time_scale = 0.2
				Input.action_press("move_forward")
			if _frame < 8:
				_review_cam.current = true
				_review_cam.global_position = _player.global_position + Vector3(3.2, 1.5, 2.8)
				_review_cam.look_at(_player.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
				return false
			_shot("player_walk")
			Input.action_release("move_forward")
			Engine.time_scale = 1.0
			quit(0)
			return true
	return false


func _shot(name: String) -> void:
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s.png" % name
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
	else:
		print("saved ", target)
