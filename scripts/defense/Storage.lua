-- 独立阶段记录存储端口，不调用旧 SaveData/云/广告/IAP。
-- 原生宿主持久化；WASM File 为内存沙箱，刷新持久化待平台适配，不虚报保证。
local json = require("cjson")
local Storage = {}
local PRIMARY, BACKUP = "defense_meta_v1.json", "defense_meta_v1.backup.json"

local function nonnegativeInteger(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge and value == math.floor(value)
end
local function valid(data)
    if type(data) ~= "table" or data.schema_version ~= 1 or
        (data.revision ~= nil and not nonnegativeInteger(data.revision))
        or type(data.stages) ~= "table" or type(data.chapters) ~= "table" or type(data.story_seen) ~= "table" then return false end
    for id, record in pairs(data.stages) do
        if type(id) ~= "string" or type(record) ~= "table" or not nonnegativeInteger(record.wave)
            or not nonnegativeInteger(record.chapter) or record.completed ~= true then return false end
    end
    for id, enabled in pairs(data.chapters) do if type(id) ~= "string" or type(enabled) ~= "boolean" then return false end end
    for id, seen in pairs(data.story_seen) do if type(id) ~= "string" or type(seen) ~= "boolean" then return false end end
    if data.settings ~= nil then
        if type(data.settings) ~= "table" then return false end
        local volume = data.settings.volume
        if volume ~= nil and (type(volume) ~= "number" or volume ~= volume or volume < 0 or volume > 1) then return false end
        if data.settings.reduced_effects ~= nil and type(data.settings.reduced_effects) ~= "boolean" then return false end
        if data.settings.hints ~= nil and type(data.settings.hints) ~= "boolean" then return false end
    end
    if data.observation_seen ~= nil then
        if type(data.observation_seen) ~= "table" then return false end
        for id, seen in pairs(data.observation_seen) do if type(id) ~= "string" or type(seen) ~= "boolean" then return false end end
    end
    if data.last_report ~= nil then
        local report = data.last_report
        if type(report) ~= "table" or not nonnegativeInteger(report.wave) or not nonnegativeInteger(report.total_waves)
            or type(report.chains) ~= "table" or type(report.result) ~= "string" then return false end
    end
    if data.scenario_reports ~= nil then
        if type(data.scenario_reports) ~= "table" then return false end
        for namespace, report in pairs(data.scenario_reports) do
            if type(namespace) ~= "string" or type(report) ~= "table" or report.record_namespace ~= namespace
                or not nonnegativeInteger(report.wave) or not nonnegativeInteger(report.total_waves)
                or type(report.chains) ~= "table" or type(report.result) ~= "string" then return false end
        end
    end
    return true
end

local function read(path)
    -- 首启无存档是正常状态；File构造会先记录引擎错误，pcall无法屏蔽。
    if not fileSystem:FileExists(path) then return nil end
    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then if file then file:Dispose() end; return nil end
    local readOK, text = pcall(file.ReadString, file)
    file:Dispose()
    if not readOK then print("[Defense][存档] 读取失败: " .. path); return nil end
    local ok, data = pcall(json.decode, text)
    if ok and valid(data) then return data end
    print("[Defense][存档] 无效记录: " .. path)
end

---@return table
function Storage.Load()
    for _, path in ipairs({ PRIMARY, BACKUP }) do
        local ok, raw = pcall(read, path)
        local data = raw --[[@as table?]]
        if ok and data then
            data.revision = data.revision or 0
            data.settings = data.settings or { volume = 1, reduced_effects = false, hints = true }
            return data --[[@as table]]
        end
        if not ok then print("[Defense][存档] 记录不可读，尝试下一副本: " .. path) end
    end
    return { schema_version = 1, revision = 0, stages = {}, chapters = { ["1"] = true }, story_seen = {},
        settings = { volume = 1, reduced_effects = false, hints = true } }
end

local function write(path, data)
    local encoded, text = pcall(json.encode, data)
    if not encoded then return false end
    local file = File(path, FILE_WRITE)
    if not file or not file:IsOpen() then if file then file:Dispose() end; return false end
    local ok, written = pcall(function()
        local result = file:WriteString(text)
        file:Flush()
        return result
    end)
    file:Dispose()
    return ok and written == true
end

function Storage.Save(data)
    assert(valid(data), "阶段记录结构无效")
    local previous = read(PRIMARY)
    if previous and not write(BACKUP, previous) then error("备份记录写入失败，保留旧档") end
    if not write(PRIMARY, data) then error("阶段记录写入失败") end
    return true
end
return Storage
