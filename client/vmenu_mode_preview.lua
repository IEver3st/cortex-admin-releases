local Admin, VM = EsAdmin, EsAdmin.VmenuMode
local preview, previewKey, previewGeneration = nil, nil, 0
local camera, cameraPed, wasFrozen, heading = nil, nil, false, nil
local cameraAngle, cameraZoom, selectedMenu = 0.0, 2.6, nil
local PREVIEW_DISTANCE = 2.2
local function clearPreview()
    previewGeneration = previewGeneration + 1
    if preview and DoesEntityExist(preview) then DeleteEntity(preview) end
    preview, previewKey = nil, nil
end
-- Character edits swap the player's model, which replaces the ped the camera
-- froze. Thawing only that ped left the new one frozen until noclip cleared it,
-- so the camera follows the swap and release always acts on the current ped.
local function thaw(ped)
    if not ped or not DoesEntityExist(ped) or wasFrozen then return end
    if Admin.isPlayerFreezeHeld and Admin.isPlayerFreezeHeld() then return end
    FreezeEntityPosition(ped, false)
end
function Admin.closeVmenuCharacterCamera()
    if camera then
        if GetRenderingCam() == camera then RenderScriptCams(false, false, 0, true, true) end
        DestroyCam(camera, false)
        camera = nil
    end
    if cameraPed and DoesEntityExist(cameraPed) then
        thaw(cameraPed)
        if heading then SetEntityHeading(cameraPed, heading) end
        ClearPedLookAt(cameraPed)
    end
    local current = PlayerPedId()
    if cameraPed and current ~= cameraPed then thaw(current) end
    cameraPed, heading = nil, nil
end
function Admin.openVmenuCharacterCamera()
    clearPreview()
    if camera then return end
    local rendering = GetRenderingCam()
    if rendering and rendering ~= -1 and rendering ~= 0 then return end
    cameraPed = PlayerPedId()
    if IsPedInAnyVehicle(cameraPed, false) then cameraPed = nil; return end
    wasFrozen, heading = IsEntityPositionFrozen(cameraPed), GetEntityHeading(cameraPed)
    FreezeEntityPosition(cameraPed, true)
    camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
    cameraAngle, cameraZoom = 0.0, 2.6
    SetCamFov(camera, 40.0)
    SetCamActive(camera, true)
    RenderScriptCams(true, false, 0, true, true)
    CreateThread(function()
        Wait(0)
        while camera do
            local rendering, current = GetRenderingCam(), PlayerPedId()
            if not Admin.isVmenuModeOpen() or not Admin.state.allowed['player.setAppearance'] or IsEntityDead(current)
                or IsPedInAnyVehicle(current, false) or (rendering and rendering ~= -1 and rendering ~= 0 and rendering ~= camera) then
                Admin.closeVmenuCharacterCamera(); break
            end
            if current ~= cameraPed then
                -- New model: keep the original freeze state, frame the new ped.
                thaw(cameraPed)
                cameraPed = current
                FreezeEntityPosition(cameraPed, true)
            end
            for _, control in ipairs({ 152, 153, 179, 32, 33, 34, 35 }) do DisableControlAction(0, control, true) end
            local dt = math.min(GetFrameTime(), 0.05)
            if IsDisabledControlPressed(0, 152) then cameraAngle = cameraAngle - dt * 65 end
            if IsDisabledControlPressed(0, 153) then cameraAngle = cameraAngle + dt * 65 end
            if IsDisabledControlJustReleased(0, 179) then SetEntityHeading(cameraPed, GetEntityHeading(cameraPed) + 180) end
            if IsDisabledControlPressed(0, 32) then cameraZoom = math.max(0.65, cameraZoom - dt * 1.5) end
            if IsDisabledControlPressed(0, 33) then cameraZoom = math.min(4.5, cameraZoom + dt * 1.5) end
            local point = GetEntityCoords(cameraPed)
            local face = selectedMenu == 'mp_ped_inheritance' or selectedMenu == 'mp_ped_appearance' or selectedMenu == 'mp_ped_face'
            local height = face and 0.7 or 0.15
            local radius = face and math.min(cameraZoom, 1.1) or cameraZoom
            local angle = math.rad(heading + cameraAngle)
            SetCamCoord(camera, point.x - math.sin(angle) * radius, point.y + math.cos(angle) * radius, point.z + height)
            PointCamAtCoord(camera, point.x, point.y, point.z + height)
            if IsDisabledControlPressed(0, 34) or IsDisabledControlPressed(0, 35) then
                local side = IsDisabledControlPressed(0, 34) and -1 or 1
                TaskLookAtCoord(cameraPed, point.x + side, point.y + 1.0, point.z + 0.7, 250, 0, 2)
            end
            Wait(0)
        end
    end)
end

function Admin.onVmenuSelection(menu, args, item)
    selectedMenu = menu
    local entry = menu == 'saved_library_category' and args.kind == 'peds' and item and item.args and item.args.entry
    local model = (menu == 'player_appearance_peds' or menu == 'player_appearance_addon_peds') and item and item.key
    local enabled = Admin.vmenuSetting('vmenu_mp_ped_preview', true) and Admin.state.settings.mpPedPreviews ~= false
    local key = enabled and not camera and ((entry and ('saved:' .. tostring(entry.id))) or model) or nil
    if key == previewKey then return end
    clearPreview()
    if not key then return end
    previewKey = key
    local revision = previewGeneration
    CreateThread(function()
        Wait(150)
        if revision ~= previewGeneration then return end
        local data = entry and Admin.savedLibraryAdapter.loadPed(entry)
        local hash = data and data.ModelHash or model and joaat(model)
        if not hash then return end
        local action = entry and 'player.loadMpPed' or 'player.setModel'
        local authorization = Admin.authorizeVmenuModels('ped', { hash }, action, true)
        if revision ~= previewGeneration or not authorization or not authorization.ok or not authorization.allowed[1] then return end
        if not IsModelAPed(hash) then return end
        RequestModel(hash)
        local deadline = GetGameTimer() + 5000
        while not HasModelLoaded(hash) and revision == previewGeneration and GetGameTimer() < deadline do Wait(0) end
        if revision ~= previewGeneration or not HasModelLoaded(hash) then SetModelAsNoLongerNeeded(hash); return end
        local point = GetEntityCoords(PlayerPedId())
        local clone = CreatePed(26, hash, point.x, point.y, point.z - 3.0, 0.0, false, false)
        SetModelAsNoLongerNeeded(hash)
        if clone == 0 then return end
        preview = clone
        SetEntityCollision(clone, false, false)
        SetEntityInvincible(clone, true)
        SetBlockingOfNonTemporaryEvents(clone, true)
        FreezeEntityPosition(clone, true)
        SetPedAoBlobRendering(clone, false)
        if data then Admin.applySavedPedPreview(clone, data) end
        -- The local-only clone stands upright a fixed distance in front of the
        -- player, facing them, whatever the camera does. On a slope it follows
        -- the ground difference between the player's feet and its own.
        while revision == previewGeneration and DoesEntityExist(clone) and Admin.isVmenuModeOpen() and Admin.state.allowed[action] do
            local player = PlayerPedId()
            local home = GetEntityCoords(player)
            local spot = GetOffsetFromEntityInWorldCoords(player, 0.0, PREVIEW_DISTANCE, 0.0)
            local foundHere, groundHere = GetGroundZFor_3dCoord(home.x, home.y, home.z + 1.0, false)
            local foundThere, groundThere = GetGroundZFor_3dCoord(spot.x, spot.y, home.z + 1.0, false)
            local z = (foundHere and foundThere and math.abs(groundThere - groundHere) < 2.0) and home.z + groundThere - groundHere or home.z
            SetEntityCoordsNoOffset(clone, spot.x, spot.y, z, false, false, false)
            SetEntityRotation(clone, 0.0, 0.0, GetEntityHeading(player) + 180.0, 2, true)
            Wait(0)
        end
        if DoesEntityExist(clone) then DeleteEntity(clone) end
        if preview == clone then preview = nil end
    end)
end
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearPreview(); Admin.closeVmenuCharacterCamera()
    Admin.finishVmenuCharacterEdit(false)
end)
