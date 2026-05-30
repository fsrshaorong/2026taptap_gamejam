-- ============================================================================
-- Balance.lua
-- Central numeric configuration for the design-integration pass.
-- ============================================================================

local Balance = {}

Balance.mineDamage = 30

Balance.pressure = {
    min = 0,
    max = 100,
    explore = 2,
    mine = 10,
    monsterKill = 5,
    thresholds = {
        { pressure = 80, level = 1 },
        { pressure = 60, level = 2 },
        { pressure = 40, level = 3 },
        { pressure = 20, level = 4 },
        { pressure = 0,  level = 5 },
    },
}

Balance.search = {
    baseMin = 0,
    baseMax = 2,
    adjacentDivisor = 2,
    goldCap = 4,
    dropTable = {
        { max = 35, quality = nil },
        { max = 80, quality = "low" },
        { max = 95, quality = "common" },
        { max = 100, quality = "rare" },
    },
    highAdjacentBonus = {
        adjacentAtLeast = 3,
        rareBonus = 10,
    },
}

Balance.chest = {
    baseMin = 3,
    baseMax = 7,
    goldCap = 11,
    dropTable = {
        { max = 45, quality = "common" },
        { max = 80, quality = "rare" },
        { max = 97, quality = "precious" },
        { max = 100, quality = "abnormal" },
    },
    minItems = 1,
    maxItems = 2,
}

Balance.monster = {
    goldMin = 0,
    goldMax = 3,
    powerGain = 1,
    powerGainCap = 5,
}

Balance.trader = {
    sellRate = 0.75,
    minSaleGold = 1,
}

Balance.gambler = {
    bet = 20,
    loseMaxRoll = 4,
    smallWinRoll = 5,
    smallWinNet = 20,
    bigWinRoll = 6,
    bigWinNet = 60,
}

Balance.altar = {
    hpCosts = { 10, 15, 25, 35, 50 },
    rewards = {
        { gold = 8,  itemQuality = "low" },
        { gold = 12, itemQuality = "common" },
        { gold = 18, itemQuality = "rare" },
        { gold = 24, itemQuality = "precious" },
        { gold = 35, itemQuality = "abnormal" },
    },
}

Balance.shop = {
    armor = { price = 110, bonusHP = 20 },
    whetstone = { price = 90, bonusPower = 2 },
    medkit = { price = 120 },
    insulated_gloves = { price = 140, mineDmgReduce = 10 },
    compass = { price = 160 },
    backpack = { price = 220 },
}

Balance.talents = {
    talent_map = 100,
    talent_mine = 120,
    talent_monster = 120,
    talent_extract = 140,
    talent_event = 140,
}

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

Balance.Clamp = clamp

function Balance.RollRange(seed, x, y, salt, minValue, maxValue)
    minValue = math.floor(tonumber(minValue) or 0)
    maxValue = math.floor(tonumber(maxValue) or minValue)
    if maxValue < minValue then maxValue = minValue end
    local span = maxValue - minValue + 1
    local hash = (tonumber(seed) or 1) * 1103515245 + (x or 0) * 928371 + (y or 0) * 364479 + (salt or 0) * 7919
    hash = math.abs(hash) % 2147483647
    return minValue + (hash % span)
end

function Balance.TraderSaleValue(baseValue)
    baseValue = math.floor(tonumber(baseValue) or 0)
    if baseValue <= 0 then return 0 end
    return math.max(Balance.trader.minSaleGold, math.floor(baseValue * Balance.trader.sellRate))
end

return Balance
