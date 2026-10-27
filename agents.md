# Groom — invariants and gotchas

Rules an agent must not break, and the operational facts that are expensive to
rediscover. This file is not a log: what happened, why, and what was measured
lives in [devlog.md](./devlog.md) and in `git log`. If a rule here needs its
story, follow the devlog entry it names.

## The machine

Godot 4.7 (GL Compatibility) in a Crostini container on a Chromebook: Wayland
via XWayland, Intel UHD "Jasper Lake" through VirGL, ~2.7 GB RAM, no swap, and
**no real VRAM**. Two consequences:

- Textures must stay **Lossless** with `detect_3d/compress_to=0`, or the editor
  segfaults on a cold import. See below.
- The browser here has **no WebGL2**, so a local browser run can only prove the
  page and assets load. Rendering and touch feel have to be checked on the iPad
  or another GPU-backed browser.

## Textures and imports

- `Models/lowpoly_trees_0.png`, `Models/low_poly_nature_assets_1_0.jpg` and
  `Models/horse_riggedgame_ready_0.png` stay on `compress/mode=0`. They were the
  three that crashed the editor on this machine.
- Every `.import` file keeps `detect_3d/compress_to=0`, so neither a re-import
  nor a 3D probe can flip a texture into VRAM compression later.
- Normal-map detection may set `compress/normal_map=1`; that is fine and is not
  the crash. Such a texture still has to be `compress/mode=0` with
  `detect_3d/compress_to=0`.
- `tools/check_editor_load.gd` is the guard. It loads every scene under
  `res://scenes` (the list drifted when it was hand-written) and fails on a
  VRAM-compressed or `detect_3d`-enabled texture, including the seven interior
  textures `INTERIOR_TEXTURES` names. Do not widen it to sweep all of
  `Models/interior/`; measure first.
- The `ERROR: Attempting to parent and popup a dialog that already has a parent`
  lines during a reimport are Godot [#77426](https://github.com/godotengine/godot/issues/77426)
  and come from the editor's import dialog. This project has no such code.
- A cold checkout needs `--headless --editor --quit` to build the cache before
  any scene loads; `tools/check_all.sh` does it automatically.
- The web export re-encodes textures for ETC2 on purpose (`export_web_mobile.py`),
  so the mobile build and the desktop import settings are allowed to differ.

## Touch input

The touch layer is `scripts/touch_controls.gd`; `scripts/device.gd` picks the
mode (`GROOM_TOUCH=1|0`, `?touch=1|0`, F3 in debug builds).

- **Every player-facing interaction needs a touch path in the same change:** a
  CONTEXT offer (`touch_context()` on a node in the `touch_context` group) or a
  gesture, plus a `Device.pick(keyboard, touch)` prompt. Never hardcode a key
  name in prompt text.
- `TouchControls` reads raw fingers, so do not route play-surface touch through
  `Button`s: emulated mouse only follows the first finger.
- **Ownership is `_stick_owned`, never the sign of `_stick_index`.** iOS touch
  ids climb and overflow into negative int32; a real iPhone reported
  `-410517893` and every `_stick_index < 0` test read a live stick as absent.
- A stick holder that has gone quiet is claimable (`STICK_STALE_MS`, 250 ms):
  iOS Safari cancels a touch instead of ending it, so `_touch_up` never runs.
  Only the finger that owns the stick may release it.
- **A pushed stick owns the movement frame.** `player.steer_yaw()` returns the
  yaw captured at the push, and `horse._ride()` maps through the same frame.
  Do not replace it with a live `transform.basis`; the right thumb starts
  re-aiming the walk again.
- **The root carries the view; the model carries the facing.** `rotation.y` is
  the camera yaw and what every `tools/` aim means; `_body_yaw` eases toward
  travel and is written as `_model_base_yaw + wrapf(_body_yaw - rotation.y, -PI, PI)`.
- **Movement is the raw input vector rotated by the steering yaw:**
  `Basis(Vector3.UP, steer_yaw()) * Vector3(input.x, 0, input.y)`. Building a
  forward vector and multiplying by `input.y` applies Godot's forward-is-`-Z`
  negation twice and swaps W and S. That inversion has been introduced once.
- Touch look runs at `LOOK_GAIN` (0.55) of the mouse rate on purpose; movement is
  camera-relative, so a 1:1 drag reads as spinning. Do not raise it toward 1.0.
- Two-finger orbit is sampled **per frame** and only zooms once the gap changes
  by more than `PINCH_TRIGGER` (10%). Below that it is pure orbit.
- Touch grooming cleans **above** the thumb: `TOUCH_BRUSH_OFFSET` (0, -64) lifts
  the paint point and its disk, falling back to the finger when the lifted ray
  misses. The hoof pick stays on the finger. Touch painting must not consult
  `_hud.is_pointer_over_ui()`.
- The grooming session owns the player body (`set_model_hidden`), and
  `_update_model_visibility()` must keep its early return or the camera rule
  turns the body back on a frame later.
- `?touchdebug=1` (`GROOM_TOUCH_DEBUG=1` locally) draws two lines: the layer's
  state, then the player's `ctrl/mnt/seat/air`, `in`, `vel`, `pos`. `in` zero is
  routing, `in` set with `vel` zero is a blocked body, low `fps` is the phone not
  stepping physics. It is the only way to read a phone with no console.

## Horse progress

- Progress lives in the `HorseState` autoload, never on the horse node. The horse
  sits inside a scene and every door is a full scene change, so a value kept on
  that node is lost by walking into the farmhouse or the showground; and because
  `SaveGame` used to read the horse in the current scene, a show entry fee wrote
  a pristine horse over the save.
- **The horse can be placed anywhere in a scene, so the tack must use absolute
  positions.** `_pivot_transform` places the saddle and bridle at
  `now + rotation * (rest_origin - rest)` — the bone's position plus its rotated
  rest offset. The old `(now - rest)` form was a displacement, which only equals
  an absolute position while the horse stands at the world origin; moving the
  horse into the yard put the saddle, and the rider seat inside it, at (0, 0, 0),
  which silently broke `can_mount()`'s seat distance and the live reins. Do not
  reintroduce a rest-relative origin there.
- `horse._ready()` hydrates from the autoload; the horse records back at its own
  mutation points (`award_training`, `mark_hoof`, `apply_grooming_result`) plus
  `grooming_session.exit_session()`.
- `record_from()` emits `changed`; `apply_to()` and `from_dict()` must not, or a
  load or a spawn queues another save behind itself. `record_from()` ignores an
  empty `export_mask()`, because that is what an unbaked surface returns.
- The coat bake still runs on every spawn even when a mask is restored: it builds
  the zone map and the paint-gating table the brush needs.
- `tools/check_horse_state.gd` walks main -> farmhouse case -> main -> showground
  and asserts the stats, the coat bytes and the rosette survive.

## The care loop

- The horse's daily needs (`hunger`, `energy`, `health`) belong to
  `HorseState` and are mirrored once a second by `horse._tick_needs()` through
  `HorseState.set_needs()`. That call is a plain write and must stay one: it runs
  every second, and `record_from()` emits `changed`, which queues a save.
- The rates are exported on the horse: `hunger_per_minute`, the two energy
  rates, `health_per_minute`, `hay_feed_gain`. Nothing here is a fail state - the
  horse works at zero and health only drifts toward what the care adds up to.
- Hay is `GameState.hay`. `buy_hay()` owns the £5 price and the refusal, and
  `use_hay()` takes one back; the trough lets the horse eat first and spends the
  bale afterwards, so a refusal never costs one.- **A station cluster shares one "who owns this spot" rule.**
  `scripts/station_proximity.gd` holds it; every station that can overlap another
  joins that cluster's group (`feed_station`, `stable_station`), and only the
  nearest offers - for the prompt as well as the press. One `interact` event is
  claimed by one node, so without this the later node in the tree swallowed the
  press and the nearer station's action silently did nothing. The store and the
  trough need it; so do the stable door and the muck-out point.
- **A station's spot is not its node origin.** The stable door offers from
  `UseAnchor`, 4.7 m from the middle of the building. A station whose prompt
  stands at a marker answers `claim_point()`, and the proximity rule uses that;
  adding the node to the group is a real line in `_ready()`, not just declaring
  the constant.
- A flash message is feedback, not permission. The offer is gated separately
  from the text, so "out of hay" cannot leave a CONTEXT button on screen.
- **A station has to be somewhere the player can walk.** The stable paddock is a
  closed collision box on all four sides, and the decorative `FeedTrough` had been
  sitting inside it, unreachable. Check placement against the collision shapes,
  not against a render.
- `tools/check_care.gd` covers the needs, both stations, the refusal paths, the
  nearest-station rule and the save. `tools/check_muck.gd` covers the bed: the
  soiling rates, the threshold, the station and its refusals, the session taking
  and returning the camera and HUD, the reward, and the bed across a doorway and
  a save.
- **`stall_muck` is care progress, not scene state.** It lives in `HorseState`
  beside the needs and is mirrored by the same once-a-second tick with a plain
  write, so it survives a doorway and rides in the save. The soiling clock stops
  while the horse is boarded (`board()` freezes the tick) and while the muck
  session is running; a muck session must set `horse.mucking` or its scoops
  fight the rate.

## Money

- The wallet starts at `GameState.STARTING_MONEY` (£15: three bales, or part of a
  show entry), and the floor is **paid once per wallet, never on every load**.
  `MONEY_FLOOR_VERSION` travels in the snapshot, and `SaveGame.apply()` raises a
  payload written by an older floor and then marks it. A plain
  `max(money, STARTING_MONEY)` in the load path would be a money tap: spend down
  to £3, reload, and the wallet refills.
- `check_save` pins both directions (an older save is topped up; a marked one is
  left at £3) and was proved by disabling the top-up and watching the first
  assertion fail.

## The main level's layout

- The site is **painted, then dressed**: `tools/build_ground_control.py` owns the
  yard, the lane network, the house track and the worn patches;
  `tools/build_scenery.gd` owns the yard props, the tree belts, the hedgerows and
  the turnout field; `scenes/main.tscn` owns the fixtures and the doors.
  `tools/check_layout.gd` is the guard that keeps all three agreed, and it is in
  `tools/check_all.sh`.
- **Routes are data.** Moving a lane is a change to `LANES`/`DRIVE` in the
  generator plus the samples in `check_terrain_blend.gd`, never a nudged node.
- **A station has to stand on its own painted ground.** Sampling the control map
  at each station's world position is what caught the grooming mat hanging off the
  dirt at z = -14, and the yard props spilling 3 m onto grass at both ends.
- **No station's range may cover another station's spot, or the horse's.** The
  feed store sat 3.06 m from the horse's start with a 3.0 m `player_range`, so
  standing beside the horse to mount offered `BUY HAY` and the store swallowed
  the `interact` press. `check_touch` catches this; it is spacing, not priority -
  the CONTEXT priority list only orders offers that are legitimately in range.
- **One gate, one meaning.** The showground arch stands on the south lane at
  (1.5, 0, 25) and the arena's east gate at (-15, -1.5) is only the arena mouth.
  `check_layout.gd` fails if any two destination doors come within 6 m, and if the
  showground's return spawn drifts away from its arch.
- The dog lives by the well at (13.5, 0, -15.5), clear of the lane the player
  arrives on and of the horse's standing spot. `check_dog` pins its home and
  expects it to start `idle`; a dog inside `greet_radius` of the player start
  greets on its first brain tick.

## Camera

- Interiors carry `camera_max_boom`, `camera_pivot_height` and `camera_shoulder`
  on their root. Do not use a group: `PackedScene` drops groups added after the
  root exists, which is how the 3 m outdoor boom stayed active in the house.
- `player_controller.gd` resolves the on-foot camera with a `ShapeCast3D` sphere
  (0.28 m): direct shoulder line, then a lateral line within 35 degrees, then a
  0.45-0.95 m look-down from above the head (only while the normal boom is under
  0.90 m). A clear line reached around a blocker is stepped onto at 0.62 m before
  easing out. The body hides only below 0.58 m. Do not add a second clip path.
- `check_walkthrough` floors are 1.0 m in a room and 0.90 m backed into a corner,
  with the body visible. The 0.35 m safety clamp is a last resort, not a target.

## Scenes that are generated

- `scenes/farmhouse.tscn` is written by `godot --headless --path . --script
  res://tools/build_farmhouse.gd`. Change the plan tables at the top (rooms,
  `WINDOWS`, `DOORS`, stair constants, props, lamps), never the `.tscn`.
- Windows and doors are declared once; wall openings, frames, sills, glass and
  leaves are derived from them. The scene publishes the built `windows` and
  `doors` arrays as metadata and `check_farmhouse` reads those.
- No interior door leaves: the eight interior doorways are cased openings
  1.6-1.8 m wide with heads at 2.45 m. Do not reintroduce `interior_door.gd`.
- Props are measured, centred and dropped by `_prop`; do not nudge them by hand.
  `_prop` flattens each GLB instead of instancing it, so a prop's mesh is shared
  and a surface override cannot duplicate the mesh. Do not give furniture normal
  or ORM maps on this renderer.
- Furniture surfaces are one shared material per real material. Detail maps are
  neutral-grey and multiplied in, with `_detail_gain` compensating the mean.
- Seats and beds are `interior_spot.gd` under `Seats`; adding one means adding it
  to the generator and to `check_farmhouse`, which asserts the count.
- The stair is L-shaped and the treads are decoration over a walkable ramp. The
  controller has no step-up logic: no flight may pitch past 45 degrees and every
  ramp end must meet floor exactly. Balustrades need collision behind them.
- The front door is at z = 2.68 on the east wall with inside spawn
  `(8.35, 0.05, 2.68)`; moving either means re-checking the stair geometry.
- Doors link through `scripts/scene_door.gd`; a scene change spawn is requested
  with `GameState.request_player_spawn(position, yaw_degrees)`, never hardcoded
  in a scene.
- `tools/check_interior_cost.gd` is the speed budget: 980 mesh instances, 112k
  triangles, 115 materials, 60 textured materials, 20 textures, 20 MB of decoded
  texture memory. It is deliberately tight; raise a number in the same change
  that needs it.- `Models/interior/SOURCE.txt` records provenance (Kenney, Quaternius, Shapespark, Poly Haven, all CC0).
- `scenes/turnout_paddock.tscn` is written by `tools/build_scenery.gd`
  (`_build_turnout`). Its fence modules come from the measured arena fence, so
  the stable paddock, the arena rail and the turnout field read as one hand.
- `scenes/competition_arena.tscn` is written by `tools/build_arena.gd`, but
  regenerating re-rolls every node's `unique_id`: a spawn-only change is patched
  into the `.tscn` and the generator is updated in the same change, rather than
  re-running it (that produced 1,119 lines of id churn for a two-line edit).

## Web build and the R2 deploy

- **Only deploy when the user explicitly asks.** Never deploy or re-export as a
  side effect of another change. `tools/release.sh` is a deploy, not a
  convenience.
- The `Web` preset is single-threaded on purpose, so the host needs no COOP/COEP
  headers. Browser builds go through `tools/export_web_mobile.py`.
- Hosting is a Cloudflare R2 bucket behind `R2_HOST`. Response headers are object
  metadata written by `tools/deploy_r2.py`; there is no hosting config file.
- The two binaries are stored brotli-compressed (q9) and served with
  `Content-Encoding: br`: 84.0 MiB pck -> 42.9 MiB, 37.7 MiB wasm -> 7.6 MiB, a
  cold visit of about 50.9 MiB. Everything except the icons is `no-cache` and
  revalidated, so a device never keeps a previous pck.
- Two R2 behaviours that produce convincing false failures: the stored brotli
  representation is only served to a client advertising `Accept-Encoding: br`,
  and an unadvertised user agent is refused with `error code: 1010` and a 403.
  `--check` sends a browser UA and `Accept-Encoding: br` for that reason.
- `--check` has one expected failure on `r2.dev`: `/` answers 404 because a
  public bucket has no index document. `tools/release.sh` exits 1 while that is
  the only failure and says so. Do not swallow the status.
- Every export stamps `build <UTC>  <short hash>[+local]` into the loading
  screen and into the packed `project.godot`, and `--check` fails if the live
  page is not serving the local stamp. Read that stamp before re-testing a
  report of "the fix did not arrive". `?touchdebug=1` shows it first.
- Credentials live in `.env` (`R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_HOST`,
  `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`), git-ignored and mode 600. The tool
  reads the `R2_` names only; a run with just `AWS_*` falls through to the `cf`
  route, which cannot work. Never paste a token into a chat, an issue or a log.
- Hosts already ruled out: Netlify (paused for 503 usage on the free plan),
  Cloudflare Pages and Workers static assets (25 MiB per-file cap), Vercel Hobby
  (non-commercial, 100 MB upload cap). R2 custom domains need the zone in the
  same account as the bucket.
- Cloudflare has no hard R2 spend cap; the kill switch is deleting the bucket.
- `?touch=1` / `?touch=0` force the input mode in the browser.

## The loading screen

The branded loading screen, its art and its driver live in `tools/web_shell/`,
and `tools/export_web_mobile.py` injects them into Godot's generated
`index.html` on every export. `build/web-mobile/index.html` is generated: never
edit it, and never add a file to the export by hand.

- **The screen is `tools/web_shell/`**: `splash.html`, `splash.css`, `splash.js`
  and `art/`, with a `.gdignore` so Godot never imports it and the pck never
  carries it. Review it through `tools/web_shell/preview.html` on a local
  `python3 -m http.server`; the preview loads every file with a cache-busting
  stamp, because a plain server sends no `Cache-Control` and a heuristically
  cached file shows the previous version of what is being edited.
- **`patch_index_branding()` asserts the anchors it patches and fails the
  export.** The branded markup keeps `<div id="status-notice"></div>` because
  that is the marker `patch_index_version()` keys on, and the progress element
  keeps its stock id because the engine drives it. If Godot changes its shell
  template, update the `SHELL_*` anchors in `tools/export_web_mobile.py` and the
  verbatim stock CSS copied into `preview.html`.
- **The art is copied to the export as `branding-*.png` and must be listed in
  `tools/deploy_r2.py`'s `OBJECTS`**, or the loading screen 404s on a phone;
  `tools/check_web_shell.py` fails when the two disagree, and it is in the check
  manifest.
- The horse image is generated, not drawn: `tools/render_splash.gd` renders it
  (transparent background, camera from the horse's basis, idle clip pinned to
  1.4 s, `SPLASH_POSE`/`SPLASH_OUT` to sweep a pose) and
  `tools/prepare_splash_art.py` trims and de-halos it. Re-run both when the
  horse, the tack or the lighting changes.
- **The driver only ever reads what the engine reports.** The single injected
  line inside `onProgress` is the whole coupling; do not add a timer that moves
  the bar on its own, and do not drive the progress element by hand.

## Checks

- `tools/check_all.sh` is the single manifest: `--fast` (skips the motion
  walkthrough), `--only name[,name]`, `--list`. Every `tools/check_*.gd` belongs
  in it; add new checks there and in this file's neighbours, not in prose lists.
- An entry ending in `.py` runs under `python3` instead of Godot, for a check
  that reads the build rather than the game: `check_web_shell.py` is the one
  that does, and it skips itself (exit 0) when `build/web-mobile` does not
  exist, which is where CI runs it.
- CI (`.github/workflows/checks.yml`) runs `--fast` on every push and the
  walkthrough on pull requests and nightly. Keep that set green; do not commit a
  workflow that is red on arrival.
- **A `--script` check cannot name an autoload global** (`SaveGame.foo` is a
  compile error even though the node exists at `/root`). Resolve it by path
  (`root.get_node("SaveGame")`) and leave the variable untyped so calls stay
  dynamic. The tree is not live inside `_initialize()`, so `await process_frame`
  before touching a `get_tree()`-dependent path.
- A tool that must prove a fix should run the old code first and watch the new
  assertion fail. `check_horse_state` and `check_touch` were both written that
  way; keep restoring the tested file by checksum when you do it.
- **A new `class_name` cannot be used by a `--script` check on this machine.**
  The headless editor scan produces no global class cache entries, so the name is
  "Identifier not declared in the current scope" for every check. Helpers that
  checks must reach preload instead: `const StationProximity := preload(...)`,
  as `station_proximity.gd` explains at the top of the file.

## MCP and the editor

- The editor plugin is `addons/godot_mcp/plugin.cfg`, registered in
  `project.godot`. The `godot` MCP server (`@keeveeg/godot-mcp`) is a bridge to a
  running editor, so **the editor must be open**. `godot-headless`
  (`@coding-solo/godot-mcp`) is the fallback and has fewer tools.
- Launch with `godot --editor --path .`, not a bare `godot`.

## Commands

```bash
cd /home/chrismills029/liv/groom
godot --editor --path .                      # the editor, MCP available
tools/check_all.sh --fast                    # every check but the walkthrough
tools/check_all.sh --only check_horse_state  # one check
godot --headless --editor --quit --path .    # (re)build the import cache
tools/release.sh                             # export, brotli, upload, check (a deploy)
tools/release.sh --dry-run                   # sizes only, uploads nothing
tools/release.sh --skip-export               # publish build/web-mobile as it stands
python3 tools/deploy_r2.py --check           # assert the live host
grep -rE '^compress/mode=2' Models/          # should print nothing
python3 tools/check_web_shell.py             # the exported loading screen, and what will publish
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --resolution 2400x1600 --script res://tools/render_splash.gd   # re-render the splash horse
python3 tools/prepare_splash_art.py          # trim the splash art, after a re-render
python3 -m http.server 8765 --directory tools/web_shell   # review the loading screen
```

Screenshots for review: `tools/screenshot_farmhouse.gd` (eight views, `plan_*`
hide the storey above), `tools/screenshot_camera.gd`, `tools/screenshot_touch.gd`,
`tools/screenshot_layout.gd` (the level's routes) and `tools/screenshot_muck.gd`
(the chore: approach, full bed, part-scooped, result card).
Run them under `xvfb-run` with `--rendering-driver opengl3` and
`--resolution 1280x720`; they write to `artifacts/`, which is git-ignored.
