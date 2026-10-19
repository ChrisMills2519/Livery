extends SceneTree

## Headless verification for the split horse clips.
##   godot --headless --path . --script tools/check_horse_animations.gd

const EXPECTED := {
	"Idle_Standing_A": 5.5,
	"Paw": 3.5,
	"Idle_Look_A": 4.0,
	"Idle_Standing_B": 4.5,
	"Look": 3.5,
	"Paw_Hind": 3.0,
	"Graze": 3.0,
	"Idle_Standing_C": 2.5,
	"Trot": 91.0 / 24.0,
	"Canter": 55.0 / 24.0,
	"Walk": 82.0 / 24.0,
	"LieDown": 2.5,
	"StandUp": 0.5,
	"Rear": 31.0 / 24.0,
	"Buck": 31.0 / 24.0,
	"HeadToss": 106.0 / 24.0,
	"Idle_Standing_D": 79.0 / 24.0,
	"LookUp": 46.0 / 24.0,
	"Idle_Standing_E": 67.0 / 24.0,
	"Idle_Low": 80.0 / 24.0,
}

var _frames := 0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/horse.tscn")
	root.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	var horse := root.get_node_or_null("Horse")
	if horse == null:
		push_error("Horse node missing")
		quit(1)
		return true

	var player: AnimationPlayer = _find_player(horse)
	if player == null:
		push_error("AnimationPlayer missing")
		quit(1)
		return true

	var names := player.get_animation_list()
	print("ANIMATIONS (%d): %s" % [names.size(), names])
	var failures: Array[String] = []
	for n in EXPECTED.keys():
		if not player.has_animation(n):
			failures.append("missing " + n)
			continue
		var anim := player.get_animation(n)
		var expected: float = EXPECTED[n]
		var delta := absf(anim.length - expected)
		print("%-18s length=%.4f expected=%.4f loop=%d" % [n, anim.length, expected, anim.loop_mode])
		if delta > 0.02:
			failures.append("%s length %.4f != %.4f" % [n, anim.length, expected])

	for n in ["Idle_Look_A", "Walk", "Trot", "Canter"]:
		if player.has_animation(n) and player.get_animation(n).loop_mode != Animation.LOOP_LINEAR:
			failures.append(n + " is not looping")

	var fsm := horse.get_node_or_null("AnimStateMachine")
	if fsm == null:
		failures.append("AnimStateMachine missing")
	else:
		print("FSM state=%s states=%s" % [fsm.current_state, fsm.get_available_states()])
		if fsm.current_state != "idle":
			failures.append("FSM did not start in idle")

	if failures.is_empty():
		print("HORSE ANIMATION CHECK: PASS")
		quit(0)
	else:
		for f in failures:
			push_error(f)
		print("HORSE ANIMATION CHECK: FAIL")
		quit(1)
	return true


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null
