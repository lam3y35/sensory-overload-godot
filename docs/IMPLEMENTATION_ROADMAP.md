# Incremental Implementation Roadmap — *Sensory Overload* Godot 4 Reconstruction

> **Document Status:** Milestones 0–7 Complete & Verified (`Godot 4.7.2.stable`)  
> **Project Workspace:** `c:\Users\Tweety\Documents\ANT\sensory-overload-godot\`  
> **Related Docs:** [GAME_DESIGN_DOCUMENT.md](GAME_DESIGN_DOCUMENT.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [Reverse Engineering Roadmap](../../reverse-engineering-roadmap.md)

> **Epistemic Tagging Legend:** Each milestone below preserves strict separation between **`[BASED ON VERIFIED FINDING]`** (behaviors established in [technical-findings.md](../../technical-findings.md), `VF-01`–`VF-14`) and **`[INDEPENDENT IMPLEMENTATION]`** (clean-room Godot 4 / GDScript designs filling open `unk_*` gaps).

---

## Environment Prerequisite Check (`2026-11-22`)

Before writing GDScript code, the local environment was checked:
- **Godot 4 Engine Binary:** **Not installed** on this Windows host (checked `PATH`, `Program Files`, `AppData`, `Downloads`, `C:\`, `D:\`, Steam directories).
- **Available Host Tooling:** `Python 3.12`, `Node.js`, `Git`, and `winget` (`Microsoft.Winget`).
- **Dual Verification Paths:**
  - **Path A (Recommended — Live Godot 4 Testing):** With your permission, install Godot 4 (e.g., via `winget install GodotEngine.GodotEngine` or official portable zip), enabling live `godot --headless` script parsing, shader compilation, scene loading, and automated unit tests at every milestone gate.
  - **Path B (Static-First):** Build all 7 milestones cleanly inside `c:\Users\Tweety\Documents\ANT\sensory-overload-godot\`, validate JSON/scene/script references with Python `validate_godot_project.py`, and include the full `tests/test_runner.gd` suite ready to run the moment you open or run the project in Godot 4.

---

## Milestone Overview

| Milestone | Scope | Key Deliverables | Verification Gate |
| :---: | :--- | :--- | :--- |
| **M0** | Design & Architecture | `GAME_DESIGN_DOCUMENT.md`, `ARCHITECTURE.md`, `IMPLEMENTATION_ROADMAP.md` | Cross-links, verified/independent tagging (**Done**) |
| **M1** | Project Scaffold, Autoloads & Data Layer | `project.godot`, `default_bus_layout.tres`, 5 Autoloads, 5 Data classes, `LevelRepository` | `test_data_persistence.gd` (`19/19` passed) (**Done**) |
| **M2** | Core 3D Tunnel, Swept Collision & Movement | `SweptCollision`, `TunnelRenderer`, `voxel_tunnel.gdshader`, `ObstacleManager` (10 types), `obstacle_painted.gdshader`, `PlayerController` + `Autopilot` | `test_swept_collision.gd` (`23/23` passed) (**Done**) |
| **M3** | Gameplay Modes, Scoring & Death Freeze | `ScoringManager`, `GameSession` (Normal, Ranked, Zen, Practice checkpoints, `0.35 s` impact freeze) | `test_gameplay_modes.gd` (`16/16` passed) (**Done**) |
| **M4** | 24-Bit Effects Compositor & Procedural Audio Sync | `sensory_postprocess.gdshader`, `EffectCompositor`, `AudioSyncManager` (procedural 7-BPM OST loops + FFT + SFX + death audio FSM) | `test_replay_audio_effects.gd` (Effects & Audio checks passed) (**Done**) |
| **M5** | Replay System (`WATCH`) & Ghost Markers | `ReplayController`, local leaderboard integration, spatial 3D ghost markers, `WATCH` live playback HUD | `test_replay_audio_effects.gd` (`18/18` passed) (**Done**) |
| **M6** | Interactive Level Editor & Community Browser | `LevelEditor` (CRUD, 24-effect toggles, `"Play From Here"`, auto-backups, publish), `LevelPreviewViewport` (isolated clock) | `test_editor_workflow.gd` (`12/12` passed) (**Done**) |
| **M7** | Polished UI, Accessibility & 7-Level / 21-Stage Campaign | `MainMenu` (3D backdrop), `GameHUD` + `CrosshairDrawer`, `SettingsMenu`, `LevelSelect`, `AchievementsMenu`, `campaign_levels.json` (21 stages) | Static validator + `campaign_and_scene_boot` (`5/5` passed) + Vulkan & OpenGL3 smoke boots (**Done**) |

---

## Detailed Milestone Breakdown

### Milestone 1 — Project Scaffold, Autoloads & Data Layer
- Configure `project.godot` (`[BASED ON VERIFIED FINDING]` `VF-01`/`VF-11`: Godot 4 Forward+ with `gl_compatibility` fallback, viewport `1920x1080`, `canvas_items` stretch `expand` for ultrawide support; `[INDEPENDENT IMPLEMENTATION]`: `60 Hz` physics ticks, autoload registrations, input map actions).
- Create `default_bus_layout.tres` (`Master` -> `Music` with `AudioEffectSpectrumAnalyzer`, `Master` -> `SFX`).
- Implement `GameEvents` signal bus, `EffectCatalog` (`24` bits, `$2^{24}$` metadata), `ObstacleData`, `StageData`, `ReplayData`, `AchievementCatalog` (`20` achievements), `SettingsManager`, `SaveManager`, and `LevelRepository` (`[BASED ON VERIFIED FINDING]` `VF-12`: per-map stat/ghost isolation + pre-save backups + failed-load protection).
- **Test Gate:** `tests/test_data_persistence.gd` verifies serialization roundtrips, per-map stat isolation, corruption-safe loading, and pre-save `.bak` creation.

### Milestone 2 — Core 3D Tunnel, Swept Collision & First-Person Movement
- Implement `SweptCollision` (`[INDEPENDENT IMPLEMENTATION]` modeling `VF-09`/`VF-10`: `segment_to_obb_sweep` + `segment_to_obb_clearance` + `evaluate_graze_tier`).
- Implement `TunnelRenderer` using `MultiMeshInstance3D` ring pooling + `voxel_tunnel.gdshader` (breathing, twist, wobble, neon checker/wireframe).
- Implement `ObstacleManager` supporting all 10 parametric/animated obstacle archetypes with shared transform/OBB evaluation + `obstacle_painted.gdshader` (`[BASED ON VERIFIED FINDING]` `VF-11`: layered painted colors, opacity override `20–100%`, outline brightness/thickness, impact highlight).
- Implement `PlayerController` (`[BASED ON VERIFIED FINDING]` `VF-06`/`VF-13`: Mouse, Keyboard, Gamepad, wall-slide anti-lockup clamp, Autopilot transition steering).
- **Test Gate:** `tests/test_swept_collision.gd` verifies high-speed collision without tunneling, tumbling rotation OBB parity, and exact graze tier boundaries.

### Milestone 3 — Gameplay Modes, Scoring & Death Freeze
- Implement `ScoringManager` (`Near Miss`, `Daredevil`, `Death Wish`, `MAX_CHAIN`, `Flow Meter`, `GRAZE_ALL_STAGE`).
- Implement `GameSession` unifying Normal, Ranked, Zen (`[BASED ON VERIFIED FINDING]` `VF-12` section advance on obstacle pass-through), and Practice (custom checkpoints + respawn grace), plus the `[INDEPENDENT IMPLEMENTATION]` `0.35 s` post-impact world freeze (`VF-09`) before showing the Death Overlay.
- **Test Gate:** `tests/test_gameplay_modes.gd` tests mode rules, checkpoint save/restore, chain decay, and achievement triggers.

### Milestone 4 — 24-Bit Effects & Procedural Audio Synchronization
- Implement `sensory_postprocess.gdshader` and `EffectCompositor` mapping all 24 effect bits + Safe Photosensitivity clamping + beat/FFT reactivity.
- Implement `AudioSyncManager` generating 7 distinct multi-BPM seamless procedural synth loops (`124–152 BPM`) + procedural SFX + `Pause on Death` / `Restart Song on Death` / `Random Track` state logic.
- **Test Gate:** Shader parameter validation, 24-bit mask decoding, Safe Mode clamps, and seamless audio buffer generation tests pass.

### Milestone 5 — Replay System (`WATCH`) & Ghost Markers
- Implement `ReplayController` recording `60 Hz` frames `[y, x, z, roll]`, saving winning/top runs to `LevelRepository`, rendering spatial personal-best ghost markers in the tunnel, and executing live `WATCH` playback inside `GameSession`.
- **Test Gate:** Full record -> JSON save -> reload -> frame interpolation playback assertions pass.

### Milestone 6 — Interactive Level Editor & Community Level Browser
- Build `LevelEditor` scene and script: 3D camera fly/depth scrubbing, obstacle palette & live property inspector, 24-effect bitmask toggles, section settings, `"Play From Here"` spawning directly into `GameSession` at the editor camera's depth, pre-save backups, and publishing to local Community Maps.
- Build `LevelPreviewViewport` with isolated per-preview `simulation_time` (preventing animation-clock freeze).
- **Test Gate:** `tests/test_editor_workflow.gd` validates add/edit/delete, backup retention, failed-load protection, `"Play From Here"` state, and preview clock isolation.

### Milestone 7 — Polished UI, Accessibility & 7-Level / 21-Stage Campaign
- Author all `21` original stages across `7` escalating levels (*Calibration*, *Vertigo*, *Tornado*, *Peristalsis*, *Flashpoint*, *Sensory Overload*, *All Hallows*) in `data/levels/campaign_levels.json`.
- Build polished, ultrawide-ready UI scenes: `MainMenu` (animated 3D tunnel backdrop), `GameHUD` + `CrosshairDrawer` (Dot, Cross, Ring, Outlined Plus + color/size/thickness), `DeathOverlay`, `PauseMenu`, `SettingsMenu`, `LevelSelect` (Campaign + Community tabs, preview viewport, stage leaderboards with `WATCH` button), and `AchievementsMenu`.
- **Final Verification Gate:** Run complete `tests/test_runner.gd` (or static validator + manual verification matrix if Godot 4 is not installed) and inspect every scene, script, and shader cleanly.
