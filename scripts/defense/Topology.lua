-- 多边形房间地图生成器（定稿机制 S1–S8 / G1–G14）。
-- 纯 Lua 规则层：由 seed 完全决定布局；不引用引擎/渲染/UI/文件。
-- 环路用"同型三房等边三角环"精确构造：三方向相差 120° 的奇数方向位移之和为零，因此闭合无误差。
local Random = require("defense.Random")
local Lattice = require("defense.Lattice")

local Topology = {}

Topology.Version = "polygon-topology-v1"
Topology.MaxSteps = 400          -- G12 整局步数上限（含回退尝试）
Topology.MaxRetryPerRoom = 4     -- G12 单房重试上限
Topology.LengthOrder = { 3, 2.5, 3.5, 2, 4 }   -- 走廊长度候选（优先 3u）
Topology.ClusterKinds = { "hex" }              -- 环路族：只有六边能构成等边三角环（三角端口 120° 间隔，无法 120° 转折闭合）

---@class TopologyDifficulty
Topology.Difficulty = {
    [1] = { rooms = 3, hex = 1, clusters = 0, gates = 0, boss_waves = 1, enemy_scale = 1.00 },
    [2] = { rooms = 4, hex = 1, clusters = 0, gates = 0, boss_waves = 1, enemy_scale = 1.15 },
    [3] = { rooms = 5, hex = 3, clusters = 1, gates = 1, boss_waves = 2, enemy_scale = 1.30 },
    [4] = { rooms = 6, hex = 3, clusters = 1, gates = 2, boss_waves = 2, enemy_scale = 1.45 },
    [5] = { rooms = 8, hex = 4, clusters = 1, gates = 3, boss_waves = 3, enemy_scale = 1.60 },
}

---@return number 三角环的中心距（三房等边）
function Topology.ClusterStep(kind, length)
    return 2 * Lattice.Inradius(kind) + length
end

-- 端口基数上限（G4）：三角 ≤2、六边 ≤3、十二边 ≤6；群系核心额外限 3
local DEGREE_CAP = { tri = 2, hex = 3, dodeca = 6 }

---@return integer 该房间还能再接几条走廊（同时受端口与度数上限约束）
local function capacity(room)
    local cap = room.role == "district_core" and 3 or (DEGREE_CAP[room.kind] or 6)
    return cap - room.degree
end
local function freePorts(room)
    local cap = room.role == "district_core" and 3 or (DEGREE_CAP[room.kind] or 6)
    local list = {}
    if room.degree >= cap then return list end
    for index = 1, #room.ports do
        if not room.used[index] then list[#list + 1] = index end
    end
    return list
end

local function occupy(room, index, linkId)
    assert(room and room.used, "occupy 需要房间契约字段")
    assert(index and not room.used[index], "端口已被占用:" .. tostring(room.id) .. "#" .. tostring(index))
    room.used[index] = linkId
    room.degree = room.degree + 1
end

local function roomOverlaps(graph, room, margin, ignore)
    for _, other in ipairs(graph.rooms) do
        if other.id ~= ignore and Lattice.RoomsOverlap(room, other, margin) then
            if Topology.Debug then
                local dx, dy = room.x - other.x, room.y - other.y
                print(string.format("[debug] %s(%s) vs %s(%s) dist=%.2f rsum=%.2f",
                    room.id, room.kind, other.id, other.kind, math.sqrt(dx * dx + dy * dy),
                    Lattice.Inradius(room.kind) + Lattice.Inradius(other.kind)))
            end
            return other
        end
    end
    return nil
end

local function corridorBlocked(graph, corridor, ownerA, ownerB)
    for _, other in ipairs(graph.rooms) do
        if Lattice.CorridorHitsRoom(corridor, other, ownerA, ownerB) then return other end
    end
    return nil
end

-- 端口优先级：越朝向"远离主空间"越优先；同分按端口序号。
local function sortedPorts(room)
    local ports = freePorts(room)
    local radial = math.deg(math.atan(room.y, room.x))
    table.sort(ports, function(a, b)
        local ga, gb = Lattice.AngleGap(room.ports[a], radial), Lattice.AngleGap(room.ports[b], radial)
        if math.abs(ga - gb) > 0.0001 then return ga < gb end
        return a < b
    end)
    return ports
end

---@return table|nil room, string|nil err, table|nil info
local function tryPlace(graph, parent, portIndex, kind, length, id, district)
    local room, dir, back = Lattice.Place(parent, portIndex, kind, length, id)
    room.used, room.degree, room.district = {}, 0, district
    room.ports = Lattice.PortNormals(room.kind, room.rotation)
    room.slots = Lattice.Spec(room.kind).slots
    room.slot_kind = Lattice.Spec(room.kind).slot_kind
    local backPort = Lattice.PortIndexFacing(room, back)
    if not backPort then return nil, "no_back_port" end
    local hit = roomOverlaps(graph, room, Lattice.MinGap)
    if hit then return nil, "overlap:" .. hit.id end
    local corridor = Lattice.Corridor(parent, portIndex, room, backPort, length)
    if corridorBlocked(graph, corridor, parent.id, room.id) then return nil, "corridor_blocked" end
    return room, nil, { portIndex = portIndex, back = back, backPort = backPort, length = length, dir = dir }
end

---@return table|nil room, table|nil info 在多个长度/端口上尝试放置
local function placeBest(graph, parent, kind, id, district, lengths, ports)
    local err = "no_port"
    local candidates = ports or sortedPorts(parent)
    for _, length in ipairs(lengths or Topology.LengthOrder) do
        for _, portIndex in ipairs(candidates) do
            if graph.steps < Topology.MaxSteps then
                graph.steps = graph.steps + 1
                local room, placeErr, info = tryPlace(graph, parent, portIndex, kind, length, id, district)
                if room then return room, info end
                err = placeErr
            end
        end
    end
    return nil, nil, err
end

-- 回退支持：移除连接并归还端口占用，移除房间
local function removeLink(graph, link)
    for _, room in ipairs(graph.rooms) do
        if room.id == link.a and room.used[link.aPort] == link.id then
            room.used[link.aPort] = nil
            room.degree = room.degree - 1
        end
        if room.id == link.b and room.used[link.bPort] == link.id then
            room.used[link.bPort] = nil
            room.degree = room.degree - 1
        end
    end
    for index = #graph.links, 1, -1 do
        if graph.links[index].id == link.id then table.remove(graph.links, index) end
    end
end

local function dropRoom(graph, id)
    graph.byId[id] = nil
    for index = #graph.rooms, 1, -1 do
        if graph.rooms[index].id == id then table.remove(graph.rooms, index) end
    end
end

---@return table 生成结果：房间、连接、环路、门、锚点与统计
function Topology.Generate(seed, difficulty)
    local level = difficulty or 3
    local plan = Topology.Difficulty[level]
    assert(plan, "未知难度:" .. tostring(level))
    local rng = Random.New(seed or 20261008)
    local graph = {
        version = Topology.Version, seed = seed or 20261008, difficulty = level,
        rooms = {}, byId = {}, links = {}, districts = {}, anchors = {}, degraded = {},
        steps = 0, linkSeq = 0,
    }

    local function addRoom(room) graph.rooms[#graph.rooms + 1] = room; graph.byId[room.id] = room; return room end
    local function addLink(a, aPort, b, bPort, length, extra)
        graph.linkSeq = graph.linkSeq + 1
        local link = { id = "L" .. graph.linkSeq, a = a.id, b = b.id, aPort = aPort, bPort = bPort, length = length }
        for key, value in pairs(extra or {}) do link[key] = value end
        graph.links[#graph.links + 1] = link
        occupy(a, aPort, link.id)
        occupy(b, bPort, link.id)
        return link
    end
    local function jitter(anchor)
        -- 在优先值附近取一个 [2u,4u] 内的长度，消费随机源，保证 seed 影响布局
        local options = { 2.5, 3, 3.5 }
        local pick = options[rng:Index(#options)]
        if anchor == "short" then pick = math.min(pick, 3) end
        return pick
    end
    local function shuffledLengths()
        local list = { 3, 2.5, 3.5 }
        for index = #list, 2, -1 do
            local swap = rng:Index(index)
            list[index], list[swap] = list[swap], list[index]
        end
        return list
    end

    -- S1 主空间（十二边，度数恒为 3）
    local main = addRoom({
        id = "D0", kind = "dodeca", district = "core", role = "main", rotation = 0, x = 0, y = 0,
        degree = 0, ports = Lattice.PortNormals("dodeca", 0), used = {}, slots = 12, slot_kind = "edge",
    })
    graph.main = main.id

    -- 三个闸室方向：主空间 6 个端口里隔一个取一个，起点由 seed 决定
    local allPorts = Lattice.PortNormals("dodeca", 0)
    local start = rng:Index(3)
    local districtOrder = { "A", "B", "C" }
    for index, district in ipairs(districtOrder) do
        local portIndex = start + (index - 1) * 2
        if portIndex > 6 then portIndex = portIndex - 6 end
        graph.districts[district] = { direction = allPorts[portIndex], rooms = {}, loops = 0, gates = 0,
            core = nil, hex = 0, portIndex = portIndex }
    end

    for _, district in ipairs(districtOrder) do
        local district_ = graph.districts[district]
        local dir, mainPort = district_.direction, district_.portIndex

        -- S2 闸室：三角，必须正对主空间
        local gate, gateInfo, gateErr = placeBest(graph, main, "tri", "T-" .. district, district,
            { Lattice.CorridorPreferred or 3, jitter("short") }, { mainPort })
        assert(gate, "闸室放置失败:" .. district .. " " .. tostring(gateErr))
        gate.role = "gate"
        addRoom(gate)
        addLink(main, mainPort, gate, gateInfo.backPort, gateInfo.length)
        district_.gate = gate.id
        district_.rooms[#district_.rooms + 1] = gate.id

        -- S1 类型序列：环路簇（3 个六边）+ 普通房，总房间数对齐难度表
        local middle = plan.rooms - 2
        local slots = {}
        local clusters = math.min(plan.clusters, math.floor(middle / 2))
        local remaining = middle - clusters * 2
        local wantHex = plan.hex
        local hexPlaced = 0
        for _ = 1, remaining do
            local kind = (hexPlaced < wantHex - clusters * 2) and "hex" or "tri"
            if kind == "hex" then hexPlaced = hexPlaced + 1 end
            slots[#slots + 1] = { kind = kind }
        end
        -- 环簇排在核心之后（核心是全群系最远的房间，环簇挂它最容易闭合）
        for _ = 1, clusters do
            slots[#slots + 1] = { cluster = true, size = 2 }
        end
        local normalCount = #slots - clusters

        -- S3–S6 生成链：先普通房，再核心，最后环簇
        local tail, index = gate, 0
        local corePlaced = false
        while index < #slots do
            local slot = slots[index + 1]
            if slot.cluster then
                break                    -- 环路由后面的专用段落处理
                        else
                local kind = slot.kind or "hex"
                local order = { kind, kind == "hex" and "tri" or "hex" }
                local room, info, placeErr
                for _, candidateKind in ipairs(order) do
                    room, info, placeErr = placeBest(graph, tail, candidateKind, "R-" .. district .. "-" .. tostring(#graph.rooms), district, shuffledLengths())
                    if room then break end
                end
                if room then
                    addRoom(room)
                    addLink(tail, info.portIndex, room, info.backPort, info.length)
                    district_.rooms[#district_.rooms + 1] = room.id
                    if room.kind == "hex" then district_.hex = district_.hex + 1 end
                    tail = room
                else
                    graph.degraded[#graph.degraded + 1] = "room_skipped:" .. tostring(placeErr)
                end
                index = index + 1
            end
        end

        -- 环路：以同型房 P 为第三顶点，补 2 房构成等边三角环 P→A→B→P（闭合无误差）
        while index < #slots do
            local slot = slots[index + 1]
            if not slot.cluster then
                index = index + 1
            else
                local linkMarker = graph.linkSeq
                local placed, ok, lastErr = {}, false, "no_parent"
                local parents = {}
                for _, roomId in ipairs(district_.rooms) do
                    local room = graph.byId[roomId]
                    if room and room.kind == "hex" and #freePorts(room) >= 2 and capacity(room) >= 2 then
                        parents[#parents + 1] = room
                    end
                end
                table.sort(parents, function(a, b)
                    local da, db = a.x * a.x + a.y * a.y, b.x * b.x + b.y * b.y
                    if math.abs(da - db) > 0.001 then return da > db end
                    return a.id < b.id
                end)
                for _, clusterKind in ipairs(Topology.ClusterKinds) do
                    if ok then break end
                    for _, parent in ipairs(parents) do
                        if ok then break end
                        for _, stepLength in ipairs({ 3, 2.5, 3.5, 2, 4 }) do
                            if ok then break end
                            local step = Topology.ClusterStep(clusterKind, stepLength)
                            for _, entryPort in ipairs(sortedPorts(parent)) do
                                if ok then break end
                                for _, sign in ipairs({ 1, -1 }) do
                                    if ok then break end
                                    placed = {}
                                    local firstRoom, firstInfo = placeBest(graph, parent, clusterKind,
                                        "C-" .. district .. "-" .. tostring(#graph.rooms + 1), district,
                                        { stepLength }, { entryPort })
                                    if not firstRoom then lastErr = "first_blocked" else
                                        addRoom(firstRoom)
                                        placed[1] = { room = firstRoom, info = firstInfo, parent = parent }
                                        local axis = parent.ports[firstInfo.portIndex]
                                        local secondPort = nil
                                        for _, candidate in ipairs(freePorts(firstRoom)) do
                                            if Lattice.AngleGap(firstRoom.ports[candidate], Lattice.Norm(axis + sign * 120)) < 0.0001 then secondPort = candidate end
                                        end
                                        local secondRoom, secondErr, secondInfo = nil, "no_turn_port", nil
                                        if secondPort then
                                            secondRoom, secondErr, secondInfo = tryPlace(graph, firstRoom, secondPort, clusterKind, stepLength,
                                                "C-" .. district .. "-" .. tostring(#graph.rooms + 1), district)
                                        end
                                        if secondRoom then
                                            addRoom(secondRoom)
                                            placed[#placed + 1] = { room = secondRoom, info = secondInfo, parent = firstRoom }
                                            local backPort = nil
                                            for _, candidate in ipairs(freePorts(secondRoom)) do
                                                if Lattice.AngleGap(secondRoom.ports[candidate], Lattice.Norm(axis + sign * 240)) < 0.0001 then backPort = candidate end
                                            end
                                            local homePort = nil
                                            for _, candidate in ipairs(freePorts(parent)) do
                                                if Lattice.AngleGap(parent.ports[candidate], Lattice.Norm(axis + sign * 60)) < 0.0001 then homePort = candidate end
                                            end
                                            local dx, dy = secondRoom.x - parent.x, secondRoom.y - parent.y
                                            local distance = math.sqrt(dx * dx + dy * dy)
                                            if backPort and homePort and math.abs(distance - step) < 0.02 then
                                                local corridor = Lattice.Corridor(secondRoom, backPort, parent, homePort, stepLength)
                                                if not corridorBlocked(graph, corridor, secondRoom.id, parent.id) then
                                                    for i = 1, 2 do
                                                        local item = placed[i]
                                                        addLink(item.parent, item.info.portIndex, item.room, item.info.backPort, item.info.length)
                                                    end
                                                    addLink(secondRoom, backPort, parent, homePort, stepLength,
                                                        { loop = true, cluster = clusterKind })
                                                    district_.loops = district_.loops + 1
                                                    ok = true
                                                else
                                                    lastErr = "closing_blocked"
                                                end
                                            else
                                                lastErr = "closing_gap"
                                                if Topology.Debug then
                                                    print(string.format("[gap] parent=%s(%s d=%d) axis=%.0f sign=%+d step=%.3f dist=%.3f back=%s home=%s pports=%s bports=%s",
                                                        parent.id, parent.kind, parent.degree, axis, sign, step, distance,
                                                        tostring(backPort), tostring(homePort),
                                                        tostring(parent.ports[1]) .. "/" .. tostring(parent.ports[2]) .. "/" .. tostring(parent.ports[3]),
                                                        tostring(secondRoom.ports[1]) .. "/" .. tostring(secondRoom.ports[2]) .. "/" .. tostring(secondRoom.ports[3])))
                                                end
                                            end
                                        else
                                            lastErr = tostring(secondErr)
                                        end
                                    end
                                    if not ok then
                                        for li = #graph.links, 1, -1 do
                                            local seq = tonumber(string.match(graph.links[li].id, "^L(%d+)$"))
                                            if seq and seq > linkMarker then removeLink(graph, graph.links[li]) end
                                        end
                                        for _, item in ipairs(placed) do dropRoom(graph, item.room.id) end
                                    end
                                end
                            end
                        end
                    end
                end
                if ok then
                    for i = 1, 2 do
                        district_.rooms[#district_.rooms + 1] = placed[i].room.id
                        if placed[i].room.kind == "hex" then district_.hex = district_.hex + 1 end
                    end
                else
                    graph.degraded[#graph.degraded + 1] = "loop_skipped:" .. district .. ":" .. tostring(lastErr)
                    -- 降级：补 2 个普通房，挂到任意有空闲端口的房间（优先最远）
                    for offset = 1, 2 do
                        local options = {}
                        for _, roomId in ipairs(district_.rooms) do
                            local candidate = graph.byId[roomId]
                            if candidate and #freePorts(candidate) > 0 then options[#options + 1] = candidate end
                        end
                        table.sort(options, function(a, b)
                            local da, db = a.x * a.x + a.y * a.y, b.x * b.x + b.y * b.y
                            if math.abs(da - db) > 0.001 then return da > db end
                            return a.id < b.id
                        end)
                        local room, info, anchor = nil, nil, nil
                        for _, candidate in ipairs(options) do
                            room, info = placeBest(graph, candidate, offset == 2 and "tri" or "hex",
                                "R-" .. district .. "-" .. tostring(#graph.rooms + 1), district)
                            if room then anchor = candidate; break end
                        end
                        if room then
                            addRoom(room)
                            addLink(anchor, info.portIndex, room, info.backPort, info.length)
                            district_.rooms[#district_.rooms + 1] = room.id
                            if room.kind == "hex" then district_.hex = district_.hex + 1 end
                        else
                            graph.degraded[#graph.degraded + 1] = "room_skipped:" .. district
                        end
                    end
                end
                index = index + 1
            end
        end

        -- 群系核心（十二边）：环路铺完后落位，可挂在任意仍有余量的房间上
        local anchors = {}
        for _, roomId in ipairs(district_.rooms) do
            local room = graph.byId[roomId]
            if room and capacity(room) >= 1 and #freePorts(room) >= 1 then anchors[#anchors + 1] = room end
        end
        table.sort(anchors, function(a, b)
            if a.id == tail.id then return true end
            if b.id == tail.id then return false end
            local da, db = a.x * a.x + a.y * a.y, b.x * b.x + b.y * b.y
            if math.abs(da - db) > 0.001 then return da > db end
            return a.id < b.id
        end)
        local core, coreInfo, coreErr = nil, nil, "no_anchor"
        for _, anchor in ipairs(anchors) do
            core, coreInfo, coreErr = placeBest(graph, anchor, "dodeca", "D-" .. district, district)
            if core then
                core.role = "district_core"
                addRoom(core)
                addLink(anchor, coreInfo.portIndex, core, coreInfo.backPort, coreInfo.length)
                district_.core = core.id
                district_.rooms[#district_.rooms + 1] = core.id
                break
            end
        end
        if not core then
            graph.degraded[#graph.degraded + 1] = "core_missing:" .. district .. ":" .. tostring(coreErr)
        end
        district_.normalRooms = normalCount
    end

    -- S7 单向锁：按 seed 顺序在链中段标记门
    local candidates = {}
    for _, link in ipairs(graph.links) do
        local a = graph.byId[link.a]
        if a and a.role ~= "main" and a.role ~= "district_core" then
            candidates[#candidates + 1] = link
        end
    end
    local offset = rng:Index(math.max(1, #candidates))
    local gatesWanted = plan.gates
    for step = 0, #candidates - 1 do
        if gatesWanted <= 0 then break end
        local link = candidates[((offset + step - 1) % #candidates) + 1]
        if not link.gate then
            link.gate, link.gate_state = true, "locked"
            local district_ = graph.districts[graph.byId[link.a].district]
            if district_ then district_.gates = district_.gates + 1 end
            gatesWanted = gatesWanted - 1
        end
    end

    -- S8 内容填充：六边房清空后生成传送锚点
    for _, room in ipairs(graph.rooms) do
        if room.kind == "hex" then graph.anchors[#graph.anchors + 1] = room.id end
    end

    local loops, gates, dodeca = 0, 0, 0
    for _, district in ipairs(districtOrder) do
        district_ = graph.districts[district]
        district_.boss_waves = plan.boss_waves
        district_.loops_wanted = plan.clusters
        loops = loops + district_.loops
        if district_.loops < plan.clusters then
            graph.degraded[#graph.degraded + 1] = "loop_degraded:" .. district
        end
    end
    for _, link in ipairs(graph.links) do
        if link.gate then gates = gates + 1 end
    end
    for _, room in ipairs(graph.rooms) do
        if room.kind == "dodeca" then dodeca = dodeca + 1 end
    end
    graph.stats = {
        rooms = #graph.rooms, links = #graph.links, steps = graph.steps, hex = #graph.anchors,
        loops = loops, gates = gates, dodeca = dodeca, enemy_scale = plan.enemy_scale,
        boss_waves = plan.boss_waves,
    }
    return graph
end

---@return string 房间与连接的可读指纹（用于确定性回归）
function Topology.Fingerprint(graph)
    local rooms = {}
    for _, room in ipairs(graph.rooms) do
        rooms[#rooms + 1] = string.format("%s:%s:%.3f:%.3f:%d:%d", room.id, room.kind, room.x, room.y, room.rotation, room.degree)
    end
    table.sort(rooms)
    local links = {}
    for _, link in ipairs(graph.links) do
        links[#links + 1] = string.format("%s:%s#%d->%s#%d:%.3f%s", link.id, link.a, link.aPort, link.b, link.bPort, link.length,
            link.loop and ":loop" or (link.gate and ":gate" or ""))
    end
    table.sort(links)
    return table.concat(rooms, "|") .. "//" .. table.concat(links, "|")
end

---@return boolean, string 校验 G1–G14（不含表现）
function Topology.Validate(graph)
    local ok, err = pcall(function()
        assert(graph.stats.dodeca == 4, "全图必须恰好 4 个十二边房")
        local main = graph.byId[graph.main]
        assert(main and main.degree == 3, "主空间度数必须为 3")
        for _, room in ipairs(graph.rooms) do
            local cap = room.kind == "tri" and 2 or (room.kind == "hex" and 3 or 6)
            if room.role == "district_core" then cap = 3 end
            assert(room.degree <= cap, room.id .. " 超过度数上限")
            assert(room.degree >= 1, room.id .. " 孤立房间")
            assert(room.district ~= nil, room.id .. " 缺少群系归属")
        end
        for _, link in ipairs(graph.links) do
            local a, b = graph.byId[link.a], graph.byId[link.b]
            assert(a and b, "连接缺少房间")
            assert(Lattice.LegalCorridorLength(link.length), "走廊长度越界:" .. link.id)
            local expect = Lattice.CenterDistance(a.kind, b.kind, link.length)
            local dx, dy = b.x - a.x, b.y - a.y
            assert(math.abs(math.sqrt(dx * dx + dy * dy) - expect) < 0.001, "中心距与走廊长度不一致:" .. link.id)
        end
        for i = 1, #graph.rooms do
            for j = i + 1, #graph.rooms do
                assert(not Lattice.RoomsOverlap(graph.rooms[i], graph.rooms[j], 0),
                    "房间重叠:" .. graph.rooms[i].id .. "/" .. graph.rooms[j].id)
            end
        end
        for _, district in ipairs({ "A", "B", "C" }) do
            local info = graph.districts[district]
            assert(info.core, district .. " 缺少群系核心")
            local core = graph.byId[info.core]
            assert(core.kind == "dodeca", district .. " 核心不是十二边")
            local seen, queue = { [graph.main] = true }, { graph.main }
            while #queue > 0 do
                local id = table.remove(queue, 1)
                for _, link in ipairs(graph.links) do
                    local other = link.a == id and link.b or (link.b == id and link.a or nil)
                    if other and not seen[other] then seen[other] = true; queue[#queue + 1] = other end
                end
            end
            assert(seen[info.core], district .. " 核心不可达")
            assert(seen[info.gate], district .. " 闸室不可达")
            assert(seen[info.gate], district .. " 闸室不可达")
        end
    end)
    if ok then return true, "" end
    return false, tostring(err)
end

return Topology
