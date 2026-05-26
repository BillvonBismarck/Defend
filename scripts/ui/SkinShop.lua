--- ============================================================================
--- 皮肤商店 UI - 角色 Emoji 外观切换（金币或广告解锁）
--- 金色主题，角色分页 + 皮肤预览 + 购买/装备
--- ============================================================================
---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local SkinSystem = require("meta.SkinSystem")
local SaveData   = require("SaveData")
local Config     = require("Config")
local HUD        = require("ui.HUD")
local I18n       = require("utils.I18n")

local SkinShop = {}

-- 触摸区域
SkinShop.backBtn = { x = 0, y = 0, w = 0, h = 0 }

-- 角色分页
local selectedCharIdx = 1  -- 当前选中的角色索引（1-6）

-- 选中的皮肤
local selectedSkinId = nil

-- 按钮区域
local charTabs    = {}  -- { {x,y,w,h,charIdx}, ... }
local skinCards   = {}  -- { {x,y,w,h,skinId}, ... }
local actionBtn   = { x = 0, y = 0, w = 0, h = 0, visible = false }

-- 反馈动画
local flashTimer = 0
local flashMsg   = ""
local FLASH_DUR  = 1.2

-- 广告加载
local adLoading = false

--- 设置反馈消息
local function ShowFlash(msg)
    flashMsg = msg
    flashTimer = FLASH_DUR
end

-- ── 内部辅助 ──

local function drawCard(vg, x, y, w, h, r, fillR, fillG, fillB, fillA, strokeR, strokeG, strokeB, strokeA)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, nvgRGBA(fillR, fillG, fillB, fillA))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(strokeR, strokeG, strokeB, strokeA))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

local function hitTest(dx, dy, btn)
    return dx >= btn.x and dx <= btn.x + btn.w and dy >= btn.y and dy <= btn.y + btn.h
end

--- 更新动画
---@param dt number
function SkinShop.Update(dt)
    if flashTimer > 0 then
        flashTimer = flashTimer - dt
        if flashTimer < 0 then flashTimer = 0 end
    end
end

--- 重置状态
function SkinShop.Reset()
    selectedCharIdx = 1
    selectedSkinId = nil
    flashTimer = 0
    adLoading = false
end

--- 绘制皮肤商店全屏页面
---@param vg userdata
---@param fontId number
---@param DESIGN_W number
---@param DESIGN_H number
function SkinShop.Render(vg, fontId, DESIGN_W, DESIGN_H)
    local cx = DESIGN_W / 2
    local t  = time.elapsedTime

    -- 背景（深金暗色）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(20, 18, 10, 255))
    nvgFill(vg)
    local grad = nvgRadialGradient(vg, cx, DESIGN_H * 0.25, 80, 500,
        nvgRGBA(120, 100, 30, 45), nvgRGBA(20, 18, 10, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    nvgFontFaceId(vg, zpix)
    local zpix = HUD.zpixFontId >= 0 and HUD.zpixFontId or fontId
    local navH = 54

    -- ── 导航栏 ──
    local backW, backH = 90, 40
    local backX, backY = 12, (navH - backH) / 2
    SkinShop.backBtn = { x = backX, y = backY, w = backW, h = backH }
    drawCard(vg, backX, backY, backW, backH, 10,
             40, 35, 20, 180, 180, 160, 80, 80)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 19)
    nvgFillColor(vg, nvgRGBA(220, 200, 150, 220))
    nvgText(vg, backX + backW / 2, backY + backH / 2, "◀ 返回")

    -- 标题
    nvgFontSize(vg, 26)
    nvgFillColor(vg, nvgRGBA(255, 210, 80, 255))
    nvgText(vg, cx, navH / 2, "🎨 皮肤商店")

    -- 金币（zpix字体）
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
    nvgText(vg, DESIGN_W - 12, navH / 2, "🪙" .. tostring(SaveData.metaGold))
    nvgFontFaceId(vg, zpix)

    -- 分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, navH)
    nvgLineTo(vg, DESIGN_W, navH)
    nvgStrokeColor(vg, nvgRGBA(180, 150, 50, 80))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local curY = navH + 6

    -- ── 角色标签页 ──
    local tabMargin = 10
    local tabGap = 4
    local tabCount = #Config.CHARACTERS
    local tabW = (DESIGN_W - tabMargin * 2 - tabGap * (tabCount - 1)) / tabCount
    local tabH = 44
    charTabs = {}

    for i, char in ipairs(Config.CHARACTERS) do
        local tx = tabMargin + (i - 1) * (tabW + tabGap)
        local ty = curY
        local isSelected = (i == selectedCharIdx)

        if isSelected then
            drawCard(vg, tx, ty, tabW, tabH, 8,
                     255, 200, 60, 40, 255, 200, 60, 200)
        else
            drawCard(vg, tx, ty, tabW, tabH, 8,
                     255, 255, 255, 8, 120, 100, 60, 60)
        end

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 20)
        nvgFillColor(vg, isSelected and nvgRGBA(255, 255, 255, 255) or nvgRGBA(160, 140, 100, 160))
        nvgText(vg, tx + tabW / 2, ty + tabH / 2 - 2, char.emoji)

        -- 角色名（小字，zpix）
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 11)
        nvgFillColor(vg, isSelected and nvgRGBA(255, 220, 120, 200) or nvgRGBA(120, 100, 70, 120))
        nvgText(vg, tx + tabW / 2, ty + tabH - 6, char.name)
        nvgFontFaceId(vg, zpix)

        charTabs[i] = { x = tx, y = ty, w = tabW, h = tabH, charIdx = i }
    end

    curY = curY + tabH + 10

    -- ── 当前角色信息 ──
    local curChar = Config.CHARACTERS[selectedCharIdx]
    if not curChar then return end
    local charId = curChar.id
    local equippedSkinId = SaveData.GetEquippedSkin(charId)
    local charSkins = SkinSystem.GetSkinsForChar(charId)

    -- 角色预览区
    local previewH = 120
    local previewY = curY

    -- 预览背景
    drawCard(vg, 14, previewY, DESIGN_W - 28, previewH, 12,
             40, 35, 20, 150, 120, 100, 40, 60)

    -- 当前外观展示
    local previewEmoji = curChar.playerEmoji
    if equippedSkinId then
        local skin = SkinSystem.GetSkin(equippedSkinId)
        if skin then previewEmoji = skin.playerEmoji end
    end

    -- 中央大 emoji 展示（多状态循环）
    local states = { "idle", "move", "hit", "overload", "shield" }
    local stateIdx = math.floor(t * 0.8) % #states + 1
    local currentState = states[stateIdx]
    local displayEmoji = previewEmoji[currentState] or previewEmoji.idle

    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 48)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, cx, previewY + previewH / 2 - 6, displayEmoji)

    -- 状态标签
    local stateNames = { idle = "待机", move = "移动", hit = "受伤", overload = "过载", shield = "护盾" }
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(200, 180, 120, 160))
    nvgText(vg, cx, previewY + previewH - 12, stateNames[currentState] or currentState)

    -- 当前皮肤名称
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 120, 220))
    local skinLabel = "默认外观"
    if equippedSkinId then
        local skin = SkinSystem.GetSkin(equippedSkinId)
        if skin then skinLabel = "当前: " .. skin.name end
    end
    nvgText(vg, 24, previewY + 16, skinLabel)

    -- 卸下按钮（如果已装备皮肤）
    local unequipBtn = { x = 0, y = 0, w = 0, h = 0, visible = false }
    if equippedSkinId then
        local ubW, ubH = 64, 24
        local ubX = DESIGN_W - 28 - ubW + 6
        local ubY = previewY + 10
        drawCard(vg, ubX, ubY, ubW, ubH, 6,
                 120, 100, 40, 150, 160, 140, 60, 120)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(220, 200, 140, 200))
        nvgText(vg, ubX + ubW / 2, ubY + ubH / 2, "恢复默认")
        unequipBtn = { x = ubX, y = ubY, w = ubW, h = ubH, visible = true }
    end
    SkinShop._unequipBtn = unequipBtn

    curY = curY + previewH + 12

    -- 分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 14, curY)
    nvgLineTo(vg, DESIGN_W - 14, curY)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 40, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    curY = curY + 10

    -- ── 皮肤卡片列表 ──
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(200, 180, 120, 160))
    nvgText(vg, 14, curY + 4, "可用皮肤")
    curY = curY + 18

    skinCards = {}
    local cardMargin = 14
    local cardGap = 10
    local cardW = DESIGN_W - cardMargin * 2
    local cardH = 100

    if #charSkins == 0 then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 15)
        nvgFillColor(vg, nvgRGBA(140, 120, 80, 140))
        nvgText(vg, cx, curY + 40, "暂无皮肤")
    end

    for idx, skin in ipairs(charSkins) do
        local cy = curY + (idx - 1) * (cardH + cardGap)
        local owned = SaveData.IsSkinOwned(skin.id)
        local equipped = (equippedSkinId == skin.id)
        local selected = (selectedSkinId == skin.id)

        -- 卡片背景
        if equipped then
            local pulse = math.sin(t * 2 + idx) * 0.1 + 0.9
            drawCard(vg, cardMargin, cy, cardW, cardH, 12,
                     255, 200, 60, math.floor(30 * pulse), 255, 200, 60, math.floor(200 * pulse))
        elseif selected then
            drawCard(vg, cardMargin, cy, cardW, cardH, 12,
                     255, 220, 100, 20, 255, 210, 80, 180)
        elseif owned then
            drawCard(vg, cardMargin, cy, cardW, cardH, 12,
                     255, 255, 255, 10, 180, 160, 80, 80)
        else
            drawCard(vg, cardMargin, cy, cardW, cardH, 12,
                     50, 45, 30, 120, 100, 80, 40, 60)
        end

        -- 皮肤图标（大 emoji）
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 36)
        nvgFillColor(vg, owned and nvgRGBA(255, 255, 255, 255) or nvgRGBA(100, 80, 60, 140))
        nvgText(vg, cardMargin + 40, cy + cardH / 2, skin.icon)

        -- 皮肤名称
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFontSize(vg, 18)
        nvgFillColor(vg, owned and nvgRGBA(255, 220, 120, 255) or nvgRGBA(160, 140, 100, 180))
        nvgText(vg, cardMargin + 72, cy + 14, skin.name)

        -- 状态文字（zpix）
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 12)
        if equipped then
            nvgFillColor(vg, nvgRGBA(255, 200, 60, 220))
            nvgText(vg, cardMargin + 72, cy + 38, "✦ 使用中")
        elseif owned then
            nvgFillColor(vg, nvgRGBA(140, 200, 100, 200))
            nvgText(vg, cardMargin + 72, cy + 38, "✓ 已拥有")
        elseif skin.adUnlock then
            nvgFillColor(vg, nvgRGBA(100, 200, 255, 200))
            nvgText(vg, cardMargin + 72, cy + 38, I18n.t("skin_ad_price", skin.price))
        else
            nvgFillColor(vg, nvgRGBA(255, 200, 100, 180))
            nvgText(vg, cardMargin + 72, cy + 38, I18n.t("skin_price_fmt", skin.price))
        end
        nvgFontFaceId(vg, zpix)

        -- emoji 预览（右侧小图，展示 idle + move）
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 18)
        nvgFillColor(vg, owned and nvgRGBA(255, 255, 255, 200) or nvgRGBA(100, 80, 60, 100))
        local previewX = cardMargin + cardW - 60
        nvgText(vg, previewX, cy + cardH / 2 - 10, skin.playerEmoji.idle)
        nvgText(vg, previewX + 28, cy + cardH / 2 - 10, skin.playerEmoji.move)

        -- 子弹预览（小号）
        nvgFontSize(vg, 14)
        nvgText(vg, previewX, cy + cardH / 2 + 14, skin.bulletStyle.normal.emoji)
        nvgText(vg, previewX + 28, cy + cardH / 2 + 14, skin.bulletStyle.pierce.emoji)

        -- 操作按钮（右下角）
        local btnW, btnH = 72, 30
        local btnX = cardMargin + cardW - btnW - 8
        local btnY = cy + cardH - btnH - 8

        if equipped then
            -- 已装备，不显示按钮
        elseif owned then
            -- 已拥有：装备
            drawCard(vg, btnX, btnY, btnW, btnH, 8,
                     200, 170, 40, 220, 255, 210, 60, 255)
            nvgFontFaceId(vg, zpix)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "装备")
            nvgFontFaceId(vg, zpix)
            skinCards[#skinCards + 1] = { x = btnX, y = btnY, w = btnW, h = btnH, skinId = skin.id, action = "equip" }
        else
            if skin.adUnlock then
                -- 广告解锁按钮
                local adBtnW = 56
                drawCard(vg, btnX - adBtnW - 6, btnY, adBtnW, btnH, 8,
                         60, 160, 220, 200, 80, 180, 255, 220)
                nvgFontFaceId(vg, zpix)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFontSize(vg, 12)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, btnX - adBtnW - 6 + adBtnW / 2, btnY + btnH / 2, I18n.t("skin_ad_btn_short"))
                nvgFontFaceId(vg, zpix)
                skinCards[#skinCards + 1] = { x = btnX - adBtnW - 6, y = btnY, w = adBtnW, h = btnH, skinId = skin.id, action = "ad" }
            end
            -- 金币购买按钮
            local canAfford = SaveData.metaGold >= skin.price
            if canAfford then
                drawCard(vg, btnX, btnY, btnW, btnH, 8,
                         200, 170, 40, 220, 255, 210, 60, 255)
            else
                drawCard(vg, btnX, btnY, btnW, btnH, 8,
                         60, 50, 30, 180, 100, 80, 40, 120)
            end
            nvgFontFaceId(vg, zpix)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 12)
            nvgFillColor(vg, canAfford and nvgRGBA(255, 255, 255, 255) or nvgRGBA(120, 100, 70, 150))
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, I18n.t("skin_buy_price", skin.price))
            nvgFontFaceId(vg, zpix)
            skinCards[#skinCards + 1] = { x = btnX, y = btnY, w = btnW, h = btnH, skinId = skin.id, action = canAfford and "buy" or nil }
        end
    end

    -- ── 反馈消息 ──
    if flashTimer > 0 then
        local alpha = math.min(1, flashTimer / 0.3) * 255
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 20)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 150, DESIGN_H * 0.4 - 18, 300, 36, 12)
        nvgFillColor(vg, nvgRGBA(40, 35, 10, math.floor(alpha * 0.85)))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(255, 230, 150, math.floor(alpha)))
        nvgText(vg, cx, DESIGN_H * 0.4, flashMsg)
    end
end

--- 处理点击（设计坐标）
---@param dx number
---@param dy number
---@return string|nil "back" | nil
function SkinShop.HandleTouch(dx, dy)
    -- 返回按钮
    if hitTest(dx, dy, SkinShop.backBtn) then
        selectedSkinId = nil
        return "back"
    end

    -- 恢复默认按钮
    if SkinShop._unequipBtn and SkinShop._unequipBtn.visible and hitTest(dx, dy, SkinShop._unequipBtn) then
        local charId = Config.CHARACTERS[selectedCharIdx].id
        SaveData.UnequipSkin(charId)
        ShowFlash("已恢复默认外观")
        return nil
    end

    -- 角色标签页
    for _, tab in ipairs(charTabs) do
        if hitTest(dx, dy, tab) then
            if selectedCharIdx ~= tab.charIdx then
                selectedCharIdx = tab.charIdx
                selectedSkinId = nil
            end
            return nil
        end
    end

    -- 皮肤卡片操作按钮
    for _, card in ipairs(skinCards) do
        if hitTest(dx, dy, card) then
            if card.action == "equip" then
                local charId = Config.CHARACTERS[selectedCharIdx].id
                if SaveData.EquipSkin(charId, card.skinId) then
                    ShowFlash("装备成功！")
                else
                    ShowFlash("装备失败")
                end
            elseif card.action == "buy" then
                if adLoading then return nil end  -- 防止快速连点双重扣款
                adLoading = true
                local skin = SkinSystem.GetSkin(card.skinId)
                if skin and SaveData.SpendMetaGold(skin.price) then
                    SaveData.UnlockSkin(card.skinId)
                    ShowFlash("购买成功！-🪙" .. skin.price)
                else
                    ShowFlash("金币不足")
                end
                adLoading = false
            elseif card.action == "ad" then
                if adLoading then return nil end
                if sdk then
                    adLoading = true
                    sdk:ShowRewardVideoAd(function(result)
                        adLoading = false
                        if result.success then
                            SaveData.UnlockSkin(card.skinId)
                            ShowFlash("广告解锁成功！")
                        else
                            ShowFlash("广告未完成")
                        end
                    end)
                else
                    -- 无SDK时直接解锁（开发模式）
                    SaveData.UnlockSkin(card.skinId)
                    ShowFlash("开发模式：已解锁")
                end
            end
            return nil
        end
    end

    return nil
end

--- 处理触摸拖动开始（用于滚动，此商店暂不需要滚动）
function SkinShop.HandleDragBegin(dy) end
function SkinShop.HandleDragMove(dy) end
function SkinShop.HandleDragEnd() end

return SkinShop
