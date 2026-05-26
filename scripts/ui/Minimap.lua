--- ============================================================================
--- 像素网格小地图 - 右下角显示世界全景
--- 显示：世界边界、玩家位置、Boss位置、相机视野
--- ============================================================================

local Config        = require("Config")
local Player        = require("battle.Player")
local Enemy         = require("battle.Enemy")
local Wave          = require("battle.Wave")
local SpecialTerrain = require("battle.SpecialTerrain")

local Minimap = {}

--- BattleScene 延迟引用（避免循环 require）
local _BattleScene = nil
local function getBattleScene()
    if not _BattleScene then
        _BattleScene = require("battle.BattleScene")
    end
    return _BattleScene
end

-- ========== 配置 ==========
local MAP_SIZE     = 80    -- 小地图边长（设计像素）
local MAP_MARGIN   = 10    -- 距屏幕右下角间距
local BORDER_WIDTH = 1     -- 边框宽度
local PIXEL_SIZE   = 3     -- 每个"像素点"的大小
local BG_ALPHA     = 120   -- 背景半透明度
local WORLD_SIZE   = Config.WORLD_SIZE  -- 12000

-- 颜色定义
local COLOR_BG     = { 10,  15,  20,  BG_ALPHA }
local COLOR_BORDER = { 80, 180, 220, 180 }
local COLOR_PLAYER = { 80, 255, 120, 255 }
local COLOR_BOSS   = { 255, 60,  60, 255 }
local COLOR_VIEW   = { 255, 255, 255, 40 }

-- 世界坐标 → 小地图坐标
local function worldToMap(wx, wy, mapX, mapY)
    local nx = wx / WORLD_SIZE  -- 0~1
    local ny = wy / WORLD_SIZE
    return mapX + nx * MAP_SIZE, mapY + ny * MAP_SIZE
end

--- 渲染小地图
---@param vg userdata NanoVG 上下文
---@param viewW number 视口宽（设计分辨率）
---@param viewH number 视口高（设计分辨率）
function Minimap.Render(vg, viewW, viewH)
    local BS = getBattleScene()
    local camX = BS.camX or 0
    local camY = BS.camY or 0
    local mapX = viewW - MAP_SIZE - MAP_MARGIN
    local mapY = viewH - MAP_SIZE - MAP_MARGIN

    -- 1. 背景
    nvgBeginPath(vg)
    nvgRect(vg, mapX - BORDER_WIDTH, mapY - BORDER_WIDTH,
        MAP_SIZE + BORDER_WIDTH * 2, MAP_SIZE + BORDER_WIDTH * 2)
    nvgFillColor(vg, nvgRGBA(COLOR_BG[1], COLOR_BG[2], COLOR_BG[3], COLOR_BG[4]))
    nvgFill(vg)

    -- 2. 相机视野（半透明白色矩形）
    local vx = camX / WORLD_SIZE * MAP_SIZE
    local vy = camY / WORLD_SIZE * MAP_SIZE
    local vw = viewW / WORLD_SIZE * MAP_SIZE
    local vh = viewH / WORLD_SIZE * MAP_SIZE
    nvgBeginPath(vg)
    -- 裁剪到小地图范围
    local rx1 = math.max(0, vx)
    local ry1 = math.max(0, vy)
    local rx2 = math.min(MAP_SIZE, vx + vw)
    local ry2 = math.min(MAP_SIZE, vy + vh)
    if rx2 > rx1 and ry2 > ry1 then
        nvgRect(vg, mapX + rx1, mapY + ry1, rx2 - rx1, ry2 - ry1)
        nvgFillColor(vg, nvgRGBA(COLOR_VIEW[1], COLOR_VIEW[2], COLOR_VIEW[3], COLOR_VIEW[4]))
        nvgFill(vg)
    end

    -- 3. 敌人分布（采样显示，避免绘制过多）
    -- 将世界划分为网格，每个格子最多显示一个点
    local GRID = 20  -- 网格数量 (20x20 = 400 cells)
    local gridCell = MAP_SIZE / GRID
    local gridOccupied = {}  -- key = gx * 100 + gy
    for _, e in ipairs(Enemy.active) do
        if e.alive and not e.isBoss and not e.charmed then
            local gx = math.floor(e.x / WORLD_SIZE * GRID)
            local gy = math.floor(e.y / WORLD_SIZE * GRID)
            gx = math.max(0, math.min(GRID - 1, gx))
            gy = math.max(0, math.min(GRID - 1, gy))
            local key = gx * 100 + gy
            if not gridOccupied[key] then
                gridOccupied[key] = true
                nvgBeginPath(vg)
                nvgRect(vg, mapX + gx * gridCell, mapY + gy * gridCell,
                    math.max(1.5, gridCell * 0.6), math.max(1.5, gridCell * 0.6))
                nvgFillColor(vg, nvgRGBA(255, 120, 60, 100))
                nvgFill(vg)
            end
        end
    end

    -- 4. Boss 位置（大红色像素点，闪烁）
    local boss = Enemy.currentBoss
    if boss and boss.alive then
        local bx, by = worldToMap(boss.x, boss.y, mapX, mapY)
        local pulse = 0.6 + 0.4 * math.abs(math.sin((Wave.totalTime or 0) * 4))
        local alpha = math.floor(COLOR_BOSS[4] * pulse)
        nvgBeginPath(vg)
        nvgRect(vg, bx - PIXEL_SIZE, by - PIXEL_SIZE, PIXEL_SIZE * 2, PIXEL_SIZE * 2)
        nvgFillColor(vg, nvgRGBA(COLOR_BOSS[1], COLOR_BOSS[2], COLOR_BOSS[3], alpha))
        nvgFill(vg)
    end

    -- 4.5 特别地形标记（黄色小圆点，闪烁提示）
    local stMarkers = SpecialTerrain.GetMinimapMarkers()
    for _, m in ipairs(stMarkers) do
        local mx, my = worldToMap(m.x, m.y, mapX, mapY)
        local pulse = 0.5 + 0.5 * math.abs(math.sin((Wave.totalTime or 0) * 3 + mx))
        local c = m.color or { 255, 220, 60 }
        nvgBeginPath(vg)
        nvgCircle(vg, mx, my, PIXEL_SIZE * 0.8)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(180 * pulse + 60)))
        nvgFill(vg)
    end

    -- 5. 玩家位置（绿色像素点）
    local px, py = worldToMap(Player.x, Player.y, mapX, mapY)
    nvgBeginPath(vg)
    nvgRect(vg, px - PIXEL_SIZE * 0.5, py - PIXEL_SIZE * 0.5, PIXEL_SIZE, PIXEL_SIZE)
    nvgFillColor(vg, nvgRGBA(COLOR_PLAYER[1], COLOR_PLAYER[2], COLOR_PLAYER[3], COLOR_PLAYER[4]))
    nvgFill(vg)

    -- 6. 边框（霓虹青色）
    nvgBeginPath(vg)
    nvgRect(vg, mapX - BORDER_WIDTH, mapY - BORDER_WIDTH,
        MAP_SIZE + BORDER_WIDTH * 2, MAP_SIZE + BORDER_WIDTH * 2)
    nvgStrokeColor(vg, nvgRGBA(COLOR_BORDER[1], COLOR_BORDER[2], COLOR_BORDER[3], COLOR_BORDER[4]))
    nvgStrokeWidth(vg, BORDER_WIDTH)
    nvgStroke(vg)

    -- 7. 扫描线效果（像素风格装饰）
    for row = 0, MAP_SIZE - 1, 4 do
        nvgBeginPath(vg)
        nvgRect(vg, mapX, mapY + row, MAP_SIZE, 1)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 20))
        nvgFill(vg)
    end
end

return Minimap
