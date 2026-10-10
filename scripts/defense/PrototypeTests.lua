-- v0.3规则验收：只使用新建实例；不改实现、不写存档、不启动引擎/构建。
-- X01/R04使用原expedition移速、真实Map.Path/Move和模拟时钟，不传送/强杀证明巡行。
-- 数值边界夹具可设置HP/预算输入；这不代替路线与构筑平衡实战。
-- M04仅地图比例数据+NanoVG/组件调用记录桩；M05仅CPU数据/计时，不是FPS。
-- E01–E04明确NOT_RUN，日志不能代替真人理解、设备、画面或音效验收。
local P = {}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function fingerprint(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = fingerprint(key) .. "=" .. fingerprint(value[key]) end
    return "{" .. table.concat(parts, ";") .. "}"
end
-- 延迟加载：新依赖尚未合并时错误局限于实际执行的新case，不屏蔽诊断或假通过。
local function dependencies()
    return require("defense.Run"), require("defense.Combat"), require("defense.Scenarios"),
        require("defense.TowerModules"), require("defense.RoomGraph"), require("defense.Expedition")
end
---@return table
local function fresh(id, seed, config)
    local Run = require("defense.Run")
    local r = Run.New { scenario_id = id or "reuse_sample", seed = seed or 30307, config = config }
    r:FinishStory()
    r.player.attack_cd = 1000000
    return r
end
local function events(r, kind)
    local found = {}
    for _, event in ipairs(r.events) do if event.kind == kind then found[#found + 1] = event end end
    return found
end
---@return table
local function room(r, id)
    for _, item in ipairs(r.rooms) do if item.id == id then return item end end
    error("不存在的房间：" .. tostring(id))
end
---@return table
local function tower(r, id)
    for _, item in ipairs(r.towers) do if item.slot_id == id then return item end end
    error("不存在的设施：" .. tostring(id))
end
local function slot(r, owner)
    for _, item in ipairs(r.config.build_slots) do if item.owner_room_id == owner then return item end end
    error("不存在的槽位归属：" .. tostring(owner))
end
local function state(r)
    return fingerprint({ currency = r.currency, towers = r.towers, core = r.core, player = r.player,
        inventory = r.module_inventory, pending = r.pending_module_choices })
end
local function ownAll(r)
    for id in pairs(require("defense.TowerModules").Definitions) do r.module_inventory[id] = true end
end
local function logistics(t, r)
    t:Check(r:OpenLogistics(), "真实后勤入口成功")
    r.currency = 100000
end
---@return table
local function build(t, r, id, kind, request)
    t:Check(r:Transact("build", id, kind, request or ("建造:" .. id)).ok, "真实交易建造" .. id)
    return tower(r, id)
end
local function install(t, r, id, module, request)
    local result = r:Transact("module", id, module, request or ("安装:" .. id .. ":" .. module))
    t:Check(result.ok, "真实模块交易" .. module)
    return result
end
---@return table
local function spawn(t, r, unit)
    local e = require("defense.Combat").Spawn(r, unit)
    t:Check(type(e) == "table", "真实生成实体，不替换Combat.Spawn")
    return e --[[@as table]]
end
local function kill(t, r, e, source)
    t:Check(require("defense.Combat").DamageEnemy(r, e, e.hp + 1, source or "规则边界清理"), "真实伤害提交")
    t:Equal(e.alive, false, "以实体死亡判断，不以命中返回值判断")
end
-- 清房仅验证奖励/部署权限；坐标输入与强制守军清空明确不作为路线实战证据。
local function clearRoom(t, r, id)
    local Combat, G = require("defense.Combat"), require("defense.RoomGraph")
    local item = room(r, id)
    G.UpdateAccess(r)
    r.player.x, r.player.y = item.x, item.y
    Combat.UpdateRooms(r, 0)
    t:Equal(item.state, "active", "真实玩家进入激活守军")
    for _, e in ipairs(r.enemies) do if e.alive and e.room_id == id then kill(t, r, e) end end
    Combat.UpdateRooms(r, 0); G.UpdateAccess(r)
    t:Equal(item.state, "cleared", "真实守军清空后可部署")
    return item
end
local function dismiss(r)
    r:CloseModuleChoices()
    local iterations = 0
    while r.pause_reasons.upgrade do
        assert(r:ChooseUpgrade(r.options[1].id), "合法角色升级")
        iterations = iterations + 1; assert(iterations < 30, "升级选择有界")
    end
end
local function distance(a, b) return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2) end
-- 碰撞夹具：圆(r)沿每条Path边小步Move；门/柱为公共地图障碍。
-- 路段长度0合法；相邻房间不可跳点；r取角色/远征真实半径，切角须LOS合法。
local function walk(t, map, path, radius)
    t:Check(type(path) == "table" and #path >= 2, "真实路径存在")
    local x, y, length = path[1].x, path[1].y, 0
    t:Check(map:IsWalkable(x, y, radius), "路径起点全半径合法")
    for i = 2, #path do
        local target = path[i]
        local dx, dy = target.x - x, target.y - y
        local segment = math.sqrt(dx * dx + dy * dy)
        t:Check(map:LineOfSight(x, y, target.x, target.y, radius), "真实半径路径不穿墙")
        local sweptX, sweptY = map:Move(x, y, dx, dy, radius)
        t:Near(sweptX, target.x, "LOS合法整段圆胶囊Move必须精确到达X")
        t:Near(sweptY, target.y, "LOS合法整段圆胶囊Move必须精确到达Y")
        local steps = 0
        while (x - target.x)^2 + (y - target.y)^2 > 0.0000000001 do
            local rx, ry = target.x - x, target.y - y
            local remaining = math.sqrt(rx * rx + ry * ry)
            local step = math.min(0.05, remaining)
            local nx, ny = map:Move(x, y, rx / remaining * step, ry / remaining * step, radius)
            t:Check(map:IsWalkable(nx, ny, radius), "逐段实际移动仍全半径合法")
            t:Check(map:LineOfSight(x, y, nx, ny, radius), "逐步实际移动不穿墙")
            t:Check(math.sqrt((nx - x)^2 + (ny - y)^2) <= step + 0.00001, "移动不超过申请步长")
            x, y = nx, ny
            steps = steps + 1
            t:Check(steps <= math.ceil(segment / 0.05) + 200, "轴分离沿目标实际到达，不靠改坐标绕过卡路")
        end
        t:Near(x, target.x, "实际到达路点X"); t:Near(y, target.y, "实际到达路点Y")
        length = length + segment
    end
    return length
end
local function routeFor(r)
    for _, wave in ipairs(r.config.waves) do
        if wave.challenge then return r.config.expedition_routes[wave.challenge.route_id], wave.wave_id end
    end
    error("缺少考验路线")
end
local function expeditionSnapshot(r, e)
    for _, item in ipairs(require("defense.Expedition").Snapshot(r)) do
        if item.entity_id == e.entity_id then return item end
    end
    error("快照未包含远征实体")
end
-- 独立巡行夹具关闭玩家伤害和普通队列；不改原远征speed/半径/Move。
-- PREPARATION延长只隔离普通进攻/核心压力；远征仍由真实Run模拟步推进。
---@return table, table, table
local function routeFixture(t, id, config, seed)
    local r = fresh(id, seed, config)
    local route, waveId = routeFor(r)
    r.wave_id = waveId; r:EnterPreparation()
    t:Check(require("defense.RoomGraph").OpenChallenge(r), "按当前考验真实开门")
    r.preparation_remaining = 1000000
    r.player.x, r.player.y = r.config.recall_position.x, r.config.recall_position.y
    r.player.damage, r.player.attack_cd = 0, 1000000
    local e = spawn(t, r, { role = "expedition", portal = "S", route_id = route.route_id })
    t:Near(r.config.enemies.expedition.speed, r.config.enemies.commander.speed, "保持原统领真实移速")
    return r, e, route
end
local function advance(t, r, e, predicate, limit, observe)
    local iterations, elapsed = 0, 0
    while not predicate(e) do
        t:Check(not r.ended and not r.technical_error and not r:IsPaused(), "巡行运行条件合法，不强制解除异常暂停")
        local before = { x = e.x, y = e.y }
        local id, index, clock = e.entity_id, e.route_index, r.clock
        r:Update(0.05)
        iterations, elapsed = iterations + 1, elapsed + 0.05
        t:Equal(e.entity_id, id, "巡行实体身份不变")
        t:Check(e.route_index >= index and e.route_index <= index + 1, "站点不回退或跳过")
        t:Near(r.clock - clock, 0.05, "真实模拟时钟完整推进")
        t:Check(distance(before, e) <= r.config.enemies.expedition.speed * 0.05 + 0.00001, "真实速度位移，无跨房传送")
        t:Check(r.map:IsWalkable(e.x, e.y, e.radius), "实体完整半径合法")
        t:Check(r.map:LineOfSight(before.x, before.y, e.x, e.y, e.radius), "逐步移动无穿墙")
        t:Equal(e.room_id, nil, "远征不是守军")
        if observe then observe(e, elapsed) end
        t:Check(iterations <= (limit or 40000), "路线有界完成或明确失败，不无限卡路")
    end
    return elapsed
end
local function patrol(t, r, e, route, damageAtStop)
    local reached, seen = {}, {}
    local elapsed = advance(t, r, e, function(unit) return unit.stage == "FINAL_ASSAULT" end, 40000, function(unit)
        if unit.stage == "ROOM_ENGAGED" and not seen[unit.route_index] then
            local stop = route.stops[unit.route_index]
            t:Equal(r.map:RoomAt(unit.x, unit.y), stop.room_id, "物理到达预告站点")
            t:Check(distance(unit, stop.engage) <= 0.051, "真实到达交战点才开窗口")
            reached[#reached + 1] = stop.room_id; seen[unit.route_index] = true
            print(string.format("[原型巡行证据] 场景=%s 实体=%s 站=%s 时间=%.2f 坐标=(%.2f,%.2f) HP=%.2f",
                r.scenario_id, tostring(unit.entity_id), stop.room_id, r.clock, unit.x, unit.y, unit.hp))
            if damageAtStop then damageAtStop(r, unit, stop) end
        end
    end)
    t:Equal(#reached, #route.stops, "每个预告物理站点确实到达")
    for i, stop in ipairs(route.stops) do t:Equal(reached[i], stop.room_id, "真实站点顺序与预告一致") end
    for _, definition in ipairs(r.config.rooms) do
        if definition.challenge_target then t:Check(seen[(function()
            for i, stop in ipairs(route.stops) do if stop.room_id == definition.id then return i end end
        end)()], "每个challenge_target确实到达") end
    end
    t:Equal(#events(r, "EnemyDied"), 0, "巡行未假死")
    t:Equal(#events(r, "RoomRewardClaimed"), 0, "路过不自动发原房间奖励")
    t:Equal(#events(r, "BossSummoned"), 0, "主敌无额外召唤")
    print(string.format("[原型巡行证据] 场景=%s 实体=%s 总模拟秒=%.2f 终局HP=%.2f 玩家输出=%.2f 塔输出=%.2f 核心损失=%.2f",
        r.scenario_id, tostring(e.entity_id), elapsed, e.hp, r.totals.player_output, r.totals.tower_output, r.totals.core_damage))
    return reached, elapsed
end
local function budgetFixture(t, cap)
    local Scenarios = require("defense.Scenarios")
    local config = Scenarios.Get("reuse_sample")
    local route
    for _, item in pairs(config.expedition_routes) do route = item; break end
    route.room_caps[route.stops[1].room_id] = cap or 10
    local r, e, actualRoute = routeFixture(t, "reuse_sample", config)
    advance(t, r, e, function(unit) return unit.stage == "ROOM_ENGAGED" end, 10000)
    t:Equal(e.route_index, 1, "边界夹具真实走到首站")
    t:Equal(r.map:RoomAt(e.x, e.y), actualRoute.stops[1].room_id, "提交时物理站点合法")
    t:Check(e.hp > 100 and e.stage_elapsed < actualRoute.engage_duration - 1, "HP足够且计时未到，独立验证预算裁切")
    return r, e, actualRoute
end
local function damage(t, r, e, amount, source, expected)
    local before, n = e.hp, #events(r, "Hit")
    require("defense.Combat").DamageEnemy(r, e, amount, source)
    t:Near(before - e.hp, expected, "公共入口实际承伤")
    t:Equal(#events(r, "Hit") - n, expected > 0 and 1 or 0, "0伤害不伪造Hit")
    if expected > 0 then t:Near(events(r, "Hit")[n + 1].data.amount, expected, "Hit只统计actual") end
end
-- 组件与NanoVG边缘记录桩；真实View/ProtoView方法调用，非Yoga布局/设备/字体或音频证据。
local function presentation(body)
    local modules, globals, oldModules, oldGlobals, calls, widgets = {}, {}, {}, {}, {}, {}
    local widget = {}
    local ui = { Widget = widget, viewport = { w = 1280, h = 720 },
        Theme = { FontFace = function() return "记录桩字体" end } }
    local function record(name, ...) calls[#calls + 1] = { name = name, args = { ... } } end
    function widget:Init(props)
        self.props, self.children = {}, {}
        for key, value in pairs(props or {}) do if key ~= "children" then self.props[key] = value end end
        if self.props.visible == nil then self.props.visible = true end
        for _, child in ipairs(props and props.children or {}) do self:AddChild(child) end
        widgets[#widgets + 1] = self
        record("Widget.Init", self)
    end
    function widget:AddChild(child) self.children[#self.children + 1] = child; child.parent = self end
    function widget:GetNumChildren() return #self.children end
    function widget:GetChildAt(i) return self.children[i] end
    function widget:SetStyle(values)
        for key, value in pairs(values) do self.props[key] = value end
        record("Widget.SetStyle", self, values)
    end
    for _, field in ipairs({ "Text", "Disabled", "Visible", "Width", "Height", "Max", "Value" }) do
        local key = field:sub(1, 1):lower() .. field:sub(2)
        widget["Set" .. field] = function(self, value) self.props[key] = value; record("Widget.Set" .. field, self, value) end
    end
    function widget:GetLayout() return { x = 0, y = 0, w = ui.viewport.w, h = 88 } end -- 固定输入桩，非Yoga结果。
    function widget:GetAbsoluteLayout() return self:GetLayout() end
    function widget:Animate(options) record("Widget.Animate", self, options) end
    function widget:Destroy()
        for i = #self.children, 1, -1 do self.children[i]:Destroy() end
        if self.parent then
            for i, child in ipairs(self.parent.children) do if child == self then table.remove(self.parent.children, i); break end end
        end
        self.destroyed = true; record("Widget.Destroy", self)
    end
    local function make(props, class, kind)
        local w = setmetatable({ kind = kind or "Panel" }, { __index = class or widget })
        w:Init(props or {})
        return w
    end
    function widget:Extend(name)
        local class = {}
        return setmetatable(class, { __index = self, __call = function(_, props) return make(props, class, name) end })
    end
    for _, kind in ipairs({ "Label", "Panel", "Button", "SafeAreaView", "ScrollView", "Slider", "Checkbox" }) do
        ui[kind] = function(props) return make(props, widget, kind) end
    end
    ui.ProgressBar = widget:Extend("ProgressBar")
    ui.GetNVGContext = function() return nil end -- 无GPU上下文，真实Icon安全几何回退。
    ui.GetViewportSize = function() return ui.viewport.w, ui.viewport.h end
    ui.SetRoot = function(root, destroyOld) ui.root = root; record("UI.SetRoot", root, destroyOld) end
    ui.GetRoot = function() return ui.root end
    modules["urhox-libs/UI"] = ui
    modules["defense.Radar"], modules["defense.ProtoView"], modules["defense.View"] = false, false, false
    modules["defense.UIArt"], modules["defense.Theme"] = false, false -- 类绑定当前Widget，不复用另一夹具的类/闭包。
    for _, name in ipairs({ "nvgBeginPath", "nvgRect", "nvgRoundedRect", "nvgFillColor", "nvgFill", "nvgCircle", "nvgFontFace",
        "nvgFontSize", "nvgTextAlign", "nvgText", "nvgSave", "nvgRestore", "nvgIntersectScissor", "nvgMoveTo", "nvgLineTo",
        "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgClosePath" }) do
        globals[name] = function(...) record(name, ...) end
    end
    globals.nvgRGBA = function(...) return { ... } end
    globals.NVG_ALIGN_CENTER, globals.NVG_ALIGN_MIDDLE = 2, 16
    for name, value in pairs(modules) do
        oldModules[name] = { value = package.loaded[name] }
        if value == false then package.loaded[name] = nil else package.loaded[name] = value end
    end
    for name, value in pairs(globals) do oldGlobals[name] = { value = _G[name] }; _G[name] = value end
    local ok, message = pcall(body, calls, widgets, make, ui)
    for name, old in pairs(oldModules) do package.loaded[name] = old.value end
    for name, old in pairs(oldGlobals) do _G[name] = old.value end
    if not ok then error(message, 0) end
end
local function hasWidgetText(widgets, text)
    for _, w in ipairs(widgets) do if tostring(w.props.text or ""):find(text, 1, true) then return true end end
    return false
end
local function visibleWidgets(root)
    local result = {}
    local function visit(w)
        if w.destroyed or w.props.visible == false then return end
        result[#result + 1] = w
        for _, child in ipairs(w.children) do visit(child) end
    end
    visit(root); return result
end
local function click(t, button)
    t:Check(button and not button.destroyed and button.props.disabled ~= true and type(button.props.onClick) == "function", "记录树存在可用真实回调")
    button.props.onClick(button)
end
local function findButton(root, caption)
    for _, w in ipairs(visibleWidgets(root)) do
        if w.kind == "Button" and tostring(w.props.text):find(caption, 1, true) then return w end
    end
end
local function playerText(t, root, run)
    for _, w in ipairs(visibleWidgets(root)) do
        local text = tostring(w.props.text or w.props.label or "")
        for _, internal in ipairs({ "legacy_v02", "reuse_sample", "large_map_proto", "namespace", "owner_room_id", "rules_version",
            run.rules_version or "__no_version__", run.config.version or "__no_config_version__", run.record_namespace or "__no_namespace__" }) do
            t:Check(not text:find(internal, 1, true), "默认玩家展示不泄漏内部标识：" .. internal)
        end
    end
end
local function transaction(view, action, kind)
    for _, binding in ipairs(view.transactionButtons) do
        if binding.action == action and (kind == nil or binding.towerType == kind) then return binding end
    end
end

function P.Register(case)
    case("B01", function(t)
        local _, Combat, Scenarios, Modules = dependencies()
        local config = Scenarios.Get("reuse_sample")
        for _, def in pairs(config.enemies) do def.speed = 0 end -- 仅弹体行为夹具，不用于X01。
        local count = 0
        for id, definition in pairs(Modules.Definitions) do
            count = count + 1; t:Equal(definition.id, id, "定义ID-map稳定")
            t:Check(type(definition.name) == "string" and #definition.detail > 0, "卡面有名称与真实代价")
        end
        t:Equal(count, 6, "P01六个横向模块")
        for _, kind in ipairs({ "rapid", "slow", "area" }) do
            ---@type (string|boolean)[]
            local ids = { false }
            for id, def in pairs(Modules.Definitions) do if def.tower_type == kind then ids[#ids + 1] = id end end
            t:Equal(#ids, 3, "每类基础与两个分支")
            for _, module in ipairs(ids) do
                local r = fresh("reuse_sample", 30307, copy(config)); logistics(t, r); ownAll(r)
                local built = build(t, r, "T1", kind)
                t:Check(r:Transact("upgrade", "T1", nil, "升级1").ok, "第一次升级")
                t:Check(r:Transact("upgrade", "T1", nil, "升级2").ok, "第二次升级")
                r.player.skills.synergy = 2
                local base = Modules.Attributes(r, built, false)
                if module then install(t, r, "T1", module) end
                local before = state(r)
                local attrs = Modules.Attributes(r, built)
                for _ = 1, 4 do t:Equal(fingerprint(Modules.Attributes(r, built)), fingerprint(attrs), "模块应用一次，不累加") end
                t:Equal(state(r), before, "属性预览只读")
                if module then
                    local def = Modules.Definitions[module]
                    t:Near(attrs.damage, base.damage * (def.damage_multiplier or 1), "模块伤害源自有效基础")
                    t:Near(attrs.range, math.max(def.min_range or 0, base.range + (def.range_add or 0)), "模块范围与升级协同一致")
                    t:Near(attrs.splash, (base.splash + (def.splash_add or 0)) * (def.splash_multiplier or 1), "模块溅射真实半径")
                    t:Near(attrs.slow_amount, math.max(0, base.slow_amount + (def.slow_amount_add or 0)), "减速只修饰量，不私乘速度")
                end
                r:Resume("logistics")
                local a = spawn(t, r, { role = "elite", portal = "W", x = 30, y = 14 })
                local b = spawn(t, r, { role = "elite", portal = "W", x = 32, y = 14 })
                a.attack_cd, b.attack_cd = 100000, 100000
                Combat.Update(r, 0.01)
                t:Check(#r.projectiles > 0, "实际塔发射弹体")
                local bullet = r.projectiles[1]
                t:Near(bullet.damage, attrs.damage, "卡面伤害匹配真实弹体")
                t:Equal(bullet.pierce, attrs.pierce, "卡面穿透匹配弹体")
                t:Near(built.attack_cd, attrs.interval, "卡面间隔匹配真实冷却")
                if kind == "area" then t:Near(bullet.splash, attrs.splash, "真实范围弹体半径") end
                local hpA, hpB = a.hp, b.hp
                built.attack_cd = 100000; Combat.Update(r, 0.7)
                t:Near(hpA - a.hp, attrs.damage, "主目标真实命中一次")
                if module == "rapid_sweep" then t:Near(hpB - b.hp, attrs.damage, "真实额外穿透第二目标")
                elseif kind == "rapid" then t:Near(hpB - b.hp, 0, "基础速射不伪造穿透")
                elseif kind == "area" then
                    -- 溅射中心是实际弹体与首个圆碰撞点，不是首怪圆心。
                    local hitX = a.x - a.radius - bullet.radius
                    local separation = math.sqrt((hitX - b.x)^2 + (a.y - b.y)^2)
                    t:Near(hpB - b.hp, separation <= attrs.splash + b.radius and attrs.damage or 0, "密集目标按实际命中点溅射覆盖")
                end
                presentation(function(_, _, _)
                    local text = require("defense.ProtoView").AttributesText(attrs)
                    t:Check(text:find("伤害 " .. string.format("%.2f", attrs.damage), 1, true) ~= nil,
                        "展示有效伤害而非只改名称：" .. tostring(module) .. " " .. text .. " / " .. tostring(attrs.damage))
                end)
            end
        end
        local r = fresh("reuse_sample", 33, copy(config)); logistics(t, r); ownAll(r)
        local built = build(t, r, "T1", "rapid"); install(t, r, "T1", "rapid_focus"); r:Resume("logistics")
        spawn(t, r, { role = "advance", portal = "W", x = 27, y = 15 }) -- 更近普通不放在射线前方，避免真实遮弹误作策略失败。
        local elite = spawn(t, r, { role = "elite", portal = "W", x = 32, y = 14 })
        local same = spawn(t, r, { role = "elite", portal = "W", x = 32, y = 14 })
        Combat.Update(r, 0.01)
        local shot = events(r, "Shoot")[1]
        t:Near(shot.data.target_x, elite.x, "重点锁定优先精英而非近普通")
        built.attack_cd = 100000; Combat.Update(r, 0.4)
        t:Check(elite.hp < elite.max_hp and same.hp == same.max_hp, "同级同距按entity_id稳定命中")
    end)

    case("B02", function(t)
        local _, Combat, Scenarios, Modules = dependencies()
        for _, role in ipairs({ "elite", "commander", "expedition" }) do
            local cfg = Scenarios.Get("reuse_sample")
            for _, def in pairs(cfg.enemies) do def.speed = 0 end
            local r = fresh("reuse_sample", 72, cfg)
            logistics(t, r); ownAll(r)
            local a = build(t, r, "T1", "rapid")
            local s = build(t, r, "T2", "slow")
            local c = build(t, r, "T3", "area")
            install(t, r, "T2", "slow_anchor")
            r:Resume("logistics")
            -- 来源使用真实三座设施身份；光环真实输出由B01/R02独立验证。
            local route = routeFor(r)
            if role == "expedition" then r.wave_id = 5; r:EnterPreparation(); require("defense.RoomGraph").OpenChallenge(r) end
            local e = spawn(t, r, { role = role, portal = "S", route_id = role == "expedition" and route.route_id or nil, x = 32, y = 25 })
            local boss = role ~= "elite"
            local cap = r.config.reactions.slow_cap
            for _, spec in ipairs({ { a, 0.1, 3 }, { s, Modules.Attributes(r, s).slow_amount, 0.2 }, { c, 0.2, 2 } }) do
                t:Check(Combat.ApplySlow(r, e, spec[2], spec[3], "tower:" .. spec[1].entity_id), "公共三塔来源减速")
            end
            t:Check(Combat.ApplySlow(r, e, 0.9, 0.1, "frost:player"), "角色冷凝共享解析器")
            t:Near(e.slow_factor, 1 - cap * (boss and 0.5 or 1), "最强及上限，Boss半效")
            local n = 0; for _ in pairs(e.slow_effects) do n = n + 1 end
            t:Equal(n, 4, "异源四份独立状态")
            Combat.ApplySlow(r, e, 0.9, 0.3, "frost:player")
            local m = 0; for _ in pairs(e.slow_effects) do m = m + 1 end
            t:Equal(m, 4, "同源刷新不叠加")
            e.attack_cd, e.area_cd = 100000, 100000
            Combat.Update(r, 0.31)
            t:Near(e.slow_factor, 1 - 0.2 * (boss and 0.5 or 1), "强短源到期退为弱长源，不乘模块减速")
            Combat.Update(r, 1.8)
            t:Near(e.slow_factor, 1 - 0.1 * (boss and 0.5 or 1), "弱源各自到期")
        end
    end)

    case("B03", function(t)
        local _, _, _, Modules = dependencies()
        local r = fresh(); local item = clearRoom(t, r, "A1")
        local gold, xp = r.currency, r.player.experience
        local controlConfig = require("defense.Scenarios").Get("reuse_sample")
        controlConfig.module_system = false
        local control = fresh("reuse_sample", r.seed, controlConfig)
        local controlRoom = clearRoom(t, control, "A1")
        t:Check(control:ClaimRoom(controlRoom.id, "对照领奖"), "同输入无模块对照正常领奖")
        t:Check(r:ClaimRoom(item.id, "首次领奖"), "真实首次领奖")
        t:Equal(r.currency, gold + 40, "金币一次")
        t:Check(r.player.experience >= xp, "经验发放真实事件")
        t:Equal(#events(r, "ExperienceGranted"), 1, "经验请求只一次")
        t:Equal(fingerprint(r.rng), fingerprint(control.rng), "模块独立随机流不扰动同输入角色升级/战斗RNG")
        t:Equal(#r.pending_module_choices, 1, "模块机会一次")
        local choice = r.pending_module_choices[1]; local seen = {}
        t:Equal(choice.id, choice.choice_id, "兼容选择ID")
        t:Equal(#choice.candidates, 3, "未拥有足量候选三选一")
        for i, id in ipairs(choice.candidates) do
            t:Check(Modules.Definitions[id] and not r.module_inventory[id] and not seen[id], "候选合法无重复")
            t:Equal(choice.options[i].id, id, "卡面与候选对应"); seen[id] = true
        end
        t:Check(r:CloseModuleChoices(), "关闭保留待选")
        t:Check(r.pause_reasons.upgrade, "关闭模块不覆盖角色升级暂停")
        dismiss(r)
        local before = fingerprint({ r.currency, r.player, r.pending_module_choices, r.module_rng })
        r:ClaimRoom(item.id, "重复领奖"); Modules.Offer(r, item)
        t:Equal(fingerprint({ r.currency, r.player, r.pending_module_choices, r.module_rng }), before, "重复claim/Offer不重抽或再发奖")
        t:Check(r:OpenModuleChoices(choice.choice_id), "重新打开同机会")
        t:Equal(r:ChooseModule(choice.choice_id, "非法模块", "非法选择").ok, false, "非法候选拒绝")
        local result = r:ChooseModule(choice.choice_id, choice.candidates[1], "选择1")
        t:Check(result.ok and r.module_inventory[choice.candidates[1]], "选择实际进入本局库存")
        local after = fingerprint(Modules.Snapshot(r))
        t:Equal(r:ChooseModule(choice.choice_id, choice.candidates[1], "选择1"), result, "成功选择重放原结果")
        t:Equal(r:ChooseModule(choice.choice_id, choice.candidates[1], "选择2").ok, false, "已消费机会不能再选")
        t:Equal(fingerprint(Modules.Snapshot(r)), after, "重复选择不改库存/随机")
        t:Equal(#events(r, "ModuleChosen"), 1, "选择事件一次")
        for _, remaining in ipairs({ 2, 0 }) do
            local q = fresh(); local target = clearRoom(t, q, "A1"); ownAll(q)
            local ids = {}; for id in pairs(Modules.Definitions) do ids[#ids + 1] = id end; table.sort(ids)
            for i = 1, remaining do q.module_inventory[ids[i]] = nil end
            t:Check(q:ClaimRoom(target.id, "满库存:" .. remaining), "少候选/满库存仍领金币经验")
            local pending = q.pending_module_choices[1]
            t:Equal(pending and #pending.candidates or 0, remaining, "不足三项显示真实数量；无合法项不伪造")
            t:Equal(q.currency, q.config.currency + 40, "原金币不被模块库存吞掉")
        end
        local nextRun = fresh("reuse_sample", r.seed)
        t:Equal(next(nextRun.module_inventory), nil, "重试无旧库存")
        t:Equal(#nextRun.pending_module_choices, 0, "重试无旧机会")
        t:Equal(next(nextRun.room_module_claims), nil, "重试房间机会账本清空")
    end)

    case("B04", function(t)
        local r = fresh(); logistics(t, r); ownAll(r)
        local built = build(t, r, "T1", "rapid")
        r:Transact("upgrade", "T1", nil, "升级")
        built.hp, built.attack_cd = built.hp - 9, 0.43
        local hp, cd, level, gold = built.hp, built.attack_cd, built.upgrade_count, r.currency
        local first = install(t, r, "T1", "rapid_focus", "免费安装")
        t:Near(r.currency, gold, "首次0费用")
        t:Equal(first.price, 0, "交易展示免费")
        for _, spec in ipairs({ { "BAD", "rapid_sweep", "非法槽" }, { "T1", "BAD", "非法模块" },
            { "T1", "area_focus", "不匹配" }, { "T2", "rapid_sweep", "空槽" } }) do
            local before = state(r)
            t:Equal(r:Transact("module", spec[1], spec[2], spec[3]).ok, false, "非法安装拒绝")
            t:Equal(state(r), before, "失败无资金/塔变化")
        end
        r.currency = 19; local before = state(r)
        t:Equal(r:Transact("module", "T1", "rapid_sweep", "费用不足").ok, false, "更换资金不足拒绝")
        t:Equal(state(r), before, "资金不足无副作用")
        r.currency = 100
        r.state = "ATTACK"; before = state(r)
        t:Equal(r:Transact("module", "T1", "rapid_sweep", "战斗非法").ok, false, "战斗期拒绝")
        t:Equal(state(r), before, "战斗非法无副作用"); r.state = "PREPARATION"
        local changed = install(t, r, "T1", "rapid_sweep", "更换成功")
        t:Equal(changed.price, 20, "服务费20"); t:Equal(r.currency, 80, "只扣一次20")
        t:Near(built.hp, hp, "更换保留受损HP"); t:Near(built.attack_cd, cd, "更换保留冷却")
        t:Equal(built.upgrade_count, level, "更换不抹升级")
        before = state(r)
        t:Equal(r:Transact("module", "BAD", "BAD", "更换成功"), changed, "重复request_id返回原结果")
        t:Equal(state(r), before, "成功重放不二次扣费")
        t:Equal(#events(r, "ModuleInstalled"), 1, "免费安装事件唯一")
        t:Equal(#events(r, "ModuleChanged"), 1, "更换事件唯一")
    end)

    case("B05", function(t)
        local r = fresh(); logistics(t, r); ownAll(r)
        local built = build(t, r, "T1", "rapid")
        r:Transact("upgrade", "T1", nil, "升级"); install(t, r, "T1", "rapid_focus")
        install(t, r, "T1", "rapid_sweep")
        t:Equal(built.total_spend, built.build_spend + built.upgrade_spend, "total_spend仅build+upgrade")
        t:Equal(built.service_spend, 20, "服务成本独立账本")
        local gold = r.currency
        local result = r:Transact("demolish", "T1", nil, "拆除")
        t:Equal(result.refund, math.floor((r.config.towers.rapid.cost + r.config.towers.rapid.upgrade) * 0.5), "服务费不进入返款")
        t:Equal(r.currency, gold + result.refund, "返款实际一次入账")
        r:Transact("demolish", "T1", nil, "拆除"); t:Equal(r.currency, gold + result.refund, "无服务费套利")
        built = build(t, r, "T1", "rapid", "受损建造"); built.hp = built.hp - 1
        t:Equal(r:Transact("demolish", "T1", nil, "受损拆除").refund, 0, "受损旧规则返0")
        for _, item in ipairs(r.rooms) do item.state = "cleared" end -- 容量边界夹具，清房真实流程另验。
        local slots = r.config.build_slots
        t:Check(#slots >= 7, "槽位数量与存活上限分离")
        for i = 1, 6 do build(t, r, slots[i].id, "rapid", "上限:" .. i) end
        local before = state(r)
        t:Equal(r:Transact("build", slots[7].id, "rapid", "第七塔").ok, false, "全局alive<=6")
        t:Equal(state(r), before, "超上限拒绝不扣钱")
        local dead = tower(r, slots[1].id)
        r:Resume("logistics")
        t:Check(require("defense.Combat").Damage(r, dead, dead.hp + 1, { source = "death_explosion", source_id = "夹具" }), "公共伤害真实摧毁塔")
        logistics(t, r)
        build(t, r, slots[7].id, "rapid", "释放后建造")
        t:Equal(r:Transact("build", slots[1].id, "rapid", "无空名额重建").ok, false, "重建仍需全局名额")
        r:Transact("demolish", slots[2].id, nil, "释放名额")
        build(t, r, slots[1].id, "rapid", "合法重建")
        t:Check(r.module_inventory.rapid_focus, "模块不随塔摧毁消耗")
    end)

    case("M01", function(t)
        local _, _, Scenarios, _, Graph = dependencies()
        for _, id in ipairs({ "reuse_sample", "large_map_proto" }) do
            local cfg = Scenarios.Get(id); local r = fresh(id, 19, cfg)
            for _, radius in ipairs({ cfg.player.radius, cfg.enemies.expedition.radius }) do
                local before = fingerprint({ cfg, r.map.locked })
                local ok, report = Graph.Check(cfg, r.map, radius)
                t:Check(ok, "房间图真实几何校验：" .. fingerprint(report.errors))
                t:Equal(fingerprint({ cfg, r.map.locked }), before, "Check不打开运行态门或改配置")
                for _, item in ipairs(cfg.rooms) do r.map:SetUnlocked(item.id, true) end
                local nodes = {}; for _, node in ipairs(cfg.room_graph.nodes) do nodes[node.id] = node end
                for _, point in ipairs({ cfg.recall_position, cfg.player_spawn, cfg.core_position }) do
                    walk(t, r.map, r.map:Path(cfg.core_position.x, cfg.core_position.y, point.x, point.y, radius), radius)
                end
                for _, item in ipairs(cfg.rooms) do
                    walk(t, r.map, r.map:Path(cfg.core_position.x, cfg.core_position.y, item.x, item.y, radius), radius)
                end
                for _, edge in ipairs(cfg.room_graph.edges) do
                    if edge.shortcut then r.map:SetUnlocked(edge.gate_id, true) end
                    local last, length = nodes[edge.from], 0
                    local points = copy(edge.waypoints or {}); points[#points + 1] = nodes[edge.to]
                    for _, point in ipairs(points) do
                        length = length + walk(t, r.map, r.map:Path(last.x, last.y, point.x, point.y, radius), radius)
                        last = point
                    end
                    t:Near(length, report.edge_lengths[edge.id], "配置图边与实际逐段路径对应")
                    if edge.shortcut then r.map:SetUnlocked(edge.gate_id, false) end
                end
            end
        end
    end)

    case("M02", function(t)
        local _, _, Scenarios, _, Graph = dependencies()
        local orders = { { "A1", "A2", "A3", "B1", "B2", "B3", "C1", "C2", "C3" },
            { "B1", "B2", "B3", "C1", "C2", "C3", "A1", "A2", "A3" },
            { "C1", "A1", "B1", "A2", "C2", "B2", "A3", "C3", "B3" } }
        local traces = {}
        for index, order in ipairs(orders) do
            local r = fresh("large_map_proto", 88)
            local current, length, reward = copy(r.config.core_position), 0, 0
            traces[index] = {}
            for _, id in ipairs(order) do
                t:Check(Graph.UpdateAccess(r), "依赖解锁正常")
                local item = room(r, id)
                t:Check(item.accessible and r.map:IsWalkable(item.x, item.y, r.player.radius), "探索顺序依赖合法")
                length = length + walk(t, r.map, r.map:Path(current.x, current.y, item.x, item.y, r.player.radius), r.player.radius)
                -- 移动已逐段实测，状态输入仅隔离守军耗时，不能宣称真实探索平衡。
                item.state = "cleared"; Graph.UpdateAccess(r)
                reward = reward + (item.tier == 1 and 40 or 80)
                traces[index][#traces[index] + 1] = { room_id = id, cumulative_path = length, potential_gold = reward }
                current = item
            end
            print("[探索顺序CPU证据] 顺序=" .. index .. " " .. fingerprint(traces[index]))
        end
        t:Check(fingerprint(traces[1]) ~= fingerprint(traces[2]) and fingerprint(traces[2]) ~= fingerprint(traces[3]), "至少三种探索行程/中间收益不同")
        local r = fresh("large_map_proto"); for _, item in ipairs(r.rooms) do item.state = "cleared"; r.map:SetUnlocked(item.id, true) end
        -- 全部清房后条件同步先完成，再独立比较单个捷径开/关，避免把其他解锁收益当捷径。
        t:Check(Graph.UpdateAccess(r), "全部清房通行条件先同步")
        local shorter = false
        for _, shortcut in ipairs(r.config.shortcuts) do
            local nodes = {}; for _, node in ipairs(r.config.room_graph.nodes) do nodes[node.id] = node end
            local a, b = nodes[shortcut.from], nodes[shortcut.to]
            r.map:SetUnlocked(shortcut.gate_id, false)
            local before = walk(t, r.map, r.map:Path(a.x, a.y, b.x, b.y, r.player.radius), r.player.radius)
            t:Check(Graph.UpdateAccess(r), "真实条件打开捷径")
            local after = walk(t, r.map, r.map:Path(a.x, a.y, b.x, b.y, r.player.radius), r.player.radius)
            shorter = shorter or after < before - 0.01
            print(string.format("[捷径CPU证据] %s 关闭路径=%.2f 开放路径=%.2f", shortcut.id, before, after))
        end
        t:Check(shorter, "至少一条合法路径确实缩短")
        local bad = Scenarios.Get("large_map_proto"); bad.rooms[1].prerequisite = bad.rooms[2].id
        local ok, report = Graph.Check(bad)
        t:Equal(ok, false, "循环依赖负例被拒绝")
        t:Check(fingerprint(report.errors):find("cycle", 1, true) ~= nil, "拒绝理由为循环而非偶然异常")
        local estimate = Graph.EstimateReturn(r)
        t:Check(estimate.reachable and #estimate.path >= 2, "回防估时基于实际路径")
        t:Near(estimate.path_length, walk(t, r.map, estimate.path, r.player.radius), "回防长度与路径一致")
        t:Near(estimate.seconds, estimate.path_length / estimate.effective_speed, "有效移速估时")
        t:Near(estimate.margin, estimate.remaining - estimate.seconds, "剩余时间差")
        r.player.slow_factor = 0.5
        t:Near(Graph.EstimateReturn(r).seconds, estimate.seconds * 2, "减速反映回防时间")
        r.player.x, r.player.y = -999, -999
        local blocked = Graph.EstimateReturn(r)
        t:Check(not blocked.reachable and not blocked.can_return and #blocked.reason > 0, "不可达不能保证来得及")
    end)

    case("M03", function(t)
        local _, Combat, _, _, Graph = dependencies()
        local r = fresh("large_map_proto"); local route, waveId = routeFor(r)
        local locked
        for _, stop in ipairs(route.stops) do if r.map.locked[stop.room_id] then locked = room(r, stop.room_id); break end end
        t:Check(locked ~= nil, "沿线有未解锁未清房间")
        local target = locked --[[@as table]]
        t:Equal(target.state, "unvisited", "开门前未清")
        t:Equal(r.map:IsWalkable(target.x, target.y, r.player.radius), false, "物理锁实际拒绝通行")
        r.map:Path(r.core.x, r.core.y, r.config.portals.W.x, r.config.portals.W.y, r.player.radius)
        local revision, grids, fields = r.map.revision, r.map.grids, r.map.fields
        r.wave_id = waveId; r:EnterPreparation()
        local before = fingerprint({ r.currency, r.player.experience, r.module_inventory, r.rooms })
        t:Check(Graph.OpenChallenge(r), "考验真实开沿线门")
        t:Check(r.map.revision > revision, "开门revision变化")
        t:Check(r.map.grids ~= grids and r.map.fields ~= fields, "网格/路径缓存失效")
        t:Check(target.accessible and target.challenge_gate_open and r.map:IsWalkable(target.x, target.y, r.player.radius), "协议与物理门一致")
        t:Equal(target.state, "unvisited", "开门不清守军")
        t:Equal(target.reward_claimed, false, "开门不领奖")
        t:Check(#events(r, "GateOpened") > 0, "实际开门事件")
        t:Check(before ~= fingerprint(r.rooms), "仅通行字段真实变化")
        local after = fingerprint({ r.currency, r.player.experience, r.module_inventory, r.rooms })
        local count = #events(r, "GateOpened")
        t:Check(Graph.OpenChallenge(r), "重复开门幂等")
        t:Equal(fingerprint({ r.currency, r.player.experience, r.module_inventory, r.rooms }), after, "重复考验不变奖励/房态")
        t:Equal(#events(r, "GateOpened"), count, "重复开门无二次事件")
        logistics(t, r)
        local beforeMoney = r.currency
        t:Equal(r:Transact("build", slot(r, target.id).id, "rapid", "未清建造").ok, false, "门开未清仍不能部署")
        t:Equal(r.currency, beforeMoney, "未清拒绝不扣钱")
        r:Resume("logistics")
        walk(t, r.map, r.map:Path(r.player.x, r.player.y, target.x, target.y, r.player.radius), r.player.radius)
        r.player.x, r.player.y = target.x, target.y -- 路径移动已上面验证；这里只输入最终玩家空间给生命周期。
        Combat.UpdateRooms(r, 0)
        t:Equal(target.state, "active", "玩家进入真实激活守军")
        t:Check(#target.guard_ids > 0, "真守军生成")
        t:Equal(target.reward_claimed, false, "守军激活不自动领奖")
        print("[M03证据边界] 正常门/缓存/守军规则已执行；坏门技术异常另由X07与后续协商覆盖")
    end)

    case("M04", function(t)
        local _, _, Scenarios = dependencies()
        presentation(function(calls, widgets, make)
            local Radar, View = require("defense.Radar"), require("defense.ProtoView")
            for _, id in ipairs({ "reuse_sample", "large_map_proto" }) do
                local r = fresh(id)
                local configs = { r.config, Scenarios.Get(id) }
                configs[2].map_origin = { x = -100, y = -80 }; configs[2].map_size = { w = 240, h = 180 }
                for _, config in ipairs(configs) do
                    r.config = config
                    for _, layout in ipairs({ { x = 12, y = 18, w = 320, h = 220 }, { x = 2, y = 8, w = 220, h = 310 } }) do
                        local radar = setmetatable({ run = r, GetAbsoluteLayout = function() return layout end,
                            RenderFullBackground = function() end }, { __index = Radar })
                        local start, before = #calls, state(r)
                        radar:Render({})
                        t:Equal(state(r), before, "雷达记录桩渲染只读规则")
                        local dots = {}; for i = start + 1, #calls do if calls[i].name == "nvgCircle" then dots[#dots + 1] = calls[i] end end
                        t:Check(#dots >= 2, "真实Radar方法生成标记")
                        local scale = math.min((layout.w - 12) / config.map_size.w, (layout.h - 12) / config.map_size.h)
                        local ox = layout.x + (layout.w - config.map_size.w * scale) / 2
                        local oy = layout.y + (layout.h - config.map_size.h * scale) / 2
                        local origin = config.map_origin or { x = 0, y = 0 }
                        local core, player = dots[#dots - 1].args, dots[#dots].args
                        t:Near(core[2], ox + (r.core.x - origin.x) * scale, "核心标记读取宽/原点")
                        t:Near(core[3], oy + (r.core.y - origin.y) * scale, "核心标记读取高/原点")
                        t:Near(player[2], ox + (r.player.x - origin.x) * scale, "玩家标记比例无漂移")
                    end
                end
                local view = { run = r, modalLabels = {}, transactionButtons = {}, latestNotice = "" }
                function view:ModalShell(title, subtitle)
                    local scroll, panel = make({}), make({})
                    panel:AddChild(make({ text = title })); scroll:AddChild(make({ text = subtitle }))
                    return scroll, panel
                end
                function view:Button(text, callback) return make({ text = text, onClick = callback }) end
                function view:TransactionButton(action, selectedSlot, kind, caption)
                    local button = self:Button(caption, function() end)
                    self.transactionButtons[#self.transactionButtons + 1] = { action = action, slot = selectedSlot,
                        towerType = kind, caption = caption, button = button, reason = make({}) }
                    return button
                end
                View.BuildMap(view); View.BuildModules(view); View.BuildLogistics(view)
                t:Check(hasWidgetText(widgets, "未清不可建造") and hasWidgetText(widgets, "房间地图"), "房态/地图信息可在组件树访问")
                t:Check(hasWidgetText(widgets, "仅战备期可操作") and hasWidgetText(widgets, "模块待选"), "空槽后勤展示权限与模块入口；服务费仅在已建造槽展示")
                t:Check(hasWidgetText(widgets, "核心"), "核心信息未因扩展房间移除")
                View.AddReport(make({}), { scenario_id = id, totals = { expedition_output = { player = 8, ["设施身份"] = 2 } } })
                t:Check(hasWidgetText(widgets, "对远征实际有效输出 10.00"), "按来源输出表实际求和展示10.00，不把table转数字变0")
            end
        end)
        print("[M04证据边界] 桌面/竖屏只验比例数据与组件/NanoVG调用桩；不验Yoga布局、可见遮挡、真实触控或引擎截图")
    end)

    case("UI01", function(t)
        require("defense.UIArtTests").ViewFixtureIsolation(t, presentation)
        presentation(function(calls, _, _, ui)
            local View, Modules = require("defense.View"), require("defense.TowerModules")
            local actions, starts = {}, {}
            local view = View.New(fresh("legacy_v02"), {
                action = function(kind, payload) actions[#actions + 1] = { kind = kind, payload = payload } end,
                newRun = function(total, build, retry, id) starts[#starts + 1] = { total = total, build = build, retry = retry, id = id } end,
            })
            t:Equal(ui.GetRoot(), view.root, "真实View.New挂载根树")
            t:Equal(view:Mode(), "menu", "初始化进入部署菜单")
            local ArtTests = require("defense.UIArtTests")
            ArtTests.ViewPixel(t, view)
            local function checkMenu(id, total)
                local buttons, begin = 0, 0
                for _, w in ipairs(visibleWidgets(view.overlay)) do
                    if w.kind == "Button" then
                        if w.props.text == "经典防守" or w.props.text == "三房间考验" or w.props.text == "外圈远征" or w.props.text == "神殿扩展" then buttons = buttons + 1 end
                        if w.props.text:find("开始防守", 1, true) then begin = begin + 1 end
                    end
                end
                t:Equal(buttons, 4, "菜单恰有当前四种场景选择，包含神殿扩展")
                t:Equal(begin, 1, "菜单只有一个当前开始，不铺开三组开始按钮")
                t:Equal(view.selectedScenario, id, "当前场景选择保持")
                click(t, findButton(view.overlay, "开始防守"))
                t:Equal(starts[#starts].id, id, "真正开始回调传当前场景")
                t:Equal(starts[#starts].total, total, "开始回调传真实波数")
                view.menuOpen, view.modeKey = true, "__dirty"; view:Update(0)
                playerText(t, view.root, view.run)
            end
            click(t, findButton(view.overlay, "教学 · 5波")); view:Update(0)
            checkMenu("legacy_v02", 5)
            for _, item in ipairs({ { "三房间考验", "reuse_sample", 5 }, { "外圈远征", "large_map_proto", 20 }, { "神殿扩展", "sanctuary_expansion", 20 }, { "经典防守", "legacy_v02", 5 } }) do
                local before = #starts
                click(t, findButton(view.overlay, item[1])); view:Update(0)
                t:Equal(#starts, before, "切场景不提前开局")
                checkMenu(item[2], item[3])
            end
            for _, size in ipairs({ { w = 390, h = 844 }, { w = 1280, h = 720 } }) do
                ui.viewport = size
                for _, mode in ipairs({ "", "menu", "pause", "rules", "recap", "logistics", "map", "story:", "upgrade:", "moduleChoice:", "result", "technical" }) do
                    local r = fresh("reuse_sample")
                    if mode == "pause" then r:Pause("manual")
                    elseif mode == "rules" or mode == "recap" or mode == "map" then r:Pause(mode)
                    elseif mode == "logistics" then t:Check(r:OpenLogistics(), "真实后勤暂停")
                    elseif mode == "story:" then r = require("defense.Run").New { scenario_id = "reuse_sample", seed = 91 }
                    elseif mode == "upgrade:" then r:GrantExperience(100); r:CheckUpgrade()
                    elseif mode == "moduleChoice:" then
                        local source = room(r, "A1"); source.reward_claimed = true
                        Modules.Offer(r, source) -- 奖励已领的输入边界；不冒充玩家探索体验。
                    elseif mode == "result" then r.core.hp = 0; r:Update(0.05)
                    elseif mode == "technical" then r.technical_error = { reason = "验证夹具路径不可达" }; r:Pause("technical") end
                    view:SetRun(r); view.menuOpen = mode == "menu"
                    local before = state(r)
                    local pauseBefore = fingerprint(r.pause_reasons)
                    view:Update(0); view:UpdateHUD()
                    t:Equal(state(r), before, "真实UI构建/刷新不改规则实体")
                    t:Equal(fingerprint(r.pause_reasons), pauseBefore, "真实UI构建/刷新不改暂停原因集合")
                    t:Equal(mode == "" and view:Mode() or view:Mode():sub(1, #mode), mode, "真实Mode覆盖" .. mode)
                    t:Equal(view.overlay.props.top, 0, "模态遮罩从top0覆盖，不留HUD缺口")
                    t:Equal(view.overlay.props.visible, mode ~= "", "模态层可见性与模式一致")
                    t:Equal(view.top.props.visible, mode == "", "modal时顶HUD隐藏")
                    t:Equal(view.bottom.props.visible, mode == "", "modal时底HUD隐藏")
                    t:Equal(view.alerts.props.visible, mode == "", "modal时告警层隐藏")
                    t:Equal(view.radarPanel.props.visible, mode == "" and size.w >= 560, "窄屏隐藏小地图，保留地图入口")
                    if mode ~= "" then
                        t:Check(view.overlayContent ~= nil, "每种模式调用真实ModalShell")
                        t:Equal(view.overlayContent.props.height, size.w < 660 and "100%" or "92%", "窄/宽模态高度属性真实选择")
                        if mode == "upgrade:" then
                            local count = 0
                            for _, w in ipairs(visibleWidgets(view.overlay)) do
                                if w.kind == "Button" and w.props.text == "选择" then
                                    count = count + 1
                                    t:Equal(w.parent.props.width, size.w >= 800 and "auto" or "100%", "成长宽屏横排/窄屏满宽属性")
                                end
                            end
                            t:Equal(count, #r.options, "成长没有丢失真实候选")
                        end
                    else
                        t:Equal(view.buttons.recall.props.visible, false, "主殿未满足回城条件不常驻按钮")
                        local source = room(r, "A1"); source.state = "cleared"
                        r.player.x, r.player.y = source.x, source.y; view:UpdateHUD()
                        t:Check(view.buttons.recall.props.visible and not view.buttons.recall.props.disabled, "合法已清房间显示可用回城入口")
                        click(t, view.buttons.recall); t:Equal(actions[#actions].kind, "recall", "回城入口真实回调")
                        click(t, view.buttons.map); t:Equal(actions[#actions].kind, "map", "地图按钮真实入口")
                        click(t, view.buttons.active); t:Equal(actions[#actions].kind, "active", "击退能力真实入口")
                        r.core.hp = r.core.max_hp * 0.2; view:UpdateHUD()
                        t:Check(view.labels.coreAlarm.props.visible and view.labels.coreAlarm.props.text:find("30%", 1, true), "核心低耐久告警保留")
                        r.player.active_cd = 3.2; view:UpdateHUD()
                        t:Check(view.buttons.active.props.disabled and view.buttons.active.props.text:find("4秒", 1, true), "能力实际冷却与权限保留")
                    end
                    playerText(t, view.root, r)
                    ArtTests.ViewPixel(t, view)
                    if mode == "moduleChoice:" then
                        local choiceBefore = fingerprint(r.pending_module_choices)
                        local id = r.module_choice_id
                        r:Pause("manual")
                        local count = #r.pending_module_choices
                        t:Check(r:CloseModuleChoices(), "关闭模块使用真实Run接口")
                        view:Update(0)
                        t:Equal(view:Mode(), "pause", "关闭模块保留手动暂停面板")
                        t:Equal(#r.pending_module_choices, count, "关闭模块保留待选机会")
                        t:Check(r:OpenModuleChoices(id), "重新打开保留机会")
                        view:Update(0)
                        t:Equal(fingerprint(r.pending_module_choices), choiceBefore, "开关模块不重抽候选")
                        t:Check(r.pause_reasons.manual and r.pause_reasons.module_choice, "模块只管理自身暂停原因")
                    end
                end
            end
            local mounted, destroyed = 0, 0
            for _, call in ipairs(calls) do
                if call.name == "UI.SetRoot" then mounted = mounted + 1 end
                if call.name == "Widget.Destroy" then destroyed = destroyed + 1 end
            end
            t:Check(mounted > 0 and destroyed > 0, "记录真实挂载与切模式销毁调用")
            ArtTests.ViewCurrentFields(t, view, ui, fresh)
            ArtTests.ViewCancelLifecycle(t, view, ui, calls)
            t:Equal(ui.GetRoot(), nil, "Destroy卸载当前根树")
            t:Check(view.root.destroyed, "Destroy调用根控件销毁")
        end)
        print("[UI01证据边界] 390x844/1280x720为UI viewport输入；真实View方法+记录树，不是Yoga像素布局或真机验收")
    end)

    case("S14_EXPANSION_UI", function(t)
        presentation(function(_, widgets)
            local View, Proto = require("defense.View"), require("defense.ProtoView")
            local r=fresh("sanctuary_expansion"); logistics(t,r); r.exploration_currency=100
            local serial=0
            local view=View.New(r,{action=function(kind,payload)
                if kind=="transaction" then serial=serial+1; t:Check(r:Transact(payload.action,payload.slot,payload.type,"newUI"..serial).ok,"新界面真实交易") end
            end})
            view.menuOpen=false; view:Update(0)
            local function refresh() view:Events(r.events); view:Update(0); view:Update(0) end
            t:Check(hasWidgetText(visibleWidgets(view.root),"星砂"),"后勤星砂信息")
            t:Equal(#view.transactionButtons,10,"八建造加修复治疗")
            for _,kind in ipairs(r.config.facility_order) do t:Check(transaction(view,"build",kind)~=nil,"可操作设施"..kind) end
            click(t,findButton(view.root,"预览 维修站")); refresh()
            t:Check(hasWidgetText(visibleWidgets(view.root),"每次维修"),"预览支援实际属性")
            t:Check(hasWidgetText(visibleWidgets(view.root),"最大距离"),"覆盖边界说明")
            click(t,transaction(view,"build","rapid").button); refresh()
            click(t,transaction(view,"upgrade").button); refresh()
            click(t,transaction(view,"branch","focus").button); refresh()
            t:Equal(r.towers[1].branch_id,"focus","按钮真实提交分支")
            t:Check(transaction(view,"branch","reach").button.props.disabled,"另一分支实际禁用")
            t:Equal(view.protoSlots[1].attrs.props.text,Proto.AttributesText(require("defense.TowerModules").Attributes(r,r.towers[1]),r),"分支后界面读取公共属性")
            playerText(t,view.root,r)
            view:Destroy()
            t:Check(#widgets>0,"执行组件树而非文本扫描")
        end)
    end)
    case("UI02", function(t)
        presentation(function(_, _, _, _)
            local View, Proto, Modules = require("defense.View"), require("defense.ProtoView"), require("defense.TowerModules")
            local r, submitted = fresh("large_map_proto"), 0
            logistics(t, r)
            local view = View.New(r, { action = function(kind, payload)
                if kind == "transaction" then
                    submitted = submitted + 1
                    local result = r:Transact(payload.action, payload.slot, payload.type, "UI交易" .. submitted)
                    t:Check(result.ok, "按钮回调提交真实成功交易")
                elseif kind == "close_logistics" then r:Resume("logistics") end
            end })
            view.menuOpen = false; view:Update(0)
            local function refresh()
                view:Events(r.events); view:Update(0); view:Update(0)
                playerText(t, view.root, r)
                t:Equal(#view.protoSlots, 1, "后勤只创建一个当前槽的详情")
                for _, binding in ipairs(view.transactionButtons) do
                    t:Check(not binding.slot or binding.slot == view.selectedLogisticsSlot, "所有有槽交易只绑定当前选择")
                end
            end
            refresh()
            t:Equal(#r.config.build_slots, 13, "大图真实13槽输入不裁配置")
            t:Equal(view.selectedLogisticsRoom, "core", "默认选主殿")
            t:Equal(#view.transactionButtons, 5, "默认主殿仅2维护+3当前槽建造交易")
            local coreSlots = view.protoLogisticsSelectors
            t:Check(#coreSlots > 1, "保留主殿槽切换入口")
            click(t, coreSlots[2].button); refresh()
            local selected = view.selectedLogisticsSlot
            t:Equal(selected, coreSlots[2].slot.id, "选第二槽真实保持")
            local function selectRoom(id)
                for _, binding in ipairs(view.protoLogisticsRooms) do if binding.id == id then click(t, binding.button); refresh(); return end end
                error("缺少房间选择入口：" .. id)
            end
            selectRoom("A1")
            t:Equal(transaction(view, "build", "rapid").button.props.disabled, true, "未清外围建造真正禁用")
            selectRoom("core"); t:Equal(view.selectedLogisticsSlot, selected, "切房后恢复主殿已选槽")
            local panel = view.overlayContent
            click(t, transaction(view, "build", "rapid").button); refresh()
            local built = tower(r, selected)
            t:Check(panel.destroyed and view.overlayContent ~= panel, "建造后结构key触发真实旧树销毁/重建")
            t:Equal(transaction(view, "build"), nil, "建造后不保留旧空槽建造交易")
            t:Check(transaction(view, "upgrade") and transaction(view, "demolish"), "建造后有升级/拆除入口")
            t:Check(hasWidgetText(visibleWidgets(view.overlay), "服务费"), "已建造详情保留真实服务费说明")
            r.module_inventory.rapid_focus, r.module_inventory.slow_anchor = true, true
            r.module_inventory.rapid_sweep, r.module_inventory.invalid_module = false, true
            refresh()
            local moduleCount = 0
            for _, binding in ipairs(view.transactionButtons) do
                if binding.action == "module" then
                    moduleCount = moduleCount + 1
                    t:Equal(binding.towerType, "rapid_focus", "仅展示已拥有且兼容模块；未拥有/异类/无效不建交易")
                end
            end
            t:Equal(moduleCount, 1, "一个兼容已拥有模块仅一个安装交易")
            panel = view.overlayContent
            click(t, transaction(view, "upgrade").button); refresh()
            t:Check(panel.destroyed, "升级修改结构key并重建")
            t:Equal(view.selectedLogisticsSlot, selected, "升级后选择保持")
            t:Check(view.protoSlots[1].status.props.text:find("等级 2", 1, true), "真实升级等级出现在当前详情")
            local attributes = Modules.Attributes(r, built)
            t:Equal(view.protoSlots[1].attrs.props.text, Proto.AttributesText(attributes, r), "详情准确展示真实有效属性")
            built.attack_cd = 0.37
            local hp, level, cooldown = built.hp, built.upgrade_count, built.attack_cd
            click(t, transaction(view, "module", "rapid_focus").button); refresh()
            t:Equal(built.hp, hp, "模块UI操作不修复设施")
            t:Equal(built.upgrade_count, level, "模块UI操作保留升级")
            t:Near(built.attack_cd, cooldown, "模块UI操作保留真实冷却")
            t:Check(transaction(view, "module", "rapid_focus").button.props.disabled, "已安装模块真正禁用")
            t:Equal(view.protoSlots[1].attrs.props.text, Proto.AttributesText(Modules.Attributes(r, built), r), "安装后属性准确刷新")
            r.module_inventory.rapid_sweep = true; refresh()
            click(t, transaction(view, "module", "rapid_sweep").button); refresh()
            t:Near(built.service_spend, 20, "更换服务费仍真实扣20")
            t:Equal(view.selectedLogisticsSlot, selected, "更换模块后选择保持")
            local stale = transaction(view, "upgrade").button
            r.currency = 0
            local count, before = submitted, state(r)
            stale.props.onClick(stale) -- 排队点击边界：不靠stub禁用阻断，重验真实View交易权限。
            t:Equal(submitted, count, "旧按钮在资金变化后不提交非法交易")
            t:Equal(state(r), before, "拒绝排队点击无规则副作用")
            r.currency = 100000; refresh()
            panel = view.overlayContent
            click(t, transaction(view, "demolish").button); refresh()
            t:Check(panel.destroyed and transaction(view, "build", "rapid"), "拆除后恢复空槽结构")
            t:Equal(transaction(view, "module"), nil, "拆除后旧模块交易不残留")
            t:Equal(view.selectedLogisticsSlot, selected, "拆除后选择保持")
            click(t, findButton(view.overlay, "继续战备")); view:Update(0)
            t:Equal(r.pause_reasons.logistics, nil, "关闭只释放真实后勤暂停")
            t:Check(r:OpenLogistics(), "再次打开真实后勤")
            refresh(); t:Equal(view.selectedLogisticsSlot, selected, "关闭再开选择仍保持")
            view:Destroy()
        end)
        print("[UI02证据边界] 13槽配置/单当前槽交易/选择保持/结构刷新均调用真实View与Economy；不证明屏幕能看到每个控件")
    end)

    case("UI03", function(t)
        local r, e = budgetFixture(t, 10)
        damage(t, r, e, 8, { source = "player", source_id = "player" }, 8)
        damage(t, r, e, 8, { source = "tower_rapid", source_id = "设施身份" }, 2)
        local report = require("defense.Feedback").Stage(r)
        presentation(function(_, _, _, _)
            local View, Proto = require("defense.View"), require("defense.ProtoView")
            r:Pause("recap")
            local view = View.New(r, {})
            view.menuOpen = false; view:Update(0)
            local before = fingerprint(report)
            t:Check(hasWidgetText(visibleWidgets(view.overlay), "对远征实际有效输出 10.00"), "真实主View战报展示预算裁8/2总和10.00")
            t:Equal(fingerprint(report), before, "战报显示不修改来源输出/预算历史")
            t:Equal(Proto.LastReport(fresh("large_map_proto")), nil, "新场景无别场景战报")
            local shared = r.meta
            shared.scenario_reports = shared.scenario_reports or {}
            shared.scenario_reports[r.record_namespace] = { scenario_id = "reuse_sample", wave = 5, totals = { expedition_output = { player = 10 } } }
            local other = fresh("large_map_proto"); other.meta = shared
            t:Equal(Proto.LastReport(other), nil, "共享meta仍拒绝跨场景旧战报")
            t:Equal(Proto.LastReport(r), shared.scenario_reports[r.record_namespace], "同场景命名空间旧战报仍可读取")
            playerText(t, view.root, r)
            local later = copy(report); later.wave, later.totals.expedition_output = report.wave + 1, { player = 11 } -- 次阶段页签输入夹具，不伪称实战输出。
            r.stage_reports, shared.scenario_reports[r.record_namespace] = { report, later }, nil
            view.modeKey = "__dirty"; view:Update(0)
            t:Check(hasWidgetText(visibleWidgets(view.overlay), "对远征实际有效输出 11.00"), "战报默认选最近阶段")
            t:Equal(hasWidgetText(visibleWidgets(view.overlay), "对远征实际有效输出 10.00"), false, "非当前战报不全量铺开")
            click(t, findButton(view.overlay, "第" .. tostring(report.wave) .. "波")); view:Update(0)
            t:Equal(view.selectedReportIndex, 1, "战报页签选择保持")
            t:Check(hasWidgetText(visibleWidgets(view.overlay), "对远征实际有效输出 10.00"), "切页仍显示真实10.00")
            t:Equal(hasWidgetText(visibleWidgets(view.overlay), "对远征实际有效输出 11.00"), false, "切页移除旧展示而不改报告事实")
            t:Equal(fingerprint(report), before, "切战报页签不改原预算/来源历史")
            view:SetRun(fresh("reuse_sample")); view.menuOpen = false; view:Update(0)
            t:Equal(view.selectedReportIndex, nil, "新局不沿用旧战报页签索引")
            view:Destroy()
        end)
    end)

    case("M05", function(t)
        local Scenarios = require("defense.Scenarios")
        local config = Scenarios.Get("large_map_proto")
        for _, def in pairs(config.enemies) do def.speed = 0 end -- 负载逻辑夹具，不宣称巡行速度或设备性能。
        local a, b = fresh("large_map_proto", 555, copy(config)), fresh("large_map_proto", 555, copy(config))
        a.run_id, b.run_id = "M05固定CPU回放", "M05固定CPU回放" -- 仅对照夹具相同身份，避免root前缀差异伪装逻辑变化。
        local function setup(r)
            for _, item in ipairs(r.rooms) do item.state = "cleared" end
            require("defense.RoomGraph").UpdateAccess(r)
            logistics(t, r)
            for i = 1, 6 do build(t, r, r.config.build_slots[i].id, i % 2 == 0 and "area" or "rapid") end
            r:Resume("logistics")
            r.preparation_remaining = 100000; r.player.x, r.player.y = r.config.recall_position.x, r.config.recall_position.y
            for i = 1, r.config.alive_soft_limit do
                local e = spawn(t, r, { role = "advance", portal = "S", x = 30 + (i % 5) * 0.6, y = 25 + (i % 8) * 0.4,
                    subtype = i % 4 == 0 and "explosive" or nil })
                e.attack_cd = 100000
            end
            local first = r.enemies[4]
            kill(t, r, first, { source = "player", source_id = "player", root_action_id = "负载连锁" })
        end
        setup(a); setup(b)
        a.meta.settings, b.meta.settings = a.meta.settings or {}, b.meta.settings or {}
        a.meta.settings.reduced_effects, b.meta.settings.reduced_effects = false, true
        local samples, calls, peak = {}, 0, 0
        local original = a.map.Path
        a.map.Path = function(self, ...) calls = calls + 1; return original(self, ...) end -- 只计数，调用原公共寻路。
        for _ = 1, 40 do
            local start = os.clock(); a:Update(0.05); samples[#samples + 1] = os.clock() - start
            b:Update(0.05); peak = math.max(peak, #a.events)
        end
        a.map.Path = original
        local function logical(r)
            return fingerprint({ player = r.player, core = r.core, enemies = r.enemies, towers = r.towers,
                projectiles = r.projectiles, drops = r.drops, clock = r.clock, totals = r.totals,
                pending = r.pending_harmful_reactions, queue = r.director.queue })
        end
        t:Equal(logical(a), logical(b), "减少表现设置不改模拟伤害/时钟/事件结果")
        t:Near(a.clock, 2, "40CPU模拟步不漏步")
        t:Check(#events(a, "Explosion") > 0 and #events(a, "EnemyDied") > 1, "真实延时连锁已发生")
        t:Equal(#a.events, #b.events, "表现开关不丢事件")
        local total, max = 0, 0; for _, seconds in ipairs(samples) do total = total + seconds; max = math.max(max, seconds) end
        local grids, fields = 0, 0; for _ in pairs(a.map.grids) do grids = grids + 1 end; for _ in pairs(a.map.fields) do fields = fields + 1 end
        print(string.format("[M05 CPU数据，非FPS] 房间=%d 存活塔=%d 初始进攻怪=%d CPU总秒=%.6f 平均步毫秒=%.3f 最大步毫秒=%.3f 路径查询=%d 网格缓存=%d 路径缓存=%d revision=%s 峰值事件=%d",
            #a.rooms, #a.towers, config.alive_soft_limit, total, total / #samples * 1000, max * 1000, calls, grids, fields, tostring(a.map.revision), peak))
    end)

    case("R01", function(t)
        local r = fresh(); logistics(t, r)
        local item, selected = room(r, "A1"), slot(r, "A1")
        local before = state(r)
        t:Equal(r:Transact("build", selected.id, "rapid", "未清").ok, false, "未清禁止外围建造")
        t:Equal(state(r), before, "未清失败无副作用"); r:Resume("logistics")
        clearRoom(t, r, item.id); logistics(t, r)
        build(t, r, selected.id, "rapid", "已清未领")
        t:Equal(item.reward_claimed, false, "清未领可建不隐式领奖")
        r:Transact("demolish", selected.id, nil, "拆除"); r:Resume("logistics")
        t:Check(r:ClaimRoom(item.id), "真实一次领取"); dismiss(r); logistics(t, r)
        build(t, r, selected.id, "rapid", "已领部署"); r:Resume("logistics")
        local beforeRewards = fingerprint({ r.currency, r.player.experience, r.module_inventory, r.room_module_claims, item.state })
        local route, waveId = routeFor(r); r.wave_id = waveId; r:EnterPreparation()
        for _ = 1, 3 do t:Check(require("defense.RoomGraph").OpenChallenge(r), "反复考验开门") end
        t:Equal(fingerprint({ r.currency, r.player.experience, r.module_inventory, r.room_module_claims, item.state }), beforeRewards, "考验不重发房间奖励或重置探索态")
        t:Equal(#events(r, "RoomRewardClaimed"), 1, "房间奖励次数唯一")
        for _, stop in ipairs(route.stops) do t:Check(room(r, stop.room_id).challenge_target, "路线站点来源于真实challenge_target配置") end
    end)

    case("R02", function(t)
        local r, e, route = routeFixture(t, "reuse_sample")
        local first = route.stops[1]; local item = room(r, first.room_id)
        item.state = "cleared"; logistics(t, r)
        local built = build(t, r, slot(r, item.id).id, "rapid")
        r:Resume("logistics")
        built.hp, built.attack_cd = built.hp - 5, 0.5
        local before = e.hp
        r:Update(0.1)
        t:Near(e.hp, before, "区域无考验目标不输出到远处")
        t:Near(built.attack_cd, 0.4, "外围闲置冷却仍按模拟时钟")
        advance(t, r, e, function(unit) return unit.stage == "ROOM_ENGAGED" end, 10000)
        local hp = e.hp
        r:Update(1.5)
        t:Check(e.hp < hp and r.totals.tower_output > 0, "外围塔实际攻击区域内主敌")
        t:Equal(item.state, "cleared", "考验不重刷原守军")
        t:Equal(#item.guard_ids, 0, "远征过境不生成守军")
        t:Check(built.hp < built.max_hp, "原损坏生命未被激活恢复")
        require("defense.Combat").Damage(r, built, built.hp + 1, { source = "death_explosion", source_id = "夹具" })
        t:Equal(built.hp, 0, "公共规则摧毁外围设施")
        logistics(t, r); local rebuilt = build(t, r, built.slot_id, "rapid", "外围重建"); r:Resume("logistics")
        t:Check(rebuilt.entity_id ~= built.entity_id and rebuilt.hp == rebuilt.max_hp, "设施寿命独立，重建新身份")
        t:Equal(item.state, "cleared", "重建不重置探索奖励状态")
    end)

    case("R03", function(t)
        local _, Combat, Scenarios = dependencies()
        local cfg = Scenarios.Get("reuse_sample")
        local special = cfg.waves[5].special_units[1]; special.at = 100
        local r = fresh("reuse_sample", 4, cfg)
        r.wave_id = 5; r:EnterPreparation(); r.story_seen.final_intro = true
        t:Check(r:StartAttack(), "考验开波")
        local director = r.director
        local loops = 0
        while director.elapsed < 50 do
            for _, e in ipairs(r.enemies) do if e.alive and e.role ~= "expedition" then kill(t, r, e) end end
            director:Update(1, r:AliveCount(), function(unit) return Combat.Spawn(r, unit) and true or false end)
            loops = loops + 1; t:Check(loops < 100, "普通队列实际耗尽")
        end
        for _, e in ipairs(r.enemies) do if e.alive then kill(t, r, e) end end
        t:Equal(r:AliveCount(), 0, "特殊单位未生成前可暂时无怪")
        t:Equal(director.generation_complete, false, "未生成特殊单位不伪完成")
        r:SettleWave(); t:Equal(r.ended, false, "不提前胜利")
        for _ = 1, cfg.alive_soft_limit do spawn(t, r, { role = "advance", portal = "S" }) end
        local cursor = director.cursor
        director:Update(100, r:AliveCount(), function(unit) return Combat.Spawn(r, unit) and true or false end)
        t:Equal(director.cursor, cursor, "软上限特殊延期不跳队首")
        t:Equal(director.generation_complete, false, "延期仍未完成")
        for _, e in ipairs(r.enemies) do if e.alive then kill(t, r, e) end end
        director:Update(0.05, 0, function(unit) return Combat.Spawn(r, unit) and true or false end)
        t:Check(director.generation_complete, "特殊生成后队列才完成")
        t:Equal(r:AliveCount(), 1, "特殊存活计入进攻怪")
        local e = r.enemies[#r.enemies]
        t:Equal(e.role, "expedition", "延期待队列没有丢特殊单位")
        r:SettleWave(); t:Equal(r.ended, false, "特殊转场中仍阻止清波")
        t:Equal(director.emitted, #director.queue, "全部真实生成计数")
    end)

    case("R04", function(t)
        local finals, outputs = {}, {}
        for index, mode in ipairs({ "未探索", "仅清空", "已布防" }) do
            local r, e, route = routeFixture(t, "reuse_sample", nil, 404)
            if index >= 2 then for _, item in ipairs(r.rooms) do item.state = "cleared" end end
            if index == 3 then
                logistics(t, r)
                for _, stop in ipairs(route.stops) do
                    local built = build(t, r, slot(r, stop.room_id).id, "rapid")
                    built.hp, built.max_hp = 100000, 100000 -- 隔离设施耐久，测实际输出；原型平衡需E01。
                end
                r:Resume("logistics")
            end
            patrol(t, r, e, route)
            finals[index], outputs[index] = e.hp, r.totals.tower_output
            local sum = 0
            for _, budget in pairs(e.damage_ledger) do sum = sum + budget.used end
            t:Near(e.max_hp - e.hp, sum, "终局HP继承真实预算承伤")
            t:Near(r.totals.tower_output, sum, "复盘塔输出只记实际来源")
            print(string.format("[R04 CPU实移对照，非平衡结论] %s 终局HP=%.2f 塔输出=%.2f", mode, e.hp, sum))
        end
        t:Near(finals[1], finals[2], "清空本身不伪造削弱")
        t:Check(finals[3] < finals[2] and outputs[3] > 0, "真实布防实际改变终局HP")
    end)

    case("X01", function(t)
        for _, id in ipairs({ "reuse_sample", "large_map_proto" }) do
            local r, e, route = routeFixture(t, id, nil, 101)
            local pre = events(r, "ChallengeAnnounced")[1]
            t:Check(pre ~= nil, "实际预告存在")
            for i, stop in ipairs(route.stops) do t:Equal(pre.data.stop_ids[i], stop.room_id, "预告与真实配置一致") end
            patrol(t, r, e, route)
            t:Near(e.hp, 1200, "无输出巡行不暗减生命")
            local snapshot = expeditionSnapshot(r, e); snapshot.damage_ledger[route.stops[1].room_id].used = 999
            t:Near(e.damage_ledger[route.stops[1].room_id].used, 0, "快照不暴露可变预算")
            local position = { x = e.x, y = e.y }
            r:Update(0.05)
            t:Check(distance(position, e) <= r.config.enemies.expedition.speed * 0.05 + 0.00001, "终局仍真实移动，不瞬回核心")
        end
    end)

    case("X02", function(t)
        local r, e, route = budgetFixture(t, 10)
        local first = route.stops[1].room_id
        damage(t, r, e, 30, "player", 10)
        t:Near(e.damage_ledger[first].used, 10, "单击预算裁10")
        t:Equal(e.stage, "LEAVING", "预算耗尽立即离场")
        damage(t, r, e, 30, "tower_rapid", 0)
        local q, target, path = budgetFixture(t, 10)
        damage(t, q, target, 8, "player", 8)
        t:Equal(target.stage, "ROOM_ENGAGED", "首8后仍合法交战")
        t:Check(target.hp > 100 and target.stage_elapsed < 1, "第二击并非HP/超时夹具")
        damage(t, q, target, 8, "tower_area", 2)
        t:Near(target.damage_ledger[path.stops[1].room_id].used, 10, "同槽8/8真实得到8/2")
        t:Near(q.totals.player_output, 8, "玩家只记8actual")
        t:Near(q.totals.tower_output, 2, "塔只记2actual")
        damage(t, q, target, 8, "player", 0)
        local low, floorEnemy, floorRoute = budgetFixture(t, 10)
        floorEnemy.hp = 2 -- 独立巡行HP保底输入，不以此替代上面足量HP预算测试。
        damage(t, low, floorEnemy, 100000, "player", 1)
        t:Near(floorEnemy.hp, 1, "巡行至少1HP")
        t:Check(floorEnemy.alive and floorEnemy.damage_ledger[floorRoute.stops[1].room_id].used == 1, "极高致死伤害不假死，不虚耗预算")
        t:Equal(#events(low, "EnemyDied"), 0, "保底不发死亡/掉落")
    end)

    case("X03", function(t)
        local _, Combat = dependencies()
        local r, e, route = budgetFixture(t, 10)
        local stop = route.stops[1]
        -- 三个来源同一真实时槽：合法发射位置/扫描弹与延时爆炸都走公共实际入口。
        local explosive = spawn(t, r, { role = "advance", portal = "S", x = e.x + 1.2, y = e.y, subtype = "explosive",
            death_reaction = { delay = 0.1, radius = 2.5, damage = 8 } })
        explosive.attack_cd = 100000
        kill(t, r, explosive, { source = "player", source_id = "player", root_action_id = "延时公共预算" })
        local before = e.hp
        r:Update(0.1)
        t:Near(before - e.hp, 8, "真实延时爆炸共享站预算")
        t:Near(e.damage_ledger[stop.room_id].used, 8, "延时爆炸记actual")
        local b = { id = r.next_entity_id, x = e.x - 1.5, y = e.y, dx = 1, dy = 0, speed = 19,
            radius = 0.08, remaining = 5, damage = 8, core_damage = 0, team = "player", source = "tower_area",
            pierce = 0, blast = 1, splash = 2, frost = 0, hit_ids = {}, alive = true, source_id = "边界塔",
            context = { source = "tower_area", source_id = "边界塔" } }
        r.next_entity_id = r.next_entity_id + 1; r.projectiles[#r.projectiles + 1] = b
        before = e.hp; r:Update(0.1)
        t:Near(before - e.hp, 2, "实际塔来源扫描弹/溅射裁剩余2")
        t:Near(e.damage_ledger[stop.room_id].used, 10, "多来源公共预算无越界")
        damage(t, r, e, 99, "player", 0)
        t:Equal(e.stage, "LEAVING", "提交时转场后余伤为0")
        -- 房间不符独立边界输入：保留ROOM_ENGAGED，合法通道坐标不冒充巡行路线证据。
        local q, target = budgetFixture(t, 10)
        target.x, target.y = q.config.portals.S.x, q.config.portals.S.y
        t:Check(q.map:RoomAt(target.x, target.y) ~= q.config.expedition_routes[target.route_id].stops[1].room_id, "当前空间确与站点不符")
        damage(t, q, target, 8, "player", 0)
        t:Check(events(q, "DamageCapped")[1].data.reason == "physical_room_mismatch", "按提交时真RoomAt拒绝")
        -- 真墙隔断弹体，不用私有DamageEnemy绕过LOS。
        local wall = fresh(); wall.preparation_remaining = 100000
        local blocked = spawn(t, wall, { role = "elite", portal = "W", x = 29, y = 21 })
        blocked.attack_cd = 100000
        wall.projectiles[1] = { id = 991, x = 23, y = 21, dx = 1, dy = 0, speed = 19, radius = 0.08,
            remaining = 10, damage = 30, core_damage = 0, team = "player", source = "player", pierce = 1,
            blast = 1, frost = 0, hit_ids = {}, alive = true }
        local hp = blocked.hp; Combat.Update(wall, 0.5)
        t:Near(blocked.hp, hp, "墙遮挡仍拒绝穿墙弹/溅射")
    end)

    case("X04", function(t)
        local r, e, route = budgetFixture(t, 10)
        local roomId = route.stops[1].room_id
        damage(t, r, e, 3, "player", 3)
        t:Check(require("defense.Combat").Displace(r, e, 0, -1, 3, { source = "active", source_id = "player" }), "公共重量位移实际发生")
        t:Near(e.damage_ledger[roomId].used, 3, "击退不重置预算")
        local index = e.route_index
        advance(t, r, e, function(unit) return unit.route_index > index end, 10000)
        t:Near(e.damage_ledger[roomId].used, 3, "离房/重新找交战点/超时后账本保留")
        t:Equal(e.route_index, 2, "到时无玩家也前进，不回站")
        t:Equal(#events(r, "RoomRewardClaimed"), 0, "无重复奖励")
        local q, target, path = budgetFixture(t, 10)
        damage(t, q, target, 10, "tower_rapid", 10)
        advance(t, q, target, function(unit) return unit.route_index == 2 end, 10000)
        t:Near(target.damage_ledger[path.stops[1].room_id].remaining, 0, "耗预算分支真实推进且不重置")
    end)

    case("X05", function(t)
        local r, e = budgetFixture(t, 10)
        damage(t, r, e, 3, "player", 3)
        for _, reason in ipairs({ "manual", "upgrade", "module_choice", "focus" }) do
            r:Pause(reason)
            local frozen = fingerprint({ r.clock, e, r.director.elapsed, r.director.cursor, r.scheduled_events, r.player.attack_cd })
            r:Update(5); require("defense.Combat").Update(r, 5)
            t:Equal(fingerprint({ r.clock, e, r.director.elapsed, r.director.cursor, r.scheduled_events, r.player.attack_cd }), frozen,
                "暂停冻结时钟/交战/预算/队列：" .. reason)
            r:Resume(reason)
        end
        local clock = r.clock; r:Update(0.05)
        t:Near(r.clock - clock, 0.05, "恢复无5秒补发")
        local id = e.entity_id; r:Close("规则退出")
        t:Equal(r.result, "abandoned", "退出不是胜利")
        local before = fingerprint({ e, r.clock, r.projectiles }); r:Update(30)
        t:Equal(fingerprint({ e, r.clock, r.projectiles }), before, "退出后不再推进旧主敌")
        local retry = require("defense.Run").New { scenario_id = r.scenario_id, seed = r.seed, retry = true, meta = r.meta }
        t:Equal(retry.scenario_id, r.scenario_id, "重试保留场景")
        t:Equal(#retry.enemies, 0, "新局无旧主敌")
        t:Equal(#require("defense.Expedition").Snapshot(retry), 0, "新局无旧预算")
        t:Equal(#retry.scheduled_events, 0, "新局无旧反应")
        t:Check(retry.run_id ~= r.run_id, "身份不串局，旧entity不复用")
        t:Check(id ~= nil, "旧历史身份仅留事实回看")
    end)

    case("X06", function(t)
        local finals = {}
        for index, high in ipairs({ false, true }) do
            local r, e, route = routeFixture(t, "reuse_sample", nil, 606)
            patrol(t, r, e, route, function(run, target, stop)
                if high then damage(t, run, target, route.room_caps[stop.room_id] + 30, "player", route.room_caps[stop.room_id]) end
            end)
            finals[index] = e.hp
            t:Equal(e.stage, "FINAL_ASSAULT", "全部站点才终局")
            t:Near(e.hp, high and 600 or 1200, "不同沿途输出继承真实剩余HP")
            presentation(function()
                local View = require("defense.ProtoView")
                local text = View.ExpeditionText(expeditionSnapshot(r, e), false)
                t:Check(text:find("解除", 1, true) and text:find("可击杀", 1, true), "终局护甲解除如实提示")
            end)
            local capped = #events(r, "DamageCapped")
            local inherited = e.hp
            damage(t, r, e, inherited + 100, "player", inherited)
            t:Equal(#events(r, "DamageCapped"), capped, "终局overkill按实际HP裁切，不再产生巡行DamageCapped")
            t:Equal(e.stage, "DEAD", "终局可正常死亡")
            t:Equal(#events(r, "EnemyDied"), 1, "死亡一次")
            local drops = #r.drops; damage(t, r, e, 99, "player", 0)
            t:Equal(#r.drops, drops, "重复击杀不双掉落")
            t:Equal(r:AliveCount(), 0, "仅真正死亡才减少进攻怪")
        end
        t:Check(finals[1] > finals[2], "输出决定终局压力，非无效限伤")
    end)

    case("X07", function(t)
        local cfg = require("defense.Scenarios").Get("reuse_sample")
        cfg.gate_regions[#cfg.gate_regions + 1] = { id = "规则临时门", x1 = 14.5, y1 = 19, x2 = 15.5, y2 = 23, unlocked = true }
        local r, e = routeFixture(t, "reuse_sample", cfg)
        -- 出生后封闭西侧通道而不是锁房：UpdateAccess不会把临时合法门自动重开。
        t:Check(r.map:SetUnlocked("规则临时门", false), "临时物理阻挡真的提交")
        local attempts = 0
        while #events(r, "StuckRepath") == 0 and not r.technical_error and attempts < 4000 do
            local previous = { x = e.x, y = e.y }
            r:Update(0.05); attempts = attempts + 1
            t:Check(distance(previous, e) <= r.config.enemies.expedition.speed * 0.05 + 0.00001, "卡路恢复仍不瞬移")
        end
        t:Check(#events(r, "StuckRepath") > 0, "先重寻当前路点")
        local id, hp = e.entity_id, e.hp
        while not r.technical_error and attempts < 5000 do
            local previous = { x = e.x, y = e.y }
            r:Update(0.05); attempts = attempts + 1
            t:Check(distance(previous, e) <= r.config.enemies.expedition.speed * 0.05 + 0.00001, "持续卡路不能回迁出生入口")
        end
        t:Check(r.technical_error ~= nil and r.pause_reasons.technical, "持续不可达进入技术异常暂停")
        t:Equal(r.ended, false, "技术异常不End失败/胜利")
        t:Equal(e.entity_id, id, "不替换卡怪身份"); t:Check(e.alive, "不删怪冒充清波")
        t:Near(e.hp, hp, "卡路不损生命")
        t:Check(distance(e, r.config.portals.S) > 5, "保持最后合法路线位置，不回出生入口")
        t:Check(#events(r, "StuckRepath") > 0, "先重寻当前路点")
        t:Equal(#events(r, "StuckRecovered"), 0, "不套普通怪出生入口回迁")
        t:Equal(#events(r, "WaveCleared"), 0, "异常不正常清波")
        t:Equal(#events(r, "ExpeditionPathError"), 1, "技术错误可追溯一次")
        local before = fingerprint({ e, r.clock, r.director.cursor }); r:Update(5)
        t:Equal(fingerprint({ e, r.clock, r.director.cursor }), before, "技术暂停冻结模拟")
    end)

    case("C01", function(t)
        local r, e, route = routeFixture(t, "reuse_sample")
        local identity, alive = e.entity_id, r:AliveCount()
        t:Equal(alive, 1, "携带current_room仍属进攻实体")
        t:Equal(e.wave_id, r.wave_id, "当前波身份")
        advance(t, r, e, function(unit) return unit.stage == "ROOM_ENGAGED" end, 10000)
        t:Equal(e.current_room_id, route.stops[1].room_id, "房间空间信息更新")
        t:Equal(e.room_id, nil, "空间信息不误设守军归属")
        t:Equal(r:AliveCount(), alive, "跨站不漏计活怪")
        -- 重复生成操作明确两个新实体，不把同role当同身份；独立预算且死亡各一次。
        local secondUnit = { role = "expedition", portal = "S", route_id = route.route_id, spawn_key = "C01第二远征" }
        local second = spawn(t, r, secondUnit)
        t:Check(second.entity_id ~= identity and second.damage_ledger ~= e.damage_ledger, "同role再次Spawn仍独立身份/预算")
        local spawnCount = #events(r, "EnemySpawned")
        t:Equal(spawn(t, r, secondUnit), second, "同spawn_key重放返回已有实体")
        t:Equal(#events(r, "EnemySpawned"), spawnCount, "重放不生成新事件或预算")
        t:Equal(r:AliveCount(), 2, "不按房间或role错误去重活怪")
        patrol(t, r, e, route)
        kill(t, r, e, "player")
        t:Equal(r:AliveCount(), 1, "死一个不会删除另一个")
        require("defense.Combat").DamageEnemy(r, e, 99999, "player")
        t:Equal(#events(r, "EnemyDied"), 1, "重复Death操作唯一")
        t:Equal(events(r, "EnemyDied")[1].data.room_id, nil, "死亡归属不变守军")
    end)

    case("C02", function(t)
        for _, fail in ipairs({ false, true }) do
            local r = fresh("reuse_sample")
            r.wave_id = 5; r:EnterPreparation(); r.story_seen.final_intro = true
            t:Check(r:StartAttack(), "终局清波边界启动")
            -- 队列完成边界输入，仅验证危险/失败；真实特殊队列R03独立测。
            r.director.generation_complete = true; r.director.cursor = #r.director.queue + 1
            local e = spawn(t, r, { role = "advance", portal = "S", x = r.core.x, y = r.core.y + 2,
                subtype = "explosive", death_reaction = { delay = 0.1, radius = 3, damage = 40 } })
            if fail then r.core.hp = 40 end
            kill(t, r, e, "player")
            t:Check(r:PendingHarmfulCount() > 0, "末敌死亡仍有真实延时危险")
            r:SettleWave(); t:Equal(r.ended, false, "危险结算前不得清波")
            r:Update(0.1)
            t:Equal(r.result, fail and "defeat" or "victory", "同槽失败优先")
            t:Equal(#events(r, "WaveCleared"), fail and 0 or 1, "失败槽不发胜利奖励")
            local before = fingerprint({ r.currency, r.enemies, r.module_inventory, r.meta })
            if r:StorySeen("opening") then
                t:Check(r:ReplayStory("opening"), "结局后回看已见节点")
                r:Update(20); r:PresentationUpdate(14)
            end
            t:Equal(fingerprint({ r.currency, r.enemies, r.module_inventory, r.meta }), before, "终局回看不再生敌人或重复奖励")
            t:Equal(#events(r, "RunEnded"), 1, "结束事件唯一")
        end
        local r, e = budgetFixture(t, 10)
        damage(t, r, e, 8, { source = "player", source_id = "player" }, 8)
        damage(t, r, e, 8, { source = "tower_rapid", source_id = "设施身份" }, 2)
        local report = require("defense.Feedback").Stage(r)
        t:Near(report.totals.expedition_output.player, 8, "阶段保存真实玩家8输出")
        t:Near(report.totals.expedition_output["设施身份"], 2, "阶段保存真实塔2输出")
        local before = fingerprint(report)
        r.totals.expedition_output.player = 999
        e.damage_ledger[e.expedition_route.stops[1].room_id].used = 999
        t:Equal(fingerprint(report), before, "阶段totals和远征预算均深拷贝，源表改变不污染历史")
    end)

    case("C03", function(t)
        local _, _, Scenarios = dependencies()
        local Config, Director = require("defense.Config"), require("defense.WaveDirector")
        local original = fingerprint(Config)
        local legacy = Scenarios.Get("legacy_v02")
        t:Equal(fingerprint(legacy.waves), fingerprint(Config.waves), "legacy原20行不变")
        local ok, totals = Director.Validate(legacy)
        t:Check(ok, "legacy原校验保留"); t:Equal(totals.total, 1176, "legacy1176单位保留")
        local old = fresh("legacy_v02")
        t:Check(old.meta.story_seen.opening, "显式legacy旧opening键兼容")
        t:Near(old.preparation_remaining, 15, "旧首波15秒")
        for _, elapsed in ipairs({ 40, 60, 75 }) do
            local r = fresh("legacy_v02"); r:StartAttack()
            r.director.generation_complete = true; r.director.cursor = #r.director.queue + 1
            r.attack_elapsed = elapsed; r:SettleWave()
            t:Near(r.preparation_remaining, 15 + math.max(0, 60 - elapsed), "旧快速清波公式保留")
        end
        local meta = old.meta
        for _, id in ipairs({ "reuse_sample", "large_map_proto" }) do
            local cfg = Scenarios.Get(id)
            t:Equal(#cfg.waves, 20, "原型保留完整20行输入")
            t:Equal(cfg.waves[id == "reuse_sample" and 5 or 10].special_count, 1, "样板5/大图10附特殊")
            if id == "large_map_proto" then t:Equal(cfg.waves[20].special_count, 1, "大图20附特殊") end
            local r = fresh(id); r.meta = meta
            logistics(t, r); ownAll(r)
            build(t, r, "T1", "rapid", "结束前建造")
            local installed = install(t, r, "T1", "rapid_focus", "结束前安装")
            t:Check(installed.ok, "结束前成功请求夹具")
            r:Resume("logistics")
            r.wave_id = r.total_waves; r:EnterPreparation(); r.story_seen.final_intro = true
            r:StartAttack(); r.director.generation_complete = true; r.director.cursor = #r.director.queue + 1
            r:SettleWave()
            t:Equal(r.result, "victory", "场景独立胜利边界")
            t:Equal(r.meta.chapters["2"], nil, "原型不解锁旧章节")
            t:Check(r.meta.stages[r.record_namespace .. ":1:" .. r.total_waves], "阶段记录按场景命名空间")
            t:Equal(next(r.transactions), nil, "End清理事务账本，不将旧成功返回给已结束局")
            t:Equal(next(r.challenge_opened or {}), nil, "End清理本局考验开门账本")
            t:Equal(next(r.combat_spawn_keys or {}), nil, "End清理生成幂等账本")
            t:Equal(r.module_rng, nil, "End清理模块随机流")
            t:Equal(r.module_seed, nil, "End清理模块随机种子")
            local afterEnd = state(r)
            local replay = r:Transact("module", "T1", "rapid_focus", "结束前安装")
            t:Equal(replay.ok, false, "结束旧请求不再返回历史成功")
            t:Equal(state(r), afterEnd, "结束请求无资金/塔/库存副作用")
            local retry = require("defense.Run").New { scenario_id = id, retry = true, meta = meta, seed = r.seed }
            t:Equal(retry.scenario_id, id, "重试保留场景")
            t:Equal(#retry.towers, 0, "重试设施空")
            t:Equal(next(retry.module_inventory), nil, "重试库存空")
            retry:FinishStory(); retry.core.hp = 0; retry:Update(0.05)
            t:Equal(retry.result, "defeat", "扩展场景正常失败边界")
            t:Equal(retry.meta.chapters["2"], nil, "原型失败不解锁")
        end
        t:Equal(fingerprint(Config), original, "所有新场景夹具不改共享legacy Config")
        print("[C03证据边界] 新增场景边界与旧表公式已测；旧53项仍由Tests原注册实际执行，不以本case替代")
    end)

    for _, id in ipairs({ "E01", "E02", "E03", "E04" }) do
        case(id, function() end, "NOT_RUN: 未执行真人构筑/探索实战、理解访谈或桌面竖屏真机画面/音效/FPS；CPU规则与记录桩不替代体验证据")
    end
end
return P
