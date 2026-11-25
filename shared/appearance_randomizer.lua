AppearanceRandomizer = AppearanceRandomizer or {}

local VALID_MODES = { outfit = true, character = true }
local VALID_STYLES = { polished = true, casual = true, street = true, sport = true, utility = true,
    biker = true, resort = true, nightlife = true, designer = true,
    military = true, scuba = true, tactical = true, aviator = true, alpine = true, motocross = true }
local VALID_GENDERS = { keep = true, male = true, female = true, random = true }
local VALID_HAIR_TONES = { any = true, dark = true, warm = true, light = true, gray = true, fashion = true }
-- Full range rolls every texture of every piece, named or not.
local VALID_PALETTES = { neutral = true, tonal = true, varied = true, full = true }
local VALID_FACE_PROFILES = { everyday = true, east_asian = true, soft = true, wide = true }
local VALID_AGE_PROFILES = { young = true, adult = true, mature = true }
local VALID_COMPLEXIONS = { clean = true, natural = true, freckled = true }
local VALID_HAIR_STYLES = { any = true, short = true, medium = true, long = true, updo = true }
local VALID_MAKEUP = { none = true, subtle = true, polished = true, bold = true }
local VALID_TOP_TYPES = { any = true, tee = true, shirt = true, knit = true, hoodie = true, jacket = true }
local VALID_BOTTOM_TYPES = { any = true, jeans = true, trousers = true, cargo = true, joggers = true, shorts = true, skirt = true }
local VALID_FOOTWEAR = { any = true, sneakers = true, boots = true, smart = true, heels = true, open = true }
local VALID_HEADWEAR = { none = true, any = true, cap = true, beanie = true, hat = true }
local VALID_ACCESSORIES = { none = true, minimal = true, layered = true }
local VALID_FACIAL_HAIR = { any = true, clean = true, stubble = true, short = true, full = true }
local VALID_EYE_COLORS = { natural = true, brown = true, blue = true, green = true, gray = true }
local VALID_FACE_VARIATION = { subtle = true, balanced = true, distinct = true }
local VALID_HIGHLIGHTS = { natural = true, none = true, contrast = true }

-- Each garment filter maps to the option that selects it.
local CATEGORY_FILTERS = {
    tops = { key = 'topType', valid = VALID_TOP_TYPES },
    bottoms = { key = 'bottomType', valid = VALID_BOTTOM_TYPES },
    shoes = { key = 'footwear', valid = VALID_FOOTWEAR },
}

-- Curated from rendered MP freemode catalogs. Pieces are interchangeable only
-- inside their declared style pool. An upper-body piece owns arms, undershirt,
-- and top together so a roll cannot create sleeve holes or mismatched layers.
--
-- Catalogs: https://wiki.rage.mp/wiki/Clothes
--           https://github.com/Colbss/FiveM-ClothingData
-- Indexing: https://docs.fivem.net/docs/scripting-manual/using-new-game-features/collection-based-natives/
local BASE_GAME_COLLECTION = ''

-- SET_PED_HEAD_BLEND_DATA treats shapeFirst as the mother and shapeSecond as
-- the father. These pools were reviewed against a rendered 0-45 parent grid;
-- each profile keeps one coherent parent pair and controls the resemblance
-- range instead of sampling four unrelated IDs.
--
-- Native contract: https://github.com/citizenfx/natives/blob/master/PED/SetPedHeadBlendData.md
-- Parent renders: https://forum.gta.world/en/topic/3809-gtmp-parent-face-list/
-- Hair stays on named base-game drawables so indexes remain stable across
-- game builds and installed clothing packs.
--
-- The wide profile samples every base-game parent on the correct side of the
-- native contract (mothers 21-41 and 45, fathers 0-20) for the full skin-tone
-- range. Story characters 42-44 stay out because they read as recognisable NPCs.
local WIDE_MOTHERS = { 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 45 }
local WIDE_FATHERS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }
local IDENTITY_POOLS = {
    male = {
        profiles = {
            everyday = { mothers = { 21, 22, 27, 28, 31, 33, 34, 37, 38, 40, 45 }, fathers = { 0, 1, 7, 10, 12, 16, 18, 19, 20 }, shapeMix = { 0.58, 0.78 } },
            east_asian = { mothers = { 27, 28, 31, 40, 45 }, fathers = { 6, 7, 12, 18, 19 }, shapeMix = { 0.58, 0.76 } },
            soft = { mothers = { 21, 22, 28, 31, 33, 34, 40, 45 }, fathers = { 0, 7, 10, 12, 18 }, shapeMix = { 0.48, 0.66 } },
            wide = { mothers = WIDE_MOTHERS, fathers = WIDE_FATHERS, shapeMix = { 0.58, 0.78 } },
        },
        hair = {
            { name = 'Buzzcut', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 1, texture = 0 },
            { name = 'Faux hawk', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 2, texture = 0 },
            { name = 'Short cut', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 5, texture = 0 },
            { name = 'Short brushed', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 10, texture = 0 },
            { name = 'Caesar', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 12, texture = 0 },
            { name = 'Short side part', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 18, texture = 0 },
            { name = 'Side-parted', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 4, texture = 0 },
            { name = 'Slicked', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 9, texture = 0 },
            { name = 'Layered', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 13, texture = 0 },
            { name = 'Tousled', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 19, texture = 0 },
            { name = 'Long tied', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 3, texture = 0 },
            { name = 'Braids', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 6, texture = 0 },
            { name = 'Long swept', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 15, texture = 0 },
            { name = 'Long loose', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 16, texture = 0 },
            { name = 'Top knot', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 14, texture = 0 },
            { name = 'Tied back', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 17, texture = 0 },
            { name = 'High knot', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 20, texture = 0 },
        },
    },
    female = {
        profiles = {
            everyday = { mothers = { 21, 22, 27, 28, 31, 33, 34, 37, 38, 40, 45 }, fathers = { 0, 7, 10, 12, 16, 18, 19, 20 }, shapeMix = { 0.16, 0.38 } },
            east_asian = { mothers = { 27, 28, 31, 40, 45 }, fathers = { 6, 7, 12, 18, 19 }, shapeMix = { 0.14, 0.34 } },
            soft = { mothers = { 21, 22, 28, 31, 33, 34, 40, 45 }, fathers = { 0, 7, 10, 12, 18 }, shapeMix = { 0.10, 0.28 } },
            wide = { mothers = WIDE_MOTHERS, fathers = WIDE_FATHERS, shapeMix = { 0.16, 0.38 } },
        },
        hair = {
            { name = 'Short', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 1, texture = 0 },
            { name = 'Pixie', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 12, texture = 0 },
            { name = 'Shaved fringe', group = 'short', collection = BASE_GAME_COLLECTION, drawable = 13, texture = 0 },
            { name = 'Layered bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 2, texture = 0 },
            { name = 'Bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 7, texture = 0 },
            { name = 'Long bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 10, texture = 0 },
            { name = 'Wavy bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 15, texture = 0 },
            { name = 'Flapper bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 18, texture = 0 },
            { name = 'Twisted bob', group = 'medium', collection = BASE_GAME_COLLECTION, drawable = 20, texture = 0 },
            { name = 'Pigtails', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 3, texture = 0 },
            { name = 'Ponytail', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 4, texture = 0 },
            { name = 'Braided mohawk', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 5, texture = 0 },
            { name = 'Braids', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 6, texture = 0 },
            { name = 'Loose tied', group = 'long', collection = BASE_GAME_COLLECTION, drawable = 11, texture = 0 },
            { name = 'French twist', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 9, texture = 0 },
            { name = 'Top knot', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 14, texture = 0 },
            { name = 'Pin-up', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 16, texture = 0 },
            { name = 'Messy bun', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 17, texture = 0 },
            { name = 'Tight bun', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 19, texture = 0 },
            { name = 'Large bun', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 21, texture = 0 },
            { name = 'Braided top knot', group = 'updo', collection = BASE_GAME_COLLECTION, drawable = 22, texture = 0 },
        },
    },
}

-- Narrow, reviewed morph bands keep generated faces recognizable without
-- flattening every roll into the same preset. Profile differences come from
-- the rendered parent pool; no ethnicity is encoded as a facial stereotype.
local FEMALE_FACE_RANGES = {
    [0] = { -0.18, 0.14 }, [1] = { -0.14, 0.16 }, [2] = { -0.18, 0.16 },
    [3] = { -0.14, 0.16 }, [4] = { -0.18, 0.14 }, [5] = { -0.14, 0.16 },
    [6] = { -0.12, 0.18 }, [7] = { -0.10, 0.18 }, [8] = { -0.10, 0.20 },
    [9] = { -0.10, 0.18 }, [10] = { -0.14, 0.12 }, [11] = { -0.12, 0.18 },
    [12] = { -0.22, 0.04 }, [13] = { -0.28, -0.02 }, [14] = { -0.24, 0.02 },
    [15] = { -0.14, 0.14 }, [16] = { -0.12, 0.14 }, [17] = { -0.20, 0.04 },
    [18] = { -0.12, 0.12 }, [19] = { -0.24, -0.04 },
}

local MALE_FACE_RANGES = {
    [0] = { -0.22, 0.22 }, [1] = { -0.18, 0.20 }, [2] = { -0.20, 0.20 },
    [3] = { -0.18, 0.20 }, [4] = { -0.20, 0.20 }, [5] = { -0.18, 0.20 },
    [6] = { -0.18, 0.18 }, [7] = { -0.16, 0.18 }, [8] = { -0.16, 0.20 },
    [9] = { -0.16, 0.18 }, [10] = { -0.18, 0.20 }, [11] = { -0.16, 0.16 },
    [12] = { -0.18, 0.16 }, [13] = { -0.12, 0.24 }, [14] = { -0.10, 0.24 },
    [15] = { -0.16, 0.18 }, [16] = { -0.14, 0.18 }, [17] = { -0.14, 0.18 },
    [18] = { -0.14, 0.16 }, [19] = { -0.12, 0.20 },
}

-- Scales the reviewed morph bands. Distinct stays well inside the native -1..1.
local FACE_VARIATION_SCALE = { subtle = 0.6, balanced = 1.0, distinct = 1.45 }

-- Overlay 1 styles in character-creator order. The novelty styles 21-25
-- (Handlebar through Otto & Full Stranger) stay out of every group.
local FACIAL_HAIR_STYLES = {
    stubble = { 0, 11 },
    short = { 1, 2, 3, 4, 5, 6, 9, 10, 12, 14, 15, 16 },
    full = { 7, 8, 13, 17, 18, 19, 20, 26, 27, 28 },
}
FACIAL_HAIR_STYLES.any = {}
for _, group in ipairs({ 'stubble', 'short', 'full' }) do
    for _, style in ipairs(FACIAL_HAIR_STYLES[group]) do FACIAL_HAIR_STYLES.any[#FACIAL_HAIR_STYLES.any + 1] = style end
end

-- SetPedEyeColor creator order: 0-1 green, 2-3 blue, 4-6 brown and hazel,
-- 7-8 gray. Natural repeats the browns so they appear most often.
local EYE_COLORS = {
    natural = { 4, 5, 5, 6, 4, 5, 6, 0, 1, 2, 3, 7, 8 },
    brown = { 4, 5, 6 },
    blue = { 2, 3 },
    green = { 0, 1 },
    gray = { 7, 8 },
}

local function overlay(chance, minimumOpacity, maximumOpacity, color, styles)
    return {
        chance = chance,
        minimumOpacity = minimumOpacity or 0.0,
        maximumOpacity = maximumOpacity or minimumOpacity or 0.0,
        color = color,
        styles = styles,
    }
end

local function upperVariant(name, undershirtTexture, topTexture)
    return { name = name, textures = { [3] = 0, [8] = undershirtTexture, [11] = topTexture } }
end

local function clothingVariant(name, component, texture)
    return { name = name, textures = { [component] = texture } }
end

local function propVariant(name, texture)
    return { name = name, texture = texture }
end

-- Props stay on base-game drawables: collection-local and global indexes are
-- identical there, so no prop index table is needed. Textures above 7 on these
-- frames arrived in later updates and are left out. A nil style list means the
-- prop suits every direction.
local function accessory(kind, prop, drawable, styles, neutral, tonal, varied)
    return {
        kind = kind, prop = prop, drawable = drawable, styles = styles,
        variants = { neutral = neutral, tonal = tonal, varied = varied },
    }
end

local PIECES = {
    male = {
        tops = {
            tee_clean = {
                components = { [3] = 0, [8] = 0, [11] = 0 },
                variants = {
                    neutral = { upperVariant('Charcoal T-shirt', 2, 2), upperVariant('Crew T-shirt', 0, 0) },
                    tonal = { upperVariant('Charcoal T-shirt', 2, 2), upperVariant('Sweatbox T-shirt', 8, 8) },
                    varied = { upperVariant('Ranch T-shirt', 4, 4), upperVariant('Pikeys T-shirt', 5, 5) },
                },
            },
            tee_graphic = {
                components = { [3] = 0, [8] = 0, [11] = 0 },
                variants = {
                    neutral = { upperVariant('Charcoal T-shirt', 2, 2), upperVariant('Eris T-shirt', 11, 11) },
                    tonal = { upperVariant('Sweatbox T-shirt', 8, 8), upperVariant('Crew T-shirt', 0, 0) },
                    varied = { upperVariant('Multi-Logo T-shirt', 7, 7), upperVariant('Ranch T-shirt', 4, 4), upperVariant('Pikeys T-shirt', 5, 5) },
                },
            },
            polo = {
                components = { [3] = 0, [8] = 9, [11] = 9 },
                variants = {
                    neutral = { upperVariant('Night polo', 2, 2), upperVariant('Metal polo', 1, 1), upperVariant('White striped polo', 0, 0) },
                    tonal = { upperVariant('Blue polo', 4, 4), upperVariant('Royale polo', 7, 7), upperVariant('Hunter polo', 13, 13) },
                    varied = { upperVariant('Salmon polo', 6, 6), upperVariant('Pro Lite polo', 10, 10), upperVariant('Ice polo', 11, 11) },
                },
            },
        },
        bottoms = {
            regular_jeans = {
                components = { [4] = 0 },
                variants = {
                    neutral = { clothingVariant('Black regular-fit jeans', 4, 12), clothingVariant('Gray regular-fit jeans', 4, 5), clothingVariant('Dark blue regular-fit jeans', 4, 8) },
                    tonal = { clothingVariant('Navy regular-fit jeans', 4, 0), clothingVariant('Faded dark-blue jeans', 4, 4) },
                    varied = { clothingVariant('Tan regular-fit jeans', 4, 3), clothingVariant('Brown regular-fit jeans', 4, 11) },
                },
            },
            ranch_jeans = {
                components = { [4] = 1 },
                variants = {
                    neutral = { clothingVariant('Black Ranch jeans', 4, 1), clothingVariant('Gray Ranch jeans', 4, 2), clothingVariant('Slate jeans', 4, 0) },
                    tonal = { clothingVariant('Navy Ranch jeans', 4, 11), clothingVariant('Blue Ranch jeans', 4, 12) },
                    varied = { clothingVariant('Olive Ranch jeans', 4, 9), clothingVariant('Tan Ranch jeans', 4, 14) },
                },
            },
            chinos = {
                components = { [4] = 8 },
                variants = {
                    neutral = { clothingVariant('Charcoal chinos', 4, 0), clothingVariant('Gray chinos', 4, 4) },
                    tonal = { clothingVariant('Charcoal chinos', 4, 0), clothingVariant('Gray chinos', 4, 4) },
                    varied = { clothingVariant('Tan chinos', 4, 3), clothingVariant('Sky-blue chinos', 4, 14) },
                },
            },
            dress_chinos = {
                components = { [4] = 12 },
                variants = {
                    neutral = { clothingVariant('Black chinos', 4, 0), clothingVariant('Gray chinos', 4, 5) },
                    tonal = { clothingVariant('Navy chinos', 4, 12), clothingVariant('Gray plaid chinos', 4, 4) },
                    varied = { clothingVariant('Tan chinos', 4, 7), clothingVariant('Navy chinos', 4, 12) },
                },
            },
            cargo = {
                components = { [4] = 9 },
                variants = {
                    neutral = { clothingVariant('Black cargo pants', 4, 7), clothingVariant('Urban cargo pants', 4, 10), clothingVariant('Black-camo cargo pants', 4, 13) },
                    tonal = { clothingVariant('Navy cargo pants', 4, 3), clothingVariant('Olive cargo pants', 4, 0) },
                    varied = { clothingVariant('Khaki cargo pants', 4, 1), clothingVariant('Brown cargo pants', 4, 5) },
                },
            },
            baggy = {
                components = { [4] = 13 },
                variants = {
                    neutral = { clothingVariant('Black baggy pants', 4, 0), clothingVariant('Gray baggy pants', 4, 1) },
                    tonal = { clothingVariant('Gray baggy pants', 4, 1), clothingVariant('Blue baggy pants', 4, 2) },
                    varied = { clothingVariant('Blue baggy pants', 4, 2), clothingVariant('Black baggy pants', 4, 0) },
                },
            },
            fitted_cargo = {
                components = { [4] = 15 },
                variants = {
                    neutral = { clothingVariant('Black fitted cargos', 4, 3), clothingVariant('Gray fitted cargos', 4, 5) },
                    tonal = { clothingVariant('Olive fitted cargos', 4, 1), clothingVariant('Blue fitted cargos', 4, 14) },
                    varied = { clothingVariant('Tan fitted cargos', 4, 4), clothingVariant('Brown fitted cargos', 4, 7) },
                },
            },
        },
        shoes = {
            canvas = {
                components = { [6] = 4 },
                variants = {
                    neutral = { clothingVariant('Black canvas shoes', 6, 1), clothingVariant('White canvas shoes', 6, 2) },
                    tonal = { clothingVariant('Navy canvas shoes', 6, 0), clothingVariant('Black canvas shoes', 6, 1) },
                    varied = { clothingVariant('White canvas shoes', 6, 2), clothingVariant('Red canvas shoes', 6, 4) },
                },
            },
            skate = {
                components = { [6] = 1 },
                variants = {
                    neutral = { clothingVariant('Black skate shoes', 6, 14), clothingVariant('Gray skate shoes', 6, 13), clothingVariant('Charcoal skate shoes', 6, 7) },
                    tonal = { clothingVariant('Navy skate shoes', 6, 6), clothingVariant('Slate skate shoes', 6, 2) },
                    varied = { clothingVariant('Olive skate shoes', 6, 11), clothingVariant('Tan skate shoes', 6, 12) },
                },
            },
            boat = {
                components = { [6] = 3 },
                variants = {
                    neutral = { clothingVariant('Black boat shoes', 6, 4), clothingVariant('Gray boat shoes', 6, 2), clothingVariant('Charcoal boat shoes', 6, 13) },
                    tonal = { clothingVariant('Blue-gray boat shoes', 6, 1), clothingVariant('Umber boat shoes', 6, 15) },
                    varied = { clothingVariant('Tan two-tone boat shoes', 6, 9), clothingVariant('Black boat shoes', 6, 4) },
                },
            },
            oxford = {
                components = { [6] = 10 },
                variants = {
                    neutral = { clothingVariant('Black Oxfords', 6, 0) },
                    tonal = { clothingVariant('Coffee Oxfords', 6, 12), clothingVariant('Black Oxfords', 6, 0) },
                    varied = { clothingVariant('Beige Oxfords', 6, 14), clothingVariant('Black Oxfords', 6, 0) },
                },
            },
            chelsea = {
                components = { [6] = 15 },
                variants = {
                    neutral = { clothingVariant('Black Chelsea boots', 6, 0), clothingVariant('Gray Chelsea boots', 6, 13), clothingVariant('Black wingtip Chelsea boots', 6, 10) },
                    tonal = { clothingVariant('Brown Chelsea boots', 6, 1), clothingVariant('Black Chelsea boots', 6, 4) },
                    varied = { clothingVariant('Tan Chelsea boots', 6, 5), clothingVariant('Burgundy Chelsea boots', 6, 2) },
                },
            },
            boots = {
                components = { [6] = 14 },
                variants = {
                    neutral = { clothingVariant('Black boots', 6, 1), clothingVariant('Charcoal boots', 6, 0) },
                    tonal = { clothingVariant('Navy boots', 6, 3), clothingVariant('Olive boots', 6, 2) },
                    varied = { clothingVariant('Tan boots', 6, 4), clothingVariant('Brown boots', 6, 8) },
                },
            },
        },
        accessories = {
            classic_watch = accessory('watch', 6, 0, nil,
                { propVariant('Silver Watch', 2), propVariant('Black Watch', 3) },
                { propVariant('Silver Watch', 2), propVariant('Black Watch', 3) },
                { propVariant('Deep Sea Watch', 0), propVariant('Gold Watch', 1), propVariant('Gold Faced Silver Watch', 4) }),
            led_watch = accessory('watch', 6, 1, { 'casual', 'street', 'sport' },
                { propVariant('White LED, Black Strap', 0) },
                { propVariant('White LED, Tan Strap', 3) },
                { propVariant('Red LED, White Strap', 1), propVariant('Red LED, Brown Strap', 2), propVariant('Yellow LED', 4) }),
            sport_watch = accessory('watch', 6, 2, { 'sport', 'street', 'casual', 'utility', 'resort' },
                { propVariant('Black Sports', 0), propVariant('White Sports', 2) },
                { propVariant('Blue Sports', 4) },
                { propVariant('Red Sports', 1), propVariant('Yellow Sports', 3) }),
            janitor_frames = accessory('glasses', 1, 3, nil,
                { propVariant('Slate Janitor Frames', 0), propVariant('Black Janitor Frames', 1), propVariant('Gray Janitor Frames', 2), propVariant('Ash Janitor Frames', 3) },
                { propVariant('Tan Janitor Frames', 4) },
                { propVariant('Tan Janitor Frames', 4) }),
            aviators = accessory('glasses', 1, 5, nil,
                { propVariant('Steel Aviators', 1) },
                { propVariant('Silver Aviators, Brown Tint', 2), propVariant('Silver Aviators, Blue Tint', 4), propVariant('Tan Aviators, Dark Tint', 5), propVariant('Steel Aviators, Blue Tint', 6) },
                { propVariant('Gold Aviators', 0), propVariant('Gray Aviators, Green Tint', 3), propVariant('Silver Aviators, Copper Tint', 7) }),
            casuals = accessory('glasses', 1, 7, { 'casual', 'street', 'resort', 'sport' },
                { propVariant('Black Casuals', 0), propVariant('White Casuals', 4) },
                { propVariant('Black Casuals', 0), propVariant('White Casuals', 4) },
                { propVariant('Zap Casuals', 1), propVariant('Tortoiseshell Casuals', 2), propVariant('Red Casuals', 3), propVariant('Camo Collection Casuals', 5) }),
            cop_frames = accessory('glasses', 1, 8, { 'polished', 'utility', 'nightlife', 'biker' },
                { propVariant('Silver Eyewear', 1), propVariant('Gray Eyewear', 2), propVariant('Smoke Cop Frames', 3), propVariant('Black Cop Frames', 5) },
                { propVariant('Brown Eyewear', 0), propVariant('Coffee Cop Frames', 4) },
                { propVariant('Brown Eyewear', 0), propVariant('Coffee Cop Frames', 4) }),
            bull_emic = accessory('glasses', 1, 10, { 'nightlife', 'designer', 'polished' },
                { propVariant('Gray Bull Emic', 1), propVariant('Silver Bull Emic', 2), propVariant('Black Bull Emic', 3), propVariant('Slate Bull Emic', 5) },
                { propVariant('Brown Bull Emic', 4) },
                { propVariant('Gold Bull Emic', 0), propVariant('Purple Tint Bull Emic', 7) }),
            hipsters = accessory('glasses', 1, 13, { 'designer', 'street', 'casual' },
                { propVariant('Broker Black Hipsters', 0), propVariant('White Polarized Hipsters', 1), propVariant('Slate Hipsters', 3), propVariant('Charcoal Hipsters', 4) },
                { propVariant('Olive Polarized Hipsters', 5) },
                { propVariant('Choco Polarized Hipsters', 2), propVariant('Gold Polarized Hipsters', 6), propVariant('Candy Polarized Hipsters', 7) }),
            shades = accessory('glasses', 1, 2, { 'resort', 'sport', 'street' },
                { propVariant('Black Winter Shades', 0), propVariant('White Silver Shades', 1), propVariant('Black Summer Shades', 3), propVariant('Black Autumn Shades', 4) },
                { propVariant('White Rust Shades', 5) },
                { propVariant('Crimson Polarized Shades', 2), propVariant('Green Polarized Shades', 7) }),
            hawaiian_snow = accessory('glasses', 1, 9, { 'resort', 'sport' },
                { propVariant('Hawaiian Snow Black', 0), propVariant('Hawaiian Snow Gray', 1), propVariant('Hawaiian Snow White', 2), propVariant('Hawaiian Snow Ash', 3) },
                { propVariant('Hawaiian Snow Walnut', 7) },
                { propVariant('Hawaiian Snow Copper', 4), propVariant('Hawaiian Snow Tortoiseshell', 5), propVariant('Hawaiian Snow Marble', 6) }),
            winter_beanie = accessory('beanie', 0, 2, { 'street', 'casual', 'utility', 'sport' },
                { propVariant('Black Winter Hat', 0), propVariant('Gray Winter Hat', 1), propVariant('White Winter Hat', 6) },
                { propVariant('Blue Winter Hat', 2), propVariant('Maroon Winter Hat', 7) },
                { propVariant('Rasta Winter Hat', 3), propVariant('Gray Striped Winter Hat', 4), propVariant('Trio Knit Winter Hat', 5) }),
            saggy_beanie = accessory('beanie', 0, 5, { 'street', 'casual' },
                { propVariant('Black Saggy Beanie', 0), propVariant('Gray Saggy Beanie', 1) },
                { propVariant('Black Saggy Beanie', 0), propVariant('Gray Saggy Beanie', 1) },
                { propVariant('Black Saggy Beanie', 0), propVariant('Gray Saggy Beanie', 1) }),
            fitted_cap = accessory('cap', 0, 4, { 'street', 'sport', 'casual' },
                { propVariant('Black LS Fitted Cap', 0), propVariant('Gray LS Fitted Cap', 1) },
                { propVariant('Black LS Fitted Cap', 0), propVariant('Gray LS Fitted Cap', 1) },
                { propVariant('Black LS Fitted Cap', 0), propVariant('Gray LS Fitted Cap', 1) }),
            army_cap = accessory('cap', 0, 6, { 'utility', 'street', 'casual' },
                { propVariant('Black Army Cap', 1), propVariant('Gray Army Cap', 2) },
                { propVariant('Blue Army Cap', 3), propVariant('Desert Army Cap', 4), propVariant('Ranch Beige Army Cap', 6), propVariant('Ranch Brown Army Cap', 7) },
                { propVariant('Green Army Cap', 0), propVariant('Woodland Army Cap', 5) }),
            flat_cap = accessory('cap', 0, 7, { 'casual', 'polished', 'resort', 'designer' },
                { propVariant('White Flat Cap', 0), propVariant('Gray Flat Cap', 1), propVariant('Black Flat Cap', 2) },
                { propVariant('Navy Flat Cap', 3), propVariant('Brown Flat Cap', 5) },
                { propVariant('Red Flat Cap', 4), propVariant('Green Flat Cap', 6), propVariant('Yellow Flat Cap', 7) }),
            canvas_hat = accessory('hat', 0, 3, { 'resort', 'utility' },
                { propVariant('Black Canvas Hat', 1) },
                { propVariant('Tan Canvas Hat', 2) },
                { propVariant('Tan Canvas Hat', 2) }),
            pork_pie = accessory('hat', 0, 11, { 'nightlife', 'designer', 'polished' },
                { propVariant('Black Pork Pie', 1) },
                { propVariant('Olive Pork Pie', 3), propVariant('Blue Pork Pie', 6) },
                { propVariant('Olive Pork Pie', 3), propVariant('Blue Pork Pie', 6) }),
            fedora = accessory('hat', 0, 12, { 'nightlife', 'polished', 'designer' },
                { propVariant('Black Fedora', 0), propVariant('White Fedora', 1), propVariant('Ash Fedora', 2) },
                { propVariant('Brown Fedora', 4), propVariant('Navy Fedora', 7) },
                { propVariant('Green Fedora', 6) }),
            cowboy_hat = accessory('hat', 0, 13, { 'biker', 'casual' },
                { propVariant('Black Cowboy Hat', 0), propVariant('White Cowboy Hat', 3) },
                { propVariant('Brown Cowboy Hat', 1), propVariant('Chocolate Cowboy Hat', 2), propVariant('Chestnut Cowboy Hat', 4), propVariant('Beige Cowboy Hat', 5) },
                { propVariant('Red Cowboy Hat', 6) }),
        },
    },
    female = {
        tops = {
            tee_clean = {
                components = { [3] = 0, [8] = 0, [11] = 0 },
                variants = {
                    neutral = { upperVariant('Ash T-shirt', 10, 10), upperVariant('Gray T-shirt', 11, 11), upperVariant('Crew T-shirt', 0, 0) },
                    tonal = { upperVariant('Blue T-shirt', 6, 6), upperVariant('Baby-blue T-shirt', 14, 14), upperVariant('Gray T-shirt', 11, 11) },
                    varied = { upperVariant('Tan T-shirt', 7, 7), upperVariant('Two-tone T-shirt', 13, 13), upperVariant('Two-tone striped T-shirt', 15, 15) },
                },
            },
            polo = {
                components = { [3] = 0, [8] = 14, [11] = 14 },
                variants = {
                    neutral = { upperVariant('Black polo', 0, 3), upperVariant('Gray polo', 0, 0), upperVariant('Black striped polo', 0, 12) },
                    tonal = { upperVariant('Navy polo', 0, 7), upperVariant('Sky-blue polo', 0, 5) },
                    varied = { upperVariant('Black striped polo', 0, 12), upperVariant('White striped polo', 0, 13) },
                },
            },
            shirt = {
                components = { [3] = 0, [8] = 9, [11] = 9 },
                variants = {
                    neutral = { upperVariant('Charcoal shirt', 0, 0), upperVariant('White shirt', 0, 1) },
                    tonal = { upperVariant('Navy-fade shirt', 0, 9), upperVariant('Light-blue shirt', 0, 8), upperVariant('Sky-blue shirt', 0, 2) },
                    varied = { upperVariant('Olive shirt', 0, 3), upperVariant('Peach shirt', 0, 4) },
                },
            },
        },
        bottoms = {
            skinny = {
                components = { [4] = 0 },
                variants = {
                    neutral = { clothingVariant('Black skinny jeans', 4, 1), clothingVariant('Navy faded skinny jeans', 4, 8), clothingVariant('Navy skinny jeans', 4, 0) },
                    tonal = { clothingVariant('Indigo skinny jeans', 4, 2), clothingVariant('Blue faded skinny jeans', 4, 10) },
                    varied = { clothingVariant('Green skinny jeans', 4, 7), clothingVariant('Black skinny jeans', 4, 1) },
                },
            },
            regular_jeans = {
                components = { [4] = 1 },
                variants = {
                    neutral = { clothingVariant('Distressed black jeans', 4, 5), clothingVariant('Slate regular-fit jeans', 4, 6), clothingVariant('Navy regular-fit jeans', 4, 13) },
                    tonal = { clothingVariant('Faded dark-blue jeans', 4, 0), clothingVariant('Dark-blue regular-fit jeans', 4, 4) },
                    varied = { clothingVariant('Brown regular-fit jeans', 4, 11), clothingVariant('White regular-fit jeans', 4, 12) },
                },
            },
            rollups = {
                components = { [4] = 2 },
                variants = {
                    neutral = { clothingVariant('Black rollups', 4, 2), clothingVariant('Charcoal rollups', 4, 1), clothingVariant('Ash rollups', 4, 0) },
                    tonal = { clothingVariant('Charcoal rollups', 4, 1), clothingVariant('Ash rollups', 4, 0) },
                    varied = { clothingVariant('Ash rollups', 4, 0), clothingVariant('Black rollups', 4, 2) },
                },
            },
            chinos = {
                components = { [4] = 3 },
                variants = {
                    neutral = { clothingVariant('Black chinos', 4, 0), clothingVariant('Gray chinos', 4, 2), clothingVariant('Navy chinos', 4, 3) },
                    tonal = { clothingVariant('Navy chinos', 4, 3), clothingVariant('Gray chinos', 4, 2) },
                    varied = { clothingVariant('Khaki chinos', 4, 5), clothingVariant('Beige chinos', 4, 8) },
                },
            },
            suit = {
                components = { [4] = 6 },
                variants = {
                    neutral = { clothingVariant('Black suit trousers', 4, 0), clothingVariant('Charcoal suit trousers', 4, 1), clothingVariant('Navy suit trousers', 4, 2) },
                    tonal = { clothingVariant('Navy suit trousers', 4, 2), clothingVariant('Charcoal suit trousers', 4, 1) },
                    varied = { clothingVariant('Charcoal suit trousers', 4, 1), clothingVariant('Navy suit trousers', 4, 2) },
                },
            },
            cargo = {
                components = { [4] = 11 },
                variants = {
                    neutral = { clothingVariant('Black cargos', 4, 1), clothingVariant('Charcoal cargos', 4, 3), clothingVariant('Gray cargos', 4, 12) },
                    tonal = { clothingVariant('Navy cargos', 4, 4), clothingVariant('Olive cargos', 4, 0) },
                    varied = { clothingVariant('Khaki cargos', 4, 6), clothingVariant('Tan cargos', 4, 7) },
                },
            },
        },
        shoes = {
            canvas = {
                components = { [6] = 3 },
                variants = {
                    neutral = { clothingVariant('Black canvas shoes', 6, 0), clothingVariant('White canvas shoes', 6, 1), clothingVariant('Navy canvas shoes', 6, 3) },
                    tonal = { clothingVariant('Navy canvas shoes', 6, 3), clothingVariant('Blue canvas shoes', 6, 11) },
                    varied = { clothingVariant('White canvas shoes', 6, 1), clothingVariant('Green canvas shoes', 6, 5) },
                },
            },
            sports = {
                components = { [6] = 4 },
                variants = {
                    neutral = { clothingVariant('Black sports shoes', 6, 0), clothingVariant('White sports shoes', 6, 1), clothingVariant('Off-white sports shoes', 6, 2) },
                    tonal = { clothingVariant('Blue sports shoes', 6, 3), clothingVariant('Black sports shoes', 6, 0) },
                    varied = { clothingVariant('White sports shoes', 6, 1), clothingVariant('Off-white sports shoes', 6, 2) },
                },
            },
            runners = {
                components = { [6] = 10 },
                variants = {
                    neutral = { clothingVariant('Gray runners', 6, 1), clothingVariant('Two-tone runners', 6, 3) },
                    tonal = { clothingVariant('Baby-blue runners', 6, 2), clothingVariant('Two-tone runners', 6, 3) },
                    varied = { clothingVariant('Purple-accent runners', 6, 0), clothingVariant('Gray runners', 6, 1) },
                },
            },
            ankle = {
                components = { [6] = 8 },
                variants = {
                    neutral = { clothingVariant('Black ankle boots', 6, 0), clothingVariant('Gray ankle boots', 6, 1), clothingVariant('Charcoal ankle boots', 6, 4) },
                    tonal = { clothingVariant('Charcoal ankle boots', 6, 4), clothingVariant('Brown ankle boots', 6, 2) },
                    varied = { clothingVariant('Cream ankle boots', 6, 5), clothingVariant('Explorer ankle boots', 6, 6) },
                },
            },
            round_toed = {
                components = { [6] = 13 },
                variants = {
                    neutral = { clothingVariant('Charcoal round-toed shoes', 6, 0), clothingVariant('Gray round-toed shoes', 6, 14) },
                    tonal = { clothingVariant('Blue round-toed shoes', 6, 11), clothingVariant('Charcoal round-toed shoes', 6, 0) },
                    varied = { clothingVariant('Wheat round-toed shoes', 6, 6), clothingVariant('Two-tone round-toed shoes', 6, 5) },
                },
            },
            combat = {
                components = { [6] = 7 },
                variants = {
                    neutral = { clothingVariant('Midnight combat boots', 6, 0), clothingVariant('Gray combat boots', 6, 1) },
                    tonal = { clothingVariant('Olive combat boots', 6, 9), clothingVariant('Gray combat boots', 6, 1) },
                    varied = { clothingVariant('Wheat combat boots', 6, 5), clothingVariant('Tan combat boots', 6, 13) },
                },
            },
            high_tops = {
                components = { [6] = 11 },
                variants = {
                    neutral = { clothingVariant('Two-tone high tops', 6, 2), clothingVariant('Elite Shock high tops', 6, 1) },
                    tonal = { clothingVariant('Two-tone high tops', 6, 2), clothingVariant('Elite Shock high tops', 6, 1) },
                    varied = { clothingVariant('Red-accent high tops', 6, 3), clothingVariant('Two-tone high tops', 6, 2) },
                },
            },
        },
        accessories = {
            pewter_watch = accessory('watch', 6, 0, nil,
                { propVariant('Pewter Watch', 4) },
                { propVariant('Pewter Watch', 4) },
                { propVariant('Pewter Watch', 4) }),
            aviators = accessory('glasses', 1, 11, nil,
                { propVariant('Pewter Aviators', 0), propVariant('Steel Aviators', 1), propVariant('Black Aviators', 3), propVariant('Slate Aviators', 7) },
                { propVariant('Pewter Aviators', 0), propVariant('Steel Aviators', 1) },
                { propVariant('Bronze Aviators', 2), propVariant('Copper Aviators', 5), propVariant('Gold Aviators', 6) }),
            marbles = accessory('glasses', 1, 1, { 'resort', 'casual', 'nightlife' },
                { propVariant('Black Marbles', 2), propVariant('White Marbles', 6) },
                { propVariant('Blue Tint Marbles', 1), propVariant('Teal Marbles', 4) },
                { propVariant('Copper Marbles', 0), propVariant('Purple Marbles', 3), propVariant('Red Tint Marbles', 5), propVariant('Pink Tint Marbles', 7) }),
            mademoiselles = accessory('glasses', 1, 2, { 'polished', 'nightlife', 'designer' },
                { propVariant('Black Mademoiselles', 5) },
                { propVariant('Walnut Mademoiselles', 4) },
                { propVariant('Marble Mademoiselles', 0), propVariant('Copper Mademoiselles', 1), propVariant('Orange Tint Mademoiselles', 2), propVariant('Pink Tint Mademoiselles', 3) }),
            retro = accessory('glasses', 1, 4, { 'casual', 'street', 'designer' },
                { propVariant('Black Retro', 5) },
                { propVariant('Deep Walnut Retro', 0), propVariant('Beige Retro', 2), propVariant('Toffee Retro', 6) },
                { propVariant('Marble Retro', 1), propVariant('Aqua Retro', 3), propVariant('Dice Retro', 4), propVariant('Red Retro', 7) }),
            figure_eights = accessory('glasses', 1, 7, { 'nightlife', 'designer', 'polished' },
                { propVariant('White Figure 8s', 5), propVariant('Gray Figure 8s', 6) },
                { propVariant('White Figure 8s', 5), propVariant('Gray Figure 8s', 6) },
                { propVariant('Champagne Figure 8s', 0), propVariant('Platinum Figure 8s', 1), propVariant('Sapphire Figure 8s', 2), propVariant('Amethyst Figure 8s', 3) }),
            cat_eyes = accessory('glasses', 1, 14, { 'polished', 'nightlife', 'designer', 'resort' },
                { propVariant('Black Cat Eyes', 0) },
                { propVariant('Brown Marble Cat Eyes', 1), propVariant('Teal Cat Eyes', 5), propVariant('Blue Cat Eyes', 7) },
                { propVariant('Pink Cat Eyes', 2), propVariant('Green Marble Cat Eyes', 3), propVariant('Red Cat Eyes', 4), propVariant('Purple Cat Eyes', 6) }),
            sports_shades = accessory('glasses', 1, 0, { 'sport', 'resort', 'street' },
                { propVariant('Blue Sports Shades', 3), propVariant('Beige Sports Shades', 7) },
                { propVariant('Blue Sports Shades', 3), propVariant('Beige Sports Shades', 7) },
                { propVariant('Hornet Sports Shades', 0), propVariant('Two-Tone Sports Shades', 1), propVariant('Orange Sports Shades', 2), propVariant('Marble Sports Shades', 4) }),
            fitted_cap = accessory('cap', 0, 4, { 'street', 'sport', 'casual' },
                { propVariant('Black LS Fitted Cap', 0) },
                { propVariant('Black LS Fitted Cap', 0) },
                { propVariant('Fruntalot Fitted Cap', 1), propVariant('Broker Fitted Cap', 2), propVariant('SA Fitted Cap', 3), propVariant('SA Boars Fitted Cap', 4) }),
            military_cap = accessory('cap', 0, 6, { 'utility', 'street', 'casual' },
                { propVariant('Black Military Cap', 0) },
                { propVariant('Tan Military Cap', 3), propVariant('Denim Military Cap', 4) },
                { propVariant('Green Military Cap', 1), propVariant('Leopard Military Cap', 2), propVariant('Field Camo Military Cap', 5), propVariant('Desert Camo Military Cap', 6) }),
            flat_cap = accessory('cap', 0, 7, { 'casual', 'polished', 'resort', 'designer' },
                { propVariant('White Flat Cap', 1) },
                { propVariant('Navy Flat Cap', 0) },
                { propVariant('Gray Plaid Flat Cap', 2), propVariant('Brown Plaid Flat Cap', 3), propVariant('Red Flat Cap', 4), propVariant('Pink Flat Cap', 5) }),
            beanie = accessory('beanie', 0, 5, { 'street', 'casual', 'utility', 'sport' },
                { propVariant('Rearwall Black Beanie', 0), propVariant('Crevis Ash Beanie', 1) },
                { propVariant('Hawaiian Snow Blue Beanie', 5) },
                { propVariant('Crevis Pink Beanie', 2), propVariant('LS Panic Beanie', 3), propVariant('SA Beanie', 4), propVariant('Rearwall Lime Beanie', 6) }),
            saggy_beanie = accessory('beanie', 0, 12, { 'street', 'casual' },
                { propVariant('Black Saggy Beanie', 0) },
                { propVariant('Black Saggy Beanie', 0) },
                { propVariant('Hawaiian Snow Saggy Beanie', 6), propVariant('Yeti Saggy Beanie', 7) }),
            straw_hat = accessory('hat', 0, 13, { 'resort', 'casual' },
                { propVariant('Gray Patterned Straw Hat', 4), propVariant('Gray Straw Hat', 6) },
                { propVariant('Tan Straw Hat', 0), propVariant('Brown Straw Hat', 2), propVariant('Navy Straw Hat', 7) },
                { propVariant('Two-Tone Straw Hat', 1), propVariant('Safari Straw Hat', 3), propVariant('Brown Striped Straw Hat', 5) }),
            beret = accessory('hat', 0, 14, { 'designer', 'polished', 'nightlife' },
                { propVariant('Black Beret', 0), propVariant('White Beret', 3), propVariant('Gray Beret', 4) },
                { propVariant('Navy Beret', 5), propVariant('Tan Beret', 6) },
                { propVariant('Cherry Beret', 1), propVariant('Purple Beret', 2), propVariant('Magenta Beret', 7) }),
        },
    },
}

local STYLE_POOLS = {
    male = {
        polished = { tops = { 'polo' }, bottoms = { 'chinos', 'dress_chinos', 'regular_jeans' }, shoes = { 'oxford', 'chelsea', 'boat' } },
        casual = { tops = { 'tee_clean', 'polo' }, bottoms = { 'regular_jeans', 'ranch_jeans', 'chinos' }, shoes = { 'canvas', 'skate', 'boat' } },
        street = { tops = { 'tee_graphic', 'tee_clean' }, bottoms = { 'cargo', 'baggy', 'fitted_cargo' }, shoes = { 'skate', 'boots', 'canvas' } },
    },
    female = {
        polished = { tops = { 'shirt', 'polo' }, bottoms = { 'suit', 'chinos' }, shoes = { 'round_toed', 'ankle' } },
        casual = { tops = { 'tee_clean' }, bottoms = { 'skinny', 'rollups', 'chinos' }, shoes = { 'canvas', 'sports', 'ankle' } },
        street = { tops = { 'tee_clean' }, bottoms = { 'cargo', 'skinny' }, shoes = { 'combat', 'high_tops', 'canvas' } },
    },
}

-- Every public direction has one catalog pool. Props are matched to a
-- direction through their own style lists instead.
for _, gender in ipairs({ 'male', 'female' }) do
    for style in pairs(VALID_STYLES) do
        STYLE_POOLS[gender][style] = STYLE_POOLS[gender][style] or { tops = {}, bottoms = {}, shoes = {} }
    end
end

local BASE_KINDS = {
    tops = { tee_clean = 'tee', tee_graphic = 'tee', polo = 'tee', shirt = 'shirt' },
    bottoms = {
        regular_jeans = 'jeans', ranch_jeans = 'jeans', skinny = 'jeans', rollups = 'jeans', chinos = 'trousers',
        dress_chinos = 'trousers', baggy = 'trousers', suit = 'trousers', cargo = 'cargo', fitted_cargo = 'cargo',
    },
    shoes = {
        canvas = 'sneakers', skate = 'sneakers', sports = 'sneakers', runners = 'sneakers', high_tops = 'sneakers',
        boat = 'smart', oxford = 'smart', round_toed = 'smart', chelsea = 'boots', boots = 'boots', ankle = 'boots',
        combat = 'boots',
    },
}
for _, definitions in pairs(PIECES) do
    for category, kinds in pairs(BASE_KINDS) do
        for pieceId, definition in pairs(definitions[category]) do definition.kind = kinds[pieceId] end
    end
end

local function registerOfficialCatalog()
    if type(AppearanceCatalog) ~= 'table' then return end
    for _, gender in ipairs({ 'male', 'female' }) do
        local catalog = AppearanceCatalog[gender]
        if type(catalog) == 'table' then
            for _, category in ipairs({ 'tops', 'bottoms', 'shoes' }) do
                for _, entry in ipairs(catalog[category] or {}) do
                    local pieceId = ('official_%s_%s'):format(category, entry.id)
                    local variants = { neutral = {}, tonal = {}, varied = {} }
                    for _, palette in ipairs({ 'neutral', 'tonal', 'varied' }) do
                        for _, variant in ipairs(entry.variants[palette] or {}) do
                            if category == 'tops' then
                                variants[palette][#variants[palette] + 1] = upperVariant(variant.name, 0, variant.texture)
                            else
                                local componentId = category == 'bottoms' and 4 or 6
                                variants[palette][#variants[palette] + 1] = clothingVariant(variant.name, componentId, variant.texture)
                            end
                        end
                    end

                    local components
                    if category == 'tops' then
                        components = {
                            [3] = entry.torso,
                            [8] = gender == 'female' and 14 or 15,
                            [11] = entry.drawable,
                        }
                    else
                        components = { [category == 'bottoms' and 4 or 6] = entry.drawable }
                    end
                    PIECES[gender][category][pieceId] = {
                        global = true,
                        kind = entry.kind,
                        components = components,
                        variants = variants,
                    }
                    for _, style in ipairs(entry.styles or {}) do
                        local stylePool = STYLE_POOLS[gender][style]
                        if stylePool then stylePool[category][#stylePool[category] + 1] = pieceId end
                    end
                end
            end
        end
    end
end

registerOfficialCatalog()

-- Complete silhouettes, not the Cartesian product of a broad style tag.
-- Open jackets, suit sets and tall boots with trousers require additional fit
-- rules and stay available in the manual wardrobe instead of these families.
local OUTFIT_FAMILIES = {
    male = {
        { id = 'smart', name = 'Smart separates', styles = { polished = true },
          tops = { 'polo', 'official_tops_loose_polo', 'official_tops_tucked_shirt' },
          bottoms = { 'chinos', 'dress_chinos', 'official_bottoms_slim_fit', 'official_bottoms_smart_regular' },
          shoes = { 'boat', 'chelsea', 'official_shoes_slip_ons', 'official_shoes_leather_loafers' } },
        { id = 'weekend', name = 'Weekend denim', styles = { casual = true, polished = true },
          tops = { 'polo', 'official_tops_loose_polo' },
          bottoms = { 'regular_jeans', 'ranch_jeans', 'official_bottoms_classic_jeans', 'official_bottoms_ribbed_denim' },
          shoes = { 'boat', 'canvas', 'official_shoes_canvas_slip_ons' } },
        { id = 'everyday', name = 'Everyday essentials', styles = { casual = true, street = true },
          tops = { 'tee_clean', 'tee_graphic', 'official_tops_utility_tee', 'official_tops_print_sweater' },
          bottoms = { 'regular_jeans', 'ranch_jeans', 'official_bottoms_loose_jeans', 'official_bottoms_ribbed_denim', 'official_bottoms_roadworn_denim' },
          shoes = { 'canvas', 'skate', 'official_shoes_hi_top_sneakers', 'official_shoes_retro_sneakers' } },
        { id = 'athletic', name = 'Off duty', styles = { casual = true, street = true },
          tops = { 'official_tops_sport_hoodie', 'official_tops_zipped_bomber', 'official_tops_varsity_jacket' },
          bottoms = { 'official_bottoms_tracksuit_pants', 'official_bottoms_modern_tracksuit', 'official_bottoms_loose_jeans' },
          shoes = { 'skate', 'official_shoes_hi_top_sneakers', 'official_shoes_retro_sneakers' } },
        { id = 'utility', name = 'Urban utility', styles = { street = true },
          tops = { 'official_tops_combat_top', 'official_tops_combat_sweater', 'official_tops_utility_tee' },
          bottoms = { 'cargo', 'fitted_cargo', 'official_bottoms_plain_biker', 'official_bottoms_padded_biker' },
          shoes = { 'boots', 'official_shoes_ankle_boots', 'official_shoes_moc_toe_boots' } },
    },
    female = {
        { id = 'smart', name = 'Smart separates', styles = { polished = true },
          tops = { 'shirt', 'polo', 'official_tops_blouse', 'official_tops_rolled_shirt', 'official_tops_work_shirt' },
          bottoms = { 'suit', 'chinos', 'official_bottoms_fitted_chinos', 'official_bottoms_high_waisted' },
          shoes = { 'round_toed', 'ankle', 'official_shoes_patent_heels' } },
        { id = 'weekend', name = 'Weekend denim', styles = { polished = true, casual = true },
          tops = { 'shirt', 'polo', 'official_tops_blouse', 'official_tops_work_shirt' },
          bottoms = { 'skinny', 'rollups', 'official_bottoms_ribbed_denim', 'official_bottoms_roadworn_denim' },
          shoes = { 'canvas', 'ankle', 'round_toed' } },
        { id = 'everyday', name = 'Everyday essentials', styles = { casual = true, street = true },
          tops = { 'tee_clean', 'official_tops_utility_tee', 'official_tops_print_sweater' },
          bottoms = { 'skinny', 'rollups', 'official_bottoms_skinny_cuts', 'official_bottoms_ribbed_denim' },
          shoes = { 'canvas', 'sports', 'runners', 'high_tops' } },
        { id = 'athletic', name = 'Off duty', styles = { casual = true, street = true },
          tops = { 'official_tops_sport_hoodie', 'official_tops_varsity_jacket', 'tee_clean' },
          bottoms = { 'official_bottoms_leggings', 'official_bottoms_tracksuit_pants', 'official_bottoms_modern_tracksuit' },
          shoes = { 'sports', 'runners', 'high_tops' } },
        { id = 'utility', name = 'Urban utility', styles = { street = true },
          tops = { 'official_tops_combat_top', 'official_tops_combat_sweater', 'official_tops_utility_tee' },
          bottoms = { 'cargo', 'official_bottoms_combat_pants', 'official_bottoms_skinny_cuts' },
          shoes = { 'combat', 'ankle', 'high_tops' } },
    },
}

-- Legacy families are fallbacks when the selected build lacks the later collections.
for _, gender in ipairs({ 'male', 'female' }) do
    for _, family in ipairs(OUTFIT_FAMILIES[gender]) do
        family.fallback = true
        if family.id == 'smart' then family.styles.nightlife = true; family.styles.designer = true end
        if family.id == 'weekend' then family.styles.resort = true end
        if family.id == 'athletic' then family.styles.sport = true; family.styles.designer = true end
        if family.id == 'utility' then family.styles.utility = true; family.styles.biker = true end
    end
end

local MODERN_FAMILIES = {
    { id = 'modern_smart', name = 'Modern smart separates', styles = { polished = true },
      tops = { 'official_tops_office', 'official_tops_office_open', 'official_tops_brand_polo' },
      bottoms = { 'official_bottoms_straight_chinos' },
      shoes = { 'official_shoes_smart_oxford', 'official_shoes_buckled' },
    },
    { id = 'soft_tailoring', name = 'Soft tailoring', styles = { polished = true, nightlife = true },
      tops = { 'official_tops_cardigan', 'official_tops_designer_cardigan' },
      bottoms = { 'official_bottoms_straight_chinos' },
      shoes = { 'official_shoes_buckled', 'official_shoes_smart_oxford' },
    },
    { id = 'clean_denim', name = 'Clean denim', styles = { polished = true, casual = true },
      tops = { 'official_tops_chore', 'official_tops_brand_polo' },
      bottoms = { 'official_bottoms_turnups' },
      shoes = { 'official_shoes_buckled', 'official_shoes_low_canvas' },
    },
    { id = 'modern_everyday', name = 'Relaxed layers', styles = { casual = true },
      tops = { 'official_tops_double_shirt', 'official_tops_pullover' },
      bottoms = { 'official_bottoms_turnups', 'official_bottoms_straight_chinos' },
      shoes = { 'official_shoes_knit', 'official_shoes_low_canvas' },
    },
    { id = 'offduty', name = 'Off-duty sweats', styles = { casual = true, sport = true },
      tops = { 'official_tops_pullover', 'official_tops_zipped_bigness' },
      bottoms = { 'official_bottoms_cuffed_sweats' },
      shoes = { 'official_shoes_knit', 'official_shoes_designer_lace' },
    },
    { id = 'chore_denim', name = 'Chore jacket & denim', styles = { casual = true, utility = true },
      tops = { 'official_tops_chore', 'official_tops_double_shirt' },
      bottoms = { 'official_bottoms_turnups' },
      shoes = { 'official_shoes_low_canvas', 'official_shoes_logger' },
    },
    { id = 'sneaker_focus', name = 'Sneaker rotation', styles = { street = true, sport = true, designer = true },
      tops = { 'official_tops_pullover', 'official_tops_zipped_bigness' },
      bottoms = { 'official_bottoms_cuffed_sweats', 'official_bottoms_snap_joggers' },
      shoes = { 'official_shoes_knit', 'official_shoes_designer_lace' },
      accent = 'shoes',
    },
    { id = 'oversized', name = 'Volume & layers', styles = { street = true, designer = true },
      tops = { 'official_tops_brand_hoodie', 'official_tops_broker_puffer' },
      bottoms = { 'official_bottoms_large_cargo', 'official_bottoms_cuffed_sweats' },
      shoes = { 'official_shoes_knit', 'official_shoes_designer_lace' },
    },
    { id = 'racing_street', name = 'Pit lane streetwear', styles = { street = true, biker = true },
      tops = { 'official_tops_racing', 'official_tops_retro_racing' },
      bottoms = { 'official_bottoms_chain', 'official_bottoms_turnups' },
      shoes = { 'official_shoes_low_canvas', 'official_shoes_knit' },
    },
    { id = 'urban_utility', name = 'Technical layers', styles = { street = true, utility = true },
      tops = { 'official_tops_waterproof', 'official_tops_field_blouson' },
      bottoms = { 'official_bottoms_large_cargo' },
      shoes = { 'official_shoes_logger' },
    },
    { id = 'training', name = 'Training day', styles = { sport = true },
      tops = { 'official_tops_track_top', 'official_tops_pullover' },
      bottoms = { 'official_bottoms_snap_joggers', 'official_bottoms_cuffed_sweats' },
      shoes = { 'official_shoes_knit' },
    },
    { id = 'track', name = 'Track separates', styles = { sport = true },
      tops = { 'official_tops_track_top' },
      bottoms = { 'official_bottoms_track', 'official_bottoms_cuffed_sweats' },
      shoes = { 'official_shoes_knit', 'official_shoes_designer_lace' },
    },
    { id = 'field', name = 'Field gear', styles = { utility = true },
      tops = { 'official_tops_field_blouson', 'official_tops_waterproof' },
      bottoms = { 'official_bottoms_large_cargo' },
      shoes = { 'official_shoes_logger' },
    },
    { id = 'workwear', name = 'Workshop layers', styles = { utility = true },
      tops = { 'official_tops_chore', 'official_tops_double_shirt' },
      bottoms = { 'official_bottoms_straight_chinos', 'official_bottoms_large_cargo' },
      shoes = { 'official_shoes_logger' },
    },
    { id = 'leather', name = 'Road leathers', styles = { biker = true },
      tops = { 'official_tops_light_biker', 'official_tops_leather_bomber' },
      bottoms = { 'official_bottoms_leather_stitch', 'official_bottoms_laced_leather' },
      shoes = { 'official_shoes_road' },
    },
    { id = 'motorsport', name = 'Motorsport', styles = { biker = true },
      tops = { 'official_tops_racing', 'official_tops_retro_racing' },
      bottoms = { 'official_bottoms_chain' },
      shoes = { 'official_shoes_road', 'official_shoes_low_canvas' },
    },
    { id = 'coastal', name = 'Coastal prints', styles = { resort = true },
      tops = { 'official_tops_revere', 'official_tops_botanical', 'official_tops_palms' },
      bottoms = { 'official_bottoms_beach_shorts', 'official_bottoms_jean_shorts' },
      shoes = { 'official_shoes_pool_sliders', 'official_shoes_low_canvas' },
    },
    { id = 'boardwalk', name = 'Boardwalk club', styles = { resort = true },
      tops = { 'official_tops_brand_polo', 'official_tops_revere' },
      bottoms = { 'official_bottoms_beach_shorts' },
      shoes = { 'official_shoes_buckled', 'official_shoes_low_canvas' },
    },
    { id = 'afterdark', name = 'After dark', styles = { nightlife = true },
      tops = { 'official_tops_light_biker', 'official_tops_revere', 'official_tops_office_open' },
      bottoms = { 'official_bottoms_laced_leather', 'official_bottoms_straight_chinos' },
      shoes = { 'official_shoes_buckled', 'official_shoes_smart_oxford' },
    },
    { id = 'club_knit', name = 'Late-night knitwear', styles = { nightlife = true, designer = true },
      tops = { 'official_tops_designer_cardigan', 'official_tops_cardigan', 'official_tops_casino_bomber' },
      bottoms = { 'official_bottoms_wide_designer', 'official_bottoms_straight_chinos' },
      shoes = { 'official_shoes_buckled', 'official_shoes_smart_oxford' },
    },
    { id = 'label_layers', name = 'Statement labels', styles = { designer = true },
      tops = { 'official_tops_designer_cardigan', 'official_tops_casino_bomber', 'official_tops_broker_puffer' },
      bottoms = { 'official_bottoms_wide_designer' },
      shoes = { 'official_shoes_designer_lace', 'official_shoes_buckled' },
    },
    { id = 'luxury_sport', name = 'Designer sportswear', styles = { designer = true },
      tops = { 'official_tops_brand_hoodie', 'official_tops_zipped_bigness' },
      bottoms = { 'official_bottoms_cuffed_sweats', 'official_bottoms_snap_joggers' },
      shoes = { 'official_shoes_designer_lace', 'official_shoes_knit' },
    },
}
for _, gender in ipairs({ 'male', 'female' }) do
    for _, family in ipairs(MODERN_FAMILIES) do
        OUTFIT_FAMILIES[gender][#OUTFIT_FAMILIES[gender] + 1] = family
    end
end

local function official(category, ...)
    local ids = {}
    for index, id in ipairs({ ... }) do ids[index] = ('official_%s_%s'):format(category, id) end
    return ids
end

-- Families shared by both bodies. IDs a body does not have are skipped, and a
-- family that ends up without tops, bottoms or shoes for a body is not offered
-- to it, so skirt and heel families stay with the female body. Knee-high boots
-- only meet skirts and shorts.
local EXPANDED_FAMILIES = {
    { id = 'city_knit', name = 'City knitwear', styles = { polished = true, nightlife = true },
      tops = official('tops', 'crew_sweater', 'turtleneck', 'vneck_sweater'),
      bottoms = official('bottoms', 'straight_chinos', 'beach_chinos', 'slacks'),
      shoes = official('shoes', 'smart_oxford', 'buckled', 'oxford_ankle', 'classic_heels') },
    { id = 'tailored_outerwear', name = 'Tailored outerwear', styles = { polished = true },
      tops = official('tops', 'cashmere_coat', 'pocket_jacket', 'boating_blazer', 'leather_field'),
      bottoms = official('bottoms', 'straight_chinos', 'beach_chinos', 'slacks'),
      shoes = official('shoes', 'smart_oxford', 'oxford_ankle', 'buckled', 'classic_platforms') },
    { id = 'flannel', name = 'Weekend flannel', styles = { casual = true, utility = true },
      tops = official('tops', 'cross_check', 'quilted_jacket', 'work_shirt'),
      bottoms = official('bottoms', 'turnups', 'fitted_jeans', 'cropped_jeans', 'ribbed_denim'),
      shoes = official('shoes', 'moc_toe_boots', 'walking_boots', 'low_canvas', 'sheepskin_boots') },
    { id = 'denim_jacket', name = 'Denim jacket', styles = { casual = true, street = true },
      tops = official('tops', 'denim_biker', 'denim_jacket'),
      bottoms = official('bottoms', 'turnups', 'fitted_jeans', 'ribbed_denim', 'cropped_jeans'),
      shoes = official('shoes', 'kicks', 'low_canvas', 'retro_sneakers', 'backside') },
    { id = 'gym', name = 'Gym kit', styles = { sport = true },
      tops = official('tops', 'sports_long_sleeve', 'tracksuit_top'),
      bottoms = official('bottoms', 'running_shorts', 'jogging_shorts', 'sport_shorts', 'basketball_shorts', 'camo_leggings', 'leggings'),
      shoes = official('shoes', 'athletic_shoes', 'sports_shoes', 'court_sneakers', 'cross_trainers', 'knit') },
    { id = 'tracksuit', name = 'Classic tracksuit', styles = { sport = true, street = true },
      tops = official('tops', 'tracksuit_top'),
      bottoms = official('bottoms', 'tracksuit_pants', 'track_pants', 'sweatpants'),
      shoes = official('shoes', 'retro_runners', 'kicks', 'court_sneakers', 'backside') },
    { id = 'skate', name = 'Skate park', styles = { street = true },
      tops = official('tops', 'baggy_tee', 'crewneck_tee', 'hippy_hoodie', 'classic_tee'),
      bottoms = official('bottoms', 'low_crotch_shorts', 'chain_shorts', 'loose_jeans', 'cargo_shorts'),
      shoes = official('shoes', 'kicks', 'hi_top_69', 'retro_runners', 'backside') },
    { id = 'cold_weather', name = 'Cold weather', styles = { street = true, utility = true },
      tops = official('tops', 'puffer', 'utility_bomber', 'longline_hoodie'),
      bottoms = official('bottoms', 'large_cargo', 'combat_pants', 'camo_chinos'),
      shoes = official('shoes', 'winter_boots', 'desert_boots', 'work_boots', 'sheepskin_boots') },
    { id = 'work_site', name = 'Work site', styles = { utility = true },
      tops = official('tops', 'work_shirt', 'cross_check', 'quilted_jacket'),
      bottoms = official('bottoms', 'work_pants', 'utility_pants', 'knee_pad_cargo', 'cargo_shorts'),
      shoes = official('shoes', 'work_boots', 'logger', 'winter_boots', 'desert_boots') },
    { id = 'classic_biker', name = 'Classic biker', styles = { biker = true },
      tops = official('tops', 'classic_biker', 'blouson', 'racer', 'fitted_racer'),
      bottoms = official('bottoms', 'leather_stitch', 'laced_leather', 'raider_pants', 'ribbed_leather', 'leather_zippers_color'),
      shoes = official('shoes', 'harness_boots', 'cowboy_boots', 'raider_boots', 'road') },
    { id = 'clubhouse', name = 'Clubhouse', styles = { polished = true, resort = true, sport = true },
      tops = official('tops', 'golf_polo'),
      bottoms = official('bottoms', 'beach_chinos', 'chino_shorts', 'straight_chinos'),
      shoes = official('shoes', 'buckled', 'low_canvas') },
    { id = 'beach_day', name = 'Beach day', styles = { resort = true },
      tops = official('tops', 'shortsleeve', 'garland_shortsleeve', 'crewneck_tee', 'untucked_rolled_shirt', 'classic_tee'),
      bottoms = official('bottoms', 'board_shorts', 'beach_boards', 'sport_shorts', 'summer_shorts', 'casual_shorts', 'beach_shorts_print'),
      shoes = official('shoes', 'flip_flops', 'beach_flip_flops', 'print_flip_flops', 'coin_sliders', 'sandals') },
    { id = 'leather_night', name = 'Leather after dark', styles = { nightlife = true },
      tops = official('tops', 'popped_leather', 'fashion_biker', 'padded_leather', 'satin_jacket'),
      bottoms = official('bottoms', 'leather_jeans', 'laced_leather', 'slacks', 'leather_stitch'),
      shoes = official('shoes', 'oxford_ankle', 'smart_oxford', 'strappy_heels', 'classic_heels') },
    { id = 'logo_season', name = 'Logo season', styles = { designer = true },
      tops = official('tops', 'bigness_vneck', 'diamond_hoodie', 'pattern_sweater'),
      bottoms = official('bottoms', 'blagueurs_sweats', 'wide_designer', 'hipster_fitted'),
      shoes = official('shoes', 'zebra_sneakers', 'print_canvas', 'slipper_loafers', 'coin_sliders') },
    { id = 'varsity', name = 'Varsity', styles = { street = true, casual = true, sport = true },
      tops = official('tops', 'baseball_jacket', 'varsity_jacket', 'satin_jacket'),
      bottoms = official('bottoms', 'track_pants', 'loose_jeans', 'cuffed_sweats', 'fitted_jeans'),
      shoes = official('shoes', 'kicks', 'hi_top_69', 'retro_sneakers', 'court_sneakers') },
    { id = 'office_skirt', name = 'Office skirt', styles = { polished = true },
      tops = official('tops', 'blouse', 'silk_blouse', 'work_shirt', 'tucked_rolled_shirt', 'frill_shirt', 'turtleneck'),
      bottoms = official('bottoms', 'pencil_classic', 'pencil_skirt', 'panel_pencil'),
      shoes = official('shoes', 'classic_heels', 'rounded_heels', 'classic_platforms', 'patent_heels') },
    { id = 'night_out', name = 'Night out', styles = { nightlife = true },
      tops = official('tops', 'frill_shirt', 'silk_blouse', 'popped_leather', 'cropped_biker', 'satin_jacket'),
      bottoms = official('bottoms', 'mini_skirt', 'designer_mini', 'leather_zippers'),
      shoes = official('shoes', 'strappy_heels', 'patent_heels', 'rounded_heels', 'knee_high_classic', 'riding_boots') },
    { id = 'skirt_day', name = 'Skirt and sneakers', styles = { casual = true, street = true, resort = true },
      tops = official('tops', 'crewneck_tee', 'classic_tee', 'loose_tank', 'shortsleeve', 'denim_jacket'),
      bottoms = official('bottoms', 'denim_skirt', 'pleated_skirt', 'mini_skirt'),
      shoes = official('shoes', 'canvas_snugs', 'backside', 'platforms', 'sandals', 'knee_high_classic') },
    { id = 'summer_shorts', name = 'Summer shorts', styles = { casual = true, resort = true },
      tops = official('tops', 'classic_tee', 'loose_tank', 'shortsleeve', 'golf_polo', 'crewneck_tee'),
      bottoms = official('bottoms', 'chino_shorts', 'summer_shorts', 'casual_shorts', 'city_shorts', 'jean_shorts', 'denim_shorts'),
      shoes = official('shoes', 'sandals', 'flip_flops', 'canvas_snugs', 'low_canvas', 'dlc_canvas') },
}
for _, gender in ipairs({ 'male', 'female' }) do
    for _, family in ipairs(EXPANDED_FAMILIES) do
        OUTFIT_FAMILIES[gender][#OUTFIT_FAMILIES[gender] + 1] = family
    end
end

-- Base tops also need a bare undershirt, not a second visible copy of a tee.
for gender, definitions in pairs(PIECES) do
    for _, definition in pairs(definitions.tops) do
        definition.components[8] = gender == 'female' and 14 or 15
        for _, variants in pairs(definition.variants) do
            for _, variant in ipairs(variants) do variant.textures[8] = 0 end
        end
    end
end

-- Kit pieces carry no curated variants: their colorways come from the
-- generated texture names at materialization time. They register after the
-- bare-undershirt pass so a scuba tank keeps its own undershirt slot.
local FOCAL_COMPONENTS = { tops = 11, bottoms = 4, shoes = 6 }
local function registerKits()
    if type(AppearanceKits) ~= 'table' then return end
    for _, gender in ipairs({ 'male', 'female' }) do
        local definitions = PIECES[gender]
        definitions.gear, definitions.headgear, definitions.eyewear = {}, {}, {}
        for _, entry in ipairs(AppearanceKits[gender] or {}) do
            local pieceId = ('kit_%s_%s'):format(entry.category, entry.id)
            if entry.category == 'headgear' or entry.category == 'eyewear' then
                definitions[entry.category][pieceId] = {
                    kind = entry.category, prop = entry.prop, drawable = entry.drawable,
                    global = not entry.base, name = entry.name,
                }
            else
                local focal = FOCAL_COMPONENTS[entry.category] or entry.component
                local components = { [focal] = entry.drawable }
                if entry.category == 'tops' then
                    components[3] = entry.torso
                    components[8] = entry.undershirt or (gender == 'female' and 14 or 15)
                end
                local linked = nil
                for _, componentId in ipairs(entry.linked or {}) do
                    linked = linked or {}
                    linked[componentId] = true
                end
                definitions[entry.category][pieceId] = {
                    global = true, generated = true, kind = entry.kind or entry.category, name = entry.name,
                    components = components, focal = focal, linked = linked,
                }
            end
        end
    end
end

registerKits()

local function appendFamilies(families)
    for _, gender in ipairs({ 'male', 'female' }) do
        for _, family in ipairs(families or {}) do
            OUTFIT_FAMILIES[gender][#OUTFIT_FAMILIES[gender] + 1] = family
        end
    end
end

if type(AppearanceKits) == 'table' then
    appendFamilies(AppearanceKits.statementFamilies)
    appendFamilies(AppearanceKits.families)
end

local function finiteInteger(value, minimum, maximum)
    if type(value) ~= 'number' and type(value) ~= 'string' then return nil end
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge or number ~= math.floor(number) then return nil end
    if minimum and number < minimum then return nil end
    if maximum and number > maximum then return nil end
    return number
end

local function enumValue(value, allowed, fallback)
    if type(value) ~= 'string' or #value > 24 then return fallback end
    value = value:lower()
    return allowed[value] and value or fallback
end

-- Older clients sent a boolean accessory switch; true meant one prop.
local function accessoryLevel(value)
    if value == true then return 'minimal' end
    return enumValue(value, VALID_ACCESSORIES, 'none')
end

function AppearanceRandomizer.sanitizeOptions(raw)
    raw = type(raw) == 'table' and raw or {}
    return {
        mode = enumValue(raw.mode, VALID_MODES, 'outfit'), style = enumValue(raw.style, VALID_STYLES, 'polished'),
        gender = enumValue(raw.gender, VALID_GENDERS, 'keep'), hairTone = enumValue(raw.hairTone, VALID_HAIR_TONES, 'any'),
        palette = enumValue(raw.palette, VALID_PALETTES, 'neutral'),
        faceProfile = enumValue(raw.faceProfile, VALID_FACE_PROFILES, 'everyday'),
        ageProfile = enumValue(raw.ageProfile, VALID_AGE_PROFILES, 'young'),
        complexion = enumValue(raw.complexion, VALID_COMPLEXIONS, 'clean'),
        hairStyle = enumValue(raw.hairStyle, VALID_HAIR_STYLES, 'any'),
        makeup = enumValue(raw.makeup, VALID_MAKEUP, 'subtle'),
        topType = enumValue(raw.topType, VALID_TOP_TYPES, 'any'),
        bottomType = enumValue(raw.bottomType, VALID_BOTTOM_TYPES, 'any'),
        footwear = enumValue(raw.footwear, VALID_FOOTWEAR, 'any'),
        headwear = enumValue(raw.headwear, VALID_HEADWEAR, 'none'),
        accessories = accessoryLevel(raw.accessories),
        facialHair = enumValue(raw.facialHair, VALID_FACIAL_HAIR, 'any'),
        eyeColor = enumValue(raw.eyeColor, VALID_EYE_COLORS, 'natural'),
        faceVariation = enumValue(raw.faceVariation, VALID_FACE_VARIATION, 'balanced'),
        highlights = enumValue(raw.highlights, VALID_HIGHLIGHTS, 'natural'),
    }
end

function AppearanceRandomizer.isNaturalHairRgb(red, green, blue)
    red, green, blue = finiteInteger(red, 0, 255), finiteInteger(green, 0, 255), finiteInteger(blue, 0, 255)
    if not red or not green or not blue then return false end
    local maximum, minimum = math.max(red, green, blue), math.min(red, green, blue)
    local spread = maximum - minimum
    local neutral = spread <= 24 and maximum <= 230
    local warm = red >= green and green >= blue and red <= 238 and spread <= 175 and (red < 48 or green >= 18) and (red < 58 or blue >= 5)
    return neutral or warm
end

local function luminance(entry)
    return (entry.r * 0.2126) + (entry.g * 0.7152) + (entry.b * 0.0722)
end

local function matchesTone(entry, tone)
    local value = luminance(entry)
    if tone == 'dark' then return value <= 82 end
    if tone == 'light' then return value >= 128 end
    if tone == 'warm' then return entry.r >= entry.g + 7 and value > 45 and value < 170 end
    if tone == 'gray' then
        return math.max(entry.r, entry.g, entry.b) - math.min(entry.r, entry.g, entry.b) <= 24 and value >= 70
    end
    return true
end

local function paletteEntries(entries)
    local valid = {}
    if type(entries) ~= 'table' then return valid end
    for _, entry in ipairs(entries) do
        if type(entry) == 'table' then
            local index = finiteInteger(entry.index, 0, 255)
            local red, green, blue = finiteInteger(entry.r, 0, 255), finiteInteger(entry.g, 0, 255), finiteInteger(entry.b, 0, 255)
            if index and red and green and blue then valid[#valid + 1] = { index = index, r = red, g = green, b = blue } end
        end
    end
    return valid
end

function AppearanceRandomizer.filterNaturalHairColors(entries, tone)
    tone = VALID_HAIR_TONES[tone] and tone or 'any'
    local natural, toned = {}, {}
    for _, color in ipairs(paletteEntries(entries)) do
        if AppearanceRandomizer.isNaturalHairRgb(color.r, color.g, color.b) then
            natural[#natural + 1] = color
            if matchesTone(color, tone) then toned[#toned + 1] = color end
        end
    end
    if #toned > 0 then return toned end
    if #natural > 0 then return natural end
    return { { index = 0, r = 0, g = 0, b = 0 } }
end

-- Fashion picks clearly dyed shades; every other tone stays natural.
function AppearanceRandomizer.filterHairColors(entries, tone)
    if tone ~= 'fashion' then return AppearanceRandomizer.filterNaturalHairColors(entries, tone) end
    local dyed = {}
    for _, color in ipairs(paletteEntries(entries)) do
        local spread = math.max(color.r, color.g, color.b) - math.min(color.r, color.g, color.b)
        if spread >= 60 and not AppearanceRandomizer.isNaturalHairRgb(color.r, color.g, color.b) then dyed[#dyed + 1] = color end
    end
    if #dyed > 0 then return dyed end
    return AppearanceRandomizer.filterNaturalHairColors(entries, 'any')
end

-- Lipstick keeps reds, berries, pinks and nudes; blush keeps soft pinks and
-- peach. Live palette rows come from the makeup colour natives.
function AppearanceRandomizer.filterCosmeticColors(entries, kind)
    local matches = {}
    for _, color in ipairs(paletteEntries(entries)) do
        local value = luminance(color)
        local accepted
        if kind == 'blush' then
            accepted = color.r >= color.g + 20 and color.r >= color.b and value >= 70 and value <= 200
        else
            accepted = color.r >= color.g + 25 and color.r + 10 >= color.b and value >= 30 and value <= 185
        end
        if accepted then matches[#matches + 1] = color end
    end
    if #matches > 0 then return matches end
    return { { index = 0, r = 0, g = 0, b = 0 } }
end

function AppearanceRandomizer.getEyeColorPool(eyeColor)
    local pool = {}
    for index, color in ipairs(EYE_COLORS[eyeColor] or EYE_COLORS.natural) do pool[index] = color end
    return pool
end

-- Texture names from shared/appearance_textures.lua are sorted into the same
-- three palettes as the curated variants by their color words. A bright word
-- anywhere wins, so Restrained never picks up an accent. Names without any
-- color word are prints or logos and count as Mixed.
local function wordSet(words)
    local set = {}
    for word in words:gmatch('%S+') do set[word] = true end
    return set
end

local VARIED_WORDS = wordSet([[red pink purple orange yellow lime neon magenta cyan aqua lilac lavender violet
    mint peach salmon coral fuchsia crimson scarlet gold golden turquoise tangerine mustard lemon candy rainbow
    leopard zebra tiger snake snakeskin python cheetah floral flower flowers blossom blooming botanical tropical
    palms palm splatter splat tie dye tie-dye glitch contrast bright pastel pastels multi fruit flame flames cherry berry
    rose plum blush apricot lobster banana flamingo hot primary vivid electric acid fluorescent luminous sunset
    paisley tartan argyle stars stripes usa union jack skull skulls dice zigzag swirl psychedelic graffiti
    comic cartoon emoji heart hearts magma lava ocean vines baroque ornate pink-tint orange-tint amethyst
    sapphire emerald ruby champagne copper-tint bronze-tint burgundy-tint tortoiseshell marble dazzle]])
local TONAL_WORDS = wordSet([[navy blue indigo denim olive khaki tan beige brown chocolate coffee mocha chestnut
    camel sand taupe wheat umber sienna russet tawny walnut maroon burgundy wine forest moss sage earth fawn
    chamois bronze copper teal sky dusk rust desert woodland digital camo flecktarn splinter crosshatch
    brushstroke cobble fall green hunter military army toffee caramel cocoa latte ochre mahogany oxblood
    bordeaux petrol jungle field tundra autumn hazel nut brick terracotta clay cinnamon honey amber leather
    suede tweed corduroy plaid check houndstooth hound herringbone pinstripe gingham]])
local NEUTRAL_WORDS = wordSet([[black white gray grey charcoal ash slate ice stone ivory cream smoke graphite silver
    pewter steel midnight onyx obsidian grayscale mono monochrome chalk off-white offwhite carbon jet noir bone
    ecru oatmeal putty metal platinum nickel gunmetal ink coal shadow light dark plain classic washed faded worn
    dirty two-tone tonal neutral natural nude oat flint frost snow pearl concrete urban]])

local function toneOf(label)
    local text = label:lower()
    local tonal, neutral = false, false
    for word in text:gmatch('[%a][%a%-]*') do
        if VARIED_WORDS[word] then return 'varied' end
        tonal = tonal or TONAL_WORDS[word] == true
        neutral = neutral or NEUTRAL_WORDS[word] == true
    end
    if tonal then return 'tonal' end
    if neutral then return 'neutral' end
    return 'varied'
end

local function splitWords(label)
    local words = {}
    for word in label:gmatch('%S+') do words[#words + 1] = word end
    return words
end

-- The trailing words every named texture of a drawable shares are the
-- garment noun ("Combat Shirt"); what precedes it is the colorway, which is
-- also the pattern key kits match across pieces.
local function garmentNoun(labels)
    local first, shared = nil, nil
    for _, label in ipairs(labels) do
        local words = splitWords(label)
        if not first then
            first, shared = words, #words
        else
            local count = 0
            while count < shared and count < #words
                and words[#words - count]:lower() == first[#first - count]:lower() do
                count = count + 1
            end
            shared = count
        end
    end
    if not first or #labels < 2 then return {}, 0 end
    local noun = {}
    for index = #first - shared + 1, #first do noun[#noun + 1] = first[index] end
    return noun, shared
end

local textureCache = { component = {}, prop = {} }

-- One entry per texture: { texture, name, tone, pattern }. Unnamed textures
-- have no name or tone and are only used by Full range and unlabeled kits.
local function textureEntries(gender, kind, slot, drawable)
    local source = type(AppearanceTextures) == 'table' and AppearanceTextures or nil
    local labels = source and (kind == 'prop' and source.props and source.props[gender] or source[gender])
    labels = labels and labels[slot] and labels[slot][drawable]
    if type(labels) ~= 'table' then return nil end
    local key = ('%s:%d:%d'):format(gender, slot, drawable)
    if textureCache[kind][key] then return textureCache[kind][key] end

    local named = {}
    for _, label in ipairs(labels) do
        if type(label) == 'string' then named[#named + 1] = label end
    end
    local noun, shared = garmentNoun(named)
    local entries = { noun = table.concat(noun, ' ') }
    for index, label in ipairs(labels) do
        local entry = { texture = index - 1 }
        if type(label) == 'string' then
            local words = splitWords(label)
            local stem = {}
            for word = 1, math.max(1, #words - shared) do stem[#stem + 1] = words[word] end
            entry.name = label
            entry.tone = toneOf(table.concat(stem, ' '))
            entry.pattern = table.concat(stem, ' '):lower()
        end
        entries[#entries + 1] = entry
    end
    textureCache[kind][key] = entries
    return entries
end

local function entryName(entries, entry, fallbackName)
    if entry.name then return entry.name end
    local base = fallbackName or (entries.noun ~= '' and entries.noun) or 'Colorway'
    return ('%s, colorway %d'):format(base, entry.texture + 1)
end

-- A one-word earthy colorway (Moss, Sand, Navy) is the quietest stand-in
-- when a piece has no neutral texture at all.
local QUIET_TONAL_WORDS = wordSet('moss sand olive khaki tan beige navy brown chocolate coffee mocha taupe earth desert sage')
local function plainTonal(entry)
    return entry.tone == 'tonal' and entry.pattern ~= nil and QUIET_TONAL_WORDS[entry.pattern] == true
end

-- Alternatives for one palette, keeping `first` (the curated texture) in
-- front so deterministic choosers and the curated name stay stable.
local function textureAlternatives(entries, palette, first, firstName, fallbackName)
    if type(entries) ~= 'table' then return nil end
    local alternatives, seen = {}, {}
    local function add(entry, name)
        if seen[entry.texture] then return end
        seen[entry.texture] = true
        alternatives[#alternatives + 1] = {
            texture = entry.texture, name = name or entryName(entries, entry, fallbackName), pattern = entry.pattern,
        }
    end
    if first and entries[first + 1] then add(entries[first + 1], firstName) end
    for _, entry in ipairs(entries) do
        if palette == 'full' or (entry.name and entry.tone == palette) then add(entry) end
    end
    if palette == 'neutral' and #alternatives < 2 then
        for _, entry in ipairs(entries) do
            if plainTonal(entry) then add(entry) end
        end
    end
    return #alternatives > 1 and alternatives or nil
end

local function pieceComponents(definition, textures, texture, global)
    local components = {}
    for componentId, drawable in pairs(definition.components) do
        local component = { component = componentId, texture = textures and textures[componentId] or 0 }
        if texture and (componentId == definition.focal or (definition.linked and definition.linked[componentId])) then
            component.texture = texture
        end
        if global then
            component.globalDrawable = drawable
        else
            component.collection = BASE_GAME_COLLECTION
            component.drawable = drawable
        end
        components[#components + 1] = component
    end
    table.sort(components, function(left, right) return left.component < right.component end)
    return components
end

-- Curated pieces list their reviewed variants for a palette; Full range
-- joins all three. Generated (kit) pieces pick the first colorway of the
-- palette, falling back to Restrained, any name, then texture zero.
local function curatedVariants(definition, palette, focal)
    if palette ~= 'full' then return definition.variants[palette] or definition.variants.neutral end
    local merged, seen = {}, {}
    for _, name in ipairs({ 'neutral', 'tonal', 'varied' }) do
        for _, variant in ipairs(definition.variants[name] or {}) do
            local key = focal and variant.textures[focal] or variant.texture
            if not seen[key] then seen[key] = true; merged[#merged + 1] = variant end
        end
    end
    return merged
end

local function generatedRepresentative(entries, palette)
    if type(entries) ~= 'table' then return nil end
    for _, wanted in ipairs({ palette, 'neutral' }) do
        for _, entry in ipairs(entries) do
            if wanted == 'full' or (entry.name and entry.tone == wanted) then return entry end
        end
        if wanted == 'neutral' then
            for _, entry in ipairs(entries) do
                if plainTonal(entry) then return entry end
            end
        end
    end
    for _, entry in ipairs(entries) do
        if entry.name then return entry end
    end
    return entries[1]
end

local function materializeClothingPiece(gender, category, pieceId, definition, palette)
    local focal = definition.focal or FOCAL_COMPONENTS[category]
    local drawable = definition.components[focal]
    local entries = drawable and textureEntries(gender, 'component', focal, drawable)
    local pieces = {}
    local function add(variantIndex, name, textures, texture, firstName)
        local alternatives = textureAlternatives(entries, palette, texture, firstName, definition.name)
        pieces[#pieces + 1] = {
            id = ('%s-%s-%d'):format(pieceId, palette, variantIndex), name = name, model = pieceId,
            kind = definition.kind, focal = focal, linked = definition.linked, texture = texture,
            pattern = entries and texture and entries[texture + 1] and entries[texture + 1].pattern or nil,
            alternatives = alternatives,
            components = pieceComponents({ components = definition.components, focal = focal, linked = definition.linked },
                textures, definition.generated and texture or nil, definition.global),
        }
    end
    if definition.generated then
        local entry = generatedRepresentative(entries, palette) or { texture = 0 }
        add(1, entries and entryName(entries, entry, definition.name) or definition.name, nil, entry.texture)
        return pieces
    end
    for variantIndex, variant in ipairs(curatedVariants(definition, palette, focal)) do
        add(variantIndex, variant.name, variant.textures, variant.textures[focal] or 0, variant.name)
    end
    return pieces
end

local function materializeAccessory(gender, pieceId, definition, palette)
    local entries = textureEntries(gender, 'prop', definition.prop, definition.drawable)
    local pieces = {}
    local function add(variantIndex, name, texture)
        pieces[#pieces + 1] = {
            id = ('%s-%s-%d'):format(pieceId, palette, variantIndex), name = name, kind = definition.kind,
            prop = definition.prop, texture = texture, model = pieceId,
            collection = not definition.global and BASE_GAME_COLLECTION or nil,
            drawable = not definition.global and definition.drawable or nil,
            globalDrawable = definition.global and definition.drawable or nil,
            pattern = entries and entries[texture + 1] and entries[texture + 1].pattern or nil,
            alternatives = textureAlternatives(entries, palette, texture, name, definition.name),
        }
    end
    if not definition.variants then
        local entry = generatedRepresentative(entries, palette) or { texture = 0 }
        add(1, entries and entryName(entries, entry, definition.name) or definition.name, entry.texture)
        return pieces
    end
    for variantIndex, variant in ipairs(curatedVariants(definition, palette)) do
        add(variantIndex, variant.name, variant.texture)
    end
    return pieces
end

local ACCESSORY_KINDS = { watch = true, glasses = true }
local HEADWEAR_KINDS = {
    any = { cap = true, beanie = true, hat = true },
    cap = { cap = true }, beanie = { beanie = true }, hat = { hat = true },
}

local function propSuitsStyle(definition, style)
    if type(definition.styles) ~= 'table' then return true end
    for _, allowed in ipairs(definition.styles) do
        if allowed == style then return true end
    end
    return false
end

-- Props tagged for the direction come first; any prop of the kind is the
-- fallback so an explicit request is never silently dropped.
local function propPool(gender, style, palette, kinds)
    local definitions, ids = PIECES[gender].accessories, {}
    for pieceId, definition in pairs(definitions) do
        if kinds[definition.kind] then ids[#ids + 1] = pieceId end
    end
    table.sort(ids)
    local styled, anyStyle = {}, {}
    for _, pieceId in ipairs(ids) do
        for _, piece in ipairs(materializeAccessory(gender, pieceId, definitions[pieceId], palette)) do
            anyStyle[#anyStyle + 1] = piece
            if propSuitsStyle(definitions[pieceId], style) then styled[#styled + 1] = piece end
        end
    end
    return #styled > 0 and styled or anyStyle
end

local function normalizeScope(gender, style, palette)
    return gender == 'female' and 'female' or 'male', VALID_STYLES[style] and style or 'polished',
        VALID_PALETTES[palette] and palette or 'neutral'
end

function AppearanceRandomizer.getHeadwearPool(gender, style, palette, headwear)
    local kinds = HEADWEAR_KINDS[headwear]
    if not kinds then return {} end
    gender, style, palette = normalizeScope(gender, style, palette)
    return propPool(gender, style, palette, kinds)
end

function AppearanceRandomizer.getPiecePools(gender, style, palette)
    gender, style, palette = normalizeScope(gender, style, palette)
    local definitions, stylePool = PIECES[gender], STYLE_POOLS[gender][style]
    local pools = { tops = {}, bottoms = {}, shoes = {}, accessories = {} }
    for _, category in ipairs({ 'tops', 'bottoms', 'shoes' }) do
        -- Mixed outfits vary the focal top while keeping pants and shoes in the
        -- neutral pool. This prevents three independently saturated pieces.
        local piecePalette = palette == 'varied' and category ~= 'tops' and 'neutral' or palette
        for _, pieceId in ipairs(stylePool[category]) do
            for _, piece in ipairs(materializeClothingPiece(gender, category, pieceId, definitions[category][pieceId], piecePalette)) do
                pools[category][#pools[category] + 1] = piece
            end
        end
    end
    pools.accessories = propPool(gender, style, palette, ACCESSORY_KINDS)
    return pools
end

local function kindFilters(options)
    options = type(options) == 'table' and options or {}
    local filters = {}
    for category, filter in pairs(CATEGORY_FILTERS) do
        local value = options[filter.key]
        if value ~= 'any' and filter.valid[value] then filters[category] = value end
    end
    return filters
end

local function familyPieceIds(gender, category, family)
    local ids = {}
    local definitions = PIECES[gender][category] or {}
    for _, id in ipairs(family[category] or {}) do
        if definitions[id] then ids[#ids + 1] = id end
    end
    return ids
end

local function materializeKitProps(gender, category, ids, palette)
    local pool = {}
    for _, id in ipairs(ids) do
        for _, piece in ipairs(materializeAccessory(gender, id, PIECES[gender][category][id], palette)) do pool[#pool + 1] = piece end
    end
    return pool
end

local function materializeIds(gender, category, ids, palette, kind)
    local pool = {}
    for _, id in ipairs(ids) do
        local definition = PIECES[gender][category][id]
        if not kind or definition.kind == kind then
            for _, piece in ipairs(materializeClothingPiece(gender, category, id, definition, palette)) do pool[#pool + 1] = piece end
        end
    end
    return pool
end

-- Pieces of a kind that some family already approved: the direction's own
-- families first, then every family for the body.
local function approvedIdsOfKind(gender, category, kind, style)
    local styled, anyStyle, seenStyled, seenAny = {}, {}, {}, {}
    for _, family in ipairs(OUTFIT_FAMILIES[gender]) do
        for _, id in ipairs(family.kit and {} or familyPieceIds(gender, category, family)) do
            if PIECES[gender][category][id].kind == kind then
                if not seenAny[id] then seenAny[id] = true; anyStyle[#anyStyle + 1] = id end
                if family.styles[style] and not seenStyled[id] then seenStyled[id] = true; styled[#styled + 1] = id end
            end
        end
    end
    return #styled > 0 and styled or anyStyle
end

-- A family keeps its silhouette when it already has the requested kinds. When
-- it lacks one, that category borrows approved pieces of the kind and the
-- family is marked relaxed so exact matches win at selection time.
function AppearanceRandomizer.getOutfitFamilies(gender, style, palette, options)
    gender, style, palette = normalizeScope(gender, style, palette)
    local filters = kindFilters(options)
    local headwear = type(options) == 'table' and options.headwear or 'none'
    local families = {}
    for _, family in ipairs(OUTFIT_FAMILIES[gender]) do
        if family.styles[style] then
            local pools, relaxed = { tops = {}, bottoms = {}, shoes = {} }, false
            -- Kits are complete uniforms: every piece shares one palette and
            -- the garment filters do not reshape them.
            local familyPalette = family.palette or palette
            for _, category in ipairs({ 'tops', 'bottoms', 'shoes' }) do
                -- One focal garment carries color. Sneaker-led families let Mixed
                -- use the newer footwear colorways without a clashing top.
                local focal = palette == 'varied' and family.accent or 'tops'
                local piecePalette = category == (focal or 'tops') and palette or 'neutral'
                -- Matched kits share the palette across pieces; the others keep the
                -- everyday rule so only the top carries a bold colorway.
                if (family.kit and family.match) or familyPalette == 'full' then piecePalette = familyPalette end
                local ids, kind = familyPieceIds(gender, category, family), not family.kit and filters[category] or nil
                pools[category] = materializeIds(gender, category, ids, piecePalette, kind)
                if kind and #ids > 0 and #pools[category] == 0 then
                    relaxed = true
                    pools[category] = materializeIds(gender, category,
                        approvedIdsOfKind(gender, category, kind, style), piecePalette, kind)
                end
            end
            if #pools.tops > 0 and #pools.bottoms > 0 and #pools.shoes > 0 then
                pools.accessories = propPool(gender, style, palette, ACCESSORY_KINDS)
                pools.headwear = AppearanceRandomizer.getHeadwearPool(gender, style, palette, headwear)
                if family.kit then
                    -- Kit faces carry masks and goggles, so only watches join
                    -- them, and the kit's own headgear replaces Headwear.
                    local watches = {}
                    for _, accessory in ipairs(pools.accessories) do
                        if accessory.kind == 'watch' then watches[#watches + 1] = accessory end
                    end
                    pools.accessories, pools.headwear = watches, {}
                    pools.match = family.match
                    pools.gear = materializeIds(gender, 'gear', familyPieceIds(gender, 'gear', family), familyPalette)
                    pools.kitHeadgear = materializeKitProps(gender, 'headgear', familyPieceIds(gender, 'headgear', family), familyPalette)
                    pools.kitEyewear = materializeKitProps(gender, 'eyewear', familyPieceIds(gender, 'eyewear', family), familyPalette)
                    pools.gearChance = family.gearChance or 100
                    pools.headgearChance = family.headgearChance or 100
                    pools.eyewearChance = family.eyewearChance or 100
                end
                families[#families + 1] = {
                    id = family.id, name = family.name, fallback = family.fallback == true,
                    relaxed = relaxed, kit = family.kit == true, pools = pools,
                }
            end
        end
    end
    return families
end

-- Collection identity for a global drawable or prop: AppearanceIndex covers
-- the wardrobe components, the generated texture table covers kit slots.
function AppearanceRandomizer.getCollectionIdentity(gender, kind, slot, drawable)
    gender = gender == 'female' and 'female' or 'male'
    if kind == 'component' then
        local indexed = type(AppearanceIndex) == 'table' and AppearanceIndex[gender]
            and AppearanceIndex[gender][slot] and AppearanceIndex[gender][slot][drawable]
        if indexed then return indexed end
    end
    local source = type(AppearanceTextures) == 'table'
        and AppearanceTextures[kind == 'prop' and 'propIdentity' or 'identity'] or nil
    return source and source[gender] and source[gender][slot] and source[gender][slot][drawable] or nil
end

-- Requested garment kinds that no family offers this body, for error copy.
function AppearanceRandomizer.getUnavailableFilters(gender, options)
    gender = gender == 'female' and 'female' or 'male'
    local missing = {}
    for category, kind in pairs(kindFilters(options)) do
        if #approvedIdsOfKind(gender, category, kind, nil) == 0 then
            missing[#missing + 1] = { category = category, kind = kind }
        end
    end
    table.sort(missing, function(left, right) return left.category < right.category end)
    return missing
end

-- Optional textureLimit(piece, category) returns how many textures the
-- running build has for the piece's focal (and linked) slots; alternatives
-- at or above it are dropped so a reroll never applies a missing texture.
local function limitAlternatives(piece, category, textureLimit)
    if type(textureLimit) ~= 'function' or type(piece.alternatives) ~= 'table' then return piece end
    local limit = finiteInteger(textureLimit(piece, category), 0)
    if not limit then return piece end
    local kept = {}
    for _, option in ipairs(piece.alternatives) do
        if option.texture < limit then kept[#kept + 1] = option end
    end
    local copy = {}
    for key, value in pairs(piece) do copy[key] = value end
    copy.alternatives = #kept > 1 and kept or nil
    return copy
end

function AppearanceRandomizer.filterPiecePools(pools, clothingValidator, accessoryValidator, textureLimit)
    pools = type(pools) == 'table' and pools or {}
    local filtered = { tops = {}, bottoms = {}, shoes = {}, accessories = {}, headwear = {} }
    local acceptsClothing = type(clothingValidator) == 'function' and clothingValidator or function() return true end
    local acceptsAccessory = type(accessoryValidator) == 'function' and accessoryValidator or function() return true end
    for _, key in ipairs({ 'match', 'gearChance', 'headgearChance', 'eyewearChance' }) do filtered[key] = pools[key] end

    for _, category in ipairs({ 'tops', 'bottoms', 'shoes', 'gear' }) do
        if pools[category] then
            filtered[category] = filtered[category] or {}
            for _, piece in ipairs(pools[category]) do
                if acceptsClothing(piece, category) then
                    filtered[category][#filtered[category] + 1] = limitAlternatives(piece, category, textureLimit)
                end
            end
        end
    end
    for _, category in ipairs({ 'accessories', 'headwear', 'kitHeadgear', 'kitEyewear' }) do
        if pools[category] or category == 'accessories' or category == 'headwear' then
            filtered[category] = filtered[category] or {}
            for _, accessory in ipairs(pools[category] or {}) do
                if acceptsAccessory(accessory) then
                    filtered[category][#filtered[category] + 1] = limitAlternatives(accessory, category, textureLimit)
                end
            end
        end
    end
    return filtered
end

local function chooseFromPool(pool, chooser, category)
    if type(pool) ~= 'table' or #pool == 0 then return nil end
    local index = type(chooser) == 'function' and finiteInteger(chooser(#pool, category), 1, #pool) or 1
    return pool[index or 1]
end

function AppearanceRandomizer.getIdentityPool(gender, options)
    options = type(options) == 'table' and options or {}
    local source = IDENTITY_POOLS[gender == 'female' and 'female' or 'male']
    local profileName = VALID_FACE_PROFILES[options.faceProfile] and options.faceProfile or 'everyday'
    local hairStyle = VALID_HAIR_STYLES[options.hairStyle] and options.hairStyle or 'any'
    local profile = source.profiles[profileName] or source.profiles.everyday
    local pool = {
        profile = profileName,
        mothers = {},
        fathers = {},
        hair = {},
        shapeMixMin = profile.shapeMix[1],
        shapeMixMax = profile.shapeMix[2],
        skinMixMin = 0.24,
        skinMixMax = 0.76,
    }
    for index, parentId in ipairs(profile.mothers) do pool.mothers[index] = parentId end
    for index, parentId in ipairs(profile.fathers) do pool.fathers[index] = parentId end
    for _, hair in ipairs(source.hair) do
        if hairStyle == 'any' or hair.group == hairStyle then
            pool.hair[#pool.hair + 1] = {
                name = hair.name,
                group = hair.group,
                collection = hair.collection,
                drawable = hair.drawable,
                texture = hair.texture,
            }
        end
    end
    return pool
end

function AppearanceRandomizer.assembleIdentity(gender, options, chooser)
    if type(options) == 'function' then
        chooser, options = options, {}
    end
    local pool = AppearanceRandomizer.getIdentityPool(gender, options)
    local mother = chooseFromPool(pool.mothers, chooser, 'mother')
    local father = chooseFromPool(pool.fathers, chooser, 'father')
    return {
        profile = pool.profile,
        shapeFirst = mother,
        shapeSecond = father,
        skinFirst = mother,
        skinSecond = father,
        shapeMixMin = pool.shapeMixMin,
        shapeMixMax = pool.shapeMixMax,
        skinMixMin = pool.skinMixMin,
        skinMixMax = pool.skinMixMax,
        hair = chooseFromPool(pool.hair, chooser, 'hair'),
    }
end

-- Natural keeps the primary colour about two times in three. Contrast prefers
-- a shade at least 30 luminance steps away from the primary.
function AppearanceRandomizer.pickHighlight(colors, primary, mode, chooser)
    mode = VALID_HIGHLIGHTS[mode] and mode or 'natural'
    if mode == 'none' or type(colors) ~= 'table' or #colors == 0 then return primary end
    local roll = type(chooser) == 'function' and finiteInteger(chooser(100, 'highlightChance'), 1, 100) or 1
    if mode == 'natural' and roll <= 68 then return primary end
    local pool = colors
    if mode == 'contrast' and type(primary) == 'table' and primary.r then
        local contrasting = {}
        for _, color in ipairs(colors) do
            if color.r and math.abs(luminance(color) - luminance(primary)) >= 30 then contrasting[#contrasting + 1] = color end
        end
        if #contrasting > 0 then pool = contrasting end
    end
    return chooseFromPool(pool, chooser, 'highlight') or primary
end

function AppearanceRandomizer.getFaceFeatureRange(gender, profileName, featureId, variation)
    featureId = finiteInteger(featureId, 0, 19) or 0
    profileName = VALID_FACE_PROFILES[profileName] and profileName or 'everyday'
    local ranges = gender == 'female' and FEMALE_FACE_RANGES or MALE_FACE_RANGES
    local range = ranges[featureId] or { -0.12, 0.12 }
    local minimum, maximum = range[1], range[2]
    if profileName == 'soft' then
        minimum, maximum = minimum * 0.78, maximum * 0.78
    end
    local scale = FACE_VARIATION_SCALE[variation] or FACE_VARIATION_SCALE.balanced
    return minimum * scale, maximum * scale
end

local MAKEUP_LEVELS = {
    none = { eyes = 0, blush = 0, lips = 0 },
    subtle = { eyes = 18, blush = 12, lips = 18, eyesMax = 0.22, blushMax = 0.18, lipsMax = 0.24 },
    polished = { eyes = 48, blush = 34, lips = 46, eyesMax = 0.38, blushMax = 0.28, lipsMax = 0.38 },
    bold = { eyes = 88, blush = 62, lips = 92, eyesMax = 0.62, blushMax = 0.42, lipsMax = 0.72 },
}

local FACIAL_HAIR_PLANS = {
    any = { chance = 52, minimum = 0.50, maximum = 0.88 },
    clean = { chance = 0, minimum = 0.0, maximum = 0.0 },
    stubble = { chance = 100, minimum = 0.35, maximum = 0.70 },
    short = { chance = 100, minimum = 0.70, maximum = 0.95 },
    full = { chance = 100, minimum = 0.80, maximum = 1.0 },
}

function AppearanceRandomizer.getOverlayPlan(gender, options)
    options = type(options) == 'table' and options or {}
    local ageProfile = VALID_AGE_PROFILES[options.ageProfile] and options.ageProfile or 'young'
    local complexion = VALID_COMPLEXIONS[options.complexion] and options.complexion or 'clean'
    local makeup = MAKEUP_LEVELS[VALID_MAKEUP[options.makeup] and options.makeup or 'subtle']
    local facialHair = VALID_FACIAL_HAIR[options.facialHair] and options.facialHair or 'any'
    local isFemale = gender == 'female'
    local naturalSkin = complexion == 'natural'
    local isMature = ageProfile == 'mature'
    local isAdult = ageProfile == 'adult'
    local beard = FACIAL_HAIR_PLANS[facialHair]
    local freckles = complexion == 'freckled' and 85 or (naturalSkin and 12 or 0)

    local plan = {
        [0] = overlay(naturalSkin and 8 or 0, 0.08, 0.20),
        [1] = overlay(isFemale and 0 or beard.chance, beard.minimum, beard.maximum, 'hair', FACIAL_HAIR_STYLES[facialHair]),
        [2] = overlay(100, 0.78, 1.0, 'hair'),
        [3] = overlay(isMature and 42 or (isAdult and 5 or 0), 0.08, isMature and 0.42 or 0.16),
        [4] = overlay(isFemale and makeup.eyes or 0, 0.08, makeup.eyesMax, 'cosmetic'),
        [5] = overlay(isFemale and makeup.blush or 0, 0.06, makeup.blushMax, 'blush'),
        [6] = overlay(naturalSkin and 8 or 0, 0.08, 0.20),
        [7] = overlay(isMature and 16 or (isAdult and naturalSkin and 3 or 0), 0.08, 0.20),
        [8] = overlay(isFemale and makeup.lips or 0, 0.10, makeup.lipsMax, 'lipstick'),
        [9] = overlay(freckles, complexion == 'freckled' and 0.25 or 0.10, complexion == 'freckled' and 0.55 or 0.28),
        [10] = overlay(isFemale and 0 or 18, 0.28, 0.65, 'hair'),
        [11] = overlay(naturalSkin and 4 or 0, 0.06, 0.16),
    }
    return plan
end

-- A chosen piece rerolls its focal texture among the palette's alternatives.
-- `anchor` narrows the choice to the first piece's pattern or texture index
-- when the family matches pieces; with no match the full list stays open.
local function rollTexture(piece, chooser, category, anchor)
    local options = piece and piece.alternatives
    if type(options) ~= 'table' or #options <= 1 then return piece end
    local candidates = options
    if anchor then
        local matched = {}
        for _, option in ipairs(options) do
            if (anchor.pattern and option.pattern == anchor.pattern)
                or (anchor.texture and option.texture == anchor.texture) then
                matched[#matched + 1] = option
            end
        end
        if #matched > 0 then candidates = matched end
    end
    local index = type(chooser) == 'function' and finiteInteger(chooser(#candidates, category .. 'Texture'), 1, #candidates) or 1
    local option = candidates[index or 1]
    if option.texture == piece.texture then return piece end

    local rolled = {}
    for key, value in pairs(piece) do rolled[key] = value end
    rolled.id = ('%s~%d'):format(piece.id, option.texture)
    rolled.name, rolled.texture, rolled.pattern = option.name, option.texture, option.pattern
    if piece.components then
        rolled.components = {}
        for index2, component in ipairs(piece.components) do
            local copy = {}
            for key, value in pairs(component) do copy[key] = value end
            if component.component == piece.focal or (piece.linked and piece.linked[component.component]) then
                copy.texture = option.texture
            end
            rolled.components[index2] = copy
        end
    end
    return rolled
end

local function matchAnchor(match, piece)
    if match == 'pattern' and piece.pattern then return { pattern = piece.pattern } end
    if match == 'index' and piece.texture then return { texture = piece.texture } end
    return nil
end

local function rollChance(chooser, chance, category)
    if not chance or chance >= 100 then return true end
    if chance <= 0 then return false end
    local roll = type(chooser) == 'function' and finiteInteger(chooser(100, category), 1, 100) or 1
    return (roll or 1) <= chance
end

local function propEntry(accessory)
    return {
        prop = accessory.prop, collection = accessory.collection, drawable = accessory.drawable,
        globalDrawable = accessory.globalDrawable, texture = accessory.texture,
    }
end

-- plan is true for one prop, false for none, or { accessories = level } where
-- level is none, minimal (one prop) or layered (one per prop slot, up to two).
-- Headwear comes from pools.headwear whenever the plan is not false. Kit
-- gear and kit props roll their own chances and take their slots first.
function AppearanceRandomizer.assembleOutfit(pools, plan, chooser)
    pools = type(pools) == 'table' and pools or {}
    local top = chooseFromPool(pools.tops, chooser, 'tops')
    local bottom = chooseFromPool(pools.bottoms, chooser, 'bottoms')
    local shoes = chooseFromPool(pools.shoes, chooser, 'shoes')
    if not top or not bottom or not shoes then return nil, 'empty_piece_pool' end
    top = rollTexture(top, chooser, 'tops')
    local anchor = matchAnchor(pools.match, top)
    bottom = rollTexture(bottom, chooser, 'bottoms', anchor)
    shoes = rollTexture(shoes, chooser, 'shoes', anchor)
    local pieces = { top, bottom, shoes }
    local gear = nil
    if pools.gear and #pools.gear > 0 and rollChance(chooser, pools.gearChance, 'gearChance') then
        gear = rollTexture(chooseFromPool(pools.gear, chooser, 'gear'), chooser, 'gear', anchor)
        pieces[#pieces + 1] = gear
    end

    local components = {}
    for _, piece in ipairs(pieces) do
        for _, component in ipairs(piece.components) do
            components[#components + 1] = {
                component = component.component,
                collection = component.collection,
                drawable = component.drawable,
                globalDrawable = component.globalDrawable,
                texture = component.texture,
            }
        end
    end
    table.sort(components, function(left, right) return left.component < right.component end)

    local accessories, names, occupied = {}, { top.name, bottom.name, shoes.name }, {}
    if gear then names[#names + 1] = gear.name end
    for _, kitProp in ipairs({ { 'kitHeadgear', 'headgearChance' }, { 'kitEyewear', 'eyewearChance' } }) do
        local pool = pools[kitProp[1]]
        if pool and #pool > 0 and rollChance(chooser, pools[kitProp[2]], kitProp[2]) then
            local chosen = rollTexture(chooseFromPool(pool, chooser, kitProp[1]), chooser, kitProp[1], anchor)
            if chosen and not occupied[chosen.prop] then
                occupied[chosen.prop] = true
                accessories[#accessories + 1] = propEntry(chosen)
                names[#names + 1] = chosen.name
            end
        end
    end

    local level = plan == true and 'minimal' or (type(plan) == 'table' and accessoryLevel(plan.accessories) or 'none')
    local count = ({ none = 0, minimal = 1, layered = 2 })[level]
    local remaining = {}
    for _, candidate in ipairs(pools.accessories or {}) do
        if not occupied[candidate.prop] then remaining[#remaining + 1] = candidate end
    end
    for _ = 1, count do
        local accessory = rollTexture(chooseFromPool(remaining, chooser, 'accessories'), chooser, 'accessories')
        if not accessory then break end
        occupied[accessory.prop] = true
        accessories[#accessories + 1] = propEntry(accessory)
        local others = {}
        for _, candidate in ipairs(remaining) do
            if candidate.prop ~= accessory.prop then others[#others + 1] = candidate end
        end
        remaining = others
    end
    if plan and not occupied[0] then
        local hat = rollTexture(chooseFromPool(pools.headwear, chooser, 'headwear'), chooser, 'headwear')
        if hat then
            accessories[#accessories + 1] = propEntry(hat)
            names[#names + 1] = hat.name
        end
    end
    local ids = { top.id, bottom.id, shoes.id }
    if gear then ids[#ids + 1] = gear.id end
    return {
        id = table.concat(ids, '+'),
        name = table.concat(names, ', '),
        components = components, accessories = accessories,
        pieces = { top = top.id, bottom = bottom.id, shoes = shoes.id, gear = gear and gear.id or nil },
    }
end
