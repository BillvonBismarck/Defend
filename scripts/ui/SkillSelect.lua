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
SkillSelect.onRefresh = nil -- function() -> 新的三个选项
SkillSelect.adLoading = false
SkillSelect.countdown = 45.0
SkillSelect.feedbackText = nil
SkillSelect.feedbackTimer = 0

-- 终极奖励状态
SkillSelect.ultimateVisible = false
SkillSelect.onUltimateSelect = nil  -- function(choice) "heal_inv" or "rage"

-- 布局常量（720×1280 设计分辨率，卡片宽度在 Render 时动态计算）
local SELECT_TIMEOUT = 45.0
local CARD_H = 218
local CARD_GAP = 14
local CARD_RADIUS = 16
local REFRESH_GAP = 22
local REFRESH_W = 360
local REFRESH_H = 64

local function GetLayout(viewW, viewH, count)
    local cardW = viewW - 48
    local cardsH = count * CARD_H + (count - 1) * CARD_GAP
    local contentH = cardsH + REFRESH_GAP + REFRESH_H
    local startY = (viewH - contentH) / 2 + 8
    return {
        cardW = cardW,
        cardX = (viewW - cardW) / 2,
        startY = startY,
        refreshX = (viewW - REFRESH_W) / 2,
        refreshY = startY + cardsH + REFRESH_GAP,
    }
end

local function SetFeedback(text)
    SkillSelect.feedbackText = text
    SkillSelect.feedbackTimer = 2.5
end

--- 显示技能选择
function SkillSelect.Show(choices, onSelect, onRefresh)
    SkillSelect.visible = true
    SkillSelect.choices = choices
    SkillSelect.onSelect = onSelect
    SkillSelect.onRefresh = onRefresh
    SkillSelect.adLoading = false
    SkillSelect.countdown = SELECT_TIMEOUT
    SkillSelect.feedbackText = nil
    SkillSelect.feedbackTimer = 0
    print("[SkillSelect] 显示天赋选择，倒计时 " .. SELECT_TIMEOUT .. " 秒")
end

--- 隐藏
function SkillSelect.Hide()
    SkillSelect.visible = false
    SkillSelect.choices = {}
    SkillSelect.onSelect = nil
    SkillSelect.onRefresh = nil
    SkillSelect.adLoading = false
    SkillSelect.feedbackText = nil
    SkillSelect.feedbackTimer = 0
end

--- 选择指定天赋
function SkillSelect.Select(index)
    if not SkillSelect.visible or SkillSelect.adLoading then return false end
    if not SkillSelect.choices[index] then return false end

    local callback = SkillSelect.onSelect
    SkillSelect.Hide()
    if callback then
        callback(index)
    end
    return true
end

--- 更新选择倒计时；广告播放期间暂停计时
function SkillSelect.Update(dt)
    if SkillSelect.feedbackTimer > 0 then
        SkillSelect.feedbackTimer = math.max(0, SkillSelect.feedbackTimer - dt)
        if SkillSelect.feedbackTimer == 0 then
            SkillSelect.feedbackText = nil
        end
    end

    if not SkillSelect.visible or SkillSelect.adLoading then return end

    SkillSelect.countdown = math.max(0, SkillSelect.countdown - dt)
    if SkillSelect.countdown <= 0 and #SkillSelect.choices > 0 then
        local autoIndex = math.random(1, #SkillSelect.choices)
        print("[SkillSelect] 倒计时结束，自动选择第 " .. autoIndex .. " 项")
        SkillSelect.Select(autoIndex)
    end
end

--- 观看奖励广告并刷新三个候选天赋
local function RefreshChoicesWithAd(sdk)
    if SkillSelect.adLoading or not SkillSelect.visible then return end
    if not sdk then
        SetFeedback(I18n.t("skill_refresh_unavailable"))
        print("[SkillSelect] SDK 不可用，无法播放奖励广告")
        return
    end

    SkillSelect.adLoading = true
    SetFeedback(I18n.t("skill_refresh_loading"))
    print("[SkillSelect] 请求奖励广告刷新天赋")
    sdk:ShowRewardVideoAd(function(result)
        SkillSelect.adLoading = false
        if not SkillSelect.visible then return end

        if result and result.success then
            local refreshed = SkillSelect.onRefresh and SkillSelect.onRefresh() or nil
            if refreshed and #refreshed > 0 then
                SkillSelect.choices = refreshed
                SkillSelect.countdown = SELECT_TIMEOUT
                SetFeedback(I18n.t("skill_refresh_success"))
                print("[SkillSelect] 广告完整观看，已刷新 " .. #refreshed .. " 个天赋")
            else
                SetFeedback(I18n.t("skill_refresh_no_choices"))
                print("[SkillSelect] 广告成功，但没有可刷新的天赋")
            end
        else
            SetFeedback(I18n.t("skill_refresh_incomplete"))
            print("[SkillSelect] 广告未完成，不刷新天赋: " .. tostring(result and result.msg or "unknown"))
        end
    end)
end

--- 处理点击选择
---@param touchX number 设计坐标系的点击X
---@param touchY number 设计坐标系的点击Y
---@param viewW number 设计宽度
---@param viewH number 设计高度
---@param sdk userdata|nil 引擎 SDK，用于播放奖励广告
---@return boolean 是否处理了点击
function SkillSelect.HandleTouch(touchX, touchY, viewW, viewH, sdk)
    if not SkillSelect.visible then return false end

    local count = #SkillSelect.choices
    if count == 0 then return false end

    local layout = GetLayout(viewW, viewH, count)

    for i = 1, count do
        local cy = layout.startY + (i - 1) * (CARD_H + CARD_GAP)
        if touchX >= layout.cardX and touchX <= layout.cardX + layout.cardW and
            touchY >= cy and touchY <= cy + CARD_H then
            SkillSelect.Select(i)
            return true
        end
    end

    if touchX >= layout.refreshX and touchX <= layout.refreshX + REFRESH_W and
        touchY >= layout.refreshY and touchY <= layout.refreshY + REFRESH_H then
        RefreshChoicesWithAd(sdk)
        return true
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

    local layout = GetLayout(viewW, viewH, count)
    local startY = layout.startY
    local CARD_W = layout.cardW
    local cardX = layout.cardX

    -- 标题区：大标题、选择说明、可见倒计时
    nvgFontFaceId(vg, font)
    local zpix = HUD.zpixFontId >= 0 and HUD.zpixFontId or font
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 42)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 220, 255, 255))
    nvgText(vg, viewW / 2, startY - 112, I18n.t("skill_level_up"))

    nvgFontFaceId(vg, font)
    nvgFontSize(vg, 24)
    nvgFillColor(vg, nvgRGBA(235, 238, 255, 245))
    nvgText(vg, viewW / 2, startY - 72, I18n.t("skill_choose"))

    local seconds = math.max(0, math.ceil(SkillSelect.countdown))
    local timerText = SkillSelect.adLoading and I18n.t("skill_countdown_paused")
        or I18n.t("skill_countdown_fmt", seconds)
    local timerW = 280
    local timerH = 38
    local timerX = (viewW - timerW) / 2
    local timerY = startY - 50
    nvgBeginPath(vg)
    nvgRoundedRect(vg, timerX, timerY, timerW, timerH, timerH / 2)
    nvgFillColor(vg, nvgRGBA(7, 15, 35, 230))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(0, 205, 255, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 18)
    nvgFillColor(vg, seconds <= 10 and nvgRGBA(255, 90, 90, 255) or nvgRGBA(120, 225, 255, 255))
    nvgText(vg, viewW / 2, timerY + timerH / 2, timerText)

    -- 渲染卡片（动态全宽）
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
        local iconAreaW = 150
        local iconCx = cardX + iconAreaW / 2
        local iconCy = cy + CARD_H / 2
        local iconR = 42

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
        nvgFontSize(vg, 48)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, iconCx, iconCy, def.icon)

        -- 右侧文字区
        local textAreaX = cardX + iconAreaW + 10
        local textAreaW = CARD_W - iconAreaW - 28

        -- 等级标签（右上角徽章）
        local levelText = isNew and "✦ NEW" or ("Lv." .. newLevel)
        local levelColor = isNew and Config.COLORS.neonGreen or Config.COLORS.neonBlue
        local lc = levelColor
        local badgeW, badgeH = 82, 34
        local badgeX, badgeY = cardX + CARD_W - badgeW - 12, cy + 12
        nvgBeginPath(vg)
        nvgRoundedRect(vg, badgeX, badgeY, badgeW, badgeH, badgeH / 2)
        nvgFillColor(vg, nvgRGBA(lc[1], lc[2], lc[3], 55))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(lc[1], lc[2], lc[3], 190))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 17)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(lc[1], lc[2], lc[3], 255))
        nvgText(vg, badgeX + badgeW / 2, badgeY + badgeH / 2, levelText)

        -- 类型标签（左侧徽章）
        local typeLabel
        if def.type == "weapon" then typeLabel = I18n.t("skill_type_weapon")
        elseif def.type == "defense" then typeLabel = I18n.t("skill_type_defense")
        else typeLabel = I18n.t("skill_type_attr")
        end
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(br, bg, bb, 245))
        nvgText(vg, textAreaX, cy + 30, typeLabel)

        -- 技能名称（大字，左对齐）
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 32)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, textAreaX, cy + 76, def.name)

        -- 分割线
        nvgBeginPath(vg)
        nvgMoveTo(vg, textAreaX, cy + 102)
        nvgLineTo(vg, cardX + CARD_W - 18, cy + 102)
        nvgStrokeColor(vg, nvgRGBA(br, bg, bb, 90))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 描述（左对齐，允许在文字区自动换行）
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 21)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgTextLineHeight(vg, 1.25)
        nvgFillColor(vg, nvgRGBA(225, 228, 242, 245))
        nvgTextBox(vg, textAreaX, cy + 118, textAreaW, def.desc)

        -- 最高叠加层数
        if def.maxLevel and def.maxLevel > 1 then
            nvgFontFaceId(vg, zpix)
            nvgFontSize(vg, 17)
            nvgFillColor(vg, nvgRGBA(175, 185, 215, 220))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, textAreaX, cy + 195, I18n.t("skill_max_stack_fmt", def.maxLevel))
            nvgFontFaceId(vg, font)
        end
    end

    -- 卡片下方的次级操作：观看奖励广告后刷新三个候选
    local buttonPulse = 0.92 + 0.08 * math.sin(t * 3.0)
    local btnColor = SkillSelect.adLoading and { 90, 95, 120 } or { 0, 185, 230 }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, layout.refreshX, layout.refreshY, REFRESH_W, REFRESH_H, 20)
    local btnGrad = nvgLinearGradient(vg, layout.refreshX, layout.refreshY,
        layout.refreshX, layout.refreshY + REFRESH_H,
        nvgRGBA(btnColor[1], btnColor[2], btnColor[3], 235),
        nvgRGBA(25, 35, 75, 245))
    nvgFillPaint(vg, btnGrad)
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 225, 255, math.floor(230 * buttonPulse)))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    nvgFontFaceId(vg, font)
    nvgFontSize(vg, 24)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    local refreshText = SkillSelect.adLoading and I18n.t("skill_refresh_loading")
        or I18n.t("skill_refresh_ad")
    nvgText(vg, viewW / 2, layout.refreshY + REFRESH_H / 2, refreshText)

    if SkillSelect.feedbackText then
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(255, 230, 120, 255))
        nvgText(vg, viewW / 2, layout.refreshY + REFRESH_H + 25, SkillSelect.feedbackText)
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
