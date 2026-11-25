-- Saved-library metadata uses the same stores as spawning and importing.
local Admin = EsAdmin
local A = Admin.savedLibraryAdapter
local entryCache, refreshing = {}, false
local function allowed(kind, deleting)
    local action = kind == 'vehicles' and (deleting and 'vehicle.removePersonal' or 'vehicle.savePersonal') or 'player.saveMpPed'
    return Admin.state.allowed[action] == true
end
local function validName(value)
    return type(value) == 'string' and #value > 0 and #value <= 60
        and not value:find('[%z\1-\31\127]') and value:match('%S') ~= nil
end
local function copy(value) return json.decode(json.encode(value)) end
local function category(entry, kind)
    local value = kind == 'vehicles' and entry.vmenuCategory or entry.category
    return type(value) == 'string' and value:lower() ~= 'uncategorized' and value or ''
end
local function refresh()
    if Admin.refreshPersonalVehiclesCache then Admin.refreshPersonalVehiclesCache() end
    entryCache = {}
    if Admin.refreshSavedLibrary then Admin.refreshSavedLibrary() end
    if Admin.refreshVmenuMode then Admin.refreshVmenuMode() end
end
local function localizeVehicle(entry)
    if entry.source == A.remoteVehicleSource then
        entry.importedFrom, entry.importedSourceKey = 'vmenu', entry.sourceKey
        entry.source, entry.sourceKey = A.localVehicleSource, nil
    end
end
function Admin.getSavedLibraryEntries(kind)
    return entryCache[kind] or {}
end
function Admin.refreshSavedLibrary()
    if refreshing then return end
    refreshing = true
    CreateThread(function()
        local ok, vehicles = pcall(A.loadVehicles)
        if ok then entryCache.vehicles = vehicles.vehicles or {} end
        local pedOk, peds = pcall(Admin.getSavedPeds)
        if pedOk then entryCache.peds = peds or {} end
        refreshing = false
        if Admin.refreshVmenuMode then Admin.refreshVmenuMode() end
    end)
end
function Admin.getSavedLibraryCategories(kind)
    local saved = A.read(Config.KvpKeys.vmenuCategories, {})
    local rows, seen = {}, {}
    local function add(name, description, icon)
        if not validName(name) or name:lower() == 'uncategorized' or seen[name] then return end
        seen[name] = true
        rows[#rows + 1] = { name = name, description = description or '', icon = icon or 'none' }
    end
    for _, record in ipairs(type(saved[kind]) == 'table' and saved[kind] or {}) do
        local data = record.data or record
        add(data.Name, data.Description, data.Icon)
    end
    for _, entry in ipairs(Admin.getSavedLibraryEntries(kind)) do add(category(entry, kind)) end
    table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
    return rows
end
function Admin.updateSavedVehicleMetadata(id, changes)
    if not allowed('vehicles') or type(changes) ~= 'table' then return false end
    local saved, target = A.loadVehicles()
    for _, entry in ipairs(saved.vehicles) do if entry.id == id then target = entry end end
    if not target then return false end
    if changes.name ~= nil then
        if not validName(changes.name) then return false end
        for _, entry in ipairs(saved.vehicles) do
            if entry.id ~= id and entry.name:lower() == changes.name:lower() then return false end
        end
        target.name = changes.name
        if target.props then target.props.name = changes.name end
    end
    if changes.category ~= nil then
        if changes.category ~= '' and not validName(changes.category) then return false end
        target.vmenuCategory = changes.category
    end
    localizeVehicle(target)
    if not A.saveVehicles(saved) then return false end
    refresh()
    return true
end
function Admin.assignSavedLibraryCategory(kind, id, name)
    if not allowed(kind) or name ~= '' and not validName(name) then return false end
    if kind == 'vehicles' then return Admin.updateSavedVehicleMetadata(id, { category = name }) end
    if kind ~= 'peds' then return false end
    for _, entry in ipairs(Admin.getSavedPeds()) do
        if entry.id == id then
            local data = A.loadPed(entry)
            if not data then return false end
            data.Category = name
            if not A.writePed(entry, data) then return false end
            refresh(); return true
        end
    end
    return false
end

-- Category rename/delete updates all memberships. Failed writes roll back the
-- completed records and leave the category definition intact.
function Admin.editSavedLibraryCategory(kind, previous, changes)
    if kind ~= 'vehicles' and kind ~= 'peds' or not allowed(kind) then return false end
    changes = changes or {}
    local nextName = changes.delete and '' or changes.name or previous
    if not changes.delete and not validName(nextName) then return false end
    entryCache[kind] = kind == 'vehicles' and A.loadVehicles().vehicles or Admin.getSavedPeds()
    local rows = Admin.getSavedLibraryCategories(kind)
    local records, found = {}, false
    for _, row in ipairs(rows) do
        if row.name == previous then
            found = true
            if not changes.delete then
                row = { name = nextName, description = changes.description or row.description, icon = changes.icon or row.icon }
            else row = nil end
        elseif row.name:lower() == nextName:lower() then return false end
        if row then records[#records + 1] = { data = { Name = row.name, Description = row.description, Icon = row.icon } } end
    end
    if not found then
        if previous or changes.delete then return false end
        records[#records + 1] = { data = { Name = nextName, Description = changes.description or '', Icon = changes.icon or 'none' } }
    end
    local categories = A.read(Config.KvpKeys.vmenuCategories, {})
    local rollback = {}
    local function restore()
        local restored = true
        for i = #rollback, 1, -1 do if rollback[i]() == false then restored = false end end
        if not restored then Admin.notify('error', 'A save could not be restored after the write failed. Check the saved library before retrying.') end
    end
    if previous and previous ~= nextName then
        if kind == 'vehicles' then
            local saved = A.loadVehicles()
            local original = copy(saved)
            for _, entry in ipairs(saved.vehicles) do
                if category(entry, kind) == previous then entry.vmenuCategory = nextName; localizeVehicle(entry) end
            end
            if not A.saveVehicles(saved) then return false end
            rollback[#rollback + 1] = function() return A.saveVehicles(original) end
        else
            for _, entry in ipairs(Admin.getSavedPeds()) do
                if category(entry, kind) == previous then
                    local original = A.loadPed(entry)
                    if not original then restore(); return false end
                    local changed = copy(original); changed.Category = nextName
                    if not A.writePed(entry, changed) then restore(); return false end
                    rollback[#rollback + 1] = function() return A.writePed(entry, original) end
                end
            end
        end
    end
    categories[kind] = records
    if not A.write(Config.KvpKeys.vmenuCategories, categories) then restore(); return false end
    refresh()
    return true
end

function Admin.deleteSavedLibraryCategoryContents(kind, name)
    if not allowed(kind, true) then return false end
    if kind == 'vehicles' then
        local saved = A.loadVehicles()
        saved.suppressedVmenu = saved.suppressedVmenu or {}
        for i = #saved.vehicles, 1, -1 do
            local entry = saved.vehicles[i]
            if category(entry, kind) == name then
                local sourceKey = entry.importedSourceKey or entry.source == A.remoteVehicleSource and entry.sourceKey
                if sourceKey then saved.suppressedVmenu[sourceKey] = true end
                table.remove(saved.vehicles, i)
            end
        end
        if not A.saveVehicles(saved) then return false end
        refresh(); return true
    elseif kind == 'peds' then
        for _, entry in ipairs(Admin.getSavedPeds()) do
            if category(entry, kind) == name and Admin.deleteSavedPed(entry) ~= true then return false end
        end
        return true
    end
    return false
end
