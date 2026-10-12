-- 固定据点地图纯规则：只读取配置，不引用引擎，也不把塔/尸体/掉落加入障碍。
-- 碰撞设计（逻辑格，X 向右、Y 向下；下面仅是拓扑，不是像素测量）：
--     A2(锁)       后勤(25,2)-(39,8)       B2(锁)
--       |                 |                 |
--      A1 -- W(17,21) -- 主殿 -- E(47,21) -- B1
--                       [左柱] 核心 [右柱]
--                            |
--                         S(32,35)
--                            |
--                           C1 -- C2(锁)
-- 主殿闭矩形 (21,10)-(43,32)，两柱闭矩形 (24,20)-(27,23)、(37,19)-(40,22)。
-- 通道精确边界由 Config 灰盒推定；不是已确认的原图数值。外边界是矩形并集，
-- 不能逐个收缩矩形，否则连接处会出现假墙。圆体半径 r：距并集外边界 >= r；
-- 障碍/锁房做圆形 Minkowski 膨胀，接触即阻挡（包含四角，不只测圆心/四点）。
-- 先推演：r=0 允许落在外边界但不能碰柱；细缝中心只有宽度 >=2r 才能通过；
-- 房门与通道重叠时仍由整个锁房阻挡；高位移用连续线段判定+分步轴分离，不穿薄墙。

-- 通行点使用 {x:number, y:number}；路径数组的类型源头在 Path 中声明。
---@class DefenseMapRect
---@field id? string
---@field x1 number
---@field y1 number
---@field x2 number
---@field y2 number

---@class DefenseMapEdge
---@field ax number
---@field ay number
---@field bx number
---@field by number
---@field x1 number
---@field y1 number
---@field x2 number
---@field y2 number

---@class DefenseMapGrid
---@field step number
---@field cols integer
---@field rows integer
---@field valid table<number, boolean>
---@field origin_x number
---@field origin_y number

---@class DefenseMapField
---@field grid DefenseMapGrid
---@field next table<number, integer>
---@field queue integer[]
---@field cursor integer
---@field discovered table<number, integer>

---@class DefenseMap
---@field config table
---@field regions DefenseMapRect[]
---@field obstacles DefenseMapRect[]
---@field edges DefenseMapEdge[]
---@field room_regions table<string, DefenseMapRect>
---@field locked table<string, boolean>
---@field locked_regions table<string, DefenseMapRect[]>
---@field gate_regions table<string, DefenseMapRect>
---@field revision integer
---@field los_cache table
---@field origin_x number
---@field origin_y number
---@field width number
---@field height number
---@field grid_step number
---@field portal_radius number
---@field grids table<string, DefenseMapGrid>
---@field fields table<string, DefenseMapField>
---@field field_order string[]
---@field warmupJobs table[]
---@field warmupCursor integer
local Map = {}
Map.__index = Map
local EPS = 1e-9

local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function inside(x, y, r)
    return x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2
end

local function inUnion(regions, x, y)
    for _, r in ipairs(regions) do
        if inside(x, y, r) then return true end
    end
    return false
end

local function copyRect(r)
    assert(finite(r.x1) and finite(r.y1) and finite(r.x2) and finite(r.y2), "地图矩形坐标无效")
    assert(r.x1 < r.x2 and r.y1 < r.y2, "地图矩形必须有正面积")
    return { id = r.id, x1 = r.x1, y1 = r.y1, x2 = r.x2, y2 = r.y2 }
end

local function uniqueSorted(values)
    table.sort(values)
    local result = {}
    for _, v in ipairs(values) do
        if result[#result] ~= v then result[#result + 1] = v end
    end
    return result
end

-- 将所有矩形边界组成坐标分区，只有“通行/不通行”交界才是外墙。
local function buildEdges(regions)
    local xs, ys = {}, {}
    for _, r in ipairs(regions) do
        xs[#xs + 1], xs[#xs + 2] = r.x1, r.x2
        ys[#ys + 1], ys[#ys + 2] = r.y1, r.y2
    end
    xs, ys = uniqueSorted(xs), uniqueSorted(ys)
    local occupied = {}
    local cols = #xs - 1
    for j = 1, #ys - 1 do
        for i = 1, cols do
            occupied[(j - 1) * cols + i] = inUnion(regions, (xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2)
        end
    end
    local function cell(i, j)
        return i >= 1 and i <= cols and j >= 1 and j < #ys and occupied[(j - 1) * cols + i]
    end
    ---@type DefenseMapEdge[]
    local edges = {}
    ---@param ax number
    ---@param ay number
    ---@param bx number
    ---@param by number
    local function add(ax, ay, bx, by)
        edges[#edges + 1] = { ax = ax, ay = ay, bx = bx, by = by,
            x1 = math.min(ax, bx), y1 = math.min(ay, by), x2 = math.max(ax, bx), y2 = math.max(ay, by) }
    end
    for j = 1, #ys - 1 do
        for i = 1, cols do
            if cell(i, j) then
                if not cell(i - 1, j) then add(xs[i], ys[j], xs[i], ys[j + 1]) end
                if not cell(i + 1, j) then add(xs[i + 1], ys[j], xs[i + 1], ys[j + 1]) end
                if not cell(i, j - 1) then add(xs[i], ys[j], xs[i + 1], ys[j]) end
                if not cell(i, j + 1) then add(xs[i], ys[j + 1], xs[i + 1], ys[j + 1]) end
            end
        end
    end
    return edges
end

local function pointSegmentSq(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len = dx * dx + dy * dy
    local t = len == 0 and 0 or math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len))
    local ox, oy = px - ax - t * dx, py - ay - t * dy
    return ox * ox + oy * oy
end

-- 标量裁剪不创建闭包/临时矩形；与原闭区间算法保持相同的切线语义。
local function rectIntervalBounds(ax, ay, bx, by, x1, y1, x2, y2)
    local lo, hi = 0, 1
    local dx, dy = bx - ax, by - ay
    if dx == 0 then
        if ax < x1 or ax > x2 then return nil end
    else
        local a, b = (x1 - ax) / dx, (x2 - ax) / dx
        if a > b then a, b = b, a end
        lo, hi = math.max(lo, a), math.min(hi, b)
        if lo > hi then return nil end
    end
    if dy == 0 then
        if ay < y1 or ay > y2 then return nil end
    else
        local a, b = (y1 - ay) / dy, (y2 - ay) / dy
        if a > b then a, b = b, a end
        lo, hi = math.max(lo, a), math.min(hi, b)
        if lo > hi then return nil end
    end
    return lo, hi
end
local function rectInterval(ax, ay, bx, by, r)
    return rectIntervalBounds(ax, ay, bx, by, r.x1, r.y1, r.x2, r.y2)
end
local function segmentEdgeBoundsSq(ax, ay, bx, by, ex1, ey1, ex2, ey2)
    if rectIntervalBounds(ax, ay, bx, by, math.min(ex1, ex2), math.min(ey1, ey2),
        math.max(ex1, ex2), math.max(ey1, ey2)) then return 0 end
    return math.min(
        pointSegmentSq(ax, ay, ex1, ey1, ex2, ey2),
        pointSegmentSq(bx, by, ex1, ey1, ex2, ey2),
        pointSegmentSq(ex1, ey1, ax, ay, bx, by),
        pointSegmentSq(ex2, ey2, ax, ay, bx, by))
end
local function segmentEdgeSq(ax, ay, bx, by, edge)
    return segmentEdgeBoundsSq(ax, ay, bx, by, edge.ax, edge.ay, edge.bx, edge.by)
end
local function overlapsRect(x1, y1, x2, y2, r)
    return x1 <= r.x2 and x2 >= r.x1 and y1 <= r.y2 and y2 >= r.y1
end
local function contained(x, y, radius, r)
    return x - radius >= r.x1 and x + radius <= r.x2
        and y - radius >= r.y1 and y + radius <= r.y2
end

local function circleHitsRect(x, y, radius, r)
    local dx = math.max(r.x1 - x, 0, x - r.x2)
    local dy = math.max(r.y1 - y, 0, y - r.y2)
    return dx * dx + dy * dy <= radius * radius + EPS
end

local function segmentHitsRect(ax, ay, bx, by, radius, r)
    local padding = radius + 0.000032 -- 保留距离平方 EPS 对近切线的容差。
    if not overlapsRect(math.min(ax, bx) - padding, math.min(ay, by) - padding,
        math.max(ax, bx) + padding, math.max(ay, by) + padding, r) then return false end
    if rectInterval(ax, ay, bx, by, r) then return true end
    local rr = radius * radius + EPS
    return segmentEdgeBoundsSq(ax, ay, bx, by, r.x1, r.y1, r.x2, r.y1) <= rr
        or segmentEdgeBoundsSq(ax, ay, bx, by, r.x2, r.y1, r.x2, r.y2) <= rr
        or segmentEdgeBoundsSq(ax, ay, bx, by, r.x2, r.y2, r.x1, r.y2) <= rr
        or segmentEdgeBoundsSq(ax, ay, bx, by, r.x1, r.y2, r.x1, r.y1) <= rr
end

function Map.New(config)
    if config.polygon_expansion then return require("defense.RoomLattice").New(config, Map) end
    local self = setmetatable({}, Map)
    self:Init(config)
    return self
end

function Map:Init(config)
    assert(type(config) == "table" and config.map_size and config.walkable_regions, "缺少地图配置")
    self.config = config
    self.width, self.height = config.map_size.w, config.map_size.h
    local origin = config.map_origin or { x = 0, y = 0 }
    self.origin_x, self.origin_y = origin.x, origin.y
    assert(finite(self.origin_x) and finite(self.origin_y), "地图原点无效")
    assert(finite(self.width) and finite(self.height) and self.width > 0 and self.height > 0, "地图尺寸无效")
    self.regions, self.obstacles, self.room_regions, self.locked = {}, {}, {}, {}
    self.locked_regions, self.gate_regions, self.revision, self.los_cache = {}, {}, 0, {}
    for _, r in ipairs(config.walkable_regions) do
        local region = copyRect(r)
        assert(region.x1 >= self.origin_x and region.y1 >= self.origin_y
            and region.x2 <= self.origin_x + self.width and region.y2 <= self.origin_y + self.height, "通行区超出地图")
        self.regions[#self.regions + 1] = region
        if region.id then
            assert(not self.room_regions[region.id], "通行区ID重复")
            self.room_regions[region.id] = region
        end
    end
    assert(#self.regions > 0, "地图没有通行区")
    for _, r in ipairs(config.obstacles or {}) do self.obstacles[#self.obstacles + 1] = copyRect(r) end
    for _, room in ipairs(config.rooms or {}) do
        assert(self.room_regions[room.id], "房间缺少同名通行矩形")
        assert(self.locked[room.id] == nil, "房间ID重复")
        local hasPrerequisite = room.prerequisite ~= nil or room.prerequisites ~= nil or room.unlock_condition ~= nil
        local locked = (hasPrerequisite or room.tier == 2) and room.unlocked ~= true
        if config.locked_rooms and config.locked_rooms[room.id] ~= nil then
            locked = config.locked_rooms[room.id] == true
        end
        self.locked[room.id] = locked
        self.locked_regions[room.id] = { self.room_regions[room.id] }
    end
    -- gate_regions 是通行几何中的实体闸门，不是敌人专有的穿墙权限。
    -- 一个 gate_id 可对应多段闸门；SetUnlocked 同时控制全部段与所有缓存。
    for _, def in ipairs(config.gate_regions or {}) do
        local gate = copyRect(def)
        local id = def.gate_id or def.id
        assert(type(id) == "string" and id ~= "" and not self.room_regions[id], "闸门ID无效或与通行区重名")
        assert(gate.x1 >= self.origin_x and gate.y1 >= self.origin_y
            and gate.x2 <= self.origin_x + self.width and gate.y2 <= self.origin_y + self.height, "闸门超出地图")
        if not self.locked_regions[id] then
            self.locked_regions[id] = {}
            self.locked[id] = def.unlocked ~= true
            if config.locked_gates and config.locked_gates[id] ~= nil then self.locked[id] = config.locked_gates[id] == true end
        end
        self.locked_regions[id][#self.locked_regions[id] + 1] = gate
        self.gate_regions[id] = gate
    end
    self.edges = buildEdges(self.regions)
    self.grid_step = config.path_grid_step or 0.5
    assert(self.grid_step == 0.5 or self.grid_step == 1, "寻路网格只支持0.5或1格")
    self.portal_radius = config.player and config.player.radius or 0
    for _, enemy in pairs(config.enemies or {}) do
        self.portal_radius = math.max(self.portal_radius, enemy.radius or 0)
    end
    self.grids, self.fields, self.field_order = {}, {}, {}
    self.warmupJobs, self.warmupCursor = {}, 1
end

---@return boolean
function Map:IsWalkable(x, y, radius)
    radius = radius or 0
    if not finite(x) or not finite(y) or not finite(radius) or radius < 0 then return false end
    if not inUnion(self.regions, x, y) then return false end
    for _, r in ipairs(self.obstacles) do
        if circleHitsRect(x, y, radius, r) then return false end
    end
    for id, locked in pairs(self.locked) do
        if locked then
            for _, r in ipairs(self.locked_regions[id]) do
                if circleHitsRect(x, y, radius, r) then return false end
            end
        end
    end
    local x1, y1, x2, y2 = x - radius, y - radius, x + radius, y + radius
    if radius > 0 then
        -- 圆体完全位于任一通行凸矩形时，其并集外缘不可能侵入圆体。
        -- 柱和锁房已单独检查；连接处才需要进一步遍历真实外缘。
        for _, r in ipairs(self.regions) do if contained(x, y, radius, r) then return true end end
        for _, e in ipairs(self.edges) do
            if overlapsRect(x1, y1, x2, y2, e)
                and pointSegmentSq(x, y, e.ax, e.ay, e.bx, e.by) < radius * radius - EPS then return false end
        end
    end
    return true
end

---@return boolean
function Map:LineOfSight(x1, y1, x2, y2, radius)
    radius = radius or 0
    if not self:IsWalkable(x1, y1, radius) or not self:IsWalkable(x2, y2, radius) then return false end
    -- 同一个凸矩形已包含整段时，不再分配/排序15个覆盖区间。
    -- 仍继续检查真实柱体、锁门与外缘，不能把主殿当无碰撞区域。
    local coveredByOne, capsuleByOne = false, false
    for _, r in ipairs(self.regions) do
        if contained(x1, y1, 0, r) and contained(x2, y2, 0, r) then
            coveredByOne = true
            if contained(x1, y1, radius, r) and contained(x2, y2, radius, r) then capsuleByOne = true; break end
        end
    end
    if not coveredByOne then
        local intervals = {}
        for _, r in ipairs(self.regions) do
            local lo, hi = rectInterval(x1, y1, x2, y2, r)
            if lo then intervals[#intervals + 1] = { lo = lo, hi = hi } end
        end
        table.sort(intervals, function(a, b) return a.lo < b.lo end)
        local covered = 0
        for _, interval in ipairs(intervals) do
            if interval.lo > covered + EPS then return false end
            covered = math.max(covered, interval.hi)
        end
        if covered < 1 - EPS then return false end
    end
    for _, r in ipairs(self.obstacles) do
        if segmentHitsRect(x1, y1, x2, y2, radius, r) then return false end
    end
    for id, locked in pairs(self.locked) do
        if locked then
            for _, r in ipairs(self.locked_regions[id]) do
                if segmentHitsRect(x1, y1, x2, y2, radius, r) then return false end
            end
        end
    end
    if radius > 0 and not capsuleByOne then
        local ax, ay = math.min(x1, x2) - radius, math.min(y1, y2) - radius
        local bx, by = math.max(x1, x2) + radius, math.max(y1, y2) + radius
        for _, e in ipairs(self.edges) do
            if overlapsRect(ax, ay, bx, by, e)
                and segmentEdgeSq(x1, y1, x2, y2, e) < radius * radius - EPS then return false end
        end
    end
    return true
end

---@return number, number
function Map:Move(x, y, dx, dy, radius)
    radius = radius or 0
    if not finite(dx) or not finite(dy) or not self:IsWalkable(x, y, radius) then return x, y end
    if dx == 0 and dy == 0 then return x, y end
    -- 合法斜向胶囊扫掠直接到达终点。不能先拆成轴段：轴段可能碰柱，
    -- 即使真实斜线有完整半径余量，旧轴分离也会偏离Path的合法线段。
    if self:LineOfSight(x, y, x + dx, y + dy, radius) then return x + dx, y + dy end
    local steps = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy)) / 0.2))
    local sx, sy = dx / steps, dy / steps
    local function axis(ax, ay, bx, by)
        if self:LineOfSight(ax, ay, bx, by, radius) then return bx, by end
        -- 收敛到接触前的合法点，避免整步回退形成明显的墙边空隙。
        local lo, hi = 0, 1
        for _ = 1, 14 do
            local t = (lo + hi) / 2
            if self:LineOfSight(ax, ay, ax + (bx - ax) * t, ay + (by - ay) * t, radius) then lo = t else hi = t end
        end
        return ax + (bx - ax) * lo, ay + (by - ay) * lo
    end
    local nx, ny = x, y
    for _ = 1, steps do
        if sx ~= 0 then nx, ny = axis(nx, ny, nx + sx, ny) end
        if sy ~= 0 then nx, ny = axis(nx, ny, nx, ny + sy) end
    end
    return nx, ny
end

---@return string?
function Map:RoomAt(x, y)
    for _, room in ipairs(self.config.rooms or {}) do
        if inside(x, y, self.room_regions[room.id]) then return room.id end
    end
    return nil
end

---@return boolean
function Map:IsInRegion(id, x, y)
    local region = self.room_regions[id]
    return region ~= nil and finite(x) and finite(y) and inside(x, y, region) or false
end

-- 返回 true 表示合法设置；支持所有探索房间及显式闸门，重复设置不改变revision。
function Map:SetUnlocked(id, unlocked)
    if self.locked[id] == nil or type(unlocked) ~= "boolean" then return false end
    local locked = not unlocked
    if self.locked[id] ~= locked then
        self.locked[id] = locked
        self.revision = self.revision + 1
        self.grids, self.fields, self.field_order, self.los_cache = {}, {}, {}, {}
        self.warmupCursor = 1
    end
    return true
end

local function gridPoint(grid, id)
    local index = id - 1
    return grid.origin_x + (index % grid.cols) * grid.step, grid.origin_y + (index // grid.cols) * grid.step
end

function Map:GetGrid(radius)
    local key = string.format("%.17g", radius)
    if self.grids[key] then return self.grids[key] end
    ---@type DefenseMapGrid
    local grid = { step = self.grid_step, cols = math.floor(self.width / self.grid_step) + 1,
        rows = math.floor(self.height / self.grid_step) + 1, valid = {}, origin_x = self.origin_x, origin_y = self.origin_y }
    -- 半格坐标与BFS顺序保持不变，只按首次访问懒算精确通行性。
    -- 每种半径不再在首只怪物出生帧扫描全图12513个格点。
    setmetatable(grid.valid, { __index = function(values, id)
        local x, y = gridPoint(grid, id)
        local valid = self:IsWalkable(x, y, radius)
        rawset(values, id, valid)
        return valid
    end })
    self.grids[key] = grid
    return grid
end

-- 任意连续坐标连接附近合法半格中心；连接线也必须通过完整半径检测。
function Map:GridAnchors(grid, x, y, radius)
    local ix, iy = math.floor((x - grid.origin_x) / grid.step), math.floor((y - grid.origin_y) / grid.step)
    local anchors = {}
    for j = math.max(0, iy - 1), math.min(grid.rows - 1, iy + 2) do
        for i = math.max(0, ix - 1), math.min(grid.cols - 1, ix + 2) do
            local id = j * grid.cols + i + 1
            local px, py = gridPoint(grid, id)
            if grid.valid[id] and self:LineOfSight(x, y, px, py, radius) then
                anchors[#anchors + 1] = { id = id, distance = (px - x)^2 + (py - y)^2 }
            end
        end
    end
    table.sort(anchors, function(a, b) return a.distance < b.distance or (a.distance == b.distance and a.id < b.id) end)
    return anchors
end

---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param radius number?
---@param nodeBudget number? 仅资源预热使用；正常寻路不设预算，不截断合法路径。
---@return table[]?
function Map:Path(x1, y1, x2, y2, radius, nodeBudget)
    radius = radius or 0
    if not self:IsWalkable(x1, y1, radius) or not self:IsWalkable(x2, y2, radius) then return nil end
    if self:LineOfSight(x1, y1, x2, y2, radius) then
        ---@type table[]
        local direct = { { x = x1, y = y1 }, { x = x2, y = y2 } }
        return direct
    end
    local grid = self:GetGrid(radius)
    local starts = self:GridAnchors(grid, x1, y1, radius)
    if #starts == 0 then return nil end
    local key = string.format("%.17g:%.17g:%.17g", x2, y2, radius)
    ---@type DefenseMapField?
    local field = self.fields[key]
    if not field then
        local goals = self:GridAnchors(grid, x2, y2, radius)
        if #goals == 0 then return nil end
        field = { grid = grid, next = {}, queue = {}, cursor = 1, discovered = {} }
        for _, goal in ipairs(goals) do
            field.next[goal.id] = 0
            field.discovered[goal.id] = 0
            field.queue[#field.queue + 1] = goal.id
        end
        -- 保持基线六个目标场的淘汰顺序，避免缓存历史改变起点锚点选择。
        -- 三入口共享同一个核心终点；本波所需的四种半径均能保留。
        self.fields[key] = field
        self.field_order[#self.field_order + 1] = key
        if #self.field_order > 6 then self.fields[table.remove(self.field_order, 1)] = nil end
    end
    local function reached()
        -- 选择冷搜索首先触及的起点锚点；同一展开步内仍按距离/id顺序。
        -- 预热扩展了更多节点时不能仅按“现在已visited”反转绕柱方向。
        local best, earliest = nil, math.huge
        for _, start in ipairs(starts) do
            local discovered = field.discovered[start.id]
            if discovered and discovered < earliest then best, earliest = start.id, discovered end
        end
        return best
    end
    local found = reached()
    local expanded = 0
    while not found and field.cursor <= #field.queue do
        if nodeBudget and expanded >= nodeBudget then return nil end
        expanded = expanded + 1
        local id = field.queue[field.cursor]
        field.cursor = field.cursor + 1
        local x, y = gridPoint(grid, id)
        local col, row = (id - 1) % grid.cols, (id - 1) // grid.cols
        local neighbors = {}
        if col > 0 then neighbors[#neighbors + 1] = id - 1 end
        if col < grid.cols - 1 then neighbors[#neighbors + 1] = id + 1 end
        if row > 0 then neighbors[#neighbors + 1] = id - grid.cols end
        if row < grid.rows - 1 then neighbors[#neighbors + 1] = id + grid.cols end
        for _, neighbor in ipairs(neighbors) do
            if grid.valid[neighbor] and field.next[neighbor] == nil then
                local px, py = gridPoint(grid, neighbor)
                if self:LineOfSight(x, y, px, py, radius) then
                    field.next[neighbor] = id
                    field.discovered[neighbor] = field.cursor - 1
                    field.queue[#field.queue + 1] = neighbor
                end
            end
        end
        found = reached()
    end
    if not found then return nil end
    ---@type table[]
    local raw = { { x = x1, y = y1 } }
    local id = found
    while id ~= 0 do
        local x, y = gridPoint(grid, id)
        raw[#raw + 1] = { x = x, y = y }
        id = field.next[id]
    end
    raw[#raw + 1] = { x = x2, y = y2 }
    -- 只简化可见段，不进行会穿柱的曲线平滑；首尾保持调用者的精确坐标。
    ---@type table[]
    local result = { raw[1] }
    local index = 1
    while index < #raw do
        local nextIndex = #raw
        while nextIndex > index + 1 and not self:LineOfSight(raw[index].x, raw[index].y, raw[nextIndex].x, raw[nextIndex].y, radius) do
            nextIndex = nextIndex - 1
        end
        result[#result + 1] = raw[nextIndex]
        index = nextIndex
    end
    return result
end

-- 战备/预警阶段分帧预热下一波真正需要的核心路径，不推进世界时间。
-- 每次只展开有限网格节点；遇到实际敌人时 Path 仍会完整求解，不丢怪或缩短路线。
function Map:PrepareWave(wave)
    local roles, jobs = { advance = true }, {}
    if wave.wave_id >= 4 then roles.ranged = true end
    if wave.wave_id >= 6 then roles.charger = true end
    if wave.elite_count > 0 then roles.elite = true end
    if wave.boss_type then roles[wave.boss_type] = true end
    local radii = {}
    for role in pairs(roles) do
        local radius = self.config.enemies[role].radius
        radii[radius] = true
    end
    local sorted = {}
    for radius in pairs(radii) do sorted[#sorted + 1] = radius end
    table.sort(sorted)
    for _, radius in ipairs(sorted) do
        for _, portal in ipairs(wave.active_portals) do
            local x, y = self:PortalPoint(portal, radius)
            if x and y then jobs[#jobs + 1] = { x = x, y = y, radius = radius } end
        end
    end
    self.warmupJobs, self.warmupCursor = jobs, 1
end
function Map:Warmup(nodeBudget)
    local job = self.warmupJobs and self.warmupJobs[self.warmupCursor or 1]
    if not job then return end
    local core = self.config.core_position
    local path = self:Path(job.x, job.y, core.x, core.y, job.radius, nodeBudget or 48)
    if path then self.warmupCursor = self.warmupCursor + 1
    else
        local key = string.format("%.17g:%.17g:%.17g", core.x, core.y, job.radius)
        local field = self.fields[key]
        if not field or field.cursor > #field.queue then self.warmupCursor = self.warmupCursor + 1 end
    end
end

-- 返回 x,y；默认按配置中最大的敌人半径校验，可显式传具体实体半径。
-- 无合法点返回 nil,nil，调用方须保留卡怪并记录错误，不得静默删除。
---@return number?, number?
function Map:PortalPoint(portal, radius)
    local point = type(portal) == "string" and self.config.portals[portal] or portal
    if type(point) ~= "table" or not finite(point.x) or not finite(point.y) then return nil, nil end
    radius = radius or self.portal_radius
    if self:IsWalkable(point.x, point.y, radius) then return point.x, point.y end
    -- 仅在同入口两格内修复落点，不把卡怪送到核心或另一入口。
    for ring = 1, 4 do
        for dy = -ring, ring do
            for dx = -ring, ring do
                if math.abs(dx) == ring or math.abs(dy) == ring then
                    local x, y = point.x + dx * 0.5, point.y + dy * 0.5
                    if self:IsWalkable(x, y, radius) then return x, y end
                end
            end
        end
    end
    return nil, nil
end

return Map
