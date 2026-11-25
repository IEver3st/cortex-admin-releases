-- vMenu mode: Server Management. vMenu has no such menu; this is the Cortex
-- resource manager (web-admin's Resources page) in MenuAPI form. It uses the
-- same server events, so the server still checks server.resources, refuses
-- protected resources and reports the resulting state.
local Admin = EsAdmin
local VM = Admin.VmenuMode

local TONES = { started = '~g~', starting = '~y~', stopping = '~y~', missing = '~r~' }

-- Sorted once per list the server sends. Sorting on every build, and again in
-- each resource row's lookup, cost ~20 ms per rebuild with 130 resources.
local sortedFrom, sorted, byName = nil, {}, {}
local function resources()
    local source = type(Admin.state.resources) == 'table' and Admin.state.resources or {}
    if source == sortedFrom then return sorted end
    local list, keys, names = {}, {}, {}
    for _, resource in ipairs(source) do
        if type(resource) == 'table' and type(resource.name) == 'string' and resource.name ~= '' then
            list[#list + 1] = resource
            keys[resource], names[resource.name] = resource.name:lower(), resource
        end
    end
    table.sort(list, function(a, b) return keys[a] < keys[b] end)
    sortedFrom, sorted, byName = source, list, names
    return list
end

local function find(name)
    resources()
    return byName[name]
end

local function stateLabel(resource)
    local status = tostring(resource.state or resource.status or 'unknown')
    return (TONES[status] or '~c~') .. status:sub(1, 1):upper() .. status:sub(2)
end

local function about(resource)
    local text = type(resource.description) == 'string' and resource.description ~= '' and resource.description ~= 'No description'
        and resource.description or 'No description.'
    return ('%s~n~~c~v%s · %s'):format(text, tostring(resource.version or 'Unknown'), tostring(resource.author or 'Unknown'))
end

local function pullStash()
    if VM.denied('server.pullStash') then return end
    local stash = VM.input('Stash name, such as police_stash', nil, 80)
    stash = stash and stash:match('^%s*(.-)%s*$')
    if not stash or stash == '' then Admin.notify('error', 'Nothing was entered, so no stash was opened.'); return end
    Admin.closeVmenuMode()
    TriggerServerEvent('cortex-admin:server:pullStash', { stash = stash })
end

local function act(action, name, verb)
    if VM.denied('server.resources') then return end
    TriggerServerEvent('cortex-admin:server:resourceAction', { action = action, name = name })
    if verb then Admin.notify('info', ('%s %s…'):format(verb, name)) end
end

VM.define('server_management', {
    subtitle = 'Server Management',
    counterPreText = 'Resources: ',
    static = true, -- redrawn when the server sends a new list
    onOpen = function() TriggerServerEvent('cortex-admin:server:requestResources') end,
    buttons = { VM.filterButton('Resource name to match (submit empty to show all)', 'Filter Resources') },
    build = function()
        local rows = {}
        if VM.can('server.pullStash') then
            rows[1] = VM.button('Pull Stash', 'Type a stash name to open it (ox_inventory). Closes this menu.', pullStash, { key = 'server.pullStash' })
        end
        if not VM.can('server.resources') then return rows end
        rows[#rows + 1] = VM.button('Refresh Resource List', 'Scan the resources folder for new or changed resources, then reload this list.', function()
            act('refresh', 'all')
        end)
        local list = resources()
        if #list == 0 then
            rows[#rows + 1] = VM.button('Loading resources…', 'The server sends the list when this menu opens.', nil, { enabled = false })
        end
        for _, resource in ipairs(list) do
            -- Every resource menu has rows, so it is never built just to check;
            -- the description is formatted only for the highlighted row.
            rows[#rows + 1] = VM.submenu('server_resource', resource.name, function() return about(resource) end,
                { key = resource.name, name = resource.name },
                { key = 'resource:' .. resource.name, rightLabel = stateLabel(resource), hideEmpty = false })
        end
        return rows
    end,
})

VM.define('server_resource', {
    title = 'Server Management',
    static = true,
    subtitle = function(args) return 'Resource: ~y~' .. tostring(args and args.name or '?') end,
    build = function(args)
        if not VM.can('server.resources') or type(args) ~= 'table' or type(args.name) ~= 'string' then return {} end
        local name = args.name
        local resource = find(name) or { name = name, state = 'unknown' }
        local status = tostring(resource.state or resource.status or 'unknown')
        local description = about(resource)
        local rows = {}
        if status == 'stopped' or status == 'uninitialized' then
            rows[#rows + 1] = VM.button('Start Resource', description, function() act('start', name, 'Starting') end)
        else
            rows[#rows + 1] = VM.button('Restart Resource', description, function() act('restart', name, 'Restarting') end)
            rows[#rows + 1] = VM.button('~r~Stop Resource', description, function() act('stop', name, 'Stopping') end)
        end
        rows[#rows + 1] = VM.button('Current State', description, nil, { rightLabel = stateLabel(resource), enabled = false })
        return rows
    end,
})

-- A fresh list from the server (after an action, refresh or open) redraws the open menu.
function Admin.onVmenuResources()
    if Admin.isVmenuModeOpen and Admin.isVmenuModeOpen() then VM.refresh() end
end
