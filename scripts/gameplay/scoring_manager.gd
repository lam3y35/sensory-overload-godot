class_name ScoringManager
extends RefCounted
## Handles 3-tier Graze scoring (Near Miss, Daredevil, Death Wish), Chain multipliers,
## Flow Color Lock, Practice checkpoints, Zen pass-through, and Ranked speed escalation.

const MODE_NORMAL := "normal"
const MODE_RANKED := "ranked"
const MODE_ZEN := "zen"
const MODE_PRACTICE := "practice"
const MODE_WATCH := "watch"
const MODE_EDITOR_TEST := "editor_test"

const CHAIN_DECAY_SECONDS := 4.5
const MAX_CHAIN_MULT := 8.0
const FLOW_DECAY_PER_SEC := 0.06
const FLOW_LOCK_THRESHOLD := 0.70

const GRAZE_POINTS := {
	SweptCollision.TIER_NEAR_MISS: 100,
	SweptCollision.TIER_DAREDEVIL: 250,
	SweptCollision.TIER_DEATH_WISH: 600,
}

const GRAZE_STREAK_STEP := {
	SweptCollision.TIER_NEAR_MISS: 1,
	SweptCollision.TIER_DAREDEVIL: 2,
	SweptCollision.TIER_DEATH_WISH: 3,
}

const GRAZE_FLOW_GAIN := {
	SweptCollision.TIER_NEAR_MISS: 0.06,
	SweptCollision.TIER_DAREDEVIL: 0.12,
	SweptCollision.TIER_DEATH_WISH: 0.22,
}

var mode: String = MODE_NORMAL
var score: int = 0
var streak: int = 0
var chain_multiplier: float = 1.0
var max_chain: float = 1.0
var chain_timer: float = 0.0
var flow_meter: float = 0.0
var color_locked: bool = false
var reached_flow_lock: bool = false

var near_misses: int = 0
var daredevils: int = 0
var death_wishes: int = 0
var rings_collected: int = 0
var boost_time: float = 0.0
var deaths_in_run: int = 0
var grazed_obstacles: Dictionary = {} # obs_id -> highest tier awarded
var _stage_obstacle_count: int = 0

var practice_checkpoint_active: bool = false
var practice_checkpoint_depth: float = 0.0
var practice_checkpoint_xz: Vector2 = Vector2.ZERO


func begin_run(run_mode: String, stage: StageData, keep_checkpoint: bool = false) -> void:
	mode = run_mode
	score = 0
	streak = 0
	chain_multiplier = 1.0
	max_chain = 1.0
	chain_timer = 0.0
	flow_meter = 0.0
	color_locked = false
	reached_flow_lock = false
	near_misses = 0
	daredevils = 0
	death_wishes = 0
	rings_collected = 0
	boost_time = 0.0
	grazed_obstacles.clear()
	_stage_obstacle_count = stage.obstacles.size() if stage != null else 0
	if not keep_checkpoint:
		deaths_in_run = 0
		practice_checkpoint_active = false
		practice_checkpoint_depth = 0.0
		practice_checkpoint_xz = Vector2.ZERO
	GameEvents.chain_changed.emit(streak, chain_multiplier, 0.0)
	GameEvents.flow_changed.emit(flow_meter, color_locked)
	GameEvents.checkpoint_updated.emit(practice_checkpoint_active, practice_checkpoint_depth)


func set_checkpoint(depth_m: float, xz: Vector2) -> void:
	if mode != MODE_PRACTICE:
		return
	practice_checkpoint_active = true
	practice_checkpoint_depth = maxf(0.0, depth_m)
	practice_checkpoint_xz = xz
	GameEvents.checkpoint_updated.emit(true, practice_checkpoint_depth)


func clear_checkpoint() -> void:
	practice_checkpoint_active = false
	practice_checkpoint_depth = 0.0
	practice_checkpoint_xz = Vector2.ZERO
	GameEvents.checkpoint_updated.emit(false, 0.0)


func register_graze(obs_id: String, tier: int, is_autopilot: bool = false) -> int:
	if tier <= SweptCollision.TIER_NONE or is_autopilot:
		return 0
	if mode == MODE_WATCH:
		return 0

	var prev_tier := int(grazed_obstacles.get(obs_id, SweptCollision.TIER_NONE))
	if tier <= prev_tier:
		return 0
	grazed_obstacles[obs_id] = tier

	if mode == MODE_ZEN:
		# Zen allows visual flow glow without competitive scoring or achievement farming
		flow_meter = minf(1.0, flow_meter + float(GRAZE_FLOW_GAIN.get(tier, 0.05)))
		_update_flow_lock()
		return 0

	var awarded_pts := 0
	if prev_tier == SweptCollision.TIER_NONE:
		match tier:
			SweptCollision.TIER_NEAR_MISS:
				near_misses += 1
			SweptCollision.TIER_DAREDEVIL:
				daredevils += 1
			SweptCollision.TIER_DEATH_WISH:
				death_wishes += 1
		streak += int(GRAZE_STREAK_STEP.get(tier, 1))
		chain_multiplier = minf(MAX_CHAIN_MULT, 1.0 + floorf(float(streak) / 3.0) * 0.5)
		max_chain = maxf(max_chain, chain_multiplier)
		chain_timer = CHAIN_DECAY_SECONDS
		awarded_pts = int(round(float(GRAZE_POINTS.get(tier, 100)) * chain_multiplier))
		score += awarded_pts
		flow_meter = minf(1.0, flow_meter + float(GRAZE_FLOW_GAIN.get(tier, 0.06)))
		_update_flow_lock()
		if mode == MODE_NORMAL or mode == MODE_RANKED:
			SaveManager.record_graze(tier, streak, chain_multiplier)
	else:
		# Upgrade graze bonus if player slipped closer before clearing the obstacle
		var delta_pts := int(GRAZE_POINTS.get(tier, 0)) - int(GRAZE_POINTS.get(prev_tier, 0))
		awarded_pts = maxi(0, int(round(float(delta_pts) * chain_multiplier)))
		score += awarded_pts

	GameEvents.graze_scored.emit(tier, awarded_pts, streak, chain_multiplier)
	GameEvents.chain_changed.emit(streak, chain_multiplier, 1.0)
	return awarded_pts


func register_ring(_ring_id: String, is_autopilot: bool = false) -> int:
	if mode == MODE_WATCH or is_autopilot:
		return 0
	rings_collected += 1
	if mode == MODE_ZEN:
		flow_meter = minf(1.0, flow_meter + 0.12)
		_update_flow_lock()
		GameEvents.flow_changed.emit(flow_meter, color_locked)
		return 0

	streak += 1
	chain_multiplier = minf(MAX_CHAIN_MULT, 1.0 + floorf(float(streak) / 3.0) * 0.5)
	max_chain = maxf(max_chain, chain_multiplier)
	chain_timer = CHAIN_DECAY_SECONDS
	var awarded := int(round(300.0 * chain_multiplier))
	score += awarded
	flow_meter = minf(1.0, flow_meter + 0.12)
	_update_flow_lock()
	GameEvents.ring_collected.emit(awarded, streak, chain_multiplier)
	GameEvents.chain_changed.emit(streak, chain_multiplier, 1.0)
	GameEvents.flow_changed.emit(flow_meter, color_locked)
	return awarded


func step(delta: float, is_frozen: bool, in_transition: bool) -> void:
	if is_frozen:
		return
	var prev_flow := flow_meter
	var prev_lock := color_locked
	flow_meter = maxf(0.0, flow_meter - FLOW_DECAY_PER_SEC * delta)
	_update_flow_lock()
	if not is_equal_approx(prev_flow, flow_meter) or prev_lock != color_locked:
		GameEvents.flow_changed.emit(flow_meter, color_locked)

	if streak > 0 and not in_transition:
		chain_timer -= delta
		if chain_timer <= 0.0:
			chain_timer = 0.0
			streak = 0
			chain_multiplier = 1.0
			GameEvents.chain_changed.emit(streak, chain_multiplier, 0.0)
		else:
			GameEvents.chain_changed.emit(streak, chain_multiplier, chain_timer / CHAIN_DECAY_SECONDS)


func add_descent_distance_score(delta_depth: float, is_boosting: bool = false) -> void:
	if mode == MODE_ZEN or mode == MODE_WATCH:
		return
	var mult := 2.0 if is_boosting else 1.0
	score += maxi(0, int(floor(delta_depth * 2.0 * mult * chain_multiplier)))


func _update_flow_lock() -> void:
	color_locked = flow_meter >= FLOW_LOCK_THRESHOLD
	if color_locked:
		reached_flow_lock = true


func compute_active_speed(stage: StageData, depth_m: float, ranked_lap: int, is_boosting: bool = false) -> float:
	if stage == null:
		return 60.0 if is_boosting else 40.0
	var ramp_bonus := (depth_m / 100.0) * stage.speed_ramp * 3.5
	var lap_bonus := float(ranked_lap) * 8.5 if mode == MODE_RANKED else 0.0
	var base := clampf(stage.base_speed + ramp_bonus + lap_bonus, 18.0, 118.0)
	if is_boosting:
		return clampf(base * 1.48, 26.0, 155.0)
	return base


func compute_effective_mask(stage: StageData, depth_m: float, ranked_lap: int) -> int:
	if stage == null:
		return 0
	var mask := stage.effect_mask_at_depth(depth_m)
	if mode == MODE_RANKED and ranked_lap > 0:
		# Escalate active disorientation effects per endless lap
		for lap_bit in range(mini(ranked_lap * 2, EffectCatalog.TOTAL_BITS)):
			mask = EffectCatalog.set_effect(mask, (lap_bit * 3 + 1) % EffectCatalog.TOTAL_BITS, true)
	return EffectCatalog.clamp_safe_mask(mask, SettingsManager.safe_photosensitivity_mode)


func is_indestructible() -> bool:
	return mode == MODE_ZEN or mode == MODE_WATCH


func compute_rank_grade() -> String:
	var final_score := score
	if final_score >= 45000 and max_chain >= 5.0:
		return "S+"
	if final_score >= 22000 or max_chain >= 4.0:
		return "S"
	if final_score >= 10000 or max_chain >= 2.5 or rings_collected >= 5:
		return "A"
	if final_score >= 3500:
		return "B"
	return "C"


func build_summary(depth_m: float, elapsed_sec: float, cleared: bool) -> Dictionary:
	var grazed_all := cleared and _stage_obstacle_count > 0 and grazed_obstacles.size() >= _stage_obstacle_count
	var final_score := score + (25000 if grazed_all else 0)
	return {
		"score": final_score,
		"max_chain": max_chain,
		"near_misses": near_misses,
		"daredevils": daredevils,
		"death_wishes": death_wishes,
		"total_grazes": near_misses + daredevils + death_wishes,
		"rings_collected": rings_collected,
		"boost_time": boost_time,
		"rank_grade": compute_rank_grade(),
		"deaths": deaths_in_run,
		"depth": depth_m,
		"duration_sec": elapsed_sec,
		"reached_flow_lock": reached_flow_lock,
		"grazed_all": grazed_all,
		"cleared": cleared,
	}
