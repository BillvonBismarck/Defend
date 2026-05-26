--- ============================================================================
--- 波次管理 - 敌人生成节奏、波次系数、精英/BOSS 触发
--- ============================================================================

local Config = require("Config")
local Enemy = require("battle.Enemy")
local GameAudio = require("fx.GameAudio")
local SM = require("utils.SafeMath")
local Player = require("battle.Player")
local DailyChallenge = require("meta.DailyChallenge")
local WeeklyChallenge = require("meta.WeeklyChallenge")

local Wave = {}

-- 状态
Wave.waveNum = 0          -- 当前波次号
Wave.timer = 0            -- 波次间隔计时
Wave.totalTime = 0        -- 全局战斗时间（秒）
Wave.waveCoeff = 1.0      -- 当前波次系数
Wave.bossAlive = false    -- Boss 是否存活
Wave.spawnTimer = 0       -- 持续刷怪计时
Wave.gameOver = false     -- 游戏结束标记（通关）
Wave.onWaveComplete = nil -- 过波回调 function(waveNum)
Wave.onWaveStart = nil   -- 波次开始回调 function(waveNum)

function Wave.Reset()
    Wave.waveNum = 0
    Wave.timer = 0
    Wave.totalTime = 0
    Wave.waveCoeff = 1.0
    Wave.bossAlive = false
    Wave.spawnTimer = 0
    Wave.gameOver = false
end

--- 获取当前波次应该生成的敌人数（受难度系数影响）
local function GetWaveEnemyCount()
    local base = Config.WAVE.baseEnemyCount + Config.WAVE.countGrowth * Wave.waveNum
    local diff = Config.GetDifficulty()
    local count = math.max(1, math.floor(base * diff.spawnMult))
    -- 周挑战：敌人数量倍率
    local wcCount = WeeklyChallenge.GetMod("enemyCountMul")
    if wcCount then count = math.max(1, math.floor(count * wcCount)) end
    return count
end

-- ============================================================================
-- 波次阵容表：越高波次敌怪种类越多、阵容越复杂
-- 每项 { 类型, 权重 }，权重越高出现概率越大
-- ============================================================================
local WAVE_TIERS = {
    -- 波次 1~2：只有普通怪，新手适应期
    { maxWave = 2,  pool = {
        { "normal", 1.0 },
    }},
    -- 波次 3~4：加入速敏怪
    { maxWave = 4,  pool = {
        { "normal", 0.65 },
        { "fast",   0.35 },
    }},
    -- 波次 5~6：蜂群小怪 + 坦克 + 远程怪登场
    { maxWave = 6,  pool = {
        { "normal", 0.30 },
        { "fast",   0.20 },
        { "swarm",  0.18 },
        { "tank",   0.15 },
        { "ranger", 0.17 },
    }},
    -- 波次 7~9：冲锋怪 + 幽灵怪加入
    { maxWave = 9,  pool = {
        { "normal",  0.20 },
        { "fast",    0.17 },
        { "swarm",   0.13 },
        { "tank",    0.10 },
        { "charger", 0.13 },
        { "ghost",   0.12 },
        { "ranger",  0.15 },
    }},
    -- 波次 10~12：巫师登场
    { maxWave = 12, pool = {
        { "normal",  0.12 },
        { "fast",    0.12 },
        { "swarm",   0.10 },
        { "tank",    0.10 },
        { "charger", 0.12 },
        { "ghost",   0.10 },
        { "shaman",  0.12 },
        { "ranger",  0.12 },
        { "elite",   0.10 },
    }},
    -- 波次 13+：全怪种高强度
    { maxWave = 999, pool = {
        { "normal",  0.08 },
        { "fast",    0.10 },
        { "swarm",   0.09 },
        { "tank",    0.09 },
        { "charger", 0.11 },
        { "ghost",   0.11 },
        { "shaman",  0.11 },
        { "ranger",  0.13 },
        { "elite",   0.18 },
    }},
}

--- 根据当前波次选择敌人类型（加权随机）
local function PickEnemyType()
    -- 每日挑战：强制单一敌怪类型
    if DailyChallenge.active and DailyChallenge.todayConfig then
        return DailyChallenge.todayConfig.enemyType
    end
    -- 找到当前波次对应的阵容层
    local tier = WAVE_TIERS[#WAVE_TIERS]  -- 默认最高层
    for _, t in ipairs(WAVE_TIERS) do
        if Wave.waveNum <= t.maxWave then
            tier = t
            break
        end
    end

    -- 加权随机选择
    local r = math.random()
    local accum = 0
    for _, entry in ipairs(tier.pool) do
        accum = accum + entry[2]
        if r <= accum then
            return entry[1]
        end
    end
    return tier.pool[#tier.pool][1]  -- 兜底
end

--- 更新波次逻辑
---@param dt number
---@param playerX number
---@param playerY number
function Wave.Update(dt, playerX, playerY)
    Wave.totalTime = Wave.totalTime + dt

    -- 持续少量刷怪（补充型）
    Wave.spawnTimer = Wave.spawnTimer + dt
    local spawnInterval
    if Wave.waveNum <= 30 then
        spawnInterval = math.max(0.8, 2.0 - Wave.waveNum * 0.05)
    else
        -- 30波后继续加速：从0.8秒逐渐降到0.3秒
        spawnInterval = math.max(0.3, 0.8 - (Wave.waveNum - 30) * 0.025)
    end

    -- 动态缩减：玩家攻击力碾压本波普通敌人时加速刷怪
    local normalHp = SM.mulFloor(Config.ENEMY.normal.baseHp, Wave.waveCoeff)
    local pAtk = Player.atk
    if pAtk * 1.5 > normalHp then
        -- 碾压程度越高缩减越大：×3 → 10%间隔，×2 → 25%间隔，×1.5 → 70%间隔
        if pAtk * 3 > normalHp then
            spawnInterval = spawnInterval * 0.10
        elseif pAtk * 2 > normalHp then
            spawnInterval = spawnInterval * 0.25
        else
            spawnInterval = spawnInterval * 0.70
        end
        -- 保底最低 0.05 秒防止无限刷
        if spawnInterval < 0.05 then spawnInterval = 0.05 end
    end

    if Wave.spawnTimer >= spawnInterval then
        Wave.spawnTimer = 0
        if #Enemy.active < Config.WAVE.maxEnemiesAlive * 0.5 then
            local etype = PickEnemyType()
            if etype == "swarm" then
                local packSize = math.random(2, 3)
                for _ = 1, packSize do
                    Enemy.SpawnAroundPlayer(playerX, playerY, "swarm", Wave.waveCoeff)
                end
            else
                Enemy.SpawnAroundPlayer(playerX, playerY, etype, Wave.waveCoeff)
            end
        end
    end

    -- 波次大刷怪
    Wave.timer = Wave.timer + dt
    if Wave.timer >= Config.WAVE.interval then
        Wave.timer = 0
        Wave.waveNum = Wave.waveNum + 1
        -- 波次开始回调（守护遗物充能等）
        if Wave.onWaveStart then
            Wave.onWaveStart(Wave.waveNum)
        end
        -- 波次系数：30波前线性，30-39波×1.08指数，40-49波×2，50波后加速增长
        -- 使用 SafeMath 防止指数增长导致溢出为负值
        local baseCoeff = 1.0 + Config.WAVE.coeffGrowth * Wave.waveNum
        if Wave.waveNum >= 50 then
            -- 50波后：指数加速（每波额外 ×1.01^(n-50)）
            baseCoeff = SM.mul(baseCoeff, SM.mul(2, SM.pow(1.01, Wave.waveNum - 50)))
        elseif Wave.waveNum >= 40 then
            -- 40-50波：成长翻倍
            baseCoeff = baseCoeff * 2
        elseif Wave.waveNum >= 30 then
            -- 30-39波：每波额外 ×1.03^(n-30)，适度加速血量增长
            baseCoeff = SM.mul(baseCoeff, SM.pow(1.03, Wave.waveNum - 30))
        end
        -- 难度乘数：影响敌人HP/ATK缩放
        local diff = Config.GetDifficulty()
        baseCoeff = SM.mul(baseCoeff, diff.enemyHpMult)
        Wave.waveCoeff = SM.clamp(baseCoeff)

        local count = GetWaveEnemyCount()
        for _ = 1, count do
            local etype = PickEnemyType()
            if etype == "swarm" then
                local packSize = math.random(3, 5)
                local baseAngle = math.random() * 6.28
                local baseDist = Config.WAVE.spawnMinRadius +
                    math.random() * (Config.WAVE.spawnRadius - Config.WAVE.spawnMinRadius)
                for j = 1, packSize do
                    local aOff = (j - 1) * 0.3 + (math.random() - 0.5) * 0.4
                    local dOff = (math.random() - 0.5) * 40
                    local sx = playerX + math.cos(baseAngle + aOff) * (baseDist + dOff)
                    local sy = playerY + math.sin(baseAngle + aOff) * (baseDist + dOff)
                    sx = math.max(50, math.min(Config.WORLD_SIZE - 50, sx))
                    sy = math.max(50, math.min(Config.WORLD_SIZE - 50, sy))
                    Enemy.Spawn(sx, sy, "swarm", Wave.waveCoeff)
                end
            else
                Enemy.SpawnAroundPlayer(playerX, playerY, etype, Wave.waveCoeff)
            end
        end

        -- 每波刷精英（每日挑战翻倍为 2 只）
        local eliteCount = (DailyChallenge.active) and 2 or 1
        for _ = 1, eliteCount do
            Enemy.SpawnAroundPlayer(playerX, playerY, "elite", Wave.waveCoeff)
        end

        -- 过波回调（自动存档等）
        if Wave.onWaveComplete then
            Wave.onWaveComplete(Wave.waveNum)
        end

        -- 每 bossInterval 波刷 Boss（不与已有 Boss 重叠）
        -- 每日挑战 boss_double 因子：间隔减半
        if not Wave.bossAlive then
            local bossDef
            local wcBossEvery = WeeklyChallenge.GetMod("bossEveryN")
            if wcBossEvery then
                -- 周挑战 boss_rush：每 N 波刷 Boss
                if Wave.waveNum % wcBossEvery == 0 then
                    local bossIdx = math.floor(Wave.waveNum / wcBossEvery)
                    local bossListLen = #Config.BOSSES
                    bossDef = Config.BOSSES[((bossIdx - 1) % bossListLen) + 1]
                end
            elseif DailyChallenge.HasFactor("boss_double") then
                -- boss_double：间隔减半（原 bossInterval→减半）
                local halfInterval = math.max(1, math.floor(Config.WAVE.bossInterval / 2))
                if Wave.waveNum % halfInterval == 0 then
                    -- 从 BOSSES 表循环取 Boss
                    local bossIdx = math.floor(Wave.waveNum / halfInterval)
                    local bossListLen = #Config.BOSSES
                    bossDef = Config.BOSSES[((bossIdx - 1) % bossListLen) + 1]
                end
            else
                bossDef = Config.GetBossForWave(Wave.waveNum)
            end
            if bossDef then
                Wave.bossAlive = true
                GameAudio.PlaySFX("boss_warning")
                Enemy.SpawnBossAroundPlayer(playerX, playerY, bossDef, Wave.waveCoeff)
            end
        end
    end

    -- 检查 Boss 是否被击杀
    if Wave.bossAlive then
        if not Enemy.currentBoss or not Enemy.currentBoss.alive then
            Wave.bossAlive = false
            -- 第 70 波 Boss（第 7 个）被击杀视为通关
            if Wave.waveNum >= #Config.BOSSES * Config.WAVE.bossInterval then
                Wave.gameOver = true
            end
        end
    end
end

--- 获取显示用的时间字符串 MM:SS
function Wave.GetTimeString()
    local m = math.floor(Wave.totalTime / 60)
    local s = math.floor(Wave.totalTime % 60)
    return string.format("%02d:%02d", m, s)
end

return Wave
