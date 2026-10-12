-- 房间图负责通行协议/校验/估时；不依赖Combat，不推进时钟，不激活守军或结算奖励。
local Map = require("defense.Map")
local RoomGraph = {}
local EPS = 1e-7

local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function isPoint(p) return type(p) == "table" and finite(p.x) and finite(p.y) end
local function cleared(room) return room and (room.state == "cleared" or room.state == "claimed" or room.reward_claimed == true) end
---@return table<string,table>
local function roomIndex(rooms)
    local result = {}
    for _, room in ipairs(rooms or {}) do result[room.id] = room end
    return result
end
local function pathLength(path)
    local length = 0
    for i = 2, #path do
        local a, b = path[i - 1], path[i]
        length = length + math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
    end
    return length
end

-- 条件支持单个room_id、字符串room_id、all/any；无条件表示初始可通行。
local function conditionSatisfied(condition, rooms)
    if condition == nil then return true end
    if type(condition) == "string" then return cleared(rooms[condition]) == true end
    if type(condition) ~= "table" then return false end
    if condition.all then
        for _, item in ipairs(condition.all) do if not conditionSatisfied(item, rooms) then return false end end
        return #condition.all > 0
    end
    if condition.any then
        for _, item in ipairs(condition.any) do if conditionSatisfied(item, rooms) then return true end end
        return false
    end
    local room = rooms[condition.room_id]
    if not room then return false end
    if condition.state == nil or condition.state == "cleared" then return cleared(room) == true end
    if condition.state == "claimed" then return room.state == "claimed" or room.reward_claimed == true end
    return false
end

local function prerequisites(def)
    local result = {}
    if def.prerequisite then result[#result + 1] = def.prerequisite end
    for _, id in ipairs(def.prerequisites or {}) do result[#result + 1] = id end
    return result
end

local function dependencyIds(condition, result)
    if type(condition) == "string" then result[#result + 1] = condition; return true end
    if type(condition) ~= "table" then return false end
    if condition.all or condition.any then
        local items = condition.all or condition.any
        if type(items) ~= "table" or #items == 0 then return false end
        for _, item in ipairs(items) do if not dependencyIds(item, result) then return false end end
        return true
    end
    if type(condition.room_id) ~= "string" or
        (condition.state ~= nil and condition.state ~= "cleared" and condition.state ~= "claimed") then return false end
    result[#result + 1] = condition.room_id
    return true
end

---@param run table
---@return boolean, string?
function RoomGraph.UpdateAccess(run)
    if run.config.polygon_expansion then return require("defense.PolygonRooms").UpdateAccess(run) end
    if not run.config or not run.map then return false, "missing_map" end
    local rooms = roomIndex(run.rooms)
    for _, def in ipairs(run.config.rooms or {}) do
        local runtime = rooms[def.id]
        if not runtime then return false, "missing_runtime_room:" .. tostring(def.id) end
        local satisfied = true
        for _, id in ipairs(prerequisites(def)) do
            if not cleared(rooms[id]) then satisfied = false; break end
        end
        if def.unlock_condition and not conditionSatisfied(def.unlock_condition, rooms) then satisfied = false end
        local required = prerequisites(def)
        local override = run.config.locked_rooms and run.config.locked_rooms[def.id]
        -- locked_rooms 是初始覆盖，不是永久禁止：false可开任意房间；true优先于def.unlocked，
        -- 但正常清前置后仍可解锁。没有前置的显式锁只能由已有通行授权/考验开门解除。
        if override == false then satisfied = true
        elseif override == true and #required == 0 and not def.unlock_condition then
            satisfied = runtime.prerequisite_satisfied == true
        elseif override == nil and def.unlocked == true then satisfied = true end
        if cleared(runtime) then satisfied = true end
        runtime.prerequisite_satisfied = satisfied
        runtime.challenge_gate_open = runtime.challenge_gate_open == true
        runtime.accessible = satisfied or runtime.challenge_gate_open
        runtime.unlocked = runtime.accessible -- 兼容旧 UpdateRooms 与UI；不能据此授权外围建造。
        if not run.map:SetUnlocked(def.id, runtime.accessible) then return false, "unknown_room_gate:" .. def.id end
    end
    -- 清房捷径独立于考验；只有自己的条件满足才开，不随远征自动解锁。
    local gates = {}
    for _, gate in ipairs(run.config.gate_regions or {}) do gates[gate.gate_id or gate.id] = gate end
    for _, shortcut in ipairs(run.config.shortcuts or {}) do
        local id = shortcut.gate_id or shortcut.id
        local gate = gates[id]
        if not gate then return false, "unknown_shortcut_gate:" .. tostring(id) end
        local condition = shortcut.unlock_condition or gate.unlock_condition
        if conditionSatisfied(condition, rooms) and run.map.locked[id] == true then
            if not run.map:SetUnlocked(id, true) then return false, "unknown_shortcut_gate:" .. id end
            if run.Emit then run:Emit("GateOpened", { gate_id = id, reason = "room_cleared", shortcut_id = shortcut.id }) end
        end
    end
    for id, gate in pairs(gates) do
        if gate.shortcut ~= true and gate.unlock_condition and conditionSatisfied(gate.unlock_condition, rooms)
            and run.map.locked[id] == true then
            if not run.map:SetUnlocked(id, true) then return false, "unknown_gate:" .. id end
            if run.Emit then run:Emit("GateOpened", { gate_id = id, reason = "prerequisite" }) end
        end
    end
    return true
end

-- 配置验证使用独立地图，不将验证期间的“全开门”污染当前运行态或缓存。
local function cloneMap(config, source)
    local ok, map = pcall(Map.New, config)
    if not ok then return nil, tostring(map) end
    if source then
        for id, locked in pairs(source.locked) do
            if not map:SetUnlocked(id, not locked) then return nil, "unknown_map_gate:" .. tostring(id) end
        end
    end
    return map
end

local function leg(map, a, b, radius)
    if not isPoint(a) or not isPoint(b) then return nil, "invalid_point" end
    local path = map:Path(a.x, a.y, b.x, b.y, radius)
    if not path then return nil, "path_blocked" end
    for i = 2, #path do
        local p, q = path[i - 1], path[i]
        if not map:LineOfSight(p.x, p.y, q.x, q.y, radius) then return nil, "path_crosses_wall" end
    end
    return pathLength(path), path
end

-- 单一路线的实体站点/预算/逐段路径。stop_ids必须与预告顺序完全一致，不能静默补站。
local function checkRoute(config, map, route, radius, challenge, portal)
    if type(route) ~= "table" or type(route.route_id) ~= "string" or type(route.stops) ~= "table" or #route.stops == 0 then
        return false, "invalid_route"
    end
    if not finite(route.initial_hp) or route.initial_hp <= 0 or not finite(route.engage_duration) or route.engage_duration <= 0
        or not isPoint(route.final_target) or type(route.room_caps) ~= "table" then return false, "invalid_route_budget" end
    if not isPoint(config.core_position) or math.abs(route.final_target.x - config.core_position.x) > EPS
        or math.abs(route.final_target.y - config.core_position.y) > EPS then return false, "final_target_not_core" end
    if challenge and (type(challenge.stop_ids) ~= "table" or #challenge.stop_ids ~= #route.stops) then return false, "stop_ids_mismatch" end
    local rooms, seen, caps, last, length = roomIndex(config.rooms), {}, 0, config.portals[portal or "S"], 0
    if not isPoint(last) then return false, "invalid_route_portal" end
    local segments = {}
    for i, item in ipairs(route.stops) do
        local id = item.room_id
        local room = rooms[id]
        if not room or seen[id] then return false, "invalid_or_duplicate_stop:" .. tostring(id) end
        if challenge and challenge.stop_ids[i] ~= id then return false, "stop_ids_order_mismatch" end
        seen[id] = true
        local cap = route.room_caps[id]
        if not finite(cap) or cap <= 0 then return false, "invalid_room_cap:" .. id end
        caps = caps + cap
        for _, name in ipairs({ "entry", "engage", "exit" }) do
            local p = item[name]
            if not isPoint(p) or not map:IsInRegion(id, p.x, p.y) or not map:IsWalkable(p.x, p.y, radius) then
                return false, "invalid_stop_geometry:" .. id
            end
        end
        for _, name in ipairs({ "entry", "engage", "exit" }) do
            local p = item[name]
            local distance, path = leg(map, last, p, radius)
            if not distance then return false, "route_blocked:" .. id end
            length = length + distance
            segments[#segments + 1] = path
            last = p
        end
    end
    for id in pairs(route.room_caps) do if not seen[id] then return false, "cap_without_stop:" .. tostring(id) end end
    if caps > route.initial_hp * 0.5 + EPS then return false, "route_budget_exceeds_half_hp" end
    for _, room in ipairs(config.rooms or {}) do
        if room.challenge_target == true and not seen[room.id] then return false, "missing_challenge_target:" .. room.id end
    end
    local distance, path = leg(map, last, route.final_target, radius)
    if not distance then return false, "invalid_final_target_path" end
    segments[#segments + 1] = path
    return true, { path_length = length + distance, segments = segments, cap_total = caps, stop_count = #route.stops }
end

local function collectChallengeGates(config, map, route)
    local rooms, ids = roomIndex(config.rooms), {}
    local function addRoom(id, visiting)
        if visiting[id] then return false, "prerequisite_cycle:" .. id end
        if ids[id] then return true end
        local def = rooms[id]
        if not def or map.locked[id] == nil then return false, "unknown_route_room:" .. tostring(id) end
        visiting[id] = true
        for _, prerequisite in ipairs(prerequisites(def)) do
            local ok, reason = addRoom(prerequisite, visiting)
            if not ok then return false, reason end
        end
        local dependencies = {}
        if def.unlock_condition then
            if not dependencyIds(def.unlock_condition, dependencies) then return false, "invalid_unlock_condition:" .. id end
            for _, prerequisite in ipairs(dependencies) do
                local ok, reason = addRoom(prerequisite, visiting)
                if not ok then return false, reason end
            end
        end
        visiting[id], ids[id] = nil, true
        return true
    end
    for _, stop in ipairs(route.stops or {}) do
        local ok, reason = addRoom(stop.room_id, {})
        if not ok then return nil, reason end
    end
    for _, id in ipairs(route.gate_ids or {}) do
        if map.locked[id] == nil then return nil, "unknown_route_gate:" .. tostring(id) end
        ids[id] = true
    end
    return ids
end

---@param run table
---@return boolean, string?
function RoomGraph.OpenChallenge(run)
    if not run.config or not run.map then return false, "missing_map" end
    local wave = run.current_wave or run.config.waves[run.wave_id]
    local challenge = wave and wave.challenge
    if not challenge then return RoomGraph.UpdateAccess(run) end
    local function fail(reason)
        run.technical_error = { reason = reason, wave_id = run.wave_id, route_id = challenge.route_id }
        if run.Emit then run:Emit("ExpeditionPathError", { wave_id = run.wave_id,
            route_id = challenge.route_id, reason = reason, phase = "open_challenge" }) end
        return false, reason
    end
    local route = (run.config.expedition_routes or {})[challenge.route_id]
    if type(route) ~= "table" or route.route_id ~= challenge.route_id then return fail("unknown_route") end
    local key = tostring(run.wave_id) .. ":" .. challenge.route_id
    run.challenge_opened = run.challenge_opened or {}
    if run.challenge_opened[key] then return RoomGraph.UpdateAccess(run) end
    local trial, reason = cloneMap(run.config, run.map)
    if not trial then return fail(reason) end
    local gates, gateReason = collectChallengeGates(run.config, trial, route)
    if not gates then return fail(gateReason) end
    for id in pairs(gates) do trial:SetUnlocked(id, true) end
    local def = run.config.enemies.expedition
    if not def then return fail("missing_expedition_definition") end
    local ok, detail = checkRoute(run.config, trial, route, def.radius or 0, challenge, "S")
    if not ok then return fail(detail) end
    local rooms = roomIndex(run.rooms)
    for id in pairs(gates) do if roomIndex(run.config.rooms)[id] and not rooms[id] then return fail("missing_runtime_room:" .. id) end end
    -- 先完整验证，再提交真门；任何奖励/守军/建造字段均不修改。
    local sorted = {}
    for id in pairs(gates) do sorted[#sorted + 1] = id end
    table.sort(sorted)
    for _, id in ipairs(sorted) do
        local wasLocked = run.map.locked[id] == true
        if not run.map:SetUnlocked(id, true) then return fail("gate_commit_failed:" .. id) end
        if rooms[id] then rooms[id].challenge_gate_open = true end
        if wasLocked and run.Emit then run:Emit("GateOpened", { gate_id = id, room_id = rooms[id] and id or nil,
            wave_id = run.wave_id, route_id = route.route_id, reason = "challenge" }) end
    end
    local accessOK, accessReason = RoomGraph.UpdateAccess(run)
    if not accessOK then return fail(accessReason) end
    run.challenge_opened[key] = true
    if run.Emit then run:Emit("ChallengeAnnounced", { wave_id = run.wave_id, route_id = route.route_id,
        stop_ids = { table.unpack(challenge.stop_ids) }, special_count = wave.special_count }) end
    return true
end

---@param config table
---@param map? DefenseMap
---@param radius? number
---@return boolean, table 报告含errors/edge_lengths/routes；校验不修改config/map。
function RoomGraph.Check(config, map, radius)
    local report = { errors = {}, edge_lengths = {}, routes = {}, node_count = 0, edge_count = 0, cross_region_count = 0 }
    local function error(reason) report.errors[#report.errors + 1] = reason end
    if type(config) ~= "table" then error("invalid_config"); return false, report end
    radius = radius or (config.enemies and config.enemies.expedition and config.enemies.expedition.radius)
        or (config.player and config.player.radius) or 0
    if not finite(radius) or radius < 0 then error("invalid_radius"); return false, report end
    local trial, reason = cloneMap(config, map)
    if not trial then error(reason); return false, report end
    local rooms, dependencies = {}, {}
    for _, room in ipairs(config.rooms or {}) do
        if type(room.id) ~= "string" or rooms[room.id] then error("duplicate_or_invalid_room_id:" .. tostring(room.id))
        else rooms[room.id] = room end
        dependencies[room.id] = prerequisites(room)
        if room.unlock_condition and not dependencyIds(room.unlock_condition, dependencies[room.id]) then
            error("invalid_room_condition:" .. tostring(room.id))
        end
    end
    local visiting, done = {}, {}
    local function visit(id)
        if visiting[id] then error("prerequisite_cycle:" .. tostring(id)); return end
        if done[id] then return end
        visiting[id] = true
        for _, dependency in ipairs(dependencies[id] or {}) do
            if not rooms[dependency] then error("missing_prerequisite:" .. tostring(dependency)) else visit(dependency) end
        end
        visiting[id], done[id] = nil, true
    end
    for id in pairs(rooms) do visit(id) end
    for _, gate in ipairs(config.gate_regions or {}) do
        local ids = {}
        if gate.unlock_condition and not dependencyIds(gate.unlock_condition, ids) then error("invalid_gate_condition:" .. tostring(gate.id)) end
        for _, id in ipairs(ids) do if not rooms[id] then error("missing_gate_prerequisite:" .. id) end end
    end
    if #report.errors > 0 then return false, report end
    -- 全部探索门开，仅保留玩家捷径闸门关闭；用于逐边与必经路线验证。
    for id in pairs(rooms) do trial:SetUnlocked(id, true) end
    for _, gate in ipairs(config.gate_regions or {}) do
        if not gate.shortcut then trial:SetUnlocked(gate.gate_id or gate.id, true) end
    end
    for _, key in ipairs({ "core_position", "player_spawn", "recall_position" }) do
        local p = config[key]
        if not isPoint(p) or not trial:IsWalkable(p.x, p.y, radius) then error("invalid_required_point:" .. key) end
    end
    for id, p in pairs(config.portals or {}) do
        local distance = leg(trial, p, config.core_position, radius)
        if not distance then error("portal_path_blocked:" .. id) end
    end
    for id, room in pairs(rooms) do
        if not trial:IsInRegion(id, room.x, room.y) then error("room_center_outside:" .. id) end
        local distance = leg(trial, config.core_position, room, radius)
        if not distance then error("room_unreachable:" .. id) end
    end
    local graph = config.room_graph
    if graph then
        local nodes, edges, adjacency = {}, {}, {}
        for _, node in ipairs(graph.nodes or {}) do
            report.node_count = report.node_count + 1
            if type(node.id) ~= "string" or nodes[node.id] then error("duplicate_or_invalid_node:" .. tostring(node.id))
            else nodes[node.id], adjacency[node.id] = node, {} end
            if not isPoint(node) or not trial:IsWalkable(node.x, node.y, radius) then error("node_not_walkable:" .. tostring(node.id)) end
            if node.room_id and not rooms[node.room_id] then error("node_missing_room:" .. tostring(node.id)) end
        end
        for id in pairs(rooms) do
            local found = false
            for _, node in ipairs(graph.nodes or {}) do if node.room_id == id then found = true; break end end
            if not found then error("room_missing_node:" .. id) end
        end
        for _, edge in ipairs(graph.edges or {}) do
            report.edge_count = report.edge_count + 1
            if type(edge.id) ~= "string" or edges[edge.id] then error("duplicate_or_invalid_edge:" .. tostring(edge.id)) end
            edges[edge.id] = true
            local a, b = nodes[edge.from], nodes[edge.to]
            if not a or not b or a == b then error("edge_missing_endpoints:" .. tostring(edge.id))
            else
                if type(edge.roles) ~= "table" or #edge.roles == 0 then error("edge_missing_roles:" .. edge.id) end
                if edge.gate_id and trial.locked[edge.gate_id] == nil then error("edge_unknown_gate:" .. edge.id) end
                if edge.path_length ~= nil and (not finite(edge.path_length) or edge.path_length < 0) then error("invalid_edge_length:" .. edge.id) end
                local ids = {}
                if edge.unlock_condition and not dependencyIds(edge.unlock_condition, ids) then error("invalid_edge_condition:" .. edge.id) end
                for _, id in ipairs(ids) do if not rooms[id] then error("edge_missing_prerequisite:" .. id) end end
                local wasLocked = edge.gate_id and trial.locked[edge.gate_id]
                if edge.shortcut and edge.gate_id then trial:SetUnlocked(edge.gate_id, true) end
                local last, length, valid = a, 0, true
                local points = {}
                for _, p in ipairs(edge.waypoints or {}) do points[#points + 1] = p end
                points[#points + 1] = b
                for _, p in ipairs(points) do
                    local distance = leg(trial, last, p, radius)
                    if not distance then error("edge_geometry_blocked:" .. edge.id); valid = false; break end
                    length, last = length + distance, p
                end
                if valid then
                    report.edge_lengths[edge.id] = length
                    if edge.path_length and math.abs(edge.path_length - length) > EPS then error("edge_length_mismatch:" .. edge.id) end
                    adjacency[edge.from][#adjacency[edge.from] + 1] = edge.to
                    if edge.directed ~= true then adjacency[edge.to][#adjacency[edge.to] + 1] = edge.from end
                end
                if edge.shortcut and edge.gate_id then trial:SetUnlocked(edge.gate_id, not wasLocked) end
                if edge.cross_region then
                    local ar = a.room_id and rooms[a.room_id] --[[@as table?]]
                    local br = b.room_id and rooms[b.room_id] --[[@as table?]]
                    if not ar or not br or ar.region_id == br.region_id then error("invalid_cross_region_edge:" .. edge.id)
                    else report.cross_region_count = report.cross_region_count + 1 end
                end
            end
        end
        local root = nodes.core and "core" or (graph.nodes[1] and graph.nodes[1].id)
        local reached, queue = {}, {}
        if root then reached[root], queue[1] = true, root end
        local cursor = 1
        while cursor <= #queue do
            local id = queue[cursor]
            cursor = cursor + 1
            for _, other in ipairs(adjacency[id] or {}) do if not reached[other] then reached[other], queue[#queue + 1] = true, other end end
        end
        for id in pairs(nodes) do if not reached[id] then error("graph_node_unreachable:" .. id) end end
        if config.scenario_id == "large_map_proto" then
            if #config.rooms < 8 or #config.rooms > 12 then error("large_room_count") end
            if report.cross_region_count < 2 then error("missing_cross_region_loops") end
            if #config.shortcuts < 1 then error("missing_clear_room_shortcut") end
        end
    elseif config.scenario_id and config.scenario_id ~= "legacy_v02" then error("missing_room_graph") end
    local slots = {}
    for _, slot in ipairs(config.build_slots or {}) do
        if slots[slot.id] then error("duplicate_slot:" .. tostring(slot.id)) end
        slots[slot.id] = slot
        if not trial:IsWalkable(slot.x, slot.y, (config.combat or {}).tower_radius or 0.65) then error("slot_not_walkable:" .. tostring(slot.id)) end
        if slot.owner_room_id and (not rooms[slot.owner_room_id] or not trial:IsInRegion(slot.owner_room_id, slot.x, slot.y)) then
            error("invalid_slot_owner:" .. tostring(slot.id))
        end
        if slot.owner_room_id and (not slot.activation_region_id or not trial.room_regions[slot.activation_region_id]) then
            error("invalid_slot_activation_region:" .. tostring(slot.id))
        end
    end
    for _, room in ipairs(config.rooms or {}) do
        for _, id in ipairs(room.defense_slots or {}) do
            if not slots[id] or slots[id].owner_room_id ~= room.id then error("invalid_room_slot:" .. room.id) end
        end
    end
    for id, route in pairs(config.expedition_routes or {}) do
        if route.route_id ~= id then error("route_key_mismatch:" .. tostring(id)) end
        local ok, detail = checkRoute(config, trial, route, radius)
        if not ok then error(tostring(id) .. ":" .. tostring(detail)) else report.routes[id] = detail end
    end
    for _, wave in ipairs(config.waves or {}) do
        if wave.challenge then
            local route = (config.expedition_routes or {})[wave.challenge.route_id]
            local ok, detail = checkRoute(config, trial, route, radius, wave.challenge)
            if not ok then error("wave_" .. tostring(wave.wave_id) .. ":" .. tostring(detail)) end
            if wave.special_count ~= #(wave.special_units or {}) then error("special_count_mismatch") end
            for _, unit in ipairs(wave.special_units or {}) do
                if unit.route_id ~= wave.challenge.route_id or unit.role ~= "expedition" or not finite(unit.at) or unit.at < 0 then
                    error("invalid_special_unit")
                end
                if not config.portals[unit.portal] then error("invalid_special_portal") end
            end
        end
    end
    return #report.errors == 0, report
end

---@param run table
---@return table
function RoomGraph.EstimateReturn(run)
    local p, config = run.player or {}, run.config or {}
    local base = p.speed or (config.player and config.player.speed) or 0
    local mobility = math.max(0, (p.skills or {}).mobility or 0)
    local speed = base * (1 + mobility * 0.12) * (p.slow_factor or 1)
    if p.movable == false or p.anchored == true or p.alive == false then speed = 0 end
    local result = { reachable = false, reason = "missing_map", path = {}, path_length = math.huge, distance = math.huge,
        effective_speed = speed, seconds = math.huge, remaining = run.preparation_remaining or 0,
        margin = -math.huge, can_return = false }
    local target = run.core or config.core_position
    if not run.map or not isPoint(p) or not isPoint(target) then return result end
    local length, path = leg(run.map, p, target, p.radius or 0)
    if not length then result.reason = "path_blocked"; return result end
    result.path, result.path_length, result.distance = path, length, length
    if not finite(speed) or speed <= 0 then result.reason = "zero_effective_speed"; return result end
    result.reachable, result.reason, result.seconds = true, "", length / speed
    result.margin = result.remaining - result.seconds
    result.can_return = result.margin >= -EPS
    return result
end

return RoomGraph
