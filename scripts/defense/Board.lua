-- 独立 raw NanoVG 战场；上下文、字体和帧生命周期由 Runtime 管理。
-- Update/Events 更新表现缓存，Render 只读；本对象不参与 UI 布局。
local Original = require("defense.Visuals")
local Combat = require("defense.Combat")
local TowerModules = require("defense.TowerModules")
local LegacyFX = require("defense.FX")
local COLORS = Original.COLORS
local CAT = Original.CHARACTERS[1]
local TAU = math.pi * 2
local ROLE_TYPE = { advance = "normal", ranged = "ranger", charger = "charger", elite = "elite",
    commander = "boss", siege = "boss", final = "boss", expedition = "boss",
    expedition_advance = "normal", expedition_ranged = "ranger", expedition_elite = "elite" }
local BOSS_INDEX = { commander = 1, siege = 2, final = 3, expedition = 1 }
local TOWER_EMOJI = { rapid = "🔫", slow = "❄️", area = "💣", repulsor = "🌀", barricade = "🛡️", stakes = "🔱", repair_station = "🛠️", energy_station = "⚡" }
local TOWER_COLOR = { rapid = COLORS.neonGreen, slow = COLORS.neonBlue, area = COLORS.neonPurple }
local WALL = { 35, 29, 55, 255 }
local FLOOR = { 20, 19, 39, 255 }
local HALL = { 27, 24, 49, 255 }
local DIM = { 100, 92, 139, 255 }
local WHITE = COLORS.white

---@class DefenseBoard
---@field run table
---@field options table
---@field elapsed number
---@field pixelsPerCell number
---@field cameraX number
---@field cameraY number
---@field moving boolean
---@field playerX number
---@field playerY number
---@field playerFlash number
---@field coreAlert number
---@field corePortal string
---@field coreEventId number
---@field reducedEffects boolean
---@field destroyed boolean
---@field lastEventId number
---@field hitFlashes table<number, number>
---@field enemyViews table<string|number, table>
---@field deaths table[]
---@field trajectories table<number, table>
---@field displacements table[]
---@field coverage table<string, table>
---@field geometryRevision string
local Board = {}
Board.__index = Board

local function color(c, a)
    return nvgRGBA(c[1], c[2], c[3], math.floor(math.max(0, math.min(255, a or c[4] or 255))))
end
local function rect(vg, x, y, w, h, c, a)
    nvgBeginPath(vg); nvgRect(vg, x, y, w, h); nvgFillColor(vg, color(c, a)); nvgFill(vg)
end
local function line(vg, ax, ay, bx, by, c, width, a)
    nvgBeginPath(vg); nvgMoveTo(vg, ax, ay); nvgLineTo(vg, bx, by)
    nvgStrokeColor(vg, color(c, a)); nvgStrokeWidth(vg, width or 1); nvgStroke(vg)
end
local function disc(vg, x, y, r, c, a)
    nvgBeginPath(vg); nvgCircle(vg, x, y, r); nvgFillColor(vg, color(c, a)); nvgFill(vg)
end
local function ring(vg, x, y, r, c, width, a)
    nvgBeginPath(vg); nvgCircle(vg, x, y, r)
    nvgStrokeColor(vg, color(c, a)); nvgStrokeWidth(vg, width or 1); nvgStroke(vg)
end
local function text(vg, x, y, value, size, c, a)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, size)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, color(c or WHITE, a)); nvgText(vg, x, y, tostring(value))
end
local function shadow(vg, x, y, r, alpha)
    nvgBeginPath(vg); nvgEllipse(vg, x, y + r + 2, r * 0.7, 4)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha or 70)); nvgFill(vg)
end
local function glow(vg, x, y, r, c, a)
    nvgBeginPath(vg); nvgCircle(vg, x, y, r)
    nvgFillPaint(vg, nvgRadialGradient(vg, x, y, r * 0.2, r, color(c, a), color(c, 0)))
    nvgFill(vg)
end
local function arc(vg, x, y, r, progress, c, width, a)
    nvgBeginPath(vg)
    local steps = math.max(2, math.ceil(math.max(0, progress) * 48))
    for i = 1, steps + 1 do
        local angle = -math.pi / 2 + math.max(0, math.min(1, progress)) * TAU * (i - 1) / steps
        local px, py = x + math.cos(angle) * r, y + math.sin(angle) * r
        if i == 1 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
    end
    nvgStrokeColor(vg, color(c, a)); nvgStrokeWidth(vg, width); nvgStroke(vg)
end
local function arrow(vg, x, y, dx, dy, length, c, a)
    local bx, by = x + dx * length, y + dy * length
    line(vg, x, y, bx, by, c, 2, a)
    line(vg, bx, by, bx - dx * 7 - dy * 4, by - dy * 7 + dx * 4, c, 2, a)
    line(vg, bx, by, bx - dx * 7 + dy * 4, by - dy * 7 - dx * 4, c, 2, a)
end
local function hpBar(vg, x, y, w, hp, maxHp, c)
    rect(vg, x - w / 2, y, w, 4, COLORS.bg, 220)
    rect(vg, x - w / 2, y, w * math.max(0, math.min(1, hp / math.max(1, maxHp))), 4, c, 230)
end
local function dist2(ax, ay, bx, by) return (ax - bx)^2 + (ay - by)^2 end
local function direction(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.000001 then return 0, -1, 0 end
    return dx / length, dy / length, length
end
---@param run table
local function visible(run, ax, ay, bx, by, radius)
    return run.map and run.map:LineOfSight(ax, ay, bx, by, radius or 0) == true
end
---@param run table
---@param tower table
local function towerRange(run, tower)
    if type(Combat.TowerRange) == "function" then return Combat.TowerRange(run, tower) end
    return tower.aura_range or run.config.towers[tower.type].range
end
local function enemyColor(e)
    if e.subtype == "explosive" or e.explodes_on_death then return COLORS.neonOrange end
    local def = Original.ENEMY[ROLE_TYPE[e.role] or "normal"]
    return COLORS[def.color] or COLORS.enemyNormal
end
---@param run table
---@param e table
local function enemyEmoji(run, e)
    if e.emoji then return e.emoji end
    local def = run.config.enemies[e.role] or {}
    if e.subtype == "explosive" then
        return (run.config.explosive or {}).emoji or (def.explosive or {}).emoji or "💣"
    end
    if def.emoji then return def.emoji end
    local bossIndex = BOSS_INDEX[e.role]
    local bosses = Original.BOSSES --[[@as table]]
    if bossIndex and bosses[bossIndex] then return bosses[bossIndex].emoji end
    local choices = Original.ENEMY_EMOJI[ROLE_TYPE[e.role] or "normal"]
    return choices[(math.floor(tonumber(e.id) or 1) - 1) % #choices + 1]
end
local function coverageKey(x, y, radius)
    return string.format("%.5f:%.5f:%.5f", x, y, radius)
end

-- 射线结合障碍角点收敛到首个 LOS 遮挡；不用会写寻路缓存的 Path/GetGrid。
---@param run table
local function buildCoverage(run, x, y, radius, reduced)
    local angles, points = {}, {}
    local count = reduced and 32 or 64
    for i = 1, count do angles[#angles + 1] = (i - 1) * TAU / count end
    local function corner(cx, cy)
        if dist2(x, y, cx, cy) <= (radius + 0.1)^2 then
            local a = math.atan(cy - y, cx - x) % TAU
            angles[#angles + 1] = (a - 0.0001) % TAU
            angles[#angles + 1] = a
            angles[#angles + 1] = (a + 0.0001) % TAU
        end
    end
    local function corners(r)
        corner(r.x1, r.y1); corner(r.x2, r.y1); corner(r.x2, r.y2); corner(r.x1, r.y2)
    end
    local map = run.map --[[@as DefenseMap]]
    for _, r in ipairs(map.obstacles or {}) do corners(r) end
    for id, locked in pairs(map.locked or {}) do
        if locked and map.room_regions[id] then corners(map.room_regions[id]) end
    end
    for _, edge in ipairs(map.edges or {}) do corner(edge.ax, edge.ay); corner(edge.bx, edge.by) end
    table.sort(angles)
    for _, a in ipairs(angles) do
        local dx, dy = math.cos(a), math.sin(a)
        local length = radius
        if not visible(run, x, y, x + dx * radius, y + dy * radius) then
            local lo, hi = 0, radius
            for _ = 1, 11 do
                local mid = (lo + hi) * 0.5
                if visible(run, x, y, x + dx * mid, y + dy * mid) then lo = mid else hi = mid end
            end
            length = lo
        end
        points[#points + 1] = { x = x + dx * length, y = y + dy * length, blocked = length < radius - 0.01 }
    end
    return points
end

function Board.New(run, options)
    local self = setmetatable({}, Board)
    self:Init(run, options or {})
    return self
end
function Board:Init(run, options)
    self.options = options
    self.elapsed, self.pixelsPerCell = 0, options.pixelsPerCell or options.pixels_per_cell or 40
    self.cameraX, self.cameraY, self.playerX, self.playerY = 30, 27, 30, 27
    self.moving, self.destroyed, self.reducedEffects = false, false, options.reducedEffects == true
    self.playerFlash, self.coreAlert, self.coreEventId, self.lastEventId = 0, 0, 0, 0
    self.corePortal, self.geometryRevision = "", ""
    self.hitFlashes, self.enemyViews, self.deaths, self.trajectories = {}, {}, {}, {}
    self.displacements, self.coverage = {}, {}
    self.run = {}
    self:SetRun(run)
    print("[DefenseBoard] 独立 NanoVG / 猫 emoji / " .. self.pixelsPerCell .. "逻辑px每格")
end
function Board:SetRun(run)
    self.run = run or {}
    self.elapsed, self.lastEventId, self.playerFlash, self.coreAlert, self.coreEventId = 0, 0, 0, 0, 0
    self.corePortal, self.geometryRevision = "", ""
    self.hitFlashes, self.enemyViews, self.deaths, self.trajectories = {}, {}, {}, {}
    self.displacements, self.coverage = {}, {}
    local p = self.run.player or { x = 30, y = 27 }
    self.cameraX, self.cameraY, self.playerX, self.playerY = p.x, p.y, p.x, p.y
    self.moving = false
end
function Board:SetReducedEffects(reduced)
    self.reducedEffects = reduced == true
    self.coverage = {}
    if self.reducedEffects then self.trajectories, self.deaths = {}, {} end
end
function Board:SetPresentation(elapsed, _, alert, portal)
    self.elapsed, self.coreAlert, self.corePortal = elapsed, alert or 0, portal or ""
end

---@param events table[]
function Board:Events(events)
    for _, event in ipairs(events or {}) do
        local id = event.event_id or self.lastEventId + 1
        if id > self.lastEventId then
            self.lastEventId = id
            local d = event.data or {}
            if event.kind == "EnemySpawned" and d.id then
                local def = (self.run.config.enemies or {})[d.role] or {}
                local view = { id = d.id, x = d.x, y = d.y, role = d.role, subtype = d.subtype,
                    radius = d.radius or def.radius or 0.34, marker = d.marker, emoji = d.emoji }
                view.emoji = enemyEmoji(self.run, view)
                self.enemyViews[d.id] = view
            elseif event.kind == "Hit" and d.id then self.hitFlashes[d.id] = 0.12
            elseif event.kind == "PlayerDamaged" then self.playerFlash = 0.3
            elseif event.kind == "CoreDamaged" then
                self.corePortal, self.coreAlert, self.coreEventId = d.portal or "S", 0.8, id
            elseif event.kind == "EnemyDied" then
                local cached = self.enemyViews[d.id] or {}
                self.deaths[#self.deaths + 1] = { id = d.id, x = d.x or cached.x, y = d.y or cached.y,
                    role = d.role or cached.role, subtype = d.subtype or cached.subtype,
                    radius = d.radius or cached.radius or 0.34, emoji = d.emoji or cached.emoji, life = 0.25 }
                if #self.deaths > 64 then table.remove(self.deaths, 1) end
            elseif event.kind == "Displaced" and d.old_x and d.x then
                self.displacements[#self.displacements + 1] = { id = d.target_id, x = d.x, y = d.y,
                    old_x = d.old_x, old_y = d.old_y, dx = d.dx, dy = d.dy, distance = d.distance,
                    blocked = d.blocked, life = 0.32, emoji = (self.enemyViews[d.target_id] or {}).emoji }
                if #self.displacements > 24 then table.remove(self.displacements, 1) end
            end
        end
    end
end

function Board:Update(dt)
    if self.destroyed or not self.run.player or dt <= 0 then return end
    local run, p = self.run, self.run.player
    self.elapsed = self.elapsed + dt
    self.moving = dist2(p.x, p.y, self.playerX, self.playerY) > 0.000001
    self.playerX, self.playerY = p.x, p.y
    local core = run.core
    local bias = core and dist2(p.x, p.y, core.x, core.y) < 9^2 and 0.18 or 0
    local cx = p.x * (1 - bias) + (core and core.x or p.x) * bias
    local cy = p.y * (1 - bias) + (core and core.y or p.y) * bias
    local smooth = 1 - math.exp(-dt * 10)
    self.cameraX, self.cameraY = self.cameraX + (cx - self.cameraX) * smooth, self.cameraY + (cy - self.cameraY) * smooth
    self.playerFlash, self.coreAlert = math.max(0, self.playerFlash - dt), math.max(0, self.coreAlert - dt)
    for id, t in pairs(self.hitFlashes) do
        if t <= dt then self.hitFlashes[id] = nil else self.hitFlashes[id] = t - dt end
    end
    for _, list in ipairs({ self.deaths, self.displacements }) do
        for i = #list, 1, -1 do
            list[i].life = list[i].life - dt
            if list[i].life <= 0 then table.remove(list, i) end
        end
    end
    local views = {}
    for _, e in ipairs(run.enemies or {}) do
        if e.alive then
            views[e.id] = { x = e.x, y = e.y, radius = e.radius, role = e.role, subtype = e.subtype,
                emoji = enemyEmoji(run, e) }
            if e.entity_id then views[e.entity_id] = views[e.id] end
        end
    end
    self.enemyViews = views
    local seen = {}
    for _, b in ipairs(run.projectiles or {}) do
        if b.alive ~= false and not self.reducedEffects then
            seen[b.id] = true
            local trail = self.trajectories[b.id] --[[@as table?]]
            if not trail then
                trail = { points = {}, head = 0, count = 0, timer = 0, born = self.elapsed }
                self.trajectories[b.id] = trail
            end
            trail.timer = trail.timer + dt
            if trail.timer >= 0.015 then
                trail.timer = trail.timer % 0.015
                trail.head = trail.head % 8 + 1
                trail.count = math.min(8, trail.count + 1)
                trail.points[trail.head] = { x = b.x, y = b.y }
            end
        end
    end
    for id in pairs(self.trajectories) do if not seen[id] then self.trajectories[id] = nil end end
    if not run.map then return end
    local locks = {}
    for id, locked in pairs(run.map.locked or {}) do locks[#locks + 1] = id .. tostring(locked) end
    table.sort(locks)
    local revision = table.concat(locks, ":")
    if revision ~= self.geometryRevision then self.coverage = {}; self.geometryRevision = revision end
    -- 覆盖缓存在 Update 建立，锁状态变化时失效。
    local needed = {}
    local function cover(x, y, r)
        local key = coverageKey(x, y, r)
        needed[key] = true
        if not self.coverage[key] then self.coverage[key] = buildCoverage(run, x, y, r, self.reducedEffects) end
    end
    for _, reaction in ipairs(run.scheduled_events or {}) do
        if reaction.committed ~= true then cover(reaction.x, reaction.y, reaction.radius or 2.5) end
    end
    for _, fx in ipairs(run.effects or {}) do
        if fx.alive ~= false and (fx.kind == "death_explosion" or fx.kind == "blast" or fx.kind == "enemy_area") then
            cover(fx.x, fx.y, fx.radius or 2.5)
        end
    end
    for _, enemy in ipairs(run.enemies or {}) do
        if enemy.alive and enemy.warning_kind and enemy.warning_kind ~= "charge" and enemy.warning_x and enemy.warning_y then
            cover(enemy.warning_x, enemy.warning_y, enemy.warning_radius or 3.2)
        end
    end
    for _, tower in ipairs(run.towers or {}) do
        if tower.hp > 0 and tower.type == "slow" then
            cover(tower.x, tower.y, towerRange(run, tower))
        end
    end
    for key in pairs(self.coverage) do if not needed[key] then self.coverage[key] = nil end end
end

-- 输入为逻辑像素，物理输入须先除 DPR。
function Board:GetTransform(logicalW, logicalH)
    local top = math.min(self.options.topInset or 130, logicalH * 0.24)
    local bottom = math.min(self.options.bottomInset or 90, logicalH * 0.22)
    local anchorY = top + (logicalH - top - bottom) * 0.5
    return logicalW * 0.5 - self.cameraX * self.pixelsPerCell,
        anchorY - self.cameraY * self.pixelsPerCell, self.pixelsPerCell
end
function Board:ScreenToWorld(x, y, logicalW, logicalH)
    local ox, oy, scale = self:GetTransform(logicalW, logicalH)
    return (x - ox) / scale, (y - oy) / scale
end

---@param vg NVGContextWrapper
function Board:DrawCoverage(vg, x, y, radius, ox, oy, scale, c, alpha, outline)
    local key = coverageKey(x, y, radius)
    local points = self.coverage[key] or buildCoverage(self.run, x, y, radius, self.reducedEffects)
    nvgBeginPath(vg)
    for i, p in ipairs(points) do
        local px, py = ox + p.x * scale, oy + p.y * scale
        if i == 1 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
    end
    nvgClosePath(vg); nvgFillColor(vg, color(c, alpha)); nvgFill(vg)
    nvgStrokeColor(vg, color(c, outline or 130)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
end

---@param vg NVGContextWrapper
function Board:DrawMap(vg, ox, oy, scale, w, h)
    local run, cfg = self.run, self.run.config
    local map = run.map --[[@as DefenseMap]]
    local regions = map and map.regions or cfg.walkable_regions
    for _, r in ipairs(regions or {}) do
        local x, y, rw, rh = ox + r.x1 * scale, oy + r.y1 * scale, (r.x2 - r.x1) * scale, (r.y2 - r.y1) * scale
        if x + rw >= 0 and x <= w and y + rh >= 0 and y <= h then
            nvgBeginPath(vg); nvgRect(vg, x, y, rw, rh)
            nvgFillPaint(vg, nvgLinearGradient(vg, x, y, x + rw, y + rh,
                color(r.id == "hall" and HALL or FLOOR), color(FLOOR)))
            nvgFill(vg)
            if cfg.sanctuary_expansion then
                local zone = ({ A = COLORS.neonGreen, B = COLORS.neonBlue, C = COLORS.neonOrange })[tostring(r.id):sub(1, 1)]
                if zone then rect(vg, x, y, rw, rh, zone, 18) end
            end
            nvgSave(vg); nvgIntersectScissor(vg, x, y, rw, rh)
            for gx = math.max(r.x1, math.floor(-ox / scale)), math.min(r.x2, math.ceil((w - ox) / scale)) do
                line(vg, ox + gx * scale, y, ox + gx * scale, y + rh, COLORS.bgGrid, 1, 36)
            end
            for gy = math.max(r.y1, math.floor(-oy / scale)), math.min(r.y2, math.ceil((h - oy) / scale)) do
                line(vg, x, oy + gy * scale, x + rw, oy + gy * scale, COLORS.bgGrid, 1, 36)
            end
            if not self.reducedEffects then
                for gx = math.ceil(math.max(r.x1, -ox / scale) / 4) * 4, math.min(r.x2, (w - ox) / scale), 4 do
                    for gy = math.ceil(math.max(r.y1, -oy / scale) / 4) * 4, math.min(r.y2, (h - oy) / scale), 4 do
                        local px, py = ox + gx * scale, oy + gy * scale
                        line(vg, px - 3, py, px + 3, py, COLORS.neonBlue, 1, 45)
                        line(vg, px, py - 3, px, py + 3, COLORS.neonBlue, 1, 45)
                    end
                end
            end
            nvgRestore(vg)
        end
    end
    -- 只绘制通行矩形并集的外缘。
    for _, e in ipairs(map and map.edges or {}) do
        local ax, ay, bx, by = ox + e.ax * scale, oy + e.ay * scale, ox + e.bx * scale, oy + e.by * scale
        if math.max(ax, bx) >= -20 and math.min(ax, bx) <= w + 20 and math.max(ay, by) >= -20 and math.min(ay, by) <= h + 20 then
            line(vg, ax + 3, ay + 5, bx + 3, by + 5, COLORS.bg, 8, 180)
            if not self.reducedEffects then line(vg, ax, ay, bx, by, COLORS.neonPurple, 8, 24) end
            line(vg, ax, ay, bx, by, COLORS.neonPurple, 2, 90)
        end
    end
    for _, room in ipairs(run.rooms or {}) do
        local r = map and map.room_regions[room.id]
        local locked = map and map.locked[room.id] == true
        local x, y = ox + room.x * scale, oy + room.y * scale
        if locked and r and ox + r.x2 * scale >= -30 and ox + r.x1 * scale <= w + 30
            and oy + r.y2 * scale >= -30 and oy + r.y1 * scale <= h + 30 then
            local rx, ry, rw, rh = ox + r.x1 * scale, oy + r.y1 * scale, (r.x2 - r.x1) * scale, (r.y2 - r.y1) * scale
            rect(vg, rx, ry, rw, rh, WALL, 245)
            nvgSave(vg); nvgIntersectScissor(vg, rx, ry, rw, rh)
            for offset = -rh, rw, 24 do line(vg, rx + offset, ry, rx + offset + rh, ry + rh, DIM, 1, 55) end
            nvgRestore(vg)
            -- 锁房整体阻挡通行，门标记放在房间与通道的交叠处。
            for _, corridor in ipairs(regions or {}) do
                if corridor.id ~= room.id then
                    local ax, ay = math.max(r.x1, corridor.x1), math.max(r.y1, corridor.y1)
                    local bx, by = math.min(r.x2, corridor.x2), math.min(r.y2, corridor.y2)
                    if ax < bx and ay < by then
                        local cx, cy = ox + (ax + bx) * scale * 0.5, oy + (ay + by) * scale * 0.5
                        local horizontal = (bx - ax) >= (by - ay)
                        line(vg, horizontal and ox + ax * scale or cx, horizontal and cy or oy + ay * scale,
                            horizontal and ox + bx * scale or cx, horizontal and cy or oy + by * scale, COLORS.neonPurple, 5, 150)
                        text(vg, cx, cy, "🔒", 24, WHITE)
                    end
                end
            end
        end
        if x > -80 and x < w + 80 and y > -80 and y < h + 80 then
            local c = locked and DIM or room.state == "cleared" and COLORS.neonGreen or room.state == "active" and COLORS.neonOrange or COLORS.neonPurple
            text(vg, x, y, locked and "🔒" or room.state == "cleared" and "🎁" or "⚑", 26, c, 210)
            text(vg, x, y + 30, cfg.sanctuary_expansion and room.name or room.id, 12, c)
        end
    end
    -- 捷径闸门的锁状态独立于探索门。
    for _, gate in ipairs(cfg.gate_regions or {}) do
        local id = gate.gate_id or gate.id
        local x, y = ox + gate.x1 * scale, oy + gate.y1 * scale
        local rw, rh = (gate.x2 - gate.x1) * scale, (gate.y2 - gate.y1) * scale
        if x + rw >= 0 and x <= w and y + rh >= 0 and y <= h then
            local locked = map.locked[id] == true
            if locked then
                rect(vg, x, y, rw, rh, WALL, 245)
                line(vg, x, y, x + rw, y + rh, COLORS.neonPurple, 3, 190)
                line(vg, x + rw, y, x, y + rh, COLORS.neonPurple, 3, 190)
            end
            text(vg, x + rw * 0.5, y + rh * 0.5, locked and "🔒" or "捷径已开", locked and 24 or 11,
                locked and DIM or COLORS.neonGreen)
        end
    end
    local active = {}
    for _, id in ipairs((run.current_wave and run.current_wave.active_portals) or {}) do active[id] = true end
    for _, unit in ipairs((run.current_wave and run.current_wave.special_units) or {}) do active[unit.portal] = true end
    local warning = run.state == "WARNING" or not cfg.sanctuary_expansion and run.state == "PREPARATION" and (run.preparation_remaining or 99) <= cfg.warning_duration
    for _, id in ipairs({ "W", "E", "S" }) do
        local p = cfg.portals[id]
        local x, y = ox + p.x * scale, oy + p.y * scale
        local attacking, pending = active[id] and run.state == "ATTACK", active[id] and warning
        local c = attacking and COLORS.neonRed or pending and COLORS.neonOrange or DIM
        if not self.reducedEffects then glow(vg, x, y, 44, c, attacking and 85 or pending and 55 or 12) end
        ring(vg, x, y, 26, c, attacking and 3 or 1.5, 180)
        if pending or attacking then ring(vg, x, y, 31 + math.sin(self.elapsed * 5) * 3, c, 1, 130) end
        text(vg, x, y, "🌀", 30, WHITE, active[id] and 255 or 100)
        text(vg, x, y - 43, id .. " · " .. (p.name or id), 13, c)
        text(vg, x, y + 42, attacking and "进攻中" or pending and "即将开启" or "待命", 11, c)
    end
    local p = cfg.recall_position or { x = 32, y = 6 }
    local x, y = ox + p.x * scale, oy + p.y * scale
    ring(vg, x, y, 25, COLORS.neonGreen, 1.5, 100)
    text(vg, x, y, "🛠️", 30, WHITE)
    text(vg, x, y + 36, "后勤 / 回城", 12, COLORS.neonGreen)
end

---@param vg NVGContextWrapper
function Board:DrawObstacle(vg, r, ox, oy, scale, w, h)
    local x, y, rw, rh = ox + r.x1 * scale, oy + r.y1 * scale, (r.x2 - r.x1) * scale, (r.y2 - r.y1) * scale
    if x + rw >= -8 and x <= w + 8 and y + rh >= -8 and y <= h + 8 then
        rect(vg, x + 5, y + 7, rw, rh, COLORS.bg, 180)
        rect(vg, x, y, rw, rh, WALL)
        line(vg, x, y, x + rw, y, COLORS.neonPurple, 2, 140)
        line(vg, x, y, x, y + rh, COLORS.neonBlue, 2, 70)
        line(vg, x + rw, y, x + rw, y + rh, DIM, 1, 90)
        line(vg, x, y + rh, x + rw, y + rh, DIM, 1, 90)
        rect(vg, x + 8, y + 8, rw - 16, rh - 16, HALL)
        rect(vg, x + 8, y + rh - 15, rw - 16, 7, COLORS.bg, 160)
        for _, dx in ipairs({ 12, rw - 12 }) do
            for _, dy in ipairs({ 12, rh - 12 }) do disc(vg, x + dx, y + dy, 2, DIM, 170) end
        end
        line(vg, x + rw * 0.32, y + rh * 0.45, x + rw * 0.68, y + rh * 0.45, COLORS.neonPurple, 2, 100)
        line(vg, x + rw * 0.4, y + rh * 0.55, x + rw * 0.6, y + rh * 0.55, COLORS.neonBlue, 2, 90)
    end
end

---@param vg NVGContextWrapper
function Board:DrawTowers(vg, ox, oy, scale)
    local run = self.run
    for _, slot in ipairs(run.config.build_slots or {}) do
        local tower = {}
        for _, t in ipairs(run.towers or {}) do if t.slot_id == slot.id then tower = t; break end end
        local x, y, alive = ox + slot.x * scale, oy + slot.y * scale, (tower.hp or 0) > 0
        local c = alive and (TOWER_COLOR[tower.type] or COLORS.neonCyan) or DIM
        ring(vg, x, y, 24, c, 1.5, alive and 125 or 70)
        for i = 1, 4 do
            local a = (i - 1) * math.pi / 2
            line(vg, x + math.cos(a) * 26, y + math.sin(a) * 26, x + math.cos(a) * 32, y + math.sin(a) * 32, c, 2, 140)
        end
        if not alive then text(vg, x, y, slot.id, 12, DIM, 120) end
    end
end

---@param vg NVGContextWrapper
function Board:DrawTower(vg, tower, ox, oy, scale)
    local run = self.run
    local slot = { id = tower.slot_id }
    local x, y, alive = ox + tower.x * scale, oy + tower.y * scale, tower.hp > 0
    local c = TOWER_COLOR[tower.type] or COLORS.neonCyan
    if alive then
        if not self.reducedEffects then glow(vg, x, y, 42, c, 40) end
        shadow(vg, x, y, 16)
        text(vg, x, y, tower.emoji or (run.config.towers[tower.type] or {}).emoji or TOWER_EMOJI[tower.type], 34, WHITE)
        text(vg, x + 25, y - 23, "⚓", 14, c, 200)
        hpBar(vg, x, y + 24, 38, tower.hp, tower.max_hp, c)
        text(vg, x, y + 39, slot.id .. " · " .. tostring(tower.upgrade_count or 0), 10, c)
        if tower.branch_id then
            text(vg, x, y - 57, (run.config.branches[tower.branch_id] or {}).name or tower.branch_id, 10, c, 220)
        end
        if tower.module_id then
            local module = TowerModules.Definitions[tower.module_id]
            text(vg, x, y - 42, module and module.name or tower.module_id, 11, c, 220)
        end
    end
end

---@param vg NVGContextWrapper
function Board:DrawSlowAuras(vg, ox, oy, scale)
    local run = self.run
    for _, t in ipairs(run.towers or {}) do
        if t.hp > 0 and t.type == "slow" then
            local radius = towerRange(run, t)
            local siteActive = not t.activation_region_id or run.config.sanctuary_expansion
            if not siteActive then
                for _, enemy in ipairs(run.enemies) do
                    if enemy.alive and enemy.behavior == "expedition"
                        and run.map:IsInRegion(t.activation_region_id, enemy.x, enemy.y) then siteActive = true; break end
                end
            end
            self:DrawCoverage(vg, t.x, t.y, radius, ox, oy, scale, COLORS.neonBlue, siteActive and 10 or 3, siteActive and 65 or 20)
            -- 光环外轮廓使用实际半径，不随动画变化。
            if not self.reducedEffects then
                ring(vg, ox + t.x * scale, oy + t.y * scale, radius * scale, DIM, 1, 25)
            end
        end
    end
end

---@param vg NVGContextWrapper
function Board:DrawWarnings(vg, ox, oy, scale)
    local run, core = self.run, self.run.core
    for _, e in ipairs(run.enemies or {}) do
        if e.alive and e.warning_kind then
            local x, y = ox + e.x * scale, oy + e.y * scale
            if e.warning_kind == "charge" then
                local dx, dy = e.charge_dx or 0, e.charge_dy or 0
                local length = (run.config.combat or {}).charge_speed or 8
                length = length * ((run.config.combat or {}).charge_duration or 1.2)
                local wx, wy = e.x + dx * length, e.y + dy * length
                if not visible(run, e.x, e.y, wx, wy) then
                    local lo, hi = 0, length
                    for _ = 1, 10 do
                        local mid = (lo + hi) * 0.5
                        if visible(run, e.x, e.y, e.x + dx * mid, e.y + dy * mid) then lo = mid else hi = mid end
                    end
                    wx, wy = e.x + dx * lo, e.y + dy * lo
                end
                local bx, by = ox + wx * scale, oy + wy * scale
                line(vg, x, y, bx, by, COLORS.neonOrange, e.radius * scale * 2, 42)
                line(vg, x, y, bx, by, COLORS.neonYellow, 2, 190)
                ring(vg, x, y, e.radius * scale + 7, COLORS.neonYellow, 2, 170)
            elseif e.warning_x and e.warning_y then
                self:DrawCoverage(vg, e.warning_x, e.warning_y, e.warning_radius or 3.2,
                    ox, oy, scale, COLORS.neonRed, 25, 170)
            end
        end
    end
    for _, reaction in ipairs(run.scheduled_events or {}) do
        if reaction.committed ~= true then
            local radius = reaction.radius or 2.5
            local x, y = ox + reaction.x * scale, oy + reaction.y * scale
            local remaining = math.max(0, (reaction.at or 0) - (run.clock or 0))
            local pulse = 0.5 + 0.5 * math.sin(self.elapsed * 18)
            -- 灰圆为理论半径，橙红多边形为 LOS 可见范围。
            ring(vg, x, y, radius * scale, DIM, 1, 65)
            self:DrawCoverage(vg, reaction.x, reaction.y, radius, ox, oy, scale, COLORS.neonOrange, 24 + pulse * 18, 210)
            for i = 1, 8 do
                local a = (i - 1) * TAU / 8
                local wx, wy = reaction.x + math.cos(a) * radius, reaction.y + math.sin(a) * radius
                if not visible(run, reaction.x, reaction.y, wx, wy) then
                    local bx, by = ox + wx * scale, oy + wy * scale
                    line(vg, bx - 4, by - 4, bx + 4, by + 4, DIM, 1, 95)
                    line(vg, bx + 4, by - 4, bx - 4, by + 4, DIM, 1, 95)
                end
            end
            text(vg, x, y, "💣", 28, WHITE)
            arc(vg, x, y, 22, 1 - math.min(1, remaining / math.max(0.001, reaction.delay or
                (run.config.reactions or {}).delay or 0.7)), COLORS.neonOrange, 3, 240)
            text(vg, x, y - 37, string.format("%.1fs · %g", remaining, reaction.damage or 40), 12, COLORS.neonOrange)
            text(vg, x, y + 37, "碰撞体接触也命中 · 墙后遮挡", 10, COLORS.neonOrange, 190)
            -- 命中按圆碰撞体接触判定，不仅看目标中心是否落入多边形。
            if type(Combat.ExplosionContains) == "function" then
                for _, target in ipairs(run.enemies or {}) do
                    if Combat.ExplosionContains(run, reaction.x, reaction.y, radius, target) then
                        ring(vg, ox + target.x * scale, oy + target.y * scale, target.radius * scale + 5,
                            COLORS.neonOrange, 2, 180)
                    end
                end
                for _, target in ipairs(run.towers or {}) do
                    if Combat.ExplosionContains(run, reaction.x, reaction.y, radius, target) then
                        ring(vg, ox + target.x * scale, oy + target.y * scale, (target.radius or 0.65) * scale + 5,
                            COLORS.neonRed, 2, 190)
                    end
                end
                if Combat.ExplosionContains(run, reaction.x, reaction.y, radius, run.player) then
                    ring(vg, ox + run.player.x * scale, oy + run.player.y * scale, run.player.radius * scale + 9,
                        COLORS.neonRed, 3, 220)
                end
            end
            if core and core.hp > 0 and dist2(reaction.x, reaction.y, core.x, core.y) <= (radius + core.radius)^2
                and visible(run, reaction.x, reaction.y, core.x, core.y) then
                local cx, cy = ox + core.x * scale, oy + core.y * scale
                ring(vg, cx, cy, core.radius * scale + 10, COLORS.neonRed, 3, 230)
                text(vg, cx, cy + core.radius * scale + 23, "核心在爆炸范围", 12, COLORS.neonRed)
            end
        end
    end
    for _, fx in ipairs(run.effects or {}) do
        if fx.alive ~= false then
            if fx.kind == "death_explosion" then
                local alpha = math.max(0, math.min(1, (fx.timer or 0.35) / 0.35))
                self:DrawCoverage(vg, fx.x, fx.y, fx.radius or 2.5, ox, oy, scale, COLORS.neonOrange, 45 * alpha, 230 * alpha)
            elseif fx.kind == "enemy_area" or fx.kind == "blast" then
                self:DrawCoverage(vg, fx.x, fx.y, fx.radius or 1, ox, oy, scale,
                    fx.kind == "enemy_area" and COLORS.neonRed or COLORS.neonPurple, 18, 120)
            end
        end
    end
end

---@param vg NVGContextWrapper
function Board:DrawEnemy(vg, e, x, y, scale, dying)
    local run, r, c = self.run, e.radius * scale, enemyColor(e)
    local life = e.life or 0.25
    local progress = dying and 1 - life / 0.25 or 0
    local deathScale, alpha = 1 + progress * 0.5, 1 - progress
    nvgSave(vg)
    if dying then nvgGlobalAlpha(vg, math.max(0, alpha)) end
    if not dying then
        if self.hitFlashes[e.id] then disc(vg, x, y, r + 2, WHITE, 180) end
        if not self.reducedEffects then
            disc(vg, x, y, r + 8, COLORS.neonRed, 25)
            disc(vg, x, y, r + 3, COLORS.neonRed, 40)
        end
        ring(vg, x, y, r + 4, c, 2, 50)
    end
    shadow(vg, x, y, r * deathScale, 60)
    text(vg, x, y, enemyEmoji(run, e), r * 2.2 * deathScale, WHITE)
    if not dying then
        if e.subtype == "explosive" or e.explodes_on_death then
            ring(vg, x, y, r + 7, COLORS.neonOrange, 2, 160)
            text(vg, x + r + 4, y - r - 2, e.marker or "💥", 15, WHITE)
        end
        local boss = BOSS_INDEX[e.role] ~= nil
        if boss then
            local pulse = 0.5 + 0.5 * math.sin(self.elapsed * 3)
            ring(vg, x, y, r + 8, c, 2.5, 80 + pulse * 80)
            if not self.reducedEffects then ring(vg, x, y, r + 14, c, 1.5, 40 + pulse * 40) end
        end
        if e.anchored then text(vg, x + r + 6, y - r, "⚓", 14, c) end
        if (e.slow_factor or 1) < 1 then
            local inside = false
            for _, t in ipairs(run.towers or {}) do
                if t.hp > 0 and t.type == "slow" then
                    local radius = towerRange(run, t)
                    local legal = not t.activation_region_id or (e.behavior == "expedition" or run.config.sanctuary_expansion)
                        and run.map:IsInRegion(t.activation_region_id, e.x, e.y)
                    if legal and dist2(e.x, e.y, t.x, t.y) <= radius^2 and visible(run, t.x, t.y, e.x, e.y) then inside = true; break end
                end
            end
            local remaining = 0
            for _, status in pairs(e.slow_effects or {}) do
                if math.abs((status.factor or 1) - e.slow_factor) < 0.000001 then
                    remaining = math.max(remaining, status.timer or 0)
                end
            end
            disc(vg, x, y, r + 5, COLORS.neonBlue, 25)
            ring(vg, x, y, r + 6, COLORS.neonBlue, inside and 2 or 1, inside and 190 or 100)
            text(vg, x, y + r + 21, string.format("-%d%% %s%.1fs", math.floor((1 - e.slow_factor) * 100 + 0.5),
                inside and "" or "余", remaining), 10, COLORS.neonBlue, 220)
        end
        if e.hp < e.max_hp or boss or e.role == "elite" then hpBar(vg, x, y - r - 10, math.max(24, r * 2), e.hp, e.max_hp, c) end
        if e.behavior == "expedition" then
            local marching = e.stage == "TRAVELLING" or e.stage == "LEAVING" or e.stage == "SPAWNING"
            if run.config.sanctuary_expansion then
                text(vg, x, y - r - 26, "第" .. tostring(e.squad_id) .. "队 · " ..
                    (e.stage == "ROOM_ENGAGED" and tostring(e.current_room_id) or e.stage == "FINAL_ASSAULT" and "攻核" or "行军"), 11, COLORS.neonOrange)
            elseif marching then
                ring(vg, x, y, r + 12, COLORS.neonBlue, 3, 210)
                text(vg, x, y - r - 26, "远征 · 转场护甲", 12, COLORS.neonBlue)
            elseif e.stage == "ROOM_ENGAGED" then
                local ledger = e.damage_ledger and e.damage_ledger[e.current_room_id] or {}
                text(vg, x, y - r - 26, "远征 · " .. tostring(e.current_room_id), 12, COLORS.neonOrange)
                text(vg, x, y - r - 42, string.format("本站可伤 %.1f", math.max(0, (ledger.cap or 0) - (ledger.used or 0))), 11, COLORS.neonOrange)
            elseif e.stage == "FINAL_ASSAULT" then
                text(vg, x, y - r - 26, "远征 · 终局护甲解除", 12, COLORS.neonRed)
            end
        end
    end
    nvgRestore(vg)
end

---@param vg NVGContextWrapper
function Board:DrawProjectiles(vg, ox, oy, scale, w, h)
    for _, b in ipairs(self.run.projectiles or {}) do
        if b.alive ~= false then
            local x, y = ox + b.x * scale, oy + b.y * scale
            if x > -60 and x < w + 60 and y > -60 and y < h + 60 then
                local ice = b.source == "tower_slow" or (b.frost or 0) > 0
                local style = CAT.bulletStyle[(b.pierce or 0) > 0 and "pierce" or "normal"]
                local c = b.team == "enemy" and COLORS.neonRed or ice and COLORS.neonBlue or b.source == "tower_area" and COLORS.neonPurple or style.trailColor
                -- 绘制尺寸可大于规则碰撞半径。
                local r = math.max(4, (b.radius or 0.08) * scale)
                local trail = self.trajectories[b.id] --[[@as table?]]
                if trail and not self.reducedEffects then
                    for i = 1, trail.count do
                        local index = ((trail.head - trail.count + i - 1) % 8) + 1
                        local p = trail.points[index]
                        local nextIndex = ((trail.head - trail.count + i) % 8) + 1
                        local np = i < trail.count and trail.points[nextIndex] or { x = b.x, y = b.y }
                        if p and np then
                            local t = i / (trail.count + 1)
                            line(vg, ox + p.x * scale, oy + p.y * scale, ox + np.x * scale, oy + np.y * scale,
                                c, r * (0.6 + t * 2), 20 + 140 * t)
                        end
                    end
                    glow(vg, x, y, (r + 5) * (0.7 + math.sin(self.elapsed * 12) * 0.3), c, 65)
                end
                nvgSave(vg); nvgTranslate(vg, x, y)
                nvgRotate(vg, math.atan(b.dy or 0, b.dx or 1) + math.pi * 0.5)
                local emoji = b.emoji or (b.team == "enemy" and "🔴" or ice and "❄️" or b.source == "tower_area" and "💣" or style.emoji)
                text(vg, 0, 0, emoji, r * 4.5, WHITE)
                nvgRestore(vg)
            end
        end
    end
end

---@param vg NVGContextWrapper
function Board:DrawPlayer(vg, ox, oy, scale)
    local p = self.run.player
    local x, y, r = ox + p.x * scale, oy + p.y * scale, p.radius * scale
    local character = self.run.config.character or {}
    local emojis = character.states or character.playerEmoji or CAT.playerEmoji
    local inv = p.invulnerable == true or type(p.invulnerable) == "number" and p.invulnerable > 0
    local hit = self.playerFlash > 0
    nvgSave(vg)
    if not self.reducedEffects then glow(vg, x, y, r + 18, COLORS.neonBlue, 50) end
    if inv or hit then
        local pulse = 0.5 + 0.5 * math.sin(self.elapsed * 16)
        ring(vg, x, y, r + 10 + pulse * 4, WHITE, 2, 80 + pulse * 120)
        if math.floor(self.elapsed * 12) % 2 == 0 then nvgGlobalAlpha(vg, 0.35) end
    end
    shadow(vg, x, y, r)
    local emoji = p.hp <= 0 and emojis.dead or hit and emojis.hit or self.moving and emojis.move or p.emoji or emojis.idle
    text(vg, x, y, emoji, r * 2.4, WHITE)
    nvgRestore(vg)
    if self.run.recall and self.run.recall.active then
        ring(vg, x, y, r + 15, COLORS.neonBlue, 2, 100)
        arc(vg, x, y, r + 15, (self.run.recall.progress or 0) / self.run.config.recall_duration, COLORS.neonBlue, 3, 230)
    end
end

---@param vg NVGContextWrapper
function Board:DrawActiveTarget(vg, ox, oy, scale)
    if type(Combat.ActiveTarget) ~= "function" then return end
    local target, info = Combat.ActiveTarget(self.run)
    if not target or not info then return end
    local x, y, r = ox + target.x * scale, oy + target.y * scale, target.radius * scale + 9
    local ready = (self.run.player.active_cd or 0) <= 0
    local c = not ready and DIM or info.ok and COLORS.neonBlue or COLORS.neonOrange
    for i = 1, 4 do
        local dx = i <= 2 and -1 or 1
        local dy = i % 2 == 1 and -1 or 1
        line(vg, x + dx * r, y + dy * r, x + dx * (r - 7), y + dy * r, c, 2, ready and 240 or 110)
        line(vg, x + dx * r, y + dy * r, x + dx * r, y + dy * (r - 7), c, 2, ready and 240 or 110)
    end
    local dx, dy = info.dx or 0, info.dy or -1
    arrow(vg, x + dx * (r + 3), y + dy * (r + 3), dx, dy, 28, c, ready and 230 or 100)
    if info.blocked then
        local bx, by = ox + (info.landing_x or target.x) * scale, oy + (info.landing_y or target.y) * scale
        line(vg, bx - 5, by - 5, bx + 5, by + 5, COLORS.neonOrange, 2, 160)
        line(vg, bx + 5, by - 5, bx - 5, by + 5, COLORS.neonOrange, 2, 160)
    end
end

---@param vg NVGContextWrapper
function Board:DrawCore(vg, ox, oy, scale, w, h, indicatorOnly)
    local run, core = self.run, self.run.core
    local x, y, r = ox + core.x * scale, oy + core.y * scale, core.radius * scale
    local danger, portal = self.coreAlert > 0 or core.hp / math.max(1, core.max_hp) < 0.3, self.corePortal
    for _, e in ipairs(run.enemies or {}) do
        if e.alive and not e.room_id and dist2(e.x, e.y, core.x, core.y) <= (core.radius + e.radius + 1.5)^2
            and visible(run, e.x, e.y, core.x, core.y) then danger, portal = true, e.origin_portal or portal; break end
    end
    for _, reaction in ipairs(run.scheduled_events or {}) do
        if reaction.committed ~= true and dist2(reaction.x, reaction.y, core.x, core.y) <= ((reaction.radius or 2.5) + core.radius)^2
            and visible(run, reaction.x, reaction.y, core.x, core.y) then danger = true; break end
    end
    local c = danger and COLORS.neonRed or COLORS.neonBlue
    if not indicatorOnly then
        if not self.reducedEffects then glow(vg, x, y, r + 30, c, danger and 100 or 55) end
        ring(vg, x, y, r, c, 2, 130)
        ring(vg, x, y, r + 6, c, danger and 3 or 1, danger and 180 or 70)
        shadow(vg, x, y, 26)
        text(vg, x, y - math.sin(self.elapsed * 2) * 2, core.emoji or "💎", 62, WHITE)
        text(vg, x + 32, y - 35, "⚓", 16, c)
        hpBar(vg, x, y + 42, 84, core.hp, core.max_hp, c)
        if danger then
            local dx, dy = portal == "W" and -1 or portal == "E" and 1 or 0, portal == "S" and 1 or 0
            if dx ~= 0 or dy ~= 0 then arrow(vg, x + dx * (r + 10), y + dy * (r + 10), dx, dy, 24, c, 230) end
            text(vg, x, y - r - 23, "核心危险", 14, c)
        end
    end
    -- 屏外核心提示锚定到世界可见边缘，避开 HUD。
    if indicatorOnly and (x < 26 or x > w - 26 or y < 150 or y > h - 100) then
        local px, py = math.max(28, math.min(w - 28, x)), math.max(math.min(160, h * 0.3), math.min(h - 105, y))
        local dx, dy = direction(px, py, x, y)
        ring(vg, px, py, 19, c, danger and 3 or 1, danger and 230 or 100)
        text(vg, px, py, "💎", 22, WHITE)
        arrow(vg, px + dx * 22, py + dy * 22, dx, dy, 14, c, 180)
    end
end

-- Y 向下，按柱底 y2/实体规则位置排序，不随动画变化；同深度保持插入序，仅排序临时表。
function Board:WorldDrawOrder()
    local run, items = self.run, {}
    local function add(kind, entity, depth)
        items[#items + 1] = { kind = kind, entity = entity, depth = depth, order = #items + 1 }
    end
    for _, r in ipairs(run.map and run.map.obstacles or run.config.obstacles or {}) do add("obstacle", r, r.y2) end
    for _, t in ipairs(run.towers or {}) do if t.hp > 0 then add("tower", t, t.y) end end
    if run.core then add("core", run.core, run.core.y) end
    for _, d in ipairs(self.deaths) do if d.x and d.y then add("death", d, d.y) end end
    for _, e in ipairs(run.enemies or {}) do if e.alive then add("enemy", e, e.y) end end
    add("player", run.player, run.player.y)
    table.sort(items, function(a, b)
        if a.depth == b.depth then return a.order < b.order end
        return a.depth < b.depth
    end)
    return items
end

---@param vg NVGContextWrapper
function Board:DrawWorld(vg, ox, oy, scale, w, h)
    for _, item in ipairs(self:WorldDrawOrder()) do
        local e = item.entity
        if item.kind == "obstacle" then self:DrawObstacle(vg, e, ox, oy, scale, w, h)
        elseif item.kind == "tower" then self:DrawTower(vg, e, ox, oy, scale)
        elseif item.kind == "core" then self:DrawCore(vg, ox, oy, scale, w, h)
        elseif item.kind == "player" then self:DrawPlayer(vg, ox, oy, scale)
        else
            local x, y = ox + e.x * scale, oy + e.y * scale
            if x > -100 and x < w + 100 and y > -100 and y < h + 100 then
                self:DrawEnemy(vg, e, x, y, scale, item.kind == "death")
            end
        end
    end
end

---@param vg NVGContextWrapper
---@param logicalW number
---@param logicalH number
function Board:Render(vg, logicalW, logicalH)
    if self.destroyed or not self.run.config or not self.run.player or not logicalW or not logicalH or logicalW <= 0 or logicalH <= 0 then return end
    local ox, oy, scale = self:GetTransform(logicalW, logicalH)
    local sx, sy = LegacyFX.GetShakeOffset()
    if not self.reducedEffects then ox, oy = ox + sx, oy + sy end
    nvgSave(vg)
    nvgIntersectScissor(vg, 0, 0, logicalW, logicalH)
    nvgLineCap(vg, NVG_ROUND)
    rect(vg, 0, 0, logicalW, logicalH, COLORS.bg)
    self:DrawMap(vg, ox, oy, scale, logicalW, logicalH)
    self:DrawSlowAuras(vg, ox, oy, scale)
    self:DrawTowers(vg, ox, oy, scale)
    for _, d in ipairs(self.run.drops or {}) do
        if d.alive ~= false then
            local x, y = ox + d.x * scale, oy + d.y * scale
            if x > -30 and x < logicalW + 30 and y > -30 and y < logicalH + 30 then
                local c = d.kind == "gold" and COLORS.neonYellow or COLORS.neonGreen
                if not self.reducedEffects then glow(vg, x, y, 14, c, 35) end
                text(vg, x, y - math.sin(self.elapsed * 3 + (d.id or 0)) * 2,
                    d.emoji or (d.kind == "gold" and Original.SPECIAL_LOOT.coin.emoji or "💠"), d.kind == "gold" and 15 or 12, WHITE)
            end
        end
    end
    self:DrawWorld(vg, ox, oy, scale, logicalW, logicalH)
    -- 危险范围和瞄准提示覆盖实体层。
    self:DrawWarnings(vg, ox, oy, scale)
    for _, d in ipairs(self.displacements) do
        local x, y, bx, by = ox + d.old_x * scale, oy + d.old_y * scale, ox + d.x * scale, oy + d.y * scale
        local alpha = math.max(0, d.life / 0.32)
        line(vg, x, y, bx, by, COLORS.neonBlue, 2, alpha * 140)
        ring(vg, bx, by, 18, d.blocked and COLORS.neonOrange or COLORS.neonBlue, 2, alpha * 190)
        if d.emoji and not self.reducedEffects then text(vg, x, y, d.emoji, 30, WHITE, alpha * 80) end
    end
    self:DrawProjectiles(vg, ox, oy, scale, logicalW, logicalH)
    self:DrawActiveTarget(vg, ox, oy, scale)
    self:DrawCore(vg, ox, oy, scale, logicalW, logicalH, true)
    LegacyFX.Render(vg, ox, oy, scale, logicalW, logicalH)
    nvgRestore(vg)
end

function Board:Destroy()
    self.destroyed = true
    self.run = {}
    self.hitFlashes, self.enemyViews, self.deaths, self.trajectories, self.displacements, self.coverage = {}, {}, {}, {}, {}, {}
    -- 不释放 Runtime 的上下文/字体，也不停止它共享的 LegacyFX。
end
return Board
