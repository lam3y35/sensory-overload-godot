# Game Design Document — *Sensory Overload* Independent Godot 4 Reconstruction

> **Document Status:** Reconstruction Design Baseline (Milestone 0)  
> **Target Engine:** Godot Engine 4.x (`4.3+` / `4.4`) + Pure GDScript  
> **Project Workspace:** `c:\Users\Tweety\Documents\ANT\sensory-overload-godot\`  
> **Research Inputs:** [Game Overview](../../game-overview.md) · [Engine Analysis](../../engine-analysis.md) · [System Architecture](../../architecture.md) · [Gameplay Systems](../../gameplay-systems.md) · [Technical Findings](../../technical-findings.md)  
> **Sibling Docs:** [ARCHITECTURE.md](ARCHITECTURE.md) · [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md)

---

## 1. Vision, Provenance & Epistemic Boundaries

This project is a **clean-room, independent Godot 4 + GDScript reconstruction** designed to reproduce the core arcade precision-dropper experience, visual intensity, and engineering mechanics documented in our baseline reconnaissance of *Sensory Overload* (`4403510`). No proprietary code, `.pck` assets, audio files, or Steamworks binaries are copied.

To preserve forensic rigor, every design rule below specifies whether it is grounded in verified public facts or represents an original engineering solution for an undocumented internal system:

| Design Area | `[BASED ON VERIFIED FINDING]` Anchor | `[INDEPENDENT IMPLEMENTATION]` Choice (Filling Open `unk_*` Gaps) |
| :--- | :--- | :--- |
| **Engine & Renderers** | `VF-01`, `VF-03`, `VF-11`: Godot 4.x 64-bit, Vulkan primary + Compatibility renderer parity, ultrawide support | Pure GDScript (zero custom C++ GDExtensions) for `unk_1d24235b...` & `unk_2cb697e4...`; Godot 4.3+ Compatibility-safe `.gdshader` files (`unk_656a6a8f...`) |
| **Core Loop & Modes** | `VF-05`, `VF-06`: Normal, Ranked, Zen (indestructible + section progress), Practice (checkpoints), Level Editor, `WATCH` Replays | Self-contained 7-level / 21-stage campaign + local community map catalog + local ranked leaderboard JSON (`unk_66dc37a9...`) |
| **Movement & Controls** | `VF-06`, `VF-13`: Mouse tracking (`1.00x` exact sensitivity step), Keyboard-Only, Controller, Autopilot transitions, wall-clamp safety | Canonical vertical descent along `-Y`, lateral `XZ` movement inside cylinder `R = 10.0 m`, smooth boundary slide, cubic Autopilot centering |
| **Collision & Grazing** | `VF-09`, `VF-10`: `1.0.3` swept/reworked hitboxes, tumbling OBB sync, `0.35s` post-impact death freeze, Near Miss / Daredevil / Death Wish | Custom analytical swept segment-to-OBB solver (`SweptCollision`) with exact clearance thresholds `1.65 m` / `0.95 m` / `0.42 m` (`unk_38b86029...`) |
| **Visual Effects (`24+`)** | `VF-05`, `VF-11`: `>16M` effect combinations, obstacle opacity (`20–100%`), edge outline sliders, speed lines, custom crosshairs | Explicit 24-bit integer bitmask ($2^{24} = 16,777,216$) driving spatial, camera, and screen-space shaders + Photosensitivity Safe Cap (`unk_656a6a8f...`) |
| **Audio & Music Sync** | `VF-05`, `VF-13`: Beat/rhythm pulsing, play-well color lock, Pause/Restart-on-Death, Random Song, zero-click looping | Original procedural PCM synthesizer generating multi-BPM techno/industrial loops + real-time `AudioEffectSpectrumAnalyzer` + BPM phase (`unk_3e142c08...`) |
| **Persistence & Editor** | `VF-07`, `VF-12`: Per-map isolated stats/ghosts, pre-save backups, corruption-safe load guard, `"Play From Here"`, preview clock isolation | Versioned JSON `stage_v1` files, UUID-keyed `user://save_data.json`, rolling `.bak` backups, `60 Hz` deterministic/state replay JSON (`unk_9ef6e65c...`) |

---

## 2. Core Gameplay Loop & Game Modes

### 2.1 Core Dropper Loop (`[BASED ON VERIFIED FINDING]` `VF-06`, `VF-09`, `VF-10`)
1. **Descent Initiation:** Player enters a vertical 3D voxel shaft (`Level -> Stage -> Section`) falling downward (`-Y`) at increasing vertical speed.
2. **Reading & Micro-Steering:** Player weaves laterally through rotating, sliding, pulsing, and layered obstacles while 24-bit disorientation shaders warp walls, camera roll, and colors.
3. **Risk-Reward Grazing:** Skimming obstacle edges without colliding triggers **Near Miss**, **Daredevil**, or **Death Wish** grazes, boosting the **Chain Multiplier** and charging the **Flow Meter**.
4. **Music Color Lock:** Reaching `>= 70%` Flow locks tunnel palette pulses directly to the soundtrack beat (`VF-13`, Gameplay Systems §6.4).
5. **Stage Transitions (Autopilot):** Crossing section gates smoothly engages brief **Autopilot** centering while dynamically advancing visual effect masks and speed.
6. **Resolution:**
   - **Impact (Normal / Ranked):** Instant death triggers a **`0.35 s` freeze-frame** (`[INDEPENDENT IMPLEMENTATION]` modeling `VF-09` delayed death screen) highlighting the colliding obstacle before presenting Retry / Watch / Menu options.
   - **Clear:** Reaching `-stage_length` saves stats, updates personal ghost markers, awards achievement unlocks, and advances to the next stage.

### 2.2 Supported Play Modes

| Mode | Rules & Mechanics | Persistence & Scoring Behavior |
| :--- | :--- | :--- |
| **Normal Mode** | Campaign stage run (`3` sections per stage). Instant death on obstacle hit; restart stage on death. | Unlocks subsequent campaign stages; records stage clear, attempts, best score, and personal best ghost markers. |
| **Ranked Mode** | Endless/escalating speed and progressive effect-stacking (`speed_ramp`, rising effect bitmask intensity). | Submits verified local run scores and `60 Hz` replay payloads to local stage leaderboards (`WATCH` enabled). |
| **Zen Mode** | Indestructible pass-through (`VF-06`, `VF-12` `1.0.1` fix: crashing obstacles still advances through all stage sections smoothly). | Zero deaths, zero score/leaderboard submission; ideal for visual/audio immersion and obstacle sightreading. |
| **Practice Mode** | Player drops/clears custom checkpoints (`C` key / HUD button) at any safe depth during descent. | Instant respawn at active checkpoint `-Y` depth with brief `0.8 s` grace buffer; excluded from Ranked records. |
| **Replay `WATCH` Mode** | Triggered from any leaderboard entry (`VF-06`, `VF-08`). Plays back the recorded run inside the live 3D engine. | Read-only playback (`Space` pause/resume, `1x / 2x` speed, `Esc` exit); does not alter player stats. |
| **Level Editor Mode** | Interactive 3D/depth-sliced editor supporting obstacle placement, parameter editing, 24-bit effect selection, `"Play From Here"`, and publishing. | Auto-creates timestamped backup before every overwrite; isolated preview clock; publishes to local Community Maps browser. |

---

## 3. Player Movement, Canonical Space & Controls

### 3.1 Canonical Coordinate System (`[INDEPENDENT IMPLEMENTATION]`)
All gameplay, rendering, collision, editor, and replay modules share one invariant 3D coordinate convention:
- **Descent Axis:** **`-Y` (downward)** — stage starts at `y = 0.0` and descends to `y = -total_length`.
- **Tunnel Cross-Section:** Cylindrical play volume in the **`XZ` plane** with playable radius **`R_play = 8.6 m`** inside an outer voxel tunnel wall radius **`R_wall = 10.0 m`**.
- **Camera Orientation:** First-person camera positioned at `player_pos`, looking straight down `-Y` (`rotation_degrees.x = -90`), with dynamic Z/roll rotation driven by steering bank angle and active visual effects.

### 3.2 Input Modes & Boundary Solver (`[BASED ON VERIFIED FINDING]` `VF-06`, `VF-13`)
- **Mouse Tracking Mode (Mouse-Only compatible):** Screen/relative mouse delta steers lateral `XZ` target velocity; sensitivity slider uses exact **`0.05` step increments** spanning `0.20x` to `3.00x`, guaranteed to land cleanly on **`1.00x`** (preventing the `VF-13` slider skip bug).
- **Keyboard-Only Mode:** `WASD` / Arrow keys apply crisp acceleration + damping lateral motion (`v_lat_max = 22.0 m/s`, tunable per sensitivity).
- **Controller Mode:** Left analog stick maps radially with `0.12` deadzone; triggers/shoulders map to quick retry and practice checkpoint.
- **Anti-Lockup Boundary Constraint (`VF-13` `1.0.1` fix):** When `length(pos_xz) > R_play`, position is projected back onto the circle boundary and **only the outward radial velocity component** is zeroed (`v_xz -= n * max(0.0, dot(v_xz, n))`), preserving smooth tangential sliding along the tunnel wall with zero camera snap or directional lockup.
- **Autopilot Transition Controller (`VF-06`):** During inter-section gates (`1.5 s` transition window), `Autopilot` smoothly steers `pos_xz` toward a collision-free corridor point via damped cubic/spring steering with guaranteed obstacle avoidance.

---

## 4. Collision, Instant-Death Freeze & 3-Tier Graze Scoring

### 4.1 Continuous Swept Collision (`[INDEPENDENT IMPLEMENTATION]` for `VF-09`)
To eliminate high-speed tunneling and rotating-hitbox desync (`VF-09`):
1. Every physics tick (`60 Hz`), every active obstacle supplies its exact world `Transform3D` (matching its rendered mesh 1:1) and local half-extents `Vector3` (or composite OBB list for multi-part obstacles like *Waffle*, *Iris Ring*, or *Cross Bars*).
2. The player trajectory segment `P_prev -> P_curr` (inflated by player collision radius `r_player = 0.32 m`) is transformed into each OBB's local space (`T.affine_inverse()`).
3. Exact 3D slab intersection tests whether the swept sphere/segment intersects the OBB at any `t in [0.0, 1.0]`:
   - If **`hit == true`** (and mode != `Zen` and not in Practice spawn grace): record exact impact point `P_hit`, freeze world motion for **`0.35 s`** with camera shake & red/flash rim highlight on the lethal obstacle (`VF-09`), then open the Death Overlay.
   - If **`hit == false`**: compute minimum Euclidean surface clearance **`d_min`** between the trajectory segment and the OBB surface.

### 4.2 3-Tier Graze & Combo Math (`[INDEPENDENT IMPLEMENTATION]` for `VF-10`)
Each obstacle evaluates `d_min` once as the player's `-Y` depth passes its bounding slab (or continuously per obstacle ID with a per-obstacle graze lock so one obstacle awards at most one highest-tier graze per pass):

| Graze Tier | Surface Clearance (`d_min`) | Base Points | Streak Increment | Flow Meter Gain | Audio/Visual Cue |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Near Miss** | `0.95 m < d_min <= 1.65 m` | `+100` | `+1` | `+6%` | Crisp cyan edge ping + subtle chime |
| **Daredevil** | `0.42 m < d_min <= 0.95 m` | `+250` | `+2` | `+12%` | Gold spark flash + harmonic synth ping |
| **Death Wish** | `0.00 m < d_min <= 0.42 m` | `+600` | `+3` | `+22%` | Magenta shockwave ring + high-energy chord hit |

- **Chain Multiplier:** Scales linearly with active consecutive graze streak: `multiplier = min(8.0, 1.0 + floor(streak / 3) * 0.5)` (`MAX_CHAIN` achievement unlocks at `8.0x`, i.e., streak `>= 42`). Streak decays/resets if `4.5 s` elapse without a graze (paused during transitions).
- **Flow State (`Color Lock`):** Flow decays at `6% / s` and locks tunnel colors to the audio beat whenever `flow >= 0.70` (`70%`).
- **`GRAZE_ALL_STAGE` Bonus:** Clearing a stage after grazing `100%` of eligible obstacles awards a `+25,000` stage mastery bonus.

---

## 5. Obstacle Archetypes (10 Parametric / Animated Types)

Every obstacle defines an explicit **type ID**, **local OBB list generator**, **per-instance deterministic animation function `eval(local_time)`**, and **painted multi-layer shader colors**:

| # | Archetype ID | Visual & Geometric Structure | Motion / Animation Rule (`local_time`) | Hitbox / OBB Composition |
| :---: | :--- | :--- | :--- | :--- |
| 1 | `waffle` | Signature 3x3 / 4x4 voxel grid slab with open cells (`VF-10` top killer) | Optional slow axial rotation or static alignment | Array of solid bar OBBs forming exact grid bars around open windows |
| 2 | `cross_bars` | Intersecting perpendicular voxel beams spanning tunnel | Continuous angular spin around `Y` (`omega * t + phase`) | 2–3 rotated orthogonal OBBs synced to mesh transform |
| 3 | `iris_ring` | Segmented circular voxel aperture ring | Sinusoidal radial contraction/expansion synced to beat | 6–8 radial arc OBB segments updating radius dynamically |
| 4 | `sliding_blades` | Staggered horizontal blades entering from opposite tunnel walls (`All Hallows`) | Ping-pong / sawtooth lateral slide along local `X` | 2–4 sliding blade OBBs offset in depth (`Y`) |
| 5 | `pendulum` | Overhead pivot arm + heavy voxel bob (`The Thirteenth Bell`) | Harmonic swing `theta = amp * sin(freq * t + phase)` | Arm OBB + bob OBB parented under swinging pivot |
| 6 | `tumbling_cube` | Multi-layered painted voxel block (`1.0.3` tumble sync test case) | Multi-axis Euler/quaternion tumble `(rx, ry, rz) * t` | Single rotated OBB using identical transform matrix as mesh |
| 7 | `guillotine` | Heavy notched shutter gate slicing across tunnel (`Maw of Midnight`) | Snap-drop & smooth retract cycle driven by `BPM` phase | Twin vertical rail OBBs + slamming blade OBB |
| 8 | `drifting_ghost` | Translucent glowing layered voxel entity (`The Haunted Reflection`) | Lissajous `XZ` drift orbit inside tunnel radius | Softly pulsing inner core OBB + translucent outer shell |
| 9 | `spiral_slats` | Helical staircase of narrow voxel planks | Helical twist rotation + downward wave offset | 4–6 stepped OBB slats spiraling down `Y` |
| 10 | `pillar_grid` | Vertical voxel columns creating tight slalom corridors | Optional subtle lateral sway or static tight lanes | 3–6 tall vertical column OBBs extending along `Y` |

---

## 6. The 24-Bit Combinable Visual Effects Catalog ($2^{24} = 16,777,216$)

Inspired by `VF-05` (*"Over 24 visual effects with more than 16 million possible combinations"*), active effects are stored as a **24-bit integer bitmask** (`0x000000` to `0xFFFFFF`), enabling $2^{24} = 16,777,216$ distinct combinations:

| Bit | ID | Category | Visual / Spatial Effect |
| :---: | :--- | :--- | :--- |
| `0` | `BREATHING_WALLS` | Tunnel Vertex | Sinusoidal radial expansion/contraction along tunnel rings |
| `1` | `AXIAL_TWIST` | Tunnel Vertex | Helical corkscrew twist along `-Y` depth (`sin/twist * depth`) |
| `2` | `TUNNEL_WOBBLE` | Tunnel Vertex | Lateral serpentine tunnel bend wave ahead of player |
| `3` | `BEAT_SCALE_PULSE` | Tunnel + Obstacle | Geometry scale throb synced to audio beat phase |
| `4` | `NEON_PALETTE_CYCLE` | Tunnel Surface | Continuous HSV hue rotation across voxel tiles |
| `5` | `CHECKER_SCROLL` | Tunnel Surface | High-contrast scrolling checkerboard / voxel grid pattern |
| `6` | `WIREFRAME_GLOW` | Tunnel Surface | Glowing neon voxel cell borders |
| `7` | `DEPTH_FOG_THROB` | Tunnel Surface | Oscillating chromatic fog density pulsing down the shaft |
| `8` | `CAMERA_SPIRAL_ROLL` | Camera | Continuous or oscillating camera roll angle |
| `9` | `CAMERA_FOV_SURGE` | Camera | Speed & beat-reactive FOV expansion (`75° -> 105°`) |
| `10` | `HORIZON_SWAY` | Camera | Subtle dutch-tilt coupled to lateral steering velocity |
| `11` | `SPEED_LINES` | Camera / Overlay | Radial edge motion streaks (independently disableable in Accessibility) |
| `12` | `CHROMATIC_ABERRATION` | Post-Process | Radial RGB channel separation scaling with speed & flow |
| `13` | `KALEIDOSCOPE_FOLD` | Post-Process | Subtle angular UV mirroring/symmetry pulse on peripheral vision |
| `14` | `FISHEYE_WARP` | Post-Process | Peripheral spherical lens warp creating tunnel depth illusion |
| `15` | `BARREL_RIPPLE` | Post-Process | Concentric shockwave UV ripple radiating from center |
| `16` | `STROBE_FLASH` | Post-Process | Beat-synced luminance flash *(clamped/disabled by Safe Photosensitivity Mode)* |
| `17` | `HUE_SHIFT_SCREEN` | Post-Process | Full-screen color temperature / hue shift wave |
| `18` | `INVERT_ACCENT` | Post-Process | Brief high-contrast color inversion pulses *(Safe-mode damped)* |
| `19` | `SCANLINE_OVERLAY` | Post-Process | Industrial CRT/arcade horizontal scanlines |
| `20` | `VIGNETTE_THROB` | Post-Process | Rhythmic neon/dark vignette squeezing peripheral view |
| `21` | `PIXEL_CRUNCH` | Post-Process | Dynamic retro pixelation quantization spikes on heavy drops |
| `22` | `CONTRAST_OVERDRIVE` | Post-Process | High-saturation/bloom contrast boost during high Flow |
| `23` | `WHITEOUT_GLARE` | Post-Process | Intense radial highlight glare *(inspired by Flash's Whiteout; Safe-mode damped)* |

---

## 7. Campaign Progression (7 Progressive Levels / 21 Stages)

Each level contains **3 bespoke multi-section stages** (`21` official playable stages total), scaling vertical speed (`32 m/s` to `82 m/s`), obstacle density, and active effect-bitmask complexity:

| Level | Theme Title | Stages (3 Each) | Base Speed | Primary Obstacles | Active Effects Progression |
| :---: | :--- | :--- | :---: | :--- | :--- |
| **01** | *Calibration (Tutorial)* | `01-A Drop Check`, `01-B Graze School`, `01-C First Descent` | `32–38 m/s` | `pillar_grid`, `cross_bars`, intro `waffle` | `0–2` bits (`CHECKER_SCROLL`, `SPEED_LINES`) |
| **02** | *Vertigo* | `02-A Corkscrew`, `02-B Tilted Horizon`, `02-C Spiral Drop` | `40–46 m/s` | `cross_bars`, `spiral_slats`, `tumbling_cube` | `3–4` bits (`AXIAL_TWIST`, `CAMERA_SPIRAL_ROLL`, `BREATHING_WALLS`) |
| **03** | *Tornado* | `03-A Slipstream`, `03-B Vortex Gate`, `03-C Eye of the Storm` | `46–54 m/s` | `spiral_slats`, `tumbling_cube`, `waffle` | `4–6` bits (`CAMERA_FOV_SURGE`, `TUNNEL_WOBBLE`, `CHROMATIC_ABERRATION`) |
| **04** | *Peristalsis* | `04-A Compression`, `04-B Deep Channel`, `04-C Digestion` | `52–60 m/s` | `iris_ring`, `waffle`, `pillar_grid` | `5–7` bits (`BREATHING_WALLS`, `BEAT_SCALE_PULSE`, `BARREL_RIPPLE`, `VIGNETTE_THROB`) |
| **05** | *Flashpoint* | `05-A Aperture`, `05-B Whiteout`, `05-C Overexposed` | `58–68 m/s` | `sliding_blades`, `waffle`, `iris_ring` | `6–8` bits (`WHITEOUT_GLARE`, `STROBE_FLASH`, `CONTRAST_OVERDRIVE`, `SCANLINE_OVERLAY`) |
| **06** | *Sensory Overload* | `06-A Terminal Velocity`, `06-B Cascade`, `06-C Sensory Overload` | `68–82 m/s` | All core obstacles + tight `waffle` chains | `8–12` bits (combining spatial twist, kaleidoscope fold, pixel crunch, hue cycle) |
| **07** | *All Hallows (Bonus)* | `07-A Haunted Reflection`, `07-B Thirteenth Bell`, `07-C Maw of Midnight` | `56–74 m/s` | `drifting_ghost`, `pendulum`, `guillotine`, `sliding_blades` | `5–8` bits (layered painted obstacles, depth fog throb, neon violet/amber palette) |

---

## 8. Audio & Music-Sync Architecture (`[INDEPENDENT IMPLEMENTATION]`)

- **Zero-External-Asset Procedural OST Synthesizer:** `AudioSyncManager` synthesizes 7 distinct, seamless techno/industrial/EDM loops (`124` to `152 BPM`, matching level energy) at startup or on-demand into `AudioStreamWAV` PCM buffers using exact integer-beat cycle counts so loop seams occur at zero crossings — guaranteeing **zero clicking or crackling** (`VF-13` *Aperture* fix).
- **Real-Time Beat & Spectrum Sync:**
  - `beat_phase` (`0.0–1.0`) computed accurately from `AudioStreamPlayer.get_playback_position() + AudioServer.get_time_since_last_mix()`.
  - `AudioEffectSpectrumAnalyzer` on the `Music` bus provides live `bass_energy` (`20–140 Hz`), `mid_energy` (`140–2000 Hz`), and `high_energy` (`2000–12000 Hz`) uniforms to shaders.
- **Audio State Machine (`VF-13`):**
  - Separate buses: `Master`, `Music`, `SFX`.
  - Independent settings toggles: **`Pause on Death`**, **`Restart Song on Death`**, **`Random Track`**, **`Play-Well Color Sync`**.
- **Procedural SFX Suite:** Distinct synthesized audio cues for *Near Miss*, *Daredevil*, *Death Wish*, *Chain Break*, *Checkpoint Set*, *Stage Clear*, *Death Impact*, and *UI Navigation*.

---

## 9. UI, Accessibility & Achievements

### 9.1 Accessibility Suite (`[BASED ON VERIFIED FINDING]` `VF-11`, `VF-13`)
1. **Obstacle Opacity Override:** `20%` to `100%` (`0.20`–`1.00`).
2. **Obstacle Edge Outline Brightness:** `0.0` to `2.0`.
3. **Obstacle Edge Outline Thickness:** `0.0` to `1.0`.
4. **Speed Lines Toggle:** On / Off.
5. **Photosensitivity Safe Mode (Camera Comfort):** Clamps `STROBE_FLASH`, `INVERT_ACCENT`, and `WHITEOUT_GLARE` intensity and limits camera roll amplitude.
6. **Crosshair Customizer:** Shape (`Dot`, `Cross`, `Ring`, `Outlined Plus`), Color (full RGB picker), Size (`0.5x–2.5x`), Thickness (`1–6 px`).
7. **Mouse Sensitivity Slider:** `0.20x` to `3.00x` in `0.05` increments (explicitly includes exact `1.00x`).

### 9.2 Local Achievements System (`20` Milestone Achievements)
Modeled behaviorally after the verified achievement schema in [game-overview.md](../../game-overview.md) §6:
`FIRST_DESCENT`, `FIRST_DEATH`, `FIRST_DEATHWISH`, `TUTORIAL_DONE`, `GRAZE_STREAK_5`, `GRAZE_STREAK_10`, `GRAZE_STREAK_20`, `GRAZE_STREAK_50`, `MAX_CHAIN`, `GRAZE_1000`, `GRAZE_ALL_STAGE`, `NODEATH_STAGE`, `NODEATH_STREAK_3`, `PERFECT_STAGE`, `DEATHWISH_STREAK_10`, `ATTEMPTS_100`, `CLEAR_VERTIGO`, `CLEAR_TORNADO`, `CLEAR_SENSORY_OVERLOAD`, `CLEAR_ALL_HALLOWS`.
