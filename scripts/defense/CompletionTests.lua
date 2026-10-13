-- v0.2补齐项CPU回归。仅新建实例/边缘桩；不写存档、不build、不启动浏览器。
-- 演出时钟/绘制调度不代表高品质镜头声音；V17/V32–V34原NOT_RUN保持不变。
local Config = require("defense.Config")
local Run = require("defense.Run")
local Combat = require("defense.Combat")
local Reactions = require("defense.Reactions")
local Feedback = require("defense.Feedback")
local Map = require("defense.Map")
local C = {}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function fingerprint(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = fingerprint(key) .. "=" .. fingerprint(value[key]) end
    return "{" .. table.concat(parts, ";") .. "}"
end
---@return table
local function fresh(options, stationary)
    local settings = copy(options or {})
    settings.config = settings.config or copy(Config)
    if stationary then
        for _, def in pairs(settings.config.enemies) do def.speed = 0 end
    end
    local r = Run.New(settings)
    r:FinishStory()
    r.player.x, r.player.y, r.player.attack_cd = 32, 6, 1000
    return r
end
local function events(r, kind)
    local found = {}
    for _, event in ipairs(r.events) do if event.kind == kind then found[#found + 1] = event end end
    return found
end
local function eventById(r, id)
    for _, event in ipairs(r.events) do if event.event_id == id then return event end end
end
---@return table
local function spawn(t, r, unit, armed)
    local enemy = Combat.Spawn(r, unit)
    t:Check(type(enemy) == "table", "真实Combat.Spawn成功")
    if not armed then enemy.attack_cd = 1000 end
    return enemy --[[@as table]]
end
local function kill(t, r, enemy, context)
    t:Check(Combat.DamageEnemy(r, enemy, enemy.hp + 1, context or "completion_clear"), "提交真实击杀")
    t:Equal(enemy.alive, false, "实际死亡")
end
local function room(r, id)
    for _, item in ipairs(r.rooms) do if item.id == id then return item end end
    error("missing room " .. id)
end
-- 真实队列生成并强制击杀，只证明清波/报告边界，不冒充20分钟构筑实战。
local function clearQueue(t, r)
    local count = 0
    while not r.director.generation_complete do
        for _, enemy in ipairs(r.enemies) do if enemy.alive then kill(t, r, enemy) end end
        r.director:Update(1, r:AliveCount(), function(unit) return Combat.Spawn(r, unit) and true or false end)
        count = count + 1
        t:Check(count < 200, "队列有界完成")
    end
    for _, enemy in ipairs(r.enemies) do if enemy.alive then kill(t, r, enemy) end end
    t:Equal(r.director.emitted, #r.director.queue, "完整真实队列已生成")
end
local function settle(t, r)
    for _ = 1, 100 do
        if r:PendingHarmfulCount() == 0 then break end
        r:Update(0.05)
    end
    t:Equal(r:PendingHarmfulCount(), 0, "反应真实结算而非清空队列")
    r:Update(0.05)
end

-- 所有边缘桩在失败时也还原；不替换Run/Combat/Map，不调用真实File写入。
local function edge(modules, globals, body)
    local savedModules, savedGlobals = {}, {}
    for name, value in pairs(modules) do
        savedModules[name] = { value = package.loaded[name] }
        package.loaded[name] = value == false and nil or value
    end
    for name, value in pairs(globals) do
        savedGlobals[name] = { value = _G[name] }
        _G[name] = value
    end
    local ok, message = pcall(body)
    for name, old in pairs(savedModules) do package.loaded[name] = old.value end
    for name, old in pairs(savedGlobals) do _G[name] = old.value end
    if not ok then error(message, 0) end
end
local function presentation(body)
    local calls, globals = {}, {}
    local function stub(name)
        return function(...) calls[#calls + 1] = { name = name, args = { ... } }; return {} end
    end
    for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgFillColor", "nvgFill", "nvgMoveTo", "nvgLineTo",
        "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgCircle", "nvgFontFace", "nvgFontSize", "nvgTextAlign",
        "nvgText", "nvgEllipse", "nvgFillPaint", "nvgClosePath", "nvgSave", "nvgRestore", "nvgIntersectScissor",
        "nvgTranslate", "nvgRotate", "nvgGlobalAlpha", "nvgLineCap", "nvgScale", "nvgBeginFrame", "nvgEndFrame",
        "nvgDelete", "nvgRadialGradient", "nvgLinearGradient","nvgImagePattern","nvgDeleteImage" }) do globals[name] = stub(name) end
    local imageId=0
    globals.nvgCreateImage=function(...) imageId=imageId+1;calls[#calls+1]={name='nvgCreateImage',args={...}};return imageId end
    globals.NVG_IMAGE_NEAREST=1
    globals.nvgRGBA = function(red, green, blue, alpha) return { red, green, blue, alpha } end
    globals.NVG_ALIGN_CENTER, globals.NVG_ALIGN_MIDDLE, globals.NVG_ROUND = 2, 16, 1
    globals.GetAudio = false
    local widget = {}
    function widget:Extend() return {} end
    local ui = { Widget = widget, ProgressBar = widget }
    local modules = { ["defense.Board"] = false,['defense.TowerArt']=false, ["defense.LegacyFX"] = false, ["defense.FX"] = false,
        ["defense.View"] = false, ["defense.Radar"] = false, ["defense.Theme"] = false,
        ["defense.UIArt"] = false, ["defense.ProtoView"] = false, -- 仅Mode入口也须隔离类绑定的UI缓存。
        ["urhox-libs/UI"] = ui,
        ["defense.fx.Particle"] = { Reset = stub("Particle.Reset"), Update = stub("Particle.Update"), Spawn = stub("Particle.Spawn"), Render = stub("Particle.Render") },
        ["defense.fx.GameAudio"] = { Init = stub("Audio.Init"), Update = stub("Audio.Update"), PlayBGM = stub("Audio.BGM"), StopBGM = stub("Audio.Stop"), PlaySFX = stub("Audio.SFX") },
        ["defense.fx.DamageNumber"] = { Reset = stub("Number.Reset"), Update = stub("Number.Update"), Spawn = stub("Number.Spawn"), Render = stub("Number.Render"), fontId = -1 },
        ["defense.fx.ScreenShake"] = { Reset = stub("Shake.Reset"), Update = stub("Shake.Update"), Trigger = stub("Shake.Trigger"), offsetX = 0, offsetY = 0 } }
    edge(modules, globals, function() body(calls) end)
end
local function hasText(calls, text)
    for _, call in ipairs(calls) do
        if call.name == "nvgText" and tostring(call.args[4]):find(text, 1, true) then return true end
    end
    return false
end

function C.Register(case)
    case("WAVE_REST_REWARD", function(t)
        for _, elapsed in ipairs({ 40, 60, 75 }) do
            local r = fresh(nil, true)
            t:Near(r.preparation_remaining, 15, "首波只有基础战备")
            t:Near(r.rest_bonus, 0, "首波无赠送时间")
            r:StartAttack()
            r:Update(elapsed)
            t:Near(r.attack_elapsed, elapsed, "出怪结束后进攻时钟继续走")
            t:Equal(r.state, "ATTACK", "超时也不能强制清波")
            local bonus = math.max(0, 60 - elapsed)
            clearQueue(t, r)
            r:SettleWave()
            t:Equal(r.wave_id, 2, "清波只推进一波")
            t:Near(r.preparation_remaining, 15 + bonus, "实际用时决定休息奖励")
            t:Near(r.preparation_total, 15 + bonus, "进度条总长包含奖励")
            t:Near(r.rest_bonus, bonus, "奖励显示值")
            t:Near(events(r, "WaveCleared")[1].data.attack_elapsed, elapsed, "结算事件记录用时")
            local duration = r.preparation_remaining
            r:SettleWave()
            t:Near(r.preparation_remaining, duration, "重复结算不重复发奖励")
            r.player.experience = 0
            r:Update(1)
            t:Near(r.preparation_remaining, duration - 1, "延长战备正常倒计时")
            r:RequestWave()
            r:Update(8)
            t:Equal(r.state, "ATTACK", "奖励休息仍能主动跳过且完成预警")
            t:Check(r.attack_elapsed < 0.1, "新波不沿用上一波用时")
        end
    end)

    case("WAVE_REST_PAUSE_AND_DANGER", function(t)
        local r = fresh(nil, true)
        r:Update(3)
        t:Near(r.attack_elapsed, 0, "战备不计入进攻用时")
        r:StartAttack(); r:Update(20)
        for _, reason in ipairs({ "manual", "focus", "logistics", "upgrade", "story" }) do
            r:Pause(reason); r:Update(30)
            t:Near(r.attack_elapsed, 20, "暂停不消耗奖励：" .. reason)
            r:Resume(reason)
        end
        clearQueue(t, r)
        r.pending_harmful_reactions = 1
        r:SettleWave()
        t:Equal(r.wave_id, 1, "仍有有害反应时不能奖励或开下一波")
        r.pending_harmful_reactions = 0
        r:SettleWave()
        t:Near(r.preparation_remaining, 55, "暂停和战备时间没有扣除奖励")
        r:Pause("manual"); r:Update(30)
        t:Near(r.preparation_remaining, 55, "休息奖励随世界一起暂停")
        local final = fresh(nil, true)
        final.wave_id = 20; final:EnterPreparation(); final.story_seen.final_intro = true
        final:StartAttack(); final.director.generation_complete = true
        final:SettleWave()
        t:Equal(final.result, "victory", "最终波直接胜利")
        t:Near(events(final, "WaveCleared")[1].data.rest_bonus, 0, "最终波不发无用休息奖励")
    end)

    case("WORLD_DEPTH_ORDER", function(t)
        presentation(function(calls)
            local r = fresh(nil, true)
            r.player.x, r.player.y, r.player.emoji = 30, 19, "depth_player"
            r.core.x, r.core.y, r.core.emoji = 30, 21, "depth_core"
            r.towers = { { slot_id = "T1", type = "rapid", x = 30, y = 23, hp = 100, max_hp = 100, emoji = "depth_tower" } }
            r.enemies = {
                { id = 90, x = 30, y = 24, radius = 0.34, alive = true, role = "advance", hp = 30, max_hp = 30, emoji = "depth_front" },
                { id = 91, x = 30, y = 18, radius = 0.34, alive = true, role = "advance", hp = 30, max_hp = 30, emoji = "depth_back" },
            }
            local board = require("defense.Board").New(r)
            local function renderOrder()
                local first, order = #calls + 1, {}
                board:Render({}, 960, 640)
                for i = first, #calls do
                    local c = calls[i]
                    if c.name == "nvgText" and tostring(c.args[4]):find("depth_", 1, true) then order[#order + 1] = c.args[4]
                    elseif c.name=='nvgImagePattern' then order[#order+1]='depth_tower' end
                end
                return table.concat(order, ",")
            end
            local before = fingerprint(r)
            t:Equal(renderOrder(), "depth_back,depth_player,depth_core,depth_tower,depth_front", "渲染真正使用世界深度，核心不再强制置顶")
            t:Equal(fingerprint(r), before, "排序不改敌人列表和规则随机状态")
            r.player.y = 25
            t:Equal(renderOrder(), "depth_back,depth_core,depth_tower,depth_front,depth_player", "玩家跨过其他实体后遮挡顺序反转")
            r.enemies[1].y = 18
            local equalOrder = renderOrder()
            board.cameraY = board.cameraY + 0.1
            t:Equal(renderOrder(), equalOrder, "相同深度与相机移动保持稳定")
            local pillar = { x1 = 29, y1 = 18, x2 = 31, y2 = 20 }
            r.map.obstacles = { pillar }; r.player.y = 19
            local playerIndex, pillarIndex = 0, 0
            for i, item in ipairs(board:WorldDrawOrder()) do
                if item.kind == "player" then playerIndex = i end
                if item.entity == pillar then pillarIndex = i end
            end
            t:Check(playerIndex < pillarIndex, "柱体底边覆盖后方角色")
            r.player.y = 21
            for i, item in ipairs(board:WorldDrawOrder()) do
                if item.kind == "player" then playerIndex = i end
                if item.entity == pillar then pillarIndex = i end
            end
            t:Check(playerIndex > pillarIndex, "前方角色覆盖柱体")
        end)
    end)

    case("AUDIT_UPGRADE_PREVIEW", function(t)
        local P = require("defense.Progression")
        local r = fresh(nil, true)
        r.player.x, r.player.y = 30, 26
        local before = fingerprint({ r:Snapshot(), r.player, r.events })
        for _, definition in ipairs(P.skills) do
            t:Check(#P.Preview(r, definition.id) > 0, "全部成长项提供数值说明")
        end
        for _, id in ipairs({ "heal_bonus", "gold_bonus", "cooldown_bonus" }) do
            t:Check(#P.Preview(r, id) > 0, "补给也展示实际变化")
        end
        t:Equal(fingerprint({ r:Snapshot(), r.player, r.events }), before, "预览不改变局内状态或随机序列")
        local preview = P.Preview(r, "power")
        t:Check(P.Apply(r, "power"), "实际应用火力成长")
        spawn(t, r, { role = "advance", portal = "S", x = 30, y = 29 })
        r.player.attack_cd = 0
        Combat.Update(r, 0.01, {})
        local projectile = r.projectiles[1] --[[@as table?]]
        t:Check(projectile ~= nil, "真实战斗生成弹体")
        t:Check(preview:find(string.format("%.2f", projectile.damage), 1, true) ~= nil, "预览伤害与真实弹体一致")
        r.player.skills.pulse, r.player.skills.relay = 1, 1
        local relayPreview = P.Preview(r, "relay")
        r.player.level = 4
        t:Check(P.Apply(r, "relay"), "实际应用冷却成长")
        t:Check(Combat.Active(r), "真实释放击退")
        t:Check(relayPreview:find(string.format("%.2f", r.player.active_cd), 1, true) ~= nil, "预览冷却与真实释放一致")
        r.player.hp = r.player.max_hp - 3
        local healing = P.Preview(r, "heal_bonus")
        P.Apply(r, "heal_bonus")
        t:Check(healing:find(string.format("%.2f", r.player.hp), 1, true) ~= nil, "治疗预览按实际缺血封顶")
    end)
    case("COMPLETION_STAGE", function(t)
        local r = fresh({ seed = 7701 }, true)
        local chainRoot = "completion:real-chain"
        for wave = 1, 5 do
            t:Equal(r.wave_id, wave, "连续真实波次")
            t:Check(r:RequestWave(), "开波请求")
            r:Update(8)
            t:Equal(r.state, "ATTACK", "预警后攻击")
            clearQueue(t, r)
            if wave == 5 then
                local a = spawn(t, r, { role = "advance", portal = "S", x = 32, y = 22.5, subtype = "explosive" })
                local b = spawn(t, r, { role = "advance", portal = "S", x = 32, y = 24.5, subtype = "explosive" })
                b.hp = 35 -- 第二只确由40点真实死亡爆炸击杀，不是fake Explosion日志。
                local pendingBefore = r:PendingHarmfulCount()
                kill(t, r, a, { source = "player", source_id = "player", root_action_id = chainRoot })
                t:Equal(r:PendingHarmfulCount(), pendingBefore + 1, "新增死亡反应阻止阶段报告")
                t:Equal(#r.stage_reports, 0, "完整反应前无报告")
            end
            settle(t, r)
        end
        t:Equal(r.wave_id, 6, "阶段边界不暂停后续世界")
        t:Equal(#r.stage_reports, 1, "5波只记一次")
        local report = r.stage_reports[1]
        t:Equal(report.wave, 5, "真实阶段5快照")
        t:Check(#report.chains >= 1 and #report.chains <= 2, "1–2条已提交链")
        local chain = report.chains[1]
        t:Equal(chain.root_action_id, chainRoot, "链来自实际击杀root")
        t:Equal(chain.explosions, 2, "两层真实反应")
        t:Equal(chain.kills, 2, "两次实际死亡")
        t:Equal(chain.core_damage, 80, "记录真实核心损失而非避免伤害")
        t:Check(#chain.segments > 0, "完整事实段而非只剩计数")
        local kinds = {}
        for _, segment in ipairs(chain.segments) do
            local event = eventById(r, segment.event_id)
            t:Check(event ~= nil, "快照每段来自真实事件")
            t:Equal(segment.kind, event.kind, "段类型匹配")
            t:Equal(segment.root_action_id, chainRoot, "段root匹配")
            if segment.position then t:Equal(fingerprint(segment.position), fingerprint(event.data.position), "死点坐标匹配") end
            kinds[segment.kind] = true
        end
        t:Check(kinds.Hit and kinds.EnemyDied and kinds.ReactionScheduled and kinds.Explosion, "完整击杀→死亡→计划→爆炸")
        local snapshot, eventSnapshot = fingerprint(report), fingerprint(events(r, "StageReportReady")[1].data.report)
        local live = r.causal_by_root[chainRoot]
        t:Check(live ~= chain and live.segments ~= chain.segments, "报告深拷贝mutable summary")
        local later = spawn(t, r, { role = "advance", portal = "W", x = 30, y = 16 })
        Combat.DamageEnemy(r, later, 1, { source = "player", source_id = "player", root_action_id = chainRoot })
        live.segments[1].position.x = -999 -- 专门探针：历史源坐标改变不能污染已记快照。
        t:Equal(fingerprint(report), snapshot, "后续同root及源表变更不污染阶段快照")
        t:Equal(fingerprint(events(r, "StageReportReady")[1].data.report), eventSnapshot, "报告事件也独立快照")
        t:Equal(#events(r, "StageReportReady"), 1, "无重记阶段")
    end)

    case("COMPLETION_REPORT", function(t)
        local r = fresh({ total_waves = 5 }, true)
        r.player.experience, r.currency, r.core.hp = 13, 11, 820
        t:Check(r:End("victory", "report boundary fixture"), "真实End提交胜利报告")
        local victory, saved = r.meta.last_report, fingerprint(r.meta.last_report)
        t:Equal(victory.result, "victory", "保存victory")
        t:Equal(victory.currency, 11, "实际结算资金")
        local retry = Run.New { meta = r.meta, retry = true }
        t:Equal(fingerprint(retry.meta.last_report), saved, "重试保上局报告")
        t:Equal(retry.player.experience, 0, "重试经验reset")
        t:Equal(retry.currency, 60, "重试资金reset")
        t:Equal(retry.core.hp, 1000, "重试核心reset")
        t:Equal(#retry.stage_reports, 0, "重试本局阶段reset")
        t:Equal(#retry.economy_facts, 0, "重试本局经济reset")
        t:Equal(#retry.towers, 0, "重试设施reset")
        t:Equal(fingerprint(retry.player.skills), fingerprint({ power = 1, pierce = 1 }), "重试构筑reset")
        retry:Close("离开未完成局")
        t:Equal(retry.meta.last_report, victory, "abandoned不覆盖last_report")
        local defeat = fresh({ meta = retry.meta }, true)
        defeat.core.hp = 0; defeat:Update(0.05)
        t:Equal(defeat.result, "defeat", "真实失败判定")
        t:Equal(defeat.meta.last_report.result, "defeat", "最后失败覆盖胜利")
        t:Check(defeat.meta.last_report ~= victory, "只保最后一局而非报告队列")
        t:Equal(defeat:End("victory"), false, "不能重判/重写报告")
        local report = fingerprint(defeat.meta.last_report)
        defeat.totals.core_damage = 999; defeat.stage_reports[1] = { wave = 999 }
        t:Equal(fingerprint(defeat.meta.last_report), report, "End后源表变更不污染报告")
    end)

    case("COMPLETION_SELECT", function(t)
        local r = fresh(nil, true)
        local function push(root, x)
            local e = spawn(t, r, { role = "advance", portal = "W", x = x, y = 16 })
            t:Check(Combat.Displace(r, e, 0, 1, 0.2, { source = "active", source_id = "player", root_action_id = root }), "真实位移建摘要")
            return e
        end
        local a = push("old-late-root", 30)
        r:Update(0.05); push("middle-root", 31)
        r:Update(0.05); push("new-root", 32)
        r:Update(0.05)
        Combat.DamageEnemy(r, a, 1, { source = "player", source_id = "player", root_action_id = "shot-later" })
        t:Equal(r.causal_history[1].root_action_id, "old-late-root", "late root仍保持FIFO原插入位置")
        local selected = Feedback.Select(r, 1, 5)
        t:Equal(#selected, 2, "仅最近两条")
        t:Equal(selected[1].root_action_id, "old-late-root", "按最新summary.time而非FIFO")
        t:Equal(selected[2].root_action_id, "new-root", "次新root")
        t:Check(selected[1] ~= r.causal_history[1], "返回深快照")
        t:Equal(#Feedback.Select(r, 2, 5), 0, "排除其他阶段")
        local before = fingerprint(r)
        Feedback.Select(r, 1, 5)
        t:Equal(fingerprint(r), before, "Select只读全部run")
    end)

    case("COMPLETION_ECONOMY", function(t)
        local r = fresh(nil, true)
        r.currency, r.core.hp, r.player.hp = 1000, 950, 90
        t:Check(r:OpenLogistics(), "后勤真实入口")
        local specs = { { "repair", nil, nil, 40, 50, 0, 0 }, { "heal", nil, nil, 20, 0, 10, 0 },
            { "build", "T1", "rapid", 80, 0, 0, 0 }, { "upgrade", "T1", nil, 60, 0, 0, 0 },
            { "demolish", "T1", nil, 0, 0, 0, 70 } }
        for i, spec in ipairs(specs) do
            local id = "completion-tx-" .. i
            local result = r:Transact(spec[1], spec[2], spec[3], id)
            t:Check(result.ok, "真实合法交易" .. spec[1])
            local fact = r.economy_facts[#r.economy_facts]
            t:Equal(fact.action, spec[1], "事实操作")
            t:Equal(fact.spend, spec[4], "实际支出")
            t:Equal(fact.repair, spec[5], "实际修复不虚报200")
            t:Equal(fact.heal, spec[6], "实际治疗不虚报25")
            t:Equal(fact.refund, spec[7], "实际拆除返款")
            t:Equal(fact.currency, r.currency, "实际余额")
            local before, n = fingerprint({ r.currency, r.core, r.player, r.towers, r.economy_facts }), #events(r, "TransactionResolved")
            t:Equal(r:Transact(spec[1], spec[2], spec[3], id), result, "重复tx返回原结果")
            t:Equal(fingerprint({ r.currency, r.core, r.player, r.towers, r.economy_facts }), before, "重复tx不二次记录或结算")
            t:Equal(#events(r, "TransactionResolved"), n, "重复tx无二次反馈事件")
        end
        local n = #r.economy_facts
        t:Equal(r:Transact("heal", nil, nil, "full-hp").ok, false, "非法交易拒绝")
        t:Equal(#r.economy_facts, n, "拒绝不记录收益")
        for i = 1, 5 do r.player.hp = 99; t:Check(r:Transact("heal", nil, nil, "cap-" .. i).ok, "有界账本追加") end
        t:Equal(#r.economy_facts, 8, "最后8笔事实有界")
        r:Resume("logistics"); r:End("defeat", "ledger fixture")
        t:Equal(fingerprint(r.meta.last_report.economy), fingerprint(r.economy_facts), "End保存实际经济事实")
    end)

    case("COMPLETION_OBSERVATION", function(t)
        for _, id in ipairs({ "explosive", "slow" }) do
            local r = fresh(nil, true)
            r.player.x, r.player.y = 23, 21
            local e = spawn(t, r, { role = "advance", portal = "W", x = 29, y = 21, subtype = id == "explosive" and "explosive" or nil })
            if id == "slow" then Combat.ApplySlow(r, e, 0.35, 20, "test-observation") end
            t:Equal(r.map:LineOfSight(r.player.x, r.player.y, e.x, e.y), false, "柱后近身真实LOS拒绝")
            Feedback.Update(r)
            t:Equal(#events(r, "ObservationHint"), 0, "柱后不得提示" .. id)
            r.player.x, r.player.y, r.clock = 32, 6, r.clock + 0.25
            Feedback.Update(r)
            t:Equal(#events(r, "ObservationHint"), 0, "视野远距不得提示")
            r.player.x, r.player.y, r.clock = 29, 23, r.clock + 0.25
            r.meta.settings = { hints = false }
            Feedback.Update(r)
            t:Equal(r.meta.observation_seen[id], nil, "关闭提示不消费首次观察")
            r.meta.settings.hints = true; r.clock = r.clock + 0.25
            local before = fingerprint({ r.player, e, r.core, r.currency, r.scheduled_events })
            Feedback.Update(r)
            t:Equal(fingerprint({ r.player, e, r.core, r.currency, r.scheduled_events }), before, "提示不自动授技能/造成伤害/改变资金")
            t:Equal(#events(r, "ObservationHint"), 1, "真实近身LOS首次提示")
            t:Check(r.observation_seen[id] and r.meta.observation_seen[id], "本局/持久seen均记录")
            local remaining = r.observation_hint.expires_at - r.clock
            r:Pause("manual"); r:Update(7); r:PresentationUpdate(7); Feedback.Update(r)
            t:Near(r.observation_hint.expires_at - r.clock, remaining, "暂停冻结提示有效时限")
            r:Resume("manual"); r.player.x, r.player.y = 32, 6
            r:Update(5.1)
            t:Check(r.observation_hint.expires_at <= r.clock, "有效世界时间后收起")
            t:Equal(Feedback.Observe(r, id), false, "已seen不重复展开")
            local nextRun = fresh({ meta = r.meta }, true)
            t:Equal(Feedback.Observe(nextRun, id), false, "下一局持久seen仍收起")
        end
    end)

    case("COMPLETION_STORY", function(t)
        local r = Run.New { retry = true }
        t:Equal(r.story.duration, 3, "retry opening3")
        r:PresentationUpdate(2.9); t:Equal(r.state, "DEPLOY", "short opening完整末尾前不部署")
        r:PresentationUpdate(0.1); t:Equal(r.state, "PREPARATION", "short opening交接")
        local revision, world = r.meta.revision, fingerprint(r:Snapshot())
        t:Check(r:ReplayStory("opening"), "已见opening回看")
        t:Equal(r.story.duration, 14, "retry也回看完整opening14")
        r:PresentationUpdate(13.9); t:Equal(r.story.node, "opening", "回看末尾前不中断")
        r:PresentationUpdate(0.1)
        t:Equal(fingerprint(r:Snapshot()), world, "回看不部署/改世界")
        t:Equal(r.meta.revision, revision, "回看不二次Save")
        r.wave_id = 20; r:EnterPreparation(); r:RequestWave(); r:Update(8)
        t:Equal(r.story.node, "final_intro", "真实final入口")
        t:Equal(r.story.duration, 4, "retry final4")
        r:PresentationUpdate(4)
        t:Equal(r.state, "WARNING", "final后重进预警")
        t:Near(r.warning_elapsed, 0, "final后完整warning重新计时")
        r:Update(7.9); t:Equal(r.director.emitted, 0, "final后7.9不生成")
        r:Update(0.1); t:Equal(r.state, "ATTACK", "final后8秒生成")
        local cursor = r.director.cursor
        t:Check(r:ReplayStory("final_intro"), "已见final回看")
        t:Equal(r.story.duration, 8, "retry也回看完整final8")
        r:PresentationUpdate(8); t:Equal(r.director.cursor, cursor, "回看不重开队列")
        t:Check(r:End("victory", "story ending fixture"), "真实End触发ending")
        t:Equal(r.story.duration, 5, "retry ending5")
        r:PresentationUpdate(4.9); t:Equal(r.story.node, "ending", "short ending末尾前有效")
        r:PresentationUpdate(0.1); t:Check(r.meta.story_seen.ending, "short ending正常seen")
        t:Check(r:ReplayStory("ending"), "已见ending回看")
        t:Equal(r.story.duration, 14, "回看完整ending14")
        r:PresentationUpdate(14); t:Equal(r.result, "victory", "ending回看不重判结局")
    end)

    case("COMPLETION_MODAL", function(t)
        local r = fresh(nil, true)
        for _, reason in ipairs({ "logistics", "upgrade", "rules", "recap" }) do
            r:Pause("menu"); r:Pause("manual"); r:Pause(reason)
            local before = fingerprint(r)
            t:Equal(r:ReplayStory("opening"), false, "嵌套" .. reason .. "拒绝回看")
            t:Equal(fingerprint(r), before, "拒绝不改story/state/暂停/事件")
            r:Resume(reason); r:Resume("manual"); r:Resume("menu")
        end
        presentation(function()
            local View = require("defense.View")
            local v = setmetatable({ run = r, menuOpen = true, replayPreview = true }, View)
            r:Pause("menu"); t:Check(r:ReplayStory("opening"), "菜单回看可播放")
            t:Equal(v:Mode(), "story:opening", "回看从菜单可见")
            r:PresentationUpdate(1); r:Pause("focus")
            local before = fingerprint(r)
            t:Equal(v:Mode(), "pause", "菜单回看失焦显示可恢复暂停")
            t:Equal(fingerprint(r), before, "Mode只读")
            r:PresentationUpdate(5); t:Near(r.story.elapsed, 1, "失焦freeze回看")
            r:Resume("focus"); t:Equal(v:Mode(), "story:opening", "恢复回看可见")
            r:PresentationUpdate(13); t:Equal(v:Mode(), "menu", "回看结束返回菜单")
            t:Check(r.pause_reasons.menu, "菜单暂停不消失")
            r:Pause("rules"); r:Pause("recap")
            t:Equal(v:Mode(), "rules", "rules优先于recap/menu")
            r:Resume("rules"); t:Equal(v:Mode(), "recap", "仅关闭rules保recap")
        end)
    end)

    case("COMPLETION_STORAGE", function(t)
        local primary, backup = "defense_meta_v1.json", "defense_meta_v1.backup.json"
        local data, behavior, disposed, constructed = {}, {}, {}, {}
        local function meta(revision)
            return { schema_version = 1, revision = revision, stages = {}, chapters = { ["1"] = true }, story_seen = {} }
        end
        local globals = { FILE_READ = "read-stub", FILE_WRITE = "write-stub" }
        globals.fileSystem = { FileExists = function(_, path) return data[path] ~= nil or behavior[path] ~= nil end }
        globals.File = function(path, mode)
            t:Equal(mode, "read-stub", "CPU存储回归绝不真实写档")
            constructed[path] = (constructed[path] or 0) + 1
            if behavior[path] == "constructor" then error("File construction probe") end
            return { IsOpen = function() return behavior[path] ~= "closed" end,
                ReadString = function()
                    if behavior[path] == "read" then error("ReadString probe") end
                    return path -- JSON解码边缘桩映射token，不替换Storage校验/回退逻辑。
                end,
                Dispose = function() disposed[path] = (disposed[path] or 0) + 1 end }
        end
        edge({ ["defense.Storage"] = false, cjson = { decode = function(token)
            if behavior[token] == "decode" then error("decode probe") end
            return copy(data[token])
        end } }, globals, function()
            local Storage = require("defense.Storage")
            for _, mode in ipairs({ "read", "closed", "decode", "constructor" }) do
                data[primary], data[backup], behavior[primary] = meta(1), meta(17), mode
                disposed, constructed = {}, {}
                t:Equal(Storage.Load().revision, 17, "异常/损坏主档回退Backup:" .. mode)
                t:Equal(disposed[backup], 1, "Backup读取对象Dispose")
                if mode ~= "constructor" then t:Equal(disposed[primary], 1, "异常主档对象仍Dispose") end
            end
            behavior = {}
            local invalid = { false, "3", -1, 1.5, math.huge, 0 / 0 }
            for _, revision in ipairs(invalid) do
                data[primary], data[backup] = meta(revision), meta(17)
                t:Equal(Storage.Load().revision, 17, "无效revision回退:" .. tostring(revision))
            end
            local settings = { { volume = -0.1 }, { volume = 1.1 }, { volume = "0.5" }, { volume = 0 / 0 },
                { hints = "false" }, { reduced_effects = 1 } }
            for _, bad in ipairs(settings) do
                data[primary] = meta(1); data[primary].settings = bad
                t:Equal(Storage.Load().revision, 17, "settings非法值回退Backup")
            end
            data[primary] = meta(2); data[primary].settings = { volume = 0, reduced_effects = true, hints = false }
            local loaded = Storage.Load()
            t:Equal(loaded.settings.volume, 0, "合法静音0保持")
            t:Equal(loaded.settings.hints, false, "合法关闭提示保持")
            t:Equal(loaded.settings.reduced_effects, true, "合法低表现保持")
            data[primary], data[backup] = meta(nil), nil
            data[primary].stages["1:5"] = { chapter = 1, wave = 5, completed = true }
            loaded = Storage.Load()
            t:Equal(loaded.revision, 0, "旧v1缺revision迁移")
            t:Check(loaded.stages["1:5"].completed, "旧v1阶段保留")
            t:Equal(loaded.settings.volume, 1, "旧optional settings默认")
            t:Check(loaded.settings.hints, "旧optional hints默认启用")
            local r = Run.New { meta = loaded }
            t:Equal(type(r.meta.observation_seen), "table", "旧v1缺observations可初始化")
            data[primary], data[backup] = nil, nil
            disposed, constructed = {}, {}
            t:Equal(Storage.Load().schema_version, 1, "无档回退默认")
            t:Equal(next(constructed), nil, "无档不构造File")
        end)
    end)

    case("COMPLETION_ROOMS", function(t)
        local cfg = copy(Config)
        cfg.rooms[2].unlocked, cfg.rooms[4].unlocked, cfg.rooms[6].unlocked = true, true, true
        cfg.locked_rooms = { A2 = true, B2 = false, C2 = true }
        local r = fresh({ config = cfg }, true)
        for _, item in ipairs(r.rooms) do
            t:Equal(item.unlocked, r.map.locked[item.id] ~= true, "Run/Map配置锁状态一致:" .. item.id)
            t:Equal(r.map:IsWalkable(item.x, item.y, 0.35), item.unlocked, "锁房通行一致")
        end
        t:Equal(room(r, "A2").unlocked, false, "locked_rooms优先room.unlocked")
        t:Equal(room(r, "B2").unlocked, true, "显式locked_rooms=false开房")
        for _, id in ipairs({ "A1", "C1" }) do
            local item = room(r, id)
            r.player.x, r.player.y = item.x, item.y
            Combat.UpdateRooms(r, 0)
            t:Equal(item.state, "active", "真实入房激活")
            for _, enemy in ipairs(r.enemies) do if enemy.alive and enemy.room_id == id then kill(t, r, enemy) end end
            Combat.UpdateRooms(r, 0)
            local unlocked = room(r, item.unlock)
            t:Equal(item.state, "cleared", "真实守军清空")
            t:Check(unlocked.unlocked and not r.map.locked[unlocked.id], "清房即解锁Run/Map")
            t:Check(r.map:IsWalkable(unlocked.x, unlocked.y, 0.35), "解锁后可走")
            t:Equal(item.reward_claimed, false, "解锁不要求领奖")
        end
        t:Equal(cfg.locked_rooms.A2, true, "本局开房不改共享配置")
    end)

    case("COMPLETION_PRESENTATION", function(t)
        local r = fresh(nil, true)
        local e = spawn(t, r, { role = "advance", portal = "S", x = 32, y = 27 })
        Combat.ApplySlow(r, e, 0.35, 0.2, "strong-short")
        Combat.ApplySlow(r, e, 0.1, 2, "weak-long")
        t:Near(e.slow_factor, 0.65, "逻辑取最强35%")
        presentation(function(calls)
            local Board, FX = require("defense.Board"), require("defense.LegacyFX")
            FX.Init()
            local board = Board.New(r, { pixelsPerCell = 40 })
            local before = fingerprint(r)
            board:Events(r.events); board:Update(0.05)
            t:Equal(fingerprint(r), before, "Board表现事件/Update不改run")
            board:DrawEnemy({}, e, 100, 100, 40, false)
            t:Check(hasText(calls, "-35% 余0.2s"), "强35%只报自身0.2s不混弱2s")
            t:Equal(hasText(calls, "-35% 余2.0s"), false, "不得强百分比配弱时限")
            local boardBefore = fingerprint(board)
            board:Render({}, 960, 640)
            t:Equal(fingerprint(board), boardBefore, "Render只读表现缓存")
            t:Equal(fingerprint(r), before, "完整nvg记录桩只presentation不改run")
            r.projectiles = { { id = 990, x = 0, y = 0, dx = 1, dy = 0, radius = 0.08, team = "enemy", source = "ranged", pierce = 0, alive = true } }
            local start = #calls
            board:DrawProjectiles({}, 100, 100, 40, 960, 640)
            local enemyCalls = {}; for i = start + 1, #calls do enemyCalls[#enemyCalls + 1] = calls[i] end
            t:Equal(hasText(enemyCalls, Config.character.bullets.normal.emoji), false, "敌弹不能套角色普通弹外观")
            t:Equal(hasText(enemyCalls, Config.character.bullets.pierce.emoji), false, "敌弹不能套角色穿透外观")
            r.projectiles[1].team, r.projectiles[1].source, r.projectiles[1].pierce = "player", "player", 1
            start = #calls; board:DrawProjectiles({}, 100, 100, 40, 960, 640)
            local playerCalls = {}; for i = start + 1, #calls do playerCalls[#playerCalls + 1] = calls[i] end
            t:Check(hasText(playerCalls, Config.character.bullets.pierce.emoji), "玩家真实pierce保原作外观")
            board:Destroy(); FX.Stop()
        end)
        r.projectiles = {} -- 上面只绘制的最小presentation弹体不交给规则Update。
        Combat.Update(r, 0.21)
        t:Near(e.slow_factor, 0.9, "强短来源到期退为弱长来源")
        presentation(function(calls)
            local board = require("defense.Board").New(r)
            board:DrawEnemy({}, e, 100, 100, 40, false)
            t:Check(hasText(calls, "-10% 余1.8s"), "弱来源接替百分比/时限同步")
        end)
    end)

    case("COMPLETION_ATTACK_SOURCES", function(t)
        for _, kind in ipairs({ "core", "player", "tower", "area", "charge", "ranged" }) do
            local r = fresh(nil, true)
            local role = kind == "area" and "commander" or kind == "charge" and "charger" or kind == "ranged" and "ranged" or "advance"
            local x, y = 32, 23
            if kind == "player" then r.player.x, r.player.y, y = 32, 25, 25.8
            elseif kind == "tower" then
                r.currency = 1000; r:OpenLogistics(); r:Transact("build", "T1", "rapid", "attack-tower"); r:Resume("logistics")
                -- 塔在朝核心方向，且距敌人.8 <= .34+.65+.22；不得摆在身后冒充阻挡。
                r.towers[1].attack_cd = 1000; x, y = 27, 13.2
            elseif kind == "area" or kind == "charge" then y = 25
            elseif kind == "ranged" then r.player.x, r.player.y, y = 32, 25, 29 end
            local e = spawn(t, r, { role = role, portal = "S", x = x, y = y }, true)
            if kind == "area" then e.area_cd = 0 end
            Combat.Update(r, kind == "area" and 0.8 or kind == "charge" and 1.2 or kind == "ranged" and 0.5 or 0.05)
            local damageKind = kind == "ranged" and "PlayerDamaged" or "CoreDamaged"
            if kind == "player" then damageKind = "PlayerDamaged" elseif kind == "tower" then damageKind = "TowerDamaged" end
            local damage = events(r, damageKind)[1]
            t:Check(damage ~= nil, "真实enemy攻击造成" .. kind .. "伤害")
            t:Equal(damage.source_id, e.entity_id, "真实攻击source_id不是effect:" .. kind)
            local parent = eventById(r, damage.parent_event_id)
            t:Check(parent ~= nil, "damage直接父事件存在")
            t:Equal(parent.kind, kind == "ranged" and "Shoot" or "EnemyAttack", "真实攻击父事件")
            t:Equal(parent.source_id, e.entity_id, "父source_id同enemy")
            t:Equal(parent.root_action_id, damage.root_action_id, "父子root一致")
            if kind ~= "ranged" then
                t:Equal(parent.data.attack_kind, kind == "area" and "area" or kind == "charge" and "charge" or "melee", "明确攻击类别")
            end
            if kind == "charge" then t:Equal(#events(r, "EnemyAttack"), 1, "charge扫掠不逐帧生成新动作") end
        end
    end)

    case("COMPLETION_DISPLACED_PARENT", function(t)
        local r = fresh(nil, true)
        r.player.x, r.player.y = 32, 25
        local e = spawn(t, r, { role = "advance", portal = "S", x = 32, y = 27, subtype = "explosive" })
        t:Check(Combat.Active(r), "真实Active无伤位移")
        local displacement = events(r, "Displaced")[1]
        t:Equal(e.hp, e.max_hp, "Active不直接伤害")
        r.player.attack_cd = 0
        Combat.Update(r, 0.5)
        local hit = events(r, "Hit")[1]
        t:Check(hit ~= nil, "位移后真实player弹命中")
        local shoot = eventById(r, hit.parent_event_id)
        t:Check(shoot and shoot.kind == "Shoot", "近期Displaced不吞Shoot直接parent")
        t:Equal(hit.root_action_id, displacement.root_action_id, "只将解释root关联位移")
        t:Equal(hit.data.related_displacement_event_id, displacement.event_id, "位移关联单独字段")
        t:Equal(hit.data.triggering_action_id, shoot.root_action_id, "保留真实射击动作身份")
        local context = { source = "player", source_id = "player", root_action_id = shoot.root_action_id, parent_event_id = shoot.event_id }
        kill(t, r, e, context)
        local death = events(r, "EnemyDied")[1]
        local scheduled = events(r, "ReactionScheduled")[1]
        t:Equal(eventById(r, death.parent_event_id).kind, "Hit", "Death直接parent仍是Hit")
        t:Equal(scheduled.parent_event_id, death.event_id, "Reaction直接parent仍是死亡")
        t:Equal(scheduled.data.related_displacement_event_id, displacement.event_id, "位移关联透传死亡反应")
        t:Equal(scheduled.data.source_id, e.entity_id, "反应源确为死者")
    end)

    case("COMPLETION_REACTION_CONFIG", function(t)
        local cfg = copy(Config)
        cfg.reactions.delay, cfg.reactions.radius, cfg.reactions.damage = 0.31, 1.75, 17
        cfg.enemies.advance.death_reaction = { delay = 0.42, radius = 2.25 }
        local specs = { { unit = { delay = 0.11, damage = 9 }, expected = { 0.11, 1.75, 9 } },
            { expected = { 0.42, 2.25, 17 } }, { noDef = true, expected = { 0.31, 1.75, 17 } } }
        for _, spec in ipairs(specs) do
            local ownCfg = copy(cfg); if spec.noDef then ownCfg.enemies.advance.death_reaction = nil end
            local r = fresh({ config = ownCfg }, true)
            local e = spawn(t, r, { role = "advance", portal = "S", x = 32, y = 25,
                subtype = "explosive", death_reaction = spec.unit })
            kill(t, r, e)
            local job = r.scheduled_events[1]
            t:Near(job.delay, spec.expected[1], "unit>def>config逐字段delay")
            t:Near(job.radius, spec.expected[2], "unit对象优先def对象；缺字段回退config")
            t:Near(job.damage, spec.expected[3], "逐字段damage回退")
            t:Near(job.at - r.clock, spec.expected[1], "计划时限使用覆盖参数")
            local event = events(r, "ReactionScheduled")[1]
            t:Equal(event.data.damage, job.damage, "警告反馈与实际参数一致")
        end
        local r = fresh(nil, true)
        local e = spawn(t, r, { role = "advance", portal = "W", x = 30, y = 16, subtype = "explosive" })
        kill(t, r, e)
        t:Near(r.scheduled_events[1].delay, 0.7, "默认delay保持")
        t:Near(r.scheduled_events[1].radius, 2.5, "默认radius保持")
        t:Equal(r.scheduled_events[1].damage, 40, "默认damage保持")
    end)

    case("COMPLETION_PATH_WARM", function(t)
        local cold, partial, warm = Map.New(Config), Map.New(Config), Map.New(Config)
        local target, radius = Config.core_position, 0.32
        local points = { { 23.3, 21.95 }, { 23.4, 19.5 }, { 27.6, 23.6 }, { 36.3, 21.8 },
            { 40.5, 22.6 }, { 22.7, 16.3 }, { 41.3, 25.7 }, { 17.1, 21.1 } }
        partial:Path(17, 21, target.x, target.y, radius, 48)
        for _, p in ipairs(points) do warm:Path(p[1], p[2], target.x, target.y, radius) end
        for _, p in ipairs(points) do
            local reference = Map.New(Config):Path(p[1], p[2], target.x, target.y, radius)
            t:Check(reference ~= nil, "continuous合法坐标有路径")
            for _, map in ipairs({ cold, partial, warm }) do
                local path = map:Path(p[1], p[2], target.x, target.y, radius)
                t:Equal(fingerprint(path), fingerprint(reference), "cold/partial/warm锚点选择一致")
                for i = 2, #path do
                    t:Check(map:LineOfSight(path[i - 1].x, path[i - 1].y, path[i].x, path[i].y, radius), "连续路径不穿柱")
                end
            end
        end
        local a = fresh({ seed = 8801, run_id = "warm-compare" })
        local b = fresh({ seed = 8801, run_id = "warm-compare" })
        for _, r in ipairs({ a, b }) do r.wave_id = 19; r:EnterPreparation() end
        local before = fingerprint({ b:Snapshot(), b.events, b.rooms })
        for _ = 1, 1000 do
            if b.map.warmupCursor > #b.map.warmupJobs then break end
            b.map:Warmup(48)
        end
        t:Check(b.map.warmupCursor > #b.map.warmupJobs, "W19实际预热jobs有界完成")
        t:Equal(fingerprint({ b:Snapshot(), b.events, b.rooms }), before, "预热不改规则/身份/RNG/事件")
        for _, r in ipairs({ a, b }) do r.warning_elapsed = 8; r:StartAttack(); r:Update(2) end
        t:Equal(fingerprint(a.enemies), fingerprint(b.enemies), "W19冷热敌人移动/攻击一致")
        t:Equal(fingerprint(a.projectiles), fingerprint(b.projectiles), "W19冷热弹体一致")
        t:Equal(fingerprint(a:Snapshot()), fingerprint(b:Snapshot()), "W19冷热世界快照一致")
        t:Equal(fingerprint(a.events), fingerprint(b.events), "W19冷热真实事件流一致")
    end)
end
return C
