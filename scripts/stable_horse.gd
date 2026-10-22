extends Node

## A decorative horse standing in one of the stable bays.
##
## It owns no gameplay: the imported clips are frozen on a standing frame so
## four extra skeletons stay cheap and the horses never wander into the
## stable's boarding interaction.

@export var clip := "Rest_Pose"
@export var pose_time := 0.08


func _ready() -> void:
	var player := _find_animation_player()
	if player == null:
		push_warning("StableHorse: no AnimationPlayer found")
		return
	if not player.has_animation(clip):
		push_warning("StableHorse: clip '%s' not found" % clip)
		return
	# Let the imported skeleton settle onto its rest transforms before the
	# clip writes the pose.
	await get_tree().process_frame
	player.play(clip)
	player.seek(pose_time, true)
	player.pause()


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
