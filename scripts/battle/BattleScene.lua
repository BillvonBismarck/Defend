--- ============================================================================
--- 战斗主循环 - 协调所有战斗子系统、相机、状态管理
--- ============================================================================

local Config = require("Config")
local Player = require("battle.Player")
local Enemy = require("battle.Enemy")
local EnemyBullet = require("battle.EnemyBullet")
local Projectile = require("battle.Projectile")
local Loot = require("battle.Loot")
local Skill = require("battle.Skill")
local Wave = require("battle.Wave")
local DamageNumber = require("ui.DamageNumber")
local Particle = require("fx.Particle")
local GameAudio = require("fx.GameAudio")
local SM = require("utils.SafeMath")
local SaveData = require("SaveData")
local RelicSystem = require("meta.RelicSystem")
local RuneEffects = require("battle.RuneEffects")
local DailyChallenge = require("meta.DailyChallenge")
local DamageStats = require("ui.DamageStats")
local Achievement = require("Achievement")
local Glow = require("fx.Glow")
local ScreenShake = require("fx.ScreenShake")
local Tombstone = require("social.Tombstone")
local MapEvent = require("battle.MapEvent")
local MapVariant = require("battle.MapVariant")
local SpecialTerrain = require("battle.SpecialTerrain")
local Codex = require("meta.Codex")
local WeeklyChallenge = require("meta.WeeklyChallenge")

local BattleScene = {}

-- 子系统错误追踪（防止单个子系统崩溃导致整个战斗卡停）
BattleScene._errors = {}        -- { [subsystem] = { msg=string, count=number, lastTime=number } }
BattleScene._errorTotal = 0     -- 总错误计数

--- 安全调用子系统，崩溃时记录错误但不中断其他系统
---@param name string 子系统名称
---@param fn function 要调用的函数
---@return any ...
local function safeCall(name, fn, ...)
    local results = { pcall(fn, ...) }
    if not results[1] then
        local msg = tostring(results[2])
        BattleScene._errorTotal = BattleScene._errorTotal + 1
        local entry = BattleScene._errors[name]
        if not entry then
            entry = { msg = msg, count = 0, lastTime = 0 }
            BattleScene._errors[name] = entry
        end
        entry.msg = msg
        entry.count = entry.count + 1
        entry.lastTime = os.clock()
        -- 仅首次和每100次打印，避免日志轰炸
        if entry.count == 1 or entry.count % 100 == 0 then
            print(string.format("[BATTLE ERROR] %s (#%d): %s", name, entry.count, msg))
        end
        return false
    end
    return true, table.unpack(results, 2)
end

-- 战斗状态
BattleScene.STATE_PLAYING = 1
BattleScene.STATE_SKILL_SELECT = 2
BattleScene.STATE_PAUSED = 3
BattleScene.STATE_GAME_OVER = 4
BattleScene.STATE_VICTORY = 5
BattleScene.STATE_ULTIMATE_SELECT = 6
BattleScene.STATE_GIFT_AD = 7

BattleScene.state = BattleScene.STATE_PLAYING

-- 完整战斗更新心跳：用于确认恢复的是整条战斗流水线，而不是只有主角。
BattleScene.heartbeat = {
    frame = 0,
    player = 0,
    projectile = 0,
    enemy = 0,
    enemyBullet = 0,
    collision = 0,
}

-- 局内金币（本局拾取的局外金币，结算时存入 SaveData.metaGold）
BattleScene.sessionGold = 0

-- 相机
BattleScene.camX = 0
BattleScene.camY = 0

-- 技能选择
BattleScene.skillChoices = {}

-- 每日挑战：红心DoT（渐进回血）
BattleScene.healDots = {}  -- { {remaining, tickAmt, tickTimer} ... }

-- 回调
BattleScene.onGameOver = nil      -- function(isVictory, stats)
BattleScene.onLevelUp = nil       -- function(choices) -> 显示技能选择UI
BattleScene.onGraduation = nil    -- function() -> 毕业通知
BattleScene.onUltimateSelect = nil -- function() -> 终极奖励选择UI
BattleScene.onGiftPickup = nil     -- function() -> 礼物盒广告弹窗
BattleScene.onBombKills = nil      -- function(bombKills) -> 炸弹击杀数回调

--- 初始化战斗
---@param charId string|nil 角色ID
function BattleScene.Init(charId)
    Player.Init(charId)

    -- 应用皮肤外观覆盖（浅拷贝 charDef 避免污染 Config.CHARACTERS）
    local SkinSystem = require("meta.SkinSystem")
    local equippedSkinId = SaveData.GetEquippedSkin(charId)
    if equippedSkinId then
        local skin = SkinSystem.GetSkin(equippedSkinId)
        if skin and skin.charId == charId then
            -- 浅拷贝 charDef
            local original = Player.charDef
            local copy = {}
            for k, v in pairs(original) do copy[k] = v end
            copy.playerEmoji = skin.playerEmoji
            copy.bulletStyle = skin.bulletStyle
            Player.charDef = copy
            print("[BattleScene] Applied skin: " .. skin.name .. " for " .. charId)
        end
    end

    -- 应用遗物加成（在 RecalcStats 之前设置 relic 字段）
    RelicSystem.ApplyBonusesToPlayer(Player, SaveData.relicLevels)
    Player.RecalcStats()
    Player.hp = Player.maxHp  -- 以含遗物加成的满血开局

    Enemy.Reset()
    EnemyBullet.Reset()
    Projectile.Reset()
    Loot.Reset()
    Skill.Reset()
    Wave.Reset()
    DamageStats.Reset()

    -- 应用已装备图腾加成（数值 + 百分比 + 技能 + 异界天赋）
    local TotemSystem = require("meta.TotemSystem")
    local bonuses = TotemSystem.CalcEquippedBonuses(SaveData.equippedTotems)
    -- 基础固定加成
    Player.totemHpFlat  = bonuses.hpFlat
    Player.totemAtkFlat = bonuses.atkFlat
    Player.totemSpdFlat = bonuses.spdFlat
    -- 百分比数值加成
    Player.totemCritBonus     = bonuses.critBonus
    Player.totemFireRateBonus = bonuses.fireRateBonus
    Player.totemHpRegenBonus  = bonuses.hpRegenBonus
    Player.totemLootBonus     = bonuses.lootBonus

    -- 异界天赋：未毕业即可学习其他角色的非专属技能
    Skill.hasCrossClassRune = bonuses.hasCrossClass

    -- 应用已装备符文加成（触发型机制效果 + 基础值增强）
    local RuneSystem = require("meta.RuneSystem")
    local runeBonuses = RuneSystem.CalcEquippedBonuses(SaveData.equippedRunes, 0)
    Player.runeVampireFullHpAtkBonus = runeBonuses.vampireFullHpAtkBonus
    Player.runeVampireKillHealChance = runeBonuses.vampireKillHealChance
    Player.runeVampireKillHealPercent = runeBonuses.vampireKillHealPercent
    Player.runeAllStatBonus          = runeBonuses.allStatBonus
    Player.runeEquipped              = runeBonuses.equipped

    -- 检测符文共鸣
    local resonance = RuneEffects.DetectResonance(runeBonuses.equipped)
    if resonance then
        DamageNumber.Spawn(Player.x, Player.y - 60,
            resonance.icon .. " " .. resonance.name .. " 共鸣激活!", "levelup")
    end

    -- 技能图腾：开局自带 1 级对应技能
    for _, skillId in ipairs(bonuses.skillTotems) do
        Player.ApplySkill(skillId, 1)
    end

    Player.RecalcStats()
    -- 周挑战修正器：玩家属性
    local wcMaxHp = WeeklyChallenge.GetMod("playerMaxHp")
    if wcMaxHp then Player.maxHp = wcMaxHp end
    local wcSpdMul = WeeklyChallenge.GetMod("playerSpeedMul")
    if wcSpdMul then Player.speed = math.floor(Player.speed * wcSpdMul) end
    local wcDmgMul = WeeklyChallenge.GetMod("playerDmgMul")
    if wcDmgMul then Player.atk = SM.mulFloor(Player.atk, wcDmgMul) end
    Player.hp = Player.maxHp  -- 含图腾加成的满血开局

    BattleScene.sessionGold = 0
    SaveData.sessionTotems = {}  -- 重置本局图腾记录
    SaveData.sessionRunes  = {}  -- 重置本局符文记录
    BattleScene.state = BattleScene.STATE_PLAYING
    BattleScene.skillChoices = {}
    BattleScene.healDots = {}
    BattleScene.heartbeat.frame = 0
    BattleScene.heartbeat.player = 0
    BattleScene.heartbeat.projectile = 0
    BattleScene.heartbeat.enemy = 0
    BattleScene.heartbeat.enemyBullet = 0
    BattleScene.heartbeat.collision = 0

    -- 相机直接跳到玩家居中位置，避免从(0,0)慢慢追赶
    local initViewW = Config.DESIGN_W or 720
    local initViewH = Config.DESIGN_H or 1280
    BattleScene.camX = math.max(0, math.min(Config.WORLD_SIZE - initViewW, Player.x - initViewW / 2))
    BattleScene.camY = math.max(0, math.min(Config.WORLD_SIZE - initViewH, Player.y - initViewH / 2))

    -- 注入 Player 引用供 Loot 金币掉率计算使用（避免循环 require）
    Loot._Player = Player

    -- 初始化地图变体（随机选择）
    local mapSeed = os.time() + math.random(9999)
    MapVariant.Init(nil, mapSeed)

    -- 图鉴：发现当前地图变体
    if MapVariant.active then
        Codex.Discover("map_" .. MapVariant.active.id)
    end

    -- 初始化地图专属特别地形散点
    local variantId = MapVariant.active and MapVariant.active.id or "cyber"
    SpecialTerrain.Init(variantId, mapSeed)

    -- 拉取其他玩家墓碑（异步，不阻塞初始化）
    Tombstone.Reset()
    Tombstone.Fetch()

    -- 连接掉落物回调
    Loot.onHeartPickup = function(healPercent)
        -- 周挑战 noHeal：完全禁止治疗
        if WeeklyChallenge.GetMod("noHeal") then
            DamageNumber.Spawn(Player.x, Player.y - 20, "治疗无效!", "miss")
            return
        end
        if DailyChallenge.HasFactor("heart_dot") then
            -- 渐进回血：5秒内10次，每次回复总量的1/10
            local totalAmt = SM.mulFloor(Player.maxHp, healPercent)
            local tickAmt = math.max(1, math.floor(totalAmt / 10))
            BattleScene.healDots[#BattleScene.healDots + 1] = {
                remaining = 10,
                tickAmt = tickAmt,
                tickTimer = 0,
            }
            DamageNumber.Spawn(Player.x, Player.y - 20, "DoT +" .. totalAmt .. "HP", "heal")
            Particle.Spawn(Player.x, Player.y, "heal")
        else
            local healAmt = SM.mulFloor(Player.maxHp, healPercent)
            Player.Heal(healPercent)
            DamageNumber.Spawn(Player.x, Player.y - 20, "+" .. healAmt .. "HP", "heal")
            Particle.Spawn(Player.x, Player.y, "heal")
        end
    end
    -- 礼物盒拾取回调
    Loot.onGiftPickup = function()
        BattleScene.state = BattleScene.STATE_GIFT_AD
        if BattleScene.onGiftPickup then
            BattleScene.onGiftPickup()
        end
    end

    Loot.onBombPickup = function()
        -- 全屏清怪（Boss免疫秒杀，受20% maxHp伤害）
        local bombKills = 0
        for _, e in ipairs(Enemy.active) do
            if e.alive and not e.dying then
                if e.isBoss then
                    -- Boss 免疫炸弹秒杀，受 20% maxHp 伤害
                    local bossDmg = SM.mulFloor(e.maxHp, 0.2)
                    e.hp = e.hp - bossDmg
                    e.hitFlash = 0.2
                    DamageNumber.SpawnDamage(e.x, e.y - 10, bossDmg, false)
                    Particle.Spawn(e.x, e.y, "hit")
                    if e.hp <= 0 then
                        e.dying = true
                        e.deathTimer = 0.25
                        Player.AddKill()
                        Loot.SpawnFromEnemy(e.x, e.y, e.expDrop)
                        bombKills = bombKills + 1
                    end
                else
                    e.hp = 0
                    e.dying = true
                    e.deathTimer = 0.25
                    Player.AddKill()
                    Loot.SpawnFromEnemy(e.x, e.y, e.expDrop)
                    bombKills = bombKills + 1
                end
            end
        end
        DamageNumber.Spawn(Player.x, Player.y - 30, "BOOM! x" .. bombKills, "pickup")
        Particle.Spawn(Player.x, Player.y, "bomb")
        ScreenShake.Trigger("bomb")
        -- 炸弹核爆 FX：大型冲击波 + 二次冲击波 + 全屏闪光
        Particle.SpawnShockWave(Player.x, Player.y, 300, 0.6, 255, 180, 50, 5)
        Particle.SpawnShockWave(Player.x, Player.y, 200, 0.4, 255, 100, 30, 3)
        Particle.SpawnFlash(255, 200, 100, 0.25, 100)
        -- 每日挑战 炸弹风险：自伤10点
        if DailyChallenge.HasFactor("bomb_risk") then
            local dead = Player.TakeDamage(10)
            DamageNumber.SpawnDamage(Player.x, Player.y - 10, 10, false)
            if dead then
                -- 内联提交金币（避免前向引用 local CommitSessionGold）
                if BattleScene.sessionGold > 0 then
                    local diff2 = Config.GetDifficulty()
                    local gm2 = diff2.goldMult or 1.0
                    local wcL2 = WeeklyChallenge.GetMod("lootMul")
                    if wcL2 then gm2 = gm2 * wcL2 end
                    local fg = math.max(1, math.floor(BattleScene.sessionGold * gm2))
                    SaveData.AddMetaGold(fg)
                    BattleScene.sessionGold = 0
                end
                if Wave.waveNum and Wave.waveNum > 0 then
                    SaveData.UpdateHighestWave(Wave.waveNum)
                end
                BattleScene.state = BattleScene.STATE_GAME_OVER
                if BattleScene.onGameOver then
                    BattleScene.onGameOver(false, BattleScene.GetStats())
                end
                return
            end
        end
        -- 通知炸弹击杀数（成就系统用）
        if BattleScene.onBombKills then
            BattleScene.onBombKills(bombKills)
        end
    end

    -- 局外金币拾取：累积 sessionGold，结算时存入 SaveData.metaGold
    Loot.onCoinPickup = function()
        BattleScene.sessionGold = BattleScene.sessionGold + 1
    end

    -- 波次开始：恢复守护遗物充能
    Wave.onWaveStart = function(_waveNum)
        if Player.guardianMaxCharges > 0 then
            Player.guardianCharges = Player.guardianMaxCharges
        end
    end

    -- 屏幕震动重置
    ScreenShake.Reset()

    -- 符文效果初始化
    RuneEffects.Reset()

    -- 地图事件初始化
    MapEvent.Reset()

    -- 特别地形初始化（SpecialTerrain.Init 在 MapVariant.Init 之后已调用）
    SpecialTerrain.Reset()

    -- 初始波次立即刷一批敌人
    for _ = 1, Config.WAVE.baseEnemyCount do
        Enemy.SpawnAroundPlayer(Player.x, Player.y, "normal", 1.0)
    end
end

--- 更新相机（跟随玩家居中）
---@param viewW number 视口宽
---@param viewH number 视口高
local function UpdateCamera(viewW, viewH)
    -- 目标：玩家居中
    local targetX = Player.x - viewW / 2
    local targetY = Player.y - viewH / 2

    -- 限制在世界范围内
    targetX = math.max(0, math.min(Config.WORLD_SIZE - viewW, targetX))
    targetY = math.max(0, math.min(Config.WORLD_SIZE - viewH, targetY))

    -- 平滑跟随
    local lerp = 0.1
    BattleScene.camX = BattleScene.camX + (targetX - BattleScene.camX) * lerp
    BattleScene.camY = BattleScene.camY + (targetY - BattleScene.camY) * lerp

    -- 叠加屏幕震动偏移
    BattleScene.camX = BattleScene.camX + ScreenShake.offsetX
    BattleScene.camY = BattleScene.camY + ScreenShake.offsetY
end

--- 处理自动攻击
local function HandleAutoAttack()
    local attackInterval = Player.GetEffectiveInterval() * SpecialTerrain.GetAttackRateMult()
    if Player.attackTimer < attackInterval then return end

    -- 找最近敌人
    local target = Enemy.GetNearest(Player.x, Player.y, Config.PLAYER.attackRange)
    if not target then return end

    Player.attackTimer = 0
    local damage = math.max(1, math.floor(Player.GetEffectiveAtk() * SpecialTerrain.GetAtkMult()))
    GameAudio.PlaySFX("shoot")

    -- 发射子弹
    if Player.extraBullets > 0 then
        Projectile.SpawnSpread(
            Player.x, Player.y, target.x, target.y,
            damage, Player.pierceCount, Player.extraBullets, Player.bounceCount
        )
    else
        Projectile.Spawn(
            Player.x, Player.y, target.x, target.y,
            damage, Player.pierceCount, nil, Player.bounceCount
        )
    end

    -- OTTO 大象踩背：每次射击有概率召唤大象
    local elephantLevel = Player.skills["elephant_stomp"] or 0
    if elephantLevel > 0 then
        Skill.TrySpawnElephant(Player.x, Player.y, elephantLevel)
    end
end

--- 处理击杀后逻辑（掉落、经验、过载等）
---@param killedList table 被击杀的敌人列表
local function HandleKills(killedList)
    for _, e in ipairs(killedList) do
        -- ── 魅惑触发（击杀 → 复活为我方）──
        -- TryCharmOnKill 会将敌人复活并标记 charmed，此时跳过掉落/死亡特效
        Skill.TryCharmOnKill(e, Player.skills)
        if e.charmed then
            -- 敌人已被魅惑复活，不计入击杀/掉落
            goto continue
        end

        Player.AddKill()
        -- 图鉴：发现击杀的敌人/Boss
        if e.isBoss and e.bossId then
            Codex.Discover("boss_" .. e.bossId)
        elseif e.typeName and e.typeName ~= "boss" then
            Codex.Discover("enemy_" .. e.typeName)
        end
        -- 符文击杀回血（血族契约：击杀15%概率回复5%最大HP）
        -- 共鸣：烈焰重生 - 回血概率翻倍
        if not WeeklyChallenge.GetMod("noHeal") then
        local vampChance = Player.runeVampireKillHealChance * RuneEffects.GetVampHealChanceMult()
        if vampChance > 0 and math.random() < vampChance then
            local healAmt = math.floor(Player.maxHp * Player.runeVampireKillHealPercent)
            if healAmt >= 1 then
                Player.hp = math.min(Player.maxHp, Player.hp + healAmt)
                -- 血族契约特效
                Particle.Spawn(Player.x, Player.y, "heal")
                Particle.SpawnShockWave(Player.x, Player.y, 40, 0.3, 200, 30, 30, 3)
                DamageNumber.Spawn(Player.x, Player.y - 30, "🩸+" .. healAmt, "heal")
            end
        end
        end -- noHeal guard
        -- 符文击杀触发
        RuneEffects.OnKill(e.x, e.y, e.isBoss or false, Enemy.active)
        -- 地图事件：宝箱守卫击杀检测
        if MapEvent.OnGuardKilled(e.x, e.y) then
            -- 守卫全灭，掉落大量金币
            for _ = 1, 15 do
                Loot.SpawnSpecial(e.x + math.random(-60, 60), e.y + math.random(-60, 60), "coin")
            end
            DamageNumber.Spawn(e.x, e.y - 30, "📦 宝箱开启!", "levelup")
            Particle.SpawnShockWave(e.x, e.y, 150, 0.4, 255, 200, 50, 4)
            GameAudio.PlaySFX("pickup")
        end
        Loot.SpawnFromEnemy(e.x, e.y, e.expDrop)
        -- 死亡粒子（根据敌人类型）
        if e.isBoss then
            -- Boss 死亡：多波连锁爆炸 + 清除敌方弹幕
            GameAudio.PlaySFX("explosion")
            Particle.Spawn(e.x, e.y, "elite_die")
            Particle.SpawnShockWave(e.x, e.y, 200, 0.5, 255, 100, 0, 5)
            Particle.SpawnShockWave(e.x, e.y, 120, 0.35, 255, 200, 50, 3)
            Particle.SpawnShockWave(e.x, e.y, 280, 0.7, 255, 50, 0, 4)
            Particle.SpawnFlash(255, 120, 30, 0.3, 90)
            DamageNumber.Spawn(e.x, e.y - 30, "BOSS DEFEATED!", "levelup")
            ScreenShake.Trigger("boss_defeat")
            -- Boss 死后清除所有敌方弹幕
            EnemyBullet.Reset()
            -- Boss 掉落图腾（通用）
            local TotemSystem = require("meta.TotemSystem")
            local droppedTotem = TotemSystem.RollTotem()
            if SaveData.AddTotem(droppedTotem) then
                local tName = TotemSystem.GetTotemName(droppedTotem.typeId, droppedTotem.rarity)
                DamageNumber.Spawn(e.x, e.y - 50, tName, "pickup")
                SaveData.sessionTotems[#SaveData.sessionTotems + 1] = droppedTotem
                -- 图鉴：发现图腾
                Codex.Discover("totem_" .. droppedTotem.typeId)
            else
                DamageNumber.Spawn(e.x, e.y - 50, "背包已满!", "pickup")
            end
            -- Boss符文掉落（5%概率掉落对应Boss专属符文，已拥有则不重复掉落）
            if e.bossId then
                local RuneSystem = require("meta.RuneSystem")
                local droppedRune = RuneSystem.RollRune(e.bossId, SaveData.ownedRunes)
                if droppedRune then
                    SaveData.AddRune(droppedRune.id)
                    local rName = RuneSystem.GetRuneName(droppedRune.id)
                    local rIcon = RuneSystem.GetRuneIcon(droppedRune.id)
                    DamageNumber.Spawn(e.x, e.y - 70, rIcon .. rName, "levelup")
                    -- 图鉴：发现符文
                    Codex.Discover("rune_" .. droppedRune.id)
                    Particle.SpawnShockWave(e.x, e.y, 100, 0.3, 255, 50, 50, 3)
                    Particle.SpawnShockWave(e.x, e.y, 60, 0.2, 255, 80, 80, 2)
                    SaveData.sessionRunes[#SaveData.sessionRunes + 1] = droppedRune
                end
            end
            -- Boss击杀成就
            Achievement.CheckBossKill()
        elseif e.typeName == "elite" then
            -- 精英死亡：冲击波 + 粒子
            GameAudio.PlaySFX("enemy_die")
            Particle.Spawn(e.x, e.y, "elite_die")
            Particle.SpawnShockWave(e.x, e.y, 120, 0.4, 255, 150, 0, 3)
            -- 精英击杀成就
            Achievement.CheckEliteKill()
        else
            local enemyCfg = Config.ENEMY[e.typeName]
            local col = enemyCfg and Config.COLORS[enemyCfg.color] or {255, 255, 255}
            Particle.Spawn(e.x, e.y, "enemy_die", col)
        end
        ::continue::
    end
end

--- 将本局累积金币存入局外存档，并更新最高波次
local function CommitSessionGold()
    if BattleScene.sessionGold > 0 then
        local diff = Config.GetDifficulty()
        local goldMul = diff.goldMult or 1.0
        -- 周挑战：掉落倍率
        local wcLoot = WeeklyChallenge.GetMod("lootMul")
        if wcLoot then goldMul = goldMul * wcLoot end
        local finalGold = math.max(1, math.floor(BattleScene.sessionGold * goldMul))
        SaveData.AddMetaGold(finalGold)
        BattleScene.sessionGold = 0
    end
    -- 追踪最高波次（仅在有实质进展时更新）
    if Wave.waveNum and Wave.waveNum > 0 then
        SaveData.UpdateHighestWave(Wave.waveNum)
    end
end

--- 主更新逻辑
---@param dt number
---@param moveX number 摇杆输入X（-1~1）
---@param moveY number 摇杆输入Y（-1~1）
---@param viewW number
---@param viewH number
function BattleScene.Update(dt, moveX, moveY, viewW, viewH)
    if BattleScene.state ~= BattleScene.STATE_PLAYING then return end

    -- 限制 dt 防止卡顿导致跳帧
    dt = math.min(dt, 0.05)
    BattleScene.heartbeat.frame = BattleScene.heartbeat.frame + 1

    -- 1. 波次管理
    do
        local prevBoss = Enemy.currentBoss
        safeCall("Wave", Wave.Update, dt, Player.x, Player.y)
        -- Boss 出场检测（新 Boss 刷出时触发震动）
        if Enemy.currentBoss and Enemy.currentBoss ~= prevBoss then
            ScreenShake.Trigger("boss_spawn")
        end
    end

    -- 检查通关
    if Wave.gameOver then
        CommitSessionGold()
        BattleScene.state = BattleScene.STATE_VICTORY
        if BattleScene.onGameOver then
            BattleScene.onGameOver(true, BattleScene.GetStats())
        end
        return
    end

    -- 1.5 地图事件更新
    safeCall("MapEvent", MapEvent.Update, dt, Player.x, Player.y, Player, Wave.waveNum,
        -- 商人购买回调：花费局内金币获得随机技能升级
        function(cost)
            if BattleScene.sessionGold >= cost then
                BattleScene.sessionGold = BattleScene.sessionGold - cost
                -- 随机选一个可升级技能并升1级
                local choices = Skill.RandomChoices(Player.skills, Player.charId)
                if #choices > 0 then
                    local pick = choices[math.random(#choices)]
                    Player.ApplySkill(pick.def.id, pick.newLevel)
                    DamageNumber.Spawn(Player.x, Player.y - 40, "🏪 " .. pick.def.name .. "!", "pickup")
                    Particle.Spawn(Player.x, Player.y, "level_up")
                    GameAudio.PlaySFX("pickup")
                end
                return true
            end
            return false
        end,
        -- 宝箱守卫生成回调
        function(x, y, count)
            for _ = 1, count do
                Enemy.SpawnAroundPlayer(x, y, "elite", 1.0)
            end
        end
    )

    -- 1.6 特别地形更新
    safeCall("SpecialTerrain", SpecialTerrain.Update, dt, Player.x, Player.y, Player, Wave.waveNum,
        BattleScene.camX, BattleScene.camY, viewW, viewH,
        -- 经验奖励
        function(amount)
            local gained = Player.AddExp(amount)
            DamageNumber.Spawn(Player.x, Player.y - 40, "+" .. math.floor(amount) .. "EXP", "exp")
            Particle.Spawn(Player.x, Player.y, "exp_pickup")
            GameAudio.PlaySFX("pickup")
            if gained then
                GameAudio.PlaySFX("levelup")
                DamageNumber.Spawn(Player.x, Player.y - 60, "LEVEL UP!", "levelup")
                Particle.Spawn(Player.x, Player.y, "level_up")
            end
        end,
        -- 技能升级
        function()
            local choices = Skill.RandomChoices(Player.skills, Player.charId)
            if #choices > 0 then
                local pick = choices[math.random(#choices)]
                Player.ApplySkill(pick.def.id, pick.newLevel)
                DamageNumber.Spawn(Player.x, Player.y - 40, "🛕 " .. pick.def.name .. "!", "pickup")
                Particle.Spawn(Player.x, Player.y, "level_up")
                GameAudio.PlaySFX("levelup")
            end
        end,
        -- 全屏炸弹
        function()
            local enemies = Enemy.GetAll()
            for _, e in ipairs(enemies) do
                if not e.isBoss then
                    e.hp = 0
                end
            end
            ScreenShake.TriggerCustom(18, 0.4)
            Particle.Spawn(Player.x, Player.y, "explosion")
            GameAudio.PlaySFX("explosion")
            DamageNumber.Spawn(Player.x, Player.y - 50, "💥 全屏清怪!", "pickup")
        end,
        -- 金币
        function(amount)
            BattleScene.sessionGold = BattleScene.sessionGold + amount
            DamageNumber.Spawn(Player.x, Player.y - 20, "+" .. amount .. "G", "gold")
        end
    )

    -- 2. 玩家更新（含地图事件速度加成 + 特别地形速度加成）
    -- 🔴 玩家移动是整个游戏最关键逻辑，三重保护确保必定执行
    local wasOverload = Player.overloadActive
    do
        local mapSpeedBonus = 0.0
        local stSpeedMult = 1.0
        pcall(function()
            mapSpeedBonus = MapEvent.GetSpeedBonus(Player)
            stSpeedMult = SpecialTerrain.GetSpeedMult()
        end)
        local origMoveSpeed
        if mapSpeedBonus > 0 or stSpeedMult ~= 1.0 then
            origMoveSpeed = Player.speed
            Player.speed = math.floor(Player.speed * (1 + mapSpeedBonus) * stSpeedMult)
        end
        -- 🔴 Player.Update 用独立 pcall 保护
        -- 即使崩溃，也不影响后续子系统，且 main.lua 的冻结检测会兜底
        local pOk, pErr = pcall(Player.Update, dt, moveX, moveY)
        if not pOk then
            print("[BATTLE ERROR] Player.Update: " .. tostring(pErr))
            -- 最后手段：直接移动坐标（绕过所有复杂逻辑）
            if moveX ~= 0 or moveY ~= 0 then
                local len = math.sqrt(moveX * moveX + moveY * moveY)
                local spd = (Player.speed or 200) * dt
                Player.x = Player.x + (moveX / len) * spd
                Player.y = Player.y + (moveY / len) * spd
                Player.x = math.max(20, math.min(Config.WORLD_SIZE - 20, Player.x))
                Player.y = math.max(20, math.min(Config.WORLD_SIZE - 20, Player.y))
            end
        end
        if origMoveSpeed then
            Player.speed = origMoveSpeed
        end
        if pOk then
            BattleScene.heartbeat.player = BattleScene.heartbeat.frame
        end
    end

    -- 2.5 每日挑战：红心DoT渐进回血
    safeCall("HealDots", function()
        if #BattleScene.healDots > 0 then
            local i = 1
            local healLoopCap = 200  -- 安全上限防卡死
            while i <= #BattleScene.healDots and healLoopCap > 0 do
                healLoopCap = healLoopCap - 1
                local dot = BattleScene.healDots[i]
                dot.tickTimer = dot.tickTimer + dt
                if dot.tickTimer >= 0.5 then  -- 每0.5秒回复一次，共10次=5秒
                    dot.tickTimer = dot.tickTimer - 0.5
                    dot.remaining = dot.remaining - 1
                    if not WeeklyChallenge.GetMod("noHeal") then
                        Player.hp = math.min(Player.maxHp, Player.hp + dot.tickAmt)
                        DamageNumber.Spawn(Player.x, Player.y - 20, "+" .. dot.tickAmt, "heal")
                    end
                end
                if dot.remaining <= 0 then
                    table.remove(BattleScene.healDots, i)
                else
                    i = i + 1
                end
            end
        end
    end)

    -- 3. 自动攻击
    safeCall("HandleAutoAttack", HandleAutoAttack)

    -- 4. 子弹更新 + 碰撞
    do
        local ok, kills = safeCall("Projectile", Projectile.Update, dt, Enemy.active)
        if ok then
            BattleScene.heartbeat.projectile = BattleScene.heartbeat.frame
        end
        if ok and kills then HandleKills(kills) end
    end

    -- 5. 技能更新
    do
        local ok, kills = safeCall("Skill", Skill.Update, dt, Player.skills, Player.x, Player.y,
            Player.GetEffectiveAtk(), Enemy.active)
        if ok and kills then HandleKills(kills) end
    end

    -- 5.5 符文效果每帧更新（定时器/被动效果）
    safeCall("RuneEffects", RuneEffects.Update, dt, Enemy.active)

    -- 5.6 过载激活检测（击杀后 AddKill 可能触发过载）
    pcall(function()
        if Player.overloadActive and not wasOverload then
            Particle.SpawnShockWave(Player.x, Player.y, 180, 0.5, 255, 150, 0, 4)
            Particle.Spawn(Player.x, Player.y, "level_up")
            Particle.SpawnFlash(255, 180, 0, 0.2, 80)
            ScreenShake.Trigger("overload")
        end
    end)

    -- 6. 敌人更新
    local enemyUpdateOk = safeCall("Enemy", Enemy.Update, dt, Player.x, Player.y)
    if enemyUpdateOk then
        BattleScene.heartbeat.enemy = BattleScene.heartbeat.frame
    end

    -- 6.5 敌方弹幕更新（ranger子弹 + Boss技能弹幕/范围攻击）
    safeCall("EnemyBulletPhase", function()
        -- 构建阻挡者列表（象+魅惑敌人，可阻挡敌方子弹）
        local blockers = {}
        for _, el in ipairs(Skill.GetElephants()) do
            blockers[#blockers + 1] = el
        end
        for _, ce in ipairs(Skill.GetCharmedEnemies()) do
            if ce.alive then
                blockers[#blockers + 1] = ce
            end
        end
        local charmedBulletKills = {}
        local ok, dmg = safeCall("EnemyBullet", EnemyBullet.Update, dt, Player.x, Player.y, Player.radius, blockers, Enemy.active, charmedBulletKills)
        if ok then
            BattleScene.heartbeat.enemyBullet = BattleScene.heartbeat.frame
        end
        local bulletDmg = (ok and dmg) or 0
        if #charmedBulletKills > 0 then
            HandleKills(charmedBulletKills)
        end
        if bulletDmg > 0 then
            local wasInv = Player.invTimer > 0
            local dead = Player.TakeDamage(bulletDmg)
            if not wasInv then
                GameAudio.PlaySFX("player_hurt")
                DamageNumber.SpawnDamage(Player.x, Player.y - 20, bulletDmg, false)
                Particle.Spawn(Player.x, Player.y, "player_hit")
                ScreenShake.Trigger("player_hit")
            end
            if dead then
                CommitSessionGold()
                BattleScene.state = BattleScene.STATE_GAME_OVER
                if BattleScene.onGameOver then
                    BattleScene.onGameOver(false, BattleScene.GetStats())
                end
                return
            end
        end
    end)

    -- 6.6 魅惑Boss冲刺碰撞检测（伤害敌人）
    do
        local ok, kills = safeCall("EnemyCharmedDash", Enemy.CheckCharmedBossDashCollision)
        if ok and kills and #kills > 0 then
            HandleKills(kills)
        end
    end

    -- 6.7 Boss 冲刺碰撞检测（伤害玩家）
    do
        local ok, dmg = safeCall("EnemyBossDash", Enemy.CheckBossDashCollision, Player.x, Player.y, Player.radius)
        local dashDmg = (ok and dmg) or 0
        if dashDmg > 0 then
            local wasInv = Player.invTimer > 0
            local dead = Player.TakeDamage(dashDmg)
            if not wasInv then
                DamageNumber.SpawnDamage(Player.x, Player.y - 20, dashDmg, false)
                Particle.Spawn(Player.x, Player.y, "player_hit")
                ScreenShake.Trigger("player_hit")
            end
            if dead then
                CommitSessionGold()
                BattleScene.state = BattleScene.STATE_GAME_OVER
                if BattleScene.onGameOver then
                    BattleScene.onGameOver(false, BattleScene.GetStats())
                end
                return
            end
        end
    end

    -- 7. 敌人碰撞玩家（造成接触伤害，无敌帧内不受伤也不弹数字）
    do
        local ok, hits = safeCall("EnemyCollision", Enemy.CheckPlayerCollision, Player.x, Player.y, Player.radius)
        if ok then
            BattleScene.heartbeat.collision = BattleScene.heartbeat.frame
        end
        if ok and hits then
            for _, e in ipairs(hits) do
                local wasInv = Player.invTimer > 0
                local dead = Player.TakeDamage(e.atk)
                if not wasInv then
                    DamageNumber.SpawnDamage(Player.x, Player.y - 20, e.atk, false)
                    Particle.Spawn(Player.x, Player.y, "player_hit")
                    ScreenShake.Trigger("player_hit")
                end
                if dead then
                    CommitSessionGold()
                    BattleScene.state = BattleScene.STATE_GAME_OVER
                    if BattleScene.onGameOver then
                        BattleScene.onGameOver(false, BattleScene.GetStats())
                    end
                    return
                end
            end
        end
    end

    -- 8. 掉落物拾取（含磁铁增益 + 特别地形磁力加成）
    safeCall("LootPickup", function()
        local magnetOk, baseMagnet = pcall(function()
            return Player.GetMagnetRange() * SpecialTerrain.GetMagnetMult()
        end)
        if not magnetOk then baseMagnet = 60 end  -- 保底磁铁范围
        local emOk, effectiveMagnetResult = pcall(Loot.GetEffectiveMagnetRange, baseMagnet)
        local effectiveMagnet = (emOk and tonumber(effectiveMagnetResult)) or baseMagnet
        local ok, exp = safeCall("Loot", Loot.Update, dt, Player.x, Player.y, effectiveMagnet)
        local expGained = (ok and tonumber(exp)) or 0
        -- 周挑战：经验倍率
        local wcExpMul = WeeklyChallenge.GetMod("expMul")
        if wcExpMul and expGained > 0 then expGained = expGained * wcExpMul end
        if expGained > 0 then
            GameAudio.PlaySFX("pickup")
            DamageNumber.Spawn(Player.x, Player.y + 15, "+" .. math.floor(expGained) .. "EXP", "exp")
            Particle.Spawn(Player.x, Player.y, "exp_pickup")
            local leveledUp = Player.AddExp(expGained)
            if leveledUp then
                GameAudio.PlaySFX("levelup")
                DamageNumber.Spawn(Player.x, Player.y - 40, "LEVEL UP!", "levelup")
                Particle.Spawn(Player.x, Player.y, "level_up")
                -- 符文升级触发
                RuneEffects.OnLevelUp(Player.level, Enemy.active)
                -- 弹出技能选择
                BattleScene.skillChoices = Skill.RandomChoices(Player.skills, Player.charId)
                if #BattleScene.skillChoices > 0 then
                    -- 周挑战 roulette：自动随机选技能，不弹UI
                    if WeeklyChallenge.GetMod("roulette") then
                        local ri = math.random(1, #BattleScene.skillChoices)
                        BattleScene.SelectSkill(ri)
                        DamageNumber.Spawn(Player.x, Player.y - 60, "🎰 轮盘!", "pickup")
                    else
                        BattleScene.state = BattleScene.STATE_SKILL_SELECT
                        if BattleScene.onLevelUp then
                            BattleScene.onLevelUp(BattleScene.skillChoices)
                        end
                    end
                end
            end
        end
    end)

    -- 9. 墓碑交互检测
    safeCall("Tombstone", Tombstone.Update, dt, Player.x, Player.y)
    safeCall("TombstoneInteract", Tombstone.AutoInteract)

    -- 10. 屏幕震动
    pcall(ScreenShake.Update, dt)

    -- 11. 相机（必须执行，否则画面不跟随）
    local camOk, camErr = pcall(UpdateCamera, viewW, viewH)
    if not camOk then
        -- 相机崩溃时用最简单逻辑兜底
        local targetX = math.max(0, math.min(Config.WORLD_SIZE - viewW, Player.x - viewW / 2))
        local targetY = math.max(0, math.min(Config.WORLD_SIZE - viewH, Player.y - viewH / 2))
        BattleScene.camX = BattleScene.camX + (targetX - BattleScene.camX) * 0.1
        BattleScene.camY = BattleScene.camY + (targetY - BattleScene.camY) * 0.1
    end
end

--- 获取子系统错误摘要（用于调试 HUD 显示）
---@return string|nil 有错误时返回摘要文本，无错误返回nil
function BattleScene.GetErrorSummary()
    if BattleScene._errorTotal == 0 then return nil end
    local lines = {}
    for name, entry in pairs(BattleScene._errors) do
        lines[#lines + 1] = string.format("%s(x%d)", name, entry.count)
    end
    return table.concat(lines, ", ")
end

--- 重置错误计数（战斗开始/重试时调用）
function BattleScene.ResetErrors()
    BattleScene._errors = {}
    BattleScene._errorTotal = 0
end

--- 选择技能（被UI回调调用）
function BattleScene.SelectSkill(index)
    local choice = BattleScene.skillChoices[index]
    if choice then
        Player.ApplySkill(choice.def.id, choice.newLevel)
        -- 图鉴：发现技能
        Codex.Discover("skill_" .. choice.def.id)
        -- 每日挑战 专精之路：记录首次选中的技能ID
        if DailyChallenge.HasFactor("single_skill") and not DailyChallenge.singleSkillId then
            DailyChallenge.singleSkillId = choice.def.id
        end
    end
    BattleScene.skillChoices = {}
    BattleScene.state = BattleScene.STATE_PLAYING

    -- 毕业检查
    if Player.CheckGraduation() then
        Player.TriggerGraduation()
        DamageNumber.Spawn(Player.x, Player.y - 50, "GRADUATION!", "levelup")
        Particle.SpawnShockWave(Player.x, Player.y, 250, 0.6, 180, 50, 255, 5)
        Particle.SpawnFlash(180, 50, 255, 0.3, 100)
        GameAudio.PlaySFX("levelup")
        if BattleScene.onGraduation then
            BattleScene.onGraduation()
        end
    end

    -- 终极奖励检查（毕业后所有技能再次满级）
    if Player.CheckUltimateReady() then
        BattleScene.state = BattleScene.STATE_ULTIMATE_SELECT
        if BattleScene.onUltimateSelect then
            BattleScene.onUltimateSelect()
        end
    end
end

--- 选择终极奖励（被UI回调调用）
---@param choice string "heal_inv" 或 "rage"
function BattleScene.SelectUltimate(choice)
    Player.ApplyUltimateReward(choice)
    BattleScene.state = BattleScene.STATE_PLAYING

    if choice == "heal_inv" then
        DamageNumber.Spawn(Player.x, Player.y - 50, "FULL HEAL + INVINCIBLE!", "levelup")
        Particle.SpawnShockWave(Player.x, Player.y, 300, 0.8, 0, 255, 150, 6)
        Particle.SpawnFlash(0, 255, 150, 0.4, 120)
    elseif choice == "rage" then
        DamageNumber.Spawn(Player.x, Player.y - 50, "RAGE MODE!", "levelup")
        Particle.SpawnShockWave(Player.x, Player.y, 300, 0.8, 255, 30, 30, 6)
        Particle.SpawnFlash(255, 30, 30, 0.4, 120)
    end
    GameAudio.PlaySFX("levelup")
end

--- 计算当前波次的礼物经验奖励
--- 公式: 基础值 + 波次 × 每波增量
---@param isAd boolean 是否为广告奖励
---@return number 实际奖励经验值
function BattleScene.CalcGiftReward(isAd)
    local base = isAd and Config.GIFT_BOX.adExpReward or Config.GIFT_BOX.giveUpExpReward
    local perWave = isAd and Config.GIFT_BOX.adExpPerWave or Config.GIFT_BOX.giveUpExpPerWave
    local result = SM.floor(base + Wave.waveNum * perWave)
    -- 周挑战：波次奖励倍率
    local wcWave = WeeklyChallenge.GetMod("waveRewardMul")
    if wcWave then result = SM.floor(result * wcWave) end
    return result
end

--- 处理礼物盒结果（被UI回调调用）
---@param watchedAd boolean 是否成功看完广告
function BattleScene.ResolveGift(watchedAd)
    local reward
    if watchedAd then
        reward = BattleScene.CalcGiftReward(true)
        DamageNumber.Spawn(Player.x, Player.y - 40, "+" .. reward .. "EXP!", "levelup")
        Particle.SpawnShockWave(Player.x, Player.y, 200, 0.5, 255, 220, 50, 4)
        Particle.SpawnFlash(255, 220, 50, 0.25, 80)
        GameAudio.PlaySFX("pickup")
    else
        reward = BattleScene.CalcGiftReward(false)
        DamageNumber.Spawn(Player.x, Player.y - 40, "+" .. reward .. "EXP", "exp")
        GameAudio.PlaySFX("pickup")
    end

    local leveledUp = Player.AddExp(reward)
    if leveledUp then
        GameAudio.PlaySFX("levelup")
        DamageNumber.Spawn(Player.x, Player.y - 60, "LEVEL UP!", "levelup")
        Particle.Spawn(Player.x, Player.y, "level_up")
        BattleScene.skillChoices = Skill.RandomChoices(Player.skills, Player.charId)
        if #BattleScene.skillChoices > 0 then
            if WeeklyChallenge.GetMod("roulette") then
                local ri = math.random(1, #BattleScene.skillChoices)
                BattleScene.SelectSkill(ri)
                DamageNumber.Spawn(Player.x, Player.y - 60, "🎰 轮盘!", "pickup")
            else
                BattleScene.state = BattleScene.STATE_SKILL_SELECT
                if BattleScene.onLevelUp then
                    BattleScene.onLevelUp(BattleScene.skillChoices)
                end
                return
            end
        end
    end
    BattleScene.state = BattleScene.STATE_PLAYING
end

--- 获取战斗统计
function BattleScene.GetStats()
    return {
        time = Wave.totalTime,
        timeStr = Wave.GetTimeString(),
        wave = Wave.waveNum,
        kills = Player.kills,
        level = Player.level,
        sessionGold = BattleScene.sessionGold,
        deathX = Player.x,
        deathY = Player.y,
    }
end

--- 渲染背景网格
local function RenderBackground(vg, viewW, viewH, camX, camY)
    local bg = Config.COLORS.bg
    local grid = Config.COLORS.bgGrid

    -- 填充背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
    nvgFill(vg)

    -- 网格线
    local gridSize = 80
    local offsetX = -(camX % gridSize)
    local offsetY = -(camY % gridSize)

    nvgStrokeColor(vg, nvgRGBA(grid[1], grid[2], grid[3], grid[4]))
    nvgStrokeWidth(vg, 1)

    for x = offsetX, viewW, gridSize do
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, 0)
        nvgLineTo(vg, x, viewH)
        nvgStroke(vg)
    end

    for y = offsetY, viewH, gridSize do
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, y)
        nvgLineTo(vg, viewW, y)
        nvgStroke(vg)
    end

    -- 世界边界线（如果在视野内）
    local borderColor = Config.COLORS.neonPurple
    nvgStrokeColor(vg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], 120))
    nvgStrokeWidth(vg, 2)

    local worldLeft = 0 - camX
    local worldTop = 0 - camY
    local worldRight = Config.WORLD_SIZE - camX
    local worldBottom = Config.WORLD_SIZE - camY

    nvgBeginPath(vg)
    nvgRect(vg, worldLeft, worldTop, Config.WORLD_SIZE, Config.WORLD_SIZE)
    nvgStroke(vg)
end

--- 渲染整个战斗场景
function BattleScene.Render(vg, viewW, viewH)
    local camX = BattleScene.camX
    local camY = BattleScene.camY

    -- 重置 bloom 绘制计数器
    Glow.BeginFrame()

    -- 背景（使用地图变体）
    MapVariant.RenderBackground(vg, viewW, viewH, camX, camY)

    -- 障碍物（背景上层、掉落物下层）
    MapVariant.RenderObstacles(vg, camX, camY, viewW, viewH, Wave.totalTime)

    -- 特别地形（障碍物上层、掉落物下层）
    SpecialTerrain.Render(vg, camX, camY, viewW, viewH, Wave.totalTime)

    -- 豆芽陷阱（最底层）
    Skill.RenderBeanTraps(vg, camX, camY)

    -- 掉落物
    Loot.Render(vg, camX, camY, viewW, viewH)

    -- 地图事件（掉落物上层、敌人下层）
    MapEvent.Render(vg, camX, camY, viewW, viewH, Wave.totalTime)

    -- 墓碑（掉落物上层、敌人下层）
    Tombstone.Render(vg, camX, camY, viewW, viewH, Wave.totalTime)

    -- 敌人
    Enemy.Render(vg, camX, camY, viewW, viewH)

    -- 敌方弹幕（在玩家子弹下层）
    EnemyBullet.Render(vg, camX, camY, viewW, viewH)

    -- 子弹
    Projectile.Render(vg, camX, camY, viewW, viewH)

    -- 飞行中的手雷
    Skill.RenderGrenades(vg, camX, camY)

    -- 飞行中的抓取猛击
    Skill.RenderGrabSmashes(vg, camX, camY)

    -- 无人机（环绕玩家，在玩家下层）
    Skill.Render(vg, camX, camY, Player.x, Player.y, Player.skills["atk_drone"] or 0)
    Skill.RenderGreenDrone(vg, camX, camY, Player.x, Player.y, Player.skills["atk_drone_green"] or 0)

    -- 星爆猫爪范围指示
    Skill.RenderCatScratch(vg, camX, camY, Player.x, Player.y, Player.skills["cat_scratch"] or 0)

    -- 分身渲染（大圣专属）
    if Player.charDef then
        local cloneEmoji = Player.charDef.playerEmoji.idle or "🐵"
        Skill.RenderClones(vg, camX, camY, cloneEmoji)
    end

    -- 圣诞树环绕武器（落叶专属）
    Skill.RenderXmasTree(vg, camX, camY, Player.x, Player.y, Player.skills["xmas_tree"] or 0)

    -- 落叶风暴范围指示
    Skill.RenderLeafStorm(vg, camX, camY, Player.x, Player.y, Player.skills["leaf_storm"] or 0)

    -- OTTO 专属渲染
    Skill.RenderElephants(vg, camX, camY)
    Skill.RenderCharmedIndicators(vg, camX, camY)
    Skill.RenderHorseAndWhirlwinds(vg, camX, camY)
    Skill.RenderOttoBoxes(vg, camX, camY)
    -- Skill.RenderSprint 已移除（otto_sprint 改为被动）

    -- 符文影分身（在玩家下层）
    RuneEffects.RenderClones(vg, camX, camY, 0)

    -- 玩家
    Player.Render(vg, camX, camY)

    -- 粒子特效（最顶层）
    Particle.Render(vg, camX, camY, viewW, viewH)
end

return BattleScene
