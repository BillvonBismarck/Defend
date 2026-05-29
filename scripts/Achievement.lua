--- ============================================================================
--- 成就系统 - 定义、解锁、持久化（本地+云端）、通知
--- ============================================================================

local ok, cjson = pcall(require, "cjson")
if not ok then
    print("[Achievement] WARNING: cjson not available")
    cjson = nil
end

local Config = require("Config")

local Achievement = {}

-- 持久化文件
local ACH_FILE = "achievements.json"

-- 云变量 key（整数位掩码，存在 iscores）
local CLOUD_KEY = "achievements"

-- 成就解锁通知队列
Achievement.notifications = {}  -- { {id, name, icon, timer}, ... }
local NOTIFY_DURATION = 3.0     -- 通知显示时长（秒）

-- 云端同步状态
local cloudSynced = false       -- 是否已完成首次云端同步

-- ============================================================================
-- 成就定义
-- ============================================================================

-- 动态生成角色50级成就
local charAchievements = {}
for _, ch in ipairs(Config.CHARACTERS) do
    table.insert(charAchievements, {
        id = "char_lv50_" .. ch.id,
        name = ch.name .. " Lv.50",
        desc = ch.name .. "达到50级",
        icon = ch.emoji,
        category = "character",
    })
end

-- 固定成就
local fixedAchievements = {
    -- ── 战斗 ──
    {
        id = "first_wave_death",
        name = "出师未捷",
        desc = "第一波就阵亡",
        icon = "💀",
        category = "challenge",
    },
    {
        id = "bomb_20_kills",
        name = "爆破专家",
        desc = "单次炸弹清除20个敌怪",
        icon = "💣",
        category = "combat",
    },
    {
        id = "give_up_gift",
        name = "淡泊名利",
        desc = "放弃广告宝箱奖励",
        icon = "🎁",
        category = "misc",
    },
    -- ── 波次里程碑 ──
    {
        id = "wave_10",
        name = "初露锋芒",
        desc = "到达第10波",
        icon = "🌊",
        category = "milestone",
    },
    {
        id = "wave_20",
        name = "身经百战",
        desc = "到达第20波",
        icon = "⚔️",
        category = "milestone",
    },
    {
        id = "wave_30",
        name = "战场老兵",
        desc = "到达第30波",
        icon = "🎖️",
        category = "milestone",
    },
    {
        id = "wave_50",
        name = "传奇幸存者",
        desc = "到达第50波",
        icon = "👑",
        category = "milestone",
    },
    -- ── 击杀 ──
    {
        id = "kills_100",
        name = "初窥门径",
        desc = "单局击杀100个敌人",
        icon = "🗡️",
        category = "combat",
    },
    {
        id = "kills_500",
        name = "杀戮机器",
        desc = "单局击杀500个敌人",
        icon = "⚡",
        category = "combat",
    },
    {
        id = "kills_1000",
        name = "万夫莫敌",
        desc = "单局击杀1000个敌人",
        icon = "🔥",
        category = "combat",
    },
    -- ── 等级 ──
    {
        id = "level_10",
        name = "小有所成",
        desc = "单局达到10级",
        icon = "📈",
        category = "growth",
    },
    {
        id = "level_20",
        name = "实力非凡",
        desc = "单局达到20级",
        icon = "💪",
        category = "growth",
    },
    {
        id = "level_30",
        name = "登峰造极",
        desc = "单局达到30级",
        icon = "🏔️",
        category = "growth",
    },
    -- ── 难度挑战 ──
    {
        id = "hard_wave10",
        name = "硬核玩家",
        desc = "困难难度到达第10波",
        icon = "🔴",
        category = "challenge",
    },
    {
        id = "nightmare_wave5",
        name = "噩梦行者",
        desc = "噩梦难度到达第5波",
        icon = "💀",
        category = "challenge",
    },
    {
        id = "nightmare_wave10",
        name = "噩梦征服者",
        desc = "噩梦难度到达第10波",
        icon = "☠️",
        category = "challenge",
    },
    -- ── 精英怪 ──
    {
        id = "elite_kill_10",
        name = "精英猎手",
        desc = "累计击杀10个精英怪",
        icon = "🛡️",
        category = "combat",
    },
    {
        id = "elite_kill_50",
        name = "精英终结者",
        desc = "累计击杀50个精英怪",
        icon = "⭐",
        category = "combat",
    },
    -- ── Boss ──
    {
        id = "boss_kill_1",
        name = "屠龙勇士",
        desc = "击杀第一个Boss",
        icon = "🐉",
        category = "combat",
    },
    {
        id = "boss_kill_10",
        name = "Boss终结者",
        desc = "累计击杀10个Boss",
        icon = "👹",
        category = "combat",
    },
    -- ── 经济 ──
    {
        id = "gold_1000",
        name = "小有积蓄",
        desc = "累计获得1000金币",
        icon = "🪙",
        category = "economy",
    },
    {
        id = "gold_10000",
        name = "富甲一方",
        desc = "累计获得10000金币",
        icon = "💰",
        category = "economy",
    },
    -- ── 每日挑战 ──
    {
        id = "daily_1",
        name = "每日打卡",
        desc = "完成1次每日挑战",
        icon = "📅",
        category = "daily",
    },
    {
        id = "daily_5",
        name = "持之以恒",
        desc = "完成5次每日挑战",
        icon = "📆",
        category = "daily",
    },
    -- ── 收集 ──
    {
        id = "all_chars_unlocked",
        name = "全员集合",
        desc = "解锁全部角色",
        icon = "🎭",
        category = "collection",
    },
    {
        id = "relic_3",
        name = "遗物收藏家",
        desc = "升级3个不同遗物",
        icon = "🏺",
        category = "collection",
    },
    -- ── 速通 ──
    {
        id = "speedrun_wave10",
        name = "闪电突击",
        desc = "5分钟内到达第10波",
        icon = "⏱️",
        category = "challenge",
    },
    -- ── 图鉴 (33) ──
    {
        id = "codex_10",
        name = "博物学者",
        desc = "图鉴收录10个条目",
        icon = "📖",
        category = "collection",
    },
    {
        id = "codex_all",
        name = "百科全书",
        desc = "图鉴收录全部条目",
        icon = "📚",
        category = "collection",
    },
    -- ── 周挑战 (31) ──
    {
        id = "weekly_1",
        name = "赛季初体验",
        desc = "完成1次周挑战",
        icon = "📋",
        category = "weekly",
    },
    {
        id = "weekly_7",
        name = "赛季全勤",
        desc = "累计完成7次周挑战",
        icon = "🏅",
        category = "weekly",
    },
    -- ── 地图事件 (30) ──
    {
        id = "event_treasure",
        name = "宝箱猎人",
        desc = "击杀全部守卫开启宝箱",
        icon = "📦",
        category = "exploration",
    },
    {
        id = "event_all_types",
        name = "事件达人",
        desc = "触发全部6种地图事件",
        icon = "🗺️",
        category = "exploration",
    },
    -- ── 地图变体 (35) ──
    {
        id = "variant_all",
        name = "环游世界",
        desc = "在全部4种地图中通关",
        icon = "🌍",
        category = "exploration",
    },
    -- ── 符文共鸣 (37) ──
    {
        id = "resonance_1",
        name = "共鸣初现",
        desc = "首次激活符文共鸣",
        icon = "✨",
        category = "collection",
    },
    {
        id = "resonance_all",
        name = "共鸣大师",
        desc = "激活全部6种符文共鸣",
        icon = "💎",
        category = "collection",
    },
}

-- 合并所有成就定义
Achievement.DEFS = {}
for _, a in ipairs(charAchievements) do
    table.insert(Achievement.DEFS, a)
end
for _, a in ipairs(fixedAchievements) do
    table.insert(Achievement.DEFS, a)
end

-- 按 id 索引 + 位掩码索引（bit 0 ~ N-1）
local defsById = {}
local bitIndexById = {}  -- id -> bit 位 (0-based)
for i, def in ipairs(Achievement.DEFS) do
    defsById[def.id] = def
    bitIndexById[def.id] = i - 1  -- Lua 数组 1-based，bit 0-based
end

-- ============================================================================
-- 运行时状态
-- ============================================================================

-- unlocked[id] = true/false
Achievement.unlocked = {}

-- ============================================================================
-- 持久化
-- ============================================================================

function Achievement.Load()
    if not cjson then return end
    if not fileSystem:FileExists(ACH_FILE) then return end

    local file = File(ACH_FILE, FILE_READ)
    if not file:IsOpen() then return end

    local ok2, data = pcall(cjson.decode, file:ReadString())
    file:Close()

    if ok2 and data and data.unlocked then
        for id, val in pairs(data.unlocked) do
            if defsById[id] then
                Achievement.unlocked[id] = val
            end
        end
    end
    print("[Achievement] Loaded, unlocked count=" .. Achievement.GetUnlockedCount())
end

function Achievement.Save()
    if not cjson then return end

    local data = {
        unlocked = Achievement.unlocked,
    }

    local file = File(ACH_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(data))
        file:Close()
    end

    -- 同步到云端
    Achievement.SyncToCloud()
end

-- ============================================================================
-- 云端同步（位掩码）
-- ============================================================================

--- 将当前解锁状态编码为整数位掩码
---@return integer
function Achievement.EncodeBitmask()
    local mask = 0
    for id, val in pairs(Achievement.unlocked) do
        if val and bitIndexById[id] then
            mask = mask | (1 << bitIndexById[id])
        end
    end
    return mask
end

--- 从位掩码解码并合并到本地（不覆盖，只补充）
---@param mask integer
---@return boolean hasNew 是否有新增解锁
function Achievement.MergeFromBitmask(mask)
    local hasNew = false
    for id, bitIdx in pairs(bitIndexById) do
        if (mask & (1 << bitIdx)) ~= 0 then
            if not Achievement.unlocked[id] then
                Achievement.unlocked[id] = true
                hasNew = true
                print("[Achievement] 从云端同步: " .. id)
            end
        end
    end
    return hasNew
end

--- 上传到云端
function Achievement.SyncToCloud()
    if not clientCloud then return end
    local mask = Achievement.EncodeBitmask()
    clientCloud:SetInt(CLOUD_KEY, mask, {
        ok = function()
            print("[Achievement] 云端同步成功, mask=" .. mask)
        end,
        error = function(code, reason)
            print("[Achievement] 云端同步失败: " .. tostring(reason))
        end
    })
end

--- 从云端拉取并合并
function Achievement.SyncFromCloud()
    if not clientCloud then return end
    clientCloud:Get(CLOUD_KEY, {
        ok = function(values, iscores)
            local cloudMask = iscores[CLOUD_KEY] or 0
            local localMask = Achievement.EncodeBitmask()

            -- 云端 → 本地（补充缺失的）
            local hasNew = Achievement.MergeFromBitmask(cloudMask)
            if hasNew then
                -- 本地有新数据，保存本地文件
                if cjson then
                    local data = { unlocked = Achievement.unlocked }
                    local file = File(ACH_FILE, FILE_WRITE)
                    if file:IsOpen() then
                        file:WriteString(cjson.encode(data))
                        file:Close()
                    end
                end
            end

            -- 本地 → 云端（本地有云端没有的）
            local mergedMask = Achievement.EncodeBitmask()
            if mergedMask ~= cloudMask then
                clientCloud:SetInt(CLOUD_KEY, mergedMask, {
                    ok = function()
                        print("[Achievement] 云端已更新, mask=" .. mergedMask)
                    end
                })
            end

            cloudSynced = true
            print("[Achievement] 云端同步完成, unlocked=" .. Achievement.GetUnlockedCount())
        end,
        error = function(code, reason)
            cloudSynced = true  -- 标记完成，避免反复重试
            print("[Achievement] 云端拉取失败: " .. tostring(reason))
        end
    })
end

--- 初始化（在 Start() 中调用）
function Achievement.Init()
    Achievement.unlocked = {}
    Achievement.notifications = {}
    cloudSynced = false
    Achievement.Load()
    -- 异步从云端拉取并合并
    Achievement.SyncFromCloud()
end

-- ============================================================================
-- 解锁逻辑
-- ============================================================================

--- 尝试解锁成就（幂等：已解锁的不会重复触发）
---@param id string 成就 ID
---@return boolean 是否新解锁
function Achievement.Unlock(id)
    if Achievement.unlocked[id] then return false end

    local def = defsById[id]
    if not def then
        print("[Achievement] Unknown achievement: " .. tostring(id))
        return false
    end

    Achievement.unlocked[id] = true
    Achievement.Save()

    -- 加入通知队列
    table.insert(Achievement.notifications, {
        id = id,
        name = def.name,
        icon = def.icon,
        timer = NOTIFY_DURATION,
    })

    print("[Achievement] UNLOCKED: " .. def.icon .. " " .. def.name)
    return true
end

--- 检查是否已解锁
---@param id string
---@return boolean
function Achievement.IsUnlocked(id)
    return Achievement.unlocked[id] == true
end

--- 获取已解锁数量
---@return number
function Achievement.GetUnlockedCount()
    local count = 0
    for _ in pairs(Achievement.unlocked) do
        count = count + 1
    end
    return count
end

--- 获取总成就数量
---@return number
function Achievement.GetTotalCount()
    return #Achievement.DEFS
end

--- 返回已解锁数和总数
---@return number unlocked, number total
function Achievement.GetProgress()
    return Achievement.GetUnlockedCount(), Achievement.GetTotalCount()
end

-- ============================================================================
-- 成就触发检查（由 main.lua 回调调用）
-- ============================================================================

-- 累计统计（本地持久化，与成就解锁数据一起保存）
Achievement.stats = {
    eliteKills = 0,
    bossKills  = 0,
    totalGold  = 0,
    dailyDone  = 0,
    weeklyDone = 0,              -- 周挑战完成次数
    eventTypes = {},             -- 已触发过的地图事件类型 {treasure=true, ...}
    variantClears = {},          -- 已通关的地图变体 {cyber=true, ...}
    resonanceSeen = {},          -- 已激活过的符文共鸣 {flame_rebirth=true, ...}
}

--- 加载累计统计
local function LoadStats(data)
    if data and data.stats then
        for k, v in pairs(data.stats) do
            Achievement.stats[k] = v
        end
    end
end

--- 保存时附带累计统计
local origSave = Achievement.Save
function Achievement.Save()
    if not cjson then return end
    local data = {
        unlocked = Achievement.unlocked,
        stats = Achievement.stats,
    }
    local file = File(ACH_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(data))
        file:Close()
    end
    Achievement.SyncToCloud()
end

--- 覆盖 Load 以加载 stats
local origLoad = Achievement.Load
function Achievement.Load()
    if not cjson then return end
    if not fileSystem:FileExists(ACH_FILE) then return end
    local file = File(ACH_FILE, FILE_READ)
    if not file:IsOpen() then return end
    local ok2, data = pcall(cjson.decode, file:ReadString())
    file:Close()
    if ok2 and data then
        if data.unlocked then
            for id, val in pairs(data.unlocked) do
                if defsById[id] then
                    Achievement.unlocked[id] = val
                end
            end
        end
        LoadStats(data)
    end
    print("[Achievement] Loaded, unlocked=" .. Achievement.GetUnlockedCount()
          .. " eliteKills=" .. Achievement.stats.eliteKills
          .. " bossKills=" .. Achievement.stats.bossKills)
end

--- 游戏结束时检查
---@param isVictory boolean
---@param stats table { wave, kills, level, time, ... }
---@param charId string
function Achievement.CheckGameOver(isVictory, stats, charId)
    local wave = stats.wave or 0
    local kills = stats.kills or 0
    local level = stats.level or 0
    local gameTime = stats.time or 0

    -- 角色50级成就
    if level >= 50 then
        Achievement.Unlock("char_lv50_" .. charId)
    end

    -- 第一波阵亡
    if not isVictory and wave <= 1 then
        Achievement.Unlock("first_wave_death")
    end

    -- 波次里程碑
    if wave >= 10 then Achievement.Unlock("wave_10") end
    if wave >= 20 then Achievement.Unlock("wave_20") end
    if wave >= 30 then Achievement.Unlock("wave_30") end
    if wave >= 50 then Achievement.Unlock("wave_50") end

    -- 击杀里程碑
    if kills >= 100  then Achievement.Unlock("kills_100") end
    if kills >= 500  then Achievement.Unlock("kills_500") end
    if kills >= 1000 then Achievement.Unlock("kills_1000") end

    -- 等级里程碑
    if level >= 10 then Achievement.Unlock("level_10") end
    if level >= 20 then Achievement.Unlock("level_20") end
    if level >= 30 then Achievement.Unlock("level_30") end

    -- 难度挑战（需要 Config.GetDifficulty）
    local diff = Config.GetDifficulty()
    if diff.id == "hard" and wave >= 10 then
        Achievement.Unlock("hard_wave10")
    end
    if diff.id == "nightmare" then
        if wave >= 5  then Achievement.Unlock("nightmare_wave5") end
        if wave >= 10 then Achievement.Unlock("nightmare_wave10") end
    end

    -- 速通：5分钟内到达第10波
    if wave >= 10 and gameTime <= 300 then
        Achievement.Unlock("speedrun_wave10")
    end

    -- 地图变体通关（波次 >= 10 视为通关）
    if wave >= 10 then
        local MapVariant = require("battle.MapVariant")
        if MapVariant.active then
            Achievement.CheckVariantClear(MapVariant.active.id)
        end
    end
end

--- 炸弹清除敌人时检查
---@param bombKills number 本次炸弹击杀数
function Achievement.CheckBombKills(bombKills)
    if bombKills >= 20 then
        Achievement.Unlock("bomb_20_kills")
    end
end

--- 放弃广告宝箱时检查
function Achievement.CheckGiveUpGift()
    Achievement.Unlock("give_up_gift")
end

--- 精英怪击杀检查（每次击杀精英时调用）
function Achievement.CheckEliteKill()
    Achievement.stats.eliteKills = Achievement.stats.eliteKills + 1
    if Achievement.stats.eliteKills >= 10 then Achievement.Unlock("elite_kill_10") end
    if Achievement.stats.eliteKills >= 50 then Achievement.Unlock("elite_kill_50") end
    Achievement.Save()
end

--- Boss击杀检查
function Achievement.CheckBossKill()
    Achievement.stats.bossKills = Achievement.stats.bossKills + 1
    if Achievement.stats.bossKills >= 1  then Achievement.Unlock("boss_kill_1") end
    if Achievement.stats.bossKills >= 10 then Achievement.Unlock("boss_kill_10") end
    Achievement.Save()
end

--- 金币累计检查（在 AddMetaGold 时调用）
---@param amount number 本次新增金币
function Achievement.CheckGold(amount)
    Achievement.stats.totalGold = Achievement.stats.totalGold + amount
    if Achievement.stats.totalGold >= 1000  then Achievement.Unlock("gold_1000") end
    if Achievement.stats.totalGold >= 10000 then Achievement.Unlock("gold_10000") end
    -- 不在这里 Save，由 AddMetaGold 触发的保存流程即可
end

--- 每日挑战完成检查
function Achievement.CheckDailyDone()
    Achievement.stats.dailyDone = Achievement.stats.dailyDone + 1
    if Achievement.stats.dailyDone >= 1 then Achievement.Unlock("daily_1") end
    if Achievement.stats.dailyDone >= 5 then Achievement.Unlock("daily_5") end
    Achievement.Save()
end

--- 角色全部解锁检查
function Achievement.CheckAllCharsUnlocked()
    local SaveData = require("SaveData")
    local allUnlocked = true
    for _, ch in ipairs(Config.CHARACTERS) do
        if not SaveData.IsCharUnlocked(ch.id) then
            allUnlocked = false
            break
        end
    end
    if allUnlocked then
        Achievement.Unlock("all_chars_unlocked")
    end
end

--- 遗物升级检查
function Achievement.CheckRelicUpgrade()
    local SaveData = require("SaveData")
    local count = 0
    for _, lv in pairs(SaveData.relicLevels or {}) do
        if lv and lv > 0 then count = count + 1 end
    end
    if count >= 3 then
        Achievement.Unlock("relic_3")
    end
end

-- ── 图鉴 (33) ──

--- 图鉴发现检查（每次新发现时调用）
---@param discovered number 当前已发现总数
---@param total number 图鉴总条目数
function Achievement.CheckCodexDiscover(discovered, total)
    if discovered >= 10 then Achievement.Unlock("codex_10") end
    if discovered >= total and total > 0 then Achievement.Unlock("codex_all") end
end

-- ── 周挑战 (31) ──

--- 周挑战完成检查（每次完成周挑战战斗时调用）
function Achievement.CheckWeeklyDone()
    Achievement.stats.weeklyDone = Achievement.stats.weeklyDone + 1
    if Achievement.stats.weeklyDone >= 1 then Achievement.Unlock("weekly_1") end
    if Achievement.stats.weeklyDone >= 7 then Achievement.Unlock("weekly_7") end
    Achievement.Save()
end

-- ── 地图事件 (30) ──

--- 地图事件触发检查（每次事件被激活时调用）
---@param eventId string 事件类型 id（treasure/spring/merchant/poison/speed_zone/magnet_zone）
function Achievement.CheckMapEvent(eventId)
    if not Achievement.stats.eventTypes then Achievement.stats.eventTypes = {} end
    Achievement.stats.eventTypes[eventId] = true
    -- 宝箱成就单独由 CheckTreasureOpened 处理
    -- 检查是否触发了全部6种
    local ALL_EVENTS = {"treasure", "spring", "merchant", "poison", "speed_zone", "magnet_zone"}
    local allSeen = true
    for _, eid in ipairs(ALL_EVENTS) do
        if not Achievement.stats.eventTypes[eid] then
            allSeen = false
            break
        end
    end
    if allSeen then Achievement.Unlock("event_all_types") end
    Achievement.Save()
end

--- 宝箱开启检查（守卫全灭时调用）
function Achievement.CheckTreasureOpened()
    Achievement.Unlock("event_treasure")
end

-- ── 地图变体 (35) ──

--- 地图变体通关检查（胜利/达到一定波次时调用）
---@param variantId string 地图变体 id
function Achievement.CheckVariantClear(variantId)
    if not Achievement.stats.variantClears then Achievement.stats.variantClears = {} end
    Achievement.stats.variantClears[variantId] = true
    local ALL_VARIANTS = {"cyber", "grass", "cave", "sky"}
    local allCleared = true
    for _, vid in ipairs(ALL_VARIANTS) do
        if not Achievement.stats.variantClears[vid] then
            allCleared = false
            break
        end
    end
    if allCleared then Achievement.Unlock("variant_all") end
    Achievement.Save()
end

-- ── 符文共鸣 (37) ──

--- 符文共鸣激活检查（每次检测到共鸣时调用）
---@param resonanceId string 共鸣 id
function Achievement.CheckResonance(resonanceId)
    if not Achievement.stats.resonanceSeen then Achievement.stats.resonanceSeen = {} end
    if not Achievement.stats.resonanceSeen[resonanceId] then
        Achievement.stats.resonanceSeen[resonanceId] = true
        Achievement.Unlock("resonance_1")
        -- 检查是否全部激活过
        local ALL_RES = {"flame_rebirth", "phantom_storm", "iron_medic",
                         "shadow_fission", "thunder_loot", "overclock_perfect"}
        local allSeen = true
        for _, rid in ipairs(ALL_RES) do
            if not Achievement.stats.resonanceSeen[rid] then
                allSeen = false
                break
            end
        end
        if allSeen then Achievement.Unlock("resonance_all") end
        Achievement.Save()
    end
end

-- ============================================================================
-- 通知更新与渲染
-- ============================================================================

-- ── 滚动状态 ──
Achievement._scrollY = 0
Achievement._scrollVel = 0
Achievement._dragStartY = nil
Achievement._dragLastY = nil
Achievement._dragScrollStart = 0

function Achievement.HandleDragBegin(dy)
    Achievement._dragStartY = dy
    Achievement._dragLastY = dy
    Achievement._dragScrollStart = Achievement._scrollY
    Achievement._scrollVel = 0
end

function Achievement.HandleDragMove(dy)
    if Achievement._dragStartY then
        Achievement._scrollY = Achievement._dragScrollStart + (Achievement._dragStartY - dy)
        Achievement._scrollVel = (Achievement._dragLastY - dy) * 8
        Achievement._dragLastY = dy
    end
end

function Achievement.HandleDragEnd()
    Achievement._dragStartY = nil
    Achievement._dragLastY = nil
end

--- 更新通知计时器（在 HandleUpdate 中调用）
---@param dt number
function Achievement.Update(dt)
    local i = 1
    while i <= #Achievement.notifications do
        local n = Achievement.notifications[i]
        n.timer = n.timer - dt
        if n.timer <= 0 then
            table.remove(Achievement.notifications, i)
        else
            i = i + 1
        end
    end

    -- 滚动惯性
    if not Achievement._dragStartY then
        if math.abs(Achievement._scrollVel) > 0.5 then
            Achievement._scrollY = Achievement._scrollY + Achievement._scrollVel * dt
            Achievement._scrollVel = Achievement._scrollVel * 0.92
        else
            Achievement._scrollVel = 0
        end
        -- 边界回弹
        local rowH = 70
        local maxScroll = math.max(0, #Achievement.DEFS * rowH - 400)
        if Achievement._scrollY < 0 then
            Achievement._scrollY = Achievement._scrollY * 0.85
            Achievement._scrollVel = 0
        elseif Achievement._scrollY > maxScroll then
            Achievement._scrollY = maxScroll + (Achievement._scrollY - maxScroll) * 0.85
            Achievement._scrollVel = 0
        end
    end
end

--- 渲染成就解锁通知（叠在 HUD 之上）
---@param vg userdata NanoVG 上下文
---@param viewW number
---@param viewH number
---@param fontId number
function Achievement.RenderNotifications(vg, viewW, viewH, fontId)
    if #Achievement.notifications == 0 then return end

    nvgFontFaceId(vg, zpix)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local cx = viewW / 2

    for i, n in ipairs(Achievement.notifications) do
        -- 从顶部弹出动画
        local progress = 1 - (n.timer / NOTIFY_DURATION)
        local slideIn = math.min(1, progress * 5) -- 前 0.2 秒滑入
        local fadeOut = math.min(1, n.timer / 0.5) -- 最后 0.5 秒淡出

        local alpha = math.floor(230 * fadeOut)
        local baseY = 100 + (i - 1) * 60
        local y = baseY - (1 - slideIn) * 40

        -- 通知背景
        local boxW = 320
        local boxH = 48
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - boxW / 2, y - boxH / 2, boxW, boxH, 12)
        nvgFillColor(vg, nvgRGBA(40, 30, 70, math.floor(200 * fadeOut)))
        nvgFill(vg)

        -- 金色边框
        nvgStrokeColor(vg, nvgRGBA(255, 220, 80, alpha))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 图标
        nvgFontSize(vg, 24)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        nvgText(vg, cx - boxW / 2 + 30, y, n.icon)

        -- "成就解锁" 标签
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, alpha))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
        nvgText(vg, cx - boxW / 2 + 54, y - 2, "🏆 成就解锁")

        -- 成就名
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgText(vg, cx - boxW / 2 + 54, y + 2, n.name)

        -- 重置对齐
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
end

--- 渲染成就列表页面（独立全屏）
---@param vg userdata
---@param viewW number
---@param viewH number
---@param fontId number
function Achievement.RenderPage(vg, viewW, viewH, fontId)
    local bg = Config.COLORS.bg
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
    nvgFill(vg)

    local cx = viewW / 2
    local t = time.elapsedTime

    nvgFontFaceId(vg, zpix)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 标题
    nvgFontSize(vg, 36)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, cx, 60, "🏆 成就")

    -- 进度
    local unlocked = Achievement.GetUnlockedCount()
    local total = Achievement.GetTotalCount()
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 150))
    nvgText(vg, cx, 92, unlocked .. " / " .. total .. " 已解锁")

    -- 进度条
    local barW = 300
    local barH = 8
    local barX = cx - barW / 2
    local barY = 108
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 4)
    nvgFillColor(vg, nvgRGBA(40, 30, 60, 200))
    nvgFill(vg)

    if total > 0 then
        local ratio = unlocked / total
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * ratio, barH, 4)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
        nvgFill(vg)
    end

    -- 成就列表（带滚动）
    local startY = 140
    local rowH = 70
    local cardW = viewW - 60
    local cardX = 30
    local scrollY = Achievement._scrollY

    nvgSave(vg)
    nvgScissor(vg, 0, startY - 4, viewW, viewH - startY - 70)

    for i, def in ipairs(Achievement.DEFS) do
        local y = startY + (i - 1) * rowH - scrollY
        if y > viewH then break end  -- 超出底部不渲染
        if y + rowH < startY - 4 then goto continue end  -- 超出顶部跳过

        local isUnlocked = Achievement.IsUnlocked(def.id)

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, y, cardW, rowH - 8, 10)
        if isUnlocked then
            nvgFillColor(vg, nvgRGBA(40, 50, 30, 200))
        else
            nvgFillColor(vg, nvgRGBA(25, 20, 45, 200))
        end
        nvgFill(vg)

        -- 边框
        if isUnlocked then
            nvgStrokeColor(vg, nvgRGBA(100, 200, 80, 120))
        else
            nvgStrokeColor(vg, nvgRGBA(80, 70, 100, 80))
        end
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        local midY = y + (rowH - 8) / 2

        -- 图标
        nvgFontSize(vg, 28)
        if isUnlocked then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        else
            nvgFillColor(vg, nvgRGBA(100, 100, 120, 100))
        end
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, cardX + 34, midY, isUnlocked and def.icon or "🔒")

        -- 成就名
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
        nvgFontSize(vg, 17)
        if isUnlocked then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        else
            nvgFillColor(vg, nvgRGBA(160, 160, 180, 160))
        end
        nvgText(vg, cardX + 64, midY, def.name)

        -- 描述
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFontSize(vg, 13)
        if isUnlocked then
            nvgFillColor(vg, nvgRGBA(100, 200, 80, 200))
        else
            nvgFillColor(vg, nvgRGBA(140, 140, 160, 120))
        end
        nvgText(vg, cardX + 64, midY + 4, def.desc)

        -- 已解锁标记
        if isUnlocked then
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(100, 200, 80, 200))
            nvgText(vg, cardX + cardW - 16, midY, "✅")
        end
        ::continue::
    end

    nvgRestore(vg)  -- 恢复 scissor

    -- 返回按钮
    local backW = 200
    local backH = 48
    local backX = cx - backW / 2
    local backY = viewH - 80

    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, backX, backY, backW, backH, 12)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 15))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 200, 220, 120))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 200))
    nvgText(vg, cx, backY + backH / 2, "← 返回")
end

--- 返回成就页面返回按钮区域
---@param viewW number
---@param viewH number
---@return table {x, y, w, h}
function Achievement.GetBackButtonRect(viewW, viewH)
    local backW = 200
    local backH = 48
    return {
        x = viewW / 2 - backW / 2,
        y = viewH - 80,
        w = backW,
        h = backH,
    }
end

return Achievement
