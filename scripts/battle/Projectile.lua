--- ============================================================================
--- 子弹模块 - 对象池、碰撞检测
--- ============================================================================

local Config = require("Config")
local Player = require("battle.Player")
local DamageNumber = require("ui.DamageNumber")
local Particle = require("fx.Particle")
local Enemy = require("battle.Enemy")
local SM = require("utils.SafeMath")
local RuneEffects = require("battle.RuneEffects")
local Glow = require("fx.Glow")
local SpatialHash = require("utils.SpatialHash")
local PerfQuality = require("utils.PerfQuality")

local Projectile = {}

-- 空间哈希实例（持久化复用，避免每帧 New 造成 GC 压力）
---@type table|nil
Projectile.spatialHash = nil
local _persistentHash = nil  -- 持久化空间哈希（复用）

Projectile.pool = {}
Projectile.active = {}

-- 拖尾配置（基准值，会根据 extraBullets 动态缩减）
local TRAIL_MAX_BASE = 8           -- 基准最大段数
local TRAIL_INTERVAL_BASE = 0.015  -- 基准记录间隔（秒）

--- 根据当前额外子弹数动态计算拖尾参数
--- extraBullets 越多 → 段数越少、间隔越大（总长度更短）
local function GetTrailParams()
    local extra = Player.extraBullets or 0
    -- 每多1颗额外子弹：段数 -1（最低3），间隔 +0.006（总长度缩短）
    local trailMax = math.max(3, TRAIL_MAX_BASE - extra)
    local trailInterval = TRAIL_INTERVAL_BASE + extra * 0.006
    return trailMax, trailInterval
end

-- 默认子弹风格（兜底，不应被使用）
local DEFAULT_BULLET_STYLE = {
    normal   = { emoji = "🐾", color = { 0, 230, 200 },   trailColor = { 0, 230, 200 },   glowColor = { 0, 255, 220, 50 },  size = 1.0 },
    pierce   = { emoji = "⭐", color = { 200, 120, 255 }, trailColor = { 180, 80, 255 },  glowColor = { 200, 100, 255, 60 }, size = 1.15 },
    spread   = { emoji = "💫", color = { 255, 140, 200 }, trailColor = { 255, 100, 180 }, glowColor = { 255, 150, 200, 50 }, size = 0.9 },
    ricochet = { emoji = "🔹", color = { 0, 200, 255 },   trailColor = { 0, 180, 255 },   glowColor = { 0, 220, 255, 60 },  size = 1.1 },
}

--- 猴子毕业后爆米花子弹风格（缓存，避免每帧创建新表）
local monkeyGradBulletStyles = nil

--- 根据已解锁天赋随机选择子弹视觉风格
--- 从 "normal" + 已解锁的穿透/扩散/弹射 天赋对应风格中等概率随机选一种
local function RandomVisualStyle()
    local candidates = { "normal" }
    local skills = Player.skills
    -- 穿透类天赋 → pierce 风格
    if (skills["piercing"] or 0) > 0 or (skills["leaf_pierce"] or 0) > 0 then
        candidates[#candidates + 1] = "pierce"
    end
    -- 多重射击天赋 → spread 风格
    if (skills["multi_shot"] or 0) > 0 then
        candidates[#candidates + 1] = "spread"
    end
    -- 弹射天赋 → ricochet 风格
    if (skills["ricochet"] or 0) > 0 then
        candidates[#candidates + 1] = "ricochet"
    end
    return candidates[math.random(#candidates)]
end

--- 获取当前角色的子弹风格表
local function GetBulletStyles()
    if Player.charDef and Player.charDef.bulletStyle then
        -- 猴子毕业后子弹变成爆米花 🍿
        if Player.charId == "monkey" and Player.graduationPhase >= 1 then
            if not monkeyGradBulletStyles then
                monkeyGradBulletStyles = {}
                for k, v in pairs(Player.charDef.bulletStyle) do
                    monkeyGradBulletStyles[k] = {
                        emoji = "🍿",
                        color = v.color,
                        trailColor = v.trailColor,
                        glowColor = v.glowColor,
                        size = v.size,
                    }
                end
            end
            return monkeyGradBulletStyles
        end
        return Player.charDef.bulletStyle
    end
    return DEFAULT_BULLET_STYLE
end

local function GetFromPool()
    local p = table.remove(Projectile.pool)
    if p then return p end
    return {
        x = 0, y = 0,
        vx = 0, vy = 0,
        damage = 0,
        lifetime = 0,
        alive = false,
        pierceLeft = 0,
        bounceLeft = 0,
        hitEnemies = {},
        -- 拖尾用
        trail = {},        -- {{x,y}, {x,y}, ...}  最新在末尾
        trailTimer = 0,
        -- 视觉
        bulletType = "normal",  -- "normal" / "pierce" / "spread" / "ricochet"
        visualStyle = "normal", -- 随机视觉风格（从已解锁天赋中选）
        spawnTime = 0,          -- 用于旋转动画
        isBig = false,          -- 大子弹标记
        bigScale = 1.0,         -- 大子弹缩放倍数
        -- 追踪子弹
        isHoming = false,       -- 是否为追踪子弹
        homingTimer = 0,        -- 追踪延迟计时器（0.3s后开始追踪）
        -- 冰弹
        isIceBullet = false,    -- 是否为冰弹（无伤害，叠加冰冻层）
    }
end

local function Recycle(p)
    p.alive = false
    p.hitEnemies = {}
    p.bounceLeft = 0
    p.visualStyle = "normal"
    p.isBig = false
    p.bigScale = 1.0
    p.isHoming = false
    p.homingTimer = 0
    p.isIceBullet = false
    -- 重置环形拖尾
    p.trailHead = 0
    p.trailCount = 0
    p.trailTimer = 0
    table.insert(Projectile.pool, p)
end

function Projectile.Reset()
    for i = #Projectile.active, 1, -1 do
        Recycle(Projectile.active[i])
        table.remove(Projectile.active, i)
    end
    monkeyGradBulletStyles = nil  -- 重置毕业子弹风格缓存
end

--- 发射子弹
---@param bulletType string|nil "normal"/"pierce"/"spread"/"ricochet" 默认自动判定
function Projectile.Spawn(x, y, targetX, targetY, damage, pierceCount, bulletType, bounceCount)
    local dx = targetX - x
    local dy = targetY - y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return end

    local p = GetFromPool()
    p.x = x
    p.y = y
    p.vx = (dx / dist) * Config.BULLET.speed
    p.vy = (dy / dist) * Config.BULLET.speed
    p.damage = damage
    p.alive = true
    p.pierceLeft = pierceCount or 0
    p.bounceLeft = bounceCount or 0
    -- 弹射/穿透每级 +0.2s 存活时间
    p.lifetime = Config.BULLET.lifetime + (p.pierceLeft + p.bounceLeft) * 0.2
    p.hitEnemies = {}
    p.trailHead = 0
    p.trailCount = 0
    p.trailTimer = 0

    -- 子弹类型：手动指定 > 自动判定
    if bulletType then
        p.bulletType = bulletType
    elseif p.pierceLeft > 0 then
        p.bulletType = "pierce"
    elseif p.bounceLeft > 0 then
        p.bulletType = "ricochet"
    else
        p.bulletType = "normal"
    end
    -- 随机视觉风格：从已解锁天赋中等概率选一种
    p.visualStyle = RandomVisualStyle()
    p.spawnTime = time.elapsedTime

    -- 大子弹概率判定
    if Player.bigBulletChance > 0 and math.random() < Player.bigBulletChance then
        p.isBig = true
        p.bigScale = 3.5  -- 3.5倍大小
        p.damage = SM.mulFloor(p.damage, 3.0)  -- 3倍伤害
        p.pierceLeft = p.pierceLeft + 2  -- 额外穿透
    else
        p.isBig = false
        p.bigScale = 1.0
    end

    -- 追踪子弹概率判定（穿透后0.3s延迟追踪最近敌人）
    p.isHoming = false
    p.homingTimer = 0
    if Player.homingChance > 0 and p.pierceLeft > 0 and math.random() < Player.homingChance then
        p.isHoming = true
        p.homingTimer = 0.3  -- 0.3秒后开始追踪
    end

    p.isIceBullet = false

    table.insert(Projectile.active, p)
end

--- 发射扇形子弹（多重射击）
function Projectile.SpawnSpread(x, y, targetX, targetY, damage, pierceCount, extraCount, bounceCount)
    local dx = targetX - x
    local dy = targetY - y
    local baseAngle = math.atan(dy, dx)
    local spreadAngle = 0.15 -- 弧度

    -- 中间那发类型判定
    local centerType
    if pierceCount > 0 then centerType = "pierce"
    elseif (bounceCount or 0) > 0 then centerType = "ricochet"
    else centerType = "spread" end
    Projectile.Spawn(x, y, targetX, targetY, damage, pierceCount, centerType, bounceCount)

    -- 额外子弹（一律标记为 spread）
    for i = 1, extraCount do
        local offset = math.ceil(i / 2) * spreadAngle
        if i % 2 == 1 then offset = -offset end
        local angle = baseAngle + offset
        local tx = x + math.cos(angle) * 100
        local ty = y + math.sin(angle) * 100
        Projectile.Spawn(x, y, tx, ty, damage, pierceCount, "spread", bounceCount)
    end
end

--- 发射冰弹（无伤害，叠加冰冻层，支持玩家子弹加成）
---@param x number 起始X
---@param y number 起始Y
---@param targetX number 目标X
---@param targetY number 目标Y
---@param applyEnhancements boolean|nil 是否应用玩家子弹加成（追踪、弹射）
function Projectile.SpawnIceBullet(x, y, targetX, targetY, applyEnhancements)
    local dx = targetX - x
    local dy = targetY - y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return end

    local p = GetFromPool()
    p.x = x
    p.y = y
    p.vx = (dx / dist) * Config.BULLET.speed * 0.8  -- 冰弹稍慢
    p.vy = (dy / dist) * Config.BULLET.speed * 0.8
    p.damage = 0           -- 无伤害
    p.alive = true
    p.pierceLeft = 9999    -- 无限穿透
    p.hitEnemies = {}
    p.trailHead = 0
    p.trailCount = 0
    p.trailTimer = 0
    p.bulletType = "normal"
    p.spawnTime = time.elapsedTime
    p.isBig = false
    p.bigScale = 1.0
    p.isIceBullet = true   -- 标记为冰弹

    -- 应用玩家子弹加成
    if applyEnhancements then
        -- 追踪
        p.isHoming = Player.homingChance > 0 and math.random() < Player.homingChance
        p.homingTimer = p.isHoming and 0.3 or 0
        -- 弹射（冰弹弹射时改变方向继续冻结）
        p.bounceLeft = Player.bounceCount or 0
    else
        p.isHoming = false
        p.homingTimer = 0
        p.bounceLeft = 0
    end

    -- 冰弹存活时间：基础1.5s + 弹射每级+0.2s
    p.lifetime = 1.5 + p.bounceLeft * 0.2

    table.insert(Projectile.active, p)
end

--- 更新所有子弹
---@param enemies table Enemy.active 列表
---@return table 被击杀的敌人列表
function Projectile.Update(dt, enemies)
    local killed = {}

    -- 构建空间哈希（持久化复用，Clear + InsertAll 替代每帧 New）
    if not _persistentHash then
        _persistentHash = SpatialHash.New(200)
    end
    _persistentHash:Clear()
    _persistentHash:InsertAll(enemies)
    Projectile.spatialHash = _persistentHash
    local hash = _persistentHash
    -- 复用查询结果表，避免每次分配
    local _nearby = {}

    for i = #Projectile.active, 1, -1 do
        local p = Projectile.active[i]
        if not p.alive then
            table.remove(Projectile.active, i)
            Recycle(p)
        else
            -- 记录拖尾（移动前的位置，段数根据额外子弹动态缩减）
            if PerfQuality.TrailEnabled() then
                local trailMax, trailInterval = GetTrailParams()
                -- 性能档位 3（均衡）缩短拖尾长度
                trailMax = math.max(2, math.floor(trailMax * PerfQuality.TrailLenMult()))
                p.trailTimer = p.trailTimer + dt
                if p.trailTimer >= trailInterval then
                    p.trailTimer = p.trailTimer - trailInterval
                    -- 环形写入：复用 trail 槽位避免 GC 压力
                    local tHead = (p.trailHead or 0) % trailMax + 1
                    local entry = p.trail[tHead]
                    if entry then
                        entry[1] = p.x; entry[2] = p.y
                    else
                        p.trail[tHead] = { p.x, p.y }
                    end
                    p.trailHead = tHead
                    p.trailCount = math.min((p.trailCount or 0) + 1, trailMax)
                end
            else
                -- 拖尾禁用时重置环形缓冲
                p.trailHead = 0
                p.trailCount = 0
                p.trailTimer = 0
            end

            -- 移动
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.lifetime = p.lifetime - dt

            -- 追踪子弹逻辑：延迟后转向最近敌人（含冰弹）
            if p.isHoming then
                if p.homingTimer > 0 then
                    p.homingTimer = p.homingTimer - dt
                else
                    -- 寻找最近敌人并平滑转向（空间哈希加速）
                    local bestDist = 400 * 400
                    local bestE = nil
                    for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                    hash:QueryInto(p.x, p.y, 400, _nearby)
                    for ni = 1, #_nearby do
                        local e = _nearby[ni]
                        if e.alive and not p.hitEnemies[e] and not e.charmed then
                            local hdx = e.x - p.x
                            local hdy = e.y - p.y
                            local hd2 = hdx * hdx + hdy * hdy
                            if hd2 < bestDist then
                                bestDist = hd2
                                bestE = e
                            end
                        end
                    end
                    if bestE then
                        local hdx = bestE.x - p.x
                        local hdy = bestE.y - p.y
                        local hdist = math.sqrt(hdx * hdx + hdy * hdy)
                        if hdist > 1 then
                            -- 目标方向
                            local targetVx = (hdx / hdist) * Config.BULLET.speed
                            local targetVy = (hdy / hdist) * Config.BULLET.speed
                            -- 平滑转向（lerp系数越大转向越快）
                            local turnRate = 8.0 * dt
                            p.vx = p.vx + (targetVx - p.vx) * turnRate
                            p.vy = p.vy + (targetVy - p.vy) * turnRate
                            -- 保持速度恒定
                            local spd = math.sqrt(p.vx * p.vx + p.vy * p.vy)
                            if spd > 1 then
                                p.vx = (p.vx / spd) * Config.BULLET.speed
                                p.vy = (p.vy / spd) * Config.BULLET.speed
                            end
                        end
                    end
                end
            end

            -- 超时销毁
            if p.lifetime <= 0 then
                p.alive = false
            else
                -- 碰撞检测（空间哈希加速）
                local bulletR = Config.BULLET.radius * p.bigScale
                local searchR = bulletR + 60  -- 子弹半径 + 最大敌人半径余量
                for ni = #_nearby, 1, -1 do _nearby[ni] = nil end
                hash:QueryInto(p.x, p.y, searchR, _nearby)
                for ni = 1, #_nearby do
                    local e = _nearby[ni]
                    if e.alive and not e.charmed and not p.hitEnemies[e] then
                        local edx = p.x - e.x
                        local edy = p.y - e.y
                        local distSq = edx * edx + edy * edy
                        local radSum = bulletR + e.radius
                        if distSq <= radSum * radSum then
                            -- 命中
                            p.hitEnemies[e] = true

                            -- 冰弹：不造成伤害，叠加冰冻层
                            if p.isIceBullet then
                                Enemy.ApplyFreezeStack(e)
                                Particle.Spawn(e.x, e.y, "hit")
                                -- 冰弹无限穿透，不消耗pierceLeft，继续飞行
                            else
                                -- 普通子弹伤害逻辑
                                local dmg = p.damage
                                -- 巨弹附加敌人生命上限 0.2% 的伤害
                                if p.isBig and e.maxHp then
                                    dmg = dmg + SM.mulFloor(e.maxHp, 0.002)
                                end
                                -- 符文加成：完美主义（未受伤累积伤害加成）
                                local gentDmgBonus, gentExtraPierce, gentKnockback = RuneEffects.GetGentlemanBonuses()
                                if gentDmgBonus > 0 then
                                    dmg = SM.mulFloor(dmg, 1 + gentDmgBonus)
                                end
                                if gentExtraPierce > 0 and not p._gentPierceApplied then
                                    p.pierceLeft = p.pierceLeft + gentExtraPierce
                                    p._gentPierceApplied = true
                                end

                                local killed2, finalAmount, isFrozenHit = Enemy.Damage(e, dmg)
                                e.hitFlash = 0.1

                                -- 伤害跳字 + 命中粒子
                                local isCrit = p.damage > Player.atk * 1.2
                                DamageNumber.SpawnDamage(e.x, e.y - 10, finalAmount, isCrit, isFrozenHit)
                                if isCrit then
                                    Particle.Spawn(e.x, e.y, "crit_hit")
                                    -- 符文暴击触发
                                    RuneEffects.OnCrit(e.x, e.y)
                                else
                                    Particle.Spawn(e.x, e.y, "hit")
                                end
                                if killed2 then
                                    table.insert(killed, e)
                                elseif gentKnockback or (Player.knockbackChance > 0 and math.random() < Player.knockbackChance) then
                                    -- 击退效果：敌人以400速度反向移动0.2秒
                                    Enemy.ApplyKnockback(e, p.vx, p.vy)
                                    Particle.Spawn(e.x, e.y, "hit")
                                end
                                -- 弹射优先于穿透：先消耗弹射次数
                                if p.bounceLeft > 0 then
                                    p.bounceLeft = p.bounceLeft - 1
                                    local bestDist = 250 * 250  -- 弹射搜索半径 250px
                                    local bestTarget = nil
                                    for ni2 = #_nearby, 1, -1 do _nearby[ni2] = nil end
                                    hash:QueryInto(p.x, p.y, 250, _nearby)
                                    for bi = 1, #_nearby do
                                        local e2 = _nearby[bi]
                                        if e2.alive and e2 ~= e and not p.hitEnemies[e2] and not e2.charmed then
                                            local bdx = e2.x - p.x
                                            local bdy = e2.y - p.y
                                            local bd2 = bdx * bdx + bdy * bdy
                                            if bd2 < bestDist then
                                                bestDist = bd2
                                                bestTarget = e2
                                            end
                                        end
                                    end
                                    if bestTarget then
                                        -- 转向新目标
                                        local bdx = bestTarget.x - p.x
                                        local bdy = bestTarget.y - p.y
                                        local bdist = math.sqrt(bdx * bdx + bdy * bdy)
                                        if bdist > 1 then
                                            p.vx = (bdx / bdist) * Config.BULLET.speed
                                            p.vy = (bdy / bdist) * Config.BULLET.speed
                                        end
                                        p.lifetime = Config.BULLET.lifetime * 0.5  -- 弹射后缩短寿命
                                        -- 清空拖尾制造折线效果
                                        p.trailHead = 0; p.trailCount = 0
                                    else
                                        -- 找不到弹射目标，当作一次穿透（保持方向继续飞行）
                                        -- 弹射次数减一，不清空
                                    end
                                -- 弹射用完后再消耗穿透
                                elseif p.pierceLeft > 0 then
                                    p.pierceLeft = p.pierceLeft - 1
                                    -- 符文穿透触发：裂变弹头（穿透后分裂出额外子弹）
                                    local splits = RuneEffects.OnPierce(p.x, p.y, p.vx, p.vy, p.damage)
                                    if splits then
                                        for _, s in ipairs(splits) do
                                            local sp = GetFromPool()
                                            sp.x = p.x
                                            sp.y = p.y
                                            sp.vx = s.vx
                                            sp.vy = s.vy
                                            sp.damage = s.dmg
                                            sp.alive = true
                                            sp.pierceLeft = 0
                                            sp.bounceLeft = 0
                                            sp.lifetime = 0.8
                                            sp.hitEnemies = {}
                                            sp.trailHead = 0
                                            sp.trailCount = 0
                                            sp.trailTimer = 0
                                            sp.bulletType = "spread"
                                            sp.visualStyle = "pierce"
                                            sp.spawnTime = time.elapsedTime
                                            sp.isBig = false
                                            sp.bigScale = 1.0
                                            sp.isHoming = false
                                            sp.homingTimer = 0
                                            sp.isIceBullet = false
                                            table.insert(Projectile.active, sp)
                                        end
                                    end
                                else
                                    p.alive = false
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return killed
end

--- 渲染所有子弹（emoji + 类型专属拖尾）
function Projectile.Render(vg, camX, camY, viewW, viewH)
    local baseR = Config.BULLET.radius
    local now = time.elapsedTime

    for _, p in ipairs(Projectile.active) do
        if p.alive then
            local sx = p.x - camX
            local sy = p.y - camY
            if sx > -60 and sx < viewW + 60 and sy > -60 and sy < viewH + 60 then
                -- 冰弹单独渲染
                if p.isIceBullet then
                    local iceR = baseR * 1.2
                    local trail = p.trail
                    local trailLen = p.trailCount or 0
                    local trailMax = TRAIL_MAX_BASE  -- 冰弹用基准值
                    local trailHead = p.trailHead or 0

                    -- 冰弹拖尾（淡蓝色）- 环形缓冲区迭代
                    if trailLen >= 1 then
                        for ti = 1, trailLen do
                            local idx = ((trailHead - trailLen + ti - 1) % trailMax) + 1
                            local entry = trail[idx]
                            if not entry then break end
                            local nx, ny
                            if ti < trailLen then
                                local nIdx = ((trailHead - trailLen + ti) % trailMax) + 1
                                local nEntry = trail[nIdx]
                                if nEntry then
                                    nx = nEntry[1] - camX
                                    ny = nEntry[2] - camY
                                else
                                    nx = sx; ny = sy
                                end
                            else
                                nx = sx
                                ny = sy
                            end
                            local tx = entry[1] - camX
                            local ty = entry[2] - camY
                            local t = ti / (trailLen + 1)
                            local alpha = math.floor(20 + 100 * t)
                            local width = iceR * (0.5 + 1.5 * t)
                            nvgBeginPath(vg)
                            nvgMoveTo(vg, tx, ty)
                            nvgLineTo(vg, nx, ny)
                            nvgStrokeColor(vg, nvgRGBA(100, 200, 255, alpha))
                            nvgStrokeWidth(vg, width)
                            nvgLineCap(vg, NVG_ROUND)
                            nvgStroke(vg)
                        end
                    end

                    -- 冰弹光晕（蓝色脉冲）- Bloom 升级
                    local pulse = 0.7 + 0.3 * math.sin((now - p.spawnTime) * 10)
                    if Glow.enabled then
                        Glow.DrawCircleBloom255(vg, sx, sy, (iceR + 4) * pulse, 80, 180, 255, 50)
                    else
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy, (iceR + 4) * pulse)
                        nvgFillColor(vg, nvgRGBA(80, 180, 255, 50))
                        nvgFill(vg)
                    end

                    -- 冰弹 emoji（朝向移动方向）
                    nvgSave(vg)
                    nvgTranslate(vg, sx, sy)
                    nvgRotate(vg, math.atan(p.vy, p.vx) + math.pi * 0.5)
                    nvgFontSize(vg, iceR * 4)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, 0, 0, "❄️")
                    nvgRestore(vg)
                else
                -- 普通子弹渲染

                local styles = GetBulletStyles()
                local style = styles[p.visualStyle] or styles[p.bulletType] or styles.normal
                local tc = style.trailColor
                local gc = style.glowColor
                local r = baseR * style.size * p.bigScale
                local trail = p.trail
                local trailLen = p.trailCount or 0
                local trailMax, _ = GetTrailParams()
                trailMax = math.max(2, math.floor(trailMax * PerfQuality.TrailLenMult()))
                local trailHead = p.trailHead or 0

                -- =====================
                -- 拖尾（类型专属颜色）- 环形缓冲区迭代
                -- =====================
                if trailLen >= 1 then
                    for i = 1, trailLen do
                        local idx = ((trailHead - trailLen + i - 1) % trailMax) + 1
                        local entry = trail[idx]
                        if not entry then break end
                        local nx, ny
                        if i < trailLen then
                            local nIdx = ((trailHead - trailLen + i) % trailMax) + 1
                            local nEntry = trail[nIdx]
                            if nEntry then
                                nx = nEntry[1] - camX
                                ny = nEntry[2] - camY
                            else
                                nx = sx; ny = sy
                            end
                        else
                            nx = sx
                            ny = sy
                        end

                        local tx = entry[1] - camX
                        local ty = entry[2] - camY

                        local t = i / (trailLen + 1)
                        local alpha = math.floor(20 + 140 * t)
                        local width = r * (0.6 + 2.0 * t)

                        nvgBeginPath(vg)
                        nvgMoveTo(vg, tx, ty)
                        nvgLineTo(vg, nx, ny)
                        nvgStrokeColor(vg, nvgRGBA(tc[1], tc[2], tc[3], alpha))
                        nvgStrokeWidth(vg, width)
                        nvgLineCap(vg, NVG_ROUND)
                        nvgStroke(vg)
                    end

                    -- 尾端小粒子点（最旧位置画一个渐隐小圆）
                    if trailLen >= 3 then
                        local oldIdx = ((trailHead - trailLen) % trailMax) + 1
                        local oldEntry = trail[oldIdx]
                        if oldEntry then
                            local oldX = oldEntry[1] - camX
                            local oldY = oldEntry[2] - camY
                            nvgBeginPath(vg)
                            nvgCircle(vg, oldX, oldY, r * 0.5)
                            nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 30))
                            nvgFill(vg)
                        end
                    end
                end

                -- =====================
                -- 外发光圈（脉冲） - Bloom 升级
                -- =====================
                local pulse = 0.7 + 0.3 * math.sin((now - p.spawnTime) * 12)
                local glowR = (r + 5) * pulse
                if Glow.enabled then
                    Glow.DrawCircleBloom255(vg, sx, sy, glowR, gc[1], gc[2], gc[3], gc[4])
                else
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, glowR)
                    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], gc[4]))
                    nvgFill(vg)
                end

                -- =====================
                -- emoji 子弹体（朝向移动方向）
                -- =====================
                local fontSize = r * 4.5
                -- 以移动方向为贴图"上"方向：atan2 得到速度角，-π/2 使默认朝上的emoji指向速度方向
                local rot = math.atan(p.vy, p.vx) + math.pi * 0.5

                nvgSave(vg)
                nvgTranslate(vg, sx, sy)
                nvgRotate(vg, rot)
                nvgFontSize(vg, fontSize)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, 0, 0, style.emoji)
                nvgRestore(vg)

                -- 追踪子弹额外标记（蓝色小瞄准线）
                if p.isHoming then
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, r + 8)
                    nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 120))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)
                end

                end -- end else (非冰弹)
            end
        end
    end
end

return Projectile
