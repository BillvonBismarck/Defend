-- B01–B03/P01–P03：本局模块、独立随机流与选择暂停；只由 Run 驱动。
local T = {}
local Expansion = require("defense.Expansion")
local Random = require("defense.Random")

-- 唯一候选数据源；UI/Combat/测试均读取此表，不另维护倍率表。
T.Definitions = {
    rapid_focus = { id = "rapid_focus", name = "重点锁定", tower_type = "rapid", target_policy = "priority",
        detail = "射程内优先远征主敌或精英；同级按距离、实体ID排序，普通密集推进可能漏怪" },
    rapid_sweep = { id = "rapid_sweep", name = "贯穿扫射", tower_type = "rapid", damage_multiplier = 0.8, pierce = 1,
        detail = "有效伤害×0.8，额外穿透1个合法目标；仍受墙柱遮挡，不重复命中" },
    slow_field = { id = "slow_field", name = "广域控制", tower_type = "slow", range_add = 1.5, slow_amount_add = -0.10,
        detail = "有效范围+1.5格，减速量-10个百分点（下限0）；普通弹体伤害不变" },
    slow_anchor = { id = "slow_anchor", name = "定点锚控", tower_type = "slow", range_add = -1, min_range = 1, slow_amount_add = 0.10,
        detail = "有效范围-1格（下限1格），减速量+10个百分点；公共上限及Boss半效仍生效" },
    area_cluster = { id = "area_cluster", name = "集群爆破", tower_type = "area", splash_add = 0.8, damage_multiplier = 0.75,
        detail = "溅射半径+0.8格，有效伤害×0.75；降低单目标输出" },
    area_focus = { id = "area_focus", name = "聚焦爆破", tower_type = "area", splash_multiplier = 0.6, damage_multiplier = 1.3,
        detail = "溅射半径×0.6，有效伤害×1.3；降低群体覆盖" },
}
T.ChangeCost = 20 -- P02：服务费，不进入拆除返款基数。

---@param config table
function T.GetDefinitions(config)
    return T.Definitions
end

---@param run table
function T.Enabled(run)
    return run.config.module_system == true
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

---@param run table
---@param moduleId string
function T.Find(run, moduleId)
    local definition = T.GetDefinitions(run.config)[moduleId] --[[@as table?]]
    if definition and run.config.towers[definition.tower_type] then return definition end
end

-- moduleOverride=nil 使用已安装模块；false/"" 明确预览无模块，字符串预览合法分支。
-- 先完整复现 Combat 的基础/升级/协同，再一次应用模块；不写回塔，不解析最终减速。
---@param run table
---@param tower table
---@param moduleOverride string|boolean|nil
function T.Attributes(run, tower, moduleOverride)
    local def = run.config.towers[tower.type] --[[@as table?]]
    local attributes = { damage = 0, interval = 0, range = 0, slow_amount = 0, slow_duration = 0,
        splash = 0, pierce = 0, target_policy = "nearest" }
    if not def then return Expansion.Attributes(run, tower, attributes) end
    local upgrade = math.min(2, math.max(0, tower.upgrade_count or 0))
    local synergy = math.max(0, (run.player.skills or {}).synergy or 0)
    attributes.damage = def.damage * (1 + upgrade * 0.3) * (1 + synergy * 0.2)
    attributes.interval = def.interval * (1 - upgrade * 0.1)
    attributes.range = def.range + upgrade * 0.5 + synergy * 0.35
    attributes.splash = def.splash and (def.splash + upgrade * 0.25) or 0
    if tower.type == "slow" then
        attributes.slow_amount = (def.slow_amount or 0.35) + upgrade * 0.05
        attributes.slow_duration = def.slow_duration or 2
    end
    if not T.Enabled(run) then return Expansion.Attributes(run, tower, attributes) end
    local moduleId = moduleOverride
    if moduleId == nil then moduleId = tower.module_id end
    if type(moduleId) ~= "string" or moduleId == "" then return Expansion.Attributes(run, tower, attributes) end
    local module = T.Find(run, moduleId)
    if not module or module.tower_type ~= tower.type then return Expansion.Attributes(run, tower, attributes) end
    attributes.damage = attributes.damage * (module.damage_multiplier or 1)
    attributes.range = math.max(module.min_range or 0, attributes.range + (module.range_add or 0))
    attributes.slow_amount = math.max(0, attributes.slow_amount + (module.slow_amount_add or 0))
    attributes.splash = (attributes.splash + (module.splash_add or 0)) * (module.splash_multiplier or 1)
    attributes.pierce = module.pierce or 0
    attributes.target_policy = module.target_policy or "nearest"
    return Expansion.Attributes(run, tower, attributes)
end

---@param run table
function T.Init(run)
    run.module_inventory, run.pending_module_choices, run.room_module_claims = {}, {}, {}
    run.module_choice_id = nil
    run.pause_reasons.module_choice = nil
    run.module_seed = nil
    run.module_rng = nil
    -- 即便同一实例被重新初始化，也只清模块选择账本，不触碰经济/领奖账本。
    for key in pairs(run.transactions) do
        if type(key) == "string" and key:sub(1, 14) == "module_choice:" then run.transactions[key] = nil end
    end
    if T.Enabled(run) then
        run.module_seed = (math.floor(run.seed or 20261002) ~ 0x4d4f4455) & 0xffffffff
        run.module_rng = Random.New(run.module_seed)
    end
end

---@param run table
local function ensureInit(run)
    if not run.module_inventory then T.Init(run) end
end

---@param run table
local function pending(run, choiceId)
    for index, choice in ipairs(run.pending_module_choices or {}) do
        if choiceId == nil or choice.choice_id == choiceId then return choice, index end
    end
end

---@param run table
local function findRoom(run, roomId)
    for _, room in ipairs(run.rooms) do if room.id == roomId then return room end end
end

---@param run table
local function roomDefinition(run, roomId)
    for _, definition in ipairs(run.config.rooms) do if definition.id == roomId then return definition end end
end

-- 所有待选候选互斥；保留合法旧候选，不因开关面板重新洗牌。
---@param run table
local function refreshPending(run)
    local reserved, pool, unowned = {}, {}, 0
    for _, choice in ipairs(run.pending_module_choices) do
        local candidates, options = {}, {}
        for _, moduleId in ipairs(choice.candidates) do
            local definition = T.Find(run, moduleId)
            if definition and not run.module_inventory[moduleId] and not reserved[moduleId] then
                reserved[moduleId] = true
                candidates[#candidates + 1] = moduleId
                options[#options + 1] = copy(definition)
            end
        end
        choice.candidates, choice.options = candidates, options
        choice.waiting = #candidates == 0
    end
    for moduleId in pairs(T.GetDefinitions(run.config)) do
        if T.Find(run, moduleId) and not run.module_inventory[moduleId] then
            unowned = unowned + 1
            if not reserved[moduleId] then pool[#pool + 1] = moduleId end
        end
    end
    table.sort(pool)
    for index = #run.pending_module_choices, 1, -1 do
        if unowned == 0 and run.pending_module_choices[index].waiting then table.remove(run.pending_module_choices, index) end
    end
    for _, choice in ipairs(run.pending_module_choices) do
        if choice.waiting and #pool > 0 then
            while #choice.candidates < 3 and #pool > 0 do
                local moduleId = table.remove(pool, run.module_rng:Index(#pool))
                choice.candidates[#choice.candidates + 1] = moduleId
                choice.options[#choice.options + 1] = copy(T.Find(run, moduleId))
            end
            choice.waiting = false
            run:Emit("ModuleOffered", { room_id = choice.room_id, choice_id = choice.choice_id,
                candidates = copy(choice.candidates), options = copy(choice.options), waiting = false, reason = "保留机会候选已就绪" })
        end
    end
end

---@param run table
function T.Open(run, choiceId)
    if not T.Enabled(run) then return false, "本场景未启用模块" end
    if run.ended then return false, "本局已结束" end
    ensureInit(run)
    refreshPending(run)
    local choice = pending(run, choiceId)
    if not choice then return false, "没有该待选模块" end
    if choice.waiting then return false, "候选暂在其它待选项中，请先完成已有选择", copy(choice) end
    run.module_choice_id = choice.choice_id
    if not run.pause_reasons.module_choice then run:Pause("module_choice") end
    return true, "选择模块", copy(choice)
end

---@param run table
function T.Close(run, choiceId)
    if not T.Enabled(run) then return false, "本场景未启用模块" end
    if choiceId ~= nil and choiceId ~= run.module_choice_id then return false, "该选择面板未打开" end
    if not run.module_choice_id and not run.pause_reasons.module_choice then return false, "选择面板未打开" end
    run.module_choice_id = nil
    if run.pause_reasons.module_choice then run:Resume("module_choice") end
    -- pending 保留；只释放自己的暂停，不覆盖 upgrade 或 state/resume_state。
    return true, "已保留待选模块"
end

-- Run 在金币/经验首次领奖提交之后调用；重复 Offer 不重抽、不重开面板。
---@param run table
---@param room table
function T.Offer(run, room)
    if not T.Enabled(run) then return nil, "本场景未启用模块" end
    if run.ended then return nil, "本局已结束" end
    ensureInit(run)
    local current = room and findRoom(run, room.id)
    local definition = current and roomDefinition(run, current.id)
    if not current or not definition or definition.module_reward ~= true then return nil, "该房间没有模块奖励" end
    if not current.reward_claimed then return nil, "请先领取房间奖励" end
    local previous = run.room_module_claims[current.id]
    if previous then
        local choice = pending(run, previous)
        return choice and copy(choice) or nil, "该房间模块机会已结算"
    end
    local reserved, pool, unowned = {}, {}, 0
    for _, choice in ipairs(run.pending_module_choices) do
        for _, moduleId in ipairs(choice.candidates) do reserved[moduleId] = true end
    end
    for moduleId in pairs(T.GetDefinitions(run.config)) do
        if T.Find(run, moduleId) and not run.module_inventory[moduleId] then
            unowned = unowned + 1
            if not reserved[moduleId] then pool[#pool + 1] = moduleId end
        end
    end
    table.sort(pool) -- 不依赖 pairs 顺序，固定 seed 可重放。
    local choiceId = run.run_id .. ":module:" .. current.id
    local choice = { id = choiceId, choice_id = choiceId, room_id = current.id, candidates = {}, options = {} }
    while #choice.candidates < 3 and #pool > 0 do
        local moduleId = table.remove(pool, run.module_rng:Index(#pool))
        choice.candidates[#choice.candidates + 1] = moduleId
        choice.options[#choice.options + 1] = copy(T.Find(run, moduleId))
    end
    run.room_module_claims[current.id] = choiceId
    choice.waiting = #choice.candidates == 0 and unowned > 0
    if unowned > 0 then run.pending_module_choices[#run.pending_module_choices + 1] = choice end
    local reason = unowned == 0 and "模块已收集"
        or (choice.waiting and "候选暂在其它待选项中，模块机会已保留" or "首次领奖模块选择")
    run:Emit("ModuleOffered", { room_id = current.id, choice_id = choiceId, candidates = copy(choice.candidates),
        options = copy(choice.options), waiting = choice.waiting, reason = reason })
    if unowned == 0 then return nil, reason end
    if not choice.waiting then T.Open(run, choiceId) end
    return copy(choice), reason
end

---@param run table
---@param choiceId string
---@param moduleId string
---@param requestId string
function T.Choose(run, choiceId, moduleId, requestId)
    if type(requestId) ~= "string" or requestId == "" then return { ok = false, reason = "缺少请求ID" } end
    local key = "module_choice:" .. requestId
    local existing = run.transactions[key]
    if existing then return existing end
    local result = { ok = false, reason = "没有该待选模块", run_id = run.run_id, request_id = requestId,
        id = requestId, choice_id = choiceId, module_id = moduleId }
    if not T.Enabled(run) then result.reason = "本场景未启用模块"
    elseif run.ended then result.reason = "本局已结束"
    else
        ensureInit(run)
        local choice, index = pending(run, choiceId)
        if choice and choiceId ~= nil then
            result.room_id = choice.room_id
            local room = findRoom(run, choice.room_id)
            local def = roomDefinition(run, choice.room_id)
            local found = false
            for _, candidateId in ipairs(choice.candidates) do if candidateId == moduleId then found = true; break end end
            if not room or not room.reward_claimed or not def or def.module_reward ~= true
                or run.room_module_claims[choice.room_id] ~= choiceId then result.reason = "该房间模块机会无效"
            elseif not found or not T.Find(run, moduleId) then result.reason = "无效模块候选"
            elseif run.module_inventory[moduleId] then result.reason = "该模块已拥有"
            else
                result.ok, result.reason = true, "模块已解锁"
                run.module_inventory[moduleId] = true
                table.remove(run.pending_module_choices, index)
                if run.module_choice_id == choiceId then T.Close(run, choiceId) end
            end
        end
    end
    run.transactions[key] = result
    if result.ok then
        run:Emit("ModuleChosen", copy(result))
        refreshPending(run) -- 释放未选分支，按领取顺序补齐暂缓机会，不自动打开下一面板。
    end
    run:Emit("ModuleChoiceResolved", copy(result)) -- 不进入经济战报/last_transaction。
    return result
end

---@param run table
function T.Snapshot(run)
    local rng = run.module_rng
    return { module_system = T.Enabled(run), module_inventory = copy(run.module_inventory or {}),
        pending_module_choices = copy(run.pending_module_choices or {}), room_module_claims = copy(run.room_module_claims or {}),
        module_choice_id = run.module_choice_id, module_seed = run.module_seed,
        module_rng_state = rng and rng.state or nil, module_rng_calls = rng and rng.calls or 0 }
end
return T
