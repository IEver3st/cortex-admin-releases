local Admin, VM = EsAdmin, EsAdmin.VmenuMode
local zones = { { 'hair', 'Hair Overlays' }, { 1, 'Head Tattoos' }, { 0, 'Torso Tattoos' },
    { 2, 'Left Arm Tattoos' }, { 3, 'Right Arm Tattoos' }, { 4, 'Left Leg Tattoos' }, { 5, 'Right Leg Tattoos' },
    { 'badges', 'Badges' }, { 'addons', 'Addon Tattoos' } }
local catalog = {}
local function hashKey(collection, overlay) return (collection & 0xffffffff) .. ':' .. (overlay & 0xffffffff) end
local function load()
    catalog = {}
    local gender = GetEntityModel(PlayerPedId()) == joaat('mp_f_freemode_01') and 1 or 0
    local function add(row, addon)
        if row[1] ~= gender and row[1] ~= 2 then return end
        local key = addon and 'addons' or row[2]:lower():find('hair_', 1, true) and 'hair'
            or row[5] == 'TYPE_BADGE' and 'badges' or row[5] == 'TYPE_TATTOO' and row[4]
        if key == nil or key == false then return end
        catalog[key] = catalog[key] or {}
        catalog[key][#catalog[key] + 1] = { name = row[2], collection = row[3] }
    end
    for _, row in ipairs(EsAdminTattooCatalog or {}) do add(row) end
    local config = Admin.getVmenuImportedConfig()
    for _, row in ipairs(type(config.tattoos) == 'table' and config.tattoos or {}) do
        if type(row.name) == 'string' and type(row.collectionName) == 'string' then
            add({ row.gender or 2, row.name, row.collectionName, row.zoneId or 0, row.type or 'TYPE_TATTOO' }, true)
        end
    end
end
VM._definitions.mp_ped_tattoos.onOpen = load
VM._definitions.mp_ped_tattoos.build = function()
    local rows = { VM.action('player.clearPedTattoos', 'Remove All Tattoos & Badges', 'Remove the current tattoos and badges.') }
    if VM.can('player.applyTattoo') then
        for _, zone in ipairs(zones) do
            if catalog[zone[1]] and #catalog[zone[1]] > 0 then
                rows[#rows + 1] = VM.submenu('mp_ped_tattoo_zone', zone[2], 'Apply or remove individual tattoos.', { key = zone[1], title = zone[2] }, { hideEmpty = false })
            end
        end
    end
    return rows
end
VM.define('mp_ped_tattoo_zone', {
    title = function(args) return args.title end, subtitle = 'Character Tattoos',
    build = function(args)
        if not VM.can('player.applyTattoo') then return {} end
        local current = capturePedDecorations(PlayerPedId())
        local selected, rows = {}, {}
        for _, tattoo in ipairs(current or {}) do selected[hashKey(tattoo.collection, tattoo.overlay)] = true end
        for index, tattoo in ipairs(catalog[args.key] or {}) do
            local label = GetLabelText(tattoo.name)
            if not label or label == 'NULL' or label == '' then label = ('Tattoo #%d'):format(index) end
            rows[#rows + 1] = { kind = 'checkbox', key = tattoo.collection .. ':' .. tattoo.name, label = label,
                description = tattoo.name, enabled = current ~= nil,
                checked = selected[hashKey(joaat(tattoo.collection), joaat(tattoo.name))] == true,
                onCheck = function(enabled) VM.execute('player.applyTattoo', { collection = tattoo.collection, overlay = tattoo.name, enabled = enabled }) end }
        end
        return rows
    end,
})
