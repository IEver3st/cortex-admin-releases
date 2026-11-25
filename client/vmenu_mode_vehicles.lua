-- vMenu mode: Vehicle Spawner, Saved Vehicles and Personal Vehicle, ported from
-- vMenu 3.8.67 menus/VehicleSpawner.cs, SavedVehicles.cs and PersonalVehicle.cs.
-- Spawning, saving and personal-vehicle control run the Cortex vehicle actions;
-- per-class, addon and whitelisted-model authorization stays on the server.
local Admin = EsAdmin
local VM = Admin.VmenuMode

-- Stock models per class (GetVehicleClass order), from the game-data reference.
local CLASS_MODELS = {}
do
    local reference = EsAdminVmenuReference or { vehicleClassNames = {}, vehicleClasses = {} }
    local position, names = {}, {}
    for index, suffix in ipairs(reference.vehicleClassNames) do position[suffix], CLASS_MODELS[index] = index, {} end
    for name in pairs(reference.vehicleClasses) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local list = CLASS_MODELS[position[reference.vehicleClasses[name]]]
        if list then list[#list + 1] = name end
    end
end
local CLASS_FALLBACK = { 'Compacts', 'Sedans', 'SUVs', 'Coupes', 'Muscle', 'Sports Classics', 'Sports', 'Super',
    'Motorcycles', 'Off-road', 'Industrial', 'Utility', 'Vans', 'Cycles', 'Boats', 'Helicopters', 'Planes',
    'Service', 'Emergency', 'Military', 'Commercial', 'Trains', 'Open Wheel' }

local INVALID_INPUT = 'Nothing was entered or the prompt was closed. Try again.'
local MISSING_MODEL = 'The game has no model with this name. An addon vehicle only appears here while the server streams it.'

local function className(class)
    local label = GetLabelText(('VEH_CLASS_%d'):format(class))
    if not label or label == '' or label == 'NULL' then return CLASS_FALLBACK[class + 1] end
    return label
end

local function modelHash(model)
    if type(model) == 'number' then return model end
    return joaat(tostring(model or ''))
end

-- Model facts do not change while a session runs, so each is looked up once.
local modelInfo = {}
local function info(model)
    local hash = modelHash(model)
    local entry = modelInfo[hash]
    if not entry then
        local display = GetDisplayNameFromVehicleModel(hash) or 'CARNOTFOUND'
        local label = GetLabelText(display)
        local exists = IsModelInCdimage(hash)
        entry = {
            class = GetVehicleClassFromName(hash),
            exists = exists == true or exists == 1,
            display = display,
            label = (label and label ~= 'NULL' and label ~= '') and label or nil,
        }
        modelInfo[hash] = entry
    end
    return entry
end

local function spawnModel(model) VM.execute('vehicle.spawn', { model = model }) end

-- ---------------------------------------------------------------------------
-- Vehicle Spawner (VehicleSpawner.cs)

local function addonVehicles()
    local list = Admin.getAddonVehicles and Admin.getAddonVehicles() or {}
    local output = {}
    for _, entry in ipairs(type(list) == 'table' and list or {}) do
        local model = type(entry) == 'table' and entry.model or entry
        if type(model) == 'string' and model ~= '' then output[#output + 1] = model:lower() end
    end
    return output
end

-- VehicleSpawner.cs:90-93: label text, then the display name, then the model key.
local function addonName(model)
    local entry = info(model)
    local name = entry.label or entry.display
    return name ~= 'CARNOTFOUND' and name or model
end

VM.define('vehicle_spawner', {
    subtitle = 'Vehicle Spawner',
    onOpen = function()
        if VM.can('vehicle.spawn') and Admin.requestAddonVehiclesIfNeeded then Admin.requestAddonVehiclesIfNeeded(false) end
    end,
    build = function()
        if not VM.can('vehicle.spawn') then return {} end
        local items = {
            VM.ace('vMenu.VehicleSpawner.SpawnByName', 'vehicle.spawn') and VM.button('Spawn Vehicle By Model Name', 'Type a model name, such as adder, to spawn that vehicle.', function()
                if VM.denied('vehicle.spawn') then return end
                local name = VM.input('Vehicle model', nil, 30)
                if not name or name == '' then VM.notify('error', INVALID_INPUT); return end
                spawnModel(name)
            end) or nil,
            VM.toggle('options.spawnInsideVehicle', 'Spawn Inside Vehicle', 'Seat yourself behind the wheel of each vehicle as it spawns.'),
            VM.toggle('options.replacePersonalVehicle', 'Replace Previous Vehicle', 'Remove the last vehicle you spawned whenever you spawn another one.'),
        }
        if not VM.ace('vMenu.VehicleSpawner.Addon', 'vehicle.spawn') then
            -- The class lists remain available independently of addon access.
        elseif #addonVehicles() > 0 then
            items[#items + 1] = VM.submenu('vehicle_spawner_addons', 'Addon Vehicles', 'Browse the custom vehicles this server streams.', nil, { hideEmpty = false })
        else
            items[#items + 1] = VM.button('Addon Vehicles', 'This server streams no custom vehicles.', nil, { enabled = false, rightLabel = '→→→' })
        end
        for class = 0, 22 do
            local name = className(class)
            local suffix = EsAdminVmenuReference and EsAdminVmenuReference.vehicleClassNames[class + 1]
            local allowed = not suffix or VM.ace('vMenu.VehicleSpawner.' .. suffix, 'vehicle.spawn')
            items[#items + 1] = VM.submenu('vehicle_spawner_class', name, ('Browse stock ~o~%s ~s~models.'):format(name),
                { key = class }, { hideEmpty = false, enabled = allowed, icon = not allowed and 'lock' or nil })
        end
        return items
    end,
})

-- A class menu is built once, as vMenu does; duplicate names get " (2)", " (3)"...
local classRows = {}
local function buildClassRows(class)
    local rows, seen = {}, {}
    for _, model in ipairs(CLASS_MODELS[class + 1] or {}) do
        local entry = info(model)
        local name = entry.label or (model:sub(1, 1):upper() .. model:sub(2))
        if seen[name] then
            seen[name] = seen[name] + 1
            name = ('%s (%d)'):format(name, seen[name])
        else
            seen[name] = 1
        end
        local row = { key = model, label = name, rightLabel = ('(%s)'):format(model) }
        row.stats = function() return VM.vehicleStats and VM.vehicleStats(model) end
        if entry.exists then
            row.onSelect = function() spawnModel(model) end
        else
            row.enabled = false
            row.description = 'Locked: your game files lack this model. DLC models need the server to stream them.'
        end
        rows[#rows + 1] = row
    end
    return rows
end

VM.define('vehicle_spawner_class', {
    title = 'Vehicle Spawner',
    subtitle = function(args) return className(args.key) end,
    build = function(args)
        local class = type(args) == 'table' and args.key
        if not VM.can('vehicle.spawn') or type(class) ~= 'number' then return {} end
        classRows[class] = classRows[class] or buildClassRows(class)
        local rows = {}
        for _, row in ipairs(classRows[class]) do
            rows[#rows + 1] = VM.modelRow(row, 'vehicle', row.key, 'vehicle.spawn')
        end
        return rows
    end,
})

-- Addon vehicles sorted into the 23 classes, plus the ones that are not streamed.
local function addonGroups()
    local groups, unavailable = {}, {}
    for _, model in ipairs(addonVehicles()) do
        local entry = info(model)
        if entry.exists then
            local class = entry.class or 0
            groups[class] = groups[class] or {}
            groups[class][#groups[class] + 1] = model
        else
            unavailable[#unavailable + 1] = model
        end
    end
    return groups, unavailable
end

local function addonRow(model, available)
    local name = addonName(model)
    local row = { key = model, label = name, rightLabel = ('(%s)'):format(model) }
    row.stats = function() return VM.vehicleStats and VM.vehicleStats(model) end
    if available then
        row.description = ('Spawn %s.'):format(name)
        row.onSelect = function() spawnModel(model) end
    else
        row.enabled = false
        row.description = 'Locked: this model is not loading. The server owner should check that it streams correctly.'
    end
    return VM.modelRow(row, 'vehicle', model, 'vehicle.spawn')
end

VM.define('vehicle_spawner_addons', {
    title = 'Addon Vehicles',
    subtitle = 'Spawn An Addon Vehicle',
    build = function()
        if not VM.can('vehicle.spawn') then return {} end
        local groups, unavailable = addonGroups()
        local items = {}
        for class = 0, 22 do
            local name = className(class)
            if groups[class] then
                items[#items + 1] = VM.submenu('vehicle_spawner_addon_class', name, ('Custom vehicles in the %s class.'):format(name),
                    { key = class }, { hideEmpty = false })
            else
                items[#items + 1] = VM.button(name, 'No custom vehicles belong to this class.', nil, { enabled = false, rightLabel = '' })
            end
        end
        if #unavailable > 0 then
            items[#items + 1] = VM.submenu('vehicle_spawner_addon_unavailable', 'Unavailable Vehicles',
                'Custom vehicles that fail to stream and so cannot spawn.', nil, { hideEmpty = false })
        end
        return items
    end,
})

VM.define('vehicle_spawner_addon_class', {
    title = 'Addon Spawner',
    subtitle = function(args) return className(args.key) end,
    build = function(args)
        if not VM.can('vehicle.spawn') then return {} end
        local items = {}
        for _, model in ipairs(addonGroups()[type(args) == 'table' and args.key] or {}) do items[#items + 1] = addonRow(model, true) end
        return items
    end,
})

VM.define('vehicle_spawner_addon_unavailable', {
    title = 'Addon Spawner',
    subtitle = 'Unavailable Vehicles',
    build = function()
        if not VM.can('vehicle.spawn') then return {} end
        local _, unavailable = addonGroups()
        local items = {}
        for _, model in ipairs(unavailable) do items[#items + 1] = addonRow(model, false) end
        return items
    end,
})

-- ---------------------------------------------------------------------------
-- Saved Vehicles (SavedVehicles.cs). Cortex keys saves by id; the summary cache
-- carries id, name, model and modelLabel.

local SAVED_IDS = { 'vehicle.personal', 'vehicle.savePersonal', 'vehicle.removePersonal' }

local function savedVehicles()
    local list = Admin.getPersonalVehiclesCache and Admin.getPersonalVehiclesCache()
    return type(list) == 'table' and list or {}
end

local function savedVehicle(id)
    if id == nil then return nil end
    for _, entry in ipairs(savedVehicles()) do
        if entry.id == id then return entry end
    end
end

local function savedLabel(entry)
    if type(entry.modelLabel) == 'string' and entry.modelLabel ~= '' then return entry.modelLabel end
    local model = info(entry.model)
    return model.label or model.display
end

-- vMenu re-reads its saves when these menus open (UpdateMenuAvailableCategories).
local function reloadSaved()
    if not Admin.refreshPersonalVehiclesCache then return end
    CreateThread(function()
        Admin.refreshPersonalVehiclesCache()
        VM.refresh()
    end)
end

local function saveCurrentVehicle()
    if VM.denied('vehicle.savePersonal') then return end
    if not IsPedInAnyVehicle(PlayerPedId(), false) then
        VM.notify('error', 'Get in a vehicle first; you are not in any vehicle to save.')
        return
    end
    local name = VM.input('Name for this save', nil, 30)
    if not name or name == '' then
        VM.notify('error', 'Not saved: the name was empty or the prompt was closed.')
        return
    end
    -- Cortex would overwrite a save with the same name; vMenu refuses it.
    for _, entry in ipairs(savedVehicles()) do
        if type(entry.name) == 'string' and entry.name:lower() == name:lower() then
            VM.notify('error', ('Not saved: a save called %s already exists. Pick another name.'):format(name))
            return
        end
    end
    VM.execute('vehicle.savePersonal', { name = name })
end

VM.define('saved_vehicles', {
    title = 'Saved Vehicles',
    subtitle = 'Select from class or custom category',
    onOpen = reloadSaved,
    build = function()
        if not VM.canAny(SAVED_IDS) then return {} end
        return {
            VM.can('vehicle.savePersonal') and VM.button('Save Current Vehicle', 'Store the vehicle you are in, with its current setup, under a name.', saveCurrentVehicle) or nil,
            VM.submenu('saved_vehicles_classes', 'Vehicle Class', 'Browse saved vehicles grouped by class.', nil, { hideEmpty = false }),
        }
    end,
})

local function savedByClass()
    local classes, missing = {}, {}
    for _, entry in ipairs(savedVehicles()) do
        local model = info(entry.model)
        if model.exists then
            local class = model.class or 0
            classes[class] = classes[class] or {}
            classes[class][#classes[class] + 1] = entry
        else
            missing[#missing + 1] = entry
        end
    end
    return classes, missing
end

VM.define('saved_vehicles_classes', {
    title = 'Saved Vehicles',
    subtitle = 'Manage Saved Vehicles',
    onOpen = reloadSaved,
    build = function()
        if not VM.canAny(SAVED_IDS) then return {} end
        local classes = savedByClass()
        local items = {}
        for class = 0, 22 do
            local name = className(class)
            if classes[class] then
                items[#items + 1] = VM.submenu('saved_vehicles_class', name, ('Your saves in the %s class.'):format(name),
                    { key = class }, { hideEmpty = false })
            else
                items[#items + 1] = VM.button(name, ('None of your saves are in the %s class.'):format(name), nil,
                    { enabled = false, rightLabel = '' })
            end
        end
        items[#items + 1] = VM.submenu('saved_vehicles_missing', 'Unavailable Saved Vehicles',
            'Saves whose models the game cannot load, usually because the server no longer streams them.',
            nil, { hideEmpty = false })
        return items
    end,
})

VM.define('saved_vehicles_class', {
    title = 'Saved Vehicles',
    subtitle = function(args) return className(args.key) end,
    build = function(args)
        if not VM.canAny(SAVED_IDS) then return {} end
        local source = savedByClass()[type(args) == 'table' and args.key] or {}
        local list = table.move(source, 1, #source, 1, {})
        table.sort(list, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
        local items = {}
        for _, entry in ipairs(list) do
            items[#items + 1] = VM.submenu('saved_vehicle', tostring(entry.name), 'Spawn, overwrite or delete this save.', { key = entry.id },
                { key = 'saved:' .. tostring(entry.id), rightLabel = ('(%s) →→→'):format(savedLabel(entry)), hideEmpty = false })
        end
        return items
    end,
})

local missingArmed
VM.define('saved_vehicles_missing', {
    title = 'Missing Vehicles',
    subtitle = 'Unavailable Saved Vehicles',
    onClose = function() missingArmed = nil end,
    buttons = function()
        if not VM.can('vehicle.removePersonal') then return nil end
        return { { control = 214, label = 'Delete Vehicle!', run = function(_, item)
            local id = item and item.savedId
            if id == nil then VM.notify('error', 'No unavailable saves are left to delete.'); return end
            if missingArmed ~= id then missingArmed = id; return end
            missingArmed = nil
            if VM.execute('vehicle.removePersonal', { id = id }) ~= false then VM.back() end
        end } }
    end,
    build = function()
        if not VM.canAny(SAVED_IDS) then return {} end
        local _, missing = savedByClass()
        local items = {}
        for _, entry in ipairs(missing) do
            items[#items + 1] = { key = 'missing:' .. tostring(entry.id), label = tostring(entry.name), enabled = false, savedId = entry.id,
                rightLabel = missingArmed == entry.id and '~r~Press again' or ('(%s)'):format(savedLabel(entry)), description = MISSING_MODEL }
        end
        return items
    end,
})

-- Replace and Delete need a second press; any other button cancels it (SavedVehicles.cs:519-570).
local armed = {}
local function disarm() armed.id, armed.button = nil, nil end
local function arm(id, button)
    if armed.id == id and armed.button == button then disarm(); return true end
    armed.id, armed.button = id, button
    return false
end
local function armedLabel(id, button) return (armed.id == id and armed.button == button) and 'Press once more to go ahead.' or nil end

VM.define('saved_vehicle', {
    title = 'Manage Vehicle',
    subtitle = function(args)
        local entry = savedVehicle(type(args) == 'table' and args.key)
        return entry and ('%s (%s)'):format(entry.name, savedLabel(entry)) or 'Saved vehicle'
    end,
    onClose = disarm,
    build = function(args)
        local entry = savedVehicle(type(args) == 'table' and args.key)
        if not entry then return {} end
        local id, model = entry.id, info(entry.model)
        return {
            VM.can('vehicle.personal') and VM.modelRow(VM.button('Spawn Vehicle', model.exists and 'Bring this save into the world.' or MISSING_MODEL, function()
                disarm()
                VM.execute('vehicle.personal', { id = id })
            end, { enabled = model.exists, rightLabel = ('(%s)'):format(tostring(model.display):lower()) }), 'vehicle', entry.model, 'vehicle.personal') or nil,
            VM.can('vehicle.savePersonal') and VM.button('~r~Replace Vehicle',
                'Overwrite this save with the vehicle you are in now. ~r~The old save is lost for good.', function()
                if not IsPedInAnyVehicle(PlayerPedId(), false) then
                    disarm()
                    VM.notify('error', 'Get in a vehicle first; it is what overwrites this save.')
                    return
                end
                if not arm(id, 'replace') then
                    VM.notify('info', 'Press Replace Vehicle once more to overwrite this save.')
                    return
                end
                if VM.execute('vehicle.savePersonal', { id = id, name = entry.name }) ~= false then VM.close() end
            end, { key = 'replace', rightLabel = armedLabel(id, 'replace') }) or nil,
            VM.can('vehicle.removePersonal') and VM.button('~r~Delete Vehicle', '~r~Erase this save for good. It cannot be restored.', function()
                if not arm(id, 'delete') then
                    VM.notify('info', 'Press Delete Vehicle once more to erase this save.')
                    return
                end
                if VM.execute('vehicle.removePersonal', { id = id }) ~= false then VM.back() end
            end, { key = 'delete', rightLabel = armedLabel(id, 'delete') }) or nil,
        }
    end,
})

-- ---------------------------------------------------------------------------
-- Personal Vehicle (PersonalVehicle.cs)

local currentName -- shown as "Current Vehicle: <name>" after Set Vehicle succeeds

local function setPersonalVehicle()
    if VM.denied('vehicle.personalSet') then return end
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if VM.execute('vehicle.personalSet', {}) == true and vehicle ~= 0 then
        local model = info(GetEntityModel(vehicle))
        currentName = model.label or model.display
    end
end

VM.define('personal_vehicle', {
    subtitle = 'Personal Vehicle Options',
    build = function()
        if not VM.can('vehicle.personalSet') then return {} end
        return {
            VM.button('Set Vehicle', 'Mark the vehicle you are in as your personal vehicle, replacing any earlier choice.',
                setPersonalVehicle, { rightLabel = ('Current Vehicle: %s'):format(currentName or 'None') }),
            VM.action('vehicle.personalEngine', 'Toggle Engine', 'Start or stop the engine remotely. Fails while another player is driving it.', {}),
            VM.select('vehicle.personalLights', 'Set Vehicle Lights', 'Force the headlights on or off, or hand them back to the game. The engine must be running.', {
                values = { { label = 'Force On', value = 2 }, { label = 'Force Off', value = 1 }, { label = 'Reset', value = 0 } },
            }),
            VM.select('vehicle.personalStance', 'Vehicle Stance', 'Pick the ride height for your personal vehicle.', {
                values = { 'Default', 'Lowered' },
                onSelect = function(position)
                    if VM.denied('vehicle.personalStance') then return end
                    Admin.selectAction('vehicle.personalStance', position == 2)
                end,
            }),
            VM.action('vehicle.personalKickPassengers', 'Kick Passengers', 'Eject every passenger from your personal vehicle.', {}),
            VM.action('vehicle.personalLock', 'Lock Vehicle Doors', 'Lock every door against all players. People already inside can still get out.', {}),
            VM.action('vehicle.personalUnlock', 'Unlock Vehicle Doors', 'Unlock every door so any player can get in.', {}),
            VM.can('vehicle.personalDoors') and VM.submenu('personal_vehicle_doors', 'Vehicle Doors', 'Control each door, the hood and the trunk, or detach them.') or nil,
            VM.action('vehicle.personalHorn', 'Sound Horn', 'Honk the horn from wherever you are.', {}),
            VM.action('vehicle.personalAlarm', 'Toggle Alarm Sound', 'Start or silence the alarm noise. It does not arm an alarm system.', {}),
            VM.toggle('vehicle.personalBlip', 'Add Blip For Personal Vehicle', 'Show your personal vehicle on the map.'),
            VM.toggle('vehicle.personalExclusive', 'Exclusive Driver', 'Reserve the driver seat for yourself. Other players may still ride as passengers.'),
        }
    end,
})

local function door(label, description, command)
    return VM.button(label, description, function()
        if VM.denied('vehicle.personalDoors') then return end
        Admin.selectAction('vehicle.personalDoors', command)
    end)
end

VM.define('personal_vehicle_doors', {
    title = 'Vehicle Doors',
    subtitle = 'Vehicle Doors Management',
    build = function()
        if not VM.can('vehicle.personalDoors') then return {} end
        return {
            door('Left Front Door', 'Swing the front left door open or shut.', 'toggle_0'),
            door('Right Front Door', 'Swing the front right door open or shut.', 'toggle_1'),
            door('Left Rear Door', 'Swing the rear left door open or shut.', 'toggle_2'),
            door('Right Rear Door', 'Swing the rear right door open or shut.', 'toggle_3'),
            door('Hood', 'Raise or lower the hood.', 'toggle_4'),
            door('Trunk', 'Raise or lower the trunk lid.', 'toggle_5'),
            door('Extra 1', 'Work the first extra door, which few vehicles have.', 'toggle_6'),
            door('Extra 2', 'Work the second extra door, which few vehicles have.', 'toggle_7'),
            door('Bomb Bay', 'Work the bomb bay doors on planes that have them.', 'bomb_bay'),
            door('Open All Doors', 'Swing every door, the hood and the trunk open.', 'open_all'),
            door('Close All Doors', 'Shut every door, the hood and the trunk.', 'close_all'),
            VM.select('vehicle.personalDoors', 'Remove Door', 'Detach one door from the vehicle.', {
                key = 'remove_door',
                values = { 'Front Left', 'Front Right', 'Rear Left', 'Rear Right', 'Hood', 'Trunk', 'Extra 1', 'Extra 2', 'Bomb Bay' },
                onSelect = function(position)
                    if VM.denied('vehicle.personalDoors') then return end
                    -- vMenu breaks "door 8" for Bomb Bay, which is no door; Cortex accepts remove_0..7 only.
                    if position <= 8 then Admin.selectAction('vehicle.personalDoors', ('remove_%d'):format(position - 1)) end
                end,
            }),
            VM.toggle('vehicle.deleteRemovedDoors', 'Delete Removed Doors', 'Make detached doors vanish instead of dropping to the ground.'),
        }
    end,
})
