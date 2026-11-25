-- Players console: a full-screen page for acting on online players. Like
-- cortex-lib's settings page it owns NUI focus, blurs the game natively and
-- hides the HUD while open. The roster refreshes once a second, only while open.
local Admin = EsAdmin
local state = Admin.state
local open = false
local FADE_MS = 160.0
-- A second engine effect, so graphics packs that neuter the screen blur keep one.
local POSTFX = 'MenuMGSelectionIn'
local ROSTER_MS = 1000

-- Actions the console offers; any one of them lets an admin open it.
local CONSOLE_ACTIONS = {
    'player.goto', 'player.bring', 'player.sitInVehicle', 'player.waypoint', 'player.spectate',
    'player.freezeTarget', 'player.reviveTarget', 'player.kill', 'player.orbitalStrike', 'player.smite', 'player.message', 'player.identifiers',
    'player.kick', 'player.ban',
}

local function send(data) SendNUIMessage({ action = 'cortex-admin:players', data = data }) end
Admin.isPlayersOpen = function() return open end
Admin.sendPlayers = function(data) if open then send(data) end end

local function permitted()
    for _, id in ipairs(CONSOLE_ACTIONS) do
        if state.allowed[id] == true then return true end
    end
    if QboxAdmin and QboxAdmin.capabilities().hasQBX then
        for id, action in pairs(QboxAdmin.actions) do
            if not action.selfOnly and state.allowed[id] == true and QboxAdmin.available(action) then return true end
        end
    end
    return false
end

local function allowedMap()
    local allowed = {}
    for _, id in ipairs(CONSOLE_ACTIONS) do allowed[id] = state.allowed[id] == true end
    return allowed
end

-- Qbox character tools come from the same descriptors as the Qbox tab, so a
-- new tool appears here without a second definition.
local function characterTools()
    local tools = {}
    if not QboxAdmin or not QboxAdmin.capabilities().hasQBX then return tools end
    for id, action in pairs(QboxAdmin.actions) do
        if not action.selfOnly and QboxAdmin.available(action) and state.allowed[id] == true then
            local fields = {}
            for _, field in ipairs(action.fields or {}) do
                if field.name ~= 'target' then
                    fields[#fields + 1] = { name = field.name, label = field.label, catalog = field.catalog,
                        type = field.type, min = field.min, max = field.max }
                end
            end
            tools[#tools + 1] = { id = id, label = action.label, description = action.description,
                confirm = action.confirm == true, fields = fields }
        end
    end
    table.sort(tools, function(a, b) return a.id < b.id end)
    return tools
end

local labels = {}
local function vehicleLabel(model)
    if type(model) ~= 'number' then return nil end
    if labels[model] then return labels[model] end
    local name = GetDisplayNameFromVehicleModel(model)
    local label = name and GetLabelText(name)
    if not label or label == 'NULL' then label = name and name ~= 'CARNOTFOUND' and name or 'Vehicle' end
    labels[model] = label
    return label
end

local scene = { blur = false, postfx = false }
local function setScene(active)
    if active then
        TriggerScreenblurFadeIn(FADE_MS); scene.blur = true
        AnimpostfxPlay(POSTFX, 0, true); scene.postfx = true
        return
    end
    if scene.blur then TriggerScreenblurFadeOut(FADE_MS) end
    if scene.postfx and AnimpostfxIsRunning(POSTFX) then AnimpostfxStop(POSTFX) end
    scene.blur, scene.postfx = false, false
end

local function close()
    if not open then return end
    open = false
    Admin.syncHudVisibility()
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    setScene(false)
    send({ open = false })
end
Admin.closePlayers = close

local function openConsole(focusId)
    if open then
        if focusId then send({ focus = focusId }) end
        return true
    end
    if not permitted() then
        Admin.notify('error', 'You do not have access to player tools.')
        return false
    end
    if state.open then Admin.setOpen(false) end
    open = true
    Admin.syncHudVisibility()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    setScene(true)
    send({ open = true, focus = focusId, allowed = allowedMap(), tools = characterTools(),
        self = GetPlayerServerId(PlayerId()) })
    TriggerServerEvent('cortex-admin:server:requestPlayerRoster')
    CreateThread(function()
        local nextRoster = GetGameTimer() + ROSTER_MS
        while open do
            HideHudAndRadarThisFrame()
            -- Escape belongs to the page: it must not open the pause menu.
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 199, true)
            if GetGameTimer() >= nextRoster then
                nextRoster = GetGameTimer() + ROSTER_MS
                TriggerServerEvent('cortex-admin:server:requestPlayerRoster')
            end
            Wait(0)
        end
    end)
    return true
end
Admin.openPlayers = openConsole

-- Results from player actions: inline in the console, a notification otherwise.
Admin.playerResult = function(requestId, ok, message)
    local text = type(message) == 'string' and message:sub(1, 200) or (ok and 'Done.' or 'That did not work.')
    if open and type(requestId) == 'string' then
        send({ result = { id = requestId:sub(1, 40), ok = ok == true, message = text } })
    else
        Admin.notify(ok and 'success' or 'error', text)
    end
end
RegisterNetEvent('cortex-admin:client:playerResult', function(requestId, ok, message)
    Admin.playerResult(requestId, ok, message)
end)

RegisterNetEvent('cortex-admin:client:playerRoster', function(roster, withCharacter, capacity)
    if not open or type(roster) ~= 'table' then return end
    for _, entry in ipairs(roster) do
        if type(entry) == 'table' and type(entry.vehicle) == 'table' then
            entry.vehicle.label = vehicleLabel(entry.vehicle.model)
            entry.vehicle.model = nil
        end
    end
    send({ roster = roster, character = withCharacter == true, capacity = capacity })
end)

RegisterNUICallback('cortex-admin:players', function(data, cb)
    local op = type(data) == 'table' and data.op or nil
    if op == 'close' then close(); cb({ ok = true }); return end
    if op == 'open' then cb({ ok = openConsole(tonumber(data.target)) }); return end
    if op == 'menu' then close(); Admin.setOpen(true); cb({ ok = true }); return end
    if op == 'refresh' and open then TriggerServerEvent('cortex-admin:server:requestPlayerRoster'); cb({ ok = true }); return end
    cb({ ok = false })
end)

RegisterCommand('players', function(_, args)
    openConsole(tonumber(args[1]))
end, false)

-- Permissions can change while the console is open.
AddEventHandler('cortex-admin:client:permissions', function()
    if open then
        if not permitted() then close(); return end
        send({ allowed = allowedMap(), tools = characterTools() })
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then
        SetNuiFocusKeepInput(false)
        SetNuiFocus(false, false)
        setScene(false)
    end
end)
