-- vMenu mode: the main menu and the three category menus, in vMenu 3.8.67's
-- order and wording (vMenu/MainMenu.cs CreateSubmenus). Each submenu lives in
-- its own client/vmenu_mode_*.lua and is hidden when it has nothing usable,
-- as vMenu hides menus the player has no permission for.
local VM = EsAdmin.VmenuMode

VM.define('main', {
    subtitle = 'Main Menu',
    build = function()
        return {
            VM.submenu('online_players', 'Online Players', 'Everyone on the server right now.'),
            VM.submenu('banned_players', 'Banned Players', 'Browse ban records and lift bans.'),
            VM.submenu('player_related', 'Player Related Options', 'Your character, appearance, weapons and loadouts.'),
            VM.submenu('vehicle_related', 'Vehicle Related Options', 'Spawning, tuning, saved and personal vehicles.'),
            VM.submenu('world_related', 'World Related Options', 'Time, weather, traffic and clearing the area around you.'),
            -- Cortex addition: vMenu has no resource manager.
            VM.submenu('server_management', 'Server Management', 'Start, stop and restart server resources, or open a stash.'),
            VM.submenu('voice_chat', 'Voice Chat Settings', 'Settings for in-game voice.'),
            VM.submenu('recording', 'Recording Options', 'Controls for the built-in clip recorder.'),
            VM.submenu('misc_settings', 'Misc Settings', 'General menu preferences, including saving your settings.'),
            VM.submenu('about', 'About vMenu Mode', 'Information about this menu.'),
        }
    end,
})

VM.define('player_related', {
    subtitle = 'Player Related Options',
    build = function()
        local noclip = VM.can('player.noclip') and VM.button('Toggle NoClip', 'Turn free-flight movement on or off.', function()
            if VM.denied('player.noclip') then return end
            EsAdmin.toggleAction('player.noclip', not VM.isOn('player.noclip'))
        end) or nil
        local giveItem = QboxAdmin and QboxAdmin.actions['qbx.giveItem']
        giveItem = giveItem and VM.can(giveItem.id) and QboxAdmin.available(giveItem)
        return {
            VM.submenu('player_options', 'Player Options', 'Everyday tools for your own character.'),
            VM.submenu('player_appearance', 'Player Appearance', 'Pick a ped model, adjust how it looks, and save or load characters.'),
            VM.submenu('mp_ped', 'MP Ped Customization', 'Build, save and load freemode (MP) characters.'),
            VM.submenu('weapon_options', 'Weapon Options', 'Give or take weapons, fit attachments and manage ammo.'),
            VM.submenu('weapon_loadouts', 'Weapon Loadouts', 'Store weapon sets and equip them again later.'),
            noclip,
            giveItem and VM.submenu('qbox_action', 'Inventory', 'Give a player any registered inventory item.',
                { key = 'qbx.giveItem:any', action = 'qbx.giveItem' }, { key = 'inventory', hideEmpty = false }) or nil,
            EsAdmin.vmenuHasQboxTools and EsAdmin.vmenuHasQboxTools(false) and VM.submenu('qbox_tools', 'Qbox Tools',
                'Jobs, gangs, money, needs, inventory, licenses and saved looks for Qbox characters.', nil, { hideEmpty = false }) or nil,
        }
    end,
})

VM.define('vehicle_related', {
    subtitle = 'Vehicle Related Options',
    build = function()
        return {
            VM.submenu('vehicle_options', 'Vehicle Options', 'Repair, tune and restyle the vehicle you are in, plus general vehicle settings.'),
            VM.submenu('vehicle_spawner', 'Vehicle Spawner', 'Spawn a model by name or browse vehicle classes.'),
            VM.submenu('saved_vehicles', 'Saved Vehicles', 'Store the vehicle you are in, then respawn or remove saved ones.'),
            VM.submenu('personal_vehicle', 'Personal Vehicle', 'Mark a vehicle as yours and control it remotely while you are on foot.'),
            EsAdmin.vmenuGarageAvailable and EsAdmin.vmenuGarageAvailable() and VM.submenu('qbox_garage', 'My Garage',
                'Spawn a vehicle you own from your Qbox garages.', nil, { hideEmpty = false }) or nil,
        }
    end,
})

VM.define('world_related', {
    subtitle = 'World Options',
    build = function()
        return {
            VM.submenu('time_options', 'Time Options', 'Set the clock and adjust how time passes.'),
            VM.submenu('weather_options', 'Weather Options', 'Set the weather and related effects.'),
            VM.toggle('world.disableNpcs', 'Disable NPCs & Traffic', 'Removes all ambient peds and vehicles while it is on.'),
            VM.select('world.clearVehicles', 'Delete Vehicles', 'Pick a radius and confirm to delete nearby vehicles.'),
            VM.select('world.clearPeds', 'Delete Peds', 'Pick a radius and confirm to delete nearby peds.'),
            VM.select('world.clearObjects', 'Delete Objects', 'Pick a radius and confirm to delete nearby objects.'),
        }
    end,
})
