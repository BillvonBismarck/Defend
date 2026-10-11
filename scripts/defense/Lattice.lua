-- 多边形房间几何内核（定稿：三角 10u / 六边 6u / 十二边 4u）。
-- 纯 Lua 规则层：只做几何、端口、走廊与契约校验，不引用引擎/渲染/UI/文件。
-- 定稿口径见《多边形房间地图与炮塔重设计 v2.0》§1；面积比 1 : 2.16 : 4.00，边长不可变。
local Lattice = {}

Lattice.Version = "polygon-lattice-v1"
Lattice.Unit = 1                   -- u：单位三角边长（世界缩放由场景决定）
Lattice.OddDirections = { 30, 90, 150, 210, 270, 330 }   -- 走廊轴允许的 6 个方向
Lattice.CorridorWidth = 2          -- w = 2u
Lattice.CorridorMin = 2            -- L 下限（= 2u）
Lattice.CorridorMax = 4            -- L 上限（= 4u）
Lattice.PreferredCorridor = 3      -- 优先长度
Lattice.MinGap = 0.5               -- 房间最小间距
Lattice.DodecagonCellTarget = 400  -- 十二边阶梯取整目标（单位三角数）

---@class LatticeRoomSpec
---@field kind string
---@field name string
---@field sides integer
---@field edge number       -- 边长（u）
---@field ports integer      -- 可开走廊的边数
---@field slots integer      -- 炮塔槽位数
---@field slot_kind string   -- "center" | "edge"
---@field area number        -- 面积（单位三角）
Lattice.Catalog = {
    tri = { kind = "tri", name = "三角房", sides = 3, edge = 10, ports = 3, slots = 1,
        slot_kind = "center", area = 100 },
    hex = { kind = "hex", name = "六边房", sides = 6, edge = 6, ports = 6, slots = 3,
        slot_kind = "edge", area = 216 },
    dodeca = { kind = "dodeca", name = "十二边房", sides = 12, edge = 4, ports = 6, slots = 12,
        slot_kind = "edge", area = 400 },
}
Lattice.Kinds = { "tri", "hex", "dodeca" }

-- 朝向类别：端口法线必须落在 6 个奇数方向上，否则房间无法接走廊。
-- 端口法线 = 边的中点方向；三角 2 类（尖上/尖下），六边与十二边各 1 类。
local PORT_NORMALS = {
    tri = { { 30, 150, 270 }, { 90, 210, 330 } },
    hex = { { 30, 90, 150, 210, 270, 330 } },
    dodeca = { { 30, 90, 150, 210, 270, 330 } },
}

-- 顶点相位（度）：决定实际顶点角度，与端口法线表互为对偶。
local VERTEX_PHASE = {
    tri = { 90, 30 },
    hex = { 0 },
    dodeca = { 15 },
}

local function rad(deg) return deg * math.pi / 180 end

function Lattice.Norm(deg)
    local d = deg % 360
    if d < 0 then d = d + 360 end
    return d
end

---@return number 两个方向的最小夹角（度，0–180）
function Lattice.AngleGap(a, b)
    local d = math.abs(Lattice.Norm(a) - Lattice.Norm(b)) % 360
    if d > 180 then d = 360 - d end
    return d
end

function Lattice.IsOddDirection(deg)
    return Lattice.AngleGap(deg, 30) % 60 < 0.0001 or Lattice.AngleGap(deg, 90) % 60 < 0.0001
        or Lattice.AngleGap(deg, 150) % 60 < 0.0001 or Lattice.AngleGap(deg, 210) % 60 < 0.0001
        or Lattice.AngleGap(deg, 270) % 60 < 0.0001 or Lattice.AngleGap(deg, 330) % 60 < 0.0001
end

function Lattice.Spec(kind)
    local spec = Lattice.Catalog[kind]
    assert(spec, "未知房间类型:" .. tostring(kind))
    return spec
end

---@return number 内切圆半径（中心到边的中点）
function Lattice.Inradius(kind)
    local spec = Lattice.Spec(kind)
    return spec.edge / (2 * math.tan(math.pi / spec.sides))
end

---@return number 外接圆半径（中心到顶点）
function Lattice.Circumradius(kind)
    local spec = Lattice.Spec(kind)
    return spec.edge / (2 * math.sin(math.pi / spec.sides))
end

function Lattice.Perimeter(kind)
    local spec = Lattice.Spec(kind)
    return spec.edge * spec.sides
end

---@return integer 朝向类别数
function Lattice.RotationCount(kind)
    return #PORT_NORMALS[kind]
end

---@return table 该朝向下的端口法线（度，从正东逆时针）
function Lattice.PortNormals(kind, rotation)
    local list = PORT_NORMALS[kind]
    local index = ((rotation or 0) % #list) + 1
    return list[index]
end

---@return integer|nil 能正对 dir 的朝向类别
function Lattice.RotationFacing(kind, dir)
    for r = 0, Lattice.RotationCount(kind) - 1 do
        for _, normal in ipairs(Lattice.PortNormals(kind, r)) do
            if Lattice.AngleGap(normal, dir) < 0.0001 then return r end
        end
    end
    return nil
end

---@return integer|nil 该朝向下正对 dir 的端口序号
function Lattice.PortIndexFacing(room, dir)
    local normals = Lattice.PortNormals(room.kind, room.rotation)
    for i, normal in ipairs(normals) do
        if Lattice.AngleGap(normal, dir) < 0.0001 then return i end
    end
    return nil
end

---@return table 边中点坐标（端口锚点）
function Lattice.PortPoint(room, index)
    local normals = Lattice.PortNormals(room.kind, room.rotation)
    local dir = normals[index]
    assert(dir, "端口越界:" .. tostring(index))
    local r = Lattice.Inradius(room.kind)
    return room.x + r * math.cos(rad(dir)), room.y + r * math.sin(rad(dir))
end

---@return number 两房间中心距（连接时必须等于 r(A) + L + r(B)）
function Lattice.CenterDistance(kindA, kindB, length)
    return Lattice.Inradius(kindA) + length + Lattice.Inradius(kindB)
end

---@return number 合法走廊长度是否在 [2u,4u] 内
function Lattice.LegalCorridorLength(length)
    return type(length) == "number" and length >= Lattice.CorridorMin - 0.0001
        and length <= Lattice.CorridorMax + 0.0001
end

---@return table 顶点（世界坐标）
function Lattice.Vertices(room)
    local spec = Lattice.Spec(room.kind)
    local R = Lattice.Circumradius(room.kind)
    local phases = VERTEX_PHASE[room.kind]
    local base = phases[((room.rotation or 0) % #phases) + 1]
    local pts = {}
    for k = 0, spec.sides - 1 do
        local a = rad(base + 360 * k / spec.sides)
        pts[#pts + 1] = { x = room.x + R * math.cos(a), y = room.y + R * math.sin(a), deg = Lattice.Norm(base + 360 * k / spec.sides) }
    end
    return pts
end

---@return table 沿端口 dir 放置的新房间（不含碰撞判定）
function Lattice.Place(parent, portIndex, kind, length, id)
    assert(Lattice.LegalCorridorLength(length), "走廊长度越界:" .. tostring(length))
    local normals = Lattice.PortNormals(parent.kind, parent.rotation)
    local dir = normals[portIndex]
    assert(dir, "父房间端口无效:" .. tostring(portIndex))
    local back = Lattice.Norm(dir + 180)
    local rotation = Lattice.RotationFacing(kind, back)
    assert(rotation, "该类型无法正对方向:" .. tostring(back))
    local distance = Lattice.CenterDistance(parent.kind, kind, length)
    local room = {
        id = id, kind = kind, rotation = rotation,
        x = parent.x + distance * math.cos(rad(dir)),
        y = parent.y + distance * math.sin(rad(dir)),
    }
    return room, dir, back
end

---@return table 走廊矩形（中心线 + 宽度）
function Lattice.Corridor(a, aPort, b, bPort, length)
    local ax, ay = Lattice.PortPoint(a, aPort)
    local bx, by = Lattice.PortPoint(b, bPort)
    local d = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    return { x1 = ax, y1 = ay, x2 = bx, y2 = by, length = d, width = Lattice.CorridorWidth,
        a = a.id, b = b.id, expected = length }
end

-- 凸多边形分离轴（SAT）：房间互不重叠的精确判定。
local function project(points, ax, ay)
    local min, max
    for _, p in ipairs(points) do
        local v = p.x * ax + p.y * ay
        if not min or v < min then min = v end
        if not max or v > max then max = v end
    end
    return min, max
end

local function axesOf(points)
    local axes = {}
    for i = 1, #points do
        local a, b = points[i], points[(i % #points) + 1]
        local ex, ey = b.x - a.x, b.y - a.y
        local len = math.sqrt(ex * ex + ey * ey)
        if len > 0.000001 then axes[#axes + 1] = { x = -ey / len, y = ex / len } end
    end
    return axes
end

---@return boolean 两个凸多边形是否分离
function Lattice.PolygonsSeparated(pointsA, pointsB)
    for _, axis in ipairs(axesOf(pointsA)) do
        local amin, amax = project(pointsA, axis.x, axis.y)
        local bmin, bmax = project(pointsB, axis.x, axis.y)
        if amax < bmin or bmax < amin then return true end
    end
    for _, axis in ipairs(axesOf(pointsB)) do
        local amin, amax = project(pointsA, axis.x, axis.y)
        local bmin, bmax = project(pointsB, axis.x, axis.y)
        if amax < bmin or bmax < amin then return true end
    end
    return false
end

---@return boolean 两个房间是否重叠（含最小间距）
function Lattice.RoomsOverlap(a, b, gap)
    local margin = gap or Lattice.MinGap
    local dx, dy = b.x - a.x, b.y - a.y
    local need = Lattice.Inradius(a.kind) + Lattice.Inradius(b.kind) + margin
    if dx * dx + dy * dy > (Lattice.Circumradius(a.kind) + Lattice.Circumradius(b.kind) + margin) ^ 2 then
        return false          -- 外接圆都不相交，直接判不重叠
    end
    if dx * dx + dy * dy < need * need then return true end
    return not Lattice.PolygonsSeparated(Lattice.Vertices(a), Lattice.Vertices(b))
end

---@return boolean 走廊是否穿过不属于它两端的房间
function Lattice.CorridorHitsRoom(corridor, room, ownerA, ownerB)
    if room.id == ownerA or room.id == ownerB then return false end
    local cx, cy = (corridor.x1 + corridor.x2) / 2, (corridor.y1 + corridor.y2) / 2
    local dx, dy = room.x - cx, room.y - cy
    local half = corridor.length / 2 + Lattice.Circumradius(room.kind) + corridor.width / 2
    return dx * dx + dy * dy <= half * half
end

-- ---------------------------------------------------------------- 十二边阶梯几何
-- 三角网格只有 3 个方向，12 条边的房间无法格点精确；用单位三角求并把面积取整到 400。
local function latticePoint(i, j, u)
    return { x = i * u + j * u / 2, y = j * u * math.sqrt(3) / 2 }
end

local function insideDodecagon(x, y, R)
    local inradius = R * math.cos(math.pi / 12)
    for k = 0, 11 do
        local a = rad(15 + 30 * k + 15)
        if x * math.cos(a) + y * math.sin(a) > inradius + 0.0000001 then return false end
    end
    return true
end

---@return table 十二边房的阶梯格点：单位三角集合（面积取整到 DodecagonCellTarget）
function Lattice.DodecagonGeometry()
    local u = Lattice.Unit
    local R = Lattice.Circumradius("dodeca")
    -- 候选集略大于理想轮廓，再按中心距离取最近的 400 个，保证面积可精确取整。
    local span = math.ceil((R + 1.2) / (u * math.sqrt(3) / 2)) + 2
    local margin = R + 1.2
    local cells = {}
    for j = -span, span do
        for i = -span - 1, span + 1 do
            local up = { latticePoint(i, j, u), latticePoint(i + 1, j, u), latticePoint(i, j + 1, u) }
            local ux = (up[1].x + up[2].x + up[3].x) / 3
            local uy = (up[1].y + up[2].y + up[3].y) / 3
            if insideDodecagon(ux, uy, margin) then
                cells[#cells + 1] = { i = i, j = j, up = true, x = ux, y = uy, d = math.sqrt(ux * ux + uy * uy),
                    inner = insideDodecagon(ux, uy, R) }
            end
            local dn = { latticePoint(i + 1, j, u), latticePoint(i, j + 1, u), latticePoint(i + 1, j + 1, u) }
            local dx = (dn[1].x + dn[2].x + dn[3].x) / 3
            local dy = (dn[1].y + dn[2].y + dn[3].y) / 3
            if insideDodecagon(dx, dy, margin) then
                cells[#cells + 1] = { i = i, j = j, up = false, x = dx, y = dy, d = math.sqrt(dx * dx + dy * dy),
                    inner = insideDodecagon(dx, dy, R) }
            end
        end
    end
    table.sort(cells, function(p, q)
        if math.abs(p.d - q.d) > 0.000001 then return p.d < q.d end
        if p.j ~= q.j then return p.j > q.j end
        if p.i ~= q.i then return p.i < q.i end
        return (p.up and 1 or 0) < (q.up and 1 or 0)
    end)
    local raw = 0
    for _, cell in ipairs(cells) do
        if cell.inner then raw = raw + 1 end
    end
    local target = Lattice.DodecagonCellTarget
    local trimmed = {}
    for index = 1, target do trimmed[index] = cells[index] end
    return { cells = trimmed, raw = raw, candidate = #cells, target = target, area = #trimmed, u = u, R = R }
end

---@return number 十二边阶梯面积取整后的单位三角数
function Lattice.DodecagonArea()
    return Lattice.DodecagonGeometry().area
end

---@return table 契约校验：尺寸、面积、端口、槽位与朝向
function Lattice.Validate()
    local expect = {
        tri = { edge = 10, area = 100, ports = 3, slots = 1 },
        hex = { edge = 6, area = 216, ports = 6, slots = 3 },
        dodeca = { edge = 4, area = 400, ports = 6, slots = 12 },
    }
    for _, kind in ipairs(Lattice.Kinds) do
        local spec, want = Lattice.Spec(kind), expect[kind]
        assert(spec.edge == want.edge, kind .. " 边长与定稿不符")
        assert(spec.area == want.area, kind .. " 面积与定稿不符")
        assert(spec.ports == want.ports, kind .. " 端口数与定稿不符")
        assert(spec.slots == want.slots, kind .. " 槽位数与定稿不符")
        for rotation = 0, Lattice.RotationCount(kind) - 1 do
            local normals = Lattice.PortNormals(kind, rotation)
            assert(#normals == spec.ports, kind .. " 端口法线数量不符")
            for _, dir in ipairs(normals) do
                assert(Lattice.IsOddDirection(dir), kind .. " 端口方向必须落在奇数方向:" .. tostring(dir))
            end
        end
    end
    assert(Lattice.RotationFacing("tri", 270) == 0, "三角房朝向类别判定错误")
    assert(Lattice.RotationFacing("tri", 90) == 1, "三角房朝向类别判定错误")
    local geometry = Lattice.DodecagonGeometry()
    assert(geometry.area == Lattice.DodecagonCellTarget, "十二边阶梯取整失败")
    return true, geometry
end

return Lattice
