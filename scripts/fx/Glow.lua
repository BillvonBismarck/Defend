--- ============================================================================
--- Bloom/Glow 渲染模块 - 基于 NanoVG 径向渐变模拟 HDR 发光
--- 性能友好：单层渐变，仅在 brightness > 1.0 时绘制 bloom
--- ============================================================================

local Glow = {}

-- ============================================================================
-- Bloom 常量（可全局调节发光强度）
-- ============================================================================
Glow.BLOOM_INNER_ALPHA = 0.45   -- 中心亮度
Glow.BLOOM_MID_ALPHA   = 0.6    -- 中间层比例
Glow.BLOOM_OUTER_ALPHA = 0.1    -- 外缘残光
Glow.BLOOM_SIZE        = 2.0    -- 光晕扩散倍数

--- 是否启用 bloom（全局开关，可用于低端设备降级）
Glow.enabled = false

-- 每帧 bloom 绘制计数器（性能监控）
Glow._drawCount = 0

--- 每帧开始时重置计数器
function Glow.BeginFrame()
    Glow._drawCount = 0
end

--- 获取本帧 bloom 绘制次数
function Glow.GetDrawCount()
    return Glow._drawCount
end

-- ============================================================================
-- 核心绘制函数
-- ============================================================================

--- 绘制圆形 Bloom 光晕（单层径向渐变，性能最优）
--- @param ctx userdata NanoVG 上下文
--- @param x number 屏幕坐标 X
--- @param y number 屏幕坐标 Y
--- @param radius number 物体半径
--- @param r number HDR 红（可 >1.0）
--- @param g number HDR 绿
--- @param b number HDR 蓝
--- @param alphaScale number|nil 整体透明度缩放（0~1，默认1）
function Glow.DrawCircleBloom(ctx, x, y, radius, r, g, b, alphaScale)
    if not Glow.enabled then return end
    local scale = alphaScale or 1.0
    local alpha = Glow.BLOOM_INNER_ALPHA * scale

    local innerR = radius * Glow.BLOOM_MID_ALPHA * 0.5
    local maxRadius = radius * Glow.BLOOM_SIZE * (1.0 + Glow.BLOOM_OUTER_ALPHA * 3.0)

    nvgBeginPath(ctx)
    nvgCircle(ctx, x, y, maxRadius)
    local grad = nvgRadialGradient(ctx, x, y, innerR, maxRadius,
        nvgRGBAf(r, g, b, alpha),
        nvgRGBAf(r, g, b, 0))
    nvgFillPaint(ctx, grad)
    nvgFill(ctx)

    Glow._drawCount = Glow._drawCount + 1
end

--- 绘制带 Bloom 的发光圆形（bloom + 实心圆）
--- brightness > 1.0 时自动添加 bloom 光晕
--- @param ctx userdata NanoVG 上下文
--- @param x number 屏幕坐标 X
--- @param y number 屏幕坐标 Y
--- @param radius number 圆半径
--- @param r number 基础红 (0~1)
--- @param g number 基础绿 (0~1)
--- @param b number 基础蓝 (0~1)
--- @param brightness number 亮度倍数（>1.0 触发 bloom）
--- @param alpha number|nil 实心圆透明度（0~1，默认1）
function Glow.DrawGlowingCircle(ctx, x, y, radius, r, g, b, brightness, alpha)
    local a = alpha or 1.0

    -- HDR 颜色
    local hdrR = r * brightness
    local hdrG = g * brightness
    local hdrB = b * brightness

    -- brightness > 1.0 才绘制 bloom
    if brightness > 1.0 and Glow.enabled then
        Glow.DrawCircleBloom(ctx, x, y, radius, hdrR, hdrG, hdrB, a)
    end

    -- 实心圆（颜色 clamp 到 0~1）
    nvgBeginPath(ctx)
    nvgCircle(ctx, x, y, radius)
    nvgFillColor(ctx, nvgRGBAf(
        math.min(1, hdrR),
        math.min(1, hdrG),
        math.min(1, hdrB),
        a
    ))
    nvgFill(ctx)
end

--- 绘制矩形 Bloom 光晕（BoxGradient）
--- @param ctx userdata NanoVG 上下文
--- @param x number 左上角 X
--- @param y number 左上角 Y
--- @param w number 宽度
--- @param h number 高度
--- @param r number HDR 红
--- @param g number HDR 绿
--- @param b number HDR 蓝
--- @param alphaScale number|nil 整体透明度缩放
function Glow.DrawRectBloom(ctx, x, y, w, h, r, g, b, alphaScale)
    if not Glow.enabled then return end
    local scale = alphaScale or 1.0
    local alpha = Glow.BLOOM_INNER_ALPHA * scale

    local blur = math.max(w, h) * Glow.BLOOM_SIZE * 0.5
    local expand = blur * 0.8

    nvgBeginPath(ctx)
    nvgRect(ctx, x - expand, y - expand, w + expand * 2, h + expand * 2)
    local grad = nvgBoxGradient(ctx, x, y, w, h, 0, blur,
        nvgRGBAf(r, g, b, alpha),
        nvgRGBAf(r, g, b, 0))
    nvgFillPaint(ctx, grad)
    nvgFill(ctx)

    Glow._drawCount = Glow._drawCount + 1
end

--- 绘制带 Bloom 的发光矩形
--- @param ctx userdata NanoVG 上下文
--- @param x number 左上角 X
--- @param y number 左上角 Y
--- @param w number 宽度
--- @param h number 高度
--- @param r number 基础红 (0~1)
--- @param g number 基础绿 (0~1)
--- @param b number 基础蓝 (0~1)
--- @param brightness number 亮度倍数
--- @param cornerRadius number|nil 圆角半径（默认0）
function Glow.DrawGlowingRect(ctx, x, y, w, h, r, g, b, brightness, cornerRadius)
    local cr = cornerRadius or 0

    local hdrR = r * brightness
    local hdrG = g * brightness
    local hdrB = b * brightness

    if brightness > 1.0 and Glow.enabled then
        Glow.DrawRectBloom(ctx, x, y, w, h, hdrR, hdrG, hdrB)
    end

    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, x, y, w, h, cr)
    nvgFillColor(ctx, nvgRGBAf(
        math.min(1, hdrR),
        math.min(1, hdrG),
        math.min(1, hdrB),
        1.0
    ))
    nvgFill(ctx)
end

-- ============================================================================
-- 便捷函数（基于 0~255 颜色值）
-- ============================================================================

--- 绘制圆形 Bloom（颜色 0~255）
--- @param ctx userdata
--- @param x number
--- @param y number
--- @param radius number
--- @param r255 number 红 (0~255)
--- @param g255 number 绿 (0~255)
--- @param b255 number 蓝 (0~255)
--- @param alpha255 number|nil 透明度 (0~255，默认255)
function Glow.DrawCircleBloom255(ctx, x, y, radius, r255, g255, b255, alpha255)
    if not Glow.enabled then return end
    local a = (alpha255 or 255) / 255
    Glow.DrawCircleBloom(ctx, x, y, radius, r255 / 255, g255 / 255, b255 / 255, a)
end

--- 绘制发光圆形（颜色 0~255 + brightness）
--- @param ctx userdata
--- @param x number
--- @param y number
--- @param radius number
--- @param r255 number 红 (0~255)
--- @param g255 number 绿 (0~255)
--- @param b255 number 蓝 (0~255)
--- @param brightness number 亮度倍数（>1.0 触发 bloom）
--- @param alpha255 number|nil 透明度 (0~255，默认255)
function Glow.DrawGlowingCircle255(ctx, x, y, radius, r255, g255, b255, brightness, alpha255)
    local a = (alpha255 or 255) / 255
    Glow.DrawGlowingCircle(ctx, x, y, radius, r255 / 255, g255 / 255, b255 / 255, brightness, a)
end

-- ============================================================================
-- 游戏专用封装
-- ============================================================================

--- 绘制霓虹脉冲发光（适用于玩家光晕、精英敌人光环）
--- 自动以时间驱动脉冲亮度
--- @param ctx userdata
--- @param x number
--- @param y number
--- @param radius number 基础半径
--- @param r255 number
--- @param g255 number
--- @param b255 number
--- @param baseAlpha number 基础透明度 (0~255)
--- @param pulseSpeed number|nil 脉冲速度（默认3.0）
--- @param bloomRadius number|nil 光晕额外半径（默认 radius*0.5）
function Glow.DrawNeonPulse(ctx, x, y, radius, r255, g255, b255, baseAlpha, pulseSpeed, bloomRadius)
    if not Glow.enabled then return end
    local speed = pulseSpeed or 3.0
    local extra = bloomRadius or (radius * 0.5)
    local t = time and time.elapsedTime or 0
    local pulse = 0.6 + 0.4 * math.sin(t * speed)
    local alpha = (baseAlpha / 255) * pulse
    local glowR = radius + extra * pulse

    Glow.DrawCircleBloom(ctx, x, y, glowR, r255 / 255, g255 / 255, b255 / 255, alpha)
end

--- 绘制光柱（适用于稀有掉落、传送点、Boss出场）
--- @param ctx userdata
--- @param x number 中心 X
--- @param bottomY number 底部 Y
--- @param width number 光柱宽度
--- @param height number 光柱高度（向上延伸）
--- @param r255 number
--- @param g255 number
--- @param b255 number
--- @param alpha number 透明度 (0~1)
function Glow.DrawLightPillar(ctx, x, bottomY, width, height, r255, g255, b255, alpha)
    if not Glow.enabled then return end
    local r = r255 / 255
    local g = g255 / 255
    local b = b255 / 255

    -- 底部圆形光源
    Glow.DrawCircleBloom(ctx, x, bottomY, width * 0.6, r, g, b, alpha * 0.8)

    -- 光柱主体（渐变矩形）
    local topY = bottomY - height
    nvgBeginPath(ctx)
    -- 梯形：底宽 → 顶窄
    local halfW = width * 0.5
    local topHalfW = halfW * 0.3
    nvgMoveTo(ctx, x - halfW, bottomY)
    nvgLineTo(ctx, x - topHalfW, topY)
    nvgLineTo(ctx, x + topHalfW, topY)
    nvgLineTo(ctx, x + halfW, bottomY)
    nvgClosePath(ctx)

    local grad = nvgLinearGradient(ctx, x, bottomY, x, topY,
        nvgRGBAf(r, g, b, alpha * 0.5),
        nvgRGBAf(r, g, b, 0))
    nvgFillPaint(ctx, grad)
    nvgFill(ctx)

    Glow._drawCount = Glow._drawCount + 1
end

return Glow
