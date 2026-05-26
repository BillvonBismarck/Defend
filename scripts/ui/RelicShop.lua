--- ============================================================================
--- 遗物商店 UI - 局外养成页面
--- 使用 NanoVG 渲染，显示6个遗物卡片 + 广告金币按钮
--- ============================================================================

local RelicSystem = require("meta.RelicSystem")
local SaveData    = require("SaveData")
local HUD         = require("ui.HUD")

local RelicShop = {}

-- 触摸区域记录（由 Render 每帧更新）
RelicShop.backBtn  = { x = 0, y = 0, w = 0, h = 0 }
RelicShop.adBtn    = { x = 0, y = 0, w = 0, h = 0 }
-- 每个遗物的升级按钮
local upgradeButtons = {}  -- [i] = { x, y, w, h, relicId, cost }

-- 升级反馈动画（短暂闪烁）
local upgradeFlash   = {}  -- [relicId] = timer
local FLASH_DURATION = 0.5

-- 广告加载中标记
local adLoading = false

--- 更新帧计时（在 HandleUpdate 中调用）
---@param dt number
function RelicShop.Update(dt)
    for id, t in pairs(upgradeFlash) do
        upgradeFlash[id] = t - dt
        if upgradeFlash[id] <= 0 then
            upgradeFlash[id] = nil
        end
    end
    if adLoading then
        -- 广告超时兜底（10秒后重置）
    end
end

--- 绘制遗物商店全屏页面
---@param vg userdata NanoVG context
---@param fontId number
---@param DESIGN_W number
---@param DESIGN_H number
function RelicShop.Render(vg, fontId, DESIGN_W, DESIGN_H)
    local cx = DESIGN_W / 2
    local t  = time.elapsedTime

    -- ── 背景 ──
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(18, 14, 38, 255))
    nvgFill(vg)

    -- 背景光晕
    local grad = nvgRadialGradient(vg, cx, DESIGN_H * 0.35, 100, 500,
        nvgRGBA(80, 50, 160, 40), nvgRGBA(18, 14, 38, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    nvgFontFaceId(vg, zpix)
    local zpix = HUD.zpixFontId >= 0 and HUD.zpixFontId or fontId

    -- ── 波次未达解锁条件：显示锁定界面 ──
    local UNLOCK_WAVE = 10
    if SaveData.highestWave < UNLOCK_WAVE then
        -- 返回按钮（锁定界面也要有）
        local backW, backH = 100, 44
        local backX, backY = 16, (80 - backH) / 2
        RelicShop.backBtn = { x = backX, y = backY, w = backW, h = backH }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, backX, backY, backW, backH, 10)
        nvgFillColor(vg, nvgRGBA(40, 30, 70, 180))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(150, 150, 200, 80))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(200, 200, 220, 220))
        nvgText(vg, backX + backW / 2, backY + backH / 2, "◀ 返回")

        -- 锁图标
        nvgFontSize(vg, 72)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
        local pulse = 0.9 + 0.1 * math.sin(t * 2)
        nvgFontSize(vg, math.floor(72 * pulse))
        nvgText(vg, cx, DESIGN_H * 0.4, "🔒")

        -- 提示文字
        nvgFontSize(vg, 24)
        nvgFillColor(vg, nvgRGBA(220, 180, 80, 240))
        nvgText(vg, cx, DESIGN_H * 0.55, "遗物商店未解锁")
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(170, 160, 200, 180))
        nvgText(vg, cx, DESIGN_H * 0.62,
            "通过第 " .. UNLOCK_WAVE .. " 波后可开启")
        -- 进度
        local prog = math.min(SaveData.highestWave, UNLOCK_WAVE)
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(100, 200, 255, 200))
        nvgText(vg, cx, DESIGN_H * 0.68,
            "当前最高波次：" .. tostring(SaveData.highestWave) .. " / " .. UNLOCK_WAVE)
        nvgFontFaceId(vg, zpix)

        -- 进度条
        local barW = 320
        local barH = 12
        local barX = cx - barW / 2
        local barY = DESIGN_H * 0.73
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 6)
        nvgFillColor(vg, nvgRGBA(60, 60, 100, 140))
        nvgFill(vg)
        local fillW = barW * (prog / UNLOCK_WAVE)
        if fillW > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, fillW, barH, 6)
            nvgFillColor(vg, nvgRGBA(100, 200, 255, 200))
            nvgFill(vg)
        end
        return
    end

    -- ── 顶部导航栏 ──
    local navH = 80
    -- 返回按钮
    local backW, backH = 100, 44
    local backX, backY = 16, (navH - backH) / 2
    RelicShop.backBtn = { x = backX, y = backY, w = backW, h = backH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, backX, backY, backW, backH, 10)
    nvgFillColor(vg, nvgRGBA(40, 30, 70, 180))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(150, 150, 200, 80))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 220))
    nvgText(vg, backX + backW / 2, backY + backH / 2, "◀ 返回")

    -- 标题
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 26)
    nvgFillColor(vg, nvgRGBA(220, 180, 80, 255))
    nvgText(vg, cx, navH / 2, "🛒 遗物商店")

    -- 金币显示（右上角，zpix字体）
    nvgFontFaceId(vg, zpix)
    local goldStr = "🪙 " .. tostring(SaveData.metaGold)
    nvgFontSize(vg, 20)
    local goldW = nvgTextBounds(vg, 0, 0, goldStr) + 24
    local goldH = 40
    local goldX = DESIGN_W - goldW - 12
    local goldY = (navH - goldH) / 2
    nvgBeginPath(vg)
    nvgRoundedRect(vg, goldX, goldY, goldW, goldH, 10)
    nvgFillColor(vg, nvgRGBA(255, 200, 50, 20))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
    nvgText(vg, goldX + goldW / 2, goldY + goldH / 2, goldStr)
    nvgFontFaceId(vg, zpix)

    -- 分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, navH)
    nvgLineTo(vg, DESIGN_W, navH)
    nvgStrokeColor(vg, nvgRGBA(100, 80, 180, 80))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ── 遗物卡片列表 ──
    local cardMarginH = 14   -- 左右边距
    local cardW = DESIGN_W - cardMarginH * 2
    local cardH = 90         -- 卡片高度（紧凑版）
    local cardGap = 6        -- 卡片间距
    local startY = navH + 10

    upgradeButtons = {}

    for i, relic in ipairs(RelicSystem.RELICS) do
        local cY = startY + (i - 1) * (cardH + cardGap)
        local cX = cardMarginH
        local curLv = SaveData.relicLevels[relic.id] or 0
        local cost  = math.floor(RelicSystem.GetCost(relic.id, curLv))
        local canAfford = (SaveData.metaGold >= cost)

        -- 升级闪光效果
        local flashAlpha = 0
        if upgradeFlash[relic.id] and upgradeFlash[relic.id] > 0 then
            flashAlpha = math.floor(160 * (upgradeFlash[relic.id] / FLASH_DURATION))
        end

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cX, cY, cardW, cardH, 14)
        nvgFillColor(vg, nvgRGBA(30, 22, 60, 200))
        nvgFill(vg)
        -- 升级闪光
        if flashAlpha > 0 then
            nvgFillColor(vg, nvgRGBA(100, 255, 150, flashAlpha))
            nvgFill(vg)
        end
        nvgStrokeColor(vg, nvgRGBA(100, 80, 200, 80))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 图标（大号 emoji）
        local iconX = cX + 14
        local iconCY = cY + cardH / 2 - 4
        nvgFontSize(vg, 34)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgText(vg, iconX, iconCY, relic.icon)

        -- 遗物名称 + 等级
        local textX = cX + 62
        local nameY = cY + 22
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(230, 210, 255, 240))
        nvgText(vg, textX, nameY, relic.name)

        -- 等级徽章（zpix字体）
        nvgFontFaceId(vg, zpix)
        local lbStr = "Lv." .. curLv
        local lbW = nvgTextBounds(vg, 0, 0, lbStr) + 18
        local lbH = 24
        local lbX = textX + nvgTextBounds(vg, 0, 0, relic.name) + 12
        local lbY = nameY - lbH / 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, lbX, lbY, lbW, lbH, 6)
        if curLv > 0 then
            nvgFillColor(vg, nvgRGBA(80, 200, 140, 40))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(80, 220, 150, 120))
        else
            nvgFillColor(vg, nvgRGBA(100, 100, 150, 30))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(150, 150, 200, 60))
        end
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if curLv > 0 then
            nvgFillColor(vg, nvgRGBA(100, 240, 170, 220))
        else
            nvgFillColor(vg, nvgRGBA(160, 160, 200, 160))
        end
        nvgText(vg, lbX + lbW / 2, nameY, lbStr)
        nvgFontFaceId(vg, zpix)

        -- 描述文字
        local descY = cY + 46
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(170, 160, 200, 180))
        nvgText(vg, textX, descY, relic.desc)

        -- ── 升级按钮（右侧竖向居中）──
        local upgW = 120
        local upgH = 40
        local upgX = cX + cardW - upgW - 14
        local upgY = cY + (cardH - upgH) / 2

        -- 记录按钮区域
        upgradeButtons[i] = { x = upgX, y = upgY, w = upgW, h = upgH,
                               relicId = relic.id, cost = cost }

        -- 绘制升级按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, upgX, upgY, upgW, upgH, 10)
        if canAfford then
            local pulse = 0.8 + 0.2 * math.sin(t * 2 + i)
            nvgFillColor(vg, nvgRGBA(80, 180, 255, math.floor(40 * pulse)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(100, 200, 255, math.floor(200 * pulse)))
        else
            nvgFillColor(vg, nvgRGBA(60, 60, 90, 80))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(100, 100, 150, 60))
        end
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 按钮文字：费用 + 升级（zpix字体）
        nvgFontFaceId(vg, zpix)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if canAfford then
            nvgFillColor(vg, nvgRGBA(180, 230, 255, 240))
        else
            nvgFillColor(vg, nvgRGBA(130, 130, 170, 140))
        end
        nvgFontSize(vg, 14)
        nvgText(vg, upgX + upgW / 2, upgY + 14, "🪙 " .. cost)
        nvgFontSize(vg, 16)
        if canAfford then
            nvgFillColor(vg, nvgRGBA(220, 240, 255, 255))
        else
            nvgFillColor(vg, nvgRGBA(150, 150, 190, 150))
        end
        nvgText(vg, upgX + upgW / 2, upgY + 32, "升级 ▲")
        nvgFontFaceId(vg, zpix)
    end

    -- ── 广告金币按钮 ──
    local lastCardIdx = #RelicSystem.RELICS
    local adBtnY = startY + lastCardIdx * (cardH + cardGap) + 8
    local adBtnW = cardW
    local adBtnH = 64
    local adBtnX = cardMarginH
    local canAd   = SaveData.CanWatchAdForGold()
    -- 今日剩余次数
    local remaining = 10 - SaveData.adGoldCount

    RelicShop.adBtn = { x = adBtnX, y = adBtnY, w = adBtnW, h = adBtnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, adBtnX, adBtnY, adBtnW, adBtnH, 14)
    if canAd then
        local pulse = 0.7 + 0.3 * math.sin(t * 2.5)
        nvgFillColor(vg, nvgRGBA(60, 180, 100, math.floor(35 * pulse)))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 220, 120, math.floor(180 * pulse)))
    else
        nvgFillColor(vg, nvgRGBA(40, 40, 60, 100))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 80, 120, 60))
    end
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if canAd then
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(150, 255, 180, 240))
        nvgText(vg, cx, adBtnY + adBtnH / 2 - 10, "📺 观看广告 +500🪙")
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(120, 200, 140, 180))
        nvgText(vg, cx, adBtnY + adBtnH / 2 + 14, "今日剩余 " .. remaining .. "/10 次")
    else
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(130, 130, 160, 160))
        nvgText(vg, cx, adBtnY + adBtnH / 2 - 8, "📺 今日广告已达上限")
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(110, 110, 140, 120))
        nvgText(vg, cx, adBtnY + adBtnH / 2 + 14, "明天再来吧 (0/10)")
    end
    nvgFontFaceId(vg, zpix)

    -- 底部提示
    local hintY = adBtnY + adBtnH + 20
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(120, 110, 160, 130))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, cx, hintY, "遗物加成在每局开始时生效 · 金币从局内拾取🪙获得")
end

--- 处理点击事件（设计坐标）
---@param dx number
---@param dy number
---@param sdk userdata 引擎 SDK，用于播放广告
---@return string|nil  "back" = 返回标题，nil = 已处理
function RelicShop.HandleTouch(dx, dy, sdk)
    -- 返回按钮
    local bb = RelicShop.backBtn
    if dx >= bb.x and dx <= bb.x + bb.w and dy >= bb.y and dy <= bb.y + bb.h then
        return "back"
    end

    -- 广告金币按钮
    local ab = RelicShop.adBtn
    if dx >= ab.x and dx <= ab.x + ab.w and dy >= ab.y and dy <= ab.y + ab.h then
        if SaveData.CanWatchAdForGold() and sdk then
            adLoading = true
            sdk:ShowRewardVideoAd(function(rewarded)
                adLoading = false
                if rewarded then
                    SaveData.ClaimAdGold()
                end
            end)
        end
        return nil
    end

    -- 遗物升级按钮
    for _, btn in ipairs(upgradeButtons) do
        if dx >= btn.x and dx <= btn.x + btn.w and dy >= btn.y and dy <= btn.y + btn.h then
            local curLv = SaveData.relicLevels[btn.relicId] or 0
            local cost  = math.floor(RelicSystem.GetCost(btn.relicId, curLv))
            if SaveData.metaGold >= cost then
                SaveData.UpgradeRelic(btn.relicId, cost)
                upgradeFlash[btn.relicId] = FLASH_DURATION
            end
            return nil
        end
    end

    return nil
end

return RelicShop
