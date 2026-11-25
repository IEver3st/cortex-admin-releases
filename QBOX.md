# Qbox administration

The Qbox destination adds 31 actions. It appears when `qbx_core` is running. Inventory, owned-vehicle and appearance actions also require their supporting resources. The server supplies capability information because `qbx_vehicles` is a server-only resource. Starting or stopping integrations updates the menu; every write checks current availability and permissions again.

## Available actions

| Area | Actions |
| --- | --- |
| Vehicles | Give a registered vehicle to an online character's public garage |
| Inventory | Give item, remove item, inspect inventory, clear inventory |
| Money | Add, remove or set cash; add, remove or set bank balance |
| Jobs | Set primary job and grade, add membership, remove membership, switch primary membership |
| Gangs | Set primary gang and grade, add membership, remove membership, switch primary membership |
| Duty | On duty, off duty |
| Needs | Set hunger, thirst or stress; restore all three |
| Licenses | Grant or revoke a license defined on the selected character |
| Character | Inspect character data, request a Qbox character save |
| Appearance | Save the current look as the active character skin; load the saved character skin |

The Inventory destination uses the same grant form. Item names come from `ox_inventory:Items()`, including custom items and inventory weapons. Search covers labels and internal names, with 60 results per page and no overall 200-item cutoff. Rescan discards the 30-second catalog cache. Inventory grants use the provider's capacity check and AddItem result; weapons receive the inventory's normal metadata. Arbitrary metadata injection is not exposed.

Vehicle selection comes from Qbox's registered vehicle definitions. A grant creates ownership through `qbx_vehicles:CreatePlayerVehicle`, with a generated plate and a compatible public `qbx_garages` garage. Retrieve it there through the normal garage flow. It does not create an extra world entity. Impounds, job/gang garages and garages with custom access rules are excluded.

Group and grade choices come from the active Qbox registry. Set-primary actions honor the server's `qbx:setjob_replaces` / `qbx:setgang_replaces` policy. Add-membership actions preserve the current primary membership.

## Custom slash commands

Restart `cortex-admin` to load the commands. Use `/qbxhelp` in chat for the complete syntax list. Commands default to your loaded character; append a player server ID to target another online character. They require the same menu access and action permissions as the corresponding Qbox menu action, and share its write limits, character locks and audit log. Commands require a logged-in administrator and cannot mutate characters from the server console.

| Command | Effect |
| --- | --- |
| `/fillneeds [playerId]` | Fill hunger and thirst to 100 and clear stress; aliases `/resetneeds`, `/qbxneeds` |
| `/feed [playerId]` | Fill hunger to 100; alias `/fillhunger` |
| `/hydrate [playerId]` | Fill thirst to 100; alias `/fillthirst` |
| `/clearstress [playerId]` | Set stress to 0 |
| `/hunger [value] [playerId]` | Set hunger from 0–100; default 100; alias `/qbxhunger` |
| `/thirst [value] [playerId]` | Set thirst from 0–100; default 100; alias `/qbxthirst` |
| `/stress [value] [playerId]` | Set stress from 0–100; default 0; alias `/qbxstress` |
| `/qbxduty <on\|off> [playerId]` | Set job duty |
| `/qbxmoney <add\|remove\|set> <cash\|bank> <amount> [playerId]` | Update the Qbox balance |
| `/qbxjob <set\|add> <name> <grade> [playerId]` | Set primary job or add a membership |
| `/qbxjob <remove\|primary> <name> [playerId]` | Remove a job membership or switch to an existing one |
| `/qbxgang <set\|add> <name> <grade> [playerId]` | Set primary gang or add a membership |
| `/qbxgang <remove\|primary> <name> [playerId]` | Remove a gang membership or switch to an existing one |
| `/qbxlicense <grant\|revoke> <license> [playerId]` | Change a license already defined on the character |
| `/qbxitem <give\|remove> <item> <quantity> [playerId]` | Change inventory contents through ox_inventory |
| `/giveitem <playerId\|me> <item> [quantity]` | Give an inventory item; quantity defaults to 1; alias `/additem` |
| `/qbxgivevehicle <model> <publicGarage> [playerId]` | Create an owned vehicle in a compatible public garage |
| `/qbxsave [playerId]` | Request a character save through Qbox |
| `/qbxinfo [playerId]` | Display citizen ID, balances, primary groups, duty and needs |

Examples: `/fillneeds` restores your needs, `/feed 12` fills player 12's hunger, `/thirst 75 12` sets their thirst to 75, and `/qbxmoney add cash 500 12` gives them 500 cash. For hunger/thirst/stress, the first argument is always the value; use the fill shortcuts when you only want to supply a target ID. Values and quantities must be whole numbers within the existing action limits. A complete command is explicit confirmation for removal, replacement and vehicle grants. Every invocation executes once; repeating a command intentionally repeats its effect. The commands check registered items/groups/grades/garages and report provider errors.

Needs use Qbox's `SetMetadata` export, which updates character metadata and replicated hunger/thirst/stress state in the installed core. No direct database edits or extra HUD events are needed. The implementation uses the [Qbox server exports](https://docs.qbox.re/resources/qbx_core/exports/server).

Static verification covers command defaults, target selection, action permissions, rate limits, invalid values, failed providers, lock cleanup and command routing through the existing actions. The full Lua runner (`python tools/run-lua-tests.py`) passes, including the Qbox server and client specs. In-game checks remain pending:

1. Run `restart cortex-admin` from the server console. As an admin, use `/qbxhelp`, `/fillneeds`, `/hunger 25`, `/hydrate` and `/qbxinfo`; confirm the HUD and character needs agree.
2. With a second online player, use `/fillneeds <theirId>` and `/thirst 75 <theirId>`. Confirm only their needs change, then relog to check the Qbox save path.
3. Test duty, a valid job/grade, a small cash grant, an inventory item and an owned vehicle in a compatible garage. Check the notifications, inventory/garage and server log.
4. As a regular player, try `/fillneeds` and `/qbxmoney add cash 1`; both must be denied. As an admin, test an offline ID, value 101, an invalid grade and an unavailable inventory resource. Restart `cortex-admin` again and repeat a needs command.

## Use a Cortex wardrobe look as the Qbox character

1. Load or import the desired outfit with Cortex's existing wardrobe controls. Apply the ped model, face, hair and clothing changes you want.
2. In **Character studio → Wardrobe**, expand **Save as Qbox character**. Alternatively, open **Qbox → Save current look as character**.
3. Confirm the change and press **Save current look as character**. Wait for the server's save confirmation.
4. Use **Qbox → Load saved character look** to check the saved result, then relog to verify the normal character-loading path.

The saved fields are the model, face blend, face features, head overlays, hair style/colors, eye color, clothing components, props and named tattoos supported by Illenium. Face blend uses Cortex's native struct reader. Tattoo hashes are translated to Illenium's catalog format, including known automatic hair fades. An unreadable or unrecognized model/tattoo stops the save with an error instead of silently replacing or dropping it. Custom ped names must be registered in Illenium's `shared/peds.lua`; custom tattoos must be in its `shared/tattoos.lua`.

Appearance saving uses the installed Illenium QB `playerskins` schema. Illenium v5.7.0 exposes client appearance APIs but no server appearance-save export. The adapter therefore performs its active-skin update, same-model replacement and insert as one parameterized oxmysql transaction, then reads the active skin back. It does not modify Qbox's player schema or character identity fields. Alternate-model skins remain inactive. A transaction failure preserves the previous active skin. A successful replacement of the same model is permanent.

While Qbox is running, Cortex does not automatically load its local default ped at spawn or after death. Qbox and its appearance provider own that lifecycle. Manual Cortex wardrobe loading remains available. Local standalone auto-restore settings are retained for standalone servers.

Other appearance providers are not guessed. Facial animations, movement styles, temporary damage and other fields outside Illenium's appearance format are not made persistent by this action. This save does not change name, birth date or character gender metadata.

## Permissions and limits

Existing full-admin grants and Qbox admin/god mappings apply. The new tab uses `cortex-admin.qbx`; individual actions use `cortex-admin.qbx.<action>`, such as `cortex-admin.qbx.giveItem` or `cortex-admin.qbx.saveAppearance`. Action IDs are listed in `shared/qbox.lua`. The item-grant form also honors the existing `inventory.giveItem` permission so existing Inventory access keeps working. The existing moderator mapping does not automatically grant all the new Qbox actions. Add specific action IDs to that group's `grant.actions` if needed.

Every target selection includes the character's citizen ID as well as the current server ID. A disconnect, reused ID or character switch requires a new selection. Appearance actions always affect the requesting administrator's own loaded character. Destructive changes require confirmation. No action is authorized by NUI visibility alone.

Requests have bounded rates, one active mutation per administrator and target character, and a 32-result replay cache per administrator session. The client holds at most eight pending requests. A form waits for server acknowledgement and times out after 15 seconds; it never automatically retries a write. If an operation times out, check the inventory, balance or garage before repeating it. The server log records actor/target character, action, outcome and selected values.

Design limits: 60 catalog rows per response, 200 ms search debounce, 30-second catalog cache, two forced rescans per 10 seconds, 1–10000 items per grant/removal, 0–100 needs, and money changes up to 10000000. These are implementation limits, not measured runtime performance claims.

## Compatibility

Targeted actions check both the citizen ID and the player's connection, and check again after inventory capacity and catalog reads. An action is refused if the selected player has reconnected or their server ID now belongs to someone else. Permitted target tools see the minimal citizen ID without being granted character inspection.

Built against: qbx_core 1.24.0, ox_inventory 2.47.9, qbx_vehicles 1.4.2, qbx_garages 1.1.4, illenium-appearance v5.7.0, and oxmysql 2.14.1. Qbox exports were also checked against the [core documentation](https://docs.qbox.re/resources/qbx_core/exports/server) and [vehicle documentation](https://docs.qbox.re/resources/qbx_vehicles/exports/server). No upstream resources or database schemas were edited.
