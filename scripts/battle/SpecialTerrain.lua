--- ============================================================================
--- SpecialTerrain.lua — 地图专属特别地形系统
--- 每种特别地形同时仅有一个实例。
--- 玩家靠近后自动触发互动奖励，之后该地形消失。
--- 随机延迟（15-35秒）后，同种地形在屏幕外随机位置重新生成。
--- ============================================================================

local Config = require("Config")

local SpecialTerrain = {}

-- ============================================================================
-- 各地图的特别地形定义
-- ============================================================================
-- 每条记录：
--   emoji      显示图标
--   name       名称（奖励提示用）
--   color      { r, g, b } 光圈颜色
--   radius     触发半径（像素）
--   reward     奖励类型字符串
--   rewardVal  奖励数值或时长
--   desc       简短描述
local MAP_DEFS = {
    -- ── 赛博废墟 ──────────────────────────────────────
    cyber = {
        {
            emoji = "💉", name = "数据注射器",
            color = { 80, 200, 255 },
            radius = 55,
            reward = "attack_rate_buff",
            rewardVal = 25,         -- 攻速+20% 持续25秒
            desc = "⚡ 攻速+20%  25秒",
        },
        {
            emoji = "💾", name = "数据宝箱",
            color = { 120, 80, 255 },
            radius = 55,
            reward = "exp",
            rewardVal = 180,        -- 大量经验
            desc = "💾 获得大量经验",
        },
        {
            emoji = "🔫", name = "激光炮台",
            color = { 255, 60, 120 },
            radius = 55,
            reward = "atk_buff",
            rewardVal = 30,         -- 攻击+25% 持续30秒
            desc = "🔫 攻击+25%  30秒",
        },
    },
    -- ── 翡翠草原 ──────────────────────────────────────
    grass = {
        {
            emoji = "💧", name = "治愈泉",
            color = { 60, 220, 160 },
            radius = 60,
            reward = "heal",
            rewardVal = 0.60,       -- 回复60%最大HP
            desc = "💧 回复60%生命",
        },
        {
            emoji = "🧚", name = "精灵祝福",
            color = { 200, 100, 255 },
            radius = 55,
            reward = "magnet_buff",
            rewardVal = 15,         -- 磁吸×3 持续15秒
            desc = "🧚 磁力×3  15秒",
        },
        {
            emoji = "🛕", name = "自然神龛",
            color = { 255, 220, 60 },
            radius = 55,
            reward = "skill_up",
            rewardVal = 1,
            desc = "🛕 随机技能升级",
        },
    },
    -- ── 幽暗洞穴 ──────────────────────────────────────
    cave = {
        {
            emoji = "💎", name = "古代水晶",
            color = { 100, 180, 255 },
            radius = 55,
            reward = "atk_buff",
            rewardVal = 40,         -- 攻击+25% 持续40秒
            desc = "💎 攻击+25%  40秒",
        },
        {
            emoji = "🍄", name = "爆炸蘑菇",
            color = { 255, 120, 60 },
            radius = 55,
            reward = "bomb",
            rewardVal = 1,
            desc = "🍄 全屏清怪！",
        },
        {
            emoji = "🏺", name = "深渊宝藏",
            color = { 255, 200, 80 },
            radius = 55,
            reward = "exp_coin",
            rewardVal = 220,        -- 大量经验+金币
            desc = "🏺 大量经验+金币",
        },
    },
    -- ── 天空浮岛 ──────────────────────────────────────
    sky = {
        {
            emoji = "🌀", name = "风之祭坛",
            color = { 120, 220, 255 },
            radius = 60,
            reward = "speed_buff",
            rewardVal = 20,         -- 移速+30% 持续20秒
            desc = "🌀 移速+30%  20秒",
        },
        {
            emoji = "⭐", name = "星辰神殿",
            color = { 255, 240, 100 },
            radius = 60,
            reward = "star_burst",
            rewardVal = 5,          -- 无敌5秒+全屏AOE
            desc = "⭐ 无敌5秒+全屏AOE",
        },
        {
            emoji = "📦", name = "云端宝箱",
            color = { 180, 130, 255 },
            radius = 55,
            reward = "exp",
            rewardVal = 200,        -- 大量经验
            desc = "📦 获得大量经验",
        },
    },
}

-- ============================================================================
-- 常量
-- ============================================================================
local RESPAWN_MIN    = 15       -- 最短重生等待时间（秒）
local RESPAWN_MAX    = 35       -- 最长重生等待时间（秒）
local SPAWN_MARGIN   = 120      -- 生成位置超出屏幕边缘的额外距离（像素）
local WORLD_MARGIN   = 200      -- 距世界边界的安全距离
local PULSE_SPEED    = 2.2      -- 光圈脉动速度
local FLOAT_AMP      = 5        -- 上下浮动幅度（像素）
local FLOAT_SPEED    = 1.8      -- 浮动速度

-- ============================================================================
-- 运行时状态
-- ============================================================================

---@class SpotInstance
---@field defIdx      number    地形定义索引（在 defs 数组中的位置）
---@field def         table     指向 MAP_DEFS 中某条定义
---@field x           number    世界坐标 X
---@field y           number    世界坐标 Y
---@field alive       boolean   true = 可见可触碰；false = 已领取/等待重生
---@field flashTimer  number    领取时闪光倒计时（0 = 无）
---@field phase       number    浮动相位偏移
---@field respawnTimer number   重生倒计时（alive=false 时递减，≤0 则重生）

--- 当前地图所有地形槽（每种地形类型一个槽，全局保持不变）
SpecialTerrain.spots = {}

--- Buff 状态（玩家当前效果）
SpecialTerrain.buffs = {
    atkMult        = 1.0,  atkTimer        = 0,
    speedMult      = 1.0,  speedTimer      = 0,
    attackRateMult = 1.0,  attackRateTimer = 0,
    magnetMult     = 1.0,  magnetTimer     = 0,
    invincTimer    = 0,    -- 无敌倒计时（star_burst）
}

-- 保存当前地图的 defs，供重生时使用
local _activeDefs = nil

-- ============================================================================
-- 内部工具
-- ============================================================================
local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

--- 在屏幕外随机选一个合法世界坐标（用于重生）
---@param camX  number  相机左上角世界 X
---@param camY  number  相机左上角世界 Y
---@param viewW number  视口宽
---@param viewH number  视口高
---@return number, number  世界坐标 wx, wy
local function PickOffScreenPos(camX, camY, viewW, viewH)
    local ws  = Config.WORLD_SIZE
    local wm  = WORLD_MARGIN
    local sm  = SPAWN_MARGIN

    -- 屏幕四个边的外侧区域（各自独立，随机选一条边）
    local edge = math.random(4)
    local wx, wy

    for attempt = 1, 20 do
        if edge == 1 then
            -- 上方
            wx = wm + math.random() * (ws - wm * 2)
            wy = camY - sm - math.random() * sm * 2
        elseif edge == 2 then
            -- 下方
            wx = wm + math.random() * (ws - wm * 2)
            wy = camY + viewH + sm + math.random() * sm * 2
        elseif edge == 3 then
            -- 左方
            wx = camX - sm - math.random() * sm * 2
            wy = wm + math.random() * (ws - wm * 2)
        else
            -- 右方
            wx = camX + viewW + sm + math.random() * sm * 2
            wy = wm + math.random() * (ws - wm * 2)
        end

        -- 夹紧到世界范围内
        wx = math.max(wm, math.min(ws - wm, wx))
        wy = math.max(wm, math.min(ws - wm, wy))

        -- 检查是否真的在屏幕外（加一点余量）
        local offscreen = wx < camX - sm * 0.5 or wx > camX + viewW + sm * 0.5
                       or wy < camY - sm * 0.5 or wy > camY + viewH + sm * 0.5
        if offscreen then
            return wx, wy
        end

        -- 换一条边再试
        edge = (edge % 4) + 1
    end

    -- 保底：直接放到地图左上角区域
    return wm + math.random() * 400, wm + math.random() * 400
end

--- 生成一个随机重生等待时间
---@return number
local function RandRespawnDelay()
    return RESPAWN_MIN + math.random() * (RESPAWN_MAX - RESPAWN_MIN)
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 重置（每局开始前调用）
function SpecialTerrain.Reset()
    SpecialTerrain.spots = {}
    _activeDefs = nil
    local b = SpecialTerrain.buffs
    b.atkMult = 1.0;  b.atkTimer = 0
    b.speedMult = 1.0; b.speedTimer = 0
    b.attackRateMult = 1.0; b.attackRateTimer = 0
    b.magnetMult = 1.0; b.magnetTimer = 0
    b.invincTimer = 0
end

--- 初始化：为每种地形类型创建一个实例，分散在世界各处
---@param variantId string  当前地图 ID（"cyber"/"grass"/"cave"/"sky"）
---@param seed      number  随机种子（与 MapVariant 共享）
function SpecialTerrain.Init(variantId, seed)
    SpecialTerrain.Reset()

    local defs = MAP_DEFS[variantId]
    if not defs or #defs == 0 then
        print("[SpecialTerrain] No defs for variant: " .. tostring(variantId))
        return
    end

    _activeDefs = defs

    local ws  = Config.WORLD_SIZE
    local wm  = WORLD_MARGIN
    local playerStartX = ws / 2
    local playerStartY = ws / 2
    local safeStartDist = 500   -- 距玩家出生点最小距离
    local minSpotDist   = 400   -- 地形点之间最小距离

    -- 用种子初始化一个伪随机序列
    math.randomseed(seed)

    -- 每种地形类型创建一个实例
    for i = 1, #defs do
        local def = defs[i]

        local sx, sy
        local attempts = 0
        repeat
            attempts = attempts + 1
            sx = wm + math.random() * (ws - wm * 2)
            sy = wm + math.random() * (ws - wm * 2)

            local tooClosePlayer = dist2(sx, sy, playerStartX, playerStartY) < safeStartDist ^ 2
            local tooCloseSpot = false
            for _, existing in ipairs(SpecialTerrain.spots) do
                if dist2(sx, sy, existing.x, existing.y) < minSpotDist ^ 2 then
                    tooCloseSpot = true
                    break
                end
            end
            if not tooClosePlayer and not tooCloseSpot then break end
        until attempts >= 30

        SpecialTerrain.spots[#SpecialTerrain.spots + 1] = {
            defIdx       = i,
            def          = def,
            x            = sx,
            y            = sy,
            alive        = true,
            flashTimer   = 0,
            phase        = math.random() * 6.28,
            respawnTimer = 0,
        }
    end

    print(string.format("[SpecialTerrain] Init: %d terrain types for map=%s",
        #SpecialTerrain.spots, variantId))
end

--- 每帧更新
---@param dt           number   帧时间
---@param playerX      number
---@param playerY      number
---@param playerRef    table    Player 模块引用
---@param waveNum      number   当前波次
---@param camX         number   相机左上角世界 X
---@param camY         number   相机左上角世界 Y
---@param viewW        number   视口宽
---@param viewH        number   视口高
---@param onExpGain    function(amount)
---@param onSkillUp    function()
---@param onBomb       function()
---@param onCoin       function(amount)
function SpecialTerrain.Update(dt, playerX, playerY, playerRef, waveNum,
                               camX, camY, viewW, viewH,
                               onExpGain, onSkillUp, onBomb, onCoin)
    -- ── 1. 每个槽单独处理 ─────────────────────────────
    for _, spot in ipairs(SpecialTerrain.spots) do
        if spot.alive then
            -- 检测玩家触碰
            local r = spot.def.radius
            if dist2(playerX, playerY, spot.x, spot.y) < r * r then
                spot.alive        = false
                spot.flashTimer   = 0.6
                spot.respawnTimer = RandRespawnDelay()
                SpecialTerrain._ApplyReward(spot.def, playerRef,
                    onExpGain, onSkillUp, onBomb, onCoin)
            end
        else
            -- 领取闪光倒计时
            if spot.flashTimer > 0 then
                spot.flashTimer = spot.flashTimer - dt
            end

            -- 重生倒计时（flashTimer 结束后才开始计时，避免视觉重叠）
            if spot.flashTimer <= 0 then
                spot.respawnTimer = spot.respawnTimer - dt
                if spot.respawnTimer <= 0 then
                    -- 在屏幕外重生
                    spot.x         = 0
                    spot.y         = 0
                    spot.x, spot.y = PickOffScreenPos(camX, camY, viewW, viewH)
                    spot.alive        = true
                    spot.flashTimer   = 0
                    spot.respawnTimer = 0
                    spot.phase        = math.random() * 6.28
                    print(string.format("[SpecialTerrain] Respawned '%s' at (%.0f, %.0f)",
                        spot.def.name, spot.x, spot.y))
                end
            end
        end
    end

    -- ── 2. Buff 倒计时 ────────────────────────────────
    local b = SpecialTerrain.buffs

    if b.atkTimer > 0 then
        b.atkTimer = b.atkTimer - dt
        if b.atkTimer <= 0 then b.atkMult = 1.0; b.atkTimer = 0 end
    end
    if b.speedTimer > 0 then
        b.speedTimer = b.speedTimer - dt
        if b.speedTimer <= 0 then b.speedMult = 1.0; b.speedTimer = 0 end
    end
    if b.attackRateTimer > 0 then
        b.attackRateTimer = b.attackRateTimer - dt
        if b.attackRateTimer <= 0 then b.attackRateMult = 1.0; b.attackRateTimer = 0 end
    end
    if b.magnetTimer > 0 then
        b.magnetTimer = b.magnetTimer - dt
        if b.magnetTimer <= 0 then b.magnetMult = 1.0; b.magnetTimer = 0 end
    end
    if b.invincTimer > 0 then
        b.invincTimer = b.invincTimer - dt
        if b.invincTimer <= 0 then
            b.invincTimer = 0
        else
            -- 每帧续期玩家无敌时间，防止被普通受击帧重置
            if playerRef and playerRef.invTimer and playerRef.invTimer < b.invincTimer then
                playerRef.invTimer = b.invincTimer
            end
        end
    end
end

--- 内部：应用奖励
function SpecialTerrain._ApplyReward(def, playerRef, onExpGain, onSkillUp, onBomb, onCoin)
    local b   = SpecialTerrain.buffs
    local r   = def.reward
    local val = def.rewardVal

    if r == "heal" then
        if playerRef then
            local amt = math.floor(playerRef.maxHp * val)
            playerRef.hp = math.min(playerRef.maxHp, playerRef.hp + amt)
        end

    elseif r == "exp" then
        if onExpGain then onExpGain(val) end

    elseif r == "exp_coin" then
        if onExpGain then onExpGain(val) end
        if onCoin    then onCoin(math.floor(val * 0.4)) end

    elseif r == "atk_buff" then
        b.atkMult  = 1.25
        b.atkTimer = val

    elseif r == "speed_buff" then
        b.speedMult  = 1.30
        b.speedTimer = val

    elseif r == "attack_rate_buff" then
        b.attackRateMult  = 0.80    -- 攻击间隔×0.8 → 攻速+20%
        b.attackRateTimer = val

    elseif r == "magnet_buff" then
        b.magnetMult  = 3.0
        b.magnetTimer = val

    elseif r == "bomb" then
        if onBomb then onBomb() end

    elseif r == "skill_up" then
        if onSkillUp then onSkillUp() end

    elseif r == "star_burst" then
        -- 无敌：通过持续给 Player.invTimer 续期实现
        b.invincTimer = val
        if playerRef then playerRef.invTimer = val + 0.1 end
        -- 全屏AOE 通过 onBomb 回调触发
        if onBomb then onBomb() end
    end

    print("[SpecialTerrain] Reward applied: " .. def.name .. " → " .. r)
end

--- 渲染所有地形点
---@param vg        userdata
---@param camX      number
---@param camY      number
---@param viewW     number
---@param viewH     number
---@param totalTime number
function SpecialTerrain.Render(vg, camX, camY, viewW, viewH, totalTime)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for _, spot in ipairs(SpecialTerrain.spots) do
        local sx = spot.x - camX
        local sy = spot.y - camY

        -- 视口裁切
        if sx > -80 and sx < viewW + 80 and sy > -80 and sy < viewH + 80 then
            local def   = spot.def
            local alive = spot.alive
            local flash = spot.flashTimer
            local t     = totalTime + spot.phase

            if alive then
                -- 脉动光圈
                local pulse = 0.5 + 0.5 * math.sin(t * PULSE_SPEED)
                local ringR = def.radius * (0.85 + 0.20 * pulse)
                local alpha = math.floor(120 + 80 * pulse)
                local c     = def.color

                -- 外圈光晕
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, ringR)
                nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
                nvgStrokeWidth(vg, 2.5)
                nvgStroke(vg)

                -- 内部半透明填充
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, ringR * 0.7)
                nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 30))
                nvgFill(vg)

                -- 浮动 emoji
                local floatY = math.sin(t * FLOAT_SPEED) * FLOAT_AMP
                nvgFontSize(vg, 28)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
                nvgText(vg, sx, sy + floatY - 4, def.emoji)

                -- 名称标签（emoji 下方）
                nvgFontSize(vg, 11)
                nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 200))
                nvgText(vg, sx, sy + floatY + 18, def.name)

            elseif flash > 0 then
                -- 领取闪光：向外扩散的圆圈
                local progress = 1.0 - flash / 0.6
                local flashR   = def.radius * (1.0 + 1.5 * progress)
                local flashA   = math.floor(200 * (1.0 - progress))
                local c        = def.color
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, flashR)
                nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], flashA))
                nvgStrokeWidth(vg, 3)
                nvgStroke(vg)

                -- 描述文字淡出
                nvgFontSize(vg, 13)
                nvgFillColor(vg, nvgRGBA(255, 255, 220, flashA))
                nvgText(vg, sx, sy - 30, def.desc)
            end
        end
    end
end

--- 小地图标记
---@return table  { {x, y, emoji, color} ... }
function SpecialTerrain.GetMinimapMarkers()
    local markers = {}
    for _, spot in ipairs(SpecialTerrain.spots) do
        if spot.alive then
            markers[#markers + 1] = {
                x     = spot.x,
                y     = spot.y,
                emoji = spot.def.emoji,
                color = spot.def.color,
            }
        end
    end
    return markers
end

-- ============================================================================
-- Buff 查询 API
-- ============================================================================

function SpecialTerrain.GetAtkMult()
    return SpecialTerrain.buffs.atkMult
end

function SpecialTerrain.GetSpeedMult()
    return SpecialTerrain.buffs.speedMult
end

--- 攻击间隔乘数（< 1.0 = 攻速提升）
function SpecialTerrain.GetAttackRateMult()
    return SpecialTerrain.buffs.attackRateMult
end

function SpecialTerrain.GetMagnetMult()
    return SpecialTerrain.buffs.magnetMult
end

function SpecialTerrain.IsInvincible()
    return SpecialTerrain.buffs.invincTimer > 0
end

--- 获取当前激活的 buff 列表（供 HUD 显示）
---@return table  { {icon, name, timer} ... }
function SpecialTerrain.GetActiveBuffInfo()
    local list = {}
    local b    = SpecialTerrain.buffs
    if b.atkTimer > 0 then
        list[#list + 1] = { icon = "⚔️", name = "攻击+25%", timer = b.atkTimer }
    end
    if b.speedTimer > 0 then
        list[#list + 1] = { icon = "💨", name = "移速+30%", timer = b.speedTimer }
    end
    if b.attackRateTimer > 0 then
        list[#list + 1] = { icon = "⚡", name = "攻速+20%", timer = b.attackRateTimer }
    end
    if b.magnetTimer > 0 then
        list[#list + 1] = { icon = "🧲", name = "磁力×3", timer = b.magnetTimer }
    end
    if b.invincTimer > 0 then
        list[#list + 1] = { icon = "⭐", name = "无敌", timer = b.invincTimer }
    end
    return list
end

return SpecialTerrain
