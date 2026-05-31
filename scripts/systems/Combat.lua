-- ============================================================================
-- Combat.lua
-- 血量 + 战斗力系统, 处理踩雷扣血,敌人生成与战斗判定
-- ============================================================================

local Balance = require("systems.Balance")

local Combat = {}

-- 玩家属性
Combat.maxHp = 100
Combat.hp = 100
Combat.power = 10         -- 玩家基础战斗力

-- 敌人数据 { ["x,y"] = { name, power, alive } }
Combat.enemies = {}
Combat.monsterPowerBonus = 0

-- 配置
local CONFIG = {
    mineDamage = Balance.mineDamage,             -- 踩雷扣血
    enemySpawnChance = 0.30,     -- 30% 房间有敌人
    enemyPowerMin = 5,           -- 敌人最低战斗力
    enemyPowerMax = 20,          -- 敌人最高战斗力
    powerUpChance = 0,           -- 普通搜索不再提升战斗力
    powerUpAmount = 0,
    monsterRewardBaseGold = Balance.monster.goldMin,
    monsterRewardPowerGold = 0,
    monsterRewardPartPower = 999,
    monsterPositionX = 0.35,
    monsterPositionY = 0.45,
    monsterHpBase = 18,
    monsterDamageMin = 4,
    monsterAttackRadius = 0.20,
    playerAttackRange = 0.21,
    monsterIdleDuration = 1.10,
    monsterWarningDuration = 0.75,
    monsterActiveDuration = 0.28,
    monsterCooldownDuration = 0.55,
    playerAttackCooldown = 0.45,
    playerInvincibleDuration = 0.90,
    monsterHitFlashDuration = 0.20,
}

local function cellKey(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function makeReward(enemyPower)
    local span = Balance.monster.goldMax - Balance.monster.goldMin + 1
    local gold = Balance.monster.goldMin
    if span > 0 then
        gold = gold + (math.floor(tonumber(enemyPower) or 0) % span)
    end
    return {
        gold = gold,
        pendingGold = gold,
        parts = 0,
    }
end

local function ensureMonsterState(enemy)
    if not enemy then return nil end
    if enemy.monsterMaxHP == nil then
        enemy.monsterMaxHP = CONFIG.monsterHpBase + enemy.power
    end
    if enemy.monsterHP == nil then
        enemy.monsterHP = enemy.monsterMaxHP
    end
    if enemy.monsterDamage == nil then
        enemy.monsterDamage = math.max(CONFIG.monsterDamageMin, math.floor(enemy.power / 3))
    end
    if enemy.monsterPosition == nil then
        enemy.monsterPosition = { x = CONFIG.monsterPositionX, y = CONFIG.monsterPositionY }
    end
    enemy.attackPhase = enemy.attackPhase or "idle"
    enemy.attackTimer = enemy.attackTimer or CONFIG.monsterIdleDuration
    enemy.attackRadius = enemy.attackRadius or CONFIG.monsterAttackRadius
    enemy.playerAttackRange = enemy.playerAttackRange or CONFIG.playerAttackRange
    enemy.playerAttackCooldown = enemy.playerAttackCooldown or 0
    enemy.playerInvincibleTimer = enemy.playerInvincibleTimer or 0
    enemy.hitFlashTimer = enemy.hitFlashTimer or 0
    enemy.attackHitResolved = enemy.attackHitResolved or false
    enemy.monsterAlive = enemy.alive == true
    return enemy
end

local function distToEnemy(enemy, playerPos)
    ensureMonsterState(enemy)
    if not enemy or not playerPos then return 999 end
    local pos = enemy.monsterPosition
    local dx = (playerPos.x or 0) - pos.x
    local dy = (playerPos.y or 0) - pos.y
    return math.sqrt(dx * dx + dy * dy)
end

local function buildClearResult(enemy, damage, playerWin)
    local enemyPower = enemy and enemy.power or 0
    return {
        fought = true,
        enemy = enemy,
        damage = damage or 0,
        hp = Combat.hp,
        dead = Combat.hp <= 0,
        playerWin = playerWin ~= false,
        playerPower = Combat.power,
        enemyPower = enemyPower,
        cleared = true,
        reward = makeReward(enemyPower),
        powerGain = 0,
        pressureDelta = Balance.pressure.monsterKill,
    }
end

local function transitionAttackPhase(enemy)
    if enemy.attackPhase == "idle" then
        enemy.attackPhase = "warning"
        enemy.attackTimer = CONFIG.monsterWarningDuration
        enemy.attackHitResolved = false
    elseif enemy.attackPhase == "warning" then
        enemy.attackPhase = "active"
        enemy.attackTimer = CONFIG.monsterActiveDuration
        enemy.attackHitResolved = false
    elseif enemy.attackPhase == "active" then
        enemy.attackPhase = "cooldown"
        enemy.attackTimer = CONFIG.monsterCooldownDuration
        enemy.attackHitResolved = true
    else
        enemy.attackPhase = "idle"
        enemy.attackTimer = CONFIG.monsterIdleDuration
        enemy.attackHitResolved = false
    end
end

--- 重置战斗状态(新游戏时调用)
function Combat.Reset()
    Combat.maxHp = 100
    Combat.hp = Combat.maxHp
    Combat.power = 10
    Combat.enemies = {}
    Combat.monsterPowerBonus = 0
    Combat.mineImmunity = false    -- 首次踩雷免疫(装备效果)
    Combat.mineDmgReduce = 0       -- 雷伤减免(天赋效果)
end

--- 获取玩家是否存活
function Combat.IsAlive()
    return Combat.hp > 0
end

local function clampHp(value)
    if value < 0 then return 0 end
    if value > Combat.maxHp then return Combat.maxHp end
    return value
end

function Combat.ApplyHpDelta(delta)
    delta = tonumber(delta) or 0
    local before = Combat.hp
    Combat.hp = clampHp(Combat.hp + delta)
    return {
        delta = Combat.hp - before,
        requestedDelta = delta,
        hp = Combat.hp,
        dead = Combat.hp <= 0,
    }
end

function Combat.ApplyDamage(damage)
    damage = tonumber(damage) or 0
    if damage < 0 then damage = 0 end
    local result = Combat.ApplyHpDelta(-damage)
    result.damage = damage
    return result
end

function Combat.GrantMonsterKillPower(result)
    if not result or not result.fought or result.dead then return 0 end
    local enemy = result.enemy
    if enemy and enemy.powerGainGranted then return 0 end
    if Combat.monsterPowerBonus >= Balance.monster.powerGainCap then
        if enemy then enemy.powerGainGranted = true end
        return 0
    end

    local gain = math.min(Balance.monster.powerGain, Balance.monster.powerGainCap - Combat.monsterPowerBonus)
    if gain <= 0 then return 0 end
    Combat.power = Combat.power + gain
    Combat.monsterPowerBonus = Combat.monsterPowerBonus + gain
    if enemy then enemy.powerGainGranted = true end
    result.powerGain = gain
    return gain
end

--- 踩雷伤害:扣血, 返回是否死亡
---@return table { damage: number, hp: number, dead: boolean, immuneUsed: boolean }
function Combat.TakeMineHit()
    -- 急救包免疫:首次踩雷不受伤害
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
    local hit = Combat.ApplyDamage(damage)
    return {
        damage = damage,
        hp = hit.hp,
        dead = hit.dead,
        immuneUsed = false,
    }
end

--- 为指定格子生成敌人
--- 怪物房(roomType="monster")必定生成, 普通房不再随机生成
---@param minefield table
---@param x number
---@param y number
function Combat.TrySpawnEnemy(minefield, x, y)
    local key = cellKey(x, y)

    -- 已有敌人记录(无论死活), 不重复生成
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

    -- 生成敌人, 战斗力与位置/邻接相关
    local adjPower = (cell.adjacent or 0) * 2
    local basePower = CONFIG.enemyPowerMin + (hash % (CONFIG.enemyPowerMax - CONFIG.enemyPowerMin + 1))
    local enemyPower = basePower + adjPower

    local names = {
        "滞留工偶",
        "空壳巡工",
        "失控搬运机",
        "头灯哨卫",
        "管道清理机"
    }
    local nameIdx = (hash % #names) + 1

    Combat.enemies[key] = {
        name = names[nameIdx],
        power = enemyPower,
        alive = true,
    }
    ensureMonsterState(Combat.enemies[key])
end

--- 获取指定格子的敌人(如果有且活着)
---@param x number
---@param y number
---@return table|nil  { name, power, alive }
function Combat.GetEnemy(x, y)
    local key = cellKey(x, y)
    local enemy = Combat.enemies[key]
    if enemy and enemy.alive then
        ensureMonsterState(enemy)
        return enemy
    end
    return nil
end

--- 获取指定格子的敌人(无论死活, 用于渲染)
---@param x number
---@param y number
---@return table|nil  { name, power, alive }
function Combat.GetEnemyAny(x, y)
    local key = cellKey(x, y)
    ensureMonsterState(Combat.enemies[key])
    return Combat.enemies[key]
end

function Combat.GetMonsterConfig()
    return {
        position = { x = CONFIG.monsterPositionX, y = CONFIG.monsterPositionY },
        attackRadius = CONFIG.monsterAttackRadius,
        playerAttackRange = CONFIG.playerAttackRange,
    }
end

---@param x number
---@param y number
---@param dt number
---@param playerPos table|nil
---@return table
function Combat.UpdateEnemy(x, y, dt, playerPos)
    local enemy = Combat.GetEnemy(x, y)
    if not enemy then return { ok = false, status = "no_enemy" } end
    ensureMonsterState(enemy)

    local elapsed = tonumber(dt) or 0
    if elapsed < 0 then elapsed = 0 end
    if elapsed > 0.08 then elapsed = 0.08 end

    if enemy.playerAttackCooldown > 0 then
        enemy.playerAttackCooldown = math.max(0, enemy.playerAttackCooldown - elapsed)
    end
    if enemy.playerInvincibleTimer > 0 then
        enemy.playerInvincibleTimer = math.max(0, enemy.playerInvincibleTimer - elapsed)
    end
    if enemy.hitFlashTimer > 0 then
        enemy.hitFlashTimer = math.max(0, enemy.hitFlashTimer - elapsed)
    end

    enemy.attackTimer = (enemy.attackTimer or CONFIG.monsterIdleDuration) - elapsed
    while enemy.attackTimer <= 0 do
        transitionAttackPhase(enemy)
    end

    local result = {
        ok = true,
        enemy = enemy,
        playerHit = false,
        damage = 0,
        hp = Combat.hp,
        dead = false,
    }

    if enemy.attackPhase == "active" and not enemy.attackHitResolved then
        if distToEnemy(enemy, playerPos) <= enemy.attackRadius and enemy.playerInvincibleTimer <= 0 then
            local damage = enemy.monsterDamage
            local hit = Combat.ApplyDamage(damage)
            enemy.playerInvincibleTimer = CONFIG.playerInvincibleDuration
            enemy.attackHitResolved = true
            result.playerHit = true
            result.damage = damage
            result.hp = hit.hp
            result.dead = hit.dead
        end
    end

    return result
end

---@param x number
---@param y number
---@param playerPos table|nil
---@return table
function Combat.PlayerAttackEnemy(x, y, playerPos)
    local enemy = Combat.GetEnemy(x, y)
    if not enemy then return { ok = false, status = "no_enemy" } end
    ensureMonsterState(enemy)

    if enemy.playerAttackCooldown > 0 then
        return { ok = false, status = "cooldown", cooldown = enemy.playerAttackCooldown, enemy = enemy }
    end
    if distToEnemy(enemy, playerPos) > enemy.playerAttackRange then
        return { ok = false, status = "too_far", enemy = enemy }
    end

    local damage = Combat.power
    enemy.monsterHP = math.max(0, enemy.monsterHP - damage)
    enemy.playerAttackCooldown = CONFIG.playerAttackCooldown
    enemy.hitFlashTimer = CONFIG.monsterHitFlashDuration

    if enemy.monsterHP <= 0 then
        enemy.alive = false
        enemy.monsterAlive = false
        return {
            ok = true,
            status = "killed",
            hit = true,
            killed = true,
            damage = damage,
            enemy = enemy,
            result = buildClearResult(enemy, 0, true),
        }
    end

    return {
        ok = true,
        status = "hit",
        hit = true,
        killed = false,
        damage = damage,
        enemy = enemy,
        hp = enemy.monsterHP,
        maxHp = enemy.monsterMaxHP,
    }
end

--- 战斗判定:玩家 vs 敌人
--- 如果玩家战斗力 >= 敌人, 敌人死亡, 玩家不受伤
--- 如果玩家战斗力 < 敌人, 扣除差值血量, 敌人仍死亡(战斗完成后通过)
---@param x number
---@param y number
---@return table { fought, enemy, damage, hp, dead, playerWin }
function Combat.FightEnemy(x, y)
    local key = cellKey(x, y)
    local enemy = Combat.enemies[key]

    if not enemy or not enemy.alive then
        return { fought = false }
    end

    local playerPower = Combat.power
    local enemyPower = enemy.power
    ensureMonsterState(enemy)
    enemy.alive = false
    enemy.monsterAlive = false
    enemy.monsterHP = 0
    local damage = 0
    local playerWin = true

    if playerPower < enemyPower then
        damage = enemyPower - playerPower
        Combat.ApplyDamage(damage)
        playerWin = false
    end

    return buildClearResult(enemy, damage, playerWin)
end

--- 搜索时可能获得战斗力加成
---@param minefield table
---@param x number
---@param y number
---@return number  获得的战斗力加成(0 表示没获得)
function Combat.TryPowerUp(minefield, x, y)
    return 0
end

--- 获取战斗系统状态摘要(用于 HUD 显示)
function Combat.GetStatus()
    return {
        hp = Combat.hp,
        maxHp = Combat.maxHp,
        power = Combat.power,
        alive = Combat.IsAlive(),
    }
end

return Combat
