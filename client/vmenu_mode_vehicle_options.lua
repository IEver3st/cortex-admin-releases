-- vMenu mode: Vehicle Options and its submenus (vMenu/menus/VehicleOptions.cs).
-- Rows run the Cortex vehicle actions. Mod, colour, neon, livery and extra edits
-- go through Admin.setVehicleCustomization with the payloads the panel's
-- cortex-admin:setVehicleCustomization callback builds, so validation and
-- network control stay in one place.
local Admin = EsAdmin
local VM = Admin.VmenuMode
-- FiveM client Lua returns 1 or false for BOOL natives, so `== true` never matches.
local function nativeOn(value) return value == true or value == 1 end

local MODS, COLORS, LIVERIES = 'vehicle.customMods', 'vehicle.customColors', 'vehicle.customLiveries'
local EXTRAS, NEON = 'vehicle.customExtras', 'vehicle.customUnderglow'
local INVALID_INPUT = 'No valid value was entered. Try again.'
local NO_VEHICLE = 'Get in a vehicle first.'
local NEED_DRIVER = 'Only the driver can do this.'
local DRIVER_MENU = 'This menu is for the driver only. Take the driver seat first.'
local DRIVER_COLORS = 'Take the driver seat to repaint this vehicle.'
local DRIVER_DRIVEABLE = 'Take the driver seat of a working vehicle to use this.'

local function noop() end

-- Lists and sliders that show live vehicle state key on the value and on a
-- revision every handler bumps, so a failed or external change re-reads the vehicle.
local revision = 0
local function bump() revision = revision + 1 end
local function liveKey(name, value) return ('%s:%s:%d'):format(name, tostring(value), revision) end

local function vehicle()
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v == 0 or not DoesEntityExist(v) then return nil end
    return v
end
local function isDriver(v) return v ~= nil and GetPedInVehicleSeat(v, -1) == PlayerPedId() end
-- A live vehicle the local player is driving.
local function driven(message)
    local v = vehicle()
    if v and not IsEntityDead(v) and isDriver(v) then return v end
    if message then VM.notify('error', message) end
    return nil
end

-- Only for edits Cortex has no customization type for (preset colours, custom
-- wheels, custom xenon RGB); same control request as client/actions.lua.
local function control(v)
    if not NetworkGetEntityIsNetworked(v) or NetworkHasControlOfEntity(v) then return true end
    local deadline = GetGameTimer() + 750
    repeat NetworkRequestControlOfEntity(v); Wait(0) until NetworkHasControlOfEntity(v) or GetGameTimer() >= deadline
    if NetworkHasControlOfEntity(v) then return true end
    VM.notify('error', 'This vehicle is controlled by another player.')
    return false
end

local REASONS = {
    no_vehicle = NO_VEHICLE, vehicle_destroyed = 'This vehicle is destroyed.',
    no_control = 'This vehicle is controlled by another player.',
    plate_build_unsupported = 'This plate type needs a newer game build.',
}
local function customize(actionId, data, silent)
    if VM.denied(actionId) then return false end
    local ok, reason = Admin.setVehicleCustomization(data)
    bump()
    if ok ~= true and not silent then
        VM.notify('error', REASONS[reason] or ('That change could not be applied (%s).'):format(tostring(reason or 'unknown')))
    end
    return ok == true
end

local function label(key, fallback)
    local text = GetLabelText(key)
    if type(text) ~= 'string' or text == '' or text == 'NULL' then return fallback or key end
    return text
end

-- Splits joined words for display: "FrontBumper2" -> "Front Bumper2".
local function properString(input)
    local text = tostring(input):gsub('([^%u%s])(%u)', '%1 %2'):gsub('%s+', ' ')
    return text
end

-- ---------------------------------------------------------------------------
-- Data

-- Paint palettes come from GTA V game data via shared/vmenu_reference.lua.
local PALETTES = EsAdminVmenuReference and EsAdminVmenuReference.paintPalettes
    or { classic = {}, matte = {}, metals = {}, util = {}, worn = {} }

local paletteNames = {}
local function colorNames(palette)
    if not paletteNames[palette] then
        local list, names = PALETTES[palette], {}
        for i, entry in ipairs(list) do names[i] = ('%s (%d/%d)'):format(entry[2], i, #list) end
        paletteNames[palette] = names
    end
    return paletteNames[palette]
end
local function classicPosition(id)
    for i, entry in ipairs(PALETTES.classic) do if entry[1] == id then return i end end
    return nil
end

local NEON_COLORS = {
    { 255, 255, 255 }, { 2, 21, 255 }, { 3, 83, 255 }, { 0, 255, 140 }, { 94, 255, 1 }, { 255, 255, 0 }, { 255, 150, 5 },
    { 255, 62, 0 }, { 255, 0, 0 }, { 255, 50, 100 }, { 255, 5, 190 }, { 35, 1, 255 }, { 15, 3, 255 },
}
local NEON_FALLBACKS = { 'White', 'Blue', 'Electric Blue', 'Mint Green', 'Lime Green', 'Yellow', 'Golden Shower', 'Orange',
    'Red', 'Pony Pink', 'Hot Pink', 'Purple', 'Blacklight' }
local neonNames
local function neonColorNames()
    if not neonNames then
        neonNames = {}
        for i = 1, 13 do neonNames[i] = label(('CMOD_NEONCOL_%d'):format(i - 1), NEON_FALLBACKS[i]) end
    end
    return neonNames
end

local WHEEL_TYPES = { 'Sports', 'Muscle', 'Lowrider', 'SUV', 'Offroad', 'Tuner', 'Bike Wheels', 'High End', "Benny's (1)",
    "Benny's (2)", 'Open Wheel', 'Street', 'Track' }
local HEADLIGHT_COLORS = { 'White', 'Blue', 'Electric Blue', 'Mint Green', 'Lime Green', 'Yellow', 'Golden Shower', 'Orange',
    'Red', 'Pony Pink', 'Hot Pink', 'Purple', 'Blacklight', 'Default Xenon' }
-- Cortex tyre smoke presets. Black stays off 0,0,0, which the game treats specially.
local TYRE_SMOKES = {
    { 'White', 255, 255, 255 }, { 'Black', 8, 8, 8 }, { 'Grey', 128, 128, 132 }, { 'Red', 220, 30, 40 },
    { 'Orange', 255, 120, 20 }, { 'Yellow', 255, 210, 30 }, { 'Green', 40, 200, 70 }, { 'Teal', 0, 170, 160 },
    { 'Blue', 30, 90, 230 }, { 'Purple', 130, 50, 210 }, { 'Pink', 240, 90, 170 }, { 'Mint', 120, 230, 190 },
}
local TYRE_SMOKE_NAMES = {}
for i, smoke in ipairs(TYRE_SMOKES) do TYRE_SMOKE_NAMES[i] = smoke[1] end
-- Window Tint list position -> SET_VEHICLE_WINDOW_TINT value, and back.
local TINTS = { 'Stock [1/7]', 'None [2/7]', 'Limo [3/7]', 'Light Smoke [4/7]', 'Dark Smoke [5/7]', 'Pure Black [6/7]', 'Green [7/7]' }
local TINT_VALUE = { 4, 0, 5, 3, 2, 1, 6 }
local TINT_POSITION = { [-1] = 1, [0] = 2, [1] = 6, [2] = 5, [3] = 4, [4] = 1, [5] = 3, [6] = 7 }
-- vMenu's "Paint Finish" is Colour_Types; Chameleon (6) has no Cortex paintFinish value.
local PAINT_FINISHES = { 'Metallic', 'Classic', 'Pearlescent', 'Matte', 'Metals', 'Chrome', 'Chameleon' }
-- CitizenFX LocalizedModTypeName, used when the game has no slot label.
local SLOT_NAMES = {
    [0] = 'Spoilers', 'Front Bumper', 'Rear Bumper', 'Side Skirt', 'Exhaust', 'Frame', 'Grille', 'Hood', 'Fender', 'Right Fender',
    'Roof', 'Engine', 'Brakes', 'Transmission', 'Horns', 'Suspension', 'Armor', 'Nitrous', 'Turbo', 'Subwoofer', 'Tire Smoke',
    'Hydraulics', 'Xenon Lights', 'Front Wheels', 'Rear Wheels', 'Plate Holder', 'Vanity Plates', 'Trim Design', 'Ornaments',
    'Dashboard', 'Dial Design', 'Door Speakers', 'Seats', 'Steering Wheels', 'Shifter Leavers', 'Plaques', 'Speakers', 'Trunk',
    'Hydraulics', 'Engine Block', 'Air Filter', 'Struts', 'Arch Cover', 'Aerials', 'Trim', 'Tank', 'Windows', 'Doors', 'Livery',
    'Lightbar',
}
-- Mod Menu part lists by group. Toggle slots 17-22 are the Turbo, Tire Smoke and
-- Headlights rows; 23/24 sit under Wheel Type.
local PERFORMANCE_SLOTS = { 11, 12, 13, 15, 16 }
local BODY_SLOTS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 42, 43, 44, 45, 46, 47, 37, 25, 26, 48, 49 }
local INTERIOR_SLOTS = { 27, 28, 29, 30, 31, 32, 33, 34, 35, 36 }
local ENGINE_BAY_SLOTS = { 39, 40, 41, 38 }
local HORN_SLOT = 14

-- ---------------------------------------------------------------------------
-- Vehicle Options

local function passengerBlocked()
    local v = vehicle()
    if v and not isDriver(v) then VM.notify('error', DRIVER_MENU); return true end
    return false
end

-- vMenu's main-menu buttons act for the driver only (VehicleOptions.cs:495-565).
local function driverAction(actionId, text, description)
    return VM.action(actionId, text, description, nil, { onSelect = function()
        if passengerBlocked() then return end
        VM.execute(actionId, {})
    end })
end

-- vMenu toggles these on the current vehicle with a plain button.
local function vehicleToggleButton(actionId, text, description, isOn)
    if not VM.can(actionId) then return nil end
    return VM.button(text, description, function()
        if VM.denied(actionId) then return end
        local v = vehicle()
        if not v then VM.notify('error', NO_VEHICLE); return end
        if passengerBlocked() then return end
        Admin.toggleAction(actionId, not isOn(v))
    end, { key = actionId })
end

local function dirtValues()
    local values = { { label = 'No Dirt', value = 0 } }
    for i = 1, 15 do values[#values + 1] = { label = tostring(i), value = i } end
    return values
end

local PLATE_KEYS = { 'CMOD_PLA_0', 'CMOD_PLA_1', 'CMOD_PLA_2', 'CMOD_PLA_3', 'CMOD_PLA_4', 'PROL', 'CMOD_PLA_6', 'CMOD_PLA_7',
    'CMOD_PLA_8', 'CMOD_PLA_9', 'CMOD_PLA_10', 'CMOD_PLA_11', 'CMOD_PLA_12' }
local plateNames
local function plateValues()
    if not plateNames then
        plateNames = {}
        local catalog = (VM.descriptor('vehicle.plateType') or {}).values or {}
        for i, key in ipairs(PLATE_KEYS) do plateNames[i] = label(key, catalog[i] and catalog[i].label) end
    end
    return plateNames
end

local function setPlateText()
    if VM.denied('vehicle.changePlate') then return end
    local v = vehicle()
    if not v then return end
    if not isDriver(v) then VM.notify('error', DRIVER_MENU); return end
    local text = VM.input('Plate text, up to 8 characters.', GetVehicleNumberPlateText(v) or '', 8)
    if not text or text == '' then VM.notify('error', INVALID_INPUT); return end
    VM.execute('vehicle.changePlate', { plate = text })
end

-- Set / Reset / Custom Speed Limit. Cortex's limiter takes km/h; vMenu asks for m/s.
local function speedLimiter(position)
    local v = vehicle()
    if not v then return end
    if position == 1 then
        VM.execute('vehicle.speedLimiter', { speed = GetEntitySpeed(v) * 3.6 })
    elseif position == 2 then
        VM.execute('vehicle.clearSpeedLimit', {})
    else
        if VM.denied('vehicle.speedLimiter') then return end
        local input = VM.input('Top speed in metres per second.', '20.0', 5)
        if not input or input == '' then VM.notify('error', INVALID_INPUT); return end
        local speed = tonumber(input)
        if not speed then VM.notify('error', 'Use a number of metres per second, such as 20 or 35.5.'); return end
        VM.execute('vehicle.speedLimiter', { speed = speed * 3.6 })
    end
end

-- VehicleOptions.cs:209-212.
local MULTIPLIERS = {}
for power = 1, 10 do MULTIPLIERS[power] = { label = 'x' .. (2 ^ power | 0), value = 2.0 ^ power } end
local function multiplierList(actionId, text, description, current)
    local index = 1
    for i, entry in ipairs(MULTIPLIERS) do if entry.value == current then index = i end end
    return VM.select(actionId, text, description, { values = MULTIPLIERS, index = index, apply = 'change', onSelect = noop })
end

-- Hazard / indicators / interior / spotlight (VehicleOptions.cs:829-903). Cortex's
-- vehicle.lights action covers the same vMenu permission (VOLights) but only sets
-- headlight modes, so these local light natives run here.
local LIGHTS = { 'Hazard Lights', 'Left Indicator', 'Right Indicator', 'Interior Lights', 'Helicopter Spotlight' }
local function vehicleLights(position)
    if VM.denied('vehicle.lights') then return end
    local v = vehicle()
    if not v then VM.notify('error', NO_VEHICLE); return end
    local lit = GetVehicleIndicatorLights(v) % 4 -- 0 none, 1 left, 2 right, 3 both
    if position == 1 then
        SetVehicleIndicatorLights(v, 1, lit ~= 3); SetVehicleIndicatorLights(v, 0, lit ~= 3)
    elseif position == 2 then
        SetVehicleIndicatorLights(v, 1, lit ~= 1); SetVehicleIndicatorLights(v, 0, false)
    elseif position == 3 then
        SetVehicleIndicatorLights(v, 1, false); SetVehicleIndicatorLights(v, 0, lit ~= 2)
    elseif position == 4 then
        SetVehicleInteriorlight(v, not IsVehicleInteriorLightOn(v))
    elseif position == 5 then
        SetVehicleSearchlight(v, not IsVehicleSearchlightOn(v), true)
    end
end

local TYRES = { 'All Tires', 'Tire #1', 'Tire #2', 'Tire #3', 'Tire #4', 'Tire #5', 'Tire #6', 'Tire #7', 'Tire #8' }
local function fixOrDestroyTyre(position)
    if VM.denied('vehicle.tyres') then return end
    local v = vehicle()
    if not v then VM.notify('error', NO_VEHICLE); return end
    if not isDriver(v) then VM.notify('error', NEED_DRIVER); return end
    local tyre = position == 1 and 0 or position - 2
    local fix = nativeOn(IsVehicleTyreBurst(v, tyre, false))
    if position == 1 then
        Admin.selectAction('vehicle.tyres', fix and 'fix_all' or 'burst_all')
        VM.notify('success', fix and 'Every tyre is repaired.' or 'Every tyre is burst.')
    else
        Admin.selectAction('vehicle.tyres', (fix and 'fix_' or 'burst_') .. tyre)
        VM.notify('success', ('Tyre #%d is now %s.'):format(position - 1, fix and 'repaired' or 'burst'))
    end
end

local deleteRound = 0 -- a fresh confirm menu each time, so "NO, CANCEL" is highlighted
local radioRound = 0 -- turning the override on moves the station list to Los Santos Rock Radio

local function plateTypeRow()
    if not VM.can('vehicle.plateType') then return nil end
    local v = vehicle()
    local current = v and GetVehicleNumberPlateTextIndex(v) or 0
    if current < 0 or current > 12 then current = 0 end
    return VM.select('vehicle.plateType', 'License Plate Type', 'Pick a plate style, then press ~r~enter~s~ to fit it.', {
        key = liveKey('plateType', current), index = current + 1, values = plateValues(), onSelect = noop,
        onChange = function(position)
            if VM.denied('vehicle.plateType') then return end
            Admin.selectAction('vehicle.plateType', position - 1)
            bump()
        end,
    })
end

local mods -- Mod Menu snapshot: { vehicle, model, parts = { [slot] = { slot, label, names } } }
local function snapshotMods()
    local v = vehicle()
    mods = nil
    if not v or IsEntityDead(v) then return end
    if not HasThisAdditionalTextLoaded('mod_mnu', 10) then
        RequestAdditionalText('mod_mnu', 10)
        local deadline = GetGameTimer() + 1000
        while not HasThisAdditionalTextLoaded('mod_mnu', 10) and GetGameTimer() < deadline do Wait(0) end
        if vehicle() ~= v then return end
    end
    local _, _, custom = Admin.vehicleModKit(v)
    local parts, work = {}, 0
    -- Slot 24 is rear wheels on bikes only; on other vehicles the game reuses it.
    local bike = IsThisModelABike(GetEntityModel(v))
    for slot = 0, 49 do
        local count = math.min(GetNumVehicleMods(v, slot) or 0, 4096)
        if (slot < 17 or slot > 22) and (slot ~= 24 or bike) and Admin.vehicleModSlotOffered(v, slot, count) then
            local typeName = Admin.vehicleModSlotLabel(v, slot, custom) or SLOT_NAMES[slot]
            local names = { ('Stock %s [1/%d]'):format(typeName, count + 1) }
            for x = 0, count - 1 do
                local name = Admin.vehicleModPartLabel(v, slot, x, custom)
                names[#names + 1] = name and ('%s [%d/%d]'):format(properString(name), x + 2, count + 1)
                    or ('%s #%d [%d/%d]'):format(typeName, x, x + 2, count + 1)
                work = work + 1
                if work % 128 == 0 then Wait(0); if vehicle() ~= v then return end end
            end
            parts[slot] = { slot = slot, label = typeName, names = names }
        end
    end
    mods = { vehicle = v, model = GetEntityModel(v), parts = parts }
end

local function openMods()
    if VM.denied(MODS) then return end
    if not vehicle() then return end -- vMenu closes the Mod Menu again outside a vehicle
    snapshotMods()
    bump()
    if Admin.isVmenuModeOpen() then VM.open('vehicle_options_mods') end
end

local function openLiveries()
    if VM.denied(LIVERIES) then return end
    local v = vehicle()
    if not v or IsEntityDead(v) or not isDriver(v) then
        VM.notify('error', 'Liveries can only be changed from the driver seat.')
        return
    end
    if (GetVehicleLiveryCount(v) or 0) <= 0 then VM.notify('error', 'No liveries exist for this model.'); return end
    if Admin.isVmenuModeOpen() then VM.open('vehicle_options_liveries') end
end

local function arrow(text, description, onSelect, key)
    return VM.button(text, description, onSelect, { rightLabel = '→→→', key = key })
end

VM.define('vehicle_options', {
    subtitle = 'Vehicle Options',
    build = function()
        local god = VM.can('vehicle.invincible')
        local radioOn = VM.isOn('vehicle.defaultRadioEnabled')
        return {
            VM.toggle('vehicle.invincible', 'Vehicle God Mode', 'Stops this vehicle from taking damage. Choose which damage types are blocked in God Mode Options below.'),
            god and VM.submenu('vehicle_options_god', 'God Mode Options', 'Choose which kinds of damage the vehicle ignores.', nil, { hideEmpty = false }) or nil,
            driverAction('vehicle.repair', 'Repair Vehicle', 'Fixes all body, engine and cosmetic damage on this vehicle.'),
            driverAction('vehicle.maxMods', 'Max Vehicle Upgrades', 'Fits the best body and performance parts, plus turbo, xenon lights, dark window tint and bulletproof tyres.'),
            driverAction('vehicle.performanceMods', 'Max Performance Upgrades', 'Fits the best engine, brakes, transmission, suspension, armor and turbo only. Looks stay as they are.'),
            VM.toggle('vehicle.keepClean', 'Keep Vehicle Clean', 'Wipes off dust and dirt as soon as any builds up. ~o~Mud~s~, snow and ~r~damage decals~s~ stay until the vehicle is repaired.'),
            driverAction('vehicle.clean', 'Wash Vehicle', 'Removes all dirt from the vehicle once.'),
            VM.select('vehicle.dirtLevel', 'Set Dirt Level', 'Pick a dirt amount from 0 to 15, then press ~r~enter~s~ to apply it.', { values = dirtValues() }),
            VM.can(MODS) and arrow('Mod Menu', 'Fit performance parts, body parts, wheels and window tint.', openMods, 'mods') or nil,
            VM.can(COLORS) and VM.submenu('vehicle_options_colors', 'Vehicle Colors', 'Paint, pearlescent, wheel, trim and dashboard colours.', nil, { hideEmpty = false }) or nil,
            VM.can(NEON) and VM.submenu('vehicle_options_underglow', 'Vehicle Neon Kits', 'Switch underglow strips on or off and set their colour.', nil, { hideEmpty = false }) or nil,
            VM.can(LIVERIES) and arrow('Vehicle Liveries', 'Apply one of the livery designs this model ships with.', openLiveries, 'liveries') or nil,
            VM.can(EXTRAS) and VM.submenu('vehicle_options_extras', 'Vehicle Extras', "Turn the model's optional parts on or off.", nil, { hideEmpty = false }) or nil,
            vehicleToggleButton('vehicle.engine', 'Toggle Engine On/Off', 'Starts or stops the engine.', function(v) return nativeOn(GetIsVehicleEngineRunning(v)) end),
            VM.can('vehicle.changePlate') and VM.button('Set License Plate Text', 'Type new number plate text, up to 8 characters.', setPlateText, { key = 'vehicle.changePlate' }) or nil,
            plateTypeRow(),
            VM.can('vehicle.doors') and VM.submenu('vehicle_options_doors', 'Vehicle Doors', 'Open, shut or detach the doors, the hood and the trunk.', nil, { hideEmpty = false }) or nil,
            VM.can('vehicle.windows') and VM.submenu('vehicle_options_windows', 'Vehicle Windows', 'Raise or lower the front and rear windows.', nil, { hideEmpty = false }) or nil,
            VM.toggle('vehicle.bikeSeatbelt', 'Bike Seatbelt', 'Keeps you seated on bikes, bicycles, quads and similar when you crash.'),
            VM.can('vehicle.speedLimiter') and {
                kind = 'list', key = 'vehicle.speedLimiter', label = 'Speed Limiter', values = { 'Set', 'Reset', 'Custom Speed Limit' },
                description = 'Set caps this vehicle at your ~y~current speed~s~. Reset removes the cap. Custom Speed Limit asks for a value. Only the vehicle you are in is affected.',
                onSelect = speedLimiter,
            } or nil,
            VM.toggle('vehicle.torqueEnabled', 'Enable Torque Multiplier', 'Applies the torque value chosen in the list below.'),
            multiplierList('vehicle.torqueMultiplier', 'Set Engine Torque Multiplier', 'Torque scale used while the torque multiplier is on.', Admin.state.vehicleTorqueMultiplier),
            VM.toggle('vehicle.powerEnabled', 'Enable Power Multiplier', 'Applies the power value chosen in the list below.'),
            multiplierList('vehicle.powerMultiplier', 'Set Engine Power Multiplier', 'Power scale used while the power multiplier is on.', Admin.state.vehiclePowerMultiplier),
            VM.toggle('options.disablePlaneTurbulence', 'Disable Plane Turbulence', 'Removes air turbulence for every plane.'),
            VM.toggle('options.disableHelicopterTurbulence', 'Disable Helicopter Turbulence', 'Removes air turbulence for every helicopter.'),
            VM.toggle('vehicle.anchorBoat', 'Anchor Boat', 'Holds a boat in place. Works only in a boat, in water where anchoring is allowed.'),
            driverAction('vehicle.flip', 'Flip Vehicle', 'Turns the vehicle back onto its wheels.'),
            VM.action('vehicle.adminCar', 'Admin Car', 'Saves the vehicle you are in to your Qbox garage as an owned vehicle.'),
            VM.action('vehicle.giveKeys', 'Give Current Vehicle Keys', 'Gives you the keys for the vehicle you are in.'),
            VM.action('vehicle.camera', 'Vehicle Camera', 'Fly around your vehicle, save camera positions and switch between them while driving. Closes this menu.', nil, {
                onSelect = function()
                    if VM.denied('vehicle.camera') then return end
                    Admin.closeVmenuMode()
                    VM.execute('vehicle.camera')
                end,
            }),
            VM.can('vehicle.liveTuning') and VM.submenu('vehicle_tuning', 'Live Vehicle Tuning',
                'Change handling and engine sound on the vehicle you drive, live.', nil, { hideEmpty = false }) or nil,
            driverAction('vehicle.alarm', 'Toggle Vehicle Alarm', "Sound the alarm, or silence it."),
            VM.action('vehicle.cycleSeat', 'Cycle Through Vehicle Seats', 'Move to the next free seat.'),
            VM.can('vehicle.lights') and {
                kind = 'list', key = 'vehicle.lights', label = 'Vehicle Lights', values = LIGHTS,
                description = 'Switch the hazards, an indicator, the cabin light or a helicopter spotlight.', onSelect = vehicleLights,
            } or nil,
            VM.can('vehicle.tyres') and {
                kind = 'list', key = 'vehicle.tyres', label = 'Fix / Destroy Tires', values = TYRES, onSelect = fixOrDestroyTyre,
                description = 'Repairs a burst tyre or bursts an intact one, or all tyres at once. Some tyre numbers do not exist on every vehicle and do nothing there.',
            } or nil,
            driverAction('vehicle.destroyEngine', 'Destroy Engine', 'Breaks the engine so the vehicle cannot drive.'),
            VM.toggle('vehicle.freeze', 'Freeze Vehicle', 'Locks the vehicle where it stands.'),
            vehicleToggleButton('vehicle.invisible', 'Toggle Vehicle Visibility', 'Hides or shows this vehicle. ~r~It turns visible again when you get out, so you can get back in.~s~', function() return VM.isOn('vehicle.invisible') end),
            VM.toggle('vehicle.engineAlwaysOn', 'Engine Always On', 'The engine keeps running after you step out.'),
            VM.toggle('vehicle.infiniteFuel', 'Infinite Fuel', 'Stops this vehicle from using fuel. Requires the FRFuel resource.'),
            VM.toggle('vehicle.showHealth', 'Show Vehicle Health', 'Displays the vehicle health values on screen.'),
            VM.toggle('vehicle.defaultRadioEnabled', 'Enable Default Radio Station', 'Forces a chosen starting station in every vehicle.', {
                onCheck = function(checked)
                    if VM.denied('vehicle.defaultRadioEnabled') then return end
                    Admin.toggleAction('vehicle.defaultRadioEnabled', checked)
                    -- vMenu starts the override on Los Santos Rock Radio.
                    if checked and VM.can('vehicle.defaultRadioStation') then
                        Admin.selectAction('vehicle.defaultRadioStation', 'RADIO_01_CLASS_ROCK')
                        radioRound = radioRound + 1
                    end
                end,
            }),
            VM.select('vehicle.defaultRadioStation', 'Set Default Radio Station', 'Station that vehicles you spawn tune to first.', {
                key = 'radio:' .. radioRound, index = 2, enabled = radioOn, apply = 'change', onSelect = noop,
            }),
            VM.toggle('vehicle.noSiren', 'Disable Siren', 'Silences the siren. Has no effect on vehicles without one.'),
            VM.toggle('vehicle.noHelmet', 'No Bike Helmet', 'Stops your character putting on a helmet when mounting a bike or quad.'),
            VM.toggle('vehicle.flashHighbeams', 'Flash Highbeams On Honk', 'Flashes the high beams while you sound the horn. In daylight it only works with the headlights on.'),
            VM.can('vehicle.delete') and VM.submenu('vehicle_options_delete', '~r~Delete Vehicle', 'Removes this vehicle permanently. ~r~This cannot be reversed.~s~', { key = deleteRound }, {
                hideEmpty = false, onSelect = function() deleteRound = deleteRound + 1 end,
            }) or nil,
        }
    end,
})

VM.define('vehicle_options_god', {
    title = 'Vehicle Godmode', subtitle = 'Vehicle Godmode Options',
    build = function()
        return {
            VM.toggle('vehicle.invincible', 'Invincible', 'Blocks all damage, including fire, explosions and collisions.'),
            VM.toggle('vehicle.preventEngineDamage', 'Engine Damage', 'The engine takes no damage.'),
            VM.toggle('vehicle.preventVisualDamage', 'Visual Damage', 'Stops scratches and damage decals from appearing. Body deformation still happens.'),
            VM.toggle('vehicle.strongWheels', 'Strong Wheels', 'Wheels do not bend or hurt handling. Tyres can still burst.'),
            VM.toggle('vehicle.preventRampDamage', 'Ramp Damage', 'Ramp vehicles, such as the Ramp Buggy, take no damage from using the ramp.'),
            VM.toggle('vehicle.autoRepair', '~r~Auto Repair', 'Repairs the vehicle the moment it takes any damage. Best left off, as it can cause visual glitches.'),
        }
    end,
})

VM.define('vehicle_options_delete', {
    title = 'Confirm Action', subtitle = 'Delete Vehicle, Are You Sure?',
    build = function()
        if not VM.can('vehicle.delete') then return {} end
        return {
            VM.button('NO, CANCEL', 'Keep the vehicle and return to the previous menu.', VM.back),
            VM.button('~r~YES, DELETE', 'Delete this vehicle now. This is permanent.', function()
                VM.execute('vehicle.delete', {})
                VM.back()
            end),
        }
    end,
})

-- ---------------------------------------------------------------------------
-- RGB rows (CreateCustomColourMenu, VehicleOptions.cs:2571-2857)

local function headlightIndex(v)
    if v and IsToggleModOn(v, 22) then
        local value = GetVehicleXenonLightsColour(v)
        if value and value >= 0 and value <= 12 then return value end
    end
    return -1
end

local RGB = {
    primary = {
        action = COLORS,
        read = function(v) return GetVehicleCustomPrimaryColour(v) end,
        write = function(_, rgb) customize(COLORS, { type = 'customColor', id = 'primary', enabled = true, value = rgb }) end,
    },
    secondary = {
        action = COLORS,
        read = function(v) return GetVehicleCustomSecondaryColour(v) end,
        write = function(_, rgb) customize(COLORS, { type = 'customColor', id = 'secondary', enabled = true, value = rgb }) end,
    },
    underglow = {
        action = NEON,
        read = function(v) return GetVehicleNeonLightsColour(v) end,
        write = function(_, rgb) customize(NEON, { type = 'neonColor', value = rgb }) end,
    },
    tiresmoke = {
        action = COLORS,
        read = function(v) return GetVehicleTyreSmokeColor(v) end,
        write = function(_, rgb) customize(COLORS, { type = 'tyreSmokeColor', value = rgb }) end,
    },
    -- Cortex has no custom xenon RGB type; covered by the same Mod permission as the xenon colour.
    headlight = {
        action = MODS,
        read = function(v)
            local custom, r, g, b = GetVehicleXenonLightsCustomColor(v)
            if custom then return r, g, b end
            if IsToggleModOn(v, 22) then
                local color = NEON_COLORS[math.max(headlightIndex(v), 0) + 1]
                return color[1], color[2], color[3]
            end
            return 0, 0, 0
        end,
        write = function(v, rgb)
            if control(v) then SetVehicleXenonLightsCustomColor(v, rgb[1], rgb[2], rgb[3]) end
            bump()
        end,
    },
}

local function readRgb(kind, v)
    if not v then return 0, 0, 0 end
    local r, g, b = RGB[kind].read(v)
    return math.floor(tonumber(r) or 0), math.floor(tonumber(g) or 0), math.floor(tonumber(b) or 0)
end

local function hexColor(kind)
    local spec = RGB[kind]
    if VM.denied(spec.action) then return end
    local v = vehicle()
    if not v then return end
    local result = VM.input('Six-digit hex colour, such as FF8000.', ('%02X%02X%02X'):format(readRgb(kind, v)), 6)
    if not result or result == '' or not result:match('^%x+$') then return end
    local value = tonumber(result, 16)
    if vehicle() ~= v then return end
    spec.write(v, { (value >> 16) & 255, (value >> 8) & 255, value & 255 })
end

local function setChannel(kind, channel, value)
    local spec = RGB[kind]
    if VM.denied(spec.action) then return end
    local v = vehicle()
    if not v then bump(); return end
    local rgb = { readRgb(kind, v) }
    rgb[channel] = value
    spec.write(v, rgb)
end

local CHANNELS = { 'Red Color', 'Green Color', 'Blue Color' }
local function rgbRows(kind, rows)
    if not VM.can(RGB[kind].action) then return end
    local rgb = { readRgb(kind, vehicle()) }
    rows[#rows + 1] = VM.button('Hex Color Code', nil, function() hexColor(kind) end, { key = kind .. ':hex' })
    for channel, text in ipairs(CHANNELS) do
        rows[#rows + 1] = {
            kind = 'slider', key = liveKey(kind .. ':' .. channel, rgb[channel]), label = ('%s (%d)'):format(text, rgb[channel]),
            min = 0, max = 255, value = rgb[channel],
            onChange = function(value) setChannel(kind, channel, value) end,
        }
    end
end

VM.define('vehicle_options_custom_colour', {
    title = 'Custom Colour', subtitle = 'Custom Vehicle Colour',
    build = function(args)
        local kind = type(args) == 'table' and args.key
        if (kind ~= 'primary' and kind ~= 'secondary') or not VM.can(COLORS) then return {} end
        local rows = {}
        rgbRows(kind, rows)
        rows[#rows + 1] = {
            kind = 'list', key = kind .. ':finish', label = 'Paint Finish', values = PAINT_FINISHES,
            onChange = function(position) customize(COLORS, { type = 'paintFinish', id = kind, value = position - 1 }) end,
        }
        return rows
    end,
})

-- ---------------------------------------------------------------------------
-- Mod Menu (UpdateMods, VehicleOptions.cs:2036-2487)

local function changeWheelType(position, _, oldPosition)
    local v = vehicle()
    if not v then bump(); return end
    local newIndex, oldIndex = position - 1, (oldPosition or position) - 1
    local isBike, openWheel = IsThisModelABike(GetEntityModel(v)), GetVehicleClass(v) == 22
    local valid = (newIndex == 6 and isBike) or (newIndex == 10 and openWheel)
        or (newIndex ~= 6 and newIndex ~= 10 and not isBike and not openWheel)
    if not valid then
        if not isBike and not openWheel then
            newIndex = (newIndex + (newIndex > oldIndex and 1 or -1)) % #WHEEL_TYPES
        else
            newIndex = isBike and 6 or 10
        end
    end
    if not customize(MODS, { type = 'wheelType', value = newIndex }) then return end
    if (GetNumVehicleMods(v, 23) or 0) > 0 then customize(MODS, { type = 'mod', id = 23, value = -1 }, true) end
    if isBike and (GetNumVehicleMods(v, 24) or 0) > 0 then customize(MODS, { type = 'mod', id = 24, value = -1 }, true) end
    snapshotMods() -- the wheel lists change with the wheel type
end

local function toggleCustomWheels()
    if VM.denied(MODS) then return end
    local v = vehicle()
    if not v or not control(v) then bump(); return end
    local custom = not nativeOn(GetVehicleModVariation(v, 23))
    SetVehicleMod(v, 23, GetVehicleMod(v, 23), custom)
    if IsThisModelABike(GetEntityModel(v)) then SetVehicleMod(v, 24, GetVehicleMod(v, 24), custom) end
    bump()
end

local function toggleMod(slot)
    return function(checked) customize(MODS, { type = 'mod', id = slot, isToggle = true, enabled = checked }) end
end

VM.define('vehicle_options_mods', {
    title = 'Mod Menu', subtitle = 'Vehicle Mods',
    buttons = { { control = 22, label = 'Toggle Vehicle Doors', on = 'press', run = function()
        if VM.denied(MODS) then return end
        local v = driven()
        if not v then return end
        local open = GetVehicleDoorAngleRatio(v, 0) < 0.1
        for door = 0, 7 do
            if open then SetVehicleDoorOpen(v, door, false, false) else SetVehicleDoorShut(v, door, false) end
        end
    end } },
    build = function()
        if not VM.can(MODS) then return {} end
        local v = vehicle()
        if not mods or not v or v ~= mods.vehicle or GetEntityModel(v) ~= mods.model or IsEntityDead(v) then return {} end
        local rows = {}
        local function partRows(slots)
            for _, slot in ipairs(slots) do
                local entry = mods.parts[slot]
                if entry then
                    local current = GetVehicleMod(v, slot) + 1 -- 0 is stock
                    if current >= #entry.names then current = 0 end
                    rows[#rows + 1] = {
                        kind = 'list', key = liveKey('mod' .. slot, current), label = entry.label, values = entry.names, index = current + 1,
                        description = slot == HORN_SLOT and 'Pick a ~y~horn~s~. It is fitted and played as soon as you select it.'
                            or ('Pick a ~y~%s~s~ part. It is fitted as soon as you select it.'):format(entry.label),
                        onChange = function(position)
                            if customize(MODS, { type = 'mod', id = slot, value = position - 2 }) and slot == HORN_SLOT then
                                local fitted = driven()
                                if fitted then StartVehicleHorn(fitted, 1000, joaat('NORMAL'), false) end
                            end
                        end,
                    }
                end
            end
        end
        -- Performance
        partRows(PERFORMANCE_SLOTS)
        rows[#rows + 1] = {
            kind = 'checkbox', key = 'turbo', label = 'Turbo', description = 'Fits or removes the ~y~turbo~s~ upgrade.',
            checked = nativeOn(IsToggleModOn(v, 18)), onCheck = toggleMod(18),
        }
        -- Wheels: the type first, since changing it resets the rims below it.
        local model = GetEntityModel(v)
        if not (IsThisModelABoat(model) or IsThisModelAHeli(model) or IsThisModelAPlane(model)
            or IsThisModelABicycle(model) or IsThisModelATrain(model)) then
            local wheelType = math.max(0, math.min(GetVehicleWheelType(v), 12))
            rows[#rows + 1] = {
                kind = 'list', key = liveKey('wheelType', wheelType), label = 'Wheel Type', values = WHEEL_TYPES, index = wheelType + 1,
                description = 'Wheel category, such as ~y~sport~s~ or ~y~offroad~s~. Changing it puts the rims back to stock.', onChange = changeWheelType,
            }
        end
        partRows({ 23, 24 })
        rows[#rows + 1] = {
            kind = 'checkbox', key = 'customWheels', label = 'Toggle Custom Wheels', description = 'Use the ~y~custom~s~ tyre variant of the current rims.',
            checked = nativeOn(GetVehicleModVariation(v, 23)), onCheck = toggleCustomWheels,
        }
        rows[#rows + 1] = VM.toggle('vehicle.bulletproofTyres', 'Bullet Proof Tires', 'Makes the tyres ~y~bulletproof~s~ so they cannot be shot out.')
        if GetGameBuildNumber() >= 2372 then
            rows[#rows + 1] = VM.toggle('vehicle.lowGripTyres', 'Low Grip Tires', 'Fits ~y~low grip~s~ tyres that slide more easily.')
        end
        rows[#rows + 1] = VM.submenu('vehicle_options_tire_smoke', 'Tire Smoke', nil, nil, { rightLabel = false, hideEmpty = false })
        -- Body, then lights, glass and horn
        partRows(BODY_SLOTS)
        rows[#rows + 1] = VM.submenu('vehicle_options_headlights', 'Headlights', nil, nil, { rightLabel = false, hideEmpty = false })
        local tint = TINT_POSITION[GetVehicleWindowTint(v)] or 1
        rows[#rows + 1] = {
            kind = 'list', key = liveKey('tint', tint), label = 'Window Tint', values = TINTS, index = tint,
            description = 'How dark the window glass is.',
            onChange = function(position) customize(MODS, { type = 'window', value = TINT_VALUE[position] }) end,
        }
        partRows({ HORN_SLOT })
        -- Interior, then engine bay
        partRows(INTERIOR_SLOTS)
        partRows(ENGINE_BAY_SLOTS)
        return rows
    end,
})

local function setHeadlightColor(position)
    if VM.denied(MODS) then return end
    local v = driven() -- vMenu's SetHeadlightsColorForVehicle ignores non-drivers
    if not v then bump(); return end
    if position <= 13 and control(v) then ClearVehicleXenonLightsCustomColor(v) end
    customize(MODS, { type = 'xenonColor', value = position == 14 and 255 or position - 1 })
end

VM.define('vehicle_options_headlights', {
    title = 'Headlights', subtitle = 'headlights',
    build = function()
        if not VM.can(MODS) then return {} end
        local v = vehicle()
        local color = headlightIndex(v)
        local position = color < 0 and 14 or color + 1
        local rows = {
            {
                kind = 'checkbox', key = 'xenon', label = 'Xenon Headlights', description = 'Switches between stock and ~b~xenon~s~ headlights.',
                checked = v ~= nil and nativeOn(IsToggleModOn(v, 22)), onCheck = toggleMod(22),
            },
            {
                kind = 'list', key = liveKey('headlightColor', position), label = 'Headlight Color', values = HEADLIGHT_COLORS, index = position,
                description = 'Colour of the xenon beams. Turn on Xenon Headlights first.',
                onChange = setHeadlightColor,
            },
        }
        rgbRows('headlight', rows)
        return rows
    end,
})

local function tyreSmokePosition(v)
    if not v then return 1 end
    local r, g, b = GetVehicleTyreSmokeColor(v)
    for i, smoke in ipairs(TYRE_SMOKES) do
        if smoke[2] == r and smoke[3] == g and smoke[4] == b then return i end
    end
    return 1
end

VM.define('vehicle_options_tire_smoke', {
    title = 'Tire Smoke', subtitle = 'Tire Smoke',
    build = function()
        local v = vehicle()
        local position = tyreSmokePosition(v)
        local rows = {}
        if VM.can(COLORS) then
            rows[#rows + 1] = {
                kind = 'list', key = liveKey('tyreSmoke', position), label = 'Tire Smoke Color', values = TYRE_SMOKE_NAMES, index = position,
                description = 'Colour of the ~y~burnout smoke~s~.',
                onChange = function(next)
                    local smoke = TYRE_SMOKES[next]
                    customize(COLORS, { type = 'tyreSmokeColor', value = { smoke[2], smoke[3], smoke[4] } })
                end,
            }
        end
        if VM.can(MODS) then
            rows[#rows + 1] = {
                kind = 'checkbox', key = 'tyreSmokeOn', label = 'Tire Smoke', checked = v ~= nil and nativeOn(IsToggleModOn(v, 20)),
                description = 'Turns ~y~tyre smoke~s~ on or off. ~h~~r~Note:~s~ after turning it off, drive for a moment before the smoke stops.',
                onCheck = function(checked)
                    if VM.denied(MODS) then return end
                    local smoke = TYRE_SMOKES[tyreSmokePosition(vehicle())]
                    if checked then
                        if customize(MODS, { type = 'mod', id = 20, isToggle = true, enabled = true }) and VM.can(COLORS) then
                            customize(COLORS, { type = 'tyreSmokeColor', value = { smoke[2], smoke[3], smoke[4] } })
                        end
                    else
                        if VM.can(COLORS) then customize(COLORS, { type = 'tyreSmokeColor', value = { 255, 255, 255 } }, true) end
                        customize(MODS, { type = 'mod', id = 20, isToggle = true, enabled = false })
                    end
                end,
            }
        end
        rgbRows('tiresmoke', rows)
        return rows
    end,
})

-- ---------------------------------------------------------------------------
-- Vehicle Colors (VehicleOptions.cs:1036-1399)

local function setColor(id, value)
    if not driven(DRIVER_COLORS) then bump(); return false end
    return customize(COLORS, { type = 'color', id = id, value = value })
end

local function classicList(key, text, current, id)
    local position = classicPosition(current) or 1
    return {
        kind = 'list', key = liveKey(key, position), label = text, values = colorNames('classic'), index = position,
        onChange = function(next) setColor(id, PALETTES.classic[next][1]) end,
    }
end

VM.define('vehicle_options_colors', {
    title = 'Vehicle Colors', subtitle = 'Vehicle Colors',
    build = function()
        if not VM.can(COLORS) then return {} end
        local v = vehicle()
        local enveff, wheel, dashboard, trim = 10, 156, 0, 0
        if v then
            local scale = tonumber(GetVehicleEnveffScale(v)) or 0.5
            if scale ~= scale then scale = 0.5 end -- NaN on vehicles without the effect
            enveff = math.max(0, math.min(20, math.floor(scale * 20 + 0.5)))
            local _, wheelColor = GetVehicleExtraColours(v)
            wheel, dashboard, trim = wheelColor, GetVehicleInteriorColour(v), GetVehicleDashboardColour(v)
        end
        local wheelPosition = wheel == 156 and 1 or ((classicPosition(wheel) or 0) + 1)
        local wheelValues = { 'Default Alloy' }
        for _, name in ipairs(colorNames('classic')) do wheelValues[#wheelValues + 1] = name end
        return {
            VM.submenu('vehicle_options_colors_customize', 'Customize Colors', nil, nil, { hideEmpty = false }),
            {
                kind = 'slider', key = liveKey('enveff', enveff), label = 'Vehicle Enveff Scale', min = 0, max = 20, value = enveff,
                description = 'Fades some paint layers. Only certain models react, such as the Besra.',
                onChange = function(value)
                    if not driven('Take the driver seat of a working vehicle to move this slider.') then bump(); return end
                    customize(COLORS, { type = 'enveff', value = value / 20 })
                end,
            },
            -- vMenu writes the dashboard with SET_VEHICLE_INTERIOR_COLOUR and the trim with
            -- SET_VEHICLE_DASHBOARD_COLOUR (the native names are swapped); Cortex's trim/dashboard ids map to those natives.
            classicList('dashboard', 'Dashboard Color', dashboard, 'trim'),
            classicList('trim', 'Interior / Trim Color', trim, 'dashboard'),
            {
                kind = 'list', key = liveKey('wheelColor', wheelPosition), label = 'Wheel Color', values = wheelValues, index = wheelPosition,
                onChange = function(next) setColor('wheel', next == 1 and 156 or PALETTES.classic[next - 1][1]) end,
            },
        }
    end,
})

local function setPreset(position)
    if VM.denied(COLORS) then return end
    local v = driven(DRIVER_DRIVEABLE)
    if v and control(v) then SetVehicleColourCombination(v, position - 1) end
    bump()
end

VM.define('vehicle_options_colors_customize', {
    title = 'Vehicle Colors', subtitle = 'Customize Colors',
    build = function()
        if not VM.can(COLORS) then return {} end
        local v = vehicle()
        local count = v and GetNumberOfVehicleColours(v) or 0
        local preset
        if count <= 0 then
            preset = { kind = 'list', key = 'preset:none', label = 'Preset Colors', values = { 'No Preset Colors' }, enabled = false }
        else
            local values = {}
            for i = 1, count do values[i] = ('Preset Color #%d'):format(i) end
            local current = math.max(GetVehicleColourCombination(v), 0) + 1
            preset = {
                kind = 'list', key = liveKey('preset', current), label = 'Preset Colors', values = values, index = current,
                onChange = setPreset, onSelect = setPreset,
            }
        end
        return {
            VM.submenu('vehicle_options_colors_primary', 'Primary Color', nil, nil, { hideEmpty = false }),
            VM.submenu('vehicle_options_colors_secondary', 'Secondary Color', nil, nil, { hideEmpty = false }),
            preset,
            VM.button('Chrome', nil, function()
                if VM.denied(COLORS) or not driven(DRIVER_DRIVEABLE) then return end
                if customize(COLORS, { type = 'color', id = 'primary', value = 120 }) then
                    customize(COLORS, { type = 'color', id = 'secondary', value = 120 })
                end
            end, { key = 'chrome' }),
        }
    end,
})

-- { label, palette, Cortex colour id }; Metallic also sets the pearlescent layer.
local PRIMARY_LISTS = { { 'Classic', 'classic' }, { 'Metallic', 'classic' }, { 'Matte', 'matte' }, { 'Metals', 'metals' },
    { 'Util', 'util' }, { 'Worn', 'worn' } }
local SECONDARY_LISTS = { { 'Pearlescent', 'classic', 'pearlescent' }, { 'Classic', 'classic' }, { 'Metallic', 'classic' },
    { 'Matte', 'matte' }, { 'Metals', 'metals' }, { 'Util', 'util' }, { 'Worn', 'worn' } }

local function paintMenu(kind, lists)
    return function()
        if not VM.can(COLORS) then return {} end
        local rows = { VM.submenu('vehicle_options_custom_colour', 'Custom RGB', nil, { key = kind }, { hideEmpty = false }) }
        for _, list in ipairs(lists) do
            rows[#rows + 1] = {
                kind = 'list', key = kind .. ':' .. list[1], label = list[1], values = colorNames(list[2]),
                onChange = function(position)
                    local id = PALETTES[list[2]][position][1]
                    if list[3] then setColor(list[3], id); return end
                    if setColor(kind, id) and kind == 'primary' then
                        customize(COLORS, { type = 'color', id = 'pearlescent', value = list[1] == 'Metallic' and id or 0 })
                    end
                end,
            }
        end
        if Admin.vmenuSetting and Admin.vmenuSetting('vmenu_using_chameleon_colours', false) then
            local colors = EsAdminVmenuReference.chameleonColors
            local names = {}
            for index, color in ipairs(colors) do names[index] = label(color[2], color[3]) end
            rows[#rows + 1] = { kind = 'list', key = kind .. ':chameleon', label = 'Chameleon', values = names,
                onChange = function(position) setColor(kind, colors[position][1]) end }
        end
        return rows
    end
end

VM.define('vehicle_options_colors_primary', { title = 'Vehicle Colors', subtitle = 'Primary Colors', build = paintMenu('primary', PRIMARY_LISTS) })
VM.define('vehicle_options_colors_secondary', { title = 'Vehicle Colors', subtitle = 'Secondary Colors', build = paintMenu('secondary', SECONDARY_LISTS) })

-- ---------------------------------------------------------------------------
-- Vehicle Neon Kits (VehicleOptions.cs:1823-1951). Native neon indexes: 0 left, 1 right, 2 front, 3 back.

local NEON_LIGHTS = {
    { 'Enable Front Light', 'front', 2, 'neon_f', 'Front underglow strip. Not every vehicle can fit one.' },
    { 'Enable Rear Light', 'back', 3, 'neon_b', 'Rear underglow strip. Not every vehicle can fit one.' },
    { 'Enable Left Light', 'left', 0, 'neon_l', 'Left underglow strip. Not every vehicle can fit one.' },
    { 'Enable Right Light', 'right', 1, 'neon_r', 'Right underglow strip. Not every vehicle can fit one.' },
}

local function hasNeon(v, bone) return GetEntityBoneIndexByName(v, bone) ~= -1 end
local function hasNeonKit(v)
    if not v then return false end
    for _, light in ipairs(NEON_LIGHTS) do if hasNeon(v, light[4]) then return true end end
    return false
end
-- vMenu's GetIndexFromColor; nil when the colour is custom.
local function neonPosition(v)
    local r, g, b = GetVehicleNeonLightsColour(v)
    if r == 255 and g == 0 and b == 255 then return 1 end -- no colour picked yet
    for i, color in ipairs(NEON_COLORS) do
        if color[1] == r and color[2] == g and color[3] == b then return i end
    end
    return nil
end

local function setNeon(light, checked)
    if VM.denied(NEON) then return end
    local v = vehicle()
    if not v or not hasNeonKit(v) then bump(); return end
    -- vMenu re-applies the list colour first; a custom RGB colour is kept.
    local position = neonPosition(v)
    if position then customize(NEON, { type = 'neonColor', value = NEON_COLORS[position] }, true) end
    customize(NEON, { type = 'neon', id = light[2], value = hasNeon(v, light[4]) and checked })
end

VM.define('vehicle_options_underglow', {
    title = 'Vehicle Neon Kits', subtitle = 'Vehicle Neon Underglow Options',
    build = function()
        if not VM.can(NEON) then return {} end
        local v = vehicle()
        local kit = hasNeonKit(v)
        local rows = {}
        for _, light in ipairs(NEON_LIGHTS) do
            rows[#rows + 1] = {
                kind = 'checkbox', key = 'neon:' .. light[2], label = light[1], description = light[5], enabled = kit,
                checked = kit and hasNeon(v, light[4]) and nativeOn(IsVehicleNeonLightEnabled(v, light[3])) or false,
                onCheck = function(checked) setNeon(light, checked) end,
            }
        end
        local position = kit and neonPosition(v) or 1
        rows[#rows + 1] = {
            kind = 'list', key = liveKey('neonColor', position), label = label('CMOD_NEON_1', 'Neon Color'), values = neonColorNames(), index = position,
            description = 'Preset colour for the underglow strips.',
            onChange = function(next)
                local current = vehicle()
                if not current or not hasNeonKit(current) then bump(); return end
                customize(NEON, { type = 'neonColor', value = NEON_COLORS[next] })
            end,
        }
        rgbRows('underglow', rows)
        return rows
    end,
})

-- ---------------------------------------------------------------------------
-- Vehicle Liveries / Vehicle Extras

local liveryCache = {}
local function liveryNames(v, count)
    local key = ('%d:%d:%d'):format(v, GetEntityModel(v), count)
    if not liveryCache[key] then
        local names = {}
        for i = 0, count - 1 do
            local name = GetLiveryName(v, i)
            names[#names + 1] = type(name) == 'string' and name ~= '' and label(name, ('Livery #%d'):format(i)) or ('Livery #%d'):format(i)
        end
        liveryCache = { [key] = names }
    end
    return liveryCache[key]
end

VM.define('vehicle_options_liveries', {
    title = 'Vehicle Liveries', subtitle = 'Vehicle Liveries',
    build = function()
        if not VM.can(LIVERIES) then return {} end
        local v = driven()
        local count = v and (GetVehicleLiveryCount(v) or 0) or 0
        if count <= 0 then
            return { VM.button('No Liveries Available :(', 'This model has no liveries. Select to return.', VM.back, { rightLabel = 'Go Back' }) }
        end
        local livery = math.max(GetVehicleLivery(v), 0)
        return {
            {
                kind = 'list', key = liveKey('livery', livery), label = 'Set Livery', values = liveryNames(v, count), index = livery + 1,
                description = "Pick one of this model's paint schemes.",
                onChange = function(position) customize(LIVERIES, { type = 'livery', value = position - 1 }) end,
            },
        }
    end,
})

-- Extra names from an imported vMenu config (vMenu's VehicleExtras), as the Cortex panel reads them.
local extraLabelCache = {}
local function u32(value) value = tonumber(value); return value and math.floor(value) % 4294967296 end
local function extraLabels(model)
    local target = u32(model)
    if extraLabelCache[target] then return extraLabelCache[target] end
    local labels = {}
    local config = type(Admin.getVmenuImportedConfig) == 'function' and Admin.getVmenuImportedConfig() or {}
    for rawModel, rawLabels in pairs(type(config.extras) == 'table' and config.extras or {}) do
        if u32(type(rawModel) == 'string' and joaat(rawModel) or rawModel) == target and type(rawLabels) == 'table' then
            for id, text in pairs(rawLabels) do
                if tonumber(id) and type(text) == 'string' and text ~= '' then labels[math.floor(tonumber(id))] = text:sub(1, 80) end
            end
            break
        end
    end
    extraLabelCache[target] = labels
    return labels
end

VM.define('vehicle_options_extras', {
    title = 'Vehicle Extras', subtitle = 'Vehicle Extras/Components',
    build = function()
        if not VM.can(EXTRAS) then return {} end
        local v = driven()
        if not v then return {} end
        local labels = extraLabels(GetEntityModel(v))
        local rows = {}
        for extra = 0, 13 do
            if DoesExtraExist(v, extra) then
                rows[#rows + 1] = {
                    kind = 'checkbox', key = 'extra:' .. extra, label = labels[extra] or ('Extra #%d'):format(extra),
                    description = tostring(extra), checked = nativeOn(IsVehicleExtraTurnedOn(v, extra)),
                    onCheck = function(checked) customize(EXTRAS, { type = 'extra', id = extra, enabled = checked }) end,
                }
            end
        end
        if #rows > 0 then
            rows[#rows + 1] = VM.button('Go Back', 'Return to Vehicle Options.', VM.back)
        else
            rows[1] = VM.button('No Extras Available :(', 'Return to Vehicle Options.', VM.back, { rightLabel = 'Go Back' })
        end
        return rows
    end,
})

-- ---------------------------------------------------------------------------
-- Vehicle Doors / Vehicle Windows

local DOORS = {
    { 'Left Front Door', 'Opens or shuts the front left door.' }, { 'Right Front Door', 'Opens or shuts the front right door.' },
    { 'Left Rear Door', 'Opens or shuts the rear left door.' }, { 'Right Rear Door', 'Opens or shuts the rear right door.' },
    { 'Hood', 'Opens or shuts the hood.' }, { 'Trunk', 'Opens or shuts the trunk.' },
    { 'Extra 1', 'Opens or shuts extra door 1. Most vehicles do not have it.' },
    { 'Extra 2', 'Opens or shuts extra door 2. Most vehicles do not have it.' },
}
local REMOVE_DOORS = {}
for i, name in ipairs({ 'Front Left', 'Front Right', 'Rear Left', 'Rear Right', 'Hood', 'Trunk', 'Extra 1', 'Extra 2' }) do
    REMOVE_DOORS[i] = { label = name, value = 'remove_' .. (i - 1) }
end

local function door(command)
    return function()
        if VM.denied('vehicle.doors') then return end
        if not driven('Take the driver seat to open or shut doors.') then return end
        Admin.selectAction('vehicle.doors', command)
    end
end

VM.define('vehicle_options_doors', {
    title = 'Vehicle Doors', subtitle = 'Vehicle Doors Management',
    build = function()
        local rows = {}
        if VM.can('vehicle.doors') then
            for i, entry in ipairs(DOORS) do rows[#rows + 1] = VM.button(entry[1], entry[2], door('toggle_' .. (i - 1)), { key = 'door:' .. i }) end
            rows[#rows + 1] = VM.button('Bomb Bay', 'Opens or shuts the bomb bay on planes that have one.', door('bomb_bay'))
            rows[#rows + 1] = VM.button('Open All Doors', 'Swings every door, the hood and the trunk open.', door('open_all'))
            rows[#rows + 1] = VM.button('Close All Doors', 'Shut every door, the hood and the trunk.', door('close_all'))
            rows[#rows + 1] = VM.select('vehicle.doors', 'Remove Door', 'Detach one door from the vehicle.', {
                key = 'removeDoor', values = REMOVE_DOORS,
                onSelect = function(position)
                    if VM.denied('vehicle.doors') then return end
                    local v = vehicle()
                    if not v then VM.notify('error', NO_VEHICLE); return end
                    if not isDriver(v) then VM.notify('error', NEED_DRIVER); return end
                    Admin.selectAction('vehicle.doors', REMOVE_DOORS[position].value)
                end,
            })
        end
        rows[#rows + 1] = VM.toggle('vehicle.deleteRemovedDoors', 'Delete Removed Doors', 'When on, doors you remove with the list above disappear. When off, they drop to the ground.')
        return rows
    end,
})

local function windows(command)
    return function()
        if VM.denied('vehicle.windows') then return end
        Admin.selectAction('vehicle.windows', command)
    end
end

VM.define('vehicle_options_windows', {
    title = 'Vehicle Windows', subtitle = 'Vehicle Windows Management',
    build = function()
        if not VM.can('vehicle.windows') then return {} end
        return {
            VM.button('~y~↑~s~ Roll Front Windows Up', 'Raises the driver and front passenger windows.', windows('front_up')),
            VM.button('~o~↓~s~ Roll Front Windows Down', 'Lowers the driver and front passenger windows.', windows('front_down')),
            VM.button('~y~↑~s~ Roll Rear Windows Up', 'Raises both back windows.', windows('rear_up')),
            VM.button('~o~↓~s~ Roll Rear Windows Down', 'Lowers both back windows.', windows('rear_down')),
        }
    end,
})
