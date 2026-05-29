--- ============================================================================
--- 礼物盒广告弹窗 UI - 放弃 / 看广告获取大量经验
--- ============================================================================

local Config = require("Config")
local I18n   = require("utils.I18n")

local GiftAd = {}

GiftAd.visible = false
GiftAd.onSelect = nil   -- function(watchAd: boolean)
GiftAd.adReward = 0     -- 当前看广告奖励值
GiftAd.giveUpReward = 0 -- 当前放弃奖励值
GiftAd.showTimer = 0    -- 显示计时器（超时自动关闭防卡死）
GiftAd.TIMEOUT = 30     -- 超时秒数

-- 布局常量（放大版）
local PANEL_W = 440
local PANEL_H = 400
local BTN_W = 340
local BTN_H = 68
local BTN_GAP = 20

--- 显示弹窗
---@param onSelect function(watchAd: boolean)
---@param adReward number|nil 看广告经验奖励（可选，默认从Config读取）
---@param giveUpReward number|nil 放弃经验奖励（可选，默认从Config读取）
function GiftAd.Show(onSelect, adReward, giveUpReward)
    GiftAd.visible = true
    GiftAd.onSelect = onSelect
    GiftAd.adReward = adReward or Config.GIFT_BOX.adExpReward
    GiftAd.giveUpReward = giveUpReward or Config.GIFT_BOX.giveUpExpReward
    GiftAd.showTimer = 0  -- 重置超时计时器
end

--- 隐藏弹窗
function GiftAd.Hide()
    GiftAd.visible = false
    GiftAd.onSelect = nil
    GiftAd.showTimer = 0
end

--- 超时更新（每帧调用，防止广告SDK回调丢失导致卡死）
---@param dt number
function GiftAd.Update(dt)
    if not GiftAd.visible then return end
    GiftAd.showTimer = GiftAd.showTimer + dt
    if GiftAd.showTimer >= GiftAd.TIMEOUT then
        print("[GiftAd] 超时自动关闭（" .. GiftAd.TIMEOUT .. "s无响应）")
        local cb = GiftAd.onSelect
        GiftAd.Hide()
        if cb then
            cb(false)  -- 超时视为放弃
        end
    end
end

--- 渲染弹窗
function GiftAd.Render(vg, viewW, viewH, fontId)
    if not GiftAd.visible then return end
    local HUD = require("ui.HUD")
    local zpix = HUD.zpixFontId >= 0 and HUD.zpixFontId or fontId

    local t = time.elapsedTime

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 170))
    nvgFill(vg)

    -- 面板居中
    local px = (viewW - PANEL_W) / 2
    local py = (viewH - PANEL_H) / 2

    -- 面板背景（赛博朋克渐变）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, PANEL_W, PANEL_H, 16)
    local bgGrad = nvgLinearGradient(vg, px, py, px, py + PANEL_H,
        nvgRGBA(30, 25, 55, 245),
        nvgRGBA(15, 10, 35, 245))
    nvgFillPaint(vg, bgGrad)
    nvgFill(vg)

    -- 金色边框 + 脉冲
    local pulse = 0.7 + 0.3 * math.sin(t * 3)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 50, math.floor(180 * pulse)))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 外发光
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px - 3, py - 3, PANEL_W + 6, PANEL_H + 6, 18)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 50, math.floor(40 * pulse)))
    nvgStrokeWidth(vg, 4)
    nvgStroke(vg)

    local cx = viewW / 2

    -- 大号 emoji（浮动）
    nvgFontFaceId(vg, zpix)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local emojiY = py + 70 + math.sin(t * 2.5) * 5
    nvgFontSize(vg, 76)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, cx, emojiY, "🎁")

    -- 标题
    nvgFontSize(vg, 28)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
    nvgText(vg, cx, py + 140, "发现神秘礼物！")

    -- 副标题（经验量，zpix字体）
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(180, 200, 220, 200))
    nvgText(vg, cx, py + 175, I18n.t("gift_ad_exp_tip", GiftAd.adReward))
    nvgFontFaceId(vg, zpix)

    -- 按钮区域
    local btnX = (viewW - BTN_W) / 2
    local btn1Y = py + 210  -- 看广告按钮
    local btn2Y = btn1Y + BTN_H + BTN_GAP  -- 放弃按钮

    -- 按钮1：看广告领取（绿色高亮）
    local greenPulse = 0.8 + 0.2 * math.sin(t * 4)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btn1Y, BTN_W, BTN_H, 10)
    local btnGrad = nvgLinearGradient(vg, btnX, btn1Y, btnX, btn1Y + BTN_H,
        nvgRGBA(20, 180, 80, math.floor(220 * greenPulse)),
        nvgRGBA(10, 120, 50, math.floor(220 * greenPulse)))
    nvgFillPaint(vg, btnGrad)
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 255, 150, math.floor(200 * greenPulse)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 24)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, cx, btn1Y + BTN_H / 2, "🎬 看广告领取")
    nvgFontFaceId(vg, zpix)

    -- 按钮2：放弃（灰色低调）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btn2Y, BTN_W, BTN_H, 10)
    nvgFillColor(vg, nvgRGBA(50, 45, 70, 180))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 100, 120, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(160, 160, 180, 200))
    nvgText(vg, cx, btn2Y + BTN_H / 2, I18n.t("gift_ad_give_up", GiftAd.giveUpReward))
    nvgFontFaceId(vg, zpix)
end

--- 处理触摸
---@return boolean 是否消耗了事件
function GiftAd.HandleTouch(touchX, touchY, viewW, viewH)
    if not GiftAd.visible then return false end

    local px = (viewW - PANEL_W) / 2
    local py = (viewH - PANEL_H) / 2
    local btnX = (viewW - BTN_W) / 2
    local btn1Y = py + 210
    local btn2Y = btn1Y + BTN_H + BTN_GAP

    -- 看广告按钮
    if touchX >= btnX and touchX <= btnX + BTN_W and
       touchY >= btn1Y and touchY <= btn1Y + BTN_H then
        local cb = GiftAd.onSelect
        GiftAd.Hide()
        if cb then
            cb(true)
        end
        return true
    end

    -- 放弃按钮
    if touchX >= btnX and touchX <= btnX + BTN_W and
       touchY >= btn2Y and touchY <= btn2Y + BTN_H then
        local cb = GiftAd.onSelect
        GiftAd.Hide()
        if cb then
            cb(false)
        end
        return true
    end

    -- 面板外不消耗（但也不穿透到游戏）
    return true
end

return GiftAd
