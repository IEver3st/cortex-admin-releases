-- Compact cortex-lib presentation of the existing permission-filtered actions.
-- Complex editors hand off to their existing workspace; no second action engine.
local Admin = EsAdmin
local MENU = 'cortex-admin:classic'
local active, tab, page = false, nil, 1
local selections = {}
local cursors = {} -- highlighted row per category page, so re-renders keep the player's place
local PAGE_SIZE = 48 -- cortex-lib permits 64 rows; reserve navigation rows.
local render

local function failMenu(reason)
    active = false
    lib.hideMenu(false)
    print(('[cortex-admin] Classic menu failed: %s'):format(tostring(reason)))
    Admin.notify('error', 'Classic could not open. Restart cortex-lib, then cortex-admin.')
    return false, reason
end

function Admin.closeClassicMenu()
    if not active then return end
    active = false
    lib.hideMenu(false)
end

local function workspace(target, query)
    Admin.closeClassicMenu()
    Admin.setOpen(true)
    SendNUIMessage({ action = 'cortex-admin:workspace', tab = target or 'all', search = query or '' })
end

local function permitted(action)
    if action.framework == 'qbx' and (not Config.HasQBX or GetResourceState('qbx_core') ~= 'started' or (action.qbox and not QboxAdmin.available(action))) then return false end
    return action.hidden ~= true and Admin.state.allowed[action.id] == true
end

render = function()
    if not active then return end
    local options, handlers = {}, {}
    local function row(label, description, handler, extra)
        local item = extra or {}
        item.label, item.description, item.close = label, description, false
        options[#options + 1], handlers[#handlers + 1] = item, handler
    end
    if not tab then
        for _, category in ipairs(EsAdminActions.tabs) do
            local found = false
            for _, action in ipairs(EsAdminActions.actions) do
                if permitted(action) and action.tab == category.id then found = true; break end
            end
            if found then
                row(category.label, 'Browse commands', function() tab, page = category.id, 1; render() end)
            end
        end
        row('Vehicle studio', 'Open the vehicle workshop', function() workspace('vehicle_custom') end)
        row('Character studio', 'Open the wardrobe and appearance editor', function() workspace('appearance') end)
        row('Command library', 'Search every available command', function() workspace('all') end)
        row('Use Panel interface', 'Remember this interface for next time', function()
            Admin.state.settings.interfaceStyle = 'panel'
            Admin.saveSettings()
            workspace('options')
        end)
    else
        row('Back', 'Return to categories', function() tab, page = nil, 1; render() end)
        local actions = {}
        for _, action in ipairs(EsAdminActions.actions) do
            if action.tab == tab and permitted(action) then actions[#actions + 1] = action end
        end
        page = math.min(page, math.max(1, math.ceil(#actions / PAGE_SIZE)))
        for index = (page - 1) * PAGE_SIZE + 1, math.min(page * PAGE_SIZE, #actions) do
            local action = actions[index]
            local extra = {}
            if action.type == 'toggle' then
                local key = action.id:match('^options%.(.+)$')
                extra.checked = key and Admin.state.settings[key] == true or Admin.state.toggles[action.id] == true
            elseif action.type == 'select' and type(action.values) == 'table' and #action.values > 0 and #action.values <= 64 then
                extra.values = {}
                for _, value in ipairs(action.values) do
                    extra.values[#extra.values + 1] = type(value) == 'table' and tostring(value.label or value.value) or tostring(value)
                end
                extra.defaultIndex = math.min(selections[action.id] or 1, #extra.values)
            end
            row(action.label, action.description, function(scroll, checked)
                if not permitted(action) then render(); return end
                if action.type == 'toggle' then
                    local nextValue = checked
                    if nextValue == nil then nextValue = not extra.checked end
                    Admin.toggleAction(action.id, nextValue)
                    render()
                elseif extra.values and not action.requiresConfirm then
                    local value = action.values[scroll or 1]
                    selections[action.id] = scroll or 1
                    Admin.selectAction(action.id, type(value) == 'table' and value.value or value)
                elseif action.qbox or action.id == 'inventory.giveItem' or action.id == 'garage.spawnVehicle' then
                    workspace(action.tab, action.qbox and action.label or '')
                elseif action.type == 'action' and not action.requiresConfirm then
                    -- Release shared focus before an action may open another lib dialog.
                    Admin.closeClassicMenu()
                    Admin.executeAction(action.id)
                else
                    workspace(action.tab, action.label)
                end
            end, extra)
        end
        if page > 1 then row('Previous page', tostring(page - 1), function() page = page - 1; render() end) end
        if page * PAGE_SIZE < #actions then row('Next page', tostring(page + 1), function() page = page + 1; render() end) end
    end
    -- Hide before replacement so the old onClose cannot close the new menu.
    lib.hideMenu(false)
    local settings = Admin.state.settings
    local view = (tab or '') .. ':' .. page
    local called, ok, reason = pcall(lib.registerMenu, { id = MENU, title = 'CORTEX', subtitle = tab and (tab:upper() .. ' / ' .. page) or 'ADMINISTRATION',
        position = settings.menuPosition == 'left' and 'top-left' or 'top-right',
        -- vMenu-style: no cursor, gameplay keeps moving; wheel/click/right click drive the list.
        gameControls = settings.mouseMenuControls ~= false,
        gamepad = settings.disableControllerSupport ~= true,
        startIndex = #options > 0 and math.min(cursors[view] or 1, #options) or nil,
        options = options,
        onSelected = function(index) cursors[view] = index end,
        onClose = function(reason)
            if reason == 'Backspace' and tab then tab, page = nil, 1; render() else active = false end
        end,
        onCheck = function(index, checked) if handlers[index] then handlers[index](1, checked) end end,
    }, function(index, scroll) if handlers[index] then handlers[index](scroll) end end)
    if not called or not ok then return failMenu(called and reason or ok) end
    local shown, result = pcall(lib.showMenu, MENU)
    if not shown or not result then return failMenu(shown and 'focus_unavailable' or result) end
    return true
end

function Admin.openClassicMenu()
    local wasOpen = Admin.state.open
    if Admin.state.open then Admin.setOpen(false) end
    if Admin.closeVehicleCamera then Admin.closeVehicleCamera() end
    if Admin.closeShowcaseCamera then Admin.closeShowcaseCamera() end
    active = true
    local ok, reason = render()
    if not ok then
        -- A saved Classic preference must not disguise a failed open as Leonida.
        if wasOpen then Admin.setOpen(true) end
        return false, reason
    end
    TriggerServerEvent('cortex-admin:server:requestPermissions')
    return true
end
function Admin.isClassicMenuOpen() return active end
function Admin.refreshClassicMenu() if active then render() end end
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() or resource == 'cortex-lib' then Admin.closeClassicMenu() end
end)
