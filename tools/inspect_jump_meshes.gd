extends SceneTree

func _initialize() -> void:
	var paths := [
		"res://Models/split/show_jumping____horse_jumping_obstacles/13_Pole.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/07_HalfBarrier1.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/09_HalfBarrier2.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/11_Holder1.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/12_Holder2.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/00_Barrier1.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/01_Barrier2.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/02_BarrierEvery3D.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/03_Cavaletti1.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/04_Cavaletti2.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/05_FlagRed.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/06_FlagWhite.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/08_HalfBarrier1Every3D.glb",
		"res://Models/split/show_jumping____horse_jumping_obstacles/10_HalfBarrier2Every3D.glb",
	]

	for path in paths:
		var scene := load(path) as PackedScene
		if scene == null:
			print("SKIP: %s (cannot load)" % path)
			continue
		var inst := scene.instantiate()
		var aabb := AABB()
		var has := false
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var local_aabb := m.get_aabb()
			var world_aabb := m.transform * local_aabb
			if not has:
				aabb = world_aabb
				has = true
			else:
				aabb = aabb.merge(world_aabb)
		inst.queue_free()
		if has:
			print("%s" % path.get_file())
			print("  AABB pos=(%s)  size=(%s)" % [aabb.position, aabb.size])
			print("  centre=(%s)" % aabb.get_center())
			print("  min_y=%.4f  max_y=%.4f" % [aabb.position.y, aabb.position.y + aabb.size.y])
		else:
			print("%s: NO MESH" % path.get_file())
	print("\nDONE")
	quit()
