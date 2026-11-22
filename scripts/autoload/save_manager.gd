extends Node
## Manages campaign unlocks, strictly UUID-isolated per-map stats & ghost markers,
## lifetime telemetry, and local achievements.

const SAVE_SCHEMA := "save_v1"

var _storage_root: String = "user://"
var unlocked_stage_ids: PackedStringArray = PackedStringArray(["01_a"])
var cleared_stage_ids: PackedStringArray = PackedStringArray([])
var map_stats: Dictionary = {}
var unlocked_achievements: PackedStringArray = PackedStringArray([])
var global_stats: Dictionary = {
	"total_attempts": 0,
	"total_deaths": 0,
	"total_grazes": 0,
	"total_near_miss": 0,
	"total_daredevil": 0,
	"total_death_wish": 0,
	"consecutive_nodeath_stages": 0,
	"best_streak": 0,
}


func _ready() -> void:
	load_save()


func set_storage_root(root_dir: String) -> void:
	_storage_root = root_dir if root_dir.ends_with("/") else root_dir + "/"
	reset_in_memory()
	load_save()


func reset_in_memory() -> void:
	unlocked_stage_ids = PackedStringArray(["01_a"])
	cleared_stage_ids = PackedStringArray([])
	map_stats.clear()
	unlocked_achievements = PackedStringArray([])
	global_stats = {
		"total_attempts": 0,
		"total_deaths": 0,
		"total_grazes": 0,
		"total_near_miss": 0,
		"total_daredevil": 0,
		"total_death_wish": 0,
		"consecutive_nodeath_stages": 0,
		"best_streak": 0,
	}


func _save_file_path() -> String:
	return _storage_root + "save_data.json"


func _ensure_map_entry(stage_id: String) -> Dictionary:
	if not map_stats.has(stage_id):
		map_stats[stage_id] = {
			"attempts": 0,
			"clears": 0,
			"high_score": 0,
			"best_chain": 1.0,
			"best_depth": 0.0,
			"ghost_markers": [],
		}
	return map_stats[stage_id] as Dictionary


func get_map_stats(stage_id: String) -> Dictionary:
	return _ensure_map_entry(stage_id).duplicate(true)


func get_ghost_markers(stage_id: String) -> Array:
	var entry := _ensure_map_entry(stage_id)
	return (entry.get("ghost_markers", []) as Array).duplicate(true)


func is_stage_unlocked(stage_id: String) -> bool:
	return unlocked_stage_ids.has(stage_id) or cleared_stage_ids.has(stage_id)


func unlock_stage(stage_id: String) -> void:
	if stage_id.is_empty() or unlocked_stage_ids.has(stage_id):
		return
	unlocked_stage_ids.append(stage_id)


func record_attempt(stage_id: String) -> void:
	var entry := _ensure_map_entry(stage_id)
	entry["attempts"] = int(entry.get("attempts", 0)) + 1
	map_stats[stage_id] = entry

	global_stats["total_attempts"] = int(global_stats.get("total_attempts", 0)) + 1
	unlock_achievement("FIRST_DESCENT")
	if int(global_stats["total_attempts"]) >= 100:
		unlock_achievement("ATTEMPTS_100")
	save_to_disk()


func record_graze(tier: int, streak: int, multiplier: float) -> void:
	global_stats["total_grazes"] = int(global_stats.get("total_grazes", 0)) + 1
	match tier:
		1:
			global_stats["total_near_miss"] = int(global_stats.get("total_near_miss", 0)) + 1
		2:
			global_stats["total_daredevil"] = int(global_stats.get("total_daredevil", 0)) + 1
		3:
			global_stats["total_death_wish"] = int(global_stats.get("total_death_wish", 0)) + 1
			unlock_achievement("FIRST_DEATHWISH")

	global_stats["best_streak"] = maxi(int(global_stats.get("best_streak", 0)), streak)
	if streak >= 5:
		unlock_achievement("GRAZE_STREAK_5")
	if streak >= 10:
		unlock_achievement("GRAZE_STREAK_10")
	if streak >= 20:
		unlock_achievement("GRAZE_STREAK_20")
	if streak >= 50:
		unlock_achievement("GRAZE_STREAK_50")
	if multiplier >= 8.0:
		unlock_achievement("MAX_CHAIN")
	if int(global_stats["total_grazes"]) >= 1000:
		unlock_achievement("GRAZE_1000")


func record_death(stage_id: String, depth_m: float, xz: Vector2, score: int, max_chain: float) -> void:
	var entry := _ensure_map_entry(stage_id)
	entry["high_score"] = maxi(int(entry.get("high_score", 0)), score)
	entry["best_chain"] = maxf(float(entry.get("best_chain", 1.0)), max_chain)
	entry["best_depth"] = maxf(float(entry.get("best_depth", 0.0)), depth_m)

	var ghosts: Array = entry.get("ghost_markers", []) as Array
	ghosts.append({
		"kind": "death",
		"depth": depth_m,
		"x": xz.x,
		"z": xz.y,
		"score": score,
	})
	if ghosts.size() > 6:
		ghosts = ghosts.slice(ghosts.size() - 6, ghosts.size())
	entry["ghost_markers"] = ghosts
	map_stats[stage_id] = entry

	global_stats["total_deaths"] = int(global_stats.get("total_deaths", 0)) + 1
	global_stats["consecutive_nodeath_stages"] = 0
	unlock_achievement("FIRST_DEATH")
	save_to_disk()


func record_stage_clear(stage_id: String, next_stage_id: String, summary: Dictionary) -> void:
	var entry := _ensure_map_entry(stage_id)
	entry["clears"] = int(entry.get("clears", 0)) + 1
	entry["high_score"] = maxi(int(entry.get("high_score", 0)), int(summary.get("score", 0)))
	entry["best_chain"] = maxf(float(entry.get("best_chain", 1.0)), float(summary.get("max_chain", 1.0)))
	entry["best_depth"] = maxf(float(entry.get("best_depth", 0.0)), float(summary.get("depth", 0.0)))

	var ghosts: Array = entry.get("ghost_markers", []) as Array
	ghosts.append({
		"kind": "clear",
		"depth": float(summary.get("depth", 0.0)),
		"x": 0.0,
		"z": 0.0,
		"score": int(summary.get("score", 0)),
	})
	if ghosts.size() > 6:
		ghosts = ghosts.slice(ghosts.size() - 6, ghosts.size())
	entry["ghost_markers"] = ghosts
	map_stats[stage_id] = entry

	if not cleared_stage_ids.has(stage_id):
		cleared_stage_ids.append(stage_id)
	if not next_stage_id.is_empty():
		unlock_stage(next_stage_id)

	var deaths_in_run := int(summary.get("deaths", 0))
	if deaths_in_run == 0:
		unlock_achievement("NODEATH_STAGE")
		var streak_nd := int(global_stats.get("consecutive_nodeath_stages", 0)) + 1
		global_stats["consecutive_nodeath_stages"] = streak_nd
		if streak_nd >= 3:
			unlock_achievement("NODEATH_STREAK_3")
		if bool(summary.get("reached_flow_lock", false)):
			unlock_achievement("PERFECT_STAGE")

	if bool(summary.get("grazed_all", false)):
		unlock_achievement("GRAZE_ALL_STAGE")
	if int(summary.get("death_wishes", 0)) >= 10:
		unlock_achievement("DEATHWISH_STREAK_10")

	if cleared_stage_ids.has("01_a") and cleared_stage_ids.has("01_b") and cleared_stage_ids.has("01_c"):
		unlock_achievement("TUTORIAL_DONE")
	if cleared_stage_ids.has("02_a") and cleared_stage_ids.has("02_b") and cleared_stage_ids.has("02_c"):
		unlock_achievement("CLEAR_VERTIGO")
	if cleared_stage_ids.has("03_a") and cleared_stage_ids.has("03_b") and cleared_stage_ids.has("03_c"):
		unlock_achievement("CLEAR_TORNADO")
	if cleared_stage_ids.has("06_a") and cleared_stage_ids.has("06_b") and cleared_stage_ids.has("06_c"):
		unlock_achievement("CLEAR_SENSORY_OVERLOAD")
	if cleared_stage_ids.has("07_a") and cleared_stage_ids.has("07_b") and cleared_stage_ids.has("07_c"):
		unlock_achievement("CLEAR_ALL_HALLOWS")

	save_to_disk()


func unlock_achievement(achievement_id: String) -> bool:
	if achievement_id.is_empty() or unlocked_achievements.has(achievement_id):
		return false
	unlocked_achievements.append(achievement_id)
	var meta := AchievementCatalog.find(achievement_id)
	GameEvents.achievement_unlocked.emit(achievement_id, str(meta.get("title", achievement_id)))
	return true


func is_achievement_unlocked(achievement_id: String) -> bool:
	return unlocked_achievements.has(achievement_id)


func save_to_disk() -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_storage_root))
	var payload := {
		"schema": SAVE_SCHEMA,
		"unlocked_stage_ids": Array(unlocked_stage_ids),
		"cleared_stage_ids": Array(cleared_stage_ids),
		"map_stats": map_stats,
		"unlocked_achievements": Array(unlocked_achievements),
		"global_stats": global_stats,
	}
	var f := FileAccess.open(_save_file_path(), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(payload, "\t"))
	return OK


func load_save() -> void:
	var path := _save_file_path()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	if str(d.get("schema", "")) != SAVE_SCHEMA:
		return

	unlocked_stage_ids.clear()
	for s_id in (d.get("unlocked_stage_ids", ["01_a"]) as Array):
		unlocked_stage_ids.append(str(s_id))
	if not unlocked_stage_ids.has("01_a"):
		unlocked_stage_ids.append("01_a")

	cleared_stage_ids.clear()
	for c_id in (d.get("cleared_stage_ids", []) as Array):
		cleared_stage_ids.append(str(c_id))

	map_stats.clear()
	var ms_raw: Variant = d.get("map_stats", {})
	if typeof(ms_raw) == TYPE_DICTIONARY:
		for k in (ms_raw as Dictionary).keys():
			map_stats[str(k)] = (ms_raw[k] as Dictionary).duplicate(true)

	unlocked_achievements.clear()
	for a_id in (d.get("unlocked_achievements", []) as Array):
		unlocked_achievements.append(str(a_id))

	var gs_raw: Variant = d.get("global_stats", {})
	if typeof(gs_raw) == TYPE_DICTIONARY:
		for gk in global_stats.keys():
			if (gs_raw as Dictionary).has(gk):
				global_stats[gk] = int((gs_raw as Dictionary)[gk])
