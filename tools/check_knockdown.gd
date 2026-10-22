extends SceneTree

const SCENE := "res://scenes/jump_obstacle.tscn"

var _jump: Node3D
var _fake_horse: CharacterBody3D
var _step := 0
var _knock_signal_received := false
var _knocked_faults := 0
var _cleared_tier := -1
var _done := false

func _initialize() -> void:
	var packed = load(SCENE) as PackedScene
	if packed == null:
		print("FAIL: could not load ", SCENE)
		quit(1)
		return

	_jump = packed.instantiate()
	root.add_child(_jump)

	_fake_horse = CharacterBody3D.new()
	_fake_horse.add_to_group("horse")
	_fake_horse.velocity = Vector3(0, 0, -4.5)
	root.add_child(_fake_horse)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	match _step:
		0:
			# 1. Check initial state
			assert(_jump.height_tier == 1, "Default height_tier should be 1 (Novice 0.85m)")
			assert(is_equal_approx(_jump.get_current_height(), 0.85), "Current height should be 0.85")
			assert(_jump.pole_top != null, "pole_top should exist")
			assert(_jump.pole_top.freeze == true, "pole_top should be frozen initially")
			assert(_jump.allow_player_adjust == false, "course jumps should not be height-adjustable")

			# Geometry: the split GLBs retain the source layout offset, so the
			# pole and standards must be re-centred on the obstacle origin.
			var pole_box := _mesh_aabb(_jump.pole_top)
			var pole_centre := pole_box.get_center()
			assert(pole_box.size.x > 2.9 and pole_box.size.x < 3.1,
				"pole should be 3.0 m wide (got %.2f)" % pole_box.size.x)
			assert(absf(pole_centre.x) < 0.02 and absf(pole_centre.z) < 0.02,
				"pole should be centred on the obstacle (got %s)" % pole_centre)
			assert(absf(pole_centre.y - _jump.get_current_height()) < 0.02,
				"pole should sit at cup height (got y %.2f, expected %.2f)" % [pole_centre.y, _jump.get_current_height()])
			var left_box := _mesh_aabb(_jump.get_node("WingLeft"))
			var right_box := _mesh_aabb(_jump.get_node("WingRight"))
			assert(absf(left_box.get_center().x + 1.5) < 0.12,
				"left standard should be at x -1.5 (got %.2f)" % left_box.get_center().x)
			assert(absf(right_box.get_center().x - 1.5) < 0.12,
				"right standard should be at x +1.5 (got %.2f)" % right_box.get_center().x)
			assert(absf(left_box.get_center().z) < 0.12 and absf(right_box.get_center().z) < 0.12,
				"standards should sit in the pole plane")
			print("Step 1: Initial state and geometry verified. Height = %.2f m" % _jump.get_current_height())

			# 2. Test height change
			_jump.height_tier = 2  # Intermediate 1.05m
			assert(is_equal_approx(_jump.get_current_height(), 1.05), "Height should be 1.05m")
			assert(is_equal_approx(_jump.pole_top.position.y, 1.05), "Pole position.y should be 1.05m")
			print("Step 2: Height adjustment verified (tier 2 = 1.05m)")

			# 3. Test knockdown
			_jump.pole_knocked.connect(func(_j, faults):
				_knock_signal_received = true
				_knocked_faults = faults
			)
			_jump.knock_down(_fake_horse)
			assert(_knock_signal_received == true, "pole_knocked signal should be emitted")
			assert(_knocked_faults == 4, "Knockdown should assess 4 faults")
			assert(_jump.pole_top.freeze == false, "pole_top should be unfrozen after knockdown")
			var launch_vel: Vector3 = _jump.pole_top.linear_velocity
			assert(launch_vel.y > 1.0,
				"knocked rail should launch upward, not drop (got y %.2f)" % launch_vel.y)
			assert(Vector2(launch_vel.x, launch_vel.z).length() > 1.0,
				"knocked rail should fly along the approach, not straight down")
			assert(_jump.pole_top.angular_velocity.length() > 1.0,
				"knocked rail should tumble")
			print("Step 3: Physics knockdown verified (4 faults, rail launched at %.1f m/s, tumbling)" % launch_vel.length())

			# 4. Test reset
			_jump.reset_jump()
			assert(_jump.pole_top.freeze == true, "pole_top should be frozen after reset")
			assert(is_equal_approx(_jump.pole_top.position.y, 1.05), "pole_top position should be restored to cup height")
			print("Step 4: Reset rails verified")

			# 5. Test clean clearance
			_jump.jump_cleared.connect(func(_j, tier):
				_cleared_tier = tier
			)
			var horse_script = load("res://scripts/horse.gd")
			_fake_horse.set_script(horse_script)
			_fake_horse.set("airborne", true)
			_fake_horse.global_position.y = 2.0
			_jump._on_clear_body_entered(_fake_horse)
			assert(_cleared_tier == 2, "jump_cleared should be emitted with height_tier 2")
			print("Step 5: Clean clearance verified")

			print("KNOCKDOWN CHECK: PASS")
			quit(0)
			return true
	return false


func _mesh_aabb(node: Node3D) -> AABB:
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
