-- 固定据点主循环：纯规则权威。UI 仅发意图；引擎时间与表现不能直接改规则。
local Config = require("defense.Config")
local Random = require("defense.Random")
local Map = require("defense.Map")
local WaveDirector = require("defense.WaveDirector")
local Combat = require("defense.Combat")
local Progression = require("defense.Progression")
local Economy = require("defense.Economy")
local Reactions = require("defense.Reactions")
local Feedback = require("defense.Feedback")
local Scenarios = require("defense.Scenarios")
local TowerModules = require("defense.TowerModules")
local RoomGraph = require("defense.RoomGraph")
local Expedition = require("defense.Expedition")
local Expansion = require("defense.Expansion")
local runSerial = 0

---@class DefenseRun
---@field pending_harmful_reactions integer
---@field processing_reactions boolean
---@field scheduled_events table[]
---@field trial_started boolean
---@field exploration_currency_earned number
---@field exploration_seconds_used number
---@field room_core_damage table
---@field zone_visits table
---@field wave_reports table[]
local Run = {}
Run.__index = Run

function Run.New(options)
    local self = setmetatable({}, Run)
    self:init(options or {})
    return self
end

function Run:init(options)
    self.config = (options.config and Feedback.Copy(options.config)) or (options.scenario_id and Scenarios.Get(options.scenario_id)) or Config
    self.scenario_id = self.config.scenario_id or options.scenario_id or "legacy_v02"
    self.rules_version = self.config.rules_version or self.config.version
    self.record_namespace = self.config.record_namespace or "legacy_v02"
    self.can_record_chapter = self.config.can_record_chapter ~= false and self.scenario_id == "legacy_v02"
    runSerial = runSerial + 1
    self.run_id = options.run_id or ("defense-local-" .. tostring(runSerial))
    self.chapter = options.chapter or 1
    self.total_waves = options.total_waves or self.config.total_waves or 20
    assert(type(self.total_waves) == "number" and self.total_waves >= 1 and self.total_waves <= #self.config.waves
        and self.total_waves == math.floor(self.total_waves), "场景波数无效")
    self.final_intro_wave = self.config.final_intro_wave or 20
    self.build = options.build or "single"
    self.retry = options.retry == true
    self.seed = options.seed or 20261002
    self.rng = Random.New(self.seed)
    self.map = Map.New(self.config)
    self.meta = options.meta or { schema_version = 1, revision = 0, stages = {}, chapters = { ["1"] = true }, story_seen = {} }
    self.meta.stages = self.meta.stages or {}
    self.meta.chapters = self.meta.chapters or { ["1"] = true }
    self.meta.story_seen = self.meta.story_seen or {}
    self.on_meta = options.on_meta
    self.player = {
        x = self.config.player_spawn.x, y = self.config.player_spawn.y,
        hp = self.config.player.hp, max_hp = self.config.player.hp,
        radius = self.config.player.radius, speed = self.config.player.speed,
        damage = self.config.player.damage, interval = self.config.player.interval, range = self.config.player.range,
        level = 1, experience = 0, attack_cd = 0, active_cd = 0, invulnerable = 0, skills = {},
    }
    if self.build == "area" then self.player.skills.blast = 1
    elseif self.build == "control" then self.player.skills.frost = 1
    else self.player.skills.power = 1; self.player.skills.pierce = 1 end
    self.player.id, self.player.entity_id, self.player.team, self.player.alive = "player", "player", "player", true
    self.player.movable, self.player.anchored, self.player.damageable = true, false, true
    self.player.weight, self.player.emoji = self.config.player.weight or 1, self.config.player.emoji
    self.player.slowable = true
    self.core = { id = "core", entity_id = "core", team = "player", anchored = true, movable = false, damageable = true, alive = true, slowable = false,
        x = self.config.core_position.x, y = self.config.core_position.y,
        hp = self.config.core_max_hp, max_hp = self.config.core_max_hp, radius = self.config.core_radius }
    self.currency = self.config.currency
    self.repair_uses = 0
    self.wave_id = 1
    self.current_wave = self.config.waves[1]
    self.director = WaveDirector.New(self.config, 1)
    self.state = "DEPLOY"
    self.resume_state = "DEPLOY"
    self.clock = 0
    self.preparation_remaining = self.config.preparation_duration
    self.preparation_total = self.preparation_remaining
    self.rest_bonus, self.attack_elapsed = 0, 0
    self.attack_duration = self.current_wave.attack_duration or self.config.attack_duration
    self.warning_elapsed = 0
    self.pause_reasons = {}
    self.enemies, self.projectiles, self.drops, self.effects, self.towers, self.rooms = {}, {}, {}, {}, {}, {}
    self.events, self.transactions, self.settled_waves, self.story_seen = {}, {}, {}, {}
    self.next_entity_id, self.event_id = 1, 0
    self.range_opportunity_offered, self.range_opportunity_wave = false, 0
    self.last_transaction = {}
    Reactions.Init(self)
    Feedback.Init(self)
    Expansion.Init(self)
    Reactions.Sync(self, self.player)
    Reactions.Sync(self, self.core)
    self.ended = false
    self.result, self.end_reason = "", ""
    self.options = {}
    self.recall = { active = false, progress = 0, room_id = "" }
    self.story = { node = "opening", elapsed = 0, duration = options.retry and 3 or 14, replay = false }
    self.pause_reasons.story = true
    self.totals = { kills = 0, core_damage = 0, player_damage = 0, player_output = 0, tower_output = 0,
        output_by_source = {}, expedition_output = {} }
    for _, def in ipairs(self.config.rooms) do
        self.rooms[#self.rooms + 1] = { id = def.id, name = def.name, x = def.x, y = def.y, tier = def.tier,
            unlocked = self.map.locked[def.id] ~= true, prerequisite = def.prerequisite, unlock = def.unlock,
            region_id = def.region_id or def.id, guard_profile = Feedback.Copy(def.guard_profile), reward_kind = def.reward_kind,
            module_reward = def.module_reward == true, defense_slots = Feedback.Copy(def.defense_slots or {}),
            challenge_target = def.challenge_target == true, prerequisite_satisfied = self.map.locked[def.id] ~= true,
            challenge_gate_open = false, accessible = self.map.locked[def.id] ~= true,
            state = "unvisited", guard_ids = {}, reward_claimed = false }
    end
    TowerModules.Init(self)
    RoomGraph.UpdateAccess(self)
    self:Emit("RunStarted", { total_waves = self.total_waves, build = self.build, version = self.config.version,
        scenario_id = self.scenario_id, rules_version = self.rules_version, record_namespace = self.record_namespace })
    self:Emit("StoryRequested", { node = "opening", duration = self.story.duration, prototype = true })
end

function Run:Emit(kind, data)
    data = data or {}
    if kind == "TransactionResolved" then Feedback.Transaction(self, data) end
    if self.totals then
        if kind == "EnemyDied" then self.totals.kills = self.totals.kills + 1
        elseif kind == "CoreDamaged" then self.totals.core_damage = self.totals.core_damage + (data.amount or 0)
        elseif kind == "PlayerDamaged" then self.totals.player_damage = self.totals.player_damage + (data.amount or 0)
        elseif kind == "Hit" then
            local sourceKey = tostring(data.source_id or data.source or "effect")
            self.totals.output_by_source[sourceKey] = (self.totals.output_by_source[sourceKey] or 0) + (data.amount or 0)
            if data.role == "expedition" then
                self.totals.expedition_output[sourceKey] = (self.totals.expedition_output[sourceKey] or 0) + (data.amount or 0)
            end
            if data.source == "player" or data.source == "active" then
                self.totals.player_output = self.totals.player_output + (data.amount or 0)
            elseif type(data.source) == "string" and data.source:find("tower") then
                self.totals.tower_output = self.totals.tower_output + (data.amount or 0)
            end
        end
    end
    self.event_id = self.event_id + 1
    local record = { kind = kind, data = data, event_id = self.event_id, run_id = self.run_id, time = self.clock, wave = self.wave_id,
        root_action_id = data.root_action_id, parent_event_id = data.parent_event_id, source_id = data.source_id,
        planned_at = data.planned_at or self.clock }
    self.events[#self.events + 1] = record
    return record.event_id
end

function Run:DrainEvents()
    local result = self.events
    self.events = {}
    return result
end

function Run:IsPaused()
    return next(self.pause_reasons) ~= nil
end

function Run:Pause(reason)
    if self.ended and (not self.story or self.story.node == "") and reason ~= "rules" and reason ~= "recap" then return end
    self.pause_reasons[reason] = true
    self:CancelRecall("暂停取消引导")
    self:Emit("Paused", { reason = reason, wave = self.wave_id })
end

function Run:Resume(reason)
    self.pause_reasons[reason] = nil
    self:Emit("Resumed", { reason = reason, wave = self.wave_id, still_paused = self:IsPaused() })
end

function Run:AliveCount()
    local count = 0
    for _, e in ipairs(self.enemies) do
        if e.alive and e.wave_id == self.wave_id and not e.room_id then count = count + 1 end
    end
    return count
end

function Run:PendingHarmfulCount()
    return self.pending_harmful_reactions
end

function Run:CausalSummaries(history)
    return Reactions.Summaries(self, history == true)
end

function Run:Close(reason)
    -- Runtime切换/重试必须关闭旧实例，不触发胜利或清波奖励。
    return self:End("abandoned", reason or "离开本局")
end

function Run:GrantExperience(amount)
    if self.ended or amount <= 0 then return end
    self.player.experience = self.player.experience + math.floor(amount)
    self:Emit("ExperienceGranted", { amount = amount, experience = self.player.experience })
end

function Run:CheckUpgrade()
    if self.ended or self.pause_reasons.upgrade or self.processing_reactions or self.player.hp <= 0 or self.core.hp <= 0 then return false end
    if #self.scheduled_events > 0 and self.scheduled_events[1].at <= self.clock + 0.00000001 then return false end
    if self.player.experience < Progression.Threshold(self.player.level) then return false end
    self.resume_state = self.state
    self.state = "UPGRADE_CHOICE"
    self.pause_reasons.upgrade = true
    self.options = Progression.Options(self, self.rng)
    self:CancelRecall("升级取消引导")
    self:Emit("UpgradeOffered", { level = self.player.level, options = self.options })
    return true
end

function Run:ChooseUpgrade(id)
    if self.ended or not self.pause_reasons.upgrade then return false end
    local found = false
    for _, option in ipairs(self.options) do if option.id == id then found = true; break end end
    if not found then return false end
    local threshold = Progression.Threshold(self.player.level)
    if not Progression.Apply(self, id) then return false end
    self.player.experience = self.player.experience - threshold
    self.player.level = self.player.level + 1
    self.options = {}
    self.pause_reasons.upgrade = nil
    self.state = self.resume_state
    self:Emit("UpgradeChosen", { id = id, level = self.player.level, resume_state = self.state })
    self:CheckUpgrade()
    return true
end

function Run:EnterPreparation(bonus)
    self.state = "PREPARATION"
    self.rest_bonus = math.max(0, bonus or 0)
    if Expansion.Enabled(self) then
        self.rest_bonus = math.min(self.rest_bonus, self.config.clear_bonus_max, self.config.exploration_window_cap - self.config.preparation_duration)
        self.exploration_seconds_earned = self.exploration_seconds_earned + self.rest_bonus
    end
    self.preparation_total = self.config.preparation_duration + self.rest_bonus
    self.preparation_remaining = self.preparation_total
    self.attack_elapsed = 0
    self.warning_elapsed = 0
    self.current_wave = self.config.waves[self.wave_id]
    self.attack_duration = self.current_wave.attack_duration or self.config.attack_duration
    self.director = WaveDirector.New(self.config, self.wave_id)
    self.map:PrepareWave(self.current_wave)
    self:Emit("PreparationStarted", { wave = self.wave_id, duration = self.preparation_remaining,
        base_duration = self.config.preparation_duration, bonus = self.rest_bonus })
end

function Run:PrepareChallenge()
    if not self.current_wave.challenge then return true end
    local ok, reason = RoomGraph.OpenChallenge(self)
    if ok == false then
        self.technical_error = self.technical_error or { reason = reason or "考验路线无法通行", wave_id = self.wave_id }
        self:Pause("technical")
        self:Emit("ChallengePathError", Feedback.Copy(self.technical_error))
        return false
    end
    return true
end

function Run:StartAttack()
    if self.ended or self.state == "ATTACK" or self.technical_error then return false end
    if not self:PrepareChallenge() then return false end
    self:CancelRecall("开波取消回城")
    if self.wave_id == self.final_intro_wave and not self.story_seen.final_intro then
        self.state = "WARNING"
        self.pause_reasons.story = true
        self.story = { node = "final_intro", elapsed = 0, duration = self.retry and 4 or 8, replay = false }
        self:Emit("StoryRequested", { node = "final_intro", duration = self.story.duration, prototype = true })
        return true
    end
    self.state = "ATTACK"
    self.attack_elapsed = 0
    self.director:Start()
    self:Emit("AttackStarted", { wave = self.wave_id, portals = self.current_wave.active_portals,
        duration = self.attack_duration })
    return true
end

function Run:RequestWave()
    if self.ended or self.state ~= "PREPARATION" or self:IsPaused() then return false end
    if not self:PrepareChallenge() then return false end
    self:CancelRecall("提前开波取消回城")
    self.preparation_remaining = 0
    if self.warning_elapsed >= self.config.warning_duration - 0.000001 then self:StartAttack()
    else self.state = "WARNING"; self:Emit("WarningStarted", { remaining = self.config.warning_duration - self.warning_elapsed }) end
    return true
end

function Run:OpenLogistics()
    if self.ended or self.state ~= "PREPARATION" or self:IsPaused() then return false end
    self:Pause("logistics")
    return true
end

function Run:Transact(action, slotId, towerType, requestId)
    return Economy.Transact(self, action, slotId, towerType, requestId)
end

function Run:ChooseModule(choiceId, moduleId, requestId)
    return TowerModules.Choose(self, choiceId, moduleId, requestId)
end

function Run:OpenModuleChoices(choiceId)
    return TowerModules.Open(self, choiceId)
end

function Run:CloseModuleChoices()
    return TowerModules.Close(self)
end

function Run:ClaimRoom(id, requestId)
    local key = requestId and ("claim:" .. requestId)
    if key and self.transactions[key] ~= nil then return self.transactions[key] end
    if self.ended or self:IsPaused() then return false end
    for _, room in ipairs(self.rooms) do
        if room.id == id and room.state == "cleared" and not room.reward_claimed and self.map:RoomAt(self.player.x, self.player.y) == id then
            room.reward_claimed = true
            room.state = "claimed"
            local definition = {}
            for _, d in ipairs(self.config.rooms) do if d.id == room.id then definition = d; break end end
            local gold = definition.gold_reward or (room.tier == 1 and 40 or 80)
            Expansion.Sand(self, definition.sand_reward or 0, "room:" .. id)
            self.currency = self.currency + gold
            self:GrantExperience(room.tier == 1 and 20 or 40)
            self:Emit("RoomRewardClaimed", { room_id = id, gold = gold, request_id = requestId })
            if key then self.transactions[key] = true end
            self:CheckUpgrade()
            TowerModules.Offer(self, room)
            return true
        end
    end
    return false
end

function Run:RequestRecall()
    if self.ended or self.state ~= "PREPARATION" or self:IsPaused() then return false end
    local id = self.map:RoomAt(self.player.x, self.player.y)
    for _, room in ipairs(self.rooms) do
        if room.id == id and (room.state == "cleared" or room.state == "claimed") then
            self.recall = { active = true, progress = 0, room_id = id }
            self:Emit("RecallStarted", { room_id = id })
            return true
        end
    end
    return false
end

function Run:CancelRecall(reason)
    if not self.recall or not self.recall.active then return end
    self.recall.active = false
    self.recall.progress = 0
    self:Emit("RecallCancelled", { reason = reason })
end

function Run:StorySeen(node)
    local key = self.record_namespace == "legacy_v02" and node or (self.record_namespace .. ":" .. node)
    return self.meta.story_seen[key] == true
end

function Run:FinishStory()
    if not self.story or self.story.node == "" then return false end
    local node, replay = self.story.node, self.story.replay
    self.story.node = ""
    self.story.replay = false
    self.pause_reasons.story = nil
    self:Emit("StoryCompleted", { node = node, replay = replay })
    if replay then
        if self.replay_return_manual then
            self.pause_reasons.manual = true
            self.replay_return_manual = false
        end
        if self.replay_return_story then
            self.story = self.replay_return_story
            self.replay_return_story = nil
            if self.story.node ~= "" then self.pause_reasons.story = true end
        end
        return true
    end
    self.story_seen[node] = true
    local key = self.record_namespace == "legacy_v02" and node or (self.record_namespace .. ":" .. node)
    self.meta.story_seen[key] = true
    self:SaveMeta()
    if node == "opening" then self:EnterPreparation()
    elseif node == "final_intro" then self.state = "WARNING"; self.warning_elapsed = 0 end
    return true
end

function Run:ReplayStory(node)
    if not self:StorySeen(node) or self.story.replay or self.pause_reasons.logistics or self.pause_reasons.upgrade
        or self.pause_reasons.module_choice or self.pause_reasons.map or self.pause_reasons.technical
        or self.pause_reasons.rules or self.pause_reasons.recap then return false end
    if self.story.node ~= "" then
        if not self.pause_reasons.menu then return false end
        self.replay_return_story = self.story
    end
    if self.pause_reasons.manual then
        self.replay_return_manual = true
        self.pause_reasons.manual = nil
    end
    self.pause_reasons.story = true
    self.story = { node = node, elapsed = 0, duration = node == "final_intro" and 8 or 14, replay = true }
    self:Emit("StoryRequested", { node = node, replay = true, prototype = true })
    return true
end

function Run:PresentationUpdate(dt)
    -- 只推进演出时间，不推进世界；用户暂停/失焦时演出也停止。
    local canPlay = self.story.replay or not self.pause_reasons.menu
    if self.story.node ~= "" and not self.pause_reasons.manual and not self.pause_reasons.focus
        and not self.pause_reasons.rules and not self.pause_reasons.recap and not self.pause_reasons.logistics
        and not self.pause_reasons.upgrade and not self.pause_reasons.module_choice
        and not self.pause_reasons.map and not self.pause_reasons.technical and canPlay then
        self.story.elapsed = self.story.elapsed + dt
        if self.story.elapsed >= self.story.duration then self:FinishStory() end
    end
end

function Run:SaveMeta()
    self.meta.revision = (self.meta.revision or 0) + 1
    if self.on_meta then
        local ok, errorMessage = pcall(self.on_meta, self.meta)
        if not ok then self:Emit("SaveFailed", { reason = tostring(errorMessage) }) end
    end
end

function Run:End(result, reason)
    if self.ended then return false end
    self.ended, self.result, self.end_reason = true, result, reason or ""
    self.state = "END_SETTLEMENT"
    self.options = {}
    TowerModules.Close(self)
    self.module_inventory, self.pending_module_choices, self.room_module_claims = {}, {}, {}
    self.module_choice_id = nil
    self.pause_reasons = {}
    Reactions.Close(self)
    self:CancelRecall("本局结束")
    self:Emit("RunEnded", { result = result, reason = self.end_reason, wave = self.wave_id })
    if result == "victory" and self.can_record_chapter and self.total_waves == 20 then
        self.meta.chapters[tostring(self.chapter + 1)] = true
        self.pause_reasons.story = true
        self.story = { node = "ending", elapsed = 0, duration = self.retry and 5 or 14, replay = false }
    else self.story.node = "" end
    Feedback.Finish(self)
    -- 结束事实已复制进报告；幂等账本、随机流和开门/生成缓存不跨局保留。
    self.transactions, self.challenge_opened, self.combat_spawn_keys = {}, {}, {}
    self.module_rng, self.module_seed = nil, nil
    self:SaveMeta()
    return true
end

function Run:CheckFailure()
    if self.ended then return true end
    if self.player.hp <= 0 then self:End("defeat", "角色生命归零"); return true end
    if self.core.hp <= 0 then self:End("defeat", "核心耐久归零"); return true end
    return false
end

function Run:SettleWave()
    if self.technical_error or self:CheckFailure() or self.settled_waves[self.wave_id] or self:PendingHarmfulCount() > 0
        or not self.director.generation_complete or self:AliveCount() > 0 then return end
    self.state = "WAVE_SETTLEMENT"
    self.settled_waves[self.wave_id] = true
    self.currency = self.currency + self.current_wave.reward
    local bonus = Expansion.Bonus(self)
    local continues = self.wave_id < self.total_waves or self.wave_id == 20 and Expansion.ShouldStartTrial(self)
    Expansion.RecordWave(self, continues and bonus or 0)
    self:Emit("WaveCleared", { wave = self.wave_id, reward = self.current_wave.reward,
        attack_elapsed = self.attack_elapsed, attack_duration = self.attack_duration,
        rest_bonus = continues and bonus or 0 })
    if self.wave_id % 5 == 0 then
        local id = tostring(self.chapter) .. ":" .. tostring(self.wave_id)
        if self.record_namespace ~= "legacy_v02" then id = self.record_namespace .. ":" .. id end
        if not self.meta.stages[id] then
            self.meta.stages[id] = { chapter = self.chapter, wave = self.wave_id, completed = true,
                scenario_id = self.scenario_id, rules_version = self.rules_version, record_namespace = self.record_namespace }
            self:SaveMeta()
        end
        Feedback.Stage(self)
        self:Emit("StageRecorded", { id = id, wave = self.wave_id })
    end
    if self.wave_id >= self.total_waves then
        if Expansion.StartTrial(self, bonus) then return end
        if self.trial_started then Expansion.Sand(self, 20, "expedition_completed") end
        self:End("victory", "全部进攻单位已清空")
    else self.wave_id = self.wave_id + 1; self:EnterPreparation(bonus) end
end

function Run:Step(dt, intent)
    if self:CheckFailure() or self:IsPaused() then return end
    if self.state == "DEPLOY" then return end
    self.clock = self.clock + dt
    -- 先提交当前时槽全部有害反应，不被升级、自然开波、普通AI提前抢占。
    Combat.ProcessReactions(self)
    if self:CheckFailure() then return end
    if self.state == "PREPARATION" then
        local old = self.preparation_remaining
        self.preparation_remaining = math.max(0, old - dt)
        Expansion.TrackExploration(self, dt, old)
        local warningBefore = math.max(0, self.config.warning_duration - old)
        local warningAfter = math.max(0, self.config.warning_duration - self.preparation_remaining)
        self.warning_elapsed = Expansion.Enabled(self) and 0 or math.min(self.config.warning_duration, self.warning_elapsed + warningAfter - warningBefore)
        if self.preparation_remaining <= self.config.warning_duration and not self:PrepareChallenge() then return end
        if self.preparation_remaining <= 0 then
            if Expansion.Enabled(self) then
                self.state = "WARNING"; self.warning_elapsed = 0
                self:Emit("WarningStarted", { remaining = self.config.warning_duration })
            else self:StartAttack() end
        end
    elseif self.state == "WARNING" then
        self.warning_elapsed = math.min(self.config.warning_duration, self.warning_elapsed + dt)
        if self.warning_elapsed >= self.config.warning_duration - 0.000001 then self:StartAttack() end
    end
    if self:IsPaused() then return end
    if self.state == "ATTACK" then
        -- 生成队列完成后仍计时，直到残敌和有害反应全部结算；暂停由 Step 入口拦截。
        self.attack_elapsed = self.attack_elapsed + dt
        if Expansion.Enabled(self) and self.trial_started and self.attack_elapsed >= self.config.expedition_time_cap then
            self:End("defeat", "远征" .. tostring(self.config.expedition_time_cap) .. "秒时限届满"); return
        end
        self.director:Update(dt, self:AliveCount(), function(unit) return Combat.Spawn(self, unit) and true or false end)
    end
    Combat.Update(self, dt, intent)
    RoomGraph.UpdateAccess(self)
    if self.technical_error then return end
    Combat.ProcessReactions(self)
    Reactions.Prune(self)
    if self:CheckFailure() then return end
    Feedback.Update(self)
    if self.recall.active then
        if self.state ~= "PREPARATION" or math.abs(intent.x or 0) + math.abs(intent.y or 0) > 0 then
            self:CancelRecall("移动或状态切换")
        else
            self.recall.progress = self.recall.progress + dt
            if self.recall.progress >= self.config.recall_duration - 0.000001 then
                self.player.x, self.player.y = self.config.recall_position.x, self.config.recall_position.y
                self.recall.active = false
                self:Emit("RecallCompleted", { x = self.player.x, y = self.player.y })
            end
        end
    end
    if self:CheckUpgrade() then return end
    if self.state == "ATTACK" and self.director.generation_complete and self:AliveCount() == 0
        and self:PendingHarmfulCount() == 0 then self:SettleWave() end
end

function Run:Update(dt, intent)
    if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt == math.huge then return end
    if self:CheckFailure() or self:IsPaused() then return end
    intent = intent or {}
    local remaining = dt
    local stepIntent = { x = intent.x or intent.move_x or 0, y = intent.y or intent.move_y or 0, active = intent.active }
    while remaining > 0.000001 do
        local step = math.min(remaining, self.config.max_step)
        local pending = self.scheduled_events[1]
        if pending and pending.at > self.clock + 0.00000001 then
            step = math.min(step, pending.at - self.clock) -- 落在事件槽，不让粗dt挪动死点反应时序。
        end
        self:Step(step, stepIntent)
        stepIntent.active = false -- 单次按下只消费一次，不能因大帧子步重复释放。
        remaining = remaining - step
        if self.ended or self:IsPaused() then break end
    end
end

function Run:Snapshot()
    local _, activeTarget = Combat.ActiveTarget(self)
    return { expansion = Expansion.Snapshot(self), version = self.config.version, run_id = self.run_id, state = self.state, wave = self.wave_id,
        total_waves = self.total_waves, clock = self.clock, core_hp = self.core.hp, player_hp = self.player.hp,
        core_x = self.core.x, core_y = self.core.y, currency = self.currency, level = self.player.level,
        experience = self.player.experience, alive = self:AliveCount(), queue_remaining = self.director:Remaining(),
        generation_complete = self.director.generation_complete, preparation_remaining = self.preparation_remaining,
        preparation_total = self.preparation_total, rest_bonus = self.rest_bonus,
        attack_elapsed = self.attack_elapsed, attack_duration = self.attack_duration,
        warning_elapsed = self.warning_elapsed, repair_uses = self.repair_uses, paused = self:IsPaused(),
        rng_state = self.rng.state, rng_calls = self.rng.calls, result = self.result,
        pending_harmful_reactions = self.pending_harmful_reactions, scheduled_count = #self.scheduled_events,
        causal_summaries = Feedback.Copy(self:CausalSummaries()), active_target = activeTarget,
        range_opportunity_offered = self.range_opportunity_offered, scenario_id = self.scenario_id,
        rules_version = self.rules_version, record_namespace = self.record_namespace,
        map_size = Feedback.Copy(self.config.map_size), map_origin = Feedback.Copy(self.config.map_origin or { x = 0, y = 0 }),
        modules = TowerModules.Snapshot(self), rooms = Feedback.Copy(self.rooms), towers = Feedback.Copy(self.towers),
        challenge = Feedback.Copy(self.current_wave.challenge), expeditions = Expedition.Snapshot(self),
        technical_error = Feedback.Copy(self.technical_error) }
end
return Run
