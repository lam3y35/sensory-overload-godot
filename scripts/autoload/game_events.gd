extends Node
## Global typed signal bus decoupling gameplay, UI, audio, and persistence modules.

signal graze_scored(tier: int, points: int, streak: int, multiplier: float)
signal ring_collected(points: int, streak: int, multiplier: float)
signal chain_changed(streak: int, multiplier: float, timer_ratio: float)
signal flow_changed(flow: float, color_locked: bool)
signal boost_changed(active: bool, boost_ratio: float)
signal phase_dash_used(parried: bool, cooldown_ratio: float)
signal milestone_callout(text: String, color: Color)
signal section_changed(section_index: int, effect_mask: int)
signal player_died(obstacle_id: String, obstacle_type: String, impact_point: Vector3, summary: Dictionary)
signal stage_cleared(stage_id: String, mode: String, summary: Dictionary)
signal checkpoint_updated(has_checkpoint: bool, depth_m: float)
signal settings_changed()
signal achievement_unlocked(achievement_id: String, title: String)
signal replay_state_changed(active: bool, paused: bool, progress: float, speed_mult: float)
signal beat_pulse(beat_index: int, beat_phase: float)
