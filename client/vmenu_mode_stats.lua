local VM = EsAdmin.VmenuMode
local vehicles, weapons = {}, {}
local function ratio(value, maximum)
    if not value or not maximum or maximum <= 0 then return 0 end
    return math.max(0, math.min(1, value / maximum))
end
function VM.vehicleStats(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if vehicles[hash] then return vehicles[hash] end
    if not IsModelInCdimage(hash) or not GetVehicleClassEstimatedMaxSpeed then return nil end
    local class = GetVehicleClassFromName(hash)
    local rows = {
        { label = 'Top speed', value = ratio(GetVehicleModelEstimatedMaxSpeed(hash), GetVehicleClassEstimatedMaxSpeed(class)) },
        { label = 'Acceleration', value = ratio(GetVehicleModelAcceleration(hash), GetVehicleClassMaxAcceleration(class)) },
        { label = 'Braking', value = ratio(GetVehicleModelMaxBraking(hash), GetVehicleClassMaxBraking(class)) },
        { label = 'Traction', value = ratio(GetVehicleModelMaxTraction(hash), GetVehicleClassMaxTraction(class)) },
    }
    vehicles[hash] = rows
    return rows
end
function VM.weaponStats(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if weapons[hash] ~= nil then return weapons[hash] or nil end
    -- CitizenFX UnsafeWeaponHudStats: five signed integers, aligned to 8 bytes.
    -- Keep the writable buffer alive until the native has finished.
    local buffer = string.rep('\0', 40)
    local ok, found = pcall(Citizen.InvokeNative, 0xD92C739EE34C9EBA, hash, buffer, Citizen.ReturnResultAnyway())
    if not ok or not found or found == 0 then weapons[hash] = false; return nil end
    local rows = {}
    for _, field in ipairs({ { 'Damage', 1 }, { 'Fire rate', 9 }, { 'Accuracy', 25 }, { 'Range', 33 } }) do
        rows[#rows + 1] = { label = field[1], value = ratio(string.unpack('<i4', buffer, field[2]), 100) }
    end
    weapons[hash] = rows
    return rows
end
