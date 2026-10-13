local UI = require("urhox-libs/UI")
local Theme = require("defense.Theme")
local Art = require("defense.UIArt")
local TowerModules = require("defense.TowerModules")
local Scenarios = require("defense.Scenarios")
local RoomGraph = require("defense.RoomGraph")
local Expedition = require("defense.Expedition")
local Economy = require("defense.Economy")
local Feedback = require("defense.Feedback")
local C = Theme.C
local P = {}
local function num(value) return string.format("%.2f", tonumber(value) or 0) end
local function whole(value) return tostring(math.floor(tonumber(value) or 0)) end
local function text(value, color, size)
    return UI.Label { text = value or "", width = "100%", flexShrink = 1, whiteSpace = "normal",
        wordBreak = "break-word", maxLines = 24, fontFamily = "pixel", fontSize = Theme.TextSize(size or 11),
        fontColor = color or C.text, lineHeight = 1.35 }
end
local function box(children, view)
    return Art.Frame({ width = "100%", padding = 10, gap = 7,
        backgroundColor = C.card, borderWidth = 1, borderColor = C.cyanSoft, children = children or {} }, view)
end
local function row(children)
    return UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6,
        pointerEvents = "box-none", children = children or {} }
end
local function set(label, value)
    if label and label.props.text ~= value then label:SetText(value) end
end
local function roomById(run, id)
    for _, room in ipairs(run.rooms or {}) do if room.id == id then return room end end
    return nil
end
local function towerAt(run, slot)
    local destroyed = nil --[[@as table?]]
    for _, tower in ipairs(run.towers or {}) do
        if tower.slot_id == slot then
            if tower.hp > 0 then return tower end
            destroyed = tower
        end
    end
    return destroyed
end
local SCENARIO_NAMES = { legacy_v02 = "经典防守", reuse_sample = "三房间考验", large_map_proto = "外圈远征", sanctuary_expansion = "神殿扩展", polygon_expansion = "多边形远域" }
local REGION_NAMES = { A = "森林 / 西区", B = "冰川 / 东区", C = "火山 / 南区" }
local function roomName(run, id)
    if not id or id == "core" then return "主殿" end
    if id == "logistics" then return "后勤站" end
    local room = roomById(run, id)
    return room and (room.name or room.title) or tostring(id)
end
local function targetPolicy(policy)
    if policy == "priority" then return "远征/精英优先" end
    if policy == "nearest" then return "最近目标" end
    return "默认目标"
end
local function markDirty(view)
    view.modeKey, view.dirty = "__dirty", true
end
function P.Definitions(run)
    if TowerModules.GetDefinitions then return TowerModules.GetDefinitions(run.config) or {} end
    return TowerModules.Definitions or {}
end
function P.Pending(run)
    local pending = {}
    for _, choice in ipairs(run.pending_module_choices or {}) do
        if not choice.chosen_module_id and not choice.resolved then pending[#pending + 1] = choice end
    end
    return pending
end
function P.CurrentChoice(run)
    local pending = P.Pending(run)
    for _, choice in ipairs(pending) do
        if (choice.choice_id or choice.id) == run.module_choice_id then return choice end
    end
    for _, choice in ipairs(pending) do if not choice.waiting and #(choice.candidates or {}) > 0 then return choice end end
    return pending[1]
end
function P.ModuleKey(run)
    local choice = P.CurrentChoice(run)
    local key = "moduleChoice:" .. tostring(choice and (choice.choice_id or choice.id) or "empty")
    for _, id in ipairs(choice and choice.candidates or {}) do key = key .. ":" .. tostring(id) end
    return key
end
function P.Scenario(run)
    return run.scenario_id or (run.config or {}).scenario_id or "legacy_v02"
end
function P.Identity(run)
    return SCENARIO_NAMES[P.Scenario(run)] or "当前防守场景"
end
function P.LastReport(run)
    if Feedback.LastReport then return Feedback.LastReport(run) end
    local report = run.meta.last_report
    if report and (not report.scenario_id and P.Scenario(run) == "legacy_v02" or report.scenario_id == P.Scenario(run)) then return report end
    return nil
end
function P.StorySeen(run, node)
    if run.StorySeen then return run:StorySeen(node) end
    return P.Scenario(run) == "legacy_v02" and (run.meta.story_seen or {})[node] == true
end
local function effectiveSlow(run, attributes)
    return math.max(0, math.min((run.config.reactions or {}).slow_cap or 0.5, attributes.slow_amount or 0))
end
function P.AttributesText(attributes, run)
    if not attributes then return "属性暂不可用" end
    local lines = { "伤害 " .. num(attributes.damage) .. " · 间隔 " .. num(attributes.interval) .. "秒 · 射程 " .. num(attributes.range) .. "格" }
    local cap = run and (run.config.reactions or {}).slow_cap or 0.5
    local slow = math.max(0, math.min(cap, attributes.slow_amount or 0))
    if slow > 0 and (attributes.slow_duration or 0) > 0 then
        lines[#lines + 1] = "减速 " .. num(slow * 100) .. "% · Boss " .. num(slow * 50) .. "% · 持续 " .. num(attributes.slow_duration) .. "秒"
        lines[#lines + 1] = "减速上限 " .. num(cap * 100) .. "% · 多来源取最强" ..
            (attributes.slow_amount > slow and "（已封顶）" or "")
    end
    local extra = {}
    if (attributes.push or 0) > 0 then lines[#lines + 1] = "击退 " .. num(attributes.push) .. "格" end
    if (attributes.repair or 0) > 0 then lines[#lines + 1] = "每次维修 " .. num(attributes.repair) .. "耐久 · 范围/视线内" end
    if (attributes.energy or 0) > 0 then lines[#lines + 1] = "供能加速 " .. num(attributes.energy * 100) .. "% · 不叠乘" end
    if (attributes.energy_received or 0) > 0 then lines[#lines + 1] = "接受供能 " .. num(attributes.energy_received * 100) .. "%（已计入间隔）" end
    if (attributes.splash or 0) > 0 then extra[#extra + 1] = "溅射 " .. num(attributes.splash) .. "格" end
    if (attributes.pierce or 0) > 0 then extra[#extra + 1] = "额外穿透 " .. whole(attributes.pierce) end
    if #extra > 0 then lines[#lines + 1] = table.concat(extra, " · ") end
    lines[#lines + 1] = "目标：" .. targetPolicy(attributes.target_policy)
    return table.concat(lines, "\n")
end
local function moduleDifference(run, tower, moduleId)
    local before = TowerModules.Attributes(run, tower)
    local after = TowerModules.Attributes(run, tower, moduleId)
    local lines = {}
    for _, field in ipairs({ { "damage", "伤害", 1 }, { "interval", "间隔秒", 1 }, { "range", "射程格", 1 },
        { "slow_duration", "持续秒", 1 }, { "splash", "溅射格", 1 }, { "pierce", "额外穿透", 1 } }) do
        local a, b = (before[field[1]] or 0) * field[3], (after[field[1]] or 0) * field[3]
        if a ~= b then lines[#lines + 1] = field[2] .. " " .. num(a) .. " → " .. num(b) end
    end
    if before.target_policy ~= after.target_policy then
        lines[#lines + 1] = "目标 " .. targetPolicy(before.target_policy) .. " → " .. targetPolicy(after.target_policy)
    end
    if before.slow_amount ~= after.slow_amount then
        local a, b = effectiveSlow(run, before), effectiveSlow(run, after)
        lines[#lines + 1] = "有效减速 " .. num(a * 100) .. "% → " .. num(b * 100) .. "% · Boss " ..
            num(a * 50) .. "% → " .. num(b * 50) .. "%"
        if a == b then lines[#lines + 1] = "已达公共上限，减速没有额外提升" end
    end
    return #lines == 0 and "当前属性与目标策略不变" or table.concat(lines, "\n")
end
function P.Preview(run, tower, moduleId)
    return moduleDifference(run, tower, moduleId) .. "\n安装后：\n" ..
        P.AttributesText(TowerModules.Attributes(run, tower, moduleId), run)
end
function P.InventoryText(run)
    local definitions, names = P.Definitions(run), {}
    for id, owned in pairs(run.module_inventory or {}) do
        if owned then names[#names + 1] = definitions[id] and definitions[id].name or tostring(id) end
    end
    table.sort(names)
    return "本局模块库存 " .. #names .. "：" .. (#names > 0 and table.concat(names, " / ") or "尚未获得")
end

function P.BuildScenarioMenu(view, parent)
    local selected = view.selectedScenario or P.Scenario(view.run)
    if not SCENARIO_NAMES[selected] then selected = "legacy_v02" end
    view.selectedScenario = selected
    local buttons = {}
    for _, id in ipairs(Scenarios.List()) do
        local button = view:Button(SCENARIO_NAMES[id], function()
            view.selectedScenario = id
            markDirty(view)
        end, selected == id and "success" or "secondary")
        button:SetStyle({ width = "auto", flexGrow = 1, flexShrink = 1, flexBasis = 140, minWidth = 120, height = 44 })
        buttons[#buttons + 1] = button
    end
    parent:AddChild(row(buttons))
    local descriptions = {
        legacy_v02 = "20波经典守核；可切换5波教学。",
        reuse_sample = "5波防守；第5波远征穿过三处房间，探索模块与外围布防。",
        large_map_proto = "20波外圈防守；第10、20波远征巡行，多房间探索与捷径。",
        sanctuary_expansion = "20波守核；速清最多+15秒探索，星砂与四类设施构筑。清过据点后追加考验与三队远征，逐房间核心限伤。原型数值待试玩。",
        polygon_expansion = "多边形房间 · 三路守核。三角三波、六边两波小Boss、地区核心Boss；清空六边激活传送。就地布防，战备期地图可传送。",
    }
    parent:AddChild(text(descriptions[selected], C.dim))
    if selected == "polygon_expansion" then
        local levels = {}
        for level = 1, 5 do
            local button = view:Button("难度 " .. level, function()
                view.selectedPolygonDifficulty = level; markDirty(view)
            end, (view.selectedPolygonDifficulty or view.run.config.difficulty or 1) == level and "success" or "secondary")
            button:SetStyle({ flexGrow = 1, height = 44, minWidth = 70 })
            levels[#levels + 1] = button
        end
        parent:AddChild(row(levels))
    end
    local total = selected == "legacy_v02" and (view.selectedLegacyWaves or 20) or Scenarios.Get(selected).total_waves
    if selected == "legacy_v02" then
        local lengths = {}
        for _, waves in ipairs({ 20, 5 }) do
            local button = view:Button(waves == 20 and "完整防守 · 20波" or "教学 · 5波", function()
                view.selectedLegacyWaves = waves
                markDirty(view)
            end, total == waves and "success" or "secondary")
            button:SetStyle({ flexGrow = 1, height = 44 })
            lengths[#lengths + 1] = button
        end
        parent:AddChild(row(lengths))
    end
    parent:AddChild(view:Button("开始防守 · " .. whole(total) .. "波", function() view:NewRun(total, false, selected) end, "primary"))
end
function P.OpenButtons(view, parent)
    local pending = #P.Pending(view.run)
    local modules = view:Button("模块待选 " .. whole(pending), function() view:Action("module_open") end)
    modules:SetDisabled(pending == 0 or view.run.ended or (view.run.pause_reasons or {}).technical == true)
    parent:AddChild(row({ modules, view:Button("房间地图", function() view:Action("map") end) }))
end
function P.BuildModules(view)
    local run, choice = view.run, P.CurrentChoice(view.run)
    local scroll, panel = view:ModalShell("探索模块", "已暂停；解锁后可在本局后勤安装。关闭会保留待选机会。")
    scroll:AddChild(text(P.InventoryText(run), Theme.Gold))
    if (run.pause_reasons or {}).upgrade then scroll:AddChild(text("角色成长仍待选择，关闭后继续。", C.warn)) end
    local pending = P.Pending(run)
    local tabs = {}
    for _, offer in ipairs(pending) do
        local id = offer.choice_id or offer.id
        tabs[#tabs + 1] = view:Button(roomName(run, offer.room_id), function() view:Action("module_open", id) end)
    end
    if #tabs > 1 then scroll:AddChild(row(tabs)) end
    if not choice then
        scroll:AddChild(text("没有待选模块；已解锁模块仍可在后勤使用。", C.dim))
    else
        scroll:AddChild(text("来自 " .. roomName(run, choice.room_id) .. " · 待选 " .. whole(#pending) .. " 次", C.dim))
        if choice.waiting then scroll:AddChild(text("请先完成其它待选机会，本次选择已保留。", C.warn)) end
        local definitions = P.Definitions(run)
        for _, moduleId in ipairs(choice.candidates or {}) do
            local def = definitions[moduleId]
            if def then
                local tower = { type = def.tower_type, upgrade_count = 0 }
                local towerDef = run.config.towers[def.tower_type]
                scroll:AddChild(box({ Art.Heading("turret", def.name .. " · " .. (towerDef and towerDef.name or "设施模块"), C.text),
                    text(def.detail, C.text), text(moduleDifference(run, tower, moduleId), C.dim),
                    view:Button("解锁 " .. def.name, function()
                        view:Action("module_choose", { choice_id = choice.choice_id or choice.id, module_id = moduleId })
                    end, "success") }, view))
            else scroll:AddChild(text("该候选暂不可用。", C.warn)) end
        end
        scroll:AddChild(text("差异以未升级基础塔与当前角色协同计算；具体设施见后勤。首次安装免费，更换服务费20资金，不返还。", C.dim, 10))
    end
    panel:AddChild(view:Button((run.pause_reasons or {}).upgrade and "返回角色成长" or "返回", function()
        view:Action("module_close")
    end, "primary"))
end

local function owner(slot) return slot.owner_room_id or "core" end
local function aliveTowers(run, ownerId)
    local count = 0
    for _, tower in ipairs(run.towers or {}) do
        if tower.hp > 0 then
            local towerOwner = tower.owner_room_id
            if not towerOwner then
                for _, slot in ipairs(run.config.build_slots or {}) do if slot.id == tower.slot_id then towerOwner = slot.owner_room_id; break end end
            end
            if not ownerId or (towerOwner or "core") == ownerId then count = count + 1 end
        end
    end
    return count
end
local function roomState(run, id)
    if id == "core" then return "主殿固定防线" end
    local room = roomById(run, id)
    if not room then return "房间不可用" end
    local access = room.accessible
    if access == nil then access = room.unlocked end
    local deployment = ""
    for _, slot in ipairs(run.config.build_slots or {}) do
        if slot.owner_room_id == id then deployment = " · 可布防"; break end
    end
    if room.state == "claimed" or room.reward_claimed then return "已清空 · 已领奖" .. deployment end
    if room.state == "cleared" then return "已清空 · 待领奖" .. deployment end
    if room.state == "active" then return "守军交战 · 未清不可建造" end
    return (access and "可探索" or "尚未开放") .. " · 未清不可建造"
end
local function logisticsGroups(run)
    local groups, order = {}, {}
    for _, slot in ipairs(run.config.build_slots or {}) do
        local id = owner(slot)
        if not groups[id] then groups[id] = {}; order[#order + 1] = id end
        groups[id][#groups[id] + 1] = slot
    end
    return groups, order
end
local function logisticsKey(view)
    local run, parts = view.run, { tostring(view.selectedLogisticsRoom), tostring(view.selectedLogisticsSlot), P.Scenario(view.run) }
    local tower = towerAt(run, view.selectedLogisticsSlot)
    parts[#parts + 1] = tower and tostring(tower.entity_id or tower.id or "tower") or "empty"
    if tower then
        parts[#parts + 1] = tostring(tower.hp > 0)
        parts[#parts + 1] = tostring(tower.type)
        parts[#parts + 1] = tostring(tower.upgrade_count or 0)
        parts[#parts + 1] = tostring(tower.module_id or "base")
        parts[#parts + 1] = tostring(tower.module_revision or 0)
        parts[#parts + 1] = tostring(tower.branch_id or "none")
    end
    local modules = {}
    for id, owned in pairs(run.module_inventory or {}) do if owned then modules[#modules + 1] = tostring(id) end end
    table.sort(modules)
    for _, id in ipairs(modules) do parts[#parts + 1] = id end
    return table.concat(parts, ":")
end
function P.BuildLogistics(view)
    if view.run.config.polygon_expansion then return require('defense.Placement').Build(view) end
    local run = view.run
    local scroll, panel = view:ModalShell(run.config.polygon_expansion and "就地布防" or "后勤布防",
        run.config.polygon_expansion and "已暂停；仅可操作当前房间槽位。资金与12个存活名额全域共享。" or "已暂停；仅战备期可操作。主殿与外围共用资金和存活名额。")
    view.modalLabels.balance, view.modalLabels.transaction = text("", Theme.Gold, 13), text("", C.green)
    scroll:AddChild(view.modalLabels.balance)
    scroll:AddChild(view.modalLabels.transaction)
    scroll:AddChild(Art.Heading("repair", "核心维护", C.text))
    local repair = view:TransactionButton("repair", nil, nil, "核心修复 +200 · 40资金")
    local heal = view:TransactionButton("heal", nil, nil, "角色治疗 +25 · 20资金")
    repair:SetStyle({ width = "auto", flexGrow = 1, flexBasis = 0, minWidth = 165 })
    heal:SetStyle({ width = "auto", flexGrow = 1, flexBasis = 0, minWidth = 165 })
    scroll:AddChild(row({ repair, heal }))
    P.OpenButtons(view, scroll)
    view.protoSlots, view.protoLogisticsRooms, view.protoLogisticsSelectors = {}, {}, {}
    view.selectedLogisticsSlots = view.selectedLogisticsSlots or {}
    local groups, order = logisticsGroups(run)
    if run.config.polygon_expansion then
        local localId=run.map:RoomAt(run.player.x,run.player.y) or run.config.topology.main
        if localId==run.config.topology.main then localId="core" end
        groups,order={ [localId]=groups[localId] or {} },{localId}
        view.selectedLogisticsRoom=localId
    end
    if not groups[view.selectedLogisticsRoom] then view.selectedLogisticsRoom = order[1] end
    local selectedSlots = groups[view.selectedLogisticsRoom] or {}
    local selected = nil --[[@as table?]]
    for _, slot in ipairs(selectedSlots) do if slot.id == view.selectedLogisticsSlot then selected = slot; break end end
    if not selected then
        local remembered = view.selectedLogisticsSlots[view.selectedLogisticsRoom]
        for _, slot in ipairs(selectedSlots) do if slot.id == remembered then selected = slot; break end end
        selected = selected or selectedSlots[1]
        view.selectedLogisticsSlot = selected and selected.id or nil
    end
    if selected then view.selectedLogisticsSlots[view.selectedLogisticsRoom] = selected.id end
    local regions, regionOrder = {}, {}
    for _, id in ipairs(order) do
        local room = roomById(run, id)
        local region = room and (room.region_id or room.id:sub(1, 1)) or "core"
        if not regions[region] then regions[region] = {}; regionOrder[#regionOrder + 1] = region end
        local button = view:Button(roomName(run, id), function()
            view.selectedLogisticsRoom = id
            markDirty(view)
        end, id == view.selectedLogisticsRoom and "success" or "secondary")
        button:SetStyle({ height = 44, minWidth = 75, flexGrow = 1 })
        regions[region][#regions[region] + 1] = button
        view.protoLogisticsRooms[#view.protoLogisticsRooms + 1] = { id = id, button = button }
    end
    for _, region in ipairs(regionOrder) do
        if #regionOrder > 1 then scroll:AddChild(text(REGION_NAMES[region] or "主殿", C.dim, 10)) end
        scroll:AddChild(row(regions[region]))
    end
    local slots = {}
    for index, slot in ipairs(selectedSlots) do
        local button = view:Button("槽位 " .. whole(index), function()
            view.selectedLogisticsSlot = slot.id
            view.selectedLogisticsSlots[view.selectedLogisticsRoom] = slot.id
            markDirty(view)
        end, slot.id == view.selectedLogisticsSlot and "success" or "secondary")
        button:SetStyle({ height = 44, minWidth = 85, flexGrow = 1 })
        slots[#slots + 1] = button
        view.protoLogisticsSelectors[#view.protoLogisticsSelectors + 1] = { slot = slot, index = index, button = button }
    end
    if #slots > 1 then scroll:AddChild(row(slots)) end
    if selected then
        local status, attrs, deployment = text("", C.text, 12), text("", C.cyan), text("", C.dim)
        ---@type Widget[]
        local children = { Art.Heading("turret", "当前选中槽", C.text), deployment, status, attrs }
        local tower = towerAt(run, selected.id)
        local previews = {}
        if not tower or tower.hp <= 0 then
            if run.config.sanctuary_expansion then
                local kind = view.facilityPreviewType or "rapid"
                local a = TowerModules.Attributes(run, { type = kind, upgrade_count = 0, hp = 1, x = selected.x, y = selected.y })
                local mini = P.MapOverview(run)
                local size, origin = run.config.map_size, run.config.map_origin or { x = 0, y = 0 }
                mini:AddChild(UI.Panel { position = "absolute", left = tostring((selected.x - a.range - origin.x) / size.w * 100) .. "%",
                    top = tostring((selected.y - a.range - origin.y) / size.h * 100) .. "%",
                    width = tostring(a.range * 2 / size.w * 100) .. "%", height = tostring(a.range * 2 / size.h * 100) .. "%",
                    borderRadius = 1000, borderWidth = 2, borderColor = C.cyan, backgroundColor = { 0, 0, 0, 0 }, pointerEvents = "none" })
                children[#children + 1] = text("预览 " .. run.config.towers[kind].name .. " · 圆环为最大距离，实战按墙柱/视线与所属房间裁剪。", C.dim, 10)
                children[#children + 1] = mini
                children[#children + 1] = text(P.AttributesText(a, run), C.dim, 10)
            end
            for _, kind in ipairs(run.config.facility_order or { "rapid", "slow", "area" }) do
                local def = run.config.towers[kind]
                children[#children + 1] = view:TransactionButton("build", selected.id, kind, "建造 " .. def.name .. " · " .. whole(def.cost) .. "资金" ..
                    ((def.sand_cost or 0) > 0 and " + " .. whole(def.sand_cost) .. "星砂" or ""))
                if run.config.sanctuary_expansion then
                    children[#children + 1] = view:Button("预览 " .. def.name, function() view.facilityPreviewType = kind; markDirty(view) end)
                    children[#children + 1] = text(def.family .. " · 覆盖 " .. num(def.range) .. "格 · 基础输出 " .. num(def.damage / def.interval) .. "/秒", C.dim, 10)
                end
            end
        else
            children[#children + 1] = view:TransactionButton("upgrade", selected.id, nil, "升级 · " .. whole(tower.upgrade_count or 0) .. "/2")
            children[#children + 1] = view:TransactionButton("demolish", selected.id, nil, "拆除设施")
            children[#children + 1] = view:TransactionButton("repair_tower", selected.id, nil, "修复设施 +80 / 20资金")
            if run.config.sanctuary_expansion then
                children[#children + 1] = text("升级一次后可选分支，消耗20星砂。选择不可逆，星砂拆除不返。", C.warn)
                for _, id in ipairs({ "reach", "focus" }) do
                    local branch = run.config.branches[id]
                    children[#children + 1] = view:TransactionButton("branch", selected.id, id, branch.name .. " · 20星砂")
                    local preview = Feedback.Copy(tower); preview.branch_id = id
                    children[#children + 1] = text("分支预览：" .. P.AttributesText(TowerModules.Attributes(run, preview), run), C.dim, 10)
                end
            end
            local definitions, ids = P.Definitions(run), {}
            for id, owned in pairs(run.module_inventory or {}) do
                local def = definitions[id]
                if owned and def and def.tower_type == tower.type and TowerModules.Enabled(run) then ids[#ids + 1] = id end
            end
            table.sort(ids)
            if #ids == 0 then children[#children + 1] = text("暂无已解锁的适用模块。", C.dim) end
            for _, id in ipairs(ids) do
                local def = definitions[id]
                local preview = text("", C.dim)
                children[#children + 1] = text(def.name, C.purple, 12)
                children[#children + 1] = text(def.detail, C.text)
                children[#children + 1] = preview
                children[#children + 1] = view:TransactionButton("module", selected.id, id, tower.module_id == id and "已安装 " .. def.name or "安装 " .. def.name)
                previews[#previews + 1] = { id = id, widget = preview }
            end
            children[#children + 1] = text("更换模块保留等级、生命与冷却；服务费不返还。完好拆除返还建造与升级支出的50%，受损不返。", C.dim, 10)
        end
        scroll:AddChild(box(children, view))
        view.protoSlots[1] = { slot = selected, status = status, attrs = attrs, deployment = deployment, previews = previews }
    else scroll:AddChild(text("本场景没有建造槽位。", C.dim)) end
    view.protoLogisticsKey = logisticsKey(view)
    panel:AddChild(view:Button("继续战备", function() view:Action("close_logistics") end, "primary"))
    P.RefreshLogistics(view)
end
function P.RefreshLogistics(view)
    if view.run.config.polygon_expansion then return require('defense.Placement').Refresh(view) end
    local run, definitions = view.run, P.Definitions(view.run)
    set(view.modalLabels.balance, "资金 " .. whole(run.currency) .. " · 战备 " .. whole(math.ceil(run.preparation_remaining)) ..
        "秒 · 修复 " .. whole(run.repair_uses) .. "/3 · 存活塔 " .. whole(aliveTowers(run)) .. "/" .. whole(run.config.max_alive_towers or 6) ..
        (run.config.sanctuary_expansion and " · 星砂 " .. whole(run.exploration_currency) .. " / 累计收入 " .. whole(run.exploration_currency_earned) .. "/120" or ""))
    set(view.modalLabels.transaction, view.latestNotice)
    for _, binding in ipairs(view.transactionButtons) do
        local ok, reason, price = Economy.Check(run, binding.action, binding.slot, binding.towerType)
        local button = binding.button --[[@as Button]]
        local reasonLabel = binding.reason --[[@as Label]]
        button:SetDisabled(not ok)
        local suffix = (binding.action == "upgrade" or binding.action == "module") and price ~= nil and " · " .. whole(price) .. "资金" or ""
        set(button, binding.caption .. suffix)
        set(reasonLabel, ok and "" or tostring(reason or "暂不可操作"))
    end
    for _, binding in ipairs(view.protoLogisticsRooms or {}) do
        local button = binding.button --[[@as Button]]
        set(button, roomName(run, binding.id) .. " · " .. whole(aliveTowers(run, binding.id)) .. "塔")
    end
    for _, binding in ipairs(view.protoLogisticsSelectors or {}) do
        local tower = towerAt(run, binding.slot.id)
        local def = tower and run.config.towers[tower.type]
        local state = tower and tower.hp > 0 and (def and def.name or "设施") or tower and "损毁" or "空"
        local button = binding.button --[[@as Button]]
        set(button, "槽位 " .. whole(binding.index) .. " · " .. state)
    end
    for _, binding in ipairs(view.protoSlots or {}) do
        local tower = towerAt(run, binding.slot.id)
        local scope = run.config.sanctuary_expansion and "攻击本房守军、考验与远征；射程与墙柱遮挡仍生效。" or
            "仅攻击本区域内的远征目标；射程与墙柱遮挡仍生效。"
        set(binding.deployment, roomName(run, owner(binding.slot)) .. " · " .. roomState(run, owner(binding.slot)) ..
            (binding.slot.activation_region_id and "\n" .. scope or ""))
        if tower and tower.hp > 0 then
            local module = tower.module_id and definitions[tower.module_id]
            local def = run.config.towers[tower.type]
            set(binding.status, (def and def.name or "设施") .. " · 等级 " .. whole((tower.upgrade_count or 0) + 1) ..
                " · 耐久 " .. num(tower.hp) .. "/" .. num(tower.max_hp) .. "\n模块：" .. (module and module.name or "未安装"))
            set(binding.attrs, P.AttributesText(TowerModules.Attributes(run, tower), run))
        else
            set(binding.status, tower and "设施已损毁，可重建。" or "空槽：选择设施建造。")
            set(binding.attrs, "")
        end
        for _, preview in ipairs(binding.previews) do
            if tower and tower.hp > 0 then set(preview.widget, moduleDifference(run, tower, preview.id)) end
        end
    end
    if view.protoLogisticsKey and logisticsKey(view) ~= view.protoLogisticsKey then markDirty(view) end
end

function P.ReturnEstimate(run)
    return RoomGraph.EstimateReturn(run)
end
function P.ReturnText(run, estimate)
    if run.config.polygon_expansion then
        local id = run.map:RoomAt(run.player.x, run.player.y)
        local room = roomById(run, id)
        if run.room_encounter then return "房间交战 " .. tostring(room and room.encounter_wave or 1) .. " 波 · 清空后可离开；主空间仍按时进攻" end
        return "步行回防或使用已激活六边锚点 · 传送冷却 " .. whole(math.ceil(run.anchor_cooldown)) .. "秒"
    end
    estimate = estimate or P.ReturnEstimate(run)
    if not estimate.reachable or estimate.seconds == math.huge then return "回防路径不可用：" .. tostring(estimate.reason or "未找到合法路径") end
    local value = "实际路径回防约 " .. num(estimate.seconds) .. "秒 / " .. num(estimate.path_length or estimate.distance) ..
        "格 · 有效速度 " .. num(estimate.effective_speed) .. "格/秒"
    if run.state == "PREPARATION" then
        value = value .. " · 战备剩余 " .. num(run.preparation_remaining) .. "秒 · " ..
            (estimate.can_return and "按当前路径可回防" or "路径回防时间不足")
    end
    return value .. "（仅移动估时，不含途中战斗/领奖）"
end
function P.RouteIds(route, challenge)
    local result = {}
    for _, stop in ipairs(challenge and challenge.stop_ids or route and (route.stops or route.stop_ids) or {}) do
        result[#result + 1] = tostring(type(stop) == "table" and (stop.room_id or stop.id) or stop)
    end
    return result
end
local function routeNames(run, ids)
    local names = {}
    for _, id in ipairs(ids) do names[#names + 1] = roomName(run, id) end
    return table.concat(names, " → ")
end
function P.RouteText(run)
    local challenge = run.current_wave and run.current_wave.challenge
    if not challenge then return "本波守住固定核心。" end
    local route = (run.config.expedition_routes or {})[challenge.route_id]
    return "第" .. whole(run.wave_id) .. "波远征：" .. routeNames(run, P.RouteIds(route, challenge)) .. " → 固定核心"
end
local STAGES = { SPAWNING = "入场", TRAVELLING = "行军", ROOM_ENGAGED = "房间交战", LEAVING = "离站",
    FINAL_ASSAULT = "攻核", DEAD = "已击败" }
function P.Expeditions(run)
    return Expedition.Snapshot(run) or {}
end
function P.ExpeditionText(snapshot, compact)
    local phase = snapshot.stage
    local head = "远征 · " .. (STAGES[phase] or "状态待确认") .. " · HP " .. num(snapshot.hp) .. "/" .. num(snapshot.max_hp)
    local target = snapshot.next_room_id
    if phase == "TRAVELLING" or phase == "SPAWNING" then
        local stop = (snapshot.stops or {})[snapshot.route_index or 1]
        target = snapshot.stop_room_id or stop and stop.room_id
    end
    local nextRoom = tostring(target or "固定核心")
    local separator = compact and " · " or "\n"
    if snapshot.damage_mode == "core_budget" then
        local site = snapshot.current_room_id or snapshot.stop_room_id or nextRoom
        return "第" .. whole(snapshot.squad_id) .. "队 · " .. head .. separator .. site ..
            (phase == "ROOM_ENGAGED" and " · 停留剩余 " .. num(snapshot.engage_remaining) .. "秒" or " → " .. nextRoom) ..
            (compact and "" or "\n巡行可击杀；各队共享来源房间核心损失上限，单位生命不锁底。")
    end
    if phase == "ROOM_ENGAGED" then
        local remaining = snapshot.room_remaining or snapshot.remaining
        local cap = snapshot.room_cap or snapshot.cap
        local seconds = snapshot.engage_remaining or math.max(0, (snapshot.engage_duration or 12) - (snapshot.stage_elapsed or 0))
        return head .. separator .. tostring(snapshot.current_room_id or snapshot.stop_room_id or "房间") .. " 预算 " .. num(remaining) ..
            "/" .. num(cap) .. " · 剩余 " .. num(seconds) .. "秒" ..
            (compact and "" or "\n预算或交战窗口耗尽即离站，至少保留1HP；下一站 " .. nextRoom)
    elseif phase == "FINAL_ASSAULT" then
        return head .. separator .. "可击杀 · 目标固定核心" ..
            (compact and "" or "\n已解除房间限伤与转场免伤，继承沿途剩余生命。")
    elseif phase == "DEAD" then return head end
    return head .. separator .. "转场免伤 → " .. nextRoom
end
function P.HUDText(run)
    if run.config.polygon_expansion and not run.trial_started then
        local room = roomById(run, run.current_room_id)
        local title = room and room.name or "主空间 · 三路守核"
        if run.room_encounter then
            local total = 0
            for _, def in ipairs(run.config.rooms) do if def.id == room.id then total = def.encounter_waves; break end end
            return title .. " · 房间交战 " .. whole(room.encounter_wave) .. "/" .. whole(total) .. "波"
        end
        return title .. " · 传送冷却 " .. whole(math.ceil(run.anchor_cooldown)) .. "秒"
    end
    if run.config.sanctuary_expansion and run.trial_started then
        local alive, teams = 0, {}
        for _, e in ipairs(P.Expeditions(run)) do if e.stage ~= "DEAD" then alive = alive + 1; teams[e.squad_id] = true end end
        local count = 0; for _ in pairs(teams) do count = count + 1 end
        return "神殿考验 · 远征 " .. whole(count) .. "队 / " .. whole(alive) .. "单位 · 剩余 " ..
            whole(math.ceil(math.max(0, run.config.expedition_time_cap - run.attack_elapsed))) .. "秒\n各房核心损失共用上限 " ..
            whole(run.config.room_core_damage_cap) .. " · 详情见地图/战报"
    end
    local lines = {}
    for _, snapshot in ipairs(P.Expeditions(run)) do
        local phase = snapshot.stage
        local hp = "HP " .. whole(snapshot.hp)
        if phase == "ROOM_ENGAGED" then
            local seconds = snapshot.engage_remaining or math.max(0, (snapshot.engage_duration or 12) - (snapshot.stage_elapsed or 0))
            lines[#lines + 1] = "远征 · " .. tostring(snapshot.current_room_id or snapshot.stop_room_id or "交战") ..
                " 预算 " .. whole(snapshot.room_remaining or snapshot.remaining) .. "/" .. whole(snapshot.room_cap or snapshot.cap) ..
                " · " .. whole(math.ceil(seconds)) .. "秒 · " .. hp
        elseif phase == "FINAL_ASSAULT" then
            lines[#lines + 1] = "远征 · 攻核可击杀 · " .. hp
        elseif phase ~= "DEAD" then
            lines[#lines + 1] = "远征 · 行军免伤 · " .. hp
        end
    end
    return table.concat(lines, "\n")
end
function P.RoomSummary(run)
    local cleared, available, deployed = 0, 0, aliveTowers(run)
    for _, room in ipairs(run.rooms or {}) do
        if room.state == "cleared" and not room.reward_claimed then cleared = cleared + 1 end
        if room.state == "cleared" or room.state == "claimed" then available = available + 1 end
    end
    return "清未领 " .. whole(cleared) .. " · 已清 " .. whole(available) .. "\n存活塔 " .. whole(deployed) .. "/" .. whole(run.config.max_alive_towers or 6) .. " · 详情见房间地图"
end
local function shortcutText(run, shortcut)
    local gateId = shortcut.gate_id or shortcut.id
    local state = (run.map.locked or {})[gateId]
    local roomId = type(shortcut.unlock_condition) == "table" and (shortcut.unlock_condition.room_id or shortcut.unlock_condition.room) or shortcut.unlock_condition
    return roomName(run, shortcut.from) .. " ↔ " .. roomName(run, shortcut.to) .. " · " ..
        (state == false and "已开放" or state == true and "未开放" or "状态待确认") ..
        (state ~= false and roomId and "（清空 " .. roomName(run, roomId) .. " 后开放）" or "")
end
function P.MapOverview(run)
    if run.config.polygon_expansion then
        return require("defense.PolygonMapView").Widget { run = run, width = "100%", height = 300,
            backgroundColor = C.ink, borderWidth = 1, borderColor = C.cyanDim, borderRadius = 8, pointerEvents = "auto" }
    end
    local size, origin = run.config.map_size, run.config.map_origin or { x = 0, y = 0 }
    local w, h = size.w, size.h
    local panel = UI.Panel { width = "100%", aspectRatio = w / h, backgroundColor = C.ink,
        borderWidth = 1, borderColor = C.cyanDim, borderRadius = 8, overflow = "hidden", pointerEvents = "none" }
    local function px(x) return tostring((x - origin.x) / w * 100) .. "%" end
    local function py(y) return tostring((y - origin.y) / h * 100) .. "%" end
    for _, region in ipairs(run.config.walkable_regions or {}) do
        panel:AddChild(UI.Panel { position = "absolute", left = px(region.x1), top = py(region.y1),
            width = tostring((region.x2 - region.x1) / w * 100) .. "%", height = tostring((region.y2 - region.y1) / h * 100) .. "%",
            backgroundColor = C.hall, borderRadius = 0, pointerEvents = "none" })
    end
    for _, obstacle in ipairs(run.config.obstacles or {}) do
        panel:AddChild(UI.Panel { position = "absolute", left = px(obstacle.x1), top = py(obstacle.y1),
            width = tostring((obstacle.x2 - obstacle.x1) / w * 100) .. "%", height = tostring((obstacle.y2 - obstacle.y1) / h * 100) .. "%",
            backgroundColor = C.ink, borderRadius = 0, pointerEvents = "none" })
    end
    local function marker(x, y, caption, color)
        panel:AddChild(UI.Label { text = caption, position = "absolute", left = px(x), top = py(y),
            fontFamily = "pixel", fontSize = Theme.TextSize(9),
            fontColor = color, textStroke = { width = 1, color = C.ink }, pointerEvents = "none" })
    end
    for _, room in ipairs(run.rooms or {}) do marker(room.x - 1, room.y, roomName(run, room.id), room.state == "cleared" and C.warn or
        room.state == "claimed" and C.green or room.accessible == false and C.dim or C.cyan) end
    marker(run.core.x - 2, run.core.y, "核心", C.cyan)
    marker(run.player.x, run.player.y, "你", C.text)
    local directions = { W = "西入口", E = "东入口", S = "南入口" }
    for id, portal in pairs(run.config.portals or {}) do marker(portal.x, portal.y, directions[id] or "入口", C.error) end
    for _, gate in ipairs(run.config.gate_regions or {}) do
        panel:AddChild(UI.Panel { position = "absolute", left = px(gate.x1), top = py(gate.y1),
            width = tostring((gate.x2 - gate.x1) / w * 100) .. "%", height = tostring((gate.y2 - gate.y1) / h * 100) .. "%",
            backgroundColor = (run.map.locked or {})[gate.id] == false and C.green or C.error, borderRadius = 0, pointerEvents = "none" })
    end
    return panel
end
function P.BuildMap(view)
    local run = view.run
    local scroll, panel = view:ModalShell("房间地图", "已暂停；查看路线、房间状态与布防。")
    local overview=P.MapOverview(run)
    view.mapOverview=overview
    if run.config.polygon_expansion then
        panel:SetStyle({maxWidth=1280})
        local _,height=UI.GetViewportSize()
        overview:SetHeight(math.max(180,math.min(560,height*0.52)))
        -- 地图固定在窗口主区域；详情另行滚动，不把地图藏在长列表里。
        panel:RemoveChild(scroll); panel:AddChild(overview); panel:AddChild(scroll)
        scroll:AddChild(row({view:Button("放大 +",function() overview.zoom=math.min(10,overview.zoom*1.4) end),
            view:Button("缩小 -",function() overview.zoom=math.max(1,overview.zoom/1.4) end),
            view:Button("全图复位",function() overview.zoom,overview.panX,overview.panY=1,0,0 end)}))
        scroll:AddChild(text(#run.config.topology.rooms.."房间 · "..run.config.topology.stats.loops.."环路 · 滚轮/捏合缩放，拖动平移",C.cyan))
    else scroll:AddChild(overview) end
    if run.config.polygon_expansion then
        local Anchors = require("defense.Anchors")
        local legend=text("点击地图传送点：绿=可传送，橙=已激活但暂不可传，红=未激活",C.dim)
        view.mapTeleportStatus=text(run.last_teleport and run.last_teleport.reason or '点击地图上的传送点查看或传送',C.warn)
        panel:RemoveChild(scroll);panel:AddChild(legend);panel:AddChild(view.mapTeleportStatus);panel:AddChild(scroll)
        overview.props.onAnchorClick=function(id)
            local ok,reason=Anchors.Check(run,id)
            if ok then view:Action('teleport',id)
            else run.last_teleport={ok=false,reason=reason,target_id=id} end
            set(view.mapTeleportStatus,run.last_teleport.reason)
        end
    end
    scroll:AddChild(text("蓝：可探索 · 橙：待领奖 · 绿：已领奖 · 灰：未开放", C.dim, 10))
    scroll:AddChild(text(P.ReturnText(run), C.warn))
    local upcoming, routeOrder = {}, {}
    for index, wave in ipairs(run.config.waves or {}) do
        if index >= run.wave_id and index <= run.total_waves and wave.challenge then
            local id = wave.challenge.route_id
            if not upcoming[id] then
                upcoming[id] = { waves = {}, challenge = wave.challenge }
                routeOrder[#routeOrder + 1] = id
            end
            upcoming[id].waves[#upcoming[id].waves + 1] = whole(index)
        end
    end
    for _, id in ipairs(routeOrder) do
        local entry = upcoming[id]
        local route = (run.config.expedition_routes or {})[id]
        scroll:AddChild(text("第" .. table.concat(entry.waves, "、") .. "波远征：" ..
            routeNames(run, P.RouteIds(route, entry.challenge)) .. " → 固定核心", C.text))
    end
    for _, snapshot in ipairs(P.Expeditions(run)) do
        if snapshot.stage ~= "DEAD" then
            scroll:AddChild(text(P.ExpeditionText(snapshot, false), C.text))
            local budgets = {}
            for _, id in ipairs(P.RouteIds(snapshot)) do
                local ledger = (snapshot.damage_ledger or {})[id]
                if ledger and snapshot.damage_mode ~= "core_budget" then budgets[#budgets + 1] = roomName(run, id) .. " " .. num(ledger.used) .. "/" .. num(ledger.cap) end
            end
            if #budgets > 0 then scroll:AddChild(text("各站实际承伤：" .. table.concat(budgets, " · "), C.dim, 10)) end
        end
    end
    if run.config.sanctuary_expansion then
        for _, ledger in pairs(run.room_core_damage) do
            scroll:AddChild(text(ledger.room_id .. " 核心损失 " .. num(ledger.used) .. "/" .. num(ledger.cap) .. " · 三队共享", C.warn))
        end
    end
    if #routeOrder > 0 then scroll:AddChild(text("沿线开门只开放通行；清空守军后才能领奖或布防。", C.dim, 10)) end
    if #(run.config.shortcuts or {}) > 0 then
        scroll:AddChild(text("玩家捷径", C.purple, 12))
        for _, shortcut in ipairs(run.config.shortcuts) do scroll:AddChild(text(shortcutText(run, shortcut), C.text)) end
        scroll:AddChild(text("捷径不改变远征必经站顺序。", C.dim, 10))
    end
    scroll:AddChild(text("房间 / 状态 / 布防", C.text, 13))
    local function deployment(id)
        local count, free = 0, 0
        for _, slot in ipairs(run.config.build_slots or {}) do
            if owner(slot) == id then
                count = count + 1
                local tower = towerAt(run, slot.id)
                if not tower or tower.hp <= 0 then free = free + 1 end
            end
        end
        return count > 0 and whole(aliveTowers(run, id)) .. "塔 · 空/损毁 " .. whole(free) .. "/" .. whole(count) .. "槽" or "无布防槽"
    end
    scroll:AddChild(text("主殿 · 固定防线 · " .. deployment("core"), C.text))
    for _, room in ipairs(run.rooms or {}) do
        local cleared = room.state == "cleared" or room.state == "claimed"
        local line = roomName(run, room.id) .. " · " .. roomState(run, room.id) .. "\n" .. deployment(room.id)
        if room.module_reward then line = line .. (room.reward_claimed and " · 模块奖励已领取" or " · 领奖可得模块") end
        scroll:AddChild(text(line, cleared and C.text or C.dim))
    end
    panel:AddChild(view:Button("返回", function() view:Action("close_map") end, "primary"))
end
local function expandable(parent, caption, build)
    local detail = UI.Panel { width = "100%", gap = 5, visible = false }
    local built = false
    local button = UI.Button { text = caption, height = 44, fontFamily = "pixel", fontSize = Theme.TextSize(10),
        variant = "secondary", onClick = function(self)
        local visible = not detail.props.visible
        if visible and not built then build(detail); built = true end
        detail:SetVisible(visible)
        local buttonSelf = self --[[@as Button]]
        buttonSelf:SetText(visible and "收起详情" or caption)
    end }
    parent:AddChild(button)
    parent:AddChild(detail)
end
function P.BuildTechnical(view)
    local run = view.run
    local scroll, panel = view:ModalShell("运行异常", "本局已停止，无法判定胜负；不会按普通失败结算。")
    scroll:AddChild(text("第" .. whole(run.wave_id) .. "波 · " .. P.Identity(run) .. "\n可重试当前场景或返回部署。", C.warn, 13))
    expandable(scroll, "查看异常详情", function(detail)
        local error = run.technical_error
        local reason = type(error) == "table" and (error.reason or error.message or error.kind) or error
        detail:AddChild(text(tostring(reason or run.end_reason or "暂未记录异常原因"), C.warn))
        detail:AddChild(text("场景 " .. P.Scenario(run) .. " · 规则 " .. tostring(run.rules_version or run.config.rules_version or run.config.version) ..
            "\n模拟时间 " .. num(run.clock) .. "秒 · 本局 " .. tostring(run.run_id), C.dim, 10))
        if type(error) == "table" then
            detail:AddChild(text("实体 " .. tostring(error.entity_id or "未知") .. " · 路点 " .. tostring(error.waypoint_index or error.waypoint or "未知") ..
                " · 恢复尝试 " .. whole(error.recovery_attempts or error.attempts), C.dim, 10))
        end
    end)
    panel:AddChild(row({ view:Button("重试当前场景", function() view:NewRun(run.total_waves, true) end, "primary"),
        view:Button("返回部署", function() view.menuOpen = true; view:Action("menu") end) }))
end
function P.AddReport(parent, report)
    local expansion = report.expansion
    if expansion and report.scenario_id == "sanctuary_expansion" then
        parent:AddChild(text("星砂收入 " .. whole(expansion.sand_earned) .. " · 余额 " .. whole(expansion.sand) ..
            "\n奖励探索时间获得 " .. num(expansion.exploration_seconds_earned) .. "秒 · 房内使用 " .. num(expansion.exploration_seconds_used) .. "秒", C.text))
        expandable(parent, "查看探索与核心预算", function(detail)
            for _, fact in ipairs(expansion.wave_reports or {}) do
                detail:AddChild(text("W" .. whole(fact.wave) .. " 战斗 " .. num(fact.combat_time) .. "/" .. num(fact.base_combat_time) ..
                    "秒 · 奖励 " .. num(fact.bonus) .. "秒 · 房内使用 " .. num(fact.exploration_used) .. "秒", C.dim))
                local destinations = {}; for id in pairs(fact.zone_visits or {}) do destinations[#destinations + 1] = id end
                table.sort(destinations)
                if #destinations > 0 then detail:AddChild(text("探索去向 " .. table.concat(destinations, " / "), C.dim)) end
            end
            for _, ledger in pairs(expansion.room_core_damage or {}) do
                detail:AddChild(text(ledger.room_id .. " 核心实际损失 " .. num(ledger.used) .. "/" .. num(ledger.cap), C.warn))
            end
        end)
    end
    local economy, totals = report.economy_totals, report.totals or {}
    if economy then
        parent:AddChild(text("资金支出 " .. num(economy.spend) .. " · 拆除返还 " .. num(economy.refund) ..
            ((economy.service_spend or 0) > 0 and " · 模块服务费 " .. num(economy.service_spend) .. "（不返）" or ""), Theme.Gold))
    end
    local output = totals.expedition_output
    if type(output) == "table" then
        local sum = 0
        for _, amount in pairs(output) do sum = sum + (tonumber(amount) or 0) end
        output = sum
    end
    if totals.expedition_output ~= nil then
        parent:AddChild(text("对远征实际有效输出 " .. num(output) .. " · 核心损失 " .. num(totals.core_damage), C.text))
    end
    local expeditions, defeated, remaining = report.expedition or {}, 0, 0
    for _, snapshot in ipairs(expeditions) do
        if snapshot.stage == "DEAD" then defeated = defeated + 1 else remaining = remaining + 1 end
    end
    if #expeditions > 0 then
        parent:AddChild(text("远征已击败 " .. whole(defeated) .. (remaining > 0 and " · 记录时存活 " .. whole(remaining) or ""), C.text))
    end
    if economy or next(totals.output_by_source or {}) or #expeditions > 0 then
        expandable(parent, "查看战报细节", function(detail)
            if economy then
                local actions = { build = "建造", upgrade = "升级", repair = "核心修复", heal = "角色治疗", module = "模块服务" }
                local costs = {}
                for _, action in ipairs({ "build", "upgrade", "repair", "heal", "module" }) do
                    local amount = (economy.by_action or {})[action]
                    if amount and amount > 0 then costs[#costs + 1] = actions[action] .. " " .. num(amount) end
                end
                if #costs > 0 then detail:AddChild(text(table.concat(costs, " · "), C.dim)) end
            end
            local sources = {}
            for id in pairs(totals.output_by_source or {}) do sources[#sources + 1] = tostring(id) end
            table.sort(sources)
            if #sources > 0 then detail:AddChild(text("按来源实际输出（已扣限伤与免伤）", C.dim)) end
            for _, id in ipairs(sources) do
                local amount = totals.output_by_source[id]
                if amount == nil then amount = totals.output_by_source[tonumber(id)] end
                detail:AddChild(text((id == "player" and "角色" or "设施 " .. id) .. "：" .. num(amount), C.dim))
            end
            for _, snapshot in ipairs(expeditions) do
                detail:AddChild(text("第" .. whole(snapshot.wave_id) .. "波 · " .. P.ExpeditionText(snapshot, true), C.text))
                local stations = {}
                for _, id in ipairs(P.RouteIds(snapshot)) do
                    local ledger = (snapshot.damage_ledger or {})[id]
                    if ledger and snapshot.damage_mode ~= "core_budget" then stations[#stations + 1] = id .. " " .. num(ledger.used) .. "/" .. num(ledger.cap) end
                end
                if #stations > 0 then detail:AddChild(text("各站实际承伤：" .. table.concat(stations, " · "), C.dim)) end
            end
        end)
    end
end
function P.ResultNote(run, win)
    if (run.pause_reasons or {}).technical or run.result == "UNDETERMINED" or run.result == "undetermined" then
        return "本局运行异常，未判定胜负；可重试当前场景。"
    end
    if not win then return "下次部署将重新分配本局资金、设施与模块。" end
    if P.Scenario(run) == "legacy_v02" and run.total_waves == 20 and run.can_record_chapter == true then
        return "首章防守完成！下一章地图尚未开放。"
    end
    if P.Scenario(run) == "legacy_v02" then return "5波教学完成；完整防守为20波。" end
    return P.Identity(run) .. "完成！本场景独立记录，不解锁经典防守的下一章。"
end
return P
