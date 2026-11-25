-- vMenu mode: Online Players and Banned Players (vMenu/menus/OnlinePlayers.cs,
-- BannedPlayers.cs, CommonFunctions.cs). Player rows send the same payloads the
-- Players console sends through cortex-admin:playerAction / sitInVehicle; the ban
-- list uses Admin.getBanList / Admin.unbanPlayer like the Bans workspace.
local Admin = EsAdmin
local VM = Admin.VmenuMode

local PLAYER_ACTIONS = {
    'player.message', 'player.goto', 'player.sitInVehicle', 'player.bring', 'player.spectate',
    'player.waypoint', 'player.identifiers', 'player.kill', 'player.orbitalStrike', 'player.smite', 'player.kick', 'player.ban',
    'player.freezeTarget', 'player.reviveTarget',
}
-- Same split as client/nui.lua cortex-admin:playerAction.
local VMENU_EVENT = { waypoint = true, spectate = true, message = true, identifiers = true, kill = true, orbital = true, smite = true }
local IDENTIFIER_COLOURS = { '~r~', '~g~', '~b~', '~o~', '~y~', '~p~', '~s~', '~t~' }
local BAN_PAGE, BAN_PAGES = 100, 5
local INVALID_INPUT = 'Nothing valid was entered, so the action was cancelled.'

-- vMenu's GetSafePlayerName: a name must not inject text formatting.
local function safeName(name)
    return (tostring(name or ''):gsub('~', '∼'):gsub('<', '«'):gsub('>', '»'))
end

local function selfId() return GetPlayerServerId(PlayerId()) end

local function players()
    local list, me, hasSelf = {}, selfId(), false
    for _, entry in ipairs(Admin.state.playerList or {}) do
        if type(entry) == 'table' and tonumber(entry.id) then
            list[#list + 1] = entry
            if entry.id == me then hasSelf = true end
        end
    end
    -- vMenu always lists the local player.
    if not hasSelf then list[#list + 1] = { id = me, name = GetPlayerName(PlayerId()), isSelf = true } end
    table.sort(list, function(a, b)
        local an, bn = tostring(a.name or ''):lower(), tostring(b.name or ''):lower()
        if an == bn then return a.id < b.id end
        return an < bn
    end)
    return list
end

local function isSelf(player) return player.id == selfId() end

local function send(action, player, extra)
    local payload = { action = action, target = player.id, targetSession = player.session }
    for key, value in pairs(extra or {}) do payload[key] = value end
    TriggerServerEvent(VMENU_EVENT[action] and 'cortex-admin:server:vmenuPlayerAction' or 'cortex-admin:server:playerAction', payload)
end

-- ---------------------------------------------------------------------------
-- Online Players

local gpsTarget -- server id of the player the last Toggle GPS routed to

local function banPlayer(player, forever)
    local reason = VM.input('Ban reason', 'Removed by server staff.', 200)
    if not reason or #reason <= 1 then Admin.notify('error', INVALID_INPUT); return end
    local duration = 0
    if not forever then
        local hours = tonumber(VM.input('Ban length in hours, up to 720 (30 days)', '1.5', 10) or '')
        if not hours then Admin.notify('error', INVALID_INPUT); return end
        if hours <= 0 then Admin.notify('error', 'Ban length must be between 1 and 720 hours.'); return end
        -- Cortex bans are in minutes, and 0 means permanent.
        duration = math.max(1, math.min(720 * 60, math.floor(hours * 60 + 0.5)))
    end
    if VM.denied('player.ban') then return end
    send('ban', player, { reason = reason, duration = duration })
end

local function toggleGps(player)
    if isSelf(player) then Admin.notify('error', 'A GPS route needs another player as its target.'); return end
    if gpsTarget == player.id and IsWaypointActive() then
        SetWaypointOff()
        gpsTarget = nil
        Admin.notify('info', ('Route to %s cleared from the map.'):format(player.name))
        return
    end
    gpsTarget = player.id
    send('waypoint', player)
end

-- Qbox character tools (job, gang, money, needs, inventory, licenses) for a
-- player, as native menus (client/vmenu_mode_qbox.lua).
local function hasCharacterTools() return Admin.vmenuHasQboxTools ~= nil and Admin.vmenuHasQboxTools(true) end

local function playerDescription(item)
    return ('Open actions for this player (server ID %d, local ID %d).'):format(item.args.id, GetPlayerFromServerId(item.args.id))
end

VM.define('online_players', {
    subtitle = 'Online Players',
    counterPreText = 'Players: ',
    onOpen = function() TriggerServerEvent('cortex-admin:server:requestPlayerDirectory') end,
    build = function()
        if not VM.canAny(PLAYER_ACTIONS) and not hasCharacterTools() then return {} end
        local rows = {}
        for _, player in ipairs(players()) do
            rows[#rows + 1] = VM.submenu('online_player', safeName(player.name), playerDescription,
                { key = player.id, id = player.id, name = player.name, session = player.session },
                { key = 'player:' .. player.id, rightLabel = ('Server #%d →→→'):format(player.id), hideEmpty = false })
        end
        return rows
    end,
})

local function row(actionId, label, description, handler, extra)
    if not VM.can(actionId) then return nil end
    return VM.button(label, description, function()
        if VM.denied(actionId) then return end
        handler()
    end, extra)
end

VM.define('online_player', {
    title = 'Online Players',
    subtitle = function(args) return '~s~Player: ~y~' .. safeName(args and args.name) end,
    counterPreText = function(args) return ('[Server ID: ~y~%s~s~] '):format(args and args.id or '?') end,
    build = function(args)
        if type(args) ~= 'table' or not args.id then return {} end
        local player = { id = args.id, name = safeName(args.name), session = args.session }
        return {
            row('player.message', 'Send Private Message', 'Send this player a direct message. ~r~Direct messages can be visible to staff.', function()
                if isSelf(player) then Admin.notify('error', 'Pick another player to message.'); return end
                if Admin.state.settings.disablePrivateMessages == true then
                    Admin.notify('error', 'Your own private messages are turned off. Turn them on in Misc Settings first.')
                    return
                end
                local message = VM.input('Message for ' .. player.name, nil, 200)
                if not message or message == '' then Admin.notify('error', INVALID_INPUT); return end
                if VM.denied('player.message') then return end
                send('message', player, { message = message })
            end),
            row('player.goto', 'Teleport To Player', 'Go to where this player is.', function()
                if isSelf(player) then Admin.notify('error', 'Pick another player to teleport to.'); return end
                send('goto', player)
            end),
            row('player.sitInVehicle', 'Teleport Into Player Vehicle', 'Take a free seat in the vehicle this player is using.', function()
                if isSelf(player) then Admin.notify('error', 'Pick another player to teleport to.'); return end
                TriggerServerEvent('cortex-admin:server:sitInVehicle', { target = player.id, targetSession = player.session })
            end),
            row('player.bring', 'Summon Player', 'Bring this player to your position.', function()
                if isSelf(player) then Admin.notify('error', 'Pick another player to summon.'); return end
                send('bring', player)
            end),
            row('player.spectate', 'Spectate Player', 'Watch this player through their camera. Select it again to return to your own view.', function()
                send('spectate', player)
            end),
            row('player.waypoint', 'Toggle GPS', 'Show or clear a minimap route that follows this player.', function()
                toggleGps(player)
            end),
            row('player.freezeTarget', 'Freeze / Unfreeze Player', 'Lock this player in place, or release them. They stay frozen until you select this again.', function()
                if isSelf(player) then Admin.notify('error', 'Use Freeze Player in Player Options for yourself.'); return end
                send('freeze', player)
            end),
            row('player.reviveTarget', 'Revive Player', 'Bring this player back from death or a downed state.', function()
                TriggerServerEvent('cortex-admin:server:revivePlayer', { target = player.id, targetSession = player.session })
            end),
            hasCharacterTools() and VM.submenu('qbox_tools', 'Qbox Character Tools', 'Job, gang, money, needs, inventory and licenses for this player.',
                { key = 'player:' .. player.id .. ':' .. tostring(player.session), target = player.id, session = player.session, name = player.name }, { key = 'characterTools', hideEmpty = false }) or nil,
            row('player.identifiers', 'Print Identifiers', "Write this player's identifiers to the F8 console, which also records them in CitizenFX.log.", function()
                send('identifiers', player)
            end),
            row('player.kill', '~r~Kill Player', 'Kill this player. They are told you did it, and the action is recorded in the Staff Actions log.', function()
                send('kill', player)
            end),
            row('player.orbitalStrike', '~r~Orbital Strike', 'Fire the orbital cannon at this player. Anyone close to them is caught in the blast.', function()
                send('orbital', player)
            end),
            row('player.smite', '~r~Smite: Launch', 'Throw this player straight up into the sky. If they are driving, their car goes with them.', function()
                send('smite', player, { kind = 'launch' })
            end),
            row('player.smite', '~r~Smite: Set On Fire', 'Set this player on fire for eight seconds.', function()
                send('smite', player, { kind = 'fire' })
            end),
            row('player.smite', '~r~Smite: Chicken', 'Turn this player into a hen for twenty seconds. Their own look comes back afterwards.', function()
                send('smite', player, { kind = 'chicken' })
            end),
            row('player.smite', '~r~Smite: Drunk', 'Make this player stumble with a blurred, swaying view for thirty seconds.', function()
                send('smite', player, { kind = 'drunk' })
            end),
            row('player.kick', '~r~Kick Player', 'Disconnect this player with a reason.', function()
                if isSelf(player) then Admin.notify('error', 'Pick another player to kick.'); return end
                local reason = VM.input('Kick reason', nil, 100)
                if not reason or reason == '' then Admin.notify('error', 'A kick needs a reason, so nothing was sent.'); return end
                if VM.denied('player.kick') then return end
                send('kick', player, { reason = 'Kicked by staff: ' .. reason })
            end),
            row('player.ban', '~r~Ban Player Temporarily', 'Ban this player for up to 30 days. You choose the reason and length next.', function()
                banPlayer(player, false)
            end, { key = 'tempban' }),
            -- vMenu asks "Are you sure?", then goes back to the list before asking for the reason.
            row('player.ban', '~r~Ban Player Permanently', 'Remove this player from the server for good. You confirm first, then enter the reason.', function()
                VM.back()
                banPlayer(player, true)
            end, { key = 'permban', confirm = true, icon = 'warning' }),
        }
    end,
})

-- ---------------------------------------------------------------------------
-- Banned Players

local bans = { status = 'idle', records = {}, generation = 0 }
local viewing -- id of the ban record whose detail menu is open

local function loadBans()
    if not VM.can('player.viewBans') or type(Admin.getBanList) ~= 'function' then return end
    bans.generation = bans.generation + 1
    local mine = bans.generation
    bans.status = 'loading'
    CreateThread(function()
        local records, offset = {}, 0
        for _ = 1, BAN_PAGES do
            local page = Admin.getBanList({ query = '', offset = offset, limit = BAN_PAGE })
            if mine ~= bans.generation then return end
            if type(page) ~= 'table' or page.ok == false then
                bans.status = 'error'
                VM.refresh()
                return
            end
            local list = type(page.records) == 'table' and page.records or {}
            for _, record in ipairs(list) do
                if type(record) == 'table' and record.id then records[#records + 1] = record end
            end
            if page.hasMore ~= true or #list == 0 then break end
            offset = offset + #list
        end
        bans.records, bans.status = records, 'ready'
        VM.refresh()
    end)
end

-- .NET's en-US DateTime.ToString(), in UTC (client Lua has no os.date).
local function formatDate(epoch, dateOnly)
    local seconds = math.floor(tonumber(epoch) or 0)
    local days = seconds // 86400
    local rest = dateOnly and 0 or seconds - days * 86400
    local z = days + 719468
    local era = (z >= 0 and z or z - 146096) // 146097
    local doe = z - era * 146097
    local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    local mp = (5 * doy + 2) // 153
    local day = doy - (153 * mp + 2) // 5 + 1
    local month = mp < 10 and mp + 3 or mp - 9
    local year = yoe + era * 400 + (month <= 2 and 1 or 0)
    local hour = rest // 3600
    local hour12 = hour % 12 == 0 and 12 or hour % 12
    return ('%d/%d/%d %d:%02d:%02d %s'):format(month, day, year, hour12, (rest % 3600) // 60, rest % 60, hour < 12 and 'AM' or 'PM')
end

local function bannedBy(record) return safeName(record.admin or record.adminName or 'Unknown') end
local function permanent(record) return not tonumber(record.expiresAt) or tonumber(record.expiresAt) <= 0 end

VM.define('banned_players', {
    subtitle = 'Banned Players Management',
    onOpen = loadBans,
    buttons = { { control = 22, label = 'Filter Options', run = function()
        if #bans.records < 2 then
            VM.notify('error', 'Filtering needs two or more ban records.')
            return
        end
        local input = VM.input('Name or ban ID to match (submit empty to show all)')
        if input == nil then return end
        VM.setFilter(input)
        VM.notify('info', input ~= '' and 'Showing matching bans.' or 'Showing all bans.')
    end } },
    build = function()
        if not VM.can('player.viewBans') then return {} end
        local rows = {}
        for _, record in ipairs(bans.records) do
            local name = safeName(record.playerName or 'Unknown player')
            local untilText = permanent(record) and 'Forever' or formatDate(record.expiresAt)
            rows[#rows + 1] = VM.submenu('banned_player', name,
                ('~y~%s~s~: banned by ~y~%s~s~ until ~y~%s~s~. Reason: ~y~%s~s~.'):format(name, bannedBy(record), untilText, safeName(record.reason)),
                { key = record.id, record = record }, { key = 'ban:' .. tostring(record.id), hideEmpty = false })
        end
        -- vMenu shows an empty menu; the engine would hide the Banned Players button, so keep one row.
        if #rows == 0 then
            local label = bans.status == 'error' and 'Ban list unavailable' or bans.status == 'ready' and 'No banned players' or 'Loading...'
            rows[1] = { key = 'bans:empty', label = label, enabled = false }
        end
        return rows
    end,
})

local function unban(record)
    if VM.denied('player.unban') or type(Admin.unbanPlayer) ~= 'function' then return end
    local result = Admin.unbanPlayer(record.id)
    if type(result) ~= 'table' or result.ok ~= true then
        Admin.notify('error', 'The ban could not be removed.')
        return
    end
    for index = #bans.records, 1, -1 do
        if bans.records[index].id == record.id then table.remove(bans.records, index) end
    end
    Admin.notify('success', ('Unbanned %s.'):format(record.playerName or record.id))
    if viewing == record.id then VM.back() end
end

VM.define('banned_player', {
    title = 'Banned Player',
    subtitle = function(args) return 'Ban Record: ~y~' .. safeName(args and args.record and args.record.playerName) end,
    onOpen = function(args) viewing = args and args.key end,
    -- vMenu re-requests the ban list whenever a record closes.
    onClose = function() viewing = nil; loadBans() end,
    build = function(args)
        local record = type(args) == 'table' and args.record
        if type(record) ~= 'table' or not VM.can('player.viewBans') then return {} end
        local canUnban = VM.can('player.unban')
        local name, by = safeName(record.playerName), bannedBy(record)
        local untilDate = permanent(record) and nil or formatDate(record.expiresAt, true)
        local identifiers = {}
        for index, id in ipairs(type(record.identifiers) == 'table' and record.identifiers or {}) do
            local colour = IDENTIFIER_COLOURS[(index - 1) % #IDENTIFIER_COLOURS + 1]
            -- Only admins who can unban see IPs, as in vMenu.
            local text = (tostring(id):sub(1, 3) == 'ip:' and not canUnban) and 'ip: (hidden)' or tostring(id):gsub(':', ': ')
            identifiers[#identifiers + 1] = colour .. safeName(text) .. ' '
        end
        local unbanRow = { key = 'unban', label = '~r~Unban', confirm = true,
            description = '~r~Unbanning is permanent and cannot be undone. You cannot ban this player again until they rejoin the server.~s~ Temporary bans lift on their own the next time the player joins after the ban has expired.',
            onSelect = function() unban(record) end }
        if not canUnban then
            unbanRow.enabled, unbanRow.confirm, unbanRow.onSelect, unbanRow.icon = false, nil, nil, 'lock'
            unbanRow.description = 'Your permissions let you view this ban record but not remove it.'
        end
        return {
            { key = 'name', label = 'Player Name', rightLabel = name, description = 'Name: ~y~' .. name },
            { key = 'by', label = 'Banned By', rightLabel = by, description = 'Issued by: ~y~' .. by },
            { key = 'until', label = 'Banned Until', rightLabel = untilDate or 'Forever',
              description = 'Ban expires: ' .. (untilDate or 'Forever') },
            { key = 'identifiers', label = 'Player Identifiers', description = table.concat(identifiers) },
            { key = 'reason', label = 'Banned For', description = 'Reason: ' .. safeName(record.reason) },
            unbanRow,
        }
    end,
})
