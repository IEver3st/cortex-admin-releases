# Changelog

## 1.3.0 (2026-11-01)

First public release.

### Added
- Admin menu with player, vehicle, world, weapon, teleport, appearance, developer and server tools, in three interface styles: Panel, Classic and vMenu mode.
- vMenu mode: vMenu's menu layout and controls in the Cortex style, running on Cortex's own actions and permissions. The `compat/vMenu` stand-in replaces an existing vMenu install and keeps its key bindings, bans and config files.
- Qbox tools (31 actions) when `qbx_core` is running: items, money, jobs and gangs, needs, licenses, owned vehicles and saving a look as the character's appearance.
- Players console for acting on online players: go to, bring, spectate, freeze, revive, message, kick and ban.
- Character Studio, Vehicle Studio, Live Vehicle Tuning, photo mode and freecam.
- vMenu mode's Generate Appearance offers the Character Studio's choices: style, palette, clothing types, and face, hair and makeup for a full character.
- One server-owned clock and weather, which steps aside automatically while a listed weather resource is running.
- `/dv`, `/delveh` and `/deleteveh`, checked on the server for range, routing bucket and occupants. Public by default; set `Config.Dv.RequirePermission = true` to restrict it.
- ACE permissions per tab and per action. vMenu's ACE and `vmenu_*` convar names keep working.
- Server exports `CanOpenMenu` and `CanDeleteVehicle`, so other resources can ask the same permission policy the menu uses.
- A startup check of `shared/config.lua`: a wrong type or out-of-range value prints one console line naming the key and falls back to a safe value.
- The Addon vehicle list is scanned in the background and updates when a vehicle pack restarts.
