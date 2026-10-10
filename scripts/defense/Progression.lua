-- R06：候选、前置、满级与溢出经验；纯 Lua，随机源显式注入。
local P = {}
P.skills = {
    { id = "power", name = "精确火力", group = "single", max = 5, detail = "每级基础伤害 +25%" },
    { id = "rapid", name = "快速装填", group = "single", max = 4, detail = "每级射击间隔 -10%" },
    { id = "pierce", name = "贯穿弹头", group = "single", max = 3, prerequisite = "power", detail = "每级多穿透 1 个敌人" },
    { id = "blast", name = "爆破弹头", group = "area", max = 4, detail = "弹体命中产生范围伤害" },
    { id = "pulse", name = "施力强化", group = "area", max = 4, detail = "无伤击退距离每级 +0.4格；墙柱仍阻挡，核心不能推动" },
    { id = "frost", name = "冷凝弹头", group = "control", max = 4, detail = "命中减速，给回防争取时间" },
    { id = "vitality", name = "生存强化", group = "survival", max = 4, detail = "最大生命 +15，并恢复15生命" },
    { id = "mobility", name = "机动强化", group = "mobility", max = 3, detail = "每级移速 +12%，拾取距离增加" },
    { id = "synergy", name = "防守协同", group = "defense", max = 4, min_upgrade = 3, detail = "每级设施伤害 +20%，射程增加" },
    { id = "relay", name = "应急电容", group = "defense", max = 3, min_upgrade = 3, prerequisite = "pulse", detail = "主动技冷却 -15%，提高救核频率" },
}
local fallback = {
    { id = "heal_bonus", name = "紧急治疗", group = "survival", detail = "恢复25生命，封顶；无数值升级" },
    { id = "gold_bonus", name = "资金补给", group = "defense", detail = "获得15防守资金；无数值升级" },
    { id = "cooldown_bonus", name = "技能充能", group = "control", detail = "主动技冷却归零；无数值升级" },
}

function P.Threshold(level)
    return 20 + 10 * (level - 1)
end

function P.Find(id)
    for _, d in ipairs(P.skills) do if d.id == id then return d end end
    for _, d in ipairs(fallback) do if d.id == id then return d end end
end

-- R23：预览只读当前构筑，展示真实数值而不是把等级当作效果。
---@param run table
---@param id string
---@return string
function P.Preview(run, id)
    local p, cfg = run.player, run.config
    local level = p.skills[id] or 0
    local function change(name, before, after, unit)
        return string.format("%s %.2f → %.2f%s", name, before, after, unit or "")
    end
    if id == "power" then
        return change("单发伤害", p.damage * (1 + level * 0.25), p.damage * (1 + (level + 1) * 0.25))
    elseif id == "rapid" then
        return change("射击间隔", p.interval * math.max(0.1, 1 - level * 0.1), p.interval * math.max(0.1, 1 - (level + 1) * 0.1), "秒")
    elseif id == "pierce" then
        return string.format("额外穿透 %d → %d 个目标", level, level + 1)
    elseif id == "blast" then
        return change("爆破半径", level > 0 and 1.2 + level * 0.3 or 0, 1.2 + (level + 1) * 0.3, "格") ..
            string.format(" · 溅射伤害为单发的 %d%%（不重复命中主目标）", math.floor((0.35 + (level + 1) * 0.1) * 100 + 0.5))
    elseif id == "pulse" then
        local base = cfg.player.active_distance or 3
        return change("基础击退", base + level * 0.4, base + (level + 1) * 0.4, "格") .. " · 重量与墙柱仍限制实际位移"
    elseif id == "frost" then
        local cap = (cfg.reactions or {}).slow_cap or 0.5
        return string.format("减速 %.0f%% → %.0f%% · 持续 %.1f秒，Boss半效",
            math.min(cap, level * 0.1) * 100, math.min(cap, (level + 1) * 0.1) * 100,
            (cfg.combat or {}).slow_duration or 2)
    elseif id == "vitality" then
        return change("最大生命", p.max_hp, p.max_hp + 15) .. " · 恢复15生命"
    elseif id == "mobility" then
        return change("基础移速", p.speed * (1 + level * 0.12), p.speed * (1 + (level + 1) * 0.12), "格/秒") ..
            change(" · 拾取半径", ((cfg.combat or {}).pickup_radius or 1.1) + level * ((cfg.combat or {}).pickup_mobility or 0.35),
                ((cfg.combat or {}).pickup_radius or 1.1) + (level + 1) * ((cfg.combat or {}).pickup_mobility or 0.35), "格")
    elseif id == "synergy" then
        return string.format("设施伤害倍率 %.2f → %.2f · 所有设施射程 +0.35格", 1 + level * 0.2, 1 + (level + 1) * 0.2)
    elseif id == "relay" then
        return change("击退冷却", cfg.player.active_cooldown * math.max(0.1, 1 - level * 0.15),
            cfg.player.active_cooldown * math.max(0.1, 1 - (level + 1) * 0.15), "秒")
    elseif id == "heal_bonus" then
        return change("当前生命", p.hp, math.min(p.max_hp, p.hp + 25))
    elseif id == "gold_bonus" then
        return string.format("资金 %d → %d", run.currency, run.currency + 15)
    elseif id == "cooldown_bonus" then
        return change("剩余冷却", p.active_cd, 0, "秒")
    end
    return ""
end

function P.Options(run, rng)
    local upgrade = run.player.level
    local pool, options = {}, {}
    for _, d in ipairs(P.skills) do
        if (run.player.skills[d.id] or 0) < d.max and upgrade >= (d.min_upgrade or 1)
            and (not d.prerequisite or (run.player.skills[d.prerequisite] or 0) >= 1) then
            pool[#pool + 1] = d
        end
    end
    local function take(index)
        local d = table.remove(pool, index)
        options[#options + 1] = { id = d.id, name = d.name, group = d.group, detail = d.detail,
            current = run.player.skills[d.id] or 0, next = (run.player.skills[d.id] or 0) + 1, max = d.max }
    end
    -- R38/Q20：W3–5 首个实际升级窗口保范围候选，不强制选、不赠未选能力。
    if run.wave_id >= 3 and run.wave_id <= 5 and not run.range_opportunity_offered then
        for i, definition in ipairs(pool) do
            if definition.id == "blast" then
                take(i)
                run.range_opportunity_offered, run.range_opportunity_wave = true, run.wave_id
                break
            end
        end
    end
    if upgrade == 1 and #options == 0 then
        for i, definition in ipairs(pool) do
            if definition.group == "area" or definition.group == "control" then take(i); break end
        end
    end
    while #options < 3 and #pool > 0 do take(rng:Index(#pool)) end
    for _, d in ipairs(fallback) do
        if #options >= 3 then break end
        options[#options + 1] = { id = d.id, name = d.name, group = d.group, detail = d.detail, current = 0, next = 0, max = 0 }
    end
    return options
end

function P.Apply(run, id)
    local d = P.Find(id)
    if not d then return false end
    local p = run.player
    if id == "heal_bonus" then p.hp = math.min(p.max_hp, p.hp + 25)
    elseif id == "gold_bonus" then run.currency = run.currency + 15
    elseif id == "cooldown_bonus" then p.active_cd = 0
    else
        if (p.skills[id] or 0) >= d.max or p.level < (d.min_upgrade or 1)
            or (d.prerequisite and (p.skills[d.prerequisite] or 0) < 1) then return false end
        p.skills[id] = (p.skills[id] or 0) + 1
        if id == "vitality" then p.max_hp = p.max_hp + 15; p.hp = math.min(p.max_hp, p.hp + 15) end
    end
    return true
end
return P
