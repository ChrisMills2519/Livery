extends SceneTree

## Renders close review shots of the saddle, bridle and live reins.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_tack.gd

const MAIN := "res://scenes/main.tscn"

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _camera: Camera3D
var _frame := 0
var _shot := 0
var _settle := 0
var _mounted := false
var _jumping := false
var _jump_frame := 0
var _output_prefix := ""

const SHOTS := [
	{"file": "tack_side", "offset": Vector3(4.2, 2.0, 0.5), "look": Vector3(0.0, 1.3, 0.0)},
	{"file": "tack_rear", "offset": Vector3(-2.4, 2.5, 3.2), "look": Vector3(0.0, 1.35, -0.1)},
	{"file": "tack_front", "offset": Vector3(2.2, 2.0, -3.4), "look": Vector3(0.0, 1.3, -0.4)},
	{"file": "tack_rider", "offset": Vector3(3.0, 2.2, 0.5), "look": Vector3(0.0, 1.55, 0.0)},
	{"file": "tack_head", "offset": Vector3(1.3, 1.8, -2.2), "look": Vector3(0.0, 1.35, -0.9)},
	{"file": "tack_jump", "offset": Vector3(3.6, 2.6, 0.8), "look": Vector3(0.0, 1.7, 0.0)},
]


func _initialize() -> void:
	var requested := OS.get_environment("GROOM_CHARACTER").strip_edges().to_lower()
	if not requested.is_empty():
		_output_prefix = requested + "_"
	var packed := load(MAIN) as PackedScene
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	_camera = Camera3D.new()
	_camera.name = "TackReviewCamera"
	_camera.fov = 52.0
	_camera.far = 400.0
	root.add_child(_camera)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 4:
		_player = _world.get_node("Player") as CharacterBody3D
		_horse = _world.get_node("Horse") as CharacterBody3D
		for n in _world.find_children("*", "CanvasLayer", true, false):
			(n as CanvasLayer).visible = false
		for m in _horse.find_children("*", "Label3D", true, false):
			(m as Label3D).visible = false
		# The horse follows the player and spins to face it at spawn.  Put the
		# review horse back on its authored heading and stand the player in
		# front so every camera label means what it says.
		_horse.rotation.y = 0.0
		_player.global_position = _horse.global_position + Vector3(0.0, 0.05, -1.2)
		_player.velocity = Vector3.ZERO
	elif _frame == 8 and not _mounted:
		_mounted = true
		_player.try_mount()
		print("mounted=", _player.mounted, " seat=", _horse.get_rider_seat_position())
		_place_camera()
		return false
	if not _mounted:
		return false
	if _jumping:
		_jump_frame += 1
		if _jump_frame == 4:
			# Hold the horse at the jump apex.  A real jump is driven by
			# physics, but this review shot must not race the landing.
			_horse.gravity = 0.0
			_horse.velocity = Vector3.ZERO
			_horse.global_position += Vector3.UP * 1.4
			_horse.airborne = true
			_horse._air_time = 0.45
			_horse.air_phase = 0.5
			_horse.fsm.set_airborne(true)
		if _jump_frame < 24:
			return false
		_jumping = false
		_settle = 10
	if _settle < 10:
		_settle += 1
		return false
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s%s.png" % [_output_prefix, String(SHOTS[_shot]["file"])]
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return true
	print("saved ", target)
	_shot += 1
	if _shot >= SHOTS.size():
		quit(0)
		return true
	_jumping = _shot == SHOTS.size() - 1
	_jump_frame = 0
	_place_camera()
	_settle = 0
	return false


func _place_camera() -> void:
	var shot: Dictionary = SHOTS[_shot]
	_camera.global_position = _horse.global_position + shot["offset"]
	_camera.look_at(_horse.global_position + shot["look"], Vector3.UP)
	_camera.current = true
