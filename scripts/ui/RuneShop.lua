--- ============================================================================
--- 符文管理 UI - 图标网格 + 装备槽 + 底部详情面板
--- 装备槽与背包均只显示图标，点击后底部显示详情
--- ============================================================================

local RuneSystem = require("meta.RuneSystem")
local SaveData   = require("SaveData")
local HUD        = require("ui.HUD")
local I18n       = require("utils.I18n")

local RuneShop = {}

-- 触摸区域
RuneShop.backBtn = { x = 0, y = 0, w = 0, h = 0 }

-- 选中（来源可以是装备槽或网格）
local selectedRuneId = nil

-- 滚动
local scrollY     = 0
local scrollVel   = 0
local dragStartY  = nil
local dragLastY   = nil
local dragScrollStart = 0

-- 按钮区域
local equipSlots  = {}  -- { {x,y,w,h,slotIdx}, ... }
local gridCells   = {}  -- { {x,y,w,h,runeId}, ... }
local equipBtn    = { x = 0, y = 0, w = 0, h = 0, visible = false }

-- 反馈动画
local flashTimer = 0
local flashMsg   = ""
local FLASH_DUR  = 1.2

local function ShowFlash(msg)
    flashMsg = msg
    flashTimer = FLASH_DUR
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

local function IsRuneEquipped(runeId)
    for _, rid in ipairs(SaveData.equippedRunes) do
        if rid == runeId then return true end
    end
    return false
end

local function GetEquippedSlot(runeId)
    for i, rid in ipairs(SaveData.equippedRunes) do
        if rid == runeId then return i end
    end
    return nil
end

--- 更新动画
---@param dt number
function RuneShop.Update(dt)
    if flashTimer > 0 then
        flashTimer = flashTimer - dt
        if flashTimer < 0 then flashTimer = 0 end
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

--- 重置状态
function RuneShop.Reset()
    selectedRuneId = nil
    scrollY = 0
    scrollVel = 0
    flashTimer = 0
    dragStartY = nil
end

--- 绘制符文管理全屏页面
---@param vg userdata
---@param fontId number
---@param DESIGN_W number
---@param DESIGN_H number
function RuneShop.Render(vg, fontId, DESIGN_W, DESIGN_H)
    local cx = DESIGN_W / 2
    local t  = time.elapsedTime

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(20, 12, 14, 255))
    nvgFill(vg)
    local grad = nvgRadialGradient(vg, cx, DESIGN_H * 0.3, 80, 480,
        nvgRGBA(120, 30, 30, 50), nvgRGBA(20, 12, 14, 0))
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
    RuneShop.backBtn = { x = backX, y = backY, w = backW, h = backH }
    drawCard(vg, backX, backY, backW, backH, 10,
             40, 25, 28, 180, 150, 100, 100, 80)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(200, 180, 180, 220))
    nvgText(vg, backX + backW / 2, backY + backH / 2, "◀ 返回")

    -- 标题
    nvgFontSize(vg, 28)
    nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
    nvgText(vg, cx, navH / 2, "🔮 符文管理")

    -- 拥有数（zpix字体）
    local ownedCount = RuneSystem.GetOwnedCount(SaveData.ownedRunes)
    local totalCount = RuneSystem.GetTotalCount()
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 17)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 150, 150, 180))
    nvgText(vg, DESIGN_W - 12, navH / 2, ownedCount .. "/" .. totalCount)
    nvgFontFaceId(vg, zpix)

    -- 分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, navH)
    nvgLineTo(vg, DESIGN_W, navH)
    nvgStrokeColor(vg, nvgRGBA(160, 40, 40, 80))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local curY = navH + 8

    -- ── 已装备栏（2槽） - 只显示图标 ──
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(200, 140, 140, 160))
    nvgText(vg, 14, curY + 8, "已装备")
    curY = curY + 22

    local slotMargin = 14
    local slotGap = 12
    local slotSize = 72  -- 正方形图标槽
    equipSlots = {}

    for i = 1, RuneSystem.MAX_EQUIPPED do
        local sx = slotMargin + (i - 1) * (slotSize + slotGap)
        local sy = curY
        local runeId = SaveData.equippedRunes[i]
        equipSlots[i] = { x = sx, y = sy, w = slotSize, h = slotSize, slotIdx = i, runeId = runeId }

        local isSelected = (runeId and runeId == selectedRuneId)

        if runeId then
            local rune = RuneSystem.GetRune(runeId)
            if rune then
                local pulse = math.sin(t * 2 + i) * 0.15 + 0.85
                if isSelected then
                    drawCard(vg, sx, sy, slotSize, slotSize, 12,
                             255, 60, 60, 60, 255, 100, 100, 255)
                else
                    drawCard(vg, sx, sy, slotSize, slotSize, 12,
                             255, 50, 50, math.floor(25 * pulse), 255, 60, 60, math.floor(180 * pulse))
                end
                -- 大图标
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFontSize(vg, 36)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, rune.icon)
                -- 装备角标
                nvgFontSize(vg, 12)
                nvgFillColor(vg, nvgRGBA(255, 200, 80, 220))
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgText(vg, sx + slotSize - 4, sy + 4, "✦")
            end
        else
            drawCard(vg, sx, sy, slotSize, slotSize, 12,
                     40, 25, 28, 100, 120, 60, 60, 60)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 16)
            nvgFillColor(vg, nvgRGBA(120, 80, 80, 100))
            nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, "空")
        end
    end

    curY = curY + slotSize + 10

    -- 分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 14, curY)
    nvgLineTo(vg, DESIGN_W - 14, curY)
    nvgStrokeColor(vg, nvgRGBA(120, 40, 40, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    curY = curY + 6

    -- ── 符文收藏标题 ──
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(200, 140, 140, 160))
    nvgText(vg, 14, curY + 8, "符文收藏")
    curY = curY + 22

    -- ── 符文网格（7列，只显示图标） ──
    local gridMargin = 10
    local gridGap = 6
    local cols = 7
    local cellW = (DESIGN_W - gridMargin * 2 - gridGap * (cols - 1)) / cols
    local cellH = cellW  -- 正方形格子

    -- 底部详情面板高度
    local detailH = selectedRuneId and 200 or 0

    -- 滚动区域
    local gridAreaTop = curY
    local gridAreaBottom = DESIGN_H - 8 - detailH
    local gridAreaH = gridAreaBottom - gridAreaTop

    -- 内容高度
    local totalRunes = #RuneSystem.RUNES
    local rows = math.ceil(totalRunes / cols)
    local contentH = rows * (cellH + gridGap) - gridGap

    -- 限制滚动
    local maxScroll = math.max(0, contentH - gridAreaH)
    if scrollY < 0 then scrollY = 0 end
    if scrollY > maxScroll then scrollY = maxScroll end

    -- 裁切区域
    nvgSave(vg)
    nvgScissor(vg, 0, gridAreaTop, DESIGN_W, gridAreaH)

    gridCells = {}
    for idx, rune in ipairs(RuneSystem.RUNES) do
        local col = (idx - 1) % cols
        local row = math.floor((idx - 1) / cols)
        local gx = gridMargin + col * (cellW + gridGap)
        local gy = gridAreaTop + row * (cellH + gridGap) - scrollY

        -- 可见性检查
        if gy + cellH >= gridAreaTop and gy <= gridAreaTop + gridAreaH then
            local owned = SaveData.ownedRunes[rune.id] == true
            local equipped = IsRuneEquipped(rune.id)
            local selected = (selectedRuneId == rune.id)

            -- 背景
            if selected then
                drawCard(vg, gx, gy, cellW, cellH, 8,
                         255, 60, 60, 50, 255, 100, 100, 240)
            elseif equipped then
                drawCard(vg, gx, gy, cellW, cellH, 8,
                         255, 50, 50, 30, 255, 80, 80, 140)
            elseif owned then
                drawCard(vg, gx, gy, cellW, cellH, 8,
                         255, 255, 255, 10, 200, 100, 100, 80)
            else
                drawCard(vg, gx, gy, cellW, cellH, 8,
                         40, 30, 30, 100, 80, 50, 50, 60)
            end

            -- 图标
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if owned then
                nvgFontSize(vg, cellW * 0.52)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            else
                nvgFontSize(vg, cellW * 0.45)
                nvgFillColor(vg, nvgRGBA(80, 60, 60, 120))
            end
            nvgText(vg, gx + cellW / 2, gy + cellH / 2, rune.icon)

            -- 装备角标
            if equipped then
                nvgFontSize(vg, 11)
                nvgFillColor(vg, nvgRGBA(255, 200, 80, 220))
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgText(vg, gx + cellW - 3, gy + 3, "✦")
            end

            -- 未拥有锁
            if not owned then
                nvgFontSize(vg, 14)
                nvgFillColor(vg, nvgRGBA(100, 60, 60, 150))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                nvgText(vg, gx + cellW / 2, gy + cellH - 2, "🔒")
            end

            gridCells[#gridCells + 1] = { x = gx, y = gy, w = cellW, h = cellH, runeId = rune.id }
        end
    end

    nvgRestore(vg)

    -- ── 底部详情面板（选中时显示） ──
    equipBtn = { x = 0, y = 0, w = 0, h = 0, visible = false }

    if selectedRuneId then
        local rune = RuneSystem.GetRune(selectedRuneId)
        if rune then
            local panelY = DESIGN_H - detailH
            local panelH = detailH

            -- 面板背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, 6, panelY, DESIGN_W - 12, panelH - 4, 14)
            nvgFillColor(vg, nvgRGBA(40, 20, 20, 245))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(200, 60, 60, 140))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            local px = 20
            local py = panelY + 16

            -- 图标 + 名称（一行）
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 34)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, px, py + 16, rune.icon)

            nvgFontSize(vg, 24)
            nvgFillColor(vg, nvgRGBA(255, 100, 100, 255))
            nvgText(vg, px + 46, py + 10, rune.name)

            -- Boss来源
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(200, 150, 150, 160))
            nvgText(vg, px + 46, py + 30, I18n.t("rune_source_fmt", rune.bossId or "?"))
            py = py + 52

            -- 描述（使用 nvgTextBox 自动换行）
            nvgFontSize(vg, 16)
            nvgFillColor(vg, nvgRGBA(230, 210, 210, 230))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgTextBox(vg, px, py, DESIGN_W - px * 2, rune.desc)
            py = py + 44

            local owned = SaveData.ownedRunes[rune.id] == true
            local equipped = IsRuneEquipped(rune.id)

            if not owned then
                nvgFontSize(vg, 15)
                nvgFillColor(vg, nvgRGBA(120, 80, 80, 180))
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgText(vg, px, py, I18n.t("rune_locked"))
            elseif equipped then
                -- 卸下按钮
                local btnW, btnH = 140, 40
                local btnX = cx - btnW / 2
                local btnY = py
                drawCard(vg, btnX, btnY, btnW, btnH, 10,
                         120, 40, 40, 200, 180, 60, 60, 220)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFontSize(vg, 18)
                nvgFillColor(vg, nvgRGBA(255, 180, 180, 255))
                nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, I18n.t("rune_unequip_btn"))
                equipBtn = { x = btnX, y = btnY, w = btnW, h = btnH, visible = true, action = "unequip" }
            else
                -- 装备按钮
                local canEquip = #SaveData.equippedRunes < RuneSystem.MAX_EQUIPPED
                local btnW, btnH = 140, 40
                local btnX = cx - btnW / 2
                local btnY = py
                if canEquip then
                    drawCard(vg, btnX, btnY, btnW, btnH, 10,
                             200, 50, 50, 220, 255, 80, 80, 255)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFontSize(vg, 18)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, I18n.t("rune_equip_btn"))
                else
                    drawCard(vg, btnX, btnY, btnW, btnH, 10,
                             60, 40, 40, 180, 100, 60, 60, 120)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFontSize(vg, 18)
                    nvgFillColor(vg, nvgRGBA(150, 100, 100, 150))
                    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, I18n.t("rune_slots_full"))
                end
                equipBtn = { x = btnX, y = btnY, w = btnW, h = btnH, visible = true, action = canEquip and "equip" or nil }
            end
        end
    end

    -- ── 反馈消息 ──
    if flashTimer > 0 then
        local alpha = math.min(1, flashTimer / 0.3) * 255
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 150, DESIGN_H * 0.4 - 20, 300, 40, 12)
        nvgFillColor(vg, nvgRGBA(40, 10, 10, math.floor(alpha * 0.85)))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(255, 200, 200, math.floor(alpha)))
        nvgText(vg, cx, DESIGN_H * 0.4, flashMsg)
    end

    -- 空收藏提示
    if ownedCount == 0 then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(150, 100, 100, 150))
        nvgText(vg, cx, DESIGN_H * 0.55, I18n.t("rune_no_runes"))
    end
end

--- 处理点击（设计坐标）
---@param dx number
---@param dy number
---@return string|nil "back" | nil
function RuneShop.HandleTouch(dx, dy)
    -- 返回按钮
    if hitTest(dx, dy, RuneShop.backBtn) then
        selectedRuneId = nil
        scrollY = 0
        scrollVel = 0
        return "back"
    end

    -- 操作按钮（装备/卸下）- 优先检查
    if equipBtn.visible and equipBtn.w > 0 and hitTest(dx, dy, equipBtn) then
        if equipBtn.action == "equip" and selectedRuneId then
            if SaveData.EquipRune(selectedRuneId) then
                ShowFlash("装备成功！")
            else
                ShowFlash("装备失败")
            end
        elseif equipBtn.action == "unequip" and selectedRuneId then
            local slot = GetEquippedSlot(selectedRuneId)
            if slot then
                SaveData.UnequipRune(slot)
                ShowFlash("已卸下符文")
            end
        end
        return nil
    end

    -- 装备槽：点击选中查看详情（不再直接卸下）
    for _, slot in ipairs(equipSlots) do
        if hitTest(dx, dy, slot) then
            if slot.runeId then
                if selectedRuneId == slot.runeId then
                    selectedRuneId = nil  -- 再次点击取消
                else
                    selectedRuneId = slot.runeId
                end
            end
            return nil
        end
    end

    -- 网格点击：选中/取消选中
    for _, cell in ipairs(gridCells) do
        if hitTest(dx, dy, cell) then
            if selectedRuneId == cell.runeId then
                selectedRuneId = nil
            else
                selectedRuneId = cell.runeId
            end
            return nil
        end
    end

    -- 点击空白区域取消选中
    selectedRuneId = nil
    return nil
end

--- 处理触摸拖动开始
function RuneShop.HandleDragBegin(dy)
    dragStartY = dy
    dragLastY = dy
    dragScrollStart = scrollY
    scrollVel = 0
end

--- 处理触摸拖动移动
function RuneShop.HandleDragMove(dy)
    if dragStartY then
        local delta = dragStartY - dy
        scrollY = dragScrollStart + delta
        if dragLastY then
            scrollVel = (dragLastY - dy) * 60
        end
        dragLastY = dy
    end
end

--- 处理触摸拖动结束
function RuneShop.HandleDragEnd()
    dragStartY = nil
    dragLastY = nil
end

return RuneShop
