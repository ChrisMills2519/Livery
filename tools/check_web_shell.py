#!/usr/bin/env python3
"""Check the exported web loading screen and the files the host will serve.

    python3 tools/check_web_shell.py [--dir build/web-mobile]

This is the guard for everything that lives outside the game: the branded shell
that tools/export_web_mobile.py injects, and the object list tools/deploy_r2.py
publishes.  Both failure modes it covers are silent otherwise.

* A build where Godot's shell template moved: the exporter asserts its anchors
  and stops, but a build made before that check, or one assembled by hand, would
  publish Godot's default page and look fine from the outside.
* An object the deployer will not upload.  `deploy_r2.py` takes its file list
  from its own OBJECTS table and skips names it cannot find, so a screenshot
  that is missing from the export directory becomes a 404 on a phone -- the
  loading screen losing its logo, with nothing in the deploy output saying so.

A checkout with no export is not a failure: there is nothing to check yet, and
CI runs this before anything is built.  It says so and exits 0.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIR = ROOT / "build" / "web-mobile"
DEPLOY_TOOL = ROOT / "tools" / "deploy_r2.py"

# The branded screen, by the parts that must survive into the export.  The
# progress element keeps Godot's id on purpose: the engine drives it, so losing
# it would leave a bar that never moves.
BRANDING_MARKERS = [
    'id="ginger-splash"',
    'id="ginger-logo"',
    'id="ginger-livery"',
    'id="ginger-bar"',
    'id="ginger-puller"',
    'id="ginger-percent"',
    'id="status-progress"',
    'id="status-notice"',
    "gingerSplash.set(current, total)",
    "--ginger-progress",
]

STAMP = re.compile(r'id="build-version"[^>]*>([^<]+)<')
LOCAL_SOURCE = re.compile(r'(?:src|href)="([^":#?]+\.(?:png|jpg|jpeg|svg|webp|js|css))"')


def deploy_objects() -> list[str]:
    """The names tools/deploy_r2.py will publish, read from that file itself."""
    spec = importlib.util.spec_from_file_location("deploy_r2", DEPLOY_TOOL)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load {DEPLOY_TOOL}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return list(module.OBJECTS)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dir", default=str(DEFAULT_DIR), help="export directory (default: build/web-mobile)")
    args = parser.parse_args()
    out = Path(args.dir).resolve()
    index = out / "index.html"

    if not index.exists():
        print(f"[web-shell] SKIP - no export at {out} to check (run tools/export_web_mobile.py)")
        return 0

    failures: list[str] = []
    text = index.read_text(encoding="utf-8", errors="replace")

    for marker in BRANDING_MARKERS:
        if marker not in text:
            failures.append(f"index.html is missing {marker}")

    if "$GODOT" in text:
        failures.append("index.html still carries an unsubstituted $GODOT placeholder")

    stamp = STAMP.search(text)
    if stamp is None:
        failures.append("index.html has no build stamp")
    else:
        stats = out.with_name(out.name + "-report") / "build-stats.json"
        if stats.exists():
            version = json.loads(stats.read_text(encoding="utf-8")).get("version", "")
            if version and version.strip() != stamp.group(1).strip():
                failures.append(f"index.html shows {stamp.group(1).strip()!r} but the build was {version.strip()!r}")

    # Every file the shell asks for, and every file the deployer will offer.
    for name in sorted(set(LOCAL_SOURCE.findall(text))):
        if not (out / name).exists():
            failures.append(f"index.html asks for {name}, which is not in the export")

    for name in deploy_objects():
        if not (out / name).exists():
            failures.append(f"deploy_r2.py would publish {name}, which is not in the export")

    for name in ("index.pck", "index.wasm"):
        if not (out / name).exists():
            failures.append(f"the export has no {name}")

    if failures:
        for failure in failures:
            print(f"[web-shell] FAIL - {failure}")
        return 1

    print(
        "[web-shell] PASS - loading screen branded, stamp"
        f" {stamp.group(1).strip()!r}, {len(deploy_objects())} objects present"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
