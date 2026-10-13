-- 多边形地图插件：房间与走廊的真实并集，Map 原有签名保持。
-- 碰撞：圆体到并集外墙 >= radius；开口处删除共用边，不收缩每间房制造假墙。
-- 关门房间整块禁止通行；连续胶囊扫掠不会越墙，敌人与玩家共用通行规则。
local Lattice = require("defense.Lattice")
local Index = require("defense.RoomIndex")
local RoomLattice = {}
local EPS = 1e-7
local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function cross(ax, ay, bx, by) return ax * by - ay * bx end
local function inside(points, x, y)
    for i, a in ipairs(points) do
        local b = points[i % #points + 1]
        if cross(b.x - a.x, b.y - a.y, x - a.x, y - a.y) < -EPS then return false end
    end
    return true
end
local function distanceSq(x, y, a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    local t = math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / math.max(EPS, dx * dx + dy * dy)))
    return (x - a.x - dx * t)^2 + (y - a.y - dy * t)^2
end
local function intersection(a, b, c, d)
    local dx, dy, ex, ey = b.x - a.x, b.y - a.y, d.x - c.x, d.y - c.y
    local det = cross(dx, dy, ex, ey)
    if math.abs(det) < EPS then return nil end
    local t = cross(c.x - a.x, c.y - a.y, ex, ey) / det
    local u = cross(c.x - a.x, c.y - a.y, dx, dy) / det
    if t >= -EPS and t <= 1 + EPS and u >= -EPS and u <= 1 + EPS then return math.max(0, math.min(1, t)) end
end
local function segmentSq(a, b, c, d)
    if intersection(a, b, c, d) then return 0 end
    return math.min(distanceSq(a.x, a.y, c, d), distanceSq(b.x, b.y, c, d),
        distanceSq(c.x, c.y, a, b), distanceSq(d.x, d.y, a, b))
end
local function circleTouches(points, x, y, radius)
    if inside(points, x, y) then return true end
    for i, a in ipairs(points) do if distanceSq(x, y, a, points[i % #points + 1]) <= radius^2 + EPS then return true end end
    return false
end

function RoomLattice.New(config, Base)
    RoomLattice.__index = RoomLattice
    setmetatable(RoomLattice, { __index = Base })
    local self = setmetatable({}, RoomLattice)
    self:Init(config)
    return self
end
function RoomLattice:Init(config)
    self.config, self.regions, self.obstacles, self.edges = config, {}, {}, {}
    self.locked, self.room_regions, self.locked_regions, self.gate_regions = {}, {}, {}, {}
    self.revision, self.los_cache, self.grids, self.fields, self.field_order = 0, {}, {}, {}, {}
    self.origin_x, self.origin_y = config.map_origin.x, config.map_origin.y
    self.width, self.height, self.grid_step, self.portal_radius = config.map_size.w, config.map_size.h, 1, config.player.radius
    self.polygons, self.roomsById, self.neighbors = {}, {}, {}
    local unit, graph = config.polygon_unit, config.topology
    for _, room in ipairs(graph.rooms) do
        local points = Lattice.Vertices(room)
        local region = { id = room.id, points = points, x1 = math.huge, y1 = math.huge, x2 = -math.huge, y2 = -math.huge }
        for _, p in ipairs(points) do
            p.x, p.y = p.x * unit, p.y * unit
            region.x1, region.y1 = math.min(region.x1, p.x), math.min(region.y1, p.y)
            region.x2, region.y2 = math.max(region.x2, p.x), math.max(region.y2, p.y)
        end
        self.roomsById[room.id], self.room_regions[room.id] = room, region
        self.neighbors[room.id] = {}
        points.room_ids = {room.id}
        self.regions[#self.regions + 1], self.polygons[#self.polygons + 1] = region, points
    end
    self.room_regions.hall = self.room_regions[graph.main]
    for _, def in ipairs(config.rooms) do
        self.locked[def.id] = def.prerequisite ~= nil
        self.locked_regions[def.id] = { self.room_regions[def.id] }
    end
    for _, link in ipairs(graph.links) do
        local corridor = Lattice.Corridor(graph.byId[link.a], link.aPort, graph.byId[link.b], link.bPort, link.length)
        local dx, dy = corridor.x2 - corridor.x1, corridor.y2 - corridor.y1
        local len = math.sqrt(dx^2 + dy^2)
        local nx, ny = -dy / len * unit, dx / len * unit
        -- 极小重叠消除浮点缝隙，不改变门的设计宽度。
        local ax, ay = corridor.x1 * unit - dx / len * EPS, corridor.y1 * unit - dy / len * EPS
        local bx, by = corridor.x2 * unit + dx / len * EPS, corridor.y2 * unit + dy / len * EPS
        self.polygons[#self.polygons + 1] = { { x = ax - nx, y = ay - ny }, { x = bx - nx, y = by - ny },
            { x = bx + nx, y = by + ny }, { x = ax + nx, y = ay + ny } }
        self.polygons[#self.polygons].room_ids = {link.a,link.b}
        self.neighbors[link.a][#self.neighbors[link.a] + 1] = link.b
        self.neighbors[link.b][#self.neighbors[link.b] + 1] = link.a
        if link.gate then
            local gateId = "gate_" .. link.id
            -- 门垂直横断走廊中心；与房间先后解锁分开维护。
            local cx, cy, tx, ty = (ax + bx) / 2, (ay + by) / 2, dx / len * 0.15, dy / len * 0.15
            local gate = { id = gateId, points = { { x = cx - tx - nx, y = cy - ty - ny }, { x = cx + tx - nx, y = cy + ty - ny },
                { x = cx + tx + nx, y = cy + ty + ny }, { x = cx - tx + nx, y = cy - ty + ny } } }
            self.locked[gateId], self.locked_regions[gateId], self.gate_regions[gateId] = true, { gate }, gate
        end
    end
    self.polygonBounds = {}
    for _, points in ipairs(self.polygons) do
        local bound = { points = points, x1 = math.huge, y1 = math.huge, x2 = -math.huge, y2 = -math.huge }
        for _, p in ipairs(points) do
            bound.x1, bound.y1 = math.min(bound.x1,p.x), math.min(bound.y1,p.y)
            bound.x2, bound.y2 = math.max(bound.x2,p.x), math.max(bound.y2,p.y)
        end
        self.polygonBounds[#self.polygonBounds+1] = bound
    end
    self.polygonIndex = Index.New(self.polygonBounds)
    -- 仅检查相交包围盒，不在初始化时对整图多边形两两切边。
    for index, points in ipairs(self.polygons) do
        for i, a in ipairs(points) do
            local b, ts = points[i % #points + 1], { 0, 1 }
            local candidates = self.polygonIndex:Query(math.min(a.x,b.x)-EPS,math.min(a.y,b.y)-EPS,
                math.max(a.x,b.x)+EPS,math.max(a.y,b.y)+EPS)
            for _, candidate in ipairs(candidates) do
                local other = candidate.points
                if points ~= other then
                    for k, c in ipairs(other) do
                        local t = intersection(a, b, c, other[k % #other + 1])
                        if t then ts[#ts + 1] = t end
                    end
                end
            end
            table.sort(ts)
            for k = 2, #ts do
                local lo, hi = ts[k - 1], ts[k]
                if hi - lo > EPS then
                    local mid, hidden = (lo + hi) / 2, false
                    local x, y = a.x + (b.x - a.x) * mid, a.y + (b.y - a.y) * mid
                    -- 向外微移；接缝恰在另一多边形边上也能稳定归类。
                    local ex, ey = b.x - a.x, b.y - a.y
                    local len = math.sqrt(ex^2 + ey^2)
                    for _, candidate in ipairs(candidates) do
                        local other = candidate.points
                        if points ~= other and inside(other, x + ey / len * EPS * 8, y - ex / len * EPS * 8) then hidden = true; break end
                    end
                    if not hidden then self.edges[#self.edges + 1] = {
                        ax = a.x + (b.x - a.x) * lo, ay = a.y + (b.y - a.y) * lo,
                        bx = a.x + (b.x - a.x) * hi, by = a.y + (b.y - a.y) * hi } end
                end
            end
        end
    end
    for _, e in ipairs(self.edges) do
        e.x1,e.y1,e.x2,e.y2 = math.min(e.ax,e.bx),math.min(e.ay,e.by),math.max(e.ax,e.bx),math.max(e.ay,e.by)
    end
    self.edgeIndex = Index.New(self.edges)
    local locks = {}
    for id, regions in pairs(self.locked_regions) do
        for _, region in ipairs(regions) do
            local b = { id=id,points=region.points,x1=math.huge,y1=math.huge,x2=-math.huge,y2=-math.huge }
            for _,p in ipairs(b.points) do
                b.x1,b.y1,b.x2,b.y2=math.min(b.x1,p.x),math.min(b.y1,p.y),math.max(b.x2,p.x),math.max(b.y2,p.y)
            end
            locks[#locks+1]=b
        end
    end
    self.lockIndex = Index.New(locks)
    self.roomIndex = Index.New(self.regions)
    self.roomDefs = {}; for _, def in ipairs(config.rooms) do self.roomDefs[def.id]=def end
    self.pathLinks, self.pathRevision = {}, -1
    return self
end

function RoomLattice:IsWalkable(x, y, radius)
    radius = radius or 0
    if not finite(x) or not finite(y) or not finite(radius) or radius < 0 then return false end
    local covered = false
    for _, bound in ipairs(self.polygonIndex:Query(x,y,x,y)) do if inside(bound.points, x, y) then covered = true; break end end
    if not covered then return false end
    for _, region in ipairs(self.lockIndex:Query(x-radius,y-radius,x+radius,y+radius)) do
        if self.locked[region.id] then
            if circleTouches(region.points, x, y, radius) then return false end
        end
    end
    if radius > 0 then
        for _, e in ipairs(self.edgeIndex:Query(x-radius,y-radius,x+radius,y+radius)) do
            if distanceSq(x, y, { x = e.ax, y = e.ay }, { x = e.bx, y = e.by }) < radius^2 - EPS then return false end
        end
    end
    return true
end
function RoomLattice:LineOfSight(x1, y1, x2, y2, radius)
    radius = radius or 0
    if not self:IsWalkable(x1, y1, radius) or not self:IsWalkable(x2, y2, radius) then return false end
    local a, b = { x = x1, y = y1 }, { x = x2, y = y2 }
    local ax,ay,bx,by=math.min(x1,x2)-radius,math.min(y1,y2)-radius,math.max(x1,x2)+radius,math.max(y1,y2)+radius
    for _, e in ipairs(self.edgeIndex:Query(ax,ay,bx,by)) do
        if segmentSq(a, b, { x = e.ax, y = e.ay }, { x = e.bx, y = e.by }) < math.max(EPS, radius^2 - EPS) then return false end
    end
    for _, region in ipairs(self.lockIndex:Query(ax,ay,bx,by)) do
        if self.locked[region.id] then
            for i, p in ipairs(region.points) do
                if segmentSq(a, b, p, region.points[i % #region.points + 1]) <= radius^2 + EPS then return false end
            end
        end
    end
    return true
end
function RoomLattice:IsInRegion(id, x, y)
    local region = self.room_regions[id] --[[@as table?]]
    return region ~= nil and finite(x) and finite(y) and inside(region.points, x, y)
end
function RoomLattice:RoomAt(x, y)
    if not finite(x) or not finite(y) then return nil end
    for _, region in ipairs(self.roomIndex:Query(x,y,x,y)) do
        if self.roomDefs[region.id] and inside(region.points,x,y) then return region.id end
    end
    return nil
end
function RoomLattice:ResidentRoom(x,y)
    local best,distance=nil,math.huge
    for _,b in ipairs(self.polygonIndex:Query(x,y,x,y)) do
        if inside(b.points,x,y) then
            for _,id in ipairs(b.points.room_ids) do
                local room=self.config.topology.byId[id]
                local d=(room.x*self.config.polygon_unit-x)^2+(room.y*self.config.polygon_unit-y)^2
                if d<distance then best,distance=id,d end
            end
        end
    end
    return best or self.config.topology.main
end
function RoomLattice:Path(x1, y1, x2, y2, radius)
    radius = radius or 0
    if not self:IsWalkable(x1, y1, radius) or not self:IsWalkable(x2, y2, radius) then return nil end
    if self:LineOfSight(x1, y1, x2, y2, radius) then return { { x = x1, y = y1 }, { x = x2, y = y2 } } end
    local graph, unit, queue, previous = self.config.topology, self.config.polygon_unit, {}, {}
    local function anchors(x,y)
        local result,seen={},{}
        for _,b in ipairs(self.polygonIndex:Query(x,y,x,y)) do
            if inside(b.points,x,y) then
                for _,id in ipairs(b.points.room_ids) do
                    local room=graph.byId[id]
                    if not seen[id] and self:LineOfSight(x,y,room.x*unit,room.y*unit,radius) then
                        result[#result+1]=id; seen[id]=true
                    end
                end
            end
        end
        return result
    end
    local goals={}; for _,id in ipairs(anchors(x2,y2)) do goals[id]=true end
    for _,id in ipairs(anchors(x1,y1)) do queue[#queue+1]=id; previous[id]=false end
    if self.pathRevision ~= self.revision then self.pathLinks,self.pathRevision={},self.revision end
    local function traversable(id,nextId)
        local key=id < nextId and id..':'..nextId or nextId..':'..id
        key=key..':'..radius
        local cached=self.pathLinks[key]
        if cached ~= nil then return cached end
        local a,b=graph.byId[id],graph.byId[nextId]
        local ok=self:LineOfSight(a.x*unit,a.y*unit,b.x*unit,b.y*unit,radius)
        self.pathLinks[key]=ok
        return ok
    end
    local cursor, found = 1, nil
    while cursor <= #queue do
        local id = queue[cursor]; cursor = cursor + 1
        local room = graph.byId[id]
        if goals[id] then found = id; break end
        for _, nextId in ipairs(self.neighbors[id]) do
            local nextRoom = graph.byId[nextId]
            if previous[nextId] == nil and traversable(id,nextId) then
                previous[nextId], queue[#queue + 1] = id, nextId
            end
        end
    end
    if not found then return nil end
    local result = { { x = x2, y = y2 } }
    while found do
        local room = graph.byId[found]
        table.insert(result, 1, { x = room.x * unit, y = room.y * unit })
        found = previous[found]
    end
    table.insert(result, 1, { x = x1, y = y1 })
    return result
end
function RoomLattice:PrepareWave() end
function RoomLattice:Warmup() end
return RoomLattice
