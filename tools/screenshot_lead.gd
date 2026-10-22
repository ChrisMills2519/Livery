extends SceneTree

## Renders the lead: walking the horse out and standing with it.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_lead.gd

const MAIN := "res://scenes/main.tscn"

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _camera: Camera3D
var _start := 0
var _state := 0
var _state_ms := 0


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_camera = Camera3D.new()
	_camera.name = "LeadReviewCamera"
	_camera.fov = 48.0
	_camera.far = 400.0
	root.add_child(_camera)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	if _start == 0:
		_start = now
	match _state:
		0:
			if now - _start >= 300:
				_begin()
				_next(1, now)
		1:
			if now - _state_ms >= 200:
				_send_key(KEY_F)
				Input.action_press("move_forward")
				_next(2, now)
		2:
			if now - _state_ms >= 1200:
				_capture("lead_walking")
				Input.action_release("move_forward")
				_next(3, now)
		3:
			if now - _state_ms >= 1200:
				_capture("lead_idle")
				quit(0)
				return true
	if now - _start > 15000:
		push_error("lead screenshot timed out")
		quit(1)
		return true
	return false


func _begin() -> void:
	_player = _world.get_node("Player") as CharacterBody3D
	_horse = _world.get_node("Horse") as CharacterBody3D
	for n in _world.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	_horse.global_position = Vector3(0.0, 0.0, 1.6)
	_horse.rotation.y = 0.0
	_horse.velocity = Vector3.ZERO
	_player.global_position = Vector3(0.0, 0.05, 4.0)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO


func _capture(name: String) -> void:
	_camera.global_position = _player.global_position + Vector3(3.4, 2.3, 4.2)
	_camera.look_at(_player.global_position + Vector3(0.3, 1.0, -0.8), Vector3.UP)
	_camera.current = true
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s.png" % name
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return
	print("saved ", target)


func _next(state: int, now: int) -> void:
	_state = state
	_state_ms = now


func _send_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	_player.call("_unhandled_input", event)
