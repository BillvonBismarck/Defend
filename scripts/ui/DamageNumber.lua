--- ============================================================================
--- 伤害跳字 / 数值浮字 模块
--- 白边黑字像素风格，支持多种类型（伤害、暴击、回血、经验、拾取等）
--- ============================================================================

local DamageNumber = {}

-- 对象池
DamageNumber.pool = {}
DamageNumber.active = {}

-- zpix 字体 ID（由 main.lua 初始化后设置）
DamageNumber.fontId = -1

-- ============================================================================
-- 跳字类型预设
-- ============================================================================

---@class DmgNumStyle
---@field fillColor table {r,g,b,a}
---@field strokeColor table {r,g,b,a}
---@field fontSize number
---@field lifetime number
---@field riseSpeed number 上浮速度（像素/秒）
---@field scalePunch number 初始放大倍率

DamageNumber.STYLES = {
    --- 普通伤害：白边黑字
    damage = {
        fillColor   = { 30, 30, 30, 255 },
        strokeColor = { 255, 255, 255, 255 },
        fontSize    = 26,
        lifetime    = 0.8,
        riseSpeed   = 60,
        scalePunch  = 1.3,
    },
    --- 暴击伤害：白边红字 + 更大
    crit = {
        fillColor   = { 220, 30, 30, 255 },
        strokeColor = { 255, 255, 255, 255 },
        fontSize    = 36,
        lifetime    = 1.0,
        riseSpeed   = 80,
        scalePunch  = 1.6,
    },
    --- 回血：白边绿字
    heal = {
        fillColor   = { 30, 200, 60, 255 },
        strokeColor = { 255, 255, 255, 255 },
        fontSize    = 26,
        lifetime    = 0.9,
        riseSpeed   = 55,
        scalePunch  = 1.2,
    },
    --- 经验拾取：白边蓝字
    exp = {
        fillColor   = { 60, 120, 255, 255 },
        strokeColor = { 255, 255, 255, 255 },
        fontSize    = 22,
        lifetime    = 0.6,
        riseSpeed   = 50,
        scalePunch  = 1.2,
    },
    --- 特殊拾取（磁铁/炸弹/金币）：白边金字
    pickup = {
        fillColor   = { 255, 200, 30, 255 },
        strokeColor = { 255, 255, 255, 255 },
        fontSize    = 24,
        lifetime    = 0.9,
        riseSpeed   = 55,
        scalePunch  = 1.3,
    },
    --- 升级：白边紫字
    levelup = {
        fillColor   = { 180, 50, 255, 255 },
        strokeColor = { 255, 255, 255, 255 },
        fontSize    = 38,
        lifetime    = 1.2,
        riseSpeed   = 40,
        scalePunch  = 1.8,
    },
    --- 冰冻伤害：白边蓝字
    frozen = {
        fillColor   = { 80, 180, 255, 255 },
        strokeColor = { 255, 255, 255, 255 },
        fontSize    = 28,
        lifetime    = 0.9,
        riseSpeed   = 65,
        scalePunch  = 1.4,
    },
}

-- ============================================================================
-- 对象池
-- ============================================================================

local function GetFromPool()
    local n = table.remove(DamageNumber.pool)
    if n then return n end
    return {
        x = 0, y = 0,          -- 世界坐标
        text = "",
        style = "damage",
        timer = 0,
        lifetime = 0,
        riseSpeed = 0,
        scalePunch = 1.0,
        offsetX = 0,            -- 随机水平偏移（避免重叠）
        alive = false,
    }
end

local function Recycle(n)
    n.alive = false
    table.insert(DamageNumber.pool, n)
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 重置所有跳字
function DamageNumber.Reset()
    for i = #DamageNumber.active, 1, -1 do
        Recycle(DamageNumber.active[i])
        table.remove(DamageNumber.active, i)
    end
end

-- 跳字数量上限
local MAX_ACTIVE = 40
-- 合并距离平方（30px 内同类型合并）
local MERGE_DIST_SQ = 30 * 30
-- 合并窗口：只对生存时间 < 0.2s 的跳字合并
local MERGE_TIME_WINDOW = 0.2

--- 生成一个跳字
---@param worldX number 世界坐标X
---@param worldY number 世界坐标Y
---@param text string 显示内容（如 "-120"、"+15%HP"）
---@param styleName string 样式名称（见 STYLES 表）
function DamageNumber.Spawn(worldX, worldY, text, styleName)
    local s = DamageNumber.STYLES[styleName or "damage"]
    if not s then s = DamageNumber.STYLES.damage end

    -- 超上限时，尝试合并到附近同类型跳字
    if #DamageNumber.active >= MAX_ACTIVE then
        -- 寻找附近的同类型新跳字进行合并
        local sn = styleName or "damage"
        for _, existing in ipairs(DamageNumber.active) do
            if existing.alive and existing.style == sn and existing.timer < MERGE_TIME_WINDOW then
                local ddx = existing.x - worldX
                local ddy = existing.y - worldY
                if ddx * ddx + ddy * ddy < MERGE_DIST_SQ then
                    -- 合并：累加数值
                    local oldVal = tonumber(existing.text) or 0
                    local newVal = tonumber(text) or 0
                    if oldVal > 0 and newVal > 0 then
                        existing.text = tostring(math.floor(oldVal + newVal))
                        existing.timer = 0  -- 重置动画
                        existing.comboCount = (existing.comboCount or 1) + 1
                        return  -- 合并成功，不新建
                    end
                end
            end
        end
        -- 合并失败，丢弃此跳字（不超过上限）
        return
    end

    local n = GetFromPool()
    n.x = worldX
    n.y = worldY
    n.text = text
    n.style = styleName or "damage"
    n.timer = 0
    n.lifetime = s.lifetime
    n.riseSpeed = s.riseSpeed
    n.scalePunch = s.scalePunch
    n.offsetX = (math.random() - 0.5) * 24  -- 随机水平偏移 ±12px
    n.alive = true
    n.comboCount = 1

    table.insert(DamageNumber.active, n)
end

--- 便捷方法：生成伤害数字
---@param worldX number
---@param worldY number
---@param damage number 伤害值
---@param isCrit boolean 是否暴击
---@param isFrozen boolean|nil 是否冰冻加成伤害（蓝色）
function DamageNumber.SpawnDamage(worldX, worldY, damage, isCrit, isFrozen)
    local text = tostring(math.floor(damage))
    local style
    if isFrozen then
        style = "frozen"
    elseif isCrit then
        style = "crit"
    else
        style = "damage"
    end
    DamageNumber.Spawn(worldX, worldY, text, style)
end

--- 更新所有跳字
function DamageNumber.Update(dt)
    for i = #DamageNumber.active, 1, -1 do
        local n = DamageNumber.active[i]
        if not n.alive then
            table.remove(DamageNumber.active, i)
            Recycle(n)
        else
            n.timer = n.timer + dt
            if n.timer >= n.lifetime then
                n.alive = false
            end
        end
    end
end

--- 渲染所有跳字（白边黑字像素风格）
---@param vg userdata NanoVG 上下文
---@param camX number 相机X
---@param camY number 相机Y
---@param viewW number 视口宽
---@param viewH number 视口高
function DamageNumber.Render(vg, camX, camY, viewW, viewH)
    if DamageNumber.fontId < 0 then return end

    nvgFontFaceId(vg, DamageNumber.fontId)

    for _, n in ipairs(DamageNumber.active) do
        if n.alive then
            local s = DamageNumber.STYLES[n.style] or DamageNumber.STYLES.damage
            local t = n.timer / n.lifetime   -- 归一化进度 0→1

            -- 屏幕坐标
            local sx = n.x - camX + n.offsetX
            local sy = n.y - camY - n.riseSpeed * n.timer  -- 向上浮动

            -- 视野裁剪
            if sx < -80 or sx > viewW + 80 or sy < -60 or sy > viewH + 60 then
                goto continue
            end

            -- 缩放动画：先放大后回弹
            local scaleAnim
            if t < 0.15 then
                -- 弹出阶段：线性到 scalePunch
                scaleAnim = 1.0 + (n.scalePunch - 1.0) * (t / 0.15)
            elseif t < 0.35 then
                -- 回弹阶段：scalePunch → 1.0
                local bt = (t - 0.15) / 0.20
                scaleAnim = n.scalePunch + (1.0 - n.scalePunch) * bt
            else
                scaleAnim = 1.0
            end

            -- 淡出（最后 30%）
            local alpha = 1.0
            if t > 0.7 then
                alpha = 1.0 - (t - 0.7) / 0.3
            end

            local finalSize = s.fontSize * scaleAnim
            local fc = s.fillColor
            local sc = s.strokeColor
            local a = math.floor(alpha * 255)
            local strokeA = math.floor(alpha * sc[4])
            local fillA = math.floor(alpha * fc[4])

            nvgFontSize(vg, finalSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

            -- ====== 白边（描边模拟：8方向偏移绘制） ======
            local strokeW = 2.0
            nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], strokeA))
            for _, off in ipairs({
                { -strokeW, 0 }, { strokeW, 0 },
                { 0, -strokeW }, { 0, strokeW },
                { -strokeW, -strokeW }, { strokeW, -strokeW },
                { -strokeW, strokeW },  { strokeW, strokeW },
            }) do
                nvgText(vg, sx + off[1], sy + off[2], n.text)
            end

            -- ====== 内填充 ======
            nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], fillA))
            nvgText(vg, sx, sy, n.text)

            ::continue::
        end
    end
end

-- ============================================================================
-- HUD 工具函数：用白边黑字风格绘制任意文本
-- ============================================================================

--- 用白边字风格绘制文本（不依赖对象池，直接绘制）
---@param vg userdata
---@param x number 绘制坐标X
---@param y number 绘制坐标Y
---@param text string 文本
---@param fontSize number 字号
---@param fillR number 填充色R
---@param fillG number 填充色G
---@param fillB number 填充色B
---@param fillA number|nil 填充色A（默认255）
---@param strokeW number|nil 描边宽度（默认1.5）
function DamageNumber.DrawOutlinedText(vg, x, y, text, fontSize, fillR, fillG, fillB, fillA, strokeW)
    fillA = fillA or 255
    strokeW = strokeW or 1.5

    nvgFontFaceId(vg, DamageNumber.fontId)
    nvgFontSize(vg, fontSize)

    -- 白色描边（8方向）
    nvgFillColor(vg, nvgRGBA(255, 255, 255, fillA))
    for _, off in ipairs({
        { -strokeW, 0 }, { strokeW, 0 },
        { 0, -strokeW }, { 0, strokeW },
        { -strokeW, -strokeW }, { strokeW, -strokeW },
        { -strokeW, strokeW },  { strokeW, strokeW },
    }) do
        nvgText(vg, x + off[1], y + off[2], text)
    end

    -- 内填充
    nvgFillColor(vg, nvgRGBA(fillR, fillG, fillB, fillA))
    nvgText(vg, x, y, text)
end

return DamageNumber
