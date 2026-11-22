class_name ReplayData
extends RefCounted
## Serializable 60 Hz run recording supporting live WATCH replay playback.

const SCHEMA_VERSION := "replay_v1"

var replay_id: String = ""
var stage_id: String = ""
var mode: String = "ranked"
var player_name: String = "Pilot"
var score: int = 0
var max_chain: float = 1.0
var duration_sec: float = 0.0
var max_depth: float = 0.0
var cleared: bool = false
var tick_hz: int = 60
## Each frame is [y_depth: float, x_pos: float, z_pos: float, roll_rad: float]
var frames: Array[Array] = []
## Each event is [tick: int, kind: String, value: float]
var events: Array[Array] = []


func add_frame(y_pos: float, x_pos: float, z_pos: float, roll_rad: float) -> void:
	frames.append([y_pos, x_pos, z_pos, roll_rad])
	max_depth = maxf(max_depth, -y_pos)


func add_event(kind: String, value: float = 0.0) -> void:
	events.append([maxi(0, frames.size() - 1), kind, value])


func sample_at_time(elapsed_sec: float) -> Dictionary:
	if frames.is_empty():
		return {"pos": Vector3.ZERO, "roll": 0.0, "finished": true, "progress": 1.0}
	var exact_tick := clampf(elapsed_sec * float(tick_hz), 0.0, float(frames.size() - 1))
	var i0 := int(floor(exact_tick))
	var i1 := mini(i0 + 1, frames.size() - 1)
	var alpha := exact_tick - float(i0)
	var f0: Array = frames[i0]
	var f1: Array = frames[i1]
	var y_val := lerpf(float(f0[0]), float(f1[0]), alpha)
	var x_val := lerpf(float(f0[1]), float(f1[1]), alpha)
	var z_val := lerpf(float(f0[2]), float(f1[2]), alpha)
	var r_val := lerpf(float(f0[3]), float(f1[3]), alpha)
	var finished := exact_tick >= float(frames.size() - 1) and frames.size() > 1
	return {
		"pos": Vector3(x_val, y_val, z_val),
		"roll": r_val,
		"finished": finished,
		"progress": exact_tick / maxf(1.0, float(frames.size() - 1)),
	}


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"replay_id": replay_id,
		"stage_id": stage_id,
		"mode": mode,
		"player_name": player_name,
		"score": score,
		"max_chain": max_chain,
		"duration_sec": duration_sec,
		"max_depth": max_depth,
		"cleared": cleared,
		"tick_hz": tick_hz,
		"frames": frames,
		"events": events,
	}


static func from_dict(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"ok": false, "replay": null, "error": "Replay JSON must be a dictionary."}
	var d: Dictionary = raw
	if str(d.get("schema", "")) != SCHEMA_VERSION:
		return {"ok": false, "replay": null, "error": "Invalid replay schema."}
	var frames_raw: Variant = d.get("frames", null)
	if typeof(frames_raw) != TYPE_ARRAY:
		return {"ok": false, "replay": null, "error": "Replay frames must be an array."}

	var rep := ReplayData.new()
	rep.replay_id = str(d.get("replay_id", ""))
	rep.stage_id = str(d.get("stage_id", ""))
	rep.mode = str(d.get("mode", "ranked"))
	rep.player_name = str(d.get("player_name", "Pilot"))
	rep.score = int(d.get("score", 0))
	rep.max_chain = float(d.get("max_chain", 1.0))
	rep.duration_sec = float(d.get("duration_sec", 0.0))
	rep.max_depth = float(d.get("max_depth", 0.0))
	rep.cleared = bool(d.get("cleared", false))
	rep.tick_hz = maxi(1, int(d.get("tick_hz", 60)))

	for f_raw in (frames_raw as Array):
		if typeof(f_raw) == TYPE_ARRAY and (f_raw as Array).size() >= 4:
			var arr: Array = f_raw
			rep.frames.append([float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3])])

	var ev_raw: Variant = d.get("events", [])
	if typeof(ev_raw) == TYPE_ARRAY:
		for e_item in (ev_raw as Array):
			if typeof(e_item) == TYPE_ARRAY and (e_item as Array).size() >= 3:
				var earr: Array = e_item
				rep.events.append([int(earr[0]), str(earr[1]), float(earr[2])])

	return {"ok": true, "replay": rep, "error": ""}
