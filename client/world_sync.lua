local Admin = EsAdmin
local world = Admin.worldState
local receivedAt, sequence, epoch = nil, -1, nil
local lastRequest = -5000
local previewWasActive = false
local applied = false
local timeApplied, weatherApplied = false, false
local timeTransition
-- A smooth time change sweeps the clock over this long, eased, and is redrawn
-- every frame; at the normal 250 ms tick it would visibly step.
local TRANSITION_MS = 2500
local function enabled()
    local config = Config and Config.WorldSync or {}
    if config.mode == 'disabled' or world.enabled == false then return false end
    if config.mode == 'auto' then
        for _, name in ipairs(config.externalResources or {}) do if GetResourceState(name) == 'started' then return false end end
    end
    return config.mode == nil or config.mode == 'auto' or config.mode == 'cortex'
end
local function releaseWorld()
    if not applied then return end
    applied = false
    timeApplied, weatherApplied, timeTransition = false, false, nil
    PauseClock(false)
    NetworkClearClockTimeOverride()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetBlackout(false)
    if Admin.applyVmenuWorldState then Admin.applyVmenuWorldState({ vehicleBlackout = true, snowEffects = false, cloudHat = '' }) end
end
local function toolsPreview()
    if GetResourceState('cortex-tools') ~= 'started' then return false end
    local ok, active = pcall(function() return exports['cortex-tools']:IsEnvironmentPreviewActive() end)
    return ok and active == true
end
-- Another resource holds this client's world: a cortex-tools preview, or a scene (multicharacter,
-- interiors) that set the Renewed-Weathersync convention `syncWeather = false`.
local function worldHeld()
    return not enabled() or toolsPreview() or LocalPlayer.state.syncWeather == false
end
local function restoreWeather(transition)
    if world.weatherEnabled == false then return end
    if type(world.weather) == 'string' then
        weatherApplied = true
        applied = true
        if transition and (world.weatherTransition or 0) > 0 then
            ClearOverrideWeather()
            SetWeatherTypeOvertimePersist(world.weather, world.weatherTransition + 0.0)
            return
        end
        SetWeatherTypeNowPersist(world.weather)
        SetOverrideWeather(world.weather)
    end
end

-- While cortex-weather owns the clock, Freeze Time mirrors the clock it publishes,
-- including freezes made from its own editor or console.
local function mirrorWeatherClock(clock)
    if world.owner ~= 'cortex-weather' or type(clock) ~= 'table' then return end
    Admin.state.toggles['world.freezeTime'] = clock.frozen == true
    if Admin.state.open then
        SendNUIMessage({ action = 'cortex-admin:setState', data = { toggles = Admin.state.toggles } })
    end
end
AddStateBagChangeHandler('cortexWeather:clock', 'global', function(_, _, value) mirrorWeatherClock(value) end)

local function requestSnapshot()
    local now = GetGameTimer()
    if (now - lastRequest) % 4294967296 < 2000 then return end
    lastRequest = now
    TriggerServerEvent('cortex-admin:server:requestWorldState')
end

function Admin.restoreWorldClock()
    local preview = worldHeld()
    if previewWasActive and not preview and receivedAt ~= nil and world.weatherEnabled ~= false then
        restoreWeather()
        SetBlackout(world.blackout == true)
        if Admin.applyVmenuWorldState then Admin.applyVmenuWorldState(world) end
    end
    previewWasActive = preview
    if receivedAt == nil or Admin.vehicleStudioClockActive or preview then return end
    if world.timeEnabled == false then
        if timeApplied then PauseClock(false); NetworkClearClockTimeOverride(); timeApplied = false end
        return
    end
    local elapsed = world.freezeTime and 0 or ((GetGameTimer() - receivedAt) % 4294967296) * 60 / world.millisecondsPerGameMinute
    local seconds = math.floor((world.hour * 3600 + world.minute * 60 + world.second + elapsed) % 86400)
    if timeTransition then
        local fraction = math.min(1, ((GetGameTimer() - timeTransition.at) % 4294967296) / TRANSITION_MS)
        local eased = 1 - (1 - fraction) ^ 3
        seconds = math.floor((seconds + timeTransition.offset * (1 - eased)) % 86400)
        if fraction >= 1 then timeTransition = nil end
    end
    PauseClock(world.freezeTime)
    applied = true
    timeApplied = true
    NetworkOverrideClockTime(math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

-- Local notification also covers previews shorter than the normal 250 ms clock tick.
AddEventHandler('cortex-tools:environmentReleased', function()
    if receivedAt == nil or worldHeld() then return end
    previewWasActive = false
    restoreWeather()
    Admin.restoreWorldClock()
end)

RegisterNetEvent('cortex-admin:client:updateWorldState', function(payload)
    if type(payload) ~= 'table' then return end
    local function valid(value, low, high)
        return type(value) == 'number' and value == value and value >= low and value <= high
    end
    if not valid(payload.hour, 0, 23) or payload.hour % 1 ~= 0
        or not valid(payload.minute, 0, 59) or payload.minute % 1 ~= 0
        or not valid(payload.second, 0, 60) or payload.second >= 60
        or not valid(payload.millisecondsPerGameMinute, 100, 3600000)
        or not valid(payload.sequence, 0, 9007199254740991) or type(payload.epoch) ~= 'string'
        or type(payload.freezeTime) ~= 'boolean' then return end
    if payload.epoch == epoch and payload.sequence <= sequence then return end
    if receivedAt and payload.epoch == epoch and payload.smoothTime and not worldHeld() then
        local elapsed = world.freezeTime and 0 or ((GetGameTimer() - receivedAt) % 4294967296) * 60 / world.millisecondsPerGameMinute
        local previous = world.hour * 3600 + world.minute * 60 + world.second + elapsed
        local nextTime = payload.hour * 3600 + payload.minute * 60 + payload.second
        local difference = (previous - nextTime + 43200) % 86400 - 43200
        if math.abs(difference) > 60 then timeTransition = { at = GetGameTimer(), offset = difference } end
    elseif payload.epoch ~= epoch then timeTransition = nil end
    local hadSnapshot = receivedAt ~= nil
    epoch, sequence, receivedAt = payload.epoch, payload.sequence, GetGameTimer()
    local previousWeather = world.weather
    for key, value in pairs(payload) do world[key] = value end
    if not enabled() then
        releaseWorld()
        mirrorWeatherClock(GlobalState['cortexWeather:clock'])
        if Admin.hasMenuAccess and Admin.hasMenuAccess() then TriggerServerEvent('cortex-admin:server:requestPermissions') end
        return
    end
    Admin.restoreWorldClock()
    if not worldHeld() and (not hadSnapshot or world.weather ~= previousWeather) then restoreWeather(hadSnapshot) end
    if not worldHeld() and world.weatherEnabled ~= false then SetBlackout(world.blackout == true) end
    if world.weatherEnabled == false and weatherApplied then
        ClearOverrideWeather(); ClearWeatherTypePersist(); SetBlackout(false); weatherApplied = false
        if Admin.applyVmenuWorldState then Admin.applyVmenuWorldState({ vehicleBlackout = true, snowEffects = false, cloudHat = '' }) end
    end
    Admin.state.toggles['world.freezeTime'] = world.freezeTime
    Admin.state.toggles['world.blackout'] = world.blackout == true
    if not worldHeld() and world.weatherEnabled ~= false and Admin.applyVmenuWorldState then Admin.applyVmenuWorldState(world) end
    if Admin.state.open then
        SendNUIMessage({ action = 'cortex-admin:setState', data = {
            toggles = Admin.state.toggles, gameHour = world.hour, gameMinute = world.minute, currentWeather = world.weather,
        } })
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() then requestSnapshot() end
    if not enabled() then releaseWorld() end
end)
AddEventHandler('playerSpawned', requestSnapshot)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or receivedAt == nil then return end
    if not worldHeld() then releaseWorld() end
end)

CreateThread(function()
    while true do
        if receivedAt == nil then requestSnapshot() else Admin.restoreWorldClock() end
        Wait((receivedAt == nil or not enabled()) and 2000 or timeTransition and 0 or 250)
    end
end)
