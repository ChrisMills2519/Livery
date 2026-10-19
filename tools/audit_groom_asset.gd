extends SceneTree

## Temporary audit for the horse grooming pipeline.

const HORSE := "res://scenes/horse.tscn"


func _dump_tree(node: Node, depth: int) -> void:
	if depth > 10:
		return
	var extra := ""
	if node is Node3D:
		extra = " pos=" + str((node as Node3D).position)
	if node is MeshInstance3D:
		extra += " skeleton_path=" + str((node as MeshInstance3D).skeleton)
	print("  ".repeat(depth), node.name, " [", node.get_class(), "]", extra)
	for child in node.get_children():
		_dump_tree(child, depth + 1)


func _initialize() -> void:
	var horse := (load(HORSE) as PackedScene).instantiate() as Node3D
	root.add_child(horse)
	await process_frame
	await process_frame
	var model := horse.get_node_or_null("Model") as Node3D
	print("model=", model)
	_dump_tree(horse, 0)
	var meshes := model.find_children("*", "MeshInstance3D", true, false) if model != null else []
	print("meshes=", meshes.size())
	for mesh_node in meshes:
		var mi := mesh_node as MeshInstance3D
		print("MESH ", mi.name, " parent=", mi.get_parent(), " mesh=", mi.mesh, " skin=", mi.skin,
			" skeleton=", mi.skeleton, " surfaces=", mi.mesh.get_surface_count() if mi.mesh != null else -1)
		if mi.mesh != null:
			var arrays := mi.mesh.surface_get_arrays(0)
			for i in range(arrays.size()):
				var v = arrays[i]
				if v is PackedVector3Array or v is PackedVector2Array or v is PackedInt32Array or v is PackedFloat32Array or v is PackedByteArray:
					print("  array ", i, " size=", v.size())
				else:
					print("  array ", i, " ", v)
		if mi.skin != null:
			print("  skin binds=", mi.skin.get_bind_count())
			for i in range(mini(mi.skin.get_bind_count(), 8)):
				print("    bind ", i, " name=", mi.skin.get_bind_name(i), " bone=", mi.skin.get_bind_bone(i),
					" pose=", mi.skin.get_bind_pose(i))
	var skeletons := horse.find_children("*", "Skeleton3D", true, false)
	print("skeletons=", skeletons.size())
	for s in skeletons:
		var sk := s as Skeleton3D
		print("  skeleton ", sk.name, " parent=", sk.get_parent(), " bones=", sk.get_bone_count())
		for i in range(sk.get_bone_count()):
			print("    ", i, " ", sk.get_bone_name(i))
	var anims := horse.find_children("*", "AnimationPlayer", true, false)
	for a in anims:
		print("animplayer ", a.name, " anims=", (a as AnimationPlayer).get_animation_list())
	quit(0)
	return
