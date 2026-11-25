-- vMenu mode: Player Appearance and MP Ped Customization, in vMenu 3.8.67's
-- labels and order (vMenu/menus/PlayerAppearance.cs, MpPedCustomization.cs).
-- Lists read the live ped and write through Admin.setPedAppearance, the setter
-- behind the Character Studio (player.setAppearance). Models, saves and loads
-- run the player.* actions with the payloads the Cortex panel sends.
local Admin = EsAdmin
local VM = Admin.VmenuMode

local EDIT = 'player.setAppearance'
local SAVE_MP = 'player.saveMpPed'
local CHARACTER_ACTIONS = { 'player.loadMpPed', SAVE_MP, 'player.setDefaultSavedPed' }
local CTRL = 36 -- INPUT_DUCK: Ctrl+Enter on a list asks for an ID, as in vMenu
local INVALID_INPUT = 'Nothing was entered, or the prompt was closed. Try again.'
local INVALID_NAME = 'That name cannot be used. Enter a different one.'
local NAME_EXISTS = 'A save with that name already exists. Pick another name.'
local FEMALE_LOCKED = 'Female characters cannot use this option.'

-- Ped models and names are generated from GTA V game data (client/game_catalogs.lua):
-- the story and freemode peds, animals, then male, female and other peds by model prefix.
local PEDS = EsAdminGameCatalogs and EsAdminGameCatalogs.peds or {}

local function ped() return PlayerPedId() end
local function ctrlHeld() return IsControlPressed(0, CTRL) or IsDisabledControlPressed(0, CTRL) end
local function byName(a, b) return a:lower() < b:lower() end
local function present(value) return type(value) == 'string' and value ~= '' end

-- The engine remembers list positions by item key. Keys carry the live value and
-- an edit counter, so a list shows the ped as it is now, not a stale position.
local edits = 0
local function live(item, position)
    item.key = ('%s#%s#%d'):format(item.label, tostring(position), edits)
    if item.kind == 'slider' then item.value = position else item.index = position end
    return item
end

local function list(label, values, description, position, onChange, onSelect)
    return live({ kind = 'list', label = label, values = values, description = description,
        onChange = onChange, onSelect = onSelect }, position)
end

local function slider(label, description, maximum, value, onChange)
    return live({ kind = 'slider', label = label, description = description, min = 0, max = maximum, onChange = onChange }, value)
end

local function apply(data)
    edits = edits + 1
    if VM.denied(EDIT) then return false end
    Admin.setPedAppearance(data)
    return true
end

local lists = {}
local function numbered(format, count, first)
    first = first or 1
    local key = ('%s|%d|%d'):format(format, count, first)
    if not lists[key] then
        local values = {}
        for i = 1, count do values[i] = format:format(i - 1 + first, count) end
        lists[key] = values
    end
    return lists[key]
end

-- A disabled, centred heading row.
local function spacer(title)
    local length = utf8.len(title) or #title
    local pad = math.max((80 - length) // 2 - length // 2, 0)
    return { key = 'spacer:' .. title, label = '~h~' .. string.rep(' ', pad) .. title, description = '', enabled = false }
end

local function askId(title, minimum, maximum)
    local value = tonumber(VM.input(title, nil, 5))
    if not value or value ~= math.floor(value) or value < minimum or value > maximum then
        VM.notify('error', 'Invalid input')
        return nil
    end
    return math.floor(value)
end

local function cycleComponent(id, drawable)
    local p = ped()
    local texture = math.max(GetPedTextureVariation(p, id), 0)
    local last = GetNumberOfPedTextureVariations(p, id, drawable) - 1
    apply({ type = 'component', id = id, drawable = drawable, texture = texture < last and texture + 1 or 0 })
end

local function cycleProp(id)
    local p = ped()
    local drawable = GetPedPropIndex(p, id)
    if drawable < 0 then return end
    local texture = math.max(GetPedPropTextureIndex(p, id), 0)
    local last = GetNumberOfPedPropTextureVariations(p, id, drawable) - 1
    apply({ type = 'prop', id = id, drawable = drawable, texture = texture < last and texture + 1 or 0 })
end

-- ---------------------------------------------------------------------------
-- Player Appearance

local COMPONENT_NAMES = { 'Head', 'Mask / Facial Hair', 'Hair Style / Color', 'Hands / Upper Body', 'Legs / Pants',
    'Bags / Parachutes', 'Shoes', 'Neck / Scarfs', 'Shirt / Accessory', 'Body Armor / Accessory 2', 'Badges / Logos',
    'Shirt Overlay / Jackets' }
local PROP_IDS = { 0, 1, 2, 6, 7 }
local PROP_NAMES = { 'Hats / Helmets', 'Glasses', 'Misc', 'Watches', 'Bracelets' }

local function savePed()
    if VM.denied('player.savePed') then return end
    local name = VM.input('Name for this ped save', nil, 30)
    if not present(name) then VM.notify('error', INVALID_INPUT); return end
    if present(GetResourceKvpString('ped_' .. name)) then
        VM.notify('error', 'A ped save with that name already exists. Pick another name.')
        return
    end
    VM.execute('player.savePed', { name = name })
end

VM.define('player_appearance_customize', {
    subtitle = 'Customize Saved Ped',
    build = function()
        if not VM.can(EDIT) then return {} end
        local p, rows = ped(), {}
        for id = 0, 11 do
            local count = GetNumberOfPedDrawableVariations(p, id)
            if count > 0 then
                local name = COMPONENT_NAMES[id + 1]
                rows[#rows + 1] = list(name, numbered('Drawable #%d (of %d)', count),
                    ('Arrows pick the ~o~%s~s~ drawable, ~r~enter~s~ moves to its next texture.'):format(name),
                    GetPedDrawableVariation(p, id) + 1,
                    function(position) apply({ type = 'component', id = id, drawable = position - 1, texture = 0 }) end,
                    function(position)
                        if ctrlHeld() then
                            local drawable = askId('Enter Drawable ID', 1, count)
                            if drawable then apply({ type = 'component', id = id, drawable = drawable - 1, texture = 0 }) end
                            return
                        end
                        cycleComponent(id, position - 1)
                    end)
            end
        end
        for index, id in ipairs(PROP_IDS) do
            local count = GetNumberOfPedPropDrawableVariations(p, id)
            if count > 0 then
                local name = PROP_NAMES[index]
                -- Position 1 is "no prop", position n + 1 is prop n - 1.
                rows[#rows + 1] = list(name, numbered('Prop #%d (of %d)', count + 1),
                    ('Arrows pick the ~o~%s~s~ drawable, ~r~enter~s~ moves to its next texture.'):format(name),
                    GetPedPropIndex(p, id) + 2,
                    function(position) apply({ type = 'prop', id = id, drawable = position - 2, texture = 0 }) end,
                    function()
                        if ctrlHeld() then
                            local prop = askId('Enter Prop ID', 1, count + 1)
                            if prop then apply({ type = 'prop', id = id, drawable = prop - 2, texture = 0 }) end
                            return
                        end
                        cycleProp(id)
                    end)
            end
        end
        return rows
    end,
})

-- Ped Collections: collection-local indexes resolve to global drawables, which
-- the Cortex setter applies.
local function collectionsSupported()
    return type(GetPedCollectionsCount) == 'function' and type(GetPedCollectionName) == 'function'
        and type(GetNumberOfPedCollectionDrawableVariations) == 'function'
        and type(GetPedDrawableGlobalIndexFromCollection) == 'function'
        and type(GetPedPropGlobalIndexFromCollection) == 'function'
end

local function nameOf(collection) return collection == 'Base Collection' and '' or collection end

local function drawableCollection(p, id)
    local drawable = GetPedDrawableVariation(p, id)
    local nameNative = GetPedCollectionNameFromDrawable or GetPedDrawableCollectionName
    local indexNative = GetPedCollectionLocalIndexFromDrawable or GetPedDrawableCollectionLocalIndex
    if not nameNative or not indexNative then return nil, -1 end
    return nameNative(p, id, drawable) or '', indexNative(p, id, drawable)
end

local function propCollection(p, id)
    local drawable = GetPedPropIndex(p, id)
    if drawable < 0 or not GetPedCollectionNameFromProp or not GetPedCollectionLocalIndexFromProp then return nil, -1 end
    return GetPedCollectionNameFromProp(p, id, drawable) or '', GetPedCollectionLocalIndexFromProp(p, id, drawable)
end

local collectionCache = {}
local function collectionDrawables(p, collection, id, total)
    local key = ('%s|%s|%d'):format(tostring(GetEntityModel(p)), collection, id)
    local cached = collectionCache[key]
    if cached and cached.total == total then return cached end
    local values, valid, withNone = {}, {}, {}
    for i = 0, total - 1 do
        local ok = (type(IsPedCollectionComponentVariationValid) ~= 'function' or IsPedCollectionComponentVariationValid(p, id, collection, i, 0))
            and not (type(IsPedCollectionComponentVariationGen9Exclusive) == 'function' and IsPedCollectionComponentVariationGen9Exclusive(p, id, collection, i))
        valid[i + 1] = ok and true or false
        values[i + 1] = ('Drawable #%d%s (of %d)'):format(i + 1, ok and '' or ' (Invalid)', total)
        withNone[i + 1] = values[i + 1]
    end
    withNone[total + 1] = ('None Selected (of %d)'):format(total)
    cached = { total = total, values = values, withNone = withNone, valid = valid }
    collectionCache[key] = cached
    return cached
end

local function collectionProps(total)
    local key = 'collection-props|' .. total
    if not lists[key] then
        local values = { ('None Selected (of %d)'):format(total) }
        for i = 1, total do values[i + 1] = ('Prop #%d (of %d)'):format(i, total) end
        lists[key] = values
    end
    return lists[key]
end

local originals, notes = {}, {}
local COLLECTION_HINT = 'Arrows change the drawable, ~r~enter~s~ steps through its textures. '
local NOT_IN_COLLECTION = 'The worn item comes from another collection.'

VM.define('player_appearance_collections', {
    subtitle = 'Ped Collections',
    build = function()
        if not VM.can(EDIT) or not collectionsSupported() then return {} end
        local p, rows = ped(), {}
        -- In reverse, so the newest collections are at the top.
        for i = GetPedCollectionsCount(p) - 1, 0, -1 do
            local name = i == 0 and 'Base Collection' or GetPedCollectionName(p, i)
            rows[#rows + 1] = VM.submenu('player_appearance_collection', name, ('Clothing and props from the "%s" collection.'):format(name),
                { key = name }, { rightLabel = ('(#%d)'):format(i), hideEmpty = false })
        end
        return rows
    end,
})

VM.define('player_appearance_collection', {
    subtitle = function(args) return args.key end,
    onOpen = function(args)
        local p, original = ped(), { components = {}, props = {} }
        for id = 0, 11 do original.components[id] = { GetPedDrawableVariation(p, id), GetPedTextureVariation(p, id) } end
        for _, id in ipairs(PROP_IDS) do original.props[id] = { GetPedPropIndex(p, id), GetPedPropTextureIndex(p, id) } end
        originals[args.key] = original
        notes = {}
    end,
    build = function(args)
        if not VM.can(EDIT) or not collectionsSupported() then return {} end
        local p, rows, collection = ped(), {}, nameOf(args.key)
        for id = 0, 11 do
            local total = GetNumberOfPedCollectionDrawableVariations(p, id, collection)
            if total > 0 then
                local data = collectionDrawables(p, collection, id, total)
                local current, localIndex = drawableCollection(p, id)
                local values, position, suffix
                if current == collection and localIndex >= 0 then
                    values, position = data.values, localIndex + 1
                    suffix = ('Texture %d of %d.'):format(GetPedTextureVariation(p, id) + 1,
                        GetNumberOfPedCollectionTextureVariations(p, id, collection, localIndex))
                else
                    values, position, suffix = data.withNone, total + 1, NOT_IN_COLLECTION
                end
                local note = notes[id]
                rows[#rows + 1] = list(COMPONENT_NAMES[id + 1], values, COLLECTION_HINT .. (note or suffix), position,
                    function(selected)
                        if selected > total then
                            notes[id] = nil
                            local original = (originals[args.key] or { components = {} }).components[id]
                            if original then apply({ type = 'component', id = id, drawable = original[1], texture = original[2] }) end
                        elseif not data.valid[selected] then
                            notes[id] = 'This drawable cannot be used here (broken or Gen9 only).' -- no edit: the list stays on it
                        else
                            notes[id] = nil
                            apply({ type = 'component', id = id, texture = 0,
                                drawable = GetPedDrawableGlobalIndexFromCollection(ped(), id, collection, selected - 1) })
                        end
                    end,
                    function(selected)
                        if selected > total or not data.valid[selected] then return end
                        local target = ped()
                        local texture = math.max(GetPedTextureVariation(target, id), 0)
                        local last = GetNumberOfPedCollectionTextureVariations(target, id, collection, selected - 1) - 1
                        apply({ type = 'component', id = id, texture = texture < last and texture + 1 or 0,
                            drawable = GetPedDrawableGlobalIndexFromCollection(target, id, collection, selected - 1) })
                    end)
            end
        end
        for index, id in ipairs(PROP_IDS) do
            local total = type(GetNumberOfPedCollectionPropDrawableVariations) == 'function'
                and GetNumberOfPedCollectionPropDrawableVariations(p, id, collection) or 0
            if total > 0 then
                local current, localIndex = propCollection(p, id)
                local position, suffix = 1, NOT_IN_COLLECTION
                if current == collection and localIndex >= 0 then
                    position = localIndex + 2
                    suffix = ('Texture %d of %d.'):format(GetPedPropTextureIndex(p, id) + 1,
                        GetNumberOfPedCollectionPropTextureVariations(p, id, collection, localIndex))
                end
                rows[#rows + 1] = list(PROP_NAMES[index], collectionProps(total), COLLECTION_HINT .. suffix, position,
                    function(selected)
                        if selected == 1 then
                            local original = (originals[args.key] or { props = {} }).props[id]
                            if original then apply({ type = 'prop', id = id, drawable = original[1], texture = math.max(original[2], 0) }) end
                            return
                        end
                        apply({ type = 'prop', id = id, texture = 0,
                            drawable = GetPedPropGlobalIndexFromCollection(ped(), id, collection, selected - 2) })
                    end,
                    function(selected)
                        if selected == 1 then return end
                        local target = ped()
                        local texture = math.max(GetPedPropTextureIndex(target, id), 0)
                        local count = GetNumberOfPedCollectionPropTextureVariations(target, id, collection, selected - 2)
                        apply({ type = 'prop', id = id, texture = texture + 1 < count and texture + 1 or 0,
                            drawable = GetPedPropGlobalIndexFromCollection(target, id, collection, selected - 2) })
                    end)
            end
        end
        return rows
    end,
})

-- Saved Peds: PlayerAppearance's ped_<name> saves, the keys player.savePed writes.
local savedPeds
local function loadSavedPeds()
    local names, handle = {}, StartFindKvp('ped_')
    if handle and handle ~= -1 then
        while true do
            local key = FindKvp(handle)
            if not present(key) then break end
            names[#names + 1] = key:sub(5)
        end
        EndFindKvp(handle)
    end
    table.sort(names, byName)
    savedPeds = names
end

local function cloneSavedPed(args)
    if VM.denied('player.savePed') then return end
    local name = VM.input(('Name for the copy of %s'):format(args.key), args.key, 30)
    if not present(name) then VM.notify('error', INVALID_NAME); return end
    if present(GetResourceKvpString('ped_' .. name)) then VM.notify('error', NAME_EXISTS); return end
    local data = GetResourceKvpString('ped_' .. args.key)
    if not present(data) then VM.notify('error', 'Saved ped not found.'); return end
    SetResourceKvp('ped_' .. name, data)
    if GetResourceKvpString('ped_' .. name) ~= data then VM.notify('error', 'Failed to clone saved ped.'); return end
    loadSavedPeds()
    VM.notify('success', ('Copied the saved ped as %s.'):format(name))
end

local function renameSavedPed(args)
    if VM.denied('player.savePed') then return end
    local name = VM.input(('New name for %s'):format(args.key), args.key, 30)
    if not present(name) then VM.notify('error', INVALID_NAME); return end
    if name == args.key then
        VM.notify('error', 'The new name matches the current one. Enter a different name.')
        return
    end
    if present(GetResourceKvpString('ped_' .. name)) then VM.notify('error', NAME_EXISTS); return end
    local data = GetResourceKvpString('ped_' .. args.key)
    if not present(data) then VM.notify('error', 'Saved ped not found.'); return end
    SetResourceKvp('ped_' .. name, data)
    if GetResourceKvpString('ped_' .. name) ~= data then VM.notify('error', 'Failed to rename saved ped.'); return end
    DeleteResourceKvp('ped_' .. args.key)
    if GetResourceKvpString('ped_' .. args.key) then
        DeleteResourceKvp('ped_' .. name)
        VM.notify('error', 'Failed to remove the old save.'); return
    end
    args.key = name -- the open menu follows the rename, as vMenu retitles it
    loadSavedPeds()
    VM.notify('success', ('Saved ped renamed to %s.'):format(name))
end

local function deleteSavedPed(args)
    if VM.denied('player.savePed') then return end
    DeleteResourceKvp('ped_' .. args.key)
    if GetResourceKvpString('ped_' .. args.key) then VM.notify('error', 'Failed to delete saved ped.'); return end
    loadSavedPeds()
    VM.notify('success', 'Saved ped removed.')
    VM.back()
end

VM.define('player_appearance_saved', {
    subtitle = 'Saved Peds',
    onOpen = function() loadSavedPeds() end,
    build = function()
        if not VM.canAny({ 'player.loadPed', 'player.savePed' }) then return {} end
        local rows = {}
        for _, name in ipairs(savedPeds or {}) do
            rows[#rows + 1] = VM.submenu('player_appearance_saved_ped', name, 'Spawn, copy, rename, overwrite or remove this save.', { key = name }, { hideEmpty = false })
        end
        return rows
    end,
})

VM.define('player_appearance_saved_ped', {
    title = 'Saved Ped',
    subtitle = function(args) return args.key end,
    build = function(args)
        local spawn = VM.can('player.loadPed')
        local manage = VM.can('player.savePed')
        return {
            VM.button('Spawn Saved Ped', spawn and 'Become the ped stored in this save.' or 'Your permissions do not include loading saved peds.', function()
                if VM.denied('player.loadPed') then return end
                VM.execute('player.loadPed', { name = args.key })
            end, { enabled = spawn, icon = not spawn and 'lock' or nil }),
            manage and VM.button('Clone Saved Ped', 'Make a copy of this save under a new name.', function() cloneSavedPed(args) end) or nil,
            manage and VM.button('Rename Saved Ped', 'Give this save a new name.', function() renameSavedPed(args) end, { icon = 'warning' }) or nil,
            manage and VM.button('~r~Replace Saved Ped', 'Overwrite this save with the ped you have now. This is permanent.', function()
                if VM.denied('player.savePed') then return end
                VM.execute('player.savePed', { name = args.key })
            end, { confirm = true, icon = 'warning' }) or nil,
            manage and VM.button('~r~Delete Saved Ped', 'Remove this save permanently.', function() deleteSavedPed(args) end,
                { confirm = true, icon = 'warning' }) or nil,
        }
    end,
})

-- Spawn Peds
-- Sea animals die on land; checked for every spawn path, including typed names.
local AQUATIC = { a_c_dolphin = true, a_c_fish = true, a_c_humpback = true, a_c_killerwhale = true, a_c_sharkhammer = true,
    a_c_sharktiger = true, a_c_stingray = true }

local function spawnModel(model)
    if VM.denied('player.setModel') then return end
    if AQUATIC[tostring(model):lower()] and not IsEntityInWater(ped()) then
        VM.notify('error', 'Sea animals die instantly on land, so get in water before choosing this one.')
        return
    end
    VM.execute('player.setModel', { model = model })
end

local function spawnByName()
    if VM.denied('player.setModel') then return end
    local model = VM.input('Model name of the ped', nil, 30)
    if not present(model) then VM.notify('error', INVALID_INPUT); return end
    spawnModel(model)
end

-- Addon peds come from the imported vMenu addons.json; read once per menu open.
local addonRows
local function loadAddonPeds()
    local config = type(Admin.getVmenuImportedConfig) == 'function' and Admin.getVmenuImportedConfig() or {}
    local peds = type(config.addons) == 'table' and type(config.addons.peds) == 'table' and config.addons.peds or {}
    local names, seen = {}, {}
    for key, value in pairs(peds) do
        local name = type(key) == 'string' and key or value
        if present(name) and not seen[name] then seen[name], names[#names + 1] = true, name end
    end
    table.sort(names, byName)
    local rows = {}
    for _, name in ipairs(names) do
        local label = GetLabelText(name)
        if not present(label) or label == 'NULL' then label = name end
        local hash = joaat(name)
        local streamed = IsModelInCdimage(hash) and IsModelAPed(hash)
        rows[#rows + 1] = { key = name, label = name, rightLabel = ('(%s)'):format(label), enabled = streamed == true,
            icon = not streamed and 'lock' or nil,
            description = streamed and 'Switch to this addon model.'
                or 'This model is not streamed on the server. Owners should check the ped name and model files.',
            onSelect = function() spawnModel(name) end }
    end
    addonRows = rows
end

local PED_LISTS = {
    main = { title = 'Main Peds', data = PEDS.main or {} },
    animals = { title = 'Animals', data = PEDS.animals or {}, animal = true },
    male = { title = 'Male Peds', data = PEDS.male or {} },
    female = { title = 'Female Peds', data = PEDS.female or {} },
    other = { title = 'Other Peds', data = PEDS.other or {} },
}
local pedRows = {}
local function pedList(key)
    if pedRows[key] then return pedRows[key] end
    local source, rows = PED_LISTS[key], {}
    local description = source.animal and 'Turn into this animal.' or 'Switch to this ped model.'
    for _, entry in ipairs(source.data) do
        local model, name = entry[1], entry[2]
        if not EsAdminIsUnsafePlayerPedModel(model) then
            rows[#rows + 1] = { key = model, label = model, rightLabel = name ~= '' and ('(%s)'):format(name) or nil, description = description,
                onSelect = function() spawnModel(model) end }
        end
    end
    pedRows[key] = rows
    return rows
end

VM.define('player_appearance_peds', {
    title = function(args) return PED_LISTS[args.key].title end,
    subtitle = 'Spawn A Ped',
    buttons = function(args)
        if args.key ~= 'male' and args.key ~= 'female' and args.key ~= 'other' then return nil end
        return { VM.filterButton('Model name to filter by (empty clears the filter)') }
    end,
    build = function(args)
        if not VM.can('player.setModel') or not PED_LISTS[args.key] then return {} end
        local rows = {}
        for _, row in ipairs(pedList(args.key)) do rows[#rows + 1] = VM.modelRow(row, 'ped', row.key, 'player.setModel') end
        return rows
    end,
})

VM.define('player_appearance_addon_peds', {
    subtitle = 'Addon Peds',
    build = function()
        if not VM.can('player.setModel') then return {} end
        local rows = {}
        for _, row in ipairs(addonRows or {}) do rows[#rows + 1] = VM.modelRow(row, 'ped', row.key, 'player.setModel') end
        return rows
    end,
})

VM.define('player_appearance_spawn', {
    subtitle = 'Spawn Ped',
    onOpen = function() loadAddonPeds() end,
    build = function()
        if not VM.can('player.setModel') then return {} end
        local function category(key, label, description)
            return VM.submenu('player_appearance_peds', label, description, { key = key }, { hideEmpty = false })
        end
        return {
            VM.ace('vMenu.PlayerAppearance.AddonPeds', 'player.setModel') and addonRows and #addonRows > 0
                and VM.submenu('player_appearance_addon_peds', 'Addon Peds', 'Custom ped models this server streams.', nil, { hideEmpty = false }) or nil,
            VM.ace('vMenu.PlayerAppearance.SpawnNew', 'player.setModel') and VM.button('Spawn By Name', 'Spawn a ped by entering its model name.', spawnByName) or nil,
            category('main', 'Main Peds', 'Story protagonists and the freemode models.'),
            (not Admin.vmenuSetting or Admin.vmenuSetting('vmenu_enable_animals_spawn_menu', false)) and category('animals', 'Animals', "Play as an animal. ~r~Dying as an animal can crash your game or other players' games, and godmode does not stop it.") or nil,
            category('male', 'Male Peds', 'Male story, ambient and multiplayer models.'),
            category('female', 'Female Peds', 'Female story, ambient and multiplayer models.'),
            category('other', 'Other Peds', 'Animals and models without a gender.'),
        }
    end,
})

VM.define('player_appearance', {
    subtitle = 'Player Appearance',
    onOpen = function() loadAddonPeds() end,
    build = function()
        local customize = VM.can(EDIT)
        return {
            customize and VM.submenu('player_appearance_customize', 'Ped Customization', 'Change the clothing and props on your current ped.', nil, { hideEmpty = false }) or nil,
            customize and collectionsSupported() and VM.submenu('player_appearance_collections', 'Ped Collections',
                'Dress your ped from base game, DLC and custom clothing collections.', nil, { hideEmpty = false }) or nil,
            VM.action('player.savePed', 'Save Ped', 'Store your current ped and its full appearance under a name.',
                nil, { onSelect = savePed }),
            VM.canAny({ 'player.loadPed', 'player.savePed' })
                and VM.submenu('player_appearance_saved', 'Saved Peds', 'Peds you have stored, ready to load or manage.', nil, { hideEmpty = false }) or nil,
            VM.can('player.setModel') and VM.submenu('player_appearance_spawn', 'Spawn Peds',
                'Switch your player model, from the built-in lists or the server addons.', nil, { hideEmpty = false }) or nil,
            VM.select('player.walkingStyle', 'Walking Style',
                'How your ped walks. Apply it again after a model change or after loading a saved ped.'),
            VM.select('player.illuminatedClothing', 'Illuminated Clothing Style', 'Animation for clothing pieces that glow.'),
        }
    end,
})

-- ---------------------------------------------------------------------------
-- MP Ped Customization

local MALE_BASE = { { 3, 15 }, { 8, 15 }, { 11, 15 }, { 4, 61, 'random' }, { 6, 34 } }
local FEMALE_BASE = { { 3, 15 }, { 8, 14 }, { 4, 17, 'random' }, { 11, 18, 'same' }, { 6, 35 } }

-- vMenu's SetPlayerClothing: a fresh character starts in its base layer.
local function dressBase(male)
    local p, random = ped(), 0
    for _, piece in ipairs(male and MALE_BASE or FEMALE_BASE) do
        local texture = 0
        if piece[3] == 'random' then
            random = math.random(0, math.max(GetNumberOfPedTextureVariations(p, piece[1], piece[2]) - 1, 0))
            texture = random
        elseif piece[3] == 'same' then
            texture = random
        end
        Admin.setPedAppearance({ type = 'component', id = piece[1], drawable = piece[2], texture = texture })
    end
end

local function createCharacter(male)
    if VM.denied('player.setModel') then return end
    if Admin.beginVmenuCharacterEdit and not Admin.beginVmenuCharacterEdit() then return false end
    local model = male and 'mp_m_freemode_01' or 'mp_f_freemode_01'
    if VM.execute('player.setModel', { model = model }) == false then
        if Admin.finishVmenuCharacterEdit then Admin.finishVmenuCharacterEdit(false) end
        return false
    end
    if GetEntityModel(ped()) == joaat(model) and VM.can(EDIT) then dressBase(male) end
end

local characters, categories
local function loadCharacters()
    local ok, result = pcall(Admin.getSavedPeds)
    local entries = {}
    for _, entry in ipairs(ok and type(result) == 'table' and result or {}) do
        if type(entry) == 'table' and present(entry.name) then entries[#entries + 1] = entry end
    end
    table.sort(entries, function(a, b) return byName(a.name, b.name) end)
    local names, seen = {}, {}
    local function add(name, description)
        if not present(name) or name:lower() == 'uncategorized' then return end
        if not seen[name] then
            seen[name] = { name = name, description = '' }
            names[#names + 1] = seen[name]
        end
        if present(description) then seen[name].description = description end
    end
    local imported = type(Admin.getVmenuImportedCategories) == 'function' and Admin.getVmenuImportedCategories() or {}
    for _, entry in ipairs(type(imported.peds) == 'table' and imported.peds or {}) do
        local data = type(entry) == 'table' and entry.data
        if type(data) == 'table' then add(data.Name, data.Description) end
    end
    for _, entry in ipairs(entries) do add(entry.category) end
    table.sort(names, function(a, b) return byName(a.name, b.name) end)
    characters, categories = entries, names
end

-- Listing reaches into the vMenu bridge, so it runs off the menu thread.
local loadingCharacters = false
local function requestCharacters()
    if loadingCharacters then return end
    loadingCharacters = true
    CreateThread(function()
        loadCharacters()
        loadingCharacters = false
        VM.refresh()
    end)
end

local function characterNamed(name)
    loadCharacters()
    for _, entry in ipairs(characters) do
        if entry.name == name then return entry end
    end
end

local function saveCharacter(args)
    args = args or {}
    if VM.denied(SAVE_MP) then return end
    local model = GetEntityModel(ped())
    if model ~= joaat('mp_m_freemode_01') and model ~= joaat('mp_f_freemode_01') then
        VM.notify('error', 'Switch to an MP character before saving.'); return
    end
    local entry = args.entry
    local result
    if entry then
        result = VM.execute(SAVE_MP, { name = entry.name, entry = entry })
    else
        local name = VM.input('Name for this character', nil, 30)
        if not present(name) then VM.notify('error', INVALID_INPUT); return end
        if characterNamed(name) then
            VM.notify('error', ('Another character already uses the name %s.'):format(name))
            return
        end
        result = VM.execute(SAVE_MP, { name = name })
    end
    if result == false then return end
    if Admin.finishVmenuCharacterEdit then Admin.finishVmenuCharacterEdit(true) end
    requestCharacters()
    if not args.stay then VM.back() end
end

local function expressionRow()
    local action = VM.descriptor('player.facialExpression')
    if not action or not VM.can('player.facialExpression') then return nil end
    local style = type(Admin.getPedStyle) == 'function' and Admin.getPedStyle(ped()) or {}
    local position = 1
    for i, value in ipairs(action.values) do
        if value.value == style.FacialExpression then position = i end
    end
    local item = VM.select('player.facialExpression', 'Facial Expression', 'The expression your ped wears while standing idle.', {
        onChange = function(selected)
            edits = edits + 1
            if VM.denied('player.facialExpression') then return end
            Admin.selectAction('player.facialExpression', action.values[selected].value)
        end,
        onSelect = function() end, -- vMenu applies on change only
    })
    return live(item, position)
end

VM.define('mp_ped_create', {
    title = 'Create Character',
    subtitle = 'Create A New Character',
    onOpen = function() if Admin.openVmenuCharacterCamera then Admin.openVmenuCharacterCamera() end end,
    onClose = function()
        if Admin.closeVmenuCharacterCamera then Admin.closeVmenuCharacterCamera() end
        if Admin.finishVmenuCharacterEdit then Admin.finishVmenuCharacterEdit(false) end
    end,
    build = function(args)
        local edit = VM.can(EDIT)
        local function section(id, label, description, allowed)
            return allowed and VM.submenu(id, label, description, nil, { hideEmpty = false }) or nil
        end
        return {
            VM.action(SAVE_MP, 'Save Character', 'Store this character in your saved list.', nil, { onSelect = function() saveCharacter(args) end }),
            VM.action('player.randomizeMpFace', 'Randomize Character', 'Roll a random face and look.'),
            section('mp_ped_inheritance', 'Character Inheritance', 'Parents and how their features blend.', edit),
            section('mp_ped_appearance', 'Character Appearance', 'Hair, facial hair, makeup, skin details and eyes.', edit),
            section('mp_ped_face', 'Character Face Shape Options', 'Fine-tune nose, brows, cheeks, jaw, chin and neck.', VM.can('player.setFaceFeature')),
            section('mp_ped_tattoos', 'Character Tattoo Options', 'Tattoo and badge controls.', VM.can('player.clearPedTattoos')),
            section('mp_ped_clothes', 'Character Clothes', 'Outfit pieces: tops, legs, shoes and more.', edit),
            section('mp_ped_props', 'Character Props', 'Hats, glasses, ears, watches and bracelets.', edit),
            expressionRow(),
            VM.button('Exit Without Saving', 'Leave the creator and discard every change since the last save.', function() VM.back() end, { confirm = true }),
        }
    end,
})

-- Parent names in vMenu's order (Male_, Special_Male_, Female_, Special_Female_);
-- the list position is the head blend id, exactly as vMenu passes it.
local parentNames
local function parents()
    if parentNames then return parentNames end
    local names = {}
    for _, group in ipairs({ { 0, 'Male_', 'Male' }, { 2, 'Special_Male_', 'Male' }, { 1, 'Female_', 'Female' }, { 3, 'Special_Female_', 'Female' } }) do
        for i = 0, GetNumParentPedsOfType(group[1]) - 1 do
            local label = GetLabelText(group[2] .. i)
            if not present(label) or label:match('^%s*$') or label == 'NULL' then label = tostring(i) end
            names[#names + 1] = ('%s (%s)'):format(label, group[3])
        end
    end
    parentNames = names
    return names
end

local function headBlend(p)
    if type(readPedHeadBlendSafely) == 'function' then
        local ok, blend = pcall(readPedHeadBlendSafely, p)
        if ok and type(blend) == 'table' then return blend end
    end
    return { shapeFirstID = 0, shapeSecondID = 0, skinFirstID = 0, skinSecondID = 0, shapeMix = 0.5, skinMix = 0.5 }
end

local function tenths(value, maximum) return math.max(0, math.min(maximum, math.floor((tonumber(value) or 0) * 10 + 0.5))) end

VM.define('mp_ped_inheritance', {
    title = 'vMenu',
    subtitle = 'Character Inheritance Options',
    build = function()
        if not VM.can(EDIT) then return {} end
        local names, blend = parents(), headBlend(ped())
        local function parent(label, field, description)
            return list(label, names, description, (tonumber(blend[field]) or 0) + 1,
                function(position) apply({ type = 'blend', field = field, value = math.min(position - 1, 45) }) end)
        end
        local function mix(label, field, description)
            return slider(label, description, 10, tenths(blend[field], 10),
                function(value) apply({ type = 'blend', field = field, value = value / 10 }) end)
        end
        return {
            parent('Parent #1', 'shapeFirstID', 'First parent for head shape.'),
            parent('Parent #1 Skin', 'skinFirstID', 'Skin tone taken from the first parent.'),
            parent('Parent #2', 'shapeSecondID', 'Second parent for head shape.'),
            parent('Parent #2 Skin', 'skinSecondID', 'Skin tone taken from the second parent.'),
            mix('Head Shape Mix', 'shapeMix', 'Balance of head shape between the parents. Far left is all Parent #1, far right is all Parent #2.'),
            mix('Body Skin Mix', 'skinMix', 'Balance of skin tone between the parents. Far left is all Parent #1, far right is all Parent #2.'),
        }
    end,
})

-- { overlay id, name, style description, opacity description, colour description }
local OVERLAYS = {
    { 0, 'Blemishes', 'Pick the facial blemish pattern.', 'How visible the blemishes are.' },
    { 1, 'Beard', 'Pick the beard or stubble.', 'How dense the beard looks.', 'Beard colour.', male = true },
    { 2, 'Eyebrows', 'Pick the eyebrow shape.', 'How dense the eyebrows look.', 'Eyebrow colour.' },
    { 3, 'Ageing', 'Pick the wrinkles and age lines.', 'How visible the ageing is.' },
    { 4, 'Makeup', 'Pick the eye makeup.', 'How strong the makeup is.', 'Makeup colour.' },
    { 5, 'Blush', 'Pick the blush shape.', 'How strong the blush is.', 'Blush colour.' },
    { 6, 'Complexion', 'Pick the skin complexion.', 'How strong the complexion is.' },
    { 7, 'Sun Damage', 'Pick the sun damage pattern.', 'How visible the sun damage is.' },
    { 8, 'Lipstick', 'Pick the lipstick finish.', 'How strong the lipstick is.', 'Lipstick colour.' },
    { 9, 'Moles and Freckles', 'Pick the moles and freckles pattern.', 'How visible the moles and freckles are.' },
    { 10, 'Chest Hair', 'Pick the chest hair pattern.', 'How dense the chest hair looks.', 'Chest hair colour.', male = true },
    { 11, 'Body Blemishes', 'Pick the body blemish pattern.', 'How visible the body blemishes are.' },
}
local OPACITY = { '0%', '10%', '20%', '30%', '40%', '50%', '60%', '70%', '80%', '90%', '100%' }

local function lock(item, locked)
    if locked then item.enabled, item.description, item.icon = false, FEMALE_LOCKED, 'lock' end
    return item
end

local function overlayState(p, id)
    local ok, success, _, _, color, _, opacity = pcall(GetPedHeadOverlayData, p, id)
    if not ok or not success then return 0, 0 end
    return tonumber(color) or 0, tonumber(opacity) or 0
end

VM.define('mp_ped_appearance', {
    title = 'vMenu',
    subtitle = 'Character Appearance Options',
    build = function()
        if not VM.can(EDIT) then return {} end
        local p = ped()
        local female = GetEntityModel(p) == joaat('mp_f_freemode_01')
        local colors = numbered('Color #%d', GetNumHairColors())
        local hairStyles = GetNumberOfPedDrawableVariations(p, 2)
        local rows = {
            list('Hair Style', numbered('Style #%d', hairStyles + 1), 'Pick the haircut.', GetPedDrawableVariation(p, 2) + 1,
                function(position)
                    local drawable = position - 1
                    if drawable >= GetNumberOfPedDrawableVariations(ped(), 2) then drawable = 0 end
                    apply({ type = 'component', id = 2, drawable = drawable, texture = 0 })
                end),
            list('Hair Color', colors, 'Main hair colour.', GetPedHairColor(p) + 1,
                function(position) apply({ type = 'color', colorType = 'hair', value = position - 1 }) end),
            list('Hair Highlight Color', colors, 'Colour of the highlights.', GetPedHairHighlightColor(p) + 1,
                function(position) apply({ type = 'color', colorType = 'hairHighlight', value = position - 1 }) end),
        }
        for _, overlay in ipairs(OVERLAYS) do
            local id, name = overlay[1], overlay[2]
            local locked = female and overlay.male
            local style = GetPedHeadOverlayValue(p, id)
            local color, opacity = overlayState(p, id)
            rows[#rows + 1] = lock(list(name .. ' Style', numbered('Style #%d', GetNumHeadOverlayValues(id)), overlay[3],
                (style == 255 and 0 or style) + 1,
                function(position) apply({ type = 'overlay', id = id, field = 'style', value = position - 1 }) end), locked)
            rows[#rows + 1] = lock(list(name .. ' Opacity', OPACITY, overlay[4], tenths(opacity, 10) + 1,
                function(position) apply({ type = 'overlay', id = id, field = 'opacity', value = (position - 1) / 10 }) end), locked)
            if overlay[5] then
                rows[#rows + 1] = lock(list(name .. ' Color', colors, overlay[5], color + 1,
                    function(position) apply({ type = 'color', colorType = 'overlay', id = id, value = position - 1 }) end), locked)
            end
        end
        rows[#rows + 1] = list('Eye Colors', numbered('Eye Color #%d', 32), 'Eye or contact lens colour.',
            math.min(math.max(GetPedEyeColor(p), 0), 31) + 1,
            function(position) apply({ type = 'color', colorType = 'eyes', value = position - 1 }) end)
        return rows
    end,
})

local FACE_FEATURES = { 'Nose Width', 'Noes Peak Height', 'Nose Peak Length', 'Nose Bone Height', 'Nose Peak Lowering',
    'Nose Bone Twist', 'Eyebrows Height', 'Eyebrows Depth', 'Cheekbones Height', 'Cheekbones Width', 'Cheeks Width',
    'Eyes Opening', 'Lips Thickness', 'Jaw Bone Width', 'Jaw Bone Depth/Length', 'Chin Height', 'Chin Depth/Length',
    'Chin Width', 'Chin Hole Size', 'Neck Thickness' }

VM.define('mp_ped_face', {
    title = 'vMenu',
    subtitle = 'Character Face Shape Options',
    build = function()
        if not VM.can('player.setFaceFeature') then return {} end
        local p, rows = ped(), {}
        for index, name in ipairs(FACE_FEATURES) do
            local id = index - 1
            rows[index] = slider(name, ('Use the arrows to adjust %s.'):format(name), 20,
                math.max(0, math.min(20, math.floor((tonumber(GetPedFaceFeature(p, id)) or 0) * 10 + 0.5) + 10)),
                function(value)
                    edits = edits + 1
                    VM.execute('player.setFaceFeature', { id = id, value = (value - 10) / 10 })
                end)
        end
        return rows
    end,
})

VM.define('mp_ped_tattoos', {
    title = 'vMenu',
    subtitle = 'Character Tattoo Options',
    build = function()
        return { VM.action('player.clearPedTattoos', 'Remove All Tattoos & Badges', 'Strip every tattoo and badge so you can start fresh.') }
    end,
})

local CLOTHES = { { 1, 'Masks' }, { 3, 'Upper Body' }, { 4, 'Lower Body' }, { 5, 'Bags & Parachutes' }, { 6, 'Shoes' },
    { 7, 'Scarfs & Chains' }, { 8, 'Shirt & Accessory' }, { 9, 'Body Armor & Accessory 2' }, { 10, 'Badges & Logos' },
    { 11, 'Shirt Overlay & Jackets' } }
local CLOTHES_HINT = 'Arrows pick the drawable, ~o~enter~s~ moves to its next texture.'

VM.define('mp_ped_clothes', {
    title = 'vMenu',
    subtitle = 'Character Clothing Options',
    build = function()
        if not VM.can(EDIT) then return {} end
        local p, rows = ped(), {}
        for index, piece in ipairs(CLOTHES) do
            local id = piece[1]
            local count, drawable = GetNumberOfPedDrawableVariations(p, id), GetPedDrawableVariation(p, id)
            rows[index] = list(piece[2], numbered('Drawable #%d (of %d)', count, 0),
                ('%s Texture %d of %d.'):format(CLOTHES_HINT, GetPedTextureVariation(p, id) + 1,
                    GetNumberOfPedTextureVariations(p, id, drawable)),
                drawable + 1,
                function(position) apply({ type = 'component', id = id, drawable = position - 1, texture = 0 }) end,
                function(position)
                    if ctrlHeld() then
                        local chosen = askId('Enter Drawable ID', 0, count - 1)
                        if chosen then apply({ type = 'component', id = id, drawable = chosen, texture = 0 }) end
                        return
                    end
                    cycleComponent(id, position - 1)
                end)
        end
        return rows
    end,
})

local MP_PROP_NAMES = { 'Hats & Helmets', 'Glasses', 'Misc Props', 'Watches', 'Bracelets' }
local PROPS_HINT = 'Arrows pick the prop, ~o~enter~s~ moves to its next texture.'

local function mpPropValues(count)
    local key = 'mp-props|' .. count
    if not lists[key] then
        local values = {}
        for i = 1, count do values[i] = ('Prop #%d (of %d)'):format(i - 1, count) end
        values[count + 1] = 'No Prop'
        lists[key] = values
    end
    return lists[key]
end

VM.define('mp_ped_props', {
    title = 'vMenu',
    subtitle = 'Character Props Options',
    build = function()
        if not VM.can(EDIT) then return {} end
        local p, rows = ped(), {}
        for index, id in ipairs(PROP_IDS) do
            local count, current = GetNumberOfPedPropDrawableVariations(p, id), GetPedPropIndex(p, id)
            local description = PROPS_HINT
            if current >= 0 then
                description = ('%s Texture %d of %d.'):format(PROPS_HINT, GetPedPropTextureIndex(p, id) + 1,
                    GetNumberOfPedPropTextureVariations(p, id, current))
            end
            rows[index] = list(MP_PROP_NAMES[index], mpPropValues(count), description, current < 0 and count + 1 or current + 1,
                function(position)
                    local drawable = position - 1
                    apply({ type = 'prop', id = id, drawable = drawable >= count and -1 or drawable, texture = 0 })
                end,
                function(position)
                    if ctrlHeld() then
                        local chosen = askId('Enter Prop ID', -1, count - 1)
                        if chosen then apply({ type = 'prop', id = id, drawable = chosen, texture = 0 }) end
                        return
                    end
                    if position - 1 < count then cycleProp(id) end
                end)
        end
        return rows
    end,
})

-- Saved characters: the Cortex saved-outfit library (Cortex and vMenu MP saves).
local function cloneCharacter(entry)
    if VM.denied(SAVE_MP) then return end
    local name = VM.input('Name for the copy', entry.name, 30)
    if not present(name) then VM.notify('error', INVALID_NAME); return end
    if characterNamed(name) then VM.notify('error', NAME_EXISTS); return end
    Admin.cloneSavedPed(entry, name)
    loadCharacters()
end

local function renameCharacter(entry)
    if VM.denied(SAVE_MP) then return end
    local name = VM.input('New name for this character', entry.name, 30)
    if not present(name) then VM.notify('error', INVALID_INPUT); return end
    if characterNamed(name) then VM.notify('error', NAME_EXISTS); return end
    if Admin.renameSavedPed(entry, name) == false then return end
    loadCharacters()
    VM.back()
end

local function deleteCharacter(entry)
    if VM.denied(SAVE_MP) then return end
    if Admin.deleteSavedPed(entry) == false then return end
    loadCharacters()
    VM.back()
end

VM.define('mp_ped_character', {
    title = 'vMenu',
    subtitle = function(args) return args.entry.name end,
    build = function(args)
        local entry = args.entry
        local manage = VM.can(SAVE_MP)
        return {
            VM.action('player.loadMpPed', 'Spawn Saved Character', 'Load this character onto your player.', { entry = entry }),
            VM.can('player.loadMpPed') and VM.submenu('mp_ped_create', 'Edit Saved Character',
                'Open this character in the creator. Saving there writes the changes back to this entry.',
                { key = 'edit:' .. entry.id, entry = entry },
                { rightLabel = '', hideEmpty = false, onSelect = function()
                    if VM.denied('player.loadMpPed') then return end
                    if Admin.beginVmenuCharacterEdit and not Admin.beginVmenuCharacterEdit() then return false end
                    if VM.execute('player.loadMpPed', { entry = entry }) == false then
                        if Admin.finishVmenuCharacterEdit then Admin.finishVmenuCharacterEdit(false) end
                        return false
                    end
                end }) or nil,
            manage and VM.button('Clone Saved Character',
                'Copy this character under a new name. The copy is cancelled if that name is taken.',
                function() cloneCharacter(entry) end) or nil,
            VM.action('player.setDefaultSavedPed', 'Set As Default Character',
                "Spawn as this character by default. Needs 'Respawn As Default MP Character' turned on in Misc Settings.",
                nil, { onSelect = function()
                    if VM.execute('player.setDefaultSavedPed', { entry = entry }) ~= false then requestCharacters() end
                end }),
            manage and VM.button('Rename Saved Character',
                'Give this character a new name. Nothing changes if that name is taken.',
                function() renameCharacter(entry) end) or nil,
            manage and VM.button('Update Character Clothing',
                'Copy the outfit you are wearing into this save. ~r~The saved outfit is replaced.~w~ Face, hair and other appearance data stay as they are.',
                function()
                    if VM.denied(SAVE_MP) then return end
                    VM.execute(SAVE_MP, { name = entry.name, entry = entry, clothingOnly = true })
                end, { confirm = true, icon = 'warning' }) or nil,
            manage and VM.button('Delete Saved Character', 'Remove this character permanently.',
                function() deleteCharacter(entry) end, { confirm = true, icon = 'warning' }) or nil,
        }
    end,
})

local function inCategory(entry, category)
    local name = entry.category
    if not present(name) or name:lower() == 'uncategorized' then return category == '' end
    return name == category
end

VM.define('mp_ped_category', {
    title = function(args) return args.key == '' and 'Uncategorized' or args.key end,
    subtitle = function(args) return '~s~Category: ~y~' .. (args.key == '' and 'Uncategorized' or args.key) end,
    build = function(args)
        if not VM.canAny(CHARACTER_ACTIONS) then return {} end
        local rows = { spacer('↓ Characters ↓') }
        for _, entry in ipairs(characters or {}) do
            if inCategory(entry, args.key) then
                local description = 'Load or manage this saved character.'
                if entry.isDefault then
                    description = description .. ' ~g~This is your default character, loaded every time you spawn or respawn.'
                end
                rows[#rows + 1] = VM.submenu('mp_ped_character', entry.name, description, { key = entry.id, entry = entry },
                    { key = 'character:' .. tostring(entry.id), hideEmpty = false, icon = entry.isDefault and 'tick' or nil })
            end
        end
        return rows
    end,
})

VM.define('mp_ped_saved', {
    title = 'vMenu',
    subtitle = 'Manage Saved Characters',
    onOpen = function() requestCharacters() end,
    build = function()
        if not VM.canAny(CHARACTER_ACTIONS) then return {} end
        local rows = {
            spacer('↓ Character Categories ↓'),
            VM.submenu('mp_ped_category', 'Uncategorized', 'Characters without a category.', { key = '' }, { hideEmpty = false }),
        }
        for _, category in ipairs(categories or {}) do
            rows[#rows + 1] = VM.submenu('mp_ped_category', category.name, category.description, { key = category.name },
                { key = 'category:' .. category.name, hideEmpty = false })
        end
        return rows
    end,
})

-- Generate Appearance: the Character Studio generator's choices as lists. They
-- persist per player and are sent with every roll.
local GENERATOR_KVP = 'cortex-admin_vmenu_generator'
local KIT_STYLES = { military = true, scuba = true, tactical = true, aviator = true, alpine = true, motocross = true }
local STYLE_NOTES = {
    polished = 'Knitwear, tailored coats, office shirts, chinos and dress shoes.',
    casual = 'Flannel, denim jackets, chore coats, turnups and canvas sneakers.',
    street = 'Hoodies, puffers, varsity jackets, cargos and statement sneakers.',
    sport = 'Track tops, gym shorts, joggers and running shoes.',
    utility = 'Work shirts, field jackets, cargos and work boots.',
    biker = 'Leather jackets, racing tops, leather trousers and biker boots.',
    resort = 'Printed short sleeves, shorts, sandals and slides.',
    nightlife = 'Open-collar shirts, leather, designer knits and sharp shoes.',
    designer = 'Bigness, Blagueurs and Broker layers with wide trousers and designer shoes.',
    military = 'Army kit: camo combat shirts, matching cargos, tactical boots and helmets.',
    scuba = 'Scuba kit: wetsuit, fins, tank and dive mask in one colorway.',
    tactical = 'Tactical kit: jackets, combat pants, boots, balaclavas and goggles.',
    aviator = 'Pilot kit: flight suits, flight jackets, boots and helmets.',
    alpine = 'Alpine kit: puffers, parkas, winter boots, beanies and ski goggles.',
    motocross = 'Motocross kit: jerseys with gloves, padded pants, boots and helmets.',
}

-- choices: { value, label, body } where body limits a choice to one freemode body.
-- wardrobe rows hide for kits (complete uniforms); character rows show only in Full character.
local GENERATOR_ROWS = {
    { key = 'mode', label = 'Mode', description = 'Outfit only keeps your face, hair and heritage. Full character rolls those too.',
      choices = { { 'outfit', 'Outfit only' }, { 'character', 'Full character' } } },
    { key = 'style', label = 'Style', choices = { { 'polished', 'Polished' }, { 'casual', 'Casual' }, { 'street', 'Street' },
        { 'sport', 'Sport' }, { 'utility', 'Utility' }, { 'biker', 'Biker' }, { 'resort', 'Resort' }, { 'nightlife', 'Nightlife' },
        { 'designer', 'Designer' }, { 'military', 'Army' }, { 'scuba', 'Scuba' }, { 'tactical', 'Tactical' }, { 'aviator', 'Pilot' },
        { 'alpine', 'Alpine' }, { 'motocross', 'Motocross' } } },
    { key = 'palette', label = 'Clothing Palette', description = 'How much color the outfit carries.',
      choices = { { 'neutral', 'Restrained' }, { 'tonal', 'Tonal' }, { 'varied', 'Mixed' }, { 'full', 'Full range' } } },
    { key = 'topType', label = 'Top', wardrobe = true, description = 'Limit the roll to one kind of top.',
      choices = { { 'any', 'Any top' }, { 'tee', 'Tees and polos' }, { 'shirt', 'Shirts and blouses' }, { 'knit', 'Knitwear' },
        { 'hoodie', 'Hoodies and track tops' }, { 'jacket', 'Jackets and coats' } } },
    { key = 'bottomType', label = 'Bottoms', wardrobe = true, description = 'Limit the roll to one kind of bottoms.',
      choices = { { 'any', 'Any bottoms' }, { 'jeans', 'Jeans' }, { 'trousers', 'Trousers' }, { 'cargo', 'Cargos' },
        { 'joggers', 'Joggers and leggings' }, { 'shorts', 'Shorts' }, { 'skirt', 'Skirts', 'female' } } },
    { key = 'footwear', label = 'Footwear', wardrobe = true, description = 'Limit the roll to one kind of shoes.',
      choices = { { 'any', 'Any shoes' }, { 'sneakers', 'Sneakers' }, { 'boots', 'Boots' }, { 'smart', 'Dress shoes and loafers' },
        { 'heels', 'Heels', 'female' }, { 'open', 'Sandals and slides' } } },
    { key = 'headwear', label = 'Headwear', wardrobe = true, description = 'Add a hat to the outfit.',
      choices = { { 'none', 'None' }, { 'any', 'Any hat' }, { 'cap', 'Caps' }, { 'beanie', 'Beanies' }, { 'hat', 'Brimmed hats' } } },
    { key = 'accessories', label = 'Accessories', description = 'Add a watch, glasses or both.',
      choices = { { 'none', 'None' }, { 'minimal', 'Watch or glasses' }, { 'layered', 'Watch and glasses' } } },
    { key = 'gender', label = 'Body Model', character = true, description = 'Which freemode body the new character uses.',
      choices = { { 'keep', 'Keep current' }, { 'random', 'Surprise me' }, { 'male', 'Freemode male' }, { 'female', 'Freemode female' } } },
    { key = 'faceProfile', label = 'Face Profile', character = true, description = 'The heritage pool the face is built from.',
      choices = { { 'everyday', 'Everyday' }, { 'east_asian', 'East Asian' }, { 'soft', 'Soft features' }, { 'wide', 'Full heritage range' } } },
    { key = 'faceVariation', label = 'Face Variation', character = true, description = 'How far face shape sliders may move.',
      choices = { { 'subtle', 'Subtle' }, { 'balanced', 'Balanced' }, { 'distinct', 'Distinct' } } },
    { key = 'ageProfile', label = 'Age', character = true, description = 'Adds age detail to the skin.',
      choices = { { 'young', 'Young adult' }, { 'adult', 'Adult' }, { 'mature', 'Mature' } } },
    { key = 'complexion', label = 'Complexion', character = true, description = 'Skin detail such as blemishes and freckles.',
      choices = { { 'clean', 'Clean' }, { 'natural', 'Natural detail' }, { 'freckled', 'Freckles' } } },
    { key = 'eyeColor', label = 'Eye Color', character = true, description = 'Eye colors the roll may pick.',
      choices = { { 'natural', 'Natural mix' }, { 'brown', 'Brown and hazel' }, { 'blue', 'Blue' }, { 'green', 'Green' }, { 'gray', 'Gray' } } },
    { key = 'hairStyle', label = 'Hair Shape', character = true, description = 'Hair lengths the roll may pick.',
      choices = { { 'any', 'Any reviewed style' }, { 'short', 'Short' }, { 'medium', 'Medium' }, { 'long', 'Long / tied' }, { 'updo', 'Updo' } } },
    { key = 'hairTone', label = 'Hair Color', character = true, description = 'Hair colors the roll may pick.',
      choices = { { 'any', 'Any natural tone' }, { 'dark', 'Dark' }, { 'warm', 'Warm brown / auburn' }, { 'light', 'Blonde / light' },
        { 'gray', 'Gray / silver' }, { 'fashion', 'Dyed color' } } },
    { key = 'highlights', label = 'Highlights', character = true, description = 'A second hair color through the first.',
      choices = { { 'natural', 'Occasional' }, { 'none', 'None' }, { 'contrast', 'Contrasting' } } },
    { key = 'facialHair', label = 'Facial Hair', character = true, body = 'male', description = 'Beard options for male characters.',
      choices = { { 'any', 'Any' }, { 'clean', 'Clean shaven' }, { 'stubble', 'Stubble' }, { 'short', 'Goatee or trimmed' }, { 'full', 'Full beard' } } },
    { key = 'makeup', label = 'Makeup', character = true, body = 'female', description = 'Makeup level for female characters.',
      choices = { { 'none', 'None' }, { 'subtle', 'Subtle' }, { 'polished', 'Polished' }, { 'bold', 'Bold' } } },
}

local generator = nil
local function sanitizeGenerator(raw)
    return AppearanceRandomizer and AppearanceRandomizer.sanitizeOptions(raw) or { mode = 'outfit', style = 'polished' }
end

local function generatorOptions()
    if not generator then
        local ok, saved = pcall(json.decode, GetResourceKvpString(GENERATOR_KVP) or '')
        generator = sanitizeGenerator(ok and type(saved) == 'table' and saved or nil)
    end
    return generator
end

-- Bumping edits gives every list a fresh key, so a position the engine stored
-- before the change can never override the saved choice.
local function setGeneratorOption(key, value)
    local options = generatorOptions()
    options[key] = value
    generator = sanitizeGenerator(options)
    SetResourceKvp(GENERATOR_KVP, json.encode(generator))
    edits = edits + 1
end

-- The body the next roll dresses, so body-only choices (skirts, heels, beards,
-- makeup) follow it. 'any' when it cannot be known before the roll.
local function generatorBody(options)
    if options.mode == 'character' and (options.gender == 'male' or options.gender == 'female') then return options.gender end
    if options.mode == 'character' and options.gender == 'random' then return 'any' end
    local current = GetEntityModel(ped())
    if current == joaat('mp_f_freemode_01') then return 'female' end
    if current == joaat('mp_m_freemode_01') then return 'male' end
    return 'any'
end

local function availableChoices(row, body)
    local choices = {}
    for _, choice in ipairs(row.choices) do
        if not choice[3] or body == 'any' or choice[3] == body then choices[#choices + 1] = choice end
    end
    return choices
end

local function choicePosition(choices, value)
    for position, choice in ipairs(choices) do
        if choice[1] == value then return position end
    end
    return nil
end

-- A choice the body cannot wear falls back to the first (any), like the studio.
local function effectiveGeneratorOptions()
    local options, body, effective = generatorOptions(), generatorBody(generatorOptions()), {}
    for key, value in pairs(options) do effective[key] = value end
    for _, row in ipairs(GENERATOR_ROWS) do
        local choices = availableChoices(row, body)
        if not choicePosition(choices, options[row.key]) then effective[row.key] = choices[1][1] end
    end
    return effective
end

VM.define('mp_ped_generate', {
    subtitle = 'Generate Appearance',
    build = function()
        if not VM.can('player.randomizeAppearance') then return {} end
        local options = generatorOptions()
        local body = generatorBody(options)
        local rows = {
            VM.action('player.randomizeAppearance', 'Generate', 'Roll a new look from the choices below. Select again for another.',
                effectiveGeneratorOptions),
        }
        for _, row in ipairs(GENERATOR_ROWS) do
            local hidden = (row.wardrobe and KIT_STYLES[options.style]) or (row.character and options.mode ~= 'character')
                or (row.body and body ~= 'any' and body ~= row.body)
            if not hidden then
                local choices, values = availableChoices(row, body), {}
                for i, choice in ipairs(choices) do values[i] = choice[2] end
                rows[#rows + 1] = list(row.label, values, row.key == 'style' and STYLE_NOTES[options.style] or row.description,
                    choicePosition(choices, options[row.key]) or 1, function(position)
                        setGeneratorOption(row.key, choices[position][1])
                    end)
            end
        end
        rows[#rows + 1] = VM.button('Reset Choices', 'Return every choice to its default.', function()
            generator = sanitizeGenerator(nil)
            SetResourceKvp(GENERATOR_KVP, json.encode(generator))
            edits = edits + 1
        end)
        rows[#rows + 1] = VM.action('player.undoRandomizedAppearance', 'Undo Generated Appearance',
            'Restores the look you had before the last generated appearance.')
        return rows
    end,
})

VM.define('mp_ped', {
    subtitle = 'MP Ped Customization',
    build = function()
        local create = VM.can('player.setModel')
        return {
            VM.action(SAVE_MP, 'Save Current Character', 'Save the MP character you are wearing.', nil,
                { onSelect = function() saveCharacter({ stay = true }) end }),
            create and VM.submenu('mp_ped_create', 'Create Male Character', 'Start a fresh male freemode character.', { key = 'male' },
                { hideEmpty = false, onSelect = function() return createCharacter(true) end }) or nil,
            create and VM.submenu('mp_ped_create', 'Create Female Character', 'Start a fresh female freemode character.', { key = 'female' },
                { hideEmpty = false, onSelect = function() return createCharacter(false) end }) or nil,
            VM.canAny(CHARACTER_ACTIONS) and VM.submenu('mp_ped_saved', 'Saved Characters',
                'Characters you have saved, grouped by category.', nil, { hideEmpty = false }) or nil,
            VM.can('player.randomizeAppearance') and VM.submenu('mp_ped_generate', 'Generate Appearance',
                'Roll a new outfit or a whole character. Pick the style, clothing types and identity first.', nil,
                { hideEmpty = false }) or nil,
            VM.action('player.undoRandomizedAppearance', 'Undo Generated Appearance', 'Restores the look you had before the last generated appearance.'),
        }
    end,
})
