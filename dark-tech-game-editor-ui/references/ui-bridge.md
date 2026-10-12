# 组件路线：`urhox-libs/UI` + `ExtendTheme`

适用：菜单、表单、列表、弹窗、HUD、标签页，以及任何需要滚动 / 虚拟列表 / 拖拽 / 复杂交互的界面。

产出：**一份主题配置** + 业务代码里的标准组件调用。不需要逐控件写绘制代码。

## 为什么默认走这条路

- 45 个内置控件自动获得 Dark Tech 视觉，改一处令牌全项目生效。
- Yoga 算布局，滚动、手势、焦点、高 DPI 命中、letterbox 坐标都免费。
- 状态（hover / pressed / focus / disabled）由主题驱动，不用写 `if`。
- 组件的滚动、虚拟列表、拖拽是引擎实现，自绘重写一遍既慢又容易出 bug。

代价是受组件 API 约束。所以：**先看内置组件能不能表达，不能才自定义控件，再不能才纯自绘。**

## 接入三步

1. 建一个主题包模块（下称 `ThemePack`），导出 `C`（令牌表）、`Create()`（返回主题）、语义色。
2. `Start()` 里 `UI.Init { theme = ThemePack.Create(), scale = UI.Scale.DEFAULT }`。
3. 业务代码写 `UI.Panel { ... }` / `UI.Button { variant = "primary" }`，不要逐控件写颜色和圆角。

## 主题映射

令牌 → 主题字段。左边是本文档的令牌，右边是 `urhox-libs/UI` 认识的名字。

| 令牌 | 主题字段 | 说明 |
| --- | --- | --- |
| `bg` | `background` | 全屏底。**不要**用纯黑 |
| `panel` | `surface` | 窗口外壳 |
| `rail` | `surfaceAlt` | 内容区、侧栏 |
| `widget` | `surfaceHover` / `disabled` | 输入框底、hover 态 |
| `cyan` | `primary` / `success` / `info` | 主操作、进度、焦点 |
| `cyanDim` | `border` | 弱描边、分隔 |
| `cyan` | `borderFocus` | 聚焦描边 |
| `ink` | `variantTextColor.primary` | 青底上的字 |
| `text` | `text` | 主文字 |
| `dim` | `textSecondary` / `disabledText` | 次文字、禁用 |
| `warn` | `warning` | 警告 |

`primaryHover` / `primaryPressed` 由 `cyan` 提亮或压暗得到，不要另开新色相。

### 完整主题包

这是一份可直接改用的主题包。删掉项目不需要的字段即可，但**不要**把圆角改大、不要加厚阴影——那会破坏风格。

```lua
-- Theme.lua：Dark Tech 主题包
local UI = require("urhox-libs/UI")

local C = {
    bg      = { 7, 11, 20, 236 },
    panel   = { 10, 16, 28, 248 },
    rail    = { 12, 20, 34, 255 },
    card    = { 16, 26, 44, 255 },
    widget  = { 22, 36, 56, 255 },
    cyan    = { 0, 229, 208, 255 },
    cyanDim = { 0, 150, 148, 220 },
    ink     = { 4, 8, 16, 255 },
    text    = { 240, 248, 252, 255 },
    dim     = { 120, 148, 162, 255 },
    warn    = { 255, 196, 72, 255 },
    error   = { 232, 93, 91, 255 },
}

local M = {}
M.C = C

function M.Create()
    return UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/NotoSansSC-Black.ttf",
                bold   = "Fonts/NotoSansSC-Black.ttf",
            } },
        },
        colors = {
            -- 主强调：酸青只给焦点 / 主操作 / 进度
            primary        = C.cyan,
            primaryHover   = { 64, 240, 224, 255 },
            primaryPressed = { 0, 180, 168, 255 },
            borderFocus    = C.cyan,
            success        = C.cyan,
            info           = C.cyan,

            -- 层级：越往上越亮，靠明度差分层而不是靠阴影
            background   = C.bg,
            surface      = C.panel,
            surfaceAlt   = C.rail,
            surfaceHover = C.widget,
            secondary        = C.card,
            secondaryHover   = C.widget,
            secondaryPressed = { 14, 22, 38, 255 },

            -- 文字三级
            text           = C.text,
            textSecondary  = C.dim,
            textDisabled   = { 90, 112, 124, 255 },
            disabledText   = C.dim,
            disabled       = C.widget,

            -- 描边：细、偏青，不要纯白
            border = C.cyanDim,

            warning        = C.warn,
            warningHover   = { 255, 215, 110, 255 },
            error          = C.error,
            errorHover     = { 255, 118, 115, 255 },
            errorPressed   = { 179, 64, 66, 255 },
            danger         = C.error,
            dangerHover    = { 255, 118, 115, 255 },
            dangerPressed  = { 179, 64, 66, 255 },

            overlay = { 7, 11, 20, 200 },
            hover   = { 0, 229, 208, 28 },   -- 极淡的青，用于 hover 底
        },
        -- 小圆角。不要 9999，不要 0
        radius = {
            none = 0, xs = 3, sm = 4, md = 6, lg = 8, xl = 10, full = 11,
        },
        componentDefaults = {
            borderRadius = 6,
            fontWeight = "bold",
        },
        components = {
            Button = {
                borderWidth = 1, borderRadius = 6,
                fontWeight = "bold", height = 36, fontSize = 12,
                padding = { 6, 12, 6, 12 },
                -- 主按钮青底配深字；其余保持浅字
                variantTextColor = {
                    primary = C.ink, success = C.ink,
                    secondary = C.text, danger = C.text, error = C.text,
                },
            },
            Card     = { borderWidth = 1, borderRadius = 6 },
            Panel    = { borderRadius = 6 },
            Badge    = { borderWidth = 1, borderRadius = 4 },
            -- 胶囊 Chip 用 11，不是 9999
            Chip     = { borderWidth = 1, borderRadius = 11, height = 22, fontSize = 10 },
            Avatar   = { showBorder = true },
            Label    = { fontWeight = "bold" },
            ProgressBar = { borderRadius = 3, height = 8 },
            Toast = {
                borderWidth = 1, borderRadius = 6,
                accentBarWidth = 3, accentBarHeight = 24, accentBarInset = 8,
                showIcon = false,          -- 技术舱不摆大图标
            },
            Modal = {
                borderWidth = 1, borderRadius = 6,
                headerBgColor = C.panel, contentBgColor = C.rail,
                headerBorderWidth = 1, footerBorderWidth = 0,
                headerFullWidthBorder = true,
                titleTextColor = C.cyan,   -- 标题青，取自令牌
            },
        },
    })
end

-- 语义色：不要就地取近似色，统一从这里取
M.Rarity = {
    common    = C.dim,
    uncommon  = { 72, 196, 168, 255 },
    rare      = { 64, 176, 220, 255 },
    epic      = { 168, 120, 220, 255 },
    legendary = C.warn,
}
M.HP    = { 232, 93, 91, 255 }
M.Trail = { 255, 208, 84, 255 }   -- 掉血滞后段
M.MP    = C.cyan
M.Armor = C.warn
M.Gold  = C.warn
M.XP    = { 77, 177, 255, 255 }

return M
```

### 注入

```lua
-- Start()
UI.Init({
    theme = ThemePack.Create(),
    scale = UI.Scale.DEFAULT,
})
```

`scale = UI.Scale.DEFAULT` 让组件按逻辑分辨率响应式适配，不要再自己算 DPR——那是自绘路线才需要操心的事。

## 组件选择对照

| 需求 | 用哪个组件 | 关键属性 |
| --- | --- | --- |
| 窗口外壳 | `UI.Panel` | `backgroundColor = C.panel`, `borderColor = C.cyanDim`, `borderWidth = 1` |
| 内容区 / 侧栏 | `UI.Panel` | `backgroundColor = C.rail`, `overflow = "hidden"` |
| 卡片 | `UI.Card` | 主题已给边框 + 圆角 |
| 主 / 次按钮 | `UI.Button` | `variant = "primary"` / `"secondary"` |
| 标签选择 | `UI.Chip` | 主题已给半径 11、高 22 |
| 输入 | `UI.TextField` | 聚焦描边由 `borderFocus` 给 |
| 长列表 | `UI.ScrollView` / `UI.VirtualList` | 超过百条用 `VirtualList` |
| 弹窗 | `UI.Modal` | `titleTextColor` 已是 `cyan` |
| 轻提示 | `UI.Toast` | 关掉图标更贴风格 |
| 进度 | `UI.ProgressBar` | 高 8、半径 3 |
| 标签页 | `UI.Tabs` | — |

组件全部属性见 `urhox-libs/UI/Widgets/*.lua` 源码头部注释，或 `engine-docs/recipes/ui.md`。

## 自定义控件：`UI.Widget:Extend`

内置组件表达不了的图形（进度条、雷达、波形、培养舱、特殊装饰），用自定义控件下沉到 NanoVG——但**布局、命中、层叠仍由组件负责**。

```lua
---@class TechBarProps : WidgetProps
---@field value? number
---@field max? number

---@class TechBar : Widget
---@overload fun(props?: TechBarProps): TechBar
local TechBar = UI.Widget:Extend("TechBar")

function TechBar:Init(props)
    props = props or {}
    props.height = props.height or 8
    props.value = props.value or 0
    props.max = math.max(1, props.max or 1)
    props.borderRadius = props.borderRadius or 4
    UI.Widget.Init(self, props)      -- 必须调父类，且要在设完默认值之后
end

function TechBar:SetValue(v, max)
    if max then self.props.max = math.max(1, max) end
    self.props.value = v
end

function TechBar:Render(nvg)
    local l = self:GetAbsoluteLayout()   -- 组件算好的绝对坐标
    if l.w <= 0 or l.h <= 0 then return end

    local props = self.props
    local r = math.min(props.borderRadius, math.min(l.w, l.h) / 2)

    -- 轨道
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, r)
    nvgFillColor(nvg, nvgRGBA(C.ink[1], C.ink[2], C.ink[3], 255))
    nvgFill(nvg)

    -- 进度
    local t = math.max(0, math.min(props.max, props.value)) / props.max
    local w = l.w * t
    if w > 0 then
        nvgBeginPath(nvg)
        if w >= l.w - 0.5 then
            nvgRoundedRect(nvg, l.x, l.y, w, l.h, r)
        else
            nvgRoundedRectVarying(nvg, l.x, l.y, w, l.h, r, 0, 0, r)
        end
        nvgFillColor(nvg, nvgRGBA(C.cyan[1], C.cyan[2], C.cyan[3], 255))
        nvgFill(nvg)
    end
end

return TechBar
```

使用：

```lua
TechBar { id = "ManaBar", width = "100%", height = 8, value = 60, max = 100 }
```

**要点**

- **必须调 `UI.Widget.Init(self, props)`**，且在所有默认值之后，否则布局和主题属性不会生效。
- `GetAbsoluteLayout()` 返回 `{ x, y, w, h }`，是最终屏幕坐标（已含滚动偏移与变换）。**用它，不要自己算坐标**——这正是「绘制与命中同源」的保证。
- 需要背景 / 边框 / 阴影时，在 `:Render` 开头调 `self:RenderFullBackground(nvg)`，它会按主题和当前状态画好，你再在上面叠加自定义图形。
- 取主题色用 `UI.Theme.Color("primary")`，取换算字号用 `UI.Theme.FontSize(pt)`，不要在控件里硬编码十六进制。
- 若要响应 hover / pressed，在 `:Init` 里自建 `self.state = { hovered = false, pressed = false }`（基类不预置字段，字段名由控件自己定，参见 `urhox-libs/UI/Widgets/Button.lua` 的写法），并自行在事件里更新。
- `:Update(dt)` 每帧调用，做动画；`:OnClick(event)` 接点击。

## 什么时候下沉到 NanoVG

| 情况 | 选择 |
| --- | --- |
| 内置组件 + 主题就能表达 | 用组件，不写一行绘制代码 |
| 需要全新图形（进度环、波形、培养舱） | `UI.Widget:Extend` + `:Render` |
| 需要装饰花纹（角标、刻度、网格、扫描带） | 优先用 `UI.Sprite` / `UI.Panel` 拼；拼不出来再自定义控件 |
| 整个界面没有标准控件、且无布局约束 | 纯自绘，见 [`nanovg.md`](nanovg.md) |

**不要**在组件树里直接调 `nvgBeginFrame`——矢量绘制要么挂在 `NanoVGRender` 事件（纯自绘路线），要么写在自定义控件的 `:Render(nvg)` 里（混用路线）。
