local UI = require("urhox-libs/UI")
local Theme = require("defense.Theme")
local C = Theme.C
local Art = {}

local function rgba(color, alpha)
    return nvgRGBA(color[1], color[2], color[3], alpha or color[4] or 255)
end

---@class DefenseEdgeProps : WidgetProps
---@field view? table
---@class DefenseEdge : Widget
---@field props DefenseEdgeProps
---@overload fun(props?: DefenseEdgeProps): DefenseEdge
local Edge = UI.Widget:Extend("DefenseEdge")
---@param props DefenseEdgeProps?
function Edge:Init(props)
    UI.Widget.Init(self --[[@as Widget]], props or {})
end
---@param vg NVGContextWrapper
function Edge:Render(vg)
    local l = self:GetAbsoluteLayout()
    if l.w < 24 or l.h < 24 then return end
    local x, y = math.floor(l.x) + 2.5, math.floor(l.y) + 2.5
    local w, h = math.floor(l.w) - 5, math.floor(l.h) - 5
    local view = self.props.view
    local pulse = view and view.atmosphere or 0.08
    local alpha = view and view.reducedEffects and 110 or math.floor(100 + pulse * 100)
    nvgSave(vg)
    nvgIntersectScissor(vg, l.x, l.y, l.w, l.h)
    nvgBeginPath(vg)
    for _, corner in ipairs({ { x, y, 1, 1 }, { x + w, y, -1, 1 },
        { x, y + h, 1, -1 }, { x + w, y + h, -1, -1 } }) do
        nvgMoveTo(vg, corner[1] + corner[3] * 8, corner[2])
        nvgLineTo(vg, corner[1], corner[2])
        nvgLineTo(vg, corner[1], corner[2] + corner[4] * 8)
    end
    nvgStrokeColor(vg, rgba(C.cyanDim, alpha)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    -- 刻度只占顶边预留的 4px，不扫过读数和正文。
    nvgBeginPath(vg)
    for i = 1, 8 do
        local tx = x + w - 18 - i * 6
        if tx > x + 16 then
            nvgMoveTo(vg, tx, y); nvgLineTo(vg, tx, y + (i % 4 == 0 and 4 or 2))
        end
    end
    nvgStrokeColor(vg, rgba(C.dim, 75)); nvgStroke(vg)
    nvgRestore(vg)
end

---@param props PanelProps
---@param view? table
---@return Panel
function Art.Frame(props, view)
    props.borderWidth = props.borderWidth or 1
    props.borderColor = props.borderColor or C.cyanSoft
    local panel = UI.Panel(props)
    panel:AddChild(Edge { position = "absolute", left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "none", view = view })
    return panel
end

---@class DefenseIconProps : WidgetProps
---@field icon string
---@class DefenseIcon : Widget
---@field props DefenseIconProps
---@field image integer
---@field context NVGContextWrapper?
---@overload fun(props: DefenseIconProps): DefenseIcon
local Icon = UI.Widget:Extend("DefenseIcon")
---@param props DefenseIconProps
function Icon:Init(props)
    props.width, props.height = 32, 32
    props.flexShrink, props.pointerEvents = 0, "none"
    UI.Widget.Init(self --[[@as Widget]], props)
    self.image = -1
    self.context = UI.GetNVGContext and UI.GetNVGContext() or nil
    local path = Theme.ICON_PATHS[props.icon]
    if self.context and path then
        local ok, image = pcall(nvgCreateImage, self.context, path, NVG_IMAGE_NEAREST)
        if ok and type(image) == "number" and image > 0 then self.image = image --[[@as integer]]
        else print("[DefenseUI] 图标不可用，使用几何回退：" .. path) end
    end
end
---@param vg NVGContextWrapper
function Icon:Render(vg)
    local l = self:GetAbsoluteLayout()
    local scale = UI.GetScale and UI.GetScale() or 1
    -- Yoga 按物理像素取整，32基准px的布局可能略小；容忍一物理像素但不缩放母版。
    local rounding = 1 / math.max(0.625, scale) + 0.001
    if l.w <= 0 or l.h <= 0 or l.w < 32 - rounding or l.h < 32 - rounding then return end
    local x, y = math.floor(l.x + (l.w - 32) / 2), math.floor(l.y + (l.h - 32) / 2)
    if self.image > 0 and self.context == vg then
        local w, h = nvgImageSize(vg, self.image)
        if w == 32 and h == 32 then
            nvgBeginPath(vg); nvgRect(vg, x, y, 32, 32)
            nvgFillPaint(vg, nvgImagePattern(vg, x, y, 32, 32, 0, self.image, 1)); nvgFill(vg)
            return
        end
    end
    local function block(dx, dy, w, h, color)
        nvgBeginPath(vg); nvgRect(vg, x + dx, y + dy, w, h)
        nvgFillColor(vg, rgba(color)); nvgFill(vg)
    end
    block(5, 5, 22, 22, C.widget)
    if self.props.icon == "repair" then
        block(8, 14, 16, 4, C.dim); block(14, 8, 4, 16, C.dim)
    elseif self.props.icon == "turret" then
        block(8, 20, 16, 4, C.dim); block(12, 12, 8, 8, C.text); block(15, 7, 3, 8, C.dim)
    else
        block(10, 10, 12, 12, C.dim); block(14, 14, 4, 4, C.cyan)
    end
end
function Icon:Destroy()
    -- View 在 UI.Shutdown 前销毁树；图片仅属于创建它的 UI 上下文。
    if self.image > 0 and self.context and UI.GetNVGContext() == self.context then
        nvgDeleteImage(self.context, self.image)
    end
    self.image, self.context = -1, nil
    UI.Widget.Destroy(self)
end
function Art.CancelInput(root)
    if not UI.Input or not UI.HandlePointerCancel or not UI.PointerEvent then return end
    local function belongs(widget)
        local current = widget
        while current do
            if current == root then return true end
            current = current.parent
        end
        return false
    end
    -- 取消捕获须早于 Destroy；不伪造抬手/点击，也不清除其他界面的指针。
    local ids = { [0] = true }
    local pointers = UI.Input.GetActivePointers()
    for id in pairs(pointers) do ids[id] = true end
    for id in pairs(ids) do
        local pressed = UI.GetPressedWidgetForPointer(id)
        local hovered = UI.GetHoveredWidgetForPointer(id)
        if belongs(pressed) or belongs(hovered) then
            local x, y = UI.Input.GetLastPosition(id)
            local pointer = pointers[id]
            local event = UI.PointerEvent.new(UI.PointerEvent.Types.PointerCancel, {
                pointerId = id, pointerType = pointer and pointer.pointerType or UI.PointerEvent.PointerTypes.Mouse,
                x = x, y = y, buttons = UI.PointerEvent.Buttons.None,
            })
            UI.HandlePointerCancel(event)
        end
    end
    if UI.GetFocus and belongs(UI.GetFocus()) then UI.SetFocus(nil) end
end

Art.Icon = Icon

---@class DefenseGauge : ProgressBar
---@overload fun(props?: ProgressBarProps): DefenseGauge
local Gauge = UI.ProgressBar:Extend("DefenseGauge")
---@param vg NVGContextWrapper
function Gauge:Render(vg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 2 or l.h <= 2 then return end
    local fraction = math.max(0, math.min(1, (self.props.value or 0) / math.max(0.000001, self.props.max or 1)))
    local x, y = math.floor(l.x) + 1, math.floor(l.y) + 1
    local w, h = math.max(0, math.floor(l.w) - 2), math.max(0, math.floor(l.h) - 2)
    local fillWidth = w * fraction
    nvgSave(vg)
    nvgIntersectScissor(vg, l.x, l.y, l.w, l.h)
    nvgBeginPath(vg); nvgRoundedRect(vg, l.x, l.y, l.w, l.h, 3)
    nvgFillColor(vg, rgba(self.props.backgroundColor or C.ink)); nvgFill(vg)
    -- 保留真实比例，末段允许部分填充；分隔只改变表现，不量化生命值。
    for offset = 0, w - 1, 8 do
        local segment = math.min(6, w - offset)
        nvgBeginPath(vg); nvgRect(vg, x + offset, y, segment, h)
        nvgFillColor(vg, rgba(C.widget)); nvgFill(vg)
        local lit = math.min(segment, math.max(0, fillWidth - offset))
        if lit > 0 then
            nvgBeginPath(vg); nvgRect(vg, x + offset, y, lit, h)
            nvgFillColor(vg, rgba(self.props.fillColor or C.cyan)); nvgFill(vg)
        end
    end
    nvgRestore(vg)
end
Art.Gauge = Gauge

---@param icon string
---@param caption string
---@param color? table
---@return Panel
function Art.Heading(icon, caption, color)
    return UI.Panel { width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
        pointerEvents = "none", children = { Icon { icon = icon }, UI.Label { text = caption,
            fontFamily = "pixel", fontSize = 18, fontColor = color or C.text,
            flexGrow = 1, flexShrink = 1, whiteSpace = "normal", maxLines = 2 } } }
end
return Art
