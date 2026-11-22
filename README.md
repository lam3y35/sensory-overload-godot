# Sensory Overload — Godot 4 Clean-Room Reconstruction (`v3.0.0`)

[![Download Windows x64](https://img.shields.io/badge/⬇_ONE--CLICK_DOWNLOAD-Windows_x64_(ZIP)-14F1D9?style=for-the-badge&logo=windows&logoColor=0A0618&labelColor=0A0618)](https://github.com/lam3y35/sensory-overload-godot/releases/latest/download/SensoryOverload-Windows-x64.zip)
[![Direct EXE](https://img.shields.io/badge/Direct_Standalone-.EXE_(Windows_x64)-FF2E93?style=for-the-badge)](https://github.com/lam3y35/sensory-overload-godot/releases/latest/download/SensoryOverload-Windows-x64.exe)
[![Download Linux x64](https://img.shields.io/badge/Download-Linux_x64_(tar.gz)-FACC15?style=for-the-badge&logo=linux&logoColor=white&labelColor=1F1638)](https://github.com/lam3y35/sensory-overload-godot/releases/latest/download/SensoryOverload-Linux-x64.tar.gz)
[![60s Trailer](https://img.shields.io/badge/🎬_WATCH-60s_Gameplay_Trailer_(MP4)-38BDF8?style=for-the-badge)](https://github.com/lam3y35/sensory-overload-godot/releases/latest/download/SensoryOverload_60s_Trailer.mp4)

An independent, clean-room **Godot 4 + GDScript** reconstruction of high-speed 3D voxel-tunnel arcade gameplay, built with **100% original source code, Early-Z opaque + glow GLSL shaders, procedural cyber-synthwave audio, Hyper-Boost, Phase Blink / Parry mechanics, collectible Energy Rings, and handcrafted campaign stages**.

---

## Play in One Click (No Godot Install Required)

1. Click **[⬇ ONE-CLICK DOWNLOAD (Windows x64 ZIP)](https://github.com/lam3y35/sensory-overload-godot/releases/latest/download/SensoryOverload-Windows-x64.zip)** *(or grab the direct standalone [`SensoryOverload-Windows-x64.exe`](https://github.com/lam3y35/sensory-overload-godot/releases/latest/download/SensoryOverload-Windows-x64.exe), [`SensoryOverload-Linux-x64.tar.gz`](https://github.com/lam3y35/sensory-overload-godot/releases/latest/download/SensoryOverload-Linux-x64.tar.gz), or download the **[60s Gameplay Trailer (`SensoryOverload_60s_Trailer.mp4`)](https://github.com/lam3y35/sensory-overload-godot/releases/latest/download/SensoryOverload_60s_Trailer.mp4)**)*.
2. Extract (if using the ZIP/tar.gz) and run **`SensoryOverload.exe`**.
3. **No Vulkan GPU?** Run with OpenGL 3.3 Compatibility mode:
   ```powershell
   SensoryOverload.exe --rendering-driver opengl3
   ```

---

## Screenshots (`v3.0.0` Live GPU Captures)

| Main Menu (1-Click Quick Dive) | Tunnel Descent & Energy Rings |
| :---: | :---: |
| ![Main Menu](docs/screenshots/01_main_menu.png) | ![Normal Gameplay](docs/screenshots/05_normal_gameplay.png) |

| Overdrive Boost, Milestones & Phase Diamond | Sensory Overload FX (60 FPS Locked) |
| :---: | :---: |
| ![Graze and Flow](docs/screenshots/06_graze_and_flow.png) | ![Sensory Overload FX](docs/screenshots/10_sensory_overload_fx.png) |

| Built-in 3D Level Editor |
| :---: |
| ![Level Editor](docs/screenshots/14_level_editor.png) |

---

## Key Features (`v3.0.0` Performance + Joy Overhaul)

- **High-FPS Early-Z Architecture:** Hardware opaque Early-Z obstacle shader (`obstacle_opaque.gdshader`), pooled recycled obstacle meshes (zero runtime `queue_free`/`new` churn), 64× faster modulo ring-buffer tunnel updates, 1-draw-call MultiMesh Energy Rings, idle full-screen copy skip in `EffectCompositor`, and decoupled 120 Hz logic sub-stepping + once-per-frame GPU sync (`~1.05 ms/frame` CPU render time at `1920x1080`, `60.0 FPS` steady in full 10-FX chaos).
- **Phase Blink & Phase Parry (`Right Click` / `E`):** Invulnerability micro-dash across tight obstacle gaps; timing a blink straight through a deadly hazard triggers a **`26 ms` hit-stop**, **PHASE PARRY! (`+800 * Chain`)** callout, spark burst, crystalline harmonic chime, and **instant cooldown reset** — also refreshed instantly on Energy Ring pickups & Death Wish grazes.
- **Active Hyper-Boost & 3D Speed Streaks (`Hold Left Click` / `Shift` / `Space`):** Surge speed `1.48x` (up to `155 m/s`), double distance scoring, expand peripheral FOV, and ignite golden 3D MultiMesh speed-streak needles.
- **Collectible Energy Rings:** Glowing 12-segment gold-cyan hoops threaded along safe corridors award `+300 * Chain` pts, build Flow toward **Overdrive Color Lock**, trigger rising pitch-scaled synth chimes, and refresh Phase Blink.
- **Crisp Dark-Cyber Visuals & Zero Glitches:** Non-coplanar Z-fighting fixes, smooth distance depth cueing & far fade-in (`168 m -> 128 m`), seamless kaleidoscope polar blending, crimson-orange impact alerts, and roll-compensated Mouse/Keyboard/Gamepad steering with zero double-integration drift.
- **10 Dynamic 3D Obstacle Archetypes & 5 Playable Modes:** Normal Campaign (`21` stages / `7` tiers + `▶ PLAY NOW` Quick Dive), Practice (`C`/`X` Checkpoints), Zen, Ranked Endless (`WATCH` 60 Hz Replays + leaderboards), and All Hallows'.
- **Warm 8-Beat Cyber-Synthwave Audio & Built-In 3D Editor:** Procedurally synthesized BPM-synced music + Menu Ambient + visual level authoring with `Play From Here`.

---

## Controls

| Input | Action |
| :--- | :--- |
| **Mouse** (or **WASD** / **Arrow Keys**) | Steer laterally inside the 3D voxel tunnel (roll-compensated) |
| **Hold Left Click** / **Shift** / **Space** | **Hyper-Boost** (`1.48x` speed + `2x` distance score + Flow gain) |
| **Right Click** / **E** | **Phase Blink & Parry** (invulnerability dash; blink through hazards to Parry `+800x` & reset cooldown) |
| **C** / **X** | Place / Clear Checkpoint *(Practice Mode)* |
| **R** / **Space** *(on Death)* | Instant Retry |
| **Enter** / **Space** *(on Clear)* | Launch Next Campaign Stage |
| **Esc** / **P** | Pause / Resume |

---

## Running from Source & Automated Verification

Requires **Godot 4.7.2+** (`godot` / `godot_console`) and **Python 3.10+**:

```bash
# 1. Static integrity & schema validation
python tools/validate_godot_project.py

# 2. Run headless unit & integration suites (6 suites, 106 assertions)
godot_console --headless --path . res://tests/test_runner.tscn

# 3. Launch the game in Godot
godot --path .
```

See [`docs/QA_REPORT.md`](docs/QA_REPORT.md) for the complete QA findings, `v2.0.0`/`v3.0.0` verification metrics, and [`docs/GAME_DESIGN_DOCUMENT.md`](docs/GAME_DESIGN_DOCUMENT.md) for architecture details.

---

## Clean-Room & License Notice

This project is an independent clean-room reconstruction written entirely from scratch in GDScript and Godot GLSL shaders, informed solely by public store materials and structural reverse-engineering documentation. It contains **zero** proprietary source code, binaries, textures, audio, or copyrighted assets. Licensed under the [MIT License](LICENSE).
