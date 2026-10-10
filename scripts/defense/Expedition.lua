-- v0.3 远征策略：仅由Combat/Run的模拟步驱动，没有第二时钟或私有伤害系统。
-- 碰撞/阶段设计：spawn -> entry -> engage [ROOM_ENGAGED] -> exit -> next entry -> core。
-- 所有箭头均调用公共Map.Path/Move（完整实体半径），绝不跨房传送。
-- 伤害判定：目标圆心RoomAt == 当前站点，且阶段为ROOM_ENGAGED；攻击者位置不计账。
-- 边界：击退出房仍消耗交战时钟，不重置站点/账本；同槽先8后8预算10 => 8/2；
-- 转场免伤，巡行hp>=1；所有站退出后解除限伤，死亡只走Combat公共提交。
local Expedition = {}
local Reactions = require("defense.Reactions")
local EPS = 1e-8

local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
---@param map table
local function roomAt(map, x, y)
    local room = map:RoomAt(x, y)
    return type(room) == "table" and room.id or room
end
---@param run table
---@param routeId string
local function routeFor(run, routeId)
    return (run.config.expedition_routes or {})[routeId]
end

-- 接受Run或Map，以及route_id或路线表；start为真实生成点，可省略（验站点间通行）。
-- 不开门、不修改配置；调用方应先OpenChallenge，再验证当下真实几何。
---@param owner table
---@param routeOrId table|string
---@param start? table
---@param radius? number
---@return boolean, string, table?
function Expedition.Validate(owner, routeOrId, start, radius)
    local map, config = owner.map or owner, owner.config
    if type(config) ~= "table" or type(map.Path) ~= "function" or type(map.RoomAt) ~= "function"
        or type(map.IsWalkable) ~= "function" then return false, "missing_map_contract" end
    local route = type(routeOrId) == "table" and routeOrId or (config.expedition_routes or {})[routeOrId]
    if type(route) ~= "table" or type(route.route_id) ~= "string" or route.route_id == ""
        or (type(routeOrId) == "string" and route.route_id ~= routeOrId) then return false, "invalid_route_id" end
    local def = (config.enemies or {}).expedition or {}
    radius = radius or def.radius
    if not finite(radius) or radius < 0 then return false, "invalid_route_radius" end
    if not finite(route.initial_hp) or route.initial_hp <= 1 then return false, "invalid_initial_hp" end
    if not finite(route.engage_duration) or route.engage_duration <= 0 then return false, "invalid_engage_duration" end
    if type(route.stops) ~= "table" or #route.stops == 0 or type(route.room_caps) ~= "table" then return false, "missing_route_stops" end
    local rooms, seen, capTotal = {}, {}, 0
    for _, room in ipairs(config.rooms or {}) do rooms[room.id] = true end
    local points = {}
    if start then points[#points + 1] = start end
    for index, stop in ipairs(route.stops) do
        if type(stop) ~= "table" or type(stop.room_id) ~= "string" or not rooms[stop.room_id] then return false, "invalid_stop_room" end
        local cap = route.room_caps[stop.room_id]
        if not finite(cap) or cap <= 0 then return false, "invalid_room_cap" end
        if not seen[stop.room_id] then capTotal = capTotal + cap; seen[stop.room_id] = true end
        for _, name in ipairs({ "entry", "engage", "exit" }) do
            local point = stop[name]
            if type(point) ~= "table" or not finite(point.x) or not finite(point.y)
                or not map:IsWalkable(point.x, point.y, radius) then
                return false, "invalid_" .. name .. "_point", { route_id = route.route_id, index = index, waypoint = copy(point) }
            end
            points[#points + 1] = point
        end
        if roomAt(map, stop.engage.x, stop.engage.y) ~= stop.room_id then return false, "engage_room_mismatch" end
    end
    for id in pairs(route.room_caps) do if not seen[id] then return false, "cap_for_unknown_stop" end end
    if capTotal >= route.initial_hp - EPS then return false, "room_caps_exhaust_initial_hp" end
    local final = route.final_target
    if type(final) ~= "table" or not finite(final.x) or not finite(final.y)
        or not map:IsWalkable(final.x, final.y, radius) then return false, "invalid_final_target" end
    local core = config.core_position
    if type(core) ~= "table" or math.abs(final.x - core.x) > EPS or math.abs(final.y - core.y) > EPS then
        return false, "final_target_not_core"
    end
    points[#points + 1] = final
    local length = 0
    for i, point in ipairs(points) do
        if not finite(point.x) or not finite(point.y) or not map:IsWalkable(point.x, point.y, radius) then return false, "invalid_start_point" end
        if i > 1 then
            local previous = points[i - 1]
            local path = map:Path(previous.x, previous.y, point.x, point.y, radius)
            if not path or #path < 2 then return false, "unreachable_waypoint", { route_id = route.route_id, waypoint = copy(point), index = i } end
            for j = 2, #path do
                local a, b = path[j - 1], path[j]
                if not map:LineOfSight(a.x, a.y, b.x, b.y, radius) then return false, "illegal_path_segment" end
                length = length + math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
            end
        end
    end
    return true, "", { route_id = route.route_id, path_length = length, cap_total = capTotal, stops = #route.stops }
end

---@param run table
---@param e? table
function Expedition.TechnicalError(run, e, reason, details)
    if run.technical_error then return false end
    local payload = copy(details or {})
    payload.reason, payload.route_id = reason, e and e.route_id or payload.route_id
    payload.entity_id, payload.id = e and e.entity_id, e and e.id
    payload.last_legal_position = e and { x = e.x, y = e.y } or payload.last_legal_position
    payload.waypoint = e and copy(e.expedition_waypoint) or payload.waypoint
    payload.recovery_attempts = e and e.recovery_attempts or 0
    payload.status = "UNDETERMINED"
    run.technical_error = copy(payload)
    if e then e.path_error = copy(payload) end
    run:Emit("ExpeditionPathError", payload)
    run:Pause("technical") -- 不End、不删除、不清波；主Run同样拦截technical_error。
    return false
end

---@param run table
---@param e table
local function refresh(run, e)
    e.current_room_id = roomAt(run.map, e.x, e.y)
end
---@param run table
---@param e table
local function stage(run, e, after, reason, suppliedContext)
    local context = suppliedContext or Reactions.Context(run, { source = "expedition", source_id = e.entity_id })
    local before = e.stage
    if before == after then return end
    e.stage, e.stage_elapsed = after, 0
    e.path, e.path_index, e.path_timer, e.stuck_timer = {}, 1, 0, 0
    e.warning_kind, e.warning_timer, e.charge_timer, e.charge_context = nil, 0, 0, nil
    refresh(run, e)
    local stop = e.expedition_route.stops[e.route_index]
    Reactions.Emit(run, "ExpeditionStageChanged", { entity_id = e.entity_id, id = e.id, wave_id = e.wave_id,
        route_id = e.route_id, index = e.route_index, route_index = e.route_index, before = before, after = after,
        stage = after, current_room_id = e.current_room_id, stop_room_id = stop and stop.room_id, reason = reason }, context)
end

---@param run table
---@param e table
function Expedition.Init(run, e, routeId)
    e.behavior, e.route_id, e.room_id, e.wave_id = "expedition", routeId, nil, run.wave_id
    e.expedition_route = copy(routeFor(run, routeId))
    e.damage_ledger = {}
    for roomId, cap in pairs(e.expedition_route.room_caps) do e.damage_ledger[roomId] = { cap = cap, used = 0, remaining = cap } end
    local hp = e.expedition_route.damage_mode == "core_budget" and run.config.enemies[e.role].hp or e.expedition_route.initial_hp
    e.hp, e.max_hp = hp, hp
    e.route_index, e.stage, e.stage_elapsed, e.expedition_leg, e.recovery_attempts = 1, "SPAWNING", 0, "entry", 0
    e.engage_duration, e.summon_disabled = e.expedition_route.engage_duration, true
    e.summon_pending = 0
    e.expedition_waypoint = copy(e.expedition_route.stops[1].entry)
    refresh(run, e)
    run.expedition_history = run.expedition_history or {}
    run.expedition_history[#run.expedition_history + 1] = e -- 死亡压缩后仍有账本，Snapshot只导出副本。
end

-- 纯提交前查询：公共Combat在写HP之前调用；不按发射时或攻击者房间计账。
---@param run table
---@param e table
---@return number, string
function Expedition.DamageAmount(run, e, requested)
    if e.behavior ~= "expedition" or e.expedition_route.damage_mode == "core_budget" then return requested, "" end
    if e.stage == "FINAL_ASSAULT" then return requested, "" end
    if e.stage ~= "ROOM_ENGAGED" then return 0, "transit_armor" end
    local stop = e.expedition_route.stops[e.route_index]
    if not stop or roomAt(run.map, e.x, e.y) ~= stop.room_id then return 0, "physical_room_mismatch" end
    local budget = e.damage_ledger[stop.room_id]
    if not budget then return 0, "missing_room_budget" end
    local remaining = math.max(0, budget.cap - budget.used)
    local actual = math.min(requested, remaining, math.max(0, e.hp - 1))
    return actual, actual < requested and (remaining <= math.max(0, e.hp - 1) and "room_budget" or "patrol_hp_floor") or ""
end

-- HP已由Combat写入，再同步账本，任何事件观察者都能读到完整提交。
---@param run table
---@param e table
function Expedition.CommitDamage(run, e, requested, actual, reason, context)
    if e.behavior ~= "expedition" or e.expedition_route.damage_mode == "core_budget" or e.stage == "FINAL_ASSAULT" or e.stage == "DEAD" then return end
    local stop = e.expedition_route.stops[e.route_index]
    local budget = stop and e.damage_ledger[stop.room_id]
    if e.stage == "ROOM_ENGAGED" and actual > 0 and budget then
        budget.used = math.min(budget.cap, budget.used + actual)
        budget.remaining = math.max(0, budget.cap - budget.used)
        if budget.remaining <= EPS then
            e.expedition_waypoint = copy(stop.exit)
            stage(run, e, "LEAVING", "budget_exhausted", context)
        end
        Reactions.Emit(run, "RoomDamageBudgetChanged", { entity_id = e.entity_id, id = e.id, route_id = e.route_id,
            room_id = stop.room_id, cap = budget.cap, used = budget.used, remaining = budget.remaining,
            requested = requested, actual = actual, suppressed = requested - actual, hp = e.hp, reason = reason }, context)
    end
    if actual < requested then
        Reactions.Emit(run, "DamageCapped", { entity_id = e.entity_id, id = e.id, target_id = e.entity_id,
            route_id = e.route_id, room_id = stop and stop.room_id, cap = budget and budget.cap,
            used = budget and budget.used, remaining = budget and budget.remaining, stage = e.stage,
            requested = requested, actual = actual, suppressed = requested - actual, reason = reason }, context)
    end
end

---@param run table
---@param e table
function Expedition.Died(run, e, context)
    if e.behavior == "expedition" then stage(run, e, "DEAD", "hp_zero", context) end
end

-- 当前路点重寻，不触发普通怪回入口恢复；成功寻路但连续不能移动也必须有界停止。
---@param run table
---@param e table
---@param repath fun(run:table,e:table,x:number,y:number):boolean
function Expedition.Recover(run, e, tx, ty, repath)
    e.recovery_attempts = (e.recovery_attempts or 0) + 1
    e.expedition_waypoint = { x = tx, y = ty }
    local ok = repath(run, e, tx, ty)
    e.stuck_timer = 0
    run:Emit("StuckRepath", { id = e.id, entity_id = e.entity_id, route_id = e.route_id, stage = e.stage,
        x = e.x, y = e.y, target_x = tx, target_y = ty, hp = e.hp, ok = ok,
        recovery_attempts = e.recovery_attempts, path_points = #e.path })
    if e.recovery_attempts >= ((run.config.combat or {}).expedition_recovery_limit or 3) then
        Expedition.TechnicalError(run, e, "waypoint_unreachable")
    end
end

-- move/attack来自Combat公共实现。ROOM_ENGAGED可攻击合法玩家/塔，绝不攻击核心。
-- 返回false只在FINAL_ASSAULT：交回既有Boss攻核/预警/碰撞；召唤始终禁用。
---@param run table
---@param e table
---@param callbacks table
function Expedition.Step(run, e, dt, callbacks)
    refresh(run, e)
    if e.stage == "FINAL_ASSAULT" then e.stage_elapsed = e.stage_elapsed + dt; return false end
    if e.stage == "DEAD" then return true end
    if e.stage == "SPAWNING" then stage(run, e, "TRAVELLING", "spawned") end
    e.stage_elapsed = e.stage_elapsed + dt
    local stop = e.expedition_route.stops[e.route_index]
    if e.stage == "ROOM_ENGAGED" then
        local budget = e.damage_ledger[stop.room_id]
        if budget.remaining <= EPS or e.stage_elapsed >= e.engage_duration - EPS then
            stage(run, e, "LEAVING", budget.remaining <= EPS and "budget_exhausted" or "engage_timeout")
        elseif e.current_room_id ~= stop.room_id then
            e.expedition_waypoint = copy(stop.engage)
            callbacks.move(run, e, stop.engage.x, stop.engage.y, dt)
            refresh(run, e)
            return true
        else
            callbacks.attack(run, e, stop.room_id, dt)
            return true
        end
    end
    local waypoint = e.stage == "LEAVING" and stop.exit or stop[e.expedition_leg]
    e.expedition_waypoint = copy(waypoint)
    callbacks.move(run, e, waypoint.x, waypoint.y, dt)
    refresh(run, e)
    if (e.x - waypoint.x)^2 + (e.y - waypoint.y)^2 > 0.05^2 then return true end
    e.recovery_attempts = 0
    if e.stage == "LEAVING" then
        if e.route_index < #e.expedition_route.stops then
            e.route_index, e.expedition_leg = e.route_index + 1, "entry"
            stage(run, e, "TRAVELLING", "exit_reached")
            e.expedition_waypoint = copy(e.expedition_route.stops[e.route_index].entry)
        else
            e.expedition_waypoint = copy(e.expedition_route.final_target)
            stage(run, e, "FINAL_ASSAULT", "all_stops_visited")
        end
    elseif e.expedition_leg == "entry" then
        e.expedition_leg, e.path_timer = "engage", 0
        e.expedition_waypoint = copy(stop.engage)
    elseif e.current_room_id == stop.room_id then
        stage(run, e, "ROOM_ENGAGED", "engage_reached")
    else Expedition.TechnicalError(run, e, "arrival_room_mismatch") end
    return true
end

-- 数组包含已死亡历史；无世界/配置/账本的可变引用暴露给UI。
---@param run table
function Expedition.Snapshot(run)
    local result = {}
    for _, e in ipairs(run.expedition_history or {}) do
        local route, stop = e.expedition_route, e.expedition_route.stops[e.route_index]
        local budget = stop and e.damage_ledger[stop.room_id]
        local nextStop = route.stops[e.route_index + 1]
        result[#result + 1] = { id = e.id, entity_id = e.entity_id, wave_id = e.wave_id, route_id = e.route_id, damage_mode = route.damage_mode, squad_id = e.squad_id,
            stage = e.stage, route_index = e.route_index, current_room_id = roomAt(run.map, e.x, e.y),
            stop_room_id = stop and stop.room_id, next_room_id = nextStop and nextStop.room_id,
            stage_elapsed = e.stage_elapsed, engage_duration = e.engage_duration,
            engage_remaining = e.stage == "ROOM_ENGAGED" and math.max(0, e.engage_duration - e.stage_elapsed) or 0,
            hp = e.hp, max_hp = e.max_hp, x = e.x, y = e.y,
            cap = budget and budget.cap or 0, used = budget and budget.used or 0, remaining = budget and budget.remaining or 0,
            room_cap = budget and budget.cap or 0, room_used = budget and budget.used or 0, room_remaining = budget and budget.remaining or 0,
            damage_ledger = copy(e.damage_ledger), stops = copy(route.stops), waypoint = copy(e.expedition_waypoint),
            final_target = copy(route.final_target), recovery_attempts = e.recovery_attempts, path_error = copy(e.path_error) }
    end
    return result
end
return Expedition
