--- ============================================================================
--- 战斗 HUD - 血条、经验条、过载条、波次、计时器、击杀数
--- 所有数值文本使用 zpix 像素字体 + 白边黑字风格
--- ============================================================================

local Config         = require("Config")
local Player         = require("battle.Player")
local Enemy          = require("battle.Enemy")
local Wave           = require("battle.Wave")
local SpecialTerrain = require("battle.SpecialTerrain")
local Skill = require("battle.Skill")
local DamageNumber = require("ui.DamageNumber")
local Loot = require("battle.Loot")
local SaveData = require("SaveData")
local TotemSystem = require("meta.TotemSystem")
local RuneSystem = require("meta.RuneSystem")
local Glow = require("fx.Glow")
local I18n = require("utils.I18n")
local PerfQuality = require("utils.PerfQuality")
local Minimap = require("ui.Minimap")
local DailyChallenge = require("meta.DailyChallenge")
local DamageStats = require("ui.DamageStats")
local RuneEffects = require("battle.RuneEffects")
local BattleScene = require("battle.BattleScene")

local HUD = {}

-- zpix 字体 ID（由 main.lua 初始化后设置）
HUD.zpixFontId = -1

-- 摇杆位置设置（"left" / "center" / "right"，默认居中）
HUD.joystickPos = "center"

-- 八向移动模式（默认关闭 = 自由方向）
HUD.eightDirMode = false

-- 摇杆位置选项按钮区域（渲染时写入，供点击检测）
HUD.joyPosBtns = {}  -- { {x, y, w, h, key}, ... }

-- 暂停按钮（位置在渲染时计算，供点击检测用）
HUD.pauseBtnX = 0
HUD.pauseBtnY = 0
HUD.pauseBtnSize = 36
HUD.paused = false

-- 复活按钮（游戏结束画面）
HUD.reviveBtnX = 0
HUD.reviveBtnY = 0
HUD.reviveBtnW = 0
HUD.reviveBtnH = 0
HUD.showReviveBtn = false  -- 当前是否显示复活按钮

-- 再来一局按钮（游戏结束画面）
HUD.restartBtnX = 0
HUD.restartBtnY = 0
HUD.restartBtnW = 0
HUD.restartBtnH = 0

-- 保存退出按钮（暂停界面）
HUD.saveExitBtnX = 0
HUD.saveExitBtnY = 0
HUD.saveExitBtnW = 220
HUD.saveExitBtnH = 48
HUD.onSaveExit = nil  -- function() 回调，由 main.lua 设置

-- 遗言输入（由 main.lua 每帧设置）
HUD.tombLastWords = ""
HUD.tombEditMode = false
HUD.tombInputBox = nil  -- { x, y, w, h } 供点击检测

-- 技能/图腾/符文图标点击区域（渲染时写入）
HUD.skillSlots = {}  -- { {x, y, w, h, kind, icon, name, desc, borderColor}, ... }

-- 详情弹窗状态
HUD.detailPopup = nil  -- nil 或 { icon, name, desc, timer }
HUD.detailPopupDuration = 2.5  -- 自动消失时间（秒）

--- 白边文字绘制（使用 zpix 字体）
--- 如果 zpix 未加载则回退到 fallback 字体
---@param vg userdata
---@param x number
---@param y number
---@param text string
---@param fontSize number
---@param fillR number
---@param fillG number
---@param fillB number
---@param fillA number|nil
---@param fallbackFont number|nil
local function DrawOutlined(vg, x, y, text, fontSize, fillR, fillG, fillB, fillA, fallbackFont)
    fillA = fillA or 255
    if HUD.zpixFontId >= 0 then
        DamageNumber.DrawOutlinedText(vg, x, y, text, fontSize, fillR, fillG, fillB, fillA, 1.5)
    else
        -- 回退：普通渲染
        if fallbackFont then nvgFontFaceId(vg, fallbackFont) end
        nvgFontSize(vg, fontSize)
        nvgFillColor(vg, nvgRGBA(fillR, fillG, fillB, fillA))
        nvgText(vg, x, y, text)
    end
end

--- 渲染战斗HUD
---@param vg userdata NanoVG 上下文
---@param viewW number 设计宽度
---@param viewH number 设计高度
---@param font number 字体ID（回退用）
function HUD.Render(vg, viewW, viewH, font)
    local padX = 16
    local topY = 20

    -- 设置对齐（DrawOutlined 内部会用 zpix 字体）
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    -- ========================
    -- 顶部信息区（zpix 白边黑字）
    -- ========================

    -- 计时器（居中顶部）— 白边黑字
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    DrawOutlined(vg, viewW / 2, topY, Wave.GetTimeString(), 28, 30, 30, 30, 255, font)

    -- 波次号（计时器下方）— 白边紫字
    DrawOutlined(vg, viewW / 2, topY + 32, "WAVE " .. Wave.waveNum, 20, 180, 50, 255, 230, font)

    -- 击杀数（右上角）— 白边红字
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    DrawOutlined(vg, viewW - padX, topY, "KILL " .. Player.kills, 24, 255, 50, 50, 230, font)

    -- 暂停按钮（等级左侧，顶部行）
    local pauseSize = HUD.pauseBtnSize
    local pauseBtnX = padX
    local pauseBtnY = topY - 2
    HUD.pauseBtnX = pauseBtnX
    HUD.pauseBtnY = pauseBtnY

    nvgBeginPath(vg)
    nvgRoundedRect(vg, pauseBtnX, pauseBtnY, pauseSize, pauseSize, 6)
    nvgFillColor(vg, nvgRGBA(30, 20, 50, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 200, 200, 120))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontFaceId(vg, font)
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
    if HUD.paused then
        nvgText(vg, pauseBtnX + pauseSize / 2, pauseBtnY + pauseSize / 2, "▶")
    else
        nvgText(vg, pauseBtnX + pauseSize / 2, pauseBtnY + pauseSize / 2, "⏸")
    end

    -- 等级（暂停按钮右侧）— 白边青字
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    DrawOutlined(vg, padX + pauseSize + 6, topY, "Lv." .. Player.level, 24, 0, 200, 255, 230, font)

    -- ========================
    -- 血条（顶部下方，加厚）
    -- ========================
    local barY = topY + 58
    local barW = viewW - padX * 2
    local barH = 22

    -- HP 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, barY, barW, barH, 4)
    nvgFillColor(vg, nvgRGBA(40, 20, 20, 200))
    nvgFill(vg)

    -- HP 填充
    local hpRatio = Player.hp / Player.maxHp
    local hpC = Config.COLORS.hpBar
    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, barY, barW * hpRatio, barH, 4)
    nvgFillColor(vg, nvgRGBA(hpC[1], hpC[2], hpC[3], 255))
    nvgFill(vg)

    -- HP 发光边缘
    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, barY, barW * hpRatio, barH, 4)
    nvgStrokeColor(vg, nvgRGBA(hpC[1], hpC[2], hpC[3], 80))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- HP 文字（白边黑字，加大）
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    DrawOutlined(vg, viewW / 2, barY + barH / 2,
        math.floor(Player.hp) .. "/" .. Player.maxHp, 16, 30, 30, 30, 255, font)

    -- ========================
    -- 经验条（血条下方，较细）
    -- ========================
    local expBarY = barY + barH + 5
    local expBarH = 12

    -- EXP 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, expBarY, barW, expBarH, 3)
    nvgFillColor(vg, nvgRGBA(20, 20, 40, 200))
    nvgFill(vg)

    -- EXP 填充
    local expRatio = Player.exp / math.max(1, Player.expToNext)
    local expC = Config.COLORS.expBar
    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, expBarY, barW * expRatio, expBarH, 3)
    nvgFillColor(vg, nvgRGBA(expC[1], expC[2], expC[3], 255))
    nvgFill(vg)

    -- ========================
    -- 过载条（经验条下方）
    -- ========================
    local overBarY = expBarY + expBarH + 5
    local overBarH = 10

    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, overBarY, barW, overBarH, 2)
    nvgFillColor(vg, nvgRGBA(20, 15, 10, 200))
    nvgFill(vg)

    local overC = Config.COLORS.overloadBar
    if Player.overloadActive then
        -- 过载激活时脉冲闪烁
        local pulse = 0.6 + 0.4 * math.sin(Wave.totalTime * 10)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, padX, overBarY, barW, overBarH, 2)
        nvgFillColor(vg, nvgRGBA(overC[1], overC[2], overC[3],
            math.floor(255 * pulse)))
        nvgFill(vg)

        -- OVERLOAD! 文字（白边橙字）
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        DrawOutlined(vg, viewW / 2, overBarY - 2, "OVERLOAD!", 18,
            overC[1], overC[2], overC[3], math.floor(255 * pulse), font)
    else
        -- 过载累积进度
        local overRatio = Player.overloadKills / Config.OVERLOAD.killsToFull
        nvgBeginPath(vg)
        nvgRoundedRect(vg, padX, overBarY, barW * overRatio, overBarH, 2)
        nvgFillColor(vg, nvgRGBA(overC[1], overC[2], overC[3], 180))
        nvgFill(vg)
    end

    -- ========================
    -- 毕业徽章 + 狂暴进度条
    -- ========================
    if Player.graduationPhase >= 1 then
        local gradBadgeY = overBarY + overBarH + 4

        -- 毕业徽章
        local badgeText = Player.graduationPhase >= 2 and "GRAD II" or "GRAD I"
        local badgeColor = (Player.graduationPhase >= 2) and { 255, 200, 50 } or { 180, 50, 255 }

        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        DrawOutlined(vg, padX, gradBadgeY, badgeText, 16,
            badgeColor[1], badgeColor[2], badgeColor[3], 230, font)

        -- 狂暴进度条（如果狂暴激活）
        if Player.rageActive then
            local rageBarY = gradBadgeY + 20
            local rageBarW = barW * 0.5
            local rageBarH = 8
            local rageBarX = padX

            -- 背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, rageBarX, rageBarY, rageBarW, rageBarH, 2)
            nvgFillColor(vg, nvgRGBA(40, 10, 10, 200))
            nvgFill(vg)

            -- 填充（红色脉冲）
            local rageRatio = Player.rageTimer / Config.GRADUATION.ULTIMATE_RAGE_TIME
            local ragePulse = 0.7 + 0.3 * math.sin(Wave.totalTime * 8)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, rageBarX, rageBarY, rageBarW * rageRatio, rageBarH, 2)
            nvgFillColor(vg, nvgRGBA(255, 30, 30, math.floor(255 * ragePulse)))
            nvgFill(vg)

            -- RAGE! 文字
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local rageAlpha = math.floor(200 + 55 * ragePulse)
            DrawOutlined(vg, rageBarX + rageBarW + 8, rageBarY - 2,
                "RAGE " .. string.format("%.1f", Player.rageTimer) .. "s",
                14, 255, 50, 30, rageAlpha, font)
        end
    end

    -- ========================
    -- 技能冷却指示器（过载条下方）
    -- ========================
    local cooldowns = Skill.GetCooldowns(Player.skills)
    if #cooldowns > 0 then
        local cdY = overBarY + overBarH + 10
        local cdSize = 28       -- 圆形直径
        local cdR = cdSize / 2
        local cdGap = 8
        local cdStartX = viewW - padX

        for i, cd in ipairs(cooldowns) do
            local cx = cdStartX - (i - 1) * (cdSize + cdGap) - cdR
            local cy = cdY + cdR

            -- 背景圆
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, cdR)
            nvgFillColor(vg, nvgRGBA(20, 15, 40, 200))
            nvgFill(vg)

            -- CD 扇形（从顶部顺时针扫过，显示已冷却比例）
            if cd.ratio < 1.0 then
                -- 灰色遮罩表示剩余 CD
                local startAngle = -math.pi / 2
                local sweepAngle = (1.0 - cd.ratio) * math.pi * 2
                nvgBeginPath(vg)
                nvgMoveTo(vg, cx, cy)
                nvgArc(vg, cx, cy, cdR, startAngle, startAngle + sweepAngle, NVG_CW)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
                nvgFill(vg)
            else
                -- CD 就绪闪光
                local pulse = 0.5 + 0.5 * math.sin(Wave.totalTime * 8)
                nvgBeginPath(vg)
                nvgCircle(vg, cx, cy, cdR)
                nvgStrokeColor(vg, nvgRGBA(0, 255, 200, math.floor(100 * pulse)))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)
            end

            -- 边框
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, cdR)
            nvgStrokeColor(vg, nvgRGBA(0, 200, 255, 120))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 技能 emoji（CD 圆内）
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontFaceId(vg, font)
            nvgFontSize(vg, 18)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, cx, cy - 1, cd.icon)

            -- 剩余时间（圆下方）
            if cd.ratio < 1.0 then
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                local timeStr = string.format("%.1f", cd.remaining)
                DrawOutlined(vg, cx, cy + cdR + 2, timeStr, 12, 200, 200, 200, 200, font)
            end
        end
    end

    -- ========================
    -- 已有技能 + 图腾 + 符文图标（多行自动换行，可点击）
    -- ========================
    do
        local iconSize = 36
        local iconGap = 6
        local maxRowW = viewW - padX * 2
        local baseY = viewH - 170

        -- ── 共鸣指示器（符文图标上方）──
        local resonance = RuneEffects.GetActiveResonance()
        if resonance then
            local resoY = baseY - 22
            local pulse = 0.6 + 0.4 * math.sin((Wave.totalTime or 0) * 2.5)
            local ra = math.floor(200 * pulse)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontFaceId(vg, font)
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(220, 180, 255, ra))
            nvgText(vg, viewW / 2, resoY, resonance.icon .. " " .. resonance.name)
        end

        -- 收集所有条目：符文 → 图腾 → 技能
        local items = {}  -- { icon, name, desc, borderColor, badge }

        -- ① 符文（紫色边框）
        for _, runeId in ipairs(SaveData.equippedRunes) do
            local rune = RuneSystem.GetRune(runeId)
            if rune then
                items[#items + 1] = {
                    icon = rune.icon, name = rune.name, desc = rune.desc,
                    borderColor = { 180, 80, 255, 180 }, badge = nil, kind = "rune",
                }
            end
        end

        -- ② 图腾（稀有度边框色）
        for _, t in ipairs(SaveData.equippedTotems) do
            local rc = TotemSystem.GetRarityConfig(t.rarity)
            local tIcon = TotemSystem.GetTotemIcon(t.typeId)
            local tName = TotemSystem.GetTotemName(t.typeId, t.rarity)
            local tDesc = TotemSystem.GetTotemDesc(t.typeId, t.rarity)
            local col = rc.color
            items[#items + 1] = {
                icon = tIcon, name = tName, desc = tDesc,
                borderColor = { col[1], col[2], col[3], 180 }, badge = nil, kind = "totem",
            }
        end

        -- ③ 技能（蓝色边框 + 等级角标）
        for sid, slv in pairs(Player.skills) do
            local sIcon = "?"
            local sName = sid
            local sDesc = ""
            for _, def in ipairs(Config.SKILLS) do
                if def.id == sid then
                    sIcon = def.icon
                    sName = def.name
                    sDesc = def.desc or ""
                    break
                end
            end
            items[#items + 1] = {
                icon = sIcon, name = sName .. " Lv." .. slv, desc = sDesc,
                borderColor = { 0, 200, 255, 100 }, badge = tostring(slv), kind = "skill",
            }
        end

        -- 多行布局（从底部向上堆叠）
        HUD.skillSlots = {}
        if #items > 0 then
            local cols = math.floor((maxRowW + iconGap) / (iconSize + iconGap))
            local rows = math.ceil(#items / cols)
            -- 每行实际图标数居中
            for row = 1, rows do
                local rowStart = (row - 1) * cols + 1
                local rowEnd = math.min(row * cols, #items)
                local rowCount = rowEnd - rowStart + 1
                local rowW = rowCount * (iconSize + iconGap) - iconGap
                local sx = (viewW - rowW) / 2
                -- 行 Y：最后一行在 baseY，向上堆叠
                local ry = baseY - (rows - row) * (iconSize + iconGap)

                for c = 1, rowCount do
                    local idx = rowStart + c - 1
                    local it = items[idx]
                    local ix = sx + (c - 1) * (iconSize + iconGap)

                    -- 背景
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, ix, ry, iconSize, iconSize, 6)
                    nvgFillColor(vg, nvgRGBA(30, 20, 60, 200))
                    nvgFill(vg)

                    -- 边框（按类型着色）
                    local bc = it.borderColor
                    nvgStrokeColor(vg, nvgRGBA(bc[1], bc[2], bc[3], bc[4]))
                    nvgStrokeWidth(vg, it.kind == "skill" and 1 or 1.5)
                    nvgStroke(vg)

                    -- emoji 图标
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFontFaceId(vg, font)
                    nvgFontSize(vg, 20)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, ix + iconSize / 2, ry + iconSize / 2, it.icon)

                    -- 等级角标（仅技能）
                    if it.badge then
                        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                        DrawOutlined(vg, ix + iconSize - 2, ry + iconSize - 2, it.badge, 12, 30, 30, 30, 230, font)
                    end

                    -- 类型小标记：符文=紫点、图腾=三角
                    if it.kind == "rune" then
                        nvgBeginPath(vg)
                        nvgCircle(vg, ix + 5, ry + 5, 3)
                        nvgFillColor(vg, nvgRGBA(180, 80, 255, 220))
                        nvgFill(vg)
                    elseif it.kind == "totem" then
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, ix + 5, ry + 2)
                        nvgLineTo(vg, ix + 9, ry + 9)
                        nvgLineTo(vg, ix + 1, ry + 9)
                        nvgClosePath(vg)
                        nvgFillColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 220))
                        nvgFill(vg)
                    end

                    -- 存储点击区域
                    HUD.skillSlots[#HUD.skillSlots + 1] = {
                        x = ix, y = ry, w = iconSize, h = iconSize,
                        icon = it.icon, name = it.name, desc = it.desc,
                    }
                end
            end
        end
    end

    -- ========================
    -- 临时加成指示器（右下角，zpix 像素字体）
    -- ========================
    do
        local buffs = {}
        -- 磁铁增益
        if Loot.magnetBoostTimer > 0 then
            table.insert(buffs, { icon = "🧲", time = Loot.magnetBoostTimer, color = { 100, 200, 255 } })
        end
        -- 过载
        if Player.overloadActive then
            table.insert(buffs, { icon = "⚡", time = -1, color = { 255, 160, 30 } })  -- -1 表示无限制
        end
        -- 狂暴
        if Player.rageActive then
            table.insert(buffs, { icon = "🔥", time = Player.rageTimer, color = { 255, 50, 30 } })
        end

        if #buffs > 0 then
            local buffSize = 40
            local buffGap = 6
            local buffX = viewW - padX - buffSize
            local buffBaseY = viewH - 200

            for i, buff in ipairs(buffs) do
                local by = buffBaseY + (i - 1) * (buffSize + buffGap)

                -- 背景圆角矩形
                nvgBeginPath(vg)
                nvgRoundedRect(vg, buffX, by, buffSize, buffSize, 8)
                nvgFillColor(vg, nvgRGBA(20, 15, 40, 200))
                nvgFill(vg)

                -- 脉冲边框
                local pulse = 0.5 + 0.5 * math.sin(Wave.totalTime * 5 + i)
                nvgStrokeColor(vg, nvgRGBA(buff.color[1], buff.color[2], buff.color[3],
                    math.floor(80 + 100 * pulse)))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)

                -- emoji 图标
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFontFaceId(vg, font)
                nvgFontSize(vg, 22)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, buffX + buffSize / 2, by + buffSize / 2, buff.icon)

                -- 持续时间文字（zpix 字体，图标下方）
                if buff.time > 0 then
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                    DrawOutlined(vg, buffX + buffSize / 2, by + buffSize + 2,
                        string.format("%.1f", buff.time), 12,
                        buff.color[1], buff.color[2], buff.color[3], 230, font)
                end
            end
        end
    end

    -- ========================
    -- Boss 血条 UI（屏幕上方大血条）
    -- ========================
    local boss = Enemy.currentBoss
    local bossDef = Enemy.currentBossDef
    if boss and boss.alive and bossDef then
        local bossBarY = topY + 58 + 22 + 5 + 12 + 5 + 10 + 18  -- 在过载条下方
        local bossBarW = viewW - padX * 2
        local bossBarH = 20
        local bossCol = bossDef.color or { 255, 100, 100 }

        -- Boss 名称（zpix白边黑字，叠加在血条上方靠左）
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, padX, bossBarY - 2, bossDef.emoji)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
        DrawOutlined(vg, padX + 24, bossBarY - 2, bossDef.name, 18, 30, 30, 30, 255, font)

        -- 血条背景（半透明）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, padX, bossBarY, bossBarW, bossBarH, 4)
        nvgFillColor(vg, nvgRGBA(40, 10, 10, 140))
        nvgFill(vg)

        -- 血条填充（Boss 颜色，半透明）
        local bossHpRatio = math.max(0, boss.hp / boss.maxHp)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, padX, bossBarY, bossBarW * bossHpRatio, bossBarH, 4)
        nvgFillColor(vg, nvgRGBA(bossCol[1], bossCol[2], bossCol[3], 160))
        nvgFill(vg)

        -- 血条发光边缘
        local pulse = 0.6 + 0.4 * math.sin(Wave.totalTime * 6)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, padX, bossBarY, bossBarW * bossHpRatio, bossBarH, 4)
        nvgStrokeColor(vg, nvgRGBA(bossCol[1], bossCol[2], bossCol[3], math.floor(120 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- HP 数值（zpix白边黑字，叠加在血条内）
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DrawOutlined(vg, viewW / 2, bossBarY + bossBarH / 2,
            math.floor(boss.hp) .. "/" .. boss.maxHp, 14, 30, 30, 30, 255, font)

        -- 技能 CD 指示器（血条下方，增大尺寸）
        if boss.bossSkillTimers and bossDef.skills then
            local skY = bossBarY + bossBarH + 6
            local skSize = 36
            local skGap = 8
            local skCount = #bossDef.skills
            local skTotalW = skCount * (skSize + skGap) - skGap
            local skStartX = (viewW - skTotalW) / 2

            for i, skillDef in ipairs(bossDef.skills) do
                local sx = skStartX + (i - 1) * (skSize + skGap)
                local sy = skY
                local cdTimer = boss.bossSkillTimers[i] or 0
                local cdTotal = skillDef.cd or 5
                local cdRatio = math.max(0, math.min(1, 1.0 - cdTimer / cdTotal))

                -- 技能背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx, sy, skSize, skSize, 6)
                if skillDef.isUltimate then
                    nvgFillColor(vg, nvgRGBA(60, 10, 60, 220))
                else
                    nvgFillColor(vg, nvgRGBA(20, 15, 40, 220))
                end
                nvgFill(vg)

                -- CD 遮罩（从底部向上收缩）
                if cdRatio < 1.0 then
                    local maskH = skSize * (1.0 - cdRatio)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx, sy, skSize, maskH, 6)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                    nvgFill(vg)
                end

                -- 眩晕状态标记
                if boss.bossStunTimer and boss.bossStunTimer > 0 and skillDef.isUltimate then
                    local stunPulse = 0.5 + 0.5 * math.sin(Wave.totalTime * 12)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx, sy, skSize, skSize, 6)
                    nvgStrokeColor(vg, nvgRGBA(255, 255, 0, math.floor(200 * stunPulse)))
                    nvgStrokeWidth(vg, 2.5)
                    nvgStroke(vg)
                else
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx, sy, skSize, skSize, 6)
                    nvgStrokeColor(vg, nvgRGBA(bossCol[1], bossCol[2], bossCol[3], 100))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)
                end

                -- 技能序号（增大字号）
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                DrawOutlined(vg, sx + skSize / 2, sy + skSize / 2,
                    tostring(i), 18, 255, 255, 255, cdRatio >= 1.0 and 255 or 120, font)
            end

            -- 状态文字提示（眩晕 > 冻结 > 冰冻层数）
            local statusText, statusColor, statusPulseSpeed
            if boss.bossStunTimer and boss.bossStunTimer > 0 then
                statusText = "💫 STUNNED " .. string.format("%.1f", boss.bossStunTimer) .. "s"
                statusColor = { 255, 255, 0 }
                statusPulseSpeed = 10
            elseif boss.freezeTimer and boss.freezeTimer > 0 then
                statusText = "❄️ FROZEN " .. string.format("%.1f", boss.freezeTimer) .. "s"
                statusColor = { 100, 200, 255 }
                statusPulseSpeed = 8
            elseif boss.freezeStacks and boss.freezeStacks > 0 then
                local threshold = 5 + 3 * (boss.freezeCount or 0)
                statusText = "🧊 ICE " .. boss.freezeStacks .. "/" .. threshold
                statusColor = { 150, 220, 255 }
                statusPulseSpeed = 4
            end
            if statusText then
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                local sp = 0.5 + 0.5 * math.sin(Wave.totalTime * statusPulseSpeed)
                DrawOutlined(vg, viewW / 2, skY + skSize + 4, statusText,
                    18, statusColor[1], statusColor[2], statusColor[3],
                    math.floor(200 + 55 * sp), font)
            end
        end
    end

    -- ========================
    -- 局内金币数量（左下角）
    -- ========================
    do
        local gold = BattleScene.sessionGold or 0
        local coinY = viewH - 28
        local coinX = padX

        -- 背景胶囊
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 16)
        local goldStr = tostring(gold)
        local tw = nvgTextBounds(vg, 0, 0, goldStr)
        local pillW = 22 + tw + 12  -- emoji宽 + 间距 + 文字 + 右padding
        local pillH = 26
        local pillY = coinY - pillH / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, coinX, pillY, pillW, pillH, pillH / 2)
        nvgFillColor(vg, nvgRGBA(20, 15, 40, 180))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 100))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 金币 emoji
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, coinX + 4, coinY, "🪙")

        -- 数量文字（zpix 白边黑字）
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        DrawOutlined(vg, coinX + 24, coinY, goldStr, 16, 255, 220, 50, 255, font)
    end

    -- ========================
    -- 特别地形 Buff 图标条（小地图左侧）
    -- ========================
    local stBuffs = SpecialTerrain.GetActiveBuffInfo()
    if #stBuffs > 0 then
        local iconSize = 22
        local iconPad  = 4
        local rowW     = #stBuffs * (iconSize + iconPad) - iconPad
        -- 右下角，小地图正上方（距离底部 108px）
        local bStartX  = viewW - rowW - 12
        local bStartY  = viewH - 108
        for i, b in ipairs(stBuffs) do
            local bx = bStartX + (i - 1) * (iconSize + iconPad)
            local by = bStartY
            -- 圆角背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, iconSize, iconSize, 4)
            nvgFillColor(vg, nvgRGBA(20, 20, 40, 180))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 220, 60, 160))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- Buff emoji
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, bx + iconSize * 0.5, by + iconSize * 0.5 - 2, b.icon)
            -- 剩余时间（秒，底部小字）
            local timerStr = string.format("%.0f", b.timer)
            DrawOutlined(vg, bx + iconSize * 0.5, by + iconSize - 1,
                timerStr, 9, 255, 220, 60, 220, font)
        end
    end

    -- ========================
    -- 像素网格小地图（右下角）
    -- ========================
    Minimap.Render(vg, viewW, viewH)
end

--- 检测暂停按钮点击
---@param dx number 设计坐标 X
---@param dy number 设计坐标 Y
---@return boolean 是否点击了暂停按钮
function HUD.HitPauseButton(dx, dy)
    local bx = HUD.pauseBtnX
    local by = HUD.pauseBtnY
    local bs = HUD.pauseBtnSize
    return dx >= bx and dx <= bx + bs and dy >= by and dy <= by + bs
end

-- 暂停继续按钮尺寸
HUD.continueBtnW = 220
HUD.continueBtnH = 56
HUD.continueBtnX = 0
HUD.continueBtnY = 0

--- 渲染暂停遮罩
---@param vg userdata
---@param viewW number
---@param viewH number
---@param font number
function HUD.RenderPauseOverlay(vg, viewW, viewH, font)
    -- 半透明遮罩（加深，让界面更聚焦）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 185))
    nvgFill(vg)

    -- 中央面板卡片背景
    local panelW = viewW - 40
    local panelX = 20
    local panelY = viewH / 2 - 180
    local panelH = 130
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 18)
    nvgFillColor(vg, nvgRGBA(10, 20, 40, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 60))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- PAUSED 标题（加大 + 颜色更鲜明）
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local textFont = HUD.zpixFontId >= 0 and HUD.zpixFontId or font
    nvgFontFaceId(vg, textFont)
    nvgFontSize(vg, 46)
    -- 阴影
    nvgFillColor(vg, nvgRGBA(60, 120, 220, 100))
    nvgText(vg, viewW / 2 + 2, panelY + 42 + 2, I18n.t("pause_title"))
    -- 正文
    nvgFillColor(vg, nvgRGBA(220, 240, 255, 245))
    nvgText(vg, viewW / 2, panelY + 42, I18n.t("pause_title"))

    -- "继续游戏" 按钮（加宽加高）
    local btnW = viewW - 40
    local btnH = 62
    local btnX = 20
    local btnY = panelY + panelH + 14
    HUD.continueBtnW = btnW
    HUD.continueBtnH = btnH
    HUD.continueBtnX = btnX
    HUD.continueBtnY = btnY

    local pulse = 0.75 + 0.25 * math.sin(time.elapsedTime * 3)

    -- 按钮渐变背景
    local btnPaint = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + btnH,
        nvgRGBA(40, 200, 110, math.floor(180 * pulse)),
        nvgRGBA(20, 140, 80, math.floor(120 * pulse)))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 14)
    nvgFillPaint(vg, btnPaint)
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 240, 150, math.floor(240 * pulse)))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 按钮文字（加大）
    nvgFontFaceId(vg, textFont)
    nvgFontSize(vg, 28)
    -- 阴影
    nvgFillColor(vg, nvgRGBA(0, 60, 30, 120))
    nvgText(vg, viewW / 2 + 1, btnY + btnH / 2 + 1, "▶ " .. I18n.t("pause_resume"))
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(245 * pulse)))
    nvgText(vg, viewW / 2, btnY + btnH / 2, "▶ " .. I18n.t("pause_resume"))

    -- ── 摇杆位置设置 ──
    local optY = btnY + btnH + 32
    nvgFontFaceId(vg, textFont)
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
    nvgText(vg, viewW / 2, optY, I18n.t("pause_joystick"))

    local options = { { key = "left", label = I18n.t("pause_joy_left") }, { key = "center", label = I18n.t("pause_joy_center") }, { key = "right", label = I18n.t("pause_joy_right") }, { key = "hide", label = I18n.t("pause_joy_hide") } }
    local optBtnW = 72
    local optBtnH = 36
    local optGap = 12
    local totalW = #options * optBtnW + (#options - 1) * optGap
    local startX = (viewW - totalW) / 2
    local optBtnY = optY + 18

    HUD.joyPosBtns = {}
    for i, opt in ipairs(options) do
        local ox = startX + (i - 1) * (optBtnW + optGap)
        local selected = (HUD.joystickPos == opt.key)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, ox, optBtnY, optBtnW, optBtnH, 8)
        if selected then
            nvgFillColor(vg, nvgRGBA(50, 200, 120, 140))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(50, 220, 130, 240))
        else
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 20))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 100))
        end
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFaceId(vg, textFont)
        nvgFontSize(vg, 17)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, selected and 255 or 160))
        nvgText(vg, ox + optBtnW / 2, optBtnY + optBtnH / 2, opt.label)

        HUD.joyPosBtns[i] = { x = ox, y = optBtnY, w = optBtnW, h = optBtnH, key = opt.key }
    end

    -- ── 八向移动开关 ──
    local edY = optBtnY + optBtnH + 24
    nvgFontFaceId(vg, textFont)
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
    nvgText(vg, viewW / 2, edY, I18n.t("pause_move_mode"))

    local edBtnW = 108
    local edBtnH = 36
    local edGap = 12
    local edTotalW = 2 * edBtnW + edGap
    local edStartX = (viewW - edTotalW) / 2
    local edBtnY = edY + 18

    local edOptions = { { key = false, label = I18n.t("pause_free_dir") }, { key = true, label = I18n.t("pause_eight_dir") } }
    HUD.eightDirBtns = {}
    for i, opt in ipairs(edOptions) do
        local ex = edStartX + (i - 1) * (edBtnW + edGap)
        local sel = (HUD.eightDirMode == opt.key)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, ex, edBtnY, edBtnW, edBtnH, 8)
        if sel then
            nvgFillColor(vg, nvgRGBA(50, 200, 120, 140))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(50, 220, 130, 240))
        else
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 20))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 100))
        end
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFaceId(vg, textFont)
        nvgFontSize(vg, 17)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, sel and 255 or 160))
        nvgText(vg, ex + edBtnW / 2, edBtnY + edBtnH / 2, opt.label)

        HUD.eightDirBtns[i] = { x = ex, y = edBtnY, w = edBtnW, h = edBtnH, key = opt.key }
    end

    -- ── 辉光效果开关 ──
    local glowY = edBtnY + edBtnH + 24
    nvgFontFaceId(vg, textFont)
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
    nvgText(vg, viewW / 2, glowY, I18n.t("pause_glow"))

    local glBtnW = 108
    local glBtnH = 36
    local glGap = 12
    local glTotalW = 2 * glBtnW + glGap
    local glStartX = (viewW - glTotalW) / 2
    local glBtnY = glowY + 18

    local glOptions = { { key = false, label = I18n.t("pause_off") }, { key = true, label = I18n.t("pause_on") } }
    HUD.glowBtns = {}
    for i, opt in ipairs(glOptions) do
        local gx = glStartX + (i - 1) * (glBtnW + glGap)
        local sel = (Glow.enabled == opt.key)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, gx, glBtnY, glBtnW, glBtnH, 8)
        if sel then
            nvgFillColor(vg, nvgRGBA(50, 200, 120, 140))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(50, 220, 130, 240))
        else
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 20))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 100))
        end
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFaceId(vg, textFont)
        nvgFontSize(vg, 17)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, sel and 255 or 160))
        nvgText(vg, gx + glBtnW / 2, glBtnY + glBtnH / 2, opt.label)

        HUD.glowBtns[i] = { x = gx, y = glBtnY, w = glBtnW, h = glBtnH, key = opt.key }
    end

    -- ── 性能档位 ──
    local perfY = glBtnY + glBtnH + 24
    nvgFontFaceId(vg, textFont)
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
    nvgText(vg, viewW / 2, perfY, I18n.t("pause_perf_quality"))

    local perfLabels = PerfQuality.GetLabels(I18n.lang)
    local pfBtnW  = 66
    local pfBtnH  = 36
    local pfGap   = 8
    local pfTotalW = #perfLabels * pfBtnW + (#perfLabels - 1) * pfGap
    local pfStartX = (viewW - pfTotalW) / 2
    local pfBtnY  = perfY + 18

    -- 每档按钮颜色（省电→全量，绿→黄→橙→红）
    local perfColors = {
        { 60, 200, 100 },   -- 1 省电  绿
        { 100, 200, 60 },   -- 2 流畅  黄绿
        { 200, 180, 50 },   -- 3 均衡  黄
        { 220, 130, 40 },   -- 4 精致  橙
        { 220, 80,  60 },   -- 5 全量  红橙
    }

    HUD.perfBtns = {}
    for i, label in ipairs(perfLabels) do
        local px = pfStartX + (i - 1) * (pfBtnW + pfGap)
        local sel = (PerfQuality.level == i)
        local pc  = perfColors[i]

        nvgBeginPath(vg)
        nvgRoundedRect(vg, px, pfBtnY, pfBtnW, pfBtnH, 8)
        if sel then
            nvgFillColor(vg, nvgRGBA(pc[1], pc[2], pc[3], 160))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(pc[1], pc[2], pc[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 20))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(pc[1], pc[2], pc[3], 120))
        end
        nvgStrokeWidth(vg, sel and 2 or 1.5)
        nvgStroke(vg)

        nvgFontFaceId(vg, textFont)
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, sel and 255 or 160))
        nvgText(vg, px + pfBtnW / 2, pfBtnY + pfBtnH / 2, label)

        HUD.perfBtns[i] = { x = px, y = pfBtnY, w = pfBtnW, h = pfBtnH, level = i }
    end

    -- ── 语言切换 ──
    local langY = pfBtnY + pfBtnH + 24
    nvgFontFaceId(vg, textFont)
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
    nvgText(vg, viewW / 2, langY, I18n.t("pause_lang"))

    local lnBtnW = 72
    local lnBtnH = 36
    local lnGap = 12
    local lnTotalW = #I18n.LANGUAGES * lnBtnW + (#I18n.LANGUAGES - 1) * lnGap
    local lnStartX = (viewW - lnTotalW) / 2
    local lnBtnY = langY + 18

    HUD.langBtns = {}
    for i, lang in ipairs(I18n.LANGUAGES) do
        local lx = lnStartX + (i - 1) * (lnBtnW + lnGap)
        local sel = (I18n.lang == lang)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, lx, lnBtnY, lnBtnW, lnBtnH, 8)
        if sel then
            nvgFillColor(vg, nvgRGBA(50, 200, 120, 140))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(50, 220, 130, 240))
        else
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 20))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 100))
        end
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFaceId(vg, textFont)
        nvgFontSize(vg, 17)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, sel and 255 or 160))
        nvgText(vg, lx + lnBtnW / 2, lnBtnY + lnBtnH / 2, I18n.LANG_LABELS[lang])

        HUD.langBtns[i] = { x = lx, y = lnBtnY, w = lnBtnW, h = lnBtnH, key = lang }
    end

    -- ── 保存退出按钮 ──
    local seBtnW = HUD.saveExitBtnW
    local seBtnH = HUD.saveExitBtnH
    local seBtnX = (viewW - seBtnW) / 2
    local seBtnY = lnBtnY + lnBtnH + 36
    HUD.saveExitBtnX = seBtnX
    HUD.saveExitBtnY = seBtnY

    nvgBeginPath(vg)
    nvgRoundedRect(vg, seBtnX, seBtnY, seBtnW, seBtnH, 10)
    nvgFillColor(vg, nvgRGBA(200, 60, 60, 60))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 80, 80, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontFaceId(vg, textFont)
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 120, 120, 230))
    nvgText(vg, seBtnX + seBtnW / 2, seBtnY + seBtnH / 2, I18n.t("pause_save_exit"))
end

--- 检测继续按钮点击
---@param dx number 设计坐标X
---@param dy number 设计坐标Y
---@return boolean
function HUD.HitContinueButton(dx, dy)
    return dx >= HUD.continueBtnX and dx <= HUD.continueBtnX + HUD.continueBtnW and dy >= HUD.continueBtnY and dy <= HUD.continueBtnY + HUD.continueBtnH
end

--- 检测摇杆位置按钮点击
---@param dx number 设计坐标X
---@param dy number 设计坐标Y
---@return string|nil 点击的选项key ("left"/"center"/"right") 或 nil
function HUD.HitJoystickPosButton(dx, dy)
    for _, btn in ipairs(HUD.joyPosBtns) do
        if dx >= btn.x and dx <= btn.x + btn.w and dy >= btn.y and dy <= btn.y + btn.h then
            return btn.key
        end
    end
    return nil
end

--- 检测八向移动按钮点击
---@param dx number
---@param dy number
---@return boolean|nil 点击的选项key (true/false) 或 nil
function HUD.HitEightDirButton(dx, dy)
    if not HUD.eightDirBtns then return nil end
    for _, btn in ipairs(HUD.eightDirBtns) do
        if dx >= btn.x and dx <= btn.x + btn.w and dy >= btn.y and dy <= btn.y + btn.h then
            return btn.key
        end
    end
    return nil
end

--- 检测辉光开关按钮点击
---@param dx number
---@param dy number
---@return boolean|nil 点击的选项key (true/false) 或 nil
function HUD.HitGlowButton(dx, dy)
    if not HUD.glowBtns then return nil end
    for _, btn in ipairs(HUD.glowBtns) do
        if dx >= btn.x and dx <= btn.x + btn.w and dy >= btn.y and dy <= btn.y + btn.h then
            return btn.key
        end
    end
    return nil
end

--- 检测性能档位按钮点击
---@param dx number
---@param dy number
---@return number|nil 点击的档位 (1~5) 或 nil
function HUD.HitPerfButton(dx, dy)
    if not HUD.perfBtns then return nil end
    for _, btn in ipairs(HUD.perfBtns) do
        if dx >= btn.x and dx <= btn.x + btn.w and dy >= btn.y and dy <= btn.y + btn.h then
            return btn.level
        end
    end
    return nil
end

--- 检测语言按钮点击
---@param dx number
---@param dy number
---@return string|nil 点击的语言代码 ("zh"/"en") 或 nil
function HUD.HitLangButton(dx, dy)
    if not HUD.langBtns then return nil end
    for _, btn in ipairs(HUD.langBtns) do
        if dx >= btn.x and dx <= btn.x + btn.w and dy >= btn.y and dy <= btn.y + btn.h then
            return btn.key
        end
    end
    return nil
end

--- 保存用户设置到本地
function HUD.SaveSettings()
    local ok, cjson = pcall(require, "cjson")
    if not ok then return end
    local data = {
        joystickPos  = HUD.joystickPos,
        eightDirMode = HUD.eightDirMode,
        glowEnabled  = Glow.enabled,
        lang         = I18n.lang,
        perfLevel    = PerfQuality.level,
    }
    local file = File("settings.json", FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(data))
        file:Close()
    end
end

--- 从本地加载用户设置
function HUD.LoadSettings()
    if not fileSystem:FileExists("settings.json") then return end
    local ok, cjson = pcall(require, "cjson")
    if not ok then return end
    local file = File("settings.json", FILE_READ)
    if file:IsOpen() then
        local ok2, data = pcall(cjson.decode, file:ReadString())
        file:Close()
        if ok2 and data then
            if data.joystickPos == "left" or data.joystickPos == "center" or data.joystickPos == "right" or data.joystickPos == "hide" then
                HUD.joystickPos = data.joystickPos
            end
            if data.eightDirMode ~= nil then
                HUD.eightDirMode = data.eightDirMode
            end
            if data.glowEnabled ~= nil then
                Glow.enabled = data.glowEnabled
            end
            if data.lang == "zh" or data.lang == "en" then
                I18n.lang = data.lang
            end
            if type(data.perfLevel) == "number" then
                PerfQuality.SetLevel(data.perfLevel)
                -- 同步辉光开关（档位 5 才启用辉光；若已单独存储 glowEnabled 则以其为准）
                if data.glowEnabled == nil then
                    Glow.enabled = PerfQuality.GlowEnabled()
                end
            end
        end
    end
end

--- 检测保存退出按钮点击
---@param dx number 设计坐标X
---@param dy number 设计坐标Y
---@return boolean
function HUD.HitSaveExitButton(dx, dy)
    return dx >= HUD.saveExitBtnX and dx <= HUD.saveExitBtnX + HUD.saveExitBtnW and dy >= HUD.saveExitBtnY and dy <= HUD.saveExitBtnY + HUD.saveExitBtnH
end

--- 检测复活按钮点击
---@param dx number 设计坐标X
---@param dy number 设计坐标Y
---@return boolean 是否点击了复活按钮
function HUD.HitReviveButton(dx, dy)
    if HUD.reviveBtnW <= 0 then return false end
    return dx >= HUD.reviveBtnX and dx <= HUD.reviveBtnX + HUD.reviveBtnW and dy >= HUD.reviveBtnY and dy <= HUD.reviveBtnY + HUD.reviveBtnH
end

--- 检测再来一局按钮点击
---@param dx number 设计坐标X
---@param dy number 设计坐标Y
---@return boolean 是否点击了再来一局按钮
function HUD.HitRestartButton(dx, dy)
    if HUD.restartBtnW <= 0 then return false end
    return dx >= HUD.restartBtnX and dx <= HUD.restartBtnX + HUD.restartBtnW
       and dy >= HUD.restartBtnY and dy <= HUD.restartBtnY + HUD.restartBtnH
end

--- 渲染游戏结束/胜利画面
function HUD.RenderGameOver(vg, viewW, viewH, font, isVictory, stats)
    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    local centerX = viewW / 2
    local centerY = viewH / 2

    -- 从角色定义读取文案
    local charDef = Player.charDef or Config.GetCharacter("cat")
    local deadEmoji = charDef.playerEmoji and charDef.playerEmoji.dead or "😿"

    -- 字体：zpix 优先，emoji 回退主字体
    local textFont = HUD.zpixFontId >= 0 and HUD.zpixFontId or font

    -- 暗色面板（动态调整高度）
    local sessionTotems = SaveData.sessionTotems or {}
    local hasSessionTotems = #sessionTotems > 0
    local dcReward = DailyChallenge.lastReward
    local hasDcReward = dcReward and dcReward.waveGold > 0
    local hasDmgStats = DamageStats.GetSourceCount() > 0
    local panelW = viewW * 0.90
    local panelH = 360  -- 2x2 grid stats layout (compact)
    if hasDmgStats then panelH = panelH + 220 end
    if hasDcReward then panelH = panelH + 80 end
    -- 图腾自动换行：计算行数（最多显示2行，超出省略）
    local totemIconSize = 36
    local totemGap = 6
    local totemRows = 0
    local totemPerRow = 1
    local MAX_TOTEM_ROWS = 2
    local totemShowCount = 0
    if hasSessionTotems then
        local totemAreaW = panelW - 48
        totemPerRow = math.max(1, math.floor((totemAreaW + totemGap) / (totemIconSize + totemGap)))
        totemRows = math.ceil(#sessionTotems / totemPerRow)
        if totemRows > MAX_TOTEM_ROWS then
            totemRows = MAX_TOTEM_ROWS
            totemShowCount = totemPerRow * MAX_TOTEM_ROWS - 1  -- 留1格给 "+N"
        else
            totemShowCount = #sessionTotems
        end
        panelH = panelH + 30 + totemRows * (totemIconSize + totemGap)
    end
    -- 计算面板下方元素总高度，让整体内容居中而非仅面板居中
    local belowPanelH = 20 + 68  -- 底部间距 + 按钮行（复活与再来一次并排，只占一行）
    local panelX = centerX - panelW / 2
    local panelY = centerY - (panelH + belowPanelH) / 2
    local cornerR = 16

    -- 暗色面板背景（与游戏整体风格一致）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
    nvgFillColor(vg, nvgRGBA(12, 10, 28, 230))
    nvgFill(vg)
    -- 边框（紫蓝色调）
    nvgStrokeColor(vg, nvgRGBA(100, 120, 200, 160))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if isVictory then
        -- 胜利 emoji（emoji 必须用主字体）
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 80)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, centerX, panelY + 55, "🎉")

        -- zpix 标题
        nvgFontFaceId(vg, textFont)
        nvgFontSize(vg, 56)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, centerX, panelY + 115, charDef.victoryText or "大获全胜！")

        -- 副标题
        nvgFontSize(vg, 26)
        nvgFillColor(vg, nvgRGBA(180, 200, 220, 200))
        nvgText(vg, centerX, panelY + 152, charDef.victorySub or "")
    else
        -- 死亡 emoji（emoji 必须用主字体）
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 80)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, centerX, panelY + 55, deadEmoji)

        -- zpix 标题（红色系）
        nvgFontFaceId(vg, textFont)
        nvgFontSize(vg, 56)
        nvgFillColor(vg, nvgRGBA(255, 100, 100, 255))
        nvgText(vg, centerX, panelY + 115, charDef.deathText or "倒下了")

        -- 遗言输入框（替代副标题位置，在面板内）
        do
            local t = time.elapsedTime
            local inputW = panelW * 0.80
            local inputH = 36
            local inputX = centerX - inputW / 2
            local inputY = panelY + 155  -- 上移避免与死亡标题重叠(原134)

            HUD.tombInputBox = { x = inputX, y = inputY, w = inputW, h = inputH }

            -- 输入框背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, inputX, inputY, inputW, inputH, 8)
            nvgFillColor(vg, nvgRGBA(15, 10, 30, 200))
            nvgFill(vg)

            -- 边框（编辑模式高亮）
            if HUD.tombEditMode then
                local bp = 180 + math.floor(math.sin(t * 4) * 75)
                nvgStrokeColor(vg, nvgRGBA(100, 220, 255, bp))
                nvgStrokeWidth(vg, 2)
            else
                nvgStrokeColor(vg, nvgRGBA(120, 100, 180, 80))
                nvgStrokeWidth(vg, 1)
            end
            nvgStroke(vg)

            -- 文字内容（zpix）
            nvgFontFaceId(vg, textFont)
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local textX = inputX + 12
            local textY = inputY + inputH / 2

            if #HUD.tombLastWords > 0 then
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, textX, textY, HUD.tombLastWords)
                if HUD.tombEditMode then
                    local tw = nvgTextBounds(vg, 0, 0, HUD.tombLastWords)
                    local cursorX = textX + tw + 2
                    local ca = math.floor(128 + 127 * math.sin(t * 6))
                    nvgBeginPath(vg)
                    nvgRect(vg, cursorX, inputY + 6, 2, inputH - 12)
                    nvgFillColor(vg, nvgRGBA(100, 220, 255, ca))
                    nvgFill(vg)
                end
            else
                nvgFillColor(vg, nvgRGBA(120, 120, 150, 100))
                nvgText(vg, textX, textY, I18n.t("tomb_input_placeholder"))
                if HUD.tombEditMode then
                    local ca = math.floor(128 + 127 * math.sin(t * 6))
                    nvgBeginPath(vg)
                    nvgRect(vg, textX, inputY + 6, 2, inputH - 12)
                    nvgFillColor(vg, nvgRGBA(100, 220, 255, ca))
                    nvgFill(vg)
                end
            end
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
    end

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 24, panelY + 205)
    nvgLineTo(vg, panelX + panelW - 24, panelY + 205)
    nvgStrokeColor(vg, nvgRGBA(80, 90, 130, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 战斗数据（2×2 网格，带图标和高亮数字）
    local dataEndY = panelY + 218
    if stats then
        local gridTop = panelY + 218
        local cellW = (panelW - 32) / 2
        local cellH = 52
        local gapX = 12
        local gapY = 10
        local col1X = panelX + 16
        local col2X = panelX + 16 + cellW + gapX

        local cells = {
            { icon = "⏱", label = "存活时间", value = stats.timeStr,      icolor = {100, 200, 255} },
            { icon = "💀", label = "击杀数",   value = tostring(stats.kills), icolor = {255, 120, 120} },
            { icon = "⬆", label = "到达等级", value = tostring(stats.level),  icolor = {120, 255, 160} },
            { icon = "🌊", label = "到达波次", value = tostring(stats.wave),   icolor = {255, 200, 80} },
        }

        for idx, cell in ipairs(cells) do
            local col = (idx - 1) % 2
            local row = math.floor((idx - 1) / 2)
            local cx = (col == 0) and col1X or col2X
            local cy = gridTop + row * (cellH + gapY)

            -- 格子背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cy, cellW, cellH, 10)
            nvgFillColor(vg, nvgRGBA(20, 18, 45, 200))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(cell.icolor[1], cell.icolor[2], cell.icolor[3], 60))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 图标（主字体）
            nvgFontFaceId(vg, font)
            nvgFontSize(vg, 18)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(cell.icolor[1], cell.icolor[2], cell.icolor[3], 220))
            nvgText(vg, cx + 10, cy + 16, cell.icon)

            -- 标签（zpix，小字）
            nvgFontFaceId(vg, textFont)
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(150, 160, 185, 200))
            nvgText(vg, cx + 30, cy + 16, cell.label)

            -- 数值（大字，高亮色）
            nvgFontFaceId(vg, textFont)
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(cell.icolor[1], cell.icolor[2], cell.icolor[3], 255))
            nvgText(vg, cx + 10, cy + 38, cell.value)
        end

        dataEndY = gridTop + 2 * (cellH + gapY) - gapY + 12
    end

    -- 伤害统计饼图
    local dmgChartH = 0
    if hasDmgStats then
        local chartTopY = dataEndY + 4
        -- 分隔线
        nvgBeginPath(vg)
        nvgMoveTo(vg, panelX + 24, chartTopY)
        nvgLineTo(vg, panelX + panelW - 24, chartTopY)
        nvgStrokeColor(vg, nvgRGBA(80, 90, 130, 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 小标题（zpix）
        nvgFontFaceId(vg, textFont)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(160, 170, 200, 220))
        nvgText(vg, centerX, chartTopY + 18, "⚔️ 伤害统计")
        -- 饼图（圆心偏左，右侧留给图例）
        local chartCX = panelX + panelW * 0.28
        local chartCY = chartTopY + 120
        local chartR = 72
        DamageStats.RenderPieChart(vg, chartCX, chartCY, chartR, font, textFont)
        dmgChartH = 220
    end

    -- 每日挑战奖励展示
    local dcRewardEndY = dataEndY + 4 + dmgChartH
    if hasDcReward then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 标题（emoji 用主字体）
        local dcLabelY = dcRewardEndY
        nvgFontFaceId(vg, font)
        nvgFontSize(vg, 17)
        nvgFillColor(vg, nvgRGBA(255, 180, 40, 230))
        nvgText(vg, centerX, dcLabelY, "🏆 每日挑战奖励")

        -- 波次奖励金币（zpix）
        nvgFontFaceId(vg, textFont)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
        nvgText(vg, centerX, dcLabelY + 28, I18n.t("result_gold_reward", dcReward.waveGold))

        -- 达成阶梯标签（zpix）
        if dcReward.tiers and #dcReward.tiers > 0 then
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(150, 160, 190, 200))
            local tierNames = {}
            for _, t in ipairs(dcReward.tiers) do
                tierNames[#tierNames + 1] = t.label
            end
            nvgText(vg, centerX, dcLabelY + 52, I18n.t("result_dc_reached", table.concat(tierNames, " / ")))
        end

        -- 排名奖励（zpix）
        if dcReward.rankBonus then
            nvgFontSize(vg, 18)
            nvgFillColor(vg, nvgRGBA(255, 230, 100, 255))
            nvgText(vg, centerX, dcLabelY + 68, dcReward.rankBonus.label .. " " .. I18n.t("result_gold_reward", dcReward.rankBonus.gold))
        end

        dcRewardEndY = dcLabelY + 80
    end

    -- 本局获得图腾展示（自动换行）
    if hasSessionTotems then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontFaceId(vg, textFont)
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(170, 140, 220, 220))
        local totemLabelY = dcRewardEndY + 8
        nvgText(vg, centerX, totemLabelY, "本局获得图腾")

        local totemStartY = totemLabelY + 22
        local totemAreaW = panelW - 48
        local rowStartX = centerX - totemAreaW / 2
        local remaining = #sessionTotems - totemShowCount
        for idx = 1, totemShowCount do
            local totem = sessionTotems[idx]
            local col = (idx - 1) % totemPerRow
            local row = math.floor((idx - 1) / totemPerRow)
            local ix = rowStartX + col * (totemIconSize + totemGap) + totemIconSize / 2
            local iy = totemStartY + row * (totemIconSize + totemGap) + totemIconSize / 2
            -- 稀有度底色圆点
            local rc = TotemSystem.GetRarityConfig(totem.rarity)
            local c = rc.color
            nvgBeginPath(vg)
            nvgCircle(vg, ix, iy, totemIconSize / 2)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 50))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], 150))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
            -- 图腾图标（emoji 用主字体）
            nvgFontFaceId(vg, font)
            nvgFontSize(vg, 22)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
            nvgText(vg, ix, iy, TotemSystem.GetTotemIcon(totem.typeId))
        end
        -- 超出部分显示 "+N" 省略标记
        if remaining > 0 then
            local eIdx = totemShowCount + 1
            local col = (eIdx - 1) % totemPerRow
            local row = math.floor((eIdx - 1) / totemPerRow)
            local ix = rowStartX + col * (totemIconSize + totemGap) + totemIconSize / 2
            local iy = totemStartY + row * (totemIconSize + totemGap) + totemIconSize / 2
            nvgBeginPath(vg)
            nvgCircle(vg, ix, iy, totemIconSize / 2)
            nvgFillColor(vg, nvgRGBA(80, 80, 120, 120))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(120, 120, 160, 150))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
            nvgFontFaceId(vg, textFont)
            nvgFontSize(vg, 16)
            nvgFillColor(vg, nvgRGBA(200, 200, 220, 200))
            nvgText(vg, ix, iy, "+" .. remaining)
        end
    end

    -- 胜利时无遗言框
    if isVictory then
        HUD.tombInputBox = nil
    end

    -- 按钮行：复活（左）+ 再来一局（右）并排，或仅再来一局居中
    local btnRowY = panelY + panelH + 20
    local btnH    = 60
    local btnGap  = 12
    local t       = time.elapsedTime

    nvgFontFaceId(vg, textFont)
    nvgFontSize(vg, 26)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if not isVictory and HUD.showReviveBtn then
        -- ── 并排：左=复活，右=再来一局 ──
        local halfW = (panelW - btnGap) / 2

        -- 左：看广告复活（绿色渐变，脉冲）
        local rbX = panelX
        local greenPulse = 0.8 + 0.2 * math.sin(t * 4)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rbX, btnRowY, halfW, btnH, 12)
        nvgFillPaint(vg, nvgLinearGradient(vg, rbX, btnRowY, rbX, btnRowY + btnH,
            nvgRGBA(20, 180, 80, math.floor(230 * greenPulse)),
            nvgRGBA(10, 130, 50, math.floor(230 * greenPulse))))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 255, 150, math.floor(200 * greenPulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, rbX + halfW / 2, btnRowY + btnH / 2, "🎬 看广告复活")

        HUD.reviveBtnX = rbX
        HUD.reviveBtnY = btnRowY
        HUD.reviveBtnW = halfW
        HUD.reviveBtnH = btnH

        -- 右：再来一局（蓝紫渐变，微脉冲）
        local rsBtnX = panelX + halfW + btnGap
        local pulse  = 0.85 + 0.15 * math.sin(Wave.totalTime * 3)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rsBtnX, btnRowY, halfW, btnH, 12)
        nvgFillPaint(vg, nvgLinearGradient(vg, rsBtnX, btnRowY, rsBtnX, btnRowY + btnH,
            nvgRGBA(80, 70, 200, math.floor(220 * pulse)),
            nvgRGBA(50, 40, 150, math.floor(220 * pulse))))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(140, 130, 255, math.floor(180 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, rsBtnX + halfW / 2, btnRowY + btnH / 2, charDef.restartText or "再来一局！")

        HUD.restartBtnX = rsBtnX
        HUD.restartBtnY = btnRowY
        HUD.restartBtnW = halfW
        HUD.restartBtnH = btnH
    else
        -- ── 仅再来一局（居中） ──
        HUD.reviveBtnW = 0
        local rsBtnW = panelW
        local rsBtnX = panelX
        local pulse  = 0.85 + 0.15 * math.sin(Wave.totalTime * 3)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rsBtnX, btnRowY, rsBtnW, btnH, 12)
        nvgFillPaint(vg, nvgLinearGradient(vg, rsBtnX, btnRowY, rsBtnX, btnRowY + btnH,
            nvgRGBA(80, 70, 200, math.floor(220 * pulse)),
            nvgRGBA(50, 40, 150, math.floor(220 * pulse))))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(140, 130, 255, math.floor(180 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, rsBtnX + rsBtnW / 2, btnRowY + btnH / 2, charDef.restartText or "再来一局！")

        HUD.restartBtnX = rsBtnX
        HUD.restartBtnY = btnRowY
        HUD.restartBtnW = rsBtnW
        HUD.restartBtnH = btnH
    end
end

--- 检测技能/图腾/符文图标点击
---@param dx number 设计坐标 X
---@param dy number 设计坐标 Y
---@return boolean 是否命中了某个图标
function HUD.HitSkillIcon(dx, dy)
    for _, slot in ipairs(HUD.skillSlots) do
        if dx >= slot.x and dx <= slot.x + slot.w and dy >= slot.y and dy <= slot.y + slot.h then
            HUD.detailPopup = {
                icon = slot.icon,
                name = slot.name,
                desc = slot.desc,
                timer = HUD.detailPopupDuration,
            }
            return true
        end
    end
    return false
end

--- 更新详情弹窗计时器（每帧调用）
---@param dt number
function HUD.UpdateDetailPopup(dt)
    if HUD.detailPopup then
        HUD.detailPopup.timer = HUD.detailPopup.timer - dt
        if HUD.detailPopup.timer <= 0 then
            HUD.detailPopup = nil
        end
    end
end

--- 渲染详情弹窗（居中半透明面板）
---@param vg userdata
---@param viewW number
---@param viewH number
---@param font number
function HUD.RenderDetailPopup(vg, viewW, viewH, font)
    local popup = HUD.detailPopup
    if not popup then return end

    -- 淡入淡出
    local alpha = 1.0
    local fadeTime = 0.3
    if popup.timer < fadeTime then
        alpha = popup.timer / fadeTime
    elseif popup.timer > HUD.detailPopupDuration - fadeTime then
        alpha = (HUD.detailPopupDuration - popup.timer) / fadeTime
    end
    alpha = math.max(0, math.min(1, alpha))

    local panelW = 340
    local panelH = 120
    local px = (viewW - panelW) / 2
    local py = viewH / 2 - panelH / 2 - 60  -- 略偏上避免遮挡角色
    local cornerR = 12
    local baseAlpha = math.floor(alpha * 230)

    -- 背景面板
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, cornerR)
    nvgFillColor(vg, nvgRGBA(20, 12, 40, baseAlpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 140, 255, math.floor(alpha * 160)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- emoji 图标
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontFaceId(vg, font)
    nvgFontSize(vg, 36)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 255)))
    nvgText(vg, px + 36, py + panelH / 2 - 4, popup.icon)

    -- 名称（zpix 白边字）
    local textFont = HUD.zpixFontId >= 0 and HUD.zpixFontId or font
    nvgFontFaceId(vg, textFont)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 255)))
    nvgText(vg, px + 66, py + 16, popup.name)

    -- 描述（自动折行，灰色小字）
    nvgFontFaceId(vg, font)
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, math.floor(alpha * 200)))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    -- 用 nvgTextBox 自动折行
    local descX = px + 66
    local descW = panelW - 66 - 16
    nvgTextBox(vg, descX, py + 44, descW, popup.desc or "")
end

return HUD
