local Admin = EsAdmin
local pending, sequence = {}, 0
local nonce = tostring(GetGameTimer()) .. ':' .. tostring(math.random(100000, 999999))
local function finish(id, result)
    local request = pending[id]
    if not request then return end
    pending[id] = nil
    request.callback(result)
end

local function captureAppearance()
    local ped = PlayerPedId()
    local provider = exports['illenium-appearance']
    local appearance = { model = provider:getPedModel(ped), components = provider:getPedComponents(ped),
        props = provider:getPedProps(ped), faceFeatures = provider:getPedFaceFeatures(ped),
        headOverlays = provider:getPedHeadOverlays(ped), hair = provider:getPedHair(ped),
        eyeColor = math.max(0, GetPedEyeColor(ped)), tattoos = {} }
    -- Illenium otherwise silently substitutes a male freemode model for unknown peds.
    if not appearance.model or (joaat(appearance.model) & 0xffffffff) ~= (GetEntityModel(ped) & 0xffffffff) then
        return nil, 'Add this ped model to illenium-appearance/shared/peds.lua before saving it.'
    end
    if appearance.model == 'mp_m_freemode_01' or appearance.model == 'mp_f_freemode_01' then
        local blend, captured = readPedHeadBlendSafely(ped)
        if not captured then return nil, 'The current face blend could not be captured. The saved character was not changed.' end
        appearance.headBlend = { shapeFirst = blend.shapeFirstID, shapeSecond = blend.shapeSecondID, shapeThird = blend.shapeThirdID,
            skinFirst = blend.skinFirstID, skinSecond = blend.skinSecondID, skinThird = blend.skinThirdID,
            shapeMix = blend.shapeMix, skinMix = blend.skinMix, thirdMix = blend.thirdMix }
    end
    local decorations = capturePedDecorations and capturePedDecorations(ped)
    if not decorations then return nil, 'This client cannot read current tattoos. Update FiveM before saving an imported look.' end
    if decorations and #decorations > 0 then
        -- Map native hashes back to Illenium's named tattoo format. Never silently
        -- save the stale tattoo cache from before a Cortex wardrobe was loaded.
        local env = { Config = {} }
        local source = LoadResourceFile('illenium-appearance', 'shared/tattoos.lua')
        local chunk = source and load(source, '@illenium-tattoos', 't', env)
        if not chunk then return nil, 'The Illenium tattoo catalog could not be read.' end
        chunk()
        local known, tattoos = {}, {}
        for zone, entries in pairs(env.Config.Tattoos or {}) do
            for _, entry in ipairs(entries) do
                for _, name in ipairs({ entry.hashMale, entry.hashFemale }) do
                    if name and name ~= '' then known[(joaat(entry.collection) & 0xffffffff) .. ':' .. (joaat(name) & 0xffffffff)] = { zone = zone, entry = entry } end
                end
            end
        end
        -- Illenium's automatic hair fades are named in its constants file.
        local constants = LoadResourceFile('illenium-appearance', 'game/constants.lua') or ''
        for collection, overlay in constants:gmatch('{%s*`([^`]+)`%s*,%s*`([^`]+)`%s*}') do
            known[(joaat(collection) & 0xffffffff) .. ':' .. (joaat(overlay) & 0xffffffff)] = {
                zone = 'ZONE_HAIR', entry = { name = overlay, collection = collection, hashMale = overlay, hashFemale = overlay, opacity = 0.1 }
            }
        end
        for _, decoration in ipairs(decorations) do
            local found = known[(decoration.collection & 0xffffffff) .. ':' .. (decoration.overlay & 0xffffffff)]
            if not found then return nil, 'A current tattoo or hair decoration is missing from the Illenium tattoo catalog. Add it there or remove it before saving.' end
            tattoos[found.zone] = tattoos[found.zone] or {}
            tattoos[found.zone][#tattoos[found.zone] + 1] = found.entry
        end
        appearance.tattoos = tattoos
    elseif decorations then
        appearance.tattoos = {}
    end
    return appearance
end

-- One path for the Panel forms (NUI) and vMenu mode's native Qbox menus.
-- cb receives the server's result table, or a local failure.
function Admin.qboxRequest(data, cb)
    local action = type(data) == 'table' and QboxAdmin.actions[data.action]
    if not action or not QboxAdmin.available(action) or Admin.state.allowed[action.id] ~= true then
        cb({ ok = false, error = 'This Qbox action is unavailable or not permitted.' }); return
    end
    local count = 0
    for _ in pairs(pending) do count = count + 1 end
    if count >= 8 then cb({ ok = false, error = 'Wait for the current requests to finish.' }); return end
    local operation = data.operation
    if operation ~= 'catalog' and operation ~= 'execute' then cb({ ok = false, error = 'Invalid operation.' }); return end
    if operation == 'execute' and action.id == 'qbx.saveAppearance' then
        local ok, appearance, err = pcall(captureAppearance)
        if not ok or not appearance then cb({ ok = false, error = err or 'Current appearance could not be captured.' }); return end
        data.appearance = appearance
    end
    sequence = sequence + 1
    local id = nonce .. ':' .. sequence
    pending[id] = { callback = cb, action = action.id, operation = operation }
    TriggerServerEvent('cortex-admin:server:qbox', id, operation, data)
    SetTimeout(15000, function()
        finish(id, { ok = false, error = 'No server confirmation yet. Check the result before retrying a change.' })
    end)
end

RegisterNUICallback('cortex-admin:qbox', function(data, cb) Admin.qboxRequest(data, cb) end)

RegisterNetEvent('cortex-admin:client:qboxResult', function(id, result)
    local request = pending[id]
    if not request or type(result) ~= 'table' then return end
    if result.ok and request.operation == 'execute' and request.action == 'qbx.restoreAppearance' then
        local appearance = result.data and result.data.appearance
        local ok, err = pcall(function()
            if not QboxAdmin.capabilities().appearance or type(appearance) ~= 'table' then error('Appearance provider unavailable') end
            local character = exports.qbx_core:GetPlayerData()
            if not character or character.citizenid ~= result.data.citizenid then error('Character changed') end
            exports['illenium-appearance']:setPlayerAppearance(appearance)
        end)
        if not ok then result = { ok = false, error = 'The stored appearance could not be applied.' }; print(tostring(err)) end
        if ok and Admin.refreshAppearance then Admin.refreshAppearance() end
    elseif result.ok and request.operation == 'execute' and request.action == 'qbx.openInventory' then
        Admin.setOpen(false)
    end
    finish(id, result)
end)

local resources = { qbx_core = true, ox_inventory = true, qbx_vehicles = true,
    qbx_garages = true, ['illenium-appearance'] = true, oxmysql = true }
RegisterNetEvent('cortex-admin:client:qboxCapabilities', function(caps)
    if type(caps) ~= 'table' then return end
    QboxAdmin.serverCapabilities = caps
    Config.HasQBXVehicles = caps.hasGarage == true
    SendNUIMessage({ action = 'cortex-admin:setState', data = { frameworkInfo = caps } })
    TriggerServerEvent('cortex-admin:server:requestPermissions')
end)
local function update(resource)
    if not resources[resource] then return end
    SendNUIMessage({ action = 'cortex-admin:setState', data = { frameworkInfo = QboxAdmin.capabilities() } })
    TriggerServerEvent('cortex-admin:server:requestPermissions')
end
AddEventHandler('onClientResourceStart', update)
AddEventHandler('onClientResourceStop', function(resource)
    if resources[resource] or resource == GetCurrentResourceName() then
        for id in pairs(pending) do finish(id, { ok = false, error = 'A required resource stopped. Reopen the menu.' }) end
    end
    update(resource)
end)
AddEventHandler('QBCore:Client:OnPlayerUnload', function()
    for id in pairs(pending) do finish(id, { ok = false, error = 'Character logged out.' }) end
    Admin.setOpen(false)
end)
