--- ============================================================================
--- 掉落物模块 - 经验芯片 + 特殊掉落（红心/磁铁/炸弹/金币/礼物盒）
--- ============================================================================

local Config = require("Config")
local Wave = require("battle.Wave")
local SM = require("utils.SafeMath")
local DailyChallenge = require("meta.DailyChallenge")
local Glow = require("fx.Glow")

local Player  -- 延迟引用，在 SpawnFromEnemy 中通过 Loot._Player 访问

local Loot = {}

Loot.pool = {}
Loot.active = {}

-- 合并检查计时器（不需要每帧检查）
Loot._mergeTimer = 0
Loot._MERGE_INTERVAL = 5.0           -- 每 5 秒检查一次合并
Loot._MERGE_MAX_XP = 50             -- 场上最多保留 50 个经验球
Loot._MERGE_MAX_COIN = 50           -- 场上最多保留 50 个金币

-- 磁铁增益状态
Loot.magnetBoostTimer = 0      -- 磁铁效果剩余时间
Loot.magnetBoostRange = 0      -- 磁铁增益范围

-- 礼物盒状态
Loot.lastGiftWave = -99        -- 上次掉落礼物的波次号
Loot.onGiftPickup = nil        -- function() -> 弹出广告弹窗

-- 炸弹回调（由 BattleScene 设置）
Loot.onBombPickup = nil        -- function() -> 全屏清怪

-- 回血回调（由 BattleScene 设置）
Loot.onHeartPickup = nil       -- function(healPercent)

-- 金币拾取回调（由 BattleScene 设置，用于积累局外金币）
Loot.onCoinPickup = nil        -- function() -> 积累1枚局外金币

local function GetFromPool()
    local l = table.remove(Loot.pool)
    if l then return l end
    return {
        x = 0, y = 0,
        exp = 0,
        alive = false,
        spawnTimer = 0,
        lootType = "xp",       -- "xp"|"heart"|"magnet"|"bomb"|"coin"
        floatPhase = 0,        -- 浮动动画相位
    }
end

local function Recycle(l)
    l.alive = false
    table.insert(Loot.pool, l)
end

function Loot.Reset()
    for i = #Loot.active, 1, -1 do
        Recycle(Loot.active[i])
        table.remove(Loot.active, i)
    end
    Loot.magnetBoostTimer = 0
    Loot.magnetBoostRange = 0
    Loot.lastGiftWave = -99
    Loot._mergeTimer = 0
end

-- 就近合并半径（生成时检查附近是否有同类可合并）
Loot._SPAWN_MERGE_RADIUS_SQ = 40 * 40  -- 40 像素内合并

--- 生成经验芯片（就近合并：附近已有经验球则叠加，减少对象数量）
function Loot.Spawn(x, y, exp)
    -- 硬上限：场上掉落物过多时直接合并到最近的或丢弃（防炸弹清怪单帧爆炸）
    if #Loot.active >= 200 then
        -- 找最近的经验球合并
        local bestL, bestD2 = nil, math.huge
        for i = math.max(1, #Loot.active - 30), #Loot.active do
            local l = Loot.active[i]
            if l and l.alive and l.lootType == "xp" then
                local dx2 = x - l.x
                local dy2 = y - l.y
                local d2 = dx2 * dx2 + dy2 * dy2
                if d2 < bestD2 then bestD2 = d2; bestL = l end
            end
        end
        if bestL then bestL.exp = bestL.exp + exp end
        return
    end

    -- 就近合并检查：只检查最近的20个（避免O(n)全量扫描）
    local mergeR2 = Loot._SPAWN_MERGE_RADIUS_SQ
    local nx = x + (math.random() - 0.5) * 20
    local ny = y + (math.random() - 0.5) * 20
    local scanStart = math.max(1, #Loot.active - 20)
    for i = scanStart, #Loot.active do
        local l = Loot.active[i]
        if l.alive and l.lootType == "xp" and l.spawnTimer <= 0 then
            local dx = nx - l.x
            local dy = ny - l.y
            if dx * dx + dy * dy < mergeR2 then
                l.exp = l.exp + exp
                return  -- 已合并，不创建新对象
            end
        end
    end

    local l = GetFromPool()
    l.x = nx
    l.y = ny
    l.exp = exp
    l.alive = true
    l.spawnTimer = 0.2
    l.lootType = "xp"
    l.floatPhase = math.random() * 6.28
    table.insert(Loot.active, l)
end

--- 生成特殊掉落物
function Loot.SpawnSpecial(x, y, lootType)
    local l = GetFromPool()
    l.x = x + (math.random() - 0.5) * 10
    l.y = y + (math.random() - 0.5) * 10
    l.exp = 0
    l.alive = true
    l.spawnTimer = 0.3
    l.lootType = lootType
    l.floatPhase = math.random() * 6.28
    table.insert(Loot.active, l)
end

--- 计算当前金币掉落概率（图腾加基础，波次和四叶草乘算）
---@return number 最终掉率（可超过 1.0）
function Loot.CalcCoinDropChance()
    -- 延迟加载 Player（避免循环 require）
    if not Player and Loot._Player then Player = Loot._Player end

    -- 1) 基础掉率 = 初始值 + 金币图腾 + 掉落图腾（加算）
    local base = Config.LOOT.coinChance
    if Player then
        base = base + (Player.totemLootBonus or 0)
    end

    -- 2) 波次缩放：乘算，每波 +8%（第13波 ×2.0，第25波 ×3.0）
    local waveMulti = 1 + (Wave.waveNum or 0) * 0.08

    -- 3) 四叶草天赋（技能 lootBonus）：乘算
    local cloverMulti = 1
    if Player then
        cloverMulti = 1 + (Player.lootBonus or 0)
    end

    return base * waveMulti * cloverMulti
end

--- 批量掉落（敌人死亡时）- 现在包含特殊掉落判定
function Loot.SpawnFromEnemy(x, y, expDrop)
    -- 经验芯片（大经验拆分）
    if expDrop > 30 then
        local count = math.min(5, math.ceil(expDrop / 15))
        local each = SM.floor(expDrop / count)
        for i = 1, count do
            Loot.Spawn(x, y, each)
        end
    else
        Loot.Spawn(x, y, expDrop)
    end

    -- ========== 特殊掉落随机判定 ==========
    -- 红心/磁铁/炸弹：固定概率，独立判定
    local roll = math.random()
    local heartChance = Config.LOOT.heartChance
    local magnetChance = Config.LOOT.magnetChance
    local bombChance = Config.LOOT.bombChance

    -- 幸运遗物加成
    local pl = Loot._Player
    if pl and pl.relicLuckBonus and pl.relicLuckBonus > 0 then
        local luckMult = 1 + pl.relicLuckBonus
        heartChance = heartChance * luckMult
        magnetChance = magnetChance * luckMult
        bombChance = bombChance * luckMult
    end

    -- 每日挑战修改器
    if DailyChallenge.active then
        -- 拾金者：道具掉率 ×0.5
        if DailyChallenge.HasFactor("coin_loot") then
            heartChance = heartChance * 0.5
            magnetChance = magnetChance * 0.5
            bombChance = bombChance * 0.5
        end
        -- 危险炸弹：炸弹掉率 ×2
        if DailyChallenge.HasFactor("bomb_risk") then
            bombChance = bombChance * 2
        end
    end

    if roll < heartChance then
        Loot.SpawnSpecial(x, y, "heart")
    elseif roll < heartChance + magnetChance then
        Loot.SpawnSpecial(x, y, "magnet")
    elseif roll < heartChance + magnetChance + bombChance then
        Loot.SpawnSpecial(x, y, "bomb")
    end

    -- ========== 金币掉落：波次缩放 + 超100%多掉 ==========
    local coinRate = Loot.CalcCoinDropChance()
    -- 每日挑战 拾金者：金币掉率 ×2
    if DailyChallenge.HasFactor("coin_loot") then
        coinRate = coinRate * 2
    end
    -- 整数部分：保底掉落数量
    local guaranteed = math.floor(coinRate)
    -- 小数部分：概率掉落
    local fractional = coinRate - guaranteed
    local coinCount = guaranteed
    if math.random() < fractional then
        coinCount = coinCount + 1
    end
    for _ = 1, coinCount do
        Loot.SpawnSpecial(x, y, "coin")
    end

    -- 礼物盒掉落判定（极低概率，每5波最多1个，场上最多1个）
    local gb = Config.GIFT_BOX
    if Wave.waveNum - Loot.lastGiftWave >= gb.waveCooldown then
        local hasGift = false
        for _, l in ipairs(Loot.active) do
            if l.alive and l.lootType == "gift" then hasGift = true; break end
        end
        if not hasGift and math.random() < gb.dropChance then
            Loot.SpawnSpecial(x, y, "gift")
            Loot.lastGiftWave = Wave.waveNum
        end
    end
end

--- 获取当前有效磁吸范围（包含磁铁增益）
function Loot.GetEffectiveMagnetRange(baseRange)
    if Loot.magnetBoostTimer > 0 then
        return math.max(baseRange, Loot.magnetBoostRange)
    end
    return baseRange
end

--- 处理特殊掉落拾取效果
---@return number 额外经验
local function HandleSpecialPickup(l)
    local tp = l.lootType

    if tp == "heart" then
        if Loot.onHeartPickup then
            Loot.onHeartPickup(Config.SPECIAL_LOOT.heart.healPercent)
        end
        return 0

    elseif tp == "magnet" then
        local mc = Config.SPECIAL_LOOT.magnet
        Loot.magnetBoostTimer = mc.duration
        Loot.magnetBoostRange = mc.range
        return 0

    elseif tp == "bomb" then
        if Loot.onBombPickup then
            Loot.onBombPickup()
        end
        return 0

    elseif tp == "coin" then
        -- 金币拾取：合并后 l.exp 存储叠加数量（>=1）
        local coinCount = math.max(l.exp or 0, 1)
        if Loot.onCoinPickup then
            for _ = 1, coinCount do
                Loot.onCoinPickup()
            end
        end
        return Config.LOOT.baseExp * Config.SPECIAL_LOOT.coin.expMulti * coinCount
    end

    return 0
end

--- 合并掉落物：保留最多 _MERGE_MAX_XP 个经验球和 _MERGE_MAX_COIN 个金币
--- 超出上限的项被移除，其经验/金币值转移到距离最近的保留项上
--- 保留策略：离玩家最近的优先保留
function Loot.MergeNearby()
    local active = Loot.active
    if not Player and Loot._Player then Player = Loot._Player end
    local px, py = Player and Player.x or 0, Player and Player.y or 0

    -- 收集可合并的 xp 和 coin（已完成生成动画的）
    local xpList = {}
    local coinList = {}
    for i = 1, #active do
        local l = active[i]
        if l.alive and l.spawnTimer <= 0 then
            if l.lootType == "xp" then
                xpList[#xpList + 1] = l
            elseif l.lootType == "coin" then
                coinList[#coinList + 1] = l
            end
        end
    end

    -- 裁剪函数：保留离玩家最近的 maxKeep 个，多余的值转移到最近的保留项
    local function TrimList(list, maxKeep)
        if #list <= maxKeep then return end

        -- 按离玩家距离升序排序（近的在前）
        table.sort(list, function(a, b)
            local da = (a.x - px) * (a.x - px) + (a.y - py) * (a.y - py)
            local db = (b.x - px) * (b.x - px) + (b.y - py) * (b.y - py)
            return da < db
        end)

        -- 保留前 maxKeep 个（离玩家最近），移除后面的
        for ri = maxKeep + 1, #list do
            local removed = list[ri]
            local val = removed.exp or 0
            if removed.lootType == "coin" then
                val = math.max(val, 1)
            end

            -- 找距离最近的保留项来转移值
            local bestDist = math.huge
            local bestItem = nil
            for ki = 1, maxKeep do
                local keeper = list[ki]
                if keeper.alive then
                    local dx = removed.x - keeper.x
                    local dy = removed.y - keeper.y
                    local d = dx * dx + dy * dy
                    if d < bestDist then
                        bestDist = d
                        bestItem = keeper
                    end
                end
            end

            -- 转移值
            if bestItem then
                bestItem.exp = (bestItem.exp or 0) + val
            end
            -- 标记移除
            removed.alive = false
        end
    end

    TrimList(xpList, Loot._MERGE_MAX_XP)
    TrimList(coinList, Loot._MERGE_MAX_COIN)
end

--- 更新掉落物（磁吸拾取）
---@return number 本帧拾取的总经验
function Loot.Update(dt, playerX, playerY, magnetRange)
    local totalExp = 0

    -- 磁铁增益倒计时
    if Loot.magnetBoostTimer > 0 then
        Loot.magnetBoostTimer = Loot.magnetBoostTimer - dt
    end

    -- 定时合并检查
    Loot._mergeTimer = Loot._mergeTimer + dt
    if Loot._mergeTimer >= Loot._MERGE_INTERVAL then
        Loot._mergeTimer = 0
        Loot.MergeNearby()
    end

    local effectiveRange = Loot.GetEffectiveMagnetRange(magnetRange)

    for i = #Loot.active, 1, -1 do
        local l = Loot.active[i]
        if not l.alive then
            table.remove(Loot.active, i)
            Recycle(l)
        else
            -- 浮动动画
            l.floatPhase = l.floatPhase + dt * 3

            -- 生成动画
            if l.spawnTimer > 0 then
                l.spawnTimer = l.spawnTimer - dt
            else
                local dx = playerX - l.x
                local dy = playerY - l.y
                local distSq = dx * dx + dy * dy

                -- 礼物盒：不被磁铁吸引，仅碰撞拾取触发回调
                if l.lootType == "gift" then
                    local pickupR = Player.radius + 10
                    if distSq < pickupR * pickupR then
                        l.alive = false
                        if Loot.onGiftPickup then
                            Loot.onGiftPickup()
                        end
                    end
                else
                    -- 常规磁吸效果
                    local pickupR = Player.radius
                    if l.lootType ~= "xp" then
                        pickupR = pickupR + 8
                    end

                    local magnetSq = effectiveRange * effectiveRange

                    if distSq <= magnetSq then
                        local dist = math.sqrt(distSq)
                        if dist < pickupR then
                            -- 拾取
                            if l.lootType == "xp" then
                                totalExp = SM.add(totalExp, l.exp)
                            else
                                totalExp = SM.add(totalExp, HandleSpecialPickup(l))
                            end
                            l.alive = false
                        else
                            -- 加速靠近
                            local speed = Config.LOOT.magnetSpeed
                            l.x = l.x + (dx / dist) * speed * dt
                            l.y = l.y + (dy / dist) * speed * dt
                        end
                    end
                end
            end
        end
    end

    return totalExp
end

--- 渲染掉落物
function Loot.Render(vg, camX, camY, viewW, viewH)
    local xpR = Config.LOOT.radius
    local xpC = Config.COLORS.xpChip

    for _, l in ipairs(Loot.active) do
        if l.alive then
            local sx = l.x - camX
            local sy = l.y - camY
            if sx > -20 and sx < viewW + 20 and sy > -20 and sy < viewH + 20 then
                -- 生成缩放动画
                local scaleT = 1.0
                if l.spawnTimer > 0 then
                    scaleT = 1 - (l.spawnTimer / 0.3)
                end

                -- 浮动偏移
                local floatY = math.sin(l.floatPhase) * 2

                if l.lootType == "xp" then
                    -- 经验芯片（菱形 + 发光）
                    local displayR = xpR * scaleT

                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy + floatY, displayR + 3)
                    nvgFillColor(vg, nvgRGBA(xpC[1], xpC[2], xpC[3], 30))
                    nvgFill(vg)

                    nvgBeginPath(vg)
                    nvgMoveTo(vg, sx, sy + floatY - displayR)
                    nvgLineTo(vg, sx + displayR, sy + floatY)
                    nvgLineTo(vg, sx, sy + floatY + displayR)
                    nvgLineTo(vg, sx - displayR, sy + floatY)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(xpC[1], xpC[2], xpC[3], 255))
                    nvgFill(vg)
                elseif l.lootType == "gift" then
                    -- 礼物盒（金色脉冲光晕 + 大号 emoji）- Bloom 升级
                    local spec = Config.SPECIAL_LOOT.gift
                    local displayR = spec.radius * scaleT
                    local pulse = 0.6 + 0.4 * math.sin(l.floatPhase * 1.5)

                    if Glow.enabled then
                        -- Bloom 光柱 + 脉冲光晕
                        Glow.DrawLightPillar(vg, sx, sy + floatY, displayR * 1.5, 60, 255, 200, 50, 0.3 * pulse)
                        Glow.DrawNeonPulse(vg, sx, sy + floatY, displayR + 6, 255, 220, 80, math.floor(60 * pulse), 2.0)
                    else
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy + floatY, displayR + 10 + pulse * 4)
                        nvgFillColor(vg, nvgRGBA(255, 200, 50, math.floor(30 * pulse)))
                        nvgFill(vg)
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy + floatY, displayR + 4)
                        nvgFillColor(vg, nvgRGBA(255, 220, 80, math.floor(50 * pulse)))
                        nvgFill(vg)
                    end

                    -- emoji
                    nvgFontSize(vg, displayR * 2.5)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, sx, sy + floatY, spec.emoji)
                else
                    -- 其他特殊掉落物（emoji 渲染）- Bloom 升级
                    local spec = Config.SPECIAL_LOOT[l.lootType]
                    if spec then
                        local displayR = spec.radius * scaleT

                        -- 外发光圈（bloom 径向渐变）
                        if Glow.enabled then
                            Glow.DrawCircleBloom255(vg, sx, sy + floatY, displayR + 5, 255, 255, 200, 40)
                        else
                            nvgBeginPath(vg)
                            nvgCircle(vg, sx, sy + floatY, displayR + 5)
                            nvgFillColor(vg, nvgRGBA(255, 255, 200, 25))
                            nvgFill(vg)
                        end

                        -- emoji
                        local fontSize = displayR * 2.2
                        nvgFontSize(vg, fontSize)
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                        nvgText(vg, sx, sy + floatY, spec.emoji)
                    end
                end
            end
        end
    end

    -- 临时加成在右下角由 HUD 统一渲染（已移除此处）
end

return Loot
