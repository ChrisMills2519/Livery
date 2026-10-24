extends SceneTree

## Run with:
##     godot --headless --path . --script res://tools/check_editor_load.gd
## Exits non-zero when a scene, script or texture setting is broken.

var _scanned := 0


func _initialize() -> void:
	print("=== CHECK FOR VRAM-COMPRESSED TEXTURES (mode=2) ===")
	var bad: Array = []
	var risky: Array = []
	for root in ["res://Models", "res://assets"]:
		_scan_imports(root, bad, risky)
	print("  Scanned %d .import files" % _scanned)
	if bad.size() == 0:
		print("  OK: no VRAM-compressed textures")
	else:
		print("  FAIL: %d VRAM-compressed textures found:" % bad.size())
		for b in bad:
			print("    - " + b)

	print("\n=== CHECK NORMAL MAPS STAY LOSSLESS ===")
	if risky.size() == 0:
		print("  OK: every normal map is lossless with 3D compression disabled")
	else:
		print("  FAIL: %d normal maps could be flipped to VRAM compression:" % risky.size())
		for r in risky:
			print("    - " + r)

	print("\n=== CHECK INTERIOR TEXTURES ARE LOSSLESS AND MIPMAPPED ===")
	var interior: Array = []
	_scan_interior_textures("res://Models/interior", interior)
	if interior.is_empty():
		print("  OK: interior textures are lossless, mipmapped and cannot flip to VRAM compression")
	else:
		print("  FAIL: %d interior textures are set up wrong:" % interior.size())
		for i in interior:
			print("    - " + i)

	print("\n=== CHECK SCENES LOAD ===")
	var scenes := [
		"res://scenes/character_select.tscn",
		"res://scenes/main.tscn", "res://scenes/player.tscn", "res://scenes/horse.tscn",
		"res://scenes/dog.tscn", "res://scenes/terrain.tscn", "res://scenes/stable.tscn",
		"res://scenes/arena_fence.tscn",
		"res://scenes/forest.tscn", "res://scenes/nature_props.tscn", "res://scenes/arena_course.tscn",
		"res://scenes/farmhouse.tscn",
		"res://scenes/competition_arena.tscn", "res://scenes/show_course.tscn",
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
	var passed: bool = ok and bad.is_empty() and risky.is_empty() and interior.is_empty()
	print("  ALL OK" if passed else "  ISSUES FOUND")
	quit(0 if passed else 1)


## The farmhouse's detail maps are multiplied over the furniture's own colours,
## so they must stay lossless (VRAM compression crashes this machine), carry
## mipmaps (or the grain shimmers across the room) and keep
## detect_3d/compress_to at 0 so no future 3D import can undo that.
func _scan_interior_textures(dir_path: String, problems: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".import"):
			continue
		var path := dir_path.path_join(f)
		var ini := FileAccess.open(path, FileAccess.READ)
		if ini == null:
			continue
		var is_texture := false
		var lossless := false
		var mipmapped := false
		var detect_3d := true
		while not ini.eof_reached():
			var line := ini.get_line().strip_edges()
			if line == "importer=\"texture\"":
				is_texture = true
			elif line.begins_with("compress/mode="):
				lossless = line.get_slice("=", 1).to_int() == 0
			elif line.begins_with("mipmaps/generate="):
				# Import files spell booleans "true"/"false", not 1/0.
				mipmapped = line.get_slice("=", 1).strip_edges() == "true"
			elif line.begins_with("detect_3d/compress_to="):
				detect_3d = line.get_slice("=", 1).to_int() != 0
		ini.close()
		if not is_texture:
			continue
		var source := path.trim_suffix(".import")
		if not lossless:
			problems.append(source + " is not lossless (compress/mode must be 0)")
		if not mipmapped:
			problems.append(source + " has no mipmaps")
		if detect_3d:
			problems.append(source + " could flip to VRAM compression (detect_3d/compress_to)")
	for sub in dir.get_directories():
		_scan_interior_textures(dir_path.path_join(sub), problems)


## Recursively scan .import files for VRAM-compressed textures. The previous
## version only looked at the top level of res://Models and therefore missed
## Models/split/, Models/medieval_village/ and everything under assets/.
func _scan_imports(dir_path: String, bad: Array, risky: Array) -> void:
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
		var is_texture := false
		var vram := false
		var normal_map := false
		var detect_3d := false
		while not ini.eof_reached():
			var line := ini.get_line().strip_edges()
			if line == "importer=\"texture\"":
				is_texture = true
			elif line.begins_with("compress/mode=2"):
				vram = true
			elif line.begins_with("compress/normal_map=1"):
				normal_map = true
			elif line.begins_with("detect_3d/compress_to="):
				detect_3d = line.get_slice("=", 1).to_int() != 0
		ini.close()
		# Audio importers also use compress/mode, and 2 is a valid audio
		# format there; only texture imports are relevant to this check.
		if is_texture and vram:
			bad.append(path.trim_suffix(".import"))
		# A normal map must stay lossless (see agents.md): VRAM-compressed
		# textures crash this machine. A nonzero detect_3d/compress_to would
		# silently flip it to mode=2 on the next 3D import, so guard that too.
		if is_texture and normal_map and detect_3d:
			risky.append(path.trim_suffix(".import"))
	for sub in dir.get_directories():
		_scan_imports(dir_path.path_join(sub), bad, risky)
