class_name SweptCollision
extends RefCounted
## Pure analytical continuous swept segment/sphere-to-OBB collision & 3-tier graze math.
## [INDEPENDENT IMPLEMENTATION] Designed to prevent high-speed tunneling and keep tilted/tumbling
## hitboxes locked 1:1 to rendered mesh transforms (addressing VF-09 and VF-10).

const DEFAULT_PLAYER_RADIUS := 0.32
const GRAZE_NEAR_MISS_MAX := 1.65
const GRAZE_DAREDEVIL_MAX := 0.95
const GRAZE_DEATH_WISH_MAX := 0.42

const TIER_NONE := 0
const TIER_NEAR_MISS := 1
const TIER_DAREDEVIL := 2
const TIER_DEATH_WISH := 3


static func segment_to_obb_sweep(
	p0: Vector3,
	p1: Vector3,
	obb_transform: Transform3D,
	half_extents: Vector3,
	radius: float = DEFAULT_PLAYER_RADIUS
) -> Dictionary:
	var inv := obb_transform.affine_inverse()
	var lp0 := inv * p0
	var lp1 := inv * p1
	var d := lp1 - lp0
	var ext := half_extents + Vector3.ONE * radius

	var tmin := 0.0
	var tmax := 1.0

	for axis in range(3):
		var origin_c := lp0[axis]
		var dir_c := d[axis]
		var min_b := -ext[axis]
		var max_b := ext[axis]

		if absf(dir_c) < 1e-6:
			if origin_c < min_b or origin_c > max_b:
				return {"hit": false, "t": 1.0, "impact_point": p1}
		else:
			var inv_d := 1.0 / dir_c
			var t1 := (min_b - origin_c) * inv_d
			var t2 := (max_b - origin_c) * inv_d
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return {"hit": false, "t": 1.0, "impact_point": p1}

	var hit_t := clampf(tmin, 0.0, 1.0)
	return {
		"hit": true,
		"t": hit_t,
		"impact_point": p0.lerp(p1, hit_t),
	}


static func segment_to_obb_clearance(
	p0: Vector3,
	p1: Vector3,
	obb_transform: Transform3D,
	half_extents: Vector3,
	radius: float = DEFAULT_PLAYER_RADIUS
) -> float:
	var inv := obb_transform.affine_inverse()
	var lp0 := inv * p0
	var lp1 := inv * p1

	# Coarse scan across 12 samples along the convex distance curve, followed by local ternary refinement
	var best_t := 0.0
	var best_dist := INF
	const STEPS := 12
	for i in range(STEPS + 1):
		var t := float(i) / float(STEPS)
		var pt := lp0.lerp(lp1, t)
		var dist := _point_to_local_box_distance(pt, half_extents)
		if dist < best_dist:
			best_dist = dist
			best_t = t

	var lo := maxf(0.0, best_t - (1.0 / float(STEPS)))
	var hi := minf(1.0, best_t + (1.0 / float(STEPS)))
	for _iter in range(10):
		var m1 := lo + (hi - lo) / 3.0
		var m2 := hi - (hi - lo) / 3.0
		var d1 := _point_to_local_box_distance(lp0.lerp(lp1, m1), half_extents)
		var d2 := _point_to_local_box_distance(lp0.lerp(lp1, m2), half_extents)
		if d1 < d2:
			hi = m2
			if d1 < best_dist:
				best_dist = d1
		else:
			lo = m1
			if d2 < best_dist:
				best_dist = d2

	return maxf(0.0, best_dist - radius)


static func _point_to_local_box_distance(pt: Vector3, half_extents: Vector3) -> float:
	var q := Vector3(
		maxf(0.0, absf(pt.x) - half_extents.x),
		maxf(0.0, absf(pt.y) - half_extents.y),
		maxf(0.0, absf(pt.z) - half_extents.z)
	)
	return q.length()


static func classify_graze_tier(clearance: float) -> int:
	if clearance <= GRAZE_DEATH_WISH_MAX:
		return TIER_DEATH_WISH
	if clearance <= GRAZE_DAREDEVIL_MAX:
		return TIER_DAREDEVIL
	if clearance <= GRAZE_NEAR_MISS_MAX:
		return TIER_NEAR_MISS
	return TIER_NONE


static func tier_name(tier: int) -> String:
	match tier:
		TIER_DEATH_WISH:
			return "DEATH WISH"
		TIER_DAREDEVIL:
			return "DAREDEVIL"
		TIER_NEAR_MISS:
			return "NEAR MISS"
		_:
			return ""


static func evaluate_obstacle(
	p0: Vector3,
	p1: Vector3,
	parts: Array[Dictionary],
	player_radius: float = DEFAULT_PLAYER_RADIUS
) -> Dictionary:
	var any_hit := false
	var earliest_t := 2.0
	var impact_point := p1
	var min_clearance := INF

	for part in parts:
		var t_xform := part["transform"] as Transform3D
		var half_ext := part["half_extents"] as Vector3
		var sweep := segment_to_obb_sweep(p0, p1, t_xform, half_ext, player_radius)
		if bool(sweep["hit"]):
			any_hit = true
			var ht := float(sweep["t"])
			if ht < earliest_t:
				earliest_t = ht
				impact_point = sweep["impact_point"] as Vector3
		elif not any_hit:
			var clr := segment_to_obb_clearance(p0, p1, t_xform, half_ext, player_radius)
			if clr < min_clearance:
				min_clearance = clr

	if any_hit:
		return {
			"hit": true,
			"hit_t": earliest_t,
			"impact_point": impact_point,
			"min_clearance": 0.0,
			"graze_tier": TIER_NONE,
		}

	var tier := classify_graze_tier(min_clearance)
	return {
		"hit": false,
		"hit_t": 1.0,
		"impact_point": p1,
		"min_clearance": min_clearance,
		"graze_tier": tier,
	}
