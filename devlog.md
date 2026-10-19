# Groom devlog

2026-10-15

## Outcomes

- The terminal-side crash you saw — `godot` crashing with SIGSEGV at editor start on this machine — is now understood, reproduced, and fixed.
- The root cause is a small set of textures configured as **VRAM-compressed (S3TC/BPTC)** in their `.import` files, which is unsupported on this machine’s GPU (Intel UHD, VirGL renderer, no real VRAM).
- The fix is already applied: those three textures are now Lossless, and `detect_3d/compress_to=0` is set everywhere so future imports cannot reintroduce the crash.
- A full cold re-import was done headlessly afterward, so the cache is now correct and complete.
- A separate scene bug in `scenes/stable.tscn` — four CollisionShape3D nodes all named `%sShape` under `PaddockCollision` — was also fixed (renamed).

## What we changed

### Import settings (the actual crash fix)

- `Models/lowpoly_trees_0.png.import`
- `Models/low_poly_nature_assets_1_0.jpg.import`
- `Models/horse_riggedgame_ready_0.png.import`

Each set to `compress/mode=0` (Lossless).

#### All `.import` files

- Every `.import` file in the project had `detect_3d/compress_to` set from `1` to `0` so that no texture auto-switches into VRAM compression during import or 3D probing.

### Scene

- `scenes/stable.tscn`
- Renamed `PaddockCollision/%sShape` (x4) into `ColX_A`, `ColX_B`, `ColZ_A`, `ColZ_B`.

### Labels / documentation

- `tools/safe_editor.sh` comment block updated to reflect the corrected root cause.
- Added `agents.md` and `devlog.md` for the project.

#### Exact file changes

- `Models/lowpoly_trees_0.png.import` — `compress/mode=0`
- `Models/low_poly_nature_assets_1_0.jpg.import` — `compress/mode=0`
- `Models/horse_riggedgame_ready_0.png.import` — `compress/mode=0`
- Every other `*.import` — `detect_3d/compress_to=0`
- `scenes/stable.tscn` — renamed four CollisionShape3D children
- `tools/safe_editor.sh` — reworded root cause
- `agents.md` — created
- `devlog.md` — created

## Agent tooling

- The `godot` MCP connector in `~/.agents/mcp.json` now has two server entries:
  - `godot` → `@keeveeg/godot-mcp` (386 tools) running in the editor once it's open.
  - `godot-headless` → `@coding-solo/godot-mcp` (14 tools) can act without the editor open.

## Reproducibility

We tested cold-start launches explicitly:

- Before the fix: crash on cold cold GUI imports, with or without the MCP plugin.
- After the fix: cold-import survives, and the editor stays up with the MCP plugin loaded.

## No regressions

- Headless game run exits cleanly.
- No new editor errors beyond the original startup.

## To re-apply or re-verify

If you ever see the crash again after working on this project on this machine:

```bash
cd /home/chrismills029/liv/groom
grep -rE '^compress/mode=2' Models/  # should print nothing
godot --headless --editor --quit --path .
godot --editor --path .
```

If the grep shows anything, reset that texture’s import to Lossless.

## Future reminders

- Keep `compress/mode=0` on the three textures above.
- Keep `detect_3d/compress_to=0` in `.import` files.
- If you re-import assets or use a different project, check texture import settings first.

## Where this machine differs

- It is a Crostini container (ChromeOS Linux) with a virtual GPU and no VRAM, so any Godot setup here has to avoid GPU-dependent crashes on import of big textures, even before the project logic matters.
- The MCP server only works while the editor is open.
- The headless fallback MCP server is useful when the editor can't stay up.

# Session close

All of today’s work is reflected in the fixed import settings, the renamed collision shapes, the updated script comment, and the new project notes. Any further agent sessions should start from the headless re-import cache rather than from a cold editor launch.

2026-10-18

## Horse animation split

- `Models/horse_riggedgame_ready.glb` had one 60.33 s animation, `Animations`, with every action packed back to back at 24 fps.
- Added `tools/split_horse_animations.py`, a headless Blender script that copies the take into 20 named actions, pushes each onto its own single-strip NLA track and exports `Models/horse_riggedgame_ready_clips.glb`. The original GLB is untouched.
- Gaits found by forward-kinematics hoof analysis: trot 29.5–33.3 s, canter 33.3–35.6 s, walk 35.6–39.0 s. The old runtime windows (walk 46–48.4 s, canter 39–42 s) were pointing at standing still and at the lie-down/get-up section.
- `scenes/horse.tscn` now instances the new GLB and keeps the 180° model rotation.
- `scripts/animation_state_machine.gd` no longer slices at runtime. It plays the named clips `Idle_Look_A`, `Walk`, `Trot`, `Canter`, sets them to loop, crossfades over 0.15 s, and exposes `play_action()` for the one-shot clips (Graze, Rear, Buck, ...).
- `tools/check_horse_animations.gd` verifies the 20 clips, their lengths, loop modes and the FSM state headlessly.
- The extracted texture `Models/horse_riggedgame_ready_clips_Image_0.png.import` is Lossless with `detect_3d/compress_to=0`, matching the no-VRAM machine rules above.
- Verification: all 20 clips import with the expected lengths; bone poses match the source within 5 µm, rest pose and mesh AABB within 4 µm; the main scene runs headless with no errors.

## Mounting and the riding seat

- Mounting already existed, but it placed the player's **feet** on the saddle, kept the standing locomotion idle, and left the seat marker fixed to the horse root, so the rider floated and ignored the gait.
- `scenes/horse.tscn` gained a `RiderSeat` marker on the back surface and a billboarded `MountPrompt` (`E  MOUNT`).
- `scripts/horse.gd` now computes the seat marker's offset to the `Bip01 Spine1_04_20` bone once and reapplies it every physics frame, so the saddle socket rises and pitches with the animated spine; the prompt is visible only when the player is in `mount_range` and nobody is riding.
- `scenes/player.tscn` gained a `SeatContact` marker and a `RidePose` node. Mounting disables the player collider, stops the locomotion mixer, activates the riding overlay, rotates the visible rider to face the same way as the horse, and translates the player so the pelvis sits `HIPS_TO_SEAT` (0.10 m) above the saddle socket. The camera pivot drops and the camera pulls back while riding, both blended.
- The player's `GeneralSkeleton` is a humanoid retarget with different local rest axes than `chris.glb`, so an exported Blender clip did not reproduce the authored pose. `scripts/ride_pose.gd` therefore applies the pose directly to the skeleton in model space: thighs angle down and out, shins hang nearly vertical, feet level with toes up, upper arms down, forearms forward and hands over the withers, with a small chest/neck sway. This is the plan's documented retarget fallback.
- `assets/animations/ride.res` and `tools/build_ride_library.gd` remain as the authored reference pipeline; the scene no longer loads the clip because the runtime overlay is authoritative.
- `tools/check_mount.gd` verifies the seat error, the hips-above-saddle distance, the twelve key riding-pose bone directions, the rider/horse yaw, collision state, the mount prompt, the camera blend, and dismount landing; the checks are time-based because headless runs far faster than 60 fps. `tools/screenshot_mount.gd` renders the review shots in `artifacts/mount_*.png`.
- Verification on 2026-10-18: `MOUNT CHECK: PASS`, `HORSE ANIMATION CHECK: PASS`; the five mounted renders were inspected and show a seated rider with clear legs and forward hands.
- The new `Models/ride_pose_*.import` textures follow the project's Lossless / `detect_3d/compress_to=0` rule, so they cannot reintroduce the earlier VRAM-compression crash.
- At the time, the horse asset had no saddle mesh, so the rider sat bareback on the socket; the fitted saddle, bridle and reins are added in the next section.

## Riding state machines, jumping and the first gameplay loop

2026-10-18

### State machine audit (fixes)

- The horse could never reach trot or canter while ridden: the old ride speeds were walk 2.5 / run 4.5 m/s, but the FSM thresholds were 3.2 / 4.8 m/s. `scripts/horse.gd` now uses walk 2.5, trot 4.5, canter 7.2 m/s, `scripts/animation_state_machine.gd` thresholds are 3.4 / 5.8 m/s, and the reference speeds are per-gait instead of reusing the trot threshold for walk.
- The old `_reference_speed("walk")` returned the trot threshold, so the walk clip always played at 0.78x. Each gait now matches its own cruise speed.
- Speed matching now runs only when a gait clip is playing, and playback scale is reset when the horse goes airborne.
- The FSM gained an explicit airborne state with an optional `air_animation` hook, so a jump can no longer be overwritten by a speed tick while the horse is in the air. One-shot actions are no longer cleared by gait changes.
- The player was playing `unarmed-crouch-run` from `loco.res` as its **walk** and had no landing state. `scripts/player_controller.gd` now uses the `humanoid` library already attached to `player.tscn`: Idle, Walk, Sprint, Jump, Jump_Land. Added blend times, an air state, a landing state and on-foot jumping.
- `tools/check_mount.gd` now expects `humanoid/Idle` after dismounting.

### Jumping

- There is **no jump clip** in the horse asset. The 20 clips are idle/paw/look/graze/trot/canter/walk/lie down/stand up/rear/buck/head toss; Rear and Buck are the closest.
- Added a phase-driven airborne pose in `scripts/horse_jump_pose.gd`: it aims the spine, neck, front and hind leg chains at takeoff, apex and descent directions in skeleton space and blends that over the gait. It runs after the AnimationPlayer (process priority 100) and is only active while airborne.
- The FSM still has `air_animation = "Jump"`; if a real clip is later added to the GLB, `has_air_clip()` becomes true and the overlay disables itself.
- Jump input is Space (`jump` action). The horse jumps at 9.0 m/s vertical + 0.05 per jumping skill point (apex ~2.0 m, air time ~0.9 s), only when mounted, grounded and not already airborne.
- Riding now accelerates through the gaits: hold run to trot, keep holding for `gait_hold_time` (0.9 s) to canter. Airborne steering only turns the body; forward momentum is preserved.
- `scripts/ride_pose.gd` folds the rider into a two-point position while the horse is airborne (deeper hip tilt, torso forward, hands toward the withers).

### First gameplay loop

- Opened the arena: removed two east fence sections and split the east collision shape, so there is now a ~7 m gate at `(-15, -1.5)`.
- `scripts/riding_course.gd` builds collision boxes for the three fences from their mesh AABBs (top 0.9 m), numbers the fences, and draws a gate beam and label. The rounds start when the mounted horse passes through the gate (or enters the arena, including by jumping the fence).
- Fences only count when the horse is airborne and above 0.75 m. Clearing all three stops the clock, pays `25 + 15/fence + 0.5/second under 120 s`, records the best time in the new `GameState` autoload, and adds jumping/fitness training to the horse. A full clear adds +3 jumping.
- The round auto-resets after 6 s (fences reset, gate arms again once the horse leaves the arena); `R` resets early. The result card and the HUD are built in code by `scripts/hud.gd` (money, jumping level, best round, objective, timer, fence count, toast).
- Verification tools: `tools/check_jump_and_loop.gd` (gaits, jump arc, double-jump rejection, fence detection, reward, reset, on-foot jump/landing) and `tools/check_fence_jump.gd` (the horse is physically blocked by a fence on the ground and clears the same fence when jumping at 4.5 m/s). `tools/screenshot_jump.gd` and `tools/screenshot_loop.gd` render the jump phases, gate, HUD, result card and walking player into `artifacts/`.

## Fitted saddle, bridle and live reins

2026-10-18

- Measured the horse before modeling: back top 1.43–1.49 m, barrel ~0.52 m wide and ~0.65 m deep (≈2.2 m girth), mouth/bit ~1.15 m forward and ~1.38 m high, bit rings ±0.10 m. The saddle seat sits in the seat dip at 1.57 m; the rider's hips are 0.10 m above it.
- `tools/build_tack.py` is the reproducible Blender build. It exports:
  - `Models/tack/horse_saddle.glb` — pad, seat with pommel/cantle, flaps, knee rolls, girth and buckle, D-rings, stirrup leathers, irons and treads.
  - `Models/tack/horse_bridle.glb` — browband, noseband, cheekpieces, throatlatch, snaffle bit and `BitAnchor_L/R` empties.
- `scenes/horse.tscn` gained a `Tack` node (180° yaw, matching the model's authored space) with the saddle and bridle instances. `RiderSeat` moved from the rear rise to the seat dip at `(0, 1.57, 0.03)`.
- `scripts/horse.gd` attaches the saddle to `Bip01 Spine1_04_20` and the bridle to `Bip01 Head_06_5`. The rig's bone bases carry a large arbitrary roll, so the tack keeps the bone's yaw and pitch and discards the roll, then rotates around the bone's rest pivot and follows its translation. The rider's seat follows the saddle, so it stays centred instead of drifting with the spine twist. The bridle bit rings are exposed through `get_bit_anchor()`.
- `scripts/player_controller.gd` exposes `get_hand_anchor()` from the `LeftHand`/`RightHand` bones. `scripts/reins.gd` (on a `Reins` node in `player.tscn`) rebuilds a thin leather ribbon from each bit anchor to its hand every frame, with a small Bézier sag, using an `ImmediateMesh`. The reins therefore stay attached through walk, trot, canter and the jump instead of being baked to either rig.
- `tools/check_tack.gd` runs headless and verifies the seat marker is inside the seat mesh, the girth wraps the barrel, both stirrup treads are within 0.14 m of the boots, both bit anchors are within 0.65 m of the head bone, the reins are a plausible 0.25–1.4 m long, and the rein mesh is visible with geometry while mounted. `tools/screenshot_tack.gd` renders `artifacts/tack_side.png`, `tack_rear.png`, `tack_front.png`, `tack_rider.png`, `tack_head.png` and `tack_jump.png`.
- Verification on 2026-10-18: `TACK CHECK: PASS` (stirrup/boot offset ≈0.04 m horizontal and ≈0.10 m vertical; reins 1.10–1.16 m), `MOUNT CHECK: PASS`, `RIDE LOOP CHECK: PASS`, `FENCE JUMP CHECK: PASS`, `HORSE ANIMATION CHECK: PASS`; the main scene runs headless with no errors. Renders inspected at the side, front, head and jump apex.
- Housekeeping: `Models/liv_0.png` and `liv_1.png` were still VRAM-compressed in their `.import` files, which violates this machine's no-VRAM rule. Both are now Lossless with `detect_3d/compress_to=0`, and `tools/check_editor_load.gd` reports `ALL OK`.
- Limitations: the tack is low-poly (no flocked panels or stitched seams), the reins are a swept ribbon rather than a simulated strap, and the saddle fit is authored for this horse rather than adjusted per conformation.

### Verification on 2026-10-18

- `RIDE LOOP CHECK: PASS`
- `FENCE JUMP CHECK: PASS` (ground approach stops at z=-13.31; jumping clears and counts the fence)
- `MOUNT CHECK: PASS`
- `HORSE ANIMATION CHECK: PASS`
- `TACK CHECK: PASS`
- `tools/check_editor_load.gd`: ALL OK
- Main scene runs headless with no errors or warnings.
- Renders inspected: jump takeoff/apex/descent/landed, arena gate, live round HUD, result card, walking player.

### Limitations / next

- The jump is a procedural pose, not an authored Blender clip. A proper 0.9 s Jump action in the split GLB is the upgrade; the FSM already prefers an air clip when one exists.
- The saddle, bridle and reins are now modeled and fitted; see the saddle section above.
- The core loop does not yet include feeding, grooming or stall cleaning; the ride → school → earn → train loop is complete, and care is the next system.

## Painted ground blend and selectable player bodies

2026-10-18

### Ground surfaces

- The four ground surfaces (stable yard, path, training ground, arena) used to be separate `PlaneMesh` rectangles floating 1–2 cm above a 200×200 grass plane. Their straight edges and mismatched tiling read as rugs, so they are gone.
- Added `assets/textures/ground/terrain_control.png`, a 2048×2048 RGBA control map covering a 128 m square centred on `(10, -5)`. R = yard dirt, G = path, B = training sand, A = arena sand; grass is the remainder. The map is 83% grass, feathered for 0.9–2.4 m at the borders, with extra wear at the arena gate and the path ends. Max weight sum is 1.00.
- `tools/build_ground_control.py` regenerates the base mask deterministically with numpy/PIL (rounded regions + two octaves of edge noise + gate/path wear). The committed PNG can be hand-painted over in Krita/GIMP; rerun the script only when the layout rectangles move.
- Added `res/shaders/terrain_blend.gdshader` and `resources/materials/terrain_blend.tres`. The shader samples the four tiled albedo/normal pairs in world space (grass 15 m, dirt 2.1 m, path 5 m, sand 2.5 m), normalizes the painted weights, adds low-frequency macro variation, and blends normals explicitly through TANGENT/BINORMAL. It is Compatibility-renderer-safe: no screen texture, decals or texture arrays.
- `scenes/terrain.tscn` is now one `GroundBlend` mesh at y=0; `scenes/main.tscn` keeps `Ground` as collision only. The old grass mesh/material and the four overlay nodes are removed. `cast_shadow = 0` on the ground plane to avoid self-shadow acne.
- No terrain add-on. Terrain3D 1.0.2 targets Godot 4.4–4.6 (this project is 4.7), its texture arrays are the risky path on this VirGL/no-VRAM machine, and a flat 200 m yard does not need a clipmap heightfield. A painted control map plus one shader is the smaller, safer tool.
- Verification: `tools/verify_look.gd` checks all nine textures (lossless, mipmaps, no `detect_3d` compression, control map keeps its RGB next to alpha=0) and the new material; `tools/check_terrain_blend.gd` samples the map against the world layout (all four regions dominant, grass remainder empty, yard edge R=0.07, gate wear, 16k-point sweep) and confirms no legacy overlay nodes. `tools/screenshot_terrain.gd` renders a top-down plus five eye-level shots into `artifacts/terrain_*.png`.
- Limitation: the terrain stays flat at y=0 so prop grounding and arena collision remain valid. Height sculpting is still a later step.

### Player bodies

- Both GLBs are already imported with the same `SkeletonProfileHumanoid` bone map into a `GeneralSkeleton`: Chris is an Avaturn rig (52 bones, 1.89 m), Liv is a Mixamo rig (65 bones, 1.47 m, root scale baked into the import). Rest poses match the GLBs; the old scene pose overrides were not needed.
- Added `scripts/player_model_profile.gd` and `resources/characters/chris.tres` / `liv.tres`. A profile carries the scene, facing, scale, hips-to-seat distance, stirrup lift, hand offset and riding camera offsets.
- `scripts/player_controller.gd` now instances the selected profile into the `Model` slot, then rebases every track in `assets/animations/humanoid.res` from `%GeneralSkeleton` onto the active skeleton's real relative path (`Armature/GeneralSkeleton` or `Node/GeneralSkeleton`). That is what lets one clip library drive both rigs without a Blender retarget. `set_character()` swaps a body without restarting the scene; `F2` cycles profiles in debug builds; `GROOM_CHARACTER=liv` runs any scene/tool with Liv for testing.
- `scripts/ride_pose.gd` gained `rebuild_for_skeleton()` so it recaptures the rest pose, hips and targets after a swap. The reins follow the new hand bones automatically.
- Liv is 42 cm shorter, so her boots stopped 26 cm above the adult stirrup treads. Added `scripts/stirrup_fit.gd` to `Tack/Saddle`: it shortens each stirrup leather about its buckle and raises the iron and tread by the profile's `stirrup_lift` (0.26 m for Liv, 0 for Chris), then resets on dismount. `tools/check_tack.gd` now also verifies the applied lift and that the shortened leather still meets its iron and buckle.
- Deleted `scenes/liv.tscn`; it was a duplicate player scene with no controller. Liv is now a profile in the one player scene.
- `tools/check_character_swap.gd` mounts Chris, swaps to Liv, checks the seat/ride pose/stirrup lift, swaps back and dismounts. This covers the runtime path behind the F2 debug key.
- Verification (2026-10-18): `PLAYER MODEL CHECK: PASS` for both bodies (height, bone set, Idle actually moving the skeleton, seat error 0.000 m, hips 0.100 m above the saddle, reins ~1.0–1.1 m); `CHARACTER SWAP CHECK: PASS` (Chris 52 bones / Liv 65 bones / Chris, seat 0.000 m each, stirrup lift 0.000/0.260/0.000); `MOUNT CHECK: PASS` for Chris and Liv; `TACK CHECK: PASS` for Chris and Liv (Liv stirrups dxz 0.12–0.13, dy 0.001–0.009, leather gaps 0.084/0.035); `RIDE LOOP CHECK: PASS` and `FENCE JUMP CHECK: PASS` with both; `VERIFY LOOK`, `TERRAIN BLEND CHECK`, `VERIFY SCENERY`, `HORSE ANIMATION CHECK` and `CHECK EDITOR LOAD` all pass. Renders: `artifacts/chris_idle.png`, `chris_walk.png`, `liv_idle.png`, `liv_walk.png`, `liv_tack_*.png`, `liv_mount_*.png`.
- Limitations: the on-foot camera pivot is still tuned for Chris; the stirrup leather is scaled, not re-stitched; footsteps are still grass-only regardless of surface. The character-select screen below now provides the player-facing body choice.

### Character model import audit

- Found and fixed a latent second mixer: Liv's GLB still imported its embedded Mixamo `AnimationPlayer`. The controller stopped it, but the node stayed in the body and could be woken by a later scene change, competing with the shared humanoid library.
- `Models/liv.glb.import` now sets `animation/import=false`. As a belt-and-braces guard, `player_controller.gd` removes (not just stops) any embedded `AnimationPlayer` a profile GLB brings, and `tools/check_player_models.gd` now fails if the active model still carries one. The one-off audit tool was removed after the invariant moved into the standing check.
- The local `.godot/imported` cache predated the import setting, and headless editor runs would not regenerate a cache whose `.scn` had been deleted. The cache was rebuilt in an isolated project from the same source, import parameters and texture UIDs; the rebuilt scene loads Liv with no warnings (the first rebuild referenced the temp project's texture UIDs). Fresh imports use the project's `.import` file, so `animation/import=false` is the reproducible path.
- Re-verified after the change: `PLAYER MODEL CHECK`, `CHARACTER SWAP CHECK`, `MOUNT CHECK` / `TACK CHECK` for Chris and Liv, `RIDE LOOP CHECK` / `FENCE JUMP CHECK` for both, `CHECK EDITOR LOAD` and `VERIFY LOOK` all pass.

## Character select and mounted handoff

2026-10-18

- `project.godot` now boots `scenes/character_select.tscn`. It is a real 3D studio, not a captured image: a plinth, accent ring, soft gradient backdrop, key/fill/rim lights and a camera framed for the active body. Both GLBs are instanced once and the inactive one is hidden, so switching bodies does not hitch on a model load.
- `scripts/character_select.gd` builds the screen entirely in code. The active body plays `humanoid/Idle` through the shared library on a slowly turning turntable; dragging the mouse takes over the spin and lets it ease back when released. Cards, arrow keys/A-D, number keys and Enter/Space drive the selection.
- Extracted `scripts/humanoid_animation.gd`; both the player and the preview use the same track-rebasing step, so the two bodies keep sharing one clip library. Profiles gained `role`, `blurb`, `accent` and `preview_yaw_degrees` presentation data for the screen. Chris needed a -90° preview correction; Liv's authored forward already faces the camera.
- Handoff is one-shot state on `GameState`: `choose_character(profile, start_mounted)` survives the scene change, and the player consumes it in `_ready`, steps beside the horse, waits for the floor, mounts, and only then re-enables movement. `SceneFade` is an autoload state machine (not an await chain) so the cover survives the scene swap, holds through the synchronous load and fades the mounted game back in.
- Verification: `CHARACTER SELECT CHECK: PASS` covers both previews and skeletons, the Idle clip, real turntable motion, card copy/accent changes, keyboard right/left/number selection, Enter starting the transition, the fade completing, and the mounted handoff to Liv (65 bones, 0.000 m seat error, controls enabled). `check_editor_load.gd` now includes the new scene. Renders: `artifacts/character_select_chris.png`, `character_select_liv.png`, `character_select_handoff.png`.
- Regression after the change: `PLAYER MODEL CHECK`, `CHARACTER SWAP CHECK`, `MOUNT CHECK` and `TACK CHECK` for both bodies, `RIDE LOOP CHECK`, `FENCE JUMP CHECK`, `HORSE ANIMATION CHECK`, `TERRAIN BLEND CHECK`, `VERIFY LOOK`, `VERIFY SCENERY` and `CHECK EDITOR LOAD` all pass.
- Limitations: no gamepad or touch bindings yet; there is no in-game route back to the select screen; opening `main.tscn` directly still starts on foot (the mounted start is only requested by the select screen).

## Tack look pass: leather textures + bridle rework

2026-10-18

- Downloaded CC0 leather packs from ambientCG into `Models/tack/textures/` (`Leather030` dark brown leather, `Leather039` suede); `tools/build_tack.py` downloads and extracts them on demand, so the build stays reproducible and works offline after the first run.
- Root cause of the flat look: the tack meshes had no UVs at all plus four constant-color materials, so nothing could carry grain next to the textured horse. Every mesh now gets world-scale cube-projected UVs (0.34 m tile) so grain density is uniform across parts, and the leather/suede materials use base color + roughness + OpenGL normal maps (`metallicFactor=0`, which zeroes the roughness image's blue channel so metalness cannot leak).
- Shading: smooth with 45° auto-smooth (lofts/bands/tori were faceted) and a 3.5 mm bevel on flap, knee-roll, tread and buckle edges so highlights catch.
- Bridle rebuilt against measured head cross-sections (skull top at y=-0.97: z=1.855, half-width 0.115; ear bases y=-1.00…-1.04; forehead front y=-1.075 at z=1.80; muzzle station y=-1.20: z=[1.296,1.580], half-width 0.074):
  - New **crownpiece** arcs over the poll behind the ears — no strap ran over the top before, so the others floated.
  - **Browband** was a full encircling loop (it passed under the jaw, rx=0.135 against a 0.134 head); now a surface-fitted forehead arc ending on the crown ends where the cheekpieces branch.
  - **Noseband** was rx=0.108 against an 0.074 muzzle (~3 cm float per side); now hugs the measured muzzle station.
  - **Cheekpieces** re-rooted at the crown, routed down in front of the eye to the bit rings; **throatlatch** hangs as a loose V under the jaw.
  - Bit, rings and `BitAnchor_L/R` unchanged at the mouth corners, so the live reins needed no edits.
- Exported GLB JSON verified: `TEXCOORD_0` on every primitive, embedded color/roughness/normal images, `metallicFactor=0`, `BitAnchor_L/R` present, and all `Saddle_*` node names that Godot looks up preserved.
- Verification: `TACK CHECK`, `MOUNT CHECK`, `HORSE ANIMATION CHECK`, `RIDE LOOP CHECK`, `FENCE JUMP CHECK` all pass; `check_editor_load` reports `ALL OK` (embedded GLB textures create no VRAM `.import` entries, so the no-VRAM rule holds).
- Renders re-inspected: `artifacts/tack_side.png`, `tack_rider.png`, `tack_head.png`, `tack_jump.png` show textured leather with visible grain, beveled edges, and the fitted bridle (cheekpiece to bit ring, noseband on the blaze, browband below the ears).
- Limitations: low-poly tack — no flocked panels, stitching, keeper loops or buckle tongues; the suede seat reads lighter than the leather flaps; the fit is authored for this horse rather than adjustable per conformation.

## Grooming bay and coat care

2026-10-18

- Added a grooming bay at `(-8, 0, -12.5)` in `scenes/main.tscn`: a rubber mat, a low back rail, a proximity prompt and a `G` interaction (`groom` action). Standing at the groomer anchor with the horse nearby shows `G · GROOM`; the bay refuses entry while mounted or when the horse is elsewhere.
- `scripts/grooming_session.gd` owns the session: it freezes the horse in `Idle_Standing_A`, hides the tack and player model, releases the player camera, hides the gameplay HUD and the riding-course labels, swaps in a 38° orbit camera (right-drag orbit, wheel zoom), and restores every saved value on exit. `Esc` or the HUD's DONE button finishes; the result card's RETURN button leaves.
- The toolset is curry comb (`1`), dandy brush (`2`), soft brush (`3`), face brush (`4`) and hoof pick (`5`). Curry only loosens body coat; dandy lifts body/leg dirt; soft only polishes coat that is already at least half clean; face is limited to the head. Invalid zones produce short contextual hints instead of silently doing nothing. Hoof clumps are only shown while the pick is selected; clicking one clears that hoof.
- `scripts/groom_surface.gd` bakes a 256×256 RGBA mask from the horse mesh at load: R = clean, G = polished, B = curried, A = groomable. A second byte map records the dominant zone (coat/leg/face/mane/tail) and a UV-island map is kept for diagnostics. The bake is deferred 0.2 s so the character-select handoff does not block on it; it measured 449 ms headless (2914 triangles).
- `scripts/groom_picker.gd` rebuilds CPU-skinned triangle positions when the session starts, then finds the nearest ray hit in skeleton space. The session converts the hit to world space and paints through `paint_hit`; the cursor ring follows the same ray. Painting is guarded by the baked alpha and the zone map. The brush does not require the exact UV shell under the cursor: a 2.2× UV radius boost reaches the narrow neighbouring coat shells while the zone map still keeps the face brush off the body. This fixed a brush that only affected a few hundred texels per stroke.
- `res/shaders/horse_groom.gdshader` replaces the horse's imported unlit material. It adds a fine two-octave dirt speckle, subtle curried lift, clean-coat lift and a fresnel sheen for polished areas. `mask_view` is a diagnostic overlay (brown dirty, amber curried, green clean, gold polished); it is display-only and hides the hand brush. Dirt level is stored on the horse, so a partial groom survives leaving the bay and a completed groom leaves a clean coat.
- `scripts/horse.gd` gained `begin_grooming` / `end_grooming`, hoof state, cleanliness/polish and trust/happiness. Rewards are paid against the best care score so brushing the same clean patch cannot farm trust; a second visit to a fully clean horse pays nothing. The horse stays in the idle pose with the tack hidden for the session and returns to `Idle_Look_A` on exit.
- `scripts/grooming_hud.gd` is the session UI: CLEAN/SHINE bars, hoof count, tool list, mask legend, hints/toasts, mask toggle and a result card with trust/happiness gains. The gameplay HUD is restored untouched on exit.
- Verification: `tools/check_groom.gd` (`GROOMING CHECK: PASS`) covers the bay prompt, the real `G` action, camera/controls/HUD/tack swap, body pick, tool and zone restrictions, curry → dandy → soft values, mask-view isolation, hoof selection, completion, the result card, exit restoration, a second visit and the no-farming rule. `tools/smoke_groom.gd` is a quick diagnostic print. `tools/screenshot_grooming.gd` renders `artifacts/grooming_dirty.png`, `grooming_hooves.png`, `grooming_brushed.png`, `grooming_mask.png`, `grooming_clean.png` and `grooming_result.png`.
- Regressions: `CHARACTER SELECT CHECK`, `MOUNT CHECK`, `TACK CHECK`, `RIDE LOOP CHECK`, `FENCE JUMP CHECK` and `CHECK EDITOR LOAD` pass. The character-select handoff check budget was widened from 5.5 s to 9 s because the synchronous main-world load now runs about six seconds on this machine; the assertions (mounted player, cleared fade, seat fit) are unchanged.
- Limitations: the mask is 256×256 and the UV-shell boost trades exact brush footprint for usable coverage; the shader is intentionally unlit to match the imported horse art; mane/tail are not groomable; there are no gamepad bindings for the grooming camera/tools yet; the 5–6 s world load is still a hitch before the bay is available.

<!-- end -->
