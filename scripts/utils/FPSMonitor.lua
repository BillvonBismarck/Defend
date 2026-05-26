--- ============================================================================
--- FPS 监控 + 自动性能降级
--- 滚动窗口计算平均 FPS，低帧率时自动关闭 Glow，恢复后自动开启
--- ============================================================================

local Glow = require("fx.Glow")

local FPSMonitor = {}

-- ========== 配置 ==========
local SAMPLE_WINDOW    = 1.0   -- 滚动采样窗口（秒）
local DEGRADE_FPS      = 25    -- 低于此阈值触发降级
local RECOVER_FPS      = 35    -- 高于此阈值恢复
local DEGRADE_HOLD     = 2.0   -- 低帧持续多久才降级（秒）
local RECOVER_HOLD     = 3.0   -- 高帧持续多久才恢复（秒）

-- ========== 内部状态 ==========
local frameTimes = {}          -- 最近帧时间戳环形缓冲
local frameIdx   = 0
local MAX_SAMPLES = 120        -- 最多存储帧数
local totalDt    = 0           -- 窗口内总 dt
local sampleCount = 0

local avgFPS     = 60
local lowTimer   = 0           -- 连续低帧计时
local highTimer  = 0           -- 连续高帧计时
local degraded   = false       -- 当前是否已降级
local userGlow   = false       -- 降级前用户的 Glow 设置

--- 是否显示 FPS 计数器
FPSMonitor.showFPS = true

--- 每帧调用
---@param dt number 帧间隔
function FPSMonitor.Update(dt)
    -- 更新滚动窗口
    frameIdx = frameIdx + 1
    if frameIdx > MAX_SAMPLES then frameIdx = 1 end

    local oldDt = frameTimes[frameIdx] or 0
    frameTimes[frameIdx] = dt

    if sampleCount < MAX_SAMPLES then
        sampleCount = sampleCount + 1
        totalDt = totalDt + dt
    else
        totalDt = totalDt - oldDt + dt
    end

    -- 计算平均 FPS
    if totalDt > 0 and sampleCount > 0 then
        avgFPS = sampleCount / totalDt
    end

    -- 自动降级逻辑（仅当用户开启了 Glow 时才有意义）
    if avgFPS < DEGRADE_FPS then
        lowTimer = lowTimer + dt
        highTimer = 0
    elseif avgFPS > RECOVER_FPS then
        highTimer = highTimer + dt
        lowTimer = 0
    else
        -- 介于两个阈值之间：不改变状态，重置计时
        lowTimer = math.max(0, lowTimer - dt * 0.5)
        highTimer = math.max(0, highTimer - dt * 0.5)
    end

    -- 触发降级：连续低帧 > DEGRADE_HOLD 秒
    if not degraded and lowTimer >= DEGRADE_HOLD then
        if Glow.enabled then
            userGlow = true
            Glow.enabled = false
            degraded = true
            print("[FPSMonitor] Auto-degrade: Glow OFF (avg FPS: " .. math.floor(avgFPS) .. ")")
        end
        lowTimer = 0
    end

    -- 触发恢复：连续高帧 > RECOVER_HOLD 秒
    if degraded and highTimer >= RECOVER_HOLD then
        if userGlow then
            Glow.enabled = true
            print("[FPSMonitor] Auto-recover: Glow ON (avg FPS: " .. math.floor(avgFPS) .. ")")
        end
        degraded = false
        highTimer = 0
    end
end

--- 获取当前平均 FPS
---@return number
function FPSMonitor.GetFPS()
    return avgFPS
end

--- 是否处于降级状态
---@return boolean
function FPSMonitor.IsDegraded()
    return degraded
end

--- 渲染 FPS 计数器（右下角小字）
---@param vg userdata NanoVG 上下文
---@param viewW number 视口宽
---@param viewH number 视口高
---@param font number 字体 ID
function FPSMonitor.Render(vg, viewW, viewH, font)
    if not FPSMonitor.showFPS then return end

    local fps = math.floor(avgFPS + 0.5)
    local text = "FPS " .. fps

    -- 颜色根据帧率变化
    local r, g, b = 100, 255, 100  -- 绿色 = 正常
    if fps < DEGRADE_FPS then
        r, g, b = 255, 80, 80      -- 红色 = 低帧
    elseif fps < RECOVER_FPS then
        r, g, b = 255, 200, 60     -- 黄色 = 偏低
    end

    -- 降级指示
    if degraded then
        text = text .. " ▼"
    end

    local HUD = require("ui.HUD")
    local zpix = HUD.zpixFontId >= 0 and HUD.zpixFontId or font
    nvgFontFaceId(vg, zpix)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)

    -- 阴影
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgText(vg, viewW - 7, viewH - 7, text)
    -- 主体
    nvgFillColor(vg, nvgRGBA(r, g, b, 200))
    nvgText(vg, viewW - 8, viewH - 8, text)
    nvgFontFaceId(vg, font)
end

--- 重置状态（场景切换时调用）
function FPSMonitor.Reset()
    frameTimes = {}
    frameIdx = 0
    totalDt = 0
    sampleCount = 0
    avgFPS = 60
    lowTimer = 0
    highTimer = 0
    degraded = false
    userGlow = false
end

return FPSMonitor
