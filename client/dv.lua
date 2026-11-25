-- Standalone vehicle command; no menu or chat resource is required.
local function bounded(value, fallback, low, high)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then value = fallback end
    return math.max(low, math.min(high, value))
end

local function findNearestVehicle(originCoords, maxDistance)
    local nearestVehicle = 0
    local nearestDistance = (maxDistance or 6.0) + 0.001
    local vehicles = GetGamePool('CVehicle')

    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if DoesEntityExist(vehicle) then
            local distance = #(GetEntityCoords(vehicle) - originCoords)
            if distance < nearestDistance then
                nearestDistance = distance
                nearestVehicle = vehicle
            end
        end
    end

    return nearestVehicle
end

-- /dv - Delete current or nearest vehicle
-- ============================================================
if Config.Dv and Config.Dv.Enabled then
    local lastDvRequestAt = nil
    RegisterCommand('dv', function()
        local now = GetGameTimer()
        local cooldown = bounded(Config.Dv.CooldownMs, 1500, 1000, 60000)
        if lastDvRequestAt and now >= lastDvRequestAt and now - lastDvRequestAt < cooldown then return end
        lastDvRequestAt = now
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle == 0 then
            local range = bounded(Config.Dv.Range, 6, 1.5, 25)
            vehicle = findNearestVehicle(GetEntityCoords(ped), range)
        end

        if vehicle == 0 or not DoesEntityExist(vehicle) then
            EsAdmin.notify('error', 'No nearby vehicle found.')
            return
        end
        if not NetworkGetEntityIsNetworked(vehicle) then
            EsAdmin.notify('error', 'This vehicle is not networked and cannot be deleted with /dv.')
            return
        end
        TriggerServerEvent('cortex-admin:server:deleteVehicle', NetworkGetNetworkIdFromEntity(vehicle))
    end, false)
end
