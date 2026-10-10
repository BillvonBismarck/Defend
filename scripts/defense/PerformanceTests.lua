-- 性能回归用例检查重复工作与规则隔离，不依赖机器快慢或伪造FPS门槛。
local P = {}
function P.Register(case)
    case("PERF_OPENING", function(t)
        local Run = require("defense.Run")
        local r = Run.New { run_id = "perf-opening", seed = 901 }
        r:FinishStory()
        local clock, hp, currency, rng = r.clock, r.core.hp, r.currency, r.rng.state
        local eventCount = #r.events
        local visits = 0
        local original = r.map.IsWalkable
        r.map.IsWalkable = function(self, ...)
            visits = visits + 1
            return original(self, ...)
        end
        local grid = r.map:GetGrid(0.34)
        t:Equal(visits, 0, "创建寻路网格不在开波帧扫描全图")
        local first = grid.valid[1]
        local before = visits
        t:Equal(grid.valid[1], first, "缓存false格点仍可复用")
        t:Equal(visits, before, "false通行结果不反复计算")
        local cacheWarm = false
        for i = 1, 100 do
            r.map:Warmup(48)
            if r.map.warmupCursor > #r.map.warmupJobs then cacheWarm = true; break end
        end
        t:Check(cacheWarm, "西路路径在预警前完成分帧预热")
        t:Equal(r.clock, clock, "预热不消费世界时间")
        t:Equal(r.core.hp, hp, "预热不造成伤害")
        t:Equal(r.currency, currency, "预热不发奖励")
        t:Equal(r.rng.state, rng, "预热不消费规则随机数")
        t:Equal(#r.events, eventCount, "预热不生成玩法事件")
        local cfg = r.config
        local field = r.map.fields[string.format("%.17g:%.17g:%.17g", cfg.core_position.x, cfg.core_position.y, 0.34)]
        t:Check(field ~= nil, "预热保留核心路径场")
        local cursor = field.cursor
        r:StartAttack()
        r:Update(1 / 60, {})
        t:Equal(field.cursor, cursor, "首个怪物更新不重建已预热BFS")
        t:Equal(r:AliveCount(), 1, "开波数量仍按原生成队列")
        t:Equal(r.current_wave.ordinary, 18, "没有删怪降低开波压力")
    end)
    case("PERF_TARGET", function(t)
        local Run = require("defense.Run")
        local Combat = require("defense.Combat")
        local r = Run.New { run_id = "perf-target", seed = 902 }
        r:FinishStory()
        r.player.x, r.player.y = 32, 25
        for i = 1, 80 do
            Combat.Spawn(r, { role = "advance", portal = "S", x = 32, y = 27 + i * 0.01 })
        end
        local calls = 0
        local original = r.map.LineOfSight
        r.map.LineOfSight = function(self, ...)
            calls = calls + 1
            return original(self, ...)
        end
        local eventId, actionId = r.event_id, r.next_action_id
        local target, info = Combat.ActiveTarget(r)
        t:Check(target ~= nil and info.ok, "密集目标中仍找到最近合法目标")
        t:Equal(target.id, r.enemies[1].id, "排序不改变原最近合法目标规则")
        t:Check(calls <= 4, "首个合法目标找到后不扫描其余79个落点")
        t:Equal(r.event_id, eventId, "纯查询不追加事件")
        t:Equal(r.next_action_id, actionId, "纯查询不分配因果动作")
        calls = 0
        r.map:Move(r.player.x, r.player.y, 0, 0, r.player.radius)
        t:Equal(calls, 0, "零位移不执行两次空轴扫掠")
    end)
end
return P
