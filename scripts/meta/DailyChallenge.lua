--- ============================================================================
--- 每日挑战模式 - 每日配置生成、修改器定义、状态管理
--- 使用 UTC 日期种子确保全服统一
--- ============================================================================

local Config = require("Config")

local DailyChallenge = {}

-- ============================================================================
-- 状态
-- ============================================================================
DailyChallenge.active = false          -- 当前是否在每日挑战中
DailyChallenge.todayConfig = nil       -- 今日配置缓存
DailyChallenge.singleSkillId = nil     -- 专精之路：首次选中的技能ID

-- ============================================================================
-- 敌怪池（9种可选，不含 boss）
-- ============================================================================
local ENEMY_POOL = { "normal", "fast", "tank", "swarm", "charger", "ghost", "shaman", "ranger", "elite" }

-- 每种敌怪类型对应的固定展示 emoji（每日挑战中所有该类型共用同一个）
local ENEMY_DISPLAY_EMOJI = {
    normal  = "👾",
    fast    = "🦇",
    tank    = "🐻",
    swarm   = "🐜",
    charger = "🦏",
    ghost   = "👻",
    shaman  = "🧙",
    ranger  = "🏹",
    elite   = "👹",
}

-- ============================================================================
-- 负面因子池（每日随机 1 个）
-- ============================================================================
local NEGATIVE_FACTORS = {
    {
        id   = "exp_up",
        name = "经验膨胀",
        icon = "📈",
        desc = "升级经验需求 ×1.5",
    },
    {
        id   = "enemy_atk",
        name = "敌怪狂暴",
        icon = "🔥",
        desc = "敌怪攻击力翻倍",
    },
    {
        id   = "enemy_spd",
        name = "敌怪迅捷",
        icon = "💨",
        desc = "敌怪移速翻倍",
    },
    {
        id   = "enemy_hp",
        name = "敌怪坚韧",
        icon = "🛡️",
        desc = "敌怪血量翻倍",
    },
    {
        id   = "boss_double",
        name = "Boss倍增",
        icon = "👑",
        desc = "Boss出现间隔减半",
    },
}

-- ============================================================================
-- 中性因子池（每日随机 3 个不重复）
-- ============================================================================
local NEUTRAL_FACTORS = {
    {
        id   = "single_skill",
        name = "专精之路",
        icon = "🎯",
        desc = "仅1个可获取技能，无等级上限",
    },
    {
        id   = "player_small",
        name = "缩小药水",
        icon = "🔬",
        desc = "体积和血量 -50%",
    },
    {
        id   = "player_big",
        name = "巨大化",
        icon = "🗿",
        desc = "体积和血量 +100%",
    },
    {
        id   = "dmg_crit",
        name = "暴击本能",
        icon = "💥",
        desc = "伤害 -4 点，暴击率翻倍",
    },
    {
        id   = "coin_loot",
        name = "拾金者",
        icon = "🪙",
        desc = "金币掉率 ×2，道具掉率 ×0.5",
    },
    {
        id   = "heart_dot",
        name = "缓释回复",
        icon = "💊",
        desc = "红心改为5s渐进回复",
    },
    {
        id   = "bomb_risk",
        name = "危险炸弹",
        icon = "⚠️",
        desc = "炸弹掉率 ×2，自伤10点",
    },
    {
        id   = "magnet_exp",
        name = "广域拾取",
        icon = "🧲",
        desc = "拾取范围 ×2，经验值 ×0.2",
    },
}

-- ============================================================================
-- 确定性 PRNG（线性同余，确保全服统一）
-- ============================================================================
local function CreateRNG(seed)
    local state = seed
    return function()
        -- 使用简单乘法哈希避免大数溢出
        state = (state * 1103 + 12345) % 65536
        return state
    end
end

-- ============================================================================
-- 获取今日配置（缓存，同一天只计算一次）
-- ============================================================================
function DailyChallenge.GetTodayConfig()
    local utc = os.date("!*t")
    local dateKey = string.format("%02d%02d", utc.month, utc.day)

    -- 缓存命中
    if DailyChallenge.todayConfig and DailyChallenge.todayConfig.dateKey == dateKey then
        return DailyChallenge.todayConfig
    end

    -- 用日期生成种子
    local seed = utc.year * 1000 + utc.yday
    local rng = CreateRNG(seed)

    -- 选敌怪类型
    local enemyIdx = (rng() % #ENEMY_POOL) + 1
    local enemyType = ENEMY_POOL[enemyIdx]
    local enemyEmoji = ENEMY_DISPLAY_EMOJI[enemyType]

    -- 选 1 个负面因子
    local negIdx = (rng() % #NEGATIVE_FACTORS) + 1
    local negativeFactor = NEGATIVE_FACTORS[negIdx]

    -- 选 3 个不重复的中性因子（Fisher-Yates 用 rng）
    local neutralIndices = {}
    for i = 1, #NEUTRAL_FACTORS do neutralIndices[i] = i end
    for i = #neutralIndices, 2, -1 do
        local j = (rng() % i) + 1
        neutralIndices[i], neutralIndices[j] = neutralIndices[j], neutralIndices[i]
    end
    local neutralFactors = {}
    for i = 1, 3 do
        neutralFactors[i] = NEUTRAL_FACTORS[neutralIndices[i]]
    end

    -- 构建因子查找表
    local factorSet = {}
    factorSet[negativeFactor.id] = true
    for _, f in ipairs(neutralFactors) do
        factorSet[f.id] = true
    end

    local config = {
        dateKey        = dateKey,
        enemyType      = enemyType,
        enemyEmoji     = enemyEmoji,
        negativeFactor = negativeFactor,
        neutralFactors = neutralFactors,
        factorSet      = factorSet,
    }

    DailyChallenge.todayConfig = config
    return config
end

--- 判断某因子是否在今日挑战中生效
---@param factorId string
---@return boolean
function DailyChallenge.HasFactor(factorId)
    if not DailyChallenge.active then return false end
    local cfg = DailyChallenge.todayConfig
    if not cfg then return false end
    return cfg.factorSet[factorId] == true
end

--- 获取当日排行榜 iscore key
---@return string
function DailyChallenge.GetLeaderboardKey()
    local cfg = DailyChallenge.GetTodayConfig()
    return "dc_wave_" .. cfg.dateKey
end

--- 重置挑战状态（Game Over 或回到主菜单时调用）
function DailyChallenge.Reset()
    DailyChallenge.active = false
    DailyChallenge.singleSkillId = nil
end

--- 获取所有因子列表（展示用）
---@return table negativeFactor, table neutralFactors
function DailyChallenge.GetAllFactors()
    local cfg = DailyChallenge.GetTodayConfig()
    return cfg.negativeFactor, cfg.neutralFactors
end

--- 获取敌怪类型名称（中文）
function DailyChallenge.GetEnemyTypeName()
    local names = {
        normal = "普通怪", fast = "速敏怪", tank = "坦克怪", swarm = "蜂群怪",
        charger = "冲锋怪", ghost = "幽灵怪", shaman = "巫师怪", ranger = "远程怪",
        elite = "精英怪",
    }
    local cfg = DailyChallenge.GetTodayConfig()
    return names[cfg.enemyType] or cfg.enemyType
end

-- ============================================================================
-- 每日挑战奖励计算
-- ============================================================================

--- 波次奖励阶梯（到达对应波次可获得额外金币）
local WAVE_REWARD_TIERS = {
    { wave =  3, gold =  20, label = "初级" },
    { wave =  5, gold =  50, label = "中级" },
    { wave = 10, gold = 120, label = "高级" },
    { wave = 15, gold = 200, label = "精英" },
    { wave = 20, gold = 350, label = "大师" },
}

--- 排名额外奖励（前3名额外金币）
local RANK_BONUS = {
    [1] = { gold = 200, label = "🥇 冠军" },
    [2] = { gold = 100, label = "🥈 亚军" },
    [3] = { gold =  50, label = "🥉 季军" },
}

--- 计算每日挑战的波次奖励金币
---@param wave number 到达的波次
---@return number totalGold 总奖励金币
---@return table  tiers    已达成的阶梯列表 { {wave, gold, label}, ... }
function DailyChallenge.CalcWaveReward(wave)
    local total = 0
    local reached = {}
    for _, tier in ipairs(WAVE_REWARD_TIERS) do
        if wave >= tier.wave then
            total = total + tier.gold
            reached[#reached + 1] = tier
        end
    end
    return total, reached
end

--- 获取排名奖励配置
---@param rank number|nil 排名（1/2/3 或 nil）
---@return table|nil bonusInfo { gold, label } 或 nil
function DailyChallenge.GetRankBonus(rank)
    if not rank then return nil end
    return RANK_BONUS[rank]
end

--- 上次每日挑战结算信息（供 HUD 展示）
DailyChallenge.lastReward = nil

return DailyChallenge
