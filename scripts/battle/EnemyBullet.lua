--- ============================================================================
--- 敌方弹幕模块 - 对象池、碰撞玩家、渲染
--- Boss 技能弹幕 & 远程怪 (ranger) 射击
--- ============================================================================

local Config = require("Config")
local SM = require("utils.SafeMath")
local SpatialHash = require("utils.SpatialHash")

local EnemyBullet = {}

-- 魅惑子弹空间查询复用表
local _charmedNearby = {}

EnemyBullet.pool = {}
EnemyBullet.active = {}

-- 区域攻击列表（Boss area_rain / area_circle 等）
EnemyBullet.areas = {}

local function GetFromPool()
    local b = table.remove(EnemyBullet.pool)
    if b then return b end
    return {
        x = 0, y = 0,
        vx = 0, vy = 0,
        damage = 0,
        radius = 6,
        lifetime = 0,
        alive = false,
        emoji = "🔴",
        color = { 255, 50, 50 },
        -- 分裂弹专用
        splitOnDeath = false,
        splitCount = 0,
        splitSpeed = 0,
        splitDamage = 0,
        splitTargetX = 0,
        splitTargetY = 0,
    }
end

local function Recycle(b)
    b.alive = false
    b.splitOnDeath = false
    b.charmedBullet = false
    table.insert(EnemyBullet.pool, b)
end

function EnemyBullet.Reset()
    for i = #EnemyBullet.active, 1, -1 do
        Recycle(EnemyBullet.active[i])
        table.remove(EnemyBullet.active, i)
    end
    EnemyBullet.areas = {}
end

--- 发射一颗敌方子弹
---@param x number 起始X
---@param y number 起始Y
---@param targetX number 目标X
---@param targetY number 目标Y
---@param damage number 伤害
---@param speed number 弹速
---@param emoji string|nil 子弹 emoji
---@param color table|nil 颜色 {r,g,b}
---@param radius number|nil 碰撞半径
function EnemyBullet.Spawn(x, y, targetX, targetY, damage, speed, emoji, color, radius)
    local dx = targetX - x
    local dy = targetY - y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then dist = 1 end

    local b = GetFromPool()
    b.x = x
    b.y = y
    b.vx = (dx / dist) * speed
    b.vy = (dy / dist) * speed
    b.damage = damage
    b.radius = radius or 6
    b.lifetime = 4.0
    b.alive = true
    b.emoji = emoji or "🔴"
    b.color = color or { 255, 50, 50 }
    b.splitOnDeath = false
    table.insert(EnemyBullet.active, b)
    return b
end

--- 发射扇形弹幕
function EnemyBullet.SpawnFan(x, y, targetX, targetY, count, speed, damage, spreadAngle, emoji, color)
    local dx = targetX - x
    local dy = targetY - y
    local baseAngle = math.atan(dy, dx)
    local step = count > 1 and spreadAngle / (count - 1) or 0
    local startAngle = baseAngle - spreadAngle / 2

    for i = 0, count - 1 do
        local angle = startAngle + step * i
        local tx = x + math.cos(angle) * 200
        local ty = y + math.sin(angle) * 200
        EnemyBullet.Spawn(x, y, tx, ty, damage, speed, emoji, color)
    end
end

--- 发射 360° 散射弹幕
function EnemyBullet.SpawnRadial(x, y, count, speed, damage, emoji, color)
    for i = 0, count - 1 do
        local angle = (i / count) * math.pi * 2
        local tx = x + math.cos(angle) * 200
        local ty = y + math.sin(angle) * 200
        EnemyBullet.Spawn(x, y, tx, ty, damage, speed, emoji, color)
    end
end

--- 发射分裂弹（到达目标附近后分裂成多颗小弹）
function EnemyBullet.SpawnSplit(x, y, targetX, targetY, speed, damage, splitCount, splitSpeed, splitDamage, emoji, color)
    local b = EnemyBullet.Spawn(x, y, targetX, targetY, damage, speed, emoji, color, 10)
    b.splitOnDeath = true
    b.splitCount = splitCount
    b.splitSpeed = splitSpeed
    b.splitDamage = splitDamage
    b.splitTargetX = targetX
    b.splitTargetY = targetY
    -- 短寿命：飞到目标附近就分裂
    local dx = targetX - x
    local dy = targetY - y
    local dist = math.sqrt(dx * dx + dy * dy)
    b.lifetime = math.max(0.3, dist / speed)
end

--- 添加区域攻击（落石/毒圈等）
---@param area table 区域攻击数据
function EnemyBullet.AddArea(area)
    table.insert(EnemyBullet.areas, area)
end

--- 更新所有敌方弹幕，返回对玩家的伤害总和
---@param dt number
---@param playerX number
---@param playerY number
---@param playerRadius number
---@param blockers table|nil 阻挡者列表 { {x,y,radius,blockCD}, ... }（象+魅惑敌人）
---@param enemies table|nil 敌人列表（供魅惑子弹碰撞检测）
---@param killedList table|nil 击杀列表（魅惑子弹击杀的敌人加入此表）
---@return number totalDamage 对玩家造成的总伤害
function EnemyBullet.Update(dt, playerX, playerY, playerRadius, blockers, enemies, killedList)
    local totalDamage = 0

    -- 更新阻挡者冷却
    if blockers then
        for _, bk in ipairs(blockers) do
            if bk.blockCD and bk.blockCD > 0 then
                bk.blockCD = bk.blockCD - dt
            end
        end
    end

    -- 更新子弹
    for i = #EnemyBullet.active, 1, -1 do
        local b = EnemyBullet.active[i]
        if not b.alive then
            table.remove(EnemyBullet.active, i)
            Recycle(b)
        else
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt
            b.lifetime = b.lifetime - dt

            if b.lifetime <= 0 then
                -- 分裂弹到期：在当前位置散射
                if b.splitOnDeath then
                    EnemyBullet.SpawnRadial(b.x, b.y, b.splitCount, b.splitSpeed, b.splitDamage, "💥", b.color)
                end
                b.alive = false
            elseif b.charmedBullet then
                -- ── 魅惑子弹：空间哈希查询附近敌人（替代全量遍历）──
                local EnemyMod = require("battle.Enemy")
                local hash = EnemyMod._spatialHash
                if hash then
                    for ni = #_charmedNearby, 1, -1 do _charmedNearby[ni] = nil end
                    hash:QueryInto(b.x, b.y, 60, _charmedNearby)
                    for _, e in ipairs(_charmedNearby) do
                        if e.alive and not e.dying and not e.charmed and e.hp > 0 then
                            local edx = b.x - e.x
                            local edy = b.y - e.y
                            local ed2 = edx * edx + edy * edy
                            local er = b.radius + (e.radius or 15)
                            if ed2 <= er * er then
                                local dmg = math.max(1, SM.floor(b.damage))
                                EnemyMod.Damage(e, dmg)
                                if e.dying and killedList then
                                    table.insert(killedList, e)
                                end
                                b.alive = false
                                break
                            end
                        end
                    end
                end
            else
                -- 碰撞检测：与阻挡者（象/魅惑敌人，1s CD）
                local blocked = false
                if blockers then
                    for _, bk in ipairs(blockers) do
                        if (not bk.blockCD or bk.blockCD <= 0) then
                            local bdx = b.x - bk.x
                            local bdy = b.y - bk.y
                            local bd2 = bdx * bdx + bdy * bdy
                            local br = b.radius + (bk.radius or 20)
                            if bd2 <= br * br then
                                bk.blockCD = 1.0  -- 1秒冷却
                                b.alive = false
                                blocked = true
                                break
                            end
                        end
                    end
                end

                -- 碰撞检测：与玩家
                if not blocked then
                    local dx = b.x - playerX
                    local dy = b.y - playerY
                    local distSq = dx * dx + dy * dy
                    local radSum = b.radius + playerRadius
                    if distSq <= radSum * radSum then
                        totalDamage = totalDamage + b.damage
                        b.alive = false
                    end
                end
            end
        end
    end

    -- 更新区域攻击
    for i = #EnemyBullet.areas, 1, -1 do
        local a = EnemyBullet.areas[i]
        a.timer = a.timer - dt

        if a.type == "rain" then
            -- 落石：等待落下时间后在落点造成伤害
            if not a.landed and a.timer <= 0 then
                a.landed = true
                a.timer = 0.4  -- 落地后显示0.4秒
                -- 落点伤害检测
                if a.charmed then
                    -- 魅惑区域：伤害非魅惑敌人
                    if enemies then
                        for _, e in ipairs(enemies) do
                            if e.alive and not e.dying and not e.charmed and e.hp > 0 then
                                local edx = a.x - e.x
                                local edy = a.y - e.y
                                if edx * edx + edy * edy <= (a.radius + (e.radius or 15)) ^ 2 then
                                    local EnemyMod = require("battle.Enemy")
                                    local dmg = math.max(1, SM.floor(a.damage))
                                    EnemyMod.Damage(e, dmg)
                                    if e.dying and killedList then table.insert(killedList, e) end
                                end
                            end
                        end
                    end
                else
                    local dx = a.x - playerX
                    local dy = a.y - playerY
                    if dx * dx + dy * dy <= (a.radius + playerRadius) ^ 2 then
                        totalDamage = totalDamage + a.damage
                    end
                end
            end
            if a.landed and a.timer <= 0 then
                table.remove(EnemyBullet.areas, i)
            end
        elseif a.type == "circle" then
            -- 持续毒圈
            a.tickTimer = a.tickTimer - dt
            if a.tickTimer <= 0 then
                a.tickTimer = a.tickInterval
                if a.charmed then
                    -- 魅惑毒圈：伤害非魅惑敌人
                    if enemies then
                        for _, e in ipairs(enemies) do
                            if e.alive and not e.dying and not e.charmed and e.hp > 0 then
                                local edx = a.x - e.x
                                local edy = a.y - e.y
                                if edx * edx + edy * edy <= (a.radius + (e.radius or 15)) ^ 2 then
                                    local EnemyMod = require("battle.Enemy")
                                    local dmg = math.max(1, SM.floor(a.damage))
                                    EnemyMod.Damage(e, dmg)
                                    if e.dying and killedList then table.insert(killedList, e) end
                                end
                            end
                        end
                    end
                else
                    local dx = a.x - playerX
                    local dy = a.y - playerY
                    if dx * dx + dy * dy <= (a.radius + playerRadius) ^ 2 then
                        totalDamage = totalDamage + a.damage
                    end
                end
            end
            if a.timer <= 0 then
                table.remove(EnemyBullet.areas, i)
            end
        end
    end

    return totalDamage
end

--- 渲染所有敌方弹幕
function EnemyBullet.Render(vg, camX, camY, viewW, viewH)
    local margin = 30

    -- 渲染区域攻击
    for _, a in ipairs(EnemyBullet.areas) do
        local sx = a.x - camX
        local sy = a.y - camY
        if sx > -200 and sx < viewW + 200 and sy > -200 and sy < viewH + 200 then
            if a.type == "rain" then
                if not a.landed then
                    -- 预警圈（脉冲红圈）
                    local progress = 1.0 - (a.timer / a.fallDuration)
                    local pulse = 0.5 + 0.5 * math.sin(progress * 20)
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, a.radius)
                    nvgFillColor(vg, nvgRGBA(255, 50, 30, math.floor(40 + 60 * pulse)))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(255, 80, 30, math.floor(120 + 80 * pulse)))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                    -- 下落阴影（越来越大）
                    local shadowR = a.radius * progress * 0.6
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, shadowR)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(80 * progress)))
                    nvgFill(vg)
                else
                    -- 落地爆炸效果
                    local fadeOut = a.timer / 0.4
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, a.radius * (1.2 + (1.0 - fadeOut) * 0.5))
                    nvgFillColor(vg, nvgRGBA(255, 100, 30, math.floor(180 * fadeOut)))
                    nvgFill(vg)
                    -- 爆炸 emoji
                    nvgFontSize(vg, a.radius * 1.8)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * fadeOut)))
                    nvgText(vg, sx, sy, "💥")
                end
            elseif a.type == "circle" then
                -- 持续毒圈
                local fadeOut = math.min(1.0, a.timer / 0.5)
                local pulse = 0.7 + 0.3 * math.sin(a.tickTimer * 15)
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, a.radius)
                nvgFillColor(vg, nvgRGBA(a.color[1], a.color[2], a.color[3],
                    math.floor(40 * fadeOut * pulse)))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(a.color[1], a.color[2], a.color[3],
                    math.floor(150 * fadeOut)))
                nvgStrokeWidth(vg, 2.5)
                nvgStroke(vg)
            end
        end
    end

    -- 渲染子弹
    for _, b in ipairs(EnemyBullet.active) do
        if b.alive then
            local sx = b.x - camX
            local sy = b.y - camY
            if sx > -margin and sx < viewW + margin and sy > -margin and sy < viewH + margin then
                -- 外发光
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, b.radius + 4)
                nvgFillColor(vg, nvgRGBA(b.color[1], b.color[2], b.color[3], 40))
                nvgFill(vg)

                -- emoji 弹体
                nvgFontSize(vg, b.radius * 3.0)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, sx, sy, b.emoji)
            end
        end
    end
end

return EnemyBullet
