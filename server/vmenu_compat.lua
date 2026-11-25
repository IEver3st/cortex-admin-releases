local Server = EsAdminServer
local nativeAce = IsPlayerAceAllowed
local function IsPlayerAceAllowed(src, ace)
    if Server.vmenuAce and ace:sub(1, 6) == 'vMenu.' then return Server.vmenuAce(src, ace) end
    return nativeAce(src, ace)
end
local resourceName = GetCurrentResourceName()
local spectating = {}
Server.spectatingTarget = function(src) return spectating[src] end
local pendingBanImports = {}
local pendingModelAuthorizations = {}
local personalVehicles = {}
local privateMessagesDisabled = {}
local lastVehicleSpawn = {}

local MAX_CONFIG_DOMAIN_BYTES = 2 * 1024 * 1024
local MAX_CONFIG_STORE_BYTES = 4 * 1024 * 1024
local CONFIG_DOMAIN_BPS = 512 * 1024
local CONFIG_DOMAINS = {
    addons = true,
    extras = true,
    locations = true,
    modelWhitelists = true,
    tattoos = true,
}

local extendedWorldState = Server.worldState
local cloudHats = { 'Cirrus', 'Cloudy 01', 'Contrails', 'Horizon', 'Nimbus', 'Puffs', 'RAIN', 'Snowy 01', 'Stormy 01', 'Wispy' }

local weatherCycle = {
    'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'CLEARING', 'RAIN', 'THUNDER', 'FOGGY', 'SMOG',
}
local weatherIndex = 1

local configStore = {
    version = 1,
    domains = {},
}

local function trim(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$')
    if value == '' then return nil end
    if maxLength and #value > maxLength then value = value:sub(1, maxLength) end
    return value
end

local function integer(value, minValue, maxValue)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge or value ~= math.floor(value) then return nil end
    if minValue and value < minValue or maxValue and value > maxValue then return nil end
    return value
end

local function allowed(src, actionId)
    return Server and Server.hasPermission and Server.hasPermission(src, actionId) == true
end

local function rate(src, bucket, count, window)
    return Server and Server.allowRequest and Server.allowRequest(src, bucket, count, window) == true
end

local function resolvePersonalVehicle(src)
    local session = personalVehicles[src]
    if type(session) ~= 'table' then return nil end
    local vehicle = NetworkGetEntityFromNetworkId(session.networkId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        personalVehicles[src] = nil
        return nil
    end
    if GetEntityModel(vehicle) ~= session.model
        or GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src) then
        personalVehicles[src] = nil
        return nil
    end
    return vehicle, session
end

local MODEL_RULES = {
    vehicle = {
        keys = { 'whitelistedvehicle', 'whitelistedvehicles' },
        acePrefix = 'vMenu.VehicleSpawner.WhitelistedModels',
    },
    ped = {
        keys = { 'whitelistedpeds' },
        acePrefix = 'vMenu.PlayerAppearance.WhitelistedModels',
    },
    weapon = {
        keys = { 'whitelistedweapons' },
        acePrefix = 'vMenu.WeaponOptions.WhitelistedModels',
    },
}

local MODEL_ACTIONS = {
    vehicle = {
        ['vehicle.spawn'] = true,
        ['vehicle.personal'] = true,
        ['vehicle.load'] = true,
        ['garage.spawnVehicle'] = true,
        ['qbx.giveVehicle'] = true,
        ['vehicle.giveKeys'] = true,
        ['dev.spawnEntity'] = true,
    },
    ped = {
        ['player.setModel'] = true,
        ['player.loadPed'] = true,
        ['player.loadMpPed'] = true,
        ['player.randomizeAppearance'] = true,
        ['dev.spawnEntity'] = true,
    },
    weapon = {
        ['weapons.give'] = true,
        ['weapons.giveCustom'] = true,
        ['weapons.giveAll'] = true,
        ['weapons.loadLoadout'] = true,
        ['weapons.restoreLoadoutOnRespawn'] = true,
        ['weapons.parachute'] = true,
        ['weapons.primaryParachute'] = true,
        ['weapons.unlimitedParachutes'] = true,
        ['weapons.autoEquipParachute'] = true,
    },
}

local modelWhitelistIndex = {
    vehicle = { names = {}, hashes = {}, count = 0 },
    ped = { names = {}, hashes = {}, count = 0 },
    weapon = { names = {}, hashes = {}, count = 0 },
}

local function unsignedHash(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge
        or number ~= math.floor(number) then return nil end
    if number < 0 then number = number + 4294967296 end
    if number < 0 or number > 4294967295 then return nil end
    return number
end

local function normalizeModelName(kind, value)
    if type(value) ~= 'string' then return nil end
    local name = trim(value, 64)
    if not name then return nil end
    name = name:lower()
    if not name:match('^[%w_%-]+$') then return nil end
    if kind == 'weapon' and name ~= 'gadget_parachute' and name:sub(1, 7) ~= 'weapon_' then
        name = 'weapon_' .. name
    end
    return name
end

local function modelHashForName(name)
    if type(name) ~= 'string' or not joaat then return nil end
    return unsignedHash(joaat(name))
end

local function aceModelSuffix(kind, name)
    if kind == 'weapon' and name:sub(1, 7) == 'weapon_' then return name:sub(8) end
    return name
end

local function refreshModelWhitelistIndex()
    modelWhitelistIndex = {
        vehicle = { names = {}, hashes = {}, count = 0 },
        ped = { names = {}, hashes = {}, count = 0 },
        weapon = { names = {}, hashes = {}, count = 0 },
    }

    local domain = configStore.domains and configStore.domains.modelWhitelists
    local data = type(domain) == 'table' and domain.data or nil
    if type(data) ~= 'table' then return end

    for kind, rule in pairs(MODEL_RULES) do
        local index = modelWhitelistIndex[kind]
        for keyIndex = 1, #rule.keys do
            local entries = data[rule.keys[keyIndex]]
            if type(entries) == 'table' then
                for entryIndex = 1, math.min(#entries, 20000) do
                    local name = normalizeModelName(kind, entries[entryIndex])
                    if name and not index.names[name] then
                        local descriptor = {
                            name = name,
                            ace = rule.acePrefix .. '.' .. aceModelSuffix(kind, name),
                        }
                        index.names[name] = descriptor
                        local hash = modelHashForName(name)
                        if hash then
                            index.hashes[hash] = index.hashes[hash] or {}
                            index.hashes[hash][#index.hashes[hash] + 1] = descriptor
                        end
                        index.count = index.count + 1
                    end
                end
            end
        end
    end
end

local function requiredModelDescriptors(kind, model)
    local index = modelWhitelistIndex[kind]
    if not index then return nil, 'invalid_kind' end
    if type(model) == 'string' then
        local name = normalizeModelName(kind, model)
        if not name then return nil, 'invalid_model' end
        local descriptor = index.names[name]
        if descriptor then return { descriptor }, nil, name end
        local hash = modelHashForName(name)
        return hash and index.hashes[hash] or nil, nil, name
    end
    local hash = unsignedHash(model)
    if not hash then return nil, 'invalid_model' end
    return index.hashes[hash], nil, hash
end

local classSuffixes = {
    compacts = 'Compacts', sedans = 'Sedans', suvs = 'SUVs', coupes = 'Coupes', muscle = 'Muscle',
    sportsclassics = 'SportsClassic', sportsclassic = 'SportsClassic', sports = 'Sports', super = 'Super',
    motorcycles = 'Motorcycles', offroad = 'OffRoad', industrial = 'Industrial', utility = 'Utility',
    vans = 'Vans', cycles = 'Cycles', boats = 'Boats', helicopters = 'Helicopters', planes = 'Planes',
    service = 'Service', emergency = 'Emergency', military = 'Military', commercial = 'Commercial',
    trains = 'Trains', openwheel = 'OpenWheel',
}
local function approvedAddon(kind, name)
    local plural = kind == 'vehicle' and 'vehicles' or kind == 'ped' and 'peds' or 'weapons'
    local domain = configStore.domains.addons
    local imported = domain and domain.data and domain.data[plural]
    for _, entries in ipairs({ Config.VmenuAddonModels and Config.VmenuAddonModels[plural] or {}, imported or {} }) do
        for _, value in ipairs(entries) do
            if normalizeModelName(kind, value) == name then return true end
        end
    end
    return false
end
local vehicleRegistry, registryHashes = nil, {}
local function vehicleDefinitions()
    local values = EsAdminBridge.getSharedVehicleList and EsAdminBridge.getSharedVehicleList() or {}
    if values ~= vehicleRegistry then
        vehicleRegistry, registryHashes = values, {}
        for name in pairs(values) do
            local hash = modelHashForName(name)
            if hash then registryHashes[hash] = name end
        end
    end
    return values
end
local function resolvedName(kind, model)
    if type(model) == 'string' then return normalizeModelName(kind, model) end
    local hash = unsignedHash(model)
    if not hash then return nil end
    if kind == 'vehicle' then
        vehicleDefinitions()
        if registryHashes[hash] then return registryHashes[hash] end
        for name in pairs(Config.VmenuVehicleClasses or {}) do if modelHashForName(name) == hash then return name end end
    elseif kind == 'weapon' then
        for name in pairs(EsAdminVmenuWeaponAces or {}) do if modelHashForName(name) == hash then return name end end
    end
    local plural = kind == 'vehicle' and 'vehicles' or kind == 'ped' and 'peds' or 'weapons'
    local domain = configStore.domains.addons
    for _, list in ipairs({ Config.VmenuAddonModels and Config.VmenuAddonModels[plural] or {},
        domain and domain.data and domain.data[plural] or {} }) do
        for _, value in ipairs(list) do
            local name = normalizeModelName(kind, value)
            if name and modelHashForName(name) == hash then return name end
        end
    end
end
local function vmenuModelAllowed(src, kind, model, actionId)
    if Server.hasFullPermission(src) or Server.hasCortexPermission(src, actionId) then return true end
    if kind == 'ped' then
        -- Customize changes the current ped; it must not authorize model selection.
        -- Saved-ped actions already have their own SpawnSaved action gate.
        if actionId ~= 'player.setModel' then return true end
        if IsPlayerAceAllowed(src, 'vMenu.PlayerAppearance.All')
            or IsPlayerAceAllowed(src, 'vMenu.PlayerAppearance.SpawnNew') then return true end
        local name = resolvedName(kind, model)
        return name ~= nil and approvedAddon(kind, name)
            and IsPlayerAceAllowed(src, 'vMenu.PlayerAppearance.AddonPeds')
    end
    local name = resolvedName(kind, model)
    if not name then return false end
    if kind == 'weapon' then
        if IsPlayerAceAllowed(src, 'vMenu.WeaponOptions.All') then return true end
        local ace = (EsAdminVmenuWeaponAces or {})[name]
        if ace then return IsPlayerAceAllowed(src, ace) end
        return approvedAddon(kind, name) and IsPlayerAceAllowed(src, 'vMenu.WeaponOptions.Spawn')
    end
    if IsPlayerAceAllowed(src, 'vMenu.VehicleSpawner.All') then return true end
    local definition = vehicleDefinitions()[name]
    -- Stock models use the game's own class, as the class menus and vMenu's
    -- GetVehicleClassFromName do; Qbox categories only classify addons.
    local class = (Config.VmenuVehicleClasses or {})[name]
        or EsAdminVmenuReference and EsAdminVmenuReference.vehicleClasses[name]
        or definition and definition.category
    local suffix = type(class) == 'string' and classSuffixes[class:lower():gsub('[%s_%-]', '')]
    -- Upstream CommonFunctions.SpawnVehicle checks the class for every path,
    -- including typed names, addons and saved vehicles. Unknown classes fail closed.
    if not suffix or not IsPlayerAceAllowed(src, 'vMenu.VehicleSpawner.' .. suffix) then return false end
    if actionId == 'vehicle.spawn' and approvedAddon(kind, name) then
        return IsPlayerAceAllowed(src, 'vMenu.VehicleSpawner.Addon')
            or IsPlayerAceAllowed(src, 'vMenu.VehicleSpawner.SpawnByName')
    end
    return true
end

local function authorizeModel(src, kind, model, actionId)
    if kind == 'ped' and EsAdminIsUnsafePlayerPedModel(model) then return false, 'unsafe_player_model' end
    local rule = MODEL_RULES[kind]
    if not rule or not MODEL_ACTIONS[kind] or MODEL_ACTIONS[kind][actionId] ~= true then
        return false, 'invalid_action'
    end
    if not allowed(src, actionId) then return false, 'forbidden' end

    local descriptors, errorReason, normalized = requiredModelDescriptors(kind, model)
    if errorReason then return false, errorReason end
    if not vmenuModelAllowed(src, kind, model, actionId) then return false, 'model_forbidden', normalized end
    if type(descriptors) ~= 'table' or #descriptors == 0 then return true, nil, normalized end

    if Server.hasFullPermission(src)
        or IsPlayerAceAllowed(src, rule.acePrefix .. '.All') then
        return true, nil, normalized
    end
    for index = 1, #descriptors do
        if IsPlayerAceAllowed(src, descriptors[index].ace) then return true, nil, normalized end
    end
    return false, 'model_forbidden', normalized
end

Server.authorizeModel = authorizeModel
Server.refreshModelWhitelistIndex = refreshModelWhitelistIndex

local function buildAuthorizedModelSet(kind, models)
    local result = { names = {}, hashes = {} }
    for index = 1, #models do
        local model = models[index]
        if type(model) == 'string' then
            local name = normalizeModelName(kind, model)
            if name then
                result.names[name] = true
                local hash = modelHashForName(name)
                if hash then result.hashes[hash] = true end
            end
        else
            local hash = unsignedHash(model)
            if hash then result.hashes[hash] = true end
        end
    end
    return result
end

local function authorizedModelMatches(entry, kind, model)
    if type(entry) ~= 'table' or entry.kind ~= kind or type(entry.models) ~= 'table' then return false end
    if type(model) == 'string' then
        local name = normalizeModelName(kind, model)
        if not name then return false end
        if type(entry.models.names) == 'table' and entry.models.names[name] == true then return true end
        local hash = modelHashForName(name)
        return hash ~= nil and type(entry.models.hashes) == 'table' and entry.models.hashes[hash] == true
    end
    local hash = unsignedHash(model)
    return hash ~= nil and type(entry.models.hashes) == 'table' and entry.models.hashes[hash] == true
end

local function notify(src, kind, message)
    TriggerClientEvent('cortex-admin:client:vmenuNotice', src, kind, message)
end

local function safeCopy(value, depth, budget)
    local valueType = type(value)
    if valueType == 'boolean' then return value, true end
    if valueType == 'string' then
        if #value > 1024 then return nil, false end
        return value, true
    end
    if valueType == 'number' then
        if value ~= value or value == math.huge or value == -math.huge or math.abs(value) > 1000000000000 then return nil, false end
        return value, true
    end
    if valueType ~= 'table' or depth > 8 then return nil, false end

    local result = {}
    for key, entry in pairs(value) do
        budget.count = budget.count + 1
        if budget.count > 20000 then return nil, false end
        if type(key) == 'string' then
            if key == '' or #key > 128 then return nil, false end
        elseif type(key) == 'number' then
            if key ~= math.floor(key) or key < 0 or key > 20000 then return nil, false end
        else
            return nil, false
        end
        local clean, ok = safeCopy(entry, depth + 1, budget)
        if not ok then return nil, false end
        result[key] = clean
    end
    return result, true
end

local function tableCount(value)
    local count = 0
    if type(value) == 'table' then for _ in pairs(value) do count = count + 1 end end
    return count
end

-- vMenu's model-whitelists.json template contains // comments. Newtonsoft
-- accepts those comments, while CitizenFX's JSON decoder does not. Strip only
-- comments outside strings so imported model names and URLs remain untouched.
local function stripJsonComments(value)
    if type(value) ~= 'string' then return nil end
    local output = {}
    local index = 1
    local inString = false
    local escaped = false

    while index <= #value do
        local current = value:sub(index, index)
        local nextChar = value:sub(index + 1, index + 1)

        if inString then
            output[#output + 1] = current
            if escaped then
                escaped = false
            elseif current == '\\' then
                escaped = true
            elseif current == '"' then
                inString = false
            end
            index = index + 1
        elseif current == '"' then
            inString = true
            output[#output + 1] = current
            index = index + 1
        elseif current == '/' and nextChar == '/' then
            index = index + 2
            while index <= #value and value:sub(index, index) ~= '\n' and value:sub(index, index) ~= '\r' do
                index = index + 1
            end
        elseif current == '/' and nextChar == '*' then
            index = index + 2
            local closed = false
            while index <= #value do
                if value:sub(index, index) == '*' and value:sub(index + 1, index + 1) == '/' then
                    index = index + 2
                    closed = true
                    break
                end
                index = index + 1
            end
            if not closed then return nil end
        else
            output[#output + 1] = current
            index = index + 1
        end
    end

    if inString then return nil end
    return table.concat(output)
end

local function domainCount(domain, value)
    if type(value) ~= 'table' then return 0 end
    if domain == 'locations' then
        return (type(value.teleports) == 'table' and #value.teleports or 0)
            + (type(value.blips) == 'table' and #value.blips or 0)
    end
    if domain == 'addons' or domain == 'modelWhitelists' then
        local count = 0
        for _, entries in pairs(value) do
            if type(entries) == 'table' then count = count + #entries end
        end
        return count
    end
    if domain == 'extras' then
        local count = 0
        for _, entries in pairs(value) do
            if type(entries) == 'table' then count = count + tableCount(entries) end
        end
        return count
    end
    return #value > 0 and #value or tableCount(value)
end

local function saveConfigStore()
    local ok, encoded = pcall(json.encode, configStore)
    if not ok or type(encoded) ~= 'string' or #encoded > MAX_CONFIG_STORE_BYTES then return false end
    SetResourceKvp(Config.KvpKeys.vmenuServerImport, encoded)
    return true
end

local function loadConfigStore()
    local raw = GetResourceKvpString(Config.KvpKeys.vmenuServerImport)
    if not raw or raw == '' or #raw > MAX_CONFIG_STORE_BYTES then return end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' or decoded.version ~= 1 or type(decoded.domains) ~= 'table' then return end
    local clean, cleanOk = safeCopy(decoded, 1, { count = 0 })
    if cleanOk then configStore = clean end
end

local function findVmenuResource()
    local names = Config.VmenuCompatibility and Config.VmenuCompatibility.importResourceNames or { 'vMenu', 'vmenu' }
    for index = 1, #names do
        local candidate = trim(names[index], 64)
        if candidate and GetResourceState(candidate) ~= 'missing' then return candidate end
    end
    return nil
end

local function refreshConfigImport()
    local sourceResource = findVmenuResource()
    local result = { resource = sourceResource, imported = 0, failed = 0, unavailable = 0, domains = {} }
    local files = Config.VmenuCompatibility and Config.VmenuCompatibility.importConfigFiles or {}

    for domain, path in pairs(files) do
        local safeDomain = trim(domain, 48)
        local safePath = trim(path, 160)
        if safeDomain and CONFIG_DOMAINS[safeDomain] and safePath and sourceResource then
            local raw = LoadResourceFile(sourceResource, safePath)
            if type(raw) == 'string' and raw ~= '' and #raw <= MAX_CONFIG_DOMAIN_BYTES then
                local normalized = stripJsonComments(raw)
                local ok, decoded = false, nil
                if normalized then
                    ok, decoded = pcall(json.decode, normalized)
                end
                local clean, cleanOk
                if ok and type(decoded) == 'table' then clean, cleanOk = safeCopy(decoded, 1, { count = 0 }) end
                if cleanOk then
                    local encodedOk, encoded = pcall(json.encode, clean)
                    if encodedOk and type(encoded) == 'string' and #encoded <= MAX_CONFIG_DOMAIN_BYTES then
                        local previous = configStore.domains[safeDomain]
                        local candidate = {
                            data = clean,
                            sourceResource = sourceResource,
                            sourcePath = safePath,
                            importedAt = os.time(),
                            count = domainCount(safeDomain, clean),
                        }
                        configStore.domains[safeDomain] = candidate
                        local storeOk, storeEncoded = pcall(json.encode, configStore)
                        if storeOk and type(storeEncoded) == 'string' and #storeEncoded <= MAX_CONFIG_STORE_BYTES then
                            result.imported = result.imported + 1
                        else
                            configStore.domains[safeDomain] = previous
                            result.failed = result.failed + 1
                        end
                    else
                        result.failed = result.failed + 1
                    end
                else
                    result.failed = result.failed + 1
                end
            else
                result.unavailable = result.unavailable + 1
            end
        else
            result.unavailable = result.unavailable + 1
        end
    end

    if result.imported > 0 and not saveConfigStore() then
        result.failed = result.failed + result.imported
        result.imported = 0
    end
    refreshModelWhitelistIndex()
    result.domains = nil
    return result
end

local function compatibilityState(importResult)
    local domains = {}
    for domain, entry in pairs(configStore.domains) do
        domains[domain] = {
            available = type(entry) == 'table' and type(entry.data) == 'table',
            count = type(entry) == 'table' and integer(entry.count, 0, 20000) or 0,
            sourceResource = type(entry) == 'table' and entry.sourceResource or nil,
            sourcePath = type(entry) == 'table' and entry.sourcePath or nil,
            importedAt = type(entry) == 'table' and entry.importedAt or nil,
        }
    end
    for domain in pairs(Config.VmenuCompatibility and Config.VmenuCompatibility.importConfigFiles or {}) do
        if not domains[domain] then domains[domain] = { available = false, count = 0 } end
    end
    local bans = Server.listBans and Server.listBans() or {}
    return {
        resource = findVmenuResource(),
        config = { domains = domains, importResult = importResult },
        bans = { count = #bans },
        world = Server.getWorldSnapshot(),
        generatedAt = os.time(),
    }
end

RegisterNetEvent('cortex-admin:server:requestModelAuthorization', function(requestId, payload)
    local src = source
    if type(requestId) ~= 'string' or requestId == '' or #requestId > 96 then return end

    local function reply(result)
        TriggerClientEvent('cortex-admin:client:receiveModelAuthorization', src, requestId, result)
    end

    if not rate(src, 'model-authorization', 16, 10000) then
        reply({ ok = false, error = 'rate_limited', allowed = {} })
        return
    end
    if type(payload) ~= 'table' then
        reply({ ok = false, error = 'invalid_payload', allowed = {} })
        return
    end

    local kind = trim(payload.kind, 16)
    local actionId = trim(payload.actionId, 96)
    if not kind or not actionId or not MODEL_RULES[kind]
        or not MODEL_ACTIONS[kind] or MODEL_ACTIONS[kind][actionId] ~= true then
        reply({ ok = false, error = 'invalid_action', allowed = {} })
        return
    end

    local models = payload.models
    if models == nil then models = { payload.model } end
    if type(models) ~= 'table' or #models < 1 or #models > 256 then
        reply({ ok = false, error = 'invalid_models', allowed = {} })
        return
    end

    local now = GetGameTimer()
    local playerTokens = pendingModelAuthorizations[src] or {}
    pendingModelAuthorizations[src] = playerTokens
    for token, entry in pairs(playerTokens) do
        if type(entry) ~= 'table' or now >= (entry.expiresAt or 0) then playerTokens[token] = nil end
    end

    local allowedModels = {}
    local denied = 0
    local firstError = nil
    for index = 1, #models do
        local modelAllowed, errorReason = authorizeModel(src, kind, models[index], actionId)
        allowedModels[index] = modelAllowed == true
        if modelAllowed ~= true then
            denied = denied + 1
            firstError = firstError or errorReason or 'model_forbidden'
        end
    end


    local token = nil
    if denied == 0 and payload.preview ~= true then
        if kind == 'vehicle' and (actionId == 'vehicle.spawn' or actionId == 'vehicle.personal' or actionId == 'vehicle.load')
            and EsAdminVmenuPolicy and not IsPlayerAceAllowed(src, 'vMenu.VehicleSpawner.BypassRateLimit')
            and not Server.hasCortexPermission(src, actionId) then
            local delay = EsAdminVmenuPolicy.get('vmenu_vehicle_spawn_delay', 5) * 1000
            if lastVehicleSpawn[src] and (now - lastVehicleSpawn[src]) % 4294967296 < delay then
                reply({ ok = false, error = 'spawn_cooldown', allowed = {} }); return
            end
            lastVehicleSpawn[src] = now
        end
        token = ('ma:%d:%d:%d'):format(src, now, math.random(1000, 9999))
        playerTokens[token] = {
            kind = kind,
            actionId = actionId,
            models = buildAuthorizedModelSet(kind, models),
            expiresAt = now + 10000,
            remaining = 1,
        }
    end

    reply({
        ok = true,
        allAllowed = denied == 0,
        allowed = allowedModels,
        denied = denied,
        error = firstError,
        token = token,
    })
end)

local function consumeModelAuthorization(src, token, kind, actionId, model)
    if type(token) ~= 'string' or token == '' or #token > 96 then return false end
    local playerTokens = pendingModelAuthorizations[src]
    local entry = type(playerTokens) == 'table' and playerTokens[token] or nil
    if not entry or GetGameTimer() >= (entry.expiresAt or 0)
        or entry.kind ~= kind or entry.actionId ~= actionId or (entry.remaining or 0) < 1
        or not authorizedModelMatches(entry, kind, model)
        or not authorizeModel(src, kind, model, actionId) then
        if playerTokens then playerTokens[token] = nil end
        return false
    end
    entry.remaining = entry.remaining - 1
    if entry.remaining <= 0 then playerTokens[token] = nil end
    return true
end

Server.consumeModelAuthorization = consumeModelAuthorization

-- The ban list arrives from the client and imported bans can be permanent, so
-- importing requires the same grant as issuing a permanent ban, not just viewing.
local function canImportBans(src)
    return allowed(src, 'migration.import') and allowed(src, 'player.viewBans')
        and Server.hasPermission(src, 'player.ban', { 'vMenu.OnlinePlayers.PermBan', 'vMenu.OnlinePlayers.All', 'vMenu.Everything' }) == true
end
Server.canImportVmenuBans = canImportBans

RegisterNetEvent('cortex-admin:server:requestVmenuCompatibilityState', function(requestId, importNow)
    local src = source
    if not rate(src, 'vmenu-state', 4, 10000) or type(requestId) ~= 'string' or requestId == '' or #requestId > 96 then return end
    local actionId = importNow == true and 'migration.import' or 'migration.read'
    if not allowed(src, actionId) then
        TriggerClientEvent('cortex-admin:client:receiveVmenuCompatibilityState', src, requestId, { ok = false, reason = 'forbidden' })
        return
    end

    local importResult = importNow == true and refreshConfigImport() or nil
    local payload = compatibilityState(importResult)
    payload.ok = true
    TriggerClientEvent('cortex-admin:client:receiveVmenuCompatibilityState', src, requestId, payload)

    if importNow == true and payload.resource and canImportBans(src) then
        local token = ('vban:%d:%d:%d'):format(src, GetGameTimer(), math.random(1000, 9999))
        pendingBanImports[src] = { token = token, expiresAt = GetGameTimer() + 10000 }
        TriggerClientEvent('cortex-admin:client:requestVmenuBanList', src, token)
    end
end)

RegisterNetEvent('cortex-admin:server:requestVmenuConfigDomain', function(requestId, domain)
    local src = source
    if not rate(src, 'vmenu-config-read', 8, 10000)
        or type(requestId) ~= 'string' or requestId == '' or #requestId > 96 then return end

    domain = trim(domain, 48)
    if not allowed(src, 'migration.read') then
        TriggerClientEvent('cortex-admin:client:receiveVmenuConfigDomain', src, requestId, domain, nil, 'forbidden')
        return
    end
    local entry = domain and CONFIG_DOMAINS[domain] and configStore.domains[domain] or nil
    if type(entry) ~= 'table' or type(entry.data) ~= 'table' then
        TriggerClientEvent('cortex-admin:client:receiveVmenuConfigDomain', src, requestId, domain, nil, 'unavailable')
        return
    end

    local ok, encoded = pcall(json.encode, entry.data)
    if not ok or type(encoded) ~= 'string' or #encoded > MAX_CONFIG_DOMAIN_BYTES then
        TriggerClientEvent('cortex-admin:client:receiveVmenuConfigDomain', src, requestId, domain, nil, 'too_large')
        return
    end

    TriggerLatentClientEvent(
        'cortex-admin:client:receiveVmenuConfigDomain',
        src,
        CONFIG_DOMAIN_BPS,
        requestId,
        domain,
        encoded,
        nil
    )
end)

RegisterNetEvent('cortex-admin:server:importVmenuBanList', function(token, encoded)
    local src = source
    local pending = pendingBanImports[src]
    pendingBanImports[src] = nil
    if not pending or pending.token ~= token or GetGameTimer() > pending.expiresAt then return end
    if not canImportBans(src) then return end
    if type(encoded) ~= 'string' or encoded == '' or #encoded > 2 * 1024 * 1024 then return end
    local ok, records = pcall(json.decode, encoded)
    if not ok or type(records) ~= 'table' or #records > 4096 then
        notify(src, 'error', 'The vMenu ban list was malformed or too large.')
        return
    end
    local result = Server.importVmenuBans and Server.importVmenuBans(records) or { imported = 0, invalid = #records }
    TriggerClientEvent('cortex-admin:client:vmenuBanImportResult', src, result)
    notify(src, result.imported > 0 and 'success' or 'info', ('vMenu bans imported %d, skipped %d, invalid %d.'):format(result.imported or 0, result.skipped or 0, result.invalid or 0))
end)

local function buildBanPage(options)
    options = type(options) == 'table' and options or {}
    local offset = integer(options.offset, 0, 100000) or 0
    local limit = integer(options.limit, 1, 100) or 50
    local query = trim(options.query, 64)
    if query then query = query:lower() end

    local all = Server.listBans and Server.listBans() or {}
    local matched = {}
    for index = 1, #all do
        local record = all[index]
        local include = query == nil
        if not include and type(record) == 'table' then
            for _, value in ipairs({ record.id, record.playerName, record.reason, record.adminName }) do
                if type(value) == 'string' and value:lower():find(query, 1, true) then
                    include = true
                    break
                end
            end
        end
        if include then matched[#matched + 1] = record end
    end

    local records = {}
    local finalIndex = math.min(#matched, offset + limit)
    for index = offset + 1, finalIndex do records[#records + 1] = matched[index] end
    return {
        records = records,
        total = #matched,
        offset = offset,
        limit = limit,
        hasMore = finalIndex < #matched,
    }
end

RegisterNetEvent('cortex-admin:server:requestBanList', function(requestId, options)
    local src = source
    if not rate(src, 'ban-read', 6, 10000) or type(requestId) ~= 'string' or requestId == '' or #requestId > 96 then return end
    if not allowed(src, 'player.viewBans') then
        TriggerClientEvent('cortex-admin:client:receiveBanList', src, requestId, { ok = false, error = 'forbidden', records = {} })
        return
    end
    local page = buildBanPage(options)
    page.ok = true
    TriggerClientEvent('cortex-admin:client:receiveBanList', src, requestId, page)
end)

RegisterNetEvent('cortex-admin:server:unban', function(requestId, banId)
    local src = source
    if not rate(src, 'ban-write', 4, 10000) or type(requestId) ~= 'string' or requestId == '' or #requestId > 96 then return end
    if not allowed(src, 'player.unban') then return end
    banId = trim(banId, 96)
    local removed = banId and Server.removeBan and Server.removeBan(banId) == true
    if not EsAdminVmenuPolicy or EsAdminVmenuPolicy.get('vmenu_log_ban_actions', true) then print(('[cortex-admin] %s attempted unban %s: %s'):format(GetPlayerName(src) or 'Console', tostring(banId), removed and 'removed' or 'not found')) end
    TriggerClientEvent('cortex-admin:client:receiveUnbanResult', src, requestId, {
        ok = removed,
        id = banId,
    })
end)

RegisterNetEvent('cortex-admin:server:privateMessagePreference', function(disabled)
    local src = source
    if type(disabled) ~= 'boolean' or not rate(src, 'private-message-preference', 12, 5000) then return end
    privateMessagesDisabled[src] = disabled
end)

local orbitalStrikeSequence = 0
RegisterNetEvent('cortex-admin:server:vmenuPlayerAction', function(data)
    local src = source
    if not rate(src, 'vmenu-player-write', 12, 5000) or type(data) ~= 'table' then return end
    local action = trim(data.action, 16)
    local target = integer(data.target, 1, 65535)
    local permissions = {
        waypoint = 'player.waypoint', spectate = 'player.spectate', message = 'player.message',
        identifiers = 'player.identifiers', kill = 'player.kill', orbital = 'player.orbitalStrike',
        smite = 'player.smite',
    }
    local actionId = action and permissions[action]
    if not target or not actionId then return end
    if not allowed(src, actionId) then
        if Server.vmenuDenied then Server.vmenuDenied(src, actionId) end
        Server.playerResult(src, data.requestId, false, 'You do not have permission to use this action.')
        return
    end
    local function result(ok, message) Server.playerResult(src, data.requestId, ok, message) end
    if not Server.targetSessionMatches(target, data.targetSession) then
        result(false, 'The selected player changed. Refresh the player list and select them again.'); return
    end
    if not GetPlayerName(target) then result(false, 'That player is no longer online.'); return end
    local name = GetPlayerName(target)

    if action == 'message' then
        local message = trim(data.message, 320)
        if not message then result(false, 'Write a message first.'); return end
        if privateMessagesDisabled[src] then result(false, 'Enable private messages before sending one.'); return end
        if privateMessagesDisabled[target] then result(false, 'That player has private messages disabled.'); return end
        local sender = GetPlayerName(src) or ('Player %d'):format(src)
        TriggerClientEvent('cortex-admin:client:vmenuNotice', target, 'info', ('Private message from %s: %s'):format(sender, message))
        for _, player in ipairs(GetPlayers()) do
            local viewer = tonumber(player)
            if viewer and allowed(viewer, 'player.monitorMessages') then
                TriggerClientEvent('cortex-admin:client:vmenuNotice', viewer, 'info',
                    ('Staff PM log: %s → %s: %s'):format(sender, name, message))
            end
        end
        result(true, ('Message sent to %s.'):format(name))
        return
    end

    if action == 'identifiers' then
        local identifiers = GetPlayerIdentifiers(target)
        local output = {}
        for index = 1, math.min(type(identifiers) == 'table' and #identifiers or 0, 16) do
            local identifier = trim(identifiers[index], 160)
            if identifier then output[#output + 1] = identifier end
        end
        TriggerClientEvent('cortex-admin:client:vmenuIdentifiers', src, {
            target = target,
            session = data.targetSession,
            name = GetPlayerName(target),
            identifiers = output,
        })
        result(true, ('Identifiers for %s.'):format(name))
        return
    end

    if action == 'kill' then
        TriggerClientEvent('cortex-admin:client:killPed', target)
        print(('[cortex-admin] %s killed %s (%d)'):format(GetPlayerName(src) or 'Console', GetPlayerName(target) or 'Unknown', target))
        result(true, ('Killed %s.'):format(name))
        return
    end

    if action == 'smite' then
        local labels = { launch = 'Launched', fire = 'Set fire to', chicken = 'Turned into a chicken:', drunk = 'Got drunk:' }
        local kind = type(data.kind) == 'string' and labels[data.kind] and data.kind
        if not kind then result(false, 'Pick a smite first.'); return end
        TriggerClientEvent('cortex-admin:client:smite', target, kind)
        print(('[cortex-admin] %s smote %s (%d): %s'):format(GetPlayerName(src) or 'Console', GetPlayerName(target) or 'Unknown', target, kind))
        result(true, ('%s %s.'):format(labels[kind], name))
        return
    end

    if action == 'orbital' then
        local targetPed = GetPlayerPed(target)
        if not targetPed or targetPed <= 0 or not DoesEntityExist(targetPed) then
            result(false, 'That player has no ped yet.'); return
        end
        local coords = GetEntityCoords(targetPed)
        local bucket = GetPlayerRoutingBucket(target)
        orbitalStrikeSequence = orbitalStrikeSequence % 0x7fffffff + 1
        local strike = { id = orbitalStrikeSequence, target = target, coords = { x = coords.x, y = coords.y, z = coords.z } }
        for _, player in ipairs(GetPlayers()) do
            local viewer = tonumber(player)
            if viewer and GetPlayerRoutingBucket(viewer) == bucket then
                TriggerClientEvent('cortex-admin:client:orbitalStrike', viewer, strike)
            end
        end
        print(('[cortex-admin] %s orbital struck %s (%d)'):format(GetPlayerName(src) or 'Console', GetPlayerName(target) or 'Unknown', target))
        result(true, ('Orbital strike on %s.'):format(name))
        return
    end

    -- Spectating the same player again stops; so does an explicit stop.
    if action == 'spectate' and (data.stop == true or spectating[src] == target) then
        spectating[src] = nil
        TriggerClientEvent('cortex-admin:client:setSpectateTarget', src, false)
        result(true, ('Stopped spectating %s.'):format(name))
        return
    end
    if action == 'spectate' and target == src then result(false, 'Choose another player.'); return end

    local targetPed = GetPlayerPed(target)
    if not targetPed or targetPed <= 0 or not DoesEntityExist(targetPed) or GetEntityType(targetPed) ~= 1 then
        result(false, ('%s has no position yet.'):format(name))
        return
    end
    local coords = GetEntityCoords(targetPed)
    if not coords or math.abs(coords.x) > 20000 or math.abs(coords.y) > 20000 or math.abs(coords.z) > 20000 then
        result(false, ('%s has no position yet.'):format(name))
        return
    end

    if action == 'waypoint' then
        TriggerClientEvent('cortex-admin:client:setPlayerWaypoint', src, { x = coords.x, y = coords.y, z = coords.z })
        result(true, ('Waypoint set on %s.'):format(name))
    elseif action == 'spectate' then
        if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then
            result(false, ('%s is in routing bucket %d and you are in %d.'):format(name, GetPlayerRoutingBucket(target), GetPlayerRoutingBucket(src)))
            return
        end
        spectating[src] = target
        TriggerClientEvent('cortex-admin:client:setSpectateTarget', src, target, data.targetSession, { x = coords.x, y = coords.y, z = coords.z })
        result(true, ('Spectating %s. Spectate again to stop.'):format(name))
    end
end)

RegisterNetEvent('cortex-admin:server:setVmenuWorldState', function(payload)
    local src = source
    if not rate(src, 'vmenu-world-write', 8, 5000) or type(payload) ~= 'table' then return end
    local actionId = trim(payload.actionId, 64)
    if not actionId or not allowed(src, actionId) then return end
    local changed = {}

    if actionId == 'world.dynamicWeather' and type(payload.dynamicWeather) == 'boolean' then
        extendedWorldState.dynamicWeather = payload.dynamicWeather
        changed.dynamicWeather = payload.dynamicWeather
    elseif actionId == 'world.vehicleBlackout' and type(payload.vehicleBlackout) == 'boolean' then
        extendedWorldState.vehicleBlackout = payload.vehicleBlackout
        changed.vehicleBlackout = payload.vehicleBlackout
    elseif actionId == 'world.snowEffects' and type(payload.snowEffects) == 'boolean' then
        extendedWorldState.snowEffects = payload.snowEffects
        changed.snowEffects = payload.snowEffects
    elseif actionId == 'world.randomClouds' and payload.cloudAction == 'random' then
        extendedWorldState.cloudHat = cloudHats[math.random(1, #cloudHats)]
        changed.cloudHat = extendedWorldState.cloudHat
    elseif actionId == 'world.removeClouds' and payload.cloudAction == 'remove' then
        extendedWorldState.cloudHat = ''
        changed.cloudHat = ''
    end
    if next(changed) then Server.publishWorldState(-1, true) end
end)

RegisterNetEvent('cortex-admin:server:requestVmenuWorldState', function()
    local src = source
    if not rate(src, 'world-read', 6, 5000) then return end
    Server.publishWorldState(src)
end)

RegisterNetEvent('cortex-admin:server:setPersonalVehicle', function(networkId)
    local src = source
    networkId = integer(networkId, 1, 65535)
    if not networkId or not rate(src, 'personal-vehicle-set', 4, 10000)
        or not allowed(src, 'vehicle.personalSet') then return end
    local vehicle = NetworkGetEntityFromNetworkId(networkId)
    local ped = GetPlayerPed(src)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2
        or not ped or ped == 0 or not DoesEntityExist(ped)
        or GetPedInVehicleSeat(vehicle, -1) ~= ped
        or GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src) then return end
    personalVehicles[src] = {
        networkId = networkId,
        model = GetEntityModel(vehicle),
    }
end)

RegisterNetEvent('cortex-admin:server:kickPersonalVehiclePassengers', function()
    local src = source
    if not rate(src, 'personal-vehicle-kick', 3, 10000)
        or not allowed(src, 'vehicle.personalKickPassengers') then return end
    local vehicle, session = resolvePersonalVehicle(src)
    if not vehicle then
        notify(src, 'error', 'Set a valid personal vehicle first.')
        return
    end
    local requesterPed = GetPlayerPed(src)
    local kicked = {}
    for seat = -1, 15 do
        local occupant = GetPedInVehicleSeat(vehicle, seat)
        if occupant and occupant ~= 0 and occupant ~= requesterPed then
            local owner = NetworkGetEntityOwner(occupant)
            if owner and owner > 0 and owner ~= src and GetPlayerName(owner) and not kicked[owner] then
                kicked[owner] = true
                TriggerClientEvent('cortex-admin:client:leavePersonalVehicle', owner, session.networkId)
            end
        end
    end
    local count = 0
    for _ in pairs(kicked) do count = count + 1 end
    notify(src, count > 0 and 'success' or 'info', count > 0
        and ('Asked %d player(s) to leave your personal vehicle.'):format(count)
        or 'There are no other players in your personal vehicle.')
end)

RegisterNetEvent('cortex-admin:server:requestEntitySpawn', function(payload)
    local src = source
    local requestId = type(payload) == 'table' and trim(payload.requestId, 96) or nil
    local function reject(reason)
        if requestId then
            TriggerClientEvent('cortex-admin:client:entitySpawnRejected', src, requestId, reason)
        end
    end
    if not rate(src, 'entity-spawn', 3, 10000) then
        reject('rate_limited')
        return
    end
    if not allowed(src, 'dev.spawnEntity') then
        reject('forbidden')
        return
    end
    if type(payload) ~= 'table' or not requestId then
        reject('invalid_payload')
        return
    end
    local entityType = trim(payload.type, 16)
    local model = trim(payload.model, 64)
    if entityType then entityType = entityType:lower() end
    if (entityType ~= 'vehicle' and entityType ~= 'ped' and entityType ~= 'object')
        or not model or not model:match('^[%w_%-]+$') then
        reject('invalid_model')
        return
    end
    if entityType == 'vehicle' or entityType == 'ped' then
        local modelAllowed, reason = authorizeModel(src, entityType, model, 'dev.spawnEntity')
        if not modelAllowed then
            reject(reason or 'model_forbidden')
            return
        end
    end
    TriggerClientEvent('cortex-admin:client:authorizedEntitySpawn', src, requestId, entityType, model)
end)

RegisterNetEvent('cortex-admin:server:reportDeath', function()
    local src = source
    local ped = GetPlayerPed(src)
    if not rate(src, 'death-report', 2, 10000) or not GetPlayerName(src)
        or not ped or ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) > 0 then return end
    TriggerClientEvent('cortex-admin:client:vmenuDeath', -1, ('%s died.'):format(GetPlayerName(src)))
end)

AddEventHandler('playerJoining', function()
    local src = source
    local name = GetPlayerName(src) or ('Player %d'):format(src)
    TriggerClientEvent('cortex-admin:client:vmenuJoinQuit', -1, ('%s joined the server.'):format(name))
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    local name = GetPlayerName(src) or ('Player %d'):format(src)
    pendingBanImports[src] = nil
    pendingModelAuthorizations[src] = nil
    personalVehicles[src] = nil
    privateMessagesDisabled[src] = nil
    lastVehicleSpawn[src] = nil
    spectating[src] = nil
    for viewer, target in pairs(spectating) do
        if target == src then
            spectating[viewer] = nil
            TriggerClientEvent('cortex-admin:client:setSpectateTarget', viewer, false)
        end
    end
    TriggerClientEvent('cortex-admin:client:vmenuJoinQuit', -1, ('%s left the server%s.'):format(name, trim(reason, 96) and (': ' .. trim(reason, 96)) or ''))
end)

CreateThread(function()
    local default = EsAdminVmenuPolicy and EsAdminVmenuPolicy.get('vmenu_dynamic_weather_timer', 15) * 60000 or 300000
    local interval = integer(GetConvar('cortex-admin_dynamic_weather_interval_ms', tostring(default)), 60000, 86400000) or default
    while true do
        Wait(interval)
        if extendedWorldState.dynamicWeather and Server.worldActionAvailable('world.weather') then
            weatherIndex = weatherIndex % #weatherCycle + 1
            local weather = weatherCycle[weatherIndex]
            Server.worldState.weather = weather
            Server.publishWorldState(-1, true)
        end
    end
end)

loadConfigStore()
refreshModelWhitelistIndex()

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= resourceName then return end
    personalVehicles = {}
    saveConfigStore()
end)

-- Former vMenu servers carry over without an admin pressing Import. vMenu's
-- config files are copied in whenever a vMenu resource (vMenu itself, or the
-- stand-in with the old config folder) is present; files that fail to load keep
-- the last good copy. Bans live in vMenu's own server storage, which only a
-- resource named vMenu can read, so the stand-in hands them over. Imports are
-- keyed by vMenu's ban id and never repeat.
local function vmenuCompat()
    return GetResourceState('vMenu') == 'started' and GetResourceMetadata('vMenu', 'cortex_vmenu_compat', 0) == 'yes'
end

local function autoImportVmenu()
    if findVmenuResource() then
        local result = refreshConfigImport()
        if result.imported > 0 then
            print(('[cortex-admin] vMenu config copied from %s: %d files.'):format(result.resource, result.imported))
        end
    end
    if not vmenuCompat() or not Server.importVmenuBans then return end
    local ok, records = pcall(function() return exports.vMenu:GetBanRecords() end)
    if not ok or type(records) ~= 'table' then
        print(('[cortex-admin] vMenu bans could not be read: %s'):format(tostring(records)))
        return
    end
    local result = Server.importVmenuBans(records)
    if result.imported > 0 or result.invalid > 0 then
        print(('[cortex-admin] vMenu bans: %d imported, %d already present, %d unreadable.'):format(result.imported, result.skipped, result.invalid))
    end
end

AddEventHandler('onResourceStart', function(started)
    if started ~= 'vMenu' then return end
    CreateThread(function() Wait(1000) autoImportVmenu() end)
end)
CreateThread(function() Wait(2000) autoImportVmenu() end)
