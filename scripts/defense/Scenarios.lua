-- 场景是 legacy Config 的独立深拷贝；原20行普通/精英/Boss输入永不改写。
-- v0.3 几何继续以逻辑格表示，X向右/Y向下；原点取实际矩形包围盒并留一格边。
local Legacy = require("defense.Config")
local Scenarios = {}
local Expansion = require("defense.Expansion")

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end

local function point(x, y) return { x = x, y = y } end
local function rect(id, x1, y1, x2, y2)
    return { id = id, x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

local function room(id, x, y, tier, prerequisite, unlock, profile, reward, target)
    local roles = profile == "junction" and { "advance", "ranged", "charger" }
        or profile == "deep" and { "advance", "ranged", "advance" } or { "advance", "advance", "ranged" }
    return { id = id, x = x, y = y, tier = tier, prerequisite = prerequisite, unlock = unlock,
        region_id = id:sub(1, 1), guard_profile = { id = profile,
            count = profile == "junction" and 8 or tier == 1 and 4 or 6, roles = roles },
        reward_kind = reward, module_reward = true, defense_slots = {}, challenge_target = target }
end

local function addSlot(config, owner, x, y)
    local id = "T_" .. owner.id
    owner.defense_slots[#owner.defense_slots + 1] = id
    config.build_slots[#config.build_slots + 1] = { id = id, x = x, y = y,
        owner_room_id = owner.id, activation_region_id = owner.id }
end

local function bounds(config)
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for _, region in ipairs(config.walkable_regions) do
        x1, y1 = math.min(x1, region.x1), math.min(y1, region.y1)
        x2, y2 = math.max(x2, region.x2), math.max(y2, region.y2)
    end
    config.map_origin = point(x1 - 1, y1 - 1)
    config.map_size = { w = x2 - x1 + 2, h = y2 - y1 + 2 }
end

local function stop(id, entryX, entryY, x, y, exitX, exitY)
    return { room_id = id, entry = point(entryX, entryY), engage = point(x, y), exit = point(exitX, exitY) }
end

local function addRoute(config, id, stops, waveIds)
    local route = { route_id = id, stops = stops, engage_duration = 12, room_caps = {},
        initial_hp = 1200, final_target = copy(config.core_position) }
    local stopIds = {}
    for _, item in ipairs(stops) do
        route.room_caps[item.room_id] = 600 / #stops
        stopIds[#stopIds + 1] = item.room_id
    end
    config.expedition_routes[id] = route
    for _, waveId in ipairs(waveIds) do
        local wave = config.waves[waveId]
        wave.challenge = { route_id = id, stop_ids = copy(stopIds) }
        wave.special_units = { { role = "expedition", portal = "S", at = 3, route_id = id } }
        wave.special_count = 1
    end
end

local function addGraph(config, links)
    local graph = { nodes = {}, edges = {} }
    config.room_graph = graph
    local function node(id, kind, p, roomId)
        graph.nodes[#graph.nodes + 1] = { id = id, kind = kind, x = p.x, y = p.y, room_id = roomId }
    end
    node("core", "core", config.core_position)
    node("logistics", "logistics", config.recall_position)
    for _, id in ipairs({ "W", "E", "S" }) do node("portal_" .. id, "connection", config.portals[id]) end
    for _, def in ipairs(config.rooms) do node(def.id, "room", def, def.id) end
    for _, link in ipairs(links) do
        graph.edges[#graph.edges + 1] = { id = link[1], from = link[2], to = link[3],
            roles = { "player", "expedition", "enemy" }, gate_id = link[4], unlock_condition = link[5],
            cross_region = link[6] == true, waypoints = link[7] }
    end
    -- path_length 是按当前实体半径实际求出的派生值，由 RoomGraph.Check 返回报告而不是虚构直线值。
    for _, shortcut in ipairs(config.shortcuts) do
        graph.edges[#graph.edges + 1] = { id = shortcut.id, from = shortcut.from, to = shortcut.to,
            roles = { "player" }, gate_id = shortcut.gate_id, unlock_condition = copy(shortcut.unlock_condition),
            shortcut = true, waypoints = copy(shortcut.waypoints) }
    end
end

local function common(config, id, totalWaves, specials)
    config.scenario_id, config.rules_version = id, "0.3.0-prototype"
    config.version = "defense-0.3.0"
    config.total_waves, config.final_intro_wave = totalWaves, totalWaves
    config.record_namespace, config.can_record_chapter = "defense_" .. id, false
    config.module_system, config.max_alive_towers, config.module_change_cost = true, 6, 20
    config.map_origin = point(0, 0)
    config.expedition_routes, config.shortcuts, config.gate_regions = {}, {}, {}
    config.declared_ordinary_total, config.declared_special_total = 1176, specials
    config.declared_totals = { ordinary = 1176, normal = 1159, elite = 14, boss = 3,
        special = specials, total = 1176 + specials }
    config.enemies.expedition = copy(config.enemies.commander)
    local enemy = config.enemies.expedition
    enemy.hp, enemy.name, enemy.is_boss, enemy.summon_disabled = 1200, "远征统领", true, true
    config.enemy_emoji.expedition = copy(config.enemy_emoji.commander)
    for _, wave in ipairs(config.waves) do wave.special_units, wave.special_count = {}, 0 end
end

local function sample(config)
    common(config, "reuse_sample", 5, 1)
    config.rooms = {
        room("A1", 8, 21, 1, nil, "A2", "near", "gold_and_module", true),
        room("A2", 8, 6, 2, "A1", nil, "deep", "experience_and_module", false),
        room("B1", 56, 21, 1, nil, "B2", "near", "gold_and_module", true),
        room("B2", 56, 6, 2, "B1", nil, "deep", "experience_and_module", false),
        room("C1", 32, 43, 1, nil, "C2", "near", "gold_and_module", true),
        room("C2", 53, 43, 2, "C1", nil, "deep", "experience_and_module", false),
    }
    addSlot(config, config.rooms[1], 8, 24)
    addSlot(config, config.rooms[3], 56, 24)
    addSlot(config, config.rooms[5], 35, 43)
    addRoute(config, "sample_loop", {
        stop("A1", 11, 21, 8, 21, 11, 21),
        stop("B1", 53, 21, 56, 21, 53, 21),
        stop("C1", 32, 40, 32, 43, 32, 40),
    }, { 5 })
    addGraph(config, {
        { "core_logistics", "core", "logistics" }, { "core_w", "core", "portal_W" },
        { "core_e", "core", "portal_E" }, { "core_s", "core", "portal_S" },
        { "w_a1", "portal_W", "A1" }, { "a1_a2", "A1", "A2", "A2", { room_id = "A1", state = "cleared" } },
        { "e_b1", "portal_E", "B1" }, { "b1_b2", "B1", "B2", "B2", { room_id = "B1", state = "cleared" } },
        { "s_c1", "portal_S", "C1" }, { "c1_c2", "C1", "C2", "C2", { room_id = "C1", state = "cleared" } },
    })
end

local function large(config)
    common(config, "large_map_proto", 20, 2)
    config.title = "固定据点防守 · 外圈远征"
    -- 三外圈：A西侧、B东侧、C南侧。宽4格的连接可供半径.9圆体通过。
    --          A2 ========== B2        顶部跨区环路
    --           |  [捷径->后勤] |
    --          A1 --W--核心--E--B1
    --           |       S       |
    --          A3       C1      B3
    --           \       /\       /
    --            C2 ========= C3       两处下方跨区连接
    -- 锁是整个探索房间；考验真开全部沿线房间。捷径仅清A2后开，不改变必经站顺序。
    config.rooms = {
        room("A1", -6, 21, 1, nil, "A2", "near", "gold_and_module", true),
        room("A2", -6, 0, 2, "A1", "A3", "deep", "experience_and_module", true),
        room("A3", -6, 48, 2, "A2", nil, "junction", "shortcut_and_module", true),
        room("B1", 70, 21, 1, nil, "B2", "near", "gold_and_module", true),
        room("B2", 70, 0, 2, "B1", "B3", "deep", "experience_and_module", true),
        room("B3", 70, 48, 2, "B2", nil, "junction", "gold_and_module", true),
        room("C1", 32, 51, 1, nil, "C2", "near", "gold_and_module", true),
        room("C2", 14, 65, 2, "C1", "C3", "deep", "experience_and_module", true),
        room("C3", 50, 65, 2, "C2", nil, "junction", "gold_and_module", true),
    }
    config.walkable_regions = {
        rect("hall", 21, 10, 43, 32), rect("logistics", 25, 2, 39, 8),
        rect("north_corridor", 30, 7, 34, 11), rect("west_corridor", 1, 19, 22, 23),
        rect("east_corridor", 42, 19, 63, 23), rect("south_corridor", 30, 31, 34, 44),
        rect("A1", -14, 13, 2, 29), rect("A2", -14, -8, 2, 8), rect("A3", -14, 40, 2, 56),
        rect("A_north", -8, 7, -4, 14), rect("A_south", -8, 28, -4, 41),
        rect("B1", 62, 13, 78, 29), rect("B2", 62, -8, 78, 8), rect("B3", 62, 40, 78, 56),
        rect("B_north", 68, 7, 72, 14), rect("B_south", 68, 28, 72, 41),
        rect("C1", 24, 43, 40, 59), rect("C2", 6, 60, 22, 70), rect("C3", 42, 60, 58, 70),
        rect("C_left_h", 12, 49, 25, 53), rect("C_left_v", 12, 50, 16, 63),
        rect("C_right_h", 39, 49, 52, 53), rect("C_right_v", 48, 50, 52, 63),
        rect("loop_AB", 1, -2, 63, 2),
        rect("loop_AC_v", -8, 55, -4, 67), rect("loop_AC_h", -7, 63, 7, 67),
        rect("loop_BC_v", 68, 55, 72, 67), rect("loop_BC_h", 57, 63, 71, 67),
        rect("loop_CC", 21, 63, 43, 67), rect("shortcut_A2_lane", 1, 4, 26, 8),
    }
    bounds(config)
    for _, def in ipairs(config.rooms) do addSlot(config, def, def.x + 3, def.y + 2) end
    config.gate_regions = { { id = "G_shortcut_A2", x1 = 16, y1 = 4, x2 = 18, y2 = 8,
        unlocked = false, unlock_condition = { room_id = "A2", state = "cleared" }, shortcut = true } }
    config.shortcuts = { { id = "shortcut_A2", gate_id = "G_shortcut_A2", from = "A2", to = "logistics",
        unlock_condition = { room_id = "A2", state = "cleared" },
        waypoints = { point(-6, 6), point(25.5, 6) } } }
    addRoute(config, "outer_circuit", {
        stop("C1", 32, 46, 32, 51, 27, 51),
        stop("C2", 14, 62, 14, 65, 9, 65),
        stop("A3", -6, 53, -6, 48, -6, 43),
        stop("A1", -6, 26, -6, 21, -6, 16),
        stop("A2", -6, 5, -6, 0, -1, 0),
        stop("B2", 65, 0, 70, 0, 70, 5),
        stop("B1", 70, 16, 70, 21, 70, 26),
        stop("B3", 70, 43, 70, 48, 70, 53),
        stop("C3", 55, 65, 50, 65, 50, 62),
    }, { 10, 20 })
    addGraph(config, {
        { "core_logistics", "core", "logistics" }, { "core_w", "core", "portal_W" },
        { "core_e", "core", "portal_E" }, { "core_s", "core", "portal_S" },
        { "w_a1", "portal_W", "A1" }, { "a1_a2", "A1", "A2", "A2", { room_id = "A1", state = "cleared" } },
        { "a1_a3", "A1", "A3", "A3", { room_id = "A2", state = "cleared" } },
        { "e_b1", "portal_E", "B1" }, { "b1_b2", "B1", "B2", "B2", { room_id = "B1", state = "cleared" } },
        { "b1_b3", "B1", "B3", "B3", { room_id = "B2", state = "cleared" } },
        { "s_c1", "portal_S", "C1" }, { "c1_c2", "C1", "C2", "C2", { room_id = "C1", state = "cleared" } },
        { "c1_c3", "C1", "C3", "C3", { room_id = "C2", state = "cleared" } },
        { "cross_AB", "A2", "B2", nil, nil, true, { point(0, 0), point(64, 0) } },
        { "cross_AC", "A3", "C2", nil, nil, true, { point(-6, 65), point(8, 65) } },
        { "cross_BC", "B3", "C3", nil, nil, true, { point(70, 65), point(56, 65) } },
        { "c2_c3", "C2", "C3", "C3", { room_id = "C2", state = "cleared" } },
    })
end

---@param id? string
---@return table
function Scenarios.Get(id)
    id = id or "legacy_v02"
    assert(id == "legacy_v02" or id == "reuse_sample" or id == "large_map_proto" or id == "sanctuary_expansion", "unknown_scenario:" .. tostring(id))
    local config = copy(Legacy)
    if id == "legacy_v02" then
        config.scenario_id, config.rules_version = id, "0.2.0"
        config.total_waves, config.final_intro_wave = 20, 20
        config.record_namespace, config.can_record_chapter = "legacy_v02", true
        config.map_origin, config.module_system = point(0, 0), false
        config.declared_ordinary_total, config.declared_special_total = 1176, 0
    elseif id == "reuse_sample" then sample(config)
    elseif id == "sanctuary_expansion" then sample(config); Expansion.Configure(config)
    else large(config) end
    return config
end

function Scenarios.List() return { "legacy_v02", "reuse_sample", "large_map_proto", "sanctuary_expansion" } end
return Scenarios
