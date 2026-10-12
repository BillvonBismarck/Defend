# 自绘路线：raw NanoVG

适用：培养舱、扫描带、自定义图形、无设计稿约束的画布、纯装饰花纹，以及整个界面都不用标准控件的场景。

产出：一组绘制原语 + 窗口壳 + 各控件的绘制函数。

**先确认真的需要它。** 内置组件能表达的（按钮、输入、列表、弹窗、滚动）走组件路线更省事，且天然解决命中与响应式，见 [`ui-bridge.md`](ui-bridge.md)。本文件覆盖的是组件表达不了的那部分。

## 接入骨架

```lua
local vg

function Start()
    -- 分辨率模式见 skill nvg-resolution-mode，先定模式再写绘制
    -- 只创建一次；返回值 < 0 表示失败，引擎会退回内置 sans
    nvgCreateFont(vg, "sans", "Fonts/NotoSansSC-Black.ttf")
    SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")
end

---@param eventType string
---@param eventData NanoVGRenderEventData
function HandleNanoVGRender(eventType, eventData)
    -- 参数按所选分辨率模式给，模式 A/B 的差别见 nvg-resolution-mode
    nvgBeginFrame(vg, logicalW, logicalH, dpr)
    nvgScale(vg, s, s)          -- 模式 A 才需要：缩到设计空间
    DrawUI(vg)
    nvgEndFrame(vg)
end
```

**绘制必须挂 `NanoVGRender`**，挂在 `Update` 里画不出东西。

## 绘制原语

后续所有片段都建立在这组函数上。颜色表四通道，缺 alpha 当 255。

```lua
local C = {
    bg = {7,11,20,236}, panel = {10,16,28,248}, rail = {12,20,34,255},
    card = {16,26,44,255}, widget = {22,36,56,255},
    cyan = {0,229,208,255}, cyanDim = {0,150,148,220}, cyanSoft = {0,150,148,80},
    ink = {4,8,16,255}, text = {240,248,252,255},
    dim = {120,148,162,255}, warn = {255,196,72,255},
    error = {232,93,91,255},
}

local function RGBA(c, a)
    return nvgRGBA(c[1], c[2], c[3], a or c[4] or 255)
end

local function FillRect(vg, x, y, w, h, color, r)
    if w <= 0 or h <= 0 then return end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r or 4)
    nvgFillColor(vg, RGBA(color))
    nvgFill(vg)
end

local function StrokeRect(vg, x, y, w, h, color, r, width)
    -- +0.5 让 1px 描边落在像素中心，否则边缘发虚
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + 0.5, y + 0.5, w - 1, h - 1, r or 4)
    nvgStrokeColor(vg, RGBA(color))
    nvgStrokeWidth(vg, width or 1)
    nvgStroke(vg)
end

local function Line(vg, x1, y1, x2, y2, color, width)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y1)
    nvgLineTo(vg, x2, y2)
    nvgStrokeColor(vg, RGBA(color))
    nvgStrokeWidth(vg, width or 1)
    nvgStroke(vg)
end

local function Corners(vg, x, y, w, h, color, length)
    local l = length or 12
    Line(vg, x, y + l, x, y, color); Line(vg, x, y, x + l, y, color)
    Line(vg, x + w - l, y, x + w, y, color); Line(vg, x + w, y, x + w, y + l, color)
    Line(vg, x, y + h - l, x, y + h, color); Line(vg, x, y + h, x + l, y + h, color)
    Line(vg, x + w - l, y + h, x + w, y + h, color); Line(vg, x + w, y + h, x + w, y + h - l, color)
end

local function UseTechFont(vg)
    -- 字体在 Start() 里已注册为 "sans"；注册失败时引擎会退回内置 sans
    nvgFontFace(vg, "sans")
end

local function DrawText(vg, str, x, y, size, color, align)
    UseTechFont(vg)
    nvgFontSize(vg, size)
    nvgTextAlign(vg, align or (NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE))
    nvgFillColor(vg, RGBA(color))
    nvgText(vg, x, y, str or "", nil)
end

-- 真实测量，不要用「字数 × 固定宽」。先设好 face 和 size 再量。
local function TextWidth(vg, str, size)
    UseTechFont(vg)
    nvgFontSize(vg, size)
    return nvgTextBounds(vg, 0, 0, str or "") or (#(str or "") * size * 0.5)
end
```

## 补充绘制原语

`DrawLine` / `Corners` 之外的常用语汇。这些是实验室气质的主要载体，见 [`atmosphere.md`](atmosphere.md) 的分层用法。

```lua
-- 渐变填充：容器底、侧栏、仪表条。比纯色厚，比阴影便宜
local function GradientBox(vg, x, y, w, h, radius, top, bottom)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, radius)
    nvgFillPaint(vg, nvgLinearGradient(vg, x, y, x, y + h, RGBA(top), RGBA(bottom)))
    nvgFill(vg)
end

-- 虚线：标注引线、次级轴、剖面线。相位固定，不要随机
local function DashLine(vg, x1, y1, x2, y2, color, width, dash, gap)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local ux, uy = dx / len, dy / len
    local d, g = dash or 5, gap or 4
    nvgStrokeColor(vg, RGBA(color))
    nvgStrokeWidth(vg, width or 1)
    local drawn = 0.0
    while drawn < len do
        local stop = math.min(drawn + d, len)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1 + ux * drawn, y1 + uy * drawn)
        nvgLineTo(vg, x1 + ux * stop,  y1 + uy * stop)
        nvgStroke(vg)
        drawn = stop + g
    end
end

-- 十字标注：定位点、取样点
local function Cross(vg, x, y, size, color)
    Line(vg, x - size, y, x + size, y, color)
    Line(vg, x, y - size, x, y + size, color)
end

-- 刻度环：长短交替的径向刻度，做仪表 / 舱体识别
local function TickRing(vg, cx, cy, r, startDeg, endDeg, stepDeg, color)
    local steps = math.floor((endDeg - startDeg) / stepDeg)
    for i = 0, steps do
        local rad = math.rad(startDeg + i * stepDeg)
        local long = (i % 3 == 0)
        local inner = r - (long and 9 or 4)
        local ox, oy = math.cos(rad), math.sin(rad)
        Line(vg, cx + ox * inner, cy + oy * inner,
                cx + ox * r,     cy + oy * r, color, long and 1.3 or 0.7)
    end
end

-- 网点：半调纹理。必须 scissor，且 step 不宜过小
local function Halftone(vg, x, y, w, h, step, alpha)
    nvgSave(vg)
    nvgScissor(vg, x, y, w, h)
    nvgFillColor(vg, RGBA({20, 48, 120, 255}, alpha or 16))
    local s = step * 2
    for gy = y, y + h, s do
        for gx = x, x + w, s do
            nvgBeginPath(vg)
            nvgCircle(vg, gx, gy, 0.9)
            nvgFill(vg)
        end
    end
    nvgRestore(vg)
end

-- 断线边框：四边留缺口。缺口位置固定，不要随机
local function BrokenFrame(vg, x, y, w, h, color, gap)
    local g = gap or 22
    Line(vg, x, y, x + g, y, color)
    Line(vg, x + w - g, y, x + w, y, color)
    Line(vg, x, y + h, x + g, y + h, color)
    Line(vg, x + w - g, y + h, x + w, y + h, color)
    Line(vg, x, y, x, y + g, color)
    Line(vg, x, y + h - g, x, y + h, color)
    Line(vg, x + w, y, x + w, y + g, color)
    Line(vg, x + w, y + h - g, x + w, y + h, color)
end
```

**性能提醒**：`DashLine` 和 `Halftone` 是循环绘制，每段 / 每点一次 `nvgBeginPath`。在 360×720 的设计空间里，`Halftone` 的 `step` 不要小于 7，`DashLine` 的总长不要超过一屏，否则单帧调用数会迅速上千。需要大面积纹理时优先用 `nvgImagePattern` 而不是逐点画。

## 窗口壳

```lua
local function DrawWindow(vg, x, y, w, h, title)
    local titleH, footerH, pad = 52, 42, 10
    FillRect(vg, x, y, w, h, C.panel, 6)
    StrokeRect(vg, x, y, w, h, C.cyanDim, 6)
    Corners(vg, x, y, w, h, C.cyan, 13)
    FillRect(vg, x, y, 4, titleH, C.cyan, 0)   -- 标题识别竖线
    DrawText(vg, title, x + 16, y + titleH * 0.5, 15, C.cyan)

    local cx, cy = x + pad, y + titleH + pad
    local cw = w - pad * 2
    local ch = h - titleH - footerH - pad * 2
    nvgSave(vg)
    nvgScissor(vg, cx, cy, cw, ch)
    FillRect(vg, cx, cy, cw, ch, C.rail, 4)
    -- 调用方内容画在这里
    nvgRestore(vg)
end
```

每个裁剪区用 `nvgSave` / `nvgRestore` 包住。内容溢出不得画到窗口外。

底栏和标题栏按 SKILL.md 的尺寸表搭，本函数只给最小骨架。

## 装饰花纹

装饰是少量重复几何，不是随机贴图。主窗用较强角标 + 左竖线；普通分组只留一种弱花纹。

| 花纹 | 形态 | 放哪 | 强度 |
| --- | --- | --- | --- |
| 角落折角 | L 形短线 | 窗口四角、重点卡片 | 1–2 px，`cyan` / `cyanDim` |
| 断线边框 | 边框留缺口 | 外框、标题栏、分组 | 1 px，低透明 |
| 标题竖线 | 3–4 px | 标题左侧、侧栏边 | 主 `cyan`，陪 `cyanDim` |
| 微型网格 | 稀疏十字线 | 大块空白、预览区 | alpha 18–45，必须 scissor |
| 刻度线 | 长短交替 | 顶/底/侧边 | alpha 50–100 |
| 扫描带 | 半透明横条 | 内容/预览背景 | alpha 20–55，可固定相位 |
| 状态短线 | 短线、圆点 | 标题旁、底栏 | 装饰，不冒充真实数据 |

```lua
local function MicroGrid(vg, x, y, w, h, step)
    nvgSave(vg)
    nvgScissor(vg, x, y, w, h)
    local g = {C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 28}
    for gx = x, x + w, (step or 12) do Line(vg, gx, y, gx, y + h, g) end
    for gy = y, y + h, (step or 12) do Line(vg, x, gy, x + w, gy, g) end
    nvgRestore(vg)
end

local function EdgeTicks(vg, x, y, w, count)
    if count < 2 then return end
    local step = w / (count - 1)
    for i = 0, count - 1 do
        local th = (i % 4 == 0) and 6 or 3
        Line(vg, x + i * step, y, x + i * step, y + th, {0, 150, 148, 110})
    end
end

local function ScanBand(vg, x, y, w, h, phase)
    local bandY = y + h * ((phase or 0) % 1)
    FillRect(vg, x, bandY, w, 2, {0, 229, 208, 34}, 0)
    FillRect(vg, x, bandY - 5, w, 1, {0, 150, 148, 22}, 0)
end

-- 断线边框：四边各画两段，中间留缺口。缺口位置固定，不要随机。
local function BrokenFrame(vg, x, y, w, h, color, gap)
    local g = gap or 22
    local mx, my = x + w * 0.5, y + h * 0.5
    Line(vg, x, y, x + g, y, color)
    Line(vg, x + w - g, y, x + w, y, color)
    Line(vg, x, y + h, x + g, y + h, color)
    Line(vg, x + w - g, y + h, x + w, y + h, color)
    Line(vg, x, y, x, y + g, color)
    Line(vg, x, y + h - g, x, y + h, color)
    Line(vg, x + w, y, x + w, y + g, color)
    Line(vg, x + w, y + h - g, x + w, y + h, color)
end
```

扫描带不要盖住可读文字。静态窗用固定 `phase`，不为装饰强行加动画。同一项目锁死角标长度、网格步长、刻度节奏。

## 控件绘制

尺寸与配色规则见 SKILL.md「控件外观」「状态」两节，这里只给实现。`state` 取 `"default" | "hover" | "active" | "disabled"`。

```lua
-- 状态取色：只靠颜色不够，调用方还应叠加底色/描边/左标记
local function StateFill(base, state)
    if state == "hover"  then return {base[1] + 8, base[2] + 12, base[3] + 16, base[4] or 255} end
    if state == "active" then return C.cyanSoft end
    return base
end

-- 胶囊 Chip：高 20–24，半径 ≤ 11（不是 9999）
local function Chip(vg, x, y, text, selected, state)
    local size, padX, h = 10, 9, 22
    local w = TextWidth(vg, text, size) + padX * 2
    if selected then
        FillRect(vg, x, y, w, h, C.cyan, 11)
        DrawText(vg, text, x + w * 0.5, y + h * 0.5, size, C.ink,
                 NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    else
        FillRect(vg, x, y, w, h, StateFill(C.card, state), 11)
        StrokeRect(vg, x, y, w, h, C.cyanDim, 11, 1)
        DrawText(vg, text, x + w * 0.5, y + h * 0.5, size, C.text,
                 NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    return w   -- 返回宽度，方便调用方横向排布
end

-- 按钮：primary 青底深字，secondary 卡底浅字，danger 仅破坏性操作
local function Button(vg, x, y, w, h, text, role, state)
    local size = 11
    if state == "disabled" then
        FillRect(vg, x, y, w, h, C.widget, 6)
        StrokeRect(vg, x, y, w, h, C.cyanDim, 6, 1)
        DrawText(vg, text, x + w * 0.5, y + h * 0.5, size, C.dim,
                 NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        return
    end
    local bg, fg
    if role == "primary" then
        bg, fg = C.cyan, C.ink
    elseif role == "danger" then
        bg, fg = C.error, C.text
    else
        bg, fg = StateFill(C.card, state), C.text
    end
    FillRect(vg, x, y, w, h, bg, 6)
    if role == "secondary" then StrokeRect(vg, x, y, w, h, C.cyanDim, 6, 1) end
    DrawText(vg, text, x + w * 0.5, y + h * 0.5, size, fg,
             NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

-- 输入框：底 ink 或 widget，聚焦只加青描边，不改整个窗口
local function Input(vg, x, y, w, h, text, focused, placeholder)
    FillRect(vg, x, y, w, h, C.ink, 4)
    StrokeRect(vg, x, y, w, h, focused and C.cyan or C.cyanDim, 4, 1)
    local size = 11
    local hasText = text and #text > 0
    DrawText(vg, hasText and text or placeholder, x + 8, y + h * 0.5, size,
             hasText and C.text or C.dim)
end

-- 滑轨：轨 widget，进度 cyan，未激活 cyanDim；轨高 8–12
local function Slider(vg, x, y, w, value, disabled)
    local trackH, r = 8, 4
    FillRect(vg, x, y, w, trackH, C.widget, r)
    local fill = disabled and C.cyanDim or C.cyan
    local vw = w * math.max(0, math.min(1, value))
    if vw > 0 then FillRect(vg, x, y, vw, trackH, fill, r) end
    -- thumb：拖动命中区可扩到 18–22，这里给可见大小
    local thumbR = 6
    local cx = x + vw
    nvgBeginPath(vg)
    nvgCircle(vg, cx, y + trackH * 0.5, thumbR)
    nvgFillColor(vg, RGBA(disabled and C.dim or C.text))
    nvgFill(vg)
end

-- 列表 / 属性行：行高 30–38，当前行 card 底 + 3px 青左标记
local function ListRow(vg, x, y, w, h, label, value, selected, hovered)
    if selected then
        FillRect(vg, x, y, w, h, C.card, 3)
        FillRect(vg, x, y, 3, h, C.cyan, 0)
    elseif hovered then
        FillRect(vg, x, y, w, h, C.widget, 3)
    end
    DrawText(vg, label, x + 12, y + h * 0.5, 11, C.text)
    if value then
        DrawText(vg, value, x + w - 12, y + h * 0.5, 10, C.dim,
                 NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    end
end

-- 滚动条：轨 widget，thumb cyanDim，最小高 36–44
local function Scrollbar(vg, x, y, h, offset, total, viewH)
    if total <= viewH then return end
    local w = 4
    FillRect(vg, x, y, w, h, C.widget, 2)
    local minThumb = 36
    local th = math.max(minThumb, h * (viewH / total))
    local maxOffset = math.max(1, total - viewH)
    local ty = y + (h - th) * math.max(0, math.min(1, offset / maxOffset))
    FillRect(vg, x, ty, w, th, C.cyanDim, 2)
end
```

## 命中区

自绘路线的头号 bug 来源：**视觉坐标和点击坐标两套数**。高 DPI 与 letterbox 下必然点空。

规矩：

1. 一份布局数据同时驱动绘制和命中判断。先算出 `{x, y, w, h}`，再拿它去画，也拿它去判 `pointInRect`。
2. 不要在绘制函数里临时改坐标。
3. 触摸命中 ≥ 24×24，桌面控件 ≥ 20×20；可见边可以更小，但命中框不小于此。
4. 输入坐标先做 DPR 与 letterbox 反变换，再和布局坐标比。

```lua
local function Hit(r, px, py)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end
```

如果发现自己在反复处理这些，说明该走组件路线了——`GetAbsoluteLayout()` 已经替你做完这一切。

## 参考

- 组件路线（更省事，优先考虑）：[`ui-bridge.md`](ui-bridge.md)
- 完整令牌表：[`tokens.md`](tokens.md)
- 分辨率三种模式与输入变换：skill `nvg-resolution-mode`
- NanoVG C API 映射与扩展（如图片染色 `nvgImagePatternTinted`）：`engine-docs/lua-scripting-guide.md`
