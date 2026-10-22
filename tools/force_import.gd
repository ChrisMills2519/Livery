extends SceneTree

## Build a GLB's imported scene directly, bypassing the broken headless importer.
##
##   godot --headless --path . --script res://tools/force_import.gd -- \
##       --src res://Models/horse2.glb
##
## The destination defaults to the .import remap path for the source
## (.godot/imported/<file>-<md5 of the res path>.scn), which is what Godot
## looks up when a scene references the GLB.  GLTFDocument leaves skin bind
## names empty, so they are filled from the skeleton before packing; the groom
## zone classifier needs those names.

const DEFAULT_SRC := "res://Models/horse_riggedgame_ready_clips.glb"


func _first(root: Node, type: String) -> Node:
	var found := root.find_children("*", type, true, false)
	return found[0] if not found.is_empty() else null


func _initialize() -> void:
	var src := DEFAULT_SRC
	var dst := ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--src" and i + 1 < args.size():
			src = args[i + 1]
		elif args[i] == "--dst" and i + 1 < args.size():
			dst = args[i + 1]
	if dst == "":
		dst = "res://.godot/imported/%s-%s.scn" % [src.get_file(), src.md5_text()]
	print("source=", src)
	print("dest=", dst)

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(src, state)
	print("append err=", err)
	if err != OK:
		quit(1)
		return
	var scene := doc.generate_scene(state)
	var skel := _first(scene, "Skeleton3D") as Skeleton3D
	print("skeleton=", skel, " bones=", (skel.get_bone_count() if skel != null else -1))
	var fixed := 0
	for c in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.skin == null:
			continue
		var sk := mi.skin
		for i in range(sk.get_bind_count()):
			if sk.get_bind_name(i) == "" and skel != null and i < skel.get_bone_count():
				sk.set_bind_name(i, skel.get_bone_name(i))
				fixed += 1
	print("bind names fixed=", fixed)
	var ps := PackedScene.new()
	ps.pack(scene)
	var serr := ResourceSaver.save(ps, dst)
	print("save err=", serr, " exists=", FileAccess.file_exists(dst))
	var md5_path := dst.trim_suffix(".scn") + ".md5"
	var f := FileAccess.open(md5_path, FileAccess.WRITE)
	f.store_line('source_md5="%s"' % FileAccess.get_md5(src))
	f.store_line('dest_md5="%s"' % FileAccess.get_md5(dst))
	f.close()
	quit()
