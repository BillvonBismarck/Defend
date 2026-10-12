local Run = require("defense.Run")
local Scenarios = require("defense.Scenarios")
local Map = require("defense.Map")
local Combat = require("defense.Combat")
local Anchors = require("defense.Anchors")
local Rooms = require("defense.PolygonRooms")
local Economy = require("defense.Economy")
local WaveDirector = require("defense.WaveDirector")
local Tests = {}
local function fresh(options)
    options = options or {}; options.scenario_id = "polygon_expansion"
    local run = Run.New(options)
    run:FinishStory(); run.pause_reasons = {}; run.state = "PREPARATION"
    return run
end
local function first(run, kind)
    for _, room in ipairs(run.rooms) do if room.kind == kind and room.role ~= "gate" then return room end end
end
local function enter(run, room)
    room.prerequisite = nil; run.map:SetUnlocked(room.id, true); room.accessible = true
    run.player.x, run.player.y = room.x, room.y
    Combat.UpdateRooms(run, 0)
end
local function killRoom(run, room)
    for _, enemy in ipairs(run.enemies) do if enemy.room_id == room.id then enemy.alive, enemy.hp = false, 0 end end
    Combat.UpdateRooms(run, 0)
end
function Tests.Register(case)
    case("POLYGON_REAL_EXPEDITION_MOVE", function(t)
        local run = fresh(); local room = first(run, "hex")
        enter(run, room); killRoom(run, room); killRoom(run, room)
        run.player.x, run.player.y, run.player.damage, run.player.range = 0, 4, 0, 0
        run.player.hp, run.player.invulnerable, run.core.hp = 10000, 10000, 10000
        run.player.max_hp, run.core.max_hp = 10000, 10000
        t:Check(require("defense.Expansion").StartTrial(run, 0), "建立考验路线")
        t:Check(run:RequestWave(), "请求考验波")
        run:Update(8)
        if run.story.node ~= "" then run:FinishStory(); run:Update(8) end
        local unit = run.current_wave.special_units[1]
        local expedition = Combat.Spawn(run, unit)
        t:Check(type(expedition) == "table", "生成真实远征实体")
        local entered, exited, iterations = false, false, 0
        while expedition.alive and expedition.stage ~= "FINAL_ASSAULT" and iterations < 3000 do
            iterations = iterations + 1
            run.clock = run.clock + 0.05
            Combat.Update(run, 0.05, {})
            if expedition.stage == "ROOM_ENGAGED" then entered = true end
            if entered and expedition.stage ~= "ROOM_ENGAGED" then exited = true end
        end
        t:Check(entered, "真实沿路径进入房间")
        t:Check(exited, "12秒交战后真实离房")
        t:Equal(expedition.stage, "FINAL_ASSAULT", "返回核心最终攻势")
        t:Check(iterations < 3000, "路径无卡死")
        t:Equal(run.technical_error, nil, "无卡怪技术异常")
    end)
    case("POLYGON_ENCOUNTER_DOOR", function(t)
        local run = fresh(); local room = first(run, "hex")
        enter(run, room)
        local graphRoom = run.config.topology.byId[room.id]
        local parentId = run.map.neighbors[room.id][1]
        local parent = run.config.topology.byId[parentId]
        local dx, dy = parent.x - graphRoom.x, parent.y - graphRoom.y
        Combat.Displace(run, run.player, dx, dy, 100, { source = "test_fixture" })
        t:Equal(run.map:RoomAt(run.player.x, run.player.y), room.id, "击退不能越过战斗门")
        local count = 0; for _ in pairs(run.active_rooms) do count = count + 1 end
        t:Check(count <= 3, "仅当前房加最多两个相邻房")
    end)
    case("POLYGON_GRAPH_CONTRACT", function(t)
        for difficulty = 1, 5 do
            local c = Scenarios.Get("polygon_expansion", { seed = 97, difficulty = difficulty })
            local ok, report = require("defense.RoomGraph").Check(c)
            t:Check(ok, "完整房间图/槽位/闸门协议:" .. table.concat(report.errors, ","))
        end
    end)
    case("POLYGON_W20_TRIAL", function(t)
        local run = fresh()
        local room = first(run, "hex")
        enter(run, room); killRoom(run, room); killRoom(run, room)
        run.player.x, run.player.y = 0, 4
        run.player.hp, run.player.invulnerable, run.core.hp = 10000, 10000, 10000
        run.player.max_hp, run.core.max_hp = 10000, 10000
        -- 强制击杀夹具只验队列/状态/路线，不代表实战平衡或玩家通关。
        local sawTrial, iterations = false, 0
        while not run.ended and iterations < 12000 do
            iterations = iterations + 1
            if run.story.node ~= "" then run:FinishStory() end
            if run.pause_reasons.upgrade then run:ChooseUpgrade(run.options[1].id) end
            if run.state == "PREPARATION" and not run:IsPaused() then run:RequestWave() end
            run:Update(0.25)
            if run.trial_started then sawTrial = true end
            for _, enemy in ipairs(run.enemies) do
                if enemy.alive and not enemy.room_id then Combat.DamageEnemy(run, enemy, 100000, "test_fixture") end
            end
        end
        t:Check(sawTrial, "W20后进入考验")
        t:Equal(run.result, "victory", "新几何下考验可结算")
        t:Equal(run.technical_error, nil, "无路线技术错误")
        t:Check(iterations < 12000, "状态机不挂起")
        t:Equal(run.wave_id, 21, "独立考验波")
        t:Check(run.meta.stages["defense_polygon_expansion:1:20"] ~= nil, "阶段记录独立命名空间")
        t:Equal(run.meta.stages["defense_sanctuary_expansion:1:20"], nil, "不写旧扩展记录")
    end)
    case("POLYGON_SCENARIO", function(t)
        local c = Scenarios.Get("polygon_expansion", { seed = 99, difficulty = 2 })
        t:Equal(c.scenario_id, "polygon_expansion", "独立场景")
        t:Equal(c.difficulty, 2, "难度显式")
        t:Check(WaveDirector.Validate(c), "20波配置通过原校验")
        local a, b = Scenarios.Get("sanctuary_expansion"), Scenarios.Get("polygon_expansion")
        t:Check(a.record_namespace ~= b.record_namespace, "新旧记录和剧情去重隔离")
        b.enemies.advance.hp = 999
        t:Equal(a.enemies.advance.hp, 20, "旧场景数值不改")
        t:Equal(#a.rooms, 6, "旧场景六房不变")
        t:Equal(#Scenarios.List(), 5, "菜单注册")
    end)
    case("POLYGON_RADIUS_PATHS", function(t)
        for difficulty = 1, 5 do
            for seed = 1, 3 do
                local c = Scenarios.Get("polygon_expansion", { seed = seed * 97, difficulty = difficulty })
                local map = Map.New(c)
                for id in pairs(map.locked or {}) do map:SetUnlocked(id, true) end
                for _, link in ipairs(c.topology.links) do
                    local a, b, unit = c.topology.byId[link.a], c.topology.byId[link.b], c.polygon_unit
                    t:Check(map:LineOfSight(a.x * unit, a.y * unit, b.x * unit, b.y * unit, 0.9), "完整半径无假墙:" .. link.id)
                end
                for _, room in ipairs(c.rooms) do
                    local path = map:Path(room.x, room.y, 0, 0, 0.9)
                    t:Check(path ~= nil, "所有房间可回核心:" .. room.id)
                    for i = 2, #path do
                        local a, b = path[i - 1], path[i]
                        t:Check(map:LineOfSight(a.x, a.y, b.x, b.y, 0.9), "返回路径全部胶囊合法")
                    end
                end
            end
        end
    end)
    case("POLYGON_COLLISION", function(t)
        local run = fresh()
        t:Check(run.map:IsWalkable(0, 4, run.player.radius), "初始点合法")
        t:Check(not run.map:IsWalkable(run.config.map_origin.x, run.config.map_origin.y, 0), "包围盒空白不能走")
        t:Check(not run.map:IsWalkable(0/0, 0, 0), "拒绝NaN")
        local x, y = run.map:Move(0, 4, 500, 500, run.player.radius)
        t:Check(run.map:IsWalkable(x, y, run.player.radius), "高速位移不越墙")
        t:Check(x < 500 and y < 504, "不瞬移到界外")
        for _, def in ipairs(run.config.rooms) do
            for _, id in ipairs(def.defense_slots) do
                for _, slot in ipairs(run.config.build_slots) do
                    if slot.id == id then t:Check(run.map:IsInRegion(def.id, slot.x, slot.y), "槽位在真实房内") end
                end
            end
        end
    end)
    case("POLYGON_ENCOUNTER_IDENTITY", function(t)
        local run, waveBefore = fresh(), nil
        local room = first(run, "hex"); waveBefore = run.wave_id
        enter(run, room)
        t:Equal(room.state, "active", "进入触发战斗")
        t:Equal(room.encounter_wave, 1, "第一波")
        t:Equal(run:AliveCount(), 0, "守军不混入守核计数")
        for _, enemy in ipairs(run.enemies) do t:Equal(enemy.wave_id, nil, "身份独立") end
        killRoom(run, room)
        t:Equal(room.encounter_wave, 2, "第一波不提前清房")
        t:Equal(room.state, "active", "第二波仍交战")
        local bossRole
        for _, enemy in ipairs(run.enemies) do if enemy.alive and enemy.is_boss then bossRole = enemy.role end end
        t:Equal(bossRole, "siege", "第二波不同小Boss")
        killRoom(run, room)
        t:Equal(room.state, "cleared", "两波后清房")
        t:Equal(run.wave_id, waveBefore, "清房不推进守核波")
        t:Equal(run.room_encounter, nil, "房门解除")
        t:Check(run.anchors[room.id].active, "首清激活锚点")
        local enemies = #run.enemies
        Combat.UpdateRooms(run, 0)
        t:Equal(#run.enemies, enemies, "重入不重刷")
    end)
    case("POLYGON_TRI_CORE_WAVES", function(t)
        local run = fresh({ difficulty = 5 })
        local room = first(run, "tri")
        enter(run, room)
        for i = 1, 2 do killRoom(run, room); t:Equal(room.state, "active", "三角前两波不清房") end
        killRoom(run, room); t:Equal(room.state, "cleared", "三角第三波清空")
        run = fresh()
        room = first(run, "dodeca"); enter(run, room)
        local final = false
        for _, enemy in ipairs(run.enemies) do if enemy.role == "final" then final = true end end
        t:Check(final, "地区核心超级Boss")
        killRoom(run, room); t:Equal(room.state, "cleared", "核心一波清空")
    end)
    case("POLYGON_CLEAR_REWARD_ONCE", function(t)
        local run = fresh(); local room = first(run, "hex")
        enter(run, room); killRoom(run, room); killRoom(run, room)
        local before = run.currency
        t:Check(run:ClaimRoom(room.id, "first"), "可领取首清")
        local balance, sand = run.currency, run.exploration_currency
        t:Equal(balance - before, 60, "六边资金奖励")
        t:Equal(sand, 10, "六边星砂奖励")
        t:Check(not run:ClaimRoom(room.id, "second"), "不能再领")
        t:Equal(run.currency, balance, "资金不重复")
        t:Equal(run.exploration_currency, sand, "星砂不重复")
    end)
    case("POLYGON_ANCHOR_PERMISSION", function(t)
        local run = fresh(); local room = first(run, "hex")
        t:Check(not Anchors.Check(run, room.id), "未清不能传送")
        enter(run, room)
        t:Check(not Anchors.Check(run, run.config.topology.main), "交战不能传送")
        killRoom(run, room); killRoom(run, room)
        run.state = "WARNING"; t:Check(not Anchors.Check(run, run.config.topology.main), "预警不可传送")
        run.state = "ATTACK"; t:Check(not Anchors.Check(run, run.config.topology.main), "进攻不可传送")
        run.state = "PREPARATION"; run:Pause("manual")
        t:Check(not Anchors.Check(run, run.config.topology.main), "暂停来源不绕过")
        run:Resume("manual"); run:Pause("map")
        t:Check(Anchors.Check(run, run.config.topology.main), "地图面板可以传送")
    end)
    case("POLYGON_TELEPORT_CLOCK", function(t)
        local run = fresh(); local room = first(run, "hex")
        enter(run, room); killRoom(run, room); killRoom(run, room)
        run.player.active_cd, run.player.attack_cd = 7, 0.4
        run:Pause("map")
        local result = Anchors.Teleport(run, run.config.topology.main, "one")
        t:Check(result.ok, "传送回主空间")
        t:Equal(run.player.active_cd, 7, "不刷新主动冷却")
        t:Equal(run.player.attack_cd, 0.4, "不刷新攻击冷却")
        t:Equal(Anchors.Teleport(run, run.config.topology.main, "one"), result, "重试原结果")
        run:Update(5)
        t:Equal(run.anchor_cooldown, 20, "地图暂停冻结传送冷却")
        run:Resume("map"); run:Update(1)
        t:Near(run.anchor_cooldown, 19, "模拟时间推进冷却")
        t:Check(not Anchors.Teleport(run, room.id, "two").ok, "冷却中拒绝")
    end)
    case("POLYGON_LOCAL_BUILD", function(t)
        local run = fresh(); run.currency = 1000; run:OpenLogistics()
        local mainSlot = run.config.build_slots[1]
        t:Check(Economy.Check(run, "build", mainSlot.id, "rapid"), "主空间就地建造")
        local room = first(run, "hex"); room.state = "cleared"; run.map:SetUnlocked(room.id, true)
        t:Check(not Economy.Check(run, "build", room.defense_slots[1], "rapid"), "拒绝远程建造")
        run.player.x, run.player.y = room.x, room.y
        t:Check(Economy.Check(run, "build", room.defense_slots[1], "rapid"), "本房就地建造")
        local result = run:Transact("build", room.defense_slots[1], "rapid", "build")
        t:Check(result.ok, "交易成功")
        t:Equal(run:Transact("build", room.defense_slots[1], "rapid", "build"), result, "交易幂等")
    end)
    case("POLYGON_FAILURE_PRIORITY", function(t)
        local run = fresh(); local room = first(run, "hex")
        enter(run, room); run.player.hp = 0
        run:Update(0.1)
        t:Equal(run.result, "defeat", "房间死亡全局失败")
        t:Check(not Anchors.Teleport(run, run.config.topology.main, "death").ok, "传送不能救活")
        t:Check(not run.anchors[room.id].active, "失败未发锚点")
    end)
    case("POLYGON_ROOM_GATE", function(t)
        local run = fresh({ difficulty = 3 })
        local locked
        for _, room in ipairs(run.rooms) do if room.prerequisite then locked = room; break end end
        t:Check(locked ~= nil, "存在进度锁")
        t:Check(not run.map:IsWalkable(locked.x, locked.y, 0.6), "清上游前不能进下游")
        for _, room in ipairs(run.rooms) do if room.id == locked.prerequisite then room.state = "cleared" end end
        Rooms.UpdateAccess(run)
        t:Check(run.map:IsWalkable(locked.x, locked.y, 0.6), "清上游后解锁")
    end)
end
return Tests
