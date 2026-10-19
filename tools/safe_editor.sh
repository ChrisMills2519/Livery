#!/usr/bin/env bash
#
# Groom — OPTIONAL safety-net launcher for the Godot editor.
#
# ---------------------------------------------------------------------------
# STATUS: the root cause of the cold-start crash is FIXED. This script is no
# longer required — `godot --editor --path .` now works on a cold cache.
# It is kept only as a belt-and-braces option.
# ---------------------------------------------------------------------------
#
# ROOT CAUSE (measured 2026-10-15, Godot 4.7.stable, gl_compatibility renderer)
#
#   Three textures had `compress/mode=2` in their .import files, i.e. they were
#   set to VRAM Compressed (S3TC/ETC/BPTC):
#       Models/lowpoly_trees_0.png
#       Models/low_poly_nature_assets_1_0.jpg
#       Models/horse_riggedgame_ready_0.png
#   These are exactly the three textures the crash log named. This machine has
#   NO real VRAM: the GPU is Intel UHD "Jasper Lake" accessed through the virgl
#   virtual GPU (Mesa 22.3.6) in a Crostini container. Uploading S3TC/BPTC
#   compressed textures on that path segfaults the editor during the initial
#   asset import.
#
#   Evidence:
#     * cold GUI import, VRAM-compressed textures .... crashed 7/7 runs (52-93s)
#     * cold GUI import, those 3 set to Lossless ..... COMPLETED, 0 crashes
#     * with them Lossless and the MCP plugin ENABLED . COMPLETED in 117-159s
#     * headless import of all 118 assets ............ always exit 0
#     * peak RSS was ~850-940 MB in both crashing and surviving runs, so this
#       was never an out-of-memory problem
#
#   Two things that were investigated and RULED OUT:
#     * the KeeVeeG MCP editor plugin — the crash reproduces with the addon
#       deleted entirely (0 `[MCP]` lines in the log), originally at 2/2 runs
#     * the display driver — `--display-driver x11` crashed identically
#     * duplicate node names in scenes/stable.tscn — those caused a separate
#       "node name clashes" dialog and have been fixed, but not the segfault
#
# THE FIX THAT IS NOW APPLIED IN THIS PROJECT
#   * the 3 offending textures: compress/mode=2 -> 0 (Lossless)
#   * all 58 .import files: detect_3d/compress_to=1 -> 0, so the editor never
#     auto-switches a texture to VRAM compression again at import time
#
#   If you reimport assets or import new ones, keep them off VRAM compression
#   on this machine. If a cold start ever crashes again, the first thing to
#   check is:  grep -rl '^compress/mode=2' --include=*.import .
#
# USAGE
#   tools/safe_editor.sh              # optional: pre-import headlessly, then open
#   GODOT=/path/to/godot tools/safe_editor.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
CACHE_DIR=".godot"
# A complete import cache is ~45 MB. Anything well below that is cold/partial.
MIN_CACHE_MB=40

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "error: '$GODOT' not found on PATH. Set GODOT=/path/to/godot" >&2
  exit 1
fi

cache_mb=$(du -sm "$CACHE_DIR" 2>/dev/null | cut -f1) || cache_mb=0
[ -n "$cache_mb" ] || cache_mb=0

if [ "$cache_mb" -lt "$MIN_CACHE_MB" ]; then
  echo ">> import cache is cold (${cache_mb}MB) — pre-importing headlessly"
  echo ">> (headless import never touches the GPU path, so it is always safe)"
  "$GODOT" --headless --editor --quit --path .
  echo ">> headless import finished; cache is now $(du -sm "$CACHE_DIR" | cut -f1)MB"
else
  echo ">> import cache is warm (${cache_mb}MB) — skipping the headless pass"
fi

echo ">> opening the editor"
exec "$GODOT" --editor --path .
