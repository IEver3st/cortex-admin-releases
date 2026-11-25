-- Personal gameplay toggles (Never Wanted, Fast Run, blips...): what the player
-- chose is kept apart from what is applied right now.
--
--   choice   settings.savedToggles, written to the settings record the moment
--            the player changes a toggle. Only Admin.toggleAction writes it.
--   effect   applied through the inner handler (vMenu compat, then actions.lua).
--            Restores after a permission lease and revocations use the inner
--            handler directly, so they can never overwrite a choice.
--
-- The old design kept a second list (importedVmenuToggles) that the base
-- handler rewrote on every toggle, and skipped saving behind a module-wide
-- "restoring" flag. Players' choices landed in the list nothing restored from.
-- That list is folded in once below and no longer written.
local Admin, eligible, applied, changes = EsAdmin, {}, {}, {}
local inner = Admin.toggleAction
local sessionOnly = {
    ['player.noclip'] = true, ['player.freeze'] = true,
    ['vehicle.freeze'] = true, ['vehicle.engine'] = true,
    ['dev.freecam'] = true,
}
local sharedWorld = {
    ['world.freezeTime'] = true, ['world.blackout'] = true,
    ['world.dynamicWeather'] = true, ['world.vehicleBlackout'] = true,
    ['world.snowEffects'] = true,
}
-- On by default in FiveM, and switching them off disables a native feature for
-- the whole session. Enable Voice Chat calls NetworkSetVoiceActive: a saved off
-- choice restored on every join kept FiveM from ever connecting to Mumble
-- (pma-voice showed NO VOICE). Never saved, restored or revoked; each
-- reconnect starts with voice active.
local defaultOn = { ['voice.enabled'] = true }
for _, action in ipairs(EsAdminActions.actions) do
    local option = action.id:match('^options%.(.+)$')
    if action.type == 'toggle' and not sessionOnly[action.id] and not sharedWorld[action.id]
        and not defaultOn[action.id]
        and not (option and Config.DefaultSettings[option] ~= nil) then
        eligible[action.id] = true
    end
end

local function choices()
    local settings = Admin.state.settings
    if type(settings.savedToggles) ~= 'table' then settings.savedToggles = {} end
    return settings.savedToggles
end

-- The settings record only: no cortex-lib push, key mappings or server event,
-- none of which a toggle choice needs (and any of which failing used to count
-- as a failed save).
local function persist()
    if Admin.writeSettingsRecord then return Admin.writeSettingsRecord() == true end
    return Admin.saveSettings() ~= false
end

-- One-time carry-over. A first run takes the vMenu stand-in's saved toggles;
-- the retired imported list then fills anything not chosen in Cortex yet. It
-- holds the choices the old code wrote there instead of here.
do
    local settings = Admin.state.settings
    local fresh = type(settings.savedToggles) ~= 'table'
    local saved, changed = choices(), fresh
    local function fill(values)
        if type(values) ~= 'table' then return end
        for id, enabled in pairs(values) do
            if eligible[id] and type(enabled) == 'boolean' and saved[id] == nil then
                saved[id], changed = enabled, true
            end
        end
    end
    if type(settings.importedVmenuToggles) == 'table' then
        -- Latest values win over the stand-in's older copy.
        for id, enabled in pairs(settings.importedVmenuToggles) do
            if eligible[id] and type(enabled) == 'boolean' and saved[id] ~= enabled then
                saved[id], changed = enabled, true
            end
        end
        settings.importedVmenuToggles, changed = nil, true
    end
    if fresh and Admin.getSavedVmenuToggles then fill(Admin.getSavedVmenuToggles()) end
    for id in pairs(defaultOn) do
        if saved[id] ~= nil then saved[id], changed = nil, true end
    end
    if changed and not persist() then
        print('[cortex-admin] Could not write the carried-over gameplay toggles; they stay in memory for this session.')
    end
end

local function apply(id, value)
    local ok, err = pcall(inner, id, value)
    if not ok then print(('[cortex-admin] Could not apply %s: %s'):format(id, tostring(err))) end
    return ok
end

Admin.toggleAction = function(id, enabled)
    changes[id] = (changes[id] or 0) + 1
    local result = inner(id, enabled)
    local confirmed = Admin.state.toggles[id]
    if eligible[id] and type(confirmed) == 'boolean' then
        applied[id] = confirmed
        local saved = choices()
        if saved[id] ~= confirmed then
            local previous = saved[id]
            saved[id] = confirmed
            if persist() then
                if Config.Debug then
                    print(('[cortex-admin] Saved toggle %s = %s'):format(id, tostring(confirmed)))
                end
            else
                -- Keep the last written value so repeating the choice retries the write.
                saved[id] = previous
                print(('[cortex-admin] Could not save toggle %s'):format(id))
                Admin.notify('error', 'Could not save this setting. Try changing it again.')
            end
        end
    end
    return result
end

-- After every permission lease: each saved choice the player may use is applied,
-- each one they may not is switched off (and kept as a choice for later).
Admin.restoreSavedToggles = function()
    local restored = {}
    for id, enabled in pairs(choices()) do
        if eligible[id] and type(enabled) == 'boolean' then
            local allowed = Admin.state.allowed[id] == true
            local desired = allowed and enabled or false
            if (allowed and applied[id] ~= desired) or (not allowed and applied[id] == true) then
                local before = changes[id]
                -- A handler can yield (entity control); if the player changed this
                -- toggle meanwhile, their change already set applied and wins.
                if apply(id, desired) and changes[id] == before then
                    applied[id] = desired
                    if desired then restored[#restored + 1] = id end
                end
            end
        end
    end
    if #restored > 0 then
        table.sort(restored)
        if Config.Debug then
            print(('[cortex-admin] Restored saved toggles: %s'):format(table.concat(restored, ', ')))
        end
    end
end

Admin.revokeDisallowedToggles = function()
    local revoke = {}
    for id, enabled in pairs(Admin.state.toggles) do
        if enabled == true and Admin.state.allowed[id] ~= true and not sharedWorld[id] and not defaultOn[id] then
            revoke[#revoke + 1] = id
        end
    end
    for _, id in ipairs(revoke) do
        if not apply(id, false) then print(('[cortex-admin] Could not stop revoked %s'):format(id)) end
        Admin.state.toggles[id], applied[id] = false, false
    end
end

Admin.resetSavedToggles = function()
    for id in pairs(eligible) do
        if Admin.state.toggles[id] == true then apply(id, false) end
    end
    applied = {}
    Admin.state.settings.savedToggles = {}
end

-- Also handles a permission response received before this script finished loading.
Admin.restoreSavedToggles()

-- F8 readout for "my setting did not stay": what the menu holds, what is on
-- disk and what is live, per saved toggle.
RegisterCommand('cortexadmin_prefs', function()
    local ok, disk = pcall(json.decode, GetResourceKvpString(Config.KvpKeys.settings) or '')
    disk = ok and type(disk) == 'table' and type(disk.savedToggles) == 'table' and disk.savedToggles or {}
    local ids = {}
    for id in pairs(choices()) do ids[#ids + 1] = id end
    for id in pairs(disk) do if choices()[id] == nil then ids[#ids + 1] = id end end
    table.sort(ids)
    print(('[cortex-admin] %d saved toggles (memory / disk / live / allowed):'):format(#ids))
    for _, id in ipairs(ids) do
        print(('  %s  %s / %s / %s / %s'):format(id, tostring(choices()[id]), tostring(disk[id]),
            tostring(Admin.state.toggles[id]), tostring(Admin.state.allowed[id] == true)))
    end
end, false)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        TriggerServerEvent('cortex-admin:server:requestPermissions')
    end
end)
