extends Node3D

## Schooling round: the first complete gameplay loop.
##
## Mount the horse, clear a fence, and the round starts on that first fence.
## Clearing all eight fences pays money, the horse gains jumping training, and
## the best time is kept in GameState.  The round resets itself so the loop can
## be repeated.
##
## Nothing starts on its own: riding into the arena, through the gate or past a
## fence is free, so the arena can be explored.  Leaving the training area while
## a round runs cancels it without a result.
##
## The course owns the fence collisions and the floating fence numbers, so the
## arena scene stays a pure set-dressing scene.

signal round_started
signal jump_cleared(index: int, cleared: int, total: int)
signal fault_recorded(fault_amount: int, total_faults: int)
signal round_finished(result: Dictionary)
signal round_reset
signal notice(text: String)

const JUMP_PREFIX := "Jump_"
const COLLISION_HEIGHT := 0.90
const CLEAR_MIN_HEIGHT := 0.75
const CLEAR_Z_RADIUS := 1.1
const CLEAR_X_MARGIN := 0.3
## The training area.  A running round is cancelled once the horse is outside.
const TRAINING_MIN := Vector2(-49.5, -34.5)
const TRAINING_MAX := Vector2(-15.5, 34.5)

@export var jumps_root_path: NodePath = ^"../ArenaCourse/ArenaJumps"
## The loose jump beside the course: clearing it also opens a round, but it is
## not one of the eight and does not count towards the round.
@export var practice_jump_path: NodePath = ^"../ArenaCourse/ArenaJumps/PracticeJump"
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
var faults := 0

var _jumps: Array[Dictionary] = []
var _reset_left := 0.0


func _ready() -> void:
	add_to_group("riding_course")
	horse = get_tree().get_first_node_in_group("horse") as Node3D
	player = get_tree().get_first_node_in_group("player") as Node3D
	_build_jumps()
	_bind_practice_jump()
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
		var is_obstacle := (child as Node).has_signal("jump_cleared")
		# Physics jump obstacles own their own solid pole and standards.  Only
		# legacy static fences still need the invisible course collider.
		if not is_obstacle:
			var collision := StaticBody3D.new()
			collision.name = "FenceCollision%d" % index
			var shape_node := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(aabb.size.x, COLLISION_HEIGHT, aabb.size.z)
			shape_node.shape = box
			collision.add_child(shape_node)
			collision.position = Vector3(aabb.get_center().x, COLLISION_HEIGHT * 0.5, aabb.get_center().z)
			add_child(collision)

		var label: Label3D = null
		if is_obstacle:
			label = child.get_node_or_null("NumberLabel") as Label3D
			if label != null:
				label.visible = false
		else:
			label = Label3D.new()
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

		# Wire up dynamic JumpObstacle signals if present.
		var cur_idx := index - 1
		if child.has_signal("pole_knocked"):
			child.connect("pole_knocked", func(_j, fault_amount): _on_pole_knocked(cur_idx, fault_amount))
		if child.has_signal("jump_cleared"):
			child.connect("jump_cleared", func(_j, _tier): _clear_jump(cur_idx))

		_jumps.append({
			"node": child,
			"aabb": aabb,
			"label": label,
			"cleared": false,
		})


func _on_pole_knocked(idx: int, fault_amount: int) -> void:
	if state == "running":
		faults += fault_amount
		fault_recorded.emit(fault_amount, faults)
		notice.emit("Fence %d: Rail down! (+%d faults)" % [idx + 1, fault_amount])


func _global_mesh_aabb(node: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_global_mesh_aabb(node, boxes)
	if boxes.is_empty():
		return AABB()
	var result: AABB = boxes[0]
	for i in range(1, boxes.size()):
		result = result.merge(boxes[i])
	return result


func _collect_global_mesh_aabb(node: Node, boxes: Array[AABB]) -> void:
	if node.name == "NumberBlock":
		return
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh != null:
			boxes.append(instance.global_transform * instance.get_aabb())
	for child in node.get_children():
		_collect_global_mesh_aabb(child, boxes)


## The practice jump is not a course fence, so it is wired separately: it can
## open a round, but it is never counted as one of the eight.
func _bind_practice_jump() -> void:
	var jump := get_node_or_null(practice_jump_path)
	if jump == null or not jump.has_signal("jump_cleared"):
		return
	jump.connect("jump_cleared", func(_jump, _tier): _start_if_idle())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("restart_round"):
		return
	_reset_all_jumps()
	if state == "running":
		notice.emit("Rails reset")
	else:
		reset_round()
		notice.emit("Fences reset — clear a fence to start")


func _physics_process(delta: float) -> void:
	if horse == null or player == null:
		return

	match state:
		"running":
			elapsed += delta
			_check_jump_clears()
			if state != "running":
				return
			if elapsed >= time_limit:
				_finish(true)
				return
			_check_left_training_area()
		"finished":
			_reset_left -= delta
			if _reset_left <= 0.0:
				reset_round()


## A cleared fence is the player asking for a round.  Nothing else starts one.
func _start_if_idle() -> void:
	if state == "idle":
		start_round()


func is_inside_training_area(point: Vector3) -> bool:
	return (
		point.x >= TRAINING_MIN.x and point.x <= TRAINING_MAX.x
		and point.z >= TRAINING_MIN.y and point.z <= TRAINING_MAX.y
	)


## Wandering out of the arena mid-round ends it: no result, no reward.
func _check_left_training_area() -> void:
	if is_inside_training_area(horse.global_position):
		return
	reset_round()
	notice.emit("Round cancelled — you left the training area")


func start_round() -> void:
	if state == "running" or _jumps.is_empty():
		return
	state = "running"
	elapsed = 0.0
	cleared_count = 0
	faults = 0
	_reset_jump_visuals()
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
		# JumpObstacle nodes emit jump_cleared themselves via their ClearDetector
		# Area3D.  Skip the legacy AABB check for them to avoid counting twice.
		if (jump["node"] as Node).has_signal("jump_cleared"):
			continue
		var aabb: AABB = jump["aabb"]
		var centre := aabb.get_center()
		if absf(position.x - centre.x) > aabb.size.x * 0.5 + CLEAR_X_MARGIN:
			continue
		if absf(position.z - centre.z) > CLEAR_Z_RADIUS:
			continue
		_clear_jump(i)


func _clear_jump(index: int) -> void:
	# Clearing the first fence is what opens a round; everything before it was
	# free riding, so the clock starts here.  Fences cleared while the result
	# card is up are not part of any round.
	_start_if_idle()
	if state != "running":
		return
	var jump: Dictionary = _jumps[index]
	jump["cleared"] = true
	_jumps[index] = jump
	cleared_count += 1
	var label: Label3D = jump["label"]
	if label != null:
		if (jump["node"] as Node).has_signal("jump_cleared"):
			label.text = "CLEAR"
			label.visible = true
		else:
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
	var is_clear_round := (cleared_count >= _jumps.size() and faults == 0 and not timed_out)
	var new_best := false

	if is_clear_round:
		reward += 50  # Clear round bonus!
		var bonus := int(maxf(0.0, time_limit - elapsed) * time_bonus_per_second)
		reward += bonus
		new_best = GameState.record_round_time(elapsed)
		if horse.has_method("award_training"):
			horse.award_training(4.0, 2.0)
	elif cleared_count >= _jumps.size() and not timed_out:
		var bonus := int(maxf(0.0, time_limit - elapsed) * time_bonus_per_second)
		reward += bonus
		new_best = GameState.record_round_time(elapsed)
		if horse.has_method("award_training"):
			horse.award_training(3.0, 1.5)
	elif cleared_count > 0 and horse.has_method("award_training"):
		horse.award_training(cleared_count * 0.4, 0.5)

	GameState.add_money(reward)
	var result := {
		"clears": cleared_count,
		"total": _jumps.size(),
		"faults": faults,
		"seconds": elapsed,
		"reward": reward,
		"new_best": new_best,
		"timed_out": timed_out,
		"clear_round": is_clear_round,
	}
	round_finished.emit(result)
	if timed_out:
		notice.emit("Time! %d/%d fences, %d faults — ride back through the gate to try again" % [cleared_count, _jumps.size(), faults])
	elif is_clear_round:
		notice.emit("★ CLEAR ROUND! ★ 0 faults! +£%d" % reward)
	else:
		notice.emit("Round complete! %d faults, +£%d" % [faults, reward])


func reset_round() -> void:
	state = "idle"
	elapsed = 0.0
	cleared_count = 0
	faults = 0
	_reset_left = 0.0
	_reset_jump_visuals()
	_reset_all_jumps()

	round_reset.emit()


func _reset_all_jumps() -> void:
	# Reset all jump obstacles so fallen poles snap back onto cups.
	var root := get_node_or_null(jumps_root_path)
	if root == null:
		return
	for c in root.get_children():
		if c.has_method("reset_jump"):
			c.reset_jump()


func _reset_jump_visuals() -> void:
	for i in range(_jumps.size()):
		var jump: Dictionary = _jumps[i]
		jump["cleared"] = false
		_jumps[i] = jump
		var label: Label3D = jump["label"]
		if label != null:
			label.text = str(i + 1)
			label.modulate = Color(0.95, 0.92, 0.72, 1.0)
			label.visible = not (jump["node"] as Node).has_signal("jump_cleared")
