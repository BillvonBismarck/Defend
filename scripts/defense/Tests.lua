-- 固定据点规则回归：纯 Lua 5.4，无 Start/引擎/UI/文件写入依赖。
-- 覆盖需求包12的逻辑分支；强制击杀只验队列/结算，不代表构筑实战或18–22分钟实测。
-- V17保留NOT_RUN：预警时钟有断言，但HUD、视觉、声音与真机须另行验收。
-- V10/V20只核对已记录坐标与灰盒规则，不冒充推定几何的原图/画面验收。
-- V18只验演出接线，不验最终分层镜头与声音品质。所有夹具只修改新建测试实例。
local Config = require("defense.Config")
local Run = require("defense.Run")
local Map = require("defense.Map")
local Combat = require("defense.Combat")
local WaveDirector = require("defense.WaveDirector")
local Progression = require("defense.Progression")
local Random = require("defense.Random")
local Tests = {}

---@class DefenseTestContext
---@field assertions integer
local Context = {}
Context.__index = Context
function Context:Init() self.assertions = 0 end
function Context:Check(condition, message)
    self.assertions = self.assertions + 1
    if not condition then error(message or "断言失败", 2) end
end
function Context:Equal(actual, expected, message)
    self:Check(actual == expected, (message or "值不一致") .. ": actual=" .. tostring(actual) .. ", expected=" .. tostring(expected))
end
function Context:Near(actual, expected, message)
    self:Check(type(actual) == "number" and math.abs(actual - expected) <= 0.00001,
        (message or "浮点值不一致") .. ": actual=" .. tostring(actual) .. ", expected=" .. tostring(expected))
end

-- 稳定序列化只用于规则数据，不遍历metatable、不改变被测对象。
local function fingerprint(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = fingerprint(key) .. "=" .. fingerprint(value[key]) end
    return "{" .. table.concat(parts, ";") .. "}"
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
---@return table
local function fresh(options)
    return Run.New(options or { seed = 4701 })
end
---@param r table
local function prepare(r) r:FinishStory(); return r end
---@param r table
local function events(r, kind)
    local found = {}
    for _, e in ipairs(r.events) do if e.kind == kind then found[#found + 1] = e end end
    return found
end
---@param r table
local function room(r, id)
    for _, item in ipairs(r.rooms) do if item.id == id then return item end end
    error("据点不存在：" .. id)
end
---@param t DefenseTestContext
---@param r table
---@return table
local function spawn(t, r, unit)
    local enemy = Combat.Spawn(r, unit)
    t:Check(type(enemy) == "table", "真实Combat.Spawn应成功")
    return enemy --[[@as table]]
end
---@param t DefenseTestContext
---@param r table
local function kill(t, r, enemy)
    t:Check(enemy.alive, "击杀前必须存活")
    t:Check(Combat.DamageEnemy(r, enemy, enemy.hp + 1, "test_force_clear"), "击杀必须提交实际命中")
    t:Equal(enemy.alive, false, "以alive而非DamageEnemy返回值判死亡")
end
---@param t DefenseTestContext
---@param r table
local function killAttack(t, r, keep)
    for _, e in ipairs(r.enemies) do
        if e.alive and not e.room_id and e.wave_id == r.wave_id and e ~= keep then kill(t, r, e) end
    end
end
---@param t DefenseTestContext
---@param r table
local function beginWave(t, r)
    t:Equal(r.state, "PREPARATION", "开波前战备")
    t:Check(r:RequestWave(), "主动开波成功")
    r:Update(8)
    if r.story.node == "final_intro" then
        t:Equal(r.state, "WARNING", "终局演出在预警态冻结")
        t:Check(r:FinishStory(), "结束终局节点")
        t:Near(r.warning_elapsed, 0, "终局后预警重新累计")
        r:Update(8)
    end
    t:Equal(r.state, "ATTACK", "足量预警后进攻")
    t:Check(r.director.started, "队列已启动")
end
-- 逐队列时刻生成真实实体后强制击杀；不靠修改generation_complete伪造完整波次。
---@param t DefenseTestContext
---@param r table
local function forceQueue(t, r, keepLast)
    local director = r.director
    local iterations = 0
    while not director.generation_complete do
        killAttack(t, r)
        director:Update(1, r:AliveCount(), function(unit) return Combat.Spawn(r, unit) and true or false end)
        iterations = iterations + 1
        t:Check(iterations < 200, "队列应有界完成，不可死循环")
    end
    local last = keepLast and r.enemies[#r.enemies] or nil
    killAttack(t, r, last)
    return last
end
---@param t DefenseTestContext
---@param r table
local function clearRoom(t, r, id)
    local item = room(r, id)
    r.player.x, r.player.y = item.x, item.y
    Combat.UpdateRooms(r, 0)
    t:Equal(item.state, "active", "进入激活真实守军")
    for _, e in ipairs(r.enemies) do if e.alive and e.room_id == id then kill(t, r, e) end end
    Combat.UpdateRooms(r, 0)
    t:Equal(item.state, "cleared", "守军清空改变据点态")
    return item
end
---@param r table
local function completedFixture(r, waveId)
    -- 指定清波边界夹具；完整队列执行由V01/V07/V13独立检验。
    r.wave_id = waveId
    r:EnterPreparation()
    r.story_seen.final_intro = true
    r.warning_elapsed = r.config.warning_duration
    r:StartAttack()
    r.director.cursor = #r.director.queue + 1
    r.director.generation_complete = true
end
---@param r table
local function projectile(r, x, y, team)
    local b = { id = r.next_entity_id, x = x, y = y, dx = 0, dy = -1, speed = 10,
        radius = 0.08, remaining = 10, damage = 8, core_damage = 4, team = team or "enemy",
        source = "test_projectile", pierce = 0, blast = 0, frost = 0, hit_ids = {}, alive = true }
    r.next_entity_id = r.next_entity_id + 1
    r.projectiles[#r.projectiles + 1] = b
    return b
end
-- 清波边界必须等待真实有害反应时钟；不删队列、不把待反应计数置零。
---@param t DefenseTestContext
---@param r table
local function settle(t, r)
    r:Update(0.05)
    local steps = 0
    while not r.ended and (r.pending_harmful_reactions or 0) > 0 do
        t:Check(not r:IsPaused(), "清波夹具不应遇到未消费升级暂停")
        r:Update(0.05)
        steps = steps + 1
        t:Check(steps < 1000, "真实危险反应应有界结算")
    end
end
---@param r table
local function economyState(r)
    return fingerprint({ gold = r.currency, hp = r.core.hp, player = r.player.hp,
        uses = r.repair_uses, towers = r.towers })
end

---@type {case:string, test:fun(t:DefenseTestContext), not_run?:string}[]
local cases = {}
---@param fn fun(t:DefenseTestContext)
local function case(id, fn, notRun) cases[#cases + 1] = { case = id, test = fn, not_run = notRun } end

case("V01", function(t)
    local r = prepare(fresh())
    r.player.x, r.player.y = 32, 6 -- 不拾取强制击杀掉落，隔离每波奖励账本。
    local total = 0
    for waveId = 1, 20 do
        t:Equal(r.wave_id, waveId, "连续波序")
        local before = r.currency
        local spawnedBefore = #events(r, "EnemySpawned")
        beginWave(t, r)
        local director = r.director
        total = total + #director.queue
        local last = forceQueue(t, r, waveId == 20)
        t:Equal(director.emitted, #director.queue, "每波全部队列成功生成")
        t:Equal(director:Remaining(), 0, "没有遗漏批次")
        t:Equal(#events(r, "EnemySpawned") - spawnedBefore, #director.queue, "每波真实生成事件计数")
        if last then
            r:Update(0.05)
            t:Equal(r:AliveCount(), 1, "末波确留一只")
            t:Equal(r.ended, false, "末波残留不得胜利")
            t:Equal(r.currency, before, "残留不发清波奖励")
            kill(t, r, last)
        end
        settle(t, r)
        t:Equal(r.currency, before + 12, "每波奖励一次")
        t:Check(r.settled_waves[waveId], "每波结算标记")
        local cleared = events(r, "WaveCleared")
        t:Equal(#cleared, waveId, "结算事件数量等于波序")
        t:Equal(cleared[waveId].data.wave, waveId, "结算事件波号正确")
        r:Update(0.05)
        t:Equal(#events(r, "WaveCleared"), waveId, "重复Update不重复结算")
    end
    t:Equal(total, 1176, "1159普通+14精英+3Boss基数")
    t:Equal(#events(r, "EnemySpawned"), 1176, "实际基数实体总计")
    t:Equal(#events(r, "BossSummoned"), 0, "强制清理流程不冒充召唤实战")
    t:Equal(r.result, "victory", "20波全部清空胜利")
    t:Equal(r.currency, 300, "60初始+240清波奖励")
    t:Equal(#events(r, "StageRecorded"), 4, "5/10/15/20阶段记录")
    t:Equal(#events(r, "RunEnded"), 1, "结局一次")
    t:Check(r.meta.chapters["2"], "首次完整通关解锁下一章")
end)

case("V02", function(t)
    local r = prepare(fresh())
    r.player.x, r.player.y = 32, 6
    completedFixture(r, 10)
    local bossEnemy = spawn(t, r, { role = "commander", portal = "E" })
    Combat.Update(r, 5.1)
    local summoned = events(r, "BossSummoned")
    t:Equal(#summoned, 3, "真实Boss第一轮召唤三只")
    local children = {}
    for _, e in ipairs(r.enemies) do
        if e.summoned_by == bossEnemy.id then
            children[#children + 1] = e
            t:Equal(e.wave_id, 10, "召唤归当前波")
            t:Equal(e.origin_portal, "E", "召唤保存入口")
        end
    end
    t:Equal(#children, 3, "已生成召唤保留")
    kill(t, r, bossEnemy)
    t:Equal(bossEnemy.summon_pending, 0, "Boss死后待召唤清零")
    r:Update(0.05)
    t:Equal(r.wave_id, 10, "已有召唤阻止结束")
    Combat.Update(r, 7)
    t:Equal(#events(r, "BossSummoned"), 3, "死后超过召唤间隔不再召唤")
    t:Equal(r:AliveCount(), 3, "已生成召唤未被删除")
    killAttack(t, r)
    r:Update(0.05)
    t:Equal(r.wave_id, 11, "最后召唤死后清波")
end)

case("V03", function(t)
    for _, kind in ipairs({ "player", "core" }) do
        local r = prepare(fresh())
        completedFixture(r, 20)
        local enemy = spawn(t, r, { role = "final", portal = "S" })
        kill(t, r, enemy)
        r[kind].hp = 0 -- 同一帧提交Boss死亡及死亡输入，交由Run优先检查。
        local gold = r.currency
        r:Update(0.05)
        t:Equal(r:AliveCount(), 0, "同帧末怪死亡")
        t:Equal(r.result, "defeat", kind .. "归零失败优先")
        t:Equal(r.currency, gold, "同帧失败不发清波奖励")
        t:Equal(#events(r, "WaveCleared"), 0, "没有错误胜利结算")
        t:Equal(r:End("victory"), false, "不能改判结局")
        r:Update(1)
        t:Equal(#events(r, "RunEnded"), 1, "失败结局一次")
        t:Equal(r.meta.chapters["2"], nil, "失败不解锁")
    end
    local r = fresh()
    r.core.hp = 0
    r:Update(0.05)
    t:Equal(r.result, "defeat", "演出暂停期间死亡仍即时失败")
end)

case("V04", function(t)
    local r = prepare(fresh())
    beginWave(t, r)
    local e = spawn(t, r, { role = "advance", portal = "S", x = 32, y = 23 })
    local hp = r.core.hp
    Combat.Update(r, 0.05)
    t:Check(r.core.hp < hp, "冻结前核心确实正在受击")
    e.attack_cd, e.stuck_timer = 1, 1
    local b = projectile(r, 32, 25)
    r.player.attack_cd, r.player.active_cd = 3, 7
    r:GrantExperience(95) -- 20+30+40，三次选择后余额5。
    t:Check(r:CheckUpgrade(), "达到阈值打开选择")
    local frozen = fingerprint({ r:Snapshot(), e, b, r.player.attack_cd, r.player.active_cd })
    r:Update(4, { active = true })
    Combat.Update(r, 4, { active = true })
    t:Equal(fingerprint({ r:Snapshot(), e, b, r.player.attack_cd, r.player.active_cd }), frozen,
        "升级冻结时间/耐久/敌人/弹体/队列/冷却/停滞")
    t:Equal(r:ChooseUpgrade("not_a_skill"), false, "非法选择不能消费经验")
    for i = 1, 3 do
        t:Equal(r.state, "UPGRADE_CHOICE", "溢出连续选择" .. i)
        t:Equal(#r.options, 3, "三选一")
        t:Check(r:ChooseUpgrade(r.options[1].id), "合法选择成功")
    end
    t:Equal(r.player.level, 4, "三次升级")
    t:Equal(r.player.experience, 5, "溢出余额不丢失")
    t:Equal(r.state, "ATTACK", "恢复原进攻态")
    t:Equal(r.wave_id, 1, "恢复原波次")
    t:Equal(#events(r, "AttackStarted"), 1, "恢复不重启队列")
    local elapsed = r.director.elapsed
    r:Update(0.05)
    t:Check(r.director.elapsed > elapsed and r.player.active_cd < 7 and b.y < 25, "解除暂停后模拟恢复")
    local p = prepare(fresh())
    p:GrantExperience(20); p:CheckUpgrade()
    local remaining = p.preparation_remaining
    p:Update(5)
    t:Equal(p.preparation_remaining, remaining, "战备升级也冻结倒计时")
    p:ChooseUpgrade(p.options[1].id)
    t:Equal(p.state, "PREPARATION", "战备升级恢复原态")
end)

case("V05", function(t)
    for _, battle in ipairs({ false, true }) do
        local r = prepare(fresh())
        if battle then beginWave(t, r); spawn(t, r, { role = "advance", portal = "S", x = 32, y = 23 }) end
        r:Pause("manual"); r:Pause("focus")
        local before = fingerprint({ r:Snapshot(), r.enemies, r.projectiles })
        r:Update(5)
        t:Equal(fingerprint({ r:Snapshot(), r.enemies, r.projectiles }), before, "嵌套暂停全冻结")
        r:Resume("manual")
        t:Check(r:IsPaused(), "解除一个原因不能恢复")
        local clock, hp = r.clock, r.core.hp
        r:Update(5)
        t:Equal(r.clock, clock, "失焦仍阻止时间")
        t:Equal(r.core.hp, hp, "失焦仍阻止伤害")
        r:Resume("focus")
        t:Equal(r:IsPaused(), false, "最后一个原因解除才恢复")
        r:Update(0.05)
        t:Check(r.clock > clock, "恢复世界时钟")
        t:Equal(r.wave_id, 1, "当前波次保留")
        t:Equal(table.concat(r.current_wave.active_portals), "W", "方向信息保留")
    end
    local r = prepare(fresh())
    t:Check(r:OpenLogistics(), "后勤入口暂停")
    r:Pause("focus"); r:Resume("logistics")
    t:Check(r:IsPaused(), "关闭后勤不解除失焦")
end)

case("V06", function(t)
    for _, input in ipairs({ { elapsed = 0, extra = 8 }, { elapsed = 10, extra = 5 }, { elapsed = 15, extra = 0 } }) do
        local r = prepare(fresh())
        r:Update(input.elapsed)
        local before = r.clock
        if input.extra > 0 then
            t:Check(r:RequestWave(), "提前开波请求")
            t:Near(8 - r.warning_elapsed, input.extra, "准确补足预警")
            t:Equal(r:RequestWave(), false, "重复请求不能重启")
            r:Update(input.extra - 0.1)
            t:Equal(r.state, "WARNING", "不足累计8秒不生成")
            t:Equal(r.director.emitted, 0, "不足预警队列未生成")
            r:Update(0.1)
        end
        t:Equal(r.state, "ATTACK", "累计8秒启动进攻")
        t:Near(r.clock - before, input.extra, "t0/t10/自然补足8/5/0")
        t:Near(r.warning_elapsed, 8, "有效方向提示累计8秒")
        t:Equal(#events(r, "AttackStarted"), 1, "队列启动一次")
        t:Equal(r:StartAttack(), false, "重复StartAttack不重置")
    end
end)

case("V07", function(t)
    local r = prepare(fresh())
    beginWave(t, r)
    killAttack(t, r)
    t:Equal(r:AliveCount(), 0, "队列延期时可以暂时无活怪")
    r:Update(0.05)
    t:Equal(r.wave_id, 1, "尚有待生成批次不得清波")
    t:Equal(r.director.generation_complete, false, "队列未完成")
    local last = forceQueue(t, r, true)
    t:Check(last ~= nil, "完成队列后保留真实活怪")
    r:Update(0.05)
    t:Equal(r.wave_id, 1, "生成完成但有活怪不得清波")
    kill(t, r, last)
    r:Update(0.05)
    t:Equal(r.wave_id, 2, "完成且无活怪才清波")
end)

case("V08", function(t)
    local r = prepare(fresh())
    beginWave(t, r)
    clearRoom(t, r, "A1")
    r:Update(0.05)
    t:Equal(r.wave_id, 1, "清据点不清进攻波")
    t:Check(r:AliveCount() > 0, "进攻怪仍存活")
    local other = prepare(fresh())
    completedFixture(other, 1)
    other.player.x, other.player.y = 8, 21
    Combat.UpdateRooms(other, 0)
    t:Equal(#room(other, "A1").guard_ids, 4, "真实据点守军存在")
    t:Equal(other:AliveCount(), 0, "守军不计入进攻怪")
    other:Update(0.05)
    t:Equal(other.wave_id, 2, "守军不阻止合法清波")
    t:Equal(room(other, "A1").state, "active", "清波不删除据点守军")
end)

case("V09", function(t)
    local r = prepare(fresh())
    r.player.x, r.player.y = 8, 21
    Combat.UpdateRooms(r, 0)
    local guard = r.enemies[1]
    local id, count = guard.id, #r.enemies
    t:Check(Combat.DamageEnemy(r, guard, 5, "test_partial"), "DamageEnemy true表示命中而非死亡")
    t:Check(guard.alive, "部分伤害不得误判击杀")
    local hp = guard.hp
    r.player.x, r.player.y = 32, 6; Combat.UpdateRooms(r, 0)
    r.player.x, r.player.y = 8, 21; Combat.UpdateRooms(r, 0)
    t:Equal(guard.id, id, "重入保留实体")
    t:Equal(guard.hp, hp, "重入保留受损生命")
    t:Equal(#r.enemies, count, "重入不双生成守军")
    for _, e in ipairs(r.enemies) do if e.alive and e.room_id == "A1" then kill(t, r, e) end end
    Combat.UpdateRooms(r, 0)
    t:Equal(room(r, "A1").state, "cleared", "清空未领取态")
    t:Check(room(r, "A2").unlocked and r.map:IsWalkable(8, 6, 0.35), "未领奖即解锁二级")
    local before = r.currency
    t:Check(r:ClaimRoom("A1"), "一级领取成功")
    t:Equal(r.currency, before + 40, "资金40只入账一次")
    t:Equal(r.player.experience, 20, "经验20即时入账")
    t:Equal(r:ClaimRoom("A1"), false, "重复请求不能领奖")
    if r.pause_reasons.upgrade then r:ChooseUpgrade(r.options[1].id) end
    for _ = 1, 3 do
        r.player.x, r.player.y = 32, 6; Combat.UpdateRooms(r, 0)
        r.player.x, r.player.y = 8, 21; Combat.UpdateRooms(r, 0)
        t:Equal(r:ClaimRoom("A1"), false, "反复进出不得重领奖")
    end
    t:Equal(#events(r, "RoomRewardClaimed"), 1, "据点奖励事件幂等")
end)

case("V10", function(t)
    local r = prepare(fresh())
    local baseline = {}
    local function verifyPaths()
        for _, portal in ipairs({ "W", "E", "S" }) do
            for _, radius in ipairs({ 0.35, 0.9 }) do
                local p = Config.portals[portal]
                local path = r.map:Path(p.x, p.y, 32, 21, radius)
                t:Check(path and #path >= 2, portal .. "实际地图到固定核心可达")
                t:Near(path[1].x, p.x, "路径起点精确")
                t:Near(path[#path].y, 21, "路径终点精确")
                for i = 2, #path do
                    local a, b = path[i - 1], path[i]
                    t:Check(r.map:LineOfSight(a.x, a.y, b.x, b.y, radius), "每一段全半径合法绕柱")
                    local x, y = r.map:Move(a.x, a.y, b.x - a.x, b.y - a.y, radius)
                    t:Near(x, b.x, "沿路径实际移动不被卡死X")
                    t:Near(y, b.y, "沿路径实际移动不被卡死Y")
                end
                local key = portal .. tostring(radius)
                if baseline[key] then t:Equal(fingerprint(path), baseline[key], "设施/尸体/掉落不改变路径")
                else baseline[key] = fingerprint(path) end
            end
        end
    end
    verifyPaths()
    r.currency = 1000; r:OpenLogistics()
    for _, slot in ipairs(Config.build_slots) do
        t:Check(r:Transact("build", slot.id, "rapid", "path_build_" .. slot.id).ok, "四槽实际建造")
        local x, y = r.map:Move(slot.x - 1, slot.y, 2, 0, r.player.radius)
        t:Near(x, slot.x + 1, "角色可穿越塔槽不互相卡死")
        t:Near(y, slot.y, "塔槽移动纵坐标")
    end
    verifyPaths()
    r:Resume("logistics")
    for _, tower in ipairs(r.towers) do tower.hp = 0 end -- 损毁设施状态输入，不新增地图障碍。
    local e = spawn(t, r, { role = "advance", portal = "W", x = 27, y = 14 })
    kill(t, r, e)
    verifyPaths()
    t:Equal(r.map:LineOfSight(23, 21, 29, 21, 0.35), false, "左柱不能穿透")
    t:Equal(r.map:LineOfSight(35, 21, 42, 21, 0.35), false, "右柱不能穿透")
    for _, endpoints in ipairs({ { 23, 21, 29, 21 }, { 35, 21, 42, 21 } }) do
        local path = r.map:Path(endpoints[1], endpoints[2], endpoints[3], endpoints[4], 0.35)
        t:Check(path and #path > 2, "角色实际绕柱路径")
    end
    r:Update(0.05, { x = 1 })
    t:Equal(r.core.x, 32, "移动/设施损毁不迁移核心X")
    t:Equal(r.core.y, 21, "移动/设施损毁不迁移核心Y")
end)

case("V11", function(t)
    local r = prepare(fresh())
    local function reject(action, slot, tower, id)
        local before = economyState(r)
        local result = r:Transact(action, slot, tower, id)
        t:Equal(result.ok, false, "非法交易应拒绝：" .. action)
        t:Check(type(result.reason) == "string" and #result.reason > 0, "菜单可使用拒绝原因")
        t:Equal(economyState(r), before, "非法交易无资金/次数/设施副作用")
    end
    reject("repair", nil, nil, "closed")
    t:Check(r:OpenLogistics(), "合法打开后勤")
    reject("repair", nil, nil, "full_core")
    reject("heal", nil, nil, "full_player")
    r.core.hp, r.currency = 900, 39
    reject("repair", nil, nil, "poor_repair")
    reject("build", "T1", "rapid", "poor_build")
    reject("build", "BAD", "rapid", "bad_slot")
    reject("build", "T1", "BAD", "bad_tower")
    reject("repair", nil, nil, nil)
    r.currency, r.core.hp = 1000, 950
    local first = r:Transact("repair", nil, nil, "repair1")
    t:Check(first.ok, "修复1合法")
    t:Equal(r.core.hp, 1000, "修复封顶")
    local before = economyState(r)
    t:Equal(r:Transact("repair", nil, nil, "repair1"), first, "重复ID返回原交易")
    t:Equal(economyState(r), before, "重复ID不双扣")
    r.core.hp = 300
    for i = 2, 3 do t:Check(r:Transact("repair", nil, nil, "repair" .. i).ok, "修复次数2/3合法") end
    t:Equal(r.repair_uses, 3, "最多三次")
    t:Equal(r.currency, 880, "修复总支出120")
    t:Equal(r.core.hp, 700, "后两次各修复200")
    reject("repair", nil, nil, "repair4")
    r.player.hp = 90
    t:Check(r:Transact("heal", nil, nil, "heal1").ok, "治疗合法")
    t:Equal(r.player.hp, 100, "治疗按Q09封顶")
    t:Check(r:Transact("build", "T1", "rapid", "build1").ok, "空槽建造")
    reject("build", "T1", "slow", "occupied")
    r.state = "WARNING"; reject("heal", nil, nil, "warning")
    r.state = "ATTACK"; reject("demolish", "T1", nil, "battle")
end)

case("V12", function(t)
    for _, towerType in ipairs({ "rapid", "slow", "area" }) do
        local r = prepare(fresh())
        r.currency = 1000; r:OpenLogistics()
        local d = Config.towers[towerType]
        t:Check(r:Transact("build", "T1", towerType, "build").ok, "建造" .. towerType)
        for i = 1, 2 do t:Check(r:Transact("upgrade", "T1", nil, "up" .. i).ok, "两次升级合法") end
        local tower = r.towers[1]
        t:Equal(tower.upgrade_count, 2, "升级上限2")
        t:Equal(tower.total_spend, d.cost + d.upgrade * 2, "累计支出含两次升级")
        local before = economyState(r)
        t:Equal(r:Transact("upgrade", "T1", nil, "up3").ok, false, "第三次拒绝")
        t:Equal(economyState(r), before, "第三次无副作用")
        local gold = r.currency
        local result = r:Transact("demolish", "T1", nil, "normal_remove")
        t:Check(result.ok, "正常塔可拆除")
        t:Equal(result.refund, math.floor((d.cost + d.upgrade * 2) * 0.5), "满耐久返累计支出50%")
        t:Equal(r.currency, gold + result.refund, "返款实际入账")
        t:Equal(#r.towers, 0, "拆除移出槽")
        r:Transact("demolish", "T1", nil, "normal_remove")
        t:Equal(r.currency, gold + result.refund, "重复拆除不双返")
        for _, damage in ipairs({ 1, d.hp }) do
            t:Check(r:Transact("build", "T1", towerType, "damaged_build" .. damage).ok, "损坏塔夹具实际建造")
            r.towers[1].hp = d.hp - damage
            local saved = r.currency
            local remove = r:Transact("demolish", "T1", nil, "damaged_remove" .. damage)
            t:Equal(remove.refund, 0, "受损或已摧毁塔按Q09返0")
            r:Transact("demolish", "T1", nil, "damaged_remove" .. damage)
            t:Equal(r.currency, saved, "损坏塔重复拆除无收益")
        end
    end
    local config = copy(Config); config.towers.rapid.cost = 81
    local odd = prepare(fresh({ config = config })); odd.currency = 200; odd:OpenLogistics()
    odd:Transact("build", "T1", "rapid", "odd")
    t:Equal(odd:Transact("demolish", "T1", nil, "odd_remove").refund, 40, "奇数累计成本向下取整")
end)

case("V13", function(t)
    local r = prepare(fresh())
    r.player.x, r.player.y = 32, 6
    r.wave_id = 19; r:EnterPreparation(); r.warning_elapsed = 8; r:StartAttack()
    local director, emitted = r.director, 0
    local original = fingerprint(director.queue)
    local function generate(unit)
        if Combat.Spawn(r, unit) then emitted = emitted + 1; return true end
        return false
    end
    t:Equal(director:Update(100, 0, generate), 80, "同帧多批次最多生成80")
    t:Equal(r:AliveCount(), 80, "实际存活80")
    local cursor = director.cursor
    t:Equal(director:Update(1, 80, generate), 0, "到软上限延期")
    t:Equal(director.cursor, cursor, "延期不跳队首")
    t:Equal(director:Remaining(), 30, "全部待生成30只保留")
    t:Equal(director.generation_complete, false, "延期不伪造完成")
    t:Check(director.blocked and director.delayed > 0, "延期状态可观察")
    r:Update(0.05)
    t:Equal(r.wave_id, 19, "软上限期间不误清波")
    local dead = 0
    for _, e in ipairs(r.enemies) do if e.alive and dead < 20 then kill(t, r, e); dead = dead + 1 end end
    t:Equal(director:Update(1, r:AliveCount(), generate), 20, "杀20只后续生成20")
    dead = 0
    for _, e in ipairs(r.enemies) do if e.alive and dead < 20 then kill(t, r, e); dead = dead + 1 end end
    t:Equal(director:Update(1, r:AliveCount(), generate), 10, "剩余10批次继续生成")
    t:Equal(emitted, 110, "108普通+2精英没有丢单位")
    t:Equal(fingerprint(director.queue), original, "延期没有删除或修改原队列")
    t:Check(director.generation_complete, "全部生成才完成")
    killAttack(t, r); settle(t, r)
    t:Equal(r.wave_id, 20, "最后活怪清空后进入20波战备")
end)

case("V14", function(t)
    local r = prepare(fresh())
    r.player.x, r.player.y = 8, 21
    t:Equal(r:RequestRecall(), false, "未清据点不能回城")
    clearRoom(t, r, "A1")
    t:Check(r:RequestRecall(), "已清未领奖即可引导")
    r:Update(0.5)
    t:Near(r.recall.progress, 0.5, "真实引导进度")
    projectile(r, r.player.x, r.player.y)
    local hp = r.player.hp
    r:Update(0.05)
    t:Check(r.player.hp < hp, "真实弹体造成受击")
    t:Equal(r.recall.active, false, "受击取消引导")
    t:Check(r:RequestRecall(), "取消后可以重新请求")
    r:Update(0.05, { x = 1 })
    t:Equal(r.recall.active, false, "移动取消引导")
    t:Check(r:RequestRecall(), "战备可再次请求")
    t:Check(r:RequestWave(), "提前开波")
    t:Equal(r.recall.active, false, "跨入WARNING取消")
    t:Equal(r:RequestRecall(), false, "WARNING禁回城")
    r:Update(8)
    t:Equal(r:RequestRecall(), false, "ATTACK禁回城")
    local natural = prepare(fresh())
    clearRoom(t, natural, "A1")
    natural:Update(14.9)
    t:Check(natural:RequestRecall(), "战备末尾允许开始引导")
    natural:Update(0.2)
    t:Equal(natural.state, "ATTACK", "引导不能延长战备")
    t:Equal(natural.recall.active, false, "自然开波取消跨状态引导")
    local success = prepare(fresh()); clearRoom(t, success, "A1")
    success:RequestRecall(); success:Update(1.5)
    t:Near(success.player.x, 32, "引导完成只移动角色X")
    t:Near(success.player.y, 6, "引导完成回城Y")
    t:Equal(success.core.y, 21, "回城不移动核心")
end)

case("V15", function(t)
    local r = prepare(fresh())
    r.player.x, r.player.y = 32, 6
    local e = spawn(t, r, { role = "advance", portal = "W", x = 18, y = 21 })
    e.hp, e.stuck_timer = 7, 2.9
    local pathCalls, portalCalls = 0, 0
    -- 此用例唯一地图mock：强制“寻路失败且位移为0”，入口恢复仍由Combat执行。
    r.map = {
        RoomAt = function() return nil end,
        IsWalkable = function() return true end,
        LineOfSight = function() return false end,
        Move = function(_, x, y) return x, y end,
        Path = function() pathCalls = pathCalls + 1; return nil end,
        PortalPoint = function(_, id) portalCalls = portalCalls + 1; t:Equal(id, "W", "恢复请求同入口"); return 17, 21 end,
        SetUnlocked = function() return false end,
    }
    r:Pause("manual"); r:Update(5)
    t:Near(e.stuck_timer, 2.9, "暂停不积累停滞")
    r:Resume("manual"); r:Update(0.2)
    t:Check(pathCalls >= 2, "先常规寻路再恢复重寻路")
    t:Equal(portalCalls, 1, "仍失败才同入口回迁")
    t:Near(e.x, 17, "回迁入口X")
    t:Near(e.y, 21, "回迁入口Y")
    t:Equal(e.hp, 7, "回迁保留受损HP")
    t:Equal(e.wave_id, 1, "回迁保留wave_id")
    t:Check(e.alive and r.enemies[1] == e, "不删除不替换卡怪")
    local recovered = events(r, "StuckRecovered")
    t:Equal(#recovered, 1, "恢复事件可诊断")
    t:Equal(recovered[1].data.old_x, 18, "恢复日志带原位置")
end)

case("V16", function(t)
    local function legal(r, options)
        t:Equal(#options, 3, "合法三候选")
        local seen = {}
        for _, o in ipairs(options) do
            t:Equal(seen[o.id], nil, "候选ID不重复")
            seen[o.id] = true
            local d = Progression.Find(o.id)
            t:Check(d ~= nil, "候选真实存在")
            if d.max then
                t:Check((r.player.skills[o.id] or 0) < d.max, "满级项移出")
                t:Check(r.player.level >= (d.min_upgrade or 1), "第3次协同门槛")
                t:Check(not d.prerequisite or (r.player.skills[d.prerequisite] or 0) > 0, "前置合法")
            end
        end
        return seen
    end
    for _, build in ipairs({ "single", "area", "control" }) do
        local r = fresh({ build = build, seed = 17 })
        local options = Progression.Options(r, r.rng)
        legal(r, options)
        local covered = false
        for _, o in ipairs(options) do if o.group == "area" or o.group == "control" then covered = true end end
        t:Check(covered, "第1次保证范围或控制")
    end
    local r = fresh()
    for _, d in ipairs(Progression.skills) do r.player.skills[d.id] = d.max end
    r.player.skills.synergy = 0
    r.player.level = 2
    local second = legal(r, Progression.Options(r, r.rng))
    t:Equal(second.synergy, nil, "第2次不能出现协同")
    r.player.level = 3
    local third = legal(r, Progression.Options(r, r.rng))
    t:Check(third.synergy, "第3次协同可进入合法池")
    r.player.skills.synergy = 4
    local fallback = legal(r, Progression.Options(r, r.rng))
    t:Check(fallback.heal_bonus and fallback.gold_bonus and fallback.cooldown_bonus, "不足池以三个不同fallback补齐")
    r.player.skills = {}
    local absent = legal(r, Progression.Options(r, r.rng))
    t:Equal(absent.pierce, nil, "缺power前置无pierce")
    t:Equal(absent.relay, nil, "缺pulse前置无relay")
    t:Equal(Progression.Apply(r, "not_a_skill"), false, "不存在的技能不能应用")
end)

case("V17", function(t)
    local r = prepare(fresh())
    r.player.x, r.player.y = 32, 6
    local e = spawn(t, r, { role = "commander", portal = "S", x = 32, y = 25 })
    e.area_cd = 0
    Combat.Update(r, 0.05)
    local warning = events(r, "AttackWarning")
    t:Equal(#warning, 1, "真实Boss预警事件")
    t:Check(warning[1].data.duration >= 0.7, "预警寿命至少0.7秒")
    t:Equal(e.warning_kind, "area", "范围攻击先预警")
    local hp = r.core.hp
    Combat.Update(r, 0.6)
    t:Equal(r.core.hp, hp, "预警不足0.7秒不打核心")
    local timer = e.warning_timer
    r:Pause("focus"); Combat.Update(r, 2)
    t:Equal(e.warning_timer, timer, "暂停冻结攻击预警时钟")
    r:Resume("focus"); Combat.Update(r, 0.11)
    t:Check(r.core.hp < hp, "足量有效预警后真实伤害")
    t:Equal(#events(r, "AttackWarning"), 1, "一次预警不重复发")
end, "NOT_RUN: 已测Boss预警时钟；HUD常驻、危急遮挡、入口视觉、音效及真机可读性未执行")

case("V18", function(t)
    local r = fresh()
    local deployed = fingerprint(r:Snapshot())
    r:Update(20)
    t:Equal(fingerprint(r:Snapshot()), deployed, "开场世界冻结")
    r:PresentationUpdate(13.9)
    t:Equal(r.state, "DEPLOY", "开场自然未到节点结尾")
    r:PresentationUpdate(0.1)
    t:Equal(r.state, "PREPARATION", "完整演出交接战备")
    local revision = r.meta.revision
    t:Equal(r:FinishStory(), false, "重复结束节点不执行副作用")
    t:Equal(r.meta.revision, revision, "重复结束不双保存")
    t:Equal(#events(r, "PreparationStarted"), 1, "开场不双部署")
    local skip = fresh(); t:Check(skip:FinishStory(), "跳过开场")
    t:Equal(skip.state, r.state, "跳过和完整结束任务态一致")
    t:Equal(skip.core.x, r.core.x, "跳过不移动核心")
    local retry = fresh({ retry = true })
    t:Equal(retry.story.duration, 3, "重试短版3秒")
    retry:PresentationUpdate(3); t:Equal(retry.state, "PREPARATION", "短版合法交接")
    t:Check(r:ReplayStory("opening"), "已记录节点可回看")
    local replay = fingerprint(r:Snapshot())
    r:Update(2)
    t:Equal(fingerprint(r:Snapshot()), replay, "回看关键停顿冻结")
    r:FinishStory()
    t:Equal(r.meta.revision, revision, "回看不执行存档副作用")
    t:Equal(#events(r, "PreparationStarted"), 1, "回看不重部署")
    r.wave_id = 20; r:EnterPreparation(); r:RequestWave(); r:Update(8)
    t:Equal(r.story.node, "final_intro", "本局终局节点触发")
    local final = fingerprint(r:Snapshot())
    r:Update(2)
    t:Equal(fingerprint(r:Snapshot()), final, "终局演出冻结队列和时钟")
    t:Check(r:FinishStory(), "跳过终局登场")
    t:Near(r.warning_elapsed, 0, "终局后完整预警重新累计")
    r:Update(7.9)
    t:Equal(r.director.emitted, 0, "7.9秒未生成")
    r:Update(0.1)
    t:Equal(r.state, "ATTACK", "完整8秒后恢复进攻")
    local cursor, started = r.director.cursor, #events(r, "AttackStarted")
    t:Check(r:ReplayStory("final_intro"), "战斗回看终局登场")
    r:Update(2); r:FinishStory()
    t:Equal(r.state, "ATTACK", "回看保持原态")
    t:Equal(r.director.cursor, cursor, "回看不双生成")
    t:Equal(#events(r, "AttackStarted"), started, "回看不重启攻击")
    r:Pause("menu")
    t:Check(r:ReplayStory("opening"), "菜单暂停中允许显式回看")
    local clock, queued = r.clock, r.director.cursor
    r:PresentationUpdate(1)
    t:Near(r.story.elapsed, 1, "回看可以独立于菜单推进")
    for _, reason in ipairs({ "manual", "rules", "focus" }) do
        r:Pause(reason)
        r:PresentationUpdate(2)
        t:Near(r.story.elapsed, 1, "回看仍冻结于暂停源：" .. reason)
        r:Resume(reason)
    end
    r:PresentationUpdate(13)
    t:Equal(r.story.node, "", "菜单回看自然完成")
    t:Check(r.pause_reasons.menu, "完成回看保留菜单暂停")
    r:Update(2)
    t:Equal(r.clock, clock, "回看完成不意外推进世界")
    t:Equal(r.director.cursor, queued, "回看完成不双生成")
    t:Equal(r.meta.revision, revision + 1, "终局seen仅保存一次，回看不保存")
    r:Pause("manual")
    r:Resume("menu"); t:Check(r:IsPaused(), "关闭菜单仍保留手动暂停")
    r:Resume("manual"); t:Equal(r:IsPaused(), false, "所有原因解除才恢复")
    r:End("victory", "节点结算夹具")
    local gold = r.currency
    t:Equal(r:End("victory"), false, "结算副作用一次")
    r:PresentationUpdate(14)
    t:Check(r.story_seen.ending, "收束节点完整结束")
    t:Equal(r.currency, gold, "收束不重领奖")
    t:Equal(r.core.x, 32, "全节点核心固定X")
    t:Equal(r.core.y, 21, "全节点核心固定Y")
    -- 新局首次opening未完成，但持久记录允许菜单回看已见final_intro。
    local old = fresh({ meta = { schema_version = 1, revision = 7, stages = {},
        chapters = { ["1"] = true }, story_seen = { final_intro = true } } })
    old:PresentationUpdate(1)
    local original = old.story
    local state, time, revisionBefore = old.state, old.clock, old.meta.revision
    t:Equal(old:ReplayStory("final_intro"), false, "非菜单不覆盖首次演出")
    old:Pause("menu"); old:Pause("manual")
    t:Equal(old:ReplayStory("not_seen"), false, "未见节点不允许回看")
    t:Check(old:ReplayStory("final_intro"), "菜单回看明确请求已见节点")
    t:Equal(old.pause_reasons.manual, nil, "显式请求回看暂存调用前手动暂停")
    t:Equal(old.story.node, "final_intro", "不是错播未完opening")
    t:Equal(old.story.replay, true, "回看标记明确")
    old:PresentationUpdate(1)
    old:Pause("manual")
    old:PresentationUpdate(2)
    t:Near(old.story.elapsed, 1, "播放中再次手动暂停真实冻结")
    old:Resume("manual")
    old:PresentationUpdate(7)
    t:Equal(old.story, original, "回看结束恢复原opening实例和剩余时限")
    t:Near(old.story.elapsed, 1, "原opening不在回看期间暗中推进")
    t:Equal(old.state, state, "回看不部署或改任务态")
    t:Equal(old.clock, time, "回看不改世界时钟")
    t:Equal(old.meta.revision, revisionBefore, "回看不重复保存seen")
    t:Equal(#events(old, "PreparationStarted"), 0, "回看不抢原opening副作用")
    t:Check(old.pause_reasons.menu and old.pause_reasons.story and old.pause_reasons.manual,
        "回看结束恢复调用前manual，原演出与菜单暂停均保持")
    old:Resume("menu")
    old:PresentationUpdate(13)
    t:Equal(old.state, state, "回看恢复的manual不因关闭菜单意外消失")
    old:Resume("manual")
    old:PresentationUpdate(13)
    t:Equal(old.state, "PREPARATION", "恢复原opening自然结束才部署")
    t:Equal(#events(old, "PreparationStarted"), 1, "部署副作用只执行一次")
    t:Equal(old.meta.revision, revisionBefore + 1, "首次opening结束仅一次记录")
end)

case("V19", function(t)
    local r = prepare(fresh())
    r.player.x, r.player.y = 32, 6
    for _ = 1, 5 do beginWave(t, r); forceQueue(t, r); settle(t, r) end
    t:Check(r.meta.stages["1:5"].completed, "实际完成5波记录阶段")
    r.currency = 1000; r:OpenLogistics(); r:Transact("build", "T1", "rapid", "old_tower"); r:Resume("logistics")
    clearRoom(t, r, "A1"); r:ClaimRoom("A1")
    if r.pause_reasons.upgrade then r:ChooseUpgrade(r.options[1].id) end
    r.player.experience, r.currency = 17, 1
    r.core.hp = 0; r:Update(0.05)
    t:Equal(r.result, "defeat", "完成阶段后失败")
    local nextRun = fresh({ meta = r.meta, retry = true })
    t:Check(nextRun.meta.stages["1:5"].completed, "新实例保留阶段记录")
    t:Equal(nextRun.player.experience, 0, "本局经验重置")
    t:Equal(nextRun.player.level, 1, "本局等级重置")
    t:Equal(fingerprint(nextRun.player.skills), fingerprint({ power = 1, pierce = 1 }), "构筑重置为新版单体初始方案")
    t:Equal(nextRun.currency, 60, "资金重置")
    t:Equal(#nextRun.towers, 0, "设施重置")
    t:Equal(nextRun.repair_uses, 0, "修复次数重置")
    t:Equal(nextRun.core.hp, 1000, "核心生命重置")
    t:Equal(nextRun.player.hp, 100, "角色生命重置")
    for _, item in ipairs(nextRun.rooms) do
        t:Equal(item.state, "unvisited", "据点状态重置")
        t:Equal(item.reward_claimed, false, "本局领奖重置")
    end
    t:Equal(nextRun.map.locked.A2, true, "二级锁状态重置")
    t:Equal(nextRun.story_seen.opening, nil, "本局seen不等于持久seen")
    t:Check(nextRun.meta.story_seen.opening, "持久seen保留用于回看")
    prepare(nextRun); completedFixture(nextRun, 20)
    nextRun:Update(0.05)
    t:Equal(nextRun.result, "victory", "合法末波完成边界")
    local chapter = fresh({ meta = nextRun.meta })
    t:Check(chapter.meta.chapters["2"], "通关后新实例保留解锁")
    t:Equal(chapter.currency, 60, "重进章节仍新局资金")
end)

case("V20", function(t)
    local ok, totals = WaveDirector.Validate(Config)
    t:Check(ok, "完整配置校验")
    t:Equal(totals.waves, 20, "20波")
    t:Equal(totals.normal, 1159, "普通怪总计")
    t:Equal(totals.elite, 14, "精英总计")
    t:Equal(totals.boss, 3, "Boss总计")
    t:Equal(totals.total, 1176, "基数1176")
    t:Equal(Config.map_size.w, 64, "地图64格宽")
    t:Equal(Config.map_size.h, 48, "地图48格高")
    t:Equal(Config.core_position.x, 32, "固定核心X")
    t:Equal(Config.core_position.y, 21, "固定核心Y")
    t:Equal(fingerprint(Config.player_spawn), fingerprint({ x = 30, y = 27 }), "入场坐标")
    t:Equal(fingerprint(Config.recall_position), fingerprint({ x = 32, y = 6 }), "回城坐标")
    local expectedPortals = { W = { 17, 21 }, E = { 47, 21 }, S = { 32, 35 } }
    local portalCount = 0
    for id, point in pairs(Config.portals) do
        portalCount = portalCount + 1
        t:Equal(point.x, expectedPortals[id][1], "入口X")
        t:Equal(point.y, expectedPortals[id][2], "入口Y")
    end
    t:Equal(portalCount, 3, "只有三入口")
    t:Equal(#Config.build_slots, 4, "四槽")
    local slots = { { 27, 14 }, { 37, 14 }, { 27, 28 }, { 37, 28 } }
    for i, point in ipairs(Config.build_slots) do
        t:Equal(point.id, "T" .. i, "槽ID")
        t:Equal(point.x, slots[i][1], "槽X")
        t:Equal(point.y, slots[i][2], "槽Y")
    end
    t:Equal(#Config.rooms, 6, "六据点")
    local coords = { A1 = { 8, 21 }, A2 = { 8, 6 }, B1 = { 56, 21 }, B2 = { 56, 6 }, C1 = { 32, 43 }, C2 = { 53, 43 } }
    local rewards, xp = 0, 0
    for _, item in ipairs(Config.rooms) do
        t:Equal(item.x, coords[item.id][1], "据点X")
        t:Equal(item.y, coords[item.id][2], "据点Y")
        rewards = rewards + (item.tier == 1 and 40 or 80)
        xp = xp + (item.tier == 1 and 20 or 40)
    end
    t:Equal(rewards, 360, "据点资金总额360")
    t:Equal(xp, 180, "据点经验总额180")
    t:Equal(fingerprint(Config.waves[16].portal_offsets), fingerprint({ W = 0, E = 2, S = 4 }), "W16临时错峰记录一致")
    local map = Map.New(Config)
    t:Check(map:IsWalkable(32, 21, 0.9), "核心周围合法")
    t:Equal(map:IsWalkable(25, 21, 0.35), false, "左柱坐标实体障碍")
    t:Equal(map:IsWalkable(38, 20, 0.35), false, "右柱坐标实体障碍")
    t:Check(Config.decisions.Q07:find("推定", 1, true) ~= nil, "推定几何保留声明")
    local bad = copy(Config); bad.waves[1].ordinary = 17
    local accepted, message = pcall(WaveDirector.Validate, bad)
    t:Equal(accepted, false, "漂移配置负例确被拒绝")
    t:Check(tostring(message):find("R16", 1, true) ~= nil, "负例验证实际校验失败原因")
end)

case("ISOLATION", function(t)
    local a, b = prepare(fresh()), prepare(fresh())
    local before = fingerprint({ b:Snapshot(), b.rooms, b.map.locked, b.events })
    a.currency = 1000; a:OpenLogistics(); a:Transact("build", "T1", "rapid", "isolated")
    a:Resume("logistics"); clearRoom(t, a, "A1"); a:GrantExperience(20); a:CheckUpgrade()
    a.core.hp, a.player.hp = 5, 10
    t:Equal(fingerprint({ b:Snapshot(), b.rooms, b.map.locked, b.events }), before, "实例不共享可变规则数据")
    t:Check(a.meta ~= b.meta and a.rng ~= b.rng and a.map ~= b.map, "实例meta/random/map独立")
    t:Equal(Config.currency, 60, "实例交易不修改共享Config")
    t:Equal(Config.rooms[2].unlocked, nil, "解锁不写回Config")
end)

case("SAME_SEED_REPLAY", function(t)
    -- 显式相同身份只用于确定性回放；默认新局身份隔离由V27另验。
    local a, b = prepare(fresh({ seed = 997, run_id = "same-seed-fixture" })),
        prepare(fresh({ seed = 997, run_id = "same-seed-fixture" }))
    for _, r in ipairs({ a, b }) do
        r:GrantExperience(90); r:CheckUpgrade()
        for _ = 1, 3 do r:ChooseUpgrade(r.options[2].id) end
        r:RequestWave(); r:Update(8)
        for i = 1, 10 do r:Update(0.05, { x = i % 2, y = 0, active = i == 3 }) end
    end
    t:Equal(fingerprint(a:Snapshot()), fingerprint(b:Snapshot()), "同seed同输入状态回放")
    t:Equal(fingerprint(a.player.skills), fingerprint(b.player.skills), "同seed成长一致")
    t:Equal(fingerprint(a.enemies), fingerprint(b.enemies), "同seed敌人一致")
    t:Equal(fingerprint(a.projectiles), fingerprint(b.projectiles), "同seed弹体一致")
    t:Equal(fingerprint(a.events), fingerprint(b.events), "同seed事件一致")
    local x, y = Random.New(11), Random.New(11)
    for _ = 1, 10 do t:Equal(x:Index(9), y:Index(9), "随机源回放") end
end)

case("ASSERT_GUARD", function(t)
    -- 故意错误期望单独catch；不是硬编码true，必须确认断言实际抛错且原因匹配。
    local accepted, message = pcall(function() t:Equal(2, 3, "expected_failure_probe") end)
    t:Equal(accepted, false, "错误期望必须触发断言")
    t:Check(tostring(message):find("expected_failure_probe", 1, true) ~= nil, "捕获的是指定断言而非其他异常")
end)

require("defense.EmergenceTests").Register(case)
require("defense.PerformanceTests").Register(case)
require('defense.CompletionTests').Register(case)
require('defense.PrototypeTests').Register(case)
require('defense.ExpansionTests').Register(case)
require('defense.UIArtTests').Register(case)

-- 返回固定报告结构；每个case独立catch，失败后继续。保留日志供Runtime.Debug查看。
---@param filter? string Lua模式；省略执行全部，^V2[1-8]$等用于逐批回归。
function Tests.Run(filter)
    local report = { passed = 0, failed = 0, not_run = 0, results = {} }
    for _, item in ipairs(cases) do
        if not filter or item.case:match(filter) then
            local context = setmetatable({}, Context)
            context:Init()
            local ok, message = pcall(item.test, context)
            local status = ok and (item.not_run and "NOT_RUN" or "PASS") or "FAIL"
            local result = { case = item.case, status = status, assertions = context.assertions,
                error = not ok and tostring(message) or item.not_run or "" }
            report.results[#report.results + 1] = result
            if status == "PASS" then report.passed = report.passed + 1
            elseif status == "FAIL" then report.failed = report.failed + 1
            else report.not_run = report.not_run + 1 end
            print(string.format("[DefenseTests] %s %s assertions=%d %s", result.case, status, result.assertions, result.error))
        end
    end
    print(string.format("[DefenseTests] passed=%d failed=%d not_run=%d results=%d (NOT_RUN不计通过)",
        report.passed, report.failed, report.not_run, #report.results))
    return report
end
return Tests
