---
name: dark-tech-game-editor-ui
description: "深海军酸青技术舱 UI（Dark Tech / Ecnach）。做游戏窗口、编辑器面板、HUD、培养舱、实验室、工具浮层、属性检查器、菜单、日志页时用本 skill；不要用 ui-astroon 的发光药丸按钮，也不要用 ui-pixelforge 的直角硬阴影。Use when (1) 深海军/酸青/技术舱/像素科技 UI, (2) 深夜实验室、培养舱、编辑器窗口、HUD chrome, (3) 给 urhox-libs/UI 组件套深色科技主题（ExtendTheme 映射）, (4) NanoVG 自定义窗口壳/角标/微型网格/扫描带, (5) dark navy acid-cyan pixel-tech / lab HUD / editor overlay, (6) 用户提到 Ecnach、dark-tech、技术舱风格。SKIP：宇宙卡通霓虹渐变 → ui-astroon；复古 8-bit 直角像素 → ui-pixelforge；只问 urhox-libs/UI 组件 API → engine-docs/recipes/ui.md。本 skill 只规定视觉、排版、层级和绘制，不规定业务玩法。"
---

# Dark Tech / Ecnach UI

给 AI 的外观规范。用户要「按这个风格做界面 / 美化窗口 / 实验室 HUD / 编辑器面板」时，按本文出 UrhoX Lua 代码。

气质：深夜技术舱、轻像素、克制霓虹、信息密但不花。像仪器，不像商店页。

## 何时用 / 何时不用

用：窗口壳、工具面板、浮层、检查器、菜单、HUD、培养舱、日志页、标本库。

不用：规定玩法、数据模型、点击后发生什么。那些由调用方决定。

别和另外两套风格混：

| 风格 | 一眼区别 | 不要带到本风格里 |
| --- | --- | --- |
| 本风格 | 深海军层级 + 酸青焦点 + 小圆角 + 角标/刻度 | — |
| `ui-astroon` | 宇宙渐变、药丸按钮、外发光、金 CTA | 发光阴影、`radius 9999`、大渐变底 |
| `ui-pixelforge` | 直角、2px 内描边、硬投影、高饱和 | `radius = 0`、硬阴影、把所有边做成块 |

## 两条路线

本风格有两条落地路线，产出同一种视觉。**先选路线，再写代码。**

| | **A. 组件路线**（默认） | **B. 自绘路线** |
| --- | --- | --- |
| 技术 | `urhox-libs/UI` + `UI.Theme.ExtendTheme` | raw NanoVG |
| 布局 | Yoga Flexbox，自动 | 手算坐标 |
| 命中区 | 组件自动处理 | 必须自己保证绘制与命中共用同一套几何 |
| 适用 | 菜单、表单、列表、弹窗、HUD、需要滚动 / 虚拟列表 / 拖拽的界面 | 培养舱、扫描带、自定义图形、无设计稿约束的画布、纯装饰 |
| 代价 | 受组件 API 约束 | 每个像素都要自己画、自己接输入 |
| 详见 | [`references/ui-bridge.md`](references/ui-bridge.md) | [`references/nanovg.md`](references/nanovg.md) |

两条路线都可以（也应该）叠加**氛围层**——让界面「死气沉沉地活着」的那一层。它独立于路线选择，用同一个氛围标量驱动残影、扫描带、强调色切换、文本异变与音频。要做出本风格真正的辨识度，读 [`references/atmosphere.md`](references/atmosphere.md)。

**界面里的图标 / 字标 / 徽章从哪来？** 面板、按钮、进度条、装饰花纹一律**程序化绘制**（它们是几何，不是素材）；只有「一个具体的物」（炸弹、护盾、奖章）或「一段艺术字」（游戏 logo）才做成像素贴图。生成、量化、进包、装载、显示倍率的完整接线图见 [`references/pipeline.md`](references/pipeline.md)——它把 skill `0718-pixelimage-aigc` 接到本风格上，并给出「图标 32×32 / ≤9 色 / 最近邻 / `.meta` uuid」这套本项目已落地的规格。

需要**具体的绘制元素**（培养舱 12 层、装饰母题参数、帧序列淡化、幽灵标注、滚动条与选项卡规格）时，直接查 [`references/elements.md`](references/elements.md)——那是本项目已落地的元素库，含可复制代码，不要重新发明。

**默认走 A。** 组件能表达的，不要自己画——组件顺带解决滚动、手势、焦点、无障碍与高 DPI 命中，这些自绘都要重写一遍。只有组件表达不出来的图形才下沉到 B。

### 混用：桥在 `UI.Widget:Extend`

两条路线不互斥，且推荐混用。桥是自定义控件——布局、命中、状态由组件负责，绘制下沉到 NanoVG：

```lua
local TechBar = UI.Widget:Extend("TechBar")

function TechBar:Init(props)
    props = props or {}
    props.height = props.height or 8
    UI.Widget.Init(self, props)
end

function TechBar:Render(nvg)
    local l = self:GetAbsoluteLayout()   -- 组件已算好的绝对坐标
    -- 在 l.x, l.y, l.w, l.h 内用 raw NanoVG 自由绘制
end
```

`GetAbsoluteLayout()` 让设计 DNA 第 8 条自动成立：绘制坐标就是命中坐标，高 DPI / letterbox 下不会点空。这是混用相对纯自绘的最大好处。完整范式（含背景、边框、状态色、动画）见 [`references/ui-bridge.md`](references/ui-bridge.md)。

## 设计 DNA

1. **深海军底，不是纯黑。** 大面积用 `bg` / `panel`。纯黑只允许极小的槽、进度轨。
2. **用相邻深蓝分层，不用厚阴影。** `panel` < `rail` < `card` < `widget`（越往上越亮）。
3. **酸青是唯一主强调色。** `cyan` 只表示焦点、激活、主操作、进度。标题、边框、图标默认不要全青。
4. **小圆角、细描边。** 窗口 4–8 px，控件 3–6 px。不要药丸，不要直角像素块。
5. **像素感字体，中文必须可读。** 项目当前用 `NotoSansSC-Black`；有 zpix 更贴风格，但要重调字号层级。
6. **花纹是识别度，不是壁纸。** 每窗 2–3 种：角标、断线边框、标题左竖线、局部网格、边刻度、弱扫描带。
7. **花纹贴边，文字背后干净。** 装饰透明度低于 `dim` 文字。
8. **同一套几何既绘制也点按。** 视觉框和 Hit 框必须同源，否则高 DPI / letterbox 会点空。走组件路线时由 `GetAbsoluteLayout()` 保证；纯自绘时自己保证。
9. **界面要「死气沉沉地活着」。** 完全静止的画面像截图。用**一个** 0..1 的氛围标量驱动全屏：基线不为 0，高位阈值上逐层解锁残影、强调色切换、文本异变。整屏共享同一个值，元素才会同步「发作」。细则见 [`references/atmosphere.md`](references/atmosphere.md)。

## 工作流

1. **选路线**（见上）。标准控件走 A；组件画不出的图形走 B，或按混用范式下沉绘制。
2. **定分辨率模式**。有明确设计稿（游戏 HUD 常见 360×720）→ 模式 A；未给设计稿的编辑器 / 工具 → 模式 B。细则读 `nvg-resolution-mode`；组件路线由 `UI.Init` 的 `scale` 统一处理。
3. **复用令牌**，不要为「差不多青」再造颜色。核心色板见下，完整表见 [`references/tokens.md`](references/tokens.md)。
3.5. **界面元素先分类**：能用「函数 + 数字」画出来的（面板、边框、进度、花纹）→ 程序化；只有具体的物/艺术字才做像素素材，走 [`references/pipeline.md`](references/pipeline.md)（生成 → 量化到项目色板 → `.meta` → `ICON_PATHS` → NEAREST 装载）。
4. **先画窗口骨架**（标题栏 / 内容区 / 底栏），再填调用方内容。
5. **装饰只加在边缘、角落、空白区**，不进入正文。
6. **需要「活着」的气质时，叠氛围层**：一个氛围标量 + 非等距阈值分带。先让界面安静成立，再加扰动；别一上来就满屏抽搐。见 [`references/atmosphere.md`](references/atmosphere.md)。
7. **对照文末清单验收。**

## 色彩令牌

RGBA 8-bit。新页面优先复用，不要为「差不多青」再开一色。

| Token | RGBA | 用途 |
| --- | --- | --- |
| `bg` | `7, 11, 20, 236` | 全屏底、窗口外层 |
| `panel` | `10, 16, 28, 248` | 窗口外壳 |
| `rail` | `12, 20, 34, 255` | 内容区、侧栏、工作区 |
| `card` | `16, 26, 44, 255` | 卡片、未激活控件、选中行底 |
| `widget` | `22, 36, 56, 255` | 输入框、滑轨、次级容器 |
| `cyan` | `0, 229, 208, 255` | 激活、主操作、进度、焦点 |
| `cyanDim` | `0, 150, 148, 220` | 弱描边、分隔、滚动 thumb |
| `ink` | `4, 8, 16, 255` | 青底上的字 |
| `text` | `240, 248, 252, 255` | 主文字 |
| `dim` | `120, 148, 162, 255` | 次文字、提示、禁用 |
| `warn` | `255, 196, 72, 255` | 警告、注意 |

**取用方式**：自绘路线用本地 `C.cyan`；组件路线用 `UI.Theme.Color("primary")`——两者指向同一个值，映射见 [`references/ui-bridge.md`](references/ui-bridge.md)。

规则：

- 青底配 `ink`；深底正文用 `text`，说明用 `dim`。
- 红色只表示明确错误，不要拿红当「未选中」。
- 可选注释层 `blue` / `gold` / `klein` / `ghost` 透明度通常 40–150，不能压过正文。完整表见 [`references/tokens.md`](references/tokens.md)。
- 语义色（HP / MP / Armor / Gold / XP / 稀有度）在 [`references/tokens.md`](references/tokens.md)，不要就地取近似色。

## 字体与字号

字体只在初始化时创建一次，每帧创建会漏显存。

组件路线：在主题里声明，不要手动 `nvgCreateFont`——组件会按 `weight` 自己取 face：

```lua
-- UI.Init 的 theme 里
fonts = {
    { family = "sans", weights = {
        normal = "Fonts/NotoSansSC-Black.ttf",
        bold   = "Fonts/NotoSansSC-Black.ttf",
    } },
},
```

自绘路线：`Start()` 里创建一次，之后每帧只 `nvgFontFace`：

```lua
-- 资源路径从 ResourceCache 根算，不要加 assets/
fontMain = nvgCreateFont(vg, "sans", "Fonts/NotoSansSC-Black.ttf")
```

项目 `assets/Fonts/` 现有 `NotoSansSC-Black.ttf`。想更硬的像素感可换 zpix，换字体后字号层级需要重调。

| 角色 | 字号 | 颜色 |
| --- | --- | --- |
| 窗口主标题 | 15–17 | `cyan` 或 `text` |
| 区域标题 | 11–13 | `cyan` |
| 正文 | 11–12 | `text` |
| 按钮 / 标签 | 9–11 | 随状态 |
| 辅助、单位、时间 | 9–10 | `dim` |
| 编辑中的数值 | 10–12 | `cyan` |

字号单位按路线不同：自绘直接给 NanoVG 像素值；组件路线的 `fontSize` 是 pt，设计稿 px → pt 用 `pt = px * 0.75`（18px = 13.5pt）。`UI.Theme.FontSize(pt)` 负责换算。

用 `nvgTextBounds` / `nvgTextBox` 量真实宽度，不要「字数 × 固定宽」。长标题放裁剪区并截断。窗口里不放长段落。

## 窗口骨架

```text
┌────────────────────────────────────────────┐
│  标题 / 短状态                       窗口操作 │  标题栏 46–56
├────────────────────────────────────────────┤
│  （可选侧栏 24%–34%）     主工作区（裁剪）   │  内容
├────────────────────────────────────────────┤
│  辅助状态                         主操作按钮 │  底栏 38–44
└────────────────────────────────────────────┘
```

尺寸：外边距 8–12；内容内边距 10–14；侧栏与内容间距 8–12；卡片间距 6–10。边框约 1 px。

高度不够时：先减装饰和间距，再缩小字，最后才挤内容。保留顺序：主标题 → 主内容 → 主操作 → 辅助说明。

标题栏左侧标题，必要时跟一个短状态；右侧放关闭 / 折叠等窗口级小按钮。左侧可有 3–4 px `cyan` 竖线作识别。标题栏不放多行说明。

层级最多四层：窗口、区域、控件、文字。需要强调的当前区用青细线或青标题，不要加发光。

两条路线的搭法：组件路线用 `UI.Panel` + `flexDirection`，见 [`references/ui-bridge.md`](references/ui-bridge.md) 的骨架片段；自绘路线用 `DrawWindow`，见 [`references/nanovg.md`](references/nanovg.md)。

## 控件外观

**胶囊 Chip（高 20–24，半径 ≤ 11，不是 9999）**

- 选中：`cyan` 底 + `ink` 字。
- 普通：`card` 底 + `cyanDim` 描边 + `text` 字。
- 宽度按文本实测；小窗可换行，但命中区不能小到点不到。

**按钮**

- 主：`cyan` 底 + `ink` 字。
- 次：`card` / `widget` 底 + `text` + `cyanDim` 描边。
- 禁用：低对比底 + `dim` 字。
- 危险：仅破坏性操作才用警示色。
- 命中区略大于可见边，但不得侵入相邻按钮。

**输入 / 滑轨**

- 输入底 `ink` 或 `widget`，圆角 3–5。聚焦只加 `cyan` 描边，不改整个窗口。
- 轨道 `widget`，进度 `cyan`，未激活 `cyanDim`。轨高 8–12，拖动命中可扩到 18–22。

**列表 / 属性行**

- 行高 30–38。当前行：`card` 底 + 约 3 px `cyan` 左标记。
- 主标题 11–12，辅助 9–10 `dim`。标签列、数值列对齐。空状态用短、低对比说明，不用大图。

**滚动条**

- 轨 `widget`，thumb `cyanDim`，thumb 最小高 36–44。贴内容裁剪区边缘，独立命中。内容滚动和参数滚动分开。

两条路线的落地写法：

- 组件路线——用内置控件 + 主题默认值调优（`UI.Button { variant = "primary" }`、`UI.Chip`、`UI.ScrollView`），组件默认值见 [`references/ui-bridge.md`](references/ui-bridge.md) 的 `components` 配置。
- 自绘路线——上面每条规格都有对应绘制函数，见 [`references/nanovg.md`](references/nanovg.md)。

## 状态

| 状态 | 外观 |
| --- | --- |
| 默认 | `card` 底、`text` 字 |
| 可点未选 | 弱描边、`text` / `dim` |
| 悬停 / 聚焦 | `widget` 底或 `cyanDim` 描边 |
| 当前选中 | 青底深字，或青色左标记 |
| 编辑中 | `cyan` 数值 + 青描边 |
| 禁用 | `dim` 字、低对比底 |
| 警告 | 小范围 `warn` |
| 错误 | 红色仅用于明确错误 |

不要只靠颜色区分状态；选中 / 聚焦 / 禁用至少再叠加底色、描边、左标记或亮度。

组件路线不要逐控件手写这套状态——把状态色写进主题（`primaryHover` / `borderFocus` / `disabled` 等），组件自己会切；只有自绘控件才需要在 `:Render` 里按当前状态取色。

## 分辨率、输入、引擎约束

`graphics:SetMode()` 无效。用 `graphics:GetWidth()` / `GetHeight()` / `GetDPR()`。

- 明确设计分辨率（游戏 HUD 常见 360×720）→ **模式 A**：`nvgBeginFrame(vg, logicalW, logicalH, dpr)`，再 `nvgScale` 到设计空间，输入先除 DPR 再减 letterbox 偏移。
- 未给设计稿的编辑器 / 工具 → **模式 B**：逻辑分辨率 + 响应式。
- 模式 C（物理像素）不推荐。

完整三种模式见 skill `nvg-resolution-mode`。组件路线由 `UI.Init { scale = UI.Scale.DEFAULT }` 统一处理，不要另设。

其它硬约束：

- 矢量绘制挂 `NanoVGRender`，不要挂在 `Update` 里画。
- 字体只在初始化创建。
- 鼠标判断用 `MOUSEB_LEFT` 等枚举，不要写 `0`。
- 触摸命中建议 ≥ 24×24；桌面小控件也不要 < 20×20。
- 窄屏优先：减左右留白 → 缩侧栏 → Chip 换行 → 折次要区。720 宽仍应认出标题、主内容、一组主操作。
- 原生 `UIElement` 已废弃，两条路线都不要用。

## 禁止

- 把所有字、图标、边框染成青。
- 大面积纯黑 / 纯白 / 高饱和多色渐变。
- 厚阴影、发光描边、玻璃拟态、药丸大圆角。
- 全屏等密度网格；花纹穿过标题、按钮、输入、正文。
- 用固定字数代替文本测量。
- 标题、内容、按钮互相覆盖。
- 视觉坐标和点击坐标两套数。
- 组件能做的事自己重画一遍（滚动、虚拟列表、拖拽、手势优先用 `urhox-libs/UI`）。
- 凭记忆猜 UrhoX / NanoVG API。

## 验收

- [ ] 深色底上有清楚但克制的边界
- [ ] 标题栏 / 内容 / 底栏分层明确
- [ ] 青色只出现在有意义的当前状态
- [ ] 主字 / 次字 / 禁用字可分
- [ ] 复用了角标、竖线、网格、刻度或扫描带之一组
- [ ] 装饰不挡字和控件
- [ ] 中文可读，数字不挤
- [ ] 小屏无互相覆盖
- [ ] 长文本经测量并裁切
- [ ] 内容区 scissor，溢出不污染窗外
- [ ] 绘制与命中同一套布局
- [ ] 走组件路线时主题经 `ExtendTheme` 注入，没有逐控件手写颜色 / 圆角
- [ ] `NanoVGRender`、字体一次创建、分辨率模式符合项目约定
- [ ] （有氛围层时）全屏共享一个氛围标量，基线不为 0，阈值非等距
- [ ] （有氛围层时）高阈值切换强调色，且每帧视觉不用 `math.random`
- [ ] （双色板时）两套色板 key 一致，颜色在函数体内现取而非模块级局部变量
- [ ] 界面元素已分类：几何走程序化，只有具体的物/艺术字做成像素素材
- [ ] 像素素材 ≤9 色、外轮廓统一、`.meta` uuid 唯一、加载用最近邻、显示为整数倍
- [ ] `ICON_PATHS` 每个 key 都有绘制点（无死键），缺图回退程序化而非崩 Init

## 参考

- 组件路线（主题映射 + 自定义控件）：[`references/ui-bridge.md`](references/ui-bridge.md)
- 自绘路线（绘制原语 + 窗口壳 + 装饰花纹 + 控件代码）：[`references/nanovg.md`](references/nanovg.md)
- **本项目 NanoVG 绘制元素库（培养舱分层 / 装饰母题参数 / 复合构件规格 / 图像与文字处理）：[`references/elements.md`](references/elements.md)**
- **界面素材生成与落地（图标/字标规格 · 项目色板量化 · `.meta` uuid · NEAREST 装载 · 死键检查）：[`references/pipeline.md`](references/pipeline.md)**
- **氛围层（氛围标量 + 阈值分带 + 残影 + 文本异变 + 音频联动）：[`references/atmosphere.md`](references/atmosphere.md)**
- 完整令牌表（色板 / 氛围色板 / 结构渐变 / 语义色 / 字号 / 圆角）：[`references/tokens.md`](references/tokens.md)
- NanoVG / 事件 / 字体：`engine-docs/lua-scripting-guide.md`
- 分辨率模式：skill `nvg-resolution-mode`
- 标准 UI 组件 API：`engine-docs/recipes/ui.md`、`examples/14-ui-widgets-gallery.lua`
- 装饰花纹 + 自定义控件（节点画布方向）：skill `node-mode-ingame-editor`
