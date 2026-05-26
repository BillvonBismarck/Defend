--- ============================================================================
--- 图腾商店 UI - 图标网格 + 装备栏 + 底部详情 + 筛选/合成/出售
--- 装备槽与背包均只显示图标，点击后底部显示详情
--- ============================================================================

local TotemSystem = require("meta.TotemSystem")
local SaveData    = require("SaveData")
local HUD         = require("ui.HUD")
local I18n        = require("utils.I18n")

local TotemShop = {}

-- 触摸区域
TotemShop.backBtn = { x = 0, y = 0, w = 0, h = 0 }

-- 筛选
local filterRarity = "all"

-- 滚动
local scrollY     = 0
local scrollVel   = 0
local dragStartY  = nil
local dragLastY   = nil
local dragScrollStart = 0

-- 选中项（可以是背包索引或装备槽索引）
local selectedIdx     = nil   -- 背包索引（来自网格）
local selectedEquipSlot = nil -- 装备槽索引（来自装备栏）

-- 按钮区域
local filterBtns    = {}
local gridCells     = {}
local equipSlots    = {}
local actionBtns    = {}  -- { {x,y,w,h,id}, ... }
local batchSynthBtn = { x = 0, y = 0, w = 0, h = 0 }

-- 反馈动画
local flashTimer = 0
local flashMsg   = ""
local FLASH_DUR  = 1.2

-- 合成动画
local synthQueue      = {}
local synthAnimTimer  = 0
local synthAnimResult = nil
local synthAnimConsumed = nil
local SYNTH_ANIM_DUR  = 0.5
local SYNTH_INTERVAL  = 0.08
local synthTotalCount = 0
local synthDoneCount  = 0

-- 一键合成长按
local batchSynthPressStart = nil
local batchSynthPressDy    = 0
local LONG_PRESS_THRESHOLD = 0.5
local batchSynthContinuous = false

-- 筛选列表缓存
local filteredList = {}
local filteredDirty = true

local function ShowFlash(msg)
    flashMsg = msg
    flashTimer = FLASH_DUR
end

--- 清除所有选中
local function ClearSelection()
    selectedIdx = nil
    selectedEquipSlot = nil
end

--- 获取当前选中的图腾数据
local function GetSelectedTotem()
    if selectedEquipSlot then
        return SaveData.equippedTotems[selectedEquipSlot], "equipped", selectedEquipSlot
    elseif selectedIdx then
        return SaveData.totems[selectedIdx], "bag", selectedIdx
    end
    return nil, nil, nil
end

--- 更新动画
---@param dt number
function TotemShop.Update(dt)
    if flashTimer > 0 then
        flashTimer = flashTimer - dt
        if flashTimer < 0 then flashTimer = 0 end
    end

    -- 合成动画队列
    if synthAnimResult then
        synthAnimTimer = synthAnimTimer - dt
        if synthAnimTimer <= 0 then
            synthAnimResult = nil
            synthAnimConsumed = nil
            synthAnimTimer = 0
            if #synthQueue > 0 then
                synthAnimTimer = SYNTH_INTERVAL
            elseif batchSynthContinuous then
                local added = false
                for _, r in ipairs({ "junk", "normal", "rare" }) do
                    local cnt = 0
                    for _, tt in ipairs(SaveData.totems) do
                        if tt.rarity == r then cnt = cnt + 1 end
                    end
                    if cnt >= 3 then synthQueue[#synthQueue + 1] = r; added = true end
                end
                if added then
                    synthAnimTimer = SYNTH_INTERVAL
                else
                    batchSynthContinuous = false
                    if synthDoneCount > 0 then
                        ShowFlash("全部合成完成 ×" .. synthDoneCount)
                        synthDoneCount = 0; synthTotalCount = 0
                    end
                end
            elseif synthDoneCount > 0 then
                ShowFlash("合成完成 ×" .. synthDoneCount)
                synthDoneCount = 0; synthTotalCount = 0
            end
        end
    elseif #synthQueue > 0 then
        synthAnimTimer = synthAnimTimer - dt
        if synthAnimTimer <= 0 then
            local rarity = table.remove(synthQueue, 1)
            local result, consumed = SaveData.SynthesizeTotems(rarity)
            if result then
                synthDoneCount = synthDoneCount + 1
                synthAnimResult = result
                synthAnimConsumed = consumed
                synthAnimTimer = SYNTH_ANIM_DUR
                filteredDirty = true
                ClearSelection()
            end
        end
    end

    -- 惯性滚动
    if not dragStartY then
        if math.abs(scrollVel) > 0.5 then
            scrollY = scrollY + scrollVel * dt
            scrollVel = scrollVel * (1 - 8 * dt)
        else
            scrollVel = 0
        end
    end
end

--- 重建筛选列表
local function RebuildFilteredList()
    filteredList = {}
    for i, totem in ipairs(SaveData.totems) do
        if filterRarity == "all" or totem.rarity == filterRarity then
            filteredList[#filteredList + 1] = { bagIdx = i, totem = totem }
        end
    end
    filteredDirty = false
end

-- ── 辅助 ──

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

-- 筛选标签（label 在渲染时通过 I18n.t 动态获取）
local FILTER_TABS = {
    { id = "all",       labelKey = "totem_rarity_all" },
    { id = "junk",      labelKey = "totem_rarity_junk" },
    { id = "normal",    labelKey = "totem_rarity_normal" },
    { id = "rare",      labelKey = "totem_rarity_rare" },
    { id = "legendary", labelKey = "totem_rarity_legend" },
}

--- 绘制图腾商店全屏页面
---@param vg userdata
---@param fontId number
---@param DESIGN_W number
---@param DESIGN_H number
function TotemShop.Render(vg, fontId, DESIGN_W, DESIGN_H)
    local cx = DESIGN_W / 2
    local t  = time.elapsedTime

    RebuildFilteredList()

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(14, 18, 36, 255))
    nvgFill(vg)
    local grad = nvgRadialGradient(vg, cx, DESIGN_H * 0.3, 80, 480,
        nvgRGBA(60, 30, 120, 50), nvgRGBA(14, 18, 36, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    nvgFontFaceId(vg, zpix)
    local zpix = HUD.zpixFontId >= 0 and HUD.zpixFontId or fontId
    local navH = 56

    -- ── 导航栏 ──
    local backW, backH = 90, 42
    local backX, backY = 12, (navH - backH) / 2
    TotemShop.backBtn = { x = backX, y = backY, w = backW, h = backH }
    drawCard(vg, backX, backY, backW, backH, 10,
             30, 25, 60, 180, 150, 150, 200, 80)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 220))
    nvgText(vg, backX + backW / 2, backY + backH / 2, "◀ 返回")

    -- 标题
    nvgFontSize(vg, 28)
    nvgFillColor(vg, nvgRGBA(180, 140, 255, 255))
    nvgText(vg, cx, navH / 2, "🏺 图腾背包")

    -- 金币 + 容量（zpix字体）
    nvgFontFaceId(vg, zpix)
    local capStr = #SaveData.totems .. "/" .. TotemSystem.MAX_INVENTORY
    local goldStr = "🪙" .. tostring(SaveData.metaGold)
    nvgFontSize(vg, 17)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
    nvgText(vg, DESIGN_W - 12, navH / 2 - 9, goldStr)
    nvgFillColor(vg, nvgRGBA(180, 170, 220, 180))
    nvgText(vg, DESIGN_W - 12, navH / 2 + 9, capStr)
    nvgFontFaceId(vg, zpix)

    -- 分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, navH)
    nvgLineTo(vg, DESIGN_W, navH)
    nvgStrokeColor(vg, nvgRGBA(80, 60, 160, 80))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local curY = navH + 6

    -- ── 已装备图腾槽（3个，只显示图标） ──
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(160, 150, 200, 160))
    nvgText(vg, 14, curY + 8, "已装备")
    curY = curY + 22

    local slotMargin = 14
    local slotGap = 10
    local slotSize = 66
    equipSlots = {}

    for i = 1, TotemSystem.MAX_EQUIPPED do
        local sx = slotMargin + (i - 1) * (slotSize + slotGap)
        local sy = curY
        local totem = SaveData.equippedTotems[i]
        equipSlots[i] = { x = sx, y = sy, w = slotSize, h = slotSize, slotIdx = i }

        local isSelected = (selectedEquipSlot == i)

        if totem then
            local rc = TotemSystem.GetRarityConfig(totem.rarity)
            local c = rc.color
            if isSelected then
                drawCard(vg, sx, sy, slotSize, slotSize, 10,
                         c[1], c[2], c[3], 60, c[1], c[2], c[3], 255)
            else
                drawCard(vg, sx, sy, slotSize, slotSize, 10,
                         c[1], c[2], c[3], 25, c[1], c[2], c[3], 160)
            end
            -- 大图标
            nvgFontSize(vg, 32)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
            nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, TotemSystem.GetTotemIcon(totem.typeId))
            -- 稀有度角标
            nvgBeginPath(vg)
            nvgCircle(vg, sx + slotSize - 8, sy + 8, 5)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 220))
            nvgFill(vg)
        else
            drawCard(vg, sx, sy, slotSize, slotSize, 10,
                     40, 35, 70, 100, 80, 70, 140, 60)
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(80, 70, 120, 100))
            nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, "+")
        end
    end
    curY = curY + slotSize + 4

    -- ── 加成汇总 ──
    local bonuses = TotemSystem.CalcEquippedBonuses(SaveData.equippedTotems)
    local hasAnyBonus = false
    if bonuses.hpFlat > 0 or bonuses.atkFlat > 0 or bonuses.spdFlat > 0 then hasAnyBonus = true end
    if bonuses.critBonus > 0 or bonuses.fireRateBonus > 0 or bonuses.hpRegenBonus > 0 then hasAnyBonus = true end
    if bonuses.lootBonus > 0 or #bonuses.skillTotems > 0 or bonuses.hasCrossClass then hasAnyBonus = true end
    if hasAnyBonus then
        nvgFontFaceId(vg, zpix)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local bonusParts = {}
        if bonuses.hpFlat > 0 then bonusParts[#bonusParts + 1] = "HP+" .. math.floor(bonuses.hpFlat) end
        if bonuses.atkFlat > 0 then bonusParts[#bonusParts + 1] = "ATK+" .. string.format("%.1f", bonuses.atkFlat) end
        if bonuses.spdFlat > 0 then bonusParts[#bonusParts + 1] = "SPD+" .. math.floor(bonuses.spdFlat) end
        if bonuses.critBonus > 0 then bonusParts[#bonusParts + 1] = I18n.t("totem_bonus_crit", math.floor(bonuses.critBonus * 100)) end
        if bonuses.fireRateBonus > 0 then bonusParts[#bonusParts + 1] = I18n.t("totem_bonus_firerate", math.floor(bonuses.fireRateBonus * 100)) end
        if bonuses.hpRegenBonus > 0 then bonusParts[#bonusParts + 1] = I18n.t("totem_bonus_regen", bonuses.hpRegenBonus * 100) end
        if bonuses.lootBonus > 0 then bonusParts[#bonusParts + 1] = I18n.t("totem_bonus_loot", math.floor(bonuses.lootBonus * 100)) end
        for _, sid in ipairs(bonuses.skillTotems) do
            local stc = TotemSystem.TYPE_CONFIG[sid]
            if stc then bonusParts[#bonusParts + 1] = stc.icon .. stc.name end
        end
        if bonuses.hasCrossClass then bonusParts[#bonusParts + 1] = "🌀" .. I18n.t("totem_cross_talent") end
        local lineSize = 4
        for lineStart = 1, #bonusParts, lineSize do
            local lineEnd = math.min(lineStart + lineSize - 1, #bonusParts)
            local lineParts = {}
            for k = lineStart, lineEnd do lineParts[#lineParts + 1] = bonusParts[k] end
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(180, 255, 180, 180))
            local prefix = (lineStart == 1) and I18n.t("totem_bonus_prefix") or ""
            nvgText(vg, cx, curY + 7, prefix .. table.concat(lineParts, "  "))
            curY = curY + 17
        end
        curY = curY + 2
        nvgFontFaceId(vg, zpix)
    end

    -- ── 筛选标签 ──
    local tabH = 34
    local tabGap2 = 5
    local tabTotalW = 0
    local tabWidths = {}
    nvgFontSize(vg, 15)
    nvgFontFaceId(vg, zpix)
    local rarCounts = TotemSystem.CountByRarity(SaveData.totems)
    for _, tab in ipairs(FILTER_TABS) do
        local cnt = (tab.id == "all") and #SaveData.totems or (rarCounts[tab.id] or 0)
        local label = I18n.t(tab.labelKey) .. "(" .. cnt .. ")"
        local tw = nvgTextBounds(vg, 0, 0, label) + 14
        tabWidths[#tabWidths + 1] = { w = tw, label = label, id = tab.id }
        tabTotalW = tabTotalW + tw + tabGap2
    end
    tabTotalW = tabTotalW - tabGap2
    local tabStartX = (DESIGN_W - tabTotalW) / 2
    filterBtns = {}

    for i, tw in ipairs(tabWidths) do
        local tx = tabStartX
        local ty = curY
        local isActive = (filterRarity == tw.id)
        filterBtns[i] = { x = tx, y = ty, w = tw.w, h = tabH, rarity = tw.id }

        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, ty, tw.w, tabH, 6)
        if isActive then
            nvgFillColor(vg, nvgRGBA(180, 140, 255, 50))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(180, 140, 255, 200))
        else
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 8))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(150, 150, 180, 60))
        end
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 15)
        nvgFillColor(vg, isActive and nvgRGBA(200, 170, 255, 255) or nvgRGBA(150, 150, 180, 180))
        nvgText(vg, tx + tw.w / 2, ty + tabH / 2, tw.label)
        tabStartX = tabStartX + tw.w + tabGap2
    end
    nvgFontFaceId(vg, zpix)
    curY = curY + tabH + 4

    -- ── 一键合成按钮 ──
    local showBatchSynth = false
    do
        for _, r in ipairs({ "junk", "normal", "rare" }) do
            if (rarCounts[r] or 0) >= 3 then showBatchSynth = true; break end
        end
    end

    batchSynthBtn = { x = 0, y = 0, w = 0, h = 0 }
    if showBatchSynth then
        local bsH = 40
        local bsX = 14
        local bsY = curY
        local bsW = DESIGN_W - 28
        batchSynthBtn = { x = bsX, y = bsY, w = bsW, h = bsH }

        local isSynthRunning = (#synthQueue > 0 or synthAnimResult ~= nil)
        local isPressed = (batchSynthPressStart ~= nil)
        local holdTime = isPressed and (time.elapsedTime - batchSynthPressStart) or 0
        local isLong = holdTime >= LONG_PRESS_THRESHOLD

        local bgAlpha = isPressed and 60 or 35
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bsX, bsY, bsW, bsH, 8)
        if isSynthRunning then
            nvgFillColor(vg, nvgRGBA(100, 80, 160, 25))
        else
            nvgFillColor(vg, nvgRGBA(200, 120, 255, bgAlpha))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 120, 255, isSynthRunning and 80 or 160))
        nvgStrokeWidth(vg, isPressed and 2 or 1.5)
        nvgStroke(vg)

        -- 长按进度条
        if isPressed and holdTime > 0 then
            local prog = math.min(1, holdTime / LONG_PRESS_THRESHOLD)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bsX + 2, bsY + bsH - 5, (bsW - 4) * prog, 3, 1.5)
            nvgFillColor(vg, nvgRGBA(255, 200, 80, isLong and 255 or 180))
            nvgFill(vg)
        end

        nvgFontFaceId(vg, zpix)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isSynthRunning then
            nvgFontSize(vg, 17)
            nvgFillColor(vg, nvgRGBA(180, 160, 220, 160))
            nvgText(vg, bsX + bsW / 2, bsY + bsH / 2, "合成中… 点击可打断")
        else
            nvgFontSize(vg, 17)
            nvgFillColor(vg, nvgRGBA(200, 120, 255, 240))
            local mainLabel = isPressed and (isLong and "松手：全部合成" or "按住中…") or "⚡ 一键合成（短按一组|长按全部）"
            nvgText(vg, bsX + bsW / 2, bsY + bsH / 2, mainLabel)
        end
        nvgFontFaceId(vg, zpix)
        curY = curY + bsH + 4
    end

    -- ── 背包网格 ──
    -- 底部详情面板高度
    local selTotem = GetSelectedTotem()
    local detailH = selTotem and 180 or 0

    local gridTop = curY
    local gridBottom = DESIGN_H - 6 - detailH
    local gridH = gridBottom - gridTop
    local gridMargin = 8
    local cellGap = 5
    local cols = 7
    local cellW = (DESIGN_W - gridMargin * 2 - cellGap * (cols - 1)) / cols
    local cellH = cellW  -- 正方形

    local totalRows = math.ceil(#filteredList / cols)
    local contentH = totalRows * (cellH + cellGap)

    local maxScroll = math.max(0, contentH - gridH)
    if scrollY < 0 then scrollY = 0 end
    if scrollY > maxScroll then scrollY = maxScroll end

    nvgSave(vg)
    nvgScissor(vg, 0, gridTop, DESIGN_W, gridH)

    gridCells = {}
    for fi, entry in ipairs(filteredList) do
        local row = math.floor((fi - 1) / cols)
        local col = (fi - 1) % cols
        local gx = gridMargin + col * (cellW + cellGap)
        local gy = gridTop + row * (cellH + cellGap) - scrollY

        if gy + cellH >= gridTop and gy <= gridBottom then
            local totem = entry.totem
            local rc = TotemSystem.GetRarityConfig(totem.rarity)
            local c = rc.color
            local isSelected = (entry.bagIdx == selectedIdx and selectedEquipSlot == nil)

            gridCells[#gridCells + 1] = { x = gx, y = gy, w = cellW, h = cellH, bagIdx = entry.bagIdx }

            -- 背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, gx, gy, cellW, cellH, 6)
            if isSelected then
                nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 60))
            else
                nvgFillColor(vg, nvgRGBA(30, 25, 60, 180))
            end
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], isSelected and 255 or 80))
            nvgStrokeWidth(vg, isSelected and 2 or 1)
            nvgStroke(vg)

            -- 图标
            nvgFontSize(vg, cellW * 0.52)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
            nvgText(vg, gx + cellW / 2, gy + cellH / 2, TotemSystem.GetTotemIcon(totem.typeId))

            -- 稀有度角标
            nvgBeginPath(vg)
            nvgCircle(vg, gx + 7, gy + 7, 4)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 220))
            nvgFill(vg)
        end
    end

    -- 空背包提示
    if #filteredList == 0 then
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 130, 180, 150))
        local emptyMsg = (#SaveData.totems == 0) and I18n.t("totem_empty_bag") or I18n.t("totem_none_cat")
        nvgText(vg, cx, gridTop + gridH / 2, emptyMsg)
    end

    nvgRestore(vg)

    -- 滚动指示器
    if contentH > gridH then
        local scrollBarH = math.max(20, gridH * (gridH / contentH))
        local scrollBarY = gridTop + (scrollY / maxScroll) * (gridH - scrollBarH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, DESIGN_W - 4, scrollBarY, 3, scrollBarH, 1.5)
        nvgFillColor(vg, nvgRGBA(180, 140, 255, 80))
        nvgFill(vg)
    end

    -- ── 底部详情面板 ──
    actionBtns = {}
    if selTotem then
        local totem, source, idx = GetSelectedTotem()
        local rc = TotemSystem.GetRarityConfig(totem.rarity)
        local c = rc.color
        local tc = TotemSystem.TYPE_CONFIG[totem.typeId]

        local panelY = DESIGN_H - detailH
        local panelH = detailH

        -- 面板背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 6, panelY, DESIGN_W - 12, panelH - 4, 14)
        nvgFillColor(vg, nvgRGBA(20, 15, 50, 245))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], 140))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        local px = 20
        local py = panelY + 14

        -- 图标 + 名称
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 32)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, px, py + 16, TotemSystem.GetTotemIcon(totem.typeId))

        local totemName = TotemSystem.GetTotemName(totem.typeId, totem.rarity)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 255))
        nvgText(vg, px + 44, py + 10, totemName)

        -- 稀有度标签
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 180))
        nvgText(vg, px + 44, py + 28, I18n.t("totem_quality_fmt", rc.name))
        py = py + 48

        -- 描述
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(220, 210, 240, 230))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local desc = TotemSystem.GetTotemDesc(totem.typeId, totem.rarity)
        nvgTextBox(vg, px, py, DESIGN_W - px * 2, desc)
        py = py + 38

        -- 操作按钮行
        local btnY = py + 2
        local btnH = 38
        local btnGap = 10
        local btnList = {}

        if source == "equipped" then
            btnList[#btnList + 1] = { id = "unequip", label = I18n.t("totem_btn_unequip"), color = { 200, 100, 100 } }
        elseif source == "bag" then
            if #SaveData.equippedTotems < TotemSystem.MAX_EQUIPPED then
                btnList[#btnList + 1] = { id = "equip", label = I18n.t("totem_btn_equip"), color = { 80, 200, 130 } }
            end
            local sp = TotemSystem.GetSellPrice(totem.rarity)
            btnList[#btnList + 1] = { id = "sell", label = I18n.t("totem_btn_sell", sp), color = { 255, 160, 80 } }
        end

        -- 批量卖垃圾（仅在未选中装备栏时显示）
        local junkCount = rarCounts.junk or 0
        if source == "bag" and junkCount > 0 then
            btnList[#btnList + 1] = { id = "sellJunk", label = I18n.t("totem_btn_sell_junk", junkCount), color = { 200, 160, 80 } }
        end

        if #btnList > 0 then
            local totalBtnW = DESIGN_W - 40
            local btnW = (totalBtnW - btnGap * (#btnList - 1)) / #btnList
            for bi, btn in ipairs(btnList) do
                local bx = 20 + (bi - 1) * (btnW + btnGap)
                local bc = btn.color
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx, btnY, btnW, btnH, 8)
                nvgFillColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 40))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 180))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
                nvgFontFaceId(vg, zpix)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFontSize(vg, 17)
                nvgFillColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 240))
                nvgText(vg, bx + btnW / 2, btnY + btnH / 2, btn.label)
                nvgFontFaceId(vg, zpix)
                actionBtns[#actionBtns + 1] = { x = bx, y = btnY, w = btnW, h = btnH, id = btn.id }
            end
        end
    end

    -- ── 合成动画浮层 ──
    if synthAnimResult then
        local prog = 1 - synthAnimTimer / SYNTH_ANIM_DUR
        local saRc = TotemSystem.RARITY_CONFIG[synthAnimResult.rarity]
        local saTc = TotemSystem.TYPE_CONFIG[synthAnimResult.typeId]
        local cr, cg, cb = saRc.color[1], saRc.color[2], saRc.color[3]
        local animCx, animCy = cx, DESIGN_H * 0.42

        local bgAlpha = (prog < 0.75) and 120 or math.floor(120 * (1 - (prog - 0.75) / 0.25))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, bgAlpha))
        nvgFill(vg)

        if prog < 0.35 and synthAnimConsumed then
            local p1 = prog / 0.35
            local startR = 55
            local curR = startR * (1 - p1)
            local matAlpha = math.floor(255 * (1 - p1 * 0.6))
            local matScale = 22 * (1 - p1 * 0.4)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            for i, mat in ipairs(synthAnimConsumed) do
                local angle = (i - 1) * 2.094 - 1.571
                local mx = animCx + math.cos(angle) * curR
                local my = animCy + math.sin(angle) * curR
                local matTc = TotemSystem.TYPE_CONFIG[mat.typeId]
                local matIcon = matTc and matTc.icon or "🔮"
                local matRc = TotemSystem.RARITY_CONFIG[mat.rarity]
                nvgBeginPath(vg)
                nvgCircle(vg, mx, my, matScale * 0.8)
                nvgFillColor(vg, nvgRGBA(matRc.color[1], matRc.color[2], matRc.color[3], math.floor(matAlpha * 0.3)))
                nvgFill(vg)
                nvgFontSize(vg, matScale)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, matAlpha))
                nvgText(vg, mx, my, matIcon)
            end
            if p1 > 0.3 then
                local lineAlpha = math.floor(180 * ((p1 - 0.3) / 0.7))
                nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, lineAlpha))
                nvgStrokeWidth(vg, 1.5)
                for i, mat in ipairs(synthAnimConsumed) do
                    local angle = (i - 1) * 2.094 - 1.571
                    local mx = animCx + math.cos(angle) * curR
                    local my = animCy + math.sin(angle) * curR
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, mx, my)
                    nvgLineTo(vg, animCx, animCy)
                    nvgStroke(vg)
                end
            end
        end

        if prog >= 0.3 then
            local p2 = math.min(1, (prog - 0.3) / 0.4)
            local resultAlpha = 255
            local scale = 1.0
            if p2 < 0.4 then
                scale = 0.3 + 0.7 * (p2 / 0.4)
                scale = scale + math.sin(p2 / 0.4 * math.pi) * 0.15
            end
            if prog > 0.75 then
                resultAlpha = math.floor(255 * (1 - (prog - 0.75) / 0.25))
            end
            local glowR = 50 * scale
            nvgBeginPath(vg)
            nvgCircle(vg, animCx, animCy, glowR)
            nvgFillColor(vg, nvgRGBA(cr, cg, cb, math.floor(resultAlpha * 0.25)))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, animCx, animCy, glowR * 0.7)
            nvgFillColor(vg, nvgRGBA(cr, cg, cb, math.floor(resultAlpha * 0.4)))
            nvgFill(vg)
            nvgFontSize(vg, math.floor(36 * scale))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, resultAlpha))
            local icon = saTc and saTc.icon or "🔮"
            nvgText(vg, animCx, animCy, icon)
            local totemName = TotemSystem.GetTotemName(synthAnimResult.typeId, synthAnimResult.rarity)
            nvgFontSize(vg, math.floor(20 * scale))
            nvgFillColor(vg, nvgRGBA(cr, cg, cb, resultAlpha))
            nvgText(vg, animCx, animCy + 50 * scale, totemName)
            if synthTotalCount > 0 or synthDoneCount > 0 then
                nvgFontFaceId(vg, zpix)
                nvgFontSize(vg, 15)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, math.floor(resultAlpha * 0.7)))
                nvgText(vg, animCx, animCy + 72 * scale,
                        synthDoneCount .. "/" .. (synthDoneCount + #synthQueue))
                nvgFontFaceId(vg, zpix)
            end
        end
    end

    -- ── 反馈消息浮层 ──
    if flashTimer > 0 then
        local alpha = math.min(1, flashTimer / 0.3) * 255
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local msgW = nvgTextBounds(vg, 0, 0, flashMsg) + 40
        local msgH = 42
        local msgX = cx - msgW / 2
        local msgY = DESIGN_H / 2 - msgH / 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, msgX, msgY, msgW, msgH, 10)
        nvgFillColor(vg, nvgRGBA(20, 15, 50, math.floor(alpha * 0.85)))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(180, 140, 255, math.floor(alpha * 0.6)))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha)))
        nvgText(vg, cx, DESIGN_H / 2, flashMsg)
    end
end

--- 处理触摸拖动开始
function TotemShop.HandleDragBegin(dy)
    dragStartY = dy
    dragLastY = dy
    dragScrollStart = scrollY
    scrollVel = 0
end

--- 处理触摸拖动移动
function TotemShop.HandleDragMove(dy)
    if dragStartY then
        scrollY = dragScrollStart - (dy - dragStartY)
        scrollVel = -(dy - (dragLastY or dy)) * 20
        dragLastY = dy
    end
    if batchSynthPressStart and math.abs(dy - batchSynthPressDy) > 8 then
        batchSynthPressStart = nil
    end
end

--- 处理触摸拖动结束
function TotemShop.HandleDragEnd()
    dragStartY = nil
    dragLastY = nil

    -- 一键合成松手触发
    if batchSynthPressStart then
        local holdTime = time.elapsedTime - batchSynthPressStart
        batchSynthPressStart = nil
        if #synthQueue > 0 or synthAnimResult then return end

        if holdTime >= LONG_PRESS_THRESHOLD then
            local queue = {}
            for _, r in ipairs({ "junk", "normal", "rare" }) do
                local cnt = 0
                for _, tt in ipairs(SaveData.totems) do
                    if tt.rarity == r then cnt = cnt + 1 end
                end
                if cnt >= 3 then queue[#queue + 1] = r end
            end
            if #queue > 0 then
                synthQueue = queue
                synthDoneCount = 0; synthTotalCount = 0; synthAnimTimer = 0
                ClearSelection(); filteredDirty = true; batchSynthContinuous = true
            else
                ShowFlash("无可合成图腾")
            end
        else
            local found = nil
            for _, r in ipairs({ "junk", "normal", "rare" }) do
                local cnt = 0
                for _, tt in ipairs(SaveData.totems) do
                    if tt.rarity == r then cnt = cnt + 1 end
                end
                if cnt >= 3 then found = r; break end
            end
            if found then
                synthQueue = { found }
                synthDoneCount = 0; synthTotalCount = 0; synthAnimTimer = 0
                ClearSelection(); filteredDirty = true; batchSynthContinuous = false
            else
                ShowFlash("无可合成图腾")
            end
        end
    end
end

--- 处理点击（设计坐标）
---@param dx number
---@param dy number
---@return string|nil "back" | nil
function TotemShop.HandleTouch(dx, dy)
    -- 返回按钮
    if hitTest(dx, dy, TotemShop.backBtn) then
        ClearSelection()
        scrollY = 0; scrollVel = 0; filterRarity = "all"
        return "back"
    end

    -- 详情面板的操作按钮
    for _, btn in ipairs(actionBtns) do
        if hitTest(dx, dy, btn) then
            if btn.id == "equip" and selectedIdx then
                if SaveData.EquipTotem(selectedIdx) then
                    ShowFlash("装备成功！")
                    ClearSelection()
                else
                    ShowFlash("装备栏已满")
                end
            elseif btn.id == "unequip" and selectedEquipSlot then
                SaveData.UnequipTotem(selectedEquipSlot)
                ShowFlash("已卸下图腾")
                ClearSelection()
            elseif btn.id == "sell" and selectedIdx then
                local totem = SaveData.totems[selectedIdx]
                if totem then
                    local price = TotemSystem.GetSellPrice(totem.rarity)
                    SaveData.SellTotem(selectedIdx)
                    ShowFlash("出售 +🪙" .. price)
                    ClearSelection()
                end
            elseif btn.id == "sellJunk" then
                local gold, count = SaveData.SellAllByRarity("junk")
                if count > 0 then
                    ShowFlash("批量出售 ×" .. count .. " +🪙" .. gold)
                    ClearSelection()
                end
            end
            return nil
        end
    end

    -- 装备槽：点击选中查看详情
    for _, slot in ipairs(equipSlots) do
        if hitTest(dx, dy, slot) then
            if SaveData.equippedTotems[slot.slotIdx] then
                if selectedEquipSlot == slot.slotIdx then
                    ClearSelection()
                else
                    selectedIdx = nil
                    selectedEquipSlot = slot.slotIdx
                end
            end
            return nil
        end
    end

    -- 筛选标签
    for _, btn in ipairs(filterBtns) do
        if hitTest(dx, dy, btn) then
            filterRarity = btn.rarity
            ClearSelection()
            scrollY = 0; scrollVel = 0
            return nil
        end
    end

    -- 一键合成按钮
    if batchSynthBtn.w > 0 and hitTest(dx, dy, batchSynthBtn) then
        if #synthQueue > 0 or synthAnimResult then
            synthQueue = {}; batchSynthContinuous = false
            ShowFlash("已打断合成")
            return nil
        end
        batchSynthPressStart = time.elapsedTime
        batchSynthPressDy = dy
        return nil
    end

    -- 合成进行中时，点击其他区域也可打断
    if #synthQueue > 0 or (synthAnimResult and batchSynthContinuous) then
        synthQueue = {}; batchSynthContinuous = false
        ShowFlash("已打断合成")
        return nil
    end

    -- 背包网格点击：选中/取消选中
    for _, cell in ipairs(gridCells) do
        if hitTest(dx, dy, cell) then
            if selectedIdx == cell.bagIdx and selectedEquipSlot == nil then
                ClearSelection()
            else
                selectedEquipSlot = nil
                selectedIdx = cell.bagIdx
            end
            return nil
        end
    end

    return nil
end

--- 处理鼠标滚轮
function TotemShop.HandleWheel(wheel)
    if wheel ~= 0 then
        scrollY = scrollY - wheel * 60
        scrollVel = 0
    end
end

--- 重置状态
function TotemShop.Reset()
    ClearSelection()
    scrollY = 0; scrollVel = 0; filterRarity = "all"
    flashTimer = 0; dragStartY = nil
    synthQueue = {}; synthAnimTimer = 0; synthAnimResult = nil
    synthTotalCount = 0; synthDoneCount = 0
    batchSynthPressStart = nil; batchSynthContinuous = false
end

return TotemShop
