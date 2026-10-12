-- 2026-10-08 扩展案的独立原型策略。旧场景不启用，不改写旧数值与旧限伤语义。
local X = {}
local function copy(v)
    if type(v) ~= "table" then return v end
    local r = {}; for k, item in pairs(v) do r[k] = copy(item) end; return r
end
function X.Enabled(run) return run.config.sanctuary_expansion == true end

function X.Configure(c)
    c.sanctuary_expansion, c.scenario_id = true, "sanctuary_expansion"
    c.version, c.rules_version = "defense-0.4.0-prototype", "20261008-expansion-v02"
    c.title, c.record_namespace = "固定据点守护神殿", "defense_sanctuary_expansion"
    c.total_waves, c.final_intro_wave, c.can_record_chapter = 20, 21, false
    c.attack_duration, c.clear_bonus_max, c.exploration_window_cap = 30, 15, 30
    c.max_alive_towers, c.exploration_currency_cap = 12, 120
    c.expedition_time_cap, c.room_core_damage_cap = 120, c.core_max_hp * 0.1
    c.irreversible_branches = true
    c.facility_order = { "rapid", "area", "slow", "repulsor", "barricade", "stakes", "repair_station", "energy_station" }
    c.zones = {
        { id = "A", name = "森林", rooms = { "A1", "A2" }, motive = "资金与基础材料" },
        { id = "B", name = "冰川", rooms = { "B1", "B2" }, motive = "控制图纸与模块" },
        { id = "C", name = "火山", rooms = { "C1", "C2" }, motive = "星砂与高级设施" },
    }
    c.towers.rapid.family, c.towers.area.family, c.towers.slow.family = "输出", "输出", "控制"
    local function tower(name, family, cost, range, interval, damage, extra)
        local d = { name = name, family = family, cost = cost, upgrade = 60, hp = 150,
            range = range, interval = interval, damage = damage }
        for k, v in pairs(extra or {}) do d[k] = v end
        return d
    end
    c.towers.repulsor = tower("击退台", "控制", 95, 4.5, 2.5, 0, { push = 1.8 })
    c.towers.barricade = tower("路障", "阻挡", 55, 1.6, 1.5, 0, { hp = 260, slow_amount = 0.4, slow_duration = 0.3 })
    c.towers.stakes = tower("拒马", "阻挡", 75, 1.8, 1.2, 9, { hp = 200, slow_amount = 0.2, slow_duration = 0.3 })
    c.towers.repair_station = tower("维修站", "支援", 100, 6, 2, 0, { repair = 4, sand_cost = 10 })
    c.towers.energy_station = tower("供能站", "支援", 100, 5, 2, 0, { energy = 0.15, sand_cost = 10 })
    c.branches = {
        reach = { id = "reach", name = "广域部署", range_add = 1, damage_multiplier = 0.9, support_multiplier = 1 },
        focus = { id = "focus", name = "重点强化", range_add = -0.5, damage_multiplier = 1.25, support_multiplier = 1.5 },
    }
    -- 两条外环只增加连通空间；核心、入口与四主殿槽保持原坐标。
    c.walkable_regions[#c.walkable_regions + 1] = { id = "forest_glacier_ring", x1 = 13, y1 = 4, x2 = 51, y2 = 8 }
    c.walkable_regions[#c.walkable_regions + 1] = { id = "forest_volcano_v", x1 = 6, y1 = 26, x2 = 10, y2 = 45 }
    c.walkable_regions[#c.walkable_regions + 1] = { id = "forest_volcano_h", x1 = 8, y1 = 41, x2 = 26, y2 = 45 }
    c.walkable_regions[#c.walkable_regions + 1] = { id = "glacier_volcano_v", x1 = 54, y1 = 26, x2 = 58, y2 = 39 }
    c.route_order = { "A1", "A2", "B2", "B1", "C2", "C1" }
    c.expedition_routes = {} -- 新版远征只在W20后动态建立，W5/W10不偷插特殊单位。
    for i, w in ipairs(c.waves) do
        w.attack_duration = i < 10 and 30 or 45 -- 基准不随波数下降。
        w.special_units, w.special_count, w.challenge = {}, 0, nil
    end
    c.declared_special_total = 0
    c.declared_totals = { ordinary = 1176, normal = 1159, elite = 14, boss = 3, special = 0, total = 1176 }
    for _, def in ipairs(c.rooms) do
        def.challenge_target = false
        def.name = ({ A = "森林", B = "冰川", C = "火山" })[def.id:sub(1, 1)] .. "据点" .. def.tier
        def.sand_reward = def.id:sub(1, 1) == "C" and 25 or 10
        def.gold_reward = def.id:sub(1, 1) == "A" and (def.tier == 1 and 60 or 100) or (def.tier == 1 and 40 or 80)
        def.module_reward = def.id:sub(1, 1) == "B"
    end
    -- 六房间各有防线槽，外围塔同时参与守军、考验和远征。
    for _, def in ipairs(c.rooms) do
        if #def.defense_slots == 0 then
            local id = "T_" .. def.id; def.defense_slots = { id }
            c.build_slots[#c.build_slots + 1] = { id = id, x = def.x + 2, y = def.y + 2,
                owner_room_id = def.id, activation_region_id = def.id }
        end
    end
    for _, role in ipairs({ "advance", "ranged", "elite" }) do
        local id = "expedition_" .. role
        c.enemies[id] = copy(c.enemies[role]); c.enemies[id].speed = 9
        c.enemies[id].name, c.enemies[id].summon_disabled = "远征" .. c.enemies[role].name, true
        c.enemies[id].hp = role == "elite" and 400 or 160
        c.enemy_emoji[id] = copy(c.enemy_emoji[role])
    end
    c.decisions.X01 = "扩展独立场景：30秒起，W10起45秒；速清奖励封顶15，探索总长30；经典场景保持旧规则。"
    c.decisions.X02 = "星砂仅首次据点/远征结算获得，累计收入120封顶；不可逆分支20星砂；完好拆除资金返50%，星砂不返。"
    c.decisions.X03 = "W20后若至少一房已清则独立考验；未清房不出怪、不发奖；三队各推进/远程/破阵，路线按已清房过滤。"
    c.decisions.X04 = "每波各房共享100核心伤害预算，跨队/再入房不重置；最终攻核沿用末站来源；巡行不锁HP、不转场免伤。"
    c.decisions.X05 = "原型总时限120秒（扩展案建议<=90秒，尚未确认）；六站12秒停留与实测87秒巡行须留后发队/攻核余量；暂停冻结，超时失败。阻挡设施拦截但不改静态寻路。"
    return c
end

function X.Init(run)
    run.exploration_currency, run.exploration_currency_earned = 0, 0
    run.wave_reports, run.room_core_damage, run.zone_visits = {}, {}, {}
    run.exploration_seconds_earned, run.exploration_seconds_used = 0, 0
    run.slow_clear_streak, run.trial_started = 0, false
end
function X.Sand(run, amount, source)
    if not X.Enabled(run) or run.ended then return 0 end
    local actual = math.min(math.max(0, amount), math.max(0, run.config.exploration_currency_cap - run.exploration_currency_earned))
    run.exploration_currency = run.exploration_currency + actual
    run.exploration_currency_earned = run.exploration_currency_earned + actual
    if actual > 0 then run:Emit("ExplorationCurrencyEarned", { amount = actual, balance = run.exploration_currency, source = source }) end
    return actual
end
function X.Bonus(run)
    local bonus = math.max(0, run.attack_duration - run.attack_elapsed)
    if X.Enabled(run) then
        bonus = math.min(bonus, run.config.clear_bonus_max, math.max(0, run.config.exploration_window_cap - run.config.preparation_duration))
    end
    return bonus
end
function X.RecordWave(run, bonus)
    if not X.Enabled(run) then return end
    run.slow_clear_streak = run.attack_elapsed >= run.attack_duration and run.slow_clear_streak + 1 or 0
    local fact = { wave = run.wave_id, combat_time = run.attack_elapsed, base_combat_time = run.attack_duration,
        bonus = bonus, exploration_used = 0, zone_visits = {} }
    run.wave_reports[#run.wave_reports + 1] = fact
    if run.slow_clear_streak == 2 then run:Emit("SlowClearHint", { text = "考虑先修复或布防" }) end
end
function X.TrackExploration(run, dt, before)
    if not X.Enabled(run) or run.state ~= "PREPARATION" then return end
    local room = run.map:RoomAt(run.player.x, run.player.y)
    if room then
        local used = math.min(dt, math.max(0, before - run.config.preparation_duration))
        run.exploration_seconds_used = run.exploration_seconds_used + used
        run.zone_visits[room] = true
        local report = run.wave_reports[#run.wave_reports]
        if report and report.wave == run.wave_id - 1 then
            report.exploration_used = report.exploration_used + used
            report.zone_visits[room] = true
        end
    end
end
function X.ShouldStartTrial(run)
    if not X.Enabled(run) or run.trial_started or run.total_waves ~= 20 then return false end
    for _, room in ipairs(run.rooms) do
        if (room.state == "cleared" or room.state == "claimed") and (not run.config.polygon_expansion or room.role ~= "gate") then return true end
    end
    return false
end
function X.StartTrial(run, bonus)
    if not X.ShouldStartTrial(run) then return false end
    local stops = {}
    for _, id in ipairs(run.config.route_order) do
        for _, room in ipairs(run.rooms) do
            if room.id == id and (room.state == "cleared" or room.state == "claimed") then
                local p = { x = room.x, y = room.y }
                stops[#stops + 1] = { room_id = id, entry = copy(p), engage = copy(p), exit = copy(p) }
            end
        end
    end
    if #stops == 0 then return false end
    local c = run.config
    run.trial_started = true
    local caps = {}; for _, stop in ipairs(stops) do caps[stop.room_id] = 1 end
    local route = { route_id = "sanctuary_circuit", stops = stops, room_caps = caps, initial_hp = 1200,
        engage_duration = 12, damage_mode = "core_budget", final_target = copy(c.core_position) }
    c.expedition_routes[route.route_id] = route
    local w = { wave_id = 21, active_portals = { "W", "E", "S" }, ordinary = 18, elite_count = 0,
        reward = 20, attack_duration = 90, portal_offsets = { W = 0, E = 1, S = 2 },
        special_units = {}, special_count = 9, challenge = { route_id = route.route_id, stop_ids = {} } }
    for _, stop in ipairs(stops) do w.challenge.stop_ids[#w.challenge.stop_ids + 1] = stop.room_id end
    for team = 1, 3 do
        for index, role in ipairs({ "advance", "ranged", "elite" }) do
            w.special_units[#w.special_units + 1] = { role = "expedition_" .. role,
                portal = ({ "W", "E", "S" })[team], at = (team - 1) * 3 + (index - 1) * 0.8,
                route_id = route.route_id, squad_id = team }
        end
    end
    for _, def in ipairs(c.rooms) do
        def.challenge_target = false
        for _, stop in ipairs(stops) do if def.id == stop.room_id then def.challenge_target = true end end
    end
    -- 已清房区域各追加三名向心推进怪，独立入口只在考验队列使用。
    w.regional_units = {}
    for _, stop in ipairs(stops) do
        local portal = "zone_" .. stop.room_id
        c.portals[portal] = { x = stop.engage.x, y = stop.engage.y, name = stop.room_id }
        for i = 1, 3 do w.regional_units[#w.regional_units + 1] = { role = "advance", portal = portal, at = 2 + i * 0.8 } end
    end
    local regional = #w.regional_units
    c.declared_special_total = 9
    c.declared_ordinary_total = 1176 + 18 + regional
    c.declared_totals = { ordinary = 1176 + 18 + regional, normal = 1159 + 18 + regional,
        elite = 14, boss = 3, special = 9, total = 1176 + 27 + regional }
    c.waves[21], run.total_waves, run.wave_id = w, 21, 21
    run:EnterPreparation(bonus or 0)
    run:Emit("TrialPrepared", { rooms = copy(w.challenge.stop_ids), teams = 3, warning = c.warning_duration })
    return true
end

-- 核心预算按wave+来源房去重，提交顺序与公共伤害完全一致。角色/设施不使用此账本。
function X.CoreDamage(run, requested, context)
    if not X.Enabled(run) or not run.trial_started or run.wave_id ~= 21 then return requested end
    local id = context and context.core_budget_room
    if not id then return requested end
    local key = tostring(run.wave_id) .. ":" .. id
    local ledger = run.room_core_damage[key]
    if not ledger then
        ledger = { room_id = id, wave_id = run.wave_id, cap = run.config.room_core_damage_cap, used = 0 }
        run.room_core_damage[key] = ledger
    end
    local actual = math.min(requested, math.max(0, ledger.cap - ledger.used), run.core.hp)
    ledger.used = ledger.used + actual; ledger.remaining = ledger.cap - ledger.used
    run:Emit("CoreRoomBudgetChanged", { room_id = id, wave_id = run.wave_id, cap = ledger.cap,
        used = ledger.used, remaining = ledger.remaining, actual = actual, suppressed = requested - actual })
    return actual
end
function X.SourceRoom(run, e)
    if not X.Enabled(run) then return nil end
    if e.core_budget_room then return e.core_budget_room end
    if e.behavior ~= "expedition" then return nil end
    if e.stage == "FINAL_ASSAULT" then return e.expedition_route.stops[#e.expedition_route.stops].room_id end
    return run.map:RoomAt(e.x, e.y)
end
function X.Attributes(run, tower, a)
    if not X.Enabled(run) then return a end
    local d = run.config.towers[tower.type]
    if not d then return a end
    a.repair, a.energy, a.push = d.repair or 0, d.energy or 0, d.push or 0
    if d.slow_amount and tower.type ~= "slow" then a.slow_amount, a.slow_duration = d.slow_amount, d.slow_duration or 2 end
    local branch = run.config.branches[tower.branch_id]
    if branch then
        a.range = math.max(1, a.range + branch.range_add)
        a.damage = a.damage * branch.damage_multiplier
        a.repair, a.energy, a.push = a.repair * branch.support_multiplier, a.energy * branch.support_multiplier, a.push * branch.support_multiplier
    end
    -- 邻接供能读取活设施公共范围/LOS；取最强，不相乘、不借特殊组合ID。
    local energy = 0
    for _, station in ipairs(run.towers) do
        local sd = run.config.towers[station.type]
        if sd and sd.energy and station.hp > 0 and station ~= tower and
            (not tower.entity_id or station.entity_id ~= tower.entity_id) and tower.x and tower.y and
            (station.x - tower.x)^2 + (station.y - tower.y)^2 <=
                math.max(1, sd.range + (station.upgrade_count or 0) * 0.5 + math.max(0, run.player.skills.synergy or 0) * 0.35 +
                    ((run.config.branches[station.branch_id] or {}).range_add or 0))^2 and
            run.map:LineOfSight(station.x, station.y, tower.x, tower.y) then
            energy = math.max(energy, sd.energy * (station.branch_id == "focus" and 1.5 or 1))
        end
    end
    a.interval = a.interval / (1 + energy)
    a.energy_received = energy
    return a
end
function X.Snapshot(run)
    return { sand = run.exploration_currency, sand_earned = run.exploration_currency_earned,
        exploration_seconds_earned = run.exploration_seconds_earned, exploration_seconds_used = run.exploration_seconds_used,
        wave_reports = copy(run.wave_reports), room_core_damage = copy(run.room_core_damage), zone_visits = copy(run.zone_visits), trial_started = run.trial_started }
end
return X
