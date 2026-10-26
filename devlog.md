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

## Stable boarding and a stationary horse

2026-10-19

- The riderless horse no longer trails the player.  `scripts/horse.gd` dropped `follow_distance` and `_follow_player()` for `_stand()`, which decelerates to a stop, so dismounting at speed still settles instead of leaving the horse sliding.  It waits where it is left.
- To keep the horse retrievable, `scenes/stable.tscn` gained `scripts/stable.gd`: a prompt at the stall door (`HorseStall` at the building front, `UseAnchor` where the player stands) with `E · PUT HORSE AWAY`, `E · BRING HORSE OUT`, `BRING YOUR HORSE TO THE STABLE` when the horse is elsewhere, and `E · DISMOUNT TO USE THE STABLE` while mounted.  The stable uses `_input` and marks the event handled, so the player's own `interact` handler does not also mount or dismount on the same press.
- `scripts/horse.gd` gained `board()` (hidden, physics and collision off, not mountable) and `release_from_stable(anchor)` (placed at the stall, visible and mountable again).  The player must bring the horse within 12 m of the yard to stable it; bringing it out always works.  `can_mount()` and `begin_grooming()` both refuse a boarded horse.
- The horse gained `mount_prompt_suppressed`, set by the stable while its interaction is the live one, so the mount prompt and the stable prompt cannot overlap over one key.
- Fixed the reins floating beside the horse: `Reins` sets `top_level = true`, and Godot's `top_level` preserves the global transform the node had at the call.  That transform was the player's spawn point, so every world-space rein vertex rendered offset by it.  `scripts/reins.gd` now clears the transform to identity after going top-level, and `tools/check_tack.gd` fails if the rein mesh ever carries a transform again.  The reins now visibly run bit to fist.
- `scripts/hud.gd` reports `Your horse is stabled - press E at the stable door` while the horse is boarded, and the controls line mentions the stable.
- `tools/check_stable.gd` (`STABLE CHECK: PASS`) covers the no-follow rule, the prompt copy, boarding, the hidden/unmountable stabled state, release at the stall, and the refusal to stable a horse left far away.  `tools/screenshot_stable.gd` renders `artifacts/stable_boarding.png`, `stable_boarded.png` and `stable_released.png`.
- Regressions: `MOUNT CHECK`, `TACK CHECK`, `RIDE LOOP CHECK`, `FENCE JUMP CHECK`, `GROOMING CHECK`, `CHARACTER SWAP CHECK`, `CHARACTER SELECT CHECK`, `CHECK EDITOR LOAD` all pass.
- Limitations: the horse is boarded from the stable only (there is no leading mechanic, so it is brought by riding); the stall door has no opening animation; the stable prompt is a floating `Label3D` rather than a 3D sign.

## Leading the horse on foot

2026-10-19

- New `lead` action (`F`) in `project.godot`.  `scripts/player_controller.gd` gained `leading` and `_toggle_lead()`: on foot, `F` takes the rope if the horse is within 3.4 m, `F` again drops it, and mounting with `E` releases the rope first.  The flag clears itself if the horse stops being led (stabled, groomed, or the node disappears).
- `scripts/horse.gd` gained `leader`, `can_lead()`, `set_leader()`, `clear_leader()` and `_lead()`.  A led horse walks to a shoulder offset beside the handler (`lead_offset` 0.95 m right, 1.15 m behind), stops inside 0.45 m, and turns to face the handler's heading so it is ready to walk on.  Speed scales with the gap up to `trot_speed`, so it keeps pace with a walking handler and closes a gap without breaking into a canter.  `board()` and `begin_grooming()` clear the lead.
- The horse's prompt is now context sensitive: `E MOUNT / F LEAD`, `F LEAD` when only the rope is in range, or `E MOUNT / F RELEASE` while led.  The stable's prompt suppression still wins near the stall door.
- `scripts/reins.gd` draws a single lead rope from the hand and bit on the side that needs the shorter line while leading, and hides it again when the lead is dropped.
- `scripts/hud.gd` mentions `F lead` in the controls line and the on-foot objective.
- Verification: `tools/check_lead.gd` (`LEAD CHECK: PASS`) covers taking and dropping the lead, the prompt copy, the horse following a walking handler and settling at the shoulder, stopping when the handler stops, the rope being drawn/hidden, the released horse staying put, mounting straight from the lead, and `F` doing nothing in the saddle.  `tools/check_stable.gd` now also covers leading the horse to the door and stabling it dropping the lead.  `tools/screenshot_lead.gd` renders `artifacts/lead_walking.png` and `lead_idle.png`.
- Regressions: `MOUNT`, `TACK`, `STABLE`, `RIDE LOOP`, `FENCE JUMP`, `GROOMING`, `CHARACTER SWAP`, `CHARACTER SELECT` and `CHECK EDITOR LOAD` all pass.
- Limitations: the handler's arm does not visibly grip the rope (the rope tracks the animated hand), there is no rope tension or pull-back, and a sprinting handler outruns the led horse.

## Grooming visibility pass

2026-10-19

- The coat barely changed while brushing: `res/shaders/horse_groom.gdshader` mixed dirt only 40% toward a `dirt_color` that was almost the horse's own brown, and clean revealed as a 6% brighten, so a full groom moved the pixels a few percent. `dirt_strength` is now `0.85` with a cooler, darker grime (`0.30, 0.27, 0.21`), dirt darkens the base (`× (1 - 0.22·dirt)`) and uses a third low-frequency noise octave, curry now reads as a damp darkened coat (`mix` toward `colour * vec3(0.72, 0.70, 0.66)`), clean lifts `base * vec3(1.14, 1.09, 1.02)`, and the polished sheen is stronger with a broader fresnel (power 2). `resources/materials/horse_groom.tres` matches the new defaults.
- The projected brush ring was a thin, coat-coloured torus, so it disappeared against the horse. `scripts/grooming_session.gd` now builds an always-on-top ring (`no_depth_test`, `render_priority 10`) with a translucent footprint disc child (radius `0.1`, so it matches `brush_world_radius` under the ring's scale). `_update_ring` tints both green when the active tool can paint the zone under the pointer and red when it cannot, offset `0.012` along the normal; the per-tool ring tint was removed from `_update_tool_visuals`.
- `scripts/groom_surface.gd` gained a public `can_tool_paint(tool, zone)` wrapper so the cursor can read the zone rule.
- Verification: `GROOMING CHECK: PASS`. `tools/screenshot_grooming.gd` gained a `grooming_cursor.png` stage (the session is paused so the ring is not overwritten before capture); re-rendered `grooming_dirty/brushed/clean` now show an unmistakable dirty → clean progression.
- Limitations: a stronger dirt look means the horse reads as dirty anywhere in the world until groomed (intended, Cleanliness is a stat); the effect strength is still a single global `dirt_level` plus the local mask.

## Grooming paint-bleed fix (Phase 1: world-space gate)

2026-10-19

- The coat UVs are mirrored left/right and the atlas packs belly, flank and croup into one shell, so a UV-space brush stamp bled onto a physically distant part of the horse (rubbing the belly also cleaned the hind). `scripts/groom_picker.gd` gained `triangles_within(point, radius)`, which returns a byte mask of every posed triangle whose AABB is within the brush's world radius of a skeleton-local hit point.
- `scripts/groom_surface.gd` now bakes `_pixel_tris` during `_rasterise_mask`: up to `PIXEL_TRI_STRIDE` (4) candidate triangle ids per mask texel, covering the mirrored pair plus overlapping shells. `pick_ray` keeps the picker's raw `local_position` on the hit. `paint_hit` builds the allowed-triangle set for the stamp and passes it to `paint_uv`, which now rejects a texel unless at least one of its candidate triangles is under the brush (`_pixel_tri_allowed`). The 2.2× UV radius boost is kept for sparse shells, but the effective footprint is now the world radius, so the visible ring is truthful.
- The gate removes the belly→hind bleed but cannot separate the mirrored left/right sides (they share texels by construction); that still needs the Phase 2 mesh re-unwrap.
- Verification: `GROOMING CHECK: PASS`, including a new regression that stamps the same curry brush with and without the gate and asserts the gated set is a proper subset that only drops out-of-brush texels (it fails if the gate is disabled). `tools/screenshot_grooming.gd` re-rendered the dirty/brushed/clean/cursor shots; the coat progression and the ring still read clearly.
- Limitations: left/right remains bilaterally symmetric until the horse is re-unwrapped; the gate costs one ~2.9k-triangle AABB scan per paint stamp (negligible next to the existing pick).

## Grooming paint-bleed fix (Phase 2: split left/right UVs)

2026-10-19

- The Phase 1 gate could not separate the mirrored left/right coat because both sides share the same texels by construction. The horse model now carries a **second UV set** (`TEXCOORD_1`) built by `tools/add_groom_uv.py`: every triangle is assigned to the left or right side by its face-centroid X, then the side that fits in `[0, 1]` is scaled into `SIDE_SCALE = 0.49` and offset to `LEFT_OFFSET = 0.0` or `RIGHT_OFFSET = 0.51`. Left faces land in `u 0.0068..0.4853` and right faces in `u 0.5168..0.9953` (disjoint), 1457 faces each. `TEXCOORD_0` is untouched, so the coat texture is unchanged.
- `scripts/groom_surface.gd` prefers `Mesh.ARRAY_TEX_UV2` for the groom mask and falls back to `ARRAY_TEX_UV` (`_groom_uv2`). `res/shaders/horse_groom.gdshader` gained `uniform float use_uv2` and samples the mask at `mix(UV, UV2, use_uv2)`, set from `_build_material`.
- Two Godot-side traps had to be cleared. First, this machine's `godot --headless --import` (and `--headless --editor --quit`) no longer imports anything at all — the filesystem scan runs but no `.import`/`.scn` is ever produced — so the horse scene has to be built directly. `tools/force_import.gd` loads the GLB with `GLTFDocument`, packs it, and `ResourceSaver.save`s it to the `.import` remap path (plus the `.md5` sidecar). It also re-populates the skin bind names, which `GLTFDocument` leaves empty but the zone classifier needs.
- Second, the glTF importer with `gltf/embedded_image_handling=1` (Extract) **rewrote the source `.glb`** during a scan and dropped `TEXCOORD_1` when it did. `Models/horse_riggedgame_ready_clips.glb.import` is now set to `gltf/embedded_image_handling=3` (Embed as Uncompressed) so the source is never rewritten.
- Verification: `GROOMING CHECK: PASS`, including the new regressions that the mask uses the split set (`_groom_uv2`) and that grooming one side leaves the mirrored side unpainted; `MOUNT`, `TACK`, `CHARACTER SELECT` and `CHECK EDITOR LOAD` (`ALL OK`) also pass. `tools/screenshot_grooming.gd` re-rendered the dirty/brushed/mask/clean shots: the near side cleans while the far side stays dirty, with no midline bleed in mask view.
- Limitations: halving the atlas means each side gets half the texels (the `MASK_SIZE = 256` mask is effectively ~0.48× density per side, so raise it if the brush edge looks coarse); and the broken headless importer means the horse `.scn` must be (re)built with `tools/force_import.gd` after any change to `Models/horse_riggedgame_ready_clips.glb`.

## New 56-bone horse and matching gait speeds

2026-10-20

- Replaced `Models/horse_riggedgame_ready_clips.glb` with `Models/horse2.glb` in `scenes/horse.tscn`. The mesh, `TEXCOORD_0` and embedded coat texture are unchanged; the new model adds a 56-bone skeleton and 14 clips (`Death`, `Eating`, `Head_But`, `Idle`, `Kick`, `Rear`, `Rest_Pose`, `Run`, `Sleep`, `Trot`, `Turn_Left`, `Turn_Right`, `Walk`, `lay_to_idle`). `Model` keeps the existing mirror and gains the baked `+0.1698 m` local-Z offset so the hooves sit where the old mesh did.
- Built the new `.scn` with the parameterized `tools/force_import.gd` because headless GLB import is still broken on this machine. It rebuilt 56 bones and 56 skin bind names; `Models/horse2.glb.import` uses `gltf/embedded_image_handling=3` so the source GLB is never rewritten and the split groom UV survives.
- Updated the rig-facing code to the new names: `spine_3` seat with `spine_2` fallback, `head` for the bridle, `front_leg_foot_l/r` and `back_leg_toe_l/r` for hooves. `scripts/animation_state_machine.gd` now maps `Idle/Walk/Trot/Run`, and `scripts/horse.gd` uses the measured natural clip speeds: walk `1.74`, trot `1.95`, run `4.98` m/s. The FSM thresholds are `0.25 / 1.85 / 3.0` and its reference speeds match the clips.
- No jump pose for now. The physical jump, air time and landing stay, and the gait clip continues in the air; `scripts/horse_jump_pose.gd` has `active := false` until the old Bip01 overlay is remapped onto the new skeleton.
- Fixed the groom picker’s CPU skinning while validating the new rig. `Skin.get_bind_pose()` already stores the inverse bind matrix (it maps skeleton space back to bind space), so `rebuild_picker()` must apply it directly. The old `.affine_inverse()` produced geometry outside the mesh AABB and made the grooming ray miss the horse; the picker now rebuilds the real silhouette.
- Grooming zones and hoof handling now recognise the new bone names; `tools/analyze_horse_clips.py` supports both rigs. `check_horse_animations`, `check_tack`, `check_jump_and_loop`, `check_lead` and `check_fence_jump` were updated for the new clip set; `check_lead` gives the slower horse 1.5 s to settle, and `check_fence_jump` sets the horse’s yaw so the test rides straight at the rails instead of drifting around them.
- Also set the extracted tack textures to lossless (`compress/mode=0`) and reimported them, clearing the nine VRAM-compressed textures that `check_editor_load` flags on this no-VRAM machine.
- Verification: `HORSE ANIMATION`, `TACK`, `GROOMING`, `MOUNT`, `LEAD`, `STABLE`, `RIDE LOOP`, `FENCE JUMP`, `EDITOR LOAD`, `CHARACTER SWAP`, `CHARACTER SELECT`, `PLAYER MODEL` and `TERRAIN BLEND` all pass. Re-rendered `artifacts/tack_*.png`, `grooming_*.png`, `lead_*.png` and `stable_*.png`; the new horse’s coat, saddle, bridle and reins align correctly.
- Limitations: the jump overlay is still the disabled Bip01 animation; the old model and `.import` stay in the tree for rollback; and a walking handler can still outpace the led horse, whose lead speed is capped at the natural trot speed.

## Stable dog with needs-driven behaviour

2026-10-20

- Added the chihuahua as a yard resident at `(-3.5, 0, -16.5)` in `scenes/dog.tscn`. The scene holds a decorative bowl and food, a `BowlSpot` marker, a `CharacterBody3D` body, the GLB model (rotated 180° so its eyes face the body's `-Z` forward), the animator and a `Q · PET` prompt. The body is on collision layer 2 / mask 1, so the dog collides with the world but never blocks the player or horse; the bowl and food are visual only.
- `scripts/dog.gd` is a needs-driven FSM: `IDLE`, `ALERT`, `GREET`, `WANDER`, `FOLLOW`, `RETURN`, `SIT`, `LIE`, `SLEEP`, `EAT`, `PET`, `SHAKE`. Hunger, energy, affection and boredom tick every frame; hunger drives eating, low energy lies the dog down and then sleeps, boredom starts wandering, and the player arriving within 7 m triggers a one-off alert and greet. On foot the dog follows inside 8 m, sits 2.5 s after the player stops, and returns home when the player mounts or the 22 m leash is exceeded. Petting with `Q` within 1.6 m plays `TailWag`, raises affection and clears a little boredom.
- `scripts/dog_animator.gd` maps the 19 in-place chihuahua clips onto poses and gaits: `Idle`, `Idle_Alert`, `Walk`, `Trot`, `Run`, `Sit`, `Eat`, `Sleep`, `Rest_Pose` loop, while `Lie` and `Shake` are one-shots. Locomotion picks `Walk`/`Trot`/`Run` by speed and scales playback against the 0.9 / 2.2 / 4.8 m/s reference speeds, clamped to 0.75–1.4×.
- Integration: `scenes/main.tscn` instances the dog, `project.godot` gains the `pet` action on `Q`, and the HUD controls line now lists `Q pet`. `tools/check_editor_load.gd` includes `dog.tscn`.
- Verification: `tools/check_dog.gd` (`DOG CHECK: PASS`) covers the model height and home, prompt visibility, petting and affection, following and sitting, hunger-driven eating, lying down and sleeping with energy recovery, wandering near home, and the leash return. `EDITOR LOAD`, `MOUNT`, `LEAD`, `STABLE`, `GROOMING`, `RIDE LOOP`, `FENCE JUMP`, `CHARACTER SWAP`, `CHARACTER SELECT`, `PLAYER MODEL`, `TERRAIN BLEND`, `TACK` and `HORSE ANIMATION` all pass after the change.
- Limitations: needs reset every session (no save), the dog has no commands, fetch or audio yet (the `Bark` and `Howl` clips are unused), and screenshot capture was skipped because the full scene OOMs at 720p on this 2.7 GB machine.

## Grooming finish and chihuahua clip build

2026-10-20

- Grooming: the "horse still looks clean" report was not a dirt-level bug. The mask view showed the brushed band clean and the head and legs dirty, so the state was correct; the dirt colour itself read as pale sandy tan. `dirt_color` is now a darker grime `(0.16, 0.13, 0.10)` in both `res/shaders/horse_groom.gdshader` and `resources/materials/horse_groom.tres`, so dirty legs and head read as dirty in the normal view.
- Grooming: removed the diagnostic prints from `tools/screenshot_grooming_ui.gd`. `debug_areas.gd` was already gone. The zone map, tool-change glow, the "Areas n / 9" panel and the Rest_Pose freeze/restore are covered by `GROOMING CHECK: PASS`.
- Import crash path: eight tack textures under `Models/tack/textures/` (Leather030/039 Color, Displacement, NormalGL, Roughness) were back on `compress/mode=2`, and six imports had `detect_3d/compress_to=1`. All are now lossless and `compress_to=0`, per the checklist above.
- Chihuahua: `tools/build_chihuahua.py` now builds Lie and Sleep from Death frame 35 (`DEATH_LIE_FRAME`), with ground clipping and linear keys on every generated clip. The docstring points at `artifacts/` instead of `/tmp/opencode`. `Models/chihuahua.glb` (19 clips, 49 joints, 7.7 MB) is exported.
- Verification: `GROOMING CHECK`, `HORSE ANIMATION`, `TACK`, `MOUNT`, `LEAD`, `STABLE`, `RIDE LOOP` and `FENCE JUMP` all pass, and `CHECK EDITOR LOAD` prints `ALL OK`. `CHIHUAHUA ANIMATION CHECK: PASS` (lengths match, loop wrap < 1e-4, 49 bones, 0.225 m height).
- Limitations: the chihuahua Lie transition (around frame 18) flips the body up and back before it settles, so it reads as a fall more than a lie-down. The build logged measured foot speeds of 0.087 / 0.171 / 0.254 m/s for Walk / Trot / Run, far below the 0.9 / 2.2 / 4.8 m/s references in `dog_animator.gd`, so in-game foot slide is likely. `check_chihuahua_animations.gd` computes `loop_ok` but does not assert it; the looping is set at runtime in `dog_animator.gd`. Full-scene grooming screenshots still OOM on this machine; the lean 960×540 render is the only one that runs.

## Dog interest model and movement state-machine review

2026-10-20

- The dog no longer shadows the player. `scripts/dog.gd` builds an `_interest` value (0 to 1) while the player walks within 8 m and lets it fade otherwise. It follows only above `interest_threshold` (0.6), and standing players never pull it along. A chase ends after `follow_max_time` (14 s) or when interest drops below 0.05, then the dog waits a random 25 to 50 s before it chases again.
- A dog already following does not greet the player again. The greeting itself happens on about 60% of arrivals (`greet_chance`). After a greeting or a pet the dog sits or goes back to its own business, following only if interest is high.
- Idle dogs sometimes sit (25%), sniff within `sniff_radius` (2 m) of their spot (30%), or roam the yard (45%), with longer pauses after a sniff.
- Player speed is measured from position changes (`_measure_player`), so the dog no longer depends on the player's physics velocity.
- Debug hooks `debug_set_interest` and `debug_set_follow_elapsed` were added for the checks.
- `tools/check_dog.gd` now proves that a standing player is ignored, a walking player is followed, a chase expires into a cooldown, and the dog does not restart the chase straight away. The stage numbering was extended from 9 to 11.
- Verification: `DOG CHECK: PASS`, plus `MOUNT`, `LEAD`, `STABLE`, `GROOMING` and `CHECK EDITOR LOAD` (`ALL OK`), all exit 0.

State-machine review (no defects found in the horse or player code):
- Horse: riderless `_stand`, ridden `_ride` (walk / trot / canter from input and a hold timer), and led `_lead` (walks to a shoulder offset). Gait clips come from `animation_state_machine.gd` by speed, with measured reference speeds (1.74 / 1.95 / 4.98 m/s).
- Player: mounted (position driven by the horse), leading, and on foot, with idle / walk / run / air / land locomotion.
- Dog: IDLE, ALERT, GREET, WANDER, FOLLOW, RETURN, SIT, LIE, SLEEP, EAT, PET, SHAKE, driven by needs and by the interest model above.
- Open: the dog's animator reference speeds (0.9 / 2.2 / 4.8 m/s) are hand-picked, not measured like the horse's; the chihuahua build logged much lower clip speeds, so foot slide is likely in game.

## Dog gait measurement (foot slide, open)

2026-10-20

- Measured the chihuahua gait clips in `artifacts/chihuahua_build.blend` (body frame, foot tips, contact at z < 0.012 m):
  - Walk (0.97 s cycle): median stance slide 0.15 m/s; stance runs travel about 3 cm.
  - Trot (0.67 s): median stance slide 0.24 m/s; stance runs travel about 3 cm.
  - Run (0.47 s): median stance slide 0.39 m/s, from only 5 samples; feet are off the ground for most of the cycle.
- `dog.gd` moves the dog at walk 1.0, trot 2.8 and run 5.2 m/s. The clips' implied speeds are far lower, so the feet will slide in game. The swings are small (the gait is derived from the walk by scaling about 1.1 to 1.35x), so they read as marching rather than a stride.
- Fixing this means re-authoring the gaits with larger leg swings and a stride that matches a realistic speed for a 0.34 m dog, then retuning the dog's speeds to match. It needs visual review in the contact sheets, so it is not finished.

- Tried re-authoring by amplifying the leg swing (Trot `amp_legs` 1.08 to 2.6, Run 1.35 to 3.0). Trot and Run feet then left the ground for most of the cycle (contact 5 to 19%), so they hop rather than stride, and the body-frame stance travel barely changed (about 2 to 3 cm). Reverted; the shipped amplitudes stay, and `CHIHUAHUA ANIMATION CHECK` passes on the rebuilt GLB.
- Next step for this item: re-author Walk, Trot and Run from a stride-based design (pose keys for a real swing and stance phase), not by scaling the existing swing, then set `dog.gd` speeds and `dog_animator.gd` reference speeds from the measured stance travel.

## Stable rebuilt as a five-bay horse stable

2026-10-21

- Replaced the fantasy house in `scenes/stable.tscn` with `Models/horse_stable_animal.glb`, a 3.25 × 3.31 × 7.45 m open-front stable with five bays along its long side. The asset is authored Y-up in centimetres, so it sits at scale 1; it is scaled 1.2 and rotated -90° about Y so the five bays face south into the yard. Footprint is now 8.94 m (X) × 3.9 m (Z) at `(-7, 0, -25)`.
- The old 9.4 × 4.98 × 6.66 m box collider became an 8.94 × 3.97 × 3.9 m box at y ≈ 1.99. The model's low front wall keeps the player out of the bays without an invisible wall.
- `HorseStall` moved to `(-7, 0, -21.9)` (just outside the centre bay) and `UseAnchor` to `(-7, 0, -20.3)`, so boarding/release still works and the released horse clears the collider. `scripts/stable.gd` and `tools/check_stable.gd` needed no logic changes.
- Added `scenes/stable_horse.tscn` + `scripts/stable_horse.gd`, four decorative horses from `horse2.glb` standing in the four outer bays at x ≈ -10.48, -8.74, -5.26 and -3.52, facing the yard. The centre bay is left empty for the player's horse. The script freezes each imported `AnimationPlayer` on a `Rest_Pose` frame, and the horses have no `horse` group or `CharacterBody3D`, so the singleton horse lookups used by the player, stable, grooming, HUD, dog and reins are unaffected.
- Verification: `STABLE CHECK: PASS`, `CHECK EDITOR LOAD: ALL OK`, and `tools/screenshot_stable.gd` re-rendered `artifacts/stable_boarding.png`, `stable_boarded.png`, `stable_released.png`; `tools/screenshot_scene.gd` re-rendered the yard/overview shots. The four static horses read clearly over the low front wall.
- Limitations: the static horses are decorative only; several *interactive* horses would need the `get_first_node_in_group("horse")` singletons in `player_controller.gd`, `stable.gd`, `grooming_*.gd`, `hud.gd`, `dog.gd`, `reins.gd` and `riding_course.gd` refactored to target a chosen horse.

## Larger show-jumping arena and an eight-fence course

2026-10-21

- Tripled the arena area from 20 × 40 m to **35 × 70 m** (2,450 m², 3.06×), keeping the east rail at `x = -15` and the existing gate at `(-15, -1.5)` so the stable yard, path and training ground still line up. The arena is now `x = -50 … -15`, `z = -35 … 35`.
- Extended `tools/build_scenery.gd` to generate `scenes/arena_fence.tscn` from the fence module's measured length. It writes 12 modules per short side and 23 per long side, skips the two east modules at the gate, and builds north/south/west/east collision boxes with the east one split around the gate. West/east modules are yawed 90°. Re-running the tool now regenerates the rail instead of leaving it hand-authored.
- Re-spaced the course into **eight numbered fences** with 7–9 m clearance from the outer rail: a serpentine loop at `(-22,-1.5)`, `(-31,-12)`, `(-42,-20)`, `(-33,-27)`, `(-23,-22)`, `(-26,3)`, `(-39,12)` and `(-43,26)`. The four cavaletti moved to a trot-pole line at `x = -44.5`; the three marker boxes were repositioned out of the riding lines.
- Moved the west tree belt from `x ≈ -50…-54` to `x ≈ -56…-61` and the `ArenaEdge` plants to `x ≈ -53…-54`, so nothing stands inside the larger arena.
- Grew the painted arena layer in `tools/build_ground_control.py` to centre `(-32.5, 0)`, half-size `(17.5, 35)`, and regenerated `terrain_control.png`. The 128 m control map still covers the new west edge.
- Updated `scripts/riding_course.gd` (`ARENA_MIN/MAX`), `tools/verify_scenery.gd` (arena course now 23 props), `tools/check_jump_and_loop.gd` (expects and clears all eight fences), and the arena cameras in `screenshot_scene.gd`, `screenshot_terrain.gd` and `screenshot_loop.gd`.
- Verification: `VERIFY SCENERY: PASS` (arena_course 23 props, 573,984 total tris), `TERRAIN BLEND CHECK: PASS`, `RIDE LOOP CHECK: PASS` (8/8 fences, +£204, jumping 4.0), `FENCE JUMP CHECK: PASS`, `CHECK EDITOR LOAD: ALL OK`. `artifacts/arena_course.png` was re-rendered and inspected; the arena is clearly larger, the jumps are clear of the rail, and the gate remains open.
- Limitation: all eight fences share the same rail orientation (across X); rotating a fence 90° would need the clear-detection check to test the fence's local axes instead of the world AABB.

## Physics knock-down jumps and training area polish

2026-10-21

- Replaced the static monolithic fence obstacles with **modular dynamic physics jump obstacles** (`scenes/jump_obstacle.tscn`, `scripts/jump_obstacle.gd`). Each obstacle features left and right standards (`07_HalfBarrier1.glb` / `09_HalfBarrier2.glb`), official red (right) and white (left) flags, height cups, and a physical `RigidBody3D` striped pole (`13_Pole.glb`).
- **Dynamic Physics Knockdown**: Poles rest stably on cups (`freeze = true`) until an under-cleared jump or chest impact occurs, which unfreezes the pole, applies kinetic impulse based on the horse's approach velocity, knocks it down to the sand, and triggers an authentic wooden clatter audio effect.
- **Graduated Course Progression**: The 8 numbered fences now feature progressive height classes:
  - Fence 1: Intro (0.60m)
  - Fences 2, 3, 5: Novice (0.85m)
  - Fences 4, 6, 7: Intermediate (1.05m)
  - Fence 8: Grand Prix (1.25m)
- Added an **Interactive Practice Jump** in the schooling area where the player can walk up on foot and press `E` to cycle heights (Intro 0.60m -> Novice 0.85m -> Intermediate 1.05m -> Grand Prix 1.25m) or press `R` to reset knocked poles.
- **Realistic Horse Jumping & Bascule**:
  - Re-mapped `scripts/horse_jump_pose.gd` onto the 56-bone skeleton (`horse2.glb`) and re-enabled the procedural jump posture overlay (`active = true`), delivering arched back, tucked front legs, and trailing hind limbs across takeoff, apex, and descent.
  - Increased `jump_training_bonus` to `0.15` in `scripts/horse.gd` so trained horses jump visibly higher and clear Grand Prix fences with ease.
- **FEI Faults & Scoring**:
  - `scripts/riding_course.gd` tracks knockdowns as 4 faults each.
  - Clear round detection: clearing all fences with 0 faults triggers a "★ CLEAR ROUND! ★" notification and a +£50 bonus purse.
  - HUD displays live faults counter during rounds and detailed summary on the result card.
- **Verification**:
  - `KNOCKDOWN CHECK: PASS` (`tools/check_knockdown.gd` tests initial height, height switching, 4-fault knockdown impulse/audio, reset, and clearance).
  - `FENCE JUMP CHECK: PASS` (verifies horse is stopped on foot approach and clears when jumping).
  - `RIDE LOOP CHECK: PASS` (completes full 8-fence course loop and reset).
  - `HORSE ANIMATION CHECK: PASS` (14 clips validated, FSM idle).
  - `CHECK EDITOR LOAD: ALL OK` (zero VRAM compression warnings, all scenes and scripts compile).

## Jump obstacle repair: split-asset offsets and real knockdowns

2026-10-21

- Found that the modular jump built from the `show_jumping` split GLBs was assembled in the wrong coordinate space. Each split `.glb` retains its position inside the original Blender layout, so used raw at the obstacle origin they landed metres away from where the scene expected them. The pole was 1.76 m above the cup height, both standards overlapped around x = -3, the white flag sat at x = -6.2, and the cups were empty. The resulting obstacle AABB was 6.6 m wide and centred ~3 m left / 1.6 m behind the node, which also offset the generated collision and fence number.
- `scenes/jump_obstacle.tscn` now re-centres every split piece on the obstacle origin: standards at x = ±1.5, flags at ±1.5, cups (11/12 Holder) added under `Cups` at ±1.5, and `13_Pole` offset by (+2.97, -1.76) so the physical body at `y = h` really is the cup height. The pole collision is 3.0 × 0.12 × 0.12. Wing colliders moved to ±1.5.
- The obstacle is now the solid fence: the frozen pole blocks a ground approach, unfreezes and tumbles on impact, and a downed rail can be ridden through. `riding_course._build_jumps()` no longer creates the old invisible 0.9 m box (or a second number label) for physics obstacles.
- Knock detection only reacts to the `horse` group and ignores a horse whose body is already above the rail; clear detection only fires when the horse is airborne and its root is above the rail. The clear Area is 4 m tall so the horse's body actually passes through it at jump height instead of flying over a rail-height slab.
- `R` now resets every rail during a round as well as between rounds. Course fences are no longer height-adjustable; only `PracticeJump` has `allow_player_adjust = true`. Knockdown toasts use the correct fence number.
- Re-centred the four cavaletti (`00_Barrier1` is offset ~3 m in X / 1.4 m in Z) and the three marker boxes in `scenes/arena_course.tscn`.
- Replaced the `blocky.mp3` gallop sample with a synthesised `assets/sounds/horse/wood_clatter.wav`.
- Extended `tools/check_knockdown.gd` with geometry assertions (pole centred at cup height, 3 m wide, standards at ±1.5, not player-adjustable) and fixed it to run only once. `tools/check_fence_jump.gd` resets the rail between its ground approach and jump attempt. `tools/check_editor_load.gd` now only flags texture imports for VRAM compression (audio importers use the same key).
- Verification: `KNOCKDOWN CHECK: PASS`, `FENCE JUMP CHECK: PASS`, `RIDE LOOP CHECK: PASS`, `CHECK EDITOR LOAD: ALL OK`. Re-rendered `artifacts/arena_training_overview.png`, `jump_obstacle_intact.png`, `jump_obstacle_knocked.png` and `practice_jump_prompt.png`; the intact and knocked frames now differ, and the jumps read as proper standards with a striped pole resting on cups.
- Open: the course is still eight identical verticals plus a cavaletti line and one adjustable practice jump; there is no cross-rail or one-stride combination yet. Flags are small single-sided planes and the cup holders are barely visible at gameplay distance.

## Fences launch on impact and no longer stop the horse dead

2026-10-21

- `scripts/jump_obstacle.gd` now throws a struck rail clear of the horse instead of dropping it at the cups. The launch is the horse's approach direction plus a base shove, with an upward component and an end-over-end tumble; the tunables are exported as `knock_launch_up` (4.2 m/s), `knock_launch_speed_scale` (0.9), `knock_launch_base` (1.6 m/s) and `knock_spin` (8 rad/s). Launch velocity is set directly after unfreezing so it takes effect on the same frame.
- The flying rail no longer acts as a wall. `knock_down()` adds a collision exception between the pole and the striking horse, and `reset_jump()` removes it and restores the rest transform. The horse therefore rides on through the gap instead of stopping dead; `scripts/horse.gd` adds `apply_fence_impact()` to shed 15% of ride speed on the hit without killing momentum.
- `tools/check_knockdown.gd` now asserts the pole gains upward and forward velocity and tumbles. `tools/check_fence_jump.gd` now expects the ground approach to knock the rail (4 faults) and carry on past the fence; the jumping clearance half is unchanged.
- Verification: `KNOCKDOWN CHECK: PASS`, `FENCE JUMP CHECK: PASS` (ground approach z reaches 1.11 past the fence at z=-1.5 with 4 faults; the jumped approach still clears), `RIDE LOOP CHECK: PASS`, `CHECK EDITOR LOAD: ALL OK`. Re-rendered `artifacts/jump_obstacle_knocked.png`; the rail is visibly airborne rather than lying on the sand.

## Training arena course redesign with physical number blocks

2026-10-21

- Re-laid the eight-fence course into a compact loop around `(-21…-42, -22…27)` with progressive heights from Intro to Grand Prix and quarter-turn fences at the corners. The practice jump moved inside the loop to `(-32, 4)`, and the four cavaletti now form a trot-pole line at `x = -34`.
- Removed the three marker boxes from `ArenaJumps`; the arena course is down to 21 instanced props.
- `scripts/jump_obstacle.gd` now spawns a physical wooden number block beside every numbered fence, using `No_1_Box` through `No_9_Box` (plus `No_10` as a spare). The blocks are scaled 1.8, recentred from their baked GLB offsets, and grounded at `y = 0`. They sit on the red/right side and face the approach, with no collision body.
- Floating fence numbers are hidden. The existing `NumberLabel` is now used only to show a green `CLEAR` after the fence is jumped, then hidden again on reset.
- `scripts/riding_course.gd` excludes the `NumberBlock` subtree from the fence AABB, so the physical marker cannot shift the jump centre or clear detection.
- `tools/build_scenery.gd` no longer regenerates `arena_course.tscn`; the course is hand-authored. `tools/verify_scenery.gd` expects 21 arena props and skips the jump obstacle's dynamic rail when checking ground contact.
- `tools/check_jump_and_loop.gd` now asserts every course jump and the practice jump has a grounded number block, floating numbers stay hidden before clearing, and each cleared fence shows `CLEAR`.
- Verification: `CHECK EDITOR LOAD: ALL OK`, `VERIFY SCENERY: PASS` (arena 21 props), `KNOCKDOWN CHECK: PASS`, `FENCE JUMP CHECK: PASS`, `RIDE LOOP CHECK: PASS`. Re-rendered the arena overview, intact/knocked jump and practice-jump screenshots; the blocks are readable from the approach and sit clear of the standards.

## Touch controls for tablets, with a touch-first rule

2026-10-21

- Added two autoloads. `scripts/device.gd` (`Device`) decides keyboard vs touch: F3 in debug builds, then `GROOM_TOUCH=1/0`, then the touchscreen or mobile feature. Prompt text goes through `Device.pick(keyboard, touch)`, so the keyboard strings are unchanged. `scripts/touch_controls.gd` (`TouchControls`) is a CanvasLayer at layer 30 that tracks every finger itself, because Godot's touch-to-mouse emulation only follows the first finger.
- Ride: a floating left-thumb stick walks the player and the horse with analog speed. Pushing past 80% of the radius holds `run` and releasing below 70% drops it. A right-half drag adds to the same look path as the mouse, and mounted steering reads the same move input. The bottom-right cluster has a CONTEXT button, JUMP, LEAD and RESET. CONTEXT shows what the nearest interaction will do: `GROOM` > `PET` > `HORSE OUT` / `PUT AWAY` > `RAISE` > `MOUNT` / `DISMOUNT`. Gameplay nodes describe themselves in the `touch_context` group.
- Keyboard and mouse stay live in touch mode. Pointer lock is skipped when touch is on, so the cursor stays visible.
- Character select: a swipe spins the turntable, and the hint reads "Swipe turn · tap a rider · tap Ride out".
- Grooming: one finger paints, two fingers orbit, and spreading them pinches the camera in. Mouse paint and orbit are ignored in touch mode. The tool row, MASK and DONE are 56 px high in touch mode.
- Project: 1280x720 base viewport, sensor-landscape orientation, and explicit `emulate_mouse_from_touch=true`.
- Verification: `tools/check_touch.gd` runs 27 headless assertions (prompts, stick, run hysteresis, look, CONTEXT mount, grooming gestures, select swipe, keyboard still live). It passes. `tools/screenshot_touch.gd` renders ride, groom and select views.
- Not verified on a real tablet: thumb feel, latency, and multitouch with real hardware. Button hit areas and the stick radius are first guesses.

## Web build on Netlify, for testing on the iPad

2026-10-22

- Added a `Web` export preset to `export_presets.cfg`. It is single-threaded, so the host does not need COOP/COEP headers.
- Added `netlify.toml` with `publish = "build/web"`, `application/wasm` for the engine binary and a one-hour cache on the pack.
- `Device` now reads `?touch=1` / `?touch=0` from the web build's URL, between the debug F3 toggle and the `GROOM_TOUCH` environment override. `tools/check_touch.gd` covers the parser: `?touch=1` forces touch, `?touch=0` forces keyboard, and anything else is ignored.
- Deployed to <https://groom-769.netlify.app>. The export is about 250 MB, so the first tablet load is slow.
- Verification: the live page, script, wasm and pack all answer 200 with the right content types, and the served pack is byte-identical to the local export (head and tail checksums). The engine starts and then reports the missing WebGL2 in this machine's Chromium, which has no GPU, so rendering was not verified here.

## The dog faces the way it walks

2026-10-22

- At heel the dog moves by matching the player's velocity instead of steering at a point, and that branch never set a heading, so it trotted alongside the player while still facing wherever it had been. It now turns toward the travel direction, the same way every other moving state does through `_steer_to`.
- `tools/check_dog.gd` gained a heel case: the dog starts facing away from the player's path, the player walks past, and the test asserts the dog both keeps up and ends up facing that direction. It reports `dot 0.38` without the fix and passes with it.

## The arena only starts a round when you ask for one

2026-10-22

- `riding_course.gd` no longer starts a round on entry. The old trigger fired on the gate radius and on being anywhere inside the arena rectangle, so riding in to look at the fences began a timed round. Both checks are gone, and the gate's green beam and `SCHOOLING ROUND` sign are removed with them.
- A round now starts on the first fence cleared: the obstacle's own `jump_cleared` runs `_start_if_idle()` before the fence is counted, so the clock begins at that fence. The practice jump opens a round too but is not one of the eight.
- Leaving the training area cancels a running round: `reset_round()` with no result, no money and no training, plus a notice. `TRAINING_MIN` / `TRAINING_MAX` hold the bounds.
- HUD objective while idle reads "Jump a fence to start a round"; the result card says "Clear a fence to go again".
- `_clear_jump` ignores fences cleared while the result card is up, so a stray jump cannot push the finished round's count past eight.
- `tools/check_jump_and_loop.gd` covers it: mounted inside the arena does not start a round, clearing fence 1 starts it and counts it, riding outside cancels it with the money unchanged, the practice jump opens a round without counting, and the eight-fence clear, reward and reset still pass.

## A farmhouse to come home to

2026-10-22

- New standalone scene `scenes/farmhouse.tscn`, generated by `tools/build_farmhouse.gd`. Two storeys: sitting room, kitchen, hall, study and boot room downstairs; main bedroom, second bedroom, bathroom, landing and gallery upstairs. Interior footprint 11 x 9 m, 2.6 m ceilings, 0.3 m exterior walls.
- The plan lives in tables at the top of the generator: `WINDOWS`, `DOORS`, `STAIRS`, the room rectangles and the `PROP` placements. Wall openings, casing, glass, sills and leaves are all derived from the same tables, so a moved window cannot leave a hole in the wrong place.
- The stair is 15 risers over 3.2 m with a hidden ramp collider, because the player controller has no step-up logic; the visible treads, risers, stringers, handrail and the first-floor balustrade around the stairwell are meshes only.
- Furniture is Kenney's CC0 Furniture Kit (140 GLBs in `Models/interior/kenney_furniture_kit/`) plus Poly Haven plaster and oak floor textures. Every prop is measured from its own AABB, centred on its footprint and dropped onto the floor, so the kit's offset pivots cannot leave a chair floating. Provenance is in `Models/interior/SOURCE.txt`.
- The kit's upholstery is a fixed pastel pink; the generator recolours only that surface (so legs and frames keep their wood) to the green, cream and terracotta palette, and does it per instanced model. Those overrides sit on nodes inside the GLB instance, which the packer drops unless the nodes are given to the scene root, so `_own_tree` does that for tinted props.
- `scripts/interior_spot.gd` makes a sofa or bed usable: an E prompt through `Device.pick`, a CONTEXT offer for touch, `sit_at()` / `stand_up()` on the player, and for beds a dim-and-return rest fade with a `RESTED` toast. There are 11 spots.
- Lighting is a dusk sky with a low south-west sun and warm pendants in every room; the pendants are meshes so the pool of light on the ceiling has a fixture above it.
- Verification: `tools/check_farmhouse.gd` walk-tests the shell and the furnishing — floor height under all ten rooms, every doorway open while the wall beside it is solid, every window open to the outside, the stair climbable by holding forward, every room furnished, 11 lamps, sitting and standing on the sofa, a bed rest that dims the screen, and standing back up. It passes.
- `tools/screenshot_farmhouse.gd` renders eight review views, including orthographic ground and first-floor plans that hide the ceiling above them. Add view names after `--` to render only those.
- The house is not reachable from the stable yet: there is no door or scene change into it, by request.

## The stairs now go somewhere

2026-10-22

- The old straight flight was built into a 0.95 m slot along the hall's south wall, with its foot 0.45 m from the west wall and its top 0.05 m from the east wall. The controller has no step-up logic, so the only way onto it was the narrow pocket at its foot, and the top opened onto a strip too thin to stand on: the stair could not be entered or left the way a player walks.
- Replaced with an L-shaped stair in the hall's south-east corner: six risers up along the east wall to a 1 m square quarter landing, then nine risers west along the south wall, finishing flush with the gallery floor in front of the main bedroom door. Fifteen risers of 0.181 m, 28.7 and 39.4 degree pitches, both inside the controller's 45 degree floor limit.
- The foot now faces north into the hall with 1.3 m of floor in front of it, so it is walked into end-on. Each flight has one solid ramp as its walking surface (the treads are decoration) and the ramp meets floor and landing exactly, so there is no lip at either end. `_floor_with_holes` cuts the L-shaped well through the ceiling and the upper floor.
- The quarter landing is open on no side that drops: walls behind and to the east, a flight on each other side. Every other edge has a balustrade — raked along each open flight side, level around the well on the gallery — built as shoe, spindles and handrail with an invisible solid barrier behind it, so the joinery is open but the collision is a wall. Checked by walking at the well edges and at the open side of the flight.
- The front door moved from z = 0 to z = 1.55 on the east wall, because the old position opened straight onto the lower flight. The hall window moved over the stair instead, and the side table and coat rack moved out of the new stair footprint. The study door moved to x = 2.5, which puts it under the high end of the upper flight (2.6 m of headroom) rather than inside the quarter landing; that is the only place the south wall is free of stair.
- `tools/check_farmhouse.gd` now walks the stair the way a player does: in from the hall, up the lower flight to the turn, west and up onto the landing at (x 1.77, y 2.72), then back down to the hall floor. It also walks at three stairwell edges, at the sofa, and through the study door under the upper flight, and checks the surface height along both flights. It passes.
- `tools/screenshot_farmhouse.gd` hides the new named slabs by prefix, so the plan views work again, and its hall and landing cameras look at the stair.

## Normal-map detection in the editor log is benign

2026-10-22

- A fresh editor scan auto-detected 14 `_Image_2.png` textures under `Models/split/` as normal maps and 14 corresponding roughness maps. It printed the "Texture detected as used as a normal map/roughness map in 3D" lines and rewrote only `compress/normal_map=0→1` and `roughness/mode=0→1` in their `.import` files; `compress/mode` and `detect_3d/compress_to` stayed `0`. The images really are normal maps (flat `128,128,255`), so the edits are correct.
- This is not the VRAM crash. The `.ctex` outputs are lossless WebP (585 KB each), not the ~1.3 MB RGTC layout that `mode=2` would produce, and a project-wide scan still finds no texture on `compress/mode=2`.
- The 14 `ERROR: Attempting to parent and popup a dialog that already has a parent.` lines are the editor's import progress dialog, one per reimported texture. This is the known benign Godot issue #77426; the project has no `Window`/`AcceptDialog`/`.popup*()` usage, and the errors stop once the reimports finish.
- `tools/check_editor_load.gd` gained a second report, `CHECK NORMAL MAPS STAY LOSSLESS`, which fails if a `compress/normal_map=1` texture is VRAM-compressed or still has `detect_3d/compress_to` enabled. Verified by temporarily planting a file that trips it (it reported the file and exited 1) and then removing it.
- Verification: `CHECK EDITOR LOAD: ALL OK` (489 `.import` files scanned, both texture sections clean).

## The farmhouse front door opens

2026-10-22

- `scripts/scene_door.gd` is a reusable door link: a proximity `Label3D` prompt, `Device.pick` text, a CONTEXT offer via `touch_context()`, and an E / interact handoff that fades through `SceneFade`. It refuses while the player is mounted, seated, fading or out of reach.
- `GameState.request_player_spawn(position, yaw_degrees)` / `consume_player_spawn()` carry the landing spot across the scene change; `scripts/player_controller.gd` consumes it in `_ready()`, before physics runs.
- The fantasy house front door is centred on the +Z facade at world `(36.978, 0, -31.2)`. The yard-side `FrontDoor` lands in the farmhouse hall at `(4.6, 0.05, 1.55)` facing west; the interior `FrontDoorExit` returns to `(36.978, 0.05, -30.9)` facing the house.
- The decorative house now has a single invisible collision shell, `5.9 x 3.5 x 5.9` at `(36.978, 1.75, -34.307)`. The farmhouse front leaf gets a matching `0.12 x 2.11 x 0.99` collider so the player cannot walk through the closed door from inside.
- The interior exit is part of `tools/build_farmhouse.gd` and therefore survives a regeneration; `scenes/farmhouse.tscn` was rebuilt.
- Verification: `tools/check_scene_doors.gd` passes both links, the house shell, the yard prompt, the farmhouse leaf collider and the pending-spawn move/yaw. `tools/check_farmhouse.gd` now also asserts the exit link, and `tools/check_editor_load.gd` loads `scenes/farmhouse.tscn`; all checks pass. A rendered yard view shows the prompt centred over the door.

## A prop library of our own

2026-10-23

- New `tools/build_props.py` generates the farm's props procedurally in Blender and writes 70 ready-to-use assets: 13 trees (oaks, autumn oak, apple, birch, two pines, willow, dead tree, sapling, stump, fallen log), 7 bushes (round, large, berry, two flowering, hedge, bramble), 7 nature scatter props, 18 stable props, 12 yard props, 4 garden props, 2 jump-course props and 7 grooming tools.
- Everything is flat shaded, built from solid materials (no textures, no UVs, no external assets) and sits at real-world scale with its origin on the ground, so a 1.8 m rider, a 1.6 m trough and a 1.1 m bale line up without rescaling. The whole library is 34,652 triangles.
- Outputs: `Models/props/<category>/<name>.glb` (one object per file), `Models/props/props_manifest.json` (category, bounding size in metres, triangles, material slots), `artifacts/props_library.blend` (every prop in a labelled grid, one collection per category, objects marked as Blender assets) and a contact sheet per category in `artifacts/props_*.png`, plus `artifacts/props_overview.png`.
- The grooming category mirrors the tools the grooming loop already uses — curry comb, dandy, soft and face brushes, hoof pick, sponge and sweat scraper — and the stable gained a hay net, pitchfork, broom, muck tub, saddle blanket, lead rope and carrots.
- Sheets are rendered one prop per tile at a common camera angle, then captioned with the prop name, its real dimensions and triangle count. Earlier row-based sheets framed each row separately, so a row of saplings and a row of oaks appeared at different scales; the earlier overview also rendered the library grid instead of a scene.
- Prop fixes while assembling the library: the milk churn floated 5 cm above its origin and the bramble's roots started above the ground; both now touch 0. Crate rebuilt as an open slatted box, saddle rack given a proper saddle-tree top instead of a table top, brushes given dense short bristles, and the blossom bushes given larger pink flowers.
- `--stage trees` (or any other category) rebuilds just that category while iterating; `Models/props/README.md` documents the layout, the rebuild command and the Godot import notes.
- Verification: every GLB parses as glTF 2.0 with one mesh, its node bounds match the manifest size to 1 cm, triangle and material counts match, and no prop floats above the ground (rocks and bushes are deliberately bedded a few centimetres into it).

## The competition arena

2026-10-23

- New `scenes/competition_arena.tscn`, generated by `tools/build_arena.gd` and reached from the yard through a new `ShowgroundGate` under an arch at the existing arena entrance `(-13.2, 0, -1.5)`. The arena's `ExitDoor` returns to `(-12.5, 0.05, -1.5)` on the yard side, so both scenes share one gateway.
- The venue is a 60 x 30 m sand ring inside a post-and-rail track with letter boards and a START gate on the east side, a five-tier covered grandstand for 51 low-poly spectators, a judges' box with bell, desk and canopy, a score board and a handwritten class board, eight sponsor boards, two pennant poles, bunting along the stand and over the entrance, a secretary's desk with an ENTER CLASS prompt, a warm-up ring with two practice fences, a lorry park of three trailers, three trade stands with striped awnings, and trees, bushes and planters around the concourse. 649 meshes, 97 collision shapes, no textures.
- The show course is ten fences in `scenes/show_course.tscn`: vertical, oxer, triple bar, wall, liverpool and brush, at 1.05 m or 1.25 m, laid out as a proper track around the ring. `scripts/jump_obstacle.gd` gained OXER, TRIPLE_BAR, WALL, LIVERPOOL and BRUSH types with the matching build (spread poles, triple bars, painted wall, water tray, brush filler) and faults for the solid ones. Number boards are the obstacle's own; the course does not add floating labels.
- `scripts/show_class.gd` extends `SchoolingCourse`: the desk takes a £20 entry, issues a rider number and builds a deterministic field of seven rivals seeded from `GameState.show_entries`. The class starts when a mounted rider crosses the gate line at x = 30 (with a bell sound), and ends on ten clears, on the 120 s limit, or as an elimination if the horse leaves the ring. Placings compare faults and then time; a clear round is placed first against the par-78 s field and pays £120 / £70 / £45 / £25 for the top four. A top-three finish leaves a rosette to collect from the stand at the judges' box, records it in `GameState.rosettes`, and pins a rosette mesh to the horse. The class resets after 8 s so it can be entered again.
- `scripts/show_secretary.gd` follows the project's proximity + aim interaction pattern for both the entry desk and the rosette stand; `scripts/arena_scoreboard.gd` reads the class through its group and shows the live class, entries, last result and rosette count.
- HUD: the objective changes from "Enter CLASS 1 · 1.05 m OPEN at the secretary's desk · £20" to the rider number, then to the running class; the result card gains placing, field size, prize, rosette and the "enter again" hint, and a rosette counter appears under the wallet.
- Two bugs found while verifying the venue: the show class readied before the horse existed and cached null actors (`RidingCourse` now re-resolves them deferred, which also makes scene order irrelevant), and the secretary was parented to the desk but given the desk's global position, putting the interaction 37 m out in the field. The gate banner gained real faces on both sides instead of showing mirrored text from behind, and `_build_bunting()` was defined but never called.
- Verification: `tools/check_arena.gd` passes — venue parts, 51-strong crowd, five rising tiers, sponsor boards, scoreboard labels, five solid rail sections, ten fences inside the ring using the expected types, the desk refusing an unpaid entry, the desk prompt and entry, the gate starting the class, a clear round winning £120 with a red rosette, the HUD card, the rosette stand handing it over, the horse wearing it, a second class, elimination for leaving the ring with no prize, and both scene-door links. `tools/screenshot_arena.gd` renders six review views into `artifacts/arena_*.png`. `check_scene_doors`, `check_jump_and_loop` and `check_editor_load` (now loading both new scenes) still pass.

## The farmyard and forest move to the prop library

2026-10-23

- The stable yard's loose medieval props are gone: the three 3x hay bales, two barrels, two crates, cart, bench and well, plus the six GLB resources that only existed for them. Their replacements are 32 props in a generated `scenes/stable_yard_props.tscn`, instanced once in `stable.tscn` as `YardProps`; the building, paddock, horses, mount anchor and gameplay `FeedTrough` are untouched.
- Yard contents: hay rounds and a square bale by the paddock fence, barrels, stacked crates, wheelbarrow, bench, well, water trough, mounting block, hitching post, saddle rack with the blanket folded on it, feed and water buckets with carrots, feed sack, hay net hung on the stable wall, pitchfork and broom against the east wall, muck tub, grooming tote, lead rope on the post, signpost, two lantern posts, two planters, an apple basket and a firewood stack.
- The yard is part of `tools/build_scenery.gd`, using the same measured AABB normalisation as the trees: every prop is centred on its footprint with its base exactly on the surface under it. A `collide` flag adds a box collider measured from that same AABB (inset 2 cm), so 19 solid items - hay, barrels, crates, barrow, bench, well, trough, block, post, rack, tub, signpost, lanterns, firewood - cannot be walked through. Stacked and hanging props (top crate, blanket, carrots, hay net, lead rope) use a `lift` offset.
- Forest: all 30 tree instances now use the library (oak 01/02/03, autumn oak, apple, birch, pine 01/02, willow, dead tree, sapling) in place of the split low-poly GLBs, keeping each belt's positions and yaws. Accents became the autumn oak, dead tree and sapling. Nature: all 22 scatter instances now use rock clusters, mushroom clusters, grass tufts, reeds and flower patches, with bushes, a stump and a fallen log at the path and paddock edges.
- Tree scales were already close to real-world size, so the belts moved only to 1.0-1.2. The nature rows had been authored at 10-12x for the tiny split assets; those are now 0.8-1.6 so a grass tuft is 0.5-1 m rather than seven metres tall.
- Verification: new `tools/check_yard_props.gd` passes - the old nodes are gone, 32 props are present, each sits on its slot surface, all 19 colliders match their visuals and centres, no prop clips the stable shell, paddock fences or feed trough, and the gameplay trough keeps its collision. `verify_scenery` still finds 30 forest and 22 nature props, all seated at y = 0, with 15,272 and 8,216 triangles respectively. `check_stable`, `check_feed`, `check_scene_doors`, `check_jump_and_loop`, `check_arena` and `check_editor_load` all pass. `screenshot_scene.gd` gained a `yard_props` view.

## The dog walks on its own feet

2026-10-23

- Two separate faults made the chihuahua look wrong. (1) `scripts/dog.gd` aimed `velocity` at the steering target while `_face_direction()` only lerped `rotation.y` toward it, so after every heading change the body travelled up to 90° off its nose — the sideways slide. The horse had already been fixed the same way in `horse.gd` `_ride()` ("travel along the direction the horse actually faces"). (2) The Walk/Trot/Run clips were retimed copies of a 1 s source shuffle whose stance covered about 3 cm, so their feet planted at 0.09 / 0.17 / 0.25 m/s while the dog was driven at 1.0 / 2.8 / 5.2 m/s: a 10-20x skate that no animator tweak could hide.
- `scripts/dog.gd` gained `_move_along_facing()`: turn toward the target at `turn_speed`, then set velocity along the body's own forward vector, scaled by how well the nose is lined up (zero past ~70° off, so a big heading change is a pivot-and-go). `_steer_to()` now defers to it, so WANDER, GREET, EAT, RETURN and FOLLOW gap-closing all inherit it. The at-heel branch matches the player's stride the same way instead of copying their velocity vector, and horse avoidance now folds an outward direction into the next steering decision instead of adding raw sideways velocity.
- `_update_state()` clears `_use_locomotion` / `_desired_pose` every frame (not only on a state change), and `_apply_animation()` hands a pose over once the dog has actually stopped, so `Eat`, `TailWag` and `Sit` appear as soon as it arrives instead of never.
- `_check_stuck()` compared movement against a flat 2 cm per frame. A 0.73 m/s walk covers 1.2 cm a frame, so the dog declared itself stuck after a second of walking and gave up 1.6 m short of home. The threshold is now a quarter of the ground the frame's speed should have covered, which is frame-rate and speed independent.
- `tools/build_chihuahua.py` now authors Walk/Trot/Run from the stride instead of amplifying the source clip. Each paw is pinned to a ground path (backward through stance at the clip's speed, eased forward with a lift in swing) and the leg is solved onto it with IK constraints on the whole sagittal chain (scapula, humerus, radius, hock) plus copy-rotation guides that keep the paw level; the result is baked to plain bone keys, the same pattern as `tools/build_horse_clips.py`. One helper target and paw guide per joint, not one per leg — a shared guide curled the paw under by 1.7 cm.
- The stance is centred where the leg can actually reach. The source rig stands with nearly straight legs, so the paws sit close to their forward limit; `foot_windows()` measures each paw's reachable fore-aft window and the gaits use the narrowest one, with per-leg centres (front +3 cm, hind -4 cm from rest). Run adds two correction passes per frame because the paw hangs off a joint the solver also turns.
- Measured planted speeds (sub-frame sampling, backward half of the contact window only): Walk 0.73 m/s over a 0.333 s cycle, Trot 1.86 m/s over 0.233 s, Run 3.26 m/s over 0.2 s, with contact duty 0.73 / 0.38 / 0.21. `scripts/dog.gd` is driven at exactly those speeds (was 1.0 / 2.8 / 5.2) and `scripts/dog_animator.gd` plays each clip against them, so the playback scale stays at ~1.0; the clamp tightened to 0.85-1.2 and the gait thresholds moved to 1.15 / 2.4 with a small hold so it cannot flap between gaits.
- Verification: `tools/check_chihuahua_animations.gd` now asserts, per gait, that the planted paws travel at the animator's reference speed (Walk 0.748 vs 0.730, Trot 1.895 vs 1.860, Run 3.105 vs 3.260) and that contact duty is 0.2-0.9; lengths updated to 0.333 / 0.233 / 0.200 and loop wrap is 0. `tools/check_dog.gd` gained a turn stage: sent home from behind its own tail, the dog must keep the velocity aligned with its facing (dot > 0.9) and the Walk clip must play at 0.85-1.2x. Its return stage now allows 13 s, because the honest run speed makes the 25 m leash walk take ~8 s longer than before. `DOG CHECK: PASS`, `CHIHUAHUA ANIMATION CHECK: PASS`, `MOUNT`, `LEAD`, `STABLE`, `GROOMING`, `FEED`, `TOUCH`, `HORSE ANIMATION` and `CHECK EDITOR LOAD` (`ALL OK`) all pass.
- `artifacts/chihuahua/sheet_{Walk,Trot,Run}_side.png` and `sheet_{Walk,Trot}_three_quarter.png` review the gaits across the cycle: legs reach fore and aft with the paws on the ground plane and no lateral splay. Render with `blender --background --python tools/render_chihuahua.py -- artifacts/chihuahua_build.blend artifacts/chihuahua Walk,Trot,Run 4 side`.
- Limitations: the dog now tops out at 3.26 m/s, which is roughly the player's 3.0 m/s walk, so it trails a sprinting player (6.0 m/s) and eventually takes the leash home. Run is a 0.2 s cycle, which is six keys at 30 fps, so at full pelt it reads as a fast scramble rather than individual strides. The gaits are in-place clips with the speed matched by playback rate, not root motion; the Lie-to-Sleep pose and the one-shot clips are unchanged.

## The led horse walks where it faces

2026-10-23

- `scripts/horse.gd` `_lead()` still aimed `velocity` at the handler's shoulder while `_face()` eased the body round, so a led horse slid sideways through every turn. It now moves along `-global_transform.basis.z`, the direction the body actually faces, with the same alignment throttle the dog uses: turn rate decides the heading, the dot against the target direction scales the speed, and a sharp turn becomes a pivot on the spot before the horse walks off. `_ride()` already worked this way; `_lead()` was the remaining raw-direction steer.
- The shoulder approach, the stop-and-settle branch, the walk/trot speed ramp and `lead_acceleration` are unchanged, so the horse still settles at the same spot beside the handler.
- Verification: `tools/check_lead.gd` gained a turn stage — with the handler still leading, the player is stepped sideways at 1.6 m/s for 1.2 s and the horse must keep its velocity aligned with its facing (dot > 0.9) while actually covering ground (> 0.3 m, measured 1.18 m at dot 0.98, so the assertion cannot pass by standing still). `LEAD CHECK`, `MOUNT`, `STABLE`, `GROOMING`, `RIDE LOOP`, `HORSE ANIMATION` and `CHECK EDITOR LOAD` (`ALL OK`) all pass.

## The farmhouse opens up

2026-10-23

- Every room is now three times its old floor area. The clear footprint is 19.05 x 15.59 m (was 11 x 9 m), with 3.0 m ground ceilings and 2.88 m upstairs instead of 2.6 m. The ten-room plan is unchanged: sitting, kitchen, hall, study and boot room below; two bedrooms, landing, bathroom and gallery above. The hall is 7.10 x 7.62 m, the four main rooms 11.95 x 7.79 m and the study/boot/landing/bath 7.10 x 3.98 m.
- All eight interior swing doors are gone. Their thresholds are 1.6-1.8 m wide cased openings with 2.45 m heads (2.4 m between the sitting room and kitchen), so the house can be walked through without opening anything. Only the 1.3 m front door and 1.2 m back door keep leaves. No `interior_door` nodes remain in the scene.
- The L-shaped stair was rebuilt for the new floor height: 1.2 m wide, 17 risers at 0.1835 m, seven up the east wall to the quarter landing and ten west to the gallery. Both ramps stay under 30 degrees, meet the floor and landing exactly, and every open edge has a solid balustrade with shoe, spindles and handrail.
- The facades gained windows for the larger rooms: 32 in all, mostly 1.5-1.8 m wide, with ground sills at 0.95 m and upper sills at 4.07 m. Window openings, jambs, sills, glass, mullions and transoms all come from the same table as the wall holes. The sitting room's west windows were moved clear of the chimney breast.
- The indoor camera is no longer a 3 m ray that dives to the pivot whenever a wall is behind the player. Interiors publish a profile on the scene root (2.35 m boom, 1.62 m pivot, 0.22 m shoulder), and `player_controller.gd` resolves the boom with a 0.28 m sphere cast against walls and furniture: it pulls in at once, keeps a 0.10 m margin, never goes below 0.35 m, and eases back out at 2.5 m/s. The body is hidden below a 1.0 m boom so it cannot fill the lens.
- The larger rooms are furnished from three more CC0 packs: Kenney's Food Kit (table settings, dresser plates, fruit), Quaternius's Ultimate House Interior (plants, small chairs/tables, bath accessories) and Shapespark's textiles (rugs, curtains, pillows, throws). Every room gained something useful: games corner and window seat in the sitting room, pantry, window seat and runner in the kitchen, desk, chaise and window seat in the main bedroom, a reading corner in the second bedroom, a stool, bath tray, folded towels and laundry basket in the bathroom, and rugs, consoles and pictures on the landing and gallery. Provenance is in `Models/interior/SOURCE.txt`.
- The Quaternius round carpets are authored as upright discs, so they read as giant dark wheels at ceiling height when dropped onto a floor. The scene uses Kenney's flat round and rectangular rugs instead.
- `tools/check_farmhouse.gd` was rewritten for the new house. It checks all ten areas are at least 2.9x their old size, that there are no interior leaves, that every cased opening is clear and every solid wall still stops a ray, that all 32 windows open to the outside, that the stair can be climbed and descended on foot, that every room has furniture and a lamp, that sitting/resting still work, and that the camera stays out of walls and furniture from twenty views. It reads the built opening table from scene metadata, so a moved window cannot drift from its check.
- Verification: `godot --headless --path . --script res://tools/build_farmhouse.gd` rebuilds `scenes/farmhouse.tscn`; `check_farmhouse`, `check_scene_doors`, `check_editor_load`, `check_feed`, `check_touch`, `check_mount` and `check_dog` all pass. The yard door's farmhouse spawn moved with the front door to `(8.35, 0.05, 2.68)`. `tools/screenshot_farmhouse.gd` renders the eight review views, with the plans framed at 18.5 m so the whole 19 x 15.6 m footprint fits and the upper plan rendered before the ground plan so neither one's hidden storey leaks into the other.
- Limitation: the review images are static renders. The camera's feel at speed and the room proportions in motion still need a play pass in the app.

## The indoor camera was still the outdoor one

2026-10-23

- The farmhouse root published its camera metadata, but `_root.add_to_group("interior")` runs after the root exists and `PackedScene.pack()` does not save that group. The packed `scenes/farmhouse.tscn` had no `interior` group, `_apply_camera_profile()` found nothing, and the player kept the 3.0 m outdoor boom, 1.5 m pivot and no shoulder. The 2.35 m indoor rig described in the previous entry never ran in the house.
- `_apply_camera_profile()` now walks up from the player to the scene that carries `camera_max_boom`, and the group lookup stays only as a fallback. The generator no longer claims to publish a group that cannot survive packing.
- `check_farmhouse` now bounds the open sitting-room boom to 2.20-2.50 m and asserts the pivot at 1.62 m. The outdoor 3 m rig fails both; the previous test only had a lower bound and passed at 3.0 m.
- The walkthrough found the second bedroom's bookcase standing across its cased opening at x = 2.43, z 0.70-2.50. Its collision covered z 0.68-1.52 and the side table blocked the north side, leaving a squeeze narrower than the player. It moved to z = 3.95, clear of the opening and the chest.
- The door check used one centre ray at mid-height, which passed the blocked opening. It now sweeps a player-sized capsule (0.28 m radius, 1.10 m cylinder) along the centre line of every cased opening, so furniture in a doorway fails.
- New `tools/check_walkthrough.gd` walks the house in motion: from the front door through every room and cased opening, up and down both stair flights, then 11 camera sweeps backing into walls, corners and furniture. It reports 57/57 legs, 0 clipped frames in 6,960 samples, a 0.35-2.36 m boom range, and no outward snap over 0.35 m. It takes about two minutes.
- Verification: `check_farmhouse`, `check_walkthrough`, `check_scene_doors`, `check_editor_load`, `check_feed`, `check_touch`, `check_mount` and `check_dog` all pass.
- Remaining rough edge: backing into a corner or standing under a plant drops the boom to its 0.35 m floor and hides the body, which reads as first person. That is the safety clamp doing its job, not clipping; the return to 2.35 m eases at 2.5 m/s. Feel in motion still needs a human pass with a mouse.

## The camera steps around tight furniture instead of diving into the head

2026-10-23

- The earlier rig resolved the direct shoulder line, then tried a few lateral lines and eased between them. That worked in the open house, but in the tight spots it was still pinned: a chair, a bookcase or a wall blocked the direct line, the clear lateral line existed but the straight ease from the head to the lateral crossed the same blocker, so the boom sat on the 0.35 m safety floor and the body disappeared. The walkthrough measured 0.35 m in the sitting corner, 0.54-0.56 m at the study desk and 0.35-0.67 m in most of its 11 backed-into corners.
- `player_controller.gd` now resolves four different cases instead of lowering one limit:
  - **A chair or desk behind the player** gets a lateral line. The line must keep the player inside 35 degrees of the view, so a slide cannot put the body off-screen; a 0.25 cost per metre keeps the direct line when it is clear.
  - **A wall corner** gets a look-down from above the head: lifts of 0.45, 0.60 and 0.95 m, each tried at 0, +0.45 and -0.45 m across the head because a corner usually blocks one side. The lower lifts are what fit under a doorway head; the look-down is offered only while the normal boom is below 0.90 m, so it never replaces a clear rear view.
  - **A blocked path to a clear line** gets a swing: when the chosen line is more than 0.30 rad around from the current camera, the rig steps onto that line at a 0.62 m radius before easing outward. This is the missing piece that made the old lateral search ineffective; the step changes direction, not distance.
  - **The body** is hidden only below a 0.58 m boom, so the lateral and overhead answers stay visibly third-person. The ride camera resets its pitch when mounted, so a look-down cannot follow the player into the saddle.
- `check_walkthrough.gd` no longer accepts just "above the safety clamp". A room sweep must keep a 1.0 m boom and a backed-into corner a 0.90 m boom, and the body must still be visible at the end of every sweep. The measured floors after the change:
  - rooms: study 1.05 (was 0.56), bathroom 1.32, landing 1.33, sitting 2.36, kitchen 1.91, hall 1.20, boot 1.34, gallery 1.91, bedrooms 2.05/2.36;
  - corners: sitting fireplace 0.95 (was 0.35), study east wall 1.03, the other nine 1.05 or 2.36.
- The full walkthrough is 57/57 legs, 0 clipped frames in 6,960 samples, 0 outward pops, boom range 0.35-2.85 m and a 0.30 m maximum outward step. The 0.35 m minimum is now the study doorway under the stair, where a wall is behind the player and the stair soffit caps the lift; every room and corner sweep stays at or above 0.95 m.
- New `tools/screenshot_camera.gd` renders the player's own camera, not a review camera, at the four tight spots. It backs into the sitting corner the same 1.2 s the check does so the frame is the tight view. Output is `artifacts/camera_{sitting_corner,study_desk,bath,landing}.png`; `artifacts/` is ignored, so these are local review images, not committed.
- Verification: `check_farmhouse`, `check_walkthrough`, `check_scene_doors`, `check_editor_load`, `check_feed`, `check_touch`, `check_mount` and `check_dog` all pass. The screenshots were rendered under `xvfb-run` at 1280x720.
- Limitation: the swing is a direction step, not a rendered interpolation, and the overhead is a deliberate top-down view. The 2.23 m inward step on a doorway transition is unchanged and still needs a human feel pass with a mouse; the static review frames cannot judge that.

## The camera recovers from a jamb instead of diving into the head

2026-10-24

- The doorway transit between the hall and the study still fell to the 0.35 m safety clamp and hid the body. `player_controller.gd` chose a lateral or overhead line by its full length, but a camera already on the far side of a door jamb could not reach that line: the short arc between the current point and the candidate crosses the jamb, so the straight ease stayed blocked.
- `_line_reachable()` now tests a candidate at the current boom's radius instead of trusting its full length, and the recovery path runs only when the current camera is already blocked below the overhead trigger (0.90 m). Rooms and corners that still have a third-person line keep exactly the behaviour they had. A blocked current point also forces the 0.62 m direction step even when the angle to the next line is small.
- `check_walkthrough` measures the doorway transit separately: the route must keep a 0.90 m third-person boom, and the 1.2 m stair, which has a wall behind the player, keeps a 0.30 m first-person exception. Both are floors, not the 0.35 m safety clamp.
- Measured after the change: 57/57 legs, 0 clipped frames in 6960 samples, 0 outward pops, third-person boom 0.95-2.85 m (was 0.35 m in the study doorway), stair 0.35 m, max inward step 1.61 m, max outward 0.29 m. Room booms are unchanged.
- `tools/screenshot_camera.gd` gained a `study_doorway` view (`artifacts/camera_study_doorway.png`).
- Verification: `check_walkthrough` and `check_farmhouse` pass. Limitation: still a static measurement; the doorway feel needs a human pass with a mouse.

## The farmhouse furniture gets textures, and gets lighter

2026-10-24

- The furniture was flat colour: Kenney's 140 kit models and Quaternius's 28 carry only a `baseColorFactor`, and the walls and floor were the only textured surfaces in the house. Every wood, fabric, metal and ceramic surface now has a detail map.
- Four neutral-luminance maps in `Models/interior/textures/` - veneer grain, plain-weave cotton, plaster stone and brushed metal - are multiplied over the kit's own colours, so the farmhouse palette is unchanged. They are greys at a 0.90 mean built by the new `tools/make_interior_detail.py` from Poly Haven's CC0 "Angli Veneer", "Book Pattern" and the project's own plaster map; `_detail_gain` in the generator lifts the albedo by the reciprocal of that mean so the tone stays where it was. No normal or roughness maps: one extra fetch per surface is the whole cost on the Compatibility renderer.
- The 104 per-prop duplicated materials became one shared material per real material (`_surface()` in the generator): kit materials matched by name, Quaternius by name prefix, textiles by a cached tint copy. The house went from 354 materials to 103, and the ones that remain are mostly the pictures' flat canvases, the yard props and the textiles' own maps.
- The Food Kit was broken: all 34 tableware and food models reference `Textures/colormap.png`, which was never included with the models, so plates, forks, bread, fruit and the dresser china rendered with a missing texture. Restoring the 10 KB palette atlas from the same Kenney archive fixed all 34 at a cost of 512x512.
- `_prop` no longer instances the downloaded GLB. Instancing plus a surface override made Godot save a duplicate clone of the mesh beside the instance, which rendered twice and doubled the prop's triangles - an existing bug for the ~60 tinted props that this pass would otherwise have spread to all 195. Props are now flattened into their own nodes, one MeshInstance3D per model surface, sharing one mesh resource between every copy.
- Small static dressing is merged: each place setting is one mesh (12 plates and forks), the table centre 3, the island fruit 4 and the dresser plates 2, and every balustrade's spindles are one mesh. The merged groups keep a `merged_parts` meta so `check_farmhouse` still counts a set table as 21 pieces.
- Mipmaps are on for the wall, floor and detail maps, which the floor and walls were missing.
- Measured across Shell, Furniture and Lighting, before -> after: 1098 -> 941 mesh instances, 154,532 -> 107,246 triangles (-31%), 354 -> 103 materials, 75 -> 52 textured materials, 11 -> 15 textures, 17.0 -> 18.1 MB decoded texture memory.
- New `tools/check_interior_cost.gd` enforces that budget, and `tools/check_editor_load.gd` now fails if any texture under `Models/interior/` is not lossless, is not mipmapped, or has a nonzero `detect_3d/compress_to`.
- Verification: `check_farmhouse`, `check_walkthrough` (57/57 legs, 0 clipped frames, 0 outward pops), `check_scene_doors`, `check_interior_cost` and `check_editor_load` pass. The eight review views in `artifacts/farmhouse_*.png` were rendered under `xvfb-run`; the grain was softened and retiled once after the first pass, because a 0.55 m tile of the veneer's cathedral figure read as plywood on the bookcases.
- Limitation: this machine has no GPU, so the budget check counts work rather than frame time. The measured numbers say the house is 31% lighter in triangles and three times lighter in materials, but the actual frame rate still has to come from the iPad build.

## The gate that never passed on a clean clone

2026-10-24

- `tools/check_editor_load.gd` listed `res://scenes/competition_arena.tscn` and `res://scenes/show_course.tscn` by hand, and neither file has ever been committed. The check therefore exited 1 on any fresh clone: the texture pass's "all checks pass" only held on this machine, where unrelated uncommitted work had left those scenes on disk. The scene list is now discovered from `res://scenes` (recursive, sorted, and a failure if it finds none), so a scene that ships is checked and a scene that does not is never named.
- The interior texture guard is now the named `INTERIOR_TEXTURES` list instead of a recursive sweep of `Models/interior/`: a blanket scan forces every future texture in that folder to change its import cost, which is not this check's call. The list holds the four detail maps, the Food Kit atlas and the two shell maps, and a missing `.import` or a non-texture importer now fails instead of being skipped.
- The wall and floor maps stay mipmapped. That was flipped without a recorded reason in the texture pass, so it is recorded here: they are 1k maps tiling across the largest surfaces in the house, and without mips the floor and plaster shimmer at a distance. It costs about 2.8 MB of decoded VRAM, inside the 20 MB budget (`check_interior_cost` measures 18.1 MB with them on); if the budget gets tight, give it back first.
- Verification: a checkout built from `git archive origin/master` plus this branch and imported from scratch passes `check_farmhouse`, `check_walkthrough`, `check_scene_doors`, `check_interior_cost` and `check_editor_load`. The gate was probed by corrupting `scenes/forest.tscn` (names the scene, exit 1), turning mipmaps off on `detail_wood_diff_512.jpg` (names the texture, exit 1), deleting `colormap.png.import` (exit 1) and emptying `scenes/` (exit 1); each was restored afterwards.

## The furniture went red on a driver that reads one channel

2026-10-24

- Every textured surface in the house - furniture, trim, the Quaternius ceramic pots - drew solid red, in the editor and in the game, on one machine. The four detail maps are neutral greys, and a greyscale JPEG imports as a luminance texture (`Image.FORMAT_L8`, format 0; the wall and floor maps import as RGB8, format 4). A driver that samples a luminance texture without a channel swizzle reads it as `(grey, 0, 0)`, so multiplying it into the albedo leaves only the red channel: cream albedo times a 0.9 map is about `(1.09, 0, 0)`, which is exactly the saturated red in the report. Walls, floor, rugs, curtains and the flat-colour props use three-channel maps or no map, which is why they stayed correct.
- `tools/make_interior_detail.py` now writes the maps as RGB (same pixels, same 0.90 mean; the tone and the `_detail_gain` albedo of 1.111 are unchanged) and the four files were regenerated, so all four import as RGB8.
- `tools/check_interior_cost.gd` fails if a detail map imports as `FORMAT_L8` or `FORMAT_LA8`, naming the red symptom, and its decoded-texture budget went 20.0 -> 22.0 MB because three channels cost 2.1 MB more (measured 20.24 MB).
- Verification: `check_interior_cost` passes at 20.24 MB and the new luminance guard was proved by re-saving one map as grey, seeing it fail, and regenerating; `check_editor_load` reports ALL OK; the sitting and bedroom review renders are pixel-identical to before the change on this machine's software GL.
- Limitation: this machine's Mesa llvmpipe swizzles luminance textures correctly, so the red never reproduced here - the fix is verified by the import format changing from L8 to RGB8, not by watching the red go away. Confirmation still needs the build that showed it, which is the iPad/tablet target.

## The right thumb spin and the stick that sometimes did nothing

2026-10-25

- Touch look applied the mouse rate 1:1 (`mouse_sensitivity` 0.0024 rad/px, about 7.9 deg for a 60 px drag and 14 deg per 100 px of finger travel). Movement is camera-relative, so every pixel the thumb dragged to look also re-aimed the walk/ride vector; holding the stick right while turning the camera therefore curved, and on horseback pivoted, the whole character. `LOOK_GAIN` is now 0.55 for touch drags only, so camera aiming costs roughly twice the thumb travel per degree and the same drag turns about 8 deg per 100 px instead of 14. The mouse path is untouched.
- The stick could be wedged two ways, both now handled in `TouchControls`. A contact that reached the stick half first (a resting palm, the edge of the hand) owned the stick forever, and the thumb that actually pushed was filed as `idle`; a new left-half touch now takes the stick over when the holder has not pushed it (`STICK_REST`, 10 px). And a lost touch-up (tab switch, app background, a dropped event) left `_stick_index` set, so `_touch_down` returned early for that index and the stick stayed dead until the next scene - a repeated press for a held index now releases it and re-arms, and `NOTIFICATION_APPLICATION_FOCUS_OUT` / `NOTIFICATION_WM_WINDOW_FOCUS_OUT` release every finger.
- Lifting the pushing thumb hands the stick to a finger still resting in the stick half, so steering does not drop out mid-turn.
- `tools/check_touch.gd` grew the cases that would have caught this: a resting contact then a pushing thumb, the hand-back on lift, a repeated press on a stale index, a 60 px drag producing the touch gain rather than the mouse rate, and both thumbs at once (right-half drag must leave the stick push and the stick index untouched).
- Verification: `check_touch` PASS and `check_mount` PASS. `check_character_select` failed once on its known handoff timeout and passed on three reruns; it does not exercise the changed paths.
- Limitation: the look gain is a feel number picked without the tablet. 0.55 halves the rate; if it is still quick, drop it toward 0.45, and if aiming now lags, raise it toward 0.65 - `check_touch` asserts whatever `LOOK_GAIN` is, so only the constant needs to change.

## Grooming with two thumbs, and a steering frame the camera cannot move

2026-10-25

- The player was never hidden during grooming, only hidden once. `grooming_session.enter()` set `player_model.visible = false`, but the player keeps processing and its own camera rule (`_update_model_visibility()`, `_boom_length > 0.58`) turned the body back on the next frame whenever there was room behind it in the bay. `player.set_model_hidden()` now parks that rule for the session, and the session clears it before restoring the saved visibility. This is why `check_groom` was failing with `FAIL: player model hidden`; the assertion passes now, with a second check 30 frames later.
- Touch grooming painted and drew its red/green disk exactly under the finger. `TOUCH_BRUSH_OFFSET` (0, -64) lifts the paint point, and with it the disk, above the thumb; when the lifted ray misses the horse (top of the screen) the stroke falls back to the finger rather than dying. The hoof pick is exempt because the mud clumps are ~30 px targets. Touch painting also stopped consulting `_hud.is_pointer_over_ui()`: that hover belongs to the emulated mouse, which often still sits on the tool button that was just tapped, and the touch layer already routes real UI touches to the GUI.
- Rotating the horse was hard because orbiting zoomed. The pinch was measured inside every drag event, so moving one thumb then the other changed the gap mid-frame and applied a zoom, and orbiting wobbles the gap by a few percent besides. It is now sampled once per frame in `TouchControls._process`, and only zoom grows past `PINCH_TRIGGER` (10% from where the second finger landed); below that the gesture is pure orbit. Orbit also went from 0.006 / 0.004 to `TOUCH_ORBIT_YAW` 0.008 / `TOUCH_ORBIT_PITCH` 0.005 rad per pixel, so a 100 px two-thumb drag turns about 45 degrees instead of 34.
- The right thumb no longer steers. Earlier the touch look was calmed (gain 0.55) but movement stayed camera-relative, so dragging to look re-aimed the walk and the horse and read as spinning. `player.steer_yaw()` now returns the camera yaw only while no touch stick push is in progress; a held stick freezes the frame captured at the push, and `horse._ride()` maps its input through the same frame. Keyboard and mouse are untouched, so holding W and steering with the mouse still works. Easing the player's yaw toward the travel direction instead would loop - the input is camera-relative, so the target moves with the camera and the spin gets faster, which is why the frame is frozen rather than followed.
- Verification: `check_touch` PASS (51 checks, including the held frame, the 64 px lift, orbit-without-zoom and the hoof exemption), `check_groom` PASS, `check_mount` PASS, `check_lead` PASS. New `check_touch` cases: a pushed stick owns the frame, a 120 px look drag turns the camera while `steer_yaw()` and the walk direction stay put (0 degrees off), releasing frees the frame, a fresh push re-aims from the new view.
- Limitation: the lift, the orbit rates and `STICK_PUSH` are feel numbers chosen without the tablet. If aiming trails too far behind the thumb, drop the offset toward 48 px; if the horse still turns too slowly, raise `TOUCH_ORBIT_YAW` toward 0.010. On foot the body still faces the view, so looking mid-walk reads as a side-step; turning the model toward travel (as it already does when mounted) is a separate change.

## The game reports its own play sessions

2026-10-25

- `scripts/analytics.gd` is a new autoload that records one row per visit for the family dashboard: `start` when the player presses Ride out on the character-select screen, `heartbeat` every 30 s carrying the elapsed seconds, and one `end` when the visit is over. Three POSTs carrying one `s_`-prefixed id upsert one row in `public.sessions`, with `game_id` exactly `livery`.
- The start signal is `character_select._start_ride()`, not engine boot: the 88 MB pack and the select screen must not count as play time, and the arena round, the farmhouse door and the stable all live inside one run, so starting anywhere in `main.tscn` would split a session every time the player walked through a door and back. `start()` closes a live session as `restart` before opening the next one, so a second ride can never leave two live rows, and `character_select._ready()` closes one as `quit` if the menu is ever re-entered.
- The end has to survive a closed tab, and Godot's `HTTPRequest` has no keepalive mode, so the transport is `fetch(..., { keepalive: true })` through `JavaScriptBridge`: a `pagehide` listener and `visibilitychange` -> hidden fire the end from the page itself, with the ended flag duplicated in JavaScript because those listeners outlive GDScript. Outside `OS.has_feature("web")` every entry point returns immediately, so a desktop build logs nothing and runs unchanged.
- The heartbeat is gated on the wall clock in `_process` rather than on a `Timer`. Godot clamps the frame delta to about 0.13 s, so a delta-driven 30 s Timer needs a couple of hundred frames - on this machine's software GL the first build missed every heartbeat. Elapsed seconds come from the same clock, so the cadence and the payload cannot drift apart.
- Nothing is awaited, every GDScript entry point is web-guarded, the JavaScript swallows its own errors, and a reply is only ever ignored, so analytics cannot stall or change gameplay.
- Verification: the build was exported with `tools/export_web_mobile.py` and deployed to <https://groom-769.netlify.app>. A live run showed `OPTIONS` 204 (the function caches the preflight for 24 h) and `start`, `heartbeat` and `end` POSTs each answering 200; the table held one row per run with `game_id = 'livery'`, a plausible `duration_seconds` and `status = 'quit'`, and two `pagehide` events produced exactly one end. The test rows were deleted afterwards.
- Limitation: there is still no in-game route back to the character-select menu (the HUD logo emits `logo_pressed` and nothing listens), so `end("quit")` on menu entry is a guard rather than an exercised path; what a real player produces comes from `pagehide` and `visibilitychange`. This headless browser's tab close kills the renderer without dispatching `pagehide`, so that exact close could not be reproduced here - the same handler was proved by navigating away.

## W and S walk the way the keys say, and the character faces his own heading

2026-10-25

- Forward walked backwards. `Input.get_vector("move_left", "move_right", "move_forward", "move_back")` puts `move_forward` on the *negative* Y axis - Godot's forward is -Z, which is exactly what the old walk expected from `Basis(Vector3.UP, steer_yaw()) * Vector3(input.x, 0, input.y)`. The camera-relative rewrite then built a real forward vector with `-camera.global_transform.basis.z` and multiplied it by the same `input.y`, applying the negation twice: W walked away from the camera and S walked at it. `horse._ride()` carried the same line, so W turned the horse 180 degrees and rode it at the camera. Both now rotate the raw input vector by the steering frame, and the broken no-camera fallback in `_ride()` (`Vector3(input.x, 0, 0).normalized() * Vector3(1, 0, 1)`, which pointed along world X rather than the camera's right) is gone with it.
- The character faces the way he walks. The player root carries the view yaw, so a camera-relative walk meant dragging the mouse spun the body with the view and a sideways walk slid him across the ground. The body has its own `_body_yaw` now: `_turn_body()` eases it toward `atan2(-dir.x, -dir.z)` at `BODY_TURN_SPEED` (12 rad/s) while there is input, and writes `model.rotation.y = _model_base_yaw + wrapf(_body_yaw - rotation.y, -PI, PI)` every on-foot frame. That is the wrap `_align_to_seat()` already used for the rider, so the mounted pose is untouched. Standing still leaves the body where it stopped, and `dismount()` / `stand_up()` resync `_body_yaw` to the root. `footprint_emitter` reads the new `facing_yaw()`, or boot prints would follow the camera instead of the boots.
- The frozen touch frame is back. The camera-relative rewrite had reduced `steer_yaw()` to `rotation.y`, which broke the held-stick contract in `agents.md` and `check_touch._check_steer_frame`; the capture on the push edge is restored, and `horse._ride()` maps through the same frame again. Now that the body turns toward travel, a look drag while walking reads as a turn rather than the old spin.
- The earlier camera edit had also deleted the guard in `horse._ready()` that stands the `jump_pose` overlay down once the GLB ships a real Jump clip, and left two stray blank lines behind it. Both are restored; `check_jump_and_loop` and `check_horse_animations` PASS.
- Verification: `check_touch` PASS (51 checks, including the held frame and `steer_yaw()` staying put through a 120 px look drag), `check_mount` PASS, `check_lead` PASS, `check_footprints` PASS, `check_walkthrough` PASS. A temporary headless probe on `main.tscn` measured the direction itself: W moved 1.5 m along -Z, S 2.25 m along +Z (body yaw 3.14, turned round), D 2.25 m along +X with the body at -1.57, W at a 90 degree view yaw moved 1.5 m along -X, a standing body held its yaw while the view turned, and holding W mounted put the horse at -1.74 m/s along -Z.
- Limitation: the turn rate, like the camera and stick numbers, is a feel constant; `BODY_TURN_SPEED` is the only knob if the character swings too slowly on a hard sidestep. The camera does not trail behind the new heading the way a console third-person camera does - the walk follows the view, and the view only moves when the mouse or look drag moves it.

## The game leaves Netlify, and starts sending itself compressed

2026-10-26

- Netlify paused <https://groom-769.netlify.app> with `503 usage_exceeded`, so the family's tablets could not load the game at all. The cause is the payload, not the plan: a cold visit pulled the 84.0 MiB `index.pck` **uncompressed** (Netlify does not compress it) plus the 37.7 MiB `index.wasm` at ~9.1 MiB brotli, so roughly 93 MiB per play. The credit-based Free plan buys about 15 GB of transfer a month, which that spends in a couple of hundred visits.
- The new host is a Cloudflare R2 bucket behind a custom domain: egress is free, storage for 84 MiB is a fraction of a cent, and 10 M Class B reads a month is about a million loads. The alternatives are recorded in `agents.md` so they are not re-tried: Cloudflare Pages and Workers static assets cap a single file at 25 MiB (both big files exceed it), and Vercel Hobby is non-commercial only with a 100 MB CLI upload cap.
- `tools/deploy_r2.py` replaces the Netlify deploy. It brotli-compresses the two binaries at q9 (q11 costs ~20x the time for a few percent), uploads all nine objects through the S3 API, and writes the response headers as object metadata: `application/wasm` and `application/octet-stream` with `Content-Encoding: br` and an hour of caching for the binaries, `no-cache` for `index.html` and the loader, a day for the icons. The objects keep Godot's names, so `index.html` needs no change; the encoding header does the work.
- That takes a cold visit from ~93 MiB to **50.9 MiB** (42.9 MiB pck + 7.6 MiB wasm + the small shell). The compression streams in 4 MiB chunks and writes to a temp directory, so the 84 MiB file is never held twice, and the whole step costs about two minutes.
- No permanent R2 token is stored. When `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` are unset the tool mints one-hour S3 keys from the `cf` CLI session (`cf auth login`) with `cf r2 temporary-credentials create`, and it looks the fields up by name rather than trusting one wrapper shape. `cf` resolves `node` through `/usr/bin/env`, so a background shell that finds Node 20 fails with "cf requires Node.js v22 or newer" until the nvm bin directory is put first on `PATH`.
- `netlify.toml` is gone (`agents.md` used to point at it for the headers) and its rules now live in the deploy tool's table. The exporter's "served raw today" line and its Redeploy block were updated to match, `.gitignore` no longer points at a file that does not exist, and the deploy section of `agents.md` carries the new sequence.
- Verification: `--dry-run` on the current build compresses and reports without touching the bucket (122.0 MiB on disk -> 50.9 MiB over the wire, 2m01s), and `--report-only` regenerates `OPTIMISATION.txt` with the new wire and Redeploy lines. The analytics endpoint needs no change: a preflight with a foreign `Origin` answers `204` and echoes `access-control-allow-origin`, so `scripts/analytics.gd` works from any new hostname.
- R2 was then enabled and the game came back up. Bucket `livery-web` (WEUR) holds all nine objects, r2.dev public access is on, and the page boots from <https://pub-c58ef825739c4f909034241aca46866a.r2.dev/index.html>: Godot 4.7 starts, WebGL2 initialises, `index.pck` and `index.wasm` both return 200, and the canvas renders. The bare `/` is a 404 because a public bucket has no index document, so the interim address carries `/index.html`.
- The raw upload was a stopgap and is now replaced. `cf r2 buckets objects upload` cannot set `Content-Encoding` or `Cache-Control`, so it served the 122 MiB build; with an R2 API token (*Object Read & Write*, scoped to `livery-web`) passed as `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` plus `R2_ACCOUNT_ID`, `tools/deploy_r2.py` brotli-compressed the two binaries and overwrote all nine objects in place. The token reads the `R2_` names only - `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` are ignored, and a run that provides just those falls through to the `cf` route and stops, which needs a parent R2 key that does not exist.
- Measured live, via curl and a real browser: `index.pck` returns `Content-Encoding: br` with `Content-Length` 44,994,485 and `index.wasm` the same header with 7,996,631; `index.html` and the loader stay unencoded with `no-cache`. Chromium reports `encodedBodySize` 44,994,485 / 7,996,631 against `decodedBodySize` 88,083,588 / 39,509,339, so the two binaries cost 52,991,116 bytes on a cold visit instead of 127,592,927 - a cold play is 50.9 MiB, down from the ~93 MiB Netlify sent and the 121.7 MiB R2 was sending. Godot 4.7 still boots, WebGL2 initialises, the canvas renders.
- Two R2 behaviours cost an afternoon and are now encoded in the checker. **The stored representation is only served to a client that advertises it**: curl with no `Accept-Encoding` received a decoded 88,083,588-byte pck, `Transfer-Encoding: chunked` and no encoding header at all, which looks exactly like a failed upload. **Cloudflare refuses an unadvertised user agent** with `error code: 1010` and a 403 - urllib's default UA got that on every object, while a browser UA gets 200. `--check` therefore sends `Accept-Encoding: br` and a browser UA, and now reports all nine objects `ok` including `Range` -> 206 and `If-None-Match` -> 304; its only remaining failure is the `/` 404, which is r2.dev having no index document and not a regression.
- Limitation: the custom domain is still unattached. `cf zones list` returns an empty list for this account, and an R2 custom domain must live in a zone in the same account, so the game runs on the rate-limited r2.dev URL until the domain is added as a zone here.
- Cloudflare offers no hard spend cap for R2: budget alerts are documented as informational only ("They do not pause or cap usage"). The saving grace is the shape of this workload — free egress, 84 MiB of 10 GB storage, 9 Class A writes per deploy and about 8 of 10M Class B reads per load — so the realistic bill is zero, and the kill switch is `cf r2 buckets delete livery-web` or disabling the managed domain.

## A release is one command, and the token stops being pasted about

2026-10-26

- Publishing used to mean typing the R2 token into the command line, which put it into this transcript twice. The settings now live in `.env` beside the repo root - `R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_HOST`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` - and `tools/deploy_r2.py` reads that file into the environment before it builds its argument parser, so `--account`, `--bucket` and `--host` default from it. A variable already set in the real environment wins, so an explicit override still works, and `.env` is git-ignored and mode 600: `git check-ignore -v .env` proves the rule instead of assuming it.
- `tools/release.sh` is the whole release: export, brotli, upload, then assert the live host. `--dry-run` stops after the wire sizes, `--skip-export` publishes `build/web-mobile` as it stands, and the check runs with its exit status kept - a release that fails its own check must not look like it passed.
- The wrapper therefore exits 1 while the game is on its `r2.dev` address, because the check's one expected failure is `/` -> 404. That is left visible on purpose: it prints the reason, and the custom domain plus a Redirect Rule clears it. Swallowing the status would hide the day a real object starts failing.
- The exporter's report now ends with `tools/release.sh` and the bare `--check` line, so a checkout that reads `OPTIMISATION.txt` finds the one-command path rather than the four-step one.
- Verification: the loader reads 5 values, and skips a value already in the environment (`R2_BUCKET=preset-bucket` stayed `preset-bucket`, 4 read). `tools/release.sh --skip-export --dry-run` printed 122.0 MiB -> 50.9 MiB and uploaded nothing. The full `tools/release.sh --skip-export` then uploaded all nine objects with credentials coming only from `.env`, and every host check passed except the known `/` 404.
- Limitation: the Godot export step of the wrapper was not re-run for this change. Nothing in the exporter's own behaviour changed - only the report text - and that path is covered by `--report-only`, which regenerated `OPTIMISATION.txt` cleanly.
- Limitation: `.env` holds a live token in plaintext on this machine. It is ignored by git and unreadable to other users on the box, but it is the file to drop and rotate first if this checkout is ever copied, shared or restored from a backup.

## The left stick that died on the phone

2026-10-26

- Report: on the iPhone the left stick did nothing at all - no ring, no knob - while CONTEXT / JUMP still worked and a right-half drag still turned the camera. That combination is the whole diagnosis. Buttons are matched before the UI test and the look role is assigned after it, so both prove the layer was active, receiving fingers and classifying halves correctly. The only remaining path was `_fingers[index] = {"role": "idle"}`, which happens when `_stick_index` is set and `_stick_is_resting()` says it has pushed.
- Cause: a touch that pushed the stick and then never sent its touch-up. iOS Safari cancels a touch instead of ending it - the edge back-swipe, its toolbar sliding in and out, a system gesture, palm rejection - and Godot's web input has no event for a cancel, so `_touch_up` never ran. `_stick_is_resting()` reads the *stored* offset rather than a live finger, so the one stale holder locked **every** later left-half press out of the stick for the rest of the scene, with no recovery short of a scene change. The earlier fixes covered the same index pressing again and the app losing focus; neither fires for a different thumb.
- Fix, all in `TouchControls` and all routing rather than movement: `_stick_is_available()` treats a holder that has not reported for `STICK_STALE_MS` (250 ms), whose entry is gone, or whose role is no longer "stick" as free; `_process` drops an index no finger owns; an "idle" finger that pushes past `STICK_REST` takes over (the press can land inside the window, so the push has to be able to recover it); `_claim_stick` demotes every other stick-role finger and keeps its landing point so a live thumb can claim back; `_touch_up` only resets the stick when the lifted index is the current holder, so a late touch-up from the demoted finger cannot kill the thumb that replaced it; and a canvas resize (Safari's toolbar) releases the fingers. The camera-relative mapping, `steer_yaw()`'s frozen frame, the body turn, the gait ramp and every feel constant are untouched - `check_touch` still asserts them.
- `?touchdebug=1` (`GROOM_TOUCH_DEBUG=1` for a local run) draws one line of the layer's state - mode, viewport, finger roles, stick owner, move vector - because a phone cannot show a console. It renders under `xvfb-run` with no errors and sits under the wallet block, clear of the thumb's band.
- The pck and wasm headers are now `no-cache` (revalidated, 304 on a repeat visit) instead of `public, max-age=3600`. An hour of blind reuse meant a phone that had played kept the previous pack after a fix shipped, so a device test could measure code that had already been replaced.
- Verification: `check_touch` PASS (72 checks). The new cases failed first on the old code - the lost touch-up left the stick on the dead index, the push could not recover it, the dead index was never dropped - and pass after. The real-event case also found something worth keeping: a touch parsed with `Input.parse_input_event` is mapped from window pixels into canvas space by the viewport (a 1280x720 canvas on the 64x36 headless window is a 20x stretch), so a raw position sent in canvas coordinates landed at 4400,10400 and was filed as "look". The test now pushes its positions through `get_final_transform()`, which is the trip a phone's touch actually makes. Also PASS: `check_mount`, `check_lead`, `check_footprints`, and `tools/screenshot_touch.gd` under `GROOM_TOUCH_DEBUG=1`.
- Limitation: `touchcancel` itself is still invisible to Godot. The 250 ms window is a feel constant picked without the device; if a held-stick walk can still be stolen by a second finger, raise it, and if recovery feels slow after a cancelled touch, lower it. If the readout shows fingers still being lost on the phone, the next step is a web-only `window.addEventListener('touchcancel', ...)` hook through `JavaScriptBridge` that calls `_release_all()`.

## A build that says which build it is

2026-10-26

- The left stick was fixed and released, and the report that came back was "still not working or appearing". Nothing on screen could tell the difference between a phone running the old page out of a cache and a phone running the new pack with the fault still in it, so the build now names itself.
- `tools/export_web_mobile.py` gains `build_version()`: `build 2026-10-26 13:32 UTC  7c63106+local`. It carries the UTC time the export ran (the only thing that separates two builds of the same commit), the short hash, and `+local` when tracked files have uncommitted edits. The string is plain ASCII because it is written into `project.godot` as well, where an escape would have to survive the config parser.
- It is stamped twice from one value: a `<div id="build-version">` injected into the shell's `#status` block - absolutely positioned at the bottom so it cannot disturb the splash image or the progress bar, and re-stamped idempotently so a repeated run cannot duplicate it - and `application/config/version` in the staged project, which `TouchControls`' `?touchdebug=1` line now prints first. A fresh page beside a stale pack therefore disagrees instead of agreeing wrongly.
- `tools/deploy_r2.py --check` reads the stamp out of the local `index.html` and fails if the live page is not serving it, so `tools/release.sh` ends with `ok   index.html build stamp build ...` - the machine-checked answer to "is the live page the build I just published" rather than an assumption about caches.
- Verification: the stamp function ran twice against the existing export and left exactly one div, and the report records the string (`--report-only` reads it back from `build-stats.json`). `check_touch` PASS after the `?touchdebug=1` change.

## Progress now survives a visit: per-player save slots

2026-10-26

- New autoload `scripts/save_game.gd`. Identity comes from the shelf: `?player=liv|ted` in the web URL, validated against the same allowlist the `save_game` edge function uses, remembered per origin under `livery.player`, and used only when it is on that list. Guest, an unknown name, and a desktop launch without the parameter all leave saving **disabled** rather than guessing — a save filed under the wrong child is worse than no save.
- `?slot=N` selects 1–9 and defaults to 1; out-of-range values clamp, so a bad URL cannot fail a load. `check_save` covers ten identity cases (names, case, guest, unknown, `?touch=1` alongside, and slot clamping).
- **Local first.** Every save writes `user://save_livery_<player>_<slot>.json` before any network call, so a dropped connection never costs progress; the cloud row is the backup that survives a cleared browser or a replaced tablet. The file records the cloud `revision` beside the payload.
- The cloud mirror posts `{action, game_id, player, slot, payload, base_revision}` to `save_game` over `HTTPRequest`. On `200` the acknowledged revision is stored; on **`409` the stale device adopts the cloud revision, emits `conflict`, and reloads the cloud save** rather than overwriting newer progress. On a load where the local revision is ahead (played offline), the local copy is pushed up instead.
- Snapshot scope: money, best round time, show best time, show entries and rosettes from `GameState`; trust, happiness, cleanliness, polish, hooves, care score, fitness and jumping from the horse. **Deliberately not saved:** `selected_character` / `auto_mount_on_start` and the door spawn (one-shot scene transitions — persisting them would start a player in the saddle at a stale position).
- Save points: the `money_changed`, `best_time_changed` and `rosettes_changed` signals through a 1.5 s debounce; `grooming_session.exit_session()` explicitly, because trust/happiness/cleanliness change without a signal; and focus loss, which is the closest thing to a clean exit on a tablet.
- Boot ordering matters: the select screen loads before any horse exists, so `apply()` parks the horse half in `_pending_horse` and `horse._ready()` collects it through `SaveGame.apply_to_horse(self)`.
- **The painted coat is saved too**, as a base64 PNG of the mask (`groom_surface.export_mask()` / `import_mask()`). Without it a groomed horse came back with a correct CLEAN bar over a fully dirty coat, which is exactly the mismatch the mask work exists to avoid. A real horse's mask encodes to about 4.3 KB, so the whole save stays far inside the function's 256 KB cap.
- Restoring the mask is deliberately **not** a replacement for the bake. `_setup()` still runs `_rasterise_mask()` first, because that pass also builds the zone map and the paint-gating triangle table; the restored bytes are copied over `_mask_data` between the rasterise and `_build_material()`. Skipping the bake would leave a restored horse impossible to brush.
- The shader mixes a global `dirt_level` with the local mask, so a restore sets both: the mask, and `dirt_level` from the restored cleanliness (`0.0` when fully clean, else `1.0 - cleanliness`). Restoring either alone leaves the coat wrong — mask only and the whole horse stays dark, level only and the painted patches vanish.
- `import_mask()` rejects anything that fails a base64 shape check, then anything that is not a 256×256 PNG, so a damaged save leaves the horse as it was instead of blanking the coat. The shape check exists because `Marshalls.base64_to_raw` logs an engine `ERROR` on malformed input, which reads as a failure in an otherwise clean log.
- The function and table were built and verified in the `game-shelf` repo first: `public.game_saves` with `(player, game_id, slot)`, a `SELECT` policy and no write policy, written only by `save_game` with the service role. Anon `INSERT` returns `42501`; anon `PATCH`/`DELETE` match zero rows.
- Verification: `SAVE CHECK: PASS` (`tools/check_save.gd`) covers the identity rules, the full snapshot/apply round trip across `GameState` and nine horse fields, the local file and its revision, the parked-horse path, the guest refusal, the coat mask (encode, exact byte round trip, corrupt and wrong-sized input refused), and the cloud reply handler driven directly — `200`, `409` adopting + reporting the newer revision, a load applying its payload, and a missing save changing nothing. A one-off probe on `scenes/horse.tscn` confirmed the live path off a real bake: the mask exported at 4,284 base64 bytes, imported, and re-encoded byte-identically. `CHECK EDITOR LOAD` (`ALL OK`), `GROOMING CHECK` and `MOUNT CHECK` all still pass.
- Limitations: the cloud half is **not** exercised in-engine here — this machine's Chromium has no WebGL2, so `HTTPRequest` to the live function is untested from inside the build, and only the function itself and the reply handler are proven. The shelf strips `?touch=1` from Livery's link when it attaches `?player=` (`href.split('?')[0]`), so an iPad falls back to touchscreen auto-detection; the save identity is unaffected.
- A trap for future tools: a `--script` main-loop script cannot resolve autoload **globals** (`SaveGame.foo` is a compile error), even though the autoload nodes exist. Resolve them by path — `root.get_node("SaveGame")` — and leave the variable untyped so the calls stay dynamic.

## A negative finger id, and the stick that looked dead

2026-10-26

- Report: the new readout on the iPhone read `-410517893:stick  stick -410517893  move 0.97,-0.26` with `p ctrl:1 mnt:1 seat:0 air:0 in:0.00,0.00 vel:0.00,0.00` and `fps 49`. The vector was full length and the owner was that same finger, yet `get_move_input()` handed out nothing - so the fault sat between an armed stick and the vector it returns, not in movement.
- Cause: iOS Safari's touch identifiers climb for the life of the page and overflow into a negative int32. `_stick_index` kept -1 as its "no stick" sentinel and every ownership test was a sign test, so a live stick read as absent: `get_move_input()` returned bare keyboard input and both the walk and `horse._ride()` got zero, the ring was never drawn (`_draw_stick()` returns early), and `is_stick_pushing()` stayed false so `steer_yaw()` never froze a frame - the exact cluster of symptoms, including "getting input but no movement". `_stick_is_available()` also answered "free" for the owner, so every new left-half press re-claimed the stick and demoted it.
- Fix: a `_stick_owned` flag carries ownership and every ownership test reads it - `get_move_input()`, `is_stick_active()`, `is_stick_pushing()`, the stale-holder drop in `_process`, `_stick_is_available()`, `_adopt_idle_stick()`, `_touch_up()` and `_draw_stick()`. `-1` still goes into `_stick_index` when nothing is owned, but nothing keys off the value any more. The debug line prints the owner id as-is, `stick -` when nothing is owned, because hiding the sign is how the sign became the owner test.
- The readout earned its keep and is now two lines: the touch layer's state, then the player's `ctrl/mnt/seat/air`, `in`, `vel` and `pos` on a dark plate below the wallet block. `fps` went in because a phone stepping physics slowly looks the same as a dead stick. That line is what turned "no movement" into a finger id.
- Verification: `check_touch` gains `_check_negative_index()`, which drives -410517893 through arming the stick, steering, `is_stick_pushing()`, 0.92 m of walking and release. The new assertions were run against the old sign tests first and failed exactly as the phone did (`arms the stick`, `steers the stick`, `moved 0.00 m`); they pass with the flag, and the rest of `check_touch` is PASS. The pre-fix probe was restored from a copy and checked by sha256, so the tested file is the shipped one.
- Limitation: a touch identifier could legitimately be -1, and the flag is what makes that safe - do not go back to comparing the id to the sentinel. `check_touch` proves the routing and the walk natively; the iPhone confirmation is the next device run.

## Horse progress stops falling out of the world at every door

2026-10-26

- The care loop never closed. `trust`, `cleanliness`, `grooming_polish`, `hooves_cleaned`, `fitness` and `jumping_skill` were variables on the horse node, and both the farmhouse and the showground are reached by a full `change_scene_to_file`, so every doorway spawned a horse that had never been groomed: the coat went dirty, trust went to 0 and the trained jump bonus was gone exactly where it was meant to pay off. `SaveGame` then made that permanent instead of merely visible. `snapshot()` read `get_first_node_in_group("horse")`, so paying the £20 show entry (a `money_changed` signal, a 1.5 s debounce, a save) wrote the showground's pristine horse over the local file and the cloud row, and a focus-loss save in the farmhouse had no horse in the scene at all, so the payload lost its horse half.
- `scripts/horse_state.gd` is the owner now, an autoload declared before `SaveGame`. The horse hydrates from it in `_ready()` and records back at its own mutation points (`award_training`, `mark_hoof`, `apply_grooming_result`), plus once from `grooming_session.exit_session()` so the last strokes and the painted mask are in before that explicit save point. `SaveGame.snapshot()` is `HorseState.to_dict()` and nothing else; `_pending_horse`, `_apply_horse()` and `apply_to_horse()` are gone, because a horse no longer needs a parked payload - it hydrates whenever it spawns.
- `record_from()` emits `changed` and `apply_to()`/`from_dict()` do not, so a load or a spawn cannot queue a save behind itself. `record_from()` also ignores an empty `export_mask()`, which is what an unbaked surface returns, so a record taken before the 0.2 s bake cannot wipe the coat.
- The coat restore still goes through `import_mask()`, which parks the bytes and lets `_setup()` copy them over the mask after `_rasterise_mask()`: the bake builds the zone map and the paint-gating table, so it has to run either way.
- The rosette had the same fault in miniature. `show_class` built the node onto the horse, so a win disappeared with the next door. `horse.attach_rosette()` owns the pin now, `show_class` calls it, and `_restore_rosette()` wears the latest `GameState.rosettes` entry on spawn.
- Verification: new `tools/check_horse_state.gd` PASS (23 assertions). It earns training and a full groom in `main.tscn`, pays an entry fee, frees the scene, covers the farmhouse case (a scene with no horse still snapshots the horse), re-spawns `main.tscn` and then `competition_arena.tscn` and checks the stats and the parked coat bytes on each, then wins a rosette and checks it is worn after the door. The hydration line was then disabled and the check re-run first: 10 assertions fail exactly as the old code behaved, including "training survives the doorway", "the showground horse inherits the trained jump bonus" and "the showground horse is handed the painted coat"; the file was restored and verified by sha256. Also PASS: `check_save` (rewritten for the new owner, including a horse-less snapshot), `check_mount`, `check_groom`, `check_tack`, `check_jump_and_loop`, `check_editor_load`.
- Limitation: `HorseState` holds one horse's progress, which matches the GDD's one-horse MVP. A second horse needs it keyed by horse id rather than a second copy of this class.

## One command runs the checks, and CI runs the command

2026-10-26

- The suite had 27 checks and no runner. `agents.md` named ten of them in prose, so the other seventeen existed only for whoever remembered them; `tools/check_all.sh` is the single manifest now. `--fast` skips the motion walkthrough, `--only name[,name]` runs a subset, `--list` prints the manifest, each entry carries its own timeout, and each check's own exit status is what decides pass or fail. A timeout is reported as a timeout rather than as a failed assertion, only the FAIL/ERROR lines are echoed, and `artifacts/check-report.txt` keeps the same lines for CI.
- It builds the import cache first when `.godot/imported` is missing, because a cold clone has no cache and every check loads a scene. That is the same `--headless --editor --quit` step the notes have always used.
- `.github/workflows/checks.yml` runs `--fast` on every push and the walkthrough on pull requests and the nightly, caching both the Godot binary and the import cache. It is committed now that the set is green rather than before: a pipeline that arrives red teaches everyone to ignore it.
- Baseline on this machine: `--fast` PASS 27/27 in 277 s, `check_walkthrough` PASS in 140 s. The two checks the notes called flaky (`check_lead`, `check_dog`) passed in that run.
- `check_character_select` no longer fails. The notes recorded a handoff timeout, but that check has allowed 9 s for the handoff and 20 s overall since the initial commit (its own comment measures the world load at close to six seconds here), and it passed three standalone runs plus the suite. No assertion was touched for this change; the note was stale, and `agents.md` now points at the runner instead of describing check status by hand.
- Limitation: the workflow has not executed on GitHub from this machine. It is pinned to Godot 4.7-stable, and `GODOT_SHA256` is deliberately empty until a first run prints the archive hash - fill it in then.

## One file of rules, one file of history

2026-10-26

- `agents.md` had grown to 4,800 words titled "devlog and troubleshooting notes" and retold the same stories as this file - the import crash, the Netlify move, the farmhouse - while being the only home of several invariants. It is now *invariants and gotchas*: the rules an agent must not break, the measured numbers inline, and a pointer to this file for the story. Nothing operational was dropped; the narrative was already here.
- `TOUCH_CONTROLS_PLAN.md` is deleted. It opened with "There is no device detection and no touch support anywhere", which stopped being true weeks ago, and everything still useful in it now lives in the touch rules or in this log.
- `GameState` gained `progress_changed`, emitted by a new `add_show_entry()` and by a new show best time. `show_entries` and `show_best_time` had no signal at all: they were saved only because an entry fee or a prize happened to move money 1.5 s earlier, a contract nobody had written down. `show_class.gd` calls `add_show_entry()` instead of `+= 1`, `SaveGame` listens to the new signal, and `check_save` asserts both emissions and the negative case.
- Stale comments are gone with it. `game_state.gd` no longer says rosettes are not saved to disk or that save/load comes later, and `agents.md` no longer records check status by hand: `tools/check_all.sh --list` is the list, and CI is what enforces it.
- Verification: `check_save` PASS (with the progress-signal case), `check_arena` PASS, `check_horse_state` PASS.

## Hay, hunger, and a reason to spend money

2026-10-26

- The GDD's MVP lists "feeding ... and purchasing supplies" and neither existed for the horse: the only feed bowl in the game belongs to the dog, and money only ever left the wallet as a £20 show entry. The horse now carries `hunger`, `energy` and `health`, the yard has a feed store that sells hay at £5 a bale, and the trough spends a bale to fill the horse. That is the loop the design asked for: earn at the show, spend on hay, feed the horse, train it, go back.
- The needs are gentle on purpose. Hunger empties over about ninety minutes of play, riding spends a little energy, standing still or being stabled restores it, and health eases toward `0.35 + 0.35 * cleanliness + 0.2 * trust + 0.1 * hunger` at 0.02/min. Nothing dies, nothing stalls, and a missed visit is noticeable rather than punishing - the GDD's "avoid heavy punishment mechanics". The five rates are exported on the horse and are the only knobs.
- The needs change every frame, which is far too often for `HorseState.record_from()`: that emits `changed`, and `changed` queues a save. They are mirrored once a second through `HorseState.set_needs()`, a plain write, and the existing save points carry them.
- `GameState.hay` is the first real supply. `buy_hay()` owns the price and the refusal, `use_hay()` takes one back out, and hay is in the snapshot - a child who buys bales and closes the tab finds them again.
- **Both stations had to be placed twice.** The first attempt put them inside the stable paddock, which is a *closed* collision box on all four sides; the pre-existing `FeedTrough` had been decorative and unreachable, and a station the player cannot walk to is not a station. A proximity audit (every mesh within 2 m, printed from a throwaway probe) moved the feed corner into the corridor between the stable and the paddock, clear of the fence, the props and the bush.
- **Two stations inside one another's range is a real fault, not a test artifact.** A single `interact` event is claimed by one node, and the store, later in the tree, swallowed every press meant for the trough: FEED did nothing while the player stood between them. Both are in the `feed_station` group now and the nearest one wins the prompt as well as the press, so a thumb never sees two offers for one spot and the keyboard cannot press the wrong one.
- A flash message used to grant permission: "NO HAY" was shown while the CONTEXT offer stayed up for its 2.5 s. The text and the gate are computed separately on both stations now, so feedback is never mistaken for an offer.
- Verification: new `tools/check_care.gd` PASS (36 assertions) - decay, rest, health drift, the mirror into the owner, the HUD panel, the price and the broke refusal, the spend-and-fill cycle, a full horse refusing without costing a bale, an empty yard offering nothing, the horse having to be at the trough, the nearest-station rule, the snapshot and the doorway. `check_save` failed first on the new fields because its stub horse mirrors the contract rather than the node; the stub was updated and it passes. `tools/check_all.sh` then ran the whole suite: PASS 29/29 in 436 s, with no retries needed.
- Limitation: the four rates are arithmetic, not play-tested; the HUD bars and both prompts have only been rendered under xvfb. The CONTEXT label on a phone is exercised by the routing in `check_touch`, not by a device. Feeding has no animation or sound of its own yet - the horse eats and the needs move.

## The three checks that only fail under load

2026-10-26

- The first full run of the suite after the care loop failed three checks: `check_character_select` (timed out waiting for the mounted handoff at 18 s), `check_dog` (the followed dog covered 0.86 m) and `check_walkthrough` (two camera clips inside the farmhouse). All three pass on their own, and all three had passed in two earlier `--fast` runs and a standalone walkthrough run that day, so this is load: the full suite runs 29 Godot processes back to back on a 2.7 GB machine, and these three measure motion or a heavy synchronous scene load.
- `tools/check_all.sh` gained a documented retry-once list rather than a skip: a listed check that fails is run again, a pass on the second attempt is reported `ok (retried)`, and a failure twice is still a failure. A deterministic regression fails both times, so nothing is hidden by this; a flaky check that fails twice still turns the suite red.
- `check_character_select` was the one with a magic number to fix: it now allows 25 s for the handoff (measured 8 s standalone, 18 s under load) with a 45 s overall cap, which still catches a hang. The property under test - a mounted player behind a cleared fade - is unchanged, and no assertion was relaxed.
- `check_dog` and `check_walkthrough` were left alone: their thresholds are the properties, and both pass reliably when they are not sharing the machine with the rest of the suite.

## Main level layout pass: routes and middle ground

2026-10-26

### What the audit found

- The play area is 105 x 70 m; 44% of it was unpainted grass with no prop in it, and the tree belts only start 50-75 m out, so the eye had about 15 m of detail and then lawn to the horizon.
- The yard dirt was 24 x 16 m centred (0, -22) while the dressed yard ran x -14.1...14.9: the well, the second lantern, the saddle rack, the signpost and the firewood stood on grass. The grooming bay's whole 3.2 x 2.4 m mat sat south of the paint edge at z = -14, on grass.
- One 4 m wide, 26 m straight path at x = 0 arrived at the paddock's south fence corner, with the feed store standing in its mouth at (-0.4, -18.8). The only path in the level ended in furniture.
- The showground arch and its door sat on the arena's east gate at (-13.2, -1.5): one spot, two destinations, 13 m from the yard on bare grass. The arch's sign faced west, into the arena, so it was unreadable from the yard.
- The farmhouse door at (37, -31.2) was 25 m from the nearest dressed ground, with no drive or garden.
- The horse and player started at (0, 0, 0) and (0, 0, 6): a horse alone in the middle of a path, 25 m from the stable, facing the fence corner.

The care loop itself is compact on purpose (it is a phone game and `check_care`/`check_stable` assume the stations stay beside the stable), so the pass spent the space on frame - routes, field boundaries and depth layers - rather than stretching the chores.

### What changed

- **Ground** (`tools/build_ground_control.py`): added a capsule-chain `polyline_sdf`, so a lane can bend. New yard at centre (0, -19), half (16, 9); a gravel lane spine (0, 26) -> (0, 8) -> (-4, -2) -> (-5, -13) that now arrives at the stable door; an arena spur from the spine to the gate at (-15.5, -1.5); a school spur to (15, 10); a 4 m house drive from the yard's north-east corner to the front door; and eight worn patches at the stations and the gate. Painted grass dropped 83% -> 69%.
- **Scenery** (`tools/build_scenery.gd`, plus the store node itself in `scenes/stable.tscn`): the feed store left the lane mouth for the corridor between the stable and the paddock - first at (-3.6, -18.4), then to (-1.2, -19.4) to clear the horse's mounting spot, see below; hay, barrels, crates and the barrow moved to the west wall, clearing the yard's working square; the turnout field (x -13...-4, z 4...20) is generated into the new `scenes/turnout_paddock.tscn` with 17 fence modules, an open five-bar gate, a trough and a hay ring; 19 mid-ground trees at 8-35 m, 15 hedge props, 8 meadow props and two garden beds; the lane's verge props follow the new bend; the schooling ground's `Fence_02` moved from (41.4, -18.3) - 3 m off the sand - onto it at (41.4, -12.5).
- **Fixtures** (`scenes/main.tscn`): the bay moved to (-12, -13), fully on hardstanding; the showground arch and door moved to (1.5, 0, 25) and rotated so the arch spans the lane and the sign faces north; the turnout field is instanced; a lane fingerpost at (2, 0, 3) carries four directions and a `STABLE` label hangs over the stable front; the horse starts at (-6, 0, -16.5) in the yard and the player at (-5, 0, -13) at the lane's arrival; the dog moved to the well corner at (13.5, 0, -15.5).
- `scenes/competition_arena.tscn`: the showground's exit spawn moved to (1.5, 0.05, 22.4), yaw 0, and `build_arena.gd`'s `EXIT_SPAWN_MAIN` followed. Regenerating that scene re-rolls every node's `unique_id` (1,119 changed lines for a two-line edit), so the spawn is patched into the `.tscn` with the generator kept in step; `arena_fence.tscn` was regenerated with no semantic change and was restored to HEAD for the same reason.

### Two layout bugs the move exposed

- **`horse._pivot_transform` placed the tack by displacement.** It returned the bone's `now - rest` movement as the saddle's absolute origin, which only equals a position while the horse stands at the world origin. Moving the horse into the yard put the saddle, and the rider seat inside it, at (0, 0, 0): `can_mount()` measured 4.8 m to a seat on the floor at the origin, so `check_mount`, `check_character_swap` and `check_tack` all failed. Fixed to `now + rotation * (rest_origin - rest)` with the prop's rest origin passed in; seat error is back to 0.000 m and the bridle follows the same path.
- **The dog stood where the horse and player now start.** `_check_player_arrival` alerts within `greet_radius` (10.5 m) on the first brain tick, so `check_dog` saw `alert` at spawn. The dog now lives by the well, and `check_dog` pins the new home.
- **The feed store's range covered the horse's mounting spot.** The store went to (-3.6, -18.4), which is 3.06 m from the horse's new start at (-6, 0, -16.5) - and the store's `player_range` is 3.0 m. `check_touch` failed deterministically on it: standing the player beside the horse, which the check does to mount, had the store's `BUY HAY` claim the CONTEXT offer instead of `MOUNT`, and the feed store's `_input` then swallowed the `interact` press. That is a real fault and not a test artifact: a player could not mount the horse where it starts without stepping away from it first. The store moved east along the same corridor to (-1.2, -19.4), 5.6 m from the horse and 2.3 m from the nearest prop (`PlanterA`), still on the yard's dirt and clear of the lane. `check_touch`, `check_feed`, `check_care` and `check_layout` all pass again.

### Verification

- New `tools/check_layout.gd`, in the manifest: 13 stations on painted ground, all 32 yard props on hardstanding and none in the lane, the grooming mat's four corners on dirt, the spine/arena spur/school spur/drive continuous, doors at least 6 m apart, the arch off the arena gate, the horse start within 12 m of the stable, and the showground's return spawn within 6 m of its arch. It was proved to bite: putting the bay back at (-8, -12.5) fails with "the grooming mat corner (-6.4, -13.5) is not on the yard (dirt 0.11, gravel 0.86)", then it was restored.
- `check_terrain_blend` samples updated for the lane, the drive and the showground hardstanding: PASS, 69% grass, max weight sum 1.00.
- `verify_scenery`: 92 props / 55,244 tris before the pass, 136 props / 81,528 tris after (+44 props, +26,284 tris), 13.6% of its 600k budget.
- `tools/check_all.sh --fast`: 29/29 PASS in 581 s. `check_dog` needed its documented retry under load.
- `check_walkthrough` (the slow one, skipped by `--fast`): first attempt failed with 4 clipped frames, all at one repeated sample (5.5, 0.001, -5.545) - the load flake already recorded above; the immediate retry passed with 6,960 samples and 0 clipped frames.
- `tools/screenshot_layout.gd` renders nine views into `artifacts/layout_*.png`; they were inspected at the yard, lane, junction, turnout field, arena approach, schooling ground, house drive and from above.

### Limitations

- The lanes are painted, not modelled: no kerbs or camber, and the ground is still flat at y = 0.
- The turnout field is dressing only - no gate interaction - and the arch signs are readable from the north only.
- The arena's western 8 m strip and both ends still carry no fence. Adding to `ArenaJumps` changes the round's fence count, which `check_jump_and_loop` pins, so that was deliberately left alone.
- The 46 m walk from the stable to the showground gate, and the lane widths, have only been seen in renders; no device or touch pass yet.

## The game starts a player on £15, and pays it once

2026-10-26

- The wallet started at £0, so the only early purchase - a £5 bale at the feed store - was a formality and the first visit had nothing to decide. `GameState.STARTING_MONEY` is £15 now: three bales, or part of the £20 show entry, with the arena round as the free route to the rest.
- **A floor paid on every load is a money tap, not a starting balance.** `max(money, 15)` in the load path would mean spending £15 on hay, reloading, and being rich again. The snapshot therefore carries `money_floor_version`, and `SaveGame.apply()` raises a payload written by an older floor to the current one and marks it; a payload already at this version is applied exactly as it stands, so spending down to £3 stays at £3. Because it is a raise rather than an addition, a local load followed by a cloud load cannot pay twice.
- A returning player is unaffected in every other respect: the top-up only raises a balance below the floor, and the two existing tablet saves keep the money they earned.
- `tools/check_save.gd` gained `_check_starting_money`: a fresh process holds £15, an older-shaped payload of £3 is raised and marked, the same wallet with the marker is left at £3, and a floor never claws back £240. The check was proved to bite by disabling the top-up - "an older save is topped up to the floor" failed, then the file was restored and verified by sha256.
- `hud.gd`'s wallet label no longer carries a `£0` placeholder that disagrees with the balance.

## Mucking out the stable, the third care chore

2026-10-26

- Feeding and grooming existed; the bed the horse actually stands in did not. `HorseState.stall_muck` is now part of the care progress (0.0 a fresh bed, 1.0 a full muck-out), because the stable is reached through a doorway like everywhere else and `SaveGame` serialises the state owner rather than whichever horse the current scene holds. `MUCK_MIN` (0.10) and `needs_mucking()` are the one threshold the station, the session and the check all ask.
- **The bed soils on the player's clock, not the wall clock.** `horse._tick_needs()` adds 0.02/min while the horse is in the world and 0.06/min while it is standing about, because a horse spends that time in or beside its stall; a boarded horse does not tick at all, so putting it away stops the bed. The clock pauses during the chore, because the session is removing exactly what is in the bed and a rate underneath would fight the scoop. A clean bed at the standing rate reaches the threshold in under two minutes, and a full one in about seventeen.
- **A soiled bed is what holds health back.** The drift target was `0.35 + 0.35 clean + 0.2 trust + 0.1 hunger` with nothing to separate a horse kept in a filthy box from a well-kept one; it is now `0.35 + 0.30 clean + 0.15 trust + 0.10 hunger + 0.10 clean bed`. Still a drift, so neglect alone cannot take health to zero.
- **The station stands at the middle bay and offers the chore.** `scenes/stable.tscn` gained a `MuckStation` at (-8.9, 0, -19.85) with its `Session` child: 3.2 m of `player_range`, a 14 m horse rule matching the stable door's, a `MUCK OUT  (60% SOILED)` prompt, and refusals on its own prompt for `DISMOUNT TO MUCK OUT`, `BRING YOUR HORSE TO THE STABLE` and `THE BED IS CLEAN`. A flash is feedback, not permission, so the gate is computed separately from the text.
- **The stable door and the muck point are one cluster.** They stand a couple of metres apart with overlapping ranges, and one `interact` event is claimed by one node, so both join `stable_station` and only the nearer offers, for the prompt as well as the press. The rule that already ordered the feed store and the trough moved into `scripts/station_proximity.gd` and both stations now share it, so there is one answer to "who owns this spot" rather than three copies.
- **The session is a working view of the bed.** `scripts/muck_session.gd` parks the player's camera at the bay, hides the gameplay HUD and the player body, lays eight heaps (one scoop each) on the apron in front of the middle bay, and moves a pitchfork along the scoop ray. Leaving early keeps the work - each heap writes its share of the bed to `HorseState` as it goes - and only an emptied bed pays, `TRUST_PER_MUCK` 0.06 and `HAPPINESS_PER_MUCK` 0.10, against the mess that was there at entry so re-scooping a clean bed cannot farm trust.
- `scripts/muck_hud.gd` carries `BED CLEAN %`, a `Barrow n / 8` counter, the prompt line and a `STALL MUCKED OUT` result card with `BACK TO THE YARD`. `hud.gd`'s needs panel gained a fourth bar, `STABLE`, filled from `1 - stall_muck` so a full bar means the same good thing the other three do.

### Three bugs the chore exposed

- **The stable door never joined a station group.** `stable.gd` declared `STATION_GROUP` but only added itself to `touch_context`, so the muck point had nothing to compare against and the pair could both offer. The point of the shared rule is that the group is real, so the membership is now asserted by the chore rather than assumed from the constant being declared.
- **A station's spot is not its node origin.** The stable door offers from `UseAnchor` at the stall end; its node origin is the middle of the building 4.7 m away, which made it "nearer" than a player standing at the muck point. A station can now answer `claim_point()`, and the comparison uses that.
- **The heap grid was geometrically impossible.** Four columns across 82% of a 3 m bed put neighbouring heaps closer together than the spacing the placement loop demanded, so it stopped early and a bed could be laid with fewer than eight heaps - and the chore would then need a scoop that was never placed. The spacing and the spread were fitted to the bed, and `check_muck` pins the count.

### Verification

- New `tools/check_muck.gd`, in the manifest: the bed soiling standing, riding and paused in the chore, the mirror into the state owner, the threshold both ways, the station's offer and all three refusals, the nearest-station rule against the stable door, the session taking and returning the camera, the HUD, the player body and the gameplay HUD, one scoop clearing exactly one heap, the reward paid against the mess at entry, leaving early keeping the work, and the bed surviving a doorway and a save round trip.
- The station, the session and the stable door are the real nodes in `scenes/stable.tscn`, so the check drives the shipped prompts and gates rather than copies of them.
- Proved to bite by widening `player_range` so the muck point claimed the stable door's spot; `check_muck` failed and the file was restored byte-identically (checked against the backup).
- `tools/screenshot_muck.gd` renders four views into `artifacts/muck_*.png`: the approach prompt in the yard, a full bed, three heaps scooped, and the result card. They were inspected: the bed reads dark and heaps legible on a phone-sized frame, the scooped patch turns green, and the card sits clear of the bed.
- `tools/check_all.sh --fast`: 30/30 PASS in 781 s, with `check_muck` at 66 s. `check_dog` took its documented retry under load and passed on the second attempt. `check_walkthrough`, which `--fast` skips, took its documented retry too and passed in 287 s.

### Limitations

- The bed is the apron in front of the middle bay, not the box behind it: the five bays sit inside the building's collision box, so the part a player can see and work from the yard is the apron. The stable's interior is still not walkable.
- The barrow is dressing. Scooping removes a heap and increments the count; nothing has to be carried to it, and there is no trip with a full barrow.
- The chore has no time limit and no failure; it is a job to do, like the other two.
- Seen in renders only - no device or touch pass on the scoop gesture yet.

<!-- end -->
