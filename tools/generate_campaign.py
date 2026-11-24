"""Generates the original 7-level, 21-stage Sensory Overload campaign + 1 community sample stage
with curated art-directed tunnel palettes, high-contrast obstacle colorways, synced OST BPMs,
and exhilarating precision-dropper pacing.
"""

import json
import math
from pathlib import Path

LEVELS = [
    {
        "level_index": 1,
        "level_title": "01 - Calibration",
        "bpm": 128.0,
        "track_index": 0,
        "palette": ["#C2188A", "#2E1A7A", "#070410"],
        "obs_palette": ["#FF2E93", "#00E5FF"],
        "stages": [
            ("01_a", "01-A", "Drop Check", 54.0, 0.25, 480.0, [1 << 11, (1 << 3) | (1 << 11)], ["waffle", "cross_bars", "pillar_grid"]),
            ("01_b", "01-B", "Graze School", 58.0, 0.30, 520.0, [(1 << 3) | (1 << 11), (1 << 0) | (1 << 3) | (1 << 11)], ["cross_bars", "iris_ring", "waffle", "pillar_grid"]),
            ("01_c", "01-C", "First Descent", 62.0, 0.35, 560.0, [(1 << 0) | (1 << 5), (1 << 0) | (1 << 3) | (1 << 5) | (1 << 11)], ["waffle", "sliding_blades", "cross_bars", "tumbling_cube"]),
        ],
    },
    {
        "level_index": 2,
        "level_title": "02 - Vertigo",
        "bpm": 132.0,
        "track_index": 1,
        "palette": ["#8B2FC9", "#2980D9", "#080614"],
        "obs_palette": ["#E5C158", "#00F0FF"],
        "stages": [
            ("02_a", "02-A", "Corkscrew", 62.0, 0.40, 580.0, [(1 << 1) | (1 << 11), (1 << 1) | (1 << 8) | (1 << 10)], ["spiral_slats", "cross_bars", "tumbling_cube"]),
            ("02_b", "02-B", "Tilted Horizon", 66.0, 0.45, 620.0, [(1 << 1) | (1 << 8) | (1 << 10), (1 << 0) | (1 << 1) | (1 << 8) | (1 << 11)], ["tumbling_cube", "spiral_slats", "waffle", "pillar_grid"]),
            ("02_c", "02-C", "Spiral Drop", 70.0, 0.50, 660.0, [(1 << 0) | (1 << 1) | (1 << 8), (1 << 1) | (1 << 4) | (1 << 8) | (1 << 12)], ["spiral_slats", "tumbling_cube", "iris_ring", "waffle"]),
        ],
    },
    {
        "level_index": 3,
        "level_title": "03 - Tornado",
        "bpm": 136.0,
        "track_index": 2,
        "palette": ["#D15A1F", "#1B84A8", "#0A0A14"],
        "obs_palette": ["#FF8C1A", "#00E5FF"],
        "stages": [
            ("03_a", "03-A", "Slipstream", 68.0, 0.50, 620.0, [(1 << 2) | (1 << 9) | (1 << 11), (1 << 1) | (1 << 2) | (1 << 9) | (1 << 12)], ["spiral_slats", "sliding_blades", "cross_bars"]),
            ("03_b", "03-B", "Vortex Gate", 72.0, 0.55, 660.0, [(1 << 1) | (1 << 2) | (1 << 9), (1 << 1) | (1 << 2) | (1 << 6) | (1 << 9) | (1 << 12)], ["iris_ring", "tumbling_cube", "spiral_slats", "waffle"]),
            ("03_c", "03-C", "Eye of the Storm", 76.0, 0.60, 700.0, [(1 << 2) | (1 << 6) | (1 << 9) | (1 << 12), (1 << 1) | (1 << 2) | (1 << 8) | (1 << 9) | (1 << 12) | (1 << 15)], ["waffle", "spiral_slats", "tumbling_cube", "cross_bars"]),
        ],
    },
    {
        "level_index": 4,
        "level_title": "04 - Peristalsis",
        "bpm": 140.0,
        "track_index": 3,
        "palette": ["#DCE2EA", "#00D4D8", "#090B10"],
        "obs_palette": ["#00E5FF", "#FF1E3C"],
        "stages": [
            ("04_a", "04-A", "Compression", 74.0, 0.55, 660.0, [(1 << 0) | (1 << 3) | (1 << 20), (1 << 0) | (1 << 3) | (1 << 15) | (1 << 20)], ["iris_ring", "waffle", "pillar_grid"]),
            ("04_b", "04-B", "Deep Channel", 78.0, 0.60, 700.0, [(1 << 0) | (1 << 3) | (1 << 7) | (1 << 15), (1 << 0) | (1 << 3) | (1 << 7) | (1 << 15) | (1 << 20)], ["waffle", "iris_ring", "sliding_blades", "pillar_grid"]),
            ("04_c", "04-C", "Digestion", 82.0, 0.65, 740.0, [(1 << 0) | (1 << 2) | (1 << 3) | (1 << 15) | (1 << 20), (1 << 0) | (1 << 2) | (1 << 3) | (1 << 14) | (1 << 15) | (1 << 20)], ["waffle", "guillotine", "iris_ring", "tumbling_cube"]),
        ],
    },
    {
        "level_index": 5,
        "level_title": "05 - Flashpoint",
        "bpm": 144.0,
        "track_index": 4,
        "palette": ["#D91624", "#ECEFF4", "#060609"],
        "obs_palette": ["#00D8EB", "#B829FF"],
        "stages": [
            ("05_a", "05-A", "Aperture", 80.0, 0.60, 700.0, [(1 << 3) | (1 << 12) | (1 << 19) | (1 << 22), (1 << 3) | (1 << 12) | (1 << 19) | (1 << 22) | (1 << 23)], ["cross_bars", "iris_ring", "sliding_blades"]),
            ("05_b", "05-B", "Whiteout", 84.0, 0.70, 740.0, [(1 << 6) | (1 << 12) | (1 << 16) | (1 << 23), (1 << 6) | (1 << 11) | (1 << 12) | (1 << 16) | (1 << 22) | (1 << 23)], ["sliding_blades", "waffle", "iris_ring", "guillotine"]),
            ("05_c", "05-C", "Overexposed", 88.0, 0.75, 780.0, [(1 << 4) | (1 << 12) | (1 << 16) | (1 << 22) | (1 << 23), (1 << 4) | (1 << 9) | (1 << 12) | (1 << 16) | (1 << 18) | (1 << 22) | (1 << 23)], ["waffle", "sliding_blades", "tumbling_cube", "iris_ring"]),
        ],
    },
    {
        "level_index": 6,
        "level_title": "06 - Sensory Overload",
        "bpm": 148.0,
        "track_index": 5,
        "palette": ["#39E600", "#E600B8", "#08040C"],
        "obs_palette": ["#00F0FF", "#FF2EC4"],
        "stages": [
            ("06_a", "06-A", "Terminal Velocity", 86.0, 0.80, 780.0, [(1 << 1) | (1 << 3) | (1 << 9) | (1 << 11) | (1 << 12) | (1 << 14), (1 << 0) | (1 << 1) | (1 << 3) | (1 << 8) | (1 << 9) | (1 << 11) | (1 << 12) | (1 << 17)], ["waffle", "spiral_slats", "tumbling_cube", "sliding_blades"]),
            ("06_b", "06-B", "Cascade", 92.0, 0.90, 820.0, [(1 << 0) | (1 << 1) | (1 << 4) | (1 << 6) | (1 << 9) | (1 << 12) | (1 << 13) | (1 << 21), (1 << 0) | (1 << 1) | (1 << 2) | (1 << 4) | (1 << 6) | (1 << 8) | (1 << 12) | (1 << 13) | (1 << 21) | (1 << 22)], ["waffle", "guillotine", "iris_ring", "tumbling_cube", "spiral_slats"]),
            ("06_c", "06-C", "Sensory Overload", 96.0, 1.00, 880.0, [(1 << 0) | (1 << 1) | (1 << 2) | (1 << 4) | (1 << 8) | (1 << 9) | (1 << 11) | (1 << 12) | (1 << 13) | (1 << 15), (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 6) | (1 << 8) | (1 << 9) | (1 << 11) | (1 << 12) | (1 << 13) | (1 << 17) | (1 << 20) | (1 << 22)], ["waffle", "tumbling_cube", "guillotine", "spiral_slats", "sliding_blades"]),
        ],
    },
    {
        "level_index": 7,
        "level_title": "07 - All Hallows",
        "bpm": 152.0,
        "track_index": 6,
        "palette": ["#E86414", "#7020E8", "#0A0512"],
        "obs_palette": ["#22D3EE", "#FACC15"],
        "stages": [
            ("07_a", "07-A", "Haunted Reflection", 74.0, 0.60, 700.0, [(1 << 4) | (1 << 7) | (1 << 20), (1 << 0) | (1 << 4) | (1 << 7) | (1 << 12) | (1 << 20)], ["drifting_ghost", "pillar_grid", "cross_bars"]),
            ("07_b", "07-B", "Thirteenth Bell", 82.0, 0.70, 760.0, [(1 << 1) | (1 << 6) | (1 << 7) | (1 << 19) | (1 << 20), (1 << 1) | (1 << 6) | (1 << 7) | (1 << 10) | (1 << 12) | (1 << 20)], ["pendulum", "drifting_ghost", "sliding_blades", "iris_ring"]),
            ("07_c", "07-C", "Maw of Midnight", 90.0, 0.85, 840.0, [(1 << 0) | (1 << 3) | (1 << 6) | (1 << 7) | (1 << 12) | (1 << 20) | (1 << 22), (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6) | (1 << 7) | (1 << 8) | (1 << 12) | (1 << 15) | (1 << 20) | (1 << 22)], ["guillotine", "pendulum", "sliding_blades", "drifting_ghost", "waffle"]),
        ],
    },
]


def build_stage(lvl: dict, spec: tuple, source: str = "campaign") -> dict:
    sid, code, title, base_speed, ramp, total_len, sec_masks, pool = spec
    sec_count = 3
    sec_len = round(total_len / sec_count, 1)
    gap = 26.0
    sections = []
    for s_idx in range(sec_count):
        mask = sec_masks[min(s_idx, len(sec_masks) - 1)]
        if s_idx == sec_count - 1:
            mask |= (1 << 3)
        sections.append({
            "id": f"sec_{s_idx + 1}",
            "length": sec_len,
            "effect_mask": mask,
            "transition_gap": gap,
        })

    obstacles = []
    obs_counter = 1
    step_m = max(28.0, min(42.0, 21.0 + base_speed * 0.19))
    o_prim, o_acc = lvl["obs_palette"]

    for s_idx in range(sec_count):
        sec_start = s_idx * sec_len
        sec_end = (s_idx + 1) * sec_len - (gap + 8.0)
        first_offset = max(62.0, round(base_speed * 1.15, 1)) if s_idx == 0 else 32.0
        d = sec_start + first_offset
        while d < sec_end:
            otype = pool[(obs_counter - 1) % len(pool)]
            angle_y = ((obs_counter * 37) % 360) - 180.0
            rx = 18.0 * math.sin(obs_counter * 0.9) if otype in ("tumbling_cube", "cross_bars") else 0.0
            off_x = 0.0 if otype in ("waffle", "iris_ring", "guillotine", "pendulum") else round(2.1 * math.sin(obs_counter * 1.3), 2)
            off_z = 0.0 if otype in ("waffle", "iris_ring", "guillotine", "pendulum") else round(2.1 * math.cos(obs_counter * 1.1), 2)
            obstacles.append({
                "id": f"{sid}_obs_{obs_counter:02d}",
                "type": otype,
                "depth": round(d, 1),
                "offset_xz": [off_x, off_z],
                "rotation_deg": [round(rx, 1), round(angle_y, 1), 0.0],
                "scale": [1.0, 1.0, 1.0],
                "speed": round(0.65 + (lvl["level_index"] * 0.14) + ((obs_counter % 3) * 0.12), 2),
                "amplitude": 1.0,
                "phase": round((obs_counter * 0.7) % 6.28, 2),
                "section_index": s_idx,
                "color_primary": o_prim if (obs_counter % 2 == 1) else o_acc,
                "color_accent": o_acc if (obs_counter % 2 == 1) else o_prim,
                "seed_int": obs_counter + lvl["level_index"] * 7,
            })
            obs_counter += 1
            d += step_m

    return {
        "schema": "stage_v1",
        "id": sid,
        "level_index": lvl["level_index"],
        "level_title": lvl["level_title"],
        "stage_code": code,
        "title": title,
        "author": "Pancake Reconstruction",
        "source": source,
        "description": f"{lvl['level_title']} — {title}",
        "bpm": lvl["bpm"],
        "track_index": lvl["track_index"],
        "base_speed": base_speed,
        "speed_ramp": ramp,
        "tunnel_radius": 10.0,
        "palette": lvl["palette"],
        "sections": sections,
        "obstacles": obstacles,
    }


def main() -> None:
    campaign = []
    for lvl in LEVELS:
        for spec in lvl["stages"]:
            campaign.append(build_stage(lvl, spec, "campaign"))

    community_sample = build_stage(
        LEVELS[4],
        ("comm_inception_legacy", "COM-1", "Inception Legacy (Showcase)", 72.0, 0.55, 640.0,
         [(1 << 1) | (1 << 5) | (1 << 6) | (1 << 12), (1 << 1) | (1 << 4) | (1 << 8) | (1 << 12)],
         ["waffle", "cross_bars", "tumbling_cube", "pendulum", "guillotine"]),
        source="custom",
    )
    community_sample["level_index"] = 0
    community_sample["level_title"] = "Community Showcase"
    community_sample["author"] = "Community Showcase"

    out_path = Path(__file__).resolve().parent.parent / "data" / "levels" / "campaign_levels.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps({"campaign": campaign, "community_samples": [community_sample]}, indent=2),
        encoding="utf-8",
    )
    print(f"Wrote {len(campaign)} campaign stages + 1 community sample to {out_path}")


if __name__ == "__main__":
    main()
