-- R28–R40 公共交互协议与稳定反应队列。纯 Lua，不依赖引擎或表现层。
-- Q19 原型：本局所有有害死亡反应（包括 room_id 守军）都阻挡清波；身份本身不改写。
-- 爆炸不递归：死亡只加入未来事件；到期按 at + sequence 迭代提交整个时间槽。
-- 生命周期去重按实体/副作用，不按 root 去重多个死亡。反馈摘要只保存已提交事实。
local R = {}
local EPS = 1e-8

---@param run table
function R.Init(run)
    run.scheduled_events, run.pending_harmful_reactions = {}, 0
    run.next_stable_sequence, run.next_action_id = 1, 1
    run.side_effect_ledger, run.effect_ledger, run.reaction_event_ledger = {}, {}, {}
    run.next_causal_prune = 1
    run.causal_summaries, run.causal_history, run.causal_by_root = {}, {}, {}
    run.causal_queue_closed, run.processing_reactions = false, false
end

---@param run table
---@param entity table
function R.Sync(run, entity)
    entity.entity_id = entity.entity_id or entity.id or entity.slot_id
    entity.id = entity.id or entity.entity_id
    entity.position = entity.position or {}
    entity.position.x, entity.position.y = entity.x, entity.y
    entity.collision = entity.collision or {}
    entity.collision.radius = entity.radius or entity.collision.radius or 0
    entity.weight = entity.weight or 1
    if entity.damageable == nil then entity.damageable = true end
    if entity.anchored == nil then entity.anchored = false end
    if entity.movable == nil then entity.movable = not entity.anchored end
    if entity.explodes_on_death == nil then entity.explodes_on_death = false end
    entity.active_statuses = entity.slow_effects or entity.active_statuses or {}
    entity.slow_effects = entity.active_statuses
    entity.slow_factor = entity.slow_factor or 1
    return entity
end

---@param run table
---@param context table|string|nil
function R.Context(run, context, sourceId)
    local input = type(context) == "table" and context or { source = context or "effect" }
    local result = {}
    for key, item in pairs(input) do result[key] = item end
    result.source = result.source or "effect"
    result.source_id = result.source_id or sourceId or result.source
    if not result.root_action_id then
        result.root_action_id = run.run_id .. ":action:" .. tostring(run.next_action_id)
        run.next_action_id = run.next_action_id + 1
    end
    result.run_id = result.run_id or run.run_id
    return result
end

---@param run table
---@param entity table
function R.Once(run, entity, sideEffect)
    local key = tostring(entity.entity_id or entity.id or entity.slot_id) .. ":" .. sideEffect
    if run.side_effect_ledger[key] then return false end
    run.side_effect_ledger[key] = true
    return true
end

-- 只保存标量和坐标副本；有界的是展示事实，不是逻辑事件流/奖励账本。
local SEGMENT_FIELDS = { "event_id", "kind", "run_id", "wave", "wave_id", "room_id", "time", "planned_at",
    "source", "source_id", "target_id", "root_action_id", "parent_event_id", "triggering_action_id",
    "related_displacement_event_id", "portal", "amount", "before_hp", "after_hp", "reason", "radius",
    "at", "delay", "damage", "factor", "expires_at", "status", "active", "sequence", "harmful",
    "hits", "kills", "core_damage", "player_damage", "tower_damage", "attack_kind", "displacement", "blocked",
    "route_id", "route_index", "stage", "before", "after", "current_room_id", "cap", "used", "actual", "suppressed", "requested" }
local function copySegment(segment)
    local result = {}
    for _, key in ipairs(SEGMENT_FIELDS) do
        local item = segment[key]
        if type(item) == "string" or type(item) == "number" or type(item) == "boolean" then result[key] = item end
    end
    for _, key in ipairs({ "position", "old_position", "origin_position" }) do
        local point = segment[key]
        if point then result[key] = { x = point.x, y = point.y } end
    end
    return result
end

---@param run table
---@param context table
local function summaryFor(run, context, x, y)
    if not context or context.run_id ~= run.run_id then return end
    local root = context.root_action_id
    local summary = run.causal_by_root[root]
    if summary then return summary end
    if not context.track_causal and context.source ~= "active" and context.source ~= "death_explosion" then return end
    summary = { root_action_id = root, source = context.source, source_id = context.source_id,
        time = run.clock, expires_at = run.clock, x = x, y = y,
        wave = run.wave_id, started_at = run.clock, origin_x = x, origin_y = y,
        pushed = 0, explosions = 0, hits = 0, kills = 0, core_damage = 0, player_damage = 0,
        tower_damage = 0, gold = 0, experience = 0, target_ids = {}, facts = {}, segments = {}, segments_omitted = 0 }
    run.causal_by_root[root] = summary
    run.causal_history[#run.causal_history + 1] = summary
    local limit = (run.config.reactions or {}).history_limit or 64
    if #run.causal_history > limit then table.remove(run.causal_history, 1) end
    return summary
end

-- 事件负载是独立事实快照，不保留实体可变 position 引用。
---@param run table
---@param context table
function R.Emit(run, kind, data, context)
    data = data or {}
    data.root_action_id = context.root_action_id
    data.parent_event_id = context.parent_event_id
    data.source = data.source or context.source
    data.source_id = data.source_id or context.source_id
    data.triggering_action_id = context.triggering_action_id
    data.related_displacement_event_id = data.related_displacement_event_id or context.related_displacement_event_id
    data.planned_at = context.planned_at or run.clock
    if data.x ~= nil and data.y ~= nil then data.position = { x = data.x, y = data.y }
    elseif data.position then data.position = { x = data.position.x, y = data.position.y } end
    local eventId = run:Emit(kind, data)
    local summary = summaryFor(run, context, data.x, data.y)
    if summary then
        local segment = copySegment(data)
        segment.kind, segment.event_id, segment.time, segment.run_id = kind, eventId, run.clock, run.run_id
        segment.wave = data.wave or data.wave_id or run.wave_id
        segment.after_hp = data.after_hp or data.hp
        if data.old_x ~= nil and data.old_y ~= nil then segment.old_position = { x = data.old_x, y = data.old_y } end
        if data.origin_x ~= nil and data.origin_y ~= nil then segment.origin_position = { x = data.origin_x, y = data.origin_y } end
        summary.segments[#summary.segments + 1] = segment
        if #summary.segments > 16 then
            table.remove(summary.segments, 1)
            summary.segments_omitted = (summary.segments_omitted or 0) + 1
        end
        summary.time = run.clock -- 旧root晚到账也可按最近实际事件选择，不改变history插入次序。
    end
    return eventId
end

---@param run table
---@param context table
function R.Record(run, context, changes)
    local summary = summaryFor(run, context, changes.x, changes.y)
    if not summary then return end
    local root = context.root_action_id
    for _, key in ipairs({ "pushed", "explosions", "hits", "kills", "core_damage", "player_damage", "tower_damage", "gold", "experience" }) do
        summary[key] = summary[key] + (changes[key] or 0)
    end
    if changes.target_id then summary.target_ids[tostring(changes.target_id)] = true end
    if changes.x then summary.x, summary.y = changes.x, changes.y end
    if changes.event_id then summary.last_event_id = changes.event_id end
    summary.time = run.clock
    summary.expires_at = run.clock + ((run.config.reactions or {}).summary_duration or 2)
    if changes.fact then
        summary.facts[#summary.facts + 1] = changes.fact
        -- 一条摘要最多保留16个事实文本，原事件流仍完整。
        if #summary.facts > 16 then table.remove(summary.facts, 1) end
    end
    local interesting = summary.pushed > 0 or summary.explosions > 0
    if interesting then
        local present = false
        for _, old in ipairs(run.causal_summaries) do if old == summary then present = true; break end end
        if not present then run.causal_summaries[#run.causal_summaries + 1] = summary end
        local limit = (run.config.reactions or {}).summary_limit or 2
        while #run.causal_summaries > limit do table.remove(run.causal_summaries, 1) end
        run:Emit("CausalSummary", { summary = R.CopySummary(summary), root_action_id = root,
            parent_event_id = summary.last_event_id, source_id = context.source_id })
    end
    return summary
end

function R.CopySummary(summary)
    local result = {}
    for key, item in pairs(summary) do
        if type(item) ~= "table" then result[key] = item end
    end
    result.facts = {}
    for _, fact in ipairs(summary.facts) do result.facts[#result.facts + 1] = fact end
    result.segments = {}
    for _, segment in ipairs(summary.segments or {}) do result.segments[#result.segments + 1] = copySegment(segment) end
    result.target_ids = {}
    for id in pairs(summary.target_ids) do result.target_ids[#result.target_ids + 1] = id end
    table.sort(result.target_ids)
    return result
end

---@param run table
function R.Summaries(run, history)
    local results = {}
    for _, summary in ipairs(history and run.causal_history or run.causal_summaries) do
        if history or summary.expires_at > run.clock or run.ended then
            results[#results + 1] = R.CopySummary(summary)
        end
    end
    return results
end

---@param run table
---@param entity table
---@param context table
function R.ScheduleDeath(run, entity, context)
    if run.ended or run.causal_queue_closed or not entity.explodes_on_death then return false end
    if not R.Once(run, entity, "reaction_scheduled") then return false end
    local defaults, own = run.config.reactions or {}, entity.death_reaction or {}
    local delay = math.max(0.001, own.delay or defaults.delay or 0.7)
    local sequence = run.next_stable_sequence
    run.next_stable_sequence = sequence + 1
    local event = { kind = "death_explosion", at = run.clock + delay, planned_at = run.clock + delay, delay = delay,
        sequence = sequence, x = entity.x, y = entity.y, radius = own.radius or defaults.radius or 2.5,
        damage = own.damage or defaults.damage or 40, source_id = entity.entity_id,
        origin_portal = entity.origin_portal, wave_id = entity.wave_id, room_id = entity.room_id,
        root_action_id = context.root_action_id, parent_event_id = context.parent_event_id,
        triggering_action_id = context.triggering_action_id, related_displacement_event_id = context.related_displacement_event_id,
        run_id = run.run_id, committed = false, entity = entity }
    event.event_id = R.Emit(run, "ReactionScheduled", { x = event.x, y = event.y, radius = event.radius,
        damage = event.damage, delay = delay, at = event.at, wave_id = event.wave_id, room_id = event.room_id,
        id = entity.id, source_id = event.source_id, sequence = sequence, harmful = true }, context)
    entity.reaction_scheduled = true
    run.scheduled_events[#run.scheduled_events + 1] = event
    table.sort(run.scheduled_events, function(a, b) return a.at < b.at or (a.at == b.at and a.sequence < b.sequence) end)
    run.pending_harmful_reactions = run.pending_harmful_reactions + 1
    return event
end

---@param run table
---@param resolve fun(event:table, context:table)
function R.Process(run, resolve)
    if run.ended or run.causal_queue_closed or run:IsPaused() or run.processing_reactions then return 0 end
    run.processing_reactions = true
    local processed = 0
    while #run.scheduled_events > 0 do
        local first = run.scheduled_events[1]
        if first.at > run.clock + EPS then break end
        local slot = first.at
        -- 整槽所有结果先提交（包括核心已被前一个反应致死后的其他命中），Run随后判失败。
        while #run.scheduled_events > 0 and run.scheduled_events[1].at <= slot + EPS do
            local event = table.remove(run.scheduled_events, 1)
            local identity = tostring(event.run_id) .. ":" .. tostring(event.event_id)
            if event.run_id == run.run_id and not event.committed and not run.reaction_event_ledger[identity]
                and not event.entity.reaction_committed then
                run.reaction_event_ledger[identity] = true
                event.committed = true
                event.entity.reaction_committed = true
                run.pending_harmful_reactions = math.max(0, run.pending_harmful_reactions - 1)
                local context = R.Context(run, { source = "death_explosion", source_id = event.source_id,
                    root_action_id = event.root_action_id, parent_event_id = event.event_id,
                    triggering_action_id = event.triggering_action_id, related_displacement_event_id = event.related_displacement_event_id,
                    planned_at = event.at, run_id = event.run_id, portal = event.origin_portal, processing_reaction = true })
                resolve(event, context)
                processed = processed + 1
            end
        end
        -- 函数只处理队列；不End、不升级、不清波。新死亡反应仍至少delay后，不即时递归。
        if run.player.hp <= 0 or run.core.hp <= 0 then break end -- 整个槽已提交，后槽先交Run判失败。
    end
    run.processing_reactions = false
    return processed
end

---@param run table
function R.Prune(run)
    if run.clock < run.next_causal_prune then return end
    run.next_causal_prune = run.clock + 1
    local retained = {}
    for _, summary in ipairs(run.causal_history) do retained[summary.root_action_id] = true end
    for _, event in ipairs(run.scheduled_events) do retained[event.root_action_id] = true end
    for _, projectile in ipairs(run.projectiles) do
        if projectile.alive and projectile.root_action_id then retained[projectile.root_action_id] = true end
    end
    for _, drop in ipairs(run.drops) do if drop.alive and drop.root_action_id then retained[drop.root_action_id] = true end end
    for _, enemy in ipairs(run.enemies) do
        local displacement = enemy.last_displacement
        if enemy.alive and displacement and run.clock - displacement.at <= run.config.player.active_cooldown then
            retained[displacement.root_action_id] = true
        end
    end
    for root, summary in pairs(run.causal_by_root) do
        if not retained[root] and summary.expires_at <= run.clock then run.causal_by_root[root] = nil end
    end
    local visible = {}
    for _, summary in ipairs(run.causal_summaries) do
        if summary.expires_at > run.clock then visible[#visible + 1] = summary end
    end
    run.causal_summaries = visible
end

---@param run table
function R.Close(run)
    run.causal_queue_closed = true
    for _, event in ipairs(run.scheduled_events) do event.cancelled = true end
    run.scheduled_events, run.pending_harmful_reactions = {}, 0
end

return R
