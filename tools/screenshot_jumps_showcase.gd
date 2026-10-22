extends SceneTree

const JUMP_SCENE := "res://scenes/jump_obstacle.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"

var _phase := 0
var _frame := 0
var _world: Node3D
var _camera: Camera3D
var _jump: Node3D

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	
	# Load main scene
	var packed = load(MAIN_SCENE) as PackedScene
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	
	# Hide heavy background scenery so software Mesa/llvmpipe doesn't lag/OOM
	for name in ["Forest", "NatureProps"]:
		var n = _world.get_node_or_null(name) as Node3D
		if n != null:
			n.visible = false

	_camera = Camera3D.new()
	_camera.name = "ShowcaseCam"
	_camera.fov = 55.0
	_camera.far = 300.0
	root.add_child(_camera)
	_camera.current = true


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			# Give shaders/shadows 10 frames to settle
			if _frame < 12:
				return false
			
			# Shot 1: Arena Overview with the new jumps & flags
			_camera.global_position = Vector3(-6.0, 16.0, 36.0)
			_camera.look_at(Vector3(-32.0, 1.0, 0.0), Vector3.UP)
			_phase = 1
			_frame = 0
		1:
			if _frame == 4:
				_save_shot("arena_training_overview")
				_phase = 2
				_frame = 0
		2:
			# Shot 2: Close-up of Jump_01 (Intact pole resting on cups, with red/white flags)
			var jumps_root = _world.find_child("ArenaJumps", true, false)
			if jumps_root:
				_jump = jumps_root.find_child("Jump_01", true, false)
			if _jump:
				var jp = _jump.global_position
				_camera.global_position = jp + Vector3(2.6, 1.3, 3.2)
				_camera.look_at(jp + Vector3(0.0, 0.75, 0.0), Vector3.UP)
			_phase = 3
			_frame = 0
		3:
			if _frame == 4:
				_save_shot("jump_obstacle_intact")
				_phase = 4
				_frame = 0
		4:
			# Shot 3: Knock down Jump_01 and let the pole tumble with physics!
			if _jump and _jump.has_method("knock_down"):
				var fake = CharacterBody3D.new()
				fake.velocity = Vector3(0.0, 0.0, -4.5)
				_jump.knock_down(fake)
				fake.free()
			_phase = 5
			_frame = 0
		5:
			# Let physics simulate for 15 frames so pole hits the ground and rolls
			if _frame == 15:
				_save_shot("jump_obstacle_knocked")
				_phase = 6
				_frame = 0
		6:
			# Shot 4: Practice Jump with height interaction prompt
			var jumps_root = _world.find_child("ArenaJumps", true, false)
			var practice = jumps_root.find_child("PracticeJump", true, false) if jumps_root else null
			if practice:
				var prompt = practice.find_child("PromptLabel", true, false) as Label3D
				if prompt:
					prompt.visible = true
				var pp = practice.global_position
				_camera.global_position = pp + Vector3(2.4, 1.4, 2.8)
				_camera.look_at(pp + Vector3(0.0, 0.9, 0.0), Vector3.UP)
			_phase = 7
			_frame = 0
		7:
			if _frame == 4:
				_save_shot("practice_jump_prompt")
				print("ALL SCREENSHOTS CAPTURED SUCCESSFULLY!")
				quit(0)
				return true
	return false


func _save_shot(name: String) -> void:
	var img = root.get_texture().get_image()
	var path = ProjectSettings.globalize_path("res://artifacts/%s.png" % name)
	var err = img.save_png(path)
	if err == OK:
		print("Saved screenshot: ", path)
	else:
		push_error("Failed to save screenshot: " + path)
