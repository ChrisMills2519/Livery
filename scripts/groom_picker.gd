extends RefCounted
class_name GroomPicker

## Triangle picker for the groomed horse.
##
## The horse is a skinned mesh, so the CPU vertex positions are rebuilt from
## the Skeleton3D pose whenever grooming starts. A single rider scene means one
## horse and roughly three thousand triangles: a linear ray test is cheap and
## avoids maintaining a second acceleration structure that could fall out of
## sync with the animated pose.

var triangle_count := 0
var _indices := PackedInt32Array()
var _rest_vertices := PackedVector3Array()
var _uvs := PackedVector2Array()
var _tri_zones := PackedByteArray()
var _tri_islands := PackedInt32Array()
var _uv_per_meter := PackedFloat32Array()
var _positions := PackedVector3Array()
var _aabbs: Array = []


func setup(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, tri_zones: PackedByteArray, tri_islands: PackedInt32Array) -> void:
	_rest_vertices = vertices
	_uvs = uvs
	_indices = indices
	_tri_zones = tri_zones
	_tri_islands = tri_islands
	triangle_count = indices.size() / 3
	_positions.resize(triangle_count * 3)
	_aabbs.resize(triangle_count)
	_uv_per_meter.resize(triangle_count)
	for t in range(triangle_count):
		var i0 := indices[t * 3]
		var i1 := indices[t * 3 + 1]
		var i2 := indices[t * 3 + 2]
		var p0 := vertices[i0]
		var p1 := vertices[i1]
		var p2 := vertices[i2]
		var uv0 := uvs[i0]
		var uv1 := uvs[i1]
		var uv2 := uvs[i2]
		var world_length := p0.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(p0)
		var uv_length := uv0.distance_to(uv1) + uv1.distance_to(uv2) + uv2.distance_to(uv0)
		var scale := 1.0
		if world_length > 0.00001:
			scale = uv_length / world_length
		_uv_per_meter[t] = maxf(scale, 0.01)
		_positions[t * 3] = p0
		_positions[t * 3 + 1] = p1
		_positions[t * 3 + 2] = p2
		_aabbs[t] = AABB(p0, Vector3.ZERO).expand(p1).expand(p2)


func rebuild(skinned_vertices: PackedVector3Array) -> void:
	if skinned_vertices.size() != _rest_vertices.size():
		return
	for t in range(triangle_count):
		var p0 := skinned_vertices[_indices[t * 3]]
		var p1 := skinned_vertices[_indices[t * 3 + 1]]
		var p2 := skinned_vertices[_indices[t * 3 + 2]]
		_positions[t * 3] = p0
		_positions[t * 3 + 1] = p1
		_positions[t * 3 + 2] = p2
		_aabbs[t] = AABB(p0, Vector3.ZERO).expand(p1).expand(p2)


## Byte mask (length triangle_count) marking every triangle whose posed AABB
## comes within `radius` of `point` (skeleton-local space).
##
## Mirrored UVs and a packed coat atlas mean a UV-space stamp can land on a
## part of the mesh that is physically far from the cursor.  This hands the
## painter the set of triangles actually under the brush so it can reject a
## texel that only belongs to a distant region.
func triangles_within(point: Vector3, radius: float) -> PackedByteArray:
	var allowed := PackedByteArray()
	allowed.resize(triangle_count)
	allowed.fill(0)
	for t in range(triangle_count):
		if _aabbs[t].grow(radius).has_point(point):
			allowed[t] = 1
	return allowed


func pick(origin: Vector3, direction: Vector3) -> Dictionary:
	if triangle_count == 0:
		return {}
	var dir := direction.normalized()
	if dir.length_squared() < 0.5:
		return {}
	var best_t := INF
	var best_tri := -1
	var best_u := 0.0
	var best_v := 0.0
	for t in range(triangle_count):
		if not _ray_hits_aabb(origin, dir, _aabbs[t]):
			continue
		var p0 := _positions[t * 3]
		var p1 := _positions[t * 3 + 1]
		var p2 := _positions[t * 3 + 2]
		var edge1 := p1 - p0
		var edge2 := p2 - p0
		var pvec := dir.cross(edge2)
		var det := edge1.dot(pvec)
		if absf(det) < 0.0000001:
			continue
		var inv_det := 1.0 / det
		var tvec := origin - p0
		var u := tvec.dot(pvec) * inv_det
		if u < 0.0 or u > 1.0:
			continue
		var qvec := tvec.cross(edge1)
		var v := dir.dot(qvec) * inv_det
		if v < 0.0 or u + v > 1.0:
			continue
		var hit_distance := edge2.dot(qvec) * inv_det
		if hit_distance <= 0.0001 or hit_distance >= best_t:
			continue
		best_t = hit_distance
		best_tri = t
		best_u = u
		best_v = v
	if best_tri < 0:
		return {}
	var i0 := _indices[best_tri * 3]
	var i1 := _indices[best_tri * 3 + 1]
	var i2 := _indices[best_tri * 3 + 2]
	var w := 1.0 - best_u - best_v
	var uv := _uvs[i0] * w + _uvs[i1] * best_u + _uvs[i2] * best_v
	var normal := (_positions[best_tri * 3 + 1] - _positions[best_tri * 3]).cross(_positions[best_tri * 3 + 2] - _positions[best_tri * 3]).normalized()
	return {
		"position": origin + dir * best_t,
		"normal": normal,
		"uv": uv,
		"zone": int(_tri_zones[best_tri]),
		"island": int(_tri_islands[best_tri]),
		"uv_per_meter": _uv_per_meter[best_tri],
		"triangle": best_tri,
		"distance": best_t,
	}


func _ray_hits_aabb(origin: Vector3, dir: Vector3, box: AABB) -> bool:
	var tmin := -INF
	var tmax := INF
	for axis in range(3):
		var o: float = origin[axis]
		var d: float = dir[axis]
		var lo: float = box.position[axis]
		var hi: float = lo + box.size[axis]
		if absf(d) < 0.0000001:
			if o < lo or o > hi:
				return false
			continue
		var inv := 1.0 / d
		var t1 := (lo - o) * inv
		var t2 := (hi - o) * inv
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return false
	return tmax >= 0.0
