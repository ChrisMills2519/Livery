extends SceneTree

## Renders the airborne jump pose from a clean close side view.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_jump.gd
##
## Output: artifacts/jump_takeoff.png, jump_apex.png, jump_descent.png,
##         jump_landed.png

const MAIN := "res://scenes/main.tscn"
const OPEN_GROUND := Vector3(45, 0.1, 45)

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _review_cam: Camera3D
var _frame := 0
var _phase := 0
var _settle := 0
var _pending := ""
var _jump_started := false
var _captured := {}


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_review_cam = Camera3D.new()
	_review_cam.name = "JumpReviewCamera"
	_review_cam.fov = 48.0
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
			# Clear the review background; the forest hides the legs.
			for scenery in ["Forest", "NatureProps"]:
				var node := _world.get_node_or_null(scenery) as Node3D
				if node != null:
					node.visible = false
			_player.global_position = _horse.global_position + Vector3(1.2, 0.05, 0.1)
			_player.velocity = Vector3.ZERO
			_phase = 1
			_frame = 0
		1:
			if _frame == 1:
				_player.try_mount()
				_player.rotation.y = 0.0
				_horse.global_position = OPEN_GROUND
				_horse.velocity = Vector3.ZERO
				Input.action_press("move_forward")
				Input.action_press("gallop")
			if _frame < 70:
				_track_horse()
				return false
			Input.action_press("jump")
			_phase = 2
			_frame = 0
			Engine.time_scale = 0.12
		2:
			Input.action_release("jump")
			_track_horse()
			var phase: float = _horse.air_phase
			var airborne: bool = _horse.is_airborne()
			if not _jump_started and airborne:
				_jump_started = true
			if _settle > 0:
				_settle -= 1
				if _settle == 0:
					_shot(_pending)
				return false
			if _jump_started and not airborne:
				_shot("jump_landed")
				Engine.time_scale = 1.0
				Input.action_release("move_forward")
				Input.action_release("gallop")
				quit(0)
				return true
			if _jump_started:
				if phase < 0.24 and not _captured.has("jump_takeoff"):
					_settle = 2
					_pending = "jump_takeoff"
				elif phase > 0.42 and phase < 0.65 and not _captured.has("jump_apex"):
					_settle = 2
					_pending = "jump_apex"
				elif phase > 0.82 and phase < 0.96 and not _captured.has("jump_descent"):
					_settle = 2
					_pending = "jump_descent"
	return false


func _track_horse() -> void:
	if _horse == null:
		return
	_review_cam.current = true
	_review_cam.global_position = _horse.global_position + Vector3(3.0, 1.55, 1.7)
	_review_cam.look_at(_horse.global_position + Vector3(0.0, 1.15, 0.0), Vector3.UP)


func _shot(name: String) -> void:
	if name.is_empty() or _captured.has(name):
		return
	_captured[name] = true
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s.png" % name
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
	else:
		print("saved ", target)
