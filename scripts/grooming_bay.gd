extends Node3D

## The physical grooming bay in the stable yard.  It owns the mat and posts,
## the proximity prompt and the G interaction.  The session child owns the
## camera and UI once grooming starts.

@export var player_range := 4.2
@export var horse_range := 4.8

@onready var horse_anchor: Marker3D = $HorseAnchor
@onready var groomer_anchor: Marker3D = $GroomerAnchor
@onready var session: Node = $Session

var _player: Node3D
var _horse: Node3D
var _prompt: Label3D
var _session_active := false
var _can_groom := false
var _tick := 0.0


func _ready() -> void:
	_build_set()
	_prompt = Label3D.new()
	_prompt.name = "GroomPrompt"
	_prompt.position = Vector3(0, 1.85, 1.15)
	_prompt.pixel_size = 0.006
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 52
	_prompt.outline_size = 10
	_prompt.modulate = Color(1.0, 0.96, 0.82, 1.0)
	_prompt.visible = false
	add_child(_prompt)
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_horse = get_tree().get_first_node_in_group("horse") as Node3D


func _build_set() -> void:
	var canvas := StandardMaterial3D.new()
	canvas.albedo_color = Color(0.31, 0.27, 0.19, 1.0)
	canvas.roughness = 1.0
	var mat := MeshInstance3D.new()
	mat.name = "Mat"
	var mat_mesh := BoxMesh.new()
	mat_mesh.size = Vector3(3.2, 0.05, 2.4)
	mat.mesh = mat_mesh
	mat.material_override = canvas
	mat.position = Vector3(0, 0.025, 0.2)
	mat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mat)

	# Keep the bay furniture behind the horse.  A tall post on the camera side
	# cut straight through the horse's neck during the orbit, so the back rail
	# supplies the working-yard read without ever blocking the groom.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.30, 0.20, 0.11, 1.0)
	wood.roughness = 0.9
	for z in [-0.95, 0.95]:
		var post := MeshInstance3D.new()
		post.name = "RailPost"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.05
		cylinder.bottom_radius = 0.065
		cylinder.height = 1.05
		post.mesh = cylinder
		post.material_override = wood
		post.position = Vector3(-1.52, 0.525, z)
		add_child(post)
	var rail := MeshInstance3D.new()
	rail.name = "Rail"
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.09, 0.09, 2.1)
	rail.mesh = rail_mesh
	rail.material_override = wood
	rail.position = Vector3(-1.52, 0.98, 0)
	add_child(rail)


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.10:
		return
	_tick = 0.0
	if _player == null or _horse == null:
		_bind()
		if _player == null or _horse == null:
			return
	if _session_active or session == null or bool(session.get("active")):
		_prompt.visible = false
		_can_groom = false
		return
	var player_near := _player.global_position.distance_to(groomer_anchor.global_position) < player_range
	var horse_near := _horse.global_position.distance_to(horse_anchor.global_position) < horse_range
	var mounted := bool(_player.get("mounted"))
	_can_groom = player_near and horse_near and not mounted
	_prompt.visible = player_near
	if not player_near:
		return
	if mounted:
		_prompt.text = "DISMOUNT TO GROOM"
	elif not horse_near:
		_prompt.text = "BRING YOUR HORSE HERE"
	else:
		_prompt.text = "G  ·  GROOM"


func _unhandled_input(event: InputEvent) -> void:
	if _session_active or session == null or bool(session.get("active")):
		return
	if not event.is_action_pressed("groom"):
		return
	if not _can_groom:
		return
	if session.has_method("enter"):
		session.call("enter", horse_anchor.global_transform, groomer_anchor.global_transform)


func set_session_active(active: bool) -> void:
	_session_active = active
	if _prompt != null:
		_prompt.visible = false
