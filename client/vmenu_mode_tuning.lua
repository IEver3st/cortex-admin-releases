-- vMenu mode: Live Vehicle Tuning, the Panel's Tuning page as MenuAPI menus.
-- Same session API (client/actions.lua Admin.vehicleTuning): handling values
-- step with Left/Right and apply at once, Enter types an exact value, and the
-- defaults captured when the session started are what Reset restores.
local Admin = EsAdmin
local VM = Admin.VmenuMode

local ACTION = 'vehicle.liveTuning'
local GROUPS = { 'Powertrain', 'Control', 'Grip', 'Chassis' }
local INVALID_INPUT = 'Nothing valid was entered, so the value was not changed.'

local function fields() return Admin.vehicleTuning and Admin.vehicleTuning.fields or {} end
local function format(field, value) return ('%.' .. (field.precision or 2) .. 'f'):format(value) .. (field.unit and (' ' .. field.unit) or '') end

-- The value at a list position, rounded to the field's precision and kept in range
-- (min + n * step drifts: 0.1 + 199 * 0.1 is 20.000000000000004).
local function valueAt(field, index)
    local scale = 10 ^ (field.precision or 2)
    local value = math.floor((field.min + (index - 1) * field.step) * scale + 0.5) / scale
    return math.max(field.min, math.min(field.max, value))
end
-- Every step of a field's range, built once per field.
local steps = {}
local function values(field)
    if steps[field.id] then return steps[field.id] end
    local list, count = {}, math.floor((field.max - field.min) / field.step + 0.5)
    for i = 1, count + 1 do list[i] = format(field, valueAt(field, i)) end
    steps[field.id] = list
    return list
end
local function position(field, value)
    local index = math.floor((value - field.min) / field.step + 0.5) + 1
    return math.max(1, math.min(#values(field), index))
end

-- A reset or typed value changes the live number; a new row key drops the
-- remembered list position so the row shows the live value again.
local revisions = {}
local function bump(id) revisions[id] = (revisions[id] or 0) + 1 end

local function result(response, success)
    if type(response) ~= 'table' or not response.ok then
        Admin.notify('error', type(response) == 'table' and response.message or 'The vehicle could not be tuned.')
        return false
    end
    if success then Admin.notify('success', success) end
    return true
end

local function session()
    local current, reason = Admin.getVehicleTuningSession()
    return current, reason
end

VM.define('vehicle_tuning', {
    subtitle = 'Live Vehicle Tuning',
    build = function()
        if not VM.can(ACTION) then return {} end
        local current, reason = session()
        if not current then
            return { VM.button('No Vehicle To Tune', reason or 'Get in the driver seat of a vehicle.', nil, { enabled = false, key = 'none' }) }
        end
        local rows = {
            VM.button(current.label, ('Model ~y~%s~s~, plate ~y~%s~s~. Changes apply to this vehicle until it is gone or you reset them.')
                :format(current.modelName, current.plate), nil, { rightLabel = current.plate, enabled = false, key = 'vehicle' }),
        }
        for _, group in ipairs(GROUPS) do
            rows[#rows + 1] = VM.submenu('vehicle_tuning_group', group, ('%s handling values.'):format(group), { key = group }, { hideEmpty = false })
        end
        local audio = current.audioName
        rows[#rows + 1] = VM.submenu('vehicle_tuning_audio', 'Engine Audio', 'Swap the engine sound for another vehicle\'s.', nil,
            { hideEmpty = false, rightLabel = audio and ('~y~' .. audio) or 'Default' })
        rows[#rows + 1] = VM.button('Reset Handling', 'Restore every handling value captured when tuning started. The engine sound stays.', function()
            if VM.denied(ACTION) then return end
            if result(Admin.resetVehicleTuning('handling'), 'Handling restored.') then for _, field in ipairs(fields()) do bump(field.id) end end
        end, { key = 'resetHandling', confirm = true })
        rows[#rows + 1] = VM.button('~r~Reset Everything', 'Restore every handling value and the original engine sound.', function()
            if VM.denied(ACTION) then return end
            if result(Admin.resetVehicleTuning('all'), 'Vehicle tuning restored.') then for _, field in ipairs(fields()) do bump(field.id) end end
        end, { key = 'resetAll', confirm = true, icon = 'warning' })
        return rows
    end,
})

VM.define('vehicle_tuning_group', {
    title = 'Live Vehicle Tuning',
    subtitle = function(args) return 'Tuning: ~y~' .. tostring(args and args.key or '') end,
    build = function(args)
        if not VM.can(ACTION) or type(args) ~= 'table' then return {} end
        local current, reason = session()
        if not current then
            return { VM.button('No Vehicle To Tune', reason or 'Get in the driver seat of a vehicle.', nil, { enabled = false, key = 'none' }) }
        end
        local rows = {}
        for _, field in ipairs(fields()) do
            if field.group == args.key then
                local live = GetVehicleHandlingFloat(current.vehicle, 'CHandlingData', field.id)
                local default = current.defaults[field.id]
                rows[#rows + 1] = {
                    -- Keyed by vehicle too, so another car never inherits this one's position.
                    kind = 'list', key = ('tune:%s:%s:%d'):format(tostring(current.vehicle), field.id, revisions[field.id] or 0), label = field.label,
                    values = values(field), index = position(field, live),
                    description = ('%s.~n~Now ~y~%s~s~, default ~y~%s~s~. Left/Right change it, Enter types an exact value.')
                        :format(field.description, format(field, live), type(default) == 'number' and format(field, default) or '?'),
                    onChange = function(index)
                        if VM.denied(ACTION) then return end
                        result(Admin.setVehicleTuningValue(field.id, valueAt(field, index)))
                    end,
                    onSelect = function()
                        if VM.denied(ACTION) then return end
                        local input = VM.input(('%s (%s to %s)'):format(field.label, format(field, field.min), format(field, field.max)),
                            ('%.' .. (field.precision or 2) .. 'f'):format(live), 12)
                        local value = tonumber(input or '')
                        if not value then Admin.notify('error', INVALID_INPUT); return end
                        if result(Admin.setVehicleTuningValue(field.id, value)) then bump(field.id) end
                    end,
                }
            end
        end
        rows[#rows + 1] = VM.button('Reset This Group', ('Restore the %s values captured when tuning started.'):format(args.key:lower()), function()
            if VM.denied(ACTION) then return end
            for _, field in ipairs(fields()) do
                if field.group == args.key then
                    if not result(Admin.resetVehicleTuningField(field.id)) then return end
                    bump(field.id)
                end
            end
            Admin.notify('success', args.key .. ' restored.')
        end, { key = 'resetGroup' })
        return rows
    end,
})

VM.define('vehicle_tuning_audio', {
    title = 'Live Vehicle Tuning',
    subtitle = 'Engine Audio',
    build = function()
        if not VM.can(ACTION) then return {} end
        local current, reason = session()
        if not current then
            return { VM.button('No Vehicle To Tune', reason or 'Get in the driver seat of a vehicle.', nil, { enabled = false, key = 'none' }) }
        end
        local rows = {}
        for _, preset in ipairs(Admin.vehicleTuning.audioPresets or {}) do
            rows[#rows + 1] = VM.button(preset.label, ('Use the %s engine sound.'):format(preset.label), function()
                if VM.denied(ACTION) then return end
                result(Admin.setVehicleTuningAudio(preset.value), preset.label .. ' engine sound applied.')
            end, { key = 'audio:' .. preset.value, rightLabel = current.audioName == preset.value and '~g~Active' or nil })
        end
        rows[#rows + 1] = VM.button('Custom Engine Sound', 'Type a vehicle model name, such as t20, to use its engine sound.', function()
            if VM.denied(ACTION) then return end
            local input = VM.input('Vehicle model name for the engine sound', current.audioName or '', 64)
            if not input or input == '' then Admin.notify('error', INVALID_INPUT); return end
            result(Admin.setVehicleTuningAudio(input), 'Engine sound applied.')
        end, { key = 'audio:custom' })
        rows[#rows + 1] = VM.button('Default Engine Sound', 'Go back to this vehicle\'s own engine sound.', function()
            if VM.denied(ACTION) then return end
            result(Admin.resetVehicleTuning('audio'), 'Original engine sound restored.')
        end, { key = 'audio:default' })
        return rows
    end,
})
