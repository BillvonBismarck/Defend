--- ============================================================================
--- 图鉴收集册 - 敌人/Boss/技能/符文/图腾/地图 全收集
--- 持久化到本地文件 + 云端整数位掩码
--- ============================================================================

local ok, cjson = pcall(require, "cjson")
if not ok then cjson = nil end

local Config = require("Config")

local Codex = {}

-- ── 持久化 ──
local CODEX_FILE = "codex.json"
local CLOUD_KEY  = "codex_mask"

-- ── 分类定义 ──
-- 每个分类: id, name, icon, entries[]
-- entry: { id, name, icon, desc }
-- 运行时 discovered[entryGlobalId] = true

Codex.CATEGORIES = {}  -- 初始化时填充
Codex.discovered = {}  -- { [globalId] = true }
Codex.allEntries = {}  -- { globalId -> { catIdx, entryIdx, def } }
Codex.notifications = {} -- { {name, icon, timer}, ... }
local NOTIFY_DURATION = 2.5

-- ============================================================================
-- 构建分类数据（从 Config 动态读取）
-- ============================================================================

local function BuildCategories()
    local cats = {}

    -- ── 1. 敌人种类 ──
    local enemyOrder = {
        "normal", "fast", "tank", "swarm", "charger",
        "ghost", "shaman", "ranger", "elite",
    }
    local enemyNames = {
        normal = "普通怪", fast = "速敏怪", tank = "坦克怪",
        swarm = "蜂群怪", charger = "冲锋怪", ghost = "幽灵怪",
        shaman = "巫师怪", ranger = "远程怪", elite = "精英怪",
    }
    local enemyDescs = {
        normal = "最基础的敌人，数量众多",
        fast = "移速极快，血量较低",
        tank = "血量极高，移速缓慢",
        swarm = "大量出现的小型单位",
        charger = "会向玩家冲锋突进",
        ghost = "半透明，可穿越障碍",
        shaman = "召唤其他敌人的施法者",
        ranger = "远距离攻击的射手",
        elite = "带有随机强化词缀的精英",
    }
    local enemyEntries = {}
    for _, etype in ipairs(enemyOrder) do
        local emojis = Config.ENEMY_EMOJI[etype]
        table.insert(enemyEntries, {
            id = "enemy_" .. etype,
            name = enemyNames[etype] or etype,
            icon = emojis and emojis[1] or "❓",
            desc = enemyDescs[etype] or "",
        })
    end
    table.insert(cats, {
        id = "enemy", name = "敌人", icon = "👾",
        entries = enemyEntries,
    })

    -- ── 2. Boss ──
    local bossEntries = {}
    for _, boss in ipairs(Config.BOSSES) do
        local skillNames = {}
        for _, sk in ipairs(boss.skills or {}) do
            table.insert(skillNames, sk.icon .. sk.name)
        end
        table.insert(bossEntries, {
            id = "boss_" .. boss.id,
            name = boss.name,
            icon = boss.emoji,
            desc = "技能: " .. table.concat(skillNames, " "),
        })
    end
    table.insert(cats, {
        id = "boss", name = "Boss", icon = "👹",
        entries = bossEntries,
    })

    -- ── 3. 技能 ──
    local skillEntries = {}
    for _, sk in ipairs(Config.SKILLS) do
        table.insert(skillEntries, {
            id = "skill_" .. sk.id,
            name = sk.name,
            icon = sk.icon,
            desc = sk.desc or "",
        })
    end
    table.insert(cats, {
        id = "skill", name = "技能", icon = "⚡",
        entries = skillEntries,
    })

    -- ── 4. 符文 ──
    local RuneSystem = require("meta.RuneSystem")
    local runeEntries = {}
    for _, rune in ipairs(RuneSystem.RUNES) do
        table.insert(runeEntries, {
            id = "rune_" .. rune.id,
            name = rune.name,
            icon = rune.icon,
            desc = rune.desc or "",
        })
    end
    table.insert(cats, {
        id = "rune", name = "符文", icon = "🔮",
        entries = runeEntries,
    })

    -- ── 5. 图腾 ──
    local TotemSystem = require("meta.TotemSystem")
    local totemEntries = {}
    for typeId, cfg in pairs(TotemSystem.TYPE_CONFIG) do
        table.insert(totemEntries, {
            id = "totem_" .. typeId,
            name = cfg.name,
            icon = cfg.icon,
            desc = cfg.desc or "",
        })
    end
    -- 排序保证一致性
    table.sort(totemEntries, function(a, b) return a.id < b.id end)
    table.insert(cats, {
        id = "totem", name = "图腾", icon = "🏺",
        entries = totemEntries,
    })

    -- ── 6. 地图 ──
    local MapVariant = require("battle.MapVariant")
    local mapEntries = {}
    for _, mv in ipairs(MapVariant.GetAllVariants()) do
        local obstNames = {}
        for _, obs in ipairs(mv.obstacles or {}) do
            table.insert(obstNames, obs.emoji .. (obs.name or ""))
        end
        table.insert(mapEntries, {
            id = "map_" .. mv.id,
            name = mv.name,
            icon = mv.icon,
            desc = #obstNames > 0 and ("障碍: " .. table.concat(obstNames, " ")) or "无障碍物",
        })
    end
    table.insert(cats, {
        id = "map", name = "地图", icon = "🗺️",
        entries = mapEntries,
    })

    Codex.CATEGORIES = cats

    -- 构建全局索引 (用于位掩码)
    Codex.allEntries = {}
    Codex._bitIndex = {}  -- globalId -> 0-based bit index
    Codex._bitToId = {}   -- bit index -> globalId
    local bitIdx = 0
    for _, cat in ipairs(cats) do
        for _, entry in ipairs(cat.entries) do
            Codex.allEntries[entry.id] = entry
            Codex._bitIndex[entry.id] = bitIdx
            Codex._bitToId[bitIdx] = entry.id
            bitIdx = bitIdx + 1
        end
    end
    Codex._totalEntries = bitIdx
end

-- ============================================================================
-- 持久化
-- ============================================================================

function Codex.Load()
    if not cjson then return end
    if not fileSystem:FileExists(CODEX_FILE) then return end
    local file = File(CODEX_FILE, FILE_READ)
    if not file:IsOpen() then return end
    local ok2, data = pcall(cjson.decode, file:ReadString())
    file:Close()
    if ok2 and data and data.discovered then
        for id, val in pairs(data.discovered) do
            if Codex.allEntries[id] then
                Codex.discovered[id] = val
            end
        end
    end
    print("[Codex] Loaded, discovered=" .. Codex.GetDiscoveredCount())
end

function Codex.Save()
    if not cjson then return end
    local data = { discovered = Codex.discovered }
    local file = File(CODEX_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(data))
        file:Close()
    end
    Codex.SyncToCloud()
end

-- ============================================================================
-- 云端同步（多个整数位掩码，每64位一个 key）
-- ============================================================================

function Codex.EncodeBitmasks()
    -- 返回 { key1 = mask1, key2 = mask2, ... }
    -- 每个 key 最多 53 位（JS 安全整数）
    local BITS_PER_KEY = 53
    local masks = {}
    for id, val in pairs(Codex.discovered) do
        if val and Codex._bitIndex[id] then
            local bit = Codex._bitIndex[id]
            local keyIdx = math.floor(bit / BITS_PER_KEY)
            local bitInKey = bit % BITS_PER_KEY
            local key = CLOUD_KEY .. (keyIdx > 0 and ("_" .. keyIdx) or "")
            masks[key] = (masks[key] or 0) | (1 << bitInKey)
        end
    end
    return masks
end

function Codex.SyncToCloud()
    if not clientCloud then return end
    local masks = Codex.EncodeBitmasks()
    for key, mask in pairs(masks) do
        clientCloud:SetInt(key, mask, {
            ok = function()
                print("[Codex] Cloud sync OK: " .. key .. "=" .. mask)
            end,
            error = function(_, reason)
                print("[Codex] Cloud sync fail: " .. tostring(reason))
            end,
        })
    end
end

function Codex.SyncFromCloud()
    if not clientCloud then return end
    local BITS_PER_KEY = 53
    -- 计算需要多少个 key
    local numKeys = math.ceil((Codex._totalEntries or 1) / BITS_PER_KEY)
    local keysToFetch = {}
    for i = 0, numKeys - 1 do
        local key = CLOUD_KEY .. (i > 0 and ("_" .. i) or "")
        table.insert(keysToFetch, key)
    end

    -- 逐个拉取（简化实现）
    for _, key in ipairs(keysToFetch) do
        clientCloud:Get(key, {
            ok = function(_, iscores)
                local cloudMask = iscores[key] or 0
                if cloudMask == 0 then return end
                local keyIdx = 0
                if key:find("_") then
                    keyIdx = tonumber(key:match("_(%d+)$")) or 0
                end
                local hasNew = false
                for b = 0, BITS_PER_KEY - 1 do
                    if (cloudMask & (1 << b)) ~= 0 then
                        local globalBit = keyIdx * BITS_PER_KEY + b
                        local entryId = Codex._bitToId[globalBit]
                        if entryId and not Codex.discovered[entryId] then
                            Codex.discovered[entryId] = true
                            hasNew = true
                        end
                    end
                end
                if hasNew then
                    -- 保存本地
                    if cjson then
                        local data = { discovered = Codex.discovered }
                        local file = File(CODEX_FILE, FILE_WRITE)
                        if file:IsOpen() then
                            file:WriteString(cjson.encode(data))
                            file:Close()
                        end
                    end
                    print("[Codex] Merged from cloud: " .. key)
                end
            end,
            error = function(_, reason)
                print("[Codex] Cloud fetch fail: " .. tostring(reason))
            end,
        })
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

function Codex.Init()
    Codex.discovered = {}
    Codex.notifications = {}
    BuildCategories()
    Codex.Load()
    Codex.SyncFromCloud()

    -- 回溯已拥有的图腾/符文（静默，不弹通知）
    local SaveData = require("SaveData")
    local hasNew = false
    -- 图腾背包 + 已装备
    local allTotems = {}
    for _, t in ipairs(SaveData.totems or {}) do
        allTotems["totem_" .. t.typeId] = true
    end
    for _, t in ipairs(SaveData.equippedTotems or {}) do
        allTotems["totem_" .. t.typeId] = true
    end
    for gid in pairs(allTotems) do
        if Codex.allEntries[gid] and not Codex.discovered[gid] then
            Codex.discovered[gid] = true
            hasNew = true
        end
    end
    -- 符文
    for runeId in pairs(SaveData.ownedRunes or {}) do
        local gid = "rune_" .. runeId
        if Codex.allEntries[gid] and not Codex.discovered[gid] then
            Codex.discovered[gid] = true
            hasNew = true
        end
    end
    if hasNew then
        Codex.Save()
        print("[Codex] Retroactive discovery from SaveData")
    end
end

-- ============================================================================
-- 发现逻辑
-- ============================================================================

--- 发现一个条目（幂等）
---@param globalId string  例如 "enemy_normal", "boss_police", "skill_atk_drone"
---@return boolean 是否新发现
function Codex.Discover(globalId)
    if Codex.discovered[globalId] then return false end
    if not Codex.allEntries[globalId] then
        print("[Codex] Unknown entry: " .. tostring(globalId))
        return false
    end
    Codex.discovered[globalId] = true
    Codex.Save()

    local def = Codex.allEntries[globalId]
    table.insert(Codex.notifications, {
        name = def.name,
        icon = def.icon,
        timer = NOTIFY_DURATION,
    })
    print("[Codex] DISCOVERED: " .. def.icon .. " " .. def.name)
    -- 成就检查
    local Achievement = require("Achievement")
    Achievement.CheckCodexDiscover(Codex.GetDiscoveredCount(), Codex.GetTotalCount())
    return true
end

--- 批量发现（不会每次都保存，最后统一保存）
---@param ids string[]
function Codex.DiscoverBatch(ids)
    local hasNew = false
    for _, gid in ipairs(ids) do
        if not Codex.discovered[gid] and Codex.allEntries[gid] then
            Codex.discovered[gid] = true
            hasNew = true
            local def = Codex.allEntries[gid]
            table.insert(Codex.notifications, {
                name = def.name, icon = def.icon, timer = NOTIFY_DURATION,
            })
        end
    end
    if hasNew then Codex.Save() end
end

--- 是否已发现
---@param globalId string
---@return boolean
function Codex.IsDiscovered(globalId)
    return Codex.discovered[globalId] == true
end

-- ============================================================================
-- 统计
-- ============================================================================

function Codex.GetDiscoveredCount()
    local n = 0
    for _ in pairs(Codex.discovered) do n = n + 1 end
    return n
end

function Codex.GetTotalCount()
    return Codex._totalEntries or 0
end

function Codex.GetProgress()
    return Codex.GetDiscoveredCount(), Codex.GetTotalCount()
end

--- 获取某分类的进度
---@param catId string
---@return number discovered, number total
function Codex.GetCategoryProgress(catId)
    for _, cat in ipairs(Codex.CATEGORIES) do
        if cat.id == catId then
            local d = 0
            for _, entry in ipairs(cat.entries) do
                if Codex.discovered[entry.id] then d = d + 1 end
            end
            return d, #cat.entries
        end
    end
    return 0, 0
end

-- ============================================================================
-- 通知
-- ============================================================================

function Codex.Update(dt)
    local i = 1
    while i <= #Codex.notifications do
        Codex.notifications[i].timer = Codex.notifications[i].timer - dt
        if Codex.notifications[i].timer <= 0 then
            table.remove(Codex.notifications, i)
        else
            i = i + 1
        end
    end
end

--- 渲染发现通知（右上角小提示）
---@param vg userdata
---@param viewW number
---@param viewH number
---@param fontId number
function Codex.RenderNotifications(vg, viewW, viewH, fontId)
    if #Codex.notifications == 0 then return end
    nvgFontFaceId(vg, zpix)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local cx = viewW / 2
    for i, n in ipairs(Codex.notifications) do
        local progress = 1 - (n.timer / NOTIFY_DURATION)
        local slideIn = math.min(1, progress * 5)
        local fadeOut = math.min(1, n.timer / 0.4)
        local alpha = math.floor(220 * fadeOut)
        local baseY = 170 + (i - 1) * 44
        local y = baseY - (1 - slideIn) * 30

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 140, y - 18, 280, 36, 10)
        nvgFillColor(vg, nvgRGBA(20, 40, 60, math.floor(180 * fadeOut)))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 200, 255, alpha))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(80, 200, 255, alpha))
        nvgText(vg, cx, y, "📖 图鉴发现: " .. n.icon .. " " .. n.name)
    end
end

-- ============================================================================
-- 渲染图鉴页面（全屏，带标签页切换和滚动）
-- ============================================================================

-- UI 状态
Codex._activeTab = 1      -- 当前选中的分类标签 (1-based)
Codex._scrollY = 0        -- 滚动偏移
Codex._scrollVel = 0      -- 滚动惯性
Codex._dragStartY = nil
Codex._dragLastY = nil
Codex._dragScrollStart = 0

function Codex.ResetPageState()
    Codex._activeTab = 1
    Codex._scrollY = 0
    Codex._scrollVel = 0
    Codex._dragStartY = nil
end

--- 渲染图鉴页面
---@param vg userdata
---@param viewW number
---@param viewH number
---@param fontId number
function Codex.RenderPage(vg, viewW, viewH, fontId)
    local bg = Config.COLORS.bg
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
    nvgFill(vg)

    local cx = viewW / 2
    local t = time.elapsedTime

    nvgFontFaceId(vg, zpix)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- ── 标题 ──
    nvgFontSize(vg, 34)
    nvgFillColor(vg, nvgRGBA(80, 200, 255, 255))
    nvgText(vg, cx, 50, "📖 图鉴收集册")

    -- 总进度（zpix字体，延迟获取避免循环依赖）
    local HUD = require("ui.HUD")
    local zpix = HUD.zpixFontId >= 0 and HUD.zpixFontId or fontId
    local dCount, dTotal = Codex.GetProgress()
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(180, 200, 220, 160))
    nvgText(vg, cx, 80, dCount .. " / " .. dTotal .. " 已发现")
    nvgFontFaceId(vg, zpix)

    -- 总进度条
    local barW = 300
    local barH = 6
    local barX = cx - barW / 2
    local barY = 94
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 3)
    nvgFillColor(vg, nvgRGBA(40, 50, 70, 200))
    nvgFill(vg)
    if dTotal > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * (dCount / dTotal), barH, 3)
        nvgFillColor(vg, nvgRGBA(80, 200, 255, 200))
        nvgFill(vg)
    end

    -- ── 分类标签页 ──
    local tabY = 114
    local tabH = 38
    local tabGap = 4
    local numTabs = #Codex.CATEGORIES
    local totalTabW = viewW - 30
    local tabW = math.floor((totalTabW - tabGap * (numTabs - 1)) / numTabs)
    local tabStartX = 15

    for i, cat in ipairs(Codex.CATEGORIES) do
        local tx = tabStartX + (i - 1) * (tabW + tabGap)
        local isActive = (i == Codex._activeTab)
        local catD, catT = Codex.GetCategoryProgress(cat.id)
        local allDone = (catD == catT and catT > 0)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, tabY, tabW, tabH, 8)
        if isActive then
            nvgFillColor(vg, nvgRGBA(40, 80, 120, 230))
        else
            nvgFillColor(vg, nvgRGBA(20, 25, 40, 200))
        end
        nvgFill(vg)

        if isActive then
            nvgStrokeColor(vg, nvgRGBA(80, 200, 255, 180))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 图标 + 进度
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, isActive and 240 or 120))
        nvgText(vg, tx + tabW / 2, tabY + 3, cat.icon)

        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 11)
        if allDone then
            nvgFillColor(vg, nvgRGBA(80, 255, 120, isActive and 220 or 140))
        else
            nvgFillColor(vg, nvgRGBA(180, 200, 220, isActive and 180 or 100))
        end
        nvgText(vg, tx + tabW / 2, tabY + 22, catD .. "/" .. catT)
        nvgFontFaceId(vg, zpix)
    end

    -- ── 内容区域 ──
    local contentY = tabY + tabH + 10
    local contentH = viewH - contentY - 70  -- 底部留返回按钮空间

    -- 裁剪区域（用 NanoVG scissor）
    nvgSave(vg)
    nvgScissor(vg, 0, contentY, viewW, contentH)

    local cat = Codex.CATEGORIES[Codex._activeTab]
    if cat then
        local cardX = 20
        local cardW = viewW - 40
        local cardH = 72
        local cardGap = 8
        local scrollY = Codex._scrollY

        for i, entry in ipairs(cat.entries) do
            local y = contentY + (i - 1) * (cardH + cardGap) - scrollY
            -- 可见性裁剪
            if y + cardH < contentY - 10 then goto skipCard end
            if y > contentY + contentH + 10 then goto skipCard end

            local isFound = Codex.IsDiscovered(entry.id)

            -- 卡片背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cardX, y, cardW, cardH, 10)
            if isFound then
                nvgFillColor(vg, nvgRGBA(20, 40, 55, 220))
            else
                nvgFillColor(vg, nvgRGBA(18, 16, 30, 200))
            end
            nvgFill(vg)

            -- 边框
            if isFound then
                nvgStrokeColor(vg, nvgRGBA(60, 160, 200, 100))
            else
                nvgStrokeColor(vg, nvgRGBA(50, 45, 70, 80))
            end
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            local midY = y + cardH / 2

            -- 图标
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 30)
            if isFound then
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                nvgText(vg, cardX + 32, midY, entry.icon)
            else
                nvgFillColor(vg, nvgRGBA(80, 80, 100, 100))
                nvgText(vg, cardX + 32, midY, "❓")
            end

            -- 名称
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
            nvgFontSize(vg, 17)
            if isFound then
                nvgFillColor(vg, nvgRGBA(230, 240, 255, 240))
            else
                nvgFillColor(vg, nvgRGBA(120, 120, 140, 140))
            end
            nvgText(vg, cardX + 64, midY - 1, isFound and entry.name or "???")

            -- 描述
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFontSize(vg, 12)
            if isFound then
                nvgFillColor(vg, nvgRGBA(140, 180, 200, 180))
                -- 截断过长描述
                local desc = entry.desc or ""
                if #desc > 50 then desc = desc:sub(1, 48) .. "…" end
                nvgText(vg, cardX + 64, midY + 4, desc)
            else
                nvgFillColor(vg, nvgRGBA(100, 100, 120, 100))
                nvgText(vg, cardX + 64, midY + 4, "尚未发现")
            end

            -- 已发现标记
            if isFound then
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFontSize(vg, 14)
                nvgFillColor(vg, nvgRGBA(80, 200, 255, 180))
                nvgText(vg, cardX + cardW - 14, midY, "✅")
            end

            ::skipCard::
        end

        -- 滚动边界提示
        local maxScroll = math.max(0, #cat.entries * (cardH + cardGap) - contentH)
        if Codex._scrollY > maxScroll + 20 then
            Codex._scrollY = maxScroll + 20
        end
        if Codex._scrollY < -20 then
            Codex._scrollY = -20
        end
    end

    nvgRestore(vg)

    -- ── 返回按钮 ──
    local backW = 200
    local backH = 48
    local backX = cx - backW / 2
    local backY = viewH - 65

    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, backX, backY, backW, backH, 12)
    nvgFillColor(vg, nvgRGBA(20, 35, 55, 180))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 200, 255, 120))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(200, 220, 240, 200))
    nvgText(vg, cx, backY + backH / 2, "← 返回")
end

--- 返回按钮区域
function Codex.GetBackButtonRect(viewW, viewH)
    local backW = 200
    local backH = 48
    return {
        x = viewW / 2 - backW / 2,
        y = viewH - 65,
        w = backW,
        h = backH,
    }
end

--- 获取标签点击区域
---@return table[] { {x,y,w,h,catIdx}, ... }
function Codex.GetTabRects(viewW)
    local tabY = 114
    local tabH = 38
    local tabGap = 4
    local numTabs = #Codex.CATEGORIES
    local totalTabW = viewW - 30
    local tabW = math.floor((totalTabW - tabGap * (numTabs - 1)) / numTabs)
    local tabStartX = 15
    local rects = {}
    for i = 1, numTabs do
        local tx = tabStartX + (i - 1) * (tabW + tabGap)
        table.insert(rects, { x = tx, y = tabY, w = tabW, h = tabH, catIdx = i })
    end
    return rects
end

--- 处理点击
---@param dx number 设计坐标
---@param dy number 设计坐标
---@param viewW number
---@param viewH number
---@return string|nil "back" 表示返回
function Codex.HandleTouch(dx, dy, viewW, viewH)
    -- 返回按钮
    local backRect = Codex.GetBackButtonRect(viewW, viewH)
    if dx >= backRect.x and dx <= backRect.x + backRect.w and dy >= backRect.y and dy <= backRect.y + backRect.h then
        return "back"
    end

    -- 标签切换
    local tabs = Codex.GetTabRects(viewW)
    for _, tab in ipairs(tabs) do
        if dx >= tab.x and dx <= tab.x + tab.w and dy >= tab.y and dy <= tab.y + tab.h then
            if Codex._activeTab ~= tab.catIdx then
                Codex._activeTab = tab.catIdx
                Codex._scrollY = 0
                Codex._scrollVel = 0
            end
            return nil
        end
    end

    return nil
end

--- 处理拖动开始（用于滚动）
function Codex.HandleDragBegin(dy)
    Codex._dragStartY = dy
    Codex._dragLastY = dy
    Codex._dragScrollStart = Codex._scrollY
    Codex._scrollVel = 0
end

--- 处理拖动（在 HandleUpdate 中检测 MouseMove 调用）
function Codex.HandleDragMove(dy)
    if Codex._dragStartY then
        local delta = Codex._dragStartY - dy
        Codex._scrollY = Codex._dragScrollStart + delta
        if Codex._dragLastY then
            Codex._scrollVel = (Codex._dragLastY - dy) * 8
        end
        Codex._dragLastY = dy
    end
end

--- 处理拖动结束
function Codex.HandleDragEnd()
    Codex._dragStartY = nil
    Codex._dragLastY = nil
end

--- 滚动惯性更新（在 HandleUpdate 中调用）
function Codex.UpdateScroll(dt)
    if not Codex._dragStartY then
        -- 惯性衰减
        Codex._scrollY = Codex._scrollY + Codex._scrollVel * dt
        Codex._scrollVel = Codex._scrollVel * 0.92

        -- 弹性回弹
        local cat = Codex.CATEGORIES[Codex._activeTab]
        if cat then
            local maxScroll = math.max(0, #cat.entries * 80 - (1280 - 114 - 38 - 10 - 70))
            if Codex._scrollY < 0 then
                Codex._scrollY = Codex._scrollY * 0.85
                Codex._scrollVel = 0
            elseif Codex._scrollY > maxScroll then
                Codex._scrollY = maxScroll + (Codex._scrollY - maxScroll) * 0.85
                Codex._scrollVel = 0
            end
        end

        if math.abs(Codex._scrollVel) < 0.5 then
            Codex._scrollVel = 0
        end
    end
end

return Codex
