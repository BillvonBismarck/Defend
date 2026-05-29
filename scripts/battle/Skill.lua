--- ============================================================================
--- 技能系统 - 技能定义、随机选择、主动技能逻辑
--- ============================================================================

local Config = require("Config")
local DamageNumber = require("ui.DamageNumber")
local Particle = require("fx.Particle")
local Player = require("battle.Player")
local Projectile = require("battle.Projectile")
local Enemy = require("battle.Enemy")
local EnemyBullet = require("battle.EnemyBullet")
local SM = require("utils.SafeMath")
local SaveData = require("SaveData")
local RelicSystem = require("meta.RelicSystem")
local DailyChallenge = require("meta.DailyChallenge")
local DamageStats = require("ui.DamageStats")
local SpatialHash = require("utils.SpatialHash")

-- 帧预算：单帧最大碰撞检测次数，超出后跳过本帧剩余碰撞
local FRAME_COLLISION_BUDGET = 2000
local _frameCollisions = 0

-- 持久化空间哈希（避免每帧 New 产生 GC 压力）
local _persistentSkillHash = SpatialHash.New(200)
local _nearby = {}  -- 复用查询结果表

local Skill = {}

-- 符文标志（由 BattleScene 在每局开始时设置）
Skill.hasCrossClassRune = false  -- 异界天赋符文：未毕业前可看到其他角色非专属技能

-- 主动技能计时器
Skill.droneTimer = 0
Skill.grenadeTimer = 0
Skill.grabSmashTimer = 0
Skill.cloneTimer = 0
Skill.catScratchTimer = 0
Skill.catStarFlash = 0       -- 五角星触发闪光计时器
Skill.catStarVerts = nil     -- 上次触发的五角星顶点（供渲染）
Skill.catScratchPending = 0  -- 猫爪积攒待释放轮数
Skill.catScratchBurstTimer = 0  -- 猫爪连续释放间隔计时
Skill.beanSproutTimer = 0
Skill.thumbUpTimer = 0

-- 圣诞树副武器状态
Skill.xmasTreeTimer = 0         -- 接触伤害计时器
Skill.xmasTreeAngle = 0         -- 公转角度
Skill.xmasTreeIceTimer = 0      -- 冰弹发射计时器
Skill.xmasTreeHitMap = {}       -- per-enemy命中冷却 { [enemy] = remainingCD }

-- 落叶风暴状态
Skill.leafStormTimer = 0
Skill.leafStormFlash = 0        -- 风暴触发闪光
Skill.leafStormAngle = 0        -- 旋转角度

-- ======== OTTO 专属技能状态 ========
-- 大象踩背
Skill.elephantStompTimer = 0        -- 踩踏tick计时器（每秒踩一次）
local elephants = {}                -- { {x, y, life, targetEnemy} }

-- 我喜欢你你喜欢我（魅惑）
Skill.charmTimer = 0                -- 魅惑尝试计时（与射击联动，此处留给update轮询）
local charmedEnemies = {}           -- { enemy_ref, ... } 当前被魅惑的敌人列表
Skill.charmDamageTimer = 0          -- 魅惑敌人碰撞伤害tick计时

-- 慢行者（马匹子弹+旋风）
Skill.slowRiderTimer = 0
local horseProjectiles = {}         -- { {x, y, targetEnemy, dmg} }
local horseWhirlwinds = {}          -- { {x, y, life, dmg, tickTimer} }

-- 盒子
local ottoBoxes = {}                -- { {x, y, spawnAge, droneTimer, clones, ...} }
Skill.ottoBoxPlaceTimer = 0

-- 冲刺（已改为被动移速加成，保留变量避免外部引用报错）
Skill.isSprintActive = false
Skill.sprintShieldHits = 0

-- 星爆多段伤害队列
local catScratchHitQueue = {}   -- { {timer, dmg, verts, count} }

-- 无人机视觉状态
Skill.droneAngle = 0            -- 当前公转角度
Skill.droneOrbitRadius = 60     -- 公转半径
Skill.droneSpeed = 3.5          -- 公转角速度 (rad/s)
Skill.droneVisualSize = 8       -- 无人机显示半径

-- 绿色无人机视觉状态
Skill.greenDroneAngle = 0
Skill.greenDroneOrbitRadius = 90  -- 比蓝色大（蓝色60）
Skill.greenDroneSpeed = 2.5       -- 公转角速度
Skill.greenDroneTimer = 0

-- 分身状态
local clones = {}   -- { {x, y, attackTimer, mimicTimer} }
local CLONE_FOLLOW_SPEED = 220
local CLONE_ORBIT_DIST = 50      -- 分身到玩家的理想距离
local CLONE_ATTACK_RANGE = 350
local cloneSharedAngle = 0       -- 共享公转角度（像无人机一样均匀分布）

-- 星爆猫爪视觉角度
local catScratchAngle = 0

-- 豆芽陷阱状态
local beanTraps = {}  -- { {x, y, life, radius, dmg} }
local BEAN_TRAP_LIFE = 8.0       -- 陷阱持续8秒
local BEAN_TRAP_TRIGGER_R = 30   -- 触发半径

-- 点赞弹幕角度
local thumbUpAngle = 0
Skill.thumbUpPending = 0       -- 点赞积攒待释放轮数
Skill.thumbUpBurstTimer = 0    -- 点赞连续释放间隔计时

-- 飞行手雷状态
local flyingGrenades = {}   -- { {x, y, tx, ty, dmg, radius, speed, rotation} }
local GRENADE_SPEED = 380   -- 飞行速度 (px/s)

-- 太极拳状态
Skill.taichiChargesUsed = 0       -- 本周期已触发次数
Skill.taichiCooldownTimer = 0     -- 冷却周期计时器
-- 太极拳掌风波子弹列表
local taichiWaves = {}   -- { {x, y, vx, vy, dmg, lifetime, scale, spawnTime} }

-- 无人机拖尾（环形缓冲区）
local TRAIL_MAX = 8
local droneTrails = {}          -- [droneIndex] = { {x,y}, {x,y}, ... }
local trailHead = 0             -- 写入游标
local trailTimer = 0            -- 拖尾采样计时器
local TRAIL_INTERVAL = 0.05     -- 每 50ms 采样一次（更稀疏）

-- 绿色无人机拖尾
local greenDroneTrails = {}
local greenTrailHead = 0
local greenTrailTimer = 0
-- 绿色无人机碰撞计时器
local greenDroneCollisionTimer = 0

--- 重置技能计时器
function Skill.Reset()
    Skill.droneTimer = 0
    Skill.grenadeTimer = 0
    Skill.grabSmashTimer = 0
    Skill.cloneTimer = 0
    Skill.catScratchTimer = 0
    Skill.catStarFlash = 0
    Skill.catStarVerts = nil
    Skill.catScratchPending = 0
    Skill.catScratchBurstTimer = 0
    Skill.beanSproutTimer = 0
    Skill.thumbUpTimer = 0
    Skill.thumbUpPending = 0
    Skill.thumbUpBurstTimer = 0
    Skill.droneAngle = 0
    Skill.xmasTreeTimer = 0
    Skill.xmasTreeAngle = 0
    Skill.xmasTreeIceTimer = 0
    Skill.xmasTreeHitMap = {}
    Skill.leafStormTimer = 0
    Skill.leafStormFlash = 0
    Skill.leafStormAngle = 0
    droneTrails = {}
    trailHead = 0
    trailTimer = 0
    clones = {}
    cloneSharedAngle = 0
    catScratchAngle = 0
    catScratchHitQueue = {}
    beanTraps = {}
    thumbUpAngle = 0
    flyingGrenades = {}
    Skill.taichiChargesUsed = 0
    Skill.taichiCooldownTimer = 0
    taichiWaves = {}
    -- OTTO 专属技能重置
    Skill.elephantStompTimer = 0
    elephants = {}
    Skill.charmTimer = 0
    charmedEnemies = {}
    Skill.charmDamageTimer = 0
    Skill.slowRiderTimer = 0
    horseProjectiles = {}
    horseWhirlwinds = {}
    ottoBoxes = {}
    Skill.ottoBoxPlaceTimer = 0
    Skill.isSprintActive = false
    Skill.sprintShieldHits = 0
    -- 绿色无人机
    Skill.greenDroneAngle = 0
    Skill.greenDroneTimer = 0
    greenDroneTrails = {}
    greenTrailHead = 0
    greenTrailTimer = 0
    greenDroneCollisionTimer = 0
end

--- 构建角色可用技能 ID 集合（专属 + 共享 + 毕业解锁）
---@param charId string 角色ID
---@return table<string, boolean> 允许的技能ID集合
local function BuildAllowedSkills(charId)
    local charDef = Config.GetCharacter(charId)
    local allowed = {}
    -- 角色专属技能
    for _, sid in ipairs(charDef.exclusiveSkills) do
        allowed[sid] = true
    end
    -- 共享技能
    for _, sid in ipairs(Config.SHARED_SKILLS) do
        allowed[sid] = true
    end
    -- 毕业后解锁跨角色技能
    if Player.graduationPhase >= 1 then
        local gradSkills = Player.GetGraduationSkillIds()
        for _, sid in ipairs(gradSkills) do
            allowed[sid] = true
        end
    end
    -- 飞行遗物1级以上解锁绿色无人机
    local flightLv = (SaveData.relicLevels or {})["flight"] or 0
    if flightLv >= 1 then
        allowed["atk_drone_green"] = true
    end
    -- 异界天赋符文：可获得其他角色的全部专属技能（含真专属）
    -- 毕业前：全部解锁可选；毕业后：保留已获得的（享受毕业maxLevel提升）
    if Skill.hasCrossClassRune then
        for _, ch in ipairs(Config.CHARACTERS) do
            if ch.id ~= charId then
                for _, sid in ipairs(ch.exclusiveSkills or {}) do
                    if Player.graduationPhase < 1 then
                        -- 未毕业：全部可选
                        allowed[sid] = true
                    elseif (Player.skills[sid] or 0) > 0 then
                        -- 已毕业：保留已获得的技能（可继续升级）
                        allowed[sid] = true
                    end
                end
            end
        end
    end
    return allowed
end

--- 随机选择3个可升级技能（按角色过滤）
---@param playerSkills table 玩家已有技能 { id = level }
---@param charId string|nil 角色ID（传入以过滤可选池）
---@return table 3个技能选项 { {skillDef, newLevel}, ... }
function Skill.RandomChoices(playerSkills, charId)
    local allowed = charId and BuildAllowedSkills(charId) or nil

    -- 收集已持有技能的互斥列表
    local excluded = {}
    for sid, slv in pairs(playerSkills) do
        if slv > 0 then
            local def = Config.FindSkill(sid)
            if def and def.excludes then
                for _, exId in ipairs(def.excludes) do
                    excluded[exId] = true
                end
            end
        end
    end

    -- 收集可升级的技能
    local candidates = {}
    -- 每日挑战 single_skill（专精之路）：只允许首次选中的技能
    local singleSkillActive = DailyChallenge.HasFactor("single_skill")
    for _, skillDef in ipairs(Config.SKILLS) do
        -- 如果有角色限制，检查是否在允许列表中
        if not allowed or allowed[skillDef.id] then
            -- 专精之路：已确定技能后，只允许该技能
            if singleSkillActive and DailyChallenge.singleSkillId and skillDef.id ~= DailyChallenge.singleSkillId then
                goto skipSkill
            end
            -- 互斥检查：已持有的技能排斥此技能
            if not excluded[skillDef.id] then
                local currentLevel = playerSkills[skillDef.id] or 0
                local maxLv = Player.GetEffectiveMaxLevel(skillDef)
                if currentLevel < maxLv then
                    table.insert(candidates, {
                        def = skillDef,
                        newLevel = currentLevel + 1,
                        isNew = currentLevel == 0,
                    })
                end
            end
            ::skipSkill::
        end
    end

    -- 如果候选不足3个，全部返回
    if #candidates <= 3 then
        return candidates
    end

    -- 随机选3个（Fisher-Yates shuffle取前3）
    for i = #candidates, 2, -1 do
        local j = math.random(1, i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    return { candidates[1], candidates[2], candidates[3] }
end

--- 更新主动技能效果
---@param dt number
---@param playerSkills table
---@param playerX number
---@param playerY number
---@param playerAtk number 玩家有效攻击力
---@param enemies table Enemy.active
---@return table 被击杀的敌人列表
function Skill.Update(dt, playerSkills, playerX, playerY, playerAtk, enemies)
    local killed = {}

    -- 构建空间哈希（Otto Box、Charmed、Drone 等共用，避免重复 O(n) 全量遍历）
    local skillHash = _persistentSkillHash
    skillHash:Clear()
    skillHash:InsertAll(enemies)
    _frameCollisions = 0  -- 重置帧预算

    -- 攻击无人机
    local droneLevel = playerSkills["atk_drone"] or 0
    if droneLevel > 0 then
        local interval = 1.0 / droneLevel -- 等级越高频率越高
        Skill.droneTimer = Skill.droneTimer + dt
        if Skill.droneTimer >= interval then
            Skill.droneTimer = 0
            -- 找最近敌人造成伤害
            local dmg = SM.mulFloor(playerAtk, 0.5 * droneLevel)
            local nearest = nil
            local nearDist = 400 * 400
            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
            skillHash:QueryInto(playerX, playerY, 400, _nearby)
            for ni = 1, #_nearby do
                local e = _nearby[ni]
                if e.alive and not e.charmed then
                    local dx = e.x - playerX
                    local dy = e.y - playerY
                    local d2 = dx * dx + dy * dy
                    if d2 < nearDist then
                        nearDist = d2
                        nearest = e
                    end
                end
            end
            if nearest then
                DamageStats._currentSource = "atk_drone"
                local killed2, finalAmount, isFrozenHit = Enemy.Damage(nearest, dmg)
                DamageNumber.SpawnDamage(nearest.x, nearest.y - 10, finalAmount, false, isFrozenHit)
                -- 无人机激光线 FX：从最近无人机到目标
                local da = Skill.droneAngle
                local drX = playerX + math.cos(da) * Skill.droneOrbitRadius
                local drY = playerY + math.sin(da) * Skill.droneOrbitRadius
                Particle.SpawnLaser(drX, drY, nearest.x, nearest.y, 0.15, 0, 220, 255, 2)
                Particle.Spawn(nearest.x, nearest.y, "hit")
                if killed2 then
                    table.insert(killed, nearest)
                end
            end
        end
    end

    -- 手雷（投掷到敌人方向，碰到敌人立即爆炸+击退，升级连投多个）
    local grenadeLevel = playerSkills["grenade"] or 0
    if grenadeLevel > 0 then
        local interval = 5.0
        Skill.grenadeTimer = Skill.grenadeTimer + dt
        if Skill.grenadeTimer >= interval then
            Skill.grenadeTimer = 0
            local dmg = SM.mulFloor(playerAtk, 2.0)
            local radius = 80 + 20 * grenadeLevel
            local grenadeCount = grenadeLevel  -- 等级 = 同时投掷数量
            -- 用空间哈希找最近的 grenadeCount 个目标（避免全量遍历+排序+临时表GC）
            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
            skillHash:QueryInto(playerX, playerY, 500, _nearby)
            -- 简单选择排序取前 grenadeCount 个最近的（_nearby通常很小）
            local nCount = #_nearby
            local sortCount = math.min(grenadeCount, nCount)
            for si = 1, sortCount do
                local bestIdx = si
                local bestD2 = math.huge
                for sj = si, nCount do
                    local e = _nearby[sj]
                    if e.alive then
                        local dx2 = e.x - playerX
                        local dy2 = e.y - playerY
                        local d2 = dx2 * dx2 + dy2 * dy2
                        if d2 < bestD2 then
                            bestD2 = d2
                            bestIdx = sj
                        end
                    end
                end
                _nearby[si], _nearby[bestIdx] = _nearby[bestIdx], _nearby[si]
            end
            for gi = 1, grenadeCount do
                local t = _nearby[gi] or _nearby[1]
                if t and t.alive then
                    table.insert(flyingGrenades, {
                        x = playerX, y = playerY,
                        tx = t.x, ty = t.y,
                        dmg = dmg, radius = radius,
                        speed = GRENADE_SPEED,
                        rotation = 0,
                        hitRadius = 18,  -- 碰撞检测半径
                    })
                end
            end
        end
    end

    -- 更新飞行中的手雷（碰到敌人立即爆炸）
    for i = #flyingGrenades, 1, -1 do
        local g = flyingGrenades[i]
        local dx = g.tx - g.x
        local dy = g.ty - g.y
        local dist = math.sqrt(dx * dx + dy * dy)
        g.rotation = g.rotation + dt * 12  -- 旋转动画

        -- 检测飞行途中碰到敌人（空间哈希加速）
        local exploded = false
        local explodeX, explodeY = g.x, g.y
        local gHitR = g.hitRadius or 18
        for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
        skillHash:QueryInto(g.x, g.y, gHitR + 20, _nearby)
        for ni = 1, #_nearby do
            local e = _nearby[ni]
            if e.alive and not e.charmed then
                local ex = e.x - g.x
                local ey = e.y - g.y
                local eR = e.radius or 15
                local hitDist = gHitR + eR
                if ex * ex + ey * ey <= hitDist * hitDist then
                    exploded = true
                    explodeX, explodeY = g.x, g.y
                    break
                end
            end
        end

        -- 到达目标位置也爆炸
        if not exploded and dist < 8 then
            exploded = true
            explodeX, explodeY = g.tx, g.ty
        end

        if exploded then
            -- 爆炸：对范围内敌人造成伤害 + 击退（空间哈希加速）
            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
            skillHash:QueryInto(explodeX, explodeY, g.radius, _nearby)
            for ni = 1, #_nearby do
                local e = _nearby[ni]
                if e.alive and not e.charmed then
                    local edx = e.x - explodeX
                    local edy = e.y - explodeY
                    if edx * edx + edy * edy <= g.radius * g.radius then
                        DamageStats._currentSource = "grenade"
                        local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, g.dmg)
                        DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                        -- 击退：方向 = 敌人远离玩家（即敌人移动方向的反方向）
                        local kbdx = e.x - playerX
                        local kbdy = e.y - playerY
                        local kbDist = math.sqrt(kbdx * kbdx + kbdy * kbdy)
                        if kbDist > 1 then
                            Enemy.ApplyKnockback(e, kbdx / kbDist * 300, kbdy / kbDist * 300)
                        end
                        if killed2 then
                            table.insert(killed, e)
                        end
                    end
                end
            end
            -- 手雷爆炸 FX
            local GameAudio = require("fx.GameAudio")
            GameAudio.PlaySFX("explosion")
            Particle.SpawnShockWave(explodeX, explodeY, g.radius, 0.4, 255, 120, 30, 3)
            Particle.Spawn(explodeX, explodeY, "bomb")
            table.remove(flyingGrenades, i)
        else
            -- 飞行中
            g.x = g.x + (dx / dist) * g.speed * dt
            g.y = g.y + (dy / dist) * g.speed * dt
        end
    end

    -- ======== 太极拳（手专属）—— 消除来袭敌弹并释放掌风波 ========
    local grabSmashLevel = playerSkills["grab_smash"] or 0
    if grabSmashLevel > 0 then
        local skillDef = Config.FindSkill("grab_smash")
        local eff = skillDef.effect
        local maxCharges = grabSmashLevel  -- 等级 = 每10秒最大触发次数
        local detectR = eff.detectRadius
        local detectR2 = detectR * detectR

        -- 冷却周期计时器
        Skill.taichiCooldownTimer = Skill.taichiCooldownTimer + dt
        if Skill.taichiCooldownTimer >= eff.baseCooldown then
            Skill.taichiCooldownTimer = Skill.taichiCooldownTimer - eff.baseCooldown
            Skill.taichiChargesUsed = 0  -- 重置触发次数
        end

        -- 检测即将击中玩家的敌方子弹（在检测半径内）
        if Skill.taichiChargesUsed < maxCharges then
            for _, b in ipairs(EnemyBullet.active) do
                if b.alive then
                    local bdx = b.x - playerX
                    local bdy = b.y - playerY
                    if bdx * bdx + bdy * bdy <= detectR2 then
                        -- 消除敌弹
                        b.alive = false
                        Skill.taichiChargesUsed = Skill.taichiChargesUsed + 1

                        -- 释放掌风波：方向 = 敌弹飞行方向
                        local bspd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                        local wvx, wvy
                        if bspd > 1 then
                            wvx = (b.vx / bspd) * eff.waveSpeed
                            wvy = (b.vy / bspd) * eff.waveSpeed
                        else
                            wvx = eff.waveSpeed
                            wvy = 0
                        end
                        local waveDmg = SM.mulFloor(playerAtk, eff.dmgMultiplier)
                        table.insert(taichiWaves, {
                            x = playerX, y = playerY,
                            vx = wvx, vy = wvy,
                            dmg = waveDmg,
                            lifetime = 1.5,
                            scale = 1.0,
                            spawnTime = time.elapsedTime,
                            hitEnemies = {},
                        })
                        -- FX: 消除特效 + 音效
                        Particle.SpawnShockWave(playerX, playerY, 40, 0.2, 220, 200, 255, 2)
                        Particle.Spawn(b.x, b.y, "hit")
                        Skill.grabSmashTimer = 0  -- 重置供 CD 显示

                        if Skill.taichiChargesUsed >= maxCharges then break end
                    end
                end
            end
        end
    end

    -- 更新太极拳掌风波
    for i = #taichiWaves, 1, -1 do
        local w = taichiWaves[i]
        w.x = w.x + w.vx * dt
        w.y = w.y + w.vy * dt
        w.lifetime = w.lifetime - dt
        -- 快速膨胀
        local eff = Config.FindSkill("grab_smash").effect
        w.scale = math.min(eff.waveMaxScale, w.scale + eff.waveGrowRate * dt)

        if w.lifetime <= 0 then
            table.remove(taichiWaves, i)
        else
            -- 碰撞检测（穿透所有敌人 + 必暴击 + 击退，空间哈希加速）
            local waveR = 14 * w.scale  -- 基础碰撞半径 × 膨胀
            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
            skillHash:QueryInto(w.x, w.y, waveR + 20, _nearby)
            for ni = 1, #_nearby do
                local e = _nearby[ni]
                if e.alive and not e.charmed and not w.hitEnemies[e] then
                    local edx = e.x - w.x
                    local edy = e.y - w.y
                    local eR = e.radius or 15
                    local hitDist = waveR + eR
                    if edx * edx + edy * edy <= hitDist * hitDist then
                        w.hitEnemies[e] = true
                        -- 必定暴击伤害
                        local critDmg = SM.mulFloor(w.dmg, Config.PLAYER.critDamage)
                        DamageStats._currentSource = "grab_smash"
                        local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, critDmg)
                        DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, true, isFrozenHit)
                        Particle.Spawn(e.x, e.y, "crit_hit")
                        -- 必定击退
                        Enemy.ApplyKnockback(e, w.vx, w.vy)
                        if killed2 then
                            table.insert(killed, e)
                        end
                    end
                end
            end
        end
    end

    -- ======== 星爆猫爪（猫咪专属）—— 多段伤害 ========
    local catScratchLevel = playerSkills["cat_scratch"] or 0
    if catScratchLevel > 0 then
        local interval = 3.0 / catScratchLevel
        Skill.catScratchTimer = Skill.catScratchTimer + dt
        catScratchAngle = catScratchAngle + 1.5 * dt  -- 缓慢旋转

        -- CD 到了就积攒轮数（最多积攒 3*level 轮）
        if Skill.catScratchTimer >= interval then
            Skill.catScratchTimer = 0
            local maxPending = 3 * catScratchLevel
            Skill.catScratchPending = math.min(Skill.catScratchPending + catScratchLevel, maxPending)
        end

        -- 连续释放：每0.3s释放一轮（需有积攒且有敌人）
        local hasEnemy = false
        for _, e in ipairs(enemies) do
            if e.alive then hasEnemy = true; break end
        end
        if Skill.catScratchPending > 0 and hasEnemy then
            Skill.catScratchBurstTimer = Skill.catScratchBurstTimer + dt
            if Skill.catScratchBurstTimer >= 0.3 or Skill.catScratchBurstTimer == dt then
                -- 首次立即释放（burstTimer == dt 表示刚积攒）或每0.3s释放
                if Skill.catScratchBurstTimer >= 0.3 then
                    Skill.catScratchBurstTimer = Skill.catScratchBurstTimer - 0.3
                end
                Skill.catScratchPending = Skill.catScratchPending - 1

                local dmg = SM.mulFloor(playerAtk, 2.4)
                local baseR = Config.FindSkill("cat_scratch").effect.radius + 20 * catScratchLevel
                local outerR = baseR * 2  -- 范围200%
                local innerR = outerR * 0.382  -- 五角星内径（黄金比例）
                -- 构建五角星 10 个顶点
                local starVerts = {}
                for i = 1, 10 do
                    local a = catScratchAngle + (i - 1) * (math.pi / 5) - math.pi / 2
                    local r = (i % 2 == 1) and outerR or innerR
                    starVerts[i] = { x = playerX + math.cos(a) * r, y = playerY + math.sin(a) * r }
                end

                -- 对五角星内敌人造成伤害（空间哈希预筛选 outerR 范围）
                for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                skillHash:QueryInto(playerX, playerY, outerR, _nearby)
                for ni = 1, #_nearby do
                    local e = _nearby[ni]
                    if e.alive and not e.charmed then
                        local inside = false
                        local n = #starVerts
                        local j = n
                        for vi = 1, n do
                            local vi_y = starVerts[vi].y
                            local vj_y = starVerts[j].y
                            if (vi_y > e.y) ~= (vj_y > e.y) then
                                local vi_x = starVerts[vi].x
                                local vj_x = starVerts[j].x
                                local intersectX = vj_x + (e.y - vj_y) / (vi_y - vj_y) * (vi_x - vj_x)
                                if e.x < intersectX then
                                    inside = not inside
                                end
                            end
                            j = vi
                        end
                        if inside then
                            DamageStats._currentSource = "cat_scratch"
                            local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, dmg)
                            DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                            Particle.Spawn(e.x, e.y, "hit")
                            if killed2 then
                                table.insert(killed, e)
                            end
                        end
                    end
                end

                -- 概率爆出红心（20%每次触发）
                if math.random() < 0.20 then
                    local Loot = require("battle.Loot")
                    local heartAngle = math.random() * math.pi * 2
                    local heartDist = outerR * 0.5
                    Loot.SpawnSpecial(playerX + math.cos(heartAngle) * heartDist,
                                      playerY + math.sin(heartAngle) * heartDist, "heart")
                end
                -- 叠加10%攻速加成5秒（可多次叠加）
                Player.AddTempAtkSpeed(0.05, 5.0)

                -- 保存顶点供渲染闪烁用
                Skill.catStarFlash = 0.35
                Skill.catStarVerts = starVerts
                -- 冲击波 FX
                Particle.SpawnShockWave(playerX, playerY, outerR, 0.4, 255, 220, 50, 3)
            end
        else
            -- 没有释放时重置burst计时器
            if Skill.catScratchPending == 0 then
                Skill.catScratchBurstTimer = 0
            end
        end

        -- 闪光衰减
        if Skill.catStarFlash > 0 then
            Skill.catStarFlash = Skill.catStarFlash - dt
        end
    end

    -- ======== 豆芽陷阱（黄豆专属）========
    local beanSproutLevel = playerSkills["bean_sprout"] or 0
    if beanSproutLevel > 0 then
        local interval = 4.0 / beanSproutLevel
        local maxTraps = 3 + beanSproutLevel
        Skill.beanSproutTimer = Skill.beanSproutTimer + dt
        if Skill.beanSproutTimer >= interval and #beanTraps < maxTraps then
            Skill.beanSproutTimer = 0
            -- 在玩家身后随机位置种下陷阱
            local trapAngle = math.random() * math.pi * 2
            local trapDist = 40 + math.random() * 60
            table.insert(beanTraps, {
                x = playerX + math.cos(trapAngle) * trapDist,
                y = playerY + math.sin(trapAngle) * trapDist,
                life = BEAN_TRAP_LIFE,
                radius = (60 + 10 * beanSproutLevel) * 2,  -- 伤害范围翻倍
                dmg = SM.mulFloor(playerAtk, 1.5 * beanSproutLevel),
                triggered = false,
            })
        end
        -- 更新陷阱：寿命 + 触发检测（空间哈希加速）
        for i = #beanTraps, 1, -1 do
            local trap = beanTraps[i]
            trap.life = trap.life - dt
            if trap.life <= 0 then
                table.remove(beanTraps, i)
            elseif not trap.triggered then
                -- 用空间哈希检查触发范围内是否有敌人
                for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                skillHash:QueryInto(trap.x, trap.y, BEAN_TRAP_TRIGGER_R, _nearby)
                local triggered = false
                for ni = 1, #_nearby do
                    local e = _nearby[ni]
                    if e.alive and not e.charmed then
                        triggered = true
                        break
                    end
                end
                if triggered then
                    trap.triggered = true
                    trap.life = 0.3
                    -- 对爆炸范围内敌人造成伤害（空间哈希查询）
                    for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                    skillHash:QueryInto(trap.x, trap.y, trap.radius, _nearby)
                    for ni = 1, #_nearby do
                        local e2 = _nearby[ni]
                        if e2.alive and not e2.charmed then
                            DamageStats._currentSource = "bean_sprout"
                            local killed2, finalAmount, isFrozenHit = Enemy.Damage(e2, trap.dmg)
                            DamageNumber.SpawnDamage(e2.x, e2.y - 10, finalAmount, false, isFrozenHit)
                            if killed2 then
                                table.insert(killed, e2)
                            end
                        end
                    end
                    Particle.SpawnShockWave(trap.x, trap.y, trap.radius, 0.3, 100, 220, 50, 3)
                    Particle.Spawn(trap.x, trap.y, "bomb")
                end
            end
        end
    end

    -- ======== 点赞弹幕（手专属）- 连续释放level轮，受子弹加成 ========
    local thumbUpLevel = playerSkills["thumb_up"] or 0
    if thumbUpLevel > 0 then
        local interval = 3.5 / thumbUpLevel
        Skill.thumbUpTimer = Skill.thumbUpTimer + dt
        thumbUpAngle = thumbUpAngle + 0.5 * dt

        -- CD 到了积攒 level 轮（上限防无限增长导致性能问题）
        if Skill.thumbUpTimer >= interval then
            Skill.thumbUpTimer = 0
            local maxPending = thumbUpLevel * 3
            Skill.thumbUpPending = math.min(Skill.thumbUpPending + thumbUpLevel, maxPending)
        end

        -- 连续释放：每0.3s释放一轮
        if Skill.thumbUpPending > 0 then
            Skill.thumbUpBurstTimer = Skill.thumbUpBurstTimer + dt
            if Skill.thumbUpBurstTimer >= 0.3 or Skill.thumbUpBurstTimer == dt then
                if Skill.thumbUpBurstTimer >= 0.3 then
                    Skill.thumbUpBurstTimer = Skill.thumbUpBurstTimer - 0.3
                end
                Skill.thumbUpPending = Skill.thumbUpPending - 1

                -- 子弹数 = 4 + 2*level + 散射加成（猫multi_shot/猴combo_hit的extraBullets）
                local baseBulletCount = 4 + 2 * thumbUpLevel
                local extraFromScatter = Player.extraBullets  -- 来自 multi_shot / combo_hit
                local bulletCount = baseBulletCount + extraFromScatter

                local dmg = SM.mulFloor(playerAtk, 0.6)
                -- 继承所有子弹类加成（穿透、弹射）
                local pierce = Player.pierceCount
                local bounce = Player.bounceCount
                local bulletType = "spread"
                if pierce > 0 then bulletType = "pierce"
                elseif bounce > 0 then bulletType = "ricochet"
                end

                -- 找最近敌人用于瞄准
                local nearestE = nil
                local nearestDist2 = math.huge
                for _, e in ipairs(enemies) do
                    if e.alive and not e.charmed then
                        local edx = e.x - playerX
                        local edy = e.y - playerY
                        local d2 = edx * edx + edy * edy
                        if d2 < nearestDist2 then
                            nearestDist2 = d2
                            nearestE = e
                        end
                    end
                end

                -- 计算瞄准角度（第一颗子弹对准最近敌人）
                local aimAngle = thumbUpAngle
                if nearestE then
                    aimAngle = math.atan(nearestE.y - playerY, nearestE.x - playerX)
                end

                -- 发射环形弹幕，其中第一颗对准最近敌人
                for i = 1, bulletCount do
                    local angle = aimAngle + ((i - 1) / bulletCount) * math.pi * 2
                    local tx = playerX + math.cos(angle) * 200
                    local ty = playerY + math.sin(angle) * 200
                    Projectile.Spawn(playerX, playerY, tx, ty, dmg, pierce, bulletType, bounce)
                end
                Particle.SpawnShockWave(playerX, playerY, 60, 0.2, 220, 80, 220, 2)
            end
        else
            Skill.thumbUpBurstTimer = 0
        end
    end

    -- ======== 分身打击（大圣专属）- 发射实际射弹 ========
    local cloneLevel = playerSkills["clone_strike"] or 0
    if cloneLevel > 0 then
        local cloneCount = math.min(cloneLevel, 3)
        -- 确保分身数量正确
        while #clones < cloneCount do
            table.insert(clones, {
                x = playerX,
                y = playerY,
                attackTimer = 0,
                mimicTimer = 0,    -- 模仿技能计时
            })
        end
        while #clones > cloneCount do
            table.remove(clones)
        end

        -- 共享角度递增（像无人机一样）
        cloneSharedAngle = cloneSharedAngle + 1.8 * dt

        -- 分身属性：20%伤害 + 继承所有射弹加成
        -- 猴子专属：分身获得散射技能时不增加子弹，而是提升伤害倍率（+10%/散射等级）
        local cloneDmgRatio = 0.2
        local totalPierceCount = 0
        local totalExtraBullets = 0
        for sid, slv in pairs(playerSkills) do
            local def = Config.FindSkill(sid)
            if def and def.effect then
                if def.effect.pierceCount then
                    totalPierceCount = totalPierceCount + def.effect.pierceCount * slv
                end
                if def.effect.extraBullets then
                    if Player.charId == "monkey" then
                        -- 猴子分身：散射技能转为伤害加成（每级+10%）
                        cloneDmgRatio = cloneDmgRatio + 0.10 * slv
                    else
                        totalExtraBullets = totalExtraBullets + def.effect.extraBullets * slv
                    end
                end
            end
        end
        local cloneDmg = SM.mulFloor(playerAtk, cloneDmgRatio)

        local cloneInterval = Config.FindSkill("clone_strike").effect.interval / cloneLevel
        local mimicInterval = 5.0 / cloneLevel  -- 模仿技能间隔

        local cloneAngleStep = (math.pi * 2) / cloneCount
        for i, c in ipairs(clones) do
            -- 均匀环绕目标点（像无人机一样）
            local orbitAngle = cloneSharedAngle + (i - 1) * cloneAngleStep
            local targetX = playerX + math.cos(orbitAngle) * CLONE_ORBIT_DIST
            local targetY = playerY + math.sin(orbitAngle) * CLONE_ORBIT_DIST

            -- 平滑跟随
            local cdx = targetX - c.x
            local cdy = targetY - c.y
            local cdist = math.sqrt(cdx * cdx + cdy * cdy)
            if cdist > 2 then
                local spd = math.min(CLONE_FOLLOW_SPEED * dt, cdist)
                c.x = c.x + (cdx / cdist) * spd
                c.y = c.y + (cdy / cdist) * spd
            end

            -- 自动发射射弹（继承所有加成）
            c.attackTimer = c.attackTimer + dt
            if c.attackTimer >= cloneInterval then
                c.attackTimer = 0
                local nearest = nil
                local nearDist = CLONE_ATTACK_RANGE * CLONE_ATTACK_RANGE
                for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                skillHash:QueryInto(c.x, c.y, CLONE_ATTACK_RANGE, _nearby)
                for ni = 1, #_nearby do
                    local e = _nearby[ni]
                    if e.alive and not e.charmed then
                        local edx = e.x - c.x
                        local edy = e.y - c.y
                        local ed2 = edx * edx + edy * edy
                        if ed2 < nearDist then
                            nearDist = ed2
                            nearest = e
                        end
                    end
                end
                if nearest then
                    -- 发射实际子弹（继承玩家的 extraBullets、pierceCount 和 bounceCount）
                    local totalBounceCount = Player.bounceCount
                    if totalExtraBullets > 0 then
                        Projectile.SpawnSpread(c.x, c.y, nearest.x, nearest.y,
                            cloneDmg, totalPierceCount, totalExtraBullets, totalBounceCount)
                    else
                        Projectile.Spawn(c.x, c.y, nearest.x, nearest.y,
                            cloneDmg, totalPierceCount, nil, totalBounceCount)
                    end
                    Particle.Spawn(c.x, c.y, "hit")
                end
            end

            -- 模仿玩家的其他主动技能
            c.mimicTimer = c.mimicTimer + dt
            if c.mimicTimer >= mimicInterval then
                c.mimicTimer = 0
                local mimicDmg = SM.mulFloor(playerAtk, 0.2)

                -- 模仿手雷（空间哈希加速）
                local grenadeLv = playerSkills["grenade"] or 0
                if grenadeLv > 0 then
                    local gRadius = 60 + 10 * grenadeLv
                    for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                    skillHash:QueryInto(c.x, c.y, gRadius, _nearby)
                    for ni = 1, #_nearby do
                        local e = _nearby[ni]
                        if e.alive and not e.charmed then
                            DamageStats._currentSource = "clone_strike"
                            local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, mimicDmg)
                            DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                            if killed2 then
                                table.insert(killed, e)
                            end
                        end
                    end
                    Particle.SpawnShockWave(c.x, c.y, gRadius, 0.3, 255, 140, 50, 2)
                end

                -- 太极拳是被动反击技能，分身不模仿

                -- 模仿无人机（空间哈希加速）
                local dLv = playerSkills["atk_drone"] or 0
                if dLv > 0 then
                    local dNearest = nil
                    local dNearDist = 300 * 300
                    for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                    skillHash:QueryInto(c.x, c.y, 300, _nearby)
                    for ni = 1, #_nearby do
                        local e = _nearby[ni]
                        if e.alive and not e.charmed then
                            local ddx = e.x - c.x
                            local ddy = e.y - c.y
                            local dd2 = ddx * ddx + ddy * ddy
                            if dd2 < dNearDist then
                                dNearDist = dd2
                                dNearest = e
                            end
                        end
                    end
                    if dNearest then
                        DamageStats._currentSource = "clone_strike"
                        local killed2, finalAmount, isFrozenHit = Enemy.Damage(dNearest, mimicDmg)
                        DamageNumber.SpawnDamage(dNearest.x, dNearest.y - 10, finalAmount, false, isFrozenHit)
                        Particle.SpawnLaser(c.x, c.y, dNearest.x, dNearest.y, 0.12, 255, 140, 50, 1.5)
                        Particle.Spawn(dNearest.x, dNearest.y, "hit")
                        if killed2 then
                            table.insert(killed, dNearest)
                        end
                    end
                end
            end
        end
    else
        clones = {}
    end

    -- ======== 圣诞树环绕副武器（叶子专属）- 等级=数量 ========
    local xmasTreeLevel = playerSkills["xmas_tree"] or 0
    if xmasTreeLevel > 0 then
        local skillDef = Config.FindSkill("xmas_tree")
        local eff = skillDef.effect
        local treeCount = xmasTreeLevel  -- 等级 = 圣诞树数量
        local orbitR = eff.orbitRadius + 10 * xmasTreeLevel
        local contactInterval = eff.interval
        local contactDmg = SM.mulFloor(playerAtk, eff.baseDmg * xmasTreeLevel)
        local iceInterval = eff.iceBulletInterval / xmasTreeLevel

        -- 公转角度更新
        Skill.xmasTreeAngle = Skill.xmasTreeAngle + 2.5 * dt

        -- 更新 per-enemy 命中冷却
        for e, cd in pairs(Skill.xmasTreeHitMap) do
            if not e.alive then
                Skill.xmasTreeHitMap[e] = nil
            else
                cd = cd - dt
                if cd <= 0 then
                    Skill.xmasTreeHitMap[e] = nil
                else
                    Skill.xmasTreeHitMap[e] = cd
                end
            end
        end

        local angleStep = (math.pi * 2) / treeCount
        local hitR = 28 + 4 * xmasTreeLevel

        for ti = 1, treeCount do
            if _frameCollisions >= FRAME_COLLISION_BUDGET then break end
            local treeAngle = Skill.xmasTreeAngle + (ti - 1) * angleStep
            local treeX = playerX + math.cos(treeAngle) * orbitR
            local treeY = playerY + math.sin(treeAngle) * orbitR

            -- 接触伤害（per-enemy 命中冷却，空间哈希加速）
            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
            skillHash:QueryInto(treeX, treeY, hitR + 20, _nearby)
            for ni = 1, #_nearby do
                _frameCollisions = _frameCollisions + 1
                local e = _nearby[ni]
                if e.alive and not e.charmed and not Skill.xmasTreeHitMap[e] then
                    local edx = e.x - treeX
                    local edy = e.y - treeY
                    local eR = e.radius or 15
                    local totalR = hitR + eR
                    if edx * edx + edy * edy <= totalR * totalR then
                        DamageStats._currentSource = "xmas_tree"
                        local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, contactDmg)
                        DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                        Particle.Spawn(e.x, e.y, "hit")
                        Skill.xmasTreeHitMap[e] = contactInterval
                        if killed2 then
                            table.insert(killed, e)
                        end
                    end
                end
            end
        end

        -- 圣诞树消除敌方子弹（环绕树接触敌弹时消除）
        local clearR = hitR + 6  -- 消除半径略大于接触半径
        for ti = 1, treeCount do
            local treeAngle = Skill.xmasTreeAngle + (ti - 1) * angleStep
            local treeX = playerX + math.cos(treeAngle) * orbitR
            local treeY = playerY + math.sin(treeAngle) * orbitR
            for bi = #EnemyBullet.active, 1, -1 do
                local b = EnemyBullet.active[bi]
                if b.alive then
                    local bdx = b.x - treeX
                    local bdy = b.y - treeY
                    if bdx * bdx + bdy * bdy <= (clearR + b.radius) * (clearR + b.radius) then
                        b.alive = false
                        Particle.Spawn(b.x, b.y, "hit")
                    end
                end
            end
        end

        -- 冰弹发射（轮流从不同树发射）
        Skill.xmasTreeIceTimer = Skill.xmasTreeIceTimer + dt
        if Skill.xmasTreeIceTimer >= iceInterval then
            Skill.xmasTreeIceTimer = Skill.xmasTreeIceTimer - iceInterval
            -- 选择本次发射的树（轮流）
            Skill.xmasTreeIceIndex = ((Skill.xmasTreeIceIndex or 0) % treeCount) + 1
            local shootAngle = Skill.xmasTreeAngle + (Skill.xmasTreeIceIndex - 1) * angleStep
            local shootX = playerX + math.cos(shootAngle) * orbitR
            local shootY = playerY + math.sin(shootAngle) * orbitR
            -- 寻找最近敌人（空间哈希加速）
            local nearestE = nil
            local nearDist2 = 500 * 500
            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
            skillHash:QueryInto(shootX, shootY, 500, _nearby)
            for ni = 1, #_nearby do
                local e = _nearby[ni]
                if e.alive and not e.charmed then
                    local edx = e.x - shootX
                    local edy = e.y - shootY
                    local ed2 = edx * edx + edy * edy
                    if ed2 < nearDist2 then
                        nearDist2 = ed2
                        nearestE = e
                    end
                end
            end
            if nearestE then
                Projectile.SpawnIceBullet(shootX, shootY, nearestE.x, nearestE.y, true)
            else
                local dirX = math.cos(shootAngle)
                local dirY = math.sin(shootAngle)
                Projectile.SpawnIceBullet(shootX, shootY, shootX + dirX * 200, shootY + dirY * 200, true)
            end
        end
    end

    -- ======== 霜瑟风暴（叶子专属）========
    local leafStormLevel = playerSkills["leaf_storm"] or 0
    if leafStormLevel > 0 then
        local skillDef = Config.FindSkill("leaf_storm")
        local eff = skillDef.effect
        local radius = eff.radius + 15 * leafStormLevel
        -- 每秒 2*level 次命中，AoE 命中范围内全部敌人，伤害 = playerAtk / 3
        local hitsPerSecond = 2 * leafStormLevel
        local hitInterval = 1.0 / hitsPerSecond
        local dmg = math.max(1, SM.mulFloor(playerAtk, 1/3))

        Skill.leafStormTimer = Skill.leafStormTimer + dt
        Skill.leafStormAngle = Skill.leafStormAngle + 2.0 * dt

        -- 可能一帧内触发多次（高等级时），加安全上限防卡死
        local leafLoopCap = 10
        while Skill.leafStormTimer >= hitInterval and leafLoopCap > 0 do
            leafLoopCap = leafLoopCap - 1
            Skill.leafStormTimer = Skill.leafStormTimer - hitInterval
            -- AoE：对范围内所有敌人造成伤害 + 叠加冰冻（空间哈希加速）
            local hitAny = false
            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
            skillHash:QueryInto(playerX, playerY, radius, _nearby)
            for ni = 1, #_nearby do
                local e = _nearby[ni]
                if e.alive and not e.charmed then
                    local edx = e.x - playerX
                    local edy = e.y - playerY
                    if edx * edx + edy * edy <= radius * radius then
                        hitAny = true
                        DamageStats._currentSource = "leaf_storm"
                        local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, dmg)
                        DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                        Particle.Spawn(e.x, e.y, "hit")
                        Enemy.ApplyFreezeStack(e)
                        if killed2 then
                            table.insert(killed, e)
                        end
                    end
                end
            end
            if hitAny then
                Skill.leafStormFlash = 0.15
            end
        end
        if Skill.leafStormFlash > 0 then
            Skill.leafStormFlash = Skill.leafStormFlash - dt
        end
    end

    -- ======== OTTO: 大象踩背 (elephant_stomp) ========
    local elephantLevel = playerSkills["elephant_stomp"] or 0
    if elephantLevel > 0 and Player.charId == "otto" then
        -- 清理过期/死亡的大象
        for i = #elephants, 1, -1 do
            local el = elephants[i]
            el.life = el.life - dt
            if el.life <= 0 then
                table.remove(elephants, i)
            end
        end

        -- 大象缓慢接近最近敌人（空间哈希加速寻敌）
        for _, el in ipairs(elephants) do
            local nearE = nil
            local nearD2 = math.huge
            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
            skillHash:QueryInto(el.x, el.y, 400, _nearby)
            for ni = 1, #_nearby do
                local e = _nearby[ni]
                if e.alive and not e.charmed then
                    local dx = e.x - el.x
                    local dy = e.y - el.y
                    local d2 = dx * dx + dy * dy
                    if d2 < nearD2 then
                        nearD2 = d2
                        nearE = e
                    end
                end
            end
            if nearE then
                local dx = nearE.x - el.x
                local dy = nearE.y - el.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > 5 then
                    el.x = el.x + (dx / dist) * 60 * dt
                    el.y = el.y + (dy / dist) * 60 * dt
                end
                el.targetEnemy = nearE
            end
        end

        -- 每秒踩踏一次：所有大象向最近敌人位移并造成AoE伤害
        Skill.elephantStompTimer = Skill.elephantStompTimer + dt
        if Skill.elephantStompTimer >= 1.0 then
            Skill.elephantStompTimer = Skill.elephantStompTimer - 1.0
            local stompDmg = SM.mulFloor(playerAtk, 1.5)
            local stompRadius = 80
            for _, el in ipairs(elephants) do
                -- 踩踏时向最近敌人位移一小段
                if el.targetEnemy and el.targetEnemy.alive then
                    local dx = el.targetEnemy.x - el.x
                    local dy = el.targetEnemy.y - el.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist > 5 then
                        local shift = math.min(30, dist)
                        el.x = el.x + (dx / dist) * shift
                        el.y = el.y + (dy / dist) * shift
                    end
                end
                -- AoE伤害（空间哈希加速）
                for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                skillHash:QueryInto(el.x, el.y, stompRadius, _nearby)
                for ni = 1, #_nearby do
                    local e = _nearby[ni]
                    if e.alive and not e.charmed then
                        local edx = e.x - el.x
                        local edy = e.y - el.y
                        if edx * edx + edy * edy <= stompRadius * stompRadius then
                            DamageStats._currentSource = "elephant_stomp"
                            local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, stompDmg)
                            DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                            Particle.Spawn(e.x, e.y, "hit")
                            if killed2 then
                                table.insert(killed, e)
                            end
                        end
                    end
                end
                -- 踩踏视觉效果
                Particle.SpawnShockWave(el.x, el.y, stompRadius, 0.3, 180, 140, 100, 2)
            end
        end
    else
        elephants = {}
    end

    -- ======== OTTO: 我喜欢你你喜欢我 (charm_enemy) ========
    -- 魅惑触发已移至 Skill.TryCharmOnKill()（由 HandleKills 调用）
    -- 此处仅处理：清理死亡魅惑敌人 + 魅惑敌人 AI 行为
    local charmLevel = playerSkills["charm_enemy"] or 0
    if charmLevel > 0 then
        -- 清理死亡/无效的魅惑敌人
        for i = #charmedEnemies, 1, -1 do
            local ce = charmedEnemies[i]
            if not ce.alive then
                table.remove(charmedEnemies, i)
            end
        end

        -- ── 魅惑敌人 AI ──
        local charmTickInterval = 1.0 / 6.0  -- 每秒6次攻击
        Skill.charmDamageTimer = Skill.charmDamageTimer + dt

        for _, ce in ipairs(charmedEnemies) do
            if ce.alive and not ce.isBoss then  -- Boss由Enemy.lua自身AI控制
                -- 索敌：距离自身最近的、血量为正的、未被魅惑的唯一敌人
                local nearTarget = nil
                local nearTargetD2 = math.huge
                for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                skillHash:QueryInto(ce.x, ce.y, 400, _nearby)
                for ni = 1, #_nearby do
                    local e = _nearby[ni]
                    if e.alive and not e.charmed and e.hp > 0 then
                        local dx = e.x - ce.x
                        local dy = e.y - ce.y
                        local d2 = dx * dx + dy * dy
                        if d2 < nearTargetD2 then
                            nearTargetD2 = d2
                            nearTarget = e
                        end
                    end
                end

                if nearTarget then
                    local dx = nearTarget.x - ce.x
                    local dy = nearTarget.y - ce.y
                    local dist = math.sqrt(dx * dx + dy * dy)

                    -- ── 远程类魅惑敌人 (ranger)：发射魅惑子弹 ──
                    if ce.typeName == "ranger" then
                        local rDef = Config.ENEMY.ranger
                        ce.shootTimer = (ce.shootTimer or 0) + dt
                        local keepDist = rDef.keepDistance or 180
                        local moveSpeed = (ce.speed or 90) * 1.2

                        -- 保持距离
                        if dist > (rDef.shootRange or 250) then
                            ce.x = ce.x + (dx / dist) * moveSpeed * dt
                            ce.y = ce.y + (dy / dist) * moveSpeed * dt
                        elseif dist < keepDist * 0.7 then
                            ce.x = ce.x - (dx / dist) * moveSpeed * 0.8 * dt
                            ce.y = ce.y - (dy / dist) * moveSpeed * 0.8 * dt
                        end

                        -- 射击（魅惑子弹：只打敌人、不被我方消除）
                        if ce.shootTimer >= (rDef.shootInterval or 2.0) and dist <= (rDef.shootRange or 250) then
                            ce.shootTimer = 0
                            local bSpeed = rDef.bulletSpeed or 280
                            local cb = EnemyBullet.Spawn(ce.x, ce.y, nearTarget.x, nearTarget.y,
                                ce.atk, bSpeed, "💗", { 255, 100, 200 })
                            cb.charmedBullet = true  -- 标记为魅惑子弹
                        end
                    else
                        -- ── 近战类魅惑敌人：向目标移动 + 范围内每秒6次攻击 ──
                        local moveSpeed = (ce.speed or 80) * 1.2
                        if dist > 10 then
                            ce.x = ce.x + (dx / dist) * moveSpeed * dt
                            ce.y = ce.y + (dy / dist) * moveSpeed * dt
                        end

                        -- 在判定范围内（接触距离）造成攻击伤害
                        local ceR = ce.radius or 15
                        local targetR = nearTarget.radius or 15
                        local contactDist = ceR + targetR + 5
                        if dist <= contactDist and Skill.charmDamageTimer >= charmTickInterval then
                            local tickDmg = math.max(1, SM.floor(ce.atk))
                            -- 对范围内所有非魅惑敌人造成伤害
                            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                            skillHash:QueryInto(ce.x, ce.y, contactDist + 20, _nearby)
                            for ni = 1, #_nearby do
                                local e = _nearby[ni]
                                if e.alive and not e.charmed and e.hp > 0 then
                                    local edx = e.x - ce.x
                                    local edy = e.y - ce.y
                                    local ed2 = edx * edx + edy * edy
                                    if ed2 <= contactDist * contactDist then
                                        DamageStats._currentSource = "charm_enemy"
                                        local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, tickDmg)
                                        DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                                        Particle.Spawn(e.x, e.y, "hit")
                                        if killed2 then
                                            table.insert(killed, e)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        -- 魅惑Boss接触伤害（移动由Enemy.lua处理，此处仅做碰撞伤害）
        if Skill.charmDamageTimer >= charmTickInterval then
            for _, ce in ipairs(charmedEnemies) do
                if ce.alive and ce.isBoss then
                    local ceR = ce.radius or 15
                    local tickDmg = math.max(1, SM.floor(ce.atk))
                    local bossContactR = ceR + 35  -- 最大可能的接触距离
                    for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                    skillHash:QueryInto(ce.x, ce.y, bossContactR, _nearby)
                    for ni = 1, #_nearby do
                        local e = _nearby[ni]
                        if e.alive and not e.charmed and e.hp > 0 then
                            local edx = e.x - ce.x
                            local edy = e.y - ce.y
                            local ed2 = edx * edx + edy * edy
                            local contactDist = ceR + (e.radius or 15) + 5
                            if ed2 <= contactDist * contactDist then
                                DamageStats._currentSource = "charm_enemy"
                                local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, tickDmg)
                                DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                                Particle.Spawn(e.x, e.y, "hit")
                                if killed2 then
                                    table.insert(killed, e)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 重置攻击tick计时器
        if Skill.charmDamageTimer >= charmTickInterval then
            Skill.charmDamageTimer = Skill.charmDamageTimer - charmTickInterval
        end
    else
        -- 技能未学习：清理所有魅惑标记
        for _, ce in ipairs(charmedEnemies) do
            if ce.alive then
                ce.charmed = false
                ce.charmedInvincible = false
            end
        end
        charmedEnemies = {}
    end

    -- ======== OTTO: 慢行者 (slow_rider) ========
    local slowRiderLevel = playerSkills["slow_rider"] or 0
    if slowRiderLevel > 0 then
        local fireInterval = 4.0 / slowRiderLevel
        Skill.slowRiderTimer = Skill.slowRiderTimer + dt

        -- 发射马匹子弹
        if Skill.slowRiderTimer >= fireInterval then
            Skill.slowRiderTimer = Skill.slowRiderTimer - fireInterval
            -- 找最近敌人（空间哈希加速）
            local nearE = nil
            local nearD2 = math.huge
            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
            skillHash:QueryInto(playerX, playerY, 600, _nearby)
            for ni = 1, #_nearby do
                local e = _nearby[ni]
                if e.alive and not e.charmed then
                    local dx = e.x - playerX
                    local dy = e.y - playerY
                    local d2 = dx * dx + dy * dy
                    if d2 < nearD2 then
                        nearD2 = d2
                        nearE = e
                    end
                end
            end
            if nearE then
                table.insert(horseProjectiles, {
                    x = playerX,
                    y = playerY,
                    targetEnemy = nearE,
                    dmg = SM.mulFloor(playerAtk, 1.0),
                })
            end
        end

        -- 更新马匹子弹：锁定追踪目标
        for i = #horseProjectiles, 1, -1 do
            local hp = horseProjectiles[i]
            local target = hp.targetEnemy
            -- 如果目标死亡，重新锁定最近敌人（空间哈希加速）
            if not target or not target.alive then
                local nearE = nil
                local nearD2 = math.huge
                for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                skillHash:QueryInto(hp.x, hp.y, 600, _nearby)
                for ni = 1, #_nearby do
                    local e = _nearby[ni]
                    if e.alive and not e.charmed then
                        local dx = e.x - hp.x
                        local dy = e.y - hp.y
                        local d2 = dx * dx + dy * dy
                        if d2 < nearD2 then
                            nearD2 = d2
                            nearE = e
                        end
                    end
                end
                if nearE then
                    hp.targetEnemy = nearE
                    target = nearE
                else
                    table.remove(horseProjectiles, i)
                    goto continue_horse
                end
            end

            local dx = target.x - hp.x
            local dy = target.y - hp.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 15 then
                -- 到达目标：生成旋风
                table.insert(horseWhirlwinds, {
                    x = target.x,
                    y = target.y,
                    life = 5.0,
                    dmg = hp.dmg,
                    tickTimer = 0,
                })
                Particle.SpawnShockWave(target.x, target.y, 60, 0.3, 120, 200, 120, 2)
                table.remove(horseProjectiles, i)
            else
                -- 飞向目标
                hp.x = hp.x + (dx / dist) * 300 * dt
                hp.y = hp.y + (dy / dist) * 300 * dt
            end
            ::continue_horse::
        end

        -- 更新旋风：持续5秒，每0.5秒造成一次伤害
        for i = #horseWhirlwinds, 1, -1 do
            local ww = horseWhirlwinds[i]
            ww.life = ww.life - dt
            if ww.life <= 0 then
                table.remove(horseWhirlwinds, i)
            else
                ww.tickTimer = ww.tickTimer + dt
                local whirlwindTickInterval = 0.5  -- 2x/sec
                if ww.tickTimer >= whirlwindTickInterval then
                    ww.tickTimer = ww.tickTimer - whirlwindTickInterval
                    local whirlRadius = 60
                    for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                    skillHash:QueryInto(ww.x, ww.y, whirlRadius, _nearby)
                    for ni = 1, #_nearby do
                        local e = _nearby[ni]
                        if e.alive and not e.charmed then
                            DamageStats._currentSource = "slow_rider"
                            local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, ww.dmg)
                            DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                            Particle.Spawn(e.x, e.y, "hit")
                            if killed2 then
                                table.insert(killed, e)
                            end
                        end
                    end
                end
            end
        end
    else
        horseProjectiles = {}
        horseWhirlwinds = {}
    end

    -- ======== OTTO: 盒子 (otto_box) ========
    local ottoBoxLevel = playerSkills["otto_box"] or 0
    if ottoBoxLevel > 0 then
        local maxBoxes = ottoBoxLevel

        -- 每5秒判定一次：放置或拆除
        Skill.ottoBoxPlaceTimer = (Skill.ottoBoxPlaceTimer or 0) + dt
        if Skill.ottoBoxPlaceTimer >= 5.0 then
            Skill.ottoBoxPlaceTimer = Skill.ottoBoxPlaceTimer - 5.0
            if #ottoBoxes < maxBoxes then
                -- 数量不足：在玩家位置放置一个
                local angle = math.random() * math.pi * 2
                local dist = 30
                table.insert(ottoBoxes, {
                    x = playerX + math.cos(angle) * dist,
                    y = playerY + math.sin(angle) * dist,
                    spawnAge = 0,        -- 放置动画计时
                    removing = false,    -- 是否正在拆除
                    removeAge = 0,       -- 拆除动画计时
                    -- Drone 僚机（与主机完全一致）
                    droneTimer = 0,
                    droneAngle = math.random() * math.pi * 2,
                    droneCollisionTimer = 0,
                    droneTrails = {},       -- 拖尾数据 [droneIndex] = { {x,y}, ... }
                    droneTrailHead = 0,
                    droneTrailTimer = 0,
                    -- Clone 僚机（与主机完全一致）
                    clones = {},
                    cloneAngle = math.random() * math.pi * 2,
                    -- Xmas 僚机（与主机完全一致）
                    xmasAngle = math.random() * math.pi * 2,
                    xmasHitMap = {},
                    xmasIceTimer = 0,
                    xmasIceIndex = 0,
                    -- Green Drone 僚机（与主机完全一致）
                    greenDroneAngle = math.random() * math.pi * 2,
                    greenDroneTimer = 0,
                    greenDroneCollisionTimer = 0,
                    greenDroneTrails = {},
                    greenDroneTrailHead = 0,
                    greenDroneTrailTimer = 0,
                })
            elseif #ottoBoxes >= maxBoxes then
                -- 数量已满且玩家附近有盒子：标记最近盒子为拆除中
                local pickupRange = 60
                local closestIdx = nil
                local closestD2 = pickupRange * pickupRange
                for bi, box in ipairs(ottoBoxes) do
                    if not box.removing then
                        local bdx = box.x - playerX
                        local bdy = box.y - playerY
                        local d2 = bdx * bdx + bdy * bdy
                        if d2 < closestD2 then
                            closestD2 = d2
                            closestIdx = bi
                        end
                    end
                end
                if closestIdx then
                    ottoBoxes[closestIdx].removing = true
                    ottoBoxes[closestIdx].removeAge = 0
                end
            end
        end

        -- 更新动画计时 & 僚机角度 & 移除完成拆除的盒子
        for bi = #ottoBoxes, 1, -1 do
            local box = ottoBoxes[bi]
            box.spawnAge = (box.spawnAge or 0) + dt
            -- 与主僚机相同的角速度
            box.droneAngle = (box.droneAngle or 0) + Skill.droneSpeed * dt
            box.xmasAngle = (box.xmasAngle or 0) + 2.5 * dt
            box.cloneAngle = (box.cloneAngle or 0) + 1.8 * dt
            box.greenDroneAngle = (box.greenDroneAngle or 0) + Skill.greenDroneSpeed * dt
            if box.removing then
                box.removeAge = (box.removeAge or 0) + dt
                if box.removeAge >= 0.3 then
                    table.remove(ottoBoxes, bi)
                end
            end
        end

        -- 盒子固定在场地上，不跟随玩家
        -- 每个盒子拥有与主僚机完全一致的攻击逻辑（仅伤害减半）
        local DMG_MULT = 0.5  -- 盒子伤害倍率

        for bi, box in ipairs(ottoBoxes) do
            if box.removing then goto continue_box end

            -- ======== 盒子 Drone 僚机（与主机 atk_drone 完全一致）========
            local droneLv = playerSkills["atk_drone"] or 0
            if droneLv > 0 then
                -- 激光攻击（同主机：间隔 1.0/等级，伤害 atk*0.5*等级*减半）
                local droneInterval = 1.0 / droneLv
                box.droneTimer = (box.droneTimer or 0) + dt
                if box.droneTimer >= droneInterval then
                    box.droneTimer = 0
                    local dmg = SM.mulFloor(playerAtk, 0.5 * droneLv * DMG_MULT)
                    local nearest = nil
                    local nearDist = 400 * 400
                    for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                    skillHash:QueryInto(box.x, box.y, 400, _nearby)
                    for ni = 1, #_nearby do
                        local e = _nearby[ni]
                        if e.alive and not e.charmed then
                            local dx = e.x - box.x
                            local dy = e.y - box.y
                            local d2 = dx * dx + dy * dy
                            if d2 < nearDist then
                                nearDist = d2
                                nearest = e
                            end
                        end
                    end
                    if nearest then
                        DamageStats._currentSource = "thumb_up"
                        local killed2, finalAmount, isFrozenHit = Enemy.Damage(nearest, dmg)
                        DamageNumber.SpawnDamage(nearest.x, nearest.y - 10, finalAmount, false, isFrozenHit)
                        -- 激光从环绕 drone 位置射出（与主机一致）
                        local da = box.droneAngle or 0
                        local drX = box.x + math.cos(da) * Skill.droneOrbitRadius
                        local drY = box.y + math.sin(da) * Skill.droneOrbitRadius
                        Particle.SpawnLaser(drX, drY, nearest.x, nearest.y, 0.15, 0, 220, 255, 2)
                        Particle.Spawn(nearest.x, nearest.y, "hit")
                        if killed2 then
                            table.insert(killed, nearest)
                        end
                    end
                end

                -- Drone 碰撞伤害（同主机毕业后碰撞）
                if Player.droneCollisionDmg > 0 then
                    box.droneCollisionTimer = (box.droneCollisionTimer or 0) + dt
                    if box.droneCollisionTimer >= Config.GRADUATION.DRONE_COLLISION_TICK then
                        box.droneCollisionTimer = box.droneCollisionTimer - Config.GRADUATION.DRONE_COLLISION_TICK
                        local maxDrones = Player.graduationPhase >= 1 and 7 or 4
                        local droneCount = math.min(droneLv, maxDrones)
                        local angleStep = (math.pi * 2) / droneCount
                        local collisionR = Skill.droneVisualSize + 12
                        local colDmg = SM.mulFloor(Player.droneCollisionDmg, DMG_MULT)
                        for i = 1, droneCount do
                            if _frameCollisions >= FRAME_COLLISION_BUDGET then break end
                            local a = (box.droneAngle or 0) + (i - 1) * angleStep
                            local drX = box.x + math.cos(a) * Skill.droneOrbitRadius
                            local drY = box.y + math.sin(a) * Skill.droneOrbitRadius
                            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                            skillHash:QueryInto(drX, drY, collisionR + 20, _nearby)
                            for ni = 1, #_nearby do
                                _frameCollisions = _frameCollisions + 1
                                local e = _nearby[ni]
                                if e.alive and not e.charmed then
                                    local edx = e.x - drX
                                    local edy = e.y - drY
                                    local eR = e.radius or 15
                                    local hitDist = collisionR + eR
                                    if edx * edx + edy * edy <= hitDist * hitDist then
                                        DamageStats._currentSource = "thumb_up"
                                        local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, colDmg)
                                        DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                                        if killed2 then
                                            table.insert(killed, e)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                -- Drone 拖尾采样（与主机完全一致）
                box.droneTrailTimer = (box.droneTrailTimer or 0) + dt
                if box.droneTrailTimer >= TRAIL_INTERVAL then
                    box.droneTrailTimer = 0
                    box.droneTrailHead = ((box.droneTrailHead or 0) % TRAIL_MAX) + 1
                    local maxDrones = Player.graduationPhase >= 1 and 7 or 4
                    local droneCount = math.min(droneLv, maxDrones)
                    local angleStep = (math.pi * 2) / droneCount
                    if not box.droneTrails then box.droneTrails = {} end
                    for i = 1, droneCount do
                        if not box.droneTrails[i] then box.droneTrails[i] = {} end
                        local a = (box.droneAngle or 0) + (i - 1) * angleStep
                        local dx = math.cos(a) * Skill.droneOrbitRadius
                        local dy = math.sin(a) * Skill.droneOrbitRadius
                        box.droneTrails[i][box.droneTrailHead] = { x = box.x + dx, y = box.y + dy }
                    end
                end
            end

            -- ======== 盒子 Clone 僚机（与主机 clone_strike 完全一致）========
            local cloneLv = playerSkills["clone_strike"] or 0
            if cloneLv > 0 then
                local cloneCount = math.min(cloneLv, 3)
                -- 初始化/调整分身数量
                if not box.clones then box.clones = {} end
                while #box.clones < cloneCount do
                    local ca = (box.cloneAngle or 0) + (#box.clones) * ((math.pi * 2) / cloneCount)
                    table.insert(box.clones, {
                        x = box.x + math.cos(ca) * CLONE_ORBIT_DIST,
                        y = box.y + math.sin(ca) * CLONE_ORBIT_DIST,
                        attackTimer = 0,
                    })
                end
                while #box.clones > cloneCount do
                    table.remove(box.clones)
                end

                -- 分身伤害与主机一致（含猴子散射加成），再减半
                local cloneDmgRatio = 0.2
                local totalPierceCount = 0
                local totalExtraBullets = 0
                for sid, slv in pairs(playerSkills) do
                    local def = Config.FindSkill(sid)
                    if def and def.effect then
                        if def.effect.pierceCount then
                            totalPierceCount = totalPierceCount + def.effect.pierceCount * slv
                        end
                        if def.effect.extraBullets then
                            if Player.charId == "monkey" then
                                cloneDmgRatio = cloneDmgRatio + 0.10 * slv
                            else
                                totalExtraBullets = totalExtraBullets + def.effect.extraBullets * slv
                            end
                        end
                    end
                end
                local cloneDmg = SM.mulFloor(playerAtk, cloneDmgRatio * DMG_MULT)

                local cloneSkillDef = Config.FindSkill("clone_strike")
                local cloneInterval = cloneSkillDef.effect.interval / cloneLv
                local cloneAngleStep = (math.pi * 2) / cloneCount

                for i, c in ipairs(box.clones) do
                    -- 分身环绕盒子（盒子不移动，直接定位）
                    local orbitAngle = (box.cloneAngle or 0) + (i - 1) * cloneAngleStep
                    local targetX = box.x + math.cos(orbitAngle) * CLONE_ORBIT_DIST
                    local targetY = box.y + math.sin(orbitAngle) * CLONE_ORBIT_DIST
                    local cdx = targetX - c.x
                    local cdy = targetY - c.y
                    local cdist = math.sqrt(cdx * cdx + cdy * cdy)
                    if cdist > 2 then
                        local spd = math.min(CLONE_FOLLOW_SPEED * dt, cdist)
                        c.x = c.x + (cdx / cdist) * spd
                        c.y = c.y + (cdy / cdist) * spd
                    end

                    -- 自动发射射弹（继承所有加成，与主机一致）
                    c.attackTimer = c.attackTimer + dt
                    if c.attackTimer >= cloneInterval then
                        c.attackTimer = 0
                        local nearest = nil
                        local nearDist = CLONE_ATTACK_RANGE * CLONE_ATTACK_RANGE
                        for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                        skillHash:QueryInto(c.x, c.y, CLONE_ATTACK_RANGE, _nearby)
                        for ni = 1, #_nearby do
                            local e = _nearby[ni]
                            if e.alive and not e.charmed then
                                local edx = e.x - c.x
                                local edy = e.y - c.y
                                local ed2 = edx * edx + edy * edy
                                if ed2 < nearDist then
                                    nearDist = ed2
                                    nearest = e
                                end
                            end
                        end
                        if nearest then
                            local totalBounceCount = Player.bounceCount
                            if totalExtraBullets > 0 then
                                Projectile.SpawnSpread(c.x, c.y, nearest.x, nearest.y,
                                    cloneDmg, totalPierceCount, totalExtraBullets, totalBounceCount)
                            else
                                Projectile.Spawn(c.x, c.y, nearest.x, nearest.y,
                                    cloneDmg, totalPierceCount, nil, totalBounceCount)
                            end
                        end
                    end
                end
            else
                if box.clones then box.clones = {} end
            end

            -- ======== 盒子 Xmas 僚机（与主机 xmas_tree 完全一致）========
            local xmasLv = playerSkills["xmas_tree"] or 0
            if xmasLv > 0 then
                local xmasSkillDef = Config.FindSkill("xmas_tree")
                local xmasEff = xmasSkillDef.effect
                local treeCount = xmasLv
                local xmasOrbitR = xmasEff.orbitRadius + 10 * xmasLv
                local contactInterval = xmasEff.interval
                local contactDmg = SM.mulFloor(playerAtk, xmasEff.baseDmg * xmasLv * DMG_MULT)
                local iceInterval = xmasEff.iceBulletInterval / xmasLv
                local xmasAngleStep = (math.pi * 2) / treeCount
                local hitR = 28 + 4 * xmasLv

                -- 更新 per-enemy 命中冷却
                if not box.xmasHitMap then box.xmasHitMap = {} end
                for e, cd in pairs(box.xmasHitMap) do
                    if not e.alive then
                        box.xmasHitMap[e] = nil
                    else
                        cd = cd - dt
                        if cd <= 0 then
                            box.xmasHitMap[e] = nil
                        else
                            box.xmasHitMap[e] = cd
                        end
                    end
                end

                for ti = 1, treeCount do
                    if _frameCollisions >= FRAME_COLLISION_BUDGET then break end
                    local treeAngle = (box.xmasAngle or 0) + (ti - 1) * xmasAngleStep
                    local treeX = box.x + math.cos(treeAngle) * xmasOrbitR
                    local treeY = box.y + math.sin(treeAngle) * xmasOrbitR

                    -- 接触伤害（per-enemy 命中冷却，空间哈希加速）
                    for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                    skillHash:QueryInto(treeX, treeY, hitR + 20, _nearby)
                    for ni = 1, #_nearby do
                        _frameCollisions = _frameCollisions + 1
                        local e = _nearby[ni]
                        if e.alive and not e.charmed and not box.xmasHitMap[e] then
                            local edx = e.x - treeX
                            local edy = e.y - treeY
                            local eR = e.radius or 15
                            local totalR = hitR + eR
                            if edx * edx + edy * edy <= totalR * totalR then
                                DamageStats._currentSource = "xmas_tree"
                                local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, contactDmg)
                                DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                                Particle.Spawn(e.x, e.y, "hit")
                                box.xmasHitMap[e] = contactInterval
                                if killed2 then
                                    table.insert(killed, e)
                                end
                            end
                        end
                    end
                end

                -- 圣诞树消除敌方子弹
                local clearR = hitR + 6
                for ti = 1, treeCount do
                    local treeAngle = (box.xmasAngle or 0) + (ti - 1) * xmasAngleStep
                    local treeX = box.x + math.cos(treeAngle) * xmasOrbitR
                    local treeY = box.y + math.sin(treeAngle) * xmasOrbitR
                    for ebi = #EnemyBullet.active, 1, -1 do
                        local b = EnemyBullet.active[ebi]
                        if b.alive then
                            local bdx = b.x - treeX
                            local bdy = b.y - treeY
                            if bdx * bdx + bdy * bdy <= (clearR + b.radius) * (clearR + b.radius) then
                                b.alive = false
                                Particle.Spawn(b.x, b.y, "hit")
                            end
                        end
                    end
                end

                -- 冰弹发射（轮流从不同树发射）
                box.xmasIceTimer = (box.xmasIceTimer or 0) + dt
                if box.xmasIceTimer >= iceInterval then
                    box.xmasIceTimer = box.xmasIceTimer - iceInterval
                    box.xmasIceIndex = ((box.xmasIceIndex or 0) % treeCount) + 1
                    local shootAngle = (box.xmasAngle or 0) + (box.xmasIceIndex - 1) * xmasAngleStep
                    local shootX = box.x + math.cos(shootAngle) * xmasOrbitR
                    local shootY = box.y + math.sin(shootAngle) * xmasOrbitR
                    local nearestE = nil
                    local nearDist2 = math.huge
                    for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                    skillHash:QueryInto(shootX, shootY, 400, _nearby)
                    for ni = 1, #_nearby do
                        local e = _nearby[ni]
                        if e.alive and not e.charmed then
                            local edx = e.x - shootX
                            local edy = e.y - shootY
                            local ed2 = edx * edx + edy * edy
                            if ed2 < nearDist2 then
                                nearDist2 = ed2
                                nearestE = e
                            end
                        end
                    end
                    if nearestE then
                        Projectile.SpawnIceBullet(shootX, shootY, nearestE.x, nearestE.y, true)
                    else
                        local dirX = math.cos(shootAngle)
                        local dirY = math.sin(shootAngle)
                        Projectile.SpawnIceBullet(shootX, shootY, shootX + dirX * 200, shootY + dirY * 200, true)
                    end
                end
            end

            -- ======== 盒子 Green Drone 僚机（与主机 atk_drone_green 完全一致）========
            local greenDroneLv = playerSkills["atk_drone_green"] or 0
            if greenDroneLv > 0 then
                local greenOrbitR = Skill.greenDroneOrbitRadius

                -- 碰撞伤害（tick式，伤害=100%玩家攻击力*减半）
                box.greenDroneCollisionTimer = (box.greenDroneCollisionTimer or 0) + dt
                if box.greenDroneCollisionTimer >= Config.GRADUATION.DRONE_COLLISION_TICK then
                    box.greenDroneCollisionTimer = box.greenDroneCollisionTimer - Config.GRADUATION.DRONE_COLLISION_TICK
                    local collisionR = Skill.droneVisualSize + 12
                    local dmgCollision = SM.mulFloor(Player.atk, DMG_MULT)
                    local gAngleStep = (math.pi * 2) / greenDroneLv
                    for i = 1, greenDroneLv do
                        if _frameCollisions >= FRAME_COLLISION_BUDGET then break end
                        local a = (box.greenDroneAngle or 0) + (i - 1) * gAngleStep
                        local drX = box.x + math.cos(a) * greenOrbitR
                        local drY = box.y + math.sin(a) * greenOrbitR
                        for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                        skillHash:QueryInto(drX, drY, collisionR + 20, _nearby)
                        for ni = 1, #_nearby do
                            _frameCollisions = _frameCollisions + 1
                            local e = _nearby[ni]
                            if e.alive and not e.charmed then
                                local edx = e.x - drX
                                local edy = e.y - drY
                                local eR = e.radius or 15
                                local hitDist = collisionR + eR
                                if edx * edx + edy * edy <= hitDist * hitDist then
                                    DamageStats._currentSource = "atk_drone_green"
                                    local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, dmgCollision)
                                    DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                                    if killed2 then
                                        table.insert(killed, e)
                                    end
                                end
                            end
                        end
                    end
                end

                -- 远程激光攻击（间隔 1/level，伤害=0.25*level*atk*减半）
                local greenInterval = 1.0 / greenDroneLv
                box.greenDroneTimer = (box.greenDroneTimer or 0) + dt
                if box.greenDroneTimer >= greenInterval then
                    box.greenDroneTimer = 0
                    local dmg = SM.mulFloor(playerAtk, 0.25 * greenDroneLv * DMG_MULT)
                    local nearest = nil
                    local nearDist = 400 * 400
                    for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                    skillHash:QueryInto(box.x, box.y, 400, _nearby)
                    for ni = 1, #_nearby do
                        local e = _nearby[ni]
                        if e.alive and not e.charmed then
                            local dx = e.x - box.x
                            local dy = e.y - box.y
                            local d2 = dx * dx + dy * dy
                            if d2 < nearDist then
                                nearDist = d2
                                nearest = e
                            end
                        end
                    end
                    if nearest then
                        DamageStats._currentSource = "atk_drone_green"
                        local killed2, finalAmount, isFrozenHit = Enemy.Damage(nearest, dmg)
                        DamageNumber.SpawnDamage(nearest.x, nearest.y - 10, finalAmount, false, isFrozenHit)
                        local da = box.greenDroneAngle or 0
                        local drX = box.x + math.cos(da) * greenOrbitR
                        local drY = box.y + math.sin(da) * greenOrbitR
                        Particle.SpawnLaser(drX, drY, nearest.x, nearest.y, 0.15, 50, 255, 80, 2)
                        Particle.Spawn(nearest.x, nearest.y, "hit")
                        if killed2 then
                            table.insert(killed, nearest)
                        end
                    end
                end

                -- 拖尾采样（与主机完全一致）
                box.greenDroneTrailTimer = (box.greenDroneTrailTimer or 0) + dt
                if box.greenDroneTrailTimer >= TRAIL_INTERVAL then
                    box.greenDroneTrailTimer = 0
                    box.greenDroneTrailHead = ((box.greenDroneTrailHead or 0) % TRAIL_MAX) + 1
                    local gAngleStep = (math.pi * 2) / greenDroneLv
                    if not box.greenDroneTrails then box.greenDroneTrails = {} end
                    for i = 1, greenDroneLv do
                        if not box.greenDroneTrails[i] then box.greenDroneTrails[i] = {} end
                        local a = (box.greenDroneAngle or 0) + (i - 1) * gAngleStep
                        local dx = math.cos(a) * greenOrbitR
                        local dy = math.sin(a) * greenOrbitR
                        box.greenDroneTrails[i][box.greenDroneTrailHead] = { x = box.x + dx, y = box.y + dy }
                    end
                end
            end

            ::continue_box::
        end
    else
        ottoBoxes = {}
    end

    -- ======== OTTO: 冲刺 (otto_sprint) ========
    -- 已改为被动移速加成（每级+15%，上限3层），由 Player.RecalcStats 自动处理

    -- 无人机碰撞伤害（tick式）
    droneLevel = playerSkills["atk_drone"] or 0
    if droneLevel > 0 and Player.droneCollisionDmg > 0 then
        if Player.droneCollisionTimer >= Config.GRADUATION.DRONE_COLLISION_TICK then
            Player.droneCollisionTimer = Player.droneCollisionTimer - Config.GRADUATION.DRONE_COLLISION_TICK
            local maxDrones = Player.graduationPhase >= 1 and 7 or 4
            local droneCount = math.min(droneLevel, maxDrones)
            local angleStep = (math.pi * 2) / droneCount
            local collisionR = Skill.droneVisualSize + 12 -- 碰撞检测半径
            local dmg = SM.floor(Player.droneCollisionDmg)
            for i = 1, droneCount do
                if _frameCollisions >= FRAME_COLLISION_BUDGET then break end
                local a = Skill.droneAngle + (i - 1) * angleStep
                local drX = playerX + math.cos(a) * Skill.droneOrbitRadius
                local drY = playerY + math.sin(a) * Skill.droneOrbitRadius
                for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                skillHash:QueryInto(drX, drY, collisionR + 20, _nearby)
                for ni = 1, #_nearby do
                    _frameCollisions = _frameCollisions + 1
                    local e = _nearby[ni]
                    if e.alive and not e.charmed then
                        local edx = e.x - drX
                        local edy = e.y - drY
                        local eR = e.radius or 15
                        local hitDist = collisionR + eR
                        if edx * edx + edy * edy <= hitDist * hitDist then
                            DamageStats._currentSource = "atk_drone_green"
                            local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, dmg)
                            DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                            if killed2 then
                                table.insert(killed, e)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 无人机公转角度更新 + 拖尾采样
    if droneLevel > 0 then
        local maxDrones = Player.graduationPhase >= 1 and 7 or 4
        local droneCount = math.min(droneLevel, maxDrones)
        Skill.droneAngle = Skill.droneAngle + Skill.droneSpeed * dt

        -- 拖尾采样
        trailTimer = trailTimer + dt
        if trailTimer >= TRAIL_INTERVAL then
            trailTimer = 0
            trailHead = (trailHead % TRAIL_MAX) + 1  -- 1-based 环形
            local angleStep = (math.pi * 2) / droneCount
            for i = 1, droneCount do
                if not droneTrails[i] then droneTrails[i] = {} end
                local a = Skill.droneAngle + (i - 1) * angleStep
                local dx = math.cos(a) * Skill.droneOrbitRadius
                local dy = math.sin(a) * Skill.droneOrbitRadius
                droneTrails[i][trailHead] = { x = playerX + dx, y = playerY + dy }
            end
        end
    end

    -- ======== 绿色无人机 ========
    local greenDroneLevel = playerSkills["atk_drone_green"] or 0
    if greenDroneLevel > 0 then
        -- 碰撞伤害（tick式，伤害=100%玩家攻击力）
        if greenDroneCollisionTimer >= Config.GRADUATION.DRONE_COLLISION_TICK then
            greenDroneCollisionTimer = greenDroneCollisionTimer - Config.GRADUATION.DRONE_COLLISION_TICK
            local collisionR = Skill.droneVisualSize + 12
            local dmgCollision = SM.floor(Player.atk)
            local angleStep = (math.pi * 2) / greenDroneLevel
            for i = 1, greenDroneLevel do
                if _frameCollisions >= FRAME_COLLISION_BUDGET then break end
                local a = Skill.greenDroneAngle + (i - 1) * angleStep
                local drX = playerX + math.cos(a) * Skill.greenDroneOrbitRadius
                local drY = playerY + math.sin(a) * Skill.greenDroneOrbitRadius
                for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                skillHash:QueryInto(drX, drY, collisionR + 20, _nearby)
                for ni = 1, #_nearby do
                    _frameCollisions = _frameCollisions + 1
                    local e = _nearby[ni]
                    if e.alive and not e.charmed then
                        local edx = e.x - drX
                        local edy = e.y - drY
                        local eR = e.radius or 15
                        local hitDist = collisionR + eR
                        if edx * edx + edy * edy <= hitDist * hitDist then
                            DamageStats._currentSource = "atk_drone_green"
                            local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, dmgCollision)
                            DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, false, isFrozenHit)
                            if killed2 then
                                table.insert(killed, e)
                            end
                        end
                    end
                end
            end
        end
        greenDroneCollisionTimer = greenDroneCollisionTimer + dt

        -- 远程攻击：每 1/greenDroneLevel 秒攻击最近敌人，伤害=蓝色一半(0.25*level*atk)
        local interval = 1.0 / greenDroneLevel
        Skill.greenDroneTimer = Skill.greenDroneTimer + dt
        if Skill.greenDroneTimer >= interval then
            Skill.greenDroneTimer = 0
            local dmg = SM.mulFloor(playerAtk, 0.25 * greenDroneLevel)
            local nearest = nil
            local nearDist = 400 * 400
            for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
            skillHash:QueryInto(playerX, playerY, 400, _nearby)
            for ni = 1, #_nearby do
                local e = _nearby[ni]
                if e.alive and not e.charmed then
                    local dx = e.x - playerX
                    local dy = e.y - playerY
                    local d2 = dx * dx + dy * dy
                    if d2 < nearDist then
                        nearDist = d2
                        nearest = e
                    end
                end
            end
            if nearest then
                DamageStats._currentSource = "atk_drone_green"
                local killed2, finalAmount, isFrozenHit = Enemy.Damage(nearest, dmg)
                DamageNumber.SpawnDamage(nearest.x, nearest.y - 10, finalAmount, false, isFrozenHit)
                local da = Skill.greenDroneAngle
                local drX = playerX + math.cos(da) * Skill.greenDroneOrbitRadius
                local drY = playerY + math.sin(da) * Skill.greenDroneOrbitRadius
                Particle.SpawnLaser(drX, drY, nearest.x, nearest.y, 0.15, 50, 255, 80, 2)
                Particle.Spawn(nearest.x, nearest.y, "hit")
                if killed2 then
                    table.insert(killed, nearest)
                end
            end
        end

        -- 公转角度更新 + 拖尾采样
        Skill.greenDroneAngle = Skill.greenDroneAngle + Skill.greenDroneSpeed * dt
        greenTrailTimer = greenTrailTimer + dt
        if greenTrailTimer >= TRAIL_INTERVAL then
            greenTrailTimer = 0
            greenTrailHead = (greenTrailHead % TRAIL_MAX) + 1
            local angleStep = (math.pi * 2) / greenDroneLevel
            for i = 1, greenDroneLevel do
                if not greenDroneTrails[i] then greenDroneTrails[i] = {} end
                local a = Skill.greenDroneAngle + (i - 1) * angleStep
                local dx = math.cos(a) * Skill.greenDroneOrbitRadius
                local dy = math.sin(a) * Skill.greenDroneOrbitRadius
                greenDroneTrails[i][greenTrailHead] = { x = playerX + dx, y = playerY + dy }
            end
        end
    end

    DamageStats._currentSource = "basic"
    return killed
end

--- 击杀敌人时尝试魅惑（由 BattleScene.HandleKills 调用）
--- 机制：击杀 → 恢复满血 → 无敌 → 立即魅惑 → 保留maxHP最高的N个
---@param enemy table 被击杀的敌人
---@param playerSkills table 玩家技能表
function Skill.TryCharmOnKill(enemy, playerSkills)
    local charmLevel = playerSkills["charm_enemy"] or 0
    if charmLevel <= 0 then return end
    if enemy.charmed then return end          -- 已被魅惑的不重复处理

    local maxCharmed = charmLevel

    -- 复活该敌人：恢复满血、标记魅惑、无敌
    enemy.alive = true
    enemy.hp = enemy.maxHp or enemy.hp
    enemy.charmed = true
    enemy.charmedInvincible = true
    enemy.charmedIsSummon = false             -- 非召唤产物，占用魅惑上限
    table.insert(charmedEnemies, enemy)
    Particle.SpawnShockWave(enemy.x, enemy.y, 40, 0.3, 255, 100, 200, 2)

    -- ── 淘汰判定：保留 maxHP 最高的 maxCharmed 个，其余正常死亡 ──
    -- 只计算非召唤物的魅惑敌人
    local countable = {}
    for i, ce in ipairs(charmedEnemies) do
        if ce.alive and not ce.charmedIsSummon then
            table.insert(countable, { idx = i, enemy = ce, maxHp = ce.maxHp or ce.hp })
        end
    end

    if #countable > maxCharmed then
        -- 按 maxHp 降序排列
        table.sort(countable, function(a, b) return a.maxHp > b.maxHp end)
        -- 超出上限的从列表末尾淘汰
        local toRemove = {}
        for i = maxCharmed + 1, #countable do
            local ce = countable[i].enemy
            if ce.alive then
                ce.charmed = false
                ce.charmedInvincible = false
                ce.dying = true
                ce.deathTimer = 0.25
                Particle.Spawn(ce.x, ce.y, "enemy_die")
            end
            -- 记录要从 charmedEnemies 中移除的引用
            toRemove[ce] = true
        end
        -- 从 charmedEnemies 中移除淘汰的
        for i = #charmedEnemies, 1, -1 do
            if toRemove[charmedEnemies[i]] then
                table.remove(charmedEnemies, i)
            end
        end
    end
end

--- 获取有 CD 的技能冷却状态（供 HUD 显示）
---@param playerSkills table 玩家已有技能
---@return table[] { id, icon, ratio, remaining }
function Skill.GetCooldowns(playerSkills)
    local cds = {}

    local droneLevel = playerSkills["atk_drone"] or 0
    if droneLevel > 0 then
        local interval = 1.0 / droneLevel
        local ratio = math.min(1, Skill.droneTimer / interval)
        local remaining = math.max(0, interval - Skill.droneTimer)
        table.insert(cds, { id = "atk_drone", icon = "🛸", ratio = ratio, remaining = remaining })
    end

    local greenDroneLevelCD = playerSkills["atk_drone_green"] or 0
    if greenDroneLevelCD > 0 then
        local interval = 1.0 / greenDroneLevelCD
        local ratio = math.min(1, Skill.greenDroneTimer / interval)
        local remaining = math.max(0, interval - Skill.greenDroneTimer)
        table.insert(cds, { id = "atk_drone_green", icon = "🛩️", ratio = ratio, remaining = remaining })
    end

    local grenadeLevel = playerSkills["grenade"] or 0
    if grenadeLevel > 0 then
        local interval = 5.0 / grenadeLevel
        local ratio = math.min(1, Skill.grenadeTimer / interval)
        local remaining = math.max(0, interval - Skill.grenadeTimer)
        table.insert(cds, { id = "grenade", icon = "💣", ratio = ratio, remaining = remaining })
    end

    local grabSmashLevelCD = playerSkills["grab_smash"] or 0
    if grabSmashLevelCD > 0 then
        local skillDef = Config.FindSkill("grab_smash")
        local eff = skillDef.effect
        local maxCharges = grabSmashLevelCD
        local chargesLeft = math.max(0, maxCharges - Skill.taichiChargesUsed)
        local ratio = chargesLeft / maxCharges  -- 剩余次数比例
        local remaining = math.max(0, eff.baseCooldown - Skill.taichiCooldownTimer)
        table.insert(cds, { id = "grab_smash", icon = "🫴", ratio = ratio, remaining = remaining })
    end

    local cloneLevel = playerSkills["clone_strike"] or 0
    if cloneLevel > 0 then
        local skillDef = Config.FindSkill("clone_strike")
        if skillDef then
            local interval = skillDef.effect.interval / cloneLevel
            local ratio = math.min(1, Skill.cloneTimer / interval)
            local remaining = math.max(0, interval - Skill.cloneTimer)
            table.insert(cds, { id = "clone_strike", icon = "🐒", ratio = ratio, remaining = remaining })
        end
    end

    local catScratchLevel = playerSkills["cat_scratch"] or 0
    if catScratchLevel > 0 then
        local interval = 3.0 / catScratchLevel
        local ratio = math.min(1, Skill.catScratchTimer / interval)
        local remaining = math.max(0, interval - Skill.catScratchTimer)
        table.insert(cds, { id = "cat_scratch", icon = "⭐", ratio = ratio, remaining = remaining })
    end

    local beanSproutLevel = playerSkills["bean_sprout"] or 0
    if beanSproutLevel > 0 then
        local interval = 4.0 / beanSproutLevel
        local ratio = math.min(1, Skill.beanSproutTimer / interval)
        local remaining = math.max(0, interval - Skill.beanSproutTimer)
        table.insert(cds, { id = "bean_sprout", icon = "🌱", ratio = ratio, remaining = remaining })
    end

    local thumbUpLevel = playerSkills["thumb_up"] or 0
    if thumbUpLevel > 0 then
        local interval = 3.5 / thumbUpLevel
        local ratio = math.min(1, Skill.thumbUpTimer / interval)
        local remaining = math.max(0, interval - Skill.thumbUpTimer)
        table.insert(cds, { id = "thumb_up", icon = "👍", ratio = ratio, remaining = remaining })
    end

    local xmasTreeLevel = playerSkills["xmas_tree"] or 0
    if xmasTreeLevel > 0 then
        local skillDef = Config.FindSkill("xmas_tree")
        local iceInterval = skillDef.effect.iceBulletInterval / xmasTreeLevel
        local ratio = math.min(1, Skill.xmasTreeIceTimer / iceInterval)
        local remaining = math.max(0, iceInterval - Skill.xmasTreeIceTimer)
        table.insert(cds, { id = "xmas_tree", icon = "🎄", ratio = ratio, remaining = remaining })
    end

    local leafStormLevel = playerSkills["leaf_storm"] or 0
    if leafStormLevel > 0 then
        -- 霜瑟风暴：每秒 2*level 次命中
        local hitInterval = 1.0 / (2 * leafStormLevel)
        local ratio = math.min(1, Skill.leafStormTimer / hitInterval)
        local remaining = math.max(0, hitInterval - Skill.leafStormTimer)
        table.insert(cds, { id = "leaf_storm", icon = "🌨️", ratio = ratio, remaining = remaining })
    end

    -- ======== OTTO 专属技能 CD ========
    local elephantLevel = playerSkills["elephant_stomp"] or 0
    if elephantLevel > 0 then
        local ratio = math.min(1, Skill.elephantStompTimer / 1.0)
        local remaining = math.max(0, 1.0 - Skill.elephantStompTimer)
        table.insert(cds, { id = "elephant_stomp", icon = "🐘", ratio = ratio, remaining = remaining })
    end

    local ottoBoxLevel = playerSkills["otto_box"] or 0
    if ottoBoxLevel > 0 then
        local cdTotal = 5.0
        local ratio = math.min(1, (Skill.ottoBoxPlaceTimer or 0) / cdTotal)
        local remaining = math.max(0, cdTotal - (Skill.ottoBoxPlaceTimer or 0))
        table.insert(cds, { id = "otto_box", icon = "📦", ratio = ratio, remaining = remaining })
    end

    local slowRiderLevel = playerSkills["slow_rider"] or 0
    if slowRiderLevel > 0 then
        local fireInterval = 4.0 / slowRiderLevel
        local ratio = math.min(1, Skill.slowRiderTimer / fireInterval)
        local remaining = math.max(0, fireInterval - Skill.slowRiderTimer)
        table.insert(cds, { id = "slow_rider", icon = "🐎", ratio = ratio, remaining = remaining })
    end

    -- otto_sprint 已改为被动移速加成，无需CD显示

    return cds
end

--- 渲染无人机和拖尾
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
---@param playerX number 玩家世界X
---@param playerY number 玩家世界Y
---@param droneLevel number 无人机等级
function Skill.Render(vg, camX, camY, playerX, playerY, droneLevel)
    if droneLevel <= 0 then return end

    local maxDrones = Player.graduationPhase >= 1 and 7 or 4
    local droneCount = math.min(droneLevel, maxDrones)
    local angleStep = (math.pi * 2) / droneCount
    local r = Skill.droneVisualSize

    for i = 1, droneCount do
        local a = Skill.droneAngle + (i - 1) * angleStep
        local wx = playerX + math.cos(a) * Skill.droneOrbitRadius
        local wy = playerY + math.sin(a) * Skill.droneOrbitRadius
        local sx = wx - camX
        local sy = wy - camY

        -- ── 拖尾（稀疏 + 低透明度） ──
        local trail = droneTrails[i]
        if trail then
            for j = 1, TRAIL_MAX do
                -- 从最旧到最新遍历
                local idx = ((trailHead - 1 + j - 1) % TRAIL_MAX) + 1
                local pt = trail[idx]
                if pt then
                    local t = j / TRAIL_MAX  -- 0→旧, 1→新
                    local alpha = math.floor(t * 70)
                    local trailR = r * (0.2 + 0.4 * t)
                    local tx = pt.x - camX
                    local ty = pt.y - camY
                    nvgBeginPath(vg)
                    nvgCircle(vg, tx, ty, trailR)
                    nvgFillColor(vg, nvgRGBA(0, 220, 255, alpha))
                    nvgFill(vg)
                end
            end
        end

        -- ── 无人机本体光晕 ──
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, r + 6)
        nvgFillColor(vg, nvgRGBA(0, 200, 255, 35))
        nvgFill(vg)

        -- ── 无人机本体 ──
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, r)
        nvgFillColor(vg, nvgRGBA(0, 220, 255, 230))
        nvgFill(vg)

        -- 内核高亮
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, r * 0.45)
        nvgFillColor(vg, nvgRGBA(200, 240, 255, 255))
        nvgFill(vg)
    end
end

--- 渲染绿色无人机
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
---@param playerX number 玩家世界X
---@param playerY number 玩家世界Y
---@param greenDroneLevel number 绿色无人机等级
function Skill.RenderGreenDrone(vg, camX, camY, playerX, playerY, greenDroneLevel)
    if greenDroneLevel <= 0 then return end

    local droneCount = greenDroneLevel
    local angleStep = (math.pi * 2) / droneCount
    local r = Skill.droneVisualSize

    for i = 1, droneCount do
        local a = Skill.greenDroneAngle + (i - 1) * angleStep
        local wx = playerX + math.cos(a) * Skill.greenDroneOrbitRadius
        local wy = playerY + math.sin(a) * Skill.greenDroneOrbitRadius
        local sx = wx - camX
        local sy = wy - camY

        -- ── 拖尾（稀疏 + 低透明度） ──
        local trail = greenDroneTrails[i]
        if trail then
            for j = 1, TRAIL_MAX do
                local idx = ((greenTrailHead - 1 + j - 1) % TRAIL_MAX) + 1
                local pt = trail[idx]
                if pt then
                    local t = j / TRAIL_MAX
                    local alpha = math.floor(t * 70)
                    local trailR = r * (0.2 + 0.4 * t)
                    local tx = pt.x - camX
                    local ty = pt.y - camY
                    nvgBeginPath(vg)
                    nvgCircle(vg, tx, ty, trailR)
                    nvgFillColor(vg, nvgRGBA(50, 255, 80, alpha))
                    nvgFill(vg)
                end
            end
        end

        -- ── 光晕 ──
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, r + 6)
        nvgFillColor(vg, nvgRGBA(50, 200, 80, 35))
        nvgFill(vg)

        -- ── 绿色无人机本体 ──
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, r)
        nvgFillColor(vg, nvgRGBA(50, 220, 80, 230))
        nvgFill(vg)

        -- 内核高亮
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, r * 0.45)
        nvgFillColor(vg, nvgRGBA(200, 255, 210, 255))
        nvgFill(vg)
    end
end

--- 渲染分身（猴子分身）
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
---@param cloneEmoji string 分身使用的 emoji
function Skill.RenderClones(vg, camX, camY, cloneEmoji)
    if #clones == 0 then return end

    for _, c in ipairs(clones) do
        local sx = c.x - camX
        local sy = c.y - camY

        -- 半透明光晕
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, 18)
        nvgFillColor(vg, nvgRGBA(255, 140, 50, 40))
        nvgFill(vg)

        -- 半透明 emoji 分身
        nvgGlobalAlpha(vg, 0.6)
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, sx, sy, cloneEmoji)
        nvgGlobalAlpha(vg, 1.0)
    end
end

--- 渲染豆芽陷阱
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
function Skill.RenderBeanTraps(vg, camX, camY)
    for _, trap in ipairs(beanTraps) do
        local sx = trap.x - camX
        local sy = trap.y - camY

        if trap.triggered then
            -- 爆炸效果（渐消）
            local alpha = math.floor(200 * (trap.life / 0.3))
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, trap.radius * (1 - trap.life / 0.3) * 0.5 + 10)
            nvgFillColor(vg, nvgRGBA(100, 220, 50, math.max(0, alpha)))
            nvgFill(vg)
        else
            -- 陷阱范围圈（半透明）
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, BEAN_TRAP_TRIGGER_R)
            nvgFillColor(vg, nvgRGBA(100, 220, 50, 20))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(100, 220, 50, 60))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 豆芽 emoji
            local pulse = 0.9 + 0.1 * math.sin(trap.life * 4)
            nvgFontSize(vg, 22 * pulse)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, sx, sy, "🌱")
        end
    end
end

--- 渲染飞行中的手雷
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
function Skill.RenderGrenades(vg, camX, camY)
    for _, g in ipairs(flyingGrenades) do
        local sx = g.x - camX
        local sy = g.y - camY

        -- 手雷阴影
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, sy + 10, 8, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
        nvgFill(vg)

        -- 尾焰拖尾（外层）
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, 7)
        nvgFillColor(vg, nvgRGBA(255, 120, 20, 80))
        nvgFill(vg)
        -- 尾焰拖尾（内层）
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, 4)
        nvgFillColor(vg, nvgRGBA(255, 220, 60, 150))
        nvgFill(vg)

        -- 旋转的手雷 emoji
        nvgSave(vg)
        nvgTranslate(vg, sx, sy)
        nvgRotate(vg, g.rotation)
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, 0, 0, "💣")
        nvgRestore(vg)
    end
end

--- 渲染太极拳掌风波
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
function Skill.RenderGrabSmashes(vg, camX, camY)
    local now = time.elapsedTime
    for _, w in ipairs(taichiWaves) do
        local sx = w.x - camX
        local sy = w.y - camY
        local visualR = 14 * w.scale

        -- 外层气场光晕（半透明白蓝渐变）
        local fadeAlpha = math.floor(math.min(1, w.lifetime / 0.3) * 60)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, visualR + 8)
        nvgFillColor(vg, nvgRGBA(200, 220, 255, fadeAlpha))
        nvgFill(vg)

        -- 核心掌风波圆（白色偏蓝）
        local coreAlpha = math.floor(math.min(1, w.lifetime / 0.3) * 180)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, visualR)
        nvgFillColor(vg, nvgRGBA(230, 240, 255, coreAlpha))
        nvgFill(vg)

        -- 旋转的☯️ emoji
        nvgSave(vg)
        nvgTranslate(vg, sx, sy)
        nvgRotate(vg, (now - w.spawnTime) * 6)
        local emojiSize = math.min(visualR * 2.5, 80)
        nvgFontSize(vg, emojiSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgGlobalAlpha(vg, math.min(1, w.lifetime / 0.3))
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, 0, 0, "🫴")
        nvgRestore(vg)
        nvgGlobalAlpha(vg, 1.0)

        -- 边缘弧线装饰（太极风格）
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, visualR + 2)
        nvgStrokeColor(vg, nvgRGBA(180, 200, 255, math.floor(fadeAlpha * 1.5)))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end
end

--- 渲染圣诞树环绕副武器
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
---@param playerX number 玩家世界X
---@param playerY number 玩家世界Y
---@param xmasTreeLevel number 等级
function Skill.RenderXmasTree(vg, camX, camY, playerX, playerY, xmasTreeLevel)
    if xmasTreeLevel <= 0 then return end

    local skillDef = Config.FindSkill("xmas_tree")
    local eff = skillDef.effect
    local treeCount = xmasTreeLevel
    local orbitR = eff.orbitRadius + 10 * xmasTreeLevel
    local angleStep = (math.pi * 2) / treeCount

    -- 环绕轨道线
    nvgBeginPath(vg)
    nvgCircle(vg, playerX - camX, playerY - camY, orbitR)
    nvgStrokeColor(vg, nvgRGBA(60, 180, 80, 30))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    for ti = 1, treeCount do
        local treeAngle = Skill.xmasTreeAngle + (ti - 1) * angleStep
        local treeX = playerX + math.cos(treeAngle) * orbitR
        local treeY = playerY + math.sin(treeAngle) * orbitR
        local sx = treeX - camX
        local sy = treeY - camY

        -- 圣诞树光晕
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, 22 + 3 * xmasTreeLevel)
        nvgFillColor(vg, nvgRGBA(60, 200, 80, 35))
        nvgFill(vg)

        -- 圣诞树 emoji
        nvgSave(vg)
        nvgTranslate(vg, sx, sy)
        nvgRotate(vg, treeAngle + math.pi / 2)
        nvgFontSize(vg, 36 + 4 * xmasTreeLevel)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, 0, 0, "🎄")
        nvgRestore(vg)
    end
end

--- 渲染霜瑟风暴范围指示
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
---@param playerX number 玩家世界X
---@param playerY number 玩家世界Y
---@param leafStormLevel number 等级
function Skill.RenderLeafStorm(vg, camX, camY, playerX, playerY, leafStormLevel)
    if leafStormLevel <= 0 then return end

    local skillDef = Config.FindSkill("leaf_storm")
    local eff = skillDef.effect
    local radius = eff.radius + 15 * leafStormLevel

    local sx = playerX - camX
    local sy = playerY - camY

    -- 常驻半透明冰霜范围圈（低调、不闪烁）
    nvgBeginPath(vg)
    nvgCircle(vg, sx, sy, radius)
    nvgFillColor(vg, nvgRGBA(80, 180, 255, 18))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 35))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 外圈飘散小粒子（轻柔漂浮的冰晶碎片）
    local particleCount = 6 + leafStormLevel * 2
    for i = 1, particleCount do
        local baseA = (i / particleCount) * math.pi * 2
        -- 缓慢公转 + 径向浮动
        local a = baseA + Skill.leafStormAngle * 0.6
        local radialOffset = math.sin(Skill.leafStormAngle * 1.2 + i * 1.7) * 12
        local pr = radius - 5 + radialOffset
        local px = sx + math.cos(a) * pr
        local py = sy + math.sin(a) * pr
        local pAlpha = 60 + math.floor(math.sin(a * 1.5 + Skill.leafStormAngle) * 30)
        local pSize = 2.0 + math.sin(i * 0.9 + Skill.leafStormAngle * 0.8) * 1.0
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, pSize)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, pAlpha))
        nvgFill(vg)
    end

    -- 内圈少量冰晶 emoji（低调旋转）
    local frostEmojis = { "❄️", "❄️", "💎" }
    local emojiCount = 3
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for i = 1, emojiCount do
        local a = Skill.leafStormAngle * 0.8 + (i / emojiCount) * math.pi * 2
        local lr = radius * 0.55
        local lx = sx + math.cos(a) * lr
        local ly = sy + math.sin(a) * lr
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 80))
        nvgText(vg, lx, ly, frostEmojis[(i - 1) % #frostEmojis + 1])
    end

    -- 触发闪光（极淡，几乎不可见）
    if Skill.leafStormFlash > 0 then
        local flashAlpha = math.floor((Skill.leafStormFlash / 0.15) * 25)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, radius)
        nvgFillColor(vg, nvgRGBA(180, 230, 255, flashAlpha))
        nvgFill(vg)
    end
end

--- 渲染星爆猫爪（半透明五角星 + 触发闪光）
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
---@param playerX number 玩家世界X
---@param playerY number 玩家世界Y
---@param catScratchLevel number 等级
function Skill.RenderCatScratch(vg, camX, camY, playerX, playerY, catScratchLevel)
    if catScratchLevel <= 0 then return end

    local sx = playerX - camX
    local sy = playerY - camY
    local outerR = (120 + 20 * catScratchLevel) * 2  -- 范围200%
    local innerR = outerR * 0.382
    local interval = 3.0 / catScratchLevel
    local ratio = Skill.catScratchTimer / interval

    -- ① 常驻半透明五角星范围（缓慢旋转，随CD脉冲）
    local baseAlpha = 12 + math.floor(ratio * 18)  -- 越接近触发越亮（降低透明度）
    nvgSave(vg)
    nvgBeginPath(vg)
    for i = 1, 10 do
        local a = catScratchAngle + (i - 1) * (math.pi / 5) - math.pi / 2
        local r = (i % 2 == 1) and outerR or innerR
        local vx = sx + math.cos(a) * r
        local vy = sy + math.sin(a) * r
        if i == 1 then
            nvgMoveTo(vg, vx, vy)
        else
            nvgLineTo(vg, vx, vy)
        end
    end
    nvgClosePath(vg)

    -- 半透明金色填充（降低透明度）
    nvgFillColor(vg, nvgRGBA(255, 220, 50, baseAlpha))
    nvgFill(vg)

    -- 边框（越接近触发越亮，降低透明度）
    local strokeAlpha = 20 + math.floor(ratio * 50)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 50, strokeAlpha))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
    nvgRestore(vg)

    -- ② 触发瞬间闪光（白色高亮五角星快速消退）
    if Skill.catStarFlash > 0 and Skill.catStarVerts then
        local flashAlpha = math.floor((Skill.catStarFlash / 0.35) * 100)
        nvgSave(vg)
        nvgBeginPath(vg)
        for i, v in ipairs(Skill.catStarVerts) do
            local fvx = v.x - camX
            local fvy = v.y - camY
            if i == 1 then
                nvgMoveTo(vg, fvx, fvy)
            else
                nvgLineTo(vg, fvx, fvy)
            end
        end
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, flashAlpha))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 240, 100, math.min(255, flashAlpha + 40)))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
        nvgRestore(vg)
    end

    -- ③ 中心旋转⭐emoji
    nvgSave(vg)
    nvgFontSize(vg, 22 + catScratchLevel * 4)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgGlobalAlpha(vg, 0.6)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, sx, sy - outerR * 0.15, "⭐")
    nvgRestore(vg)
end

--- ======== OTTO 专属渲染函数 ========

--- 召唤大象的外部接口（供 Projectile 射击时调用）
---@param x number 召唤位置X
---@param y number 召唤位置Y
---@param level number 技能等级（最大大象数）
function Skill.TrySpawnElephant(x, y, level)
    if level <= 0 then return end
    if #elephants >= level then return end  -- 已达上限
    if math.random() < 0.02 then  -- 2%概率
        table.insert(elephants, {
            x = x,
            y = y,
            life = 10.0,
            targetEnemy = nil,
        })
        Particle.SpawnShockWave(x, y, 30, 0.2, 180, 140, 100, 2)
    end
end

--- 检查敌人是否被魅惑（供 Projectile/Enemy 模块调用）
---@param enemy table 敌人对象
---@return boolean
function Skill.IsCharmed(enemy)
    return enemy.charmed == true
end

--- 获取魅惑敌人列表（供渲染等外部使用）
---@return table
function Skill.GetCharmedEnemies()
    return charmedEnemies
end

--- 获取大象列表（供 EnemyBullet 阻挡等外部使用）
---@return table
function Skill.GetElephants()
    return elephants
end

--- 渲染大象踩背
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
function Skill.RenderElephants(vg, camX, camY)
    if #elephants == 0 then return end

    for _, el in ipairs(elephants) do
        local sx = el.x - camX
        local sy = el.y - camY

        -- 大象阴影
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, sy + 12, 16, 6)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 30))
        nvgFill(vg)

        -- 大象光晕（踩踏时脉冲）
        local pulse = 1.0 + 0.15 * math.sin(time.elapsedTime * 6)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, 22 * pulse)
        nvgFillColor(vg, nvgRGBA(180, 140, 100, 30))
        nvgFill(vg)

        -- 大象 emoji
        nvgFontSize(vg, 38)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, sx, sy - 2, "\xF0\x9F\x90\x98")

        -- 生命条
        local lifeRatio = el.life / 10.0
        local barW = 24
        local barH = 3
        nvgBeginPath(vg)
        nvgRect(vg, sx - barW / 2, sy + 16, barW, barH)
        nvgFillColor(vg, nvgRGBA(40, 40, 40, 120))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, sx - barW / 2, sy + 16, barW * lifeRatio, barH)
        nvgFillColor(vg, nvgRGBA(180, 140, 100, 200))
        nvgFill(vg)
    end
end

--- 渲染魅惑敌人标识
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
function Skill.RenderCharmedIndicators(vg, camX, camY)
    if #charmedEnemies == 0 then return end

    for _, ce in ipairs(charmedEnemies) do
        if ce.alive then
            local sx = ce.x - camX
            local sy = ce.y - camY

            -- 粉色爱心光圈
            local pulse = 0.8 + 0.2 * math.sin(time.elapsedTime * 4)
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, (ce.radius or 15) + 8)
            nvgStrokeColor(vg, nvgRGBA(255, 100, 200, math.floor(120 * pulse)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            -- 头顶爱心标识
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
            local floatY = math.sin(time.elapsedTime * 3) * 3
            nvgText(vg, sx, sy - (ce.radius or 15) - 12 + floatY, "\xE2\x9D\xA4")
        end
    end
end

--- 渲染马匹子弹和旋风
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
function Skill.RenderHorseAndWhirlwinds(vg, camX, camY)
    -- 渲染飞行中的马匹子弹
    for _, hp in ipairs(horseProjectiles) do
        local sx = hp.x - camX
        local sy = hp.y - camY

        -- 马匹拖尾
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, 8)
        nvgFillColor(vg, nvgRGBA(160, 120, 80, 60))
        nvgFill(vg)

        -- 马匹 emoji
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, sx, sy, "\xF0\x9F\x90\x8E")
    end

    -- 渲染旋风
    for _, ww in ipairs(horseWhirlwinds) do
        local sx = ww.x - camX
        local sy = ww.y - camY
        local whirlRadius = 60

        -- 旋风范围圈（半透明）
        local fadeAlpha = math.floor(math.min(1, ww.life / 1.0) * 40)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, whirlRadius)
        nvgFillColor(vg, nvgRGBA(120, 200, 120, fadeAlpha))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(120, 200, 120, fadeAlpha + 30))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 旋转的风粒子
        local particleCount = 6
        for i = 1, particleCount do
            local a = time.elapsedTime * 4 + (i / particleCount) * math.pi * 2
            local pr = whirlRadius * 0.6
            local px = sx + math.cos(a) * pr
            local py = sy + math.sin(a) * pr
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, 3)
            nvgFillColor(vg, nvgRGBA(160, 220, 160, 120))
            nvgFill(vg)
        end

        -- 中心旋风 emoji
        nvgSave(vg)
        nvgTranslate(vg, sx, sy)
        nvgRotate(vg, time.elapsedTime * 5)
        nvgFontSize(vg, 24)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(math.min(1, ww.life / 0.5) * 255)))
        nvgText(vg, 0, 0, "\xF0\x9F\x8C\x80")
        nvgRestore(vg)
    end
end

--- 渲染盒子
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
function Skill.RenderOttoBoxes(vg, camX, camY)
    if #ottoBoxes == 0 then return end

    for bi, box in ipairs(ottoBoxes) do
        local sx = box.x - camX
        local sy = box.y - camY

        -- 动画参数
        local animScale = 1.0
        local animAlpha = 255
        local animOffsetY = 0

        local spawnAge = box.spawnAge or 1.0
        if spawnAge < 0.4 then
            -- 放置动画：弹跳缩放 + 从上方落下
            local t = spawnAge / 0.4  -- 0→1
            -- 弹性缩放：overshoot 后回弹
            if t < 0.5 then
                animScale = t * 2 * 1.3  -- 0→1.3
            else
                animScale = 1.3 - (t - 0.5) * 2 * 0.3  -- 1.3→1.0
            end
            animOffsetY = -(1 - t) * 20  -- 从上方20px落下
            animAlpha = math.floor(255 * math.min(1, t * 2))
        end

        if box.removing then
            -- 拆除动画：缩小 + 向上飘走 + 淡出
            local rt = (box.removeAge or 0) / 0.3  -- 0→1
            if rt > 1 then rt = 1 end
            animScale = 1.0 - rt * 0.8  -- 1.0→0.2
            animOffsetY = -rt * 25       -- 向上飘25px
            animAlpha = math.floor(255 * (1 - rt))
        end

        -- 盒子阴影（随动画缩放）
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, sy + 10 + animOffsetY * 0.3, 12 * animScale, 5 * animScale)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(30 * animAlpha / 255)))
        nvgFill(vg)

        -- 盒子光晕（存在一段时间后脉冲）
        local mimicPulse = 1.0
        if box.spawnAge > 1.6 then
            mimicPulse = 1.0 + 0.2 * math.sin((box.spawnAge - 1.6) * 15)
        end
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy + animOffsetY, 16 * mimicPulse * animScale)
        nvgFillColor(vg, nvgRGBA(200, 160, 80, math.floor(25 * animAlpha / 255)))
        nvgFill(vg)

        -- 盒子 emoji（带缩放动画）
        nvgSave(vg)
        nvgTranslate(vg, sx, sy - 2 + animOffsetY)
        nvgScale(vg, animScale, animScale)
        nvgFontSize(vg, 30)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, animAlpha))
        nvgText(vg, 0, 0, "\xF0\x9F\x93\xA6")
        nvgRestore(vg)

        -- 僚机渲染（与攻击位置完全一致，仅在非拆除状态且放置动画完成后显示）
        if not box.removing and (box.spawnAge or 0) >= 0.4 then
            local skills = Player.skills

            -- ======== 渲染 Drone 僚机（与主机 Skill.Render 完全一致）========
            local droneLvR = skills["atk_drone"] or 0
            if droneLvR > 0 then
                local maxDrones = Player.graduationPhase >= 1 and 7 or 4
                local droneCount = math.min(droneLvR, maxDrones)
                local droneAngleStep = (math.pi * 2) / droneCount
                local r = Skill.droneVisualSize

                for i = 1, droneCount do
                    local a = (box.droneAngle or 0) + (i - 1) * droneAngleStep
                    local wx = box.x + math.cos(a) * Skill.droneOrbitRadius
                    local wy = box.y + math.sin(a) * Skill.droneOrbitRadius
                    local drSx = wx - camX
                    local drSy = wy - camY

                    -- 拖尾（与主机完全一致）
                    local trail = box.droneTrails and box.droneTrails[i]
                    if trail then
                        local head = box.droneTrailHead or 0
                        for j = 1, TRAIL_MAX do
                            local idx = ((head - 1 + j - 1) % TRAIL_MAX) + 1
                            local pt = trail[idx]
                            if pt then
                                local t = j / TRAIL_MAX
                                local alpha = math.floor(t * 120)
                                local trailR = r * (0.3 + 0.5 * t)
                                local ptx = pt.x - camX
                                local pty = pt.y - camY
                                nvgBeginPath(vg)
                                nvgCircle(vg, ptx, pty, trailR)
                                nvgFillColor(vg, nvgRGBA(0, 220, 255, alpha))
                                nvgFill(vg)
                            end
                        end
                    end

                    -- 外层光晕（与主机一致：r+6, alpha 35）
                    nvgBeginPath(vg)
                    nvgCircle(vg, drSx, drSy, r + 6)
                    nvgFillColor(vg, nvgRGBA(0, 200, 255, 35))
                    nvgFill(vg)
                    -- 主体（与主机一致：alpha 230）
                    nvgBeginPath(vg)
                    nvgCircle(vg, drSx, drSy, r)
                    nvgFillColor(vg, nvgRGBA(0, 220, 255, 230))
                    nvgFill(vg)
                    -- 内核（与主机一致：alpha 255）
                    nvgBeginPath(vg)
                    nvgCircle(vg, drSx, drSy, r * 0.45)
                    nvgFillColor(vg, nvgRGBA(200, 240, 255, 255))
                    nvgFill(vg)
                end
            end

            -- ======== 渲染 Clone 僚机（与主机 Skill.RenderClones 完全一致）========
            local cloneLvR = skills["clone_strike"] or 0
            if cloneLvR > 0 and box.clones then
                local cloneE = (Player.charDef and Player.charDef.playerEmoji and Player.charDef.playerEmoji.idle) or "🐵"
                for _, c in ipairs(box.clones) do
                    local cx = c.x - camX
                    local cy = c.y - camY
                    -- 光晕（与主机一致：半径 18, alpha 40）
                    nvgBeginPath(vg)
                    nvgCircle(vg, cx, cy, 18)
                    nvgFillColor(vg, nvgRGBA(255, 140, 50, 40))
                    nvgFill(vg)
                    -- 半透明角色 emoji（与主机一致：alpha 0.6, 字号 32）
                    nvgGlobalAlpha(vg, 0.6)
                    nvgFontSize(vg, 32)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, cx, cy, cloneE)
                    nvgGlobalAlpha(vg, 1.0)
                end
            end

            -- ======== 渲染 Xmas 僚机（与主机 Skill.RenderXmasTree 完全一致）========
            local xmasLvR = skills["xmas_tree"] or 0
            if xmasLvR > 0 then
                local xmasSkillDef = Config.FindSkill("xmas_tree")
                local xmasEff = xmasSkillDef.effect
                local treeCount = xmasLvR
                local xmasOrbitR = xmasEff.orbitRadius + 10 * xmasLvR
                local xmasAngleStep = (math.pi * 2) / treeCount

                -- 环绕轨道线（与主机一致）
                nvgBeginPath(vg)
                nvgCircle(vg, box.x - camX, box.y - camY, xmasOrbitR)
                nvgStrokeColor(vg, nvgRGBA(60, 180, 80, 30))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                local fontSize = 36 + 4 * xmasLvR
                for ti = 1, treeCount do
                    local treeAngle = (box.xmasAngle or 0) + (ti - 1) * xmasAngleStep
                    local wx = box.x + math.cos(treeAngle) * xmasOrbitR
                    local wy = box.y + math.sin(treeAngle) * xmasOrbitR
                    local tx = wx - camX
                    local ty = wy - camY

                    -- 光晕（与主机一致：22+3*level, alpha 35）
                    nvgBeginPath(vg)
                    nvgCircle(vg, tx, ty, 22 + 3 * xmasLvR)
                    nvgFillColor(vg, nvgRGBA(60, 200, 80, 35))
                    nvgFill(vg)

                    -- 圣诞树 emoji（与主机一致：旋转）
                    nvgSave(vg)
                    nvgTranslate(vg, tx, ty)
                    nvgRotate(vg, treeAngle + math.pi / 2)
                    nvgFontSize(vg, fontSize)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, 0, 0, "🎄")
                    nvgRestore(vg)
                end
            end

            -- ======== 渲染 Green Drone 僚机（与主机 Skill.RenderGreenDrone 完全一致）========
            local greenDroneLvR = skills["atk_drone_green"] or 0
            if greenDroneLvR > 0 then
                local greenDroneCount = greenDroneLvR
                local gAngleStep = (math.pi * 2) / greenDroneCount
                local r = Skill.droneVisualSize
                local greenOrbitR = Skill.greenDroneOrbitRadius

                for i = 1, greenDroneCount do
                    local a = (box.greenDroneAngle or 0) + (i - 1) * gAngleStep
                    local wx = box.x + math.cos(a) * greenOrbitR
                    local wy = box.y + math.sin(a) * greenOrbitR
                    local drSx = wx - camX
                    local drSy = wy - camY

                    -- 拖尾（绿色）
                    local trail = box.greenDroneTrails and box.greenDroneTrails[i]
                    if trail then
                        local head = box.greenDroneTrailHead or 0
                        for j = 1, TRAIL_MAX do
                            local idx = ((head - 1 + j - 1) % TRAIL_MAX) + 1
                            local pt = trail[idx]
                            if pt then
                                local t = j / TRAIL_MAX
                                local alpha = math.floor(t * 120)
                                local trailR = r * (0.3 + 0.5 * t)
                                local ptx = pt.x - camX
                                local pty = pt.y - camY
                                nvgBeginPath(vg)
                                nvgCircle(vg, ptx, pty, trailR)
                                nvgFillColor(vg, nvgRGBA(50, 255, 80, alpha))
                                nvgFill(vg)
                            end
                        end
                    end

                    -- 外层光晕（绿色）
                    nvgBeginPath(vg)
                    nvgCircle(vg, drSx, drSy, r + 6)
                    nvgFillColor(vg, nvgRGBA(50, 200, 80, 35))
                    nvgFill(vg)
                    -- 主体（绿色）
                    nvgBeginPath(vg)
                    nvgCircle(vg, drSx, drSy, r)
                    nvgFillColor(vg, nvgRGBA(50, 220, 80, 230))
                    nvgFill(vg)
                    -- 内核（绿色高亮）
                    nvgBeginPath(vg)
                    nvgCircle(vg, drSx, drSy, r * 0.45)
                    nvgFillColor(vg, nvgRGBA(200, 255, 210, 255))
                    nvgFill(vg)
                end
            end
        end
    end
end

-- RenderSprint 已移除（otto_sprint 改为被动移速加成）

-- ============================================================================
-- 存档序列化/反序列化（运行时实体 + 全部计时器）
-- ============================================================================

--- 导出所有技能运行时状态（供 SaveData.SaveGame 调用）
---@return table
function Skill.ExportState()
    local state = {
        -- 全部计时器（含之前遗漏的）
        droneTimer = Skill.droneTimer,
        grenadeTimer = Skill.grenadeTimer,
        grabSmashTimer = Skill.grabSmashTimer,
        cloneTimer = Skill.cloneTimer,
        catScratchTimer = Skill.catScratchTimer,
        catScratchPending = Skill.catScratchPending,
        catScratchBurstTimer = Skill.catScratchBurstTimer,
        beanSproutTimer = Skill.beanSproutTimer,
        thumbUpTimer = Skill.thumbUpTimer,
        thumbUpPending = Skill.thumbUpPending,
        thumbUpBurstTimer = Skill.thumbUpBurstTimer,
        xmasTreeTimer = Skill.xmasTreeTimer,
        xmasTreeAngle = Skill.xmasTreeAngle,
        xmasTreeIceTimer = Skill.xmasTreeIceTimer,
        leafStormTimer = Skill.leafStormTimer,
        leafStormAngle = Skill.leafStormAngle,
        droneAngle = Skill.droneAngle,
        taichiChargesUsed = Skill.taichiChargesUsed,
        taichiCooldownTimer = Skill.taichiCooldownTimer,
        -- OTTO 专属
        elephantStompTimer = Skill.elephantStompTimer,
        charmTimer = Skill.charmTimer,
        charmDamageTimer = Skill.charmDamageTimer,
        slowRiderTimer = Skill.slowRiderTimer,
        ottoBoxPlaceTimer = Skill.ottoBoxPlaceTimer,
        -- 绿色无人机
        greenDroneAngle = Skill.greenDroneAngle,
        greenDroneTimer = Skill.greenDroneTimer,
    }

    -- 运行时实体：ottoBoxes（永久存在，高优先级）
    local boxData = {}
    for _, box in ipairs(ottoBoxes) do
        if not box.removing then
            boxData[#boxData + 1] = {
                x = box.x, y = box.y,
                droneAngle = box.droneAngle,
                cloneAngle = box.cloneAngle,
                xmasAngle = box.xmasAngle,
                greenDroneAngle = box.greenDroneAngle,
            }
        end
    end
    state.ottoBoxes = boxData

    -- 运行时实体：clones（持续跟随）
    local cloneData = {}
    for _, c in ipairs(clones) do
        cloneData[#cloneData + 1] = {
            x = c.x, y = c.y,
            attackTimer = c.attackTimer,
            mimicTimer = c.mimicTimer,
        }
    end
    state.clones = cloneData

    -- 运行时实体：beanTraps（8秒持续）
    local trapData = {}
    for _, t in ipairs(beanTraps) do
        trapData[#trapData + 1] = {
            x = t.x, y = t.y,
            life = t.life, radius = t.radius, dmg = t.dmg,
            triggered = t.triggered,
        }
    end
    state.beanTraps = trapData

    return state
end

--- 导入技能运行时状态（供 SaveData.ApplyToGame 调用）
---@param state table 由 ExportState 返回的数据
function Skill.ImportState(state)
    if not state then return end

    -- 全部计时器
    Skill.droneTimer = state.droneTimer or 0
    Skill.grenadeTimer = state.grenadeTimer or 0
    Skill.grabSmashTimer = state.grabSmashTimer or 0
    Skill.cloneTimer = state.cloneTimer or 0
    Skill.catScratchTimer = state.catScratchTimer or 0
    Skill.catScratchPending = state.catScratchPending or 0
    Skill.catScratchBurstTimer = state.catScratchBurstTimer or 0
    Skill.beanSproutTimer = state.beanSproutTimer or 0
    Skill.thumbUpTimer = state.thumbUpTimer or 0
    Skill.thumbUpPending = state.thumbUpPending or 0
    Skill.thumbUpBurstTimer = state.thumbUpBurstTimer or 0
    Skill.xmasTreeTimer = state.xmasTreeTimer or 0
    Skill.xmasTreeAngle = state.xmasTreeAngle or 0
    Skill.xmasTreeIceTimer = state.xmasTreeIceTimer or 0
    Skill.leafStormTimer = state.leafStormTimer or 0
    Skill.leafStormAngle = state.leafStormAngle or 0
    Skill.droneAngle = state.droneAngle or 0
    Skill.taichiChargesUsed = state.taichiChargesUsed or 0
    Skill.taichiCooldownTimer = state.taichiCooldownTimer or 0
    -- OTTO 专属
    Skill.elephantStompTimer = state.elephantStompTimer or 0
    Skill.charmTimer = state.charmTimer or 0
    Skill.charmDamageTimer = state.charmDamageTimer or 0
    Skill.slowRiderTimer = state.slowRiderTimer or 0
    Skill.ottoBoxPlaceTimer = state.ottoBoxPlaceTimer or 0
    -- 绿色无人机
    Skill.greenDroneAngle = state.greenDroneAngle or 0
    Skill.greenDroneTimer = state.greenDroneTimer or 0

    -- 运行时实体：ottoBoxes
    if state.ottoBoxes then
        ottoBoxes = {}
        for _, bd in ipairs(state.ottoBoxes) do
            ottoBoxes[#ottoBoxes + 1] = {
                x = bd.x, y = bd.y,
                spawnAge = 1.0,  -- 跳过放置动画
                removing = false, removeAge = 0,
                droneTimer = 0,
                droneAngle = bd.droneAngle or 0,
                droneCollisionTimer = 0,
                droneTrails = {}, droneTrailHead = 0, droneTrailTimer = 0,
                clones = {},
                cloneAngle = bd.cloneAngle or 0,
                xmasAngle = bd.xmasAngle or 0,
                xmasHitMap = {}, xmasIceTimer = 0, xmasIceIndex = 0,
                greenDroneAngle = bd.greenDroneAngle or 0,
                greenDroneTimer = 0, greenDroneCollisionTimer = 0,
                greenDroneTrails = {}, greenDroneTrailHead = 0, greenDroneTrailTimer = 0,
            }
        end
    end

    -- 运行时实体：clones
    if state.clones then
        clones = {}
        for _, cd in ipairs(state.clones) do
            clones[#clones + 1] = {
                x = cd.x, y = cd.y,
                attackTimer = cd.attackTimer or 0,
                mimicTimer = cd.mimicTimer or 0,
            }
        end
    end

    -- 运行时实体：beanTraps
    if state.beanTraps then
        beanTraps = {}
        for _, td in ipairs(state.beanTraps) do
            beanTraps[#beanTraps + 1] = {
                x = td.x, y = td.y,
                life = td.life or 0,
                radius = td.radius or 120,
                dmg = td.dmg or 0,
                triggered = td.triggered or false,
            }
        end
    end
end

return Skill
