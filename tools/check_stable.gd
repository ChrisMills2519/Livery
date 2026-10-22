extends SceneTree

## Headless check for the stable handover.
##
##   godot --headless --path . --script res://tools/check_stable.gd

const MAIN := "res://scenes/main.tscn"

var _frame := 0
var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _stable: Node3D
var _failures: Array[String] = []
var _horse_start := Vector3.ZERO


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_player = _world.get_node("Player") as CharacterBody3D
		_horse = _world.get_node("Horse") as CharacterBody3D
		_stable = _world.get_node("Stable") as Node3D
		_horse.global_position = Vector3.ZERO
		_horse.rotation.y = 0.0
		_horse.velocity = Vector3.ZERO
		_horse_start = _horse.global_position
		_player.global_position = Vector3(0.0, 0.05, 2.0)
	elif _frame == 5:
		# Walk well away from the horse.  It must stay where it was left.
		_player.global_position = Vector3(10.0, 0.05, 10.0)
	elif _frame == 45:
		var moved := Vector2(_horse.global_position.x, _horse.global_position.z).distance_to(
			Vector2(_horse_start.x, _horse_start.z)
		)
		_check(moved < 0.05, "riderless horse stays put (moved %.2f m)" % moved)
		_place_at_stable()
	elif _frame == 55:
		_stable.call("_refresh")
		_check(bool(_stable.get("_can_use")), "stable offers boarding with the horse led in")
		_check(bool(_horse.get("mount_prompt_suppressed")), "stable hides the overlapping mount prompt")
		_check(_prompt_text().contains("PUT HORSE AWAY"), "prompt offers PUT HORSE AWAY (got '%s')" % _prompt_text())
		_send_lead()
		_check(bool(_player.get("leading")), "the horse can be led up to the stable door")
		_send_interact()
		_check(bool(_horse.get("boarded")), "horse boards from the stable")
		_check(not _horse.visible, "boarded horse is hidden")
		_check(not _horse.can_mount(_player), "boarded horse cannot be mounted")
	elif _frame == 60:
		_stable.call("_refresh")
		_check(not bool(_player.get("leading")), "stabling drops the lead")
		_check(bool(_stable.get("_can_use")), "stable offers the horse back")
		_check(_prompt_text().contains("BRING HORSE OUT"), "prompt offers BRING HORSE OUT (got '%s')" % _prompt_text())
		_send_interact()
		var stall := _stable.get_node("HorseStall") as Marker3D
		_check(not bool(_horse.get("boarded")), "horse leaves the stable")
		_check(_horse.visible, "released horse is visible")
		_check(_horse.global_position.distance_to(stall.global_position) < 0.05, "released horse stands at the stall")
		_check(_horse.can_mount(_player), "released horse can be mounted")
	elif _frame == 65:
		# Leave the horse out in the far field and try to stable it from the door.
		_horse.global_position = Vector3(40.0, 0.0, 40.0)
		_player.global_position = (_stable.get_node("UseAnchor") as Marker3D).global_position
	elif _frame == 75:
		_stable.call("_refresh")
		_check(not bool(_stable.get("_can_use")), "stable refuses a horse left far away")
		_check(not bool(_horse.get("mount_prompt_suppressed")), "mount prompt returns when the stable prompt is gone")
		_check(_prompt_text().contains("BRING YOUR HORSE"), "prompt asks for the horse to be brought in")
		_send_interact()
		_check(not bool(_horse.get("boarded")), "far-away horse is not boarded")
		_finish()
		return true
	return false


func _place_at_stable() -> void:
	var stall := _stable.get_node("HorseStall") as Marker3D
	var use := _stable.get_node("UseAnchor") as Marker3D
	_horse.global_position = stall.global_position
	_horse.rotation.y = 0.0
	_horse.velocity = Vector3.ZERO
	_player.global_position = use.global_position
	_player.velocity = Vector3.ZERO


func _prompt_text() -> String:
	var prompt := _stable.get("_prompt") as Label3D
	return prompt.text if prompt != null else ""


func _send_lead() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F
	event.keycode = KEY_F
	event.pressed = true
	_player.call("_unhandled_input", event)


func _send_interact() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	_stable.call("_input", event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		print("  FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("STABLE CHECK: PASS")
		quit(0)
	else:
		print("STABLE CHECK: FAIL")
		quit(1)
