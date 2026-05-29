--- ============================================================================
--- 符文共鸣系统 - 双符文组合产生额外共鸣特效
--- 当玩家装备特定的两个符文组合时，激活共鸣效果
--- ============================================================================

local Player       = require("battle.Player")
local Particle     = require("fx.Particle")
local DamageNumber = require("ui.DamageNumber")
local SM           = require("utils.SafeMath")

local RuneResonance = {}

-- ============================================================================
-- 共鸣定义（6组）
-- ============================================================================

RuneResonance.COMBOS = {
    -- ── 1. 烈焰重生 (浴火重生 + 血族契约) ──
    {
        id    = "flame_rebirth",
        rune1 = "rune_firefighter",
        rune2 = "rune_vampire",
        name  = "烈焰重生",
        icon  = "🔥🩸",
        desc  = "浴火触发时额外回复20%HP，击杀回血概率翻倍",
        -- 效果参数
        fireExtraHeal  = 0.20,   -- 浴火触发额外回血
        vampHealChance = 2.0,    -- 击杀回血概率倍数
    },
    -- ── 2. 幻影风暴 (影分身 + 节拍风暴) ──
    {
        id    = "phantom_storm",
        rune1 = "rune_ninja",
        rune2 = "rune_dj",
        name  = "幻影风暴",
        icon  = "👤🎵",
        desc  = "影分身也会释放迷你节拍冲击波（50%范围，60%伤害）",
        cloneAoeScale  = 0.50,  -- 分身AOE范围倍率
        cloneAoeDmg    = 0.60,  -- 分身AOE伤害倍率
    },
    -- ── 3. 铁壁医疗 (钢铁壁垒 + 急救协议) ──
    {
        id    = "iron_medic",
        rune1 = "rune_worker",
        rune2 = "rune_doctor",
        name  = "铁壁医疗",
        icon  = "🪖💊",
        desc  = "护盾叠满3层时自动回复15%HP，急救冷却-5秒",
        shieldFullHeal = 0.15,  -- 满层回血比例
        doctorCDReduce = 5,     -- 急救CD减少
    },
    -- ── 4. 暗影裂变 (深渊王权 + 裂变弹头) ──
    {
        id    = "shadow_fission",
        rune1 = "rune_demon_king",
        rune2 = "rune_scientist",
        name  = "暗影裂变",
        icon  = "👁️⚛️",
        desc  = "暗影爆发时额外产生裂变弹幕（8颗，每颗60%ATK）",
        burstSplitCount = 8,
        burstSplitDmg   = 0.60,
    },
    -- ── 5. 闪电掠夺 (递归循环 + 夺宝奇兵) ──
    {
        id    = "thunder_loot",
        rune1 = "rune_programmer",
        rune2 = "rune_pirate",
        name  = "闪电掠夺",
        icon  = "🔄💰",
        desc  = "连锁闪电击杀的敌人100%掉落金币，宝箱阈值-5",
        chainGuaranteedCoin = true,
        treasureReduce      = 5,  -- 宝箱阈值减少
    },
    -- ── 6. 超频完美 (超频核心 + 完美主义) ──
    {
        id    = "overclock_perfect",
        rune1 = "rune_robot",
        rune2 = "rune_gentleman",
        name  = "超频完美",
        icon  = "⚡🎩",
        desc  = "超频期间完美主义伤害加成翻倍，未受伤时间减半触发",
        burstDmgDouble   = true,   -- 超频时完美伤害×2
        gentlemanTimeHalf = true,  -- tier时间减半
    },
}

-- 索引：runeId 对 → comboId
RuneResonance._pairIndex = {}

for _, combo in ipairs(RuneResonance.COMBOS) do
    -- 用排序后的拼接键
    local key1
    if combo.rune1 < combo.rune2 then
        key1 = combo.rune1 .. "|" .. combo.rune2
    else
        key1 = combo.rune2 .. "|" .. combo.rune1
    end
    RuneResonance._pairIndex[key1] = combo
end

-- ============================================================================
-- 运行时状态
-- ============================================================================

local activeCombo = nil  -- 当前激活的共鸣（每局最多1个，因为只能装2个符文）
local resonanceFX = {
    pulseTimer = 0,       -- 共鸣光环脉冲计时
    shieldFullTriggered = false,  -- 铁壁医疗：满层是否已触发
}

--- 重置（每局开始）
function RuneResonance.Reset()
    activeCombo = nil
    resonanceFX = {
        pulseTimer = 0,
        shieldFullTriggered = false,
    }
end

--- 检测并激活共鸣（装备符文后调用一次）
---@param equippedRunes table { [runeId] = runeDef }
---@return table|nil 激活的共鸣定义
function RuneResonance.Detect(equippedRunes)
    activeCombo = nil
    resonanceFX.shieldFullTriggered = false

    -- 收集装备的符文ID
    local ids = {}
    for id, _ in pairs(equippedRunes) do
        ids[#ids + 1] = id
    end
    if #ids < 2 then return nil end

    -- 查找匹配的共鸣组合
    table.sort(ids)
    local key = ids[1] .. "|" .. ids[2]
    activeCombo = RuneResonance._pairIndex[key]

    if activeCombo then
        -- 成就检查
        local Achievement = require("Achievement")
        Achievement.CheckResonance(activeCombo.id)
        -- 激活特效提示（由外部调用者显示）
        return activeCombo
    end
    return nil
end

--- 获取当前激活的共鸣
---@return table|nil
function RuneResonance.GetActive()
    return activeCombo
end

-- ============================================================================
-- 共鸣效果钩子（由 RuneEffects 在对应触发点调用）
-- ============================================================================

--- 浴火重生触发时的额外效果（烈焰重生共鸣）
---@return number extraHealPercent 额外回血百分比
function RuneResonance.OnFireTrigger()
    if activeCombo and activeCombo.id == "flame_rebirth" then
        Particle.SpawnShockWave(Player.x, Player.y, 100, 0.5, 255, 100, 50, 4)
        DamageNumber.Spawn(Player.x, Player.y - 50, "🔥🩸共鸣!", "levelup")
        return activeCombo.fireExtraHeal
    end
    return 0
end

--- 击杀回血概率倍数（烈焰重生共鸣）
---@return number multiplier
function RuneResonance.GetVampHealChanceMult()
    if activeCombo and activeCombo.id == "flame_rebirth" then
        return activeCombo.vampHealChance
    end
    return 1.0
end

--- 影分身是否带AOE（幻影风暴共鸣），返回参数
---@return number|nil aoeRadius, number|nil aoeDmgPercent
function RuneResonance.GetCloneAoeParams()
    if activeCombo and activeCombo.id == "phantom_storm" then
        -- 基于 DJ 的 aoeRadius 缩放
        return 180 * activeCombo.cloneAoeScale, activeCombo.cloneAoeDmg
    end
    return nil, nil
end

--- 护盾满层检查（铁壁医疗共鸣）
---@param currentLayers number
---@param maxLayers number
function RuneResonance.OnShieldLayerChange(currentLayers, maxLayers)
    if activeCombo and activeCombo.id == "iron_medic" then
        if currentLayers >= maxLayers and not resonanceFX.shieldFullTriggered then
            resonanceFX.shieldFullTriggered = true
            local healAmt = math.floor(Player.maxHp * activeCombo.shieldFullHeal)
            Player.hp = math.min(Player.maxHp, Player.hp + healAmt)
            Particle.Spawn(Player.x, Player.y, "heal")
            Particle.SpawnShockWave(Player.x, Player.y, 60, 0.4, 100, 200, 255, 3)
            DamageNumber.Spawn(Player.x, Player.y - 50, "🪖💊共鸣+" .. healAmt, "heal")
        end
        -- 护盾被打掉后重置
        if currentLayers < maxLayers then
            resonanceFX.shieldFullTriggered = false
        end
    end
end

--- 急救协议CD修正（铁壁医疗共鸣）
---@param baseCooldown number
---@return number
function RuneResonance.GetDoctorCooldown(baseCooldown)
    if activeCombo and activeCombo.id == "iron_medic" then
        return math.max(5, baseCooldown - activeCombo.doctorCDReduce)
    end
    return baseCooldown
end

--- 暗影爆发时额外裂变弹幕（暗影裂变共鸣，空间哈希加速）
---@param enemies table
function RuneResonance.OnDemonBurst(enemies)
    if activeCombo and activeCombo.id == "shadow_fission" then
        local count = activeCombo.burstSplitCount
        local dmg = SM.mulFloor(Player.atk, activeCombo.burstSplitDmg)
        local Enemy = require("battle.Enemy")
        local DamageStats = require("ui.DamageStats")
        local hash = Enemy._spatialHash
        -- 空间哈希查询 200px 内敌人，一次查询 + 去重伤害（替代 count×n 遍历）
        local hitEnemies = {}
        if hash then
            local nearby = {}
            hash:QueryInto(Player.x, Player.y, 200, nearby)
            for _, e in ipairs(nearby) do
                if e.alive and not e.charmed and not hitEnemies[e] then
                    local dx = e.x - Player.x
                    local dy = e.y - Player.y
                    if dx * dx + dy * dy < 200 * 200 then
                        hitEnemies[e] = true
                        DamageStats._currentSource = "rune"
                        Enemy.Damage(e, dmg)
                    end
                end
            end
        end
        -- 视觉特效：8方向粒子
        for i = 1, count do
            local angle = (i - 1) * (2 * math.pi / count)
            local dist = 100 + math.random(50)
            local tx = Player.x + math.cos(angle) * dist
            local ty = Player.y + math.sin(angle) * dist
            Particle.Spawn(tx, ty, "crit_hit")
        end
        Particle.SpawnShockWave(Player.x, Player.y, 200, 0.6, 120, 0, 200, 5)
        DamageNumber.Spawn(Player.x, Player.y - 50, "👁️⚛️暗影裂变!", "levelup")
    end
end

--- 连锁闪电击杀是否保证金币（闪电掠夺共鸣）
---@return boolean
function RuneResonance.IsChainGuaranteedCoin()
    return activeCombo ~= nil and activeCombo.id == "thunder_loot"
end

--- 宝箱阈值减少量（闪电掠夺共鸣）
---@return number
function RuneResonance.GetTreasureThresholdReduce()
    if activeCombo and activeCombo.id == "thunder_loot" then
        return activeCombo.treasureReduce
    end
    return 0
end

--- 完美主义时间和伤害修正（超频完美共鸣）
---@param tier1Time number
---@param tier2Time number
---@param dmgBonus number
---@param robotBurstActive boolean
---@return number newTier1Time, number newTier2Time, number newDmgBonus
function RuneResonance.ModifyGentleman(tier1Time, tier2Time, dmgBonus, robotBurstActive)
    if activeCombo and activeCombo.id == "overclock_perfect" then
        -- 未受伤触发时间减半
        if activeCombo.gentlemanTimeHalf then
            tier1Time = tier1Time * 0.5
            tier2Time = tier2Time * 0.5
        end
        -- 超频期间伤害翻倍
        if robotBurstActive and activeCombo.burstDmgDouble and dmgBonus > 0 then
            dmgBonus = dmgBonus * 2
        end
    end
    return tier1Time, tier2Time, dmgBonus
end

-- ============================================================================
-- 每帧更新（共鸣光环特效）
-- ============================================================================

---@param dt number
function RuneResonance.Update(dt)
    if not activeCombo then return end
    resonanceFX.pulseTimer = resonanceFX.pulseTimer + dt
    -- 每8秒一次共鸣脉冲光环
    if resonanceFX.pulseTimer >= 8 then
        resonanceFX.pulseTimer = resonanceFX.pulseTimer - 8
        Particle.SpawnShockWave(Player.x, Player.y, 50, 0.3, 200, 180, 255, 2)
    end
end

-- ============================================================================
-- 渲染：共鸣激活指示器（在HUD上显示）
-- ============================================================================

---@param vg userdata
---@param hudX number 显示位置X
---@param hudY number 显示位置Y
---@param totalTime number
function RuneResonance.RenderHUD(vg, hudX, hudY, totalTime)
    if not activeCombo then return end

    -- 共鸣图标 + 名称闪烁显示
    local alpha = 160 + math.floor(math.sin(totalTime * 2) * 60)

    nvgFontFace(vg, "zpix")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 180, 255, alpha))
    nvgText(vg, hudX, hudY, activeCombo.icon .. " " .. activeCombo.name)
end

return RuneResonance
