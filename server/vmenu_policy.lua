local Server, P = EsAdminServer, EsAdminVmenuPolicy
local known = {}
for _, ace in ipairs(EsAdminVmenuReference.permissions) do known[ace] = true end
local noPermissionModeDenied = {
    ['vMenu.Everything'] = true, ['vMenu.OnlinePlayers.All'] = true,
    ['vMenu.OnlinePlayers.Kick'] = true, ['vMenu.OnlinePlayers.Kill'] = true,
    ['vMenu.OnlinePlayers.PermBan'] = true, ['vMenu.OnlinePlayers.TempBan'] = true,
    ['vMenu.OnlinePlayers.Unban'] = true, ['vMenu.OnlinePlayers.Identifiers'] = true,
    ['vMenu.OnlinePlayers.ViewBannedPlayers'] = true,
}
function Server.vmenuAce(src, ace)
    if type(ace) ~= 'string' or ace:sub(1, 6) ~= 'vMenu.' then return false end
    local unrestricted = P.get('vmenu_use_permissions', true) == false
    if P.get('vmenu_menu_staff_only', false) and not unrestricted
        and not IsPlayerAceAllowed(src, 'vMenu.Staff') and not IsPlayerAceAllowed(src, 'vMenu.Everything') then return false end
    if unrestricted and known[ace] then return noPermissionModeDenied[ace] ~= true end
    if IsPlayerAceAllowed(src, 'vMenu.Everything') or IsPlayerAceAllowed(src, ace) then return true end
    local domain, name = ace:match('^vMenu%.([^.]+)%.([^.]+)$')
    -- vMenu's category All grants do not imply Menu access.
    return domain ~= nil and name ~= 'Menu' and name ~= 'All'
        and IsPlayerAceAllowed(src, 'vMenu.' .. domain .. '.All') or false
end
function Server.vmenuSnapshot(src)
    local snapshot = { aces = {}, cortex = {}, settings = P.settings() }
    for ace in pairs(known) do snapshot.aces[ace] = Server.vmenuAce(src, ace) end
    for _, action in ipairs(EsAdminActions.actions) do
        snapshot.cortex[action.id] = Server.hasCortexPermission(src, action.id) == true
    end
    return snapshot
end

local recentlyGranted, banPending = {}, {}
function Server.noteVmenuGrant(src, action)
    recentlyGranted[src] = recentlyGranted[src] or {}
    recentlyGranted[src][action] = GetGameTimer()
end
function Server.vmenuDenied(src, action)
    if not P.get('vmenu_auto_ban_cheaters', false) or not src or src <= 0 or banPending[src] then return end
    -- A permission lease can become stale between opening a control and sending
    -- its request. Never classify that normal revocation race as a forged event.
    local previous = recentlyGranted[src] and recentlyGranted[src][action]
    if previous and GetGameTimer() - previous < 45000 then return end
    if not Server.addBan or not GetPlayerName(src) then return end
    local reason = P.get('vmenu_auto_ban_cheaters_ban_message', 'Unauthorized administrative event.')
    local ban = Server.addBan(GetPlayerIdentifiers(src), reason, 'Cortex Admin', 0, GetPlayerName(src))
    if not ban then return end
    banPending[src] = true
    if P.get('vmenu_log_ban_actions', true) then print(('[cortex-admin] Automatic ban %s: player %d attempted %s without permission.'):format(ban.id or 'unknown', src, action)) end
    DropPlayer(src, reason)
end
function Server.vmenuBanMessage(reason)
    local extra = P.get('vmenu_default_ban_message_information', '')
    return extra ~= '' and (reason .. '\n' .. extra) or reason
end
AddEventHandler('playerDropped', function() recentlyGranted[source], banPending[source] = nil, nil end)
