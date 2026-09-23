--- ============================================================================
--- Emoji幸存者 - 客户端主逻辑
--- NanoVG 直接渲染 + VirtualControls 摇杆
--- ============================================================================

require "urhox-libs.UI.VirtualControls"

---@diagnostic disable-next-line: undefined-global
local sdk = sdk  -- 引擎运行时全局 SDK 接口
---@diagnostic disable-next-line: undefined-global
local lobby = lobby  -- 引擎运行时全局 lobby 接口

local Config = require("Config")
local BattleScene = require("battle.BattleScene")
local Player = require("battle.Player")
local Wave = require("battle.Wave")
local Skill = require("battle.Skill")
local Loot = require("battle.Loot")
local Enemy = require("battle.Enemy")
local EnemyBullet = require("battle.EnemyBullet")
local HUD = require("ui.HUD")
local SkillSelect = require("ui.SkillSelect")
local DamageNumber = require("ui.DamageNumber")
local GiftAd = require("ui.GiftAd")
local RelicShop = require("ui.RelicShop")
local TotemShop = require("ui.TotemShop")
local RuneShop  = require("ui.RuneShop")
local SkinShop  = require("ui.SkinShop")
local RelicSystem = require("meta.RelicSystem")
local TotemSystem = require("meta.TotemSystem")
local RuneSystem  = require("meta.RuneSystem")
local SkinSystem  = require("meta.SkinSystem")
local Particle = require("fx.Particle")
local Glow = require("fx.Glow")
local I18n = require("utils.I18n")
local PerfQuality = require("utils.PerfQuality")
local GameAudio = require("fx.GameAudio")
local SaveData = require("SaveData")
local Achievement = require("Achievement")
local Codex = require("meta.Codex")
local DailyChallenge = require("meta.DailyChallenge")
local WeeklyChallenge = require("meta.WeeklyChallenge")
local MockCloud = require("MockCloud")
local Tombstone = require("social.Tombstone")
local FPSMonitor = require("utils.FPSMonitor")
local GameMode = require("GameMode")
local RechargeShop = require("ui.RechargeShop")

local ClientMain = {}

-- ============================================================================
-- GC 调优：降低暂停率，增大步进倍率，减少单次 GC 停顿
-- ============================================================================
collectgarbage("setpause", 110)       -- 内存增长 10% 即触发（默认200太懒）
collectgarbage("setstepmul", 200)     -- 步进倍率加大（默认200，保持）

-- ============================================================================
-- 全局变量
-- ============================================================================

---@type userdata NanoVG 上下文
local vg = nil
---@type number 字体 ID
local fontId = -1
---@type number zpix 像素字体 ID（全局，供所有模块使用）
zpix = -1

-- 摇杆
local joystick = nil
local moveX, moveY = 0, 0

-- 设计分辨率（竖屏）
local DESIGN_W <const> = Config.DESIGN_W
local DESIGN_H <const> = Config.DESIGN_H

-- 屏幕缩放
local scaleX = 1
local scaleY = 1
local scale = 1
local offsetX = 0
local offsetY = 0
local physW = 0
local physH = 0

-- 游戏状态
local STATE_TITLE = 0
local STATE_CHAR_SELECT = 3
local STATE_PLAYING = 1
local STATE_OVER = 2
local STATE_NICKNAME = 4
local STATE_LEADERBOARD = 5
local STATE_ACHIEVEMENT = 6
local STATE_RELIC_SHOP  = 7
local STATE_TOTEM_SHOP  = 8
local STATE_RUNE_SHOP   = 9
local STATE_SKIN_SHOP   = 10
local STATE_CODEX       = 11
local STATE_WEEKLY      = 12

-- ============================================================================
-- 调试日志窗口（Tab+Q 切换）
-- ============================================================================
local debugLogEnabled = false          -- 是否显示日志窗口
local debugLogLines = {}               -- 日志缓冲区
local DEBUG_LOG_MAX = 60               -- 最多保留行数

-- 拦截 print，把 [SaveData] 相关日志捕获到缓冲区
local _origPrint = print
---@diagnostic disable-next-line: lowercase-global
function print(...)
    _origPrint(...)  -- 保留原始输出
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local line = table.concat(parts, "\t")
    if line:find("%[SaveData%]") or line:find("%[TotemSystem%]") or line:find("%[Cloud%]") then
        debugLogLines[#debugLogLines + 1] = line
        -- 超出上限时批量裁剪（避免每次 O(n) 的 table.remove(1)）
        if #debugLogLines > DEBUG_LOG_MAX + 20 then
            local newLines = {}
            for di = #debugLogLines - DEBUG_LOG_MAX + 1, #debugLogLines do
                newLines[#newLines + 1] = debugLogLines[di]
            end
            debugLogLines = newLines
        end
    end
end

-- 作弊：Tab+E 获得200万经验

-- 游戏状态（全局变量）
gameState = STATE_TITLE
gameOverVictory = false
gameOverShowTime = 0  -- 防止误触立即关闭结算界面
repNotifyTime = -999  -- 评价解锁按钮点击后的通知计时器
gameOverStats = nil
hasUsedRevive = false       -- 是否已使用广告复活（每局最多一次）
local _battleResumeCheckFrames = 0 -- 天赋关闭后的完整战斗恢复检查窗口

-- 遗言输入
local tombLastWords = ""          -- 玩家自定义遗言文本
local tombEditMode = false        -- 是否处于遗言键盘输入模式


-- 标题页点击闪光特效（必须在 HandleUpdate 之前声明）
local titleFlash = 0.0
local titleFlashX, titleFlashY = DESIGN_W / 2, DESIGN_H / 2

-- 角色选择
local selectedCharId = "cat"    -- 当前选中的角色 ID
local selectedCharIdx = 1       -- 当前高亮索引（1-based）

-- 昵称设置
local tempNickname = ""         -- 暂存的随机昵称
local nickEditMode = false      -- 是否处于键盘输入模式
local lastHighScoreRank = nil   -- 上次游戏结束的高分排名

-- 网络排行榜
local leaderboardData = nil         -- 缓存的排行榜数据 { {rank, nickname, wave, kills, userId}, ... }
local leaderboardLoading = false    -- 是否正在加载
local leaderboardLoadingMore = false -- 是否正在加载更多
local leaderboardError = nil        -- 加载错误信息
local leaderboardTotal = 0          -- 已加载总条数
local leaderboardHasMore = true     -- 是否还有更多数据
local lbScrollY = 0                 -- 排行榜滚动偏移（像素）
local lbScrollVel = 0               -- 滚动惯性速度
local lbDragStartY = nil            -- 触摸拖动起始Y
local lbDragLastY = nil             -- 上一帧拖动Y
local lbDragScrollStart = 0         -- 拖动开始时的scrollY
local LB_PAGE_SIZE = 100            -- 每页加载条数
local LB_MAX_ENTRIES = 1000         -- 最多加载条数
local myCloudBestWave = 0           -- 我的云端最高波次

-- 云端排行榜 key（clientCloud iscores）
local LB_KEY_KILLS = "best_kills"  -- 击杀数排名
local LB_KEY_WAVE  = "best_wave"   -- 最大波次排名

-- 排行榜标签页
local LB_TAB_WAVE = 1               -- 波次排名
local LB_TAB_KILLS = 2              -- 击杀排名
local LB_TAB_DAILY = 3              -- 每日挑战排名
local lbCurrentTab = LB_TAB_WAVE    -- 当前标签
local lbTabBtn1 = { x = 0, y = 0, w = 0, h = 0 }  -- 波次标签按钮区域
local lbTabBtn2 = { x = 0, y = 0, w = 0, h = 0 }  -- 击杀标签按钮区域
local lbTabBtn3 = { x = 0, y = 0, w = 0, h = 0 }  -- 每日挑战标签按钮区域

-- ============================================================================
-- 摇杆位置设置
-- ============================================================================

--- 根据位置选项更新摇杆的 position/alignment
---@param pos string "left" | "center" | "right"
function ApplyJoystickPosition(pos)
    if not joystick then return end
    if pos == "left" then
        joystick.position = Vector2(140, -200)
        joystick.alignment = { HA_LEFT, VA_BOTTOM }
    elseif pos == "right" then
        joystick.position = Vector2(-140, -200)
        joystick.alignment = { HA_RIGHT, VA_BOTTOM }
    else -- center
        joystick.position = Vector2(0, -200)
        joystick.alignment = { HA_CENTER, VA_BOTTOM }
    end
end

-- ============================================================================
-- 云端工具
-- ============================================================================

--- 启动时从排行榜 iscore 拉取自己的最高波次，同步到 SaveData
--- 确保遗物/图腾解锁门槛以排行榜记录为准（跨设备一致）
local function LoadOwnCloudBestWave()
    if GameMode.IsOffline() then return end
    if not clientCloud then return end
    clientCloud:BatchGet()
        :Key(LB_KEY_WAVE)
        :Fetch({
            ok = function(values, iscores)
                local wave = iscores[LB_KEY_WAVE] or 0
                if wave > 0 then
                    myCloudBestWave = wave
                    -- 取排行榜记录与本地 kv 的较大值，写回 SaveData
                    SaveData.UpdateHighestWave(wave)
                    print("[Cloud] 排行榜最高波次同步: " .. wave)
                end
            end,
            error = function(code, reason)
                print("[Cloud] 拉取排行榜波次失败: " .. tostring(reason))
            end
        })
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function ClientMain.Start(opts)
    opts = opts or {}
    if opts.offline then
        GameMode.SetOffline(true)
    end

    graphics.windowTitle = "Emoji幸存者"

    -- 预览环境 Mock（真机有 clientCloud 时自动跳过）
    MockCloud.Install()

    -- 创建游戏 NanoVG 上下文
    vg = nvgCreate(1)
    if vg == nil then
        print("ERROR: Failed to create NanoVG context")
        return
    end

    -- 加载字体
    fontId = nvgCreateFont(vg, "main", "Fonts/MiSans-Regular.ttf")
    if fontId == -1 then
        print("ERROR: Failed to load font")
    end

    -- 加载 zpix 像素字体（伤害跳字 + HUD 数值）
    local zpixFontId = nvgCreateFont(vg, "zpix", "Fonts/zpix.ttf")
    if zpixFontId == -1 then
        print("ERROR: Failed to load zpix font")
        zpix = fontId  -- fallback
    else
        DamageNumber.fontId = zpixFontId
        HUD.zpixFontId = zpixFontId
        zpix = zpixFontId
    end

    -- 初始化虚拟控制（竖屏设计分辨率）
    VirtualControls.Initialize(DESIGN_W, DESIGN_H)

    -- 加载用户设置（摇杆位置等）
    HUD.LoadSettings()

    -- 创建摇杆（默认居中，根据设置调整）
    joystick = VirtualControls.CreateJoystick({
        position = Vector2(0, -200),
        alignment = { HA_CENTER, VA_BOTTOM },
        radius = 70,
        knobRadius = 32,
        alwaysShow = true,
    })
    -- 游戏以标题界面启动，立即隐藏摇杆；HandleUpdate 中按 gameState 实时同步
    joystick.visible = false
    joystick:_updateShouldShow()
    ApplyJoystickPosition(HUD.joystickPos)

    -- 计算屏幕缩放
    UpdateScreenMetrics()

    -- 初始化存档系统
    SaveData.Init()

    -- 从云端拉取局外养成数据（异步，优先云端）
    -- 昵称判断延迟到云端回调：云端有昵称则跳过起名
    SaveData.LoadMetaFromCloud(function()
        if SaveData.NeedsNickname() then
            tempNickname = SaveData.GenerateNickname()
            gameState = STATE_NICKNAME
        else
            gameState = STATE_TITLE
        end
    end)

    -- 本地有昵称时先进标题（云端回调可能覆盖）
    if not SaveData.NeedsNickname() then
        gameState = STATE_TITLE
    end

    -- 从排行榜 iscore 同步自己的最高波次（用于遗物/图腾解锁判断）
    LoadOwnCloudBestWave()

    -- 初始化成就系统
    Achievement.Init()

    -- 初始化图鉴收集册
    Codex.Init()

    -- 初始化周挑战赛季
    WeeklyChallenge.Init()

    -- 初始化音频
    GameAudio.Init()
    GameAudio.PlayBGM()

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("TextInput", "HandleTextInput")

    if IsNetworkMode and IsNetworkMode() and not GameMode.IsOffline() then
        local okNet, ClientNet = pcall(require, "network.Client")
        if okNet and ClientNet and ClientNet.Start then
            ClientNet.Start()
        else
            print("[ClientMain] 网络层启动失败: " .. tostring(ClientNet))
        end
    end

    print("=== Emoji幸存者 ===")
    print("[ClientMain] offline=" .. tostring(GameMode.IsOffline())
        .. " networkMode=" .. tostring(IsNetworkMode and IsNetworkMode() or false))
end

function Start()
    ClientMain.Start()
end

function ClientMain.Stop()
    pcall(function()
        local ClientNet = require("network.Client")
        if ClientNet.Stop then ClientNet.Stop() end
    end)
    pcall(UnsubscribeFromAllEvents)
    pcall(VirtualControls.Shutdown)
    if vg then
        nvgDelete(vg)
        vg = nil
    end
    print("[ClientMain] Stop")
end

function Stop()
    ClientMain.Stop()
end

-- ============================================================================
-- 屏幕适配
-- ============================================================================

function UpdateScreenMetrics()
    physW = graphics:GetWidth()
    physH = graphics:GetHeight()

    -- 按短边缩放，保证设计分辨率内容完整显示（letterbox）
    scaleX = physW / DESIGN_W
    scaleY = physH / DESIGN_H
    scale = math.min(scaleX, scaleY)

    offsetX = (physW - DESIGN_W * scale) / 2
    offsetY = (physH - DESIGN_H * scale) / 2
end

--- 将屏幕物理坐标转为设计坐标
local function ScreenToDesign(sx, sy)
    local dx = (sx - offsetX) / scale
    local dy = (sy - offsetY) / scale
    return dx, dy
end

-- ============================================================================
-- 游戏状态管理
-- ============================================================================

-- ============================================================================
-- 云排行榜
-- ============================================================================

--- 上传成绩到云端两个排行榜（波次 + 击杀，各自独立比较更新）
local function UploadCloudScores(wave, kills)
    if GameMode.IsOffline() then return end
    if not clientCloud then return end
    -- 批量查询当前云端记录
    clientCloud:BatchGet()
        :Key(LB_KEY_WAVE)
        :Key(LB_KEY_KILLS)
        :Fetch({
            ok = function(values, iscores)
                local cloudWave = iscores[LB_KEY_WAVE] or 0
                local cloudKills = iscores[LB_KEY_KILLS] or 0
                local needUpdate = false
                local batch = clientCloud:BatchSet()

                if wave > cloudWave then
                    batch:SetInt(LB_KEY_WAVE, wave)
                    needUpdate = true
                end
                if kills > cloudKills then
                    batch:SetInt(LB_KEY_KILLS, kills)
                    needUpdate = true
                end

                if needUpdate then
                    batch:Save("更新排行榜", {
                        ok = function()
                            if wave > cloudWave then myCloudBestWave = wave end
                            print("[Cloud] 排行榜更新: wave=" .. wave .. "(云端" .. cloudWave .. ") kills=" .. kills .. "(云端" .. cloudKills .. ")")
                        end,
                        error = function(code, reason)
                            print("[Cloud] 上传失败: " .. tostring(reason))
                        end
                    })
                else
                    print("[Cloud] 无需更新: wave=" .. wave .. " kills=" .. kills)
                end
            end,
            error = function(code, reason)
                -- 查询失败，直接尝试上传两个
                print("[Cloud] 查询失败，直接上传: " .. tostring(reason))
                clientCloud:BatchSet()
                    :SetInt(LB_KEY_WAVE, wave)
                    :SetInt(LB_KEY_KILLS, kills)
                    :Save("更新排行榜")
            end
        })
end

--- 加载网络排行榜数据（支持分页）
---@param loadMore boolean|nil 是否加载更多（追加模式）
local function LoadLeaderboard(loadMore)
    if GameMode.IsOffline() or not clientCloud then
        leaderboardError = "联网不可用"
        leaderboardLoading = false
        leaderboardLoadingMore = false
        return
    end
    if loadMore then
        if leaderboardLoadingMore or not leaderboardHasMore then return end
        leaderboardLoadingMore = true
    else
        -- 首次加载，重置所有状态
        leaderboardLoading = true
        leaderboardError = nil
        leaderboardData = nil
        leaderboardTotal = 0
        leaderboardHasMore = true
        lbScrollY = 0
        lbScrollVel = 0
    end

    local startIdx = leaderboardTotal
    local count = math.min(LB_PAGE_SIZE, LB_MAX_ENTRIES - startIdx)
    if count <= 0 then
        leaderboardHasMore = false
        leaderboardLoading = false
        leaderboardLoadingMore = false
        return
    end

    -- 根据当前标签页选择排序 key
    local sortKey, otherKey
    if lbCurrentTab == LB_TAB_DAILY then
        sortKey = DailyChallenge.GetLeaderboardKey()
        otherKey = LB_KEY_KILLS
    elseif lbCurrentTab == LB_TAB_KILLS then
        sortKey = LB_KEY_KILLS
        otherKey = LB_KEY_WAVE
    else
        sortKey = LB_KEY_WAVE
        otherKey = LB_KEY_KILLS
    end

    clientCloud:GetRankList(sortKey, startIdx, count, {
        ok = function(rankList)
            local entries = {}
            local userIds = {}
            for i, item in ipairs(rankList) do
                table.insert(entries, {
                    rank = startIdx + i,
                    userId = item.player,
                    wave = item.iscore[LB_KEY_WAVE] or 0,
                    kills = item.iscore[LB_KEY_KILLS] or 0,
                    nickname = "...",
                    isMe = (lobby and lobby:GetMyUserId() and item.player == lobby:GetMyUserId()),
                })
                table.insert(userIds, item.player)
            end

            -- 判断是否还有更多
            if #rankList < count then
                leaderboardHasMore = false
            end
            if startIdx + #rankList >= LB_MAX_ENTRIES then
                leaderboardHasMore = false
            end

            if #userIds == 0 then
                if not loadMore then leaderboardData = {} end
                leaderboardLoading = false
                leaderboardLoadingMore = false
                return
            end

            -- 查询昵称（GetUserNickname 可能在预览环境不存在）
            if type(GetUserNickname) == "function" then
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do
                            map[info.userId] = info.nickname or ""
                        end
                        for _, entry in ipairs(entries) do
                            entry.nickname = map[entry.userId] or "玩家"
                        end
                        if loadMore and leaderboardData then
                            for _, e in ipairs(entries) do
                                table.insert(leaderboardData, e)
                            end
                        else
                            leaderboardData = entries
                        end
                        leaderboardTotal = #leaderboardData
                        leaderboardLoading = false
                        leaderboardLoadingMore = false
                    end,
                    onError = function(errorCode)
                        for _, entry in ipairs(entries) do
                            entry.nickname = "玩家"
                        end
                        if loadMore and leaderboardData then
                            for _, e in ipairs(entries) do
                                table.insert(leaderboardData, e)
                            end
                        else
                            leaderboardData = entries
                        end
                        leaderboardTotal = #leaderboardData
                        leaderboardLoading = false
                        leaderboardLoadingMore = false
                    end
                })
            else
                -- 预览环境无昵称查询，直接用默认名
                for _, entry in ipairs(entries) do
                    entry.nickname = "玩家"
                end
                if loadMore and leaderboardData then
                    for _, e in ipairs(entries) do
                        table.insert(leaderboardData, e)
                    end
                else
                    leaderboardData = entries
                end
                leaderboardTotal = #leaderboardData
                leaderboardLoading = false
                leaderboardLoadingMore = false
            end
        end,
        error = function(code, reason)
            if not loadMore then
                leaderboardError = "加载失败"
            end
            leaderboardLoading = false
            leaderboardLoadingMore = false
            print("[Cloud] 排行榜加载失败: code=" .. tostring(code) .. " reason=" .. tostring(reason))
        end
    }, otherKey)
end

--- 配置战斗回调（StartBattle 和 ResumeBattle 共用）
local function SetupBattleCallbacks()
    -- 升级回调
    BattleScene.onLevelUp = function(choices)
        SkillSelect.Show(choices, function(index)
            BattleScene.SelectSkill(index)
            -- 选择回调完成后再次校验：普通天赋选择必须回到完整战斗态。
            -- 如果触发终极奖励，终极弹窗仍可见，继续保持阻塞是正确行为。
            if not SkillSelect.visible and not SkillSelect.ultimateVisible and not GiftAd.visible then
                BattleScene.state = BattleScene.STATE_PLAYING
                _battleResumeCheckFrames = 8
            end
        end, function()
            local previousIds = {}
            for _, choice in ipairs(BattleScene.skillChoices) do
                previousIds[choice.def.id] = true
            end

            local refreshed = BattleScene.skillChoices
            for _ = 1, 6 do
                local candidate = Skill.RandomChoices(Player.skills, Player.charId)
                refreshed = candidate
                local hasDifferentChoice = false
                for _, choice in ipairs(candidate) do
                    if not previousIds[choice.def.id] then
                        hasDifferentChoice = true
                        break
                    end
                end
                if hasDifferentChoice then break end
            end

            BattleScene.skillChoices = refreshed
            return refreshed
        end)
    end

    -- 游戏结束回调
    BattleScene.onGameOver = function(isVictory, stats)
        gameState = STATE_OVER
        gameOverVictory = isVictory
        gameOverStats = stats
        gameOverShowTime = time.elapsedTime

        -- 删除游戏存档（游戏已结束）
        SaveData.DeleteSave()

        -- 记录高分 + 更新历史最高波次（用于商店解锁判定）
        lastHighScoreRank = SaveData.AddHighScore(
            stats.wave, stats.kills, Player.charId, stats.timeStr, stats.level
        )
        SaveData.UpdateHighestWave(stats.wave)

        -- 上传云端排行榜
        UploadCloudScores(stats.wave, stats.kills)

        -- 墓碑遗言：延迟到离开结算画面时上传（等待玩家输入自定义遗言）
        -- 初始化遗言输入状态
        if not isVictory then
            tombLastWords = ""
            tombEditMode = false
        end

        -- 每日挑战：计算奖励 + 上传排行榜
        if DailyChallenge.active then
            -- 1) 波次奖励（立即发放）
            local dcWaveGold, dcTiers = DailyChallenge.CalcWaveReward(stats.wave)
            if dcWaveGold > 0 then
                SaveData.AddMetaGold(dcWaveGold)
                print("[DailyReward] 波次奖励: +" .. dcWaveGold .. " 金币")
            end
            -- 保存奖励信息供 HUD 展示
            DailyChallenge.lastReward = {
                waveGold = dcWaveGold,
                tiers    = dcTiers,
                rankBonus = nil,  -- 异步回调中填充
            }

            -- 2) 上传排行榜 + 排名奖励
            if clientCloud then
                local dcKey = DailyChallenge.GetLeaderboardKey()
                local dcDateKey = DailyChallenge.GetTodayConfig().dateKey
                local dcWave = stats.wave
                clientCloud:BatchSet()
                    :SetInt(dcKey, dcWave)
                    :Save("上传每日挑战", {
                        ok = function()
                            print("[Cloud] 每日挑战上传: " .. dcKey .. "=" .. dcWave)
                            -- 查询排行榜 Top3，判断是否进入名人堂 + 发放排名奖励
                            clientCloud:GetRankList(dcKey, 0, 3, {
                                ok = function(rankList)
                                    if not rankList then return end
                                    local myNick = SaveData.nickname or "???"
                                    for i, entry in ipairs(rankList) do
                                        if i <= 3 and entry.nickname == myNick then
                                            SaveData.AddToHallOfFame(dcDateKey, i, myNick, dcWave)
                                            print("[HallOfFame] 进入名人堂! rank=" .. i)
                                            -- 排名奖励
                                            local rb = DailyChallenge.GetRankBonus(i)
                                            if rb then
                                                SaveData.AddMetaGold(rb.gold)
                                                print("[DailyReward] 排名奖励: " .. rb.label .. " +" .. rb.gold)
                                                if DailyChallenge.lastReward then
                                                    DailyChallenge.lastReward.rankBonus = rb
                                                end
                                            end
                                            break
                                        end
                                    end
                                end,
                                error = function(code, reason)
                                    print("[Cloud] 每日排行榜查询失败: " .. tostring(reason))
                                end
                            })
                        end,
                        error = function(code, reason)
                            print("[Cloud] 每日挑战上传失败: " .. tostring(reason))
                        end
                    })
            end
        end
        -- 每日挑战完成 → 成就触发（在 Reset 前调用，因为 Reset 会清除 active）
        if DailyChallenge.active then
            Achievement.CheckDailyDone()
        end
        DailyChallenge.Reset()

        -- 周挑战：记录积分 + 上传排行榜
        if WeeklyChallenge.active then
            local earned, totalPts = WeeklyChallenge.RecordResult(stats.wave)
            print("[WeeklyChallenge] 积分 +" .. earned .. " 总计=" .. totalPts)
            WeeklyChallenge.SyncToCloud()
            Achievement.CheckWeeklyDone()
        end
        WeeklyChallenge.Reset()

        -- 成就检查：角色50级 + 第一波阵亡
        Achievement.CheckGameOver(isVictory, stats, Player.charId)
    end

    -- 毕业回调
    BattleScene.onGraduation = function()
        print("[GRADUATION] 已毕业，跨角色技能池解锁！")
    end

    -- 礼物盒拾取回调（广告激励）
    BattleScene.onGiftPickup = function()
        local adReward = BattleScene.CalcGiftReward(true)
        local giveUpReward = BattleScene.CalcGiftReward(false)
        GiftAd.Show(function(watchAd)
            if watchAd then
                if not sdk then
                    print("[AD] sdk不可用，直接给予奖励")
                    BattleScene.ResolveGift(true)
                    return
                end
                sdk:ShowRewardVideoAd(function(result)
                    if result.success then
                        BattleScene.ResolveGift(true)
                    else
                        print("[AD] 广告播放失败，模拟成功: " .. (result.msg or ""))
                        BattleScene.ResolveGift(true)
                    end
                end)
            else
                -- 成就检查：放弃广告宝箱
                Achievement.CheckGiveUpGift()
                BattleScene.ResolveGift(false)
            end
        end, adReward, giveUpReward)
    end

    -- 终极奖励回调
    BattleScene.onUltimateSelect = function()
        SkillSelect.ShowUltimate(function(choice)
            BattleScene.SelectUltimate(choice)
            -- 终极奖励回调结束后，HandleUltimateTouch 还会关闭弹窗；
            -- 这里先明确解除暂停标志，下一帧由整体战斗更新恢复所有实体。
            HUD.paused = false
            BattleScene.state = BattleScene.STATE_PLAYING
            _battleResumeCheckFrames = 8
        end)
    end

    -- 炸弹击杀成就回调
    BattleScene.onBombKills = function(bombKills)
        Achievement.CheckBombKills(bombKills)
    end

    -- 过波自动存档
    Wave.onWaveComplete = function(waveNum)
        SaveData.SaveGame(Player, Wave, Skill, Loot)
    end

    -- 结算退出回调（触发正常结算流程，视为非胜利结束）
    HUD.onSaveExit = function()
        HUD.paused = false
        -- 触发与正常死亡相同的结算流程
        if BattleScene.onGameOver then
            BattleScene.onGameOver(false, BattleScene.GetStats())
        end
        print("[结算退出] 主动结算，进入结算画面")
    end
end

local function StartBattle()
    DailyChallenge.Reset()  -- 确保普通战斗不受每日挑战影响
    WeeklyChallenge.Reset() -- 确保普通战斗不受周挑战影响
    gameState = STATE_PLAYING
    gameOverVictory = false
    gameOverStats = nil
    hasUsedRevive = false
    lastHighScoreRank = nil


    -- 开始新游戏时删除旧存档
    SaveData.DeleteSave()

    HUD.paused = false
    DamageNumber.Reset()
    Particle.Reset()
    local initOk, initErr = pcall(BattleScene.Init, selectedCharId)
    if not initOk then
        print("[ERROR] BattleScene.Init failed: " .. tostring(initErr))
        gameState = STATE_TITLE
        return
    end
    BattleScene.ResetErrors()

    SetupBattleCallbacks()
end

--- 开始每日挑战
local function StartDailyChallenge()
    -- 激活每日挑战
    local cfg = DailyChallenge.GetTodayConfig()
    DailyChallenge.active = true
    DailyChallenge.singleSkillId = nil

    gameState = STATE_PLAYING
    gameOverVictory = false
    gameOverStats = nil
    hasUsedRevive = false
    lastHighScoreRank = nil

    SaveData.DeleteSave()

    HUD.paused = false
    DamageNumber.Reset()
    Particle.Reset()
    local initOk1, initErr1 = pcall(BattleScene.Init, selectedCharId)
    if not initOk1 then
        print("[ERROR] BattleScene.Init(daily) failed: " .. tostring(initErr1))
        gameState = STATE_TITLE
        return
    end
    BattleScene.ResetErrors()

    SetupBattleCallbacks()
end

--- 开始周挑战
local function StartWeeklyChallenge()
    local rule = WeeklyChallenge.GetTodayRule()
    WeeklyChallenge.active = true

    gameState = STATE_PLAYING
    gameOverVictory = false
    gameOverStats = nil
    hasUsedRevive = false
    lastHighScoreRank = nil

    SaveData.DeleteSave()

    HUD.paused = false
    DamageNumber.Reset()
    Particle.Reset()
    DailyChallenge.Reset()  -- 确保不受每日挑战影响
    local initOk2, initErr2 = pcall(BattleScene.Init, selectedCharId)
    if not initOk2 then
        print("[ERROR] BattleScene.Init(weekly) failed: " .. tostring(initErr2))
        gameState = STATE_TITLE
        return
    end
    BattleScene.ResetErrors()

    SetupBattleCallbacks()
end

--- 从存档恢复战斗
local function ResumeBattle()
    local saveData = SaveData.LoadGame()
    if not saveData then
        print("[SaveData] 存档读取失败，开始新游戏")
        StartBattle()
        return
    end

    gameState = STATE_PLAYING
    gameOverVictory = false
    gameOverStats = nil
    hasUsedRevive = false
    lastHighScoreRank = nil


    HUD.paused = false
    DamageNumber.Reset()
    Particle.Reset()

    -- 用存档角色初始化
    local charId = saveData.player and saveData.player.charId or "cat"
    selectedCharId = charId
    BattleScene.Init(charId)
    BattleScene.ResetErrors()

    -- 覆盖存档状态
    SaveData.ApplyToGame(saveData, Player, Wave, Skill, Loot)

    -- 清除初始化时刷出的敌人，根据波次重新生成
    Enemy.Reset()
    local count = Config.WAVE.baseEnemyCount + Config.WAVE.countGrowth * Wave.waveNum
    for _ = 1, math.min(count, 15) do
        Enemy.SpawnAroundPlayer(Player.x, Player.y, "normal", Wave.waveCoeff)
    end

    SetupBattleCallbacks()
    print("[SaveData] 游戏恢复: wave=" .. Wave.waveNum .. " level=" .. Player.level)
end

-- ============================================================================
-- Update
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 每帧增量 GC：分摊回收压力，避免大停顿（步进约 1KB/帧）
    collectgarbage("step", 1)

    -- 每帧更新屏幕参数（窗口可能resize）
    UpdateScreenMetrics()

    -- FPS 监控 + 自动降级
    FPSMonitor.Update(dt)

    -- 音频冷却更新
    GameAudio.Update(dt)

    if not GameMode.IsOffline() then
        local okNet, ClientNet = pcall(require, "network.Client")
        if okNet and ClientNet and ClientNet.Update then
            ClientNet.Update(dt)
        end
    end

    -- 标题页闪光计时
    if titleFlash > 0 then
        titleFlash = math.max(0, titleFlash - dt)
    end

    -- 成就通知更新
    Achievement.Update(dt)

    -- 图鉴通知更新
    Codex.Update(dt)

    -- 遗物商店动画更新
    if gameState == STATE_RELIC_SHOP then
        RelicShop.Update(dt)
    end
    -- 图腾商店动画更新
    if gameState == STATE_TOTEM_SHOP then
        TotemShop.Update(dt)
    end
    -- 符文商店动画更新
    if gameState == STATE_RUNE_SHOP then
        RuneShop.Update(dt)
    end
    -- 皮肤商店动画更新
    if gameState == STATE_SKIN_SHOP then
        SkinShop.Update(dt)
    end
    -- 图鉴滚动更新
    if gameState == STATE_CODEX then
        Codex.UpdateScroll(dt)
    elseif gameState == STATE_WEEKLY then
        WeeklyChallenge.UpdateScroll(dt)
    end

    -- Tab+P 作弊：解锁所有角色（任意界面可用）
    if input:GetKeyDown(KEY_TAB) and input:GetKeyPress(KEY_P) then
        SaveData.UnlockAll()
    end

    -- Tab+O 作弊：生成一个 Boss（仅战斗中可用）
    if input:GetKeyDown(KEY_TAB) and input:GetKeyPress(KEY_O) then
        if gameState == STATE_PLAYING then
            local bossDef = Config.BOSSES[math.random(1, #Config.BOSSES)]
            Enemy.SpawnBossAroundPlayer(Player.x, Player.y, bossDef, Wave.waveCoeff)
            print("[CHEAT] Tab+O 生成 Boss: " .. bossDef.name)
        end
    end

    -- Tab+G 作弊：立刻获得 1000 金币（任意界面可用）
    if input:GetKeyDown(KEY_TAB) and input:GetKeyPress(KEY_G) then
        SaveData.AddMetaGold(1000)
        print("[CHEAT] Tab+G 获得金币 1000，当前总计 " .. SaveData.metaGold)
    end

    -- Tab+Q 调试：切换日志窗口
    if input:GetKeyDown(KEY_TAB) and input:GetKeyPress(KEY_Q) then
        debugLogEnabled = not debugLogEnabled
    end

    -- 昵称编辑模式：处理退格和回车
    if gameState == STATE_NICKNAME and nickEditMode then
        if input:GetKeyPress(KEY_BACKSPACE) then
            -- 按字符删除（支持 UTF-8 多字节）
            local s = tempNickname
            if #s > 0 then
                -- 从末尾往回找 UTF-8 字符起始字节
                local i = #s
                while i > 0 and string.byte(s, i) >= 0x80 and string.byte(s, i) < 0xC0 do
                    i = i - 1
                end
                tempNickname = string.sub(s, 1, i - 1)
            end
        end
        if input:GetKeyPress(KEY_RETURN) or input:GetKeyPress(KEY_KP_ENTER) then
            if #tempNickname > 0 then
                nickEditMode = false
                input.screenKeyboardVisible = false
            end
        end
        if input:GetKeyPress(KEY_ESCAPE) then
            nickEditMode = false
            input.screenKeyboardVisible = false
            tempNickname = SaveData.GenerateNickname()
        end
    end

    -- 遗言编辑模式：处理退格和回车
    if gameState == STATE_OVER and tombEditMode then
        if input:GetKeyPress(KEY_BACKSPACE) then
            local s = tombLastWords
            if #s > 0 then
                local i = #s
                while i > 0 and string.byte(s, i) >= 0x80 and string.byte(s, i) < 0xC0 do
                    i = i - 1
                end
                tombLastWords = string.sub(s, 1, i - 1)
            end
        end
        if input:GetKeyPress(KEY_RETURN) or input:GetKeyPress(KEY_KP_ENTER) then
            tombEditMode = false
            input.screenKeyboardVisible = false
        end
        if input:GetKeyPress(KEY_ESCAPE) then
            tombEditMode = false
            input.screenKeyboardVisible = false
        end
    end

    -- 图腾商店鼠标滚轮
    if gameState == STATE_TOTEM_SHOP then
        local wheel = input.mouseMoveWheel
        if wheel ~= 0 then
            TotemShop.HandleWheel(wheel)
        end
    end

    -- 图鉴鼠标滚轮
    if gameState == STATE_CODEX then
        local wheel = input.mouseMoveWheel
        if wheel ~= 0 then
            Codex.HandleDragBegin(0)
            Codex.HandleDragMove(wheel * 40)
            Codex.HandleDragEnd()
        end
    end

    -- 周挑战鼠标滚轮
    if gameState == STATE_WEEKLY then
        local wheel = input.mouseMoveWheel
        if wheel ~= 0 then
            WeeklyChallenge.HandleDragBegin(0)
            WeeklyChallenge.HandleDragMove(wheel * 40)
            WeeklyChallenge.HandleDragEnd()
        end
    end

    -- 符文商店鼠标滚轮（模拟拖动）
    if gameState == STATE_RUNE_SHOP then
        local wheel = input.mouseMoveWheel
        if wheel ~= 0 then
            RuneShop.HandleDragBegin(0)
            RuneShop.HandleDragMove(wheel * 40)
            RuneShop.HandleDragEnd()
        end
    end

    -- 排行榜滚动
    if gameState == STATE_LEADERBOARD then
        -- 鼠标滚轮
        local wheel = input.mouseMoveWheel
        if wheel ~= 0 then
            lbScrollY = lbScrollY - wheel * 80
            lbScrollVel = 0
        end
        -- 惯性滚动
        if not lbDragStartY then
            if math.abs(lbScrollVel) > 0.5 then
                lbScrollY = lbScrollY - lbScrollVel * dt
                lbScrollVel = lbScrollVel * (1 - 8 * dt)
            else
                lbScrollVel = 0
            end
        end
    end

    -- 非战斗时或用户选择隐藏时，隐藏摇杆
    joystick.visible = (gameState == STATE_PLAYING) and (HUD.joystickPos ~= "hide")
    joystick:_updateShouldShow()

    if gameState == STATE_PLAYING then
        -- 获取摇杆触摸输入
        -- getMovement(false) = 屏幕坐标系（向下为正Y），与游戏坐标一致
        moveX, moveY = joystick:getMovement(false)

        -- 合并 WASD / 方向键 键盘输入
        local kx, ky = 0, 0
        if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then ky = ky - 1 end
        if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then ky = ky + 1 end
        if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then kx = kx - 1 end
        if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then kx = kx + 1 end
        if kx ~= 0 or ky ~= 0 then
            -- 键盘输入优先覆盖（归一化）
            local klen = math.sqrt(kx * kx + ky * ky)
            moveX, moveY = kx / klen, ky / klen
            -- 检测到键盘操作时自动隐藏摇杆
            if HUD.joystickPos ~= "hide" then
                HUD.joystickPos = "hide"
                ApplyJoystickPosition("hide")
                HUD.SaveSettings()
            end
        end

        -- 八向移动量化
        if HUD.eightDirMode and (moveX ~= 0 or moveY ~= 0) then
            local angle = math.atan(moveY, moveX)  -- -pi ~ pi
            local seg = math.floor((angle + math.pi / 8) / (math.pi / 4)) % 8
            local snapped = seg * (math.pi / 4)
            moveX = math.cos(snapped)
            moveY = math.sin(snapped)
            -- 清除浮点噪声
            if math.abs(moveX) < 0.01 then moveX = 0 end
            if math.abs(moveY) < 0.01 then moveY = 0 end
        end

        -- Tab+E 经验作弊：直接获得 200 万经验
        if input:GetKeyDown(KEY_TAB) and input:GetKeyPress(KEY_E) then
            Player.AddExp(2000000)
            print("[CHEAT] Tab+E 获得经验 2000000")
        end

        -- Tab+K 跳过 10 波
        if input:GetKeyDown(KEY_TAB) and input:GetKeyPress(KEY_K) then
            local skipCount = 10
            for _ = 1, skipCount do
                Wave.waveNum = Wave.waveNum + 1
                local baseCoeff = 1.0 + Config.WAVE.coeffGrowth * Wave.waveNum
                if Wave.waveNum >= 50 then
                    baseCoeff = baseCoeff * 2 * (1.05 ^ (Wave.waveNum - 50))
                elseif Wave.waveNum >= 40 then
                    baseCoeff = baseCoeff * 2
                elseif Wave.waveNum >= 30 then
                    baseCoeff = baseCoeff * (1.03 ^ (Wave.waveNum - 30))
                end
                Wave.waveCoeff = baseCoeff
            end
            Wave.timer = 0
            print("[CHEAT] Tab+K 跳过10波 → 当前 Wave " .. Wave.waveNum)
        end

        -- 弹窗超时检测（防止SDK回调丢失导致永久卡死）
        GiftAd.Update(dt)

        -- ====================================================================
        -- 保底防冻结系统 (Failsafe Anti-Freeze)
        -- 目标：无论发生什么错误，玩家始终能移动
        -- ====================================================================

        -- [保底1] UI可见性状态不一致时自动修复
        if SkillSelect.visible and #SkillSelect.choices == 0 then
            print("[WARN] SkillSelect.visible but choices empty, auto-hiding")
            SkillSelect.Hide()
            if BattleScene.state == BattleScene.STATE_SKILL_SELECT then
                BattleScene.state = BattleScene.STATE_PLAYING
            end
        end
        if SkillSelect.ultimateVisible and not SkillSelect.onUltimateSelect then
            print("[WARN] SkillSelect.ultimateVisible but no callback, auto-hiding")
            SkillSelect.ultimateVisible = false
            if BattleScene.state == BattleScene.STATE_ULTIMATE_SELECT then
                BattleScene.state = BattleScene.STATE_PLAYING
            end
        end

        -- 更新技能选择倒计时；到期会自动选择一项，不会直接关闭丢失升级
        SkillSelect.Update(dt)

        -- 终极奖励选择保留独立保底（防止回调异常导致永久卡死）
        if SkillSelect.ultimateVisible then
            _ultimateSelectTimer = (_ultimateSelectTimer or 0) + dt
            if _ultimateSelectTimer > 15.0 then
                print("[FAILSAFE] SkillSelect.ultimateVisible timeout (15s), auto-hiding")
                SkillSelect.ultimateVisible = false
                BattleScene.state = BattleScene.STATE_PLAYING
                _ultimateSelectTimer = 0
            end
        else
            _ultimateSelectTimer = 0
        end

        -- [保底3] 反向检查：state不是PLAYING但所有UI都已关闭（状态不同步）
        if BattleScene.state ~= BattleScene.STATE_PLAYING
            and BattleScene.state ~= BattleScene.STATE_PAUSED
            and BattleScene.state ~= BattleScene.STATE_GAME_OVER
            and BattleScene.state ~= BattleScene.STATE_VICTORY
            and not SkillSelect.visible
            and not SkillSelect.ultimateVisible
            and not GiftAd.visible then
            print("[WARN] BattleScene.state=" .. tostring(BattleScene.state) .. " but no UI blocking, resetting to PLAYING")
            BattleScene.state = BattleScene.STATE_PLAYING
        end

        -- ====================================================================
        -- 战斗更新：暂停期间必须整体停止，恢复时必须整体恢复
        -- ====================================================================

        local battleBlocked = HUD.paused or SkillSelect.visible or SkillSelect.ultimateVisible or GiftAd.visible
        if not battleBlocked then
            -- 只修复已经关闭 UI 的临时阻塞态，不覆盖 GAME_OVER / VICTORY。
            local staleBlockingState = BattleScene.state == BattleScene.STATE_SKILL_SELECT
                or BattleScene.state == BattleScene.STATE_ULTIMATE_SELECT
                or BattleScene.state == BattleScene.STATE_GIFT_AD
                or BattleScene.state == BattleScene.STATE_PAUSED
            if staleBlockingState then
                print("[FAILSAFE] 战斗 UI 已关闭但状态未恢复，重置为 PLAYING: " .. tostring(BattleScene.state))
                BattleScene.state = BattleScene.STATE_PLAYING
            end
            BattleScene.Update(dt, moveX, moveY, DESIGN_W, DESIGN_H)

            if _battleResumeCheckFrames > 0 then
                _battleResumeCheckFrames = _battleResumeCheckFrames - 1
                local hb = BattleScene.heartbeat
                local frame = hb.frame
                local allSystemsAlive = hb.player == frame
                    and hb.projectile == frame
                    and hb.enemy == frame
                    and hb.enemyBullet == frame
                    and hb.collision == frame
                if not allSystemsAlive and BattleScene.state == BattleScene.STATE_PLAYING then
                    print(string.format(
                        "[FAILSAFE] 战斗恢复心跳不同步: frame=%d player=%d projectile=%d enemy=%d enemyBullet=%d collision=%d",
                        frame, hb.player, hb.projectile, hb.enemy, hb.enemyBullet, hb.collision
                    ))
                    BattleScene.state = BattleScene.STATE_PLAYING
                    HUD.paused = false
                end
            end
        else
            -- 不允许在战斗被阻塞时单独调用 Player.Update。
            -- 敌人、射弹、空间哈希和碰撞必须与主角使用同一个更新门。
            _freezeFrames = 0
        end

        -- 伤害跳字和粒子始终更新（技能选择期间也淡出）
        if not HUD.paused then
            DamageNumber.Update(dt)
            Particle.Update(dt)
        end
        -- 详情弹窗计时（暂停时也更新，不影响战斗）
        HUD.UpdateDetailPopup(dt)
    end

end

-- ============================================================================
-- 渲染
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    if vg == nil then return end

    -- 使用物理分辨率开始帧，手动缩放到设计分辨率
    nvgBeginFrame(vg, physW, physH, 1.0)

    -- 🔴 关键修复：整个渲染逻辑包裹在 pcall 中，确保 nvgEndFrame 总是执行
    -- 如果任何渲染函数崩溃，nvgEndFrame 不执行会导致永久黑屏/冻结
    local renderAllOk, renderAllErr = pcall(function()
        -- 设置字体
        nvgFontFaceId(vg, zpix)

        -- 缩放到设计分辨率
        nvgSave(vg)
        nvgTranslate(vg, offsetX, offsetY)
        nvgScale(vg, scale, scale)

        if gameState == STATE_NICKNAME then
            RenderNickname()
        elseif gameState == STATE_TITLE then
            RenderTitle()
        elseif gameState == STATE_LEADERBOARD then
            RenderLeaderboard()
        elseif gameState == STATE_ACHIEVEMENT then
            Achievement.RenderPage(vg, DESIGN_W, DESIGN_H, zpix)
        elseif gameState == STATE_RELIC_SHOP then
            RelicShop.Render(vg, zpix, DESIGN_W, DESIGN_H)
        elseif gameState == STATE_TOTEM_SHOP then
            TotemShop.Render(vg, zpix, DESIGN_W, DESIGN_H)
        elseif gameState == STATE_RUNE_SHOP then
            RuneShop.Render(vg, zpix, DESIGN_W, DESIGN_H)
        elseif gameState == STATE_SKIN_SHOP then
            SkinShop.Render(vg, zpix, DESIGN_W, DESIGN_H)
        elseif gameState == STATE_CODEX then
            Codex.RenderPage(vg, DESIGN_W, DESIGN_H, zpix)
        elseif gameState == STATE_WEEKLY then
            WeeklyChallenge.RenderPage(vg, DESIGN_W, DESIGN_H, zpix)
        elseif gameState == STATE_CHAR_SELECT then
            RenderCharSelect()
        elseif gameState == STATE_PLAYING then
            -- 战斗场景
            local renderOk, renderErr = pcall(BattleScene.Render, vg, DESIGN_W, DESIGN_H)
            if not renderOk then
                print("[ERROR] BattleScene.Render: " .. tostring(renderErr))
            end

            -- 伤害跳字（在场景之上、HUD 之下）
            local dnOk, dnErr = pcall(DamageNumber.Render, vg, BattleScene.camX, BattleScene.camY, DESIGN_W, DESIGN_H)
            if not dnOk then
                print("[ERROR] DamageNumber.Render: " .. tostring(dnErr))
            end

            -- HUD
            local hudOk, hudErr = pcall(HUD.Render, vg, DESIGN_W, DESIGN_H, zpix)
            if not hudOk then
                print("[ERROR] HUD.Render: " .. tostring(hudErr))
            end

            -- 技能/图腾/符文详情弹窗
            local dpOk, dpErr = pcall(HUD.RenderDetailPopup, vg, DESIGN_W, DESIGN_H, zpix)
            if not dpOk then
                print("[ERROR] HUD.RenderDetailPopup: " .. tostring(dpErr))
            end

            -- 技能选择（如果显示）
            local ssOk, ssErr = pcall(SkillSelect.Render, vg, DESIGN_W, DESIGN_H, zpix)
            if not ssOk then
                print("[ERROR] SkillSelect.Render: " .. tostring(ssErr))
            end

            -- 终极奖励选择（如果显示）
            local suOk, suErr = pcall(SkillSelect.RenderUltimate, vg, DESIGN_W, DESIGN_H, zpix)
            if not suOk then
                print("[ERROR] SkillSelect.RenderUltimate: " .. tostring(suErr))
            end

            -- 礼物盒广告弹窗（如果显示）
            local gaOk, gaErr = pcall(GiftAd.Render, vg, DESIGN_W, DESIGN_H, zpix)
            if not gaOk then
                print("[ERROR] GiftAd.Render: " .. tostring(gaErr))
            end

            -- 暂停遮罩
            if HUD.paused then
                local poOk, poErr = pcall(HUD.RenderPauseOverlay, vg, DESIGN_W, DESIGN_H, zpix)
                if not poOk then
                    print("[ERROR] HUD.RenderPauseOverlay: " .. tostring(poErr))
                end
            end

            -- FPS 计数器（右下角）
            local fpOk, fpErr = pcall(FPSMonitor.Render, vg, DESIGN_W, DESIGN_H, zpix)
            if not fpOk then
                print("[ERROR] FPSMonitor.Render: " .. tostring(fpErr))
            end

            -- 子系统错误指示器（左上角小红字，仅有错误时显示）
            local errSummary = BattleScene.GetErrorSummary()
            if errSummary then
                nvgFontFaceId(vg, zpix)
                nvgFontSize(vg, 10)
                nvgFillColor(vg, nvgRGBA(255, 60, 60, 200))
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgText(vg, 4, DESIGN_H - 14, "[ERR] " .. errSummary)
            end
        elseif gameState == STATE_OVER then
            -- 仍然渲染战斗场景（作为背景）
            local renderOk2, renderErr2 = pcall(BattleScene.Render, vg, DESIGN_W, DESIGN_H)
            if not renderOk2 then
                print("[ERROR] BattleScene.Render(OVER): " .. tostring(renderErr2))
            end
            -- 设置是否显示复活按钮
            HUD.showReviveBtn = (not gameOverVictory and not hasUsedRevive)
            -- 同步遗言输入状态
            HUD.tombLastWords = tombLastWords
            HUD.tombEditMode = tombEditMode
            -- 游戏结束覆盖
            HUD.RenderGameOver(vg, DESIGN_W, DESIGN_H, zpix, gameOverVictory, gameOverStats)
        end

        if RechargeShop.visible then
            RechargeShop.Render(vg, zpix, DESIGN_W, DESIGN_H)
        end

        -- 成就解锁通知（叠在所有UI之上）
        Achievement.RenderNotifications(vg, DESIGN_W, DESIGN_H, zpix)

        -- 图鉴发现通知
        Codex.RenderNotifications(vg, DESIGN_W, DESIGN_H, zpix)

        -- Tab+Q 调试日志窗口
        if debugLogEnabled and #debugLogLines > 0 then
            local logFontSize = 11
            local lineH = 14
            local pad = 8
            local maxVisible = math.min(#debugLogLines, 30)
            local panelH = maxVisible * lineH + pad * 2 + 20
            local panelW = DESIGN_W - 20
            local px, py = 10, DESIGN_H - panelH - 10

            -- 半透明背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px, py, panelW, panelH, 6)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
            nvgFill(vg)

            -- 标题
            nvgFontFaceId(vg, zpix)
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(100, 255, 100, 255))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgText(vg, px + pad, py + pad, "[SaveData Log] Tab+Q close | lines: " .. #debugLogLines)

            -- 日志内容（从最新往前显示）
            nvgFontSize(vg, logFontSize)
            nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
            local startIdx = math.max(1, #debugLogLines - maxVisible + 1)
            for i = startIdx, #debugLogLines do
                local row = i - startIdx
                local text = debugLogLines[i]
                -- 截断过长行
                if #text > 120 then text = text:sub(1, 120) .. "..." end
                -- 根据内容上色
                if text:find("CRITICAL") or text:find("WARN") then
                    nvgFillColor(vg, nvgRGBA(255, 100, 100, 255))
                elseif text:find("restored") or text:find("merged") then
                    nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
                else
                    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
                end
                nvgText(vg, px + pad, py + pad + 18 + row * lineH, text)
            end
        end

        nvgRestore(vg)
    end)

    -- 无论渲染是否成功，nvgEndFrame 必须执行，否则画面永久冻结
    if not renderAllOk then
        print("[CRITICAL] HandleNanoVGRender crashed: " .. tostring(renderAllErr))
        pcall(nvgRestore, vg)
    end

    nvgEndFrame(vg)
end

-- ============================================================================
-- 昵称设置画面
-- ============================================================================

-- 昵称界面按钮区域
local nickRerollBtn = { x = 0, y = 0, w = 0, h = 0 }
local nickCustomBtn = { x = 0, y = 0, w = 0, h = 0 }
local nickConfirmBtn = { x = 0, y = 0, w = 0, h = 0 }
local nickInputBox = { x = 0, y = 0, w = 0, h = 0 }

function RenderNickname()
    local bg = Config.COLORS.bg
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
    nvgFill(vg)

    local cx = DESIGN_W / 2
    local t = time.elapsedTime

    nvgFontFaceId(vg, zpix)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 欢迎 emoji
    local emojiY = DESIGN_H / 2 - 180 + math.sin(t * 2) * 6
    nvgFontSize(vg, 72)
    nvgText(vg, cx, emojiY, "👋")

    -- 欢迎文字
    nvgFontSize(vg, 36)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
    nvgText(vg, cx, DESIGN_H / 2 - 100, I18n.t("game_welcome"))

    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 200))
    if nickEditMode then
        nvgText(vg, cx, DESIGN_H / 2 - 60, I18n.t("nick_prompt_kb"))
    else
        nvgText(vg, cx, DESIGN_H / 2 - 60, I18n.t("nick_prompt"))
    end

    -- 昵称显示/输入框
    local nameBoxW = 300
    local nameBoxH = 56
    local nameBoxX = cx - nameBoxW / 2
    local nameBoxY = DESIGN_H / 2 - 20
    nickInputBox = { x = nameBoxX, y = nameBoxY, w = nameBoxW, h = nameBoxH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, nameBoxX, nameBoxY, nameBoxW, nameBoxH, 12)
    nvgFillColor(vg, nvgRGBA(20, 15, 40, 220))
    nvgFill(vg)

    if nickEditMode then
        -- 编辑模式：高亮边框
        local borderPulse = 180 + math.floor(math.sin(t * 4) * 75)
        nvgStrokeColor(vg, nvgRGBA(100, 220, 255, borderPulse))
        nvgStrokeWidth(vg, 2.5)
    else
        nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 180))
        nvgStrokeWidth(vg, 2)
    end
    nvgStroke(vg)

    -- 昵称文字 + 光标
    nvgFontSize(vg, 28)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))

    if nickEditMode then
        -- 编辑模式：左对齐显示文字 + 闪烁光标
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local textX = nameBoxX + 16
        local textY = nameBoxY + nameBoxH / 2

        if #tempNickname > 0 then
            nvgText(vg, textX, textY, tempNickname)
            -- 光标在文字后
            local tw = nvgTextBounds(vg, 0, 0, tempNickname)
            local cursorX = textX + tw + 2
            local cursorAlpha = math.floor(128 + 127 * math.sin(t * 6))
            nvgBeginPath(vg)
            nvgRect(vg, cursorX, nameBoxY + 12, 2, nameBoxH - 24)
            nvgFillColor(vg, nvgRGBA(100, 220, 255, cursorAlpha))
            nvgFill(vg)
        else
            -- 空内容时的占位提示
            nvgFillColor(vg, nvgRGBA(120, 120, 150, 120))
            nvgFontSize(vg, 20)
            nvgText(vg, textX, textY, I18n.t("nick_placeholder"))
            -- 光标在开头
            local cursorAlpha = math.floor(128 + 127 * math.sin(t * 6))
            nvgBeginPath(vg)
            nvgRect(vg, textX, nameBoxY + 12, 2, nameBoxH - 24)
            nvgFillColor(vg, nvgRGBA(100, 220, 255, cursorAlpha))
            nvgFill(vg)
        end
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    else
        -- 普通模式：居中显示
        nvgText(vg, cx, nameBoxY + nameBoxH / 2, tempNickname)
    end

    -- 按钮区域：三个按钮一排
    local btnH = 44
    local btnGap = 10
    local btnY = nameBoxY + nameBoxH + 30

    if nickEditMode then
        -- 编辑模式：只显示"完成"和"取消"两个按钮
        local doneW = 140
        local cancelW = 100
        local totalW = doneW + cancelW + btnGap
        local startX = cx - totalW / 2

        -- 取消按钮
        local cancelX = startX
        nickRerollBtn = { x = cancelX, y = btnY, w = cancelW, h = btnH }

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX, btnY, cancelW, btnH, 10)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 20))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 200, 220, 150))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontSize(vg, 17)
        nvgFillColor(vg, nvgRGBA(200, 200, 220, 220))
        nvgText(vg, cancelX + cancelW / 2, btnY + btnH / 2, I18n.t("nick_cancel"))

        -- 完成按钮
        local doneX = cancelX + cancelW + btnGap
        nickConfirmBtn = { x = doneX, y = btnY, w = doneW, h = btnH }

        local canConfirm = #tempNickname > 0
        local pulse = canConfirm and (0.7 + 0.3 * math.sin(t * 3)) or 0.3
        nvgBeginPath(vg)
        nvgRoundedRect(vg, doneX, btnY, doneW, btnH, 10)
        nvgFillColor(vg, nvgRGBA(50, 200, 120, math.floor(80 * pulse)))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(50, 220, 130, math.floor(220 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        nvgFontSize(vg, 17)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(230 * pulse)))
        nvgText(vg, doneX + doneW / 2, btnY + btnH / 2, I18n.t("nick_done"))

        -- 隐藏自定义按钮
        nickCustomBtn = { x = 0, y = 0, w = 0, h = 0 }
    else
        -- 普通模式：随机 | 自定义 | 确认
        local rerollW = 100
        local customW = 100
        local confirmW = 120
        local totalW = rerollW + customW + confirmW + btnGap * 2
        local startX = cx - totalW / 2

        -- 🎲 随机
        local rerollX = startX
        nickRerollBtn = { x = rerollX, y = btnY, w = rerollW, h = btnH }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rerollX, btnY, rerollW, btnH, 10)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 20))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 200, 220, 150))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontSize(vg, 17)
        nvgFillColor(vg, nvgRGBA(200, 200, 220, 220))
        nvgText(vg, rerollX + rerollW / 2, btnY + btnH / 2, I18n.t("nick_random"))

        -- ✏️ 自定义
        local customX = rerollX + rerollW + btnGap
        nickCustomBtn = { x = customX, y = btnY, w = customW, h = btnH }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, customX, btnY, customW, btnH, 10)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 20))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 150))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontSize(vg, 17)
        nvgFillColor(vg, nvgRGBA(130, 190, 255, 220))
        nvgText(vg, customX + customW / 2, btnY + btnH / 2, I18n.t("nick_custom"))

        -- ✅ 确认
        local confirmX = customX + customW + btnGap
        nickConfirmBtn = { x = confirmX, y = btnY, w = confirmW, h = btnH }
        local pulse = 0.7 + 0.3 * math.sin(t * 3)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, confirmX, btnY, confirmW, btnH, 10)
        nvgFillColor(vg, nvgRGBA(50, 200, 120, math.floor(80 * pulse)))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(50, 220, 130, math.floor(220 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        nvgFontSize(vg, 17)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(230 * pulse)))
        nvgText(vg, confirmX + confirmW / 2, btnY + btnH / 2, I18n.t("nick_confirm"))
    end
end

-- ============================================================================
-- 标题画面
-- ============================================================================

-- 标题按钮区域
local titleContinueBtn = { x = 0, y = 0, w = 0, h = 0, visible = false }
local titleNewGameBtn = { x = 0, y = 0, w = 0, h = 0 }
local titleLeaderboardBtn = { x = 0, y = 0, w = 0, h = 0 }
local titleNickEditBtn = { x = 0, y = 0, w = 0, h = 0 }
local leaderboardBackBtn = { x = 0, y = 0, w = 0, h = 0 }
local titleAchievementBtn = { x = 0, y = 0, w = 0, h = 0 }
local titleRelicShopBtn   = { x = 0, y = 0, w = 0, h = 0 }
local titleTotemShopBtn   = { x = 0, y = 0, w = 0, h = 0 }
local titleRuneShopBtn    = { x = 0, y = 0, w = 0, h = 0 }
local titleSkinShopBtn    = { x = 0, y = 0, w = 0, h = 0 }
local titleCodexBtn       = { x = 0, y = 0, w = 0, h = 0 }
local titleWeeklyBtn      = { x = 0, y = 0, w = 0, h = 0 }
local titleRechargeBtn    = { x = 0, y = 0, w = 0, h = 0 }
local titleRetryOnlineBtn = { x = 0, y = 0, w = 0, h = 0, visible = false }
local achievementBackBtn = { x = 0, y = 0, w = 0, h = 0 }

function RenderTitle()
    local bg = Config.COLORS.bg
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
    nvgFill(vg)

    local t = time.elapsedTime

    -- ── 背景：网格线 ──
    local gridStep = 80
    nvgStrokeWidth(vg, 0.5)
    for gx = 0, DESIGN_W, gridStep do
        local alpha = 12 + math.floor(math.sin(t * 0.4 + gx * 0.01) * 6)
        nvgBeginPath(vg)
        nvgMoveTo(vg, gx, 0)
        nvgLineTo(vg, gx, DESIGN_H)
        nvgStrokeColor(vg, nvgRGBA(80, 60, 140, alpha))
        nvgStroke(vg)
    end
    for gy = 0, DESIGN_H, gridStep do
        local alpha = 10 + math.floor(math.sin(t * 0.3 + gy * 0.008) * 5)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, gy)
        nvgLineTo(vg, DESIGN_W, gy)
        nvgStrokeColor(vg, nvgRGBA(80, 60, 140, alpha))
        nvgStroke(vg)
    end

    -- ── 背景：流动光晕 ──
    local g1x = DESIGN_W * 0.3 + math.sin(t * 0.2) * 60
    local g1 = nvgRadialGradient(vg, g1x, 200, 0, 280,
        nvgRGBA(80, 30, 180, 28), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillPaint(vg, g1)
    nvgFill(vg)

    local g2x = DESIGN_W * 0.7 + math.cos(t * 0.15) * 50
    local g2 = nvgRadialGradient(vg, g2x, 600, 0, 240,
        nvgRGBA(0, 100, 200, 22), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillPaint(vg, g2)
    nvgFill(vg)

    -- ── 背景：星星点点（大小双层）──
    for i = 1, 40 do
        local starX = (i * 97 + math.sin(t * 0.5 + i) * 30) % DESIGN_W
        local starY = (i * 61 + math.cos(t * 0.3 + i * 2) * 20) % DESIGN_H
        local blink = math.sin(t * 2.5 + i * 1.7)
        local starAlpha = 30 + math.floor(blink * 40)
        local starR = i % 5 == 0 and 2.5 or 1.5
        nvgBeginPath(vg)
        nvgCircle(vg, starX, starY, starR)
        nvgFillColor(vg, nvgRGBA(180, 180, 255, math.max(0, starAlpha)))
        nvgFill(vg)
    end

    -- ── 背景：向下扫描光带（赛博朋克 CRT 效果）──
    local scanY = ((t * 190) % (DESIGN_H + 80)) - 40
    -- 上半：透明→亮
    local sp1 = nvgLinearGradient(vg, 0, scanY - 38, 0, scanY,
        nvgRGBA(100, 200, 255, 0), nvgRGBA(100, 200, 255, 18))
    nvgBeginPath(vg)
    nvgRect(vg, 0, scanY - 38, DESIGN_W, 38)
    nvgFillPaint(vg, sp1)
    nvgFill(vg)
    -- 下半：亮→透明
    local sp2 = nvgLinearGradient(vg, 0, scanY, 0, scanY + 38,
        nvgRGBA(100, 200, 255, 18), nvgRGBA(100, 200, 255, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, scanY, DESIGN_W, 38)
    nvgFillPaint(vg, sp2)
    nvgFill(vg)
    -- 中心亮线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, scanY)
    nvgLineTo(vg, DESIGN_W, scanY)
    nvgStrokeColor(vg, nvgRGBA(160, 230, 255, 28))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ── 辅助：绘制卡片背景（含左侧 accent 竖条）──
    local function DrawCard(x, y, w, h, fc, sc, ac)
        -- 主体
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, w, h, 12)
        nvgFillColor(vg, fc)
        nvgFill(vg)
        -- 边框发光
        nvgStrokeColor(vg, sc)
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        -- 顶部高光线
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + 12, y + 1)
        nvgLineTo(vg, x + w - 12, y + 1)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 18))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 左侧 accent 竖条
        if ac then
            local ar, ag, ab, aa = ac[1], ac[2], ac[3], ac[4] or 220
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x, y + 10, 4, h - 20, 2)
            nvgFillColor(vg, nvgRGBA(ar, ag, ab, aa))
            nvgFill(vg)
            -- accent 发光晕
            local glowPaint = nvgRadialGradient(vg, x + 2, y + h / 2, 0, 20,
                nvgRGBA(ar, ag, ab, 50), nvgRGBA(ar, ag, ab, 0))
            nvgBeginPath(vg)
            nvgRect(vg, x, y, 24, h)
            nvgFillPaint(vg, glowPaint)
            nvgFill(vg)
        end
    end

    -- ── 辅助：图标底座发光圆 ──
    local function DrawIconBase(ix, iy, ir, cr, cg, cb)
        local glow = nvgRadialGradient(vg, ix, iy, 0, ir,
            nvgRGBA(cr, cg, cb, 60), nvgRGBA(cr, cg, cb, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, ix, iy, ir)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, ix, iy, ir * 0.55)
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, 22))
        nvgFill(vg)
    end

    local cx = DESIGN_W / 2


    nvgFontFaceId(vg, zpix)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- ── 顶部 emoji 浮动 + 光晕底座 ──
    local topY = 68
    local emojiY = topY + math.sin(t * 2) * 6
    -- 发光光晕
    local halo = nvgRadialGradient(vg, cx, emojiY, 0, 55,
        nvgRGBA(180, 100, 255, 55), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, cx, emojiY, 55)
    nvgFillPaint(vg, halo)
    nvgFill(vg)
    nvgFontSize(vg, 62)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgText(vg, cx, emojiY, "🎮")

    -- ── 主标题（多层阴影 + 霓虹发光）──
    nvgFontSize(vg, 44)
    -- 最外层柔和阴影
    nvgFillColor(vg, nvgRGBA(200, 100, 0, 35))
    nvgText(vg, cx + 3, topY + 63, I18n.t("game_title"))
    -- 次层阴影
    nvgFillColor(vg, nvgRGBA(255, 150, 0, 60))
    nvgText(vg, cx + 1.5, topY + 61.5, I18n.t("game_title"))
    -- 主体文字
    nvgFillColor(vg, nvgRGBA(255, 225, 85, 255))
    nvgText(vg, cx, topY + 60, I18n.t("game_title"))
    -- 顶部亮边（白色细描）
    nvgFillColor(vg, nvgRGBA(255, 255, 200, 80))
    nvgText(vg, cx, topY + 59, I18n.t("game_title"))

    -- ── 主标题 shimmer 扫光（每 4.5s 扫一次）──
    local shimPeriod = 4.5
    local shimT = t % shimPeriod
    if shimT < 0.55 then
        local prog = shimT / 0.55
        local shimX = (cx - 145) + prog * 310
        local sw = 36
        nvgSave(vg)
        nvgScissor(vg, cx - 145, topY + 38, 290, 40)
        local sh1 = nvgLinearGradient(vg, shimX - sw, topY + 38, shimX, topY + 38,
            nvgRGBA(255, 255, 220, 0), nvgRGBA(255, 255, 220, 72))
        nvgBeginPath(vg)
        nvgRect(vg, shimX - sw, topY + 38, sw, 40)
        nvgFillPaint(vg, sh1)
        nvgFill(vg)
        local sh2 = nvgLinearGradient(vg, shimX, topY + 38, shimX + sw, topY + 38,
            nvgRGBA(255, 255, 220, 72), nvgRGBA(255, 255, 220, 0))
        nvgBeginPath(vg)
        nvgRect(vg, shimX, topY + 38, sw, 40)
        nvgFillPaint(vg, sh2)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- ── 副标题横线装饰 ──
    local subY = topY + 94
    local lineW = 80
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - lineW - 30, subY + 1)
    nvgLineTo(vg, cx - 30, subY + 1)
    nvgStrokeColor(vg, nvgRGBA(80, 180, 255, 90))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + 30, subY + 1)
    nvgLineTo(vg, cx + lineW + 30, subY + 1)
    nvgStrokeColor(vg, nvgRGBA(80, 180, 255, 90))
    nvgStroke(vg)

    nvgFontSize(vg, 19)
    nvgFillColor(vg, nvgRGBA(120, 210, 255, 230))
    nvgText(vg, cx, subY, "Emoji Survivors")

    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 130))
    nvgText(vg, cx - 108, topY + 78, "⚔️")
    nvgText(vg, cx + 100, topY + 78, "🛡️")

    -- ── 昵称胶囊（霓虹边框版）──
    if SaveData.nickname then
        local nickText = "👋 " .. SaveData.nickname .. "  ✏️"
        nvgFontSize(vg, 16)
        local tw = nvgTextBounds(vg, 0, 0, nickText)
        local ebW = tw + 30
        local ebH = 36
        local ebX = cx - ebW / 2
        local ebY = topY + 112
        titleNickEditBtn = { x = ebX, y = ebY, w = ebW, h = ebH }
        -- 外发光
        local nickGlow = nvgBoxGradient(vg, ebX, ebY, ebW, ebH, 18, 8,
            nvgRGBA(100, 180, 255, 30), nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ebX - 4, ebY - 4, ebW + 8, ebH + 8, 22)
        nvgFillPaint(vg, nickGlow)
        nvgFill(vg)
        -- 主体
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ebX, ebY, ebW, ebH, 18)
        nvgFillColor(vg, nvgRGBA(20, 40, 80, 160))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 160, 255, 100))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFillColor(vg, nvgRGBA(200, 220, 255, 220))
        nvgText(vg, cx, ebY + ebH / 2, nickText)
    end

    -- ── 按钮区域（新游戏置顶，全宽）──
    local bX     = 16
    local bW     = DESIGN_W - 32
    local hasSave = SaveData.HasGameSave()
    local bAreaY = topY + 180

    -- ── 继续游戏按钮 ──
    if hasSave then
        local contH = 52
        titleContinueBtn = { x = bX, y = bAreaY, w = bW, h = contH, visible = true }
        local pulse = 0.75 + 0.25 * math.sin(t * 3)
        -- 纯色背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bX, bAreaY, bW, contH, 12)
        nvgFillColor(vg, nvgRGBA(14, 120, 72, math.floor(70 * pulse)))
        nvgFill(vg)
        -- 顶部高光线
        nvgBeginPath(vg)
        nvgMoveTo(vg, bX + 12, bAreaY + 1)
        nvgLineTo(vg, bX + bW - 12, bAreaY + 1)
        nvgStrokeColor(vg, nvgRGBA(150, 255, 200, 50))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 发光边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bX, bAreaY, bW, contH, 12)
        nvgStrokeColor(vg, nvgRGBA(50, 230, 140, math.floor(200 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        -- 左侧绿色竖条
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bX, bAreaY + 10, 4, contH - 20, 2)
        nvgFillColor(vg, nvgRGBA(50, 230, 140, 220))
        nvgFill(vg)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(200, 255, 220, math.floor(235 * pulse)))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, cx, bAreaY + contH / 2, I18n.t("charsel_continue"))
        bAreaY = bAreaY + contH + 10
    else
        titleContinueBtn.visible = false
    end

    -- ── 新游戏按钮（核心 CTA，最强视觉）──
    local newH = hasSave and 74 or 90
    titleNewGameBtn = { x = bX, y = bAreaY, w = bW, h = newH }
    local ngPulse = 0.78 + 0.22 * math.sin(t * 2.2)
    -- 纯色主体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bX, bAreaY, bW, newH, 16)
    nvgFillColor(vg, nvgRGBA(30, 20, 5, math.floor(200 * ngPulse)))
    nvgFill(vg)
    -- 发光边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bX, bAreaY, bW, newH, 16)
    nvgStrokeColor(vg, nvgRGBA(255, 220, 80, math.floor(255 * ngPulse)))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)
    -- 文字
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, hasSave and 34 or 40)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
    nvgText(vg, cx + 1, bAreaY + newH / 2 + 1, I18n.t("charsel_new"))
    nvgFillColor(vg, nvgRGBA(255, 230, 100, math.floor(255 * ngPulse)))
    nvgText(vg, cx, bAreaY + newH / 2, I18n.t("charsel_new"))
    bAreaY = bAreaY + newH + 14

    -- ── 2×3 功能卡片网格 ──
    local gM   = 14
    local gGap = 10
    local gW   = math.floor((DESIGN_W - gM * 2 - gGap) / 2)
    local gH   = 110
    local gX1  = gM
    local gX2  = gM + gW + gGap
    local gR1Y = bAreaY
    local gR2Y = bAreaY + gH + gGap
    local gR3Y = bAreaY + (gH + gGap) * 2
    local gR4Y = bAreaY + (gH + gGap) * 3
    local gR5Y = bAreaY + (gH + gGap) * 4

    -- 预计算各项进度
    local achUnlocked, achTotal = Achievement.GetProgress()
    local achAllDone = (achUnlocked == achTotal)

    -- 解锁判定：取本地与排行榜的较大值（防止云端回调时序导致本地值滞后）
    local bestWave = math.max(SaveData.highestWave, myCloudBestWave or 0)

    local totemOwned = #SaveData.totems
    local equippedCount = #SaveData.equippedTotems
    local totemLocked   = (bestWave < 20)

    local relicTotal    = #RelicSystem.RELICS
    local relicUnlocked = 0
    for _, r in ipairs(RelicSystem.RELICS) do
        if (SaveData.relicLevels[r.id] or 0) > 0 then relicUnlocked = relicUnlocked + 1 end
    end
    local relicLocked = (bestWave < 10)

    local icPad = 12   -- 图标左内边距
    local txOff = icPad + 44  -- 文字起始偏移

    -- ── 卡片 1：全球排行榜（左上）──
    titleLeaderboardBtn = { x = gX1, y = gR1Y, w = gW, h = gH }
    DrawCard(gX1, gR1Y, gW, gH,
        nvgRGBA(12, 28, 58, 215),
        nvgRGBA(255, 190, 70, 130),
        { 255, 190, 70 })

    DrawIconBase(gX1 + icPad + 16, gR1Y + gH / 2, 24, 255, 190, 70)
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 215))
    nvgText(vg, gX1 + icPad, gR1Y + gH / 2, "🌐")

    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 200, 80, 220))
    nvgText(vg, gX1 + txOff, gR1Y + 14, I18n.t("card_leaderboard"))

    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 160))
    if myCloudBestWave and myCloudBestWave > 0 then
        nvgFontFaceId(vg, zpix)
        nvgText(vg, gX1 + txOff, gR1Y + 40, I18n.t("card_best_wave", myCloudBestWave))
        nvgFontFaceId(vg, zpix)
    else
        nvgText(vg, gX1 + txOff, gR1Y + 40, I18n.t("card_lb_view"))
    end
    if #SaveData.highScores > 0 then
        local hs = SaveData.highScores[1]
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(170, 170, 190, 130))
        nvgFontFaceId(vg, zpix)
        nvgText(vg, gX1 + txOff, gR1Y + 64, I18n.t("card_local_best", hs.wave, hs.level or 1))
        nvgFontFaceId(vg, zpix)
    end

    -- ── 卡片 2：成就（右上）──
    titleAchievementBtn = { x = gX2, y = gR1Y, w = gW, h = gH }
    local achAccent = achAllDone and { 255, 220, 50 } or { 180, 140, 255 }
    local achStroke = achAllDone and nvgRGBA(255, 220, 50, 150) or nvgRGBA(180, 140, 255, 130)
    DrawCard(gX2, gR1Y, gW, gH, nvgRGBA(20, 12, 45, 215), achStroke, achAccent)

    DrawIconBase(gX2 + icPad + 16, gR1Y + gH / 2, 24, achAccent[1], achAccent[2], achAccent[3])
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 215))
    nvgText(vg, gX2 + icPad, gR1Y + gH / 2, achAllDone and "🏆" or "🥈")

    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    if achAllDone then
        nvgFillColor(vg, nvgRGBA(255, 220, 50, 220))
    else
        nvgFillColor(vg, nvgRGBA(180, 140, 255, 220))
    end
    nvgText(vg, gX2 + txOff, gR1Y + 14, I18n.t("card_achievement"))

    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 170))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, gX2 + txOff, gR1Y + 40, I18n.t("card_unlocked_fmt", achUnlocked, achTotal))
    nvgFontFaceId(vg, zpix)

    -- 进度条
    local barW = gW - txOff - 10
    local barX = gX2 + txOff
    local barY = gR1Y + 74
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, 5, 2)
    nvgFillColor(vg, nvgRGBA(80, 80, 100, 100))
    nvgFill(vg)
    if achTotal > 0 then
        local pct = achUnlocked / achTotal
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * pct, 5, 2)
        nvgFillColor(vg, achAllDone and nvgRGBA(255, 220, 50, 200) or nvgRGBA(160, 120, 255, 200))
        nvgFill(vg)
    end

    -- ── 卡片 3：遗物商店（左下）──
    titleRelicShopBtn = { x = gX1, y = gR2Y, w = gW, h = gH }
    local relicAccent = relicLocked and { 100, 110, 130 } or { 80, 200, 255 }
    local relicStroke = relicLocked and nvgRGBA(100, 110, 130, 70) or nvgRGBA(80, 200, 255, 140)
    DrawCard(gX1, gR2Y, gW, gH, nvgRGBA(10, 35, 65, 215), relicStroke, relicAccent)

    DrawIconBase(gX1 + icPad + 16, gR2Y + gH / 2 - 12, 22, relicAccent[1], relicAccent[2], relicAccent[3])
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, relicLocked and 80 or 220))
    nvgText(vg, gX1 + icPad, gR2Y + gH / 2 - 12, "🛒")

    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    if relicLocked then
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 160))
    else
        nvgFillColor(vg, nvgRGBA(100, 215, 255, 230))
    end
    nvgText(vg, gX1 + txOff, gR2Y + 14, I18n.t("card_relic_shop"))

    nvgFontSize(vg, 15)
    if relicLocked then
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 130))
        nvgFontFaceId(vg, zpix)
        nvgText(vg, gX1 + txOff, gR2Y + 40, I18n.t("card_wave_unlock", 10))
        nvgFontFaceId(vg, zpix)
    else
        nvgFillColor(vg, nvgRGBA(160, 195, 225, 170))
        nvgFontFaceId(vg, zpix)
        nvgText(vg, gX1 + txOff, gR2Y + 40, I18n.t("card_relic_unlocked", relicUnlocked, relicTotal))
        nvgFontFaceId(vg, zpix)
    end

    -- 遗物图标行
    if not relicLocked then
        local riX = gX1 + txOff
        local riY = gR2Y + 76
        for _, r in ipairs(RelicSystem.RELICS) do
            local lv = SaveData.relicLevels[r.id] or 0
            nvgFontSize(vg, 18)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, lv > 0 and 220 or 50))
            nvgText(vg, riX, riY, r.icon)
            if lv > 0 then
                nvgFontSize(vg, 9)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(255, 210, 80, 200))
                nvgFontFaceId(vg, zpix)
                nvgText(vg, riX + 1, riY + 9, "L" .. lv)
                nvgFontFaceId(vg, zpix)
            end
            riX = riX + 28
        end
    end

    -- 右上角金币
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 205, 80, 200))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, gX1 + gW - 8, gR2Y + 10, I18n.t("card_gold_badge", SaveData.metaGold))
    nvgFontFaceId(vg, zpix)

    -- ── 卡片 4：图腾商店（右下）──
    titleTotemShopBtn = { x = gX2, y = gR2Y, w = gW, h = gH }
    local totemAccent = totemLocked and { 100, 110, 130 } or { 170, 120, 255 }
    local totemStroke = totemLocked and nvgRGBA(100, 110, 130, 70) or nvgRGBA(170, 120, 255, 140)
    DrawCard(gX2, gR2Y, gW, gH, nvgRGBA(28, 12, 55, 215), totemStroke, totemAccent)

    DrawIconBase(gX2 + icPad + 16, gR2Y + gH / 2 - 12, 22, totemAccent[1], totemAccent[2], totemAccent[3])
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, totemLocked and 80 or 220))
    nvgText(vg, gX2 + icPad, gR2Y + gH / 2 - 12, "🏺")

    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    if totemLocked then
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 160))
    else
        nvgFillColor(vg, nvgRGBA(190, 140, 255, 230))
    end
    nvgText(vg, gX2 + txOff, gR2Y + 14, I18n.t("card_totem_shop"))

    nvgFontSize(vg, 15)
    if totemLocked then
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 130))
        nvgFontFaceId(vg, zpix)
        nvgText(vg, gX2 + txOff, gR2Y + 40, I18n.t("card_wave_unlock", 20))
        nvgFontFaceId(vg, zpix)
    else
        nvgFillColor(vg, nvgRGBA(180, 160, 225, 170))
        nvgFontFaceId(vg, zpix)
        nvgText(vg, gX2 + txOff, gR2Y + 40, I18n.t("card_totem_status", equippedCount, totemOwned))
        nvgFontFaceId(vg, zpix)
    end

    -- 装备槽显示（新图腾系统）
    if not totemLocked then
        local slX = gX2 + txOff
        local slY = gR2Y + 72
        local slW = 44
        local slH = 30
        for i = 1, TotemSystem.MAX_EQUIPPED do
            local totem = SaveData.equippedTotems[i]
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slX, slY, slW, slH, 6)
            if totem then
                local rc = TotemSystem.GetRarityConfig(totem.rarity)
                local c = rc.color
                nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 40))
            else
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 10))
            end
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(170, 120, 255, totem and 110 or 40))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            if totem then
                nvgFontSize(vg, 18)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
                nvgText(vg, slX + slW / 2, slY + slH / 2, TotemSystem.GetTotemIcon(totem.typeId))
            else
                nvgFontSize(vg, 12)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 180, 255, 50))
                nvgText(vg, slX + slW / 2, slY + slH / 2, I18n.t("card_slot_empty"))
            end
            slX = slX + slW + 6
        end
    end

    -- 右上角装备数
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(190, 150, 255, 200))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, gX2 + gW - 8, gR2Y + 10, I18n.t("card_totem_badge", equippedCount))
    nvgFontFaceId(vg, zpix)

    -- ── 卡片 5：符文管理（左下第三行）──
    local runeOwned = RuneSystem.GetOwnedCount(SaveData.ownedRunes)
    local runeTotal = RuneSystem.GetTotalCount()
    local runeEquipped = 0
    for _ , rid in ipairs(SaveData.equippedRunes) do
        if rid then runeEquipped = runeEquipped + 1 end
    end
    local runeLocked = (bestWave < 20)

    titleRuneShopBtn = { x = gX1, y = gR3Y, w = gW, h = gH }
    local runeAccent = runeLocked and { 100, 110, 130 } or { 255, 80, 80 }
    local runeStroke = runeLocked and nvgRGBA(100, 110, 130, 70) or nvgRGBA(255, 80, 80, 140)
    DrawCard(gX1, gR3Y, gW, gH, nvgRGBA(40, 12, 12, 215), runeStroke, runeAccent)

    DrawIconBase(gX1 + icPad + 16, gR3Y + gH / 2 - 6, 22, runeAccent[1], runeAccent[2], runeAccent[3])
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, runeLocked and 80 or 220))
    nvgText(vg, gX1 + icPad, gR3Y + gH / 2 - 6, "🔮")

    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    if runeLocked then
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 160))
    else
        nvgFillColor(vg, nvgRGBA(255, 120, 120, 230))
    end
    nvgText(vg, gX1 + txOff, gR3Y + 14, I18n.t("card_rune_mgr"))

    nvgFontSize(vg, 15)
    if runeLocked then
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 130))
        nvgFontFaceId(vg, zpix)
        nvgText(vg, gX1 + txOff, gR3Y + 40, I18n.t("card_wave_unlock", 20))
        nvgFontFaceId(vg, zpix)
    else
        nvgFillColor(vg, nvgRGBA(220, 160, 160, 170))
        nvgFontFaceId(vg, zpix)
        nvgText(vg, gX1 + txOff, gR3Y + 40, I18n.t("card_rune_collected", runeOwned, runeTotal))
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(200, 150, 150, 130))
        nvgFontFaceId(vg, zpix)
        nvgText(vg, gX1 + txOff, gR3Y + 64, I18n.t("card_rune_equipped", runeEquipped, RuneSystem.MAX_EQUIPPED))
        nvgFontFaceId(vg, zpix)
    end

    -- 右上角符文数
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 120, 120, 200))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, gX1 + gW - 8, gR3Y + 10, I18n.t("card_rune_badge", runeEquipped, RuneSystem.MAX_EQUIPPED))
    nvgFontFaceId(vg, zpix)

    -- ── 卡片 6：皮肤商店（右下第三行）──
    local skinOwned = SkinSystem.GetOwnedCount(SaveData.ownedSkins)
    local skinTotal = SkinSystem.GetTotalCount()

    titleSkinShopBtn = { x = gX2, y = gR3Y, w = gW, h = gH }
    DrawCard(gX2, gR3Y, gW, gH, nvgRGBA(35, 28, 8, 215), nvgRGBA(255, 200, 60, 140), { 255, 200, 60 })
    DrawIconBase(gX2 + icPad + 16, gR3Y + gH / 2 - 6, 22, 255, 200, 60)

    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgText(vg, gX2 + icPad, gR3Y + gH / 2 - 6, "🎨")

    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 210, 80, 230))
    nvgText(vg, gX2 + txOff, gR3Y + 14, I18n.t("card_skin_shop"))

    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(220, 200, 140, 170))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, gX2 + txOff, gR3Y + 40, I18n.t("card_skin_owned", skinOwned, skinTotal))
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(200, 180, 120, 130))
    nvgText(vg, gX2 + txOff, gR3Y + 64, I18n.t("card_skin_change"))

    -- 右上角皮肤数
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 210, 80, 200))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, gX2 + gW - 8, gR3Y + 10, I18n.t("card_skin_badge", skinOwned, skinTotal))
    nvgFontFaceId(vg, zpix)

    -- ── 卡片 7：图鉴收集册（第四行，全宽）──
    local cdxUnlocked, cdxTotal = Codex.GetProgress()
    local fullW = gW * 2 + gGap
    titleCodexBtn = { x = gX1, y = gR4Y, w = fullW, h = gH }
    DrawCard(gX1, gR4Y, fullW, gH, nvgRGBA(15, 30, 45, 215), nvgRGBA(100, 180, 255, 140), { 80, 180, 255 })
    DrawIconBase(gX1 + icPad + 16, gR4Y + gH / 2 - 6, 22, 80, 180, 255)

    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgText(vg, gX1 + icPad, gR4Y + gH / 2 - 6, "📖")

    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 230))
    nvgText(vg, gX1 + txOff, gR4Y + 14, I18n.t("card_codex"))

    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(150, 190, 220, 170))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, gX1 + txOff, gR4Y + 40, I18n.t("card_codex_found", cdxUnlocked, cdxTotal))
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(130, 160, 190, 130))
    nvgText(vg, gX1 + txOff, gR4Y + 64, I18n.t("card_codex_hint"))

    -- 右上角进度百分比
    local cdxPct = cdxTotal > 0 and math.floor(cdxUnlocked / cdxTotal * 100) or 0
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 200))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, gX1 + fullW - 8, gR4Y + 10, cdxPct .. "%")
    nvgFontFaceId(vg, zpix)

    -- 进度条
    local cBarX = gX1 + fullW - 130
    local cBarY = gR4Y + gH - 22
    local cBarW = 118
    local cBarH = 8
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cBarX, cBarY, cBarW, cBarH, 4)
    nvgFillColor(vg, nvgRGBA(40, 50, 60, 180))
    nvgFill(vg)
    if cdxTotal > 0 then
        local fillW = math.floor(cBarW * cdxUnlocked / cdxTotal)
        if fillW > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cBarX, cBarY, fillW, cBarH, 4)
            nvgFillColor(vg, nvgRGBA(80, 180, 255, 220))
            nvgFill(vg)
        end
    end

    -- ── 卡片 8：周挑战赛季（第五行，全宽）──
    local wcRule = WeeklyChallenge.GetTodayRule()
    local wcPts = WeeklyChallenge.seasonPoints
    local wcPct = WeeklyChallenge.GetProgressPct()
    local wcDays = WeeklyChallenge.GetDaysRemaining()
    local fullW2 = gW * 2 + gGap
    titleWeeklyBtn = { x = gX1, y = gR5Y, w = fullW2, h = gH }

    local wcR, wcG, wcB = wcRule.color[1], wcRule.color[2], wcRule.color[3]
    DrawCard(gX1, gR5Y, fullW2, gH, nvgRGBA(math.floor(wcR * 0.1), math.floor(wcG * 0.1), math.floor(wcB * 0.1), 215),
        nvgRGBA(wcR, wcG, wcB, 160), { wcR, wcG, wcB })
    DrawIconBase(gX1 + icPad + 16, gR5Y + gH / 2 - 6, 22, wcR, wcG, wcB)

    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgText(vg, gX1 + icPad, gR5Y + gH / 2 - 6, "🏆")

    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(wcR, wcG, wcB, 240))
    nvgText(vg, gX1 + txOff, gR5Y + 14, I18n.t("card_weekly"))

    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 180))
    nvgText(vg, gX1 + txOff, gR5Y + 40,
        I18n.t("card_weekly_today_fmt", wcRule.icon, wcRule.name))
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(160, 160, 180, 140))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, gX1 + txOff, gR5Y + 64,
        wcDays > 0 and I18n.t("card_weekly_score_days", wcPts, wcDays) or I18n.t("card_weekly_last_day", wcPts))
    nvgFontFaceId(vg, zpix)

    -- 右上角赛季ID
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(wcR, wcG, wcB, 180))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, gX1 + fullW2 - 8, gR5Y + 10, WeeklyChallenge.seasonId)
    nvgFontFaceId(vg, zpix)

    -- 进度条
    local wBarX = gX1 + fullW2 - 130
    local wBarY = gR5Y + gH - 22
    local wBarW = 118
    local wBarH = 8
    nvgBeginPath(vg)
    nvgRoundedRect(vg, wBarX, wBarY, wBarW, wBarH, 4)
    nvgFillColor(vg, nvgRGBA(40, 40, 50, 180))
    nvgFill(vg)
    if wcPct > 0 then
        local fillW = math.floor(wBarW * wcPct / 100)
        if fillW > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, wBarX, wBarY, fillW, wBarH, 4)
            nvgFillColor(vg, nvgRGBA(wcR, wcG, wcB, 220))
            nvgFill(vg)
        end
    end

    -- ── 充值 / 重试联机 ──
    local extraY = gR5Y + gH + 12
    titleRechargeBtn = { x = gX1, y = extraY, w = gW, h = 56 }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, titleRechargeBtn.x, titleRechargeBtn.y, titleRechargeBtn.w, titleRechargeBtn.h, 12)
    nvgFillColor(vg, nvgRGBA(40, 28, 8, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 80, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 230, 120, 255))
    nvgText(vg, titleRechargeBtn.x + titleRechargeBtn.w / 2, titleRechargeBtn.y + 28, I18n.t("iap_entry"))

    if GameMode.IsOffline() then
        titleRetryOnlineBtn = { x = gX2, y = extraY, w = gW, h = 56, visible = true }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, titleRetryOnlineBtn.x, titleRetryOnlineBtn.y, titleRetryOnlineBtn.w, titleRetryOnlineBtn.h, 12)
        nvgFillColor(vg, nvgRGBA(12, 40, 70, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 180, 255, 180))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFillColor(vg, nvgRGBA(160, 220, 255, 255))
        nvgText(vg, titleRetryOnlineBtn.x + titleRetryOnlineBtn.w / 2, titleRetryOnlineBtn.y + 28, I18n.t("retry_online"))
    else
        titleRetryOnlineBtn.visible = false
        titleRetryOnlineBtn.w = 0
    end

    -- emoji 阵列装饰（底部）
    nvgFontSize(vg, 22)
    local emojis = { "👾", "🦇", "🐻", "👹", "💣", "❤️", "🪙", "🧲" }
    local startX = cx - (#emojis - 1) * 22
    for i, em in ipairs(emojis) do
        local ey = DESIGN_H - 80 + math.sin(t * 3 + i * 0.8) * 5
        nvgText(vg, startX + (i - 1) * 44, ey, em)
    end

    -- 版本信息
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(120, 120, 140, 150))
    nvgFontFaceId(vg, zpix)
    nvgText(vg, cx, DESIGN_H - 30, I18n.t("game_version"))
    nvgFontFaceId(vg, zpix)

    -- ── 点击闪光 ripple ──
    if titleFlash > 0 then
        local fp = titleFlash / 0.22           -- 归一化 1→0
        local radius = 160 * (1.2 - fp * 0.8) -- 随时间扩散
        local glow = nvgRadialGradient(vg, titleFlashX, titleFlashY, 0, radius,
            nvgRGBA(255, 240, 160, math.floor(55 * fp)),
            nvgRGBA(255, 200, 80, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
        -- 中心亮点
        nvgBeginPath(vg)
        nvgCircle(vg, titleFlashX, titleFlashY, 18 * fp)
        nvgFillColor(vg, nvgRGBA(255, 255, 220, math.floor(90 * fp)))
        nvgFill(vg)
    end
end

-- ============================================================================
-- 全球排行榜画面
-- ============================================================================

function RenderLeaderboard()
    local bg = Config.COLORS.bg
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
    nvgFill(vg)

    local cx = DESIGN_W / 2
    local t = time.elapsedTime

    nvgFontFaceId(vg, zpix)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 标题
    nvgFontSize(vg, 36)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, cx, 50, I18n.t("lb_title"))

    -- 标签页切换按钮（3个标签）
    local tabCount = 3
    local tabGap = 6
    local totalTabW = DESIGN_W - 40  -- 两侧各留20
    local tabW = math.floor((totalTabW - tabGap * (tabCount - 1)) / tabCount)
    local tabH = 34
    local tabY = 80
    local tabStartX = 20
    local tab1X = tabStartX
    local tab2X = tabStartX + tabW + tabGap
    local tab3X = tabStartX + (tabW + tabGap) * 2
    lbTabBtn1 = { x = tab1X, y = tabY, w = tabW, h = tabH }
    lbTabBtn2 = { x = tab2X, y = tabY, w = tabW, h = tabH }
    lbTabBtn3 = { x = tab3X, y = tabY, w = tabW, h = tabH }

    local tabLabels = { I18n.t("lb_tab_wave"), I18n.t("lb_tab_kills"), I18n.t("lb_tab_daily") }
    local tabXs = { tab1X, tab2X, tab3X }
    local tabIds = { LB_TAB_WAVE, LB_TAB_KILLS, LB_TAB_DAILY }

    for idx = 1, tabCount do
        local tx = tabXs[idx]
        local isActive = (lbCurrentTab == tabIds[idx])

        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, tabY, tabW, tabH, 8)
        if isActive then
            if idx == 3 then
                nvgFillColor(vg, nvgRGBA(100, 200, 255, 40))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 180))
            else
                nvgFillColor(vg, nvgRGBA(255, 220, 100, 40))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(255, 220, 100, 180))
            end
        else
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 8))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(150, 150, 180, 60))
        end
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontSize(vg, 14)
        if isActive then
            if idx == 3 then
                nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
            else
                nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
            end
        else
            nvgFillColor(vg, nvgRGBA(180, 180, 200, 150))
        end
        nvgText(vg, tx + tabW / 2, tabY + tabH / 2, tabLabels[idx])
    end

    -- 副标题
    local subtitleText
    if lbCurrentTab == LB_TAB_DAILY then
        local cfg = DailyChallenge.GetTodayConfig()
        subtitleText = I18n.t("lb_subtitle_daily_fmt", cfg.dateKey)
    elseif lbCurrentTab == LB_TAB_KILLS then
        subtitleText = I18n.t("lb_subtitle_kills")
    else
        subtitleText = I18n.t("lb_subtitle_wave")
    end
    if leaderboardData and #leaderboardData > 0 then
        subtitleText = subtitleText .. I18n.t("lb_count_fmt", leaderboardTotal)
    end
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(150, 150, 180, 120))
    nvgText(vg, cx, tabY + tabH + 16, subtitleText)

    -- 布局常量
    local headerY = tabY + tabH + 36
    local listTop = headerY + 28     -- 列表内容起始Y
    local listBottom = DESIGN_H - 120 -- 列表底部（留空给返回按钮）
    local listH = listBottom - listTop
    local rowH = 40

    if leaderboardLoading then
        local dots = string.rep(".", math.floor(t * 2) % 4)
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(200, 200, 220, 180))
        nvgText(vg, cx, DESIGN_H / 2, I18n.t("lb_loading") .. dots)
    elseif leaderboardError then
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(255, 100, 100, 200))
        nvgText(vg, cx, DESIGN_H / 2 - 20, I18n.t("lb_error_prefix") .. leaderboardError)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, 150))
        nvgText(vg, cx, DESIGN_H / 2 + 15, I18n.t("lb_retry"))
    elseif leaderboardData and #leaderboardData > 0 then
        -- 表头（固定不滚动）
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(150, 150, 180, 150))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, 30, headerY, I18n.t("lb_rank"))
        nvgText(vg, 80, headerY, I18n.t("lb_player"))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        if lbCurrentTab == LB_TAB_DAILY then
            nvgText(vg, DESIGN_W - 30, headerY, I18n.t("lb_wave"))
        elseif lbCurrentTab == LB_TAB_WAVE then
            nvgText(vg, DESIGN_W - 110, headerY, I18n.t("lb_wave"))
            nvgText(vg, DESIGN_W - 30, headerY, I18n.t("lb_kills"))
        else
            nvgText(vg, DESIGN_W - 110, headerY, I18n.t("lb_kills"))
            nvgText(vg, DESIGN_W - 30, headerY, I18n.t("lb_wave"))
        end

        nvgBeginPath(vg)
        nvgMoveTo(vg, 20, headerY + 14)
        nvgLineTo(vg, DESIGN_W - 20, headerY + 14)
        nvgStrokeColor(vg, nvgRGBA(100, 100, 140, 60))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 滚动裁剪区域
        nvgSave(vg)
        nvgScissor(vg, 0, listTop, DESIGN_W, listH)

        -- 计算内容总高度和滚动上限
        local contentH = #leaderboardData * rowH
        local maxScroll = math.max(0, contentH - listH)

        -- 限制滚动范围
        lbScrollY = math.max(0, math.min(lbScrollY, maxScroll))

        -- 接近底部时自动加载更多
        if leaderboardHasMore and not leaderboardLoadingMore and lbScrollY > maxScroll - 200 then
            LoadLeaderboard(true)
        end

        local medals = { "🥇", "🥈", "🥉" }

        -- 只渲染可见行（性能优化）
        local firstVisible = math.max(1, math.floor(lbScrollY / rowH))
        local lastVisible = math.min(#leaderboardData, firstVisible + math.ceil(listH / rowH) + 2)

        for i = firstVisible, lastVisible do
            local entry = leaderboardData[i]
            local ry = listTop + (i - 1) * rowH - lbScrollY + rowH / 2

            -- 超出裁剪区跳过
            if ry > listTop - rowH and ry < listBottom + rowH then
                local isMe = entry.isMe

                -- 自己的行高亮
                if isMe then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, 16, ry - rowH / 2 + 2, DESIGN_W - 32, rowH - 4, 8)
                    nvgFillColor(vg, nvgRGBA(50, 200, 120, 25))
                    nvgFill(vg)
                end

                -- 排名
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFontSize(vg, 18)
                if medals[entry.rank] then
                    nvgText(vg, 48, ry, medals[entry.rank])
                else
                    nvgFontSize(vg, 14)
                    nvgFillColor(vg, nvgRGBA(150, 150, 180, 180))
                    nvgText(vg, 48, ry, "#" .. entry.rank)
                end

                -- 昵称
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFontSize(vg, 15)
                if isMe then
                    nvgFillColor(vg, nvgRGBA(100, 255, 160, 255))
                else
                    nvgFillColor(vg, nvgRGBA(220, 220, 240, 220))
                end
                local displayName = entry.nickname
                if isMe then displayName = displayName .. I18n.t("lb_me_suffix") end
                if #displayName > 24 then
                    displayName = string.sub(displayName, 1, 21) .. "..."
                end
                nvgText(vg, 80, ry, displayName)

                -- 主排序列 + 副列
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFontSize(vg, 15)
                if lbCurrentTab == LB_TAB_DAILY then
                    nvgFillColor(vg, nvgRGBA(100, 200, 255, 220))
                    nvgText(vg, DESIGN_W - 30, ry, "W" .. entry.wave)
                elseif lbCurrentTab == LB_TAB_WAVE then
                    nvgFillColor(vg, nvgRGBA(255, 220, 100, 220))
                    nvgText(vg, DESIGN_W - 110, ry, "W" .. entry.wave)
                    nvgFillColor(vg, nvgRGBA(200, 200, 220, 180))
                    nvgText(vg, DESIGN_W - 30, ry, tostring(entry.kills))
                else
                    nvgFillColor(vg, nvgRGBA(255, 140, 100, 220))
                    nvgText(vg, DESIGN_W - 110, ry, tostring(entry.kills))
                    nvgFillColor(vg, nvgRGBA(200, 200, 220, 180))
                    nvgText(vg, DESIGN_W - 30, ry, "W" .. entry.wave)
                end
            end
        end

        -- 加载更多提示
        if leaderboardLoadingMore then
            local loadY = listTop + contentH - lbScrollY + 20
            if loadY > listTop and loadY < listBottom then
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFontSize(vg, 14)
                nvgFillColor(vg, nvgRGBA(180, 180, 200, 150))
                local dots = string.rep(".", math.floor(t * 3) % 4)
                nvgText(vg, cx, loadY, I18n.t("lb_load_more_loading") .. dots)
            end
        elseif not leaderboardHasMore and #leaderboardData > 10 then
            local endY = listTop + contentH - lbScrollY + 20
            if endY > listTop and endY < listBottom then
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFontSize(vg, 13)
                nvgFillColor(vg, nvgRGBA(140, 140, 160, 100))
                nvgText(vg, cx, endY, I18n.t("lb_all_loaded"))
            end
        end

        nvgRestore(vg)

        -- 滚动条指示器
        if maxScroll > 0 then
            local scrollBarH = math.max(30, listH * (listH / contentH))
            local scrollBarY = listTop + (lbScrollY / maxScroll) * (listH - scrollBarH)
            local scrollBarAlpha = (lbDragStartY or lbScrollVel ~= 0) and 80 or 30
            nvgBeginPath(vg)
            nvgRoundedRect(vg, DESIGN_W - 8, scrollBarY, 4, scrollBarH, 2)
            nvgFillColor(vg, nvgRGBA(200, 200, 220, scrollBarAlpha))
            nvgFill(vg)
        end
    else
        -- 空排行榜
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, 150))
        nvgText(vg, cx, DESIGN_H / 2, I18n.t("lb_empty"))
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 120))
        nvgText(vg, cx, DESIGN_H / 2 + 30, I18n.t("lb_empty_hint"))
    end

    -- 返回按钮
    local backW = 200
    local backH = 48
    local backX = cx - backW / 2
    local backY = DESIGN_H - 90
    leaderboardBackBtn = { x = backX, y = backY, w = backW, h = backH }

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
    nvgText(vg, cx, backY + backH / 2, I18n.t("lb_back"))
end

-- ============================================================================
-- 角色选择画面
-- ============================================================================

-- 角色卡片布局参数（单卡翻页模式）
local CARD_W = 380
local CARD_H = 460
local CARD_START_Y = 145

-- 左右箭头区域
local ARROW_SIZE = 50
local ARROW_Y_CENTER = CARD_START_Y + CARD_H / 2

--- 单卡布局底部 Y
local CARDS_BOTTOM_Y = CARD_START_Y + CARD_H + 16

function RenderCharSelect()
    local bg = Config.COLORS.bg
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
    nvgFill(vg)


    -- 背景粒子
    local t = time.elapsedTime
    for i = 1, 20 do
        local sx = (i * 113 + math.sin(t * 0.4 + i) * 40) % DESIGN_W
        local sy = (i * 79 + math.cos(t * 0.25 + i * 1.5) * 30) % DESIGN_H
        local sa = 30 + math.floor(math.sin(t * 1.5 + i * 2) * 25)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, 2)
        nvgFillColor(vg, nvgRGBA(200, 200, 255, sa))
        nvgFill(vg)
    end

    local cx = DESIGN_W / 2

    -- 标题
    nvgFontFaceId(vg, zpix)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 36)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, cx, 80, I18n.t("charsel_title"))

    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 180))
    nvgText(vg, cx, 120, I18n.t("charsel_subtitle"))

    -- 当前选中角色（单卡展示）
    local chars = Config.CHARACTERS
    local total = #chars
    local i = selectedCharIdx
    local ch = chars[i]
    local col = ch.color

    local DN = DamageNumber  -- zpix 白边文字绘制

    local cardX = (DESIGN_W - CARD_W) / 2
    local cardY = CARD_START_Y
    local cw = CARD_W
    local ch2 = CARD_H

    -- 选中光晕
    local pulse = 0.6 + 0.4 * math.sin(t * 4)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX - 5, cardY - 5, cw + 10, ch2 + 10, 18)
    nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], math.floor(30 + 25 * pulse)))
    nvgFill(vg)

    -- 卡片背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX, cardY, cw, ch2, 14)
    nvgFillColor(vg, nvgRGBA(25, 20, 50, 235))
    nvgFill(vg)

    -- 边框
    nvgStrokeColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    local midX = cardX + cw / 2

    -- emoji 居中显示
    local emojiY = cardY + 60 + math.sin(t * 2 + i * 1.5) * 5
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 72)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, midX, emojiY, ch.emoji)

    -- 角色名（居中）
    nvgFontSize(vg, 26)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
    nvgText(vg, midX, cardY + 110, ch.name)

    -- 角色描述
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 180))
    nvgText(vg, midX, cardY + 138, ch.desc)

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, cardX + 20, cardY + 158)
    nvgLineTo(vg, cardX + cw - 20, cardY + 158)
    nvgStrokeColor(vg, nvgRGBA(col[1], col[2], col[3], 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 属性条（HP / ATK / SPD / CRIT）
    local stats = ch.stats
    local P = Config.PLAYER
    local barLabels = { "HP", "ATK", "SPD", "CRT" }
    local barValues = { stats.hp, stats.atk, stats.speed, stats.critRate }
    local barActual = {
        tostring(math.floor(P.baseHp * stats.hp)),
        string.format("%.1f", P.baseAtk * stats.atk),
        tostring(math.floor(P.baseSpeed * stats.speed)),
        math.floor(P.baseCritRate * stats.critRate * 100) .. "%",
    }
    local barColors = {
        { 50, 255, 100 }, { 255, 100, 80 }, { 100, 200, 255 }, { 255, 200, 50 }
    }

    local barStartY = cardY + 172
    local barSpacing = 32
    local bh = 20
    local labelW = 50
    local bx = cardX + labelW + 12
    local bw = cw - labelW - 30

    for j = 1, 4 do
        local by = barStartY + (j - 1) * barSpacing
        local barMidY = by + bh / 2

        -- 标签
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, 220))
        nvgText(vg, cardX + 14, barMidY, barLabels[j])
        nvgFontFaceId(vg, zpix)

        -- 属性条背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw, bh, 5)
        nvgFillColor(vg, nvgRGBA(40, 30, 60, 200))
        nvgFill(vg)

        -- 属性条填充
        local ratio = math.min(1.0, barValues[j] / 1.5)
        local bc = barColors[j]
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw * ratio, bh, 5)
        nvgFillColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 200))
        nvgFill(vg)

        -- zpix 白边黑字数值（叠在条上方）
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        DN.DrawOutlinedText(vg, bx + bw / 2, barMidY,
            barLabels[j] .. " " .. barActual[j], 14, 0, 0, 0, 255, 1.2)
    end

    -- 专属技能预览
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 150))
    nvgText(vg, midX, cardY + ch2 - 50, I18n.t("charsel_skill_label"))

    -- 技能图标 + 技能名
    local exSkills = ch.exclusiveSkills
    local skillGap = 36
    local skillW = #exSkills * skillGap
    local skillStartX = midX - skillW / 2

    for k, sid in ipairs(exSkills) do
        local icon = "?"
        local skillName = ""
        for _, def in ipairs(Config.SKILLS) do
            if def.id == sid then icon = def.icon; skillName = def.name; break end
        end
        local skx = skillStartX + (k - 1) * skillGap + skillGap / 2
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 230))
        nvgText(vg, skx, cardY + ch2 - 24, icon)
    end

    -- 页码指示器（圆点）
    local dotR = 5
    local dotGap = 18
    local dotsW = total * dotGap
    local dotsStartX = cx - dotsW / 2

    for d = 1, total do
        local dotX = dotsStartX + (d - 1) * dotGap + dotGap / 2
        local dotY = cardY + ch2 + 12
        nvgBeginPath(vg)
        nvgCircle(vg, dotX, dotY, d == i and dotR or (dotR - 1.5))
        if d == i then
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(120, 120, 140, 120))
        end
        nvgFill(vg)
    end

    -- 左箭头
    local arrowMargin = 14
    local leftArrowX = cardX - ARROW_SIZE - arrowMargin
    local arrowY = ARROW_Y_CENTER - ARROW_SIZE / 2

    if total > 1 then
        -- 左箭头背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, leftArrowX, arrowY, ARROW_SIZE, ARROW_SIZE, 10)
        nvgFillColor(vg, nvgRGBA(40, 35, 70, 180))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(col[1], col[2], col[3], 100))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, leftArrowX + ARROW_SIZE / 2, arrowY + ARROW_SIZE / 2, "◀")

        -- 右箭头背景
        local rightArrowX = cardX + cw + arrowMargin
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rightArrowX, arrowY, ARROW_SIZE, ARROW_SIZE, 10)
        nvgFillColor(vg, nvgRGBA(40, 35, 70, 180))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(col[1], col[2], col[3], 100))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontSize(vg, 28)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, rightArrowX + ARROW_SIZE / 2, arrowY + ARROW_SIZE / 2, "▶")
    end

    -- 检查当前角色是否锁定
    local isLocked = not SaveData.IsCharUnlocked(ch.id)

    -- 锁定遮罩
    if isLocked then
        local unlockType = SaveData.GetUnlockType(ch.id)
        local unlockText = SaveData.GetUnlockText(ch.id)

        -- 半透明暗色遮罩
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cardY, cw, ch2, 14)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)

        -- 锁图标
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 56)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if unlockType == "wave" then
            nvgFillColor(vg, nvgRGBA(100, 200, 255, 220))
        else
            nvgFillColor(vg, nvgRGBA(255, 200, 80, 220))
        end
        nvgText(vg, midX, cardY + ch2 / 2 - 30, "🔒")

        -- 锁定提示文字
        nvgFontSize(vg, 18)
        if unlockType == "wave" then
            nvgFillColor(vg, nvgRGBA(130, 210, 255, 230))
            nvgText(vg, midX, cardY + ch2 / 2 + 20, unlockText)
            -- 当前进度
            local cond = SaveData.UNLOCK_CONDITIONS[ch.id]
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(180, 200, 220, 150))
            local bestW = math.max(SaveData.highestWave, myCloudBestWave or 0)
            nvgFontFaceId(vg, zpix)
            nvgText(vg, midX, cardY + ch2 / 2 + 46, I18n.t("card_best_wave_cur", bestW))
            nvgFontFaceId(vg, zpix)
        else
            nvgFillColor(vg, nvgRGBA(255, 220, 130, 230))
            nvgText(vg, midX, cardY + ch2 / 2 + 20, unlockText)
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(200, 200, 220, 150))
            nvgText(vg, midX, cardY + ch2 / 2 + 46, I18n.t("charsel_unlock_msg2"))
        end
    end

    -- 底部按钮区域
    local btnW = 300
    local btnH = 56
    local btnX = (DESIGN_W - btnW) / 2
    local btnY = CARDS_BOTTOM_Y + 24

    local sc = col
    local btnPulse = 0.8 + 0.2 * math.sin(t * 3)

    if isLocked then
        local unlockType2 = SaveData.GetUnlockType(ch.id)
        if unlockType2 == "wave" then
            -- 波次解锁：显示进度提示按钮（不可点击）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 12)
            nvgFillColor(vg, nvgRGBA(60, 120, 180, math.floor(30 * btnPulse)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(80, 160, 220, math.floor(140 * btnPulse)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            local cond2 = SaveData.UNLOCK_CONDITIONS[ch.id]
            local bestW2 = math.max(SaveData.highestWave, myCloudBestWave or 0)
            local progress = math.min(1, bestW2 / cond2)
            -- 进度条
            if progress > 0 then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX + 4, btnY + btnH - 6, (btnW - 8) * progress, 3, 1.5)
                nvgFillColor(vg, nvgRGBA(100, 200, 255, math.floor(180 * btnPulse)))
                nvgFill(vg)
            end

            nvgFontFaceId(vg, zpix)
            nvgFontSize(vg, 17)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(150, 210, 255, math.floor(200 * btnPulse)))
            nvgText(vg, DESIGN_W / 2, btnY + btnH / 2 - 4, I18n.t("card_locked_wave", cond2))
            nvgFontFaceId(vg, zpix)
        else
            -- 广告/评价解锁：双按钮布局
            local gap = 12
            local halfW = (btnW - gap) / 2

            -- 左按钮：推荐游戏解锁（金色主题）
            local lbX = btnX
            nvgBeginPath(vg)
            nvgRoundedRect(vg, lbX, btnY, halfW, btnH, 12)
            nvgFillColor(vg, nvgRGBA(255, 180, 30, math.floor(60 * btnPulse)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 80, math.floor(220 * btnPulse)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            nvgFontFaceId(vg, zpix)
            nvgFontSize(vg, 17)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 220, 100, math.floor(240 * btnPulse)))
            nvgText(vg, lbX + halfW / 2, btnY + btnH / 2, I18n.t("charsel_unlock_all"))

            -- 右按钮：看广告解锁（绿色主题）
            local rbX = btnX + halfW + gap
            nvgBeginPath(vg)
            nvgRoundedRect(vg, rbX, btnY, halfW, btnH, 12)
            nvgFillColor(vg, nvgRGBA(60, 200, 80, math.floor(50 * btnPulse)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(80, 220, 100, math.floor(220 * btnPulse)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            nvgFontFaceId(vg, zpix)
            nvgFontSize(vg, 17)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(130, 255, 150, math.floor(240 * btnPulse)))
            nvgText(vg, rbX + halfW / 2, btnY + btnH / 2, I18n.t("charsel_unlock_ad"))
        end
    else
        -- 正常"开始战斗"按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 12)
        nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], math.floor(40 * btnPulse)))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], math.floor(200 * btnPulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        nvgFontSize(vg, 24)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(200 * btnPulse)))
        nvgText(vg, DESIGN_W / 2, btnY + btnH / 2, I18n.t("charsel_start"))
    end

    -- ── 难度选择条（在开始战斗按钮下方） ──
    local diffBarY = btnY + btnH + 10
    local diffBarH = 36
    local diffs = Config.DIFFICULTY
    local diffCount = #diffs
    local diffBtnW = 64
    local diffGap = 8
    local diffTotalW = diffCount * diffBtnW + (diffCount - 1) * diffGap
    local diffStartX = (DESIGN_W - diffTotalW) / 2

    -- 标签
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 160, 180, 150))
    nvgText(vg, DESIGN_W / 2, diffBarY - 2, I18n.t("charsel_diff"))

    diffBarY = diffBarY + 10

    -- 存储按钮区域供触摸检测
    diffBtnRects = {}
    for di = 1, diffCount do
        local d = diffs[di]
        local dbx = diffStartX + (di - 1) * (diffBtnW + diffGap)
        local isSelected = (di == Config.currentDiffIdx)

        diffBtnRects[di] = { x = dbx, y = diffBarY, w = diffBtnW, h = diffBarH }

        -- 按钮背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dbx, diffBarY, diffBtnW, diffBarH, 8)
        if isSelected then
            -- 选中态：主题色填充
            local diffColors = { {80,220,100}, {255,210,60}, {255,80,60}, {180,50,255} }
            local dc = diffColors[di] or {255,255,255}
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 50))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 220))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            -- 选中文字
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 255))
            nvgText(vg, dbx + diffBtnW / 2, diffBarY + diffBarH / 2, d.icon .. d.name)
        else
            -- 未选中态
            nvgFillColor(vg, nvgRGBA(30, 25, 50, 180))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(80, 80, 100, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(150, 150, 170, 180))
            nvgText(vg, dbx + diffBtnW / 2, diffBarY + diffBarH / 2, d.icon .. d.name)
        end
    end

    -- 选中难度描述
    local curDiff = Config.GetDifficulty()
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 140))
    nvgText(vg, DESIGN_W / 2, diffBarY + diffBarH + 10, curDiff.desc)

    -- 每日挑战入口按钮（在难度选择下方）
    local dcBtnW = DESIGN_W - 32
    local dcBtnH = 52
    local dcBtnX = (DESIGN_W - dcBtnW) / 2
    local dcBtnY = diffBarY + diffBarH + 26
    local cfg = DailyChallenge.GetTodayConfig()

    -- 绘制每日挑战卡片背景
    local dcPulse = 0.7 + 0.3 * math.sin(t * 2.5)
    -- 卡片底色
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dcBtnX, dcBtnY, dcBtnW, dcBtnH, 12)
    nvgFillColor(vg, nvgRGBA(15, 40, 80, 210))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 160, 255, math.floor(200 * dcPulse)))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 左侧 emoji 图标
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgText(vg, dcBtnX + 12, dcBtnY + dcBtnH / 2, "📅")

    -- 按钮标题
    nvgFontSize(vg, 21)
    nvgFillColor(vg, nvgRGBA(120, 210, 255, math.floor(240 * dcPulse)))
    nvgText(vg, dcBtnX + 50, dcBtnY + dcBtnH / 2 - 10, I18n.t("charsel_dc_title"))

    -- 每日挑战详情信息（按钮内右侧）
    local neg = cfg.negativeFactor
    local detailText = cfg.enemyEmoji .. " " .. DailyChallenge.GetEnemyTypeName() .. "  " .. neg.icon .. neg.name
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(180, 210, 240, 190))
    nvgText(vg, dcBtnX + 50, dcBtnY + dcBtnH / 2 + 12, detailText)

    -- 中性因子（右侧行）
    local neutralParts = {}
    for _, f in ipairs(cfg.neutralFactors) do
        neutralParts[#neutralParts + 1] = f.icon .. f.name
    end
    if #neutralParts > 0 then
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 180, 200, 150))
        nvgText(vg, dcBtnX + dcBtnW - 10, dcBtnY + dcBtnH / 2, table.concat(neutralParts, " · "))
    end

    -- ── 词条详解展开区 ──
    -- 收集所有词条（负面 + 中性）
    local allFactors = {}
    allFactors[#allFactors + 1] = {
        icon = cfg.negativeFactor.icon,
        name = cfg.negativeFactor.name,
        desc = cfg.negativeFactor.desc,
        isNeg = true,
    }
    for _, f in ipairs(cfg.neutralFactors) do
        allFactors[#allFactors + 1] = { icon = f.icon, name = f.name, desc = f.desc, isNeg = false }
    end

    local rowH    = 38
    local rowGap  = 6
    local detailX = dcBtnX
    local detailW = dcBtnW
    local detailY = dcBtnY + dcBtnH + 8

    for ri, fac in ipairs(allFactors) do
        local ry = detailY + (ri - 1) * (rowH + rowGap)

        -- 行背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, detailX, ry, detailW, rowH, 8)
        if fac.isNeg then
            nvgFillColor(vg, nvgRGBA(60, 15, 15, 200))
        else
            nvgFillColor(vg, nvgRGBA(15, 30, 55, 200))
        end
        nvgFill(vg)
        -- 左侧色条
        nvgBeginPath(vg)
        nvgRoundedRect(vg, detailX, ry, 3, rowH, 2)
        if fac.isNeg then
            nvgFillColor(vg, nvgRGBA(255, 90, 90, 220))
        else
            nvgFillColor(vg, nvgRGBA(90, 190, 255, 200))
        end
        nvgFill(vg)

        -- 图标
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgText(vg, detailX + 10, ry + rowH / 2, fac.icon)

        -- 词条名称
        nvgFontSize(vg, 15)
        if fac.isNeg then
            nvgFillColor(vg, nvgRGBA(255, 160, 140, 240))
        else
            nvgFillColor(vg, nvgRGBA(140, 210, 255, 240))
        end
        nvgText(vg, detailX + 36, ry + rowH / 2 - 8, fac.name)

        -- 说明文字
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(170, 175, 195, 190))
        nvgText(vg, detailX + 36, ry + rowH / 2 + 10, fac.desc)
    end

    -- 底部提示
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 120))
    nvgText(vg, DESIGN_W / 2, DESIGN_H - 30, I18n.t("charsel_hint"))

    -- 评价解锁通知 Toast（点击后3秒内显示）
    local notifyDur = 3.0
    local elapsed = time.elapsedTime - repNotifyTime
    if elapsed >= 0 and elapsed < notifyDur then
        local fadeAlpha = elapsed < 0.3 and (elapsed / 0.3)
                       or elapsed > notifyDur - 0.5 and (1 - (elapsed - (notifyDur - 0.5)) / 0.5)
                       or 1.0
        local toastW = 320
        local toastH = 52
        local toastX = (DESIGN_W - toastW) / 2
        local toastY = DESIGN_H * 0.25
        nvgBeginPath(vg)
        nvgRoundedRect(vg, toastX, toastY, toastW, toastH, 14)
        nvgFillColor(vg, nvgRGBA(20, 160, 80, math.floor(220 * fadeAlpha)))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 255, 140, math.floor(180 * fadeAlpha)))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * fadeAlpha)))
        nvgText(vg, DESIGN_W / 2, toastY + toastH / 2, I18n.t("charsel_unlocked_all"))
    end
end

--- 角色选择触控处理（翻页模式）
function HandleCharSelectTouch(dx, dy)
    local chars = Config.CHARACTERS
    local total = #chars

    local cardX = (DESIGN_W - CARD_W) / 2
    local arrowMargin = 14
    local arrowY = ARROW_Y_CENTER - ARROW_SIZE / 2

    -- 左箭头检测
    local leftArrowX = cardX - ARROW_SIZE - arrowMargin
    if dx >= leftArrowX and dx <= leftArrowX + ARROW_SIZE and dy >= arrowY and dy <= arrowY + ARROW_SIZE then
        selectedCharIdx = selectedCharIdx - 1
        if selectedCharIdx < 1 then selectedCharIdx = total end
        selectedCharId = chars[selectedCharIdx].id
        return
    end

    -- 右箭头检测
    local rightArrowX = cardX + CARD_W + arrowMargin
    if dx >= rightArrowX and dx <= rightArrowX + ARROW_SIZE and dy >= arrowY and dy <= arrowY + ARROW_SIZE then
        selectedCharIdx = selectedCharIdx + 1
        if selectedCharIdx > total then selectedCharIdx = 1 end
        selectedCharId = chars[selectedCharIdx].id
        return
    end

    -- 检测是否点了底部按钮
    local btnW = 300
    local btnH = 56
    local btnX = (DESIGN_W - btnW) / 2
    local btnY = CARDS_BOTTOM_Y + 24

    local curChar = chars[selectedCharIdx]
    local isLocked = not SaveData.IsCharUnlocked(curChar.id)

    if isLocked then
        local unlockType3 = SaveData.GetUnlockType(curChar.id)
        if unlockType3 == "wave" then
            -- 波次解锁角色：按钮不可点击，无操作
            return
        end

        -- 广告/评价解锁：双按钮检测
        local gap = 12
        local halfW = (btnW - gap) / 2

        -- 左按钮：评价解锁全部
        local lbX = btnX
        if dx >= lbX and dx <= lbX + halfW and dy >= btnY and dy <= btnY + btnH then
            local repUrl = "https://www.taptap.cn/app/" .. tostring(835257)
            pcall(function() fileSystem:SystemOpen(repUrl) end)
            SaveData.UnlockRep()
            repNotifyTime = time.elapsedTime  -- 触发屏幕通知
            print("[Rep] 已解锁全部角色: " .. curChar.name)
            return
        end

        -- 右按钮：看广告解锁当前角色
        local rbX = btnX + halfW + gap
        if dx >= rbX and dx <= rbX + halfW and dy >= btnY and dy <= btnY + btnH then
            print("[AD] 请求播放广告解锁: " .. curChar.id)
            if not sdk then
                print("[AD] sdk不可用，直接解锁")
                SaveData.UnlockCharByAd(curChar.id)
                return
            end
            sdk:ShowRewardVideoAd(function(result)
                if result.success then
                    SaveData.UnlockCharByAd(curChar.id)
                    print("[AD] 广告观看成功，已解锁角色: " .. curChar.name)
                else
                    print("[AD] 广告播放失败: " .. (result.msg or "unknown"))
                end
            end)
            return
        end
    else
        -- 解锁状态：开始战斗按钮
        if dx >= btnX and dx <= btnX + btnW and dy >= btnY and dy <= btnY + btnH then
            StartBattle()
            return
        end
    end

    -- ── 难度按钮检测 ──
    local diffBarY2 = btnY + btnH + 10 + 10  -- 与渲染一致: btnY+btnH+10 是初始, +10是标签偏移
    local diffBarH2 = 36
    local diffs2 = Config.DIFFICULTY
    local diffCount2 = #diffs2
    local diffBtnW2 = 64
    local diffGap2 = 8
    local diffTotalW2 = diffCount2 * diffBtnW2 + (diffCount2 - 1) * diffGap2
    local diffStartX2 = (DESIGN_W - diffTotalW2) / 2
    for di = 1, diffCount2 do
        local dbx = diffStartX2 + (di - 1) * (diffBtnW2 + diffGap2)
        if dx >= dbx and dx <= dbx + diffBtnW2 and dy >= diffBarY2 and dy <= diffBarY2 + diffBarH2 then
            Config.currentDiffIdx = di
            return
        end
    end

    -- 每日挑战按钮（无论角色是否解锁都可见）
    local dcBtnW = DESIGN_W - 32
    local dcBtnH = 52
    local dcBtnX = (DESIGN_W - dcBtnW) / 2
    local dcBtnY = diffBarY2 + diffBarH2 + 26  -- 与渲染一致
    if dx >= dcBtnX and dx <= dcBtnX + dcBtnW and dy >= dcBtnY and dy <= dcBtnY + dcBtnH then
        -- 每日挑战需要角色解锁
        local curChar2 = chars[selectedCharIdx]
        if SaveData.IsCharUnlocked(curChar2.id) then
            StartDailyChallenge()
        end
    end
end

-- ============================================================================
-- 输入处理
-- ============================================================================

--- 文字输入事件（昵称自定义编辑）
---@param eventType string
---@param eventData TextInputEventData
function HandleTextInput(eventType, eventData)
    local text = eventData["Text"]:GetString()

    -- 昵称输入
    if gameState == STATE_NICKNAME and nickEditMode then
        if #tempNickname + #text <= 32 then
            tempNickname = tempNickname .. text
        end
        return
    end

    -- 遗言输入（限制 60 字节 ≈ 20 中文字符）
    if gameState == STATE_OVER and tombEditMode then
        if #tombLastWords + #text <= 60 then
            tombLastWords = tombLastWords .. text
        end
        return
    end
end

function HandleTouchBegin(eventType, eventData)
    local touchX = eventData["X"]:GetInt()
    local touchY = eventData["Y"]:GetInt()
    HandleScreenTouch(touchX, touchY)
end

function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local mx = input.mousePosition.x
    local my = input.mousePosition.y
    HandleScreenTouch(mx, my)
end

-- ── 排行榜拖动滚动 ──

---@param screenX number
---@param screenY number
local function LbDragBegin(screenX, screenY)
    if gameState ~= STATE_LEADERBOARD then return end
    local _, dy = ScreenToDesign(screenX, screenY)
    -- 只在列表区域内开始拖动（headerY+28 ~ DESIGN_H-120）
    if dy > 148 and dy < DESIGN_H - 120 then
        lbDragStartY = dy
        lbDragLastY = dy
        lbDragScrollStart = lbScrollY
        lbScrollVel = 0
    end
end

---@param screenX number
---@param screenY number
local function LbDragMove(screenX, screenY)
    if not lbDragStartY then return end
    local _, dy = ScreenToDesign(screenX, screenY)
    local delta = lbDragLastY - dy  -- 向上拖 = 正值 = 列表下滚
    lbScrollVel = -delta / math.max(0.016, time.timeStep)  -- 像素/秒（用于惯性）
    lbScrollY = lbScrollY + delta
    lbDragLastY = dy
end

local function LbDragEnd()
    if not lbDragStartY then return end
    lbDragStartY = nil
    lbDragLastY = nil
    -- lbScrollVel 保留用于惯性
end

function HandleTouchMove(eventType, eventData)
    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    if gameState == STATE_CODEX then
        local _, dy = ScreenToDesign(tx, ty)
        Codex.HandleDragMove(dy)
        return
    end
    if gameState == STATE_WEEKLY then
        local _, dy = ScreenToDesign(tx, ty)
        WeeklyChallenge.HandleDragMove(dy)
        return
    end
    if gameState == STATE_TOTEM_SHOP then
        local _, dy = ScreenToDesign(tx, ty)
        TotemShop.HandleDragMove(dy)
        return
    end
    if gameState == STATE_RUNE_SHOP then
        local _, dy = ScreenToDesign(tx, ty)
        RuneShop.HandleDragMove(dy)
        return
    end
    if gameState == STATE_SKIN_SHOP then
        local _, dy = ScreenToDesign(tx, ty)
        SkinShop.HandleDragMove(dy)
        return
    end
    if gameState == STATE_ACHIEVEMENT then
        local _, dy = ScreenToDesign(tx, ty)
        Achievement.HandleDragMove(dy)
        return
    end
    LbDragMove(tx, ty)
end

function HandleTouchEnd(eventType, eventData)
    if gameState == STATE_CODEX then
        Codex.HandleDragEnd()
        return
    end
    if gameState == STATE_WEEKLY then
        WeeklyChallenge.HandleDragEnd()
        return
    end
    if gameState == STATE_TOTEM_SHOP then
        TotemShop.HandleDragEnd()
        return
    end
    if gameState == STATE_RUNE_SHOP then
        RuneShop.HandleDragEnd()
        return
    end
    if gameState == STATE_SKIN_SHOP then
        SkinShop.HandleDragEnd()
        return
    end
    if gameState == STATE_ACHIEVEMENT then
        Achievement.HandleDragEnd()
        return
    end
    LbDragEnd()
end

function HandleMouseMove(eventType, eventData)
    if gameState == STATE_CODEX then
        local mx = input.mousePosition.x
        local my = input.mousePosition.y
        local _, dy = ScreenToDesign(mx, my)
        Codex.HandleDragMove(dy)
        return
    end
    if gameState == STATE_WEEKLY then
        local mx = input.mousePosition.x
        local my = input.mousePosition.y
        local _, dy = ScreenToDesign(mx, my)
        WeeklyChallenge.HandleDragMove(dy)
        return
    end
    if gameState == STATE_TOTEM_SHOP then
        local mx = input.mousePosition.x
        local my = input.mousePosition.y
        local _, dy = ScreenToDesign(mx, my)
        TotemShop.HandleDragMove(dy)
        return
    end
    if gameState == STATE_RUNE_SHOP then
        local mx = input.mousePosition.x
        local my = input.mousePosition.y
        local _, dy = ScreenToDesign(mx, my)
        RuneShop.HandleDragMove(dy)
        return
    end
    if gameState == STATE_SKIN_SHOP then
        local mx = input.mousePosition.x
        local my = input.mousePosition.y
        local _, dy = ScreenToDesign(mx, my)
        SkinShop.HandleDragMove(dy)
        return
    end
    if gameState == STATE_ACHIEVEMENT then
        local mx = input.mousePosition.x
        local my = input.mousePosition.y
        local _, dy = ScreenToDesign(mx, my)
        Achievement.HandleDragMove(dy)
        return
    end
    if not lbDragStartY then return end
    local mx = input.mousePosition.x
    local my = input.mousePosition.y
    LbDragMove(mx, my)
end

function HandleMouseUp(eventType, eventData)
    if gameState == STATE_CODEX then
        Codex.HandleDragEnd()
        return
    end
    if gameState == STATE_WEEKLY then
        WeeklyChallenge.HandleDragEnd()
        return
    end
    if gameState == STATE_TOTEM_SHOP then
        TotemShop.HandleDragEnd()
        return
    end
    if gameState == STATE_RUNE_SHOP then
        RuneShop.HandleDragEnd()
        return
    end
    if gameState == STATE_SKIN_SHOP then
        SkinShop.HandleDragEnd()
        return
    end
    if gameState == STATE_ACHIEVEMENT then
        Achievement.HandleDragEnd()
        return
    end
    LbDragEnd()
end

function HandleScreenTouch(screenX, screenY)
    -- 转换到设计坐标
    local dx, dy = ScreenToDesign(screenX, screenY)

    if RechargeShop.visible then
        RechargeShop.HandleTouch(dx, dy)
        return
    end

    -- ── 昵称设置 ──
    if gameState == STATE_NICKNAME then
        if nickEditMode then
            -- 编辑模式：取消按钮（复用 nickRerollBtn 位置）
            local rb = nickRerollBtn
            if rb.w > 0 and dx >= rb.x and dx <= rb.x + rb.w and dy >= rb.y and dy <= rb.y + rb.h then
                nickEditMode = false
                input.screenKeyboardVisible = false
                tempNickname = SaveData.GenerateNickname()
                return
            end
            -- 编辑模式：完成按钮（复用 nickConfirmBtn 位置）
            local cb = nickConfirmBtn
            if cb.w > 0 and dx >= cb.x and dx <= cb.x + cb.w and dy >= cb.y and dy <= cb.y + cb.h then
                if #tempNickname > 0 then
                    nickEditMode = false
                    input.screenKeyboardVisible = false
                end
                return
            end
            -- 点击输入框本身不做特殊处理（已在编辑中）
            return
        else
            -- 普通模式：随机按钮
            local rb = nickRerollBtn
            if dx >= rb.x and dx <= rb.x + rb.w and dy >= rb.y and dy <= rb.y + rb.h then
                tempNickname = SaveData.GenerateNickname()
                return
            end
            -- 普通模式：自定义按钮
            local cu = nickCustomBtn
            if cu.w > 0 and dx >= cu.x and dx <= cu.x + cu.w and dy >= cu.y and dy <= cu.y + cu.h then
                nickEditMode = true
                tempNickname = ""  -- 清空，让用户从头输入
                input.screenKeyboardVisible = true  -- 唤起手机软键盘
                return
            end
            -- 普通模式：确认按钮
            local cb = nickConfirmBtn
            if dx >= cb.x and dx <= cb.x + cb.w and dy >= cb.y and dy <= cb.y + cb.h then
                if #tempNickname > 0 then
                    SaveData.SetNickname(tempNickname)
                    nickEditMode = false
                    input.screenKeyboardVisible = false
                    gameState = STATE_TITLE
                    print("[SaveData] 昵称设置: " .. tempNickname)
                end
                return
            end
            -- 点击输入框也进入编辑模式
            local ib = nickInputBox
            if ib.w > 0 and dx >= ib.x and dx <= ib.x + ib.w and dy >= ib.y and dy <= ib.y + ib.h then
                nickEditMode = true
                tempNickname = ""
                input.screenKeyboardVisible = true  -- 唤起手机软键盘
                return
            end
        end
        return
    end

    -- ── 标题画面 ──
    if gameState == STATE_TITLE then
        -- 昵称编辑按钮
        local ne = titleNickEditBtn
        if ne.w > 0 and dx >= ne.x and dx <= ne.x + ne.w and dy >= ne.y and dy <= ne.y + ne.h then
            tempNickname = SaveData.nickname or SaveData.GenerateNickname()
            nickEditMode = false
            gameState = STATE_NICKNAME
            return
        end
        -- 继续游戏按钮
        if titleContinueBtn.visible then
            local tb = titleContinueBtn
            if dx >= tb.x and dx <= tb.x + tb.w and dy >= tb.y and dy <= tb.y + tb.h then
                ResumeBattle()
                return
            end
        end
        -- 新游戏按钮
        local nb = titleNewGameBtn
        if dx >= nb.x and dx <= nb.x + nb.w and dy >= nb.y and dy <= nb.y + nb.h then
            GameAudio.PlaySFX("levelup")
            titleFlash = 0.22; titleFlashX = dx; titleFlashY = dy
            lastHighScoreRank = nil
            gameState = STATE_CHAR_SELECT
            selectedCharIdx = 1
            selectedCharId = Config.CHARACTERS[1].id
            return
        end
        -- 排行榜按钮
        local lb = titleLeaderboardBtn
        if dx >= lb.x and dx <= lb.x + lb.w and dy >= lb.y and dy <= lb.y + lb.h then
            GameAudio.PlaySFX("pickup")
            titleFlash = 0.22; titleFlashX = dx; titleFlashY = dy
            LoadLeaderboard()
            gameState = STATE_LEADERBOARD
            return
        end
        -- 成就按钮
        local ab = titleAchievementBtn
        if ab.w > 0 and dx >= ab.x and dx <= ab.x + ab.w and dy >= ab.y and dy <= ab.y + ab.h then
            GameAudio.PlaySFX("pickup")
            titleFlash = 0.22; titleFlashX = dx; titleFlashY = dy
            gameState = STATE_ACHIEVEMENT
            return
        end
        -- 遗物商店按钮
        local rb = titleRelicShopBtn
        if rb.w > 0 and dx >= rb.x and dx <= rb.x + rb.w and dy >= rb.y and dy <= rb.y + rb.h then
            GameAudio.PlaySFX("pickup")
            titleFlash = 0.22; titleFlashX = dx; titleFlashY = dy
            gameState = STATE_RELIC_SHOP
            return
        end
        -- 图腾商店按钮
        local tsb = titleTotemShopBtn
        if tsb.w > 0 and dx >= tsb.x and dx <= tsb.x + tsb.w and dy >= tsb.y and dy <= tsb.y + tsb.h then
            GameAudio.PlaySFX("pickup")
            titleFlash = 0.22; titleFlashX = dx; titleFlashY = dy
            TotemShop.Reset()
            gameState = STATE_TOTEM_SHOP
            return
        end
        -- 符文商店按钮
        local rnb = titleRuneShopBtn
        if rnb.w > 0 and dx >= rnb.x and dx <= rnb.x + rnb.w and dy >= rnb.y and dy <= rnb.y + rnb.h then
            GameAudio.PlaySFX("pickup")
            titleFlash = 0.22; titleFlashX = dx; titleFlashY = dy
            RuneShop.Reset()
            gameState = STATE_RUNE_SHOP
            return
        end
        -- 皮肤商店按钮
        local skb = titleSkinShopBtn
        if skb.w > 0 and dx >= skb.x and dx <= skb.x + skb.w and dy >= skb.y and dy <= skb.y + skb.h then
            GameAudio.PlaySFX("pickup")
            titleFlash = 0.22; titleFlashX = dx; titleFlashY = dy
            SkinShop.Reset()
            gameState = STATE_SKIN_SHOP
            return
        end
        -- 图鉴收集册按钮
        local cxb = titleCodexBtn
        if cxb.w > 0 and dx >= cxb.x and dx <= cxb.x + cxb.w and dy >= cxb.y and dy <= cxb.y + cxb.h then
            GameAudio.PlaySFX("pickup")
            titleFlash = 0.22; titleFlashX = dx; titleFlashY = dy
            Codex.ResetPageState()
            gameState = STATE_CODEX
            return
        end
        -- 周挑战赛季按钮
        local wcb = titleWeeklyBtn
        if wcb.w > 0 and dx >= wcb.x and dx <= wcb.x + wcb.w and dy >= wcb.y and dy <= wcb.y + wcb.h then
            GameAudio.PlaySFX("pickup")
            titleFlash = 0.22; titleFlashX = dx; titleFlashY = dy
            WeeklyChallenge.ResetPageState()
            gameState = STATE_WEEKLY
            return
        end
        -- 充值
        local rcb = titleRechargeBtn
        if rcb.w > 0 and dx >= rcb.x and dx <= rcb.x + rcb.w and dy >= rcb.y and dy <= rcb.y + rcb.h then
            GameAudio.PlaySFX("pickup")
            titleFlash = 0.22; titleFlashX = dx; titleFlashY = dy
            RechargeShop.Open()
            return
        end
        -- 重试联机
        local rob = titleRetryOnlineBtn
        if rob.visible and rob.w > 0 and dx >= rob.x and dx <= rob.x + rob.w and dy >= rob.y and dy <= rob.y + rob.h then
            GameAudio.PlaySFX("pickup")
            ClientMain.Stop()
            if type(_G.LobbyRetryOnline) == "function" then
                _G.LobbyRetryOnline()
            else
                GameMode.SetOffline(false)
                ClientMain.Start()
            end
            return
        end
        return
    end

    -- ── 遗物商店 ──
    if gameState == STATE_RELIC_SHOP then
        local result = RelicShop.HandleTouch(dx, dy, sdk)
        if result == "back" then
            gameState = STATE_TITLE
        end
        return
    end

    -- ── 图腾商店 ──
    if gameState == STATE_TOTEM_SHOP then
        local result = TotemShop.HandleTouch(dx, dy)
        if result == "back" then
            gameState = STATE_TITLE
        else
            -- 开始拖动（用于网格滚动）
            TotemShop.HandleDragBegin(dy)
        end
        return
    end

    -- ── 符文商店 ──
    if gameState == STATE_RUNE_SHOP then
        local result = RuneShop.HandleTouch(dx, dy)
        if result == "back" then
            gameState = STATE_TITLE
        else
            RuneShop.HandleDragBegin(dy)
        end
        return
    end

    -- ── 皮肤商店 ──
    if gameState == STATE_SKIN_SHOP then
        local result = SkinShop.HandleTouch(dx, dy)
        if result == "back" then
            gameState = STATE_TITLE
        else
            SkinShop.HandleDragBegin(dy)
        end
        return
    end

    -- ── 图鉴收集册 ──
    if gameState == STATE_CODEX then
        local result = Codex.HandleTouch(dx, dy, DESIGN_W, DESIGN_H)
        if result == "back" then
            gameState = STATE_TITLE
        else
            Codex.HandleDragBegin(dy)
        end
        return
    end

    -- ── 周挑战赛季 ──
    if gameState == STATE_WEEKLY then
        local result = WeeklyChallenge.HandleTouch(dx, dy, DESIGN_W, DESIGN_H)
        if result == "back" then
            gameState = STATE_TITLE
        elseif result == "claim" then
            WeeklyChallenge.ClaimLastSeasonReward()
        elseif result == "start" then
            StartWeeklyChallenge()
        else
            WeeklyChallenge.HandleDragBegin(dy)
        end
        return
    end

    -- ── 成就页面 ──
    if gameState == STATE_ACHIEVEMENT then
        local backRect = Achievement.GetBackButtonRect(DESIGN_W, DESIGN_H)
        if dx >= backRect.x and dx <= backRect.x + backRect.w and dy >= backRect.y and dy <= backRect.y + backRect.h then
            Achievement._scrollY = 0
            Achievement._scrollVel = 0
            gameState = STATE_TITLE
            return
        end
        Achievement.HandleDragBegin(dy)
        return
    end

    -- ── 排行榜 ──
    if gameState == STATE_LEADERBOARD then
        local bb = leaderboardBackBtn
        if dx >= bb.x and dx <= bb.x + bb.w and dy >= bb.y and dy <= bb.y + bb.h then
            lbDragStartY = nil
            lbScrollVel = 0
            gameState = STATE_TITLE
            return
        end
        -- 标签页切换
        local t1 = lbTabBtn1
        if dx >= t1.x and dx <= t1.x + t1.w and dy >= t1.y and dy <= t1.y + t1.h then
            if lbCurrentTab ~= LB_TAB_WAVE then
                lbCurrentTab = LB_TAB_WAVE
                LoadLeaderboard()
            end
            return
        end
        local t2 = lbTabBtn2
        if dx >= t2.x and dx <= t2.x + t2.w and dy >= t2.y and dy <= t2.y + t2.h then
            if lbCurrentTab ~= LB_TAB_KILLS then
                lbCurrentTab = LB_TAB_KILLS
                LoadLeaderboard()
            end
            return
        end
        local t3 = lbTabBtn3
        if dx >= t3.x and dx <= t3.x + t3.w and dy >= t3.y and dy <= t3.y + t3.h then
            if lbCurrentTab ~= LB_TAB_DAILY then
                lbCurrentTab = LB_TAB_DAILY
                LoadLeaderboard()
            end
            return
        end
        -- 开始拖动滚动
        LbDragBegin(screenX, screenY)
        return
    end

    if gameState == STATE_CHAR_SELECT then
        HandleCharSelectTouch(dx, dy)
        return
    end

    if gameState == STATE_OVER then
        -- 复活按钮检测（优先）
        if HUD.HitReviveButton(dx, dy) and not hasUsedRevive and not gameOverVictory then
            if not sdk then
                print("[AD] sdk不可用，直接复活")
                hasUsedRevive = true
                Player.hp = math.max(1, math.floor(Player.maxHp * 0.5))
                Player.invTimer = 3.0
                EnemyBullet.Reset()
                BattleScene.state = BattleScene.STATE_PLAYING
                gameState = STATE_PLAYING
                return
            end
            sdk:ShowRewardVideoAd(function(result)
                if result.success then
                    hasUsedRevive = true
                    -- 恢复 50% 血量
                    Player.hp = math.max(1, math.floor(Player.maxHp * 0.5))
                    -- 给 3 秒无敌时间
                    Player.invTimer = 3.0
                    -- 清除附近敌方子弹
                    EnemyBullet.Reset()
                    -- 恢复战斗状态
                    BattleScene.state = BattleScene.STATE_PLAYING
                    gameState = STATE_PLAYING
                    print("[REVIVE] 广告复活成功，恢复 HP=" .. Player.hp)
                else
                    -- 广告失败也给复活（与礼物盒逻辑一致）
                    hasUsedRevive = true
                    Player.hp = math.max(1, math.floor(Player.maxHp * 0.5))
                    Player.invTimer = 3.0
                    EnemyBullet.Reset()
                    BattleScene.state = BattleScene.STATE_PLAYING
                    gameState = STATE_PLAYING
                    print("[REVIVE] 广告播放失败，模拟成功复活: " .. (result.msg or ""))
                end
            end)
            return
        end
        -- 遗言输入框点击检测（仅死亡时）
        if not gameOverVictory and HUD.tombInputBox then
            local tb = HUD.tombInputBox
            if dx >= tb.x and dx <= tb.x + tb.w and dy >= tb.y and dy <= tb.y + tb.h then
                tombEditMode = true
                input.screenKeyboardVisible = true
                return
            end
        end

        -- 如果正在编辑遗言，点击输入框外区域关闭键盘（不跳转）
        if tombEditMode then
            tombEditMode = false
            input.screenKeyboardVisible = false
            return
        end

        -- 再来一局按钮检测（需至少展示1.5秒，防止误触）
        if time.elapsedTime - gameOverShowTime < 1.5 then return end
        if not HUD.HitRestartButton(dx, dy) then return end
        -- 上传墓碑遗言（延迟到此时，携带玩家自定义遗言）
        if not gameOverVictory and gameOverStats then
            local charEmoji = ((Player.charDef and Player.charDef.playerEmoji) and Player.charDef.playerEmoji.idle or "👻")
            local words = (tombLastWords ~= "") and tombLastWords or nil
            Tombstone.Upload(gameOverStats, Player.charId, charEmoji, words)
        end
        tombEditMode = false
        tombLastWords = ""
        DailyChallenge.lastReward = nil  -- 清理每日挑战奖励展示
        gameState = STATE_TITLE
        return
    end

    if gameState == STATE_PLAYING then
        -- 暂停按钮（最高优先级之一）
        if HUD.HitPauseButton(dx, dy) then
            HUD.paused = not HUD.paused
            return
        end
        -- 暂停时：检测继续按钮 & 摇杆位置按钮 & 保存退出
        if HUD.paused then
            if HUD.HitContinueButton(dx, dy) then
                HUD.paused = false
                return
            end
            -- 保存退出按钮
            if HUD.HitSaveExitButton(dx, dy) then
                if HUD.onSaveExit then
                    HUD.onSaveExit()
                end
                return
            end
            local joyPos = HUD.HitJoystickPosButton(dx, dy)
            if joyPos and joyPos ~= HUD.joystickPos then
                HUD.joystickPos = joyPos
                ApplyJoystickPosition(joyPos)
                HUD.SaveSettings()
            end
            local edVal = HUD.HitEightDirButton(dx, dy)
            if edVal ~= nil and edVal ~= HUD.eightDirMode then
                HUD.eightDirMode = edVal
                HUD.SaveSettings()
            end
            local glVal = HUD.HitGlowButton(dx, dy)
            if glVal ~= nil and glVal ~= Glow.enabled then
                Glow.enabled = glVal
                HUD.SaveSettings()
            end
            local langVal = HUD.HitLangButton(dx, dy)
            if langVal and langVal ~= I18n.lang then
                I18n.lang = langVal
                HUD.SaveSettings()
            end
            local perfVal = HUD.HitPerfButton(dx, dy)
            if perfVal and perfVal ~= PerfQuality.level then
                PerfQuality.SetLevel(perfVal)
                -- 切换档位时同步辉光开关（仅档位5开启）
                Glow.enabled = PerfQuality.GlowEnabled()
                HUD.SaveSettings()
            end
            return
        end
        -- 礼物盒广告弹窗处理（最高优先级）
        if GiftAd.visible then
            GiftAd.HandleTouch(dx, dy, DESIGN_W, DESIGN_H)
            return
        end
        -- 终极奖励选择处理
        if SkillSelect.ultimateVisible then
            SkillSelect.HandleUltimateTouch(dx, dy, DESIGN_W, DESIGN_H)
            return
        end
        -- 技能选择处理
        if SkillSelect.visible then
            SkillSelect.HandleTouch(dx, dy, DESIGN_W, DESIGN_H, sdk)
            return
        end
        -- 技能/图腾/符文图标点击详情
        if HUD.HitSkillIcon(dx, dy) then
            return
        end
    end
end

return ClientMain
