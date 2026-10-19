# Groom — devlog and troubleshooting notes

## Incompatible machine

Godot 4.7.stable (GL Compatibility renderer) on a Chromebook Crostini container with *no real VRAM*:

- Display: Wayland via XWayland, `DISPLAY=:0`, `XDG_SESSION_TYPE=wayland`
- GPU: Intel UHD "Jasper Lake" (VirGL / Mesa 22.3.6) → `OpenGL API 4.3`
- RAM: ~2.7 GB total, ~1.7 GB available, no swap
- Godot: `/usr/local/bin/godot` 4.7.stable.official
- MCP driver: `@keeveeg/godot-mcp` (npx), 386 tools, connected as the `godot` server in `~/.agents/mcp.json`

The project uses the GL Compatibility renderer and is ~51 MB of import cache (236 files) once warm.

## The crash you saw

`godot` crashes with `SIGSEGV / signal 11` (sometimes crashing the whole system) when the editor starts on a *cold* import cache and has to import the 118 project assets (47 GLB models) for the first time. You saw it twice, and both times it showed that exact log.

Later (after all fixes below) testing reproduced it 7/7 times and then comfortably survived. Root cause is fixed.

## Root cause

A small number of textures in the project are set to **VRAM Compressed (S3TC/BPTC)** by their `.import` files. That is exactly the thing that crashes on this machine — there is no persistent VRAM for the GPU to upload those compressed textures to.

In particular, the three textures named in your crash log:

- `Models/lowpoly_trees_0.png`
- `Models/low_poly_nature_assets_1_0.jpg`
- `Models/horse_riggedgame_ready_0.png`

were set to `compress/mode=2` (VRAM‑compressed). In Godot 4 text mode, `compress/mode=2` means VRAM‑compressed. These are 1024x1024 images, so even once the crash is gone the loss in memory is small (around 16 MiB lossless versus 4 MiB compressed).

Every other import file in the project was 0 (Lossless), and the clone/project you are using for this is otherwise plain.

## Fix (already applied here)

1. Set all three to `compress/mode=0` (Lossless) in their `.import` files.
2. Set `detect_3d/compress_to=0` in every other `.import` file so that neither on‑import reimport nor 3D reprobe will auto‑switch any texture to VRAM compression again.
3. Re‑import the whole project via `godot --headless --editor --quit --path .` so the cache is fully built with the corrected settings.

The plugin and the project editor are otherwise unchanged.

## A side bug in the same scene

The 3D scene `scenes/stable.tscn` contained four CollisionShape3D nodes all named `%sShape` as children of `PaddockCollision` — duplicate sibling names, which would produce Godot’s “name clash” dialog during scene reload. Those were renamed to `ColX_A`, `ColX_B`, `ColZ_A`, `ColZ_B`. No scripts were found to reference that name, so the rename is safe.

## MCP / agent setup here

- The Godot editor plugin for the AI agent lives at `addons/godot_mcp/plugin.cfg` and is registered in `project.godot` under `[editor_plugins]`. You connect to it via `@keeveeg/godot-mcp` (npx), giving you 386 Godot tools.
- The connector config in `~/.agents/mcp.json` has a `godot` server entry that runs `cd /home/chrismills029/liv/groom && exec npx -y @keeveeg/godot-mcp`. **You must open the Godot editor on this project for MCP tools to work.**
- There is also a headless fallback connector (`godot-headless`) using `@coding-solo/godot-mcp` (14 tools) that you can keep as a backup; it works without the GUI editor.
- A helper script `tools/safe_editor.sh` exists. It used to be treated as the solution but its comments now reflect the corrected root cause — it is a *belt and braces* renderer-safe hydration script only.

## A note on what this is *not*

- The crash is not a project-data problem. Headless re‑importing all assets finishes successfully, and the exported game runs headlessly without errors.
- It is not the Godot MCP plugin. We tested with the plugin removed entirely (the server entry in `~/.agents/mcp.json` too) and the crash still happened.
- It is not the editor side of Godot itself. Even on a clean, newly-imported headless build, the same textures crashed if left VRAM-compressed. It is a texture-compression configuration issue.
- It is not a memory exhaustion problem. Peak memory during cold runs was about 850–940 MB, well under the ~1.7 GB available.

## Reusable commands

Hyper‑linked references:

- [Images: Low-poly nature assets](./Models/low_poly_nature_assets_1_0.jpg) — the 1024×1024 JPEG
- [Images: lowpoly trees](./Models/lowpoly_trees_0.png) — the 1024×1024 PNG
- [Images: Horse rigged game ready 0](./Models/horse_riggedgame_ready_0.png) — the 1024×1024 PNG

The way to start editing here:

```bash
cd /home/chrismills029/liv/groom
godot --editor --path .
```

Before you pipe an MCP client (Claude Code, Cursor, etc.), make sure the editor is running. If you ever need to re-check the import settings on those three textures, they are line 1 of each `.import` file:

Run against norms `grep -rE '^compress/mode=' Models` from the project root.

## Checklist for anyone continuing this on the same machine

- Keep those three textures on `compress/mode=0`, never VRAM compressed.
- Keep `detect_3d/compress_to=0` everywhere in `.import` files, so that 3D texture switching cannot reintroduce the crash during import.
- Re‑import headlessly (`godot --headless ... --quit`) before opening the editor whenever the cache is cold.
- If you are setting this up in another project, check image dimensions before enabling VRAM compression — 1024×1024 or larger with many such textures is the risk profile.
- Prefer `godot --editor --path .` as the launch command, not a bare `godot`, and note that MCP is only available while the editor is running.

## Files changed by the fixes

- `Models/lowpoly_trees_0.png.import`
- `Models/low_poly_nature_assets_1_0.jpg.import`
- `Models/horse_riggedgame_ready_0.png.import`
- every other `*.import` file in the project (detect_3d switch)
- `scenes/stable.tscn` (the duplicate-name scene reload bug, exactly `PaddockCollision/%sShape`)
- `tools/safe_editor.sh` (corrected comments)

## If the crash ever comes back

Run this immediately to get a fresh headless import cache, then open the editor:

```bash
cd /home/chrismills029/liv/groom
godot --headless --editor --quit --path .
godot --editor --path .
```

If it still crashes, use this as a pre‑flight check:

```bash
grep -rE '^compress/mode=2' Models/  # any texture left VRAM compressed?
```

If that shows anything, turn it back to 0. If it shows nothing and it still crashes, it may be a different crash and is worth reporting with the full Godot output.

## MCP‑specific gotchas

- The server is a bridge to the editor over localhost; it expects the editor to be open. If the editor is closed, the MCP tools will not work.
- The connector registry in `~/.agents/mcp.json` is per‑machine and was rebuilt from what we know is in this project now. If the MCP tools are missing from your client, check the `godot` entry there and that the editor runs.
- The headless fallback (`godot-headless`) uses a different server package (`@coding-solo/godot-mcp`). It does not expose 386 tools but it is the way to continue agent work when the editor cannot stay open.

---

*End of notes.*
