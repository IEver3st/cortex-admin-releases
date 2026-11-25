fx_version 'cerulean'
game 'gta5'
cortex_inventory_legacy_api '1'

name 'cortex-admin'
author 'GSDMODS/CORTEX'
version '1.3.0'
description 'Admin/dev menu with QBX framework support'

shared_scripts {
    '@cortex-lib/init.lua',
    'shared/config.lua',
    'shared/config_validate.lua',
    'shared/appearance_catalog.lua',
    'shared/appearance_index.lua',
    'shared/appearance_textures.lua',
    'shared/appearance_kits.lua',
    'shared/wardrobe_catalog.lua',
    'shared/appearance_randomizer.lua',
    'shared/wardrobe_share.lua',
    'shared/weapon_component_hashes.lua',
    'shared/bridge.lua',
    'shared/actions.lua',
    'shared/qbox.lua',
    'shared/vmenu_compat.lua',
    'shared/vmenu_weapon_aces.lua',
    'shared/vmenu_reference.lua',
    'shared/vmenu_policy.lua',
}

client_scripts {
    '@cortex-lib/presentation-client.lua',
    'client/bridge.lua',
    'client/main.lua',
    'client/help_layers.lua',
    'client/dv.lua',
    'client/settings.lua',
    'client/vmenu_import.lua',
    'client/vehicle_mod_catalog.lua',
    'client/actions.lua',
    'client/saved_library.lua',
    'client/studio_camera_input.lua',
    'client/character_studio.lua',
    'client/wardrobe_catalog.lua',
    'client/vehicle_studio.lua',
    'client/vehicle_camera.lua',
    'client/showcase_camera.lua',
    'client/vmenu_compat.lua',
    'client/toggle_preferences.lua',
    'client/world_sync.lua',
    'client/vmenu_policy.lua',
    'client/vmenu_runtime.lua',
    'client/classic_menu.lua',
    'client/game_catalogs.lua',
    'client/vmenu_mode.lua',
    'client/vmenu_mode_stats.lua',
    'client/vmenu_mode_main.lua',
    'client/vmenu_mode_players.lua',
    'client/vmenu_mode_player.lua',
    'client/vmenu_mode_appearance.lua',
    'client/tattoo_catalog.lua',
    'client/vmenu_mode_tattoos.lua',
    'client/vmenu_mode_vehicle_options.lua',
    'client/vmenu_mode_vehicles.lua',
    'client/vmenu_mode_world.lua',
    'client/vmenu_mode_server.lua',
    'client/vmenu_mode_qbox.lua',
    'client/vmenu_mode_tuning.lua',
    'client/vmenu_mode_library.lua',
    'client/vmenu_mode_preview.lua',
    'client/nui.lua',
    'client/qbox.lua',
    'client/players.lua',
    'client/gravity_gun.lua',
}

server_scripts {
    'server/files.js',
    'server/bridge.lua',
    'server/actions.lua',
    'server/world_sync.lua',
    'server/vmenu_policy.lua',
    'server/leveldb_reader.lua',
    'server/vmenu_fallback.lua',
    'server/main.lua',
    'server/owned_vehicles.lua',
    'server/permission_exports.lua',
    'server/dv.lua',
    'server/qbox.lua',
    'server/qbox_commands.lua',
    'server/wardrobe_catalog.lua',
    'server/vmenu_compat.lua',
}

dependency 'cortex-lib'
dependency '/onesync'

-- Exports for external resources
exports {
    'teleportToCoords'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    -- Svelte builds: the admin panel and studios, and the players console.
    'ui/admin/*.js',
    'ui/admin/*.css',
    'ui/players/players.css',
    'ui/players/players.js',
    'ui/vehicle-catalog/catalog.js',
    'ui/wardrobe-capture.js',
    'ui/wardrobe-matte.js',
}

lua54 'yes'

-- Keep customer configuration and integration points editable in escrow releases.
escrow_ignore {
    'fxmanifest.lua',
    'shared/config.lua',
    'shared/bridge.lua',
    'client/bridge.lua',
    'server/bridge.lua',
    'permissions.cfg',
    'compat/vMenu/fxmanifest.lua',
    'compat/vMenu/client.lua',
    'compat/vMenu/server.lua',
}
