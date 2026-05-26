--- ============================================================================
--- 伤害统计模块 - 追踪各技能/来源的伤害数据 + NanoVG 饼图渲染
--- ============================================================================

local Config = require("Config")

local DamageStats = {}

--- 当前伤害来源标记（在调用 Enemy.Damage 前设置）
--- "basic" = 基础射击, 技能ID = 技能伤害, "rune" = 符文效果
DamageStats._currentSource = "basic"

--- 累计伤害数据 { [source] = totalDamage }
local dmgData = {}

--- 总伤害
local totalDmg = 0

--- 记录一次伤害
---@param source string 伤害来源标识
---@param amount number 实际伤害量
function DamageStats.Record(source, amount)
    if amount <= 0 then return end
    local src = source or "basic"
    dmgData[src] = (dmgData[src] or 0) + amount
    totalDmg = totalDmg + amount
end

--- 重置统计（新局开始时调用）
function DamageStats.Reset()
    dmgData = {}
    totalDmg = 0
    DamageStats._currentSource = "basic"
end

--- 获取排序后的伤害数据（降序）
---@return table[] { {source, damage, percent} }
function DamageStats.GetSorted()
    if totalDmg <= 0 then return {} end
    local result = {}
    for src, dmg in pairs(dmgData) do
        result[#result + 1] = {
            source  = src,
            damage  = dmg,
            percent = dmg / totalDmg,
        }
    end
    table.sort(result, function(a, b) return a.damage > b.damage end)
    return result
end

--- 获取总伤害
function DamageStats.GetTotal()
    return totalDmg
end

--- 获取来源数量
function DamageStats.GetSourceCount()
    local n = 0
    for _ in pairs(dmgData) do n = n + 1 end
    return n
end

-- ============================================================================
-- 渲染：NanoVG 饼图
-- ============================================================================

--- 配色方案（最多显示前8个来源，其余合并为"其他"）
local COLORS = {
    { 255,  90,  90 },  -- 红
    {  80, 180, 255 },  -- 蓝
    { 100, 220, 100 },  -- 绿
    { 255, 200,  60 },  -- 黄
    { 200, 130, 255 },  -- 紫
    { 255, 150,  60 },  -- 橙
    {  80, 220, 220 },  -- 青
    { 255, 130, 200 },  -- 粉
}

local MAX_SLICES = 8

--- 获取来源的显示名称和图标
---@param source string
---@return string icon, string name
local function GetSourceDisplay(source)
    if source == "basic" then
        return "🔫", "基础射击"
    elseif source == "rune" then
        return "🔮", "符文效果"
    else
        -- 从 Config.SKILLS 查找技能信息
        local skill = Config.GetSkillBySid and Config.GetSkillBySid(source)
        if skill then
            return skill.icon or "⚔️", skill.name or source
        end
        return "⚔️", source
    end
end

--- 格式化大数字
local function FormatNumber(n)
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 10000 then
        return string.format("%.1fW", n / 10000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return tostring(math.floor(n))
end

--- 渲染饼图到指定区域
---@param vg userdata NanoVG context
---@param cx number 饼图圆心X
---@param cy number 饼图圆心Y
---@param radius number 饼图半径
---@param font number 主字体ID（emoji）
---@param textFont number 文字字体ID
function DamageStats.RenderPieChart(vg, cx, cy, radius, font, textFont)
    local sorted = DamageStats.GetSorted()
    if #sorted == 0 then return 0 end

    -- 合并超过 MAX_SLICES 的项为 "其他"
    local slices = {}
    local otherDmg = 0
    for i, entry in ipairs(sorted) do
        if i <= MAX_SLICES then
            slices[#slices + 1] = entry
        else
            otherDmg = otherDmg + entry.damage
        end
    end
    if otherDmg > 0 then
        slices[#slices + 1] = {
            source  = "_other",
            damage  = otherDmg,
            percent = otherDmg / totalDmg,
        }
    end

    local PI2 = math.pi * 2
    local startAngle = -math.pi / 2  -- 从12点方向开始

    -- 绘制饼图扇区
    for i, slice in ipairs(slices) do
        local sweepAngle = slice.percent * PI2
        local endAngle = startAngle + sweepAngle
        local c = COLORS[((i - 1) % #COLORS) + 1]

        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy)
        nvgArc(vg, cx, cy, radius, startAngle, endAngle, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 220))
        nvgFill(vg)

        -- 扇区边线（白色细线分隔）
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 180))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 扇区内标注百分比（>8% 才显示）
        if slice.percent > 0.08 then
            local midAngle = startAngle + sweepAngle / 2
            local labelR = radius * 0.62
            local lx = cx + math.cos(midAngle) * labelR
            local ly = cy + math.sin(midAngle) * labelR
            nvgFontFaceId(vg, textFont)
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, lx, ly, math.floor(slice.percent * 100) .. "%")
        end

        startAngle = endAngle
    end

    -- 中心圆（镂空效果 = 甜甜圈图，暗色面板用深色底）
    local innerR = radius * 0.38
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, innerR)
    nvgFillColor(vg, nvgRGBA(20, 18, 40, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 90, 130, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 中心文字：总伤害（浅色适配暗底面板）
    nvgFontFaceId(vg, textFont)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(160, 170, 200, 200))
    nvgText(vg, cx, cy - 10, "总伤害")
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(220, 225, 240, 255))
    nvgText(vg, cx, cy + 10, FormatNumber(totalDmg))

    -- 右侧图例（紧凑布局，避免重叠）
    local legendLineH = 22
    local legendX = cx + radius + 14
    local legendY = cy - (#slices * legendLineH) / 2
    for i, slice in ipairs(slices) do
        local c = COLORS[((i - 1) % #COLORS) + 1]
        local ly = legendY + (i - 1) * legendLineH

        -- 色块
        nvgBeginPath(vg)
        nvgRoundedRect(vg, legendX, ly - 5, 10, 10, 2)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 220))
        nvgFill(vg)

        -- 图标 + 名称
        local icon, name
        if slice.source == "_other" then
            icon, name = "📦", "其他"
        else
            icon, name = GetSourceDisplay(slice.source)
        end
        -- 截断过长名称（最多4个中文字符）
        local nameLen = #name
        if nameLen > 12 then  -- UTF-8 中文约3字节/字
            name = name:sub(1, 12) .. "…"
        end

        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        -- emoji图标（用主字体渲染emoji）
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(220, 225, 240, 230))
        local iconAdvance = nvgText(vg, legendX + 14, ly, icon)

        -- 名称 + 百分比（zpix字体）
        nvgFontFaceId(vg, textFont)
        nvgFontSize(vg, 13)
        local pctStr = math.floor(slice.percent * 100) .. "%"
        nvgText(vg, iconAdvance + 2, ly, name .. " " .. pctStr)
    end

    -- 返回图例区域使用的总高度
    return math.max(radius * 2, #slices * legendLineH)
end

return DamageStats
