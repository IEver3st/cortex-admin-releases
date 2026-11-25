-- /dv is owned by Cortex Admin; all entity validation and deletion is server-side.
local playerLastDvAt = {}
local pendingDv = {}

local function getNowMs()
    return GetGameTimer()
end

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function bounded(value, fallback, low, high)
    value = tonumber(value)
    if not finite(value) then value = fallback end
    return math.max(low, math.min(high, value))
end

local function entityCoords(entity)
    if entity == 0 or not DoesEntityExist(entity) then return nil end
    local coords = GetEntityCoords(entity)
    if not coords or not finite(coords.x) or not finite(coords.y) or not finite(coords.z) then return nil end
    return coords
end

local function inRange(a, b, range)
    if not a or not b then return false end
    local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
    return x * x + y * y + z * z <= range * range
end

local function canDeleteVehicle(src)
    if type(src) ~= 'number' or src ~= src or src < 1 or src % 1 ~= 0 or not GetPlayerName(src) then return false end
    if not Config.Dv or Config.Dv.Enabled ~= true then return false end
    if Config.Dv.RequirePermission == false then return true end
    return EsAdminServer.hasPermission(src, 'vehicle.delete') == true
end

local function dvResult(src, ok, message)
    TriggerClientEvent('cortex-admin:client:notify', src, ok and 'success' or 'error', message)
end

RegisterNetEvent('cortex-admin:server:deleteVehicle', function(netId)
    local src = source
    if type(src) ~= 'number' or src <= 0 or not GetPlayerName(src) then return end
    local now = getNowMs()
    local cooldown = bounded(Config.Dv and Config.Dv.CooldownMs, 1500, 1000, 60000)
    local last = playerLastDvAt[src]
    if pendingDv[src] or (last and now >= last and now - last < cooldown) then return end
    playerLastDvAt[src] = now -- denied/malformed requests also consume the slot
    if not canDeleteVehicle(src) then
        dvResult(src, false, 'You do not have permission to use /dv.')
        return
    end
    if not finite(netId) or netId % 1 ~= 0 or netId < 1 or netId > 65535 then
        dvResult(src, false, 'No valid networked vehicle selected.')
        return
    end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local ped = GetPlayerPed(src)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2
        or GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src)
        or not inRange(entityCoords(ped), entityCoords(vehicle), bounded(Config.Dv.Range, 6, 1.5, 25)) then
        dvResult(src, false, 'Vehicle unavailable or outside your deletion range.')
        return
    end
    local driver = GetPedInVehicleSeat(vehicle, -1)
    if driver ~= 0 and driver ~= ped then
        dvResult(src, false, 'You cannot delete a vehicle with another driver.')
        return
    end
    if GetVehiclePedIsIn(ped, false) == vehicle and driver ~= ped then
        dvResult(src, false, 'You must be the driver to delete your current vehicle.')
        return
    end
    for _, player in ipairs(GetPlayers()) do
        local other = tonumber(player)
        local otherPed = other and GetPlayerPed(other) or 0
        if other ~= src and otherPed ~= 0 and GetVehiclePedIsIn(otherPed, false) == vehicle then
            dvResult(src, false, 'Another player is inside that vehicle.')
            return
        end
    end
    -- No yield between validation and mutation; only the server deletes entities.
    local token = {}
    pendingDv[src] = token
    DeleteEntity(vehicle)
    SetTimeout(500, function()
        -- A dropped/recycled source must never receive this session's result.
        if pendingDv[src] ~= token then return end
        pendingDv[src] = nil
        if not GetPlayerName(src) then return end
        local deleted = not DoesEntityExist(vehicle)
        dvResult(src, deleted, deleted and 'Vehicle deleted.'
            or 'Vehicle removal was not confirmed. Check the vehicle before retrying.')
    end)
end)

AddEventHandler('playerDropped', function()
    playerLastDvAt[source] = nil
    pendingDv[source] = nil
end)
