--- ============================================================================
--- 周挑战赛季 - 7天规则轮换 + 赛季积分 + 赛季奖励
--- UTC 周一 00:00 为赛季起点，每天一个特殊规则
--- ============================================================================

local ok, cjson = pcall(require, "cjson")
if not ok then cjson = nil end

local Config = require("Config")
local SaveData = require("SaveData")

local WC = {}

-- ============================================================================
-- 赛季状态
-- ============================================================================
WC.active       = false        -- 当前是否在周挑战战斗中
WC.todayRule    = nil          -- 今日规则缓存
WC.seasonId     = ""           -- 赛季 ID (如 "2026W19")
WC.seasonDay    = 1            -- 今天是赛季第几天 (1-7)
WC.seasonPoints = 0            -- 本赛季累计积分
WC.dailyPlayed  = {}           -- { [dayIndex] = bestWave }  本赛季每日最佳
WC.lastSeasonReward = nil      -- 上赛季未领取的奖励

local SAVE_FILE = "weekly_challenge.json"
local CLOUD_KEY_WEEKLY = "wc_pts"

-- ============================================================================
-- 每日规则池（7个，按赛季日轮换）
-- ============================================================================
local DAILY_RULES = {
    {
        id    = "speed_frenzy",
        name  = "极速狂潮",
        icon  = "⚡",
        desc  = "一切加速！敌人更快，玩家也更快",
        mods  = { enemySpeedMul = 1.8, playerSpeedMul = 1.5 },
        color = { 255, 180, 50 },
    },
    {
        id    = "glass_cannon",
        name  = "玻璃大炮",
        icon  = "💎",
        desc  = "攻击力×3，但生命值只有1点",
        mods  = { playerDmgMul = 3.0, playerMaxHp = 1 },
        color = { 200, 100, 255 },
    },
    {
        id    = "swarm_tide",
        name  = "虫潮来袭",
        icon  = "🐛",
        desc  = "敌怪数量×3，但经验值也×2",
        mods  = { enemyCountMul = 3.0, expMul = 2.0 },
        color = { 100, 220, 80 },
    },
    {
        id    = "boss_rush",
        name  = "Boss连战",
        icon  = "👑",
        desc  = "每2波出Boss，Boss血量减半",
        mods  = { bossEveryN = 2, bossHpMul = 0.5 },
        color = { 255, 80, 80 },
    },
    {
        id    = "no_heal",
        name  = "铁人模式",
        icon  = "🩸",
        desc  = "红心掉落全部变为经验宝石",
        mods  = { noHeal = true },
        color = { 180, 50, 50 },
    },
    {
        id    = "mega_loot",
        name  = "宝箱雨",
        icon  = "🎁",
        desc  = "掉落率×4，但敌怪攻击力×2",
        mods  = { lootMul = 4.0, enemyAtkMul = 2.0 },
        color = { 50, 200, 255 },
    },
    {
        id    = "roulette",
        name  = "命运轮盘",
        icon  = "🎰",
        desc  = "每升级随机正负效果，波次奖励×2",
        mods  = { roulette = true, waveRewardMul = 2.0 },
        color = { 255, 200, 100 },
    },
}

-- ============================================================================
-- 积分阶梯奖励（每级金币 = 基础30 × 等级²）
-- Level 1: 30×1²=30  Level 2: 30×2²=120  Level 3: 30×3²=270
-- Level 4: 30×4²=480  Level 5: 30×5²=750
-- ============================================================================
local SEASON_REWARDS = {
    { points =  10, gold =  30, label = "新手冒险者",  icon = "🌱" },
    { points =  25, gold = 120, label = "勇敢战士",    icon = "⚔️" },
    { points =  50, gold = 270, label = "精英挑战者",  icon = "🏅" },
    { points =  80, gold = 480, label = "赛季之星",    icon = "⭐" },
    { points = 120, gold = 750, label = "传奇勇者",    icon = "👑" },
}

-- ============================================================================
-- 确定性 PRNG（同 DailyChallenge）
-- ============================================================================
local function CreateRNG(seed)
    local state = seed
    return function()
        state = (state * 1103 + 12345) % 65536
        return state
    end
end

-- ============================================================================
-- 赛季与日期计算
-- ============================================================================

--- 获取 UTC 当前时间的赛季信息
---@return string seasonId, number dayIndex (1-7), number weekNum
function WC.GetSeasonInfo()
    local utc = os.date("!*t")
    -- ISO 8601 周数（简化计算）
    local yday = utc.yday
    local wday = utc.wday  -- 1=Sun..7=Sat
    -- 调整为 Mon=1..Sun=7
    local isoWday = wday == 1 and 7 or (wday - 1)
    -- ISO week: (yday - isoWday + 10) / 7
    local weekNum = math.floor((yday - isoWday + 10) / 7)
    if weekNum < 1 then weekNum = 52 end
    if weekNum > 52 then weekNum = 1 end

    local seasonId = string.format("%dW%02d", utc.year, weekNum)
    local dayIndex = isoWday  -- 1=Mon..7=Sun

    return seasonId, dayIndex, weekNum
end

--- 获取赛季剩余天数
---@return number
function WC.GetDaysRemaining()
    local _, dayIndex = WC.GetSeasonInfo()
    return 7 - dayIndex
end

--- 获取赛季剩余时间文本
---@return string
function WC.GetTimeRemainingText()
    local days = WC.GetDaysRemaining()
    if days == 0 then
        return "今天是赛季最后一天！"
    else
        return "赛季剩余 " .. days .. " 天"
    end
end

-- ============================================================================
-- 今日规则
-- ============================================================================

--- 获取今日赛季规则
---@return table rule {id, name, icon, desc, mods, color}
function WC.GetTodayRule()
    if WC.todayRule then return WC.todayRule end

    local seasonId, dayIndex = WC.GetSeasonInfo()
    WC.seasonId = seasonId
    WC.seasonDay = dayIndex

    -- 用赛季种子 shuffle 规则顺序，确保每周不同
    local utc = os.date("!*t")
    local seed = utc.year * 100 + math.floor(utc.yday / 7)
    local rng = CreateRNG(seed)

    local indices = {}
    for i = 1, #DAILY_RULES do indices[i] = i end
    for i = #indices, 2, -1 do
        local j = (rng() % i) + 1
        indices[i], indices[j] = indices[j], indices[i]
    end

    local ruleIdx = indices[dayIndex]
    WC.todayRule = DAILY_RULES[ruleIdx]
    return WC.todayRule
end

--- 判断某修改器是否生效
---@param modId string
---@return any value  (true/number/nil)
function WC.GetMod(modId)
    if not WC.active then return nil end
    local rule = WC.todayRule
    if not rule then return nil end
    return rule.mods[modId]
end

--- 获取赛季的7天规则预览
---@return table[] { dayIndex, rule, isCurrent }
function WC.GetWeekPreview()
    local seasonId, currentDay = WC.GetSeasonInfo()
    local utc = os.date("!*t")
    local seed = utc.year * 100 + math.floor(utc.yday / 7)
    local rng = CreateRNG(seed)

    local indices = {}
    for i = 1, #DAILY_RULES do indices[i] = i end
    for i = #indices, 2, -1 do
        local j = (rng() % i) + 1
        indices[i], indices[j] = indices[j], indices[i]
    end

    local preview = {}
    local dayNames = { "周一", "周二", "周三", "周四", "周五", "周六", "周日" }
    for d = 1, 7 do
        local rule = DAILY_RULES[indices[d]]
        preview[d] = {
            dayIndex  = d,
            dayName   = dayNames[d],
            rule      = rule,
            isCurrent = (d == currentDay),
            bestWave  = WC.dailyPlayed[d] or 0,
        }
    end
    return preview
end

-- ============================================================================
-- 积分系统
-- ============================================================================

--- 完成一局挑战，计算积分
---@param wave number 达到的波次
---@return number pointsEarned, number totalPoints
function WC.RecordResult(wave)
    local _, dayIndex = WC.GetSeasonInfo()
    local prevBest = WC.dailyPlayed[dayIndex] or 0

    -- 只有超过当日最佳才获得额外积分
    local basePoints = wave  -- 基础积分 = 波次
    local bonusPoints = 0
    if wave > prevBest then
        bonusPoints = math.floor((wave - prevBest) * 0.5)
        WC.dailyPlayed[dayIndex] = wave
    end

    local earned = basePoints + bonusPoints
    WC.seasonPoints = WC.seasonPoints + earned
    WC.Save()

    return earned, WC.seasonPoints
end

--- 获取已达成的赛季奖励
---@return table[] reached, number totalGold
function WC.GetReachedRewards()
    local reached = {}
    local total = 0
    for _, r in ipairs(SEASON_REWARDS) do
        if WC.seasonPoints >= r.points then
            reached[#reached + 1] = r
            total = total + r.gold
        end
    end
    return reached, total
end

--- 获取下一个未达成的奖励
---@return table|nil nextReward, number pointsNeeded
function WC.GetNextReward()
    for _, r in ipairs(SEASON_REWARDS) do
        if WC.seasonPoints < r.points then
            return r, r.points - WC.seasonPoints
        end
    end
    return nil, 0
end

--- 获取赛季进度百分比(0~100)
---@return number
function WC.GetProgressPct()
    local maxPts = SEASON_REWARDS[#SEASON_REWARDS].points
    return math.min(100, math.floor(WC.seasonPoints / maxPts * 100))
end

-- ============================================================================
-- 排行榜 key
-- ============================================================================

--- 获取本赛季排行榜 key
---@return string
function WC.GetLeaderboardKey()
    local seasonId = WC.GetSeasonInfo()
    return "wc_pts_" .. seasonId
end

-- ============================================================================
-- 持久化
-- ============================================================================

function WC.Load()
    if not cjson then return end
    if not fileSystem:FileExists(SAVE_FILE) then return end
    local file = File(SAVE_FILE, FILE_READ)
    if not file:IsOpen() then return end
    local ok2, data = pcall(cjson.decode, file:ReadString())
    file:Close()
    if not ok2 or not data then return end

    local currentSeason = WC.GetSeasonInfo()
    if data.seasonId == currentSeason then
        -- 同赛季，恢复进度
        WC.seasonPoints = data.seasonPoints or 0
        WC.dailyPlayed  = data.dailyPlayed  or {}
    else
        -- 新赛季，计算上赛季奖励
        if data.seasonPoints and data.seasonPoints > 0 then
            local reached, totalGold = WC.GetReachedRewardsForPoints(data.seasonPoints)
            if totalGold > 0 then
                WC.lastSeasonReward = {
                    seasonId = data.seasonId,
                    points   = data.seasonPoints,
                    gold     = totalGold,
                    rewards  = reached,
                    claimed  = false,
                }
            end
        end
        WC.seasonPoints = 0
        WC.dailyPlayed  = {}
    end
    print("[WeeklyChallenge] Loaded: season=" .. currentSeason
        .. " pts=" .. WC.seasonPoints)
end

function WC.Save()
    if not cjson then return end
    local data = {
        seasonId     = WC.seasonId,
        seasonPoints = WC.seasonPoints,
        dailyPlayed  = WC.dailyPlayed,
    }
    local file = File(SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(data))
        file:Close()
    end
end

--- 用于计算历史赛季奖励(仅用积分)
function WC.GetReachedRewardsForPoints(pts)
    local reached = {}
    local total = 0
    for _, r in ipairs(SEASON_REWARDS) do
        if pts >= r.points then
            reached[#reached + 1] = r
            total = total + r.gold
        end
    end
    return reached, total
end

-- ============================================================================
-- 云端同步
-- ============================================================================

function WC.SyncToCloud()
    if not clientCloud then return end
    local key = WC.GetLeaderboardKey()
    clientCloud:SetInt(key, WC.seasonPoints, {
        ok = function()
            print("[WC] Cloud sync OK: " .. key .. "=" .. WC.seasonPoints)
        end,
        error = function(_, reason)
            print("[WC] Cloud sync fail: " .. tostring(reason))
        end,
    })
end

-- ============================================================================
-- 初始化 / 重置
-- ============================================================================

function WC.Init()
    WC.active = false
    WC.todayRule = nil
    WC.seasonPoints = 0
    WC.dailyPlayed  = {}
    WC.lastSeasonReward = nil

    local seasonId, dayIndex = WC.GetSeasonInfo()
    WC.seasonId  = seasonId
    WC.seasonDay = dayIndex

    WC.GetTodayRule()
    WC.Load()
end

function WC.Reset()
    WC.active = false
end

--- 领取上赛季奖励
---@return number gold 领取的金币数
function WC.ClaimLastSeasonReward()
    if not WC.lastSeasonReward or WC.lastSeasonReward.claimed then
        return 0
    end
    local gold = WC.lastSeasonReward.gold
    WC.lastSeasonReward.claimed = true
    SaveData.metaGold = SaveData.metaGold + gold
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    WC.Save()
    WC.SyncToCloud()
    return gold
end

-- ============================================================================
-- 渲染：赛季信息页面
-- ============================================================================

--- 渲染赛季详情页面（在 main.lua 的 STATE_WEEKLY 中调用）
---@param vg any NanoVG context
---@param viewW number
---@param viewH number
---@param fontId number
function WC.RenderPage(vg, viewW, viewH, fontId)
    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(8, 8, 20, 250))
    nvgFill(vg)

    nvgFontFaceId(vg, zpix)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 标题
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(255, 200, 80, 255))
    nvgText(vg, viewW / 2, 40, "🏆 周挑战赛季")

    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 160))
    nvgText(vg, viewW / 2, 62, WC.seasonId .. " · " .. WC.GetTimeRemainingText())

    -- 赛季积分
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgText(vg, viewW / 2, 92, "赛季积分: " .. WC.seasonPoints)

    -- 进度条
    local barW = viewW - 60
    local barX = 30
    local barY = 108
    local barH = 10
    local pct = WC.GetProgressPct() / 100
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 5)
    nvgFillColor(vg, nvgRGBA(40, 40, 60, 200))
    nvgFill(vg)
    if pct > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * pct, barH, 5)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 220))
        nvgFill(vg)
    end

    -- 奖励节点
    nvgFontSize(vg, 10)
    for _, r in ipairs(SEASON_REWARDS) do
        local rx = barX + barW * (r.points / SEASON_REWARDS[#SEASON_REWARDS].points)
        local reached = WC.seasonPoints >= r.points
        nvgFillColor(vg, reached and nvgRGBA(255, 220, 80, 255) or nvgRGBA(120, 120, 140, 160))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgText(vg, rx, barY + barH + 3, r.icon)
    end

    -- 下一奖励提示
    local nextR, needed = WC.GetNextReward()
    if nextR then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, 180))
        nvgText(vg, viewW / 2, barY + barH + 24,
            "下一奖励: " .. nextR.icon .. " " .. nextR.label
            .. " (还需 " .. needed .. " 积分)")
    else
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
        nvgText(vg, viewW / 2, barY + barH + 24, "🎉 所有赛季奖励已达成！")
    end

    -- ── 7天日程表 ──
    local schedY = barY + barH + 48
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 200))
    nvgText(vg, viewW / 2, schedY, "📅 本周日程")

    local preview = WC.GetWeekPreview()
    local cardW = viewW - 40
    local cardH = 50
    local cardGap = 6
    local startY = schedY + 20

    for i, day in ipairs(preview) do
        local cy = startY + (i - 1) * (cardH + cardGap)
        local r, g, b = day.rule.color[1], day.rule.color[2], day.rule.color[3]

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 20, cy, cardW, cardH, 8)
        if day.isCurrent then
            nvgFillColor(vg, nvgRGBA(r, g, b, 40))
        else
            nvgFillColor(vg, nvgRGBA(20, 20, 35, 180))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(r, g, b, day.isCurrent and 200 or 60))
        nvgStrokeWidth(vg, day.isCurrent and 2 or 1)
        nvgStroke(vg)

        -- 日期
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, day.isCurrent and nvgRGBA(255, 255, 255, 255) or nvgRGBA(150, 150, 170, 180))
        nvgText(vg, 30, cy + 16, day.dayName)

        -- 规则
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(r, g, b, day.isCurrent and 255 or 150))
        nvgText(vg, 72, cy + 16, day.rule.icon .. " " .. day.rule.name)

        -- 描述
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, day.isCurrent and 180 or 100))
        nvgText(vg, 72, cy + 35, day.rule.desc)

        -- 最佳波次
        if day.bestWave > 0 then
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 220, 80, 200))
            nvgText(vg, cardW + 10, cy + cardH / 2, "W" .. day.bestWave)
        elseif day.isCurrent then
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(100, 200, 255, 180))
            nvgText(vg, cardW + 10, cy + cardH / 2, "挑战 →")
        end
    end

    -- ── 赛季奖励列表 ──
    local rewardY = startY + 7 * (cardH + cardGap) + 12
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 200))
    nvgText(vg, viewW / 2, rewardY, "🎁 赛季奖励")

    rewardY = rewardY + 22
    for _, r in ipairs(SEASON_REWARDS) do
        local reached = WC.seasonPoints >= r.points
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 30, rewardY, cardW, 32, 6)
        nvgFillColor(vg, reached and nvgRGBA(40, 50, 20, 180) or nvgRGBA(20, 20, 30, 150))
        nvgFill(vg)

        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, reached and nvgRGBA(255, 220, 80, 255) or nvgRGBA(150, 150, 170, 150))
        nvgText(vg, 40, rewardY + 16,
            r.icon .. " " .. r.label .. " (" .. r.points .. "积分)")

        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, reached and nvgRGBA(255, 200, 50, 255) or nvgRGBA(120, 120, 140, 130))
        nvgText(vg, cardW + 10, rewardY + 16,
            (reached and "✅ " or "") .. "🪙" .. r.gold)

        rewardY = rewardY + 38
    end

    -- ── 上赛季奖励领取提示 ──
    if WC.lastSeasonReward and not WC.lastSeasonReward.claimed then
        local claimY = rewardY + 12
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 30, claimY, cardW, 46, 10)
        nvgFillColor(vg, nvgRGBA(80, 60, 10, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 200))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, viewW / 2, claimY + 15,
            "📦 上赛季奖励: " .. WC.lastSeasonReward.gold .. " 金币")
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, viewW / 2, claimY + 33, "[ 点击领取 ]")

        WC._claimBtnRect = { x = 30, y = claimY, w = cardW, h = 46 }
    else
        WC._claimBtnRect = nil
    end

    -- 返回按钮
    local backW = 120
    local backH = 38
    local backX = (viewW - backW) / 2
    local backY = viewH - 60
    nvgBeginPath(vg)
    nvgRoundedRect(vg, backX, backY, backW, backH, 8)
    nvgFillColor(vg, nvgRGBA(40, 40, 60, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(150, 150, 180, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 220))
    nvgText(vg, viewW / 2, backY + backH / 2, "← 返回")

    WC._backBtnRect = { x = backX, y = backY, w = backW, h = backH }
end

--- 页面触控处理
---@param dx number
---@param dy number
---@param viewW number
---@param viewH number
---@return string|nil action  "back" | "claim" | "start" | nil
function WC.HandleTouch(dx, dy, viewW, viewH)
    -- 返回按钮
    if WC._backBtnRect then
        local b = WC._backBtnRect
        if dx >= b.x and dx <= b.x + b.w and dy >= b.y and dy <= b.y + b.h then
            return "back"
        end
    end

    -- 领取奖励
    if WC._claimBtnRect then
        local b = WC._claimBtnRect
        if dx >= b.x and dx <= b.x + b.w and dy >= b.y and dy <= b.y + b.h then
            return "claim"
        end
    end

    -- 点击今日规则卡片 → 开始挑战
    local barH = 10
    local schedY = 108 + barH + 48 + 20  -- 与 RenderPage 保持一致
    local cardH = 50
    local cardGap = 6
    local preview = WC.GetWeekPreview()
    for i, day in ipairs(preview) do
        if day.isCurrent then
            local cy = schedY + (i - 1) * (cardH + cardGap)
            if dx >= 20 and dx <= viewW - 20 and dy >= cy and dy <= cy + cardH then
                return "start"
            end
        end
    end

    return nil
end

-- ============================================================================
-- 滚动支持（页面可能超出屏幕，使用 main.lua 的全局滚动即可）
-- ============================================================================
WC.scrollY    = 0
WC.scrollVel  = 0
WC.isDragging = false
WC.lastDragY  = 0

function WC.HandleDragBegin(dy)
    WC.isDragging = true
    WC.lastDragY  = dy
    WC.scrollVel  = 0
end

function WC.HandleDragMove(deltaY)
    if not WC.isDragging then return end
    WC.scrollY = WC.scrollY + deltaY
end

function WC.HandleDragEnd()
    WC.isDragging = false
end

function WC.UpdateScroll(dt)
    if not WC.isDragging then
        WC.scrollY = WC.scrollY + WC.scrollVel * dt
        WC.scrollVel = WC.scrollVel * 0.92

        -- 弹回
        local maxScroll = 0
        local minScroll = -400  -- 大概页面高度溢出量
        if WC.scrollY > maxScroll then
            WC.scrollY = WC.scrollY + (maxScroll - WC.scrollY) * 0.15
        elseif WC.scrollY < minScroll then
            WC.scrollY = WC.scrollY + (minScroll - WC.scrollY) * 0.15
        end
    end
end

function WC.ResetPageState()
    WC.scrollY   = 0
    WC.scrollVel = 0
    WC.isDragging = false
end

return WC
