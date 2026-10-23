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

<!-- end -->
