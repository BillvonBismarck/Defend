-- 双层地图共用真实几何；布局/裁剪由 UI.Widget 管，色板沿用 Theme。
local UI = require("urhox-libs/UI")
local Theme = require("defense.Theme")
local C = Theme.C
local Anchors=require('defense.Anchors')
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
function MapView.Draw(vg, run, ox, oy, scale, labels, bounds, currentRoom)
    local function inView(x,y)
        return not bounds or x>=bounds.x1 and x<=bounds.x2 and y>=bounds.y1 and y<=bounds.y2
    end
    local polygons = bounds and run.map.polygonIndex:Query(bounds.x1,bounds.y1,bounds.x2,bounds.y2) or run.map.polygonBounds
    for _, b in ipairs(polygons) do
        local ids=b.points.room_ids
        if #ids==2 and (not currentRoom or ids[1]==currentRoom or ids[2]==currentRoom) then
            outline(vg,b.points,ox,oy,scale,C.floor,C.cyanDim)
        end
    end
    local states = {}
    for _, room in ipairs(run.rooms) do states[room.id] = room.state end
    local regions = currentRoom and {run.map.room_regions[currentRoom]} or
        bounds and run.map.roomIndex:Query(bounds.x1,bounds.y1,bounds.x2,bounds.y2) or run.map.regions
    for _, region in ipairs(regions) do
        local state = states[region.id]
        local locked = run.map.locked[region.id] == true
        local fill = locked and C.ink or state == "active" and C.cardLit or C.hall
        local stroke = locked and C.dim or state == "cleared" and C.warn or state == "claimed" and C.green or C.cyanDim
        outline(vg, region.points, ox, oy, scale, fill, stroke)
        if labels and scale>=1.4 then
            local room = run.config.topology.byId[region.id]
            nvgFontFace(vg, "sans"); nvgFontSize(vg, 10); nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, color(C.text)); nvgText(vg, ox + room.x * run.config.polygon_unit * scale,
                oy + room.y * run.config.polygon_unit * scale, region.id)
        end
    end
    for _, gate in ipairs(run.map.lockIndex:Query(bounds and bounds.x1 or run.map.origin_x,
        bounds and bounds.y1 or run.map.origin_y,bounds and bounds.x2 or run.map.origin_x+run.map.width,
        bounds and bounds.y2 or run.map.origin_y+run.map.height)) do
        if run.map.gate_regions[gate.id] then outline(vg,gate.points,ox,oy,scale,run.map.locked[gate.id] and C.warn or C.green) end
    end
    local occupied = {}
    for _, tower in ipairs(run.towers) do if tower.hp > 0 then occupied[tower.slot_id] = true end end
    for _, slot in ipairs(run.config.build_slots) do
        if (scale>=1.4 or occupied[slot.id]) and inView(slot.x,slot.y) and (not currentRoom or (slot.owner_room_id or run.config.topology.main)==currentRoom) then
        nvgBeginPath(vg); nvgRect(vg, ox + slot.x * scale - 2, oy + slot.y * scale - 2, 4, 4)
        nvgStrokeColor(vg, color(occupied[slot.id] and C.cyan or C.dim)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
        if occupied[slot.id] then nvgFillColor(vg, color(C.cyan)); nvgFill(vg) end
        end
    end
    for _, anchor in pairs(run.anchors or {}) do
        if inView(anchor.x,anchor.y) and (not currentRoom or anchor.room_id==currentRoom or run.anchors[currentRoom]==anchor) then
        local state=Anchors.Status(run,anchor.id)
        local tint=state=='available' and C.green or state=='blocked' and C.orange or C.error
        local x,y=ox+anchor.x*scale,oy+anchor.y*scale
        nvgBeginPath(vg); nvgCircle(vg,x,y,labels and 7 or 5)
        nvgFillColor(vg,color(tint));nvgFill(vg)
        nvgStrokeColor(vg, color(C.ink)); nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
        end
    end
end

---@class DefensePolygonMap : Widget
---@field run table
---@field localMap boolean
local Widget = UI.Widget:Extend("DefensePolygonMap")
function Widget:Init(props)
    UI.Widget.Init(self, props)
    rawset(self,"run",props.run)
    self.localMap = props.localMap == true
    self.zoom,self.panX,self.panY=1,0,0
    local gestures=self.props --[[@as table]]
    gestures.onPanStart=function() return not self.localMap end
    gestures.onPanMove=function(e) self.dragged=true; self.panX=self.panX+e.deltaX; self.panY=self.panY+e.deltaY end
    self.props.onPinchMove=function(e) self.dragged=true; self.zoom=math.max(1,math.min(10,self.zoom*e.scale)) end
end
function Widget:OnWheel(_,dy) self.zoom=math.max(1,math.min(10,self.zoom*(dy>0 and 1.2 or 1/1.2))) end
function MapView.Transform(run,l,localMap,zoom,panX,panY)
    if l.w<=12 or l.h<=12 then return nil end
    local origin, size = run.config.map_origin, run.config.map_size
    local x1, y1, w, h = origin.x, origin.y, size.w, size.h
    if localMap then
        local id = run.map:RoomAt(run.player.x, run.player.y) or run.config.topology.main
        local region = run.map.room_regions[id]
        x1, y1, w, h = region.x1 - 2, region.y1 - 2, region.x2 - region.x1 + 4, region.y2 - region.y1 + 4
    end
    local scale = math.min((l.w - 12) / w, (l.h - 12) / h)*(zoom or 1)
    if scale <= 0 then return nil end
    local ox, oy = l.x + (l.w - w * scale) / 2 - x1 * scale+(panX or 0), l.y + (l.h - h * scale) / 2 - y1 * scale+(panY or 0)
    return ox,oy,scale,x1,y1,w,h
end
function Widget:OnPointerDown(event)
    self.dragged=false
    UI.Widget.OnPointerDown(self,event)
end
function Widget:AnchorAt(x,y)
    local l=self:GetAbsoluteLayout()
    if x<l.x or y<l.y or x>l.x+l.w or y>l.y+l.h then return nil end
    local ox,oy,scale=MapView.Transform(self.run,l,self.localMap,self.zoom,self.panX,self.panY)
    if not scale then return nil end
    local best,distance=nil,14^2
    for id,anchor in pairs(self.run.anchors or {}) do
        local ax,ay=ox+anchor.x*scale,oy+anchor.y*scale
        if ax>=l.x and ay>=l.y and ax<=l.x+l.w and ay<=l.y+l.h then
            local d=(x-ax)^2+(y-ay)^2
            if d<distance or d==distance and (not best or id<best) then best,distance=id,d end
        end
    end
    return best
end
function Widget:OnClick(event)
    if self.localMap or self.dragged or not event then return end
    local id=self:AnchorAt(event.x,event.y)
    if id and self.props.onAnchorClick then self.props.onAnchorClick(id) end
end
function MapView.RenderInLayout(vg, run, l, localMap, zoom, panX, panY)
    local ox,oy,scale,x1,y1,w,h=MapView.Transform(run,l,localMap,zoom,panX,panY)
    if not scale then return end
    nvgSave(vg); nvgIntersectScissor(vg, l.x, l.y, l.w, l.h)
    MapView.Draw(vg, run, ox, oy, scale, not localMap,
        {x1=(l.x-ox)/scale,y1=(l.y-oy)/scale,x2=(l.x+l.w-ox)/scale,y2=(l.y+l.h-oy)/scale},
        localMap and (run.map:RoomAt(run.player.x,run.player.y) or run.current_room_id or run.config.topology.main) or nil)
    local function dot(x, y, c, radius)
        nvgBeginPath(vg); nvgCircle(vg, ox + x * scale, oy + y * scale, radius)
        nvgFillColor(vg, color(c)); nvgFill(vg)
    end
    for _, enemy in ipairs(run.enemies) do
        if enemy.alive and enemy.x>=x1 and enemy.x<=x1+w and enemy.y>=y1 and enemy.y<=y1+h then dot(enemy.x, enemy.y, C.error, 1.5) end
    end
    dot(run.core.x, run.core.y, C.warn, 3)
    dot(run.player.x, run.player.y, C.text, 3)
    nvgRestore(vg)
end
function Widget:Render(vg)
    self:RenderFullBackground(vg)
    return MapView.RenderInLayout(vg, self.run, self:GetAbsoluteLayout(), self.localMap,self.zoom,self.panX,self.panY)
end
MapView.Widget = Widget
return MapView
