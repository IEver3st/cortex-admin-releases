local Admin, P = EsAdmin, EsAdminVmenuPolicy
function Admin.vmenuSetting(name, fallback) return P.get(name, fallback) end
function Admin.vmenuAce(ace, action)
    local policy = Admin.state.vmenuPolicy
    if type(policy) ~= 'table' then return action ~= nil and Admin.state.allowed[action] == true end
    if action and policy.cortex and policy.cortex[action] then return true end
    return policy.aces and policy.aces[ace] == true or false
end
-- Cortex rows added to vMenu's menus have no vMenu ACE, so holding one of
-- them (some, like player.freezeTarget, are permission ids outside the action
-- catalog the policy snapshot covers) opens its menu; each row still checks its own action.
local CORTEX_ONLY = {
    OnlinePlayers = { 'player.freezeTarget', 'player.reviveTarget' },
    PlayerOptions = { 'player.gearUp', 'player.armor', 'player.revive', 'player.clearWanted' },
    WeaponOptions = { 'weapons.explosiveAmmo', 'weapons.fireAmmo', 'weapons.gravityGun', 'weapons.setAmmo' },
    VehicleOptions = { 'vehicle.maxMods', 'vehicle.performanceMods', 'vehicle.adminCar', 'vehicle.giveKeys', 'vehicle.camera', 'vehicle.liveTuning' },
    PlayerAppearance = { 'player.randomizeAppearance', 'player.undoRandomizedAppearance' },
}
local function cortexOnly(domain, granted)
    for _, action in ipairs(CORTEX_ONLY[domain] or {}) do
        if granted[action] then return true end
    end
    -- Qbox character tools on a player open through the Players console.
    if domain == 'OnlinePlayers' and QboxAdmin and QboxAdmin.actions then
        for id, action in pairs(QboxAdmin.actions) do
            if not action.selfOnly and granted[id] then return true end
        end
    end
    return false
end
function Admin.vmenuMenuAllowed(domain)
    local policy = Admin.state.vmenuPolicy
    if type(policy) ~= 'table' then return true end
    if Admin.vmenuAce('vMenu.' .. domain .. '.Menu') then return true end
    for action, aliases in pairs(Config.VmenuAcePermissions) do
        if action:sub(1, 8) ~= 'options.' and policy.cortex and policy.cortex[action] then
            for _, ace in ipairs(aliases) do
                if ace:sub(1, #domain + 7) == 'vMenu.' .. domain .. '.' then return true end
            end
        end
    end
    return cortexOnly(domain, Admin.state.allowed or {})
end
function Admin.canChangeVehicleExtras(vehicle)
    if not P.get('vmenu_prevent_extras_when_damaged', false)
        or Admin.vmenuAce('vMenu.VehicleOptions.BypassExtraDamage', 'vehicle.customExtras') then return true end
    return GetVehicleEngineHealth(vehicle) >= P.get('vmenu_allowed_engine_damage_for_extra_change', 800)
        and GetVehicleBodyHealth(vehicle) >= P.get('vmenu_allowed_body_damage_for_extra_change', 800)
end

-- Preview batches share the authoritative model rules, never mint spawn tokens,
-- and only run for a visible menu. Pending results are not denials.
local epoch, cached, queued, worker, inFlight = 0, {}, {}, false, {}
function Admin.invalidateVmenuModels()
    epoch, cached, queued, inFlight = epoch + 1, {}, {}, {}
end
function Admin.vmenuModelAccess(kind, model, action, request)
    if not Admin.state.vmenuPolicy then return true end
    local group = kind .. ':' .. action
    local key = group .. ':' .. tostring(model)
    local entry = cached[key]
    if entry and GetGameTimer() < entry.expires then return entry.allowed end
    if not request then return nil end
    if inFlight[key] ~= nil then return nil end
    queued[group] = queued[group] or { kind = kind, action = action, models = {}, keys = {} }
    local batch = queued[group]
    if not batch.keys[key] and #batch.models < 256 then
        batch.keys[key] = true; batch.models[#batch.models + 1] = model
    end
    if worker then return nil end
    worker = true
    CreateThread(function()
        Wait(0)
        while next(queued) do
            local id, work = next(queued)
            queued[id] = nil
            if Admin.isVmenuModeOpen and not Admin.isVmenuModeOpen() then queued = {}; break end
            local revision = epoch
            for key in pairs(work.keys) do inFlight[key] = revision end
            local ok, result = pcall(Admin.authorizeVmenuModels, work.kind, work.models, work.action, true)
            for key in pairs(work.keys) do if inFlight[key] == revision then inFlight[key] = nil end end
            if revision == epoch then
                for index, name in ipairs(work.models) do
                    local verdict
                    if ok and type(result) == 'table' and result.ok == true and type(result.allowed) == 'table' then
                        verdict = result.allowed[index]
                    end
                    local valid = type(verdict) == 'boolean'
                    cached[id .. ':' .. tostring(name)] = { allowed = verdict,
                        expires = GetGameTimer() + (valid and 10000 or 2000) }
                end
                if Admin.refreshVmenuMode then Admin.refreshVmenuMode() end
            end
        end
        worker = false
    end)
    return nil
end
