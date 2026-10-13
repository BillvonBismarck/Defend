-- 静态几何宽阶段：局部查询不随全图房间数线性增长；精确碰撞仍由 RoomLattice 判定。
---@class DefenseRoomIndex
---@field cells table<string, table[]>
---@field size number
local Index = {}
Index.__index = Index
function Index.New(items, size)
    local self = setmetatable({ cells = {}, size = size or 24 }, Index)
    for _, item in ipairs(items) do
        for x = math.floor(item.x1 / self.size), math.floor(item.x2 / self.size) do
            for y = math.floor(item.y1 / self.size), math.floor(item.y2 / self.size) do
                local key = x .. ':' .. y
                self.cells[key] = self.cells[key] or {}
                self.cells[key][#self.cells[key]+1] = item
            end
        end
    end
    return self
end
function Index:Query(x1, y1, x2, y2)
    local result, seen = {}, {}
    for x = math.floor(x1 / self.size), math.floor(x2 / self.size) do
        for y = math.floor(y1 / self.size), math.floor(y2 / self.size) do
            for _, item in ipairs(self.cells[x .. ':' .. y] or {}) do
                if not seen[item] and item.x1 <= x2 and item.x2 >= x1 and item.y1 <= y2 and item.y2 >= y1 then
                    seen[item] = true; result[#result+1] = item
                end
            end
        end
    end
    return result
end
return Index
