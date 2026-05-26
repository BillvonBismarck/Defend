--- ============================================================================
--- 粒子特效系统 - 对象池 + 多种预设
--- ============================================================================

local Glow = require("fx.Glow")
local FPSMonitor = require("utils.FPSMonitor")
local PerfQuality = require("utils.PerfQuality")

local Particle = {}

-- 对象池
local pool = {}
local active = {}

-- 动态粒子上限（联动 FPSMonitor）
local MAX_PARTICLES_BASE    = 300   -- 正常上限
local MAX_PARTICLES_DEGRADED = 120  -- 降级上限
local MAX_PARTICLES = MAX_PARTICLES_BASE
local _targetMax = MAX_PARTICLES_BASE
local _LERP_SPEED = 100  -- 每秒调整速度

-- Bloom 配置：哪些粒子预设启用 bloom
local BLOOM_PRESETS = {
    crit_hit  = { brightness = 2.0 },    -- 暴击火花：强发光
    elite_die = { brightness = 1.8 },    -- 精英死亡：中强发光
    level_up  = { brightness = 2.2 },    -- 升级爆发：最强发光
    bomb      = { brightness = 1.6 },    -- 炸弹：中等发光
    heal      = { brightness = 1.5 },    -- 治疗：柔和发光
}

-- ============================================================================
-- 预设配置
-- ============================================================================

Particle.PRESETS = {
    --- 子弹命中敌人：小型霓虹火花四散
    hit = {
        count = { 6, 10 },
        speed = { 80, 200 },
        life  = { 0.15, 0.35 },
        size  = { 2, 5 },
        sizeEnd = 0,
        color = { 0, 230, 200 },
        colorVar = 30,
        fadeOut = true,
        gravity = 0,
        drag = 3.0,
        spread = 6.28,       -- 全方向
    },

    --- 暴击命中：更大更亮的火花
    crit_hit = {
        count = { 10, 16 },
        speed = { 120, 280 },
        life  = { 0.2, 0.45 },
        size  = { 3, 7 },
        sizeEnd = 0,
        color = { 255, 220, 50 },
        colorVar = 20,
        fadeOut = true,
        gravity = 0,
        drag = 2.5,
        spread = 6.28,
    },

    --- 敌人死亡：大型爆炸碎片
    enemy_die = {
        count = { 12, 18 },
        speed = { 60, 220 },
        life  = { 0.3, 0.6 },
        size  = { 3, 8 },
        sizeEnd = 0,
        color = { 255, 80, 60 },
        colorVar = 40,
        fadeOut = true,
        gravity = 120,
        drag = 1.5,
        spread = 6.28,
    },

    --- 精英/Boss 死亡：大爆炸 + 多色
    elite_die = {
        count = { 20, 30 },
        speed = { 80, 300 },
        life  = { 0.4, 0.8 },
        size  = { 4, 10 },
        sizeEnd = 0,
        color = { 255, 150, 0 },
        colorVar = 60,
        fadeOut = true,
        gravity = 80,
        drag = 1.2,
        spread = 6.28,
    },

    --- 经验拾取：绿色上升微粒
    exp_pickup = {
        count = { 5, 8 },
        speed = { 30, 80 },
        life  = { 0.3, 0.5 },
        size  = { 2, 4 },
        sizeEnd = 0,
        color = { 100, 255, 100 },
        colorVar = 20,
        fadeOut = true,
        gravity = -100,    -- 向上飘
        drag = 2.0,
        spread = 1.2,      -- 窄锥形向上
        baseAngle = -1.5708, -- -π/2 向上
    },

    --- 升级：紫金爆发
    level_up = {
        count = { 24, 36 },
        speed = { 100, 300 },
        life  = { 0.4, 0.8 },
        size  = { 3, 7 },
        sizeEnd = 1,
        color = { 180, 100, 255 },
        colorVar = 50,
        fadeOut = true,
        gravity = 0,
        drag = 2.0,
        spread = 6.28,
    },

    --- 玩家受伤：红色碎片
    player_hit = {
        count = { 8, 12 },
        speed = { 60, 160 },
        life  = { 0.2, 0.4 },
        size  = { 2, 5 },
        sizeEnd = 0,
        color = { 255, 50, 50 },
        colorVar = 30,
        fadeOut = true,
        gravity = 100,
        drag = 2.0,
        spread = 6.28,
    },

    --- 治疗：绿色心形微粒上浮
    heal = {
        count = { 6, 10 },
        speed = { 20, 60 },
        life  = { 0.4, 0.7 },
        size  = { 2, 4 },
        sizeEnd = 1,
        color = { 50, 255, 100 },
        colorVar = 20,
        fadeOut = true,
        gravity = -80,
        drag = 1.5,
        spread = 3.14,
        baseAngle = -1.5708,
    },

    --- 炸弹：橙红冲击波
    bomb = {
        count = { 30, 40 },
        speed = { 150, 400 },
        life  = { 0.3, 0.6 },
        size  = { 4, 10 },
        sizeEnd = 0,
        color = { 255, 180, 50 },
        colorVar = 40,
        fadeOut = true,
        gravity = 60,
        drag = 1.8,
        spread = 6.28,
    },
}

-- ============================================================================
-- 对象池管理
-- ============================================================================

local function GetParticle()
    local p = table.remove(pool)
    if p then return p end
    return {
        x = 0, y = 0,
        vx = 0, vy = 0,
        life = 0, maxLife = 0,
        size = 0, sizeStart = 0, sizeEnd = 0,
        r = 0, g = 0, b = 0,
        alive = false,
        gravity = 0,
        drag = 0,
        fadeOut = true,
        presetName = nil,   -- 记录预设名（用于 bloom 查表）
    }
end

local function Recycle(p)
    p.alive = false
    p.presetName = nil
    table.insert(pool, p)
end

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 重置所有粒子
function Particle.Reset()
    for i = #active, 1, -1 do
        Recycle(active[i])
        table.remove(active, i)
    end
    MAX_PARTICLES = MAX_PARTICLES_BASE
    _targetMax = MAX_PARTICLES_BASE
end

--- 在世界坐标 (wx, wy) 生成一组粒子
---@param wx number 世界X
---@param wy number 世界Y
---@param presetName string 预设名称
---@param colorOverride table|nil 覆盖颜色 {r,g,b}
function Particle.Spawn(wx, wy, presetName, colorOverride)
    local preset = Particle.PRESETS[presetName]
    if not preset then return end

    -- 性能档控制：按比例缩减粒子数量
    local pscale = PerfQuality.ParticleScale()
    if pscale <= 0 then return end

    local rawCount = math.random(preset.count[1], preset.count[2])
    local count = math.max(1, math.floor(rawCount * pscale))
    -- 粒子上限保护（MAX_PARTICLES 可能是浮点数，取 floor）
    local cap = math.floor(MAX_PARTICLES)
    if #active + count > cap then
        count = cap - #active
        if count <= 0 then return end
    end

    local baseAngle = preset.baseAngle or 0
    local halfSpread = preset.spread / 2

    local cr = colorOverride and colorOverride[1] or preset.color[1]
    local cg = colorOverride and colorOverride[2] or preset.color[2]
    local cb = colorOverride and colorOverride[3] or preset.color[3]
    local cv = preset.colorVar

    local bloomCfg = BLOOM_PRESETS[presetName]

    for _ = 1, count do
        local p = GetParticle()
        p.alive = true
        p.presetName = bloomCfg and presetName or nil

        -- 位置
        p.x = wx + (math.random() - 0.5) * 4
        p.y = wy + (math.random() - 0.5) * 4

        -- 方向和速度
        local angle = baseAngle + (math.random() - 0.5) * 2 * halfSpread
        local speed = preset.speed[1] + math.random() * (preset.speed[2] - preset.speed[1])
        p.vx = math.cos(angle) * speed
        p.vy = math.sin(angle) * speed

        -- 生命
        p.life = preset.life[1] + math.random() * (preset.life[2] - preset.life[1])
        p.maxLife = p.life

        -- 大小
        p.sizeStart = preset.size[1] + math.random() * (preset.size[2] - preset.size[1])
        p.sizeEnd = preset.sizeEnd or 0
        p.size = p.sizeStart

        -- 颜色（带随机偏移）
        p.r = math.max(0, math.min(255, cr + math.random(-cv, cv)))
        p.g = math.max(0, math.min(255, cg + math.random(-cv, cv)))
        p.b = math.max(0, math.min(255, cb + math.random(-cv, cv)))

        -- 物理
        p.gravity = preset.gravity or 0
        p.drag = preset.drag or 0
        p.fadeOut = preset.fadeOut

        table.insert(active, p)
    end
end

--- 每帧更新
function Particle.Update(dt)
    -- 动态调整粒子上限：降级时目标降低，恢复时目标提高
    _targetMax = FPSMonitor.IsDegraded() and MAX_PARTICLES_DEGRADED or MAX_PARTICLES_BASE
    if MAX_PARTICLES ~= _targetMax then
        local step = _LERP_SPEED * dt
        if MAX_PARTICLES < _targetMax then
            MAX_PARTICLES = math.min(_targetMax, MAX_PARTICLES + step)
        else
            MAX_PARTICLES = math.max(_targetMax, MAX_PARTICLES - step)
        end
    end

    for i = #active, 1, -1 do
        local p = active[i]
        if not p.alive or p.life <= 0 then
            table.remove(active, i)
            Recycle(p)
        else
            -- 物理
            p.vy = p.vy + p.gravity * dt
            p.vx = p.vx * (1 - p.drag * dt)
            p.vy = p.vy * (1 - p.drag * dt)
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt

            -- 生命
            p.life = p.life - dt

            -- 大小插值
            local t = 1 - (p.life / p.maxLife)
            p.size = p.sizeStart + (p.sizeEnd - p.sizeStart) * t
        end
    end
end

--- 渲染所有粒子
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
---@param viewW number 视口宽
---@param viewH number 视口高
function Particle.Render(vg, camX, camY, viewW, viewH)
    for _, p in ipairs(active) do
        if p.alive and p.size > 0.2 then
            local sx = p.x - camX
            local sy = p.y - camY

            -- 视野裁剪
            if sx > -20 and sx < viewW + 20 and sy > -20 and sy < viewH + 20 then
                local alpha = 255
                if p.fadeOut then
                    alpha = math.floor(255 * (p.life / p.maxLife))
                end
                if alpha < 1 then goto continue end

                -- Bloom / 外发光
                local bloomCfg = p.presetName and BLOOM_PRESETS[p.presetName]
                if bloomCfg and p.size > 2 then
                    -- 径向渐变 bloom（视觉更佳）
                    Glow.DrawGlowingCircle255(vg, sx, sy, p.size,
                        p.r, p.g, p.b, bloomCfg.brightness, alpha)
                elseif p.size > 3 then
                    -- 普通粒子仍用简单外发光（性能优先）
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, p.size + 3)
                    nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 0.2)))
                    nvgFill(vg)
                    -- 粒子本体
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, p.size)
                    nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, alpha))
                    nvgFill(vg)
                else
                    -- 小粒子：仅本体
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, p.size)
                    nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, alpha))
                    nvgFill(vg)
                end
            end

            ::continue::
        end
    end
end

--- 获取当前活跃粒子数量（调试用）
function Particle.GetCount()
    return #active
end

--- 获取当前动态粒子上限（调试用）
function Particle.GetMaxParticles()
    return math.floor(MAX_PARTICLES)
end

-- ============================================================================
-- 冲击波环 / 闪光屏 / 激光线 - 独立于粒子的 FX 系统
-- ============================================================================

--- @class ShockWave 冲击波环
--- @field x number 世界坐标
--- @field y number
--- @field radius number 当前半径
--- @field maxRadius number 最大半径
--- @field life number 剩余生命
--- @field maxLife number 总生命
--- @field r number 颜色R
--- @field g number 颜色G
--- @field b number 颜色B
--- @field width number 线宽
--- @field alive boolean

local shockPool = {}
local shockActive = {}

local function GetShock()
    local s = table.remove(shockPool)
    if s then return s end
    return { x=0,y=0, radius=0, maxRadius=0, life=0, maxLife=0, r=0,g=0,b=0, width=3, alive=false }
end

local function RecycleShock(s)
    s.alive = false
    table.insert(shockPool, s)
end

--- 生成一个冲击波环
---@param wx number 世界坐标X
---@param wy number 世界坐标Y
---@param maxRadius number 最大扩散半径
---@param life number 持续时间(秒)
---@param r number 颜色R
---@param g number 颜色G
---@param b number 颜色B
---@param width number|nil 线宽（默认3）
function Particle.SpawnShockWave(wx, wy, maxRadius, life, r, g, b, width)
    if not PerfQuality.ShockwaveEnabled() then return end
    local s = GetShock()
    s.x = wx; s.y = wy
    s.radius = 0; s.maxRadius = maxRadius
    s.life = life; s.maxLife = life
    s.r = r; s.g = g; s.b = b
    s.width = width or 3
    s.alive = true
    table.insert(shockActive, s)
end

--- @class FlashScreen 全屏闪光
local flashActive = {}

--- 触发全屏闪光
---@param r number
---@param g number
---@param b number
---@param duration number 持续时间
---@param maxAlpha number|nil 最大透明度(0~255，默认120)
function Particle.SpawnFlash(r, g, b, duration, maxAlpha)
    if not PerfQuality.FlashEnabled() then return end
    table.insert(flashActive, {
        r = r, g = g, b = b,
        life = duration, maxLife = duration,
        maxAlpha = maxAlpha or 120,
    })
end

--- @class LaserBeam 激光线
local laserActive = {}

--- 生成一条激光线（从A到B，快速淡出）
---@param x1 number 起点世界X
---@param y1 number 起点世界Y
---@param x2 number 终点世界X
---@param y2 number 终点世界Y
---@param life number 持续时间
---@param r number 颜色R
---@param g number 颜色G
---@param b number 颜色B
---@param width number|nil 线宽（默认2）
function Particle.SpawnLaser(x1, y1, x2, y2, life, r, g, b, width)
    table.insert(laserActive, {
        x1=x1, y1=y1, x2=x2, y2=y2,
        life=life, maxLife=life,
        r=r, g=g, b=b, width=width or 2,
    })
end

--- 更新所有 FX（在 Particle.Update 中调用）
local function UpdateFX(dt)
    -- 冲击波
    for i = #shockActive, 1, -1 do
        local s = shockActive[i]
        s.life = s.life - dt
        if s.life <= 0 then
            table.remove(shockActive, i)
            RecycleShock(s)
        else
            local t = 1 - (s.life / s.maxLife)
            s.radius = s.maxRadius * t
        end
    end
    -- 闪光屏
    for i = #flashActive, 1, -1 do
        flashActive[i].life = flashActive[i].life - dt
        if flashActive[i].life <= 0 then
            table.remove(flashActive, i)
        end
    end
    -- 激光线
    for i = #laserActive, 1, -1 do
        laserActive[i].life = laserActive[i].life - dt
        if laserActive[i].life <= 0 then
            table.remove(laserActive, i)
        end
    end
end

--- 渲染所有 FX（在 Particle.Render 中调用）
local function RenderFX(vg, camX, camY, viewW, viewH)
    -- 冲击波环（Bloom 升级）
    for _, s in ipairs(shockActive) do
        local sx = s.x - camX
        local sy = s.y - camY
        local t = 1 - (s.life / s.maxLife)
        local alpha = math.floor(255 * (1 - t))  -- 线性淡出

        -- Bloom 径向渐变光晕（跟随冲击波环扩散）
        if Glow.enabled and s.radius > 5 then
            Glow.DrawCircleBloom255(vg, sx, sy, s.radius * 0.3, s.r, s.g, s.b, math.floor(alpha * 0.4))
        end

        -- 外层辉光
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, s.radius)
        nvgStrokeColor(vg, nvgRGBA(s.r, s.g, s.b, math.floor(alpha * 0.3)))
        nvgStrokeWidth(vg, s.width + 4)
        nvgStroke(vg)

        -- 主环
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, s.radius)
        nvgStrokeColor(vg, nvgRGBA(s.r, s.g, s.b, alpha))
        nvgStrokeWidth(vg, s.width)
        nvgStroke(vg)
    end

    -- 激光线
    for _, l in ipairs(laserActive) do
        local t = 1 - (l.life / l.maxLife)
        local alpha = math.floor(255 * (1 - t * t))  -- 二次淡出
        local sx1 = l.x1 - camX
        local sy1 = l.y1 - camY
        local sx2 = l.x2 - camX
        local sy2 = l.y2 - camY

        -- 外层辉光
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx1, sy1)
        nvgLineTo(vg, sx2, sy2)
        nvgStrokeColor(vg, nvgRGBA(l.r, l.g, l.b, math.floor(alpha * 0.25)))
        nvgStrokeWidth(vg, l.width + 6)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)

        -- 主线
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx1, sy1)
        nvgLineTo(vg, sx2, sy2)
        nvgStrokeColor(vg, nvgRGBA(l.r, l.g, l.b, alpha))
        nvgStrokeWidth(vg, l.width)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)

        -- 中心高亮
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx1, sy1)
        nvgLineTo(vg, sx2, sy2)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 0.6)))
        nvgStrokeWidth(vg, math.max(1, l.width * 0.4))
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    end

    -- 闪光屏（全屏覆盖，最后绘制）
    for _, f in ipairs(flashActive) do
        local t = 1 - (f.life / f.maxLife)
        local alpha = math.floor(f.maxAlpha * (1 - t * t))
        if alpha > 0 then
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, viewW, viewH)
            nvgFillColor(vg, nvgRGBA(f.r, f.g, f.b, alpha))
            nvgFill(vg)
        end
    end
end

-- 重写 Update 和 Render 把 FX 纳入
local _origUpdate = Particle.Update
function Particle.Update(dt)
    _origUpdate(dt)
    UpdateFX(dt)
end

local _origRender = Particle.Render
function Particle.Render(vg, camX, camY, viewW, viewH)
    _origRender(vg, camX, camY, viewW, viewH)
    RenderFX(vg, camX, camY, viewW, viewH)
end

local _origReset = Particle.Reset
function Particle.Reset()
    _origReset()
    for i = #shockActive, 1, -1 do
        RecycleShock(shockActive[i])
        table.remove(shockActive, i)
    end
    flashActive = {}
    laserActive = {}
end

return Particle
