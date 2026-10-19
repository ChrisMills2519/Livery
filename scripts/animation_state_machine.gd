extends Node
class_name AnimationStateMachine

## Drives an AnimationPlayer with named animation clips.
##
## The horse GLB ships one clip per action, split from the original 60 second
## take by tools/split_horse_animations.py. This node picks the gait clip from
## the horse's speed and lets AnimationPlayer blend between clips.
##
## Gaits are picked from real ground speed, and the playback speed is matched to
## the clip's own cruise speed so a horse easing through a walk does not look
## like it is trotting on the spot.  An explicit airborne state takes priority
## over the gait so a jump is never overwritten by the next speed tick.

signal state_changed(from_state: String, to_state: String)

@export_group("Clips")
@export var idle_animation := "Idle_Look_A"
@export var walk_animation := "Walk"
@export var trot_animation := "Trot"
@export var canter_animation := "Canter"
## Optional one-shot. The current horse asset has no jump clip, so the horse's
## JumpPose overlay supplies the airborne pose instead.
@export var air_animation := "Jump"

@export_group("Transition thresholds (metres per second)")
@export var walk_threshold := 0.25
@export var trot_threshold := 3.4
@export var canter_threshold := 5.8

@export_group("Gait cruise speeds (metres per second)")
@export var walk_reference_speed := 2.5
@export var trot_reference_speed := 4.5
@export var canter_reference_speed := 7.2

@export_group("Playback")
@export var match_playback_speed := true
@export var min_speed_scale := 0.7
@export var max_speed_scale := 1.5
@export var blend_time := 0.18
@export var air_time_scale := 0.35

var player: AnimationPlayer
var current_state := ""
var airborne := false

var _anim_names := {}
var _state_speed := {}
var _one_shot := ""
var _has_air_clip := false


func _ready() -> void:
	player = _find_animation_player()
	if player == null:
		push_warning("AnimationStateMachine: no AnimationPlayer found under the scene root")
		return
	_build_states()
	_has_air_clip = player.has_animation(air_animation)
	if _has_air_clip:
		var air := player.get_animation(air_animation)
		if air != null:
			air.loop_mode = Animation.LOOP_NONE
	if not _anim_names.is_empty():
		player.animation_finished.connect(_on_animation_finished)
		set_state("idle")


func _find_animation_player() -> AnimationPlayer:
	var root: Node = owner if owner != null else get_parent()
	return _find_by_class(root, "AnimationPlayer") as AnimationPlayer


func _find_by_class(n: Node, type_name: String) -> Node:
	if n.is_class(type_name):
		return n
	for c in n.get_children():
		var r: Node = _find_by_class(c, type_name)
		if r != null:
			return r
	return null


func _build_states() -> void:
	var names := {
		"idle": idle_animation,
		"walk": walk_animation,
		"trot": trot_animation,
		"canter": canter_animation,
	}
	for state_name in names.keys():
		var anim_name: String = names[state_name]
		if not player.has_animation(anim_name):
			push_warning("AnimationStateMachine: animation '%s' not found (state '%s')" % [anim_name, state_name])
			continue
		var anim := player.get_animation(anim_name)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		_anim_names[state_name] = anim_name
		_state_speed[state_name] = 1.0


func set_state(state_name: String) -> void:
	if not _anim_names.has(state_name):
		return
	# The airborne pose owns the skeleton until the horse lands.
	if airborne:
		current_state = state_name
		return
	if state_name == current_state and _one_shot == "":
		return
	if _one_shot != "":
		return
	var from := current_state
	current_state = state_name
	if player != null:
		player.speed_scale = 1.0
		player.play(_anim_names[state_name], blend_time)
	state_changed.emit(from, state_name)


## Play one of the non-looping clips (Graze, Rear, Buck, ...) once, then
## return to the current gait when it finishes.
func play_action(action_name: String) -> void:
	if player == null or not player.has_animation(action_name):
		return
	var anim := player.get_animation(action_name)
	if anim != null and anim.loop_mode != Animation.LOOP_NONE:
		push_warning("AnimationStateMachine: '%s' is a looping clip, not a one-shot action" % action_name)
		return
	_one_shot = action_name
	player.speed_scale = 1.0
	player.play(action_name, blend_time)


func is_playing_action() -> bool:
	return _one_shot != ""


func has_air_clip() -> bool:
	return _has_air_clip


func set_airborne(value: bool) -> void:
	if airborne == value:
		return
	airborne = value
	if player == null:
		return
	if airborne:
		_one_shot = ""
		if _has_air_clip:
			player.speed_scale = 1.0
			player.play(air_animation, blend_time)
		# Without a clip the gait keeps running slowly while the JumpPose
		# overlay supplies the tuck/extend pose.
		elif player.current_animation != "":
			player.speed_scale = air_time_scale
	else:
		player.speed_scale = 1.0
		if _has_air_clip and _anim_names.has(current_state):
			player.play(_anim_names[current_state], blend_time)
		elif not _anim_names.has(current_state) and not _anim_names.is_empty():
			current_state = "idle"
			player.play(_anim_names["idle"], blend_time)


func _on_animation_finished(anim_name: StringName) -> void:
	if _one_shot != "" and String(anim_name) == _one_shot:
		_one_shot = ""
		if _anim_names.has(current_state) and not airborne:
			player.speed_scale = 1.0
			player.play(_anim_names[current_state], blend_time)


func update_for_speed(speed: float) -> void:
	if _one_shot != "" or airborne:
		return
	var want := "idle"
	if speed >= canter_threshold:
		want = "canter"
	elif speed >= trot_threshold:
		want = "trot"
	elif speed > walk_threshold:
		want = "walk"
	set_state(want)

	if match_playback_speed and player != null and player.current_animation != "":
		var reference := _reference_speed(current_state)
		var scale := 1.0
		if reference > 0.0:
			scale = clampf(speed / reference, min_speed_scale, max_speed_scale)
		player.speed_scale = scale


func _reference_speed(state_name: String) -> float:
	match state_name:
		"walk":
			return walk_reference_speed
		"trot":
			return trot_reference_speed
		"canter":
			return canter_reference_speed
		_:
			return 0.0


func get_available_states() -> Array:
	return _anim_names.keys()
