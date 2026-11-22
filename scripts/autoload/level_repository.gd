extends Node
## Repository managing Campaign stages, Custom/Community levels, pre-save backups,
## corruption-safe load guards, local ranked leaderboards, and replay storage.
## [BASED ON VERIFIED FINDING] Reproduces 1.0.1 pre-save backup & load-guard protections.

const CAMPAIGN_JSON_PATH := "res://data/levels/campaign_levels.json"
const MAX_BACKUPS_PER_STAGE := 5
const MAX_LEADERBOARD_ENTRIES := 25

var _storage_root: String = "user://"
var _campaign_stages: Array[StageData] = []
var _community_builtin_stages: Array[StageData] = []
var _leaderboards: Dictionary = {}


func _ready() -> void:
	_ensure_directories()
	_load_campaign_bundle()
	_load_leaderboards()


func set_storage_root(root_dir: String) -> void:
	_storage_root = root_dir if root_dir.ends_with("/") else root_dir + "/"
	_ensure_directories()
	_leaderboards.clear()
	_load_leaderboards()


func _custom_dir() -> String:
	return _storage_root + "custom_levels/"


func _backup_dir() -> String:
	return _storage_root + "custom_levels/backups/"


func _replay_dir() -> String:
	return _storage_root + "replays/"


func _leaderboard_path() -> String:
	return _storage_root + "leaderboards.json"


func _ensure_directories() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_custom_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_backup_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_replay_dir()))


func get_campaign_stages() -> Array[StageData]:
	var copy_arr: Array[StageData] = []
	for s in _campaign_stages:
		copy_arr.append(s)
	return copy_arr


func get_stage_by_id(stage_id: String) -> StageData:
	for s in _campaign_stages:
		if s.id == stage_id:
			return s.duplicate_stage()
	for cs in _community_builtin_stages:
		if cs.id == stage_id:
			return cs.duplicate_stage()
	var res := load_custom_stage(stage_id)
	if bool(res["ok"]):
		return res["stage"] as StageData
	return null


func get_next_campaign_stage_id(stage_id: String) -> String:
	for i in range(_campaign_stages.size()):
		if _campaign_stages[i].id == stage_id and i + 1 < _campaign_stages.size():
			return _campaign_stages[i + 1].id
	return ""


func list_custom_stages() -> Array[StageData]:
	var list: Array[StageData] = []
	for bs in _community_builtin_stages:
		list.append(bs)
	var abs_dir := ProjectSettings.globalize_path(_custom_dir())
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return list
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var res := load_stage_from_file(_custom_dir() + fname)
			if bool(res["ok"]):
				list.append(res["stage"] as StageData)
		fname = dir.get_next()
	dir.list_dir_end()
	return list


func save_custom_stage(stage: StageData) -> Dictionary:
	_ensure_directories()
	if stage == null or stage.id.strip_edges().is_empty():
		return {"ok": false, "path": "", "backup_path": "", "error": "Stage ID is required."}

	var safe_id := stage.id.validate_filename()
	var dest_path := _custom_dir() + safe_id + ".json"
	var backup_path := ""

	if FileAccess.file_exists(dest_path):
		var old_file := FileAccess.open(dest_path, FileAccess.READ)
		if old_file != null:
			var prev_text := old_file.get_as_text()
			backup_path = "%s%s_%d.json.bak" % [_backup_dir(), safe_id, Time.get_ticks_usec()]
			var bak := FileAccess.open(backup_path, FileAccess.WRITE)
			if bak != null:
				bak.store_string(prev_text)
			_prune_backups(safe_id)

	var f := FileAccess.open(dest_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "path": dest_path, "backup_path": backup_path, "error": "Failed to open stage file for write."}
	f.store_string(JSON.stringify(stage.to_dict(), "\t"))
	return {"ok": true, "path": dest_path, "backup_path": backup_path, "error": ""}


func load_custom_stage(stage_id: String) -> Dictionary:
	var safe_id := stage_id.validate_filename()
	return load_stage_from_file(_custom_dir() + safe_id + ".json")


func load_stage_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "stage": null, "error": "File does not exist: " + path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "stage": null, "error": "Unable to open file: " + path}
	var raw_text := f.get_as_text()
	var json := JSON.new()
	var err := json.parse(raw_text)
	if err != OK:
		return {
			"ok": false,
			"stage": null,
			"error": "JSON parse failure at line %d: %s" % [json.get_error_line(), json.get_error_message()],
		}
	return StageData.from_dict(json.data)


func list_backups_for_stage(stage_id: String) -> PackedStringArray:
	var safe_id := stage_id.validate_filename()
	var matches: Array[String] = []
	var abs_bak := ProjectSettings.globalize_path(_backup_dir())
	var dir := DirAccess.open(abs_bak)
	if dir == null:
		return PackedStringArray()
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and fname.begins_with(safe_id + "_") and fname.ends_with(".json.bak"):
			matches.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	matches.sort()
	return PackedStringArray(matches)


func _prune_backups(safe_id: String) -> void:
	var baks := list_backups_for_stage(safe_id)
	if baks.size() <= MAX_BACKUPS_PER_STAGE:
		return
	var abs_bak := ProjectSettings.globalize_path(_backup_dir())
	var dir := DirAccess.open(abs_bak)
	if dir == null:
		return
	for i in range(baks.size() - MAX_BACKUPS_PER_STAGE):
		dir.remove(baks[i])


func save_replay(replay: ReplayData) -> Dictionary:
	_ensure_directories()
	if replay == null or replay.replay_id.is_empty():
		return {"ok": false, "path": "", "error": "Replay ID is required."}
	var safe_id := replay.replay_id.validate_filename()
	var path := _replay_dir() + safe_id + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "path": path, "error": "Unable to write replay file."}
	f.store_string(JSON.stringify(replay.to_dict()))
	return {"ok": true, "path": path, "error": ""}


func load_replay(replay_id: String) -> Dictionary:
	var safe_id := replay_id.validate_filename()
	var path := _replay_dir() + safe_id + ".json"
	if not FileAccess.file_exists(path):
		return {"ok": false, "replay": null, "error": "Replay not found."}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "replay": null, "error": "Cannot read replay."}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return ReplayData.from_dict(parsed)


func submit_leaderboard_entry(stage_id: String, player_name: String, score: int, max_chain: float, duration_sec: float, replay_id: String) -> void:
	var rows: Array = _leaderboards.get(stage_id, []) as Array
	rows.append({
		"player_name": player_name,
		"score": score,
		"max_chain": max_chain,
		"duration_sec": duration_sec,
		"replay_id": replay_id,
		"timestamp": int(Time.get_unix_time_from_system()),
	})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	if rows.size() > MAX_LEADERBOARD_ENTRIES:
		rows = rows.slice(0, MAX_LEADERBOARD_ENTRIES)
	_leaderboards[stage_id] = rows
	_save_leaderboards()


func get_stage_leaderboard(stage_id: String) -> Array:
	return (_leaderboards.get(stage_id, []) as Array).duplicate(true)


func _save_leaderboards() -> void:
	var f := FileAccess.open(_leaderboard_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_leaderboards, "\t"))


func _load_leaderboards() -> void:
	if not FileAccess.file_exists(_leaderboard_path()):
		return
	var f := FileAccess.open(_leaderboard_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_leaderboards = parsed


func _load_campaign_bundle() -> void:
	_campaign_stages.clear()
	_community_builtin_stages.clear()
	if FileAccess.file_exists(CAMPAIGN_JSON_PATH):
		var f := FileAccess.open(CAMPAIGN_JSON_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var root: Dictionary = parsed
				for raw_s in (root.get("campaign", []) as Array):
					var res := StageData.from_dict(raw_s)
					if bool(res["ok"]):
						_campaign_stages.append(res["stage"] as StageData)
				for raw_c in (root.get("community_samples", []) as Array):
					var cres := StageData.from_dict(raw_c)
					if bool(cres["ok"]):
						_community_builtin_stages.append(cres["stage"] as StageData)
	if _campaign_stages.is_empty():
		_campaign_stages.append(_build_fallback_starter_stage())


func _build_fallback_starter_stage() -> StageData:
	var st := StageData.new()
	st.id = "01_a"
	st.level_index = 1
	st.level_title = "01 — Calibration"
	st.stage_code = "01-A"
	st.title = "Drop Check"
	st.author = "Pancake Reconstruction"
	st.source = "campaign"
	st.bpm = 124.0
	st.track_index = 0
	st.base_speed = 34.0
	st.speed_ramp = 0.25
	st.sections = [
		{"id": "sec_1", "length": 180.0, "effect_mask": (1 << 5) | (1 << 11), "transition_gap": 24.0},
		{"id": "sec_2", "length": 180.0, "effect_mask": (1 << 0) | (1 << 5) | (1 << 11), "transition_gap": 24.0},
	]
	var obs1 := ObstacleData.new()
	obs1.id = "starter_01"
	obs1.type = "cross_bars"
	obs1.depth = 60.0
	obs1.speed = 0.6
	st.obstacles.append(obs1)
	var obs2 := ObstacleData.new()
	obs2.id = "starter_02"
	obs2.type = "waffle"
	obs2.depth = 120.0
	obs2.speed = 0.2
	st.obstacles.append(obs2)
	return st
