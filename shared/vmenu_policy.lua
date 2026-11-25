-- Shared, bounded configuration parsing. Authority remains in server/vmenu_policy.lua.
EsAdminVmenuPolicy = {}
local P = EsAdminVmenuPolicy
local reference = EsAdminVmenuReference or { defaults = {}, permissions = {} }
local bounds = {
    vmenu_vehicle_spawn_delay = { 0, 3600 }, vmenu_delete_vehicle_distance = { 0, 1000 },
    vmenu_allowed_engine_damage_for_extra_change = { -4000, 1000 },
    vmenu_allowed_body_damage_for_extra_change = { 0, 1000 }, vmenu_player_names_distance = { 0, 10000 },
    vmenu_dynamic_weather_timer = { 1, 1440 }, vmenu_weather_change_duration = { 0, 3600 },
    vmenu_ingame_minute_duration = { 100, 3600000 }, vmenu_current_hour = { 0, 23 },
    vmenu_current_minute = { 0, 59 }, vmenu_pvp_mode = { 0, 2 },
    vmenu_override_voicechat_default_range = { 0, 10000 }, vmenu_teleport_to_wp_keybind_key = { 0, 360 },
}
function P.get(name, fallback)
    local default = fallback
    if default == nil then default = reference.defaults[name] end
    if Config.VmenuCompatibility and Config.VmenuCompatibility.respectConvars == false then return default end
    if type(P.received) == 'table' and P.received[name] ~= nil then return P.received[name] end
    local value = GetConvar and GetConvar(name, '') or ''
    if value == '' then return default end
    if type(default) == 'boolean' then
        if value == 'true' or value == '1' then return true end
        if value == 'false' or value == '0' then return false end
    elseif type(default) == 'number' then
        local number = tonumber(value)
        local limit = bounds[name]
        if number and number == number and math.abs(number) < math.huge then
            if limit then number = math.max(limit[1], math.min(limit[2], number)) end
            return number
        end
    elseif type(default) == 'string' then return value:sub(1, 1024) end
    return default
end
function P.settings()
    local result = {}
    for name in pairs(reference.defaults) do result[name] = P.get(name) end
    return result
end
function P.actionEnabled(action)
    if action == 'options.mpPedPreviews' and not P.get('vmenu_mp_ped_preview', true) then return false end
    if action == 'vehicle.noSiren' and P.get('vmenu_use_els_compatibility_mode', false) then return false end
    if action == 'player.invisible' and not P.get('vmenu_handle_invisibility', true) then return false end
    if (action == 'options.autoLoadSavedPed' or action == 'options.defaultToMpPed')
        and P.get('vmenu_disable_spawning_as_default_character', false) then return false end
    if (action == 'dev.vehicleDimensions' or action == 'dev.propDimensions' or action == 'dev.pedDimensions')
        and P.get('vmenu_disable_entity_outlines_tool', false) then return false end
    return true
end
