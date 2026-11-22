"""Composes the final 60s 1280x720 60fps Sensory Overload v3.0 hooked trailer MP4.

Synthesizes a 60.0s stereo cyber-synthwave soundtrack + synced SFX bursts (`media/trailer_audio.wav`),
overlays bold kinetic neon captions + transition flashes + CTA end-card onto `media/raw_trailer_60fps.avi`
via PIL/OpenCV, and encodes `media/SensoryOverload_60s_Trailer.mp4` via ffmpeg.
"""

from __future__ import annotations

import subprocess
import wave
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MEDIA_DIR = ROOT / "media"
RAW_AVI = MEDIA_DIR / "raw_trailer_60fps.avi"
AUDIO_WAV = MEDIA_DIR / "trailer_audio.wav"
OUT_MP4 = MEDIA_DIR / "SensoryOverload_60s_Trailer.mp4"

FPS = 60
DURATION = 60.0
SAMPLE_RATE = 44100


def load_font(size: int, style: str = "bold") -> ImageFont.FreeTypeFont:
    candidates = {
        "impact": [r"C:\Windows\Fonts\impact.ttf", r"C:\Windows\Fonts\segoeuib.ttf"],
        "bold": [r"C:\Windows\Fonts\segoeuib.ttf", r"C:\Windows\Fonts\bahnschrift.ttf", r"C:\Windows\Fonts\arialbd.ttf"],
        "mono": [r"C:\Windows\Fonts\consolab.ttf", r"C:\Windows\Fonts\segoeuib.ttf"],
    }[style]
    for p in candidates:
        if Path(p).exists():
            return ImageFont.truetype(p, size=size)
    return ImageFont.load_default()


def build_stereo_soundtrack(out_path: Path) -> None:
    n = int(DURATION * SAMPLE_RATE)
    t = np.arange(n, dtype=np.float64) / SAMPLE_RATE
    bpm = 136.0
    beat_sec = 60.0 / bpm
    beat_pos = t / beat_sec
    beat_num = np.floor(beat_pos).astype(np.int32)
    beat_frac = np.mod(beat_pos, 1.0)

    # Minor synthwave chord progression cycling across 4 bars (i -> VI -> III -> VII)
    roots_hz = np.array([110.0, 87.31, 130.81, 98.0], dtype=np.float64) # A2, F2, C3, G2
    bar_idx = (beat_num // 2) % 4
    root = roots_hz[bar_idx]

    # Driving 16th-note pulse & beat energy per narrative segment
    bar_energy = np.ones(n, dtype=np.float64)
    bar_energy[(t >= 0.0) & (t < 1.5)] = 0.55
    bar_energy[(t >= 3.6) & (t < 4.0)] = 0.25 # micro-drop silence before beat slam at 4.0s
    bar_energy[(t >= 46.0) & (t < 50.0)] = 0.52 # editor breakdown
    bar_energy[(t >= 50.0) & (t < 50.7)] = 0.20 # impact freeze tension

    # Kick drum (every beat outside silence drops)
    kick_active = np.where((t >= 4.0) & ((t < 46.0) | (t >= 51.3)), 1.0, 0.0)
    kick_freq = 44.0 + 130.0 * np.exp(-beat_frac * 26.0)
    kick_phase = np.cumsum(kick_freq / SAMPLE_RATE) * 2.0 * np.pi
    kick = np.sin(kick_phase) * np.exp(-beat_frac * 7.5) * 0.52 * kick_active

    # Rolling stereo bassline
    bass_phase = np.cumsum((root * 0.5) / SAMPLE_RATE)
    bass_saw = (bass_phase % 1.0) * 2.0 - 1.0
    sidechain = np.clip(beat_frac * 3.0, 0.14, 1.0)
    bass = (bass_saw * 0.35 + np.sin(2.0 * np.pi * bass_phase) * 0.65) * sidechain * 0.30 * bar_energy

    # Wide detuned supersaw pads (left & right channel phase spread)
    pad_l_p = np.cumsum((root * 1.992) / SAMPLE_RATE)
    pad_r_p = np.cumsum((root * 2.008) / SAMPLE_RATE)
    fifth_p = np.cumsum((root * 2.996) / SAMPLE_RATE)
    pad_l = (np.sin(2 * np.pi * pad_l_p) * 0.6 + ((pad_l_p % 1.0) - 0.5) * 0.4 + np.sin(2 * np.pi * fifth_p) * 0.35) * sidechain * 0.18 * bar_energy
    pad_r = (np.sin(2 * np.pi * pad_r_p) * 0.6 + ((pad_r_p % 1.0) - 0.5) * 0.4 + np.sin(2 * np.pi * fifth_p) * 0.35) * sidechain * 0.18 * bar_energy

    # Driving 16th-note melodic cyber arpeggio
    arp_mult = np.array([1.0, 1.189, 1.498, 2.0, 1.498, 1.189, 1.335, 1.782])
    s16_idx = np.floor(beat_pos * 4.0).astype(np.int32)
    s16_frac = np.mod(beat_pos * 4.0, 1.0)
    arp_hz = root * 2.0 * arp_mult[s16_idx % len(arp_mult)]
    arp_p = np.cumsum(arp_hz / SAMPLE_RATE)
    arp_env = np.minimum(1.0, s16_frac * 12.0) * np.exp(-s16_frac * 4.8)
    arp_wave = (np.sin(2 * np.pi * arp_p) * 0.65 + np.sin(4 * np.pi * arp_p) * 0.25) * arp_env * 0.22 * bar_energy

    # Crisp snare/clap on beats 2,4,6,8 + 16th hats
    rng = np.random.default_rng(42)
    noise = rng.uniform(-1.0, 1.0, size=n)
    snare_on = np.where((beat_num % 2) == 1, 1.0, 0.0) * kick_active
    snare = noise * np.exp(-beat_frac * 16.0) * snare_on * 0.20
    hat_frac = np.mod(beat_pos * 2.0 + 0.5, 1.0)
    hat_env = np.where((t >= 22.0) | ((beat_num % 2) == 1), 1.0, 0.45) * bar_energy
    hats = noise * np.exp(-hat_frac * 28.0) * 0.09 * hat_env

    left = kick + bass + pad_l + arp_wave * 1.08 + snare * 0.92 + hats * 0.85
    right = kick + bass + pad_r + arp_wave * 0.92 + snare * 1.08 + hats * 1.15

    # Helper to inject crisp SFX cues at exact trailer timestamps
    def add_sweep(t0: float, dur: float, f0: float, f1: float, amp: float = 0.42, pan: float = 0.0, add_noise: float = 0.0) -> None:
        i0 = max(0, int(t0 * SAMPLE_RATE))
        i1 = min(n, int((t0 + dur) * SAMPLE_RATE))
        if i1 <= i0:
            return
        u = np.linspace(0.0, 1.0, i1 - i0)
        freq = f0 + (f1 - f0) * u
        ph = np.cumsum(freq / SAMPLE_RATE)
        env = np.sin(np.pi * np.minimum(1.0, u * 6.0)) * np.exp(-u * 3.8)
        sig = (np.sin(2 * np.pi * ph) + 0.35 * np.sin(3 * np.pi * ph)) * env * amp
        if add_noise > 0.0:
            sig += rng.uniform(-1.0, 1.0, size=i1 - i0) * env * amp * add_noise
        left[i0:i1] += sig * (1.0 - max(0.0, pan) * 0.5)
        right[i0:i1] += sig * (1.0 + min(0.0, pan) * 0.5)

    # Cold-open Phase Parry explosion & sub drop
    add_sweep(0.05, 1.55, 55.0, 240.0, amp=0.28, add_noise=0.25) # riser
    add_sweep(1.65, 0.28, 720.0, 1820.0, amp=0.48, add_noise=0.20) # phase parry crystal hit!
    add_sweep(4.00, 0.40, 160.0, 42.0, amp=0.55, add_noise=0.18) # title slam bass hit

    # Ring & graze chimes during Core Loop (10-22s)
    for rt in [11.4, 13.1, 14.8, 17.2, 18.9, 20.5]:
        add_sweep(rt, 0.24, 880.0, 1520.0, amp=0.28, pan=np.sin(rt))
    # Overdrive Boost + Flow Lock + Cuts
    add_sweep(22.0, 0.45, 220.0, 960.0, amp=0.38, add_noise=0.45)
    add_sweep(26.5, 0.55, 523.25, 1046.5, amp=0.34)
    for cut_t in [34.0, 37.0, 40.0, 43.0, 46.0]:
        add_sweep(cut_t, 0.16, 480.0, 120.0, amp=0.24, add_noise=0.6)
    # Crimson crash impact + instant retry + finale boom
    add_sweep(50.10, 0.42, 190.0, 34.0, amp=0.55, add_noise=0.45)
    add_sweep(51.35, 0.25, 440.0, 1180.0, amp=0.35)
    add_sweep(53.00, 0.50, 150.0, 40.0, amp=0.52, add_noise=0.22)

    # Master limiter + fade in/out
    left = np.tanh(left * 1.15) * 0.88
    right = np.tanh(right * 1.15) * 0.88
    fade_n = int(0.08 * SAMPLE_RATE)
    left[:fade_n] *= np.linspace(0.0, 1.0, fade_n)
    right[:fade_n] *= np.linspace(0.0, 1.0, fade_n)
    fade_out = int(0.8 * SAMPLE_RATE)
    left[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)
    right[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)

    stereo = np.stack([left, right], axis=1)
    pcm16 = np.clip(np.round(stereo * 32767.0), -32768, 32767).astype(np.int16)
    with wave.open(str(out_path), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm16.tobytes())


def draw_centered_pill_text(
    img: Image.Image,
    text: str,
    y_center: int,
    font: ImageFont.FreeTypeFont,
    fg: tuple[int, int, int, int],
    border_col: tuple[int, int, int, int] = (20, 241, 217, 235),
    bg_col: tuple[int, int, int, int] = (8, 5, 22, 200),
    pad_x: int = 26,
    pad_y: int = 10,
) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    cx = img.width // 2
    x0 = cx - tw // 2 - pad_x
    x1 = cx + tw // 2 + pad_x
    y0 = y_center - th // 2 - pad_y
    y1 = y_center + th // 2 + pad_y
    if bg_col[3] > 0 or border_col[3] > 0:
        draw.rounded_rectangle([x0, y0, x1, y1], radius=10, fill=bg_col, outline=border_col if border_col[3] > 0 else None, width=3)
    draw.text((cx - tw // 2 - bbox[0], y_center - th // 2 - bbox[1]), text, font=font, fill=fg)


def main() -> None:
    if not RAW_AVI.exists():
        raise FileNotFoundError(f"Missing raw Godot capture: {RAW_AVI}")

    print("[1/3] Synthesizing 60s stereo cyber-synthwave soundtrack & SFX...")
    build_stereo_soundtrack(AUDIO_WAV)

    f_hero = load_font(78, "impact")
    f_big = load_font(42, "impact")
    f_sub = load_font(26, "bold")
    f_cta = load_font(30, "bold")
    f_tag = load_font(22, "mono")

    cap = cv2.VideoCapture(str(RAW_AVI))
    total_raw = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f"[2/3] Compositing kinetic trailer overlays onto {total_raw} GPU frames @ {FPS}fps...")

    ff_cmd = [
        "ffmpeg", "-y",
        "-f", "rawvideo",
        "-vcodec", "rawvideo",
        "-pix_fmt", "bgr24",
        "-s", "1280x720",
        "-r", str(FPS),
        "-i", "-",
        "-i", str(AUDIO_WAV),
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "19",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        "-b:a", "192k",
        "-movflags", "+faststart",
        "-shortest",
        str(OUT_MP4),
    ]
    proc = subprocess.Popen(ff_cmd, stdin=subprocess.PIPE)
    assert proc.stdin is not None

    cut_times = [4.0, 10.0, 16.0, 22.0, 34.0, 37.0, 40.0, 43.0, 46.0, 49.5, 53.0]
    captions = [
        (0.15, 3.85, "BLINK THROUGH THE IMPOSSIBLE", 112, (250, 204, 21, 255), (255, 46, 147, 240)),
        (10.3, 15.7, "DODGE  ·  THREAD RINGS  ·  GRAZE THE EDGE", 626, (255, 255, 255, 255), (20, 241, 217, 240)),
        (16.3, 21.7, "BUILD CHAINS UP TO 8.0x SCORE", 626, (250, 204, 21, 255), (56, 189, 248, 240)),
        (22.3, 27.6, "HOLD CLICK TO HYPER-BOOST (155 M/S)", 626, (250, 204, 21, 255), (255, 46, 147, 240)),
        (28.0, 33.7, "RIGHT-CLICK: PHASE BLINK & PARRY HAZARDS", 626, (20, 241, 217, 255), (250, 204, 21, 240)),
        (34.3, 39.7, "21 STAGES  ·  10 DEADLY 3D ARCHETYPES", 626, (255, 255, 255, 255), (20, 241, 217, 240)),
        (40.3, 45.7, "24-BIT VISUAL OVERDRIVE  (+ SAFE MODE)", 626, (255, 112, 166, 255), (232, 121, 249, 240)),
        (46.2, 49.3, "CREATE & PLAY CUSTOM LEVELS IN 3D EDITOR", 626, (20, 241, 217, 255), (56, 189, 248, 240)),
        (49.7, 52.8, "ZERO WAIT  ·  INSTANT RETRY LOOP", 626, (251, 113, 133, 255), (255, 46, 147, 240)),
    ]

    idx = 0
    max_frames = int(DURATION * FPS)
    while idx < max_frames:
        ok, frame_bgr = cap.read()
        if not ok:
            break
        if frame_bgr.shape[1] != 1280 or frame_bgr.shape[0] != 720:
            frame_bgr = cv2.resize(frame_bgr, (1280, 720), interpolation=cv2.INTER_AREA)
        t = idx / float(FPS)

        # Beat-cut subtle cyan/white transition flash
        flash_alpha = 0.0
        for ct in cut_times:
            dt = t - ct
            if 0.0 <= dt < 0.14:
                flash_alpha = max(flash_alpha, (1.0 - dt / 0.14) * 0.42)
        if flash_alpha > 0.01:
            white = np.full_like(frame_bgr, (255, 245, 215))
            frame_bgr = cv2.addWeighted(frame_bgr, 1.0 - flash_alpha, white, flash_alpha, 0)

        # Overlay kinetic UI / typography with PIL RGBA
        need_pil = (4.0 <= t < 10.0) or (t >= 53.0) or any(c[0] <= t <= c[1] for c in captions)
        if need_pil:
            pil_img = Image.fromarray(cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)).convert("RGBA")

            if 4.0 <= t < 10.0:
                draw_centered_pill_text(
                    pil_img, "SENSORY OVERLOAD", 315, f_hero,
                    (255, 255, 255, 255), (20, 241, 217, 245), (8, 4, 20, 205), pad_x=42, pad_y=18
                )
                draw_centered_pill_text(
                    pil_img, "HIGH-SPEED CYBER TUNNEL ARCADE  ·  v3.0", 412, f_sub,
                    (20, 241, 217, 255), (255, 46, 147, 235), (8, 4, 20, 215), pad_x=28, pad_y=10
                )

            for t0, t1, txt, yc, fg, border in captions:
                if t0 <= t <= t1:
                    draw_centered_pill_text(pil_img, txt, yc, f_big if t < 4.0 else f_sub, fg, border)

            if t >= 53.0:
                d = ImageDraw.Draw(pil_img, "RGBA")
                d.rounded_rectangle([220, 128, 1060, 588], radius=16, fill=(7, 3, 20, 224), outline=(20, 241, 217, 245), width=4)
                draw_centered_pill_text(
                    pil_img, "SENSORY OVERLOAD", 205, f_hero,
                    (255, 255, 255, 255), (255, 46, 147, 0), (0, 0, 0, 0), pad_x=0, pad_y=0
                )
                draw_centered_pill_text(
                    pil_img, "v3.0  ·  FREE 1-CLICK PLAY  ·  WINDOWS & LINUX", 288, f_cta,
                    (20, 241, 217, 255), (0, 0, 0, 0), (0, 0, 0, 0), pad_x=0, pad_y=0
                )
                draw_centered_pill_text(
                    pil_img, "THINK YOU CAN BEAT LEVEL 6? PROVE IT.", 368, f_big,
                    (250, 204, 21, 255), (250, 204, 21, 235), (25, 16, 48, 220), pad_x=28, pad_y=12
                )
                draw_centered_pill_text(
                    pil_img, "DOWNLOAD NOW:  github.com/lam3y35/sensory-overload-godot", 468, f_tag,
                    (248, 250, 252, 255), (56, 189, 248, 230), (14, 10, 34, 225), pad_x=22, pad_y=10
                )
                draw_centered_pill_text(
                    pil_img, "GODOT 4 CLEAN-ROOM EDITION  ·  NO INSTALL NEEDED", 538, f_tag,
                    (148, 163, 184, 255), (0, 0, 0, 0), (0, 0, 0, 0), pad_x=0, pad_y=0
                )

            frame_bgr = cv2.cvtColor(np.array(pil_img.convert("RGB")), cv2.COLOR_RGB2BGR)

        proc.stdin.write(frame_bgr.tobytes())
        idx += 1

    cap.release()
    proc.stdin.close()
    rc = proc.wait()
    if rc != 0:
        raise RuntimeError(f"ffmpeg exited with code {rc}")
    print(f"[3/3] Encoded {idx} frames into {OUT_MP4} ({OUT_MP4.stat().st_size / 1048576:.2f} MB)")


if __name__ == "__main__":
    main()
