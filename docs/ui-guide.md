# UrhoX UI 设计与代码实现完全指南

> 基于 `urhox-libs/UI` v1.2.0，使用 Yoga Flexbox 布局 + NanoVG 渲染。
> 本文档整理自 `engine-docs/recipes/ui.md`，供项目开发参考。

---

## 目录

1. [技术架构](#1-技术架构)
2. [初始化（三步必做）](#2-初始化三步必做)
3. [布局系统（Yoga Flexbox）](#3-布局系统yoga-flexbox)
4. [控件完整速查表](#4-控件完整速查表)
5. [布局控件](#5-布局控件)
6. [输入控件](#6-输入控件)
7. [选择控件](#7-选择控件)
8. [展示控件](#8-展示控件)
9. [导航控件](#9-导航控件)
10. [容器控件](#10-容器控件)
11. [浮层控件](#11-浮层控件)
12. [高级组件](#12-高级组件)
13. [主题系统](#13-主题系统)
14. [事件系统](#14-事件系统)
15. [动画与过渡](#15-动画与过渡)
16. [视觉属性增强](#16-视觉属性增强)
17. [图片与背景](#17-图片与背景)
18. [分辨率缩放策略](#18-分辨率缩放策略)
19. [自定义控件](#19-自定义控件)
20. [常用布局模式](#20-常用布局模式)
21. [常见陷阱与解决方案](#21-常见陷阱与解决方案)

---

## 1. 技术架构

| 层级 | 技术 | 说明 |
|------|------|------|
| 布局 | **Yoga**（React Native 布局引擎） | ⚠️ 不是标准 CSS，默认值有差异 |
| 渲染 | **NanoVG** | 矢量图形，硬件加速 |
| 脚本 | **Lua 5.4** | 所有 UI 代码均为 Lua |
| 坐标 | **基准像素（Base Pixels）** | 代码中使用的逻辑坐标单位 |

**Yoga 与 CSS 关键差异**：

| 属性 | CSS 默认值 | Yoga 默认值 | 影响 |
|------|-----------|-------------|------|
| `flexShrink` | 1（收缩） | **0（不收缩）** | 子元素可能溢出！ |
| `flexDirection` | row（水平） | **column（垂直）** | 默认纵向排列 |
| 盒模型 | content-box | **border-box** | padding 包含在 width/height 内 |

---

## 2. 初始化（三步必做）

```lua
local UI = require("urhox-libs/UI")

-- 步骤 1：初始化 UI 系统
UI.Init({
    fonts = {
        {
            family = "sans",
            weights = {
                normal = "Fonts/MiSans-Regular.ttf",
                bold   = "Fonts/MiSans-Bold.ttf",
            }
        }
    },
    scale = UI.Scale.DEFAULT,  -- 必须指定缩放策略（详见第18节）
})

-- 步骤 2：构建控件树
local root = UI.Panel {
    width = "100%", height = "100%",
    justifyContent = "center",
    alignItems = "center",
    children = {
        UI.Button {
            text = "开始游戏",
            variant = "primary",
            onClick = function(self) print("clicked") end,
        }
    }
}

-- 步骤 3：设置根控件（忘记调用 = 什么都不显示！）
UI.SetRoot(root)
```

**UI.Init 完整参数**：

```lua
UI.Init({
    fonts = { ... },                -- 字体配置（必填）
    scale = UI.Scale.DEFAULT,       -- 缩放策略
    -- theme = customTheme,         -- 自定义主题（可选）
    -- fontSizeMethod = "pixel",    -- "pixel"（默认）或 "char"
    -- autoEvents = true,           -- 自动事件订阅（默认 true）
})
```

**UI.SetRoot 说明**：

```lua
UI.SetRoot(root)             -- 设置根控件，不销毁旧控件
UI.SetRoot(newRoot, true)    -- 设置根控件并销毁旧控件
```

> **自动行为**：`SetRoot` 会将根容器的 `pointerEvents` 设为 `"box-none"`，防止全屏根容器拦截游戏输入。

---

## 3. 布局系统（Yoga Flexbox）

### 尺寸

```lua
{ width = 200, height = 100 }           -- 固定尺寸（基准像素）
{ width = "50%", height = "100%" }      -- 百分比（相对父容器）
{ width = "auto", height = "auto" }     -- 自动适应内容
{ minWidth = 100, maxWidth = 500 }      -- 约束
{ aspectRatio = 16/9 }                  -- 宽高比（Yoga 自动计算另一维度）
```

### Flex 布局

```lua
-- 方向（默认 "column" 垂直）
{ flexDirection = "row" }               -- 水平
{ flexDirection = "column" }            -- 垂直（默认）
{ flexDirection = "row-reverse" }       -- 水平反向
{ flexDirection = "column-reverse" }    -- 垂直反向

-- 主轴对齐（justifyContent）
{ justifyContent = "flex-start" }       -- 起点（默认）
{ justifyContent = "center" }           -- 居中
{ justifyContent = "flex-end" }         -- 终点
{ justifyContent = "space-between" }    -- 两端对齐
{ justifyContent = "space-around" }     -- 均匀分布
{ justifyContent = "space-evenly" }     -- 等距分布

-- 交叉轴对齐（alignItems）
{ alignItems = "flex-start" }           -- 顶部/左侧
{ alignItems = "center" }              -- 居中
{ alignItems = "flex-end" }            -- 底部/右侧
{ alignItems = "stretch" }             -- 拉伸（默认）
{ alignItems = "baseline" }            -- 文字基线对齐

-- Flex 弹性
{ flexGrow = 1 }                       -- 填充可用空间
{ flexShrink = 1 }                     -- 允许收缩（Yoga 默认为 0！）
{ flex = 1 }                           -- flexGrow + flexShrink 简写

-- 换行
{ flexWrap = "wrap" }                  -- 超出自动换行
{ flexWrap = "no-wrap" }               -- 不换行（默认）
```

### 间距

```lua
-- 子元素间距
{ gap = 8 }
{ rowGap = 8, columnGap = 16 }

-- 外边距（支持 CSS shorthand 数组）
{ margin = 16 }                        -- 四边
{ margin = { 10, 20 } }               -- 上下10, 左右20
{ margin = { 10, 20, 30, 40 } }       -- 上右下左
{ marginHorizontal = 16 }             -- 左+右
{ marginVertical = 8 }                -- 上+下
{ margin = "auto" }                   -- 自动居中

-- 内边距（border-box，包含在 width/height 内）
{ padding = 16 }                      -- 四边
{ paddingHorizontal = 16 }            -- 左+右
{ paddingVertical = 8 }               -- 上+下
```

### 定位

```lua
-- 相对定位（默认，参与 flex 流）
{ position = "relative" }

-- 绝对定位（脱离 flex 流）
{ position = "absolute", top = 10, right = 10 }

-- 固定定位（相对视口，脱离滚动）
{ position = "fixed", bottom = 20, right = 20 }

-- 粘性定位（仅 ScrollView 内垂直方向有效）
{ position = "sticky", stickyOffset = 0 }

-- 溢出处理
{ overflow = "visible" }               -- 默认
{ overflow = "hidden" }                -- 裁剪子元素
```

---

## 4. 控件完整速查表

| 分类 | 控件 | 用途 |
|------|------|------|
| 布局 | `UI.Panel` | 通用容器，背景/边框/裁剪 |
| 布局 | `UI.Label` | 文字显示 |
| 布局 | `UI.Divider` | 分隔线 |
| 布局 | `UI.SafeAreaView` | 设备安全区适配 |
| 布局 | `UI.ScrollView` | 可滚动容器 |
| 布局 | `UI.SimpleGrid` | 等宽列网格 |
| 输入 | `UI.Button` | 按钮 |
| 输入 | `UI.TextField` | 单行文本输入 |
| 输入 | `UI.Checkbox` | 复选框 |
| 输入 | `UI.Toggle` | 开关 |
| 输入 | `UI.Slider` | 滑块 |
| 输入 | `UI.Stepper` | 数字加减 |
| 输入 | `UI.Rating` | 星级评分 |
| 输入 | `UI.FileUpload` | 文件上传 |
| 选择 | `UI.Dropdown` | 下拉选择器 |
| 选择 | `UI.DatePicker` | 日期选择器 |
| 选择 | `UI.TimePicker` | 时间选择器 |
| 选择 | `UI.ColorPicker` | 颜色选择器 |
| 选择 | `UI.Calendar` | 完整日历 |
| 选择 | `UI.Menu` | 上下文菜单 |
| 选择 | `UI.Tree` | 树形结构 |
| 展示 | `UI.Card` | 卡片 |
| 展示 | `UI.Badge` | 通知徽标 |
| 展示 | `UI.Chip` | 标签/筛选 |
| 展示 | `UI.Avatar` | 用户头像 |
| 展示 | `UI.Alert` | 警告消息框 |
| 展示 | `UI.Tooltip` | 悬停提示 |
| 展示 | `UI.Skeleton` | 加载占位 |
| 展示 | `UI.RichText` | 富文本 |
| 展示 | `UI.ProgressBar` | 进度条 |
| 展示 | `UI.Spine` | Spine 骨骼动画（预览版）|
| 导航 | `UI.Tabs` | 标签页 |
| 导航 | `UI.Breadcrumb` | 面包屑 |
| 导航 | `UI.Pagination` | 分页 |
| 容器 | `UI.Accordion` | 折叠面板 |
| 容器 | `UI.Carousel` | 轮播 |
| 容器 | `UI.Timeline` | 时间线 |
| 容器 | `UI.Table` | 数据表格 |
| 容器 | `UI.List` | 简单列表 |
| 浮层 | `UI.Modal` | 模态对话框 |
| 浮层 | `UI.Drawer` | 侧边抽屉 |
| 浮层 | `UI.Popover` | 浮动面板 |
| 浮层 | `UI.Toast` | 临时通知 |

---

## 5. 布局控件

### Panel — 通用容器

```lua
UI.Panel {
    width = 300, height = 200,
    backgroundColor = { 240, 240, 240, 255 },
    borderRadius = 8,
    borderColor = { 200, 200, 200, 255 },
    borderWidth = 1,
    padding = 16,
    flexDirection = "row",
    gap = 8,
    overflow = "hidden",
    shadowBlur = 4,
    shadowColor = { 0, 0, 0, 40 },
    children = { ... },
}
```

### Label — 文字显示

```lua
UI.Label {
    text = "Hello World",
    fontSize = 14,
    fontColor = { 50, 50, 50, 255 },
    fontFamily = "sans",
    fontWeight = "bold",            -- "normal" | "bold"
    textAlign = "center",           -- "left" | "center" | "right"
    verticalAlign = "middle",       -- "top" | "middle" | "bottom"
    maxLines = 2,                   -- 超出显示省略号
    lineHeight = 1.4,               -- 行高倍数
    letterSpacing = 2,              -- 字间距
    textDecoration = "underline",   -- "none" | "underline" | "line-through"
    whiteSpace = "normal",          -- "nowrap"（单行，默认）| "normal"（自动换行）
    -- 文字特效
    textStroke = { width = 2, color = "#000000" },           -- 描边
    textShadow = { offsetX = 2, offsetY = 3, blur = 4, color = {0,0,0,128} },  -- 阴影
}
```

> **注意**：Label 默认 `pointerEvents = "none"`（点击穿透）。

**方法**：`SetText(text)` · `GetText()` · `SetFontSize(size)` · `SetFontColor(color)`

### ScrollView — 可滚动容器

```lua
UI.ScrollView {
    flexGrow = 1,
    flexBasis = 0,          -- ⚠️ 配合 flexGrow 必须设为 0！
    scrollX = false,
    scrollY = true,
    showScrollbar = true,
    bounces = true,
    -- 滚动吸附
    scrollSnapType = "y mandatory",  -- "y mandatory" | "y proximity" | "x mandatory"
    onScroll = function(self, x, y) end,
    children = { ... },
}

-- 子元素设置吸附点
UI.Panel { height = 300, scrollSnapAlign = "start" }  -- "start" | "center" | "end"
```

**方法**：`ScrollBy(dx, dy)` · `SetScroll(x, y)` · `ScrollToTop()` · `ScrollToBottom()` · `GetContentSize()`

### SimpleGrid — 等宽网格

```lua
UI.SimpleGrid {
    columns = 4,
    gap = 8,
    -- 或响应式列宽：
    -- minColumnWidth = 120,
    children = { ... },
}
```

---

## 6. 输入控件

### Button — 按钮

```lua
UI.Button {
    text = "点击我",
    variant = "primary",          -- "primary" | "secondary" | "danger" | "success"
    disabled = false,
    fontSize = 14,
    textColor = { 255, 255, 255, 255 },
    hoverBackgroundColor = { 50, 120, 230, 255 },
    pressedBackgroundColor = { 40, 100, 200, 255 },
    onClick = function(self) end,
}
```

**方法**：`SetText(text)` · `SetDisabled(bool)` · `IsDisabled()`

### TextField — 文本输入

```lua
UI.TextField {
    value = "",
    placeholder = "请输入...",
    password = false,
    maxLength = 100,
    disabled = false,
    onChange = function(self, value) end,
    onSubmit = function(self, value) end,  -- 按回车触发
    onFocus = function(self) end,
    onBlur = function(self) end,
}
```

**方法**：`SetValue(v)` · `GetValue()` · `SetPlaceholder(p)` · `Clear()` · `SelectAll()`

### Checkbox · Toggle · Rating · Slider

```lua
-- 复选框
UI.Checkbox { checked = false, label = "同意条款",
    onChange = function(self, checked) end }

-- 开关
UI.Toggle { checked = false,
    onChange = function(self, checked) end }

-- 星级评分
UI.Rating { value = 3, max = 5, allowHalf = true,
    onChange = function(self, value) end }

-- 滑块
UI.Slider {
    value = 50, min = 0, max = 100, step = 1,
    onChange = function(self, value) end,
    onChangeEnd = function(self, value) end,
}
```

---

## 7. 选择控件

### Dropdown — 下拉选择

```lua
UI.Dropdown {
    options = {
        { value = 1, label = "选项 A" },
        { value = 2, label = "选项 B" },
        { value = 3, label = "选项 C", disabled = true },
    },
    value = 1,
    placeholder = "请选择...",
    maxVisibleItems = 6,
    onChange = function(self, value, option) end,
}
```

**方法**：`SetValue(v)` · `GetValue()` · `SetOptions(opts)` · `Open()` · `Close()` · `Toggle()`

### DatePicker · TimePicker · ColorPicker

```lua
-- 日期选择
UI.DatePicker {
    value = { year = 2026, month = 2, day = 8 },
    onChange = function(self, date) end,
}

-- 时间选择
UI.TimePicker {
    hour = 14, minute = 30, second = 0,
    use24Hour = true,
    onChange = function(self, hour, minute, second) end,
}

-- 颜色选择
UI.ColorPicker {
    value = { 255, 0, 0, 255 },
    showAlpha = true,
    onChange = function(self, color) end,
}
```

---

## 8. 展示控件

### Card — 卡片

```lua
UI.Card {
    variant = "elevated",         -- "elevated" | "outlined" | "filled"
    elevation = 2,                -- 阴影深度 0-5
    hoverable = true,
    header = "卡片标题",
    coverImage = "Images/photo.png",
    coverHeight = 160,
    onClick = function(self) end,
}

-- 静态辅助
UI.Card.Simple("标题", "内容文本")
UI.Card.Media({ title = "照片", coverImage = "img.png" })
```

### Badge — 徽标

```lua
UI.Badge {
    content = 5,
    variant = "error",            -- "primary" | "success" | "warning" | "error"
    size = "md",                  -- "sm" | "md" | "lg"
    dot = false,                  -- 仅显示圆点
    max = 99,                     -- 超出显示 "99+"
    pulse = true,                 -- 脉冲动画
    position = "top-right",
}

-- 包裹其他控件
UI.Badge.Wrap(UI.Button { text = "邮件" }, 3, { variant = "error" })
```

### Chip — 标签

```lua
UI.Chip {
    label = "标签",
    variant = "filled",           -- "filled" | "outlined" | "soft"
    color = "primary",            -- "default" | "primary" | "secondary" | "success" | "warning" | "error"
    size = "md",
    deletable = true,
    selectable = true,
    selected = false,
    onDelete = function(self) end,
    onSelect = function(self, selected) end,
}

-- 筛选器组
UI.Chip.Group({ "全部", "热门", "最新" }, { onSelect = fn })
```

> ⚠️ `variant` 控制外观样式，`color` 控制颜色，两者独立。

### ProgressBar — 进度条

```lua
UI.ProgressBar {
    value = 0.7,                  -- 0-1
    variant = "primary",
    showLabel = true,
    indeterminate = false,
    -- 渐变填充
    fillGradient = {
        direction = "to-right",
        from = "#B8E75C",
        to = "#8DC63F",
    },
    -- 动画过渡
    transition = "value 0.3s easeOut",  -- SetValue() 自动平滑过渡
}
```

**自定义进度条（渐变 + 描边文字）**：

```lua
local wrapper = UI.Panel { width = 400, height = 36 }
wrapper:AddChild(UI.ProgressBar {
    value = 0.75, width = "100%", height = "100%",
    backgroundColor = "#EDE1CA",
    borderColor = "#D2A382", borderWidth = 3, borderRadius = 18,
    fillGradient = { direction = "to-right", from = "#B8E75C", to = "#8DC63F" },
    transition = "value 0.3s easeOut",
})
wrapper:AddChild(UI.Label {
    text = "75%", fontColor = "#FFFFFF",
    textStroke = { width = 2, color = "#729233" },
    textAlign = "center",
    position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
})
```

### Avatar — 用户头像

```lua
UI.Avatar {
    src = "Images/user.png",
    name = "张三",                -- 无图片时自动生成首字母
    size = "md",                  -- "xs"(24) | "sm"(32) | "md"(40) | "lg"(56) | "xl"(80) | 数字
    shape = "circle",             -- "circle" | "rounded" | "square"
    status = "online",            -- "online" | "offline" | "away" | "busy"
}

UI.Avatar.Group(
    { { name = "Alice" }, { name = "Bob" }, { name = "Charlie" } },
    { max = 3 }
)
```

### Alert · Skeleton · Tooltip

```lua
UI.Alert {
    title = "警告", message = "出了些问题",
    severity = "warning",         -- "info" | "success" | "warning" | "error"
    closable = true,
    onClose = function(self) end,
}

UI.Skeleton { variant = "text", lines = 3, animation = "pulse" }
UI.Skeleton.Card()                -- 静态辅助

UI.Tooltip {
    content = "提示文本",
    position = "top",             -- "top" | "bottom" | "left" | "right"
    delay = 0.3,
}
```

---

## 9. 导航控件

### Tabs — 标签页

```lua
UI.Tabs {
    tabs = {
        { id = "tab1", label = "常规", content = generalPanel },
        { id = "tab2", label = "设置", content = settingsPanel },
        { id = "tab3", label = "关于", disabled = true },
    },
    activeTab = "tab1",
    variant = "line",             -- "line" | "enclosed" | "pills"
    orientation = "horizontal",   -- "horizontal" | "vertical"
    onChange = function(self, tabId, tab) end,
}
```

**方法**：`SetActiveTab(id)` · `GetActiveTab()` · `AddTab(tab, content)` · `NextTab()` · `PrevTab()`

---

## 10. 容器控件

### Accordion — 折叠面板

```lua
UI.Accordion {
    items = {
        { id = "s1", title = "第一节", content = panel1 },
        { id = "s2", title = "第二节", content = "文本内容" },
    },
    variant = "default",          -- "default" | "outlined" | "separated"
    allowMultiple = false,
    onChange = function(self, expandedItems) end,
}

UI.Accordion.FAQ({
    { question = "问题1？", answer = "答案1" },
})
```

### Carousel — 轮播

```lua
UI.Carousel {
    items = { widget1, widget2, widget3 },
    autoPlay = true, interval = 3,
    showDots = true, showArrows = true,
    onChange = function(self, index) end,
}
```

### Table — 数据表格

```lua
UI.Table {
    columns = {
        { key = "name",  title = "姓名", width = 200 },
        { key = "age",   title = "年龄", width = 80 },
        { key = "email", title = "邮箱", flexGrow = 1 },
    },
    data = {
        { name = "Alice", age = 30, email = "alice@test.com" },
    },
    onRowClick = function(self, row, index) end,
}
```

---

## 11. 浮层控件

### Modal — 模态对话框

```lua
local modal = UI.Modal {
    title = "确认操作",
    size = "md",                  -- "sm" | "md" | "lg" | "xl" | "fullscreen"
    closeOnOverlay = true,
    closeOnEscape = true,
    onClose = function(self) self:Destroy() end,
}

modal:AddContent(UI.Label { text = "你确定要删除吗？" })

modal:SetFooter(UI.Panel {
    flexDirection = "row", justifyContent = "flex-end", gap = 8,
    children = {
        UI.Button { text = "取消", onClick = function() modal:Close() end },
        UI.Button { text = "确定", variant = "primary",
            onClick = function() doAction(); modal:Close() end },
    }
})

modal:Open()

-- 快捷静态方法
UI.Modal.Confirm({
    title = "删除？",
    message = "此操作不可撤销。",
    onConfirm = function() end,
})

UI.Modal.Alert({ title = "成功", message = "操作已完成。" })
```

**方法**：`Open()` · `Close()` · `Toggle()` · `IsOpen()` · `SetTitle(t)` · `AddContent(w)` · `SetFooter(w)`

### Drawer — 侧边抽屉

```lua
UI.Drawer {
    position = "right",           -- "left" | "right" | "top" | "bottom"
    size = 300,
    onClose = function(self) end,
}
```

### Toast — 临时通知

```lua
UI.Toast.Show("已保存！", {
    duration = 3,
    variant = "success",          -- "info" | "success" | "warning" | "error"
    position = "bottom",          -- "top" | "bottom"
})
```

### Popover — 浮动面板

```lua
UI.Popover {
    placement = "bottom",         -- "top" | "bottom" | "left" | "right" 及衍生
    trigger = "click",            -- "click" | "hover" | "focus" | "manual"
    content = "弹出内容",
    title = "标题",
    showArrow = true,
    maxWidth = 300,
}
```

---

## 12. 高级组件

### VirtualList — 万级数据虚拟列表

```lua
UI.VirtualList {
    data = items,                 -- 数据数组（支持万级）
    itemHeight = 40,              -- 固定项高度
    createItem = function()       -- 工厂：创建复用项控件
        return UI.Panel { height = 40 }
    end,
    bindItem = function(widget, data, index)  -- 绑定数据到控件
        widget:FindById("label").text = data.name
    end,
    onItemClick = function(data, index) end,
}
```

### ChatWindow — 聊天窗口

```lua
UI.ChatWindow {
    messages = { ... },
    onSend = function(self, text) end,
}
```

### DragDropContext — 拖拽系统

```lua
UI.DragDropContext {
    onDragStart = function(item, source) end,
    onDrop = function(item, target) end,
}
```

### InventoryManager / SkillTree

游戏专用组件，用于背包系统和技能树 UI。

---

## 13. 主题系统

### 获取颜色

```lua
-- 返回 { r, g, b, a } 表
UI.Theme.Color("primary")        -- 蓝色
UI.Theme.Color("secondary")      -- 灰色
UI.Theme.Color("success")        -- 绿色
UI.Theme.Color("error")          -- 红色
UI.Theme.Color("warning")        -- 琥珀

-- 返回 NVGcolor（可直接用于 nvgFillColor）
UI.Theme.NvgColor("primary")
```

### 获取间距与字号

```lua
-- 间距（基准像素）
UI.Theme.Spacing("xs")    -- 4
UI.Theme.Spacing("sm")    -- 8
UI.Theme.Spacing("md")    -- 16
UI.Theme.Spacing("lg")    -- 24
UI.Theme.Spacing("xl")    -- 32
UI.Theme.Spacing("xxl")   -- 48

-- 圆角
UI.Theme.Radius("sm")     -- 4
UI.Theme.Radius("md")     -- 8
UI.Theme.Radius("lg")     -- 12
UI.Theme.Radius("xl")     -- 16

-- 语义字号（pt）
UI.Theme.FontSizeOf("display")   -- 24
UI.Theme.FontSizeOf("headline")  -- 18
UI.Theme.FontSizeOf("title")     -- 15
UI.Theme.FontSizeOf("body")      -- 11（默认正文）
UI.Theme.FontSizeOf("small")     -- 9
UI.Theme.FontSizeOf("caption")   -- 8

-- 字体名称
UI.Theme.FontFace("sans", "bold")  -- 返回 "sans-bold"
```

### 自定义主题

```lua
UI.Theme.SetTheme(myTheme)

-- 继承默认主题并覆盖部分颜色
local theme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
    colors = {
        primary = { 255, 100, 0, 255 },   -- 橙色主题
    }
})
UI.Theme.SetTheme(theme)
```

---

## 14. 事件系统

### 指针事件

```lua
UI.Panel {
    onPointerEnter = function(event, widget) end,
    onPointerLeave = function(event, widget) end,
    onPointerDown  = function(event, widget) end,
    onPointerUp    = function(event, widget) end,
    onPointerMove  = function(event, widget) end,

    onClick = function(widget, event) end,   -- ⚠️ 注意参数顺序与指针事件不同！
}
```

**PointerEvent 属性**：

| 属性 | 类型 | 说明 |
|------|------|------|
| `x`, `y` | number | 基准像素坐标 |
| `pointerId` | number | 0=鼠标，N=触摸手指 |
| `pointerType` | string | "mouse" 或 "touch" |
| `button` | number | 0=左键，1=中键，2=右键 |
| `isPrimary` | boolean | 是否为主指针 |

**方法**：`event:StopPropagation()` · `event:IsTouch()` · `event:IsMouse()`

### 手势事件

```lua
UI.Panel {
    onTap = function(event, widget) end,
    onDoubleTap = function(event, widget) end,
    onLongPressStart = function(event, widget) end,
    onSwipe = function(event, widget) end,
    onSwipeLeft = function(event, widget) end,
    onSwipeRight = function(event, widget) end,
    onPanStart = function(event, widget) end,   -- 返回 true 表示处理
    onPanMove = function(event, widget) end,
    onPanEnd = function(event, widget) end,
    onPinchStart = function(event, widget) end,
    onPinchMove = function(event, widget) end,  -- 捏合缩放
}
```

**GestureEvent 属性**：`direction` · `velocity` · `deltaX/deltaY` · `totalDeltaX/totalDeltaY` · `scale`

### 命令式注册（OnEvent / OffEvent）

```lua
local btn = UI.Button { text = "hover me" }

btn:OnEvent("pointerenter", function(event, widget)
    widget:SetStyle({ scale = 1.1 })
end)
btn:OnEvent("pointerleave", function(event, widget)
    widget:SetStyle({ scale = 1.0 })
end)

-- 移除
btn:OffEvent("click", handler)   -- 移除指定处理器
btn:OffEvent("click")            -- 移除所有 click 处理器
```

### 指针事件控制

```lua
{ pointerEvents = "auto" }       -- 默认，正常接收事件
{ pointerEvents = "none" }       -- 穿透，不接收事件（Label 默认值）
{ pointerEvents = "box-none" }   -- 自身不接收，子控件正常接收
{ pointerEvents = "box-only" }   -- 自身接收，子控件不接收
```

### 游戏与 UI 输入协调

```lua
-- 在游戏输入处理前检查指针是否在 UI 上
if UI.IsPointerOverUI() then
    return  -- 跳过游戏输入（移动、射击等）
end
```

---

## 15. 动画与过渡

### 属性过渡（Transition）

配置后，通过 `SetStyle()` 修改属性时自动产生平滑过渡动画。

```lua
UI.Panel {
    transition = "all 0.3s easeOut",           -- 所有属性
    transition = "opacity 0.2s easeInOut",     -- 单属性
    transition = "backgroundColor 0.8s easeInOut, scale 0.3s easeOutBack",  -- 多属性
    opacity = 1.0,
}

-- 触发过渡（自动平滑动画）
widget:SetStyle({ opacity = 0.0 })
```

**可过渡属性**：`opacity` · `scale` · `rotate` · `translateX/Y` · `borderRadius` · `borderWidth` · `shadowBlur` · `backgroundColor` · `borderColor` · `fontColor`

**缓动函数**：`linear` · `easeIn` · `easeOut` · `easeInOut` · `easeInCubic` · `easeOutCubic` · `easeInExpo` · `easeOutExpo` · `easeInBack` · `easeOutBack` · `spring`

### 关键帧动画

```lua
widget:Animate({
    keyframes = {
        [0]   = { opacity = 0, translateY = 20 },
        [0.5] = { opacity = 1, translateY = 5 },
        [1]   = { opacity = 1, translateY = 0 },
    },
    duration = 0.5,
    easing = "easeOut",
    loop = true,             -- true=无限循环，数字=循环次数
    direction = "alternate", -- "normal" | "reverse" | "alternate"
    fillMode = "forwards",   -- "none"（默认）| "forwards" | "backwards" | "both"
    onComplete = function() end,
})

widget:StopAnimation()
```

**fillMode 说明**：

| 值 | 含义 |
|---|---|
| `"none"` | 动画结束后恢复原始值 |
| `"forwards"` | 动画结束后保持最后一帧 |
| `"backwards"` | 动画开始前立即应用第一帧（防止闪烁）|
| `"both"` | forwards + backwards |

---

## 16. 视觉属性增强

### 圆角、边框、阴影

```lua
UI.Panel {
    -- 每角圆角
    borderRadius = 8,
    borderRadius = { 8, 16, 8, 16 },       -- {TL, TR, BR, BL}
    borderRadiusTopLeft = 12,              -- 单角覆盖

    -- 每边边框
    borderWidth = 2,
    borderWidth = { 1, 2, 3, 4 },          -- 上右下左（CSS shorthand）
    borderColor = { 200, 200, 200, 255 },
    borderTopWidth = 2, borderTopColor = { 255, 0, 0, 255 },

    -- 增强阴影
    boxShadow = {
        { x = 0, y = 2, blur = 8, spread = 0, color = { 0, 0, 0, 40 } },
        { x = 0, y = 1, blur = 3, spread = 0, color = { 0, 0, 0, 20 }, inset = true },
    },

    -- 背景模糊（近似效果）
    backdropBlur = 10,
}
```

### 渐变背景

```lua
-- 线性渐变
{ backgroundGradient = {
    type = "linear",
    direction = "to-bottom",       -- "to-bottom" | "to-right" | 角度数字
    from = { 59, 130, 246, 255 },
    to = { 147, 51, 234, 255 },
} }

-- 径向渐变
{ backgroundGradient = {
    type = "radial",
    innerRadius = 0,
    outerRadius = 100,
    from = { 255, 255, 255, 255 },
    to = { 0, 0, 0, 255 },
} }
```

### Transform、Opacity

```lua
{ opacity = 0.5 }                          -- 透明度（影响整个子树）
{ scale = 1.5 }                            -- 均匀缩放
{ rotate = 45 }                            -- 旋转角度
{ translateX = 10, translateY = 20 }       -- 平移
{ transformOrigin = "center" }             -- "center" | "top-left" | {x, y}
{ zIndex = 10 }                            -- 渲染和命中测试顺序
{ visibility = "hidden" }                  -- 隐藏但保持布局空间
```

### 裁剪路径

```lua
{ clipPath = "circle" }                    -- 圆形裁剪
{ clipPath = "ellipse" }                   -- 椭圆裁剪
{ clipPath = { type = "circle", radius = 50 } }
```

---

## 17. 图片与背景

```lua
-- 背景图
UI.Panel {
    backgroundImage = "Images/bg.png",
    backgroundFit = "cover",               -- "fill" | "contain" | "cover"
}

-- 九宫格（可拉伸 UI 元素）
UI.Panel {
    backgroundImage = "Images/frame.png",
    backgroundFit = "sliced",
    backgroundSlice = { top = 10, right = 10, bottom = 10, left = 10 },
}

-- 图片叠色（乘法混合，用于压暗/染色）
UI.Panel {
    backgroundImage = "Images/portrait.png",
    backgroundFit = "cover",
    imageTint = { 115, 115, 115, 255 },    -- 压暗到约 45%
    -- 支持 hex：imageTint = "#737373"
    -- 支持 transition 动画
}
```

---

## 18. 分辨率缩放策略

**公式**：物理像素 = 基准像素 × scale

| 预设 | 说明 | 推荐场景 |
|------|------|----------|
| `UI.Scale.DEFAULT`<br>`UI.Scale.DPR_DENSITY_ADAPTIVE` | 小屏密度自适应，**默认推荐** | 大多数游戏 |
| `UI.Scale.DPR` | 1 基准像素 = 1 CSS 像素，跨设备视觉大小一致 | 追求 Web 一致性 |
| `UI.Scale.DESIGN_RESOLUTION(w, h)` | 按设计稿尺寸开发 | 明确设计分辨率时 |

```lua
-- 默认（推荐）
UI.Init({ scale = UI.Scale.DEFAULT })

-- 设计分辨率模式（设计稿 1080x1920）
UI.Init({ scale = UI.Scale.DESIGN_RESOLUTION(1080, 1920) })

-- 自定义缩放逻辑
UI.Init({
    scale = function()
        local dpr = graphics:GetDPR()
        return dpr * yourFactor
    end,
})
```

> ⚠️ `graphics:SetMode()` 已禁用。获取屏幕信息用：
> ```lua
> local physW, physH = graphics:GetWidth(), graphics:GetHeight()
> local dpr = graphics:GetDPR()
> local logW, logH = physW / dpr, physH / dpr
> ```

---

## 19. 自定义控件

```lua
local MyWidget = UI.Widget:Extend("MyWidget")

function MyWidget:Init(props)
    props = props or {}
    props.height = props.height or 40
    props.backgroundColor = props.backgroundColor or { 200, 200, 200, 255 }
    UI.Widget.Init(self, props)   -- 必须调用父类 Init
    self.myField_ = 0
end

function MyWidget:Render(nvg)
    self:RenderFullBackground(nvg)  -- 渲染背景 + 边框 + 阴影

    local l = self:GetAbsoluteLayout()   -- { x, y, w, h }
    -- 自定义 NanoVG 绘制
    nvgFontFace(nvg, UI.Theme.FontFace("sans", "normal"))
    nvgFontSize(nvg, UI.Theme.FontSize(12))
    nvgFillColor(nvg, UI.Theme.NvgColor("text"))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, l.x + 8, l.y + l.h / 2, "自定义文字")
end

function MyWidget:Update(dt)
    -- 每帧调用，用于动画更新
end

function MyWidget:OnClick(event)
    -- 点击响应
end

return MyWidget
```

### Widget 基础方法速查

```lua
-- 子控件管理
widget:AddChild(child)
widget:InsertChild(child, index)  -- 1-based
widget:RemoveChild(child)
widget:ClearChildren()
widget:FindById("myId")           -- 递归查找

-- 可见性
widget:Show() / widget:Hide()
widget:SetVisible(bool) / widget:IsVisible()

-- 布局查询
widget:GetLayout()                 -- {x,y,w,h} 相对父容器
widget:GetAbsoluteLayout()         -- {x,y,w,h} 绝对坐标
widget:GetComputedSize()           -- (width, height)

-- 属性路由（自动调用对应 SetXxx 方法）
widget.text = "Hello"             -- → widget:SetText("Hello")
widget.visible = false            -- → widget:SetVisible(false)
widget.width = 300                -- → widget:SetWidth(300)

-- 销毁
widget:Destroy()                  -- 销毁控件及所有子控件
widget:Remove()                   -- 从父控件移除（可重新添加）
```

---

## 20. 常用布局模式

### 全屏三段式布局（顶栏 + 内容 + 底栏）

```lua
local root = UI.Panel {
    width = "100%", height = "100%",
    flexDirection = "column",
    children = {
        -- 顶栏（固定高度）
        UI.Panel {
            height = 60,
            flexDirection = "row",
            alignItems = "center",
            paddingHorizontal = 16,
            backgroundColor = UI.Theme.Color("primary"),
            children = {
                UI.Label { text = "游戏标题", fontColor = {255,255,255,255}, fontWeight = "bold" },
                UI.Spacer(),
                UI.Button { text = "设置", variant = "secondary" },
            }
        },
        -- 内容区（填充剩余空间 + 可滚动）
        UI.ScrollView {
            flexGrow = 1,
            flexBasis = 0,          -- 关键！
            padding = 16,
            children = { contentPanel },
        },
        -- 底栏（固定高度）
        UI.Panel {
            height = 50,
            justifyContent = "center", alignItems = "center",
            children = { UI.Label { text = "© 2026" } }
        },
    }
}
UI.SetRoot(root)
```

### 表单布局

```lua
UI.Panel {
    flexDirection = "column", gap = 16, padding = 20,
    children = {
        UI.Label { text = "用户名", fontWeight = "bold" },
        UI.TextField {
            placeholder = "请输入用户名",
            onChange = function(self, v) username = v end,
        },
        UI.Label { text = "密码", fontWeight = "bold" },
        UI.TextField {
            placeholder = "请输入密码",
            password = true,
            onChange = function(self, v) password = v end,
        },
        UI.Button {
            text = "登录", variant = "primary",
            onClick = function() login(username, password) end,
        },
    }
}
```

### 居中弹窗

```lua
local modal = UI.Modal {
    title = "编辑资料", size = "md",
    onClose = function(self) self:Destroy() end,
}
modal:AddContent(UI.Panel {
    flexDirection = "column", gap = 12,
    children = {
        UI.TextField { placeholder = "姓名" },
        UI.TextField { placeholder = "邮箱" },
    }
})
modal:SetFooter(UI.Panel {
    flexDirection = "row", justifyContent = "flex-end", gap = 8,
    children = {
        UI.Button { text = "取消", onClick = function() modal:Close() end },
        UI.Button { text = "保存", variant = "primary",
            onClick = function() save(); modal:Close() end },
    }
})
modal:Open()
```

### 水平 Chip 标签组

```lua
UI.Panel {
    flexDirection = "row", gap = 8, flexWrap = "wrap",
    children = {
        UI.Chip { label = "全部", variant = "filled", color = "primary", selected = true },
        UI.Chip { label = "热门", variant = "outlined" },
        UI.Chip { label = "最新", variant = "outlined" },
    }
}
```

### 辅助工具快速布局

```lua
-- 水平/垂直布局简写
UI.Row { gap = 8, children = { a, b, c } }
UI.Column { gap = 8, children = { a, b, c } }

-- 弹性空白（把左右推开）
UI.Row {
    children = {
        UI.Label { text = "左侧" },
        UI.Spacer(),
        UI.Label { text = "右侧" },
    }
}

-- 防截断的按钮组（自动换行）
UI.ButtonGroup {
    UI.Button { text = "保存", variant = "primary" },
    UI.Button { text = "取消" },
}

-- 固定尺寸占位
UI.Box(100, 50)
```

---

## 21. 常见陷阱与解决方案

### ❌ 陷阱 1：忘记调用 `UI.SetRoot()`

```lua
-- 错误：什么都不渲染
local root = UI.Panel { ... }
-- 缺少 UI.SetRoot(root)！

-- 正确：
UI.SetRoot(root)
```

### ❌ 陷阱 2：子元素溢出（flexShrink 默认 0）

```lua
-- 错误：250px 子元素放在 200px 容器里溢出
UI.Panel { height = 200, children = {
    UI.Panel { height = 150 },   -- 溢出！
    UI.Panel { height = 100 },
} }

-- 正确：设置 flexShrink = 1
UI.Panel { height = 150, flexShrink = 1 }
```

### ❌ 陷阱 3：ScrollView 不滚动

```lua
-- 错误：缺少 flexBasis = 0
UI.ScrollView { flexGrow = 1 }   -- 不会滚动！

-- 正确：
UI.ScrollView { flexGrow = 1, flexBasis = 0 }
-- 或使用固定高度：
UI.ScrollView { height = 400 }
```

### ❌ 陷阱 4：maxHeight 导致 flexGrow 子元素坍缩

```lua
-- 错误：maxHeight 不是确定尺寸，flexGrow 分到 0
UI.Panel {
    maxHeight = "85%",
    children = {
        UI.Panel { height = 56 },
        UI.ScrollView { flexGrow = 1, flexBasis = 0 },  -- 高度变成 0！
    }
}

-- 正确：换用 height
UI.Panel {
    height = "85%",
    children = {
        UI.Panel { height = 56 },
        UI.ScrollView { flexGrow = 1, flexBasis = 0 },  -- 正常填充
    }
}
```

### ❌ 陷阱 5：混淆 Chip 的 variant 和 color

```lua
-- 错误：variant 不是颜色，是外观样式
UI.Chip { label = "标签", variant = "primary" }    -- primary 不是有效 variant！

-- 正确：
UI.Chip { label = "标签", variant = "filled", color = "primary" }
```

### ❌ 陷阱 6：onClick 与指针事件参数顺序不同

```lua
-- onClick：function(widget, event)
onClick = function(self, event) end

-- 指针/手势事件：function(event, widget)
onPointerDown = function(event, widget) end
onTap = function(event, widget) end
```

### ❌ 陷阱 7：百分比宽度无效

```lua
-- 错误：父容器无宽度，50% 无从计算
UI.Panel { children = { UI.Panel { width = "50%" } } }

-- 正确：父容器需有明确宽度
UI.Panel { width = "100%", children = { UI.Panel { width = "50%" } } }
```

### ❌ 陷阱 8：浮层销毁顺序

```lua
-- 错误：直接 Destroy 会跳过浮层栈移除
modal:Destroy()

-- 正确：先关闭再销毁
modal:Close()
modal:Destroy()

-- 或在 onClose 中处理
UI.Modal {
    onClose = function(self) self:Destroy() end
}
```

---

*整理自 engine-docs/recipes/ui.md，版本 v1.2.0*
*最后更新：2026-05-15*
