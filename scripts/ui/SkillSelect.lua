--- ============================================================================
--- 技能选择弹窗 - 升级时三选一 UI（NanoVG 渲染）
--- ============================================================================

local Config = require("Config")
local HUD    = require("ui.HUD")
local I18n   = require("utils.I18n")

local SkillSelect = {}

-- 状态
SkillSelect.visible = false
SkillSelect.choices = {}    -- { {def, newLevel, isNew}, ... }
SkillSelect.onSelect = nil  -- function(index) 选择回调

-- 终极奖励状态
SkillSelect.ultimateVisible = false
SkillSelect.onUltimateSelect = nil  -- function(choice) "heal_inv" or "rage"

-- 布局常量（卡片宽度在 Render 时根据 viewW 动态计算）
local CARD_H = 196
local CARD_GAP = 14
local CARD_RADIUS = 14

--- 显示技能选择
function SkillSelect.Show(choices, onSelect)
    SkillSelect.visible = true
    SkillSelect.choices = choices
    SkillSelect.onSelect = onSelect
end

--- 隐藏
function SkillSelect.Hide()
    SkillSelect.visible = false
    SkillSelect.choices = {}
end

--- 处理点击选择
---@param touchX number 设计坐标系的点击X
---@param touchY number 设计坐标系的点击Y
---@param viewW number 设计宽度
---@param viewH number 设计高度
---@return boolean 是否处理了点击
function SkillSelect.HandleTouch(touchX, touchY, viewW, viewH)
    if not SkillSelect.visible then return false end

    local count = #SkillSelect.choices
    if count == 0 then return false end

    -- 计算卡片布局（竖排居中）
    local CARD_W = viewW - 48
    local totalH = count * CARD_H + (count - 1) * CARD_GAP
    local startY = (viewH - totalH) / 2
    local cardX = (viewW - CARD_W) / 2

    for i = 1, count do
        local cy = startY + (i - 1) * (CARD_H + CARD_GAP)
        -- 判断点击是否在卡片内
        if touchX >= cardX and touchX <= cardX + CARD_W and
            touchY >= cy and touchY <= cy + CARD_H then
            -- 选中
            if SkillSelect.onSelect then
                SkillSelect.onSelect(i)
            end
            SkillSelect.Hide()
            return true
        end
    end

    return true -- 消耗点击事件（不穿透）
end

--- 渲染技能选择面板
function SkillSelect.Render(vg, viewW, viewH, font)
    if not SkillSelect.visible then return end

    local count = #SkillSelect.choices
    if count == 0 then return end

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 标题
    nvgFontFaceId(vg, font)
    local zpix = HUD.zpixFontId >= 0 and HUD.zpixFontId or font
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 200, 255, 255))

    local totalH = count * CARD_H + (count - 1) * CARD_GAP
    local startY = (viewH - totalH) / 2
    nvgFontFaceId(vg, zpix)
    nvgText(vg, viewW / 2, startY - 40, I18n.t("skill_level_up"))
    nvgFontFaceId(vg, font)

    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 200))
    nvgText(vg, viewW / 2, startY - 16, I18n.t("skill_choose"))

    -- 渲染卡片（动态全宽）
    local CARD_W = viewW - 48
    local cardX = (viewW - CARD_W) / 2
    local t = time.elapsedTime

    for i, choice in ipairs(SkillSelect.choices) do
        local cy = startY + (i - 1) * (CARD_H + CARD_GAP)
        local def = choice.def
        local newLevel = choice.newLevel
        local isNew = choice.isNew

        -- 卡片类型颜色
        local borderColor
        if def.type == "weapon" then
            borderColor = Config.COLORS.neonRed
        elseif def.type == "defense" then
            borderColor = Config.COLORS.neonGreen
        else
            borderColor = Config.COLORS.neonBlue
        end
        local br, bg, bb = borderColor[1], borderColor[2], borderColor[3]

        -- 卡片背景（渐变，顶部带色调）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, CARD_W, CARD_H, CARD_RADIUS)
        local bgGrad = nvgLinearGradient(vg, cardX, cy, cardX, cy + CARD_H,
            nvgRGBA(math.min(25 + br // 6, 60), math.min(20 + bg // 6, 55), math.min(50 + bb // 6, 80), 245),
            nvgRGBA(12, 10, 30, 245))
        nvgFillPaint(vg, bgGrad)
        nvgFill(vg)

        -- 卡片边框（霓虹发光，脉冲）
        local pulse = 0.7 + 0.3 * math.sin(t * 2.5 + i)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, CARD_W, CARD_H, CARD_RADIUS)
        nvgStrokeColor(vg, nvgRGBA(br, bg, bb, math.floor(200 * pulse)))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)

        -- 外发光效果
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX - 2, cy - 2, CARD_W + 4, CARD_H + 4, CARD_RADIUS + 2)
        nvgStrokeColor(vg, nvgRGBA(br, bg, bb, math.floor(50 * pulse)))
        nvgStrokeWidth(vg, 6)
        nvgStroke(vg)

        -- 横向布局：左侧图标 + 右侧文字区
        local iconAreaW = CARD_H  -- 正方形左区
        local iconCx = cardX + iconAreaW / 2
        local iconCy = cy + CARD_H / 2
        local iconR = 32

        -- 图标背景圆
        nvgBeginPath(vg)
        nvgCircle(vg, iconCx, iconCy, iconR)
        local iconGrad = nvgRadialGradient(vg, iconCx, iconCy, 4, iconR,
            nvgRGBA(br, bg, bb, 70), nvgRGBA(br, bg, bb, 15))
        nvgFillPaint(vg, iconGrad)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, iconCx, iconCy, iconR)
        nvgStrokeColor(vg, nvgRGBA(br, bg, bb, 160))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 图标 emoji
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, iconCx, iconCy, def.icon)

        -- 右侧文字区
        local textAreaX = cardX + iconAreaW + 10
        local textAreaW = CARD_W - iconAreaW - 18
        local textCx = textAreaX + textAreaW / 2

        -- 等级标签（右上角徽章）
        local levelText = isNew and "✦ NEW" or ("Lv." .. newLevel)
        local levelColor = isNew and Config.COLORS.neonGreen or Config.COLORS.neonBlue
        local lc = levelColor
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX + CARD_W - 52, cy + 8, 44, 22, 11)
        nvgFillColor(vg, nvgRGBA(lc[1], lc[2], lc[3], 40))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(lc[1], lc[2], lc[3], 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(lc[1], lc[2], lc[3], 255))
        nvgText(vg, cardX + CARD_W - 52 + 22, cy + 8 + 11, levelText)

        -- 类型标签（左侧徽章）
        local typeLabel
        if def.type == "weapon" then typeLabel = I18n.t("skill_type_weapon")
        elseif def.type == "defense" then typeLabel = I18n.t("skill_type_defense")
        else typeLabel = I18n.t("skill_type_attr")
        end
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(br, bg, bb, 180))
        nvgText(vg, cardX + iconAreaW + 10, cy + 19, typeLabel)

        -- 技能名称（大字，左对齐）
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 245))
        nvgText(vg, textAreaX, cy + 68, def.name)

        -- 分割线
        nvgBeginPath(vg)
        nvgMoveTo(vg, textAreaX, cy + 82)
        nvgLineTo(vg, cardX + CARD_W - 14, cy + 82)
        nvgStrokeColor(vg, nvgRGBA(br, bg, bb, 50))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 描述（左对齐，多行适配）
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(190, 195, 215, 215))
        nvgText(vg, textAreaX, cy + 100, def.desc)

        -- 最高叠加层数
        if def.maxLevel and def.maxLevel > 1 then
            nvgFontFaceId(vg, zpix)
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(140, 150, 180, 160))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, textAreaX, cy + 122, I18n.t("skill_max_stack_fmt", def.maxLevel))
            nvgFontFaceId(vg, font)
        end
    end
end

--- ============================================================================
--- 终极奖励选择 UI
--- ============================================================================

local ULTIMATE_CARD_W = 240
local ULTIMATE_CARD_H = 160
local ULTIMATE_CARD_GAP = 24

--- 显示终极奖励选择
function SkillSelect.ShowUltimate(onSelect)
    SkillSelect.ultimateVisible = true
    SkillSelect.onUltimateSelect = onSelect
end

--- 隐藏终极奖励
function SkillSelect.HideUltimate()
    SkillSelect.ultimateVisible = false
end

--- 处理终极奖励点击
function SkillSelect.HandleUltimateTouch(touchX, touchY, viewW, viewH)
    if not SkillSelect.ultimateVisible then return false end

    local totalH = 2 * ULTIMATE_CARD_H + ULTIMATE_CARD_GAP
    local startY = (viewH - totalH) / 2
    local cardX = (viewW - ULTIMATE_CARD_W) / 2

    -- 选项1: 回血+无敌
    local cy1 = startY
    if touchX >= cardX and touchX <= cardX + ULTIMATE_CARD_W and
        touchY >= cy1 and touchY <= cy1 + ULTIMATE_CARD_H then
        if SkillSelect.onUltimateSelect then
            SkillSelect.onUltimateSelect("heal_inv")
        end
        SkillSelect.HideUltimate()
        return true
    end

    -- 选项2: 狂暴模式
    local cy2 = startY + ULTIMATE_CARD_H + ULTIMATE_CARD_GAP
    if touchX >= cardX and touchX <= cardX + ULTIMATE_CARD_W and
        touchY >= cy2 and touchY <= cy2 + ULTIMATE_CARD_H then
        if SkillSelect.onUltimateSelect then
            SkillSelect.onUltimateSelect("rage")
        end
        SkillSelect.HideUltimate()
        return true
    end

    return true -- 消耗点击
end

--- 渲染终极奖励选择
function SkillSelect.RenderUltimate(vg, viewW, viewH, font)
    if not SkillSelect.ultimateVisible then return end

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    local totalH = 2 * ULTIMATE_CARD_H + ULTIMATE_CARD_GAP
    local startY = (viewH - totalH) / 2
    local cardX = (viewW - ULTIMATE_CARD_W) / 2

    -- 标题（zpix）
    local zpixU = (HUD and HUD.zpixFontId >= 0) and HUD.zpixFontId or font
    nvgFontFaceId(vg, zpixU)
    nvgFontSize(vg, 30)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
    nvgText(vg, viewW / 2, startY - 50, I18n.t("skill_ult_title"))
    nvgFontFaceId(vg, font)

    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(255, 220, 150, 200))
    nvgText(vg, viewW / 2, startY - 24, I18n.t("skill_ult_choose"))

    -- 选项定义
    local options = {
        { icon = "💚", title = I18n.t("skill_full_hp"),   desc = I18n.t("skill_full_hp_desc"), color = Config.COLORS.neonGreen },
        { icon = "🔥", title = I18n.t("skill_rage"),      desc = I18n.t("skill_rage_desc"),    color = Config.COLORS.neonRed },
    }

    for i, opt in ipairs(options) do
        local cy = startY + (i - 1) * (ULTIMATE_CARD_H + ULTIMATE_CARD_GAP)

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, ULTIMATE_CARD_W, ULTIMATE_CARD_H, 14)
        local grad = nvgLinearGradient(vg, cardX, cy, cardX, cy + ULTIMATE_CARD_H,
            nvgRGBA(30, 20, 60, 245),
            nvgRGBA(15, 10, 35, 245))
        nvgFillPaint(vg, grad)
        nvgFill(vg)

        -- 边框（金色发光）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, ULTIMATE_CARD_W, ULTIMATE_CARD_H, 14)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 200))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)

        -- 外发光
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX - 2, cy - 2, ULTIMATE_CARD_W + 4, ULTIMATE_CARD_H + 4, 16)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 30))
        nvgStrokeWidth(vg, 6)
        nvgStroke(vg)

        -- 图标
        nvgFontSize(vg, 40)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, cardX + ULTIMATE_CARD_W / 2, cy + 45, opt.icon)

        -- 标题
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(opt.color[1], opt.color[2], opt.color[3], 255))
        nvgText(vg, cardX + ULTIMATE_CARD_W / 2, cy + 90, opt.title)

        -- 描述
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(200, 200, 220, 200))
        nvgText(vg, cardX + ULTIMATE_CARD_W / 2, cy + 120, opt.desc)
    end
end

return SkillSelect
