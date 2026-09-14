--- ============================================================================
--- 图腾系统 - 掉落+合成+出售 背包系统
--- 四级稀有度：垃圾(75%) / 普通(20%) / 稀有(4.5%) / 罕见(0.5%)
--- 类型：数值(hp/atk/spd/crit/fire_rate/hp_regen/loot)
---       技能(atk_up/speed_up/magnet/knockback/atk_drone)
---       特殊(cross_class)
--- ============================================================================

local TotemSystem = {}

-- ============================================================================
-- 稀有度定义
-- ============================================================================

TotemSystem.RARITY = {
    JUNK      = "junk",
    NORMAL    = "normal",
    RARE      = "rare",
    LEGENDARY = "legendary",
}

--- 稀有度顺序（用于合成升降级）
local RARITY_ORDER = { "junk", "normal", "rare", "legendary" }

--- 稀有度 → 数字索引映射
local RARITY_INDEX = {}
for i, r in ipairs(RARITY_ORDER) do
    RARITY_INDEX[r] = i
end

--- 稀有度配置
TotemSystem.RARITY_CONFIG = {
    junk      = { name = "垃圾", color = { 140, 140, 140 }, glowColor = { 140, 140, 140,  60 }, sellPrice = 10    },
    normal    = { name = "普通", color = { 180, 180, 180 }, glowColor = { 200, 200, 200,  80 }, sellPrice = 100   },
    rare      = { name = "稀有", color = {  80, 160, 255 }, glowColor = {  80, 160, 255, 100 }, sellPrice = 1000  },
    legendary = { name = "罕见", color = { 255, 160,  30 }, glowColor = { 255, 180,  60, 120 }, sellPrice = 10000 },
}

--- Boss 掉落稀有度概率
local DROP_WEIGHTS = {
    { rarity = "junk",      weight = 750 },
    { rarity = "normal",    weight = 200 },
    { rarity = "rare",      weight =  45 },
    { rarity = "legendary", weight =   5 },
}
local DROP_TOTAL_WEIGHT = 0
for _, dw in ipairs(DROP_WEIGHTS) do
    DROP_TOTAL_WEIGHT = DROP_TOTAL_WEIGHT + dw.weight
end

-- ============================================================================
-- 类型定义
-- ============================================================================

TotemSystem.TYPE = {
    -- 数值类
    HP        = "hp",
    ATK       = "atk",
    SPD       = "spd",
    CRIT      = "crit",
    FIRE_RATE = "fire_rate",
    HP_REGEN  = "hp_regen",
    LOOT      = "loot",
    -- 技能类
    ATK_UP      = "atk_up",
    SPEED_UP    = "speed_up",
    MAGNET      = "magnet",
    KNOCKBACK   = "knockback",
    DRONE       = "atk_drone",
    -- 特殊类
    CROSS_CLASS = "cross_class",
}

--- 类型配置（category: "stat"=数值, "skill"=技能, "special"=特殊）
TotemSystem.TYPE_CONFIG = {
    -- 数值类
    hp        = { name = "生命",     icon = "❤️",  desc = "初始HP",        category = "stat" },
    atk       = { name = "攻击",     icon = "⚔️",  desc = "初始ATK",       category = "stat" },
    spd       = { name = "速度",     icon = "👟",  desc = "初始SPD",       category = "stat" },
    crit      = { name = "暴击",     icon = "🎯",  desc = "暴击率",        category = "stat", unit = "%" },
    fire_rate = { name = "射速",     icon = "🔥",  desc = "攻击间隔降低",  category = "stat", unit = "%" },
    hp_regen  = { name = "掘金",     icon = "🪙",  desc = "金币掉取率",    category = "stat", unit = "%" },
    loot      = { name = "幸运",     icon = "🍀",  desc = "掉落率提升",    category = "stat", unit = "%" },
    -- 技能类（icon 与 Config.SKILLS 保持一致）
    atk_up    = { name = "攻击提升", icon = "⚔️", desc = "开局携带一级攻击提升", category = "skill" },
    speed_up  = { name = "移速提升", icon = "👟", desc = "开局携带一级移速提升", category = "skill" },
    magnet    = { name = "磁力增强", icon = "🧲", desc = "开局携带一级磁力增强", category = "skill" },
    knockback = { name = "击退冲击", icon = "💥", desc = "开局携带一级击退冲击", category = "skill" },
    atk_drone = { name = "攻击无人机", icon = "🛸", desc = "开局携带一级攻击无人机", category = "skill" },
    -- 特殊类
    cross_class = { name = "异界天赋", icon = "🌀", desc = "未毕业即可学习其他角色技能", category = "special" },
}

--- 按稀有度可掉落的类型池（通用Boss掉落，Boss系列图腾走专属掉落逻辑）
local TYPES_BY_RARITY = {
    junk      = { "hp", "atk", "spd" },
    normal    = { "hp", "atk", "spd", "crit", "fire_rate", "hp_regen", "loot",
                  "atk_up", "speed_up", "magnet", "knockback" },
    rare      = { "hp", "atk", "spd", "crit", "fire_rate", "hp_regen", "loot",
                  "atk_drone" },
    legendary = { "hp", "atk", "spd", "crit", "fire_rate", "hp_regen", "loot", "cross_class" },
}

--- 合法图腾key集合（用于 ExpandTotems 向后兼容校验）
local VALID_TOTEM_KEYS = {}
for rarity, types in pairs(TYPES_BY_RARITY) do
    for _, typeId in ipairs(types) do
        VALID_TOTEM_KEYS[typeId .. "_" .. rarity] = true
    end
end

-- ============================================================================
-- 玩家数值计算公式（Player.RecalcStats）
-- ============================================================================
--
-- 【基础属性】图腾固定值加入基础属性，享受升级成长 + 百分比放大
--
--   生命 = floor( (基础HP×角色倍率 + 图腾HP固定值) × (1 + HP成长×(等级-1))
--                 × (1 + 技能HP% + 遗物HP% + 图腾HP%) )
--
--   攻击 = floor( (基础ATK×角色倍率 + 图腾ATK固定值) × (1 + ATK成长×(等级-1))
--                 × (1 + 技能ATK% + 遗物ATK% + 图腾ATK%) )
--
--   速度 = (基础SPD×角色倍率 + 图腾SPD固定值)
--          × (1 + 技能SPD% + 遗物SPD% + 图腾SPD%)
--
-- 【暴击率】最终加算（不乘基础）
--
--   暴击率 = 基础暴击×角色倍率 + 暴击成长×(等级-1)
--            + 技能暴击% + 遗物暴击% + 图腾暴击%
--
-- 【攻击间隔】
--
--   攻击间隔 = 基础间隔 × (1 - 技能攻速% - 遗物攻速% - 图腾攻速%)
--              下限 0.1 秒
--
-- 【伤害结算】
--
--   基础伤害 = 攻击力
--   暴击判定 → if random() < 暴击率 then 伤害 × (暴击倍率 + 图腾暴击伤害%)
--
-- 【加成来源映射】
--   图腾固定值: hp/atk/spd 类型 → VALUE_TABLE[稀有度][类型] → 加入基础属性
--   暴击/攻速/掉落: crit/fire_rate/loot 类型 → VALUE_TABLE 值 ÷ 100 → 加算
--
-- ============================================================================

-- ============================================================================
-- 数值表（稀有度 × 类型 → 加成数值）
-- ============================================================================

local VALUE_TABLE = {
    junk = {
        hp  = 5,
        atk = 1,
        spd = 10,
        -- crit/fire_rate/hp_regen/loot 垃圾品质不掉
    },
    normal = {
        hp        = 15,
        atk       = 3,
        spd       = 30,
        crit      = 5,      -- +5% 暴击率
        fire_rate = 5,      -- 攻击间隔-5%
        hp_regen  = 10,     -- 金币掉取率+10%
        loot      = 8,      -- 掉落率+8%
    },
    rare = {
        hp        = 50,
        atk       = 10,
        spd       = 80,
        crit      = 12,     -- +12%
        fire_rate = 12,     -- -12%
        hp_regen  = 20,     -- 金币掉取率+20%
        loot      = 18,     -- +18%
    },
    legendary = {
        hp        = 150,
        atk       = 30,
        spd       = 200,
        crit      = 25,     -- +25%
        fire_rate = 25,     -- -25%
        hp_regen  = 35,     -- 金币掉取率+35%
        loot      = 25,     -- +25%
    },
}

-- ============================================================================
-- 背包限制
-- ============================================================================

TotemSystem.MAX_INVENTORY = 600
TotemSystem.MAX_EQUIPPED  = 3

-- ============================================================================
-- 核心函数
-- ============================================================================

--- 随机掉落稀有度
---@return string rarity
function TotemSystem.RollRarity()
    local r = math.random(1, DROP_TOTAL_WEIGHT)
    local acc = 0
    for _, dw in ipairs(DROP_WEIGHTS) do
        acc = acc + dw.weight
        if r <= acc then
            return dw.rarity
        end
    end
    return "junk"  -- fallback
end

--- 随机掉落一个图腾（类型按稀有度池随机）
---@return table { typeId = string, rarity = string }
function TotemSystem.RollTotem()
    local rarity = TotemSystem.RollRarity()
    local pool = TYPES_BY_RARITY[rarity] or { "hp", "atk", "spd" }
    local typeId = pool[math.random(1, #pool)]
    return { typeId = typeId, rarity = rarity }
end

--- 获取图腾的属性加成数值
--- 数值类返回对应加成值，技能类返回1（代表1级），特殊类返回0
---@param typeId string
---@param rarity string
---@return number
function TotemSystem.GetTotemValue(typeId, rarity)
    local tc = TotemSystem.TYPE_CONFIG[typeId]
    if not tc then return 0 end
    if tc.category == "skill" then return 1 end
    if tc.category == "special" then return 0 end
    -- 数值类
    local rarityTable = VALUE_TABLE[rarity]
    if not rarityTable then return 0 end
    return rarityTable[typeId] or 0
end

--- 获取图腾显示名称
---@param typeId string
---@param rarity string
---@return string
function TotemSystem.GetTotemName(typeId, rarity)
    local rc = TotemSystem.RARITY_CONFIG[rarity]
    local tc = TotemSystem.TYPE_CONFIG[typeId]
    if not rc or not tc then return "未知图腾" end
    return rc.name .. tc.name .. "图腾"
end

--- 获取图腾描述（含数值）
---@param typeId string
---@param rarity string
---@return string
function TotemSystem.GetTotemDesc(typeId, rarity)
    local tc = TotemSystem.TYPE_CONFIG[typeId]
    if not tc then return "" end
    -- 技能类/特殊类直接返回描述
    if tc.category == "skill" or tc.category == "special" then
        return tc.desc
    end
    -- 数值类（含百分比单位）
    local val = TotemSystem.GetTotemValue(typeId, rarity)
    if tc.unit == "%" then
        -- 百分比类型：显示百分号
        if val == math.floor(val) then
            return tc.desc .. " +" .. tostring(math.floor(val)) .. "%"
        else
            return tc.desc .. " +" .. string.format("%.1f", val) .. "%"
        end
    elseif typeId == "atk" then
        return tc.desc .. " +" .. string.format("%.1f", val)
    else
        return tc.desc .. " +" .. tostring(math.floor(val))
    end
end

--- 获取图腾图标
---@param typeId string
---@return string
function TotemSystem.GetTotemIcon(typeId)
    local tc = TotemSystem.TYPE_CONFIG[typeId]
    return tc and tc.icon or "🏺"
end

--- 获取出售价格
---@param rarity string
---@return number
function TotemSystem.GetSellPrice(rarity)
    local rc = TotemSystem.RARITY_CONFIG[rarity]
    return rc and rc.sellPrice or 0
end

--- 获取稀有度配置
---@param rarity string
---@return table
function TotemSystem.GetRarityConfig(rarity)
    return TotemSystem.RARITY_CONFIG[rarity] or TotemSystem.RARITY_CONFIG.junk
end

-- ============================================================================
-- 合成系统
-- ============================================================================

--- 合成3个同稀有度图腾 → 1个新图腾
--- 50% 升一级，40% 保持，10% 降一级（垃圾不降级）
---@param rarity string 输入的稀有度
---@return string newRarity 合成结果稀有度
function TotemSystem.Synthesize(rarity)
    local idx = RARITY_INDEX[rarity]
    if not idx then return rarity end

    local roll = math.random(1, 100)
    if roll <= 30 then
        -- 30% 升级
        local newIdx = math.min(idx + 1, #RARITY_ORDER)
        return RARITY_ORDER[newIdx] or rarity
    elseif roll <= 80 then
        -- 50% 保持
        return rarity
    else
        -- 20% 降级（垃圾不降）
        local newIdx = math.max(1, idx - 1)
        return RARITY_ORDER[newIdx] or rarity
    end
end

--- 检查指定稀有度是否可以合成（需要 >= 3 个且不是罕见）
---@param rarity string
---@param count number 该稀有度的图腾数量
---@return boolean
function TotemSystem.CanSynthesize(rarity, count)
    if rarity == "legendary" then return false end
    return count >= 3
end

-- ============================================================================
-- 聚合编码（用于云端存储）
-- ============================================================================

--- 将图腾列表聚合为计数表
--- { "hp_junk" = 42, "atk_normal" = 5, ... }
---@param totems table[] 图腾数组 { {typeId, rarity}, ... }
---@return table counts { [key] = count }
function TotemSystem.AggregateTotems(totems)
    local counts = {}
    for _, t in ipairs(totems) do
        -- v3: 使用数字 _id 作为 key（如 "1_1" 代替 "hp_junk"）
        local tid = TotemSystem.GetTypeNumId(t.typeId)
        local rid = RARITY_INDEX[t.rarity]
        if rid then
            local key = tid .. "_" .. rid
            counts[key] = (counts[key] or 0) + 1
        else
            print("[TotemSystem] WARN AggregateTotems: invalid rarity '"
                  .. tostring(t.rarity) .. "' for typeId=" .. tostring(t.typeId) .. ", skipped")
        end
    end
    return counts
end

--- 从聚合计数表展开为图腾数组（兼容旧字符串 key 和新数字 key）
---@param counts table { [key] = count }
---@return table[] totems
function TotemSystem.ExpandTotems(counts)
    local totems = {}
    for key, count in pairs(counts) do
        local a, b = key:match("^(.+)_(.+)$")
        if a and b then
            local typeId, rarity
            local numA, numB = tonumber(a), tonumber(b)
            if numA and numB then
                -- 新格式: "1_1" → typeId="hp", rarity="junk"
                typeId = TotemSystem.GetTypeById(numA)
                rarity = RARITY_ORDER[numB]
            elseif VALID_TOTEM_KEYS[key] then
                -- 旧格式: "hp_junk" → 直接使用
                typeId = a
                rarity = b
            end
            if typeId and rarity then
                for _ = 1, count do
                    totems[#totems + 1] = { typeId = typeId, rarity = rarity }
                end
            end
        end
    end
    return totems
end

--- 合并两个聚合计数表（取 max）
---@param local_counts table
---@param cloud_counts table
---@return table merged
function TotemSystem.MergeAggregates(local_counts, cloud_counts)
    local merged = {}
    -- 合并本地
    for k, v in pairs(local_counts) do
        merged[k] = v
    end
    -- 与云端取 max
    for k, v in pairs(cloud_counts) do
        merged[k] = math.max(merged[k] or 0, v)
    end
    return merged
end

-- ============================================================================
-- 统计辅助
-- ============================================================================

--- 按稀有度统计图腾数量
---@param totems table[]
---@return table { junk=N, normal=N, rare=N, legendary=N }
function TotemSystem.CountByRarity(totems)
    local counts = { junk = 0, normal = 0, rare = 0, legendary = 0 }
    for _, t in ipairs(totems) do
        counts[t.rarity] = (counts[t.rarity] or 0) + 1
    end
    return counts
end

--- 计算装备列表的总加成（含技能图腾、特殊图腾）
--- 返回统一的加成结构表，便于各系统读取
---@param equippedTotems table[] 已装备图腾数组
---@return table bonuses 加成结构
function TotemSystem.CalcEquippedBonuses(equippedTotems)
    local bonuses = {
        -- 基础数值（固定加成）
        hpFlat      = 0,
        atkFlat     = 0,
        spdFlat     = 0,
        -- 百分比数值加成（来自stat图腾）
        critBonus     = 0,    -- 暴击率加成（百分比，如 0.03 = +3%）
        fireRateBonus = 0,    -- 攻击间隔降低（百分比）
        hpRegenBonus  = 0,    -- 每秒恢复最大HP百分比
        lootBonus     = 0,    -- 掉落率提升百分比
        -- 技能类
        skillTotems   = {},
        -- 特殊类
        hasCrossClass = false,
    }

    for _, t in ipairs(equippedTotems) do
        local tc = TotemSystem.TYPE_CONFIG[t.typeId]
        if tc then
            if tc.category == "stat" then
                local val = TotemSystem.GetTotemValue(t.typeId, t.rarity)
                if t.typeId == "hp" then
                    bonuses.hpFlat = bonuses.hpFlat + val
                elseif t.typeId == "atk" then
                    bonuses.atkFlat = bonuses.atkFlat + val
                elseif t.typeId == "spd" then
                    bonuses.spdFlat = bonuses.spdFlat + val
                elseif t.typeId == "crit" then
                    bonuses.critBonus = bonuses.critBonus + val / 100
                elseif t.typeId == "fire_rate" then
                    bonuses.fireRateBonus = bonuses.fireRateBonus + val / 100
                elseif t.typeId == "hp_regen" then
                    bonuses.hpRegenBonus = bonuses.hpRegenBonus + val / 100
                elseif t.typeId == "loot" then
                    bonuses.lootBonus = bonuses.lootBonus + val / 100
                end
            elseif tc.category == "skill" then
                bonuses.skillTotems[#bonuses.skillTotems + 1] = t.typeId
            elseif tc.category == "special" and t.typeId == "cross_class" then
                bonuses.hasCrossClass = true
            end
        end
    end

    return bonuses
end

--- 获取所有稀有度顺序（用于UI筛选标签）
---@return table
function TotemSystem.GetRarityOrder()
    return RARITY_ORDER
end

--- 获取稀有度数字索引（1=junk, 2=normal, 3=rare, 4=legendary）
--- 返回 nil 表示无效稀有度（调用方需检查）
---@param rarity string
---@return number|nil
function TotemSystem.GetRarityIndex(rarity)
    return RARITY_INDEX[rarity]
end

--- 获取指定稀有度的可选类型池
---@param rarity string
---@return table typeIds
function TotemSystem.GetTypesForRarity(rarity)
    return TYPES_BY_RARITY[rarity] or { "hp", "atk", "spd" }
end

--- 获取图腾类型的分类
---@param typeId string
---@return string category "stat"|"skill"|"special"
function TotemSystem.GetTypeCategory(typeId)
    local tc = TotemSystem.TYPE_CONFIG[typeId]
    return tc and tc.category or "stat"
end

-- ============================================================================
-- 图腾类型 数字ID索引 + 反查表 + 保底
-- ============================================================================

--- 固定顺序（新增类型只能追加到末尾，不得调整已有顺序！）
local TOTEM_TYPE_ORDER = {
    "hp", "atk", "spd",                                        -- 数值类 1-3
    "atk_up", "speed_up", "magnet", "knockback", "atk_drone",  -- 技能类 4-8
    "cross_class",                                              -- 特殊类 9
    -- v2新增数值类 10-13
    "crit", "fire_rate", "hp_regen", "loot",
    -- v2新增Boss系列 14-27（已废弃，保留索引用于旧存档向后兼容）
    "boss_police", "boss_worker", "boss_chef", "boss_programmer",
    "boss_firefighter", "boss_vampire", "boss_gentleman", "boss_scientist",
    "boss_pirate", "boss_dj", "boss_doctor", "boss_ninja",
    "boss_robot", "boss_demon_king",
}

--- typeId → _id 映射
TotemSystem._TYPE_ID_MAP = {}
--- _id → typeId 映射
TotemSystem._TYPE_BY_ID = {}

for i, tid in ipairs(TOTEM_TYPE_ORDER) do
    TotemSystem._TYPE_ID_MAP[tid] = i
    TotemSystem._TYPE_BY_ID[i] = tid
    -- 在 TYPE_CONFIG 上也挂一份 _id
    if TotemSystem.TYPE_CONFIG[tid] then
        TotemSystem.TYPE_CONFIG[tid]._id = i
    end
end

--- 根据数字ID查询图腾类型字符串（保底返回 "hp"）
---@param numId number
---@return string typeId
function TotemSystem.GetTypeById(numId)
    return TotemSystem._TYPE_BY_ID[numId] or "hp"
end

--- 根据字符串typeId查询数字ID（保底返回 1 = hp）
---@param typeId string
---@return number
function TotemSystem.GetTypeNumId(typeId)
    return TotemSystem._TYPE_ID_MAP[typeId] or 1
end

--- 校验typeId是否有效（无效返回保底 "hp"）
---@param typeId string
---@return string validTypeId
function TotemSystem.ValidateTypeId(typeId)
    if TotemSystem.TYPE_CONFIG[typeId] then
        return typeId
    end
    return "hp"  -- 保底
end

return TotemSystem
