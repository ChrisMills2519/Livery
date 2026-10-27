extends Node

signal action_finished(clip_name: String)

@export_group("Gaits")
@export var walk_clip := "Walk"
@export var trot_clip := "Trot"
@export var run_clip := "Run"
@export var idle_clip := "Idle"

@export_group("Gait thresholds")
@export var trot_threshold := 1.15
@export var run_threshold := 2.4

@export_group("Reference speeds")
## Body speed (m/s) each clip plants its feet at.  These are measured from the
## built clips (tools/build_chihuahua.py, "measured ... ground speed"), so a
## clip only stays planted while it plays near its reference speed.  The dog is
## driven at these speeds, and dog.gd must not ask for more than the clip can
## cover or the paws go back to skating.
@export var walk_reference_speed := 0.73
@export var trot_reference_speed := 1.86
@export var run_reference_speed := 3.26

@export_group("Playback")
@export var blend_time := 0.18
@export var min_speed_scale := 0.85
@export var max_speed_scale := 1.2

const LOOPING := [
	"Idle", "Idle_Alert", "Walk", "Trot", "Run", "TailWag",
	"Sit", "Eat", "Sleep", "Rest_Pose",
]

var player: AnimationPlayer
var current_clip := ""

var _one_shot := ""


func _ready() -> void:
	player = _find_animation_player()
	if player == null:
		push_warning("DogAnimator: no AnimationPlayer found")
		return
	_configure_clips()
	player.animation_finished.connect(_on_animation_finished)
	if player.has_animation(idle_clip):
		set_pose(idle_clip, 0.0)


func _find_animation_player() -> AnimationPlayer:
	var root: Node = owner if owner != null else get_parent()
	return _find_by_class(root, "AnimationPlayer") as AnimationPlayer


func _find_by_class(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _find_by_class(child, type_name)
		if found != null:
			return found
	return null


func _configure_clips() -> void:
	for clip_name in player.get_animation_list():
		var animation := player.get_animation(clip_name)
		if animation == null:
			continue
		animation.loop_mode = (
			Animation.LOOP_LINEAR if clip_name in LOOPING else Animation.LOOP_NONE
		)


func set_pose(clip_name: String, blend := -1.0) -> void:
	if player == null or not player.has_animation(clip_name):
		return
	_one_shot = ""
	if current_clip == clip_name and player.is_playing():
		player.speed_scale = 1.0
		return
	player.speed_scale = 1.0
	player.play(clip_name, blend_time if blend < 0.0 else blend)
	current_clip = clip_name


func play_action(clip_name: String, blend := -1.0) -> void:
	if player == null or not player.has_animation(clip_name):
		return
	_one_shot = clip_name
	player.speed_scale = 1.0
	player.play(clip_name, blend_time if blend < 0.0 else blend)
	current_clip = clip_name


func set_locomotion(speed: float) -> void:
	if player == null:
		return
	if speed < 0.12:
		set_pose(idle_clip)
		return
	if _one_shot != "":
		return
	# A small hold on the current gait keeps it from flapping right at a
	# threshold, where the clip's speed scale would jump back and forth.
	var hold := 0.9
	var clip_name := walk_clip
	var reference := walk_reference_speed
	if _has_any([run_clip]) and (
		speed >= run_threshold
		or (current_clip == run_clip and speed >= run_threshold * hold)
	):
		clip_name = run_clip
		reference = run_reference_speed
	elif _has_any([trot_clip]) and (
		speed >= trot_threshold
		or (current_clip == trot_clip and speed >= trot_threshold * hold)
	):
		clip_name = trot_clip
		reference = trot_reference_speed
	elif not _has_any([walk_clip]):
		clip_name = idle_clip
		reference = 0.0
	var scale := 1.0
	if reference > 0.0:
		scale = clampf(speed / reference, min_speed_scale, max_speed_scale)
	if current_clip != clip_name:
		player.speed_scale = scale
		player.play(clip_name, blend_time)
		current_clip = clip_name
	else:
		player.speed_scale = scale


func _has_any(clips: Array) -> bool:
	for clip_name in clips:
		if player != null and player.has_animation(clip_name):
			return true
	return false


func get_current_clip() -> String:
	return current_clip


func is_playing_action() -> bool:
	return _one_shot != ""


func _on_animation_finished(anim_name: StringName) -> void:
	if _one_shot == "" or String(anim_name) != _one_shot:
		return
	_one_shot = ""
	action_finished.emit(current_clip)
