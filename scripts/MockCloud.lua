--- ============================================================================
--- clientCloud 本地 Mock（预览环境用）
--- 在引擎未注入 clientCloud / GetUserNickname 时自动启用
--- 数据存储在本地文件 mockcloud.json，重启后保留
--- ============================================================================

---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local MockCloud = {}

-- ── 内存存储 ──
local store = {
    values  = {},   -- Set() 存储
    iscores = {},   -- SetInt()/Add() 存储
}

local SAVE_FILE = "mockcloud.json"

-- ── 持久化 ──
local function SaveStore()
    if not cjson then return end
    local file = File(SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(store))
        file:Close()
    end
end

local function LoadStore()
    if not cjson then return end
    if not fileSystem:FileExists(SAVE_FILE) then return end
    local file = File(SAVE_FILE, FILE_READ)
    if not file:IsOpen() then return end
    local raw = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, raw)
    if ok and data then
        store.values  = data.values  or {}
        store.iscores = data.iscores or {}
        print("[MockCloud] Loaded store: " .. tostring(#raw) .. " bytes")
    end
end

-- ── 生成假排行榜数据（首次使用时填充） ──
local FAKE_NAMES = {
    "勇敢猫猫", "无敌大王", "暴走忍者", "闪亮英雄", "元气骑士",
    "酷炫玩家", "幸运高手", "狂野勇士", "超级法师", "疾风剑客",
    "星光猎人", "暗影挑战者", "冰霜战神", "烈焰幸存者", "钢铁小萌新",
}

local function EnsureFakeLeaderboard(key)
    -- 检查是否已经有至少5条数据
    local count = 0
    for k, _ in pairs(store.iscores) do
        if k:find("^__user%d+__" .. key .. "$") then
            count = count + 1
        end
    end
    if count >= 5 then return end

    -- 生成10个假玩家数据
    math.randomseed(os.time())
    for i = 1, 10 do
        local uid = 100000 + i
        local userKey = "__user" .. uid .. "__" .. key
        if not store.iscores[userKey] then
            if key == "best_wave" then
                store.iscores[userKey] = math.random(5, 50)
            elseif key == "best_kills" then
                store.iscores[userKey] = math.random(50, 500)
            else
                -- 每日挑战等其他 key
                store.iscores[userKey] = math.random(3, 30)
            end
        end
    end
    SaveStore()
end

-- ── 排行榜排序 ──
local function BuildRankList(key, start, count, orderAsc, otherKeys)
    EnsureFakeLeaderboard(key)

    -- 收集所有该 key 的数据
    local entries = {}
    -- 先加自己的（如果有）
    local myScore = store.iscores[key]
    if myScore and type(myScore) == "number" then
        local entry = { userId = 999999, iscore = { [key] = myScore } }
        -- 附加 otherKeys
        for _, ok2 in ipairs(otherKeys or {}) do
            entry.iscore[ok2] = store.iscores[ok2] or 0
        end
        entries[#entries + 1] = entry
    end

    -- 加假玩家
    for k, v in pairs(store.iscores) do
        local uid = k:match("^__user(%d+)__" .. key .. "$")
        if uid then
            uid = tonumber(uid)
            local entry = { userId = uid, iscore = { [key] = v } }
            -- 附加 otherKeys（假数据）
            for _, ok2 in ipairs(otherKeys or {}) do
                local fakeOther = store.iscores["__user" .. uid .. "__" .. ok2]
                entry.iscore[ok2] = fakeOther or math.random(10, 200)
            end
            entries[#entries + 1] = entry
        end
    end

    -- 排序
    table.sort(entries, function(a, b)
        local va = a.iscore[key] or 0
        local vb = b.iscore[key] or 0
        if orderAsc then
            return va < vb
        else
            return va > vb
        end
    end)

    -- 分页
    local result = {}
    for i = start + 1, math.min(start + count, #entries) do
        local e = entries[i]
        e.player = e.userId  -- 兼容旧字段
        e.score = {}
        e.sscore = {}
        -- 给假玩家加 nickname 字段（方便 GetUserNickname mock）
        if e.userId ~= 999999 then
            local idx = ((e.userId - 100000 - 1) % #FAKE_NAMES) + 1
            e.nickname = FAKE_NAMES[idx]
        end
        result[#result + 1] = e
    end

    return result
end

-- ── BatchSet 链式构建器 ──
local BatchSetBuilder = {}
BatchSetBuilder.__index = BatchSetBuilder

function BatchSetBuilder:Set(key, value)
    self._ops[#self._ops + 1] = { op = "set", key = key, value = value }
    return self
end

function BatchSetBuilder:SetInt(key, value)
    self._ops[#self._ops + 1] = { op = "setint", key = key, value = math.floor(value) }
    return self
end

function BatchSetBuilder:Add(key, delta)
    self._ops[#self._ops + 1] = { op = "add", key = key, delta = delta }
    return self
end

function BatchSetBuilder:Delete(key)
    self._ops[#self._ops + 1] = { op = "delete", key = key }
    return self
end

function BatchSetBuilder:Save(desc, events)
    for _, op in ipairs(self._ops) do
        if op.op == "set" then
            store.values[op.key] = op.value
        elseif op.op == "setint" then
            store.iscores[op.key] = op.value
        elseif op.op == "add" then
            store.iscores[op.key] = (store.iscores[op.key] or 0) + op.delta
        elseif op.op == "delete" then
            store.values[op.key] = nil
            store.iscores[op.key] = nil
        end
    end
    SaveStore()
    if events and events.ok then
        events.ok()
    end
    return self
end

-- ── BatchGet 链式构建器 ──
local BatchGetBuilder = {}
BatchGetBuilder.__index = BatchGetBuilder

function BatchGetBuilder:Key(key)
    self._keys[#self._keys + 1] = key
    return self
end

function BatchGetBuilder:Fetch(events)
    local v = {}
    local s = {}
    for _, key in ipairs(self._keys) do
        if store.values[key] ~= nil then
            v[key] = store.values[key]
        end
        if store.iscores[key] ~= nil then
            s[key] = store.iscores[key]
        end
    end
    if events and events.ok then
        events.ok(v, s)
    end
    return self
end

-- ── Mock clientCloud 对象 ──
local mockClient = {}
mockClient.userId = 999999
mockClient.mapName = "preview"

function mockClient:Set(key, value, events)
    store.values[key] = value
    SaveStore()
    if events and events.ok then events.ok() end
end

function mockClient:SetInt(key, value, events)
    store.iscores[key] = math.floor(value)
    SaveStore()
    if events and events.ok then events.ok() end
end

function mockClient:Add(key, delta, events)
    store.iscores[key] = (store.iscores[key] or 0) + delta
    SaveStore()
    if events and events.ok then events.ok() end
end

function mockClient:Get(key, events)
    if events and events.ok then
        events.ok(
            { [key] = store.values[key] },
            { [key] = store.iscores[key] }
        )
    end
end

function mockClient:BatchSet()
    local builder = setmetatable({ _ops = {} }, BatchSetBuilder)
    return builder
end

function mockClient:BatchGet()
    local builder = setmetatable({ _keys = {} }, BatchGetBuilder)
    return builder
end

--- GetRankList(key, start, count, [orderAsc,] events, ...otherKeys)
function mockClient:GetRankList(key, start, count, ...)
    local args = { ... }
    local orderAsc = false
    local events
    local otherKeys = {}

    if type(args[1]) == "boolean" then
        orderAsc = args[1]
        events = args[2]
        for i = 3, #args do
            otherKeys[#otherKeys + 1] = args[i]
        end
    else
        events = args[1]
        for i = 2, #args do
            otherKeys[#otherKeys + 1] = args[i]
        end
    end

    local rankList = BuildRankList(key, start, count, orderAsc, otherKeys)
    if events and events.ok then
        events.ok(rankList)
    end
end

function mockClient:GetUserRank(userId, key, events)
    local rankList = BuildRankList(key, 0, 999, false, {})
    for i, entry in ipairs(rankList) do
        if entry.userId == userId then
            if events and events.ok then
                events.ok(i, entry.iscore[key] or 0)
            end
            return
        end
    end
    if events and events.ok then
        events.ok(nil, 0)
    end
end

function mockClient:GetRankTotal(key, events)
    local rankList = BuildRankList(key, 0, 999, false, {})
    if events and events.ok then
        events.ok(#rankList)
    end
end

-- ── Mock GetUserNickname ──
local function MockGetUserNickname(params)
    local nicknames = {}
    for _, uid in ipairs(params.userIds or {}) do
        if uid == 999999 then
            local SaveData = require("SaveData")
            nicknames[#nicknames + 1] = {
                userId = uid,
                nickname = SaveData.nickname or "我",
            }
        else
            local idx = ((uid - 100000 - 1) % #FAKE_NAMES) + 1
            if idx < 1 then idx = 1 end
            nicknames[#nicknames + 1] = {
                userId = uid,
                nickname = FAKE_NAMES[idx] or ("玩家" .. uid),
            }
        end
    end
    if params.onSuccess then
        params.onSuccess(nicknames)
    end
end

-- ── 初始化入口 ──
function MockCloud.Install()
    ---@diagnostic disable-next-line: undefined-global
    if clientCloud then
        print("[MockCloud] Real clientCloud detected, mock skipped")
        return false
    end

    LoadStore()

    -- 注入全局
    ---@diagnostic disable-next-line: lowercase-global
    clientCloud = mockClient
    ---@diagnostic disable-next-line: lowercase-global
    GetUserNickname = MockGetUserNickname

    print("[MockCloud] Installed! Local mock active (data in " .. SAVE_FILE .. ")")
    return true
end

return MockCloud
