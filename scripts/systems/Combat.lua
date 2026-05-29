-- ============================================================================
-- Combat.lua
-- 血量 + 战斗力系统，处理踩雷扣血、敌人生成与战斗判定
-- ============================================================================

local Combat = {}

-- 玩家属性
Combat.maxHp = 100
Combat.hp = 100
Combat.power = 10         -- 玩家基础战斗力

-- 敌人数据 { ["x,y"] = { name, power, alive } }
Combat.enemies = {}

-- 配置
local CONFIG = {
    mineDamage = 25,             -- 踩雷扣血
    enemySpawnChance = 0.30,     -- 30% 房间有敌人
    enemyPowerMin = 5,           -- 敌人最低战斗力
    enemyPowerMax = 20,          -- 敌人最高战斗力
    powerUpChance = 0.20,        -- 搜索后获得战斗力加成概率
    powerUpAmount = 3,           -- 战斗力加成数值
}

local function cellKey(x, y)
    return tostring(x) .. "," .. tostring(y)
end

--- 重置战斗状态（新游戏时调用）
function Combat.Reset()
    Combat.maxHp = 100
    Combat.hp = Combat.maxHp
    Combat.power = 10
    Combat.enemies = {}
    Combat.mineImmunity = false    -- 首次踩雷免疫（装备效果）
    Combat.mineDmgReduce = 0       -- 雷伤减免（天赋效果）
end

--- 获取玩家是否存活
function Combat.IsAlive()
    return Combat.hp > 0
end

--- 踩雷伤害：扣血，返回是否死亡
---@return table { damage: number, hp: number, dead: boolean, immuneUsed: boolean }
function Combat.TakeMineHit()
    -- 急救包免疫：首次踩雷不受伤害
    if Combat.mineImmunity then
        Combat.mineImmunity = false
        return {
            damage = 0,
            hp = Combat.hp,
            dead = false,
            immuneUsed = true,
        }
    end
    local damage = CONFIG.mineDamage - Combat.mineDmgReduce
    if damage < 5 then damage = 5 end  -- 最低伤害 5
    Combat.hp = math.max(0, Combat.hp - damage)
    return {
        damage = damage,
        hp = Combat.hp,
        dead = Combat.hp <= 0,
        immuneUsed = false,
    }
end

--- 为指定格子生成敌人
--- 怪物房（roomType="monster"）必定生成，普通房不再随机生成
---@param minefield table
---@param x number
---@param y number
function Combat.TrySpawnEnemy(minefield, x, y)
    local key = cellKey(x, y)

    -- 已有敌人记录（无论死活），不重复生成
    if Combat.enemies[key] then return end

    local cell = minefield:GetCellView(x, y)
    if not cell then return end
    -- 出生点和撤离点不生成敌人
    if cell.spawn or cell.exitId then return end

    -- 只有怪物房才生成敌人
    if cell.roomType ~= "monster" then return end

    -- 根据 seed + 坐标做伪随机确定战斗力
    local seed = minefield.seed or 1
    local hash = (x * 131 + y * 97 + seed * 41) % 1000

    -- 生成敌人，战斗力与位置/邻接相关
    local adjPower = (cell.adjacent or 0) * 2
    local basePower = CONFIG.enemyPowerMin + (hash % (CONFIG.enemyPowerMax - CONFIG.enemyPowerMin + 1))
    local enemyPower = basePower + adjPower

    local names = { "哥布林", "骷髅兵", "蝙蝠怪", "食尸鬼", "暗影刺客" }
    local nameIdx = (hash % #names) + 1

    Combat.enemies[key] = {
        name = names[nameIdx],
        power = enemyPower,
        alive = true,
    }
end

--- 获取指定格子的敌人（如果有且活着）
---@param x number
---@param y number
---@return table|nil  { name, power, alive }
function Combat.GetEnemy(x, y)
    local key = cellKey(x, y)
    local enemy = Combat.enemies[key]
    if enemy and enemy.alive then
        return enemy
    end
    return nil
end

--- 获取指定格子的敌人（无论死活，用于渲染）
---@param x number
---@param y number
---@return table|nil  { name, power, alive }
function Combat.GetEnemyAny(x, y)
    local key = cellKey(x, y)
    return Combat.enemies[key]
end

--- 战斗判定：玩家 vs 敌人
--- 如果玩家战斗力 >= 敌人，敌人死亡，玩家不受伤
--- 如果玩家战斗力 < 敌人，扣除差值血量，敌人仍死亡（战斗完成后通过）
---@param x number
---@param y number
---@return table { fought, enemy, damage, hp, dead, playerWin }
function Combat.FightEnemy(x, y)
    local key = cellKey(x, y)
    local enemy = Combat.enemies[key]

    if not enemy or not enemy.alive then
        return { fought = false }
    end

    enemy.alive = false
    local damage = 0
    local playerWin = true

    if Combat.power < enemy.power then
        damage = enemy.power - Combat.power
        Combat.hp = math.max(0, Combat.hp - damage)
        playerWin = false
    end

    return {
        fought = true,
        enemy = enemy,
        damage = damage,
        hp = Combat.hp,
        dead = Combat.hp <= 0,
        playerWin = playerWin,
    }
end

--- 搜索时可能获得战斗力加成
---@param minefield table
---@param x number
---@param y number
---@return number  获得的战斗力加成（0 表示没获得）
function Combat.TryPowerUp(minefield, x, y)
    local seed = minefield.seed or 1
    local hash = (x * 67 + y * 113 + seed * 23) % 100

    if hash / 100 < CONFIG.powerUpChance then
        Combat.power = Combat.power + CONFIG.powerUpAmount
        return CONFIG.powerUpAmount
    end
    return 0
end

--- 获取战斗系统状态摘要（用于 HUD 显示）
function Combat.GetStatus()
    return {
        hp = Combat.hp,
        maxHp = Combat.maxHp,
        power = Combat.power,
        alive = Combat.IsAlive(),
    }
end

return Combat
