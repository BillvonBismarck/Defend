-- 将规则事件适配为音效、粒子和跳字。
local Particle = require("defense.fx.Particle")
local GameAudio = require("defense.fx.GameAudio")
local DamageNumber = require("defense.fx.DamageNumber")
local ScreenShake = require("defense.fx.ScreenShake")
local A = {
    corePortal = "", coreEventId = 0, coreAlert = 0,
    reducedEffects = false, musicVolume = 1, effectsVolume = 1,
}
local initialized, audioReady, running = false, false, false
local runId, lastEventId = "", 0
---@type Node[]
local ownedAudioNodes = {}
---@type Audio?
local mixer = nil
local previousMusic, previousEffects = 1, 1
local criticalKinds = {
    RunStarted = true, PreparationStarted = true, AttackStarted = true, WaveCleared = true,
    RunEnded = true, TransactionResolved = true, RoomCleared = true, RoomRewardClaimed = true,
    RecallCompleted = true, RecallCancelled = true, StuckRepath = true, RecoveryFailed = true,
    StuckRecovered = true, CombatError = true, SaveFailed = true,
    ModuleOffered = true, ModuleChosen = true, ModuleInstalled = true, ModuleChanged = true,
    GateOpened = true, DefenseSiteAvailable = true, ChallengeAnnounced = true,
    ExpeditionStageChanged = true, ExpeditionPathError = true, ChallengePathError = true,
}

local function clampVolume(v)
    return math.max(0, math.min(1, tonumber(v) or 1))
end
local function applyVolume()
    if mixer then
        mixer:SetMasterGain(SOUND_MUSIC, previousMusic * A.musicVolume)
        mixer:SetMasterGain(SOUND_EFFECT, previousEffects * A.effectsVolume)
    end
end

-- 可在 Init 前调用；一个值控制两类，第二值可单独控制音效。
function A.SetVolume(music, effects)
    A.musicVolume = clampVolume(music)
    A.effectsVolume = clampVolume(effects == nil and music or effects)
    applyVolume()
end
function A.SetReducedEffects(reduced)
    A.reducedEffects = reduced == true
    if A.reducedEffects then Particle.Reset(); ScreenShake.Reset() end
end
function A.GetShakeOffset()
    if A.reducedEffects then return 0, 0 end
    return ScreenShake.offsetX, ScreenShake.offsetY
end

local function play(name, gain)
    if audioReady and A.effectsVolume > 0 then GameAudio.PlaySFX(name, gain) end
end
local function particles(d, preset, color)
    if not A.reducedEffects and d.x and d.y then Particle.Spawn(d.x * 32, d.y * 32, preset, color) end
end
local function shake(preset)
    if not A.reducedEffects then ScreenShake.Trigger(preset) end
end
local function number(d, value, style)
    if d.x and d.y and value and value > 0 then
        -- 跳字缓存按 32 px/格定位，渲染时换算为 Board 的逻辑像素。
        DamageNumber.Spawn(d.x * 32, d.y * 32 - 12, tostring(math.floor(value * 10 + 0.5) / 10), style)
    end
end

function A.Init()
    if not initialized then
        -- GameAudio.Init 非幂等：重开局复用池，Stop 只释放本次 Init 新建的节点。
        local before = {}
        if type(GetAudio) == "function" then
            mixer = GetAudio()
            if mixer then
                previousMusic = mixer:GetMasterGain(SOUND_MUSIC)
                previousEffects = mixer:GetMasterGain(SOUND_EFFECT)
                for _, source in ipairs(mixer:GetSoundSources()) do before[source] = true end
            end
        end
        local ok, errorMessage = pcall(GameAudio.Init)
        audioReady = ok
        if mixer then
            local seenNodes = {}
            for _, source in ipairs(mixer:GetSoundSources()) do
                if not before[source] then
                    local node = source:GetNode()
                    if node and not seenNodes[node] then
                        seenNodes[node] = true
                        ownedAudioNodes[#ownedAudioNodes + 1] = node
                    end
                end
            end
        end
        if not ok then print("[DefenseFX] 音频降级：" .. tostring(errorMessage)) end
        initialized = true
    end
    Particle.Reset(); DamageNumber.Reset(); ScreenShake.Reset()
    A.corePortal, A.coreEventId, A.coreAlert = "", 0, 0
    runId, lastEventId, running = "", 0, true
    applyVolume()
    if audioReady then GameAudio.PlayBGM() end
end

function A.Update(dt)
    if not running or dt <= 0 then return end
    if audioReady then GameAudio.Update(dt) end
    Particle.Update(dt)
    DamageNumber.Update(dt)
    if not A.reducedEffects then ScreenShake.Update(dt) end
    A.coreAlert = math.max(0, A.coreAlert - dt)
end

---@param run table
---@param events table[]
function A.Events(run, events)
    if runId ~= (run.run_id or "") then runId, lastEventId = run.run_id or "", 0 end
    for _, event in ipairs(events or {}) do
        local id = event.event_id or (lastEventId + 1)
        -- 先校验 run_id 再推进游标，避免旧局 event_id 吞掉本局事件。
        if (not event.run_id or event.run_id == runId) and id > lastEventId then
            lastEventId = id
            local d = event.data or {}
            local kind = event.kind
            if criticalKinds[kind] then
                local wave = event.wave or d.wave or d.wave_id or run.wave_id or 1
                print(string.format("[Defense][%s] 波=%d 时刻=%.2f", kind, wave, event.time or 0))
            end
            if kind == "Shoot" then play("shoot")
            elseif kind == "Hit" then
                particles(d, "hit")
                number(d, d.amount, d.is_crit and "crit" or "damage")
            elseif kind == "EnemyDied" then
                local elite = d.role == "elite" or d.role == "commander" or d.role == "siege" or d.role == "final" or d.role == "expedition"
                play("enemy_die")
                particles(d, elite and "elite_die" or "enemy_die")
                if elite then shake("boss_defeat") end
            elseif kind == "ReactionScheduled" then
                play("boss_warning", 0.22)
            elseif kind == "Explosion" then
                play("bomb_explode")
                -- 跳字由各目标 Hit/*Damaged 事件提供，爆炸轮廓由 Board 按 LOS 绘制。
                particles(d, "bomb")
                shake("bomb")
            elseif kind == "Displaced" then
                play("dodge_roll", 0.28)
            elseif kind == "DisplacementRejected" or kind == "ActiveRejected" then
                play("skill_select", 0.16)
            elseif kind == "StatusChanged" or kind == "EnemySlowed" then
                -- 仅状态变更播音，避免光环连续刷新时逐帧重播。
                if kind == "StatusChanged" and (d.status == "slow" or d.kind == "slow") and d.active ~= false then
                    play("freeze", 0.18)
                end
            elseif kind == "CoreDamaged" then
                A.corePortal, A.coreEventId, A.coreAlert = d.portal or "S", id, 0.8
                play("boss_warning", 0.4)
                number(d, d.amount, "crit")
                shake("player_hit")
            elseif kind == "PlayerDamaged" then
                play("player_hurt")
                particles(d, "player_hit")
                number(d, d.amount, "crit")
                shake("player_hit")
            elseif kind == "TowerDamaged" then number(d, d.amount, "damage")
            elseif kind == "Pickup" then
                play(d.kind == "gold" and "coin_pickup" or "pickup")
                particles(d, "exp_pickup")
                number(d, d.amount, d.kind == "gold" and "pickup" or "exp")
            elseif kind == "UpgradeOffered" then play("levelup")
            elseif kind == "UpgradeChosen" then
                play("skill_select")
                particles(run.player or {}, "level_up")
            elseif kind == "AttackStarted" then play("wave_start")
            elseif kind == "EnemySpawned" and (d.role == "commander" or d.role == "siege" or d.role == "final" or d.role == "expedition") then
                play("boss_warning"); shake("boss_spawn")
            elseif kind == "Active" or kind == "ActiveUsed" then
                -- 主动技仅位移，不复用范围爆炸反馈。
                play("dodge_roll", 0.24)
            elseif kind == "ModuleOffered" or kind == "ModuleChosen" then play("skill_select", 0.3)
            elseif kind == "ExpeditionStageChanged" and d.after == "FINAL_ASSAULT" then play("boss_warning", 0.5)
            elseif kind == "GateOpened" then play("wave_start", 0.15)
            elseif kind == "TransactionResolved" and d.ok then
                play("heal")
            elseif kind == "RunEnded" then
                if audioReady then GameAudio.StopBGM() end
            end
        end
    end
end

-- Runtime 每次创建新上下文后须重绑 DamageNumber.fontId。
---@param vg NVGContextWrapper
function A.Render(vg, ox, oy, pixelsPerCell, logicalW, logicalH)
    local scale = pixelsPerCell / 32
    nvgSave(vg)
    nvgScale(vg, scale, scale)
    if not A.reducedEffects then Particle.Render(vg, -ox / scale, -oy / scale, logicalW / scale, logicalH / scale) end
    DamageNumber.Render(vg, -ox / scale, -oy / scale, logicalW / scale, logicalH / scale)
    nvgRestore(vg)
end

function A.Stop()
    running = false
    if audioReady then GameAudio.StopBGM() end
    Particle.Reset(); DamageNumber.Reset(); ScreenShake.Reset()
    A.corePortal, A.coreEventId, A.coreAlert = "", 0, 0
    if mixer then
        mixer:SetMasterGain(SOUND_MUSIC, previousMusic)
        mixer:SetMasterGain(SOUND_EFFECT, previousEffects)
    end
    -- GameAudio 无销毁入口；仅 Dispose 自有节点，子 SoundSource 随父释放。
    for _, node in ipairs(ownedAudioNodes) do node:Dispose() end
    ownedAudioNodes = {}
    mixer = nil
    initialized, audioReady = false, false
    DamageNumber.fontId = -1
end
return A
