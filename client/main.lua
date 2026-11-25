local PlayerPedId = PlayerPedId
local PlayerId = PlayerId
local GetPlayerServerId = GetPlayerServerId
local GetPlayerName = GetPlayerName
local GetActivePlayers = GetActivePlayers
local GetEntityCoords = GetEntityCoords
local GetEntityHeading = GetEntityHeading
local IsEntityDead = IsEntityDead
local GetClockHours = GetClockHours
local GetClockMinutes = GetClockMinutes
local IsNextWeatherType = IsNextWeatherType
local GetDisplayNameFromVehicleModel = GetDisplayNameFromVehicleModel
local GetLabelText = GetLabelText
local GetCurrentResourceName = GetCurrentResourceName
local SetEntityCoordsNoOffset = SetEntityCoordsNoOffset
local SendNUIMessage = SendNUIMessage
local SetNuiFocus = SetNuiFocus
local SetNuiFocusKeepInput = SetNuiFocusKeepInput
local DisableAllControlActions = DisableAllControlActions
local EnableControlAction = EnableControlAction
local HudWeaponWheelIgnoreSelection = HudWeaponWheelIgnoreSelection
local BlockWeaponWheelThisFrame = BlockWeaponWheelThisFrame
local HideHudAndRadarThisFrame = HideHudAndRadarThisFrame
local SetPauseMenuActive = SetPauseMenuActive
local InvalidateIdleCam = InvalidateIdleCam
local InvalidateVehicleIdleCam = InvalidateVehicleIdleCam
local FreezeEntityPosition = FreezeEntityPosition
local GetVehiclePedIsIn = GetVehiclePedIsIn
local TaskLeaveVehicle = TaskLeaveVehicle
local SetEntityAsMissionEntity = SetEntityAsMissionEntity
local DeleteEntity = DeleteEntity
local DoesEntityExist = DoesEntityExist
local GetGamePool = GetGamePool
local GetGameTimer = GetGameTimer
local Wait = Wait
local CreateThread = CreateThread
local RegisterCommand = RegisterCommand
local RegisterKeyMapping = RegisterKeyMapping
local RegisterNetEvent = RegisterNetEvent
local TriggerServerEvent = TriggerServerEvent
local GetResourceKvpString = GetResourceKvpString
local SetResourceKvp = SetResourceKvp
local GetResourceState = GetResourceState

-- Cached math/table functions
local pairs = pairs
local ipairs = ipairs
local type = type
local pcall = pcall
local tonumber = tonumber
local tableSort = table.sort
local tableConcat = table.concat
local tableInsert = table.insert

-- ============================================================================
-- MODULE STATE
-- ============================================================================

EsAdmin = EsAdmin or {}

local Actions = EsAdminActions
-- FiveM client Lua returns 1 or false for BOOL natives, so `== true` never matches.
local function nativeOn(value) return value == true or value == 1 end

local state = {
    open = false,
    favorites = {},
    settings = {},
    toggles = {},
    allowed = {},
    playerList = {},
    wardrobeShareRequests = {},
    lastCoords = nil,
    coordHudDirty = false,
    speedHudDirty = false,
}

local worldState = {
    freezeTime = false,
}
EsAdmin.worldState = worldState

local currentResourceName = GetCurrentResourceName()
local trackedWeatherTypes = {
    'EXTRASUNNY',
    'CLEAR',
    'CLOUDS',
    'SMOG',
    'FOGGY',
    'OVERCAST',
    'RAIN',
    'THUNDER',
    'CLEARING',
    'NEUTRAL',
    'SNOW',
    'BLIZZARD',
    'SNOWLIGHT',
    'XMAS',
    'HALLOWEEN',
}

local enabledControls = {
    71, 72, 59, 60, 76, 77, 79, 80, 63, 64, 75,
    -- Keep GTA's text-chat controls usable while the menu owns gameplay input.
    245, 246, 247, 248, 249,
    30, 31, 32, 33, 34, 35, 21, 22, 36
}
local enabledControlsCount = #enabledControls
local menuControlThreadActive = false
local menuFocusApplied = false
local menuIdleCamTick = 0
local menuTypingLock = false
local menuOpenGeneration = 0
local menuClosedAt = nil
local uiReady = false
local playerDirectoryReceived = false
local chatResourceName = 'cortex-chat'
local MENU_REOPEN_GUARD_MS = 250

EsAdmin.state = state

-- ============================================================================
-- UTILITY FUNCTIONS (Use cortex-lib where possible)
-- ============================================================================

local function notify(notifyType, message)
    if (EsAdmin.isCharacterStudioActive and EsAdmin.isCharacterStudioActive())
        or (EsAdmin.silentNotificationThreads and EsAdmin.silentNotificationThreads[coroutine.running()]) then
        return
    end
    -- Position, sound, and sound preset are player-owned cortex-lib settings.
    -- Omitting those fields lets cortex-lib resolve the current preferences.
    exports['cortex-lib']:notify({
        type = notifyType or 'info',
        description = tostring(message or '')
    })
end

EsAdmin.notify = notify

function EsAdmin.copyToClipboard(text)
    exports['cortex-lib']:copyToClipboard(text or '')
end

local function getCurrentWeather()
    for i = 1, #trackedWeatherTypes do
        local weatherType = trackedWeatherTypes[i]
        if IsNextWeatherType(weatherType) then
            return weatherType
        end
    end

    return worldState.weather or 'UNKNOWN'
end

local function getLiveWorldSnapshot()
    return {
        gameHour = GetClockHours(),
        gameMinute = GetClockMinutes(),
        currentWeather = getCurrentWeather(),
    }
end

-- Direct native KVP functions for reliability
local function loadKvp(key, fallback)
    local raw = GetResourceKvpString(key)
    if not raw or raw == '' then
        return fallback
    end
    
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then
        return decoded
    end
    
    return fallback
end

local function saveKvp(key, data)
    if not key or key == '' then
        print('[cortex-admin] ERROR: saveKvp called with empty key')
        return false
    end
    
    local ok, encoded = pcall(json.encode, data)
    if not ok then
        print('[cortex-admin] ERROR: Failed to encode settings for key: ' .. key)
        return false
    end
    
    local written = pcall(SetResourceKvp, key, encoded)
    if not written or GetResourceKvpString(key) ~= encoded then return false end
    return true
end

local MP_PED_KEY_PREFIX = 'mp_ped_'
local MP_PED_SOURCE_ES_ADMIN = 'cortex-admin'
local MP_PED_SOURCE_VMENU = 'vmenu'
local LAST_PED_NAME_KEY = 'cortex-admin_last_ped'
local LAST_PED_SOURCE_KEY = 'cortex-admin_last_ped_source'
local LAST_PED_SOURCE_REF_KEY = 'cortex-admin_last_ped_source_key'
local DEFAULT_PED_SOURCE_KEY = 'cortex-admin_default_ped_source'
local DEFAULT_PED_SOURCE_REF_KEY = 'cortex-admin_default_ped_source_key'

local function cloneJsonTable(data)
    if type(data) ~= 'table' then
        return nil
    end

    local ok, encoded = pcall(json.encode, data)
    if not ok or type(encoded) ~= 'string' or encoded == '' then
        return nil
    end

    ok, data = pcall(json.decode, encoded)
    if ok and type(data) == 'table' then
        return data
    end

    return nil
end

local function normalizeSavedPedKey(keyOrName)
    if type(keyOrName) ~= 'string' or keyOrName == '' then
        return nil, nil
    end

    if keyOrName:sub(1, #MP_PED_KEY_PREFIX) == MP_PED_KEY_PREFIX then
        return keyOrName, keyOrName:sub(#MP_PED_KEY_PREFIX + 1)
    end

    return MP_PED_KEY_PREFIX .. keyOrName, keyOrName
end

local function normalizeMpPedData(data, sourceKey)
    if type(EsAdmin.normalizeMpPedData) == 'function' then
        local normalized = EsAdmin.normalizeMpPedData(data, sourceKey)
        if type(normalized) == 'table' then
            return normalized
        end
    end

    local normalized = cloneJsonTable(data) or {}
    if normalized.PedTatttoos and not normalized.PedTattoos then
        normalized.PedTattoos = normalized.PedTatttoos
    elseif normalized.PedTattoos and not normalized.PedTatttoos then
        normalized.PedTatttoos = normalized.PedTattoos
    end

    if type(sourceKey) == 'string' and sourceKey ~= '' then
        normalized.SaveName = sourceKey
    end

    return normalized
end

-- A resource named vMenu is either vMenu itself or Cortex's stand-in
-- (compat/vMenu), which keeps players' vMenu keys and data after vMenu is removed.
-- missing | stopped | running (vMenu itself) | compat (the stand-in)
EsAdmin.vmenuState = function()
    local resourceState = GetResourceState('vMenu')
    if resourceState == 'missing' or resourceState == 'unknown' then return 'missing' end
    if GetResourceMetadata('vMenu', 'cortex_vmenu_compat', 0) == 'yes' then return 'compat' end
    return resourceState == 'started' and 'running' or 'stopped'
end
EsAdmin.isVmenuRunning = function() return EsAdmin.vmenuState() == 'running' end

local function callVmenuBridge(method, ...)
    if not EsAdmin.isVmenuRunning() then
        return false, 'vMenu is not running'
    end

    local okBridge, bridge = pcall(function()
        return exports['vMenu']
    end)
    if not okBridge or not bridge then
        return false, 'vMenu bridge unavailable'
    end

    local okExport, exportFn = pcall(function()
        return bridge[method]
    end)
    if not okExport then
        return false, exportFn
    end

    if type(exportFn) ~= 'function' then
        return false, ('vMenu bridge export missing: %s'):format(method)
    end

    local ok, result = pcall(exportFn, ...)
    if not ok then
        return false, result
    end

    return true, result
end

local function getVmenuSavedPedByKey(sourceKey)
    local ok, rawPeds = callVmenuBridge('GetSavedMpCharactersForEsAdmin')
    if not ok or type(rawPeds) ~= 'table' then
        return nil
    end

    for i = 1, #rawPeds do
        local item = rawPeds[i]
        if item and item.key == sourceKey and type(item.data) == 'table' then
            return normalizeMpPedData(item.data, sourceKey)
        end
    end

    return nil
end

local function applyDefaultSettings(settings)
    -- Merge defaults with saved settings
    local merged = {}
    for key, value in pairs(Config.DefaultSettings) do
        merged[key] = value
    end
    if settings then
        for key, value in pairs(settings) do
            merged[key] = value
        end
    end
    return merged
end

-- ============================================================================
-- PLAYER LIST (Optimized with indexed loops)
-- ============================================================================

local function refreshPlayerList()
    local players = {}
    local activePlayers = GetActivePlayers()
    local myPlayerId = PlayerId()
    local count = 0
    
    for i = 1, #activePlayers do
        local player = activePlayers[i]
        local serverId = GetPlayerServerId(player)
        local name = GetPlayerName(player) or ('Player %s'):format(serverId)
        count = count + 1
        players[count] = {
            id = serverId,
            name = name,
            isSelf = player == myPlayerId,
        }
    end

    tableSort(players, function(a, b)
        return a.id < b.id
    end)

    state.playerList = players
end

-- ============================================================================
-- CACHED DATA (Avoid rebuilding every update)
-- ============================================================================

local cachedData = {
    personalVehicles = nil,
    addonVehicles = {},
    scannedAddonVehicles = {},
    importedAddonVehicles = {},
    playerName = nil,
    actions = nil,
    tabs = nil,
    frameworkInfo = nil,
}

local runtimeUiCache = {
    gameHour = nil,
    gameMinute = nil,
    currentWeather = nil,
    playerListSignature = nil,
}

local menuDataCache = {
    permissionsRequestedAt = 0,
    addonVehiclesRequestedAt = 0,
    addonVehiclesLoaded = false,
}

local PERMISSIONS_REFRESH_MS = 20000
local ADDON_VEHICLES_REFRESH_MS = 300000

local function buildPersonalVehiclesSummary(vehicles)
    local summary = {}
    for i = 1, #vehicles do
        local entry = vehicles[i]
        summary[#summary + 1] = {
            id = entry.id,
            name = entry.name,
            model = entry.model,
            modelLabel = entry.modelLabel,
            category = entry.category,
            vmenuCategory = entry.vmenuCategory,
        }
    end

    tableSort(summary, function(a, b)
        local catA = (a.category or ''):lower()
        local catB = (b.category or ''):lower()
        if catA ~= catB then
            return catA < catB
        end
        local nameA = (a.name or ''):lower()
        local nameB = (b.name or ''):lower()
        return nameA < nameB
    end)

    return summary
end

local function buildPlayerListSignature(players)
    if type(players) ~= 'table' or #players == 0 then
        return ''
    end

    local signature = {}

    for i = 1, #players do
        local player = players[i]
        signature[i] = ('%s:%d:%s:%s:%s:%s:%s'):format(
            tostring(player.id or ''),
            #tostring(player.name or ''),
            tostring(player.name or ''),
            player.isSelf and '1' or '0',
            tostring(player.ping or 0),
            tostring(player.bucket or 0),
            player.dead and '1' or '0'
        )
    end

    return tableConcat(signature, '|')
end

local function trimString(value)
    if type(value) ~= 'string' then
        return ''
    end
    return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function prettifyModelName(model)
    local normalized = trimString(model):gsub('_', ' ')
    return normalized:gsub('(%a)([%w]*)', function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

local function resolveLabelText(labelKey)
    local key = trimString(labelKey)
    if key == '' then
        return nil
    end

    local text = GetLabelText(key)
    if text and text ~= '' and text ~= 'NULL' then
        return text
    end

    return nil
end

local function resolveAddonVehicleName(model, gameName, fallbackName)
    local gameLabel = resolveLabelText(gameName)
    if gameLabel then
        return gameLabel
    end

    local normalizedModel = trimString(model):lower()
    if normalizedModel ~= '' then
        local displayKey = trimString(GetDisplayNameFromVehicleModel(joaat(normalizedModel)))
        if displayKey ~= '' and displayKey ~= 'NULL' and displayKey ~= 'CARNOTFOUND' then
            local displayLabel = resolveLabelText(displayKey)
            if displayLabel then
                return displayLabel
            end
        end
    end

    local fallback = trimString(fallbackName)
    if fallback ~= '' and fallback ~= trimString(gameName) then
        return fallback
    end

    return prettifyModelName(normalizedModel)
end

local function normalizeAddonVehicles(list)
    if type(list) ~= 'table' then
        return {}
    end

    local normalized = {}
    local seenModels = {}
    for i = 1, #list do
        local entry = list[i]
        if type(entry) == 'string' then
            entry = {
                model = entry,
                name = prettifyModelName(entry),
                sourceType = 'vmenu-config',
            }
        end
        if type(entry) == 'table' then
            local model = trimString(entry.model):lower()
            if model ~= '' and not seenModels[model] then
                seenModels[model] = true

                local gameName = trimString(entry.gameName)
                local makeName = trimString(entry.makeName)

                normalized[#normalized + 1] = {
                    model = model,
                    name = resolveAddonVehicleName(model, gameName, entry.name),
                    gameName = gameName ~= '' and gameName or nil,
                    makeName = makeName ~= '' and makeName or nil,
                    resource = entry.resource,
                    metaPath = entry.metaPath,
                    sourceType = entry.sourceType,
                    ownerResource = entry.ownerResource,
                    dataResource = entry.dataResource,
                }
            end
        end
    end

    tableSort(normalized, function(a, b)
        local nameA = (a.name or a.model or ''):lower()
        local nameB = (b.name or b.model or ''):lower()
        if nameA ~= nameB then
            return nameA < nameB
        end
        return (a.model or ''):lower() < (b.model or ''):lower()
    end)

    return normalized
end

local function mergeAddonVehicles(scanned, imported)
    local combined = {}
    local seen = {}
    for _, list in ipairs({ scanned, imported }) do
        for index = 1, #(type(list) == 'table' and list or {}) do
            local entry = list[index]
            local model = type(entry) == 'table' and trimString(entry.model):lower() or ''
            if model ~= '' and not seen[model] then
                seen[model] = true
                combined[#combined + 1] = entry
            end
        end
    end
    tableSort(combined, function(a, b)
        local first = (a.name or a.model or ''):lower()
        local second = (b.name or b.model or ''):lower()
        if first ~= second then return first < second end
        return (a.model or '') < (b.model or '')
    end)
    return combined
end

EsAdmin.setImportedAddonVehicles = function(vehicles)
    cachedData.importedAddonVehicles = normalizeAddonVehicles(vehicles)
    cachedData.addonVehicles = mergeAddonVehicles(cachedData.scannedAddonVehicles, cachedData.importedAddonVehicles)
    if state.open then
        SendNUIMessage({ action = 'cortex-admin:setState', data = { addonVehicles = cachedData.addonVehicles } })
    end
end

EsAdmin.getAddonVehicles = function() return cachedData.addonVehicles or {} end

local function refreshPersonalVehiclesCache()
    local loader = EsAdmin.loadPersonalVehicles
    if type(loader) == 'function' then
        local merged = loader()
        if merged and type(merged) == 'table' and type(merged.vehicles) == 'table' then
            cachedData.personalVehicles = buildPersonalVehiclesSummary(merged.vehicles)
            return
        end
    end

    local data = loadKvp('cortex-admin_personal_vehicles_v2', nil)
    if data and type(data) == 'table' and data.version == 2 and type(data.vehicles) == 'table' then
        cachedData.personalVehicles = buildPersonalVehiclesSummary(data.vehicles)
        return
    end

    local legacy = loadKvp('cortex-admin_personal_vehicles', {}) or {}
    local summary = {}
    for name, props in pairs(legacy) do
        if type(props) == 'table' then
            summary[#summary + 1] = {
                id = tostring(name),
                name = name,
                model = props.model,
                modelLabel = props.modelLabel,
                category = props.category or 'other',
            }
        end
    end

    cachedData.personalVehicles = buildPersonalVehiclesSummary(summary)
end

EsAdmin.refreshPersonalVehiclesCache = refreshPersonalVehiclesCache

EsAdmin.getPersonalVehiclesCache = function()
    return cachedData.personalVehicles
end

-- ============================================================================
-- UI STATE BUILDING (Optimized)
-- ============================================================================

local function buildUiState(includeStatic)
    includeStatic = includeStatic ~= false

    -- Cache player name (rarely changes)
    if not cachedData.playerName then
        cachedData.playerName = GetPlayerName(PlayerId()) or 'Admin'
    end
    
    -- Cache actions/tabs (static)
    if not cachedData.actions then
        cachedData.actions = Actions.actions
        cachedData.tabs = Actions.tabs
    end
    cachedData.frameworkInfo = EsAdminBridge.getFrameworkInfo()
    
    -- Cache personal vehicles (only refresh on demand)
    if not cachedData.personalVehicles then
        refreshPersonalVehiclesCache()
    end

    local pvModel = EsAdmin.getPreviewVehicleModel and EsAdmin.getPreviewVehicleModel() or nil
    local pvShared = EsAdmin.getPreviewShared and EsAdmin.getPreviewShared() == true

    local data = {
        open = state.open,
        menuGameControl = state.menuGameControl == true,
        menuControlKey = state.menuControlKey or Config.MenuControlKey or 'F4',
        favorites = state.favorites,
        settings = state.settings,
        toggles = state.toggles,
        allowed = state.allowed,
        players = state.playerList,
        wardrobeShareRequests = state.wardrobeShareRequests,
        playerName = cachedData.playerName,
        gameHour = GetClockHours(),
        gameMinute = GetClockMinutes(),
        currentWeather = getCurrentWeather(),
        personalVehicles = cachedData.personalVehicles,
        addonVehicles = cachedData.addonVehicles or {},
        voiceState = EsAdmin.getVoiceState and EsAdmin.getVoiceState() or nil,
        weaponTintCount = GetWeaponTintCount and GetWeaponTintCount(GetSelectedPedWeapon(PlayerPedId())) or 8,
        vehiclePreview = {
            active = type(pvModel) == 'string' and pvModel ~= '',
            model = pvModel,
            shared = pvShared,
        },
    }

    if includeStatic then
        data.actions = cachedData.actions
        data.tabs = cachedData.tabs
        data.frameworkInfo = cachedData.frameworkInfo
    end

    return data
end

-- Catalog builders replace their tables when data changes. Keep the last sent
-- references so a warm open does not serialize/decode these lists again.
local sentUiCatalogs = {}
local function sendUiState(includeStatic)
    local data = buildUiState(includeStatic)
    for _, key in ipairs({ 'personalVehicles', 'addonVehicles' }) do
        local value = data[key]
        if includeStatic == false and sentUiCatalogs[key] == value then
            data[key] = nil
        else
            sentUiCatalogs[key] = value
        end
    end
    local playerSignature = buildPlayerListSignature(state.playerList)
    if includeStatic == false and runtimeUiCache.playerListSignature == playerSignature then
        data.players = nil
    end
    runtimeUiCache.playerListSignature = playerSignature
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = data
    })
    if state.toggles['dev.showSpeed'] == true then
        SendNUIMessage({
            action = 'cortex-admin:setSpeedHud',
            data = {
                visible = true,
                position = state.settings.speedHudPosition or 'top-left',
                units = state.settings.speedHudUnits or 'mph',
            }
        })
    end
end

local function sendRuntimeUiState(includePlayers, force)
    local snapshot = getLiveWorldSnapshot()
    local data = {}
    local changed = force == true

    if force or runtimeUiCache.gameHour ~= snapshot.gameHour then
        runtimeUiCache.gameHour = snapshot.gameHour
        data.gameHour = snapshot.gameHour
        changed = true
    end

    if force or runtimeUiCache.gameMinute ~= snapshot.gameMinute then
        runtimeUiCache.gameMinute = snapshot.gameMinute
        data.gameMinute = snapshot.gameMinute
        changed = true
    end

    if force or runtimeUiCache.currentWeather ~= snapshot.currentWeather then
        runtimeUiCache.currentWeather = snapshot.currentWeather
        data.currentWeather = snapshot.currentWeather
        changed = true
    end

    if includePlayers then
        local signature = buildPlayerListSignature(state.playerList)
        if force or runtimeUiCache.playerListSignature ~= signature then
            runtimeUiCache.playerListSignature = signature
            data.players = state.playerList
            changed = true
        end
    end

    if not changed then
        return false
    end

    SendNUIMessage({
        action = 'cortex-admin:updateRuntimeState',
        data = data
    })

    return true
end

EsAdmin.sendUiState = sendUiState

EsAdmin.markUiReady = function()
    uiReady = true
    sendUiState(true)
end

-- ============================================================================
-- KEY MAPPINGS
-- ============================================================================

-- A registered mapping stays listed in FiveM's key settings for every player,
-- so a gated one registers once, at runtime, when it first becomes usable.
local keyMappings, registeredKeyMappings = {}, {}
local permissionsReceived = false
local permissionsExpiresAt = 0
local receivePermissions

local function refreshKeyMappings()
    for index = 1, #keyMappings do
        local mapping = keyMappings[index]
        if not registeredKeyMappings[mapping.command] and (not mapping.available or mapping.available()) then
            registeredKeyMappings[mapping.command] = true
            RegisterKeyMapping(mapping.command, mapping.description, 'keyboard', mapping.key)
        end
    end
end

EsAdmin.refreshKeyMappings = refreshKeyMappings
EsAdmin.addKeyMapping = function(command, description, key, available)
    keyMappings[#keyMappings + 1] = { command = command, description = description, key = key, available = available }
    refreshKeyMappings()
end
EsAdmin.isKeyMappingRegistered = function(command) return registeredKeyMappings[command] == true end
-- Only a current permission lease allows client menu access.
EsAdmin.hasMenuAccess = function() return permissionsReceived and GetGameTimer() < permissionsExpiresAt end

local function requestMenuPermissions(force)
    local now = GetGameTimer()
    if force or now - menuDataCache.permissionsRequestedAt > PERMISSIONS_REFRESH_MS then
        menuDataCache.permissionsRequestedAt = now
        TriggerServerEvent('cortex-admin:server:requestPermissions')
    end
end

local function requestAddonVehiclesIfNeeded(force)
    local now = GetGameTimer()
    local hasAddonVehicles = type(cachedData.addonVehicles) == 'table' and #cachedData.addonVehicles > 0
    if force or not menuDataCache.addonVehiclesLoaded or not hasAddonVehicles or now - menuDataCache.addonVehiclesRequestedAt > ADDON_VEHICLES_REFRESH_MS then
        menuDataCache.addonVehiclesRequestedAt = now
        TriggerServerEvent('cortex-admin:server:requestAddonVehicles')
        return true
    end
    return false
end

EsAdmin.requestAddonVehiclesIfNeeded = requestAddonVehiclesIfNeeded

-- ============================================================================
-- MENU OPEN/CLOSE
-- ============================================================================

local function isChatOpen()
    if GetResourceState(chatResourceName) ~= 'started' then
        return false
    end

    -- cortex-chat is optional; treat a missing/outdated export as closed so the
    -- admin menu keeps its normal focus behavior on servers without that chat.
    local ok, open = pcall(function()
        return exports[chatResourceName]:isOpen()
    end)

    return ok and open == true
end

-- Use our own reason so closing admin preserves other HUD visibility settings.
function EsAdmin.syncHudVisibility()
    if GetResourceState('cortex-hud') ~= 'started' then return false end
    local hidden = state.open or (EsAdmin.isPlayersOpen and EsAdmin.isPlayersOpen()) == true
    return pcall(function()
        exports['cortex-hud']:setHudVisibleReason(currentResourceName, not hidden)
    end)
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'cortex-hud' then EsAdmin.syncHudVisibility() end
end)

local function startMenuControlThread()
    if menuControlThreadActive then return end
    menuControlThreadActive = true

    CreateThread(function()
        local chatOpen = false
        local wasChatOpen = false
        local chatStateTick = 0

        while state.open do
            HideHudAndRadarThisFrame()
            if not state.menuGameControl then
                DisableAllControlActions(0)
                for i = 1, enabledControlsCount do
                    EnableControlAction(0, enabledControls[i], true)
                end
                HudWeaponWheelIgnoreSelection()
                BlockWeaponWheelThisFrame()
                SetPauseMenuActive(false)
            end

            local now = GetGameTimer()
            if now - chatStateTick >= 100 then
                chatOpen = isChatOpen()
                chatStateTick = now
            end

            if chatOpen then
                -- cortex-chat owns NUI focus while its input is open.
            elseif wasChatOpen and not state.menuGameControl then
                -- Chat just released focus; hand it back to the admin menu now.
                SetNuiFocus(true, true)
                SetNuiFocusKeepInput(not menuTypingLock)
                menuFocusApplied = true
            end

            wasChatOpen = chatOpen

            if now - menuIdleCamTick >= 1000 then
                InvalidateIdleCam()
                InvalidateVehicleIdleCam()
                menuIdleCamTick = now
            end

            Wait(0)
        end

        menuControlThreadActive = false
    end)
end

local function applyMenuFocus()
    if menuFocusApplied or state.menuGameControl then return end
    if isChatOpen() then return end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(not menuTypingLock)
    menuFocusApplied = true
end

local function clearMenuFocus()
    if not menuFocusApplied then return end
    menuTypingLock = false
    if not isChatOpen() then
        SetNuiFocusKeepInput(false)
        SetNuiFocus(false, false)
    end
    menuFocusApplied = false
end

function EsAdmin.setTypingLock(enabled)
    if not state.open or state.menuGameControl then return end
    local shouldLock = enabled == true
    if menuTypingLock == shouldLock then
        return
    end

    menuTypingLock = shouldLock

    if state.open then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(not menuTypingLock)
    end
end

-- Keep the Panel visible while handing keyboard, mouse and controller to GTA.
function EsAdmin.setMenuGameControl(enabled)
    if type(enabled) ~= 'boolean' then return false, 'invalid_mode' end
    if not state.open then return false, 'menu_closed' end
    if isChatOpen() then return false, 'chat_open' end
    if enabled and ((EsAdmin.isCharacterStudioActive and EsAdmin.isCharacterStudioActive())
        or (EsAdmin.isVehicleStudioActive and EsAdmin.isVehicleStudioActive())) then
        return false, 'studio_active'
    end
    if state.menuGameControl and IsNuiFocused() then return false, 'another_ui_open' end
    if (state.menuGameControl == true) == enabled then return true end
    menuTypingLock = false
    state.menuGameControl = enabled
    SetNuiFocus(not enabled, not enabled)
    SetNuiFocusKeepInput(not enabled)
    menuFocusApplied = not enabled
    SendNUIMessage({ action = 'cortex-admin:setState', data = { menuGameControl = enabled } })
    return true
end

local function menuControlKeyLabel()
    local ok, label = pcall(GetControlInstructionalButton, 0, joaat('cortex_admin_game_control') | 0x80000000, true)
    if ok and type(label) == 'string' then
        if label:sub(1, 2) == 't_' then return label:sub(3, 18) end
        local code = tonumber(label:match('^b_(%d+)$'))
        if code and code >= 170 and code <= 193 then return 'F' .. (code - 169) end
    end
    return Config.MenuControlKey or 'F4'
end

RegisterCommand('cortex_admin_game_control', function()
    if not state.open or menuTypingLock or IsPauseMenuActive() then return end
    local ok, reason = EsAdmin.setMenuGameControl(not state.menuGameControl)
    if not ok and reason == 'studio_active' then notify('info', 'Close the studio before switching to game controls.') end
end, false)
EsAdmin.addKeyMapping('cortex_admin_game_control', 'Cortex Admin: switch menu/game controls', Config.MenuControlKey or 'F4', EsAdmin.hasMenuAccess)

local function startMenuHydration(openGeneration)
    CreateThread(function()
        -- Publish open/focus first. This yield keeps player-list/state work out of
        -- the command callback and gives the NUI an immediate visible transition.
        Wait(0)

        if not state.open or menuOpenGeneration ~= openGeneration then
            return
        end

        -- Keep the authoritative directory on reopen instead of replacing it
        -- with a scoped local list and then rendering the server list again.
        if not playerDirectoryReceived then refreshPlayerList() end
        TriggerServerEvent('cortex-admin:server:requestPlayerDirectory')
        if uiReady then
            sendUiState(false)
        else
            -- If open raced the NUI ready callback, retain a full-state fallback.
            sendUiState(true)
        end
        requestMenuPermissions(false)
        requestAddonVehiclesIfNeeded(false)

        local m = EsAdmin.getPreviewVehicleModel and EsAdmin.getPreviewVehicleModel() or nil
        if type(m) == 'string' and m ~= '' and state.open and menuOpenGeneration == openGeneration then
            SendNUIMessage({
                action = 'cortex-admin:vehiclePreviewResume',
                data = {
                    model = m,
                    shared = EsAdmin.getPreviewShared and EsAdmin.getPreviewShared() == true,
                    resumeOnly = true,
                }
            })
        end

        if menuOpenGeneration == openGeneration then
            menuHydrationPending = false
        end
    end)
end

local function setOpen(open)
    if state.open == open then return end
    menuOpenGeneration = menuOpenGeneration + 1
    local openGeneration = menuOpenGeneration
    state.open = open
    state.menuGameControl = false
    EsAdmin.syncHudVisibility()
    TriggerServerEvent('cortex-admin:server:setUiPresence', { open = open == true })

    if open then
        if EsAdmin.closeClassicMenu then EsAdmin.closeClassicMenu() end
        if EsAdmin.closeVmenuMode then EsAdmin.closeVmenuMode() end
        if EsAdmin.closeVehicleCamera then EsAdmin.closeVehicleCamera() end
        if EsAdmin.closeShowcaseCamera then EsAdmin.closeShowcaseCamera() end
        state.menuControlKey = menuControlKeyLabel()
        menuTypingLock = false
        applyMenuFocus()
        menuIdleCamTick = 0
        SendNUIMessage({ action = 'cortex-admin:open' })
        startMenuControlThread()
        startMenuHydration(openGeneration)
    else
        menuClosedAt = GetGameTimer()
        menuTypingLock = false
        if EsAdmin.closeCharacterStudio then EsAdmin.closeCharacterStudio() end
        if EsAdmin.closeVehicleStudio then EsAdmin.closeVehicleStudio() end
        SendNUIMessage({ action = 'cortex-admin:close' })
        clearMenuFocus()
    end
end

EsAdmin.setOpen = setOpen

local function openVehiclePreviewPage(model)
    if not state.open then
        setOpen(true)
    end
    requestAddonVehiclesIfNeeded(false)

    SendNUIMessage({
        action = 'cortex-admin:vehiclePreviewPage',
        data = {
            model = type(model) == 'string' and model ~= '' and model or nil,
        }
    })
end

EsAdmin.openVehiclePreviewPage = openVehiclePreviewPage

local menuOpenedAt
local function toggleMenu()
    -- Two mappings on one key (a keyboard and a controller binding, or the
    -- vMenu stand-in's) fire in the same frame; the second must not close it.
    if menuOpenedAt and GetGameTimer() - menuOpenedAt < 100 then return end
    if EsAdmin.isClassicMenuOpen and EsAdmin.isClassicMenuOpen() then
        menuClosedAt = GetGameTimer()
        EsAdmin.closeClassicMenu()
        return
    end
    if EsAdmin.isVmenuModeOpen and EsAdmin.isVmenuModeOpen() then
        menuClosedAt = GetGameTimer()
        EsAdmin.closeVmenuMode()
        return
    end
    if state.open then
        setOpen(false)
        return
    end

    -- Mouse bindings can replay as NUI focus is released. Only guard reopening:
    -- close must always win, including a quick second press after opening.
    if menuClosedAt then
        local elapsedSinceClose = GetGameTimer() - menuClosedAt
        if elapsedSinceClose >= 0 and elapsedSinceClose < MENU_REOPEN_GUARD_MS then
            return
        end
    end
    menuOpenedAt = GetGameTimer()
    if state.settings.interfaceStyle == 'classic' and EsAdmin.openClassicMenu then
        EsAdmin.openClassicMenu()
        return
    end
    if state.settings.interfaceStyle == 'vmenu' and EsAdmin.openVmenuMode then
        EsAdmin.openVmenuMode()
        return
    end
    setOpen(true)
end

EsAdmin.toggleMenu = toggleMenu

RegisterCommand(Config.Command, function()
    toggleMenu()
end, false)

EsAdmin.addKeyMapping(Config.Command, 'Cortex Admin: open menu', Config.Keybind, EsAdmin.hasMenuAccess)

-- Keep the existing command/key mapping stable for saved player bindings.
if Config.Command ~= 'cortexadmin' then
    RegisterCommand('cortexadmin', toggleMenu, false)
end

local function registerMenuSuggestions()
    TriggerEvent('chat:addSuggestion', '/cortexadmin', 'Open the Cortex admin menu', {})
    if Config.Command ~= 'cortexadmin' then
        TriggerEvent('chat:addSuggestion', '/' .. Config.Command, 'Open the Cortex admin menu', {})
    end
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() or resourceName == 'cortex-chat' or resourceName == 'chat' then
        registerMenuSuggestions()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    TriggerEvent('chat:removeSuggestion', '/cortexadmin')
    if Config.Command ~= 'cortexadmin' then
        TriggerEvent('chat:removeSuggestion', '/' .. Config.Command)
    end
end)

local COMMAND_PERMISSION_WAIT_MS = 750

local function hasCommandPermission(actionId, label)
    if permissionsReceived and GetGameTimer() >= permissionsExpiresAt then
        receivePermissions({}, nil, { menuAllowed = false })
    end
    if state.allowed[actionId] == true then
        return true
    end

    if state.allowed[actionId] == nil then
        requestMenuPermissions(true)
        local deadline = GetGameTimer() + COMMAND_PERMISSION_WAIT_MS
        while state.allowed[actionId] == nil and GetGameTimer() < deadline do
            Wait(25)
        end

        if state.allowed[actionId] == true then
            return true
        end
    end

    notify('error', ('No permission for %s.'):format(label or actionId))
    return false
end

local function runCommandAction(actionId, data, label)
    if not hasCommandPermission(actionId, label) then
        return
    end

    if EsAdmin.executeAction then
        EsAdmin.executeAction(actionId, data or {})
    end
end

local function runCommandToggle(actionId, label)
    if not hasCommandPermission(actionId, label) then
        return
    end

    if EsAdmin.toggleAction then
        EsAdmin.toggleAction(actionId, not EsAdmin.state.toggles[actionId])
    end
end

local function runCommandSelect(actionId, value, label)
    if not hasCommandPermission(actionId, label) then
        return
    end

    if EsAdmin.selectAction then
        EsAdmin.selectAction(actionId, value)
    end
end

-- ============================================================================
-- TELEPORT COMMAND (Smart parsing)
-- ============================================================================

RegisterCommand('tp', function(_, args)
    if not hasCommandPermission('teleport.coords', 'teleport') then
        return
    end

    if #args == 0 then
        notify('error', 'Usage: /tp X Y [Z] or /tp X=-513.2, Y=-1943.2')
        return
    end

    -- Join all args into one string for parsing
    local input = tableConcat(args, ' ')
    
    -- Remove common prefixes/wrappers
    input = input:gsub('vector3', ''):gsub('vector4', '')
    input = input:gsub('[%(%)%[%]]', '')  -- Remove brackets
    
    local coords = { x = nil, y = nil, z = nil }
    
    -- Try to parse labeled format: X=-513.2, Y=-1943.2, Z=30
    local labeledX = input:match('[Xx]%s*[=:]%s*([%-]?[%d%.]+)')
    local labeledY = input:match('[Yy]%s*[=:]%s*([%-]?[%d%.]+)')
    local labeledZ = input:match('[Zz]%s*[=:]%s*([%-]?[%d%.]+)')
    
    if labeledX and labeledY then
        coords.x = tonumber(labeledX)
        coords.y = tonumber(labeledY)
        coords.z = labeledZ and tonumber(labeledZ) or nil
    else
        -- Try to parse unlabeled format: extract all numbers
        local numbers = {}
        local count = 0
        for num in input:gmatch('[%-]?[%d]+%.?[%d]*') do
            local n = tonumber(num)
            if n then
                count = count + 1
                numbers[count] = n
            end
        end
        
        if count >= 2 then
            coords.x = numbers[1]
            coords.y = numbers[2]
            coords.z = numbers[3] -- May be nil
        end
    end
    
    -- Validate coordinates
    if not coords.x or not coords.y then
        notify('error', 'Could not parse coordinates. Try: /tp -513.2 -1943.2')
        return
    end
    
    -- Save last coords for teleport back
    local ped = PlayerPedId()
    state.lastCoords = GetEntityCoords(ped)
    
    -- If Z is provided, teleport directly
    if coords.z then
        SetEntityCoordsNoOffset(ped, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, false, false, false)
        notify('success', ('Teleported to %.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z))
    else
        -- Use smart teleport to find ground
        exports['cortex-admin']:teleportToCoords(coords.x, coords.y, true)
    end
end, false)

RegisterCommand('tpm', function()
    runCommandAction('teleport.waypoint', nil, 'waypoint teleport')
end, false)

RegisterCommand('tpmarker', function()
    runCommandAction('teleport.marker', nil, 'marker teleport')
end, false)

RegisterCommand('tpback', function()
    runCommandAction('teleport.back', nil, 'teleport back')
end, false)

-- /parachute [0-13] — give parachute + canopy tint (matches Weapons → Parachute menu)
RegisterCommand('parachute', function(_, args)
    local tint = 0
    if args and args[1] then
        tint = tonumber(args[1]) or 0
    end
    runCommandSelect('weapons.parachute', tint, 'parachute')
end, false)

-- ============================================================================
-- OTHER COMMANDS
-- ============================================================================

-- Noclip command. Cortex's key and the vMenu stand-in's can both sit on F2 if
-- the stand-in starts late; one press must toggle once.
local noclipKeyAt = -1000
EsAdmin.claimNoclipPress = function()
    local now = GetGameTimer()
    if now - noclipKeyAt < 150 then return false end
    noclipKeyAt = now
    return true
end
RegisterCommand('noclip', function()
    if not EsAdmin.claimNoclipPress() then return end
    runCommandToggle('player.noclip', 'noclip')
end, false)

-- vMenu (or its stand-in, which keeps players' own vMenu keys) owns the noclip
-- key when present; a second mapping on the same key would toggle twice.
EsAdmin.addKeyMapping('noclip', 'Cortex Admin: toggle noclip', EsAdminVmenuPolicy and EsAdminVmenuPolicy.get('vmenu_noclip_toggle_key', 'F2') or 'F2', function()
    local vmenu = EsAdmin.vmenuState()
    return state.allowed['player.noclip'] == true and vmenu ~= 'running' and vmenu ~= 'compat'
end)

RegisterCommand('god', function()
    runCommandToggle('player.godmode', 'god mode')
end, false)

RegisterCommand('vanish', function()
    runCommandToggle('player.invisible', 'invisibility')
end, false)

-- Gear Up in one press: /gearup, or a key the player binds under Settings >
-- Key Bindings > FiveM (unbound by default, so it never steals a key).
RegisterCommand('gearup', function()
    if state.allowed['player.gearUp'] ~= true or IsPauseMenuActive() then return end
    CreateThread(function() EsAdmin.executeAction('player.gearUp') end)
end, false)
EsAdmin.addKeyMapping('gearup', 'Cortex Admin: gear up', '', function()
    return state.allowed['player.gearUp'] == true
end)

RegisterCommand('heal', function()
    runCommandAction('player.heal', nil, 'heal')
end, false)

RegisterCommand('armor', function()
    runCommandAction('player.armor', nil, 'armor')
end, false)

RegisterCommand('revive', function()
    runCommandAction('player.revive', nil, 'revive')
end, false)

RegisterCommand('coords', function()
    runCommandAction('player.copyCoords', nil, 'copy coords')
end, false)

RegisterCommand('copycoords', function()
    runCommandAction('player.copyCoords', nil, 'copy coords')
end, false)

RegisterCommand('heading', function()
    runCommandAction('player.copyHeading', nil, 'copy heading')
end, false)

RegisterCommand('copyheading', function()
    runCommandAction('player.copyHeading', nil, 'copy heading')
end, false)

-- Vehicle deletion aliases use the server-validated command in client/dv.lua.

RegisterCommand('delveh', function()
    ExecuteCommand('dv')
end, false)

RegisterCommand('deleteveh', function()
    ExecuteCommand('dv')
end, false)

local function spawnVehicleCommand(args)
    local model = tableConcat(args or {}, ' ')
    if type(model) == 'string' then
        model = model:match('^%s*(.-)%s*$')
    end

    if not model or model == '' then
        notify('error', 'Usage: /car [vehiclename]')
        return
    end

    runCommandAction('vehicle.spawn', { model = model }, 'spawn vehicle')
end

RegisterCommand('car', function(_, args)
    spawnVehicleCommand(args)
end, false)

RegisterCommand('veh', function(_, args)
    spawnVehicleCommand(args)
end, false)

RegisterCommand('spawnveh', function(_, args)
    spawnVehicleCommand(args)
end, false)

RegisterCommand('fix', function()
    runCommandAction('vehicle.repair', nil, 'repair vehicle')
end, false)

RegisterCommand('fixveh', function()
    runCommandAction('vehicle.repair', nil, 'repair vehicle')
end, false)

RegisterCommand('repair', function()
    runCommandAction('vehicle.repair', nil, 'repair vehicle')
end, false)

RegisterCommand('repairveh', function()
    runCommandAction('vehicle.repair', nil, 'repair vehicle')
end, false)

RegisterCommand('clean', function()
    runCommandAction('vehicle.clean', nil, 'clean vehicle')
end, false)

RegisterCommand('cleanveh', function()
    runCommandAction('vehicle.clean', nil, 'clean vehicle')
end, false)

RegisterCommand('flip', function()
    runCommandAction('vehicle.flip', nil, 'flip vehicle')
end, false)

local function vehicleDoorsCommand(_, args)
    local target = string.lower(args[1] or '')
    local aliases = {
        open = 'open_all', close = 'close_all', hood = 'toggle_4',
        trunk = 'toggle_5', bombbay = 'bomb_bay',
    }
    local value = aliases[target]
    if target:match('^[0-7]$') then value = 'toggle_' .. target end
    if #args ~= 1 or not value then
        notify('error', 'Usage: /doors [0-7|open|close|hood|trunk|bombbay]')
        return
    end
    runCommandSelect('vehicle.doors', value, 'vehicle doors')
end

RegisterCommand('doors', vehicleDoorsCommand, false)
RegisterCommand('door', vehicleDoorsCommand, false)

local function vehicleExtrasCommand(_, args)
    local raw = args[1] or ''
    local extra = raw:match('^%d+$') and tonumber(raw)
    if #args ~= 1 or not extra or extra < 0 or extra > 20 then
        notify('error', 'Usage: /extras [0-20] (toggles the selected extra)')
        return
    end
    runCommandAction('vehicle.extras', { extra = extra }, 'vehicle extras')
end

RegisterCommand('extras', vehicleExtrasCommand, false)
RegisterCommand('extra', vehicleExtrasCommand, false)

RegisterCommand('maxmods', function()
    runCommandAction('vehicle.maxMods', nil, 'max vehicle mods')
end, false)

RegisterCommand('perfmods', function()
    runCommandAction('vehicle.performanceMods', nil, 'full performance upgrades')
end, false)

RegisterCommand('performancemods', function()
    runCommandAction('vehicle.performanceMods', nil, 'full performance upgrades')
end, false)

local function giveWeaponCommand(args)
    local weapon = tableConcat(args or {}, ' ')
    if type(weapon) == 'string' then
        weapon = weapon:match('^%s*(.-)%s*$')
    end

    if not weapon or weapon == '' then
        notify('error', 'Usage: /weapon [weapon_name]')
        return
    end

    runCommandAction('weapons.giveCustom', { weapon = weapon }, 'give weapon')
end

RegisterCommand('weapon', function(_, args)
    giveWeaponCommand(args)
end, false)

RegisterCommand('giveweapon', function(_, args)
    giveWeaponCommand(args)
end, false)

RegisterCommand('ammo', function(_, args)
    local ammo = args and args[1]
    if not ammo or ammo == '' then
        notify('error', 'Usage: /ammo [amount]')
        return
    end

    runCommandAction('weapons.setAmmo', { ammo = ammo }, 'set ammo')
end, false)

RegisterCommand('clearweapons', function()
    runCommandAction('weapons.removeAll', nil, 'remove weapons')
end, false)

RegisterCommand('preview', function(_, args)
    if not hasCommandPermission('vehicle.spawn', 'vehicle preview') then
        return
    end

    local model = tableConcat(args, ' ')
    if type(model) == 'string' then
        model = model:match('^%s*(.-)%s*$')
    end

    if not model or model == '' then
        if EsAdmin.getPreviewVehicleModel and EsAdmin.getPreviewVehicleModel() and EsAdmin.clearVehiclePreview then
            EsAdmin.clearVehiclePreview()
            notify('info', 'Vehicle preview cleared.')
            return
        end

        notify('error', 'Usage: /preview [vehiclename]')
        return
    end

    if model == 'off' or model == 'clear' then
        if EsAdmin.clearVehiclePreview then
            EsAdmin.clearVehiclePreview()
            notify('info', 'Vehicle preview cleared.')
        end
        return
    end

    if EsAdmin.previewVehicle and EsAdmin.previewVehicle(model) then
        notify('success', ('Previewing vehicle: %s'):format(model))
    end
    openVehiclePreviewPage(model)
end, false)

-- Reset admin menu settings command
RegisterCommand('esadmin_reset', function()
    local savedToggles = state.settings.savedToggles
    state.settings = { savedToggles = savedToggles }
    for k, v in pairs(Config.DefaultSettings) do
        state.settings[k] = v
    end
    
    EsAdmin.saveSettings()
    EsAdmin.sendUiState()
    
    notify('success', 'Admin menu visual settings have been reset to defaults.')
    print('[cortex-admin] Visual settings reset to defaults via command.')
end, false)

-- ============================================================================
-- STATE LOADING
-- ============================================================================

local function loadState()
    state.settings = applyDefaultSettings(loadKvp(Config.KvpKeys.settings, {}))
    state.favorites = loadKvp(Config.KvpKeys.favorites, {}) or {}
    state.toggles = state.toggles or {}

    if state.settings and state.settings.menuPosition and type(state.settings.menuPosition) == 'string' then
        state.settings.menuPosition = state.settings.menuPosition:lower()
    end

    if state.settings.menuPosition ~= 'left' and state.settings.menuPosition ~= 'center' and state.settings.menuPosition ~= 'right' then
        state.settings.menuPosition = 'center'
    end

    local speedUnits = state.settings.speedHudUnits
    if type(speedUnits) == 'string' then
        speedUnits = speedUnits:lower()
    end
    if speedUnits ~= 'mph' and speedUnits ~= 'kph' then
        state.settings.speedHudUnits = Config.DefaultSettings.speedHudUnits
    else
        state.settings.speedHudUnits = speedUnits
    end

    local speedPos = state.settings.speedHudPosition
    if type(speedPos) == 'string' then
        speedPos = speedPos:lower()
    end
    local speedPosOk = speedPos == 'top-left' or speedPos == 'top-right' or speedPos == 'top-center'
        or speedPos == 'bottom-left' or speedPos == 'bottom-right' or speedPos == 'bottom-center'
    if not speedPosOk then
        state.settings.speedHudPosition = Config.DefaultSettings.speedHudPosition
    else
        state.settings.speedHudPosition = speedPos
    end

    if state.favorites and type(state.favorites) == 'table' then
        for index, actionId in ipairs(state.favorites) do
            if actionId == 'dev.reloadUi' then
                state.favorites[index] = 'dev.resetAllSettings'
            end
        end
    end
    
    local scale = tonumber(state.settings.uiScale) or 1.0
    if scale < 1.0 then scale = 1.0 end
    if scale > 1.6 then scale = 1.6 end
    state.settings.uiScale = scale

    local opacity = tonumber(state.settings.uiOpacity) or 0.94
    if opacity < 0.35 then opacity = 0.35 end
    if opacity > 1.0 then opacity = 1.0 end
    state.settings.uiOpacity = opacity
end

loadState()

-- ============================================================================
-- MP PED MANAGEMENT (persistent behavior)
-- ============================================================================

local mpPedState = {
    hasLoadedInitial = false,
    lastDeathTime = 0,
}

-- Try to find and load a saved ped
local function findSavedPedData()
    local lastPedName = GetResourceKvpString(LAST_PED_NAME_KEY)
    local lastPedSource = GetResourceKvpString(LAST_PED_SOURCE_KEY) or MP_PED_SOURCE_ES_ADMIN
    local lastSourceKey = GetResourceKvpString(LAST_PED_SOURCE_REF_KEY)

    if (lastPedName and lastPedName ~= '') or (lastSourceKey and lastSourceKey ~= '') then
        local sourceKey = lastSourceKey
        if not sourceKey or sourceKey == '' then
            sourceKey = normalizeSavedPedKey(lastPedName)
        end

        local _, resolvedName = normalizeSavedPedKey(sourceKey)
        resolvedName = resolvedName or lastPedName or sourceKey

        if lastPedSource == MP_PED_SOURCE_VMENU then
            local mpData = getVmenuSavedPedByKey(sourceKey)
            if mpData then
                return mpData, resolvedName, MP_PED_SOURCE_VMENU
            end
        else
            local mpData = loadKvp(sourceKey)
            if mpData then
                return normalizeMpPedData(mpData), resolvedName, MP_PED_SOURCE_ES_ADMIN
            end
        end
    end

    local defaultSource = GetResourceKvpString(DEFAULT_PED_SOURCE_KEY) or MP_PED_SOURCE_ES_ADMIN
    local defaultSourceKey = GetResourceKvpString(DEFAULT_PED_SOURCE_REF_KEY)
    if defaultSourceKey and defaultSourceKey ~= '' then
        local _, defaultName = normalizeSavedPedKey(defaultSourceKey)
        if defaultSource == MP_PED_SOURCE_VMENU then
            local mpData = getVmenuSavedPedByKey(defaultSourceKey)
            if mpData then
                return mpData, defaultName or defaultSourceKey, MP_PED_SOURCE_VMENU
            end
        else
            local mpData = loadKvp(defaultSourceKey)
            if mpData then
                return normalizeMpPedData(mpData), defaultName or defaultSourceKey, MP_PED_SOURCE_ES_ADMIN
            end
        end
    end

    local ok, defaultKey = callVmenuBridge('GetDefaultSavedMpCharacterKeyForEsAdmin')
    if ok and type(defaultKey) == 'string' and defaultKey ~= '' then
        local mpData = getVmenuSavedPedByKey(defaultKey)
        if mpData then
            local _, defaultName = normalizeSavedPedKey(defaultKey)
            return mpData, defaultName or defaultKey, MP_PED_SOURCE_VMENU
        end
    end

    return nil, nil, nil
end

-- Set default MP Ped model (male or female based on random or preference)
local function setDefaultMpPed()
    local model = joaat('mp_m_freemode_01')
    local current = GetEntityModel(PlayerPedId())
    if current == model or current == joaat('mp_f_freemode_01') then return true end
    if type(EsAdmin.authorizeVmenuModel) ~= 'function' then
        print('[cortex-admin] Default MP ped restore skipped because server model authorization is unavailable.')
        return false
    end
    local authorized = EsAdmin.authorizeVmenuModel('ped', model, 'player.loadMpPed')
    if not authorized then
        print('[cortex-admin] Default MP ped restore was denied by server model permissions.')
        return false
    end
    if exports['cortex-lib']:requestModel(model, 5000) then
        if EsAdmin.setPlayerModelPreservingWeapons then
            EsAdmin.setPlayerModelPreservingWeapons(model)
        else
            SetPlayerModel(PlayerId(), model)
        end
        SetModelAsNoLongerNeeded(model)
        
        -- IMPORTANT: Freemode peds require head blend data to be visible
        local ped = PlayerPedId()
        SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.0, false)
        
        -- Set default components so ped isn't naked
        SetPedComponentVariation(ped, 0, 0, 0, 2)  -- Face
        SetPedComponentVariation(ped, 2, 0, 0, 2)  -- Hair
        SetPedComponentVariation(ped, 3, 0, 0, 2)  -- Arms
        SetPedComponentVariation(ped, 4, 0, 0, 2)  -- Legs
        SetPedComponentVariation(ped, 6, 0, 0, 2)  -- Shoes
        SetPedComponentVariation(ped, 8, 0, 0, 2)  -- Undershirt
        SetPedComponentVariation(ped, 11, 0, 0, 2) -- Torso
        
        if Config.Debug then
            print('[cortex-admin] Set default MP Freemode ped')
        end
        return true
    end
    return false
end

-- Main function to load or restore MP ped
local function loadOrRestoreMpPed(isRespawn)
    if GetResourceState('qbx_core') == 'started' then return false end
    local settings = state.settings
    
    -- Find saved ped data
    local pedData, pedName, source = findSavedPedData()
    
    if pedData then
        if Config.Debug then
            print(('[cortex-admin] Loading saved MP Ped: %s (source: %s)'):format(pedName, source))
        end
        if type(EsAdmin.loadMpPedData) == 'function' then
            return EsAdmin.loadMpPedData(pedData) == true
        end
        print('[cortex-admin] WARNING: loadMpPedData is unavailable during startup restore.')
    end
    
    -- No saved ped found, check if we should default to MP ped. A respawn keeps
    -- the body it came back with; swapping the model would spawn a second ped.
    if settings.defaultToMpPed and not isRespawn then
        return setDefaultMpPed() == true
    end

    return false
end

-- Initial spawn handler
local function handleInitialSpawn()
    if GetResourceState('qbx_core') == 'started' then return end
    if mpPedState.hasLoadedInitial then return end
    mpPedState.hasLoadedInitial = true
    
    if not state.settings.autoLoadSavedPed then return end
    
    Wait(2000) -- Wait for player to fully spawn
    loadOrRestoreMpPed(false)
end

local function restorePedOnRespawn()
    return state.settings.restorePedOnDeath and GetResourceState('qbx_core') ~= 'started'
end

-- Up means alive, faded in and, with cortex-death, no longer down or dead.
-- cortex-death raises the body into its downed pose, which is not a respawn.
local function playerIsUp()
    if IsEntityDead(PlayerPedId()) or not IsScreenFadedIn() then return false end
    if GetResourceState('cortex-death') ~= 'started' then return true end
    local ok, down = pcall(function() return exports['cortex-death']:IsDown() end)
    return not (ok and down == true)
end

-- Death/respawn handler
local respawnPending = false
local function handleRespawn()
    while not playerIsUp() do Wait(250) end
    Wait(500)
    respawnPending = false
    -- Appearance first: a model change replaces the ped and drops its weapons.
    if restorePedOnRespawn() then loadOrRestoreMpPed(true) end
    if state.settings.restoreWeaponsOnDeath and EsAdmin.restoreDeathWeapons then EsAdmin.restoreDeathWeapons() end
end

-- Monitor for death and respawn
CreateThread(function()
    local wasDead = false

    while true do
        if restorePedOnRespawn() or state.settings.restoreWeaponsOnDeath then
            Wait(250)

            local isDead = IsEntityDead(PlayerPedId())

            -- The body still holds its weapons until it is resurrected.
            if isDead and not wasDead and state.settings.restoreWeaponsOnDeath and EsAdmin.captureDeathWeapons then
                CreateThread(EsAdmin.captureDeathWeapons)
            end
            if wasDead and not isDead and not respawnPending then
                respawnPending = true
                CreateThread(handleRespawn)
            end

            wasDead = isDead
        else
            wasDead = false
            Wait(3000)
        end
    end
end)

-- Initial spawn trigger
CreateThread(function()
    Wait(5000)
    handleInitialSpawn()
end)

EsAdmin.saveSettings = function()
    -- Every settings change lands here, including cortex-lib's settings page.
    refreshKeyMappings()
    TriggerServerEvent('cortex-admin:server:privateMessagePreference', state.settings.disablePrivateMessages == true)
    return saveKvp(Config.KvpKeys.settings, state.settings)
end

-- The settings record alone, for writes that are not settings-page changes
-- (gameplay toggle choices): no key mapping refresh, server event or cortex-lib push.
EsAdmin.writeSettingsRecord = function()
    return saveKvp(Config.KvpKeys.settings, state.settings)
end

EsAdmin.saveFavorites = function()
    saveKvp(Config.KvpKeys.favorites, state.favorites)
end

-- ============================================================================
-- NET EVENTS
-- ============================================================================

receivePermissions = function(allowed, capabilities, lease)
    -- Leases renew on every menu open with ~800 entries; compare them in place
    -- instead of encoding both copies to JSON.
    local function sameValue(a, b)
        if a == b then return true end
        if type(a) ~= 'table' or type(b) ~= 'table' then return false end
        for key, value in pairs(a) do
            if not sameValue(value, b[key]) then return false end
        end
        for key in pairs(b) do
            if a[key] == nil then return false end
        end
        return true
    end
    TriggerServerEvent('cortex-admin:server:privateMessagePreference', state.settings and state.settings.disablePrivateMessages == true or false)
    local policy = type(lease) == 'table' and lease.vmenu or nil
    local policySame = state.vmenuPolicy ~= nil and policy ~= nil and sameValue(state.vmenuPolicy, policy)
    local allowedSame = type(allowed) == 'table' and sameValue(state.allowed, allowed)
    if EsAdmin.invalidateVmenuModels and not policySame then EsAdmin.invalidateVmenuModels() end
    state.vmenuPolicy = policy
    if EsAdminVmenuPolicy then EsAdminVmenuPolicy.received = state.vmenuPolicy and state.vmenuPolicy.settings end
    if QboxAdmin and type(capabilities) == 'table' then
        QboxAdmin.serverCapabilities = capabilities
        Config.HasQBXVehicles = capabilities.hasGarage == true
    end
    state.allowed = type(allowed) == 'table' and allowed or {}
    permissionsReceived = type(lease) == 'table' and lease.menuAllowed == true
        or lease == nil and next(state.allowed) ~= nil
    permissionsExpiresAt = GetGameTimer() + math.min(30000, math.max(1000, tonumber(lease and lease.expiresInMs) or 30000))
    if EsAdmin.revokeDisallowedToggles then EsAdmin.revokeDisallowedToggles() end
    if not permissionsReceived then
        if EsAdmin.closePlayers then EsAdmin.closePlayers() end
        if EsAdmin.closeClassicMenu then EsAdmin.closeClassicMenu() end
        if EsAdmin.closeVmenuMode then EsAdmin.closeVmenuMode() end
        if EsAdmin.closeVehicleCamera then EsAdmin.closeVehicleCamera() end
        if EsAdmin.closeShowcaseCamera then EsAdmin.closeShowcaseCamera() end
        if EsAdmin.stopSpectating then EsAdmin.stopSpectating() end
        if EsAdmin.closeCharacterStudio then EsAdmin.closeCharacterStudio() end
        if EsAdmin.closeVehicleStudio then EsAdmin.closeVehicleStudio() end
        setOpen(false)
    end
    if EsAdmin.restoreSavedToggles then
        EsAdmin.restoreSavedToggles()
    elseif EsAdmin.restoreImportedVmenuSettings then
        EsAdmin.restoreImportedVmenuSettings()
    end
    if EsAdmin.applyVmenuRuntimePolicy then EsAdmin.applyVmenuRuntimePolicy() end
    if EsAdmin.scheduleVmenuAutoImport then EsAdmin.scheduleVmenuAutoImport() end
    refreshKeyMappings()
    if EsAdmin.refreshClassicMenu then EsAdmin.refreshClassicMenu() end
    if EsAdmin.refreshVmenuMode then EsAdmin.refreshVmenuMode(policySame and allowedSame) end
    if state.open then
        SendNUIMessage({
            action = 'cortex-admin:setState',
            data = { allowed = state.allowed, frameworkInfo = EsAdminBridge.getFrameworkInfo() }
        })
    end
end
RegisterNetEvent('cortex-admin:client:permissions', receivePermissions)
CreateThread(function()
    while true do
        Wait(1000)
        if permissionsReceived then
            if GetGameTimer() >= permissionsExpiresAt then
                receivePermissions({}, nil, { menuAllowed = false })
                -- Ask again at once: a lapsed lease switched every toggle off, and
                -- nothing renewed it until the menu was opened again.
                requestMenuPermissions(true)
            else
                requestMenuPermissions(false)
            end
        end
    end
end)

RegisterNetEvent('cortex-admin:client:setPlayerDirectory', function(players)
    if type(players) ~= 'table' then return end
    local normalized = {}
    for index = 1, math.min(#players, 2048) do
        local entry = players[index]
        local id = type(entry) == 'table' and tonumber(entry.id) or nil
        local name = type(entry) == 'table' and trimString(entry.name) or ''
        if id and id >= 1 and id <= 65535 and id == math.floor(id) and name ~= '' then
            normalized[#normalized + 1] = {
                id = id,
                session = type(entry.session) == 'string' and entry.session or nil,
                name = name:sub(1, 96),
                ping = math.max(0, math.min(9999, math.floor(tonumber(entry.ping) or 0))),
                bucket = math.max(0, math.min(65535, math.floor(tonumber(entry.bucket) or 0))),
                dead = entry.dead == true,
                isSelf = entry.isSelf == true,
            }
        end
    end
    tableSort(normalized, function(first, second) return first.id < second.id end)
    state.playerList = normalized
    playerDirectoryReceived = true
    if state.open then sendRuntimeUiState(true, false) end
end)

RegisterNetEvent('cortex-admin:client:setAddonVehicles', function(vehicles)
    cachedData.scannedAddonVehicles = normalizeAddonVehicles(vehicles)
    cachedData.addonVehicles = mergeAddonVehicles(cachedData.scannedAddonVehicles, cachedData.importedAddonVehicles)
    menuDataCache.addonVehiclesLoaded = true
    if state.open then
        SendNUIMessage({
            action = 'cortex-admin:setState',
            data = { addonVehicles = cachedData.addonVehicles }
        })
    end
end)

local adminFrozen = false

-- A staff freeze or the self-freeze toggle. Captures that freeze the player
-- for a camera leave the ped frozen on release while one of these holds it.
EsAdmin.isPlayerFreezeHeld = function()
    return adminFrozen or state.toggles['player.freeze'] == true
end

-- Staff teleports (Bring, Go to). `beside` lands next to the anchor instead of
-- inside it; `withVehicle` carries a vehicle this player is driving. The entity
-- holds still until collision loads, so a long jump never drops through the map.
EsAdmin.teleportPlayer = function(coords, heading, options)
    if type(coords) ~= 'table' then return false end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z
        or math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 20000 then return false end
    options = type(options) == 'table' and options or {}
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local entity = ped
    if options.withVehicle == true and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then entity = vehicle end
    local safeHeading = tonumber(heading)
    if safeHeading and (safeHeading ~= safeHeading or math.abs(safeHeading) == math.huge) then safeHeading = nil end
    if options.beside == true and safeHeading then
        -- To the anchor's right: further for a vehicle so it never lands on them.
        local gap, angle = entity == vehicle and 4.0 or 1.5, math.rad(safeHeading)
        x, y = x + math.cos(angle) * gap, y + math.sin(angle) * gap
    end
    local wasFrozen = nativeOn(IsEntityPositionFrozen(entity))
    state.lastCoords = GetEntityCoords(entity)
    FreezeEntityPosition(entity, true)
    RequestCollisionAtCoord(x + 0.0, y + 0.0, z + 0.0)
    SetEntityCoordsNoOffset(entity, x + 0.0, y + 0.0, z + 0.0, false, false, false)
    if safeHeading then SetEntityHeading(entity, (safeHeading % 360.0) + 0.0) end
    local deadline = GetGameTimer() + 2500
    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(x + 0.0, y + 0.0, z + 0.0)
        Wait(0)
    end
    -- Leave a staff freeze or a self-freeze toggle in place.
    local keepFrozen = wasFrozen or entity == ped and (adminFrozen or state.toggles['player.freeze'] == true)
        or entity == vehicle and state.toggles['vehicle.freeze'] == true
    if DoesEntityExist(entity) and not keepFrozen then FreezeEntityPosition(entity, false) end
    return true
end
RegisterNetEvent('cortex-admin:client:teleport', EsAdmin.teleportPlayer)

RegisterNetEvent('cortex-admin:client:freeze', function(enabled)
    adminFrozen = enabled == true
    FreezeEntityPosition(PlayerPedId(), adminFrozen)
end)

RegisterNetEvent('cortex-admin:client:notify', function(notifyType, message)
    notify(notifyType, message)
end)

RegisterNetEvent('cortex-admin:client:copyText', function(text)
    EsAdmin.copyToClipboard(text)
end)

-- ============================================================================
-- SINGLE UNIFIED TICK (ONLY thread in main.lua - minimal overhead)
-- ============================================================================

local lastPlayerListUpdate = 0
local lastWorldUiUpdate = 0

CreateThread(function()
    while true do
        local now = GetGameTimer()
        local menuOpen = state.open
        
        if menuOpen then
            -- Player list update every 10 seconds while open
            if now - lastPlayerListUpdate > 10000 then
                lastPlayerListUpdate = now
                TriggerServerEvent('cortex-admin:server:requestPlayerDirectory')
            elseif now - lastWorldUiUpdate > 1000 then
                sendRuntimeUiState(false, false)
            end

            if now - lastWorldUiUpdate > 1000 then
                lastWorldUiUpdate = now
            end

            Wait(250)
        else
            -- Completely idle: sleep 5 seconds
            Wait(5000)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= currentResourceName then
        return
    end

    TriggerServerEvent('cortex-admin:server:setUiPresence', { open = false })
    state.open = false
    if EsAdmin.closePlayers then EsAdmin.closePlayers() end
    EsAdmin.syncHudVisibility()
    state.menuGameControl = false
    menuTypingLock = false
    menuFocusApplied = false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
end)
