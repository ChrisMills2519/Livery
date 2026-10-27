extends Node3D
class_name JumpObstacle

signal pole_knocked(jump: Node3D, faults: int)
signal jump_cleared(jump: Node3D, height_tier: int)
signal height_changed(new_tier: int, height_m: float)

enum JumpType {
	VERTICAL,
	CROSSRAIL,
	CAVALETTI,
	OXER,
	TRIPLE_BAR,
	WALL,
	LIVERPOOL,
	BRUSH,
}

const TYPE_NAMES := [
	"Vertical", "Cross rail", "Cavaletti", "Oxer",
	"Triple bar", "Wall", "Liverpool", "Brush",
]

const HEIGHT_LEVELS := [0.60, 0.85, 1.05, 1.25]
const HEIGHT_NAMES := ["Intro (0.60m)", "Novice (0.85m)", "Intermediate (1.05m)", "Grand Prix (1.25m)"]
const NUMBER_BLOCKS := {
	1: preload("res://Models/split/horse_riding_obstacles_box_1_to_10_wooden_fence/05_No_1_Box.glb"),
	2: preload("res://Models/split/horse_riding_obstacles_box_1_to_10_wooden_fence/06_No_2_Box.glb"),
	3: preload("res://Models/split/horse_riding_obstacles_box_1_to_10_wooden_fence/07_No_3_Box.glb"),
	4: preload("res://Models/split/horse_riding_obstacles_box_1_to_10_wooden_fence/08_No_4_Box.glb"),
	5: preload("res://Models/split/horse_riding_obstacles_box_1_to_10_wooden_fence/09_No_5_Box.glb"),
	6: preload("res://Models/split/horse_riding_obstacles_box_1_to_10_wooden_fence/10_No_6_Box.glb"),
	7: preload("res://Models/split/horse_riding_obstacles_box_1_to_10_wooden_fence/11_No_7_Box.glb"),
	8: preload("res://Models/split/horse_riding_obstacles_box_1_to_10_wooden_fence/12_No_8_Box.glb"),
	9: preload("res://Models/split/horse_riding_obstacles_box_1_to_10_wooden_fence/13_No_9_Box.glb"),
	10: preload("res://Models/split/horse_riding_obstacles_box_1_to_10_wooden_fence/04_No_10_Box.glb"),
}
const NUMBER_BLOCK_SCALE := 1.8
const NUMBER_BLOCK_OFFSET := Vector3(2.2, 0.0, 0.35)

@export var jump_type: JumpType = JumpType.VERTICAL
@export var height_tier: int = 1:  # 0 to 3
	set(val):
		height_tier = clampi(val, 0, HEIGHT_LEVELS.size() - 1)
		if is_node_ready():
			_apply_height()
@export var course_number: int = 0:
	set(val):
		course_number = val
		if is_node_ready():
			_update_number_label()
			_update_number_block()
@export var allow_player_adjust: bool = false

@export_group("Knockdown")
## A struck rail is launched clear of the horse rather than dropping onto the
## sand: upward launch speed, plus a horizontal push scaled from the horse's
## approach speed and a base shove for slow impacts.
@export var knock_launch_up := 4.2
@export var knock_launch_speed_scale := 0.9
@export var knock_launch_base := 1.6
## Tumble rate in radians per second.  The rail lies along local X, so X is
## the end-over-end axis.
@export var knock_spin := 8.0

@onready var pole_top: RigidBody3D = get_node_or_null("PoleTop")
@onready var clatter_audio: AudioStreamPlayer3D = get_node_or_null("ClatterAudio")
@onready var knock_detector: Area3D = get_node_or_null("KnockDetector")
@onready var clear_detector: Area3D = get_node_or_null("ClearDetector")
@onready var interact_area: Area3D = get_node_or_null("InteractArea")
@onready var prompt_label: Label3D = get_node_or_null("PromptLabel")
@onready var number_label: Label3D = get_node_or_null("NumberLabel")
@onready var cups_node: Node3D = get_node_or_null("Cups")

var _is_knocked := false
var _is_cleared := false
var _top_rest_transform := Transform3D.IDENTITY
var _player_nearby := false
var _ignored_body: Node = null


## CONTEXT offer beside a fence the player can adjust: cycles its height.
func touch_context() -> Dictionary:
	if _player_nearby and allow_player_adjust:
		return {"action": "interact", "label": "RAISE", "priority": 2}
	return {}


func _ready() -> void:
	add_to_group("touch_context")
	add_to_group("jump_obstacle")
	_top_rest_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, get_current_height(), 0.0))
	_apply_height()
	reset_jump()
	_build_type_scenery()

	if knock_detector != null:
		knock_detector.body_entered.connect(_on_knock_body_entered)
	if clear_detector != null:
		clear_detector.body_entered.connect(_on_clear_body_entered)
	if interact_area != null:
		interact_area.body_entered.connect(_on_interact_body_entered)
		interact_area.body_exited.connect(_on_interact_body_exited)

	if prompt_label != null:
		prompt_label.visible = false
	_update_number_label()
	_update_number_block()


func get_current_height() -> float:
	return HEIGHT_LEVELS[clampi(height_tier, 0, HEIGHT_LEVELS.size() - 1)]


func get_height_name() -> String:
	return HEIGHT_NAMES[clampi(height_tier, 0, HEIGHT_NAMES.size() - 1)]


func get_type_name() -> String:
	return TYPE_NAMES[clampi(jump_type, 0, TYPE_NAMES.size() - 1)]


func set_height_tier(tier: int) -> void:
	height_tier = tier


func is_knocked() -> bool:
	return _is_knocked


func _apply_height() -> void:
	var h := get_current_height()
	_top_rest_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, h, 0.0))
	if not _is_knocked and pole_top != null:
		pole_top.freeze = true
		pole_top.transform = _top_rest_transform
		pole_top.linear_velocity = Vector3.ZERO
		pole_top.angular_velocity = Vector3.ZERO

	if cups_node != null:
		cups_node.position.y = h

	if clear_detector != null:
		clear_detector.position.y = h + 1.4

	if knock_detector != null:
		knock_detector.position.y = h

	if prompt_label != null:
		prompt_label.position.y = h + 0.85
		_update_prompt_text()

	if is_node_ready() and is_inside_tree():
		_build_type_scenery()
	height_changed.emit(height_tier, h)


# ---------------------------------------------------------------------------
# per-type scenery
# ---------------------------------------------------------------------------

var _type_materials := {}


func _type_material(key: String, colour: Color, roughness := 0.85) -> StandardMaterial3D:
	if _type_materials.has(key):
		return _type_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = roughness
	_type_materials[key] = mat
	return mat


func _add_scenery_box(centre: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = centre
	return mesh


## A striped show-jump rail made from alternating painted blocks.
func _add_rail(parent: Node3D, height: float, depth: float, length := 3.0, segments := 6) -> void:
	var white := _type_material("rail_white", Color(0.88, 0.86, 0.78))
	var red := _type_material("rail_red", Color(0.55, 0.10, 0.08))
	var piece := length / float(segments)
	for i in range(segments):
		var x := -length * 0.5 + piece * (i + 0.5)
		var mat := red if i % 2 == 0 else white
		parent.add_child(_add_scenery_box(Vector3(x, height, depth), Vector3(piece, 0.10, 0.10), mat))


func _build_type_scenery() -> void:
	var existing := get_node_or_null("TypeScenery")
	if existing != null:
		existing.free()
	if jump_type == JumpType.VERTICAL or jump_type == JumpType.CROSSRAIL \
			or jump_type == JumpType.CAVALETTI:
		return
	var root := Node3D.new()
	root.name = "TypeScenery"
	add_child(root)
	var h := get_current_height()
	match jump_type:
		JumpType.OXER:
			_add_rail(root, h - 0.26, -0.42)
			_apply_clear_depth(2.1, -0.34)
		JumpType.TRIPLE_BAR:
			_add_rail(root, h - 0.34, -0.62)
			_add_rail(root, h - 0.17, -0.31, 3.0, 6)
			_apply_clear_depth(2.3, -0.46)
		JumpType.WALL:
			var plaster := _type_material("wall_plaster", Color(0.72, 0.66, 0.55))
			var band := _type_material("wall_band", Color(0.33, 0.12, 0.09))
			root.add_child(_add_scenery_box(Vector3(0, h * 0.5 - 0.05, -0.32),
				Vector3(2.96, maxf(h - 0.08, 0.3), 0.26), plaster))
			root.add_child(_add_scenery_box(Vector3(0, h * 0.78, -0.32),
				Vector3(2.98, 0.16, 0.28), band))
			_apply_clear_depth(1.4, -0.20)
		JumpType.LIVERPOOL:
			var water := _type_material("water", Color(0.12, 0.31, 0.40), 0.12)
			var tray := _type_material("tray", Color(0.30, 0.31, 0.29))
			root.add_child(_add_scenery_box(Vector3(0, 0.035, -0.55),
				Vector3(3.5, 0.07, 1.35), tray))
			root.add_child(_add_scenery_box(Vector3(0, 0.075, -0.55),
				Vector3(3.3, 0.02, 1.12), water))
			_apply_clear_depth(2.5, -0.48)
		JumpType.BRUSH:
			var hedge := _type_material("brush", Color(0.18, 0.28, 0.13))
			root.add_child(_add_scenery_box(Vector3(0, 0.36, -0.34),
				Vector3(2.94, 0.72, 0.40), hedge))
			_apply_clear_depth(1.6, -0.26)


func _apply_clear_depth(depth: float, offset_z: float) -> void:
	if clear_detector == null:
		return
	var shape_node := clear_detector.get_node_or_null("ClearShape") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return
	var box := shape_node.shape.duplicate() as BoxShape3D
	if box == null:
		return
	box.size = Vector3(maxf(box.size.x, 3.2), box.size.y, depth)
	shape_node.shape = box
	clear_detector.position.z = offset_z


func _update_number_label() -> void:
	if number_label == null:
		return
	number_label.visible = false
	if course_number > 0:
		number_label.text = str(course_number)


func _update_number_block() -> void:
	var existing := get_node_or_null("NumberBlock")
	if existing != null:
		existing.free()
	if course_number <= 0 or not NUMBER_BLOCKS.has(course_number):
		return

	var model := (NUMBER_BLOCKS[course_number] as PackedScene).instantiate() as Node3D
	if model == null:
		return

	var block := Node3D.new()
	block.name = "NumberBlock"
	block.position = NUMBER_BLOCK_OFFSET
	block.scale = Vector3.ONE * NUMBER_BLOCK_SCALE
	add_child(block)
	block.add_child(model)

	var bounds := _local_mesh_aabb(model, Transform3D.IDENTITY)
	if bounds.size != Vector3.ZERO:
		model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)


func _local_mesh_aabb(node: Node, xform: Transform3D) -> AABB:
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	var result := AABB()
	var has_mesh := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result = local * (node as MeshInstance3D).get_aabb()
		has_mesh = true
	for child in node.get_children():
		var child_bounds := _local_mesh_aabb(child, local)
		if child_bounds.size == Vector3.ZERO:
			continue
		result = child_bounds if not has_mesh else result.merge(child_bounds)
		has_mesh = true
	return result


func _update_prompt_text() -> void:
	if prompt_label == null:
		return
	var text := Device.pick("E: Raise/Lower (", "TAP: Raise/Lower (") + get_height_name() + ")"
	if _is_knocked:
		text += Device.pick("\nR: Reset Rails", "\nRESET: Reset Rails")
	prompt_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	if not _player_nearby or not allow_player_adjust:
		return

	if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
		# Cycle height tier 0 -> 1 -> 2 -> 3 -> 0
		var next_tier := (height_tier + 1) % HEIGHT_LEVELS.size()
		height_tier = next_tier
		_update_prompt_text()
		get_viewport().set_input_as_handled()
	elif (event is InputEventKey and event.pressed and event.keycode == KEY_R) or event.is_action_pressed("restart_round"):
		reset_jump()
		_update_prompt_text()
		get_viewport().set_input_as_handled()


func _on_knock_body_entered(body: Node) -> void:
	if _is_knocked:
		return
	if not body.is_in_group("horse"):
		return
	# A horse whose body is already above the rail has cleared it; only a
	# horse that arrives at or below the rail knocks it off the cups.
	var horse := body as Node3D
	if horse != null and horse.global_position.y > get_current_height() + 0.4:
		return
	knock_down(body)


func knock_down(culprit: Node = null) -> void:
	if _is_knocked:
		return
	_is_knocked = true
	_is_cleared = false

	if pole_top != null:
		var travel := Vector3(0.0, 0.0, -1.0)
		var speed := 0.0
		if culprit is CharacterBody3D:
			var horse := culprit as CharacterBody3D
			var vel := horse.velocity
			vel.y = 0.0
			speed = vel.length()
			if speed > 0.1:
				travel = vel / speed
			else:
				var forward := -horse.global_transform.basis.z
				forward.y = 0.0
				if forward.length_squared() > 0.001:
					travel = forward.normalized()
			# Do not let the flying rail act as a wall: the horse carries on
			# through the gap while the pole is thrown clear.
			if horse.is_inside_tree():
				pole_top.add_collision_exception_with(horse)
				_ignored_body = horse
			if horse.has_method("apply_fence_impact"):
				horse.call("apply_fence_impact")

		var forward_push := speed * knock_launch_speed_scale + knock_launch_base
		var launch := Vector3(travel.x * forward_push, knock_launch_up, travel.z * forward_push)
		pole_top.freeze = false
		pole_top.sleeping = false
		pole_top.linear_velocity = launch
		pole_top.angular_velocity = Vector3(
			knock_spin * randf_range(0.75, 1.15),
			randf_range(-3.0, 3.0),
			randf_range(-2.5, 2.5)
		)

	if clatter_audio != null and clatter_audio.stream != null:
		clatter_audio.pitch_scale = randf_range(0.95, 1.05)
		clatter_audio.play()

	_update_prompt_text()
	pole_knocked.emit(self, 4)


func _on_clear_body_entered(body: Node) -> void:
	if _is_cleared or _is_knocked:
		return
	if not body.is_in_group("horse"):
		return
	var horse := body as Node3D
	if not horse.has_method("is_airborne") or not horse.is_airborne():
		return
	if horse.global_position.y < get_current_height() + 0.2:
		return
	_is_cleared = true
	jump_cleared.emit(self, height_tier)


func reset_jump() -> void:
	_is_knocked = false
	_is_cleared = false
	if pole_top != null:
		if _ignored_body != null:
			if is_instance_valid(_ignored_body) and _ignored_body.is_inside_tree():
				pole_top.remove_collision_exception_with(_ignored_body)
			_ignored_body = null
		pole_top.freeze = true
		pole_top.linear_velocity = Vector3.ZERO
		pole_top.angular_velocity = Vector3.ZERO
		pole_top.transform = _top_rest_transform
		pole_top.sleeping = true
	_update_prompt_text()


func _on_interact_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = true
		if prompt_label != null:
			_update_prompt_text()
			prompt_label.visible = true


func _on_interact_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		if prompt_label != null:
			prompt_label.visible = false
