--- ============================================================================
--- 符文效果 - 所有Boss符文的运行时触发逻辑 + 独立视觉特效
--- 由 BattleScene / Player 在关键节点调用
--- ============================================================================

local Player   = require("battle.Player")
local Particle = require("fx.Particle")
local DamageNumber = require("ui.DamageNumber")
local SM       = require("utils.SafeMath")
local DamageStats = require("ui.DamageStats")
local RuneResonance = require("battle.RuneResonance")

local RuneEffects = {}

-- ── 帧级防级联守卫 ──
local _frameGuard = {
    demonBurstFired = false,   -- 本帧是否已触发恶魔爆发（防止同帧多次级联）
    onKillBudget = 0,          -- 本帧 OnKill 剩余预算
}
local ON_KILL_BUDGET_PER_FRAME = 8  -- 每帧最多处理 8 次 OnKill 的高耗逻辑

-- 复用查询表（避免每次 QueryInto 分配新表）
local _runeNearby = {}

-- ============================================================================
-- 运行时状态（每局重置）
-- ============================================================================
local state = {}

function RuneEffects.Reset()
    RuneResonance.Reset()
    state = {
        -- 🚨 警戒反射
        policeCD         = 0,
        policeBuffTimer  = 0,
        policeSpeedBuff  = 0,

        -- 🪖 钢铁壁垒
        workerTimer      = 0,
        workerLayers     = 0,

        -- 🍖 饕餮盛宴
        chefCD           = 0,
        chefGuaranteedCrit = false,

        -- 🔄 递归循环（连锁闪电）
        programmerCD = 0,

        -- 👁️ 深渊王权（暗影叠层/爆发）
        demonStacks = 0,
        demonBuffTimer = 0,
        demonBuffAmount = 0,  -- 当前 buff 乘数

        -- 🔥 浴火重生
        firefighterCD    = 0,
        firefighterImmuneTimer = 0,

        -- 🎩 完美主义
        gentlemanNoHitTimer = 0,

        -- 💰 夺宝奇兵
        pirateGoldAcc    = 0,
        pirateCD         = 0,

        -- 🎵 节拍风暴
        djTimer          = 0,

        -- 💊 急救协议
        doctorCD         = 0,
        doctorDmgReductionTimer = 0,
        doctorDmgReduction = 0,

        -- 👤 影分身术
        ninjaCD          = 0,
        clones           = {},  -- { {x,y,timer,atkPercent} }

        -- ⚡ 超频核心
        robotKillAcc     = 0,
        robotBurstTimer  = 0,
        robotBurstDmgBonus = 0,
        robotBurstBullets  = 0,  -- 无人机替代剩余子弹
    }
end

--- 获取内部状态（供外部查询）
function RuneEffects.GetState()
    return state
end

--- 检测并激活共鸣（装备符文后调用）
---@param equippedRunes table { [runeId] = runeDef }
---@return table|nil 激活的共鸣定义
function RuneEffects.DetectResonance(equippedRunes)
    return RuneResonance.Detect(equippedRunes)
end

-- ============================================================================
-- 辅助：检查符文是否装备
-- ============================================================================
local function hasRune(runeId)
    return Player.runeEquipped and Player.runeEquipped[runeId] ~= nil
end

local function getRune(runeId)
    return Player.runeEquipped and Player.runeEquipped[runeId]
end

-- ============================================================================
-- 核心触发接口
-- ============================================================================

--- 每帧更新（定时器/被动效果）
---@param dt number
---@param enemies table 当前活跃敌人列表
function RuneEffects.Update(dt, enemies)
    -- 重置帧级守卫
    _frameGuard.demonBurstFired = false
    _frameGuard.onKillBudget = ON_KILL_BUDGET_PER_FRAME

    -- CD 递减
    if state.policeCD > 0 then state.policeCD = state.policeCD - dt end
    if state.chefCD > 0 then state.chefCD = state.chefCD - dt end
    if state.firefighterCD > 0 then state.firefighterCD = state.firefighterCD - dt end
    if state.pirateCD > 0 then state.pirateCD = state.pirateCD - dt end
    if state.doctorCD > 0 then state.doctorCD = state.doctorCD - dt end
    if state.ninjaCD > 0 then state.ninjaCD = state.ninjaCD - dt end
    if state.programmerCD > 0 then state.programmerCD = state.programmerCD - dt end

    -- ── 👁️ 深渊王权：buff 倒计时 ──
    if state.demonBuffTimer > 0 then
        state.demonBuffTimer = state.demonBuffTimer - dt
        if state.demonBuffTimer <= 0 then
            state.demonBuffTimer = 0
            -- 移除动态全属性 buff
            Player.runeAllStatBonus = Player.runeAllStatBonus - state.demonBuffAmount
            state.demonBuffAmount = 0
            Player.RecalcStats()
        end
    end

    -- ── 🚨 警戒反射 buff 倒计时 ──
    if state.policeBuffTimer > 0 then
        state.policeBuffTimer = state.policeBuffTimer - dt
        if state.policeBuffTimer <= 0 then
            state.policeBuffTimer = 0
            Player.speedBonus = Player.speedBonus - state.policeSpeedBuff
            state.policeSpeedBuff = 0
            Player.RecalcStats()
        end
    end

    -- ── 🪖 钢铁壁垒：定时叠护盾层 ──
    local rWorker = getRune("rune_worker")
    if rWorker then
        state.workerTimer = state.workerTimer + dt
        if state.workerTimer >= rWorker.interval then
            state.workerTimer = state.workerTimer - rWorker.interval
            if state.workerLayers < rWorker.maxLayers then
                state.workerLayers = state.workerLayers + 1
                -- 特效：护盾叠加环
                Particle.SpawnShockWave(Player.x, Player.y, 40, 0.4, 100, 200, 255, 3)
                DamageNumber.Spawn(Player.x, Player.y - 30, "🪖x" .. state.workerLayers, "pickup")
                -- 共鸣：铁壁医疗 - 满层回血
                RuneResonance.OnShieldLayerChange(state.workerLayers, rWorker.maxLayers)
            end
        end
    end

    -- ── 🔥 浴火重生：免疫倒计时 ──
    if state.firefighterImmuneTimer > 0 then
        state.firefighterImmuneTimer = state.firefighterImmuneTimer - dt
    end

    -- ── 🎩 完美主义：未受伤计时 ──
    if hasRune("rune_gentleman") then
        state.gentlemanNoHitTimer = state.gentlemanNoHitTimer + dt
    end

    -- ── 🎵 节拍风暴：定时AOE（空间哈希加速）──
    local rDj = getRune("rune_dj")
    if rDj then
        state.djTimer = state.djTimer + dt
        if state.djTimer >= rDj.interval then
            state.djTimer = state.djTimer - rDj.interval
            -- AOE 伤害 + 击退 + 减速（空间哈希查询范围内敌人）
            local aoeDmg = SM.mulFloor(Player.atk, rDj.aoeDmgPercent)
            local hitCount = 0
            local Enemy = require("battle.Enemy")
            local hash = Enemy._spatialHash
            if hash then
                for ni = #_runeNearby, 1, -1 do _runeNearby[ni] = nil end
                hash:QueryInto(Player.x, Player.y, rDj.aoeRadius, _runeNearby)
                for _, e in ipairs(_runeNearby) do
                    if e.alive and not e.charmed then
                        local dx = e.x - Player.x
                        local dy = e.y - Player.y
                        if dx * dx + dy * dy < rDj.aoeRadius * rDj.aoeRadius then
                            DamageStats._currentSource = "rune"
                            Enemy.Damage(e, aoeDmg)
                            if e.alive then
                                e.speedMult = (e.speedMult or 1) * (1 - rDj.slowPercent)
                                e.slowTimer = rDj.slowDuration
                            end
                            hitCount = hitCount + 1
                        end
                    end
                end
            end
            -- 特效：音符冲击波
            Particle.SpawnShockWave(Player.x, Player.y, rDj.aoeRadius, 0.5, 180, 100, 255, 4)
            Particle.Spawn(Player.x, Player.y, "bomb")
            if hitCount > 0 then
                DamageNumber.Spawn(Player.x, Player.y - 30, "🎵x" .. hitCount, "pickup")
            end
        end
    end

    -- ── 💊 急救协议：减伤倒计时 ──
    if state.doctorDmgReductionTimer > 0 then
        state.doctorDmgReductionTimer = state.doctorDmgReductionTimer - dt
        if state.doctorDmgReductionTimer <= 0 then
            state.doctorDmgReduction = 0
        end
    end

    -- ── 低血量符文统一采样（避免先触发的回血导致后触发的被跳过）──
    local lowHpRatio = Player.hp / Player.maxHp
    local isLowHp = lowHpRatio > 0 and lowHpRatio < 0.35

    -- ── 💊 急救协议：低血量触发 ──
    local rDoctor = getRune("rune_doctor")
    if rDoctor and state.doctorCD <= 0 and isLowHp then
        -- 百分比回血
        local healAmt = math.floor(Player.maxHp * rDoctor.healPercent)
        Player.hp = math.min(Player.maxHp, Player.hp + healAmt)
        -- 减伤 buff
        state.doctorDmgReductionTimer = rDoctor.reductionDuration
        state.doctorDmgReduction = rDoctor.dmgReduction
        -- 共鸣：铁壁医疗 - CD减少
        state.doctorCD = RuneResonance.GetDoctorCooldown(rDoctor.cooldown)
        -- 特效：急救十字 + 治疗光环
        Particle.Spawn(Player.x, Player.y, "heal")
        Particle.SpawnShockWave(Player.x, Player.y, 80, 0.6, 50, 255, 100, 4)
        Particle.SpawnFlash(50, 255, 100, 0.2, 60)
        DamageNumber.Spawn(Player.x, Player.y - 30, "💊+" .. healAmt, "heal")
    end

    -- ── 🔥 浴火重生：低血量触发（空间哈希加速，使用同一快照，不受急救回血影响）──
    local rFire = getRune("rune_firefighter")
    if rFire and state.firefighterCD <= 0 and state.firefighterImmuneTimer <= 0 and isLowHp then
        -- 免疫
        state.firefighterImmuneTimer = rFire.immuneDuration
        Player.invTimer = math.max(Player.invTimer, rFire.immuneDuration)
        state.firefighterCD = rFire.cooldown
        -- AOE 火焰伤害（空间哈希查询）
        local aoeDmg = SM.mulFloor(Player.atk, rFire.aoeDmgPercent)
        local Enemy = require("battle.Enemy")
        local hash = Enemy._spatialHash
        if hash then
            for ni = #_runeNearby, 1, -1 do _runeNearby[ni] = nil end
            hash:QueryInto(Player.x, Player.y, rFire.aoeRadius, _runeNearby)
            for _, e in ipairs(_runeNearby) do
                if e.alive and not e.charmed then
                    local dx = e.x - Player.x
                    local dy = e.y - Player.y
                    if dx * dx + dy * dy < rFire.aoeRadius * rFire.aoeRadius then
                        DamageStats._currentSource = "rune"
                        Enemy.Damage(e, aoeDmg)
                    end
                end
            end
        end
        -- 特效：火焰爆发
        Particle.Spawn(Player.x, Player.y, "bomb")
        Particle.SpawnShockWave(Player.x, Player.y, rFire.aoeRadius, 0.6, 255, 80, 0, 5)
        Particle.SpawnShockWave(Player.x, Player.y, rFire.aoeRadius * 0.6, 0.4, 255, 160, 30, 3)
        Particle.SpawnFlash(255, 100, 0, 0.25, 80)
        DamageNumber.Spawn(Player.x, Player.y - 30, "🔥浴火重生!", "levelup")
        -- 共鸣：烈焰重生 - 额外回血
        local extraHeal = RuneResonance.OnFireTrigger()
        if extraHeal > 0 then
            local healAmt = math.floor(Player.maxHp * extraHeal)
            Player.hp = math.min(Player.maxHp, Player.hp + healAmt)
            DamageNumber.Spawn(Player.x, Player.y - 50, "🔥🩸+" .. healAmt, "heal")
        end
    end

    -- ── 👤 影分身：更新已有分身（空间哈希加速 find-nearest + AOE）──
    local Enemy = require("battle.Enemy")
    local cloneHash = Enemy._spatialHash
    for i = #state.clones, 1, -1 do
        local c = state.clones[i]
        c.timer = c.timer - dt
        if c.timer <= 0 then
            Particle.Spawn(c.x, c.y, "enemy_die")
            table.remove(state.clones, i)
        else
            -- 分身自动攻击最近敌人
            c.atkTimer = (c.atkTimer or 0) + dt
            if c.atkTimer >= 0.5 then
                c.atkTimer = 0
                local bestDist = 200 * 200
                local bestE = nil
                if cloneHash then
                    for ni = #_runeNearby, 1, -1 do _runeNearby[ni] = nil end
                    cloneHash:QueryInto(c.x, c.y, 200, _runeNearby)
                    for _, e in ipairs(_runeNearby) do
                        if e.alive and not e.charmed then
                            local dx = e.x - c.x
                            local dy = e.y - c.y
                            local d2 = dx * dx + dy * dy
                            if d2 < bestDist then
                                bestDist = d2
                                bestE = e
                            end
                        end
                    end
                end
                if bestE then
                    local cloneDmg = SM.mulFloor(Player.atk, c.atkPercent)
                    DamageStats._currentSource = "rune"
                    Enemy.Damage(bestE, cloneDmg)
                    Particle.Spawn(bestE.x, bestE.y, "hit")
                    DamageNumber.SpawnDamage(bestE.x, bestE.y - 10, cloneDmg, false, false)
                    -- 共鸣：幻影风暴 - 分身释放迷你AOE（空间哈希）
                    local cloneAoeR, cloneAoeDmgP = RuneResonance.GetCloneAoeParams()
                    if cloneAoeR and cloneHash then
                        local cAoeDmg = SM.mulFloor(Player.atk, cloneAoeDmgP)
                        for ni = #_runeNearby, 1, -1 do _runeNearby[ni] = nil end
                        cloneHash:QueryInto(c.x, c.y, cloneAoeR, _runeNearby)
                        for _, ae in ipairs(_runeNearby) do
                            if ae.alive and not ae.charmed and ae ~= bestE then
                                local adx = ae.x - c.x
                                local ady = ae.y - c.y
                                if adx * adx + ady * ady < cloneAoeR * cloneAoeR then
                                    DamageStats._currentSource = "rune"
                                    Enemy.Damage(ae, cAoeDmg)
                                end
                            end
                        end
                        Particle.SpawnShockWave(c.x, c.y, cloneAoeR, 0.3, 180, 100, 255, 2)
                    end
                    -- 分身缓慢追踪目标
                    local dx = bestE.x - c.x
                    local dy = bestE.y - c.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist > 30 then
                        c.x = c.x + (dx / dist) * 80 * dt
                        c.y = c.y + (dy / dist) * 80 * dt
                    end
                end
            end
        end
    end

    -- ── ⚡ 超频核心：burst 倒计时 ──
    if state.robotBurstTimer > 0 then
        state.robotBurstTimer = state.robotBurstTimer - dt
        if state.robotBurstTimer <= 0 then
            state.robotBurstDmgBonus = 0
            Player.RecalcStats()
        end
    end

    -- ── 共鸣系统更新 ──
    RuneResonance.Update(dt)
end

-- ============================================================================
-- 触发点：玩家受伤时
-- ============================================================================

--- 玩家受伤前调用（可修改伤害值）
---@param amount number 原始伤害
---@return number 修改后的伤害
function RuneEffects.OnPlayerDamaged(amount)
    -- ── 🪖 钢铁壁垒：护盾层抵挡 ──
    if state.workerLayers > 0 then
        state.workerLayers = state.workerLayers - 1
        -- 共鸣：铁壁医疗 - 护盾被打掉重置
        local rW = getRune("rune_worker")
        if rW then RuneResonance.OnShieldLayerChange(state.workerLayers, rW.maxLayers) end
        -- 特效：护盾碎裂
        Particle.SpawnShockWave(Player.x, Player.y, 50, 0.3, 100, 200, 255, 4)
        Particle.SpawnFlash(100, 200, 255, 0.15, 50)
        DamageNumber.Spawn(Player.x, Player.y - 30, "🪖抵挡!", "pickup")
        return 0  -- 完全抵挡
    end

    -- ── 💊 急救协议：减伤中 ──
    if state.doctorDmgReduction > 0 and state.doctorDmgReductionTimer > 0 then
        amount = math.max(1, math.floor(amount * (1 - state.doctorDmgReduction)))
    end

    -- ── 🎩 完美主义：受伤重置计时 ──
    if hasRune("rune_gentleman") then
        state.gentlemanNoHitTimer = 0
    end

    -- ── 🚨 警戒反射：受伤后加速 ──
    local rPolice = getRune("rune_police")
    if rPolice and state.policeCD <= 0 then
        -- 移除旧 buff 再加新的
        if state.policeBuffTimer > 0 then
            Player.speedBonus = Player.speedBonus - state.policeSpeedBuff
        end
        state.policeSpeedBuff = rPolice.speedBuff
        Player.speedBonus = Player.speedBonus + rPolice.speedBuff
        Player.AddTempAtkSpeed(rPolice.atkSpeedBuff, rPolice.buffDuration)
        state.policeBuffTimer = rPolice.buffDuration
        state.policeCD = rPolice.cooldown
        Player.RecalcStats()
        -- 特效：红蓝警灯闪烁
        Particle.SpawnFlash(255, 50, 50, 0.15, 60)
        Particle.SpawnShockWave(Player.x, Player.y, 60, 0.3, 255, 80, 80, 3)
        DamageNumber.Spawn(Player.x, Player.y - 30, "🚨加速!", "pickup")
    end

    return amount
end

-- ============================================================================
-- 触发点：暴击时
-- ============================================================================

--- 子弹命中且暴击时调用
---@param enemyX number
---@param enemyY number
function RuneEffects.OnCrit(enemyX, enemyY)
    -- ── 🍖 饕餮盛宴：暴击回血 + 下次必暴 ──
    local rChef = getRune("rune_chef")
    if rChef and state.chefCD <= 0 then
        if math.random() < rChef.triggerChance then
            -- 百分比回血
            local healAmt = math.floor(Player.maxHp * rChef.healPercent)
            Player.hp = math.min(Player.maxHp, Player.hp + healAmt)
            -- 下次必暴
            state.chefGuaranteedCrit = true
            state.chefCD = rChef.cooldown
            -- 特效：食物治愈光环
            Particle.Spawn(Player.x, Player.y, "heal")
            Particle.SpawnShockWave(Player.x, Player.y, 50, 0.4, 255, 200, 80, 3)
            DamageNumber.Spawn(Player.x, Player.y - 30, "🍖+" .. healAmt, "heal")
        end
    end

    -- ── 👤 影分身术：暴击召唤分身（无CD，上限自然限制）──
    local rNinja = getRune("rune_ninja")
    if rNinja then
        if math.random() < rNinja.triggerChance then
            if #state.clones < rNinja.maxClones then
                -- 在玩家附近偏移生成
                local offsetX = (math.random() - 0.5) * 60
                local offsetY = (math.random() - 0.5) * 60
                table.insert(state.clones, {
                    x = Player.x + offsetX,
                    y = Player.y + offsetY,
                    timer = rNinja.cloneDuration,
                    atkPercent = rNinja.cloneDmgPercent,
                    atkTimer = 0,
                })
                -- 特效：影分身烟雾
                Particle.Spawn(Player.x + offsetX, Player.y + offsetY, "level_up")
                Particle.SpawnShockWave(Player.x + offsetX, Player.y + offsetY, 40, 0.3, 150, 80, 255, 3)
                DamageNumber.Spawn(Player.x, Player.y - 30, "👤影分身!", "pickup")
            end
        end
    end
end

--- 查询是否有保证暴击（饕餮盛宴）
---@return boolean
function RuneEffects.ConsumeGuaranteedCrit()
    if state.chefGuaranteedCrit then
        state.chefGuaranteedCrit = false
        return true
    end
    return false
end

-- ============================================================================
-- 触发点：击杀时
-- ============================================================================

--- 击杀敌人时调用
---@param enemyX number
---@param enemyY number
---@param isBoss boolean
function RuneEffects.OnKill(enemyX, enemyY, isBoss, enemies)
    -- ── 帧预算守卫：防止单帧 OnKill 过多导致卡死 ──
    _frameGuard.onKillBudget = _frameGuard.onKillBudget - 1
    local budgetOk = _frameGuard.onKillBudget > 0

    -- ── 🩸 血族契约（已在 HandleKills 中实现，此处添加特效）──
    -- 特效由 HandleKills 直接处理

    -- ── 🔄 递归循环：击杀触发连锁闪电（空间哈希 + 帧预算）──
    local rProg = getRune("rune_programmer")
    if rProg and state.programmerCD <= 0 and budgetOk then
        if math.random() < rProg.killChance then
            state.programmerCD = rProg.cooldown
            local chainDmg = SM.mulFloor(Player.atk, rProg.chainDmgPercent)
            local Enemy = require("battle.Enemy")
            local hash = Enemy._spatialHash
            local hitSet = {}  -- 已命中的敌人（避免重复弹射）
            local cx, cy = enemyX, enemyY
            local hitCount = 0
            for bounce = 1, rProg.chainCount do
                -- 寻找范围内最近的未命中敌人（空间哈希加速）
                local bestDist = rProg.chainRange * rProg.chainRange
                local bestE = nil
                if hash then
                    for ni = #_runeNearby, 1, -1 do _runeNearby[ni] = nil end
                    hash:QueryInto(cx, cy, rProg.chainRange, _runeNearby)
                    for _, e in ipairs(_runeNearby) do
                        if e.alive and not e.charmed and not hitSet[e] then
                            local dx = e.x - cx
                            local dy = e.y - cy
                            local d2 = dx * dx + dy * dy
                            if d2 < bestDist then
                                bestDist = d2
                                bestE = e
                            end
                        end
                    end
                end
                if not bestE then break end
                hitSet[bestE] = true
                -- 伤害 + 减速
                DamageStats._currentSource = "rune"
                Enemy.Damage(bestE, chainDmg)
                if bestE.alive then
                    bestE.speedMult = (bestE.speedMult or 1) * (1 - rProg.slowPercent)
                    bestE.slowTimer = rProg.slowDuration
                elseif RuneResonance.IsChainGuaranteedCoin() then
                    -- 共鸣：闪电掠夺 - 连锁击杀100%掉金币
                    local Loot = require("battle.Loot")
                    Loot.SpawnSpecial(bestE.x, bestE.y, "coin")
                end
                -- 闪电特效：从上一个位置到命中位置
                Particle.Spawn(bestE.x, bestE.y, "crit_hit")
                Particle.SpawnShockWave(bestE.x, bestE.y, 30, 0.2, 0, 200, 255, 2)
                DamageNumber.SpawnDamage(bestE.x, bestE.y - 10, chainDmg, false, false)
                cx, cy = bestE.x, bestE.y
                hitCount = hitCount + 1
            end
            if hitCount > 0 then
                Particle.SpawnFlash(0, 200, 255, 0.15, 50)
                DamageNumber.Spawn(enemyX, enemyY - 30, "🔄⚡x" .. hitCount, "pickup")
            end
        end
    end

    -- ── 👁️ 深渊王权：击杀叠加暗影（帧守卫防级联）──
    local rDemon = getRune("rune_demon_king")
    if rDemon then
        if state.demonStacks < rDemon.maxStacks then
            state.demonStacks = state.demonStacks + 1
            -- 每5层提示一次
            if state.demonStacks % 5 == 0 then
                DamageNumber.Spawn(Player.x, Player.y - 30, "👁️暗影x" .. state.demonStacks, "pickup")
                Particle.Spawn(Player.x, Player.y, "hit")
            end
        end
        -- 满层爆发（同帧最多触发一次，防止级联）
        if state.demonStacks >= rDemon.maxStacks and not _frameGuard.demonBurstFired then
            _frameGuard.demonBurstFired = true  -- 本帧锁定，防止级联
            state.demonStacks = 0
            -- AOE 伤害（空间哈希查询玩家周围 500px 范围代替全量遍历）
            local burstDmg = SM.mulFloor(Player.atk, rDemon.burstDmgPercent)
            local Enemy = require("battle.Enemy")
            local hash = Enemy._spatialHash
            local hitCount = 0
            DamageStats._currentSource = "rune"
            if hash then
                for ni = #_runeNearby, 1, -1 do _runeNearby[ni] = nil end
                hash:QueryInto(Player.x, Player.y, 500, _runeNearby)
                for _, e in ipairs(_runeNearby) do
                    if e.alive and not e.charmed then
                        Enemy.Damage(e, burstDmg)
                        hitCount = hitCount + 1
                    end
                end
            end
            -- 全属性 buff（如果已有旧buff先移除）
            if state.demonBuffTimer > 0 then
                Player.runeAllStatBonus = Player.runeAllStatBonus - state.demonBuffAmount
            end
            state.demonBuffAmount = rDemon.buffPerStack * rDemon.maxStacks  -- 30层 × 1% = 30%
            state.demonBuffTimer = rDemon.buffDuration
            Player.runeAllStatBonus = Player.runeAllStatBonus + state.demonBuffAmount
            Player.RecalcStats()
            -- 特效：暗影爆发
            Particle.SpawnShockWave(Player.x, Player.y, 300, 0.8, 120, 0, 200, 6)
            Particle.SpawnShockWave(Player.x, Player.y, 200, 0.5, 80, 0, 160, 4)
            Particle.SpawnFlash(120, 0, 200, 0.3, 100)
            Particle.Spawn(Player.x, Player.y, "bomb")
            DamageNumber.Spawn(Player.x, Player.y - 30, "👁️暗影爆发!x" .. hitCount, "levelup")
            -- 共鸣：暗影裂变 - 额外裂变弹幕
            RuneResonance.OnDemonBurst(enemies or {})
        end
    end

    -- ── ⚡ 超频核心：击杀累积 ──
    local rRobot = getRune("rune_robot")
    if rRobot then
        state.robotKillAcc = state.robotKillAcc + 1
        if state.robotKillAcc >= rRobot.killThreshold then
            state.robotKillAcc = 0
            -- 进入超频状态
            state.robotBurstTimer = rRobot.burstDuration
            state.robotBurstDmgBonus = rRobot.droneDmgBonus
            -- 攻速 buff（通过临时攻速系统）
            Player.AddTempAtkSpeed(0.5, rRobot.burstDuration)
            -- 特效：电能爆发
            Particle.SpawnShockWave(Player.x, Player.y, 100, 0.5, 0, 200, 255, 5)
            Particle.SpawnFlash(0, 180, 255, 0.2, 70)
            Particle.Spawn(Player.x, Player.y, "level_up")
            DamageNumber.Spawn(Player.x, Player.y - 30, "⚡超频!", "levelup")
        end
    end

    -- ── 💰 夺宝奇兵：Boss额外金币 + 累积宝箱 ──
    local rPirate = getRune("rune_pirate")
    if rPirate then
        state.pirateGoldAcc = state.pirateGoldAcc + 1
        local effectiveThreshold = rPirate.treasureThreshold - RuneResonance.GetTreasureThresholdReduce()
        if state.pirateGoldAcc >= effectiveThreshold and state.pirateCD <= 0 then
            state.pirateGoldAcc = 0
            state.pirateCD = rPirate.treasureCooldown
            -- 生成宝箱掉落（多枚金币散布）
            local Loot = require("battle.Loot")
            for _ = 1, 8 do
                local ox = Player.x + (math.random() - 0.5) * 60
                local oy = Player.y + (math.random() - 0.5) * 60
                Loot.SpawnSpecial(ox, oy, "coin")
            end
            -- 特效：宝箱爆开
            Particle.Spawn(Player.x, Player.y, "bomb")
            Particle.SpawnShockWave(Player.x, Player.y, 80, 0.4, 255, 210, 50, 4)
            DamageNumber.Spawn(Player.x, Player.y - 30, "💰宝箱!", "pickup")
        end
    end
end

-- ============================================================================
-- 触发点：升级时
-- ============================================================================

--- 玩家升级时调用
---@param newLevel number
---@param enemies table
function RuneEffects.OnLevelUp(newLevel, enemies)
    -- 递归循环已改为击杀触发连锁闪电，升级时不再触发
end

-- ============================================================================
-- 触发点：穿透时
-- ============================================================================

--- 子弹穿透敌人后调用（返回是否分裂）
---@param bulletX number
---@param bulletY number
---@param bulletVx number
---@param bulletVy number
---@param bulletDmg number
---@return table|nil 分裂子弹参数列表 { {vx,vy,dmg}, ... }
function RuneEffects.OnPierce(bulletX, bulletY, bulletVx, bulletVy, bulletDmg)
    -- ── ⚛️ 裂变弹头 ──
    local rSci = getRune("rune_scientist")
    if rSci then
        if math.random() < rSci.splitChance then
            local splits = {}
            local speed = math.sqrt(bulletVx * bulletVx + bulletVy * bulletVy)
            local baseAngle = math.atan(bulletVy, bulletVx)
            local splitDmg = SM.mulFloor(bulletDmg, rSci.splitDmgPercent)
            local halfAngle = math.rad(rSci.splitAngle / 2)
            for i = 1, rSci.splitCount do
                local angle = baseAngle + halfAngle * (2 * i - rSci.splitCount - 1) / rSci.splitCount
                splits[#splits + 1] = {
                    vx = math.cos(angle) * speed,
                    vy = math.sin(angle) * speed,
                    dmg = splitDmg,
                }
            end
            -- 特效：裂变闪光
            Particle.Spawn(bulletX, bulletY, "crit_hit")
            Particle.SpawnShockWave(bulletX, bulletY, 30, 0.2, 100, 255, 200, 2)
            return splits
        end
    end
    return nil
end

-- ============================================================================
-- 查询接口：给伤害计算用
-- ============================================================================

--- 获取完美主义伤害加成
---@return number dmgBonus 伤害加成比例
---@return number extraPierce 额外穿透
---@return boolean hasKnockback 是否额外击退
function RuneEffects.GetGentlemanBonuses()
    local rGent = getRune("rune_gentleman")
    if not rGent then return 0, 0, false end
    local t = state.gentlemanNoHitTimer
    -- 共鸣：超频完美 - 时间减半 + 超频期间伤害翻倍
    local robotBurstActive = state.robotBurstTimer > 0
    local t1, t2, dmgB = RuneResonance.ModifyGentleman(
        rGent.tier1Time, rGent.tier2Time, rGent.tier1DmgBonus, robotBurstActive)
    if t >= t2 then
        return dmgB, rGent.tier1Pierce, true
    elseif t >= t1 then
        return dmgB, rGent.tier1Pierce, false
    end
    return 0, 0, false
end

--- 获取超频核心伤害加成
---@return number 额外伤害比例
function RuneEffects.GetRobotDmgBonus()
    if state.robotBurstTimer > 0 then
        return state.robotBurstDmgBonus
    end
    return 0
end

--- 获取血族契约满血ATK加成
---@return number
function RuneEffects.GetVampireAtkBonus()
    if Player.runeVampireFullHpAtkBonus > 0 and Player.hp >= Player.maxHp then
        return Player.runeVampireFullHpAtkBonus
    end
    return 0
end

--- 获取夺宝奇兵Boss金币加成
---@return number
function RuneEffects.GetPirateBossGoldBonus()
    local rPirate = getRune("rune_pirate")
    return rPirate and rPirate.bossGoldBonus or 0
end

--- 获取深渊王权暗影层数（供HUD显示）
---@return number stacks 当前层数
---@return number maxStacks 上限
---@return boolean hasBuff 是否有爆发buff
function RuneEffects.GetDemonStacks()
    local rDemon = getRune("rune_demon_king")
    if not rDemon then return 0, 0, false end
    return state.demonStacks, rDemon.maxStacks, state.demonBuffTimer > 0
end

-- ============================================================================
-- 渲染：分身的视觉（在战斗渲染时调用）
-- ============================================================================

--- 渲染影分身（需要在 BattleScene.Render 中调用）
---@param vg userdata NanoVG 上下文
---@param camX number
---@param camY number
---@param fontId number
function RuneEffects.RenderClones(vg, camX, camY, fontId)
    if #state.clones == 0 then return end

    for _, c in ipairs(state.clones) do
        local sx = c.x - camX
        local sy = c.y - camY
        -- 半透明玩家分身
        nvgFontFaceId(vg, zpix)
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 闪烁透明度
        local alpha = 140 + math.floor(math.sin(c.timer * 6) * 40)
        nvgFillColor(vg, nvgRGBA(200, 150, 255, alpha))
        nvgText(vg, sx, sy, "👤")
    end
end

--- 获取吸血击杀回血概率倍数（共鸣：烈焰重生）
---@return number
function RuneEffects.GetVampHealChanceMult()
    return RuneResonance.GetVampHealChanceMult()
end

--- 获取连锁闪电是否保证金币（共鸣：闪电掠夺）
---@return boolean
function RuneEffects.IsChainGuaranteedCoin()
    return RuneResonance.IsChainGuaranteedCoin()
end

--- 渲染共鸣HUD指示器
---@param vg userdata
---@param hudX number
---@param hudY number
---@param totalTime number
function RuneEffects.RenderResonanceHUD(vg, hudX, hudY, totalTime)
    RuneResonance.RenderHUD(vg, hudX, hudY, totalTime)
end

--- 获取激活的共鸣信息
---@return table|nil
function RuneEffects.GetActiveResonance()
    return RuneResonance.GetActive()
end

return RuneEffects
