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

## Normal-map auto-detection looks alarming but is safe

Godot 4.7 rewrites `.import` files the first time it sees a texture used as a normal or roughness map. The editor prints, once per texture:

```
...: Texture detected as used as a normal map in 3D. Enabling red-green texture compression to reduce memory usage (blue channel is discarded).
...: Texture detected as used as a roughness map in 3D. Enabling roughness limiter based on the detected associated normal map at ...
```

This only sets `compress/normal_map=1` and `roughness/mode=1`. It is **not** the VRAM-compression crash: with `compress/mode=0` the image is still stored lossless (WebP/PNG inside the `.ctex`), and the normal-map flag only changes mipmap generation. The 14 textures under `Models/split/` whose `_Image_2.png` files were detected in October 2026 are genuinely normal maps (flat `128,128,255`), so the change is correct; the 14 edits are legitimate.

The `ERROR: Attempting to parent and popup a dialog that already has a parent.` lines that arrive at the same time come from the editor's import progress dialog, one per reimported texture, and are the known benign Godot issue [#77426](https://github.com/godotengine/godot/issues/77426). They are not project code: this project has no `Window`/`AcceptDialog`/`.popup*()` usage. They stop when the reimports finish and need no fix.

`tools/check_editor_load.gd` guards the dangerous case: it fails if a normal map is VRAM-compressed or if its `detect_3d/compress_to` is nonzero, so it cannot silently flip to `mode=2` later.

## Touch controls and the touch-first rule

- `Device` (`scripts/device.gd`) picks the input mode. Force it with `GROOM_TOUCH=1` or `GROOM_TOUCH=0`. In debug builds, F3 toggles it at runtime.
- `TouchControls` (`scripts/touch_controls.gd`) owns the stick, look drag, CONTEXT / JUMP / LEAD / RESET cluster, grooming gestures and select swipe. It reads raw fingers, so don't route touch through Buttons on the play surface: emulated mouse only follows the first finger.
- **A pushed touch stick owns the movement frame.** `player_controller.steer_yaw()` returns the yaw captured when the thumb pushed the stick (`TouchControls.is_stick_pushing()`), and both the walk and `horse._ride()` map input through it. Releasing the stick hands the frame back to the camera. Keyboard and mouse are unchanged, so never swap this for a live `transform.basis` or the right thumb starts re-aiming again.
- **The root carries the view; the model carries the facing.** The player's `rotation.y` is the camera yaw: `_look()` turns it, the camera hangs off it, and the tooling aims with it. `_body_yaw` is where the character actually faces, and `_turn_body()` eases it toward the walk direction at `BODY_TURN_SPEED`, writing the model's local yaw as `_model_base_yaw + wrapf(_body_yaw - rotation.y, -PI, PI)` - the same wrap the mounted rider uses. Do not rotate the root toward the movement direction instead: the camera would swing with every step and every `player.rotation.y` aim in `tools/` would stop meaning "look this way". Footprints read `facing_yaw()` for the same reason.
- **Movement is the raw input vector rotated by the steering yaw.** `Input.get_vector` puts `move_forward` on the *negative* Y axis, because Godot's forward is -Z, so `Basis(Vector3.UP, steer_yaw()) * Vector3(input.x, 0, input.y)` is the walk direction and the same expression steers the horse. Building a forward vector (`-basis.z`) and multiplying it by `input.y` applies that negation a second time and swaps W and S; that inversion has been introduced once already.
- **The grooming session owns the player body.** It calls `player.set_model_hidden(true/false)`; `_update_model_visibility()` must keep its early return, or the camera rule turns the body back on a frame after the session hid it (`check_groom` fails on exactly that).
- **Touch grooming cleans above the thumb.** `TOUCH_BRUSH_OFFSET` lifts the paint point (and with it the red/green disk) 64 px, falling back to the finger when the lifted ray misses. The hoof pick stays on the finger. Touch painting must not use `_hud.is_pointer_over_ui()`; that hover belongs to the mouse path.
- **Two-finger orbit is sampled per frame** in `TouchControls._process`, and only zooms once the gap changes by more than `PINCH_TRIGGER` (10%) from where the second finger landed. Measuring per drag event, or zooming below the trigger, makes the camera fight the orbit.
- Touch look runs at `LOOK_GAIN` (0.55) of the mouse rate on purpose. Movement is camera-relative, so a 1:1 drag re-aims the heading mid-look and reads as spinning. Don't raise it toward 1.0; the mouse path is unaffected.
- The stick takes over from any finger resting in its half (`STICK_REST`), re-arms on a repeated press for an index whose release was lost, and is released on focus loss. Keep those guards: the stick is the only movement input on touch.
- **Touch-first rule for new work:** every new player-facing interaction needs a touch path in the same change. That means a CONTEXT offer (a `touch_context()` method in the `touch_context` group) or a gesture, plus a `Device.pick(keyboard, touch)` prompt. Never hardcode a key name in prompt text.
- Every new interaction also gets a case in `tools/check_touch.gd`. Keyboard-only tests should say so.
- Known check status before the touch work: `check_character_select` already failed (handoff timeout), and `check_lead` was flaky. `check_dog` also fails occasionally on timing.

## Web build and the Netlify deploy

- **Only deploy when the user explicitly asks.** Never deploy or re-deploy as a side effect of another change (a gameplay fix, a doc edit, a "while I'm here" upload), and never export-and-push to refresh the site on your own initiative. Build and test locally as much as you like; wait for the word before anything reaches Netlify. When they do ask, deploy only what they asked for and say which site and URL you touched.
- Browser builds go through the `Web` preset in `export_presets.cfg`. It is single-threaded on purpose, so the host needs no `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` headers.
- Export, then deploy the folder (hosting config lives in `netlify.toml`):

```bash
cd /home/chrismills029/liv/groom
godot --headless --path . --export-release "Web" build/web/index.html
netlify deploy --prod --dir=build/web --site=66c08511-2b84-47e1-98e2-1a96e0aebd05
```

- Live site: <https://groom-769.netlify.app>. Add `?touch=1` or `?touch=0` to the URL to force an input mode; without it the build decides from the touchscreen and `mobile` features, which an iPad reports as touch.
- The export is about 250 MB (212 MB `index.pck` + 39 MB `index.wasm`), so the first load on a tablet is slow over cellular. `build/` and `.netlify/` are git-ignored.
- Vercel is not an option on the current Hobby plan: it caps a deployment upload at 100 MB.
- This machine's Chromium has no WebGL2, so the browser preview can only prove the page and assets load. Rendering has to be checked on the iPad or another GPU-backed browser.

## The farmhouse interior

- `scenes/farmhouse.tscn` is a fully furnished two-storey farmhouse: sitting room, kitchen, hall, study and boot room downstairs; two bedrooms, bathroom, landing and gallery upstairs. The clear footprint is 19.05 x 15.59 m (three times the old 11 x 9 m floor area per room), with 3.0 m ground ceilings and 2.88 m upstairs. It is entered from the fantasy house in `scenes/main.tscn` and returns there through its front door.
- It is generated. `godot --headless --path . --script res://tools/build_farmhouse.gd` rewrites the scene, so change the plan tables at the top of that script (rooms, `WINDOWS`, `DOORS`, stair constants, the prop list, lamps) and not the `.tscn` by hand.
- Windows and doors are declared once in those tables; the wall openings, frames, sills, glass and leaves are all derived from them, so a moved opening cannot drift from its hole. The scene publishes the built `windows` and `doors` arrays as metadata, and `check_farmhouse` reads them rather than a second hand-copied list.
- There are no interior door leaves. The eight interior doorways are wide cased openings (1.6-1.8 m, heads at 2.45 m; 2.4 m between sitting room and kitchen); only the front and back exterior doors keep leaves. Do not reintroduce `scripts/interior_door.gd` into the house.
- Assets are Kenney's Furniture Kit and Food Kit, Quaternius's Ultimate House Interior, Shapespark's textiles, and Poly Haven plaster/floor/detail textures in `Models/interior/` (all CC0); provenance is in `Models/interior/SOURCE.txt`. The kit's models are roughly half life size and their pivots are offset, so `_prop` measures, centres and drops each one — do not nudge props by hand in the scene. The Quaternius round carpets are authored upright, so floors use Kenney's flat rugs.
- Furniture surfaces come from one shared material per real material, built by `_surface()` in the generator and saved once in the scene. The detail maps (`Models/interior/textures/detail_*`) are neutral-luminance greys at a 0.90 mean and are multiplied over the kit's own opaque colours, so the palette is unchanged; `_detail_gain` lifts the albedo by the reciprocal of the map's linear mean so the tone stays put. Kit materials are matched by name (`KIT_SURFACE`), Quaternius by name prefix (`_quat_surface`), and the Food Kit's 34 models all share the restored `kenney_food_kit/Textures/colormap.png` atlas. Do not go back to duplicating a material per prop, and do not give the furniture normal or ORM maps: this is the Compatibility renderer on a tablet, and one extra fetch per surface is the whole budget.
- `_prop` flattens each downloaded model into its own nodes instead of instancing the GLB. Instancing plus a surface override makes Godot save a duplicate clone of the mesh beside the instance, which renders twice and doubles that prop's triangles; flattening also lets every copy of a model share one mesh resource. Merged groups (`"merge":` in the PROP calls) fold a whole place setting into one mesh per material, and keep their piece count in the `merged_parts` meta that `check_farmhouse` reads.
- `tools/check_interior_cost.gd` is the speed budget: 980 mesh instances, 112k triangles, 115 materials, 60 textured materials, 20 textures and 20 MB of decoded texture memory for the house. It is deliberately tight; raise a number in the same change that needs it. `tools/check_editor_load.gd` guards the seven interior textures the house depends on (`INTERIOR_TEXTURES`: the four detail maps, the Food Kit atlas and the two 1k shell maps): lossless, mipmapped, with `detect_3d/compress_to` at 0. It loads every scene it finds under `res://scenes` instead of a hand-written list, because that list drifted and named two scenes that were never committed. The wall and floor maps are mipmapped on purpose even though the texture pass did not require it: they tile across the largest surfaces in the house and shimmer at a distance without mips, which is about 2.8 MB of decoded VRAM inside the 20 MB budget. Do not widen the check to sweep all of `Models/interior/`, and do not drop those two from the list without measuring first.
- Seats and beds are `scripts/interior_spot.gd` nodes under `Seats`. Adding one means adding it to the generator and to `tools/check_farmhouse.gd`, which asserts the count.
- The stair is L-shaped: lower flight up the east wall to a quarter landing, upper flight west along the south wall, finishing on the gallery. The stair constants at the top of the generator define both flights and the two well openings; `_walk_ramp` lays the walkable ramp for each flight, and the treads are decoration. The controller has no step-up logic, so no flight may pitch past 45 degrees and every ramp end must meet floor exactly — a lip stops the player dead.
- Balustrades are shoe, spindles and handrail with an invisible solid barrier behind them. Add collision with any new guard: the check walks at the well edges and at the open side of the flight.
- The front door is at z = 2.68 on the east wall, clear of the stair foot, and its inside spawn is `(8.35, 0.05, 2.68)` facing west. The study opening sits under the high end of the upper flight. Moving either means checking the stair geometry again.
- Interiors carry camera metadata on their root (`camera_max_boom`, `camera_pivot_height`, `camera_shoulder`). Do not use a group for this: `PackedScene` drops groups added after the root is created, which is how the 3 m outdoor boom stayed active in the house. `_apply_camera_profile()` walks up from the player to the metadata. `player_controller.gd` resolves the on-foot camera with a `ShapeCast3D` sphere (0.28 m) against walls and furniture: direct shoulder line, then a lateral line within 35 degrees (chair/desk behind), then a 0.45-0.95 m look-down from above the head (wall corner or doorway, only while the normal boom is under 0.90 m; the lower lifts fit under a door head). When the clear line is around a blocker it steps onto that line at a 0.62 m radius before easing out; without that step the straight ease crosses the blocker and stays pinned at the head. The body hides only below 0.58 m. The ride camera resets its pitch when mounted. The outdoor camera keeps its 3 m boom. The old ray-and-lerp camera is gone, so do not add a second clip path.
- The front door links both ways through `scripts/scene_door.gd`: the yard node is `FrontDoor` in `scenes/main.tscn`, the interior node is `FrontDoorExit` and comes from `_build_exit_door()` in the generator. Do not add it by hand to `farmhouse.tscn`. The interior leaf has its own collider, and the fantasy house has an invisible `5.9 x 3.5 x 5.9` shell so neither can be walked through.
- If you change either link, use `GameState.request_player_spawn(position, yaw_degrees)`; `scripts/player_controller.gd` consumes it on load. Do not hardcode player positions in the scenes.
- Checks: `godot --headless --path . --script res://tools/check_farmhouse.gd`, `res://tools/check_walkthrough.gd` and `res://tools/check_scene_doors.gd`. The first covers the ten room areas, no interior leaves, walkable cased openings, solid walls, all 32 windows, both stair flights walked on foot, furniture in every room, seats/resting and the indoor camera profile. `check_walkthrough` takes about two minutes and walks every route in motion, including both stair flights and camera sweeps into corners; it is the one that catches a doorway blocked by furniture or a camera that pops. Its settled floors are 1.0 m for a room and 0.90 m for a backed-into corner, with the body visible; do not lower them to the 0.35 m safety clamp, which is only for a true last resort. The door check in `check_farmhouse` sweeps a player-sized capsule, so a centre ray alone is not enough. `check_scene_doors` covers both links, the house shell, prompt, leaf collider and spawn handoff. `tools/check_editor_load.gd` also loads `farmhouse.tscn`.
- Screenshots: `tools/screenshot_farmhouse.gd` renders eight views. Pass names after `--` to render only some (`-- plan_ground bathroom`); the `plan_*` views hide the ceiling and the storey above. They restore the original visibility before each plan view, so render the upper plan before the ground plan when rendering both. `tools/screenshot_camera.gd` renders the player's own camera at the sitting corner (backed in), study desk, bath and landing; it keeps the body visible, and writes `artifacts/camera_*.png`. Run both under `xvfb-run` with `--rendering-driver opengl3` and `--resolution 1280x720`.

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
- Normal-map detection may set `compress/normal_map=1`; keep such textures on `compress/mode=0` as well. `tools/check_editor_load.gd` now fails if a normal map is VRAM-compressed or still has `detect_3d` enabled.
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
