local UI = require("urhox-libs/UI")
local Theme = require("defense.Theme")
local Art = require("defense.UIArt")
local Radar = require("defense.Radar")
local Economy = require("defense.Economy")
local Progression = require("defense.Progression")
local LegacyFX = require("defense.FX")
local Feedback = require("defense.Feedback")
local Proto = require("defense.ProtoView")
local C = Theme.C
local View = {}
View.__index = View

local STATE_NAMES = { DEPLOY = "部署", PREPARATION = "战备探索", WARNING = "入口预警", ATTACK = "守核交战",
    UPGRADE_CHOICE = "选择成长", WAVE_SETTLEMENT = "清波结算", END_SETTLEMENT = "本局结算" }
local GROUP_COLORS = { single = C.error, area = C.pink, control = C.blue, survival = C.green, mobility = C.purple, defense = C.cyan }
local function fmt(n) return tostring(math.floor(n or 0)) end
local function label(text, color, size)
    return UI.Label { text = text or "", fontColor = color or C.text, fontFamily = "pixel", fontSize = Theme.TextSize(size or 12),
        width = "100%", flexShrink = 1, whiteSpace = "normal", maxLines = 12, lineHeight = 1.35 }
end
local function row(children, gap)
    return UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", gap = gap or 8,
        pointerEvents = "box-none", children = children or {} }
end
local function card(children)
    return Art.Frame({ width = "100%", padding = 12, gap = 8,
        backgroundColor = C.card, children = children or {} })
end
local function destroyChildren(parent)
    for i = parent:GetNumChildren(), 1, -1 do
        local child = parent:GetChildAt(i)
        if child then child:Destroy() end
    end
end
local function paused(run) return next(run.pause_reasons or {}) ~= nil end

---@class DefenseView
---@field selectedPolygonDifficulty number?
---@field run table
---@field callbacks table
---@field root Panel
---@field top Panel
---@field bottom Panel
---@field overlay Panel
---@field radar DefenseRadar
---@field radarPanel Panel
---@field labels table<string, Label>
---@field bars table<string, ProgressBar>
---@field buttons table<string, Button>
---@field modalLabels table<string, Label>
---@field menuButtons table<string, Button>
---@field transactionButtons table[]
---@field transactionLabels table[]
---@field overlayContent Panel?
function View.New(run, callbacks)
    local self = setmetatable({}, View)
    self:init(run, callbacks or {})
    return self
end
function View:init(run, callbacks)
    self.run, self.callbacks = run, callbacks
    self.labels, self.bars, self.buttons, self.modalLabels, self.menuButtons = {}, {}, {}, {}, {}
    self.transactionButtons, self.transactionLabels = {}, {}
    self.menuOpen, self.replayPreview, self.destroyed = true, false, false
    self.selectedBuild, self.modeKey, self.layoutKey = run.build or "single", "__dirty", ""
    self.selectedScenario, self.protoSlots = Proto.Scenario(run), {}
    self.selectedPolygonDifficulty = run.config.difficulty or 1
    self.elapsed, self.updateRemaining, self.dirty = 0, 0, true
    self.atmosphere = Theme.Atmosphere(0)
    self.topHeight = -1
    local settings = run.meta.settings or {}
    self.volume, self.reducedEffects, self.hintsEnabled = settings.volume or 1, settings.reduced_effects == true, settings.hints ~= false
    self.stageNotice, self.stageNoticeRemaining = "", 0
    self.reportExpanded = false
    self.latestNotice, self.noticeRemaining = "", 0
    self:BuildRoot()
    self:Update(0)
    print("[DefenseView] 深海军像素界面已就绪")
end
function View:Action(kind, payload)
    if self.destroyed then return end
    if self.callbacks.action then self.callbacks.action(kind, payload) end
    self.dirty = true
end
function View:NewRun(total, retry, scenarioId)
    self.menuOpen = false
    if self.callbacks.newRun then
        self.callbacks.newRun(total, self.selectedBuild, retry == true, scenarioId or Proto.Scenario(self.run),
            { difficulty = self.selectedPolygonDifficulty or self.run.config.difficulty or 1 })
    end
    self.modeKey, self.dirty = "__dirty", true
end
function View:SetRun(run)
    self.run = run
    self.menuOpen = (run.pause_reasons or {}).menu == true
    self.selectedBuild = run.build or self.selectedBuild
    self.selectedScenario, self.protoSlots = Proto.Scenario(run), {}
    self.selectedReportIndex = nil --[[@as integer?]]
    self.radar:SetRun(run)
    self.replayPreview = false
    self.latestNotice, self.noticeRemaining = "", 0
    self.stageNotice, self.stageNoticeRemaining = "", 0
    self.modeKey, self.dirty = "__dirty", true
end
function View:Button(text, callback, variant)
    return UI.Button { text = text, variant = variant or "secondary", height = 46,
        fontFamily = "pixel", fontSize = Theme.TextSize(12),
        flexShrink = 1, minWidth = 70, onClick = callback }
end
function View:AddLabel(parent, id, text, color, size)
    local widget = label(text, color, size)
    self.labels[id] = widget
    parent:AddChild(widget)
    return widget
end
function View:Text(id, value)
    local widget = self.labels[id]
    if widget and widget.props.text ~= value then widget:SetText(value) end
end
function View:Visible(widget, visible)
    if widget.props.visible ~= visible then widget:SetVisible(visible) end
end
function View:Bar(id, value, maximum)
    local bar = self.bars[id]
    if bar.props.max ~= maximum then bar:SetMax(maximum) end
    if bar.props.value ~= value then bar:SetValue(value) end
end
function View:SetButton(id, text, disabled)
    local widget = self.buttons[id]
    if not widget then return end
    if widget.props.text ~= text then widget:SetText(text) end
    if widget.props.disabled ~= disabled then widget:SetDisabled(disabled) end
end
function View:HealthCard(id, title, color)
    local titleLabel = label(title, C.text, 12)
    titleLabel:SetStyle({ maxLines = 1 })
    local bar = Art.Gauge { width = "100%", height = 8, value = 1, max = 1,
        backgroundColor = C.ink, fillColor = color }
    self.labels[id], self.bars[id] = titleLabel, bar
    local content = UI.Panel { flexGrow = 1, flexShrink = 1, gap = 4, pointerEvents = "none",
        children = { titleLabel, bar } }
    local children = { content }
    if id == "coreHP" then table.insert(children, 1, Art.Icon { icon = "core" }) end
    return UI.Panel { flexGrow = 1, flexShrink = 1, flexBasis = 0, minWidth = id == "coreHP" and 196 or 132,
        flexDirection = "row", alignItems = "center", gap = 6, pointerEvents = "none", children = children }
end

function View:BuildRoot()
    local stats = UI.Label { text = "", fontFamily = "pixel", fontSize = Theme.TextSize(12), fontColor = C.text,
        flexGrow = 1, flexShrink = 1, flexBasis = 240, minWidth = 210, whiteSpace = "normal", maxLines = 2 }
    self.labels.stats = stats
    ---@type Widget[]
    local navigation = { stats }
    for _, item in ipairs({ { "map", "地图", "map" }, { "modules", "模块", "module_open" }, { "pause", "暂停", "pause" } }) do
        local id, caption, action = item[1], item[2], item[3]
        local button = self:Button(caption, function() self:Action(action) end)
        button:SetStyle({ minWidth = 62, height = 44, fontSize = Theme.TextSize(11) })
        self.buttons[id] = button
        navigation[#navigation + 1] = button
    end
    local status = UI.Label { text = "", width = "100%", fontFamily = "pixel", fontSize = Theme.TextSize(11),
        fontColor = C.dim, flexShrink = 1, whiteSpace = "normal", maxLines = 2 }
    self.labels.status = status
    local health = row({ self:HealthCard("playerHP", "角色", Theme.HP),
        self:HealthCard("coreHP", "核心", C.cyan) }, 12)
    health:SetStyle({ alignItems = "center" })
    self.top = Art.Frame({ width = "100%", padding = { 8, 12 }, gap = 6, pointerEvents = "box-none",
        backgroundColor = C.panel, children = { row(navigation, 6), health, status } }, self)
    self.bars.experience = Art.Gauge { width = "100%", height = 4, value = 0, max = 20,
        fillColor = Theme.XP, backgroundColor = C.ink }
    self.top:AddChild(self.bars.experience)
    self.bars.phase = Art.Gauge { width = "100%", height = 4, value = 0, max = 1,
        fillColor = C.warn, backgroundColor = C.ink }
    self.top:AddChild(self.bars.phase)

    self.alerts = UI.Panel { position = "absolute", top = 100, left = 12, right = 12,
        gap = 4, pointerEvents = "none" }
    for _, item in ipairs({ { "coreAlarm", C.error, 13 }, { "returnWarning", C.warn, 11 },
        { "expedition", C.warn, 11 }, { "causalNotice", C.text, 11 } }) do
        self:AddLabel(self.alerts, item[1], "", item[2], item[3]):SetStyle({ textAlign = "center", maxLines = 1,
            visible = false, textStroke = { width = 1, color = C.ink } })
    end
    self.radar = Radar { run = self.run, width = "100%", height = 84, pointerEvents = "none",
        backgroundColor = C.rail }
    self.radarPanel = Art.Frame({ position = "absolute", top = 160, right = 12, width = 116,
        padding = 4, backgroundColor = C.panel, pointerEvents = "none", children = { self.radar } }, self)
    self.bottom = UI.Panel { position = "absolute", left = 12, right = 12, bottom = 12,
        gap = 6, pointerEvents = "box-none" }
    local actions = row()
    actions:SetStyle({ justifyContent = "flex-end" })
    for _, item in ipairs({ { "wave", "开波", "wave" }, { "logistics", "后勤", "logistics" },
        { "claim", "领取", "claim" }, { "recall", "回城", "recall" }, { "active", "击退", "active" } }) do
        local id, caption, kind = item[1], item[2], item[3]
        local button = self:Button(caption, function()
            if kind == "claim" then self:Action("claim", self.run.map:RoomAt(self.run.player.x, self.run.player.y))
            else self:Action(kind) end
        end, id == "active" and "primary" or "secondary")
        button:SetStyle({ minWidth = id == "active" and 106 or 70,
            height = id == "active" and 48 or 44, fontSize = Theme.TextSize(11) })
        self.buttons[id] = button
        actions:AddChild(button)
    end
    self.bottom:AddChild(actions)
    self.overlay = UI.Panel { position = "absolute", top = 0, bottom = 0, left = 0, right = 0,
        zIndex = 100, backgroundColor = C.bg,
        alignItems = "center", justifyContent = "center", padding = 12, visible = false, pointerEvents = "auto" }
    local content = UI.Panel { width = "100%", height = "100%", pointerEvents = "box-none",
        children = { self.top, self.alerts, self.radarPanel, self.bottom, self.overlay } }
    self.root = UI.Panel { width = "100%", height = "100%", pointerEvents = "box-none",
        children = { UI.SafeAreaView { width = "100%", height = "100%", nativeMenuInset = true,
            pointerEvents = "box-none", children = { content } } } }
    UI.SetRoot(self.root, true)
end

function View:Mode()
    local run, reasons = self.run, self.run.pause_reasons or {}
    if reasons.technical or run.result == "UNDETERMINED" or run.result == "undetermined" then
        if self.menuOpen and reasons.menu then return "menu" end
        return "technical"
    end
    if reasons.focus and (not self.menuOpen or self.replayPreview) then return "pause" end
    if reasons.rules then return "rules" end
    if reasons.recap then return "recap" end
    if self.replayPreview and run.story.replay and run.story.node ~= "" then
        if reasons.manual then return "pause" end
        return "story:" .. run.story.node
    end
    if self.menuOpen or reasons.menu then return "menu" end
    if reasons.manual and run.story.node ~= "" then return "pause" end
    if run.story.node ~= "" then return "story:" .. run.story.node end
    if run.ended then return "result" end
    -- 模块与地图不会改写 pause_reasons.upgrade/manual；关闭后显露原有面板。
    if reasons.module_choice then return Proto.ModuleKey(run) end
    if reasons.map then return "map" end
    if reasons.upgrade then
        local key = "upgrade:" .. fmt(run.player.level)
        for _, option in ipairs(run.options) do key = key .. ":" .. option.id end
        return key
    end
    if reasons.manual or reasons.focus then return "pause" end
    if reasons.logistics then return "logistics" end
    return ""
end
function View:ModalShell(title, subtitle)
    local width, height = UI.GetViewportSize()
    local compact = width < 660 or height < 600
    local panel = Art.Frame({ width = "100%", maxWidth = 720,
        height = compact and "100%" or "92%", padding = compact and 12 or 20, gap = 10,
        backgroundColor = C.panel, overflow = "hidden" }, self)
    local heading = label(title, C.text, 20)
    heading:SetStyle({ textAlign = "left", maxLines = 1 })
    panel:AddChild(UI.Panel { width = "100%", flexDirection = "row", gap = 8, alignItems = "center",
        children = { UI.Panel { width = 3, height = 24, backgroundColor = C.cyan, pointerEvents = "none" }, heading } })
    local scroll = UI.ScrollView { width = "100%", flexGrow = 1, flexBasis = 0, flexShrink = 1,
        gap = 10, scrollY = true, showScrollbar = true }
    if subtitle then
        local description = label(subtitle, C.dim, 11)
        description:SetStyle({ maxLines = 8 })
        scroll:AddChild(description)
    end
    panel:AddChild(scroll)
    self.overlay:AddChild(panel)
    self.overlayContent = panel
    if not self.reducedEffects then
        panel:Animate({ keyframes = { [0] = { opacity = 0 }, [1] = { opacity = 1 } },
            duration = 0.2, easing = "easeOut", fillMode = "forwards" })
    end
    return scroll, panel
end
function View:ReplayButtons(parent)
    for _, node in ipairs({ "opening", "final_intro", "ending" }) do
        local captions = { opening = "回看开场", final_intro = "回看终局", ending = "回看收束" }
        local button = self:Button(captions[node], function()
            self.replayPreview = true
            self:Action("replay", node)
        end)
        button:SetDisabled(not Proto.StorySeen(self.run, node) or self.run.pause_reasons.logistics == true
            or self.run.pause_reasons.upgrade == true or self.run.pause_reasons.rules == true or self.run.pause_reasons.recap == true
            or self.run.pause_reasons.module_choice == true or self.run.pause_reasons.map == true or self.run.pause_reasons.technical == true)
        parent:AddChild(button)
    end
end
function View:BuildMenu()
    local scroll, panel = self:ModalShell("固定据点防守", "守住核心，探索补给，建立你的防线。")
    scroll:AddChild(label("选择战斗风格", C.text, 13))
    self.menuButtons = {}
    local choices = row()
    for _, build in ipairs(self.run.config.builds) do
        local id = build.id
        local button = self:Button((id == self.selectedBuild and "已选 · " or "") .. build.name, function()
            self.selectedBuild = id
            self.modeKey, self.dirty = "__dirty", true
        end, id == self.selectedBuild and "success" or "secondary")
        button:SetStyle({ flexGrow = 1, flexBasis = 170, minWidth = 170, width = "auto" })
        self.menuButtons[id] = button
        choices:AddChild(button)
    end
    scroll:AddChild(choices)
    for _, build in ipairs(self.run.config.builds) do
        if build.id == self.selectedBuild then scroll:AddChild(label(build.description, C.dim, 11)) end
    end
    Proto.BuildScenarioMenu(self, scroll)
    panel:AddChild(row({ self:Button("玩法", function() self:Action("rules") end),
        self:Button("战报", function() self:Action("recap") end) }))
end
function View:TransactionButton(action, slot, towerType, caption)
    local button = self:Button(caption, function()
        local ok, reason = Economy.Check(self.run, action, slot, towerType)
        if not ok then
            self.latestNotice, self.noticeRemaining, self.dirty = reason or "交易权限已变化", 3, true
            return
        end
        self:Action("transaction", { action = action, slot = slot, type = towerType })
    end, action == "demolish" and "danger" or "secondary")
    button:SetStyle({ width = "100%", height = 44, fontSize = Theme.TextSize(11) })
    local reason = label("", C.dim, 9)
    self.transactionButtons[#self.transactionButtons + 1] = {
        button = button, reason = reason, action = action, slot = slot, towerType = towerType, caption = caption }
    return UI.Panel { width = "100%", gap = 3, children = { button, reason } }
end
function View:BuildLogistics()
    Proto.BuildLogistics(self)
end
function View:RefreshLogistics()
    Proto.RefreshLogistics(self)
end
function View:BuildUpgrade()
    local scroll = self:ModalShell("选择成长")
    local width = UI.GetViewportSize()
    local choices = row()
    for _, option in ipairs(self.run.options) do
        local id = option.id
        local color = GROUP_COLORS[option.group] or C.cyan
        local progression = option.max == 0 and "一次性补给" or
            "Lv." .. fmt(option.current) .. " → Lv." .. fmt(option.next)
        local choice = card({ label(option.name, color, 16), label(option.detail, C.text, 12),
            label(Progression.Preview(self.run, id), C.cyan, 11), label(progression, C.dim, 10),
            self:Button("选择", function() self:Action("upgrade", id) end, "success") })
        choice:SetStyle({ width = width >= 800 and "auto" or "100%", flexGrow = 1,
            flexBasis = width >= 800 and 0 or "auto", minWidth = 180 })
        choices:AddChild(choice)
    end
    scroll:AddChild(choices)
end
function View:BuildPause()
    local scroll, panel = self:ModalShell("已暂停")
    self.modalLabels.pause = label("", C.text, 13); scroll:AddChild(self.modalLabels.pause)
    Proto.OpenButtons(self, scroll)
    scroll:AddChild(row({ self:Button("玩法", function() self:Action("rules") end),
        self:Button("战报", function() self:Action("recap") end) }))
    local settings = UI.Panel { width = "100%", gap = 10, visible = false, children = {
        label("音量", C.dim, 11), UI.Slider { min = 0, max = 100, step = 5, value = self.volume * 100, width = "100%",
            onChange = function(_, v) self.volume = v / 100; self:Action("volume", self.volume) end },
        UI.Checkbox { label = "减少粒子与震动", checked = self.reducedEffects,
            onChange = function(_, checked) self.reducedEffects = checked; self:Action("reduced_effects", checked) end },
        UI.Checkbox { label = "新手提示", checked = self.hintsEnabled,
            onChange = function(_, checked) self.hintsEnabled = checked; self:Action("hints", checked) end },
    } }
    scroll:AddChild(self:Button("设置", function() settings:SetVisible(not settings.props.visible) end))
    scroll:AddChild(settings)
    local replay = row(); self:ReplayButtons(replay); replay:SetVisible(false)
    scroll:AddChild(self:Button("章节回看", function() replay:SetVisible(not replay.props.visible) end))
    scroll:AddChild(replay)
    panel:AddChild(row({ self:Button("继续防守", function() self:Action("resume") end, "primary"),
        self:Button("重新部署", function() self.menuOpen = true; self:Action("menu") end) }))
end
function View:BuildRules()
    local scroll, panel = self:ModalShell("玩法", "自动攻击 · 移动躲避 · 守住核心")
    if self.run.config.polygon_expansion then
        scroll:AddChild(label("主空间三路守核，战备期探索三片群系。进入房间后锁门，清空全部守军波次才可离开；守核时钟继续，角色或核心归零即全局失败。", C.cyan, 12))
        scroll:AddChild(label("三角房三波小怪；六边房两波不同小Boss，首清激活传送锚点；地区十二边房为超级Boss。首清奖励只领取一次，星砂累计收入上限120。", C.text, 12))
        scroll:AddChild(label("F就地布防，仅可操作当前已清房间的槽位，主空间可直接布防。M打开大地图并暂停；已激活锚点可传送，跨群系经主空间，20秒冷却。预警、进攻和房间战斗中不可传送。", C.text, 12))
        scroll:AddChild(label("W20后有已清探索房间则进入三队考验，房间核心伤害预算仍为100；未探索时直接结算。小地图显示当前房，大地图显示全域。", C.warn, 12))
    elseif self.run.config.sanctuary_expansion then
        scroll:AddChild(label("神殿扩展：基础战备15秒；速清奖励最多15秒，本波用完即失效。提前开波和自然开波都有独立8秒预警。", C.cyan, 12))
        scroll:AddChild(label("森林补资金，冰川补模块，火山补星砂。房间只领奖一次；星砂累计收入上限120，高级支援和不可逆分支消耗星砂。", C.text, 12))
        scroll:AddChild(label("四类八种设施共用12个存活名额；两次升级后封顶。完好拆除返50%基础与升级资金，损坏不返，星砂不返。", C.text, 12))
        scroll:AddChild(label("W20完成后，已清房间参与考验，未清房不出怪；三支远征队可在巡行中击杀，每来源房共享100核心损失预算。总时限从入场起计算，暂停冻结；超时失败。", C.warn, 12))
    end
    scroll:AddChild(label(self.run.config.polygon_expansion and
        "WASD / 方向键移动，空格击退；F 布防，R 返回主空间，M 地图，Enter 提前开波。触屏使用摇杆与按钮。" or
        "WASD / 方向键移动，空格击退；F 后勤，R 回城，M 地图，Enter 提前开波。触屏使用摇杆与按钮。", C.dim, 12))
    for _, item in ipairs({
        { "🌀 站位决定击退方向", "最近合法目标会出现轮廓。击退无伤害，射程4.5格、冷却8秒；碰到墙柱会停止。" },
        { "💣 在哪死亡，就在哪爆炸", "爆炸推进怪死亡0.7秒后结算；范围2.5格、伤害40。危险圈锁定死亡点，期间可以换位。" },
        { "🛡️ 核心也会受爆炸伤害", "普通攻击没有友伤，爆炸却可伤害双方、核心与塔。核心和塔固定，不能推动。" },
        { "❄️ 控制创造机会，不保证安全", "减速取最强，最多50%；离开范围后状态仍有期限。范围火力适合密集队列，但三路同时增压时仍需回防。" },
        { "🪙 每一次支出都有代价", "120资金不足以同时买90的减速塔和40的修复。外圈奖励只领取一次，低耐久或下一波逼近时可以放弃探索。" },
    }) do scroll:AddChild(card({ label(item[1], C.cyan, 14), label(item[2], C.text, 12) }, C.purple)) end
    panel:AddChild(self:Button("返回", function() self:Action("close_rules") end, "primary"))
end
function View:BuildStory()
    local run = self.run
    local names = { opening = "守住最后的光", final_intro = "终局警报", ending = "防线仍在" }
    local scroll, panel = self:ModalShell(names[run.story.node] or "章节演出", "核心固定，防线由你守护。可随时跳过。")
    local visual = UI.Panel { width = "100%", aspectRatio = 16 / 9, maxHeight = 260,
        overflow = "hidden", pointerEvents = "none",
        backgroundImage = run.story.node == "final_intro" and "image/defense_story_sanctuary_20261006140946.png"
            or "image/defense_story_finale_20261006140927.png", backgroundFit = "cover",
        children = { UI.Panel { position = "absolute", left = "12%", bottom = 0, width = "26%", height = "85%",
            backgroundImage = "image/char_cat_luckystar2_20260526082253.png", backgroundFit = "contain",
            pointerEvents = "none" } } }
    if not self.reducedEffects then
        visual:Animate({ keyframes = { [0] = { scale = 1, opacity = 0.7 }, [1] = { scale = 1.03, opacity = 1 } },
            duration = 4, loop = true, direction = "alternate" })
    end
    scroll:AddChild(visual)
    local lines = {
        opening = { "三条通道通向同一个核心。", "外圈藏着补给，离开也意味着防线承压。", "看清危险的位置，再决定下一步。" },
        final_intro = { Proto.Scenario(run) == "legacy_v02" and "南路警报已锁定终局统领。" or Proto.RouteText(run),
            "挡住进攻，守住核心。" },
        ending = { "最后一处危险已经消散。", Proto.ResultNote(run, true) },
    }
    for _, s in ipairs(lines[run.story.node] or {}) do scroll:AddChild(label(s, C.text, 14)) end
    self.modalLabels.story = label("", C.dim, 11); scroll:AddChild(self.modalLabels.story)
    panel:AddChild(self:Button("跳过 / 继续", function() self:Action("skip_story") end, "primary"))
end
local function summaryText(s) return Feedback.Describe(s) end
function View:AddReport(parent, report)
    if not report or not report.chains or #report.chains == 0 then
        parent:AddChild(label("暂无战斗片段。", C.dim, 11))
        return
    end
    for _, summary in ipairs(report.chains) do
        local detail = UI.Panel { width = "100%", gap = 4, visible = false }
        local toggle = self:Button("详情", function(button)
            local visible = not detail.props.visible
            if visible and detail:GetNumChildren() == 0 then
                detail:AddChild(label("第" .. fmt(summary.wave or report.wave or 1) .. "波 · " ..
                    string.format("%.1f秒", summary.time or 0) .. " · " .. Feedback.SourceName(summary.source), C.dim, 10))
                for _, fact in ipairs(summary.facts or {}) do detail:AddChild(label(fact, C.dim, 10)) end
            end
            detail:SetVisible(visible)
            button:SetText(visible and "收起" or "详情")
        end)
        toggle:SetStyle({ height = 44, fontSize = Theme.TextSize(11), minWidth = 70 })
        parent:AddChild(card({ label(summaryText(summary), C.text, 12), toggle, detail }))
    end
end
function View:AddEconomy(parent, report)
    local names = { build = "建造", upgrade = "升级", repair = "修复", heal = "治疗", demolish = "拆除", module = "模块服务" }
    for _, fact in ipairs(report.economy or {}) do
        local text = "第" .. fact.wave .. "波 " .. (names[fact.action] or fact.action) ..
            (fact.slot and " " .. fact.slot or "") .. " · 支出 " .. fact.spend .. " · 返还 " .. fact.refund
        if fact.repair > 0 then text = text .. " · 实际修复 " .. fact.repair end
        if fact.heal > 0 then text = text .. " · 实际治疗 " .. fact.heal end
        parent:AddChild(label(text, C.dim, 10))
    end
end
function View:BuildRecap()
    local scroll, panel = self:ModalShell("战报")
    local reports = {}
    for _, report in ipairs(self.run.stage_reports or {}) do reports[#reports + 1] = report end
    local last = Proto.LastReport(self.run)
    if last then reports[#reports + 1] = last end
    if #reports == 0 then
        scroll:AddChild(label("暂无战报，完成阶段后会自动记录。", C.dim, 12))
    else
        local selected = math.min(self.selectedReportIndex or #reports, #reports)
        local tabs = row()
        for index, report in ipairs(reports) do
            local caption = index == #reports and last and "上局" or "第" .. fmt(report.wave) .. "波"
            tabs:AddChild(self:Button(caption, function()
                self.selectedReportIndex = index
                self.modeKey, self.dirty = "__dirty", true
            end, selected == index and "success" or "secondary"))
        end
        if #reports > 1 then scroll:AddChild(tabs) end
        local report = reports[selected]
        scroll:AddChild(label("第" .. fmt(report.wave) .. "波 · " .. (report.result == "victory" and "防守完成" or "战斗记录"), C.cyan, 14))
        Proto.AddReport(scroll, report)
        self:AddReport(scroll, report)
        local economy = UI.Panel { width = "100%", gap = 5, visible = false }
        scroll:AddChild(self:Button("收支明细", function()
            if economy:GetNumChildren() == 0 then self:AddEconomy(economy, report) end
            economy:SetVisible(not economy.props.visible)
        end))
        scroll:AddChild(economy)
    end
    panel:AddChild(self:Button("返回", function() self:Action("close_recap") end, "primary"))
end
function View:BuildResult()
    local run = self.run
    if (run.pause_reasons or {}).technical or run.result == "UNDETERMINED" or run.result == "undetermined" then
        Proto.BuildTechnical(self); return
    end
    local win = run.result == "victory"
    local scroll, panel = self:ModalShell(win and "防守完成" or "防线失守", run.end_reason)
    local totals = run.totals
    scroll:AddChild(card({ label("波次 " .. fmt(run.wave_id) .. "/" .. fmt(run.total_waves) .. " · 等级 " .. fmt(run.player.level), C.cyan, 16),
        label("击杀 " .. fmt(totals.kills) .. " · 资金 " .. fmt(run.currency) .. " · 用时 " .. fmt(run.clock) .. "秒", C.text, 12),
        label("核心 " .. fmt(run.core.hp) .. "/" .. fmt(run.core.max_hp) .. " · 角色 " .. fmt(run.player.hp) .. "/" .. fmt(run.player.max_hp), C.text, 12),
        label("角色输出 " .. fmt(totals.player_output) .. " · 设施输出 " .. fmt(totals.tower_output), C.dim, 11) }))
    local report = Proto.LastReport(run) or { chains = Feedback.Select(run, 1, run.wave_id), wave = run.wave_id, totals = run.totals,
        expedition = Proto.Expeditions(run) }
    Proto.AddReport(scroll, report)
    scroll:AddChild(label(Proto.ResultNote(run, win), C.dim, 11))
    scroll:AddChild(self:Button("查看战报", function() self:Action("recap") end))
    panel:AddChild(row({ self:Button("重试当前方案", function() self:NewRun(run.total_waves, true) end, "primary"),
        self:Button("重新部署", function() self.menuOpen = true; self:Action("menu") end) }))
end
function View:RefreshOverlay(key)
    if key == self.modeKey then return end
    Art.CancelInput(self.overlay)
    destroyChildren(self.overlay)
    self.transactionButtons, self.transactionLabels, self.modalLabels, self.protoSlots = {}, {}, {}, {}
    self.overlayContent = nil
    self.modeKey = key
    self.overlay:SetVisible(key ~= "")
    if key == "menu" then self:BuildMenu()
    elseif key == "pause" then self:BuildPause()
    elseif key == "rules" then self:BuildRules()
    elseif key == "logistics" then self:BuildLogistics()
    elseif key == "result" then self:BuildResult()
    elseif key == "recap" then self:BuildRecap()
    elseif key == "map" then Proto.BuildMap(self)
    elseif key == "technical" then Proto.BuildTechnical(self)
    elseif key:sub(1, 13) == "moduleChoice:" then Proto.BuildModules(self)
    elseif key:sub(1, 6) == "story:" then self:BuildStory()
    elseif key:sub(1, 8) == "upgrade:" then self:BuildUpgrade() end
end
function View:Events(events)
    local urgent = false
    for _, event in ipairs(events) do
        local kind = event.kind
        if kind ~= "Shoot" and kind ~= "Hit" and kind ~= "EnemyAttack" and kind ~= "EnemySlowed"
            and kind ~= "StatusChanged" and kind ~= "EnemySpawned" then urgent = true end
        local d = event.data
        if event.kind == "SlowClearHint" then
            self.latestNotice, self.noticeRemaining = d.text, 5
        elseif event.kind == "ExplorationCurrencyEarned" then
            self.latestNotice, self.noticeRemaining = "星砂 +" .. fmt(d.amount) .. " · 余额 " .. fmt(d.balance), 3
        elseif event.kind == "TrialPrepared" then
            self.latestNotice, self.noticeRemaining = "已清据点进入考验 · 三支远征队准备入场", 5
        elseif event.kind == "ActiveRejected" or event.kind == "DisplacementRejected" then
            self.latestNotice, self.noticeRemaining = d.reason or "目标无法推动", 2
        elseif event.kind == "RoomRewardClaimed" then
            self.latestNotice, self.noticeRemaining = "据点补给到账：+" .. fmt(d.gold) .. "资金", 2
        elseif event.kind == "ModuleOffered" then
            local caption = #(d.candidates or {}) > 0 and "获得新的模块选择" or
                d.waiting and "模块选择已保留" or "本局模块已收集齐"
            self.latestNotice, self.noticeRemaining = caption, 4
        elseif event.kind == "ModuleChoiceResolved" then
            self.latestNotice, self.noticeRemaining = d.ok and "模块已解锁" or (d.reason or "模块未选择"), 4
        elseif event.kind == "ModuleInstalled" or event.kind == "ModuleChanged" then
            self.latestNotice, self.noticeRemaining = "模块已安装", 3
        elseif event.kind == "ExpeditionPathError" or event.kind == "ChallengePathError" then
            self.latestNotice, self.noticeRemaining = "运行异常，防守已暂停", 6
        elseif event.kind == "StageReportReady" then
            self.stageNotice = "第" .. event.data.report.wave .. "波完成，战报已更新。"
            self.stageNoticeRemaining = 5
        elseif event.kind == "SaveFailed" then
            self.latestNotice, self.noticeRemaining = "记录保存失败，当前局仍可继续：" .. tostring(d.reason or ""), 6
        elseif event.kind == "TransactionResolved" then
            if not d.ok then self.latestNotice = d.reason or "操作未成功"
            elseif (d.actual_repair or 0) > 0 then self.latestNotice = "实际修复 +" .. fmt(d.actual_repair) .. "耐久"
            elseif (d.actual_heal or 0) > 0 then self.latestNotice = "实际治疗 +" .. fmt(d.actual_heal) .. "生命"
            elseif d.action == "demolish" then self.latestNotice = "拆除返还 " .. fmt(d.refund) .. "资金"
            else self.latestNotice = "操作完成 · 支出 " .. fmt(d.price) .. "资金" end
            self.noticeRemaining = 2
        end
    end
    if urgent then self.dirty = true end
end
function View:UpdateHUD()
    local run, p, core = self.run, self.run.player, self.run.core
    self:Text("playerHP", "角色 " .. fmt(p.hp) .. " / " .. fmt(p.max_hp))
    self:Text("coreHP", "核心 " .. fmt(core.hp) .. " / " .. fmt(core.max_hp))
    self:Bar("playerHP", p.hp, p.max_hp)
    self:Bar("coreHP", core.hp, core.max_hp)
    self:Bar("experience", p.experience, Progression.Threshold(p.level))
    self:Text("stats", "第" .. fmt(run.wave_id) .. "/" .. fmt(run.total_waves) .. "波 · 资金 " .. fmt(run.currency) ..
        (run.config.sanctuary_expansion and " · 星砂 " .. fmt(run.exploration_currency) or "") .. (self.hudNarrow and "" or " · Lv." .. fmt(p.level)))
    local timeText = run.state == "PREPARATION" and " " .. fmt(math.ceil(run.preparation_remaining)) .. "秒" or
        run.state == "WARNING" and " " .. fmt(math.ceil(math.max(0, run.config.warning_duration - run.warning_elapsed))) .. "秒" or ""
    local portals = table.concat(run.current_wave.active_portals, " / ")
    local pending = run.pending_harmful_reactions or 0
    local attacking = run.state == "ATTACK"
    if run.config.sanctuary_expansion then
        if run.state == "PREPARATION" then
            local bonusRemaining = math.max(0, run.preparation_remaining - run.config.preparation_duration)
            timeText = timeText .. " · " .. (bonusRemaining > 0 and "奖励探索 " .. fmt(math.ceil(bonusRemaining)) .. "秒" or "基础战备")
        elseif attacking then timeText = " · 战斗 " .. fmt(math.floor(run.attack_elapsed)) .. "/" .. fmt(run.attack_duration) .. "秒" end
    end
    self:Text("status", (STATE_NAMES[run.state] or run.state) .. timeText ..
        (attacking and " · 残敌 " .. fmt(run:AliveCount()) or "") .. (paused(run) and " · 暂停" or ""))
    local expedition = Proto.HUDText(run)
    self:Text("expedition", expedition)
    self:Visible(self.labels.expedition, expedition ~= "")
    self:Visible(self.bars.phase, run.state == "PREPARATION" or run.state == "WARNING")
    self:Bar("phase", run.state == "PREPARATION" and run.preparation_remaining or
        math.max(0, run.config.warning_duration - run.warning_elapsed),
        run.state == "PREPARATION" and run.preparation_total or run.config.warning_duration)
    local critical = core.hp < core.max_hp * 0.3
    local alert = LegacyFX.coreAlert or 0
    local portal = LegacyFX.corePortal or ""
    local pulseColor = self.reducedEffects and (alert > 0 or critical) and C.error or
        alert > 0 and (math.floor(self.elapsed * 6) % 2 == 0 and C.error or C.cyan) or critical and C.error or C.cyan
    if self.bars.coreHP.props.fillColor ~= pulseColor then self.bars.coreHP:SetStyle({ fillColor = pulseColor }) end
    local alarm = critical and "核心耐久低于30%！立即回防" or alert > 0 and "核心正在受击！" or ""
    if alarm ~= "" and portal ~= "" then alarm = alarm .. "  " .. portal .. "路" end
    self:Text("coreAlarm", alarm); self:Visible(self.labels.coreAlarm, alarm ~= "")
    local opacity = not self.reducedEffects and alarm ~= "" and (math.floor(self.elapsed * 3) % 2 == 0 and 1 or 0.7) or 1
    if self.labels.coreAlarm.props.opacity ~= opacity then self.labels.coreAlarm:SetStyle({ opacity = opacity }) end
    local estimate = Proto.ReturnEstimate(run)
    local returnWarning = run.state == "PREPARATION" and
        (not estimate.reachable or not estimate.can_return or run.preparation_remaining <= 8 and estimate.seconds >= 2)
    local returnText = returnWarning and (estimate.reachable and
        "回防约 " .. fmt(math.ceil(estimate.seconds)) .. "秒 · 战备剩余 " .. fmt(math.ceil(run.preparation_remaining)) .. "秒" or "回防路径暂不可用") or
        run.recall.active and "回城中，请勿移动" or ""
    self:Text("returnWarning", returnText)
    self:Visible(self.labels.returnWarning, returnText ~= "" and alarm == "")
    local causal = self.noticeRemaining > 0 and self.latestNotice or ""
    if causal == "" and not critical and alert <= 0 then
        for _, s in ipairs(run.causal_summaries or {}) do
            if not s.expires_at or s.expires_at > run.clock then causal = summaryText(s) end
        end
    end
    if causal == "" and self.stageNoticeRemaining > 0 then causal = self.stageNotice end
    local hint = run.observation_hint
    if causal == "" and hint and hint.expires_at > run.clock and self.hintsEnabled then causal = hint.text end
    self:Text("causalNotice", causal); self:Visible(self.labels.causalNotice, causal ~= "" and not critical and alert <= 0)
    local canPlay = not paused(run) and not run.ended and not self.menuOpen
    self:SetButton("pause", "暂停", not canPlay)
    local modulePending = #Proto.Pending(run)
    local canInspect = not run.ended and not self.menuOpen and not (run.pause_reasons or {}).technical
    self:SetButton("modules", "模块 " .. fmt(modulePending), not canInspect or modulePending == 0)
    self:Visible(self.buttons.modules, modulePending > 0)
    self:SetButton("map", "地图", not canInspect or run.config.polygon_expansion and run.state ~= "PREPARATION")
    self:SetButton("wave", "开波", not canPlay or run.state ~= "PREPARATION")
    self:SetButton("logistics", run.config.polygon_expansion and "布防" or "后勤", not canPlay or run.state ~= "PREPARATION" or run.room_encounter ~= nil)
    self:SetButton("active", p.active_cd <= 0 and "击退" or "击退 " .. fmt(math.ceil(p.active_cd)) .. "秒", not canPlay or p.active_cd > 0)
    self:Visible(self.buttons.wave, run.state == "PREPARATION")
    self:Visible(self.buttons.logistics, run.state == "PREPARATION")
    local id = run.map:RoomAt(p.x, p.y)
    local room = {}
    for _, r in ipairs(run.rooms) do if r.id == id then room = r; break end end
    self:SetButton("claim", "领取", not canPlay or room.state ~= "cleared")
    self:Visible(self.buttons.claim, room.state == "cleared")
    self:SetButton("recall", run.recall.active and "回城中" or "回城", not canPlay or run.state ~= "PREPARATION" or
        (room.state ~= "cleared" and room.state ~= "claimed") or run.recall.active)
    self:Visible(self.buttons.recall, run.recall.active or run.state == "PREPARATION" and (room.state == "cleared" or room.state == "claimed"))
    if run.config.polygon_expansion then
        local ok = require("defense.Anchors").Check(run, run.config.topology.main)
        self:SetButton("recall", "返回主空间", not canPlay or not ok)
        self:Visible(self.buttons.recall, run.anchors[id] ~= nil and run.state == "PREPARATION")
    end
    if self.modeKey == "logistics" then self:RefreshLogistics() end
    if self.modalLabels.pause then self.modalLabels.pause:SetText("第 " .. fmt(run.wave_id) .. " / " .. fmt(run.total_waves) ..
        " 波 · 入口 " .. portals .. " · 待结算危险 " .. fmt(pending)) end
    if self.modalLabels.story then self.modalLabels.story:SetText(string.format("%.1f / %.1f 秒", run.story.elapsed, run.story.duration)) end
end
function View:Update(dt)
    if self.destroyed then return end
    self.elapsed = self.elapsed + dt
    self.atmosphere = Theme.Atmosphere(self.elapsed)
    self.noticeRemaining = math.max(0, self.noticeRemaining - dt)
    self.stageNoticeRemaining = math.max(0, self.stageNoticeRemaining - dt)
    if self.noticeRemaining == 0 and self.modeKey ~= "logistics" then self.latestNotice = "" end
    if self.replayPreview and not self.run.story.replay then self.replayPreview = false end
    local width, height = UI.GetViewportSize()
    local compact = width < 660 or height < 600
    local narrow = width < 560
    local modalLayoutKey = tostring(compact) .. ":" .. tostring(narrow) .. ":" .. tostring(width >= 800)
    if self.modalLayoutKey ~= modalLayoutKey and self.modeKey ~= "__dirty" then self.modeKey = "__dirty" end
    self.modalLayoutKey = modalLayoutKey
    local mode = self:Mode()
    self:RefreshOverlay(mode)
    if modalLayoutKey ~= self.layoutKey then
        self.layoutKey = modalLayoutKey
        self.radarPanel:SetWidth(compact and 100 or 116)
        self.radar:SetHeight(compact and 68 or 84)
        self.hudNarrow = narrow
        self.top:SetStyle({ padding = compact and 6 or 8, gap = 4 })
        self.overlay:SetStyle({ padding = compact and 8 or 16 })
    end
    local topHeight = self.top:GetLayout().h or 0
    if topHeight > 0 and math.abs(topHeight - self.topHeight) > 0.5 then
        self.topHeight = topHeight
        self.alerts:SetStyle({ top = topHeight + 6 })
        self.radarPanel:SetStyle({ top = topHeight + 60 })
    end
    self:Visible(self.top, mode == "")
    self:Visible(self.alerts, mode == "")
    self:Visible(self.bottom, mode == "")
    self:Visible(self.radarPanel, mode == "" and not narrow)
    self.updateRemaining = self.updateRemaining - dt
    if self.dirty or self.updateRemaining <= 0 then
        self:UpdateHUD(); self.dirty, self.updateRemaining = false, 0.1
    end
end
function View:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    Art.CancelInput(self.root)
    if UI.GetRoot() == self.root then UI.SetRoot(nil, false) end
    self.root:Destroy()
end
return View
