-- 管理战场、HUD、规则实例和输入的生命周期。
local UI = require("urhox-libs/UI")
require "urhox-libs.UI.VirtualControls"
---@type {New: fun(options?:table):table}
local Run = require("defense.Run")
---@type {New: fun(run:table, options?:table):table}
local Board = require("defense.Board")
local View = require("defense.View")
local Theme = require("defense.Theme")
local Storage = require("defense.Storage")
local LegacyFX = require("defense.FX")
local WaveDirector = require("defense.WaveDirector")
local Config = require("defense.Config")
---@type {Get: fun(id?:string):table, List:fun():string[]}
local Scenarios = require("defense.Scenarios")
local DamageNumber = require("defense.fx.DamageNumber")
local Runtime = {}
---@type table
local current = {}
---@type table
local view = {}
---@type table
local board = {}
---@type NVGContextWrapper?
local vg = nil
---@type VirtualJoystick?
local joystick = nil
local active, serial, requestSerial = false, 0, 0
local pendingActive = false
---@type table
local meta = {}
local renderErrors = 0
local volume, reducedEffects = 1, false
local settingsSaveRemaining = 0
local performance = { frames = 0, elapsed = 0, simulation = 0, simulationMax = 0,
    renderFrames = 0, render = 0, renderMax = 0, snapshot = {} }

function Runtime.GetPerformanceSnapshot()
    local result = {}
    for key, value in pairs(performance.snapshot) do result[key] = value end
    return result
end
local function samplePerformance(rawDt, simulationTime)
    performance.frames = performance.frames + 1
    performance.elapsed = performance.elapsed + rawDt
    performance.simulation = performance.simulation + simulationTime
    performance.simulationMax = math.max(performance.simulationMax, simulationTime)
    if performance.elapsed < 2 then return end
    local snapshot = {
        wave = current.wave_id, state = current.state, enemies = current:AliveCount(),
        update_ms = performance.simulation * 1000 / performance.frames,
        update_max_ms = performance.simulationMax * 1000,
        render_ms = performance.render * 1000 / math.max(1, performance.renderFrames),
        render_max_ms = performance.renderMax * 1000,
        frames = performance.frames, elapsed = performance.elapsed,
    }
    performance.snapshot = snapshot
    if snapshot.state == "ATTACK" and (snapshot.update_max_ms >= 25 or snapshot.render_max_ms >= 25) then
        print(string.format("[DefensePerf] W%d enemies=%d update=%.2f/max%.2fms render=%.2f/max%.2fms",
            snapshot.wave, snapshot.enemies, snapshot.update_ms, snapshot.update_max_ms,
            snapshot.render_ms, snapshot.render_max_ms))
    end
    performance.frames, performance.elapsed, performance.simulation, performance.simulationMax = 0, 0, 0, 0
    performance.renderFrames, performance.render, performance.renderMax = 0, 0, 0
end

local function resetInput()
    pendingActive = false
    if joystick then
        -- 暂停仅清方向，触摸身份由库在真实抬手时释放。
        joystick.x, joystick.y, joystick.magnitude = 0, 0, 0
        joystick.hasTarget = false
    end
end
local function makeRun(totalWaves, build, retry, scenarioId)
    if current.Close and not current.ended then current:Close("重新部署") end
    serial = serial + 1
    local config = Scenarios.Get(scenarioId or current.scenario_id or "legacy_v02")
    local valid, totals = WaveDirector.Validate(config)
    assert(valid, "场景波次配置校验失败")
    print(string.format("[Defense] 场景校验=%s 普通体系=%d 特殊=%d", config.scenario_id, totals.ordinary, totals.special))
    current = Run.New { total_waves = totalWaves or config.total_waves, build = build, retry = retry, config = config,
        scenario_id = config.scenario_id,
        run_id = "defense-" .. tostring(os.time()) .. "-" .. serial,
        seed = 20261002 + serial * 31, meta = meta, on_meta = Storage.Save }
    resetInput()
    LegacyFX.Init()
    if LegacyFX.SetVolume then LegacyFX.SetVolume(volume) end
    if LegacyFX.SetReducedEffects then LegacyFX.SetReducedEffects(reducedEffects) end
    if board.SetRun then
        board:SetRun(current)
        if board.SetReducedEffects then board:SetReducedEffects(reducedEffects) end
    end
    if view.SetRun then view:SetRun(current) end
    print("[Defense] 新局=" .. current.run_id .. " 场景=" .. current.scenario_id .. " 波数=" .. current.total_waves .. " 方案=" .. current.build)
end
local function action(kind, payload)
    if not active then return end
    if kind == "wave" then current:RequestWave()
    elseif kind == "active" then pendingActive = true
    elseif kind == "logistics" then current:OpenLogistics()
    elseif kind == "close_logistics" then current:Resume("logistics")
    elseif kind == "pause" then current:Pause("manual")
    elseif kind == "resume" then current:Resume("manual"); current:Resume("focus")
    elseif kind == "upgrade" then current:ChooseUpgrade(type(payload) == "string" and payload or payload.id)
    elseif kind == "module_open" then current:OpenModuleChoices(type(payload) == "table" and payload.choice_id or payload)
    elseif kind == "module_close" then current:CloseModuleChoices()
    elseif kind == "module_choose" then
        requestSerial = requestSerial + 1
        current:ChooseModule(payload.choice_id, payload.module_id, current.run_id .. ":module:" .. requestSerial)
    elseif kind == "map" then current:Pause("map")
    elseif kind == "close_map" then current:Resume("map")
    elseif kind == "transaction" then
        requestSerial = requestSerial + 1
        current:Transact(payload.action, payload.slot, payload.type, current.run_id .. ":tx:" .. requestSerial)
    elseif kind == "claim" then
        local id = type(payload) == "string" and payload or current.map:RoomAt(current.player.x, current.player.y)
        if id then
            requestSerial = requestSerial + 1
            current:ClaimRoom(id, current.run_id .. ":claim:" .. requestSerial)
        end
    elseif kind == "recall" then current:RequestRecall()
    elseif kind == "skip_story" then current:FinishStory()
    elseif kind == "replay" then current:ReplayStory(payload)
    elseif kind == "menu" then current:Pause("menu")
    elseif kind == "rules" then current:Pause("rules")
    elseif kind == "close_rules" then current:Resume("rules")
    elseif kind == "recap" then current:Pause("recap")
    elseif kind == "close_recap" then current:Resume("recap")
    elseif kind == "volume" then
        volume = math.max(0, math.min(1, payload or 1))
        if LegacyFX.SetVolume then LegacyFX.SetVolume(volume) end
    elseif kind == "reduced_effects" then
        reducedEffects = payload == true
        if LegacyFX.SetReducedEffects then LegacyFX.SetReducedEffects(reducedEffects) end
        if board.SetReducedEffects then board:SetReducedEffects(reducedEffects) end
    elseif kind == "hints" then
        meta.settings.hints = payload == true
    end
    if kind == "volume" or kind == "reduced_effects" or kind == "hints" then
        meta.settings.volume, meta.settings.reduced_effects = volume, reducedEffects
        settingsSaveRemaining = 0.5
    end
    if current:IsPaused() then resetInput() end
end
function Runtime.Start()
    if active then Runtime.Stop() end
    active, renderErrors = true, 0
    graphics.windowTitle = Config.title
    input.mouseMode = MM_ABSOLUTE
    local valid, totals = WaveDirector.Validate(Config)
    assert(valid, "波次配置校验失败")
    print("[Defense] v0.2 配置通过：20波基础进攻=" .. totals.total .. "；候选参数以原型规则执行")
    meta = Storage.Load()
    meta.settings = meta.settings or { volume = 1, reduced_effects = false, hints = true }
    volume, reducedEffects = meta.settings.volume or 1, meta.settings.reduced_effects == true
    settingsSaveRemaining = 0
    -- 模式 B：物理尺寸除 DPR 得逻辑像素；上下文和字体仅在 Start 初始化。
    vg = nvgCreate(1)
    assert(vg, "战场 NanoVG 上下文创建失败")
    nvgSetRenderOrder(vg, -10)
    local font = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    assert(font >= 0, "战场字体加载失败")
    local pixel = nvgCreateFont(vg, "zpix", "Fonts/zpix.ttf")
    DamageNumber.fontId = pixel >= 0 and pixel or font
    VirtualControls.Initialize(720, 1280)
    joystick = VirtualControls.CreateJoystick {
        position = Vector2(140, -210), alignment = { HA_LEFT, VA_BOTTOM },
        baseRadius = 62, knobRadius = 28, moveRadius = 48, pressRegionRadius = 88,
        alwaysShow = false, visible = false, showKeyHints = false,
    }
    UI.Init { theme = Theme.Create(), scale = UI.Scale.DEFAULT }
    makeRun(20, "single", false, "sanctuary_expansion")
    current:Pause("menu")
    board = Board.New(current, { pixels_per_cell = 40, reducedEffects = reducedEffects })
    view = View.New(current, { newRun = makeRun, action = action })
    SubscribeToEvent("Update", "DefenseHandleUpdate")
    SubscribeToEvent(vg, "NanoVGRender", "DefenseHandleRender")
    SubscribeToEvent("InputFocus", "DefenseHandleFocus")
    SubscribeToEvent("AppWillEnterBackground", "DefenseHandleBackground")
    print("[Defense] 原作战场管线已启动：WASD/方向键移动，空格击退，F后勤，R回城，Esc暂停")
end
---@param eventType string
---@param eventData UpdateEventData
function DefenseHandleUpdate(eventType, eventData)
    if not active then return end
    local rawDt = math.max(0, eventData:GetFloat("TimeStep"))
    local dt = math.min(rawDt, 0.1)
    if input:GetKeyPress(KEY_ESCAPE) then
        if current.pause_reasons.module_choice then action("module_close")
        elseif current.pause_reasons.map then action("close_map")
        elseif current.pause_reasons.logistics then action("close_logistics")
        elseif current.pause_reasons.rules then action("close_rules")
        elseif current.pause_reasons.recap then action("close_recap")
        elseif current.pause_reasons.manual or current.pause_reasons.focus then action("resume")
        elseif not current.pause_reasons.menu then action("pause") end
    end
    if input:GetKeyPress(KEY_F) then action("logistics") end
    if input:GetKeyPress(KEY_M) then action("map") end
    if input:GetKeyPress(KEY_R) then action("recall") end
    if input:GetKeyPress(KEY_RETURN) then action("wave") end
    local x, y = 0, 0
    if joystick and joystick.isActive then x, y = joystick:getMovement(false) end
    -- 摇杆无键盘绑定，键盘在这里统一处理，避免双重输入。
    ---@type number
    local kx = (input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)) and 1 or 0
    kx = kx - ((input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)) and 1 or 0)
    ---@type number
    local ky = (input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN)) and 1 or 0
    ky = ky - ((input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP)) and 1 or 0)
    if kx ~= 0 or ky ~= 0 then x, y = kx, ky end
    local pulse = pendingActive or input:GetKeyPress(KEY_SPACE)
    pendingActive = false
    if current:IsPaused() or current.ended then x, y, pulse = 0, 0, false; resetInput() end
    local simulationStarted = os.clock()
    if not current:IsPaused() and (current.state == "PREPARATION" or current.state == "WARNING") then
        current.map:Warmup(48)
    end
    current:PresentationUpdate(dt)
    current:Update(dt, { x = x, y = y, active = pulse })
    local simulationTime = os.clock() - simulationStarted
    local worldDt = not current:IsPaused() and not current.ended and dt or 0
    LegacyFX.Update(worldDt)
    local events = current:DrainEvents()
    LegacyFX.Events(current, events)
    if board.Events then board:Events(events) end
    if view.Events then view:Events(events) end
    board:Update(worldDt)
    view:Update(dt)
    if settingsSaveRemaining > 0 then
        settingsSaveRemaining = math.max(0, settingsSaveRemaining - dt)
        if settingsSaveRemaining == 0 then current:SaveMeta() end
    end
    samplePerformance(rawDt, simulationTime)
    if joystick then
        joystick.visible = not current:IsPaused() and not current.ended
        joystick:_updateShouldShow()
    end
end
---@param eventType string
---@param eventData NanoVGRenderEventData
function DefenseHandleRender(eventType, eventData)
    if not active or not vg then return end
    local dpr = math.max(1, graphics:GetDPR())
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(vg, width, height, dpr)
    nvgSave(vg)
    nvgFontFace(vg, "sans")
    local renderStarted = os.clock()
    local ok, err = pcall(board.Render, board, vg, width, height)
    local renderTime = os.clock() - renderStarted
    performance.renderFrames = performance.renderFrames + 1
    performance.render = performance.render + renderTime
    performance.renderMax = math.max(performance.renderMax, renderTime)
    nvgRestore(vg)
    nvgEndFrame(vg) -- 无论战场是否出错，都提交结束帧，防止永久黑屏。
    if not ok then
        renderErrors = renderErrors + 1
        if renderErrors == 1 or renderErrors % 120 == 0 then print("[Defense][RenderError] " .. tostring(err)) end
    end
end
---@param eventType string
---@param eventData InputFocusEventData
function DefenseHandleFocus(eventType, eventData)
    if active and (not eventData:GetBool("Focus") or eventData:GetBool("Minimized")) then
        resetInput(); current:Pause("focus")
    end
end
function DefenseHandleBackground()
    if active then resetInput(); current:Pause("focus") end
end
function Runtime.Stop()
    active = false
    if settingsSaveRemaining > 0 and current.SaveMeta then current:SaveMeta(); settingsSaveRemaining = 0 end
    if current.Close and not current.ended then current:Close("退出本局") end
    resetInput()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("InputFocus")
    UnsubscribeFromEvent("AppWillEnterBackground")
    if vg then UnsubscribeFromEvent(vg, "NanoVGRender") end
    if view.Destroy then view:Destroy() end
    if board.Destroy then board:Destroy() end
    view, board = {}, {}
    LegacyFX.Stop()
    UI.Shutdown()
    VirtualControls.Shutdown()
    joystick = nil
    if vg then nvgDelete(vg); vg = nil end
    DamageNumber.fontId = -1
    print("[Defense] 已退出；阶段记录保留，旧幸存者存档不改写")
end
return Runtime
