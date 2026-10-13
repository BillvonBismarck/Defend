-- 固定据点防守：纯 Lua 模拟。仅 Run 驱动；不订阅渲染、不推进 run.clock、不结算清波。
-- 碰撞设计（坐标为逻辑格，X 向右/Y 向下）：
--        墙/柱 ####                 圆形敌人 E(r)
-- 玩家 P(r=.35) ---- 弹体扫掠胶囊 ----> E
--                 #### | 首个墙接触截断，其后的 E 不可命中
-- 核心 C(r=1.6) <- 敌人圆 + 接触距离；塔是伤害目标而不是移动障碍。
-- 脉冲/爆破：(中心 O, 半径 R) + O->目标 LOS，不能跨柱/锁门。
-- 边界：零长度/起点重叠算接触；切线算命中；墙与目标同刻优先墙；
-- 高 dt 分步，弹体用线段-扩张圆求首交，不靠帧末重叠，避免穿越小目标。
-- 守军移动/弹体均限制本房；离房不回满血；尸体、金币、经验不阻挡路径。
local Combat = {}
local Reactions = require("defense.Reactions")
local Expansion = require("defense.Expansion")
local Expedition = require("defense.Expedition")
local TowerModules = require("defense.TowerModules")
local RoomGraph = require("defense.RoomGraph")

-- Q04/Q06/Q09/Q12 临时补值，只在此模块使用；config.combat 可覆盖这些未定参数。
local TEMP = {
    bullet_radius = 0.08, enemy_bullet_speed = 10, ranged_range = 8, harass_duration = 3,
    melee_reach = 0.22, tower_radius = 0.65, blocker_range = 1.45,
    charge_range = 6, charge_speed = 8, charge_duration = 1.2, siege_charge_interval = 6,
    boss_area_range = 7, boss_area_radius = 3.2, boss_area_interval = 5,
    summon_first = 5, summon_interval = 6, summon_rounds = 3, summon_count = 3,
    slow_duration = 2, pickup_radius = 1.1, pickup_mobility = 0.35,
    path_interval = 0.8, stuck_duration = 3, effect_duration = 0.35,
}

---@param run table
local function value(run, key)
    return (run.config.combat or {})[key] or TEMP[key]
end

local function distance2(ax, ay, bx, by)
    return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function direction(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0.000001 then return 0, 0, 0 end
    return dx / length, dy / length, length
end

---@param run table
local function nextId(run)
    local id = run.next_entity_id
    run.next_entity_id = id + 1
    return id
end

---@param e table
local function boss(e)
    return e.is_boss == true or e.role == "commander" or e.role == "siege" or e.role == "final" or e.role == "expedition" or e.role == "expedition_elite"
end

---@param run table
local function stopped(run)
    return run.ended == true or run:IsPaused() or run.player.hp <= 0 or run.core.hp <= 0
end

---@param run table
---@param p table
local function skill(run, p, id)
    -- Progression.Apply 仅 vitality 直接改生命，其余技能在模拟端派生，不重复写回基础值。
    return math.max(0, p.skills[id] or 0)
end

---@param run table
local function roomAt(run, x, y)
    local room = run.map:RoomAt(x, y)
    if type(room) == "table" then return room.id end
    return room
end

---@param run table
local function findRoom(run, id)
    for _, room in ipairs(run.rooms) do if room.id == id then return room end end
end

---@param run table
local function portalPoint(run, portal)
    local x, y = run.map:PortalPoint(portal)
    if type(x) == "table" then return x.x, x.y end
    return x, y
end

---@param run table
local function visible(run, ax, ay, bx, by, radius)
    return run.map:LineOfSight(ax, ay, bx, by, radius or 0)
end

---@param run table
local function effect(run, kind, x, y, radius, duration)
    run.effects[#run.effects + 1] = { kind = kind, x = x, y = y, radius = radius,
        timer = duration or value(run, "effect_duration"), alive = true }
end

-- 不在迭代中 table.remove；稳定原位压缩，保留未处理实体的顺序。
---@param list table[]
local function compact(list)
    local write = 1
    for read = 1, #list do
        local item = list[read]
        if item.alive ~= false then list[write] = item; write = write + 1 end
    end
    for i = write, #list do list[i] = nil end
end

---@param run table
---@param target table
local function damageTarget(run, target, amount, kind, portal, suppliedContext)
    Reactions.Sync(run, target)
    if run.ended or run.causal_queue_closed or not target.damageable or target.hp <= 0 or amount <= 0 then return false end
    local context = Reactions.Context(run, suppliedContext or "effect", suppliedContext and suppliedContext.source_id)
    if context.run_id ~= run.run_id then return false end
    if kind == "player" and (target.invulnerable == true or
        (type(target.invulnerable) == "number" and target.invulnerable > 0)) then
        Reactions.Emit(run, "DamageRejected", { target_id = target.entity_id, reason = "invulnerable" }, context)
        return false
    end
    if kind == "core" then amount = Expansion.CoreDamage(run, amount, context) end
    if amount <= 0 then return false end
    local actual = math.min(target.hp, amount)
    local previous = target.hp
    target.hp = math.max(0, previous - amount)
    local event = kind == "core" and "CoreDamaged" or kind == "player" and "PlayerDamaged" or "TowerDamaged"
    local eventId = Reactions.Emit(run, event, { amount = actual, hp = target.hp, before_hp = previous, after_hp = target.hp, portal = portal,
        x = target.x, y = target.y, slot_id = target.slot_id, target_id = target.entity_id }, context)
    local changes = { x = target.x, y = target.y, target_id = target.entity_id, event_id = eventId }
    changes[kind .. "_damage"] = actual
    Reactions.Record(run, context, changes)
    if kind == "player" then run:CancelRecall("受击取消回城") end
    if target.hp <= 0 and Reactions.Once(run, target, "death") then
        target.alive, target.death_committed = false, true
        local damageContext = Reactions.Context(run, context)
        damageContext.parent_event_id = eventId
        local deathId = Reactions.Emit(run, kind == "tower" and "TowerDestroyed" or "EntityDied",
            { slot_id = target.slot_id, x = target.x, y = target.y, target_id = target.entity_id }, damageContext)
        local deathContext = Reactions.Context(run, context)
        deathContext.parent_event_id = deathId
        Reactions.ScheduleDeath(run, target, deathContext)
    end
    return true
end

---@param run table
---@param e table
---@param source any
function Combat.DamageEnemy(run, e, amount, source)
    Reactions.Sync(run, e)
    if run.ended or run.causal_queue_closed or not e.alive or not e.damageable or e.death_committed or amount <= 0 then return false end
    local context = Reactions.Context(run, source)
    if context.run_id ~= run.run_id then return false end
    if e.last_displacement and context.source ~= "death_explosion" and run.clock - e.last_displacement.at <= run.config.player.active_cooldown then
        -- 位移只关联解释root，不取代当前攻击（例如Shoot）的直接父因，也不推断意图。
        context.triggering_action_id = context.root_action_id
        context.root_action_id = e.last_displacement.root_action_id
        context.related_displacement_event_id = e.last_displacement.event_id
    end
    if e.explodes_on_death or e.last_displacement then context.track_causal = true end
    local previous = e.hp
    local requested = amount
    local allowed, capReason = Expedition.DamageAmount(run, e, amount)
    local actual = math.min(previous, allowed)
    e.hp = math.max(0, previous - actual)
    if actual <= 0 then
        Expedition.CommitDamage(run, e, requested, 0, capReason, context)
        return false -- DamageCapped不是Hit；无伤害不增加命中/输出统计。
    end
    local killed = e.hp <= 0
    if killed then
        -- 在任何 Emit 前失活；音效/日志适配器重入也不能二次死亡、反应或掉落。
        e.alive, e.death_committed = false, true
        e.summon_pending, e.warning_timer, e.charge_timer = 0, 0, 0
        e.warning_kind, e.charge_context = nil, nil
        Reactions.Once(run, e, "death")
    end
    Expedition.CommitDamage(run, e, requested, actual, capReason, context)
    if killed then Expedition.Died(run, e, context) end
    local hitId = Reactions.Emit(run, "Hit", { id = e.id, target_id = e.entity_id, role = e.role, x = e.x, y = e.y,
        amount = actual, before_hp = previous, after_hp = e.hp, hp = e.hp }, context)
    Reactions.Record(run, context, { hits = 1, kills = killed and 1 or 0, x = e.x, y = e.y,
        target_id = e.entity_id, event_id = hitId })
    if not killed then return true end
    local def = run.config.enemies[e.role] --[[@as table]]
    local xp = def.xp or (boss(e) and 30 or e.role == "elite" and 10 or 2)
    local gold = e.room_id and 0 or (def.gold or (boss(e) and 30 or e.role == "elite" and 8 or 1))
    if Reactions.Once(run, e, "drop") then
        for _, drop in ipairs({ { kind = "experience", amount = xp }, { kind = "gold", amount = gold } }) do
            if drop.amount > 0 then
                run.drops[#run.drops + 1] = { id = nextId(run), kind = drop.kind, amount = drop.amount,
                    x = e.x, y = e.y, radius = 0.15, alive = true, room_id = e.room_id,
                    root_action_id = context.root_action_id, parent_event_id = hitId, source_id = e.entity_id }
            end
        end
    end
    if Reactions.Once(run, e, "death_event") then
        local hitContext = Reactions.Context(run, context)
        hitContext.parent_event_id = hitId
        local deathId = Reactions.Emit(run, "EnemyDied", { id = e.id, target_id = e.entity_id, role = e.role,
            subtype = e.subtype, emoji = e.emoji, marker = e.marker, radius = e.radius,
            x = e.x, y = e.y, wave_id = e.wave_id, room_id = e.room_id, portal = e.origin_portal }, hitContext)
        local deathContext = Reactions.Context(run, context)
        deathContext.parent_event_id = deathId
        Reactions.ScheduleDeath(run, e, deathContext)
    end
    return true
end

-- 公共多阵营伤害入口；外部效果不用猜角色/核心/塔函数。
---@param run table
---@param target table
function Combat.Damage(run, target, amount, context)
    if not target then return false end
    if target == run.core then return damageTarget(run, target, amount, "core", context and context.portal, context) end
    if target == run.player then return damageTarget(run, target, amount, "player", context and context.portal, context) end
    if target.slot_id then return damageTarget(run, target, amount, "tower", context and context.portal, context) end
    return Combat.DamageEnemy(run, target, amount, context)
end

---@param run table
---@param unit table role/portal 必需；守军额外 room_id/x/y；召唤额外 wave_id。
---@return table|boolean enemy 或 false（软上限延期，调用者保留队列）
function Combat.Spawn(run, unit)
    if unit.spawn_key and run.combat_spawn_keys and run.combat_spawn_keys[unit.spawn_key] then
        return run.combat_spawn_keys[unit.spawn_key] -- 包括已死亡实体，重复生成不重开账本。
    end
    if (unit.role == "expedition" or run.config.sanctuary_expansion and unit.route_id ~= nil) and (unit.room_id ~= nil or type(unit.route_id) ~= "string") then
        return Expedition.TechnicalError(run, nil, "invalid_expedition_identity", { route_id = unit.route_id })
    end
    local def = run.config.enemies[unit.role] --[[@as table?]]
    if not def then
        run:Emit("CombatError", { reason = "unknown_role", role = unit.role })
        if (unit.role == "expedition" or run.config.sanctuary_expansion and unit.route_id ~= nil) then Expedition.TechnicalError(run, nil, "missing_expedition_role", { route_id = unit.route_id }) end
        return false
    end
    if not unit.room_id and run:AliveCount() >= run.config.alive_soft_limit then return false end
    local portal = unit.portal or unit.origin_portal or "W"
    local x, y = unit.x, unit.y
    if not x or not y then
        x, y = portalPoint(run, portal)
        if x and unit.spawn_offset then
            local sx, sy = x + (unit.spawn_offset.x or 0), y + (unit.spawn_offset.y or 0)
            if run.map:IsWalkable(sx, sy, def.radius) then x, y = sx, sy end
        end
    end
    if not x or not run.map:IsWalkable(x, y, def.radius) then
        run:Emit("CombatError", { reason = "invalid_spawn", role = unit.role, portal = portal })
        if (unit.role == "expedition" or run.config.sanctuary_expansion and unit.route_id ~= nil) then Expedition.TechnicalError(run, nil, "invalid_spawn", { route_id = unit.route_id, portal = portal }) end
        return false
    end
    if (unit.role == "expedition" or run.config.sanctuary_expansion and unit.route_id ~= nil) then
        local ok, reason, details = Expedition.Validate(run, unit.route_id, { x = x, y = y }, def.radius)
        if not ok then return Expedition.TechnicalError(run, nil, reason, details or { route_id = unit.route_id }) end
    end
    local e = { id = nextId(run), role = unit.role, origin_portal = portal,
        wave_id = unit.room_id and nil or (unit.wave_id or run.wave_id), room_id = unit.room_id,
        x = x, y = y, hp = def.hp, max_hp = def.hp, radius = def.radius, alive = true,
        attack_cd = 0, warning_timer = 0, stuck_timer = 0, path_timer = 0, path = {}, path_index = 1,
        slow_effects = {}, slow_factor = 1, harass_timer = 0, charge_cd = 0, charge_timer = 0,
        area_cd = value(run, "boss_area_interval"), summon_timer = value(run, "summon_first"),
        summon_rounds = 0, summon_pending = 0, born_at = run.clock, summoned_by = unit.summoned_by }
    -- Lua 的 and nil or 会回退，守军波次必须显式清掉。
    if unit.room_id then e.wave_id = nil end
    local explosive = unit.subtype == "explosive" or unit.explodes_on_death == true or def.explodes_on_death == true
    e.subtype, e.explodes_on_death = explosive and "explosive" or unit.subtype, explosive
    e.team, e.damageable = def.team or "enemy", def.damageable ~= false
    e.movable, e.anchored, e.weight = def.movable ~= false, def.anchored == true, def.weight or 1
    local emojiList = run.config.enemy_emoji and run.config.enemy_emoji[e.role] or { def.emoji or "?" }
    e.emoji = emojiList[(e.id - 1) % #emojiList + 1]
    e.marker, e.opportunity_tag = explosive and run.config.explosive_marker or nil, unit.opportunity_tag
    if explosive then
        -- Q16 HP≈4次最初基础命中，single初始25%加成仍需4次；不是免伤/按combo隐藏阈值。
        e.hp = (run.config.reactions or {}).explosive_hp or run.config.player.damage * ((run.config.reactions or {}).initial_hits or 4)
        e.max_hp = e.hp
        -- 未指定实体覆盖时由ScheduleDeath读取run.config.reactions，默认仍为.7/2.5/40。
        e.death_reaction = unit.death_reaction or def.death_reaction
    end
    e.is_boss = def.is_boss == true or unit.role == "commander" or unit.role == "siege" or unit.role == "final"
    e.summon_disabled = def.summon_disabled == true
    e.squad_id = unit.squad_id
    e.core_budget_room = unit.regional and unit.portal:match("^zone_(.+)$") or nil
    Reactions.Sync(run, e)
    if (unit.role == "expedition" or run.config.sanctuary_expansion and unit.route_id ~= nil) then Expedition.Init(run, e, unit.route_id) end
    if unit.spawn_key then
        run.combat_spawn_keys = run.combat_spawn_keys or {}
        run.combat_spawn_keys[unit.spawn_key] = e
    end
    run.enemies[#run.enemies + 1] = e
    run:Emit("EnemySpawned", { id = e.id, role = e.role, subtype = e.subtype, explodes_on_death = explosive,
        marker = e.marker, emoji = e.emoji, radius = e.radius, opportunity_tag = e.opportunity_tag, x = x, y = y,
        portal = portal, wave_id = e.wave_id, room_id = e.room_id, summoned_by = e.summoned_by,
        entity_id = e.entity_id, route_id = e.route_id, behavior = e.behavior, stage = e.stage, is_boss = e.is_boss })
    return e
end

---@param run table
---@param e table
function Combat.ApplySlow(run, e, amount, duration, source, suppliedContext)
    Reactions.Sync(run, e)
    if run.ended or e.alive == false or e.hp <= 0 or e.slowable == false or duration <= 0 or amount <= 0 then return false end
    -- Q18 原型：先全局50%封顶，再Boss半效；来源唯一身份，刷新同源而不是乘法。
    local reduction = math.min((run.config.reactions or {}).slow_cap or 0.5, math.max(0, amount))
    if boss(e) then reduction = reduction * 0.5 end
    local factor = 1 - reduction
    local sourceKey = tostring(source or "slow")
    local previous = e.slow_effects[sourceKey]
    e.slow_effects[sourceKey] = { factor = factor, amount = reduction, timer = duration,
        expires_at = run.clock + duration, source = sourceKey }
    local strongest = 1
    for _, status in pairs(e.slow_effects) do
        if status.timer > 0 then strongest = math.min(strongest, status.factor) end
    end
    e.slow_factor = strongest
    -- 连续光环每模拟步刷新逻辑，但只在首次/强度变化时发状态反馈，避免50Hz噪声。
    if not previous or previous.factor ~= factor then
        local context = Reactions.Context(run, suppliedContext or "slow", sourceKey)
        Reactions.Emit(run, "EnemySlowed", { id = e.id, factor = factor, duration = duration,
            amount = reduction, source = sourceKey }, context)
        Reactions.Emit(run, "StatusChanged", { id = e.id, target_id = e.entity_id, status = "slow", active = true,
            factor = strongest, source = sourceKey, expires_at = run.clock + duration }, context)
    end
    return true
end

-- 旧 projectile 的 slow 是速度factor；公共 API 使用减速amount，保持兼容但不可混用。
---@param run table
---@param e table
local function slow(run, e, strength, duration, source, context)
    return Combat.ApplySlow(run, e, 1 - strength, duration, source, context)
end

---@param run table
---@param e table
local function tickSlow(run, e, dt)
    local factor = 1
    e.slow_effects = e.slow_effects or {}
    e.active_statuses = e.slow_effects
    for id, status in pairs(e.slow_effects) do
        status.timer = math.max(0, status.timer - dt)
        if status.timer <= 0.00000001 then
            e.slow_effects[id] = nil
            run:Emit("StatusChanged", { id = e.id, target_id = e.entity_id, status = "slow", active = false, source = id })
        else factor = math.min(factor, status.factor) end
    end
    e.slow_factor = factor
end

-- 外围输出使用配置区域，不借用守军room_id；弹体提交/溅射再次过滤防跨区误伤。
---@param run table
local function inRegion(run, id, x, y)
    if type(run.map.IsInRegion) == "function" then return run.map:IsInRegion(id, x, y) end
    for _, region in ipairs(run.config.walkable_regions or {}) do
        if region.id == id then return x >= region.x1 and x <= region.x2 and y >= region.y1 and y <= region.y2 end
    end
    return false
end
---@param run table
---@param e table
local function legalEnemy(run, e, regionId)
    return e.alive and e.hp > 0 and e.damageable ~= false
        and (not regionId or ((e.behavior == "expedition" or Expansion.Enabled(run)) and inRegion(run, regionId, e.x, e.y)))
end
---@param run table
---@param tower table
local function towerRegion(run, tower)
    if tower.activation_region_id then return tower.activation_region_id end
    for _, slot in ipairs(run.config.build_slots or {}) do
        if slot.id == tower.slot_id then return slot.activation_region_id end
    end
end

---@param run table
---@param exclude table|nil
local function splash(run, x, y, radius, amount, source, exclude, frost, regionId)
    local context = Reactions.Context(run, source)
    local count = #run.enemies
    for i = 1, count do
        local e = run.enemies[i] --[[@as table]]
        if legalEnemy(run, e, regionId) and e ~= exclude and distance2(x, y, e.x, e.y) <= (radius + e.radius) ^ 2
            and visible(run, x, y, e.x, e.y) then
            Combat.DamageEnemy(run, e, amount, context)
            if frost and frost > 0 then slow(run, e, 1 - 0.1 * frost, value(run, "slow_duration"), "frost:" .. tostring(context.source_id), context) end
        end
    end
    effect(run, "blast", x, y, radius)
end

-- 线段与半径扩张圆的首交 t∈[0,1]；nil 为无交。
local function circleHit(ax, ay, bx, by, x, y, radius)
    local dx, dy, ox, oy = bx - ax, by - ay, ax - x, ay - y
    local c = ox * ox + oy * oy - radius * radius
    if c <= 0 then return 0 end
    local a = dx * dx + dy * dy
    if a <= 0.00000001 then return nil end
    local b = ox * dx + oy * dy
    local discriminant = b * b - a * c
    if discriminant < 0 then return nil end
    local t = (-b - math.sqrt(discriminant)) / a
    if t >= 0 and t <= 1 then return t end
end

---@param run table
---@return number, boolean
local function wallLimit(run, ax, ay, bx, by, radius)
    if not run.map:IsWalkable(ax, ay, radius) then return 0, true end
    if run.map:IsWalkable(bx, by, radius) and visible(run, ax, ay, bx, by, radius) then return 1, false end
    local low, high = 0, 1
    for _ = 1, 16 do
        local mid = (low + high) * 0.5
        local x, y = ax + (bx - ax) * mid, ay + (by - ay) * mid
        if run.map:IsWalkable(x, y, radius) and visible(run, ax, ay, x, y, radius) then low = mid else high = mid end
    end
    return low, true
end

-- 位移碰撞示意：P --方向--> E(圆) ---- ####墙/柱；沿同一条线扫掠停止，不走Map.Move滑墙。
-- 边界：重叠无方向拒绝；墙前部分移动成功且blocked=true；完全卡住拒绝；锚定从不移动。
---@param run table
---@param target table
local function displacementInfo(run, target, dx, dy, requested)
    local info = { ok = false, reason = "无合法目标", range = run.config.player.active_range or 4.5,
        dx = dx, dy = dy, displacement = 0, distance = 0, blocked = false }
    if not target then return info end
    info.target_id, info.x, info.y = target.entity_id or target.id or target.slot_id, target.x, target.y
    info.landing_x, info.landing_y = target.x, target.y
    if target.hp <= 0 or target.alive == false then info.reason = "目标已死亡"; return info end
    if target.anchored then info.reason = "固定，不能推动"; return info end
    if target.movable == false then info.reason = "目标不能位移"; return info end
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.000001 then info.reason = "重叠目标无施力方向"; return info end
    info.dx, info.dy = dx / length, dy / length
    local wanted = math.max(0, requested) / math.max(1, target.weight or 1)
    local bx, by = target.x + info.dx * wanted, target.y + info.dy * wanted
    local limit, blocked = wallLimit(run, target.x, target.y, bx, by, target.radius or 0)
    local confinedRoom = target.room_id or (target == run.player and run.room_encounter and run.room_encounter.room_id)
    if confinedRoom then
        -- 守军位移仍在房内，符合既有守房身份；爆炸伤害可跨房但不改wave归属。
        local low, high = 0, limit
        if roomAt(run, bx, by) ~= confinedRoom then
            for _ = 1, 16 do
                local t = (low + high) * 0.5
                if roomAt(run, target.x + (bx - target.x) * t, target.y + (by - target.y) * t) == confinedRoom then low = t else high = t end
            end
            limit, blocked = low, true
        end
    end
    info.landing_x, info.landing_y = target.x + (bx - target.x) * limit, target.y + (by - target.y) * limit
    info.displacement, info.distance, info.blocked = wanted * limit, wanted * limit, blocked
    info.ok = info.displacement > 0.0001
    info.reason = info.ok and (blocked and "碰墙停止" or "位移成功") or "墙柱或边界阻挡"
    return info
end

-- 纯查询：不得Sync、Emit、分配root或变更状态，Board/测试可每帧观察而不影响回放。
---@param run table
function Combat.ActiveTarget(run)
    local p = run.player --[[@as table]]
    local range = run.config.player.active_range or run.config.player.active_radius or 4.5
    ---@type table?
    local best = nil
    ---@type table?
    local bestInfo = nil
    ---@type string?
    local rejected = nil
    -- pulse保留旧技能ID但只增距离，不再加伤；此项为Q16临时升级，不改变起始3格。
    local requested = (run.config.player.active_distance or 3) + skill(run, p, "pulse") * 0.4
    -- 距离先排，精确LOS/施力扫掠只校验到第一个合法目标。
    -- 原选择规则仍是最近合法目标、等距按id；不再给80个候选各做16轮墙查询。
    local candidates = {}
    for index, enemy in ipairs(run.enemies) do
        local d = distance2(p.x, p.y, enemy.x, enemy.y)
        if enemy.alive and enemy.hp > 0 and enemy.damageable ~= false and d <= range * range then
            candidates[#candidates + 1] = { enemy = enemy, distance = d, index = index }
        end
    end
    table.sort(candidates, function(a, b)
        return a.distance < b.distance or (a.distance == b.distance and a.enemy.id < b.enemy.id)
    end)
    local rejectedIndex = 0
    for _, entry in ipairs(candidates) do
        local enemy = entry.enemy
        if visible(run, p.x, p.y, enemy.x, enemy.y) then
            local dx, dy, distance = direction(p.x, p.y, enemy.x, enemy.y)
            local candidate = displacementInfo(run, enemy, dx, dy, requested)
            if candidate.ok then
                candidate.range, candidate.target_distance, candidate.distance = range, distance, distance
                best, bestInfo = enemy, candidate
                break
            elseif entry.index > rejectedIndex then
                rejected, rejectedIndex = candidate.reason, entry.index
            end
        end
    end
    if not best or not bestInfo then return nil, { ok = false, reason = rejected or "射程内没有合法目标", range = range } end
    if p.active_cd > 0 then bestInfo.ok, bestInfo.reason = false, "技能尚未冷却" end
    return best, bestInfo
end

---@param run table
---@param target table
function Combat.Displace(run, target, dx, dy, distance, suppliedContext)
    if run.ended or run.causal_queue_closed or not target then return false, { ok = false, reason = "本局已结束或目标不存在" } end
    local context = Reactions.Context(run, suppliedContext or "displacement")
    if context.run_id ~= run.run_id then return false, { ok = false, reason = "事件不属于本局" } end
    Reactions.Sync(run, target)
    local info = displacementInfo(run, target, dx, dy, distance)
    if not info.ok then
        Reactions.Emit(run, "DisplacementRejected", info, context)
        return false, info
    end
    local oldX, oldY = target.x, target.y
    target.x, target.y = info.landing_x, info.landing_y
    target.path, target.path_index, target.path_timer, target.stuck_timer = {}, 1, 0, 0
    target.recovery_failure_logged = false
    target.charge_timer, target.warning_timer, target.warning_kind, target.charge_context = 0, 0, nil, nil
    Reactions.Sync(run, target)
    info.old_x, info.old_y, info.x, info.y = oldX, oldY, target.x, target.y
    local eventId = Reactions.Emit(run, "Displaced", info, context)
    -- 后续伤害读取实际位移的因果root，而不是把推后击杀错误记为无关新动作。
    target.last_displacement = { root_action_id = context.root_action_id, event_id = eventId,
        source_id = context.source_id, at = run.clock }
    Reactions.Record(run, context, { pushed = 1, x = target.x, y = target.y, target_id = target.entity_id,
        event_id = eventId, fact = info.reason })
    effect(run, "displacement", oldX, oldY, info.displacement, 0.25)
    return true, info
end

---@param run table
---@return boolean activated
function Combat.Active(run)
    local p = run.player --[[@as table]]
    if stopped(run) then return false end
    local target, info = Combat.ActiveTarget(run)
    if not target or not info.ok then run:Emit("ActiveRejected", info); return false end
    local context = Reactions.Context(run, "active", p.entity_id)
    local dx, dy = direction(p.x, p.y, target.x, target.y)
    local ok, result = Combat.Displace(run, target, dx, dy,
        (run.config.player.active_distance or 3) + skill(run, p, "pulse") * 0.4, context)
    if not ok then run:Emit("ActiveRejected", result); return false end
    p.active_cd = run.config.player.active_cooldown * math.max(0.1, 1 - skill(run, p, "relay") * 0.15)
    Reactions.Emit(run, "Active", { x = p.x, y = p.y, radius = run.config.player.active_range or 4.5,
        damage = 0, cooldown = p.active_cd, target_id = target.entity_id, target_x = target.x, target_y = target.y,
        landing_x = target.x, landing_y = target.y, dx = dx, dy = dy, displacement = result.displacement,
        blocked = result.blocked }, context)
    return true
end

---@param run table
---@param target table
function Combat.ApplyEffect(run, target, payload, suppliedContext)
    local context = Reactions.Context(run, suppliedContext or "effect")
    local result = { ok = false, displaced = false, slowed = false, damaged = false, root_action_id = context.root_action_id }
    if run.ended or run.causal_queue_closed or context.run_id ~= run.run_id or not target then return result end
    if context.event_key then
        local key = tostring(context.event_key) .. ":" .. tostring(target.entity_id or target.id or target.slot_id)
        if run.effect_ledger[key] then result.reason = "duplicate_effect"; return result end
        run.effect_ledger[key] = true
    end
    local displacement = payload.displacement
    if displacement then
        result.displaced, result.displacement = Combat.Displace(run, target, displacement.dx or 0,
            displacement.dy or 0, displacement.distance or 0, context)
    end
    if payload.slow then
        result.slowed = Combat.ApplySlow(run, target, payload.slow.amount or 0,
            payload.slow.duration or 2, payload.slow.source or context.source_id, context)
    end
    if payload.damage and payload.damage > 0 then result.damaged = Combat.Damage(run, target, payload.damage, context) end
    result.ok = result.displaced or result.slowed or result.damaged
    return result
end

-- 同空间策略给爆炸渲染/规则查询：圆边触及算覆盖，LOS被墙柱/锁门阻挡。
---@param run table
---@param target table
function Combat.ExplosionContains(run, x, y, radius, target)
    return target.hp > 0 and target.alive ~= false and target.damageable ~= false
        and distance2(x, y, target.x, target.y) <= (radius + (target.radius or 0)) ^ 2
        and visible(run, x, y, target.x, target.y)
end

---@param run table
function Combat.ProcessReactions(run)
    return Reactions.Process(run, function(event, context)
        if Expansion.Enabled(run) and run.trial_started then context.core_budget_room = event.room_id or run.map:RoomAt(event.x, event.y) end
        local victims = {}
        for _, enemy in ipairs(run.enemies) do if Combat.ExplosionContains(run, event.x, event.y, event.radius, enemy) then victims[#victims + 1] = enemy end end
        for _, target in ipairs({ run.player, run.core }) do
            if Combat.ExplosionContains(run, event.x, event.y, event.radius, target) then victims[#victims + 1] = target end
        end
        for _, tower in ipairs(run.towers) do if Combat.ExplosionContains(run, event.x, event.y, event.radius, tower) then victims[#victims + 1] = tower end end
        table.sort(victims, function(a, b) return tostring(a.entity_id or a.id or a.slot_id) < tostring(b.entity_id or b.id or b.slot_id) end)
        local hits, kills, coreDamage, playerDamage, towerDamage = 0, 0, 0, 0, 0
        for _, target in ipairs(victims) do
            local before = target.hp
            if Combat.Damage(run, target, event.damage, context) then
                hits = hits + 1
                if target.hp <= 0 then kills = kills + 1 end
                local actual = before - target.hp
                if target == run.core then coreDamage = coreDamage + actual
                elseif target == run.player then playerDamage = playerDamage + actual
                elseif target.slot_id then towerDamage = towerDamage + actual end
            end
        end
        local explosionId = Reactions.Emit(run, "Explosion", { x = event.x, y = event.y, radius = event.radius,
            damage = event.damage, hits = hits, kills = kills, core_damage = coreDamage, player_damage = playerDamage,
            tower_damage = towerDamage, wave_id = event.wave_id, room_id = event.room_id, source_id = event.source_id }, context)
        Reactions.Record(run, context, { explosions = 1, x = event.x, y = event.y, event_id = explosionId,
            fact = "爆炸实际命中" .. tostring(hits) .. "个对象" })
        effect(run, "death_explosion", event.x, event.y, event.radius, 0.35)
    end)
end

---@param run table
---@param origin table
---@param target table
---@param data table
local function shoot(run, origin, target, data)
    local dx, dy, length = direction(origin.x, origin.y, target.x, target.y)
    if length == 0 then dx = 1 end
    local context = Reactions.Context(run, data.source, origin.entity_id or origin.id or origin.slot_id)
    context.core_budget_room = Expansion.SourceRoom(run, origin)
    local projectile = { id = nextId(run), x = origin.x, y = origin.y,
        dx = dx, dy = dy, speed = data.speed, radius = value(run, "bullet_radius"),
        remaining = data.range, damage = data.damage, core_damage = data.core_damage or data.damage,
        team = data.team, source = data.source,
        pierce = data.pierce or 0, blast = data.blast or 0, frost = data.frost or 0,
        slow = data.slow, slow_duration = data.slow_duration, splash = data.splash,
        activation_region_id = data.activation_region_id, hit_ids = {}, alive = true,
        portal = origin.origin_portal, room_id = origin.room_id, source_id = origin.entity_id or origin.id or origin.slot_id,
        root_action_id = context.root_action_id, context = context } -- 外观由Board按阵营/真实弹体属性派生。
    run.projectiles[#run.projectiles + 1] = projectile
    projectile.parent_event_id = Reactions.Emit(run, "Shoot", { id = projectile.id, x = origin.x, y = origin.y,
        target_x = target.x, target_y = target.y, source = data.source, team = data.team }, context)
    context.parent_event_id = projectile.parent_event_id
end

---@param run table
local function nearest(run, x, y, range, policy, regionId)
    local best, bestDistance, bestPriority = nil, range * range, math.huge
    for i = 1, #run.enemies do
        local e = run.enemies[i] --[[@as table]]
        local d = distance2(x, y, e.x, e.y)
        local priority = policy == "priority"
        local rank = priority and ((e.behavior == "expedition" or e.role == "elite") and 0 or 1) or 0
        if legalEnemy(run, e, regionId) and d <= range * range and visible(run, x, y, e.x, e.y) then
            if not best or rank < bestPriority or (rank == bestPriority and (d < bestDistance or (d == bestDistance and e.id < best.id))) then
                best, bestDistance, bestPriority = e, d, rank
            end
        end
    end
    return best
end

---@param run table
local function playerAttack(run)
    local p = run.player --[[@as table]]
    if p.attack_cd > 0 then return end
    local target = nearest(run, p.x, p.y, p.range)
    if not target then return end
    p.attack_cd = p.interval * math.max(0.1, 1 - skill(run, p, "rapid") * 0.1)
    shoot(run, p, target, { team = "player", source = "player", range = p.range,
        speed = run.config.player.bullet_speed, damage = p.damage * (1 + skill(run, p, "power") * 0.25),
        pierce = skill(run, p, "pierce"), blast = skill(run, p, "blast"), frost = skill(run, p, "frost") })
end

---@param run table
---@param b table
---@param e table
local function projectileHit(run, b, e, x, y)
    Combat.DamageEnemy(run, e, b.damage, b.context or b.source)
    if b.frost > 0 then slow(run, e, 1 - 0.1 * b.frost, value(run, "slow_duration"), "frost:" .. tostring(b.source_id or "player"), b.context) end
    if b.slow then slow(run, e, b.slow, b.slow_duration or value(run, "slow_duration"), "tower:" .. tostring(b.source_id), b.context) end
    local radius = b.splash or (b.blast > 0 and (1.2 + b.blast * 0.3) or 0)
    if radius > 0 then
        local amount = b.splash and b.damage or b.damage * (0.35 + b.blast * 0.1)
        splash(run, x, y, radius, amount, b.context or b.source, e, b.frost, b.activation_region_id)
    end
end

---@param run table
---@param b table
local function stepProjectile(run, b, dt)
    local distance = math.min(b.remaining, b.speed * dt)
    local ax, ay, bx, by = b.x, b.y, b.x + b.dx * distance, b.y + b.dy * distance
    ---@type number, boolean
    local limit, wall = wallLimit(run, ax, ay, bx, by, b.radius)
    -- 守军弹体不越房间边界，离房即失效。
    if b.room_id and roomAt(run, bx, by) ~= b.room_id then
        local low, high = 0, limit
        for _ = 1, 12 do
            local mid = (low + high) * 0.5
            if roomAt(run, ax + (bx - ax) * mid, ay + (by - ay) * mid) == b.room_id then low = mid else high = mid end
        end
        limit, wall = low, true
    end
    if b.team == "player" then
        local hits = {}
        for i = 1, #run.enemies do
            local e = run.enemies[i] --[[@as table]]
            if legalEnemy(run, e, b.activation_region_id) and not b.hit_ids[e.id] then
                local t = circleHit(ax, ay, bx, by, e.x, e.y, e.radius + b.radius)
                if t and (not wall and t <= limit or t < limit - 0.00001)
                    and visible(run, ax, ay, e.x, e.y) then hits[#hits + 1] = { t = t, e = e } end
            end
        end
        table.sort(hits, function(a, c) return a.t < c.t or (a.t == c.t and a.e.id < c.e.id) end)
        for _, hit in ipairs(hits) do
            local e = hit.e --[[@as table]]
            if e.alive then
                b.hit_ids[e.id] = true
                b.x, b.y = ax + (bx - ax) * hit.t, ay + (by - ay) * hit.t
                projectileHit(run, b, e, b.x, b.y)
                if b.pierce <= 0 then b.alive = false; return end
                b.pierce = b.pierce - 1
            end
        end
    else
        local candidates = { { target = run.player, kind = "player", radius = run.player.radius } }
        if not b.room_id then
            candidates[#candidates + 1] = { target = run.core, kind = "core", radius = run.core.radius }
            for _, tower in ipairs(run.towers) do
                if tower.hp > 0 then candidates[#candidates + 1] = { target = tower, kind = "tower", radius = value(run, "tower_radius") } end
            end
        end
        local best, bestTime = nil, limit + 0.00001
        for _, c in ipairs(candidates) do
            local target = c.target --[[@as table]]
            local t = circleHit(ax, ay, bx, by, target.x, target.y, c.radius + b.radius)
            if target.hp > 0 and t and t < bestTime and (not wall or t < limit - 0.00001) then best, bestTime = c, t end
        end
        if best then
            damageTarget(run, best.target, best.kind == "core" and b.core_damage or b.damage, best.kind, b.portal, b.context)
            b.x, b.y, b.alive = ax + (bx - ax) * bestTime, ay + (by - ay) * bestTime, false
            return
        end
    end
    b.x, b.y = ax + (bx - ax) * limit, ay + (by - ay) * limit
    b.remaining = b.remaining - distance * limit
    if wall or b.remaining <= 0 then b.alive = false end
end

---@param run table
---@param e table
local function repath(run, e, tx, ty)
    e.path = run.map:Path(e.x, e.y, tx, ty, e.radius) or {}
    e.path_index, e.path_timer, e.path_x, e.path_y = 1, value(run, "path_interval"), tx, ty
    e.path_revision = run.map.revision
    return #e.path > 0
end

---@param run table
---@param e table
local function recover(run, e, tx, ty)
    if e.behavior == "expedition" then Expedition.Recover(run, e, tx, ty, repath); return end
    if repath(run, e, tx, ty) then
        e.stuck_timer, e.recovery_failure_logged = 0, false
        run:Emit("StuckRepath", { id = e.id, target_id = e.entity_id, portal = e.origin_portal,
            wave_id = e.wave_id, room_id = e.room_id, hp = e.hp, x = e.x, y = e.y,
            target_x = tx, target_y = ty, path_points = #e.path, ok = true })
        return
    end
    local x, y = portalPoint(run, e.origin_portal)
    if e.room_id then
        local room = findRoom(run, e.room_id)
        if room then x, y = room.x, room.y end
    end
    if x and run.map:IsWalkable(x, y, e.radius) then
        local oldX, oldY = e.x, e.y
        e.x, e.y, e.stuck_timer, e.path_timer = x, y, 0, 0
        e.path, e.path_index, e.warning_timer, e.charge_timer = {}, 1, 0, 0
        e.warning_kind, e.charge_context, e.recovery_failure_logged = nil, nil, false
        run:Emit("StuckRecovered", { id = e.id, portal = e.origin_portal, wave_id = e.wave_id,
            room_id = e.room_id, hp = e.hp, x = x, y = y, old_x = oldX, old_y = oldY })
    elseif not e.recovery_failure_logged then
        -- 只记一次连续停滞失败；原有重寻路/回迁尝试仍照常，不按表现日志节流改机制。
        e.recovery_failure_logged = true
        run:Emit("RecoveryFailed", { id = e.id, target_id = e.entity_id, portal = e.origin_portal,
            wave_id = e.wave_id, room_id = e.room_id, hp = e.hp, x = e.x, y = e.y,
            recovery_x = x, recovery_y = y, reason = "no_legal_recovery_point", ok = false })
    end
end

---@param run table
---@param e table
local function moveEnemy(run, e, tx, ty, speed, dt)
    local x, y = tx, ty
    if not visible(run, e.x, e.y, tx, ty, e.radius) then
        -- 多边形图的路径跨房间中心；周期性从当前位置重算会把刚离开中心的单位
        -- 重新引回中心，形成往返。固定目标沿原路径前进，只有目标或几何变化才重算。
        if not e.path_x or #e.path == 0 or distance2(tx, ty, e.path_x, e.path_y) > 1
            or run.config.polygon_expansion and e.path_revision ~= run.map.revision
            or not run.config.polygon_expansion and e.path_timer <= 0 then repath(run, e, tx, ty) end
        local point = e.path[e.path_index] --[[@as table?]]
        while point and distance2(e.x, e.y, point.x, point.y) < 0.12 ^ 2 do
            e.path_index = e.path_index + 1
            point = e.path[e.path_index]
        end
        if point then x, y = point.x, point.y end
    else e.path = {}; e.path_index = 1 end
    local dx, dy, length = direction(e.x, e.y, x, y)
    if length <= 0.05 then e.stuck_timer, e.recovery_failure_logged = 0, false; return end
    local step = math.min(length, speed * e.slow_factor * dt)
    local nx, ny = run.map:Move(e.x, e.y, dx * step, dy * step, e.radius)
    if e.room_id and roomAt(run, nx, ny) ~= e.room_id then nx, ny = e.x, e.y end
    local moved = math.sqrt(distance2(e.x, e.y, nx, ny))
    e.x, e.y = nx, ny
    if moved < step * 0.15 then e.stuck_timer = e.stuck_timer + dt
    else e.stuck_timer, e.recovery_failure_logged = 0, false end
    if e.stuck_timer > value(run, "stuck_duration") then recover(run, e, tx, ty) end
end

---@param run table
---@param e table
---@param target table
local function touching(run, e, target, radius)
    return distance2(e.x, e.y, target.x, target.y) <= (e.radius + radius + value(run, "melee_reach")) ^ 2
        and visible(run, e.x, e.y, target.x, target.y)
end

---@param run table
---@param e table
local function blockingTarget(run, e, elite)
    local core = run.core --[[@as table]]
    local dx, dy = direction(e.x, e.y, core.x, core.y)
    local best, bestDistance = nil, value(run, "blocker_range") ^ 2
    for _, tower in ipairs(run.towers) do
        local d = distance2(e.x, e.y, tower.x, tower.y)
        if tower.hp > 0 and d <= bestDistance and visible(run, e.x, e.y, tower.x, tower.y)
            and (elite or (tower.x - e.x) * dx + (tower.y - e.y) * dy > 0) then
            best, bestDistance = tower, d
        end
    end
    if best then return best, "tower", value(run, "tower_radius") end
    local p = run.player --[[@as table]]
    if not elite and p.hp > 0 and distance2(e.x, e.y, p.x, p.y) <= bestDistance
        and (p.x - e.x) * dx + (p.y - e.y) * dy > 0 and visible(run, e.x, e.y, p.x, p.y) then
        return p, "player", p.radius
    end
end

---@param run table
---@param e table
local function enemyAttack(run, e, data)
    local context = Reactions.Context(run, { source = "enemy_attack", source_id = e.entity_id,
        portal = e.origin_portal, core_budget_room = Expansion.SourceRoom(run, e) })
    data.id, data.portal, data.wave_id, data.room_id = e.id, e.origin_portal, e.wave_id, e.room_id
    context.parent_event_id = Reactions.Emit(run, "EnemyAttack", data, context)
    return context
end

---@param run table
---@param e table
---@param target table
local function melee(run, e, target, kind, def)
    if e.attack_cd > 0 then return end
    e.attack_cd = def.interval
    local amount = kind == "core" and (def.core_damage or def.damage) or def.damage
    local context = enemyAttack(run, e, { kind = kind, attack_kind = "melee", x = e.x, y = e.y,
        amount = amount, target_id = target.entity_id, target_x = target.x, target_y = target.y })
    damageTarget(run, target, amount, kind, e.origin_portal, context)
end

---@param run table
---@param e table
---@param target table
local function warn(run, e, target, kind, radius)
    local duration = math.max(0.7, run.config.attack_warning)
    e.warning_kind, e.warning_timer = kind, duration
    e.warning_x, e.warning_y, e.warning_radius = target.x, target.y, radius
    e.charge_dx, e.charge_dy = direction(e.x, e.y, target.x, target.y)
    effect(run, kind .. "_warning", target.x, target.y, radius, duration)
    run:Emit("AttackWarning", { id = e.id, kind = kind, x = target.x, y = target.y,
        origin_x = e.x, origin_y = e.y, radius = radius, duration = duration,
        dx = e.charge_dx, dy = e.charge_dy })
end

---@param run table
---@param e table
local function areaAttack(run, e, def)
    local x, y, radius = e.warning_x, e.warning_y, e.warning_radius
    local context = enemyAttack(run, e, { kind = "area", attack_kind = "area", x = x, y = y,
        origin_x = e.x, origin_y = e.y, radius = radius, amount = def.damage })
    local targets = { { target = run.player, kind = "player", radius = run.player.radius },
        { target = run.core, kind = "core", radius = run.core.radius } }
    for _, tower in ipairs(run.towers) do targets[#targets + 1] = { target = tower, kind = "tower", radius = value(run, "tower_radius") } end
    if e.behavior == "expedition" and e.stage ~= "FINAL_ASSAULT" then
        local stop = e.expedition_route.stops[e.route_index]
        local legal = {}
        for _, candidate in ipairs(targets) do
            if e.stage == "ROOM_ENGAGED" and candidate.kind ~= "core" and stop
                and roomAt(run, e.x, e.y) == stop.room_id
                and roomAt(run, candidate.target.x, candidate.target.y) == stop.room_id then legal[#legal + 1] = candidate end
        end
        targets = legal
    end
    for _, c in ipairs(targets) do
        local target = c.target --[[@as table]]
        if target.hp > 0 and distance2(x, y, target.x, target.y) <= (radius + c.radius) ^ 2
            and visible(run, e.x, e.y, x, y) and visible(run, x, y, target.x, target.y) then
            damageTarget(run, target, def.damage, c.kind, e.origin_portal, context)
        end
    end
    effect(run, "enemy_area", x, y, radius)
end

---@param run table
---@param e table
local function charge(run, e, def, dt)
    -- 冲锋启动记录一次动作，后续扫掠命中只引用该事件；兼容已处于冲锋的旧实体。
    if not e.charge_context then
        e.charge_context = enemyAttack(run, e, { kind = "charge", attack_kind = "charge", x = e.x, y = e.y,
            dx = e.charge_dx, dy = e.charge_dy, radius = e.radius, amount = def.damage })
    end
    local time = math.min(dt, e.charge_timer)
    local travel = value(run, "charge_speed") * e.slow_factor * time
    local ax, ay, bx, by = e.x, e.y, e.x + e.charge_dx * travel, e.y + e.charge_dy * travel
    local limit, wall = wallLimit(run, ax, ay, bx, by, e.radius)
    local targets = { { target = run.player, kind = "player", radius = run.player.radius } }
    if not e.room_id then
        targets[#targets + 1] = { target = run.core, kind = "core", radius = run.core.radius }
        for _, t in ipairs(run.towers) do
            if t.hp > 0 then targets[#targets + 1] = { target = t, kind = "tower", radius = value(run, "tower_radius") } end
        end
    end
    if e.room_id and roomAt(run, bx, by) ~= e.room_id then limit, wall = 0, true end
    local best, bestTime = nil, limit + 0.00001
    for _, c in ipairs(targets) do
        local target = c.target --[[@as table]]
        local t = circleHit(ax, ay, bx, by, target.x, target.y, e.radius + c.radius)
        if target.hp > 0 and t and t < bestTime and (not wall or t < limit - 0.00001) then best, bestTime = c, t end
    end
    if best then
        damageTarget(run, best.target, def.damage, best.kind, e.origin_portal, e.charge_context)
        e.x, e.y, e.charge_timer = ax + (bx - ax) * bestTime, ay + (by - ay) * bestTime, 0
    else
        e.x, e.y = ax + (bx - ax) * limit, ay + (by - ay) * limit
        e.charge_timer = wall and 0 or math.max(0, e.charge_timer - dt)
    end
    if e.charge_timer <= 0 then e.charge_context = nil end
    e.stuck_timer, e.recovery_failure_logged = 0, false
end

---@param run table
---@param e table
local function summons(run, e, dt)
    e.summon_timer = e.summon_timer - dt
    if e.summon_rounds < math.min(3, value(run, "summon_rounds")) and e.summon_timer <= 0 then
        e.summon_rounds = e.summon_rounds + 1
        e.summon_pending = e.summon_pending + math.min(3, value(run, "summon_count"))
        e.summon_timer = value(run, "summon_interval")
    end
    while e.alive and e.summon_pending > 0 and run:AliveCount() < run.config.alive_soft_limit do
        local unit = Combat.Spawn(run, { role = "advance", portal = e.origin_portal,
            wave_id = e.wave_id, summoned_by = e.id })
        if not unit then break end
        e.summon_pending = e.summon_pending - 1
        run:Emit("BossSummoned", { id = e.id, wave_id = e.wave_id, portal = e.origin_portal,
            remaining = e.summon_pending, round = e.summon_rounds })
    end
end

-- 巡行只攻击同站点合法玩家/设施，不追逐出房、不对途经核心输出。
---@param run table
---@param e table
local function expeditionAttack(run, e, roomId, dt)
    local def = run.config.enemies[e.role]
    if e.warning_kind then
        e.warning_timer = math.max(0, e.warning_timer - dt)
        if e.warning_timer <= 0 then areaAttack(run, e, def); e.warning_kind = nil end
        return
    end
    local candidates = { { target = run.player, kind = "player", radius = run.player.radius } }
    for _, tower in ipairs(run.towers) do candidates[#candidates + 1] = { target = tower, kind = "tower", radius = value(run, "tower_radius") } end
    table.sort(candidates, function(a, b)
        local da, db = distance2(e.x, e.y, a.target.x, a.target.y), distance2(e.x, e.y, b.target.x, b.target.y)
        return da < db or (da == db and tostring(a.target.entity_id) < tostring(b.target.entity_id))
    end)
    for _, candidate in ipairs(candidates) do
        local target = candidate.target
        if target.hp > 0 and target.alive ~= false and roomAt(run, target.x, target.y) == roomId
            and visible(run, e.x, e.y, target.x, target.y) then
            if e.role == "expedition_ranged" and e.attack_cd <= 0 then
                if distance2(e.x, e.y, target.x, target.y) > value(run, "ranged_range")^2 then return end
                e.attack_cd = def.interval
                shoot(run, e, target, { team = "enemy", source = "ranged", range = value(run, "ranged_range"),
                    damage = def.damage, interval = def.interval, speed = value(run, "enemy_bullet_speed") })
                return
            end
            if (not Expansion.Enabled(run) or e.role == "expedition_elite") and e.area_cd <= 0 and distance2(e.x, e.y, target.x, target.y) <= value(run, "boss_area_range")^2 then
                e.area_cd = value(run, "boss_area_interval")
                warn(run, e, target, "area", value(run, "boss_area_radius")); return
            end
            if touching(run, e, target, candidate.radius) then melee(run, e, target, candidate.kind, def); return end
        end
    end
end
local EXPEDITION_CALLBACKS = {
    move = function(run, e, x, y, dt) moveEnemy(run, e, x, y, run.config.enemies[e.role].speed, dt) end,
    attack = expeditionAttack,
}

---@param run table
---@param e table
local function stepEnemy(run, e, dt)
    local def = run.config.enemies[e.role] --[[@as table]]
    tickSlow(run, e, dt)
    e.attack_cd = math.max(0, e.attack_cd - dt)
    e.path_timer, e.charge_cd, e.area_cd = e.path_timer - dt, e.charge_cd - dt, e.area_cd - dt
    if e.behavior == "expedition" and Expedition.Step(run, e, dt, EXPEDITION_CALLBACKS) then return end
    if boss(e) and not e.room_id and not e.summon_disabled then summons(run, e, dt) end
    if e.warning_kind then
        e.warning_timer = math.max(0, e.warning_timer - dt)
        if e.warning_timer <= 0 then
            if e.warning_kind == "area" then areaAttack(run, e, def)
            else
                e.charge_timer = value(run, "charge_duration")
                e.charge_context = enemyAttack(run, e, { kind = "charge", attack_kind = "charge", x = e.x, y = e.y,
                    dx = e.charge_dx, dy = e.charge_dy, radius = e.radius, amount = def.damage })
            end
            e.warning_kind = nil
        end
        return
    end
    if e.charge_timer > 0 then charge(run, e, def, dt); return end
    local p, core = run.player, run.core
    local target, kind, radius = core, "core", core.radius
    if e.room_id then
        local room = findRoom(run, e.room_id)
        if roomAt(run, p.x, p.y) == e.room_id then target, kind, radius = p, "player", p.radius
        elseif room then
            moveEnemy(run, e, room.x, room.y, def.speed, dt); return
        else return end
    elseif e.role == "elite" or e.role == "expedition_elite" then
        local blocked, blockedKind, blockedRadius = blockingTarget(run, e, true)
        if blocked then target, kind, radius = blocked, blockedKind, blockedRadius end
    elseif touching(run, e, core, core.radius) then
        -- 接近核心时不得被远处玩家拖走；精英仍优先附近设施。
        target, kind, radius = core, "core", core.radius
    elseif (e.role == "ranged" or e.role == "expedition_ranged") and e.harass_timer < value(run, "harass_duration")
        and distance2(e.x, e.y, p.x, p.y) <= value(run, "ranged_range") ^ 2
        and visible(run, e.x, e.y, p.x, p.y) then
        e.harass_timer = math.min(value(run, "harass_duration"), e.harass_timer + dt)
        target, kind, radius = p, "player", p.radius
    elseif e.role == "advance" or e.role == "expedition_advance" then
        local blocked, blockedKind, blockedRadius = blockingTarget(run, e, false)
        if blocked then target, kind, radius = blocked, blockedKind, blockedRadius end
    end
    if boss(e) and e.area_cd <= 0 and distance2(e.x, e.y, target.x, target.y) <= value(run, "boss_area_range") ^ 2
        and visible(run, e.x, e.y, target.x, target.y) then
        e.area_cd = value(run, "boss_area_interval")
        warn(run, e, target, "area", value(run, "boss_area_radius")); return
    end
    if (e.role == "charger" or e.role == "siege") and e.charge_cd <= 0
        and distance2(e.x, e.y, target.x, target.y) <= value(run, "charge_range") ^ 2
        and visible(run, e.x, e.y, target.x, target.y) then
        e.charge_cd = e.role == "siege" and value(run, "siege_charge_interval") or def.interval
        e.attack_cd = math.max(e.attack_cd, def.interval)
        warn(run, e, target, "charge", e.radius); return
    end
    if (e.role == "ranged" or e.role == "expedition_ranged") and kind == "player" and distance2(e.x, e.y, p.x, p.y) <= value(run, "ranged_range") ^ 2 then
        if e.attack_cd <= 0 then
            e.attack_cd = def.interval
            shoot(run, e, p, { team = "enemy", source = "ranged", range = value(run, "ranged_range"),
                speed = value(run, "enemy_bullet_speed"), damage = def.damage, core_damage = def.core_damage })
        end
        return
    end
    if touching(run, e, target, radius) then
        melee(run, e, target, kind, def); e.stuck_timer, e.recovery_failure_logged = 0, false
    else moveEnemy(run, e, target.x, target.y, def.speed, dt) end
end

---@param run table
---@param tower table
function Combat.TowerRange(run, tower)
    local attributes = TowerModules.Attributes(run, tower)
    return attributes and attributes.range or 0
end

---@param run table
local function towers(run, dt)
    for _, tower in ipairs(run.towers) do
        if tower.hp > 0 then
            Reactions.Sync(run, tower)
            tower.attack_cd = math.max(0, tower.attack_cd - dt) -- 未激活照常冷却，不刷新耐久/模块。
            local attributes = TowerModules.Attributes(run, tower)
            local regionId = towerRegion(run, tower)
            local active = not regionId or Expansion.Enabled(run)
            if regionId and not Expansion.Enabled(run) then
                for _, enemy in ipairs(run.enemies) do
                    if enemy.alive and enemy.hp > 0 and enemy.behavior == "expedition" and inRegion(run, regionId, enemy.x, enemy.y) then active = true; break end
                end
            end
            tower.defense_active = active
            tower.aura_range = attributes and attributes.range or 0
            if attributes and active then
                local range = attributes.range
                if tower.type == "slow" or Expansion.Enabled(run) and attributes.slow_amount > 0 then
                    for _, enemy in ipairs(run.enemies) do
                        if legalEnemy(run, enemy, regionId) and distance2(tower.x, tower.y, enemy.x, enemy.y) <= range * range
                            and visible(run, tower.x, tower.y, enemy.x, enemy.y) then
                            Combat.ApplySlow(run, enemy, attributes.slow_amount or 0, attributes.slow_duration or 2,
                                "tower:" .. tostring(tower.entity_id))
                        end
                    end
                end
                if Expansion.Enabled(run) and attributes.repair > 0 and tower.attack_cd <= 0 then
                    local targets = { run.core }
                    for _, facility in ipairs(run.towers) do targets[#targets + 1] = facility end
                    for _, target in ipairs(targets) do
                        if target.hp > 0 and target.hp < target.max_hp and distance2(tower.x, tower.y, target.x, target.y) <= range^2 and
                            visible(run, tower.x, tower.y, target.x, target.y) then
                            local actual = math.min(attributes.repair, target.max_hp - target.hp)
                            target.hp = target.hp + actual
                            run:Emit("FacilityRepaired", { source_id = tower.id, target_id = target.id, amount = actual })
                        end
                    end
                    tower.attack_cd = attributes.interval
                end
                if Expansion.Enabled(run) and attributes.push > 0 and tower.attack_cd <= 0 then
                    local target = nearest(run, tower.x, tower.y, range, attributes.target_policy, regionId)
                    if target then
                        Combat.Displace(run, target, target.x - tower.x, target.y - tower.y, attributes.push,
                            Reactions.Context(run, "tower_repulsor", tower.id))
                        tower.attack_cd = attributes.interval
                    end
                end
                if tower.attack_cd <= 0 and attributes.damage > 0 then
                    local target = nearest(run, tower.x, tower.y, range, attributes.target_policy, regionId)
                    if target then
                        tower.attack_cd = attributes.interval
                        shoot(run, tower, target, { team = "player", source = "tower_" .. tower.type,
                            range = range, speed = run.config.player.bullet_speed, damage = attributes.damage,
                            pierce = attributes.pierce, splash = attributes.splash, activation_region_id = regionId })
                    end
                end
            end
        end
    end
end

---@param run table
function Combat.UpdateRooms(run, dt)
    if stopped(run) then return end
    if run.config.polygon_expansion then return require("defense.PolygonRooms").Update(run, Combat) end
    -- dt 故意不消费：这里只做生命周期，守军在 Update 中只模拟一次。
    local current = roomAt(run, run.player.x, run.player.y)
    for _, room in ipairs(run.rooms) do
        local accessible = room.accessible
        if accessible == nil then accessible = room.unlocked end
        if accessible and room.state == "unvisited" and current == room.id then
            room.state, room.guard_ids = "active", {}
            local profile = room.guard_profile
            if type(profile) ~= "table" then
                for _, def in ipairs(run.config.rooms) do if def.id == room.id then profile = def.guard_profile; break end end
            end
            local count = type(profile) == "table" and profile.count or (room.tier == 1 and 4 or 6)
            local roles = type(profile) == "table" and profile.roles
            for i = 1, count do
                local angle = (i - 1) * math.pi * 2 / count
                local x, y = room.x + math.cos(angle) * 2, room.y + math.sin(angle) * 2
                if not run.map:IsWalkable(x, y, run.config.enemies.advance.radius) or roomAt(run, x, y) ~= room.id then x, y = room.x, room.y end
                local role = roles and #roles > 0 and roles[(i - 1) % #roles + 1] or (i % 3 == 0 and "ranged" or "advance")
                local guard = Combat.Spawn(run, { role = role,
                    room_id = room.id, x = x, y = y })
                if type(guard) == "table" then room.guard_ids[#room.guard_ids + 1] = guard.id end
            end
            run:Emit("RoomActivated", { id = room.id, count = #room.guard_ids, tier = room.tier })
        end
        if room.state == "active" then
            local alive = false
            for _, e in ipairs(run.enemies) do if e.alive and e.room_id == room.id then alive = true; break end end
            if not alive and #room.guard_ids > 0 then
                room.state = "cleared"
                run:Emit("RoomCleared", { id = room.id, tier = room.tier })
                if run.config.room_graph then
                    RoomGraph.UpdateAccess(run)
                    run:Emit("DefenseSiteAvailable", { room_id = room.id, reason = "room_cleared" })
                else
                local unlock = room.unlock
                if not unlock then
                    for _, def in ipairs(run.config.rooms) do if def.id == room.id then unlock = def.unlock; break end end
                end
                for _, nextRoom in ipairs(run.rooms) do
                    if nextRoom.id == unlock then
                        nextRoom.unlocked = true
                        run.map:SetUnlocked(nextRoom.id, true)
                        run:Emit("RoomUnlocked", { id = nextRoom.id, prerequisite = room.id })
                    end
                end
                end
            end
        end
    end
end

---@param run table
function Combat.Pickup(run, dt)
    if stopped(run) then return end
    local p = run.player --[[@as table]]
    local radius = value(run, "pickup_radius") + skill(run, p, "mobility") * value(run, "pickup_mobility")
    for i = 1, #run.drops do
        local drop = run.drops[i] --[[@as table]]
        if drop.alive and distance2(p.x, p.y, drop.x, drop.y) <= (radius + (drop.radius or 0)) ^ 2
            and visible(run, p.x, p.y, drop.x, drop.y) then
            drop.alive = false -- 先消费，GrantExperience 可能打开暂停面板。
            local context = Reactions.Context(run, { source = "pickup", source_id = drop.source_id,
                root_action_id = drop.root_action_id, parent_event_id = drop.parent_event_id })
            if drop.kind == "gold" then run.currency = run.currency + drop.amount
            elseif drop.kind == "experience" then run:GrantExperience(drop.amount) end
            local pickupId = Reactions.Emit(run, "Pickup", { id = drop.id, kind = drop.kind, amount = drop.amount, x = drop.x, y = drop.y }, context)
            Reactions.Record(run, context, { gold = drop.kind == "gold" and drop.amount or 0,
                experience = drop.kind == "experience" and drop.amount or 0, event_id = pickupId })
            if run:IsPaused() then break end
        end
    end
    compact(run.drops)
end

---@param run table
---@param intent table|nil move_x/move_y（兼容 x/y），active=true 为单次主动请求。
function Combat.Update(run, dt, intent)
    if dt <= 0 or dt ~= dt or dt == math.huge or stopped(run) then return end
    intent = intent or {}
    local remaining = dt
    local active = intent.active
    while remaining > 0.0000001 and not stopped(run) do
        local step = math.min(remaining, math.max(0.001, run.config.max_step))
        remaining = math.max(0, remaining - step)
        local p = run.player --[[@as table]]
        p.attack_cd, p.active_cd = math.max(0, p.attack_cd - step), math.max(0, p.active_cd - step)
        tickSlow(run, p, step)
        if type(p.invulnerable) == "number" then p.invulnerable = math.max(0, p.invulnerable - step) end
        local dx, dy = intent.move_x or intent.x or 0, intent.move_y or intent.y or 0
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 1 then dx, dy = dx / length, dy / length end
        local speed = p.speed * (1 + skill(run, p, "mobility") * 0.12) * p.slow_factor
        local nx, ny = run.map:Move(p.x, p.y, dx * speed * step, dy * speed * step, p.radius)
        if not run.room_encounter or run.map:IsInRegion(run.room_encounter.room_id, nx, ny) then p.x, p.y = nx, ny end
        -- 老特效先计时；本步创建的预警获得完整 >=.7 秒寿命。
        for _, fx in ipairs(run.effects) do
            if fx.timer then fx.timer = math.max(0, fx.timer - step); if fx.timer <= 0 then fx.alive = false end end
        end
        local enemyCount = #run.enemies
        for i = 1, enemyCount do
            local e = run.enemies[i] --[[@as table]]
            if e.alive and (not run.config.polygon_expansion or not e.room_id or not run.active_rooms or run.active_rooms[e.room_id]) then stepEnemy(run, e, step) end
            if p.hp <= 0 or run.core.hp <= 0 or run.technical_error then break end
        end
        if p.hp <= 0 or run.core.hp <= 0 or run.technical_error then break end
        if active then Combat.Active(run); active = false end
        playerAttack(run)
        local projectileCount = #run.projectiles
        -- 玩家弹先于敌弹；设施本步发弹留到下一步，所有伤害只有实际弹体命中产生。
        for _, team in ipairs({ "player", "enemy" }) do
            for i = 1, projectileCount do
                local b = run.projectiles[i] --[[@as table]]
                if b.alive and b.team == team then stepProjectile(run, b, step) end
                if p.hp <= 0 or run.core.hp <= 0 then break end
            end
            if p.hp <= 0 or run.core.hp <= 0 then break end
        end
        if p.hp > 0 and run.core.hp > 0 then
            towers(run, step)
            Combat.UpdateRooms(run, 0)
            Combat.Pickup(run, step)
        end
        compact(run.enemies); compact(run.projectiles); compact(run.effects)
        Reactions.Sync(run, p)
        for _, enemy in ipairs(run.enemies) do Reactions.Sync(run, enemy) end
    end
    compact(run.enemies); compact(run.projectiles); compact(run.effects)
    Reactions.Sync(run, run.player)
    for _, enemy in ipairs(run.enemies) do Reactions.Sync(run, enemy) end
end

return Combat
