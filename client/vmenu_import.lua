-- Read the current player's vMenu namespace, including when vMenu is stopped.
-- No host filesystem or other player's library is involved.
local Admin = EsAdmin
local MAX_KEYS, MAX_BYTES = 10000, 16 * 1024 * 1024
local VALUE_TYPES = {
    settings_vehicleDefaultRadio = 'int', settings_miscLastTimeCycleModifierIndex = 'int',
    settings_miscLastTimeCycleModifierStrength = 'int', settings_clothingAnimationType = 'int',
    settings_voiceChatProximity = 'float',
}
local PREFIXES = {
    { 'mp_ped_', 'mpPeds' }, { 'ped_', 'nonMpPeds' }, { 'veh_', 'vehicles' },
    { 'mp_character_category_', 'pedCategories' }, { 'saved_veh_category_', 'vehicleCategories' },
    { 'vmenu_string_saved_weapon_loadout_', 'weaponLoadouts' },
}

local function externalStart(resource)
    if StartFindExternalKvp then return StartFindExternalKvp(resource, '') end
    return Citizen.InvokeNative(joaat('START_FIND_EXTERNAL_KVP') & 0xffffffff, resource, '', Citizen.ResultAsInteger())
end

local function externalRead(resource, key, kind)
    local getters = { int = GetExternalKvpInt, float = GetExternalKvpFloat, string = GetExternalKvpString }
    local getter = getters[kind]
    if getter then return getter(resource, key) end
    local result = kind == 'int' and Citizen.ResultAsInteger() or kind == 'float' and Citizen.ResultAsFloat() or Citizen.ResultAsString()
    return Citizen.InvokeNative(joaat('GET_EXTERNAL_KVP_' .. kind:upper()) & 0xffffffff, resource, key, result)
end

local function decode(value)
    if type(value) ~= 'string' then return nil end
    local ok, data = pcall(json.decode, value)
    return ok and type(data) == 'table' and data or nil
end

function Admin.readVmenuClientSnapshot()
    local snapshot = {
        ok = true, scope = 'client', localHostOnly = false, readOnly = true,
        mpPeds = {}, nonMpPeds = {}, vehicles = {}, pedCategories = {}, vehicleCategories = {},
        weaponLoadouts = {}, settings = {}, rawKvp = {}, invalid = 0, bytes = 0,
    }
    snapshot.peds = snapshot.mpPeds
    local resources = Config.VmenuCompatibility and Config.VmenuCompatibility.importResourceNames or { 'vMenu', 'vmenu' }
    local total, seen, readable = 0, {}, 0
    for _, resource in ipairs(resources) do
        local started, handle = false, nil
        if type(resource) == 'string' and resource ~= '' then started, handle = pcall(externalStart, resource) end
        -- Names are aliases for one store; one that cannot be opened is skipped.
        if started and type(handle) == 'number' and handle >= 0 then
            readable = readable + 1
            local success = pcall(function()
                while true do
                    local key = FindKvp(handle)
                    if not key then break end
                    total = total + 1
                    if total > MAX_KEYS then snapshot.truncated = true; break end
                    if total % 32 == 0 then Wait(0) end
                    if type(key) == 'string' and #key <= 192 and not key:find('[%z\1-\31\127]') then
                        -- UserDefaults uses strings; only typed settings use integer/float getters.
                        local kind = VALUE_TYPES[key] or (key:match('^vmenu_int_') and 'int' or key:match('^vmenu_float_') and 'float' or 'string')
                        local ok, value = pcall(externalRead, resource, key, kind)
                        if not ok then
                            kind = 'float'
                            ok, value = pcall(externalRead, resource, key, kind)
                        end
                        if ok and (type(value) == 'string' or type(value) == 'number') then
                            local bytes = #key + #tostring(value)
                            if snapshot.bytes + bytes > MAX_BYTES then snapshot.truncated = true; break end
                            snapshot.bytes = snapshot.bytes + bytes
                            snapshot.rawKvp[#snapshot.rawKvp + 1] = { resource = resource, key = key, kind = kind, value = value }
                            if not seen[key] then
                                seen[key] = true
                                local parsed = decode(value)
                                for _, rule in ipairs(PREFIXES) do
                                    if key:sub(1, #rule[1]) == rule[1] then
                                        if parsed then
                                            local list = snapshot[rule[2]]
                                            list[#list + 1] = { key = key, data = parsed }
                                        else snapshot.invalid = snapshot.invalid + 1 end
                                        break
                                    end
                                end
                                if key == 'vmenu_default_character' then snapshot.defaultKey = value
                                elseif key == 'vmenu_string_default_loadout' then snapshot.defaultLoadout = value
                                elseif key == 'vmenu_temp_weapons_loadout_before_respawn' then snapshot.temporaryLoadout = parsed
                                elseif key:sub(1, 9) == 'settings_' then
                                    local scalar = value
                                    if type(value) == 'string' then
                                        if value:lower() == 'true' then scalar = true
                                        elseif value:lower() == 'false' then scalar = false end
                                    end
                                    snapshot.settings[key:sub(10)] = scalar
                                end
                            end
                        else snapshot.invalid = snapshot.invalid + 1 end
                    else snapshot.invalid = snapshot.invalid + 1 end
                end
            end)
            EndFindKvp(handle)
            if not success then snapshot.ok, snapshot.reason = false, 'client_kvp_read_failed'; return snapshot end
            if snapshot.truncated then break end
        end
    end
    if readable == 0 then
        snapshot.ok, snapshot.reason = false, 'client_kvp_unavailable'
        return snapshot
    end
    for _, rule in ipairs(PREFIXES) do
        table.sort(snapshot[rule[2]], function(a, b) return a.key < b.key end)
    end
    snapshot.reason = #snapshot.rawKvp > 0 and 'parsed' or 'empty'
    return snapshot
end

function Admin.archiveVmenuClientSnapshot(snapshot)
    local result = { imported = 0, skipped = 0, failed = 0, total = #(snapshot.rawKvp or {}) }
    for index, entry in ipairs(snapshot.rawKvp or {}) do
        -- Preserve original values, including settings without a Cortex equivalent.
        -- Existing archives are retained; repeating import never overwrites them.
        local key = 'cortex-admin_vmenu_archive:' .. entry.resource .. ':' .. entry.key
        if GetResourceKvpString(key) ~= nil then result.skipped = result.skipped + 1
        else
            local ok, encoded = pcall(json.encode, entry)
            local written = ok and pcall(SetResourceKvp, key, encoded)
            if written and GetResourceKvpString(key) == encoded then result.imported = result.imported + 1
            else result.failed = result.failed + 1 end
        end
        if index % 16 == 0 then Wait(0) end
    end
    return result
end
