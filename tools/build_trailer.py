"""Composes the final 60s 1280x720 60fps Sensory Overload v4.0 trailer MP4.

Assembles a 60.0s studio-mastered 44.1 kHz stereo hard-techno soundtrack from our pedalboard-mastered
`.ogg` tracks (`assets/audio/music/track_05.ogg`, `track_06.ogg`) + stereo foley SFX (`assets/audio/sfx/*.wav`),
overlays stark brutalist typography using bundled OFL fonts (`RussoOne-Regular.ttf`, `ChakraPetch-BoldItalic.ttf`,
`ChakraPetch-Bold.ttf`), and encodes `media/SensoryOverload_60s_Trailer.mp4` via ffmpeg.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
import cv2
import numpy as np
import soundfile as sf
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MEDIA_DIR = ROOT / "media"
FONTS_DIR = ROOT / "assets" / "fonts"
MUSIC_DIR = ROOT / "assets" / "audio" / "music"
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
RAW_AVI = MEDIA_DIR / "raw_trailer_60fps.avi"
AUDIO_WAV = MEDIA_DIR / "trailer_audio.wav"
OUT_MP4 = MEDIA_DIR / "SensoryOverload_60s_Trailer.mp4"

FPS = 60
DURATION = 60.0
SAMPLE_RATE = 44100


def load_font(size: int, style: str = "bold") -> ImageFont.FreeTypeFont:
    candidates = {
        "display": [str(FONTS_DIR / "RussoOne-Regular.ttf"), r"C:\Windows\Fonts\impact.ttf"],
        "italic": [str(FONTS_DIR / "ChakraPetch-BoldItalic.ttf"), str(FONTS_DIR / "ChakraPetch-Bold.ttf")],
        "bold": [str(FONTS_DIR / "ChakraPetch-Bold.ttf"), r"C:\Windows\Fonts\segoeuib.ttf"],
        "mono": [str(FONTS_DIR / "ChakraPetch-SemiBold.ttf"), r"C:\Windows\Fonts\consolab.ttf"],
    }[style]
    for p in candidates:
        if Path(p).exists():
            return ImageFont.truetype(p, size=size)
    return ImageFont.load_default()


def _load_stereo_clip(path: Path) -> np.ndarray:
    data, sr = sf.read(str(path), dtype="float32", always_2d=True)
    if data.shape[1] == 1:
        data = np.repeat(data, 2, axis=1)
    return data


def build_stereo_soundtrack(out_path: Path) -> None:
    n = int(DURATION * SAMPLE_RATE)
    t = np.arange(n, dtype=np.float32) / SAMPLE_RATE

    # Load our pedalboard-mastered hard-techno tracks and loop/crossfade across the 60s trailer arc
    trk5 = _load_stereo_clip(MUSIC_DIR / "track_05.ogg")
    trk6 = _load_stereo_clip(MUSIC_DIR / "track_06.ogg")

    def loop_to_len(clip: np.ndarray, total_samples: int) -> np.ndarray:
        reps = (total_samples // len(clip)) + 2
        tiled = np.tile(clip, (reps, 1))
        return tiled[:total_samples].copy()

    bed_a = loop_to_len(trk5, n)
    bed_b = loop_to_len(trk6, n)

    # Crossfade from Track 05 (0..22s) into high-velocity Track 06 (22..60s)
    xfade = np.clip((t - 21.5) / 1.0, 0.0, 1.0)[:, None]
    music = bed_a * (1.0 - xfade) + bed_b * xfade

    # Dynamic energy automation for dramatic drop at 4.0s and crash freeze at 50.0s
    env = np.ones(n, dtype=np.float32)
    env[(t >= 0.0) & (t < 1.5)] = 0.72
    env[(t >= 3.55) & (t < 4.0)] = 0.22  # tension pre-drop before 4.0s title slam
    env[(t >= 46.0) & (t < 49.5)] = 0.65  # editor showcase breather
    env[(t >= 50.05) & (t < 51.25)] = 0.18  # crimson impact freeze silence
    music *= env[:, None] * 0.84

    def overlay_sfx(name: str, t_sec: float, gain: float = 0.75) -> None:
        p = SFX_DIR / f"{name}.wav"
        if not p.exists():
            return
        clip = _load_stereo_clip(p) * gain
        i0 = max(0, int(t_sec * SAMPLE_RATE))
        i1 = min(n, i0 + len(clip))
        if i1 > i0:
            music[i0:i1] += clip[: i1 - i0]

    # Synced foley SFX cues from our mastered stereo WAV bank
    overlay_sfx("boost_on", 0.08, 0.75)
    overlay_sfx("phase_parry", 1.65, 0.92)
    overlay_sfx("section_up", 4.00, 0.90)

    for idx_g, gt in enumerate([11.4, 13.1, 14.8, 17.2, 18.9, 20.5]):
        overlay_sfx(f"graze_{(idx_g % 3) + 1}", gt, 0.72)
    for rt in [12.2, 15.5, 19.6]:
        overlay_sfx("ring", rt, 0.78)

    overlay_sfx("boost_on", 22.0, 0.88)
    overlay_sfx("flow_lock", 26.5, 0.92)
    overlay_sfx("phase_dash", 28.4, 0.85)
    overlay_sfx("phase_parry", 31.2, 0.90)

    for cut_t in [34.0, 37.0, 40.0, 43.0, 46.0]:
        overlay_sfx("whoosh", cut_t, 0.70)

    overlay_sfx("death", 50.08, 0.95)
    overlay_sfx("checkpoint", 51.35, 0.82)
    overlay_sfx("clear", 53.00, 0.88)

    # Fade in/out & brickwall safety clip
    fade_in = int(0.08 * SAMPLE_RATE)
    fade_out = int(0.85 * SAMPLE_RATE)
    music[:fade_in] *= np.linspace(0.0, 1.0, fade_in, dtype=np.float32)[:, None]
    music[-fade_out:] *= np.linspace(1.0, 0.0, fade_out, dtype=np.float32)[:, None]
    music = np.clip(music, -0.98, 0.98)

    sf.write(str(out_path), music, SAMPLE_RATE, subtype="PCM_16")


def draw_brutalist_banner(
    img: Image.Image,
    text: str,
    y_center: int,
    font: ImageFont.FreeTypeFont,
    fg: tuple[int, int, int, int] = (248, 250, 252, 255),
    accent_col: tuple[int, int, int, int] = (255, 159, 28, 255),
    bg_col: tuple[int, int, int, int] = (10, 11, 15, 228),
    pad_x: int = 28,
    pad_y: int = 11,
) -> None:
    """Stark brutalist carbon banner with sharp corners and a thick left-edge amber/crimson bar."""
    draw = ImageDraw.Draw(img, "RGBA")
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    cx = img.width // 2
    x0 = cx - tw // 2 - pad_x
    x1 = cx + tw // 2 + pad_x
    y0 = y_center - th // 2 - pad_y
    y1 = y_center + th // 2 + pad_y
    if bg_col[3] > 0:
        draw.rectangle([x0, y0, x1, y1], fill=bg_col, outline=(42, 46, 58, 230), width=1)
    if accent_col[3] > 0:
        draw.rectangle([x0, y0, x0 + 6, y1], fill=accent_col)
        draw.rectangle([x1 - 3, y0, x1, y1], fill=(accent_col[0], accent_col[1], accent_col[2], 140))
    # Hard 2px drop shadow for crisp readability over high-contrast voxels
    tx = cx - tw // 2 - bbox[0]
    ty = y_center - th // 2 - bbox[1]
    draw.text((tx + 2, ty + 2), text, font=font, fill=(0, 0, 0, 235))
    draw.text((tx, ty), text, font=font, fill=fg)


def draw_chromatic_hero_title(
    img: Image.Image,
    text: str,
    y_center: int,
    font: ImageFont.FreeTypeFont,
) -> None:
    """Draws the signature SENSORY OVERLOAD white display title with cyan/crimson chromatic offset."""
    draw = ImageDraw.Draw(img, "RGBA")
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = img.width // 2 - tw // 2 - bbox[0]
    ty = y_center - th // 2 - bbox[1]
    draw.text((tx - 4, ty - 2), text, font=font, fill=(0, 229, 255, 220))
    draw.text((tx + 4, ty + 3), text, font=font, fill=(255, 30, 60, 230))
    draw.text((tx, ty), text, font=font, fill=(255, 255, 255, 255))


def main() -> None:
    if not RAW_AVI.exists():
        raise FileNotFoundError(f"Missing raw Godot capture: {RAW_AVI}")

    print("[1/3] Mastering 60s stereo hard-techno soundtrack & foley SFX...")
    build_stereo_soundtrack(AUDIO_WAV)

    f_hero = load_font(76, "display")
    f_big = load_font(36, "italic")
    f_sub = load_font(25, "italic")
    f_cta = load_font(27, "bold")
    f_tag = load_font(21, "mono")

    # Decode raw_trailer_60fps.avi via ffmpeg pipe scaled to 1280x720 to avoid OpenCV >4GB AVI 32-bit Riff limit
    print(f"[2/3] Compositing brutalist v4.0 overlays onto {int(DURATION * FPS)} GPU frames @ {FPS}fps...")
    dec_cmd = [
        "ffmpeg", "-v", "error",
        "-i", str(RAW_AVI),
        "-vf", "scale=1280:720",
        "-f", "rawvideo",
        "-pix_fmt", "bgr24",
        "-",
    ]
    dec_proc = subprocess.Popen(dec_cmd, stdout=subprocess.PIPE)
    assert dec_proc.stdout is not None

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
        "-crf", "18",
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
    AMBER = (255, 159, 28, 255)
    CRIMSON = (255, 30, 60, 255)
    CYAN = (56, 189, 248, 255)
    WHITE = (248, 250, 252, 255)

    captions = [
        (0.15, 3.85, "DROP AT 96 CUBES/S — THREAD THE NEEDLE", 104, WHITE, CRIMSON),
        (10.3, 15.7, "CARVED 3D VOXEL SHAFTS  //  NEAR-MISS GRAZE SCORING", 642, WHITE, AMBER),
        (16.3, 21.7, "CHAIN RINGS & GRAZES UP TO X8 MULTIPLIER", 642, AMBER, CYAN),
        (22.3, 27.6, "LEFT-CLICK: OVERDRIVE BOOST  //  FLOW COLOR LOCK", 642, WHITE, CRIMSON),
        (28.0, 33.7, "RIGHT-CLICK: PHASE DASH & PARRY THROUGH BARRIERS", 642, CYAN, AMBER),
        (34.3, 39.7, "21 CAMPAIGN STAGES  //  10 TRANSLUCENT VOXEL ARCHETYPES", 642, WHITE, AMBER),
        (40.3, 45.7, "24-BIT SHADER MUTATORS  //  148 BPM HARD-TECHNO OST", 642, AMBER, CRIMSON),
        (46.2, 49.3, "BUILT-IN 3D VOXEL LEVEL EDITOR & REPLAY SYSTEM", 642, WHITE, CYAN),
        (49.7, 52.8, "INSTANT <0.1S RETRY LOOP — ZERO LOADING SCREENS", 642, WHITE, CRIMSON),
    ]

    idx = 0
    max_frames = int(DURATION * FPS)
    frame_bytes = 1280 * 720 * 3
    while idx < max_frames:
        raw_buf = dec_proc.stdout.read(frame_bytes)
        if len(raw_buf) < frame_bytes:
            break
        frame_bgr = np.frombuffer(raw_buf, dtype=np.uint8).reshape((720, 1280, 3)).copy()
        t = idx / float(FPS)

        # Crisp beat-cut flash
        flash_alpha = 0.0
        for ct in cut_times:
            dt = t - ct
            if 0.0 <= dt < 0.12:
                flash_alpha = max(flash_alpha, (1.0 - dt / 0.12) * 0.36)
        if flash_alpha > 0.01:
            white = np.full_like(frame_bgr, (245, 248, 255))
            frame_bgr = cv2.addWeighted(frame_bgr, 1.0 - flash_alpha, white, flash_alpha, 0)

        need_pil = (4.0 <= t < 10.0) or (t >= 53.0) or any(c[0] <= t <= c[1] for c in captions)
        if need_pil:
            pil_img = Image.fromarray(cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)).convert("RGBA")

            if 4.0 <= t < 10.0:
                d = ImageDraw.Draw(pil_img, "RGBA")
                d.rectangle([230, 235, 1050, 465], fill=(8, 9, 13, 212), outline=(42, 46, 58, 235), width=1)
                d.rectangle([230, 235, 238, 465], fill=AMBER)
                d.rectangle([1042, 235, 1050, 465], fill=CRIMSON)
                draw_chromatic_hero_title(pil_img, "SENSORY OVERLOAD", 315, f_hero)
                draw_brutalist_banner(
                    pil_img, "HIGH-VELOCITY 3D VOXEL DROPPER  //  v4.0 OVERHAUL", 412, f_sub,
                    AMBER, CRIMSON, (14, 16, 22, 240), pad_x=26, pad_y=9
                )

            for t0, t1, txt, yc, fg, accent in captions:
                if t0 <= t <= t1:
                    draw_brutalist_banner(pil_img, txt, yc, f_big if t < 4.0 else f_sub, fg, accent)

            if t >= 53.0:
                d = ImageDraw.Draw(pil_img, "RGBA")
                d.rectangle([190, 124, 1090, 596], fill=(8, 9, 13, 232), outline=(48, 52, 66, 245), width=2)
                d.rectangle([190, 124, 198, 596], fill=AMBER)
                d.rectangle([1082, 124, 1090, 596], fill=CRIMSON)
                draw_chromatic_hero_title(pil_img, "SENSORY OVERLOAD", 205, f_hero)
                draw_brutalist_banner(
                    pil_img, "v4.0  //  21 STAGES  ·  HARD-TECHNO OST  ·  WINDOWS & LINUX", 290, f_cta,
                    WHITE, AMBER, (16, 18, 25, 235), pad_x=24, pad_y=8
                )
                draw_brutalist_banner(
                    pil_img, "CAN YOU SURVIVE LEVEL 7 AT 96 CUBES/S?", 374, f_big,
                    AMBER, CRIMSON, (16, 18, 25, 245), pad_x=28, pad_y=11
                )
                draw_brutalist_banner(
                    pil_img, "1-CLICK DOWNLOAD:  github.com/lam3y35/sensory-overload-godot", 468, f_tag,
                    WHITE, CYAN, (14, 16, 22, 240), pad_x=22, pad_y=9
                )
                draw_brutalist_banner(
                    pil_img, "GODOT 4 CLEAN-ROOM RECONSTRUCTION  //  FREE & OPEN SOURCE", 540, f_tag,
                    (165, 174, 190, 255), (0, 0, 0, 0), (0, 0, 0, 0), pad_x=0, pad_y=0
                )

            frame_bgr = cv2.cvtColor(np.array(pil_img.convert("RGB")), cv2.COLOR_RGB2BGR)

        proc.stdin.write(frame_bgr.tobytes())
        idx += 1

    dec_proc.stdout.close()
    dec_proc.wait()
    proc.stdin.close()
    rc = proc.wait()
    if rc != 0:
        raise RuntimeError(f"ffmpeg exited with code {rc}")
    print(f"[3/3] Encoded {idx} frames into {OUT_MP4} ({OUT_MP4.stat().st_size / 1048576:.2f} MB)")


if __name__ == "__main__":
    main()
