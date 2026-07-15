#!/usr/bin/env python3
"""Run the focused pixel-renderer release gate locally or in CI."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
WEB_EXPORT_DIRECTORY = REPOSITORY_ROOT / "build/web"
DEFAULT_GODOT_CANDIDATES = (
    os.environ.get("GODOT_BIN", ""),
    shutil.which("godot") or "",
    "/usr/local/bin/godot",
)
GODOT_TESTS = (
    "scripts/tests/test_visual_asset_pipeline.gd",
    "scripts/tests/test_pixel_renderer_foundation.gd",
    "scripts/tests/test_pixel_actor_rendering.gd",
    "scripts/tests/test_pixel_tactical_rendering.gd",
    "scripts/tests/test_pixel_vfx_polish.gd",
    "scripts/tests/test_map_render_mode.gd",
    "scripts/tests/test_pixel_renderer_release_gate.gd",
    "scripts/tests/test_v16_5_sensory_settings.gd",
    "scripts/tests/test_v14_sensory_feedback.gd",
    "scripts/tests/test_v23_2_state_accessibility.gd",
    "scripts/tests/test_v23_projectile_system.gd",
    "scripts/tests/test_v23_projectile_runtime.gd",
    "scripts/tests/test_v23_projectile_rendering.gd",
    "scripts/tests/test_v23_boss_projectiles.gd",
    "scripts/tests/test_v23_3_boss_strategies.gd",
    "scripts/tests/test_v23_2_gameplay_hardening.gd",
)


@dataclass(frozen=True)
class Check:
    name: str
    command: tuple[str, ...]
    timeout_seconds: int = 180


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--godot",
        type=Path,
        help="Godot executable. Defaults to GODOT_BIN, PATH, then /usr/local/bin/godot.",
    )
    parser.add_argument(
        "--visual-capture",
        action="store_true",
        help="Also require the fixed-scene capture gate on a desktop rendering backend.",
    )
    parser.add_argument(
        "--web-export",
        action="store_true",
        help="Also produce the configured Web release export; requires installed templates.",
    )
    return parser.parse_args()


def resolve_godot(explicit_path: Path | None) -> Path:
    candidates = (str(explicit_path),) if explicit_path is not None else DEFAULT_GODOT_CANDIDATES
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate).expanduser()
        if path.is_file() and os.access(path, os.X_OK):
            return path.resolve()
    raise FileNotFoundError(
        "Godot executable not found; pass --godot or set GODOT_BIN to an executable path"
    )


def build_checks(godot: Path, visual_capture: bool, web_export: bool) -> list[Check]:
    checks = [
        Check(
            "Generated visual asset validation",
            (sys.executable, "tools/pixel_assets.py", "check"),
            60,
        ),
        Check(
            "Aseprite pipeline unit tests",
            (
                sys.executable,
                "-m",
                "unittest",
                "discover",
                "-s",
                "tools/tests",
                "-p",
                "test_*.py",
            ),
            60,
        ),
    ]
    for test_path in GODOT_TESTS:
        checks.append(
            Check(
                Path(test_path).stem,
                (
                    str(godot),
                    "--headless",
                    "--path",
                    str(REPOSITORY_ROOT),
                    "--script",
                    f"res://{test_path}",
                ),
            )
        )
    checks.append(
        Check(
            "Default main-scene startup",
            (
                str(godot),
                "--headless",
                "--path",
                str(REPOSITORY_ROOT),
                "--quit-after",
                "2",
            ),
            120,
        )
    )
    if visual_capture:
        checks.append(
            Check(
                "Desktop fixed-scene visual capture",
                (
                    str(godot),
                    "--path",
                    str(REPOSITORY_ROOT),
                    "--script",
                    "res://scripts/tests/test_pixel_renderer_release_gate.gd",
                    "--",
                    "--require-visual-capture",
                ),
                180,
            )
        )
    if web_export:
        checks.append(
            Check(
                "Godot Web release export",
                (
                    str(godot),
                    "--headless",
                    "--path",
                    str(REPOSITORY_ROOT),
                    "--export-release",
                    "Web",
                ),
                600,
            )
        )
    return checks


def run_check(check: Check) -> tuple[bool, float, str]:
    print(f"\n=== {check.name} ===", flush=True)
    started = time.monotonic()
    try:
        result = subprocess.run(
            check.command,
            cwd=REPOSITORY_ROOT,
            check=False,
            timeout=check.timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        elapsed = time.monotonic() - started
        return False, elapsed, f"timed out after {check.timeout_seconds} seconds"
    except OSError as error:
        elapsed = time.monotonic() - started
        return False, elapsed, str(error)
    elapsed = time.monotonic() - started
    if result.returncode != 0:
        return False, elapsed, f"exited with status {result.returncode}"
    return True, elapsed, ""


def main() -> int:
    args = parse_args()
    try:
        godot = resolve_godot(args.godot)
    except FileNotFoundError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    if args.web_export:
        WEB_EXPORT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    checks = build_checks(godot, args.visual_capture, args.web_export)
    failures: list[str] = []
    suite_started = time.monotonic()
    for index, check in enumerate(checks, start=1):
        print(f"[{index}/{len(checks)}]", end=" ", flush=True)
        passed, elapsed, detail = run_check(check)
        if passed:
            print(f"PASS {check.name} ({elapsed:.2f}s)", flush=True)
            continue
        failure = f"{check.name}: {detail}"
        failures.append(failure)
        print(f"FAIL {failure} ({elapsed:.2f}s)", file=sys.stderr, flush=True)
    suite_elapsed = time.monotonic() - suite_started
    print("\n=== Pixel renderer release summary ===")
    print(f"Checks: {len(checks) - len(failures)}/{len(checks)} passed")
    print(f"Elapsed: {suite_elapsed:.2f}s")
    if failures:
        for failure in failures:
            print(f"- {failure}")
        return 1
    print("Focused pixel renderer release gate passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
