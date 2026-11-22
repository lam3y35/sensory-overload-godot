"""Static project validator for the Sensory Overload Godot 4 reconstruction."""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VALID_OBSTACLES = {
    "waffle", "cross_bars", "iris_ring", "sliding_blades", "pendulum",
    "tumbling_cube", "guillotine", "drifting_ghost", "spiral_slats", "pillar_grid",
}


def main() -> int:
    errors: list[str] = []

    proj_file = ROOT / "project.godot"
    if not proj_file.exists():
        errors.append("Missing project.godot")
    else:
        proj_txt = proj_file.read_text(encoding="utf-8")
        for m in re.finditer(r'res://([^"\s]+)', proj_txt):
            rel = m.group(1)
            if not (ROOT / rel).exists():
                errors.append(f"project.godot references missing resource: res://{rel}")

    for tscn in ROOT.rglob("*.tscn"):
        txt = tscn.read_text(encoding="utf-8")
        for m in re.finditer(r'path="res://([^"]+)"', txt):
            rel = m.group(1)
            if not (ROOT / rel).exists():
                errors.append(f"{tscn.name} references missing resource: res://{rel}")

    for gd in ROOT.rglob("*.gd"):
        txt = gd.read_text(encoding="utf-8")
        for m in re.finditer(r'"res://([^"]+)"', txt):
            rel = m.group(1)
            # Ignore intentional test/runtime probe paths if they use tests/ or custom sandbox
            if not (ROOT / rel).exists() and not rel.startswith("tests/nonexistent"):
                errors.append(f"{gd.relative_to(ROOT)} references missing resource: res://{rel}")

    post_shader = ROOT / "shaders" / "sensory_postprocess.gdshader"
    if post_shader.exists():
        stxt = post_shader.read_text(encoding="utf-8")
        if "SCREEN_TEXTURE" in stxt:
            errors.append("sensory_postprocess.gdshader uses Godot 3 SCREEN_TEXTURE instead of hint_screen_texture")
        if "hint_screen_texture" not in stxt:
            errors.append("sensory_postprocess.gdshader missing hint_screen_texture uniform")

    camp_file = ROOT / "data" / "levels" / "campaign_levels.json"
    if not camp_file.exists():
        errors.append("Missing data/levels/campaign_levels.json")
    else:
        data = json.loads(camp_file.read_text(encoding="utf-8"))
        campaign = data.get("campaign", [])
        if len(campaign) != 21:
            errors.append(f"Expected 21 campaign stages, found {len(campaign)}")
        seen_levels = set()
        seen_ids = set()
        for s in campaign:
            sid = s.get("id", "")
            if sid in seen_ids:
                errors.append(f"Duplicate stage id: {sid}")
            seen_ids.add(sid)
            seen_levels.add(s.get("level_index"))
            if s.get("schema") != "stage_v1":
                errors.append(f"Stage {sid} missing schema=stage_v1")
            if not s.get("sections"):
                errors.append(f"Stage {sid} has no sections")
            for obs in s.get("obstacles", []):
                if obs.get("type") not in VALID_OBSTACLES:
                    errors.append(f"Stage {sid} has invalid obstacle type {obs.get('type')}")
        if len(seen_levels) != 7:
            errors.append(f"Expected 7 campaign levels, found {len(seen_levels)}")

    if errors:
        for e in errors:
            print(f"[ERROR] {e}")
        return 1

    print("[OK] Static validation passed: project.godot, scenes, shaders, scripts, and 7-level/21-stage campaign verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
