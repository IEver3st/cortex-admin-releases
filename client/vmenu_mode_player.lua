-- vMenu mode: Player Options, Weapon Options and Weapon Loadouts, after vMenu
-- 3.8.67 menus/PlayerOptions.cs, WeaponOptions.cs and WeaponLoadouts.cs.
-- Rows run the existing Cortex actions; the few local natives below (blood
-- packs, scenarios at a position, per-weapon tint/ammo, parking) are covered
-- by the Cortex permission for the same feature and rechecked on activation.
local Admin = EsAdmin
local VM = Admin.VmenuMode

local labels = {}
local function label(key)
    local text = labels[key]
    if text == nil then text = GetLabelText(key); labels[key] = text end
    return text
end

local function push(rows, item) if item then rows[#rows + 1] = item end end
local function ped() return PlayerPedId() end
local function invalidInput() VM.notify('error', 'Nothing was entered, or the input was not valid. Try again.') end
local function nameTaken() VM.notify('error', 'A loadout with that name already exists. Choose a different name.') end

-- ---------------------------------------------------------------------------
-- Player Options (PlayerOptions.cs)

local WANTED = { { label = 'No Wanted Level', value = 0 } }
for level = 1, 5 do WANTED[#WANTED + 1] = { label = tostring(level), value = level } end

-- Damage packs, scenarios and their names are generated from GTA V game data
-- (client/game_catalogs.lua).
local CATALOGS = EsAdminGameCatalogs or { scenarios = {}, damagePacks = {}, timecycles = {} }
local BLOOD = CATALOGS.damagePacks

local SCENARIO_NAMES, SCENARIO_CODES = {}, {}
for i, row in ipairs(CATALOGS.scenarios) do SCENARIO_CODES[i], SCENARIO_NAMES[i] = row[1], row[2] end

-- Seated scenarios play at a seat position behind the ped; exercise benches play in place.
local function seated(code) return code:find('SEAT_', 1, true) ~= nil and not code:find('BENCH_PRESS', 1, true) end

local currentScenario

-- Choosing the running scenario again stops it.
local function playScenario(code)
    if VM.denied('player.scenario') then return end
    local p = ped()
    if currentScenario == code then
        currentScenario = nil
        ClearPedTasks(p)
        ClearPedSecondaryTask(p)
        return
    end
    currentScenario = code
    ClearPedTasks(p)
    local canPlay = true
    for _, check in ipairs({
        { IsPedRunning(p), 'Stop running before starting a scenario.' },
        { IsEntityDead(p), 'Scenarios are unavailable while you are dead.' },
        { IsPlayerInCutscene(PlayerId()), 'Scenarios are unavailable during a cutscene.' },
        { IsPedFalling(p), 'Scenarios are unavailable while you are falling.' },
        { IsPedRagdoll(p), 'Scenarios are unavailable while your character is ragdolling.' },
        { not IsPedOnFoot(p), 'Scenarios only play while you are on foot.' },
        { NetworkIsInSpectatorMode(), 'Scenarios are unavailable while spectating.' },
        { GetEntitySpeed(p) > 5.0, 'Slow down before starting a scenario.' },
    }) do
        if check[1] then VM.notify('warning', check[2]); canPlay = false end
    end
    if not canPlay then return end
    if seated(code) then
        local pos = GetOffsetFromEntityInWorldCoords(p, 0.0, -0.5, -0.5)
        TaskStartScenarioAtPosition(p, code, pos.x, pos.y, pos.z, GetEntityHeading(p), -1, true, false)
    else
        VM.execute('player.scenario', { scenario = code })
    end
end

VM.define('player_options', {
    subtitle = 'Player Options',
    build = function()
        local armor = { { label = 'No Armor', value = 0 } }
        for i = 0, 4 do armor[#armor + 1] = { label = label('WT_BA_' .. i), value = (i + 1) * 20 } end
        return {
            VM.action('player.gearUp', 'Gear Up', 'Put on your default saved character and default weapon loadout, then fill your health and heavy armor.'),
            VM.action('player.armor', 'Max Armor', 'Fill your body armor to the maximum.'),
            VM.action('player.revive', 'Revive Player', 'Bring yourself back from death or downed state with full health.'),
            VM.toggle('player.godmode', 'Godmode', 'You take no damage from any source.'),
            VM.toggle('player.invisible', 'Invisible', 'Hide your character from everyone, including your own view.'),
            VM.toggle('player.infiniteStamina', 'Unlimited Stamina', 'Sprint without tiring and without losing health from exhaustion.'),
            VM.toggle('player.fastRun', 'Fast Run', 'Increase your running speed.'),
            VM.toggle('player.fastSwim', 'Fast Swim', 'Increase your swimming speed.'),
            VM.toggle('player.superjump', 'Super Jump', 'Jump much higher than normal.'),
            VM.toggle('player.noRagdoll', 'No Ragdoll', 'Stop your character from ragdolling, so you stay on bikes after crashes.'),
            VM.toggle('player.neverWanted', 'Never Wanted', 'Keep your wanted level at zero at all times.'),
            VM.select('player.setWantedLevel', 'Set Wanted Level', 'Choose a star count and confirm to apply it.',
                { values = WANTED, index = (GetPlayerWantedLevel(PlayerId()) or 0) + 1 }),
            VM.action('player.clearWanted', 'Clear Wanted Level', 'Remove every wanted star at once.'),
            VM.action('player.clearBlood', 'Clear Blood', 'Wipe off blood and damage marks.'),
            VM.can('player.setBloodLevel') and {
                kind = 'list', key = 'player.setBloodLevel', label = 'Set Blood Level', description = 'Apply a blood and damage look.', values = BLOOD,
                onSelect = function(position)
                    if VM.denied('player.setBloodLevel') then return end
                    ApplyPedDamagePack(ped(), BLOOD[position], 100.0, 100.0)
                end,
            } or nil,
            VM.toggle('player.everyoneIgnores', 'Everyone Ignore Player', 'NPCs ignore you and do not react to what you do.'),
            VM.toggle('player.stayInVehicle', 'Stay In Vehicle', 'Angry NPCs cannot pull you out of your vehicle.'),
            VM.action('player.heal', 'Heal Player', 'Restore full health.'),
            VM.select('player.armorType', 'Set Armor Type', 'Choose how much body armor you wear.', { values = armor }),
            VM.action('player.cleanPlayer', 'Clean Player Clothes', 'Remove dirt and stains from your outfit.'),
            VM.action('player.dryPlayer', 'Dry Player Clothes', 'Remove the wet look from your clothes.'),
            VM.action('player.wetPlayer', 'Wet Player Clothes', 'Soak your clothes as if you went swimming.'),
            VM.action('player.suicide', '~r~Commit Suicide', 'End your life on the spot, with a pistol if you carry one, otherwise with a pill.'),
            VM.submenu('player_autopilot', 'Vehicle Auto Pilot Menu', 'Let your character drive the current vehicle for you.'),
            VM.toggle('player.freeze', 'Freeze Player', 'Lock your character in place.'),
            VM.can('player.scenario') and {
                kind = 'list', key = 'player.scenario', label = 'Player Scenarios', values = SCENARIO_NAMES,
                description = 'Choose a scenario and confirm to play it. Picking a different one replaces the current scenario; picking the one already playing stops it.',
                onSelect = function(position) playScenario(SCENARIO_CODES[position]) end,
            } or nil,
            VM.action('player.stopScenario', 'Force Stop Scenario', 'End the current scenario at once, skipping its exit animation.', nil, {
                onSelect = function()
                    if VM.denied('player.stopScenario') then return end
                    currentScenario = nil
                    VM.execute('player.stopScenario')
                end,
            }),
        }
    end,
})

-- Vehicle Auto Pilot ---------------------------------------------------------

local DRIVING_STYLES = { 'Normal', 'Rushed', 'Avoid highways', 'Drive in reverse', 'Custom' }
local STYLE_VALUES = { 443, 575, 536871355, 1467 } -- GetStyleFromIndex; index 5 is the custom flag set
local FLAG_NAMES = { [0] = 'Stop for vehicles', 'Stop for pedestrians', 'Swerve around all vehicles', 'Steer around stationary vehicles',
    'Steer around pedestrians', 'Steer around objects', "Don't steer around Player", 'Stop at lights', 'Go off road when avoiding',
    'Drive into oncoming traffic', 'Drive in reverse', 'Use wander fallback instead of straight line', 'Avoid restricted areas',
    'Prevent background pathfinding', 'Adjust speed for current road', 'Prevent join in road direction when moving',
    "Don't avoid target", 'Target position overrides entity', 'Use shortcut links (Use shortest path)',
    'Change lanes around obstructions', 'Avoid target coords', 'Use switched-off nodes', 'Prefer navmesh route', 'Plane taxi mode',
    'Force straight line', 'Use string pulling at junctions', 'Avoid Adverse Conditions', 'Avoid turns',
    'Extend route with wander results', 'Avoid highways (if possible)', 'Force join in road direction', "Don't terminate task when achieved" }

local autopilot = { index = 1, flags = {}, subtitle = nil }

local function customStyle()
    local style = 0
    for bit = 0, 31 do if autopilot.flags[bit] then style = style | (1 << bit) end end
    if style >= 0x80000000 then style = style - 0x100000000 end -- (int)uint, as vMenu casts it
    return style
end

local function styleFor(index) return STYLE_VALUES[index] or customStyle() end

-- vMenu sets the running drive task's style as well as the one used for new tasks.
local function applyStyle(style)
    Admin.selectAction('player.drivingStyle', style)
    SetDriveTaskDrivingStyle(ped(), style)
end

local function drive(actionId)
    if VM.denied(actionId) then return end
    if VM.can('player.drivingStyle') then Admin.selectAction('player.drivingStyle', styleFor(autopilot.index)) end
    VM.execute(actionId)
end

local function parkAndStop()
    if VM.denied('player.autopilotStop') then return end
    local p = ped()
    if not IsPedInAnyVehicle(p, false) then
        ClearPedTasks(p)
        VM.notify('warning', 'You need to be in a vehicle for this.')
        return
    end
    local vehicle = GetVehiclePedIsIn(p, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) or IsEntityDead(vehicle) then return end
    local coords = GetEntityCoords(p)
    local found, node = GetNthClosestVehicleNode(coords.x, coords.y, coords.z, 3, 0, 0, 0)
    if not found or not node then return end
    VM.notify('info', 'Looking for a spot to park. Driving stops once the vehicle is parked.')
    ClearPedTasks(p)
    TaskVehiclePark(p, vehicle, node.x, node.y, node.z, GetEntityHeading(p), 3, 60.0, true)
    local deadline = GetGameTimer() + 60000 -- vMenu waits forever; a stuck park should not pin this thread.
    while GetGameTimer() < deadline do
        if not DoesEntityExist(vehicle) or GetVehiclePedIsIn(p, false) ~= vehicle then return end
        local pos = GetEntityCoords(p)
        local dx, dy = pos.x - node.x, pos.y - node.y
        if dx * dx + dy * dy <= 3.0 then break end
        Wait(100)
    end
    SetVehicleHalt(vehicle, 3.0, 0, false)
    ClearPedTasks(p)
    VM.notify('info', 'Auto pilot ended. Your character has stopped driving.')
end

VM.define('player_autopilot', {
    title = 'Auto Pilot',
    subtitle = 'Vehicle auto pilot options.',
    build = function()
        return {
            VM.select('player.drivingStyle', 'Driving Style', 'Driving behaviour used by Drive To Waypoint and Drive Around Randomly.', {
                values = DRIVING_STYLES, index = autopilot.index,
                onChange = function(position) autopilot.index = position end,
                onSelect = function(position, value)
                    autopilot.index = position
                    if VM.denied('player.drivingStyle') then return end
                    applyStyle(styleFor(position))
                    VM.notify('info', ('Auto pilot style: %s.'):format(value))
                end,
            }),
            VM.can('player.drivingStyle') and VM.submenu('player_autopilot_style', 'Custom Driving Style',
                "Build your own driving style from individual flags. It only applies while 'Custom' is chosen in the Driving Style list.") or nil,
            VM.action('player.autopilotWaypoint', 'Drive To Waypoint', 'Your character drives the current vehicle to the map waypoint.', nil,
                { onSelect = function() drive('player.autopilotWaypoint') end }),
            VM.action('player.autopilotWander', 'Drive Around Randomly', 'Your character drives the current vehicle around the map with no destination.', nil,
                { onSelect = function() drive('player.autopilotWander') end }),
            VM.action('player.autopilotStop', 'Stop Driving', 'Your character pulls over at a suitable spot, then the driving task ends.', nil,
                { key = 'autopilot.park', onSelect = parkAndStop }),
            VM.action('player.autopilotStop', 'Force Stop Driving', 'End the driving task right away, wherever the vehicle is.'),
        }
    end,
})

VM.define('player_autopilot_style', {
    title = 'Driving Style',
    subtitle = function() return autopilot.subtitle or 'Custom Driving Style' end,
    build = function()
        if not VM.can('player.drivingStyle') then return {} end
        local rows = {}
        for bit = 0, 31 do
            rows[#rows + 1] = {
                kind = 'checkbox', key = 'flag' .. bit, label = FLAG_NAMES[bit] or '~r~Unknown Flag',
                description = 'Include or exclude this behaviour in your custom style.', checked = autopilot.flags[bit] == true,
                onCheck = function(checked)
                    autopilot.flags[bit] = checked or nil
                    local style = customStyle()
                    autopilot.subtitle = ('custom style: %d'):format(style)
                    if autopilot.index ~= 5 then
                        VM.notify('info', "Not applied yet: choose 'Custom' in the Driving Style list first.")
                    elseif not VM.denied('player.drivingStyle') then
                        VM.notify('info', 'Custom style applied.')
                        applyStyle(style)
                    end
                end,
            }
        end
        return rows
    end,
})

-- ---------------------------------------------------------------------------
-- Weapon Options

-- Stock weapons with a vMenu weapon ACE, alphabetical: spawn name, game GXT label key.
local WEAPONS = {
    'weapon_acidpackage', 'WT_ACIDPACKAGE', 'weapon_advancedrifle', 'WT_RIFLE_ADV', 'weapon_appistol', 'WT_PIST_AP',
    'weapon_assaultrifle', 'WT_RIFLE_ASL', 'weapon_assaultrifle_mk2', 'WT_RIFLE_ASL2',
    'weapon_assaultshotgun', 'WT_SG_ASL', 'weapon_assaultsmg', 'WT_SMG_ASL', 'weapon_autoshotgun', 'WT_AUTOSHGN',
    'weapon_ball', 'WT_BALL', 'weapon_bat', 'WT_BAT', 'weapon_battleaxe', 'WT_BATTLEAXE',
    'weapon_battlerifle', 'WT_BATTLERIFLE', 'weapon_bottle', 'WT_BOTTLE', 'weapon_bullpuprifle', 'WT_BULLRIFLE',
    'weapon_bullpuprifle_mk2', 'WT_BULLRIFLE2', 'weapon_bullpupshotgun', 'WT_SG_BLP', 'weapon_bzgas', 'WT_BZGAS',
    'weapon_candycane', 'WT_CANDYCANE', 'weapon_carbinerifle', 'WT_RIFLE_CBN',
    'weapon_carbinerifle_mk2', 'WT_RIFLE_CBN2', 'weapon_ceramicpistol', 'WT_CERPST', 'weapon_combatmg', 'WT_MG_CBT',
    'weapon_combatmg_mk2', 'WT_MG_CBT2', 'weapon_combatpdw', 'WT_COMBATPDW', 'weapon_combatpistol', 'WT_PIST_CBT',
    'weapon_combatshotgun', 'WT_CMBSHGN', 'weapon_compactlauncher', 'WT_CMPGL', 'weapon_compactrifle', 'WT_CMPRIFLE',
    'weapon_crowbar', 'WT_CROWBAR', 'weapon_dagger', 'WT_DAGGER', 'weapon_dbshotgun', 'WT_DBSHGN',
    'weapon_doubleaction', 'WT_REV_DA', 'weapon_emplauncher', 'WT_EMPL', 'weapon_fertilizercan', 'WT_FERTILIZERCAN',
    'weapon_fireextinguisher', 'WT_FIRE', 'weapon_firework', 'WT_FWRKLNCHR', 'weapon_flare', 'WT_FLARE',
    'weapon_flaregun', 'WT_FLAREGUN', 'weapon_flashlight', 'WT_FLASHLIGHT', 'weapon_gadgetpistol', 'WT_GDGTPST',
    'weapon_golfclub', 'WT_GOLFCLUB', 'weapon_grenade', 'WT_GNADE', 'weapon_grenadelauncher', 'WT_GL',
    'weapon_gusenberg', 'WT_GUSENBERG', 'weapon_hackingdevice', 'WT_HACKDEVICE', 'weapon_hammer', 'WT_HAMMER',
    'weapon_hatchet', 'WT_HATCHET', 'weapon_hazardcan', 'WT_HAZARDCAN', 'weapon_heavypistol', 'WT_HEAVYPSTL',
    'weapon_heavyrifle', 'WT_HEAVYRIFLE', 'weapon_heavyshotgun', 'WT_HVYSHOT', 'weapon_heavysniper', 'WT_SNIP_HVY',
    'weapon_heavysniper_mk2', 'WT_SNIP_HVY2', 'weapon_hominglauncher', 'WT_HOMLNCH', 'weapon_knife', 'WT_KNIFE',
    'weapon_knuckle', 'WT_KNUCKLE', 'weapon_machete', 'WT_MACHETE', 'weapon_machinepistol', 'WT_MCHPIST',
    'weapon_marksmanpistol', 'WT_MKPISTOL', 'weapon_marksmanrifle', 'WT_MKRIFLE',
    'weapon_marksmanrifle_mk2', 'WT_MKRIFLE2', 'weapon_mg', 'WT_MG', 'weapon_microsmg', 'WT_SMG_MCR',
    'weapon_militaryrifle', 'WT_MLTRYRFL', 'weapon_minigun', 'WT_MINIGUN', 'weapon_minismg', 'WT_MINISMG',
    'weapon_molotov', 'WT_MOLOTOV', 'weapon_musket', 'WT_MUSKET', 'weapon_navyrevolver', 'WT_REV_NV',
    'weapon_newspaper', 'WT_NEWSPAPER', 'weapon_nightstick', 'WT_NGTSTK', 'weapon_petrolcan', 'WT_PETROL',
    'weapon_pipebomb', 'WT_PIPEBOMB', 'weapon_pistol', 'WT_PIST', 'weapon_pistol50', 'WT_PIST_50',
    'weapon_pistol_mk2', 'WT_PIST2', 'weapon_pistolxm3', 'WT_PISTOLXM3', 'weapon_poolcue', 'WT_POOLCUE',
    'weapon_precisionrifle', 'WT_PRCSRIFLE', 'weapon_proxmine', 'WT_PRXMINE', 'weapon_pumpshotgun', 'WT_SG_PMP',
    'weapon_pumpshotgun_mk2', 'WT_SG_PMP2', 'weapon_railgun', 'WT_RAILGUN', 'weapon_railgunxm3', 'WT_RAILGUNXM3',
    'weapon_raycarbine', 'WT_RAYCARBINE', 'weapon_rayminigun', 'WT_RAYMINIGUN', 'weapon_raypistol', 'WT_RAYPISTOL',
    'weapon_revolver', 'WT_REVOLVER', 'weapon_revolver_mk2', 'WT_REVOLVER2', 'weapon_rpg', 'WT_RPG',
    'weapon_sawnoffshotgun', 'WT_SG_SOF', 'weapon_smg', 'WT_SMG', 'weapon_smg_mk2', 'WT_SMG2',
    'weapon_smokegrenade', 'WT_GNADE_SMK', 'weapon_sniperrifle', 'WT_SNIP_RIF', 'weapon_snowball', 'WT_SNWBALL',
    'weapon_snowlauncher', 'WT_SNOWLNCHR', 'weapon_snspistol', 'WT_SNSPISTOL',
    'weapon_snspistol_mk2', 'WT_SNSPISTOL2', 'weapon_specialcarbine', 'WT_RIFLE_SCBN',
    'weapon_specialcarbine_mk2', 'WT_SPCARBINE2', 'weapon_stickybomb', 'WT_GNADE_STK',
    'weapon_stone_hatchet', 'WT_SHATCHET', 'weapon_stungun', 'WT_STUN', 'weapon_stungun_mp', 'WT_STNGUNMP',
    'weapon_stunrod', 'WT_STUNROD', 'weapon_switchblade', 'WT_SWBLADE', 'weapon_tacticalrifle', 'WT_TACRIFLE',
    'weapon_tecpistol', 'WT_TECPISTOL', 'weapon_vintagepistol', 'WT_VPISTOL', 'weapon_wrench', 'WT_WRENCH'
}

-- Weapon components, alphabetical: component name, game GXT label key.
local COMPONENTS = {
    'COMPONENT_ADVANCEDRIFLE_CLIP_01', 'WCT_CLIP1', 'COMPONENT_ADVANCEDRIFLE_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_ADVANCEDRIFLE_VARMOD_LUXE', 'WCT_VAR_METAL', 'COMPONENT_APPISTOL_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_APPISTOL_CLIP_02', 'WCT_CLIP2', 'COMPONENT_APPISTOL_VARMOD_LUXE', 'WCT_VAR_METAL',
    'COMPONENT_APPISTOL_VARMOD_SECURITY', 'WCT_VAR_STUD', 'COMPONENT_ASSAULTRIFLE_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_ASSAULTRIFLE_CLIP_02', 'WCT_CLIP2', 'COMPONENT_ASSAULTRIFLE_CLIP_03', 'WCT_CLIP_DRM',
    'COMPONENT_ASSAULTRIFLE_MK2_CAMO', 'WCT_CAMO_1', 'COMPONENT_ASSAULTRIFLE_MK2_CAMO_02', 'WCT_CAMO_2',
    'COMPONENT_ASSAULTRIFLE_MK2_CAMO_03', 'WCT_CAMO_3', 'COMPONENT_ASSAULTRIFLE_MK2_CAMO_04', 'WCT_CAMO_4',
    'COMPONENT_ASSAULTRIFLE_MK2_CAMO_05', 'WCT_CAMO_5', 'COMPONENT_ASSAULTRIFLE_MK2_CAMO_06', 'WCT_CAMO_6',
    'COMPONENT_ASSAULTRIFLE_MK2_CAMO_07', 'WCT_CAMO_7', 'COMPONENT_ASSAULTRIFLE_MK2_CAMO_08', 'WCT_CAMO_8',
    'COMPONENT_ASSAULTRIFLE_MK2_CAMO_09', 'WCT_CAMO_9', 'COMPONENT_ASSAULTRIFLE_MK2_CAMO_10', 'WCT_CAMO_10',
    'COMPONENT_ASSAULTRIFLE_MK2_CAMO_IND_01', 'WCT_CAMO_IND', 'COMPONENT_ASSAULTRIFLE_MK2_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_ASSAULTRIFLE_MK2_CLIP_02', 'WCT_CLIP2', 'COMPONENT_ASSAULTRIFLE_MK2_CLIP_ARMORPIERCING', 'WCT_CLIP_AP',
    'COMPONENT_ASSAULTRIFLE_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ',
    'COMPONENT_ASSAULTRIFLE_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC',
    'COMPONENT_ASSAULTRIFLE_MK2_CLIP_TRACER', 'WCT_CLIP_TR', 'COMPONENT_ASSAULTRIFLE_VARMOD_LUXE', 'WCT_VAR_GOLD',
    'COMPONENT_ASSAULTSHOTGUN_CLIP_01', 'WCT_CLIP1', 'COMPONENT_ASSAULTSHOTGUN_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_ASSAULTSMG_CLIP_01', 'WCT_CLIP1', 'COMPONENT_ASSAULTSMG_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_ASSAULTSMG_VARMOD_LOWRIDER', 'WCT_VAR_GOLD', 'COMPONENT_AT_AR_AFGRIP', 'WCT_GRIP',
    'COMPONENT_AT_AR_AFGRIP_02', 'WCT_GRIP', 'COMPONENT_AT_AR_BARREL_01', 'WCT_BARR',
    'COMPONENT_AT_AR_BARREL_02', 'WCT_BARR2', 'COMPONENT_AT_AR_FLSH', 'WCT_FLASH',
    'COMPONENT_AT_AR_FLSH_REH', 'WCT_FLASH', 'COMPONENT_AT_AR_SUPP', 'WCT_SUPP',
    'COMPONENT_AT_AR_SUPP_02', 'WCT_SUPP', 'COMPONENT_AT_BP_BARREL_01', 'WCT_BARR',
    'COMPONENT_AT_BP_BARREL_02', 'WCT_BARR2', 'COMPONENT_AT_CR_BARREL_01', 'WCT_BARR',
    'COMPONENT_AT_CR_BARREL_02', 'WCT_BARR2', 'COMPONENT_AT_MG_BARREL_01', 'WCT_BARR',
    'COMPONENT_AT_MG_BARREL_02', 'WCT_BARR2', 'COMPONENT_AT_MRFL_BARREL_01', 'WCT_BARR',
    'COMPONENT_AT_MRFL_BARREL_02', 'WCT_BARR2', 'COMPONENT_AT_MUZZLE_01', 'WCT_MUZZ1',
    'COMPONENT_AT_MUZZLE_02', 'WCT_MUZZ2', 'COMPONENT_AT_MUZZLE_03', 'WCT_MUZZ3',
    'COMPONENT_AT_MUZZLE_04', 'WCT_MUZZ4', 'COMPONENT_AT_MUZZLE_05', 'WCT_MUZZ5',
    'COMPONENT_AT_MUZZLE_06', 'WCT_MUZZ6', 'COMPONENT_AT_MUZZLE_07', 'WCT_MUZZ7',
    'COMPONENT_AT_MUZZLE_08', 'WCT_MUZZ', 'COMPONENT_AT_MUZZLE_09', 'WCT_MUZZ9', 'COMPONENT_AT_PI_COMP', 'WCT_COMP',
    'COMPONENT_AT_PI_COMP_02', 'WCT_COMP', 'COMPONENT_AT_PI_COMP_03', 'WCT_COMP', 'COMPONENT_AT_PI_FLSH', 'WCT_FLASH',
    'COMPONENT_AT_PI_FLSH_02', 'WCT_FLASH', 'COMPONENT_AT_PI_FLSH_03', 'WCT_FLASH',
    'COMPONENT_AT_PI_RAIL', 'WCT_SCOPE_PI', 'COMPONENT_AT_PI_RAIL_02', 'WCT_SCOPE_PI',
    'COMPONENT_AT_PI_SUPP', 'WCT_SUPP', 'COMPONENT_AT_PI_SUPP_02', 'WCT_SUPP',
    'COMPONENT_AT_SB_BARREL_01', 'WCT_BARR', 'COMPONENT_AT_SB_BARREL_02', 'WCT_BARR2',
    'COMPONENT_AT_SC_BARREL_01', 'WCT_BARR', 'COMPONENT_AT_SC_BARREL_02', 'WCT_BARR2',
    'COMPONENT_AT_SCOPE_LARGE', 'WCT_SCOPE_LRG', 'COMPONENT_AT_SCOPE_LARGE_FIXED_ZOOM', 'WCT_SCOPE_LRG',
    'COMPONENT_AT_SCOPE_LARGE_FIXED_ZOOM_MK2', 'WCT_SCOPE_LRG2', 'COMPONENT_AT_SCOPE_LARGE_MK2', 'WCT_SCOPE_LRG2',
    'COMPONENT_AT_SCOPE_MACRO', 'WCT_SCOPE_MAC', 'COMPONENT_AT_SCOPE_MACRO_02', 'WCT_SCOPE_MAC',
    'COMPONENT_AT_SCOPE_MACRO_02_MK2', 'WCT_SCOPE_MAC2', 'COMPONENT_AT_SCOPE_MACRO_02_SMG_MK2', 'WCT_SCOPE_MAC2',
    'COMPONENT_AT_SCOPE_MACRO_MK2', 'WCT_SCOPE_MAC2', 'COMPONENT_AT_SCOPE_MAX', 'WCT_SCOPE_MAX',
    'COMPONENT_AT_SCOPE_MEDIUM', 'WCT_SCOPE_LRG', 'COMPONENT_AT_SCOPE_MEDIUM_MK2', 'WCT_SCOPE_MED2',
    'COMPONENT_AT_SCOPE_NV', 'WCT_SCOPE_NV', 'COMPONENT_AT_SCOPE_SMALL', 'WCT_SCOPE_SML',
    'COMPONENT_AT_SCOPE_SMALL_02', 'WCT_SCOPE_SML', 'COMPONENT_AT_SCOPE_SMALL_MK2', 'WCT_SCOPE_SML2',
    'COMPONENT_AT_SCOPE_SMALL_SMG_MK2', 'WCT_SCOPE_SML2', 'COMPONENT_AT_SCOPE_THERMAL', 'WCT_SCOPE_TH',
    'COMPONENT_AT_SIGHTS', 'WCT_HOLO', 'COMPONENT_AT_SIGHTS_SMG', 'WCT_HOLO', 'COMPONENT_AT_SR_BARREL_01', 'WCT_BARR',
    'COMPONENT_AT_SR_BARREL_02', 'WCT_BARR2', 'COMPONENT_AT_SR_SUPP', 'WCT_SUPP',
    'COMPONENT_AT_SR_SUPP_03', 'WCT_SUPP', 'COMPONENT_BAT_VARMOD_XM3', 'WCT_BAT_XM3',
    'COMPONENT_BAT_VARMOD_XM3_01', 'WCT_BAT_XM301', 'COMPONENT_BAT_VARMOD_XM3_02', 'WCT_BAT_XM302',
    'COMPONENT_BAT_VARMOD_XM3_03', 'WCT_BAT_XM303', 'COMPONENT_BAT_VARMOD_XM3_04', 'WCT_BAT_XM304',
    'COMPONENT_BAT_VARMOD_XM3_05', 'WCT_BAT_XM305', 'COMPONENT_BAT_VARMOD_XM3_06', 'WCT_BAT_XM306',
    'COMPONENT_BAT_VARMOD_XM3_07', 'WCT_BAT_XM307', 'COMPONENT_BAT_VARMOD_XM3_08', 'WCT_BAT_XM308',
    'COMPONENT_BAT_VARMOD_XM3_09', 'WCT_BAT_XM309', 'COMPONENT_BATTLERIFLE_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_BATTLERIFLE_CLIP_02', 'WCT_CLIP2', 'COMPONENT_BULLPUPRIFLE_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_BULLPUPRIFLE_CLIP_02', 'WCT_CLIP2', 'COMPONENT_BULLPUPRIFLE_MK2_CAMO', 'WCT_CAMO_1',
    'COMPONENT_BULLPUPRIFLE_MK2_CAMO_02', 'WCT_CAMO_2', 'COMPONENT_BULLPUPRIFLE_MK2_CAMO_03', 'WCT_CAMO_3',
    'COMPONENT_BULLPUPRIFLE_MK2_CAMO_04', 'WCT_CAMO_4', 'COMPONENT_BULLPUPRIFLE_MK2_CAMO_05', 'WCT_CAMO_5',
    'COMPONENT_BULLPUPRIFLE_MK2_CAMO_06', 'WCT_CAMO_6', 'COMPONENT_BULLPUPRIFLE_MK2_CAMO_07', 'WCT_CAMO_7',
    'COMPONENT_BULLPUPRIFLE_MK2_CAMO_08', 'WCT_CAMO_8', 'COMPONENT_BULLPUPRIFLE_MK2_CAMO_09', 'WCT_CAMO_9',
    'COMPONENT_BULLPUPRIFLE_MK2_CAMO_10', 'WCT_CAMO_10', 'COMPONENT_BULLPUPRIFLE_MK2_CAMO_IND_01', 'WCT_CAMO_IND',
    'COMPONENT_BULLPUPRIFLE_MK2_CLIP_01', 'WCT_CLIP1', 'COMPONENT_BULLPUPRIFLE_MK2_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_BULLPUPRIFLE_MK2_CLIP_ARMORPIERCING', 'WCT_CLIP_AP',
    'COMPONENT_BULLPUPRIFLE_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ',
    'COMPONENT_BULLPUPRIFLE_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC',
    'COMPONENT_BULLPUPRIFLE_MK2_CLIP_TRACER', 'WCT_CLIP_TR', 'COMPONENT_BULLPUPRIFLE_VARMOD_LOW', 'WCT_VAR_METAL',
    'COMPONENT_CARBINERIFLE_CLIP_01', 'WCT_CLIP1', 'COMPONENT_CARBINERIFLE_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_CARBINERIFLE_CLIP_03', 'WCT_CLIP_DRM', 'COMPONENT_CARBINERIFLE_MK2_CAMO', 'WCT_CAMO_1',
    'COMPONENT_CARBINERIFLE_MK2_CAMO_02', 'WCT_CAMO_2', 'COMPONENT_CARBINERIFLE_MK2_CAMO_03', 'WCT_CAMO_3',
    'COMPONENT_CARBINERIFLE_MK2_CAMO_04', 'WCT_CAMO_4', 'COMPONENT_CARBINERIFLE_MK2_CAMO_05', 'WCT_CAMO_5',
    'COMPONENT_CARBINERIFLE_MK2_CAMO_06', 'WCT_CAMO_6', 'COMPONENT_CARBINERIFLE_MK2_CAMO_07', 'WCT_CAMO_7',
    'COMPONENT_CARBINERIFLE_MK2_CAMO_08', 'WCT_CAMO_8', 'COMPONENT_CARBINERIFLE_MK2_CAMO_09', 'WCT_CAMO_9',
    'COMPONENT_CARBINERIFLE_MK2_CAMO_10', 'WCT_CAMO_10', 'COMPONENT_CARBINERIFLE_MK2_CAMO_IND_01', 'WCT_CAMO_IND',
    'COMPONENT_CARBINERIFLE_MK2_CLIP_01', 'WCT_CLIP1', 'COMPONENT_CARBINERIFLE_MK2_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_CARBINERIFLE_MK2_CLIP_ARMORPIERCING', 'WCT_CLIP_AP',
    'COMPONENT_CARBINERIFLE_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ',
    'COMPONENT_CARBINERIFLE_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC',
    'COMPONENT_CARBINERIFLE_MK2_CLIP_TRACER', 'WCT_CLIP_TR', 'COMPONENT_CARBINERIFLE_VARMOD_LUXE', 'WCT_VAR_GOLD',
    'COMPONENT_CARBINERIFLE_VARMOD_MICH', 'WCT_CRBNMIC_VAR', 'COMPONENT_CERAMICPISTOL_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_CERAMICPISTOL_CLIP_02', 'WCT_CLIP2', 'COMPONENT_CERAMICPISTOL_SUPP', 'WCT_SUPP',
    'COMPONENT_COMBATMG_CLIP_01', 'WCT_CLIP1', 'COMPONENT_COMBATMG_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_COMBATMG_MK2_CAMO', 'WCT_CAMO_1', 'COMPONENT_COMBATMG_MK2_CAMO_02', 'WCT_CAMO_2',
    'COMPONENT_COMBATMG_MK2_CAMO_03', 'WCT_CAMO_3', 'COMPONENT_COMBATMG_MK2_CAMO_04', 'WCT_CAMO_4',
    'COMPONENT_COMBATMG_MK2_CAMO_05', 'WCT_CAMO_5', 'COMPONENT_COMBATMG_MK2_CAMO_06', 'WCT_CAMO_6',
    'COMPONENT_COMBATMG_MK2_CAMO_07', 'WCT_CAMO_7', 'COMPONENT_COMBATMG_MK2_CAMO_08', 'WCT_CAMO_8',
    'COMPONENT_COMBATMG_MK2_CAMO_09', 'WCT_CAMO_9', 'COMPONENT_COMBATMG_MK2_CAMO_10', 'WCT_CAMO_10',
    'COMPONENT_COMBATMG_MK2_CAMO_IND_01', 'WCT_CAMO_IND', 'COMPONENT_COMBATMG_MK2_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_COMBATMG_MK2_CLIP_02', 'WCT_CLIP2', 'COMPONENT_COMBATMG_MK2_CLIP_ARMORPIERCING', 'WCT_CLIP_AP',
    'COMPONENT_COMBATMG_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ', 'COMPONENT_COMBATMG_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC',
    'COMPONENT_COMBATMG_MK2_CLIP_TRACER', 'WCT_CLIP_TR', 'COMPONENT_COMBATPDW_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_COMBATPDW_CLIP_02', 'WCT_CLIP2', 'COMPONENT_COMBATPDW_CLIP_03', 'WCT_CLIP_DRM',
    'COMPONENT_COMBATPISTOL_CLIP_01', 'WCT_CLIP1', 'COMPONENT_COMBATPISTOL_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_COMBATPISTOL_VARMOD_LOWRIDER', 'WCT_VAR_GOLD',
    'COMPONENT_COMBATPISTOL_VARMOD_XMAS23', 'WCT_COMPIST_XM', 'COMPONENT_COMPACTRIFLE_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_COMPACTRIFLE_CLIP_02', 'WCT_CLIP2', 'COMPONENT_COMPACTRIFLE_CLIP_03', 'WCT_CLIP_DRM',
    'COMPONENT_GUSENBERG_CLIP_01', 'WCT_CLIP1', 'COMPONENT_GUSENBERG_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_HEAVYPISTOL_CLIP_01', 'WCT_CLIP1', 'COMPONENT_HEAVYPISTOL_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_HEAVYPISTOL_VARMOD_LUXE', 'WCT_VAR_WOOD', 'COMPONENT_HEAVYRIFLE_CAMO1', 'WCT_VAR_FAM',
    'COMPONENT_HEAVYRIFLE_CLIP_01', 'WCT_CLIP1', 'COMPONENT_HEAVYRIFLE_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_HEAVYRIFLE_SIGHT_01', 'WCT_HVYRFLE_SIG', 'COMPONENT_HEAVYSHOTGUN_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_HEAVYSHOTGUN_CLIP_02', 'WCT_CLIP2', 'COMPONENT_HEAVYSHOTGUN_CLIP_03', 'WCT_CLIP_DRM',
    'COMPONENT_HEAVYSNIPER_MK2_CAMO', 'WCT_CAMO_1', 'COMPONENT_HEAVYSNIPER_MK2_CAMO_02', 'WCT_CAMO_2',
    'COMPONENT_HEAVYSNIPER_MK2_CAMO_03', 'WCT_CAMO_3', 'COMPONENT_HEAVYSNIPER_MK2_CAMO_04', 'WCT_CAMO_4',
    'COMPONENT_HEAVYSNIPER_MK2_CAMO_05', 'WCT_CAMO_5', 'COMPONENT_HEAVYSNIPER_MK2_CAMO_06', 'WCT_CAMO_6',
    'COMPONENT_HEAVYSNIPER_MK2_CAMO_07', 'WCT_CAMO_7', 'COMPONENT_HEAVYSNIPER_MK2_CAMO_08', 'WCT_CAMO_8',
    'COMPONENT_HEAVYSNIPER_MK2_CAMO_09', 'WCT_CAMO_9', 'COMPONENT_HEAVYSNIPER_MK2_CAMO_10', 'WCT_CAMO_10',
    'COMPONENT_HEAVYSNIPER_MK2_CAMO_IND_01', 'WCT_CAMO_IND', 'COMPONENT_HEAVYSNIPER_MK2_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_HEAVYSNIPER_MK2_CLIP_02', 'WCT_CLIP2', 'COMPONENT_HEAVYSNIPER_MK2_CLIP_ARMORPIERCING', 'WCT_CLIP_AP',
    'COMPONENT_HEAVYSNIPER_MK2_CLIP_EXPLOSIVE', 'WCT_CLIP_EX', 'COMPONENT_HEAVYSNIPER_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ',
    'COMPONENT_HEAVYSNIPER_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC', 'COMPONENT_HEAVYSNIPER_VARMOD_XMAS23', 'WCT_HVSP_XM',
    'COMPONENT_KNIFE_VARMOD_XM3', 'WCT_KNIFE_XM3', 'COMPONENT_KNIFE_VARMOD_XM3_01', 'WCT_KNIFE_XM301',
    'COMPONENT_KNIFE_VARMOD_XM3_02', 'WCT_KNIFE_XM302', 'COMPONENT_KNIFE_VARMOD_XM3_03', 'WCT_KNIFE_XM303',
    'COMPONENT_KNIFE_VARMOD_XM3_04', 'WCT_KNIFE_XM304', 'COMPONENT_KNIFE_VARMOD_XM3_05', 'WCT_KNIFE_XM305',
    'COMPONENT_KNIFE_VARMOD_XM3_06', 'WCT_KNIFE_XM306', 'COMPONENT_KNIFE_VARMOD_XM3_07', 'WCT_KNIFE_XM307',
    'COMPONENT_KNIFE_VARMOD_XM3_08', 'WCT_KNIFE_XM308', 'COMPONENT_KNIFE_VARMOD_XM3_09', 'WCT_KNIFE_XM309',
    'COMPONENT_KNUCKLE_VARMOD_BALLAS', 'WCT_KNUCK_BG', 'COMPONENT_KNUCKLE_VARMOD_BASE', 'WCT_KNUCK_01',
    'COMPONENT_KNUCKLE_VARMOD_DIAMOND', 'WCT_KNUCK_DMD', 'COMPONENT_KNUCKLE_VARMOD_DOLLAR', 'WCT_KNUCK_DLR',
    'COMPONENT_KNUCKLE_VARMOD_HATE', 'WCT_KNUCK_HT', 'COMPONENT_KNUCKLE_VARMOD_KING', 'WCT_KNUCK_SLG',
    'COMPONENT_KNUCKLE_VARMOD_LOVE', 'WCT_KNUCK_LV', 'COMPONENT_KNUCKLE_VARMOD_PIMP', 'WCT_KNUCK_02',
    'COMPONENT_KNUCKLE_VARMOD_PLAYER', 'WCT_KNUCK_PC', 'COMPONENT_KNUCKLE_VARMOD_VAGOS', 'WCT_KNUCK_VG',
    'COMPONENT_MACHINEPISTOL_CLIP_01', 'WCT_CLIP1', 'COMPONENT_MACHINEPISTOL_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_MACHINEPISTOL_CLIP_03', 'WCT_CLIP_DRM', 'COMPONENT_MARKSMANRIFLE_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_MARKSMANRIFLE_CLIP_02', 'WCT_CLIP2', 'COMPONENT_MARKSMANRIFLE_MK2_CAMO', 'WCT_CAMO_1',
    'COMPONENT_MARKSMANRIFLE_MK2_CAMO_02', 'WCT_CAMO_2', 'COMPONENT_MARKSMANRIFLE_MK2_CAMO_03', 'WCT_CAMO_3',
    'COMPONENT_MARKSMANRIFLE_MK2_CAMO_04', 'WCT_CAMO_4', 'COMPONENT_MARKSMANRIFLE_MK2_CAMO_05', 'WCT_CAMO_5',
    'COMPONENT_MARKSMANRIFLE_MK2_CAMO_06', 'WCT_CAMO_6', 'COMPONENT_MARKSMANRIFLE_MK2_CAMO_07', 'WCT_CAMO_7',
    'COMPONENT_MARKSMANRIFLE_MK2_CAMO_08', 'WCT_CAMO_8', 'COMPONENT_MARKSMANRIFLE_MK2_CAMO_09', 'WCT_CAMO_9',
    'COMPONENT_MARKSMANRIFLE_MK2_CAMO_10', 'WCT_CAMO_10', 'COMPONENT_MARKSMANRIFLE_MK2_CAMO_IND_01', 'WCT_CAMO_10',
    'COMPONENT_MARKSMANRIFLE_MK2_CLIP_01', 'WCT_CLIP1', 'COMPONENT_MARKSMANRIFLE_MK2_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_MARKSMANRIFLE_MK2_CLIP_ARMORPIERCING', 'WCT_CLIP_AP',
    'COMPONENT_MARKSMANRIFLE_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ',
    'COMPONENT_MARKSMANRIFLE_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC',
    'COMPONENT_MARKSMANRIFLE_MK2_CLIP_TRACER', 'WCT_CLIP_TR', 'COMPONENT_MARKSMANRIFLE_VARMOD_LUXE', 'WCT_VAR_GOLD',
    'COMPONENT_MG_CLIP_01', 'WCT_CLIP1', 'COMPONENT_MG_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_MG_VARMOD_LOWRIDER', 'WCT_VAR_GOLD', 'COMPONENT_MICROSMG_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_MICROSMG_CLIP_02', 'WCT_CLIP2', 'COMPONENT_MICROSMG_VARMOD_FRN', 'WCT_MSMGFRN_VAR',
    'COMPONENT_MICROSMG_VARMOD_LUXE', 'WCT_VAR_GOLD', 'COMPONENT_MICROSMG_VARMOD_SECURITY', 'WCT_VAR_WEED',
    'COMPONENT_MICROSMG_VARMOD_XM3', 'WCT_MSMG_XM3', 'COMPONENT_MILITARYRIFLE_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_MILITARYRIFLE_CLIP_02', 'WCT_CLIP2', 'COMPONENT_MILITARYRIFLE_SIGHT_01', 'WCT_MRFL_SIGHT',
    'COMPONENT_MINISMG_CLIP_01', 'WCT_CLIP1', 'COMPONENT_MINISMG_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_PISTOL50_CLIP_01', 'WCT_CLIP1', 'COMPONENT_PISTOL50_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_PISTOL50_VARMOD_LUXE', 'WCT_VAR_SIL', 'COMPONENT_PISTOL_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_PISTOL_CLIP_02', 'WCT_CLIP2', 'COMPONENT_PISTOL_MK2_CAMO', 'WCT_CAMO_1',
    'COMPONENT_PISTOL_MK2_CAMO_02', 'WCT_CAMO_2', 'COMPONENT_PISTOL_MK2_CAMO_03', 'WCT_CAMO_3',
    'COMPONENT_PISTOL_MK2_CAMO_04', 'WCT_CAMO_4', 'COMPONENT_PISTOL_MK2_CAMO_05', 'WCT_CAMO_5',
    'COMPONENT_PISTOL_MK2_CAMO_06', 'WCT_CAMO_6', 'COMPONENT_PISTOL_MK2_CAMO_07', 'WCT_CAMO_7',
    'COMPONENT_PISTOL_MK2_CAMO_08', 'WCT_CAMO_8', 'COMPONENT_PISTOL_MK2_CAMO_09', 'WCT_CAMO_9',
    'COMPONENT_PISTOL_MK2_CAMO_10', 'WCT_CAMO_10', 'COMPONENT_PISTOL_MK2_CAMO_IND_01', 'WCT_CAMO_IND',
    'COMPONENT_PISTOL_MK2_CLIP_01', 'WCT_CLIP1', 'COMPONENT_PISTOL_MK2_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_PISTOL_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ', 'COMPONENT_PISTOL_MK2_CLIP_HOLLOWPOINT', 'WCT_CLIP_HP',
    'COMPONENT_PISTOL_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC', 'COMPONENT_PISTOL_MK2_CLIP_TRACER', 'WCT_CLIP_TR',
    'COMPONENT_PISTOL_MK2_VARMOD_XM3', 'WCT_PISTMK2_XM3', 'COMPONENT_PISTOL_MK2_VARMOD_XM3_SLIDE', 'WCT_PISTMK2_XM3',
    'COMPONENT_PISTOL_VARMOD_LUXE', 'WCT_VAR_GOLD', 'COMPONENT_PISTOLXM3_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_PISTOLXM3_SUPP', 'WCT_SUPP', 'COMPONENT_PRECISIONRIFLE_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_PUMPSHOTGUN_MK2_CAMO', 'WCT_CAMO_1', 'COMPONENT_PUMPSHOTGUN_MK2_CAMO_02', 'WCT_CAMO_2',
    'COMPONENT_PUMPSHOTGUN_MK2_CAMO_03', 'WCT_CAMO_3', 'COMPONENT_PUMPSHOTGUN_MK2_CAMO_04', 'WCT_CAMO_4',
    'COMPONENT_PUMPSHOTGUN_MK2_CAMO_05', 'WCT_CAMO_5', 'COMPONENT_PUMPSHOTGUN_MK2_CAMO_06', 'WCT_CAMO_6',
    'COMPONENT_PUMPSHOTGUN_MK2_CAMO_07', 'WCT_CAMO_7', 'COMPONENT_PUMPSHOTGUN_MK2_CAMO_08', 'WCT_CAMO_8',
    'COMPONENT_PUMPSHOTGUN_MK2_CAMO_09', 'WCT_CAMO_9', 'COMPONENT_PUMPSHOTGUN_MK2_CAMO_10', 'WCT_CAMO_10',
    'COMPONENT_PUMPSHOTGUN_MK2_CAMO_IND_01', 'WCT_CAMO_IND', 'COMPONENT_PUMPSHOTGUN_MK2_CLIP_01', 'WCT_SHELL',
    'COMPONENT_PUMPSHOTGUN_MK2_CLIP_ARMORPIERCING', 'WCT_SHELL_AP',
    'COMPONENT_PUMPSHOTGUN_MK2_CLIP_EXPLOSIVE', 'WCT_SHELL_EX',
    'COMPONENT_PUMPSHOTGUN_MK2_CLIP_HOLLOWPOINT', 'WCT_SHELL_HP',
    'COMPONENT_PUMPSHOTGUN_MK2_CLIP_INCENDIARY', 'WCT_SHELL_INC',
    'COMPONENT_PUMPSHOTGUN_VARMOD_LOWRIDER', 'WCT_VAR_GOLD', 'COMPONENT_PUMPSHOTGUN_VARMOD_SECURITY', 'WCT_VAR_BONE',
    'COMPONENT_PUMPSHOTGUN_VARMOD_XM3', 'WCT_PUMPSHT_XM3', 'COMPONENT_RAYPISTOL_VARMOD_XMAS18', 'WCT_VAR_RAY18',
    'COMPONENT_REVOLVER_MK2_CAMO', 'WCT_CAMO_1', 'COMPONENT_REVOLVER_MK2_CAMO_02', 'WCT_CAMO_2',
    'COMPONENT_REVOLVER_MK2_CAMO_03', 'WCT_CAMO_3', 'COMPONENT_REVOLVER_MK2_CAMO_04', 'WCT_CAMO_4',
    'COMPONENT_REVOLVER_MK2_CAMO_05', 'WCT_CAMO_5', 'COMPONENT_REVOLVER_MK2_CAMO_06', 'WCT_CAMO_6',
    'COMPONENT_REVOLVER_MK2_CAMO_07', 'WCT_CAMO_7', 'COMPONENT_REVOLVER_MK2_CAMO_08', 'WCT_CAMO_8',
    'COMPONENT_REVOLVER_MK2_CAMO_09', 'WCT_CAMO_9', 'COMPONENT_REVOLVER_MK2_CAMO_10', 'WCT_CAMO_10',
    'COMPONENT_REVOLVER_MK2_CAMO_IND_01', 'WCT_CAMO_IND', 'COMPONENT_REVOLVER_MK2_CLIP_01', 'WCT_CLIP1_RV',
    'COMPONENT_REVOLVER_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ', 'COMPONENT_REVOLVER_MK2_CLIP_HOLLOWPOINT', 'WCT_CLIP_HP',
    'COMPONENT_REVOLVER_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC', 'COMPONENT_REVOLVER_MK2_CLIP_TRACER', 'WCT_CLIP_TR',
    'COMPONENT_REVOLVER_VARMOD_BOSS', 'WCT_REV_VARB', 'COMPONENT_REVOLVER_VARMOD_GOON', 'WCT_REV_VARG',
    'COMPONENT_RPG_VARMOD_TVR', 'WCT_RPGTVR_VAR', 'COMPONENT_SAWNOFFSHOTGUN_VARMOD_LUXE', 'WCT_VAR_METAL',
    'COMPONENT_SMG_CLIP_01', 'WCT_CLIP1', 'COMPONENT_SMG_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_SMG_CLIP_03', 'WCT_CLIP_DRM', 'COMPONENT_SMG_MK2_CAMO', 'WCT_CAMO_1',
    'COMPONENT_SMG_MK2_CAMO_02', 'WCT_CAMO_2', 'COMPONENT_SMG_MK2_CAMO_03', 'WCT_CAMO_3',
    'COMPONENT_SMG_MK2_CAMO_04', 'WCT_CAMO_4', 'COMPONENT_SMG_MK2_CAMO_05', 'WCT_CAMO_5',
    'COMPONENT_SMG_MK2_CAMO_06', 'WCT_CAMO_6', 'COMPONENT_SMG_MK2_CAMO_07', 'WCT_CAMO_7',
    'COMPONENT_SMG_MK2_CAMO_08', 'WCT_CAMO_8', 'COMPONENT_SMG_MK2_CAMO_09', 'WCT_CAMO_9',
    'COMPONENT_SMG_MK2_CAMO_10', 'WCT_CAMO_10', 'COMPONENT_SMG_MK2_CAMO_IND_01', 'WCT_CAMO_IND',
    'COMPONENT_SMG_MK2_CLIP_01', 'WCT_CLIP1', 'COMPONENT_SMG_MK2_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_SMG_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ', 'COMPONENT_SMG_MK2_CLIP_HOLLOWPOINT', 'WCT_CLIP_HP',
    'COMPONENT_SMG_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC', 'COMPONENT_SMG_MK2_CLIP_TRACER', 'WCT_CLIP_TR',
    'COMPONENT_SMG_VARMOD_LUXE', 'WCT_VAR_GOLD', 'COMPONENT_SNIPERRIFLE_VARMOD_LUXE', 'WCT_VAR_WOOD',
    'COMPONENT_SNSPISTOL_CLIP_01', 'WCT_CLIP1', 'COMPONENT_SNSPISTOL_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_SNSPISTOL_MK2_CAMO', 'WCT_CAMO_1', 'COMPONENT_SNSPISTOL_MK2_CAMO_02', 'WCT_CAMO_2',
    'COMPONENT_SNSPISTOL_MK2_CAMO_03', 'WCT_CAMO_3', 'COMPONENT_SNSPISTOL_MK2_CAMO_04', 'WCT_CAMO_4',
    'COMPONENT_SNSPISTOL_MK2_CAMO_05', 'WCT_CAMO_5', 'COMPONENT_SNSPISTOL_MK2_CAMO_06', 'WCT_CAMO_6',
    'COMPONENT_SNSPISTOL_MK2_CAMO_07', 'WCT_CAMO_7', 'COMPONENT_SNSPISTOL_MK2_CAMO_08', 'WCT_CAMO_8',
    'COMPONENT_SNSPISTOL_MK2_CAMO_09', 'WCT_CAMO_9', 'COMPONENT_SNSPISTOL_MK2_CAMO_10', 'WCT_CAMO_10',
    'COMPONENT_SNSPISTOL_MK2_CAMO_IND_01', 'WCT_CAMO_10', 'COMPONENT_SNSPISTOL_MK2_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_SNSPISTOL_MK2_CLIP_02', 'WCT_CLIP2', 'COMPONENT_SNSPISTOL_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ',
    'COMPONENT_SNSPISTOL_MK2_CLIP_HOLLOWPOINT', 'WCT_CLIP_HP',
    'COMPONENT_SNSPISTOL_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC', 'COMPONENT_SNSPISTOL_MK2_CLIP_TRACER', 'WCT_CLIP_TR',
    'COMPONENT_SNSPISTOL_VARMOD_LOWRIDER', 'WCT_VAR_WOOD', 'COMPONENT_SPECIALCARBINE_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_SPECIALCARBINE_CLIP_02', 'WCT_CLIP2', 'COMPONENT_SPECIALCARBINE_CLIP_03', 'WCT_CLIP_DRM',
    'COMPONENT_SPECIALCARBINE_MK2_CAMO', 'WCT_CAMO_1', 'COMPONENT_SPECIALCARBINE_MK2_CAMO_02', 'WCT_CAMO_2',
    'COMPONENT_SPECIALCARBINE_MK2_CAMO_03', 'WCT_CAMO_3', 'COMPONENT_SPECIALCARBINE_MK2_CAMO_04', 'WCT_CAMO_4',
    'COMPONENT_SPECIALCARBINE_MK2_CAMO_05', 'WCT_CAMO_5', 'COMPONENT_SPECIALCARBINE_MK2_CAMO_06', 'WCT_CAMO_6',
    'COMPONENT_SPECIALCARBINE_MK2_CAMO_07', 'WCT_CAMO_7', 'COMPONENT_SPECIALCARBINE_MK2_CAMO_08', 'WCT_CAMO_8',
    'COMPONENT_SPECIALCARBINE_MK2_CAMO_09', 'WCT_CAMO_9', 'COMPONENT_SPECIALCARBINE_MK2_CAMO_10', 'WCT_CAMO_10',
    'COMPONENT_SPECIALCARBINE_MK2_CAMO_IND_01', 'WCT_CAMO_IND', 'COMPONENT_SPECIALCARBINE_MK2_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_SPECIALCARBINE_MK2_CLIP_02', 'WCT_CLIP2',
    'COMPONENT_SPECIALCARBINE_MK2_CLIP_ARMORPIERCING', 'WCT_CLIP_AP',
    'COMPONENT_SPECIALCARBINE_MK2_CLIP_FMJ', 'WCT_CLIP_FMJ',
    'COMPONENT_SPECIALCARBINE_MK2_CLIP_INCENDIARY', 'WCT_CLIP_INC',
    'COMPONENT_SPECIALCARBINE_MK2_CLIP_TRACER', 'WCT_CLIP_TR',
    'COMPONENT_SPECIALCARBINE_VARMOD_LOWRIDER', 'WCT_VAR_ETCHM',
    'COMPONENT_SPECIALCARBINE_VARMOD_XMAS23', 'WCT_SPCR_XM', 'COMPONENT_STUNGUN_VARMOD_BAIL', 'WCT_STNGN_BAIL',
    'COMPONENT_SWITCHBLADE_VARMOD_BASE', 'WCT_SB_BASE', 'COMPONENT_SWITCHBLADE_VARMOD_VAR1', 'WCT_SB_VAR1',
    'COMPONENT_SWITCHBLADE_VARMOD_VAR2', 'WCT_SB_VAR2', 'COMPONENT_TACTICALRIFLE_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_TACTICALRIFLE_CLIP_02', 'WCT_CLIP2', 'COMPONENT_TECPISTOL_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_TECPISTOL_CLIP_02', 'WCT_CLIP2', 'COMPONENT_VINTAGEPISTOL_CLIP_01', 'WCT_CLIP1',
    'COMPONENT_VINTAGEPISTOL_CLIP_02', 'WCT_CLIP2'
}

local TINTS = { 'Black', 'Green', 'Gold', 'Pink', 'Army', 'LSPD', 'Orange', 'Platinum' }
local TINTS_MK2 = { 'Classic Black', 'Classic Gray', 'Classic Two Tone', 'Classic White', 'Classic Beige', 'Classic Green',
    'Classic Blue', 'Classic Earth', 'Classic Brown & Black', 'Red Contrast', 'Blue Contrast', 'Yellow Contrast', 'Orange Contrast',
    'Bold Pink', 'Bold Purple & Yellow', 'Bold Orange', 'Bold Green & Purple', 'Bold Red Features', 'Bold Green Features',
    'Bold Cyan Features', 'Bold Yellow Features', 'Bold Red & White', 'Bold Blue & White', 'Metallic Gold', 'Metallic Platinum',
    'Metallic Gray & Lilac', 'Metallic Purple & Lime', 'Metallic Red', 'Metallic Green', 'Metallic Blue', 'Metallic White & Aqua',
    'Metallic Red & Yellow' }

-- Category submenus in vMenu order with the GetWeapontypeGroup values each one takes.
local CATEGORIES = {
    { id = 'handguns', label = 'Handguns', groups = { 416676503, 690389602 } },
    { id = 'rifles', label = 'Assault Rifles', groups = { 970310034 } },
    { id = 'shotguns', label = 'Shotguns', groups = { 860033945 } },
    { id = 'smgs', label = 'Sub-/Light Machine Guns', groups = { 3337201093, 1159398588 } },
    { id = 'throwables', label = 'Throwables', groups = { 1548507267, 4257178988, 1595662460 } },
    { id = 'melee', label = 'Melee', groups = { 3566412244, 2685387236 } },
    { id = 'heavy', label = 'Heavy Weapons', groups = { 2725924767 } },
    { id = 'snipers', label = 'Sniper Rifles', groups = { 3082541095 } },
}
local CATEGORY_BY_ID, CATEGORY_BY_GROUP = {}, {}
for _, category in ipairs(CATEGORIES) do
    CATEGORY_BY_ID[category.id] = category
    for _, group in ipairs(category.groups) do CATEGORY_BY_GROUP[group] = category.id end
end

-- Any of these makes a weapon's own menu useful, as the weapon ACE does in vMenu.
local WEAPON_ACTIONS = { 'weapons.give', 'weapons.removeWeapon', 'weapons.refillAllAmmo', 'weapons.setTint', 'weapons.attachments' }
local LOCKED_CATEGORY = 'No weapons in this category are available to you on this server.'
-- Centred, highlighted heading above the category submenus.
local SPACER = '~h~' .. string.rep(' ', 19) .. '↓ Weapon Categories ↓'

-- Game data that never changes in a session: resolved once, on first open.
local catalog
local function weaponCatalog()
    if catalog then return catalog end
    catalog = { bySpawn = {}, byCategory = {} }
    for i = 1, #WEAPONS, 2 do
        local spawn = WEAPONS[i]
        local weapon = { spawn = spawn, hash = joaat(spawn), name = label(WEAPONS[i + 1]) }
        catalog.bySpawn[spawn] = weapon
        local id = CATEGORY_BY_GROUP[(GetWeapontypeGroup(weapon.hash) or 0) & 0xFFFFFFFF]
        if id then
            catalog.byCategory[id] = catalog.byCategory[id] or {}
            table.insert(catalog.byCategory[id], weapon)
        end
    end
    return catalog
end

local function importedAddons()
    local imported = type(Admin.getVmenuImportedConfig) == 'function' and Admin.getVmenuImportedConfig() or nil
    local addons = type(imported) == 'table' and type(imported.addons) == 'table' and imported.addons or {}
    return type(addons.weapons) == 'table' and addons.weapons or {}, type(addons.weapon_components) == 'table' and addons.weapon_components or {}
end

local addonCache = {}
local function addonWeapons()
    local list = {}
    if not VM.can('weapons.give') then return list end
    local names = importedAddons()
    for i = 1, math.min(#names, 512) do
        local spawn = type(names[i]) == 'string' and names[i]:lower() or nil
        if spawn and spawn ~= '' and spawn ~= 'weapon_unarmed' then
            addonCache[spawn] = addonCache[spawn] or { spawn = spawn, hash = joaat(spawn), name = label(spawn), addon = true }
            list[#list + 1] = addonCache[spawn]
        end
    end
    return list
end

local function weaponFor(args)
    if type(args) ~= 'table' or type(args.spawn) ~= 'string' then return nil end
    if args.addon then return addonCache[args.spawn] end
    return weaponCatalog().bySpawn[args.spawn]
end

-- Components the weapon takes, labelled; components that share a label are listed once.
local componentCache = {}
local function componentsFor(weapon)
    local list = componentCache[weapon.hash]
    if list then return list end
    list = {}
    local seen = {}
    local function add(model, text)
        if not seen[text] and DoesWeaponTakeWeaponComponent(weapon.hash, joaat(model)) then
            seen[text] = true
            list[#list + 1] = { model = model, label = text }
        end
    end
    for i = 1, #COMPONENTS, 2 do add(COMPONENTS[i], label(COMPONENTS[i + 1])) end
    local _, extra = importedAddons()
    for i = 1, math.min(#extra, 512) do if type(extra[i]) == 'string' then add(extra[i], extra[i]) end end
    componentCache[weapon.hash] = list
    return list
end

local function isMk2(weapon)
    return tostring(weapon.name):find(' Mk II', 1, true) ~= nil or weapon.spawn:upper():find('MK_II', 1, true) ~= nil
        or weapon.spawn:sub(-4) == '_mk2'
end

local function equipOrRemove(weapon)
    local p = ped()
    SetCurrentPedWeapon(p, weapon.hash, true)
    if HasPedGotWeapon(p, weapon.hash, false) then
        VM.execute('weapons.removeWeapon', { weapon = weapon.spawn })
    elseif not VM.denied('weapons.give') then
        Admin.selectAction('weapons.give', weapon.spawn)
    end
end

local function refillWeapon(weapon)
    if VM.denied('weapons.refillAllAmmo') then return end
    local p = ped()
    SetCurrentPedWeapon(p, weapon.hash, true)
    if not HasPedGotWeapon(p, weapon.hash, false) then
        VM.notify('error', 'You need this weapon before you can refill its ammo.')
        return
    end
    local ok, ammo = GetMaxAmmo(p, weapon.hash)
    SetPedAmmo(p, weapon.hash, ok and ammo or 900)
end

local function tintWeapon(weapon, tint)
    if VM.denied('weapons.setTint') then return end
    local p = ped()
    if HasPedGotWeapon(p, weapon.hash, false) then
        SetPedWeaponTintIndex(p, weapon.hash, tint)
    else
        VM.notify('error', 'Get this weapon before changing its tint.')
    end
end

local function toggleComponent(weapon, model)
    if VM.denied('weapons.attachments') then return end
    local p = ped()
    SetCurrentPedWeapon(p, weapon.hash, true)
    if not HasPedGotWeapon(p, weapon.hash, false) then
        VM.notify('error', 'Get this weapon before changing its attachments.')
        return
    end
    Admin.toggleWeaponAttachment(model)
end

VM.define('weapon_options_weapon', {
    title = 'Weapon Options',
    stats = function(args) local weapon = weaponFor(args); return weapon and VM.weaponStats and VM.weaponStats(weapon.spawn) end,
    subtitle = function(args) local weapon = weaponFor(args); return weapon and weapon.name or '' end,
    build = function(args)
        local weapon = weaponFor(args)
        local rows = {}
        if not weapon or not VM.canAny(WEAPON_ACTIONS) then return rows end
        local canGive = VM.can('weapons.give')
        rows[#rows + 1] = {
            key = 'equip', label = 'Equip/Remove Weapon', icon = canGive and 'gun' or 'lock', enabled = canGive,
            description = canGive and 'Give yourself this weapon, or take it away if you already have it.' or 'Your permissions do not include this option.',
            onSelect = function() equipOrRemove(weapon) end,
        }
        push(rows, VM.can('weapons.refillAllAmmo') and {
            key = 'refill', label = 'Re-fill Ammo', description = 'Fill this weapon to its maximum ammo.', icon = 'ammo',
            onSelect = function() refillWeapon(weapon) end,
        } or nil)
        push(rows, VM.can('weapons.setTint') and {
            kind = 'list', key = 'tint', label = 'Tints', description = 'Pick a paint finish for this weapon.',
            values = isMk2(weapon) and TINTS_MK2 or TINTS,
            onChange = function(position) tintWeapon(weapon, position - 1) end,
        } or nil)
        if VM.can('weapons.attachments') then
            for _, component in ipairs(componentsFor(weapon)) do
                rows[#rows + 1] = {
                    key = 'component:' .. component.model, label = component.label, description = 'Attach this part, or detach it if it is already fitted.',
                    onSelect = function() toggleComponent(weapon, component.model) end,
                }
            end
        end
        return rows
    end,
})

local function weaponRow(weapon)
    return VM.modelRow(VM.submenu('weapon_options_weapon', weapon.name, ('Ammo, tint and attachments for ~y~%s~s~.'):format(weapon.name),
        { key = (weapon.addon and 'addon:' or '') .. weapon.spawn, spawn = weapon.spawn, addon = weapon.addon },
        { key = weapon.spawn, icon = 'gun', hideEmpty = false, stats = function() return VM.weaponStats and VM.weaponStats(weapon.spawn) end }), 'weapon', weapon.spawn, 'weapons.give')
end

VM.define('weapon_options_category', {
    title = 'Weapons',
    subtitle = function(args) local category = CATEGORY_BY_ID[args and args.key]; return category and category.label or '' end,
    build = function(args)
        local rows = {}
        if not VM.canAny(WEAPON_ACTIONS) then return rows end
        for _, weapon in ipairs(weaponCatalog().byCategory[args and args.key] or {}) do rows[#rows + 1] = weaponRow(weapon) end
        return rows
    end,
})

VM.define('weapon_options_addons', {
    title = 'Addon Weapons',
    subtitle = 'Equip/Remove Addon Weapons',
    build = function()
        local rows = {}
        for _, weapon in ipairs(addonWeapons()) do rows[#rows + 1] = weaponRow(weapon) end
        return rows
    end,
})

-- Parachute Options ------------------------------------------------------------

local CHUTES = { 'PM_TINT0', 'PM_TINT1', 'PM_TINT2', 'PM_TINT3', 'PM_TINT4', 'PM_TINT5', 'PM_TINT6', 'PM_TINT7',
    'PS_CAN_0', 'PS_CAN_1', 'PS_CAN_2', 'PS_CAN_3', 'PS_CAN_4', 'PS_CAN_5' }
local CHUTE_DESCRIPTIONS = { 'PD_TINT0', 'PD_TINT1', 'PD_TINT2', 'PD_TINT3', 'PD_TINT4', 'PD_TINT5', 'PD_TINT6', 'PD_TINT7',
    'PSD_CAN_0', 'PSD_CAN_1', 'PSD_CAN_2', 'PSD_CAN_3', 'PSD_CAN_4', 'PSD_CAN_5' }
local SMOKE = { { 'PM_TINT8', 'off' }, { 'PM_TINT9', '255,0,0' }, { 'PM_TINT10', '255,165,0' }, { 'PM_TINT11', '255,255,0' },
    { 'PM_TINT12', '0,0,255' }, { 'PM_TINT13', '20,20,20' } }
local chuteIndex = {}
local smokeSwitching = false

local function chuteDescription(index)
    local text = label(CHUTE_DESCRIPTIONS[index] or CHUTE_DESCRIPTIONS[1])
    if index > 8 then text = text .. ' ~r~Known not to work in FiveM.' end
    return text
end

-- vMenu applies chute styles on scroll and on select.
local function chuteRow(actionId, text, prefix)
    local values = {}
    for i, key in ipairs(CHUTES) do values[i] = { label = label(key), value = i - 1 } end
    local function apply(position)
        chuteIndex[actionId] = position
        if VM.denied(actionId) then return end
        Admin.selectAction(actionId, position - 1)
    end
    return VM.select(actionId, text, function() return prefix .. chuteDescription(chuteIndex[actionId] or 1) end,
        { values = values, index = chuteIndex[actionId] or 1, onChange = apply, onSelect = apply })
end

-- Changing the colour takes four seconds with the trail off, as in vMenu.
local function selectSmoke(position)
    if smokeSwitching or VM.denied('weapons.parachuteSmoke') then return end
    smokeSwitching = true
    Admin.selectAction('weapons.parachuteSmoke', 'off')
    Wait(4000)
    if position > 1 and not VM.denied('weapons.parachuteSmoke') then Admin.selectAction('weapons.parachuteSmoke', SMOKE[position][2]) end
    smokeSwitching = false
end

VM.define('weapon_parachute', {
    title = 'Parachute Options',
    subtitle = 'Parachute Options',
    build = function()
        local smoke = {}
        for i, entry in ipairs(SMOKE) do smoke[i] = { label = label(entry[1]), value = entry[2] } end
        return {
            VM.action('weapons.primaryParachute', 'Toggle Primary Parachute', 'Put the main parachute on, or take it off.'),
            VM.action('weapons.reserveParachute', 'Enable Reserve Parachute', 'Add a reserve parachute. Needs the primary parachute first, and cannot be taken off once added.'),
            VM.toggle('weapons.autoEquipParachute', 'Auto Equip Parachutes', 'Give yourself a primary and reserve parachute whenever you get into a plane or helicopter.'),
            VM.toggle('weapons.unlimitedParachutes', 'Unlimited Parachutes', 'Never run out of primary or reserve parachutes.'),
            VM.select('weapons.parachuteSmoke', 'Smoke Trail Color', 'Pick a trail colour and confirm. The switch takes 4 seconds, during which the smoke is unavailable.',
                { values = smoke, onSelect = selectSmoke }),
            chuteRow('weapons.primaryChuteStyle', 'Primary Chute Style', 'Main canopy: '),
            chuteRow('weapons.reserveChuteStyle', 'Reserve Chute Style', 'Reserve canopy: '),
        }
    end,
})

-- Weapon Options menu ------------------------------------------------------------

local function setAllAmmo()
    if VM.denied('weapons.setAllAmmo') then return end
    local input = VM.input('Ammo for every weapon', '100', 30)
    if not input or input == '' then invalidInput(); return end
    if not input:match('^%-?%d+$') then VM.notify('error', 'That is not a whole number.'); return end
    VM.execute('weapons.setAllAmmo', { ammo = input })
end

local function setAmmo()
    if VM.denied('weapons.setAmmo') then return end
    local input = VM.input('Ammo for the weapon in your hands', '250', 30)
    if not input or input == '' then invalidInput(); return end
    if not input:match('^%d+$') then VM.notify('error', 'That is not a whole number.'); return end
    VM.execute('weapons.setAmmo', { ammo = input })
end

local function spawnByName()
    if VM.denied('weapons.giveCustom') then return end
    local input = VM.input('Weapon spawn name, such as weapon_pistol', nil, 30)
    if not input or input == '' then invalidInput(); return end
    VM.execute('weapons.giveCustom', { weapon = input })
end

VM.define('weapon_options', {
    subtitle = 'Weapon Options',
    build = function()
        local rows = {}
        push(rows, VM.action('weapons.giveAll', 'Get All Weapons', 'Give yourself every weapon.'))
        push(rows, VM.action('weapons.removeAll', 'Remove All Weapons', 'Take every weapon out of your inventory.'))
        push(rows, VM.toggle('weapons.infiniteAmmo', 'Unlimited Ammo', 'Your ammo never runs out.'))
        push(rows, VM.toggle('weapons.noReload', 'No Reload', 'Magazines stay full while you fire.'))
        push(rows, VM.toggle('weapons.explosiveAmmo', 'Explosive Ammo', 'Your bullets explode where they land.'))
        push(rows, VM.toggle('weapons.fireAmmo', 'Incendiary Ammo', 'Your bullets set what they hit on fire.'))
        push(rows, VM.toggle('weapons.gravityGun', 'Gravity Gun (Beta)', 'Aim at a vehicle, prop or NPC and fire to lift it. Fire again to throw it, stop aiming to drop it, scroll to change the distance.'))
        push(rows, VM.action('weapons.setAmmo', 'Set Current Weapon Ammo', 'Choose an ammo count for the weapon in your hands.', nil, { onSelect = setAmmo }))
        push(rows, VM.action('weapons.setAllAmmo', 'Set All Ammo Count', 'Choose one ammo count and apply it to every weapon you carry.', nil, { onSelect = setAllAmmo }))
        push(rows, VM.action('weapons.refillAllAmmo', 'Refill All Ammo', 'Fill every weapon you carry to its maximum ammo.'))
        push(rows, VM.action('weapons.giveCustom', 'Spawn Weapon By Name', 'Type a weapon spawn name to give yourself that weapon.', nil, { onSelect = spawnByName }))
        local weaponMenus = VM.canAny(WEAPON_ACTIONS)
        if weaponMenus then
            local hasAddons = #addonWeapons() > 0
            rows[#rows + 1] = VM.submenu('weapon_options_addons', 'Addon Weapons', hasAddons and 'Give or remove the extra weapons this server has added.'
                or 'Not available: you lack permission, or the server has no addon weapons configured.',
                nil, { hideEmpty = false, enabled = hasAddons, icon = not hasAddons and 'lock' or nil })
        end
        push(rows, VM.submenu('weapon_parachute', 'Parachute Options', 'Parachute, reserve, smoke trail and canopy settings.'))
        if weaponMenus then
            rows[#rows + 1] = { key = 'spacer', label = SPACER, description = '', enabled = false }
            local byCategory = weaponCatalog().byCategory
            for _, category in ipairs(CATEGORIES) do
                local empty = not byCategory[category.id]
                rows[#rows + 1] = VM.submenu('weapon_options_category', category.label, empty and LOCKED_CATEGORY or nil, { key = category.id },
                    { hideEmpty = false, enabled = not empty, icon = empty and 'lock' or nil })
            end
        end
        return rows
    end,
})

-- ---------------------------------------------------------------------------
-- Weapon Loadouts (WeaponLoadouts.cs). Saved loadouts are read when a loadout
-- menu opens and after each change, as vMenu refreshes its list on open.

local LOADOUT_MANAGE = { 'weapons.loadLoadout', 'weapons.renameLoadout', 'weapons.cloneLoadout', 'weapons.defaultLoadout',
    'weapons.replaceLoadout', 'weapons.deleteLoadout' }
local loadouts = { names = {}, set = {}, default = nil }

local function refreshLoadouts()
    local raw = type(loadWeaponLoadoutsRaw) == 'function' and loadWeaponLoadoutsRaw() or {}
    local names, set = {}, {}
    for name, value in pairs(type(raw) == 'table' and raw or {}) do
        if type(name) == 'string' and type(value) == 'table' then names[#names + 1] = name; set[name] = true end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    loadouts.names, loadouts.set = names, set
    local ok, preferences = pcall(json.decode, GetResourceKvpString(Config.KvpKeys.vmenuPreferences) or '')
    loadouts.default = ok and type(preferences) == 'table' and preferences.defaultLoadout or nil
end

local function saveLoadout()
    if VM.denied('weapons.saveLoadout') then return end
    local name = VM.input('Loadout name', nil, 30)
    if not name or name == '' then invalidInput(); return end
    refreshLoadouts()
    if loadouts.set[name] then nameTaken(); return end
    VM.execute('weapons.saveLoadout', { name = name })
    refreshLoadouts()
end

local function renameOrClone(name, actionId)
    if VM.denied(actionId) then return end
    local newName = VM.input('Loadout name', name, 30)
    if not newName or newName == '' then invalidInput(); return end
    refreshLoadouts()
    if loadouts.set[newName] then nameTaken(); return end
    local ok = VM.execute(actionId, { from = name, to = newName })
    refreshLoadouts()
    if ok == true then VM.back() end
end

VM.define('weapon_loadouts', {
    subtitle = 'weapon loadouts management',
    onOpen = refreshLoadouts,
    build = function()
        return {
            VM.action('weapons.saveLoadout', 'Save Loadout', 'Store the weapons you carry now as a new loadout.', nil, { onSelect = saveLoadout }),
            VM.canAny(LOADOUT_MANAGE) and VM.submenu('weapon_loadouts_saved', 'Manage Loadouts', 'Browse, equip and edit your saved loadouts.', nil, { hideEmpty = false }) or nil,
            VM.toggle('weapons.restoreLoadoutOnRespawn', 'Restore Default Loadout On Respawn', 'Equip your default loadout automatically each time you spawn or respawn. Needs a default loadout to be set.'),
        }
    end,
})

VM.define('weapon_loadouts_saved', {
    title = 'Saved Loadouts',
    subtitle = 'saved weapon loadouts list',
    onOpen = refreshLoadouts,
    build = function()
        local rows = {}
        if not VM.canAny(LOADOUT_MANAGE) then return rows end
        for _, name in ipairs(loadouts.names) do
            rows[#rows + 1] = VM.submenu('weapon_loadout', name, 'Equip, rename, copy or delete this loadout.', { key = name, name = name }, { hideEmpty = false })
        end
        return rows
    end,
})

VM.define('weapon_loadout', {
    title = 'Mange Loadout',
    subtitle = 'Manage saved weapon loadout',
    onOpen = refreshLoadouts,
    build = function(args)
        local name = type(args) == 'table' and args.name or nil
        if type(name) ~= 'string' then return {} end
        return {
            VM.action('weapons.loadLoadout', 'Equip Loadout', 'Swap your current weapons for the ones saved in this loadout. Weapons you carry now are removed.', { name = name }),
            VM.action('weapons.renameLoadout', 'Rename Loadout', 'Give this loadout a new name.', nil,
                { onSelect = function() renameOrClone(name, 'weapons.renameLoadout') end }),
            VM.action('weapons.cloneLoadout', 'Clone Loadout', 'Copy this loadout under a new name.', nil,
                { onSelect = function() renameOrClone(name, 'weapons.cloneLoadout') end }),
            VM.action('weapons.defaultLoadout', 'Set As Default Loadout', "Use this loadout every time you spawn or respawn. It takes priority over 'Restore Weapons' in Misc Settings. Turn it on or off from the main Weapon Loadouts menu.", nil, {
                icon = loadouts.default == name and 'tick' or nil,
                onSelect = function()
                    if VM.execute('weapons.defaultLoadout', { name = name }) == true then loadouts.default = name end
                end,
            }),
            VM.action('weapons.replaceLoadout', '~r~Replace Loadout', '~r~Overwrite this loadout with the weapons you carry now. This cannot be undone.', { name = name }, { confirm = true }),
            VM.action('weapons.deleteLoadout', '~r~Delete Loadout', '~r~Permanently delete this loadout. This cannot be undone.', nil, {
                confirm = true,
                onSelect = function()
                    local ok = VM.execute('weapons.deleteLoadout', { name = name })
                    refreshLoadouts()
                    if ok == true then VM.back() end
                end,
            }),
        }
    end,
})
