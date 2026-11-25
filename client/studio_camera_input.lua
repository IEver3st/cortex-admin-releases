-- NUI owns hit testing/capture; the client samples a held drag at game-frame
-- cadence. No pointer-move RPCs, acknowledgement clock, easing or velocity tail.
local Admin = EsAdmin
local function finite(n) return type(n) == 'number' and n == n and math.abs(n) < math.huge end

Admin.createStudioMouseInput = function(isCurrent, apply)
    local drag, session, lastGesture = nil, nil, 0
    local input = {}
    local function held(control)
        return IsControlPressed(0, control) or IsDisabledControlPressed(0, control)
    end
    function input.cancel() drag = nil end
    function input.control(data)
        if not finite(data.gesture) or data.gesture % 1 ~= 0 or data.gesture < 1
            or (data.phase ~= 'start' and data.phase ~= 'stop') then
            return { ok = false, error = 'invalid_camera_control' }
        end
        if session ~= data.session then session, lastGesture, drag = data.session, 0, nil end
        if data.phase == 'stop' then
            if data.gesture >= lastGesture then lastGesture, drag = data.gesture, nil end
            return { ok = true }
        end
        if data.gesture <= lastGesture then return { ok = false, error = 'stale_camera_gesture' } end
        local button = ({ [0] = 237, [1] = 348, [2] = 238 })[data.button]
        if not button or not finite(data.cursorX) or not finite(data.cursorY)
            or data.cursorX < 0 or data.cursorX > 1 or data.cursorY < 0 or data.cursorY > 1
            or type(data.free) ~= 'boolean' then return { ok = false, error = 'invalid_camera_control' } end
        lastGesture = data.gesture
        if Admin.setTypingLock then Admin.setTypingLock(false) end
        local width, height = GetActiveScreenResolution()
        if width <= 0 or height <= 0 then return { ok = false, error = 'camera_unavailable' } end
        -- Keep the origin and subsequent samples in the same coordinate space.
        -- CEF CSS pixels and native cursor pixels can differ with display/NUI
        -- scaling; converting the DOM origin by render resolution caused a jump.
        -- The press point is the anchor: each frame reads the displacement from
        -- it, then warps the (hidden) cursor back so it never leaves the spot.
        local cursorX, cursorY = GetNuiCursorPosition()
        local current = { x = cursorX, y = cursorY, width = width, height = height,
            session = session, started = GetGameTimer(), seenHeld = false }
        local function pin(x, y)
            if type(SetCursorLocation) == 'function' then
                SetCursorLocation(current.x / current.width, current.y / current.height)
            else
                current.x, current.y = x, y
            end
        end
        drag = current
        CreateThread(function()
            while drag == current and isCurrent(current.session) and IsNuiFocused() do
                local down = held(button) or (data.button == 0 and held(24)) or (data.button == 2 and held(25))
                -- Give the initial focus transition one short grace period. Once
                -- observed, physical release stops locally even if CEF is busy.
                if down then current.seenHeld = true
                elseif current.seenHeld or GetGameTimer() - current.started > 100 then break end
                local w, h = GetActiveScreenResolution()
                local x, y = GetNuiCursorPosition()
                if w <= 0 or h <= 0 then break end
                if w ~= current.width or h ~= current.height then
                    current.width, current.height, current.x, current.y = w, h, x, y
                end
                -- Inverted: the subject follows the hand (drag right swings the
                -- camera left around it; drag up tilts the view down).
                local dx, dy = (current.x - x) * 1080 / h, (current.y - y) * 1080 / h
                if dx ~= 0 or dy ~= 0 then pin(x, y) end
                if down and (dx ~= 0 or dy ~= 0) then
                    -- Middle drag pans; right/left drag orbit, Shift turns either into pan.
                    local pan = data.free or data.button == 1 or held(21)
                    apply({ x = pan and 0 or dx, y = pan and 0 or dy,
                        panX = pan and dx or 0, panY = pan and dy or 0, zoom = 0, free = data.free, direct = true })
                end
                Wait(0)
            end
            if drag == current then drag = nil end
        end)
        return { ok = true }
    end
    return input
end

-- Eases discrete camera moves (wheel, buttons, presets, reset) toward the live
-- target pose from read(). Direct drag deltas are carried 1:1 into the shown
-- pose, so held drags keep zero latency even while a zoom is still easing.
-- The worker runs only while the pose is unsettled; idle frames do nothing.
-- Config.StudioCameraGlideMs = 0 restores instant jumps.
local ANGLE = { orbit = true, angle = true }
local function angleDelta(a, b) return (b - a + 180) % 360 - 180 end

Admin.createStudioCameraGlide = function(isCurrent, read, render)
    local glide = { shown = nil }
    local worker = 0
    local function duration()
        local ms = Config and tonumber(Config.StudioCameraGlideMs)
        if ms == nil or ms ~= ms then ms = 220 end
        return math.max(0, math.min(1000, ms))
    end
    local function diff(key, from, to) return ANGLE[key] and angleDelta(from, to) or to - from end
    function glide.snap()
        worker = worker + 1
        glide.shown = {}
        for key, value in pairs(read()) do glide.shown[key] = value end
        render(glide.shown)
    end
    -- Move the shown pose by the target's change since `before`, immediately.
    function glide.carry(before)
        if not glide.shown or duration() == 0 then return glide.snap() end
        for key, value in pairs(read()) do
            glide.shown[key] = (glide.shown[key] or value) + diff(key, before[key] or value, value)
        end
        render(glide.shown)
    end
    function glide.start()
        local ms = duration()
        if not glide.shown or ms == 0 then return glide.snap() end
        worker = worker + 1
        local id, last = worker, GetGameTimer()
        CreateThread(function()
            while id == worker and isCurrent() do
                Wait(0)
                if id ~= worker or not isCurrent() then return end
                local now = GetGameTimer()
                -- Exponential approach: about 95% of the move lands within `ms`.
                local alpha = 1 - math.exp(-math.max(0, now - last) * 3 / ms)
                last = now
                local settled = true
                for key, value in pairs(read()) do
                    local d = diff(key, glide.shown[key] or value, value)
                    if math.abs(d) > (ANGLE[key] and 0.02 or 0.0004) then
                        glide.shown[key] = glide.shown[key] + d * alpha
                        settled = false
                    else
                        glide.shown[key] = value
                    end
                end
                render(glide.shown)
                if settled then
                    if id == worker then worker = worker + 1 end
                    return
                end
            end
        end)
    end
    function glide.stop() worker = worker + 1; glide.shown = nil end
    return glide
end
