-- v0.2 系统真实性 V21–V31；纯 Lua 5.4，每例只修改新建测试实例。
-- 人类理解/复现/迁移 V32–V34 明确 NOT_RUN，自动连锁不是意图证据。
-- 几何夹具为 Config 灰盒；渲染桩只证明只读/调度，不证明真机视觉声音品质。
local Config = require("defense.Config")
local Run = require("defense.Run")
local Combat = require("defense.Combat")
local WaveDirector = require("defense.WaveDirector")
local Progression = require("defense.Progression")
local E = {}

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
    -- 反应/状态空间夹具固定敌人自主移速为0，防止无关AI走回覆盖区；
    -- 所有伤害/击退/地图/队列仍使用生产实现，不mock被测规则。
    local settings = copy(options or { seed = 21031 })
    settings.config = settings.config or copy(Config)
    settings.config.enemies.advance.speed = 0
    local r = Run.New(settings)
    r:FinishStory()
    -- 禁自动射击以隔离被测动作，仍让真实 Run.Update 驱动共同时钟与反应。
    r.player.x, r.player.y, r.player.attack_cd = 32, 6, 1000
    return r
end
---@param r table
local function events(r, kind)
    local result = {}
    for _, event in ipairs(r.events) do if event.kind == kind then result[#result + 1] = event end end
    return result
end
---@param t DefenseTestContext
---@param r table
---@return table
local function spawn(t, r, x, y, explosive, extra)
    local unit = { role = "advance", portal = "W", x = x, y = y }
    if explosive then unit.subtype = "explosive" end
    for k, v in pairs(extra or {}) do unit[k] = v end
    local enemy = Combat.Spawn(r, unit)
    t:Check(type(enemy) == "table", "真实生成合法目标")
    enemy.attack_cd = 1000
    return enemy --[[@as table]]
end
---@param t DefenseTestContext
---@param r table
local function kill(t, r, enemy, context)
    t:Check(Combat.DamageEnemy(r, enemy, enemy.hp + 1, context or "test_kill"), "真实伤害提交死亡")
    t:Equal(enemy.alive, false, "死亡已提交")
end
---@param t DefenseTestContext
---@param r table
local function build(t, r, slot, kind, budget)
    r.currency = budget or Config.towers[kind].cost
    t:Check(r:OpenLogistics(), "真实打开战备后勤")
    t:Check(r:Transact("build", slot, kind, "fixture_" .. slot).ok, "真实交易建造设施")
    r:Resume("logistics")
    local tower = r.towers[#r.towers]
    tower.attack_cd = 1000
    return tower
end
---@param r table
local function attackFixture(r, wave)
    r.wave_id = wave or 1
    r:EnterPreparation()
    r.story_seen.final_intro = true
    r.warning_elapsed = Config.warning_duration
    r:StartAttack()
    -- 精确清波边界夹具；完整20波实际队列另由V01/V30检验。
    r.director.cursor = #r.director.queue + 1
    r.director.generation_complete = true
end
---@param t DefenseTestContext
---@param r table
local function pending(t, r, count)
    t:Equal(r:PendingHarmfulCount(), count, "公共待危险计数")
    t:Equal(r.pending_harmful_reactions, count, "危险计数与公共查询一致")
end
---@param event table
local function causalField(event, name)
    return event[name] or event.data[name]
end

-- 只对边缘依赖做桩，真实执行 Board 与 LegacyFX；所有临时全局/模块始终恢复。
-- 不替换 Combat/Run/Map，也不拦截规则副作用以伪造只读通过。
---@param t DefenseTestContext
---@param r table
function E.CheckPresentation(t,r)
    local moduleNames={"defense.Board","defense.LegacyFX","defense.FX","defense.fx.Particle","defense.fx.GameAudio","defense.fx.DamageNumber","defense.fx.ScreenShake"}
    local savedModules,savedGlobals={},{}
    local calls={}
    local function record(name,...)
        calls[#calls+1]={name=name,args={...}}
    end
    local function stub(name) return function(...) record(name,...); return {} end end
    local function count(name)
        local n=0
        for _,call in ipairs(calls) do if call.name==name then n=n+1 end end
        return n
    end
    local function hasText(fragment)
        for _,call in ipairs(calls) do
            if call.name=="nvgText" and tostring(call.args[4]):find(fragment,1,true) then return true end
        end
        return false
    end
    local function hasRadius(radius)
        for _,call in ipairs(calls) do
            if call.name=="nvgCircle" and math.abs((call.args[4] or 0)-radius)<0.00001 then return true end
        end
        return false
    end
    for _,name in ipairs(moduleNames) do savedModules[name]=package.loaded[name]; package.loaded[name]=nil end
    local function global(name,value)
        savedGlobals[#savedGlobals+1]={name=name,value=_G[name]}
        _G[name]=value
    end
    for _,name in ipairs({"nvgBeginPath","nvgRect","nvgFillColor","nvgFill","nvgMoveTo","nvgLineTo",
        "nvgStrokeColor","nvgStrokeWidth","nvgStroke","nvgCircle","nvgFontFace","nvgFontSize","nvgTextAlign",
        "nvgText","nvgEllipse","nvgFillPaint","nvgClosePath","nvgSave","nvgRestore","nvgIntersectScissor",
        "nvgTranslate","nvgRotate","nvgGlobalAlpha","nvgLineCap","nvgScale","nvgBeginFrame","nvgEndFrame",
        "nvgCreate","nvgDelete","nvgCreateFont","nvgDeleteImage"}) do global(name,stub(name)) end
    global("nvgRGBA",function(red,green,blue,alpha) return {red,green,blue,alpha} end)
    global("nvgRadialGradient",stub("nvgRadialGradient"))
    global("nvgLinearGradient",stub("nvgLinearGradient"))
    -- 测试边缘桩的枚举，仅隔离NanoVG输入，不用于生产规则数字判断。
    global("NVG_ALIGN_CENTER",2); global("NVG_ALIGN_MIDDLE",16); global("NVG_ROUND",1)
    global("GetAudio",false)
    package.loaded["defense.fx.Particle"]={Reset=stub("Particle.Reset"),Update=stub("Particle.Update"),
        Spawn=stub("Particle.Spawn"),Render=stub("Particle.Render")}
    package.loaded["defense.fx.GameAudio"]={Init=stub("Audio.Init"),Update=stub("Audio.Update"),
        PlayBGM=stub("Audio.PlayBGM"),StopBGM=stub("Audio.StopBGM"),PlaySFX=stub("Audio.PlaySFX")}
    package.loaded["defense.fx.DamageNumber"]={Reset=stub("Number.Reset"),Update=stub("Number.Update"),
        Spawn=stub("Number.Spawn"),Render=stub("Number.Render"),fontId=-1}
    package.loaded["defense.fx.ScreenShake"]={Reset=stub("Shake.Reset"),Update=stub("Shake.Update"),
        Trigger=stub("Shake.Trigger"),offsetX=0,offsetY=0}
    local ok,message=pcall(function()
        local FX=require("defense.LegacyFX")
        local Board=require("defense.Board")
        local before=fingerprint(r)
        FX.Init()
        local board=Board.New(r,{pixelsPerCell=40})
        board:Events(r.events); FX.Events(r,r.events)
        t:Equal(fingerprint(r),before,"消费真实事件不允许写任何run字段（无view豁免）")
        board:Update(0.05); FX.Update(0.05)
        t:Equal(fingerprint(r),before,"表现Update不推进规则时钟/队列/状态/RNG")
        calls={}
        local boardBefore=fingerprint(board)
        board:Render({},960,640)
        t:Equal(fingerprint(board),boardBefore,"Render也不改表现缓存")
        t:Equal(fingerprint(r),before,"真实Board.Render严格只读全部规则字段")
        t:Equal(count("Particle.Render"),1,"Board只调用一次原粒子渲染，不另加重复draw")
        t:Equal(count("Number.Render"),1,"实际伤害数字只绘一次")
        t:Equal(count("nvgBeginFrame"),0,"Board不越权BeginFrame")
        t:Equal(count("nvgEndFrame"),0,"Board不越权EndFrame")
        t:Check(hasRadius(100),"2.5格真实死亡圈按40px/格绘制，不用旧脉冲半径")
        t:Check(hasText("核心"),"近核危险文字来自真实危险查询")
        board:SetReducedEffects(true); FX.SetReducedEffects(true); FX.SetVolume(0,0)
        board:Update(0.05)
        calls={}
        board:Render({},960,640)
        t:Equal(fingerprint(r),before,"降低粒子/震动/音量仍不改规则")
        t:Equal(count("Particle.Render"),0,"降表现实际禁可选粒子")
        t:Equal(count("Number.Render"),1,"降表现保留实际命中数值")
        t:Check(hasRadius(100),"降表现不能隐藏真实危险圈")
        t:Check(hasText("核心"),"降表现不能隐藏核心危险")
        calls={}; FX.Events(r,r.events)
        t:Equal(count("Audio.PlaySFX"),0,"重复事实事件ID不重播音效")
        board:Destroy(); FX.Stop()
        t:Equal(fingerprint(r),before,"销毁表现不释放/改动规则对象")
        t:Equal(count("nvgDelete"),0,"Board不销毁Runtime持有上下文")
    end)
    for _,name in ipairs(moduleNames) do package.loaded[name]=savedModules[name] end
    for _,item in ipairs(savedGlobals) do _G[item.name]=item.value end
    if not ok then error(message,0) end
end

---@param t DefenseTestContext
---@param r table
---@param summary table
function E.CheckSummary(t,r,summary)
    local facts={explosions=0,hits=0,kills=0,core_damage=0,player_damage=0,tower_damage=0}
    local ids={}
    for _,event in ipairs(r.events) do
        if causalField(event,"root_action_id")==summary.root_action_id then
            ids[event.event_id]=true
            if event.kind=="Explosion" then facts.explosions=facts.explosions+1
            elseif event.kind=="Hit" then facts.hits=facts.hits+1
            elseif event.kind=="EnemyDied" then facts.kills=facts.kills+1
            elseif event.kind=="CoreDamaged" then facts.core_damage=facts.core_damage+(event.data.amount or 0)
            elseif event.kind=="PlayerDamaged" then facts.player_damage=facts.player_damage+(event.data.amount or 0)
            elseif event.kind=="TowerDamaged" then facts.tower_damage=facts.tower_damage+(event.data.amount or 0) end
        end
    end
    for key,actual in pairs(facts) do t:Equal(summary[key],actual,"摘要只报已提交日志事实："..key) end
    t:Equal(facts.explosions,2,"摘要夹具真实两次爆炸")
    t:Equal(facts.kills,2,"摘要夹具两实体各死亡一次")
    t:Equal(summary.core_damage,80,"近核两层实际核心损失80，不虚构避免伤害")
    t:Equal(summary.gold,0,"未拾取金币不能冒充到手资金")
    t:Equal(summary.experience,0,"未拾取经验不能冒充到手成长")
    local gold,xp=0,0
    for _,drop in ipairs(r.drops) do
        if drop.kind=="gold" then gold=gold+drop.amount
        elseif drop.kind=="experience" then xp=xp+drop.amount end
    end
    t:Equal(gold,2,"死亡只产生两普通实体金币各1，无链深增奖")
    t:Equal(xp,4,"死亡只产生两普通实体经验各2，无链深增奖")
    t:Equal(summary.source,"player","事实原动作来源")
    t:Equal(summary.source_id,"player","事实原动作来源ID")
    for _,event in ipairs(events(r,"EnemyDied")) do
        if causalField(event,"root_action_id")==summary.root_action_id then
            local parent=causalField(event,"parent_event_id")
            if parent then t:Check(ids[parent],"摘要链parent存在同root的真实事件") end
        end
    end
    for _,name in ipairs({"saved_time","avoided_damage","player_intent","strategy_success","retention"}) do
        t:Equal(summary[name],nil,"不能从机制日志虚构反事实或玩家意图："..name)
    end
end

---@param add fun(id:string,fn:fun(t:DefenseTestContext),notRun?:string)
function E.Register(add)
    add("V21", function(t)
        t:Near(Config.player.active_radius, 4.5, "新版击退中心射程4.5")
        t:Near(Config.player.active_damage, 0, "新版主动无伤害")
        t:Near(Config.player.active_cooldown, 8, "新版基础冷却8秒")
        -- 施力方向：P -> E ---- 3格；所有测试点以半径校验合法。
        for _, dir in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
            local r = fresh()
            r.player.x, r.player.y = 32 - dir[1] * 2, 27 - dir[2] * 2
            local e = spawn(t, r, 32, 27)
            local target, info = Combat.ActiveTarget(r)
            t:Equal(target, e, "最近合法目标由公共查询选中")
            t:Check(info.ok, "查询报告真实可推动")
            local hp = e.hp
            t:Check(Combat.Active(r), "真实释放新版击退")
            t:Near(e.x, 32 + dir[1] * 3, "实际相对方向位移X约3格")
            t:Near(e.y, 27 + dir[2] * 3, "实际相对方向位移Y约3格")
            t:Equal(e.hp, hp, "主动不偷偷附带旧脉冲伤害")
            t:Near(r.player.active_cd, 8, "释放消耗8秒冷却")
            local before = fingerprint({e.x,e.y,e.hp,r.player.active_cd})
            t:Equal(Combat.Active(r), false, "冷却未好真实拒绝")
            t:Equal(fingerprint({e.x,e.y,e.hp,r.player.active_cd}), before, "拒绝不假位移/改伤害/重置冷却")
            t:Equal(#events(r, "Displaced"), 1, "只发一次真实位移")
            t:Equal(#events(r, "ActiveRejected"), 1, "拒绝有失败反馈")
        end
        local r = fresh()
        local tower = build(t, r, "T3", "slow")
        for _, target in ipairs({ r.core, tower }) do
            t:Equal(target.anchored, true, "核心/设施明确锚定")
            local before = fingerprint({target.x,target.y,target.hp})
            local ok, info = Combat.Displace(r, target, 1, 0, 3)
            t:Equal(ok, false, "锚定拒绝推动")
            t:Check(type(info.reason)=="string" and
                (info.reason=="anchored" or info.reason:find("固定",1,true)~=nil),
                "锚定失败须可辨，不强绑工程内部英文枚举")
            t:Equal(fingerprint({target.x,target.y,target.hp}), before, "锚定不位移也不受位移伤害")
        end
        -- 左柱边、外墙、锁房门均用真实地图。不得轴滑绕过柱或回迁传送。
        for _, layout in ipairs({ {23.5,21,1,0}, {42.5,27,1,0}, {8,11,0,-1}, {32,31.5,1,1} }) do
            local other = fresh()
            local e = spawn(t, other, layout[1], layout[2])
            local ok, info = Combat.Displace(other, e, layout[3], layout[4], 8)
            t:Check(ok or info.blocked, "受阻反馈与实际结果一致")
            t:Check(other.map:IsWalkable(e.x,e.y,e.radius), "落点全半径合法")
            t:Check(other.map:LineOfSight(layout[1],layout[2],e.x,e.y,e.radius), "路径不穿柱/墙/锁房")
            t:Check((e.x-layout[1])^2+(e.y-layout[2])^2 <= 64.00001, "不得传送扩大位移")
            t:Check(info.blocked, "非法远端真实撞墙停止")
        end
        local other = fresh()
        -- 由真实位移先得到柱前合法接触点，不猜半径/容差。
        local pinned=spawn(t,other,23.5,21)
        Combat.Displace(other,pinned,1,0,3)
        other.player.x,other.player.y=22,21
        local movable=spawn(t,other,22,22.9)
        local nearest=Combat.ActiveTarget(other)
        t:Equal(nearest,movable,"更近但完全撞墙的目标不遮蔽较远可推目标")
        local beforePinned=fingerprint({pinned.x,pinned.y,pinned.hp})
        t:Check(Combat.Active(other),"实际使用选中可推目标成功")
        t:Equal(fingerprint({pinned.x,pinned.y,pinned.hp}),beforePinned,"被过滤墙前目标不假移动/受伤")
        local other = fresh()
        other.player.x, other.player.y = 22, 21
        local visible = spawn(t, other, 22, 22.5)
        spawn(t, other, 25, 19.5) -- 左柱遮挡，不能因更近或强制ID成为目标。
        local target = Combat.ActiveTarget(other)
        t:Equal(target, visible, "最近目标须同时满足遮挡合法性")
        kill(t, other, visible)
        local none, info = Combat.ActiveTarget(other)
        t:Equal(none, nil, "死目标不锁定，墙后目标不假成功")
        t:Check(not info.ok, "无合法目标反馈失败")
        t:Near(other.core.x,32,"核心全程固定X"); t:Near(other.core.y,21,"核心全程固定Y")
    end)

    add("V22", function(t)
        for _, source in ipairs({ "player", "enemy", "tower_area" }) do
            local r = fresh()
            local e = spawn(t, r, 32, 27, true)
            t:Check(e.explodes_on_death or e.death_reaction, "明确爆炸属性而非组合名识别")
            t:Check(e.hp >= Config.player.damage * 3 and e.hp <= Config.player.damage * 5,
                "爆炸子类型真实约3–5次初始命中生命")
            kill(t, r, e, { source = source, source_id = source, root_action_id = "death_" .. source })
            t:Equal(e.death_committed, true, "唯一死亡提交标记")
            t:Equal(e.reaction_scheduled, true, "死亡反应已排队")
            pending(t, r, 1)
            local job = r.scheduled_events[1]
            t:Near(job.x,32,"计划中心锁死亡X"); t:Near(job.y,27,"计划中心锁死亡Y")
            t:Near(job.at-r.clock,0.7,"真实延迟0.7秒")
            t:Near(job.radius,2.5,"危险半径2.5"); t:Near(job.damage,40,"危险伤害40")
            local drops = #r.drops
            t:Equal(Combat.DamageEnemy(r,e,999,source), false,"重复死亡请求拒绝")
            t:Equal(#r.drops,drops,"重复死亡不双掉落")
            pending(t,r,1)
            e.x,e.y = 33,28 -- 死实体位置被改仍不能移动已锁定危险中心。
            r:Update(0.65)
            t:Equal(#events(r,"Explosion"),0,"不足延时不提前爆")
            r:Update(0.05)
            t:Equal(#events(r,"Explosion"),1,"合法来源同规则一次反应")
            local boom = events(r,"Explosion")[1].data
            t:Near(boom.x,32,"爆炸保持死亡X"); t:Near(boom.y,27,"爆炸保持死亡Y")
            t:Equal(e.reaction_committed,true,"反应唯一提交标记")
            r:Update(1)
            t:Equal(#events(r,"Explosion"),1,"后续帧不双爆")
            t:Equal(#events(r,"EnemyDied"),1,"奖励死亡事件一次")
        end
        local r = fresh()
        local ordinary = spawn(t,r,32,27)
        kill(t,r,ordinary)
        pending(t,r,0)
        t:Equal(#events(r,"ReactionScheduled"),0,"普通死物不暗变爆炸")
        local e = spawn(t,r,32,27,true)
        local packet={displacement={dx=1,dy=0,distance=3},damage=999}
        local context={source="protocol_mixed",root_action_id="mixed-root",event_key="mixed-once"}
        local result = Combat.ApplyEffect(r,e,packet,context)
        t:Check(type(result)=="table","混合效果返回提交结果")
        t:Equal(e.alive,false,"混合包真实击杀")
        t:Near(e.x,35,"混合包先位移后伤害")
        t:Near(r.scheduled_events[1].x,35,"提交后位置成为死亡点，不用旧坐标")
        t:Near(r.scheduled_events[1].y,27,"混合包锁定Y")
        local before=fingerprint({e.x,e.y,e.hp,r.drops,r.scheduled_events})
        Combat.ApplyEffect(r,e,packet,context)
        t:Equal(fingerprint({e.x,e.y,e.hp,r.drops,r.scheduled_events}),before,
            "重复同包event_key不再位移/伤害/安排反应")
    end)

    add("V23", function(t)
        -- 真近核友伤：固定核心C(32,21)，尸爆O(33,23)，活目标在圈内。
        local r = fresh()
        local tower = build(t,r,"T3","slow")
        -- 使用真实建造的锚定塔，只调整夹具布置以验证跨队伍统一伤害协议。
        tower.x,tower.y = 33,24
        r.player.x,r.player.y = 34,23
        local e = spawn(t,r,33,23,true)
        local victim = spawn(t,r,34,24); victim.hp,victim.max_hp = 100,100
        local entering = spawn(t,r,29,27); entering.hp,entering.max_hp = 100,100
        local leaving = spawn(t,r,33,24); leaving.hp,leaving.max_hp = 100,100
        local hp = { core=r.core.hp, player=r.player.hp, tower=tower.hp }
        kill(t,r,e)
        r:Update(0.65)
        t:Equal(r.core.hp,hp.core,"到期前核心无尸爆伤害")
        entering.x,entering.y = 33.5,24
        leaving.x,leaving.y = 30,28
        victim.x,victim.y = 34,24
        r:Update(0.05)
        t:Equal(r.core.hp,hp.core-40,"尸爆真实伤核心40，锚定非免疫")
        t:Equal(r.player.hp,hp.player-40,"尸爆真实友伤玩家40")
        t:Equal(tower.hp,hp.tower-40,"尸爆真实友伤设施40")
        t:Equal(victim.hp,60,"敌人同样真实40伤害")
        t:Equal(entering.hp,60,"到期读取进入圈的当前活目标")
        t:Equal(leaving.hp,100,"离开圈后不使用死亡时旧命中列表")
        local other = fresh()
        local bomb = spawn(t,other,23.5,21,true)
        local blocked = spawn(t,other,25,19.5); blocked.hp,blocked.max_hp = 100,100
        local clear = spawn(t,other,23,22); clear.hp,clear.max_hp = 100,100
        local outside = spawn(t,other,28,18); outside.hp,outside.max_hp = 100,100
        t:Equal(other.map:LineOfSight(23.5,21,25,19.5),false,"圈内目标真实柱遮挡")
        kill(t,other,bomb); other:Update(0.65)
        blocked.x,blocked.y,clear.x,clear.y,outside.x,outside.y = 25,19.5,23,22,28,18
        other:Update(0.05)
        t:Equal(blocked.hp,100,"墙柱遮挡尸爆伤害")
        t:Equal(clear.hp,60,"同圈无遮挡真实命中")
        t:Equal(outside.hp,100,"圈外不受伤")
        local ordinary = fresh()
        ordinary.player.x,ordinary.player.y = 33,23
        local ally = build(t,ordinary,"T3","area"); ally.x,ally.y = 33,24
        local target = spawn(t,ordinary,33,23)
        local before = fingerprint({ordinary.core.hp,ordinary.player.hp,ally.hp})
        Combat.DamageEnemy(ordinary,target,10,"player")
        t:Equal(fingerprint({ordinary.core.hp,ordinary.player.hp,ally.hp}),before,
            "普通攻击不默认友伤")
    end)

    add("V24", function(t)
        local r = fresh()
        local first = spawn(t,r,22,27,true)
        local second = spawn(t,r,24,27,true); second.hp = 20
        local third = spawn(t,r,26,27,true); third.hp = 20
        local guard = spawn(t,r,24,27,false,{room_id="A1"})
        -- 只改变夹具守军坐标，身份保持room_id，测试跨系统伤害而非刷完美目标。
        local root = "chain-root"
        kill(t,r,first,{source="player",source_id="player",root_action_id=root})
        pending(t,r,1)
        t:Equal(second.alive,true,"子实体不递归即时爆死")
        r:Update(0.65)
        second.x,second.y,third.x,third.y,guard.x,guard.y = 24,27,26,27,24,27
        r:Update(0.05)
        t:Equal(second.alive,false,"首层真实爆炸杀第二实体")
        t:Equal(guard.alive,false,"同层真实爆炸杀守军")
        t:Equal(third.alive,true,"下一层不递归即时结算")
        pending(t,r,1)
        local nextJob = r.scheduled_events[1]
        t:Near(nextJob.at-r.clock,0.7,"下一层独立延迟而非同栈递归")
        t:Equal(nextJob.root_action_id,root,"root沿链贯穿")
        local firstExplosion = events(r,"Explosion")[1]
        local parent=nil
        for _,event in ipairs(r.events) do if event.event_id==nextJob.parent_event_id then parent=event; break end end
        t:Check(parent~=nil,"队列parent指向真实直接因果事件")
        t:Equal(causalField(parent,"root_action_id"),root,"直接父事件保留同根")
        t:Equal(parent.kind,"EnemyDied","直接父是第二实体真实死亡而非自接原始动作")
        t:Equal(parent.data.id,second.id,"parent对准直接死亡实体")
        t:Equal(causalField(firstExplosion,"root_action_id"),root,"爆炸提交同根，汇总事件可在目标死亡后发出")
        r:Update(0.65); third.x,third.y=26,27; r:Update(0.05)
        t:Equal(third.alive,false,"第二层真实伤害第三实体")
        pending(t,r,1)
        r:Update(0.7)
        pending(t,r,0)
        t:Equal(#events(r,"Explosion"),3,"三爆逐层真实提交，不截链")
        t:Equal(#events(r,"EnemyDied"),4,"同根四实体独立死亡，不吞守军")
        t:Equal(r:AliveCount(),0,"守军不进入进攻计数")
        local died, byId = events(r,"EnemyDied"), {}
        for _, event in ipairs(died) do
            local id = event.data.id
            t:Equal(byId[id],nil,"每实体死亡去重而非仅按root去重")
            byId[id] = true
            t:Equal(causalField(event,"root_action_id"),root,"每死亡保存同根")
            if id==guard.id then
                t:Equal(event.data.room_id,"A1","守军room身份保留")
                t:Equal(event.data.wave_id,nil,"守军不被链改写为当前波")
            else t:Equal(event.data.wave_id,1,"进攻怪wave身份保留") end
        end
        local drops = #r.drops
        for _, e in ipairs({first,second,third,guard}) do
            t:Equal(Combat.DamageEnemy(r,e,999,{root_action_id=root}),false,"重复投递不再次死亡")
        end
        t:Equal(#r.drops,drops,"重复投递不再次掉落奖励")
        local xp,gold=0,0
        for _, drop in ipairs(r.drops) do
            if drop.kind=="experience" then xp=xp+drop.amount else gold=gold+drop.amount end
        end
        t:Equal(xp,8,"四实体经验各一次，无链深额外奖")
        t:Equal(gold,3,"三进攻金币各一次，守军不掉进攻金币")
        local repeated=fresh()
        local bomb=spawn(t,repeated,33,23,true)
        kill(t,repeated,bomb,{source="player",root_action_id="dedup-reaction"})
        local duplicate=copy(repeated.scheduled_events[1])
        repeated.scheduled_events[#repeated.scheduled_events+1]=duplicate
        -- 迟到重放不是新合法危险，计数不能额外加1。
        pending(t,repeated,1)
        repeated:Update(0.7)
        t:Equal(#events(repeated,"Explosion"),1,"同event_id深拷贝重放也只反应一次")
        t:Equal(repeated.core.hp,960,"重放不重复伤核40")
        t:Equal(#events(repeated,"EnemyDied"),1,"重放不双死亡事件")
        pending(t,repeated,0)
    end)

    add("V25", function(t)
        local r = fresh()
        local bomb=spawn(t,r,32,27,true)
        local target=spawn(t,r,32,29); target.hp,target.max_hp=100,100
        Combat.ApplySlow(r,target,0.35,2,"clock-source")
        kill(t,r,bomb)
        r.player.active_cd=6
        r:Update(0.2)
        local function frozen()
            return fingerprint({r.clock,r.scheduled_events,r.pending_harmful_reactions,
                target.slow_effects,target.slow_factor,r.player.active_cd,r.director:Snapshot(),r.drops,
                r.core.hp,r.player.hp})
        end
        for _, mode in ipairs({"upgrade","manual","focus","story"}) do
            if mode=="upgrade" then r:GrantExperience(20); t:Check(r:CheckUpgrade(),"真实打开升级冻结")
            elseif mode=="story" then t:Check(r:ReplayStory("opening"),"真实关键演出冻结")
            else r:Pause(mode) end
            local before=frozen()
            r:Update(5); Combat.Update(r,5); Combat.ProcessReactions(r)
            t:Equal(frozen(),before,"暂停共同冻结队列/减速/冷却/掉落："..mode)
            t:Equal(#events(r,"Explosion"),0,"暂停不暗爆："..mode)
            if mode=="upgrade" then t:Check(r:ChooseUpgrade(r.options[1].id),"选择恢复原态")
            elseif mode=="story" then t:Check(r:FinishStory(),"跳过恢复剩余反应")
            else r:Resume(mode) end
        end
        r:Update(0.45)
        t:Equal(#events(r,"Explosion"),0,"恢复只消费剩余0.5秒前0.45")
        target.x,target.y=32,29
        r:Update(0.05)
        t:Equal(#events(r,"Explosion"),1,"恢复连续时限，0.7累计恰一次")
        t:Near(r.clock,0.7,"世界时钟不累计暂停耗时")
        t:Near(r.player.active_cd,5.3,"冷却只消费模拟0.7")
        t:Check(target.slow_factor<1,"减速仍有真实剩余时限")
        r:Update(1.3)
        t:Near(target.slow_factor,1,"减速按连续模拟2秒到期")
        t:Equal(#events(r,"Explosion"),1,"恢复不双爆")
    end)

    add("V26", function(t)
        local r=fresh()
        local e=spawn(t,r,32,28); e.hp,e.max_hp=1000,1000
        t:Check(Combat.ApplySlow(r,e,0.25,2,"weak"),"弱源真实状态")
        t:Check(Combat.ApplySlow(r,e,0.9,0.5,"strong"),"强源首轮封顶")
        t:Near(e.slow_factor,0.5,"有效减速上限50%，不相乘")
        r:Update(0.3)
        Combat.ApplySlow(r,e,0.2,1,"strong")
        t:Near(e.slow_factor,0.75,"同源刷新强度后重新取最强，不能保留过时值")
        r:Update(0.8)
        t:Check(e.slow_effects.strong~=nil,"同源刷新延长独立来源期限")
        r:Update(0.2)
        t:Equal(e.slow_effects.strong,nil,"刷新来源到期移除")
        t:Near(e.slow_factor,0.75,"异源弱状态独立期限仍有效")
        r:Update(0.7)
        t:Near(e.slow_factor,1,"所有来源按各自期限结束")
        local boss=spawn(t,r,32,30,false,{role="commander"})
        Combat.ApplySlow(r,boss,0.9,2,"boss-order")
        t:Near(boss.slow_factor,0.75,"先封顶50%再Boss减半，顺序一致")
        local towerRun=fresh()
        local tower=build(t,towerRun,"T3","slow")
        tower.attack_cd=0
        local target=spawn(t,towerRun,32,28); target.hp,target.max_hp=1000,1000
        towerRun:Update(0.1)
        t:Near(target.slow_factor,0.65,"真实减速塔范围5.5施加35%状态")
        target.x,target.y=32,31.5
        towerRun:Update(0.05)
        t:Check(target.slow_factor<1,"离范围不立刻删除已有状态")
        towerRun:Update(1.7)
        t:Check(target.slow_factor<1,"离开不再刷新但期限未到保持")
        target.x,target.y=32,31.5
        towerRun:Update(0.3)
        t:Near(target.slow_factor,1,"离开后原状态按2秒期限结束")
        local chain=fresh()
        chain.player.x,chain.player.y=32,25
        local bomb=spawn(t,chain,32,27,true)
        t:Check(Combat.Active(chain),"真实释放击退后连锁")
        chain.player.x,chain.player.y=32,6
        kill(t,chain,bomb)
        chain:Update(0.7)
        t:Near(chain.player.active_cd,7.3,"死亡连锁不重置8秒技能冷却")
        -- 真实全目标压力，超过任何小型表现前N预算；不造生产软上限以外进攻怪。
        local pressure=fresh()
        local corpse=spawn(t,pressure,32,27,true)
        local victims={}
        for i=1,79 do victims[i]=spawn(t,pressure,32,28); victims[i].hp=20 end
        kill(t,pressure,corpse); pressure:Update(0.7)
        t:Equal(#events(pressure,"EnemyDied"),80,"80实体均真实结算，不按前N截命中")
        t:Equal(pressure:AliveCount(),0,"压力场景全部合法命中")
    end)

    add("V27", function(t)
        for _, wave in ipairs({1,20}) do
            local r=fresh(); attackFixture(r,wave)
            local bomb=spawn(t,r,32,27,true)
            kill(t,r,bomb)
            local gold=r.currency
            r:Update(0.65)
            t:Equal(r.state,"ATTACK","末怪死亡未来危险期间不战备/胜利")
            t:Equal(r.currency,gold,"危险未结不发奖励")
            t:Equal(#events(r,"WaveCleared"),0,"不能取消危险来清波")
            r:Update(0.05)
            t:Equal(#events(r,"WaveCleared"),1,"危险完成才结算")
            t:Equal(r.currency,gold+12,"合法清波奖励一次")
            if wave==20 then t:Equal(r.result,"victory","末波真实危险处理后胜利")
            else t:Equal(r.wave_id,2,"非末波危险处理后战备") end
        end
        for _, kind in ipairs({"core","player"}) do
            local r=fresh(); attackFixture(r,20)
            if kind=="core" then r.core.hp=40 else r.player.x,r.player.y,r.player.hp=34,23,40 end
            local bomb=spawn(t,r,33,23,true)
            kill(t,r,bomb)
            local gold=r.currency
            r:Update(0.7)
            t:Equal(r[kind].hp,0,"同时间槽尸爆真实归零："..kind)
            t:Equal(r.result,"defeat","同槽失败优先于末波胜利")
            local collected=0
            for _,event in ipairs(events(r,"Pickup")) do
                if event.data.kind=="gold" then collected=collected+event.data.amount end
            end
            t:Equal(r.currency,gold+collected,"失败允许真实拾取金币但无错误清波奖励")
            t:Equal(#events(r,"WaveCleared"),0,"同槽不错误清波")
            t:Equal(#events(r,"RunEnded"),1,"同槽结局一次")
        end
        local sameSlot=fresh(); attackFixture(sameSlot,20)
        sameSlot.core.hp=40
        local a=spawn(t,sameSlot,33,23,true)
        local b=spawn(t,sameSlot,34,22,true)
        local victim=spawn(t,sameSlot,34,21)
        victim.hp,victim.max_hp=100,100
        kill(t,sameSlot,a,{source="player",root_action_id="same-slot"})
        kill(t,sameSlot,b,{source="player",root_action_id="same-slot"})
        local jobs=sameSlot.scheduled_events
        t:Near(jobs[1].at,jobs[2].at,"两反应同计划时间槽")
        t:Check(jobs[1].sequence<jobs[2].sequence,"同时间稳定序号排序")
        sameSlot:Update(0.7)
        t:Equal(#events(sameSlot,"Explosion"),2,"首爆致核心死仍提交同槽第二真实反应")
        t:Equal(victim.hp,20,"同槽两个合法伤害完整提交，不截剩余目标")
        t:Equal(sameSlot.result,"defeat","整个同槽提交后失败优先")
        t:Equal(#events(sameSlot,"WaveCleared"),0,"同槽失败不结算清波")
        local r=fresh(); attackFixture(r,1)
        local guard=spawn(t,r,32,27,true,{room_id="A1"})
        kill(t,r,guard)
        t:Equal(r:AliveCount(),0,"爆炸守军仍不计进攻存活")
        r:Update(0.65)
        t:Equal(r.wave_id,1,"全局待守军危险同样阻止清波")
        r:Update(0.05)
        t:Equal(r.wave_id,2,"守军危险处理完才清波")
        local old=fresh(); local bomb=spawn(t,old,33,23,true); kill(t,old,bomb)
        local job=copy(old.scheduled_events[1])
        old:Close("retry")
        pending(t,old,0)
        local nextRun=fresh()
        t:Check(nextRun.run_id~=old.run_id,"默认新局身份唯一")
        local before=fingerprint({nextRun.core.hp,nextRun.player.hp,nextRun.currency,nextRun.drops})
        -- 迟到旧局事件的防御性输入：不隐匿危险，不请求生产忽略合法本局反应。
        nextRun.scheduled_events[#nextRun.scheduled_events+1]=job
        nextRun:Update(1)
        t:Equal(fingerprint({nextRun.core.hp,nextRun.player.hp,nextRun.currency,nextRun.drops}),before,
            "迟到旧局事件不得伤新局/双奖励")
        t:Equal(#events(nextRun,"Explosion"),0,"旧局反应不冒充新局事实")
    end)

    add("V28", function(t)
        for _, budget in ipairs({60,90,120,200}) do
            local r=fresh(); r.currency=budget; r.core.hp=800
            t:Check(r:OpenLogistics(),"真实预算交易入口")
            local before=fingerprint({r.currency,r.towers,r.repair_uses,r.core.hp})
            local slow=r:Transact("build","T3","slow","budget_slow")
            if budget<90 then
                t:Equal(slow.ok,false,"60不能买90塔")
                t:Equal(fingerprint({r.currency,r.towers,r.repair_uses,r.core.hp}),before,"开局不暗赠塔/金")
            else
                t:Check(slow.ok,"资金足额才能买90塔")
                t:Equal(slow.price,90,"真实支出90")
                t:Equal(r.currency,budget-90,"真实机会成本余额")
                if budget==120 then
                    t:Equal(r:Transact("repair",nil,nil,"after_slow_repair").ok,false,"120买90余30不能修40")
                    t:Equal(r.core.hp,800,"没钱修复不暗赠耐久")
                elseif budget==200 then
                    t:Check(r:Transact("build","T4","area","budget_area").ok,"200余110足额范围塔")
                    t:Equal(r.currency,0,"两塔90+110确实花光200")
                    t:Equal(#r.towers,2,"两实体设施而非免费效果")
                    t:Check(r.towers[1].slot_id~=r.towers[2].slot_id,"两个不同槽机会成本")
                end
            end
        end
        local repair=fresh(); repair.currency,repair.core.hp=120,800; repair:OpenLogistics()
        local tx=repair:Transact("repair",nil,nil,"repair_first")
        t:Check(tx.ok,"120先修真实合法")
        t:Equal(repair.currency,80,"先修余80")
        t:Equal(repair.core.hp,1000,"实际修复200")
        t:Equal(repair:Transact("build","T3","slow","repair_then_tower").ok,false,"余80买不起90")
        local area=fresh(); area.currency=120; area:OpenLogistics()
        t:Check(area:Transact("build","T3","area","area_first").ok,"120可以买110范围塔")
        t:Equal(area.currency,10,"范围替代路线真实余10")
        for _, buildId in ipairs({"single","area","control"}) do
            local alternative=fresh({build=buildId,seed=22})
            t:Equal(alternative.currency,60,"所有初始套装无暗赠预算")
            t:Equal(#alternative.towers,0,"不探索不建塔也不强塞设施")
            alternative.player.x,alternative.player.y=32,25
            spawn(t,alternative,32,27,true)
            t:Check(Combat.Active(alternative),"未选范围也有真实空间控制替代入口")
        end
    end)

    -- V29的真正渲染桩在实现完成后按Board/LegacyFX契约接入；视觉品质另验。
    add("V29", function(t)
        local r=fresh()
        local bomb=spawn(t,r,33,23,true)
        kill(t,r,bomb)
        local before=fingerprint({r:Snapshot(),r.enemies,r.scheduled_events,r.drops,r.player,r.core,r.rng})
        r:CausalSummaries(); r:Snapshot(); Combat.ActiveTarget(r)
        t:Equal(fingerprint({r:Snapshot(),r.enemies,r.scheduled_events,r.drops,r.player,r.core,r.rng}),before,
            "表现所用查询纯读取规则")
        t:Check(E.CheckPresentation~=nil,"需要实际Board/LegacyFX渲染调度桩，不能只以查询宣称V29完成")
        E.CheckPresentation(t,r)
    end)

    add("V30", function(t)
        local totals={ordinary=0,elite=0,boss=0,explosive=0}
        local windows={}
        for wave=1,20 do
            local queue=WaveDirector.BuildQueue(Config,wave)
            local ordinary,elite,boss,explosive=0,0,0,0
            local lanes={}
            for _,unit in ipairs(queue) do
                lanes[unit.portal]=(lanes[unit.portal] or 0)+1
                if unit.role=="elite" then elite=elite+1
                elseif unit.role=="commander" or unit.role=="siege" or unit.role=="final" then
                    boss=boss+1
                    t:Equal(unit.portal,Config.waves[wave].boss_portal,"Boss原入口不改")
                    t:Near(unit.at,3,"Boss原入场时钟不改")
                else ordinary=ordinary+1 end
                if unit.subtype=="explosive" then
                    explosive=explosive+1
                    t:Equal(unit.role,"advance","爆炸为普通推进子类型，不新增角色额度")
                    t:Check(unit.opportunity_tag~=nil,"配置机会标签可核对")
                end
            end
            t:Equal(ordinary,Config.waves[wave].ordinary,"20波普通总数逐行不漂移")
            t:Equal(elite,Config.waves[wave].elite_count,"20波精英逐行保留")
            t:Equal(boss,Config.waves[wave].boss_type and 1 or 0,"20波Boss逐行保留")
            if wave==3 then t:Equal(explosive,1,"W3恰1普通名额替换") end
            if explosive>0 then windows[#windows+1]=wave end
            if wave<3 then t:Equal(explosive,0,"初期无未声明爆炸机会") end
            totals.ordinary,totals.elite,totals.boss,totals.explosive=
                totals.ordinary+ordinary,totals.elite+elite,totals.boss+boss,totals.explosive+explosive
            local active={}
            for _,id in ipairs(Config.waves[wave].active_portals) do active[id]=true end
            for lane in pairs(lanes) do t:Check(active[lane],"不偷偷增新入口") end
            for index,id in ipairs(Config.waves[wave].active_portals) do
                t:Check(lanes[id]>0,"保留每条原入口")
                local laneCount=#Config.waves[wave].active_portals
                local normalCount=math.floor(Config.waves[wave].ordinary/laneCount)
                    +(index<=Config.waves[wave].ordinary%laneCount and 1 or 0)
                local eliteCount=math.floor(Config.waves[wave].elite_count/laneCount)
                    +(index<=Config.waves[wave].elite_count%laneCount and 1 or 0)
                local bossCount=Config.waves[wave].boss_portal==id and 1 or 0
                t:Equal(lanes[id],normalCount+eliteCount+bossCount,
                    "每入口真实名额保持基线轮转分配，不加完美目标")
            end
        end
        t:Equal(totals.ordinary,1159,"20波普通含爆炸仍1159")
        t:Equal(totals.elite,14,"精英仍14"); t:Equal(totals.boss,3,"Boss仍3")
        t:Check(#windows>=5,"多波机会，不是仅演一次隐藏配方")
        for seed=1,10 do
            local r=fresh({seed=seed}); r.wave_id=3; r.player.level=2
            local options=Progression.Options(r,r.rng)
            local range=false
            for _,option in ipairs(options) do if option.group=="area" then range=true end end
            t:Check(range,"W3–5实际范围候选保护，不强制选择")
            t:Equal(r.player.skills.blast,nil,"候选不暗赠范围技能")
        end
        local r=fresh(); r.wave_id=3; r.player.level=2
        r:GrantExperience(30); t:Check(r:CheckUpgrade(),"真实机会选择入口")
        local pick=nil
        for _,option in ipairs(r.options) do if option.group~="area" then pick=option.id; break end end
        t:Check(pick~=nil,"仍有可放弃范围的合法替代候选")
        t:Check(r:ChooseUpgrade(pick),"玩家可以实际不选范围")
        t:Equal(r.player.skills.blast,nil,"不选范围不得暗补技能")
    end)

    add("V31", function(t)
        local r=fresh()
        local first=spawn(t,r,33,23,true)
        local second=spawn(t,r,34,22,true); second.hp=20
        kill(t,r,first,{source="player",root_action_id="summary-root",source_id="player"})
        r:Update(0.65); second.x,second.y=34,22; r:Update(0.75)
        local summaries=r:CausalSummaries()
        t:Check(type(summaries)=="table" and #summaries>=1 and #summaries<=2,"最近1–2条真实摘要")
        t:Check(type(r.causal_history)=="table","历史真实事实可展开")
        local matching={}
        for _,summary in ipairs(r.causal_history) do
            if summary.root_action_id=="summary-root" then matching[#matching+1]=summary end
        end
        t:Equal(#matching,1,"同root合并摘要，不按链层刷战报")
        local summary=matching[1]
        t:Check(summary~=nil,"摘要来自实际root")
        t:Check(E.CheckSummary~=nil,"摘要字段需对照真实提交契约，不以存在字段冒充事实核对")
        E.CheckSummary(t,r,summary)
        local before=fingerprint({r.clock,r.core.hp,r.currency,r.drops,r.scheduled_events,r.rng})
        local snapshot=r:Snapshot()
        t:Check(snapshot.causal_summaries~=nil,"快照真实摘要给表现读取")
        r:CausalSummaries(); r:CausalSummaries()
        t:Equal(fingerprint({r.clock,r.core.hp,r.currency,r.drops,r.scheduled_events,r.rng}),before,
            "战报查看/关闭不更改规则或补奖励")
        local currency,xp=r.currency,r.player.experience
        r.player.x,r.player.y=33.5,22.5
        Combat.Pickup(r,0.05)
        t:Equal(r.currency,currency+2,"真实拾取两实体金币各1到账")
        t:Equal(r.player.experience,xp+4,"真实拾取两实体经验各2到账")
        local after=r:CausalSummaries(true)
        local committed=nil
        for _,item in ipairs(after) do if item.root_action_id=="summary-root" then committed=item; break end end
        t:Check(committed~=nil,"拾取继承死亡root摘要")
        t:Equal(committed.gold,2,"摘要只在实际拾取后记录到手2")
        t:Equal(committed.experience,4,"摘要只在实际拾取后记录到手4")
        t:Equal(#r.causal_history,1,"拾取合并原root而非虚构新策略")
        Combat.Pickup(r,0.05)
        t:Equal(r.currency,currency+2,"反复拾取不双到账")
    end)

    for _,id in ipairs({"V32","V33","V34"}) do
        add(id,function() end,
            "NOT_RUN: 需真实玩家观察、原话与分子/分母；自动连锁不代表理解、主动复现、迁移或留存")
    end
end
return E
