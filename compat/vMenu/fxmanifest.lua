fx_version 'cerulean'
game 'gta5'
lua54 'yes'

-- Stand-in for vMenu. FiveM saves each player's key choices per resource, so
-- this resource keeps vMenu's name and commands: every key a player bound to
-- vMenu keeps working and opens Cortex Admin. It also hands vMenu's stored bans
-- and config folder to Cortex Admin on start.
name 'vMenu'
author 'GSDMODS/CORTEX'
version '1.0.0'
description 'Cortex Admin stand-in for vMenu: keeps players vMenu keybinds, bans and config'
cortex_vmenu_compat 'yes'

dependency 'cortex-admin'

client_script 'client.lua'
server_script 'server.lua'
