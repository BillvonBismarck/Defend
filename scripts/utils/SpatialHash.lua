--- ============================================================================
--- 空间哈希网格 - 碰撞检测加速
--- 将实体按位置分配到网格单元，查询时只检查相邻单元
--- ============================================================================

local SpatialHash = {}
SpatialHash.__index = SpatialHash

--- 创建空间哈希
---@param cellSize number 网格单元大小（像素）
---@return table
function SpatialHash.New(cellSize)
    local self = setmetatable({}, SpatialHash)
    self.cellSize = cellSize or 200
    self.invCell = 1.0 / self.cellSize
    self.cells = {}
    return self
end

--- 清空所有单元
function SpatialHash:Clear()
    -- 复用 table 减少 GC，只清空内容
    for k, cell in pairs(self.cells) do
        for i = #cell, 1, -1 do
            cell[i] = nil
        end
    end
end

--- 计算 cell key
---@param x number
---@param y number
---@return number
local function cellKey(x, y, invCell)
    local cx = math.floor(x * invCell)
    local cy = math.floor(y * invCell)
    -- 使用 Cantor pairing 避免冲突
    return cx * 73856093 + cy * 19349663
end

--- 插入实体
---@param entity table 需要有 x, y 字段
function SpatialHash:Insert(entity)
    local key = cellKey(entity.x, entity.y, self.invCell)
    local cell = self.cells[key]
    if not cell then
        cell = {}
        self.cells[key] = cell
    end
    cell[#cell + 1] = entity
end

--- 批量插入（从数组）
---@param entities table[] 实体数组，每个需有 x, y, alive 字段
function SpatialHash:InsertAll(entities)
    local inv = self.invCell
    local cells = self.cells
    for i = 1, #entities do
        local e = entities[i]
        if e.alive then
            local key = cellKey(e.x, e.y, inv)
            local cell = cells[key]
            if not cell then
                cell = {}
                cells[key] = cell
            end
            cell[#cell + 1] = e
        end
    end
end

--- 查询以 (x,y) 为中心、半径 r 范围内可能存在的实体
--- 返回迭代器（避免分配临时 table）
---@param x number 查询中心 x
---@param y number 查询中心 y
---@param r number 查询半径
---@param callback fun(entity: table) 回调每个候选实体
function SpatialHash:Query(x, y, r, callback)
    local inv = self.invCell
    local minCx = math.floor((x - r) * inv)
    local maxCx = math.floor((x + r) * inv)
    local minCy = math.floor((y - r) * inv)
    local maxCy = math.floor((y + r) * inv)
    local cells = self.cells

    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            local key = cx * 73856093 + cy * 19349663
            local cell = cells[key]
            if cell then
                for i = 1, #cell do
                    callback(cell[i])
                end
            end
        end
    end
end

--- 查询以 (x,y) 为中心、半径 r 范围内可能存在的实体（收集到 table）
---@param x number
---@param y number
---@param r number
---@param result table 结果输出到此表（会 append）
function SpatialHash:QueryInto(x, y, r, result)
    local inv = self.invCell
    local minCx = math.floor((x - r) * inv)
    local maxCx = math.floor((x + r) * inv)
    local minCy = math.floor((y - r) * inv)
    local maxCy = math.floor((y + r) * inv)
    local cells = self.cells

    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            local key = cx * 73856093 + cy * 19349663
            local cell = cells[key]
            if cell then
                for i = 1, #cell do
                    result[#result + 1] = cell[i]
                end
            end
        end
    end
end

return SpatialHash
