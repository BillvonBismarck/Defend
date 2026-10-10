--- ============================================================================
--- 屏幕震动系统 - 受伤/Boss出场/炸弹等冲击反馈
--- 使用衰减正弦波模拟震动，支持叠加和优先级
--- ============================================================================

local ScreenShake = {}

-- 当前震动状态
local shakeTimer    = 0.0     -- 剩余时间
local shakeDuration = 0.0     -- 总时长
local shakeIntensity = 0.0    -- 震幅（像素）
local shakeFreq     = 30.0    -- 频率（Hz）

-- 输出偏移（每帧由 Update 计算，由相机读取）
ScreenShake.offsetX = 0
ScreenShake.offsetY = 0

-- 预设强度
ScreenShake.PRESETS = {
    --- 玩家受伤：短促轻震
    player_hit   = { intensity = 4,  duration = 0.15, freq = 35 },
    --- Boss 出场：中等持续震动
    boss_spawn   = { intensity = 6,  duration = 0.4,  freq = 20 },
    --- 炸弹爆炸：强烈冲击
    bomb         = { intensity = 10, duration = 0.35, freq = 25 },
    --- Boss 击败：胜利震动
    boss_defeat  = { intensity = 8,  duration = 0.5,  freq = 18 },
    --- 过载激活
    overload     = { intensity = 5,  duration = 0.25, freq = 28 },
}

--- 触发震动（取更强的那个）
---@param presetName string 预设名
function ScreenShake.Trigger(presetName)
    local p = ScreenShake.PRESETS[presetName]
    if not p then return end
    -- 如果当前震动更强且仍在进行，跳过弱震动
    if shakeTimer > 0 and shakeIntensity > p.intensity then return end
    shakeIntensity = p.intensity
    shakeDuration  = p.duration
    shakeTimer     = p.duration
    shakeFreq      = p.freq
end

--- 自定义震动参数
---@param intensity number 震幅像素
---@param duration number 持续秒
---@param freq number|nil 频率Hz（默认30）
function ScreenShake.TriggerCustom(intensity, duration, freq)
    if shakeTimer > 0 and shakeIntensity > intensity then return end
    shakeIntensity = intensity
    shakeDuration  = duration
    shakeTimer     = duration
    shakeFreq      = freq or 30
end

--- 每帧更新
---@param dt number
function ScreenShake.Update(dt)
    if shakeTimer <= 0 then
        ScreenShake.offsetX = 0
        ScreenShake.offsetY = 0
        return
    end

    shakeTimer = shakeTimer - dt

    -- 衰减因子：线性衰减
    local decay = math.max(0, shakeTimer / shakeDuration)
    -- 正弦波 + 随机扰动
    local t = (shakeDuration - shakeTimer) * shakeFreq
    local amp = shakeIntensity * decay

    ScreenShake.offsetX = amp * math.sin(t * 6.2832) * (0.8 + math.random() * 0.4)
    ScreenShake.offsetY = amp * math.cos(t * 6.2832 * 1.3) * (0.8 + math.random() * 0.4)
end

--- 重置
function ScreenShake.Reset()
    shakeTimer = 0
    shakeDuration = 0
    shakeIntensity = 0
    ScreenShake.offsetX = 0
    ScreenShake.offsetY = 0
end

return ScreenShake
