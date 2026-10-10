-- 固定据点波次纯规则：R16 原始表在 Config；这里仅派生队列，不维护第二份可编辑队列。
-- 依赖仅 Lua 标准库。世界暂停时调用方不调用 Update（或传 dt=0）。
-- Q05 原型临时决策：普通怪按 W/E/S 启用顺序轮转；每入口每0.8秒一只；
-- 混兵比例用确定性20槽序列逐阶段递增。W12南路偏冲锋、W13东路偏远射。
-- 精英轮转分配到启用入口，排在该入口普通怪后；Boss固定3秒，独立于普通批次。
-- W16错峰读取 Config.portal_offsets；W=0/E=2/S=4 仍是临时值，不冒充设计确认。
-- 软上限计数由调用方给 aliveCount（当前波存活含召唤，不含据点守军）；
-- Update逐单位保存队首，失败/满80不跳过、不删除、不假装生成完成。

---@class DefenseWaveUnit
---@field at number
---@field portal string
---@field role string
---@field subtype? string
---@field opportunity_tag? string
---@field spawn_offset? table
---@field route_id? string
---@field spawn_key? string
---@field special? boolean
---@field squad_id? integer
---@field regional? boolean

---@class DefenseWaveDirector
---@field config table
---@field wave_id integer
---@field queue DefenseWaveUnit[]
---@field cursor integer
---@field elapsed number
---@field generation_complete boolean
---@field started boolean
---@field emitted integer
---@field delayed integer
---@field alive_limit integer
---@field blocked boolean
local WaveDirector = {}
WaveDirector.__index = WaveDirector
local ORDER = { "W", "E", "S" }
local EPS = 1e-9

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function count(value, name)
    assert(finite(value) and value >= 0 and value == math.floor(value), name .. "必须是非负整数")
    return math.floor(value)
end

local function enabledPortals(config, wave)
    assert(type(wave.active_portals) == "table", "波次缺少入口列表")
    local active = {}
    for _, id in ipairs(wave.active_portals) do
        assert(id == "W" or id == "E" or id == "S", "非法波次入口")
        assert(config.portals and config.portals[id], "入口缺少坐标配置")
        assert(not active[id], "波次入口重复")
        active[id] = true
    end
    local result = {}
    for _, id in ipairs(ORDER) do
        if active[id] then result[#result + 1] = id end
    end
    assert(#result > 0, "波次至少需要一个入口")
    return result, active
end

-- 同入口局部序号的7步置换覆盖20个槽，避免全局取模使所有远射只落某一路。
local function ordinaryRole(waveId, portal, lane, laneIndex)
    if waveId < 4 then return "advance" end
    local ranged = math.min(6, 2 + math.floor((waveId - 4) / 4))
    local charger = waveId >= 6 and math.min(5, 1 + math.floor((waveId - 6) / 3)) or 0
    if waveId == 12 and portal == "S" then charger = 9 end
    if waveId == 13 and portal == "E" then ranged = 12 end
    local slot = ((laneIndex - 1) * 7 + (lane - 1) * 3) % 20
    if slot < charger then return "charger" end
    if slot < charger + ranged then return "ranged" end
    return "advance"
end

---@param config table
---@param wave table
local function validateSpecial(config, wave)
    local units = wave.special_units or {}
    assert(type(units) == "table", "特殊单位必须是数组")
    assert(count(wave.special_count or 0, "特殊单位数量") == #units, "特殊单位声明数量不一致")
    local route = wave.challenge and (config.expedition_routes or {})[wave.challenge.route_id]
    if wave.challenge then
        assert(type(route) == "table" and route.route_id == wave.challenge.route_id, "考验路线缺失或ID不一致")
        assert(type(wave.challenge.stop_ids) == "table" and #wave.challenge.stop_ids == #route.stops, "考验站点数量不一致")
        for i, stop in ipairs(route.stops) do assert(wave.challenge.stop_ids[i] == stop.room_id, "考验站点顺序不一致") end
    end
    for _, unit in ipairs(units) do
        assert(type(unit) == "table" and (unit.role == "expedition" or config.sanctuary_expansion and config.enemies[unit.role]), "特殊单位角色无效")
        assert(config.enemies and config.enemies[unit.role], "特殊单位角色未配置")
        assert(config.portals and config.portals[unit.portal], "特殊入口未配置")
        assert(finite(unit.at) and unit.at >= 0, "特殊单位生成时间无效")
        assert(type(unit.route_id) == "string" and (config.expedition_routes or {})[unit.route_id], "特殊单位缺少合法路线")
        assert(wave.challenge and unit.route_id == wave.challenge.route_id, "特殊单位与考验路线不一致")
    end
    assert(not wave.challenge or #units > 0, "考验缺少特殊单位")
    return units
end

---@param waveId integer
---@return DefenseWaveUnit[]
function WaveDirector.BuildQueue(config, waveId)
    assert(type(config) == "table" and type(config.waves) == "table", "缺少波次配置")
    assert(finite(waveId) and waveId == math.floor(waveId) and waveId >= 1, "波号无效")
    local wave = config.waves[waveId]
    assert(wave and wave.wave_id == waveId, "波号与配置不一致")
    local portals, active = enabledPortals(config, wave)
    local ordinary = count(wave.ordinary, "普通怪数量")
    local elites = count(wave.elite_count, "精英数量")
    local interval = config.batch_interval or 0.8
    assert(finite(interval) and interval > 0, "生成间隔必须大于0")
    local offsets, laneCounts = {}, {}
    for _, id in ipairs(portals) do
        offsets[id] = wave.portal_offsets and wave.portal_offsets[id] or 0
        assert(finite(offsets[id]) and offsets[id] >= 0, "入口错峰时间无效")
        laneCounts[id] = 0
    end
    ---@type {at:number, portal:string, role:string, order:integer, subtype?:string, opportunity_tag?:string, spawn_offset?:table, route_id?:string, special?:boolean, spawn_key?:string, squad_id?:integer, regional?:boolean}[]
    local derived = {}
    local function add(at, portal, role)
        assert(config.enemies and config.enemies[role], "怪物角色未配置：" .. role)
        derived[#derived + 1] = { at = at, portal = portal, role = role, order = #derived + 1 }
    end
    for i = 1, ordinary do
        local lane = (i - 1) % #portals + 1
        local portal = portals[lane]
        local localIndex = laneCounts[portal] + 1
        laneCounts[portal] = localIndex
        add(offsets[portal] + (localIndex - 1) * interval, portal, ordinaryRole(waveId, portal, lane, localIndex))
    end
    for i = 1, elites do
        local portal = portals[(i - 1) % #portals + 1]
        add(offsets[portal] + laneCounts[portal] * interval, portal, "elite")
        laneCounts[portal] = laneCounts[portal] + 1
    end
    if wave.boss_type then
        assert(wave.boss_type == "commander" or wave.boss_type == "siege" or wave.boss_type == "final", "Boss类型无效")
        assert(active[wave.boss_portal], "Boss入口未开启")
        add(3, wave.boss_portal, wave.boss_type)
    else
        assert(wave.boss_portal == nil, "无Boss波不能声明Boss入口")
    end
    -- R38/Q20 临时机会导演：只挑已派生advance普通名额；不同波选择不同队列位置。
    -- W3恰一只，W4–5至少两只，后续按压力预算递增但不上瘾于全爆炸。
    local opportunities = config.opportunities or {}
    if waveId >= (opportunities.first_wave or 3) then
        ---@type integer[]
        local candidates = {}
        for index, unit in ipairs(derived) do if unit.role == "advance" then candidates[#candidates + 1] = index end end
        local wanted = waveId == 3 and 1 or math.min(6, 2 + math.floor((waveId - 4) / 4))
        wanted = math.min(wanted, #candidates)
        local used = {}
        for n = 1, wanted do
            local offset = waveId == 3 and 2 or ((waveId * 3 + (n - 1) * (opportunities.explosive_gap or 9)) % math.max(1, #candidates))
            local cursor = offset % math.max(1, #candidates) + 1
            while used[cursor] do cursor = cursor % #candidates + 1 end
            used[cursor] = true
            local candidateIndex = candidates[cursor] --[[@as integer]]
            local unit = derived[candidateIndex] --[[@as table]]
            unit.subtype = "explosive"
            unit.opportunity_tag = waveId <= 5 and "space_observe" or waveId <= 10 and "space_repeat"
                or waveId <= 15 and "space_transfer" or "space_tradeoff"
        end
    end
    -- 同入口小幅横向不同位置，所有普通单位均有偏移；不绑定玩家坐标/动作，不移动入口。
    for index, unit in ipairs(derived) do
        if unit.role == "advance" or unit.role == "ranged" or unit.role == "charger" then
            local amount = (((index + waveId) % 3) - 1) * (opportunities.lane_offset or 0.45)
            unit.spawn_offset = unit.portal == "S" and { x = amount, y = 0 } or { x = 0, y = amount }
        end
    end
    -- 独立特殊队列不占普通名额，也不参加普通机会/间隔规则；同刻追加稳定order。
    for index, special in ipairs(validateSpecial(config, wave)) do
        add(special.at, special.portal, special.role)
        local unit = derived[#derived]
        unit.route_id, unit.special = special.route_id, true
        unit.squad_id = special.squad_id
        unit.spawn_key = special.spawn_key or ("wave:" .. tostring(waveId) .. ":special:" .. tostring(index))
    end
    for _, regional in ipairs(wave.regional_units or {}) do
        assert(config.sanctuary_expansion and config.portals[regional.portal] and config.enemies[regional.role], "区域入口配置无效")
        add(regional.at, regional.portal, regional.role)
        derived[#derived].regional = true
    end
    -- 同时刻按派生顺序稳定排序；延期只阻挡队首，不能绕过它生成另一入口。
    table.sort(derived, function(a, b) return a.at < b.at or (a.at == b.at and a.order < b.order) end)
    ---@type DefenseWaveUnit[]
    local queue = {}
    for _, unit in ipairs(derived) do
        queue[#queue + 1] = { at = unit.at, portal = unit.portal, role = unit.role,
            subtype = unit.subtype, opportunity_tag = unit.opportunity_tag, spawn_offset = unit.spawn_offset,
            route_id = unit.route_id, special = unit.special, spawn_key = unit.spawn_key, squad_id = unit.squad_id, regional = unit.regional }
    end
    return queue
end

-- 验收只读夹具：用来断言R16各行未漂移，不是编辑输入，队列仍仅从Config生成。
local EXPECTED = {
    { "W",18,0 }, { "E",24,0 }, { "S",30,0 }, { "WE",36,0 }, { "S",24,1 },
    { "WS",42,0 }, { "ES",48,1 }, { "WE",54,0 }, { "WS",60,1 }, { "WE",36,0,"commander","E" },
    { "WES",64,0 }, { "WES",70,1 }, { "WES",76,1 }, { "WES",82,2 }, { "WES",45,0,"siege","S" },
    { "WES",90,1 }, { "WES",96,2 }, { "WES",102,2 }, { "WES",108,2 }, { "WES",54,0,"final","S" },
}

-- 成功返回true和计数快照；legacy保留原20行/1176断言，扩展先通用再独立声明计数。
function WaveDirector.Validate(config)
    assert(type(config) == "table" and type(config.waves) == "table" and #config.waves > 0, "缺少波次配置")
    local legacy = not config.scenario_id or config.scenario_id == "legacy_v02"
    if legacy then
        assert(#config.waves == 20, "必须保留完整20波配置")
        assert(config.batch_interval == 0.8, "当前原型每入口间隔必须是0.8秒")
        assert(config.alive_soft_limit == 80, "当前原型存活软上限必须为80")
    else
        assert(finite(config.batch_interval) and config.batch_interval > 0, "生成间隔必须大于0")
        assert(count(config.alive_soft_limit, "存活软上限") > 0, "存活软上限必须大于0")
    end
    local normal, elite, boss, special, total = 0, 0, 0, 0, 0
    for i, wave in ipairs(config.waves) do
        assert(wave.wave_id == i, "波号必须连续")
        local portals = enabledPortals(config, wave)
        if legacy then
            local row = EXPECTED[i]
            assert(table.concat(portals) == row[1], "启用入口与R16不一致：W" .. i)
            assert(wave.ordinary == row[2] and wave.elite_count == row[3], "怪物数量与R16不一致：W" .. i)
            assert(wave.boss_type == row[4] and wave.boss_portal == row[5], "Boss与R16不一致：W" .. i)
            assert((wave.special_count or 0) == 0, "legacy_v02不能附加特殊单位")
        end
        local queue = WaveDirector.BuildQueue(config, i)
        local n, e, b, s, previous, laneTimes = 0, 0, 0, 0, -1, {}
        for _, unit in ipairs(queue) do
            assert(unit.at >= previous and unit.at >= 0, "生成时间未排序")
            previous = unit.at
            if unit.special then s = s + 1
            elseif unit.role == "elite" then e = e + 1
            elseif unit.role == "commander" or unit.role == "siege" or unit.role == "final" then
                b = b + 1
                assert(unit.at == 3, "Boss必须在3秒入队")
            else
                n = n + 1
                if legacy then
                    assert(i >= 4 or unit.role == "advance", "W4之前不能出现远射")
                    assert(i >= 6 or unit.role ~= "charger", "W6之前不能出现冲锋")
                end
            end
            if not unit.special and unit.role ~= "commander" and unit.role ~= "siege" and unit.role ~= "final" then
                local last = laneTimes[unit.portal]
                assert(not last or unit.at - last >= config.batch_interval - EPS, "每入口普通/精英间隔不足")
                laneTimes[unit.portal] = unit.at
            end
        end
        assert(n == wave.ordinary + #(wave.regional_units or {}) and e == wave.elite_count and b == (wave.boss_type and 1 or 0), "派生普通队列数量错误")
        assert(s == (wave.special_count or 0), "派生特殊队列数量错误")
        normal, elite, boss, special, total = normal + n, elite + e, boss + b, special + s, total + #queue
    end
    local ordinary = normal + elite + boss
    if legacy then
        assert(normal == 1159 and elite == 14 and boss == 3 and total == 1176, "20波总计应为1159普通+14精英+3Boss=1176")
    else
        local declared = config.declared_totals or {}
        local ordinaryTotal = config.declared_ordinary_total or declared.ordinary
        local specialTotal = config.declared_special_total or declared.special
        assert(ordinaryTotal ~= nil and specialTotal ~= nil, "扩展场景必须声明普通/特殊独立总数")
        assert(count(ordinaryTotal, "声明普通总数") == ordinary, "声明普通总数不一致")
        assert(count(specialTotal, "声明特殊总数") == special, "声明特殊总数不一致")
        for key, actual in pairs({ normal = normal, elite = elite, boss = boss, total = total }) do
            if declared[key] ~= nil then assert(count(declared[key], "声明" .. key) == actual, "声明" .. key .. "总数不一致") end
        end
    end
    return true, { waves = #config.waves, normal = normal, elite = elite, boss = boss, ordinary = ordinary, special = special, total = total }
end

---@param waveId integer
function WaveDirector.New(config, waveId)
    local self = setmetatable({}, WaveDirector)
    self:Init(config, waveId)
    return self
end

---@param waveId integer
function WaveDirector:Init(config, waveId)
    self.config, self.wave_id = config, waveId
    self.queue = WaveDirector.BuildQueue(config, waveId)
    self.cursor, self.elapsed, self.emitted, self.delayed = 1, 0, 0, 0
    self.started, self.generation_complete, self.blocked = false, false, false
    self.alive_limit = count(config.alive_soft_limit or 80, "存活软上限")
    assert(self.alive_limit > 0, "存活软上限必须大于0")
end

-- true表示首次启动，false表示已经启动；不重置elapsed/cursor，不重复入场。
function WaveDirector:Start()
    if self.started then return false end
    self.started = true
    self.generation_complete = #self.queue == 0
    return true
end

-- 返回本次成功生成数；只有回调严格返回true才推进cursor/emitted。
-- dt=0不处理到期单位，保障暂停时不会因队首at=0或延期而继续生成。
---@param dt number
---@param aliveCount integer
---@param spawnCallback fun(unit: DefenseWaveUnit): boolean
---@return integer
function WaveDirector:Update(dt, aliveCount, spawnCallback)
    assert(finite(dt) and dt >= 0, "生成器dt必须是非负有限数")
    assert(finite(aliveCount) and aliveCount >= 0 and aliveCount == math.floor(aliveCount), "存活数必须是非负整数")
    assert(type(spawnCallback) == "function", "缺少生成回调")
    if not self.started or self.generation_complete or dt == 0 then return 0 end
    self.elapsed = self.elapsed + dt
    self.blocked = false
    local spawned = 0
    while self.cursor <= #self.queue do
        local unit = self.queue[self.cursor]
        if unit.at > self.elapsed + EPS then break end
        -- aliveCount是本帧起始快照，加本次成功数，防止一帧多入口越过80。
        if aliveCount + spawned >= self.alive_limit then
            self.delayed = self.delayed + 1
            self.blocked = true
            break
        end
        -- 副本隔离回调意外改字段；失败后的队首保持原始时间/入口/角色。
        if spawnCallback({ at = unit.at, portal = unit.portal, role = unit.role, subtype = unit.subtype,
            opportunity_tag = unit.opportunity_tag, route_id = unit.route_id, special = unit.special, spawn_key = unit.spawn_key, squad_id = unit.squad_id, regional = unit.regional,
            spawn_offset = unit.spawn_offset and { x = unit.spawn_offset.x, y = unit.spawn_offset.y } }) ~= true then
            self.delayed = self.delayed + 1
            self.blocked = true
            break
        end
        self.cursor, self.emitted = self.cursor + 1, self.emitted + 1
        spawned = spawned + 1
    end
    self.generation_complete = self.cursor > #self.queue
    return spawned
end

---@return integer
function WaveDirector:Remaining()
    return math.max(0, #self.queue - self.cursor + 1)
end

-- 不暴露队列可变引用；delayed是累计阻挡Update次数，不是丢弃数或延期单位数。
function WaveDirector:Snapshot()
    local pendingDue = 0
    for i = self.cursor, #self.queue do
        if self.queue[i].at > self.elapsed + EPS then break end
        pendingDue = pendingDue + 1
    end
    return { wave_id = self.wave_id, cursor = self.cursor, elapsed = self.elapsed,
        started = self.started, generation_complete = self.generation_complete,
        emitted = self.emitted, delayed = self.delayed, blocked = self.blocked,
        remaining = self:Remaining(), pending_due = pendingDue, total = #self.queue }
end

return WaveDirector
