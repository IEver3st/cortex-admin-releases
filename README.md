# Cortex Admin

[![Cortex Admin](https://raw.githubusercontent.com/IEver3st/gsd-tebex-media/main/heroes/admin.jpg)](https://gsdmods.com/scripts/cortex-admin?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin)

**[Download Latest Release (v1.3.0)](https://github.com/IEver3st/cortex-admin-releases/releases/latest)** · [Product Page](https://gsdmods.com/scripts/cortex-admin?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) · [All 36 Cortex Scripts](https://gsdmods.com/scripts?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) · [Docs](https://gsdmods.com/docs?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) · [Discord](https://discord.com/invite/gsdmods)

> **Free direct download — no Tebex checkout or Asset Escrow required.** Download the ready-to-drop `cortex-admin-1.3.0.zip` from [GitHub Releases](https://github.com/IEver3st/cortex-admin-releases/releases/latest) and extract `cortex-admin` into your FiveM `resources/` folder.

![FiveM](https://img.shields.io/badge/FiveM-Resource-orange)
![QBX](https://img.shields.io/badge/QBX-Compatible-blue)
![Lua](https://img.shields.io/badge/Lua-5.4-blue)
**Admin and developer menu for FiveM, with Qbox tools and a vMenu mode.** Version 1.3.0.

`cortex-admin` is a FiveM admin and developer menu. It provides player, vehicle, world, weapons, teleport, appearance, inventory, garage, dev and server management tools, with optional automatic integration for `qbx_core`, `ox_inventory`, and `qbx_vehicles`.

The optional [Qbox administration section](QBOX.md) adds 31 actions, complete paged inventory catalogs, owned-vehicle grants, and saving the current Cortex wardrobe look as the active Qbox character appearance.

## Requirements

- OneSync. The resource does not start without it.
- [Cortex Library](https://github.com/IEver3st/cortex-lib) 3.3.1 or newer (free), started before Cortex Admin.
- Optional, for the Qbox tools: `qbx_core`, `ox_inventory`, `qbx_vehicles`, `qbx_garages` and `oxmysql`. Without `qbx_core` the menu runs standalone and the Qbox, Inventory and Garage actions stay hidden. See [QBOX.md](QBOX.md) for what each one adds.
- Optional: `screenshot-basic` for Take Photo, and `illenium-appearance` for saving a look as the Qbox character appearance.

There is no SQL to install. Owned-vehicle tools use Qbox's existing `player_vehicles` table; everything else is stored in FiveM KVP.

## Vehicle deletion command

Admin owns `/dv`. It works independently of the menu and `cortex-chat`, and requires OneSync. Configure `Config.Dv` in `shared/config.lua`:

- `Enabled = true` registers the command and permits server requests.
- `RequirePermission = false` lets every player use it. Set `true` to use Admin's `vehicle.delete` permission policy. This setting does not grant menu access.
- `Range = 6.0` limits deletion distance (server bounds: 1.5–25 game units).
- `CooldownMs = 1500` limits requests (server bounds: 1000–60000 ms).

The server validates network ID, range, routing bucket and occupants, deletes the entity, and confirms removal before reporting success through Admin notifications. Another driver or player aboard blocks deletion; a player inside the selected vehicle must be its driver. Garage/ownership records are unchanged.

After changing `Config.Dv`, run `restart cortex-admin`. If `cortex-chat` used to own `/dv` on your server, restart it after Cortex Admin.

## Features

The menu is organized into tabs. Its action catalogs live in `shared/actions.lua`, `shared/qbox.lua`, and `shared/vmenu_compat.lua`.

- **Player** – Gear Up (default saved character, default loadout, full health and heavy armour in one press; `/gearup`, unbound key **Cortex Admin: gear up**), god mode, invisibility, noclip, super jump, fast run/swim, infinite stamina, no ragdoll, heal, armor, revive, wanted level, freeze, clean/dry/wet player, ped model swap, save/load MP peds.
- **Vehicle** – spawn, preview, save personal vehicles, repair, clean, delete, flip, engine toggle, vehicle godmode, speed limiter, torque/power multipliers, plate text, bike seatbelt, max performance mods.
- **Live Vehicle Tuning** – edit powertrain, braking, grip, suspension, chassis and engine audio on the vehicle you are driving; captured handling values can be restored at any time.
- **World** – set weather, set time, freeze time, blackout, disable NPCs/traffic, clear area/vehicles/peds/objects.
- **Weapons** – give weapon, give all, remove all, save/load/delete loadouts, infinite ammo, explosive and incendiary ammo, gravity gun (beta: aim a drawn weapon at a networked prop, vehicle or NPC and fire to lift it, fire again to throw, release aim to drop, scroll for distance), set ammo, attachments, tints, parachute.
- **Teleport** – waypoint, marker, coordinates, back, save/load/delete custom locations.
- **Appearance** – generate a cleaned-up outfit or complete freemode character, choose a style, palette, top, bottoms, footwear, headwear and accessories, steer face, eyes, hair and grooming, undo the last roll, randomize MP face, clear ped tattoos, and set a default outfit.
- **Vehicle Customizer** – dedicated UI tab for tuning/styling the current vehicle.
- **Inventory** *(QBX + ox_inventory)* – give items to players from the full item list.
- **Garage** *(QBX + qbx_vehicles)* – spawn personal vehicles from the QBX garage.
- **Dev** – coordinate/speed HUD, hide HUD, night/thermal vision, player blips, freecam, photo mode, screenshots, gallery, reset UI.
- **Server** – resource manager (start/stop/restart/ensure/refresh), pull stash.
- **Options** – one row, **Admin settings**, opens Cortex settings. Menu, character, vehicle and control preferences live in the **Admin** tab there (stored by cortex-lib under `cortex-admin:`; values from the old store are carried across once). The menu wears the shared accent from Cortex settings; it has no accent of its own.
- **Favorites / All** – bookmark and browse every action.

<details>
<summary>Full action catalog</summary>

### appearance
- Set Default Outfit
- Generate Appearance
- Undo Generated Appearance
- Randomize MP Face
- Clear Ped Tattoos

### dev
- Coordinate HUD
- Speed HUD
- Speed HUD Units
- Speed HUD Position
- Hide HUD
- Night Vision
- Thermal Vision
- Show Player Blips
- Set My Stress *(QBX only)*
- Reset & Reload UI
- Take Photo
- Open Gallery
- Photo Mode (U to toggle; see [SHOWCASE-CAMERA.md](SHOWCASE-CAMERA.md))
- Freecam

### garage
- My Garage *(QBX only)*

### inventory
- Give Item *(QBX only)*

### options
- Admin settings opens the Cortex settings page. Menu, character, vehicle and control preferences live in its Admin tab. Presentation follows the shared Cortex profile.

### player
- God Mode
- Invisibility
- Noclip
- Super Jump
- Infinite Stamina
- No Ragdoll
- Fast Run
- Fast Swim
- Heal
- Max Armor
- Revive
- Clear Wanted
- Never Wanted
- Set Wanted Level
- Freeze Player
- Everyone Ignores
- Clean Player
- Dry Player
- Wet Player
- Set Ped Model
- Save MP Ped
- Load MP Ped
- Save Ped
- Load Ped
- Copy Coords
- Copy Heading
- Kill Player
- Revive Player *(QBX only)*
- Sit In Vehicle
- Set Job *(QBX only)*
- Set Gang *(QBX only)*
- Set Cash *(QBX only)*
- Set Bank *(QBX only)*
- Give Money *(QBX only)*
- Set Hunger *(QBX only)*
- Set Thirst *(QBX only)*
- Set Stress *(QBX only)*
- Open Inventory *(QBX only)*
- Set Routing Bucket *(QBX only)*

### server
- Resource Manager
- Pull Stash *(QBX only)*
- Refresh Resources

### teleport
- Teleport to Waypoint
- Teleport to Marker
- Teleport to Coords
- Teleport Back
- Save Location
- Load Saved Location
- Delete Saved Location

### vehicle
- Spawn Vehicle
- Vehicle Preview
- Live Vehicle Tuning
- Personal Vehicles
- Save Current Vehicle
- Repair Vehicle
- Clean Vehicle
- Delete Vehicle
- Destroy Engine
- Flip Vehicle
- Engine Toggle
- Vehicle Godmode
- Keep Vehicle Clean
- Speed Limiter
- Clear Speed Limit
- Torque Multiplier
- Power Multiplier
- Change Plate Text
- Bike Seatbelt
- Max Performance Mods
- Admin Car *(QBX only)*
- Give Current Vehicle Keys *(QBX only)*

### weapons
- Give Weapon
- Give Weapon (Custom)
- Give All Weapons
- Remove All Weapons
- Save Weapon Loadout
- Load Weapon Loadout
- Delete Weapon Loadout
- Infinite Ammo
- Set Ammo
- Weapon attachments
- Weapon tint
- Parachute

### world
- Set Weather
- Set Time
- Freeze Time
- Blackout
- Disable NPCs & Traffic
- Clear Area
- Delete Vehicles
- Delete Peds
- Delete Objects
</details>

## Installation

1. Download Cortex Admin from [portal.cfx.re](https://portal.cfx.re/assets/granted-assets) under Granted Assets.
2. Place the `cortex-admin` folder in your resources directory, for example `resources/[cortex]/cortex-admin`. Do not rename the folder or delete any `.fxap` file.
3. In `server.cfg`, start it after Cortex Library and, when you use them, the database, inventory and Qbox resources:
   ```cfg
   ensure cortex-lib
   # ensure oxmysql, qbx_core, ox_inventory, qbx_vehicles and qbx_garages here when you use Qbox
   ensure cortex-admin
   ```
4. If your admins already inherit `command allow` (see [Permissions](#permissions)), keep that setup. Otherwise add the bundled permission file **before** `ensure cortex-admin`, adjusting the path to where you placed the folder:
   ```cfg
   exec resources/[cortex]/cortex-admin/permissions.cfg
   ```
5. Restart the server.

Open the menu with `/cortexadmin`, `/esadmin`, or `F10`. The legacy command and default keybind can be changed in `shared/config.lua`; `/cortexadmin` remains available. Both commands use the same menu and permissions. Cortex Chat hides internal keybind/debug handlers from autocomplete while keeping their bindings functional.

Every Cortex Admin key appears in FiveM's key settings as **Cortex Admin: ...**, and only once that player can use it. The menu (`F10`, vMenu `M`) and `F4` keys register when the server first sends the player's menu permissions; noclip (`F2`) and photo mode (`U`) register with their permissions. The waypoint (`F7`), expanded radar (`Z`) and finger point (`B`) keys register when their option is first turned on; `B` stays with cortex-emotemenu while it runs. Players without access see none of these. Commands are unaffected. A key granted mid-session appears after the next permission refresh, for example opening the menu with `/esadmin`.

## Configuration

All client-side and shared configuration lives in `shared/config.lua`:

| Setting | Description |
|---------|-------------|
| `Config.Command` | Chat command to open the menu (`esadmin`). |
| `Config.Keybind` | Default keybind (`F10`). |
| `Config.DefaultSettings` | UI scale, opacity, accent color, menu position, ped behavior, etc. |
| `Config.Permissions` | Tab-level ACE permission strings. |
| `Config.ActionPermissions` | Fine-grained ACE permissions for individual actions. |
| `Config.AllowCommandAdmin` | Accept the broad FiveM `command` ACE as full Cortex admin access (default `true`). Set `false` to use separate action grants. |
| `Config.QBXPermissions` | Automatic permission mapping for QBX `god`/`admin`/`mod` ACE groups. |
| `Config.WeaponList` | Weapons available in the Give Weapon action. |
| `Config.BanIdentifierTypes` | Identifier types persisted when banning a player. |

At start, Cortex Admin checks the main settings. A wrong type or out-of-range value prints one line in the server console naming the key, for example `shared/config.lua: Config.Dv.Range expected a number, got "far"; using 6.0.` Numbers written as text, such as `'3000'`, are converted without a message. Out-of-range numbers are clamped to the nearest limit. A wrong `Config.Dv.RequirePermission`, `Config.Dv.Enabled` or `Config.AllowCommandAdmin` falls back to the stricter setting; other wrong values fall back to the default. An empty key setting such as `Config.Keybind = ''` ships that mapping unbound.

These files stay readable in the release so you can configure and integrate Cortex Admin: `fxmanifest.lua`, `shared/config.lua`, `shared/bridge.lua`, `client/bridge.lua`, `server/bridge.lua`, `permissions.cfg` and the `compat/vMenu` stand-in.

## Permissions

Access is controlled entirely by FiveM ACE permissions:

- `cortex-admin.all` – full menu access.
- `cortex-admin.<tab>` – access to a whole tab (`player`, `vehicle`, `world`, etc.).
- `cortex-admin.<tab>.<action>` – access to a specific action when fine-grained ACEs are used (see `Config.ActionPermissions`).

FiveM's standard system-admin configuration works by default, without QBX or ox_lib:

```cfg
add_ace group.admin command allow
add_ace group.admin command.quit deny
add_principal identifier.fivem:YOUR_CFX_ID group.admin
# Add one add_principal line for each admin's actual Cfx ID.
```

With `Config.AllowCommandAdmin = true`, players who inherit the broad `command` ACE receive full Cortex action and model access, equivalent to `cortex-admin.all`. The resource does not change ACE entries, so `command.quit deny` remains in effect. A grant for only `command.cortexadmin`, `command.esadmin`, `command.vmenu`, or the configured menu command opens the menu without granting actions. Ordinary players receive no new permissions, and `resource.ox_lib` ACEs apply to that resource, not players.

Set `Config.AllowCommandAdmin = false` if your server uses `command allow` for people who should have limited Cortex access, then configure explicit action grants. When `qbx_core` is running, the QBX groups `god`, `admin`, and `mod` are mapped via `Config.QBXPermissions`. Any permitted action also grants access to the relevant menu; an extra menu command ACE is optional. Players opens for target-player actions or permitted non-self Qbox tools. Self freeze does not grant target freeze.

Client permissions refresh while authorized and expire within 30 seconds without a fresh server grant. Revocation closes admin surfaces and stops disallowed local effects. Targeted requests include the selected connection token; a disconnect, source-ID reuse or stale form requires selecting the player again.

vMenu vehicle roles are enforced by class, explicit SpawnByName/All access and server-approved addon lists. `Config.VmenuVehicleClasses` is checked first (overrides and addon classes), then the stock game classes generated from GTA V data, then the Qbox vehicle category. Unknown classes fail closed. Addons come from `Config.VmenuAddonModels` or imported server addon configuration. Stock weapons require their individual vMenu weapon ACE; generic Spawn alone does not authorize every stock weapon. Model whitelists remain an additional restriction. Explicit Cortex/Qbox full or action grants intentionally add authority, so review those grants during migration.

`Config.VmenuCompatibility.respectConvars = true` enables the legacy vMenu settings policy. Existing `vmenu_*` settings control menu staff access, spawning, damaged extras, player setup, voice, key bindings, time/weather and other compatibility behavior. Server snapshots supply non-replicated settings to clients. Time/weather still respects Cortex's external-provider ownership policy. Only vMenu's public permission and convar names are reused, for compatibility; no vMenu code or text is included. See [third-party notices](THIRD-PARTY-NOTICES.md).

After changing permissions, run `restart cortex-admin` in the server console and reopen the menu. To check an admin's existing ACE inheritance, run `test_ace identifier.fivem:YOUR_CFX_ID command`; it should report allowed. See the [FiveM ACE command reference](https://docs.fivem.net/docs/server-manual/server-commands/#access-control-commands).

The bundled `permissions.cfg` grants `cortex-admin.all` and `command.esadmin` to `group.admin`:

```cfg
add_ace group.admin "cortex-admin.all" allow
add_ace group.admin "command.esadmin" allow
```

Do **not** uncomment the `builtin.everyone` lines on a production server.

## Replace vMenu

To take over a vMenu server, swap the `vMenu` folder for the stand-in in `compat/vMenu` (steps in [its README](compat/vMenu/README.md)). It keeps the `vMenu` name, so every key a player bound to vMenu (menu, noclip, controller start) opens Cortex Admin, and players land in vMenu mode once. On start, vMenu's bans and `config/` files move into Cortex automatically, and each player's saved peds, vehicles, loadouts and settings import on their first join. While the real vMenu runs instead, it keeps M and F2 and Cortex stays on F10.

## Import a vMenu library

Open **Server → Import vMenu → Import everything**. Each player runs this on their own computer. Cortex reads that player's vMenu client storage directly, even with vMenu stopped; no custom vMenu export or server-host KVP copy is required. Alternate resource names can be added to `Config.VmenuCompatibility.importResourceNames`.

The import saves MP characters, other saved peds, vehicles, weapon loadouts, categories, and settings in Cortex's client KVP storage. Admins can also copy the available server configuration domains. Saved characters and vehicles with an existing Cortex name get a separate `(vMenu)` name. Repeat imports keep records already imported. Original vMenu values, including settings without a Cortex equivalent, are retained under `cortex-admin_vmenu_archive:`; supported settings are applied only when the current role allows them. ACE permissions remain server-controlled.

Writes are read back before being counted as saved. The result distinguishes saved, existing, invalid, and failed records. Imports yield between batches and stop at 10,000 keys or 16 MiB per scan with an explicit incomplete result. Keep the source data if any errors or limits are reported. Cortex storage survives resource/server restarts and removing vMenu, but deleting this computer's FiveM KVP storage removes local libraries; it is not cloud backup.

New ped saves include all three face/skin parents and blend amounts, 20 face features, hair and highlight colors, eye color, all 13 overlays with opacity and both colors, clothing textures/palettes, props, and live decorations (tattoos, hair overlays, badges, and addon tattoos). Clothing collection names/local indices are retained where available. Walking styles and expressions loaded or set through Cortex are also retained; GTA does not expose a general getter for every animation override applied by another script. vMenu's C# clothing/tattoo pairs and skin-tone field names are converted when importing. Saves fail visibly if skin inheritance or decorations cannot be read instead of silently saving defaults. Missing addon assets still need to be installed on the destination server.

## vMenu mode

For players who want vMenu itself: vMenu 3.8.67's menu tree and MenuAPI's controls, drawn in the Cortex style. Choose **Options > Interface > vMenu** in the Panel, **Menu style: vMenu** in Cortex settings, or set `Config.DefaultSettings.interfaceStyle = 'vmenu'` to make it the server default. **About vMenu Mode > Use Cortex Panel** switches back.

- **Keys:** `M` (or the menu key) toggles; the pad's start button also toggles unless **Ignore controller** is on. Arrows or the mouse wheel move, holding repeats with MenuAPI's acceleration. Enter, pad A or left click selects; Backspace, Esc, right click or pad B goes back. Left/Right step lists and sliders, toggle checkboxes, and select or go back on plain rows, as MenuAPI does. Space is **Filter** on Banned Players and the male/female/other ped lists and toggles the doors in the Mod Menu; Delete removes an unavailable saved vehicle.
- **No cursor:** the game keeps its movement and camera under the menu. Only what MenuAPI disables is blocked: attack, aim, phone, radio wheel, weapon-wheel scrolling and Esc pausing.
- **Noclip:** flies like vMenu's: W/S move, A/D turn (with camera steering off), Q/Z up and down, Shift cycles vMenu's eight speeds, H switches camera steering. The keys show on cortex-lib's help strip, which names the bound toggle key. A/D also turn a vehicle, which vMenu skips. **Settings > Controls > vMenu noclip controls** off switches back to Cortex flight.
- **Server Management:** a Cortex addition to the main menu. Lists resources with their state; start, restart or stop one, or refresh the list. Needs `server.resources`; the server refuses protected resources. **Pull Stash** (`server.pullStash`) opens an ox_inventory stash by name.
- **Cortex additions in vMenu's menus:** Max Armor, Revive Player and Clear Wanted Level (Player Options); Explosive Ammo, Incendiary Ammo, Gravity Gun and Set Current Weapon Ammo (Weapon Options); Max Vehicle Upgrades, Max Performance Upgrades, Admin Car, Give Current Vehicle Keys, Vehicle Camera and Live Vehicle Tuning (Vehicle Options); Generate Appearance with the Character Studio's style, palette, clothing-type and identity choices, plus Undo (MP Ped Customization); Disable NPCs & Traffic and Delete Vehicles/Peds/Objects by radius (World Related); Teleport Back and Delete Teleport Location; Freecam, Photo Mode, Copy Coordinates/Heading and Set My Stress (Developer Tools); Default To MP Ped and Reset All Settings (Misc Settings); Freeze/Unfreeze and Revive on each online player. Inventory, My Garage, Live Vehicle Tuning, **Qbox Tools** (Player Related) and **Qbox Character Tools** (each online player: job, gang, money, needs, inventory, licenses) are native menus too, on the same requests and permissions as the Panel pages, so vMenu mode never switches to the Panel; only **About > Use Cortex Panel** does. Panel-only: accent colour, UI scale and opacity, mouse controls, double-click to run and target info.
- **Character previews:** a local-only clone stands 2.2 m in front of you, facing you, while you browse saved characters or ped models. It no longer follows the camera.
- **Layout:** top-left of the safe zone, or top-right with **Menu position: Right** (vMenu's Right Align Menu). Ten rows, counter, description underneath; Select/Back and the menu's buttons show on cortex-lib's help strip, bottom right.
- **Same authority:** every row runs an existing Cortex action, is hidden without its permission and is rechecked when used. vMenu ACEs keep working through the existing aliases; the server still authorizes models, weapons and targets.

Saved vehicle and character categories, rename/clone/replace flows, zone tattoos, statistics, chameleon paints, character camera controls, hover previews, recording hotkeys and server information are implemented. Model and class locks use batched server checks before selection, with authorization checked again on use. Imported teleport locations remain client-local.

## Move or drive with the menu open

In the Panel header, select **Drive / move**, or press **F4** when you are not typing. The menu stays visible while the cursor disappears and GTA regains keyboard, mouse, camera and controller input. Press F4 again to interact with the menu. The header displays the current binding; change it under FiveM key bindings (**Cortex Admin: switch menu/game controls**), with `Config.MenuControlKey` supplying the default.

Chat and other focused interfaces retain their input. Close Character or Vehicle Studio before entering game-control mode. Closing and reopening the menu returns to normal menu input. Classic keeps its existing game-controls behavior.

## Players console

Player actions identify a connection rather than only a reusable server ID. Qbox tools receive the minimal citizen ID needed to target a character; money and inspection details remain separately permission controlled. Catalogs expose Previous/Next pages and report provider failures. The roster is capped by `Config.Players.maxRosterEntries` (default 256, range 1–2048); truncation displays the total and configured limit.

A full-screen page for acting on online players, built from `web-players/` (Svelte 5) into `ui/players/`. Open it from the admin menu's Players entry or `/players [id]`. The game behind it is blurred and the HUD hidden, as on cortex-lib's settings page.

- **Roster**: search by name, server ID, character name or citizen ID; filter by nearby (100 m), in a vehicle, down or frozen; sort by nearest, ID or name. Refreshes once a second while open.
- **Dossier**: health, armour, vehicle, distance and routing bucket, plus the Qbox character, job, gang, cash and bank when you may see them.
- **Actions**: Go to, Bring (the target arrives beside you, with their car if they are driving), Enter vehicle (you arrive beside a distant vehicle first so it streams in, then take a free seat), Spectate (again to stop), Waypoint, Revive, Freeze (shared server state), Kill, Smite (launch, set on fire, turn into a chicken for 20 s, or drunk for 30 s; `player.smite`), Message, Identifiers, Kick and Ban. Only actions you are permitted appear. Each shows its progress and the server's answer inline.
- **Character**: every permitted Qbox tool from the Qbox tab (money, jobs and gangs, needs, inventory, vehicles, licenses, records), with searchable pickers for jobs, grades, items and other catalogs.
- **Keys**: ↑↓ choose a player, Enter go to, B bring, V enter vehicle, S spectate, F freeze, R revive, W waypoint, M message, I identifiers, `/` search, Esc back.

## World synchronization

Set `Config.WorldSync.mode` in `shared/config.lua`: `auto` (default) backs off when a listed external weather resource is started, `cortex` explicitly gives Cortex the global clock/weather, and `disabled` makes no global writes. Add custom weather resources to `externalResources`. Global time/weather tools are unavailable when ownership is delegated, except under cortex-weather: Set Time, Set Exact Time, Freeze Time and `/time` then drive its clock through its exports, with the same permissions. `millisecondsPerGameMinute` uses milliseconds (default 2000). Studio and director preview holds prevent Cortex world effects from overwriting their local scene.

Cortex owns one server clock and broadcasts complete time, weather, blackout, dynamic-weather, vehicle-light, snow-effect and cloud snapshots. All players receive them, including players without menu permissions. Changing world settings still requires the corresponding server-side ACE permission. Clients request fresh state on start and spawn; a 15-second heartbeat repairs missed updates. Clock projection runs locally every 250 ms, independently of whether the menu is open.

`Config.WorldSync.millisecondsPerGameMinute` defaults to `2000`. A fresh world starts at noon with clear weather. Changes and resource stops save the world in server KVP storage. Running time advances across resource downtime; frozen time stays fixed. Vehicle Studio temporarily owns only the viewing player's clock, then restores the current server time when closed. Random clouds are chosen once by the server and included in late-join snapshots.

## Commands

The resource registers a large set of convenience chat commands. Administrative commands use the menu's permission policy; `/dv`, `/delveh` and `/deleteveh` use `Config.Dv.RequirePermission` as documented above.

<details>
<summary>Registered commands</summary>

| Command | Description |
|---------|-------------|
| `/cortexadmin`, `/esadmin` | Open the admin menu. |
| `/time [set] <hour> [minute]` | Set synchronized time (hour 0-23, minute 0-59). Minutes default to 00. Accepts `/time 12`, `/time set 12`, `/time 12 00`, and `/time set 12 00`. Requires the menu's `world.time` permission; also available from the server console. |
| `/time [set] day` | Set synchronized time to 12:00. |
| `/tp X Y [Z]` | Teleport to coordinates (supports `X=..., Y=...` style). |
| `/tpm` | Teleport to the map waypoint. |
| `/tpmarker` | Teleport to the current marker. |
| `/tpback` | Teleport to the previous location. |
| `/parachute` | Give a parachute. |
| `/noclip` | Toggle noclip. |
| `/gearup` | Put on your default saved character and default loadout, then fill health and heavy armour. |
| `/cortexadmin_prefs` | Print each saved gameplay toggle: in memory, on disk, live and permitted. |
| `/players [id]` | Open the Players console, optionally on one player. The admin menu's Players entry opens it too. |
| `/showcase` | Photo mode on/off (default key U; needs `dev.photoMode`; `cortex-admin.dev` grants the Dev tab). |
| `/god` | Toggle god mode. |
| `/vanish` | Toggle invisibility. |
| `/heal` | Heal the player. |
| `/armor` | Give max armor. |
| `/revive` | Revive the player. |
| `/coords` | Print current coordinates. |
| `/copycoords` | Copy current coordinates to clipboard. |
| `/heading` | Print current heading. |
| `/copyheading` | Copy current heading to clipboard. |
| `/dv` | Delete your current vehicle as driver, or an empty nearby vehicle, subject to server safety checks. Public by default. |
| `/delveh` / `/deleteveh` | Alias for delete vehicle. |
| `/car <model>` | Spawn a vehicle model. |
| `/veh` / `/spawnveh` | Alias for `/car`. |
| `/fix` / `/fixveh` / `/repair` / `/repairveh` | Repair the current vehicle. |
| `/doors <0-7\|open\|close\|hood\|trunk\|bombbay>` / `/door` | Toggle a door or open/close all doors. IDs: 0/1 front left/right, 2/3 rear left/right, 4 hood, 5 trunk, 6/7 model-specific doors. Uses the Vehicle Doors permission. |
| `/extras <0-20>` / `/extra` | Toggle an available extra on the current vehicle. Uses the Vehicle Components permission. |
| `/clean` / `/cleanveh` | Clean the current vehicle. |
| `/flip` | Flip the current vehicle. |
| `/maxmods` | Apply max performance mods. |
| `/weapon <model>` | Give a weapon. |
| `/giveweapon` | Alias for `/weapon`. |
| `/ammo <model> [amount]` | Set ammo for a weapon. |
| `/clearweapons` | Remove all weapons. |
| `/preview <model>` | Preview a vehicle model. |
| `/esadmin_reset` | Reset and reload the UI. |
</details>

### Exports

```lua
exports['cortex-admin']:teleportToCoords(x, y, showNotification)
```

Teleports the local player to the given `x`/`y` coordinates, optionally displaying a notification.

Server-side, other resources can ask the same permission policy the menu uses, including ACE grants and Qbox group mappings:

```lua
-- true when the player may open the admin menu
local isStaff = exports['cortex-admin']:CanOpenMenu(source)

-- true when the player holds the vehicle.delete action
if exports['cortex-admin']:CanDeleteVehicle(source) then
    DeleteEntity(vehicle)
end
```

Both return `false` for an invalid player ID. Opening the menu alone does not grant destructive actions, so check the specific export for the action you gate.

## Appearance generator

Open **Appearance > Appearance generator** to apply either a curated outfit or a complete MP freemode character. Outfit-only rolls preserve the current face, heritage, and hair. Complete-character rolls add a body-model choice, a face profile (including a full heritage range across every base-game parent), face variation strength, age, complexion with optional freckles, eye color, hair shape and color (natural tones, gray, or dyed), highlight strength, facial hair for the male body, and makeup for the female body. Hair, lipstick and blush colors are picked from the live GTA palettes.

Outfits are assembled from reviewed, interchangeable piece pools for each gender, style, and palette. Upper-body modules keep arms, undershirts, and tops together, then the generator independently chooses compatible pants and shoes. This provides real random variety without mixing unrelated component numbers. The mixed palette varies the focal top while keeping pants and shoes neutral, so independent color rolls cannot clash. The Top, Bottoms and Footwear controls narrow each roll to one garment kind (for example boots, shorts or jackets). A family that lacks the kind borrows pieces of that kind already approved by the same style's other families, and exact families always win. Skirts and heels exist only for the female body; the panel hides them for the male body and the generator explains when a kind does not exist for the body being dressed. Headwear adds a base-game cap, beanie or brimmed hat, and Accessories adds a watch or glasses, or one of each. Invalid runtime pieces are removed individually, and an invalid optional prop never rejects the clothing outfit. The library uses FiveM's stable base-game collection indexes instead of GTA's global random clothing native. The most recent roll can be undone once, and generated looks remain temporary until they are saved to the outfit library. Changing the body model recreates the player ped, so model-bound tattoos or state owned by another appearance resource may need to be reapplied.

## Studio camera

Both studios use the same camera gestures over the open game view:

- Hold right or middle mouse and drag to orbit horizontally and vertically.
  Left drag also works. Hold Shift while dragging to pan. Dragging right/up moves
  the camera right/up in its own view, consistently for orbit and pan.
- Scroll to zoom. Scrolling an inspector edits/scrolls that inspector without moving the camera.
- Focus the game view for arrow-key orbit, Shift + arrows to pan, and `+` / `-` to zoom.
  Camera buttons provide the same basic alternatives. Vehicle Free-move changes dragging to panning.
- Reset restores the camera; character Body / Face / Torso / Legs buttons recenter that framing.
- Done or Escape returns to the admin menu. Applied edits remain live; garage/wardrobe saving uses the existing explicit save actions.

## Limitations

Ordinary Qbox owned-vehicle spawning requires OneSync, `oxmysql`, `qbx_core` and `qbx_vehicles`. It reserves only your GARAGED row before creating a server entity; OUT/impounded and already spawned vehicles are refused. Registered vehicle definitions must provide the correct server spawn type. Failed operations compensate the row/entity and log compensation failures. A marked Cortex inventory bridge keeps its provider-owned spawn path, without a fallback after rejection.

Admin Car claims a registered, unowned current entity as an OUT owned vehicle. It rejects an already registered plate or bound entity and does not transfer another person's vehicle. Park it through the normal garage to make it GARAGED.

Core resources are protected from menu stop/restart by `Config.ProtectedResources`, together with Cortex Admin and Cortex Lib. Use a controlled console procedure for those restarts.

- Requires `cortex-lib` to be installed and started first.
- QBX-branded tabs and actions (`Inventory`, `Garage`, `Give Money`, `Set Job/Gang`, `Admin Car`, etc.) require `qbx_core`, `ox_inventory`, or `qbx_vehicles` and will not function on a standalone server.
- Permissions are enforced through FiveM ACE; misconfiguring `permissions.cfg` can grant unintended access.
- The NUI frontend is compiled into `ui/admin/` (icons included) and uses cortex-lib's display face plus system font stacks, so the menu does not require internet access at runtime.
- Vehicle preview and customizer features rely on live NUI messages and native vehicle spawning; addon vehicles are discovered by scanning other resources’ `vehicles.meta` declarations and stream files.
- vMenu libraries are imported from each player's client storage. An optional server fallback may read a configured KVP path; it is not required for normal client imports. Customer vMenu settings live in editable `shared/config.lua`.
- vMenu compatibility is partial. Missing or different workflows include transparent distant spectating, plane bombs/flares, some MK2 tint policies and damaged-vehicle extra policy. Cortex and Qbox permissions are additional authorities; this resource does not reproduce every vMenu convar or submenu policy.
- `Config.Debug = true` prints extra diagnostics in F8 and the server console. Leave it off on a live server.

## Updating

1. Download the new version from [portal.cfx.re](https://portal.cfx.re/assets/granted-assets) under Granted Assets.
2. Keep a copy of your `shared/config.lua`, `permissions.cfg` and any bridge files you edited.
3. Replace the `cortex-admin` folder, then copy your edits back. Check [CHANGELOG.md](CHANGELOG.md) for any **Action required** notes.
4. Restart `cortex-lib` if it was updated too, then `restart cortex-admin`.

Saved peds, vehicles, loadouts, locations and settings live in each player's FiveM KVP storage and the server's KVP, so they survive updates.

## Troubleshooting

- **"You lack the required entitlement"**: your server key must belong to the Cfx.re account that bought Cortex Admin.
- **"Failed to verify protected resource"**: the files were corrupted in transfer. Download again and upload in binary mode (for example with WinSCP).
- **The resource does not start**: enable OneSync, and start `cortex-lib` before `cortex-admin`.
- **The menu does not open**: check your permissions with `test_ace identifier.fivem:YOUR_CFX_ID command` or your `cortex-admin.*` grants, and that `exec .../permissions.cfg` comes before `ensure cortex-admin`.
- **Qbox, Inventory or Garage tools are missing**: start `qbx_core` and its resources before `cortex-admin`.
- **A garaged vehicle will not spawn**: vehicles that are already out or impounded are refused on purpose. Return them through the normal garage first.
- **More console output**: set `Config.Debug = true`, reproduce the problem, and include the F8 and server console lines when you ask for help.

## Support

Join the [GSD Modifications Discord](https://discord.gg/gsdmods) and open a ticket. Include your server artifact version, framework, and the console error. Guides are at [gsdmods.com/docs](https://gsdmods.com/docs).

## License

Cortex-authored code is covered by the [commercial license](LICENSE); no resale or redistribution. Third-party notices and the reference-image shipping policy are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Copyright (c) 2026 Ever3st.

## Disclaimer

`cortex-admin` is an independent FiveM resource and is not affiliated with, endorsed by, or sponsored by Cfx, Rockstar Games, or the QBX project. Trademarks and registered trademarks are the property of their respective owners.

## More from Cortex

Cortex Admin is free and stays free. All 36 Cortex scripts share one free library ([`cortex-lib`](https://github.com/IEver3st/cortex-lib)) and one consistent UI, with native cross-script integrations and zero conflicts.

### Flagship Paid Suites & Scripts

| Police & Tactical | Economy & World | Core UI & Vehicles |
| --- | --- | --- |
| [**Cortex MDT**](https://gsdmods.com/scripts/cortex-mdt?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): Full police MDT + Dispatch included free | [**Cortex Banking**](https://gsdmods.com/scripts/cortex-banking?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): 4 banks, rebuilt 3D ATMs, cards, credit scores & loans | [**Cortex HUD**](https://gsdmods.com/scripts/cortex-hud?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): HUD Studio with three built-in layouts |
| [**Cortex PolCam**](https://gsdmods.com/scripts/cortex-polcam?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): FLIR helicopter camera with tracking & ground link | [**Cortex Vending**](https://gsdmods.com/scripts/cortex-vending?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): Player-owned vending machines with 105 3D products | [**Cortex Handling**](https://gsdmods.com/scripts/cortex-handling?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): Live in-game vehicle handling editor & exporter |
| [**Cortex Dispatch**](https://gsdmods.com/scripts/cortex-dispatch?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): Live alerts, unit routing & panic calls | [**Cortex Caseboard**](https://gsdmods.com/scripts/cortex-caseboard?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): Detective corkboards with red strings & 18 card types | [**Cortex Multicharacter**](https://gsdmods.com/scripts/cortex-multicharacter?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): Character roster, dossier & ID registration |
| [**Cortex Radar**](https://gsdmods.com/scripts/cortex-radar?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): Handheld 3D police radar gun | [**Cortex Whiteboard**](https://gsdmods.com/scripts/cortex-whiteboard?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): 28 drawable boards with city maps & physics | [**Cortex Rewind**](https://gsdmods.com/scripts/cortex-rewind?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): Forza-style vehicle rewind in FiveM |
| [**Cortex Arges**](https://gsdmods.com/scripts/cortex-arges?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) · [**Radio**](https://gsdmods.com/scripts/cortex-radio?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) · [**SceneKit**](https://gsdmods.com/scripts/cortex-scenekit?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) | [**Cortex Computer**](https://gsdmods.com/scripts/cortex-computer?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin): In-world playable computers & monitors | [**Cortex Chat**](https://gsdmods.com/scripts/cortex-chat?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) · [**Spawn**](https://gsdmods.com/scripts/cortex-spawn?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) · [**Emote Studio**](https://gsdmods.com/scripts/cortex-emote-studio?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) |

### Save with Bundles (One-Time or All-Access)

- [**Cortex Complete**](https://gsdmods.com/scripts/cortex-complete?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) — One-time lifetime bundle, no subscription.
- [**Cortex LEO Kit**](https://gsdmods.com/scripts/cortex-leo-kit?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) — Complete unified police stack (`MDT`, `Dispatch`, `PolCam`, `Radar`, `ALPR`, `Arges`, `Radio`, `SceneKit`, `Caseboard`, `Whiteboard`, `Flashlight`, `Binoculars`).
- [**Cortex Interface Kit**](https://gsdmods.com/scripts/cortex-interface-kit?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) — Complete core UI stack (`HUD`, `Chat`, `Spawn`, `Multicharacter`, `Loading Screen`).
- [**Cortex All-Access**](https://gsdmods.com/scripts/cortex-all-access?utm_source=github&utm_medium=readme&utm_campaign=cortex-admin) — Every current paid script + every future release on day one.

### All Free Cortex Scripts on GitHub

[`cortex-pause`](https://github.com/IEver3st/cortex-pause) · [`cortex-alpr`](https://github.com/IEver3st/cortex-alpr) · [`cortex-newspaper`](https://github.com/IEver3st/cortex-newspaper) · [`cortex-gunsmith`](https://github.com/IEver3st/cortex-gunsmith) · [`cortex-echo`](https://github.com/IEver3st/cortex-echo) · [`cortex-drone`](https://github.com/IEver3st/cortex-drone) · [`cortex-droneraces`](https://github.com/IEver3st/cortex-droneraces) · [`cortex-thrusters`](https://github.com/IEver3st/cortex-thrusters) · [`cortex-megaphone`](https://github.com/IEver3st/cortex-megaphone) · [`cortex-minigames`](https://github.com/IEver3st/cortex-minigames) · [`cortex-admin`](https://github.com/IEver3st/cortex-admin-releases) · [`cortex-atmrobbery`](https://github.com/IEver3st/cortex-atmrobbery) · [`cortex-vendrobbery`](https://github.com/IEver3st/cortex-vendrobbery) · [`cortex-lib`](https://github.com/IEver3st/cortex-lib)
