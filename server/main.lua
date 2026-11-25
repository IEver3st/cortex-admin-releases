local Actions = EsAdminActions

local actionIndex = {}
for _, action in ipairs(Actions.actions) do
    actionIndex[action.id] = action
end

local worldState = EsAdminServer.worldState
local mathAbs = math.abs
local mathFloor = math.floor
local stringUpper = string.upper
local tonumber = tonumber
local type = type

local allowedWorldWeather = {
    EXTRASUNNY = true,
    CLEAR = true,
    CLOUDS = true,
    SMOG = true,
    FOGGY = true,
    OVERCAST = true,
    RAIN = true,
    THUNDER = true,
    CLEARING = true,
    NEUTRAL = true,
    SNOW = true,
    BLIZZARD = true,
    SNOWLIGHT = true,
    XMAS = true,
    HALLOWEEN = true,
}

local allowedPlayerActions = {
    ['goto'] = true,
    kick = true,
    ban = true,
    freeze = true,
    bring = true,
}

local allowedResourceActions = {
    start = true,
    stop = true,
    ensure = true,
    restart = true,
    refresh = true,
}

local uiPresence = {}
-- Staff freezes, kept here so every admin sees the same state and a toggle
-- never relies on one admin's memory.
local frozenPlayers = {}
local permissionCache = {}
local requestBuckets = {}
local pendingAdminCarRequests = {}
local playerSessions, sessionSequence = {}, 0
local PERMISSION_CACHE_MS = 10000
local ADMIN_CAR_REQUEST_MS = 5000
local configuredWardrobeShareRadius = WardrobeSharePolicy.validateRadius(Config.WardrobeShareRadius)
local WARDROBE_SHARE_RADIUS = configuredWardrobeShareRadius or WardrobeSharePolicy.DEFAULT_RADIUS

if not configuredWardrobeShareRadius then
    print(('[cortex-admin] Invalid Config.WardrobeShareRadius; using %.1fm.'):format(WARDROBE_SHARE_RADIUS))
end

local moneyActions = {
    ['player.setCash'] = 'cash',
    ['player.setBank'] = 'bank',
}

local metadataActions = {
    ['player.setFood'] = 'hunger',
    ['player.setThirst'] = 'thirst',
    ['player.setStress'] = 'stress',
    ['dev.setStress'] = 'stress',
}

local allowedMoneyTypes = {
    cash = true,
    bank = true,
}

local function trimString(value, maxLength)
    if type(value) ~= 'string' then
        return nil
    end

    value = value:match('^%s*(.-)%s*$')
    if value == '' then
        return nil
    end

    if maxLength and #value > maxLength then
        value = value:sub(1, maxLength)
    end

    return value
end

local function toInteger(value, minValue, maxValue)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end

    if number ~= mathFloor(number) then
        return nil
    end

    if minValue and number < minValue then
        return nil
    end

    if maxValue and number > maxValue then
        return nil
    end

    return number
end

local function toBoolean(value)
    if value == true or value == false then
        return value
    end

    if value == 1 or value == '1' or value == 'true' then
        return true
    end

    if value == 0 or value == '0' or value == 'false' then
        return false
    end

    return nil
end

local function normalizeWeather(value)
    local weather = trimString(value, 24)
    if not weather then
        return nil
    end

    weather = stringUpper(weather)
    if not allowedWorldWeather[weather] then
        return nil
    end

    return weather
end

local function sanitizeCoords(coords)
    -- Server natives return vector3, which type() reports as 'vector3', not 'table'.
    local kind = type(coords)
    if kind ~= 'table' and kind ~= 'vector3' and kind ~= 'vector4' then
        return nil
    end

    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then
        return nil
    end

    if x ~= x or y ~= y or z ~= z then
        return nil
    end

    if mathAbs(x) > 20000 or mathAbs(y) > 20000 or mathAbs(z) > 20000 then
        return nil
    end

    return {
        x = x,
        y = y,
        z = z,
    }
end

local function allowRequest(src, bucketName, maxRequests, windowMs)
    if type(src) ~= 'number' or src <= 0 then
        return false
    end

    local now = GetGameTimer()
    local playerBuckets = requestBuckets[src]
    if not playerBuckets then
        playerBuckets = {}
        requestBuckets[src] = playerBuckets
    end

    local bucket = playerBuckets[bucketName]
    if not bucket or now < bucket.startedAt or now - bucket.startedAt >= windowMs then
        playerBuckets[bucketName] = {
            startedAt = now,
            count = 1,
        }
        return true
    end

    if bucket.count >= maxRequests then
        return false
    end

    bucket.count = bucket.count + 1
    return true
end

local function getSessionIdentifier(src)
    local identifiers = GetPlayerIdentifiers(src)
    if type(identifiers) ~= 'table' then return nil end
    return identifiers[1]
end

local function sessionIdentifierMatches(src, expected)
    if type(expected) ~= 'string' or expected == '' or not GetPlayerName(src) then
        return false
    end

    local identifiers = GetPlayerIdentifiers(src)
    if type(identifiers) ~= 'table' then return false end
    for _, identifier in ipairs(identifiers) do
        if identifier == expected then return true end
    end
    return false
end

local function hasFullPermission(src)
    return IsPlayerAceAllowed(src, Config.Permissions.all)
        or IsPlayerAceAllowed(src, 'vMenu.Everything')
        or (Config.AllowCommandAdmin == true and IsPlayerAceAllowed(src, 'command'))
end

local hasPermission
local function canOpenMenu(src)
    if hasFullPermission(src)
        or IsPlayerAceAllowed(src, 'command.' .. Config.Command)
        or IsPlayerAceAllowed(src, 'command.esadmin')
        or IsPlayerAceAllowed(src, 'command.cortexadmin')
        or IsPlayerAceAllowed(src, 'command.vmenu') then
        return true
    end

    local vmenuMenus = {
        'vMenu.OnlinePlayers.Menu', 'vMenu.PlayerOptions.Menu', 'vMenu.VehicleOptions.Menu',
        'vMenu.VehicleSpawner.Menu', 'vMenu.SavedVehicles.Menu', 'vMenu.PersonalVehicle.Menu',
        'vMenu.PlayerAppearance.Menu', 'vMenu.TimeOptions.Menu', 'vMenu.WeatherOptions.Menu',
        'vMenu.WeaponOptions.Menu', 'vMenu.WeaponLoadouts.Menu', 'vMenu.VoiceChat.Menu',
        'vMenu.MiscSettings.Menu', 'vMenu.MiscSettings.All', 'vMenu.NoClip',
    }
    for index = 1, #vmenuMenus do
        if (EsAdminServer.vmenuAce or IsPlayerAceAllowed)(src, vmenuMenus[index]) then return true end
    end

    for _, action in ipairs(Actions.actions) do
        if hasPermission and hasPermission(src, action.id) then return true end
    end

    return Config.HasQBX
        and EsAdminBridge
        and EsAdminBridge.isQBXAdmin
        and EsAdminBridge.isQBXAdmin(src) == true
end

local function sanitizeVariationPair(value, minDrawable)
    if type(value) ~= 'table' then
        return nil
    end

    local entryCount = 0
    for key in pairs(value) do
        if key ~= 1 and key ~= 2 then
            return nil
        end
        entryCount = entryCount + 1
    end

    if entryCount ~= 2 then
        return nil
    end

    local drawable = toInteger(value[1], minDrawable, 4096)
    local texture = toInteger(value[2], 0, 1024)
    if drawable == nil or texture == nil then
        return nil
    end

    return { drawable, texture }
end

local function sanitizeVariationMap(value, minId, maxId, minDrawable, maxEntries)
    if type(value) ~= 'table' then
        return nil
    end

    local sanitized = {}
    local count = 0

    for rawId, variation in pairs(value) do
        local id = toInteger(rawId, minId, maxId)
        local pair = sanitizeVariationPair(variation, minDrawable)
        if id == nil or pair == nil or sanitized[id] ~= nil then
            return nil
        end

        count = count + 1
        if count > maxEntries then
            return nil
        end
        sanitized[id] = pair
    end

    return sanitized
end

local function sanitizeWardrobe(outfit)
    if type(outfit) ~= 'table'
        or type(outfit.DrawableVariations) ~= 'table'
        or type(outfit.PropVariations) ~= 'table' then
        return nil
    end

    local clothes = sanitizeVariationMap(outfit.DrawableVariations.clothes, 0, 11, 0, 12)
    local props = sanitizeVariationMap(outfit.PropVariations.props, 0, 7, -1, 8)
    if not clothes or not props then
        return nil
    end

    return {
        Version = 1,
        DrawableVariations = { clothes = clothes },
        PropVariations = { props = props },
    }
end

local function sanitizeSerializable(value, depth, budget)
    local valueType = type(value)
    if valueType == 'boolean' then return value, true end
    if valueType == 'string' then
        if #value > 256 then return nil, false end
        return value, true
    end
    if valueType == 'number' then
        if value ~= value or value == math.huge or value == -math.huge or mathAbs(value) > 1000000000000 then
            return nil, false
        end
        return value, true
    end
    if valueType ~= 'table' or depth > 6 then
        return nil, false
    end

    local sanitized = {}
    for key, entry in pairs(value) do
        budget.count = budget.count + 1
        if budget.count > 384 then return nil, false end

        local keyType = type(key)
        if keyType == 'number' then
            if key ~= mathFloor(key) or key < -1 or key > 1024 then return nil, false end
        elseif keyType == 'string' then
            if key == '' or #key > 64 then return nil, false end
        else
            return nil, false
        end

        local cleanEntry, ok = sanitizeSerializable(entry, depth + 1, budget)
        if not ok then return nil, false end
        sanitized[key] = cleanEntry
    end

    return sanitized, true
end

local function sanitizeVehicleProps(props, model, plate)
    if type(props) ~= 'table' then return nil end

    local sanitized, ok = sanitizeSerializable(props, 1, { count = 0 })
    if not ok then return nil end
    sanitized.model = model
    sanitized.plate = trimString(plate, 16) or ''

    local encodedOk, encoded = pcall(json.encode, sanitized)
    if not encodedOk or type(encoded) ~= 'string' or #encoded > 65536 then
        return nil
    end
    return sanitized
end

local function arePlayersNearby(firstSource, secondSource, maxDistance)
    if GetPlayerRoutingBucket(firstSource) ~= GetPlayerRoutingBucket(secondSource) then
        return false
    end

    local firstPed = GetPlayerPed(firstSource)
    local secondPed = GetPlayerPed(secondSource)
    if not firstPed or firstPed <= 0 or not secondPed or secondPed <= 0 then
        return false
    end

    local firstCoords = GetEntityCoords(firstPed)
    local secondCoords = GetEntityCoords(secondPed)
    if not firstCoords or not secondCoords then
        return false
    end

    local dx = firstCoords.x - secondCoords.x
    local dy = firstCoords.y - secondCoords.y
    local dz = firstCoords.z - secondCoords.z
    local distanceSquared = dx * dx + dy * dy + dz * dz
    return WardrobeSharePolicy.isDistanceSquaredWithinRadius(distanceSquared, maxDistance)
end

hasPermission = function(src, actionId, vmenuOverride, cortexOnly)
    if EsAdminVmenuPolicy and not EsAdminVmenuPolicy.actionEnabled(actionId) then return false end
    if EsAdminServer.worldActionAvailable and not EsAdminServer.worldActionAvailable(actionId) then return false end
    local definition = actionIndex[actionId]
    if definition and definition.framework == 'qbx' then
        if not Config.HasQBX or GetResourceState('qbx_core') ~= 'started' then return false end
        if definition.qbox and not QboxAdmin.available(definition) then return false end
    end
    if definition and definition.permissionAlias and hasPermission(src, definition.permissionAlias, nil, cortexOnly) then return true end
    -- Full admins use the same grant for menu actions and model authorization.
    if hasFullPermission(src) then
        return true
    end

    local vmenuPermissions = vmenuOverride or (Config.VmenuAcePermissions and Config.VmenuAcePermissions[actionId])
    if not cortexOnly and type(vmenuPermissions) == 'table' then
        for index = 1, #vmenuPermissions do
            local permission = vmenuPermissions[index]
            if type(permission) == 'string' and (EsAdminServer.vmenuAce
                and EsAdminServer.vmenuAce(src, permission) or not EsAdminServer.vmenuAce and IsPlayerAceAllowed(src, permission)) then return true end
        end
    end

    -- QBX Permission Bridge: When QBX is active, check if the player belongs to
    -- a configured QBX admin group (god, admin, mod, etc.) and resolve permissions
    -- from Config.QBXPermissions mapping. This lets QBX admins use the menu
    -- without needing separate cortex-admin.* ACE entries.
    if Config.HasQBX and EsAdminBridge.checkQBXPermission then
        local action = actionIndex[actionId]
        local tab = action and action.tab or actionId:match('^([^.]+)%.')
        local qbxResult = EsAdminBridge.checkQBXPermission(src, actionId, tab)
        if qbxResult == true then return true end
        if qbxResult == false then return false end
        -- nil = no QBX group matched, fall through to standard ACE checks
    end

    -- Check for specific action permission
    local actionPerm = Config.ActionPermissions[actionId]
    if actionPerm and IsPlayerAceAllowed(src, actionPerm) then
        return true
    end

    -- Check for tab-level permission
    local action = actionIndex[actionId]
    local tab = action and action.tab or actionId:match('^([^.]+)%.')
    if tab and Config.Permissions[tab] and IsPlayerAceAllowed(src, Config.Permissions[tab]) then
        return true
    end

    return false
end

local checkPermission = hasPermission
hasPermission = function(src, actionId, ...)
    local allowed = checkPermission(src, actionId, ...)
    if allowed and EsAdminServer.noteVmenuGrant then EsAdminServer.noteVmenuGrant(src, actionId) end
    return allowed
end
EsAdminServer.invalidatePermissions = function() permissionCache = {} end
EsAdminServer.hasFullPermission = hasFullPermission
EsAdminServer.hasPermission = hasPermission
EsAdminServer.hasCortexPermission = function(src, actionId) return hasPermission(src, actionId, nil, true) end
EsAdminServer.canOpenMenu = canOpenMenu
EsAdminServer.allowRequest = allowRequest
EsAdminServer.toInteger = toInteger
EsAdminServer.toBoolean = toBoolean
EsAdminServer.trimString = trimString
EsAdminServer.sanitizeCoords = sanitizeCoords

-- Tokens identify a connection, not a reusable server ID or a durable account.
local function playerSession(src)
    src = tonumber(src)
    if not src or src < 1 or src % 1 ~= 0 then return nil end
    if not GetPlayerName(src) then return nil end
    if not playerSessions[src] then
        sessionSequence = sessionSequence + 1
        playerSessions[src] = ('%d:%d:%d'):format(os.time(), GetGameTimer(), sessionSequence)
    end
    return playerSessions[src]
end
local function targetSessionMatches(target, token)
    return type(token) == 'string' and token ~= '' and token == playerSession(target)
end
EsAdminServer.playerSession = playerSession
EsAdminServer.targetSessionMatches = targetSessionMatches
AddEventHandler('playerJoining', function() playerSessions[source] = nil end)

local function buildPermissionSnapshot(src)
    local now = GetGameTimer()
    local cached = permissionCache[src]
    if cached and now < cached.expiresAt then
        return cached.allowed
    end

    local allowed = {}
    for _, action in ipairs(Actions.actions) do
        allowed[action.id] = hasPermission(src, action.id)
    end
    for actionId in pairs(Config.ActionPermissions or {}) do
        if allowed[actionId] == nil then
            allowed[actionId] = hasPermission(src, actionId)
        end
    end

    permissionCache[src] = {
        allowed = allowed,
        expiresAt = now + PERMISSION_CACHE_MS,
    }

    return allowed
end

RegisterNetEvent('cortex-admin:server:requestPermissions', function()
    local src = source
    if not allowRequest(src, 'menu-read', 12, 5000) then return end
    if EsAdminBridge.clearPermCache then EsAdminBridge.clearPermCache(src) end
    permissionCache[src] = nil
    local menuAllowed = canOpenMenu(src) == true
    TriggerClientEvent('cortex-admin:client:permissions', src, menuAllowed and buildPermissionSnapshot(src) or {},
        QboxAdmin and QboxAdmin.capabilities() or nil, { menuAllowed = menuAllowed, expiresInMs = 30000,
            vmenu = menuAllowed and EsAdminServer.vmenuSnapshot and EsAdminServer.vmenuSnapshot(src) or nil })
end)

local function buildPlayerDirectory(requester)
    local directory = {}
    local players = GetPlayers()
    for index = 1, #players do
        local playerSource = toInteger(players[index], 1, 65535)
        if playerSource and GetPlayerName(playerSource) then
            local ped = GetPlayerPed(playerSource)
            local health = ped and ped > 0 and DoesEntityExist(ped) and GetEntityHealth(ped) or nil
            directory[#directory + 1] = {
                id = playerSource,
                session = playerSession(playerSource),
                name = trimString(GetPlayerName(playerSource), 96) or ('Player %d'):format(playerSource),
                ping = toInteger(GetPlayerPing(playerSource), 0, 9999) or 0,
                bucket = toInteger(GetPlayerRoutingBucket(playerSource), 0, 65535) or 0,
                dead = health ~= nil and health <= 0 or false,
                isSelf = playerSource == requester,
            }
        end
    end
    table.sort(directory, function(first, second) return first.id < second.id end)
    return directory
end

-- The Players console roster: who is online, where they are relative to the
-- requesting admin, their state, and (when permitted) their Qbox character.
local function safe(fn, ...)
    local ok, value = pcall(fn, ...)
    if ok then return value end
end
local function percent(value, max)
    if type(value) ~= 'number' or type(max) ~= 'number' or max <= 0 then return nil end
    return math.max(0, math.min(100, math.floor(value / max * 100 + 0.5)))
end
local function characterOf(playerSource)
    local player = safe(function() return exports.qbx_core:GetPlayer(playerSource) end)
    local data = player and player.PlayerData
    if type(data) ~= 'table' then return nil end
    local info, job, gang = data.charinfo or {}, data.job or {}, data.gang or {}
    local money, metadata = data.money or {}, data.metadata or {}
    local gradeOf = function(group) return type(group.grade) == 'table' and trimString(group.grade.name, 48) or nil end
    return {
        name = trimString(((info.firstname or '') .. ' ' .. (info.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''), 96),
        citizenid = trimString(data.citizenid, 32),
        job = trimString(job.label or job.name, 48), jobGrade = gradeOf(job), onDuty = job.onduty == true,
        gang = gang.name ~= 'none' and trimString(gang.label or gang.name, 48) or nil, gangGrade = gang.name ~= 'none' and gradeOf(gang) or nil,
        cash = toInteger(money.cash, 0) or 0, bank = toInteger(money.bank, 0) or 0,
        down = metadata.isdead == true or metadata.inlaststand == true,
    }
end
local spectatingOf = function(src) return EsAdminServer.spectatingTarget and EsAdminServer.spectatingTarget(src) or nil end

RegisterNetEvent('cortex-admin:server:requestPlayerRoster', function()
    local src = source
    if not allowRequest(src, 'players-roster', 6, 5000) or not canOpenMenu(src) then return end
    local withCharacter = Config.HasQBX == true and GetResourceState('qbx_core') == 'started'
        and (hasPermission(src, 'qbx.inspectCharacter') or hasPermission(src, 'player.setJob'))
    local withIdentity = withCharacter
    if Config.HasQBX and QboxAdmin then
        for id, action in pairs(QboxAdmin.actions) do
            if not action.selfOnly and hasPermission(src, id) then withIdentity = true; break end
        end
    end
    local adminPed = GetPlayerPed(src)
    local origin = adminPed and adminPed > 0 and DoesEntityExist(adminPed) and GetEntityCoords(adminPed) or nil
    local bucket = GetPlayerRoutingBucket(src)
    local watching = spectatingOf(src)
    local roster = {}
    local online = GetPlayers()
    local limit = toInteger(Config.Players and Config.Players.maxRosterEntries, 1, 2048) or 256
    for _, value in ipairs(online) do
        local id = toInteger(value, 1, 65535)
        if id and GetPlayerName(id) then
            local ped = GetPlayerPed(id)
            local entry = {
                id = id, name = trimString(GetPlayerName(id), 96) or ('Player %d'):format(id),
                session = playerSession(id),
                ping = toInteger(GetPlayerPing(id), 0, 9999) or 0, bucket = toInteger(GetPlayerRoutingBucket(id), 0, 65535) or 0,
                isSelf = id == src, frozen = frozenPlayers[id] == true, spectating = watching == id,
            }
            if ped and ped > 0 and DoesEntityExist(ped) then
                local health = safe(GetEntityHealth, ped)
                local maxHealth = safe(GetEntityMaxHealth, ped) or 200
                -- Player peds die at 100 of 200: show the living range as 0-100%.
                entry.health = maxHealth > 100 and percent((health or 0) - 100, maxHealth - 100) or percent(health, maxHealth)
                entry.armour = toInteger(safe(GetPedArmour, ped), 0, 100)
                entry.dead = (health or 0) <= (maxHealth > 100 and 100 or 0)
                local coords = GetEntityCoords(ped)
                if origin and coords and entry.bucket == bucket then
                    entry.distance = math.floor(#(vector3(coords.x, coords.y, coords.z) - vector3(origin.x, origin.y, origin.z)) + 0.5)
                end
                local vehicle = safe(GetVehiclePedIsIn, ped, false)
                if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                    entry.vehicle = { model = GetEntityModel(vehicle), driver = safe(GetPedInVehicleSeat, vehicle, -1) == ped }
                end
            end
            if withCharacter then
                entry.character = characterOf(id)
                if entry.character and entry.character.down then entry.dead = true end
            end
            if withIdentity then entry.identity = { citizenid = EsAdminBridge.getPlayerCitizenId(id) } end
            roster[#roster + 1] = entry
            if #roster >= limit then break end
        end
    end
    TriggerClientEvent('cortex-admin:client:playerRoster', src, roster, withCharacter,
        { total = #online, limit = limit, truncated = #online > #roster })
end)

RegisterNetEvent('cortex-admin:server:requestPlayerDirectory', function()
    local src = source
    if not allowRequest(src, 'player-directory-read', 6, 10000) or not canOpenMenu(src) then return end
    TriggerClientEvent('cortex-admin:client:setPlayerDirectory', src, buildPlayerDirectory(src))
end)

local function setWorldTime(hour, minute, changedState)
    hour = toInteger(hour, 0, 23)
    minute = toInteger(minute, 0, 59)
    if hour == nil or minute == nil then return false end

    if not EsAdminServer.setWorldClock(hour, minute) then return false end
    changedState.hour = hour
    changedState.minute = minute
    return true
end

local function timeCommandReply(src, kind, message)
    if src == 0 then
        print('[cortex-admin] ' .. message)
    else
        TriggerClientEvent('cortex-admin:client:notify', src, kind, message)
    end
end

RegisterCommand('time', function(src, args)
    if not EsAdminServer.ownsWorld() and not EsAdminServer.weatherOwnsClock() then
        timeCommandReply(src, 'error', 'Time is controlled by another resource or disabled in shared/config.lua.')
        return
    end
    if src ~= 0 then
        if not allowRequest(src, 'privileged-write', 15, 5000) then return end
        if not hasPermission(src, 'world.time') then
            timeCommandReply(src, 'error', 'You do not have permission to set the time.')
            return
        end
    end

    local first = args[1] and args[1]:lower() == 'set' and 2 or 1
    local value = args[first] and args[first]:lower()
    local count = #args - first + 1
    local hour, minute
    if value == 'day' and count == 1 then
        hour, minute = 12, 0
    elseif value and value:match('^%d+$') and (count == 1 or count == 2) then
        local minuteArg = args[first + 1] or '0'
        if minuteArg:match('^%d+$') then
            hour, minute = value, minuteArg
        end
    end

    local changedState = {}
    if not setWorldTime(hour, minute, changedState) then
        local valid = toInteger(hour, 0, 23) and toInteger(minute, 0, 59)
        timeCommandReply(src, 'error', valid and 'cortex-weather did not accept the time.'
            or 'Usage: /time [set] <day|hour> [minute]. Hour: 0-23; minute: 0-59 (default 00).')
        return
    end

    if EsAdminServer.ownsWorld() then EsAdminServer.publishWorldState(-1, true) end
    timeCommandReply(src, 'success', ('Time set to %02d:%02d.'):format(changedState.hour, changedState.minute))
end, false) -- Authorization uses the same server-side world.time permission as the menu.

RegisterNetEvent('cortex-admin:server:setWorldState', function(payload)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(payload) ~= 'table' then return end

    local changedState = {}

    if payload.weather ~= nil and hasPermission(src, 'world.weather') then
        local weather = normalizeWeather(payload.weather)
        if weather then
            worldState.weather = weather
            changedState.weather = weather
        end
    end

    local refused = false
    if payload.hour ~= nil and hasPermission(src, 'world.time') then
        local valid = toInteger(payload.hour, 0, 23) ~= nil and toInteger(payload.minute, 0, 59) ~= nil
        if not setWorldTime(payload.hour, payload.minute, changedState) and valid then refused = true end
    end

    if payload.freezeTime ~= nil and hasPermission(src, 'world.freezeTime') then
        local freezeTime = toBoolean(payload.freezeTime)
        if freezeTime ~= nil then
            if EsAdminServer.freezeWorldTime(freezeTime) then
                changedState.freezeTime = freezeTime
            else
                refused = true
            end
        end
    end

    if payload.blackout ~= nil and hasPermission(src, 'world.blackout') then
        local blackout = toBoolean(payload.blackout)
        if blackout ~= nil then
            worldState.blackout = blackout
            changedState.blackout = blackout
        end
    end

    -- cortex-weather publishes its own clock; a delegated snapshot would only make clients re-request permissions.
    if next(changedState) and EsAdminServer.ownsWorld() then
        EsAdminServer.publishWorldState(-1, true)
    elseif refused and EsAdminServer.weatherOwnsClock() then
        -- The requester's snapshot re-reads cortex-weather's clock, so Freeze Time stops showing the refused value.
        EsAdminServer.publishWorldState(src)
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'cortex-weather did not accept the time change.')
    end
end)

RegisterNetEvent('cortex-admin:server:setUiPresence', function(data)
    local src = source
    if not allowRequest(src, 'menu-presence', 8, 5000) or not canOpenMenu(src) then
        uiPresence[src] = nil
        return
    end
    if type(data) ~= 'table' then
        return
    end

    uiPresence[src] = data.open == true
end)

RegisterNetEvent('cortex-admin:server:requestWardrobeShareTargets', function(requestId)
    local src = source
    if not allowRequest(src, 'wardrobe-read', 6, 5000)
        or not canOpenMenu(src)
        or uiPresence[src] ~= true
        or type(requestId) ~= 'string'
        or requestId == ''
        or #requestId > 96 then
        return
    end

    local targets = {}
    for playerId, isOpen in pairs(uiPresence) do
        if playerId ~= src
            and isOpen == true
            and GetPlayerName(playerId)
            and arePlayersNearby(src, playerId, WARDROBE_SHARE_RADIUS) then
            targets[#targets + 1] = playerId
        end
    end

    table.sort(targets)
    TriggerClientEvent('cortex-admin:client:receiveWardrobeShareTargets', src, requestId, {
        radius = WARDROBE_SHARE_RADIUS,
        targets = targets,
    })
end)

RegisterNetEvent('cortex-admin:server:shareWardrobe', function(data)
    local src = source
    if not allowRequest(src, 'wardrobe-write', 3, 10000)
        or not canOpenMenu(src)
        or uiPresence[src] ~= true
        or type(data) ~= 'table' then
        return
    end

    local target = toInteger(data.target, 1)
    if not target or target == src or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player is unavailable.')
        return
    end

    if uiPresence[target] ~= true then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player must have the menu open.')
        return
    end

    if not arePlayersNearby(src, target, WARDROBE_SHARE_RADIUS) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player must be nearby.')
        return
    end

    local outfit = sanitizeWardrobe(data.outfit)
    if not outfit then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Shared wardrobe payload was invalid.')
        return
    end

    local shareId = ('wardrobe:%d:%d:%d'):format(src, target, GetGameTimer())
    local senderName = GetPlayerName(src) or ('Player %d'):format(src)

    TriggerClientEvent('cortex-admin:client:receiveWardrobeShare', target, {
        shareId = shareId,
        senderId = src,
        senderName = senderName,
        title = trimString(data.title, 64) or 'Current Outfit',
        outfit = outfit,
    })

    TriggerClientEvent('cortex-admin:client:notify', src, 'success', ('Shared current outfit with %s.'):format(GetPlayerName(target) or ('Player %d'):format(target)))
    TriggerClientEvent('cortex-admin:client:notify', target, 'info', ('%s shared an outfit with you.'):format(senderName))
end)

-- Player actions answer with a result the Players console shows inline; the
-- admin still gets a notification when the console is closed.
local function playerResult(src, requestId, ok, message)
    TriggerClientEvent('cortex-admin:client:playerResult', src, type(requestId) == 'string' and requestId:sub(1, 40) or nil, ok == true, message)
end
EsAdminServer = EsAdminServer or {}
EsAdminServer.playerResult = playerResult

RegisterNetEvent('cortex-admin:server:playerAction', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end

    local action = trimString(data.action, 16)
    local target = toInteger(data.target, 1)

    if not action or not allowedPlayerActions[action] or not target then return end
    local required = action == 'freeze' and 'player.freezeTarget' or 'player.' .. action
    if not hasPermission(src, required) then
        if EsAdminServer.vmenuDenied then EsAdminServer.vmenuDenied(src, required) end
        playerResult(src, data.requestId, false, 'You do not have permission to use this action.')
        return
    end
    local requestId = data.requestId
    if not targetSessionMatches(target, data.targetSession) then
        playerResult(src, requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    if not GetPlayerName(target) then playerResult(src, requestId, false, 'That player is no longer online.'); return end
    local name = GetPlayerName(target)
    if target == src and (action == 'kick' or action == 'ban' or action == 'freeze') then
        playerResult(src, requestId, false, 'Choose another player.')
        return
    end

    if action == 'kick' then
        if not hasPermission(src, 'player.kick') then return end
        if IsPlayerAceAllowed(target, 'vMenu.DontKickMe') then
            playerResult(src, requestId, false, ('%s is protected from kicks.'):format(name))
            return
        end
        local reason = trimString(data.reason, 160) or 'Kicked by staff.'
        if not EsAdminVmenuPolicy or EsAdminVmenuPolicy.get('vmenu_log_kick_actions', true) then print(('[cortex-admin] %s kicked %s (%d): %s'):format(GetPlayerName(src) or 'Console', GetPlayerName(target) or 'Unknown', target, reason)) end
        DropPlayer(target, reason)
        playerResult(src, requestId, true, ('Kicked %s.'):format(name))
    elseif action == 'ban' then
        if not hasPermission(src, 'player.ban') then return end
        if IsPlayerAceAllowed(target, 'vMenu.DontBanMe') then
            playerResult(src, requestId, false, ('%s is protected from bans.'):format(name))
            return
        end
        local identifiers = GetPlayerIdentifiers(target)
        local reason = trimString(data.reason, 160) or 'Banned by staff.'
        local duration = toInteger(data.duration, 0, 525600)
        if duration == nil then return end
        local durationPermission = duration > 0 and 'vMenu.OnlinePlayers.TempBan' or 'vMenu.OnlinePlayers.PermBan'
        if not hasPermission(src, 'player.ban', { durationPermission, 'vMenu.OnlinePlayers.All', 'vMenu.Everything' }) then
            playerResult(src, requestId, false, duration > 0 and 'You do not have permission to issue temporary bans.'
                or 'You do not have permission to issue permanent bans.')
            return
        end
        local adminName = GetPlayerName(src) or 'Console'
        local entry = EsAdminServer.addBan(identifiers, reason, adminName, duration, GetPlayerName(target))
        if not entry then
            playerResult(src, requestId, false, 'The ban could not be saved: no durable identifier was available.')
            return
        end
        if not EsAdminVmenuPolicy or EsAdminVmenuPolicy.get('vmenu_log_ban_actions', true) then print(('[cortex-admin] %s banned %s (%d, %s): %s'):format(adminName, name, target, entry.id or 'unknown', reason)) end
        if targetSessionMatches(target, data.targetSession) then DropPlayer(target, EsAdminServer.vmenuBanMessage and EsAdminServer.vmenuBanMessage(reason) or reason) end
        playerResult(src, requestId, true, duration and duration > 0 and ('Banned %s for %d minutes.'):format(name, duration) or ('Banned %s permanently.'):format(name))
    elseif action == 'freeze' then
        if not hasPermission(src, 'player.freezeTarget') then
            playerResult(src, requestId, false, 'You do not have permission to freeze another player.')
            return
        end
        -- An explicit state wins; otherwise toggle the shared server state.
        local enabled = toBoolean(data.enabled)
        if enabled == nil then enabled = frozenPlayers[target] ~= true end
        frozenPlayers[target] = enabled or nil
        TriggerClientEvent('cortex-admin:client:freeze', target, enabled)
        playerResult(src, requestId, true, (enabled and 'Froze %s.' or 'Unfroze %s.'):format(name))
    elseif action == 'bring' or action == 'goto' then
        if not hasPermission(src, action == 'bring' and 'player.bring' or 'player.goto') then return end
        local name = GetPlayerName(target) or ('Player %d'):format(target)
        if target == src then
            playerResult(src, data.requestId, false, action == 'bring' and 'You cannot bring yourself.' or 'You are already here.')
            return
        end
        if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then
            playerResult(src, data.requestId, false, ('%s is in routing bucket %d and you are in %d.'):format(
                name, GetPlayerRoutingBucket(target), GetPlayerRoutingBucket(src)))
            return
        end
        -- The anchor is where the player lands beside: the admin for Bring, the target for Go to.
        local anchor = action == 'bring' and src or target
        local moving = action == 'bring' and target or src
        local anchorPed = GetPlayerPed(anchor)
        local coords = anchorPed and anchorPed > 0 and DoesEntityExist(anchorPed) and sanitizeCoords(GetEntityCoords(anchorPed))
        local heading = anchorPed and anchorPed > 0 and GetEntityHeading(anchorPed)
        if not coords or type(heading) ~= 'number' or heading ~= heading then
            playerResult(src, data.requestId, false, action == 'bring' and 'Your position is unavailable.' or ('%s has no position yet.'):format(name))
            return
        end
        TriggerClientEvent('cortex-admin:client:teleport', moving, coords, heading % 360, { beside = true, withVehicle = true })
        playerResult(src, data.requestId, true, action == 'bring' and ('Brought %s to you.'):format(name) or ('Went to %s.'):format(name))
    end
end)

AddEventHandler('playerConnecting', function(name, setKickReason)
    local identifiers = GetPlayerIdentifiers(source)
    local entry = EsAdminServer.findBan(identifiers)
    if entry then
        local expiresAt = entry.expiresAt or entry.expires
        local expiresText = expiresAt and os.date('%c', expiresAt) or 'Never'
        local reason = ('Banned: %s (Expires: %s)'):format(entry.reason or 'No reason', expiresText)
        setKickReason(EsAdminServer.vmenuBanMessage and EsAdminServer.vmenuBanMessage(reason) or reason)
        CancelEvent()
    end
end)

AddEventHandler('playerDropped', function()
    playerSessions[source] = nil
    frozenPlayers[source] = nil
    uiPresence[source] = nil
    permissionCache[source] = nil
    requestBuckets[source] = nil
    pendingAdminCarRequests[source] = nil
end)

-- =============================================================================
-- RESOURCE MANAGEMENT
-- =============================================================================

local function getResourceList()
    local resources = {}
    local num = GetNumResources()

    for i = 0, num - 1 do
        local name = GetResourceByFindIndex(i)
        if name then
            local state = GetResourceState(name)
            local version = GetResourceMetadata(name, 'version', 0) or 'Unknown'
            local author = GetResourceMetadata(name, 'author', 0) or 'Unknown'
            local description = GetResourceMetadata(name, 'description', 0) or 'No description'
            
            table.insert(resources, {
                name = name,
                state = state, -- started, stopped, starting, stopping, missing
                version = version,
                author = author,
                description = description
            })
        end
    end

    -- Sort resources alphabetically by name
    table.sort(resources, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    return resources
end

local addonVehiclesCache = {
    list = {},
    ready = false,
    stale = true,
    scanning = false,
    refreshDueAt = 0,
    refreshArmed = false,
    waiters = {},
    recipients = {},
    signature = nil,
}

local ADDON_VEHICLES_SLICE_MS = 2
local ADDON_VEHICLES_REFRESH_DELAY_MS = 3000
local ADDON_VEHICLE_FILE_SUFFIXES = { '.meta', '.yft' }
local VEHICLE_META_DATA_TYPE = 'VEHICLE_METADATA_FILE'

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function stripQuotes(value)
    local normalized = trim(value)
    local first = normalized:sub(1, 1)
    local last = normalized:sub(-1)
    if (first == '"' and last == '"') or (first == "'" and last == "'") then
        return trim(normalized:sub(2, -2))
    end
    return normalized
end

local function prettifyModelName(model)
    local normalized = trim(model):gsub('_', ' ')
    return normalized:gsub('(%a)([%w]*)', function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

local function normalizePath(value)
    local normalized = trim(value):gsub('\\', '/')
    normalized = normalized:gsub('/+', '/')
    return normalized
end

local function getResourceRoot(resourceName)
    return normalizePath(GetResourcePath(resourceName) or '')
end

local function resolveResourceFile(resourceName, rawPath)
    local path = normalizePath(stripQuotes(rawPath))
    if path == '' then
        return nil, nil
    end

    local linkedResource, linkedPath = path:match('^@([^/]+)/(.+)$')
    if linkedResource and linkedPath then
        return trim(linkedResource), normalizePath(linkedPath)
    end

    return resourceName, path
end

local function parseDataFileEntry(entry)
    if type(entry) ~= 'string' or entry == '' then
        return nil, nil
    end

    local dataType, filePath = entry:match('^%s*([^%s]+)%s+(.+)%s*$')
    if not dataType or not filePath then
        return nil, nil
    end

    dataType = stripQuotes(dataType):upper()
    filePath = stripQuotes(filePath)
    return dataType, filePath
end

local function parseDataFileExtra(extra)
    if type(extra) ~= 'string' or extra == '' then
        return nil
    end

    local filePath = extra:match('^%s*%[%s*"([^"]+)"')
        or extra:match("^%s*%[%s*'([^']+)'")
        or extra:match('"file"%s*:%s*"([^"]+)"')
        or extra:match("'file'%s*:%s*'([^']+)'")
        or extra:match('"filename"%s*:%s*"([^"]+)"')
        or extra:match("'filename'%s*:%s*'([^']+)'")
        or extra:match('"path"%s*:%s*"([^"]+)"')
        or extra:match("'path'%s*:%s*'([^']+)'")

    return filePath and stripQuotes(filePath) or nil
end

-- server/files.js walks the folder with Node's fs; no shell is started.
local fileListingWarned = false
local scanFileListings
local function listResourceFiles(resourceName)
    if scanFileListings and scanFileListings[resourceName] then
        return scanFileListings[resourceName]
    end
    local ok, files = pcall(function()
        return exports[GetCurrentResourceName()]:listResourceFiles(resourceName, ADDON_VEHICLE_FILE_SUFFIXES)
    end)
    if ok and type(files) == 'table' then
        if scanFileListings then
            scanFileListings[resourceName] = files
        end
        return files
    end
    if not fileListingWarned then
        fileListingWarned = true
        print(('[cortex-admin] Addon vehicle file scan unavailable (server/files.js did not load): %s'):format(tostring(files)))
    end
    return {}
end

local function wildcardToPattern(wildcard)
    local pattern = normalizePath(wildcard):lower()
    pattern = pattern:gsub('([%^%$%(%)%%%.%[%]%+%-%?])', '%%%1')
    pattern = pattern:gsub('%*%*', '\0')
    pattern = pattern:gsub('%*', '[^/]*')
    pattern = pattern:gsub('\0', '.*')
    return '^' .. pattern .. '$'
end

local function pathMatchesWildcard(path, wildcard)
    return normalizePath(path):lower():match(wildcardToPattern(wildcard)) ~= nil
end

local function makeVehicleTargetKey(dataResourceName, path)
    return ('%s|%s'):format((dataResourceName or ''):lower(), (path or ''):lower())
end

local function addVehicleMetaTarget(targets, seen, ownerResourceName, dataResourceName, path, content)
    local normalized = normalizePath(path)
    if trim(dataResourceName) == '' or normalized == '' then
        return false
    end

    local key = makeVehicleTargetKey(dataResourceName, normalized)
    if seen[key] then
        return false
    end

    seen[key] = true
    targets[#targets + 1] = {
        ownerResource = ownerResourceName,
        dataResource = dataResourceName,
        path = normalized,
        content = content,
    }
    return true
end

local function getWildcardFallbackPaths(wildcardPath)
    local paths = {}
    local seen = {}

    local function push(path)
        local normalized = normalizePath(path):gsub('^/', '')
        if normalized == '' or seen[normalized:lower()] then
            return
        end
        seen[normalized:lower()] = true
        paths[#paths + 1] = normalized
    end

    local compact = normalizePath(wildcardPath)
    compact = compact:gsub('/%*%*/', '/')
    compact = compact:gsub('%*%*/', '')
    compact = compact:gsub('/%*', '/')
    compact = compact:gsub('%*', '')
    compact = compact:gsub('/+', '/')

    push(compact)
    push('data/vehicles.meta')
    push('vehicles.meta')

    return paths
end

local function expandVehicleMetaPattern(ownerResourceName, dataResourceName, wildcardPath, targets, seen, stats)
    local root = getResourceRoot(dataResourceName)
    if root == '' then
        return
    end

    local before = #targets
    local files = listResourceFiles(dataResourceName)
    for i = 1, #files do
        local relative = normalizePath(files[i])
        if pathMatchesWildcard(relative, wildcardPath) then
            if addVehicleMetaTarget(targets, seen, ownerResourceName, dataResourceName, relative) then
                stats.resolvedMetaFiles = stats.resolvedMetaFiles + 1
            end
        end
    end

    if #targets > before then
        return
    end

    local fallbackPaths = getWildcardFallbackPaths(wildcardPath)
    for i = 1, #fallbackPaths do
        local path = fallbackPaths[i]
        local content = LoadResourceFile(dataResourceName, path)
        if content then
            if addVehicleMetaTarget(targets, seen, ownerResourceName, dataResourceName, path, content) then
                stats.resolvedMetaFiles = stats.resolvedMetaFiles + 1
            end
        end
    end
end

local function collectVehicleMetaTargetsFromManifest(resourceName, targets, seen, stats)
    local manifest = LoadResourceFile(resourceName, 'fxmanifest.lua')
        or LoadResourceFile(resourceName, '__resource.lua')
    if type(manifest) ~= 'string' or manifest == '' then
        return false
    end

    local foundDeclaration = false
    for line in manifest:gmatch('[^\r\n]+') do
        local dataType, filePath = line:match("data_file%s*%(%s*['\"]([^'\"]+)['\"]%s*,?%s*['\"]([^'\"]+)['\"]")
        if not dataType then
            dataType, filePath = line:match("data_file%s+['\"]([^'\"]+)['\"]%s+['\"]([^'\"]+)['\"]")
        end

        if stripQuotes(dataType):upper() == VEHICLE_META_DATA_TYPE then
            foundDeclaration = true
            stats.vehicleMetaDeclarations = stats.vehicleMetaDeclarations + 1

            local dataResourceName, resolvedPath = resolveResourceFile(resourceName, filePath)
            if dataResourceName and resolvedPath then
                if resolvedPath:find('*', 1, true) then
                    expandVehicleMetaPattern(resourceName, dataResourceName, resolvedPath, targets, seen, stats)
                else
                    local content = LoadResourceFile(dataResourceName, resolvedPath)
                    if content then
                        if addVehicleMetaTarget(targets, seen, resourceName, dataResourceName, resolvedPath, content) then
                            stats.resolvedMetaFiles = stats.resolvedMetaFiles + 1
                        end
                    else
                        stats.missingMetaFiles = stats.missingMetaFiles + 1
                    end
                end
            end
        end
    end

    return foundDeclaration
end

local function collectVehicleMetaTargets(resourceName, targets, seen, stats)
    local count = GetNumResourceMetadata(resourceName, 'data_file') or 0
    local foundDeclaration = false

    for i = 0, count - 1 do
        local rawEntry = GetResourceMetadata(resourceName, 'data_file', i)
        local dataType, filePath = parseDataFileEntry(rawEntry)
        if not dataType and type(rawEntry) == 'string' then
            dataType = stripQuotes(rawEntry):upper()
            filePath = parseDataFileExtra(GetResourceMetadata(resourceName, 'data_file_extra', i))
        end

        if dataType == VEHICLE_META_DATA_TYPE and filePath then
            foundDeclaration = true
            stats.vehicleMetaDeclarations = stats.vehicleMetaDeclarations + 1

            local dataResourceName, resolvedPath = resolveResourceFile(resourceName, filePath)
            if dataResourceName and resolvedPath then
                if resolvedPath:find('*', 1, true) then
                    expandVehicleMetaPattern(resourceName, dataResourceName, resolvedPath, targets, seen, stats)
                else
                    local content = LoadResourceFile(dataResourceName, resolvedPath)
                    if content then
                        if addVehicleMetaTarget(targets, seen, resourceName, dataResourceName, resolvedPath, content) then
                            stats.resolvedMetaFiles = stats.resolvedMetaFiles + 1
                        end
                    else
                        stats.missingMetaFiles = stats.missingMetaFiles + 1
                    end
                end
            end
        end
    end

    if not foundDeclaration and count > 0 then
        foundDeclaration = collectVehicleMetaTargetsFromManifest(resourceName, targets, seen, stats)
    end

    return foundDeclaration
end

local function readXmlTag(block, tagName)
    local value = block:match('<%s*' .. tagName .. '%s*>%s*([^<]-)%s*<%s*/%s*' .. tagName .. '%s*>')
    return trim(value)
end

local function parseVehiclesMeta(xml, target, byModel, stats, metadataResources, yieldIfSliceSpent)
    if type(xml) ~= 'string' or xml == '' then
        return
    end

    for item in xml:gmatch('<%s*Item[^>]*>(.-)<%s*/%s*Item%s*>') do
        local model = readXmlTag(item, 'modelName'):lower()
        if model ~= '' then
            if byModel[model] then
                stats.duplicateModels = stats.duplicateModels + 1
            else
                local gameName = readXmlTag(item, 'gameName')
                local makeName = readXmlTag(item, 'vehicleMakeName')

                byModel[model] = {
                    model = model,
                    name = gameName ~= '' and gameName or prettifyModelName(model),
                    gameName = gameName ~= '' and gameName or nil,
                    makeName = makeName ~= '' and makeName or nil,
                    resource = target.ownerResource,
                    metaPath = target.path,
                    sourceType = 'metadata',
                    ownerResource = target.ownerResource,
                    dataResource = target.dataResource,
                }

                stats.metadataModels = stats.metadataModels + 1
                metadataResources[target.ownerResource] = true
            end
        end
        if yieldIfSliceSpent then yieldIfSliceSpent() end
    end
end

local function collectStreamFallbackModels(resourceName, byModel, stats, yieldIfSliceSpent)
    local root = getResourceRoot(resourceName)
    if root == '' then
        return
    end

    local files = listResourceFiles(resourceName)
    local added = 0
    for i = 1, #files do
        if i % 64 == 0 then yieldIfSliceSpent() end
        local relative = normalizePath(files[i])
        local lower = relative:lower()
        local inStreamFolder = lower:sub(1, 7) == 'stream/' or lower:find('/stream/', 1, true) ~= nil
        if inStreamFolder and lower:sub(-4) == '.yft' and lower:sub(-7) ~= '_hi.yft' then
            local model = lower:match('([^/]+)%.yft$')
            if model and model ~= '' then
                if byModel[model] then
                    stats.duplicateModels = stats.duplicateModels + 1
                else
                    byModel[model] = {
                        model = model,
                        name = prettifyModelName(model),
                        resource = resourceName,
                        metaPath = relative,
                        sourceType = 'stream_fallback',
                        ownerResource = resourceName,
                        dataResource = resourceName,
                    }
                    stats.streamFallbackModels = stats.streamFallbackModels + 1
                    added = added + 1
                end
            end
        end
    end

    if added > 0 then
        stats.streamFallbackResources = stats.streamFallbackResources + 1
    end
end

local function getStartedResources()
    local resources = {}
    local count = GetNumResources()
    for i = 0, count - 1 do
        local resourceName = GetResourceByFindIndex(i)
        if resourceName and GetResourceState(resourceName) == 'started' then
            resources[#resources + 1] = resourceName
        end
    end
    return resources
end

local function scanAddonVehicles()
    local sliceStart = GetGameTimer()
    local function yieldIfSliceSpent()
        if GetGameTimer() - sliceStart >= ADDON_VEHICLES_SLICE_MS then
            Wait(0)
            sliceStart = GetGameTimer()
        end
    end

    local byModel = {}
    local metadataResources = {}
    local metaTargets = {}
    local seenMetaTargets = {}
    local resourcesWithVehicleMeta = {}
    local stats = {
        startedResources = 0,
        vehicleMetaResources = 0,
        vehicleMetaDeclarations = 0,
        resolvedMetaFiles = 0,
        missingMetaFiles = 0,
        parsedMetaFiles = 0,
        metadataModels = 0,
        streamFallbackModels = 0,
        streamFallbackResources = 0,
        duplicateModels = 0,
    }

    local resources = getStartedResources()
    stats.startedResources = #resources

    for i = 1, #resources do
        local resourceName = resources[i]
        if collectVehicleMetaTargets(resourceName, metaTargets, seenMetaTargets, stats) then
            resourcesWithVehicleMeta[resourceName] = true
            stats.vehicleMetaResources = stats.vehicleMetaResources + 1
        end
        yieldIfSliceSpent()
    end

    for i = 1, #metaTargets do
        local target = metaTargets[i]
        local content = target.content or LoadResourceFile(target.dataResource, target.path)
        target.content = nil
        if content and content ~= '' then
            stats.parsedMetaFiles = stats.parsedMetaFiles + 1
            parseVehiclesMeta(content, target, byModel, stats, metadataResources, yieldIfSliceSpent)
        end
        yieldIfSliceSpent()
    end

    for resourceName in pairs(resourcesWithVehicleMeta) do
        if not metadataResources[resourceName] then
            collectStreamFallbackModels(resourceName, byModel, stats, yieldIfSliceSpent)
            yieldIfSliceSpent()
        end
    end

    local list = {}
    for _, entry in pairs(byModel) do
        list[#list + 1] = entry
    end

    table.sort(list, function(a, b)
        local nameA = (a.name or a.model or ''):lower()
        local nameB = (b.name or b.model or ''):lower()
        if nameA ~= nameB then
            return nameA < nameB
        end
        return (a.model or ''):lower() < (b.model or ''):lower()
    end)

    if Config.Debug or (#list == 0 and not addonVehiclesCache.ready) then
        print(('[cortex-admin] Addon vehicle scan indexed %d models (metadata: %d, stream fallback: %d, duplicates: %d, started resources: %d, vehicle meta resources: %d, declarations: %d, resolved meta files: %d, missing meta files: %d, parsed meta files: %d, fallback resources: %d). The list is rebuilt whenever a resource starts or stops.'):format(
            #list,
            stats.metadataModels,
            stats.streamFallbackModels,
            stats.duplicateModels,
            stats.startedResources,
            stats.vehicleMetaResources,
            stats.vehicleMetaDeclarations,
            stats.resolvedMetaFiles,
            stats.missingMetaFiles,
            stats.parsedMetaFiles,
            stats.streamFallbackResources
        ))
    end

    return list
end

local function addonVehiclesSignature(list)
    local parts = {}
    for i = 1, #list do
        parts[i] = ('%s|%s|%s'):format(list[i].model, list[i].name or '', list[i].makeName or '')
    end
    return table.concat(parts, '\n')
end

local function refreshAddonVehicles()
    local cache = addonVehiclesCache
    if cache.scanning or not cache.stale then return end
    cache.scanning = true
    local previousSignature = cache.signature
    while cache.stale do
        cache.stale = false
        scanFileListings = {}
        local ok, list = pcall(scanAddonVehicles)
        scanFileListings = nil
        if ok then
            cache.list = list
            cache.signature = addonVehiclesSignature(list)
        else
            print(('[cortex-admin] Addon vehicle scan failed: %s'):format(tostring(list)))
            break
        end
    end
    cache.ready = true
    cache.scanning = false
    local targets = cache.waiters
    cache.waiters = {}
    if previousSignature ~= cache.signature then
        for src in pairs(cache.recipients) do
            targets[src] = true
        end
    end
    for src in pairs(targets) do
        if GetPlayerName(src) and canOpenMenu(src) and hasPermission(src, 'vehicle.spawn') then
            cache.recipients[src] = true
            TriggerClientEvent('cortex-admin:client:setAddonVehicles', src, cache.list)
        else
            cache.recipients[src] = nil
        end
    end
end

local function scheduleAddonVehiclesRefresh()
    local cache = addonVehiclesCache
    cache.stale = true
    cache.refreshDueAt = GetGameTimer() + ADDON_VEHICLES_REFRESH_DELAY_MS
    if cache.refreshArmed then return end
    cache.refreshArmed = true
    CreateThread(function()
        while GetGameTimer() < cache.refreshDueAt do
            Wait(cache.refreshDueAt - GetGameTimer())
        end
        cache.refreshArmed = false
        refreshAddonVehicles()
    end)
end

local currentResourceName = GetCurrentResourceName()
local photoCaptureDir = normalizePath(('%s/photos'):format(GetResourcePath(currentResourceName)))
local photoCaptureDirReady = false

local function ensurePhotoCaptureDir()
    if photoCaptureDirReady then
        return true
    end

    local ok, created = pcall(function()
        return exports[currentResourceName]:ensurePhotoDirectory()
    end)
    photoCaptureDirReady = ok and created == true
    return photoCaptureDirReady
end

local function sanitizePhotoFileSegment(value)
    value = tostring(value or 'player')
    value = value:gsub('[^%w%-_]+', '_')
    value = value:gsub('_+', '_')
    value = value:gsub('^_+', '')
    value = value:gsub('_+$', '')

    if value == '' then
        return 'player'
    end

    return value:sub(1, 32)
end

local function buildPhotoCapturePath(src)
    local playerName = sanitizePhotoFileSegment(GetPlayerName(src))
    local stamp = os.date('%Y%m%d-%H%M%S')
    local fileName = ('%s-%d-%s.jpg'):format(stamp, src, playerName)
    return normalizePath(('%s/%s'):format(photoCaptureDir, fileName)), ('photos/%s'):format(fileName)
end

local function affectsAddonVehicles(resourceName)
    if (GetNumResourceMetadata(resourceName, 'data_file') or 0) > 0 then
        return true
    end
    local list = addonVehiclesCache.list
    for i = 1, #list do
        if list[i].ownerResource == resourceName or list[i].dataResource == resourceName then
            return true
        end
    end
    return false
end

local function invalidateAddonVehiclesCache(reason)
    scheduleAddonVehiclesRefresh()
    if Config.Debug then
        print(('[cortex-admin] addon vehicle cache invalidated (%s)'):format(reason or 'unspecified'))
    end
end

RegisterNetEvent('cortex-admin:server:requestAddonVehicles', function()
    local src = source
    if not allowRequest(src, 'expensive-read', 4, 10000) then return end
    if not canOpenMenu(src) or not hasPermission(src, 'vehicle.spawn') then return end
    local cache = addonVehiclesCache
    if cache.ready then
        cache.recipients[src] = true
        TriggerClientEvent('cortex-admin:client:setAddonVehicles', src, cache.list)
        return
    end
    cache.waiters[src] = true
    refreshAddonVehicles()
end)

AddEventHandler('playerDropped', function()
    addonVehiclesCache.recipients[source] = nil
    addonVehiclesCache.waiters[source] = nil
end)

scheduleAddonVehiclesRefresh()

-- Shared screenshot-basic capture. `done(ok, relativePath)` runs at most once.
local function capturePhoto(src, done)
    if GetResourceState('screenshot-basic') ~= 'started' then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'screenshot-basic is not running.')
        return done(false)
    end

    if not ensurePhotoCaptureDir() then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed to prepare the photo output folder.')
        return done(false)
    end

    local sessionIdentifier = getSessionIdentifier(src)
    if not sessionIdentifier then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not verify your player session.')
        return done(false)
    end

    local absolutePath, relativePath = buildPhotoCapturePath(src)

    exports['screenshot-basic']:requestClientScreenshot(src, {
        fileName = absolutePath,
        encoding = 'jpg',
        quality = 0.95,
    }, function(err)
        if not sessionIdentifierMatches(src, sessionIdentifier) then return end

        if err then
            print(('[cortex-admin] failed to capture photo for %s (%d): %s'):format(GetPlayerName(src) or 'unknown', src, tostring(err)))
            TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Photo capture failed.')
            return done(false)
        end

        TriggerClientEvent('cortex-admin:client:copyText', src, absolutePath)
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', ('Photo saved to %s. Full path copied to clipboard.'):format(relativePath))
        done(true, relativePath)
    end)
end

RegisterNetEvent('cortex-admin:server:takePhoto', function()
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if not hasPermission(src, 'dev.takePhoto') then return end
    capturePhoto(src, function() end)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == currentResourceName then
        return
    end
    if not resourceName or not affectsAddonVehicles(resourceName) then
        return
    end
    invalidateAddonVehiclesCache(('resource start: %s'):format(resourceName))
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == currentResourceName then
        return
    end
    if not resourceName or not affectsAddonVehicles(resourceName) then
        return
    end
    invalidateAddonVehiclesCache(('resource stop: %s'):format(resourceName))
end)

RegisterNetEvent('cortex-admin:server:requestResources', function()
    local src = source
    if not allowRequest(src, 'expensive-read', 4, 10000) then return end
    if not hasPermission(src, 'server.resources') then return end
    
    TriggerClientEvent('cortex-admin:client:setResources', src, getResourceList())
end)

RegisterNetEvent('cortex-admin:server:resourceAction', function(data)
    local src = source
    if not allowRequest(src, 'resource-write', 4, 10000) then return end
    if type(data) ~= 'table' then return end

    local action = trimString(data.action, 16)
    local name = trimString(data.name, 64)

    if not action or not allowedResourceActions[action] or not name then return end
    if not hasPermission(src, 'server.resources') then return end
    if action == 'refresh' then
        ExecuteCommand('refresh')
        print(string.format('^3[cortex-admin] ^7Admin %s triggered global resource refresh', GetPlayerName(src)))
        TriggerClientEvent('cortex-admin:client:notify', src, 'info', 'Resource list refreshed')
        TriggerClientEvent('cortex-admin:client:setResources', src, getResourceList())
        return
    end

    if GetResourceState(name) == 'missing' then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', ('Resource not found: %s'):format(name))
        return
    end

    local protected = name == GetCurrentResourceName() or name == 'cortex-lib'
    for _, resource in ipairs(Config.ProtectedResources or {}) do
        if name == resource then protected = true; break end
    end
    if protected then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error',
            ('%s is protected. Use a controlled server-console restart.'):format(name))
        return
    end
    -- StartResource/StopResource act synchronously but do not reliably return true,
    -- so success is judged only by the resource state they leave behind.
    local current, expected, cycled = GetResourceState(name), nil, true
    if action == 'start' then
        expected = 'started'
        if current == 'stopped' then StartResource(name) end
    elseif action == 'stop' then
        expected = 'stopped'
        if current == 'started' then StopResource(name) end
    elseif action == 'ensure' or action == 'restart' then
        expected = 'started'
        if current == 'started' then StopResource(name) end
        -- A stop that did not take must not report the old instance as restarted.
        cycled = GetResourceState(name) == 'stopped'
        if cycled then StartResource(name) end
    end
    local final = GetResourceState(name)
    local ok = cycled and expected ~= nil and final == expected
    local message = ok and ('%s is %s.'):format(name, final)
        or ('Could not %s %s (state: %s). Check the server console.'):format(action, name, final)
    TriggerClientEvent('cortex-admin:client:notify', src, ok and 'success' or 'error', message)
    print(('[cortex-admin] Resource %s %s by %s: %s'):format(action, name, GetPlayerName(src) or 'Unknown', message))

    -- Send updated list back to the sender
    TriggerClientEvent('cortex-admin:client:setResources', src, getResourceList())
end)

-- =============================================================================
-- INVENTORY MANAGEMENT (QBX / ox_inventory)
-- =============================================================================

RegisterNetEvent('cortex-admin:server:getItems', function()
    local src = source
    if not allowRequest(src, 'expensive-read', 4, 10000) then return end
    if not hasPermission(src, 'inventory.giveItem') then return end

    local items = EsAdminBridge.getAllItems()
    if type(items) ~= 'table' then
        items = {}
    end

    TriggerClientEvent('cortex-admin:client:setItems', src, items)
end)

RegisterNetEvent('cortex-admin:server:giveItem', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'inventory.giveItem') then return end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    local itemName = trimString(data.item, 64)
    local amount = toInteger(data.amount, 1, 10000)

    if not target or not itemName or not amount then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end

    -- Verify target is online
    local targetName = GetPlayerName(target)
    if not targetName then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local success, err = EsAdminBridge.giveItem(target, itemName, amount)

    if success then
        local adminName = GetPlayerName(src) or 'Admin'
        print(string.format('^3[cortex-admin] ^7%s gave %dx %s to %s (ID: %d)', adminName, amount, itemName, targetName, target))
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Gave %dx %s to %s', amount, itemName, targetName))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', err or 'Failed to give item')
    end
end)

-- =============================================================================
-- GARAGE MANAGEMENT (QBX / qbx_vehicles)
-- =============================================================================

exports('CortexInventoryAuthorizeGarage', function(src, model)
    if not hasPermission(src, 'garage.spawnVehicle') then return false end
    if model == nil then return true end
    if type(EsAdminServer.authorizeModel) ~= 'function' then return false end
    return EsAdminServer.authorizeModel(src, 'vehicle', model, 'garage.spawnVehicle') == true
end)

RegisterNetEvent('cortex-admin:server:getPlayerGarage', function()
    local src = source
    if not allowRequest(src, 'expensive-read', 4, 10000) then return end
    if not hasPermission(src, 'garage.spawnVehicle') then return end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    local vehicles = EsAdminBridge.getPlayerVehicles(citizenid)
    if type(vehicles) ~= 'table' then
        vehicles = {}
    end

    TriggerClientEvent('cortex-admin:client:setGarageVehicles', src, vehicles)
end)

RegisterNetEvent('cortex-admin:server:spawnGarageVehicle', function(data)
    local src = source
    local actorSession = playerSession(src)
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'garage.spawnVehicle') then return end
    local ciGaragePlayer = GetResourceMetadata('ox_inventory', 'cortex_inventory_bridge', 0) == '1'
        and exports.qbx_core:GetPlayer(src) or nil
    local ciGarageCitizenid = ciGaragePlayer and ciGaragePlayer.PlayerData.citizenid

    local vehicleId = toInteger(data.vehicleId, 1, 2147483647)
    if not vehicleId then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid vehicle ID')
        return
    end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    -- Fetch the specific vehicle to verify ownership
    local vehicles = EsAdminBridge.getPlayerVehicles(citizenid)
    if not targetSessionMatches(src, actorSession) or EsAdminBridge.getPlayerCitizenId(src) ~= citizenid
        or not hasPermission(src, 'garage.spawnVehicle') then return end
    if type(vehicles) ~= 'table' then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Garage data is unavailable right now')
        return
    end

    local targetVehicle = nil
    for _, veh in ipairs(vehicles) do
        if veh.id == vehicleId then
            targetVehicle = veh
            break
        end
    end

    if not targetVehicle then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Vehicle not found in your garage')
        return
    end

    if type(EsAdminServer.authorizeModel) ~= 'function' then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Server model authorization is unavailable')
        return
    end
    local modelAllowed, modelReason = EsAdminServer.authorizeModel(src, 'vehicle', targetVehicle.model, 'garage.spawnVehicle')
    if not modelAllowed then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', modelReason == 'model_forbidden'
            and 'Your ACE permissions do not allow that whitelisted vehicle model'
            or 'Vehicle model authorization failed')
        return
    end

    if not targetSessionMatches(src, actorSession) or EsAdminBridge.getPlayerCitizenId(src) ~= citizenid
        or not hasPermission(src, 'garage.spawnVehicle') then return end

    if GetResourceMetadata('ox_inventory', 'cortex_inventory_bridge', 0) == '1' then
        if not ciGaragePlayer or exports.qbx_core:GetPlayer(src) ~= ciGaragePlayer
            or ciGaragePlayer.PlayerData.citizenid ~= ciGarageCitizenid then return end
        local netId, err = exports['cortex-inventory']:CortexLegacySpawnOwnedVehicle(src, vehicleId)
        TriggerClientEvent('cortex-admin:client:notify', src, netId and 'success' or 'error',
            netId and 'Owned vehicle spawned.' or ('Owned vehicle spawn unavailable: ' .. tostring(err)))
        return -- Never fall through to client spawning on a denied/unknown adapter result.
    end

    if type(EsAdminServer.spawnOwnedGarageVehicle) ~= 'function' then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Owned vehicle spawning is unavailable.')
        return
    end
    local netId, reason = EsAdminServer.spawnOwnedGarageVehicle(src, vehicleId)
    TriggerClientEvent('cortex-admin:client:notify', src, netId and 'success' or 'error',
        netId and 'Owned vehicle spawned.' or ('Owned vehicle spawn refused: ' .. tostring(reason)))
end)

local function giveVehicleKeys(src, vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false, 'Vehicle not found'
    end

    if GetResourceState('qbx_core') ~= 'started'
        or GetResourceState('qbx_vehiclekeys') ~= 'started' then
        return false, 'Qbox vehicle keys are not running'
    end

    local ok, err = pcall(function()
        exports.qbx_vehiclekeys:GiveKeys(src, vehicle, true)
    end)

    if not ok then
        return false, tostring(err)
    end

    return true
end

RegisterNetEvent('cortex-admin:server:giveVehicleKeys', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    local silent = type(data) == 'table' and data.silent == true

    if type(data) ~= 'table' then return end
    local authorizationActionId = trimString(data.authorizationActionId, 96)
    local keyGrantActions = {
        ['vehicle.giveKeys'] = true,
        ['vehicle.spawn'] = true,
        ['vehicle.personal'] = true,
        ['vehicle.load'] = true,
        ['garage.spawnVehicle'] = true,
    }
    if not authorizationActionId or keyGrantActions[authorizationActionId] ~= true
        or (not silent and authorizationActionId ~= 'vehicle.giveKeys')
        or not hasPermission(src, authorizationActionId) then return end

    local function notifyError(message)
        if silent then return end
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', message)
    end

    if GetResourceState('qbx_core') ~= 'started'
        or GetResourceState('qbx_vehiclekeys') ~= 'started' then return end

    local netId = toInteger(data.netId, 1, 65535)
    if not netId then return end
    -- A client-created vehicle may not have replicated when the request arrives.
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local timeoutAt = GetGameTimer() + 2000
    while (vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeoutAt do
        Wait(50)
        vehicle = NetworkGetEntityFromNetworkId(netId)
    end
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        notifyError('The selected entity is not a vehicle')
        return
    end

    local playerPed = GetPlayerPed(src)
    if playerPed == 0 or not DoesEntityExist(playerPed)
        or GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src) then return end

    local currentVehicle = GetVehiclePedIsIn(playerPed, false)
    if authorizationActionId == 'vehicle.giveKeys' then
        if vehicle ~= currentVehicle then
            notifyError('You must be inside the selected vehicle')
            return
        end
    else
        -- Spawn grants also work with auto-entry disabled. The selected vehicle
        -- must belong to this client's network ownership and be near the player.
        local playerCoords, vehicleCoords = GetEntityCoords(playerPed), GetEntityCoords(vehicle)
        local dx, dy, dz = playerCoords.x - vehicleCoords.x,
            playerCoords.y - vehicleCoords.y, playerCoords.z - vehicleCoords.z
        if NetworkGetEntityOwner(vehicle) ~= src or dx * dx + dy * dy + dz * dz > 225 then return end
    end

    -- Recheck permissions after the replication wait before consuming the grant.
    if not hasPermission(src, authorizationActionId) then return end
    local vehicleModel = GetEntityModel(vehicle)
    if type(EsAdminServer.consumeModelAuthorization) ~= 'function'
        or not EsAdminServer.consumeModelAuthorization(
            src,
            data.authorizationToken,
            'vehicle',
            authorizationActionId,
            vehicleModel
        ) then
        notifyError('Vehicle model authorization expired or did not match this vehicle')
        return
    end

    local success, err = giveVehicleKeys(src, vehicle)
    if not success then
        notifyError(('Failed to give keys: %s'):format(err))
        return
    end

    if not silent then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', 'Vehicle keys granted')
    end
end)

-- =============================================================================
-- QBX PLAYER MANAGEMENT COMMANDS
-- =============================================================================

RegisterNetEvent('cortex-admin:server:killPlayer', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.kill') then return end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    TriggerClientEvent('cortex-admin:client:killPed', target)
    local adminName = GetPlayerName(src) or 'Admin'
    print(string.format('^3[cortex-admin] ^7%s killed %s (ID: %d)', adminName, GetPlayerName(target), target))
    playerResult(src, data.requestId, true, 'Killed ' .. GetPlayerName(target) .. '.')
end)

RegisterNetEvent('cortex-admin:server:revivePlayer', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.reviveTarget') then return end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    if GetResourceState('cortex-death') == 'started' then
        local revived = exports['cortex-death']:Revive(target)
        if not revived then TriggerClientEvent('cortex-admin:client:revivePed', target) end
    else
        TriggerClientEvent('cortex-admin:client:revivePed', target)
    end
    local adminName = GetPlayerName(src) or 'Admin'
    print(string.format('^3[cortex-admin] ^7%s revived %s (ID: %d)', adminName, GetPlayerName(target), target))
    playerResult(src, data.requestId, true, 'Revived ' .. GetPlayerName(target) .. '.')
end)

-- /revive and the menu's self revive while cortex-death owns death state.
RegisterNetEvent('cortex-admin:server:reviveSelf', function()
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if not hasPermission(src, 'player.revive') then return end
    if GetResourceState('cortex-death') == 'started' and exports['cortex-death']:Revive(src, src) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', 'Player revived.')
        return
    end
    -- Already up: heal through medical when it runs.
    if GetResourceState('qbx_medical') == 'started' then exports.qbx_medical:Revive(src)
    else TriggerClientEvent('cortex-admin:client:revivePed', src) end
    TriggerClientEvent('cortex-admin:client:notify', src, 'success', 'Player revived.')
end)

RegisterNetEvent('cortex-admin:server:sitInVehicle', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.sitInVehicle') then return end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    local requestId = data.requestId
    if not target or not GetPlayerName(target) then
        playerResult(src, requestId, false, 'That player is no longer online.')
        return
    end
    local name = GetPlayerName(target)
    if target == src then playerResult(src, requestId, false, 'Choose another player.'); return end

    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then
        playerResult(src, requestId, false, ('%s is in routing bucket %d and you are in %d.'):format(
            name, GetPlayerRoutingBucket(target), GetPlayerRoutingBucket(src)))
        return
    end

    local targetPed = GetPlayerPed(target)
    if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) or GetEntityType(targetPed) ~= 1 then
        playerResult(src, requestId, false, ('%s has no position yet.'):format(name))
        return
    end
    local veh = GetVehiclePedIsIn(targetPed, false)
    if veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then
        playerResult(src, requestId, false, ('%s is not in a vehicle.'):format(name))
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    local coords = sanitizeCoords(GetEntityCoords(veh))
    if not toInteger(netId, 1, 65535) or not coords then
        playerResult(src, requestId, false, ('%s\'s vehicle is not networked.'):format(name))
        return
    end
    -- The coordinates let the admin's client move close enough for the vehicle to stream in.
    TriggerClientEvent('cortex-admin:client:sitInVehicle', src, netId, coords, requestId, name)
end)

RegisterNetEvent('cortex-admin:server:setJob', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.setJob') then return end
    if not Config.HasQBX then return end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    local jobName = trimString(data.job, 64)
    local jobGrade = toInteger(data.grade, 0, 99)
    if not target or not jobName or jobGrade == nil then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        return player.Functions.SetJob(jobName, jobGrade)
    end)
    -- Qbox returns false when it rejects the change (unknown job, gang or account).
    if ok and err == false then ok, err = false, 'Qbox rejected the change.' end

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Set %s job to %s (grade %d)', GetPlayerName(target), jobName, jobGrade))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:setGang', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.setGang') then return end
    if not Config.HasQBX then return end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    local gangName = trimString(data.gang, 64)
    local gangGrade = toInteger(data.grade, 0, 99)
    if not target or not gangName or gangGrade == nil then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        return player.Functions.SetGang(gangName, gangGrade)
    end)
    -- Qbox returns false when it rejects the change (unknown job, gang or account).
    if ok and err == false then ok, err = false, 'Qbox rejected the change.' end

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Set %s gang to %s (grade %d)', GetPlayerName(target), gangName, gangGrade))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:setMoney', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not Config.HasQBX then return end

    local actionId = trimString(data.actionId, 64)
    local moneyType = actionId and moneyActions[actionId]
    if not moneyType or not hasPermission(src, actionId) then return end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    local amount = toInteger(data.amount, 0, 1000000000)
    if not target or amount == nil then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        return player.Functions.SetMoney(moneyType, amount, 'admin-set')
    end)
    -- Qbox returns false when it rejects the change (unknown job, gang or account).
    if ok and err == false then ok, err = false, 'Qbox rejected the change.' end

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Set %s %s to $%s', GetPlayerName(target), moneyType, tostring(amount)))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:giveMoney', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.giveMoney') then return end
    if not Config.HasQBX then return end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    local moneyType = trimString(data.moneyType, 32)
    local amount = toInteger(data.amount, 1, 1000000000)
    if not target or not moneyType or not allowedMoneyTypes[moneyType] or not amount or amount <= 0 then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        return player.Functions.AddMoney(moneyType, amount, 'admin-give')
    end)
    -- Qbox returns false when it rejects the change (unknown job, gang or account).
    if ok and err == false then ok, err = false, 'Qbox rejected the change.' end

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Gave $%s %s to %s', tostring(amount), moneyType, GetPlayerName(target)))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:setMetadata', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not Config.HasQBX then return end

    local actionId = trimString(data.actionId, 64)
    local key = actionId and metadataActions[actionId]
    if not key or not hasPermission(src, actionId) then return end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    local value = toInteger(data.value, 0, 100)

    if actionId == 'dev.setStress' and target ~= src then return end

    if not target or value == nil then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.SetMetaData(key, value)
    end)

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Set %s %s to %s', GetPlayerName(target), key, tostring(value)))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:openInventory', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.openInventory') then return end
    if not Config.HasOxInventory then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'No inventory system detected')
        return
    end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local ok, err = pcall(function()
        exports.ox_inventory:forceOpenInventory(src, 'player', target)
    end)

    if not ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed to open inventory: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:setRoutingBucket', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.setRoutingBucket') then return end

    local target = toInteger(data.target, 1)
    if target and target ~= src and not targetSessionMatches(target, data.targetSession) then
        playerResult(src, data.requestId, false, 'The selected player changed. Refresh the player list and select them again.')
        return
    end
    local bucket = toInteger(data.bucket, 0, 65535)
    if not target or bucket == nil or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    SetPlayerRoutingBucket(target, bucket)
    TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Set %s routing bucket to %d', GetPlayerName(target), bucket))
end)

RegisterNetEvent('cortex-admin:server:adminCar', function()
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if not hasPermission(src, 'vehicle.adminCar') then return end
    if not Config.HasQBX or not Config.HasQBXVehicles then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'QBX vehicles not available')
        return
    end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    local vehicle = GetVehiclePedIsIn(GetPlayerPed(src), false)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Enter the vehicle you want to save first.')
        return
    end
    pendingAdminCarRequests[src] = { expiresAt = GetGameTimer() + ADMIN_CAR_REQUEST_MS,
        vehicle = vehicle, model = GetEntityModel(vehicle), plate = GetVehicleNumberPlateText(vehicle),
        session = playerSession(src), citizenid = citizenid }

    -- Request vehicle props from client
    TriggerClientEvent('cortex-admin:client:getVehicleProps', src)
end)

RegisterNetEvent('cortex-admin:server:adminCarSave', function(data)
    local src = source
    if not allowRequest(src, 'admin-car-save', 2, 10000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'vehicle.adminCar') then return end
    if not Config.HasQBX or not Config.HasQBXVehicles then return end

    local request = pendingAdminCarRequests[src]
    pendingAdminCarRequests[src] = nil
    if not request or GetGameTimer() > request.expiresAt or not targetSessionMatches(src, request.session) then return end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    local ped = GetPlayerPed(src)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'You must remain inside the vehicle being saved')
        return
    end

    local model = GetEntityModel(vehicle)
    if vehicle ~= request.vehicle or model ~= request.model or citizenid ~= request.citizenid
        or GetVehicleNumberPlateText(vehicle) ~= request.plate or toInteger(data.model) ~= model then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Vehicle changed before it could be saved')
        return
    end

    local props = sanitizeVehicleProps(data.props, model, GetVehicleNumberPlateText(vehicle))
    if not props then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'No vehicle data')
        return
    end

    if type(EsAdminServer.claimAdminVehicle) ~= 'function' then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Owned vehicle saving is unavailable.')
        return
    end
    local id, reason = EsAdminServer.claimAdminVehicle(src, vehicle, props)
    TriggerClientEvent('cortex-admin:client:notify', src, id and 'success' or 'error',
        id and 'This vehicle is now yours and remains out. Park it through your garage to store it.'
        or ('Vehicle was not saved: ' .. tostring(reason)))
end)

RegisterNetEvent('cortex-admin:server:pullStash', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'server.pullStash') then return end
    if not Config.HasOxInventory then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'No inventory system detected')
        return
    end

    local stashName = trimString(data.stash, 80)
    if not stashName then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Stash name required')
        return
    end

    local ok, err = pcall(function()
        exports.ox_inventory:forceOpenInventory(src, 'stash', stashName)
    end)

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', 'Opened stash: ' .. stashName)
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed to open stash: ' .. tostring(err))
    end
end)
