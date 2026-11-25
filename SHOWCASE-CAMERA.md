# Photo mode

A copy of vMenu's **Freecam²** (the GSD vMenu fork): the same controls and behaviour, shown with Cortex's bottom-right camera controls instead of GTA's instructional buttons. Toggle it with **U**, `/showcase`, or **Dev > Photo mode**.

| Action | Key |
| --- | --- |
| Toggle photo mode | U (FiveM key setting *Cortex Admin: toggle photo mode*, listed for players with `dev.photoMode`; the default is `Config.ShowcaseCamera.toggleKey`) |
| Forward / back | W / S (along where you look, including up/down) |
| Left / right | A / D |
| Look | Mouse |
| Roll | E / Q (±90°) |
| Up / down | Space / Ctrl |
| Zoom | ↑ / ↓ |
| Filter | ← / → (cycles, wraps) |
| Reset filter | R |
| Attach to the vehicle or person in view / detach | Left mouse / right mouse |
| Speed | Scroll (0.5–20 in steps of 0.5, default 2); hold Shift for ×2 |
| Hide camera controls for this session | V |
| Take photo (saved to the pause-menu gallery) | Enter |

The bottom-right controls leave out movement keys (WASD, Space/Ctrl, mouse) and show filter and speed first. Enter saves a gallery photo after hiding the camera controls. The overlay never takes mouse or keyboard focus.

## Behaviour (as in vMenu)

- The camera starts at your character, facing your heading, with a 50° field of view. The radar is hidden. The world keeps running and your character stays where it is. All your other controls are disabled while it's on, except chat (T).
- Movement uses vMenu's per-frame steps, scaled to your frame rate so the speed is the same at any fps.
- **Attaching:** the position follows the entity and the view stays pointed where you left it. WASD still moves the camera relative to the entity.
- **Filters:** the list is vMenu's, in the same order: black & white, security cam, the 25 film looks, film noir, and Snapmatic. Filters this client doesn't have are skipped. `Config.ShowcaseCamera.filters` adds more.
- **Fresh start:** every time you open it, speed is back to 2.0 and the filter is back to None. (vMenu remembers both; this intentionally doesn't.)

## Differences from vMenu

- **Screen:** the cortex-hud HUD is hidden along with the radar.
- **Exit:** the previous timecycle modifier (for example, a weather script's) is restored instead of being cleared.
- **Closes automatically:** photo mode also closes if you open the admin menu, die, lose permission, another script takes the camera, or the resource stops.
- **Permission:** the action is `dev.photoMode`. `cortex-admin.dev` grants the Dev tab, and `cortex-admin.all` grants everything.

## Validation and runtime handoff

`tests/showcase_camera_spec.lua` checks the vMenu behaviour with mocked natives:

- start position and field of view;
- per-frame movement, strafing and up/down;
- Shift speed, mouse look scaling, roll limits and zoom steps;
- scroll speed limits;
- filter cycling, wrapping, skipping and reset;
- attach, follow, move and detach;
- toggling the strip, and the photo being taken with the strip hidden;
- restoring everything on exit, and resetting speed, filter and view when you re-enter;
- closing when the menu opens, on death, and on resource stop.

None of this is in-game evidence. To check in game: toggle with U; fly, roll, zoom, cycle filters, attach to a moving car, and take a photo (check the gallery). Then compare the feel side by side with vMenu's Freecam² at the same speed.
