--- ============================================================================
--- 玩家模块 - 移动、属性、自动攻击
--- ============================================================================

local Config = require("Config")
local SM = require("utils.SafeMath")
local DailyChallenge = require("meta.DailyChallenge")

local Player = {}

-- 状态
Player.x = 0
Player.y = 0
Player.hp = 0
Player.maxHp = 0
Player.atk = 0
Player.speed = 0.0
Player.critRate = 0.0
Player.level = 1
Player.exp = 0
Player.expToNext = 0
Player.kills = 0

-- 过载
Player.overloadKills = 0
Player.overloadActive = false
Player.overloadTimer = 0

-- 攻击
Player.attackTimer = 0
Player.attackInterval = 0
Player.extraBullets = 0
Player.pierceCount = 0
Player.bounceCount = 0

-- 防御
Player.invTimer = 0
Player.shieldCharges = 0
Player.shieldTimer = 0
Player.shieldInterval = 0
Player.regenRate = 0

-- 毕业Build
Player.graduationPhase = 0       -- 0=未毕业, 1=已毕业(技能池扩展), 2=终极奖励已领取
Player.droneCollisionDmg = 0     -- 无人机碰撞伤害（毕业后生效）
Player.droneCollisionTimer = 0   -- 碰撞伤害tick计时
Player.rageActive = false        -- 狂暴模式
Player.rageTimer = 0             -- 狂暴剩余时间

-- 技能被动加成
Player.atkBonus = 0
Player.hpBonus = 0
Player.speedBonus = 0
Player.critBonus = 0
Player.magnetBonus = 0
Player.fireRateBonus = 0
Player.knockbackChance = 0
Player.knockbackForce = 0
Player.bigBulletChance = 0
Player.homingChance = 0
Player.lootBonus = 0
Player.tempAtkSpeedBuffs = {}  -- { {remaining, bonus} } 临时攻速加成

-- 遗物加成（由 RelicSystem.ApplyBonusesToPlayer 设置）
Player.relicAtkBonus      = 0
Player.relicCritBonus     = 0
Player.relicHpBonus       = 0
Player.relicFireRateBonus = 0
Player.relicSpeedBonus    = 0
Player.relicLuckBonus     = 0    -- 掉落率加成
Player.relicArmorBonus    = 0    -- 受伤减免
Player.relicExpBonus      = 0    -- 经验加成
Player.relicMagnetBonus   = 0    -- 拾取范围加成
Player.guardianCharges    = 0    -- 守护遗物充能（每波重置）
Player.guardianMaxCharges = 0    -- 守护遗物最大充能数

-- 图腾加成（由 BattleScene.Init 从 CalcEquippedBonuses 结果设置）
Player.totemHpFlat  = 0
Player.totemAtkFlat = 0
Player.totemSpdFlat = 0
-- v2新增图腾加成
Player.totemCritBonus     = 0   -- 暴击率加成（小数）
Player.totemFireRateBonus = 0   -- 攻击间隔降低（小数）
Player.totemHpRegenBonus  = 0   -- 每秒恢复最大HP百分比
Player.totemLootBonus     = 0   -- 掉落率提升百分比
-- 符文加成（由 BattleScene.Init 从 RuneSystem.CalcEquippedBonuses 设置）
Player.runeVampireFullHpAtkBonus = 0  -- 血族契约：满血ATK基础值加成
Player.runeVampireKillHealChance = 0  -- 血族契约：击杀回血概率
Player.runeVampireKillHealPercent = 0 -- 血族契约：击杀回血百分比（最大HP的%）
Player.runeAllStatBonus          = 0  -- 深渊王权：全属性基础值加成
Player.runeEquipped              = {} -- 已装备符文 { [runeId] = runeDef }

-- 拥有的技能 { id = level }
Player.skills = {}

-- 闪烁效果
Player.flashTimer = 0

-- 移动状态（用于 emoji 选择）
Player._moving = false

-- 角色身份
Player.charId = "cat"         -- 当前角色 ID
Player.charDef = nil          -- 当前角色定义表（缓存引用）

--- 初始化玩家（支持角色选择）
---@param charId string|nil 角色ID，默认 "cat"
function Player.Init(charId)
    Player.charId = charId or "cat"
    Player.charDef = Config.GetCharacter(Player.charId)

    local P = Config.PLAYER
    local stats = Player.charDef.stats

    Player.x = Config.WORLD_SIZE / 2
    Player.y = Config.WORLD_SIZE / 2
    Player.maxHp = SM.mulFloor(P.baseHp, stats.hp)
    Player.hp = Player.maxHp
    Player.atk = SM.mulFloor(P.baseAtk, stats.atk)
    Player.speed = P.baseSpeed * stats.speed
    Player.critRate = P.baseCritRate * stats.critRate
    Player.attackInterval = P.attackInterval
    Player.level = 1
    Player.exp = 0
    Player.expToNext = SM.floor(Config.LEVEL.expFormula(1))
    Player.kills = 0
    Player.invTimer = 0
    Player.flashTimer = 0
    Player.overloadKills = 0
    Player.overloadActive = false
    Player.overloadTimer = 0
    Player.attackTimer = 0
    Player.extraBullets = 0
    Player.pierceCount = 0
    Player.bounceCount = 0
    Player.shieldCharges = 0
    Player.shieldTimer = 0
    Player.shieldInterval = 0
    Player.regenRate = 0
    Player.atkBonus = 0
    Player.hpBonus = 0
    Player.speedBonus = 0
    Player.critBonus = 0
    Player.magnetBonus = 0
    Player.fireRateBonus = 0
    Player.knockbackChance = 0
    Player.knockbackForce = 0
    Player.bigBulletChance = 0
    Player.homingChance = 0
    Player.lootBonus = 0
    Player.tempAtkSpeedBuffs = {}
    Player.skills = {}

    -- 毕业Build重置
    Player.graduationPhase = 0
    Player.droneCollisionDmg = 0
    Player.droneCollisionTimer = 0
    Player.rageActive = false
    Player.rageTimer = 0

    -- 遗物加成重置（由 RelicSystem.ApplyBonusesToPlayer 在 Init 后覆盖）
    Player.relicAtkBonus      = 0
    Player.relicCritBonus     = 0
    Player.relicHpBonus       = 0
    Player.relicFireRateBonus = 0
    Player.relicSpeedBonus    = 0
    Player.relicLuckBonus     = 0
    Player.relicArmorBonus    = 0
    Player.relicExpBonus      = 0
    Player.relicMagnetBonus   = 0
    Player.guardianCharges    = 0
    Player.guardianMaxCharges = 0

    -- 图腾加成重置（由 BattleScene.Init 计算后覆盖）
    Player.totemHpFlat  = 0
    Player.totemAtkFlat = 0
    Player.totemSpdFlat = 0
    Player.totemCritBonus     = 0
    Player.totemFireRateBonus = 0
    Player.totemHpRegenBonus  = 0
    Player.totemLootBonus     = 0
    -- 符文加成重置（由 BattleScene.Init 计算后覆盖）
    Player.runeVampireFullHpAtkBonus = 0
    Player.runeVampireKillHealChance = 0
    Player.runeVampireKillHealPercent = 0
    Player.runeAllStatBonus          = 0
    Player.runeEquipped              = {}
    -- 有效半径（每日挑战体积修改器使用）
    Player.radius = Config.PLAYER.radius
end

--- 重新计算属性（基础 × 角色倍率 + 等级成长 + 技能加成）
function Player.RecalcStats()
    local P = Config.PLAYER
    local L = Config.LEVEL
    local lvl = Player.level
    local stats = Player.charDef and Player.charDef.stats or { hp = 1, atk = 1, speed = 1, critRate = 1 }

    -- 图腾固定值加入基础属性，享受升级成长和百分比加成
    -- 公式: (角色基础 + 图腾固定值) × 升级成长 × (1 + 各种百分比)
    local baseHp = (P.baseHp * stats.hp + Player.totemHpFlat) * (1 + L.hpGrowth * (lvl - 1))
    local baseAtk = (P.baseAtk * stats.atk + Player.totemAtkFlat) * (1 + L.atkGrowth * (lvl - 1))
    local baseCrit = P.baseCritRate * stats.critRate + L.critGrowth * (lvl - 1)

    -- 深渊王权：全属性基础值加成（加算到基础值上）
    local runeAll = Player.runeAllStatBonus
    -- 遗物加成作为独立乘区，与技能加成分开相乘，避免后期被技能加成稀释
    Player.maxHp = SM.mulFloor(baseHp * (1 + runeAll) * (1 + Player.hpBonus), (1 + Player.relicHpBonus))
    Player.atk = SM.mulFloor(baseAtk * (1 + runeAll) * (1 + Player.atkBonus), (1 + Player.relicAtkBonus))
    Player.speed = (P.baseSpeed * stats.speed + Player.totemSpdFlat) * (1 + runeAll) * (1 + Player.speedBonus) * (1 + Player.relicSpeedBonus)
    Player.critRate = baseCrit + Player.critBonus + Player.relicCritBonus + Player.totemCritBonus
    local totalFireRate = Player.fireRateBonus + Player.totemFireRateBonus
    -- 攻速遗物也作为独立乘区
    local relicFireMult = 1 - Player.relicFireRateBonus
    for _, buff in ipairs(Player.tempAtkSpeedBuffs) do
        totalFireRate = totalFireRate + buff.bonus
    end
    Player.attackInterval = P.attackInterval * (1 - totalFireRate) * relicFireMult
    if Player.attackInterval < 0.1 then Player.attackInterval = 0.1 end

    -- 每日挑战修改器
    Player.radius = Config.PLAYER.radius  -- 重置半径
    if DailyChallenge.active then
        -- 缩小药水：体积和HP -50%
        if DailyChallenge.HasFactor("player_small") then
            Player.maxHp = math.max(1, SM.floor(Player.maxHp * 0.5))
            Player.radius = Config.PLAYER.radius * 0.5
        end
        -- 巨大化：体积和HP +100%
        if DailyChallenge.HasFactor("player_big") then
            Player.maxHp = SM.floor(Player.maxHp * 2)
            Player.radius = Config.PLAYER.radius * 2
        end
        -- 暴击本能：伤害 -4，暴击率 ×2
        if DailyChallenge.HasFactor("dmg_crit") then
            Player.atk = math.max(1, Player.atk - 4)
            Player.critRate = Player.critRate * 2
        end
        -- 广域拾取：拾取范围 ×2（磁铁加成翻倍）
        if DailyChallenge.HasFactor("magnet_exp") then
            Player.magnetBonus = Player.magnetBonus * 2 + 1.0  -- 基础范围也翻倍
        end
    end

    -- 保持血量比例
    if Player.hp > Player.maxHp then
        Player.hp = Player.maxHp
    end
end

--- 获取有效攻击力（含过载/狂暴加成）
--- 添加临时攻速加成（可叠加）
---@param bonus number 攻速加成比例（如 0.10 = 10%）
---@param duration number 持续时间（秒）
function Player.AddTempAtkSpeed(bonus, duration)
    table.insert(Player.tempAtkSpeedBuffs, { remaining = duration, bonus = bonus })
    Player.RecalcStats()
end

function Player.GetEffectiveAtk()
    local atk = Player.atk
    if Player.overloadActive then
        atk = SM.mul(atk, Config.OVERLOAD.atkMultiplier)
    end
    if Player.rageActive then
        atk = SM.mul(atk, Config.GRADUATION.ULTIMATE_RAGE_ATK_MULT)
    end
    -- 符文加成：血族契约满血ATK + 超频核心爆发
    local RuneEffects = require("battle.RuneEffects")
    local vampBonus = RuneEffects.GetVampireAtkBonus()
    if vampBonus > 0 then
        atk = atk + vampBonus
    end
    local robotBonus = RuneEffects.GetRobotDmgBonus()
    if robotBonus > 0 then
        atk = SM.mul(atk, 1 + robotBonus)
    end
    -- 暴击判定（含饕餮盛宴保证暴击）
    local isCrit = false
    if RuneEffects.ConsumeGuaranteedCrit() then
        isCrit = true
    elseif math.random() < Player.critRate then
        isCrit = true
    end
    if isCrit then
        atk = SM.mul(atk, Config.PLAYER.critDamage)
    end
    return SM.floor(atk)
end

--- 获取有效移速
function Player.GetEffectiveSpeed()
    local spd = Player.speed
    if Player.overloadActive then
        spd = spd * (1 + Config.OVERLOAD.speedBonus)
    end
    -- otto_sprint 已改为被动移速加成，由 RecalcStats 处理
    return spd
end

--- 获取有效攻击间隔
function Player.GetEffectiveInterval()
    local interval = Player.attackInterval
    if Player.overloadActive then
        interval = interval * Config.OVERLOAD.cooldownReduction
    end
    return interval
end

--- 获取磁吸范围
function Player.GetMagnetRange()
    return Config.PLAYER.magnetRange * (1 + Player.magnetBonus + Player.relicMagnetBonus)
end

--- 更新移动
function Player.Update(dt, moveX, moveY)
    -- 无敌计时
    if Player.invTimer > 0 then
        Player.invTimer = Player.invTimer - dt
        Player.flashTimer = Player.flashTimer + dt
    else
        Player.flashTimer = 0
    end

    -- 过载计时
    if Player.overloadActive then
        Player.overloadTimer = Player.overloadTimer - dt
        if Player.overloadTimer <= 0 then
            Player.overloadActive = false
            Player.overloadTimer = 0
            Player.overloadKills = 0
        end
    end

    -- 狂暴计时
    if Player.rageActive then
        Player.rageTimer = Player.rageTimer - dt
        if Player.rageTimer <= 0 then
            Player.rageActive = false
            Player.rageTimer = 0
        end
    end

    -- 临时攻速加成倒计时
    local needRecalc = false
    for i = #Player.tempAtkSpeedBuffs, 1, -1 do
        local buff = Player.tempAtkSpeedBuffs[i]
        buff.remaining = buff.remaining - dt
        if buff.remaining <= 0 then
            table.remove(Player.tempAtkSpeedBuffs, i)
            needRecalc = true
        end
    end
    if needRecalc then Player.RecalcStats() end

    -- 无人机碰撞伤害tick
    if Player.droneCollisionDmg > 0 then
        Player.droneCollisionTimer = Player.droneCollisionTimer + dt
    end

    -- 护盾充能
    if Player.shieldInterval > 0 then
        Player.shieldTimer = Player.shieldTimer + dt
        if Player.shieldTimer >= Player.shieldInterval then
            Player.shieldTimer = 0
            local maxCharges = (Player.skills["shield"] or 0)
            if maxCharges > 0 and Player.shieldCharges < maxCharges then
                Player.shieldCharges = Player.shieldCharges + 1
            end
        end
    end

    -- 生命恢复（技能再生 + 图腾再生）
    local totalRegen = Player.regenRate + Player.totemHpRegenBonus
    if totalRegen > 0 then
        Player.hp = math.min(Player.maxHp, Player.hp + Player.maxHp * totalRegen * dt)
    end

    -- 移动
    Player._moving = (moveX ~= 0 or moveY ~= 0)
    if moveX ~= 0 or moveY ~= 0 then
        local len = math.sqrt(moveX * moveX + moveY * moveY)
        if len > 0 then
            moveX = moveX / len
            moveY = moveY / len
        end
        local spd = Player.GetEffectiveSpeed()
        Player.x = Player.x + moveX * spd * dt
        Player.y = Player.y + moveY * spd * dt

        -- 世界边界
        local r = Player.radius
        Player.x = math.max(r, math.min(Config.WORLD_SIZE - r, Player.x))
        Player.y = math.max(r, math.min(Config.WORLD_SIZE - r, Player.y))

        -- 障碍物碰撞推离
        local MapVariant = require("battle.MapVariant")
        Player.x, Player.y = MapVariant.ResolveCollision(Player.x, Player.y, r)
    end

    -- 攻击计时
    Player.attackTimer = Player.attackTimer + dt
end

--- 受到伤害
---@return boolean 是否死亡
function Player.TakeDamage(amount)
    if Player.invTimer > 0 then return false end

    -- otto_sprint 已改为被动移速加成，无冲刺护盾

    -- 守护遗物充能：将本次伤害降为1点
    if Player.guardianCharges > 0 then
        amount = 1
        Player.guardianCharges = Player.guardianCharges - 1
    end

    -- 护盾抵挡
    if Player.shieldCharges > 0 then
        Player.shieldCharges = Player.shieldCharges - 1
        Player.invTimer = 0.2
        return false
    end

    -- 护甲遗物减免
    if Player.relicArmorBonus > 0 then
        amount = math.max(1, math.floor(amount * (1 - Player.relicArmorBonus)))
    end

    -- 符文受伤触发（可修改伤害值：钢铁壁垒抵挡、急救减伤、警戒加速等）
    local RuneEffects = require("battle.RuneEffects")
    amount = RuneEffects.OnPlayerDamaged(amount)
    if amount <= 0 then
        Player.invTimer = 0.3
        return false
    end

    Player.hp = Player.hp - amount
    Player.invTimer = Config.PLAYER.invincibleTime

    if Player.hp <= 0 then
        Player.hp = 0
        return true
    end
    return false
end

--- 回复生命值
function Player.Heal(percent)
    Player.hp = math.min(Player.maxHp, Player.hp + Player.maxHp * percent)
end

--- 增加经验
---@return boolean 是否升级
function Player.AddExp(amount)
    if Player.level >= Config.LEVEL.maxLevel then return false end

    -- 难度经验倍率
    local diff = Config.GetDifficulty()
    if diff.expMult ~= 1.0 then
        amount = math.max(1, SM.floor(amount * diff.expMult))
    end

    -- 学识遗物：经验加成
    if Player.relicExpBonus > 0 then
        amount = math.max(1, SM.floor(amount * (1 + Player.relicExpBonus)))
    end

    -- 每日挑战 广域拾取：经验值 ×0.2
    if DailyChallenge.HasFactor("magnet_exp") then
        amount = math.max(1, SM.floor(amount * 0.2))
    end

    Player.exp = SM.add(Player.exp, amount)

    -- 每日挑战 经验膨胀：经验需求 ×1.5
    local expNeeded = Player.expToNext
    if DailyChallenge.HasFactor("exp_up") then
        expNeeded = SM.floor(expNeeded * 1.5)
    end

    if Player.exp >= expNeeded then
        Player.exp = Player.exp - expNeeded
        Player.level = Player.level + 1
        Player.expToNext = SM.floor(Config.LEVEL.expFormula(Player.level))
        Player.RecalcStats()
        -- 升级回血20%
        Player.hp = math.min(Player.maxHp, Player.hp + Player.maxHp * 0.2)
        return true
    end
    return false
end

--- 增加击杀（过载累积）
function Player.AddKill()
    Player.kills = Player.kills + 1
    if not Player.overloadActive then
        Player.overloadKills = Player.overloadKills + 1
        if Player.overloadKills >= Config.OVERLOAD.killsToFull then
            Player.overloadActive = true
            Player.overloadTimer = Config.OVERLOAD.duration
            Player.overloadKills = 0
        end
    end
end

--- 应用技能效果
function Player.ApplySkill(skillId, level)
    Player.skills[skillId] = level

    -- 重置被动加成然后重新计算
    Player.atkBonus = 0
    Player.hpBonus = 0
    Player.speedBonus = 0
    Player.critBonus = 0
    Player.magnetBonus = 0
    Player.fireRateBonus = 0
    Player.knockbackChance = 0
    Player.knockbackForce = 0
    Player.bigBulletChance = 0
    Player.homingChance = 0
    Player.lootBonus = 0
    Player.extraBullets = 0
    Player.pierceCount = 0
    Player.bounceCount = 0
    Player.regenRate = 0
    Player.shieldInterval = 0

    for sid, slv in pairs(Player.skills) do
        for _, skillDef in ipairs(Config.SKILLS) do
            if skillDef.id == sid then
                local eff = skillDef.effect
                if eff.atkBonus then Player.atkBonus = Player.atkBonus + eff.atkBonus * slv end
                if eff.hpBonus then Player.hpBonus = Player.hpBonus + eff.hpBonus * slv end
                if eff.speedBonus then Player.speedBonus = Player.speedBonus + eff.speedBonus * slv end
                if eff.critBonus then Player.critBonus = Player.critBonus + eff.critBonus * slv end
                if eff.magnetBonus then Player.magnetBonus = Player.magnetBonus + eff.magnetBonus * slv end
                if eff.fireRateBonus then Player.fireRateBonus = Player.fireRateBonus + eff.fireRateBonus * slv end
                if eff.knockbackChance then Player.knockbackChance = Player.knockbackChance + eff.knockbackChance * slv end
                if eff.knockbackForce then Player.knockbackForce = eff.knockbackForce end
                if eff.bigBulletChance then Player.bigBulletChance = Player.bigBulletChance + eff.bigBulletChance * slv end
                if eff.homingChance then Player.homingChance = Player.homingChance + eff.homingChance * slv end
                if eff.lootBonus then Player.lootBonus = Player.lootBonus + eff.lootBonus * slv end
                if eff.extraBullets then Player.extraBullets = Player.extraBullets + eff.extraBullets * slv end
                if eff.pierceCount then Player.pierceCount = Player.pierceCount + eff.pierceCount * slv end
                if eff.bounceCount then Player.bounceCount = Player.bounceCount + eff.bounceCount * slv end
                if eff.regenPercent then Player.regenRate = Player.regenRate + eff.regenPercent * slv end
                if eff.charges then
                    Player.shieldInterval = eff.interval / slv
                    Player.shieldCharges = math.min(Player.shieldCharges, slv)
                end
                break
            end
        end
    end

    -- 无人机碰撞伤害 = 50% 玩家子弹伤害
    local droneLevel = Player.skills["atk_drone"] or 0
    if droneLevel > 0 then
        Player.droneCollisionDmg = Player.atk * 0.50
    else
        Player.droneCollisionDmg = 0
    end

    Player.RecalcStats()
end

--- 获取技能的有效最大等级（毕业后提升上限）
---@param skillDef table 技能定义
---@return integer
function Player.GetEffectiveMaxLevel(skillDef)
    -- 每日挑战 专精之路：选中的技能无等级上限
    if DailyChallenge.HasFactor("single_skill") and DailyChallenge.singleSkillId and skillDef.id == DailyChallenge.singleSkillId then
        return 9999
    end

    -- 绿色无人机：上限由飞行遗物等级决定，不受毕业影响
    if skillDef.id == "atk_drone_green" then
        local RelicSystem = require("meta.RelicSystem")
        local SaveData = require("SaveData")
        return math.floor(RelicSystem.GetGreenDroneMaxLevel(SaveData.relicLevels))
    end

    if Player.graduationPhase < 1 then
        return skillDef.maxLevel
    end
    -- 毕业后：无人机 3→6，其他 maxLevel3→4，maxLevel5→7
    if skillDef.id == "atk_drone" then
        return Config.GRADUATION.DRONE_MAX_LEVEL_GRAD
    elseif skillDef.maxLevel == 3 then
        return Config.GRADUATION.MAX3_UPGRADED
    elseif skillDef.maxLevel >= 5 then
        return Config.GRADUATION.MAX5_UPGRADED
    end
    return skillDef.maxLevel
end

--- 获取毕业后解锁的跨角色技能ID列表
---@return table
function Player.GetGraduationSkillIds()
    local ids = {}
    -- 本角色的 exclusive 技能不算"跨角色"
    local myExcl = {}
    if Player.charDef then
        for _, sid in ipairs(Player.charDef.exclusiveSkills) do
            myExcl[sid] = true
        end
    end
    for _, sid in ipairs(Config.GRADUATION_WEAPON_SKILLS) do
        if not myExcl[sid] then ids[#ids + 1] = sid end
    end
    for _, sid in ipairs(Config.GRADUATION_CD_SKILLS) do
        if not myExcl[sid] then ids[#ids + 1] = sid end
    end
    return ids
end

--- 检查是否达成毕业条件（自身卡包全部满级）
---@return boolean
function Player.CheckGraduation()
    if Player.graduationPhase > 0 then return false end -- 已经毕业过

    -- 收集自身卡包技能ID
    local mySkills = {}
    if Player.charDef then
        for _, sid in ipairs(Player.charDef.exclusiveSkills) do
            mySkills[#mySkills + 1] = sid
        end
    end
    for _, sid in ipairs(Config.SHARED_SKILLS) do
        mySkills[#mySkills + 1] = sid
    end

    -- 检查所有自身技能是否满级
    for _, sid in ipairs(mySkills) do
        local curLevel = Player.skills[sid] or 0
        -- 查找技能定义获取maxLevel
        for _, skillDef in ipairs(Config.SKILLS) do
            if skillDef.id == sid then
                if curLevel < skillDef.maxLevel then
                    return false -- 有未满级的技能
                end
                break
            end
        end
    end

    -- 异界天赋：跨职业技能也必须全部满级才能毕业
    -- 否则自身卡包满级即毕业，跨职业技能会从池中移除导致无法升满
    local Skill = require("battle.Skill")
    if Skill.hasCrossClassRune and Player.charDef then
        local charId = Player.charDef.id
        for _, ch in ipairs(Config.CHARACTERS) do
            if ch.id ~= charId then
                for _, sid in ipairs(ch.exclusiveSkills or {}) do
                    local curLevel = Player.skills[sid] or 0
                    if curLevel > 0 then
                        -- 已获得的跨职业技能必须满级
                        for _, skillDef in ipairs(Config.SKILLS) do
                            if skillDef.id == sid then
                                if curLevel < skillDef.maxLevel then
                                    return false
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    return true
end

--- 触发毕业（由 BattleScene 调用）
function Player.TriggerGraduation()
    Player.graduationPhase = 1
    -- 重算无人机碰撞伤害（50% 玩家子弹伤害）
    local droneLevel = Player.skills["atk_drone"] or 0
    if droneLevel > 0 then
        Player.droneCollisionDmg = Player.atk * 0.50
    end
end

--- 检查是否达成终极奖励条件（毕业后所有可选技能再次满级）
---@return boolean
function Player.CheckUltimateReady()
    if Player.graduationPhase ~= 1 then return false end

    -- 检查跨角色解锁的技能是否全满
    local gradSkills = Player.GetGraduationSkillIds()
    for _, sid in ipairs(gradSkills) do
        local curLevel = Player.skills[sid] or 0
        for _, skillDef in ipairs(Config.SKILLS) do
            if skillDef.id == sid then
                local maxLv = Player.GetEffectiveMaxLevel(skillDef)
                if curLevel < maxLv then
                    return false
                end
                break
            end
        end
    end

    -- 还需要检查原有技能是否达到新上限
    local mySkills = {}
    if Player.charDef then
        for _, sid in ipairs(Player.charDef.exclusiveSkills) do
            mySkills[#mySkills + 1] = sid
        end
    end
    for _, sid in ipairs(Config.SHARED_SKILLS) do
        mySkills[#mySkills + 1] = sid
    end
    for _, sid in ipairs(mySkills) do
        local curLevel = Player.skills[sid] or 0
        for _, skillDef in ipairs(Config.SKILLS) do
            if skillDef.id == sid then
                local maxLv = Player.GetEffectiveMaxLevel(skillDef)
                if curLevel < maxLv then
                    return false
                end
                break
            end
        end
    end

    return true
end

--- 应用终极奖励
---@param choice string "heal_inv" 或 "rage"
function Player.ApplyUltimateReward(choice)
    Player.graduationPhase = 2
    if choice == "heal_inv" then
        -- 满血 + 10秒无敌
        Player.hp = Player.maxHp
        Player.invTimer = Config.GRADUATION.ULTIMATE_HEAL_INV_TIME
    elseif choice == "rage" then
        -- 20秒狂暴 (3倍攻击)
        Player.rageActive = true
        Player.rageTimer = Config.GRADUATION.ULTIMATE_RAGE_TIME
    end
end

--- 选择当前状态对应的角色 emoji
local function GetPlayerEmoji()
    local emojis = (Player.charDef and Player.charDef.playerEmoji) or { idle = "😺", move = "😸", hit = "🙀", overload = "😼", dead = "😿", shield = "😻" }
    if Player.hp <= 0 then return emojis.dead end
    if Player.invTimer > 0 then return emojis.hit end
    if Player.overloadActive then return emojis.overload end
    if Player.shieldCharges > 0 then return emojis.shield end
    if Player._moving then return emojis.move end
    return emojis.idle
end

--- 渲染玩家（emoji 小猫）
function Player.Render(vg, camX, camY)
    local sx = Player.x - camX
    local sy = Player.y - camY
    local r = Player.radius

    -- 无敌帧视觉反馈
    local isInv = Player.invTimer > 0
    if isInv then
        -- 白色闪光保护圈
        local invPulse = 0.5 + 0.5 * math.sin(Player.flashTimer * 16)
        local shieldR = r + 10 + invPulse * 4
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, shieldR)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(80 + invPulse * 120)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 快速闪烁：交替半透明（不完全隐藏，保留可见性）
        if math.floor(Player.flashTimer * 12) % 2 == 0 then
            nvgGlobalAlpha(vg, 0.35)
        end
    end

    -- 狂暴光晕（红色脉冲圈）
    if Player.rageActive then
        local pulse = 0.5 + 0.5 * math.sin(Player.rageTimer * 6)
        local glowR = r + 18 + pulse * 8
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, glowR)
        nvgFillColor(vg, nvgRGBA(255, 30, 30, math.floor(40 + pulse * 50)))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, glowR)
        nvgStrokeColor(vg, nvgRGBA(255, 80, 30, math.floor(100 + pulse * 100)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 过载光晕（橙色脉冲圈）
    if Player.overloadActive then
        local pulse = 0.5 + 0.5 * math.sin(Player.overloadTimer * 8)
        local glowR = r + 14 + pulse * 6
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, glowR)
        nvgFillColor(vg, nvgRGBA(255, 150, 0, math.floor(30 + pulse * 40)))
        nvgFill(vg)
    end

    -- 护盾光环
    if Player.shieldCharges > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, r + 8)
        nvgStrokeColor(vg, nvgRGBA(0, 200, 255, 150))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        -- 护盾层数小点
        for i = 1, Player.shieldCharges do
            local angle = (i / Player.shieldCharges) * math.pi * 2 - math.pi / 2
            local dotX = sx + math.cos(angle) * (r + 8)
            local dotY = sy + math.sin(angle) * (r + 8)
            nvgBeginPath(vg)
            nvgCircle(vg, dotX, dotY, 3)
            nvgFillColor(vg, nvgRGBA(0, 200, 255, 230))
            nvgFill(vg)
        end
    end

    -- 底部阴影
    nvgBeginPath(vg)
    nvgEllipse(vg, sx, sy + r + 2, r * 0.7, 4)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 50))
    nvgFill(vg)

    -- emoji 小猫（核心渲染）
    local emoji = GetPlayerEmoji()
    local fontSize = r * 2.4
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, sx, sy, emoji)

    -- 恢复全局透明度（无敌帧半透明后必须还原）
    if isInv then
        nvgGlobalAlpha(vg, 1.0)
    end
end

return Player
