-- Specialist kits and the statement families built from the same pieces.
-- Drawables are official global indexes resolved to their collection at
-- runtime, exactly like shared/appearance_catalog.lua. Torsos come from the
-- pinned v-besttorso data; texture names come from the generated
-- shared/appearance_textures.lua.
--
-- Names:   Colbss/FiveM-ClothingData @ 6178655616ea88e3e2bf191b32bc4878b9c3b5eb
-- Torsos:  root-cause/v-besttorso     @ a2eba9f862baf7c6da34a4b5d1bd36a4abbf8e03
-- Reviewed: 2026-10-05. The Gunrunning camo line shares one texture order
-- across shirts, cargos, cross trainers, caps and helmets, so pattern matching
-- keeps a kit in one camo. The Doomsday scuba set is unlabeled upstream; its
-- suit, legs, fins and tank share 26 textures and are matched by index.
-- In-game fit validation remains user-run.

AppearanceKits = AppearanceKits or {}

-- linked components take the focal texture index, for tanks and gloves that
-- are authored as a set with their top.
local function upper(id, drawable, torso, kind, name, extra)
    extra = extra or {}
    return { id = id, category = 'tops', drawable = drawable, torso = torso, kind = kind, name = name,
        undershirt = extra.undershirt, linked = extra.linked }
end

local function lower(id, drawable, kind, name)
    return { id = id, category = 'bottoms', drawable = drawable, kind = kind, name = name }
end

local function feet(id, drawable, kind, name)
    return { id = id, category = 'shoes', drawable = drawable, kind = kind, name = name }
end

local function mask(id, drawable, name)
    return { id = id, category = 'gear', component = 1, drawable = drawable, name = name }
end

-- base = true keeps a base-game prop on its stable collection-local index.
local function hat(id, drawable, name, base)
    return { id = id, category = 'headgear', prop = 0, drawable = drawable, name = name, base = base == true }
end

local function eyes(id, drawable, name)
    return { id = id, category = 'eyewear', prop = 1, drawable = drawable, name = name }
end

AppearanceKits.male = {
    -- Gunrunning camo line
    upper('army_tee', 208, 0, 'tee', 'Army T-shirt'),
    upper('army_rolled_tee', 239, 2, 'tee', 'Army rolled tee'),
    upper('army_sleeveless_shirt', 219, 2, 'shirt', 'Army sleeveless shirt'),
    upper('army_combat_shirt', 220, 4, 'shirt', 'Army combat shirt'),
    upper('army_service_shirt', 221, 4, 'shirt', 'Army service shirt'),
    upper('army_defender_vest', 213, 113, 'jacket', 'Defender vest'),
    upper('army_collared_parka', 209, 4, 'jacket', 'Army collared parka'),
    upper('army_closed_parka', 210, 6, 'jacket', 'Army closed parka'),
    upper('army_open_parka', 212, 4, 'jacket', 'Army open parka'),
    upper('field_closed', 232, 14, 'jacket', 'Closed field jacket'),
    upper('field_open', 233, 14, 'jacket', 'Open field jacket'),
    lower('army_cargo', 86, 'cargo', 'Army cargo'),
    lower('army_cargo_bloused', 87, 'cargo', 'Army cargo'),
    lower('army_cargo_shorts', 88, 'shorts', 'Army cargo shorts'),
    feet('army_cross_trainers', 59, 'sneakers', 'Army cross trainers'),
    feet('army_tactical_boots', 62, 'boots', 'Tactical boots'),
    feet('army_tactical_boots_tucked', 63, 'boots', 'Tactical boots'),
    feet('tech_boots', 60, 'boots', 'Tech boots'),
    feet('tech_boots_tucked', 61, 'boots', 'Tech boots'),
    hat('army_cap', 103, 'Army cap'),
    hat('boonie_down', 104, 'Boonie hat'),
    hat('boonie_up', 105, 'Boonie hat'),
    hat('army_beret', 106, 'Beret'),
    hat('combat_helmet', 112, 'Combat helmet'),

    -- Heist and Doomsday tactical gear
    upper('tactical_blouson', 244, 14, 'jacket', 'Tactical blouson'),
    upper('tactical_sleeveless', 247, 114, 'jacket', 'Tactical sleeveless'),
    upper('tactical_midlength', 248, 6, 'jacket', 'Tactical midlength'),
    upper('battle_vest', 53, 4, 'jacket', 'Battle vest'),
    upper('combat_top', 49, 4, 'tee', 'Combat top'),
    upper('combat_sweater', 50, 4, 'knit', 'Combat sweater'),
    lower('combat_pants', 31, 'cargo', 'Combat pants'),
    lower('battle_pants', 34, 'cargo', 'Battle pants'),
    feet('black_tactical_boots', 25, 'boots', 'Black tactical boots'),
    mask('tactical_ski_mask', 104, 'Tactical ski mask'),
    eyes('tactical_goggles', 41, 'Tactical goggles'),
    hat('night_vision', 147, 'Scope night vision'),

    -- Doomsday scuba set
    upper('wetsuit', 243, 4, 'jacket', 'Wetsuit', { undershirt = 123, linked = { 8 } }),
    lower('wetsuit_legs', 94, 'trousers', 'Wetsuit legs'),
    feet('dive_fins', 67, 'open', 'Dive fins'),
    mask('scuba_mask', 122, 'Scuba mask'),
    mask('rebreather', 36, 'Rebreather'),

    -- Pilot School and Smuggler's Run flight gear
    upper('flight_jacket', 48, 4, 'jacket', 'Flight jacket'),
    upper('flight_bomber_closed', 229, 4, 'jacket', 'Closed flight jacket'),
    upper('flight_bomber_open', 230, 4, 'jacket', 'Open flight jacket'),
    lower('flight_suit_pants', 30, 'cargo', 'Flight pants'),
    feet('flight_boots', 24, 'boots', 'Flight boots'),
    mask('goggles_flight_cap', 109, 'Goggles flight cap'),
    hat('flight_helmet', 38, 'Flight helmet'),
    hat('race_flight_helmet', 111, 'Flight helmet'),

    -- Cold weather
    upper('collared_puffer', 224, 12, 'jacket', 'Collared puffer'),
    upper('tuner_puffer', 370, 12, 'jacket', 'Puffer'),
    upper('bigness_puffer', 191, 1, 'jacket', 'Bigness puffer'),
    upper('closed_parka', 188, 6, 'jacket', 'Closed parka'),
    upper('open_parka', 189, 4, 'jacket', 'Open parka'),
    eyes('ski_goggles', 25, 'Urban ski goggles'),
    hat('winter_beanie', 2, 'Winter hat', true),
    hat('saggy_beanie', 5, 'Saggy beanie', true),

    -- Cunning Stunts motocross
    upper('motocross_jersey', 152, 111, 'jacket', 'Motocross jersey', { linked = { 3 } }),
    hat('stunt_helmet', 67, 'Stunt helmet'),
    hat('stunt_helmet_visor', 82, 'Stunt helmet'),
}

AppearanceKits.female = {
    upper('army_tee', 212, 14, 'tee', 'Army T-shirt'),
    upper('army_rolled_tee', 225, 12, 'tee', 'Army rolled tee'),
    upper('army_sleeveless_shirt', 229, 11, 'shirt', 'Army sleeveless shirt'),
    upper('army_combat_shirt', 230, 3, 'shirt', 'Army combat shirt'),
    upper('army_service_shirt', 231, 3, 'shirt', 'Army service shirt'),
    upper('army_defender_vest', 217, 130, 'jacket', 'Defender vest'),
    upper('army_collared_parka', 213, 3, 'jacket', 'Army collared parka'),
    upper('army_closed_parka', 214, 3, 'jacket', 'Army closed parka'),
    upper('army_open_parka', 216, 5, 'jacket', 'Army open parka'),
    upper('field_closed', 242, 6, 'jacket', 'Closed field jacket'),
    upper('field_open', 243, 6, 'jacket', 'Open field jacket'),
    lower('army_cargo', 89, 'cargo', 'Army cargo'),
    lower('army_cargo_bloused', 90, 'cargo', 'Army cargo'),
    lower('army_cargo_shorts', 91, 'shorts', 'Army cargo shorts'),
    feet('army_cross_trainers', 62, 'sneakers', 'Army cross trainers'),
    feet('army_tactical_boots', 65, 'boots', 'Tactical boots'),
    feet('army_tactical_boots_tucked', 66, 'boots', 'Tactical boots'),
    feet('tech_boots', 63, 'boots', 'Tech boots'),
    feet('tech_boots_tucked', 64, 'boots', 'Tech boots'),
    hat('army_cap', 102, 'Army cap'),
    hat('boonie_down', 103, 'Boonie hat'),
    hat('boonie_up', 104, 'Boonie hat'),
    hat('army_beret', 105, 'Beret'),
    hat('combat_helmet', 111, 'Combat helmet'),

    upper('tactical_blouson', 252, 5, 'jacket', 'Tactical blouson'),
    upper('tactical_sleeveless', 255, 131, 'jacket', 'Tactical sleeveless'),
    upper('tactical_midlength', 256, 9, 'jacket', 'Tactical midlength'),
    upper('battle_vest', 46, 3, 'jacket', 'Battle vest'),
    upper('combat_top', 42, 3, 'tee', 'Combat top'),
    upper('combat_sweater', 43, 3, 'knit', 'Combat sweater'),
    lower('combat_pants', 30, 'cargo', 'Combat pants'),
    lower('battle_pants', 33, 'cargo', 'Battle pants'),
    feet('black_tactical_boots', 25, 'boots', 'Black tactical boots'),
    mask('tactical_ski_mask', 104, 'Tactical ski mask'),
    eyes('tactical_goggles', 43, 'Tactical goggles'),
    hat('night_vision', 146, 'Scope night vision'),

    upper('wetsuit', 251, 3, 'jacket', 'Wetsuit', { undershirt = 153, linked = { 8 } }),
    lower('wetsuit_legs', 97, 'trousers', 'Wetsuit legs'),
    feet('dive_fins', 70, 'open', 'Dive fins'),
    mask('scuba_mask', 122, 'Scuba mask'),
    mask('rebreather', 36, 'Rebreather'),

    upper('flight_jacket', 41, 3, 'jacket', 'Flight jacket'),
    upper('flight_bomber_closed', 239, 3, 'jacket', 'Closed flight jacket'),
    upper('flight_bomber_open', 240, 5, 'jacket', 'Open flight jacket'),
    lower('flight_suit_pants', 29, 'cargo', 'Flight pants'),
    feet('flight_boots', 24, 'boots', 'Flight boots'),
    mask('goggles_flight_cap', 109, 'Goggles flight cap'),
    hat('flight_helmet', 37, 'Flight helmet'),
    hat('race_flight_helmet', 110, 'Flight helmet'),

    upper('collared_puffer', 234, 6, 'jacket', 'Collared puffer'),
    upper('tuner_puffer', 389, 6, 'jacket', 'Puffer'),
    upper('bigness_puffer', 193, 5, 'jacket', 'Bigness puffer'),
    upper('closed_parka', 190, 3, 'jacket', 'Closed parka'),
    upper('open_parka', 191, 5, 'jacket', 'Open parka'),
    eyes('ski_goggles', 27, 'Urban ski goggles'),
    hat('winter_beanie', 5, 'Beanie', true),
    hat('saggy_beanie', 12, 'Saggy beanie', true),

    upper('motocross_jersey', 149, 128, 'jacket', 'Motocross jersey', { linked = { 3 } }),
    hat('stunt_helmet', 66, 'Stunt helmet'),
    hat('stunt_helmet_visor', 81, 'Stunt helmet'),
}

local function kit(category, ...)
    local ids = {}
    for index, id in ipairs({ ... }) do ids[index] = ('kit_%s_%s'):format(category, id) end
    return ids
end

local function official(category, ...)
    local ids = {}
    for index, id in ipairs({ ... }) do ids[index] = ('official_%s_%s'):format(category, id) end
    return ids
end

local function merge(...)
    local ids = {}
    for _, list in ipairs({ ... }) do
        for _, id in ipairs(list) do ids[#ids + 1] = id end
    end
    return ids
end

-- Specialist directions. Every piece shares the selected palette, and
-- match = 'pattern' keeps the camo or colorway consistent across pieces.
-- Chances are percentages; a kit prop takes its slot ahead of the
-- Headwear and Accessories choices.
AppearanceKits.families = {
    { id = 'army_fatigues', name = 'Field fatigues', styles = { military = true }, match = 'pattern',
      tops = kit('tops', 'army_combat_shirt', 'army_service_shirt', 'army_defender_vest'),
      bottoms = kit('bottoms', 'army_cargo', 'army_cargo_bloused'),
      shoes = kit('shoes', 'army_tactical_boots', 'army_tactical_boots_tucked', 'tech_boots_tucked'),
      headgear = kit('headgear', 'combat_helmet', 'boonie_down', 'boonie_up'), headgearChance = 80 },
    { id = 'army_barracks', name = 'Barracks', styles = { military = true }, match = 'pattern',
      tops = kit('tops', 'army_tee', 'army_rolled_tee', 'army_sleeveless_shirt'),
      bottoms = kit('bottoms', 'army_cargo', 'army_cargo_bloused', 'army_cargo_shorts'),
      shoes = kit('shoes', 'army_cross_trainers', 'army_tactical_boots'),
      headgear = kit('headgear', 'army_cap', 'army_beret'), headgearChance = 60 },
    { id = 'army_field', name = 'Cold-weather field', styles = { military = true }, match = 'pattern',
      tops = kit('tops', 'army_collared_parka', 'army_closed_parka', 'field_closed', 'field_open'),
      bottoms = kit('bottoms', 'army_cargo', 'army_cargo_bloused'),
      shoes = kit('shoes', 'army_tactical_boots', 'army_tactical_boots_tucked', 'tech_boots'),
      headgear = kit('headgear', 'boonie_down', 'army_beret', 'combat_helmet'), headgearChance = 70 },

    { id = 'dive', name = 'Dive kit', styles = { scuba = true }, match = 'index', palette = 'full',
      tops = kit('tops', 'wetsuit'), bottoms = kit('bottoms', 'wetsuit_legs'), shoes = kit('shoes', 'dive_fins'),
      gear = kit('gear', 'scuba_mask', 'scuba_mask', 'scuba_mask', 'rebreather'), gearChance = 100 },

    { id = 'assault', name = 'Assault team', styles = { tactical = true }, match = 'pattern',
      tops = kit('tops', 'tactical_blouson', 'tactical_midlength', 'battle_vest'),
      bottoms = kit('bottoms', 'combat_pants', 'battle_pants'),
      shoes = kit('shoes', 'black_tactical_boots', 'tech_boots', 'tech_boots_tucked'),
      gear = kit('gear', 'tactical_ski_mask'), gearChance = 45,
      eyewear = kit('eyewear', 'tactical_goggles'), eyewearChance = 45,
      headgear = kit('headgear', 'combat_helmet'), headgearChance = 35 },
    { id = 'night_ops', name = 'Night operations', styles = { tactical = true }, match = 'pattern',
      tops = kit('tops', 'tactical_sleeveless', 'combat_top', 'combat_sweater'),
      bottoms = kit('bottoms', 'combat_pants', 'battle_pants'),
      shoes = kit('shoes', 'black_tactical_boots', 'tech_boots'),
      gear = kit('gear', 'tactical_ski_mask'), gearChance = 60,
      headgear = kit('headgear', 'night_vision'), headgearChance = 40 },

    { id = 'flight_suit', name = 'Flight suit', styles = { aviator = true },
      tops = kit('tops', 'flight_jacket'), bottoms = kit('bottoms', 'flight_suit_pants'),
      shoes = kit('shoes', 'flight_boots'),
      headgear = kit('headgear', 'flight_helmet', 'race_flight_helmet'), headgearChance = 70 },
    { id = 'flight_crew', name = 'Flight crew', styles = { aviator = true },
      tops = kit('tops', 'flight_bomber_closed', 'flight_bomber_open'),
      bottoms = merge(kit('bottoms', 'flight_suit_pants', 'combat_pants'), official('bottoms', 'flight_pants', 'large_cargo')),
      shoes = merge(kit('shoes', 'flight_boots'), official('shoes', 'tactical_boots', 'moc_toe_boots')),
      gear = kit('gear', 'goggles_flight_cap'), gearChance = 35 },

    { id = 'mountain', name = 'Mountain layers', styles = { alpine = true },
      tops = kit('tops', 'collared_puffer', 'tuner_puffer', 'bigness_puffer', 'closed_parka', 'open_parka'),
      bottoms = merge(kit('bottoms', 'combat_pants'), official('bottoms', 'large_cargo', 'knee_pad_cargo', 'utility_pants')),
      shoes = official('shoes', 'winter_boots', 'walking_boots', 'desert_boots', 'sheepskin_boots'),
      eyewear = kit('eyewear', 'ski_goggles'), eyewearChance = 70,
      headgear = kit('headgear', 'winter_beanie', 'saggy_beanie'), headgearChance = 55 },

    { id = 'dirt_track', name = 'Dirt track', styles = { motocross = true },
      tops = kit('tops', 'motocross_jersey'),
      bottoms = merge(kit('bottoms', 'combat_pants'), official('bottoms', 'knee_pad_cargo', 'raider_pants', 'padded_biker', 'quilted_biker')),
      shoes = merge(kit('shoes', 'tech_boots'), official('shoes', 'raider_boots', 'harness_boots')),
      headgear = kit('headgear', 'stunt_helmet', 'stunt_helmet_visor'), headgearChance = 85 },
}
for _, family in ipairs(AppearanceKits.families) do family.kit = true end

-- Statement families for the everyday directions. Like the other modern
-- families, only the top carries color under Mixed.
AppearanceKits.statementFamilies = {
    { id = 'camo_street', name = 'Camo streetwear', styles = { street = true, utility = true },
      tops = kit('tops', 'army_tee', 'army_rolled_tee', 'army_open_parka', 'army_collared_parka'),
      bottoms = official('bottoms', 'large_cargo', 'combat_pants', 'knee_pad_cargo', 'cuffed_sweats'),
      shoes = official('shoes', 'trail_shoes', 'tech_boots', 'cross_trainers', 'kicks') },
    { id = 'puffer_season', name = 'Puffer season', styles = { street = true, casual = true, designer = true },
      tops = kit('tops', 'collared_puffer', 'tuner_puffer', 'bigness_puffer'),
      bottoms = official('bottoms', 'cuffed_sweats', 'snap_joggers', 'large_cargo', 'track_pants'),
      shoes = official('shoes', 'knit', 'designer_lace', 'retro_runners', 'winter_boots') },
    { id = 'tactical_street', name = 'Tactical streetwear', styles = { street = true, utility = true, biker = true },
      tops = kit('tops', 'tactical_blouson', 'tactical_midlength'),
      bottoms = official('bottoms', 'large_cargo', 'combat_pants', 'chain'),
      shoes = official('shoes', 'trail_shoes', 'tech_boots', 'tactical_boots') },
    { id = 'flight_jacket', name = 'Flight jacket', styles = { casual = true, street = true },
      tops = kit('tops', 'flight_bomber_closed', 'flight_bomber_open'),
      bottoms = official('bottoms', 'turnups', 'fitted_jeans', 'large_cargo', 'ribbed_denim'),
      shoes = official('shoes', 'low_canvas', 'moc_toe_boots', 'retro_sneakers') },
    { id = 'parka_layers', name = 'Parka layers', styles = { casual = true, utility = true },
      tops = kit('tops', 'closed_parka', 'open_parka'),
      bottoms = official('bottoms', 'turnups', 'straight_chinos', 'large_cargo'),
      shoes = official('shoes', 'moc_toe_boots', 'logger', 'desert_boots', 'winter_boots') },
}
