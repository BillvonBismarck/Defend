-- 地图生成器回归：S1–S8 / G1–G14、确定性、环路与门。纯 CPU，无引擎/文件依赖。
local T = {}
local Lattice = require("defense.Lattice")
local Topology = require("defense.Topology")

function T.Register(case)
    case("T01_全难度生成并通过校验", function(t)
        for level = 1, 5 do
            local graph = Topology.Generate(1000 + level, level)
            local ok, err = Topology.Validate(graph)
            t:Check(ok, "难度 " .. level .. " 校验:" .. tostring(err))
            t:Check(graph.steps <= Topology.MaxSteps, "步数上限")
        end
    end)

    case("T02_骨架契约", function(t)
        local graph = Topology.Generate(20261008, 3)
        t:Equal(graph.stats.dodeca, 4, "恰好 4 个十二边房（主空间 + 3 核心）")
        t:Equal(graph.byId[graph.main].degree, 3, "主空间度数恒为 3")
        for _, district in ipairs({ "A", "B", "C" }) do
            local info = graph.districts[district]
            t:Check(info.core ~= nil, district .. " 有核心")
            t:Equal(graph.byId[info.core].kind, "dodeca", district .. " 核心是十二边")
            t:Equal(graph.byId[info.gate].kind, "tri", district .. " 闸室是三角")
            t:Check(graph.byId[info.core].degree >= 1, "核心至少 1 条连接")
        end
    end)

    case("T03_房间数与难度单调", function(t)
        for level = 1, 5 do
            local graph = Topology.Generate(77, level)
            local want = 1 + 3 * Topology.Difficulty[level].rooms
            t:Equal(#graph.rooms, want, "难度 " .. level .. " 房间数")
            t:Near(graph.stats.enemy_scale, Topology.Difficulty[level].enemy_scale, "敌人系数")
        end
        local d1, d5 = Topology.Generate(77, 1), Topology.Generate(77, 5)
        t:Check(#d5.rooms > #d1.rooms, "高难度房间更多")
    end)

    case("T04_确定性（同种子同布局）", function(t)
        local a = Topology.Generate(4242, 4)
        local b = Topology.Generate(4242, 4)
        t:Equal(Topology.Fingerprint(a), Topology.Fingerprint(b), "同种子必须完全一致")
        local c = Topology.Generate(4243, 4)
        t:Check(Topology.Fingerprint(a) ~= Topology.Fingerprint(c), "不同种子应产生不同布局")
    end)

    case("T05_环路同型等距闭环（可构造性）", function(t)
        local found = 0
        for seed = 1, 60 do
            local graph = Topology.Generate(seed * 91, 3)
            for _, link in ipairs(graph.links) do
                if link.loop then
                    found = found + 1
                    local a, b = graph.byId[link.a], graph.byId[link.b]
                    t:Check(a.kind == b.kind, "环路必须同型:" .. a.id .. "/" .. b.id)
                    t:Check(Lattice.LegalCorridorLength(link.length), "闭环走廊长度在 [2u,4u]")
                    local dx, dy = b.x - a.x, b.y - a.y
                    t:Near(math.sqrt(dx * dx + dy * dy), 2 * Lattice.Inradius(a.kind) + link.length, "闭环中心距 = 2r + L")
                end
            end
            if found >= 4 then break end
        end
        t:Check(found >= 1, "至少有一个种能构造出精确闭环")
    end)

    case("T05b_环路缺失必须显式降级", function(t)
        local missing, recorded = 0, 0
        for seed = 1, 20 do
            local graph = Topology.Generate(seed * 17, 3)
            local loops = graph.districts.A.loops + graph.districts.B.loops + graph.districts.C.loops
            if loops < Topology.Difficulty[3].clusters then
                missing = missing + 1
                local hasRecord = false
                for _, msg in ipairs(graph.degraded) do
                    if string.find(msg, "loop_skipped") or string.find(msg, "loop_degraded") then hasRecord = true end
                end
                t:Check(hasRecord, "环路缺失时必须有显式降级记录")
                recorded = recorded + 1
            end
        end
        t:Check(missing == recorded, "降级计数一致")
        t:Check(missing <= 20, "合法计数")
    end)

    case("T06_单向锁数量与状态", function(t)
        for level = 1, 5 do
            local graph = Topology.Generate(555, level)
            local gates = 0
            for _, link in ipairs(graph.links) do
                if link.gate then
                    gates = gates + 1
                    t:Equal(link.gate_state, "locked", "门初始锁定")
                end
            end
            t:Equal(gates, Topology.Difficulty[level].gates, "难度 " .. level .. " 门数量")
        end
    end)

    case("T07_传送锚点与六边房一致", function(t)
        local graph = Topology.Generate(908, 5)
        local hexCount = 0
        for _, room in ipairs(graph.rooms) do
            if room.kind == "hex" then hexCount = hexCount + 1 end
        end
        t:Equal(#graph.anchors, hexCount, "每个六边房生成一个锚点")
        for _, id in ipairs(graph.anchors) do
            t:Equal(graph.byId[id].kind, "hex", "锚点只在六边房")
        end
    end)

    case("T08_走廊长度与中心距全量一致", function(t)
        local maxLength, minLength = 0, 99
        for level = 1, 5 do
            local graph = Topology.Generate(2000 + level, level)
            for _, link in ipairs(graph.links) do
                t:Check(Lattice.LegalCorridorLength(link.length), "走廊长度必须落在 [2u,4u]")
                local a, b = graph.byId[link.a], graph.byId[link.b]
                local dx, dy = b.x - a.x, b.y - a.y
                t:Near(math.sqrt(dx * dx + dy * dy), Lattice.CenterDistance(a.kind, b.kind, link.length), "中心距一致")
                maxLength = math.max(maxLength, link.length)
                minLength = math.min(minLength, link.length)
            end
        end
        t:Check(maxLength <= 4 and minLength >= 2, "全图走廊长度区间")
    end)

    case("T09_无重叠且无孤立房间", function(t)
        local graph = Topology.Generate(6161, 5)
        for i = 1, #graph.rooms do
            t:Check(graph.rooms[i].degree >= 1, graph.rooms[i].id .. " 度数至少 1")
            for j = i + 1, #graph.rooms do
                t:Check(not Lattice.RoomsOverlap(graph.rooms[i], graph.rooms[j], 0),
                    "房间不重叠:" .. graph.rooms[i].id .. "/" .. graph.rooms[j].id)
            end
        end
    end)

    case("T10_端口唯一占用", function(t)
        local graph = Topology.Generate(1234, 5)
        for _, room in ipairs(graph.rooms) do
            local used = 0
            for index = 1, #room.ports do
                if room.used[index] then used = used + 1 end
            end
            t:Equal(used, room.degree, room.id .. " 占用端口数等于度数")
        end
        for _, link in ipairs(graph.links) do
            local a, b = graph.byId[link.a], graph.byId[link.b]
            t:Equal(a.used[link.aPort], link.id, "A 端口归属")
            t:Equal(b.used[link.bPort], link.id, "B 端口归属")
        end
    end)

    case("T11_难度表与几何上限一致", function(t)
        for level = 1, 5 do
            local graph = Topology.Generate(8888, level)
            local loops = graph.districts.A.loops + graph.districts.B.loops + graph.districts.C.loops
            t:Check(loops <= Topology.Difficulty[level].clusters * 3, "环路数不超过难度目标")
            if Topology.Difficulty[level].clusters > 0 and loops == 0 then
                t:Check(#graph.degraded > 0, "环路降级必须显式记录")
            end
        end
    end)

    case("T12_大批量种子稳定性", function(t)
        local fails = 0
        for seed = 1, 40 do
            local graph = Topology.Generate(seed * 37, (seed % 5) + 1)
            local ok = Topology.Validate(graph)
            if not ok then fails = fails + 1 end
        end
        t:Equal(fails, 0, "40 个种子全部生成并通过校验")
    end)
end

return T
