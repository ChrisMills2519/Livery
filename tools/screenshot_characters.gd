extends SceneTree

## Renders idle and walking review shots of both player bodies.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_characters.gd
##
## Output: artifacts/chris_idle.png, chris_walk.png, liv_idle.png, liv_walk.png

const MAIN := "res://scenes/main.tscn"
const PROFILES := [
	preload("res://resources/characters/chris.tres"),
	preload("res://resources/characters/liv.tres"),
]

const IDLE_OFFSET := Vector3(2.4, 1.55, -3.4)
const WALK_OFFSET := Vector3(3.2, 1.55, -2.6)
const LOOK := Vector3(0.0, 1.0, 0.0)
const SPAWN := Vector3(60.0, 0.1, 40.0)

var _world: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _profile := 0
var _state := 0
var _frame := 0
var _walking := false


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_camera = Camera3D.new()
	_camera.name = "CharacterReviewCamera"
	_camera.fov = 45.0
	_camera.far = 400.0
	root.add_child(_camera)
	for layer in _world.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var horse := _world.get_node_or_null("Horse") as Node3D
	if horse != null:
		horse.visible = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	_frame += 1
	match _state:
		0:
			if _frame < 4:
				return false
			_player = _world.get_node("Player") as CharacterBody3D
			_start_profile()
			_state = 1
			_frame = 0
		1:
			if _frame < 30:
				return false
			_place(IDLE_OFFSET)
			_state = 2
			_frame = 0
		2:
			if _frame < 12:
				return false
			_save("idle")
			Input.action_press("move_forward")
			_walking = true
			_state = 3
			_frame = 0
		3:
			# Track the walking player so the body stays in frame; a fixed
			# camera loses it after half a metre.
			_place(WALK_OFFSET)
			if _frame < 24:
				return false
			_save("walk")
			Input.action_release("move_forward")
			_walking = false
			_profile += 1
			if _profile >= PROFILES.size():
				quit(0)
				return true
			_start_profile()
			_state = 1
			_frame = 0
	return false


func _start_profile() -> void:
	var profile: PlayerModelProfile = PROFILES[_profile]
	print("== ", profile.display_name, " ==")
	_player.set_character(profile)
	_player.global_position = SPAWN
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO


func _place(offset: Vector3) -> void:
	_camera.global_position = _player.global_position + offset
	_camera.look_at(_player.global_position + LOOK, Vector3.UP)
	_camera.current = true


func _save(shot: String) -> void:
	var profile: PlayerModelProfile = PROFILES[_profile]
	var name := profile.display_name.to_lower()
	var target := "res://artifacts/%s_%s.png" % [name, shot]
	var image := root.get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		return
	var anim := _player.get_node("AnimationPlayer") as AnimationPlayer
	var model := _player.get_node("Model") as Node3D
	print("saved ", target, " anim=", anim.current_animation, " walking=", _walking,
		" pos=", _player.global_position, " cam_dist=", _camera.global_position.distance_to(_player.global_position),
		" model=", model.name)
