-- Admin preferences live in Cortex settings (cortex-lib), in their own tab.
-- The rest of the resource keeps reading Admin.state.settings; this file is
-- the only place that knows where those values are stored.
local Admin = EsAdmin
local TAB, PREFIX, MIGRATED = 'cortex-admin', 'cortex-admin:', 'cortex-admin:settings_migrated'
local registered, pushing = false, false
local stored = {} -- last value cortex-lib holds for each key, in its own units

local function choices(list)
    local out = {}
    for index, item in ipairs(list) do out[index] = { value = item[1], label = item[2] } end
    return out
end

-- Order is the order of the settings page. Labels and descriptions come from
-- the action catalogue where the setting has an action, so they are not retyped.
local FIELDS = {
    { 'interfaceStyle', 'Menu', 'select', label = 'Menu style', description = "The panel, the classic list menu, or vMenu mode (vMenu's menus and keys).",
        options = choices({ { 'panel', 'Panel' }, { 'classic', 'Classic' }, { 'vmenu', 'vMenu' } }) },
    { 'uiScale', 'Menu', 'select',
        options = choices({ { 1.0, 'Default' }, { 1.15, 'Large' }, { 1.3, 'Extra large' }, { 1.45, 'Ultra' }, { 1.6, 'Maximum' } }) },
    { 'uiOpacity', 'Menu', 'slider', label = 'Menu opacity', description = 'How solid the admin menu is over the game.',
        min = 35, max = 100, step = 5, suffix = '%' },
    { 'menuPosition', 'Menu', 'select', label = 'Menu position', description = 'Centre the menu or dock it to a screen edge.',
        options = choices({ { 'left', 'Left' }, { 'center', 'Centre' }, { 'right', 'Right' } }) },
    { 'mouseMenuControls', 'Menu', 'toggle' },
    { 'doubleClickToRun', 'Menu', 'toggle' },
    { 'showTargetInfo', 'Menu', 'toggle' },
    { 'disableControllerSupport', 'Menu', 'toggle', label = 'Ignore controller', description = 'Keep the controller from driving the classic menu or opening vMenu mode.' },
    { 'autoLoadSavedPed', 'Character', 'toggle' },
    { 'restorePedOnDeath', 'Character', 'toggle' },
    { 'defaultToMpPed', 'Character', 'toggle' },
    { 'mpPedPreviews', 'Character', 'toggle', label = 'Character previews', description = 'Preview saved characters and ped models while browsing.' },
    { 'vmenuNoclipControls', 'Controls', 'toggle', label = 'vMenu noclip controls',
        description = 'In vMenu mode, noclip flies like vMenu: W/S move, A/D turn, Q/Z up and down, Shift changes speed, H switches camera mode. Off uses Cortex flight controls.' },
    { 'recordingControls', 'Controls', 'toggle', label = 'Recording controls', description = 'Enable recording shortcuts on keyboard and controller.' },
    { 'replacePersonalVehicle', 'Vehicles', 'toggle' },
    { 'spawnInsideVehicle', 'Vehicles', 'toggle', label = 'Spawn inside vehicle', description = 'Sit in a vehicle as soon as it is spawned.' },
    { 'disableAircraftTurbulence', 'Vehicles', 'toggle' },
    { 'disablePlaneTurbulence', 'Vehicles', 'toggle', label = 'No plane turbulence', description = 'Removes turbulence shake in planes only.' },
    { 'disableHelicopterTurbulence', 'Vehicles', 'toggle', label = 'No helicopter turbulence', description = 'Removes turbulence shake in helicopters only.' },
    { 'minimapControls', 'Controls', 'toggle', label = 'Minimap key', description = 'Enable the expanded radar key.' },
    { 'fingerPointControls', 'Controls', 'toggle', label = 'Finger point key', description = 'Enable the finger point key.' },
    { 'disablePrivateMessages', 'Controls', 'toggle', label = 'Block private messages', description = 'Refuse private messages from other players.' },
    { 'speedHudUnits', 'Speed readout', 'select', label = 'Speed units', description = 'Units for the developer speed readout.',
        options = choices({ { 'mph', 'MPH' }, { 'kph', 'KPH' } }) },
    { 'speedHudPosition', 'Speed readout', 'select', label = 'Speed readout position', description = 'Where the developer speed readout sits.',
        options = choices({ { 'top-left', 'Top left' }, { 'top-center', 'Top centre' }, { 'top-right', 'Top right' },
            { 'bottom-left', 'Bottom left' }, { 'bottom-center', 'Bottom centre' }, { 'bottom-right', 'Bottom right' } }) },
    { 'restoreWeaponsOnDeath', 'Character', 'toggle', label = 'Keep weapons on death', description = 'Give back the weapons you held when you died once you are up again.' },
    { 'vmenuImport', 'System', 'action', label = 'Import from vMenu', description = 'Copy your vMenu characters, peds, vehicles, loadouts and settings into Cortex. This runs once by itself; running it again keeps your Cortex saves.',
        actions = { { action = 'vmenu_import', label = 'Import now' } } },
}

-- cortex-lib keeps opacity as a whole percentage; the menu works in 0.35-1.
local function toStore(key, value)
    if key == 'uiOpacity' then return type(value) == 'number' and math.max(35, math.min(100, math.floor(value * 20 + 0.5) * 5)) or nil end
    return value
end
local function fromStore(key, value)
    if key == 'uiOpacity' then return value / 100 end
    return value
end

local function definition()
    local catalogue = {}
    for _, action in ipairs((EsAdminActions and EsAdminActions.actions) or {}) do catalogue[action.id] = action end
    local fields, defaults = {}, {}
    for index, spec in ipairs(FIELDS) do
        local key, action = spec[1], catalogue['options.' .. spec[1]]
        fields[index] = { key = 'admin_' .. key, section = spec[2], type = spec[3],
            label = spec.label or (action and action.label) or key,
            description = spec.description or (action and action.description) or nil,
            options = spec.options, actions = spec.actions, min = spec.min, max = spec.max, step = spec.step, suffix = spec.suffix }
        if spec[3] ~= 'action' then defaults['admin_' .. key] = toStore(key, Config.DefaultSettings[key]) end
    end
    return fields, defaults
end

local function apply()
    if Admin.refreshClassicMenu then Admin.refreshClassicMenu() end
    SendNUIMessage({ action = 'cortex-admin:setState', data = { settings = Admin.state.settings } })
end

local function pull()
    local settings = Admin.state.settings
    for _, spec in ipairs(FIELDS) do
        local key, ok, value = spec[1], false, nil
        if spec[3] ~= 'action' then
            ok, value = pcall(function() return exports['cortex-lib']:getTabSetting(TAB, 'admin_' .. key) end)
        end
        if ok and value ~= nil then
            stored[key] = value
            settings[key] = fromStore(key, value)
        end
    end
end

local function push()
    local settings, saved = Admin.state.settings, true
    -- Each write announces itself; reading back mid-way would undo the ones still to come.
    pushing = true
    for _, spec in ipairs(FIELDS) do
        local key = spec[1]
        local value = toStore(key, settings[key])
        if value ~= nil and value ~= stored[key] then
            local ok, accepted = pcall(function() return exports['cortex-lib']:setSetting('admin_' .. key, value) end)
            if ok and accepted then stored[key] = value else saved = false end
        end
    end
    pushing = false
    return saved
end

local legacySave = Admin.saveSettings
Admin.saveSettings = function()
    -- Keep the complete preference object, including gameplay toggles and imports.
    -- Cortex settings owns the visible fields, but does not store the other keys.
    local saved = legacySave()
    if not registered then return saved end
    return push() and saved
end

local function register()
    registered = false
    if GetResourceState('cortex-lib') ~= 'started' then return end
    local fields, defaults = definition()
    local ok, accepted = pcall(function()
        return exports['cortex-lib']:registerSettings(TAB, 'Admin', PREFIX, fields, defaults)
    end)
    if not ok or accepted ~= true then
        print('[cortex-admin] Cortex settings did not accept the Admin tab; preferences stay in the old store.')
        return
    end
    registered = true
    -- First run on this build: carry the preferences saved by the old store across, once.
    if GetResourceKvpString(MIGRATED) ~= '1' then
        stored = {}
        if push() then SetResourceKvp(MIGRATED, '1') end
    end
    pull()
    legacySave()
    apply()
end

Admin.openSettings = function()
    Admin.setOpen(false)
    if Admin.closeClassicMenu then Admin.closeClassicMenu() end
    local ok, opened = pcall(function() return exports['cortex-lib']:openSettings() end)
    if not ok or opened == false then Admin.notify('error', 'Cortex settings could not be opened.'); return false end
    return true
end

AddEventHandler('cortex-lib:settingsChanged', function(tabId)
    if tabId ~= TAB or not registered or pushing then return end
    pull()
    legacySave()
    apply()
end)

AddEventHandler('cortex-lib:settingsAction', function(tabId, action)
    if tabId ~= TAB or action ~= 'vmenu_import' or not Admin.runVmenuImport then return end
    CreateThread(function() Admin.runVmenuImport(false) end)
end)

AddEventHandler('onClientResourceStart', function(resource)
    -- cortex-lib drops consumer tabs when it restarts; register again once it is back.
    if resource == 'cortex-lib' then register() end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == 'cortex-lib' then registered = false end
end)

register()
