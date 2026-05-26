--- ============================================================================
--- 符文系统 - Boss击杀掉落的最高级局外养成
--- 单品质（传说/红色），14个独立符文，2个装备槽
--- 触发型机制效果，非简单数值堆叠
--- ============================================================================

local RuneSystem = {}

-- ============================================================================
-- 品质定义（唯一品质）
-- ============================================================================

RuneSystem.RARITY = "legendary"
RuneSystem.RARITY_CONFIG = {
    name      = "传说",
    color     = { 255, 50, 50 },
    glowColor = { 255, 60, 60, 140 },
    sellPrice = 50000,  -- 不可出售，保留字段
}

-- ============================================================================
-- 掉落
-- ============================================================================

RuneSystem.DROP_CHANCE = 0.05  -- 5% 击杀对应Boss后掉落

-- ============================================================================
-- 装备限制
-- ============================================================================

RuneSystem.MAX_EQUIPPED = 2  -- 独立于图腾3槽

-- ============================================================================
-- 符文定义（14个，与Boss一一对应）
-- ============================================================================

RuneSystem.RUNES = {
    {
        id       = "rune_police",
        bossId   = "police",
        name     = "警戒反射",
        icon     = "🚨",
        desc     = "受伤后3秒内移速+40%，攻速+25%（CD 4秒）",
        cooldown = 4,
        speedBuff    = 0.40,
        atkSpeedBuff = 0.25,
        buffDuration = 3,
    },
    {
        id       = "rune_worker",
        bossId   = "worker",
        name     = "钢铁壁垒",
        icon     = "🪖",
        desc     = "每6秒获得1层护盾（上限3层），可抵挡致命伤害",
        interval = 6,
        maxLayers = 3,
    },
    {
        id       = "rune_chef",
        bossId   = "chef",
        name     = "饕餮盛宴",
        icon     = "🍖",
        desc     = "暴击40%概率回复8%最大HP并使下次必定暴击（CD 3秒）",
        cooldown = 3,
        healPercent = 0.08,
        triggerChance = 0.40,
    },
    {
        id       = "rune_programmer",
        bossId   = "programmer",
        name     = "递归循环",
        icon     = "🔄",
        desc     = "击杀敌人15%概率释放连锁闪电，弹射4次（每次80%ATK+30%减速2秒，CD 2秒）",
        killChance = 0.15,
        cooldown = 2,
        chainCount = 4,
        chainDmgPercent = 0.80,
        chainRange = 200,
        slowPercent = 0.30,
        slowDuration = 2,
    },
    {
        id       = "rune_firefighter",
        bossId   = "firefighter",
        name     = "浴火重生",
        icon     = "🔥",
        desc     = "HP<35%时3秒免疫+AOE火焰伤害120%ATK（CD 15秒）",
        cooldown = 15,
        hpThreshold = 0.35,
        immuneDuration = 3,
        aoeDmgPercent = 1.20,
        aoeRadius = 120,
    },
    {
        id       = "rune_vampire",
        bossId   = "vampire",
        name     = "血族契约",
        icon     = "🩸",
        desc     = "满血时攻击力+25%；击杀15%概率回复5%最大HP",
        fullHpAtkBonus = 0.25,
        killHealChance = 0.15,
        killHealPercent = 0.05,
    },
    {
        id       = "rune_gentleman",
        bossId   = "gentleman",
        name     = "完美主义",
        icon     = "🎩",
        desc     = "2秒未受伤：伤害+80%+穿透+2；5秒未受伤：额外击退",
        tier1Time = 2,
        tier1DmgBonus = 0.80,
        tier1Pierce = 2,
        tier2Time = 5,
    },
    {
        id       = "rune_scientist",
        bossId   = "scientist",
        name     = "裂变弹头",
        icon     = "⚛️",
        desc     = "穿透后40%概率分裂2颗子弹（75%伤害）",
        splitChance = 0.40,
        splitCount = 2,
        splitDmgPercent = 0.75,
        splitAngle = 45,
    },
    {
        id       = "rune_pirate",
        bossId   = "pirate",
        name     = "夺宝奇兵",
        icon     = "💰",
        desc     = "Boss击杀+80%金币；每击杀15个敌人召唤宝箱（CD 20秒）",
        bossGoldBonus = 0.80,
        treasureThreshold = 15,
        treasureCooldown = 20,
    },
    {
        id       = "rune_dj",
        bossId   = "dj",
        name     = "节拍风暴",
        icon     = "🎵",
        desc     = "每3秒AOE击退+100%ATK伤害+40%减速2秒",
        interval = 3,
        aoeDmgPercent = 1.0,
        aoeRadius = 180,
        slowPercent = 0.40,
        slowDuration = 2,
    },
    {
        id       = "rune_doctor",
        bossId   = "doctor",
        name     = "急救协议",
        icon     = "💊",
        desc     = "HP<35%时回复40%HP+3秒减伤50%（CD 15秒）",
        hpThreshold = 0.35,
        healPercent = 0.40,
        dmgReduction = 0.50,
        reductionDuration = 3,
        cooldown = 15,
    },
    {
        id       = "rune_ninja",
        bossId   = "ninja",
        name     = "影分身术",
        icon     = "👤",
        desc     = "暴击40%概率召唤影分身（8秒，100%ATK，上限2）",
        triggerChance = 0.40,
        cloneDuration = 8,
        cloneDmgPercent = 1.0,
        maxClones = 2,
    },
    {
        id       = "rune_robot",
        bossId   = "robot",
        name     = "超频核心",
        icon     = "⚡",
        desc     = "每8击杀触发超频（攻速×3，伤害+80%，5秒）",
        killThreshold = 8,
        droneAtkSpeedMult = 3,
        droneDmgBonus = 0.80,
        burstDuration = 5,
        -- 无无人机替代：下5发子弹+50%伤害
        noDroneBullets = 5,
        noDroneDmgBonus = 0.50,
    },
    {
        id       = "rune_demon_king",
        bossId   = "demon_king",
        name     = "深渊王权",
        icon     = "👁️",
        desc     = "击杀敌人叠加暗影（上限30层），满层消耗全部层数释放暗影爆发（300%ATK全屏+全属性每层+1%持续10秒）",
        maxStacks = 30,
        burstDmgPercent = 3.0,
        buffPerStack = 0.01,
        buffDuration = 10,
    },
}

-- ============================================================================
-- 索引表（快速查找）
-- ============================================================================

--- runeId → 定义
RuneSystem._BY_ID = {}
--- bossId → 定义
RuneSystem._BY_BOSS = {}

for _, rune in ipairs(RuneSystem.RUNES) do
    RuneSystem._BY_ID[rune.id] = rune
    RuneSystem._BY_BOSS[rune.bossId] = rune
end

-- ============================================================================
-- 核心函数
-- ============================================================================

--- 根据 runeId 获取符文定义
---@param runeId string
---@return table|nil
function RuneSystem.GetRune(runeId)
    return RuneSystem._BY_ID[runeId]
end

--- 根据 bossId 获取对应符文定义
---@param bossId string
---@return table|nil
function RuneSystem.GetRuneByBoss(bossId)
    return RuneSystem._BY_BOSS[bossId]
end

--- 尝试掉落符文（击杀Boss后调用）
--- 返回 nil 表示未掉落
---@param bossId string Boss的id（如 "police", "worker" 等）
---@param ownedRunes table 已拥有的符文ID集合 { [runeId]=true }
---@return table|nil { id = string } 或 nil
function RuneSystem.RollRune(bossId, ownedRunes)
    local runeDef = RuneSystem._BY_BOSS[bossId]
    if not runeDef then return nil end

    -- 已拥有则不再掉落
    if ownedRunes and ownedRunes[runeDef.id] then
        return nil
    end

    -- 概率判定
    if math.random() > RuneSystem.DROP_CHANCE then
        return nil
    end

    return { id = runeDef.id }
end

--- 获取符文显示名称
---@param runeId string
---@return string
function RuneSystem.GetRuneName(runeId)
    local rune = RuneSystem._BY_ID[runeId]
    if not rune then return "未知符文" end
    return rune.name
end

--- 获取符文描述
---@param runeId string
---@return string
function RuneSystem.GetRuneDesc(runeId)
    local rune = RuneSystem._BY_ID[runeId]
    if not rune then return "" end
    return rune.desc
end

--- 获取符文图标
---@param runeId string
---@return string
function RuneSystem.GetRuneIcon(runeId)
    local rune = RuneSystem._BY_ID[runeId]
    return rune and rune.icon or "🔮"
end

--- 计算装备符文的常驻基础值加成
--- 用户要求：对数值的加成均为基础值增强（加算）
---@param equippedRunes string[] 已装备的符文ID列表（最多2个）
---@param equippedBossTotems number 已装备的Boss图腾数量（保留参数兼容性）
---@return table bonuses 基础值加成结构
function RuneSystem.CalcEquippedBonuses(equippedRunes, equippedBossTotems)
    local bonuses = {
        -- 血族契约（满血时的ATK基础值加成）
        vampireFullHpAtkBonus = 0,
        vampireKillHealChance = 0,
        vampireKillHealPercent = 0,
        -- 深渊王权：全属性加成现在由 RuneEffects 动态管理（击杀叠层 → 满层爆发 buff）
        allStatBonus = 0,
        -- 标记已装备的符文集合（供战斗系统查询触发效果）
        equipped = {},  -- { [runeId] = runeDef }
    }

    for _, runeId in ipairs(equippedRunes) do
        local rune = RuneSystem._BY_ID[runeId]
        if rune then
            bonuses.equipped[runeId] = rune

            -- 血族契约：满血ATK基础值+25%
            if rune.id == "rune_vampire" then
                bonuses.vampireFullHpAtkBonus = rune.fullHpAtkBonus
                bonuses.vampireKillHealChance = rune.killHealChance
                bonuses.vampireKillHealPercent = rune.killHealPercent
            end
            -- 深渊王权：不再在此处计算静态加成，改为 RuneEffects.OnKill 中动态触发
        end
    end

    return bonuses
end

--- 获取已拥有的符文总数
---@param ownedRunes table { [runeId]=true }
---@return number
function RuneSystem.GetOwnedCount(ownedRunes)
    local count = 0
    for _ in pairs(ownedRunes or {}) do
        count = count + 1
    end
    return count
end

--- 获取总符文数
---@return number
function RuneSystem.GetTotalCount()
    return #RuneSystem.RUNES
end

return RuneSystem
