local Admin, VM = EsAdmin, EsAdmin.VmenuMode
local function canManage(kind)
    return VM.can(kind == 'vehicles' and 'vehicle.savePersonal' or 'player.saveMpPed')
end
local function append(rows, row)
    if not row then return end
    local last = 0
    for key in pairs(rows) do if type(key) == 'number' then last = math.max(last, key) end end
    rows[last + 1] = row
end
local function result(ok, message)
    VM.notify(ok and 'success' or 'error', ok and message or 'The saved library could not be updated.')
    VM.refresh()
    return ok
end
local function categoryOf(entry, kind)
    local name = kind == 'vehicles' and entry.vmenuCategory or entry.category
    return type(name) == 'string' and name:lower() ~= 'uncategorized' and name or ''
end
local function categoryLink(kind, name, description, icon)
    return VM.submenu('saved_library_category', name == '' and 'Uncategorized' or name, description,
        { key = kind .. ':' .. name, kind = kind, name = name }, { hideEmpty = false, icon = icon })
end
local function createCategory(kind)
    local name = VM.input('New category name', nil, 30)
    if not name or name == '' then return end
    result(Admin.editSavedLibraryCategory(kind, nil, { name = name }), 'Category created.')
end
local function categoryRows(kind)
    local rows = { categoryLink(kind, '', 'Saves without a custom category.') }
    if canManage(kind) then rows[#rows + 1] = VM.button('Create Category', 'Create a custom save category.', function() createCategory(kind) end) end
    for _, entry in ipairs(Admin.getSavedLibraryCategories(kind)) do
        rows[#rows + 1] = categoryLink(kind, entry.name, entry.description, entry.icon)
    end
    return rows
end
local function assignmentRow(kind, entry)
    if not canManage(kind) then return nil end
    local names, values, selected = { 'Uncategorized' }, { '' }, 1
    for _, cat in ipairs(Admin.getSavedLibraryCategories(kind)) do
        names[#names + 1], values[#values + 1] = cat.name, cat.name
        if categoryOf(entry, kind) == cat.name then selected = #values end
    end
    return { kind = 'list', key = 'category:' .. tostring(entry.id), label = 'Set Category', values = names, index = selected,
        description = 'Choose a category and select to save.', onSelect = function(position)
            result(Admin.assignSavedLibraryCategory(kind, entry.id, values[position]), 'Category assigned.')
        end }
end
local originalSavedVehicles = VM._definitions.saved_vehicles.build
local originalVehiclesOpen = VM._definitions.saved_vehicles.onOpen
VM._definitions.saved_vehicles.onOpen = function(args)
    if originalVehiclesOpen then originalVehiclesOpen(args) end
    Admin.refreshSavedLibrary()
end
VM._definitions.saved_vehicles.build = function(args)
    local rows = originalSavedVehicles(args)
    append(rows, VM.submenu('saved_library_categories', 'Custom Categories', 'Organize saved vehicles.', { key = 'vehicles', kind = 'vehicles' }, { hideEmpty = false }))
    return rows
end
VM.define('saved_library_categories', {
    title = 'Saved Categories', subtitle = 'Manage Saved Vehicles',
    onOpen = function() Admin.refreshSavedLibrary() end,
    build = function(args) return categoryRows(args.kind) end,
})
VM._definitions.mp_ped_saved.build = function() return categoryRows('peds') end
VM._definitions.mp_ped_saved.onOpen = function() Admin.refreshSavedLibrary() end
local originalVehicle = VM._definitions.saved_vehicle.build
VM._definitions.saved_vehicle.build = function(args)
    local rows = originalVehicle(args)
    for _, entry in ipairs(Admin.getSavedLibraryEntries('vehicles')) do
        if entry.id == args.key then
            append(rows, assignmentRow('vehicles', entry))
            if canManage('vehicles') then
                append(rows, VM.button('Rename Vehicle', 'Change this saved vehicle name.', function()
                    local name = VM.input('Enter a new vehicle name', entry.name, 30)
                    if name and name ~= '' then result(Admin.updateSavedVehicleMetadata(entry.id, { name = name }), 'Vehicle renamed.') end
                end))
            end
            break
        end
    end
    return rows
end
local originalCharacter = VM._definitions.mp_ped_character.build
for _, id in ipairs({ 'mp_ped_character', 'saved_vehicle' }) do
    local originalClose = VM._definitions[id].onClose
    VM._definitions[id].onClose = function(args)
        if originalClose then originalClose(args) end
        Admin.refreshSavedLibrary()
    end
end
VM._definitions.mp_ped_character.build = function(args)
    for _, entry in ipairs(Admin.getSavedLibraryEntries('peds')) do
        if entry.id == args.entry.id then args.entry = entry; break end
    end
    local rows = originalCharacter(args)
    append(rows, assignmentRow('peds', args.entry))
    return rows
end

local deleteContents = {}
local icons = { 'none', 'star', 'tick', 'warning', 'lock', 'gun', 'ammo' }
VM.define('saved_library_category', {
    title = function(args) return args.name == '' and 'Uncategorized' or args.name end,
    subtitle = 'Manage Category',
    onOpen = function() Admin.refreshSavedLibrary() end,
    onClose = function(args) deleteContents[args.key] = nil end,
    build = function(args)
        local kind, name, rows = args.kind, args.name, {}
        local definition = {}
        for _, cat in ipairs(Admin.getSavedLibraryCategories(kind)) do if cat.name == name then definition = cat end end
        if canManage(kind) and name ~= '' then
            rows[#rows + 1] = VM.button('Rename Category', 'Update the category and its saved entries.', function()
                local nextName = VM.input('Category name', name, 30)
                if nextName and result(Admin.editSavedLibraryCategory(kind, name, { name = nextName }), 'Category renamed.') then
                    args.name, args.key = nextName, kind .. ':' .. nextName
                end
            end)
            rows[#rows + 1] = VM.button('Change Category Description', 'Edit the description shown in the category list.', function()
                local description = VM.input('Enter a description', definition.description, 120)
                if description then result(Admin.editSavedLibraryCategory(kind, name, { description = description }), 'Description saved.') end
            end)
            rows[#rows + 1] = { kind = 'list', label = 'Change Category Icon', values = icons, onSelect = function(position)
                result(Admin.editSavedLibraryCategory(kind, name, { icon = icons[position] }), 'Icon saved.')
            end }
            rows[#rows + 1] = { kind = 'checkbox', label = kind == 'vehicles' and 'Delete All Vehicles' or 'Delete All Characters',
                description = 'Include the saved entries when deleting this category.', checked = deleteContents[args.key] == true,
                onCheck = function(checked) deleteContents[args.key] = checked end }
            rows[#rows + 1] = VM.button('Delete Category', 'Entries are moved to Uncategorized unless deletion is selected above.', function()
                if deleteContents[args.key] and not Admin.deleteSavedLibraryCategoryContents(kind, name) then
                    result(false); return
                end
                if result(Admin.editSavedLibraryCategory(kind, name, { delete = true }), 'Category deleted.') then VM.back() end
            end, { confirm = true, icon = 'warning' })
        end
        for _, entry in ipairs(Admin.getSavedLibraryEntries(kind)) do
            if categoryOf(entry, kind) == name then
                rows[#rows + 1] = VM.submenu(kind == 'vehicles' and 'saved_vehicle' or 'mp_ped_character', entry.name,
                    'Spawn or manage this saved entry.', { key = kind == 'vehicles' and entry.id or entry.name, entry = entry },
                    { hideEmpty = false, icon = entry.isDefault and 'tick' or nil })
            end
        end
        return rows
    end,
})
