-- 将已验证拓扑派生成独立玩法配置；不改旧四场景或共享 Config。
local Lattice = require("defense.Lattice")
local Topology = require("defense.Topology")
local Polygon = {}
local function point(x, y) return { x = x, y = y } end

function Polygon.Configure(c, options)
    options = options or {}
    local seed, difficulty = options.seed or 20261012, options.difficulty or 1
    -- 正式场景使用大房间网络；旧拓扑样板仍供历史场景和回归复用。
    local plan = { rooms = 12 + difficulty * 4, hex = 6 + difficulty * 2,
        clusters = 2 + math.floor(difficulty / 2), gates = difficulty,
        boss_waves = difficulty < 3 and 1 or difficulty < 5 and 2 or 3,
        enemy_scale = 1 + (difficulty-1)*0.15 }
    local graph = require('defense.GlobalRing').Generate(seed,difficulty,{plan=plan,max_steps=8000})
    local ok, reason = Topology.Validate(graph)
    assert(ok, reason)
    c.scenario_id, c.rules_version, c.version = "polygon_expansion", "polygon-global-ring-v3", "polygon-global-ring-v3"
    c.record_namespace = "defense_polygon_expansion"
    c.title, c.polygon_expansion = "固定据点守护神殿 · 多边形远域", true
    c.polygon_unit, c.topology, c.difficulty, c.map_seed = 2, graph, difficulty, seed
    c.rooms, c.build_slots, c.walkable_regions, c.obstacles = {}, {}, {}, {}
    c.gate_regions, c.shortcuts, c.expedition_routes, c.route_order = {}, {}, {}, {}
    c.room_graph = { nodes = {}, edges = {} }
    c.core_position, c.player_spawn, c.recall_position = point(0, 0), point(0, 4), point(0, 4)
    c.portals, c.zones = {}, {}
    local unit, order, parent = c.polygon_unit, { graph.main }, {}
    local visited = { [graph.main] = true }
    local cursor = 1
    while cursor <= #order do
        local id = order[cursor]; cursor = cursor + 1
        for _, link in ipairs(graph.links) do
            local nextId = link.a == id and link.b or link.b == id and link.a
            if nextId and not visited[nextId] then
                visited[nextId], parent[nextId] = true, id
                order[#order + 1] = nextId
            end
        end
    end
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for _, room in ipairs(graph.rooms) do
        local x, y = room.x * unit, room.y * unit
        local radius = Lattice.Circumradius(room.kind) * unit
        x1, y1 = math.min(x1, x - radius), math.min(y1, y - radius)
        x2, y2 = math.max(x2, x + radius), math.max(y2, y + radius)
        c.room_graph.nodes[#c.room_graph.nodes + 1] = { id = room.id, kind = room.role, x = x, y = y,
            room_id = room.role ~= "main" and room.id or nil }
        local slots = {}
        if room.kind == "tri" then
            slots[1] = point(x, y)
        elseif room.kind == "hex" then
            -- 三个槽环绕房间中心：1.4 米到中心，短程阻挡设施也能覆盖经过中心的敌人。
            local base = Lattice.PortNormals("hex", room.rotation)[1]
            for index = 0, 2 do
                local angle = math.rad(base + index * 120)
                slots[#slots + 1] = point(x + 1.4 * math.cos(angle), y + 1.4 * math.sin(angle))
            end
        else
            -- 十二边房保留十二槽：内圈拦截入殿路线，外圈给远程塔及支援设施留出间距。
            local base = Lattice.PortNormals("dodeca", room.rotation)[1]
            for index = 0, 5 do
                local angle = math.rad(base + index * 60)
                slots[#slots + 1] = point(x + 2.4 * math.cos(angle), y + 2.4 * math.sin(angle))
            end
            for index = 0, 5 do
                local angle = math.rad(base + 30 + index * 60)
                slots[#slots + 1] = point(x + 5.2 * math.cos(angle), y + 5.2 * math.sin(angle))
            end
        end
        local slotIds = {}
        for index, slot in ipairs(slots) do
            slot.id = "P_" .. room.id .. "_" .. index
            if room.role ~= "main" then slot.owner_room_id, slot.activation_region_id = room.id, room.id end
            slotIds[#slotIds + 1] = slot.id
            c.build_slots[#c.build_slots + 1] = slot
        end
        if room.role ~= "main" then
            local prerequisite = parent[room.id]
            if prerequisite == graph.main or graph.byId[prerequisite].role == "gate" then prerequisite = nil end
            local kind = room.kind
            c.rooms[#c.rooms + 1] = { id = room.id, kind = kind, role = room.role,
                name = ({ A = "幽灵沼泽", B = "极光地区", C = "沙漠区" })[room.district] .. " · " .. Lattice.Spec(kind).name,
                x = x, y = y, tier = prerequisite and 2 or 1, prerequisite = prerequisite,
                access_prerequisites=room.access_from,
                region_id = room.district, guard_profile = { count = room.empty and 0 or 4, roles = { "advance", "ranged" } },
                encounter_waves = kind == "tri" and 3 or kind == "hex" and 2 or 1,
                defense_slots = slotIds, module_reward = kind == "hex", challenge_target = false,
                gold_reward = kind == "dodeca" and 80 or kind == "hex" and 60 or 40,
                sand_reward = kind == "dodeca" and 25 or 10, initially_cleared = room.role == "gate" }
        end
    end
    for _, id in ipairs(order) do
        local room = graph.byId[id] --[[@as table]]
        if room.role ~= "main" and room.role ~= "gate" then c.route_order[#c.route_order + 1] = id end
    end
    for index, district in ipairs({ "A", "B", "C" }) do
        local gate = graph.byId[graph.districts[district].gate] --[[@as table]]
        c.portals[({ "W", "E", "S" })[index]] = point(gate.x * unit, gate.y * unit)
        c.zones[#c.zones + 1] = { id = district, name = ({ "幽灵沼泽", "极光地区", "沙漠区" })[index], rooms = graph.districts[district].rooms }
    end
    for _, link in ipairs(graph.links) do
        if link.gate then c.gate_regions[#c.gate_regions + 1] = { id = "gate_" .. link.id,
            unlock_condition = { room_id = link.a, state = "cleared" } } end
        c.room_graph.edges[#c.room_graph.edges + 1] = { id = link.id, from = link.a, to = link.b,
            roles = { "player", "enemy", "expedition" }, gate_id = link.gate and ("gate_" .. link.id) or nil }
    end
    c.map_origin, c.map_size = point(x1 - 2, y1 - 2), { w = x2 - x1 + 4, h = y2 - y1 + 4 }
    c.enemy_scale = graph.stats.enemy_scale
    for role, enemy in pairs(c.enemies) do
        if not role:find("expedition", 1, true) then enemy.hp = enemy.hp * c.enemy_scale end
    end
    c.decisions.POLYGON = "房间接入阶段：理想十二边碰撞；同群系锚点+主空间中转；20秒冷却；死亡全局失败。双池树/六角色炮塔/墙/地形为后续阶段。"
    return c
end
return Polygon
