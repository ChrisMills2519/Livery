extends SceneTree

## Run with:
##     godot --headless --path . --script res://tools/check_editor_load.gd
## Exits non-zero when a scene, script or texture setting is broken.

var _scanned := 0


func _initialize() -> void:
	print("=== CHECK FOR VRAM-COMPRESSED TEXTURES (mode=2) ===")
	var bad: Array = []
	for root in ["res://Models", "res://assets"]:
		_scan_imports(root, bad)
	print("  Scanned %d .import files" % _scanned)
	if bad.size() == 0:
		print("  OK: no VRAM-compressed textures")
	else:
		print("  FAIL: %d VRAM-compressed textures found:" % bad.size())
		for b in bad:
			print("    - " + b)

	print("\n=== CHECK SCENES LOAD ===")
	var scenes := [
		"res://scenes/character_select.tscn",
		"res://scenes/main.tscn", "res://scenes/player.tscn", "res://scenes/horse.tscn",
		"res://scenes/terrain.tscn", "res://scenes/stable.tscn", "res://scenes/arena_fence.tscn",
		"res://scenes/forest.tscn", "res://scenes/nature_props.tscn", "res://scenes/arena_course.tscn",
	]
	var ok := true
	for s in scenes:
		var sc := load(s)
		if sc == null:
			print("  FAIL: %s" % s)
			ok = false
		else:
			print("  OK: %s" % s)

	print("\n=== CHECK SCRIPTS COMPILE ===")
	var script_dir := DirAccess.open("res://scripts")
	if script_dir == null:
		print("  FAIL: cannot open res://scripts")
		ok = false
	else:
		for f in script_dir.get_files():
			if not f.ends_with(".gd"):
				continue
			var path := "res://scripts/" + f
			var script := load(path)
			if script == null:
				print("  FAIL: %s" % path)
				ok = false
			else:
				print("  OK: %s" % path)

	print("\n=== CHECK GLTF/GLB IMPORTS ===")
	var glbs: Array = []
	var model_dir := DirAccess.open("res://Models")
	if model_dir:
		for f in model_dir.get_files():
			if f.ends_with(".glb.import") or f.ends_with(".gltf.import"):
				glbs.append("res://Models/" + f)
	print("  Found %d imported GLB/GLTF files" % glbs.size())

	print("\n=== RESULT ===")
	var passed: bool = ok and bad.is_empty()
	print("  ALL OK" if passed else "  ISSUES FOUND")
	quit(0 if passed else 1)


## Recursively scan .import files for VRAM-compressed textures. The previous
## version only looked at the top level of res://Models and therefore missed
## Models/split/, Models/medieval_village/ and everything under assets/.
func _scan_imports(dir_path: String, bad: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".import"):
			continue
		_scanned += 1
		var path := dir_path.path_join(f)
		var ini := FileAccess.open(path, FileAccess.READ)
		if ini == null:
			continue
		while not ini.eof_reached():
			var line := ini.get_line().strip_edges()
			if line.begins_with("compress/mode=2"):
				bad.append(path.trim_suffix(".import"))
		ini.close()
	for sub in dir.get_directories():
		_scan_imports(dir_path.path_join(sub), bad)
