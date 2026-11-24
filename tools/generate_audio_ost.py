"""Generates studio-mastered 44.1 kHz stereo hard-techno / industrial OST (.ogg)
and layered stereo foley/harmonic SFX (.wav) using NumPy, SciPy, Spotify Pedalboard,
and FFmpeg (libvorbis).
"""

from __future__ import annotations

import math
import shutil
import subprocess
import wave
from pathlib import Path

import numpy as np
import pedalboard as pb
import soundfile as sf
from scipy import signal

ROOT = Path(__file__).resolve().parent.parent
MUSIC_DIR = ROOT / "assets" / "audio" / "music"
SFX_DIR = ROOT / "assets" / "audio" / "sfx"

SR = 44100
LOOP_BEATS = 64  # 16 bars of 4/4 per track with intro/build/drop/climax structure

TRACK_SPECS = [
    {
        "file": "track_01.ogg",
        "title": "01 — Threshold Pulse (128 BPM)",
        "bpm": 128.0,
        "root_midi": 42,  # F#2
        "scale": [0, 3, 5, 7, 10, 12, 15, 19],
        "chords": [0, 0, -2, -4, 0, 0, 3, -2],
        "acid_cutoff": (360.0, 2100.0),
        "drive": 6.0,
        "seed": 101,
    },
    {
        "file": "track_02.ogg",
        "title": "02 — Spiral Drift (132 BPM)",
        "bpm": 132.0,
        "root_midi": 45,  # A2
        "scale": [0, 2, 3, 7, 8, 12, 14, 15],
        "chords": [0, 0, 5, 3, 0, -2, 3, 7],
        "acid_cutoff": (420.0, 2400.0),
        "drive": 7.0,
        "seed": 202,
    },
    {
        "file": "track_03.ogg",
        "title": "03 — Vortex Engine (136 BPM)",
        "bpm": 136.0,
        "root_midi": 38,  # D2 Phrygian
        "scale": [0, 1, 3, 5, 7, 8, 10, 12],
        "chords": [0, 0, 1, 0, -2, 0, 1, 3],
        "acid_cutoff": (380.0, 2900.0),
        "drive": 9.5,
        "seed": 303,
    },
    {
        "file": "track_04.ogg",
        "title": "04 — Deep Channel (140 BPM)",
        "bpm": 140.0,
        "root_midi": 37,  # C#2
        "scale": [0, 3, 5, 6, 7, 10, 12, 15],
        "chords": [0, 0, -2, -5, 0, 0, 3, 5],
        "acid_cutoff": (300.0, 2200.0),
        "drive": 8.0,
        "seed": 404,
    },
    {
        "file": "track_05.ogg",
        "title": "05 — Whiteout Rave (144 BPM)",
        "bpm": 144.0,
        "root_midi": 41,  # F2
        "scale": [0, 2, 3, 7, 10, 12, 14, 19],
        "chords": [0, 5, 3, 7, 0, 8, 5, 3],
        "acid_cutoff": (480.0, 3200.0),
        "drive": 7.5,
        "seed": 505,
    },
    {
        "file": "track_06.ogg",
        "title": "06 — Sensory Overload (148 BPM)",
        "bpm": 148.0,
        "root_midi": 43,  # G2 Phrygian dominant / industrial
        "scale": [0, 1, 4, 5, 7, 8, 10, 12],
        "chords": [0, 0, 1, 3, 0, -2, 1, 5],
        "acid_cutoff": (450.0, 3800.0),
        "drive": 11.0,
        "seed": 606,
    },
    {
        "file": "track_07.ogg",
        "title": "07 — Midnight Overdrive (152 BPM)",
        "bpm": 152.0,
        "root_midi": 40,  # E2 harmonic minor
        "scale": [0, 2, 3, 7, 8, 11, 12, 15],
        "chords": [0, 0, -4, -1, 0, 5, 3, -1],
        "acid_cutoff": (340.0, 2800.0),
        "drive": 9.0,
        "seed": 707,
    },
]


def midi_to_hz(midi: float | np.ndarray) -> float | np.ndarray:
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def poly_blep_saw(phase: np.ndarray, dt: np.ndarray) -> np.ndarray:
    """Band-limited sawtooth via PolyBLEP residual correction."""
    saw = 2.0 * phase - 1.0
    t = phase
    mask1 = t < dt
    x1 = t[mask1] / np.maximum(dt[mask1], 1e-6)
    saw[mask1] -= x1 + x1 - x1 * x1 - 1.0
    mask2 = t > (1.0 - dt)
    x2 = (t[mask2] - 1.0) / np.maximum(dt[mask2], 1e-6)
    saw[mask2] -= x2 * x2 + x2 + x2 + 1.0
    return saw


def poly_blep_square(phase: np.ndarray, dt: np.ndarray, pw: float = 0.5) -> np.ndarray:
    sq = np.where(phase < pw, 1.0, -1.0)
    # Rising edge at 0
    m1 = phase < dt
    x1 = phase[m1] / np.maximum(dt[m1], 1e-6)
    sq[m1] += x1 + x1 - x1 * x1 - 1.0
    m2 = phase > (1.0 - dt)
    x2 = (phase[m2] - 1.0) / np.maximum(dt[m2], 1e-6)
    sq[m2] += x2 * x2 + x2 + x2 + 1.0
    # Falling edge at pw
    p_shift = np.mod(phase - pw + 1.0, 1.0)
    m3 = p_shift < dt
    x3 = p_shift[m3] / np.maximum(dt[m3], 1e-6)
    sq[m3] -= x3 + x3 - x3 * x3 - 1.0
    m4 = p_shift > (1.0 - dt)
    x4 = (p_shift[m4] - 1.0) / np.maximum(dt[m4], 1e-6)
    sq[m4] -= x4 * x4 + x4 + x4 + 1.0
    return sq


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def apply_filter_chunks(audio: np.ndarray, cutoffs: np.ndarray, beat_samples: int, mode: pb.LadderFilter.Mode, drive: float, res: float) -> np.ndarray:
    """Process stereo audio (2, N) in tempo-locked chunks through Pedalboard LadderFilter."""
    n = audio.shape[1]
    chunk = max(256, beat_samples // 4)
    lf = pb.LadderFilter(mode=mode, cutoff_hz=float(cutoffs[0]), resonance=res, drive=drive)
    out = np.zeros_like(audio, dtype=np.float32)
    for start in range(0, n, chunk):
        end = min(n, start + chunk)
        lf.cutoff_hz = float(np.clip(cutoffs[(start + end) // 2], 45.0, 14000.0))
        out[:, start:end] = lf(audio[:, start:end], SR, reset=False)
    return out


def encode_ogg_from_stereo(stereo_f32: np.ndarray, out_ogg: Path, tmp_wav: Path) -> None:
    out_ogg.parent.mkdir(parents=True, exist_ok=True)
    # Write lossless float/PCM16 temp WAV then encode Vorbis quality 6 (~192kbps VBR) cleanly via ffmpeg
    sf.write(str(tmp_wav), stereo_f32.T, SR, subtype="PCM_24")
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-i", str(tmp_wav),
        "-c:a", "libvorbis", "-q:a", "6",
        "-ar", str(SR),
        str(out_ogg),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"ffmpeg failed for {out_ogg}: {res.stderr}")
    tmp_wav.unlink(missing_ok=True)


def save_stereo_wav(stereo_f32: np.ndarray, out_wav: Path) -> None:
    out_wav.parent.mkdir(parents=True, exist_ok=True)
    pcm16 = np.clip(np.round(stereo_f32.T * 32767.0), -32768, 32767).astype(np.int16)
    with wave.open(str(out_wav), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm16.tobytes())


def generate_track(spec: dict) -> None:
    bpm = float(spec["bpm"])
    beat_sec = 60.0 / bpm
    loop_dur = LOOP_BEATS * beat_sec
    n_loop = int(round(loop_dur * SR))
    # Render 2 passes back-to-back and slice pass #2 so all reverbs/delays wrap seamlessly across loop boundary!
    n_total = n_loop * 2
    rng = np.random.default_rng(spec["seed"])

    t = np.arange(n_total, dtype=np.float64) / SR
    beat_pos = t / beat_sec
    beat_in_loop = np.mod(beat_pos, LOOP_BEATS)
    beat_idx = np.floor(beat_in_loop).astype(np.int32)
    beat_frac = np.mod(beat_pos, 1.0)
    bar_idx = beat_idx // 4  # 0..15

    # Song arrangement arc across 16 bars:
    # Bars 0..3: Driving intro kick + dark filtered rumble & subtle hats
    # Bars 4..7: Full acid/bass entry + offbeat open hats + clap
    # Bars 8..11: Acid break / tension sweep (kick cuts bars 8-9 beats 0-3, snare roll bar 9-11)
    # Bars 12..15: Peak overload drop — full supersaw stabs + wide acid + ride cymbals!
    has_kick = (bar_idx != 8) & ~((bar_idx == 9) & (beat_idx % 4 < 2))
    # Bar 7 beat 3 drop-out before break & Bar 11 beat 3 drop-out before climax drop!
    has_kick &= ~((bar_idx == 11) & (beat_idx % 4 == 3) & (beat_frac > 0.25))
    has_clap = (bar_idx >= 4) & (bar_idx != 8)
    has_ride = (bar_idx >= 12) | ((bar_idx >= 4) & (bar_idx < 8) & (bar_idx % 2 == 1))
    has_lead = (bar_idx >= 12) | (bar_idx == 6) | (bar_idx == 7)

    # 1) PUNCHY HARD-TECHNO KICK + TRANSIENT CLICK + RUMBLE REVERB BUS
    kick_pitch = 43.5 + 145.0 * np.exp(-beat_frac * 34.0) + 55.0 * np.exp(-beat_frac * 140.0)
    # Phase reset accurately per beat
    beat_samp_f = beat_frac * beat_sec * SR
    kick_ph = 2.0 * np.pi * (43.5 * (beat_frac * beat_sec) + (145.0 / (34.0 / beat_sec)) * (1.0 - np.exp(-beat_frac * 34.0)))
    kick_env = np.exp(-beat_frac * 6.8) * smoothstep(0.0, 0.0025, beat_frac * beat_sec)
    kick_click = rng.normal(0.0, 1.0, size=n_total) * np.exp(-beat_frac * 220.0) * 0.25
    kick_mono = (np.sin(kick_ph) * kick_env * 0.85 + kick_click) * np.where(has_kick, 1.0, 0.0)
    kick_st = np.stack([kick_mono, kick_mono]).astype(np.float32)

    kick_bus = pb.Pedalboard([
        pb.HighpassFilter(cutoff_frequency_hz=28.0),
        pb.Distortion(drive_db=4.2),
    ])
    kick_clean = kick_bus(kick_st, SR)

    rumble_bus = pb.Pedalboard([
        pb.Reverb(room_size=0.78, damping=0.82, wet_level=0.95, dry_level=0.0, width=0.65),
        pb.LadderFilter(mode=pb.LadderFilter.Mode.LPF24, cutoff_hz=120.0, resonance=0.35, drive=2.2),
        pb.Distortion(drive_db=6.5),
    ])
    rumble_raw = rumble_bus(kick_st, SR)
    rumble_duck = smoothstep(0.10, 0.42, beat_frac) * (0.45 + 0.55 * smoothstep(0.0, 4.0, bar_idx.astype(np.float64)))
    rumble = rumble_raw * (rumble_duck * 0.62)[np.newaxis, :]

    # 2) ROLLING 16TH TB-303 ACID / EBM BASSLINE
    step16 = np.floor(beat_in_loop * 4.0).astype(np.int32)
    step16_frac = np.mod(beat_in_loop * 4.0, 1.0)
    chord_list = spec["chords"]
    scale = spec["scale"]
    pattern_idx = np.array([0, 0, 12, 0, 3, 0, 7, 1, 0, 0, 12, 4, 3, 7, 0, 12], dtype=np.int32)
    accent_mask = np.array([1.0, 0.45, 0.85, 0.50, 0.90, 0.40, 0.78, 0.62, 1.0, 0.55, 0.92, 0.45, 0.85, 0.60, 0.75, 0.95])
    chord_off = np.array([chord_list[(b // 2) % len(chord_list)] for b in bar_idx], dtype=np.int32)

    note_offsets = pattern_idx[step16 % 16]
    # Add subtle variation in bars 8-15
    alt_offsets = np.array([0, 12, 0, 7, 5, 0, 12, 3, 0, 7, 10, 0, 12, 7, 5, 1], dtype=np.int32)[step16 % 16]
    chosen_off = np.where((bar_idx >= 8), alt_offsets, note_offsets)
    midi_notes = spec["root_midi"] + chord_off + chosen_off
    acid_hz = midi_to_hz(midi_notes)
    dt_acid = acid_hz / SR
    ph_acid = np.mod(np.cumsum(dt_acid), 1.0)
    acid_osc = poly_blep_saw(ph_acid, dt_acid) * 0.65 + poly_blep_square(ph_acid, dt_acid, 0.42) * 0.35
    acid_env = smoothstep(0.0, 0.04, step16_frac) * np.exp(-step16_frac * 4.2) * accent_mask[step16 % 16]
    acid_sc = smoothstep(0.06, 0.34, beat_frac)
    acid_dry = (acid_osc * acid_env * (0.45 + 0.55 * acid_sc))
    # Slight stereo micro-offset on bass
    acid_st = np.stack([acid_dry, np.roll(acid_dry, 24)]).astype(np.float32) * 0.42

    c_lo, c_hi = spec["acid_cutoff"]
    # Dynamic filter sweep across bars (opens up through build & explodes at drop!)
    bar_sweep = np.where(bar_idx < 4, 0.12 + 0.12 * (bar_idx / 4.0),
                np.where(bar_idx < 8, 0.35 + 0.25 * ((bar_idx - 4) / 4.0),
                np.where(bar_idx < 12, 0.25 + 0.70 * ((bar_idx - 8) / 4.0), 0.72 + 0.25 * np.sin(beat_in_loop * 0.4))))
    cutoff_arr = c_lo + (c_hi - c_lo) * np.clip(bar_sweep * (0.55 + 0.45 * np.exp(-step16_frac * 3.5)), 0.0, 1.0)
    acid_filt = apply_filter_chunks(acid_st, cutoff_arr, int(beat_sec * SR), pb.LadderFilter.Mode.LPF24, drive=1.8, res=0.68)
    acid_fx = pb.Pedalboard([
        pb.Distortion(drive_db=spec["drive"] * 0.65),
        pb.Delay(delay_seconds=beat_sec * 0.75, feedback=0.28, mix=0.22),
        pb.HighpassFilter(cutoff_frequency_hz=75.0),
    ])(acid_filt, SR)

    # 3) INDUSTRIAL SUPERSAW RAVE CHORDS & ARPEGGIO LEAD
    supersaw_l = np.zeros(n_total, dtype=np.float64)
    supersaw_r = np.zeros(n_total, dtype=np.float64)
    arp_order = [0, 2, 4, 5, 7, 4, 3, 5, 0, 4, 6, 7, 5, 2, 3, 4]
    arp_hz = midi_to_hz(spec["root_midi"] + 24 + chord_off + np.array([scale[i % len(scale)] for i in arp_order])[step16 % 16])
    detunes = [-0.014, -0.008, -0.003, 0.0, 0.003, 0.008, 0.014]
    for k, d_fac in enumerate(detunes):
        hz_d = arp_hz * (1.0 + d_fac)
        dt_d = hz_d / SR
        ph_d = np.mod(np.cumsum(dt_d), 1.0)
        w_d = poly_blep_saw(ph_d, dt_d)
        pan_r = k / float(len(detunes) - 1)
        supersaw_l += w_d * (1.0 - pan_r * 0.7)
        supersaw_r += w_d * (0.3 + pan_r * 0.7)

    lead_env = smoothstep(0.0, 0.06, step16_frac) * np.exp(-step16_frac * 3.6) * np.where(has_lead, 1.0, 0.18)
    # Rave chord stab fifths on offbeats & climax
    stab_hz = midi_to_hz(spec["root_midi"] + 12 + chord_off)
    stab_fifth = midi_to_hz(spec["root_midi"] + 19 + chord_off)
    dt_s1, dt_s2 = stab_hz / SR, stab_fifth / SR
    ph_s1, ph_s2 = np.mod(np.cumsum(dt_s1), 1.0), np.mod(np.cumsum(dt_s2), 1.0)
    stab_gate = np.where((step16 % 4 == 2) & (bar_idx >= 4), 1.0, 0.0) * np.exp(-step16_frac * 6.5)
    stab_wave = (poly_blep_saw(ph_s1, dt_s1) + poly_blep_saw(ph_s2, dt_s2)) * 0.5 * stab_gate

    lead_st = np.stack([
        supersaw_l * 0.14 * lead_env + stab_wave * 0.28,
        supersaw_r * 0.14 * lead_env + stab_wave * 0.28,
    ]).astype(np.float32) * acid_sc[np.newaxis, :]

    lead_fx = pb.Pedalboard([
        pb.HighpassFilter(cutoff_frequency_hz=210.0),
        pb.Chorus(rate_hz=1.4, depth=0.32, mix=0.35),
        pb.Delay(delay_seconds=beat_sec * 0.5, feedback=0.34, mix=0.25),
        pb.Reverb(room_size=0.68, damping=0.45, wet_level=0.32, dry_level=0.82),
    ])(lead_st, SR)

    # 4) INDUSTRIAL 909 DRUMS (CLAP/SNARE + METALLIC 16TH HATS + OFFBEAT RIDE + RISER)
    noise_l = rng.normal(0.0, 1.0, size=n_total)
    noise_r = rng.normal(0.0, 1.0, size=n_total)
    # Bandpass clap around 1.8 kHz on beats 2 & 4 + snare buildup roll on bars 10-11
    b_clap, a_clap = signal.butter(2, [900 / (0.5 * SR), 4200 / (0.5 * SR)], btype="band")
    clap_n_l = signal.lfilter(b_clap, a_clap, noise_l)
    clap_n_r = signal.lfilter(b_clap, a_clap, noise_r)
    clap_trig = np.where(((beat_idx % 2 == 1) & has_clap), np.exp(-beat_frac * 14.0), 0.0)
    # Build roll in bar 11 (8th -> 16th snare buildup!)
    roll_trig = np.where((bar_idx == 11) & (beat_idx % 4 < 3), np.exp(-step16_frac * 16.0) * 0.8, 0.0)
    clap_st = np.stack([clap_n_l * np.maximum(clap_trig, roll_trig), clap_n_r * np.maximum(clap_trig, roll_trig)]).astype(np.float32) * 0.42
    clap_fx = pb.Pedalboard([
        pb.Distortion(drive_db=3.5),
        pb.Reverb(room_size=0.45, damping=0.6, wet_level=0.28, dry_level=0.9),
    ])(clap_st, SR)

    # Crisp 909 closed/open hats + metallic ride
    b_hat, a_hat = signal.butter(2, 6200 / (0.5 * SR), btype="high")
    hat_n_l = signal.lfilter(b_hat, a_hat, noise_l)
    hat_n_r = signal.lfilter(b_hat, a_hat, noise_r)
    offbeat_env = np.where(beat_frac >= 0.5, np.exp(-(beat_frac - 0.5) * 20.0), 0.0)
    c16_env = np.exp(-step16_frac * 32.0) * np.where(step16 % 2 == 0, 0.32, 0.65)
    ride_env = offbeat_env * np.where(has_ride, 1.0, 0.0)
    # Subtle inharmonic metallic ring in ride
    ride_tone = np.sin(2 * np.pi * 3140.0 * t) * 0.25 + np.sin(2 * np.pi * 4870.0 * t) * 0.25
    hats_st = np.stack([
        (hat_n_l * (c16_env * 0.24 + offbeat_env * 0.42 + ride_env * 0.35) + ride_tone * ride_env * 0.08),
        (hat_n_r * (c16_env * 0.24 + offbeat_env * 0.42 + ride_env * 0.35) - ride_tone * ride_env * 0.08),
    ]).astype(np.float32) * 0.62

    # Subtle sweep riser across bar 11 leading into the bar 12 peak drop
    riser_mask = (bar_idx == 10) | (bar_idx == 11)
    riser_u = np.clip((beat_in_loop - 40.0) / 8.0, 0.0, 1.0)
    riser_sig = np.stack([clap_n_l, clap_n_r]).astype(np.float32) * (riser_u * riser_u * np.where(riser_mask, 0.24, 0.0))[np.newaxis, :]

    # SUM MIX & EXTRACT EXACT SEAMLESS LOOP PASS #2 [n_loop : 2*n_loop]
    mix_full = kick_clean + rumble + acid_fx + lead_fx + clap_fx + hats_st + riser_sig
    loop_seg = mix_full[:, n_loop:2 * n_loop].astype(np.float32)

    # MASTER BUS: Sub-cleanup + Glue Compression + Brickwall -0.8 dB Limiter
    master = pb.Pedalboard([
        pb.HighpassFilter(cutoff_frequency_hz=26.0),
        pb.Compressor(threshold_db=-12.0, ratio=3.2, attack_ms=8.0, release_ms=90.0),
        pb.Gain(gain_db=2.8),
        pb.Limiter(threshold_db=-0.8, release_ms=60.0),
    ])
    mastered = master(loop_seg, SR)

    # Zero-click 32-sample loop seam blend
    blend = 48
    w_in = (0.5 - 0.5 * np.cos(np.pi * np.arange(blend) / blend)).astype(np.float32)
    mastered[:, :blend] *= w_in[np.newaxis, :]
    mastered[:, -blend:] *= w_in[::-1][np.newaxis, :]
    mastered = np.clip(mastered, -0.98, 0.98)

    out_ogg = MUSIC_DIR / spec["file"]
    tmp_wav = MUSIC_DIR / f"_tmp_{spec['file']}.wav"
    encode_ogg_from_stereo(mastered, out_ogg, tmp_wav)
    rms = float(np.sqrt(np.mean(mastered ** 2)))
    print(f"  [OST] {spec['file']:14s} | {bpm:5.1f} BPM | {n_loop/SR:5.2f}s | RMS={rms:.3f} | {out_ogg.stat().st_size//1024} KB")


def generate_sfx_pack() -> None:
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(909)
    rev_short = pb.Pedalboard([pb.Reverb(room_size=0.45, damping=0.4, wet_level=0.35, dry_level=0.85), pb.Limiter(-1.0)])
    rev_wide = pb.Pedalboard([pb.Chorus(depth=0.25, mix=0.3), pb.Reverb(room_size=0.68, damping=0.35, wet_level=0.42, dry_level=0.82), pb.Limiter(-1.0)])

    def make_tone(dur: float, freqs: list[float], amp: float = 0.45, decay: float = 7.5, shimmer: bool = True) -> np.ndarray:
        n = int(round(dur * SR))
        t = np.arange(n, dtype=np.float64) / SR
        env = smoothstep(0.0, 0.004, t) * np.exp(-t * decay)
        l = np.zeros(n, dtype=np.float64)
        r = np.zeros(n, dtype=np.float64)
        for i, f in enumerate(freqs):
            det = 1.0 + (i - 0.5 * (len(freqs) - 1)) * 0.0035
            l += np.sin(2 * np.pi * f * det * t) + 0.25 * np.sin(4 * np.pi * f * det * t)
            r += np.sin(2 * np.pi * f / det * t) + 0.25 * np.sin(4 * np.pi * f / det * t)
        st = (np.stack([l, r]) / max(1, len(freqs)) * env * amp).astype(np.float32)
        return (rev_wide if shimmer else rev_short)(st, SR)

    cues: dict[str, np.ndarray] = {}
    cues["graze_1"] = make_tone(0.24, [740.0, 1108.73], amp=0.52, decay=11.0)
    cues["graze_2"] = make_tone(0.32, [880.0, 1318.51, 1760.0], amp=0.58, decay=8.5)
    cues["graze_3"] = make_tone(0.48, [1046.5, 1318.51, 1567.98, 2093.0], amp=0.65, decay=5.8)
    cues["ring"] = make_tone(0.32, [987.77, 1479.98, 1975.53], amp=0.52, decay=8.0)
    cues["checkpoint"] = make_tone(0.26, [587.33, 880.0], amp=0.50, decay=9.5)
    cues["section_up"] = make_tone(0.45, [293.66, 440.0, 587.33, 880.0], amp=0.58, decay=4.5)

    # Clear arpeggiated triumphant resolve
    n_clr = int(0.85 * SR)
    t_clr = np.arange(n_clr, dtype=np.float64) / SR
    clr_l = np.zeros(n_clr); clr_r = np.zeros(n_clr)
    for k, (f, t0) in enumerate([(523.25, 0.0), (659.25, 0.08), (783.99, 0.16), (1046.5, 0.25)]):
        m = np.maximum(0.0, t_clr - t0)
        e = np.where(t_clr >= t0, smoothstep(t0, t0 + 0.008, t_clr) * np.exp(-m * 4.5), 0.0)
        clr_l += np.sin(2 * np.pi * f * 0.997 * m) * e
        clr_r += np.sin(2 * np.pi * f * 1.003 * m) * e
    cues["clear"] = rev_wide((np.stack([clr_l, clr_r]) * 0.38).astype(np.float32), SR)

    # Flow lock bloom
    n_fl = int(0.65 * SR); t_fl = np.arange(n_fl, dtype=np.float64) / SR
    fl_hz = 110.0 + 550.0 * smoothstep(0.0, 0.35, t_fl)
    fl_ph = np.cumsum(fl_hz / SR)
    fl_sig = (np.sin(2 * np.pi * fl_ph) * 0.5 + np.sin(3 * np.pi * fl_ph) * 0.4) * smoothstep(0.0, 0.04, t_fl) * np.exp(-t_fl * 3.8)
    cues["flow_lock"] = rev_wide(np.stack([fl_sig, np.roll(fl_sig, 90)]).astype(np.float32) * 0.6, SR)

    # Boost on (jet ignition + sub punch)
    n_bo = int(0.32 * SR); t_bo = np.arange(n_bo, dtype=np.float64) / SR
    b_noise = rng.normal(0.0, 1.0, size=n_bo)
    b_bp, a_bp = signal.butter(2, [350 / (0.5 * SR), 3600 / (0.5 * SR)], btype="band")
    bo_n = signal.lfilter(b_bp, a_bp, b_noise) * smoothstep(0.0, 0.03, t_bo) * np.exp(-t_bo * 7.0)
    bo_sub = np.sin(2 * np.pi * np.cumsum((120.0 + 260.0 * t_bo) / SR)) * np.exp(-t_bo * 9.0) * 0.45
    cues["boost_on"] = rev_short(np.stack([bo_n * 0.42 + bo_sub, np.roll(bo_n, 45) * 0.42 + bo_sub]).astype(np.float32), SR)

    # Phase dash & phase parry
    n_pd = int(0.24 * SR); t_pd = np.arange(n_pd, dtype=np.float64) / SR
    pd_f = 1600.0 * np.exp(-t_pd * 12.0) + 320.0
    pd_s = np.sin(2 * np.pi * np.cumsum(pd_f / SR)) * smoothstep(0.0, 0.004, t_pd) * np.exp(-t_pd * 11.0)
    cues["phase_dash"] = rev_short(np.stack([pd_s * 0.65, np.roll(pd_s, 32) * 0.65]).astype(np.float32), SR)

    n_pp = int(0.45 * SR); t_pp = np.arange(n_pp, dtype=np.float64) / SR
    pp_sig = (np.sin(2 * np.pi * 1180.0 * t_pp) + np.sin(2 * np.pi * 1760.0 * t_pp) * 0.8 + np.sin(2 * np.pi * 2637.0 * t_pp) * 0.5) * np.exp(-t_pp * 7.5)
    cues["phase_parry"] = rev_wide(np.stack([pp_sig * 0.42, np.roll(pp_sig, 55) * 0.42]).astype(np.float32), SR)

    # Obstacle Doppler whoosh
    n_w = int(0.20 * SR); t_w = np.arange(n_w, dtype=np.float64) / SR
    w_noise = rng.normal(0.0, 1.0, size=n_w)
    bw, aw = signal.butter(2, [250 / (0.5 * SR), 1900 / (0.5 * SR)], btype="band")
    wn = signal.lfilter(bw, aw, w_noise) * np.sin(np.pi * (t_w / 0.20)) ** 1.4
    cues["whoosh"] = pb.Pedalboard([pb.Limiter(-1.5)])(np.stack([wn * 0.42, np.roll(wn, 60) * 0.42]).astype(np.float32), SR)

    # Death: massive sub impact + voxel crystal shatter
    n_d = int(0.65 * SR); t_d = np.arange(n_d, dtype=np.float64) / SR
    d_sub = np.sin(2 * np.pi * np.cumsum((190.0 * np.exp(-t_d * 18.0) + 34.0) / SR)) * np.exp(-t_d * 4.5) * 0.85
    d_shatter = rng.normal(0.0, 1.0, size=n_d) * np.exp(-t_d * 8.5) * 0.45
    death_raw = np.stack([d_sub + d_shatter, d_sub + np.roll(d_shatter, 85)]).astype(np.float32)
    cues["death"] = pb.Pedalboard([pb.Distortion(5.0), pb.Reverb(room_size=0.55, wet_level=0.32), pb.Limiter(-0.8)])(death_raw, SR)

    # Crisp tactile UI clicks
    n_uc = int(0.055 * SR); t_uc = np.arange(n_uc, dtype=np.float64) / SR
    uc = (np.sin(2 * np.pi * 1150.0 * t_uc) * 0.35 + np.sin(2 * np.pi * 520.0 * t_uc) * 0.45) * np.exp(-t_uc * 65.0)
    cues["ui_click"] = np.stack([uc, uc]).astype(np.float32)

    n_uh = int(0.032 * SR); t_uh = np.arange(n_uh, dtype=np.float64) / SR
    uh = np.sin(2 * np.pi * 1480.0 * t_uh) * np.exp(-t_uh * 95.0) * 0.30
    cues["ui_hover"] = np.stack([uh, uh]).astype(np.float32)

    for name, st in cues.items():
        fade = min(64, st.shape[1] // 8)
        st[:, -fade:] *= np.linspace(1.0, 0.0, fade, dtype=np.float32)[np.newaxis, :]
        st = np.clip(st, -0.98, 0.98)
        out_path = SFX_DIR / f"{name}.wav"
        save_stereo_wav(st, out_path)
    print(f"  [SFX] Generated {len(cues)} mastered stereo 44.1kHz WAV cues in {SFX_DIR}")


def main() -> None:
    if shutil.which("ffmpeg") is None:
        raise RuntimeError("ffmpeg is required on PATH to encode .ogg Vorbis tracks.")
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    print("[1/2] Synthesizing & mastering 7 stereo 44.1 kHz hard-techno / industrial tracks...")
    for spec in TRACK_SPECS:
        generate_track(spec)
    print("[2/2] Synthesizing & mastering 15 stereo 44.1 kHz SFX cues...")
    generate_sfx_pack()
    print("[OK] Audio production complete.")


if __name__ == "__main__":
    main()
