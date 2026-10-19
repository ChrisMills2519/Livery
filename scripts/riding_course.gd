extends Node3D

## Schooling round: the first complete gameplay loop.
##
## Mount the horse, ride through the arena gate, and clear all three fences.
## A cleared fence pays money, the horse gains jumping training, and the best
## time is kept in GameState.  The round resets itself so the loop can be
## repeated; the player only has to ride back out through the gate.
##
## The course owns the fence collisions and the floating fence numbers, so the
## arena scene stays a pure set-dressing scene.

signal round_started
signal jump_cleared(index: int, cleared: int, total: int)
signal round_finished(result: Dictionary)
signal round_reset
signal notice(text: String)

const JUMP_PREFIX := "Jump_"
const COLLISION_HEIGHT := 0.90
const CLEAR_MIN_HEIGHT := 0.75
const CLEAR_Z_RADIUS := 1.1
const CLEAR_X_MARGIN := 0.3
## Inside these bounds the round can start even if the player jumped the
## arena fence instead of using the gate.
const ARENA_MIN := Vector2(-34.5, -19.5)
const ARENA_MAX := Vector2(-15.5, 19.5)

@export var jumps_root_path: NodePath = ^"../ArenaCourse/ArenaJumps"
@export var gate_position := Vector3(-15.0, 0.0, -1.5)
@export var gate_radius := 4.0
@export var time_limit := 120.0
@export var base_reward := 25
@export var per_jump_reward := 15
@export var time_bonus_per_second := 0.5
@export var reset_delay := 6.0

var state := "idle"  # idle | running | finished
var elapsed := 0.0

var horse: Node3D
var player: Node3D
var cleared_count := 0

var _jumps: Array[Dictionary] = []
var _gate_armed := true
var _reset_left := 0.0
var _gate_beam: MeshInstance3D
var _gate_label: Label3D


func _ready() -> void:
	add_to_group("riding_course")
	horse = get_tree().get_first_node_in_group("horse") as Node3D
	player = get_tree().get_first_node_in_group("player") as Node3D
	_build_jumps()
	_build_gate_visuals()
	_reset_jump_visuals()
	if horse == null:
		push_warning("RidingCourse: no horse in the scene")
	_reset_left = 0.0


func get_jump_count() -> int:
	return _jumps.size()


func _build_jumps() -> void:
	var root := get_node_or_null(jumps_root_path)
	if root == null:
		push_warning("RidingCourse: jumps root '%s' not found" % jumps_root_path)
		return
	var index := 0
	for child in root.get_children():
		if not String(child.name).begins_with(JUMP_PREFIX):
			continue
		var aabb := _global_mesh_aabb(child as Node3D)
		if aabb.size == Vector3.ZERO:
			continue
		index += 1
		var collision := StaticBody3D.new()
		collision.name = "FenceCollision%d" % index
		var shape_node := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(aabb.size.x, COLLISION_HEIGHT, aabb.size.z)
		shape_node.shape = box
		collision.add_child(shape_node)
		collision.position = Vector3(aabb.get_center().x, COLLISION_HEIGHT * 0.5, aabb.get_center().z)
		add_child(collision)

		var label := Label3D.new()
		label.name = "FenceNumber%d" % index
		label.text = str(index)
		label.font_size = 64
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 10
		label.outline_modulate = Color(0.05, 0.08, 0.04, 1.0)
		label.modulate = Color(0.95, 0.92, 0.72, 1.0)
		label.position = Vector3(aabb.get_center().x, aabb.size.y + 0.55, aabb.get_center().z)
		add_child(label)

		_jumps.append({
			"node": child,
			"aabb": aabb,
			"label": label,
			"cleared": false,
		})


func _global_mesh_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var has_mesh := false
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		if instance.mesh == null:
			continue
		var box: AABB = instance.global_transform * instance.get_aabb()
		result = box if not has_mesh else result.merge(box)
		has_mesh = true
	return result


func _build_gate_visuals() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.45, 0.95, 0.55, 0.22)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.22
	mesh.bottom_radius = 0.22
	mesh.height = 6.0
	mesh.radial_segments = 12
	mesh.material = material
	_gate_beam = MeshInstance3D.new()
	_gate_beam.name = "GateBeam"
	_gate_beam.mesh = mesh
	_gate_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gate_beam.position = gate_position + Vector3.UP * 3.0
	add_child(_gate_beam)

	_gate_label = Label3D.new()
	_gate_label.name = "GateLabel"
	_gate_label.text = "SCHOOLING ROUND"
	_gate_label.font_size = 56
	_gate_label.pixel_size = 0.006
	_gate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_gate_label.no_depth_test = true
	_gate_label.outline_size = 10
	_gate_label.outline_modulate = Color(0.05, 0.1, 0.05, 1.0)
	_gate_label.modulate = Color(0.85, 1.0, 0.75, 1.0)
	_gate_label.position = gate_position + Vector3.UP * 4.1
	add_child(_gate_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_round") and state != "running":
		reset_round()
		notice.emit("Fences reset — ride through the gate to start")


func _physics_process(delta: float) -> void:
	if horse == null or player == null:
		return

	match state:
		"running":
			elapsed += delta
			_check_jump_clears()
			if state == "running" and elapsed >= time_limit:
				_finish(true)
		"finished":
			_reset_left -= delta
			if _reset_left <= 0.0:
				reset_round()
		_:
			_check_gate()


func _check_gate() -> void:
	if not (player as CharacterBody3D).mounted:
		return
	var to_gate := horse.global_position - gate_position
	to_gate.y = 0.0
	var inside_gate := to_gate.length() <= gate_radius
	var position := horse.global_position
	var inside_arena := (
		position.x >= ARENA_MIN.x and position.x <= ARENA_MAX.x
		and position.z >= ARENA_MIN.y and position.z <= ARENA_MAX.y
	)
	if not inside_gate and not inside_arena:
		_gate_armed = true
		return
	if _gate_armed and state == "idle":
		start_round()


func start_round() -> void:
	if state == "running" or _jumps.is_empty():
		return
	state = "running"
	elapsed = 0.0
	cleared_count = 0
	_gate_armed = false
	_reset_jump_visuals()
	if _gate_beam != null:
		_gate_beam.visible = false
	round_started.emit()
	notice.emit("Round started — clear all %d fences!" % _jumps.size())


func _check_jump_clears() -> void:
	if not horse.has_method("is_airborne") or not horse.is_airborne():
		return
	var position := horse.global_position
	if position.y < CLEAR_MIN_HEIGHT:
		return
	for i in range(_jumps.size()):
		var jump: Dictionary = _jumps[i]
		if jump["cleared"]:
			continue
		var aabb: AABB = jump["aabb"]
		var centre := aabb.get_center()
		if absf(position.x - centre.x) > aabb.size.x * 0.5 + CLEAR_X_MARGIN:
			continue
		if absf(position.z - centre.z) > CLEAR_Z_RADIUS:
			continue
		_clear_jump(i)


func _clear_jump(index: int) -> void:
	var jump: Dictionary = _jumps[index]
	jump["cleared"] = true
	_jumps[index] = jump
	cleared_count += 1
	var label: Label3D = jump["label"]
	if label != null:
		label.text = "%d  CLEAR" % (index + 1)
		label.modulate = Color(0.55, 1.0, 0.55, 1.0)
	jump_cleared.emit(index, cleared_count, _jumps.size())
	notice.emit("Fence %d cleared  (%d/%d)" % [index + 1, cleared_count, _jumps.size()])
	if cleared_count >= _jumps.size():
		_finish(false)


func _finish(timed_out: bool) -> void:
	if state != "running":
		return
	state = "finished"
	_reset_left = reset_delay

	var reward := base_reward + cleared_count * per_jump_reward
	var new_best := false
	if cleared_count >= _jumps.size() and not timed_out:
		var bonus := int(maxf(0.0, time_limit - elapsed) * time_bonus_per_second)
		reward += bonus
		new_best = GameState.record_round_time(elapsed)
		if horse.has_method("award_training"):
			horse.award_training(3.0, 1.5)
	elif cleared_count > 0 and horse.has_method("award_training"):
		horse.award_training(cleared_count, 0.5)

	GameState.add_money(reward)
	var result := {
		"clears": cleared_count,
		"total": _jumps.size(),
		"seconds": elapsed,
		"reward": reward,
		"new_best": new_best,
		"timed_out": timed_out,
	}
	round_finished.emit(result)
	if timed_out:
		notice.emit("Time!  %d/%d fences — ride back through the gate to try again" % [cleared_count, _jumps.size()])
	else:
		notice.emit("Round complete!  +%d money" % reward)


func reset_round() -> void:
	state = "idle"
	elapsed = 0.0
	cleared_count = 0
	_reset_left = 0.0
	_reset_jump_visuals()
	_gate_armed = false
	if _gate_beam != null:
		_gate_beam.visible = true
	round_reset.emit()


func _reset_jump_visuals() -> void:
	for i in range(_jumps.size()):
		var jump: Dictionary = _jumps[i]
		jump["cleared"] = false
		_jumps[i] = jump
		var label: Label3D = jump["label"]
		if label != null:
			label.text = str(i + 1)
			label.modulate = Color(0.95, 0.92, 0.72, 1.0)
