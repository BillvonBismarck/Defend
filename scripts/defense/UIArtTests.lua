-- Dark Tech CPU回归：调用真实UIArt/Theme，只桩Widget边缘与NanoVG接口。
-- 不加载引擎、不验PNG解码/GPU采样/Yoga像素布局或真机可读性；无文件写入。
local A = {}

---@class DefenseArtTestCall
---@field name string
---@field args any[]

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

-- 使用真实库的深合并，防止只检查override而漏掉继承的pill/glow/gradient。
-- 此库是纯Lua；不修改只读库或将测试桩实现当作被测生产模块。
local function withArt(body, options)
    options = options or {}
    ---@type DefenseArtTestCall[]
    local calls = {}
    local globals, savedModules, savedGlobals = {}, {}, {}
    local widget = {}
    local owner = { name = "context-A" }
    local ui = { Widget = widget, context = owner, scale = options.scale or 1 }
    local function record(name, ...) calls[#calls + 1] = { name = name, args = { ... } } end
    function widget:Init(props)
        self.props, self.children = {}, {}
        for key, value in pairs(props or {}) do if key ~= "children" then self.props[key] = value end end
        for _, child in ipairs(props and props.children or {}) do self:AddChild(child) end
    end
    function widget:AddChild(child)
        self.children[#self.children + 1] = child
        child.parent = self
    end
    function widget:GetAbsoluteLayout()
        return self.testLayout or { x = 10.75, y = 20.25, w = self.props.width or 32, h = self.props.height or 32 }
    end
    function widget:Destroy()
        if rawget(self, "destroyed") == true then return end
        self.destroyed = true
        for _, child in ipairs(self.children) do child:Destroy() end
        record("Widget.Destroy", self)
    end
    function widget:Extend(name)
        local class = {}
        return setmetatable(class, { __index = self, __call = function(_, props)
            local instance = setmetatable({ kind = name }, { __index = class })
            instance:Init(props or {})
            return instance
        end })
    end
    for _, kind in ipairs({ "Panel", "Label" }) do
        ui[kind] = function(props)
            local instance = setmetatable({ kind = kind }, { __index = widget })
            instance:Init(props)
            return instance
        end
    end
    ui.ProgressBar = widget:Extend("ProgressBar") -- Gauge继承真实类形状；setter仅为UI边缘记录桩。
    function widget:SetValue(value) self.props.value = value; return self end
    function widget:SetMax(value) self.props.max = value; return self end
    ui.GetNVGContext = function() record("UI.GetNVGContext"); return ui.context end
    ui.GetScale = function() return ui.scale end
    ui.Theme = require("urhox-libs/UI/Core/Theme")
    local oldTheme = ui.Theme.GetTheme()
    local sequence = 0
    globals.NVG_IMAGE_NEAREST = 1 << 5 -- .emmylua/NanoVGEnums.d.lua；断言用枚举，不硬编码flags。
    globals.nvgCreateImage = function(ctx, path, flags)
        record("nvgCreateImage", ctx, path, flags)
        if options.create then return options.create(ctx, path, flags) end
        sequence = sequence + 1
        return 100 + sequence
    end
    globals.nvgImageSize = function(ctx, image)
        record("nvgImageSize", ctx, image)
        if options.imageSize then return options.imageSize(ctx, image) end
        return 32, 32
    end
    globals.nvgImagePattern = function(...)
        record("nvgImagePattern", ...)
        return { imagePaint = true }
    end
    globals.nvgRGBA = function(...) return { ... } end
    for _, name in ipairs({ "nvgDeleteImage", "nvgBeginPath", "nvgRect", "nvgFillPaint", "nvgFillColor", "nvgFill",
        "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgMoveTo", "nvgLineTo", "nvgStrokeColor",
        "nvgStrokeWidth", "nvgStroke", "nvgRoundedRect", "nvgBoxGradient", "nvgLinearGradient", "nvgRadialGradient" }) do
        globals[name] = function(...) record(name, ...) end
    end
    local modules = { ["urhox-libs/UI"] = ui }
    for name, value in pairs(modules) do
        savedModules[name] = { value = package.loaded[name] }
        package.loaded[name] = value
    end
    for _, name in ipairs({ "defense.UIArt", "defense.Theme" }) do
        savedModules[name] = { value = package.loaded[name] }
        package.loaded[name] = nil
    end
    for name, value in pairs(globals) do
        savedGlobals[name] = { value = _G[name] }
        _G[name] = value
    end
    local ok, message = pcall(function()
        body(require("defense.UIArt"), require("defense.Theme"), calls, ui, options)
    end)
    ui.Theme.SetTheme(oldTheme)
    for name, old in pairs(savedModules) do package.loaded[name] = old.value end
    for name, old in pairs(savedGlobals) do _G[name] = old.value end
    if not ok then error(message, 0) end
end

---@param calls DefenseArtTestCall[]
---@param name string
---@return DefenseArtTestCall[]
local function named(calls, name)
    local result = {}
    for _, call in ipairs(calls) do if call.name == name then result[#result + 1] = call end end
    return result
end
---@param calls DefenseArtTestCall[]
---@param name string
---@param index integer
---@return any[]
local function callArgs(calls, name, index)
    return assert(named(calls, name)[index], "缺少实际调用：" .. name .. " #" .. index).args
end
local function equalColor(t, actual, expected, message)
    t:Check(type(actual) == "table", message .. "是RGBA")
    for i = 1, 4 do t:Equal(actual[i], expected[i], message .. "分量" .. i) end
end
local function fallback(t, icon, ctx, calls)
    local before = #named(calls, "nvgRect")
    local ok, message = pcall(function() icon:Render(ctx) end)
    t:Check(ok, "真实Icon.Render回退不可抛异常：" .. tostring(message))
    t:Check(#named(calls, "nvgRect") > before, "回退实际绘制几何，不只检查image字段")
    t:Equal(#named(calls, "nvgImagePattern"), 0, "回退不绘制失效图片")
end
local function luminance(color)
    local function linear(byte)
        local c = byte / 255
        return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * linear(color[1]) + 0.7152 * linear(color[2]) + 0.0722 * linear(color[3])
end
local function contrast(a, b)
    local x, y = luminance(a), luminance(b)
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

-- UI01复用本模块辅助，避免接近1500行的PrototypeTests继续堆叠；仍由真实View树/方法执行。
local function tree(root)
    local result = {}
    local function visit(widget)
        if widget.destroyed then return end
        result[#result + 1] = widget
        for _, child in ipairs(widget.children) do visit(child) end
    end
    visit(root)
    return result
end
local function edgeOf(panel)
    for _, child in ipairs(panel.children) do if child.kind == "DefenseEdge" then return child end end
end
function A.ViewPixel(t, view)
    for _, widget in ipairs(tree(view.root)) do
        if widget.kind == "Label" or widget.kind == "Button" then
            t:Equal(widget.props.fontFamily, "pixel", "UI01真实View/Proto树文字统一pixel：" .. tostring(widget.props.text))
            t:Check(widget.props.fontSize == 13.5 or widget.props.fontSize == 18, "UI01字号只用13.5/18两档")
            if tostring(widget.props.text):find("爆炸推进怪死亡0.7秒后结算", 1, true) then
                t:Equal(widget.props.maxLines, 12, "像素长玩法正文预留12行，HUD明确行限制不受影响")
            end
        end
        t:Equal(widget.props.backgroundGradient, nil, "真实控件不残留旧紫色渐变")
    end
    for _, panel in ipairs({ view.top, view.radarPanel }) do
        local edge = edgeOf(panel)
        t:Check(edge ~= nil, "真实HUD面板接入Art.Frame而不是仅颜色替换")
        t:Equal(edge.props.view, view, "Frame装饰读取该View共享atmosphere")
        t:Equal(edge.props.pointerEvents, "none", "Frame装饰不劫持HUD输入")
    end
    if view.overlayContent then t:Check(edgeOf(view.overlayContent) ~= nil, "真实ModalShell接入Art.Frame") end
    for _, name in ipairs({ "playerHP", "coreHP", "experience", "phase" }) do
        t:Equal(view.bars[name].kind, "DefenseGauge", "全部HUD条实际接入Gauge：" .. name)
    end
    local health = view.labels.playerHP.parent.parent.parent
    t:Equal(view.labels.coreHP.parent.parent.parent, health, "两HP卡共用独立Health行")
    t:Check(view.labels.status.parent ~= health, "status不与两HP卡争同一行宽")
    t:Equal(view.labels.status.parent, view.top, "status直接放顶HUD独立行")
    t:Equal(view.labels.status.props.width, "100%", "状态独占一行宽")
    t:Equal(view.labels.status.props.whiteSpace, "normal", "窄屏状态允许换行")
    t:Equal(view.labels.status.props.maxLines, 2, "状态预留两行")
    t:Equal(health.props.flexWrap, "wrap", "Health行允许两HP卡窄屏换行")
    t:Equal(view.labels.stats.props.maxLines, 2, "波数资金星砂信息允许两行")
    t:Equal(view.labels.stats.props.whiteSpace, "normal", "stats不强制单行挤压")
    if view:Mode() == "menu" then
        for _, button in pairs(view.menuButtons) do
            t:Equal(button.props.minWidth, 170, "风格选项为实测像素文本预留170px")
            t:Equal(button.props.flexBasis, 170, "风格选项基准宽170，窄屏换行不强挤字")
            t:Equal(button.parent.props.flexWrap, "wrap", "菜单战斗风格允许窄屏换行")
        end
    end
    local icons = 0
    for _, widget in ipairs(tree(view.top)) do
        if widget.kind == "DefenseIcon" then
            icons = icons + 1
            t:Equal(widget.props.icon, "core", "HUD核心真正绑定core像素图标")
            t:Equal(widget.props.width, 32, "HUD图标使用32px母版")
            t:Equal(widget.props.pointerEvents, "none", "HUD图标不拦截交互")
        end
    end
    t:Equal(icons, 1, "顶HUD只有一个真实core图标，不用占位文字替代")
end

function A.ViewCurrentFields(t, view, ui, fresh)
    local Expansion, Progression = require("defense.Expansion"), require("defense.Progression")
    local scenarios = { "legacy_v02", "reuse_sample", "large_map_proto", "sanctuary_expansion" }
    for _, size in ipairs({ { w = 390, h = 844 }, { w = 1280, h = 720 } }) do
        ui.viewport = size
        for _, id in ipairs(scenarios) do
            local run = fresh(id)
            if id == "sanctuary_expansion" then t:Equal(Expansion.Sand(run, 27, "ui01_income"), 27, "真实星砂收入夹具") end
            view:SetRun(run); view.menuOpen = false; view:Update(0)
            A.ViewPixel(t, view)
            local suffix = size.w < 560 and "" or " · Lv." .. run.player.level
            local sand = id == "sanctuary_expansion" and " · 星砂 27" or ""
            t:Equal(view.labels.stats.props.text, "第" .. run.wave_id .. "/" .. run.total_waves .. "波 · 资金 " .. run.currency .. sand .. suffix,
                "四场景宽窄HUD资金/波次/星砂/等级字段接线：" .. id)
            t:Near(view.bars.playerHP.props.value, run.player.hp, "角色条读真实HP")
            t:Near(view.bars.coreHP.props.value, run.core.hp, "核心条读真实耐久")
            t:Near(view.bars.experience.props.max, Progression.Threshold(run.player.level), "经验条保留成长阈值")
            t:Near(view.bars.phase.props.value, run.preparation_remaining, "战备条读取真实剩余")
            if id == "sanctuary_expansion" then
                t:Equal(view.labels.status.props.text, "战备探索 15秒 · 基础战备", "神殿基础战备状态不丢失")
                run:EnterPreparation(5)
                view:UpdateHUD()
                t:Equal(view.labels.status.props.text, "战备探索 20秒 · 奖励探索 5秒", "真实奖励窗口保持独立秒数")
                t:Near(view.bars.phase.props.max, 20, "奖励窗口Gauge max使用本波真实总量")
                run:Update(5.25); view:UpdateHUD()
                t:Equal(view.labels.status.props.text, "战备探索 15秒 · 基础战备", "奖励用完退回基础战备，不展示负奖励")
                t:Check(run:RequestWave(), "神殿提前开波走真实Run接口")
                run:Update(2.25); view:Update(0); view:UpdateHUD()
                t:Equal(view.labels.status.props.text, "入口预警 6秒", "8秒独立预警剩余向上取整")
                t:Near(view.bars.phase.props.value, 5.75, "预警Gauge仍保留非整型真实比例")
                t:Near(view.bars.phase.props.max, 8, "预警Gauge最大值独立8秒")
                run:Update(5.75); run:Update(2.25); view:Update(0); view:UpdateHUD()
                t:Equal(run.state, "ATTACK", "真实完成预警后进入战斗")
                t:Equal(view.labels.status.props.text, "守核交战 · 战斗 " .. math.floor(run.attack_elapsed) .. "/" ..
                    math.floor(run.attack_duration) .. "秒 · 残敌 " .. run:AliveCount(), "神殿保留战斗用时/期限/残敌")
                t:Equal(view.bars.phase.props.visible, false, "交战不伪装成战备进度")
                run:Pause("manual"); view:UpdateHUD()
                t:Check(view.labels.status.props.text:find(" · 暂停", 1, true) ~= nil, "暂停状态仍单独反映")
                local clock = run.clock; run:Update(10); view:UpdateHUD()
                t:Near(run.clock, clock, "暂停不增加真实战斗钟")
                run:Resume("manual")
                view:Events(run.events); view:UpdateHUD()
                t:Check(view.labels.causalNotice.props.text:find("星砂 +27 · 余额 27", 1, true) ~= nil, "真实星砂事件接入HUD通知")
                t:Equal(run.exploration_currency, 27, "纯UI刷新不消费星砂")
            else
                t:Check(not view.labels.stats.props.text:find("星砂", 1, true), "非神殿场景不伪造星砂字段")
            end
        end
    end
end

function A.ViewCancelLifecycle(t, view, ui, calls)
    -- 真View.RefreshOverlay/Destroy调用真Art.CancelInput；输入API边缘记录，不替代引擎派发。
    local external = { parent = nil, props = {}, children = {} }
    local active = { [21] = { pointerType = "touch", identity = "modal-finger" },
        [22] = { pointerType = "touch", identity = "external-finger" } }
    local pressed, hovered, cancelled, focus = {}, {}, {}, {}
    ui.Input = { GetActivePointers = function() return active end,
        GetLastPosition = function(id) return id + 0.25, id + 0.75 end }
    ui.PointerEvent = { Types = { PointerCancel = "PointerCancel" }, PointerTypes = { Mouse = "mouse" }, Buttons = { None = 0 },
        new = function(kind, data) data.type = kind; return data end }
    ui.GetPressedWidgetForPointer = function(id) return pressed[id] end
    ui.GetHoveredWidgetForPointer = function(id) return hovered[id] end
    ui.GetFocus = function() return focus[1] end
    ui.SetFocus = function(value) focus[1] = value; calls[#calls + 1] = { name = "UI.SetFocus", args = { value } } end
    local ups, clicks = 0, 0
    ui.HandlePointerUp = function() ups = ups + 1 end
    ui.HandlePointerCancel = function(event)
        local target = pressed[event.pointerId] or hovered[event.pointerId]
        t:Check(target ~= nil and not target.destroyed, "View先取消捕获再销毁目标")
        t:Equal(event.type, "PointerCancel", "View不伪造Up/Click")
        t:Equal(event.buttons, ui.PointerEvent.Buttons.None, "取消无按键状态")
        calls[#calls + 1] = { name = "UI.HandlePointerCancel", args = { event, target } }
        cancelled[event.pointerId] = (cancelled[event.pointerId] or 0) + 1
        pressed[event.pointerId], hovered[event.pointerId] = nil, nil
    end
    view:RefreshOverlay("pause")
    local oldPanel = view.overlayContent
    local capture = assert(tree(oldPanel)[2], "真实模态内容树必须存在")
    capture.props.onClick = function() clicks = clicks + 1 end
    pressed[21], hovered[0], pressed[22], focus[1] = capture, oldPanel, external, capture
    local identity, before = active[21], #calls
    view:RefreshOverlay("rules")
    t:Equal(cancelled[21], 1, "真实切模态取消自己的touch捕获")
    t:Equal(cancelled[0], 1, "真实切模态取消mouse悬停")
    t:Equal(cancelled[22], nil, "真实切模态保留外部界面指针")
    t:Equal(pressed[22], external, "外部pressed身份未被清除")
    t:Equal(active[21], identity, "切模态保留Input的active pointer身份")
    t:Equal(focus[1], nil, "切模态清自身焦点")
    t:Check(oldPanel.destroyed, "切模态真正销毁旧Frame树")
    local firstDestroy, lastCancel = math.huge, 0
    for i = before + 1, #calls do
        if calls[i].name == "Widget.Destroy" then firstDestroy = math.min(firstDestroy, i) end
        if calls[i].name == "UI.HandlePointerCancel" then lastCancel = i end
    end
    t:Check(lastCancel > before and lastCancel < firstDestroy, "全部取消早于第一个旧树Destroy")
    local count = #calls; view:RefreshOverlay("rules")
    t:Equal(#calls, count, "相同结构key不重建/不重复取消")
    pressed[21], hovered[0], focus[1] = view.buttons.pause, view.top, view.buttons.pause
    view:Destroy()
    t:Equal(cancelled[21], 2, "真实Destroy取消根树touch捕获")
    t:Equal(cancelled[0], 2, "真实Destroy取消根树mouse悬停")
    t:Equal(cancelled[22], nil, "Destroy仍保留外部指针")
    t:Equal(ups, 0, "整个View生命周期不派发伪Up")
    t:Equal(clicks, 0, "整个View生命周期取消不触发业务点击")
    t:Equal(ui.GetRoot(), nil, "取消后才卸载根树")
    local finished = #calls; view:Destroy()
    t:Equal(#calls, finished, "重复View.Destroy幂等")
end

function A.ViewFixtureIsolation(t, presentation)
    local names = { "defense.View", "defense.ProtoView", "defense.Radar", "defense.UIArt", "defense.Theme", "urhox-libs/UI" }
    local original = {}
    for _, name in ipairs(names) do original[name] = { value = package.loaded[name] } end
    local oldRect, previous = _G.nvgRect, {}
    presentation(function(_, _, _, ui)
        previous.ui, previous.art = ui, require("defense.UIArt")
        local icon = previous.art.Icon { icon = "core" }
        t:Equal(icon.kind, "DefenseIcon", "第一presentation夹具真Icon可构造")
        icon:Destroy()
    end)
    presentation(function(_, _, _, ui)
        local art = require("defense.UIArt")
        t:Check(ui ~= previous.ui and art ~= previous.art, "presentation真Art类绑定当前新UI，不复用第一夹具")
        local gauge = art.Gauge { value = 0.25, max = 0.5 }
        t:Equal(gauge.kind, "DefenseGauge", "第二presentation的ProgressBar支持真实Gauge继承")
        gauge:Destroy()
    end)
    local ok, message = pcall(function()
        presentation(function() require("defense.UIArt"); error("expected_presentation_fixture_failure") end)
    end)
    t:Equal(ok, false, "presentation故意异常真正抛错")
    t:Check(tostring(message):find("expected_presentation_fixture_failure", 1, true) ~= nil, "异常不由加载失败伪造")
    for _, name in ipairs(names) do t:Equal(package.loaded[name], original[name].value, "presentation成功/异常都恢复原缓存：" .. name) end
    t:Equal(_G.nvgRect, oldRect, "presentation成功/异常都恢复NVG全局")
end

function A.Register(case)
    case("UIART_ICON_LIFECYCLE", function(t)
        withArt(function(Art, Theme, calls, ui)
            for _, key in ipairs({ "core", "turret", "repair" }) do
                local createsBefore = #named(calls, "nvgCreateImage")
                local icon = Art.Icon { icon = key, width = 96, height = 80, pointerEvents = "auto", flexShrink = 1 }
                t:Equal(#named(calls, "nvgCreateImage"), createsBefore + 1, "每个真实Icon只在Init加载一次")
                local create = callArgs(calls, "nvgCreateImage", createsBefore + 1)
                t:Equal(create[1], ui.context, "Init使用UI拥有的NVG上下文")
                t:Equal(create[2], Theme.ICON_PATHS[key], "使用真实Theme图标资源路径")
                t:Check(create[2]:sub(1, 6) == "image/", "不误加assets资源根前缀")
                t:Equal(create[3], NVG_IMAGE_NEAREST, "nvgCreateImage使用NEAREST，不走线性采样")
                t:Equal(icon.props.width, 32, "外部宽度被固定为32")
                t:Equal(icon.props.height, 32, "外部高度被固定为32")
                t:Equal(icon.props.flexShrink, 0, "像素图标不允许flex收缩")
                t:Equal(icon.props.pointerEvents, "none", "图标装饰不拦截点击")
                icon.testLayout = { x = 10.75, y = 20.25, w = 40, h = 40 }
                local patternsBefore = #named(calls, "nvgImagePattern")
                for _ = 1, 12 do icon:Render(ui.context) end
                t:Equal(#named(calls, "nvgCreateImage"), createsBefore + 1, "多次真实Render不重加载图片")
                t:Equal(#named(calls, "nvgImagePattern"), patternsBefore + 12, "每次Render实际绘图片")
                local pattern = callArgs(calls, "nvgImagePattern", patternsBefore + 1)
                t:Equal(pattern[1], ui.context, "绘制上下文匹配拥有者")
                t:Equal(pattern[2], 14, "32图居中后X对齐整数像素")
                t:Equal(pattern[3], 24, "32图居中后Y对齐整数像素")
                t:Equal(pattern[4], 32, "图片paint宽32，不拉伸")
                t:Equal(pattern[5], 32, "图片paint高32，不拉伸")
                t:Equal(pattern[6], 0, "像素图标不旋转")
                t:Equal(pattern[7], icon.image, "paint复用本实例拥有句柄")
                t:Equal(pattern[8], 1, "图片原色不透明绘制")
                local rect = callArgs(calls, "nvgRect", #named(calls, "nvgRect"))
                t:Equal(rect[4], 32, "实际绘制矩形宽32")
                t:Equal(rect[5], 32, "实际绘制矩形高32")
                local image = icon.image
                local deletesBefore = #named(calls, "nvgDeleteImage")
                icon:Destroy(); icon:Destroy()
                t:Equal(#named(calls, "nvgDeleteImage"), deletesBefore + 1, "重复Destroy不双删")
                local deletion = callArgs(calls, "nvgDeleteImage", deletesBefore + 1)
                t:Equal(deletion[1], ui.context, "delete只发生在原拥有上下文")
                t:Equal(deletion[2], image, "Destroy释放自己的句柄")
                t:Equal(icon.image, -1, "释放后重置句柄")
                t:Equal(icon.context, nil, "释放后清上下文引用")
            end
            t:Equal(#named(calls, "nvgImageSize"), 36, "所有正常Render实读图片尺寸")
            local a, b = Art.Icon { icon = "core" }, Art.Icon { icon = "core" }
            t:Check(a.image ~= b.image, "同资源的两个实例各自拥有图片句柄")
            a:Destroy()
            local before = #named(calls, "nvgImagePattern")
            b:Render(ui.context)
            t:Equal(#named(calls, "nvgImagePattern"), before + 1, "销毁一实例不破坏另一实例绘制")
            b:Destroy()
        end)
    end)

    case("UIART_ICON_FAILURE_FALLBACK", function(t)
        for _, mode in ipairs({ "throw", "zero", "negative", "nil", "string" }) do
            withArt(function(Art, _, calls, ui)
                local icon = Art.Icon { icon = "repair" }
                t:Equal(icon.image, -1, "加载失败/无效返回不保留句柄：" .. mode)
                for _ = 1, 3 do fallback(t, icon, ui.context, calls) end
                t:Equal(#named(calls, "nvgCreateImage"), 1, "失败只尝试Init一次，Render不重试")
                icon:Destroy(); icon:Destroy()
                t:Equal(#named(calls, "nvgDeleteImage"), 0, "未拥有图片不可delete")
            end, { create = function()
                if mode == "throw" then error("expected_image_loader_failure") end
                if mode == "zero" then return 0 end
                if mode == "negative" then return -1 end
                if mode == "string" then return "101" end
                return nil
            end })
        end
        for _, size in ipairs({ { 64, 64 }, { 32, 64 }, { 64, 32 }, { 0, 0 } }) do
            withArt(function(Art, _, calls, ui)
                local icon = Art.Icon { icon = "turret" }
                fallback(t, icon, ui.context, calls)
                t:Equal(#named(calls, "nvgImageSize"), 1, "真实Render检查尺寸后回退")
                t:Equal(#named(calls, "nvgCreateImage"), 1, "错误尺寸不触发重加载")
                icon:Destroy()
                t:Equal(#named(calls, "nvgDeleteImage"), 1, "已拥有但尺寸错误仍须释放")
            end, { imageSize = function() return size[1], size[2] end })
        end
        withArt(function(Art, _, calls, ui)
            local icon = Art.Icon { icon = "unknown" }
            fallback(t, icon, ui.context, calls)
            t:Equal(#named(calls, "nvgCreateImage"), 0, "未映射图标不猜测路径")
            icon:Destroy()
            ui.context = nil
            local noContext = Art.Icon { icon = "core" }
            fallback(t, noContext, {}, calls)
            t:Equal(#named(calls, "nvgCreateImage"), 0, "无ctx时不加载")
            noContext:Destroy()
            ui.GetNVGContext = nil
            local legacyStub = Art.Icon { icon = "core" }
            fallback(t, legacyStub, {}, calls)
            legacyStub:Destroy()
            t:Equal(#named(calls, "nvgDeleteImage"), 0, "旧UI桩无getter时安全几何回退")
        end)
    end)

    case("UIART_ICON_CONTEXT_BOUNDARY", function(t)
        withArt(function(Art, _, calls, ui)
            local oldContext = ui.context
            local icon = Art.Icon { icon = "core" }
            ui.context = { name = "context-B" }
            for _ = 1, 3 do fallback(t, icon, ui.context, calls) end
            t:Equal(#named(calls, "nvgImageSize"), 0, "异ctx不可查询旧图尺寸")
            t:Equal(#named(calls, "nvgCreateImage"), 1, "异ctxRender不重建/偷换拥有者")
            icon:Destroy(); icon:Destroy()
            t:Equal(#named(calls, "nvgDeleteImage"), 0, "旧拥有ctx失效后不可delete到新ctx")
            local current = Art.Icon { icon = "repair" }
            current:Render(ui.context)
            t:Equal(#named(calls, "nvgImagePattern"), 1, "新ctx新建实例正常绘图")
            current:Destroy()
            t:Equal(callArgs(calls, "nvgDeleteImage", 1)[1], ui.context, "新实例只delete新ctx自己的图")
            ui.context = oldContext
            local other = Art.Icon { icon = "core" }
            local otherImage = other.image
            local paints = #named(calls, "nvgImagePattern")
            other:Render({ name = "foreign-render-context" })
            t:Equal(#named(calls, "nvgImagePattern"), paints, "仅Render参数异ctx也不画旧图片")
            other:Destroy()
            t:Equal(callArgs(calls, "nvgDeleteImage", 2)[1], oldContext, "仍有效owner释放归owner而非Render参数")
            t:Equal(callArgs(calls, "nvgDeleteImage", 2)[2], otherImage, "owner释放确属自己句柄")
            local small = Art.Icon { icon = "core" }
            small.testLayout = { x = 0, y = 0, w = 28, h = 32 }
            local before = #calls
            small:Render(ui.context)
            t:Equal(#calls, before, "28px明显空间不足退出，不误用Yoga取整容差")
            small:Destroy()
        end)
    end)

    case("UIART_ICON_LAYOUT_ROUNDING", function(t)
        -- 输入来自Yoga取整后的基准px，验生产Render容差；不调用/模拟Yoga布局器。
        for _, sample in ipairs({ { scale = 2.20794, extent = 31.704 }, { scale = 0.625, extent = 30.5 } }) do
            withArt(function(Art, _, calls, ui)
                t:Near(ui.GetScale(), sample.scale, "真实Render能读取当前缩放输入")
                local icon = Art.Icon { icon = "core" }
                icon.testLayout = { x = 10.75, y = 20.25, w = sample.extent, h = sample.extent }
                for _ = 1, 3 do icon:Render(ui.context) end
                t:Equal(#named(calls, "nvgImagePattern"), 3, "Yoga取整略小尺寸仍实际绘图片")
                t:Equal(#named(calls, "nvgImageSize"), 3, "允许取整误差仍校验图片原尺寸")
                for _, pattern in ipairs(named(calls, "nvgImagePattern")) do
                    t:Equal(pattern.args[4], 32, "容差只控制可绘性，paint宽仍32")
                    t:Equal(pattern.args[5], 32, "容差只控制可绘性，paint高仍32")
                    t:Equal(pattern.args[7], icon.image, "取整容差仍复用自己句柄")
                end
                for _, rect in ipairs(named(calls, "nvgRect")) do
                    t:Equal(rect.args[4], 32, "实际绘制矩形不缩小宽")
                    t:Equal(rect.args[5], 32, "实际绘制矩形不缩小高")
                end
                t:Equal(#named(calls, "nvgCreateImage"), 1, "取整边界重复Render不重载")
                local threshold = 32 - (1 / math.max(0.625, sample.scale) + 0.001)
                for _, extent in ipairs({ { w = threshold - 0.01, h = 32 }, { w = 32, h = threshold - 0.01 },
                    { w = 0, h = 32 }, { w = 32, h = 0 } }) do
                    icon.testLayout = { x = 0, y = 0, w = extent.w, h = extent.h }
                    local before = #calls
                    icon:Render(ui.context)
                    t:Equal(#calls, before, "宽/高超过取整容差或零尺寸立即退出")
                end
                icon:Destroy(); icon:Destroy()
                t:Equal(#named(calls, "nvgDeleteImage"), 1, "取整边界不改变图片生命周期")
            end, { scale = sample.scale })
        end
    end)

    case("UIART_POINTER_CANCEL", function(t)
        withArt(function(Art, _, calls, ui)
            local clicks, ups = 0, 0
            local child = ui.Panel { children = { ui.Label { text = "捕获中的Slider" } }, onClick = function() clicks = clicks + 1 end }
            local root = ui.Panel { children = { child } }
            local external = ui.Panel { children = { ui.Label { text = "其他界面" } } }
            local pressed = { [0] = child, [21] = child.children[1], [23] = external.children[1] }
            local hovered = { [0] = child, [21] = child, [22] = root, [23] = external }
            local active = { [21] = { pointerType = "touch", identity = "finger-A" },
                [22] = { pointerType = "touch", identity = "finger-B" },
                [23] = { pointerType = "touch", identity = "external-finger" },
                [24] = { pointerType = "pen", identity = "uncaptured-pen" } }
            local identities, originalFields = {}, copy(active)
            for id, pointer in pairs(active) do identities[id] = pointer end
            ui.Input = { GetActivePointers = function() return active end,
                GetLastPosition = function(id) return id + 0.25, id + 0.75 end }
            ui.PointerEvent = { Types = { PointerCancel = "PointerCancel" }, PointerTypes = { Mouse = "mouse" }, Buttons = { None = 0 },
                new = function(kind, data)
                    data.type = kind
                    calls[#calls + 1] = { name = "PointerEvent.new", args = { kind, data } }
                    return data
                end }
            ui.GetPressedWidgetForPointer = function(id) return pressed[id] end
            ui.GetHoveredWidgetForPointer = function(id) return hovered[id] end
            local cancelled = {}
            ui.HandlePointerCancel = function(event)
                t:Equal(root.destroyed, nil, "Cancel必须在root释放前")
                t:Check((pressed[event.pointerId] or hovered[event.pointerId]).destroyed ~= true, "Cancel目标仍有有效节点")
                calls[#calls + 1] = { name = "UI.HandlePointerCancel", args = { event } }
                cancelled[event.pointerId] = (cancelled[event.pointerId] or 0) + 1
                pressed[event.pointerId], hovered[event.pointerId] = nil, nil
            end
            ui.HandlePointerUp = function() ups = ups + 1 end
            local focus, focusClears = child.children[1], 0
            ui.GetFocus = function() return focus end
            ui.SetFocus = function(value) focus = value; focusClears = focusClears + 1 end
            Art.CancelInput(root)
            for _, id in ipairs({ 0, 21, 22 }) do
                t:Equal(cancelled[id], 1, "只取消自己的mouse/pressed-touch/hover-only-touch：" .. id)
                t:Equal(pressed[id], nil, "自己的pressed捕获清理")
                t:Equal(hovered[id], nil, "自己的hover捕获清理")
            end
            t:Equal(cancelled[23], nil, "外界界面的指针不取消")
            t:Equal(cancelled[24], nil, "没有当前root捕获的active pointer不取消")
            t:Equal(pressed[23], external.children[1], "外界pressed保持")
            t:Equal(hovered[23], external, "外界hover保持")
            t:Equal(focus, nil, "root所属focus清理")
            t:Equal(focusClears, 1, "focus仅清理一次")
            t:Equal(ups, 0, "不伪造PointerUp")
            t:Equal(clicks, 0, "取消不触发业务onClick")
            t:Equal(#named(calls, "PointerEvent.new"), 3, "每个取消均构造PointerCancel")
            for _, call in ipairs(named(calls, "PointerEvent.new")) do
                local event = call.args[2]
                t:Equal(call.args[1], ui.PointerEvent.Types.PointerCancel, "仅创建cancel事件，不up/click")
                t:Equal(event.pointerType, event.pointerId == 0 and "mouse" or "touch", "mouse缺省与touch类型保留")
                t:Near(event.x, event.pointerId + 0.25, "取消采用最后指针X")
                t:Near(event.y, event.pointerId + 0.75, "取消采用最后指针Y")
                t:Equal(event.buttons, ui.PointerEvent.Buttons.None, "cancel不携带pressed buttons")
            end
            t:Equal(ui.Input.GetActivePointers(), active, "不替换Input active pointer表")
            t:Equal(active[0], nil, "为mouse0取消不伪造active mouse身份")
            for id, pointer in pairs(identities) do
                t:Equal(active[id], pointer, "不移除/替换active pointer身份：" .. id)
                t:Equal(active[id].identity, originalFields[id].identity, "不更改active pointer身份字段")
                t:Equal(active[id].pointerType, originalFields[id].pointerType, "不更改Input active pointer类型")
            end
            focus = external.children[1]
            Art.CancelInput(root)
            t:Equal(#named(calls, "UI.HandlePointerCancel"), 3, "重复取消不再次取消已清捕获")
            t:Equal(focus, external.children[1], "外界focus不清理")
            t:Equal(focusClears, 1, "外界focus不调用SetFocus")
            root:Destroy()
            t:Check(child.destroyed and root.destroyed, "取消后才销毁所属树")
            t:Equal(calls[6].name, "UI.HandlePointerCancel", "三次cancel均先于第一个Destroy")
            external:Destroy()
            ui.Input = nil
            t:Check(pcall(Art.CancelInput, root), "旧UI桩没有Input时CancelInput安全返回")
        end)
    end)

    case("UIART_FRAME_CLIP_ATMOSPHERE", function(t)
        withArt(function(Art, Theme, calls, ui)
            local view = { atmosphere = Theme.Atmosphere(0), reducedEffects = false }
            local content = ui.Label { text = "正文仍可交互的父容器内容" }
            local frame = Art.Frame({ width = 200, height = 80, children = { content }, pointerEvents = "box-none" }, view)
            t:Equal(#frame.children, 2, "Frame保留原内容并恰加一Edge")
            t:Equal(frame.children[1], content, "Frame不替换内容树")
            t:Equal(frame.props.pointerEvents, "box-none", "装饰不改变父容器交互策略")
            t:Equal(frame.props.borderWidth, 1, "默认细边框1px")
            equalColor(t, frame.props.borderColor, Theme.C.cyanSoft, "默认边色低强度酸青")
            local edge = frame.children[2]
            t:Equal(edge.kind, "DefenseEdge", "调用真实Widget扩展Edge")
            t:Equal(edge.props.pointerEvents, "none", "Edge不拦截正文与按钮点击")
            t:Equal(edge.props.position, "absolute", "Edge不占flex布局流")
            for _, key in ipairs({ "left", "right", "top", "bottom" }) do t:Equal(edge.props[key], 0, "Edge贴容器" .. key) end
            t:Equal(edge.props.view, view, "Edge持有共享view而非自己的动画钟")
            edge.testLayout = { x = 10.75, y = 20.25, w = 200, h = 80 }
            edge:Render(ui.context)
            t:Equal(calls[1].name, "nvgSave", "Edge绘制先保存状态")
            t:Equal(calls[2].name, "nvgIntersectScissor", "Edge先相交裁剪保留祖先scissor")
            local scissor = calls[2].args
            t:Equal(scissor[1], ui.context, "裁剪使用本次渲染ctx")
            for i, expected in ipairs({ 10.75, 20.25, 200, 80 }) do t:Equal(scissor[i + 1], expected, "裁剪边界" .. i) end
            t:Equal(calls[#calls].name, "nvgRestore", "Edge绘制后还原祖先状态")
            for _, call in ipairs(calls) do
                if call.name == "nvgMoveTo" or call.name == "nvgLineTo" then
                    t:Check(call.args[2] >= 10.75 and call.args[2] <= 210.75, "角标/刻度X在容器边界内")
                    t:Check(call.args[3] >= 20.25 and call.args[3] <= 100.25, "角标/刻度Y在容器边界内")
                end
                if call.name == "nvgStrokeWidth" then t:Equal(call.args[2], 1, "装饰也是1px细线") end
            end
            local firstAlpha = callArgs(calls, "nvgStrokeColor", 1)[2][4]
            t:Equal(firstAlpha, math.floor(100 + view.atmosphere * 100), "Edge读取共享atmosphere")
            view.atmosphere = 0.5
            edge:Render(ui.context)
            t:Equal(callArgs(calls, "nvgStrokeColor", 3)[2][4], 150, "共享view更新后Render立刻使用新值")
            view.reducedEffects = true
            edge:Render(ui.context)
            t:Equal(callArgs(calls, "nvgStrokeColor", 5)[2][4], 110, "低动效固定弱强度，不自行追逐动画")
            t:Equal(#named(calls, "nvgSave"), #named(calls, "nvgRestore"), "重复Render裁剪状态平衡")
            for _, name in ipairs({ "nvgBoxGradient", "nvgLinearGradient", "nvgRadialGradient", "nvgRoundedRect" }) do
                t:Equal(#named(calls, name), 0, "Edge不用发光/渐变/额外胶囊：" .. name)
            end
            local override = Art.Frame({ borderWidth = 0, borderColor = Theme.C.error, children = {} }, view)
            t:Equal(override.props.borderWidth, 0, "显式无边框不被默认覆盖")
            equalColor(t, override.props.borderColor, Theme.C.error, "显式边色保留")
            edge.testLayout = { x = 0, y = 0, w = 23, h = 80 }
            local before = #calls
            edge:Render(ui.context)
            t:Equal(#calls, before, "窄框不绘溢出装饰")
            frame:Destroy(); override:Destroy()
            t:Check(content.destroyed and edge.destroyed, "Frame销毁内容与装饰子树")
        end)
    end)

    case("UIART_GAUGE_SEGMENTS", function(t)
        withArt(function(Art, Theme, calls, ui)
            local fill = { 73, 91, 109, 127 }
            local gauge = Art.Gauge { width = 37, height = 9, value = 12.5, max = 35, fillColor = fill }
            t:Equal(gauge.kind, "DefenseGauge", "Gauge真实继承ProgressBar扩展类")
            t:Equal(rawget(Art.Gauge, "Init"), nil, "Gauge不覆盖ProgressBar构造器")
            t:Equal(rawget(Art.Gauge, "SetValue"), nil, "Gauge不覆盖继承的数值setter")
            t:Equal(rawget(Art.Gauge, "SetMax"), nil, "Gauge不覆盖继承的上限setter")
            gauge.testLayout = { x = 10.75, y = 20.25, w = 37.9, h = 9.9 }
            local function render(value, maximum, expectedWidths)
                gauge:SetMax(maximum); gauge:SetValue(value)
                local before, props = #calls, copy(gauge.props)
                gauge:Render(ui.context)
                t:Equal(gauge.props.value, props.value, "真实Render不量化/写回value")
                t:Equal(gauge.props.max, props.max, "真实Render不更改上限")
                local lit, tracks, lastRect = {}, {}, {}
                for i = before + 1, #calls do
                    local call = calls[i]
                    if call.name == "nvgRect" then lastRect = call.args end
                    if call.name == "nvgFillColor" then
                        local color = call.args[2]
                        if color[1] == fill[1] then lit[#lit + 1] = lastRect end
                        if color[1] == Theme.C.widget[1] then tracks[#tracks + 1] = lastRect end
                    end
                end
                t:Equal(calls[before + 1].name, "nvgSave", "Gauge先保存祖先NVG状态")
                t:Equal(calls[before + 2].name, "nvgIntersectScissor", "Gauge采用相交裁剪不覆盖祖先")
                local scissor = calls[before + 2].args
                for i, expected in ipairs({ 10.75, 20.25, 37.9, 9.9 }) do t:Near(scissor[i + 1], expected, "Gauge裁剪原布局" .. i) end
                t:Equal(calls[#calls].name, "nvgRestore", "Gauge结束恢复祖先裁剪")
                t:Equal(#tracks, 5, "35px内宽使用8px节奏，最后3px轨道保留")
                for i, rect in ipairs(tracks) do
                    t:Near(rect[2], 11 + (i - 1) * 8, "轨道X每8px一段")
                    t:Near(rect[3], 21, "轨道Y整数像素")
                    t:Near(rect[4], i == 5 and 3 or 6, "轨道保留2px分隔和末段裁剪")
                    t:Near(rect[5], 7, "轨道高度扣除两边1px")
                end
                t:Equal(#lit, #expectedWidths, "亮段数量来自真实连续比例")
                for i, width in ipairs(expectedWidths) do
                    t:Near(lit[i][2], 11 + (i - 1) * 8, "亮段对齐对应轨道")
                    t:Near(lit[i][4], width, "非8px倍数末段仍部分填充")
                    t:Check(lit[i][2] + lit[i][4] <= 46, "亮段不越内宽")
                end
                return lit
            end
            render(12.5, 35, { 6, 4.5 }) -- 连续截止到12.5px，不向段边界量化。
            render(12.75, 35, { 6, 4.75 })
            render(7, 35, { 6 }); render(8.25, 35, { 6, 0.25 }) -- 分隔内不伪造新亮段。
            render(0, 35, {}); render(-10, 35, {})
            render(35, 35, { 6, 6, 6, 6, 3 }); render(350, 35, { 6, 6, 6, 6, 3 })
            render(0.25, 0.5, { 6, 6, 1.5 }); render(0.5, 0.5, { 6, 6, 6, 6, 3 })
            render(0, 0, {}); render(0.5, 0, { 6, 6, 6, 6, 3 })
            render(-0.5, -5, {}); render(0.5, -5, { 6, 6, 6, 6, 3 }) -- 非正max防除零，绘制仍钳0..1。
            for _, extent in ipairs({ { 0, 9 }, { 2, 9 }, { 37, 0 }, { 37, 2 } }) do
                gauge.testLayout = { x = 10, y = 20, w = extent[1], h = extent[2] }
                local before = #calls; gauge:Render(ui.context)
                t:Equal(#calls, before, "无正内宽/高立即退出，不绘负尺寸")
            end
            local plain = Art.Gauge { value = 1, max = 1 }
            plain.testLayout = { x = 0, y = 0, w = 10, h = 4 }
            plain:Render(ui.context)
            equalColor(t, callArgs(calls, "nvgFillColor", #named(calls, "nvgFillColor"))[2], Theme.C.cyan, "缺省亮段使用酸青")
            t:Equal(#named(calls, "nvgSave"), #named(calls, "nvgRestore"), "所有Gauge调用保持save/restore平衡")
            for _, name in ipairs({ "nvgLinearGradient", "nvgRadialGradient", "nvgBoxGradient" }) do
                t:Equal(#named(calls, name), 0, "分段条不采用渐变/发光")
            end
            gauge:Destroy(); plain:Destroy()
        end)
        print("[UIART_GAUGE证据边界] 真实Gauge.Render与CPU矩形/裁剪调用；setter为Widget边缘桩，不验引擎ProgressBar过渡、实际GPU或视觉比例感知")
    end)

    case("UIART_THEME_DARKTECH", function(t)
        withArt(function(Art, Theme, _, ui)
            local baseBefore = copy(ui.Theme.defaultTheme)
            local theme = Theme.Create()
            ui.Theme.SetTheme(theme)
            equalColor(t, theme.colors.primary, { 0, 229, 208, 255 }, "主操作采用酸青")
            equalColor(t, theme.colors.success, theme.colors.primary, "成功语义也采用酸青")
            equalColor(t, theme.colors.text, Theme.C.text, "正文保持浅色")
            for _, key in ipairs({ "background", "surface", "surfaceAlt" }) do
                t:Check(luminance(theme.colors[key]) < 0.03, "暗色科技基底：" .. key)
                t:Check(contrast(theme.colors.text, theme.colors[key]) >= 7, "正文RGB对比度至少7:1：" .. key)
                t:Check(contrast(theme.colors.textSecondary, theme.colors[key]) >= 4.5, "辅助正文RGB对比度至少4.5:1：" .. key)
            end
            t:Check(contrast(Theme.C.ink, theme.colors.primary) >= 7, "主按钮深色字在酸青上保持高对比")
            local function noEffects(value, path)
                for key, item in pairs(value) do
                    local name = tostring(key):lower()
                    t:Check(not name:find("gradient", 1, true) and not name:find("glow", 1, true), "合并后的主题无渐变/发光：" .. path .. "." .. tostring(key))
                    if key == "shadowBlur" then t:Equal(item, 0, "合并主题无软阴影发光") end
                    if key == "borderRadius" then t:Check(type(item) == "number" and item <= 10, "组件小圆角而非pill：" .. path) end
                    if type(item) == "table" then noEffects(item, path .. "." .. tostring(key)) end
                end
            end
            noEffects(theme, "theme")
            for key, radius in pairs(theme.radius) do t:Check(radius <= 11, "所有radius（含full）不继承9999胶囊：" .. key) end
            local button = ui.Theme.ComponentStyle("Button")
            t:Equal(button.borderWidth, 1, "主题按钮使用1px边框")
            t:Equal(button.borderRadius, 4, "主题按钮使用小圆角")
            t:Equal(button.shadowBlur, 0, "按钮实际合并样式禁发光")
            t:Equal(button.fontFamily, "pixel", "操作按钮使用像素字体")
            t:Equal(ui.Theme.ComponentStyle("Label").fontFamily, "pixel", "正文Label默认也为pixel")
            t:Near(ui.Theme.ComponentStyle("Label").fontSize, 13.5, "正文默认为13.5pt像素档")
            t:Near(button.fontSize, 13.5, "按钮默认为13.5pt像素档")
            t:Equal(ui.Theme.FontFamily(), "pixel", "全局默认字体为pixel")
            t:Equal(theme.typography.fontFamily, "pixel", "typography不再回退sans")
            t:Equal(theme.componentDefaults.fontFamily, "pixel", "组件默认字体统一pixel")
            for _, sample in ipairs({ { -1, 13.5 }, { 0, 13.5 }, { 9, 13.5 }, { 13.4999, 13.5 },
                { 13.5, 13.5 }, { 13.5001, 18 }, { 14, 18 }, { 18, 18 }, { 100, 18 } }) do
                t:Near(Theme.TextSize(sample[1]), sample[2], "真实TextSize阈值含等号：" .. sample[1])
            end
            for _, name in ipairs({ "h1", "h2", "h3", "body", "bodySmall", "caption" }) do
                t:Near(theme.typography[name].fontSize, name:sub(1, 1) == "h" and 18 or 13.5, "语义字号两档：" .. name)
            end
            t:Equal(ui.Theme.FontFace("sans", "normal"), "sans", "sans正文font face可正常解析")
            t:Equal(ui.Theme.FontFace("pixel", "normal"), "pixel", "像素标题font face可正常解析")
            local fonts = {}
            for _, font in ipairs(theme.fonts) do fonts[font.family] = font.weights end
            t:Check(fonts.sans ~= nil and fonts.pixel ~= nil, "实际主题同时注册sans和pixel")
            t:Equal(fonts.sans.normal, "Fonts/MiSans-Regular.ttf", "保留可读中文正文MiSans")
            t:Equal(fonts.pixel.normal, "Fonts/zpix.ttf", "标题像素字体路径明确")
            local heading = Art.Heading("core", "据点标题")
            t:Equal(heading.children[1].kind, "DefenseIcon", "Heading使用真实32像素Icon而非emoji占位")
            t:Equal(heading.children[2].props.fontFamily, "pixel", "Heading是像素标题")
            t:Equal(heading.children[2].props.flexShrink, 1, "Heading文本窄屏可收缩")
            t:Equal(heading.children[2].props.whiteSpace, "normal", "Heading文字可换行")
            t:Equal(heading.props.pointerEvents, "none", "标题装饰不拦截交互")
            heading:Destroy()
            t:Equal(ui.Theme.defaultTheme.radius.full, baseBefore.radius.full, "Theme.Create不修改只读基主题胶囊值")
            equalColor(t, ui.Theme.defaultTheme.colors.primary, baseBefore.colors.primary, "Theme.Create不篡改基主题颜色")
            local first, second = Theme.Create(), Theme.Create()
            first.radius.full = 1
            t:Equal(second.radius.full, theme.radius.full, "多次Create返回独立的可变radius")
            for _, elapsed in ipairs({ 0, 1, 10, 100, 1000 }) do
                local pulse = Theme.Atmosphere(elapsed)
                t:Check(pulse >= 0.08 and pulse <= 0.14, "实际共享呼吸计算始终低幅度")
                t:Equal(Theme.Atmosphere(elapsed), pulse, "共享呼吸对相同时间确定性")
            end
        end)
        print("[UIART证据边界] 真实UIArt/Theme.Create/Theme.Atmosphere + CPU调用桩；RGB对比度不等于透明合成/实际字体/屏幕可读性，NEAREST只验传参不验GPU")
    end)

    case("UIART_STUB_ISOLATION", function(t)
        local oldArt, oldTheme, oldUI, oldCreate = package.loaded["defense.UIArt"], package.loaded["defense.Theme"],
            package.loaded["urhox-libs/UI"], _G.nvgCreateImage
        local previous = {}
        withArt(function(Art, _, _, ui)
            previous.art, previous.ui = Art, ui
            local icon = Art.Icon { icon = "core" }
            t:Equal(icon.context, ui.context, "第一套桩使用自己的ctx")
            icon:Destroy()
        end)
        withArt(function(Art, _, _, ui)
            t:Check(Art ~= previous.art and ui ~= previous.ui, "换桩重新执行真实UIArt，不共享绑定旧Widget的类")
            local icon = Art.Icon { icon = "core" }
            t:Equal(icon.context, ui.context, "第二套桩不复用第一套ctx")
            icon:Destroy()
        end)
        local accepted, message = pcall(function()
            withArt(function() error("expected_uiart_fixture_failure") end)
        end)
        t:Equal(accepted, false, "隔离夹具故意失败确实抛错")
        t:Check(tostring(message):find("expected_uiart_fixture_failure", 1, true) ~= nil, "不是加载错误造成的伪失败")
        t:Equal(package.loaded["defense.UIArt"], oldArt, "成功/失败后UIArt缓存恢复原值")
        t:Equal(package.loaded["defense.Theme"], oldTheme, "成功/失败后Theme缓存恢复原值")
        t:Equal(package.loaded["urhox-libs/UI"], oldUI, "成功/失败后UI桩恢复原值")
        t:Equal(_G.nvgCreateImage, oldCreate, "成功/失败后NVG全局恢复原值")
    end)
end
return A
