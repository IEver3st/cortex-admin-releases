-- Ordinary Qbox garage spawning. The marked Cortex inventory provider owns its
-- own transaction; never bypass that provider with this path.
local Server = EsAdminServer
local pending, count, generation = {}, 0, 0
local claims = {}
local vehicleTypes = { automobile = true, bike = true, boat = true, heli = true, plane = true,
    submarine = true, trailer = true, train = true }
local function trim(value) return type(value) == 'string' and value:match('^%s*(.-)%s*$') or '' end
local function update(query, values) return exports.oxmysql:update_async(query, values) end
local reserveQuery = 'UPDATE player_vehicles SET state = 0 WHERE id = ? AND citizenid = ? AND state = 1'
local restoreQuery = 'UPDATE player_vehicles SET state = 1 WHERE id = ? AND citizenid = ? AND state = 0'
local function erase(operation)
    local vehicle = operation.vehicle
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)
        and Entity(vehicle).state.cortexAdminOperation == operation.stamp then
        Entity(vehicle).state:set('persisted', nil, true)
        DeleteEntity(vehicle)
    end
end
-- Each reservation is journaled before its UPDATE is sent. If the resource stops
-- while that UPDATE is still in flight, the next start restores the row.
local JOURNAL = 'cortex-admin:garage-reservation:'
local function journal(id, cid, plate) SetResourceKvp(JOURNAL .. id, ('%s|%s|%d'):format(cid, plate, os.time())) end
local function settle(id) DeleteResourceKvp(JOURNAL .. id) end
local function alreadyOut(id, plate, except)
    for _, vehicle in ipairs(GetAllVehicles()) do
        if vehicle ~= except and DoesEntityExist(vehicle) and
            (Entity(vehicle).state.vehicleid == id or trim(GetVehicleNumberPlateText(vehicle)) == plate) then return true end
    end
    return false
end

function Server.spawnOwnedGarageVehicle(src, vehicleId)
    if pending[vehicleId] or count >= 16 then return nil, 'A vehicle spawn is already in progress. Wait a moment.' end
    if GetResourceMetadata('ox_inventory', 'cortex_inventory_bridge', 0) == '1' then return nil, 'Use the Cortex inventory owned-vehicle provider.' end
    local actor = exports.qbx_core:GetPlayer(src)
    local cid = actor and actor.PlayerData.citizenid
    local token = Server.playerSession(src)
    if not cid or not token then return nil, 'Your character is not loaded.' end
    local operation = { src = src, cid = cid, generation = generation, stamp = token .. ':' .. tostring(vehicleId) }
    pending[vehicleId], count = operation, count + 1
    local function current()
        if EsAdminBridge.clearPermCache then EsAdminBridge.clearPermCache(src) end
        -- Exports return a fresh copy of the player table on every call, so compare characters, not tables.
        local live = exports.qbx_core:GetPlayer(src)
        assert(operation.generation == generation and Server.targetSessionMatches(src, token)
            and live and live.PlayerData.citizenid == cid
            and Server.hasPermission(src, 'garage.spawnVehicle'), 'Character or permission changed during the spawn.')
    end
    local ok, result = pcall(function()
        local row = exports.qbx_vehicles:GetPlayerVehicle(vehicleId, { citizenid = cid })
        current()
        assert(row and row.id == vehicleId and row.citizenid == cid and row.state == 1,
            'This owned vehicle is out, impounded, or no longer in your garage.')
        local definitions = EsAdminBridge.getSharedVehicleList()
        local model = type(row.modelName) == 'string' and definitions[row.modelName]
        assert(model and vehicleTypes[model.type], 'Register this vehicle model and server spawn type in Qbox first.')
        assert(Server.authorizeModel(src, 'vehicle', row.modelName, 'garage.spawnVehicle'), 'This model is not permitted.')
        local plate = row.props and trim(row.props.plate)
        assert(plate and plate ~= '' and not alreadyOut(vehicleId, plate), 'This owned vehicle is already in the world.')
        -- Rollback matches by plate; a blank one would match unrelated vehicles.
        operation.plate = plate
        journal(vehicleId, cid, plate)
        local changed = update(reserveQuery, { vehicleId, cid })
        operation.reserved = changed == 1
        if not operation.reserved then settle(vehicleId) end
        assert(operation.reserved, 'Another garage operation already claimed this vehicle.')
        current()
        assert(not alreadyOut(vehicleId, plate), 'This owned vehicle is already in the world.')
        local ped = GetPlayerPed(src)
        local coords = ped and ped > 0 and DoesEntityExist(ped) and GetEntityCoords(ped)
        assert(coords, 'Your position is unavailable.')
        local heading = GetEntityHeading(ped) + 0.0
        local radians = math.rad(heading)
        local vehicle = CreateVehicleServerSetter(joaat(row.modelName), model.type,
            coords.x - math.sin(radians) * 4.0, coords.y + math.cos(radians) * 4.0, coords.z + 0.0, heading)
        operation.vehicle = vehicle
        assert(vehicle and vehicle ~= 0, 'The server could not create the vehicle.')
        local deadline = GetGameTimer() + 5000
        while not DoesEntityExist(vehicle) and GetGameTimer() < deadline do current(); Wait(50) end
        assert(DoesEntityExist(vehicle), 'Vehicle creation timed out.')
        Entity(vehicle).state:set('cortexAdminOperation', operation.stamp, false)
        current()
        SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
        SetEntityOrphanMode(vehicle, 2)
        Entity(vehicle).state:set('vehicleid', vehicleId, false)
        Entity(vehicle).state:set('initVehicle', true, true)
        SetPedIntoVehicle(ped, vehicle, -1)
        local owner = NetworkGetEntityOwner(vehicle)
        while (not owner or owner <= 0) and GetGameTimer() < deadline do
            current(); Wait(50); owner = NetworkGetEntityOwner(vehicle)
        end
        assert(owner and owner > 0, 'Vehicle initialization has no client owner.')
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        TriggerClientEvent('qbx_core:client:setVehicleProperties', owner, netId, row.props)
        while trim(GetVehicleNumberPlateText(vehicle)) ~= plate and GetGameTimer() < deadline do
            current(); assert(DoesEntityExist(vehicle), 'The spawned vehicle disappeared.'); Wait(50)
        end
        current()
        assert(trim(GetVehicleNumberPlateText(vehicle)) == plate, 'Vehicle properties did not initialize in time.')
        assert(not alreadyOut(vehicleId, plate, vehicle), 'Another copy of this vehicle appeared during initialization.')
        local stored = exports.qbx_vehicles:GetPlayerVehicle(vehicleId, { citizenid = cid })
        current()
        assert(stored and stored.citizenid == cid and stored.state == 0, 'Vehicle ownership or state changed during initialization.')
        assert(exports.qbx_vehicles:SaveVehicle(vehicle, { state = 0 }) == true, 'Vehicle state could not be saved.')
        stored = exports.qbx_vehicles:GetPlayerVehicle(vehicleId, { citizenid = cid })
        current()
        assert(stored and stored.citizenid == cid and stored.state == 0, 'Vehicle ownership or state changed before completion.')
        exports.qbx_core:EnablePersistence(vehicle)
        if GetResourceState('qbx_vehiclekeys') == 'started' then exports.qbx_vehiclekeys:GiveKeys(src, vehicle) end
        current()
        operation.completed = true
        settle(vehicleId)
        Entity(vehicle).state:set('cortexAdminOperation', nil, false)
        return netId
    end)
    if not ok then
        erase(operation)
        if operation.reserved and not alreadyOut(vehicleId, operation.plate or '') then
            local restored, reason = pcall(update, restoreQuery, { vehicleId, cid })
            if restored then settle(vehicleId)
            else print(('[cortex-admin] Garage rollback failed for #%s: %s'):format(vehicleId, tostring(reason))) end
        elseif operation.reserved then settle(vehicleId) end
    end
    pending[vehicleId], count = nil, count - 1
    if ok then return result end
    return nil, tostring(result)
end

-- Admin Car claims the current unowned entity. It does not manufacture a
-- second, garaged copy while that entity is still in the world.
function Server.claimAdminVehicle(src, vehicle, props)
    local cid = EsAdminBridge.getPlayerCitizenId(src)
    local token = Server.playerSession(src)
    local hash, plate = GetEntityModel(vehicle), trim(GetVehicleNumberPlateText(vehicle))
    if not cid or not token or plate == '' or claims[plate] then return nil, 'This vehicle save is unavailable or already in progress.' end
    local modelName
    for name in pairs(EsAdminBridge.getSharedVehicleList()) do
        if (joaat(name) & 0xffffffff) == (hash & 0xffffffff) then modelName = name; break end
    end
    if not modelName then return nil, 'Register this model in Qbox before saving it as an owned vehicle.' end
    local operation = { generation = generation, vehicle = vehicle }
    claims[plate] = operation
    local function current()
        if EsAdminBridge.clearPermCache then EsAdminBridge.clearPermCache(src) end
        assert(operation.generation == generation and Server.targetSessionMatches(src, token)
            and EsAdminBridge.getPlayerCitizenId(src) == cid and Server.hasPermission(src, 'vehicle.adminCar')
            and DoesEntityExist(vehicle) and GetEntityModel(vehicle) == hash
            and trim(GetVehicleNumberPlateText(vehicle)) == plate
            and GetVehiclePedIsIn(GetPlayerPed(src), false) == vehicle, 'Player or vehicle changed before saving.')
    end
    local ok, result = pcall(function()
        current()
        assert(not Entity(vehicle).state.vehicleid, 'This entity already belongs to an owned vehicle.')
        local existing = exports.qbx_vehicles:GetVehicleIdByPlate(plate)
        current()
        assert(not existing, 'This plate is already registered. Admin Car cannot copy or transfer it.')
        props.plate, props.model = plate, hash
        local id = exports.qbx_vehicles:CreatePlayerVehicle({ model = modelName, citizenid = cid, props = props })
        assert(type(id) == 'number' and id > 0, 'The vehicle provider refused the ownership claim.')
        operation.id, operation.cid = id, cid
        current()
        local row = exports.qbx_vehicles:GetPlayerVehicle(id, { citizenid = cid })
        current()
        assert(row and row.citizenid == cid and row.modelName == modelName and row.state == 0,
            'The ownership claim could not be verified.')
        Entity(vehicle).state:set('vehicleid', id, false)
        if GetResourceMetadata('ox_inventory', 'cortex_inventory_bridge', 0) == '1' then
            assert(exports['cortex-inventory']:BindVehicle(NetworkGetNetworkIdFromEntity(vehicle), id),
                'The owned vehicle inventory binding was refused.')
        end
        current()
        exports.qbx_core:EnablePersistence(vehicle)
        if GetResourceState('qbx_vehiclekeys') == 'started' then exports.qbx_vehiclekeys:GiveKeys(src, vehicle) end
        current()
        operation.completed = true
        return id
    end)
    if not ok and operation.id then
        if DoesEntityExist(vehicle) and Entity(vehicle).state.vehicleid == operation.id then
            Entity(vehicle).state:set('vehicleid', nil, false)
            Entity(vehicle).state:set('persisted', nil, true)
        end
        local removed, reason = pcall(function() return exports.qbx_vehicles:DeletePlayerVehicles('vehicleId', operation.id) end)
        if not removed or reason ~= true then print(('[cortex-admin] Admin Car rollback needs review for #%s: %s'):format(operation.id, tostring(reason))) end
    end
    claims[plate] = nil
    if ok then return result end
    return nil, tostring(result)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    generation = generation + 1
    for id, operation in pairs(pending) do
        if not operation.completed then
            erase(operation)
            -- No restore is sent from here: an unawaited UPDATE could land after the
            -- next start has settled and respawned the car. The journal entry stays,
            -- and the next start restores the row.
        end
    end
    for _, operation in pairs(claims) do
        if not operation.completed and operation.id then
            local vehicle = operation.vehicle
            if DoesEntityExist(vehicle) and Entity(vehicle).state.vehicleid == operation.id then
                Entity(vehicle).state:set('vehicleid', nil, false)
                Entity(vehicle).state:set('persisted', nil, true)
            end
            -- Dispatch through the owning provider, including its inventory fence.
            -- The provider owns the database call even if the caller stops.
            local ok, result = pcall(function() return exports.qbx_vehicles:DeletePlayerVehicles('vehicleId', operation.id) end)
            if not ok or result ~= true then
                print(('[cortex-admin] Stopped Admin Car claim needs review for #%s: %s'):format(operation.id, tostring(result)))
            end
        end
    end
end)

-- Restore reservations interrupted by a stop or crash. Each journaled vehicle is
-- locked against new spawns for RECOVERY_WINDOW seconds from the start of recovery,
-- and the restore is repeated until then: a reserve or rollback UPDATE sent by the
-- previous instance can still land late, and it must land while nothing can spawn
-- the car. Database errors are retried until the database answers.
local RECOVERY_WINDOW = 120
CreateThread(function()
    local warnAt = GetGameTimer() + 120000
    while GetResourceState('oxmysql') ~= 'started' do
        if warnAt and GetGameTimer() > warnAt then
            print('[cortex-admin] Garage recovery is waiting for oxmysql to start.'); warnAt = nil
        end
        Wait(1000)
    end
    local startedAt = os.time()
    local entries, keys = {}, {}
    local handle = StartFindKvp(JOURNAL)
    if handle and handle ~= -1 then
        repeat
            local key = FindKvp(handle)
            if key then keys[#keys + 1] = key end
        until not key
        EndFindKvp(handle)
    end
    for _, key in ipairs(keys) do
        local id = tonumber(key:sub(#JOURNAL + 1))
        local cid, plate, at = (GetResourceKvpString(key) or ''):match('^([^|]+)|([^|]+)|(%d+)$')
        if id and cid and not pending[id] then
            pending[id] = { recovery = true }
            entries[#entries + 1] = { id = id, cid = cid, plate = plate, at = tonumber(at) }
        elseif not id or not cid then DeleteResourceKvp(key) end
    end
    while #entries > 0 do
        for index = #entries, 1, -1 do
            local entry = entries[index]
            local expired = os.time() - math.max(entry.at, startedAt) >= RECOVERY_WINDOW
            local done = alreadyOut(entry.id, entry.plate)
            if not done then
                local ok, changed = pcall(update, restoreQuery, { entry.id, entry.cid })
                if not ok then
                    if not entry.warned then
                        print(('[cortex-admin] Garage recovery for #%s will retry: %s'):format(entry.id, tostring(changed)))
                        entry.warned = true
                    end
                else
                    if changed == 1 and not entry.restored then
                        print(('[cortex-admin] Restored interrupted garage reservation #%s.'):format(entry.id))
                        entry.restored = true
                    end
                    done = expired
                end
            end
            if done then
                settle(entry.id)
                if pending[entry.id] and pending[entry.id].recovery then pending[entry.id] = nil end
                table.remove(entries, index)
            end
        end
        if #entries > 0 then Wait(10000) end
    end
end)
