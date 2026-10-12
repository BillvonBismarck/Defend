-- 双层地图共用真实几何；布局/裁剪由 UI.Widget 管，色板沿用 Theme。
local UI = require("urhox-libs/UI")
local Theme = require("defense.Theme")
local C = Theme.C
local MapView = {}
local function color(c, alpha) return nvgRGBA(c[1], c[2], c[3], alpha or c[4] or 255) end
local function outline(vg, points, ox, oy, scale, fill, stroke)
    nvgBeginPath(vg)
    for i, p in ipairs(points) do
        if i == 1 then nvgMoveTo(vg, ox + p.x * scale, oy + p.y * scale)
        else nvgLineTo(vg, ox + p.x * scale, oy + p.y * scale) end
    end
    nvgClosePath(vg)
    if fill then nvgFillColor(vg, color(fill)); nvgFill(vg) end
    if stroke then nvgStrokeColor(vg, color(stroke)); nvgStrokeWidth(vg, 1); nvgStroke(vg) end
end
function MapView.Draw(vg, run, ox, oy, scale, labels)
    for _, points in ipairs(run.map.polygons) do outline(vg, points, ox, oy, scale, C.floor) end
    local states = {}
    for _, room in ipairs(run.rooms) do states[room.id] = room.state end
    for _, region in ipairs(run.map.regions) do
        local state = states[region.id]
        local locked = run.map.locked[region.id] == true
        local fill = locked and C.ink or state == "active" and C.cardLit or C.hall
        local stroke = locked and C.dim or state == "cleared" and C.warn or state == "claimed" and C.green or C.cyanDim
        outline(vg, region.points, ox, oy, scale, fill, stroke)
        if labels then
            local room = run.config.topology.byId[region.id]
            nvgFontFace(vg, "sans"); nvgFontSize(vg, 10); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, color(C.text)); nvgText(vg, ox + room.x * run.config.polygon_unit * scale,
                oy + room.y * run.config.polygon_unit * scale, region.id)
        end
    end
    for id, gate in pairs(run.map.gate_regions) do outline(vg, gate.points, ox, oy, scale, run.map.locked[id] and C.warn or C.green) end
    local occupied = {}
    for _, tower in ipairs(run.towers) do if tower.hp > 0 then occupied[tower.slot_id] = true end end
    for _, slot in ipairs(run.config.build_slots) do
        nvgBeginPath(vg); nvgRect(vg, ox + slot.x * scale - 2, oy + slot.y * scale - 2, 4, 4)
        nvgStrokeColor(vg, color(occupied[slot.id] and C.cyan or C.dim)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        if occupied[slot.id] then nvgFillColor(vg, color(C.cyan)); nvgFill(vg) end
    end
    for _, anchor in pairs(run.anchors or {}) do
        nvgBeginPath(vg); nvgCircle(vg, ox + anchor.x * scale, oy + anchor.y * scale, labels and 4 or 5)
        nvgStrokeColor(vg, color(C.cyan)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
        if anchor.active then nvgFillColor(vg, color(C.cyan)); nvgFill(vg) end
    end
end

---@class DefensePolygonMap : Widget
---@field run table
---@field localMap boolean
local Widget = UI.Widget:Extend("DefensePolygonMap")
function Widget:Init(props)
    UI.Widget.Init(self, props)
    self.run, self.localMap = props.run, props.localMap == true
end
function MapView.RenderInLayout(vg, run, l, localMap)
    if l.w <= 0 or l.h <= 0 then return end
    local origin, size = run.config.map_origin, run.config.map_size
    local x1, y1, w, h = origin.x, origin.y, size.w, size.h
    if localMap then
        local id = run.map:RoomAt(run.player.x, run.player.y) or run.config.topology.main
        local region = run.map.room_regions[id]
        x1, y1, w, h = region.x1 - 2, region.y1 - 2, region.x2 - region.x1 + 4, region.y2 - region.y1 + 4
    end
    local scale = math.min((l.w - 12) / w, (l.h - 12) / h)
    if scale <= 0 then return end
    local ox, oy = l.x + (l.w - w * scale) / 2 - x1 * scale, l.y + (l.h - h * scale) / 2 - y1 * scale
    nvgSave(vg); nvgIntersectScissor(vg, l.x, l.y, l.w, l.h)
    MapView.Draw(vg, run, ox, oy, scale, not localMap)
    local function dot(x, y, c, radius)
        nvgBeginPath(vg); nvgCircle(vg, ox + x * scale, oy + y * scale, radius)
        nvgFillColor(vg, color(c)); nvgFill(vg)
    end
    for _, enemy in ipairs(run.enemies) do if enemy.alive then dot(enemy.x, enemy.y, C.error, 1.5) end end
    dot(run.core.x, run.core.y, C.warn, 3)
    dot(run.player.x, run.player.y, C.text, 3)
    nvgRestore(vg)
end
function Widget:Render(vg)
    self:RenderFullBackground(vg)
    return MapView.RenderInLayout(vg, self.run, self:GetAbsoluteLayout(), self.localMap)
end
MapView.Widget = Widget
return MapView
