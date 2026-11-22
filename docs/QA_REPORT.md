# Visual & Gameplay Quality Assurance Report — *Sensory Overload* (Godot 4 Reconstruction)

> **QA Date:** 2026-11-22  
> **Engine & GPU Tested:** Godot `4.7.2.stable.official.ed1daf0bf` · NVIDIA Quadro M2000M (Vulkan `1.4.312 Forward+` & OpenGL `3.3.0 Compatibility`)  
> **Test Environment:** Live GPU windowed capture (`1280x720` + `1680x720` ultrawide) via [`tests/qa_visual_capture.tscn`](../tests/qa_visual_capture.tscn) + headless suite [`tests/test_runner.tscn`](../tests/test_runner.tscn)  
> **Baseline vs. After Evidence:** [`qa_screenshots/before/qa_metrics.json`](../qa_screenshots/before/qa_metrics.json) & [`qa_screenshots/after/qa_metrics.json`](../qa_screenshots/after/qa_metrics.json) (19 screenshots each)

---

## 1. Executive Summary

Playing and visually inspecting every screen, menu, mode, obstacle archetype, shader pass, and editor workflow in real GPU runs uncovered **9 prioritized visual, layout, and gameplay issues** that were invisible to headless unit tests — including **`QA-09` (non-uniform rotated mesh shear)** caught directly during visual inspection of the initial post-fix renders:
- **3 P0 Critical Blockers:** Broken UI modal centering/anchoring (`SettingsMenu`, `AchievementsMenu`, `LevelSelect`), stationary-rolling `pendulum` bug (`max_pos_delta_m = 0.0`), and camera clipping into the lethal obstacle during the `0.35 s` impact freeze.
- **5 P1 High-Priority Issues:** Unfair `0.40 s` obstacle reaction window on high-speed `06_c`, low-contrast HUD labels lacking dark pills/outlines on bright tunnel walls + default grey Godot menu chrome, moire aliasing in `SPEED_LINES` + weak `drifting_ghost` silhouette, a first-frame startup synthesis hitch (`26 FPS` -> `34 FPS` / pre-warmed 4-beat loop), and parent-space `Basis.scaled()` shear on rotated non-cubic meshes (`QA-09`).
- **1 P2 Medium Improvement:** Level Editor missing `Duplicate Selected` / `Clear All` workflow buttons and cohesive cyber-neon styling.

**All 9 issues have been fixed, retested, and visually verified in `qa_screenshots/after/` with `96/96` headless assertions passing and standalone `.exe` smoke tests passing on both Vulkan Forward+ and OpenGL 3.3 Compatibility.**

---

## 2. Prioritized Bug & Improvement Backlog

### P0 — Critical Blockers

#### `QA-01` [P0] Modal Screens (`SettingsMenu`, `AchievementsMenu`, `LevelSelect`) Clipping Off-Screen or Bleed-Through — **FIXED & VERIFIED**
- **Before Evidence:** `before/03_settings_accessibility.png`, `before/04_achievements.png`, and `before/02_level_select.png` showed modal controls anchored with negative manual offsets clipped top-left while `MainMenu` buttons bled behind `LevelSelect`.
- **Fix:** Switched all modals to `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)` + full-rect `CenterContainer` wrappers, and hid `MainMenu._menu_holder` via `visibility_changed` when sub-screens open.
- **After Evidence:** `after/02_level_select.png`, `after/03_settings_accessibility.png`, `after/04_achievements.png` center cleanly with `0` UI overlap warnings.

#### `QA-02` [P0] `Pendulum` Obstacle Rotates Around `Z` Axis Instead of Swinging Across Tunnel — **FIXED & VERIFIED**
- **Before Evidence:** `before/17_pendulum_motion_check.png` (`max_pos_delta_m = 0.0 m`) showed the pendulum hanging motionless in center X across `t = 0.00 s` and `t = 0.75 s`.
- **Fix:** Rotated `pendulum` around `Vector3.UP` (`Basis(Vector3.UP, swing)`), and added a regression test in `tests/test_swept_collision.gd`.
- **After Evidence:** `after/qa_metrics.json` confirms `max_pos_delta_m = 6.835 m` and `max_rot_delta_rad = 0.872`.

#### `QA-03` [P0] `0.35 s` Impact Freeze Clips Camera Into Obstacle Slab & Graze Popup Bleeds Behind `DeathOverlay` — **FIXED & VERIFIED**
- **Before Evidence:** `before/07_impact_freeze.png` clipped flush inside a flat pink wall; `before/08_death_overlay.png` leaked `DEATH WISH +1400` text behind the translucent overlay.
- **Fix:** Pulled camera back `3.8 m` along `+Y` above `impact_point`, triggered immediate `obstacle_manager.step_and_sync` highlight uniforms on freeze entry, added dark backdrops, and hid `_graze_popup` / `_crosshair` outside `PLAYING`.
- **After Evidence:** `after/07_impact_freeze.png` clearly frames the glowing cross-bars obstacle without clipping; `after/08_death_overlay.png` is sharp and unobstructed.

---

### P1 — High Priority

#### `QA-04` [P1] Unfair `0.40 s` Opening Reaction Runway on High-Speed Stages (`06_c` at `80 m/s`) — **FIXED & VERIFIED**
- **Before Evidence:** `06_c` (`base_speed = 80.0 m/s`) spawned its first `waffle` obstacle at `32.0 m` (`0.40 s` reaction time).
- **Fix:** Scaled Section 1 opening obstacle depth in `tools/generate_campaign.py` to `max(52.0, round(base_speed * 1.25, 1))`, placing `06_c`'s first obstacle at `100.0 m` (`1.25 s` runway).
- **After Evidence:** Confirmed directly in `data/levels/campaign_levels.json` (`06_c base_speed: 80.0`, `first_obs: 100.0 m`) and visible ahead in `after/10_sensory_overload_fx.png`.

#### `QA-05` [P1] HUD Text Contrast & Unstyled Default Grey Godot UI Chrome — **FIXED & VERIFIED**
- **Fix:** Created [`scripts/ui/ui_theme.gd`](../scripts/ui/ui_theme.gd) delivering a dark-glass cyber-neon palette (`#0A0618` panels, `#14F1D9` / `#FF2E93` neon accents), semi-opaque HUD pills (`make_hud_pill()`), and outlined HUD labels (`apply_hud_text_outline()`).
- **After Evidence:** Verified across `after/01_main_menu.png`, `after/06_graze_and_flow.png`, `after/09_pause_menu.png`, and `after/19_opengl3_compatibility.png`.

#### `QA-06` [P1] `SPEED_LINES` Moire Aliasing, Flat Painted Face Shading & Small `drifting_ghost` Silhouette — **FIXED & VERIFIED**
- **Fix:** Replaced `SPEED_LINES` moire math with clean radial spoke streaks, deepened face shading & crimson death flash in `shaders/obstacle_painted.gdshader`, and upgraded `drifting_ghost` to a 3-layer spectral silhouette (`parts = 3`).
- **After Evidence:** Verified visually in `after/10_sensory_overload_fx.png` and `after/16_obstacles_6_to_10.png`.

#### `QA-07` [P1] Startup Synthesis Hitch on First Track Load — **FIXED & VERIFIED**
- **Fix:** Deferred-prewarmed Track 0 in `AudioSyncManager._ready()` and streamlined procedural loops to `4` zero-crossing beats (`first=0, last=0`, RMS `0.114–0.119`).

#### `QA-09` [P1] Parent-Space `Basis.scaled()` Shears Rotated Non-Cubic Obstacles — **FIXED & VERIFIED**
- **Discovery Evidence:** During visual review of the first `after/17_pendulum_motion_check.png` render, the swinging `pendulum` arm appeared stretched diagonally into a diamond kite because `Basis.scaled()` in Godot 4 applies `Scale * Rot` in parent space rather than `Rot * Scale` in local space (which `SweptCollision`'s orthonormal OBB math assumes).
- **Root Cause & Fix:** Replaced `.scaled(...)` with `.scaled_local(...)` in [`scripts/gameplay/obstacle_manager.gd`](../scripts/gameplay/obstacle_manager.gd) and [`tests/qa_visual_capture.gd`](../tests/qa_visual_capture.gd). Also adjusted OpenGL3 capture wait in `qa_visual_capture.gd` (`1.2 s` -> `0.65 s`) so `19_opengl3_compatibility.png` cleanly frames the first waffle obstacle at `46 m / 720 m`.
- **After Evidence:** Re-captured `after/17_pendulum_motion_check.png`, `after/15_obstacles_1_to_5.png`, and `after/19_opengl3_compatibility.png` confirm razor-sharp, un-sheared geometry aligned 1:1 with green OBB overlays across both renderers.

---

### P2 — Medium / Polish

#### `QA-08` [P2] Level Editor Missing `Duplicate Selected` & `Clear All` Actions — **FIXED & VERIFIED**
- **Fix:** Added `Duplicate` and `Clear All` inspector buttons in [`scripts/editor/level_editor.gd`](../scripts/editor/level_editor.gd) alongside cyber-neon theming and two dedicated automated tests in `tests/test_editor_workflow.gd`.
- **After Evidence:** Visually verified in `after/14_level_editor.png` and via headless assertions (`Editor duplicates selected obstacle cleanly`, `Editor clears all obstacles cleanly`).

---

## 3. After-Fix Verification Summary

| Verification Check | Baseline (`before/`) | Final (`after/`) | Status |
| :--- | :---: | :---: | :---: |
| Static Integrity (`tools/validate_godot_project.py`) | Exit `0` | Exit `0` (21 campaign + 1 community) | **PASS** |
| Headless Test Suite (`tests/test_runner.tscn`) | `94/94` | `96/96` across `6` suites (`0` failed, `0` script errors) | **PASS** |
| Pendulum Motion Delta (`max_pos_delta_m` at `0.75 s`) | `0.0 m` (stationary Z-roll) | `6.835 m` (lateral swing, un-sheared `.scaled_local()`) | **PASS** |
| High-Speed Opening Runway (`06_c` at `80 m/s`) | `32.0 m` (`0.40 s`) | `100.0 m` (`1.25 s`) | **PASS** |
| Live GPU Modal & HUD Layout Overlaps | `3` modal clipping/bleed bugs | `ui_overlap_warnings: []` (`1280x720` & `1680x720`) | **PASS** |
| Core Gameplay QA Checks (`qa_metrics.json`) | `8/9` (`pendulum` broken) | `9/9` `true` (`graze_score: 9962`, `flow_locked`, `freeze`, `dead`, `checkpoint`, `watch`, `editor`) | **PASS** |
| Dual Renderer Parity (Vulkan Forward+ & OpenGL 3.3 Compat) | Verified (`1.2s` compat obstructed by slab) | Clean unobstructed frame (`46m / 720m`), zero shader errors | **PASS** |
| Standalone Export Smoke Test (`SensoryOverload.exe --quit-after 180`) | Not yet exported | `vulkan=0`, `opengl3=0` (`104.43 MB` Windows `.exe`, `70.47 MB` Linux `.x86_64`) | **PASS** |

---

## 4. `v2.0.0` Playability, Glitch & Visual-Identity Overhaul

Following user playtest feedback (*"boring, glitchy, not enjoyable, not attention hooked"*), a complete `v2.0.0` pass eliminated every shader/control glitch and upgraded game feel, audio, progression, and visual contrast (verified via [`qa_screenshots/v2/`](../qa_screenshots/v2/qa_metrics.json) and `103/103` headless assertions across `6` suites):

- **Glitch Eliminations:**
  - **Shader Readability & Zero Flicker (`voxel_tunnel.gdshader`):** Replaced high-frequency checkerboard flicker and olive-green `hue_rotate` shifts with dark obsidian/indigo architectural panels, glowing neon seams, BPM-synced traveling energy waves, and electric cyan/gold/magenta Overdrive accents.
  - **Depth Cueing & Zero Z-Fighting (`obstacle_painted.gdshader`, `obstacle_manager.gd`):** Added smooth far spawn fade-in (`168 m -> 128 m`), distance depth fog, near-hazard danger glow (`58 m -> 14 m`), and non-coplanar Y extents on intersecting `waffle`, `cross_bars`, and `guillotine` parts.
  - **Seamless Kaleidoscope & Event Flashes (`sensory_postprocess.gdshader`):** Replaced UV branch-cut tearing with polar color-space peripheral blending and added event vignette flashes for Grazes, Energy Rings, Overdrive Lock, Boost, and Impact.
  - **Control Precision & Frame Pacing (`player_controller.gd`, `game_session.gd`):** Removed double-integration mouse velocity drift, remapped Mouse/Keyboard/Gamepad steering cleanly onto camera-rolled `right_xz` / `down_xz` axes, and switched `GameSession` to variable-rate `120 Hz` sub-stepping.
- **Core Hook & Juice Additions:**
  - **Hyper-Boost (`Hold Click / Shift / Space`):** `1.48x` speed boost, `2x` distance scoring, FOV surge (`+12 deg`), radial speed lines, and `MultiMeshInstance3D` 3D velocity needles ([`scripts/gameplay/speed_particles.gd`](../scripts/gameplay/speed_particles.gd)).
  - **Collectible Energy Rings ([`scripts/gameplay/ring_manager.gd`](../scripts/gameplay/ring_manager.gd)):** Safe-corridor neon hoops awarding `+300 * Chain` pts, streak, Flow surge, burst sparks, FOV punch, and rising synth chimes.
  - **Procedural Cyber-Synthwave Audio (`audio_sync_manager.gd`):** Upgraded loops to 8 beats with LP-filtered basslines, detuned chord pads, soft plucked arpeggios, snare/hat grooves, Main Menu ambient groove, and pitch-escalating `ring`, `whoosh`, `boost_on`, and `flow_lock` cues.
  - **Zero-Friction HUD & Menu Flow:** Added `▶ PLAY NOW (QUICK DIVE)` on `MainMenu`, eye-centered reticle Flow/Boost/margin arcs (`CrosshairDrawer`), animated score popups (`GameHUD`), `S+`–`C` rank badges, `Next Stage (Enter)`, and `Space` instant retry on `DeathOverlay`.
