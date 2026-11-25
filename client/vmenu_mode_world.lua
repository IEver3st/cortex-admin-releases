-- vMenu mode: Time Options, Weather Options, Voice Chat Settings, Recording
-- Options, Misc Settings (with its teleport, developer, entity spawner, keybind
-- and connection submenus) and About, in vMenu 3.8.67's order and wording
-- (vMenu/menus/TimeOptions.cs, WeatherOptions.cs, VoiceChat.cs, Recording.cs,
-- MiscSettings.cs, About.cs). Every row runs an existing Cortex action.
local Admin = EsAdmin
local VM = Admin.VmenuMode

local function notify(kind, message) Admin.notify(kind, message) end
local INVALID_INPUT = 'No valid input was entered, so nothing changed.'

-- Checkbox bound to a Cortex toggle that also prints vMenu's change notice.
local function check(actionId, label, description, message)
    return VM.toggle(actionId, label, description, {
        onCheck = function(checked)
            if VM.denied(actionId) then return end
            if message then notify('info', message(checked)) end
            Admin.toggleAction(actionId, checked)
        end,
    })
end

local function onOff(checked) return checked and 'enabled' or 'disabled' end

-- ---------------------------------------------------------------------------
-- Time Options (TimeOptions.cs)

local function twoDigits(value) return ('%02d'):format(value) end
local HOURS, MINUTES = {}, {}
for i = 0, 59 do
    MINUTES[#MINUTES + 1] = twoDigits(i)
    if i < 24 then HOURS[#HOURS + 1] = twoDigits(i) end
end
local TIME_PRESETS = {
    { 'Early Morning', 6 }, { 'Morning', 9 }, { 'Noon', 12 }, { 'Early Afternoon', 15 },
    { 'Afternoon', 18 }, { 'Evening', 21 }, { 'Midnight', 0 }, { 'Night', 3 },
}

local function setExactTime(hour, minute)
    if VM.denied('world.exactTime') or VM.denied('world.time') then return end
    notify('info', ('Clock changed to %s:%s.'):format(twoDigits(hour), twoDigits(minute)))
    VM.execute('world.exactTime', { hour = hour, minute = minute })
end

VM.define('time_options', {
    subtitle = 'Time Options',
    build = function()
        local rows = {}
        if VM.can('world.freezeTime') then
            rows[#rows + 1] = VM.button('Freeze/Unfreeze Time', 'Stops or resumes the in-game clock.', function()
                if VM.denied('world.freezeTime') then return end
                local frozen = VM.isOn('world.freezeTime')
                notify('info', ('The clock is now %s.'):format(frozen and 'running' or 'frozen'))
                Admin.toggleAction('world.freezeTime', not frozen)
            end, { key = 'world.freezeTime' })
        end
        if VM.can('world.time') then
            for _, preset in ipairs(TIME_PRESETS) do
                local label, hour = preset[1], preset[2]
                rows[#rows + 1] = VM.button(label, ('Moves the clock to %s:00.'):format(twoDigits(hour)), function()
                    if VM.denied('world.time') then return end
                    notify('info', ('Clock changed to %s:00.'):format(twoDigits(hour)))
                    Admin.selectAction('world.time', hour)
                end, { rightLabel = twoDigits(hour) .. ':00' })
            end
        end
        -- The custom lists keep the other half of the clock, so they need the exact-time action too.
        if VM.can('world.time') and VM.can('world.exactTime') then
            rows[#rows + 1] = { kind = 'list', key = 'manualHour', label = 'Set Custom Hour', values = HOURS, index = 1,
                onSelect = function(position) setExactTime(position - 1, GetClockMinutes()) end }
            rows[#rows + 1] = { kind = 'list', key = 'manualMinute', label = 'Set Custom Minute', values = MINUTES, index = 1,
                onSelect = function(position) setExactTime(GetClockHours(), position - 1) end }
        end
        return rows
    end,
})

-- ---------------------------------------------------------------------------
-- Weather Options (WeatherOptions.cs)

local WEATHERS = {
    { 'Extra Sunny', 'EXTRASUNNY', 'extra sunny' }, { 'Clear', 'CLEAR', 'clear' }, { 'Neutral', 'NEUTRAL', 'neutral' },
    { 'Smog', 'SMOG', 'smog' }, { 'Foggy', 'FOGGY', 'foggy' }, { 'Cloudy', 'CLOUDS', 'clouds' },
    { 'Overcast', 'OVERCAST', 'overcast' }, { 'Clearing', 'CLEARING', 'clearing' }, { 'Rainy', 'RAIN', 'rain' },
    { 'Thunder', 'THUNDER', 'thunder' }, { 'Blizzard', 'BLIZZARD', 'blizzard' }, { 'Snow', 'SNOW', 'snow' },
    { 'Light Snow', 'SNOWLIGHT', 'light snow' }, { 'X-MAS Snow', 'XMAS', 'x-mas' }, { 'Halloween', 'HALLOWEEN', 'halloween' },
}
local SNOWY = { XMAS = true, SNOWLIGHT = true, SNOW = true, BLIZZARD = true }

VM.define('weather_options', {
    subtitle = 'Weather Options',
    build = function()
        local rows = {
            check('world.dynamicWeather', 'Toggle Dynamic Weather', 'Lets the weather cycle on its own over time.',
                function(on) return ('Automatic weather cycling %s.'):format(onOff(on)) end),
            check('world.blackout', 'Toggle Blackout', 'Cuts power to every light on the map while active.',
                function(on) return ('Map blackout %s.'):format(onOff(on)) end),
            check('world.vehicleBlackout', 'Toggle Vehicle Lights Blackout', 'Turns off the lights on every vehicle while active.',
                function(on) return ('Vehicle light blackout %s.'):format(onOff(on)) end),
        }
        if VM.can('world.weather') then
            rows[#rows + 1] = VM.toggle('world.snowEffects', 'Enable Snow Effects',
                'Covers the ground in snow and adds snow trail effects to peds and vehicles. Looks best alongside X-MAS Snow or Light Snow weather.',
                { onCheck = function(checked)
                    if VM.denied('world.snowEffects') then return end
                    local weather = Admin.worldState and Admin.worldState.weather
                    if SNOWY[weather] then
                        notify('error', ('Snow stays on while the weather is %s. Change the weather first.'):format(weather))
                        return
                    end
                    notify('info', ('Forced snow %s.'):format(onOff(checked)))
                    Admin.toggleAction('world.snowEffects', checked)
                end })
            for _, weather in ipairs(WEATHERS) do
                local label, value, text = weather[1], weather[2], weather[3]
                rows[#rows + 1] = VM.button(label, ('Applies ~y~%s~s~ weather to the server.'):format(text), function()
                    if VM.denied('world.weather') then return end
                    notify('info', ('Switching the weather to %s.'):format(label))
                    Admin.selectAction('world.weather', value)
                end, { key = 'weather:' .. value })
            end
        end
        rows[#rows + 1] = VM.action('world.randomClouds', 'Randomize Clouds', 'Picks a random cloud layer for the sky.')
        rows[#rows + 1] = VM.action('world.removeClouds', 'Remove All Clouds', 'Removes every cloud layer from the sky.')
        return rows
    end,
})

-- ---------------------------------------------------------------------------
-- Voice Chat Settings (VoiceChat.cs). vMenu nests every row under VCEnable.

local CHANNELS = { 'Channel 1 (Default)', 'Channel 2', 'Channel 3', 'Channel 4', 'Staff Channel' }
local GLOBAL_PROXIMITY = 9999.0 -- the voice.proximity value Cortex labels Global

local function formatNumber(value)
    if value == math.floor(value) then return ('%d'):format(value) end
    return (('%.3f'):format(value):gsub('0+$', ''))
end

local function metric(value)
    if value == 0 or value >= GLOBAL_PROXIMITY then return 'global' end
    if value < 1 then return formatNumber(value * 100) .. 'cm' end
    if value < 1000 then return formatNumber(value) .. 'm' end
    return formatNumber(value / 1000) .. 'km'
end

local function voiceState()
    return type(Admin.getVoiceState) == 'function' and Admin.getVoiceState() or {}
end

VM.define('voice_chat', {
    subtitle = 'Voice Chat Settings',
    build = function()
        if not VM.can('voice.enabled') then return {} end
        local voice = voiceState()
        local proximity = tonumber(voice.proximity) or 8.0
        local channel = math.floor(tonumber(voice.channel) or 0)
        local rows = {
            VM.toggle('voice.enabled', 'Enable Voice Chat', 'Lets you talk and hear other players over voice.'),
            VM.toggle('voice.showSpeaker', 'Show Current Speaker', 'Lists the players speaking right now on screen.'),
        }
        if VM.can('voice.proximity') then
            rows[#rows + 1] = VM.button(('Voice Chat Proximity (%s)'):format(metric(proximity)),
                'How far away, in meters, you can hear other players. Enter 0 to hear everyone.', function()
                    if VM.denied('voice.proximity') then return end
                    local result = tonumber(VM.input(('Hearing range in meters (now %s)'):format(metric(proximity)), nil, 6))
                    if not result then return end
                    if result == 0 then result = GLOBAL_PROXIMITY end
                    if result < 0.5 or result > 10000 then notify('error', 'Proximity must be 0 (global) or between 0.5 and 10000 meters.'); return end
                    Admin.selectAction('voice.proximity', result)
                    notify('info', ('Voice range is now %s.'):format(metric(result)))
                end, { key = 'voice.proximity' })
        end
        if VM.can('voice.channel') then
            local channels = { table.unpack(CHANNELS, 1, VM.ace('vMenu.VoiceChat.StaffChannel', 'voice.channel') and 5 or 4) }
            rows[#rows + 1] = { kind = 'list', key = 'voice.channel', label = 'Voice Chat Channel', description = 'Choose which voice channel you talk and listen on.',
                values = channels, index = (channel >= 0 and channel < #channels) and channel + 1 or 1,
                onChange = function(position)
                    if VM.denied('voice.channel') then return end
                    -- vMenu joins native channel <list index>, and clears the channel for the default.
                    VM.execute('voice.channel', { channel = position - 1 })
                    notify('info', ('Switched to %s.'):format(CHANNELS[position]))
                end }
        end
        rows[#rows + 1] = VM.toggle('voice.showStatus', 'Show Microphone Status', 'Displays an on-screen indicator for your microphone state.')
        return rows
    end,
})

-- ---------------------------------------------------------------------------
-- Recording Options (Recording.cs). Photos, clips and the editor are local game
-- features: capture rows use dev.takePhoto, the editor uses dev.openGallery.

VM.define('recording', {
    title = 'Recording',
    subtitle = 'Recording Options',
    build = function()
        local capture = VM.can('dev.takePhoto')
        return {
            capture and VM.button('Take Photo', 'Captures a screenshot into the gallery in the pause menu.', function()
                if VM.denied('dev.takePhoto') then return end
                BeginTakeHighQualityPhoto()
                SaveHighQualityPhoto(-1)
                FreeMemoryForHighQualityPhoto()
            end) or nil,
            VM.action('dev.openGallery', 'Open Gallery', 'Browse your saved photos in the pause menu.'),
            capture and VM.button('Start Recording', "Begins a clip with the game's own recorder.", function()
                if VM.denied('dev.takePhoto') then return end
                if IsRecording() then
                    notify('error', 'A clip is already recording. Stop it before starting another.')
                    return
                end
                StartRecording(1)
            end) or nil,
            capture and VM.button('Stop Recording', 'Ends the clip in progress and keeps it.', function()
                if VM.denied('dev.takePhoto') then return end
                if not IsRecording() then
                    notify('error', 'No clip is recording, so there is nothing to save.')
                    return
                end
                StopRecordingAndSaveClip()
            end) or nil,
            VM.can('dev.openGallery') and VM.button('Rockstar Editor', 'Launches the Rockstar Editor. Leaving the session first can avoid problems.', function()
                if VM.denied('dev.openGallery') then return end
                if Admin.vmenuSetting and Admin.vmenuSetting('vmenu_quit_session_in_rockstar_editor', false) then NetworkSessionEnd(true, true) end
                ActivateRockstarEditor()
                Wait(0)
                while IsPauseMenuActive() do Wait(0) end
                DoScreenFadeIn(1)
            end) or nil,
        }
    end,
})

-- ---------------------------------------------------------------------------
-- Misc Settings (MiscSettings.cs)

-- Saved locations are read from KVP once per open, as vMenu fills the menu in OnMenuOpen.
local savedLocations = {}
local function loadLocations()
    savedLocations = type(Admin.getSavedTeleportLocations) == 'function' and Admin.getSavedTeleportLocations() or {}
end

local function round2(value)
    local text = ('%.2f'):format(tonumber(value) or 0):gsub('0+$', ''):gsub('%.$', '')
    return text == '-0' and '0' or text
end

local function readCoordinate(axis)
    local value = VM.input(('Type the %s value.'):format(axis))
    if value == nil or value == '' then notify('error', INVALID_INPUT); return nil end
    local number = tonumber(value)
    if not number then notify('error', ('The %s value must be a number.'):format(axis)); return nil end
    return number
end

VM.define('misc_teleport_options', {
    subtitle = 'Teleport Options',
    build = function()
        local locations = VM.can('teleport.loadLocation')
        return {
            VM.action('teleport.waypoint', 'Teleport To Waypoint', 'Moves you to the marker set on your map.', {}),
            VM.action('teleport.back', 'Teleport Back', 'Returns you to where you were before your last teleport.'),
            VM.can('teleport.coords') and VM.button('Teleport To Coords', 'Type X, Y and Z values to move straight to that spot.', function()
                if VM.denied('teleport.coords') then return end
                local x = readCoordinate('X'); if not x then return end
                local y = readCoordinate('Y'); if not y then return end
                local z = readCoordinate('Z'); if not z then return end
                VM.execute('teleport.coords', { x = x, y = y, z = z })
            end, { key = 'teleport.coords' }) or nil,
            locations and VM.submenu('misc_teleport_locations', 'Teleport Locations',
                'Jump to one of the saved locations.', nil, { hideEmpty = false }) or nil,
            (locations and VM.can('teleport.saveLocation')) and VM.button('Save Teleport Location',
                'Stores where you stand now as a new entry under Teleport Locations, kept on this computer.', function()
                    if VM.denied('teleport.saveLocation') then return end
                    local name = VM.input('Name for this location', nil, 30)
                    if name == nil or name == '' then notify('error', INVALID_INPUT); return end
                    loadLocations()
                    for _, location in ipairs(savedLocations) do
                        if location.name == name then notify('error', 'A location with that name already exists. Pick another name.'); return end
                    end
                    VM.execute('teleport.saveLocation', { name = name })
                    loadLocations()
                end, { key = 'teleport.saveLocation' }) or nil,
            (locations and VM.can('teleport.deleteLocation')) and VM.button('Delete Teleport Location',
                'Type the name of a saved location to remove it from Teleport Locations.', function()
                    if VM.denied('teleport.deleteLocation') then return end
                    local name = VM.input('Name of the location to delete', nil, 30)
                    if name == nil or name == '' then notify('error', INVALID_INPUT); return end
                    VM.execute('teleport.deleteLocation', { name = name })
                    loadLocations()
                end, { key = 'teleport.deleteLocation' }) or nil,
        }
    end,
})

VM.define('misc_teleport_locations', {
    subtitle = 'Teleport Locations',
    onOpen = loadLocations,
    build = function()
        if not VM.can('teleport.loadLocation') then return {} end
        local rows = {}
        for _, location in ipairs(savedLocations) do
            local name = location.name
            rows[#rows + 1] = VM.button(name, ('~y~%s~s~~n~X: ~y~%s~s~ Y: ~y~%s~s~ Z: ~y~%s~s~~n~Heading: ~y~%s~s~'):format(
                name, round2(location.x), round2(location.y), round2(location.z), round2(location.h)), function()
                    VM.execute('teleport.loadLocation', { name = name })
                end, { key = 'location:' .. name })
        end
        return rows
    end,
})

-- Timecycle modifiers from GTA V game data (client/game_catalogs.lua), sorted by name.
local TIMECYCLES = EsAdminGameCatalogs and EsAdminGameCatalogs.timecycles or {}
local TIMECYCLE_VALUES = {}
for i, name in ipairs(TIMECYCLES) do TIMECYCLE_VALUES[i] = ('%s (%d/%d)'):format(name, i, #TIMECYCLES) end
-- vMenu keeps these per session too; the modifier starts disabled.
local timecycle = { enabled = false, index = 1, strength = 0 }
local dimensionPosition = 5 -- Cortex's 50 m default radius on vMenu's 0-20 slider

local function applyTimecycle()
    if timecycle.enabled then
        VM.execute('dev.timecycle', { name = TIMECYCLES[timecycle.index], strength = timecycle.strength / 20 })
    elseif VM.can('dev.clearTimecycle') then
        VM.execute('dev.clearTimecycle')
    end
end

VM.define('misc_developer_tools', {
    subtitle = 'Development Tools',
    build = function()
        local rows = {
            VM.can('world.clearArea') and VM.button('Clear Area', 'Resets a 100 meter radius around you to its default state: peds, props and vehicles are removed, and damage and dirt are repaired.', function()
                if VM.denied('world.clearArea') then return end
                Admin.selectAction('world.clearArea', 100)
            end, { key = 'world.clearArea' }) or nil,
            -- Both cameras take the arrow keys, so the menu closes first.
            VM.toggle('dev.freecam', 'Freecam', 'A detached camera for inspecting vehicles, interiors and props. Turning it on closes this menu. Not available while noclip is on.', {
                onCheck = function(checked)
                    if VM.denied('dev.freecam') then return end
                    if checked then Admin.closeVmenuMode() end
                    Admin.toggleAction('dev.freecam', checked)
                end,
            }),
            VM.action('dev.photoMode', 'Photo Mode', 'A free camera for screenshots. Closes this menu; press U to leave photo mode.', nil, {
                onSelect = function()
                    if VM.denied('dev.photoMode') then return end
                    Admin.closeVmenuMode()
                    VM.execute('dev.photoMode')
                end,
            }),
            VM.can('player.copyCoords') and {
                kind = 'list', key = 'player.copyCoords', label = 'Copy Coordinates', values = { 'vector4', 'vector3' },
                description = 'Copies your position to the clipboard. vector4 includes your heading.',
                onSelect = function(position)
                    if VM.denied('player.copyCoords') then return end
                    VM.execute('player.copyCoords', { format = position == 2 and 'vector3' or 'vector4' })
                end,
            } or nil,
            VM.action('player.copyHeading', 'Copy Heading', 'Copies the direction you face to the clipboard.'),
            VM.action('dev.setStress', 'Set My Stress', 'Type a stress level from 0 to 100 for your own character.'),
            VM.toggle('dev.showCoords', 'Show Coordinates', 'Displays your X, Y and Z position at the top of the screen.'),
            VM.toggle('dev.vehicleDimensions', 'Show Vehicle Dimensions', 'Outlines the bounding box of each nearby vehicle.'),
            VM.toggle('dev.propDimensions', 'Show Prop Dimensions', 'Outlines the bounding box of each nearby prop.'),
            VM.toggle('dev.pedDimensions', 'Show Ped Dimensions', 'Outlines the bounding box of each nearby ped.'),
            VM.toggle('dev.entityHandles', 'Show Entity Handles', 'Labels nearby entities with their handle. Needs one of the dimension outlines above turned on.'),
            VM.toggle('dev.entityModels', 'Show Entity Models', 'Labels nearby entities with their model name. Needs one of the dimension outlines above turned on.'),
            VM.toggle('dev.entityOwners', 'Show Network Owners', 'Labels nearby entities with the player that owns them on the network. Needs one of the dimension outlines above turned on.'),
        }
        if VM.can('dev.dimensionRadius') then
            -- Cortex inspects 10-200 m, so each slider step is 10 m.
            rows[#rows + 1] = { kind = 'slider', key = 'dev.dimensionRadius', label = 'Show Dimensions Radius',
                description = 'How far out outlines and labels are drawn, from 10 to 200 meters.', min = 0, max = 20, value = dimensionPosition,
                onChange = function(position)
                    if VM.denied('dev.dimensionRadius') then return end
                    dimensionPosition = position
                    Admin.selectAction('dev.dimensionRadius', math.max(10, position * 10))
                end }
        end
        if VM.can('dev.timecycle') then
            rows[#rows + 1] = { kind = 'list', key = 'dev.timecycle:list', label = 'TM', values = TIMECYCLE_VALUES, index = timecycle.index,
                description = 'Pick a modifier, then turn on Enable Timecycle Modifier to apply it.',
                onChange = function(position)
                    if VM.denied('dev.timecycle') then return end
                    timecycle.index = position
                    applyTimecycle()
                end }
            rows[#rows + 1] = { kind = 'checkbox', key = 'dev.timecycle:enabled', label = 'Enable Timecycle Modifier',
                description = 'Applies the modifier chosen in the TM list.', checked = timecycle.enabled,
                onCheck = function(checked)
                    if VM.denied('dev.timecycle') then return end
                    timecycle.enabled = checked
                    applyTimecycle()
                end }
            rows[#rows + 1] = { kind = 'slider', key = 'dev.timecycle:strength', label = 'Timecycle Modifier Intensity',
                description = 'Strength of the active modifier, from 0 to 20.', min = 0, max = 20, value = timecycle.strength,
                onChange = function(position)
                    if VM.denied('dev.timecycle') then return end
                    timecycle.strength = position
                    applyTimecycle()
                end }
        end
        rows[#rows + 1] = VM.submenu('misc_entity_spawner', 'Entity Spawner', 'Place props, peds and vehicles and adjust their position.')
        return rows
    end,
})

local function modelType(name)
    local model = GetHashKey(name)
    if IsModelAVehicle(model) then return 'vehicle' end
    if IsModelAPed(model) then return 'ped' end
    return 'object'
end

VM.define('misc_entity_spawner', {
    subtitle = 'Entity Spawner',
    build = function()
        return {
            VM.can('dev.spawnEntity') and VM.button('Spawn New Entity', 'Creates a model by name and lets you move and rotate it into place.', function()
                if VM.denied('dev.spawnEntity') then return end
                local name = VM.input('Model name')
                if name == nil or name == '' then notify('error', INVALID_INPUT); return end
                VM.execute('dev.spawnEntity', { type = modelType(name), model = name })
            end, { key = 'dev.spawnEntity' }) or nil,
            VM.action('dev.confirmEntityPlacement', 'Confirm Entity Position', 'Finishes placement and leaves the entity where it is.'),
            VM.action('dev.duplicateEntityPlacement', 'Confirm Entity Position And Duplicate', 'Finishes placement, leaves the entity where it is and starts placing a copy.'),
            VM.action('dev.cancelEntityPlacement', 'Cancel', 'Removes the entity being placed.'),
        }
    end,
})

VM.define('misc_keybinds', {
    subtitle = 'Keybind Settings',
    build = function()
        local rows = {
            VM.can('teleport.waypoint') and VM.toggle('options.teleportWaypointKey', 'Teleport To Waypoint',
                'Lets the keybind move you to your waypoint. The default key is ~r~F7~s~, but the server can change it, so ask staff if it does not work.') or nil,
            VM.toggle('dev.driftMode', 'Drift Mode', 'Hold left Shift, or X on a controller, to make your vehicle lose almost all grip.'),
            VM.toggle('options.minimapControls', 'Minimap Controls', 'Press Multiplayer Info (Z on keyboard, d-pad down on controller) to switch the radar between normal and expanded.'),
            VM.toggle('options.fingerPointControls', 'Finger Point Controls', 'Turns on the pointing key: B on a QWERTY keyboard, or a quick double press of the right stick on a controller.'),
            VM.toggle('options.recordingControls', 'Recording Controls', 'Enable recording shortcuts on keyboard and controller.'),
        }
        -- Back alone would keep an otherwise empty menu visible.
        if next(rows) then rows[6] = VM.button('Back', nil, function() VM.back() end, { key = 'back' }) end
        return rows
    end,
})

VM.define('misc_connection', {
    subtitle = 'Connection Options',
    build = function()
        return {
            VM.action('options.quitSession', 'Quit Session', 'Drops you out of the network session but keeps you on the server. ~r~Not available while you are the session host.~s~'),
            VM.action('options.rejoinSession', 'Re-join Session', 'Tries to put you back into your last session after Quit Session. It does not always succeed.'),
            VM.action('options.quitGame', 'Quit Game', 'Closes the game after a 5 second delay.'),
            VM.action('options.disconnect', 'Disconnect From Server', 'Leaves the server and opens the server list. ~r~Closing and restarting the game is more reliable.~s~'),
        }
    end,
})

-- vMenu's two speedometers map onto Cortex's single speed HUD and its unit setting.
local function speedRow(units, label, description)
    if not (VM.can('dev.showSpeed') and VM.can('options.speedHudUnits')) then return nil end
    local current = Admin.state.settings.speedHudUnits == 'kph' and 'kph' or 'mph'
    return { kind = 'checkbox', key = 'speed:' .. units, label = label, description = description,
        checked = VM.isOn('dev.showSpeed') and current == units,
        onCheck = function(checked)
            if VM.denied('dev.showSpeed') or VM.denied('options.speedHudUnits') then return end
            if not checked then Admin.toggleAction('dev.showSpeed', false); return end
            if Admin.state.settings.speedHudUnits ~= units then Admin.selectAction('options.speedHudUnits', units) end
            if not VM.isOn('dev.showSpeed') then Admin.toggleAction('dev.showSpeed', true) end
        end }
end

VM.define('misc_settings', {
    subtitle = 'Misc Settings',
    build = function()
        return {
            VM.submenu('misc_teleport_options', 'Teleport Options', 'Waypoint, coordinate and saved location teleports.'),
            VM.submenu('misc_developer_tools', 'Developer Tools', 'Debug overlays, timecycles and the entity spawner.'),
            VM.can('options.menuPosition') and {
                kind = 'checkbox', key = 'options.menuPosition', label = 'Right Align Menu',
                description = 'Turn off to show the menu on the left side of the screen. This is saved immediately.',
                checked = Admin.state.settings.menuPosition == 'right',
                onCheck = function(checked)
                    if VM.denied('options.menuPosition') then return end
                    Admin.selectAction('options.menuPosition', checked and 'right' or 'left')
                end,
            } or nil,
            VM.toggle('options.disablePrivateMessages', 'Disable Private Messages', 'Blocks private messages from the Online Players menu, both incoming and outgoing.'),
            VM.toggle('options.disableControllerSupport', 'Disable Controller Support', 'Stops the controller from opening the menu. Navigating with the controller still works.'),
            speedRow('kph', 'Show Speed KM/H', 'Displays your current speed on screen in kilometers per hour.'),
            speedRow('mph', 'Show Speed MPH', 'Displays your current speed on screen in miles per hour.'),
            VM.submenu('misc_keybinds', 'Keybind Settings', 'Choose which optional shortcut keys are active.'),
            VM.submenu('misc_connection', 'Connection Options', 'Leave the session, the server or the game.'),
            VM.toggle('dev.locationDisplay', 'Location Display', 'Displays your street, area, heading and nearest intersection. ~r~Warning: can cost up to 4.6 FPS at 60 Hz.~s~', { icon = 'warning' }),
            VM.toggle('dev.showTime', 'Show Time On Screen', 'Displays the in-game clock on screen.'),
            VM.toggle('dev.joinQuitNotifications', 'Join / Quit Notifications', 'Posts a notice when a player connects or disconnects.'),
            VM.toggle('dev.deathNotifications', 'Death Notifications', 'Posts a notice when a player dies or is killed.'),
            VM.toggle('dev.nightVision', 'Toggle Night Vision', 'Applies the night vision filter.'),
            VM.toggle('dev.thermalVision', 'Toggle Thermal Vision', 'Applies the thermal vision filter.'),
            VM.toggle('dev.locationBlips', 'Location Blips', 'Marks well-known places on the map.'),
            VM.toggle('dev.playerBlips', 'Show Player Blips', 'Marks every player on the map. ~y~With OneSync Infinity, distant players are not shown.~s~'),
            VM.toggle('dev.overheadNames', 'Show Player Names', "Displays each player's name above their head."),
            VM.toggle('options.autoLoadSavedPed', 'Respawn As Default MP Character', "Spawns you as your default saved MP character after joining or dying. The server can turn this off for everyone. Pick the default from a saved character with 'Set As Default Character'."),
            VM.toggle('options.defaultToMpPed', 'Default To MP Ped', 'Uses the freemode MP ped when you have no saved default character.'),
            VM.toggle('options.restorePedOnDeath', 'Restore Player Appearance', 'Brings back your current ped look when you respawn after death. It is not kept after rejoining the server.'),
            (VM.can('weapons.restoreLoadoutOnRespawn') or VM.can('weapons.give')) and {
                kind = 'checkbox', key = 'options.restoreWeaponsOnDeath', label = 'Restore Player Weapons',
                description = 'Gives your weapons back when you respawn after death. They are not kept after rejoining the server.',
                checked = Admin.state.settings.restoreWeaponsOnDeath == true,
                onCheck = function(checked)
                    Admin.state.settings.restoreWeaponsOnDeath = checked == true
                    Admin.saveSettings()
                end,
            } or nil,
            VM.toggle('dev.hideRadar', 'Hide Radar', 'Removes the minimap from the screen.'),
            VM.toggle('options.mpPedPreviews', 'Character Previews', 'Show a local 3D preview while browsing saved characters and ped models.'),
            VM.toggle('dev.noHud', 'Hide Hud', 'Removes every HUD element from the screen.'),
            VM.toggle('dev.lockCameraHorizontal', 'Lock Camera Horizontal Rotation', 'Stops the camera from turning left or right. Handy when flying helicopters.'),
            VM.toggle('dev.lockCameraVertical', 'Lock Camera Vertical Rotation', 'Stops the camera from tilting up or down. Handy when flying helicopters.'),
            VM.can('options.openSettings') and VM.button('Save Personal Settings', 'Stores your current settings on this computer. Reinstalling Windows clears them.', function()
                if VM.denied('options.openSettings') then return end
                if Admin.saveSettings() == false then notify('error', 'Your settings could not be saved.'); return end
                notify('success', 'Settings saved.')
            end, { key = 'saveSettings', icon = 'tick' }) or nil,
            -- The reset reloads the UI; vMenu mode stays the interface.
            VM.action('dev.resetAllSettings', '~r~Reset All Settings', 'Restores every Cortex Admin setting to its default, except the menu style: vMenu mode stays. You confirm first.', nil, {
                icon = 'warning',
                onSelect = function()
                    if VM.denied('dev.resetAllSettings') then return end
                    Admin.closeVmenuMode()
                    VM.execute('dev.resetAllSettings', { keepInterface = true })
                end,
            }),
        }
    end,
})

-- ---------------------------------------------------------------------------
-- About (About.cs), describing Cortex Admin's vMenu mode rather than vMenu.

local VERSION = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown'

VM.define('about', {
    title = 'Cortex Admin',
    subtitle = 'About vMenu Mode',
    build = function()
        return {
            VM.button('Cortex Admin Version', ('This server is using Cortex Admin ~b~~h~%s~h~~s~.'):format(VERSION), nil,
                { rightLabel = ('~h~%s~h~'):format(VERSION) }),
            VM.button('About vMenu Mode / Credits', 'Cortex Admin is made by ~b~GSDMODS~s~ for ~b~CORTEX~s~. vMenu mode reproduces the layout and controls of vMenu by ~b~Vespura~s~. It is not vMenu: every option runs on Cortex Admin\'s own actions and permissions.'),
            Admin.vmenuSetting and Admin.vmenuSetting('vmenu_server_info_message', '') ~= '' and VM.button('Server Information', Admin.vmenuSetting('vmenu_server_info_message', '')) or nil,
            Admin.vmenuSetting and Admin.vmenuSetting('vmenu_server_info_website_url', '') ~= '' and VM.button('Server Website', Admin.vmenuSetting('vmenu_server_info_website_url', '')) or nil,
            VM.button('Use Cortex Panel', 'Switch to the full Cortex Admin panel and remember it. Choose vMenu again under Options > Interface.', function()
                EsAdmin.state.settings.interfaceStyle = 'panel'
                EsAdmin.saveSettings()
                VM.workspace('options')
            end),
        }
    end,
})
