# 本项目 NanoVG 绘制元素库

> **来源**：本项目 `scripts/network/Client.lua`（实验室 / 培养舱玩法，设计空间 360×720 竖屏）
> **用途**：需要复刻、延展或迁移本项目视觉语汇时，从这里取元素，不要重新发明
> **配套**：[`nanovg.md`](nanovg.md) 原语与窗口壳 · [`tokens.md`](tokens.md) 令牌 · [`atmosphere.md`](atmosphere.md) 氛围层

---

## 0. 定位

本文件是**元素级**清单：每个视觉母题的形态、参数、落位与实现。

- 风格层（**为什么**这么画）→ SKILL.md「设计 DNA」
- 氛围层（**怎么让它动**）→ [`atmosphere.md`](atmosphere.md)
- 本文件（**画什么、画在哪、用什么数**）→ 元素库

元素分四类，全部可独立复用：

| 章节 | 类别 | 元素 |
| --- | --- | --- |
| §1 | **基座** | 设计空间 / 反变换 / 取色 / 渲染入口 |
| §2 | **原语** | `Box` `StrokeBox` `Line` `GradientBox` |
| §3 | **装饰母题** | `Corners` `MicroGrid` `Ticks` `DashLine` `Cross` `TickRing` `Halftone` `ScanBand` |
| §4 | **背景机位** | 全屏渐变 / 侧栏 / 支架 / 轴标 5 层 |
| §5 | **复合构件** | 主面板 / 数据卡 / 选项卡 / 页码胶囊 / 进度条 / 滚动条 |
| §6 | **主视觉** | 培养舱 12 层 + 舱内叠加 12 项 + 幽灵标注 |
| §7 | **图像元素** | 圆角贴图 / 帧淡化 / 残影 / 扫描切片 / 切换动画 / 缩略图 |
| §8 | **文字元素** | 描边文字 / 字号层级 / CJK 折行与测量缓存 |
| §9 | **HUD 反馈** | 飘字 / 轻提示 / 页签弹字 |
| §10 | **界面骨架** | 状态栏 / 底部档案栏 / 日志浮层 / 排行榜浮层 / 广告条 |
| §11 | **管线** | 字体注册与重载 / 主题切换 |

---

## 1. 基座

### 1.1 设计空间与 letterbox

设计分辨率 **360×720**（竖屏）。用 CONTAIN 缩放（`math.min`），居中偏移，四周留出的区域由 letterbox 底色填满。

```lua
local DESIGN_W, DESIGN_H = 360, 720

local function Layout()
    VIEW.dpr = graphics:GetDPR()
    VIEW.w, VIEW.h = graphics:GetWidth() / VIEW.dpr, graphics:GetHeight() / VIEW.dpr
    VIEW.scale = math.min(VIEW.w / DESIGN_W, VIEW.h / DESIGN_H)   -- CONTAIN
    VIEW.ox = (VIEW.w / VIEW.scale - DESIGN_W) * 0.5              -- 居中偏移
    VIEW.oy = (VIEW.h / VIEW.scale - DESIGN_H) * 0.5
end
```

`ScreenMode` 事件里重新调用 `Layout()`。这是模式 A 的标准做法，细则见 skill `nvg-resolution-mode`。

### 1.2 输入反变换

引擎输入是物理像素。先除 DPR 再除 scale，最后减 letterbox 偏移，才落到设计坐标：

```lua
local function Point(x, y)
    return x / VIEW.dpr / VIEW.scale - VIEW.ox,
           y / VIEW.dpr / VIEW.scale - VIEW.oy
end

local function Hit(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end
```

**所有命中判断都用设计坐标的 `Hit`**，和绘制共用同一套数字。触摸用更大的容差（`< 26`），鼠标用 `< 22`。

### 1.3 取色

颜色统一是四通道 8-bit 表，`Color()` 负责补 alpha：

```lua
local function Color(c, a)
    return nvgRGBA(c[1], c[2], c[3], a or c[4] or 255)
end
```

有了它，调用点可以只写三通道 `{ 255, 214, 99 }`，也可以覆盖 alpha `{ C.wash[1], C.wash[2], C.wash[3], 40 + pulse * 70 }`。

### 1.4 渲染入口

```lua
---@param eventType string
---@param eventData NanoVGRenderEventData
function HandleRender(eventType, eventData)
    if not VIEW.vg then return end
    nvgBeginFrame(VIEW.vg, VIEW.w, VIEW.h, VIEW.dpr)
    nvgSave(VIEW.vg)
    nvgScale(VIEW.vg, VIEW.scale, VIEW.scale)

    -- 先在屏幕设计空间铺 letterbox 底，避免宽屏露黑边
    local screenDesignW = VIEW.w / VIEW.scale
    local screenDesignH = VIEW.h / VIEW.scale
    nvgBeginPath(VIEW.vg)
    nvgRect(VIEW.vg, 0, 0, screenDesignW, screenDesignH)
    nvgFillColor(VIEW.vg, Color(C.letterbox))
    nvgFill(VIEW.vg)

    nvgTranslate(VIEW.vg, VIEW.ox, VIEW.oy)   -- 进入 360×720 设计空间
    DrawGame()
    DrawLeaderboard()      -- 上层浮层后画
    DrawScholarLog()
    nvgRestore(VIEW.vg)
    nvgEndFrame(VIEW.vg)
end
```

绘制顺序 = 层级顺序：**底 → 主界面 → 浮层**。浮层后画才能盖住主体。

---

## 2. 原语

四个函数撑起全部绘制。除 `GradientBox` 外都用 `Color()` 取色。

```lua
local function Box(x, y, w, h, r, c)
    nvgBeginPath(VIEW.vg)
    nvgRoundedRect(VIEW.vg, x, y, w, h, r)
    nvgFillColor(VIEW.vg, Color(c))
    nvgFill(VIEW.vg)
end

-- +0.5 / -1 让 1px 描边落在像素中心，否则边缘发虚
local function StrokeBox(x, y, w, h, r, c, width)
    nvgBeginPath(VIEW.vg)
    nvgRoundedRect(VIEW.vg, x + 0.5, y + 0.5, w - 1, h - 1, r)
    nvgStrokeColor(VIEW.vg, Color(c))
    nvgStrokeWidth(VIEW.vg, width or 1)
    nvgStroke(VIEW.vg)
end

local function Line(x1, y1, x2, y2, c, width)
    nvgBeginPath(VIEW.vg)
    nvgMoveTo(VIEW.vg, x1, y1)
    nvgLineTo(VIEW.vg, x2, y2)
    nvgStrokeColor(VIEW.vg, Color(c))
    nvgStrokeWidth(VIEW.vg, width or 1)
    nvgStroke(VIEW.vg)
end

-- 竖直渐变。比纯色厚，比阴影便宜，是分层的主要手段
local function GradientBox(x, y, w, h, radius, top, bottom)
    nvgBeginPath(VIEW.vg)
    nvgRoundedRect(VIEW.vg, x, y, w, h, radius)
    nvgFillPaint(VIEW.vg, nvgLinearGradient(VIEW.vg, x, y, x, y + h, Color(top), Color(bottom)))
    nvgFill(VIEW.vg)
end
```

| 原语 | 圆角 | 用途 |
| --- | --- | --- |
| `Box` | 传入 | 面板、卡片、进度、点块、底色 |
| `StrokeBox` | 传入 | 边框、描边强调。**必须**用 +0.5 偏移写法 |
| `Line` | — | 刻度、分隔、标注引线、波纹 |
| `GradientBox` | 传入 | 侧栏、仪表条、舱体底、缩进槽 |

> `r = 0` 也是合法值，用来画直角条块（进度轨、装饰条）。

---

## 3. 装饰母题

八种重复几何，构成「技术舱」识别度。每窗取 2–3 种，不要全上。

| 母题 | 形态 | 推荐落位 | 关键参数 |
| --- | --- | --- | --- |
| `Corners` | 四角 L 形折角 | 主面板、舱体、重点卡片 | 臂长 8–14，主线宽 1.4 |
| `MicroGrid` | 稀疏方格 | 大块空白区、舱体内胆 | 步长 12–17，alpha 26 |
| `Ticks` | 长短交替刻度 | 标题栏下沿、卡片顶边 | 16 段，长 6 / 短 3，alpha 110 |
| `DashLine` | 虚线引线 | 标注、次级轴、关系连线 | dash 3–5，gap 3–4 |
| `Cross` | 十字标注点 | 取样点、定位点、激活标记 | 臂长 3–4 |
| `TickRing` | 环形刻度 | 圆形主体外圈 | 每 3 段加长，宽 1.3 / 0.7 |
| `Halftone` | 半调网点阵 | 背景、面板、舱内底纹 | step 7–9，alpha 14–22 |
| `ScanBand` | 扫描带 + 拖尾 | 容器内部、预览区 | 速度 18 px/s，alpha 48 / 22 |

```lua
local function Corners(x, y, w, h, c, length)
    local l = length or 12
    Line(x, y + l, x, y, c);               Line(x, y, x + l, y, c)
    Line(x + w - l, y, x + w, y, c);       Line(x + w, y, x + w, y + l, c)
    Line(x, y + h - l, x, y + h, c);       Line(x, y + h, x + l, y + h, c)
    Line(x + w - l, y + h, x + w, y + h, c); Line(x + w, y + h, x + w, y + h - l, c)
end

local function MicroGrid(x, y, w, h, step)
    nvgSave(VIEW.vg)
    nvgScissor(VIEW.vg, x, y, w, h)          -- 网格必须裁剪，否则越出容器
    local g = { C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 26 }
    for gx = x, x + w, step do Line(gx, y, gx, y + h, g) end
    for gy = y, y + h, step do Line(x, gy, x + w, gy, g) end
    nvgRestore(VIEW.vg)
end

local function Ticks(x, y, w)
    for i = 0, 16 do
        local h = i % 4 == 0 and 6 or 3
        Line(x + i * w / 16, y, x + i * w / 16, y + h,
             { C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 110 })
    end
end

local function DashLine(x1, y1, x2, y2, c, width, dash, gap)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local ux, uy = dx / len, dy / len
    local drawn = 0.0
    nvgStrokeColor(VIEW.vg, Color(c))
    nvgStrokeWidth(VIEW.vg, width or 1)
    while drawn < len do
        local stop = drawn + dash
        if stop > len then stop = len end
        nvgBeginPath(VIEW.vg)
        nvgMoveTo(VIEW.vg, x1 + ux * drawn, y1 + uy * drawn)
        nvgLineTo(VIEW.vg, x1 + ux * stop,  y1 + uy * stop)
        nvgStroke(VIEW.vg)
        drawn = stop + gap
    end
end

local function Cross(x, y, size, c)
    Line(x - size, y, x + size, y, c)
    Line(x, y - size, x, y + size, c)
end

local function TickRing(cx, cy, r, startDeg, endDeg, stepDeg, c)
    local steps = math.floor((endDeg - startDeg) / stepDeg)
    for idx = 0, steps do
        local rad = math.rad(startDeg + idx * stepDeg)
        local long = (idx % 3 == 0)                       -- 每 3 段加长
        local inner = r - (long and 9 or 4)
        local ox, oy = math.cos(rad), math.sin(rad)
        Line(cx + ox * inner, cy + oy * inner, cx + ox * r, cy + oy * r,
             c, long and 1.3 or 0.7)
    end
end

local function Halftone(x, y, w, h, step, alpha)
    nvgSave(VIEW.vg)
    nvgScissor(VIEW.vg, x, y, w, h)
    nvgFillColor(VIEW.vg, nvgRGBA(C.halftone[1], C.halftone[2], C.halftone[3], alpha or 16))
    local s = step * 2
    for gy = y, y + h, s do
        for gx = x, x + w, s do
            nvgBeginPath(VIEW.vg)
            nvgCircle(VIEW.vg, gx, gy, 0.9)               -- 半径 0.9 = 一个像素点
            nvgFill(VIEW.vg)
        end
    end
    nvgRestore(VIEW.vg)
end

local function ScanBand(x, y, w, h)
    local bandY = y + (VIEW.elapsed * 18) % h
    Box(x, bandY, w, 1, 0, { C.ash[1], C.ash[2], C.ash[3], 48 })
    Box(x, bandY - 5, w, 1, 0, { C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 22 })
    local pulse = AnomalyPulse()
    if pulse > 0.28 then                                  -- 高位解锁拖尾
        local ghostY = y + ((VIEW.elapsed * 18) - 27) % h
        Box(x + 6, ghostY, w - 12, 2, 0, { C.wash[1], C.wash[2], C.wash[3], math.floor(28 + 70 * pulse) })
        Box(x, ghostY + 8, w, 10, 0, { C.washDim[1], C.washDim[2], C.washDim[3], math.floor(18 * pulse) })
    end
end
```

**性能提醒**：`Halftone` 是逐点绘制，`step` 不要小于 7；`DashLine` 总长不要超过一屏。大面积纹理优先考虑用 `nvgImagePattern` 平铺替代（见 §7）。

---

## 4. 背景机位

实验室背景不是纯色底，是一组**固定的工业机位框架**：侧栏、支架、齿刻、轴标。它给整屏提供纵深和外框，本身完全静态（只有轴标文字随脉冲呼吸）。

**5 层，从后到前：**

| 层 | 元素 | 参数 |
| --- | --- | --- |
| 1 | 全屏竖直渐变 | `bgTop → bgBottom` |
| 2 | 全屏半调网点 | `Halftone(0,0,360,720,9,14)` |
| 3 | 左右侧栏 | `GradientBox(0,78,13,530)` railTop→railBottom |
| 4 | 侧栏胶囊标记 | 每 46px 一枚 7×19 圆角块 + 27px 处短横线 |
| 5 | 上下分隔 + 齿刻 + 支架 + 虚线 + 轴标 | 见下 |

```lua
local function DrawLabBackground()
    -- 1. 全屏渐变底
    nvgBeginPath(VIEW.vg)
    nvgRect(VIEW.vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillPaint(VIEW.vg, nvgLinearGradient(VIEW.vg, 0, 0, 0, DESIGN_H,
                  Color(C.bgTop), Color(C.bgBottom)))
    nvgFill(VIEW.vg)
    Halftone(0, 0, DESIGN_W, DESIGN_H, 9, 14)

    -- 2. 左右侧栏 + 胶囊标记
    GradientBox(0, 78, 13, 530, 0, C.railTop, C.railBottom)
    GradientBox(347, 78, 13, 530, 0, C.railTop, C.railBottom)
    for y = 104, 576, 46 do
        Box(3,   y, 7, 19, 2, { C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 70 })
        Box(350, y, 7, 19, 2, { C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 70 })
        Line(0,   y + 27, 13,  y + 27, { C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 80 })
        Line(347, y + 27, 360, y + 27, { C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 80 })
    end

    -- 3. 上下分隔线 + 齿刻
    Line(0, 80, 360, 80, { C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 95 })
    Line(0, 608, 360, 608, { C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 70 })
    for x = 16, 345, 33 do
        Line(x, 77, x + 10, 80, { C.ash[1], C.ash[2], C.ash[3], 70 })
    end

    -- 4. 顶部支架（3px 粗线）+ 悬挂圆点
    Line(27, 82, 27, 94, railMark, 3)
    Line(27, 94, 73, 94, railMark, 3)
    Line(333, 82, 333, 94, railMark, 3)
    Line(287, 94, 333, 94, railMark, 3)
    for x = 51, 310, 86 do
        nvgBeginPath(VIEW.vg); nvgCircle(VIEW.vg, x, 94, 4)
        nvgFillColor(VIEW.vg, Color(C.cyanDim)); nvgFill(VIEW.vg)
        nvgBeginPath(VIEW.vg); nvgCircle(VIEW.vg, x, 94, 1.5)
        nvgFillColor(VIEW.vg, Color(C.cyan)); nvgFill(VIEW.vg)
    end

    -- 5. 轴虚线 + 轴标（低位标注随脉冲呼吸）
    DashLine(18,  82, 18,  448, { C.klein[1], C.klein[2], C.klein[3], 46 }, 1, 5, 4)
    DashLine(342, 82, 342, 448, { C.klein[1], C.klein[2], C.klein[3], 46 }, 1, 5, 4)
    local axPulse = AnomalyPulse()
    Text("AX-07", 8,   96, 8, { C.klein[1], C.klein[2], C.klein[3], 90 + math.floor(axPulse * 80) },
         NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    Text("AX-08", 352, 96, 8, { C.klein[1], C.klein[2], C.klein[3], 90 + math.floor(axPulse * 80) },
         NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    if axPulse > 0.45 then
        Text("AX-0?", 8, 112, 8, { C.wash[1], C.wash[2], C.wash[3], 120 + math.floor(axPulse * 80) },
             NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end
end
```

**要点**

- **背景全部静态**，只有 `AX-0?` 这类轴标随脉冲出现。背景里放动画会和主体抢注意力。
- 侧栏宽 13px、支架线宽 3px —— **背景元素用粗线，装饰元素用 1px**，靠线宽而非颜色区分层级。
- 悬挂圆点是「双层圆」：外圈 4px 用 `cyanDim`，内点 1.5px 用 `cyan`。这个双层结构在项目里反复出现（侧栏、顶部槽、状态点）。
- 轴标用 `klein`（不饱和蓝）而非 `cyan`，避免和交互元素混淆。

---

## 5. 复合构件

### 5.1 主面板（浮层）

```lua
local function DrawOverlayPanel(x, y, w, h, accent)
    Box(x, y, w, h, 6, { C.panel[1], C.panel[2], C.panel[3], 250 })
    StrokeBox(x, y, w, h, 6, C.cyanDim)
    Corners(x, y, w, h, accent or C.cyan, 14)
    Box(x, y, 4, 55, 0, accent or C.cyan)      -- 标题识别竖线
    Halftone(x + 4, y + 4, w - 8, h - 10, 8, 16)
    DashLine(x + 8, y + 54, x + w - 6, y + 54,
             { C.klein[1], C.klein[2], C.klein[3], 80 }, 1, 5, 4)
end
```

**层级**：面板底（半透明 `panel`）→ 折角 → 标题竖线 → 网点 → 虚线分隔。全部在面板范围内。

### 5.2 数据卡片

```lua
local function DrawDataCard(x, y, w, h, highlight)
    local edge = highlight and C.gold or C.cyanDim
    Box(x, y, w, h, 4, C.card)
    StrokeBox(x, y, w, h, 4, edge, highlight and 1.4 or 1)
    Corners(x, y, w, h, edge, 8)
    Box(x, y, 3, h, 0, highlight and C.gold or C.cyan)   -- 左标记
    Ticks(x + 14, y + 4, 300)
end
```

卡片靠**左标记 + 折角 + 顶边刻度**建立识别，不靠阴影。

### 5.3 选项卡（标本格）

```lua
-- 四格一页，格宽 62，间距 8
local function DrawSlot(x, y, selected, ready, unlocked)
    local fill = selected and C.widget or (ready and C.readyCard or C.card)
    local edge = selected and C.cyan or (ready and C.gold or C.cyanDim)
    Box(x, y, 62, 80, 4, fill)
    StrokeBox(x, y, 62, 80, 4, edge, (selected or ready) and 1.5 or 1)
    if selected then Box(x, y, 3, 80, 0, C.cyan)
    elseif ready then Box(x, y, 3, 80, 0, C.gold) end
    -- 状态点：自动可用 / 可升级（呼吸）
end
```

三态区分**同时用底色 + 描边宽 + 左标记**，不只靠颜色：
`selected` → widget 底 + 1.5 描边 + 青左标；`ready` → readyCard 底 + 1.5 描边 + 金左标；默认 → card 底 + 1 描边。

### 5.4 页码胶囊

```lua
local function DrawPageChip(x, y, label, selected, available)
    Box(x, y, 42, 26, 4, selected and (available and C.cyan or C.widget) or C.card)
    StrokeBox(x, y, 42, 26, 4, available and C.cyanDim or C.dim)
    local fg = selected and (available and C.ink or C.dim)
                        or (available and C.text or C.dim)
    Text(label, x + 21, y + 13, 12, fg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end
```

未解锁的页码显示 `?` 而不是数字，底色与文字同时降级。

### 5.5 进度条与 0.73 标记

```lua
local function DrawProgress(x, y, w, ratio, full)
    Box(x, y, w, 6, 3, C.ink)                                   -- 轨道用 ink
    local fw = w * math.min(1, ratio)
    if fw > 0 then Box(x, y, fw, 6, 3, full and C.gold or C.blue) end
end

-- 阈值标记：pulse 高位时在 73% 处点一根竖线
if pulse > 0.5 then Box(30 + 300 * 0.73, 510, 2, 10, 0, C.gold) end
```

进度条**只占 6px**，轨道用 `ink`（比 `widget` 更深），填充按状态在 `blue` / `gold` 间切换。

### 5.6 滚动条

```lua
local function DrawScrollbar(barX, trackY, trackH, barW, scroll, scrollMax, viewH, contentH)
    if scrollMax <= 0 then return end
    local thumbH = math.max(28, trackH * (viewH / contentH))     -- 最小 28
    local thumbY = trackY + (trackH - thumbH) * (scroll / scrollMax)
    Box(barX, trackY, barW, trackH, 3, C.widget)
    Box(barX, thumbY, barW, thumbH, 3, C.cyanDim)
end
```

轨道 `widget`、thumb `cyanDim`、**宽度只有 4–6px**、最小高度 28。滚动条贴内容区右缘，独立于内容滚动。

---

## 6. 培养舱（主视觉母题）

整屏最有辨识度的复合体。**12 层从后到前**，全部包在一个裁剪区里。

| 层 | 元素 | 参数 |
| --- | --- | --- |
| 1 | 壳体渐变 | `GradientBox(16,86,328,369,7)` tankTop→tankBottom |
| 2 | 壳体描边 | `cyanDim` alpha 175，宽 1.3 |
| 3 | 四角折角 | `Corners` 臂长 13，青或 wash |
| 4 | 左右立柱 | 5px 宽实心条 |
| 5 | 内胆裁剪区 | `nvgScissor(24,126,312,321)` |
| 6 | 内胆底色 | 竖直渐变 alpha 180 → 200 |
| 7 | 微型网格 | `MicroGrid` 步长 17 |
| 8 | 半调网点 | `Halftone` step 7，alpha 22 |
| 9 | 液面 | `fluidY = 372 + sin(t*1.3)*4`，alpha 48+pulse*36 |
| 10 | 波纹 | 4 条，间距 18，相位错开 |
| 11 | 气泡 | 14 个，确定性分布 |
| 12 | 扫描带 | `ScanBand` + surge |

```lua
local function DrawTankBubbles()
    local phase = VIEW.elapsed * 13
    for i = 1, 14 do
        local lane = i * 23
        -- 确定性伪随机：不要用 math.random，否则每帧瞬移
        local x = 39 + (lane % 277) + math.sin(phase + i * 1.7) * 5
        local y = 420 - ((phase * (8 + i % 4) + i * 31) % 174)
        local r = i % 3 == 0 and 2.2 or 1.2
        nvgBeginPath(VIEW.vg)
        nvgCircle(VIEW.vg, x, y, r)
        nvgStrokeColor(VIEW.vg, nvgRGBA(C.ghost[1], C.ghost[2], C.ghost[3], 70))
        nvgStrokeWidth(VIEW.vg, 0.8)
        nvgStroke(VIEW.vg)
    end
end
```

### 舱内叠加元素

| 元素 | 实现 | 参数 |
| --- | --- | --- |
| 液面 | 矩形填充 | `fluidY = 372 + sin(t*1.3)*4` |
| 波纹线 | 4 条横线 | 间距 18，`sin(t*1.5 + wave)*2`，wash |
| 气泡 | 14 个描边圆 | 半径 1.2 / 2.2，ghost alpha 70 |
| 呼吸 | 整体位移 | `sin(t*2) * 3` |
| 主环 | 圆填充 + 双层描边 | 内填 ink 170；外环 alpha 210 宽 1.4 |
| 刻度环 | `TickRing` | `-28°..208°`，步长 10 |
| 残影环 | 偏移 +7,−5 | ghost alpha 40+pulse*70 |
| 弧标 | `nvgArc` | `-32°..34°`，klein alpha 150 |
| 侧栏 | 渐变槽 + 竖线 + 点阵 | 点距 51，外点 3.4 / 内点 2.1 |
| 顶部槽 | 渐变条 + 点阵 | 点距 44，r=3 |
| 立柱高光 | 两条竖直渐变矩形 | highlight alpha 28 / 18 |
| 底部仪表 | 圆角条 | washDim alpha 40+pulse*50 |

### 幽灵标注（异常位）

高阈值时多出来的伪标注，是实验室气质的关键：

```lua
local extraDeg = -52 + math.sin(VIEW.elapsed * 0.55) * 3   -- 缓慢摆动
local extraRad = math.rad(extraDeg)
local extraX = HAND_X + math.cos(extraRad) * (ringR - 22)
local extraY = cy + math.sin(extraRad) * (ringR - 22)
local extraA = 70 + math.floor(pulse * 120)

DashLine(HAND_X + 22, cy - 36, extraX, extraY, ghostColor, 1, 4, 3)
Cross(extraX, extraY, 4, ghostColor)
DashLine(extraX, extraY, extraX + 18, extraY - 34, ghostColor, 1, 3, 3)
Cross(extraX + 18, extraY - 34, 3, washColor)
Text("FINGER 06", extraX + 22, extraY - 38, 8, ghostColor)
Text("+0.73s",    extraX + 22, extraY - 26, 8, washColor)
```

标注 = **引线 + 十字 + 标签**三件套，透明度跟随脉冲。

---

## 7. 图像元素

### 7.1 圆角图像绘制

```lua
DrawImage = function(image, x, y, w, h, alpha)
    if not image or image < 0 then return end
    nvgBeginPath(VIEW.vg)
    nvgRoundedRect(VIEW.vg, x, y, w, h, 12)
    nvgFillPaint(VIEW.vg, nvgImagePattern(VIEW.vg, x, y, w, h, 0, image, alpha or 1.0))
    nvgFill(VIEW.vg)
end
```

用 `nvgImagePattern` 而不是直接贴图，才能吃到 `nvgRoundedRect` 的圆角裁剪。

### 7.2 帧序列交叉淡化

五帧序列 `_open / _mid / _closed / _press / _max`，用浮点帧号同时叠两张：

```lua
local f = 1 + progress * 4
local frame = math.floor(f)
local mix = f - frame
DrawImage(images[frame],     x, y, w, h, 1.0 * (1 - mix))
DrawImage(images[frame + 1], x, y, w, h, 1.0 * mix)
```

配合**双重残影**（偏移 ±3px、低 alpha）制造运动模糊：

```lua
DrawImage(images[frame],     x - 3, y + 2, w, h, 0.18 * (1 - mix))
DrawImage(images[frame + 1], x + 3, y - 2, w, h, 0.16 + 0.12 * mix)
```

### 7.3 残影叠加

```lua
if pulse > 0.35 then                               -- 固定偏移，不要随机
    DrawImage(images[1], x + 7, y - 5, w, h, 0.08 + pulse * 0.10)
end
```

### 7.4 扫描线切片

用窄裁剪区把图像切成一条，模拟扫描过曝：

```lua
nvgSave(VIEW.vg)
nvgScissor(VIEW.vg, innerX, innerY + 86, innerW, 18)
DrawImage(images[frame], imageX + 5, imageY, imageW, imageH, 0.28)
nvgRestore(VIEW.vg)
Box(innerX, innerY + 86, innerW, 18, 0, { C.wash[1], C.wash[2], C.wash[3], 28 })
```

### 7.5 切换动画

换主体时：旧图下沉淡出、新图上升淡入、到达帧序列、扩散环。

```lua
local ease = SmoothStep(t)                              -- 平滑插值
DrawImage(fromImages[1], imageX - 16 * ease, imageY + 42 * ease, ..., 0.92 * (1 - ease))
DrawImage(toImages[arriveFrame], imageX + 10 * (1 - ease), imageY - 26 * (1 - ease), ..., 0.18 + 0.80 * ease)
-- 扩散环
nvgCircle(VIEW.vg, HAND_X, cy, ringR + 6 + ease * 22)
nvgStrokeColor(VIEW.vg, nvgRGBA(C.wash[1], C.wash[2], C.wash[3], math.floor(190 * (1 - ease))))
```

### 7.6 缩略图归档格

格内缩略图 48×42，可升级时叠一帧前序图做「抖动」：

```lua
local cardFrame, bounce = ArchiveGripFrame(index)        -- 周期性 5 帧 + 弹跳
DrawImage(slotImages[cardFrame], x + 7, 626 - bounce, 48, 42)
if ready then
    DrawImage(slotImages[math.max(1, cardFrame - 1)], x + 5, 628 - bounce, 48, 42, 0.18)
end
```

**图片按需加载**：`EnsureHandImages(index)` 首帧才 `nvgCreateImage`，避免启动时一次打出上百个请求。加载后用 `ImageReady(image)` 检查尺寸再绘制。

---

## 8. 文字元素

```lua
Text = function(text, x, y, size, c, align, outlined)
    UseTechFont()
    nvgFontSize(VIEW.vg, size)
    nvgTextAlign(VIEW.vg, align or (NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE))
    if outlined and size >= 12 then                      -- 大字号才描边
        nvgFillColor(VIEW.vg, nvgRGBA(C.outline[1], C.outline[2], C.outline[3], 230))
        nvgText(VIEW.vg, x - 1, y, text, nil)
        nvgText(VIEW.vg, x + 1, y, text, nil)
        nvgText(VIEW.vg, x, y - 1, text, nil)
        nvgText(VIEW.vg, x, y + 1, text, nil)
    end
    nvgFillColor(VIEW.vg, Color(c))
    nvgText(VIEW.vg, x, y, text, nil)
end
```

**描边用四个方向的偏移文字实现**（不是 `nvgStrokeText`），只对 ≥12px 的字开，否则小字会糊。

| 角色 | 字号 | 颜色 | 描边 |
| --- | --- | --- | --- |
| 主数值（货币、次数） | 21–22 | `ash` / `wash` / `text` | ✅ |
| 卡片标题 | 16 | `text` | ✅ |
| 区域标题 | 12–13 | `cyan` / `text` | ✅ |
| 正文 | 11–12 | `text` | ❌ |
| 标签 / 单位 | 8–10 | `dim` / `ash` | ❌ |
| 状态 / 注释 | 8–9 | `gold` / `wash` / `ghost` | ❌ |

**CJK 正文用 `nvgTextBox`** 自动折行，并且要先量高再滚动：

```lua
local bounds = nvgTextBoxBounds(VIEW.vg, 47, textY + 4, boxW, body, nil)
local textH = ((bounds and bounds[4] or 0) - (bounds and bounds[2] or 0)) + 8
-- 缓存 textH，避免每帧测量
nvgSave(VIEW.vg); nvgScissor(VIEW.vg, textX, textY, textW, textH)
nvgTextBox(VIEW.vg, 47, textY + 4 - scroll, boxW, body, nil)
nvgRestore(VIEW.vg)
```

---

## 9. HUD 反馈元素

三种瞬时反馈，都是「入队 → 逐帧衰减 → 到期移除」。**统一用 `PushFx` 做上限驱逐**，防止高频点击堆爆。

```lua
local function PushFx(list, item, cap)
    table.insert(list, item)
    while #list > cap do table.remove(list, 1) end   -- 超限丢弃最旧的
end

local function Toast(text)
    PushFx(FX.toasts, { text = text, life = 2.4 }, 6)
end

local function Float(text, color, x, y)
    PushFx(FX.floating, { text = text, color = color, x = x, y = y, life = 0.85 }, 24)
end
```

| 元素 | 上限 | 寿命 | 运动 | 样式 |
| --- | --- | --- | --- | --- |
| **飘字** `Float` | 24 | 0.85s | 上浮 38 px/s | 14px 描边字，颜色随来源（手币金 / EXP 蓝） |
| **轻提示** `Toast` | 6 | 2.4s | 静止，纵向堆叠 36px | 260×29 圆角 11 实底盒 + 13px `warn` 字 |
| **页签弹字** `TabPop` | — | 1.2s | 上浮 26 px/s | 10px 描边字，落在对应格子正上方 |

**绘制顺序：在所有浮层之后**，保证反馈永远压在最上层。

```lua
for _, item in ipairs(FX.floating) do
    local alpha = math.floor(math.max(0, item.life / 0.85) * 255)
    Text(item.text, item.x, item.y, 14, { item.color[1], item.color[2], item.color[3], alpha },
         NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, true)
end

for i, toast in ipairs(FX.toasts) do
    Box(50, 90 + (i - 1) * 36, 260, 29, 11, C.toastBg)
    Text(toast.text, 180, 104 + (i - 1) * 36, 13, C.warn, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

for _, pop in ipairs(FX.tabPops) do
    local alpha = math.floor(math.max(0, pop.life / 1.15) * 255)
    Text(pop.text, pop.x, pop.y, 10, { pop.color[1], pop.color[2], pop.color[3], alpha },
         NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, true)
end
```

逐帧衰减（`Update` 里）：

```lua
for i = #FX.floating, 1, -1 do
    local item = FX.floating[i]
    item.life = item.life - dt
    item.y = item.y - dt * 38
    if item.life <= 0 then table.remove(FX.floating, i) end
end
```

**要点**

- **alpha 用 `life / 初始寿命` 归一化**，不要另存淡出计时器。
- **`Toast` 是唯一带实底盒的反馈**——它需要在不打断阅读的前提下被看到；飘字和弹字是纯文字。
- **飘字坐标带抖动**（`elapsed * 37 % 18`），避免连点时数字完全重叠成一坨。
- 倒序遍历 + `table.remove`，正序删除会漏项。

---

## 10. 界面骨架

四个成型界面 + 一个状态条。**每个都是完整规格**，可直接照抄尺寸。

### 10.1 状态栏

`(12, 10, 336, 62)` —— 顶栏。

```lua
local pulse = AnomalyPulse()
Box(12, 10, 336, 62, 4, C.panel)
StrokeBox(12, 10, 336, 62, 4, pulse > 0.6 and C.washDim or C.cyanDim)
Corners(12, 10, 336, 62, pulse > 0.6 and C.wash or C.cyan, 9)
Box(12, 10, 3, 62, 0, pulse > 0.6 and C.wash or C.cyanDim)   -- 左竖线
Ticks(26, 12, 150)                                            -- 顶边刻度
DashLine(154, 32, 154, 68, { C.klein[1], C.klein[2], C.klein[3], 70 }, 1, 3, 3)

Text(pulse > 0.72 and "LAB / HANDS-0?" or "LAB / HANDS-01", 28, 28, 9,
     pulse > 0.72 and C.wash or C.dim)
Text(FormatNumber(profile_.coins), 28, 52, 22, accent, nil, true)   -- 主数值
Text("HAND COIN", 132, 52, 8, C.dim)                                -- 单位
Text(specs_[profile_.equipped][1], 336, 26, 13, C.text,
     NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, true)                      -- 当前对象
```

内部还有一个**入口按钮** `(252, 42, 88, 24)`：`Box` widget r4 + `StrokeBox` + 图标 + 标签。状态栏右侧元素一律右对齐（`NVG_ALIGN_RIGHT`）。

层级：编号标签(9/`dim`) < 单位(8/`dim`) < 数值(22/描边) < 对象名(13/描边)。

### 10.2 底部档案栏

`(0, 596, 360, 124)` —— 底栏。四格一页的标本库。

```lua
Box(0, 596, 360, 124, 0, { C.bg[1], C.bg[2], C.bg[3], 240 })
Line(0, 596, 360, 596, { C.cyanDim[1], C.cyanDim[2], C.cyanDim[3], 90 })
Box(0, 596, 360, 2, 0, { C.washDim[1], C.washDim[2], C.washDim[3], 50 })  -- 顶部高亮线
Text("SPECIMEN ARCHIVE", 16, 610, 9, C.dim)
Text(profile_.page .. " / 5", 344, 610, 9, C.cyan, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
Text("‹", 16, 662, 26, C.text, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
Text("›", 344, 662, 26, C.text, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

for slot = 1, 4 do
    local index = (profile_.page - 1) * 4 + slot
    local x = 43 + (slot - 1) * 70                              -- 格宽 62，间距 8
    -- DrawSlot(x, 622, selected, ready, unlocked)  见 §5.3
end
Text("CLOUD LINK / ACTIVE", 344, 710, 8, C.dim, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
```

左右翻页用**纯文字箭头 `‹` `›`（26px）**，不画按钮框 —— 底栏已经很密，再加框会糊。

### 10.3 日志浮层

`(14, 78, 332, 548)` —— 盖住主视觉的阅读浮层。

```lua
Box(14, 78, 332, 548, 6, { C.panel[1], C.panel[2], C.panel[3], 250 })
StrokeBox(14, 78, 332, 548, 6, C.cyanDim)
Corners(14, 78, 332, 548, C.cyan, 14)
Box(14, 78, 4, 55, 0, C.cyan)                                 -- 左竖线（仅标题栏高）
Halftone(18, 82, 324, 538, 8, 18)
DashLine(22, 132, 338, 132, { C.klein[1], C.klein[2], C.klein[3], 80 }, 1, 5, 4)
```

**六个区段**（y 坐标固定）：

| 区段 | y | 内容 |
| --- | --- | --- |
| 标题区 | 100–120 | 主标题(12/`ash`) + 编号·名称(10/`dim`) + 右上对象(9/`gold`) |
| 章翻页 | 140–168 | `‹`(18) + `第 N / 20 章`(11/`cyan`) + `›`(18) |
| 页签行 | 172–198 | 6 枚 42×26 胶囊，x = 31 + (page−1)×50 |
| 页码行 | 208–224 | 分隔线 + `页码 N / 6`(10/`dim`) + 右侧状态(10/`cyan` 或 `warn`) |
| 正文区 | 236–508 | `Box(30,236,300,272,5,C.rail)` + 描边 + 正文 + 滚动条（`barX 312, barW 6`） |
| 底部栏 | 430–500 | 分隔线 + 今日状态 + 署名行 |
| 返回按钮 | 550–592 | `Box(79,550,202,42,5,C.widget)` + 描边 + 居中描边字 |

**三态**：正文（已解密）/ 密封章（标本未入库）/ 密封页（等级不足）。后两态居中显示提示文字，不画正文框内容。

正文滚动**必须缓存测量高度**：

```lua
local cacheKey = tostring(LOG.chapter) .. ":" .. tostring(LOG.page) .. ":" .. tostring(#body)
if LOG.cacheKey ~= cacheKey then                       -- 仅内容变化时重算
    local bounds = nvgTextBoxBounds(VIEW.vg, 47, LOG.textY + 4, LOG.boxW, body, nil)
    LOG.cacheH = ((bounds and bounds[4] or 0) - (bounds and bounds[2] or 0)) + 8
    LOG.cacheKey = cacheKey
end
```

### 10.4 排行榜浮层

`(18, 78, 324, 548)` —— 与日志同构，但用**列表视口**而非正文框。

| 区段 | y | 内容 |
| --- | --- | --- |
| 标题区 | 100–126 | 双行标题（11/`ash` + 10/`dim`），右上异常注释 |
| 我的记录 | 160–240 | 大数值(21/描边) + 收藏(12/`ash`) + 最高(12/`warn`) |
| 榜单标题 | 276 | `PUBLIC DATABASE / 全服榜 · N 人`(10/`cyan`) |
| 列表视口 | 290–540 | 行高 42，间距由 `RANK_LIST` 给 |
| 滚动条 | 右侧 | x = 328，宽 4 |
| 提示行 | 548 | 居中 10/`dim` |
| 关闭按钮 | 566–606 | `Box(78,566,204,40,5,C.widget)` |

**列表行**：

```lua
local edge = C.cyanDim
if entry.rank == 1 then edge = C.warn
elseif entry.isMe then edge = C.cyan end
Box(x, y, w, 42, 5, entry.isMe and C.readyCard or C.card)
StrokeBox(x, y, w, 42, 5, edge)
Text("#" .. entry.rank, x + 15,  y + 21, 14, entry.rank == 1 and C.warn or C.cyan)
Text(name,               x + 56,  y + 15, 13, entry.isMe and C.cyan or C.text)
Text("收藏 " .. n,        x + 56,  y + 31, 10, C.dim)
Text(FormatNumber(g) .. " 次", x + 273, y + 21, 13, C.blue, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
```

**只在视口内绘制**（无限列表的关键）：

```lua
nvgSave(VIEW.vg)
nvgScissor(VIEW.vg, RANK_LIST.x, RANK_LIST.y, RANK_LIST.w, RANK_LIST.h)
for i, entry in ipairs(FX.ranks) do
    local y = RANK_LIST.y + (i - 1) * RANK_LIST.step - RANK.scroll
    if y > RANK_LIST.y - RANK_LIST.step and y < RANK_LIST.y + RANK_LIST.h then
        -- 只画可见行
    end
end
nvgRestore(VIEW.vg)
```

### 10.5 广告条（四态）

`(118, 10, 76, 20)` 主钮 + `(196, 10, 46, 20)` 关闭钮。**同一位置四种状态**：

| 状态 | 外观 |
| --- | --- |
| 观看中 / 结算中 | 整条 `Box` widget + 描边，居中 8px `dim` 字 |
| 加速生效中 | 整条 `Box` **`washDim`**（alpha 220），居中 8px `text` 字 + 剩余时间 |
| 可观看 | 主钮 `Box` **`cyan`** + 8px **`ink`** 字；关闭钮 widget + 描边 |
| 已隐藏 | 不绘制 |

```lua
DrawAdOffer = function()
    local barX, barY, barW, barH = AD.watchX, AD.watchY, AD.watchW + AD.closeW, AD.watchH
    if AD.inFlight or AD.awaitingCallback then
        Box(barX, barY, barW, barH, 0, C.widget)
        StrokeBox(barX, barY, barW, barH, 0, C.cyanDim)
        Text(AD.inFlight and "广告中" or "结算中", barX + barW * 0.5, 20, 8, C.dim,
             NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        return
    end
    if AdBoostActive() then
        Box(barX, barY, barW, barH, 0, { C.washDim[1], C.washDim[2], C.washDim[3], 220 })
        Text("加速 " .. FormatClock(AdBoostRemain()), barX + barW * 0.5, 20, 8, C.text,
             NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        return
    end
    if not AdOfferVisible() then return end
    Box(AD.watchX, AD.watchY, AD.watchW, AD.watchH, 0, C.cyan)
    Text("看广告加速", AD.watchX + AD.watchW * 0.5, 20, 8, C.ink,
         NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    Box(AD.closeX, AD.closeY, AD.closeW, AD.closeH, 0, C.widget)
    StrokeBox(AD.closeX, AD.closeY, AD.closeW, AD.closeH, 0, C.cyanDim)
    Text("关掉", AD.closeX + AD.closeW * 0.5, 20, 8, C.text,
         NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end
```

**四态共用一个 y=10 的槽位**，切换时整条替换，不做位移过渡——广告条是功能性 UI，不是主体。

---

## 11. 管线

### 11.1 字体注册与重载

字体**只在初始化注册一次**，每帧注册会漏显存。重载时先删旧 face：

```lua
local ZPIX_FONT_PATH = "Fonts/zpix.ttf"    -- 从 ResourceCache 根算，不加 assets/

local function ApplyFonts()
    if not VIEW.vg then return end
    local oldId = nvgFindFont(VIEW.vg, "zpix")
    if oldId >= 0 then
        nvgDeleteFont(VIEW.vg, oldId)      -- 关键：不删旧 face 会泄漏
    end
    VIEW.font = nvgCreateFont(VIEW.vg, "zpix", ZPIX_FONT_PATH)
    if VIEW.font >= 0 then
        nvgFontFace(VIEW.vg, "zpix")
    else
        print("[Game] 加载本地 zpix 失败: " .. ZPIX_FONT_PATH)
    end
end

local function UseTechFont()
    if VIEW.font >= 0 then
        nvgFontFace(VIEW.vg, "zpix")       -- 每帧调用只切 face，开销极低
    end
end
```

`Text()` 内部已调 `UseTechFont()`，所以业务代码不用管字体。**但直接用 `nvgText` / `nvgTextBox` 绕过 `Text()` 时必须自己调 `UseTechFont()` 并设字号**（日志正文就是这种情况）。

### 11.2 主题切换

两套色板 key 集合完全一致，切换时**整表替换**：

```lua
local THEME_CYAN, THEME_ASH = 1, 2
local THEMES = {
    [THEME_CYAN] = { /* 完整 key 集 */ },
    [THEME_ASH]  = { /* 同样的 key 集 */ },
}
local C = THEMES[THEME_CYAN]              -- C 是可重新绑定的 upvalue

local function ApplyTheme(id)
    local theme = THEMES[id]
    if not theme then return end
    local switchedToCyan = id == THEME_CYAN and themeId_ ~= THEME_CYAN
    themeId_ = id
    C = theme                             -- 所有绘制函数立刻看到新色板
    if switchedToCyan then
        TextGlitch.TriggerNow()           -- 切回主色板时强制触发乱码
    end
end
```

**唯一约束**：绘制函数里必须写 `C.cyan`，**不能**在模块加载时把它取成局部变量（`local CYAN = C.cyan`）—— 那样切换会静默失效且不报错。详见 [`atmosphere.md`](atmosphere.md) 的「双色板结构等价」。

---

## 12. 组合清单（整屏图层）

### 绘制顺序（不可调换）

```text
HandleRender
├─ nvgBeginFrame(w, h, dpr)
├─ nvgScale(scale)
├─ ① letterbox 铺底          fill 整个屏幕设计空间
├─ nvgTranslate(ox, oy)      ← 进入 360×720
├─ ② DrawGame()
│   ├─ DrawLabBackground()   §4  背景机位 5 层
│   ├─ 状态栏                §10.1
│   ├─ DrawAdOffer()         §10.5
│   ├─ DrawCultivationTank() §6  主视觉 12 层
│   ├─ 数据卡 + 双按钮        §5.2 / §5.5
│   └─ 底部档案栏            §10.2
├─ ③ DrawLeaderboard()       §10.4  遮挡层 1
├─ ④ DrawScholarLog()        §10.3  遮挡层 2
├─ ⑤ HUD 反馈                §9  floating / toasts / tabPops
└─ TextGlitch.CommitFrame()  §see atmosphere.md
```

**顺序规则**：背景 → 主体 → 浮层 → HUD 反馈。**HUD 反馈永远最后**，否则会被浮层盖住。

### 区域坐标表（360×720 设计空间）

| 区域 | 坐标 | 尺寸 | 章节 |
| --- | --- | --- | --- |
| 状态栏 | `12, 10` | `336×62` | §10.1 |
| 排行榜入口 | `252, 42` | `88×24` | §10.1 |
| 广告条 | `118, 10` | `76×20` + `46×20` | §10.5 |
| 培养舱壳体 | `16, 86` | `328×369` | §6 |
| 舱内胆裁区 | `24, 126` | `312×321` | §6 |
| 主环圆心 | `180, 335` | r = 156 | §6 |
| 数据卡 | `16, 462` | `328×82` | §5.2 |
| 升级按钮 | `16, 550` | `156×40` | §10 |
| 日志按钮 | `180, 550` | `164×40` | §10 |
| 底部栏 | `0, 596` | `360×124` | §10.2 |
| 选项卡格 | `43 + (n−1)×70, 622` | `62×80` | §5.3 |
| 日志浮层 | `14, 78` | `332×548` | §10.3 |
| 排行榜浮层 | `18, 78` | `324×548` | §10.4 |

### 遮挡关系

浮层覆盖 y `78–626`，与培养舱（`86–455`）和数据卡（`462–544`）**完全重叠**。

这意味着浮层打开时，下层主体在**空转绘制**。若要优化，可在浮层打开时跳过被完全覆盖的主体——视觉无差别，省掉约 1/3 的动态绘制调用。同理，背景的静态部分（侧栏、刻度、支架）可烘焙成一张全屏贴图，每帧一次 `nvgImagePattern` 替代上百次 `Line`/`Box`。

---

## 13. 检查清单

**基座**

- [ ] 设计空间、缩放、letterbox 偏移在 `ScreenMode` 后重算
- [ ] 输入经 `Point()` 反变换，命中与绘制共用坐标
- [ ] 颜色经 `Color()` 取，支持三通道 + 覆盖 alpha

**原语**

- [ ] `StrokeBox` 用 `+0.5 / -1` 写法，描边不发虚
- [ ] 分层用 `GradientBox` 而非阴影

**装饰**

- [ ] 每窗 2–3 种母题，没有全上
- [ ] `MicroGrid` / `Halftone` 都在 `nvgScissor` 内
- [ ] 装饰 alpha 低于 `dim` 文字，不抢正文
- [ ] 母题参数（折角臂长、网格步长、刻度节奏）全项目一致

**复合构件**

- [ ] 面板/卡片有折角或左标记，不靠阴影分层
- [ ] 选项卡三态用底色 + 描边宽 + 左标记组合区分
- [ ] 进度轨用 `ink`，滚动条宽 4–6px、thumb ≥ 28px

**主视觉**

- [ ] 所有内部层包在同一个裁剪区
- [ ] 气泡/抖动用确定性函数，无 `math.random`
- [ ] 残影偏移小且固定（本项目 +7,−5）
- [ ] 幽灵标注 = 引线 + 十字 + 标签三件套

**背景**

- [ ] 背景全静态，只有轴标随脉冲呼吸
- [ ] 背景用粗线（3px），装饰用细线（1px），靠线宽分层
- [ ] 轴标用 `klein` 而非 `cyan`，不与交互元素混淆
- [ ] 双层圆结构（外圈 `cyanDim` + 内点 `cyan`）保持一致

**图像 / 文字**

- [ ] 图像走 `nvgImagePattern` + 圆角
- [ ] 图片按需加载，加载后检查 `ImageReady`
- [ ] 描边文字仅 ≥12px
- [ ] CJK 正文用 `nvgTextBox`，高度测量结果做缓存
- [ ] 绕过 `Text()` 直接用 `nvgText` 时，自己调 `UseTechFont()` 并设字号

**HUD 反馈**

- [ ] 三种反馈都走 `PushFx` 上限驱逐
- [ ] 绘制在**所有浮层之后**
- [ ] alpha 用 `life / 初始寿命` 归一化，不另存淡出计时器
- [ ] 移除用倒序遍历 + `table.remove`
- [ ] `Toast` 是唯一带实底盒的反馈

**界面骨架**

- [ ] 浮层三态（正常 / 未解锁 / 等级不足）都有对应排版
- [ ] 无限列表只画视口内行，`nvgScissor` 包住
- [ ] 正文滚动测量结果按内容 key 缓存
- [ ] 翻页箭头区与列表滚动区命中互不侵入
- [ ] 广告条四态共用同一槽位，状态切换不做位移过渡

**管线**

- [ ] 字体只在初始化注册一次
- [ ] 重载字体前先 `nvgFindFont` + `nvgDeleteFont` 删旧 face
- [ ] 资源路径从 ResourceCache 根算，不加 `assets/` 前缀
- [ ] 两套色板 key 集合完全一致
- [ ] 颜色在函数体内现取（`C.cyan`），不取成模块级局部变量

---

## 文件清单

```
.claude/skills/dark-tech-game-editor-ui/
├── SKILL.md                  # 风格总纲（设计 DNA、路线、工作流）
└── references/
    ├── elements.md           # 本文件：本项目 NanoVG 绘制元素库
    ├── nanovg.md             # 自绘路线：原语 + 窗口壳 + 装饰 + 控件
    ├── ui-bridge.md          # 组件路线：ExtendTheme + 自定义控件
    ├── tokens.md             # 令牌：色板 / 氛围色板 / 结构色 / 字号 / 圆角
    └── atmosphere.md         # 氛围层：脉冲 / 阈值分带 / 残影 / 文本异变
```
