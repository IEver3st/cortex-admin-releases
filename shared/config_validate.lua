local isServer = IsDuplicityVersion()

local function bool(default, onInvalid) return { kind = 'boolean', default = default, onInvalid = onInvalid } end
local function text(default) return { kind = 'string', default = default } end
local function key(default) return { kind = 'key', default = default } end
local function number(default, min, max) return { kind = 'number', default = default, min = min, max = max } end
local function oneOf(default, values) return { kind = 'enum', default = default, values = values } end
local function list(default, disabled) return { kind = 'table', default = default, disabled = disabled } end

local SCHEMA = {
    { 'Debug', bool(false) },
    { 'Dv', list({}) },
    { 'Dv.Enabled', bool(true, false) },
    { 'Dv.RequirePermission', bool(false, true) },
    { 'Dv.Range', number(6.0, 1.5, 25) },
    { 'Dv.CooldownMs', number(1500, 1000, 60000) },
    { 'VmenuCompatibility', list({}) },
    { 'VmenuCompatibility.respectConvars', bool(true) },
    { 'VmenuCompatibility.commandAlias', text('vmenu') },
    { 'VmenuCompatibility.keybind', key('M') },
    { 'VmenuCompatibility.waypointKeybind', key('F7') },
    { 'VmenuFallback', list({}, { enabled = false }) },
    { 'VmenuFallback.enabled', bool(true) },
    { 'VmenuFallback.cacheMs', number(5000, 0, 60000) },
    { 'VmenuVehicleClasses', list({}) },
    { 'VmenuAddonModels', list({ vehicles = {}, weapons = {}, peds = {} }) },
    { 'ProtectedResources', list({}) },
    { 'Command', text('esadmin') },
    { 'Keybind', key('F10') },
    { 'MenuControlKey', key('F4') },
    { 'WorldSync', list({}) },
    { 'WorldSync.mode', oneOf('auto', { 'auto', 'cortex', 'disabled' }) },
    { 'WorldSync.millisecondsPerGameMinute', number(2000, 100, 3600000) },
    { 'WorldSync.externalResources', list({}) },
    { 'WardrobeShareRadius', number(8.0, 0.01, 1000) },
    { 'Players', list({}) },
    { 'Players.maxRosterEntries', number(256, 1, 2048) },
    { 'VehiclePreviewCloseControl', number(177, 0, 400) },
    { 'WardrobeCapture', list({}) },
    { 'WardrobeCapture.settleMs', number(750, 250, 5000) },
    { 'StudioCameraGlideMs', number(220, 0, 1000) },
    { 'DefaultSettings', list({}) },
    { 'DefaultSettings.interfaceStyle', oneOf('panel', { 'panel', 'classic', 'vmenu', 'leonida', 'console' }) },
    { 'DefaultSettings.uiScale', number(1, 1, 1.6) },
    { 'DefaultSettings.uiOpacity', number(0.94, 0.35, 1) },
    { 'DefaultSettings.menuPosition', oneOf('center', { 'left', 'center', 'right' }) },
    { 'DefaultSettings.speedHudUnits', oneOf('mph', { 'mph', 'kph' }) },
    { 'DefaultSettings.speedHudPosition', oneOf('top-left', { 'top-left', 'top-center', 'top-right', 'bottom-left', 'bottom-center', 'bottom-right' }) },
    { 'AllowCommandAdmin', bool(true, false) },
    { 'Permissions', list({}) },
    { 'ActionPermissions', list({}) },
    { 'ShowcaseCamera', list({ toggleKey = 'U', filters = {} }) },
    { 'ShowcaseCamera.toggleKey', key('U') },
    { 'BanIdentifierTypes', list({ 'license', 'license2', 'steam', 'discord', 'fivem', 'xbl', 'live' }) },
    { 'QBXPermissions', list({}) },
}

local function describe(value)
    if type(value) == 'string' then return ('"%s"'):format(value) end
    if type(value) == 'table' then return 'a table' end
    return tostring(value)
end

local function check(rule, value)
    if rule.kind == 'boolean' and type(value) ~= 'boolean' then
        if rule.onInvalid ~= nil then return 'expected true or false', rule.onInvalid end
        return 'expected true or false', rule.default
    end
    if rule.kind == 'string' and (type(value) ~= 'string' or value == '') then return 'expected text', rule.default end
    if rule.kind == 'key' and type(value) ~= 'string' then return 'expected a key name, or "" for unbound', rule.default end
    if rule.kind == 'table' and type(value) ~= 'table' then
        if value == false and rule.disabled then return nil, rule.disabled end
        return 'expected a table', rule.default
    end
    if rule.kind == 'number' then
        local numeric = tonumber(value)
        if not numeric or numeric ~= numeric then return 'expected a number', rule.default end
        local bounded = math.max(rule.min, math.min(rule.max, numeric))
        if bounded ~= numeric then return ('expected %s-%s'):format(rule.min, rule.max), bounded end
        if numeric ~= value then return nil, numeric end
    end
    if rule.kind == 'enum' then
        for _, allowed in ipairs(rule.values) do
            if value == allowed then return nil end
        end
        return ('expected one of %s'):format(table.concat(rule.values, ', ')), rule.default
    end
end

for _, entry in ipairs(SCHEMA) do
    local path, rule = entry[1], entry[2]
    local parent, field = Config, path
    for segment, rest in path:gmatch('([^.]+)%.(.+)') do
        parent, field = type(parent) == 'table' and parent[segment] or nil, rest
    end
    if type(parent) == 'table' and parent[field] ~= nil then
        local reason, replacement = check(rule, parent[field])
        if reason and isServer then
            print(('^3[cortex-admin] shared/config.lua: Config.%s %s, got %s; using %s.^7'):format(path, reason, describe(parent[field]), type(replacement) == 'table' and 'the defaults' or describe(replacement)))
        end
        if replacement ~= nil then
            parent[field] = replacement
        end
    end
end
