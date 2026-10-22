extends SceneTree

var _frame := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame != 2:
		return false
	var t := Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3(0.13, 1.0, 0.16)), Vector3(1, 0.012, 2))

	var a := MultiMesh.new()
	a.mesh = PlaneMesh.new()
	a.transform_format = MultiMesh.TRANSFORM_3D
	a.instance_count = 4
	a.set_instance_transform(0, t)
	print("A (mesh,fmt,count): ", a.get_instance_transform(0).origin)

	var b := MultiMesh.new()
	b.transform_format = MultiMesh.TRANSFORM_3D
	b.instance_count = 4
	b.mesh = PlaneMesh.new()
	b.set_instance_transform(0, t)
	print("B (fmt,count,mesh): ", b.get_instance_transform(0).origin)

	var c := MultiMesh.new()
	c.transform_format = MultiMesh.TRANSFORM_3D
	c.mesh = PlaneMesh.new()
	c.set_instance_transform(0, t)
	c.instance_count = 4
	print("C (fmt,mesh,write,count): ", c.get_instance_transform(0).origin)

	var d := MultiMesh.new()
	d.transform_format = MultiMesh.TRANSFORM_3D
	d.mesh = PlaneMesh.new()
	d.instance_count = 4
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = d
	root.add_child(holder)
	d.set_instance_transform(0, t)
	print("D (in tree): ", d.get_instance_transform(0).origin, " aabb ", d.get_aabb())

	var e := MultiMesh.new()
	e.transform_format = MultiMesh.TRANSFORM_3D
	e.mesh = PlaneMesh.new()
	e.instance_count = 4
	e.set_instance_transform(0, t)
	await process_frame
	print("E (after a frame): ", e.get_instance_transform(0).origin)

	quit(0)
	return true
