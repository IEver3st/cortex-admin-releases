local S = EsAdminServer
local sessions, locks, catalogCache = {}, {}, {}
local function fail(message) return { ok = false, error = message } end
local function success(message, data) return { ok = true, message = message, data = data } end
local function text(value, limit)
    if type(value) ~= 'string' or #value > limit or value == '' then return nil end
    return value
end
local function player(src) return exports.qbx_core:GetPlayer(src) end
local function catalog(kind, target, group, action)
    if kind == 'players' then
        local rows = {}
        for _, id in ipairs(GetPlayers()) do
            local p = player(tonumber(id))
            if p then rows[#rows + 1] = { value = tostring(id), citizenid = p.PlayerData.citizenid,
                session = S.playerSession(tonumber(id)), label = ('[%s] %s'):format(id, EsAdminBridge.getPlayerName(tonumber(id))) } end
        end
        return rows
    end
    if kind == 'licenses' then
        local p = target and player(target)
        local rows = {}
        for name, enabled in pairs(p and p.PlayerData.metadata.licences or {}) do
            if type(enabled) == 'boolean' then rows[#rows + 1] = { value = name, label = name .. (enabled and ' (active)' or ' (inactive)') } end
        end
        return rows
    end
    if kind == 'grades' then
        local groups = action.id:find('Job', 1, true) and exports.qbx_core:GetJobs() or exports.qbx_core:GetGangs()
        local definition = groups[group]
        local rows = {}
        for grade, info in pairs(definition and definition.grades or {}) do
            rows[#rows + 1] = { value = tostring(grade), label = ('%s · %s'):format(grade, info.name or grade) }
        end
        table.sort(rows, function(a, b) return tonumber(a.value) < tonumber(b.value) end)
        return rows
    end
    local cached = catalogCache[kind]
    if cached and GetGameTimer() < cached.untilTime then return cached.rows end
    local raw, rows = nil, {}
    if kind == 'items' then raw = exports.ox_inventory:Items()
    elseif kind == 'vehicles' then raw = exports.qbx_core:GetVehiclesByName()
    elseif kind == 'garages' then raw = exports.qbx_garages:GetGarages()
    elseif kind == 'jobs' then raw = exports.qbx_core:GetJobs()
    elseif kind == 'gangs' then raw = exports.qbx_core:GetGangs()
    else return rows end
    for name, info in pairs(raw or {}) do
        if type(info) == 'table' and (kind ~= 'items' or info.retired ~= true) then
            -- Only ordinary public garages: no job, gang, house or impound delivery.
            if kind ~= 'garages' or (info.type ~= 'depot' and not info.groups and not info.canAccess) then
                rows[#rows + 1] = { value = tostring(name), label = tostring(info.label or info.name or name),
                    detail = kind == 'vehicles' and tostring(info.brand or '') or nil }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.label:lower() == b.label:lower() then return a.value < b.value end
        return a.label:lower() < b.label:lower()
    end)
    catalogCache[kind] = { rows = rows, untilTime = GetGameTimer() + 30000 }
    return rows
end

local function readCatalog(action, data)
    local kind = text(data.catalog, 24)
    local permitted = false
    for _, field in ipairs(action.fields) do if field.catalog == kind then permitted = true end end
    if not permitted then return fail('Catalog is not available for this action.') end
    if data.query ~= nil and (type(data.query) ~= 'string' or #data.query > 80) then return fail('Search text must be 80 characters or fewer.') end
    local query = (data.query or ''):lower()
    local page = S.toInteger(data.page or 1, 1, 100000)
    if not page then return fail('Invalid page.') end
    if data.refresh == true then catalogCache[kind] = nil end
    local rows = catalog(kind, S.toInteger(data.target, 1), text(data.group, 64), action)
    local result, total = {}, 0
    for _, row in ipairs(rows) do
        if query == '' or (row.label .. ' ' .. row.value .. ' ' .. (row.detail or '')):lower():find(query, 1, true) then
            total = total + 1
            if total > (page - 1) * 60 and #result < 60 then result[#result + 1] = row end
        end
    end
    return success(nil, { rows = result, total = total, page = page, pageSize = 60 })
end

-- Illenium's QB adapter has no server save export. Use its installed playerskins
-- schema atomically, without modifying qbx_core or Illenium. Never write players.
local function database(method, query, parameters)
    local pending = promise.new()
    exports.oxmysql[method](nil, query, parameters or {}, function(result, err)
        if err then pending:reject(err) else pending:resolve(result) end
    end, GetCurrentResourceName(), true)
    return Citizen.Await(pending)
end

local function validAppearance(appearance, src)
    if type(appearance) ~= 'table' or not text(appearance.model, 80) then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 or not DoesEntityExist(ped) or (joaat(appearance.model) & 0xffffffff) ~= (GetEntityModel(ped) & 0xffffffff) then return false end
    local nodes = 0
    local function bounded(value, depth)
        nodes = nodes + 1
        if nodes > 5000 or depth > 8 then return false end
        if type(value) == 'number' then return value == value and math.abs(value) < 4294967296 end
        if type(value) == 'string' then return #value <= 128 end
        if type(value) == 'boolean' then return true end
        if type(value) ~= 'table' then return false end
        for k, v in pairs(value) do
            if (type(k) ~= 'string' and type(k) ~= 'number') or not bounded(k, depth + 1) or not bounded(v, depth + 1) then return false end
        end
        return true
    end
    if not bounded(appearance, 0) then return false end
    if type(appearance.components) ~= 'table' or #appearance.components ~= 12 or type(appearance.props) ~= 'table' or #appearance.props > 8 then return false end
    local seen = {}
    for _, c in ipairs(appearance.components) do
        if type(c) ~= 'table' or not S.toInteger(c.component_id, 0, 11) or seen[c.component_id]
            or not S.toInteger(c.drawable, 0, 4096) or not S.toInteger(c.texture, 0, 4096) then return false end
        seen[c.component_id] = true
    end
    seen = {}
    for _, p in ipairs(appearance.props) do
        if type(p) ~= 'table' or not S.toInteger(p.prop_id, 0, 7) or seen[p.prop_id]
            or not S.toInteger(p.drawable, -1, 4096) or not S.toInteger(p.texture, -1, 4096) then return false end
        seen[p.prop_id] = true
    end
    local function number(value, low, high)
        return type(value) == 'number' and value == value and value >= low and value <= high
    end
    local hair = appearance.hair
    if type(hair) ~= 'table' or not S.toInteger(hair.style, 0, 4096) or not S.toInteger(hair.texture, 0, 4096)
        or not S.toInteger(hair.color, 0, 63) or not S.toInteger(hair.highlight, 0, 63)
        or not S.toInteger(appearance.eyeColor, 0, 255) then return false end
    local freemode = appearance.model == 'mp_m_freemode_01' or appearance.model == 'mp_f_freemode_01'
    if freemode then
        local blend = appearance.headBlend
        if type(blend) ~= 'table' then return false end
        for _, key in ipairs({ 'shapeFirst', 'shapeSecond', 'shapeThird', 'skinFirst', 'skinSecond', 'skinThird' }) do
            if not S.toInteger(blend[key], 0, 255) then return false end
        end
        for _, key in ipairs({ 'shapeMix', 'skinMix', 'thirdMix' }) do if not number(blend[key], 0, 1) then return false end end
    end
    local features = { 'noseWidth', 'nosePeakHigh', 'nosePeakSize', 'noseBoneHigh', 'nosePeakLowering', 'noseBoneTwist',
        'eyeBrownHigh', 'eyeBrownForward', 'cheeksBoneHigh', 'cheeksBoneWidth', 'cheeksWidth', 'eyesOpening', 'lipsThickness',
        'jawBoneWidth', 'jawBoneBackSize', 'chinBoneLowering', 'chinBoneLenght', 'chinBoneSize', 'chinHole', 'neckThickness' }
    if type(appearance.faceFeatures) ~= 'table' or type(appearance.headOverlays) ~= 'table' then return false end
    for _, key in ipairs(features) do if not number(appearance.faceFeatures[key], -1, 1) then return false end end
    for _, key in ipairs({ 'blemishes', 'beard', 'eyebrows', 'ageing', 'makeUp', 'blush', 'complexion', 'sunDamage',
        'lipstick', 'moleAndFreckles', 'chestHair', 'bodyBlemishes' }) do
        local overlay = appearance.headOverlays[key]
        if type(overlay) ~= 'table' or not S.toInteger(overlay.style, 0, 255) or not number(overlay.opacity, 0, 1)
            or not S.toInteger(overlay.color, 0, 63) or not S.toInteger(overlay.secondColor, 0, 63) then return false end
    end
    if type(appearance.tattoos) ~= 'table' then return false end
    local zones = { ZONE_TORSO = true, ZONE_HEAD = true, ZONE_LEFT_ARM = true, ZONE_RIGHT_ARM = true,
        ZONE_LEFT_LEG = true, ZONE_RIGHT_LEG = true, ZONE_HAIR = true }
    local tattooCount = 0
    for zone, tattoos in pairs(appearance.tattoos) do
        if not zones[zone] or type(tattoos) ~= 'table' then return false end
        for index, tattoo in pairs(tattoos) do
            tattooCount = tattooCount + 1
            if not S.toInteger(index, 1, 200) or tattooCount > 200 or type(tattoo) ~= 'table'
                or not text(tattoo.collection, 100) or not text(tattoo.hashMale, 100) or not text(tattoo.hashFemale, 100)
                or (tattoo.opacity ~= nil and not number(tattoo.opacity, 0, 1)) then return false end
        end
    end
    return true
end

local function mutate(src, action, data, p, check)
    check()
    local id, target, cid = action.id:sub(5), p.PlayerData.source, p.PlayerData.citizenid
    if action.confirm and data.confirm ~= true then return fail('Confirm this change before applying it.') end
    if id == 'saveAppearance' then
        if target ~= src or not validAppearance(data.appearance, src) then return fail('Current appearance could not be validated. Capture it again.') end
        local encoded = json.encode(data.appearance)
        if #encoded > 65535 then return fail('Appearance exceeds the save limit.') end
        local saved = database('transaction', {
            { query = 'UPDATE playerskins SET active = 0 WHERE citizenid = ?', values = { cid } },
            { query = 'DELETE FROM playerskins WHERE citizenid = ? AND model = ?', values = { cid, data.appearance.model } },
            { query = 'INSERT INTO playerskins (citizenid, model, skin, active) VALUES (?, ?, ?, 1)', values = { cid, data.appearance.model, encoded } },
        })
        if saved ~= true then return fail('Appearance was not saved. The previous skin is preserved.') end
        local readback = database('scalar', 'SELECT skin FROM playerskins WHERE citizenid = ? AND active = 1', { cid })
        if readback ~= encoded then return fail('The save completed but readback did not match. Check the character before saving again.') end
        return success('Current look saved as your active Qbox character appearance.')
    elseif id == 'restoreAppearance' then
        local encoded = database('scalar', 'SELECT skin FROM playerskins WHERE citizenid = ? AND active = 1', { cid })
        if not encoded then return fail('This character has no saved appearance.') end
        return success('Saved character appearance loaded.', { appearance = json.decode(encoded), citizenid = cid })
    elseif id == 'giveVehicle' then
        local model, garage = text(data.model, 64), text(data.garage, 80)
        local vehicles = exports.qbx_core:GetVehiclesByName()
        local garages = exports.qbx_garages:GetGarages()
        local g = garage and garages[garage]
        if not model or not vehicles[model] or not g or g.type == 'depot' or g.groups or g.canAccess then return fail('Select a registered vehicle and public garage.') end
        local vehicleType = vehicles[model].type or 'automobile'
        local category = (vehicleType == 'boat' and 'sea') or ((vehicleType == 'heli' or vehicleType == 'plane') and 'air') or 'car'
        if g.vehicleType and g.vehicleType ~= 'all' and g.vehicleType ~= category then return fail('This garage cannot store that vehicle type.') end
        if S.authorizeModel then
            local allowed = S.authorizeModel(src, 'vehicle', model, action.id)
            if not allowed then return fail('This vehicle is restricted by the server model policy.') end
        end
        check()
        local vehicleId = exports.qbx_vehicles:CreatePlayerVehicle({ model = model, citizenid = cid, garage = garage })
        if not vehicleId then return fail('Qbox rejected the vehicle grant.') end
        local stored = exports.qbx_vehicles:GetPlayerVehicle(vehicleId, { citizenid = cid })
        if not stored then return fail('Vehicle creation returned an ID but readback failed. Check the garage before retrying.') end
        return success(('Vehicle #%d (%s) delivered to %s.'):format(vehicleId, stored.props.plate, garage))
    elseif id == 'giveItem' or id == 'removeItem' then
        local name, quantity = text(data.item, 100), S.toInteger(data.amount, 1, 10000)
        local definition = name and exports.ox_inventory:Items(name)
        if not definition or not quantity or (id == 'giveItem' and definition.retired == true) then
            return fail('Choose a registered item and a whole quantity from 1 to 10000.')
        end
        if id == 'giveItem' and not exports.ox_inventory:CanCarryItem(target, name, quantity) then return fail('The inventory has insufficient weight or slot capacity.') end
        check()
        local ok, reason
        if id == 'giveItem' then ok, reason = exports.ox_inventory:AddItem(target, name, quantity)
        else ok, reason = exports.ox_inventory:RemoveItem(target, name, quantity) end
        if not ok then return fail('Inventory rejected the change: ' .. tostring(reason or 'unavailable')) end
        return success(('%s %d × %s.'):format(id == 'giveItem' and 'Gave' or 'Removed', quantity, name))
    elseif id == 'openInventory' then
        local left = exports.ox_inventory:forceOpenInventory(src, 'player', target)
        if not left then return fail('The inventory could not be opened.') end
        return success('Inventory opened.')
    elseif id == 'clearInventory' then
        if not exports.ox_inventory:GetInventory(target) then return fail('Inventory is not loaded.') end
        check()
        exports.ox_inventory:ClearInventory(target)
        local inventory = exports.ox_inventory:GetInventory(target)
        if not inventory or next(inventory.items or {}) then return fail('Inventory clear could not be confirmed.') end
        return success('Inventory cleared.')
    elseif id:match('Cash$') or id:match('Bank$') then
        local operation = id:match('^(%l+)')
        local amount = S.toInteger(data.amount, operation == 'set' and 0 or 1, 10000000)
        if not amount then return fail('Enter a valid whole amount, up to 10000000.') end
        local account = id:match('Cash$') and 'cash' or 'bank'
        local method = ({ add = 'AddMoney', remove = 'RemoveMoney', set = 'SetMoney' })[operation]
        local ok = exports.qbx_core[method](nil, target, account, amount, 'cortex-admin:' .. src)
        if ok ~= true then return fail('Qbox rejected the balance change.') end
        return success(('%s balance: %s.'):format(account, p.PlayerData.money[account]))
    elseif id:match('Job$') or id:match('Gang$') then
        local isJob = id:match('Job$') ~= nil
        local group, operation = text(data.group, 64), id:match('^(%l+)')
        local definitions = isJob and exports.qbx_core:GetJobs() or exports.qbx_core:GetGangs()
        if not group or not definitions[group] then return fail('Select a registered group.') end
        local grade = S.toInteger(data.grade, 0, 10000)
        if (operation == 'set' or operation == 'add') and (not grade or not definitions[group].grades[grade]) then return fail('Select a valid grade for this group.') end
        local suffix = isJob and 'Job' or 'Gang'
        local method = ({ set = 'Set' .. suffix, add = 'AddPlayerTo' .. suffix, remove = 'RemovePlayerFrom' .. suffix, primary = 'SetPlayerPrimary' .. suffix })[operation]
        local defaultGroup = isJob and 'unemployed' or 'none'
        if operation == 'primary' and group ~= defaultGroup and not (p.PlayerData[isJob and 'jobs' or 'gangs'] or {})[group] then return fail('Add this membership before making it primary.') end
        check()
        local ok = exports.qbx_core[method](nil, cid, group, grade)
        if ok == false then return fail('Qbox rejected the membership change.') end
        local current = player(target)
        if not current or current.PlayerData.citizenid ~= cid then return fail('Character changed during the update.') end
        local membership = (current.PlayerData[isJob and 'jobs' or 'gangs'] or {})[group]
        local primary = current.PlayerData[isJob and 'job' or 'gang'].name
        if (operation == 'remove' and membership ~= nil) or (operation == 'add' and membership ~= grade)
            or ((operation == 'primary' or operation == 'set') and primary ~= group) then return fail('Membership readback did not match the requested change.') end
        return success('Character membership updated.')
    elseif id == 'dutyOn' or id == 'dutyOff' then
        exports.qbx_core:SetJobDuty(target, id == 'dutyOn')
        return success(id == 'dutyOn' and 'Character is on duty.' or 'Character is off duty.')
    elseif id == 'hunger' or id == 'thirst' or id == 'stress' then
        local value = S.toInteger(data.value, 0, 100)
        if not value then return fail('Enter a whole value from 0 to 100.') end
        exports.qbx_core:SetMetadata(target, id, value)
        return success(id .. ' updated.')
    elseif id == 'resetNeeds' then
        exports.qbx_core:SetMetadata(target, 'hunger', 100)
        exports.qbx_core:SetMetadata(target, 'thirst', 100)
        exports.qbx_core:SetMetadata(target, 'stress', 0)
        return success('Hunger, thirst and stress restored.')
    elseif id == 'grantLicense' or id == 'revokeLicense' then
        local license = text(data.license, 64)
        local licenses = p.PlayerData.metadata.licences or {}
        if not license or type(licenses[license]) ~= 'boolean' then return fail('Select a license defined on this character.') end
        local updated = {}
        for key, value in pairs(licenses) do updated[key] = value end
        updated[license] = id == 'grantLicense'
        exports.qbx_core:SetMetadata(target, 'licences', updated)
        return success('Character license updated.')
    elseif id == 'saveCharacter' then
        exports.qbx_core:Save(target)
        return success('Character save requested through Qbox.')
    elseif id == 'inspectCharacter' then
        local d = p.PlayerData
        return success('Current Qbox character data.', { citizenid = cid, name = EsAdminBridge.getPlayerName(target),
            money = d.money, job = d.job, gang = d.gang, jobs = d.jobs, gangs = d.gangs,
            hunger = d.metadata.hunger, thirst = d.metadata.thirst, stress = d.metadata.stress, licenses = d.metadata.licences })
    end
    return fail('Unknown Qbox action.')
end

local function authorize(src, data, operation)
    if type(data) ~= 'table' then return nil, fail('Invalid request.') end
    if EsAdminBridge.clearPermCache then EsAdminBridge.clearPermCache(src) end
    local action = QboxAdmin.actions[data.action]
    if not action or not QboxAdmin.available(action) or not S.canOpenMenu(src) or not S.hasPermission(src, action.id) then
        return nil, fail('This Qbox action is unavailable or not permitted.')
    end
    if not S.allowRequest(src, 'qbox-' .. operation, operation == 'catalog' and 40 or 8, 10000) then
        return nil, fail('Too many requests. Wait a moment.')
    end
    return action
end

local function execute(src, action, data, requestId)
    local actor = player(src)
    if not actor then return fail('Your Qbox character is not loaded.') end
    local actorCid = actor.PlayerData.citizenid
    local actorToken = S.playerSession(src)
    local session = sessions[src]
    if not session or session.citizenid ~= actorCid then session = { citizenid = actorCid, results = {}, order = {} }; sessions[src] = session end
    if requestId and session.results[requestId] then return session.results[requestId] end
    if session.busy then return fail('A Qbox request is still running.') end
    local target = action.selfOnly and src or S.toInteger(data.target, 1)
    local p = target and player(target)
    if not p then return fail('The selected character is not online.') end
    local cid = p.PlayerData.citizenid
    if not action.selfOnly and data.targetCitizenid ~= cid then return fail('The selected character changed. Refresh the player list and select them again.') end
    local targetToken = action.selfOnly and actorToken or data.targetSession
    if not S.targetSessionMatches(target, targetToken) then return fail('The selected connection changed. Select the player again.') end
    local function check()
        if EsAdminBridge.clearPermCache then EsAdminBridge.clearPermCache(src) end
        -- Exports return a fresh copy of the player table on every call, so compare characters, not tables.
        local liveActor, liveTarget = player(src), player(target)
        assert(S.targetSessionMatches(src, actorToken) and liveActor and liveActor.PlayerData.citizenid == actorCid
            and S.targetSessionMatches(target, targetToken) and liveTarget and liveTarget.PlayerData.citizenid == cid
            and S.hasPermission(src, action.id)
            and QboxAdmin.available(action), 'Player connection or permission changed during the request.')
    end
    if locks[cid] then return fail('Another change to this character is still running.') end
    session.busy, locks[cid] = true, session
    local ok, result = pcall(mutate, src, action, data, p, check)
    if locks[cid] == session then locks[cid] = nil end
    session.busy = false
    if not ok then
        print(('[cortex-admin:qbox] %s failed for %s: %s'):format(action.id, cid, tostring(result)))
        result = fail('The supporting resource returned an error. Check the server log before retrying.')
    end
    if requestId then
        session.results[requestId] = result
        session.order[#session.order + 1] = requestId
        if #session.order > 32 then session.results[table.remove(session.order, 1)] = nil end
    end
    local audit = {}
    for _, key in ipairs({ 'item', 'model', 'garage', 'group', 'license' }) do audit[key] = text(data[key], 100) end
    audit.amount, audit.grade, audit.value = S.toInteger(data.amount, 0, 10000000), S.toInteger(data.grade, 0, 10000), S.toInteger(data.value, 0, 100)
    print(('[cortex-admin:qbox] actor=%s character=%s target=%s action=%s ok=%s details=%s'):format(src, actorCid, cid, action.id, tostring(result.ok), json.encode(audit)))
    local current = player(src)
    if sessions[src] == session and current and current.PlayerData.citizenid == actorCid
        and S.targetSessionMatches(src, actorToken) then return result end
end

-- Commands share permissions, rate limits, character locks and audit logs with NUI.
function S.executeQboxAction(src, data)
    local action, denied = authorize(src, data, 'execute')
    if not action then return denied end
    if not action.selfOnly then data.targetSession = S.playerSession(S.toInteger(data.target, 1)) end
    return execute(src, action, data)
end

RegisterNetEvent('cortex-admin:server:qbox', function(requestId, operation, data)
    local src = source
    if not text(requestId, 80) then return end
    local function reply(result) TriggerClientEvent('cortex-admin:client:qboxResult', src, requestId, result) end
    if operation ~= 'catalog' and operation ~= 'execute' then reply(fail('Invalid operation.')); return end
    local action, denied = authorize(src, data, operation)
    if not action then reply(denied); return end
    if operation == 'catalog' then
        if data.refresh == true and not S.allowRequest(src, 'qbox-rescan', 2, 10000) then reply(fail('Wait a few seconds before scanning again.')); return end
        local ok, result = pcall(readCatalog, action, data)
        reply(ok and result or fail('Catalog unavailable. Check that the supporting resource is running.'))
        return
    end
    local result = execute(src, action, data, requestId)
    if result then reply(result) end
end)

AddEventHandler('playerDropped', function() sessions[source] = nil end)
AddEventHandler('onResourceStop', function(resource)
    if resource == 'qbx_core' or resource == 'ox_inventory' or resource == 'qbx_garages' then catalogCache = {} end
end)
local supporting = { qbx_core = true, ox_inventory = true, qbx_vehicles = true, qbx_garages = true,
    ['illenium-appearance'] = true, oxmysql = true }
local function capabilitiesChanged(resource)
    if not supporting[resource] then return end
    catalogCache = {}
    S.invalidatePermissions()
    local caps = QboxAdmin.capabilities()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if S.canOpenMenu(src) then TriggerClientEvent('cortex-admin:client:qboxCapabilities', src, caps) end
    end
end
AddEventHandler('onResourceStart', capabilitiesChanged)
AddEventHandler('onResourceStop', capabilitiesChanged)
QboxAdmin.validAppearance = validAppearance
