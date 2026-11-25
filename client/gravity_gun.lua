-- Gravity gun (beta): with any weapon drawn, aim at a networked vehicle, prop or
-- NPC and fire to lift it. It floats at the crosshair while you keep aiming;
-- fire again to throw it, stop aiming to drop it, scroll to change the distance.
-- Firing is only suppressed while something is targeted or held, so the gun in
-- your hand still shoots everything else. The thread exists only while the
-- toggle is on and sleeps unless you are aiming.
local Admin = EsAdmin

local RANGE, HOLD_MIN, HOLD_MAX = 40.0, 2.5, 30.0
local PULL, MAX_SPEED = 9.0, 45.0
local THROW_SPEED, THROW_SPEED_VEHICLE = 42.0, 30.0
local CONTROL_GRACE_MS = 1000
local SHAPE_FLAGS = 2 | 4 | 8 | 16 -- vehicles, peds, ragdolls, objects
local ACCENT_FALLBACK = { 143, 203, 191 }
local UNARMED = joaat('WEAPON_UNARMED')

local enabled, running = false, false
local held, heldDistance, heldSince, heldLastControl = nil, 8.0, 0, 0
local heldPhysicsReady = false
local outlined = nil

local function accentColour()
    local ok, data = pcall(function() return exports['cortex-lib']:getPresentation() end)
    local hex = ok and type(data) == 'table' and type(data.profile) == 'table' and data.profile.accent
    if type(hex) ~= 'string' or not hex:match('^#%x%x%x%x%x%x$') then return ACCENT_FALLBACK end
    return { tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16) }
end

local function setOutline(entity)
    -- Cfx's outline renderer does not support ped draw handlers and can
    -- crash the process. NPCs remain grabbable without an outline.
    if entity and (not DoesEntityExist(entity) or GetEntityType(entity) == 1) then entity = nil end
    if outlined == entity then return end
    if outlined and DoesEntityExist(outlined) and GetEntityType(outlined) ~= 1 then SetEntityDrawOutline(outlined, false) end
    outlined = entity
    if entity then
        local colour = accentColour()
        SetEntityDrawOutlineColor(colour[1], colour[2], colour[3], 255)
        SetEntityDrawOutline(entity, true)
    end
end

local function cameraForward()
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local scale = math.abs(math.cos(pitch))
    return vector3(-math.sin(yaw) * scale, math.cos(yaw) * scale, math.sin(pitch))
end

local function hasPlayerOccupant(vehicle)
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        local occupant = GetPedInVehicleSeat(vehicle, seat)
        if occupant ~= 0 and IsPedAPlayer(occupant) then return true end
    end
    return false
end

-- Only networked entities can be moved for everyone; players and cars with
-- players in them are left alone.
local function grabbable(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if not NetworkGetEntityIsNetworked(entity) then return false end
    local kind = GetEntityType(entity)
    if kind == 1 then return not IsPedAPlayer(entity) end
    if kind == 2 then return not hasPlayerOccupant(entity) end
    return kind == 3
end

local function aimedEntity(ped)
    local origin = GetGameplayCamCoord()
    local target = origin + cameraForward() * RANGE
    local probe = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z, target.x, target.y, target.z, SHAPE_FLAGS, ped, 7)
    local _, hit, point, _, entity = GetShapeTestResult(probe)
    if hit ~= 1 or not grabbable(entity) then return nil end
    return entity, #(point - origin)
end

local function release(throw)
    local entity = held
    held = nil
    heldPhysicsReady = false
    if not entity or not DoesEntityExist(entity) then return end
    SetEntityNoCollisionEntity(entity, PlayerPedId(), true)
    if throw and NetworkHasControlOfEntity(entity) then
        local speed = GetEntityType(entity) == 2 and THROW_SPEED_VEHICLE or THROW_SPEED
        local velocity = cameraForward() * speed
        if GetEntityType(entity) == 1 then SetPedToRagdoll(entity, 4000, 4000, 0, false, false, false) end
        SetEntityVelocity(entity, velocity.x, velocity.y, velocity.z)
    end
end

local function grab(entity, distance)
    if not grabbable(entity) then return end
    held, heldSince, heldLastControl = entity, GetGameTimer(), GetGameTimer()
    heldPhysicsReady = false
    heldDistance = math.max(HOLD_MIN, math.min(HOLD_MAX, distance or 8.0))
    NetworkRequestControlOfEntity(entity)
end

local function hold(ped, now)
    -- Players can enter a vehicle after it was grabbed; recheck on use.
    if not grabbable(held) then release(false); return end
    if NetworkHasControlOfEntity(held) then
        heldLastControl = now
    else
        NetworkRequestControlOfEntity(held)
        if now - heldLastControl > CONTROL_GRACE_MS then
            held = nil
            Admin.notify('error', now - heldSince > CONTROL_GRACE_MS and 'Lost hold: another player took control of it.'
                or 'Another player controls that, so it cannot be lifted.')
            return
        end
        return
    end
    if not heldPhysicsReady then
        if GetEntityType(held) == 3 then
            FreezeEntityPosition(held, false)
            ActivatePhysics(held)
        end
        heldPhysicsReady = true
    end
    for _, control in ipairs({ 14, 15, 16, 17 }) do DisableControlAction(0, control, true) end
    if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then heldDistance = math.min(HOLD_MAX, heldDistance + 1.5) end
    if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then heldDistance = math.max(HOLD_MIN, heldDistance - 1.5) end
    local goal = GetGameplayCamCoord() + cameraForward() * heldDistance
    local pull = (goal - GetEntityCoords(held)) * PULL
    local speed = #pull
    if speed > MAX_SPEED then pull = pull * (MAX_SPEED / speed) end
    if GetEntityType(held) == 1 and not IsPedRagdoll(held) then SetPedToRagdoll(held, 2000, 2000, 0, false, false, false) end
    SetEntityNoCollisionEntity(held, ped, false)
    SetEntityVelocity(held, pull.x, pull.y, pull.z)
end

local function loop()
    running = true
    while enabled do
        local ped, playerId = PlayerPedId(), PlayerId()
        local armed = (GetSelectedPedWeapon(ped) & 0xffffffff) ~= (UNARMED & 0xffffffff) and not IsPedInAnyVehicle(ped, false)
        local aiming = armed and IsPlayerFreeAiming(playerId) and not IsEntityDead(ped)
        if not aiming then
            if held then release(false) end
            setOutline(nil)
            Wait(armed and 50 or 250)
        else
            local now = GetGameTimer()
            if held then
                DisablePlayerFiring(playerId, true)
                hold(ped, now)
                setOutline(held)
                if held and IsDisabledControlJustPressed(0, 24) then release(true) end
            else
                local entity, distance = aimedEntity(ped)
                setOutline(entity)
                if entity then
                    DisablePlayerFiring(playerId, true)
                    if IsDisabledControlJustPressed(0, 24) then grab(entity, distance) end
                end
            end
            Wait(0)
        end
    end
    if held then release(false) end
    setOutline(nil)
    running = false
end

function Admin.setGravityGun(on)
    enabled = on == true
    if not enabled then
        if held then release(false) end
        setOutline(nil)
    end
    if enabled and not running then
        Admin.notify('info', 'Gravity gun on (beta). Draw a weapon, aim at a vehicle, prop or NPC and fire to lift it. Fire again to throw it, stop aiming to drop it, scroll to change the distance.')
        CreateThread(loop)
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    enabled = false
    if held then release(false) end
    setOutline(nil)
end)
