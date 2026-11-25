-- One authoritative clock and complete world snapshot for every player.
local Server = EsAdminServer
local config = Config.WorldSync or {}
local function setting(name, fallback)
    if EsAdminVmenuPolicy then return EsAdminVmenuPolicy.get(name, fallback) end
    return fallback
end
local rate = math.max(100, math.min(3600000, setting('vmenu_ingame_minute_duration', tonumber(config.millisecondsPerGameMinute) or 2000)))
local storageKey = 'cortex-admin_world_state_v1'
local epoch = ('%d:%d'):format(os.time(), GetGameTimer())
local sequence = 0
local anchor = GetGameTimer()
local world = {
    hour = setting('vmenu_current_hour', 12), minute = setting('vmenu_current_minute', 0), second = 0,
    freezeTime = setting('vmenu_freeze_time', false), weather = setting('vmenu_current_weather', 'CLEAR'):upper(),
    blackout = setting('vmenu_blackout_enabled', false), dynamicWeather = setting('vmenu_enable_dynamic_weather', false),
    vehicleBlackout = setting('vmenu_vehicle_blackout_enabled', false), snowEffects = setting('vmenu_enable_snow', false), cloudHat = '',
}
Server.worldState = world
function Server.ownsWorld()
    if config.mode == 'disabled' then return false, 'disabled' end
    if config.mode == 'auto' then
        for _, resource in ipairs(config.externalResources or {}) do
            if GetResourceState(resource) == 'started' then return false, resource end
        end
    elseif config.mode ~= nil and config.mode ~= 'cortex' then
        return false, 'invalid world mode'
    end
    return true, 'cortex-admin'
end
-- cortex-weather owns the clock while it runs but takes changes through its exports,
-- so the time tools drive its clock instead of standing down.
function Server.weatherOwnsClock()
    local owns, owner = Server.ownsWorld()
    return not owns and owner == 'cortex-weather'
end
local sharedWorldActions = { ['world.time'] = true, ['world.exactTime'] = true, ['world.freezeTime'] = true,
    ['world.weather'] = true, ['world.blackout'] = true, ['world.dynamicWeather'] = true,
    ['world.vehicleBlackout'] = true, ['world.snowEffects'] = true, ['world.randomClouds'] = true, ['world.removeClouds'] = true }
function Server.worldActionAvailable(actionId)
    if not sharedWorldActions[actionId] then return true end
    local time = actionId == 'world.time' or actionId == 'world.exactTime' or actionId == 'world.freezeTime'
    if time and (not setting('vmenu_enable_time_sync', true) or setting('vmenu_sync_to_machine_time', false)) then return false end
    if not time and not setting('vmenu_enable_weather_sync', true) then return false end
    if time and Server.weatherOwnsClock() then return true end
    return Server.ownsWorld()
end

local function validNumber(value, low, high)
    return type(value) == 'number' and value == value and value >= low and value <= high
end

local function assignSeconds(target, seconds)
    seconds = seconds % 86400
    target.hour = math.floor(seconds / 3600)
    target.minute = math.floor(seconds / 60) % 60
    target.second = seconds % 60
end

local stored = GetResourceKvpString(storageKey)
if stored then
    local ok, saved = pcall(json.decode, stored)
    if ok and type(saved) == 'table' and saved.version == 1 and type(saved.state) == 'table' then
        local value = saved.state
        if validNumber(value.hour, 0, 23) and value.hour % 1 == 0
            and validNumber(value.minute, 0, 59) and value.minute % 1 == 0
            and validNumber(value.second, 0, 60) and value.second < 60 then
            for key in pairs(world) do
                if type(value[key]) == type(world[key]) then world[key] = value[key] end
            end
            if not world.freezeTime and validNumber(saved.savedAt, 0, os.time()) then
                assignSeconds(world, world.hour * 3600 + world.minute * 60 + world.second + (os.time() - saved.savedAt) * 60000 / rate)
            end
        end
    end
end

function Server.getWorldSnapshot()
    local snapshot = {}
    for key, value in pairs(world) do snapshot[key] = value end
    local elapsed = world.freezeTime and 0 or ((GetGameTimer() - anchor) % 4294967296) * 60 / rate
    assignSeconds(snapshot, world.hour * 3600 + world.minute * 60 + world.second + elapsed)
    if setting('vmenu_sync_to_machine_time', false) then
        local current = os.date('*t')
        snapshot.hour, snapshot.minute, snapshot.second = current.hour, current.min, current.sec
        snapshot.freezeTime = false
    end
    snapshot.millisecondsPerGameMinute = rate
    if setting('vmenu_sync_to_machine_time', false) then snapshot.millisecondsPerGameMinute = 60000 end
    snapshot.timeEnabled = setting('vmenu_enable_time_sync', true)
    snapshot.weatherEnabled = setting('vmenu_enable_weather_sync', true)
    snapshot.weatherTransition = setting('vmenu_weather_change_duration', 30)
    snapshot.smoothTime = setting('vmenu_smooth_time_transitions', true)
    snapshot.epoch, snapshot.sequence = epoch, sequence
    snapshot.enabled, snapshot.owner = Server.ownsWorld()
    return snapshot
end

function Server.anchorWorldTime(hour, minute, second)
    world.hour, world.minute, world.second = hour, minute, second or 0
    anchor = GetGameTimer()
end

local function weatherClock(call)
    local ok, done = pcall(function() return call(exports['cortex-weather']) end)
    return ok and done == true
end

-- Returns false when cortex-weather owns the clock and refused or failed the change.
function Server.setWorldClock(hour, minute)
    if Server.weatherOwnsClock() then
        return weatherClock(function(weather) return weather:setTime(hour, minute) end)
    end
    Server.anchorWorldTime(hour, minute, 0)
    return true
end

function Server.freezeWorldTime(enabled)
    if Server.weatherOwnsClock() then
        return weatherClock(function(weather) return weather:freezeTime(enabled) end)
    end
    local current = Server.getWorldSnapshot()
    Server.anchorWorldTime(current.hour, current.minute, current.second)
    world.freezeTime = enabled
    return true
end

function Server.saveWorldState()
    local encoded = json.encode({ version = 1, savedAt = os.time(), state = Server.getWorldSnapshot() })
    SetResourceKvp(storageKey, encoded)
end

function Server.publishWorldState(target, persist)
    sequence = sequence + 1
    local snapshot = Server.getWorldSnapshot()
    if persist then Server.saveWorldState() end
    TriggerClientEvent('cortex-admin:client:updateWorldState', target or -1, snapshot)
end

RegisterNetEvent('cortex-admin:server:requestWorldState', function()
    local src = source
    -- Reading public environment state must not require opening the admin menu.
    if not Server.allowRequest(src, 'world-read', 6, 5000) then return end
    Server.publishWorldState(src)
end)

AddEventHandler('playerJoining', function() Server.publishWorldState(source) end)
local function ownershipChanged(resource)
    for _, name in ipairs(config.externalResources or {}) do
        if name == resource then
            if Server.invalidatePermissions then Server.invalidatePermissions() end
            Server.publishWorldState(-1)
            return
        end
    end
end
AddEventHandler('onResourceStart', ownershipChanged)
AddEventHandler('onResourceStop', ownershipChanged)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Server.saveWorldState() end
end)

CreateThread(function()
    while true do
        Wait(15000)
        if Server.ownsWorld() then Server.publishWorldState(-1) end
    end
end)
