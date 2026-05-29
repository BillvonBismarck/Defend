--- ============================================================================
--- 敌人模块 - 对象池、AI追踪、生成、Boss 技能状态机
--- ============================================================================

local Config = require("Config")
local EnemyBullet = require("battle.EnemyBullet")
local SM = require("utils.SafeMath")
local DailyChallenge = require("meta.DailyChallenge")
local WeeklyChallenge = require("meta.WeeklyChallenge")
local SpatialHash = require("utils.SpatialHash")
local DamageStats = require("ui.DamageStats")

local Enemy = {}

-- 对象池
Enemy.pool = {}
-- 活跃敌人列表
Enemy.active = {}
-- 当前 Boss 引用（方便 HUD 读取）
Enemy.currentBoss = nil
-- Boss 定义引用（来自 Config.BOSSES）
Enemy.currentBossDef = nil

-- 空间哈希（用于加速碰撞/范围查询）
Enemy._spatialHash = SpatialHash.New(200)
local _enemyNearby = {}  -- 复用查询缓冲区

--- 从池中取出或新建敌人
local function GetFromPool()
    local e = table.remove(Enemy.pool)
    if e then return e end
    return {
        x = 0, y = 0,
        hp = 0, maxHp = 0,
        atk = 0, speed = 0,
        radius = 0,
        expDrop = 0,
        typeName = "normal",
        alive = false,
        hitFlash = 0,
        emoji = "",
        -- 行为参数
        behaviorTimer = 0,
        behaviorPhase = 0,
        dashCooldown = 0,
        -- charger 专用
        chargeState = 0,
        chargeDirX = 0,
        chargeDirY = 0,
        -- ghost 专用
        blinkTimer = 0,
        -- ranger 专用
        shootTimer = 0,
        -- Boss 专用
        isBoss = false,
        bossDef = nil,          -- Config.BOSSES[i] 引用
        bossSkillTimers = {},   -- 每个技能独立 CD
        bossStunTimer = 0,      -- 眩晕剩余时间
        bossDashing = false,    -- 冲刺中
        bossDashTimer = 0,
        bossDashDirX = 0,
        bossDashDirY = 0,
        bossDashSpeed = 0,
        bossDashDamage = 0,
        bossDashRadius = 0,
        bossBurstQueue = {},    -- 连射队列 { {delay, targetX, targetY, speed, dmg, emoji, color}, ... }
        bossColor = nil,        -- Boss 自定义颜色
        -- 冰冻系统
        freezeStacks = 0,       -- 冰冻层数
        freezeTimer = 0,        -- 完全冻结剩余时间
        freezeImmunityCD = 0,   -- Boss 冻结免疫CD（7秒）
        freezeCount = 0,        -- 已触发冻结次数（每次阈值+3）
        freezeDecayTimer = 0,   -- 冰冻层数衰减计时器（2s未增加则清空）
        -- 击退系统
        knockbackTimer = 0,     -- 击退剩余时间
        knockbackDirX = 0,      -- 击退方向X
        knockbackDirY = 0,      -- 击退方向Y
        -- 死亡动画
        dying = false,          -- 是否正在播放死亡动画
        deathTimer = 0,         -- 死亡动画剩余时间
        -- 精英词缀
        eliteMod = nil,         -- 精英修饰符: "aura_heal"|"aura_speed"|"shield"|"enrage"
        shieldHp = 0,           -- 护盾剩余血量
        shieldMaxHp = 0,        -- 护盾最大血量
        eliteAuraTimer = 0,     -- 光环周期计时器
        enraged = false,        -- 是否已触发狂暴
    }
end

--- 回收敌人到池中
local function Recycle(e)
    e.alive = false
    e.isBoss = false
    e.bossId = nil
    e.bossDef = nil
    e.bossSkillTimers = {}
    e.bossStunTimer = 0
    e.bossDashing = false
    e.bossBurstQueue = {}
    e.bossColor = nil
    e.freezeStacks = 0
    e.freezeTimer = 0
    e.freezeImmunityCD = 0
    e.freezeCount = 0
    e.freezeDecayTimer = 0
    e.knockbackTimer = 0
    e.knockbackDirX = 0
    e.knockbackDirY = 0
    e.charmed = false
    e.charmedInvincible = false
    e.dying = false
    e.deathTimer = 0
    e.eliteMod = nil
    e.shieldHp = 0
    e.shieldMaxHp = 0
    e.eliteAuraTimer = 0
    e.enraged = false
    table.insert(Enemy.pool, e)
end

--- 重置所有敌人
function Enemy.Reset()
    for i = #Enemy.active, 1, -1 do
        Recycle(Enemy.active[i])
        table.remove(Enemy.active, i)
    end
    Enemy.currentBoss = nil
    Enemy.currentBossDef = nil
end

--- 生成敌人
function Enemy.Spawn(x, y, typeName, waveCoeff)
    if #Enemy.active >= Config.WAVE.maxEnemiesAlive then return end

    local def = Config.ENEMY[typeName]
    if not def then return end

    local e = GetFromPool()
    e.x = x
    e.y = y
    local hp = SM.mulFloor(def.baseHp, waveCoeff)
    local atk = SM.mulFloor(def.baseAtk, waveCoeff)
    local spd = def.speed
    -- 难度乘数（ATK独立修正、速度修正）
    local diff = Config.GetDifficulty()
    atk = SM.mulFloor(atk, diff.enemyAtkMult / diff.enemyHpMult)  -- waveCoeff已含HP乘数，ATK需补偿差值
    spd = math.floor(spd * diff.enemySpeedMult)
    -- 每日挑战：属性修改器
    if DailyChallenge.active then
        if DailyChallenge.HasFactor("enemy_hp") then hp = hp * 2 end
        if DailyChallenge.HasFactor("enemy_atk") then atk = atk * 2 end
        if DailyChallenge.HasFactor("enemy_spd") then spd = spd * 2 end
        -- 精英怪属性翻倍
        if typeName == "elite" then
            hp = hp * 2
            atk = atk * 2
        end
    end
    -- 周挑战修正器
    local wcSpd = WeeklyChallenge.GetMod("enemySpeedMul")
    if wcSpd then spd = math.floor(spd * wcSpd) end
    local wcAtk = WeeklyChallenge.GetMod("enemyAtkMul")
    if wcAtk then atk = SM.mulFloor(atk, wcAtk) end

    e.maxHp = hp
    e.hp = e.maxHp
    e.atk = atk
    e.speed = spd
    e.radius = def.radius
    e.expDrop = def.expDrop
    e.typeName = typeName
    e.alive = true
    e.hitFlash = 0
    e.behaviorTimer = 0
    e.behaviorPhase = math.random() * 6.28
    e.dashCooldown = 0
    e.chargeState = 0
    e.chargeDirX = 0
    e.chargeDirY = 0
    e.blinkTimer = math.random() * 2 + 2
    e.shootTimer = 0
    e.isBoss = false
    e.bossDef = nil
    e.bossSkillTimers = {}
    e.bossStunTimer = 0
    e.bossDashing = false
    e.bossBurstQueue = {}
    e.bossColor = nil
    e.freezeStacks = 0
    e.freezeTimer = 0
    e.freezeImmunityCD = 0
    e.freezeCount = 0
    e.freezeDecayTimer = 0
    e.knockbackTimer = 0
    e.knockbackDirX = 0
    e.knockbackDirY = 0
    e.charmed = false
    e.charmedInvincible = false

    -- emoji 分配：每日挑战使用固定 emoji，否则优先使用地图专属 emoji 组
    if DailyChallenge.active and DailyChallenge.todayConfig then
        e.emoji = DailyChallenge.todayConfig.enemyEmoji
    else
        local MapVariant = require("battle.MapVariant")
        local emojiList = MapVariant.GetEnemyEmojiList(typeName) or Config.ENEMY_EMOJI[typeName]
        if emojiList and #emojiList > 0 then
            e.emoji = emojiList[math.random(1, #emojiList)]
        else
            e.emoji = "👾"
        end
    end

    -- 精英词缀分配（仅 elite 类型，波次5+）
    e.eliteMod = nil
    e.shieldHp = 0
    e.shieldMaxHp = 0
    e.eliteAuraTimer = 0
    e.enraged = false
    if typeName == "elite" then
        local waveNum = require("battle.Wave").waveNum
        local modChance = 0
        if waveNum >= 12 then modChance = 1.0
        elseif waveNum >= 8 then modChance = 0.6
        elseif waveNum >= 5 then modChance = 0.3
        end
        if math.random() < modChance then
            local mods = { "aura_heal", "aura_speed", "shield", "enrage" }
            e.eliteMod = mods[math.random(1, #mods)]
            if e.eliteMod == "shield" then
                e.shieldMaxHp = SM.mulFloor(e.maxHp, 0.4)
                e.shieldHp = e.shieldMaxHp
            end
        end
    end

    table.insert(Enemy.active, e)
    return e
end

--- 生成 Boss（使用 Config.BOSSES 定义）
function Enemy.SpawnBoss(x, y, bossDef, waveCoeff)
    local e = GetFromPool()
    e.x = x
    e.y = y
    local bossHp = SM.mulFloor(bossDef.baseHp, waveCoeff)
    local wcBossHp = WeeklyChallenge.GetMod("bossHpMul")
    if wcBossHp then bossHp = SM.mulFloor(bossHp, wcBossHp) end
    e.maxHp = bossHp
    e.hp = e.maxHp
    e.atk = 0  -- Boss 无接触伤害
    local bossSpd = bossDef.speed
    local wcSpd2 = WeeklyChallenge.GetMod("enemySpeedMul")
    if wcSpd2 then bossSpd = math.floor(bossSpd * wcSpd2) end
    e.speed = bossSpd
    e.radius = bossDef.radius
    e.expDrop = bossDef.expDrop
    e.typeName = "boss"
    e.alive = true
    e.hitFlash = 0
    e.behaviorTimer = 0
    e.behaviorPhase = math.random() * 6.28
    e.dashCooldown = 0
    e.chargeState = 0
    e.blinkTimer = 0
    e.shootTimer = 0
    e.emoji = bossDef.emoji
    e.isBoss = true
    e.bossId = bossDef.id
    e.bossDef = bossDef
    e.bossColor = bossDef.color
    e.bossStunTimer = 0
    e.bossDashing = false
    e.bossBurstQueue = {}
    e.freezeStacks = 0
    e.freezeTimer = 0
    e.freezeImmunityCD = 0
    e.freezeCount = 0
    e.freezeDecayTimer = 0
    e.knockbackTimer = 0
    e.knockbackDirX = 0
    e.knockbackDirY = 0
    e.charmed = false
    e.charmedInvincible = false

    -- 初始化每个技能的 CD（第一次使用延迟 2~4 秒）
    e.bossSkillTimers = {}
    for i, sk in ipairs(bossDef.skills) do
        e.bossSkillTimers[i] = sk.interval * 0.3 + math.random() * 2.0
    end

    table.insert(Enemy.active, e)
    Enemy.currentBoss = e
    Enemy.currentBossDef = bossDef
    return e
end

--- 在玩家周围随机位置生成敌人
function Enemy.SpawnAroundPlayer(playerX, playerY, typeName, waveCoeff)
    local MapVariant = require("battle.MapVariant")
    local angle = math.random() * math.pi * 2
    local dist = Config.WAVE.spawnMinRadius +
        math.random() * (Config.WAVE.spawnRadius - Config.WAVE.spawnMinRadius)
    local x = playerX + math.cos(angle) * dist
    local y = playerY + math.sin(angle) * dist
    x = math.max(50, math.min(Config.WORLD_SIZE - 50, x))
    y = math.max(50, math.min(Config.WORLD_SIZE - 50, y))
    -- 避免在障碍物内生成：推离
    x, y = MapVariant.ResolveCollision(x, y, 20)
    Enemy.Spawn(x, y, typeName, waveCoeff)
end

--- 在玩家周围生成 Boss
function Enemy.SpawnBossAroundPlayer(playerX, playerY, bossDef, waveCoeff)
    local angle = math.random() * math.pi * 2
    local dist = Config.WAVE.spawnMinRadius + 50
    local x = playerX + math.cos(angle) * dist
    local y = playerY + math.sin(angle) * dist
    x = math.max(80, math.min(Config.WORLD_SIZE - 80, x))
    y = math.max(80, math.min(Config.WORLD_SIZE - 80, y))
    return Enemy.SpawnBoss(x, y, bossDef, waveCoeff)
end

-- ============================================================================
-- Boss 技能执行
-- ============================================================================

local function ExecBossSkill(e, skillDef, playerX, playerY)
    local col = e.bossColor or { 255, 50, 150 }
    local stype = skillDef.type
    local isCharmed = e.charmed

    -- 魅惑Boss：记录子弹数量，稍后标记新生成的子弹
    local bulletsBefore = isCharmed and #EnemyBullet.active or 0

    if stype == "shoot_fan" then
        EnemyBullet.SpawnFan(e.x, e.y, playerX, playerY,
            skillDef.bulletCount, skillDef.bulletSpeed, skillDef.damage,
            skillDef.spreadAngle, skillDef.icon, col)

    elseif stype == "shoot_burst" then
        -- 连续射击：放入队列
        for i = 0, skillDef.bulletCount - 1 do
            table.insert(e.bossBurstQueue, {
                delay = i * (skillDef.burstDelay or 0.2),
                targetX = playerX,
                targetY = playerY,
                speed = skillDef.bulletSpeed,
                damage = skillDef.damage,
                emoji = skillDef.icon,
                color = col,
                charmedBullet = isCharmed or false,
            })
        end

    elseif stype == "shoot_target" then
        EnemyBullet.Spawn(e.x, e.y, playerX, playerY,
            skillDef.damage, skillDef.bulletSpeed, skillDef.icon, col,
            skillDef.bulletRadius)

    elseif stype == "shoot_radial" then
        EnemyBullet.SpawnRadial(e.x, e.y, skillDef.bulletCount,
            skillDef.bulletSpeed, skillDef.damage, skillDef.icon, col)

    elseif stype == "shoot_split" then
        EnemyBullet.SpawnSplit(e.x, e.y, playerX, playerY,
            skillDef.bulletSpeed, skillDef.damage,
            skillDef.splitCount, skillDef.splitSpeed, skillDef.splitDamage,
            skillDef.icon, col)

    elseif stype == "dash" then
        -- 冲刺：锁定方向
        local dx = playerX - e.x
        local dy = playerY - e.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 1 then
            e.bossDashing = true
            e.bossDashTimer = skillDef.dashDuration
            e.bossDashDirX = dx / dist
            e.bossDashDirY = dy / dist
            e.bossDashSpeed = skillDef.dashSpeed
            e.bossDashDamage = skillDef.damage
            e.bossDashRadius = skillDef.dashRadius or 50
        end

    elseif stype == "area_rain" then
        -- 在玩家周围随机落石
        local range = skillDef.spawnRange or 200
        for _ = 1, skillDef.count do
            local rx = playerX + (math.random() - 0.5) * range * 2
            local ry = playerY + (math.random() - 0.5) * range * 2
            EnemyBullet.AddArea({
                type = "rain",
                x = rx, y = ry,
                damage = skillDef.damage,
                radius = skillDef.radius or 30,
                timer = skillDef.fallDuration or 0.8,
                fallDuration = skillDef.fallDuration or 0.8,
                landed = false,
                charmed = isCharmed or false,
            })
        end

    elseif stype == "area_circle" then
        -- 持续毒圈
        EnemyBullet.AddArea({
            type = "circle",
            x = e.x, y = e.y,
            damage = skillDef.damage,
            radius = skillDef.radius or 120,
            timer = skillDef.duration or 3.0,
            tickInterval = skillDef.tickInterval or 0.5,
            tickTimer = 0,
            color = col,
            charmed = isCharmed or false,
        })

    elseif stype == "blink_attack" then
        -- 先在原地放弹幕，然后传送到玩家附近
        EnemyBullet.SpawnRadial(e.x, e.y, skillDef.bulletCount,
            skillDef.bulletSpeed, skillDef.damage, skillDef.icon, col)
        -- 传送（最小距离150，避免闪现到玩家脸上）
        local blinkAngle = math.random() * 6.28
        local blinkDist = math.max(150, skillDef.blinkRange or 160)
        e.x = playerX + math.cos(blinkAngle) * blinkDist
        e.y = playerY + math.sin(blinkAngle) * blinkDist
        e.x = math.max(80, math.min(Config.WORLD_SIZE - 80, e.x))
        e.y = math.max(80, math.min(Config.WORLD_SIZE - 80, e.y))
    end

    -- 大招眩晕
    if skillDef.isUltimate and skillDef.stunDuration then
        e.bossStunTimer = skillDef.stunDuration
    end

    -- 吸血鬼大招回血
    if skillDef.healPercent then
        local healAmt = SM.mulFloor(e.maxHp, skillDef.healPercent)
        e.hp = math.min(e.maxHp, e.hp + healAmt)
    end

    -- 魅惑Boss：标记所有新生成的子弹为 charmedBullet
    if isCharmed then
        for bi = bulletsBefore + 1, #EnemyBullet.active do
            EnemyBullet.active[bi].charmedBullet = true
        end
    end
end

-- ============================================================================
-- 更新所有敌人
-- ============================================================================

-- 预收集列表（复用，避免 GC）
local _auraElites = {}

function Enemy.Update(dt, playerX, playerY)
    -- 重建空间哈希（每帧一次，InsertAll 只插入 alive 的）
    Enemy._spatialHash:Clear()
    Enemy._spatialHash:InsertAll(Enemy.active)

    -- 预收集 aura_speed 精英位置（O(n) 一次，替代 O(n²) 逐个查找）
    local auraCount = 0
    for _, e in ipairs(Enemy.active) do
        if e.alive and not e.dying and e.eliteMod == "aura_speed" then
            auraCount = auraCount + 1
            local ae = _auraElites[auraCount]
            if not ae then
                ae = {}
                _auraElites[auraCount] = ae
            end
            ae.x = e.x
            ae.y = e.y
        end
    end

    for i = #Enemy.active, 1, -1 do
        local e = Enemy.active[i]
        if not e.alive then
            if e.isBoss and Enemy.currentBoss == e then
                Enemy.currentBoss = nil
                Enemy.currentBossDef = nil
            end
            table.remove(Enemy.active, i)
            Recycle(e)
        elseif e.dying then
            -- 死亡动画倒计时
            e.deathTimer = e.deathTimer - dt
            if e.deathTimer <= 0 then
                e.alive = false  -- 动画结束，标记回收
            end
        else
            local dx = playerX - e.x
            local dy = playerY - e.y
            local dist = math.sqrt(dx * dx + dy * dy)

            e.behaviorTimer = e.behaviorTimer + dt

            -- 魅惑敌人：非Boss跳过AI（由 Skill.lua 控制），Boss保留AI但目标改为最近敌人
            if e.charmed and not e.isBoss then
                if e.hitFlash > 0 then e.hitFlash = e.hitFlash - dt end
                goto continue
            end

            -- 魅惑Boss：重新计算目标为最近的非魅惑敌人（空间哈希加速）
            -- 🔴 修复：使用 per-entity 局部目标，不再覆写函数参数 playerX/playerY
            local targetX, targetY = playerX, playerY
            if e.charmed and e.isBoss then
                local nearDist2 = 600 * 600  -- 搜索半径 600px
                local foundTarget = false
                for ni = #_enemyNearby, 1, -1 do _enemyNearby[ni] = nil end
                Enemy._spatialHash:QueryInto(e.x, e.y, 600, _enemyNearby)
                for ni = 1, #_enemyNearby do
                    local other = _enemyNearby[ni]
                    if other.alive and not other.charmed and other ~= e then
                        local odx = other.x - e.x
                        local ody = other.y - e.y
                        local od2 = odx * odx + ody * ody
                        if od2 < nearDist2 then
                            nearDist2 = od2
                            dx = other.x - e.x
                            dy = other.y - e.y
                            dist = math.sqrt(od2)
                            targetX = other.x
                            targetY = other.y
                            foundTarget = true
                        end
                    end
                end
                if not foundTarget then
                    if e.hitFlash > 0 then e.hitFlash = e.hitFlash - dt end
                    goto continue
                end
            end

            -- 击退系统更新（优先于其他移动）
            if e.knockbackTimer > 0 then
                e.knockbackTimer = e.knockbackTimer - dt
                e.x = e.x + e.knockbackDirX * 3000 * dt
                e.y = e.y + e.knockbackDirY * 3000 * dt
                -- 限制在世界边界内
                local eR = e.radius or 14
                e.x = math.max(eR, math.min(Config.WORLD_SIZE - eR, e.x))
                e.y = math.max(eR, math.min(Config.WORLD_SIZE - eR, e.y))
                if e.hitFlash > 0 then e.hitFlash = e.hitFlash - dt end
                goto continue
            end

            -- 冰冻系统计时器更新
            if e.freezeImmunityCD > 0 then
                e.freezeImmunityCD = e.freezeImmunityCD - dt
            end
            if e.freezeTimer > 0 then
                e.freezeTimer = e.freezeTimer - dt
                if e.freezeTimer <= 0 then
                    e.freezeTimer = 0
                    e.freezeStacks = 0  -- 冻结结束清空层数
                end
                -- 完全冻结：不移动（Boss连射队列仍处理，但不移动不放技能）
                if not e.isBoss then
                    if e.hitFlash > 0 then e.hitFlash = e.hitFlash - dt end
                    goto continue
                end
            end

            -- 冰冻层数衰减：2秒未增加新层数则清空
            if e.freezeStacks > 0 and e.freezeTimer <= 0 then
                e.freezeDecayTimer = e.freezeDecayTimer + dt
                if e.freezeDecayTimer >= 2.0 then
                    e.freezeStacks = 0
                    e.freezeDecayTimer = 0
                end
            end

            -- 冰冻减速倍率
            local freezeMult = Enemy.GetFreezeSpeedMult(e)

            -- 精英光环加速被动：被附近 aura_speed 精英加速40%（预收集 O(k) 替代 O(n²)）
            if not e.isBoss and freezeMult > 0 and auraCount > 0 then
                for ai = 1, auraCount do
                    local ae = _auraElites[ai]
                    local adx = e.x - ae.x
                    local ady = e.y - ae.y
                    if adx * adx + ady * ady <= 150 * 150 then
                        freezeMult = freezeMult * 1.4
                        break  -- 不叠加
                    end
                end
            end

            -- ========== Boss AI ==========
            if e.isBoss then
                -- 处理连射队列
                for qi = #e.bossBurstQueue, 1, -1 do
                    local bq = e.bossBurstQueue[qi]
                    bq.delay = bq.delay - dt
                    if bq.delay <= 0 then
                        local cb = EnemyBullet.Spawn(e.x, e.y, bq.targetX, bq.targetY,
                            bq.damage, bq.speed, bq.emoji, bq.color)
                        if bq.charmedBullet then
                            cb.charmedBullet = true
                        end
                        table.remove(e.bossBurstQueue, qi)
                    end
                end

                -- 眩晕中：不移动不攻击
                if e.bossStunTimer > 0 then
                    e.bossStunTimer = e.bossStunTimer - dt
                    if e.hitFlash > 0 then e.hitFlash = e.hitFlash - dt end
                    goto continue
                end

                -- 冲刺中
                if e.bossDashing then
                    e.bossDashTimer = e.bossDashTimer - dt
                    e.x = e.x + e.bossDashDirX * e.bossDashSpeed * dt
                    e.y = e.y + e.bossDashDirY * e.bossDashSpeed * dt
                    -- 冲刺碰撞检测（对玩家造成伤害通过 BattleScene 处理）
                    if e.bossDashTimer <= 0 then
                        e.bossDashing = false
                    end
                    if e.hitFlash > 0 then e.hitFlash = e.hitFlash - dt end
                    goto continue
                end

                -- 技能 CD 更新（完全冻结时不放技能）
                if e.bossDef and e.bossDef.skills and freezeMult > 0 then
                    for si, sk in ipairs(e.bossDef.skills) do
                        e.bossSkillTimers[si] = (e.bossSkillTimers[si] or sk.interval) - dt
                        if e.bossSkillTimers[si] <= 0 then
                            e.bossSkillTimers[si] = sk.interval
                            ExecBossSkill(e, sk, targetX, targetY)
                        end
                    end
                end

                -- Boss 移动：缓慢靠近玩家（保持中等距离）—— 受冰冻减速
                if dist > 1 and freezeMult > 0 then
                    local moveX, moveY = dx / dist, dy / dist
                    local idealDist = 200
                    if dist > idealDist then
                        e.x = e.x + moveX * e.speed * freezeMult * dt
                        e.y = e.y + moveY * e.speed * freezeMult * dt
                    elseif dist < idealDist * 0.5 then
                        -- 太近了，后退
                        e.x = e.x - moveX * e.speed * 0.5 * freezeMult * dt
                        e.y = e.y - moveY * e.speed * 0.5 * freezeMult * dt
                    end
                end

            -- ========== Ranger AI（远程怪）==========
            elseif e.typeName == "ranger" then
                local rDef = Config.ENEMY.ranger
                e.shootTimer = e.shootTimer + dt

                if dist > 1 then
                    local moveX, moveY = dx / dist, dy / dist
                    local keepDist = rDef.keepDistance or 180
                    local spd = e.speed * freezeMult

                    if dist > rDef.shootRange then
                        e.x = e.x + moveX * spd * dt
                        e.y = e.y + moveY * spd * dt
                    elseif dist < keepDist * 0.7 then
                        e.x = e.x - moveX * spd * 1.2 * dt
                        e.y = e.y - moveY * spd * 1.2 * dt
                    else
                        e.behaviorPhase = e.behaviorPhase + dt * 3
                        local perpX = -moveY
                        local perpY = moveX
                        local orbDir = math.sin(e.behaviorPhase) > 0 and 1 or -1
                        e.x = e.x + perpX * orbDir * spd * 0.6 * dt
                        e.y = e.y + perpY * orbDir * spd * 0.6 * dt
                    end

                    -- 射击
                    if e.shootTimer >= (rDef.shootInterval or 2.0) and dist <= (rDef.shootRange or 250) then
                        e.shootTimer = 0
                        local bSpeed = rDef.bulletSpeed or 280
                        EnemyBullet.Spawn(e.x, e.y, targetX, targetY,
                            e.atk, bSpeed, "🔸", { 255, 150, 0 })
                    end
                end

            -- ========== 原有 AI ==========
            elseif dist > 1 then
                local moveX, moveY = dx / dist, dy / dist
                local spd = e.speed * freezeMult  -- 应用冰冻减速

                if e.typeName == "fast" then
                    e.behaviorPhase = e.behaviorPhase + dt * 8
                    local perpX = -moveY
                    local perpY = moveX
                    local wiggle = math.sin(e.behaviorPhase) * 0.6
                    moveX = moveX + perpX * wiggle
                    moveY = moveY + perpY * wiggle
                    local len = math.sqrt(moveX * moveX + moveY * moveY)
                    if len > 0.01 then moveX = moveX / len; moveY = moveY / len end

                    e.dashCooldown = e.dashCooldown - dt
                    local speedMult = 1.0
                    if e.dashCooldown <= 0 then e.dashCooldown = 3.0 + math.random() * 2.0 end
                    if e.dashCooldown > 2.5 then speedMult = 1.8 end

                    e.x = e.x + moveX * spd * speedMult * dt
                    e.y = e.y + moveY * spd * speedMult * dt

                elseif e.typeName == "swarm" then
                    e.behaviorPhase = e.behaviorPhase + dt * 12
                    local jitterX = math.sin(e.behaviorPhase) * 0.3
                    local jitterY = math.cos(e.behaviorPhase * 1.3) * 0.3
                    e.x = e.x + (moveX + jitterX) * spd * dt
                    e.y = e.y + (moveY + jitterY) * spd * dt

                elseif e.typeName == "charger" then
                    if e.chargeState == 0 then
                        e.x = e.x + moveX * spd * dt
                        e.y = e.y + moveY * spd * dt
                        if dist < 200 then
                            e.chargeState = 1
                            e.behaviorTimer = 0
                            e.chargeDirX = moveX
                            e.chargeDirY = moveY
                        end
                    elseif e.chargeState == 1 then
                        e.behaviorTimer = e.behaviorTimer + dt
                        if e.behaviorTimer >= 0.6 then
                            e.chargeState = 2
                            e.behaviorTimer = 0
                        end
                    else
                        e.behaviorTimer = e.behaviorTimer + dt
                        e.x = e.x + e.chargeDirX * spd * 4.0 * dt
                        e.y = e.y + e.chargeDirY * spd * 4.0 * dt
                        if e.behaviorTimer >= 0.5 then
                            e.chargeState = 0
                            e.behaviorTimer = 0
                        end
                    end

                elseif e.typeName == "ghost" then
                    e.blinkTimer = e.blinkTimer - dt
                    if e.blinkTimer <= 0 and freezeMult > 0 then
                        local blinkAngle = math.random() * 6.28
                        local blinkDist = 150 + math.random() * 80
                        e.x = targetX + math.cos(blinkAngle) * blinkDist
                        e.y = targetY + math.sin(blinkAngle) * blinkDist
                        e.x = math.max(50, math.min(Config.WORLD_SIZE - 50, e.x))
                        e.y = math.max(50, math.min(Config.WORLD_SIZE - 50, e.y))
                        e.blinkTimer = 2.5 + math.random() * 2.0
                    elseif e.blinkTimer > 0 then
                        e.behaviorPhase = e.behaviorPhase + dt * 5
                        local perpX = -moveY
                        local perpY = moveX
                        local drift = math.sin(e.behaviorPhase) * 0.8
                        e.x = e.x + (moveX * 0.4 + perpX * drift) * spd * dt
                        e.y = e.y + (moveY * 0.4 + perpY * drift) * spd * dt
                    end

                elseif e.typeName == "shaman" then
                    e.behaviorPhase = e.behaviorPhase + dt * 2.0
                    e.dashCooldown = e.dashCooldown - dt

                    if e.dashCooldown <= 0 and e.dashCooldown > -0.4 then
                        e.x = e.x + moveX * spd * 3.0 * dt
                        e.y = e.y + moveY * spd * 3.0 * dt
                        if e.dashCooldown <= -0.4 then
                            e.dashCooldown = 4.0 + math.random() * 2.0
                        end
                    else
                        local idealDist = 180
                        local perpX = -moveY
                        local perpY = moveX
                        local approach = (dist - idealDist) / idealDist
                        approach = math.max(-1, math.min(1, approach))
                        local orbitStr = 0.9
                        local finalX = moveX * approach * 0.5 + perpX * orbitStr
                        local finalY = moveY * approach * 0.5 + perpY * orbitStr
                        local len = math.sqrt(finalX * finalX + finalY * finalY)
                        if len > 0.01 then finalX = finalX / len; finalY = finalY / len end
                        e.x = e.x + finalX * spd * dt
                        e.y = e.y + finalY * spd * dt
                    end

                elseif e.typeName == "elite" then
                    e.behaviorPhase = e.behaviorPhase + dt * 2.5
                    local perpX = -moveY
                    local perpY = moveX
                    local circleStr = 0.7
                    local approachStr = 0.4
                    moveX = moveX * approachStr + perpX * circleStr * math.sin(e.behaviorPhase)
                    moveY = moveY * approachStr + perpY * circleStr * math.sin(e.behaviorPhase)
                    local len = math.sqrt(moveX * moveX + moveY * moveY)
                    if len > 0.01 then moveX = moveX / len; moveY = moveY / len end
                    e.x = e.x + moveX * spd * dt
                    e.y = e.y + moveY * spd * dt

                elseif e.typeName == "tank" then
                    local speedMult = 1.0
                    if dist < 80 then speedMult = 1.5 end
                    e.x = e.x + moveX * spd * speedMult * dt
                    e.y = e.y + moveY * spd * speedMult * dt

                else
                    -- normal: 直线追踪
                    e.x = e.x + moveX * spd * dt
                    e.y = e.y + moveY * spd * dt
                end
            end

            -- ===== 精英词缀效果 =====
            if e.eliteMod then
                if e.eliteMod == "aura_heal" then
                    -- 治愈光环：每2秒回复周围友军5% maxHp
                    e.eliteAuraTimer = e.eliteAuraTimer + dt
                    if e.eliteAuraTimer >= 2.0 then
                        e.eliteAuraTimer = 0
                        local auraR = 150
                        for _, other in ipairs(Enemy.active) do
                            if other ~= e and other.alive and not other.dying and not other.charmed then
                                local adx = e.x - other.x
                                local ady = e.y - other.y
                                if adx * adx + ady * ady <= auraR * auraR then
                                    other.hp = math.min(other.maxHp, other.hp + SM.mulFloor(other.maxHp, 0.05))
                                end
                            end
                        end
                    end
                elseif e.eliteMod == "enrage" then
                    -- 狂暴：50% 血以下触发
                    if not e.enraged and e.hp <= e.maxHp * 0.5 then
                        e.enraged = true
                        e.speed = e.speed * 1.5
                        e.atk = SM.mulFloor(e.atk, 1.8)
                    end
                end
            end

            -- 障碍物碰撞推离 + 世界边界
            local eR = e.radius or 14
            e.x = math.max(eR, math.min(Config.WORLD_SIZE - eR, e.x))
            e.y = math.max(eR, math.min(Config.WORLD_SIZE - eR, e.y))
            local MapVariant = require("battle.MapVariant")
            e.x, e.y = MapVariant.ResolveCollision(e.x, e.y, eR)

            -- 受击闪烁衰减
            if e.hitFlash > 0 then
                e.hitFlash = e.hitFlash - dt
            end

            ::continue::
        end
    end
end

--- 敌人受伤（支持冰冻伤害加成）
function Enemy.Damage(enemy, amount)
    -- 魅惑敌人无敌，不可被玩家伤害
    if enemy.charmed and enemy.charmedInvincible then
        return false, 0, false
    end
    -- 完全冻结状态下受到1.5倍伤害
    local finalAmount = amount
    local isFrozenHit = false
    if enemy.freezeTimer > 0 then
        finalAmount = SM.mulFloor(amount, 1.5)
        isFrozenHit = true
    end
    -- 护盾吸收伤害
    if enemy.shieldHp > 0 then
        if finalAmount <= enemy.shieldHp then
            enemy.shieldHp = enemy.shieldHp - finalAmount
            enemy.hitFlash = 0.1
            return false, finalAmount, isFrozenHit
        else
            finalAmount = finalAmount - enemy.shieldHp
            enemy.shieldHp = 0
        end
    end
    enemy.hp = enemy.hp - finalAmount
    enemy.hitFlash = 0.1
    -- 伤害统计追踪
    DamageStats.Record(DamageStats._currentSource, finalAmount)
    if enemy.hp <= 0 then
        -- 启动死亡动画（0.25秒缩放+渐隐）
        enemy.dying = true
        enemy.deathTimer = 0.25
        return true, finalAmount, isFrozenHit
    end
    return false, finalAmount, isFrozenHit
end

--- 给敌人叠加冰冻层数
--- 每层减10%移速，达到阈值完全冻结1秒
--- 阈值 = 5 + 3 * freezeCount（首次5层，之后每次+3）
--- 2秒未增加新层数则清空
function Enemy.ApplyFreezeStack(enemy)
    if not enemy.alive then return end
    -- 护盾激活时免疫冻结
    if enemy.shieldHp > 0 then return end
    -- Boss有7秒冻结免疫CD
    if enemy.isBoss and enemy.freezeImmunityCD > 0 then return end
    -- 完全冻结中不叠加
    if enemy.freezeTimer > 0 then return end

    enemy.freezeStacks = enemy.freezeStacks + 1
    enemy.freezeDecayTimer = 0  -- 重置衰减计时器

    local threshold = 5 + 3 * enemy.freezeCount
    if enemy.freezeStacks >= threshold then
        -- 达到阈值触发完全冻结
        enemy.freezeStacks = 0
        enemy.freezeTimer = 1.0  -- 冻结1秒
        enemy.freezeCount = enemy.freezeCount + 1  -- 下次阈值+3
        if enemy.isBoss then
            enemy.freezeImmunityCD = 7.0  -- Boss 7秒冻结免疫
        end
    end
end

--- 获取敌人当前冰冻阈值
function Enemy.GetFreezeThreshold(enemy)
    return 5 + 3 * enemy.freezeCount
end

--- 对敌人施加击退（持续0.2s，速度400，方向为子弹飞行方向的反方向）
---@param enemy table 敌人对象
---@param bulletVx number 子弹速度X分量
---@param bulletVy number 子弹速度Y分量
function Enemy.ApplyKnockback(enemy, bulletVx, bulletVy)
    if not enemy.alive then return end
    if enemy.isBoss then return end  -- Boss免疫击退
    if enemy.shieldHp > 0 then return end  -- 护盾激活时免疫击退
    if enemy.freezeTimer > 0 then return end  -- 完全冻结中不击退
    -- 计算子弹飞行方向（敌人被推向子弹前进方向）
    local spd = math.sqrt(bulletVx * bulletVx + bulletVy * bulletVy)
    if spd < 1 then return end
    enemy.knockbackDirX = bulletVx / spd
    enemy.knockbackDirY = bulletVy / spd
    enemy.knockbackTimer = 0.05
end

--- 获取冰冻减速倍率（0~1，1=正常速度）
function Enemy.GetFreezeSpeedMult(enemy)
    if enemy.freezeTimer > 0 then return 0 end  -- 完全冻结
    return math.max(0, 1.0 - enemy.freezeStacks * 0.1)  -- 每层减10%，最低0
end

--- 检查与玩家碰撞的敌人（排除 Boss）— 空间哈希加速
function Enemy.CheckPlayerCollision(playerX, playerY, playerRadius)
    local hits = {}
    local maxEnemyR = 30  -- 敌人最大半径上界，确保不漏检
    local queryR = playerRadius + maxEnemyR
    Enemy._spatialHash:Query(playerX, playerY, queryR, function(e)
        if e.alive and not e.dying and not e.isBoss and not e.charmed then
            local ddx = e.x - playerX
            local ddy = e.y - playerY
            local distSq = ddx * ddx + ddy * ddy
            local radSum = e.radius + playerRadius
            if distSq <= radSum * radSum then
                hits[#hits + 1] = e
            end
        end
    end)
    return hits
end

--- 检查 Boss 冲刺是否撞到玩家（排除魅惑Boss）
function Enemy.CheckBossDashCollision(playerX, playerY, playerRadius)
    local damage = 0
    for _, e in ipairs(Enemy.active) do
        if e.alive and e.isBoss and e.bossDashing and not e.charmed then
            local ddx = e.x - playerX
            local ddy = e.y - playerY
            local distSq = ddx * ddx + ddy * ddy
            local radSum = e.bossDashRadius + playerRadius
            if distSq <= radSum * radSum then
                damage = SM.add(damage, e.bossDashDamage)
                e.bossDashing = false  -- 撞到后停止冲刺
            end
        end
    end
    return damage
end

--- 检查魅惑 Boss 冲刺是否撞到非魅惑敌人，返回击杀列表
function Enemy.CheckCharmedBossDashCollision()
    local killed = {}
    for _, e in ipairs(Enemy.active) do
        if e.alive and e.isBoss and e.bossDashing and e.charmed then
            -- 空间哈希加速：只查询冲刺半径内的敌人
            local searchR = e.bossDashRadius + 30
            for ni = #_enemyNearby, 1, -1 do _enemyNearby[ni] = nil end
            Enemy._spatialHash:QueryInto(e.x, e.y, searchR, _enemyNearby)
            for ni = 1, #_enemyNearby do
                local target = _enemyNearby[ni]
                if target.alive and not target.charmed and target ~= e then
                    local ddx = e.x - target.x
                    local ddy = e.y - target.y
                    local distSq = ddx * ddx + ddy * ddy
                    local radSum = e.bossDashRadius + (target.radius or 15)
                    if distSq <= radSum * radSum then
                        local dmg = math.max(1, SM.floor(e.bossDashDamage))
                        target.hp = target.hp - dmg
                        target.hitFlash = 0.15
                        if target.hp <= 0 then
                            target.dying = true
                            target.deathTimer = 0.25
                            table.insert(killed, target)
                        end
                    end
                end
            end
            e.bossDashing = false  -- 撞到后停止冲刺
        end
    end
    return killed
end

--- 找到最近的敌人 — 空间哈希加速
function Enemy.GetNearest(px, py, maxRange)
    local nearest = nil
    local nearestDist = maxRange * maxRange
    Enemy._spatialHash:Query(px, py, maxRange, function(e)
        if e.alive and not e.dying and not e.charmed then
            local ddx = e.x - px
            local ddy = e.y - py
            local distSq = ddx * ddx + ddy * ddy
            if distSq < nearestDist then
                nearestDist = distSq
                nearest = e
            end
        end
    end)
    return nearest, nearest and math.sqrt(nearestDist) or 0
end

--- 范围内所有敌人 — 空间哈希加速
function Enemy.GetInRange(px, py, range)
    local result = {}
    local rangeSq = range * range
    Enemy._spatialHash:Query(px, py, range, function(e)
        if e.alive and not e.dying then
            local ddx = e.x - px
            local ddy = e.y - py
            if ddx * ddx + ddy * ddy <= rangeSq then
                result[#result + 1] = e
            end
        end
    end)
    return result
end

--- 渲染所有敌人
function Enemy.Render(vg, camX, camY, viewW, viewH)
    local margin = 60
    for _, e in ipairs(Enemy.active) do
        if e.alive or e.dying then
            local sx = e.x - camX
            local sy = e.y - camY

            -- 死亡动画：缩放+渐隐
            local deathScale = 1.0
            local deathAlpha = 1.0
            if e.dying then
                local progress = 1.0 - (e.deathTimer / 0.25) -- 0→1
                deathScale = 1.0 + progress * 0.5  -- 放大到1.5倍
                deathAlpha = 1.0 - progress         -- 渐隐到0
            end

            if sx > -margin and sx < viewW + margin and sy > -margin and sy < viewH + margin then
                -- 获取颜色
                local col
                if e.bossColor then
                    col = e.bossColor
                else
                    local enemyDef = Config.ENEMY[e.typeName]
                    if enemyDef then
                        col = Config.COLORS[enemyDef.color] or Config.COLORS.enemyNormal
                    else
                        col = Config.COLORS.enemyNormal
                    end
                end

                -- 死亡动画：设置全局透明度
                if e.dying then
                    nvgGlobalAlpha(vg, deathAlpha)
                end

                -- 受击闪白（dying 跳过）
                if not e.dying and e.hitFlash > 0 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, e.radius + 2)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
                    nvgFill(vg)
                end

                -- 红色发光（底层光晕，让敌人更醒目）
                if not e.dying then
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, e.radius + 8)
                    nvgFillColor(vg, nvgRGBA(255, 30, 30, 25))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, e.radius + 3)
                    nvgFillColor(vg, nvgRGBA(255, 50, 50, 40))
                    nvgFill(vg)
                end

                -- 底部阴影
                nvgBeginPath(vg)
                nvgEllipse(vg, sx, sy + e.radius + 2, e.radius * 0.6 * deathScale, 3)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
                nvgFill(vg)

                -- 霓虹外发光圈（dying 跳过）
                if not e.dying then
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, e.radius + 4)
                    nvgStrokeColor(vg, nvgRGBA(col[1], col[2], col[3], 50))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                end

                -- 冰冻/状态特效（dying 跳过）
                if not e.dying then
                    if e.freezeTimer > 0 then
                        -- 完全冻结：蓝色冰晶光环
                        local icePulse = 0.6 + 0.4 * math.sin(e.behaviorTimer * 6)
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy, e.radius + 10)
                        nvgFillColor(vg, nvgRGBA(100, 200, 255, math.floor(60 * icePulse)))
                        nvgFill(vg)
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy, e.radius + 6)
                        nvgStrokeColor(vg, nvgRGBA(150, 220, 255, 200))
                        nvgStrokeWidth(vg, 2.5)
                        nvgStroke(vg)
                        -- 冰晶粒子
                        for ci = 0, 3 do
                            local ca = e.behaviorTimer * 3 + ci * 1.57
                            local cx = sx + math.cos(ca) * (e.radius + 8)
                            local cy = sy + math.sin(ca) * (e.radius + 8)
                            nvgFontSize(vg, 12)
                            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                            nvgFillColor(vg, nvgRGBA(200, 240, 255, 220))
                            nvgText(vg, cx, cy, "❄️")
                        end
                    elseif e.freezeStacks > 0 then
                        -- 部分冰冻：蓝色色调叠加
                        local iceAlpha = e.freezeStacks * 25
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy, e.radius + 4)
                        nvgFillColor(vg, nvgRGBA(100, 180, 255, iceAlpha))
                        nvgFill(vg)
                        -- 冰冻层数指示（当前/阈值）
                        local threshold = Enemy.GetFreezeThreshold(e)
                        nvgFontSize(vg, 10)
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
                        nvgText(vg, sx + e.radius + 6, sy - e.radius - 2, e.freezeStacks .. "/" .. threshold)
                    end

                    -- 冲锋怪蓄力警告
                    if e.typeName == "charger" and e.chargeState == 1 then
                        local pulse = 0.5 + 0.5 * math.sin(e.behaviorTimer * 20)
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy, e.radius + 6 + pulse * 4)
                        nvgStrokeColor(vg, nvgRGBA(255, 255, 50, math.floor(120 + pulse * 135)))
                        nvgStrokeWidth(vg, 2.5)
                        nvgStroke(vg)
                    end

                    -- 幽灵半透明
                    if e.typeName == "ghost" and e.blinkTimer > 0 then
                        local ghostAlpha = 0.5 + 0.3 * math.sin(e.behaviorPhase * 3)
                        nvgGlobalAlpha(vg, ghostAlpha)
                    end

                    -- Boss 眩晕特效
                    if e.isBoss and e.bossStunTimer > 0 then
                        -- 眩晕光圈（旋转星星）
                        local stunAngle = e.behaviorTimer * 5
                        for si = 0, 2 do
                            local sa = stunAngle + si * 2.094  -- 120度间隔
                            local starX = sx + math.cos(sa) * (e.radius + 12)
                            local starY = sy - e.radius - 8 + math.sin(sa) * 6
                            nvgFontSize(vg, 16)
                            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                            nvgFillColor(vg, nvgRGBA(255, 255, 100, 220))
                            nvgText(vg, starX, starY, "⭐")
                        end
                        -- 整体变暗表示眩晕
                        nvgGlobalAlpha(vg, 0.6)
                    end
                end

                -- emoji 主体
                local fontSize = e.radius * 2.2 * deathScale
                nvgFontSize(vg, fontSize)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, sx, sy, e.emoji)

                -- 恢复透明度
                if e.dying or e.typeName == "ghost" or (e.isBoss and e.bossStunTimer > 0) then
                    nvgGlobalAlpha(vg, 1.0)
                end

                -- Boss 额外光环（dying 跳过）
                if e.isBoss and not e.dying then
                    -- 双层霓虹脉冲光环
                    local pulse1 = 0.5 + 0.5 * math.sin(e.behaviorTimer * 3)
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, e.radius + 8)
                    nvgStrokeColor(vg, nvgRGBA(col[1], col[2], col[3],
                        math.floor(80 + 80 * pulse1)))
                    nvgStrokeWidth(vg, 2.5)
                    nvgStroke(vg)

                    local pulse2 = 0.5 + 0.5 * math.sin(e.behaviorTimer * 5 + 1)
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, e.radius + 14)
                    nvgStrokeColor(vg, nvgRGBA(col[1], col[2], col[3],
                        math.floor(40 + 40 * pulse2)))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)
                end

                -- 精英怪视觉特效（dying 跳过）
                if e.eliteMod and not e.dying then
                    if e.eliteMod == "aura_heal" then
                        -- 绿色治疗光环脉冲
                        local healPulse = 0.5 + 0.5 * math.sin(e.behaviorTimer * 4)
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy, e.radius + 12 + healPulse * 4)
                        nvgStrokeColor(vg, nvgRGBA(50, 255, 100, math.floor(60 + 60 * healPulse)))
                        nvgStrokeWidth(vg, 2)
                        nvgStroke(vg)
                        -- 绿色十字标记
                        nvgFontSize(vg, 14)
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(50, 255, 100, math.floor(140 + 80 * healPulse)))
                        nvgText(vg, sx, sy - e.radius - 14, "💚")

                    elseif e.eliteMod == "aura_speed" then
                        -- 蓝色速度光环 + 旋转箭头
                        local spdPulse = 0.5 + 0.5 * math.sin(e.behaviorTimer * 5)
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy, e.radius + 10)
                        nvgStrokeColor(vg, nvgRGBA(80, 180, 255, math.floor(50 + 50 * spdPulse)))
                        nvgStrokeWidth(vg, 1.5)
                        nvgStroke(vg)
                        -- 旋转速度箭头
                        for ai = 0, 2 do
                            local aa = e.behaviorTimer * 4 + ai * 2.094
                            local ax = sx + math.cos(aa) * (e.radius + 12)
                            local ay = sy + math.sin(aa) * (e.radius + 12)
                            nvgFontSize(vg, 10)
                            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                            nvgFillColor(vg, nvgRGBA(80, 200, 255, 200))
                            nvgText(vg, ax, ay, "⚡")
                        end

                    elseif e.eliteMod == "shield" then
                        if e.shieldHp > 0 then
                            -- 护盾气泡（青色半透明圆）
                            local shieldAlpha = math.floor(100 + 40 * math.sin(e.behaviorTimer * 3))
                            nvgBeginPath(vg)
                            nvgCircle(vg, sx, sy, e.radius + 8)
                            nvgFillColor(vg, nvgRGBA(80, 220, 255, math.floor(shieldAlpha * 0.3)))
                            nvgFill(vg)
                            nvgBeginPath(vg)
                            nvgCircle(vg, sx, sy, e.radius + 8)
                            nvgStrokeColor(vg, nvgRGBA(100, 240, 255, shieldAlpha))
                            nvgStrokeWidth(vg, 2.5)
                            nvgStroke(vg)
                            -- 护盾血条（在普通血条上方）
                            local sBarW = e.radius * 2
                            local sBarH = 3
                            local sBarX = sx - sBarW / 2
                            local sBarY = sy - e.radius - 14
                            nvgBeginPath(vg)
                            nvgRoundedRect(vg, sBarX, sBarY, sBarW, sBarH, 1)
                            nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
                            nvgFill(vg)
                            local sRatio = e.shieldHp / e.shieldMaxHp
                            nvgBeginPath(vg)
                            nvgRoundedRect(vg, sBarX, sBarY, sBarW * sRatio, sBarH, 1)
                            nvgFillColor(vg, nvgRGBA(80, 220, 255, 220))
                            nvgFill(vg)
                            -- 🛡️ 标记
                            nvgFontSize(vg, 12)
                            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                            nvgFillColor(vg, nvgRGBA(100, 240, 255, 220))
                            nvgText(vg, sx, sy - e.radius - 20, "🛡️")
                        end

                    elseif e.eliteMod == "enrage" then
                        if e.enraged then
                            -- 狂暴激活：红色脉冲光环 + 愤怒标记
                            local ragePulse = 0.5 + 0.5 * math.sin(e.behaviorTimer * 8)
                            nvgBeginPath(vg)
                            nvgCircle(vg, sx, sy, e.radius + 6 + ragePulse * 4)
                            nvgFillColor(vg, nvgRGBA(255, 30, 0, math.floor(30 + 40 * ragePulse)))
                            nvgFill(vg)
                            nvgBeginPath(vg)
                            nvgCircle(vg, sx, sy, e.radius + 10)
                            nvgStrokeColor(vg, nvgRGBA(255, 50, 0, math.floor(120 + 100 * ragePulse)))
                            nvgStrokeWidth(vg, 2)
                            nvgStroke(vg)
                            nvgFontSize(vg, 14)
                            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                            nvgFillColor(vg, nvgRGBA(255, 80, 30, 240))
                            nvgText(vg, sx, sy - e.radius - 14, "🔥")
                        else
                            -- 狂暴未激活：淡红色警告标记
                            nvgFontSize(vg, 10)
                            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                            nvgFillColor(vg, nvgRGBA(255, 100, 50, 120))
                            nvgText(vg, sx, sy - e.radius - 12, "💢")
                        end
                    end
                end

                -- 血条（Boss 不在这里画，由 HUD 画大血条；dying 跳过）
                if not e.isBoss and not e.dying and e.hp < e.maxHp then
                    local barW = e.radius * 2
                    local barH = 3
                    local barX = sx - barW / 2
                    local barY = sy - e.radius - 8
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, barX, barY, barW, barH, 1)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
                    nvgFill(vg)
                    local ratio = e.hp / e.maxHp
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, barX, barY, barW * ratio, barH, 1)
                    nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 200))
                    nvgFill(vg)
                end
            end
        end
    end
end

return Enemy
