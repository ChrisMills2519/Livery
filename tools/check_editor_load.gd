extends SceneTree

## Run with:
##     godot --headless --path . --script res://tools/check_editor_load.gd
## Exits non-zero when a scene, script or texture setting is broken.

## The interior textures the house depends on, guarded one by one instead of by
## sweeping all of res://Models/interior: a blanket scan forces every future
## texture that lands there to change its import cost, which is not this
## check's call.
##
## The four detail maps and the Food Kit atlas are the texture pass's own: every
## surface that reads as wood, cloth, stone or metal goes through one of them.
## They must stay lossless (VRAM compression crashes this machine), carry mipmaps
## (or the grain shimmers across the room) and keep detect_3d/compress_to at 0 so
## no future 3D import can undo that.
##
## The wall and floor maps predate that pass and were 1k with no mipmaps.  They
## are on this list because they are now mipmapped on purpose: they tile across
## the largest surfaces in the house, and without mips the floor and walls
## shimmer at a distance.  That is about 2.8 MB of decoded VRAM, already counted
## in the 18.1 MB that `tools/check_interior_cost.gd` measures against its 20 MB
## budget; if that budget ever gets tight, this is the first thing to give back.
const INTERIOR_TEXTURES := [
	"res://Models/interior/textures/detail_wood_diff_512.jpg",
	"res://Models/interior/textures/detail_fabric_diff_512.jpg",
	"res://Models/interior/textures/detail_stone_diff_512.jpg",
	"res://Models/interior/textures/detail_metal_diff_256.jpg",
	"res://Models/interior/kenney_food_kit/Textures/colormap.png",
	"res://Models/interior/textures/painted_plaster_wall_diff_1k.jpg",
	"res://Models/interior/textures/wood_floor_diff_1k.jpg",
]

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
	for texture in INTERIOR_TEXTURES:
		_check_interior_texture(texture, interior)
	if interior.is_empty():
		print("  OK: %d interior textures are lossless, mipmapped and cannot flip to VRAM compression" % INTERIOR_TEXTURES.size())
	else:
		print("  FAIL: %d interior textures are set up wrong:" % interior.size())
		for i in interior:
			print("    - " + i)

	print("\n=== CHECK SCENES LOAD ===")
	# Discovered, not hand-listed: a copied list drifts as scenes come and go, and
	# the version of this check that shipped in the texture pass named two scenes
	# that were never committed, so it failed on every fresh clone.
	var scenes: Array = []
	_scene_paths("res://scenes", scenes)
	scenes.sort()
	print("  Found %d scenes under res://scenes" % scenes.size())
	var ok := true
	if scenes.is_empty():
		print("  FAIL: no scenes found under res://scenes")
		ok = false
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


## Recursively collect every scene under res://scenes, so the load check covers
## what the project actually ships instead of a list that can go stale.
func _scene_paths(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			out.append(dir_path.path_join(f))
	for sub in dir.get_directories():
		_scene_paths(dir_path.path_join(sub), out)


## One interior texture's import settings.  A missing .import file means the
## texture was never imported, which is just as broken as a wrong setting.
func _check_interior_texture(source: String, problems: Array) -> void:
	var path := source + ".import"
	var ini := FileAccess.open(path, FileAccess.READ)
	if ini == null:
		problems.append(source + " has no .import file")
		return
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
		problems.append(source + " is not imported as a texture")
		return
	if not lossless:
		problems.append(source + " is not lossless (compress/mode must be 0)")
	if not mipmapped:
		problems.append(source + " has no mipmaps")
	if detect_3d:
		problems.append(source + " could flip to VRAM compression (detect_3d/compress_to)")


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
