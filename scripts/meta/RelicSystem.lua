--- ============================================================================
--- 局外养成 - 遗物系统
--- 遗物提供跨局永久加成，通过局内金币 🪙 购买升级
--- ============================================================================

local RelicSystem = {}

-- ============================================================================
-- 遗物定义（顺序即商店显示顺序）
-- ============================================================================
-- cost formula: base ^ (currentLevel + 1)
-- base=2: 2, 4, 8, 16, 32, 64 ...（多级普通遗物）
-- base=1000: 1000（首次解锁），1000000（第二级，极难）
-- ============================================================================
RelicSystem.RELICS = {
    {
        id   = "strength",
        name = "力量遗物",
        icon = "⚔️",
        desc = "每级全局攻击+0.2%",
        base = 2,
    },
    {
        id   = "agility",
        name = "敏捷遗物",
        icon = "🎯",
        desc = "每级暴击率+0.2%",
        base = 2,
    },
    {
        id   = "vitality",
        name = "生命遗物",
        icon = "❤️",
        desc = "每级基础生命+0.25%",
        base = 2,
    },
    {
        id   = "speed",
        name = "速度遗物",
        icon = "⚡",
        desc = "每级攻击间隔-0.5%，移速+0.5%",
        base = 2,
    },
    {
        id   = "luck",
        name = "幸运遗物",
        icon = "🍀",
        desc = "每级掉落物出现率+1%",
        base = 2,
    },
    {
        id   = "armor",
        name = "护甲遗物",
        icon = "🪨",
        desc = "每级受伤减免+0.3%",
        base = 2,
    },
    {
        id   = "exp_boost",
        name = "学识遗物",
        icon = "📖",
        desc = "每级经验获取+0.3%",
        base = 2,
    },
    {
        id   = "magnet",
        name = "磁力遗物",
        icon = "🧲",
        desc = "每级拾取范围+1%",
        base = 2,
    },
    {
        id   = "guardian",
        name = "守护遗物",
        icon = "🛡️",
        desc = "每波开始获得N次护卫充能，将单次受伤降为1点（N=遗物等级）",
        base = 1000,
    },
    {
        id   = "flight",
        name = "飞行遗物",
        icon = "🛸",
        desc = "解锁绿色无人机技能，轨道更大，等级上限=遗物等级+3（需1级以上）",
        base = 1000,
    },
}

-- 通过 ID 查找遗物定义
function RelicSystem.FindRelic(relicId)
    for _, r in ipairs(RelicSystem.RELICS) do
        if r.id == relicId then return r end
    end
    return nil
end

--- 计算遗物下一级升级费用
--- cost = base ^ (currentLevel + 1)
---@param relicId string
---@param currentLevel number 当前等级（0=未解锁）
---@return number
function RelicSystem.GetCost(relicId, currentLevel)
    local relic = RelicSystem.FindRelic(relicId)
    if not relic then return 999999 end
    return relic.base ^ (currentLevel + 1)
end

--- 计算所有遗物的加成，写入 Player 专属字段
--- 应在 BattleScene.Init → Player.Init 之后调用，再调用 Player.RecalcStats
---@param Player table
---@param relicLevels table { [relicId] = level }
function RelicSystem.ApplyBonusesToPlayer(Player, relicLevels)
    relicLevels = relicLevels or {}

    -- 力量：全局攻击+0.2%/级
    Player.relicAtkBonus      = 0.002  * (relicLevels["strength"] or 0)
    -- 敏捷：暴击率+0.2%/级
    Player.relicCritBonus     = 0.002  * (relicLevels["agility"]  or 0)
    -- 生命：基础生命+0.25%/级
    Player.relicHpBonus       = 0.0025 * (relicLevels["vitality"] or 0)
    -- 速度：攻击间隔-0.5%/级，移速+0.5%/级
    Player.relicFireRateBonus = 0.005  * (relicLevels["speed"]    or 0)
    Player.relicSpeedBonus    = 0.005  * (relicLevels["speed"]    or 0)
    -- 幸运：掉落物出现率+1%/级
    Player.relicLuckBonus     = 0.01   * (relicLevels["luck"]     or 0)
    -- 护甲：受伤减免+0.3%/级
    Player.relicArmorBonus    = 0.003  * (relicLevels["armor"]    or 0)
    -- 学识：经验获取+0.3%/级
    Player.relicExpBonus      = 0.003  * (relicLevels["exp_boost"] or 0)
    -- 磁力：拾取范围+1%/级
    Player.relicMagnetBonus   = 0.01   * (relicLevels["magnet"]   or 0)
    -- 守护：每波充能上限 = 遗物等级
    Player.guardianCharges    = 0
    Player.guardianMaxCharges = relicLevels["guardian"] or 0
end

--- 获取绿色无人机的有效最大等级
--- = flight relic level + 3（flight >= 1 时才有效）
---@param relicLevels table
---@return number
function RelicSystem.GetGreenDroneMaxLevel(relicLevels)
    local flightLevel = (relicLevels or {})["flight"] or 0
    if flightLevel < 1 then return 0 end
    return flightLevel + 3
end

return RelicSystem
