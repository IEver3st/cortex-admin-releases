local Admin = EsAdmin
local activeKit
local function integer(value, maximum)
    return type(value) == 'number' and value == value and value % 1 == 0 and value >= 0 and value <= maximum
end
local function text(value)
    if type(value) ~= 'string' or value == '' or value == 'NULL' then return nil end
    return value:sub(1, 128)
end
local function labels(vehicle)
    local model = GetEntityModel(vehicle)
    for key, entry in pairs(Config.VehicleModLabels or {}) do
        if (type(key) == 'number' and key == model or type(key) == 'string' and joaat(key) == model) and type(entry) == 'table' then
            return entry
        end
    end
    return {}
end
local function localized(key)
    return text(key) and text(GetLabelText(key)) or nil
end
-- Shop labels used by CitizenFX's VehicleMod localization, including Benny's
-- model-specific categories. Native/custom slot labels retain priority.
local shopSlots = { [11] = 'CMOD_MOD_ENG', [12] = 'CMOD_MOD_BRA', [13] = 'CMOD_MOD_TRN',
    [14] = 'CMOD_MOD_HRN', [15] = 'CMOD_MOD_SUS', [16] = 'CMOD_MOD_ARM' }
local modelSlots = {
    sultanrs = { [27] = 'CMM_MOD_S2b', [40] = 'CMM_MOD_S15b', [41] = 'CMM_MOD_S16b',
        [42] = 'CMM_MOD_S17b', [43] = 'CMM_MOD_S18b', [44] = 'CMM_MOD_S19b' },
    banshee2 = { [41] = 'CMM_MOD_S16b' },
    btype3 = { [43] = 'CMM_MOD_S18c', [44] = 'CMM_MOD_S19c', [46] = 'CMM_MOD_S21b' },
    virgo2 = { [44] = 'CMM_MOD_S19d' },
    slamvan3 = { [45] = 'CMM_MOD_S27', [47] = 'SLVAN3_RDOOR' },
}
local performanceKeys = { [12] = 'CMOD_BRA_', [13] = 'CMOD_GBX_', [15] = 'CMOD_SUS_', [16] = 'CMOD_ARM_' }
local hornKeys = { [-1] = 'CMOD_HRN_0', [0] = 'CMOD_HRN_TRK', [1] = 'CMOD_HRN_COP', [2] = 'CMOD_HRN_CLO',
    [8] = 'CMOD_HRN_SAD', [16] = 'HORN_CNOTE_C0', [17] = 'HORN_CNOTE_D0', [18] = 'HORN_CNOTE_E0',
    [19] = 'HORN_CNOTE_F0', [20] = 'HORN_CNOTE_G0', [21] = 'HORN_CNOTE_A0', [22] = 'HORN_CNOTE_B0', [23] = 'HORN_CNOTE_C1',
    [32] = 'HORN_LUXE2', [33] = 'HORN_LUXE1', [34] = 'HORN_LUXE3',
    [35] = 'HORN_LUXE2', [36] = 'HORN_LUXE1', [37] = 'HORN_LUXE3' }
for index = 3, 7 do hornKeys[index] = 'CMOD_HRN_MUS' .. (index - 2) end
for index = 9, 15 do hornKeys[index] = 'HORN_CLAS' .. (index - 8) end
for index = 24, 27 do hornKeys[index] = 'HORN_HIPS' .. (index - 23) end
for index = 28, 31 do hornKeys[index] = 'HORN_INDI_' .. (index - 27) end
for index = 38, 41 do hornKeys[index] = 'HORN_HWEEN' .. (1 + math.floor((index - 38) / 2)) end
for index = 42, 45 do hornKeys[index] = 'HORN_LOWRDER' .. (1 + math.floor((index - 42) / 2)) end
for index = 46, 48 do hornKeys[index] = 'HORN_XM15_' .. (index - 45) end
local function shopSlotLabel(vehicle, slot)
    local model = GetEntityModel(vehicle)
    for name, slots in pairs(modelSlots) do
        if slots[slot] and model == joaat(name) then
            local value = localized(slots[slot])
            if value then return value end
        end
    end
    return localized(shopSlots[slot] or (slot >= 25 and slot <= 48 and ('CMM_MOD_S%d'):format(slot - 25)))
end
function Admin.vehicleModKit(vehicle)
    local count = GetNumModKits and GetNumModKits(vehicle) or 1
    count = integer(count, 256) and count or 0
    local nativeKit = GetVehicleModKit and GetVehicleModKit(vehicle)
    local model = GetEntityModel(vehicle)
    local current = 0
    if activeKit and activeKit.vehicle == vehicle and activeKit.model == model
        and activeKit.native == nativeKit and integer(activeKit.index, count - 1) then
        current = activeKit.index
    elseif count > 0 then
        -- Initialize the kit before querying its slots, just as the mod shop does.
        -- GET_VEHICLE_MOD_KIT reports an identity, not the SET native's index.
        SetVehicleModKit(vehicle, 0)
        activeKit = { vehicle = vehicle, model = model, index = 0,
            native = GetVehicleModKit and GetVehicleModKit(vehicle) }
    end
    local custom, kits = labels(vehicle), {}
    for index = 0, count - 1 do
        kits[#kits + 1] = { value = index, label = text(type(custom.kits) == 'table' and custom.kits[index]) or ('Mod kit %d'):format(index + 1) }
    end
    return current, kits, custom
end
function Admin.vehicleModSlotLabel(vehicle, slot, custom)
    local entry = type(custom.slots) == 'table' and custom.slots[slot]
    if type(entry) == 'table' and text(entry.label) then return text(entry.label) end
    local key = GetModSlotName and GetModSlotName(vehicle, slot)
    return localized(key) or text(key) or shopSlotLabel(vehicle, slot)
end
function Admin.vehicleModPartLabel(vehicle, slot, index, custom)
    local entry = type(custom.slots) == 'table' and custom.slots[slot]
    local override = type(entry) == 'table' and type(entry.names) == 'table' and entry.names[index]
    if text(override) then return text(override) end
    local key = index >= 0 and GetModTextLabel(vehicle, slot, index) or nil
    local name = localized(key)
    if name then return name end
    -- Some stock/performance choices have shop GXT entries but no mod-text label.
    local shopKey = performanceKeys[slot] and (performanceKeys[slot] .. (index + 1))
    if slot == 11 then shopKey = index == -1 and 'CMOD_ARM_0' or ('CMOD_ENG_' .. (index + 2)) end
    if slot == 14 then shopKey = hornKeys[index] end
    if index == -1 and not shopKey then
        local model = GetEntityModel(vehicle)
        if slot == 41 and (model == joaat('banshee') or model == joaat('banshee2') or model == joaat('sultanrs')) then
            shopKey = 'CMOD_COL5_41'
        else shopKey = 'CMOD_DEF_0' end
    end
    return localized(shopKey) or text(key)
end
-- Hydraulics (slot 38, toggle slot 21) only work on models flagged
-- FLAG_HAS_LOWRIDER_HYDRAULICS (119) or FLAG_HAS_LOWRIDER_DONK_HYDRAULICS (123).
-- Addon mod kits often copy the lowrider parts without the flag.
local HYDRAULIC_FLAGS = { 119, 123 }
function Admin.vehicleHasHydraulics(vehicle)
    if not GetVehicleHasFlag then return true end -- older artifacts: trust the kit
    for _, flag in ipairs(HYDRAULIC_FLAGS) do
        local on = GetVehicleHasFlag(vehicle, flag)
        if on == true or on == 1 then return true end
    end
    return false
end
-- Whether the mod menus offer a slot with `count` parts. A fitted part stays
-- listed so it can be taken off again.
function Admin.vehicleModSlotOffered(vehicle, slot, count)
    if not integer(count, 4096) or count == 0 then return false end
    if slot ~= 21 and slot ~= 38 then return true end
    return GetVehicleMod(vehicle, slot) >= 0 or Admin.vehicleHasHydraulics(vehicle)
end
function Admin.selectVehicleModKit(vehicle, value)
    local current, kits = Admin.vehicleModKit(vehicle)
    if not integer(value, #kits - 1) then return false, 'invalid_modkit' end
    local previous = GetVehicleModKit and GetVehicleModKit(vehicle)
    SetVehicleModKit(vehicle, value)
    local nativeKit = GetVehicleModKit and GetVehicleModKit(vehicle)
    if GetVehicleModKit and value ~= current and nativeKit == previous then return false, 'modkit_unavailable' end
    activeKit = { vehicle = vehicle, model = GetEntityModel(vehicle), index = value,
        native = nativeKit }
    return true
end
