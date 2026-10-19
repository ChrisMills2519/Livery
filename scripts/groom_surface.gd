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

const MIN_ISLAND_VERTICES := 30
const GroomPickerScript := preload("res://scripts/groom_picker.gd")

const SOFT_MIN_CLEAN := 0.5
const UPLOAD_INTERVAL := 1.0 / 30.0

var material: ShaderMaterial
var mask_texture: ImageTexture
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
var _zone_map := PackedByteArray()
var _island_map := PackedInt32Array()
var _tri_zones := PackedByteArray()
var _tri_islands := PackedInt32Array()
var _rest_vertices := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
var _bind_to_bone := PackedInt32Array()
var _bind_inv: Array = []
var _uf := PackedInt32Array()
var _island_vertex_count := {}
var _zone_counts := {}
var _groomable_count := 0
var _cleanable_count := 0
var _polishable_count := 0
var _dirty := false
var _upload_accum := 0.0
var _ready_done := false


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
	if not _dirty:
		return
	_upload_accum += delta
	if _upload_accum < UPLOAD_INTERVAL:
		return
	_upload_accum = 0.0
	flush_texture()


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
	var uv_array = arrays[Mesh.ARRAY_TEX_UV]
	var index_array = arrays[Mesh.ARRAY_INDEX]
	if uv_array == null or index_array == null:
		push_warning("GroomSurface: horse mesh has no UVs or indices")
		return
	_uvs = uv_array
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
	_bind_inv.resize(bind_count)
	for i in range(bind_count):
		var bind_name := skin.get_bind_name(i)
		_bind_to_bone[i] = skeleton.find_bone(bind_name)
		_bind_inv[i] = skin.get_bind_pose(i).affine_inverse()


func _zone_for_bone(bone_name: String) -> int:
	var n := bone_name
	if n.contains("Toe") or n.contains("Finger"):
		return ZONE_HOOF
	if n.contains("Ponytail"):
		return ZONE_MANE
	if n.contains("Tail"):
		return ZONE_TAIL
	if n.contains("Head"):
		return ZONE_FACE
	if n.contains("UpperArm") or n.contains("Forearm") or n.contains("Hand"):
		return ZONE_LEG
	if n.contains("Thigh") or n.contains("Calf") or n.contains("Foot") or n.contains("HorseLink"):
		return ZONE_LEG
	return ZONE_COAT


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
	_zone_counts.clear()
	for t in range(tri_count):
		var i0 := _indices[t * 3]
		var i1 := _indices[t * 3 + 1]
		var i2 := _indices[t * 3 + 2]
		var zone_weights := {}
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
				var zone := _zone_for_bone(String(skin.get_bind_name(bind)))
				zone_weights[zone] = float(zone_weights.get(zone, 0.0)) + weight
		var dominant := ZONE_COAT
		var best := -1.0
		for zone in zone_weights.keys():
			var value: float = zone_weights[zone]
			if value > best:
				best = value
				dominant = int(zone)
		_tri_zones[t] = dominant
		_tri_islands[t] = _uf_find(i0)
		_zone_counts[dominant] = int(_zone_counts.get(dominant, 0)) + 1
	picker = GroomPickerScript.new()
	picker.setup(_rest_vertices, _uvs, _indices, _tri_zones, _tri_islands)


func _rasterise_mask() -> void:
	var pixels := MASK_SIZE * MASK_SIZE
	_mask_data.resize(pixels * 4)
	_mask_data.fill(0)
	_zone_map.resize(pixels)
	_zone_map.fill(ZONE_NONE)
	_island_map.resize(pixels)
	for i in range(pixels):
		_island_map[i] = -1
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
				_island_map[pixel] = island
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
	material.set_shader_parameter("dirt_level", current_dirt_level)
	material.set_shader_parameter("mask_view", 0.0)
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
			accumulated += (bone_pose * _bind_inv[bind] * rest) * weight
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
	hit["position"] = skeleton.global_transform * hit["position"]
	hit["normal"] = (skeleton.global_transform.basis * hit["normal"]).normalized()
	return hit


func paint_hit(hit: Dictionary, tool: String) -> Dictionary:
	if hit.is_empty():
		return {"ok": false, "reason": "miss"}
	var zone := int(hit.get("zone", ZONE_NONE))
	if tool == "hoof":
		if zone == ZONE_HOOF or zone == ZONE_LEG:
			return {"ok": false, "reason": "hoof", "zone": zone}
		return {"ok": false, "reason": "zone", "zone": zone}
	if not _tool_allows_zone(tool, zone):
		return {"ok": false, "reason": "zone", "zone": zone}
	var uv: Vector2 = hit.get("uv", Vector2.ZERO)
	if tool == "soft" and get_mask_value(uv, "clean") < SOFT_MIN_CLEAN:
		return {"ok": false, "reason": "dirty", "zone": zone}
	var uv_per_meter := float(hit.get("uv_per_meter", 100.0))
	# The coat atlas is split into narrow shells; a strict UV-space circle only
	# covers the shell under the cursor.  A modest boost lets the stamp reach
	# the neighbouring shells of the same zone without leaking across the face
	# or leg boundaries (the zone map still gates every pixel).
	var radius_uv := brush_world_radius(tool) * uv_per_meter * 2.2
	var island := int(hit.get("island", -1))
	var painted_ok := paint_uv(uv, zone, island, tool, radius_uv)
	return {"ok": painted_ok, "reason": "ok" if painted_ok else "zone", "zone": zone}


## Painting is guarded by the baked groomable alpha and the zone map.  The UV
## island is deliberately not used as a brush limit: this horse's coat is split
## into many small UV shells, and restricting a stamp to the shell under the
## cursor made the brush feel like a pinprick.  Zone + alpha keep the face brush
## off the body and the body tools off the face without that side effect.
func paint_uv(uv: Vector2, zone: int, _island: int, tool: String, radius_uv: float) -> bool:
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
	for py in range(min_y, max_y + 1):
		var dy := float(py) - float(centre_y)
		for px in range(min_x, max_x + 1):
			var dx := float(px) - float(centre_x)
			var distance := sqrt(dx * dx + dy * dy) / radius_px
			if distance > 1.0:
				continue
			var pixel := py * MASK_SIZE + px
			if _mask_data[pixel * 4 + 3] == 0:
				continue
			if int(_zone_map[pixel]) != zone:
				continue
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
					var gain := falloff * (0.16 + 0.84 * loosen)
					var new_clean := maxf(clean, gain)
					if new_clean > clean + 0.0005:
						_mask_data[base] = int(round(new_clean * 255.0))
						did_paint = true
				"soft":
					if clean < SOFT_MIN_CLEAN:
						continue
					var new_polish := maxf(polish, falloff * (0.35 + 0.65 * clean))
					if new_polish > polish + 0.0005:
						_mask_data[base + 1] = int(round(new_polish * 255.0))
						did_paint = true
	if did_paint:
		_dirty = true
		last_paint_ms = float(Time.get_ticks_usec() - started) / 1000.0
		painted.emit()
	return did_paint


func _tool_allows_zone(tool: String, zone: int) -> bool:
	match tool:
		"curry":
			return zone == ZONE_COAT
		"dandy":
			return zone == ZONE_COAT or zone == ZONE_LEG
		"soft":
			return zone == ZONE_COAT or zone == ZONE_LEG
		"face":
			return zone == ZONE_FACE
		"hoof":
			return zone == ZONE_HOOF
	return false


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


func reset_mask() -> void:
	if _mask_data.is_empty():
		return
	for pixel in range(MASK_SIZE * MASK_SIZE):
		var base := pixel * 4
		_mask_data[base] = 0
		_mask_data[base + 1] = 0
		_mask_data[base + 2] = 0
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
	_dirty = true
	flush_texture()


func find_uv_for_zone(zone: int) -> Vector2:
	for pixel in range(MASK_SIZE * MASK_SIZE):
		if int(_zone_map[pixel]) == zone:
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


func get_zone_counts() -> Dictionary:
	return _zone_counts.duplicate()


func get_groomable_count() -> int:
	return _groomable_count


func get_cleanable_count() -> int:
	return _cleanable_count


func get_polishable_count() -> int:
	return _polishable_count
