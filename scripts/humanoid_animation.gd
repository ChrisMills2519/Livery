extends RefCounted

## The shared humanoid library addresses %GeneralSkeleton.  Unique-name binding
## is scoped to each GLB subscene, not to the node that owns the
## AnimationPlayer, so every consumer has to rebase the tracks onto the
## skeleton's real relative path.  This is what lets Chris's
## Armature/GeneralSkeleton and Liv's Node/GeneralSkeleton share one library.

const LIBRARY_NAME := "humanoid"
const LIBRARY_PATH := "res://assets/animations/humanoid.res"


static func rebind(
	anim_player: AnimationPlayer,
	model: Node3D,
	skeleton: Skeleton3D,
	source: AnimationLibrary = null
) -> bool:
	if anim_player == null or model == null or skeleton == null:
		return false
	if source == null and anim_player.has_animation_library(LIBRARY_NAME):
		source = anim_player.get_animation_library(LIBRARY_NAME)
	if source == null:
		source = load(LIBRARY_PATH) as AnimationLibrary
	if source == null:
		push_warning("HumanoidAnimation: library not found")
		return false

	var rebased := AnimationLibrary.new()
	var relative := model.get_path_to(skeleton)
	for animation_name in source.get_animation_list():
		var animation := source.get_animation(animation_name).duplicate(true) as Animation
		for track in range(animation.get_track_count()):
			var bone := animation.track_get_path(track).get_concatenated_subnames()
			var path := relative if bone.is_empty() else NodePath(str(relative) + ":" + bone)
			animation.track_set_path(track, path)
		rebased.add_animation(animation_name, animation)

	if anim_player.has_animation_library(LIBRARY_NAME):
		anim_player.remove_animation_library(LIBRARY_NAME)
	anim_player.add_animation_library(LIBRARY_NAME, rebased)
	return true
