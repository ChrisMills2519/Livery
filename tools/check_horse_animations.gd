extends SceneTree

## Headless verification for the split horse clips.
##   godot --headless --path . --script tools/check_horse_animations.gd

## The current horse GLB ships its own clip library.  Durations are the glTF
## sampler lengths in seconds.
const EXPECTED := {
	"Death": 1.400,
	"Eating": 2.667,
	"Head_But": 1.000,
	"Idle": 2.667,
	"Kick": 1.300,
	"Rear": 2.933,
	"Rest_Pose": 0.167,
	"Run": 0.433,
	"Sleep": 2.000,
	"Trot": 0.700,
	"Turn_Left": 4.667,
	"Turn_Right": 4.667,
	"Walk": 0.967,
	"lay_to_idle": 2.667,
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

	for n in ["Idle", "Walk", "Trot", "Run"]:
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
