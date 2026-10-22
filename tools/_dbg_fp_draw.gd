extends Node3D


func _ready() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.subdivide_width = 0
	quad.subdivide_depth = 0
	var mesh := MeshInstance3D.new()
	mesh.name = "FPQuad"
	mesh.mesh = quad
	add_child(mesh)

	var mat := load("res://resources/materials/footprint.tres") as ShaderMaterial
	if mat == null:
		push_error("footprint material not found")
		get_tree().quit()
		return
	var m := mat.duplicate() as ShaderMaterial
	m.set_shader_parameter("lifetime", 40.0)
	m.set_shader_parameter("tint", Color(0.20, 0.16, 0.12, 1.0))
	m.set_shader_parameter("tint_strength", 0.5)
	m.set_shader_parameter("now", 2.0)
	mesh.material_override = m

	mesh.transform = Transform3D(
		Basis(Vector3.UP, 0.0).scaled(Vector3(0.13, 1.0, 0.16)),
		Vector3(0.0, 0.012, 0.0)
	)

	var cam := Camera3D.new()
	cam.name = "TestCam"
	cam.fov = 10.0
	cam.near = 0.01
	cam.far = 20.0
	cam.global_position = Vector3(0.0, 2.0, 0.0)
	cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0))
	cam.current = true
	add_child(cam)


func _process(_delta: float) -> void:
	var view := get_viewport().get_texture()
	var img := view.get_image()
	var w := img.get_width()
	var h := img.get_height()
	var dark := 0
	var vals := PackedFloat32Array()
	for y in [h * 0.45, h * 0.5, h * 0.55]:
		for x in range(w):
			var px := img.get_pixel(x, y)
			var lum := (px.r + px.g + px.b) / 3.0
			vals.append(px.r)
			if lum < 0.5:
				dark += 1
	print("quad image %dx%d" % [w, h])
	print("dark pixels (<0.5): %d" % dark)
	vals.sort()
	var n := vals.size()
	var mean := 0.0
	for i in range(n):
		mean += vals[i]
	mean /= float(n)
	var g := vals[int(n * 0.5)]
	var lo := vals[int(n * 0.1)]
	var hi := vals[int(n * 0.9)]
	print("r8 mean: %.3f  median: %.3f  p10: %.3f  p90: %.3f" % [mean, g, lo, hi])
	get_tree().quit()
