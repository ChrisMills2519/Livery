#!/usr/bin/env python3
"""Build an iPad/phone web export without changing the project's local imports.

The editor on this machine (VirGL, no real VRAM) must keep every texture
lossless.  This tool leaves the working project untouched: it makes a
copy-on-write staging copy, applies mobile-only import and project settings
there, exports, and copies the finished web build back.

What it does in the staging copy only
-------------------------------------
* VRAM-compresses every non-UI texture to ETC2 (WebGL2 requires ETC2, so this
  works on iPad/iPhone Safari and on desktop WebGL2 too; no S3TC copy is
  included, which keeps the pck small).
* Uses `process/size_limit` to cap the heavy maps: 512 px for fences, terrain,
  tack, interiors, props and nature; 1024 px for the horse, dog and riders.
  The 2048 px terrain control map stays lossless at 1024 px because its alpha
  channel drives the ground blend.
* Drops the 4096 directional shadow atlas to 2048, lowers the soft-shadow
  filter to the cheap setting, and caps the frame rate at 60.
* Keeps the obstacle/fence library at 512 px.  Those maps live under
  `Models/horse_riding_obstacles...`, which the broad "Models/horse" hero
  prefix used to match, so they shipped as 1024 px maps (24 MiB in the pack).
* Prunes known-unused heavy assets and any model scene no scene/script/resource
  references (an exact `res://` path scan; there is no runtime directory scan).
* Drops imported `.scn`/`.ctex` cache files whose source no longer exists, so a
  removed GLB cannot leave its baked scene in the pack.
* Excludes build/, _respdump/, artifacts/ and dev-only tools/ from the export.
* Adds a small HTML head snippet that caps devicePixelRatio at 2 (helps iPhone;
  an iPad is already 2).

Usage
-----
    python3 tools/export_web_mobile.py
    python3 tools/export_web_mobile.py --out build/web-mobile --keep-stage
    python3 tools/export_web_mobile.py --no-prune
    python3 tools/export_web_mobile.py --in-place
    python3 tools/export_web_mobile.py --report-only   # rewrite the report only

The default output is `build/web-mobile`; the known-good `build/web` is never
overwritten.  The build log, `build-stats.json` and `OPTIMISATION.txt` are
written to a sibling folder (`build/web-mobile-report`) because Netlify uploads
every file in the deploy directory, and a 1 MB build log has no business on a
public URL.  Deploy with the usual Netlify command after checking the result:

    netlify deploy --prod --dir=build/web-mobile --site=66c08511-2b84-47e1-98e2-1a96e0aebd05

The terrain shader reconstructs the blue channel of its normal maps from
red/green.  VRAM-compressed normal maps (RGTC/ETC2) store only two channels;
sampling `.rgb` directly would make the ground render black in this export.

This tool is not a substitute for a real device check: load it on the iPad,
watch the first transition into the yard, and confirm the textures resolve.
The selection scene is also freed before the world loads (see scene_fade.gd),
so the handoff does not keep both scenes' textures resident at once.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRESET_NAME = "Web"
STAGE_PREFIX = "groom-web-mobile-"


def report_dir(out_dir: Path) -> Path:
    """Where the log, stats and optimisation report live.

    Deliberately beside the deploy folder, not inside it: `netlify deploy --dir`
    uploads everything it finds, so `export.log` and `OPTIMISATION.txt` used to
    be downloadable from the public site root.
    """
    return out_dir.with_name(out_dir.name + "-report")

# Top-level entries we never copy into the staging project.
COPY_SKIP = {
    ".git",
    "build",
    "_respdump",
    "artifacts",
    ".freebuff",
    ".agents",
    ".netlify",
    # Developer tooling, never loaded at runtime.  Leaving it in makes the
    # reference scan keep dead assets (force_import.gd names a clip GLB) and
    # ships its scripts in the pck.
    "tools",
}

# Heavy assets that are no longer referenced anywhere.  The script re-checks
# each entry against the project text before removing it; a hit aborts the
# prune for that entry instead of risking a runtime load.
EXPLICIT_UNUSED = [
    "Models/chihuahua_derp_dog.glb",
    "Models/chihuahua_derp_dog_0.png",
    "Models/chihuahua_derp_dog_1.png",
    "Models/chihuahua_derp_dog_2.png",
    # Ride-pose reference model: no scene, resource or script references it.
    "Models/ride_pose.glb",
    "Models/ride_pose_Image_0.jpg",
    "Models/ride_pose_Image_1.jpg",
    "Models/ride_pose_Image_2.jpg",
    "Models/ride_pose_Image_3.png",
    "Models/ride_pose_Image_4.jpg",
    "Models/ride_pose_Image_5.jpg",
    "Models/ride_pose_Image_6.jpg",
    "Models/ride_pose_Image_7.jpg",
    "Models/ride_pose_Image_8.jpg",
    "Models/ride_pose_Image_9.jpg",
    "Models/ride_pose_Image_10.png",
    "Models/ride_pose_Image_11.jpg",
    "Models/ride_pose_Image_12.jpg",
    "Models/lowpoly_trees.glb",
    "Models/lowpoly_trees_0.png",
    "Models/low_poly_nature_assets.glb",
    "Models/low_poly_nature_assets_1_0.jpg",
    "Models/horse_riggedgame_ready.glb",
    "Models/horse_riggedgame_ready_0.png",
    "Models/horse_riggedgame_ready_clips.glb",
]

# Text files used to decide whether a model is referenced at runtime.
REFERENCE_SUFFIXES = {
    ".tscn",
    ".tres",
    ".res",
    ".gd",
    ".gdshader",
    ".json",
    ".cfg",
    ".godot",
    ".txt",
}

# Directories where unused models are safe to drop: these are static asset
# libraries, never scanned at runtime.
PRUNE_MODEL_DIRS = ("Models/interior/kenney_furniture_kit", "Models/interior/kenney_food_kit")

TEX_KEEP_LOSSLESS = (
    "assets/images/",
    "assets/fonts/",
)

# Checked before the hero prefixes: the obstacle/fence library is a texture
# library first and a hero asset second, and 512 px is plenty at riding
# distance.
TEX_OBSTACLE_PREFIXES = (
    "Models/horse_riding_obstacles",
    "Models/split/horse_riding_obstacles",
    "Models/show_jumping",
    "Models/split/show_jumping",
)

# Hero textures: keep 1024 px so the riders, horse and dog still read well on
# an iPad.  Everything else falls to 512 px.
TEX_HERO_PREFIXES = (
    "Models/chris",
    "Models/liv",
    "Models/ride_pose",
    "Models/horse",
    "Models/chihuahua",
    "Models/horse_stable",
)

TEX_PREFIX_POLICY = [
    ("assets/textures/ground/", 512),
    ("Models/split/", 512),
    ("Models/tack/", 512),
    ("Models/interior/", 512),
    ("Models/props/", 512),
    ("Models/medieval_village/", 512),
    ("Models/lowpoly_trees", 512),
    ("Models/low_poly_nature", 512),
]


def log(message: str) -> None:
    print(message, flush=True)


def run(command: list[str], cwd: Path, log_path: Path, label: str) -> None:
    log(f"[{label}] {' '.join(command)}")
    started = time.time()
    with log_path.open("a", encoding="utf-8", errors="replace") as handle:
        handle.write(f"\n===== {label} ({time.strftime('%Y-%m-%d %H:%M:%S')}) =====\n")
        handle.flush()
        result = subprocess.run(command, cwd=str(cwd), stdout=handle, stderr=subprocess.STDOUT)
    elapsed = time.time() - started
    if result.returncode != 0:
        log(f"[{label}] FAILED after {elapsed:.0f}s — see {log_path}")
        raise SystemExit(result.returncode)
    log(f"[{label}] ok in {elapsed:.0f}s")


def copy_project(stage: Path) -> None:
    log(f"[stage] copy-on-write copy to {stage}")
    stage.mkdir(parents=True, exist_ok=True)
    for entry in ROOT.iterdir():
        if entry.name in COPY_SKIP:
            continue
        target = stage / entry.name
        reflink = subprocess.run(
            ["cp", "-a", "--reflink=auto", str(entry), str(target)],
            capture_output=True,
            text=True,
        )
        if reflink.returncode != 0:
            log(f"[stage] reflink failed for {entry.name}; falling back to a full copy")
            subprocess.run(["cp", "-a", str(entry), str(target)], check=True)
    log("[stage] done")


def read_text_files(stage: Path) -> str:
    chunks: list[str] = []
    for path in stage.rglob("*"):
        if not path.is_file():
            continue
        if any(part in {".git", "build", ".godot"} for part in path.parts):
            continue
        if path.suffix.lower() not in REFERENCE_SUFFIXES:
            continue
        try:
            chunks.append(path.read_text(encoding="utf-8", errors="replace"))
        except OSError:
            pass
    return "\n".join(chunks)


def remove_path(path: Path, removed: list[str], reason: str) -> None:
    if not path.exists():
        return
    removed.append(f"{path.name} ({reason})")
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()


def prune_assets(stage: Path, reference_text: str) -> list[str]:
    removed: list[str] = []

    for rel in EXPLICIT_UNUSED:
        path = stage / rel
        if not path.exists():
            continue
        # Match the exact res:// path.  A bare stem also matches shared
        # prefixes (horse_riggedgame_ready_clips is a prefix of the coat PNG
        # the material really uses), which kept dead assets in the pack.
        if f"res://{rel}" in reference_text:
            log(f"[prune] keeping {rel}: still referenced")
            continue
        remove_path(path, removed, "unused")
        # Remove the matching .import, if any.
        import_file = Path(str(path) + ".import")
        if import_file.exists():
            remove_path(import_file, removed, "unused import")

    for directory in PRUNE_MODEL_DIRS:
        base = stage / directory
        if not base.exists():
            continue
        for glb in sorted(base.rglob("*.glb")):
            rel_path = glb.relative_to(stage).as_posix()
            if f"res://{rel_path}" in reference_text:
                continue
            remove_path(glb, removed, "unreferenced model")
            import_file = Path(str(glb) + ".import")
            if import_file.exists():
                remove_path(import_file, removed, "unreferenced model import")

    # Drop local build/response caches that all_resources would otherwise pack.
    for rel in ("build", "_respdump", "artifacts"):
        remove_path(stage / rel, removed, "not part of the shipped project")

    log(f"[prune] removed {len(removed)} entries")
    return removed


def set_cfg_key(text: str, section: str, key: str, value: str) -> str:
    """Set a ConfigFile-style key in a section, appending the section if needed."""
    header = f"[{section}]"
    lines = text.splitlines()
    try:
        start = lines.index(header)
    except ValueError:
        if text and not text.endswith("\n"):
            text += "\n"
        return text + f"\n{header}\n\n{key}={value}\n"

    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index].strip()
        if line.startswith("[") and line.endswith("]"):
            end = index
            break

    for index in range(start + 1, end):
        if re.match(rf"^\s*{re.escape(key)}\s*=", lines[index]):
            lines[index] = f"{key}={value}"

    block = lines[start + 1 : end]
    if not any(re.match(rf"^\s*{re.escape(key)}\s*=", line) for line in block):
        # Keep a blank line between the section header and its keys.
        insert_at = start + 1
        while insert_at < end and lines[insert_at].strip() == "":
            insert_at += 1
        lines.insert(insert_at, f"{key}={value}")

    return "\n".join(lines) + "\n"


def patch_project(stage: Path) -> None:
    project = stage / "project.godot"
    text = project.read_text(encoding="utf-8")
    text = set_cfg_key(text, "rendering", "textures/vram_compression/import_etc2_astc", "true")
    text = set_cfg_key(text, "rendering", "textures/vram_compression/import_s3tc_bptc", "false")
    text = set_cfg_key(text, "rendering", "lights_and_shadows/directional_shadow/size", "2048")
    text = set_cfg_key(
        text,
        "rendering",
        "lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
        "1",
    )
    text = set_cfg_key(text, "application", "run/max_fps", "60")
    project.write_text(text, encoding="utf-8")
    log("[setup] project settings patched for mobile")


def patch_export_preset(stage: Path) -> None:
    preset = stage / "export_presets.cfg"
    text = preset.read_text(encoding="utf-8")
    text = re.sub(
        r'(?m)^vram_texture_compression/for_desktop=.*$',
        "vram_texture_compression/for_desktop=false",
        text,
    )
    text = re.sub(
        r'(?m)^vram_texture_compression/for_mobile=.*$',
        "vram_texture_compression/for_mobile=true",
        text,
    )
    # Cap DPR at 2 before the engine boots.  iPad is already 2; iPhone is 3.
    head = (
        "<script>\n"
        "(function(){\n"
        "  var real = window.devicePixelRatio || 1;\n"
        "  if (real > 2) {\n"
        "    try { Object.defineProperty(window, 'devicePixelRatio', { configurable: true, get: function(){ return 2; } }); } catch (e) {}\n"
        "  }\n"
        "})();\n"
        "</script>"
    )
    replacement = "html/head_include=" + json.dumps(head)
    if re.search(r"(?m)^html/head_include=.*$", text):
        text = re.sub(r"(?m)^html/head_include=.*$", lambda _: replacement, text)
    else:
        text = text.replace("[preset.0.options]\n\n", "[preset.0.options]\n\n" + replacement + "\n", 1)
    preset.write_text(text, encoding="utf-8")
    log("[setup] export preset patched (ETC2 only, DPR cap)")


def texture_policy(rel: str) -> tuple[int, int] | None:
    """Return (compress_mode, size_limit) or None to leave the import alone."""
    rel = rel.replace(os.sep, "/")
    if rel.endswith("terrain_control.png"):
        return (0, 1024)
    if rel.startswith(TEX_KEEP_LOSSLESS) or rel.endswith("icon.svg"):
        return None
    for prefix in TEX_OBSTACLE_PREFIXES:
        if rel.startswith(prefix):
            return (2, 512)
    if rel.startswith(TEX_HERO_PREFIXES):
        return (2, 1024)
    for prefix, limit in TEX_PREFIX_POLICY:
        if rel.startswith(prefix):
            return (2, limit)
    if rel.startswith("Models/"):
        return (2, 512)
    if rel.startswith("assets/") and rel.endswith((".png", ".jpg", ".jpeg", ".webp", ".tga")):
        return (2, 512)
    return None


def patch_texture_imports(stage: Path) -> dict[str, int]:
    counts = {"compressed": 0, "lossless": 0, "untouched": 0}
    for imp in stage.rglob("*.import"):
        if any(part in {".git", "build"} for part in imp.parts):
            continue
        try:
            text = imp.read_text(encoding="utf-8")
        except OSError:
            continue
        if 'importer="texture"' not in text:
            continue
        source_rel = str(imp.relative_to(stage))[: -len(".import")]
        policy = texture_policy(source_rel)
        if policy is None:
            counts["untouched"] += 1
            continue
        mode, limit = policy
        if not re.search(r"(?m)^compress/mode=", text):
            counts["untouched"] += 1
            continue
        text = re.sub(r"(?m)^compress/mode=.*$", f"compress/mode={mode}", text)
        text = re.sub(r"(?m)^compress/high_quality=.*$", "compress/high_quality=false", text)
        text = re.sub(r"(?m)^detect_3d/compress_to=.*$", "detect_3d/compress_to=0", text)
        text = re.sub(r"(?m)^mipmaps/generate=.*$", "mipmaps/generate=true", text)
        if re.search(r"(?m)^process/size_limit=", text):
            text = re.sub(r"(?m)^process/size_limit=.*$", f"process/size_limit={limit}", text)
        else:
            text = text.replace("[params]\n\n", f"[params]\n\nprocess/size_limit={limit}\n", 1)
        imp.write_text(text, encoding="utf-8")
        counts["compressed" if mode == 2 else "lossless"] += 1
    log(
        f"[setup] textures: {counts['compressed']} ETC2, "
        f"{counts['lossless']} lossless-limited, {counts['untouched']} untouched"
    )
    return counts


def clear_texture_cache(stage: Path) -> None:
    imported = stage / ".godot" / "imported"
    if not imported.exists():
        return
    removed = 0
    for path in imported.glob("*.ctex"):
        path.unlink()
        removed += 1
    for path in imported.glob("*.md5"):
        path.unlink()
        removed += 1
    log(f"[setup] cleared {removed} cached texture files (model cache kept)")


def purge_orphan_imports(stage: Path) -> None:
    """Remove imported scenes/textures whose source file was pruned.

    Godot's importer never deletes the cache entry for a removed source, and
    `all_resources` can still see that stale file.  Matching the encoded source
    name against the live project keeps the export honest.
    """
    imported = stage / ".godot" / "imported"
    if not imported.exists():
        return
    live = {path.name for path in stage.rglob("*") if path.is_file()}
    removed = 0
    for path in imported.iterdir():
        if path.suffix not in {".scn", ".ctex"}:
            continue
        match = re.match(r"(.+)-[0-9a-f]{32}(?:\.[a-z0-9_]+)?\.(?:scn|ctex)$", path.name)
        if match is None or match.group(1) in live:
            continue
        path.unlink()
        removed += 1
    log(f"[prune] removed {removed} orphaned imported resources")


def verify_scene_loads(stage: Path, log_path: Path) -> None:
    """Load the main scenes headlessly to catch pruned/missing dependencies."""
    scenes = ["res://scenes/character_select.tscn", "res://scenes/main.tscn"]
    for extra in ("farmhouse", "competition_arena", "show_course"):
        if (stage / "scenes" / f"{extra}.tscn").exists():
            scenes.append(f"res://scenes/{extra}.tscn")
    for scene in scenes:
        run(
            ["godot", "--headless", "--path", ".", "--quit-after", "2", scene],
            stage,
            log_path,
            f"verify {scene}",
        )


def pck_texture_audit(path: Path) -> tuple[list[str], list[str]]:
    """List packed textures above the obstacle budget plus the largest maps."""
    import struct

    data = path.read_bytes()
    if data[:4] != b"GDPC":
        return [], []
    base = struct.unpack("<Q", data[24:32])[0]
    dir_offset = struct.unpack("<Q", data[0x20:0x28])[0]
    count = struct.unpack("<I", data[dir_offset : dir_offset + 4])[0]
    offset = dir_offset + 4
    over: list[str] = []
    entries: list[tuple[int, str]] = []
    for _ in range(count):
        name_length = struct.unpack("<I", data[offset : offset + 4])[0]
        offset += 4
        name = data[offset : offset + name_length].decode("utf-8", "replace").rstrip("\0")
        offset += name_length
        offset += (-name_length) % 4
        file_offset, file_size = struct.unpack("<QQ", data[offset : offset + 16])
        offset += 16 + 16 + 4
        if not name.endswith(".ctex"):
            continue
        start = base + file_offset
        width, height = struct.unpack("<II", data[start + 8 : start + 16])
        label = f"{width}x{height} {name.rsplit('/', 1)[-1]}"
        entries.append((file_size, label))
        if max(width, height) > 512 and any(
            key in name for key in ("wooden_fence", "obstacle", "show_jumping")
        ):
            over.append(label)
    entries.sort(reverse=True)
    biggest = [f"  {size / 1048576:7.2f} MiB  {label}" for size, label in entries[:8]]
    return over, biggest


def pck_texture_levels(path: Path) -> list[str]:
    """Group packed textures by resolution so the size budget stays visible."""
    import struct

    data = path.read_bytes()
    if data[:4] != b"GDPC":
        return []
    base = struct.unpack("<Q", data[24:32])[0]
    dir_offset = struct.unpack("<Q", data[0x20:0x28])[0]
    count = struct.unpack("<I", data[dir_offset : dir_offset + 4])[0]
    offset = dir_offset + 4
    levels: dict[tuple[int, int], list[int]] = {}
    for _ in range(count):
        name_length = struct.unpack("<I", data[offset : offset + 4])[0]
        offset += 4
        name = data[offset : offset + name_length].decode("utf-8", "replace").rstrip("\0")
        offset += name_length
        offset += (-name_length) % 4
        file_offset, file_size = struct.unpack("<QQ", data[offset : offset + 16])
        offset += 16 + 16 + 4
        if not name.endswith(".ctex"):
            continue
        start = base + file_offset
        width, height = struct.unpack("<II", data[start + 8 : start + 16])
        bucket = levels.setdefault((width, height), [0, 0])
        bucket[0] += 1
        bucket[1] += file_size
    rows = sorted(levels.items(), key=lambda kv: -kv[1][1])
    return [
        f"  {w}x{h}: {maps:3d} maps  {size / 1048576:6.2f} MiB"
        for (w, h), (maps, size) in rows
    ]


def pck_payload(path: Path) -> dict[str, int]:
    """Sum packed bytes per extension, so the report can show what the pck is made of."""
    import struct

    payload: dict[str, int] = {}
    with path.open("rb") as handle:
        if handle.read(4) != b"GDPC":
            return payload
        handle.seek(0x20)
        dir_offset = struct.unpack("<Q", handle.read(8))[0]
        handle.seek(dir_offset)
        count = struct.unpack("<I", handle.read(4))[0]
        for _ in range(count):
            name_length = struct.unpack("<I", handle.read(4))[0]
            name = handle.read(name_length).decode("utf-8", "replace").rstrip("\0")
            handle.read((-name_length) % 4)
            _, file_size = struct.unpack("<QQ", handle.read(16))
            handle.read(16)
            handle.read(4)
            ext = Path(name).suffix.lower() or "(none)"
            payload[ext] = payload.get(ext, 0) + file_size
    return payload


def transfer_sizes(out_dir: Path) -> list[str]:
    """Report raw and compressed transfer sizes for the files a browser fetches.

    Brotli runs at quality 9 rather than 11: q11 is roughly twenty times slower
    on this payload, which is not worth an extra ten minutes per build, and it
    only buys a few percent over q9 on already-packed binary data.
    """
    import zlib

    try:
        import brotli  # type: ignore
    except ImportError:
        brotli = None

    rows: list[str] = []
    wire = 0.0
    for name in ("index.pck", "index.wasm"):
        path = out_dir / name
        if not path.exists():
            continue
        raw = path.stat().st_size
        gz = 0
        compressor = zlib.compressobj(9, zlib.DEFLATED, 31)
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(8 << 20), b""):
                gz += len(compressor.compress(chunk))
        gz += len(compressor.flush())
        line = f"  {name:12s} raw {raw / 1048576:7.1f} MiB   gzip(q9) {gz / 1048576:7.1f} MiB"
        if brotli is not None:
            br = 0
            stream = brotli.Compressor(quality=9, lgwin=22)
            with path.open("rb") as handle:
                for chunk in iter(lambda: handle.read(4 << 20), b""):
                    br += len(stream.process(chunk))
            br += len(stream.finish())
            line += f"   brotli(q9) {br / 1048576:7.1f} MiB"
            wire += br / 1048576
        else:
            wire += gz / 1048576
        rows.append(line)
    if rows:
        rows.append(f"  wire total (compressed pck + wasm): {wire:7.1f} MiB")
        rows.append("  served raw today: both files are binary, so the CDN sends them uncompressed")
    return rows


def pck_summary(path: Path) -> tuple[int, int, dict[str, int]]:
    import struct

    size = path.stat().st_size
    entries = 0
    formats: dict[str, int] = {}
    with path.open("rb") as handle:
        if handle.read(4) != b"GDPC":
            return size, 0, formats
        handle.seek(0x20)
        dir_offset = struct.unpack("<Q", handle.read(8))[0]
        handle.seek(dir_offset)
        count = struct.unpack("<I", handle.read(4))[0]
        for _ in range(count):
            name_length = struct.unpack("<I", handle.read(4))[0]
            name = handle.read(name_length).decode("utf-8", "replace").rstrip("\0")
            handle.read((-name_length) % 4)
            handle.read(16)  # offset + size
            handle.read(16)  # md5
            handle.read(4)  # flags
            entries += 1
            ext = Path(name).suffix.lower()
            formats[ext] = formats.get(ext, 0) + 1
    return size, entries, formats


def existing_verification(out_dir: Path) -> str:
    """Return the hand-written device-verification block from a previous report."""
    report = report_dir(out_dir) / "OPTIMISATION.txt"
    if not report.exists():
        return ""
    existing = report.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"\n(Verified on this build.*?)\n\nRedeploy:", existing, re.S)
    return match.group(1) if match else ""


def write_report(
    out_dir: Path,
    stage: Path,
    counts: dict[str, int],
    removed: list[str],
    verified: str = "",
    baseline: int = 0,
) -> list[str]:
    original = ROOT / "build" / "web" / "index.pck"
    optimized = out_dir / "index.pck"
    orig_size = original.stat().st_size if original.exists() else baseline
    orig_note = "" if original.exists() or not baseline else " (previous build)"
    opt_size = optimized.stat().st_size if optimized.exists() else 0
    _, entries, formats = pck_summary(optimized) if optimized.exists() else (0, 0, {})
    over, biggest = pck_texture_audit(optimized) if optimized.exists() else ([], [])
    payload = pck_payload(optimized) if optimized.exists() else {}
    levels = pck_texture_levels(optimized) if optimized.exists() else []
    total_payload = sum(payload.values()) or 1
    top_payload = [
        f"  {ext:12s} {size / 1048576:7.1f} MiB  {100.0 * size / total_payload:5.1f}%"
        for ext, size in sorted(payload.items(), key=lambda kv: -kv[1])[:5]
    ]
    wire = transfer_sizes(out_dir)

    lines = [
        "WEB / iPAD EXPORT — optimisation report",
        "=" * 42,
        "",
        f"Source: {ROOT}",
        f"Stage:  {stage}",
        f"Output: {out_dir}",
        "",
        f"Original pck:  {orig_size / 1048576:8.1f} MiB{orig_note}" if orig_size else "Original pck:  (not present)",
        f"Optimised pck: {opt_size / 1048576:8.1f} MiB",
    ]
    if orig_size and opt_size:
        lines.append(f"Reduction:     {100.0 * (1.0 - opt_size / orig_size):7.1f}%")
    lines += [
        "",
        f"Pck entries: {entries}",
        "Extensions: " + ", ".join(f"{k}={v}" for k, v in sorted(formats.items())),
        "",
        "Textures:",
        f"  ETC2 compressed: {counts['compressed']}",
        f"  lossless (limited): {counts['lossless']}",
        f"  untouched (UI): {counts['untouched']}",
        "",
        "Export-only changes:",
        "  compress/mode=2 (ETC2), ETC2 only in the pck",
        "  process/size_limit: 512 obstacles/fences/props/terrain/tack, 1024 heroes and dog",
        "  obstacle override is checked before the broad Models/horse hero prefix",
        "  orphaned .scn/.ctex imports of pruned sources removed",
        "",
        "Pck payload:",
        *top_payload,
        "",
        "Texture resolution:",
        *levels,
        "",
        "Transfer size (what the browser downloads):",
        *wire,
        "",
        "Largest packed textures:",
        *biggest,
        "",
        ("Obstacle/fence textures above 512 px: none"
         if not over else f"WARNING: {len(over)} obstacle/fence textures above 512 px"),
        *[f"  {item}" for item in over[:10]],
        "  terrain_control.png: lossless, 1024 px",
        "  compressed normal maps: terrain shader rebuilds the blue channel",
        "  directional shadow atlas: 2048 (soft filter: low)",
        "  max fps: 60",
        "  devicePixelRatio capped at 2 in the web shell",
        "  outgoing selection scene freed before the world load",
        "  build/, _respdump/, artifacts/ excluded",
        "",
        "Pruned entries:",
    ]
    lines += [f"  {item}" for item in removed]
    # A hand-written device-verification block survives a rebuild or a
    # --report-only run; the numbers above are regenerated, that note is not.
    verified = verified or existing_verification(out_dir)
    lines += [
        "\n\n" + verified if verified else "",
        "",
        "Redeploy:",
        "  netlify deploy --prod --dir=build/web-mobile --site=66c08511-2b84-47e1-98e2-1a96e0aebd05",
        "  (check it on a real iPad/iPhone the first time it goes live)",
        "",
        "The working project's .import files and .godot cache were not modified.",
        "",
    ]
    destination = report_dir(out_dir) / "OPTIMISATION.txt"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(lines), encoding="utf-8")
    return over


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default="build/web-mobile", help="output directory (default: build/web-mobile)")
    parser.add_argument("--in-place", action="store_true", help="replace build/web instead of writing build/web-mobile")
    parser.add_argument("--no-prune", action="store_true", help="keep unused assets (do not prune)")
    parser.add_argument("--keep-stage", action="store_true", help="keep the staging project for inspection")
    parser.add_argument("--skip-verify", action="store_true", help="skip headless scene-load checks")
    parser.add_argument("--dry-run", action="store_true", help="stage and patch only; no import/export")
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="rewrite OPTIMISATION.txt and the transfer sizes from the existing build",
    )
    args = parser.parse_args()

    out = ROOT / (args.out if not args.in_place else "build/web")
    if args.report_only:
        stats_path = report_dir(out) / "build-stats.json"
        stats = json.loads(stats_path.read_text(encoding="utf-8")) if stats_path.exists() else {}
        over = write_report(
            out,
            Path(stats.get("stage", "(existing build)")),
            stats.get("counts", {"compressed": 0, "lossless": 0, "untouched": 0}),
            stats.get("removed", []),
            baseline=int(stats.get("original_pck", 0)),
        )
        log(f"[report] wrote {report_dir(out) / 'OPTIMISATION.txt'}")
        return 1 if over else 0
    stage = Path(tempfile.mkdtemp(prefix=STAGE_PREFIX, dir="/tmp" if Path("/tmp").exists() else None))
    log_path = report_dir(out) / "export.log"
    out.mkdir(parents=True, exist_ok=True)
    report_dir(out).mkdir(parents=True, exist_ok=True)

    try:
        copy_project(stage)
        log("[setup] building reference index")
        reference_text = read_text_files(stage)
        removed = [] if args.no_prune else prune_assets(stage, reference_text)
        patch_project(stage)
        patch_export_preset(stage)
        counts = patch_texture_imports(stage)
        clear_texture_cache(stage)
        if args.dry_run:
            log(f"[dry-run] staged project ready at {stage}")
            log(f"[dry-run] report would go to {out}")
            return 0

        run(["godot", "--headless", "--path", ".", "--import"], stage, log_path, "import")
        purge_orphan_imports(stage)
        if not args.skip_verify:
            verify_scene_loads(stage, log_path)
            verification_log = log_path.read_text(encoding="utf-8", errors="replace")
            if "Failed to load" in verification_log or "Cannot open file" in verification_log:
                log("[verify] missing resource after prune; see export.log — aborting")
                return 1

        (stage / "build" / "web").mkdir(parents=True, exist_ok=True)
        run(
            ["godot", "--headless", "--path", ".", "--export-release", PRESET_NAME, "build/web/index.html"],
            stage,
            log_path,
            "export",
        )
        built = stage / "build" / "web"
        if not (built / "index.pck").exists():
            log("[export] no index.pck produced; see export.log")
            return 1

        # Read the previous device-verification note before the output directory
        # is cleared, so a rebuild keeps it.
        previous_verification = existing_verification(out)
        if out.exists():
            for item in out.iterdir():
                # Everything here is uploaded, so clear it all -- including an
                # export.log left behind by an older layout that wrote the log
                # into the publish folder.
                if item.is_dir():
                    shutil.rmtree(item)
                else:
                    item.unlink()
        for item in built.iterdir():
            target = out / item.name
            if item.is_dir():
                shutil.copytree(item, target)
            else:
                shutil.copy2(item, target)

        (report_dir(out) / "build-stats.json").write_text(
            json.dumps(
                {
                    "stage": str(stage),
                    "counts": counts,
                    "removed": removed,
                    "original_pck": (
                        (ROOT / "build" / "web" / "index.pck").stat().st_size
                        if (ROOT / "build" / "web" / "index.pck").exists()
                        else 0
                    ),
                },
                indent=1,
            ),
            encoding="utf-8",
        )

        over = write_report(out, stage, counts, removed, previous_verification)
        if over:
            log(f"[audit] {len(over)} obstacle/fence textures are still above 512 px:")
            for item in over[:10]:
                log(f"[audit]   {item}")
            return 1
        orig = ROOT / "build" / "web" / "index.pck"
        new = out / "index.pck"
        if orig.exists():
            log(
                f"[done] pck {orig.stat().st_size / 1048576:.1f} MiB -> "
                f"{new.stat().st_size / 1048576:.1f} MiB "
                f"({100.0 * (1.0 - new.stat().st_size / orig.stat().st_size):.0f}% smaller)"
            )
        else:
            log(f"[done] pck {new.stat().st_size / 1048576:.1f} MiB")
        log(f"[done] wrote {out}")
        log(f"[done] report: {report_dir(out) / 'OPTIMISATION.txt'}")
        return 0
    finally:
        if args.keep_stage or args.dry_run:
            log(f"[stage] kept at {stage}")
        else:
            shutil.rmtree(stage, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
