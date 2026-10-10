-- 阶段复盘与观察提示只使用已提交事实；不从按键次数推断玩家理解或意图。
local F = {}
local SOURCE_NAMES = { player = "角色射击", active = "无伤击退", death_explosion = "死亡爆炸",
    tower_rapid = "速射塔", tower_slow = "减速塔", tower_area = "范围塔", enemy_attack = "敌方攻击",
    ranged = "敌方远射", pickup = "实际拾取", effect = "公共效果" }
local HINTS = {
    explosive = "爆炸标记的敌人在哪死亡，就在哪爆炸；爆炸也会伤害核心。",
    slow = "减速有持续时间，离开覆盖区后不会继续刷新；另一条路线仍可能承压。",
}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
function F.Init(run)
    run.stage_reports, run.observation_seen, run.economy_facts = {}, {}, {}
    run.economy_totals = { spend = 0, refund = 0, service_spend = 0, by_action = {} }
    run.observation_hint = { id = "", text = "", expires_at = 0 }
    run.meta.observation_seen = run.meta.observation_seen or {}
    run.next_observation_check = 0
end
function F.Select(run, firstWave, lastWave)
    local candidates, selected, roots = {}, {}, {}
    for _, summary in ipairs(run.causal_history) do
        roots[summary.root_action_id] = summary
    end
    for root, summary in pairs(run.causal_by_root) do roots[root] = summary end
    for _, summary in pairs(roots) do
        local wave = summary.wave or run.wave_id
        if wave >= firstWave and wave <= lastWave and ((summary.explosions or 0) > 0 or (summary.pushed or 0) > 0) then
            candidates[#candidates + 1] = summary
        end
    end
    table.sort(candidates, function(a, b)
        return (a.time or 0) > (b.time or 0) or ((a.time or 0) == (b.time or 0) and
            tostring(a.root_action_id) < tostring(b.root_action_id))
    end)
    for i = 1, math.min(2, #candidates) do selected[#selected + 1] = copy(candidates[i]) end
    return selected
end
function F.LastReport(run)
    if (run.record_namespace or "legacy_v02") == "legacy_v02" then return run.meta.last_report end
    return run.meta.scenario_reports and run.meta.scenario_reports[run.record_namespace] or nil
end
function F.Stage(run)
    local wave = run.wave_id
    local report = { chapter = run.chapter, wave = wave, time = run.clock, core_hp = run.core.hp,
        scenario_id = run.scenario_id, rules_version = run.rules_version, record_namespace = run.record_namespace,
        player_hp = run.player.hp, currency = run.currency, chains = F.Select(run, math.max(1, wave - 4), wave),
        economy = copy(run.economy_facts), economy_totals = copy(run.economy_totals), totals = copy(run.totals),
        expansion = require("defense.Expansion").Snapshot(run), expedition = require("defense.Expedition").Snapshot(run) }
    run.stage_reports[#run.stage_reports + 1] = report
    run:Emit("StageReportReady", { report = copy(report) })
    return report
end
function F.Finish(run)
    local report = { version = run.config.version, result = run.result, reason = run.end_reason,
        scenario_id = run.scenario_id, rules_version = run.rules_version, record_namespace = run.record_namespace,
        chapter = run.chapter, wave = run.wave_id, total_waves = run.total_waves, time = run.clock,
        core_hp = run.core.hp, player_hp = run.player.hp, currency = run.currency,
        totals = copy(run.totals), chains = F.Select(run, 1, run.wave_id), stages = copy(run.stage_reports),
        economy = copy(run.economy_facts), economy_totals = copy(run.economy_totals),
        expansion = require("defense.Expansion").Snapshot(run), expedition = require("defense.Expedition").Snapshot(run) }
    -- 最后一局只保存少量事实摘要，不提供中途续局、不保存账号或推断意图。
    if run.result ~= "abandoned" then
        if (run.record_namespace or "legacy_v02") == "legacy_v02" then run.meta.last_report = report
        else
            run.meta.scenario_reports = run.meta.scenario_reports or {}
            run.meta.scenario_reports[run.record_namespace] = report
        end
    end
    return report
end
function F.Transaction(run, data)
    if not data.ok then return end
    local fact = { wave = run.wave_id, time = run.clock, action = data.action, slot = data.slot_id,
        spend = data.price or 0, refund = data.refund or 0, repair = data.actual_repair or 0,
        heal = data.actual_heal or 0, sand_spend = data.sand_spend or 0, branch_id = data.after and data.after.branch_id,
        currency = data.currency_after or run.currency }
    run.economy_facts[#run.economy_facts + 1] = fact
    local totals = run.economy_totals
    totals.spend, totals.refund = totals.spend + fact.spend, totals.refund + fact.refund
    if data.action == "module" then totals.service_spend = totals.service_spend + fact.spend end
    totals.by_action[data.action] = (totals.by_action[data.action] or 0) + fact.spend
    if #run.economy_facts > 8 then table.remove(run.economy_facts, 1) end
end
function F.Observe(run, id)
    if not HINTS[id] or run.observation_seen[id] or run.meta.observation_seen[id] then return false end
    if run.meta.settings and run.meta.settings.hints == false then return false end
    run.observation_seen[id], run.meta.observation_seen[id] = true, true
    run.observation_hint = { id = id, text = HINTS[id], expires_at = run.clock + 5 }
    run:Emit("ObservationHint", copy(run.observation_hint))
    run:SaveMeta()
    return true
end
function F.Update(run)
    if run.ended or run:IsPaused() or run.clock < run.next_observation_check then return end
    run.next_observation_check = run.clock + 0.25
    if run.meta.settings and run.meta.settings.hints == false then return end
    if run.meta.observation_seen.explosive and run.meta.observation_seen.slow then return end
    local player = run.player
    for _, enemy in ipairs(run.enemies) do
        if enemy.alive and enemy.explodes_on_death and (enemy.x - player.x)^2 + (enemy.y - player.y)^2 <= player.range^2
            and run.map:LineOfSight(player.x, player.y, enemy.x, enemy.y) then
            if F.Observe(run, "explosive") then return end
        end
        if enemy.alive and (enemy.slow_factor or 1) < 1 and (enemy.x - player.x)^2 + (enemy.y - player.y)^2 <= player.range^2
            and run.map:LineOfSight(player.x, player.y, enemy.x, enemy.y) then
            if F.Observe(run, "slow") then return end
        end
    end
end
function F.Describe(summary)
    local parts = {}
    if (summary.pushed or 0) > 0 then parts[#parts + 1] = "实际击退 " .. summary.pushed .. " 次" end
    if (summary.explosions or 0) > 0 then parts[#parts + 1] = "爆炸 " .. summary.explosions .. " 次" end
    if (summary.hits or 0) > 0 then parts[#parts + 1] = "敌人命中 " .. summary.hits .. " 次" end
    if (summary.kills or 0) > 0 then parts[#parts + 1] = "击杀 " .. summary.kills end
    for _, item in ipairs({ { "core_damage", "核心受损" }, { "player_damage", "角色受损" }, { "tower_damage", "设施受损" },
        { "gold", "到账资金" }, { "experience", "到账经验" } }) do
        local amount = summary[item[1]] or 0
        if amount > 0 then parts[#parts + 1] = item[2] .. " " .. tostring(math.floor(amount * 10 + 0.5) / 10) end
    end
    return table.concat(parts, " · ")
end
function F.SourceName(source) return SOURCE_NAMES[source] or source or "已提交事件" end
function F.Copy(value) return copy(value) end
return F
