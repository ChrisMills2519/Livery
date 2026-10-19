extends MainLoop
func _init():
	var d = DirAccess.open("res://")
	print("class: " + d.get_class())
	var methods = []
	for m in d.get_method_list():
		if m.name.begins_with("eof") or m.name.begins_with("is_eof"):
			methods.append(m.name)
	print("eof methods: " + str(methods))
	Engine.get_main_loop().get_tree().quit()
