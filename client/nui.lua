local Admin = EsAdmin
local state = Admin.state
local mathFloor = math.floor
local tonumber = tonumber
local type = type
local nativeRegisterNUICallback = RegisterNUICallback
local nativeCreateThread = CreateThread
local silentThreads = setmetatable({}, { __mode = 'k' })
Admin.silentNotificationThreads = silentThreads

local function studioNotificationsSuppressed()
    return silentThreads[coroutine.running()]
        or (Admin.isCharacterStudioActive and Admin.isCharacterStudioActive())
end

-- Retain the originating studio context across yields and after the studio closes.
local function CreateThread(handler)
    local silent = studioNotificationsSuppressed()
    return nativeCreateThread(function()
        local thread = coroutine.running()
        silentThreads[thread] = silent or nil
        local ok, err = pcall(handler)
        silentThreads[thread] = nil
        if not ok then error(err, 0) end
    end)
end

local function RegisterNUICallback(name, handler)
    nativeRegisterNUICallback(name, function(data, cb)
        local replied = false
        local function reply(payload)
            if replied then return end
            replied = true
            cb(payload)
        end

        local thread = coroutine.running()
        local previous = silentThreads[thread]
        silentThreads[thread] = studioNotificationsSuppressed() or nil
        local ok, err = pcall(handler, data, reply)
        silentThreads[thread] = previous
        if not ok then
            print(('[cortex-admin] NUI callback %s failed: %s'):format(name, tostring(err)))
            reply({ ok = false, error = 'internal_error' })
        end
    end)
end

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

local function toFiniteNumber(value, minValue, maxValue)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    if minValue and number < minValue then return nil end
    if maxValue and number > maxValue then return nil end
    return number
end

local function sanitizeRgb(value)
    if type(value) ~= 'table' then return nil end
    local count = 0
    for key in pairs(value) do
        if key ~= 1 and key ~= 2 and key ~= 3 then return nil end
        count = count + 1
    end
    if count ~= 3 then return nil end

    local red = toInteger(value[1], 0, 255)
    local green = toInteger(value[2], 0, 255)
    local blue = toInteger(value[3], 0, 255)
    if red == nil or green == nil or blue == nil then return nil end
    return { red, green, blue }
end

local function replyError(cb, message)
    cb({ ok = false, error = message or 'invalid_payload' })
end

local actionIndex = {}
for _, action in ipairs((EsAdminActions and EsAdminActions.actions) or {}) do
    actionIndex[action.id] = true
end

local function canInvokeAction(actionId)
    if Admin.hasMenuAccess and not Admin.hasMenuAccess() then return false end
    local known = actionIndex[actionId] == true
        or (Config.ActionPermissions and Config.ActionPermissions[actionId] ~= nil)
    return known and state.allowed[actionId] == true
end

local function sanitizeSetting(key, value)
    if key == 'interfaceStyle' then
        -- Legacy leonida/console values stay valid and render the panel surface.
        return (value == 'panel' or value == 'leonida' or value == 'console' or value == 'classic' or value == 'vmenu') and value or nil
    end
    local booleanSettings = {
        showTargetInfo = true,
        doubleClickToRun = true,
        mouseMenuControls = true,
        autoLoadSavedPed = true,
        restorePedOnDeath = true,
        restoreWeaponsOnDeath = true,
        vmenuNoclipControls = true,
        defaultToMpPed = true,
        replacePersonalVehicle = true,
        spawnInsideVehicle = true,
        disableAircraftTurbulence = true,
        disablePlaneTurbulence = true,
        disableHelicopterTurbulence = true,
        disablePrivateMessages = true,
        disableControllerSupport = true,
        minimapControls = true,
        fingerPointControls = true,
    }
    if booleanSettings[key] then
        if type(value) == 'boolean' then return value end
        return nil
    end
    if key == 'uiScale' then
        local number = tonumber(value)
        return number and number == number and number >= 1.0 and number <= 1.6 and number or nil
    end
    if key == 'uiOpacity' then
        local number = tonumber(value)
        return number and number == number and number >= 0.35 and number <= 1.0 and number or nil
    end
    if key == 'menuAccentColor' then
        return type(value) == 'string' and value:match('^#[%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F]$') and value:lower() or nil
    end
    if key == 'menuPosition' then
        if value == 'left' or value == 'center' or value == 'right' then return value end
        return nil
    end
    if key == 'speedHudUnits' then
        if value == 'mph' or value == 'kph' then return value end
        return nil
    end
    if key == 'speedHudPosition' then
        local allowed = { ['top-left'] = true, ['top-right'] = true, ['bottom-left'] = true, ['bottom-right'] = true }
        return allowed[value] and value or nil
    end
    return nil
end

local function buildEmptyAppearancePayload()
    return {
        components = {},
        props = {},
        maxComponents = {},
        maxProps = {},
        model = 0,
        isFreemode = false,
        features = {},
        headBlend = {
            shapeFirstID = 0,
            shapeSecondID = 0,
            shapeThirdID = 0,
            skinFirstID = 0,
            skinSecondID = 0,
            skinThirdID = 0,
            shapeMix = 0.5,
            skinMix = 0.5,
            thirdMix = 0.0,
        },
        hairColor = 0,
        hairHighlightColor = 0,
        eyeColor = 0,
        overlays = {},
    }
end

local function agentDbg() end

local function isFavorite(id)
    for i = 1, #state.favorites do
        if state.favorites[i] == id then
            return i
        end
    end
    return nil
end

local function toggleFavorite(id)
    if not id then
        return false
    end

    local index = isFavorite(id)
    if index then
        table.remove(state.favorites, index)
    else
        state.favorites[#state.favorites + 1] = id
    end

    Admin.saveFavorites()
    -- Send only favorites update, not entire state
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { favorites = state.favorites }
    })

    return true
end

RegisterNUICallback('cortex-admin:ready', function(_, cb)
    Admin.markUiReady()
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:close', function(_, cb)
    Admin.setOpen(false)
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:action', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId or not canInvokeAction(actionId) then
        replyError(cb, 'invalid_action')
        return
    end

    local payload = data and data.data
    CreateThread(function()
        local ok, result = pcall(Admin.executeAction, actionId, payload)
        if not ok then
            print(('[cortex-admin] action %s failed: %s'):format(actionId, tostring(result)))
            replyError(cb, 'action_failed')
            return
        end
        if result == false then
            replyError(cb, 'action_failed')
            return
        end
        cb({ ok = true })
    end)
end)

RegisterNUICallback('cortex-admin:previewVehicle', function(data, cb)
    local model = data and data.model
    if (type(model) ~= 'string' and type(model) ~= 'number') or not Admin.previewVehicle then
        replyError(cb, 'invalid_model')
        return
    end

    if type(model) == 'string' then
        model = trimString(model, 64)
        if not model then
            replyError(cb, 'invalid_model')
            return
        end
    end

    local ok = Admin.previewVehicle(model)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:clearVehiclePreview', function(_, cb)
    if Admin.clearVehiclePreview then
        Admin.clearVehiclePreview()
    end
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:getPreviewVehicleExtras', function(_, cb)
    local list = Admin.getPreviewVehicleExtras and Admin.getPreviewVehicleExtras() or {}
    cb({ ok = true, extras = list })
end)

RegisterNUICallback('cortex-admin:getVehicleTuning', function(_, cb)
    if not canInvokeAction('vehicle.liveTuning') then
        replyError(cb, 'forbidden')
        return
    end
    local payload = Admin.buildVehicleTuningSnapshot and Admin.buildVehicleTuningSnapshot()
        or { ok = false, error = 'tuning_unavailable', message = 'Live vehicle tuning is unavailable.' }
    cb(payload)
end)

RegisterNUICallback('cortex-admin:setVehicleHandling', function(data, cb)
    if not canInvokeAction('vehicle.liveTuning') then
        replyError(cb, 'forbidden')
        return
    end
    local fieldId = trimString(data and data.field, 64)
    if not fieldId or not data or data.value == nil then
        replyError(cb, 'invalid_handling_value')
        return
    end

    local payload = Admin.setVehicleTuningValue and Admin.setVehicleTuningValue(fieldId, data.value)
        or { ok = false, error = 'tuning_unavailable', message = 'Live vehicle tuning is unavailable.' }
    cb(payload)
end)

RegisterNUICallback('cortex-admin:resetVehicleTuningField', function(data, cb)
    if not canInvokeAction('vehicle.liveTuning') then
        replyError(cb, 'forbidden')
        return
    end
    local fieldId = trimString(data and data.field, 64)
    if not fieldId then
        replyError(cb, 'invalid_handling_field')
        return
    end

    local payload = Admin.resetVehicleTuningField and Admin.resetVehicleTuningField(fieldId)
        or { ok = false, error = 'tuning_unavailable', message = 'Live vehicle tuning is unavailable.' }
    cb(payload)
end)

RegisterNUICallback('cortex-admin:setVehicleEngineAudio', function(data, cb)
    if not canInvokeAction('vehicle.liveTuning') then
        replyError(cb, 'forbidden')
        return
    end
    local rawSoundName = data and data.soundName
    if type(rawSoundName) ~= 'string' or #rawSoundName > 64 then
        replyError(cb, 'invalid_audio_name')
        return
    end

    local soundName = trimString(rawSoundName, 64)
    if not soundName then
        replyError(cb, 'invalid_audio_name')
        return
    end

    local payload = Admin.setVehicleTuningAudio and Admin.setVehicleTuningAudio(soundName)
        or { ok = false, error = 'tuning_unavailable', message = 'Engine audio switching is unavailable.' }
    cb(payload)
end)

RegisterNUICallback('cortex-admin:resetVehicleTuning', function(data, cb)
    if not canInvokeAction('vehicle.liveTuning') then
        replyError(cb, 'forbidden')
        return
    end
    local scope = trimString(data and data.scope, 16) or 'handling'
    if scope ~= 'handling' and scope ~= 'audio' and scope ~= 'all' then
        replyError(cb, 'invalid_reset_scope')
        return
    end

    local payload = Admin.resetVehicleTuning and Admin.resetVehicleTuning(scope)
        or { ok = false, error = 'tuning_unavailable', message = 'Live vehicle tuning is unavailable.' }
    cb(payload)
end)

RegisterNUICallback('cortex-admin:getWeaponAttachments', function(_, cb)
    if not canInvokeAction('weapons.attachments') then
        replyError(cb, 'forbidden')
        return
    end
    local payload = Admin.getWeaponAttachmentList and Admin.getWeaponAttachmentList() or { weaponName = '', components = {} }
    cb({
        ok = true,
        weaponName = payload.weaponName or '',
        components = payload.components or {},
    })
end)

RegisterNUICallback('cortex-admin:toggleWeaponAttachment', function(data, cb)
    if not canInvokeAction('weapons.attachments') then
        replyError(cb, 'forbidden')
        return
    end
    local h = trimString(data and data.componentHash, 192)
    if not h then
        replyError(cb, 'invalid_component')
        return
    end

    local ok = Admin.toggleWeaponAttachment and Admin.toggleWeaponAttachment(h)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:togglePreviewVehicleExtra', function(data, cb)
    local id = toInteger(data and data.extraId, 1, 99)
    if not id then
        replyError(cb, 'invalid_extra')
        return
    end

    local ok = Admin.togglePreviewVehicleExtra and Admin.togglePreviewVehicleExtra(id)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:setVehiclePreviewShared', function(data, cb)
    local ok = Admin.setPreviewShared and Admin.setPreviewShared(data and data.shared == true)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:spawnPreviewVehicle', function(_, cb)
    CreateThread(function()
        local okCall, ok = pcall(function()
            return Admin.spawnVehicleFromPreview and Admin.spawnVehicleFromPreview() or false
        end)
        if not okCall then
            replyError(cb, 'spawn_failed')
            return
        end
        cb({ ok = ok == true })
    end)
end)

RegisterNUICallback('cortex-admin:setMenuGameControl', function(data, cb)
    if type(data) ~= 'table' or type(data.enabled) ~= 'boolean' then
        replyError(cb, 'invalid_mode'); return
    end
    local ok, reason = Admin.setMenuGameControl(data.enabled)
    cb({ ok = ok == true, error = reason })
end)

RegisterNUICallback('cortex-admin:setTypingState', function(data, cb)
    if Admin.setTypingLock then
        Admin.setTypingLock(data and data.typing == true)
    end
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:toggle', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId or not canInvokeAction(actionId) then
        replyError(cb, 'invalid_action')
        return
    end

    Admin.toggleAction(actionId, data and data.enabled == true)
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:select', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId or not canInvokeAction(actionId) then
        replyError(cb, 'invalid_action')
        return
    end

    Admin.selectAction(actionId, data and data.value)
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:favorite', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId or not canInvokeAction(actionId) then
        replyError(cb, 'invalid_action')
        return
    end

    toggleFavorite(actionId)
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:updateSetting', function(data, cb)
    local key = trimString(data and data.key, 64)
    if not key then
        replyError(cb, 'invalid_setting')
        return
    end

    local value = sanitizeSetting(key, data and data.value)
    if value == nil then
        replyError(cb, 'invalid_setting_value')
        return
    end

    if key == 'interfaceStyle' and value == 'classic' and state.open then
        local ok = Admin.openClassicMenu()
        if not ok then replyError(cb, 'classic_unavailable'); return end
    end
    if key == 'interfaceStyle' and value == 'vmenu' and state.open then
        if not Admin.openVmenuMode() then replyError(cb, 'vmenu_unavailable'); return end
    end
    state.settings[key] = value
    Admin.saveSettings()
    -- Send only settings update
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { settings = state.settings }
    })
    cb({ ok = true })
end)


-- Smite kinds; the server checks the same list.
local SMITE_KINDS = { launch = true, fire = true, chicken = true, drunk = true }

RegisterNUICallback('cortex-admin:playerAction', function(data, cb)
    local action = trimString(data and data.action, 16)
    local target = toInteger(data and data.target, 1)
    local actionPermissions = {
        ['goto'] = 'player.goto',
        waypoint = 'player.waypoint',
        spectate = 'player.spectate',
        message = 'player.message',
        identifiers = 'player.identifiers',
        kill = 'player.kill',
        orbital = 'player.orbitalStrike',
        smite = 'player.smite',
        kick = 'player.kick',
        ban = 'player.ban',
        freeze = 'player.freezeTarget',
        bring = 'player.bring',
    }
    local actionId = action and actionPermissions[action]
    if not action or not target or not actionId or not canInvokeAction(actionId) then
        replyError(cb, 'invalid_player_action')
        return
    end

    data.action = action
    data.target = target

    if action == 'smite' and not SMITE_KINDS[data.kind] then
        replyError(cb, 'invalid_player_action')
        return
    end

    if action == 'ban' then
        local rawDuration = data.duration
        local duration = 0
        if rawDuration ~= nil and rawDuration ~= '' then
            duration = toInteger(rawDuration, 0, 525600)
            if duration == nil then
                replyError(cb, 'invalid_ban_duration')
                return
            end
        end
        data.duration = duration
    end

    -- Freeze: the server keeps the shared state and toggles it unless the
    -- console asks for an explicit state.
    if action == 'freeze' and type(data.enabled) ~= 'boolean' then data.enabled = nil end

    if action == 'waypoint' or action == 'spectate' or action == 'message' or action == 'identifiers' or action == 'kill'
        or action == 'orbital' or action == 'smite' then
        TriggerServerEvent('cortex-admin:server:vmenuPlayerAction', data)
    else
        TriggerServerEvent('cortex-admin:server:playerAction', data)
    end
    cb({ ok = true })
end)

-- Resources
RegisterNetEvent('cortex-admin:client:setResources', function(resources)
    state.resources = resources
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { resources = resources }
    })
    if Admin.onVmenuResources then Admin.onVmenuResources() end
end)

RegisterNUICallback('cortex-admin:requestResources', function(_, cb)
    TriggerServerEvent('cortex-admin:server:requestResources')
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:requestAddonVehicles', function(_, cb)
    local requested = false
    if type(Admin.requestAddonVehiclesIfNeeded) == 'function' then
        requested = Admin.requestAddonVehiclesIfNeeded(false) == true
    else
        TriggerServerEvent('cortex-admin:server:requestAddonVehicles')
        requested = true
    end
    cb({ ok = true, requested = requested })
end)

RegisterNUICallback('cortex-admin:resourceAction', function(data, cb)
    local action = trimString(data and data.action, 16)
    local name = trimString(data and data.name, 64)
    if not action or not name then
        replyError(cb, 'invalid_resource_action')
        return
    end

    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    TriggerServerEvent('cortex-admin:server:resourceAction', {
        action = action,
        name = name,
    })
    cb({ ok = true })
end)

-- Appearance
RegisterNUICallback('cortex-admin:studio', function(data, cb)
    if type(data) ~= 'table' then return replyError(cb, 'invalid_payload') end
    if data.action == 'close' then
        Admin.closeCharacterStudio()
        return cb({ ok = true })
    end
    if not state.open or not canInvokeAction('player.setAppearance') then return replyError(cb, 'forbidden') end
    if data.action == 'open' then return cb(Admin.openCharacterStudio()) end
    if data.action == 'camera' then return cb(Admin.moveCharacterStudioCamera(data)) end
    if data.action == 'catalog' then return cb(Admin.getStudioCatalog()) end
    replyError(cb, 'invalid_action')
end)

RegisterNUICallback('cortex-admin:getAppearance', function(_, cb)
    agentDbg('H4', 'nui.lua:getAppearance', 'enter', {})
    local ok, data = pcall(Admin.getPedAppearance)
    if not ok or type(data) ~= 'table' then
        print(('[cortex-admin] WARNING: Failed to build appearance payload: %s'):format(tostring(data)))
        agentDbg('H4', 'nui.lua:getAppearance', 'error', { error = tostring(data) })
        cb(buildEmptyAppearancePayload())
        return
    end

    agentDbg('H4', 'nui.lua:getAppearance', 'exit', {})
    cb(data)
end)

RegisterNUICallback('cortex-admin:setAppearance', function(data, cb)
    if not canInvokeAction('player.setAppearance') or type(data) ~= 'table' then
        replyError(cb, 'invalid_appearance')
        return
    end

    local valid = false
    if data.type == 'component' or data.type == 'prop' then
        local component = data.type == 'component'
        valid = toInteger(data.id, 0, component and 11 or 7) ~= nil
            and toInteger(data.drawable, component and 0 or -1, 4095) ~= nil
            and toInteger(data.texture, 0, 1023) ~= nil
    elseif data.type == 'blend' then
        local mix = data.field == 'shapeMix' or data.field == 'skinMix' or data.field == 'thirdMix'
        local parent = data.field == 'shapeFirstID' or data.field == 'shapeSecondID' or data.field == 'shapeThirdID'
            or data.field == 'skinFirstID' or data.field == 'skinSecondID' or data.field == 'skinThirdID'
        valid = (mix and toFiniteNumber(data.value, 0, 1) ~= nil) or (parent and toInteger(data.value, 0, 45) ~= nil)
    elseif data.type == 'overlay' then
        valid = toInteger(data.id, 0, 12) ~= nil and (
            (data.field == 'opacity' and toFiniteNumber(data.value, 0, 1) ~= nil)
            or (data.field == 'style' and toInteger(data.value, 0, 255) ~= nil)
            or ((data.field == 'color' or data.field == 'secondColor') and toInteger(data.value, 0, 63) ~= nil))
    elseif data.type == 'color' then
        local colorTypes = { hair = true, hairHighlight = true, eyes = true }
        -- Preserve the existing overlay color controls.
        local overlayColor = data.colorType == 'overlay' and toInteger(data.id, 0, 12) ~= nil
        valid = (colorTypes[data.colorType] == true or overlayColor)
            and toInteger(data.value, 0, data.colorType == 'eyes' and 31 or 63) ~= nil
    end
    if not valid then return replyError(cb, 'invalid_appearance') end

    Admin.setPedAppearance(data)
    cb({ ok = true, appearance = Admin.getPedAppearance() })
end)

local appearanceGenerationBusy = false
RegisterNUICallback('cortex-admin:randomizeAppearance', function(data, cb)
    if not canInvokeAction('player.randomizeAppearance') or type(data) ~= 'table'
        or type(Admin.randomizeAppearance) ~= 'function' then
        replyError(cb, 'invalid_action')
        return
    end

    local options = AppearanceRandomizer and AppearanceRandomizer.sanitizeOptions
        and AppearanceRandomizer.sanitizeOptions(data) or nil
    if not options then
        replyError(cb, 'invalid_appearance_options')
        return
    end

    if appearanceGenerationBusy then return replyError(cb, 'generation_busy') end
    appearanceGenerationBusy = true

    CreateThread(function()
        local ok, result = pcall(Admin.randomizeAppearance, options)
        appearanceGenerationBusy = false
        if not ok then
            print(('[cortex-admin] appearance generator failed: %s'):format(tostring(result)))
            replyError(cb, 'generation_failed')
            return
        end
        cb(type(result) == 'table' and result or { ok = result == true })
    end)
end)

RegisterNUICallback('cortex-admin:undoRandomizedAppearance', function(_, cb)
    if not canInvokeAction('player.undoRandomizedAppearance')
        or type(Admin.undoRandomizedAppearance) ~= 'function' then
        replyError(cb, 'invalid_action')
        return
    end

    CreateThread(function()
        local ok, result = pcall(Admin.undoRandomizedAppearance)
        if not ok then
            print(('[cortex-admin] appearance undo failed: %s'):format(tostring(result)))
            replyError(cb, 'undo_failed')
            return
        end
        cb(type(result) == 'table' and result or { ok = result == true })
    end)
end)

-- Vehicle Customization
RegisterNUICallback('cortex-admin:vehicleStudio', function(data, cb)
    if type(data) ~= 'table' then return replyError(cb, 'invalid_payload') end
    if data.action == 'close' then return cb(Admin.closeVehicleStudio(data.session)) end
    if not state.open or not canInvokeAction('vehicle.spawn') then return replyError(cb, 'forbidden') end
    if data.action == 'open' then
        CreateThread(function()
            local ok, result = pcall(Admin.openVehicleStudio, data)
            if not ok then
                Admin.closeVehicleStudio()
                print('[cortex-admin] Vehicle studio open failed: ' .. tostring(result))
                return replyError(cb, 'studio_open_failed')
            end
            cb(result)
        end)
    else cb(Admin.controlVehicleStudio(data)) end
end)

RegisterNUICallback('cortex-admin:getVehicleCustomization', function(query, cb)
    if not state.open then return replyError(cb, 'forbidden') end
    if type(query) == 'table' and query.studioSession ~= nil and type(query.studioSession) ~= 'string' then
        return replyError(cb, 'studio_session_expired')
    end
    local permissions = {
        mods = canInvokeAction('vehicle.customMods'),
        colors = canInvokeAction('vehicle.customColors'),
        liveries = canInvokeAction('vehicle.customLiveries'),
        extras = canInvokeAction('vehicle.customExtras'),
        underglow = canInvokeAction('vehicle.customUnderglow'),
        plate = canInvokeAction('vehicle.plateType'),
    }
    if not permissions.mods and not permissions.colors and not permissions.liveries
        and not permissions.extras and not permissions.underglow and not permissions.plate then
        replyError(cb, 'forbidden')
        return
    end

    -- A thrown error or an unencodable snapshot would otherwise leave the NUI
    -- request unanswered until its timeout, which hides the real cause.
    local ok, data, errorReason = pcall(Admin.getVehicleCustomization, type(query) == 'table' and query.studioSession or nil)
    if not ok then
        print(('[cortex-admin] Vehicle customization read failed: %s'):format(tostring(data)))
        return replyError(cb, 'read_failed')
    end
    if type(data) ~= 'table' then
        replyError(cb, errorReason or 'no_vehicle')
        return
    end
    data.ok = true
    data.permissions = permissions
    if json and json.encode then
        local encoded, encodeError = pcall(json.encode, data)
        if not encoded then
            print(('[cortex-admin] Vehicle customization snapshot could not be encoded: %s'):format(tostring(encodeError)))
            return replyError(cb, 'read_unencodable')
        end
    end
    cb(data)
end)

RegisterNUICallback('cortex-admin:setVehicleCustomization', function(data, cb)
    if not state.open then return replyError(cb, 'forbidden') end
    if type(data) ~= 'table' then
        replyError(cb, 'invalid_vehicle_customization')
        return
    end

    local kind = trimString(data.type, 32)
    local permissionByType = {
        modKit = 'vehicle.customMods',
        mod = 'vehicle.customMods',
        wheelType = 'vehicle.customMods',
        window = 'vehicle.customMods',
        xenonColor = 'vehicle.customMods',
        color = 'vehicle.customColors',
        paintFinish = 'vehicle.customColors',
        customColor = 'vehicle.customColors',
        tyreSmokeColor = 'vehicle.customColors',
        enveff = 'vehicle.customColors',
        livery = 'vehicle.customLiveries',
        modLivery = 'vehicle.customLiveries',
        extra = 'vehicle.customExtras',
        neon = 'vehicle.customUnderglow',
        neonColor = 'vehicle.customUnderglow',
        plate = 'vehicle.plateType',
    }
    local actionId = kind and permissionByType[kind] or nil
    if not actionId then
        replyError(cb, 'invalid_customization_type')
        return
    end
    if not canInvokeAction(actionId) then
        replyError(cb, 'forbidden')
        return
    end

    local sanitized = { type = kind }
    if kind == 'modKit' then
        sanitized.value = toInteger(data.value, 0, 255)
        if sanitized.value == nil then return replyError(cb, 'invalid_modkit') end
    elseif kind == 'mod' then
        sanitized.id = toInteger(data.id, 0, 49)
        if sanitized.id == nil or (data.isToggle ~= nil and type(data.isToggle) ~= 'boolean') then
            replyError(cb, 'invalid_mod')
            return
        end
        sanitized.isToggle = data.isToggle == true
        if sanitized.isToggle then
            if (sanitized.id < 17 or sanitized.id > 22)
                or type(data.enabled) ~= 'boolean' then
                replyError(cb, 'invalid_mod_toggle')
                return
            end
            sanitized.enabled = data.enabled
        else
            sanitized.value = toInteger(data.value, -1, 4096)
            if sanitized.value == nil then
                replyError(cb, 'invalid_mod_value')
                return
            end
        end
    elseif kind == 'color' then
        local colorIds = { primary = true, secondary = true, pearlescent = true, wheel = true, dashboard = true, trim = true }
        sanitized.id = trimString(data.id, 24)
        sanitized.value = toInteger(data.value, 0, 255)
        local allowsChameleon = sanitized.id == 'primary' or sanitized.id == 'secondary'
        local validColor = sanitized.value ~= nil and (sanitized.value <= 160
            or (allowsChameleon and sanitized.value >= 223 and sanitized.value <= 238))
        if not sanitized.id or not colorIds[sanitized.id] or not validColor then
            replyError(cb, 'invalid_color')
            return
        end
    elseif kind == 'paintFinish' then
        sanitized.id = trimString(data.id, 16)
        sanitized.value = toInteger(data.value, 0, 5)
        if (sanitized.id ~= 'primary' and sanitized.id ~= 'secondary') or sanitized.value == nil then
            replyError(cb, 'invalid_paint_finish')
            return
        end
    elseif kind == 'customColor' then
        sanitized.id = trimString(data.id, 16)
        sanitized.enabled = data.enabled
        if (sanitized.id ~= 'primary' and sanitized.id ~= 'secondary') or type(sanitized.enabled) ~= 'boolean' then
            replyError(cb, 'invalid_custom_color')
            return
        end
        if sanitized.enabled then
            sanitized.value = sanitizeRgb(data.value)
            if not sanitized.value then
                replyError(cb, 'invalid_custom_color')
                return
            end
        end
    elseif kind == 'neonColor' or kind == 'tyreSmokeColor' then
        sanitized.value = sanitizeRgb(data.value)
        if not sanitized.value then
            replyError(cb, 'invalid_rgb')
            return
        end
    elseif kind == 'neon' then
        local neonIds = { front = true, back = true, left = true, right = true, all = true }
        sanitized.id = trimString(data.id, 16)
        if not sanitized.id or not neonIds[sanitized.id] or type(data.value) ~= 'boolean' then
            replyError(cb, 'invalid_neon')
            return
        end
        sanitized.value = data.value
    elseif kind == 'plate' then
        sanitized.value = toInteger(data.value, 0, 12)
        if sanitized.value == nil then replyError(cb, 'invalid_plate'); return end
    elseif kind == 'window' then
        sanitized.value = toInteger(data.value, 0, 6)
        if sanitized.value == nil then replyError(cb, 'invalid_window_tint'); return end
    elseif kind == 'wheelType' then
        sanitized.value = toInteger(data.value, 0, 20)
        if sanitized.value == nil then replyError(cb, 'invalid_wheel_type'); return end
    elseif kind == 'xenonColor' then
        sanitized.value = toInteger(data.value, -1, 255)
        if sanitized.value == nil or (sanitized.value > 12 and sanitized.value ~= 255) then
            replyError(cb, 'invalid_xenon_color')
            return
        end
    elseif kind == 'modLivery' then
        sanitized.value = toInteger(data.value, -1, 4096)
        if sanitized.value == nil then replyError(cb, 'invalid_livery'); return end
    elseif kind == 'livery' then
        sanitized.value = toInteger(data.value, -1, 255)
        if sanitized.value == nil then replyError(cb, 'invalid_livery'); return end
    elseif kind == 'extra' then
        sanitized.id = toInteger(data.id, 0, 20)
        sanitized.enabled = data.enabled
        if sanitized.id == nil or type(sanitized.enabled) ~= 'boolean' then replyError(cb, 'invalid_extra'); return end
    elseif kind == 'enveff' then
        sanitized.value = toFiniteNumber(data.value, 0.0, 1.0)
        if sanitized.value == nil then replyError(cb, 'invalid_enveff'); return end
    end

    local ok, errorReason = Admin.setVehicleCustomization(sanitized, data.studioSession)
    if ok ~= true then
        replyError(cb, errorReason or 'customization_failed')
        return
    end
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:getSavedPeds', function(_, cb)
    CreateThread(function()
        agentDbg('H3', 'nui.lua:getSavedPeds', 'enter', {})
        local ok, data = pcall(Admin.getSavedPeds)
        if not ok or type(data) ~= 'table' then
            print(('[cortex-admin] WARNING: Failed to build saved ped list: %s'):format(tostring(data)))
            agentDbg('H3', 'nui.lua:getSavedPeds', 'error', { error = tostring(data) })
            cb({})
            return
        end

        agentDbg('H3', 'nui.lua:getSavedPeds', 'exit', { count = #data })
        cb(data)
    end)
end)

RegisterNUICallback('cortex-admin:getWardrobeShareTargets', function(_, cb)
    if type(Admin.getNearbyWardrobeShareTargets) ~= 'function' then
        replyError(cb, 'wardrobe_share_unavailable')
        return
    end

    CreateThread(function()
        agentDbg('H1', 'nui.lua:getWardrobeShareTargets', 'enter', {})
        local ok, targets = pcall(Admin.getNearbyWardrobeShareTargets)
        if not ok or type(targets) ~= 'table' then
            replyError(cb, 'wardrobe_share_unavailable')
            return
        end
        agentDbg('H1', 'nui.lua:getWardrobeShareTargets', 'exit', { n = type(targets) == 'table' and #targets or -1 })
        cb({
            ok = true,
            targets = targets,
        })
    end)
end)

RegisterNUICallback('cortex-admin:shareWardrobe', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then
        replyError(cb, 'invalid_target')
        return
    end

    CreateThread(function()
        local ok = type(Admin.shareCurrentWardrobe) == 'function' and Admin.shareCurrentWardrobe(target) == true
        cb({ ok = ok })
    end)
end)

RegisterNUICallback('cortex-admin:acceptWardrobeShare', function(data, cb)
    local shareId = trimString(data and data.shareId, 96)
    if not shareId or type(Admin.acceptWardrobeShare) ~= 'function' then
        replyError(cb, 'invalid_share')
        return
    end

    cb({ ok = Admin.acceptWardrobeShare(shareId) == true })
end)

RegisterNUICallback('cortex-admin:saveWardrobeShare', function(data, cb)
    local shareId = trimString(data and data.shareId, 96)
    if not shareId or type(Admin.saveWardrobeShare) ~= 'function' then
        replyError(cb, 'invalid_share')
        return
    end

    cb({ ok = Admin.saveWardrobeShare(shareId) == true })
end)

RegisterNUICallback('cortex-admin:dismissWardrobeShare', function(data, cb)
    local shareId = trimString(data and data.shareId, 96)
    if not shareId or type(Admin.dismissWardrobeShare) ~= 'function' then
        replyError(cb, 'invalid_share')
        return
    end

    cb({ ok = Admin.dismissWardrobeShare(shareId) == true })
end)

RegisterNUICallback('cortex-admin:getSavedTeleportLocations', function(_, cb)
    if type(Admin.getSavedTeleportLocations) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    cb(Admin.getSavedTeleportLocations())
end)

RegisterNUICallback('cortex-admin:saveCurrentTeleportLocation', function(data, cb)
    if type(Admin.saveCurrentTeleportLocation) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    local name = trimString(data and data.name, 64)
    local ok = Admin.saveCurrentTeleportLocation(name)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:loadSavedTeleportLocation', function(data, cb)
    if type(Admin.loadSavedTeleportLocation) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    local name = trimString(data and data.name, 64)
    local ok = Admin.loadSavedTeleportLocation(name)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:deleteSavedTeleportLocation', function(data, cb)
    if type(Admin.deleteSavedTeleportLocation) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    local name = trimString(data and data.name, 64)
    local ok = Admin.deleteSavedTeleportLocation(name)
    cb({ ok = ok == true })
end)

-- ============================================================================
-- INVENTORY (QBX / ox_inventory)
-- ============================================================================

RegisterNUICallback('cortex-admin:requestItems', function(_, cb)
    TriggerServerEvent('cortex-admin:server:getItems')
    cb({ ok = true })
end)

RegisterNetEvent('cortex-admin:client:setItems', function(items)
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { inventoryItems = items or {} }
    })
end)

RegisterNUICallback('cortex-admin:giveItem', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local item = trimString(data and data.item, 64)
    local amount = toInteger(data and data.amount, 1, 10000)
    if not target or not item or not amount then
        replyError(cb, 'invalid_item_request')
        return
    end

    TriggerServerEvent('cortex-admin:server:giveItem', {
        target = target,
        targetSession = data.targetSession,
        item = item,
        amount = amount,
    })
    cb({ ok = true })
end)

-- ============================================================================
-- GARAGE (QBX / qbx_vehicles)
-- ============================================================================

RegisterNUICallback('cortex-admin:requestGarage', function(_, cb)
    TriggerServerEvent('cortex-admin:server:getPlayerGarage')
    cb({ ok = true })
end)

RegisterNetEvent('cortex-admin:client:setGarageVehicles', function(vehicles)
    -- vMenu mode's My Garage menu reads the same list.
    state.garageVehicles = type(vehicles) == 'table' and vehicles or {}
    if Admin.onVmenuGarage then Admin.onVmenuGarage() end
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { garageVehicles = vehicles or {} }
    })
end)

RegisterNUICallback('cortex-admin:spawnGarageVehicle', function(data, cb)
    local vehicleId = toInteger(data and data.vehicleId, 1)
    if not vehicleId then
        replyError(cb, 'invalid_vehicle')
        return
    end

    TriggerServerEvent('cortex-admin:server:spawnGarageVehicle', {
        vehicleId = vehicleId,
    })
    cb({ ok = true })
end)

-- ============================================================================
-- QBX PLAYER MANAGEMENT NUI CALLBACKS
-- ============================================================================

RegisterNUICallback('cortex-admin:killPlayer', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
TriggerServerEvent('cortex-admin:server:killPlayer', { target = target, targetSession = data.targetSession })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:revivePlayer', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
TriggerServerEvent('cortex-admin:server:revivePlayer', { target = target, targetSession = data.targetSession, requestId = type(data.requestId) == 'string' and data.requestId:sub(1, 40) or nil })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:sitInVehicle', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
    local requestId = type(data.requestId) == 'string' and data.requestId:sub(1, 40) or nil
TriggerServerEvent('cortex-admin:server:sitInVehicle', { target = target, targetSession = data.targetSession, requestId = requestId })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:setJob', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local job = trimString(data and data.job, 64)
    local rawGrade = data and data.grade
    local grade = (rawGrade == nil or rawGrade == '') and 0 or toInteger(rawGrade, 0, 99)
    if not target or not job or grade == nil then replyError(cb, 'invalid_job') return end

TriggerServerEvent('cortex-admin:server:setJob', {
        target = target,
        targetSession = data.targetSession,
        job = job,
        grade = grade,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:setGang', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local gang = trimString(data and data.gang, 64)
    local rawGrade = data and data.grade
    local grade = (rawGrade == nil or rawGrade == '') and 0 or toInteger(rawGrade, 0, 99)
    if not target or not gang or grade == nil then replyError(cb, 'invalid_gang') return end

TriggerServerEvent('cortex-admin:server:setGang', {
        target = target,
        targetSession = data.targetSession,
        gang = gang,
        grade = grade,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:setMoney', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local amount = toInteger(data and data.amount, 0, 1000000000)
    local moneyType = trimString(data and data.moneyType, 32) or 'cash'
    local actionId = trimString(data and data.actionId, 64) or 'player.setCash'
    if not target or amount == nil then replyError(cb, 'invalid_money') return end

TriggerServerEvent('cortex-admin:server:setMoney', {
        target = target,
        targetSession = data.targetSession,
        moneyType = moneyType,
        amount = amount,
        actionId = actionId,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:giveMoney', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local amount = toInteger(data and data.amount, 1, 1000000000)
    local moneyType = trimString(data and data.moneyType, 32) or 'cash'
    if not target or not amount then replyError(cb, 'invalid_money') return end

TriggerServerEvent('cortex-admin:server:giveMoney', {
        target = target,
        targetSession = data.targetSession,
        moneyType = moneyType,
        amount = amount,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:setMetadata', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local key = trimString(data and data.key, 64)
    local actionId = trimString(data and data.actionId, 64)
    if not target or not key then replyError(cb, 'invalid_metadata') return end

TriggerServerEvent('cortex-admin:server:setMetadata', {
        target = target,
        targetSession = data.targetSession,
        key = key,
        value = data and data.value,
        actionId = actionId,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:openInventory', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
TriggerServerEvent('cortex-admin:server:openInventory', { target = target, targetSession = data.targetSession })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:setRoutingBucket', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local bucket = toInteger(data and data.bucket, 0, 65535)
    if not target or bucket == nil then replyError(cb, 'invalid_bucket') return end

TriggerServerEvent('cortex-admin:server:setRoutingBucket', {
        target = target,
        targetSession = data.targetSession,
        bucket = bucket,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:adminCar', function(_, cb)
    TriggerServerEvent('cortex-admin:server:adminCar')
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:pullStash', function(data, cb)
    local stash = trimString(data and data.stash, 80)
    if not stash then replyError(cb, 'invalid_stash') return end
    TriggerServerEvent('cortex-admin:server:pullStash', { stash = stash })
    cb({ ok = true })
end)

-- ============================================================================
-- QBX CLIENT-SIDE EVENT HANDLERS
-- ============================================================================

RegisterNetEvent('cortex-admin:client:killPed', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, 0)
end)

-- The server chooses the position and sends the strike to its routing bucket.
-- The target creates one blast. Vehicle owners detonate their own nearby cars
-- so a car does not survive just because its owner is another client.
local ORBITAL_EXPLOSION = 59 -- EXP_TAG_ORBITAL_CANNON
local ORBITAL_PTFX, ORBITAL_AUDIO = 'scr_xm_orbital', 'DLC_CHRISTMAS2017/XM_ION_CANNON'
local ORBITAL_DAMAGE, ORBITAL_VEHICLE_RADIUS = 10.0, 50.0
local orbitalEffectsActive = 0
local orbitalSeen, orbitalSeenOrder = {}, {}
local function orbitalBool(value) return value == true or value == 1 end

local function orbitalVehicles(x, y, z)
    local near, requested, remote, protected = 0, 0, 0, 0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and not orbitalBool(IsEntityDead(vehicle)) then
            local point = GetEntityCoords(vehicle)
            local dx, dy, dz = point.x - x, point.y - y, point.z - z
            if dx * dx + dy * dy + dz * dz <= ORBITAL_VEHICLE_RADIUS * ORBITAL_VEHICLE_RADIUS
                and orbitalBool(NetworkGetEntityIsNetworked(vehicle)) then
                near = near + 1
                if not orbitalBool(NetworkHasControlOfEntity(vehicle)) then
                    remote = remote + 1
                else
                    local proof = false
                    if GetEntityProofs then
                        local ok, valid, _, _, explosionProof = pcall(GetEntityProofs, vehicle)
                        proof = ok and orbitalBool(valid) and orbitalBool(explosionProof)
                    end
                    if proof or not orbitalBool(GetEntityCanBeDamaged(vehicle)) then
                        protected = protected + 1
                    else
                        NetworkExplodeVehicle(vehicle, true, false, false)
                        requested = requested + 1
                        if Config.Debug then
                            print(('[cortex-admin] Orbital diag [blast-v3]: vehicle net=%d engine=%.1f dead=%s'):format(
                                NetworkGetNetworkIdFromEntity(vehicle), GetVehicleEngineHealth(vehicle), tostring(IsEntityDead(vehicle))))
                        end
                    end
                end
            end
        end
    end
    return near, requested, remote, protected
end

RegisterNetEvent('cortex-admin:client:orbitalStrike', function(strike)
    if source ~= 65535 or type(strike) ~= 'table' or type(strike.coords) ~= 'table' then return end
    local coords = strike.coords
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z
        or math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 20000 then return end
    if strike.id ~= nil then
        if type(strike.id) ~= 'number' or strike.id < 1 or strike.id > 0x7fffffff or strike.id ~= math.floor(strike.id) then return end
        if orbitalSeen[strike.id] then return end
        orbitalSeen[strike.id] = true
        orbitalSeenOrder[#orbitalSeenOrder + 1] = strike.id
        if #orbitalSeenOrder > 32 then orbitalSeen[table.remove(orbitalSeenOrder, 1)] = nil end
    end
    local ped = PlayerPedId()
    local isTarget = strike.target == GetPlayerServerId(PlayerId())
    local own = GetEntityCoords(ped)
    local dx, dy, dz = own.x - x, own.y - y, own.z - z
    if dx * dx + dy * dy + dz * dz > 1500.0 * 1500.0 then return end
    if isTarget then
        -- Damage must not wait for visual/audio streaming. Pass noDamage
        -- explicitly and perform the blast before killing its owning ped.
        AddExplosion(x + 0.0, y + 0.0, z + 0.0, ORBITAL_EXPLOSION, ORBITAL_DAMAGE, true, false, 1.0, false)
    end
    local near, requested, remote, protected = orbitalVehicles(x, y, z)
    if isTarget and DoesEntityExist(ped) and ped == PlayerPedId() then SetEntityHealth(ped, 0) end
    print(('[cortex-admin] Orbital diag [blast-v3]: id=%s target=%s radius=%.0f nearby=%d requested=%d remote=%d protected=%d'):format(
        tostring(strike.id or 'legacy'), tostring(isTarget), ORBITAL_VEHICLE_RADIUS, near, requested, remote, protected))
    orbitalEffectsActive = orbitalEffectsActive + 1
    local deadline = GetGameTimer() + 1500
    RequestNamedPtfxAsset(ORBITAL_PTFX)
    while (not HasNamedPtfxAssetLoaded(ORBITAL_PTFX) or not RequestScriptAudioBank(ORBITAL_AUDIO, false))
        and GetGameTimer() < deadline do Wait(0) end
    if HasNamedPtfxAssetLoaded(ORBITAL_PTFX) then
        UseParticleFxAssetNextCall(ORBITAL_PTFX)
        StartParticleFxNonLoopedAtCoord('scr_xm_orbital_blast', x + 0.0, y + 0.0, z + 0.0, 0.0, 0.0, 0.0, 2.0, false, false, false)
    end
    PlaySoundFromCoord(-1, 'DLC_XM_Explosions_Orbital_Cannon', x + 0.0, y + 0.0, z + 0.0, 0, false, 0, false)
    Wait(5000)
    orbitalEffectsActive = orbitalEffectsActive - 1
    if orbitalEffectsActive == 0 then
        RemoveNamedPtfxAsset(ORBITAL_PTFX)
        ReleaseNamedScriptAudioBank(ORBITAL_AUDIO)
    end
end)

-- Smite runs on the struck player's own client, like the orbital strike, so
-- their ped (which only they control) carries the effect to everyone.
local smiting = {}
local SMITE_CHICKEN, SMITE_DRUNK_CLIPSET = 'a_c_hen', 'move_m@drunk@verydrunk'
local SMITE_CHICKEN_MS, SMITE_DRUNK_MS, SMITE_FIRE_MS = 20000, 30000, 8000
local smite = {
    launch = function(ped)
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            local velocity = GetEntityVelocity(vehicle)
            SetEntityVelocity(vehicle, velocity.x, velocity.y, 38.0)
            return
        end
        if vehicle ~= 0 then TaskLeaveVehicle(ped, vehicle, 16); Wait(0) end
        SetPedToRagdoll(ped, 5000, 5000, 0, false, false, false)
        Wait(0)
        SetEntityVelocity(ped, 0.0, 0.0, 38.0)
    end,
    fire = function(ped)
        StartEntityFire(ped)
        Wait(SMITE_FIRE_MS)
        if DoesEntityExist(ped) then StopEntityFire(ped) end
    end,
    chicken = function(ped)
        local hen = joaat(SMITE_CHICKEN)
        local saved = Admin.captureTemporaryLook and Admin.captureTemporaryLook()
        if not saved or not exports['cortex-lib']:requestModel(hen, 5000) then return end
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 then TaskLeaveVehicle(ped, vehicle, 16); Wait(250) end
        if GetResourceState('ox_inventory') == 'started' then TriggerEvent('ox_inventory:disarm', true) end
        Admin.setPlayerModelPreservingWeapons(hen)
        SetModelAsNoLongerNeeded(hen)
        SetPedDefaultComponentVariation(PlayerPedId())
        Wait(SMITE_CHICKEN_MS)
        if (GetEntityModel(PlayerPedId()) & 0xffffffff) == (hen & 0xffffffff) then
            if not Admin.restoreTemporaryLook(saved) then
                Wait(250)
                if not Admin.restoreTemporaryLook(saved) then Admin.notify('error', 'Smite could not restore your original ped. Ask an admin to restore your character.') end
            end
        else
            SetModelAsNoLongerNeeded(saved.look.ModelHash)
        end
    end,
    drunk = function(ped)
        RequestAnimSet(SMITE_DRUNK_CLIPSET)
        local deadline = GetGameTimer() + 2000
        while not HasAnimSetLoaded(SMITE_DRUNK_CLIPSET) and GetGameTimer() < deadline do Wait(0) end
        if HasAnimSetLoaded(SMITE_DRUNK_CLIPSET) then SetPedMovementClipset(ped, SMITE_DRUNK_CLIPSET, 1.0) end
        SetPedIsDrunk(ped, true)
        ShakeGameplayCam('DRUNK_SHAKE', 2.0)
        SetExtraTimecycleModifier('Drunk')
        Wait(SMITE_DRUNK_MS)
        ped = PlayerPedId()
        ResetPedMovementClipset(ped, 1.0)
        SetPedIsDrunk(ped, false)
        StopGameplayCamShaking(true)
        ClearExtraTimecycleModifier()
        RemoveAnimSet(SMITE_DRUNK_CLIPSET)
    end,
}
RegisterNetEvent('cortex-admin:client:smite', function(kind)
    if not SMITE_KINDS[kind] or smiting[kind] then return end
    smiting[kind] = true
    local ok, err = pcall(smite[kind], PlayerPedId())
    smiting[kind] = nil
    if not ok then print(('[cortex-admin] Smite %s failed: %s'):format(kind, tostring(err))) end
end)

RegisterNetEvent('cortex-admin:client:revivePed', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    -- The active Cortex death controller owns its incapacitation state.
    if GetResourceState('cortex-death') == 'started' then
        TriggerEvent('cortex-death:client:revive')
        return
    end

    -- Try hospital/medical revive if available
    local revived = false

    -- Try qbx_medical
    local ok1 = pcall(function()
        exports.qbx_medical:revive()
        revived = true
    end)
    if revived then return end

    -- A local event never fails, even with no listener: only hand off to a
    -- running ambulance resource, otherwise revive natively below.
    for _, resource in ipairs({ 'qb-ambulancejob', 'qbx_ambulancejob' }) do
        if GetResourceState(resource) == 'started' then
            TriggerEvent('hospital:client:Revive')
            return
        end
    end

    -- Fallback: native revive
    NetworkResurrectLocalPlayer(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, GetEntityHeading(ped) + 0.0, true, false)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPlayerInvincible(PlayerId(), false)
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
end)

-- Enter another player's vehicle. A distant vehicle is not streamed to this
-- client, so arrive beside it first and wait for it to appear.
RegisterNetEvent('cortex-admin:client:sitInVehicle', function(netId, coords, requestId, name)
    netId = toInteger(netId, 1, 65535)
    if not netId then return end
    local owner = type(name) == 'string' and name or 'the player'
    local function done(ok, message)
        if Admin.playerResult then Admin.playerResult(requestId, ok, message) else Admin.notify(ok and 'success' or 'error', message) end
    end
    local ped = PlayerPedId()
    state.lastCoords = GetEntityCoords(ped)
    if not NetworkDoesNetworkIdExist(netId) and type(coords) == 'table' then
        local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
        if x and y and z then
            RequestCollisionAtCoord(x + 0.0, y + 0.0, z + 0.0)
            SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z + 2.0, false, false, false)
            local deadline = GetGameTimer() + 4000
            while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < deadline do Wait(50) end
        end
    end
    local vehicle = NetworkDoesNetworkIdExist(netId) and NetworkGetEntityFromNetworkId(netId) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        done(false, ("Could not reach %s's vehicle."):format(owner))
        return
    end
    -- Passenger seats first: the driver's seat is usually theirs.
    local seats = {}
    for seat = 0, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do seats[#seats + 1] = seat end
    seats[#seats + 1] = -1
    for _, seat in ipairs(seats) do
        if IsVehicleSeatFree(vehicle, seat) then
            SetPedIntoVehicle(ped, vehicle, seat)
            done(true, (seat == -1 and "Driving %s's vehicle." or "In %s's vehicle."):format(owner))
            return
        end
    end
    done(false, ("%s's vehicle has no free seat. You are beside it."):format(owner))
end)

RegisterNetEvent('cortex-admin:client:getVehicleProps', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        Admin.notify('error', 'You are not in a vehicle')
        return
    end

    local model = GetEntityModel(vehicle)

    -- Try to get full props via ox_lib
    local props = nil
    local ok = pcall(function()
        props = lib.getVehicleProperties(vehicle)
    end)

    if not ok or not props then
        -- Fallback: basic props
        props = {
            model = model,
            plate = GetVehicleNumberPlateText(vehicle),
        }
    end

    TriggerServerEvent('cortex-admin:server:adminCarSave', {
        model = model,
        props = props,
    })
end)

RegisterNUICallback('cortex-admin:deleteSavedPed', function(data, cb)
    if not data then
        replyError(cb, 'invalid_entry')
        return
    end

    local ref = (data and data.entry) or data
    CreateThread(function()
        local ok = pcall(Admin.deleteSavedPed, ref)
        cb({ ok = ok == true })
    end)
end)

RegisterNUICallback('cortex-admin:renameSavedPed', function(data, cb)
    local newName = trimString(data and data.newName, 64)
    if not data or not newName then
        replyError(cb, 'invalid_name')
        return
    end

    local entry = (data and data.entry) or data
    CreateThread(function()
        local ok = pcall(Admin.renameSavedPed, entry, newName)
        cb({ ok = ok == true })
    end)
end)

RegisterNUICallback('cortex-admin:cloneSavedPed', function(data, cb)
    local entry = (data and data.entry) or data
    local fallbackName = entry and entry.name and (entry.name .. '_clone') or nil
    local newName = trimString(data and data.newName, 64) or trimString(fallbackName, 64)
    if not entry or not newName then
        replyError(cb, 'invalid_name')
        return
    end

    CreateThread(function()
        local ok = pcall(Admin.cloneSavedPed, entry, newName)
        cb({ ok = ok == true })
    end)
end)

RegisterNUICallback('cortex-admin:importVmenuSavedPeds', function(_, cb)
    if type(Admin.importVmenuSavedPeds) ~= 'function' then
        replyError(cb, 'import_unavailable')
        return
    end

    CreateThread(function()
        local okCall, ok, result = pcall(Admin.importVmenuSavedPeds)
        if not okCall then
            print(('[cortex-admin] WARNING: vMenu ped import crashed: %s'):format(tostring(ok)))
            cb({
                ok = false,
                result = { reason = 'exception', message = tostring(ok) },
            })
            return
        end

        cb({
            ok = ok == true,
            result = result or {},
        })
    end)
end)

RegisterNUICallback('cortex-admin:getVmenuMigrationSnapshot', function(_, cb)
    if not canInvokeAction('migration.read') then
        replyError(cb, 'forbidden')
        return
    end
    if type(Admin.getVmenuMigrationSnapshot) ~= 'function' then
        replyError(cb, 'migration_unavailable')
        return
    end

    CreateThread(function()
        agentDbg('H3', 'nui.lua:getVmenuMigrationSnapshot', 'enter', {})
        local ok, snap = pcall(Admin.getVmenuMigrationSnapshot)
        if not ok or type(snap) ~= 'table' then
            print(('[cortex-admin] WARNING: Failed to build vMenu migration snapshot: %s'):format(tostring(snap)))
            cb({
                vmenuRunning = Admin.isVmenuRunning(),
                peds = {
                    available = false,
                    count = 0,
                    source = 'error',
                    importedCount = 0,
                },
                vehicles = {
                    available = false,
                    count = 0,
                    source = 'error',
                    importedCount = 0,
                },
                permissions = {
                    mode = 'error',
                    note = 'Failed to read vMenu migration snapshot.',
                },
            })
            return
        end

        agentDbg('H3', 'nui.lua:getVmenuMigrationSnapshot', 'exit', {})
        cb(snap)
    end)
end)

RegisterNUICallback('cortex-admin:getVmenuImportedConfiguration', function(_, cb)
    if type(Admin.getVmenuImportedConfig) ~= 'function' or not canInvokeAction('migration.read') then
        replyError(cb, 'forbidden')
        return
    end

    local config = Admin.getVmenuImportedConfig()
    local categories = type(Admin.getVmenuImportedCategories) == 'function' and Admin.getVmenuImportedCategories() or {}
    local function sampleList(entries)
        local sample = {}
        if type(entries) ~= 'table' then return sample end
        for index = 1, math.min(#entries, 8) do
            local entry = entries[index]
            local value = type(entry) == 'string' and entry
                or type(entry) == 'table' and (entry.name or entry.label or entry.model or entry.key)
                or nil
            value = trimString(value, 96)
            if value then sample[#sample + 1] = value end
        end
        return sample
    end
    local function groupSummary(entries)
        return {
            count = type(entries) == 'table' and #entries or 0,
            sample = sampleList(entries),
        }
    end
    local function mapSummary(entries)
        local keys = {}
        local count = 0
        if type(entries) == 'table' then
            for key in pairs(entries) do
                count = count + 1
                local clean = trimString(type(key) == 'string' and key or tostring(key), 96)
                if clean and #keys < 8 then keys[#keys + 1] = clean end
            end
        end
        table.sort(keys)
        return { count = count, sample = keys }
    end

    local addons = type(config.addons) == 'table' and config.addons or {}
    local whitelists = type(config.modelWhitelists) == 'table' and config.modelWhitelists or {}
    local locations = type(config.locations) == 'table' and config.locations or {}
    local tattooList = type(config.tattoos) == 'table' and config.tattoos or {}
    local domainPayload = {
        addons = {
            vehicles = groupSummary(addons.vehicles),
            peds = groupSummary(addons.peds),
            weapons = groupSummary(addons.weapons),
            components = groupSummary(addons.weapon_components),
        },
        extras = mapSummary(config.extras),
        locations = {
            teleports = groupSummary(locations.teleports),
            blips = groupSummary(locations.blips),
        },
        modelWhitelists = {
            vehicles = groupSummary(whitelists.whitelistedvehicle),
            peds = groupSummary(whitelists.whitelistedpeds),
            weapons = groupSummary(whitelists.whitelistedweapons),
        },
        tattoos = groupSummary(tattooList),
    }

    cb({
        ok = true,
        domains = domainPayload,
        categories = {
            peds = groupSummary(type(categories.peds) == 'table' and categories.peds or {}),
            vehicles = groupSummary(type(categories.vehicles) == 'table' and categories.vehicles or {}),
        },
    })
end)

RegisterNUICallback('cortex-admin:getBanList', function(data, cb)
    if type(Admin.getBanList) ~= 'function' or not canInvokeAction('player.viewBans') then
        replyError(cb, 'forbidden')
        return
    end
    local query = trimString(data and data.query, 64) or ''
    local offset = toInteger(data and data.offset, 0, 100000) or 0
    local limit = toInteger(data and data.limit, 1, 100) or 50
    CreateThread(function()
        local ok, page = pcall(Admin.getBanList, { query = query, offset = offset, limit = limit })
        if not ok or type(page) ~= 'table' then
            cb({ ok = false, error = ok and 'timeout' or 'exception', records = {} })
            return
        end
        cb(page)
    end)
end)

RegisterNUICallback('cortex-admin:unban', function(data, cb)
    local banId = trimString(data and data.id, 96)
    if not banId or type(Admin.unbanPlayer) ~= 'function' or not canInvokeAction('player.unban') then
        replyError(cb, 'forbidden')
        return
    end
    CreateThread(function()
        local ok, result = pcall(Admin.unbanPlayer, banId)
        if not ok or type(result) ~= 'table' then
            cb({ ok = false, error = ok and 'timeout' or 'exception' })
            return
        end
        cb(result)
    end)
end)

RegisterNUICallback('cortex-admin:importVmenuMigrationData', function(_, cb)
    if not canInvokeAction('migration.import') then
        replyError(cb, 'forbidden')
        return
    end
    if type(Admin.importVmenuMigrationData) ~= 'function' then
        replyError(cb, 'migration_unavailable')
        return
    end

    CreateThread(function()
        local okCall, ok, result = pcall(Admin.importVmenuMigrationData)
        if not okCall then
            print(('[cortex-admin] WARNING: vMenu migration import crashed: %s'):format(tostring(ok)))
            cb({
                ok = false,
                result = { reason = 'exception', message = tostring(ok) },
            })
            return
        end

        cb({
            ok = ok == true,
            result = result or {},
        })
    end)
end)
