-- 新扩展的CPU边界/真实交易/公共Combat回归；坐标和清房夹具不构成试玩或FPS证据。
local T = {}
local Run = require("defense.Run")
local X = require("defense.Expansion")
local Combat = require("defense.Combat")
local Scenarios = require("defense.Scenarios")
local Modules = require("defense.TowerModules")
local Expedition = require("defense.Expedition")
---@return table
local function fresh()
    local r = Run.New { scenario_id = "sanctuary_expansion", seed = 1008 }
    r:FinishStory(); r.player.attack_cd = 1000000; return r
end
local function cleared(r, n)
    for i = 1, n do r.rooms[i].state = "cleared"; r.map:SetUnlocked(r.rooms[i].id, true) end
end
local function trial(n)
    local r = fresh(); cleared(r, n or 1); assert(X.StartTrial(r)); assert(r:PrepareChallenge()); return r
end
local function build(t, r, slot, kind)
    r.currency = 10000; r.exploration_currency = 100; r:OpenLogistics()
    t:Check(r:Transact("build", slot, kind, "build:" .. slot).ok, "真实设施交易")
    return r.towers[#r.towers]
end
function T.Register(case)
    case("S01_TIMING", function(t)
        local r = fresh()
        for _, pair in ipairs({{0,15},{15,15},{22,8},{30,0},{45,0}}) do
            r.attack_elapsed = pair[1]; t:Near(X.Bonus(r), pair[2], "速清奖励上下界")
        end
        r:EnterPreparation(100); t:Near(r.preparation_remaining,30,"探索窗口封顶")
        r:RequestWave(); r:Update(7.9); t:Equal(r.state,"WARNING","提前开波完整预警")
        r:Update(0.1); t:Equal(r.state,"ATTACK","独立8秒结束")
        local q = fresh(); q:Update(15); t:Equal(q.state,"WARNING","自然战备结束才预警")
        t:Near(q.warning_elapsed,0,"战备不能消费预警")
        q:Update(7.9); t:Equal(q.state,"WARNING","自然开波完整预警")
        local last = 0; for _, w in ipairs(r.config.waves) do t:Check(w.attack_duration >= last,"基准不递减"); last=w.attack_duration end
    end)
    case("S02_EXPLORATION_FACTS", function(t)
        local r=fresh(); cleared(r,1); r.player.x,r.player.y=r.rooms[1].x,r.rooms[1].y
        X.RecordWave(r,10); r.wave_id=2
        r:EnterPreparation(10); r:Update(2); t:Near(r.exploration_seconds_used,2,"房内真实奖励时段")
        t:Near(r.wave_reports[1].exploration_used,2,"本波奖励窗口使用分开记账")
        t:Check(r.wave_reports[1].zone_visits.A1,"本波奖励探索去向")
        t:Check(r.zone_visits.A1,"记录到达房间")
        r:Pause("manual"); r:Update(20); t:Near(r.exploration_seconds_used,2,"暂停不消费奖励")
        r:Resume("manual"); r:RequestWave(); t:Near(r.preparation_remaining,0,"提前开波作废剩余")
        r.attack_elapsed=31; X.RecordWave(r,0); X.RecordWave(r,0)
        local hints=0; for _,e in ipairs(r.events) do if e.kind=="SlowClearHint" then hints=hints+1 end end
        t:Equal(hints,1,"两次慢清只提示")
    end)
    case("S03_REWARD_ONCE", function(t)
        local r=fresh(); cleared(r,1); local room=r.rooms[1]; r.player.x,r.player.y=room.x,room.y
        local gold=r.currency; t:Check(r:ClaimRoom(room.id,"claim1"),"领取")
        t:Equal(r.currency,gold+60,"森林资金差异"); t:Equal(r.exploration_currency,10,"首次星砂")
        t:Check(r:ClaimRoom(room.id,"claim1"),"重放成功事实")
        t:Equal(r.exploration_currency,10,"重放不复制收入")
        X.Sand(r,200,"fixture"); t:Equal(r.exploration_currency_earned,120,"累计收入上限")
        r.exploration_currency=0; t:Equal(X.Sand(r,10,"after_spend"),0,"花费不能突破累计收入限制")
        local q=fresh(); t:Equal(q.exploration_currency,0,"重开收入隔离")
    end)
    case("S04_BRANCH_TRANSACTION", function(t)
        local r=fresh(); local tower=build(t,r,"T1","rapid")
        t:Equal(r:Transact("branch","T1","focus","tooearly").ok,false,"需先升级")
        t:Check(r:Transact("upgrade","T1",nil,"up1").ok,"升级")
        local before=Modules.Attributes(r,tower); local sand=r.exploration_currency
        local result=r:Transact("branch","T1","focus","branch1"); t:Check(result.ok,"选择分支")
        t:Near(Modules.Attributes(r,tower).damage,before.damage*1.25,"真实分支伤害")
        t:Equal(r.exploration_currency,sand-20,"星砂实际扣费")
        t:Equal(r:Transact("branch","T1","focus","branch1"),result,"交易重放幂等")
        t:Equal(r:Transact("branch","T1","reach","branch2").ok,false,"不可逆")
        t:Check(r:Transact("upgrade","T1",nil,"up2").ok,"第二级")
        t:Equal(r:Transact("upgrade","T1",nil,"up3").ok,false,"升级封顶")
        local refund=r:Transact("demolish","T1",nil,"remove")
        t:Equal(refund.refund,math.floor((tower.build_spend+tower.upgrade_spend)*.5),"完好返50%资金")
        t:Equal(r.exploration_currency,sand-20,"拆除不返星砂")
    end)
    case("S05_FACILITIES", function(t)
        local r=fresh(); local repair=build(t,r,"T1","repair_station")
        local energy=build(t,r,"T2","energy_station")
        local rapid=build(t,r,"T3","rapid")
        -- 合法核心附近几何输入，验证公共属性与真实更新，非布局/画面验收。
        repair.x,repair.y=r.core.x+2,r.core.y; energy.x,energy.y=r.core.x+3,r.core.y
        rapid.x,rapid.y=r.core.x+4,r.core.y
        local boosted=Modules.Attributes(r,rapid); energy.hp=0
        local normal=Modules.Attributes(r,rapid); t:Check(boosted.interval<normal.interval,"活供能站缩短实际间隔")
        t:Near(boosted.energy_received,.15,"实际供能量")
        r.core.hp=900; rapid.hp=rapid.max_hp-10; r:Resume("logistics")
        Combat.Update(r,.05,{}); t:Near(r.core.hp,904,"维修真实核心耐久")
        t:Near(rapid.hp,rapid.max_hp-6,"维修真实设施")
        energy.hp=0; Combat.Update(r,2.1,{}); t:Equal(energy.hp,0,"不复活已毁设施")
        t:Equal(#r.config.facility_order,8,"四类八设施")
    end)
    case("S06_PERIPHERAL_COMBAT", function(t)
        local r=fresh(); cleared(r,1)
        local slot; for _,s in ipairs(r.config.build_slots) do if s.owner_room_id=="A1" then slot=s end end
        local tower=build(t,r,slot.id,"rapid"); r:Resume("logistics")
        local enemy=Combat.Spawn(r,{role="advance",portal="W",room_id="A1",x=tower.x+1,y=tower.y})
        t:Check(enemy~=nil,"守军生成")
        Combat.Update(r,.05,{}); t:Check(tower.defense_active,"外围设施激活")
        local count=0; for _,b in ipairs(r.projectiles) do if b.source=="tower_rapid" then count=count+1 end end
        t:Check(count>0,"实际向守军发射弹体")
    end)
    case("S07_TRIAL_FILTER_AND_WARNING", function(t)
        local a=fresh(); t:Equal(X.StartTrial(a),false,"没有已清房不触发")
        local r=trial(1); t:Equal(#r.current_wave.challenge.stop_ids,1,"过滤未清房")
        t:Equal(#r.current_wave.special_units,9,"三支三人小队")
        t:Equal(#r.current_wave.regional_units,3,"已清房考验怪")
        t:Equal(r.rooms[2].state,"unvisited","未清房状态保留")
        t:Check(require("defense.WaveDirector").Validate(r.config),"动态完整队列校验")
        r:RequestWave(); r:Update(8); t:Check(r.pause_reasons.story,"终局演出先于战斗")
        r:FinishStory(); t:Near(r.warning_elapsed,0,"演出后预警重置")
        r:Update(7.9); t:Equal(r.state,"WARNING","演出后足8秒")
        r:Update(.1); t:Equal(r.state,"ATTACK","进入考验")
        local q=fresh(); cleared(q,1); q.wave_id=20; q.current_wave=q.config.waves[20]
        q.attack_duration=45; q.director.generation_complete=true; q:SettleWave()
        t:Near(q.preparation_remaining,30,"W20速清仍获得考验前完整探索奖励")
        t:Near(q.wave_reports[1].bonus,15,"W20奖励事实一致")
    end)
    case("S08_SHARED_CORE_BUDGET", function(t)
        local r=trial(2); r:FinishStory()
        Combat.Damage(r,r.core,80,{source="enemy_attack",source_id="team1",core_budget_room="A1"})
        Combat.Damage(r,r.core,80,{source="enemy_attack",source_id="team2",core_budget_room="A1"})
        t:Equal(r.core.hp,900,"跨队共100上限")
        Combat.Damage(r,r.core,40,{source="enemy_attack",source_id="return",core_budget_room="A1"})
        t:Equal(r.core.hp,900,"再入不重置")
        Combat.Damage(r,r.core,40,{source="enemy_attack",source_id="next",core_budget_room="A2"})
        t:Equal(r.core.hp,860,"不同房独立预算")
        t:Equal(r.totals.core_damage,140,"战报只计实际伤害")
        t:Equal(r.room_core_damage["21:A1"].remaining,0,"预算事实")
        local e=Combat.Spawn(r,r.current_wave.special_units[1]) --[[@as table]]
        t:Check(e~=nil,"真实远征入场")
        local hp=e.hp; Combat.DamageEnemy(r,e,hp+1,"player"); t:Equal(e.alive,false,"新巡行可直接击杀")
        t:Equal(e.hp,0,"不锁1HP")
    end)
    case("S09_END_PRIORITY", function(t)
        local r=fresh(); r.wave_id=20; r.current_wave=r.config.waves[20]
        r.director.generation_complete=true; r.state="ATTACK"
        r.pending_harmful_reactions=1; r:SettleWave(); t:Equal(r.ended,false,"有害反应阻止通关")
        r.pending_harmful_reactions=0; r.core.hp=0; r:SettleWave(); t:Equal(r.result,"defeat","失败优先")
        local q=fresh(); q.wave_id=20; q.current_wave=q.config.waves[20]; q.director.generation_complete=true
        q:SettleWave(); t:Equal(q.result,"victory","无探索W20普通结束")
        local z=trial(1); z.story_seen.final_intro=true; z:StartAttack()
        z.attack_elapsed=z.config.expedition_time_cap-.05; z:Pause("manual"); z:Update(10)
        t:Equal(z.ended,false,"暂停冻结截止")
        z:Resume("manual"); z:Update(.1); t:Equal(z.result,"defeat","截止判失败")
        local other=fresh(); t:Equal(#other.config.waves,20,"动态考验不泄露新局")
    end)
    case("S10_ROUTE_REAL_MOVEMENT", function(t)
        local r=trial(6); local def=r.config.enemies.expedition_advance
        local valid,reason,detail=Expedition.Validate(r,"sanctuary_circuit",r.config.portals.W,def.radius)
        t:Check(valid,reason); t:Equal(detail.stops,6,"六站合法路径")
        -- 真实公共移动+阶段，不用传送推进，不强杀；隔离伤害免于测试玩家死亡影响路线。
        local e=Combat.Spawn(r,r.current_wave.special_units[1]); t:Check(e~=nil,"实际生成")
        r.player.invulnerable=1000000; r.player.x,r.player.y=r.core.x,r.core.y
        local seen={}; local seconds=0
        while e.stage~="FINAL_ASSAULT" and seconds<150 and not r.technical_error do
            Combat.Update(r,.05,{}); seconds=seconds+.05
            if e.stage=="ROOM_ENGAGED" then seen[e.current_room_id]=true end
            t:Check(r.map:IsWalkable(e.x,e.y,e.radius),"每步完整半径合法")
        end
        t:Equal(r.technical_error,nil,"巡行无寻路异常")
        t:Equal(e.stage,"FINAL_ASSAULT","真实完成巡行")
        for _,id in ipairs(r.config.route_order) do t:Check(seen[id],"实际到达"..id) end
        t:Check(seconds<r.config.expedition_time_cap-8,"全站路线有后发队及攻核时间余量")
        print(string.format("[ExpansionRoute] stops=6 seconds=%.2f length=%.2f",seconds,detail.path_length))
    end)
    case("S11_TRIAL_COMPLETE", function(t)
        local r=trial(6); r.story_seen.final_intro=true; X.Sand(r,90,"boundary_income")
        r:StartAttack(); local seconds=0; local teams={}; local special=0
        -- 逐个公共伤害击杀，仅验全队列/胜负结算，不代表正常构筑平衡。
        while not r.ended and seconds<30 do
            r:Update(.1); seconds=seconds+.1
            for _,e in ipairs(r.enemies) do
                if e.alive then
                    if e.behavior=="expedition" then teams[e.squad_id]=(teams[e.squad_id] or 0)+1; special=special+1 end
                    Combat.DamageEnemy(r,e,e.hp+1,"boundary_clear")
                end
            end
            while r.pause_reasons.upgrade do r:ChooseUpgrade(r.options[1].id) end
        end
        t:Equal(r.result,"victory","全部队列/残敌/反应清空后通关")
        t:Equal(special,9,"实际生成九远征单位")
        for i=1,3 do t:Equal(teams[i],3,"实际每队三个角色") end
        t:Equal(r.exploration_currency_earned,110,"远征胜利收入只结算一次")
        local report=r.meta.scenario_reports[r.record_namespace] --[[@as table]]
        t:Equal(report.expansion.sand_earned,110,"结算事实带星砂")
        t:Equal(report.total_waves,21,"考验结算身份")
    end)
    case("S12_DELAYED_PROJECTILE", function(t)
        local r=trial(2); local unit=r.current_wave.special_units[2]
        local e=Combat.Spawn(r,unit) --[[@as table]]
        t:Check(e~=nil,"真实远射实体")
        e.stage="FINAL_ASSAULT"; e.x,e.y=r.core.x-4,r.core.y
        r.player.x,r.player.y=r.core.x+2,r.core.y; r.player.invulnerable=1000000
        Combat.Update(r,.05,{})
        local shot=nil --[[@as table?]]
        for _,b in ipairs(r.projectiles) do if b.team=="enemy" then shot=b end end
        t:Check(shot~=nil,"真实敌方弹体")
        t:Equal(shot.context.core_budget_room,"A2","发射保存末站来源")
        e.x,e.y=r.rooms[1].x,r.rooms[1].y; e.attack_cd=1000
        Combat.Update(r,.5,{})
        t:Check(r.core.hp<1000,"延迟弹体真实命中核心")
        t:Check(r.room_core_damage["21:A2"]~=nil,"命中仍计发射来源房")
        t:Equal(r.room_core_damage["21:A1"],nil,"换房不篡改弹体预算")
    end)
    case("S13_FX_ISOLATION", function(t)
        local old={}; for _,name in ipairs({"fx.Particle","fx.GameAudio","fx.Glow","ui.DamageNumber","utils.FPSMonitor","utils.PerfQuality"}) do old[name]=package.loaded[name] or false end
        t:Check(require("defense.FX")~=nil,"独立表现模块")
        t:Check(require("defense.fx.Particle")~=nil,"独立粒子加载")
        for name,value in pairs(old) do t:Equal(package.loaded[name] or false,value,"不加载/改写旧游戏模块") end
        t:Equal(require("defense.LegacyFX"),require("defense.FX"),"旧适配入口兼容")
    end)
end
return T
