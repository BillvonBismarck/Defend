--- ============================================================================
--- 地图变体系统 - 不同视觉风格 + 装饰元素 + 障碍物
--- ============================================================================

local Config = require("Config")

local MapVariant = {}

-- ============================================================================
-- 地图变体定义
-- ============================================================================
MapVariant.VARIANTS = {
    -- 1) 默认赛博朋克（原版）
    {
        id       = "cyber",
        name     = "赛博废墟",
        icon     = "🌃",
        bgColor  = { 10, 8, 25, 255 },
        gridColor = { 30, 20, 60, 80 },
        gridSize = 80,
        borderColor = { 180, 50, 255, 120 },
        -- 散布装饰 emoji（纯视觉）
        decors = {
            { emoji = "💾", chance = 0.3, sizeMin = 14, sizeMax = 22 },
            { emoji = "⚙️", chance = 0.25, sizeMin = 12, sizeMax = 18 },
            { emoji = "🔌", chance = 0.2, sizeMin = 10, sizeMax = 16 },
        },
        decorCount = 40,
        -- 障碍物模板
        obstacles = {
            { emoji = "🖥️", radius = 30, count = 6, name = "废弃终端" },
            { emoji = "📡", radius = 25, count = 4, name = "信号塔" },
        },
        -- 普通敌怪 emoji 组（此地图专属）
        normalEnemyEmoji = {
            normal  = { "🤖", "👾", "💀", "🦾" },
            fast    = { "⚡", "🔋", "💿", "📟" },
            tank    = { "🛡️", "🔩", "🪝", "🔧" },
            swarm   = { "🐜", "⚙️", "🔌", "💾" },
            charger = { "🚀", "🔴", "⬛" },
            ghost   = { "👻", "🫥", "📡" },
            shaman  = { "🤖", "🔮", "📺" },
            ranger  = { "🎯", "🔫", "📡" },
            elite   = { "🦾", "👿", "🤖", "🛸" },
        },
    },
    -- 2) 草地森林
    {
        id       = "grass",
        name     = "翡翠草原",
        icon     = "🌿",
        bgColor  = { 15, 30, 12, 255 },
        gridColor = { 30, 50, 25, 60 },
        gridSize = 90,
        borderColor = { 60, 200, 80, 120 },
        decors = {
            { emoji = "🌸", chance = 0.35, sizeMin = 12, sizeMax = 20 },
            { emoji = "🌻", chance = 0.25, sizeMin = 14, sizeMax = 22 },
            { emoji = "🍄", chance = 0.2, sizeMin = 10, sizeMax = 16 },
            { emoji = "🦋", chance = 0.15, sizeMin = 8, sizeMax = 14 },
        },
        decorCount = 50,
        obstacles = {
            { emoji = "🌳", radius = 35, count = 8, name = "大树" },
            { emoji = "🪨", radius = 28, count = 5, name = "岩石" },
        },
        -- 普通敌怪 emoji 组
        normalEnemyEmoji = {
            normal  = { "🐺", "🐗", "🦊", "🐻" },
            fast    = { "🐍", "🦅", "🐆", "🦌" },
            tank    = { "🦍", "🐘", "🦛", "🐂" },
            swarm   = { "🐛", "🪲", "🦟", "🐝" },
            charger = { "🦏", "🐗", "🦬" },
            ghost   = { "🦋", "🕊️", "🌫️" },
            shaman  = { "🧙", "🌿", "🍄" },
            ranger  = { "🏹", "🦅", "🎯" },
            elite   = { "🐉", "🦁", "🐯", "👹" },
        },
    },
    -- 3) 地下洞穴
    {
        id       = "cave",
        name     = "幽暗洞穴",
        icon     = "🦇",
        bgColor  = { 8, 6, 14, 255 },
        gridColor = { 20, 15, 35, 50 },
        gridSize = 70,
        borderColor = { 120, 80, 40, 120 },
        decors = {
            { emoji = "💎", chance = 0.3, sizeMin = 10, sizeMax = 18 },
            { emoji = "🕯️", chance = 0.25, sizeMin = 12, sizeMax = 16 },
            { emoji = "🦇", chance = 0.2, sizeMin = 8, sizeMax = 14 },
            { emoji = "🕸️", chance = 0.15, sizeMin = 14, sizeMax = 22 },
        },
        decorCount = 35,
        obstacles = {
            { emoji = "🗿", radius = 32, count = 7, name = "石柱" },
            { emoji = "⛏️", radius = 22, count = 4, name = "矿车" },
        },
        -- 普通敌怪 emoji 组
        normalEnemyEmoji = {
            normal  = { "🕷️", "🦇", "💀", "☠️" },
            fast    = { "🦇", "🕷️", "🐍", "🪲" },
            tank    = { "🪨", "🦟", "🐌", "🦀" },
            swarm   = { "🕷️", "🦟", "🪲", "🐛" },
            charger = { "🦀", "🐌", "🦟" },
            ghost   = { "💀", "🫥", "🕸️" },
            shaman  = { "☠️", "🔮", "🕷️" },
            ranger  = { "🕷️", "🎯", "🦇" },
            elite   = { "👹", "🕷️", "😈", "💀" },
        },
    },
    -- 4) 浮空岛
    {
        id       = "sky",
        name     = "天空浮岛",
        icon     = "☁️",
        bgColor  = { 12, 18, 35, 255 },
        gridColor = { 25, 35, 60, 50 },
        gridSize = 100,
        borderColor = { 100, 180, 255, 120 },
        decors = {
            { emoji = "☁️", chance = 0.35, sizeMin = 18, sizeMax = 30 },
            { emoji = "⭐", chance = 0.25, sizeMin = 8, sizeMax = 14 },
            { emoji = "🌙", chance = 0.15, sizeMin = 14, sizeMax = 20 },
            { emoji = "🪽", chance = 0.1, sizeMin = 10, sizeMax = 16 },
        },
        decorCount = 45,
        obstacles = {
            { emoji = "🏔️", radius = 38, count = 5, name = "浮岩" },
            { emoji = "🌀", radius = 26, count = 4, name = "气旋" },
        },
        -- 普通敌怪 emoji 组
        normalEnemyEmoji = {
            normal  = { "🦅", "🦆", "🦜", "🦉" },
            fast    = { "🦅", "🦩", "🕊️", "🪽" },
            tank    = { "🦢", "🦚", "🦜", "🦃" },
            swarm   = { "🕊️", "🦟", "🪲", "🦋" },
            charger = { "🦅", "🦢", "🪽" },
            ghost   = { "☁️", "🌫️", "🪽" },
            shaman  = { "🦉", "🔮", "⭐" },
            ranger  = { "🦅", "🎯", "🌙" },
            elite   = { "🐉", "🦅", "😈", "⭐" },
        },
    },
}

-- ============================================================================
-- 运行时状态
-- ============================================================================
MapVariant.active = nil        -- 当前激活的变体定义
MapVariant.decorInstances = {} -- { {x, y, emoji, size} ... }
MapVariant.obstacleList = {}   -- { {x, y, radius, emoji, name} ... }

--- 用种子随机数生成器（确保每局一致）
local function seededRandom(seed, idx)
    local v = math.sin(seed * 12.9898 + idx * 78.233) * 43758.5453
    return v - math.floor(v)
end

--- 初始化地图变体（在 BattleScene.Init 中调用）
---@param variantId string|nil 指定变体 ID，nil 则随机选择
---@param seed number|nil 随机种子
function MapVariant.Init(variantId, seed)
    seed = seed or (os.time() + math.random(9999))
    math.randomseed(seed)

    -- 选择变体
    if variantId then
        for _, v in ipairs(MapVariant.VARIANTS) do
            if v.id == variantId then
                MapVariant.active = v
                break
            end
        end
    end
    if not MapVariant.active then
        local idx = math.random(1, #MapVariant.VARIANTS)
        MapVariant.active = MapVariant.VARIANTS[idx]
    end

    local v = MapVariant.active
    local ws = Config.WORLD_SIZE
    local margin = 200  -- 距世界边缘最小距离

    -- 生成装饰实例
    MapVariant.decorInstances = {}
    if v.decors and v.decorCount then
        for i = 1, v.decorCount do
            -- 依概率选择装饰类型
            local roll = seededRandom(seed, i * 7 + 1)
            local cumChance = 0
            local chosenDecor = v.decors[1]
            for _, d in ipairs(v.decors) do
                cumChance = cumChance + d.chance
                if roll <= cumChance then
                    chosenDecor = d
                    break
                end
            end
            local dx = margin + seededRandom(seed, i * 3 + 100) * (ws - margin * 2)
            local dy = margin + seededRandom(seed, i * 5 + 200) * (ws - margin * 2)
            local sz = chosenDecor.sizeMin + seededRandom(seed, i * 11 + 300) * (chosenDecor.sizeMax - chosenDecor.sizeMin)
            MapVariant.decorInstances[#MapVariant.decorInstances + 1] = {
                x = dx, y = dy,
                emoji = chosenDecor.emoji,
                size = math.floor(sz),
            }
        end
    end

    -- 生成障碍物实例（确保不与玩家初始位置重叠）
    MapVariant.obstacleList = {}
    if v.obstacles then
        local playerStartX = ws / 2
        local playerStartY = ws / 2
        local safeRadius = 300  -- 玩家出生点安全区

        local obIdx = 0
        for _, obsDef in ipairs(v.obstacles) do
            for c = 1, obsDef.count do
                obIdx = obIdx + 1
                local attempts = 0
                local ox, oy
                repeat
                    attempts = attempts + 1
                    ox = margin + seededRandom(seed, obIdx * 17 + attempts * 31 + 500) * (ws - margin * 2)
                    oy = margin + seededRandom(seed, obIdx * 23 + attempts * 37 + 600) * (ws - margin * 2)
                    -- 检查是否在玩家安全区
                    local pdx = ox - playerStartX
                    local pdy = oy - playerStartY
                    local pDist = math.sqrt(pdx * pdx + pdy * pdy)
                    -- 检查是否与其他障碍物重叠
                    local overlap = false
                    for _, existing in ipairs(MapVariant.obstacleList) do
                        local edx = ox - existing.x
                        local edy = oy - existing.y
                        if math.sqrt(edx * edx + edy * edy) < obsDef.radius + existing.radius + 60 then
                            overlap = true
                            break
                        end
                    end
                    if pDist > safeRadius and not overlap then break end
                until attempts >= 20
                -- 即使 20 次都没找到好位置，也放上去（但一般不会）
                MapVariant.obstacleList[#MapVariant.obstacleList + 1] = {
                    x = ox, y = oy,
                    radius = obsDef.radius,
                    emoji = obsDef.emoji,
                    name = obsDef.name,
                }
            end
        end
    end

    print("[MapVariant] Activated: " .. v.name .. " (" .. v.id .. ") with "
        .. #MapVariant.decorInstances .. " decors, "
        .. #MapVariant.obstacleList .. " obstacles")
end

--- 重置
function MapVariant.Reset()
    MapVariant.active = nil
    MapVariant.decorInstances = {}
    MapVariant.obstacleList = {}
end

-- ============================================================================
-- 碰撞检测：推离障碍物
-- ============================================================================

--- 将实体从障碍物推离（用于 Player 和 Enemy 移动后调用）
---@param x number 当前 X
---@param y number 当前 Y
---@param entityRadius number 实体半径
---@return number, number 推离后的新坐标
function MapVariant.ResolveCollision(x, y, entityRadius)
    for _, obs in ipairs(MapVariant.obstacleList) do
        local dx = x - obs.x
        local dy = y - obs.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local minDist = obs.radius + entityRadius
        if dist < minDist and dist > 0.01 then
            -- 推离到刚好不重叠的位置
            local pushDist = minDist - dist
            local nx = dx / dist
            local ny = dy / dist
            x = x + nx * pushDist
            y = y + ny * pushDist
        elseif dist <= 0.01 then
            -- 完全重叠，向随机方向推出
            x = x + minDist
        end
    end
    return x, y
end

--- 检查一个点是否在任何障碍物内
---@param x number
---@param y number
---@param checkRadius number
---@return boolean
function MapVariant.IsInsideObstacle(x, y, checkRadius)
    for _, obs in ipairs(MapVariant.obstacleList) do
        local dx = x - obs.x
        local dy = y - obs.y
        if dx * dx + dy * dy < (obs.radius + checkRadius) * (obs.radius + checkRadius) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- 渲染
-- ============================================================================

--- 渲染地图背景（替代原 RenderBackground）
---@param vg userdata NanoVG context
---@param viewW number 视口宽
---@param viewH number 视口高
---@param camX number 摄像机 X
---@param camY number 摄像机 Y
function MapVariant.RenderBackground(vg, viewW, viewH, camX, camY)
    local v = MapVariant.active
    if not v then
        -- fallback: 用默认赛博朋克
        v = MapVariant.VARIANTS[1]
    end

    -- 填充背景
    local bg = v.bgColor
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], bg[4]))
    nvgFill(vg)

    -- 网格线
    local gridSize = v.gridSize or 80
    local offsetX = -(camX % gridSize)
    local offsetY = -(camY % gridSize)
    local gc = v.gridColor
    nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], gc[4]))
    nvgStrokeWidth(vg, 1)

    for gx = offsetX, viewW, gridSize do
        nvgBeginPath(vg)
        nvgMoveTo(vg, gx, 0)
        nvgLineTo(vg, gx, viewH)
        nvgStroke(vg)
    end
    for gy = offsetY, viewH, gridSize do
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, gy)
        nvgLineTo(vg, viewW, gy)
        nvgStroke(vg)
    end

    -- 世界边界线
    local bc = v.borderColor
    nvgStrokeColor(vg, nvgRGBA(bc[1], bc[2], bc[3], bc[4]))
    nvgStrokeWidth(vg, 2)
    local worldLeft = -camX
    local worldTop = -camY
    nvgBeginPath(vg)
    nvgRect(vg, worldLeft, worldTop, Config.WORLD_SIZE, Config.WORLD_SIZE)
    nvgStroke(vg)

    -- 装饰 emoji（只渲染视口内的）
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for _, dec in ipairs(MapVariant.decorInstances) do
        local sx = dec.x - camX
        local sy = dec.y - camY
        if sx > -40 and sx < viewW + 40 and sy > -40 and sy < viewH + 40 then
            nvgFontSize(vg, dec.size)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 35))
            nvgText(vg, sx, sy, dec.emoji)
        end
    end
end

--- 渲染障碍物（在敌人层之下）
---@param vg userdata NanoVG context
---@param camX number
---@param camY number
---@param viewW number
---@param viewH number
---@param totalTime number
function MapVariant.RenderObstacles(vg, camX, camY, viewW, viewH, totalTime)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for _, obs in ipairs(MapVariant.obstacleList) do
        local sx = obs.x - camX
        local sy = obs.y - camY
        if sx > -60 and sx < viewW + 60 and sy > -60 and sy < viewH + 60 then
            -- 障碍物阴影
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy + 4, obs.radius * 0.9)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
            nvgFill(vg)

            -- 障碍物底座（半透明圆）
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, obs.radius)
            nvgFillColor(vg, nvgRGBA(60, 50, 80, 80))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(120, 100, 160, 60))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            -- 障碍物 emoji
            local bobY = math.sin((totalTime or 0) * 1.5 + obs.x * 0.01) * 2
            nvgFontSize(vg, obs.radius * 1.2)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgText(vg, sx, sy + bobY, obs.emoji)
        end
    end
end

--- 获取当前变体信息（供 HUD / 成就使用）
---@return table|nil
function MapVariant.GetActive()
    return MapVariant.active
end

--- 获取变体列表（供图鉴使用）
---@return table
function MapVariant.GetAllVariants()
    return MapVariant.VARIANTS
end

-- ============================================================================
-- 敌怪 emoji 查询 API
-- ============================================================================

--- 获取当前地图指定敌人类型的 emoji 列表
--- 若无对应配置则返回 nil（调用方回退到 Config.ENEMY_EMOJI）
---@param typeName string 敌人类型名
---@return table|nil
function MapVariant.GetEnemyEmojiList(typeName)
    if MapVariant.active and MapVariant.active.normalEnemyEmoji then
        return MapVariant.active.normalEnemyEmoji[typeName]
    end
    return nil
end

return MapVariant
