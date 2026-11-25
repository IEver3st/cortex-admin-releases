-- vMenu mode: vMenu's menu tree with MenuAPI's exact controls, drawn by the
-- Cortex NUI (web-admin/src/vmenu). No NUI focus: the game keeps running under
-- the menu, as it does under vMenu. Menus are declared in client/vmenu_mode_*.lua
-- through VM.define and run the existing Cortex actions; no second action engine.
--
-- Controls follow MenuAPI (TomGrobbe/MenuAPI MenuController.cs / Menu.cs):
--   up/down     FrontendUp/Down or mouse wheel, held: 200ms, then 150/100/50/25ms
--   left/right  PhoneLeft/Right; lists and sliders step, a plain row goes back
--               (left) or selects (right), checkboxes toggle (right)
--   select      FrontendAccept (Enter / pad A) or left mouse, on release
--   back        PhoneCancel (Backspace / Esc / right mouse / pad B), on release
local Admin = EsAdmin
local VM = {}
Admin.VmenuMode = VM

local MAX_ITEMS = 10
local SOUNDSET = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
local REFRESH_MS = 250
local CONFIRM_MS = 5000

-- docs.fivem.net/docs/game-references/controls
local PHONE, PHONE_DOWN, PHONE_LEFT, PHONE_RIGHT, PHONE_CANCEL = 27, 173, 174, 175, 177
local SCROLL_FORWARD, SCROLL_BACKWARD = 180, 181
local FRONTEND_UP, FRONTEND_DOWN, FRONTEND_ACCEPT, FRONTEND_PAUSE_ALTERNATE = 188, 187, 201, 200
local MOUSE_SELECT, SELECT_WEAPON = 106, 37
local WEAPON_SCROLL = { 14, 15, 16, 17 }
local ATTACK_CONTROLS = { 24, 257, 263, 264, 142, 141, 140, 69, 70, 114, 92, 25, 68 }
local RADIO_CONTROLS = { 333, 332, 81, 85, 82 }

local definitions = {}
VM._definitions = definitions
local memory = {} -- per menu instance: highlighted index, scroll offset, list positions
local stack = {}
local items = {}
local active, hidden = false, false
local held -- { dir, time, times, delay } while a direction is being held
local buttonsBlockedUntil = 0
local pendingBack = false
local lastPayload
local countCache, counting = {}, {}
local lastBuild = 0
local generation = 0
local buildingId
local menuDomains = {
    online_players = 'OnlinePlayers', player_options = 'PlayerOptions',
    vehicle_options = 'VehicleOptions', vehicle_spawner = 'VehicleSpawner',
    saved_vehicles = 'SavedVehicles', personal_vehicle = 'PersonalVehicle',
    player_appearance = 'PlayerAppearance', mp_ped = 'PlayerAppearance',
    weapon_options = 'WeaponOptions', weapon_loadouts = 'WeaponLoadouts',
    time_options = 'TimeOptions', weather_options = 'WeatherOptions', voice_chat = 'VoiceChat',
}

local function sound(name) PlaySoundFrontend(-1, name, SOUNDSET, false) end

local function instanceKey(frame)
    local args = frame.args
    local key = type(args) == 'table' and (args.key or args.id) or args
    return frame.id .. '|' .. tostring(key or '')
end

local function state(frame)
    local key = instanceKey(frame)
    memory[key] = memory[key] or { index = 1, offset = 0, lists = {}, sliders = {}, confirm = {} }
    return memory[key]
end

local function itemKey(item) return tostring(item.key or item.label) end

-- Builders may return nil holes (an item the player cannot use), so compact by key.
local function compact(list)
    if type(list) ~= 'table' then return {} end
    local keys = {}
    for key in pairs(list) do if type(key) == 'number' then keys[#keys + 1] = key end end
    table.sort(keys)
    local output = {}
    for i = 1, #keys do
        local item = list[keys[i]]
        if type(item) == 'table' and item.visible ~= false then output[#output + 1] = item end
    end
    return output
end

local function rawBuild(id, args)
    local definition = definitions[id]
    if not definition then return {} end
    local domain = menuDomains[id]
    if domain and Admin.vmenuMenuAllowed and not Admin.vmenuMenuAllowed(domain) then return {} end
    local previous = buildingId
    buildingId = id
    local ok, result = pcall(definition.build, args, VM)
    buildingId = previous
    if not ok then
        print(('[cortex-admin] vMenu mode menu %s failed: %s'):format(id, tostring(result)))
        return {}
    end
    return compact(result)
end

-- vMenu adds a submenu button only when the player may use something inside it.
-- That only needs one usable row, so the walk takes plain rows first and opens
-- child menus only when there are none. Counting every row recursively built
-- the whole tree (ped lists, weapon components, tattoos) each time the menu opened.
local anyCache = {}
local function visible(item)
    return not (item.submenu and item.hideEmpty ~= false and not VM.hasItems(item.submenu, item.args))
end

function VM.hasItems(id, args)
    -- Closed menus have no rebuild to clear the cache, so check fresh.
    if not active and next(counting) == nil then countCache, anyCache = {}, {} end
    local key = instanceKey({ id = id, args = args })
    if anyCache[key] ~= nil then return anyCache[key] end
    if counting[key] then return true end
    if definitions[id] and definitions[id].alwaysShow then anyCache[key] = true; return true end
    counting[key] = true
    local rows, found = rawBuild(id, args), false
    for _, item in ipairs(rows) do
        if not item.submenu or item.hideEmpty == false then found = true; break end
    end
    if not found then
        for _, item in ipairs(rows) do
            if visible(item) then found = true; break end
        end
    end
    counting[key] = nil
    anyCache[key] = found
    return found
end

function VM.count(id, args)
    if not active and next(counting) == nil then countCache, anyCache = {}, {} end
    local key = instanceKey({ id = id, args = args })
    if countCache[key] ~= nil then return countCache[key] end
    if counting[key] then return 1 end
    if definitions[id] and definitions[id].alwaysShow then countCache[key] = 1; return 1 end
    counting[key] = true
    local total = 0
    for _, item in ipairs(rawBuild(id, args)) do
        if visible(item) then total = total + 1 end
    end
    counting[key] = nil
    countCache[key] = total
    return total
end

local function plain(text) return tostring(text or ''):gsub('~[^~]*~', ''):lower() end

local function build(frame)
    local output = {}
    local filter = state(frame).filter
    for _, item in ipairs(rawBuild(frame.id, frame.args)) do
        if visible(item)
            and (not filter or plain(item.label):find(filter, 1, true) or plain(item.rightLabel):find(filter, 1, true)) then
            output[#output + 1] = item
        end
    end
    return output
end

local function current() return stack[#stack] end
-- The open menu's id and args, so late async results can tell whether their menu is still showing.
function VM.top() local frame = current(); return frame and frame.id, frame and frame.args end

local function clampView(menu, size)
    if size < 1 then menu.index, menu.offset = 1, 0; return end
    if menu.index > size then menu.index = size end
    if menu.index < 1 then menu.index = 1 end
    local maxOffset = math.max(size - MAX_ITEMS, 0)
    if menu.offset > maxOffset then menu.offset = maxOffset end
    if menu.index <= menu.offset then menu.offset = menu.index - 1 end
    if menu.index > menu.offset + MAX_ITEMS then menu.offset = menu.index - MAX_ITEMS end
end

local function listPosition(menu, item)
    local count = type(item.values) == 'table' and #item.values or 0
    if count == 0 then return 0 end
    local position = menu.lists[itemKey(item)] or item.index or 1
    position = ((math.floor(position) - 1) % count) + 1
    return position
end

local function sliderValue(menu, item)
    local value = menu.sliders[itemKey(item)] or item.value or item.min or 0
    return math.max(item.min or 0, math.min(item.max or 10, value))
end

local function resolve(value, ...)
    if type(value) == 'function' then return value(...) end
    return value
end

-- Which submenu buttons show depends on permissions and saved data, not on the
-- 250ms live refresh, so counts are kept until something that can change them happens.
local function invalidateCounts() countCache, anyCache = {}, {} end

local function rebuild()
    local frame = current()
    if not frame then items = {}; return end
    items = build(frame)
    clampView(state(frame), #items)
    lastBuild = GetGameTimer()
end

-- Extra per-menu keys (MenuAPI ButtonPressHandlers + InstructionalButtons).
local BUTTON_KEYS = { [22] = { 'Space', 'X' }, [214] = { 'Delete', 'Delete' } }
local function menuButtons(frame)
    local definition = frame and definitions[frame.id]
    local buttons = definition and definition.buttons
    if type(buttons) == 'function' then buttons = buttons(frame.args) end
    return type(buttons) == 'table' and buttons or nil
end

-- Menu keys on cortex-lib's help strip (bottom right, clear of the minimap):
-- Select, Back, then the open menu's own keys.
local function plainLabel(text) return (tostring(text or ''):gsub('~[^~]*~', '')) end
local function helpItems(frame)
    local pad = not IsUsingKeyboard(2)
    local hints = {
        { label = 'Select', value = pad and 'A' or 'Enter' },
        { label = 'Back', value = pad and 'B' or 'Backspace' },
    }
    for _, button in ipairs(menuButtons(frame) or {}) do
        local names = BUTTON_KEYS[button.control] or { tostring(button.control), tostring(button.control) }
        hints[#hints + 1] = { label = plainLabel(button.label), value = pad and names[2] or names[1] }
    end
    return hints
end

local function setHelp(items)
    if Admin.setHelpLayer then Admin.setHelpLayer('vmenu', items) end
end

local function sendPayload()
    local frame = current()
    local payload
    if not active or not frame then
        payload = { open = false }
    else
        local menu = state(frame)
        local definition = definitions[frame.id] or {}
        local rows = {}
        for index = menu.offset + 1, math.min(menu.offset + MAX_ITEMS, #items) do
            local item = items[index]
            local row = {
                label = tostring(item.label or ''),
                right = item.rightLabel,
                kind = item.kind or 'button',
                enabled = item.enabled ~= false,
                selected = index == menu.index,
                icon = item.icon,
            }
            if (menu.confirm[itemKey(item)] or 0) > GetGameTimer() then row.right = '~r~Are you sure?' end
            if row.kind == 'checkbox' then
                row.checked = item.checked == true
            elseif row.kind == 'list' then
                local position = listPosition(menu, item)
                local value = position > 0 and item.values[position]
                row.value = value ~= nil and tostring(type(value) == 'table' and (value.label or value.value) or value) or nil
                row.arrows = not (item.hideArrows and index ~= menu.index)
            elseif row.kind == 'slider' then
                row.min, row.max, row.value = item.min or 0, item.max or 10, sliderValue(menu, item)
                row.leftText, row.rightText = item.leftText, item.rightText
            end
            rows[#rows + 1] = row
        end
        local selected = items[menu.index]
        if Admin.onVmenuSelection then Admin.onVmenuSelection(frame.id, frame.args, selected) end
        local counter
        local preText = resolve(definition.counterPreText, frame.args)
        if preText or #items > MAX_ITEMS then counter = ('%s%d / %d'):format(preText or '', math.min(menu.index, #items), #items) end
        local safeZone = GetSafeZoneSize()
        payload = {
            open = true,
            visible = not hidden,
            align = Admin.state.settings.menuPosition == 'right' and 'right' or 'left',
            safeZone = safeZone,
            title = resolve(definition.title, frame.args) or GetPlayerName(PlayerId()),
            subtitle = resolve(definition.subtitle, frame.args) or '',
            counter = counter,
            items = rows,
            more = #items > MAX_ITEMS,
            description = selected and resolve(selected.description, selected) or nil,
            stats = selected and resolve(selected.stats, selected) or resolve(definition.stats, frame.args),
            pad = not IsUsingKeyboard(2),
        }
    end
    setHelp(payload.open and payload.visible and helpItems(frame) or nil)
    local encoded = json.encode(payload)
    if encoded == lastPayload then return end
    lastPayload = encoded
    SendNUIMessage({ action = 'cortex-admin:vmenu', data = payload })
end

function VM.refresh()
    if not active then return end
    rebuild()
    sendPayload()
end

-- ---------------------------------------------------------------------------
-- Activation: handlers may yield (keyboard input, server replies), so they run
-- on their own thread and the menu refreshes when they finish.
local function run(handler, ...)
    if type(handler) ~= 'function' then return end
    local args = table.pack(...)
    CreateThread(function()
        local ok, reason = pcall(handler, table.unpack(args, 1, args.n))
        if not ok then
            print(('[cortex-admin] vMenu mode item failed: %s'):format(tostring(reason)))
            Admin.notify('error', 'That option failed. Check the client console.')
        end
        invalidateCounts()
        VM.refresh()
    end)
end

function VM.open(id, args)
    if not definitions[id] then return false end
    stack[#stack + 1] = { id = id, args = args }
    local definition = definitions[id]
    if definition.onOpen then pcall(definition.onOpen, args, VM) end
    invalidateCounts()
    VM.refresh()
    return true
end

local function closeAll(silent)
    if not active then return end
    for i = #stack, 1, -1 do
        local definition = definitions[stack[i].id]
        if definition and definition.onClose then pcall(definition.onClose, stack[i].args, VM) end
    end
    for i = 1, #stack do state(stack[i]).filter = nil end
    active, hidden, held, pendingBack = false, false, nil, false
    stack, items = {}, {}
    generation = generation + 1
    if Admin.onVmenuSelection then Admin.onVmenuSelection(nil) end
    if not silent then sendPayload() else
        lastPayload = nil
        setHelp(nil)
        SendNUIMessage({ action = 'cortex-admin:vmenu', data = { open = false } })
    end
end

function VM.back()
    sound('BACK')
    local frame = table.remove(stack)
    if frame then
        state(frame).filter = nil -- vMenu resets a menu's filter when it closes
        local definition = definitions[frame.id]
        if definition and definition.onClose then pcall(definition.onClose, frame.args, VM) end
    end
    if #stack == 0 then closeAll(); return end
    invalidateCounts()
    VM.refresh()
end

function VM.close() closeAll() end

-- MenuAPI FilterMenuItems / ResetFilter on the open menu; matches label or right label.
function VM.setFilter(text)
    local frame = current()
    if not frame then return end
    local menu = state(frame)
    menu.filter = type(text) == 'string' and text ~= '' and text:lower() or nil
    menu.index, menu.offset = 1, 0
    VM.refresh()
end

-- The Jump-key "Filter List" button vMenu puts on long lists.
function VM.filterButton(prompt, label)
    return { control = 22, label = label or 'Filter List', run = function()
        local input = VM.input(prompt or 'Filter by name, leave this empty to reset the filter')
        if input == nil then return end
        VM.setFilter(input)
        Admin.notify('info', input ~= '' and 'Showing matching items only.' or 'Showing all items.')
    end }
end

local function selectItem(index)
    local frame = current()
    local item = items[index]
    if not frame or not item then return end
    if item.enabled == false then sound('ERROR'); return end
    sound('SELECT')
    local menu = state(frame)
    if item.confirm then
        local key, now = itemKey(item), GetGameTimer()
        if (menu.confirm[key] or 0) < now then
            menu.confirm[key] = now + CONFIRM_MS
            sendPayload()
            return
        end
        menu.confirm[key] = nil
    end
    if item.kind == 'checkbox' then
        item.checked = not item.checked
        sendPayload()
        run(item.onCheck, item.checked, item)
    elseif item.kind == 'list' then
        local position = listPosition(menu, item)
        run(item.onSelect, position, item.values[position], item)
    elseif item.kind == 'slider' then
        run(item.onSelect, sliderValue(menu, item), item)
    else
        if item.submenu and item.onSelect then
            local revision = generation
            run(function()
                if item.onSelect(item) ~= false and active and generation == revision and current() == frame then VM.open(item.submenu, item.args) end
            end)
        else
            if item.onSelect then run(item.onSelect, item) end
            if item.submenu then VM.open(item.submenu, item.args) end
        end
    end
end

local function goUp()
    local frame = current(); if not frame or #items < 2 then return end
    local menu = state(frame)
    menu.index = menu.index == 1 and #items or menu.index - 1
    if menu.index <= menu.offset or menu.index > menu.offset + MAX_ITEMS then
        menu.offset = menu.offset - 1
        if menu.offset < 0 then menu.offset = math.max(#items - MAX_ITEMS, 0) end
    end
    sound('NAV_UP_DOWN')
    sendPayload()
end

local function goDown()
    local frame = current(); if not frame or #items < 2 then return end
    local menu = state(frame)
    menu.index = menu.index >= #items and 1 or menu.index + 1
    if menu.index <= menu.offset or menu.index > menu.offset + MAX_ITEMS then
        menu.offset = menu.offset + 1
        if menu.index == 1 then menu.offset = 0 end
    end
    sound('NAV_UP_DOWN')
    sendPayload()
end

local function step(item, menu, delta)
    if item.kind == 'list' then
        local count = type(item.values) == 'table' and #item.values or 0
        if count == 0 then return end
        local position = listPosition(menu, item)
        local nextPosition = ((position - 1 + delta) % count) + 1
        menu.lists[itemKey(item)] = nextPosition
        sound('NAV_LEFT_RIGHT')
        sendPayload()
        run(item.onChange, nextPosition, item.values[nextPosition], position, item)
    else
        local value = sliderValue(menu, item)
        local nextValue = value + delta
        if nextValue < (item.min or 0) or nextValue > (item.max or 10) then sound('ERROR'); return end
        menu.sliders[itemKey(item)] = nextValue
        sound('NAV_LEFT_RIGHT')
        sendPayload()
        run(item.onChange, nextValue, value, item)
    end
end

local function goLeft()
    local frame = current(); if not frame then return end
    local menu = state(frame)
    local item = items[menu.index]
    if not item then return end
    if item.kind == 'list' or item.kind == 'slider' then step(item, menu, -1) else VM.back() end
end

local function goRight()
    local frame = current(); if not frame then return end
    local menu = state(frame)
    local item = items[menu.index]
    if not item then return end
    if item.kind == 'list' or item.kind == 'slider' then step(item, menu, 1) else selectItem(menu.index) end
end

local function pressed(control) return IsControlPressed(0, control) or IsDisabledControlPressed(0, control) end
local function justPressed(control) return IsControlJustPressed(0, control) or IsDisabledControlJustPressed(0, control) end
local function justReleased(control) return IsControlJustReleased(0, control) or IsDisabledControlJustReleased(0, control) end

-- Holding TAB and scrolling picks a weapon on foot; the menu leaves that alone.
local function weaponWheelScroll(ped)
    return not IsPedInAnyVehicle(ped, false) and IsControlPressed(0, SELECT_WEAPON)
        and (IsControlPressed(0, 16) or IsControlPressed(0, 17))
end
local function upPressed(ped) return not weaponWheelScroll(ped) and (pressed(FRONTEND_UP) or pressed(SCROLL_BACKWARD)) end
local function downPressed(ped) return not weaponWheelScroll(ped) and (pressed(FRONTEND_DOWN) or pressed(SCROLL_FORWARD)) end

local HELD = {
    up = { test = upPressed, run = goUp },
    down = { test = downPressed, run = goDown },
    left = { test = function() return pressed(PHONE_LEFT) end, run = goLeft },
    right = { test = function() return pressed(PHONE_RIGHT) end, run = goRight },
}

local function startHeld(dir) held = { dir = dir, time = GetGameTimer(), times = 0, delay = 200 } end

local function processDirections(ped, now)
    if held then
        if not HELD[held.dir].test(ped) then held = nil; return end
        if now - held.time > held.delay then
            held.times = held.times + 1
            if held.times > 60 then held.delay = 25 elseif held.times > 25 then held.delay = 50
            elseif held.times > 5 then held.delay = 100 elseif held.times > 2 then held.delay = 150 end
            HELD[held.dir].run()
            held.time = now
        end
        return
    end
    if #items < 1 then return end
    if upPressed(ped) then goUp(); startHeld('up')
    elseif downPressed(ped) then goDown(); startHeld('down')
    else
        local item = items[state(current()).index]
        local enabled = item and item.enabled ~= false
        if enabled and justPressed(PHONE_LEFT) then goLeft(); if active then startHeld('left') end
        elseif enabled and justPressed(PHONE_RIGHT) then goRight(); if active then startHeld('right') end end
    end
end

-- A release only counts when its press was seen in this same menu. Otherwise a
-- release event left over from the step that opened the menu fired the button
-- (Server Management opened its filter prompt on entry).
local armed = {}
local function processButtons()
    local frame = current()
    local buttons = menuButtons(frame)
    if not buttons then return end
    for _, button in ipairs(buttons) do
        local control = button.control
        if justPressed(control) then armed[control] = frame end
        local hit
        if button.on == 'press' then
            hit = justPressed(control)
        elseif justReleased(control) then
            hit = armed[control] == frame
            armed[control] = nil
        end
        if hit then run(button.run, frame.args, items[state(frame).index], VM) end
    end
end

local function processMain()
    if pendingBack then pendingBack = false; VM.back(); return end
    processButtons()
    if justReleased(FRONTEND_ACCEPT) or justReleased(MOUSE_SELECT) then
        if #items > 0 then selectItem(state(current()).index) end
    elseif IsDisabledControlJustReleased(0, PHONE_CANCEL) then
        -- Next frame, so the cinematic camera button is not re-enabled before the close.
        pendingBack = true
    end
end

local function disableControls(ped, usingPad)
    if usingPad then
        DisableControlAction(0, 20, true)
        if IsPedInAnyVehicle(ped, false) then
            DisableControlAction(0, 74, true); DisableControlAction(0, 73, true)
            DisableControlAction(0, 351, true); DisableControlAction(0, 357, true)
        end
        local item = items[current() and state(current()).index or 0]
        if item and (item.kind == 'list' or item.kind == 'slider') then DisableControlAction(0, SELECT_WEAPON, true) end
    else
        DisableControlAction(0, FRONTEND_PAUSE_ALTERNATE, true) -- Esc goes back; P still pauses.
        if not IsControlPressed(0, SELECT_WEAPON) then
            for i = 1, #WEAPON_SCROLL do DisableControlAction(0, WEAPON_SCROLL[i], true) end
        end
    end
    for i = 1, #RADIO_CONTROLS do DisableControlAction(0, RADIO_CONTROLS[i], true) end
    DisableControlAction(0, PHONE, true); DisableControlAction(0, PHONE_CANCEL, true)
    DisableControlAction(0, PHONE_DOWN, true); DisableControlAction(0, PHONE_LEFT, true); DisableControlAction(0, PHONE_RIGHT, true)
    for i = 1, #ATTACK_CONTROLS do DisableControlAction(0, ATTACK_CONTROLS[i], true) end
    if IsPedInAnyVehicle(ped, false) then
        DisableControlAction(0, 99, true); DisableControlAction(0, 100, true); DisableControlAction(0, 80, true)
    end
end

local function isStatic()
    local frame = current()
    local definition = frame and definitions[frame.id]
    return definition ~= nil and definition.static == true
end

local function startLoop()
    local myGeneration = generation
    CreateThread(function()
        while active and generation == myGeneration do
            local now = GetGameTimer()
            local ped = PlayerPedId()
            if IsEntityDead(ped) then closeAll(); break end
            local shouldHide = IsPauseMenuActive() or not IsScreenFadedIn() or IsPlayerSwitchInProgress()
            if shouldHide ~= hidden then hidden = shouldHide; sendPayload() end
            if not hidden then
                local usingPad = not IsUsingKeyboard(2)
                disableControls(ped, usingPad)
                if UpdateOnscreenKeyboard() == 0 then
                    buttonsBlockedUntil = now + 300
                    held = nil
                elseif now >= buttonsBlockedUntil then
                    processMain()
                    if active and generation == myGeneration then processDirections(ped, now) end
                end
                if active and now - lastBuild >= REFRESH_MS and not isStatic() then VM.refresh() end
            end
            Wait(0)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Public entry points.

function Admin.isVmenuModeOpen() return active end

function Admin.closeVmenuMode()
    if active then closeAll(true) end
end

function Admin.openVmenuMode()
    if active then return true end
    if not definitions.main then return false end
    if IsEntityDead(PlayerPedId()) then return false end
    if Admin.state.open then Admin.setOpen(false) end
    if Admin.closeClassicMenu then Admin.closeClassicMenu() end
    if Admin.closeVehicleCamera then Admin.closeVehicleCamera() end
    if Admin.closeShowcaseCamera then Admin.closeShowcaseCamera() end
    active, hidden, held, pendingBack = true, false, nil, false
    generation = generation + 1
    buttonsBlockedUntil = 0
    lastPayload = nil
    stack = {}
    VM.open('main')
    startLoop()
    TriggerServerEvent('cortex-admin:server:requestPermissions')
    return true
end

function Admin.toggleVmenuMode()
    if active then closeAll() else Admin.openVmenuMode() end
end

-- Permissions or settings changed elsewhere: rebuild what is on screen.
-- keepCounts: the permission lease was renewed unchanged, so which submenus
-- are usable has not changed either.
function Admin.refreshVmenuMode(keepCounts)
    if not active then return end
    if not keepCounts then invalidateCounts() end
    VM.refresh()
end

-- vMenu binds its toggle to the pad's start button too. A separate command
-- keeps Panel and Classic players' start button untouched.
RegisterCommand('cortex_admin_vmenu_pad', function()
    if Admin.state.settings.interfaceStyle ~= 'vmenu' or Admin.state.settings.disableControllerSupport == true then return end
    if not Admin.hasMenuAccess() then return end
    Admin.toggleVmenuMode()
end, false)
CreateThread(function()
    -- Registered once vMenu mode is chosen, so other players never see it in their bindings.
    while true do
        -- The vMenu stand-in already maps the start button to the menu.
        if Admin.state.settings and Admin.state.settings.interfaceStyle == 'vmenu' and Admin.hasMenuAccess()
            and Admin.vmenuState() ~= 'compat' then
            RegisterKeyMapping('cortex_admin_vmenu_pad', 'Cortex Admin: vMenu mode (controller)', 'pad_digitalbuttonany', 'start_index')
            return
        end
        Wait(5000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Admin.closeVmenuMode() end
end)

-- ---------------------------------------------------------------------------
-- Menu declarations and item helpers used by client/vmenu_mode_*.lua.

-- Row icons (MenuAPI's left icons): 'lock', 'warning', 'tick', 'star', 'gun', 'ammo'.
-- definition = { subtitle = string|fn(args), title = string|fn(args)|nil (player name),
--   counterPreText = string|fn(args)|nil, build = fn(args, VM) -> items,
--   alwaysShow = true keeps its submenu button even when it builds no rows,
--   static = true skips the 250 ms live rebuild (rows change only on events, which call VM.refresh),
--   buttons = { { control, label, on = 'release'|'press', run = fn(args, selectedItem, VM) } } or fn(args),
--   onOpen/onClose = fn(args, VM) }
function VM.define(id, definition)
    assert(type(definition) == 'table' and type(definition.build) == 'function', 'vMenu mode menu needs build()')
    definitions[id] = definition
end

function VM.defined(id) return definitions[id] ~= nil end

local descriptorCache
function VM.descriptor(actionId)
    if not descriptorCache or descriptorCache.count ~= #EsAdminActions.actions then
        descriptorCache = { count = #EsAdminActions.actions, map = {} }
        for _, action in ipairs(EsAdminActions.actions) do descriptorCache.map[action.id] = action end
    end
    return descriptorCache.map[actionId]
end

function VM.can(actionId)
    if Admin.state.allowed[actionId] ~= true then return false end
    local action = VM.descriptor(actionId)
    if action and action.framework == 'qbx' and (not Config.HasQBX or GetResourceState('qbx_core') ~= 'started') then return false end
    return true
end

function VM.ace(ace, action)
    if Admin.vmenuAce then return Admin.vmenuAce(ace, action) end
    return action ~= nil and VM.can(action)
end

function VM.modelAccess(kind, model, action)
    if not Admin.vmenuModelAccess then return true end
    local frame = stack[#stack]
    return Admin.vmenuModelAccess(kind, model, action, active and frame and frame.id == buildingId)
end

function VM.modelRow(row, kind, model, action)
    if not row or row.enabled == false then return row end
    local copy = {}
    for key, value in pairs(row) do copy[key] = value end
    row = copy
    local verdict = VM.modelAccess(kind, model, action)
    if verdict ~= true then
        row.enabled, row.icon = false, 'lock'
        row.description = verdict == false and 'This model is restricted by the server.' or 'Checking model permissions.'
    end
    return row
end

function VM.canAny(ids)
    for i = 1, #ids do if VM.can(ids[i]) then return true end end
    return false
end

function VM.isOn(actionId)
    local key = actionId:match('^options%.(.+)$')
    if key and Admin.state.settings[key] ~= nil then return Admin.state.settings[key] == true end
    return Admin.state.toggles[actionId] == true
end

local function denied(actionId)
    if VM.can(actionId) then return false end
    Admin.notify('error', 'You are not allowed to use this option.')
    return true
end
VM.denied = denied

-- vMenu's GetUserInput: the native keyboard, titled "<title>: (MAX n Characters)".
function VM.input(title, default, maxLength)
    maxLength = math.floor(tonumber(maxLength) or 30)
    AddTextEntry('CORTEX_ADMIN_WINDOW_TITLE', ('%s:\t(MAX %d Characters)'):format(title or 'Enter', maxLength))
    DisplayOnscreenKeyboard(1, 'CORTEX_ADMIN_WINDOW_TITLE', '', default ~= nil and tostring(default) or '', '', '', '', maxLength)
    Wait(0)
    while true do
        local status = UpdateOnscreenKeyboard()
        if status == 1 then return GetOnscreenKeyboardResult() end
        if status == 2 or status == 3 then return nil end
        Wait(0)
    end
end

function VM.notify(kind, message) Admin.notify(kind, message) end

local function promptPayload(action)
    local fields = action.prompt and action.prompt.fields
    if type(fields) ~= 'table' then return {} end
    local payload = {}
    for _, field in ipairs(fields) do
        local value = VM.input(field.label or field.name, field.default, field.maxLength or 60)
        if value == nil then return nil end
        payload[field.name] = value
    end
    return payload
end

-- Run an action: prompts ask for each field through the keyboard unless data is given.
function VM.execute(actionId, data)
    if denied(actionId) then return false end
    local action = VM.descriptor(actionId)
    if data == nil and action and action.type == 'prompt' then
        data = promptPayload(action)
        if data == nil then return false end
    end
    return Admin.executeAction(actionId, data or {})
end

-- Checkbox bound to a Cortex toggle (or an options.* setting).
function VM.toggle(actionId, label, description, extra)
    if not VM.can(actionId) then return nil end
    local action = VM.descriptor(actionId) or {}
    local item = extra or {}
    item.kind = 'checkbox'
    item.key = item.key or actionId
    item.label = label or action.label or actionId
    item.description = description or action.description
    item.checked = VM.isOn(actionId)
    item.onCheck = item.onCheck or function(checked)
        if denied(actionId) then return end
        Admin.toggleAction(actionId, checked)
    end
    return item
end

-- Button running a Cortex action.
function VM.action(actionId, label, description, data, extra)
    if not VM.can(actionId) then return nil end
    local action = VM.descriptor(actionId) or {}
    local item = extra or {}
    item.key = item.key or actionId
    item.label = label or action.label or actionId
    item.description = description or action.description
    item.confirm = item.confirm == nil and action.requiresConfirm == true or item.confirm
    item.onSelect = item.onSelect or function()
        VM.execute(actionId, type(data) == 'function' and data() or data)
    end
    return item
end

-- List bound to a Cortex select action. Applies on Enter unless extra.apply == 'change'.
function VM.select(actionId, label, description, extra)
    if not VM.can(actionId) then return nil end
    local action = VM.descriptor(actionId) or {}
    local item = extra or {}
    local source = item.values or action.values or {}
    local values, raw = {}, {}
    for i, value in ipairs(source) do
        values[i] = type(value) == 'table' and tostring(value.label or value.value) or tostring(value)
        if type(value) == 'table' then raw[i] = value.value else raw[i] = value end
    end
    item.kind = 'list'
    item.key = item.key or actionId
    item.label = label or action.label or actionId
    item.description = description or action.description
    item.values = values
    local function apply(position)
        if denied(actionId) then return end
        Admin.selectAction(actionId, raw[position])
    end
    if item.apply == 'change' then item.onChange = item.onChange or function(position) apply(position) end end
    item.onSelect = item.onSelect or function(position) apply(position) end
    return item
end

function VM.submenu(menuId, label, description, args, extra)
    local item = extra or {}
    item.key = item.key or (menuId .. ':' .. tostring(label))
    item.label = label
    item.description = description
    item.rightLabel = item.rightLabel == nil and '→→→' or item.rightLabel
    item.submenu = menuId
    item.args = args
    return item
end

function VM.button(label, description, onSelect, extra)
    local item = extra or {}
    item.label, item.description, item.onSelect = label, description, onSelect
    return item
end

-- Hand a workflow vMenu builds into its own submenu to the Cortex workspace that owns it.
function VM.workspace(tab, search)
    Admin.closeVmenuMode()
    Admin.setOpen(true)
    SendNUIMessage({ action = 'cortex-admin:workspace', tab = tab or 'all', search = search or '' })
end
