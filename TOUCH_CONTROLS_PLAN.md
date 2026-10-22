# Touch Controls Plan (mobile / tablet)

Goal: the game is playable end-to-end on a tablet with touch only. Keyboard and
mouse stay fully functional for desktop development. Prompts adapt to the
active input mode.

## Current state

There is no device detection and no touch support anywhere:

- `project.godot` input map is keyboard only (WASD, E, F, G, Q, R, Space, Shift).
- Camera look uses pointer lock (`player_controller.gd:295`, `_notification`).
- All interaction consumers gate on `_unhandled_input(event.is_action_pressed(...))`.
- Grooming uses raw mouse button/motion/wheel (`grooming_session.gd:439-450`, `:395`).
- Prompts are hardcoded key strings:
  - `hud.gd:125`
  - `character_select.gd:415`, `:430`
  - `grooming_hud.gd:262`
  - `dog.gd:138`
  - `grooming_bay.gd:109`
  - `horse.gd:142-148`
  - `stable.gd:80-86`
  - `jump_obstacle.gd:186`

`devlog.md:228` already notes "no gamepad or touch bindings yet".

## Design decisions

- **Movement:** floating analog joystick (left thumb).
- **Run:** no run button and no toggle. Pushing the stick past a run threshold
  (`~0.80` of radius, hysteresis off at `~0.70`) holds the `run` action, so the
  character trots/canters and the horse gaits faster. Back inside the walk
  zone, `run` releases. The stick visually shows the run zone (outer ring
  colour shifts when engaged).
- **Look:** drag on the right half of the screen, not on a button. Feeds the
  same look path as the mouse, so mounted steering works unchanged.
- **Actions:** dynamic context button plus jump, lead, reset (see below).
- **Keyboard:** always live in both modes for development. F3 toggles touch
  mode in debug builds; `GROOM_TOUCH=1/0` forces it.

## 1. Device profile — new autoload `scripts/device.gd`

- `is_touch` resolution order:
  1. `GROOM_TOUCH` env override (`1` / `0`)
  2. `DisplayServer.is_touchscreen_available()`
  3. `OS.has_feature("mobile")`
- `mode_changed` signal so HUD/prompt text can refresh.
- Prompt helpers, e.g.:
  - `Device.key("interact")` -> `"E"` / `"TAP"`
  - `Device.prompt("groom")` -> `"G  ·  GROOM"` / `"TAP  ·  GROOM"`
  - `Device.pick(keyboard_text, touch_text)` for hint lines.
- Replace all prompt sites listed above. Keyboard text must stay
  byte-identical so `check_groom`, `check_lead`, `check_stable`, `check_dog`
  keep passing on desktop.

## 2. Touch layer — new autoload `scripts/touch_controls.gd`

- `CanvasLayer`, layer `30` (HUD is `10`, `SceneFade` is `1000`).
- Handles raw `InputEventScreenTouch` / `InputEventScreenDrag` directly for
  multitouch. Godot's mouse emulation only follows the first finger, so the
  layer must do its own finger tracking.
- Visuals use `MOUSE_FILTER_IGNORE`; real `Button` UI (tool row, DONE, MASK,
  character cards) keeps working through Godot's touch->mouse emulation and
  consumes those touches before they reach this layer.
- Left thumb joystick:
  - floating base, recenters to the touch-down point
  - analog strength drives `move_*` actions
  - `run` engages in the outer zone with hysteresis (see decisions)
- Right thumb look:
  - any right-half drag that did not start on a button adds a look delta
  - player consumes it in `_process` and calls the existing `_look()` path
- Action cluster bottom-right:
  - **CONTEXT** (large): label follows proximity and swaps between
    `MOUNT` / `DISMOUNT` / `USE` / `GROOM` / `PET` / `RAISE`
  - **JUMP**
  - **LEAD**
  - **RESET**
  - Buttons dispatch `InputEventAction` via `Input.parse_input_event`
    (press + release), so existing `_unhandled_input` handlers work with no
    gameplay refactor.
- Modes: `ride` (stick + cluster), `groom` (gestures only), `select` (no
  cluster). Set from `player_controller._ready`, `grooming_session.enter/exit`,
  `character_select._ready`.
- Pointer lock: `_capture_mouse()` early-outs, the focus notification is
  ignored, mouse mode stays `VISIBLE` in touch mode.
- Safe-area insets from `DisplayServer.get_display_safe_area()`.
- Defaults: dynamic CONTEXT button, landscape-only layout.

## 3. Character select — `scripts/character_select.gd`

- Swipe the stage to spin the turntable.
- Tap cards and "Ride out" (already Buttons; work via emulated mouse).
- Hint swaps to "Swipe turn · tap a rider · tap Ride out"; "DRAG TO TURN" ->
  "SWIPE TO TURN".

## 4. Grooming — `grooming_session.gd`, `grooming_hud.gd`

- One-finger drag over the horse paints (use `TouchInput.paint_pos` instead of
  `get_viewport().get_mouse_position()`).
- Two-finger drag orbits; pinch zooms (drives `_distance`).
- Taps on tool row / MASK / DONE keep working; enlarge tool buttons to at
  least 56 px touch targets.
- Touch hint line: "Drag brush · Two-finger orbit · Pinch zoom · Tap tool ·
  Done".
- Ignore mouse paint/orbit entirely in touch mode to avoid double input from
  emulated mouse events.

## 5. Project settings

- `display/window/handheld/orientation` = sensor landscape.
- Base viewport 1280x720 (stretch already `canvas_items` / `expand`).
- Make `input_devices/pointing/emulate_mouse_from_touch=true` explicit (needed
  for existing Buttons); keep `emulate_touch_from_mouse=false`.
- No new touch bindings needed in the input map.

## 6. Verification

- New `tools/check_touch.gd` (SceneTree, headless):
  - forced-touch detection; prompts read TAP in touch mode and E in keyboard
    mode
  - stick moves the player on foot and mounted; pushing into the outer zone
    engages `run`, returning to the inner zone releases it
  - look drag rotates camera and mounted heading
  - CONTEXT mounts/dismounts and triggers stable, groom, dog and jump
  - grooming gestures paint/orbit/zoom; tap changes tool
  - keyboard still works while touch mode is on
- New `tools/screenshot_touch.gd` renders `artifacts/touch_ride.png`,
  `touch_groom.png`, `touch_select.png` at 1280x800.
- Re-run the existing suite: `check_character_select`, `check_mount`,
  `check_lead`, `check_stable`, `check_groom`, `check_dog`,
  `check_jump_and_loop`, `check_editor_load`.
- Devlog entry plus an `agents.md` note on `GROOM_TOUCH` and F3.

## Implementation order

1. `Device` autoload + prompt swaps + project settings + F3/`GROOM_TOUCH`.
2. `TouchControls` autoload: joystick (with run zone), look, context cluster,
   event injection, mouse-capture bypass.
3. Character select touch.
4. Grooming gestures and larger touch targets.
5. Tests, screenshots, docs.
