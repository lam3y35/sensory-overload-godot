extends Node
## Procedural cyber-synthwave AudioStreamWAV synthesizer, BPM/FFT music sync,
## pitch-scaled SFX cues, Menu Ambient mode, and Pause/Restart-on-Death FSM.
## [INDEPENDENT IMPLEMENTATION] Generates zero-crossing seamless loops with no external audio files.

const SAMPLE_RATE := 22050
const LOOP_BEATS := 8

const TRACK_TEMPOS: Array[float] = [124.0, 128.0, 134.0, 138.0, 142.0, 148.0, 152.0]
const TRACK_TITLES: PackedStringArray = [
	"01 — Threshold Pulse (124 BPM)",
	"02 — Spiral Drift (128 BPM)",
	"03 — Vortex Engine (134 BPM)",
	"04 — Deep Channel (138 BPM)",
	"05 — Whiteout Glitch (142 BPM)",
	"06 — Terminal Descent (148 BPM)",
	"07 — Midnight Overdrive (152 BPM)",
]

const SCALE_NOTES_HZ: Array[Array] = [
	[110.0, 130.81, 146.83, 164.81, 196.0, 220.0], # A minor
	[98.0, 116.54, 130.81, 146.83, 174.61, 196.0], # G minor
	[123.47, 146.83, 164.81, 185.0, 220.0, 246.94], # B minor
	[130.81, 155.56, 174.61, 196.0, 233.08, 261.63], # C minor
	[87.31, 103.83, 116.54, 130.81, 155.56, 174.61], # F minor
	[110.0, 116.54, 146.83, 164.81, 174.61, 220.0], # A Phrygian industrial
	[103.83, 123.47, 138.59, 155.56, 185.0, 207.65], # G# minor
]

const CHORD_RATIOS: Array[float] = [1.0, 0.7937005, 1.189207, 0.8908987] # i -> VI -> III -> VII

var current_track_index: int = 0
var current_bpm: float = 128.0
var is_playing: bool = false
var is_paused: bool = false
var beat_phase: float = 0.0
var beat_index: int = 0
var bass_energy: float = 0.0
var mid_energy: float = 0.0
var high_energy: float = 0.0

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _spectrum_inst: AudioEffectSpectrumAnalyzerInstance
var _track_cache: Dictionary = {}
var _sfx_cache: Dictionary = {}
var _last_emitted_beat: int = -1
var _synth_time: float = 0.0


func _ready() -> void:
	_ensure_audio_buses()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)

	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_players.append(p)
	call_deferred("_prewarm_initial_track")


func _prewarm_initial_track() -> void:
	get_or_build_track_stream(0, TRACK_TEMPOS[0])


func _process(delta: float) -> void:
	if not is_playing or is_paused:
		bass_energy = lerpf(bass_energy, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		mid_energy = lerpf(mid_energy, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		high_energy = lerpf(high_energy, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		return

	_synth_time += delta
	var play_pos := _synth_time
	if _music_player != null and _music_player.playing and _music_player.stream != null and DisplayServer.get_name() != "headless":
		play_pos = _music_player.get_playback_position() + AudioServer.get_time_since_last_mix()

	var beats_per_sec := current_bpm / 60.0
	var total_beats := play_pos * beats_per_sec
	beat_index = int(floor(total_beats))
	beat_phase = total_beats - float(beat_index)

	if beat_index != _last_emitted_beat:
		_last_emitted_beat = beat_index
		GameEvents.beat_pulse.emit(beat_index, beat_phase)

	if _spectrum_inst != null and DisplayServer.get_name() != "headless":
		var b := _spectrum_inst.get_magnitude_for_frequency_range(20.0, 150.0).length()
		var m := _spectrum_inst.get_magnitude_for_frequency_range(150.0, 2200.0).length()
		var h := _spectrum_inst.get_magnitude_for_frequency_range(2200.0, 12000.0).length()
		bass_energy = clampf(b * 6.5, 0.0, 1.0)
		mid_energy = clampf(m * 8.0, 0.0, 1.0)
		high_energy = clampf(h * 10.0, 0.0, 1.0)
	else:
		bass_energy = pow(maxf(0.0, 1.0 - beat_phase * 2.2), 2.0)
		mid_energy = 0.5 + 0.5 * sin(total_beats * PI)
		high_energy = 0.35 + 0.35 * sin(total_beats * TAU * 2.0)


func start_menu_ambient() -> void:
	if _music_player != null:
		_music_player.volume_db = -7.5
	start_track(0, TRACK_TEMPOS[0], not is_playing)


func start_track(track_idx: int, bpm_override: float = -1.0, force_restart: bool = true) -> void:
	var idx := posmod(track_idx, TRACK_TEMPOS.size())
	var bpm_val := bpm_override if bpm_override > 0.0 else TRACK_TEMPOS[idx]
	if _music_player != null and force_restart:
		_music_player.volume_db = 0.0
	if not force_restart and is_playing and current_track_index == idx and is_equal_approx(current_bpm, bpm_val):
		is_paused = false
		if _music_player != null:
			_music_player.stream_paused = false
		return

	current_track_index = idx
	current_bpm = bpm_val
	_synth_time = 0.0
	_last_emitted_beat = -1
	is_playing = true
	is_paused = false

	var stream := get_or_build_track_stream(idx, bpm_val)
	if _music_player != null:
		_music_player.stream = stream
		_music_player.stream_paused = false
		if DisplayServer.get_name() != "headless":
			_music_player.play()


func select_random_track() -> int:
	var next_idx := (current_track_index + 1 + randi() % maxi(1, TRACK_TEMPOS.size() - 1)) % TRACK_TEMPOS.size()
	start_track(next_idx, -1.0, true)
	return next_idx


func on_player_death() -> void:
	if SettingsManager.pause_on_death:
		is_paused = true
		if _music_player != null:
			_music_player.stream_paused = true


func on_retry() -> void:
	if SettingsManager.random_track:
		select_random_track()
		return
	if SettingsManager.restart_song_on_death:
		start_track(current_track_index, current_bpm, true)
		return
	is_paused = false
	if _music_player != null:
		_music_player.stream_paused = false


func stop_music() -> void:
	is_playing = false
	is_paused = false
	if _music_player != null:
		_music_player.volume_db = 0.0
		_music_player.stop()


func play_sfx(cue_name: String, pitch_scale: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var stream := get_or_build_sfx_stream(cue_name)
	if stream == null or _sfx_players.is_empty():
		return
	var p := _sfx_players[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	p.stream = stream
	p.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
	p.play()


func get_or_build_track_stream(track_idx: int, bpm_override: float = -1.0) -> AudioStreamWAV:
	var idx := posmod(track_idx, TRACK_TEMPOS.size())
	var bpm_val := bpm_override if bpm_override > 0.0 else TRACK_TEMPOS[idx]
	var cache_key := "%d_%.1f" % [idx, bpm_val]
	if _track_cache.has(cache_key):
		return _track_cache[cache_key] as AudioStreamWAV

	var beat_sec := 60.0 / bpm_val
	var total_samples := int(round(float(LOOP_BEATS) * beat_sec * float(SAMPLE_RATE)))
	var pcm := PackedByteArray()
	pcm.resize(total_samples * 2)

	var scale: Array = SCALE_NOTES_HZ[idx]
	var arp_order := [0, 2, 4, 5, 3, 2, 4, 1, 0, 3, 5, 4, 2, 1, 3, 5]
	var bass_phase := 0.0
	var pad_phase_a := 0.0
	var pad_phase_b := 0.0
	var pad_phase_c := 0.0
	var arp_phase := 0.0
	var kick_phase := 0.0
	var bass_lp := 0.0
	var pad_lp := 0.0
	var arp_lp := 0.0
	var snare_lp := 0.0
	var noise_state := 1337 + idx * 97
	const FADE_SAMPLES := 32

	for i in range(total_samples):
		var t_sec := float(i) / float(SAMPLE_RATE)
		var beat_pos := t_sec / beat_sec
		var beat_num := int(floor(beat_pos))
		var beat_frac := fmod(beat_pos, 1.0)
		var chord_idx := (beat_num / 2) % CHORD_RATIOS.size()
		var chord_ratio: float = CHORD_RATIOS[chord_idx]

		var sixteenth_idx := int(floor(beat_pos * 4.0))
		var sixteenth_frac := fmod(beat_pos * 4.0, 1.0)

		# 1) Punchy four-on-the-floor kick with smooth continuous phase
		var kick_freq := 46.0 + 135.0 * exp(-beat_frac * 28.0)
		kick_phase += kick_freq / float(SAMPLE_RATE)
		if beat_frac < (1.0 / float(SAMPLE_RATE)) * 2.0:
			kick_phase = 0.0
		var kick_env := exp(-beat_frac * 7.8)
		var kick := sin(TAU * kick_phase) * kick_env * 0.52

		# 2) Warm 1-pole LP-filtered rolling synthwave sub+saw bass across 4 chords
		var root_hz := float(scale[0]) * 0.5 * chord_ratio
		bass_phase += root_hz / float(SAMPLE_RATE)
		var raw_saw := (fmod(bass_phase, 1.0) * 2.0 - 1.0)
		var bass_cutoff := 0.08 + 0.14 * (1.0 - fmod(beat_pos * 2.0, 1.0))
		bass_lp += bass_cutoff * (raw_saw - bass_lp)
		var sidechain := clampf(beat_frac * 3.4, 0.14, 1.0)
		var bass := (bass_lp * 0.55 + sin(TAU * bass_phase) * 0.45) * sidechain * 0.30

		# 3) Detuned supersaw filtered chord pad + fifth harmonic layer
		var pad_hz := root_hz * 2.0
		pad_phase_a += (pad_hz * 0.994) / float(SAMPLE_RATE)
		pad_phase_b += (pad_hz * 1.006) / float(SAMPLE_RATE)
		pad_phase_c += (pad_hz * 1.498) / float(SAMPLE_RATE)
		var pad_raw := ((fmod(pad_phase_a, 1.0) * 2.0 - 1.0) + (fmod(pad_phase_b, 1.0) * 2.0 - 1.0) + sin(TAU * pad_phase_c) * 0.7) * 0.35
		pad_lp += 0.075 * (pad_raw - pad_lp)
		var pad := pad_lp * sidechain * 0.18

		# 4) Warm melodic filtered pluck arpeggio (soft attack + decaying timbre, no raw square buzz)
		var note_hz := float(scale[int(arp_order[(sixteenth_idx + idx) % arp_order.size()])]) * chord_ratio * 2.0
		arp_phase += note_hz / float(SAMPLE_RATE)
		var arp_raw := (fmod(arp_phase, 1.0) * 2.0 - 1.0) * 0.55 + sin(TAU * arp_phase) * 0.45
		var arp_cut := clampf(0.28 * exp(-sixteenth_frac * 4.5) + 0.05, 0.04, 0.34)
		arp_lp += arp_cut * (arp_raw - arp_lp)
		var arp_env := smoothstep_sample(0.0, 0.06, sixteenth_frac) * exp(-sixteenth_frac * 4.8)
		var arp := arp_lp * arp_env * 0.22

		# 5) Crisp electronic snare/clap on beats 2, 4, 6, 8 + 16th-note groove hi-hats + bar-end fill
		noise_state = (noise_state * 1103515245 + 12345) & 0x7FFFFFFF
		var white := (float(noise_state % 2000) / 1000.0) - 1.0
		snare_lp += 0.24 * (white - snare_lp)
		var snare_on := 1.0 if (beat_num % 2) == 1 else 0.0
		var snare_fill := 1.0 if (beat_pos >= 7.5 and beat_frac >= 0.5) else 0.0
		var snare_frac := fmod(beat_pos * 2.0, 1.0) if snare_fill > 0.5 else beat_frac
		var snare := snare_lp * exp(-snare_frac * 15.0) * maxf(snare_on, snare_fill) * 0.18

		var hat_frac := fmod(beat_pos + 0.5, 1.0)
		var hat_hp := white - snare_lp
		var hat := hat_hp * exp(-hat_frac * 28.0) * 0.11

		var mixed := tanh((kick + bass + pad + arp + snare + hat) * 1.12) * 0.84

		# Seamless 32-sample (~1.4 ms) cosine edge envelope guarantees zero click at loop seam
		if i < FADE_SAMPLES:
			var w := 0.5 - 0.5 * cos(PI * float(i) / float(FADE_SAMPLES))
			mixed *= w
		elif i >= total_samples - FADE_SAMPLES:
			var rem := total_samples - 1 - i
			var w := 0.5 - 0.5 * cos(PI * float(rem) / float(FADE_SAMPLES))
			mixed *= w

		var s16 := clampi(int(round(mixed * 32767.0)), -32768, 32767)
		pcm.encode_s16(i * 2, s16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total_samples
	wav.data = pcm
	_track_cache[cache_key] = wav
	return wav


func get_or_build_sfx_stream(cue_name: String) -> AudioStreamWAV:
	if _sfx_cache.has(cue_name):
		return _sfx_cache[cue_name] as AudioStreamWAV

	var dur := 0.18
	var f0 := 520.0
	var f1 := 880.0
	var is_noise := false
	var mode := "tone"

	match cue_name:
		"graze_1":
			dur = 0.12; f0 = 580.0; f1 = 840.0
		"graze_2":
			dur = 0.16; f0 = 760.0; f1 = 1180.0
		"graze_3":
			dur = 0.24; f0 = 920.0; f1 = 1640.0; mode = "chord"
		"ring":
			dur = 0.22; f0 = 660.0; f1 = 1320.0; mode = "chord"
		"flow_lock":
			dur = 0.36; f0 = 440.0; f1 = 1100.0; mode = "arpeggio"
		"boost_on":
			dur = 0.20; f0 = 220.0; f1 = 740.0; is_noise = true
		"phase_dash":
			dur = 0.16; f0 = 880.0; f1 = 1760.0; mode = "chord"
		"phase_parry":
			dur = 0.28; f0 = 587.33; f1 = 1760.0; mode = "arpeggio"; is_noise = true
		"section_up":
			dur = 0.26; f0 = 440.0; f1 = 660.0; mode = "chord"
		"whoosh":
			dur = 0.14; f0 = 320.0; f1 = 110.0; is_noise = true; mode = "air"
		"checkpoint":
			dur = 0.18; f0 = 523.25; f1 = 783.99; mode = "chord"
		"clear":
			dur = 0.52; f0 = 523.25; f1 = 1046.5; mode = "arpeggio"
		"death":
			dur = 0.38; f0 = 185.0; f1 = 36.0; is_noise = true
		"ui_click":
			dur = 0.05; f0 = 720.0; f1 = 480.0
		"ui_hover":
			dur = 0.03; f0 = 920.0; f1 = 1040.0
		_:
			dur = 0.10; f0 = 480.0; f1 = 620.0

	var total := int(round(dur * float(SAMPLE_RATE)))
	var pcm := PackedByteArray()
	pcm.resize(total * 2)
	var phase := 0.0
	var phase2 := 0.0
	var lp := 0.0
	var n_state := 9187

	for i in range(total):
		var u := float(i) / float(maxi(1, total - 1))
		var freq := lerpf(f0, f1, u)
		if mode == "arpeggio":
			var step_mult := 1.0 if u < 0.33 else (1.25 if u < 0.66 else 1.5)
			freq = f0 * step_mult
		phase += freq / float(SAMPLE_RATE)
		phase2 += (freq * 1.5) / float(SAMPLE_RATE)
		var env := sin(PI * minf(1.0, u * 7.0)) * exp(-u * 4.2)
		var sig := sin(TAU * phase)
		if mode == "chord":
			sig = sig * 0.62 + sin(TAU * phase2) * 0.38
		elif mode == "air":
			sig = 0.0
		if is_noise:
			n_state = (n_state * 1103515245 + 12345) & 0x7FFFFFFF
			var w := (float(n_state % 2000) / 1000.0) - 1.0
			lp += 0.22 * (w - lp)
			sig = lp * 0.85 if mode == "air" else (sig * 0.58 + lp * 0.42)
		var amp := 0.38 if mode == "air" else 0.66
		var val := sig * env * amp
		pcm.encode_s16(i * 2, clampi(int(round(val * 32767.0)), -32768, 32767))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = pcm
	_sfx_cache[cue_name] = wav
	return wav


static func smoothstep_sample(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _ensure_audio_buses() -> void:
	for bus_name in [&"Music", &"SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")

	var music_idx := AudioServer.get_bus_index(&"Music")
	if music_idx >= 0:
		var has_spec := false
		for e_idx in range(AudioServer.get_bus_effect_count(music_idx)):
			if AudioServer.get_bus_effect(music_idx, e_idx) is AudioEffectSpectrumAnalyzer:
				has_spec = true
				_spectrum_inst = AudioServer.get_bus_effect_instance(music_idx, e_idx) as AudioEffectSpectrumAnalyzerInstance
				break
		if not has_spec:
			var spec := AudioEffectSpectrumAnalyzer.new()
			spec.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_512
			AudioServer.add_bus_effect(music_idx, spec)
			_spectrum_inst = AudioServer.get_bus_effect_instance(music_idx, AudioServer.get_bus_effect_count(music_idx) - 1) as AudioEffectSpectrumAnalyzerInstance
