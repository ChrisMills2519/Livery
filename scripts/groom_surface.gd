extends Node
class_name GroomSurface

## UV-space grooming state for the horse coat.
##
## A bake once at load classifies every triangle by its dominant bone, groups
## connected UV islands, and rasterises a static groomable mask plus a zone map
## at 256 x 256.  The mask's RGB channels are the live grooming state:
##
##   R  clean / dirt removed
##   G  polished
##   B  curried / loosened
##   A  groomable surface (baked, never changes)
##
## Painting is done directly in the mask bytes and uploaded at a capped rate.
## The picker rebuilds CPU-skinned triangles when a grooming session starts so
## ray hits, brush UVs and the visible pose agree.

signal painted
signal mask_reset
## Emitted once when an anatomical area crosses its clean threshold.  The
## session turns this into the PowerWash-style ding and HUD toast.
signal region_completed(region: int)

## 256 is the sweet spot: the coat mask is a soft, painterly layer, and the
## smaller bake keeps the character-select handoff under a second on a modest
## CPU (512 took several seconds of blocking load).
const MASK_SIZE := 256
const ZONE_NONE := 0
const ZONE_COAT := 1
const ZONE_LEG := 2
const ZONE_FACE := 3
const ZONE_HOOF := 4
const ZONE_MANE := 5
const ZONE_TAIL := 6

## Anatomical areas shown in the HUD and completed one at a time.  The body is
## split into five sections and the legs are tracked separately by side, so a
## session produces a steady stream of dings instead of one global percentage.
enum Region {
	HEAD,
	NECK,
	CHEST,
	BARREL,
	HINDQUARTERS,
	FRONT_L,
	FRONT_R,
	HIND_L,
	HIND_R,
	COUNT,
}
const REGION_NONE := Region.COUNT
const REGION_NAMES := [
	"Head",
	"Neck",
	"Chest / shoulders",
	"Barrel",
	"Hindquarters",
	"Front left leg",
	"Front right leg",
	"Hind left leg",
	"Hind right leg",
]
## A completed area snaps to clean, so the threshold can leave the final
## sliver to the snap instead of making the player hunt it.  The head is small
## and awkward, and the legs have no curry pass, so they get a little slack.
const REGION_CLEAN_THRESHOLDS := [0.78, 0.85, 0.85, 0.85, 0.85, 0.82, 0.82, 0.82, 0.82]

const MIN_ISLAND_VERTICES := 30
## How many candidate triangles are remembered per mask texel.  Mirror-shared
## UVs give a texel two candidates (left + right); the spare slots cover the
## rare overlapping shell.
const PIXEL_TRI_STRIDE := 4
const GroomPickerScript := preload("res://scripts/groom_picker.gd")

const SOFT_MIN_CLEAN := 0.5
const UPLOAD_INTERVAL := 1.0 / 30.0
const HIGHLIGHT_DURATION := 2.2
const HIGHLIGHT_COLORS := {
	"curry": Color(1.0, 0.55, 0.35, 1.0),
	"dandy": Color(1.0, 0.82, 0.38, 1.0),
	"soft": Color(0.62, 0.88, 1.0, 1.0),
	"face": Color(1.0, 0.62, 0.86, 1.0),
	"hoof": Color(1.0, 0.42, 0.24, 1.0),
}

var material: ShaderMaterial
var mask_texture: ImageTexture
var zone_texture: ImageTexture
var picker

var mesh_instance: MeshInstance3D
var skeleton: Skeleton3D
var skin: Skin

var current_dirt_level := 1.0
var last_bake_ms := 0.0
var last_pick_ms := 0.0
var last_paint_ms := 0.0

var _mask_image: Image
var _mask_data := PackedByteArray()
## A mask decoded from a save.  Applied after the bake, because the bake also
## builds the zone map and the paint-gating triangle table that painting needs.
var _imported_data := PackedByteArray()
var _zone_map := PackedByteArray()
var _island_map := PackedInt32Array()
var _pixel_tris := PackedInt32Array()
var _tri_zones := PackedByteArray()
var _tri_islands := PackedInt32Array()
var _tri_regions := PackedByteArray()
var _region_map := PackedByteArray()
var _region_pixels: Array = []
var _region_totals := PackedInt32Array()
var _region_polishable := PackedInt32Array()
var _region_clean_sums := PackedFloat64Array()
var _region_polish_sums := PackedFloat64Array()
var _region_complete := PackedByteArray()
var _rest_vertices := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
var _bind_to_bone := PackedInt32Array()
var _bind_pose: Array = []
var _uf := PackedInt32Array()
var _island_vertex_count := {}
var _zone_counts := {}
var _groomable_count := 0
var _cleanable_count := 0
var _polishable_count := 0
var _dirty := false
var _upload_accum := 0.0
var _ready_done := false
var _groom_uv2 := false
var _highlight_time := 0.0
var _highlight_duration := HIGHLIGHT_DURATION
## Why the last stamp did or did not change anything.  The session turns this
## into a hint, so "nothing happened" must not be reported as "wrong area".
enum PaintStatus {
	NONE,
	PAINTED,
	ALREADY_CLEAN,
	NO_TARGET,
}
var _last_paint_status := PaintStatus.NONE


func _ready() -> void:
	# The bake is cheap at 256, but it still should not sit in the middle of the
	# character-select handoff.  Let the first main-scene frame and the fade
	# settle, then bake while the cover is still clearing.
	_deferred_setup()


func _deferred_setup() -> void:
	await get_tree().create_timer(0.2).timeout
	if is_inside_tree():
		_setup()


func _process(delta: float) -> void:
	_update_highlight(delta)
	if not _dirty:
		return
	_upload_accum += delta
	if _upload_accum < UPLOAD_INTERVAL:
		return
	_upload_accum = 0.0
	flush_texture()


func _update_highlight(delta: float) -> void:
	if _highlight_time <= 0.0 or material == null:
		return
	_highlight_time = maxf(0.0, _highlight_time - delta)
	var elapsed := _highlight_duration - _highlight_time
	var fade_in := clampf(elapsed / 0.12, 0.0, 1.0)
	var fade_out := clampf(_highlight_time / 0.55, 0.0, 1.0)
	material.set_shader_parameter("highlight_strength", minf(fade_in, fade_out))


func _setup() -> void:
	if _ready_done:
		return
	var started := Time.get_ticks_msec()
	var root := get_parent()
	if root == null:
		return
	mesh_instance = _find_skinned_mesh(root)
	skeleton = _find_skeleton(root)
	if mesh_instance == null or skeleton == null:
		push_warning("GroomSurface: could not find the horse skinned mesh or skeleton")
		return
	skin = mesh_instance.skin
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh == null:
		push_warning("GroomSurface: horse mesh is not an ArrayMesh")
		return
	var arrays := mesh.surface_get_arrays(0)
	_rest_vertices = arrays[Mesh.ARRAY_VERTEX]
	# The coat texture uses TEXCOORD_0, whose left and right sides are mirrored
	# and share texels.  A second set (TEXCOORD_1) places the two sides in
	# disjoint halves so the groom mask can clean one side only.  Fall back to
	# the first set on any mesh that has not been re-exported with the split.
	var groom_uvs = arrays[Mesh.ARRAY_TEX_UV2]
	_groom_uv2 = groom_uvs != null and not (groom_uvs as PackedVector2Array).is_empty()
	if not _groom_uv2:
		groom_uvs = arrays[Mesh.ARRAY_TEX_UV]
	var index_array = arrays[Mesh.ARRAY_INDEX]
	if groom_uvs == null or index_array == null:
		push_warning("GroomSurface: horse mesh has no UVs or indices")
		return
	_uvs = groom_uvs
	_indices = index_array
	if _uvs.is_empty() or _indices.is_empty():
		push_warning("GroomSurface: horse mesh has no UVs or indices")
		return
	var bone_array = arrays[Mesh.ARRAY_BONES]
	var weight_array = arrays[Mesh.ARRAY_WEIGHTS]
	if bone_array != null and weight_array != null and not bone_array.is_empty():
		_bones = bone_array
		_weights = weight_array
	if skin != null:
		_build_bind_map()
	_build_islands()
	_build_triangles()
	_rasterise_mask()
	# A coat restored from a save wins over the bake, which would otherwise put
	# the horse back to dirty.  The bake still has to run first: it is what
	# builds the zone map and the paint-gating triangle table.
	if _imported_data.size() == MASK_SIZE * MASK_SIZE * 4:
		_mask_data = _imported_data.duplicate()
	_build_material()
	_ready_done = true
	last_bake_ms = float(Time.get_ticks_msec() - started)


func _find_skinned_mesh(root: Node) -> MeshInstance3D:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi != null and mi.skin != null and mi.mesh is ArrayMesh:
			return mi
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	for child in root.find_children("*", "Skeleton3D", true, false):
		return child as Skeleton3D
	return null


func _build_bind_map() -> void:
	var bind_count := skin.get_bind_count()
	_bind_to_bone.resize(bind_count)
	_bind_pose.resize(bind_count)
	for i in range(bind_count):
		var bind_name := skin.get_bind_name(i)
		_bind_to_bone[i] = skeleton.find_bone(bind_name)
		# Godot stores the inverse bind matrix here (it maps skeleton space
		# back into the bone's bind space), so it is applied directly.
		_bind_pose[i] = skin.get_bind_pose(i)


func _zone_for_bone(bone_name: String) -> int:
	# Lower-case so the classifier works on both the old Bip01 names and the
	# newer rig's front_leg_* / back_leg_* names.
	var n := bone_name.to_lower()
	if n.contains("toe") or n.contains("finger") or n.contains("leg_foot"):
		return ZONE_HOOF
	if n.contains("ponytail"):
		return ZONE_MANE
	if n.contains("tail"):
		return ZONE_TAIL
	if n.contains("head") or n.contains("nose") or n.contains("mouth") or n.contains("ear"):
		return ZONE_FACE
	# The leg rule has to name the leg bones outright.  A bare "front_" also
	# caught "ribcage_front", which put the chest and belly in the leg zone.
	if (
		n.contains("upperarm") or n.contains("forearm") or n.contains("hand")
		or n.contains("thigh") or n.contains("calf") or n.contains("foot")
		or n.contains("horselink") or n.contains("humerus") or n.contains("scapula")
		or n.contains("front_leg") or n.contains("front_scapula") or n.contains("front_humerus")
		or n.contains("back_leg_")
	):
		return ZONE_LEG
	return ZONE_COAT


## The nine areas the HUD tracks one at a time.  The head, neck, chest,
## barrel and hindquarters come from the spine chain and the shoulders; the
## four legs are split by the _l / _r suffix on their bones.
func _region_for_bone(bone_name: String) -> int:
	var n := bone_name.to_lower()
	if n.begins_with("ear_") or n in ["head", "head_leaf", "nose", "mouth", "mouth_tip"]:
		return Region.HEAD
	if n in ["spine_4", "spine_5", "spine_6"]:
		return Region.NECK
	if n.begins_with("ribcage_front") or n.begins_with("front_scapula") or n.begins_with("front_humerus"):
		return Region.CHEST
	if (
		n == "root" or n == "hips" or n.begins_with("spine_1") or n.begins_with("spine_2")
		or n.begins_with("spine_3") or n.begins_with("ribcage_middle") or n.begins_with("ribcage_leaf")
	):
		return Region.BARREL
	if n.begins_with("tail") or n.begins_with("back_leg_pelvis"):
		return Region.HINDQUARTERS
	if n.begins_with("front_leg"):
		return Region.FRONT_R if n.ends_with("_r") else Region.FRONT_L
	if n.begins_with("back_leg"):
		return Region.HIND_R if n.ends_with("_r") else Region.HIND_L
	return Region.BARREL


func _build_islands() -> void:
	var count := _rest_vertices.size()
	_uf.resize(count)
	for i in range(count):
		_uf[i] = i
	for t in range(_indices.size() / 3):
		var a := _indices[t * 3]
		var b := _indices[t * 3 + 1]
		var c := _indices[t * 3 + 2]
		_uf_union(a, b)
		_uf_union(b, c)
	_island_vertex_count.clear()
	for i in range(count):
		var root := _uf_find(i)
		_island_vertex_count[root] = int(_island_vertex_count.get(root, 0)) + 1


func _uf_find(x: int) -> int:
	var root := x
	while _uf[root] != root:
		root = _uf[root]
	var current := x
	while _uf[current] != current:
		var next := _uf[current]
		_uf[current] = root
		current = next
	return root


func _uf_union(a: int, b: int) -> void:
	var ra := _uf_find(a)
	var rb := _uf_find(b)
	if ra != rb:
		_uf[rb] = ra


func _build_triangles() -> void:
	var tri_count := _indices.size() / 3
	_tri_zones.resize(tri_count)
	_tri_islands.resize(tri_count)
	_tri_regions.resize(tri_count)
	_zone_counts.clear()
	for t in range(tri_count):
		var i0 := _indices[t * 3]
		var i1 := _indices[t * 3 + 1]
		var i2 := _indices[t * 3 + 2]
		var zone_weights := {}
		var region_weights := {}
		for vertex_index in [i0, i1, i2]:
			for k in range(4):
				var array_index: int = int(vertex_index) * 4 + k
				if array_index >= _bones.size() or array_index >= _weights.size():
					continue
				var weight := _weights[array_index]
				if weight <= 0.001:
					continue
				var bind := _bones[array_index]
				if bind < 0 or bind >= skin.get_bind_count():
					continue
				var bind_name := String(skin.get_bind_name(bind))
				var zone := _zone_for_bone(bind_name)
				zone_weights[zone] = float(zone_weights.get(zone, 0.0)) + weight
				var region := _region_for_bone(bind_name)
				region_weights[region] = float(region_weights.get(region, 0.0)) + weight
		var dominant := ZONE_COAT
		var best := -1.0
		for zone in zone_weights.keys():
			var value: float = zone_weights[zone]
			if value > best:
				best = value
				dominant = int(zone)
		_tri_zones[t] = dominant
		_tri_islands[t] = _uf_find(i0)
		var dominant_region := Region.BARREL
		var best_region := -1.0
		for region in region_weights.keys():
			var value: float = region_weights[region]
			if value > best_region:
				best_region = value
				dominant_region = int(region)
		_tri_regions[t] = dominant_region
		_zone_counts[dominant] = int(_zone_counts.get(dominant, 0)) + 1
	picker = GroomPickerScript.new()
	picker.setup(_rest_vertices, _uvs, _indices, _tri_zones, _tri_islands)


func _rasterise_mask() -> void:
	var pixels := MASK_SIZE * MASK_SIZE
	_mask_data.resize(pixels * 4)
	_mask_data.fill(0)
	_zone_map.resize(pixels)
	_zone_map.fill(ZONE_NONE)
	_region_map.resize(pixels)
	_region_map.fill(REGION_NONE)
	_island_map.resize(pixels)
	for i in range(pixels):
		_island_map[i] = -1
	_pixel_tris.resize(pixels * PIXEL_TRI_STRIDE)
	for i in range(pixels * PIXEL_TRI_STRIDE):
		_pixel_tris[i] = -1
	_groomable_count = 0
	_cleanable_count = 0
	_polishable_count = 0
	var tri_count := _indices.size() / 3
	for t in range(tri_count):
		var zone := int(_tri_zones[t])
		var island := int(_tri_islands[t])
		var island_vertices := int(_island_vertex_count.get(island, 0))
		var groomable := zone >= ZONE_COAT and zone <= ZONE_FACE and island_vertices >= MIN_ISLAND_VERTICES
		var i0 := _indices[t * 3]
		var i1 := _indices[t * 3 + 1]
		var i2 := _indices[t * 3 + 2]
		var uv0 := _uvs[i0]
		var uv1 := _uvs[i1]
		var uv2 := _uvs[i2]
		if _uv_outside(uv0) or _uv_outside(uv1) or _uv_outside(uv2):
			continue
		var min_u := minf(minf(uv0.x, uv1.x), uv2.x)
		var max_u := maxf(maxf(uv0.x, uv1.x), uv2.x)
		var min_v := minf(minf(uv0.y, uv1.y), uv2.y)
		var max_v := maxf(maxf(uv0.y, uv1.y), uv2.y)
		var x0 := clampi(int(floor(min_u * MASK_SIZE)) - 1, 0, MASK_SIZE - 1)
		var x1 := clampi(int(ceil(max_u * MASK_SIZE)) + 1, 0, MASK_SIZE - 1)
		var y0 := clampi(int(floor(min_v * MASK_SIZE)) - 1, 0, MASK_SIZE - 1)
		var y1 := clampi(int(ceil(max_v * MASK_SIZE)) + 1, 0, MASK_SIZE - 1)
		var denom := (uv1.y - uv2.y) * (uv0.x - uv2.x) + (uv2.x - uv1.x) * (uv0.y - uv2.y)
		if absf(denom) < 0.0000000001:
			continue
		for py in range(y0, y1 + 1):
			var v := (float(py) + 0.5) / float(MASK_SIZE)
			for px in range(x0, x1 + 1):
				var u := (float(px) + 0.5) / float(MASK_SIZE)
				var w0 := ((uv1.y - uv2.y) * (u - uv2.x) + (uv2.x - uv1.x) * (v - uv2.y)) / denom
				if w0 < -0.001:
					continue
				var w1 := ((uv2.y - uv0.y) * (u - uv2.x) + (uv0.x - uv2.x) * (v - uv2.y)) / denom
				if w1 < -0.001:
					continue
				var w2 := 1.0 - w0 - w1
				if w2 < -0.001:
					continue
				var pixel := py * MASK_SIZE + px
				_zone_map[pixel] = zone
				_region_map[pixel] = int(_tri_regions[t])
				_island_map[pixel] = island
				_record_pixel_tri(pixel, t)
				if groomable:
					var alpha_index := pixel * 4 + 3
					if _mask_data[alpha_index] == 0:
						_mask_data[alpha_index] = 255
						_groomable_count += 1
	# A seam pixel can be claimed by two islands.  Keep alpha only where the
	# final zone is actually paintable.
	for pixel in range(pixels):
		if _mask_data[pixel * 4 + 3] == 0:
			continue
		var zone := int(_zone_map[pixel])
		if zone < ZONE_COAT or zone > ZONE_FACE:
			_mask_data[pixel * 4 + 3] = 0
			_groomable_count -= 1
			continue
		if zone == ZONE_FACE or zone == ZONE_LEG or zone == ZONE_COAT:
			_cleanable_count += 1
		if zone == ZONE_COAT or zone == ZONE_LEG:
			_polishable_count += 1
	_build_region_stats()


## Collect the groomable texels of every anatomical area.  The HUD shows one
## row per area, so each region needs its own texel list, its own clean and
## polish sums, and the threshold it has to reach to count as done.
func _build_region_stats() -> void:
	_region_pixels.clear()
	_region_totals.resize(Region.COUNT)
	_region_totals.fill(0)
	_region_polishable.resize(Region.COUNT)
	_region_polishable.fill(0)
	_region_clean_sums.resize(Region.COUNT)
	_region_clean_sums.fill(0.0)
	_region_polish_sums.resize(Region.COUNT)
	_region_polish_sums.fill(0.0)
	_region_complete.resize(Region.COUNT)
	_region_complete.fill(0)
	for i in range(Region.COUNT):
		_region_pixels.append(PackedInt32Array())
	for pixel in range(MASK_SIZE * MASK_SIZE):
		if _mask_data[pixel * 4 + 3] == 0:
			continue
		var region := int(_region_map[pixel])
		if region < 0 or region >= Region.COUNT:
			continue
		var list: PackedInt32Array = _region_pixels[region]
		list.append(pixel)
		_region_pixels[region] = list
		_region_totals[region] += 1
		var zone := int(_zone_map[pixel])
		if zone == ZONE_COAT or zone == ZONE_LEG:
			_region_polishable[region] += 1


func _record_pixel_tri(pixel: int, triangle: int) -> void:
	var base := pixel * PIXEL_TRI_STRIDE
	for slot in range(PIXEL_TRI_STRIDE):
		var existing := _pixel_tris[base + slot]
		if existing == triangle:
			return
		if existing == -1:
			_pixel_tris[base + slot] = triangle
			return


## A texel may be painted when at least one of the triangles that maps onto it
## is under the brush.  This is what stops a stamp from bleeding onto a texel
## that only belongs to a far part of the coat sharing the same atlas space.
func _pixel_tri_allowed(pixel: int, allowed: PackedByteArray) -> bool:
	if allowed.is_empty():
		return true
	var base := pixel * PIXEL_TRI_STRIDE
	for slot in range(PIXEL_TRI_STRIDE):
		var triangle := _pixel_tris[base + slot]
		if triangle < 0:
			return false
		if triangle < allowed.size() and allowed[triangle] != 0:
			return true
	return false


func _uv_outside(uv: Vector2) -> bool:
	return uv.x < -0.01 or uv.x > 1.01 or uv.y < -0.01 or uv.y > 1.01


func _build_material() -> void:
	var base := load("res://resources/materials/horse_groom.tres") as ShaderMaterial
	if base == null:
		push_warning("GroomSurface: horse groom material missing")
		return
	material = base.duplicate() as ShaderMaterial
	_mask_image = Image.create_from_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8, _mask_data)
	mask_texture = ImageTexture.create_from_image(_mask_image)
	material.set_shader_parameter("groom_mask", mask_texture)
	var zone_image := Image.create_from_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_R8, _zone_map)
	zone_texture = ImageTexture.create_from_image(zone_image)
	material.set_shader_parameter("zone_map", zone_texture)
	material.set_shader_parameter("use_uv2", 1.0 if _groom_uv2 else 0.0)
	material.set_shader_parameter("dirt_level", current_dirt_level)
	material.set_shader_parameter("mask_view", 0.0)
	material.set_shader_parameter("highlight_mask", 0)
	material.set_shader_parameter("highlight_strength", 0.0)
	material.set_shader_parameter("highlight_clean_soften", 0.0)
	mesh_instance.material_override = material


func rebuild_picker() -> void:
	if picker == null or skeleton == null:
		return
	skeleton.force_update_all_bone_transforms()
	var count := _rest_vertices.size()
	var skinned := PackedVector3Array()
	skinned.resize(count)
	for i in range(count):
		var rest := _rest_vertices[i]
		if _bones.size() < count * 4 or _weights.size() < count * 4:
			skinned[i] = rest
			continue
		var accumulated := Vector3.ZERO
		var total := 0.0
		for k in range(4):
			var weight := _weights[i * 4 + k]
			if weight <= 0.0001:
				continue
			var bind := _bones[i * 4 + k]
			if bind < 0 or bind >= _bind_to_bone.size():
				continue
			var bone := _bind_to_bone[bind]
			if bone < 0:
				continue
			var bone_pose := skeleton.get_bone_global_pose(bone)
			accumulated += (bone_pose * _bind_pose[bind] * rest) * weight
			total += weight
		if total > 0.0001:
			skinned[i] = accumulated / total
		else:
			skinned[i] = rest
	picker.rebuild(skinned)


func prepare_for_grooming() -> void:
	if not _ready_done:
		_setup()
	rebuild_picker()
	flush_texture()


func pick_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	if picker == null or skeleton == null:
		return {}
	var started := Time.get_ticks_usec()
	var inverse := skeleton.global_transform.affine_inverse()
	var local_origin := inverse * origin
	var local_direction := skeleton.global_transform.basis.inverse() * direction
	var hit: Dictionary = picker.pick(local_origin, local_direction)
	last_pick_ms = float(Time.get_ticks_usec() - started) / 1000.0
	if hit.is_empty():
		return hit
	# Keep the picker's raw skeleton-local hit so the painter can measure the
	# brush's world reach against the posed triangles.
	hit["local_position"] = hit["position"]
	hit["position"] = skeleton.global_transform * hit["position"]
	hit["normal"] = (skeleton.global_transform.basis * hit["normal"]).normalized()
	return hit


func paint_hit(hit: Dictionary, tool: String) -> Dictionary:
	if hit.is_empty():
		return {"ok": false, "reason": "miss"}
	var zone := int(hit.get("zone", ZONE_NONE))
	# Hooves are not brushed at all, so every tool has to say so plainly
	# instead of blaming the face.
	if zone == ZONE_HOOF:
		return {"ok": false, "reason": "hoof", "zone": zone}
	if tool == "hoof":
		return {"ok": false, "reason": "zone", "zone": zone}
	if not _tool_allows_zone(tool, zone):
		return {"ok": false, "reason": "zone", "zone": zone}
	var uv: Vector2 = hit.get("uv", Vector2.ZERO)
	if tool == "soft" and get_mask_value(uv, "clean") < SOFT_MIN_CLEAN:
		return {"ok": false, "reason": "dirty", "zone": zone}
	var uv_per_meter := float(hit.get("uv_per_meter", 100.0))
	var radius_world := brush_world_radius(tool)
	# The coat atlas is split into narrow shells and mirrored left/right, so a
	# strict UV-space circle only covers the shell under the cursor.  The UV
	# boost reaches the neighbouring shells of the same zone; the world-space
	# triangle gate below then keeps the stamp from bleeding onto a far region
	# that happens to share the atlas (belly -> croup, say), making the visible
	# ring the true footprint.
	var radius_uv := radius_world * uv_per_meter * 2.2
	var allowed := PackedByteArray()
	if picker != null and hit.has("local_position"):
		allowed = picker.triangles_within(hit["local_position"], radius_world)
	var painted_ok := paint_uv(uv, zone, tool, radius_uv, allowed)
	if painted_ok:
		return {"ok": true, "reason": "ok", "zone": zone}
	var reason := "zone"
	if _last_paint_status == PaintStatus.ALREADY_CLEAN:
		reason = "clean"
	elif _last_paint_status == PaintStatus.NO_TARGET:
		reason = "seam"
	return {"ok": false, "reason": reason, "zone": zone}


## Painting is guarded by the baked groomable alpha, the zone map and the
## world-space triangle set under the brush.  The UV island is deliberately not
## used as a brush limit: this horse's coat is split into many small UV shells,
## and restricting a stamp to the shell under the cursor made the brush feel
## like a pinprick.  Zone + alpha keep the face brush off the body and the body
## tools off the face; `allowed` (from GroomPicker.triangles_within) keeps a
## stamp from reaching a far region that shares the same atlas.
func paint_uv(uv: Vector2, zone: int, tool: String, radius_uv: float, allowed: PackedByteArray = PackedByteArray()) -> bool:
	_last_paint_status = PaintStatus.NONE
	if not _tool_allows_zone(tool, zone):
		return false
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return false
	var started := Time.get_ticks_usec()
	var centre_x := int(uv.x * MASK_SIZE)
	var centre_y := int(uv.y * MASK_SIZE)
	var radius_px := maxf(2.0, radius_uv * MASK_SIZE)
	var min_x := clampi(int(floor(centre_x - radius_px)), 0, MASK_SIZE - 1)
	var max_x := clampi(int(ceil(centre_x + radius_px)), 0, MASK_SIZE - 1)
	var min_y := clampi(int(floor(centre_y - radius_px)), 0, MASK_SIZE - 1)
	var max_y := clampi(int(ceil(centre_y + radius_px)), 0, MASK_SIZE - 1)
	var did_paint := false
	var touched := false
	for py in range(min_y, max_y + 1):
		var dy := float(py) - centre_y
		for px in range(min_x, max_x + 1):
			var dx := float(px) - centre_x
			var distance := sqrt(dx * dx + dy * dy) / radius_px
			if distance > 1.0:
				continue
			var pixel := py * MASK_SIZE + px
			if _mask_data[pixel * 4 + 3] == 0:
				continue
			if int(_zone_map[pixel]) != zone:
				continue
			if not _pixel_tri_allowed(pixel, allowed):
				continue
			touched = true
			var base := pixel * 4
			var clean := float(_mask_data[base]) / 255.0
			var polish := float(_mask_data[base + 1]) / 255.0
			var loosen := float(_mask_data[base + 2]) / 255.0
			var falloff := pow(1.0 - distance, 1.45)
			match tool:
				"curry":
					loosen = maxf(loosen, falloff * 0.95)
					_mask_data[base + 2] = int(round(loosen * 255.0))
					did_paint = true
				"dandy", "face":
					if tool == "face" and zone != ZONE_FACE:
						continue
					# Currying loosens the dirt, so a curried patch comes off
					# far better.  The floor keeps a missed curry pass from
					# leaving an area permanently stuck at a trace of clean.
					var gain := falloff * (0.55 + 0.45 * loosen)
					if tool == "face":
						# The head has no curry step, so the face brush has to
						# be able to clean it on its own.
						gain = falloff
					var new_clean := maxf(clean, gain)
					if new_clean > clean + 0.0005:
						_mask_data[base] = int(round(new_clean * 255.0))
						_region_clean_changed(pixel, clean, new_clean)
						did_paint = true
				"soft":
					if clean < SOFT_MIN_CLEAN:
						continue
					var new_polish := maxf(polish, falloff * (0.35 + 0.65 * clean))
					if new_polish > polish + 0.0005:
						_mask_data[base + 1] = int(round(new_polish * 255.0))
						_region_polish_changed(pixel, polish, new_polish)
						did_paint = true
	if did_paint:
		_last_paint_status = PaintStatus.PAINTED
	elif touched:
		_last_paint_status = PaintStatus.ALREADY_CLEAN
	else:
		_last_paint_status = PaintStatus.NO_TARGET
	if did_paint:
		_dirty = true

		last_paint_ms = float(Time.get_ticks_usec() - started) / 1000.0
		painted.emit()
	return did_paint


## Public read-only wrapper so the session can tint the cursor ring by whether
## the active tool may paint the zone under the pointer.
func can_tool_paint(tool: String, zone: int) -> bool:
	return _tool_allows_zone(tool, zone)


func _tool_allows_zone(tool: String, zone: int) -> bool:
	match tool:
		"curry":
			# The legs carry the same dirt as the body, and the dandy brush
			# works far better on curried coat, so the comb has to reach them
			# too.  Without this the legs could never be properly cleaned.
			return zone == ZONE_COAT or zone == ZONE_LEG
		"dandy":
			return zone == ZONE_COAT or zone == ZONE_LEG
		"soft":
			return zone == ZONE_COAT or zone == ZONE_LEG
		"face":
			return zone == ZONE_FACE
		"hoof":
			return zone == ZONE_HOOF
	return false


## Per-area progress.  The HUD shows one row per area and the session turns a
## finished area into a ding, so the sums are kept live while the mask is
## painted rather than recomputed from the whole atlas every frame.
func _region_of_pixel(pixel: int) -> int:
	if pixel < 0 or pixel >= _region_map.size():
		return REGION_NONE
	return int(_region_map[pixel])


func _region_clean_changed(pixel: int, old_value: float, new_value: float) -> void:
	var region := _region_of_pixel(pixel)
	if region < 0 or region >= Region.COUNT:
		return
	_region_clean_sums[region] += new_value - old_value
	_check_region_complete(region)


func _region_polish_changed(pixel: int, old_value: float, new_value: float) -> void:
	var region := _region_of_pixel(pixel)
	if region < 0 or region >= Region.COUNT:
		return
	_region_polish_sums[region] += new_value - old_value


func _check_region_complete(region: int) -> void:
	if _region_complete[region] != 0:
		return
	var total := int(_region_totals[region])
	if total <= 0:
		return
	var ratio := float(_region_clean_sums[region]) / float(total)
	if ratio < float(REGION_CLEAN_THRESHOLDS[region]):
		return
	_region_complete[region] = 1
	region_completed.emit(region)


## Recompute the per-area sums from the mask itself.  Used after a reset or a
## bulk fill, where the incremental updates do not apply.
func _recompute_region_sums() -> void:
	_region_clean_sums.resize(Region.COUNT)
	_region_clean_sums.fill(0.0)
	_region_polish_sums.resize(Region.COUNT)
	_region_polish_sums.fill(0.0)
	_region_complete.resize(Region.COUNT)
	_region_complete.fill(0)
	for region in range(Region.COUNT):
		var list: PackedInt32Array = _region_pixels[region] if region < _region_pixels.size() else PackedInt32Array()
		var clean_sum := 0.0
		var polish_sum := 0.0
		for pixel in list:
			clean_sum += float(_mask_data[pixel * 4]) / 255.0
			polish_sum += float(_mask_data[pixel * 4 + 1]) / 255.0
		_region_clean_sums[region] = clean_sum
		_region_polish_sums[region] = polish_sum
	for region in range(Region.COUNT):
		_check_region_complete(region)


## One entry per anatomical area: how clean it is, how shiny, and whether it
## has crossed its threshold.
func region_coverage() -> Array:
	var out: Array = []
	for region in range(Region.COUNT):
		var total := int(_region_totals[region]) if region < _region_totals.size() else 0
		var polishable := int(_region_polishable[region]) if region < _region_polishable.size() else 0
		var clean := 0.0
		var polish := 0.0
		if total > 0:
			clean = float(_region_clean_sums[region]) / float(total)
		if polishable > 0:
			polish = float(_region_polish_sums[region]) / float(polishable)
		out.append({
			"id": region,
			"name": String(REGION_NAMES[region]),
			"clean": clean,
			"polish": polish,
			"texels": total,
			"complete": int(_region_complete[region]) != 0,
			"threshold": float(REGION_CLEAN_THRESHOLDS[region]),
		})
	return out


func brush_world_radius(tool: String) -> float:
	match tool:
		"curry":
			return 0.13
		"dandy":
			return 0.145
		"soft":
			return 0.145
		"face":
			return 0.06
		"hoof":
			return 0.05
	return 0.12


func get_mask_value(uv: Vector2, channel: String) -> float:
	if _mask_data.is_empty():
		return 0.0
	var px := clampi(int(uv.x * MASK_SIZE), 0, MASK_SIZE - 1)
	var py := clampi(int(uv.y * MASK_SIZE), 0, MASK_SIZE - 1)
	var base := (py * MASK_SIZE + px) * 4
	if _mask_data[base + 3] == 0:
		return 0.0
	match channel:
		"clean":
			return float(_mask_data[base]) / 255.0
		"polish":
			return float(_mask_data[base + 1]) / 255.0
		"loosen":
			return float(_mask_data[base + 2]) / 255.0
		"groomable":
			return 1.0
	return 0.0


func get_zone_at_uv(uv: Vector2) -> int:
	if _zone_map.is_empty():
		return ZONE_NONE
	var px := clampi(int(uv.x * MASK_SIZE), 0, MASK_SIZE - 1)
	var py := clampi(int(uv.y * MASK_SIZE), 0, MASK_SIZE - 1)
	return int(_zone_map[py * MASK_SIZE + px])


func coverage() -> Dictionary:
	if _mask_data.is_empty():
		return {"clean": 0.0, "polish": 0.0}
	var clean_sum := 0.0
	var polish_sum := 0.0
	var clean_count := 0
	var polish_count := 0
	for py in range(0, MASK_SIZE, 2):
		for px in range(0, MASK_SIZE, 2):
			var pixel := py * MASK_SIZE + px
			if _mask_data[pixel * 4 + 3] == 0:
				continue
			var zone := int(_zone_map[pixel])
			if zone >= ZONE_COAT and zone <= ZONE_FACE:
				clean_sum += float(_mask_data[pixel * 4]) / 255.0
				clean_count += 1
			if zone == ZONE_COAT or zone == ZONE_LEG:
				polish_sum += float(_mask_data[pixel * 4 + 1]) / 255.0
				polish_count += 1
	var clean_ratio := 0.0
	var polish_ratio := 0.0
	if clean_count > 0:
		clean_ratio = clean_sum / float(clean_count)
	if polish_count > 0:
		polish_ratio = polish_sum / float(polish_count)
	return {"clean": clean_ratio, "polish": polish_ratio, "clean_pixels": clean_count, "polish_pixels": polish_count}


func flush_texture() -> void:
	if _mask_image == null or mask_texture == null:
		return
	_mask_image.set_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8, _mask_data)
	mask_texture.update(_mask_image)
	_dirty = false


const BASE64_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="


func _looks_like_base64(text: String) -> bool:
	if text.length() < 8 or text.length() % 4 != 0:
		return false
	for i in range(text.length()):
		if BASE64_CHARS.find(text[i]) == -1:
			return false
	return true


## Base64 PNG of the painted coat, for the save.  Empty before the bake, which
## happens 0.2 s after the horse loads.
func export_mask() -> String:
	if _mask_data.size() != MASK_SIZE * MASK_SIZE * 4:
		return ""
	var image := Image.create_from_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8, _mask_data)
	return Marshalls.raw_to_base64(image.save_png_to_buffer())


## Restores a coat painted on an earlier visit.  Anything that is not a 256x256
## PNG is refused, so a damaged save leaves the horse as it was rather than
## blanking the coat.
func import_mask(encoded: String) -> bool:
	if encoded.is_empty():
		return false
	# Checked before the decoder: Marshalls.base64_to_raw logs an engine ERROR on
	# malformed input, which reads as a failure in an otherwise clean log.
	if not _looks_like_base64(encoded):
		return false
	var png := Marshalls.base64_to_raw(encoded)
	if png.is_empty():
		return false
	var image := Image.new()
	if image.load_png_from_buffer(png) != OK:
		return false
	if image.get_width() != MASK_SIZE or image.get_height() != MASK_SIZE:
		return false
	image.convert(Image.FORMAT_RGBA8)
	var decoded := image.get_data()
	if decoded.size() != MASK_SIZE * MASK_SIZE * 4:
		return false
	_imported_data = decoded
	# Before the bake there is nothing to upload yet; _setup() applies it between
	# the rasterise and the material build.
	if _ready_done:
		_mask_data = _imported_data.duplicate()
		_mask_image = Image.create_from_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8, _mask_data)
		mask_texture = ImageTexture.create_from_image(_mask_image)
		if material != null:
			material.set_shader_parameter("groom_mask", mask_texture)
		_dirty = false
	return true


func reset_mask() -> void:
	if _mask_data.is_empty():
		return
	for pixel in range(MASK_SIZE * MASK_SIZE):
		var base := pixel * 4
		_mask_data[base] = 0
		_mask_data[base + 1] = 0
		_mask_data[base + 2] = 0
	_recompute_region_sums()
	_dirty = true
	flush_texture()
	mask_reset.emit()


func debug_fill(clean: float, polish: float) -> void:
	if _mask_data.is_empty():
		return
	var clean_byte := int(round(clampf(clean, 0.0, 1.0) * 255.0))
	var polish_byte := int(round(clampf(polish, 0.0, 1.0) * 255.0))
	for pixel in range(MASK_SIZE * MASK_SIZE):
		if _mask_data[pixel * 4 + 3] == 0:
			continue
		var zone := int(_zone_map[pixel])
		if zone < ZONE_COAT or zone > ZONE_FACE:
			continue
		_mask_data[pixel * 4] = clean_byte
		_mask_data[pixel * 4 + 2] = 0
		if zone == ZONE_COAT or zone == ZONE_LEG:
			_mask_data[pixel * 4 + 1] = polish_byte
	_recompute_region_sums()
	_dirty = true
	flush_texture()


func find_uv_for_zone(zone: int) -> Vector2:
	for pixel in range(MASK_SIZE * MASK_SIZE):
		if int(_zone_map[pixel]) != zone:
			continue
		# Skip texels that are not groomable, so a caller always gets a spot
		# the brush can actually work on.
		if _mask_data[pixel * 4 + 3] == 0:
			continue
		var x := pixel % MASK_SIZE
		var y := pixel / MASK_SIZE
		return Vector2((float(x) + 0.5) / MASK_SIZE, (float(y) + 0.5) / MASK_SIZE)
	return Vector2(-1, -1)


func set_dirt_level(value: float) -> void:
	current_dirt_level = clampf(value, 0.0, 1.0)
	if material != null:
		material.set_shader_parameter("dirt_level", current_dirt_level)


func set_mask_view(enabled: bool) -> void:
	if material != null:
		material.set_shader_parameter("mask_view", 1.0 if enabled else 0.0)
	if enabled:
		clear_tool_highlight()


## Flash the body areas the given tool can work on.  Hoof picking is handled by
## the session's mud clumps, so it clears any body glow instead of tinting the
## hooves.
func highlight_tool(tool: String, seconds := HIGHLIGHT_DURATION) -> bool:
	if material == null:
		return false
	var mask := 0
	match tool:
		"curry", "dandy", "soft":
			mask = (1 << ZONE_COAT) | (1 << ZONE_LEG)
		"face":
			mask = 1 << ZONE_FACE
		"hoof":
			mask = 0
		_:
			return false
	material.set_shader_parameter("highlight_color", HIGHLIGHT_COLORS.get(tool, Color.WHITE))
	material.set_shader_parameter("highlight_mask", mask)
	material.set_shader_parameter("highlight_clean_soften", 1.0 if tool == "soft" else 0.0)
	_highlight_duration = maxf(0.1, seconds)
	_highlight_time = 0.0 if mask == 0 else _highlight_duration
	material.set_shader_parameter("highlight_strength", 0.0)
	return true


func clear_tool_highlight() -> void:
	_highlight_time = 0.0
	if material != null:
		material.set_shader_parameter("highlight_strength", 0.0)


func get_highlight_mask() -> int:
	if material == null:
		return 0
	return int(material.get_shader_parameter("highlight_mask"))


func get_zone_counts() -> Dictionary:
	return _zone_counts.duplicate()


func get_groomable_count() -> int:
	return _groomable_count


func get_cleanable_count() -> int:
	return _cleanable_count


func get_polishable_count() -> int:
	return _polishable_count
