-- Standalone photo mode uses cortex-lib for camera shortcuts.
local Admin = EsAdmin
local cfg = (Config and Config.ShowcaseCamera) or {}

local ACTION = 'dev.photoMode'
local MAX_SPEED, MIN_SPEED, SPEED_STEP, SHIFT_MULTIPLIER = 20.0, 0.5, 0.5, 2.0
local PRECISION = 1.0 -- degrees of roll per frame; mouse look uses 8x
local HUD_REASON = 'cortex-admin:showcase'
local FRAME = 1.0 / 60.0 -- vMenu steps once per frame; scaled so it feels the same at any fps

-- vMenu's filter list, in its order, with readable names.
local FILTERS = { { 'None', 'None' },
    { 'CAMERA_BW', 'Black & white' }, { 'CAMERA_secuirity', 'Security cam' }, { 'CAMERA_secuirity_FUZZ', 'Security cam (fuzz)' } }
for i = 1, 25 do FILTERS[#FILTERS + 1] = { ('NG_filmic%02d'):format(i), ('Film %02d'):format(i) } end
FILTERS[#FILTERS + 1] = { 'NG_filmnoir_BW01', 'Film noir 1' }
FILTERS[#FILTERS + 1] = { 'NG_filmnoir_BW02', 'Film noir 2' }
FILTERS[#FILTERS + 1] = { 'phone_cam', 'Snapmatic' }
for i = 1, 12 do FILTERS[#FILTERS + 1] = { 'phone_cam' .. i, ('Snapmatic %02d'):format(i) } end
if type(cfg.filters) == 'table' then
    for i = 1, math.min(#cfg.filters, 32) do
        local f = cfg.filters[i]
        if type(f) == 'table' and type(f.name) == 'string' and f.name ~= '' and #f.name <= 64 then
            FILTERS[#FILTERS + 1] = { f.name, type(f.label) == 'string' and f.label:sub(1, 28) or f.name:sub(1, 28) }
        end
    end
end

local session
-- Speed and filter for the current session; every entry starts fresh.
local memory = { speed = 2.0, filter = 1 }
local toggleLabel = 'U'

local function sin(deg) return math.sin(math.rad(deg)) end
local function cos(deg) return math.cos(math.rad(deg)) end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function pressed(control) return IsDisabledControlPressed(0, control) end
local function justPressed(control) return IsDisabledControlJustPressed(0, control) end

local function foreignCamera()
    local cam = GetRenderingCam()
    return cam and cam ~= -1 and cam ~= 0 and (not session or cam ~= session.cam)
end

local GLYPHS = { b_1003 = 'Enter', b_1004 = 'Backspace', b_2000 = 'Space', b_1002 = 'Tab' }
for index = 1, 24 do GLYPHS['b_' .. (169 + index)] = 'F' .. index end

local function readToggleLabel()
    local ok, label = pcall(GetControlInstructionalButton, 0, joaat('cortex_showcase_toggle') | 0x80000000, true)
    if ok and type(label) == 'string' then
        if label:sub(1, 2) == 't_' and #label > 2 then return label:sub(3):sub(1, 12) end
        if GLYPHS[label] then return GLYPHS[label] end
    end
    return tostring(cfg.toggleKey or 'U')
end

-- Timecycle filter -----------------------------------------------------------

local function filterAvailable(index)
    local name = FILTERS[index][1]
    return name == 'None' or (GetTimecycleModifierIndexByName(name) or -1) ~= -1
end

local function applyFilter()
    local name = FILTERS[memory.filter][1]
    if name == 'None' then
        ClearTimecycleModifier()
    else
        SetTimecycleModifier(name)
        SetTimecycleModifierStrength(1.0)
    end
end

local function stepFilter(delta)
    -- Wraps like vMenu; skips names this client doesn't have.
    for _ = 1, #FILTERS do
        memory.filter = (memory.filter - 1 + delta) % #FILTERS + 1
        if filterAvailable(memory.filter) then break end
    end
    applyFilter()
end

-- Controls strip ---------------------------------------------------------------

local function helpItems()
    if not session.hud or session.photo or IsPauseMenuActive() or IsNuiFocused() then return nil end
    local speed = memory.speed * (pressed(21) and SHIFT_MULTIPLIER or 1.0)
    -- Movement (WASD, Space/Ctrl, mouse look) is left off: everyone knows it.
    -- Filter and speed lead the bottom-right camera controls.
    return {
        { label = ('Filter: %s'):format(FILTERS[memory.filter][2]), value = '← →' },
        { label = ('Speed: %.1f'):format(speed), value = 'Scroll' },
        { label = 'Roll', value = 'E Q' },
        { label = 'Zoom', value = '↑ ↓' },
        { label = 'Reset filter', value = 'R' },
        session.attached and { label = 'Detach', value = 'RMB' } or { label = 'Attach', value = 'LMB' },
        { label = 'Photo', value = 'Enter' },

        { label = 'Exit', value = toggleLabel },
    }
end

local function setHelp(items)
    if items then
        exports['cortex-lib']:showHelp(items, { compact = true })
    else
        exports['cortex-lib']:hideHelp()
    end
end

local function syncHelp()
    local items = helpItems()
    local parts = {}
    for _, item in ipairs(items or {}) do parts[#parts + 1] = item.label .. '=' .. item.value end
    local sig = items and table.concat(parts, '|') or ''
    if sig == session.helpSig then return end
    session.helpSig = sig
    setHelp(items)
end

local function setOtherHud(hidden)
    if GetResourceState('cortex-hud') ~= 'started' then return end
    pcall(function()
        if hidden then exports['cortex-hud']:hideHud(HUD_REASON) else exports['cortex-hud']:showHud(HUD_REASON) end
    end)
end

-- Attach ------------------------------------------------------------------------

-- vMenu: a 100 m ray along the view (yaw + pitch) that hits vehicles and peds.
local function entityInFront()
    local p, rx, rz = session.pos, session.rotX, session.rotZ
    local handle = StartExpensiveSynchronousShapeTestLosProbe(p.x, p.y, p.z,
        p.x - sin(rz) * 100.0, p.y + cos(rz) * 100.0, p.z + sin(rx) * 100.0, 10, session.ped, 0)
    local _, hit, _, _, entity = GetShapeTestResult(handle)
    if (hit == true or hit == 1) and entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
end

local function detach()
    if not session.attached then return end
    session.attached, session.offset = nil, nil
    DetachCam(session.cam)
end

-- Session -------------------------------------------------------------------

Admin.isShowcaseCameraActive = function() return session ~= nil end

Admin.closeShowcaseCamera = function()
    if not session then return end
    local closing = session
    session = nil
    if closing.attached then DetachCam(closing.cam) end
    -- vMenu clears the filter on exit; put back whatever another script had.
    local prior = closing.priorFilter
    local name = prior and prior ~= -1 and GetTimecycleModifierNameByIndex(prior) or nil
    if type(name) == 'string' and name ~= '' then
        SetTimecycleModifier(name)
        SetTimecycleModifierStrength(closing.priorStrength or 1.0)
    else
        ClearTimecycleModifier()
    end
    -- Hand rendering back only if our camera still owns it.
    local rendering = GetRenderingCam()
    if rendering == closing.cam or rendering == -1 or rendering == 0 then RenderScriptCams(false, false, 0, true, false) end
    if DoesCamExist(closing.cam) then
        SetCamActive(closing.cam, false)
        DestroyCam(closing.cam, false)
    end
    ClearFocus()
    DisplayRadar(true)
    setOtherHud(false)
    setHelp(nil)
end

local function contextValid()
    if not session then return false end
    local ped = PlayerPedId()
    return Admin.state.allowed[ACTION] == true and not Admin.state.open
        and ped == session.ped and DoesEntityExist(ped) and not IsEntityDead(ped)
        and DoesCamExist(session.cam) and not foreignCamera()
end

local function takePhoto()
    -- Same natives as vMenu's Take Photo: saved to the pause-menu gallery.
    BeginTakeHighQualityPhoto()
    SaveHighQualityPhoto(-1)
    FreeMemoryForHighQualityPhoto()
    Admin.notify('success', 'Photo saved to the gallery.')
end

local function frame(dt)
    local k = dt / FRAME -- 1.0 at 60 fps: exactly vMenu's per-frame steps
    DisableFirstPersonCamThisFrame()
    BlockWeaponWheelThisFrame()
    DisableAllControlActions(0)
    EnableControlAction(0, 245, true) -- chat stays usable, as in vMenu
    HideHudAndRadarThisFrame()

    local p = session.pos
    -- Attached: start from where the entity carried the camera this frame.
    if session.attached then
        if DoesEntityExist(session.attached) then
            local o = session.offset
            local w = GetOffsetFromEntityInWorldCoords(session.attached, o.x, o.y, o.z)
            p.x, p.y, p.z = w.x, w.y, w.z
        else
            detach()
        end
    end

    local input = not IsPauseMenuActive() and not IsNuiFocused()
    if input then
        -- Speed: scroll steps 0.5 (0.5-20); Shift doubles while held.
        if justPressed(14) then memory.speed = math.max(MIN_SPEED, memory.speed - SPEED_STEP) end
        if justPressed(15) then memory.speed = math.min(MAX_SPEED, memory.speed + SPEED_STEP) end
        local step = 0.1 * memory.speed * (pressed(21) and SHIFT_MULTIPLIER or 1.0) * k
        local rx, rz = session.rotX, session.rotZ

        if pressed(32) then p.x, p.y, p.z = p.x - step * sin(rz), p.y + step * cos(rz), p.z + step * sin(rx) end
        if pressed(33) then p.x, p.y, p.z = p.x + step * sin(rz), p.y - step * cos(rz), p.z - step * sin(rx) end
        if pressed(34) then p.x, p.y = p.x - step * sin(rz + 90.0), p.y + step * cos(rz + 90.0) end
        if pressed(35) then p.x, p.y = p.x + step * sin(rz + 90.0), p.y - step * cos(rz + 90.0) end
        if pressed(22) then p.z = p.z + step end
        if pressed(36) then p.z = p.z - step end
        local sensitivity = PRECISION * 8.0
        session.rotX = clamp(session.rotX - GetDisabledControlNormal(0, 2) * sensitivity, -90.0, 90.0)
        session.rotZ = session.rotZ - GetDisabledControlNormal(0, 1) * sensitivity
        if pressed(44) then session.rotY = session.rotY - PRECISION * k end
        if pressed(38) then session.rotY = session.rotY + PRECISION * k end
        session.rotY = clamp(session.rotY, -90.0, 90.0)

        if pressed(188) then session.fov = clamp(session.fov - k, 1.0, 130.0) end
        if pressed(187) then session.fov = clamp(session.fov + k, 1.0, 130.0) end

        if session.attached and justPressed(238) then
            detach()
        elseif not session.attached and justPressed(237) then
            local entity = entityInFront()
            if entity then session.attached = entity end
        end

        if justPressed(189) then stepFilter(-1)
        elseif justPressed(190) then stepFilter(1)
        elseif justPressed(45) then memory.filter = 1; applyFilter() end

        if justPressed(236) then session.hud = not session.hud end
        if justPressed(201) and not session.photo then session.photo = 2 end
    end

    if session.attached then
        -- Position follows the entity; rotation stays world-fixed, as in vMenu.
        local o = GetOffsetFromEntityGivenWorldCoords(session.attached, p.x, p.y, p.z)
        session.offset = { x = o.x, y = o.y, z = o.z }
        AttachCamToEntity(session.cam, session.attached, o.x, o.y, o.z, true)
    else
        SetCamCoord(session.cam, p.x + 0.0, p.y + 0.0, p.z + 0.0)
    end
    SetCamRot(session.cam, session.rotX + 0.0, session.rotY + 0.0, session.rotZ + 0.0, 2)
    -- The non-OAL native invoker distinguishes integer bits from float bits.
    SetCamFov(session.cam, session.fov + 0.0)
    SetFocusPosAndVel(p.x + 0.0, p.y + 0.0, p.z + 0.0, 0.0, 0.0, 0.0)

    -- Hide camera shortcuts for two frames before the photo is taken.
    if session.photo then
        session.photo = session.photo - 1
        if session.photo < 0 then
            session.photo = nil
            takePhoto()
        end
    end
    syncHelp()
end

Admin.openShowcaseCamera = function()
    if Admin.state.allowed[ACTION] ~= true then return false end
    if session then Admin.closeShowcaseCamera(); return true end
    if foreignCamera() then Admin.notify('error', 'Close the active camera or studio first.'); return false end
    if Admin.state.toggles and Admin.state.toggles['player.noclip'] then
        Admin.notify('error', 'Disable noclip before photo mode.')
        return false
    end
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then return false end
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
    if not cam or cam == 0 or not DoesCamExist(cam) then Admin.notify('error', 'Could not create a camera.'); return false end
    Admin.setOpen(false)

    -- vMenu starts at the player's position and heading with a 50 FOV.
    local c = GetEntityCoords(ped)
    session = {
        cam = cam, ped = ped, pos = { x = c.x, y = c.y, z = c.z },
        rotX = 0.0, rotY = 0.0, rotZ = GetEntityHeading(ped), fov = 50.0, hud = true,
        priorFilter = GetTimecycleModifierIndex(), priorStrength = GetTimecycleModifierStrength(),
    }
    toggleLabel = readToggleLabel()
    memory.speed, memory.filter = 2.0, 1 -- re-entering always starts at defaults
    applyFilter()
    DisplayRadar(false)
    setOtherHud(true)
    SetCamCoord(cam, c.x, c.y, c.z)
    SetCamRot(cam, 0.0, 0.0, session.rotZ, 2)
    SetCamFov(cam, 50.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
    syncHelp()

    local owned = session
    CreateThread(function()
        while session == owned do
            if not contextValid() then Admin.closeShowcaseCamera(); break end
            frame(math.min(GetFrameTime(), 0.1))
            Wait(0)
        end
    end)
    return true
end

-- Toggle: U by default (vMenu's freecam key), rebindable in FiveM key settings.
local function toggle()
    if session then Admin.closeShowcaseCamera(); return end
    if Admin.state.allowed[ACTION] == nil then
        TriggerServerEvent('cortex-admin:server:requestPermissions')
        local deadline = GetGameTimer() + 2000
        while Admin.state.allowed[ACTION] == nil and GetGameTimer() < deadline do Wait(50) end
    end
    if Admin.state.allowed[ACTION] ~= true then
        Admin.notify('error', 'Photo mode is not available with your permissions.')
        return
    end
    if IsPauseMenuActive() or IsNuiFocused() then return end
    Admin.openShowcaseCamera()
end

RegisterCommand('cortex_showcase_toggle', function() CreateThread(toggle) end, false)
Admin.addKeyMapping('cortex_showcase_toggle', 'Cortex Admin: toggle photo mode', tostring(cfg.toggleKey or 'U'), function()
    return Admin.state.allowed[ACTION] == true
end)
RegisterCommand('showcase', function() CreateThread(toggle) end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Admin.closeShowcaseCamera() end
end)
