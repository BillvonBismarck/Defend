--- ============================================================================
--- 遗言墓碑系统 - 异步社交（死亡留言 + 战场墓碑）
--- 使用 clientCloud 存储/拉取其他玩家的死亡信息
--- ============================================================================

local Config = require("Config")
local Glow   = require("fx.Glow")

local Tombstone = {}

-- ========== 敏感词本地过滤 ==========
local BLOCKED_WORDS = {
    -- 政治敏感
    "习近平","毛泽东","共产党","国民党","六四","天安门","法轮功","台独",
    "藏独","疆独","文革","反共","反党","颠覆","政变","独裁","专制",
    -- 色情低俗
    "操你","草你","日你","fuck","shit","dick","pussy","bitch","asshole",
    "他妈","妈的","傻逼","煞笔","sb","cnm","nmsl","尼玛","你妈",
    "逼","屌","鸡巴","阴茎","阴道","性交","做爱","自慰",
    -- 暴力仇恨
    "杀人","自杀","去死","弄死","砍死","打死","毒死",
    -- 歧视侮辱
    "智障","弱智","脑残","废物","垃圾人","人渣","畜生","贱人",
    -- 诈骗引流
    "加微信","加qq","私聊","免费领","扫码","代练","外挂","开挂",
}

--- 检测文本是否包含敏感词，若包含则用 * 替换
---@param text string
---@return string 过滤后文本
---@return boolean 是否触发过过滤
local function filterText(text)
    local lower = text:lower()
    local filtered = false
    local result = text
    for _, word in ipairs(BLOCKED_WORDS) do
        local wl = word:lower()
        -- 查找不区分大小写
        local s, e = lower:find(wl, 1, true)
        while s do
            filtered = true
            local stars = string.rep("*", e - s + 1)
            result = result:sub(1, s - 1) .. stars .. result:sub(e + 1)
            lower = lower:sub(1, s - 1) .. stars .. lower:sub(e + 1)
            s, e = lower:find(wl, s + #stars, true)
        end
    end
    return result, filtered
end

-- ========== 云端 Key ==========
local CLOUD_KEY_WAVE = "tomb_wave"     -- iscores: 波次（排行榜排序）
local CLOUD_KEY_DATA = "tomb_data"     -- values:  墓碑详情 JSON

-- ========== 预设遗言库（玩家未输入时随机） ==========
local DEFAULT_MESSAGES = {
    "我倒在了黎明前…",
    "别踩我的坟！",
    "下次一定能过…",
    "这波敌人太多了😭",
    "差一点就赢了…",
    "替我报仇！",
    "我的装备掉了吗？",
    "又是被Boss带走的",
    "建议削弱第%d波",  -- %d 替换为波次
    "第%d波是我的极限",
    "希望你比我走得更远",
    "有缘再见👋",
}

-- ========== 配置 ==========
local MAX_TOMBSTONES    = 15     -- 场上最大墓碑数
local FETCH_COUNT       = 20     -- 拉取排行榜条目数
local INTERACT_DIST     = 80     -- 交互距离（设计像素）
local FLOAT_AMPLITUDE   = 3      -- 浮动幅度
local FLOAT_SPEED       = 1.5    -- 浮动速度
local TOMBSTONE_EMOJI   = "🪦"   -- 墓碑 emoji
local GHOST_ALPHA_MIN   = 100    -- 幽灵最低透明度
local GHOST_ALPHA_MAX   = 200    -- 幽灵最高透明度

-- ========== 运行时状态 ==========
local tombstones = {}            -- 已拉取的墓碑列表
local fetched = false            -- 本局是否已拉取
local fetching = false           -- 是否正在拉取中
local interactTarget = nil       -- 当前可交互的墓碑索引
local showingDetail = false      -- 是否正在展示遗言详情
local showDetailTimer = 0        -- 详情展示计时器
local DETAIL_DURATION = 3.0      -- 详情展示时长

-- ========== 数据上传 ==========

--- 上传墓碑数据（游戏结束时调用）
---@param stats table BattleScene.GetStats() 返回值
---@param charId string 角色 ID
---@param charEmoji string 角色 emoji
---@param lastWords string|nil 玩家遗言（nil 则随机）
function Tombstone.Upload(stats, charId, charEmoji, lastWords)
    if not clientCloud then
        print("[Tombstone] clientCloud 不可用，跳过上传")
        return
    end

    -- 生成遗言
    if not lastWords or lastWords == "" then
        local tpl = DEFAULT_MESSAGES[math.random(#DEFAULT_MESSAGES)] or "替我报仇！"
        if tpl:find("%%d") then
            lastWords = string.format(tpl, stats.wave)
        else
            lastWords = tpl
        end
    end
    lastWords = lastWords or "替我报仇！"
    -- 限制长度
    if #lastWords > 60 then
        lastWords = lastWords:sub(1, 60) .. "…"
    end
    -- 敏感词过滤
    local wasFiltered
    lastWords, wasFiltered = filterText(lastWords)
    if wasFiltered then
        print("[Tombstone] 遗言触发敏感词过滤: " .. lastWords)
    end

    local data = {
        msg   = lastWords,
        char  = charId,
        emoji = charEmoji,
        wave  = stats.wave,
        kills = stats.kills,
        level = stats.level,
        time  = stats.timeStr,
        -- 死亡位置归一化到 0~1 方便不同分辨率复原
        px    = math.floor((stats.deathX or 6000) / Config.WORLD_SIZE * 1000) / 1000,
        py    = math.floor((stats.deathY or 6000) / Config.WORLD_SIZE * 1000) / 1000,
    }

    clientCloud:BatchSet()
        :SetInt(CLOUD_KEY_WAVE, stats.wave)
        :Set(CLOUD_KEY_DATA, data)
        :Save("上传墓碑", {
            ok = function()
                print("[Tombstone] 上传成功: wave=" .. stats.wave .. " msg=" .. lastWords)
            end,
            error = function(code, reason)
                print("[Tombstone] 上传失败: " .. tostring(reason))
            end
        })
end

-- ========== 数据拉取 ==========

--- 拉取其他玩家的墓碑数据（开局初始化时调用）
function Tombstone.Fetch()
    if not clientCloud then
        print("[Tombstone] clientCloud 不可用，跳过拉取")
        fetched = true
        return
    end
    if fetching then return end
    fetching = true

    clientCloud:GetRankList(CLOUD_KEY_WAVE, 0, FETCH_COUNT, {
        ok = function(rankList)
            fetching = false
            fetched = true
            tombstones = {}

            if not rankList or #rankList == 0 then
                print("[Tombstone] 排行榜为空")
                return
            end

            local myId = clientCloud.userId
            local count = 0

            for _, item in ipairs(rankList) do
                if count >= MAX_TOMBSTONES then break end
                -- 跳过自己
                if item.userId ~= myId then
                    local data = item.score and item.score[CLOUD_KEY_DATA]
                    local wave = item.iscore and item.iscore[CLOUD_KEY_WAVE] or 0
                    if data and type(data) == "table" then
                        -- 从归一化坐标恢复世界坐标，加随机偏移避免重叠
                        local wx = (data.px or 0.5) * Config.WORLD_SIZE + math.random(-200, 200)
                        local wy = (data.py or 0.5) * Config.WORLD_SIZE + math.random(-200, 200)
                        wx = math.max(100, math.min(Config.WORLD_SIZE - 100, wx))
                        wy = math.max(100, math.min(Config.WORLD_SIZE - 100, wy))

                        count = count + 1
                        table.insert(tombstones, {
                            userId   = item.userId,
                            nickname = nil,   -- 稍后批量查询
                            msg      = data.msg or "...",
                            charEmoji = data.emoji or "👻",
                            wave     = wave,
                            kills    = data.kills or 0,
                            level    = data.level or 1,
                            timeStr  = data.time or "??:??",
                            worldX   = wx,
                            worldY   = wy,
                            -- 渲染用
                            floatPhase = math.random() * 6.28,
                        })
                    end
                end
            end

            print("[Tombstone] 拉取到 " .. count .. " 个墓碑")

            -- 批量查询昵称
            if count > 0 then
                local userIds = {}
                for _, t in ipairs(tombstones) do
                    table.insert(userIds, t.userId)
                end
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do
                            map[info.userId] = info.nickname or ""
                        end
                        for _, t in ipairs(tombstones) do
                            t.nickname = map[t.userId] or "旅人"
                        end
                        print("[Tombstone] 昵称查询完成")
                    end,
                    onError = function(code)
                        print("[Tombstone] 昵称查询失败: " .. tostring(code))
                        for _, t in ipairs(tombstones) do
                            t.nickname = "旅人"
                        end
                    end
                })
            end
        end,
        error = function(code, reason)
            fetching = false
            fetched = true
            print("[Tombstone] 拉取失败: " .. tostring(reason))
        end
    }, CLOUD_KEY_DATA)  -- 附加读取 tombstone_data values
end

-- ========== 更新逻辑 ==========

--- 每帧更新（检测玩家靠近墓碑）
---@param dt number
---@param playerX number
---@param playerY number
function Tombstone.Update(dt, playerX, playerY)
    if #tombstones == 0 then return end

    -- 详情展示倒计时
    if showingDetail then
        showDetailTimer = showDetailTimer - dt
        if showDetailTimer <= 0 then
            showingDetail = false
            interactTarget = nil
        end
        return  -- 展示中不再检测新的交互
    end

    -- 检测最近的墓碑
    local closestIdx = nil
    local closestDist = INTERACT_DIST

    for i, t in ipairs(tombstones) do
        local dx = playerX - t.worldX
        local dy = playerY - t.worldY
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < closestDist then
            closestDist = dist
            closestIdx = i
        end
    end

    interactTarget = closestIdx
end

--- 触发交互（玩家点击/触碰墓碑时调用）
---@return table|nil 墓碑数据（用于 UI 展示），nil 表示无可交互墓碑
function Tombstone.Interact()
    if interactTarget and tombstones[interactTarget] then
        showingDetail = true
        showDetailTimer = DETAIL_DURATION
        return tombstones[interactTarget]
    end
    return nil
end

--- 自动触发靠近交互（简化版：靠近即显示，无需点击）
function Tombstone.AutoInteract()
    if interactTarget and not showingDetail then
        showingDetail = true
        showDetailTimer = DETAIL_DURATION
    end
end

-- ========== 渲染 ==========

--- 渲染所有墓碑（在掉落物层之后、敌人层之前）
---@param vg userdata NanoVG context
---@param camX number
---@param camY number
---@param viewW number
---@param viewH number
---@param gameTime number 全局时间（用于浮动动画）
function Tombstone.Render(vg, camX, camY, viewW, viewH, gameTime)
    if #tombstones == 0 then return end

    local t = gameTime or 0

    for i, tomb in ipairs(tombstones) do
        local sx = tomb.worldX - camX
        local sy = tomb.worldY - camY

        -- 视口裁剪
        if sx > -60 and sx < viewW + 60 and sy > -60 and sy < viewH + 60 then
            -- 浮动动画
            local floatY = math.sin(t * FLOAT_SPEED + tomb.floatPhase) * FLOAT_AMPLITUDE

            -- 幽灵透明度呼吸
            local breathAlpha = GHOST_ALPHA_MIN +
                (GHOST_ALPHA_MAX - GHOST_ALPHA_MIN) * (0.5 + 0.5 * math.sin(t * 1.2 + tomb.floatPhase))
            breathAlpha = math.floor(breathAlpha)

            local isTarget = (i == interactTarget)

            -- 底部阴影
            nvgBeginPath(vg)
            nvgEllipse(vg, sx, sy + 12, 14, 4)
            nvgFillColor(vg, nvgRGBA(100, 50, 200, 30))
            nvgFill(vg)

            -- Bloom 光晕（靠近时增强）
            if Glow.enabled then
                local glowAlpha = isTarget and 60 or 25
                Glow.DrawCircleBloom255(vg, sx, sy + floatY, 22,
                    150, 100, 255, glowAlpha)
            end

            -- 墓碑 emoji
            nvgFontSize(vg, isTarget and 30 or 24)
            nvgTextAlign(vg, NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, breathAlpha))
            nvgText(vg, sx, sy + floatY - 2, TOMBSTONE_EMOJI)

            -- 角色幽灵（小号，墓碑上方）
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(breathAlpha * 0.5)))
            nvgText(vg, sx, sy + floatY - 22, tomb.charEmoji)

            -- 靠近时显示简要信息
            if isTarget then
                -- 名字标签
                nvgFontSize(vg, 12)
                nvgFillColor(vg, nvgRGBA(200, 180, 255, 220))
                nvgText(vg, sx, sy + floatY - 38, (tomb.nickname or "旅人"))

                -- "靠近查看" 提示
                if not showingDetail then
                    nvgFontSize(vg, 10)
                    nvgFillColor(vg, nvgRGBA(180, 150, 255, math.floor(120 + 60 * math.sin(t * 3))))
                    nvgText(vg, sx, sy + 24, "💬 靠近查看遗言")
                end
            end
        end
    end

    -- 遗言详情气泡
    if showingDetail and interactTarget and tombstones[interactTarget] then
        Tombstone.RenderDetail(vg, camX, camY, viewW, viewH)
    end
end

--- 渲染遗言详情气泡
function Tombstone.RenderDetail(vg, camX, camY, viewW, viewH)
    local tomb = tombstones[interactTarget]
    if not tomb then return end

    local sx = tomb.worldX - camX
    local sy = tomb.worldY - camY

    -- 气泡位置（墓碑上方）
    local bubbleX = sx
    local bubbleY = sy - 65
    local bubbleW = 200
    local bubbleH = 70

    -- 确保气泡在屏幕内
    bubbleX = math.max(bubbleW / 2 + 10, math.min(viewW - bubbleW / 2 - 10, bubbleX))
    bubbleY = math.max(10, bubbleY)

    -- 淡入淡出
    local fadeAlpha = 1.0
    if showDetailTimer < 0.5 then
        fadeAlpha = showDetailTimer / 0.5
    elseif showDetailTimer > DETAIL_DURATION - 0.3 then
        fadeAlpha = (DETAIL_DURATION - showDetailTimer) / 0.3
    end
    fadeAlpha = math.max(0, math.min(1, fadeAlpha))
    local alpha = math.floor(fadeAlpha * 230)

    -- 气泡背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bubbleX - bubbleW / 2, bubbleY - bubbleH / 2, bubbleW, bubbleH, 10)
    nvgFillColor(vg, nvgRGBA(20, 10, 40, alpha))
    nvgFill(vg)

    -- 气泡边框（霓虹紫）
    nvgStrokeColor(vg, nvgRGBA(150, 80, 255, math.floor(fadeAlpha * 150)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- Bloom 气泡光晕
    if Glow.enabled then
        Glow.DrawCircleBloom255(vg, bubbleX, bubbleY, 50, 120, 60, 255, math.floor(fadeAlpha * 30))
    end

    nvgTextAlign(vg, NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)

    -- 遗言内容
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgText(vg, bubbleX, bubbleY - 16, "「" .. tomb.msg .. "」")

    -- 玩家信息行
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(180, 160, 255, math.floor(fadeAlpha * 180)))
    local infoLine = string.format("%s %s · 第%d波 · %d击杀",
        tomb.charEmoji, tomb.nickname or "旅人", tomb.wave, tomb.kills)
    nvgText(vg, bubbleX, bubbleY + 6, infoLine)

    -- 存活时间
    nvgFontSize(vg, 9)
    nvgFillColor(vg, nvgRGBA(140, 120, 200, math.floor(fadeAlpha * 140)))
    nvgText(vg, bubbleX, bubbleY + 22, "存活 " .. tomb.timeStr)
end

-- ========== 状态查询 ==========

--- 是否有可交互墓碑
function Tombstone.HasTarget()
    return interactTarget ~= nil
end

--- 是否正在展示遗言
function Tombstone.IsShowingDetail()
    return showingDetail
end

--- 获取墓碑数量
function Tombstone.GetCount()
    return #tombstones
end

--- 重置（新局开始时）
function Tombstone.Reset()
    tombstones = {}
    fetched = false
    fetching = false
    interactTarget = nil
    showingDetail = false
    showDetailTimer = 0
end

return Tombstone
