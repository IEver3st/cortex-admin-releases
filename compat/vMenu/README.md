# vMenu stand-in

Swap vMenu for Cortex Admin without players noticing. FiveM saves each player's
key choices under the resource's name, so this small resource is named `vMenu`
and registers vMenu's own key commands. Whatever key a player picked for vMenu
(menu, noclip, controller start button) now opens Cortex Admin in vMenu mode.

On start it also hands Cortex Admin:

- vMenu's bans (server storage and an old `bans.json`). Unbanning in Cortex lifts the vMenu copy too.
- vMenu's `config/` files (addons, extras, locations, model whitelists, tattoos).

Players' saved peds, outfits, vehicles, loadouts and settings live in vMenu's
client storage, which keeps the `vMenu` name, so Cortex imports them on each
player's first join.

## Install

1. Stop the server.
2. Move the old `vMenu` folder out of `resources` (keep it as a backup).
3. Copy this `vMenu` folder into `resources`.
4. Copy the old vMenu's `config` folder into the new `vMenu` folder. Copy its `bans.json` too if it has one.
5. In `server.cfg`, keep every `setr vmenu_*` convar and the vMenu permissions file, and order the resources:

   ```
   ensure cortex-admin
   ensure vMenu
   ```

6. Start the server. The console prints how many config files and bans were copied.

To go back, stop the server and restore the old `vMenu` folder. Nothing in vMenu's storage is removed except bans you lift in Cortex.
