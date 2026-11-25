-- vMenu mode: the Panel's Qbox pages (Qbox tools, Inventory, My Garage) as
-- MenuAPI menus, so vMenu mode never hands off to the Panel. Forms send the
-- same cortex-admin:qbox requests as web-admin/src/workspaces/qbox (through
-- Admin.qboxRequest); the server checks permission, target and character.
local Admin = EsAdmin
local VM = Admin.VmenuMode

local PAGE_SIZE = 60
local INVALID_INPUT = 'Nothing valid was entered, so the value was not changed.'

local function action(id) return QboxAdmin and QboxAdmin.actions[id] end
local function usable(entry)
    return entry ~= nil and VM.can(entry.id) and QboxAdmin.available(entry)
end

-- Sorted once: the descriptors never change after shared/qbox.lua loads.
local ordered
local function actions()
    if ordered then return ordered end
    ordered = {}
    for _, entry in pairs(QboxAdmin and QboxAdmin.actions or {}) do ordered[#ordered + 1] = entry end
    table.sort(ordered, function(a, b) return a.label < b.label end)
    return ordered
end

-- Any Qbox tool on another player (job, gang, money, needs, inventory, licenses).
function Admin.vmenuHasQboxTools(onPlayer)
    if not QboxAdmin or not QboxAdmin.capabilities().hasQBX then return false end
    for _, entry in ipairs(actions()) do
        if (not onPlayer or not entry.selfOnly) and usable(entry) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Forms: one per action and preset target, kept while the menu session lasts.

local forms = {}
-- A preset target is the player and connection picked in Online Players; a
-- server ID reused by someone else is a different form.
local function formKey(id, target, session) return id .. ':' .. tostring(target or 'any') .. ':' .. tostring(session or '') end
local function form(key)
    return forms[key]
end
local function openForm(id, target, name, session)
    local key = formKey(id, target, session)
    forms[key] = forms[key] or { key = key, action = id, values = {}, labels = {}, presetTarget = target, presetName = name, presetSession = session }
    return key
end

local function fieldValue(state, field) return state.values[field.name] end
local function missing(state)
    local entry = action(state.action)
    for _, field in ipairs(entry and entry.fields or {}) do
        local value = fieldValue(state, field)
        if value == nil or value == '' then return field end
    end
    return nil
end

-- Mirrors changeValues in web-admin/src/workspaces/qbox/qbox.ts.
local function setValue(state, field, value, label, row)
    state.values[field] = value
    state.labels[field] = label
    if field == 'group' then state.values.grade, state.labels.grade = nil, nil end
    if field == 'target' then
        state.values.license, state.labels.license = nil, nil
        state.values.targetCitizenid = row and row.citizenid
        state.values.targetSession = row and row.session
    end
end

-- Catalog pages, keyed by form, field and what the list depends on (grades on
-- the group, licenses on the player), so a changed group never shows old grades.
local catalogs = {}
local function catalogKey(state, field)
    local dependency = field == 'grade' and state.values.group or field == 'license' and state.values.target or ''
    return state.key .. '|' .. field .. '|' .. tostring(dependency)
end

local function requestCatalog(state, field, catalog, page, refresh)
    local key = catalogKey(state, field)
    local entry = catalogs[key] or { query = '', page = 1, revision = 0 }
    entry.revision = entry.revision + 1
    entry.page, entry.loading, entry.error = page or entry.page or 1, true, nil
    catalogs[key] = entry
    local revision = entry.revision
    Admin.qboxRequest({ action = state.action, operation = 'catalog', catalog = catalog, query = entry.query, page = entry.page,
        group = state.values.group, target = state.values.target, refresh = refresh == true }, function(result)
        -- Only the newest request for this list may fill it.
        if catalogs[key] ~= entry or entry.revision ~= revision then return end
        entry.loading = false
        if type(result) == 'table' and result.ok then
            local data = type(result.data) == 'table' and result.data or {}
            entry.rows = type(data.rows) == 'table' and data.rows or {}
            entry.total = tonumber(data.total) or #entry.rows
        else
            entry.rows, entry.total = {}, 0
            entry.error = type(result) == 'table' and type(result.error) == 'string' and result.error or 'Catalog unavailable.'
        end
        VM.refresh()
    end)
end

-- A target picked from Online Players still needs the character and session
-- the server checks, so it comes from the players catalog like the Panel's picker.
local function resolveTarget(state)
    if not state.presetTarget or state.values.targetCitizenid or state.resolving then return end
    state.resolving = true
    -- Rows are labelled "[id] name", so the bracketed id narrows the search to
    -- this player; pages are walked in case other labels contain it too.
    local function ask(page)
        Admin.qboxRequest({ action = state.action, operation = 'catalog', catalog = 'players',
            query = ('[%s]'):format(tostring(state.presetTarget)), page = page }, function(result)
            local data = type(result) == 'table' and result.ok and type(result.data) == 'table' and result.data or {}
            for _, row in ipairs(type(data.rows) == 'table' and data.rows or {}) do
                if tostring(row.value) == tostring(state.presetTarget) then
                    state.resolving = false
                    if state.presetSession ~= nil and row.session ~= state.presetSession then
                        state.targetError = 'This player left or reconnected. Go back to Online Players and select them again.'
                    else
                        setValue(state, 'target', row.value, row.label, row)
                    end
                    VM.refresh()
                    return
                end
            end
            if page * PAGE_SIZE < (tonumber(data.total) or 0) then ask(page + 1); return end
            state.resolving = false
            state.targetError = result and result.ok and 'This player has no Qbox character loaded.' or 'The player list could not be loaded.'
            VM.refresh()
        end)
    end
    ask(1)
end

-- ---------------------------------------------------------------------------
-- Results: messages as notifications; reads (Inspect character) as a menu.

local lastResult
local function flatten(data, prefix, rows)
    local keys = {}
    for key in pairs(data) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local value, name = data[key], prefix .. tostring(key)
        if type(value) == 'table' then
            if #rows < 200 then flatten(value, name .. '.', rows) end
        else
            rows[#rows + 1] = { label = name, value = tostring(value) }
        end
    end
    return rows
end

local function submit(state)
    local entry = action(state.action)
    if not entry or VM.denied(entry.id) then return end
    local field = missing(state)
    if field then Admin.notify('error', ('Choose %s first.'):format(field.label:lower())); return end
    if state.busy then Admin.notify('error', 'The last request is still running.'); return end
    state.busy = true
    local payload = { action = entry.id, operation = 'execute', confirm = true }
    for key, value in pairs(state.values) do payload[key] = value end
    Admin.qboxRequest(payload, function(result)
        state.busy = false
        if type(result) ~= 'table' or not result.ok then
            Admin.notify('error', type(result) == 'table' and type(result.error) == 'string' and result.error or 'The request failed.')
            VM.refresh()
            return
        end
        Admin.notify('success', type(result.message) == 'string' and result.message ~= '' and result.message or (entry.label .. ' done.'))
        if entry.id == 'qbx.openInventory' then Admin.closeVmenuMode(); return end
        if type(result.data) == 'table' and not result.data.appearance and next(result.data) then
            -- Only over the form that asked; a closed or moved-on menu is left alone.
            local id, args = VM.top()
            if Admin.isVmenuModeOpen() and id == 'qbox_action' and type(args) == 'table'
                and formKey(args.action, args.target, args.session) == state.key then
                lastResult = { title = entry.label, rows = flatten(result.data, '', {}) }
                VM.open('qbox_result')
            end
            return
        end
        VM.refresh()
    end)
end

-- ---------------------------------------------------------------------------
-- Menus

VM.define('qbox_tools', {
    subtitle = function(args) return args and args.name and ('Qbox: ~y~' .. args.name) or 'Qbox Tools' end,
    build = function(args)
        local target = type(args) == 'table' and args.target or nil
        local rows = {}
        for _, entry in ipairs(actions()) do
            if (not target or not entry.selfOnly) and usable(entry) then
                rows[#rows + 1] = VM.submenu('qbox_action', entry.label, entry.description,
                    { key = formKey(entry.id, target, args and args.session), action = entry.id, target = target, session = args and args.session, name = args and args.name },
                    { key = entry.id, hideEmpty = false, icon = entry.confirm and 'warning' or nil })
            end
        end
        return rows
    end,
})

VM.define('qbox_action', {
    title = 'Qbox',
    subtitle = function(args) local entry = args and action(args.action); return entry and entry.label or 'Qbox' end,
    onOpen = function(args)
        if type(args) ~= 'table' then return end
        local state = form(openForm(args.action, args.target, args.name, args.session))
        -- The player may have reconnected or switched character since the last visit.
        if state.presetTarget then state.values.targetCitizenid, state.values.targetSession, state.labels.target, state.targetError = nil, nil, nil, nil end
        resolveTarget(state)
    end,
    build = function(args)
        local entry = type(args) == 'table' and action(args.action)
        if not entry or not usable(entry) then return {} end
        local state = form(openForm(args.action, args.target, args.name, args.session))
        local rows = {}
        for _, field in ipairs(entry.fields) do
            local value, label = fieldValue(state, field), state.labels[field.name]
            if field.name == 'target' and state.presetTarget then
                rows[#rows + 1] = VM.button(field.label, state.targetError or 'The player this change applies to.', nil,
                    { key = 'field:target', enabled = false, rightLabel = label or (state.resolving and 'Loading…' or tostring(state.presetName or state.presetTarget)) })
            elseif field.catalog then
                local blocked = (field.catalog == 'grades' and not state.values.group) or (field.catalog == 'licenses' and not state.values.target)
                rows[#rows + 1] = VM.submenu('qbox_pick', field.label,
                    blocked and (field.catalog == 'grades' and 'Choose the group first.' or 'Choose the player first.') or ('Choose the %s.'):format(field.label:lower()),
                    { key = state.key .. '|' .. field.name, form = state.key, field = field.name, catalog = field.catalog },
                    { key = 'field:' .. field.name, hideEmpty = false, enabled = not blocked, rightLabel = label and ('~y~' .. label) or 'Choose →→→' })
            else
                rows[#rows + 1] = VM.button(field.label, field.type == 'number'
                    and ('Type a number from %s to %s.'):format(tostring(field.min), tostring(field.max)) or 'Type a value.', function()
                    local input = VM.input(field.label, value or '', 20)
                    if input == nil then return end
                    if field.type == 'number' then
                        local number = tonumber(input)
                        if not number or number % 1 ~= 0 or (field.min and number < field.min) or (field.max and number > field.max) then
                            Admin.notify('error', ('%s must be a whole number from %s to %s.'):format(field.label, tostring(field.min), tostring(field.max)))
                            return
                        end
                        input = tostring(math.floor(number))
                    elseif input == '' then Admin.notify('error', INVALID_INPUT); return end
                    setValue(state, field.name, input, input)
                end, { key = 'field:' .. field.name, rightLabel = value and ('~y~' .. tostring(value)) or 'Enter value' })
            end
        end
        local ready = missing(state) == nil and not state.busy
        rows[#rows + 1] = VM.button(entry.confirm and ('~r~' .. entry.label) or entry.label,
            state.busy and 'Waiting for the server.' or (ready and entry.description or 'Fill in every field above first.'),
            function() submit(state) end,
            { key = 'submit', enabled = ready, confirm = entry.confirm == true, icon = entry.confirm and 'warning' or 'tick' })
        return rows
    end,
})

local function pickerButtons(args)
    return {
        { control = 22, label = 'Search', run = function()
            local state = args and form(args.form)
            if not state then return end
            local key = catalogKey(state, args.field)
            local input = VM.input('Search, or leave empty to show everything', catalogs[key] and catalogs[key].query or '', 80)
            if input == nil then return end
            catalogs[key] = { query = input, page = 1, revision = (catalogs[key] and catalogs[key].revision or 0) + 1 }
            requestCatalog(state, args.field, args.catalog, 1)
        end },
    }
end

VM.define('qbox_pick', {
    title = 'Qbox',
    subtitle = function(args) return 'Choose: ~y~' .. tostring(args and args.field or '') end,
    counterPreText = function(args)
        local state = args and form(args.form)
        local entry = state and catalogs[catalogKey(state, args.field)]
        return entry and entry.query ~= '' and ('"%s" '):format(entry.query) or ''
    end,
    buttons = pickerButtons,
    onOpen = function(args)
        local state = args and form(args.form)
        if state then requestCatalog(state, args.field, args.catalog, 1) end
    end,
    build = function(args)
        local state = type(args) == 'table' and form(args.form)
        if not state or not usable(action(state.action)) then return {} end
        local entry = catalogs[catalogKey(state, args.field)] or {}
        -- Nothing from an older page or search is selectable while a new one loads.
        if entry.loading then
            return { VM.button('Loading…', 'Asking the server for the list.', nil, { enabled = false, key = 'loading' }) }
        end
        if entry.error then
            return { VM.button('List Unavailable', entry.error, function() requestCatalog(state, args.field, args.catalog, entry.page, true) end, { key = 'error', rightLabel = 'Retry' }) }
        end
        local rows = {}
        for _, row in ipairs(entry.rows or {}) do
            local detail = row.detail and row.detail ~= '' and row.detail or nil
            rows[#rows + 1] = VM.button(tostring(row.label), ('%s%s'):format(tostring(row.value), detail and (' · ' .. detail) or ''), function()
                setValue(state, args.field, row.value, row.label, row)
                VM.back()
            end, { key = 'row:' .. tostring(row.value), rightLabel = state.values[args.field] == row.value and '~g~Chosen' or nil })
        end
        if #rows == 0 then rows[1] = VM.button('Nothing Found', 'Press Space to search for something else.', nil, { enabled = false, key = 'empty' }) end
        local pages = math.max(1, math.ceil((entry.total or 0) / PAGE_SIZE))
        if entry.page and entry.page < pages then
            rows[#rows + 1] = VM.button('Next Page', ('Page %d of %d.'):format(entry.page, pages), function()
                requestCatalog(state, args.field, args.catalog, entry.page + 1)
            end, { key = 'next', rightLabel = ('%d / %d'):format(entry.page, pages) })
        end
        if entry.page and entry.page > 1 then
            rows[#rows + 1] = VM.button('Previous Page', ('Page %d of %d.'):format(entry.page, pages), function()
                requestCatalog(state, args.field, args.catalog, entry.page - 1)
            end, { key = 'previous' })
        end
        return rows
    end,
})

VM.define('qbox_result', {
    title = 'Qbox',
    subtitle = function() return lastResult and lastResult.title or 'Result' end,
    build = function()
        local rows = {}
        for i, row in ipairs(lastResult and lastResult.rows or {}) do
            rows[i] = VM.button(row.label, row.value, nil, { key = 'result:' .. i, rightLabel = '~y~' .. row.value })
        end
        return rows
    end,
})

-- ---------------------------------------------------------------------------
-- My Garage (web-admin/src/workspaces/vehicles/Garage.svelte)

local STATES = { [0] = '~g~Out', [1] = 'Garaged', [2] = '~o~Impounded' }
local garage = { loading = false, requested = 0 }

function Admin.vmenuGarageAvailable()
    if not VM.can('garage.spawnVehicle') or not QboxAdmin then return false end
    local caps = QboxAdmin.capabilities()
    return caps.hasQBX == true and caps.hasGarage == true
end

function Admin.onVmenuGarage()
    garage.loading = false
    if Admin.isVmenuModeOpen and Admin.isVmenuModeOpen() then VM.refresh() end
end

VM.define('qbox_garage', {
    subtitle = 'My Garage',
    counterPreText = 'Vehicles: ',
    buttons = { VM.filterButton('Name, model, plate or garage to match (submit empty to show all)', 'Filter Vehicles') },
    onOpen = function()
        garage.loading, garage.requested = true, GetGameTimer()
        TriggerServerEvent('cortex-admin:server:getPlayerGarage')
    end,
    build = function()
        if not Admin.vmenuGarageAvailable() then return {} end
        local list = type(Admin.state.garageVehicles) == 'table' and Admin.state.garageVehicles or {}
        if #list == 0 then
            local waiting = garage.loading and GetGameTimer() - garage.requested < 8000
            return { VM.button(waiting and 'Loading Garage…' or 'No Vehicles', waiting and 'Asking the server for your vehicles.' or 'You do not own any vehicles yet, or the server did not answer.', nil, { enabled = false, key = 'empty' }) }
        end
        local rows = {}
        for _, vehicle in ipairs(list) do
            local id = tonumber(vehicle.id)
            if id then
                local name = tostring(vehicle.label or vehicle.model or 'Unknown vehicle')
                if vehicle.brand and vehicle.brand ~= '' and not name:find(vehicle.brand, 1, true) then name = vehicle.brand .. ' ' .. name end
                rows[#rows + 1] = VM.button(name, ('Plate ~y~%s~s~ · %s. Select to spawn it.'):format(tostring(vehicle.plate or 'none'), tostring(vehicle.garage or 'Unknown garage')), function()
                    if VM.denied('garage.spawnVehicle') then return end
                    TriggerServerEvent('cortex-admin:server:spawnGarageVehicle', { vehicleId = id })
                end, { key = 'garage:' .. id, rightLabel = STATES[tonumber(vehicle.state)] or tostring(vehicle.plate or '') })
            end
        end
        return rows
    end,
})
