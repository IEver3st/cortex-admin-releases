local S = EsAdminServer
local commands = {}

local function reply(src, result)
    if not result then return end -- The actor disconnected or switched characters.
    TriggerClientEvent('cortex-admin:client:notify', src, result.ok and 'success' or 'error', result.message or result.error)
end

local function register(names, usage, parse)
    for _, name in ipairs(names) do
        commands[#commands + 1] = '/' .. name .. (usage ~= '' and (' ' .. usage) or '')
        RegisterCommand(name, function(src, args)
            if src == 0 then
                print('[cortex-admin] /' .. name .. ' requires a loaded administrator character.')
                return
            end
            if GetResourceState('qbx_core') ~= 'started' then
                reply(src, { ok = false, error = 'Qbox is not running.' })
                return
            end
            local data, targetArg = parse(args)
            if not data then
                reply(src, { ok = false, error = 'Usage: /' .. name .. (usage ~= '' and (' ' .. usage) or '') })
                return
            end
            local target = targetArg == nil and src or S.toInteger(targetArg, 1, 65535)
            if not target then
                reply(src, { ok = false, error = 'Player ID must be a positive whole number.' })
                return
            end
            local action = QboxAdmin.actions[data.action]
            if EsAdminBridge.clearPermCache then EsAdminBridge.clearPermCache(src) end
            if not action or not QboxAdmin.available(action) or not S.canOpenMenu(src) or not S.hasPermission(src, action.id) then
                reply(src, { ok = false, error = 'This Qbox action is unavailable or not permitted.' })
                return
            end
            local player = exports.qbx_core:GetPlayer(target)
            if not player then
                reply(src, { ok = false, error = 'The selected character is not online.' })
                return
            end
            data.target, data.targetCitizenid = target, player.PlayerData.citizenid
            -- Typing a complete mutation command is explicit confirmation.
            data.confirm = true
            local result = S.executeQboxAction(src, data)
            if result and result.ok then
                if data.action == 'qbx.inspectCharacter' then
                    local d = result.data
                    result.message = ('[%d] %s | Citizen ID: %s | Cash: %s | Bank: %s | Job: %s (%s) | Gang: %s | Hunger: %s | Thirst: %s | Stress: %s'):format(
                        target, d.name, d.citizenid, d.money.cash, d.money.bank, d.job.name,
                        d.job.onduty and 'on duty' or 'off duty', d.gang.name, d.hunger, d.thirst, d.stress)
                else
                    result.message = ('[%d] %s'):format(target, result.message)
                end
            end
            reply(src, result)
        end, false) -- Authorization is checked on the server using the menu action.
    end
end

local function single(action, value)
    return function(args)
        if #args > 1 then return nil end
        return { action = 'qbx.' .. action, value = value }, args[1]
    end
end

for _, key in ipairs({ 'hunger', 'thirst', 'stress' }) do
    register({ key, 'qbx' .. key }, '[value 0-100] [playerId]', function(args)
        if #args > 2 then return nil end
        local value = args[1] == nil and (key == 'stress' and 0 or 100) or S.toInteger(args[1], 0, 100)
        if value == nil then return nil end
        return { action = 'qbx.' .. key, value = value }, args[2]
    end)
end
register({ 'feed', 'fillhunger' }, '[playerId]', single('hunger', 100))
register({ 'hydrate', 'fillthirst' }, '[playerId]', single('thirst', 100))
register({ 'clearstress' }, '[playerId]', single('stress', 0))
register({ 'fillneeds', 'resetneeds', 'qbxneeds' }, '[playerId]', single('resetNeeds'))
register({ 'qbxsave' }, '[playerId]', single('saveCharacter'))
register({ 'qbxinfo' }, '[playerId]', single('inspectCharacter'))

register({ 'qbxduty' }, '<on|off> [playerId]', function(args)
    local mode = args[1] and args[1]:lower()
    if #args > 2 or (mode ~= 'on' and mode ~= 'off') then return nil end
    return { action = mode == 'on' and 'qbx.dutyOn' or 'qbx.dutyOff' }, args[2]
end)

register({ 'qbxmoney' }, '<add|remove|set> <cash|bank> <amount> [playerId]', function(args)
    local operation, account = args[1] and args[1]:lower(), args[2] and args[2]:lower()
    if #args < 3 or #args > 4 or (operation ~= 'add' and operation ~= 'remove' and operation ~= 'set')
        or (account ~= 'cash' and account ~= 'bank') then return nil end
    local amount = S.toInteger(args[3], operation == 'set' and 0 or 1, 10000000)
    if amount == nil then return nil end
    return { action = 'qbx.' .. operation .. (account == 'cash' and 'Cash' or 'Bank'), amount = amount }, args[4]
end)

for _, group in ipairs({ 'Job', 'Gang' }) do
    register({ 'qbx' .. group:lower() }, '<set|add|remove|primary> <name> [grade for set/add] [playerId]', function(args)
        local operation = args[1] and args[1]:lower()
        if operation ~= 'set' and operation ~= 'add' and operation ~= 'remove' and operation ~= 'primary' then return nil end
        local graded = operation == 'set' or operation == 'add'
        local required = graded and 3 or 2
        if #args < required or #args > required + 1 then return nil end
        local grade = graded and S.toInteger(args[3], 0, 10000) or nil
        if graded and grade == nil then return nil end
        return { action = 'qbx.' .. operation .. group, group = args[2]:lower(), grade = grade }, args[required + 1]
    end)
end

register({ 'qbxlicense' }, '<grant|revoke> <license> [playerId]', function(args)
    local operation = args[1] and args[1]:lower()
    if #args < 2 or #args > 3 or (operation ~= 'grant' and operation ~= 'revoke') then return nil end
    return { action = 'qbx.' .. operation .. 'License', license = args[2] }, args[3]
end)

register({ 'qbxitem' }, '<give|remove> <item> <quantity> [playerId]', function(args)
    local operation = args[1] and args[1]:lower()
    if #args < 3 or #args > 4 or (operation ~= 'give' and operation ~= 'remove') then return nil end
    local amount = S.toInteger(args[3], 1, 10000)
    if not amount then return nil end
    return { action = 'qbx.' .. operation .. 'Item', item = args[2], amount = amount }, args[4]
end)

-- The Cortex inventory bridge exposes exports, but does not register ox's
-- administrative commands. Keep their grants on the existing admin action.
register({ 'giveitem', 'additem' }, '<playerId|me> <item> [quantity]', function(args)
    if #args < 2 or #args > 3 then return nil end
    local amount = args[3] == nil and 1 or S.toInteger(args[3], 1, 10000)
    if not amount then return nil end
    local target = args[1]
    if target:lower() == 'me' then target = nil end
    return { action = 'qbx.giveItem', item = args[2], amount = amount }, target
end)

register({ 'qbxgivevehicle' }, '<model> <publicGarage> [playerId]', function(args)
    if #args < 2 or #args > 3 then return nil end
    return { action = 'qbx.giveVehicle', model = args[1]:lower(), garage = args[2] }, args[3]
end)

RegisterCommand('qbxhelp', function(src)
    if src == 0 then print('[cortex-admin] ' .. table.concat(commands, '\n')); return end
    if not S.canOpenMenu(src) then reply(src, { ok = false, error = 'You do not have permission to use Qbox admin commands.' }); return end
    if not S.allowRequest(src, 'qbox-command-help', 2, 10000) then return end
    TriggerClientEvent('chat:addMessage', src, { args = { 'Qbox admin', table.concat(commands, '\n') } })
end, false)
