--- MapEvent.lua — 随机地图事件系统 (Task 30)
--- 战斗中随机触发：宝箱守卫、治疗泉、商人、陷阱区
---@class MapEvent

local Config = require("Config")

local MapEvent = {}

-----------------------------------------------------------------------
-- 事件定义
-----------------------------------------------------------------------
MapEvent.EVENTS = {
    {
        id    = "treasure",
        name  = "宝箱守卫",
        icon  = "📦",
        desc  = "击杀守卫获得大量金币",
        color = { 255, 200, 50 },
        duration = 20,
        radius = 120,
    },
    {
        id    = "spring",
        name  = "治疗泉",
        icon  = "⛲",
        desc  = "站在泉水中持续回血",
        color = { 80, 220, 180 },
        duration = 15,
        radius = 100,
    },
    {
        id    = "merchant",
        name  = "旅行商人",
        icon  = "🏪",
        desc  = "花金币购买技能升级",
        color = { 180, 130, 255 },
        duration = 12,
        radius = 90,
    },
    {
        id    = "poison",
        name  = "毒雾区",
        icon  = "☠️",
        desc  = "站在其中持续掉血",
        color = { 120, 200, 40 },
        duration = 18,
        radius = 130,
    },
    {
        id    = "speed_zone",
        name  = "加速领域",
        icon  = "💨",
        desc  = "进入后短暂大幅加速",
        color = { 50, 200, 255 },
        duration = 12,
        radius = 100,
    },
    {
        id    = "magnet_zone",
        name  = "磁力漩涡",
        icon  = "🧲",
        desc  = "吸取周围所有掉落物",
        color = { 255, 100, 100 },
        duration = 10,
        radius = 110,
    },
}

-----------------------------------------------------------------------
-- 状态
-----------------------------------------------------------------------
MapEvent.active  = {}       -- 当前场上活跃的事件列表
MapEvent.cooldown = 0       -- 生成冷却计时器 (秒)
MapEvent.totalTriggered = 0 -- 本局触发总数 (成就用)

local SPAWN_INTERVAL = 25   -- 每 25 秒检查一次
local SPAWN_CHANCE   = 0.20 -- 20% 生成概率
local MAX_ACTIVE     = 2    -- 同时最多 2 个事件
local EVENT_FLASH_DUR = 3   -- 出现/消失闪烁时长

-- 商人提供的技能升级价格
local MERCHANT_COST = 30

-----------------------------------------------------------------------
-- 内部：安全距离生成坐标
-----------------------------------------------------------------------
local function RandomEventPos(playerX, playerY)
    local margin = 200
    local worldMax = Config.WORLD_SIZE - margin
    for _ = 1, 20 do
        local x = math.random(margin, worldMax)
        local y = math.random(margin, worldMax)
        local dx, dy = x - playerX, y - playerY
        local dist = math.sqrt(dx * dx + dy * dy)
        -- 不要太近也不要太远
        if dist > 400 and dist < 2000 then
            return x, y
        end
    end
    -- fallback：玩家附近 800px
    local angle = math.random() * 6.28
    return playerX + math.cos(angle) * 800, playerY + math.sin(angle) * 800
end

-----------------------------------------------------------------------
-- 初始化 / 重置
-----------------------------------------------------------------------
function MapEvent.Reset()
    MapEvent.active = {}
    MapEvent.cooldown = 15 -- 开局 15 秒后才开始生成
    MapEvent.totalTriggered = 0
end

-----------------------------------------------------------------------
-- 生成事件
-----------------------------------------------------------------------
function MapEvent.TrySpawn(playerX, playerY, waveNum)
    if #MapEvent.active >= MAX_ACTIVE then return end
    if waveNum < 3 then return end -- 前 3 波不生成

    local def = MapEvent.EVENTS[math.random(#MapEvent.EVENTS)]
    local x, y = RandomEventPos(playerX, playerY)

    local event = {
        def      = def,
        x        = x,
        y        = y,
        timer    = 0,           -- 存活计时
        maxTime  = def.duration,
        alive    = true,
        triggered = false,      -- 是否被玩家触发过
        -- 宝箱守卫专用
        guardsAlive  = 0,
        guardsDead   = 0,
        rewardGiven  = false,
        -- 商人专用
        merchantUsed = false,
    }

    -- 宝箱守卫：标记生成 3 个守卫怪
    if def.id == "treasure" then
        event.guardsAlive = 3
    end

    MapEvent.active[#MapEvent.active + 1] = event
    MapEvent.totalTriggered = MapEvent.totalTriggered + 1
    -- 成就：记录事件类型
    local Achievement = require("Achievement")
    Achievement.CheckMapEvent(def.id)
end

-----------------------------------------------------------------------
-- 更新
-----------------------------------------------------------------------
---@param dt number
---@param playerX number
---@param playerY number
---@param playerRef table Player 引用
---@param waveNum number
---@param onMerchantBuy function|nil 商人购买回调(cost) -> boolean
---@param onSpawnGuards function|nil 宝箱守卫生成回调(x,y,count)
function MapEvent.Update(dt, playerX, playerY, playerRef, waveNum, onMerchantBuy, onSpawnGuards)
    -- 冷却计时
    MapEvent.cooldown = MapEvent.cooldown - dt
    if MapEvent.cooldown <= 0 then
        MapEvent.cooldown = SPAWN_INTERVAL
        if math.random() < SPAWN_CHANCE then
            MapEvent.TrySpawn(playerX, playerY, waveNum)
        end
    end

    -- 更新活跃事件
    local i = 1
    while i <= #MapEvent.active do
        local ev = MapEvent.active[i]
        ev.timer = ev.timer + dt

        -- 超时移除
        if ev.timer >= ev.maxTime then
            ev.alive = false
        end

        -- 检测玩家是否在范围内
        local dx, dy = playerX - ev.x, playerY - ev.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local inRange = dist < ev.def.radius

        if ev.alive and inRange then
            ev.triggered = true
            local id = ev.def.id

            if id == "spring" then
                -- 治疗泉：每秒回复 3% maxHP
                local healAmt = math.max(1, math.floor(playerRef.maxHp * 0.03 * dt / 1.0))
                if playerRef.hp < playerRef.maxHp then
                    playerRef.hp = math.min(playerRef.maxHp, playerRef.hp + healAmt)
                end

            elseif id == "poison" then
                -- 毒雾区：每秒扣 2% maxHP（走 TakeDamage 以尊重无敌/护盾）
                local dmg = math.max(1, math.floor(playerRef.maxHp * 0.02 * dt / 1.0))
                if playerRef.TakeDamage then
                    playerRef.TakeDamage(dmg)
                else
                    playerRef.hp = math.max(1, playerRef.hp - dmg)
                end

            elseif id == "speed_zone" then
                -- 加速领域：给予 3 秒 50% 加速 buff
                if not playerRef._speedZoneBuff or playerRef._speedZoneBuff <= 0 then
                    playerRef._speedZoneBuff = 3.0
                end

            elseif id == "magnet_zone" then
                -- 磁力漩涡：触发全屏吸取
                if not ev._magnetTriggered then
                    ev._magnetTriggered = true
                    playerRef.magnetTimer = math.max(playerRef.magnetTimer or 0, 5.0)
                end

            elseif id == "merchant" then
                -- 商人自动交互：玩家进入范围且金币足够时自动购买
                if not ev.merchantUsed and onMerchantBuy then
                    if onMerchantBuy(MERCHANT_COST) then
                        ev.merchantUsed = true
                    end
                end

            elseif id == "treasure" then
                -- 宝箱守卫：生成守卫怪
                if ev.guardsAlive > 0 and not ev._guardsSpawned then
                    ev._guardsSpawned = true
                    if onSpawnGuards then
                        onSpawnGuards(ev.x, ev.y, 3)
                    end
                end
            end
        end

        -- 速度 buff 倒计时
        if playerRef._speedZoneBuff and playerRef._speedZoneBuff > 0 then
            playerRef._speedZoneBuff = playerRef._speedZoneBuff - dt
        end

        if not ev.alive then
            table.remove(MapEvent.active, i)
        else
            i = i + 1
        end
    end
end

-----------------------------------------------------------------------
-- 商人点击检测
-----------------------------------------------------------------------
function MapEvent.HitMerchant(worldX, worldY)
    for _, ev in ipairs(MapEvent.active) do
        if ev.alive and ev.def.id == "merchant" and not ev.merchantUsed then
            local dx, dy = worldX - ev.x, worldY - ev.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < ev.def.radius then
                return ev, MERCHANT_COST
            end
        end
    end
    return nil, 0
end

--- 标记商人已使用
function MapEvent.UseMerchant(ev)
    ev.merchantUsed = true
end

-----------------------------------------------------------------------
-- 宝箱守卫被击杀回调
-----------------------------------------------------------------------
function MapEvent.OnGuardKilled(x, y)
    for _, ev in ipairs(MapEvent.active) do
        if ev.alive and ev.def.id == "treasure" and ev._guardsSpawned then
            local dx, dy = x - ev.x, y - ev.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 400 then
                ev.guardsDead = ev.guardsDead + 1
                if ev.guardsDead >= 3 and not ev.rewardGiven then
                    ev.rewardGiven = true
                    -- 成就：宝箱开启
                    local Achievement = require("Achievement")
                    Achievement.CheckTreasureOpened()
                    return true -- 表示应掉落奖励
                end
            end
        end
    end
    return false
end

-----------------------------------------------------------------------
-- 渲染
-----------------------------------------------------------------------
function MapEvent.Render(vg, camX, camY, viewW, viewH, totalTime)
    for _, ev in ipairs(MapEvent.active) do
        local sx = ev.x - camX
        local sy = ev.y - camY

        -- 剔除屏幕外
        if (sx > -200 and sx < viewW + 200 and sy > -200 and sy < viewH + 200) then
            local def = ev.def
            local r = def.radius
            local c = def.color
            local alpha = 255

            -- 出现/消失渐变
            if ev.timer < 1.0 then
                alpha = math.floor(ev.timer / 1.0 * 255)
            elseif ev.timer > ev.maxTime - 2.0 then
                alpha = math.floor((ev.maxTime - ev.timer) / 2.0 * 255)
            end
            alpha = math.max(0, math.min(255, alpha))

            -- 区域圆圈
            local pulse = 1.0 + 0.05 * math.sin(totalTime * 3)
            local drawR = r * pulse

            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, drawR)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(alpha * 0.15)))
            nvgFill(vg)

            -- 边缘环
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, drawR)
            nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(alpha * 0.6)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            -- 内圈虚线效果（简化为第二个环）
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, drawR * 0.7)
            nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(alpha * 0.3)))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 中心图标
            nvgFontFace(vg, "zpix")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 36)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
            nvgText(vg, sx, sy - 8, def.icon)

            -- 事件名称
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
            nvgText(vg, sx, sy + 22, def.name)

            -- 剩余时间条
            local barW = 60
            local barH = 4
            local barX = sx - barW / 2
            local barY = sy + 34
            local pct = math.max(0, 1 - ev.timer / ev.maxTime)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW, barH, 2)
            nvgFillColor(vg, nvgRGBA(40, 40, 40, math.floor(alpha * 0.5)))
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW * pct, barH, 2)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
            nvgFill(vg)

            -- 商人：显示价格
            if def.id == "merchant" and not ev.merchantUsed then
                nvgFontSize(vg, 11)
                nvgFillColor(vg, nvgRGBA(255, 220, 100, alpha))
                nvgText(vg, sx, sy + 46, "🪙" .. MERCHANT_COST .. " 升级技能")
            elseif def.id == "merchant" and ev.merchantUsed then
                nvgFontSize(vg, 11)
                nvgFillColor(vg, nvgRGBA(150, 150, 150, alpha))
                nvgText(vg, sx, sy + 46, "已售罄")
            end

            -- 宝箱守卫：显示进度
            if def.id == "treasure" and ev._guardsSpawned then
                nvgFontSize(vg, 11)
                if ev.rewardGiven then
                    nvgFillColor(vg, nvgRGBA(255, 220, 50, alpha))
                    nvgText(vg, sx, sy + 46, "✅ 已开启!")
                else
                    nvgFillColor(vg, nvgRGBA(255, 200, 150, alpha))
                    nvgText(vg, sx, sy + 46, "⚔️ " .. ev.guardsDead .. "/3")
                end
            end
        end
    end
end

-----------------------------------------------------------------------
-- 小地图标记
-----------------------------------------------------------------------
function MapEvent.GetMinimapMarkers()
    local markers = {}
    for _, ev in ipairs(MapEvent.active) do
        if ev.alive then
            markers[#markers + 1] = {
                x = ev.x,
                y = ev.y,
                color = ev.def.color,
                icon  = ev.def.icon,
            }
        end
    end
    return markers
end

-----------------------------------------------------------------------
-- 速度加成查询
-----------------------------------------------------------------------
function MapEvent.GetSpeedBonus(playerRef)
    if playerRef._speedZoneBuff and playerRef._speedZoneBuff > 0 then
        return 0.50 -- +50% 速度
    end
    return 0
end

return MapEvent
