-- Freecam placement, then vehicle-relative playback. NUI never takes focus.
local Admin = EsAdmin
local session
-- Session keys are game controls read by the session loop, not FiveM key
-- mappings: they do nothing outside the camera, so they stay out of the key
-- settings. Indices from docs.fivem.net/docs/game-references/controls.
local KEYS = {
    { action = 'previous', control = 43, label = '[' },   -- INPUT_SNIPER_ZOOM_OUT_SECONDARY
    { action = 'next', control = 42, label = ']' },       -- INPUT_SNIPER_ZOOM_IN_SECONDARY
    { action = 'edit', control = 167, label = 'F6' },     -- INPUT_SELECT_CHARACTER_FRANKLIN
    -- INPUT_PUSH_TO_TALK: read but never disabled, so N still talks.
    { action = 'add', control = 249, label = 'N', shared = true },
    { action = 'hide', control = 168, label = 'F7' },     -- INPUT_SELECT_CHARACTER_TREVOR
    { action = 'save', control = 201, label = 'Enter' },  -- INPUT_FRONTEND_ACCEPT
    { action = 'back', control = 194, label = 'Backspace' }, -- INPUT_FRONTEND_RRIGHT: Backspace only, not Esc
}
local keys = {}
for _, key in ipairs(KEYS) do keys[key.action] = key end
local GLYPHS = { b_1003 = 'Enter', b_1004 = 'Backspace', b_2000 = 'Space', b_1002 = 'Tab' }
for index = 1, 24 do GLYPHS['b_' .. (169 + index)] = 'F' .. index end
local MAX_SHOTS, MAX_DISTANCE = 6, 30.0
local function copy(t) local out = {}; for k,v in pairs(t) do out[k]=v end; return out end
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function validShot(t)
    return type(t)=='table' and finite(t.x) and finite(t.y) and finite(t.z)
        and t.x*t.x+t.y*t.y+t.z*t.z <= MAX_DISTANCE*MAX_DISTANCE
        and finite(t.pitch) and math.abs(t.pitch)<=89 and finite(t.yaw) and math.abs(t.yaw)<=180
        and finite(t.fov) and t.fov>=15 and t.fov<=90
end
local function wrap(n) return (n+180)%360-180 end
local function foreignCamera()
    local cam=GetRenderingCam()
    return cam and cam~=-1 and cam~=0 and (not session or cam~=session.cam)
end
local function bindings()
    local out={}
    for name,key in pairs(keys) do
        -- The player's real binding for the control; the default only if the glyph is unknown.
        local label=GetControlInstructionalButton(0,key.control,true)
        out[name]=type(label)=='string' and (label:sub(1,2)=='t_' and label:sub(3,18) or GLYPHS[label]) or key.label
    end
    return out
end
local function publish()
    local items = {}
    if session and not session.hidden then
        local editing = session.draft ~= nil
        local index = editing and session.target or session.index
        local panel = {
            id = 'vehicle-camera', variant = 'target', marker = tostring(index),
            label = editing and ('PLACE CAMERA %02d'):format(index)
                or ('CAMERA %02d / %02d%s'):format(index, #session.shots, session.saved and ' SAVED' or ''),
        }
        local bound = bindings()
        local function hint(action, label, key)
            items[#items + 1] = { id = 'vehicle-camera:' .. action, label = label,
                key = key or bound[action], priority = 100 - #items, panel = panel }
        end
        if editing then
            hint('save', 'SAVE CAMERA')
            hint('back', 'CANCEL')
            hint('look', 'LOOK', 'MOUSE')
            hint('move', 'FLY', 'W A S D')
            hint('height', 'UP / DOWN', 'SPACE / Q')
            hint('speed', 'FAST / PRECISE', 'SHIFT / CTRL')
            hint('zoom', 'ZOOM', 'SCROLL')
        else
            if #session.shots > 1 then
                hint('previous', 'PREVIOUS CAMERA')
                hint('next', 'NEXT CAMERA')
            end
            if #session.shots < MAX_SHOTS then hint('add', 'ADD CAMERA') end
            hint('edit', 'REPOSITION')
            hint('hide', 'HIDE CONTROLS')
            hint('back', 'EXIT CAMERA')
        end
    end
    lib.setInteractions(items)
end
local function releasePlacement()
    if session and session.froze and DoesEntityExist(session.vehicle) then FreezeEntityPosition(session.vehicle,false) end
    if session then session.froze=false end
end
Admin.closeVehicleCamera=function()
    if not session then return end
    releasePlacement()
    if not foreignCamera() then RenderScriptCams(false,false,0,true,false) end
    if DoesCamExist(session.cam) then DestroyCam(session.cam,false) end
    session=nil; publish()
end
local function contextValid()
    return session and Admin.state.allowed['vehicle.camera']==true and not Admin.state.open
        and PlayerPedId()==session.ped and not IsEntityDead(session.ped)
        and DoesEntityExist(session.vehicle) and not IsEntityDead(session.vehicle)
        and GetVehiclePedIsIn(session.ped,false)==session.vehicle
        and DoesCamExist(session.cam) and not foreignCamera()
end
local function inputAllowed() return contextValid() and not IsPauseMenuActive() and not IsNuiFocused() end
local function drawCamera()
    local d=session.draft
    if d then
        SetCamCoord(session.cam,d.x,d.y,d.z)
        SetCamRot(session.cam,d.pitch,0.0,d.yaw,2)
        SetCamFov(session.cam,d.fov)
    else
        local shot=session.shots[session.index]
        local p=GetOffsetFromEntityInWorldCoords(session.vehicle,shot.x,shot.y,shot.z)
        SetCamCoord(session.cam,p.x,p.y,p.z)
        -- Follow heading; keep the horizon level through suspension roll.
        SetCamRot(session.cam,shot.pitch,0.0,shot.yaw+GetEntityHeading(session.vehicle),2)
        SetCamFov(session.cam,shot.fov)
    end
end
local function beginPlacement(target, fromGameplay)
    if GetEntitySpeed(session.vehicle)>0.5 then Admin.notify('info','Park the vehicle before placing a camera.'); return false end
    if GetPedInVehicleSeat(session.vehicle,-1)~=session.ped
        or (NetworkGetEntityIsNetworked(session.vehicle) and not NetworkHasControlOfEntity(session.vehicle)) then
        Admin.notify('error','Use the driver seat to place a camera.'); return false
    end
    local p=fromGameplay and GetGameplayCamCoord() or GetCamCoord(session.cam)
    local r=fromGameplay and GetGameplayCamRot(2) or GetCamRot(session.cam,2)
    local localPos=GetOffsetFromEntityGivenWorldCoords(session.vehicle,p.x,p.y,p.z)
    if localPos.x^2+localPos.y^2+localPos.z^2>MAX_DISTANCE^2 then
        Admin.notify('error','Move your view within 30 metres of the vehicle.'); return false
    end
    session.froze=not IsEntityPositionFrozen(session.vehicle)
    if session.froze then FreezeEntityPosition(session.vehicle,true) end
    session.target=target
    session.draft={x=p.x,y=p.y,z=p.z,pitch=math.max(-89,math.min(89,r.x)),yaw=wrap(r.z),
        fov=math.max(15,math.min(90,fromGameplay and GetGameplayCamFov() or GetCamFov(session.cam)))}
    session.hidden=false; session.saved=false
    drawCamera(); publish(); return true
end
local function cancelPlacement()
    if session.draft and #session.shots>0 then
        releasePlacement(); session.draft=nil; drawCamera(); publish()
    else Admin.closeVehicleCamera() end
end
local function fly()
    -- Same movement grammar as existing freecam; only placement owns these controls.
    for _,control in ipairs({1,2,14,15,16,17,21,22,24,25,30,31,32,33,34,35,36,44,59,60,63,64,71,72,75,76,85,86,99,100,200,322}) do
        DisableControlAction(0,control,true)
    end
    if IsDisabledControlJustPressed(0,200) or IsDisabledControlJustPressed(0,322) then cancelPlacement(); return end
    local d=session.draft
    d.yaw=wrap(d.yaw-GetDisabledControlNormal(0,1)*6)
    d.pitch=math.max(-89,math.min(89,d.pitch-GetDisabledControlNormal(0,2)*6))
    local speed=3.0*math.min(GetFrameTime(),0.05)
    if IsDisabledControlPressed(0,21) then speed=speed*4 end
    if IsDisabledControlPressed(0,36) then speed=speed*0.15 end
    local function axis(a,b) return (IsDisabledControlPressed(0,a) and 1 or 0)-(IsDisabledControlPressed(0,b) and 1 or 0) end
    local forward,right,up=axis(32,33),axis(35,34),axis(22,44)
    local pitch,yaw=math.rad(d.pitch),math.rad(d.yaw)
    local p={x=d.x+(-math.sin(yaw)*math.cos(pitch)*forward+math.cos(yaw)*right)*speed,
        y=d.y+(math.cos(yaw)*math.cos(pitch)*forward+math.sin(yaw)*right)*speed,
        z=d.z+(math.sin(pitch)*forward+up)*speed}
    local offset=GetOffsetFromEntityGivenWorldCoords(session.vehicle,p.x,p.y,p.z)
    if offset.x^2+offset.y^2+offset.z^2<=MAX_DISTANCE^2 then d.x,d.y,d.z=p.x,p.y,p.z end
    if IsDisabledControlJustPressed(0,15) then d.fov=math.max(15,d.fov-2) end
    if IsDisabledControlJustPressed(0,14) then d.fov=math.min(90,d.fov+2) end
end
local perform
local function pollKeys()
    for _,key in ipairs(KEYS) do
        if not key.shared then DisableControlAction(0,key.control,true) end
    end
    for _,key in ipairs(KEYS) do
        if IsDisabledControlJustPressed(0,key.control) then perform(key.action); return end
    end
end
Admin.openVehicleCamera=function()
    if Admin.state.allowed['vehicle.camera']~=true then return end
    if session then Admin.closeVehicleCamera(); return end
    if foreignCamera() then Admin.notify('error','Close the active camera or studio first.'); return end
    local ped=PlayerPedId()
    local vehicle=GetVehiclePedIsIn(ped,false)
    if vehicle==0 or IsEntityDead(ped) or IsEntityDead(vehicle) then Admin.notify('error','Get into a vehicle to place cameras.'); return end
    local shots={}
    -- Keep old orbit presets untouched; they are not manual placements.
    local kvp='vehicle-camera:v2:'..tostring(GetEntityModel(vehicle))
    local raw=GetResourceKvpString(kvp)
    if raw and #raw<8192 then
        local ok,saved=pcall(json.decode,raw)
        if ok and type(saved)=='table' then
            for i=1,MAX_SHOTS do if validShot(saved[i]) then shots[#shots+1]=copy(saved[i]) end end
        end
    end
    local cam=CreateCam('DEFAULT_SCRIPTED_CAMERA',false)
    if not cam or cam==0 or not DoesCamExist(cam) then Admin.notify('error','Could not create a camera.'); return end
    session={cam=cam,ped=ped,vehicle=vehicle,shots=shots,index=1,kvp=kvp}
    if #shots==0 and not beginPlacement(1,true) then DestroyCam(cam,false); session=nil; publish(); return end
    Admin.setOpen(false)
    drawCamera(); SetCamActive(cam,true); RenderScriptCams(true,false,0,true,false); publish()
    local owned=session
    CreateThread(function()
        while session==owned do
            if not contextValid() then Admin.closeVehicleCamera(); break end
            if session.draft then
                if NetworkGetEntityIsNetworked(session.vehicle) and not NetworkHasControlOfEntity(session.vehicle) then
                    Admin.closeVehicleCamera(); break
                end
                if inputAllowed() then fly() end
            end
            if session and inputAllowed() then pollKeys() end
            if not session then break end
            drawCamera()
            Wait(0)
        end
    end)
end
function perform(action)
    if not inputAllowed() then return end
    if not session.hidden and not lib.isInteractionActive('vehicle-camera:' .. action) then return end
    session.saved=false
    if action=='back' then
        cancelPlacement(); return
    elseif action=='hide' and not session.draft then session.hidden=not session.hidden
    elseif action=='edit' and not session.draft then beginPlacement(session.index,false)
    elseif action=='add' and not session.draft then
        if #session.shots<MAX_SHOTS then beginPlacement(#session.shots+1,false)
        else Admin.notify('info','All six cameras are placed. Reposition an existing camera.') end
    elseif action=='save' and session.draft then
        local d=session.draft
        local p=GetOffsetFromEntityGivenWorldCoords(session.vehicle,d.x,d.y,d.z)
        local shot={x=p.x,y=p.y,z=p.z,pitch=d.pitch,yaw=wrap(d.yaw-GetEntityHeading(session.vehicle)),fov=d.fov}
        if not validShot(shot) then Admin.notify('error','Place the camera within 30 metres of the vehicle.'); return end
        local updated={}; for i,s in ipairs(session.shots) do updated[i]=copy(s) end
        updated[session.target]=shot
        local encoded=json.encode(updated)
        local ok=pcall(SetResourceKvp,session.kvp,encoded)
        if not ok or GetResourceKvpString(session.kvp)~=encoded then Admin.notify('error','Could not save. Your placement is still open.'); return end
        releasePlacement()
        session.shots,session.index,session.draft,session.saved=updated,session.target,nil,true
        drawCamera()
    elseif (action=='previous' or action=='next') and not session.draft then
        session.index=((session.index-1+(action=='next' and 1 or -1))%#session.shots)+1; drawCamera()
    end
    publish()
end
-- Commands stay for console `bind` users; the session loop handles the keys.
for _, key in ipairs(KEYS) do
    local action=key.action
    RegisterCommand('cortex_camera_'..action,function() perform(action) end,false)
end
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() then Admin.closeVehicleCamera() end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'cortex-lib' and session then publish() end
end)
