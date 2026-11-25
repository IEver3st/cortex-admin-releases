local Admin, P = EsAdmin, EsAdminVmenuPolicy
local statsApplied, statsBefore = false, {}
local statNames = { 'MP0_SHOOTING_ABILITY', 'MP0_STRENGTH', 'MP0_STEALTH_ABILITY', 'MP0_FLYING_ABILITY', 'MP0_WHEELIE_ABILITY', 'MP0_LUNG_CAPACITY' }
-- vMenu's keys. FiveM saves a player's key choice under the resource that
-- registered it, so vMenu's commands are registered by the stand-in resource
-- named vMenu (compat/vMenu) and land here.
local vmenuKeys = {
    MenuToggle = function() Admin.toggleMenu() end,
    NoClip = function()
        if Admin.state.allowed['player.noclip'] and Admin.claimNoclipPress() then Admin.toggleAction('player.noclip', not Admin.state.toggles['player.noclip']) end
    end,
    DV = function()
        if Admin.state.allowed['vehicle.delete'] then Admin.executeAction('vehicle.delete') end
    end,
}
exports('vmenuKey', function(name)
    if GetInvokingResource() ~= 'vMenu' or not Admin.hasMenuAccess() then return false end
    local handler = vmenuKeys[name]
    if handler then handler() end
    return handler ~= nil
end)
function Admin.applyVmenuRuntimePolicy()
    if not Admin.state.vmenuPolicy then return end
    local pvp = P.get('vmenu_pvp_mode', 0)
    if pvp == 1 or pvp == 2 then
        NetworkSetFriendlyFireOption(pvp == 1)
        SetCanAttackFriendly(PlayerPedId(), pvp == 1, false)
    end
    if Admin.applyVmenuVoicePolicy then Admin.applyVmenuVoicePolicy() end
    if not statsApplied and not P.get('vmenu_disable_player_stats_setup', false) and Admin.hasMenuAccess() then
        statsApplied = true
        for _, name in ipairs(statNames) do
            local hash = joaat(name)
            local ok, value = StatGetInt(hash, -1)
            if ok then statsBefore[hash] = value end
            StatSetInt(hash, 100, true)
        end
        local stamina = joaat('MP0_STAMINA')
        local ok, value = StatGetInt(stamina, -1)
        if ok then statsBefore[stamina] = value end
        StatSetInt(stamina, Admin.state.toggles['player.infiniteStamina'] and 100 or 0, true)
        local mental = joaat('MP0_PLAYER_MENTAL_STATE')
        local success, previous = StatGetFloat(mental, -1)
        if success then statsBefore.mental = previous end
        StatSetFloat(mental, 0.0, true)
    end
end
AddEventHandler('playerSpawned', function() Admin.applyVmenuRuntimePolicy() end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for hash, value in pairs(statsBefore) do
        if hash == 'mental' then StatSetFloat(joaat('MP0_PLAYER_MENTAL_STATE'), value, true)
        else StatSetInt(hash, value, true) end
    end
end)

local function gameInput()
    return Admin.hasMenuAccess() and not Admin.state.open and not Admin.isVmenuModeOpen()
        and not (Admin.isPlayersOpen and Admin.isPlayersOpen()) and not IsNuiFocused()
        and not IsPauseMenuActive() and IsScreenFadedIn() and not IsPlayerSwitchInProgress() and not IsEntityDead(PlayerPedId())
end
local pickingSnow = false
local visorBusy = false
local bikeAnimations = {
    chopper = { 'sanctus', 'zombiea', 'zombieb' },
    dirt = { 'bf400', 'enduro', 'manchez', 'sanchez', 'sanchez2', 'esskey' },
    scooter = { 'faggio', 'faggio2', 'faggio3', 'cliffhanger', 'bagger' },
    policeb = { 'avarus', 'chimera', 'policeb', 'sovereign', 'hexer', 'innovation', 'nightblade', 'ratbike', 'wolfsbane' },
}
local function switchVisor()
    if visorBusy or not gameInput() then return end
    local ped = PlayerPedId()
    local prop, texture = GetPedPropIndex(ped, 0), GetPedPropTextureIndex(ped, 0)
    if prop < 0 then return end
    local hash = GetHashNameForProp(ped, 0, prop, texture)
    if GetShopPedApparelVariantPropCount(hash) <= 0 then return end
    local alternate = GetVariantProp(hash, 0)
    -- CitizenFX MpPedDataStructs.UnsafeAltPropVariationData is 48 bytes.
    local buffer = string.rep('\0', 48)
    Citizen.InvokeNative(0x5D5CAFF661DDF6FC, alternate, buffer)
    local nextProp, nextTexture = string.unpack('<i4', buffer, 25), string.unpack('<i4', buffer, 33)
    if nextProp < 0 or nextProp >= GetNumberOfPedPropDrawableVariations(ped, 0)
        or nextTexture < 0 or nextTexture >= GetNumberOfPedPropTextureVariations(ped, 0, nextProp) then return end
    local female = GetEntityModel(ped) == joaat('mp_f_freemode_01')
    local upward = prop < nextProp
    if prop == (female and 66 or 67) or prop == (female and 81 or 82) then upward = not upward end
    local goggles = prop >= (female and 115 or 116) and prop <= (female and 118 or 119)
    local animation = (goggles and 'goggles_' or 'visor_') .. (upward and 'up' or 'down')
    local dictionary = 'anim@mp_helmets@on_foot'
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        if goggles then Admin.notify('error', 'Leave the vehicle before toggling goggles.'); return end
        local model, style = GetEntityModel(vehicle), nil
        if IsThisModelAQuadbike(model) then style = 'quad'
        elseif IsThisModelABicycle(model) then style = 'scooter'
        elseif IsThisModelABike(model) then
            style = 'sports'
            for name, models in pairs(bikeAnimations) do
                for _, entry in ipairs(models) do if model == joaat(entry) then style = name end end
            end
        end
        if style then dictionary = 'anim@mp_helmets@on_bike@' .. style end
    end
    if GetFollowPedCamViewMode() == 4 and dictionary == 'anim@mp_helmets@on_foot' then
        animation = 'pov_' .. animation:gsub('goggles', 'visor')
    end
    visorBusy = true
    CreateThread(function()
        RequestAnimDict(dictionary)
        local deadline = GetGameTimer() + 3000
        while not HasAnimDictLoaded(dictionary) and gameInput() and GetGameTimer() < deadline do Wait(0) end
        if HasAnimDictLoaded(dictionary) and gameInput() and PlayerPedId() == ped then
            TaskPlayAnim(ped, dictionary, animation, 8.0, 1.0, -1, 48, 0.0, false, false, false)
            deadline = GetGameTimer() + 4000
            while GetGameTimer() < deadline and gameInput() and PlayerPedId() == ped do
                if vehicle ~= 0 then DisableControlAction(0, 74, true) end
                if GetEntityAnimCurrentTime(ped, dictionary, animation) > 0.39 then
                    SetPedPropIndex(ped, 0, nextProp, nextTexture, true)
                    break
                end
                Wait(0)
            end
        end
        RemoveAnimDict(dictionary)
        visorBusy = false
    end)
end
local function snowball()
    if pickingSnow or not gameInput() then return end
    local ped = PlayerPedId()
    if not IsPedOnFoot(ped) or IsPedFalling(ped) or IsPedSwimming(ped) or IsPedRagdoll(ped)
        or GetEntitySpeed(ped) > 0.1 or GetInteriorFromEntity(ped) ~= 0 then return end
    pickingSnow = true
    CreateThread(function()
        local hash, dictionary, animation = joaat('weapon_snowball'), 'anim@mp_snowball', 'pickup_snowball'
        local function collect()
            local authorization = Admin.authorizeVmenuModels('weapon', { 'weapon_snowball' }, 'weapons.give')
            if not authorization or not authorization.ok or not authorization.allowed[1] or not gameInput() then return end
            local maxOk, maximum = GetMaxAmmo(ped, hash)
            maximum = maxOk and maximum or 10
            if GetAmmoInPedWeapon(ped, hash) >= maximum then return end
            RequestAnimDict(dictionary)
            local deadline = GetGameTimer() + 3000
            while not HasAnimDictLoaded(dictionary) and GetGameTimer() < deadline do Wait(0) end
            if not HasAnimDictLoaded(dictionary) or not gameInput() or ped ~= PlayerPedId() then return end
            TaskPlayAnim(ped, dictionary, animation, 8.0, 1.0, -1, 0, 0.0, false, false, false)
            deadline = GetGameTimer() + math.min(5000, math.max(500, GetAnimDuration(dictionary, animation) * 1000))
            while GetGameTimer() < deadline and gameInput() and ped == PlayerPedId() do
                if HasAnimEventFired(ped, joaat('CreateObject')) then
                    GiveWeaponToPed(ped, hash, 0, true, true)
                    SetPedAmmo(ped, hash, math.min(maximum, GetAmmoInPedWeapon(ped, hash) + 2))
                    break
                end
                if HasAnimEventFired(ped, joaat('Interrupt')) then break end
                Wait(0)
            end
            RemoveAnimDict(dictionary)
        end
        local ok, reason = pcall(collect)
        pickingSnow = false
        if not ok then print('[cortex-admin] Snowball pickup failed: ' .. tostring(reason)) end
    end)
end

CreateThread(function()
    local heldAt, visorHeldAt, visorUsed
    local visorPed, visorProp, visorTexture, visorEligible
    while true do
        local recording = Admin.state.settings.recordingControls == true and Admin.state.allowed['options.recordingControls'] == true
        local snow = Admin.worldState.snowEffects == true and Admin.state.allowed['weapons.give'] == true
        local waypointKey = P.get('vmenu_teleport_to_wp_keybind_key', 168)
        local waypoint = waypointKey ~= 168 and Admin.state.toggles['options.teleportWaypointKey'] and Admin.state.allowed['teleport.waypoint']
        -- Only switchable helmets need the per-frame hold check, not every hat.
        local ped = PlayerPedId()
        local prop, texture = GetPedPropIndex(ped, 0), GetPedPropTextureIndex(ped, 0)
        if ped ~= visorPed or prop ~= visorProp or texture ~= visorTexture then
            visorPed, visorProp, visorTexture = ped, prop, texture
            visorEligible = prop >= 0 and GetShopPedApparelVariantPropCount(GetHashNameForProp(ped, 0, prop, texture)) > 0
        end
        local visor = visorEligible
        if (recording or snow or waypoint or visor) and gameInput() then
            if visor and IsControlPressed(0, 357) then
                visorHeldAt = visorHeldAt or GetGameTimer()
                if GetGameTimer() - visorHeldAt > 380 then DisableControlAction(0, 74, true) end
                if not visorUsed and GetGameTimer() - visorHeldAt > 400 then visorUsed = true; switchVisor() end
            else visorHeldAt, visorUsed = nil, false end
            if waypoint and IsControlJustReleased(0, waypointKey) then Admin.executeAction('teleport.waypoint', {}) end
            if snow and IsControlJustReleased(0, 47) then snowball() end
            if recording then
                local keyboard = IsUsingKeyboard(0)
                if not keyboard and IsControlPressed(0, 20) then heldAt = heldAt or GetGameTimer() else heldAt = nil end
                local ready = keyboard or heldAt and GetGameTimer() - heldAt >= 400
                if ready then
                    if not keyboard then DisableControlAction(0, 80, true) end
                    if IsControlJustReleased(0, 288) then
                        if IsRecording() then StopRecordingAndSaveClip() else StartRecording(1) end
                    elseif IsRecording() and (keyboard and IsControlJustPressed(0, 297) or not keyboard and IsControlJustReleased(0, 170)) then
                        StopRecordingAndDiscardClip()
                    end
                end
            end
            -- Key edges need every frame. A worn visor helmet alone only needs the hold
            -- noticed, so it polls at 100 ms until the button is down.
            Wait((recording or snow or waypoint or visorHeldAt) and 0 or 100)
        else heldAt, visorHeldAt, visorUsed = nil, nil, false; Wait(500) end
    end
end)
