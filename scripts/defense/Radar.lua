-- 导航快照小地图。
local UI = require("urhox-libs/UI")
local Theme = require("defense.Theme")
local Map = require("defense.Map")
local C = Theme.C

---@class DefenseRadarProps : WidgetProps
---@field run? table

---@class DefenseRadar : Widget
---@field run table
---@field props DefenseRadarProps
---@field route_cache table
---@field route_cache_key string
---@field route_cache_run table
---@overload fun(props?: DefenseRadarProps): DefenseRadar
local Radar = UI.Widget:Extend("DefenseRadar")

---@param props DefenseRadarProps
function Radar:Init(props)
    local initWidget = UI.Widget.Init --[[@as fun(widget: Widget, props: WidgetProps)]]
    initWidget(self, props)
    -- run 是透明 setter 属性，rawset 避免递归调用 SetRun。
    rawset(self, "run", props.run or {})
    self.route_cache, self.route_cache_key, self.route_cache_run = {}, "", {}
end
function Radar:SetRun(run)
    self.props.run = run
    rawset(self, "run", run or {})
    self.route_cache, self.route_cache_key, self.route_cache_run = {}, "", {}
end

function Radar:Update(dt)
    local run = self.run
    local wave = run.current_wave or {}
    local challenge = wave.challenge
    local route = run.config and challenge and (run.config.expedition_routes or {})[challenge.route_id]
    if route then self:RoutePaths(run, route)
    elseif #self.route_cache > 0 then self.route_cache, self.route_cache_key = {}, "" end
end

-- 独立地图按路线开门、保留其他门状态；run/wave/route/revision 变化时重建缓存。
---@param run table
---@param route table
function Radar:RoutePaths(run, route)
    local key = tostring(run.wave_id) .. ":" .. route.route_id .. ":" .. tostring(run.map and run.map.revision or 0)
    if self.route_cache_run == run and self.route_cache_key == key then return self.route_cache end
    local map, paths = Map.New(run.config), {}
    if run.map then
        for id, locked in pairs(run.map.locked) do map:SetUnlocked(id, not locked) end
    end
    for _, stop in ipairs(route.stops or {}) do map:SetUnlocked(stop.room_id, true) end
    for _, id in ipairs(route.gate_ids or {}) do map:SetUnlocked(id, true) end
    local radius = (run.config.enemies.expedition or {}).radius or 0
    local previous = run.config.portals.S
    local function add(p)
        if previous and p then
            local path = map:Path(previous.x, previous.y, p.x, p.y, radius)
            if path then paths[#paths + 1] = path end
        end
        previous = p
    end
    for _, stop in ipairs(route.stops or {}) do add(stop.entry); add(stop.engage); add(stop.exit) end
    add(route.final_target)
    self.route_cache, self.route_cache_key, self.route_cache_run = paths, key, run
    return paths
end

---@param vg NVGContextWrapper
function Radar:Render(vg)
    local l, run = self:GetAbsoluteLayout(), self.run
    if not run.config or l.w <= 0 or l.h <= 0 then return end
    if run.config.polygon_expansion then
        self:RenderFullBackground(vg)
        return require("defense.PolygonMapView").RenderInLayout(vg, run, l, true)
    end
    self:RenderFullBackground(vg)
    local size, origin = run.config.map_size, run.config.map_origin or { x = 0, y = 0 }
    if not size or size.w <= 0 or size.h <= 0 then return end
    -- UI 宿主负责 DPR/设计缩放，这里不重复 BeginFrame/Scale。
    local scale = math.min(math.max(0, l.w - 12) / size.w, math.max(0, l.h - 12) / size.h)
    if scale <= 0 then return end
    local ox = l.x + (l.w - size.w * scale) / 2 - origin.x * scale
    local oy = l.y + (l.h - size.h * scale) / 2 - origin.y * scale
    local function rect(x1, y1, x2, y2, color)
        nvgBeginPath(vg); nvgRect(vg, ox + x1 * scale, oy + y1 * scale, (x2 - x1) * scale, (y2 - y1) * scale)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4] or 255)); nvgFill(vg)
    end
    local function dot(x, y, radius, color)
        nvgBeginPath(vg); nvgCircle(vg, ox + x * scale, oy + y * scale, radius)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 255)); nvgFill(vg)
    end
    local function mark(x, y, text, color)
        nvgFontFace(vg, UI.Theme.FontFace("sans", "normal"))
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 255))
        nvgText(vg, ox + x * scale, oy + y * scale, text)
    end
    local function line(points, color, width)
        if #points < 2 then return end
        nvgBeginPath(vg)
        nvgMoveTo(vg, ox + points[1].x * scale, oy + points[1].y * scale)
        for i = 2, #points do nvgLineTo(vg, ox + points[i].x * scale, oy + points[i].y * scale) end
        nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 180))
        nvgStrokeWidth(vg, width or 1); nvgStroke(vg)
    end
    nvgSave(vg); nvgIntersectScissor(vg, l.x, l.y, l.w, l.h)
    for _, r in ipairs(run.config.walkable_regions or {}) do rect(r.x1, r.y1, r.x2, r.y2, C.hall) end
    for _, r in ipairs(run.config.obstacles or {}) do rect(r.x1, r.y1, r.x2, r.y2, C.wall) end
    for _, gate in ipairs(run.config.gate_regions or {}) do
        local id = gate.gate_id or gate.id
        local locked = run.map and run.map.locked[id]
        rect(gate.x1, gate.y1, gate.x2, gate.y2, locked == false and C.green or C.dim)
    end
    local wave = run.current_wave or {}
    local challenge = wave.challenge
    local route = challenge and (run.config.expedition_routes or {})[challenge.route_id]
    ---@type table?
    local expedition = nil
    for _, e in ipairs(run.enemies or {}) do
        if e.alive and e.role == "expedition" and (not route or e.route_id == route.route_id) then expedition = e; break end
    end
    local nextStop = expedition and (expedition.route_index or 1) or 1
    if route then
        for _, path in ipairs(self.route_cache) do line(path, C.warn, 1.2) end
        for i, stop in ipairs(route.stops or {}) do
            mark(stop.engage.x, stop.engage.y - 3, tostring(i), C.warn)
            if i == nextStop then
                nvgBeginPath(vg); nvgCircle(vg, ox + stop.engage.x * scale, oy + stop.engage.y * scale, 5)
                nvgStrokeColor(vg, nvgRGBA(C.warn[1], C.warn[2], C.warn[3], 255)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
            end
        end
    end
    local active = {}
    for _, id in ipairs(wave.active_portals or {}) do active[id] = true end
    for _, unit in ipairs(wave.special_units or {}) do if unit.portal then active[unit.portal] = true end end
    local warning = run.state == "WARNING" or run.state == "PREPARATION" and (run.preparation_remaining or 0) <= 8
    for _, id in ipairs({ "W", "E", "S" }) do
        local p = run.config.portals[id] --[[@as table]]
        local color = active[id] and run.state == "ATTACK" and C.error or active[id] and warning and C.warn or C.dim
        dot(p.x, p.y, 2.5, color)
        mark(p.x, p.y - 3.5, id, color)
    end
    for _, room in ipairs(run.rooms) do
        local accessible = room.accessible
        if accessible == nil then accessible = room.unlocked end
        local color = not accessible and C.dim or room.state == "claimed" and C.green or
            room.state == "cleared" and C.cyan or room.state == "active" and C.warn or C.purple
        dot(room.x, room.y, 2.5, color)
        if not accessible then mark(room.x, room.y, "×", C.dim)
        elseif room.state == "cleared" then mark(room.x, room.y, "+", C.green) end
    end
    for _, tower in ipairs(run.towers) do
        local color = tower.hp <= 0 and C.error or tower.hp < tower.max_hp and C.warn or C.blue
        dot(tower.x, tower.y, 2.3, color)
        if tower.hp <= 0 then mark(tower.x, tower.y, "×", C.error)
        elseif tower.hp < tower.max_hp then mark(tower.x, tower.y, "!", C.warn) end
    end
    for _, e in ipairs(run.enemies) do if e.alive then dot(e.x, e.y, 1.2, C.error) end end
    dot(run.core.x, run.core.y, 3, run.core.hp < run.core.max_hp * 0.3 and C.error or C.cyan)
    dot(run.player.x, run.player.y, 3, C.green)
    nvgRestore(vg)
end
return Radar
