-- Same command names, descriptions and default keys as vMenu, so the bindings
-- players saved for vMenu (stored under this resource name) still apply.
local id = GetConvar('vmenu_keymapping_id', 'Default')
if id == '' then id = 'Default' end
local menuKey = GetConvar('vmenu_menu_toggle_key', 'M')
local noclipKey = GetConvar('vmenu_noclip_toggle_key', 'F2')

local function forward(name)
    return function()
        if GetResourceState('cortex-admin') ~= 'started' then return end
        pcall(function() exports['cortex-admin']:vmenuKey(name) end)
    end
end

RegisterCommand(('vMenu:%s:NoClip'):format(id), forward('NoClip'), false)
RegisterCommand(('vMenu:%s:MenuToggle'):format(id), forward('MenuToggle'), false)
RegisterCommand('vMenu:DV', forward('DV'), false)

RegisterKeyMapping(('vMenu:%s:NoClip'):format(id), 'vMenu NoClip Toggle Button', 'keyboard', noclipKey)
RegisterKeyMapping(('vMenu:%s:MenuToggle'):format(id), 'vMenu Toggle Button', 'keyboard', menuKey)
RegisterKeyMapping(('vMenu:%s:MenuToggle'):format(id), 'vMenu Toggle Button Controller', 'pad_digitalbuttonany', 'start_index')
